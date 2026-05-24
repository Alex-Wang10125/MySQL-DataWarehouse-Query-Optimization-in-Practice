-- ============================================================
-- TASK-04 模块3: 深度分页与排序优化 — 索引创建
-- ============================================================
USE mysql_optimization_db;

-- 场景2: FileSort 优化 — 为 total_amount 创建索引
-- 配合延迟关联使用，子查询走覆盖索引，避免回表
CREATE INDEX idx_total_amount ON orders(total_amount);

SHOW INDEX FROM orders WHERE Key_name = 'idx_total_amount';
