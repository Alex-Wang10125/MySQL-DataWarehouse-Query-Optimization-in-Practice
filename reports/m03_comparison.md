# TASK-04 模块3: 深度分页与排序优化 — 对比报告

## 总览

| # | 场景 | 问题根因 | 优化前 | 优化后 | 时间 (ms) | 扫描行数 | 提升 |
|---|---|---|---|---|---|---|---|
| 1 | 大 OFFSET 扫描-丢弃 | `LIMIT 950000, 20` 逐行扫描 PRIMARY 索引 | index scan 950K | range 定位 20 | 4704 → 0.079 | 950K → 20 | **59,544×** |
| 2 | FileSort + 大 OFFSET | total_amount 无索引 + 大 OFFSET | ALL+filesort | 覆盖索引+延迟关联 | 6208 → 1045 | 1M → 950K(idx) | **5.9×** |
| 3 | SELECT * 回表 + OFFSET | 950K 次回表 vs 全扫+排序 | ALL+filesort | 覆盖索引+延迟关联 | 6056 → 1394 | 1M → 950K(idx) | **4.3×** |
| 4 | JOIN + 大 OFFSET | 950K 次索引查找 + NLJ | index scan + ref × 760K | range + ref × 17 | 9682 → 0.23 | 1.7M → 37 | **42,650×** |

> 数据规模: orders(1M), order_items(1.25M)。OFFSET=950000 代表"最后一页附近"的极端场景。

---

## 场景1: 大 OFFSET 扫描-丢弃 → 游标分页

**问题 SQL:**
```sql
SELECT * FROM orders ORDER BY order_id LIMIT 950000, 20;
```

**EXPLAIN (优化前):**
| type | key | rows | Extra |
|---|---|---|---|
| index | PRIMARY | 950,020 | NULL |

**EXPLAIN ANALYZE (优化前):**
```
-> Limit/Offset: 20/950000 row(s)  (actual time=4704ms)
    -> Index scan on orders using PRIMARY  (rows=950020, time=4662ms)
```
- 从 order_id=1 开始逐行扫描 PRIMARY 索引，扫描 950,020 行
- 丢弃前 950,000 行，返回最后 20 行

**修复:**
```sql
SELECT * FROM orders
WHERE order_id > 950000 ORDER BY order_id LIMIT 20;
```

**EXPLAIN ANALYZE (优化后):**
```
-> Index range scan on orders using PRIMARY over (950000 < order_id)
   (rows=20, time=0.075ms)
```

**提升: 4704ms → 0.079ms (59,544×)**

---

## 场景2: FileSort 无索引排序 → 延迟关联 + 索引

**问题 SQL:**
```sql
SELECT * FROM orders ORDER BY total_amount DESC LIMIT 950000, 20;
```

**EXPLAIN (优化前):**
| type | key | rows | Extra |
|---|---|---|---|
| ALL | NULL | 990,392 | Using filesort |

**EXPLAIN ANALYZE (优化前):**
```
-> Sort: total_amount DESC, limit 950020 rows (time=6176ms)
    -> Table scan on orders  (rows=1M, time=4833ms)
```

**修复:**
```sql
CREATE INDEX idx_total_amount ON orders(total_amount);

SELECT o.* FROM orders o
JOIN (SELECT order_id FROM orders ORDER BY total_amount DESC LIMIT 950000, 20) t
ON o.order_id = t.order_id;
```

**EXPLAIN ANALYZE (优化后):**
```
-> Nested loop inner join  (time=1045ms)
    -> Covering index scan on orders using idx_total_amount (reverse)
       (rows=950020, time=1007ms)
    -> Single-row index lookup on o using PRIMARY (×20, time=0.286ms each)
```

**提升: 6208ms → 1045ms (5.9×)**

---

## 场景3: 延迟关联 (Deferred Join)

**问题 SQL:**
```sql
SELECT * FROM orders ORDER BY order_date LIMIT 950000, 20;
```

**EXPLAIN (优化前):**
| type | key | rows | Extra |
|---|---|---|---|
| ALL | NULL | 990,392 | Using filesort |

**EXPLAIN ANALYZE (优化前):**
```
-> Sort: orders.order_date, limit 950020 rows (time=6029ms)
    -> Table scan on orders  (rows=1M, time=4944ms)
```

**修复 (延迟关联):**
```sql
SELECT o.* FROM orders o
JOIN (SELECT order_id FROM orders ORDER BY order_date LIMIT 950000, 20) t
ON o.order_id = t.order_id;
```

**EXPLAIN ANALYZE (优化后):**
```
-> Nested loop inner join  (time=1394ms)
    -> Covering index scan on orders using idx_order_date (rows=950020, time=1328ms)
    -> Single-row index lookup on o using PRIMARY (×20, time=1.76ms each)
```

**提升: 6056ms → 1394ms (4.3×)**

---

## 场景4: JOIN + 大 OFFSET → 游标分页

**问题 SQL:**
```sql
SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
ORDER BY o.order_id LIMIT 950000, 20;
```

**EXPLAIN (优化前):**
| table | type | key | rows |
|---|---|---|---|
| o | index | PRIMARY | 760,870 |
| oi | ref | idx_oi_order_id | 1 |

**EXPLAIN ANALYZE (优化前):**
```
-> Nested loop inner join  (time=9682ms, rows=950020)
    -> Index scan on o using PRIMARY  (rows=760110, time=2697ms)
    -> Index lookup on oi using idx_oi_order_id (0.0089ms × 760110)
```

**修复 (游标分页):**
```sql
SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_id > 950000
ORDER BY o.order_id LIMIT 20;
```

**EXPLAIN ANALYZE (优化后):**
```
-> Nested loop inner join  (time=0.23ms, rows=20)
    -> Index range scan on o using PRIMARY (rows=17, time=0.15ms)
    -> Index lookup on oi using idx_oi_order_id (0.0042ms × 17)
```

**提升: 9682ms → 0.23ms (42,650×)**

---

## 优化策略对比

| 策略 | 适用场景 | 原理 | 本模块场景 |
|---|---|---|---|
| 游标分页 | 排序键单调递增 (PRIMARY/时间) | `WHERE id > last_id` 直接 seek 定位 | S1, S4 |
| 延迟关联 | 任何可建索引的排序列 | 子查询仅选 PK 走覆盖索引, 外层少量回表 | S2, S3 |
| 覆盖索引 | 查询列均在索引中 | 消除回表, 索引页密度高 | S2 子查询, S3 子查询 |

## 核心结论

1. **`LIMIT N, M` 的性能与 N 成正比** — 每多 1 行 OFFSET, 就多 1 行被扫描-丢弃
2. **游标分页是深分页的最优解** — WHERE id > last_id 将 O(N+M) 降为 O(M)
3. **延迟关联 = 缩小回表范围** — 将 SELECT * 的 N+M 次回表压缩为"索引扫描 + M 次回表"
4. **索引不能解决 OFFSET 问题** — S2 即便建了索引, MySQL 仍选全扫+排序, 延迟关联是让索引起作用的桥梁
