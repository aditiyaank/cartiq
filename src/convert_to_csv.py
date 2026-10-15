"""
Convert UCI Online Retail II xlsx → single CSV for Postgres loading.
Merges both year-sheets.
"""

import pandas as pd

SRC = "data/raw/online_retail_II.xlsx"
DST = "data/raw/online_retail_II.csv"

print("Reading Excel (both sheets)...")
sheets = pd.read_excel(SRC, sheet_name=None)   # dict of DataFrames

print(f"Sheets found: {list(sheets.keys())}")

df = pd.concat(sheets.values(), ignore_index=True)
print(f"Total rows: {len(df):,}")
print(f"Columns: {list(df.columns)}")

# Ensure consistent column names
df.columns = [
    "invoice", "stock_code", "description", "quantity",
    "invoice_date", "price", "customer_id", "country"
]

# Keep only what we need for staging (Customer ID stays for now — cleaned in ETL)
df = df[[
    "invoice", "stock_code", "description", "quantity",
    "invoice_date", "price", "customer_id", "country"
]]

# Write with proper date format
df.to_csv(DST, index=False)
print(f"\nWritten → {DST}")
print(f"Rows: {len(df):,}")