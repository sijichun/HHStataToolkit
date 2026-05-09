*! test_csadensity.do  —  Test suite for csadensity command
*! Requires: kdensity2 plugin installed

capture log close
log using test/test_csadensity.log, replace

* Add single_ado path so csadensity can be found
adopath + "`c(pwd)'/single_ado"

set seed 42

* ============================================================
*  Test 1: Basic functionality with the csa.do DGP
* ============================================================

display _n "=== Test 1: Basic functionality ==="

clear
set seed 42
set obs 1000
gen x1 = runiform()*5
gen x2 = runiform()*10
gen treatment = runiform()<0.5
drop if treatment == 0 & (x2>2*x1+rnormal()*0.2 | x2<x1+rnormal()*0.2)
drop if treatment == 1 & (x2>-2*x1+10+rnormal()*0.2 | x2< -x1+5+rnormal()*0.2)

* Run csadensity
csadensity x1 x2, treatment(treatment) generate(csa_cmd)

* Save returned results before count overwrites them
local ret_N_csa = r(N_csa)
local ret_N = r(N)
local ret_threshold = r(threshold)
local ret_treatment = r(treatment)
local ret_varlist = r(varlist)

* Validate output
quietly count if csa_cmd == 1
local n_csa = r(N)
quietly count
assert `n_csa' > 0
assert `n_csa' < r(N)

* Verify returned results
assert `ret_threshold' == 0.2
assert `ret_N_csa' == `n_csa'
assert "`ret_treatment'" == "treatment"
assert "`ret_varlist'" == "x1 x2"

* Verify no missing CSA values for observations in touse
capture assert !missing(csa_cmd)
if _rc {
    display as error "FAILED: Missing CSA values detected"
    exit 198
}

display as result "PASSED: Basic functionality"

* ============================================================
*  Test 2: Categorical variable handling
* ============================================================

display _n "=== Test 2: Non-numeric varlist rejected ==="

clear
set obs 10
gen x = runiform()
gen str_var = "hello"
gen d = 1 in 1/5
replace d = 0 in 6/10

capture csadensity x str_var, treatment(d) generate(csa_bad)
if _rc {
    display as result "PASSED: Non-numeric varlist rejected (rc=" _rc ")"
}
else {
    display as error "FAILED: Should have rejected non-numeric variable"
    exit 198
}

* ============================================================
*  Test 3: Group variable handling
* ============================================================

display _n "=== Test 3: Group variable handling ==="

clear
set seed 42
set obs 1000
gen x1 = runiform()*5
gen x2 = runiform()*10
gen region = ceil(runiform()*3)
gen treatment = runiform()<0.5
drop if treatment == 0 & (x2>2*x1+rnormal()*0.2 | x2<x1+rnormal()*0.2)
drop if treatment == 1 & (x2>-2*x1+10+rnormal()*0.2 | x2< -x1+5+rnormal()*0.2)

csadensity x1 x2, treatment(treatment) generate(csa_grp) group(region)

* Save return results before count overwrites them
local ret_groupvars = r(groupvars)
local ret_N = r(N)
local ret_N_csa = r(N_csa)

quietly count if csa_grp == 1
local n_grp = r(N)
quietly count
assert `n_grp' > 0
assert `n_grp' <= r(N)
assert !missing(csa_grp)

* Check that r(groupvars) is set (saved before count)
assert "`ret_groupvars'" == "region"
display as result "PASSED: Group variable handling"

* ============================================================
*  Test 4: String group variable handling
* ============================================================

display _n "=== Test 4: String group variable handling ==="

clear
set seed 42
set obs 1000
gen x1 = runiform()*5
gen x2 = runiform()*10
gen str_region = cond(runiform()<0.33, "A", cond(runiform()<0.5, "B", "C"))
gen treatment = runiform()<0.5
drop if treatment == 0 & (x2>2*x1+rnormal()*0.2 | x2<x1+rnormal()*0.2)
drop if treatment == 1 & (x2>-2*x1+10+rnormal()*0.2 | x2< -x1+5+rnormal()*0.2)

csadensity x1 x2, treatment(treatment) generate(csa_sgrp) group(str_region)

quietly count if csa_sgrp == 1
local n_sgrp = r(N)
quietly count
assert `n_sgrp' > 0
assert `n_sgrp' <= r(N)
assert !missing(csa_sgrp)
display as result "PASSED: String group variable handling"

* ============================================================
*  Test 5: Different thresholds
* ============================================================

display _n "=== Test 5: Threshold sensitivity ==="

clear
set seed 42
set obs 1000
gen x1 = runiform()*5
gen x2 = runiform()*10
gen treatment = runiform()<0.5
drop if treatment == 0 & (x2>2*x1+rnormal()*0.2 | x2<x1+rnormal()*0.2)
drop if treatment == 1 & (x2>-2*x1+10+rnormal()*0.2 | x2< -x1+5+rnormal()*0.2)

csadensity x1 x2, treatment(treatment) generate(csa_lo) threshold(0.05)
csadensity x1 x2, treatment(treatment) generate(csa_hi) threshold(0.40)

quietly count if csa_lo == 1
local n_lo = r(N)
quietly count if csa_hi == 1
local n_hi = r(N)

assert `n_lo' >= `n_hi'
display as result "PASSED: Threshold sensitivity"

* ============================================================
*  Test 6: if/in qualifiers
* ============================================================

display _n "=== Test 6: if/in qualifiers ==="

clear
set seed 42
set obs 1000
gen x1 = runiform()*5
gen x2 = runiform()*10
gen treatment = runiform()<0.5
drop if treatment == 0 & (x2>2*x1+rnormal()*0.2 | x2<x1+rnormal()*0.2)
drop if treatment == 1 & (x2>-2*x1+10+rnormal()*0.2 | x2< -x1+5+rnormal()*0.2)
gen subset = runiform() < 0.8

csadensity x1 x2 if subset == 1, treatment(treatment) generate(csa_if)

quietly count if csa_if == 1
local n_if = r(N)
quietly count if subset == 1
assert `n_if' <= r(N)
display as result "PASSED: if qualifier"

* ============================================================
*  Test 7: Error handling
* ============================================================

display _n "=== Test 7: Error handling ==="

clear
set obs 10
gen x = runiform()
gen d = 1
capture csadensity x, treatment(d) generate(csa_err)
assert _rc != 0
display as result "PASSED: Rejected constant treatment"

clear
set obs 10
gen x = runiform()
gen d = runiform()
capture csadensity x, treatment(d) generate(csa_err2)
assert _rc != 0
display as result "PASSED: Rejected non-binary treatment"

* ============================================================
*  Test 8: Missing density handling
* ============================================================

display _n "=== Test 8: Missing density handling ==="

clear
set seed 42
set obs 1000
gen x1 = runiform()*5
gen x2 = runiform()*10
gen treatment = runiform()<0.5
drop if treatment == 0 & (x2>2*x1+rnormal()*0.2 | x2<x1+rnormal()*0.2)
drop if treatment == 1 & (x2>-2*x1+10+rnormal()*0.2 | x2< -x1+5+rnormal()*0.2)

* Run csadensity with very high threshold — if missing values were
* incorrectly treated as > threshold, csa_high would be 1 for obs
* with missing density. Instead, they should be 0.
csadensity x1 x2, treatment(treatment) generate(csa_high) threshold(100)

* In a well-behaved dataset, threshold=100 should yield 0 CSA obs
quietly count if csa_high == 1
assert r(N) == 0
display as result "PASSED: Missing density values excluded correctly"

* ============================================================
*  Summary
* ============================================================

display _n as result "=== ALL TESTS PASSED ==="

log close
