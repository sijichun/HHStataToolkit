*! test_lp_cpu_only.do - CPU baseline for LP performance

clear all
set seed 42
set obs 50000
gen double x = rnormal()
gen double y = sin(x) + 0.3 * rnormal()

local t0 = clock(c(current_time), "hms")
nwreg y x, poly(1) generate(yhat)
local t1 = clock(c(current_time), "hms")
local elapsed = (`t1' - `t0') / 1000

display as text "CPU poly=1: " %8.2f `elapsed' " ms"

local t0 = clock(c(current_time), "hms")
nwreg y x, poly(2) generate(yhat2)
local t1 = clock(c(current_time), "hms")
local elapsed = (`t1' - `t0') / 1000

display as text "CPU poly=2: " %8.2f `elapsed' " ms"
