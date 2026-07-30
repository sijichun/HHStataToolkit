*! Test script for kdensity2 - gnormalize option (group-share weighting)
* Verifies: f_mix = f_cond * p(g) per group; string group vars;
* multi-dimensional grouping; error 198 without group(); r(ngroups).
* N=1000, unequal groups 250/750

clear all
set more off
set obs 1000
set seed 12345

* Unequal groups: 250 vs 750
gen byte g = _n > 250
gen double x = rnormal() + 3*g

capture which kdensity2
if _rc {
    display as error "kdensity2 not found. Run 'make install' first."
    exit 111
}

* -----------------------------------------
* 1. Conditional (default) vs gnormalize: ratio must equal group share
* -----------------------------------------
kdensity2 x, group(g) generate(f_cond) nproc(4)
kdensity2 x, group(g) generate(f_mix) nproc(4) gnormalize

gen double ratio = f_mix / f_cond
gen double expected = cond(g == 0, 0.25, 0.75)
gen double dev = abs(ratio - expected)

quietly summarize dev
display as text _n "{hline 60}"
display as text "Test 1: numeric group, f_mix/f_cond vs sample share"
display as text "  max deviation = " as result %12.4e r(max)
if r(max) > 1e-12 {
    display as error "FAIL: ratio != group share"
    exit 9
}
display as text "  PASS"

* r(ngroups) must be returned correctly
kdensity2 x, group(g) generate(f_r) nproc(4) gnormalize
assert r(ngroups) == 2
display as text "  PASS: r(ngroups) == 2"

* -----------------------------------------
* 2. String group variable: must match numeric-group result
* -----------------------------------------
gen str1 sg = cond(g, "b", "a")
kdensity2 x, group(sg) generate(f_str) nproc(4) gnormalize

gen double dev2 = abs(f_str - f_mix)
quietly summarize dev2
display as text _n "Test 2: string group variable vs numeric"
display as text "  max deviation = " as result %12.4e r(max)
if r(max) > 1e-12 {
    display as error "FAIL: string group result differs"
    exit 9
}
display as text "  PASS"

* -----------------------------------------
* 3. Multiple group variables: shares across combos
*    g (250/750) x g2 (split 50/50 within each g)
* -----------------------------------------
gen byte g2 = mod(_n, 2)
kdensity2 x, group(g g2) generate(f_cond2) nproc(4)
kdensity2 x, group(g g2) generate(f_mix2) nproc(4) gnormalize

gen double share2 = cond(g == 0, 0.125, 0.375)
gen double dev3 = abs(f_mix2 / f_cond2 - share2)
quietly summarize dev3
display as text _n "Test 3: two group variables, f_mix/f_cond vs combo share"
display as text "  max deviation = " as result %12.4e r(max)
if r(max) > 1e-12 {
    display as error "FAIL: multi-group ratio != combo share"
    exit 9
}
display as text "  PASS"

* -----------------------------------------
* 4. gnormalize without group() must exit 198
* -----------------------------------------
capture kdensity2 x, generate(f_bad) gnormalize
local rc = _rc
display as text _n "Test 4: gnormalize without group()"
if `rc' != 198 {
    display as error "FAIL: expected rc 198, got `rc'"
    exit 9
}
display as text "  PASS (rc=198 as expected)"

* -----------------------------------------
* 5. Missing group values: excluded from estimation, result missing;
*    shares computed on the estimation sample only (200 vs 750 of 950)
* -----------------------------------------
clear
set obs 1000
set seed 999
gen double g = _n > 250
gen double x = rnormal() + 3*g
replace g = . in 1/50

kdensity2 x, group(g) generate(f_mc) nproc(4)
kdensity2 x, group(g) generate(f_mm) nproc(4) gnormalize

display as text _n "Test 5: missing group values excluded"

quietly count if missing(g) & !missing(f_mm)
if r(N) > 0 {
    display as error "FAIL: missing-group obs received a density"
    exit 9
}
quietly count if !missing(g) & missing(f_mm)
if r(N) > 0 {
    display as error "FAIL: non-missing-group obs left missing"
    exit 9
}
display as text "  PASS: missing groups excluded, others estimated"

gen double share5 = cond(g == 0, 200/950, 750/950)
gen double dev5 = abs(f_mm / f_mc - share5) if !missing(g)
quietly summarize dev5
display as text "  max deviation from share = " as result %12.4e r(max)
if r(max) > 1e-12 {
    display as error "FAIL: shares not computed on estimation sample"
    exit 9
}
display as text "  PASS: shares based on non-missing sample (200/950, 750/950)"

display as text _n "{hline 60}"
display as result "ALL GNORMALIZE TESTS PASSED"
display as text "{hline 60}"
