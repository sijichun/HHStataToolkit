*! test_xpofangorn_seed_reproducibility.do
* Tests: DML seed-based reproducibility for xpofangorn.
* Requires: 10 consecutive runs with identical seed --> all beta identical.
* xpofangorn uses set seed for fold assignment and seed() for fangorn.
* Run: stata -b do test/xpofangorn/test_xpofangorn_seed_reproducibility.do

clear all
set more off
set seed 42
set obs 1000

* Simple DGP: partially linear model y = 3*w + g(x) + u
gen double x1  = rnormal()
gen double x2  = rnormal()
gen double x3  = rnormal()
gen double chi = rnormal()^2 + rnormal()^2
gen double w   = x1 + 0.5*x2 + 0.3*chi + rnormal()
gen double g_x = exp((x1 + x2*chi)/4)
gen double y   = 3*w + g_x + rnormal()

local depvars "x1 x2 x3 chi"

local nrep = 10

* ============================================================
* Test 1: Same seed --> identical beta (10 runs, RF basic)
* ============================================================
di _n "{hline 60}"
di "=== Test 1: xpofangorn RF reproducibility (10 runs, seed=12345) ==="
di "{hline 60}"
forvalues i = 1/`nrep' {
    quietly xpofangorn y w `depvars', ///
        ntree(50) kfold(5) maxdepth(5) seed(12345)
    local beta`i' = r(beta)
    local se`i'   = r(se)
    di "  Run `i': beta = " %9.6f r(beta) "  se = " %9.6f r(se)
}
forvalues i = 1/9 {
    local j = `i' + 1
    local diff = abs(`beta`i'' - `beta`j'')
    di "  Run `i' vs `j': |beta diff| = " %12.2e `diff'
    assert `diff' < 1e-10
}
di "  PASS: All 10 beta identical."

* ============================================================
* Test 2: Same seed --> identical beta with deeper trees
* ============================================================
di _n "{hline 60}"
di "=== Test 2: Deep RF reproducibility (10 runs, seed=99999, maxdepth=10) ==="
di "{hline 60}"
forvalues i = 1/`nrep' {
    quietly xpofangorn y w `depvars', ///
        ntree(100) kfold(5) maxdepth(10) seed(99999)
    local beta`i' = r(beta)
    local se`i'   = r(se)
    di "  Run `i': beta = " %9.6f r(beta) "  se = " %9.6f r(se)
}
forvalues i = 1/9 {
    local j = `i' + 1
    local diff = abs(`beta`i'' - `beta`j'')
    di "  Run `i' vs `j': |beta diff| = " %12.2e `diff'
    assert `diff' < 1e-10
}
di "  PASS: All 10 beta identical."

* ============================================================
* Test 3: nproc(1) vs nproc(16) --> identical beta
* ============================================================
di _n "{hline 60}"
di "=== Test 3: nproc(1) vs nproc(16) determinism ==="
di "{hline 60}"
quietly xpofangorn y w `depvars', ntree(50) kfold(5) maxdepth(5) ///
    seed(42) nproc(1)
local beta_1core = r(beta)

quietly xpofangorn y w `depvars', ntree(50) kfold(5) maxdepth(5) ///
    seed(42) nproc(16)
local beta_16core = r(beta)

local diff = abs(`beta_1core' - `beta_16core')
di "  nproc(1)  beta = " %9.6f `beta_1core'
di "  nproc(16) beta = " %9.6f `beta_16core'
di "  |diff| = " %12.2e `diff'
assert `diff' < 1e-10
di "  PASS: nproc(1) == nproc(16) bit-identical."

* ============================================================
* Test 4: Different seeds --> different betas
* ============================================================
di _n "{hline 60}"
di "=== Test 4: Different seeds produce different betas ==="
di "{hline 60}"
quietly xpofangorn y w `depvars', ntree(50) kfold(5) maxdepth(5) seed(1)
local beta_s1 = r(beta)

quietly xpofangorn y w `depvars', ntree(50) kfold(5) maxdepth(5) seed(999)
local beta_s2 = r(beta)

local diff = abs(`beta_s1' - `beta_s2')
di "  seed=1   beta = " %9.6f `beta_s1'
di "  seed=999 beta = " %9.6f `beta_s2'
di "  |diff| = " %12.2e `diff'
assert `diff' > 1e-10
di "  PASS: Different seeds produce different results."

* ============================================================
* Test 5: Same seed across kfold values --> deterministic
* ============================================================
di _n "{hline 60}"
di "=== Test 5: K-fold determinism (10 runs, K=10, seed=777) ==="
di "{hline 60}"
forvalues i = 1/`nrep' {
    quietly xpofangorn y w `depvars', ///
        ntree(50) kfold(10) maxdepth(5) seed(777)
    local beta`i' = r(beta)
    di "  Run `i': beta = " %9.6f r(beta)
}
forvalues i = 1/9 {
    local j = `i' + 1
    local diff = abs(`beta`i'' - `beta`j'')
    assert `diff' < 1e-10
}
di "  PASS: K=10 also bit-identical across runs."

* ============================================================
di _n "{hline 60}"
di "=== All xpofangorn seed reproducibility tests passed! ==="
di "{hline 60}"
exit 0
