-- =============================================================
-- CartIQ — RFM segmentation + cohort retention + churn signal
-- (UCI Online Retail II)
-- =============================================================

-- -------------------------------------------------------------
-- STEP 1: Compute RFM per customer (purchases only, no cancellations)
-- -------------------------------------------------------------
DROP TABLE IF EXISTS analytics.rfm_scores CASCADE;
CREATE TABLE analytics.rfm_scores AS
WITH base AS (
    SELECT
        dc.customer_id,
        MAX(fs.sale_date_key)                          AS last_purchase_date,
        ('2011-12-09'::date - MAX(fs.sale_date_key))   AS recency_days,
        COUNT(DISTINCT fs.invoice)                     AS frequency,
        ROUND(SUM(fs.revenue)::numeric, 2)             AS monetary
    FROM analytics.fact_sales fs
    JOIN analytics.dim_customer dc ON fs.customer_key = dc.customer_key
    WHERE fs.is_cancellation = false
      AND fs.revenue > 0
    GROUP BY dc.customer_id
)
SELECT
    customer_id,
    last_purchase_date,
    recency_days,
    frequency,
    monetary,
    NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
    NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
    NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
FROM base;

-- -------------------------------------------------------------
-- STEP 2: Assign RFM segment labels
-- -------------------------------------------------------------
DROP TABLE IF EXISTS analytics.rfm_segments CASCADE;
CREATE TABLE analytics.rfm_segments AS
SELECT
    customer_id,
    last_purchase_date,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score) AS rfm_total,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 4 AND m_score >= 4                  THEN 'Loyal High Value'
        WHEN r_score >= 4                                    THEN 'New Customers'
        WHEN r_score <= 2 AND m_score >= 4                  THEN 'Lost High Value'
        WHEN r_score <= 2 AND m_score <= 2                  THEN 'Lost Low Value'
        WHEN r_score <= 3 AND m_score >= 4                  THEN 'At-Risk High Value'
        ELSE 'Others'
    END AS rfm_segment,
    -- Churn label: no purchase in last 90 days = churned
    CASE WHEN recency_days > 90 THEN 1 ELSE 0 END AS churned
FROM analytics.rfm_scores;

CREATE INDEX idx_rfm_seg ON analytics.rfm_segments(rfm_segment);
CREATE INDEX idx_rfm_churn ON analytics.rfm_segments(churned);

-- -------------------------------------------------------------
-- STEP 3: Push RFM + churn fields back into fact_sales
-- -------------------------------------------------------------
UPDATE analytics.fact_sales fs
SET
    recency_days = rs.recency_days,
    frequency    = rs.frequency,
    monetary     = rs.monetary,
    r_score      = rs.r_score,
    f_score      = rs.f_score,
    m_score      = rs.m_score,
    rfm_segment  = rs.rfm_segment,
    churn_risk   = rs.churned
FROM analytics.dim_customer dc
JOIN analytics.rfm_segments rs ON dc.customer_id = rs.customer_id
WHERE fs.customer_key = dc.customer_key;

-- -------------------------------------------------------------
-- STEP 4: Cohort retention (first-purchase month → M0..M12)
-- -------------------------------------------------------------
DROP TABLE IF EXISTS analytics.cohort_retention CASCADE;
CREATE TABLE analytics.cohort_retention AS
WITH first_purchase AS (
    SELECT
        dc.customer_id,
        MIN(DATE_TRUNC('month', fs.sale_date_key)) AS cohort_month
    FROM analytics.fact_sales fs
    JOIN analytics.dim_customer dc ON fs.customer_key = dc.customer_key
    WHERE fs.is_cancellation = false AND fs.revenue > 0
    GROUP BY dc.customer_id
),
customer_activity AS (
    SELECT
        dc.customer_id,
        DATE_TRUNC('month', fs.sale_date_key) AS activity_month
    FROM analytics.fact_sales fs
    JOIN analytics.dim_customer dc ON fs.customer_key = dc.customer_key
    WHERE fs.is_cancellation = false AND fs.revenue > 0
    GROUP BY dc.customer_id, DATE_TRUNC('month', fs.sale_date_key)
),
cohort_data AS (
    SELECT
        fp.cohort_month,
        ca.activity_month,
        (EXTRACT(YEAR  FROM AGE(ca.activity_month, fp.cohort_month)) * 12
       + EXTRACT(MONTH FROM AGE(ca.activity_month, fp.cohort_month)))::int AS month_number,
        ca.customer_id
    FROM first_purchase fp
    JOIN customer_activity ca USING (customer_id)
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS total_customers
    FROM first_purchase
    GROUP BY cohort_month
)
SELECT
    cd.cohort_month,
    cd.month_number,
    COUNT(DISTINCT cd.customer_id) AS active_customers,
    cs.total_customers,
    ROUND(100.0 * COUNT(DISTINCT cd.customer_id) / cs.total_customers, 2) AS retention_pct
FROM cohort_data cd
JOIN cohort_size cs USING (cohort_month)
GROUP BY cd.cohort_month, cd.month_number, cs.total_customers
ORDER BY cd.cohort_month, cd.month_number;

-- -------------------------------------------------------------
-- STEP 5: Churn drivers — RFM segment summary
-- -------------------------------------------------------------
DROP TABLE IF EXISTS analytics.churn_drivers CASCADE;
CREATE TABLE analytics.churn_drivers AS
SELECT
    rfm_segment,
    COUNT(*)                          AS customers,
    SUM(churned)                      AS churned_customers,
    ROUND(100.0 * SUM(churned) / COUNT(*), 2) AS churn_rate_pct,
    ROUND(AVG(recency_days), 1)       AS avg_recency_days,
    ROUND(AVG(frequency), 2)          AS avg_frequency,
    ROUND(AVG(monetary), 2)           AS avg_monetary,
    ROUND(SUM(monetary), 2)           AS segment_revenue
FROM analytics.rfm_segments
GROUP BY rfm_segment
ORDER BY segment_revenue DESC;