# TASK-03 模块2: 大表 JOIN 策略优化 — 对比报告

## 总览

| # | 场景 | 问题根因 | 优化前 type | 优化后 type | 时间 (ms) | 驱动行数 | 提升 |
|---|---|---|---|---|---|---|---|
| 1 | Hash Join 兜底 | JOIN 键缺索引 → 全扫 1.25M + Hash Join | ALL + Hash Join | range + ref | 9884 → 257 | 1.25M → 810 | **38×** |
| 2 | 三表 JOIN 链式缺索引 | 中间表无索引 → 级联 1.25M 全扫 | ALL × 3 | ref + ref + eq_ref | 14271 → 67 | 1.25M → 27 | **212×** |
| 3 | 驱动表顺序错误 | 小表驱动大表无索引 → Hash Join | index + ALL(Hash) | index + ref | 4854 → 1222 | 1M(Hash) → 7/lookup | **4×** |
| 4 | 选择性过滤 + JOIN 缺索引 | 过滤条件无法缩小 JOIN 扫描范围 | ALL + eq_ref | ref + ref | 7908 → 77 | 1.25M → 27 | **102×** |

> 实际时间为 EXPLAIN ANALYZE 单次执行结果。涉及表规模: orders(~1M), order_items(~1.25M), customers(~150K), products(~49K)

---

## 场景1: Hash Join 兜底 — 有过滤但 JOIN 键无索引

**问题 SQL:**
```sql
SELECT COUNT(*)
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_date >= '2026-05-01' AND o.order_date < '2026-05-02';
```

**EXPLAIN (优化前):**
| table | type | key | rows | Extra |
|---|---|---|---|---|
| oi | ALL | NULL | 1,244,740 | NULL |
| o | eq_ref | PRIMARY | 1 | Using where |

**EXPLAIN ANALYZE (优化前):**
```
-> Nested loop inner join  (actual time=9884ms, rows=976 loops=1)
    -> Table scan on oi  (actual time=4524ms, rows=1.25M)
    -> Filter: (order_date in range) rows=1 (actual time=0.004ms/loop × 1.25M)
        -> Single-row index lookup on o using PRIMARY
```
- 全扫 order_items (1.25M) → 每行查 orders PRIMARY → 过滤日期
- 只有 976 行匹配日期，但必须扫描全部 1.25M 行

**修复（创建 `idx_oi_order_id` 后）:**
```sql
-- 索引创建:
CREATE INDEX idx_oi_order_id ON order_items(order_id);
-- 查询不变
```

**EXPLAIN ANALYZE (优化后):**
```
-> Nested loop inner join  (actual time=257ms, rows=976 loops=1)
    -> Covering index range scan on o using idx_order_date (rows=810, time=1.08ms)
    -> Covering index lookup on oi using idx_oi_order_id (time=0.311ms/loop × 810)
```
- orders 通过 idx_order_date 范围扫描 → 810 行
- 每行通过 idx_oi_order_id 精准命中 order_items → 总计 976 行
- **驱动表从 1.25M 缩减到 810 行**

**提升: 9884ms → 257ms (38×)**

---

## 场景2: 三表 JOIN 链式缺索引 — 中间表无索引引发级联全扫

**问题 SQL:**
```sql
SELECT o.order_id, oi.product_id, oi.quantity, p.product_name
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE o.customer_id = 1;
```

**EXPLAIN (优化前):**
| table | type | key | rows | Extra |
|---|---|---|---|---|
| oi | ALL | NULL | 1,244,740 | NULL |
| p | eq_ref | PRIMARY | 1 | NULL |
| o | eq_ref | PRIMARY | 1 | Using where |

**EXPLAIN ANALYZE (优化前):**
```
-> Nested loop inner join  (actual time=14271ms, rows=31 loops=1)
    -> Nested loop inner join  (actual time=9184ms, rows=1.25M loops=1)
        -> Table scan on oi  (actual time=4652ms, rows=1.25M)
        -> Single-row index lookup on p using PRIMARY (1.25M times)
    -> Filter: o.customer_id = 1  (0.004ms × 1.25M = 4875ms)
        -> Single-row index lookup on o using PRIMARY (1.25M times)
```
- MySQL 选择 order_items 作为驱动表（无 JOIN 键可用）
- 1.25M 行 → 查 products PRIMARY（1.25M 次）→ 查 orders PRIMARY + 过滤 customer_id（1.25M 次）
- 最终只有 31 行匹配 customer_id=1
- **14.3 秒找出 31 行 — 每行代价 460ms**

**修复（创建 3 个 JOIN 键索引后）:**
```sql
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_oi_order_id ON order_items(order_id);
CREATE INDEX idx_oi_product_id ON order_items(product_id);
-- 查询不变
```

**EXPLAIN ANALYZE (优化后):**
```
-> Nested loop inner join  (actual time=67.3ms, rows=31 loops=1)
    -> Nested loop inner join  (actual time=30.6ms, rows=31 loops=1)
        -> Covering index lookup on o using idx_orders_customer_id (customer_id=1)
           (rows=27, time=0.09ms)
        -> Index lookup on oi using idx_oi_order_id (1.13ms × 27 = 30ms)
    -> Single-row index lookup on p using PRIMARY (1.18ms × 31 = 37ms)
```
- 驱动表变为 orders，通过 idx_orders_customer_id 精准定位 27 行
- order_items 通过 idx_oi_order_id ref 查找（共 31 行）
- products 通过 PRIMARY eq_ref 查找

**提升: 14271ms → 67.3ms (212×)**

---

## 场景3: STRAIGHT_JOIN — 驱动表顺序的影响

### 3a: 大表驱动小表 (orders→customers)

| 指标 | 优化前 | 优化后 |
|---|---|---|
| EXPLAIN type | o: ALL, c: eq_ref | o: index(idx_customer_id), c: eq_ref |
| 实际耗时 | 8718ms | 2808ms |
| 驱动行数 | 1M (table scan) | 1M (index scan) |

### 3b: 小表驱动大表 (customers→orders)

| 指标 | 优化前 | 优化后 |
|---|---|---|
| EXPLAIN type | c: index, o: ALL + Hash Join | c: index, o: ref(idx_customer_id) |
| 实际耗时 | 4854ms | 1222ms |
| 驱动行数 | 150K + 1M Hash Join | 150K × 7 (ref per row) |

**关键对比:**
- 3a: 大表驱动，NLJ 效率依赖 probed 表有 PRIMARY（eq_ref），`idx_orders_customer_id` 使扫描从 ALL→index，提升 3.1×
- 3b: 小表驱动，无索引时 MySQL 被迫 Hash Join；有 `idx_orders_customer_id` 后变为 ref 精准查找，消除 Hash Join，提升 4×
- **3b 的修复效果更显著**（Hash Join → ref），说明 MySQL 8.4 的 Hash Join 是"兜底"而非"最优" — NLJ + 合适索引仍然更优

**提升: 3a 3.1× | 3b 4× | 正确驱动顺序 (3b) vs 错误 (3a): 1222ms vs 2808ms (2.3×)**

---

## 场景4: 选择性过滤 + JOIN — 最经典的索引收益

**问题 SQL:**
```sql
SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.customer_id = 1;
```

**EXPLAIN (优化前):**
| table | type | key | rows |
|---|---|---|---|
| oi | ALL | NULL | 1,244,740 |
| o | eq_ref | PRIMARY | 1 |

- 驱动表 order_items — 1.25M 全扫
- 每行查 orders PRIMARY，再过滤 customer_id=1
- 只有 27 个订单属于该客户 → **全扫 1.25M 行只为了找 31 行**

**EXPLAIN ANALYZE (优化前):** 7908ms (7.9s)

**EXPLAIN (优化后):**
| table | type | key | rows |
|---|---|---|---|
| o | ref | idx_orders_customer_id | 27 |
| oi | ref | idx_oi_order_id | 1 |

- 驱动表 orders，通过 idx_orders_customer_id → 27 行
- 每行通过 idx_oi_order_id 查 order_items → ref 精准命中

**EXPLAIN ANALYZE (优化后):** 77.4ms

**提升: 7908ms → 77.4ms (102×)**

---

## 索引创建清单

| 索引 | 表 | 列 | 用途 |
|---|---|---|---|
| idx_oi_order_id | order_items | order_id | orders↔order_items JOIN |
| idx_oi_product_id | order_items | product_id | order_items↔products JOIN |
| idx_orders_customer_id | orders | customer_id | customers↔orders JOIN |

## 核心结论

1. **JOIN 键必须建索引** — 缺索引时 MySQL 8.4 用 Hash Join 兜底，但仍是全表扫描成本；NLJ + ref 索引查找比 Hash Join 更高效
2. **驱动表大小决定 JOIN 性能** — WHERE 过滤条件配合索引可将驱动表从百万级缩至十行级
3. **STRAIGHT_JOIN 是诊断工具，非日常方案** — 正确创建索引后，优化器通常能自行选择最优 JOIN 顺序
4. **多表 JOIN 的索引需求是级联的** — 每增加一个无索引的 JOIN 键，扫描行数指数级膨胀
