-- ============================================================
-- TASK-00: 数据库初始化 DDL
-- 数据库: mysql_optimization_db
-- 仅创建主键，不创建二级索引（各模块按需添加）
-- ============================================================

USE mysql_optimization_db;

-- 1. 维度表: customers (150万行)
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id     BIGINT          NOT NULL AUTO_INCREMENT,
    customer_name   VARCHAR(100)    NOT NULL,
    email           VARCHAR(200)    DEFAULT NULL,
    phone           VARCHAR(20)     DEFAULT NULL,
    register_date   DATETIME        NOT NULL,
    customer_level  VARCHAR(10)     NOT NULL DEFAULT 'BRONZE',
    city            VARCHAR(50)     DEFAULT NULL,
    last_login      DATETIME        DEFAULT NULL,
    status          TINYINT         NOT NULL DEFAULT 1,
    PRIMARY KEY (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. 维度表: categories (500行)
CREATE TABLE categories (
    category_id         INT             NOT NULL AUTO_INCREMENT,
    category_name       VARCHAR(100)    NOT NULL,
    parent_category_id  INT             DEFAULT NULL,
    PRIMARY KEY (category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. 维度表: products (50万行)
CREATE TABLE products (
    product_id      BIGINT          NOT NULL AUTO_INCREMENT,
    product_name    VARCHAR(200)    NOT NULL,
    category_id     INT             NOT NULL,
    price           DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    cost            DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    stock_quantity  INT             NOT NULL DEFAULT 0,
    sku_code        VARCHAR(50)     NOT NULL,          -- 故意用 VARCHAR 存纯数字
    created_at      DATETIME        NOT NULL,
    is_deleted      TINYINT         NOT NULL DEFAULT 0,
    weight          DECIMAL(8,2)    DEFAULT NULL,
    description     TEXT            DEFAULT NULL,
    PRIMARY KEY (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. 事实表: orders (800万行)
CREATE TABLE orders (
    order_id            BIGINT          NOT NULL AUTO_INCREMENT,
    order_no            VARCHAR(32)     NOT NULL,      -- 故意用 VARCHAR 存纯数字
    customer_id         BIGINT          NOT NULL,
    order_date          DATETIME        NOT NULL,
    total_amount        DECIMAL(12,2)   NOT NULL DEFAULT 0.00,
    discount_amount     DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    payment_method      VARCHAR(20)     NOT NULL DEFAULT 'ALIPAY',
    order_status        VARCHAR(20)     NOT NULL DEFAULT 'PENDING',
    shipping_address    VARCHAR(500)    DEFAULT NULL,
    is_deleted          TINYINT         NOT NULL DEFAULT 0,
    created_at          DATETIME        NOT NULL,
    updated_at          DATETIME        DEFAULT NULL,
    PRIMARY KEY (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. 事实表: order_items (1000万行)
CREATE TABLE order_items (
    item_id                 BIGINT          NOT NULL AUTO_INCREMENT,
    order_id                BIGINT          NOT NULL,
    product_id              BIGINT          NOT NULL,
    quantity                INT             NOT NULL DEFAULT 1,
    unit_price              DECIMAL(10,2)   NOT NULL DEFAULT 0.00,
    subtotal                DECIMAL(12,2)   NOT NULL DEFAULT 0.00,
    product_name_snapshot   VARCHAR(200)    DEFAULT NULL,
    created_at              DATETIME        NOT NULL,
    PRIMARY KEY (item_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 验证表结构
SHOW TABLES;
