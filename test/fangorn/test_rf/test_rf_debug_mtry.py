"""
test_rf_debug_mtry.py — Verify mtry bug hypothesis.

Hypothesis: fangorn ignores mtry during tree building because
build_node_recursive always passes rng=NULL to find_best_split.
If so, mtry=1 and mtry=5 should give identical results.
"""

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import r2_score
import subprocess, os, tempfile

# ── Load data ──────────────────────────────────────────────────
df = pd.read_csv("test/fangorn/test_ent/ent_data.csv")
feature_names = ["x1", "x2", "x3", "x4", "x5"]
is_train = df["train"].values == 1
is_test = df["train"].values == 0

X = df[feature_names].values
y_reg = df["y_reg"].values
X_train, X_test = X[is_train], X[is_test]
y_train, y_test = y_reg[is_train], y_reg[is_test]

# ── 1. sklearn with mtry=1 (baseline) ─────────────────────────
rf1 = RandomForestRegressor(
    n_estimators=100,
    max_depth=10,
    min_samples_split=10,
    min_samples_leaf=3,
    min_impurity_decrease=0.0,
    bootstrap=True,
    max_features=1,
    random_state=42,
    n_jobs=1,
)
rf1.fit(X_train, y_train)
p1 = rf1.predict(X_test)
r2_1 = r2_score(y_test, p1)

# ── 2. sklearn with mtry=5 (all features) ────────────────────
rf5 = RandomForestRegressor(
    n_estimators=100,
    max_depth=10,
    min_samples_split=10,
    min_samples_leaf=3,
    min_impurity_decrease=0.0,
    bootstrap=True,
    max_features=5,
    random_state=42,
    n_jobs=1,
)
rf5.fit(X_train, y_train)
p5 = rf5.predict(X_test)
r2_5 = r2_score(y_test, p5)

print("═" * 55)
print("  SKLEARN — MTry Sensitivity Test (Regression)")
print("═" * 55)
print(f"  max_features=1: R² = {r2_1:.4f}")
print(f"  max_features=5: R² = {r2_5:.4f}")
print(f"      (all features)")
print()

# ── 3. Run fangorn with mtry=1 and mtry=5 ─────────────────────
# Create a Stata do-file dynamically
do_content = """
clear all
import delimited using "test/fangorn/test_ent/ent_data.csv", clear
destring, replace
rename train is_train
gen byte target = (is_train == 0)

fangorn y_reg x1 x2 x3 x4 x5, type(regress) generate(f1) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(mse) entcvdepth(0) ///
    target(target) ntree(100) mtry(1)

fangorn y_reg x1 x2 x3 x4 x5, type(regress) generate(f5) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(mse) entcvdepth(0) ///
    target(target) ntree(100) mtry(5)

keep id target f1_pred f5_pred y_reg is_train
export delimited using "test/fangorn/test_rf/fangorn_preds_mtry.csv", replace
"""

with tempfile.NamedTemporaryFile(suffix=".do", mode="w", delete=False) as f:
    f.write(do_content)
    do_path = f.name

subprocess.run(["stata", "-e", "do", do_path], capture_output=True)
os.unlink(do_path)

# ── 4. Load fangorn predictions ──────────────────────────────
df_fg = pd.read_csv("test/fangorn/test_rf/fangorn_preds_mtry.csv")
is_test_fg = df_fg["target"] == 1
p_f1 = df_fg.loc[is_test_fg, "f1_pred"].values
p_f5 = df_fg.loc[is_test_fg, "f5_pred"].values
y_test_fg = df_fg.loc[is_test_fg, "y_reg"].values

r2_f1 = r2_score(y_test_fg, p_f1)
r2_f5 = r2_score(y_test_fg, p_f5)

print("  FANGORN — MTry Sensitivity Test (Regression)")
print("─" * 55)
print(f"  mtry=1: R² = {r2_f1:.4f}")
print(f"  mtry=5: R² = {r2_f5:.4f}")
print()

# ── 5. Check if fangorn mtry=1 and mtry=5 give different results ─
diff = np.abs(p_f1 - p_f5).max()
print("═" * 55)
print("  DIAGNOSIS")
print("═" * 55)
print(f"  Max |fangorn(mtry=1) - fangorn(mtry=5)| = {diff:.8f}")
if diff < 1e-6:
    print("  >>> CONFIRMED: fangorn IGNORES mtry!")
    print("      mtry=1 and mtry=5 produce IDENTICAL predictions.")
else:
    print("  >>> mtry IS working (mtry=1 ≠ mtry=5).")
    print(f"      fangorn(mtry=1) R² = {r2_f1:.4f}")
    print(f"      fangorn(mtry=5) R² = {r2_f5:.4f}")

print()
print(f"  sklearn(max_f=1) R² = {r2_1:.4f}")
print(f"  fangorn(mtry=1)  R² = {r2_f1:.4f}  (should match skl mtry=1 if mtry works)")
print(f"  fangorn(mtry=5)  R² = {r2_f5:.4f}  (should match skl mtry=5 if mtry works)")
