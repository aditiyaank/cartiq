-- =============================================================
-- CartIQ — Load UCI Online Retail II CSV into staging
-- Windows-safe: relative path from cartiq/ folder
-- =============================================================

TRUNCATE staging.retail;

\copy staging.retail (invoice, stock_code, description, quantity, invoice_date, price, customer_id, country) FROM './data/raw/online_retail_II.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF8', NULL '');