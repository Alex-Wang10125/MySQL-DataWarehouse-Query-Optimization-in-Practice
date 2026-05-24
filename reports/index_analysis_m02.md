# TASK-03 索引影响分析: 模块2 — 大表 JOIN 策略优化

## 1. 索引清单

本模块创建了 3 个二级索引用于 JOIN 键加速：

| # | 表 | 索引名 | 列 | 基数 | 场景 |
|---|---|---|---|---|---|
| 1 | order_items | idx_oi_order_id | order_id | ~1M | S1, S2, S4: orders↔order_items JOIN |
| 2 | order_items | idx_oi_product_id | product_id | ~49K | S2: order_items↔products JOIN |
| 3 | orders | idx_orders_customer_id | customer_id | ~125K | S2, S3, S4: customers↔orders JOIN |

## 2. 存储成本

| 索引 | 表行数 | 键长度 (bytes) | 估算大小 (MB) |
|---|---|---|---|
| idx_oi_order_id | 1,244,740 | 8 (BIGINT FK) + 8 (BIGINT PK) = 16 | ~27 |
| idx_oi_product_id | 1,244,740 | 8 (BIGINT FK) + 8 (BIGINT PK) = 16 | ~27 |
| idx_orders_customer_id | 990,392 | 8 (BIGINT FK) + 8 (BIGINT PK) = 16 | ~22 |
| **合计** | — | — | **~76 MB** |

> 估算: (16 bytes/entry × rows × 1.4 B+Tree 填充因子)。大表 JOIN 键索引成本集中在 order_items 表（每表 ~54 MB）。

## 3. 收益预评

| 场景 | 优化前耗时 | 优化后耗时 | 提升 | 驱动行数变化 |
|---|---|---|---|---|
| S1: Hash Join→NLJ | 9,884 ms | 257 ms | 38× | 1.25M → 810 |
| S2: 三表级联 | 14,271 ms | 67 ms | 212× | 1.25M → 27 |
| S3: 驱动表 Hash Join→ref | 4,854 ms | 1,222 ms | 4× | 1M Hash → 7×150K ref |
| S4: 选择性过滤+JOIN | 7,908 ms | 77 ms | 102× | 1.25M → 27 |

## 4. 写入开销

| 表 | 已有索引(含TASK-02) | 新增 | 总计 | 写入评级 |
|---|---|---|---|---|
| order_items | PRIMARY | 2 | 3 | **中** — 每次 INSERT 多写 2 个 B+Tree (~32 bytes/行) |
| orders | PRIMARY + 4 | 1 | 6 | **中-高** — 每次 INSERT 多写 1 个 B+Tree (~16 bytes/行) |

> rating assumes simulated environment with moderate write frequency

## 5. 结论

- **这 3 个 JOIN 键索引是模块 2 的核心依赖** — 没有它们，orders↔order_items JOIN 必须全扫 1.25M 行作为驱动
- **性价比极高**: 以 ~76 MB 存储换取 4 个核心 JOIN 查询 4× ~ 212× 加速
- **建议永久保留** — 后续模块（深度分页、子查询改写）也会依赖这些 JOIN 键索引
- idx_oi_product_id 当前仅用于 S2 三表 JOIN，但后续模块（深度分页、子查询）同样需要
