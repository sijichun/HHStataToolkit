*! _lp_cpu.do - CPU baseline
clear all
set seed 42
set obs 100000
gen double x = rnormal()
gen double y = sin(x) + 0.3 * rnormal()

local t0 = clock(c(current_time), "hms")
nwreg y x, poly(1) generate(yhat_p1)
local t1 = clock(c(current_time), "hms")

nwreg y x, poly(2) generate(yhat_p2)
local t2 = clock(c(current_time), "hms")

local cpu_p1 = (`t1' - `t0') / 1000
local cpu_p2 = (`t2' - `t1') / 1000

rename yhat_p1 yhat_p1_cpu
rename yhat_p2 yhat_p2_cpu
keep yhat_p1_cpu yhat_p2_cpu
save "_lp_cpu.dta", replace

display as text "CPU poly=1: " %8.2f `cpu_p1' " ms"
display as text "CPU poly=2: " %8.2f `cpu_p2' " ms"
