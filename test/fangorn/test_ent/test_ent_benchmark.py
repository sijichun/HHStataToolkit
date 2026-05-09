"""
test_ent_benchmark.py — Generate complex dataset, train sklearn decision trees,
export data for Stata fangorn, then compare test-set accuracy.

Generates 2000 observations with 5 correlated features, then creates:
1. A 4-class classification task with complex non-linear decision boundaries
2. A regression task with non-linear, interaction-rich functional form
"""

import numpy as np
import pandas as pd
from sklearn.tree import DecisionTreeClassifier, DecisionTreeRegressor
from sklearn.metrics import accuracy_score, mean_squared_error, r2_score
from sklearn.model_selection import train_test_split
import os

# ── Reproducibility ──────────────────────────────────────────────
rng = np.random.RandomState(42)

# ── 1. Generate 5 correlated features ──────────────────────────
n = 2000

# Covariance matrix: moderate positive correlations
cov = np.array(
    [
        [1.0, 0.6, 0.3, 0.2, 0.1],
        [0.6, 1.0, 0.5, 0.3, 0.2],
        [0.3, 0.5, 1.0, 0.4, 0.3],
        [0.2, 0.3, 0.4, 1.0, 0.5],
        [0.1, 0.2, 0.3, 0.5, 1.0],
    ]
)
mean = np.zeros(5)
X_raw = rng.multivariate_normal(mean, cov, size=n)

# Apply non-linear transformations to create realistic feature distributions
X = np.column_stack(
    [
        X_raw[:, 0],  # x1: raw normal
        np.exp(X_raw[:, 1] / 2),  # x2: lognormal-ish
        np.sign(X_raw[:, 2]) * (X_raw[:, 2] ** 2),  # x3: quadratic sign
        np.sin(X_raw[:, 3]) + 0.5 * X_raw[:, 3],  # x4: sin + linear
        np.tanh(X_raw[:, 4] * 1.5),  # x5: saturating
    ]
)

feature_names = ["x1", "x2", "x3", "x4", "x5"]

# ── 2. Multi-class (4-class) classification target ────────────
# Complex non-linear decision boundaries using multiple features
z1 = np.sin(X[:, 0]) + 0.5 * X[:, 1] - 0.3 * X[:, 2] ** 2
z2 = np.cos(X[:, 3]) + 0.4 * X[:, 4] + 0.2 * X[:, 0] * X[:, 3]
z3 = X[:, 1] * X[:, 4] - 0.5 * X[:, 2] + np.sin(X[:, 0] * 2)

# Combine into 4 classes with a non-linear partition
class_score = np.column_stack(
    [
        0.3 * z1 - 0.2 * z2 + 0.1 * z3,
        0.2 * z1 + 0.4 * z2 - 0.1 * z3,
        -0.3 * z1 + 0.1 * z2 + 0.3 * z3,
        -0.2 * z1 - 0.3 * z2 - 0.3 * z3,
    ]
)

# Add noise
class_score += rng.normal(0, 0.5, size=class_score.shape)

y_cls = np.argmax(class_score, axis=1)

# ── 3. Regression target ──────────────────────────────────────
# Complex non-linear function with interactions and noise
y_reg = (
    2.0 * np.sin(X[:, 0] * 1.5)
    - 1.5 * np.cos(X[:, 3] * 2.0)
    + 0.8 * X[:, 1] * X[:, 4]
    + 0.5 * X[:, 2] ** 2
    - 0.3 * X[:, 0] * X[:, 1]
    + 0.4 * np.exp(-(X[:, 4] ** 2)) * X[:, 3]
    + rng.normal(0, 0.6, size=n)
)

# ── 4. Train/test split (70/30) ────────────────────────────────
X_train, X_test, y_cls_train, y_cls_test, y_reg_train, y_reg_test = train_test_split(
    X, y_cls, y_reg, test_size=0.3, random_state=42
)

n_train = X_train.shape[0]
n_test = X_test.shape[0]
print(f"Training observations: {n_train}")
print(f"Test observations:     {n_test}")
print(f"\nClass distribution (train): {np.bincount(y_cls_train)}")
print(f"Class distribution (test):  {np.bincount(y_cls_test)}")

# ── 5. Export to CSV for Stata ─────────────────────────────────
# Combine into a single DataFrame
df_train = pd.DataFrame(
    np.column_stack(
        [
            X_train,
            y_cls_train,
            y_reg_train,
            np.ones(n_train, dtype=int),
            np.arange(n_train),
        ]
    ),
    columns=feature_names + ["y_class", "y_reg", "train", "id"],
)
df_test = pd.DataFrame(
    np.column_stack(
        [X_test, y_cls_test, y_reg_test, np.zeros(n_test, dtype=int), np.arange(n_test)]
    ),
    columns=feature_names + ["y_class", "y_reg", "train", "id"],
)
df = pd.concat([df_train, df_test], ignore_index=True)
df.to_csv("test/test_ent/ent_data.csv", index=False)
print("\nData exported to test/test_ent/ent_data.csv")

# ── 6. sklearn benchmark: classification ──────────────────────

# Define matching hyperparameters
params = dict(
    max_depth=10,
    min_samples_split=10,
    min_samples_leaf=3,
    min_impurity_decrease=0.0,
    random_state=42,
)

# Classification: Gini
clf_gini = DecisionTreeClassifier(criterion="gini", **params)
clf_gini.fit(X_train, y_cls_train)
pred_cls_gini = clf_gini.predict(X_test)
acc_gini = accuracy_score(y_cls_test, pred_cls_gini)
print(f"\n── sklearn Classification (Gini) ──")
print(f"  Test accuracy: {acc_gini:.4f}")
print(f"  Tree depth:    {clf_gini.get_depth()}")
print(f"  Leaf count:    {clf_gini.get_n_leaves()}")

# Classification: Entropy
clf_ent = DecisionTreeClassifier(criterion="entropy", **params)
clf_ent.fit(X_train, y_cls_train)
pred_cls_ent = clf_ent.predict(X_test)
acc_ent = accuracy_score(y_cls_test, pred_cls_ent)
print(f"\n── sklearn Classification (Entropy) ──")
print(f"  Test accuracy: {acc_ent:.4f}")
print(f"  Tree depth:    {clf_ent.get_depth()}")
print(f"  Leaf count:    {clf_ent.get_n_leaves()}")

# ── 7. sklearn benchmark: regression ───────────────────────────
reg = DecisionTreeRegressor(criterion="squared_error", **params)
reg.fit(X_train, y_reg_train)
pred_reg = reg.predict(X_test)
mse = mean_squared_error(y_reg_test, pred_reg)
r2 = r2_score(y_reg_test, pred_reg)
print(f"\n── sklearn Regression (MSE) ──")
print(f"  Test MSE:  {mse:.4f}")
print(f"  Test R²:   {r2:.4f}")
print(f"  Tree depth: {reg.get_depth()}")
print(f"  Leaf count: {reg.get_n_leaves()}")

# ── 8. sklearn: regularization tests ──────────────────────────
# min_impurity_decrease=0.01
clf_reg1 = DecisionTreeClassifier(
    criterion="gini",
    max_depth=10,
    min_samples_split=10,
    min_samples_leaf=3,
    min_impurity_decrease=0.01,
    random_state=42,
)
clf_reg1.fit(X_train, y_cls_train)
pred_reg1 = clf_reg1.predict(X_test)
acc_reg1 = accuracy_score(y_cls_test, pred_reg1)
print(f"\n── sklearn Classification: min_impurity_decrease=0.01 ──")
print(f"  Test accuracy: {acc_reg1:.4f}")
print(f"  Leaf count:    {clf_reg1.get_n_leaves()}")

# max_leaf_nodes=8
clf_reg2 = DecisionTreeClassifier(
    criterion="gini",
    max_depth=10,
    min_samples_split=10,
    min_samples_leaf=3,
    max_leaf_nodes=8,
    random_state=42,
)
clf_reg2.fit(X_train, y_cls_train)
pred_reg2 = clf_reg2.predict(X_test)
acc_reg2 = accuracy_score(y_cls_test, pred_reg2)
print(f"\n── sklearn Classification: max_leaf_nodes=8 ──")
print(f"  Test accuracy: {acc_reg2:.4f}")
print(f"  Leaf count:    {clf_reg2.get_n_leaves()}")

# ── Save sklearn results for comparison ────────────────────────
results = {
    "cls_gini_acc": acc_gini,
    "cls_gini_depth": clf_gini.get_depth(),
    "cls_gini_leaves": clf_gini.get_n_leaves(),
    "cls_ent_acc": acc_ent,
    "cls_ent_depth": clf_ent.get_depth(),
    "cls_ent_leaves": clf_ent.get_n_leaves(),
    "reg_mse": mse,
    "reg_r2": r2,
    "reg_depth": reg.get_depth(),
    "reg_leaves": reg.get_n_leaves(),
    "cls_reg1_acc": acc_reg1,
    "cls_reg1_leaves": clf_reg1.get_n_leaves(),
    "cls_reg2_acc": acc_reg2,
    "cls_reg2_leaves": clf_reg2.get_n_leaves(),
}

# Save predictions for cross-reference
sk_pred = pd.DataFrame(
    {
        "id": df_test["id"].values.astype(int),
        "sk_cls_gini": pred_cls_gini.astype(int),
        "sk_cls_ent": pred_cls_ent.astype(int),
        "sk_reg": pred_reg,
        "sk_cls_reg1": pred_reg1.astype(int),
        "sk_cls_reg2": pred_reg2.astype(int),
    }
)
sk_pred.to_csv("test/test_ent/sklearn_predictions.csv", index=False)
print("\nSklearn predictions saved to test/test_ent/sklearn_predictions.csv")

# ── Print summary table ────────────────────────────────────────
print("\n" + "=" * 60)
print("  SKLEARN BENCHMARK SUMMARY")
print("=" * 60)
print(f"  {'Task':<20} {'Metric':<12} {'Value':<10} {'Leaves':<8}")
print(f"  {'─' * 20} {'─' * 12} {'─' * 10} {'─' * 8}")
print(
    f"  {'Cls Gini':<20} {'Accuracy':<12} {acc_gini:.4f}     {clf_gini.get_n_leaves():<6}"
)
print(
    f"  {'Cls Entropy':<20} {'Accuracy':<12} {acc_ent:.4f}     {clf_ent.get_n_leaves():<6}"
)
print(f"  {'Regression':<20} {'R²':<12} {r2:.4f}     {reg.get_n_leaves():<6}")
print(
    f"  {'Cls reg1 (imp=0.01)':<20} {'Accuracy':<12} {acc_reg1:.4f}     {clf_reg1.get_n_leaves():<6}"
)
print(
    f"  {'Cls reg2 (leaf=8)':<20} {'Accuracy':<12} {acc_reg2:.4f}     {clf_reg2.get_n_leaves():<6}"
)
print("=" * 60)
