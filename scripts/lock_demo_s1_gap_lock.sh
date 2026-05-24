#!/usr/bin/env bash
# ============================================================
# TASK-05 场景1: Gap Lock 阻塞 INSERT
# ============================================================
MYSQL="mysql -u alex -palex_mysql_2024 mysql_optimization_db -N"
TEST_NO='999999999999'

echo "=== 场景1: Gap Lock 阻塞 INSERT ==="
echo ""

# 清理
$MYSQL -e "DELETE FROM orders WHERE order_no = '$TEST_NO';" 2>/dev/null || true

# Session A: 在后台持有 gap lock
echo "[Session A] BEGIN + SELECT ... FOR UPDATE (order_no=$TEST_NO, 不存在)"
$MYSQL -e "
BEGIN;
SELECT CONCAT('Session_A lock held, conn_id=', CONNECTION_ID());
SELECT order_id FROM orders WHERE order_no = '$TEST_NO' FOR UPDATE;
SELECT SLEEP(10) INTO @x;
ROLLBACK;
" 2>/dev/null &
PID_A=$!

sleep 2

# Session B: 尝试插入
echo "[Session B] INSERT order_no=$TEST_NO (timeout=3s)..."
timeout 5 $MYSQL -e "
SET SESSION innodb_lock_wait_timeout = 3;
INSERT INTO orders (order_id, order_no, customer_id, order_date, total_amount, discount_amount, payment_method, order_status, shipping_address, created_at, updated_at)
VALUES (9999999, '$TEST_NO', 1, NOW(), 100.00, 0, 'ALIPAY', 'PENDING', 'addr', NOW(), NOW());
SELECT 'Session_B INSERT succeeded';
" 2>&1 || echo "[Session B] 锁等待超时 — 符合预期 (Gap Lock 阻塞了 INSERT)"

echo ""
echo "[诊断] 当前锁信息:"
$MYSQL -e "
SELECT engine_transaction_id, object_name, lock_type, lock_mode, lock_status
FROM performance_schema.data_locks
WHERE object_name = 'orders' AND lock_type = 'RECORD'
LIMIT 5;
" 2>/dev/null || echo "(检查 performance_schema.data_locks 失败)"

wait $PID_A 2>/dev/null || true
$MYSQL -e "DELETE FROM orders WHERE order_no = '$TEST_NO';" 2>/dev/null || true

echo ""
echo "=== 场景1 完成 ==="
