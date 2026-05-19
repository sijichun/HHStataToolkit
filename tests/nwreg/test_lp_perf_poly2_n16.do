*! test_lp_perf_poly2_n16.do
*! Single test: poly=2, nproc=16, N=100000

clear all
set seed 42
set maxvar 10000

local max_cores = c(processors)

display as text _n "=== N = 100000, poly=2, nproc=16 ==="

clear
set obs 100000
gen double x = rnormal()
gen double y = sin(x) + 0.3 * rnormal()

local t0 = clock(c(current_time), "hms")
nwreg y x, poly(2) generate(yhat) nproc(16)
local t1 = clock(c(current_time), "hms")
local elapsed = (`t1' - `t0') / 1000

display as text "  poly=2, nproc=16: " %10.2f `elapsed' " ms"
