-- ============================================================
-- TASK-02 模块1: 索引失效 — 场景索引创建
-- 这些是正确的索引，但会被错误的 SQL 写法绕过
-- ============================================================
USE mysql_optimization_db;

-- 场景1: 隐式类型转换 — orders.order_no 是 VARCHAR，建索引供演示
CREATE INDEX idx_order_no ON orders(order_no);

-- 场景2: 函数包裹索引列 — orders.order_date 建索引，用 DATE() 绕过
CREATE INDEX idx_order_date ON orders(order_date);

-- 场景3: LIKE 前置模糊 — products.sku_code 建索引，用 %5678 绕过
CREATE INDEX idx_sku_code ON products(sku_code);

-- 场景4: OR 条件索引拆分 — 两个独立索引，OR 条件无法同时使用
CREATE INDEX idx_payment_method ON orders(payment_method);
CREATE INDEX idx_order_status ON orders(order_status);

-- 场景5: 复合索引最左前缀 — (city, register_date) 复合索引
CREATE INDEX idx_city_regdate ON customers(city, register_date);

SHOW INDEX FROM orders;
SHOW INDEX FROM products;
SHOW INDEX FROM customers;
