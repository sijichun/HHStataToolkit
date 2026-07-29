*! test_grf_cluster.do — cluster test
clear all
set more off
set seed 42
set obs 500
gen x1 = rnormal()
gen w = runiform() > 0.5
gen y = x1 + w*x1 + rnormal()
gen cid = mod(_n, 10)
sum y
gen yhat = r(mean)
sum w
gen what = r(mean)

capture noisily grf y w x1, generate(p1) ntree(50) nproc(2) seed(12345) yhat(yhat) what(what) cluster(cid)
if _rc { display as error "FAILED"; exit _rc }

capture noisily grf y w x1, generate(p2) ntree(50) nproc(2) seed(12345) yhat(yhat) what(what) cluster(cid) equalizeclusterweights
if _rc { display as error "FAILED: equalize"; exit _rc }
display "PASSED"
