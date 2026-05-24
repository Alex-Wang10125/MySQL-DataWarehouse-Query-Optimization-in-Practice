-- ============================================================
-- TASK-03 模块2: 大表 JOIN 策略优化 — 问题 SQL（缺索引）
-- ============================================================
USE mysql_optimization_db;

-- 场景1: Hash Join 兜底 — 有过滤条件但 JOIN 键缺索引
-- idx_order_date 可过滤 orders 到几十行，但 order_items.order_id 无索引 → 被迫 Hash Join
SELECT 'Scenario 1: Hash Join fallback without JOIN key index' AS scenario;
EXPLAIN SELECT COUNT(*)
FROM orders o
INNER JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_date = '2026-05-15';

-- 场景2: 三表 JOIN 链式缺索引 — 中间表全扫
-- 两个 JOIN 键 (order_id, product_id) 均无索引
SELECT 'Scenario 2: Three-table JOIN without indexes' AS scenario;
EXPLAIN SELECT o.order_id, oi.product_id, oi.quantity, p.product_name
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE o.customer_id = 1;

-- 场景3: STRAIGHT_JOIN 驱动表顺序对比
-- 3a: 大表(1M)驱动小表(150K) vs 3b: 小表驱动大表
-- orders.customer_id 无索引 → Hash Join
SELECT 'Scenario 3a: STRAIGHT_JOIN large drives small' AS scenario;
EXPLAIN SELECT STRAIGHT_JOIN COUNT(*)
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id;

SELECT 'Scenario 3b: STRAIGHT_JOIN small drives large' AS scenario;
EXPLAIN SELECT STRAIGHT_JOIN COUNT(*)
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id;

-- 场景4: 选择性过滤 + JOIN 缺索引 — MySQL 被迫全扫大表
-- customer_id=1 只有 27 个订单，但 order_items.order_id 无索引 → 必须先全扫 order_items
SELECT 'Scenario 4: Selective filter + no JOIN key index' AS scenario;
EXPLAIN SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.customer_id = 1;
