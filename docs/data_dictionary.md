# Data Dictionary

## Analytics Schema (Star Schema)

### `fact_sales`
| Column | Type | Description |
|---|---|---|
| `sale_key` | SERIAL PK | Surrogate key |
| `invoice` | VARCHAR | Invoice number (includes 'C' for cancellations) |
| `customer_key` | INT FK | Links to `dim_customer` |
| `product_key` | INT FK | Links to `dim_product` |
| `sale_date_key` | DATE FK | Links to `dim_date` |
| `quantity` | INT | Number of units |
| `price` | NUMERIC | Unit price in GBP (£) |
| `revenue` | NUMERIC | `quantity * price` |
| `is_cancellation` | BOOLEAN | TRUE if return/cancellation |
| `recency_days` | INT | Days since last purchase (populated via RFM script) |
| `rfm_segment` | VARCHAR | Segment label (e.g., 'Champions') |
| `churn_risk` | NUMERIC | ML predicted probability of churn (0.0 to 1.0) |

### `dim_customer`
| Column | Type | Description |
|---|---|---|
| `customer_key` | SERIAL PK | Surrogate key |
| `customer_id` | VARCHAR | Original 5-digit ID from source |
| `country` | VARCHAR | Standardized customer country |

### `dim_product`
| Column | Type | Description |
|---|---|---|
| `product_key` | SERIAL PK | Surrogate key |
| `stock_code` | VARCHAR | Original SKU code |
| `description` | VARCHAR | Standardized product name |

### `dim_date`
| Column | Type | Description |
|---|---|---|
| `date_key` | DATE PK | Calendar date |
| `year` | INT | e.g., 2011 |
| `quarter` | INT | 1 to 4 |
| `month` | INT | 1 to 12 |
| `month_name` | VARCHAR | e.g., 'Jan' |
| `is_weekend` | BOOLEAN | TRUE for Saturday/Sunday |