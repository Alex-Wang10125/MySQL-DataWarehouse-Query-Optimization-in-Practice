# 技术架构链路梳理

## 1. 总体架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                          数据生成层 (Python)                         │
│  ┌─────────────┐   ┌──────────────┐   ┌────────────────────────┐   │
│  │ Faker 库     │   │ 加权随机分布  │   │ 倾斜/脏数据/NULL 注入   │   │
│  │ (姓名/地址)  │   │ (幂律/正态)   │   │ (is_deleted/VARCHAR陷阱)│   │
│  └─────────────┘   └──────────────┘   └────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│                    ┌──────────────────┐                             │
│                    │   CSV 中间文件    │  (5 个 CSV，总计 ~20M 行)    │
│                    └──────────────────┘                             │
└─────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          数据导入层 (MySQL)                          │
│  ┌──────────────────┐   ┌──────────────────┐   ┌────────────────┐  │
│  │ LOAD DATA INFILE │ → │ 二级索引构建      │ → │ 统计信息收集    │  │
│  │ (批量导入 5 表)   │   │ (外键/覆盖索引)   │   │ (ANALYZE TABLE) │  │
│  └──────────────────┘   └──────────────────┘   └────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       性能测试与优化层                                │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     Spec Checker (每个 Task 前)                │  │
│  │  生成 micro_plan → 用户批准 → 开始执行                          │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│                              ▼                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │               Performance Baseline Collector                  │  │
│  │  优化前 EXPLAIN + 5 次运行耗时 + 系统状态 → baseline_report    │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│                              ▼                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     执行优化 (SQL 脚本)                        │  │
│  │  建索引 / 改 SQL / 调参数 / 修复事务                           │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│                              ▼                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │               Performance Baseline Collector (再次)           │  │
│  │  优化后 EXPLAIN + 5 次运行耗时 + 系统状态 → optimized_report   │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│                              ▼                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │        对比报告 (comparison.md) + Outcome Archiver 归档        │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## 2. 数据链路

```
generate_data.py
  │
  ├── 1. 生成 customers (150w)  → data/customers.csv
  ├── 2. 生成 categories (500)  → data/categories.csv
  ├── 3. 生成 products (50w)    → data/products.csv
  ├── 4. 生成 orders (800w)     → data/orders.csv
  └── 5. 生成 order_items (1000w)→ data/order_items.csv
                                      │
                                      ▼
import_to_mysql.sql
  ├── LOAD DATA INFILE (5 表，按外键依赖顺序)
  ├── ALTER TABLE ADD PRIMARY KEY / INDEX
  └── ANALYZE TABLE (初始化统计信息)
```

**依赖关系**：customers / categories → products → orders → order_items

## 3. 模块执行链路

每个模块遵循统一流水线：

```
Spec Checker (微计划)
  → 问题 SQL 脚本编写
    → Baseline Collector (优化前基线)
      → 优化实施 (索引/改写/参数)
        → Baseline Collector (优化后基线)
          → Comparison 报告
            → Outcome Archiver (归档)
```

**模块间无强依赖**，可以任意顺序执行。建议按复杂度递进：
1. 模块 1（索引失效）— 最经典，立竿见影
2. 模块 6（子查询改写）— SQL 改写为主，不依赖索引
3. 模块 2（JOIN 策略）— 依赖索引模块的部分知识
4. 模块 3（深度分页）— 依赖索引知识
5. 模块 5（统计信息）— 依赖前面模块的数据积累
6. 模块 4（锁竞争）— 最独立，需要并发工具

## 4. Skill 调用关系

```
Stress Data Factory ──→ 生成数据 ──→ 供所有模块使用

Spec Checker ──→ 每个 Task 启动前调用

Performance Baseline Collector ──→ 每个模块在优化前后各调用一次

Index Impact Analyzer ──→ 模块 1/2/3/5/6 中涉及索引变更时调用

Concurrency Load and Lock Analyzer ──→ 仅在模块 4 中调用

Outcome Archiver ──→ 每个 Task 结束后调用
```

## 5. 目录结构

```
/home/alex/Projects_A/MySQL/
├── docs/
│   ├── PRD.md                        # 产品需求文档
│   ├── technical_architecture.md     # 本文档
│   └── technical_specification.md    # 技术规格文档
├── scripts/
│   ├── generate_data.py              # 数据生成脚本
│   ├── concurrency_load.py           # 并发测试脚本 (模块4)
│   └── benchmark.sh                  # 通用基准测试 shell
├── sql/
│   ├── 00_init_database.sql          # 建库 + 建表 DDL
│   ├── 01_import_data.sql            # LOAD DATA INFILE
│   ├── m01_index_failure/            # 模块1 SQL
│   │   ├── problem_queries.sql       # 问题 SQL
│   │   └── fix_scripts.sql           # 修复脚本
│   ├── m02_join_optimization/
│   ├── m03_deep_pagination/
│   ├── m04_lock_contention/
│   ├── m05_stale_statistics/
│   └── m06_subquery_rewrite/
├── data/                             # CSV 中间文件 (gitignore)
├── reports/                          # 所有报告、微计划、档案
│   ├── micro_plan_*.md
│   ├── baseline_report.md
│   ├── optimized_report.md
│   ├── comparison.md
│   ├── index_analysis.md
│   ├── lock_analysis.md
│   ├── data_generation_report.md
│   └── archive_*.md
├── results/                          # 最终汇总报告
├── .env                              # 数据库连接信息
├── .gitignore
└── README.md
```

## 6. 关键环境变量 (.env)

```
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=<password>
DB_NAME=mysql_optimization_db
DATA_DIR=./data
REPORTS_DIR=./reports
```
