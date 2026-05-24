#!/usr/bin/env bash
# ============================================================
# TASK-05 场景3: 长事务锁等待
# S1: BEGIN → UPDATE order_id=100 → SLEEP(10) → COMMIT
# S2: UPDATE order_id=100 → 等待锁 → 超时或成功
# ============================================================
MYSQL="mysql -u alex -palex_mysql_2024 mysql_optimization_db -N"

echo "=== 场景3: 长事务行锁等待 ==="
echo ""

# 记录原始值
echo "[准备] order 100 amount = $($MYSQL -e "SELECT total_amount FROM orders WHERE order_id=100;")"

# Session A: 长事务持有行锁
echo "[Session A] BEGIN + UPDATE order_id=100, 持有锁 8 秒..."
$MYSQL -e "
BEGIN;
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 100;
SELECT CONCAT('Session_A lock held at ', NOW()) AS info;
SELECT SLEEP(8) INTO @x;
SELECT CONCAT('Session_A committing at ', NOW()) AS info;
COMMIT;
" 2>/dev/null &
PID_A=$!

sleep 1

# 查看 Session A 的连接状态
echo "[诊断] 当前事务:"
$MYSQL -e "
SELECT trx_id, trx_state, trx_started, trx_rows_locked, trx_mysql_thread_id
FROM information_schema.innodb_trx;
" 2>/dev/null

# Session B: 尝试更新同一行 (innodb_lock_wait_timeout=4)
echo ""
echo "[Session B] 尝试 UPDATE order_id=100 (等待锁, timeout=4s)..."
START=$(date +%s)
timeout 10 $MYSQL -e "
SET SESSION innodb_lock_wait_timeout = 4;
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 100;
" 2>&1
RC=$?
ELAPSED=$(($(date +%s) - START))

if [ $RC -ne 0 ]; then
    echo "[Session B] 锁等待超时 (${ELAPSED}s 后) — 符合预期"
else
    echo "[Session B] UPDATE 成功 (${ELAPSED}s 后获取到锁)"
fi

wait $PID_A 2>/dev/null || true

echo ""
echo "[最终] order 100 amount = $($MYSQL -e "SELECT total_amount FROM orders WHERE order_id=100;")"
echo ""
echo "=== 场景3 完成 ==="
echo "修复建议: 缩短事务时间 / 批量操作 / 乐观锁"
