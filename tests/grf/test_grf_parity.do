*! test_grf_parity.do — R-vs-Stata parity test
* Prerequisites:
*   1. Run tests/grf/fixtures/generate_fixtures.R first
*   2. This imports the frozen R reference output
clear all
set more off
set seed 42

* Import R-generated data (now includes Y_hat, W_hat nuisance estimates)
import delimited using "tests/grf/fixtures/parity_readme1_data.csv", clear
drop id

* Run Stata GRF with R-precomputed nuisance estimates
* (isolates CATE estimation from nuisance forest RNG differences)
capture grf y w x1 x2 x3 x4 x5 x6 x7 x8 x9 x10, ///
    generate(st_tau) ntree(2000) nproc(1) seed(12345) ///
    yhat(y_hat) what(w_hat)
if _rc {
    display as error "GRF command failed"
    exit _rc
}

* Import R reference predictions
preserve
import delimited using "tests/grf/fixtures/parity_readme1.csv", clear
tempfile r_preds
save `r_preds'
restore

* Merge
gen long id = _n
merge 1:1 id using `r_preds', nogen

* Compare
gen double diff_abs = abs(st_tau - tau_oob)
quietly summarize diff_abs
local max_abs = r(max)
local mean_abs = r(mean)

quietly correlate st_tau tau_oob
local corr = r(rho)

display as text "Parity comparison:"
display as text "  Max abs diff  = " as result %12.6e `max_abs'
display as text "  Mean abs diff = " as result %12.6e `mean_abs'
display as text "  Correlation   = " as result %6.4f `corr'

* Target: corr >= 0.99, mean abs diff < 0.1, max abs diff < 0.5
* (README documents 0.997 corr, 0.032 mean, 0.180 max for R-vs-Stata parity)
if `corr' >= 0.99 & `mean_abs' < 0.1 & `max_abs' < 0.5 {
    display "test_grf_parity PASSED"
}
else {
    display as error "Parity tolerance exceeded"
    preserve
    keep id st_tau tau_oob diff_abs
    export delimited using "tests/grf/fixtures/parity_readme1_diffs.csv", replace
    restore
    exit 198
}
