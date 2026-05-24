-- ============================================================
-- TASK-06 模块5: 统计信息过期与执行计划漂移
-- 02_fix_queries.sql — ANALYZE TABLE + 直方图修复
-- ============================================================

-- ============================================================
-- 场景1 修复: ANALYZE TABLE 刷新统计信息
-- ============================================================

-- 1.1 执行统计信息更新
ANALYZE TABLE orders_stats_test;

-- 1.2 验证统计信息已更新
SELECT TABLE_NAME, TABLE_ROWS
FROM information_schema.TABLES
WHERE table_name = 'orders_stats_test';
-- 预期: TABLE_ROWS ≈ 60,000 (与实际行数一致)

-- 1.3 修复后 EXPLAIN — rows 估算准确
EXPLAIN SELECT * FROM orders_stats_test WHERE order_status = 'PENDING';
-- 预期: rows 反映真实数据分布

-- ============================================================
-- 场景2 修复: ANALYZE TABLE 更新索引基数
-- ============================================================

-- 2.1 执行 ANALYZE
ANALYZE TABLE orders_stats_test;

-- 2.2 验证索引基数已更新
SHOW INDEX FROM orders_stats_test WHERE Key_name = 'idx_order_status';
-- 预期: Cardinality 从 6 降至 3 (只剩 2 种 status)

-- 2.3 修复后 EXPLAIN — rows 估算合理
EXPLAIN SELECT * FROM orders_stats_test WHERE order_status = 'PENDING';
-- 预期: rows 接近 0 (实际 PENDING 行已被全部删除)

-- ============================================================
-- 场景3 修复: 创建直方图改善 JOIN 列范围估算
-- ============================================================

-- 3.1 在 JOIN 键上创建直方图
ANALYZE TABLE orders UPDATE HISTOGRAM ON customer_id WITH 100 BUCKETS;

-- 3.2 验证直方图已创建
SELECT TABLE_NAME, COLUMN_NAME,
       JSON_EXTRACT(HISTOGRAM, '$.number-of-buckets-specified') AS buckets
FROM information_schema.column_statistics
WHERE table_name = 'orders' AND column_name = 'customer_id';

-- 3.3 修复后 EXPLAIN — 范围查询估算更精确
EXPLAIN SELECT o.order_id, o.order_date, c.customer_name
FROM orders o JOIN customers c ON o.customer_id = c.customer_id
WHERE o.customer_id BETWEEN 1 AND 100;
-- 预期: 使用直方图感知数据倾斜, 估算更接近真实分布

-- 3.4 修复后 — IN 列表不再受 eq_range_index_dive_limit 限制
EXPLAIN SELECT o.order_id, c.customer_name
FROM orders o JOIN customers c ON o.customer_id = c.customer_id
WHERE o.customer_id IN (1, 13677, 26443, 50000);

-- ============================================================
-- 额外: 生产环境预防措施
-- ============================================================

-- 4.1 开启自动统计更新 (默认开启)
ALTER TABLE orders_stats_test STATS_AUTO_RECALC = 1;

-- 4.2 查看统计自动更新阈值 (10% 行变更触发)
SELECT TABLE_NAME, STATS_AUTO_RECALC, STATS_PERSISTENT, STATS_SAMPLE_PAGES
FROM information_schema.TABLES
WHERE table_name = 'orders_stats_test';

-- 4.3 定期维护: 对大表在低峰期手动 ANALYZE
-- ANALYZE TABLE orders;
-- ANALYZE TABLE order_items;

-- ============================================================
-- 清理
-- ============================================================

-- 删除直方图 (可选)
-- ANALYZE TABLE orders DROP HISTOGRAM ON customer_id;

-- 删除测试表
DROP TABLE IF EXISTS orders_stats_test;
