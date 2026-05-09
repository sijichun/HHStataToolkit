"""
test_rf_benchmark.py — Random Forest comparison: sklearn vs fangorn.

Uses the same data as test_ent (2000 obs, 5 correlated features).
Trains sklearn RandomForest and exports data for Stata fangorn.
"""

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.metrics import accuracy_score, mean_squared_error, r2_score
import os

# ── Load the same data as test_ent ──────────────────────────────
df = pd.read_csv("test/fangorn/test_ent/ent_data.csv")
feature_names = ["x1", "x2", "x3", "x4", "x5"]
n = len(df)

# Train/test split is encoded in the 'train' column
# (1=train, 0=test, same as ent_data.csv)
is_train = df["train"].values == 1
is_test = df["train"].values == 0

X = df[feature_names].values
y_cls = df["y_class"].values.astype(int)
y_reg = df["y_reg"].values

X_train, X_test = X[is_train], X[is_test]
y_cls_train, y_cls_test = y_cls[is_train], y_cls[is_test]
y_reg_train, y_reg_test = y_reg[is_train], y_reg[is_test]

n_train = X_train.shape[0]
n_test = X_test.shape[0]
print(f"Training observations: {n_train}")
print(f"Test observations:     {n_test}")

# ── sklearn Random Forest: Classification ──────────────────────
rng = np.random.RandomState(42)

params = dict(
    n_estimators=100,
    max_depth=10,
    min_samples_split=10,
    min_samples_leaf=3,
    min_impurity_decrease=0.0,
    bootstrap=True,
    random_state=42,
    n_jobs=1,
)

# Classification: Gini, mtry = sqrt(5) = 2
rf_clf = RandomForestClassifier(criterion="gini", max_features=2, **params)
rf_clf.fit(X_train, y_cls_train)
pred_clf = rf_clf.predict(X_test)
acc = accuracy_score(y_cls_test, pred_clf)
print(f"\n── sklearn Random Forest Classification (Gini) ──")
print(f"  Test accuracy: {acc:.4f}")
print(f"  n_estimators:  {rf_clf.n_estimators}")
print(f"  max_features:  2 (sqrt)")

# Classification: Entropy, mtry = 2
rf_ent = RandomForestClassifier(criterion="entropy", max_features=2, **params)
rf_ent.fit(X_train, y_cls_train)
pred_ent = rf_ent.predict(X_test)
acc_ent = accuracy_score(y_cls_test, pred_ent)
print(f"\n── sklearn Random Forest Classification (Entropy) ──")
print(f"  Test accuracy: {acc_ent:.4f}")

# ── sklearn Random Forest: Regression ──────────────────────────
# fangorn uses n_features/3 = 1 for regression mtry
rf_reg = RandomForestRegressor(
    criterion="squared_error",
    max_features=1,
    **params,
)
rf_reg.fit(X_train, y_reg_train)
pred_reg = rf_reg.predict(X_test)
mse = mean_squared_error(y_reg_test, pred_reg)
r2 = r2_score(y_reg_test, pred_reg)
print(f"\n── sklearn Random Forest Regression ──")
print(f"  Test MSE:  {mse:.4f}")
print(f"  Test R²:   {r2:.4f}")

# ── Save results ───────────────────────────────────────────────
results = {
    "rf_cls_gini_acc": acc,
    "rf_cls_ent_acc": acc_ent,
    "rf_reg_mse": mse,
    "rf_reg_r2": r2,
}

sk_pred = pd.DataFrame(
    {
        "id": df.loc[is_test, "id"].values.astype(int),
        "rf_cls_gini": pred_clf.astype(int),
        "rf_cls_ent": pred_ent.astype(int),
        "rf_reg": pred_reg,
    }
)
os.makedirs("test/fangorn/test_rf", exist_ok=True)
sk_pred.to_csv("test/fangorn/test_rf/sklearn_predictions.csv", index=False)
print("\nsklearn predictions saved to test/fangorn/test_rf/sklearn_predictions.csv")

# ── Summary table ──────────────────────────────────────────────
print("\n" + "=" * 60)
print("  SKLEARN RANDOM FOREST BENCHMARK SUMMARY")
print("=" * 60)
print(f"  {'Task':<25} {'Metric':<10} {'Value':<10}")
print(f"  {'─' * 25} {'─' * 10} {'─' * 10}")
print(f"  {'RF Cls Gini':<25} {'Accuracy':<10} {acc:.4f}")
print(f"  {'RF Cls Entropy':<25} {'Accuracy':<10} {acc_ent:.4f}")
print(f"  {'RF Regression':<25} {'R²':<10} {r2:.4f}")
print("=" * 60)
