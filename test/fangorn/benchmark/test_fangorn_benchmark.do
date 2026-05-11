*! test_fangorn_benchmark.do
* Unified benchmark: fangorn decision tree + random forest vs sklearn
* Prerequisites: plugin built via `make fangorn && make install`, then
*   run test/fangorn/benchmark/test_benchmark.py to generate data and sklearn baseline

clear all
set more off

* ── 1. Import data ───────────────────────────────────────────
import delimited using "test/fangorn/benchmark/benchmark_data.csv", clear
destring, replace

* Data has: x1-x5, cat1_0-cat1_2, cat2_0-cat2_3, y_cls, y_reg, train, id
* train=1 = training set, train=0 = test set
rename train is_train

* fangorn: target=0=train, target=1=test
gen byte target = (is_train == 0)

count if is_train == 1
local n_train = r(N)
count if is_train == 0
local n_test = r(N)

di _n "{hline 62}"
di "  FANGORN BENCHMARK"
di "{hline 62}"
di "  Observations:      `n_train' train, `n_test' test"
di "  Features:          x1-x5, cat1_0-cat1_2, cat2_0-cat2_3 (12 total)"
di "  Classification:    5 classes"
di "  RF trees:          100"
di "{hline 62}"

local features x1 x2 x3 x4 x5 cat1_0 cat1_1 cat1_2 cat2_0 cat2_1 cat2_2 cat2_3

* ═════════════════════════════════════════════════════════════════
* 2. Decision Tree benchmarks
* ═════════════════════════════════════════════════════════════════

di _n "{hline 62}"
di "── fangorn Decision Tree ──"

* DT Classification: Gini
timer clear
timer on 1
fangorn y_cls `features', type(classify) generate(dt_gini) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(gini) entcvdepth(0) target(target)
timer off 1

gen byte dt_gini_correct = (y_cls == dt_gini_pred) if is_train == 0
summarize dt_gini_correct if is_train == 0
local dt_gini_acc = r(mean)
preserve
    keep if is_train == 1
    quietly levelsof dt_gini, local(dt_gini_leaves)
    local dt_gini_n_leaves `: word count `dt_gini_leaves''
restore
di "  DT Gini:        Acc = `: di %9.4f `dt_gini_acc''  Leaves = `dt_gini_n_leaves'"
timer list 1
drop dt_gini_correct dt_gini_pred dt_gini

* DT Classification: Entropy
timer on 2
fangorn y_cls `features', type(classify) generate(dt_ent) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(entropy) entcvdepth(0) target(target)
timer off 2

gen byte dt_ent_correct = (y_cls == dt_ent_pred) if is_train == 0
summarize dt_ent_correct if is_train == 0
local dt_ent_acc = r(mean)
preserve
    keep if is_train == 1
    quietly levelsof dt_ent, local(dt_ent_leaves)
    local dt_ent_n_leaves `: word count `dt_ent_leaves''
restore
di "  DT Entropy:     Acc = `: di %9.4f `dt_ent_acc''  Leaves = `dt_ent_n_leaves'"
timer list 2
drop dt_ent_correct dt_ent_pred dt_ent

* DT Regression: MSE
timer on 3
fangorn y_reg `features', type(regress) generate(dt_reg) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(mse) entcvdepth(0) target(target)
timer off 3

gen double dt_reg_resid = (y_reg - dt_reg_pred)^2 if is_train == 0
quietly summarize dt_reg_resid if is_train == 0
local dt_mse = r(mean)
quietly summarize y_reg if is_train == 0
local y_mean = r(mean)
gen double dt_reg_dev = (y_reg - `y_mean')^2 if is_train == 0
quietly summarize dt_reg_dev if is_train == 0
local dt_r2 = 1 - `dt_mse' / r(mean)
preserve
    keep if is_train == 1
    quietly levelsof dt_reg, local(dt_reg_leaves)
    local dt_reg_n_leaves `: word count `dt_reg_leaves''
restore
di "  DT Regression:  R² = `: di %9.4f `dt_r2''  MSE = `: di %9.4f `dt_mse''  Leaves = `dt_reg_n_leaves'"
timer list 3
drop dt_reg_resid dt_reg_dev dt_reg_pred dt_reg

* ═════════════════════════════════════════════════════════════════
* 3. Random Forest benchmarks
* ═════════════════════════════════════════════════════════════════

di _n "{hline 62}"
di "── fangorn Random Forest (ntree=100) ──"

* RF Classification: Gini, mtry=3 (sqrt(12))
timer on 4
fangorn y_cls `features', type(classify) generate(rf_gini) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(gini) entcvdepth(0) ///
    target(target) ntree(100) mtry(3)
timer off 4

gen byte rf_gini_correct = (y_cls == rf_gini_pred) if is_train == 0
summarize rf_gini_correct if is_train == 0
local rf_gini_acc = r(mean)
di "  RF Gini (m=3):  Acc = `: di %9.4f `rf_gini_acc''"
timer list 4
drop rf_gini_correct

* RF Classification: Entropy, mtry=3
timer on 5
fangorn y_cls `features', type(classify) generate(rf_ent) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(entropy) entcvdepth(0) ///
    target(target) ntree(100) mtry(3)
timer off 5

gen byte rf_ent_correct = (y_cls == rf_ent_pred) if is_train == 0
summarize rf_ent_correct if is_train == 0
local rf_ent_acc = r(mean)
di "  RF Entropy (m=3): Acc = `: di %9.4f `rf_ent_acc''"
timer list 5
drop rf_ent_correct

* RF Regression: MSE, mtry=4 (n_features/3)
timer on 6
fangorn y_reg `features', type(regress) generate(rf_reg) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(mse) entcvdepth(0) ///
    target(target) ntree(100) mtry(4)
timer off 6

gen double rf_reg_resid = (y_reg - rf_reg_pred)^2 if is_train == 0
quietly summarize rf_reg_resid if is_train == 0
local rf_mse = r(mean)
quietly summarize y_reg if is_train == 0
local y_mean_rf = r(mean)
gen double rf_reg_dev = (y_reg - `y_mean_rf')^2 if is_train == 0
quietly summarize rf_reg_dev if is_train == 0
local rf_r2 = 1 - `rf_mse' / r(mean)
di "  RF Regression (m=4): R² = `: di %9.4f `rf_r2''  MSE = `: di %9.4f `rf_mse''"
di "  OOB error: " r(oob_error)
timer list 6
drop rf_reg_resid rf_reg_dev

* RF Regression: all features (mtry=12) for reference
timer on 7
fangorn y_reg `features', type(regress) generate(rf_reg_all) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(mse) entcvdepth(0) ///
    target(target) ntree(100) mtry(12)
timer off 7

gen double rf_reg_all_resid = (y_reg - rf_reg_all_pred)^2 if is_train == 0
quietly summarize rf_reg_all_resid if is_train == 0
local rf_all_mse = r(mean)
gen double rf_reg_all_dev = (y_reg - `y_mean_rf')^2 if is_train == 0
quietly summarize rf_reg_all_dev if is_train == 0
local rf_all_r2 = 1 - `rf_all_mse' / r(mean)
di "  RF Regression (m=12): R² = `: di %9.4f `rf_all_r2''  MSE = `: di %9.4f `rf_all_mse''"
timer list 7
drop rf_reg_all_resid rf_reg_all_dev rf_reg_all_pred rf_reg_all

* ═════════════════════════════════════════════════════════════════
* 4. Save fangorn predictions for comparison
* ═════════════════════════════════════════════════════════════════

* Note: rf_gini_pred, rf_ent_pred, rf_reg_pred are still in memory
* dt_gini_pred etc were dropped. Re-run minimal models for predictions.

* For predictions: only need the test set, use DT with minimal config
fangorn y_cls `features', type(classify) generate(fg_preds) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    criterion(gini) entcvdepth(0) target(target)
rename fg_preds_pred fg_cls_gini

fangorn y_cls `features', type(classify) generate(fe_preds) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    criterion(entropy) entcvdepth(0) target(target)
rename fe_preds_pred fe_cls_ent

fangorn y_reg `features', type(regress) generate(fr_preds) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    criterion(mse) entcvdepth(0) target(target)
rename fr_preds_pred fg_reg

keep id fg_cls_gini fe_cls_ent fg_reg target y_cls y_reg is_train
export delimited using "test/fangorn/benchmark/fangorn_predictions.csv", replace
di _n "  → fangorn predictions saved to test/fangorn/benchmark/fangorn_predictions.csv"

* ═════════════════════════════════════════════════════════════════
* 5. Summary table
* ═════════════════════════════════════════════════════════════════

di _n "{hline 62}"
di "  FANGORN BENCHMARK SUMMARY"
di "{hline 62}"
di "  {ralign 30:Model}{ralign 15:Metric}{ralign 15:Value}"
di "  ─────────────────────────────────────────────────────────"
di "  {ralign 30:DT Gini}             Acc      `: di %9.4f `dt_gini_acc''"
di "  {ralign 30:DT Entropy}          Acc      `: di %9.4f `dt_ent_acc''"
di "  {ralign 30:DT Regression}       R²       `: di %9.4f `dt_r2''"
di "  {ralign 30:RF Gini (m=3)}       Acc      `: di %9.4f `rf_gini_acc''"
di "  {ralign 30:RF Entropy (m=3)}    Acc      `: di %9.4f `rf_ent_acc''"
di "  {ralign 30:RF Regression (m=4)} R²       `: di %9.4f `rf_r2''"
di "  {ralign 30:RF Regression (m=12)} R²      `: di %9.4f `rf_all_r2''"
di "{hline 62}"
