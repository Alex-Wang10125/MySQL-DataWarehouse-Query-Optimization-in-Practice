-- ============================================================
-- TASK-01: LOAD DATA LOCAL INFILE (~245 万行)
-- NULL 标记: __NULL__
-- ============================================================
USE mysql_optimization_db;

TRUNCATE TABLE order_items;
TRUNCATE TABLE orders;
TRUNCATE TABLE products;
TRUNCATE TABLE categories;
TRUNCATE TABLE customers;

LOAD DATA LOCAL INFILE '/home/alex/Projects_A/MySQL/data/categories.csv'
INTO TABLE categories
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(category_id, category_name, @parent_category_id)
SET parent_category_id = NULLIF(@parent_category_id, '__NULL__');

SELECT 'categories' AS tbl, COUNT(*) AS cnt FROM categories;

LOAD DATA LOCAL INFILE '/home/alex/Projects_A/MySQL/data/customers.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(customer_id, customer_name, @email, @phone, @register_date,
 customer_level, @city, @last_login, status)
SET email         = NULLIF(@email, '__NULL__'),
    phone         = NULLIF(@phone, '__NULL__'),
    register_date = STR_TO_DATE(@register_date, '%Y-%m-%d %H:%i:%s'),
    city          = NULLIF(@city, '__NULL__'),
    last_login    = STR_TO_DATE(NULLIF(@last_login, '__NULL__'), '%Y-%m-%d %H:%i:%s');

SELECT 'customers' AS tbl, COUNT(*) AS cnt FROM customers;

LOAD DATA LOCAL INFILE '/home/alex/Projects_A/MySQL/data/products.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_id, product_name, category_id, price, cost, stock_quantity,
 sku_code, @created_at, is_deleted, @weight, @description)
SET created_at  = STR_TO_DATE(@created_at, '%Y-%m-%d %H:%i:%s'),
    weight      = NULLIF(@weight, '__NULL__'),
    description = NULLIF(@description, '__NULL__');

SELECT 'products' AS tbl, COUNT(*) AS cnt FROM products;

LOAD DATA LOCAL INFILE '/home/alex/Projects_A/MySQL/data/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, order_no, customer_id, @order_date, total_amount, discount_amount,
 payment_method, @order_status, @shipping_address, is_deleted, @created_at, @updated_at)
SET order_date       = STR_TO_DATE(@order_date, '%Y-%m-%d %H:%i:%s'),
    order_status     = NULLIF(@order_status, '__NULL__'),
    shipping_address = NULLIF(@shipping_address, '__NULL__'),
    created_at       = STR_TO_DATE(@created_at, '%Y-%m-%d %H:%i:%s'),
    updated_at       = STR_TO_DATE(NULLIF(@updated_at, '__NULL__'), '%Y-%m-%d %H:%i:%s');

SELECT 'orders' AS tbl, COUNT(*) AS cnt FROM orders;

LOAD DATA LOCAL INFILE '/home/alex/Projects_A/MySQL/data/order_items.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(item_id, order_id, product_id, quantity, unit_price, subtotal,
 @product_name_snapshot, @created_at)
SET product_name_snapshot = NULLIF(@product_name_snapshot, '__NULL__'),
    created_at            = STR_TO_DATE(NULLIF(@created_at, '__NULL__'), '%Y-%m-%d %H:%i:%s');

SELECT 'order_items' AS tbl, COUNT(*) AS cnt FROM order_items;

-- ============================================================
-- 验证
-- ============================================================
SELECT '=== ROW COUNTS ===' AS info;
SELECT 'customers' AS tbl, COUNT(*) AS cnt FROM customers
UNION ALL SELECT 'categories', COUNT(*) FROM categories
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items;

SELECT '=== NULL % ===' AS info;
SELECT 'email' AS col, ROUND(SUM(email IS NULL)/COUNT(*)*100,1) AS null_pct FROM customers
UNION ALL SELECT 'phone', ROUND(SUM(phone IS NULL)/COUNT(*)*100,1) FROM customers
UNION ALL SELECT 'last_login', ROUND(SUM(last_login IS NULL)/COUNT(*)*100,1) FROM customers
UNION ALL SELECT 'weight', ROUND(SUM(weight IS NULL)/COUNT(*)*100,1) FROM products
UNION ALL SELECT 'description', ROUND(SUM(description IS NULL)/COUNT(*)*100,1) FROM products
UNION ALL SELECT 'shipping_address', ROUND(SUM(shipping_address IS NULL)/COUNT(*)*100,1) FROM orders
UNION ALL SELECT 'order_status', ROUND(SUM(order_status IS NULL)/COUNT(*)*100,1) FROM orders;

SELECT '=== DIRTY DATA ===' AS info;
SELECT
  SUM(order_status IS NULL) AS null_status,
  SUM(order_status = '') AS empty_status,
  SUM(order_status = 'COMPLETED') AS completed
FROM orders;

-- 倾斜验证
SELECT customer_id, COUNT(*) AS cnt FROM orders
GROUP BY customer_id ORDER BY cnt DESC LIMIT 3;
