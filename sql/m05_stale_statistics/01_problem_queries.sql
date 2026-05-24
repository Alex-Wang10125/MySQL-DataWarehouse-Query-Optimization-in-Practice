-- ============================================================
-- TASK-06 模块5: 统计信息过期与执行计划漂移
-- 01_problem_queries.sql — 统计信息过期导致的问题 SQL
-- ============================================================

-- 准备: 创建测试表并禁用自动统计更新
DROP TABLE IF EXISTS orders_stats_test;
CREATE TABLE orders_stats_test LIKE orders;
INSERT INTO orders_stats_test
SELECT * FROM orders WHERE order_date >= '2025-06-01' LIMIT 10000;
ALTER TABLE orders_stats_test STATS_AUTO_RECALC = 0;

-- ============================================================
-- 场景1: INSERT 大量数据后不 ANALYZE → rows 估算严重偏低
-- ============================================================

-- 1.1 查看初始统计信息 (TABLE_ROWS ≈ 5,000)
SELECT TABLE_NAME, TABLE_ROWS, AVG_ROW_LENGTH, DATA_LENGTH
FROM information_schema.TABLES
WHERE table_name = 'orders_stats_test';

-- 1.2 插入 50,000 行
INSERT INTO orders_stats_test (customer_id, order_date, order_status, payment_method, total_amount, order_no, shipping_address, discount_amount, created_at)
SELECT
    FLOOR(1 + RAND() * 150000) AS customer_id,
    '2026-01-01' + INTERVAL FLOOR(RAND() * 180) DAY AS order_date,
    ELT(FLOOR(1 + RAND() * 4), 'PENDING', 'PAID', 'SHIPPED', 'REFUNDED') AS order_status,
    ELT(FLOOR(1 + RAND() * 3), 'ALIPAY', 'WECHAT', 'CARD') AS payment_method,
    ROUND(10 + RAND() * 9990, 2) AS total_amount,
    CONCAT('ORD', LPAD(FLOOR(RAND() * 999999999999), 12, '0')) AS order_no,
    CONCAT('Address ', FLOOR(RAND() * 10000)) AS shipping_address,
    ROUND(RAND() * 100, 2) AS discount_amount,
    NOW() - INTERVAL FLOOR(RAND() * 365) DAY AS created_at
FROM orders
LIMIT 50000;

-- 1.3 查看过期统计信息 — TABLE_ROWS 仍为 5,000
SELECT TABLE_NAME, TABLE_ROWS
FROM information_schema.TABLES
WHERE table_name = 'orders_stats_test';
-- 预期: TABLE_ROWS ≈ 5,000, 实际行数 60,000 (低估 12×)

-- 1.4 查看实际行数
SELECT COUNT(*) AS actual_rows FROM orders_stats_test;

-- 1.5 使用过期统计信息的 EXPLAIN — rows 估算不准
EXPLAIN SELECT * FROM orders_stats_test WHERE order_status = 'PENDING';
EXPLAIN SELECT * FROM orders_stats_test WHERE payment_method = 'ALIPAY';

-- ============================================================
-- 场景2: DELETE 大量行后索引 cardinality 不更新
-- ============================================================

-- 2.1 查看删除前索引基数
SHOW INDEX FROM orders_stats_test WHERE Key_name = 'idx_order_status';

-- 2.2 删除 PENDING 和 REFUNDED 状态的所有行 (约 50% 数据)
DELETE FROM orders_stats_test WHERE order_status IN ('PENDING', 'REFUNDED');

-- 2.3 删除后索引基数未变化 (STATS_AUTO_RECALC=0)
SHOW INDEX FROM orders_stats_test WHERE Key_name = 'idx_order_status';
-- 预期: Cardinality 仍为旧值

-- 2.4 EXPLAIN 使用过期的基数估算 — 估算 15,000 行实际为 0
EXPLAIN SELECT * FROM orders_stats_test WHERE order_status = 'PENDING';
-- 预期: rows 仍显示约 15,000, 但实际 PENDING 行数为 0

-- 2.5 验证实际行数
SELECT COUNT(*) FROM orders_stats_test WHERE order_status = 'PENDING';

-- ============================================================
-- 场景3: 无直方图时 JOIN 列范围估算偏差
-- ============================================================

-- 3.1 查看 customer_id 数据倾斜
SELECT
    CASE WHEN cnt >= 10 THEN 'heavy(>=10)' WHEN cnt >= 3 THEN 'medium(3-9)' ELSE 'light(1-2)' END AS type,
    COUNT(*) AS customer_count
FROM (SELECT customer_id, COUNT(*) AS cnt FROM orders GROUP BY customer_id) t
GROUP BY type;

-- 3.2 无直方图 — 对范围查询使用均分假设
EXPLAIN SELECT o.order_id, o.order_date, c.customer_name
FROM orders o JOIN customers c ON o.customer_id = c.customer_id
WHERE o.customer_id BETWEEN 1 AND 100;
-- 预期: 每 customer 估算 7 行 (avg), 无法感知 heavy/light 差异

-- 3.3 无直方图 — 对具体 ID 使用 index dive (较准)
EXPLAIN SELECT o.order_id, c.customer_name
FROM orders o JOIN customers c ON o.customer_id = c.customer_id
WHERE o.customer_id IN (1, 13677, 26443, 50000);
-- IN 列表可能退化为均分假设 (eq_range_index_dive_limit)

-- ============================================================
-- 清理
-- ============================================================
DROP TABLE IF EXISTS orders_stats_test;
