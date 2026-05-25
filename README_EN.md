# MySQL Data Warehouse Query Optimization in Practice

A MySQL 8.4 query performance optimization project covering **index optimization, JOIN strategies, deep pagination, lock diagnostics, statistics management, and subquery rewriting** — six core scenarios with quantifiable results.

## Environment

| Component | Version/Config |
|---|---|
| MySQL | 8.4.8 (Ubuntu) |
| CPU | 4 cores |
| RAM | 3.3 GB |
| InnoDB Buffer Pool | 128 MB |
| Data Size | ~5M rows (5 tables) |

## Project Structure

```
.
├── sql/                          # SQL scripts
│   ├── 00_init_database.sql      # DDL
│   ├── 01_import_data.sql        # LOAD DATA INFILE import
│   ├── m01_index_failure/        # Module 1: Index Failure Diagnosis
│   ├── m02_join_optimization/    # Module 2: JOIN Strategy Optimization
│   ├── m03_deep_pagination/      # Module 3: Deep Pagination
│   ├── m04_lock_contention/      # Module 4: Lock Contention & Deadlock
│   ├── m05_stale_statistics/     # Module 5: Stale Statistics & Plan Drift
│   └── m06_subquery_rewrite/     # Module 6: Subquery Rewrite Optimization
├── scripts/                      # Python/Shell scripts
│   ├── generate_data.py          # Test data generation
│   ├── lock_demo_s1_gap_lock.sh  # Gap Lock demo
│   ├── lock_demo_s2_deadlock.sh  # AB-BA Deadlock demo
│   └── lock_demo_s3_lock_wait.sh # Lock wait timeout demo
├── reports/                      # Optimization reports & analysis
│   ├── m01_comparison.md ~ m06_comparison.md  # Module comparison reports
│   ├── index_analysis_m01.md ~ m03.md         # Index cost/benefit analysis
│   ├── m04_lock_analysis.md                   # Lock diagnostic report
│   ├── rollback_idx.sql                       # Index rollback script
│   └── data_generation_report.md              # Data generation report
├── results/                      # Final deliverables
│   └── final_summary.md          # Six-module summary
├── docs/                         # Design documents
│   ├── PRD.md                    # Product Requirements Document
│   ├── technical_architecture.md # Technical Architecture
│   ├── technical_specification.md # Technical Specification
│   └── task_breakdown.md         # Task Breakdown
├── data/                         # CSV files (gitignored)
├── README.md                     # Chinese README
└── README_EN.md                  # This file
```

## Six Optimization Modules

| # | Module | Scenarios | Key Results |
|---|---|---|---|
| 1 | **Index Failure Diagnosis** | 5 | 6 indexes (134 MB), 10× ~ 100,000× improvement |
| 2 | **JOIN Strategy Optimization** | 4 | 3 JOIN indexes (76 MB), NLJ+ref beats Hash Join, 4× ~ 212× |
| 3 | **Deep Pagination** | 4 | Cursor pagination 0.079ms (59,000×), deferred join 4~6× |
| 4 | **Lock Contention & Deadlock** | 3 | Gap Lock / AB-BA Deadlock / Long transaction reproduced & fixed |
| 5 | **Stale Statistics & Plan Drift** | 3 | ANALYZE TABLE + Histogram fix 12.9× underestimation |
| 6 | **Subquery Rewrite** | 4 | DEPENDENT SUBQUERY 6× improvement, NOT IN NULL trap fixed |

See [results/final_summary.md](results/final_summary.md) for detailed results.

## Quick Start

### 1. Environment Setup

```bash
sudo systemctl status mysql
sudo mysql < sql/00_init_database.sql
```

### 2. Generate & Import Test Data

```bash
pip3 install faker pymysql
python3 scripts/generate_data.py
sudo mysql mysql_optimization_db < sql/01_import_data.sql
```

### 3. Run Each Module

Each module directory contains:
- `00_setup_indexes.sql` — Create indexes
- `01_problem_queries.sql` — Problem queries (before optimization)
- `02_fix_queries.sql` — Fixed queries (after optimization)

```bash
mysql -u root mysql_optimization_db < sql/m01_index_failure/00_setup_indexes.sql
mysql -u root mysql_optimization_db < sql/m01_index_failure/01_problem_queries.sql
mysql -u root mysql_optimization_db < sql/m01_index_failure/02_fix_queries.sql
```

### 4. Lock Diagnostics (requires root)

```bash
bash scripts/lock_demo_s1_gap_lock.sh
bash scripts/lock_demo_s2_deadlock.sh
bash scripts/lock_demo_s3_lock_wait.sh
```

## Rollback

```bash
mysql -u root mysql_optimization_db < reports/rollback_idx.sql
```

## Key Takeaways

1. **Implicit type conversion** is the most insidious index killer
2. **Cursor-based pagination** (not deferred join) is the ultimate deep-pagination fix
3. **Consistent locking order** is the simplest deadlock prevention
4. **NOT IN** causes silent data loss — always use NOT EXISTS
5. **ANALYZE TABLE** is the immediate fix for stale stats; STATS_AUTO_RECALC=1 prevents it
6. MySQL 8.4's **Hash Join is a fallback** — NLJ+ref (with indexes) is always faster

## License

MIT
