# MySQL 数仓查询优化实战 — 完整 PRD

## 1. 项目概要

| 项 | 内容 |
|---|---|
| 项目名称 | MySQL 数仓查询优化实战 |
| 目标 | 模拟电商数仓常见性能瓶颈，产出 6 个可量化、经得起深挖的优化案例 |
| 环境 | MySQL 8.4.8，Linux 本地单机，4C / 3.3GB RAM / 61GB 磁盘 |
| 数据量 | 约 2000 万行（跨 5 张表） |
| 核心约束 | 优化操作以 SQL 脚本为主；数据生成阶段可用 Python |

## 2. 数据模型（电商订单星型模型）

### 表结构与行数

```
customers (150 万行)
├── customer_id    BIGINT PK
├── customer_name  VARCHAR(100)
├── email          VARCHAR(200)        -- 含 NULL（脏数据）
├── phone          VARCHAR(20)         -- 含 NULL
├── register_date  DATETIME
├── customer_level VARCHAR(10)         -- 低基数：VIP/GOLD/SILVER/BRONZE
├── city           VARCHAR(50)
├── last_login     DATETIME            -- 含 NULL
└── status         TINYINT             -- 0/1

categories (500 行)
├── category_id    INT PK
├── category_name  VARCHAR(100)
└── parent_category_id INT

products (50 万行)
├── product_id     BIGINT PK
├── product_name   VARCHAR(200)
├── category_id    INT
├── price          DECIMAL(10,2)
├── cost           DECIMAL(10,2)
├── stock_quantity INT
├── sku_code       VARCHAR(50)         -- **故意用 VARCHAR，为隐式转换场景服务**
├── created_at     DATETIME
├── is_deleted     TINYINT DEFAULT 0
├── weight         DECIMAL(8,2)        -- 含 NULL
└── description    TEXT                -- 含 NULL

orders (800 万行)
├── order_id       BIGINT PK
├── order_no       VARCHAR(32)         -- **故意用 VARCHAR，为隐式转换场景服务**
├── customer_id    BIGINT
├── order_date     DATETIME
├── total_amount   DECIMAL(12,2)
├── discount_amount DECIMAL(10,2)
├── payment_method VARCHAR(20)         -- 低基数
├── order_status   VARCHAR(20)         -- 低基数，含脏数据
├── shipping_address VARCHAR(500)      -- 含 NULL
├── is_deleted     TINYINT DEFAULT 0
├── created_at     DATETIME
└── updated_at     DATETIME

order_items (1000 万行)
├── item_id        BIGINT PK
├── order_id       BIGINT
├── product_id     BIGINT
├── quantity       INT
├── unit_price     DECIMAL(10,2)
├── subtotal       DECIMAL(12,2)
├── product_name_snapshot VARCHAR(200)
└── created_at     DATETIME
```

**总行数 ≈ 2000 万行**，核心压力在 `orders`(800w) 和 `order_items`(1000w) 两张事实表。

### 数据特征（内建压力）

| 特征 | 目的 |
|---|---|
| `order_no`、`sku_code` 为 VARCHAR 但值全为数字 | 制造隐式类型转换陷阱 |
| 客户订单量呈幂律分布（20% 客户占 80% 订单） | 模拟数据倾斜 |
| 时间跨度 3 年 | 支持范围查询、分区演示 |
| 部分字段含 NULL | 模拟脏数据，演示 NULL 对索引/聚合的影响 |
| 低基数列（status/level/payment_method） | 演示索引选择性对执行计划的影响 |
| `order_items` 行数大于 `orders` | 模拟真实订单-明细关系 |
| `is_deleted` 标记删除 | 演示软删除对索引的污染 |

## 3. 六大性能优化模块

### 模块 1：索引失效诊断与修复

**问题场景**：
- `WHERE order_no = 202405230001` — 对 VARCHAR 列用整数比较，触发隐式类型转换，索引失效
- `WHERE DATE(order_date) = '2025-01-01'` — 函数包裹索引列
- `WHERE sku_code LIKE '%5678'` — 前置模糊导致索引失效
- 复合索引最左前缀不匹配
- OR 条件导致索引拆分

**涉及表**：orders、products
**预期优化幅度**：查询耗时降低 **100× ~ 10,000×**（全表扫描 → 索引查找）

**产出物**：
- 慢查询 SQL 集（5+ 条）
- EXPLAIN ANALYZE 对比（优化前后）
- 修复脚本（创建正确索引、改写 SQL）

---

### 模块 2：大表 JOIN 策略优化

**问题场景**：
- 多表 JOIN 时优化器选错驱动表，小表驱动大表 vs 大表驱动小表
- NLJ（Nested Loop Join）在缺索引时退化为 SNLJ（Simple Nested Loop Join），扫描量指数级膨胀
- 演示 MySQL 8.4 Hash Join 对等值 JOIN 的收益
- BNL（Block Nested Loop）的 Buffer 不足场景

**涉及表**：orders + order_items + customers + products
**预期优化幅度**：50× ~ 500×

**产出物**：
- 典型慢 JOIN SQL（3+ 条）
- 优化策略：索引创建、JOIN ORDER hint、STRAIGHT_JOIN
- 优化前后 EXPLAIN 对比

---

### 模块 3：深度分页与排序优化

**问题场景**：
- `LIMIT 1000000, 20` — 大 offset 导致 MySQL 扫描并丢弃前 100 万行
- FileSort 因排序列缺索引或索引覆盖不足
- COUNT(*) + LIMIT 组合的大数据量扫描

**涉及表**：orders、order_items
**预期优化幅度**：10× ~ 100×
**优化手段**：
- 延迟关联（Deferred Join）：先用覆盖索引定位主键，再回表
- 游标分页（Cursor-based Pagination）：`WHERE id > last_id ORDER BY id LIMIT 20`
- 覆盖索引消除回表

---

### 模块 4：锁竞争与死锁诊断

**问题场景**：
- 并发下单时，`SELECT ... FOR UPDATE` + INSERT 触发 Gap Lock 竞争
- 不同事务以不同顺序更新同一组行，导致死锁
- 长事务持有锁导致其他事务排队

**涉及表**：orders、order_items
**预期优化效果**：
- 死锁从"偶发"到"消除"
- 并发吞吐从 N tps 提升到 M tps

**产出物**：
- 并发压测脚本（Python/Shell）
- 死锁复现 → `SHOW ENGINE INNODB STATUS` 死锁日志解读
- 修复方案：调整索引以缩小锁范围、统一加锁顺序、拆分大事务
- 修复前后并发性能对比

---

### 模块 5：统计信息过期与执行计划漂移

**问题场景**：
- 大量 INSERT/DELETE 后未执行 `ANALYZE TABLE`，导致 `rows` 估算严重偏离实际
- InnoDB 统计信息抽样不准确（`innodb_stats_persistent` 参数影响）
- 直方图统计缺失导致 JOIN 顺序选择错误
- 优化器选择全表扫描而忽略索引

**涉及表**：orders、order_items
**预期优化幅度**：5× ~ 50×（错误的索引选择被纠正后）

**产出物**：
- 执行计划漂移复现脚本
- `ANALYZE TABLE` 修复前后对比
- Histogram 创建语句（`ANALYZE TABLE ... UPDATE HISTOGRAM`）
- 统计信息相关参数调优建议

---

### 模块 6：子查询改写优化

**问题场景**：
- `WHERE col IN (SELECT ...)` — 相关子查询退化为 DEPENDENT SUBQUERY，外层每行执行一次内层
- `NOT IN` + NULL 的三值逻辑陷阱
- 派生表（Derived Table）无索引导致物化后全表扫描
- MySQL 8.4 的 Semi-Join / Anti-Join 优化何时生效、何时绕过

**涉及表**：orders + order_items + customers
**预期优化幅度**：100× ~ 1000×

**产出物**：
- 低效子查询 SQL 集（5+ 条）
- 改写为 JOIN / EXISTS / 窗口函数的等价写法
- 优化前后 EXPLAIN 对比

---

## 4. 模块选择逻辑

6 个模块的筛选标准：

| 标准 | 说明 |
|---|---|
| **可量化** | 每个模块都有明确的"优化前耗时 → 优化后耗时"对比 |
| **面试可讲** | 覆盖索引原理、JOIN 算法、锁机制、统计信息、子查询优化 — 都是 Mentor 深挖的高频点 |
| **互相独立** | 每个模块有独立的 SQL 脚本集和验证标准，可单独演示 |
| **MySQL 8.4 特色** | Hash Join、直方图统计、Semi-Join 优化等新特性被充分利用 |

若后续发现某模块优化效果不显著（< 5× 提升），保留复现脚本作为"反模式文档"，仍具有教学价值。

## 5. 技术架构

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Python (Faker │ →  │   CSV Files  │ →  │  MySQL 8.4   │
│  + 随机数)    │    │   (中间层)    │    │  (目标)       │
└──────────────┘    └──────────────┘    └──────────────┘
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    ▼                         ▼                         ▼
              ┌──────────┐            ┌──────────────┐          ┌──────────────┐
              │ 模块 1-6  │            │ Benchmark    │          │   Results    │
              │ SQL 脚本  │            │ 自动化工具    │          │   归档       │
              └──────────┘            └──────────────┘          └──────────────┘
```

- **数据生成**：Python 脚本，输出 CSV → `LOAD DATA INFILE` 批量入库
- **性能测量**：每条 SQL 执行 3 次取中位数，使用 `EXPLAIN ANALYZE` 获取真实行数和耗时
- **结果记录**：每个模块一个 Markdown 报告，含 SQL、EXPLAIN 截图、耗时对比表

## 6. 验收标准

| 标准 | 指标 |
|---|---|
| 数据生成 | 5 张表均可正常导入，总行数约 2000 万，含预期脏数据 |
| 模块完成度 | 6/6 模块均完成 |
| 性能指标 | ≥ 5 个模块优化后提升 ≥ 10× |
| 可复现性 | 每个模块有独立执行脚本，可在干净环境一键重跑 |
| 文档完整性 | 每个模块有 EXPLAIN 对比、耗时对比表、优化原理简述 |

## 7. 风险与约束

| 风险 | 应对 |
|---|---|
| 4GB 内存不足以支撑 2000 万行全量扫描 | 控制单次查询扫描量，必要时适当降低总行数 |
| MySQL 查询缓存干扰 | `SQL_NO_CACHE` 或确保每次冷查询 |
| Buffer Pool 预热影响对比 | 每个查询执行 3 次：第1次暖 Buffer Pool(miss)，后 2 次作为对比 |
