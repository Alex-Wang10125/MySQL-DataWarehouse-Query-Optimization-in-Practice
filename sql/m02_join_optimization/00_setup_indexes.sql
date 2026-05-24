-- ============================================================
-- TASK-03 模块2: 大表 JOIN 策略优化 — JOIN 键索引创建
-- ============================================================
USE mysql_optimization_db;

-- 核心 JOIN 键索引（当前不存在，是 NLJ 性能瓶颈）
CREATE INDEX idx_oi_order_id ON order_items(order_id);
CREATE INDEX idx_oi_product_id ON order_items(product_id);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);

-- 验证
SHOW INDEX FROM order_items;
SHOW INDEX FROM orders;
