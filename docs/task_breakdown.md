# 任务拆分

## 任务总览

| TASK | 名称 | 涉及 Skill | 预估工作量 | 依赖 |
|---|---|---|---|---|
| TASK-00 | 环境初始化与 MySQL 配置 | — | 小 | 无 |
| TASK-01 | 生成并导入 2000 万行测试数据 | Stress Data Factory | 中 | TASK-00 |
| TASK-02 | 模块1：索引失效诊断与修复 | Spec Checker, Baseline Collector, Index Impact Analyzer | 中 | TASK-01 |
| TASK-03 | 模块2：大表 JOIN 策略优化 | Spec Checker, Baseline Collector, Index Impact Analyzer | 中 | TASK-01 |
| TASK-04 | 模块3：深度分页与排序优化 | Spec Checker, Baseline Collector, Index Impact Analyzer | 中 | TASK-01 |
| TASK-05 | 模块4：锁竞争与死锁诊断 | Spec Checker, Baseline Collector, Concurrency Load Analyzer | 中 | TASK-01 |
| TASK-06 | 模块5：统计信息过期与计划漂移 | Spec Checker, Baseline Collector | 中 | TASK-01 |
| TASK-07 | 模块6：子查询改写优化 | Spec Checker, Baseline Collector, Index Impact Analyzer | 中 | TASK-01 |
| TASK-08 | 全项目总结归档 | Outcome Archiver | 小 | TASK-02~07 |

---

## TASK-00：环境初始化与 MySQL 配置

### 目标
确认 MySQL 8.4 运行正常，创建数据库，配置必要的参数，初始化项目目录和 `.env` 文件。

### 具体操作
1. 创建数据库 `mysql_optimization_db`
2. 确认/设置关键 MySQL 参数
   - `innodb_buffer_pool_size` — 若可用内存充裕则调至 1.5G
   - `slow_query_log = ON`, `long_query_time = 0.1`
   - `innodb_status_output = ON`
   - `performance_schema = ON`
3. 创建 `.env` 文件（数据库连接信息）
4. 创建 `.gitignore`（排除 data/、.env）
5. 创建项目 `README.md`
6. 创建 `ARCHIVE_INDEX.md` 空模板

### 产出物
- `sql/00_init_database.sql` — 建库 + DDL
- `.env` — 连接信息
- `.gitignore`
- `README.md`
- `ARCHIVE_INDEX.md`

---

## TASK-01：生成并导入 2000 万行测试数据

### 目标
使用 Python 生成 5 张表的 CSV 文件，通过 LOAD DATA INFILE 导入 MySQL，验证数据质量。

### 数据规格来源
`docs/technical_specification.md` 第 2 节"数据生成规格"。

### 具体操作
1. Invoke **Stress Data Factory** Skill 生成 `scripts/generate_data.py`
2. 依次生成各表 CSV（按外键依赖顺序）
3. 编写 `sql/01_import_data.sql`，使用 `LOAD DATA INFILE` 导入
4. 构建索引（外键列 + 覆盖索引）
5. 执行 `ANALYZE TABLE` 初始化统计信息
6. 验证：行数、倾斜分布、NULL 比例

### 产出物
- `scripts/generate_data.py`
- `data/*.csv`（中间产物，可清理）
- `sql/01_import_data.sql`
- `reports/data_generation_report.md`

---

## TASK-02：模块 1 — 索引失效诊断与修复

### 目标
演示 5 种索引失效场景，逐一修复，产出优化前后对比。

### 场景
1. 隐式类型转换（VARCHAR 列用整数查询）
2. 函数包裹索引列（`DATE()`、`YEAR()` 等）
3. LIKE 前置模糊
4. OR 条件导致索引拆分
5. 复合索引最左前缀不匹配 + FileSort

### 执行流程
1. Invoke **Spec Checker** → 生成微计划，获取用户批准
2. 编写 `sql/m01_index_failure/problem_queries.sql`
3. Invoke **Performance Baseline Collector** → 采集优化前基线
4. 编写 `sql/m01_index_failure/fix_scripts.sql`
5. Invoke **Index Impact Analyzer** → 分析每个索引的成本收益
6. 执行修复脚本
7. Invoke **Performance Baseline Collector** → 采集优化后基线
8. 生成 `reports/m01_comparison.md`
9. Invoke **Outcome Archiver** → 归档

### 产出物
- `reports/micro_plan_m01.md`
- `sql/m01_index_failure/problem_queries.sql`
- `sql/m01_index_failure/fix_scripts.sql`
- `reports/m01_baseline.md` / `reports/m01_optimized.md` / `reports/m01_comparison.md`
- `reports/index_analysis_m01.md`
- `reports/archive_m01.md`

---

## TASK-03：模块 2 — 大表 JOIN 策略优化

### 目标
演示 JOIN 驱动表选择、NLJ vs Hash Join、BNL Buffer 不足等场景。

### 场景
1. 大表 JOIN 缺索引 → SNLJ 灾难
2. 驱动表选择错误（大表驱动大表）
3. MySQL 8.4 Hash Join 效果演示
4. STRAIGHT_JOIN 干预 JOIN 顺序

### 产出物
与 TASK-02 同模式，路径为 `sql/m02_join_optimization/` 和 `reports/m02_*`

---

## TASK-04：模块 3 — 深度分页与排序优化

### 目标
演示大 OFFSET 分页的浪费、延迟关联、游标分页方案。

### 场景
1. `LIMIT 2000000, 20` 大偏移扫描
2. 排序列无索引导致 FileSort
3. 延迟关联优化
4. 游标分页替代方案

### 产出物
与 TASK-02 同模式，路径为 `sql/m03_deep_pagination/` 和 `reports/m03_*`

---

## TASK-05：模块 4 — 锁竞争与死锁诊断

### 目标
使用并发负载工具制造锁竞争和死锁，诊断根因并修复。

### 场景
1. 并发 INSERT 二级唯一索引 → Gap Lock 竞争
2. 不同顺序 UPDATE → 死锁
3. 长事务锁等待

### 执行流程
1. Invoke **Spec Checker** → 微计划
2. Invoke **Concurrency Load and Lock Analyzer** → 并发负载脚本 + 指标采集 + 诊断
3. 编写修复脚本
4. 重新执行并发负载，验证死锁消除 / 吞吐提升
5. Invoke **Outcome Archiver** → 归档

### 产出物
- `scripts/concurrency_load.py`
- `reports/m04_lock_analysis.md`
- `reports/m04_comparison.md`
- `reports/archive_m04.md`

---

## TASK-06：模块 5 — 统计信息过期与执行计划漂移

### 目标
演示统计信息过期如何导致优化器选择错误的执行计划，及如何修复。

### 场景
1. 大量 INSERT 后不 ANALYZE → rows 估算严重偏低
2. 大量 DELETE 后索引选择性误判
3. 创建直方图优化 JOIN 列估算

### 产出物
与 TASK-02 同模式，路径为 `sql/m05_stale_statistics/` 和 `reports/m05_*`

---

## TASK-07：模块 6 — 子查询改写优化

### 目标
演示相关子查询、NOT IN 陷阱、派生表无索引等场景，改写为 JOIN/EXISTS/窗口函数。

### 场景
1. `IN (SELECT ...)` 退化为 DEPENDENT SUBQUERY
2. `NOT IN` + NULL 三值逻辑陷阱
3. 派生表物化后全表扫描
4. 标量子查询逐行执行

### 产出物
与 TASK-02 同模式，路径为 `sql/m06_subquery_rewrite/` 和 `reports/m06_*`

---

## TASK-08：全项目总结归档

### 目标
汇总 6 个模块的所有优化成果，生成最终的可演示报告。

### 具体操作
1. 生成 `results/final_summary.md` — 6 模块汇总对比表
2. 更新 `ARCHIVE_INDEX.md` — 确认所有档案已注册
3. 更新 `README.md` — 项目使用说明

### 产出物
- `results/final_summary.md`
- 更新 `README.md`

---

## 执行顺序

```
TASK-00 → TASK-01 → TASK-02 → TASK-03 → TASK-04 → TASK-05 → TASK-06 → TASK-07 → TASK-08
                      ↑
                      └── 所有模块任务依赖 TASK-01 的数据
                      
模块任务 (TASK-02~07) 之间无依赖，可并行或调整顺序
```

## 每个 TASK 的执行纪律

1. 启动前必须先调用 **Spec Checker** Skill 生成微计划
2. 微计划需用户批准后方可执行
3. 完成后必须调用 **Outcome Archiver** Skill 归档
4. 涉及索引变更时必须调用 **Index Impact Analyzer** Skill
5. 每个 TASK 的进度通过 `[TASK-LOG]` 标记追踪
