* Test local polynomial regression

set seed 12345
set obs 200

gen x = runiform() * 4 - 2
gen y = sin(x) + 0.2 * rnormal()

* Test 1: poly=0 should match NW (backward compatibility)
nwreg y x, generate(yhat_nw)

* Test 2: poly=1 (local linear)
nwreg y x, poly(1) generate(yhat_ll)

* Test 3: poly=2 (local quadratic)
nwreg y x, poly(2) generate(yhat_lq)

* Test 4: poly=1 with derivatives
nwreg y x, poly(1) generate(yhat_ll2) derivatives(dydx)

* Test 5: poly=2 with derivatives
nwreg y x, poly(2) generate(yhat_lq2) derivatives(d2ydx)

* Test 6: target split
gen train = runiform() > 0.3
nwreg y x, poly(1) generate(yhat_target) target(train)

* Test 7: CV bandwidth with poly=1
nwreg y x, poly(1) bw(cv) generate(yhat_cv)

* Verify results
summarize yhat_nw yhat_ll yhat_lq yhat_target yhat_cv
summarize dydx1 d2ydx1 d2ydx2

* Check that derivatives exist and are reasonable
assert dydx1 != . if yhat_ll2 != .
assert d2ydx1 != . if yhat_lq2 != .
assert d2ydx2 != . if yhat_lq2 != .

display "All tests passed!"
