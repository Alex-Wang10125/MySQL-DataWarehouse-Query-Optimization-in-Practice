# TASK-07 模块6: 子查询改写优化 — 对比报告

## 总览

| # | 场景 | 问题 | 修复前 | 修复后 | 改善 |
|---|---|---|---|---|---|
| 1 | IN + GROUP BY → DEPENDENT SUBQUERY | 150K 次相关子查询 | 2,175ms | 361ms | 6× |
| 2 | NOT IN + NULL 三值逻辑陷阱 | 返回 0 行（数据丢失） | cnt=0 | cnt=150,000 (正确) | 正确性修复 |
| 3 | 派生表物化无索引 | 外层全表扫描 992K 行 | <derived2> type=ALL | 单层查询, 无物化 | 消除临时表 |
| 4 | 双标量子查询 50K 行 | 每行执行 2 次子查询 | SUM 子查询 119s | 取决于改写策略 | 见下文 |

> 环境: MySQL 8.4, InnoDB, 1M orders / 150K customers

---

## 场景1: IN (SELECT ...) → DEPENDENT SUBQUERY

### 问题 SQL

```sql
SELECT customer_id, customer_name FROM customers c
WHERE customer_id IN (
    SELECT o.customer_id FROM orders o
    WHERE o.customer_id = c.customer_id
    GROUP BY o.customer_id
    HAVING COUNT(*) > 5
);
```

### EXPLAIN 对比

| 指标 | 问题 (DEPENDENT SUBQUERY) | 修复 (JOIN 派生表) |
|---|---|---|
| select_type | DEPENDENT SUBQUERY | DERIVED + SIMPLE |
| 外层扫描 | ALL on c (150K rows) | Materialize (127K groups → 30.9K after HAVING) |
| 内层执行次数 | 150,000 次 | 1 次 (一次性聚合) |
| 每次内层成本 | ~0.013ms (index lookup + GROUP BY + HAVING) | N/A |
| 实际时间 | **2,175ms** | **361ms** |

### 根因

`GROUP BY` + `HAVING` 引用外层列 → MySQL 无法转为 semi-join → 退化为 DEPENDENT SUBQUERY。每行外层都执行一次完整的: index lookup → GROUP BY 聚合 → HAVING 过滤。

### 修复

```sql
-- 预聚合派生表 + JOIN (只聚合一次)
SELECT c.customer_id, c.customer_name
FROM customers c
JOIN (
    SELECT customer_id, COUNT(*) AS cnt
    FROM orders
    GROUP BY customer_id
    HAVING COUNT(*) > 5
) heavy ON c.customer_id = heavy.customer_id;
```

### 关键洞察

子查询中的 GROUP BY/HAVING 是 semi-join 优化的主要障碍。当 GROUP BY 在外层与内层都出现时, MySQL 无法将 IN 子查询扁平化为 semi-join。解法: 将聚合提前到派生表或 CTE 中, 结果物化后再 JOIN。

---

## 场景2: NOT IN + NULL 三值逻辑陷阱

### 问题 SQL

```sql
-- 子查询含 NULL → NOT IN 永远返回空
SELECT COUNT(*) FROM customers
WHERE customer_id NOT IN (
    SELECT customer_id FROM orders WHERE order_date > '2026-06-01'
    UNION ALL
    SELECT NULL   -- 引入 NULL!
);
```

### 结果对比

| 查询 | 结果 | 说明 |
|---|---|---|
| NOT IN (含 NULL) | **0** | 三值逻辑: 任何值与 NULL 比较 = UNKNOWN |
| NOT IN (排除 NULL) | 150,000 | `AND customer_id IS NOT NULL` 排除 NULL |
| NOT EXISTS | 150,000 | EXISTS 本身 NULL 安全 |

### 根因

SQL 三值逻辑: `X NOT IN (1, 2, NULL)` 等价于 `X != 1 AND X != 2 AND X != NULL` → `X != NULL` 永远为 UNKNOWN → 整个 WHERE 为 UNKNOWN → 返回 0 行。

### 修复

```sql
-- 方案1: NOT EXISTS (推荐 — NULL 安全)
SELECT COUNT(*) FROM customers c
WHERE NOT EXISTS (
    SELECT 1 FROM orders o
    WHERE o.customer_id = c.customer_id AND o.order_date > '2026-06-01'
);

-- 方案2: LEFT JOIN / IS NULL (等价, 某些场景更优)
SELECT COUNT(*)
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.order_date > '2026-06-01'
WHERE o.order_id IS NULL;
```

---

## 场景3: 派生表物化后全表扫描

### 问题 SQL

```sql
SELECT c.customer_name, dt.order_cnt, dt.total_spent
FROM customers c
JOIN (
    SELECT customer_id, COUNT(*) AS order_cnt, SUM(total_amount) AS total_spent
    FROM orders GROUP BY customer_id
) dt ON c.customer_id = dt.customer_id
WHERE dt.total_spent > 5000;
```

### EXPLAIN 对比

| 步骤 | 问题 | 修复 |
|---|---|---|
| Step 1 | DERIVED: index scan orders (992K) → materialize | SIMPLE: scan orders (992K) + GROUP BY |
| Step 2 | PRIMARY: ALL on `<derived2>` (992K, no index!) | HAVING 过滤 + JOIN customers |
| Step 3 | eq_ref lookup on customers (per derived row) | N/A (单层) |

### 根因

派生表物化后是临时表, **没有索引**。外层对派生表的任何 JOIN/WHERE 都必须全表扫描。当派生表很大 (>100K 行) 时, 这成为瓶颈。

### 修复

```sql
-- HAVING 下推: 过滤在聚合层完成, 不需要派生表
SELECT c.customer_name, COUNT(*) AS order_cnt, SUM(o.total_amount) AS total_spent
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id
HAVING total_spent > 5000;

-- 或用 CTE (语义清晰, MySQL 8.0+)
WITH customer_summary AS (
    SELECT customer_id, COUNT(*) AS order_cnt, SUM(total_amount) AS total_spent
    FROM orders GROUP BY customer_id HAVING total_spent > 5000
)
SELECT c.customer_name, cs.order_cnt, cs.total_spent
FROM customers c JOIN customer_summary cs ON c.customer_id = cs.customer_id;
```

---

## 场景4: 标量子查询 vs JOIN/GROUP BY

### 问题 SQL (2 个标量子查询, 50K outer rows)

```sql
SELECT c.customer_id, c.customer_name,
    (SELECT COUNT(*) FROM orders o WHERE o.customer_id = c.customer_id) AS order_cnt,
    (SELECT COALESCE(SUM(total_amount), 0) FROM orders o WHERE o.customer_id = c.customer_id) AS total_spent
FROM customers c
WHERE c.customer_id <= 50000;
```

### 成本分析

| 指标 | COUNT 子查询 | SUM 子查询 | 说明 |
|---|---|---|---|
| 执行次数 | 50,000 | 50,000 | 每行各执行一次 |
| 每次成本 | ~0.049ms | ~2.38ms | COUNT 用 covering index, SUM 需回表 |
| 总成本 | ~2.4s | ~119s | SUM 慢 48× — **covering index 是关键** |
| 外层扫描 | 683ms | — | Index range scan on PRIMARY |

### 修复策略

| 策略 | 适用场景 | 说明 |
|---|---|---|
| LEFT JOIN + GROUP BY | 外层 < 5K 行 | 简单直接, 但会爆炸式扩大中间结果 |
| 预聚合派生表 + 过滤下推 | 外层 > 5K 行 | 聚合只发生在相关子集上 |
| 保持标量子查询 | COUNT/EXISTS 且 covering index | MySQL 8.4 对标量子查询优化较好 |
| 窗口函数 | 需要多种聚合且数据已 JOIN | OVER(PARTITION BY) 一次扫描完成 |

### 推荐修复 (带过滤下推的预聚合)

```sql
SELECT c.customer_id, c.customer_name,
    COALESCE(oa.order_cnt, 0) AS order_cnt,
    COALESCE(oa.total_spent, 0) AS total_spent
FROM customers c
LEFT JOIN (
    SELECT customer_id, COUNT(*) AS order_cnt, SUM(total_amount) AS total_spent
    FROM orders
    WHERE customer_id <= 50000    -- 过滤下推到派生表内!
    GROUP BY customer_id
) oa ON c.customer_id = oa.customer_id
WHERE c.customer_id <= 50000;
```

---

## 改写原则速查

| 原始模式 | 改写为 | 原因 |
|---|---|---|
| `IN (SELECT ...)` | `INNER JOIN` 或 `EXISTS` | semi-join 优化, 避免 DEPENDENT SUBQUERY |
| `NOT IN (SELECT ...)` | `NOT EXISTS` 或 `LEFT JOIN ... IS NULL` | NULL 安全, 性能更好 |
| `FROM (SELECT ...) dt` | CTE 或 HAVING 下推 | 派生表无索引, 避免外层全扫 |
| `SELECT ..., (SELECT ...)` | `LEFT JOIN + GROUP BY` 或预聚合派生表 | 避免 O(n×m) 逐行执行 |
| `WHERE col = (SELECT ...)` | `JOIN` 或 `EXISTS` | 标量子查询逐行, JOIN 批处理 |

### 关键洞察: 不是所有子查询都需要改写

MySQL 8.4 的优化器已能很好地处理:
- 简单 `IN (SELECT ...)` — 自动转 semi-join
- 简单标量子查询 (covering index) — 比 JOIN 更快 (避免中间结果膨胀)
- `EXISTS` 子查询 — 优化器自动转 semi-join

**真正需要改写的是**: DEPENDENT SUBQUERY (含 GROUP BY/聚合/外层引用), NOT IN, 大派生表, 多个标量子查询。
