#!/usr/bin/env python3
"""
TASK-01: 生成约 245 万行电商测试数据
压力特征: 数据倾斜、NULL、隐式转换陷阱、脏数据
"""
import csv
import os
import sys
import time
import random
import argparse
from datetime import datetime, timedelta

import numpy as np
from faker import Faker

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data')
os.makedirs(DATA_DIR, exist_ok=True)

# ============================================================
# 目标行数（适配 4C/4GB VM，128MB buffer pool）
# ============================================================
N_CUSTOMERS    = 150_000
N_CATEGORIES   = 500
N_PRODUCTS     = 50_000
N_ORDERS       = 1_000_000
# order_items 根据订单数自动推算 (~1,250,000)

BATCH_SIZE = 50000
DATE_START = datetime(2023, 1, 1)
DATE_END = datetime(2026, 5, 24)
PRODUCT_DATE_START = datetime(2021, 1, 1)
PRODUCT_DATE_END = datetime(2025, 12, 31)
REGISTER_DATE_START = datetime(2020, 1, 1)
REGISTER_DATE_END = datetime(2026, 5, 1)

def safe_str(val):
    """去除换行符和回车符，防止 CSV 行断裂"""
    return val.replace('\n',' ').replace('\r','') if isinstance(val, str) else str(val)

fake = Faker()
Faker.seed(42)
np.random.seed(42)
random.seed(42)

CITIES = [
    'Beijing', 'Shanghai', 'Guangzhou', 'Shenzhen', 'Hangzhou',
    'Chengdu', 'Nanjing', 'Wuhan', 'Chongqing', 'Tianjin',
    'Suzhou', "Xi'an", 'Changsha', 'Zhengzhou', 'Dalian',
    'Qingdao', 'Xiamen', 'Fuzhou', 'Hefei', 'Jinan',
    'Shenyang', 'Kunming', 'Nanchang', 'Changchun', 'Harbin',
    'Taiyuan', 'Nanning', 'Guiyang', 'Lanzhou', 'Haikou',
    'Yinchuan', 'Xining', 'Hohhot', 'Urumqi', 'Lhasa'
]
CITY_WEIGHTS = np.array([20,19,18,17,16] + [15]*5 + [10]*10 + [5]*10 + [2]*5, dtype=float)
CITY_WEIGHTS = CITY_WEIGHTS / CITY_WEIGHTS.sum()

CATEGORY_TREE = {
    'Electronics': ['Phones', 'Laptops', 'Tablets', 'Accessories', 'Audio'],
    'Clothing': ['Men', 'Women', 'Kids', 'Sports', 'Underwear'],
    'Home': ['Furniture', 'Kitchen', 'Bedding', 'Decor', 'Lighting'],
    'Food': ['Snacks', 'Beverages', 'Fresh', 'Frozen', 'Condiments'],
    'Beauty': ['Skincare', 'Makeup', 'Fragrance', 'Haircare', 'Bath'],
    'Sports': ['Fitness', 'Outdoor', 'Basketball', 'Football', 'Swimming'],
    'Books': ['Fiction', 'Non-Fiction', 'Children', 'Education', 'Comics'],
    'Toys': ['Building', 'Dolls', 'Puzzles', 'Remote', 'Educational'],
    'Auto': ['Parts', 'Tools', 'Electronics', 'Cleaning', 'Accessories'],
    'Health': ['Supplements', 'Devices', 'First Aid', 'Elderly', 'Baby Care'],
    'Office': ['Stationery', 'Furniture', 'Electronics', 'Paper', 'Files'],
    'Pet': ['Dog', 'Cat', 'Fish', 'Bird', 'Reptile'],
    'Garden': ['Plants', 'Tools', 'Seeds', 'Pots', 'Fertilizer'],
    'Jewelry': ['Gold', 'Silver', 'Diamond', 'Pearl', 'Watches'],
    'Luggage': ['Travel', 'Backpacks', 'Handbags', 'Wallets', 'Briefcases'],
    'Music': ['Instruments', 'Sheet Music', 'Accessories', 'Recording', 'Headphones'],
    'Art': ['Paintings', 'Sculptures', 'Prints', 'Crafts', 'Supplies'],
    'Baby': ['Diapers', 'Food', 'Clothing', 'Furniture', 'Safety'],
    'Software': ['OS', 'Office Suite', 'Antivirus', 'Development', 'Design'],
    'Industrial': ['Machinery', 'Safety', 'Measurement', 'Lab', 'Electrical'],
}

# MySQL NULL 表示 (通过 LOAD DATA SET 子句转 NULL)
NULL_MARKER = '__NULL__'

def random_date_str(start, end):
    delta = (end - start).total_seconds()
    d = start + timedelta(seconds=random.uniform(0, delta))
    return d.strftime('%Y-%m-%d %H:%M:%S')

def str_or_null(val):
    """空字符串 -> \\N"""
    return NULL_MARKER if val == '' or val is None else str(val)

def write_csv(filename, headers, generator_fn, total_rows):
    print(f"  -> {filename} ({total_rows:,} rows)", flush=True)
    filepath = os.path.join(DATA_DIR, filename)
    start_time = time.time()
    written = 0
    with open(filepath, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        while written < total_rows:
            batch = min(BATCH_SIZE, total_rows - written)
            rows = generator_fn(batch, written + 1)
            writer.writerows(rows)
            written += batch
            elapsed = time.time() - start_time
            rate = written / elapsed if elapsed > 0 else 0
            pct = written / total_rows * 100
            print(f"    {written:>12,} / {total_rows:,} ({pct:5.1f}%)  {rate:,.0f} rows/s", end='\r', flush=True)
    elapsed = time.time() - start_time
    print(f"\n    Done: {written:,} rows in {elapsed:.1f}s ({written/elapsed:,.0f} rows/s)", flush=True)
    return filepath

# ============================================================
# 1. categories
# ============================================================
def generate_categories():
    print("[1/5] Generating categories...", flush=True)
    rows = []
    cat_id = 1
    for parent_name, children in CATEGORY_TREE.items():
        rows.append([cat_id, parent_name, NULL_MARKER])
        parent_id = cat_id
        cat_id += 1
        for child_name in children:
            rows.append([cat_id, child_name, parent_id])
            cat_id += 1
    while len(rows) < N_CATEGORIES:
        parent_id = random.randint(1, len(CATEGORY_TREE))
        rows.append([cat_id, f'Sub_{cat_id}', parent_id])
        cat_id += 1
    filepath = os.path.join(DATA_DIR, 'categories.csv')
    with open(filepath, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['category_id', 'category_name', 'parent_category_id'])
        writer.writerows(rows[:N_CATEGORIES])
    print(f"  -> categories.csv: {N_CATEGORIES:,} rows", flush=True)

# ============================================================
# 2. customers
# ============================================================
def gen_customers_batch(n, start_id):
    rows = []
    levels = np.random.choice(['BRONZE','SILVER','GOLD','VIP'], size=n, p=[0.50,0.30,0.15,0.05])
    city_idx = np.random.choice(len(CITIES), size=n, p=CITY_WEIGHTS)
    null_email = np.random.random(n) < 0.05
    null_phone = np.random.random(n) < 0.15
    null_last_login = np.random.random(n) < 0.30
    statuses = np.where(np.random.random(n) < 0.05, 0, 1)
    for i in range(n):
        cid = start_id + i
        email = NULL_MARKER if null_email[i] else fake.email()
        phone = NULL_MARKER if null_phone[i] else fake.phone_number()
        reg = random_date_str(REGISTER_DATE_START, REGISTER_DATE_END)
        ll = NULL_MARKER if null_last_login[i] else random_date_str(
            datetime(2021,1,1), DATE_END)
        rows.append([cid, fake.name(), email, phone, reg,
                     levels[i], CITIES[city_idx[i]], ll, int(statuses[i])])
    return rows

# ============================================================
# 3. products
# ============================================================
def gen_products_batch(n, start_id):
    rows = []
    cat_ids = np.where(np.random.random(n) < 0.80,
                       np.random.randint(1, 51, size=n),
                       np.random.randint(51, N_CATEGORIES+1, size=n))
    prices = np.clip(np.random.lognormal(mean=5.0, sigma=0.8, size=n), 1.0, 50000.0)
    costs = prices * np.random.uniform(0.4, 0.8, size=n)
    stocks = np.random.randint(0, 10001, size=n)
    is_del = np.where(np.random.random(n) < 0.03, 1, 0)
    null_weight = np.random.random(n) < 0.20
    null_desc = np.random.random(n) < 0.40
    for i in range(n):
        pid = start_id + i
        w = NULL_MARKER if null_weight[i] else str(round(random.uniform(0.01, 50.0), 2))
        if null_desc[i]:
            d = NULL_MARKER
        else:
            d = fake.text(max_nb_chars=random.randint(100, 500)).replace('\n',' ').replace('\r','')
        rows.append([
            pid, f'{fake.catch_phrase()} {fake.word()}', int(cat_ids[i]),
            round(float(prices[i]), 2), round(float(costs[i]), 2),
            int(stocks[i]), str(1000000000 + pid),
            random_date_str(PRODUCT_DATE_START, PRODUCT_DATE_END),
            int(is_del[i]), w, d
        ])
    return rows

# ============================================================
# 4. orders (使用预生成 customer_id 避免逐批加权采样)
# ============================================================
PM_METHODS = ['ALIPAY']*8 + ['WECHAT']*7 + ['CARD']*3 + ['COD']*2

def build_order_cids():
    """Pareto: 20% 客户占 80% 订单"""
    print("    Pre-generating customer IDs (80-20 Pareto)...", flush=True)
    start = time.time()
    hot = int(N_CUSTOMERS * 0.20)
    ids = np.zeros(N_ORDERS, dtype=np.int64)
    hot_mask = np.random.random(N_ORDERS) < 0.80
    n_hot = hot_mask.sum()
    n_cold = N_ORDERS - n_hot
    ids[hot_mask] = np.random.randint(1, hot + 1, size=n_hot, dtype=np.int64)
    ids[~hot_mask] = np.random.randint(hot + 1, N_CUSTOMERS + 1, size=n_cold, dtype=np.int64)
    np.random.shuffle(ids)
    print(f"    Done: {N_ORDERS:,} IDs in {time.time()-start:.1f}s", flush=True)
    return ids

def gen_orders_batch(n, start_id, cids_slice):
    rows = []
    totals = np.round(np.random.lognormal(mean=4.5, sigma=1.0, size=n), 2)
    discounts = np.where(np.random.random(n) < 0.80, 0.0,
                         np.round(np.random.uniform(0, 30, size=n), 2))
    pms = np.random.choice(PM_METHODS, size=n)
    statuses = np.random.choice(
        ['COMPLETED','PENDING','SHIPPED','CANCELLED','REFUNDED','',''],
        size=n, p=[0.65,0.15,0.10,0.05,0.03,0.01,0.01])
    is_del = np.where(np.random.random(n) < 0.02, 1, 0)
    null_addr = np.random.random(n) < 0.005
    has_update = np.random.random(n) < 0.10
    for i in range(n):
        oid = start_id + i
        od_str = random_date_str(DATE_START, DATE_END)
        od_dt = datetime.strptime(od_str, '%Y-%m-%d %H:%M:%S')
        addr = NULL_MARKER if null_addr[i] else fake.address().replace('\n',', ').replace('\r','')
        up_str = random_date_str(od_dt, min(od_dt + timedelta(days=30), DATE_END)) if has_update[i] else od_str
        status_str = NULL_MARKER if statuses[i] == '' else statuses[i]
        rows.append([
            oid, od_dt.strftime('%Y%m%d') + str(oid % 100000).zfill(5),
            int(cids_slice[i]), od_str, float(totals[i]), float(discounts[i]),
            pms[i], status_str, addr, int(is_del[i]), od_str, up_str
        ])
    return rows

# ============================================================
# 5. order_items
# ============================================================
def build_product_ids(total_items):
    """Pareto: 5% 产品占 50% 订单行"""
    print("    Pre-generating product IDs (5-50 Pareto)...", flush=True)
    start = time.time()
    hot = int(N_PRODUCTS * 0.05)
    ids = np.zeros(total_items, dtype=np.int64)
    hot_mask = np.random.random(total_items) < 0.50
    ids[hot_mask] = np.random.randint(1, hot + 1, size=hot_mask.sum(), dtype=np.int64)
    ids[~hot_mask] = np.random.randint(hot + 1, N_PRODUCTS + 1, size=(~hot_mask).sum(), dtype=np.int64)
    np.random.shuffle(ids)
    print(f"    Done: {total_items:,} IDs in {time.time()-start:.1f}s", flush=True)
    return ids

def generate_all_order_items():
    print("\n[5/5] Generating order_items...", flush=True)
    print("    Computing item counts per order...", flush=True)
    item_counts = np.clip(np.random.poisson(lam=0.25, size=N_ORDERS) + 1, 1, 5)
    total_items = int(item_counts.sum())
    print(f"    Total order_items: {total_items:,}", flush=True)

    pids = build_product_ids(total_items)
    print("    Pre-generating prices, quantities...", flush=True)
    prices = np.clip(np.random.lognormal(mean=5.0, sigma=0.8, size=total_items), 1.0, 50000.0)
    qty_weights = [0.35,0.25,0.15,0.10,0.05,0.03,0.03,0.02,0.01,0.01]
    quantities = np.random.choice(range(1,11), size=total_items, p=qty_weights)

    filepath = os.path.join(DATA_DIR, 'order_items.csv')
    headers = ['item_id','order_id','product_id','quantity','unit_price',
               'subtotal','product_name_snapshot','created_at']
    print(f"  -> order_items.csv ({total_items:,} rows)", flush=True)
    start_time = time.time()
    next_id = 1
    orders_done = 0
    global_idx = 0

    with open(filepath, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(headers)
        while orders_done < N_ORDERS:
            batch = min(BATCH_SIZE, N_ORDERS - orders_done)
            batch_counts = item_counts[orders_done:orders_done+batch]
            rows = []
            for oi in range(batch):
                oid = orders_done + oi + 1
                for _ in range(batch_counts[oi]):
                    qty = int(quantities[global_idx])
                    price = round(float(prices[global_idx]), 2)
                    rows.append([
                        next_id, oid, int(pids[global_idx]), qty, price,
                        round(price * qty, 2), NULL_MARKER,
                        random_date_str(DATE_START, DATE_END)
                    ])
                    next_id += 1
                    global_idx += 1
            writer.writerows(rows)
            orders_done += batch
            elapsed = time.time() - start_time
            rate = next_id / elapsed if elapsed > 0 else 0
            print(f"    orders: {orders_done:>10,} / {N_ORDERS:,} -> {next_id-1:,} items ({rate:,.0f}/s)", end='\r', flush=True)

    total_out = next_id - 1
    elapsed = time.time() - start_time
    print(f"\n    Done: {total_out:,} rows in {elapsed:.1f}s ({total_out/elapsed:,.0f} rows/s)", flush=True)
    return filepath, total_out

# ============================================================
# 主流程
# ============================================================
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-categories', action='store_true')
    parser.add_argument('--skip-customers', action='store_true')
    parser.add_argument('--skip-products', action='store_true')
    parser.add_argument('--skip-orders', action='store_true')
    parser.add_argument('--skip-order-items', action='store_true')
    args = parser.parse_args()

    total_start = time.time()

    if not args.skip_categories:
        generate_categories()

    if not args.skip_customers:
        print(f"\n[2/5] Generating customers ({N_CUSTOMERS:,} rows)...", flush=True)
        write_csv('customers.csv',
            ['customer_id','customer_name','email','phone','register_date',
             'customer_level','city','last_login','status'],
            gen_customers_batch, N_CUSTOMERS)

    if not args.skip_products:
        print(f"\n[3/5] Generating products ({N_PRODUCTS:,} rows)...", flush=True)
        write_csv('products.csv',
            ['product_id','product_name','category_id','price','cost',
             'stock_quantity','sku_code','created_at','is_deleted','weight','description'],
            gen_products_batch, N_PRODUCTS)

    if not args.skip_orders:
        print(f"\n[4/5] Generating orders ({N_ORDERS:,} rows)...", flush=True)
        cids = build_order_cids()
        filepath = os.path.join(DATA_DIR, 'orders.csv')
        headers = ['order_id','order_no','customer_id','order_date',
                   'total_amount','discount_amount','payment_method','order_status',
                   'shipping_address','is_deleted','created_at','updated_at']
        print(f"  -> orders.csv ({N_ORDERS:,} rows)", flush=True)
        start_time = time.time()
        written = 0
        with open(filepath, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(headers)
            while written < N_ORDERS:
                batch = min(BATCH_SIZE, N_ORDERS - written)
                rows = gen_orders_batch(batch, written + 1, cids[written:written+batch])
                writer.writerows(rows)
                written += batch
                elapsed = time.time() - start_time
                rate = written / elapsed if elapsed > 0 else 0
                print(f"    {written:>12,} / {N_ORDERS:,} ({written/N_ORDERS*100:5.1f}%)  {rate:,.0f} rows/s", end='\r', flush=True)
        elapsed = time.time() - start_time
        print(f"\n    Done: {written:,} rows in {elapsed:.1f}s ({written/elapsed:,.0f} rows/s)", flush=True)

    if not args.skip_order_items:
        generate_all_order_items()

    total_elapsed = time.time() - total_start
    print(f"\n{'='*60}")
    print(f"Total time: {total_elapsed:.1f}s ({total_elapsed/60:.1f} min)")
    print(f"Data files in: {DATA_DIR}")
    total_size = 0
    for f in sorted(os.listdir(DATA_DIR)):
        size_mb = os.path.getsize(os.path.join(DATA_DIR, f)) / 1024 / 1024
        total_size += size_mb
        print(f"  {f}: {size_mb:.1f} MB")
    print(f"  Total: {total_size:.1f} MB")

if __name__ == '__main__':
    main()
