*! test_grf_oob.do
clear all
set more off
set seed 42
set obs 200
gen x1 = rnormal()
gen w = runiform() > 0.5
gen y = x1 + w*x1 + rnormal()
quietly sum y
gen yhat = r(mean)
quietly sum w
gen what = r(mean)

capture noisily grf y w x1, generate(p1) ntree(50) nproc(2) seed(12345) yhat(yhat) what(what) oobgenerate(oob1)
if _rc {
    display as error "FAILED oob"
    exit _rc
}
capture noisily confirm variable oob1
if _rc {
    display as error "FAILED oob not created"
    exit _rc
}
display "PASSED"
