-- ============================================================
-- TASK-02 模块1: 索引失效 — 修复后 SQL
-- ============================================================
USE mysql_optimization_db;

-- 场景1 fix: 正确的数据类型（字符串比较）
SELECT 'Fix 1: Correct type' AS scenario;
EXPLAIN SELECT * FROM orders WHERE order_no = '202405230001';

-- 场景2 fix: 范围条件替代函数包裹
SELECT 'Fix 2: Range condition' AS scenario;
EXPLAIN SELECT * FROM orders
WHERE order_date >= '2025-01-01' AND order_date < '2025-01-02';

-- 场景3 fix: 覆盖索引 — 只查索引列，避免回表，优化器选择索引扫描
SELECT 'Fix 3: Covering index (SELECT sku_code only)' AS scenario;
EXPLAIN SELECT sku_code FROM products WHERE sku_code LIKE '100000%';

-- 场景4 fix: UNION ALL 拆开 OR，每边独立命中索引
SELECT 'Fix 4: UNION ALL to split OR' AS scenario;
EXPLAIN
SELECT * FROM orders WHERE order_status = 'REFUNDED'
UNION ALL
SELECT * FROM orders WHERE order_date >= '2025-01-01' AND order_date < '2025-01-02';

-- 场景5 fix: 添加 city 条件以匹配复合索引最左前缀
SELECT 'Fix 5: Add city to WHERE clause' AS scenario;
EXPLAIN SELECT * FROM customers
WHERE city = 'Beijing' AND register_date > '2025-01-01'
ORDER BY city;
