*! _lp_gpu.do - GPU test
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

local gpu_p1 = (`t1' - `t0') / 1000
local gpu_p2 = (`t2' - `t1') / 1000

rename yhat_p1 yhat_p1_gpu
rename yhat_p2 yhat_p2_gpu
keep yhat_p1_gpu yhat_p2_gpu
save "_lp_gpu.dta", replace

display as text "GPU poly=1: " %8.2f `gpu_p1' " ms"
display as text "GPU poly=2: " %8.2f `gpu_p2' " ms"
