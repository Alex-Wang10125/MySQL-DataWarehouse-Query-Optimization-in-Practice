-- ============================================================
-- TASK-07 模块6: 子查询改写优化
-- 02_fix_queries.sql — JOIN / EXISTS / NOT EXISTS / GROUP BY 改写
-- ============================================================

-- ============================================================
-- 场景1 修复: 派生表预聚合 + JOIN 替代 DEPENDENT SUBQUERY
-- ============================================================
-- 思路: 将 GROUP BY/HAVING 从子查询中提出来, 作为派生表物化一次,
--       然后用 JOIN 关联, 避免 150K 次重复聚合

-- 1.1 修复后 EXPLAIN
EXPLAIN SELECT c.customer_id, c.customer_name
FROM customers c
JOIN (
    SELECT customer_id, COUNT(*) AS cnt
    FROM orders
    GROUP BY customer_id
    HAVING COUNT(*) > 5
) heavy ON c.customer_id = heavy.customer_id;
-- 预期: 不再有 DEPENDENT SUBQUERY
--       一次 GROUP BY 聚合 (1M 行), materialize 派生表 (30K 行), JOIN

-- 1.2 修复后实际执行时间 (约 360ms vs 2.2s)
EXPLAIN ANALYZE SELECT c.customer_id, c.customer_name
FROM customers c
JOIN (
    SELECT customer_id, COUNT(*) AS cnt
    FROM orders
    GROUP BY customer_id
    HAVING COUNT(*) > 5
) heavy ON c.customer_id = heavy.customer_id\G

-- 1.3 CTE 写法 (MySQL 8.0+, 语义更清晰)
WITH heavy_customers AS (
    SELECT customer_id, COUNT(*) AS cnt
    FROM orders
    GROUP BY customer_id
    HAVING COUNT(*) > 5
)
SELECT c.customer_id, c.customer_name
FROM customers c
JOIN heavy_customers h ON c.customer_id = h.customer_id;

-- ============================================================
-- 场景2 修复: NOT EXISTS 替代 NOT IN (NULL 安全)
-- ============================================================

-- 2.1 NOT EXISTS — NULL 安全的三值逻辑
SELECT COUNT(*) AS cnt FROM customers c
WHERE NOT EXISTS (
    SELECT 1 FROM orders o
    WHERE o.customer_id = c.customer_id
      AND o.order_date > '2026-06-01'
    UNION ALL
    SELECT 1 FROM DUAL WHERE NULL  -- NULL 不会破坏 EXISTS
);
-- 预期: 结果正确 (不受 NULL 影响)

-- 2.2 LEFT JOIN / IS NULL — 等价改写, 有时性能更好
SELECT COUNT(*) AS cnt
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.order_date > '2026-06-01'
WHERE o.order_id IS NULL;

-- 2.3 实际生产写法: 找出无订单客户
-- NOT IN 版本 (有陷阱):
-- SELECT * FROM customers WHERE customer_id NOT IN (SELECT customer_id FROM orders);

-- NOT EXISTS 版本 (推荐):
-- SELECT * FROM customers c WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);

-- LEFT JOIN / IS NULL 版本:
-- SELECT c.* FROM customers c LEFT JOIN orders o ON c.customer_id = o.customer_id WHERE o.order_id IS NULL;

-- ============================================================
-- 场景3 修复: HAVING 下推 + CTE 避免派生表物化
-- ============================================================

-- 3.1 HAVING 下推 — 过滤在聚合层完成, 无需外包派生表
SELECT c.customer_name, COUNT(*) AS order_cnt, SUM(o.total_amount) AS total_spent
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id
HAVING total_spent > 5000;
-- 预期: 单层查询, 无派生表物化

-- 3.2 CTE 改写 — 适合复杂场景 (MySQL 8.0+)
WITH customer_summary AS (
    SELECT customer_id, COUNT(*) AS order_cnt, SUM(total_amount) AS total_spent
    FROM orders
    GROUP BY customer_id
    HAVING total_spent > 5000
)
SELECT c.customer_name, cs.order_cnt, cs.total_spent
FROM customers c
JOIN customer_summary cs ON c.customer_id = cs.customer_id;
-- 注意: MySQL CTE 仍然物化, 但语义清晰, 且只物化过滤后的小结果集

-- ============================================================
-- 场景4 修复: LEFT JOIN + GROUP BY 替代标量子查询
-- ============================================================

-- 4.1 LEFT JOIN + GROUP BY — 一次扫描完成所有聚合
EXPLAIN SELECT c.customer_id, c.customer_name,
    COUNT(o.order_id) AS order_cnt,
    COALESCE(SUM(o.total_amount), 0) AS total_spent
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE c.customer_id <= 50000
GROUP BY c.customer_id;
-- 预期: 只扫描一次 orders 表, 无 DEPENDENT SUBQUERY

-- 4.2 修复后执行时间
EXPLAIN ANALYZE SELECT c.customer_id, c.customer_name,
    COUNT(o.order_id) AS order_cnt,
    COALESCE(SUM(o.total_amount), 0) AS total_spent
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE c.customer_id <= 50000
GROUP BY c.customer_id\G

-- 4.3 使用 Derived Table 预聚合 + JOIN (数据量大时更优)
SELECT c.customer_id, c.customer_name,
    COALESCE(oa.order_cnt, 0) AS order_cnt,
    COALESCE(oa.total_spent, 0) AS total_spent
FROM customers c
LEFT JOIN (
    SELECT customer_id, COUNT(*) AS order_cnt, SUM(total_amount) AS total_spent
    FROM orders
    WHERE customer_id <= 50000
    GROUP BY customer_id
) oa ON c.customer_id = oa.customer_id
WHERE c.customer_id <= 50000;
-- 预期: orders 表聚合一次 (不是每行), 结果集小, JOIN 高效

-- ============================================================
-- 改写原则总结
-- ============================================================
-- 1. IN (SELECT ...)   → 优先 INNER JOIN 或 EXISTS
-- 2. NOT IN (SELECT ..) → 优先 NOT EXISTS 或 LEFT JOIN ... IS NULL
-- 3. 派生表 (FROM subquery) → 考虑 CTE 或 HAVING 下推
-- 4. 标量子查询 (SELECT 子句)  → LEFT JOIN + GROUP BY 或预聚合派生表
