*! test_kdensity2_gpu_seed_reproducibility.do
* Tests: GPU path reproducibility for kdensity2 CUDA plugin.
* Requires: kdensity2_cuda.plugin built via 'make kdensity2_cuda'
* GPU uses float internally; tolerance is 1e-5 (vs 1e-10 for CPU).
* Run: stata -b do test/kdensity2/test_gpu_seed_reproducibility.do

capture cd ".."

clear all
set seed 42

* Check if CUDA plugin is available
capture which kdensity2
if _rc {
    display as error "kdensity2 not found. Run 'make install' first."
    exit 111
}

* Verify GPU plugin exists
capture kdensity2 x, generate(f) gpu(0)
if _rc {
    display as text "CUDA plugin not available — skipping GPU reproducibility tests"
    exit 0
}

display as text _n "{hline 60}"
display as text "kdensity2 GPU Reproducibility Tests"
display as text "Tolerance: 1e-5 (float GPU vs double CPU)"
display as text "{hline 60}"

* ============================================================
* Test 1: 1D Silverman bandwidth (deterministic, 10 runs)
* ============================================================
display as text _n "Test 1: 1D Silverman GPU (10 runs)"
set obs 1000
gen double x = rchi2(5)
forvalues i = 1/10 {
    kdensity2 x, bw(silverman) generate(gpu_s`i') gpu(0)
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen double diff_s`i' = abs(gpu_s`i' - gpu_s`j')
    quietly summarize diff_s`i'
    display as text "  Run `i' vs `j': max diff = " as result %12.2e r(max)
    assert r(max) < 1e-5
}
drop x gpu_s* diff_s*

* ============================================================
* Test 2: 1D CV bandwidth — re-set seed before each call (10 runs)
* ============================================================
display as text _n "Test 2: 1D CV GPU (10 runs, re-set seed)"
set obs 1000
gen double x = rchi2(5)
forvalues i = 1/10 {
    set seed 123
    kdensity2 x, bw(cv) generate(gpu_cv`i') gpu(0)
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen double diff_cv`i' = abs(gpu_cv`i' - gpu_cv`j')
    quietly summarize diff_cv`i'
    display as text "  Run `i' vs `j': max diff = " as result %12.2e r(max)
    assert r(max) < 1e-5
}
drop x gpu_cv* diff_cv*

* ============================================================
* Test 3: Multivariate Silverman (10 runs)
* ============================================================
display as text _n "Test 3: Multivariate Silverman GPU (10 runs)"
set obs 500
gen double x1 = rnormal()
gen double x2 = rnormal()
forvalues i = 1/10 {
    kdensity2 x1 x2, bw(silverman) generate(gpu_mv_s`i') gpu(0)
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen double diff_mv_s`i' = abs(gpu_mv_s`i' - gpu_mv_s`j')
    quietly summarize diff_mv_s`i'
    display as text "  Run `i' vs `j': max diff = " as result %12.2e r(max)
    assert r(max) < 1e-5
}
drop x1 x2 gpu_mv_s* diff_mv_s*

* ============================================================
* Test 4: Multivariate CV — re-set seed (10 runs)
* ============================================================
display as text _n "Test 4: Multivariate CV GPU (10 runs, re-set seed)"
set obs 500
gen double x1 = rnormal()
gen double x2 = rnormal()
forvalues i = 1/10 {
    set seed 456
    kdensity2 x1 x2, bw(cv) generate(gpu_mv_cv`i') gpu(0)
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen double diff_mv_cv`i' = abs(gpu_mv_cv`i' - gpu_mv_cv`j')
    quietly summarize diff_mv_cv`i'
    display as text "  Run `i' vs `j': max diff = " as result %12.2e r(max)
    assert r(max) < 1e-5
}
drop x1 x2 gpu_mv_cv* diff_mv_cv*

* ============================================================
* Test 5: Different set seed → different GPU CV results
* ============================================================
display as text _n "Test 5: Different seed → different GPU CV"
set obs 1000
gen double x = rchi2(5)
set seed 1
kdensity2 x, bw(cv) generate(gpu_ds1) gpu(0)
set seed 999
kdensity2 x, bw(cv) generate(gpu_ds2) gpu(0)
gen double diff_ds = abs(gpu_ds1 - gpu_ds2)
quietly summarize diff_ds
display as text "  Max diff (seed=1 vs seed=999): " as result %12.2e r(max)
assert r(max) > 1e-5
drop x gpu_ds* diff_ds

* ============================================================
* Test 6: Grouped estimation GPU reproducibility (10 runs)
* ============================================================
display as text _n "Test 6: Grouped Silverman GPU (10 runs)"
set obs 1000
gen double x = rnormal()
gen int g = mod(_n, 4)
forvalues i = 1/10 {
    kdensity2 x, group(g) bw(silverman) generate(gpu_g`i') gpu(0)
}
forvalues i = 1/9 {
    local j = `i' + 1
    gen double diff_g`i' = abs(gpu_g`i' - gpu_g`j')
    quietly summarize diff_g`i'
    display as text "  Run `i' vs `j': max diff = " as result %12.2e r(max)
    assert r(max) < 1e-5
}

display as text _n "{hline 60}"
display as text "All GPU reproducibility tests passed"
display as text "{hline 60}"
exit 0
