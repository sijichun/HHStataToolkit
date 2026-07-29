*! test_grf_orthogonalization.do — nuisance test
clear all
set more off
set seed 42
set obs 500
gen x1 = rnormal()
gen w = runiform() > 0.5
gen y = x1 + w*x1 + rnormal()
gen yhat_man = x1
gen what_man = 0.5

* Both provided -> succeed
capture grf y w x1, generate(p1) ntree(50) nproc(2) seed(12345) yhat(yhat_man) what(what_man)
if _rc { display as error "FAILED: both yhat/what"; exit _rc }

* Only yhat -> must fail
capture grf y w x1, generate(p3) ntree(50) nproc(2) seed(12345) yhat(yhat_man)
if _rc == 0 { display as error "FAILED: expected error for yhat-only"; exit _rc }

display "PASSED"
