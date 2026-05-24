-- ============================================================
-- TASK-02 模块1: 索引失效 — 问题 SQL（索引被绕过）
-- ============================================================
USE mysql_optimization_db;

-- 场景1: 隐式类型转换
-- order_no 是 VARCHAR，但用整数比较，索引失效
SELECT 'Scenario 1: Implicit type conversion' AS scenario;
EXPLAIN SELECT * FROM orders WHERE order_no = 202405230001;

-- 场景2: 函数包裹索引列
-- DATE() 包裹 order_date，索引失效
SELECT 'Scenario 2: Function on indexed column' AS scenario;
EXPLAIN SELECT * FROM orders WHERE DATE(order_date) = '2025-01-01';

-- 场景3: LIKE 前缀 + SELECT * (回表代价导致优化器放弃索引)
-- 虽然 LIKE '100000%' 满足最左前缀，但 SELECT * 需要回表，优化器认为全表扫描更快
SELECT 'Scenario 3: LIKE + SELECT * forces table scan' AS scenario;
EXPLAIN SELECT * FROM products WHERE sku_code LIKE '100000%';

-- 场景4: OR + 函数包裹索引列
-- DATE() 包裹 order_date，导致 OR 两边都无法有效使用索引，回退全表扫描
SELECT 'Scenario 4: OR + function on indexed column' AS scenario;
EXPLAIN SELECT * FROM orders WHERE order_status = 'REFUNDED' OR DATE(order_date) = '2025-01-01';

-- 场景5: 复合索引最左前缀不匹配
-- idx_city_regdate(city, register_date)，只用 register_date 无法命中
SELECT 'Scenario 5: Leftmost prefix mismatch' AS scenario;
EXPLAIN SELECT * FROM customers WHERE register_date > '2025-01-01' ORDER BY city;
