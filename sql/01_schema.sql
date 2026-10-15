-- =============================================================
-- CartIQ — UCI Online Retail II Star Schema
-- Layer 1: Staging (raw data from xlsx)
-- Layer 2: Analytics (fact + dim tables for Power BI)
-- =============================================================

-- -------------------------------------------------------------
-- SCHEMAS
-- -------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;

-- -------------------------------------------------------------
-- STAGING TABLE (raw transaction log, as-is)
-- -------------------------------------------------------------
DROP TABLE IF EXISTS staging.retail CASCADE;
CREATE TABLE staging.retail (
    invoice        VARCHAR(20),
    stock_code     VARCHAR(20),
    description    TEXT,
    quantity       INTEGER,
    invoice_date   TIMESTAMP,
    price          NUMERIC(10,4),
    customer_id    VARCHAR(20),
    country        VARCHAR(100)
);

-- -------------------------------------------------------------
-- ANALYTICS: DIMENSION TABLES
-- -------------------------------------------------------------
DROP TABLE IF EXISTS analytics.dim_customer CASCADE;
CREATE TABLE analytics.dim_customer (
    customer_key    SERIAL PRIMARY KEY,
    customer_id     VARCHAR(20) UNIQUE,
    country         VARCHAR(100)
);

DROP TABLE IF EXISTS analytics.dim_product CASCADE;
CREATE TABLE analytics.dim_product (
    product_key     SERIAL PRIMARY KEY,
    stock_code      VARCHAR(20) UNIQUE,
    description     TEXT
);

DROP TABLE IF EXISTS analytics.dim_date CASCADE;
CREATE TABLE analytics.dim_date (
    date_key        DATE PRIMARY KEY,
    year            INTEGER,
    quarter         INTEGER,
    month           INTEGER,
    month_name      VARCHAR(20),
    week            INTEGER,
    day_of_week     VARCHAR(20),
    is_weekend      BOOLEAN
);

-- -------------------------------------------------------------
-- ANALYTICS: FACT TABLE (one row per transaction line)
-- -------------------------------------------------------------
DROP TABLE IF EXISTS analytics.fact_sales CASCADE;
CREATE TABLE analytics.fact_sales (
    sale_key         SERIAL PRIMARY KEY,
    invoice          VARCHAR(20),
    customer_key     INTEGER REFERENCES analytics.dim_customer(customer_key),
    product_key      INTEGER REFERENCES analytics.dim_product(product_key),
    sale_date_key    DATE REFERENCES analytics.dim_date(date_key),
    quantity         INTEGER,
    price            NUMERIC(10,4),
    revenue          NUMERIC(12,2),    -- quantity * price
    is_cancellation  BOOLEAN,          -- true if invoice starts with 'C' or quantity < 0
    -- RFM fields (populated in the features layer)
    recency_days     INTEGER,
    frequency        INTEGER,
    monetary         NUMERIC(12,2),
    r_score          INTEGER,
    f_score          INTEGER,
    m_score          INTEGER,
    rfm_segment      VARCHAR(30),
    churn_risk       NUMERIC(5,4)      -- from XGBoost model
);

-- -------------------------------------------------------------
-- INDEXES
-- -------------------------------------------------------------
CREATE INDEX idx_fact_sales_customer  ON analytics.fact_sales(customer_key);
CREATE INDEX idx_fact_sales_product   ON analytics.fact_sales(product_key);
CREATE INDEX idx_fact_sales_date      ON analytics.fact_sales(sale_date_key);
CREATE INDEX idx_fact_sales_invoice   ON analytics.fact_sales(invoice);
CREATE INDEX idx_dim_customer_country ON analytics.dim_customer(country);
CREATE INDEX idx_dim_product_stock    ON analytics.dim_product(stock_code);