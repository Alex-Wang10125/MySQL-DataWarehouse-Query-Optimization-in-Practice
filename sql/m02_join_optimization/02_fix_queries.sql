-- ============================================================
-- TASK-03 模块2: 大表 JOIN 策略优化 — 修复后 SQL
-- ============================================================
USE mysql_optimization_db;

-- 场景1 fix: 创建 idx_oi_order_id 后，orders 作为驱动表，order_items 走 ref
-- NLJ 替代 Hash Join，驱动表仅 810 行
SELECT 'Fix 1: NLJ with JOIN key index' AS scenario;
EXPLAIN SELECT COUNT(*)
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_date >= '2026-05-01' AND o.order_date < '2026-05-02';

-- 场景2 fix: 两个 JOIN 键索引 + customer_id 索引 → 驱动表缩小到 27 行
SELECT 'Fix 2: Three-table NLJ chain with indexes' AS scenario;
EXPLAIN SELECT o.order_id, oi.product_id, oi.quantity, p.product_name
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE o.customer_id = 1;

-- 场景3 fix: 创建 idx_orders_customer_id 后，Hash Join 变为 NLJ ref
-- 小表(customers 150K) 驱动大表(orders 1M)，通过索引精准命中
SELECT 'Fix 3a: STRAIGHT_JOIN large drives small (with index)' AS scenario;
EXPLAIN SELECT STRAIGHT_JOIN COUNT(*)
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id;

SELECT 'Fix 3b: STRAIGHT_JOIN small drives large (with index, Hash Join → ref)' AS scenario;
EXPLAIN SELECT STRAIGHT_JOIN COUNT(*)
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id;

-- 场景4 fix: 复合效果 — customer_id 索引缩小驱动表 + order_id 索引加速 JOIN
SELECT 'Fix 4: Indexed driver reduces from 1.25M to 27 rows' AS scenario;
EXPLAIN SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.customer_id = 1;
