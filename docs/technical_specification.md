# 技术规格文档

## 1. MySQL 配置要求

### 1.1 必要参数确认

```sql
-- 检查并设置隔离级别
SELECT @@transaction_isolation;  -- 期望: REPEATABLE-READ (默认)

-- 确认 performance_schema 启用
SHOW VARIABLES LIKE 'performance_schema';  -- 期望: ON

-- 锁监控 (模块4需要)
SET GLOBAL innodb_status_output = ON;
SET GLOBAL innodb_status_output_locks = ON;

-- 统计信息持久化 (模块5需要)
SET GLOBAL innodb_stats_persistent = ON;
SET GLOBAL innodb_stats_auto_recalc = ON;
```

### 1.2 Buffer Pool 配置

当前 3.3GB RAM，建议 `innodb_buffer_pool_size = 1.5G`（约50%内存），确保数据不能全部驻留内存，制造真实的磁盘 I/O 压力。

```sql
-- 查看当前配置
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';
-- 调整 (如有权限)
-- SET GLOBAL innodb_buffer_pool_size = 1610612736;  -- 1.5G
```

### 1.3 慢查询日志

```sql
SET GLOBAL slow_query_log = ON;
SET GLOBAL long_query_time = 0.1;  -- 100ms 以上就记录
SET GLOBAL log_queries_not_using_indexes = ON;
```

## 2. 数据生成规格

### 2.1 通用参数

| 参数 | 值 | 说明 |
|---|---|---|
| 批次大小 | 100,000 行/批 | LOAD DATA INFILE 批量提交 |
| 编码 | UTF-8 | 所有 CSV 文件 |
| 日期范围 | 2023-01-01 ~ 2026-05-24 | 约 3 年 |
| NULL 分隔符 | `\N` | MySQL 标准 NULL 表示 |

### 2.2 各表生成规则

#### customers (1,500,000 行)

| 列 | 生成规则 | 压力特征 |
|---|---|---|
| customer_id | 自增 BIGINT | — |
| customer_name | Faker name | — |
| email | Faker email，5% 概率为 NULL | NULL 值 |
| phone | Faker phone，15% 概率为 NULL | NULL 值 |
| register_date | 2020-01-01 ~ 2026-05-01 随机 | 范围查询 |
| customer_level | 权重: BRONZE 50%, SILVER 30%, GOLD 15%, VIP 5% | **数据倾斜** |
| city | 从 200 个城市中随机（幂律分布：前 10 个城市占 60%） | **数据倾斜** |
| last_login | register_date 后 1~365 天，30% 概率为 NULL | NULL 值 |
| status | 95% 为 1（活跃），5% 为 0（禁用） | 低基数 |

#### categories (500 行)

| 列 | 生成规则 |
|---|---|
| category_id | 自增 INT |
| category_name | 预定义 20 个一级类目 + 480 个二级/三级类目 |
| parent_category_id | 指向父类目，NULL 表示一级类目 |

#### products (500,000 行)

| 列 | 生成规则 | 压力特征 |
|---|---|---|
| product_id | 自增 BIGINT | — |
| product_name | 类目前缀 + 随机后缀 | — |
| category_id | 1~500 随机，80% 集中在 50 个热门类目 | **数据倾斜** |
| price | 对数正态分布，均值 200，范围 1~50000 | — |
| cost | price 的 40%~80% | — |
| stock_quantity | 0~10000 随机 | — |
| sku_code | **纯数字字符串 "1000000000"~"1000500000"** | **隐式转换陷阱** |
| created_at | 2021-01-01 ~ 2025-12-31 随机 | — |
| is_deleted | 97% 为 0，3% 为 1 | 低基数索引污染 |
| weight | 0.01~50.00，20% 概率为 NULL | NULL 值 |
| description | Faker text(100~500 chars)，40% 概率为 NULL | 含 TEXT，NULL值|

#### orders (8,000,000 行)

| 列 | 生成规则 | 压力特征 |
|---|---|---|
| order_id | 自增 BIGINT | — |
| order_no | **日期+序号纯数字字符串 "202405230001"** | **隐式转换陷阱** |
| customer_id | 1~1,500,000，**幂律分布：20% 客户占 80% 订单** | **严重数据倾斜** |
| order_date | 2023-01-01 ~ 2026-05-24 随机 | 范围查询场景 |
| total_amount | order_items 汇总（生成时先算） | — |
| discount_amount | total_amount 的 0%~30%，80% 为 0 | 低基数 |
| payment_method | 权重: ALIPAY 40%, WECHAT 35%, CARD 15%, COD 10% | 低基数 |
| order_status | COMPLETED 65%, PENDING 15%, SHIPPED 10%, CANCELLED 5%, REFUNDED 3%, **空字符串 1%, NULL 1%** | **脏数据** |
| shipping_address | Faker address，0.5% 概率为 NULL | NULL 值 |
| is_deleted | 98% 为 0，2% 为 1 | 索引污染 |
| created_at | order_date 同时间 | — |
| updated_at | created_at + 0~30 天随机，10% 概率 > created_at | — |

#### order_items (10,000,000 行)

| 列 | 生成规则 | 压力特征 |
|---|---|---|
| item_id | 自增 BIGINT | — |
| order_id | 1~8,000,000，**每个订单 1~5 个明细项**（泊松分布，均值 1.25） | — |
| product_id | 1~500,000，**幂律：5% 商品占 50% 订单行** | **数据倾斜** |
| quantity | 1~10，指数衰减分布 | — |
| unit_price | 从对应 product 的 price 快照 | — |
| subtotal | quantity × unit_price | — |
| product_name_snapshot | 从对应 product 的 product_name 快照 | — |
| created_at | 对应 order 的 created_at | — |

### 2.3 数据倾斜配置汇总

| 表 | 列 | 倾斜描述 |
|---|---|---|
| customers | customer_level | VIP 仅 5% |
| customers | city | 前 10 城市占 60% |
| products | category_id | 80% 集中在 50 个热门类目 |
| products | sku_code | 纯数字 VARCHAR，为隐式转换埋伏笔 |
| orders | customer_id | **20% 客户占 80% 订单** |
| orders | order_no | 纯数字 VARCHAR，为隐式转换埋伏笔 |
| orders | order_status | 空字符串/NULL 脏数据 |
| order_items | product_id | **5% 商品占 50% 订单行** |

## 3. 基准测试方法

### 3.1 执行规范

每条 SQL 执行 3 次，记录每次耗时，取中位数作为对比值：

```
第 1 次: Buffer Pool 冷/热混合 → 用于预热，不计入统计
第 2 次: 热执行 → 记录
第 3 次: 热执行 → 记录
最终耗时 = (第2次 + 第3次) / 2
```

### 3.2 采集指标

| 指标 | 获取方式 |
|---|---|
| 执行耗时 (秒) | `time` 命令 real time |
| 扫描行数 | `EXPLAIN ANALYZE` 中 `rows` 字段 |
| 访问类型 | `EXPLAIN` 中 `type` 列 |
| Extra 信息 | `EXPLAIN` 中 `Extra` 列 (Using filesort/Using temporary) |
| Buffer Pool 命中率 | `SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read%'` |
| 磁盘读取量 | `Innodb_pages_read` 前后差值 |

### 3.3 对比报告模板

每个模块产出 `reports/mXX_comparison.md`：

```markdown
| 指标 | 优化前 | 优化后 | 提升倍数 |
|---|---|---|---|
| 平均耗时 | X.XXs | Y.YYs | XX× |
| 扫描行数 | X,XXX,XXX | Y,YYY | — |
| 访问类型 | ALL | ref | — |
| Extra | Using filesort | — | — |
```

## 4. 模块技术规格

### 模块 1：索引失效诊断与修复

**问题 SQL（5+ 条）**：

| # | SQL 模式 | 失效原因 | 预期扫描量 |
|---|---|---|---|
| 1.1 | `WHERE order_no = 202405230001` | 隐式类型转换 (VARCHAR vs INT) | 全表 800w |
| 1.2 | `WHERE DATE(order_date) = '2025-01-01'` | 函数包裹索引列 | 全表 800w |
| 1.3 | `WHERE sku_code LIKE '%5678'` | LIKE 前置模糊 | 全表 50w |
| 1.4 | `WHERE a = 1 OR b = 2` (无复合索引) | OR 条件拆分索引 | 范围扩大 |
| 1.5 | `WHERE city = '杭州' ORDER BY register_date` | 复合索引最左前缀不匹配 | FileSort |

**修复方案**：
- 1.1: 改写为 `order_no = '202405230001'` 或创建正确的 VARCHAR 索引
- 1.2: 使用范围条件 `order_date >= '2025-01-01' AND order_date < '2025-01-02'` 或创建函数索引 (MySQL 8.0.13+)
- 1.3: 创建全文索引或调整为后缀匹配需求
- 1.4: 创建复合索引
- 1.5: 创建 `(city, register_date)` 复合索引

### 模块 2：大表 JOIN 策略优化

**问题 SQL**：

| # | SQL 模式 | 问题 |
|---|---|---|
| 2.1 | orders JOIN order_items ON order_id，无 WHERE 条件缩小范围 | NLJ 在大表间狂扫 |
| 2.2 | orders JOIN customers ON customer_id，orders 为驱动表 | 大表驱动大表 |
| 2.3 | 三表 JOIN，优化器选错 JOIN 顺序 | 缺少统计信息导致错误选择 |

**MySQL 8.4 特性使用**：Hash Join 自动启用（等值 JOIN），对比 NLJ vs Hash Join 计划差异。

### 模块 3：深度分页与排序优化

**问题 SQL**：

| # | SQL 模式 | 问题 |
|---|---|---|
| 3.1 | `SELECT * FROM orders ORDER BY order_date LIMIT 2000000, 20` | 扫描并丢弃 200 万行 |
| 3.2 | `SELECT * FROM orders ORDER BY total_amount LIMIT 1000000, 20` | 排序列无索引，FileSort + 大 offset |
| 3.3 | 分页 + COUNT(*) 联用 | 两次大表扫描 |

### 模块 4：锁竞争与死锁诊断

**场景设计**：

| # | 场景 | 锁类型 |
|---|---|---|
| 4.1 | 并发 INSERT 到 orders，二级唯一索引冲突 | Gap Lock + Insert Intention Lock 冲突 |
| 4.2 | 两事务以不同顺序 UPDATE 同一组 order 行 | 死锁 (AB-BA) |
| 4.3 | 长事务 SELECT ... FOR UPDATE + 其他事务等待 | 行锁等待超时 |

**并发参数**：10 线程，每线程 100 次操作。

### 模块 5：统计信息过期与执行计划漂移

**场景设计**：

| # | 场景 | 机制 |
|---|---|---|
| 5.1 | 新增 100 万行后不 ANALYZE，执行计划仍使用旧统计 | rows 估算大幅偏离 |
| 5.2 | 删除 50 万行后，索引选择错误 | innodb_stats_persistent 样本不更新 |
| 5.3 | JOIN 列无直方图，优化器选错 JOIN 顺序 | 等值 JOIN 估算不准 |

### 模块 6：子查询改写优化

**问题 SQL**：

| # | SQL 模式 | 问题 |
|---|---|---|
| 6.1 | `WHERE customer_id IN (SELECT customer_id FROM orders WHERE ...)` | 相关子查询退化为 DEPENDENT SUBQUERY |
| 6.2 | `WHERE order_id NOT IN (SELECT order_id FROM refunds)` | NOT IN + NULL 三值逻辑陷阱 |
| 6.3 | 派生表子查询无物化索引 | 派生表被物化后全表扫描 |
| 6.4 | `SELECT (SELECT COUNT(*) FROM order_items WHERE ...) FROM orders` | 标量子查询逐行执行 |

## 5. 开发环境

| 项 | 值 |
|---|---|
| Python 虚拟环境 | `source ~/agent_env/bin/activate` |
| MySQL 用户 | `alex@localhost` / `alex_mysql_2024` |
| root 连接 | `echo "317307834" \| sudo -S mysql` |

## 6. 风险缓解

| 风险 | 缓解措施 |
|---|---|
| 数据生成时间过长 | 使用 LOAD DATA INFILE 批量导入，不用逐行 INSERT |
| 4GB 内存 OOM | 单次查询控制扫描范围，大 offset 测试使用 LIMIT 限制回表行数 |
| 锁测试影响数据一致性 | 模块 4 使用独立测试表或事务回滚 |
| 磁盘不足 | CSV 文件生成一张导一张，导入后清理 |
