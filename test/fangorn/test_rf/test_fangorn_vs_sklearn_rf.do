*! test_fangorn_vs_sklearn_rf.do
* Compare fangorn vs sklearn random forests on a complex dataset
* Uses the same data as test_ent (ent_data.csv), with ntree=100

clear all
set more off

* ── 1. Import data ───────────────────────────────────────────
import delimited using "test/fangorn/test_ent/ent_data.csv", clear
destring, replace

* Rename to avoid confusion with fangorn's 'target' option
rename train is_train

* fangorn: target=0=train, target=1=test
gen byte target = (is_train == 0)

count if is_train == 1
local n_train = r(N)
count if is_train == 0
local n_test = r(N)
di "Training observations: `n_train'"
di "Test observations:     `n_test'"

* ── 2. fangorn Random Forest: Classification (Gini) ───────────
di _n "{hline 60}"
di "── fangorn Random Forest Classification (Gini) ──"

fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(fg) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(gini) entcvdepth(0) ///
    target(target) ntree(100) mtry(2)

* Compute classification accuracy on test set
gen byte fg_correct = (y_class == fg_pred) if is_train == 0
summarize fg_correct if is_train == 0
local fg_acc = r(mean)
di "  Test accuracy: `: di %9.4f `fg_acc''"
drop fg_correct

* ── 3. fangorn Random Forest: Classification (Entropy) ────────
di _n "{hline 60}"
di "── fangorn Random Forest Classification (Entropy) ──"

fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(fe) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(entropy) entcvdepth(0) ///
    target(target) ntree(100) mtry(2)

gen byte fe_correct = (y_class == fe_pred) if is_train == 0
summarize fe_correct if is_train == 0
local fe_acc = r(mean)
di "  Test accuracy: `: di %9.4f `fe_acc''"
drop fe_correct

* ── 4. fangorn Random Forest: Regression ──────────────────────
di _n "{hline 60}"
di "── fangorn Random Forest Regression (mtry=1, MSE) ──"

fangorn y_reg x1 x2 x3 x4 x5, type(regress) generate(fr) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(mse) entcvdepth(0) ///
    target(target) ntree(100) mtry(1)

* Compute regression metrics on test set
gen double fr_resid_sq = (y_reg - fr_pred)^2 if is_train == 0
quietly summarize fr_resid_sq if is_train == 0
local mse = r(mean)
quietly summarize y_reg if is_train == 0
local y_mean = r(mean)
gen double fr_dev_sq = (y_reg - `y_mean')^2 if is_train == 0
quietly summarize fr_dev_sq if is_train == 0
local r2 = 1 - `mse' / r(mean)
di "  Test MSE: `: di %9.4f `mse''"
di "  Test R²:  `: di %9.4f `r2''"
drop fr_resid_sq fr_dev_sq

* ── Summary table ────────────────────────────────────────────
di _n "{hline 62}"
di "  FANGORN RANDOM FOREST BENCHMARK SUMMARY"
di "{hline 62}"
di "  {ralign 30:Task}                 Metric    Value"
di "  ─────────────────────────────────────────────────────────"
di "  {ralign 30:RF Cls Gini}      Accuracy  `: di %9.4f `fg_acc''"
di "  {ralign 30:RF Cls Entropy}   Accuracy  `: di %9.4f `fe_acc''"
di "  {ralign 30:RF Regression}    R²        `: di %9.4f `r2''"
di "{hline 62}"
