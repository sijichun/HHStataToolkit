"""
test_benchmark.py — Unified DGP + sklearn benchmark (decision tree + random forest).

Generates n=10000 observations with both continuous and one-hot encoded categorical
features, complex non-linear DGP with interactions between continuous and categorical
variables. Trains sklearn models and exports data for fangorn (Stata) comparison.

Outputs:
  benchmark_data.csv        — full dataset for Stata import
  sk_cls_preds.csv          — sklearn classification predictions
  sk_reg_preds.csv          — sklearn regression predictions
"""

import numpy as np
import pandas as pd
import time
from sklearn.tree import DecisionTreeClassifier, DecisionTreeRegressor
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.metrics import accuracy_score, r2_score
import os

# ── Reproducibility ──────────────────────────────────────────────
rng = np.random.RandomState(42)

# ── Parameters ──────────────────────────────────────────────────
N = 10000
TEST_SIZE = 0.3
N_TREES = 100
TREE_PARAMS = dict(
    max_depth=10,
    min_samples_split=10,
    min_samples_leaf=3,
    min_impurity_decrease=0.0,
    random_state=42,
)

print("=" * 62)
print("  BENCHMARK — sklearn Decision Tree & Random Forest")
print("=" * 62)
print(f"  Observations:        {N}")
print(f"  Train/Test split:    {1 - TEST_SIZE:.0f}/{TEST_SIZE * 100:.0f}")
print(f"  RF trees:            {N_TREES}")
print(f"  max_depth:           {TREE_PARAMS['max_depth']}")
print(f"  min_samples_split:   {TREE_PARAMS['min_samples_split']}")
print(f"  min_samples_leaf:    {TREE_PARAMS['min_samples_leaf']}")
print("=" * 62)

# ═════════════════════════════════════════════════════════════════
# 1. Generate features: 5 continuous + 2 categorical (one-hot = 7 dummies)
# ═════════════════════════════════════════════════════════════════

x1 = rng.normal(0, 1, N)
x2 = rng.exponential(1, N)
x3 = rng.uniform(0, 2, N)
x4 = rng.normal(0, 2, N)
x5 = rng.normal(1, 1, N)

cat1 = rng.choice([0, 1, 2], N, p=[0.3, 0.4, 0.3])
cat2 = rng.choice([0, 1, 2, 3], N, p=[0.25, 0.25, 0.25, 0.25])

# One-hot encoding for cat1 (3 dummies)
cat1_A = (cat1 == 0).astype(float)
cat1_B = (cat1 == 1).astype(float)
cat1_C = (cat1 == 2).astype(float)

# One-hot encoding for cat2 (4 dummies)
cat2_X = (cat2 == 0).astype(float)
cat2_Y = (cat2 == 1).astype(float)
cat2_Z = (cat2 == 2).astype(float)
cat2_W = (cat2 == 3).astype(float)

# Full feature matrix (12 columns)
X = np.column_stack(
    [
        x1,
        x2,
        x3,
        x4,
        x5,
        cat1_A,
        cat1_B,
        cat1_C,
        cat2_X,
        cat2_Y,
        cat2_Z,
        cat2_W,
    ]
)
feature_names = [
    "x1",
    "x2",
    "x3",
    "x4",
    "x5",
    "cat1_0",
    "cat1_1",
    "cat1_2",
    "cat2_0",
    "cat2_1",
    "cat2_2",
    "cat2_3",
]

print(f"\n  Features: {len(feature_names)} (5 continuous + 7 one-hot dummies)")

# Effect of categorical variables (for DGP construction)
# cat1: A=0 → low boost, B=1 → medium boost, C=2 → high boost
cat1_effect = np.where(cat1 == 0, -0.5, np.where(cat1 == 1, 0.3, 0.8))
# cat2: X=0, Y=1, Z=2, W=3
cat2_effect = np.where(
    cat2 == 0, -0.3, np.where(cat2 == 1, 0.1, np.where(cat2 == 2, 0.4, -0.2))
)

# ═════════════════════════════════════════════════════════════════
# 2. Classification target (5 classes)
# ═════════════════════════════════════════════════════════════════

# Non-linear latent scores with interactions
z1 = (
    np.sin(x1 * 2)
    + 0.5 * np.sqrt(x2 + 0.1)
    - 0.3 * x3 * x4
    + 0.6 * cat1_effect
    + 0.4 * cat2_effect * x1
)
z2 = (
    np.cos(x3 * 1.5)
    + 0.4 * x5
    - 0.2 * x1 * x4
    + 0.3 * cat1_effect * cat2_effect
    - 0.5 * np.tanh(x2)
)
z3 = (
    x2 * np.tanh(x1) + 0.5 * np.abs(x4) * x5 + cat1_effect * 0.5 + 0.3 * np.sin(x1 * x3)
)
z4 = (
    0.5 * x1 * x3
    + 0.3 * np.sin(x5)
    - 0.2 * np.exp(-x2)
    + 0.4 * cat2_effect * np.cos(x4)
)
z5 = -(z1 + z2 + z3 + z4) / 4 + 0.3 * np.sin(x1)

class_score = np.column_stack([z1, z2, z3, z4, z5])
class_score += rng.normal(0, 1.0, size=class_score.shape)
y_cls = np.argmax(class_score, axis=1)
n_classes = len(np.unique(y_cls))
print(f"  Classification:      {n_classes} classes")

# ═════════════════════════════════════════════════════════════════
# 3. Regression target
# ═════════════════════════════════════════════════════════════════

y_reg = (
    2.0 * np.sin(x1 * 1.5)
    - 1.5 * np.log(x2 + 0.1)
    + 0.8 * x3 * x5
    + 0.5 * x1 * cat1_A
    - 0.3 * x4 * cat2_Z
    + 0.4 * cat2_W * np.sin(x1)
    + rng.normal(0, 0.6, N)
)

# ═════════════════════════════════════════════════════════════════
# 4. Train/test split
# ═════════════════════════════════════════════════════════════════

idx = np.arange(N)
rng.shuffle(idx)
n_train = int(N * (1 - TEST_SIZE))
train_idx = idx[:n_train]
test_idx = idx[n_train:]

X_train, X_test = X[train_idx], X[test_idx]
y_cls_train, y_cls_test = y_cls[train_idx], y_cls[test_idx]
y_reg_train, y_reg_test = y_reg[train_idx], y_reg[test_idx]

print(f"  Train observations:  {len(train_idx)}")
print(f"  Test observations:   {len(test_idx)}")
print(f"  Class distribution (train): {np.bincount(y_cls_train)}")
print(f"  Class distribution (test):  {np.bincount(y_cls_test)}")
print()

# ═════════════════════════════════════════════════════════════════
# 5. Export data for Stata
# ═════════════════════════════════════════════════════════════════

is_train = np.zeros(N, dtype=int)
is_train[train_idx] = 1

df = pd.DataFrame(
    np.column_stack([X, y_cls, y_reg, is_train, np.arange(N)]),
    columns=feature_names + ["y_cls", "y_reg", "train", "id"],
)
df["y_cls"] = df["y_cls"].astype(int)
df["train"] = df["train"].astype(int)
df["id"] = df["id"].astype(int)

os.makedirs("test/fangorn/benchmark", exist_ok=True)
df.to_csv("test/fangorn/benchmark/benchmark_data.csv", index=False)
print(
    f"  → Data exported: benchmark_data.csv ({N} rows, {len(feature_names)} features)"
)

# ═════════════════════════════════════════════════════════════════
# 6. sklearn Decision Tree benchmarks
# ═════════════════════════════════════════════════════════════════

dt_results = {}

for criterion, sk_crit in [("Gini", "gini"), ("Entropy", "entropy")]:
    t0 = time.time()
    clf = DecisionTreeClassifier(criterion=sk_crit, **TREE_PARAMS)
    clf.fit(X_train, y_cls_train)
    t1 = time.time()
    pred = clf.predict(X_test)
    acc = accuracy_score(y_cls_test, pred)
    dt_results[f"cls_{sk_crit}"] = {
        "accuracy": acc,
        "leaves": clf.get_n_leaves(),
        "depth": clf.get_depth(),
        "time_s": t1 - t0,
    }
    print(f"\n  ── sklearn DT Classification ({criterion}) ──")
    print(f"     Test accuracy:  {acc:.4f}")
    print(f"     Tree depth:     {clf.get_depth()}")
    print(f"     Leaf count:     {clf.get_n_leaves()}")
    print(f"     Train time:     {t1 - t0:.4f}s")

t0 = time.time()
reg = DecisionTreeRegressor(criterion="squared_error", **TREE_PARAMS)
reg.fit(X_train, y_reg_train)
t1 = time.time()
pred_reg = reg.predict(X_test)
r2 = r2_score(y_reg_test, pred_reg)
dt_results["reg_mse"] = {
    "r2": r2,
    "leaves": reg.get_n_leaves(),
    "depth": reg.get_depth(),
    "time_s": t1 - t0,
}
print("\n  ── sklearn DT Regression (MSE) ──")
print(f"     Test R²:        {r2:.4f}")
print(f"     Tree depth:     {reg.get_depth()}")
print(f"     Leaf count:     {reg.get_n_leaves()}")
print(f"     Train time:     {t1 - t0:.4f}s")

# Save sklearn decision tree predictions
clf_gini = DecisionTreeClassifier(criterion="gini", **TREE_PARAMS)
clf_gini.fit(X_train, y_cls_train)
clf_ent = DecisionTreeClassifier(criterion="entropy", **TREE_PARAMS)
clf_ent.fit(X_train, y_cls_train)
reg_dt = DecisionTreeRegressor(criterion="squared_error", **TREE_PARAMS)
reg_dt.fit(X_train, y_reg_train)

sk_dt_preds = pd.DataFrame(
    {
        "id": df.loc[test_idx, "id"].values.astype(int),
        "sk_cls_gini": clf_gini.predict(X_test).astype(int),
        "sk_cls_ent": clf_ent.predict(X_test).astype(int),
        "sk_reg": reg_dt.predict(X_test),
    }
)
sk_dt_preds.to_csv("test/fangorn/benchmark/sk_dt_preds.csv", index=False)
print("  → DT predictions saved: sk_dt_preds.csv")

# ═════════════════════════════════════════════════════════════════
# 7. sklearn Random Forest benchmarks
# ═════════════════════════════════════════════════════════════════

rf_params = dict(
    n_estimators=N_TREES,
    max_depth=10,
    min_samples_split=10,
    min_samples_leaf=3,
    min_impurity_decrease=0.0,
    bootstrap=True,
    random_state=42,
    n_jobs=1,
)

rf_results = {}

n_features = X.shape[1]
for criterion, sk_crit in [("Gini", "gini"), ("Entropy", "entropy")]:
    mtry = (
        max(1, int(np.sqrt(n_features)))
        if criterion == "Gini"
        else max(1, int(np.sqrt(n_features)))
    )
    t0 = time.time()
    rf = RandomForestClassifier(criterion=sk_crit, max_features=mtry, **rf_params)
    rf.fit(X_train, y_cls_train)
    t1 = time.time()
    pred = rf.predict(X_test)
    acc = accuracy_score(y_cls_test, pred)
    rf_results[f"cls_{sk_crit}"] = {
        "accuracy": acc,
        "time_s": t1 - t0,
        "mtry": mtry,
    }
    print(f"\n  ── sklearn RF Classification ({criterion}, mtry={mtry}) ──")
    print(f"     Test accuracy:  {acc:.4f}")
    print(f"     Train time:     {t1 - t0:.4f}s")

# Regression RF (mtry = n_features/3)
mtry_reg = max(1, int(n_features / 3))
t0 = time.time()
rf_reg = RandomForestRegressor(
    criterion="squared_error",
    max_features=mtry_reg,
    **rf_params,
)
rf_reg.fit(X_train, y_reg_train)
t1 = time.time()
pred_reg = rf_reg.predict(X_test)
r2 = r2_score(y_reg_test, pred_reg)
rf_results["reg_mse"] = {
    "r2": r2,
    "time_s": t1 - t0,
    "mtry": mtry_reg,
}
print(f"\n  ── sklearn RF Regression (mtry={mtry_reg}) ──")
print(f"     Test R²:        {r2:.4f}")
print(f"     Train time:     {t1 - t0:.4f}s")

# Save sklearn RF predictions
rf_clf_gini = RandomForestClassifier(criterion="gini", max_features=mtry, **rf_params)
rf_clf_gini.fit(X_train, y_cls_train)
rf_clf_ent = RandomForestClassifier(criterion="entropy", max_features=mtry, **rf_params)
rf_clf_ent.fit(X_train, y_cls_train)
rf_reg_sk = RandomForestRegressor(
    criterion="squared_error", max_features=mtry_reg, **rf_params
)
rf_reg_sk.fit(X_train, y_reg_train)

sk_rf_preds = pd.DataFrame(
    {
        "id": df.loc[test_idx, "id"].values.astype(int),
        "rf_cls_gini": rf_clf_gini.predict(X_test).astype(int),
        "rf_cls_ent": rf_clf_ent.predict(X_test).astype(int),
        "rf_reg": rf_reg_sk.predict(X_test),
    }
)
sk_rf_preds.to_csv("test/fangorn/benchmark/sk_rf_preds.csv", index=False)
print("\n  → RF predictions saved: sk_rf_preds.csv")

# ═════════════════════════════════════════════════════════════════
# 8. Summary table
# ═════════════════════════════════════════════════════════════════

print("\n" + "=" * 62)
print("  SKLEARN BENCHMARK SUMMARY")
print("=" * 62)
print(f"  {'─' * 60}")
print(f"  {'Model':<30} {'Metric':<12} {'Value':<10} {'Time(s)':<10}")
print(f"  {'─' * 60}")
for key, res in dt_results.items():
    if "cls" in key:
        print(
            f"  {'DT ' + key:<30} {'Accuracy':<12} {res['accuracy']:<10.4f} {res['time_s']:<10.4f}"
        )
    else:
        print(
            f"  {'DT ' + key:<30} {'R²':<12} {res['r2']:<10.4f} {res['time_s']:<10.4f}"
        )
for key, res in rf_results.items():
    if "cls" in key:
        print(
            f"  {'RF ' + key:<30} {'Accuracy':<12} {res['accuracy']:<10.4f} {res['time_s']:<10.4f}"
        )
    else:
        print(
            f"  {'RF ' + key:<30} {'R²':<12} {res['r2']:<10.4f} {res['time_s']:<10.4f}"
        )
print(f"  {'─' * 60}")
print()
print("  Data exported for Stata: test/fangorn/benchmark/benchmark_data.csv")
print("  Run: test/fangorn/benchmark/test_fangorn_benchmark.do")
