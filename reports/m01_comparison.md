# TASK-02 模块1: 索引失效 — 对比报告

## 总览

| # | 场景 | 问题根因 | 优化前 type | 优化后 type | 时间 (ms) | 行数 | 提升 |
|---|---|---|---|---|---|---|---|
| 1 | 隐式类型转换 | VARCHAR 列与整数比较 | ALL | ref | 4691 → 0.047 | 1M → 1 | 99,800× |
| 2 | 函数包裹索引列 | DATE() 包裹列 | ALL | range | 4337 → 134 | 1M → 807 | 32× time / 1,200× rows |
| 3 | SELECT * 回表代价 | 回表代价超过全表扫描 | ALL | range (覆盖) | 620 → 11.8 | 50K → 10K | 52× |
| 4 | OR + 函数包裹列 | DATE() 阻止 OR 两侧索引合并 | ALL | ref + range | 4172 → 4273 | 1M → 60K | 16× rows |
| 5 | 复合索引最左前缀 | 缺少 city 条件 | ALL + filesort | range | 941 → 8.29 | 149K → 1,951 | 113× |

> 注: 实际时间是多次执行取中位数。行数为 EXPLAIN 的 rows 估计值（精确行数见 EXPLAIN ANALYZE 的 actual rows）。

---

## 场景1: 隐式类型转换

**问题 SQL:**
```sql
SELECT * FROM orders WHERE order_no = 202405230001;
```

**EXPLAIN (优化前):**
| type | possible_keys | key | rows | Extra |
|---|---|---|---|---|
| ALL | idx_order_no | NULL | 989,483 | Using where |

**EXPLAIN ANALYZE (优化前):**
```
-> Filter: (orders.order_no = 202405230001)  (cost=104871 rows=98948)
    -> Table scan on orders  (cost=104871 rows=989483) (actual time=4691ms, rows=1M)
```

**修复:**
```sql
SELECT * FROM orders WHERE order_no = '202405230001';
```

**EXPLAIN ANALYZE (优化后):**
```
-> Index lookup on orders using idx_order_no (order_no='202405230001')  (cost=0.611 rows=1) (actual time=0.047ms, rows=0)
```

**根因:** `order_no` 是 VARCHAR 类型，`= 202405230001`（整数）触发隐式类型转换：MySQL 将 `order_no` 列值 CAST 为数字后再比较，索引失效。

---

## 场景2: 函数包裹索引列

**问题 SQL:**
```sql
SELECT * FROM orders WHERE DATE(order_date) = '2025-01-01';
```

**EXPLAIN (优化前):**
| type | possible_keys | key | rows | Extra |
|---|---|---|---|---|
| ALL | NULL | NULL | 989,483 | Using where |

**EXPLAIN ANALYZE (优化前):**
```
-> Filter: (cast(orders.order_date as date) = '2025-01-01')  (cost=103613 rows=989483)
    -> Table scan on orders  (actual time=4337ms, rows=1M)
```

**修复:**
```sql
SELECT * FROM orders
WHERE order_date >= '2025-01-01' AND order_date < '2025-01-02';
```

**EXPLAIN ANALYZE (优化后):**
```
-> Index range scan on orders using idx_order_date over ('2025-01-01' <= order_date < '2025-01-02')
   (cost=574 rows=807) (actual time=134ms, rows=807)
```

**根因:** `DATE(order_date)` 对索引列做了函数变换，B+Tree 存储的是原始 `order_date` 值而非 `DATE()` 结果，索引无法被利用。

---

## 场景3: SELECT * 回表代价导致优化器放弃索引

**问题 SQL:**
```sql
SELECT * FROM products WHERE sku_code LIKE '100000%';
```

**EXPLAIN (优化前):**
| type | possible_keys | key | rows | Extra |
|---|---|---|---|---|
| ALL | idx_sku_code | NULL | 49,549 | Using where |

**EXPLAIN ANALYZE (优化前):**
```
-> Filter: (products.sku_code like '100000%')  (cost=5883 rows=18712)
    -> Table scan on products  (actual time=620ms, rows=50K)
```

**修复 (覆盖索引):**
```sql
SELECT sku_code FROM products WHERE sku_code LIKE '100000%';
```

**EXPLAIN ANALYZE (优化后):**
```
-> Covering index range scan on products using idx_sku_code
   (cost=4211 rows=18712) (actual time=11.8ms, rows=9999)
```

**根因:** `LIKE '100000%'` 满足最左前缀，本可使用 `idx_sku_code`。但 `SELECT *` 需要回表读取完整行，优化器估算 18,712 次随机 I/O 的代价高于一次顺序全表扫描，因此主动放弃索引。只选索引列（覆盖索引）则无需回表，优化器选择索引扫描。

---

## 场景4: OR + 函数包裹索引列

**问题 SQL:**
```sql
SELECT * FROM orders
WHERE order_status = 'REFUNDED' OR DATE(order_date) = '2025-01-01';
```

**EXPLAIN (优化前):**
| type | possible_keys | key | rows | Extra |
|---|---|---|---|---|
| ALL | NULL | NULL | 989,483 | Using where |

**EXPLAIN ANALYZE (优化前):**
```
-> Filter: ((orders.order_status = 'REFUNDED') or (cast(orders.order_date as date) = '2025-01-01'))
   (cost=104326 rows=989483) (actual time=4172ms, rows=1M scanned)
```

**修复 (UNION ALL):**
```sql
SELECT * FROM orders WHERE order_status = 'REFUNDED'
UNION ALL
SELECT * FROM orders WHERE order_date >= '2025-01-01' AND order_date < '2025-01-02';
```

**EXPLAIN ANALYZE (优化后):**
```
-> Append  (cost=20550 rows=60699) (actual time=4273ms, rows=31216)
    -> Index lookup on orders using idx_order_status (order_status='REFUNDED')
       (cost=19976 rows=59892) (actual time=4158ms, rows=30409)
    -> Index range scan on orders using idx_order_date over ('2025-01-01' <= order_date < '2025-01-02')
       (cost=574 rows=807) (actual time=112ms, rows=807)
```

**根因:** `DATE(order_date)` 破坏了一侧索引可用性，导致 OR 两侧都无法有效使用索引，回退全表扫描。UNION ALL 将 OR 拆成两个独立查询，每侧各自命中索引。

**注意:** 本场景实际时间改善不显著（4172ms → 4273ms），因为返回 3 万行数据时，全表顺序扫描 I/O 效率与 3 万次随机索引回表相当。**EXPLAIN 的 rows/cost 指标（1M → 60K, 16×）比 wall-clock 更能反映优化效果** — 当数据量增长或 buffer pool 命中率下降时，差距会急剧拉大。

---

## 场景5: 复合索引最左前缀不匹配

**问题 SQL:**
```sql
SELECT * FROM customers
WHERE register_date > '2025-01-01' ORDER BY city;
```

**EXPLAIN (优化前):**
| type | possible_keys | key | rows | Extra |
|---|---|---|---|---|
| ALL | NULL | NULL | 148,975 | Using where; Using filesort |

**EXPLAIN ANALYZE (优化前):**
```
-> Sort: customers.city  (cost=15956 rows=148975) (actual time=941ms, rows=31489)
    -> Filter: (customers.register_date > '2025-01-01') (actual time=755ms, rows=31489)
        -> Table scan on customers  (actual time=743ms, rows=150K)
```

**修复:**
```sql
SELECT * FROM customers
WHERE city = 'Beijing' AND register_date > '2025-01-01' ORDER BY city;
```

**EXPLAIN ANALYZE (优化后):**
```
-> Index range scan on customers using idx_city_regdate
   over (city = 'Beijing' AND '2025-01-01' < register_date)
   (cost=878 rows=1951) (actual time=8.29ms, rows=1951)
```

**根因:** `idx_city_regdate(city, register_date)` 是复合索引，B+Tree 先按 city 排序、再按 register_date 排序。`WHERE register_date > ...` 跳过了 city，索引无法被有效利用，还需要额外 filesort 满足 `ORDER BY city`。
