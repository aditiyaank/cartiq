"""
CartIQ — XGBoost customer churn prediction (UCI Online Retail II)
Time-based setup:
  - Features: customer behavior BEFORE 2011-09-09
  - Label:    did customer buy AFTER 2011-09-09 (within data window)?
Predicts which customers are about to churn.
"""

import os
import pandas as pd
import numpy as np
import joblib
from sqlalchemy import create_engine, text
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    roc_auc_score, precision_score, recall_score,
    f1_score, classification_report, confusion_matrix,
    average_precision_score
)
from xgboost import XGBClassifier
import shap
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ---------------------------------------------------------
# CONFIG  →  CHANGE PASSWORD
# ---------------------------------------------------------
from config import DB_URL
OUTPUT_DIR = "reports"
MODEL_DIR  = "src/artifacts"
CUTOFF     = "2011-09-09"   # 90 days before dataset end

os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(MODEL_DIR, exist_ok=True)


# ---------------------------------------------------------
# 1. LOAD FEATURES (pre-cutoff) + LABEL (post-cutoff)
# ---------------------------------------------------------
def load_features(engine, cutoff):
    query = f"""
    WITH pre AS (
        -- Only purchases BEFORE cutoff (exclude cancellations)
        SELECT
            dc.customer_id,
            fs.invoice,
            fs.sale_date_key,
            fs.quantity,
            fs.price,
            fs.revenue,
            fs.product_key
        FROM analytics.fact_sales fs
        JOIN analytics.dim_customer dc ON fs.customer_key = dc.customer_key
        WHERE fs.is_cancellation = false
          AND fs.revenue > 0
          AND fs.sale_date_key < DATE '{cutoff}'
    ),
    cust_agg AS (
        SELECT
            customer_id,
            MAX(sale_date_key)                    AS last_purchase,
            MIN(sale_date_key)                    AS first_purchase,
            (DATE '{cutoff}' - MAX(sale_date_key)) AS recency_days,
            (MAX(sale_date_key) - MIN(sale_date_key)) AS tenure_days,
            COUNT(DISTINCT invoice)               AS frequency,
            COUNT(DISTINCT product_key)           AS n_products,
            SUM(revenue)                          AS monetary,
            AVG(revenue)                          AS avg_line_value,
            SUM(revenue) / NULLIF(COUNT(DISTINCT invoice), 0) AS avg_order_value,
            COUNT(*)                              AS total_lines
        FROM pre
        GROUP BY customer_id
    ),
    label_cte AS (
        -- Did they buy in the 90-day window AFTER cutoff?
        SELECT
            dc.customer_id,
            MAX(CASE WHEN fs.sale_date_key >= DATE '{cutoff}' THEN 1 ELSE 0 END) AS returned
        FROM analytics.fact_sales fs
        JOIN analytics.dim_customer dc ON fs.customer_key = dc.customer_key
        WHERE fs.is_cancellation = false AND fs.revenue > 0
        GROUP BY dc.customer_id
    )
    SELECT
        ca.customer_id,
        ca.recency_days,
        ca.tenure_days,
        ca.frequency,
        ca.n_products,
        ca.monetary,
        ca.avg_line_value,
        ca.avg_order_value,
        ca.total_lines,
        (ca.n_products::float / NULLIF(ca.frequency, 0)) AS products_per_order,
        (ca.monetary / NULLIF(ca.tenure_days, 0))        AS revenue_per_day,
        dc.country,
        COALESCE(lc.returned, 0) AS returned
    FROM cust_agg ca
    JOIN analytics.dim_customer dc ON ca.customer_id = dc.customer_id
    LEFT JOIN label_cte lc ON ca.customer_id = lc.customer_id;
    """
    return pd.read_sql(query, engine)


# ---------------------------------------------------------
# 2. PREPARE
# ---------------------------------------------------------
def prepare(df):
    y = (1 - df["returned"].astype(int))   # 1 = churned (did NOT return)
    X = df.drop(columns=["customer_id", "returned"]).copy()

    num_cols = X.select_dtypes(include=[np.number]).columns
    X[num_cols] = X[num_cols].fillna(0)

    cat_cols = X.select_dtypes(include=["object", "string"]).columns
    X[cat_cols] = X[cat_cols].fillna("unknown")
    X = pd.get_dummies(X, columns=cat_cols, drop_first=True, dtype=int)

    return X, y


# ---------------------------------------------------------
# 3. TRAIN
# ---------------------------------------------------------
def train(X, y):
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    pos = (y_train == 1).sum()
    neg = (y_train == 0).sum()
    spw = neg / max(pos, 1)
    print(f"Train — churned: {pos:,} | active: {neg:,} | spw: {spw:.2f}")

    model = XGBClassifier(
        n_estimators=500,
        max_depth=5,
        learning_rate=0.05,
        subsample=0.85,
        colsample_bytree=0.85,
        min_child_weight=3,
        scale_pos_weight=spw,
        eval_metric="auc",
        random_state=42,
        n_jobs=-1,
    )
    model.fit(X_train, y_train)

    y_proba = model.predict_proba(X_test)[:, 1]
    y_pred  = (y_proba >= 0.5).astype(int)

    metrics = {
        "AUC":       round(roc_auc_score(y_test, y_proba), 4),
        "PR-AUC":    round(average_precision_score(y_test, y_proba), 4),
        "Precision": round(precision_score(y_test, y_pred, zero_division=0), 4),
        "Recall":    round(recall_score(y_test, y_pred, zero_division=0), 4),
        "F1":        round(f1_score(y_test, y_pred, zero_division=0), 4),
    }
    print("\n=== MODEL METRICS ===")
    for k, v in metrics.items():
        print(f"{k:10s}: {v}")
    print("\n", classification_report(y_test, y_pred, zero_division=0))
    print("Confusion matrix:\n", confusion_matrix(y_test, y_pred))
    return model, X_train, X_test, y_test, y_proba, metrics


# ---------------------------------------------------------
# 4. SHAP
# ---------------------------------------------------------
def shap_analysis(model, X_train, output_dir):
    X_sample = X_train.sample(n=min(3000, len(X_train)), random_state=42)
    explainer = shap.TreeExplainer(model)
    shap_values = explainer.shap_values(X_sample)

    plt.figure()
    shap.summary_plot(shap_values, X_sample, plot_type="bar", show=False, max_display=15)
    plt.tight_layout()
    plt.savefig(f"{output_dir}/shap_importance.png", dpi=150, bbox_inches="tight")
    plt.close()

    plt.figure()
    shap.summary_plot(shap_values, X_sample, show=False, max_display=15)
    plt.tight_layout()
    plt.savefig(f"{output_dir}/shap_beeswarm.png", dpi=150, bbox_inches="tight")
    plt.close()

    print(f"\nSHAP plots saved → {output_dir}/")


# ---------------------------------------------------------
# 5. SCORE + WRITE BACK
# ---------------------------------------------------------
def score_and_write(engine, model, X_all, df_original):
    scores = model.predict_proba(X_all)[:, 1]
    result = df_original[["customer_id"]].copy()
    result["churn_prob"] = scores.round(4)
    result["monetary"]   = df_original["monetary"].values

    # Top 500 highest churn risk
    top500 = result.sort_values("churn_prob", ascending=False).head(500)
    top500.to_csv(f"{OUTPUT_DIR}/top_500_at_risk_customers.csv", index=False)
    print(f"\nTop-500 at-risk CSV → {OUTPUT_DIR}/top_500_at_risk_customers.csv")

    # Save all scores
    result.to_csv(f"{OUTPUT_DIR}/all_customer_churn_scores.csv", index=False)

    # Write back to Postgres
    with engine.begin() as conn:
        conn.execute(text("""
            ALTER TABLE analytics.dim_customer
            ADD COLUMN IF NOT EXISTS churn_prob NUMERIC(5,4);
        """))
        conn.execute(text("""
            CREATE TEMP TABLE tmp_churn (
                customer_id VARCHAR(20),
                churn_prob NUMERIC(5,4)
            );
        """))
        result[["customer_id", "churn_prob"]].to_sql(
            "tmp_churn", conn, if_exists="append", index=False, method="multi"
        )
        conn.execute(text("""
            UPDATE analytics.dim_customer dc
            SET churn_prob = tmp.churn_prob
            FROM tmp_churn tmp
            WHERE dc.customer_id = tmp.customer_id;
        """))
    print("churn_prob written back to analytics.dim_customer")


# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------
if __name__ == "__main__":
    print("Connecting to Postgres...")
    engine = create_engine(DB_URL)

    print(f"Loading features (cutoff = {CUTOFF})...")
    df = load_features(engine, CUTOFF)
    print(f"Rows: {len(df):,} | Churn rate: {(1 - df['returned'].mean()):.2%}")

    X, y = prepare(df)
    print(f"Feature matrix: {X.shape}")

    model, X_train, X_test, y_test, y_proba, metrics = train(X, y)

    shap_analysis(model, X_train, OUTPUT_DIR)

    joblib.dump(model, f"{MODEL_DIR}/churn_model.pkl")
    print(f"\nModel saved → {MODEL_DIR}/churn_model.pkl")

    score_and_write(engine, model, X, df)
    print("\n✅ Done.")