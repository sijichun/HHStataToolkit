*! test_local_polynomial_reproducibility.do
*! Comprehensive reproducibility and edge-case tests for local polynomial regression
*! Run: stata -b do test/nwreg/test_local_polynomial_reproducibility.do

clear all
set seed 42
set maxvar 10000

local max_cores = c(processors)

display as text _n "{hline 72}"
display as text "Local Polynomial Regression Test Suite"
display as text "Date: $S_DATE  Time: $S_TIME"
display as text "{hline 72}"

set obs 1000
gen double x = rnormal()
gen double y = sin(x) + 0.3 * rnormal()
gen double x2 = rnormal()

* ================================================================
* Test 1: Backward compatibility - poly(0) should match NW exactly
* ================================================================
display as text _n "=== Test 1: Backward compatibility ==="

nwreg y x, generate(yhat_nw)
nwreg y x, poly(0) generate(yhat_poly0)

gen double diff = abs(yhat_nw - yhat_poly0)
quietly summarize diff
if r(max) < 1e-12 {
    display as text "  PASS: poly(0) matches NW (max diff: " %12.2e r(max) ")"
}
else {
    display as error "  FAIL: poly(0) differs from NW (max diff: " %12.2e r(max) ")"
}
drop diff yhat_nw yhat_poly0

* ================================================================
* Test 2: Reproducibility - same seed gives same results
* ================================================================
display as text _n "=== Test 2: Reproducibility ==="

set seed 999
nwreg y x, poly(1) generate(yhat_a)
set seed 999
nwreg y x, poly(1) generate(yhat_b)

gen double diff = abs(yhat_a - yhat_b)
quietly summarize diff
if r(max) < 1e-12 {
    display as text "  PASS: Reproducible (max diff: " %12.2e r(max) ")"
}
else {
    display as error "  FAIL: Not reproducible (max diff: " %12.2e r(max) ")"
}
drop diff yhat_a yhat_b

* ================================================================
* Test 3: 1-core vs multi-core bit-identical
* ================================================================
display as text _n "=== Test 3: 1-core vs " `max_cores' "-core ==="

set processors 1
nwreg y x, poly(1) generate(yhat_1c)

set processors `max_cores'
nwreg y x, poly(1) generate(yhat_mc)

gen double diff = abs(yhat_1c - yhat_mc)
quietly summarize diff
if r(max) == 0 {
    display as text "  PASS: Bit-identical (max diff: " %12.2e r(max) ")"
}
else {
    display as error "  FAIL: Non-deterministic (max diff: " %12.2e r(max) ")"
}
drop diff yhat_1c yhat_mc

* ================================================================
* Test 4: Multivariate with poly(1)
* ================================================================
display as text _n "=== Test 4: Multivariate poly(1) ==="

nwreg y x x2, poly(1) generate(yhat_mv)
quietly summarize yhat_mv
if r(N) == 1000 {
    display as text "  PASS: Multivariate poly(1) runs (N=" r(N) ")"
}
else {
    display as error "  FAIL: Multivariate poly(1) incomplete"
}
drop yhat_mv

* ================================================================
* Test 5: Error handling - poly>1 with multivariate
* ================================================================
display as text _n "=== Test 5: Error handling (poly>1 + MV) ==="

capture nwreg y x x2, poly(2)
if _rc != 0 {
    display as text "  PASS: Correctly rejects poly(2) with 2 regressors (rc=" _rc ")"
}
else {
    display as error "  FAIL: Should have rejected poly(2) with MV"
}

* ================================================================
* Test 6: Derivatives with poly(2)
* ================================================================
display as text _n "=== Test 6: Derivatives ==="

nwreg y x, poly(2) generate(yhat_d) derivatives(deriv)
quietly summarize deriv1 deriv2
if r(min) != . {
    display as text "  PASS: Derivatives generated (d1 range: " %9.4f r(min) " to " %9.4f r(max) ")"
}
else {
    display as error "  FAIL: Derivatives missing"
}
drop yhat_d deriv*

* ================================================================
* Test 7: CV bandwidth with poly(1)
* ================================================================
display as text _n "=== Test 7: CV bandwidth ==="

set seed 123
nwreg y x, poly(1) bw(cv) generate(yhat_cv)
quietly summarize yhat_cv
if r(N) == 1000 {
    display as text "  PASS: CV + poly(1) works (N=" r(N) ")"
}
else {
    display as error "  FAIL: CV + poly(1) incomplete"
}
drop yhat_cv

* ================================================================
* Test 8: Target split + poly(1)
* ================================================================
display as text _n "=== Test 8: Target split ==="

gen train = runiform() > 0.3
nwreg y x, poly(1) target(train) generate(yhat_ts)
quietly summarize yhat_ts
if r(N) == 1000 {
    display as text "  PASS: Target split + poly(1) works"
}
else {
    display as error "  FAIL: Target split + poly(1) incomplete"
}
drop yhat_ts train

* ================================================================
* Test 9: Group + poly(1)
* ================================================================
display as text _n "=== Test 9: Grouped estimation ==="

gen group = mod(_n, 3)
nwreg y x, poly(1) group(group) generate(yhat_g)
quietly summarize yhat_g
if r(N) > 0 {
    display as text "  PASS: Grouped poly(1) works (N=" r(N) ")"
}
else {
    display as error "  FAIL: Grouped poly(1) failed"
}
drop yhat_g group

* ================================================================
* Test 10: se() rejected with poly>0
* ================================================================
display as text _n "=== Test 10: se() rejected with poly>0 ==="

capture nwreg y x, poly(1) se(yse)
if _rc == 198 {
    display as text "  PASS: Correctly rejects se() with poly(1)"
}
else {
    display as error "  FAIL: Should have rejected se() with poly>0 (rc=" _rc ")"
}

display as text _n "{hline 72}"
display as text "Test suite complete."
display as text "{hline 72}"
