*! test_nwreg_seed_reproducibility.do
* Tests: CV bandwidth selection reproducibility under Stata set seed.
* Requires: 10 consecutive runs with identical seed → all results match.
* nwreg does not have a seed() option; instead, CV mode uses
* runiform() in the ado wrapper to shuffle data order.  Because
* runiform() advances Stata's RNG state, the test re-sets the seed
* before each call to verify bit-identical results.
* Run: stata -b do test/nwreg/test_seed_reproducibility.do

clear all
set seed 42
set obs 1000

gen double x = rnormal()
gen double y = x^2 + rnormal()

* ============================================================
* Test 1: CV bandwidth — re-set seed before each call, 10 runs
* ============================================================
di _n "{hline 60}"
di "=== Test 1: nwreg CV reproducibility (10 runs, re-set seed) ==="
di "{hline 60}"
forvalues i = 1/10 {
    set seed 123
    nwreg y x, bw(cv) generate(nw`i')
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen double diff`i' = abs(nw`i' - nw`j')
    quietly summarize diff`i'
    di "  Run `i' vs `j': max diff = " %12.2e r(max)
    assert r(max) < 1e-10
}

* ============================================================
* Test 2: Silverman bandwidth (deterministic, 10 runs)
* ============================================================
di _n "{hline 60}"
di "=== Test 2: nwreg Silverman (deterministic, 10 runs) ==="
di "{hline 60}"
forvalues i = 1/10 {
    nwreg y x, bw(silverman) generate(nw_s`i')
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen double diff_s`i' = abs(nw_s`i' - nw_s`j')
    quietly summarize diff_s`i'
    di "  Run `i' vs `j': max diff = " %12.2e r(max)
    assert r(max) < 1e-10
}

* ============================================================
* Test 3: Different set seed produces different CV results
* ============================================================
di _n "{hline 60}"
di "=== Test 3: Different set seed → different CV results ==="
di "{hline 60}"
set seed 1
nwreg y x, bw(cv) generate(nw_ds1)
set seed 999
nwreg y x, bw(cv) generate(nw_ds2)
gen double diff_ds = abs(nw_ds1 - nw_ds2)
quietly summarize diff_ds
di "  Max diff between seed=1 and seed=999: " %12.2e r(max)
assert r(max) > 1e-10

* ============================================================
* Test 4: Multivariate CV reproducibility (2D, 10 runs)
* ============================================================
di _n "{hline 60}"
di "=== Test 4: Multivariate CV reproducibility (2 regressors, 10 runs) ==="
di "{hline 60}"
gen double x2 = rnormal()
forvalues i = 1/10 {
    set seed 456
    nwreg y x x2, bw(cv) generate(nw_mv`i')
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen double diff_mv`i' = abs(nw_mv`i' - nw_mv`j')
    quietly summarize diff_mv`i'
    di "  Run `i' vs `j': max diff = " %12.2e r(max)
    assert r(max) < 1e-10
}

* ============================================================
* Test 5: CV with SE computation reproducibility (10 runs)
* ============================================================
di _n "{hline 60}"
di "=== Test 5: CV + SE reproducibility (10 runs, re-set seed) ==="
di "{hline 60}"
forvalues i = 1/10 {
    set seed 789
    nwreg y x, bw(cv) generate(nw_se`i') se(se`i')
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen double diff_se`i' = abs(nw_se`i' - nw_se`j')
    quietly summarize diff_se`i'
    di "  Pred run `i' vs `j': max diff = " %12.2e r(max)
    assert r(max) < 1e-10
    gen double diff_se2`i' = abs(se`i' - se`j')
    quietly summarize diff_se2`i'
    di "  SE   run `i' vs `j': max diff = " %12.2e r(max)
    assert r(max) < 1e-10
}

di _n "{hline 60}"
di "=== All nwreg seed tests passed! ==="
di "{hline 60}"
exit 0
