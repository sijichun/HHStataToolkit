*! test_grf_seed_reproducibility.do
clear all
set more off
adopath + grf/
set seed 12345
set obs 200
gen x1 = rnormal()
gen w = runiform() > 0.5
gen y = x1 + w*x1 + rnormal()
quietly sum y
quietly gen yhat = r(mean)
quietly sum w
quietly gen what = r(mean)

* Run 10 times
forvalues i = 1/10 {
    quietly grf y w x1, generate(p`i') ntree(50) nproc(2) seed(999) yhat(yhat) what(what)
}

* Compare run 1 with all others
gen double d = 0
local ok = 1
forvalues i = 2/10 {
    quietly replace d = abs(p1 - p`i')
    quietly sum d
    if r(max) > 1e-10 {
        local ok = 0
    }
}
if `ok' {
    display "PASSED"
}
else {
    display "FAILED: differences detected"
}
