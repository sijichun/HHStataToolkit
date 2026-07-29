*! test_grf_honesty.do
clear all
set more off
set seed 42
set obs 500
gen x1 = rnormal()
gen w = runiform() > 0.5
gen y = x1 + w*x1 + rnormal()
quietly sum y
gen yhat = r(mean)
quietly sum w
gen what = r(mean)

capture noisily grf y w x1, generate(p1) ntree(50) nproc(2) seed(12345) yhat(yhat) what(what)
if _rc { display as error "FAILED honesty default"; exit _rc }

capture noisily grf y w x1, generate(p2) ntree(50) nproc(2) seed(12345) yhat(yhat) what(what) honestyfraction(0.3)
if _rc { display as error "FAILED honesty fraction"; exit _rc }
display "PASSED"
