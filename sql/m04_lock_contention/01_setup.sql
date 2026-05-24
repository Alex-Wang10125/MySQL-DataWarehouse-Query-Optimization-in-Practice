-- ============================================================
-- TASK-05 模块4: 锁竞争与死锁诊断 — 环境准备
-- ============================================================
USE mysql_optimization_db;

-- 确认隔离级别为 REPEATABLE-READ (默认, Gap Lock 需要)
SELECT @@transaction_isolation;

-- 确认锁等待超时设置
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout';

-- 场景2 死锁测试: 确保 order_id 100 和 200 存在
SELECT order_id, order_no, total_amount FROM orders WHERE order_id IN (100, 200);

-- 场景1 间隙锁测试: 确认 order_no '999999999999' 不存在
SELECT COUNT(*) AS not_exists FROM orders WHERE order_no = '999999999999';

-- 开启 InnoDB 锁监控 (已在 TASK-00 配置, 此处确认)
SHOW VARIABLES LIKE 'innodb_status_output_locks';
