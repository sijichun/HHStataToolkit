*! run_all.do — Master test runner for HHStataToolkit
* Runs all non-GPU tests and reports PASS/FAIL summary.
* Usage: stata -b do tests/run_all.do

clear all
set more off
display as text _n "{hline 72}"
display as text "HHStataToolkit — Master Test Suite"
display as text "{hline 72}"
display as text "Started:  $S_DATE $S_TIME"
display as text "Stata:    `c(stata_version)' MP=`c(MP)'"
display as text "Processors: `c(processors)'"
display as text "{hline 72}" _n

local n_pass 0
local n_fail 0
local fail_list ""

* Helper: run a test do-file and record result
capture program drop _run_test
program define _run_test
    args label dofile
    display as text "{hline 72}"
    display as text "Running: `label'"
    display as text "  File: `dofile'"
    capture noisily do `dofile'
    if _rc == 0 {
        display as result "  PASS: `label'"
        global _n_pass = ${_n_pass} + 1
    }
    else {
        display as error "  FAIL (rc=`_rc'): `label'"
        global _n_fail = ${_n_fail} + 1
        global _fail_list "${_fail_list}`label' / "
    }
    display as text "{hline 72}" _n
end

* =========================================================
* kdensity2 — Kernel Density Estimation
* =========================================================
display as result _n "=== kdensity2 ==="

_run_test "kdensity2 seed reproducibility"     tests/kdensity2/test_seed_reproducibility.do
_run_test "kdensity2 CPU reproducibility"      tests/kdensity2/test_cpu_reproducibility.do
_run_test "kdensity2 chi2 group"              tests/kdensity2/test_chi2_group.do
_run_test "kdensity2 bivariate group"          tests/kdensity2/test_bivariate_group.do
_run_test "kdensity2 minobs"                   tests/kdensity2/test_minobs.do
_run_test "kdensity2 CV compare"               tests/kdensity2/test_cv_compare.do
_run_test "kdensity2 gnormalize"              tests/kdensity2/test_gnormalize.do

* =========================================================
* nwreg — Kernel Regression
* =========================================================
display as result _n "=== nwreg ==="

_run_test "nwreg seed reproducibility"        tests/nwreg/test_seed_reproducibility.do
_run_test "nwreg CPU reproducibility"         tests/nwreg/test_cpu_reproducibility.do
_run_test "nwreg simulation"                  tests/nwreg/test_nwreg_simulation.do
_run_test "nwreg standard error"              tests/nwreg/test_nwreg_se.do
_run_test "nwreg local polynomial"            tests/nwreg/test_local_polynomial.do
_run_test "nwreg local polynomial reprod"     tests/nwreg/test_local_polynomial_reproducibility.do

* =========================================================
* fangorn — Decision Tree / Random Forest
* =========================================================
display as result _n "=== fangorn ==="

_run_test "fangorn seed reproducibility"      tests/fangorn/test_fangorn_seed_reproducibility.do
_run_test "fangorn phase 1 (decision tree)"   tests/fangorn/test_fangorn_phase1.do
_run_test "fangorn phase 2 (random forest)"   tests/fangorn/test_fangorn_phase2.do
_run_test "fangorn basic"                     tests/fangorn/test_fangorn_basic.do
_run_test "fangorn CV depth"                  tests/fangorn/test_fangorn_cv.do
_run_test "fangorn regularization"            tests/fangorn/test_fangorn_regularization.do
_run_test "fangorn Mermaid export"            tests/fangorn/test_mermaid_output.do

* =========================================================
* grf — Causal Forest
* =========================================================
display as result _n "=== grf (causal forest) ==="

_run_test "grf basic"                         tests/grf/test_grf_basic.do
_run_test "grf seed reproducibility"          tests/grf/test_grf_seed_reproducibility.do
_run_test "grf CPU reproducibility"           tests/grf/test_grf_cpu_reproducibility.do
_run_test "grf honesty"                       tests/grf/test_grf_honesty.do
_run_test "grf cluster"                       tests/grf/test_grf_cluster.do
_run_test "grf OOB"                           tests/grf/test_grf_oob.do
_run_test "grf variance"                      tests/grf/test_grf_variance.do
_run_test "grf orthogonalization"             tests/grf/test_grf_orthogonalization.do

* =========================================================
* xpofangorn — DML Partially Linear Model
* =========================================================
display as result _n "=== xpofangorn ==="

_run_test "xpofangorn basic"                  tests/xpofangorn/test_xpofangorn.do
_run_test "xpofangorn seed reproducibility"   tests/xpofangorn/test_xpofangorn_seed_reproducibility.do

* =========================================================
* csa — Common Support Area
* =========================================================
display as result _n "=== csadensity ==="

_run_test "csadensity"                        tests/csa/test_csadensity.do

* =========================================================
* Summary
* =========================================================
display as text _n "{hline 72}"
display as text "Test Suite Summary"
display as text "{hline 72}"
display as text "  Passed:  " as result %3.0f ${_n_pass}
display as text "  Failed:  " as error  %3.0f ${_n_fail}
display as text "  Total:   " as text  %3.0f = ${_n_pass} + ${_n_fail}
display as text "{hline 72}"

if ${_n_fail} > 0 {
    display as error "  FAILED TESTS: ${_fail_list}"
    display as error "{hline 72}"
    exit 9
}
else {
    display as result "  ALL TESTS PASSED"
    display as text "{hline 72}"
    exit 0
}
