-- ============================================================
-- TASK-04 模块3: 深度分页与排序优化 — 修复后 SQL
-- ============================================================
USE mysql_optimization_db;

-- 场景1 fix: 游标分页替代 OFFSET
-- WHERE order_id > last_seen_id 直接定位，无需扫描-丢弃
SELECT 'Fix 1: Cursor-based pagination' AS scenario;
EXPLAIN SELECT * FROM orders
WHERE order_id > 950000 ORDER BY order_id LIMIT 20;

-- 场景2 fix: 延迟关联 + idx_total_amount 覆盖索引
-- 子查询只扫索引页（覆盖索引），避免 filesort
SELECT 'Fix 2: Deferred join with total_amount index' AS scenario;
EXPLAIN SELECT o.* FROM orders o
JOIN (SELECT order_id FROM orders ORDER BY total_amount DESC LIMIT 950000, 20) t
ON o.order_id = t.order_id;

-- 场景3 fix: 延迟关联 + idx_order_date 覆盖索引
-- SELECT order_id 只走索引，不回表；外层仅 20 次 eq_ref
SELECT 'Fix 3: Deferred join with order_date index' AS scenario;
EXPLAIN SELECT o.* FROM orders o
JOIN (SELECT order_id FROM orders ORDER BY order_date LIMIT 950000, 20) t
ON o.order_id = t.order_id;

-- 场景4 fix: 游标分页穿透 JOIN
-- WHERE + ORDER BY 先定位 orders，再 via ref JOIN order_items
SELECT 'Fix 4: Cursor pagination through JOIN' AS scenario;
EXPLAIN SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_id > 950000
ORDER BY o.order_id LIMIT 20;
