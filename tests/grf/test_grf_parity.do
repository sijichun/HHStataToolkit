*! test_grf_parity.do — R-vs-Stata parity test
* Prerequisites:
*   1. Run tests/grf/fixtures/generate_fixtures.R first
*   2. This imports the frozen R reference output
clear all
set more off
set seed 42

* Import R-generated data
import delimited using "tests/grf/fixtures/parity_readme1_data.csv", clear
rename v1 id
rename v2 x1
rename v3 x2
rename v4 x3
rename v5 x4
rename v6 x5
rename v7 x6
rename v8 x7
rename v9 x8
rename v10 x9
rename v11 x10
rename v12 y
rename v13 w
drop id

* Run Stata GRF
capture grf y w x1 x2 x3 x4 x5 x6 x7 x8 x9 x10, ///
    generate(st_tau) ntree(2000) nproc(1) seed(12345)
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
gen double diff_rel = abs((st_tau - tau_oob) / cond(abs(tau_oob) > 1e-12, abs(tau_oob), 1))
quietly summarize diff_abs
local max_abs = r(max)
quietly summarize diff_rel
local max_rel = r(max)
display as text "Parity comparison:"
display as text "  Max abs diff = " as result %12.6e `max_abs'
display as text "  Max rel diff = " as result %12.6e `max_rel'

if `max_abs' < 1e-6 & `max_rel' < 1e-6 {
    display "test_grf_parity PASSED"
}
else {
    display as error "Parity tolerance exceeded"
    preserve
    keep id st_tau tau_oob diff_abs diff_rel
    export delimited using "tests/grf/fixtures/parity_readme1_diffs.csv", replace
    restore
    exit 198
}
