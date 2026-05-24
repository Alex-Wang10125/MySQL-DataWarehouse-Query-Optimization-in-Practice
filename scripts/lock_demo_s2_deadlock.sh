#!/usr/bin/env bash
# ============================================================
# TASK-05 场景2: AB-BA 死锁
# S1: UPDATE id=100 → id=200 (按此顺序)
# S2: UPDATE id=200 → id=100 (相反顺序)
# ============================================================
MYSQL="mysql -u alex -palex_mysql_2024 mysql_optimization_db -N"
READY1="/tmp/s2_s1_ready"
READY2="/tmp/s2_s2_ready"

echo "=== 场景2: AB-BA 死锁 ==="
echo ""

rm -f "$READY1" "$READY2"

# 先记录原始值
echo "[准备] order 100 amount = $($MYSQL -e "SELECT total_amount FROM orders WHERE order_id=100;")"
echo "[准备] order 200 amount = $($MYSQL -e "SELECT total_amount FROM orders WHERE order_id=200;")"

# Session 1: 先锁 order_id=100, 发信号, 等 S2 锁了 200 后再去锁 200
echo "[Session 1] BEGIN → UPDATE order_id=100 → 等待 S2..."
$MYSQL -e "
BEGIN;
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 100;
SELECT CONCAT('S1 locked order_id=100 at ', NOW()) AS info;
SELECT SLEEP(4) INTO @x;
-- 此时 S2 应该已经锁了 order_id=200
SELECT CONCAT('S1 now trying to lock order_id=200 at ', NOW()) AS info;
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 200;
SELECT 'S1 locked order_id=200 — should NOT see this if deadlock' AS info;
COMMIT;
" 2>/dev/null &
PID1=$!

# Session 2: 等 S1 先锁了 100, 然后锁 200, 再尝试锁 100
sleep 1
echo "[Session 2] BEGIN → UPDATE order_id=200 → 然后尝试 UPDATE order_id=100..."
$MYSQL -e "
BEGIN;
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 200;
SELECT CONCAT('S2 locked order_id=200 at ', NOW()) AS info;
SELECT SLEEP(2) INTO @x;
-- 此时 S1 持有 100, S2 持有 200, S2 尝试锁 100 → 死锁
SELECT CONCAT('S2 now trying to lock order_id=100 at ', NOW()) AS info;
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 100;
SELECT 'S2 locked order_id=100 — should NOT see this' AS info;
COMMIT;
" 2>/dev/null &
PID2=$!

# 等待两个会话完成
wait $PID1 2>/dev/null || true
wait $PID2 2>/dev/null || true

echo ""
echo "[诊断] 死锁日志 (LATEST DETECTED DEADLOCK):"
$MYSQL -e "SHOW ENGINE INNODB STATUS\G" 2>/dev/null | grep -A 30 "LATEST DETECTED DEADLOCK" | head -40

echo ""
echo "[最终] order 100 amount = $($MYSQL -e "SELECT total_amount FROM orders WHERE order_id=100;")"
echo "[最终] order 200 amount = $($MYSQL -e "SELECT total_amount FROM orders WHERE order_id=200;")"
echo ""
echo "=== 场景2 完成 ==="
echo "结果: MySQL 自动检测死锁并回滚其中一个事务, 另一个成功提交"
