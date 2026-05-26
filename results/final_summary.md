# MySQL 数仓查询优化实战 — 最终总结

## 项目概况

| 项目 | 详情 |
|---|---|
| MySQL 版本 | 8.4.8 (Ubuntu) |
| 硬件环境 | 4C / 3.3GB RAM / 61GB 磁盘 |
| InnoDB Buffer Pool | 128MB |
| 数据规模 | 5 表, ~500 万行 |
| 表结构 | customers (15万), categories (500), products (5万), orders (100万), order_items (125万) |

## 六大模块成果汇总

| # | 模块 | 场景数 | 核心指标 | 关键成果 |
|---|---|---|---|---|
| 1 | 索引失效诊断与修复 | 5 | 查询时间降低 10× ~ 100,000× | 6 个索引 (134 MB), 覆盖隐式转换/函数包裹/OR/最左前缀 |
| 2 | 大表 JOIN 策略优化 | 4 | 查询时间降低 4× ~ 212× | 3 个 JOIN 键索引 (76 MB), NLJ+ref 优于 Hash Join |
| 3 | 深度分页与排序优化 | 4 | 游标分页 59,000×, 延迟关联 4~6× | OFFSET 扫描-丢弃是元凶, 游标分页 0.079ms |
| 4 | 锁竞争与死锁诊断 | 3 | 3 种锁问题全部复现并修复 | Gap Lock / AB-BA 死锁 / 长事务, 含 InnoDB 死锁日志解读 |
| 5 | 统计信息过期与计划漂移 | 3 | TABLE_ROWS 低估 12.9× → 修复 | ANALYZE TABLE + 直方图 (100 buckets) |
| 6 | 子查询改写优化 | 4 | DEPENDENT SUBQUERY 6× 提升 | IN→JOIN, NOT IN→NOT EXISTS, 派生表物化消除, 标量子查询分析 |

### 详细成果

#### 模块1: 索引失效诊断与修复
| 场景 | 问题 | 修复 | 效果 |
|---|---|---|---|
| 隐式类型转换 | `WHERE order_no = 123456789012` (VARCHAR 列) | 引号包裹或创建索引 | type: ALL → ref |
| 函数包裹列 | `WHERE DATE(order_date) = '2025-01-01'` | 范围查询改写 | 索引命中 |
| LIKE 前置模糊 | `WHERE sku_code LIKE '%5678'` | 覆盖索引 | Using index |
| OR 条件拆分 | `WHERE status = 'X' OR DATE(date) = 'Y'` | UNION ALL | 各走索引 |
| 最左前缀不匹配 | `WHERE register_date > 'X'` (索引是 city+date) | 单独索引或调整顺序 | 消除 filesort |

#### 模块2: 大表 JOIN 策略优化
| 场景 | 驱动表 | JOIN 类型 | 时间 | 改善 |
|---|---|---|---|---|
| 3 表 JOIN 无索引 | orders (1M) | Hash Join | 基线 | — |
| + JOIN 键索引 | customers (小) | NLJ + ref | — | 4~212× |
| STRAIGHT_JOIN 干预 | 指定驱动表 | NLJ + ref | — | 强制优化 |

关键发现: MySQL 8.4 的 Hash Join 是 fallback 而非最优 — NLJ + ref (有索引) 总是更快。

#### 模块3: 深度分页与排序优化
| 方案 | LIMIT 950000, 20 | 改善 |
|---|---|---|
| 纯 OFFSET | 4.7s | 基线 |
| 延迟关联 (子查询 PK + 少量回表) | ~1s | 4~6× |
| 游标分页 (WHERE id > last_id) | 0.079ms | ~59,000× |

#### 模块4: 锁竞争与死锁诊断
| 场景 | 锁类型 | 现象 | 修复 |
|---|---|---|---|
| Gap Lock | Gap + Insert Intention | INSERT 超时 | ON DUPLICATE KEY / RC 隔离级别 |
| AB-BA 死锁 | 行锁循环等待 | 死锁回滚 | 统一加锁顺序 (按 PK ASC) |
| 长事务 | 行锁超时 | 等 4s 失败 | 缩短事务 / 乐观锁 |

#### 模块5: 统计信息过期与计划漂移
| 场景 | 问题 | 修复前 | 修复后 |
|---|---|---|---|
| INSERT 后 rows 低估 | TABLE_ROWS 过期 | 4,659 (实际 60,000) | 57,523 |
| DELETE 后 cardinality 虚高 | SHOW INDEX 不更新 | Cardinality=6 (实际 3) | 3 |
| 直方图 | 范围查询均分假设 | 无倾斜感知 | 100 buckets |

#### 模块6: 子查询改写优化
| 原始模式 | 改写为 | 改善 |
|---|---|---|
| IN + GROUP BY (DEPENDENT SUBQUERY) | JOIN 派生表 | 2,175ms → 361ms (6×) |
| NOT IN (NULL 陷阱, 返回 0 行) | NOT EXISTS | 正确性修复 |
| 派生表物化 (无索引, ALL 992K) | HAVING 下推 | 消除临时表 |
| 标量子查询 (COUNT covering vs SUM 回表) | 预聚合 + 过滤下推 | 策略选择, 48× 差异 |

## 索引资产清单

| 索引名 | 表 | 列 | 模块 | 用途 |
|---|---|---|---|---|
| idx_order_no | orders | order_no | M1 | 修复隐式类型转换 |
| idx_order_date | orders | order_date | M1 | 修复 DATE() 函数包裹 |
| idx_sku_code | products | sku_code | M1 | 覆盖索引 (LIKE 前缀) |
| idx_payment_method | orders | payment_method | M1 | 索引查找 |
| idx_order_status | orders | order_status | M1 | 索引查找 + M5 基数演示 |
| idx_city_regdate | customers | city, register_date | M1 | 复合索引最左前缀 |
| idx_oi_order_id | order_items | order_id | M2 | JOIN 键索引 |
| idx_oi_product_id | order_items | product_id | M2 | JOIN 键索引 |
| idx_orders_customer_id | orders | customer_id | M2 | JOIN 键索引 |
| idx_total_amount | orders | total_amount | M3 | 排序覆盖 + 延迟关联 |

**总计**: 10 个索引, ~210 MB

## 回滚脚本

所有索引的回滚脚本: `reports/rollback_idx.sql`

```bash
mysql -u root mysql_optimization_db < reports/rollback_idx.sql
```

## 经验提炼

### 索引
1. 隐式类型转换是最隐蔽的索引杀手 — VARCHAR 列用整数查, 索引直接失效
2. 复合索引最左前缀是铁律 — 跳过前导列即全表扫描
3. OR 条件在 MySQL 中比想象中脆弱 — UNION ALL 往往是最可靠的解法
4. 每个索引都有写入/存储成本 — 本项目中 10 个索引共 ~210 MB

### JOIN
5. MySQL 8.4 Hash Join 是 fallback — 只有没索引时才用, NLJ+ref 总是更快
6. 驱动表行数决定 JOIN 性能 — WHERE 过滤 + 小表驱动大表

### 分页
7. OFFSET 是扫描-丢弃模型 — OFFSET 越大越慢, 游标分页是最终解
8. 延迟关联是过渡方案 — 适合无法改应用层分页逻辑的场景

### 锁
9. InnoDB REPEATABLE-READ 下 Gap Lock 防幻读但阻塞插入 — RC 级别可缓解
10. 统一加锁顺序是最简单的死锁预防 — 所有事务按 PK ASC 更新

### 统计信息
11. STATS_AUTO_RECALC=0 时统计完全冻结 — 批量 DML 后必须手动 ANALYZE
12. 直方图改善范围查询估算 — 等值查询 index dive 已较准

### 子查询
13. GROUP BY/HAVING 引用外层列 → DEPENDENT SUBQUERY — 预聚合后 JOIN 是正解
14. NOT IN 是静默数据丢失元凶 — 永远用 NOT EXISTS 或 LEFT JOIN ... IS NULL
15. MySQL 8.4 已能自动优化简单子查询 — 不要盲目改写所有子查询
