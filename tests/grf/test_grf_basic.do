*! test_grf_basic.do — GRF basic smoke test
clear all
set more off
set seed 42
set obs 500
gen x1 = rnormal()
gen w  = runiform() > 0.5
gen y  = x1 + w*x1 + rnormal()

* Compute simple nuisance
sum y
gen yhat = r(mean)
sum w
gen what = r(mean)

* Run GRF
capture noisily grf y w x1, generate(p) ntree(50) nproc(2) seed(12345) yhat(yhat) what(what)
if _rc { display as error "FAILED: grf rc=" _rc; exit _rc }

capture noisily confirm variable p
if _rc { display as error "FAILED: output p not created"; exit _rc }

capture noisily assert p != .
if _rc { display as error "FAILED: missing values in p"; exit _rc }

corr y p
local rho = r(rho)
if abs(`rho') < 0.3 { display as error "FAILED: low correlation"; exit _rc }
display "PASSED: grf basic smoke (corr = " %6.4f `rho' ")"
