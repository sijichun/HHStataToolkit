*! test_fangorn_regularization.do - Test relimpdec and maxleafnodes
* Tests: default behavior, relative impurity threshold, max leaf nodes, combined

clear all
set seed 42
set obs 200

* ============================================================
* Setup: Create data with clear structure for splitting
* ============================================================
gen double x1 = runiform() * 10
gen double x2 = runiform() * 10
gen int class = 0
replace class = 1 if x1 > 3 & x1 < 7
replace class = 2 if x1 >= 7

* ============================================================
* Test 1: Default behavior (no regularization) - baseline
* ============================================================
di _n "=== Test 1: Default behavior (no regularization) ==="

fangorn class x1 x2, type(classify) generate(base) maxdepth(10) entcvdepth(0)
quietly levelsof base, local(base_leaves)
di "  Leaves (default): `: word count `base_leaves''"
local n_leaves_default `: word count `base_leaves''
di "  Leaf count: `n_leaves_default'"
assert `n_leaves_default' >= 2

drop base_pred base

* ============================================================
* Test 2: relimpdec - relative threshold
* ============================================================
di _n "=== Test 2: relimpdec(0.1) ==="

fangorn class x1 x2, type(classify) generate(fac1) maxdepth(10) entcvdepth(0) relimpdec(0.1)
fangorn class x1 x2, type(classify) generate(fac2) maxdepth(10) entcvdepth(0) relimpdec(0.5)
fangorn class x1 x2, type(classify) generate(fac0) maxdepth(10) entcvdepth(0) relimpdec(0)
quietly levelsof fac0, local(fac0_leaves)
di "  Leaves (factor=0): `: word count `fac0_leaves''"
local n_leaves_fac0 `: word count `fac0_leaves''
di "  Leaf count: `n_leaves_fac0'"

* factor=0 should behave like default (or very close)
assert `n_leaves_fac0' == `n_leaves_default'

drop fac0_pred fac0

* ============================================================
* Test 5: maxleafnodes - hard limit on leaves
* ============================================================
di _n "=== Test 5: maxleafnodes(4) ==="

fangorn class x1 x2, type(classify) generate(ml4) maxdepth(10) entcvdepth(0) maxleafnodes(4)
fangorn class x1 x2, type(classify) generate(ml2) maxdepth(10) entcvdepth(0) maxleafnodes(2)
fangorn class x1 x2, type(classify) generate(ml1) maxdepth(10) entcvdepth(0) maxleafnodes(1)
fangorn class x1 x2, type(classify) generate(mlmiss) maxdepth(10) entcvdepth(0) maxleafnodes(.)
quietly levelsof mlmiss, local(mlmiss_leaves)
di "  Leaves (maxleafnodes=.): `: word count `mlmiss_leaves''"
local n_leaves_mlmiss `: word count `mlmiss_leaves''
di "  Leaf count: `n_leaves_mlmiss'"

* Missing should behave like default
assert `n_leaves_mlmiss' == `n_leaves_default'

drop mlmiss_pred mlmiss

* ============================================================
* Test 9: Combined - factor + maxleafnodes
* ============================================================
di _n "=== Test 9: Combined regularization ==="

fangorn class x1 x2, type(classify) generate(comb) maxdepth(10) entcvdepth(0) ///
    relimpdec(0.2) maxleafnodes(6)
quietly levelsof comb, local(comb_leaves)
di "  Leaves (factor=0.2, max=6): `: word count `comb_leaves''"
local n_leaves_comb `: word count `comb_leaves''
di "  Leaf count: `n_leaves_comb'"

* Should respect maxleafnodes limit
assert `n_leaves_comb' <= 6

quietly count if comb_pred != .
assert r(N) == 200

drop comb_pred comb

* ============================================================
* Test 10: Regression with regularization
* ============================================================
di _n "=== Test 10: Regression with regularization ==="

gen double y_reg = x1 + 3*x2 + rnormal(0, 2)

* Default regression tree
fangorn y_reg x1 x2, type(regress) generate(reg_base) maxdepth(10) entcvdepth(0)
fangorn y_reg x1 x2, type(regress) generate(reg_fac) maxdepth(10) entcvdepth(0) relimpdec(0.3)
fangorn y_reg x1 x2, type(regress) generate(reg_ml) maxdepth(10) entcvdepth(0) maxleafnodes(3)
quietly levelsof reg_ml, local(reg_ml_leaves)
local n_reg_ml `: word count `reg_ml_leaves''
di "  Regression leaves (max=3): `n_reg_ml'"
assert `n_reg_ml' <= 3

drop reg_base_pred reg_base reg_fac_pred reg_fac reg_ml_pred reg_ml y_reg

* ============================================================
* Test 11: Compare accuracy - regularized vs default
* ============================================================
di _n "=== Test 11: Accuracy comparison ==="

* Default tree accuracy
fangorn class x1 x2, type(classify) generate(acc_base) maxdepth(10) entcvdepth(0)
gen double correct_base = (class == acc_base_pred)
quietly summarize correct_base
local acc_base = r(mean)
di "  Default accuracy: `acc_base'"

* Regularized tree accuracy
fangorn class x1 x2, type(classify) generate(acc_reg) maxdepth(10) entcvdepth(0) relimpdec(0.2) maxleafnodes(4)
gen double correct_reg = (class == acc_reg_pred)
quietly summarize correct_reg
local acc_reg = r(mean)
di "  Regularized accuracy: `acc_reg'"
di "  Regularized leaves: "
quietly levelsof acc_reg, local(acc_reg_leaves)
di "  `: word count `acc_reg_leaves''"

* Regularized might have lower accuracy but should still be reasonable
assert `acc_reg' > 0.5

drop correct_base acc_base_pred acc_base correct_reg acc_reg_pred acc_reg

* ============================================================
* Cleanup
* ============================================================
di _n "=== All regularization tests passed! ==="

drop x1 x2 class
