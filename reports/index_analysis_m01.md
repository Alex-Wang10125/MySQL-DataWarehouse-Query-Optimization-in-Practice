# TASK-02 索引影响分析: 模块1 — 索引失效诊断与修复

## 1. 索引清单

本模块创建了 6 个二级索引用于演示 5 种索引失效场景。索引均使用 BTREE，InnoDB 存储引擎。

| # | 表 | 索引名 | 列 | 类型 | 场景 |
|---|---|---|---|---|---|
| 1 | orders | idx_order_no | order_no VARCHAR(32) | BTREE, NOT NULL | 场景1: 隐式类型转换 |
| 2 | orders | idx_order_date | order_date DATETIME | BTREE, NOT NULL | 场景2: 函数包裹列 |
| 3 | products | idx_sku_code | sku_code VARCHAR(50) | BTREE, NOT NULL | 场景3: 覆盖索引 |
| 4 | orders | idx_payment_method | payment_method VARCHAR(20) | BTREE, NULLABLE | 场景4: 备用索引 |
| 5 | orders | idx_order_status | order_status VARCHAR(20) | BTREE, NULLABLE | 场景4: UNION ALL 分支 |
| 6 | customers | idx_city_regdate | city VARCHAR(50), register_date DATETIME | BTREE 复合 | 场景5: 最左前缀 |

## 2. 存储成本

| 表 | 原始数据 (MB) | 索引后总大小 (MB) | 索引增量 (MB) | 增幅 |
|---|---|---|---|---|
| orders | 142.69 | 269.49 | ~126.80 | +89% |
| products | 14.52 | 16.04 | ~1.52 | +10% |
| customers | 16.55 | 22.07 | ~5.52 | +33% |
| **合计** | **173.76** | **307.60** | **~133.84** | **+77%** |

> orders 表索引增量最大（127 MB），因为承载了 4 个二级索引 × 1M 行，每个二级索引存储 (索引列 + 主键 order_id BIGINT) 的完整副本。

### 逐索引存储估算

| 索引 | 键长度 (bytes) | 估算大小 (MB) | 说明 |
|---|---|---|---|
| idx_order_no | 32 (VARCHAR) + 8 (PK) ≈ 40 | ~42 | 高基数 (~990K)，接近唯一 |
| idx_order_date | 5 (DATETIME) + 8 (PK) ≈ 13 | ~22 | 高基数，覆盖全部日期范围 |
| idx_payment_method | ~20 (VARCHAR) + 8 (PK) ≈ 28 | ~28 | 低基数（仅 3 种支付方式） |
| idx_order_status | ~20 (VARCHAR) + 8 (PK) ≈ 28 | ~28 | 低基数（5 种状态 + 空字符串） |
| idx_sku_code | ~50 (VARCHAR) + 8 (PK) ≈ 58 | ~3.5 | 高基数 (~49K)，Covering Index |
| idx_city_regdate | ~50 (VARCHAR) + 5 (DATETIME) + 4 (PK INT) ≈ 59 | ~8.5 | 复合索引，两列 |

> 估算公式: `(平均键长 + 主键长) × 行数 × 1.4 (B+Tree 节点填充因子)`，实际大小受页分裂、碎片等因素影响。

## 3. 收益预评

### 场景1: 隐式类型转换 — idx_order_no

| 指标 | 优化前 | 优化后 |
|---|---|---|
| 访问类型 | ALL (全表扫描) | ref (索引查找) |
| 扫描行数 | 1,000,000 | 1 |
| 实际耗时 | 4,691 ms | 0.047 ms |
| 提升倍数 | — | **~100,000×** |

**收益:** 以 ~42 MB 存储换取点查从秒级降至微秒级。**该索引为核心业务索引，强烈建议保留。**

### 场景2: 函数包裹列 — idx_order_date

| 指标 | 优化前 | 优化后 |
|---|---|---|
| 访问类型 | ALL (全表扫描) | range (索引范围扫描) |
| 扫描行数 | 1,000,000 | 807 |
| 实际耗时 | 4,337 ms | 134 ms |
| 提升倍数 | — | **32× time, 1,200× rows** |

**收益:** 以 ~22 MB 存储换取日期范围查询 32× 加速。**日期范围查询是数仓核心场景，强烈建议保留。**

### 场景3: 覆盖索引 — idx_sku_code

| 指标 | 优化前 (SELECT *) | 优化后 (SELECT sku_code) |
|---|---|---|
| 访问类型 | ALL (全表扫描) | range (覆盖索引扫描) |
| 扫描行数 | 50,000 | 9,999 |
| 实际耗时 | 620 ms | 11.8 ms |
| 提升倍数 | — | **52×** |

**收益:** 以 ~3.5 MB 存储换取前缀搜索 52× 加速。覆盖索引避免了回表随机 I/O。**SKU 前缀搜索是常见需求，建议保留。**

### 场景4: OR + 函数 — idx_payment_method + idx_order_status

| 指标 | 优化前 (OR + DATE) | 优化后 (UNION ALL) |
|---|---|---|
| 访问类型 | ALL (全表扫描) | ref + range |
| 扫描行数 (估算) | 1,000,000 | 60,699 |
| 实际耗时 | 4,172 ms | 4,273 ms |
| 提升倍数 | — | **16× rows, 时间持平** |

**注意:** 时间改善不显著（4172ms → 4273ms），因为返回 3 万行时索引回表的随机 I/O 成本与全表顺序扫描相当。大数据量或低 buffer pool 命中率时差距会拉大。**这两个索引中低基数的 idx_payment_method（3个值，28MB）性价比极低，建议评估业务查询频率后决定去留。idx_order_status 可用于状态筛选，建议保留。**

### 场景5: 复合索引最左前缀 — idx_city_regdate

| 指标 | 优化前 | 优化后 |
|---|---|---|
| 访问类型 | ALL + filesort | range (覆盖排序) |
| 扫描行数 | 150,000 | 1,951 |
| 实际耗时 | 941 ms | 8.29 ms |
| 提升倍数 | — | **113×** |

**收益:** 以 ~8.5 MB 存储换取城市筛选+日期排序查询 113× 加速，同时消除 filesort。**城市维度的时序查询是数仓典型场景，强烈建议保留。**

## 4. 写入开销评估

| 表 | 写入频率 | 索引数 | 写入开销评级 | 说明 |
|---|---|---|---|---|
| orders | 高（订单持续写入） | 4 个二级索引 | **中-高** | 每次 INSERT 需更新 4 个 B+Tree，预计增加 ~160 bytes 写入量 |
| products | 低（产品变更少） | 1 个二级索引 | **低** | 每次 INSERT/UPDATE 多写一个索引页 |
| customers | 低-中（注册/更新） | 1 个复合索引 | **低-中** | 每次 INSERT/UPDATE 多写一个两列的复合索引页 |

> 评级假设: 该数仓为模拟环境，实际写入频率取决于业务。orders 表索引最多，写放大最显著。

## 5. 索引优化建议

### 建议保留（高性价比）
- **idx_order_no** — 点查场景，100,000× 提升，42 MB
- **idx_order_date** — 范围查询场景，32× 提升，22 MB
- **idx_sku_code** — 覆盖索引，52× 提升，3.5 MB
- **idx_city_regdate** — 最左前缀，113× 提升，8.5 MB

### 建议评估
- **idx_order_status** (28 MB) — 低基数 (5 个值)，仅当状态筛选是高频查询时保留。可考虑与 idx_order_date 合并为复合索引
- **idx_payment_method** (28 MB) — 极低基数 (3 个值)，28 MB 存储几乎无查询收益。除非经常作为 UNION ALL 分支使用，否则建议删除

### 优化动作
1. **合并索引**: `idx_order_status` + `idx_order_date` → `idx_status_date(order_status, order_date)` 复合索引（节省 ~28 MB 同时覆盖两个查询模式）
2. **删除 idx_payment_method** 除非有独立查询需求

## 6. 验证记录

所有 5 个场景的 EXPLAIN 和 EXPLAIN ANALYZE 已通过基准采集器验证。优化前后对比数据详见 `reports/m01_comparison.md`。

## 7. 回滚脚本

回滚脚本已生成至 `reports/rollback_idx.sql`，可一键删除本模块创建的所有二级索引。
