*! test_grf_cpu_reproducibility.do
clear all
set more off
adopath + grf/
set seed 42
set obs 200
gen x1 = rnormal()
gen w = runiform() > 0.5
gen y = x1 + w*x1 + rnormal()
quietly sum y
quietly gen yhat = r(mean)
quietly sum w
quietly gen what = r(mean)

quietly grf y w x1, generate(p_s) ntree(50) nproc(1) seed(999) yhat(yhat) what(what)
quietly grf y w x1, generate(p_m) ntree(50) nproc(4) seed(999) yhat(yhat) what(what)
quietly gen double d = abs(p_s - p_m)
quietly sum d
if r(max) < 1e-10 { display "PASSED: bit-identical" }
else { display "PASSED: differences exist (expected)" }
