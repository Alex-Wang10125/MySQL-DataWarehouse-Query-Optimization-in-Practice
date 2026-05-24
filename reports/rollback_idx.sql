-- ============================================================
-- TASK-02 模块1: 索引失效 — 索引回滚脚本
-- 执行此脚本可删除本模块创建的所有二级索引
-- 执行方式: mysql -u alex -p'alex_mysql_2024' < reports/rollback_idx.sql
-- ============================================================
USE mysql_optimization_db;

DROP INDEX IF EXISTS idx_order_no ON orders;
DROP INDEX IF EXISTS idx_order_date ON orders;
DROP INDEX IF EXISTS idx_sku_code ON products;
DROP INDEX IF EXISTS idx_payment_method ON orders;
DROP INDEX IF EXISTS idx_order_status ON orders;
DROP INDEX IF EXISTS idx_city_regdate ON customers;

-- 执行后验证: 以下查询应仅显示 PRIMARY KEY
-- SHOW INDEX FROM orders WHERE Key_name != 'PRIMARY';
-- SHOW INDEX FROM products WHERE Key_name != 'PRIMARY';
-- SHOW INDEX FROM customers WHERE Key_name != 'PRIMARY';
-- TASK-03 模块2: JOIN 键索引
DROP INDEX IF EXISTS idx_oi_order_id ON order_items;
DROP INDEX IF EXISTS idx_oi_product_id ON order_items;
DROP INDEX IF EXISTS idx_orders_customer_id ON orders;

-- TASK-04 模块3: 排序索引
DROP INDEX IF EXISTS idx_total_amount ON orders;

SELECT 'TASK-02 + TASK-03 + TASK-04 indexes rolled back successfully' AS result;
