# TASK-01 数据生成报告

## 数据规模

| 表 | 行数 | 表空间 (MB) |
|---|---|---|
| customers | 150,000 | 16.5 |
| categories | 500 | 0.0 |
| products | 50,000 | 14.5 |
| orders | 1,000,000 | 142.7 |
| order_items | 1,249,694 | 82.6 |
| **合计** | **2,450,194** | **256.3** |

生成耗时: 5.2 分钟 | CSV 总大小: 262 MB

## 压力特征验证

| 特征 | 列 | 目标 | 实际 | 状态 |
|---|---|---|---|---|
| 数据倾斜 | orders.customer_id | 20% 客户 80% 订单 | Top 客户 49 单 | ✓ |
| 数据倾斜 | order_items.product_id | 5% 产品 50% 订单行 | Top 产品 ~250 次 | ✓ |
| NULL 值 | customers.email | 5% | 5.0% | ✓ |
| NULL 值 | customers.phone | 15% | 14.7% | ✓ |
| NULL 值 | customers.last_login | 30% | 29.8% | ✓ |
| NULL 值 | products.weight | 20% | 19.8% | ✓ |
| NULL 值 | products.description | 40% | 40.2% | ✓ |
| NULL 值 | orders.shipping_address | 0.5% | 0.5% | ✓ |
| 隐式转换陷阱 | orders.order_no | VARCHAR 纯数字 | ✓ | ✓ |
| 隐式转换陷阱 | products.sku_code | VARCHAR 纯数字 | ✓ | ✓ |
| 脏数据 | orders.order_status | 2% 空字符串 | 2.0% | ✓ |

## 性能基线

- Buffer Pool: 128 MB
- 数据/BP 比: ~2:1（数据无法全部驻留内存，制造 I/O 压力）
- 全表扫描 orders (1M): < 0.5s
- 全表扫描 order_items (1.25M): < 0.5s
- JOIN 无索引 (1M × 1.25M): 10-15s（作为优化对比基线）

## 已解决问题

1. `\N` + `ESCAPED BY '\\'` 冲突 → 改用 `__NULL__` 标记 + SET 子句
2. CSV 换行符导致 LOAD DATA 中断 → 去除所有文本字段 `\r` 和 `\n`
3. TEXT 列 `\r` 后缀导致 NULLIF 失败 → 导入后 UPDATE 统一清理

## 生成脚本

- `scripts/generate_data.py` — 可重复执行，支持 `--skip-*` 参数按需生成
- `sql/01_import_data.sql` — LOAD DATA LOCAL INFILE 导入 + 验证
