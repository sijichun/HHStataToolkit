*! test_local_polynomial_gpu_compare.do
*! Compare CPU vs GPU results for local polynomial regression

clear all
set seed 42
set maxvar 10000

display as text _n "{hline 80}"
display as text "Local Polynomial: CPU vs GPU Result Comparison"
display as text "{hline 80}"

set obs 100000
gen double x = rnormal()
gen double y = sin(x) + 0.3 * rnormal()

* Save data for second run
save "_lp_test_data.dta", replace

* ================================================================
* CPU run
* ================================================================
display as text _n "=== CPU ==="

local t0 = clock(c(current_time), "hms")
nwreg y x, poly(1) generate(yhat_cpu_p1)
local t1 = clock(c(current_time), "hms")
local cpu_p1 = (`t1' - `t0') / 1000

nwreg y x, poly(2) generate(yhat_cpu_p2)
local t2 = clock(c(current_time), "hms")
local cpu_p2 = (`t2' - `t1') / 1000

display as text "  poly=1: " %8.2f `cpu_p1' " ms"
display as text "  poly=2: " %8.2f `cpu_p2' " ms"

keep yhat_cpu_p1 yhat_cpu_p2
save "_lp_cpu_results.dta", replace

* ================================================================
* GPU run (reload data, plugin was swapped externally)
* ================================================================
display as text _n "=== GPU ==="

use "_lp_test_data.dta", clear

local t0 = clock(c(current_time), "hms")
nwreg y x, poly(1) generate(yhat_gpu_p1)
local t1 = clock(c(current_time), "hms")
local gpu_p1 = (`t1' - `t0') / 1000

nwreg y x, poly(2) generate(yhat_gpu_p2)
local t2 = clock(c(current_time), "hms")
local gpu_p2 = (`t2' - `t1') / 1000

display as text "  poly=1: " %8.2f `gpu_p1' " ms"
display as text "  poly=2: " %8.2f `gpu_p2' " ms"

keep yhat_gpu_p1 yhat_gpu_p2
save "_lp_gpu_results.dta", replace

* ================================================================
* Compare
* ================================================================
display as text _n "=== Comparison ==="

use "_lp_cpu_results.dta", clear
merge 1:1 _n using "_lp_gpu_results.dta", nogen

gen double diff_p1 = abs(yhat_cpu_p1 - yhat_gpu_p1)
quietly summarize diff_p1
display as text "  poly=1 max diff: " %12.6e r(max) "  mean: " %12.6e r(mean)

gen double diff_p2 = abs(yhat_cpu_p2 - yhat_gpu_p2)
quietly summarize diff_p2
display as text "  poly=2 max diff: " %12.6e r(max) "  mean: " %12.6e r(mean)

display as text _n "Speedup poly=1: " %5.2f (`cpu_p1' / `gpu_p1') "x"
display as text "Speedup poly=2: " %5.2f (`cpu_p2' / `gpu_p2') "x"

display as text _n "{hline 80}"

* Cleanup
shell rm -f _lp_test_data.dta _lp_cpu_results.dta _lp_gpu_results.dta
