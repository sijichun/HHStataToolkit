*! test_fangorn_seed_reproducibility.do
* Tests: Repeated RF runs with the same seed produce identical output.
* Requires: 10 consecutive runs with identical seed → all results match.
* Verifies bit-identical reproducibility for classification, regression,
* CV depth selection, and single trees.  Also verifies different seeds
* produce different results.
* Run: stata -b do test/fangorn/test_fangorn_seed_reproducibility.do

clear all
set seed 42
set obs 500

gen double x1 = rnormal()
gen double x2 = rnormal()
gen double x3 = rnormal()
gen int    y_class = (x1 + x2 + rnormal() > 0)
gen double y_reg   = x1 + 2*x2 + rnormal()

* ============================================================
* Test 1: RF classification — same seed, 10 consecutive runs
* ============================================================
di _n "{hline 60}"
di "=== Test 1: RF classification reproducibility (10 runs, seed=12345) ==="
di "{hline 60}"
forvalues i = 1/10 {
    fangorn y_class x1 x2 x3, type(classify) generate(rf_c`i') ///
        ntree(50) maxdepth(5) entcvdepth(0) seed(12345)
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen byte match_c`i' = (rf_c`i'_pred == rf_c`j'_pred)
    quietly summarize match_c`i'
    di "  Run `i' vs `j': match rate = " %9.6f r(mean)
    assert r(mean) == 1.0
}

* ============================================================
* Test 2: RF regression — same seed, 10 consecutive runs
* ============================================================
di _n "{hline 60}"
di "=== Test 2: RF regression reproducibility (10 runs, seed=12345) ==="
di "{hline 60}"
forvalues i = 1/10 {
    fangorn y_reg x1 x2 x3, type(regress) generate(rf_r`i') ///
        ntree(50) maxdepth(5) entcvdepth(0) seed(12345)
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen double diff_r`i' = abs(rf_r`i'_pred - rf_r`j'_pred)
    quietly summarize diff_r`i'
    di "  Run `i' vs `j': max diff = " %12.2e r(max)
    assert r(max) < 1e-10
}

* ============================================================
* Test 3: RF + CV depth selection — same seed, 10 runs
* ============================================================
di _n "{hline 60}"
di "=== Test 3: RF + CV depth selection reproducibility (10 runs, seed=777) ==="
di "{hline 60}"
forvalues i = 1/10 {
    fangorn y_class x1 x2 x3, type(classify) generate(rf_cv`i') ///
        ntree(30) maxdepth(10) entcvdepth(5) seed(777)
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen byte match_cv`i' = (rf_cv`i'_pred == rf_cv`j'_pred)
    quietly summarize match_cv`i'
    di "  Run `i' vs `j': match rate = " %9.6f r(mean)
    assert r(mean) == 1.0
}

* ============================================================
* Test 4: Single tree (deterministic, no seed needed), 10 runs
* ============================================================
di _n "{hline 60}"
di "=== Test 4: Single tree deterministic (10 runs, no seed) ==="
di "{hline 60}"
forvalues i = 1/10 {
    fangorn y_class x1 x2 x3, type(classify) generate(st`i') ///
        maxdepth(5) entcvdepth(0)
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen byte match_st`i' = (st`i'_pred == st`j'_pred)
    quietly summarize match_st`i'
    di "  Run `i' vs `j': match rate = " %9.6f r(mean)
    assert r(mean) == 1.0
}

* ============================================================
* Test 5: Different seeds → different results
* ============================================================
di _n "{hline 60}"
di "=== Test 5: Different seeds produce different results ==="
di "{hline 60}"
fangorn y_class x1 x2 x3, type(classify) generate(ds1) ///
    ntree(50) maxdepth(5) entcvdepth(0) seed(1)
fangorn y_class x1 x2 x3, type(classify) generate(ds2) ///
    ntree(50) maxdepth(5) entcvdepth(0) seed(999)
gen byte diff_seed = (ds1_pred != ds2_pred)
quietly summarize diff_seed
di "  Mismatch rate (seed=1 vs seed=999): " %9.4f r(mean)
assert r(mean) > 0

* ============================================================
* Test 6: OOB error reproducibility (10 runs, seed=42)
* ============================================================
di _n "{hline 60}"
di "=== Test 6: OOB error reproducibility (10 runs, seed=42) ==="
di "{hline 60}"
forvalues i = 1/10 {
    fangorn y_class x1 x2 x3, type(classify) generate(oob`i') ///
        ntree(50) maxdepth(5) entcvdepth(0) seed(42)
    local oob`i' = r(oob_error)
}
forvalues i = 1/9 {
    local j = `i' + 1
    assert `oob`i'' == `oob`j''
}
di "  All 10 OOB errors identical: " %9.6f `oob1'

di _n "{hline 60}"
di "=== All seed reproducibility tests passed! ==="
di "{hline 60}"
exit 0
