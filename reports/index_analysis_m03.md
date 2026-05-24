# TASK-04 索引影响分析: 模块3 — 深度分页与排序优化

## 1. 索引清单

本模块新增 1 个二级索引：

| # | 表 | 索引名 | 列 | 基数 | 用途 |
|---|---|---|---|---|---|
| 1 | orders | idx_total_amount | total_amount DECIMAL(12,2) | ~990K | S2: FileSort → 覆盖索引扫描 |

## 2. 存储成本

| 索引 | 键长度 (bytes) | 估算大小 (MB) |
|---|---|---|
| idx_total_amount | 6 (DECIMAL 12,2) + 8 (PK BIGINT) = 14 | ~19 MB |

> 估算: 14 bytes × 1M rows × 1.4 = ~19 MB

## 3. 收益预评

| 场景 | 优化前 | 优化后 | 提升 |
|---|---|---|---|
| S2: FileSort + 大OFFSET | 6208ms (全扫+filesort) | 1045ms (覆盖索引+延迟关联) | 5.9× |

**关键发现:** 单独创建 idx_total_amount 不足以让 MySQL 直接使用 — `SELECT * FROM orders ORDER BY total_amount DESC LIMIT 950000, 20` 在有索引的情况下仍显示 ALL+filesort。原因是 950K 次回表代价在 MySQL 成本模型中高于一次全扫+排序。索引必须配合延迟关联使用才生效。

## 4. 写入开销

| 表 | 累计索引数 | 新增 | 写入评级 |
|---|---|---|---|
| orders | 6 (PRIMARY + 4个TASK-02 + 1个TASK-03 + 1个本模块) | idx_total_amount | 中 |

> orders 已有 5 个二级索引, 新增 1 个对每次 INSERT/UPDATE 增加 ~14 bytes 写入量。

## 5. 结论

- **idx_total_amount 单独使用效果有限** — 需配合延迟关联才能发挥价值
- **性价比中等** — 19 MB 换取 5.9× 提升, 不如游标分页显著
- **建议保留** — 金额排序是常见业务需求, 且后续模块可能复用
