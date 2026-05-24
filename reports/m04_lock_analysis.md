# TASK-05 模块4: 锁竞争与死锁诊断 — 分析报告

## 总览

| # | 场景 | 锁类型 | 现象 | 根因 | 修复方案 |
|---|---|---|---|---|---|
| 1 | Gap Lock 阻塞 INSERT | Gap Lock / Insert Intention Lock 冲突 | INSERT 被阻塞直至锁超时 | `SELECT FOR UPDATE` 不存在的行获取 Gap Lock | 使用唯一约束 + `ON DUPLICATE KEY` 或 RC 隔离级别 |
| 2 | AB-BA 死锁 | 行锁循环等待 | MySQL 检测死锁，回滚一个事务 | 两个事务以相反顺序更新同一组行 | 统一加锁顺序（按 id 或 order_no 升序） |
| 3 | 长事务锁等待 | 行锁超时 | 等待 `innodb_lock_wait_timeout` 秒后失败 | 事务持有锁不释放，其他会话超时 | 缩短事务 / 减少锁持有时间 / 乐观锁 |

> 环境: MySQL 8.4, REPEATABLE-READ, innodb_lock_wait_timeout=默认值

---

## 场景1: Gap Lock 阻塞 INSERT

### 复现步骤

```sql
-- Session A: 对不存在的 order_no 加锁
BEGIN;
SELECT * FROM orders WHERE order_no = '999999999999' FOR UPDATE;
-- 获取 Gap Lock，阻塞后续 INSERT

-- Session B: 插入相同 order_no
INSERT INTO orders (...) VALUES (..., '999999999999', ...);
-- ERROR 1205: Lock wait timeout exceeded
```

### 结果

```
[Session B] ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting transaction
```

### 诊断

在 REPEATABLE-READ 隔离级别下, `SELECT ... FOR UPDATE` 对不存在的行会获取 **Gap Lock** (间隙锁), 锁定该行应存在的索引区间。其他事务的 INSERT 若落在该区间, 会获取 **Insert Intention Lock** (插入意向锁), 与 Gap Lock 冲突。

### 修复方案

1. **使用 `INSERT ... ON DUPLICATE KEY UPDATE`** 替代 SELECT → INSERT 模式
2. **改用 RC (READ-COMMITTED) 隔离级别** — 不使用 Gap Lock, 仅锁存在行
3. **使用唯一索引 + 乐观插入** — 先 INSERT, 失败再处理

---

## 场景2: AB-BA 死锁

### 复现步骤

```sql
-- Session 1: 先锁 100, 再锁 200
BEGIN;
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 100;  -- 持有 100
-- SLEEP(4)
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 200;  -- 等待 200

-- Session 2: 先锁 200, 再锁 100 (相反顺序!)
BEGIN;
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 200;  -- 持有 200
-- SLEEP(2)
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 100;  -- 等待 100 → 死锁
```

### 死锁日志 (SHOW ENGINE INNODB STATUS)

```
LATEST DETECTED DEADLOCK
------------------------
2026-05-24 21:40:27

*** (1) TRANSACTION:
TRANSACTION 4503, ACTIVE 3 sec
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 100
  (1) HOLDS THE LOCK(S):
    RECORD LOCKS ... index PRIMARY ... lock_mode X locks rec but not gap
    Record lock ... order_id=200 (hex 80000000000000c8)
  (1) WAITING FOR THIS LOCK TO BE GRANTED:
    RECORD LOCKS ... index PRIMARY ... lock_mode X locks rec but not gap waiting
    Record lock ... order_id=100 (hex 8000000000000064)

*** (2) TRANSACTION:
TRANSACTION 4502, ACTIVE 4 sec
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 200
  (2) HOLDS THE LOCK(S):
    RECORD LOCKS ... index PRIMARY ... lock_mode X locks rec but not gap
    Record lock ... order_id=100 (hex 8000000000000064)
  (2) WAITING FOR THIS LOCK TO BE GRANTED:
    RECORD LOCKS ... index PRIMARY ... lock_mode X locks rec but not gap waiting
    Record lock ... order_id=200 (hex 80000000000000c8)

*** WE ROLL BACK TRANSACTION (1)
```

### 死锁图

```
T1 (thread 187)          T2 (thread 186)
   Holds: 200               Holds: 100
   Waits: 100               Waits: 200
        ↓                      ↓
        └──────────────────────┘
           CIRCULAR WAIT → DEADLOCK
```

### 修复方案

1. **统一加锁顺序** — 所有事务按 `order_id ASC` 顺序更新:
   ```sql
   -- 所有事务统一: 先 UPDATE id=100, 再 UPDATE id=200
   UPDATE orders SET ... WHERE order_id = 100;
   UPDATE orders SET ... WHERE order_id = 200;
   ```
2. **批量操作合并** — 一次 UPDATE 处理多行:
   ```sql
   UPDATE orders SET total_amount = total_amount + 0.01
   WHERE order_id IN (100, 200);
   ```
3. **使用乐观锁** — 无锁 CAS 模式:
   ```sql
   UPDATE orders SET total_amount = total_amount + 0.01, version = version + 1
   WHERE order_id = 100 AND version = @expected_version;
   ```

---

## 场景3: 长事务锁等待

### 复现步骤

```sql
-- Session A: 长事务持有行锁 8 秒
BEGIN;
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 100;
SELECT SLEEP(8);  -- 模拟业务逻辑耗时
COMMIT;

-- Session B: 1 秒后尝试更新同一行 (lock_wait_timeout = 4)
UPDATE orders SET total_amount = total_amount + 0.01 WHERE order_id = 100;
-- 等待 4 秒后:
-- ERROR 1205: Lock wait timeout exceeded; try restarting transaction
```

### 结果

```
[Session B] ERROR 1205 (HY000): Lock wait timeout exceeded
[Session A] 8 秒后提交成功
```

Session B 等待 4 秒后超时; Session A 在 8 秒后成功提交。

### 诊断

- Session A 持有 order_id=100 的 X 锁 (排他锁)
- Session B 尝试获取同一行的 X 锁 → 进入等待队列
- 等待时间超过 `innodb_lock_wait_timeout` (默认 50 秒, 本测试设为 4 秒) → 超时回滚

### 修复方案

1. **缩短事务** — 将 SELECT/业务逻辑移到事务外:
   ```sql
   -- Bad: 事务包含业务逻辑
   BEGIN;
   UPDATE orders SET ... WHERE order_id = 100;
   -- ... 业务逻辑处理 (耗时)
   COMMIT;
   
   -- Good: 事务只包含数据库操作
   -- ... 业务逻辑处理 (事务外)
   BEGIN;
   UPDATE orders SET ... WHERE order_id = 100;
   COMMIT;
   ```
2. **批量处理** — 聚合多次更新为一次批量 UPDATE
3. **乐观锁** — 使用版本号无锁更新, 失败重试
4. **调整 lock_wait_timeout** — 仅作为临时缓解, 不宜依赖

## 锁诊断工具

| 工具 | 用途 |
|---|---|
| `SHOW ENGINE INNODB STATUS` | 查看 LATEST DETECTED DEADLOCK 段落 |
| `performance_schema.data_locks` | 当前所有持有的锁 |
| `performance_schema.data_lock_waits` | 当前所有锁等待关系 |
| `information_schema.innodb_trx` | 当前活跃事务及锁信息 |
| `sys.innodb_lock_waits` | 锁等待关系简化视图 |

## 预防清单

1. **所有事务按相同顺序访问资源** — 消除循环等待
2. **事务尽量短** — 不在事务中做网络调用 / 文件 I/O / 复杂计算
3. **使用索引缩小锁范围** — WHERE 条件走索引, 避免锁全表
4. **定期检查慢事务** — `SELECT * FROM information_schema.innodb_trx WHERE trx_started < NOW() - INTERVAL 10 SECOND`
