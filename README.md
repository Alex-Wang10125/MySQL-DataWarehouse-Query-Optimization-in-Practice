# MySQL 数仓查询优化实战

基于 MySQL 8.4 的数仓查询性能优化项目，覆盖 **索引优化、JOIN 策略、深度分页、锁诊断、统计信息、子查询改写** 六大核心场景，每个场景均有可量化的优化成果。

## 环境

| 组件 | 版本/配置 |
|---|---|
| MySQL | 8.4.8 (Ubuntu) |
| CPU | 4 核 |
| 内存 | 3.3 GB |
| InnoDB Buffer Pool | 128 MB |
| 数据量 | ~500 万行 (5 表) |

## 项目结构

```
.
├── sql/                          # SQL 脚本
│   ├── 00_init_database.sql      # 建库建表 DDL
│   ├── 01_import_data.sql        # LOAD DATA INFILE 导入
│   ├── m01_index_failure/        # 模块1: 索引失效诊断与修复
│   ├── m02_join_optimization/    # 模块2: 大表 JOIN 策略优化
│   ├── m03_deep_pagination/      # 模块3: 深度分页与排序优化
│   ├── m04_lock_contention/      # 模块4: 锁竞争与死锁诊断
│   ├── m05_stale_statistics/     # 模块5: 统计信息过期与计划漂移
│   └── m06_subquery_rewrite/     # 模块6: 子查询改写优化
├── scripts/                      # Python/Shell 脚本
│   ├── generate_data.py          # 测试数据生成
│   ├── lock_demo_s1_gap_lock.sh  # Gap Lock 复现
│   ├── lock_demo_s2_deadlock.sh  # AB-BA 死锁复现
│   └── lock_demo_s3_lock_wait.sh # 长事务锁等待复现
├── reports/                      # 优化报告与分析
│   ├── m01_comparison.md ~ m06_comparison.md  # 6 个模块对比报告
│   ├── index_analysis_m01.md ~ m03.md         # 索引成本收益分析
│   ├── m04_lock_analysis.md                   # 锁诊断分析
│   ├── rollback_idx.sql                       # 索引回滚脚本
│   └── data_generation_report.md              # 数据生成报告
├── results/                      # 最终成果
│   └── final_summary.md          # 六大模块汇总
├── docs/                         # 设计文档
│   ├── PRD.md                    # 产品需求文档
│   ├── technical_architecture.md # 技术架构
│   ├── technical_specification.md # 技术规格
│   └── task_breakdown.md         # 任务拆分
├── data/                         # CSV 数据文件 (gitignore)
├── README.md                     # 本文件
└── README_EN.md                  # English version
```

## 六大优化模块

| # | 模块 | 场景 | 核心成果 |
|---|---|---|---|
| 1 | **索引失效诊断与修复** | 5 | 6 个索引 (134 MB), 查询提升 10× ~ 100,000× |
| 2 | **大表 JOIN 策略优化** | 4 | 3 个 JOIN 键索引 (76 MB), NLJ+ref 优于 Hash Join, 提升 4× ~ 212× |
| 3 | **深度分页与排序优化** | 4 | 游标分页 0.079ms (提升 59,000×), 延迟关联 4~6× |
| 4 | **锁竞争与死锁诊断** | 3 | Gap Lock / AB-BA 死锁 / 长事务复现与修复 |
| 5 | **统计信息过期与计划漂移** | 3 | ANALYZE TABLE + 直方图修复 rows 低估 12.9× |
| 6 | **子查询改写优化** | 4 | DEPENDENT SUBQUERY 6× 提升, NOT IN NULL 陷阱修复 |

详细成果见 [results/final_summary.md](results/final_summary.md)。

## 快速开始

### 1. 环境准备

```bash
# 确认 MySQL 运行
sudo systemctl status mysql

# 创建数据库
sudo mysql < sql/00_init_database.sql
```

### 2. 生成并导入测试数据

```bash
# 安装 Python 依赖
pip3 install faker pymysql

# 生成 CSV 数据
python3 scripts/generate_data.py

# 导入 MySQL
sudo mysql mysql_optimization_db < sql/01_import_data.sql
```

### 3. 按模块执行

每个模块目录包含:
- `00_setup_indexes.sql` — 创建索引 (如有)
- `01_problem_queries.sql` — 问题 SQL (优化前)
- `02_fix_queries.sql` — 修复 SQL (优化后)

```bash
# 示例: 执行模块1
mysql -u root mysql_optimization_db < sql/m01_index_failure/00_setup_indexes.sql
mysql -u root mysql_optimization_db < sql/m01_index_failure/01_problem_queries.sql
mysql -u root mysql_optimization_db < sql/m01_index_failure/02_fix_queries.sql
```

### 4. 锁诊断 (需要 root 权限)

```bash
bash scripts/lock_demo_s1_gap_lock.sh
bash scripts/lock_demo_s2_deadlock.sh
bash scripts/lock_demo_s3_lock_wait.sh
```

## 回滚

```bash
mysql -u root mysql_optimization_db < reports/rollback_idx.sql
```

## 关键经验

1. **隐式类型转换**是最隐蔽的索引杀手
2. **游标分页**是深分页的最终解决方案 (不是延迟关联)
3. **统一加锁顺序**是最简单的死锁预防策略
4. **NOT IN** 是静默数据丢失元凶 — 永远用 NOT EXISTS
5. **ANALYZE TABLE** 是统计信息问题的即时修复, STATS_AUTO_RECALC=1 是预防
6. MySQL 8.4 的 **Hash Join 是 fallback** — NLJ+ref (有索引) 总是更快

## 许可

MIT
