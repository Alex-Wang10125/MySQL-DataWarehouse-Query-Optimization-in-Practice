-- ============================================================
-- TASK-07 模块6: 子查询改写优化
-- 01_problem_queries.sql — 4 种低效子查询模式
-- ============================================================

-- ============================================================
-- 场景1: IN (SELECT ...) 退化为 DEPENDENT SUBQUERY
-- ============================================================
-- 当子查询含 GROUP BY / HAVING 且引用外层列时,
-- MySQL 无法将其转为 semi-join, 退化为逐行执行

-- 1.1 查看执行计划 — 关注 select_type = DEPENDENT SUBQUERY
EXPLAIN SELECT customer_id, customer_name FROM customers c
WHERE customer_id IN (
    SELECT o.customer_id FROM orders o
    WHERE o.customer_id = c.customer_id
    GROUP BY o.customer_id
    HAVING COUNT(*) > 5
);
-- 预期: select_type=2 DEPENDENT SUBQUERY
--       150,000 外层行 × 7 内层行 = ~1M 次索引查找

-- 1.2 实际执行时间 (约 2.2s)
EXPLAIN ANALYZE SELECT customer_id, customer_name FROM customers c
WHERE customer_id IN (
    SELECT o.customer_id FROM orders o
    WHERE o.customer_id = c.customer_id
    GROUP BY o.customer_id
    HAVING COUNT(*) > 5
)\G

-- ============================================================
-- 场景2: NOT IN + NULL 三值逻辑陷阱
-- ============================================================

-- 2.1 NOT IN 子查询含 NULL → 返回 0 行
SELECT COUNT(*) AS cnt FROM customers
WHERE customer_id NOT IN (
    SELECT customer_id FROM orders WHERE order_date > '2026-06-01'
    UNION ALL
    SELECT NULL   -- 故意引入 NULL
);
-- 预期: cnt = 0 (三值逻辑导致整个 NOT IN 为 UNKNOWN)

-- 2.2 NOT IN 排除 NULL → 结果正确
SELECT COUNT(*) AS cnt FROM customers
WHERE customer_id NOT IN (
    SELECT customer_id FROM orders WHERE order_date > '2026-06-01'
      AND customer_id IS NOT NULL
);

-- 2.3 实际场景: 找出没有订单的客户 (子查询可能有 NULL)
SELECT COUNT(*) AS cnt FROM customers c
WHERE c.customer_id NOT IN (
    SELECT o.customer_id FROM orders o WHERE o.total_amount < 0
    -- 如果 orders.customer_id 允许 NULL, 这里有陷阱
);

-- ============================================================
-- 场景3: 派生表物化后无索引 → 全表扫描
-- ============================================================

-- 3.1 派生表 JOIN — 派生表无索引, 外层全扫
EXPLAIN SELECT c.customer_name, dt.order_cnt, dt.total_spent
FROM customers c
JOIN (
    SELECT customer_id, COUNT(*) AS order_cnt, SUM(total_amount) AS total_spent
    FROM orders
    GROUP BY customer_id
) dt ON c.customer_id = dt.customer_id
WHERE dt.total_spent > 5000;
-- 预期: <derived2> 行 type=ALL, rows=992K, 无可用索引

-- 3.2 多层派生表嵌套 — 每层都物化
EXPLAIN SELECT * FROM (
    SELECT customer_id, order_cnt FROM (
        SELECT customer_id, COUNT(*) AS order_cnt
        FROM orders GROUP BY customer_id
    ) t1 WHERE order_cnt > 3
) t2 WHERE order_cnt < 10;
-- 预期: 多层 MATERIALIZED, 每层全表扫描

-- ============================================================
-- 场景4: 标量子查询逐行执行
-- ============================================================

-- 4.1 SELECT 子句中的标量子查询 — 每行执行一次
EXPLAIN SELECT c.customer_id, c.customer_name,
    (SELECT COUNT(*) FROM orders o WHERE o.customer_id = c.customer_id) AS order_cnt,
    (SELECT COALESCE(SUM(total_amount), 0) FROM orders o WHERE o.customer_id = c.customer_id) AS total_spent
FROM customers c
WHERE c.customer_id <= 50000;
-- 预期: 2 个 DEPENDENT SUBQUERY, 各执行 N 次 (N=外查询行数)
--       select_type = DEPENDENT SUBQUERY
--       N=50000 时, 2×50000 = 100,000 次子查询执行

-- 4.2 WHERE 子句中的标量子查询 — 同样逐行
EXPLAIN SELECT customer_id, customer_name FROM customers c
WHERE (
    SELECT COUNT(*) FROM orders o WHERE o.customer_id = c.customer_id
) > 3;
-- 预期: DEPENDENT SUBQUERY, 50000 次执行
