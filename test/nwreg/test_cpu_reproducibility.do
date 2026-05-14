*! test_cpu_reproducibility.do — CPU single-core vs multi-core reproducibility
*! Tests Silverman/CV 10-run reproducibility for 1-core and 16-core,
*! plus cross-config comparison + timing.
*! Run: stata -b do test/nwreg/test_cpu_reproducibility.do

clear all
set seed 42
set maxvar 10000
local max_cores = c(processors)

display as text _n "{hline 72}"
display as text "nwreg CPU Reproducibility (1-core vs `max_cores'-core)"
display as text "Date: $S_DATE  Time: $S_TIME"
display as text "{hline 72}"

set obs 3000
gen double x1 = rnormal()
gen double y  = x1^2 + rnormal()

* ===== Section 1: Silverman 10-run (1-core) =====
display as text _n "=== Silverman 10-run (1-core) ==="
set processors 1
forvalues i = 1/10 {
    nwreg y x1, bw(silverman) generate(s1_`i')
}
local ok = 1
forvalues i = 1/9 {
    local j = `i' + 1
    gen double d = abs(s1_`i' - s1_`j')
    quietly summarize d
    if r(max) >= 1e-12 {
        local ok = 0
        display as error "FAIL: Silverman 1-core run `i' vs `j': " %12.2e r(max)
    }
    drop d
}
display as text "  Silverman 10-run (1-core): " cond(`ok', "PASS", "FAIL")
drop s1_*

* ===== Section 2: Silverman 10-run (16-core) =====
display as text _n "=== Silverman 10-run (`max_cores'-core) ==="
set processors `max_cores'
forvalues i = 1/10 {
    nwreg y x1, bw(silverman) generate(s2_`i')
}
local ok = 1
forvalues i = 1/9 {
    local j = `i' + 1
    gen double d = abs(s2_`i' - s2_`j')
    quietly summarize d
    if r(max) >= 1e-12 {
        local ok = 0
        display as error "FAIL: Silverman `max_cores'-core run `i' vs `j': " %12.2e r(max)
    }
    drop d
}
display as text "  Silverman 10-run (`max_cores'-core): " cond(`ok', "PASS", "FAIL")
drop s2_*

* ===== Section 3: CV 10-run (1-core) =====
display as text _n "=== CV 10-run (1-core) ==="
set processors 1
forvalues i = 1/10 {
    set seed 123
    nwreg y x1, bw(cv) generate(c1_`i')
}
local ok = 1
forvalues i = 1/9 {
    local j = `i' + 1
    gen double d = abs(c1_`i' - c1_`j')
    quietly summarize d
    if r(max) >= 1e-10 {
        local ok = 0
        display as error "FAIL: CV 1-core run `i' vs `j': " %12.2e r(max)
    }
    drop d
}
display as text "  CV 10-run (1-core): " cond(`ok', "PASS", "FAIL")
drop c1_*

* ===== Section 4: CV 10-run (16-core) =====
display as text _n "=== CV 10-run (`max_cores'-core) ==="
set processors `max_cores'
forvalues i = 1/10 {
    set seed 123
    nwreg y x1, bw(cv) generate(c2_`i')
}
local ok = 1
forvalues i = 1/9 {
    local j = `i' + 1
    gen double d = abs(c2_`i' - c2_`j')
    quietly summarize d
    if r(max) >= 1e-10 {
        local ok = 0
        display as error "FAIL: CV `max_cores'-core run `i' vs `j': " %12.2e r(max)
    }
    drop d
}
display as text "  CV 10-run (`max_cores'-core): " cond(`ok', "PASS", "FAIL")
drop c2_*

* ===== Section 5: Cross-config comparison + timing =====
display as text _n "=== Cross-config comparison + timing ==="
clear all
set seed 42
set obs 10000
gen double x = rnormal()
gen double y = sin(x) + 0.5*rnormal()

* Silverman: 1-core vs 16-core
set processors 1
local t0 = clock(c(current_time), "hms")
nwreg y x, bw(silverman) generate(f1)
local t1 = clock(c(current_time), "hms")
local t1_s = (`t1' - `t0') / 1000

set processors `max_cores'
local t0 = clock(c(current_time), "hms")
nwreg y x, bw(silverman) generate(f16)
local t1 = clock(c(current_time), "hms")
local t16_s = (`t1' - `t0') / 1000

gen double d = abs(f1 - f16)
quietly summarize d
display as text "  Silverman 1 vs `max_cores': max diff = " %12.2e r(max)
local ok = (r(max) < 1e-12)
display as text "  Result: " cond(`ok', "PASS (bit-identical)", "FAIL")
drop d f1 f16

* CV: 1-core vs 16-core
set processors 1
set seed 456
local t0 = clock(c(current_time), "hms")
nwreg y x, bw(cv) generate(f1_cv)
local t1 = clock(c(current_time), "hms")
local t1_cv = (`t1' - `t0') / 1000

set processors `max_cores'
set seed 456
local t0 = clock(c(current_time), "hms")
nwreg y x, bw(cv) generate(f16_cv)
local t1 = clock(c(current_time), "hms")
local t16_cv = (`t1' - `t0') / 1000

gen double d = abs(f1_cv - f16_cv)
quietly summarize d
display as text "  CV 1 vs `max_cores': max diff = " %12.2e r(max)
local ok = (r(max) < 1e-10)
display as text "  Result: " cond(`ok', "PASS (bit-identical)", "FAIL")
drop d f1_cv f16_cv

* Timing summary
display as text _n "  Timing (Silverman, n=10000):"
display as text "    1-core: " %9.4f `t1_s' "s"
display as text "    `max_cores'-core: " %9.4f `t16_s' "s"
if `t16_s' > 0 {
    display as text "    Speedup: " %9.2f `t1_s' / `t16_s' "x"
}
display as text _n "  Timing (CV, n=10000):"
display as text "    1-core: " %9.4f `t1_cv' "s"
display as text "    `max_cores'-core: " %9.4f `t16_cv' "s"
if `t16_cv' > 0 {
    display as text "    Speedup: " %9.2f `t1_cv' / `t16_cv' "x"
}

display as text _n "{hline 72}"
display as text "All CPU tests complete."
display as text "{hline 72}"
exit 0
