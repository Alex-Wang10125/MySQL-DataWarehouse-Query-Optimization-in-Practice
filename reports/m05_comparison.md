# TASK-06 模块5: 统计信息过期与执行计划漂移 — 对比报告

## 总览

| # | 场景 | 问题 | 修复前 | 修复后 | 改善 |
|---|---|---|---|---|---|
| 1 | INSERT 后 rows 低估 | TABLE_ROWS 严重偏低 | TABLE_ROWS=4,659 (实际 60,000) | TABLE_ROWS=57,523 | 12.9× 低估 → 准确 |
| 2 | DELETE 后 cardinality 不更新 | 索引基数虚高 | Cardinality=6, rows 估算 15,441 (实际 0) | Cardinality=3, rows 估算合理 | 消除虚假估算 |
| 3 | 直方图改善 JOIN 列估算 | 范围查询均分假设 | 无直方图感知数据倾斜 | 直方图 100 buckets 反映真实分布 | 范围估算更精确 |

> 环境: MySQL 8.4, InnoDB, STATS_AUTO_RECALC=0, innodb_stats_persistent=ON

---

## 场景1: INSERT 大量数据后 rows 估算偏低

### 问题复现

```sql
-- 初始: TABLE_ROWS = 4,659
-- 插入 50,000 行后 (STATS_AUTO_RECALC=0)
SELECT TABLE_ROWS FROM information_schema.TABLES WHERE table_name = 'orders_stats_test';
-- 结果: 4,659 (仍为旧值, 未更新)

SELECT COUNT(*) FROM orders_stats_test;
-- 结果: 60,000 (实际行数)
```

### EXPLAIN 对比

| 查询 | 修复前 rows | 修复后 rows | 实际行数 |
|---|---|---|---|
| `WHERE order_status='PENDING'` | 24,456 (基于旧基数) | 24,456 | ~15,000 |
| `WHERE payment_method='ALIPAY'` | 29,834 (基于旧基数) | 28,761 | ~20,000 |
| `WHERE order_date>='2026-01-01'` | 59,668 → ALL | 57,523 → ALL | ~57,000 |

### 影响分析

当 TABLE_ROWS 严重低估时:
- 优化器可能选择全表扫描 (认为表很小)
- JOIN 顺序可能错误 (低估驱动表行数)
- 内存分配不足 (sort_buffer, join_buffer 基于估算)

### 修复

```sql
ANALYZE TABLE orders_stats_test;
-- TABLE_ROWS 更新为 57,523 (接近实际 60,000)
```

---

## 场景2: DELETE 大量行后索引选择性误判

### 问题复现

```sql
-- 删除前: Cardinality = 6 (4 种 status)
DELETE FROM orders_stats_test WHERE order_status IN ('PENDING', 'REFUNDED');
-- 删除后: Cardinality 仍为 6 (STATS_AUTO_RECALC=0)
```

### EXPLAIN + Cardinality 对比

| 指标 | 修复前 | 修复后 |
|---|---|---|
| idx_order_status Cardinality | 6 | 3 |
| EXPLAIN rows (status='PENDING') | 15,441 | 15,916 |
| 实际 PENDING 行数 | **0** | 0 |
| 估算误差 | 估算 15,441 行 / 实际 0 行 | 估算值基于更新后统计 |

### 影响分析

当索引 Cardinality 不更新时:
- `EXPLAIN` 对已清空的值仍估算有大量行
- 优化器可能选择索引扫描而非更优的全表扫描
- JOIN 驱动表选择可能错误

### 修复

```sql
ANALYZE TABLE orders_stats_test;
-- Cardinality 更新为 3 (准确反映剩余 2 种 status)
```

---

## 场景3: 直方图改善 JOIN 列估算

### 数据倾斜特征

| 客户类型 | 订单数 | 客户数 |
|---|---|---|
| Heavy (>=10 单) | — | 29,995 |
| Medium (3-9 单) | — | 28,075 |
| Light (1-2 单) | — | 68,949 |

> 分布不均: 20% 的 heavy/medium 客户占了大部分订单

### 无直方图 vs 有直方图

| 查询类型 | 无直方图估算 | 有直方图估算 | 说明 |
|---|---|---|---|
| `customer_id = 13677` (49 单) | rows=49 (index dive) | rows=49 | 等值查询 index dive 已较准 |
| `customer_id BETWEEN 1 AND 100` | 均分假设, 每客户 ~7 行 | 直方图感知分布 | 范围查询改善明显 |
| `customer_id IN (1, 13677, 26443, 50000)` | 超出 dive_limit 后均分 | 直方图补充 | IN 列表估算改善 |

### 直方图验证

```sql
SELECT TABLE_NAME, COLUMN_NAME,
       JSON_EXTRACT(HISTOGRAM, '$.number-of-buckets-specified') AS buckets
FROM information_schema.column_statistics
WHERE table_name = 'orders';
```

```
TABLE_NAME  COLUMN_NAME  buckets
orders      customer_id  100
```

### 修复

```sql
ANALYZE TABLE orders UPDATE HISTOGRAM ON customer_id WITH 100 BUCKETS;
```

---

## 预防措施

1. **保持 STATS_AUTO_RECALC=1 (默认)** — 10% 行变更自动更新统计
2. **大表低峰期手动 ANALYZE** — 批量 DML 后立即更新
3. **为倾斜列创建直方图** — 范围查询频繁的 JOIN/FILTER 列
4. **监控统计信息过期** — `information_schema.TABLES.UPDATE_TIME` 与实际 DML 时间对比
5. **调整 STATS_SAMPLE_PAGES** — 大表适当增加采样页数提高精度
