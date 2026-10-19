# Data Cleaning Log

This document tracks the data quality rules applied during the ETL process from `staging.retail` to the `analytics` star schema.

| Rule | Action taken | Rows affected (Est.) | Reason |
|---|---|---:|---|
| `Customer ID` is NULL | Dropped from star schema (kept in staging) | 243,007 | Cannot attribute transaction to a customer for RFM/Churn analysis. |
| `Invoice` starts with 'C' | Flagged `is_cancellation = TRUE` | 18,334 | Kept for return-rate analysis. Excluded from revenue aggregations. |
| Negative `Quantity` | Flagged `is_cancellation = TRUE` | ~1,000 | Data entry adjustments or returns. |
| Non-product `StockCode` | Excluded from `dim_product` and `fact_sales` | 692 | Codes like TEST, ADJUST, POST, M, D, BANK CHARGES pollute product metrics. |
| Missing/Empty `Description` | Excluded from `dim_product` | 0 | None found in clean rows. |
| Inconsistent `Country` strings | Standardized via `MODE()` aggregation | ~50 | One customer might have multiple spellings (e.g., UK vs United Kingdom). Picked most frequent. |
| `InvoiceDate` null | Dropped | 0 | All rows had valid dates. |