-- =============================================================
-- CartIQ — ETL from staging → analytics star schema
-- (UCI Online Retail II)
-- =============================================================

-- Clean slate (idempotent)
TRUNCATE analytics.fact_sales, analytics.dim_customer,
         analytics.dim_product, analytics.dim_date
RESTART IDENTITY CASCADE;

-- -------------------------------------------------------------
-- DIM_DATE  (2009-12-01 → 2011-12-31)
-- -------------------------------------------------------------
INSERT INTO analytics.dim_date (date_key, year, quarter, month, month_name, week, day_of_week, is_weekend)
SELECT
    d::date,
    EXTRACT(YEAR    FROM d)::int,
    EXTRACT(QUARTER FROM d)::int,
    EXTRACT(MONTH   FROM d)::int,
    TO_CHAR(d, 'Mon'),
    EXTRACT(WEEK    FROM d)::int,
    TO_CHAR(d, 'Dy'),
    EXTRACT(ISODOW  FROM d) IN (6, 7)
FROM generate_series('2009-12-01'::date, '2011-12-31'::date, '1 day') AS d;

-- -------------------------------------------------------------
-- DIM_CUSTOMER  (only rows with a valid customer_id)
-- -------------------------------------------------------------
INSERT INTO analytics.dim_customer (customer_id, country)
SELECT
    customer_id,
    MODE() WITHIN GROUP (ORDER BY country) AS country    -- most common country per customer
FROM staging.retail
WHERE customer_id IS NOT NULL
  AND TRIM(customer_id) <> ''
GROUP BY customer_id;

-- -------------------------------------------------------------
-- DIM_PRODUCT  (only valid stock codes, drop TEST/ADJUST/etc.)
-- -------------------------------------------------------------
INSERT INTO analytics.dim_product (stock_code, description)
SELECT
    stock_code,
    MODE() WITHIN GROUP (ORDER BY description) AS description   -- most common description
FROM staging.retail
WHERE stock_code IS NOT NULL
  AND TRIM(stock_code) <> ''
  AND stock_code !~ '^(TEST|ADJUST|POST|DOT|M|D|C2|BANK CHARGES|PADS|SP1002|AMAZONFEE)$'  -- remove non-product codes
  AND description IS NOT NULL
GROUP BY stock_code;

-- -------------------------------------------------------------
-- FACT_SALES
-- - excludes guest purchases (NULL customer_id)
-- - flags cancellations (invoice starts with 'C' OR quantity < 0)
-- - excludes non-product stock codes
-- -------------------------------------------------------------
INSERT INTO analytics.fact_sales (
    invoice, customer_key, product_key, sale_date_key,
    quantity, price, revenue, is_cancellation
)
SELECT
    r.invoice,
    dc.customer_key,
    dp.product_key,
    r.invoice_date::date                                AS sale_date_key,
    r.quantity,
    r.price,
    ROUND((r.quantity * r.price)::numeric, 2)           AS revenue,
    (r.invoice LIKE 'C%' OR r.quantity < 0)             AS is_cancellation
FROM staging.retail r
JOIN analytics.dim_customer dc ON r.customer_id = dc.customer_id
LEFT JOIN analytics.dim_product dp ON r.stock_code = dp.stock_code
WHERE r.customer_id IS NOT NULL
  AND TRIM(r.customer_id) <> ''
  AND r.invoice_date IS NOT NULL;

-- -------------------------------------------------------------
-- INDEXES (for Power BI + downstream analysis)
-- -------------------------------------------------------------
CREATE INDEX idx_fact_sales_customer  ON analytics.fact_sales(customer_key);
CREATE INDEX idx_fact_sales_product   ON analytics.fact_sales(product_key);
CREATE INDEX idx_fact_sales_date      ON analytics.fact_sales(sale_date_key);
CREATE INDEX idx_fact_sales_invoice   ON analytics.fact_sales(invoice);
CREATE INDEX idx_fact_sales_cancel    ON analytics.fact_sales(is_cancellation);