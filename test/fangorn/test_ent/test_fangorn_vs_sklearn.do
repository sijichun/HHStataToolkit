*! test_fangorn_vs_sklearn.do
* Compare fangorn vs sklearn decision trees on a complex dataset
* Uses target() to split train/test: target=0=train, target=1=test

clear all
set more off

* ── 1. Import data ───────────────────────────────────────────
import delimited using "test/test_ent/ent_data.csv", clear
destring, replace

* Data has: x1-x5, y_class, y_reg, train, id
* train=1=training so rename to avoid confusion
rename train is_train

* Create target variable: fangorn uses target=0=train, target=1=test
gen byte target = (is_train == 0)

count if is_train == 1
local n_train = r(N)
count if is_train == 0
local n_test = r(N)
di "Training observations: `n_train'"
di "Test observations:     `n_test'"

* ── 2. Classification: Gini ─────────────────────────────────
di _n "{hline 60}"
di "── fangorn Classification (Gini) ──"

fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(fg) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(gini) entcvdepth(0) target(target)

fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(fe) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(entropy) entcvdepth(0) target(target)

fangorn y_reg x1 x2 x3 x4 x5, type(regress) generate(fr) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0) criterion(mse) entcvdepth(0) target(target)

fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(fr1) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    minimpuritydecrease(0.01) criterion(gini) entcvdepth(0) target(target)

fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(fr2) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    maxleafnodes(8) criterion(gini) entcvdepth(0) target(target)

fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(fr3) ///
    maxdepth(10) minsamplessplit(10) minsamplesleaf(3) ///
    relimpdec(0.1) maxleafnodes(12) criterion(gini) entcvdepth(0) target(target)

preserve
    keep if is_train == 1
    quietly levelsof fr3, local(fr3_leaves)
    local fr3_n_leaves `: word count `fr3_leaves''
restore
di "  Train leaves: `fr3_n_leaves'"

gen byte fr3_correct = (y_class == fr3_pred) if is_train == 0
summarize fr3_correct if is_train == 0
local fr3_acc = r(mean)
di "  Test accuracy: `: di %9.4f `fr3_acc''"

* ── 8. Save fangorn predictions ────────────────────────────
keep id fg_pred fe_pred fr_pred fr1_pred fr2_pred fr3_pred y_class y_reg is_train
export delimited using "test/test_ent/fangorn_predictions.csv", replace
di "Predictions saved to test/test_ent/fangorn_predictions.csv"

* ── 9. Summary table ────────────────────────────────────────
di _n "{hline 62}"
di "  FANGORN BENCHMARK SUMMARY"
di "{hline 62}"
di "  {ralign 25:Task}                     Leaves     Metric"
di "  ──────────────────────────────────────────────────────"
di "  {ralign 25:Cls Gini}              {ralign 5:`fg_n_leaves'}     Acc = `: di %9.4f `fg_acc''"
di "  {ralign 25:Cls Entropy}           {ralign 5:`fe_n_leaves'}     Acc = `: di %9.4f `fe_acc''"
di "  {ralign 25:Regression}            {ralign 5:`fr_n_leaves'}     R²  = `: di %9.4f `r2''"
di "  {ralign 25:reg1 (imp=0.01)}       {ralign 5:`fr1_n_leaves'}     Acc = `: di %9.4f `fr1_acc''"
di "  {ralign 25:reg2 (leaf=8)}         {ralign 5:`fr2_n_leaves'}     Acc = `: di %9.4f `fr2_acc''"
di "  {ralign 25:reg3 (relimp=0.1,leaf=12)} {ralign 5:`fr3_n_leaves'}     Acc = `: di %9.4f `fr3_acc''"
di "{hline 62}"
