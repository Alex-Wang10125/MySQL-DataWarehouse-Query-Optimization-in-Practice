-- ============================================================
-- TASK-04 模块3: 深度分页与排序优化 — 问题 SQL
-- ============================================================
USE mysql_optimization_db;

-- 场景1: 大 OFFSET 扫描-丢弃
-- LIMIT 950000, 20 需要扫描 950,020 行，丢弃前 950,000 行
SELECT 'Scenario 1: Large OFFSET scan-and-discard' AS scenario;
EXPLAIN SELECT * FROM orders ORDER BY order_id LIMIT 950000, 20;

-- 场景2: FileSort — 排序列 total_amount 无索引
-- 大 OFFSET + 无索引排序 = 双重惩罚
SELECT 'Scenario 2: FileSort on unindexed column' AS scenario;
EXPLAIN SELECT * FROM orders ORDER BY total_amount DESC LIMIT 950000, 20;

-- 场景3: 延迟关联前 — SELECT * with large OFFSET on secondary index
-- idx_order_date 需回表读取完整行 → 扫描大量索引页 + 数据页
SELECT 'Scenario 3: Before deferred join' AS scenario;
EXPLAIN SELECT * FROM orders ORDER BY order_date LIMIT 950000, 20;

-- 场景4: JOIN + 大 OFFSET — 分页穿透 JOIN 的结果集
-- 扫描-丢弃后还要对每行做 JOIN 回表
SELECT 'Scenario 4: JOIN with large OFFSET' AS scenario;
EXPLAIN SELECT o.order_id, o.order_date, oi.product_id, oi.quantity
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
ORDER BY o.order_id LIMIT 950000, 20;
