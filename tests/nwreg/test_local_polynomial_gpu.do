*! test_local_polynomial_gpu.do
*! CPU vs GPU comparison for local polynomial regression
*! Run: stata -b do test/nwreg/test_local_polynomial_gpu.do

clear all
set seed 42
set maxvar 10000

display as text _n "{hline 80}"
display as text "Local Polynomial Regression: CPU vs GPU Comparison"
display as text "Date: $S_DATE  Time: $S_TIME"
display as text "{hline 80}"

set obs 5000
gen double x = rnormal()
gen double y = sin(x) + 0.3 * rnormal()

* ================================================================
* Phase 1: CPU (nwreg.plugin)
* ================================================================
display as text _n "=== CPU Phase ==="

local t0 = clock(c(current_time), "hms")
nwreg y x, poly(1) generate(yhat_cpu_p1)
local t1 = clock(c(current_time), "hms")
local cpu_p1 = (`t1' - `t0') / 1000

display as text "  poly=1 CPU: " %8.2f `cpu_p1' " ms"

local t0 = clock(c(current_time), "hms")
nwreg y x, poly(2) generate(yhat_cpu_p2)
local t1 = clock(c(current_time), "hms")
local cpu_p2 = (`t1' - `t0') / 1000

display as text "  poly=2 CPU: " %8.2f `cpu_p2' " ms"

* ================================================================
* Phase 2: GPU (nwreg_cuda.plugin → nwreg.plugin)
* ================================================================
display as text _n "=== GPU Phase ==="

* Backup CPU plugin and copy GPU plugin
shell cp ~/ado/plus/nwreg.plugin ~/ado/plus/nwreg.plugin.cpu_backup 2>/dev/null || cp nwreg/nwreg.plugin ~/ado/plus/nwreg.plugin.cpu_backup
shell cp nwreg/nwreg_cuda.plugin ~/ado/plus/nwreg.plugin

* Force reload
program drop _nwreg_plugin
capture program _nwreg_plugin, plugin using("~/ado/plus/nwreg.plugin")

local t0 = clock(c(current_time), "hms")
nwreg y x, poly(1) generate(yhat_gpu_p1)
local t1 = clock(c(current_time), "hms")
local gpu_p1 = (`t1' - `t0') / 1000

display as text "  poly=1 GPU: " %8.2f `gpu_p1' " ms"

local t0 = clock(c(current_time), "hms")
nwreg y x, poly(2) generate(yhat_gpu_p2)
local t1 = clock(c(current_time), "hms")
local gpu_p2 = (`t1' - `t0') / 1000

display as text "  poly=2 GPU: " %8.2f `gpu_p2' " ms"

* ================================================================
* Phase 3: Compare results
* ================================================================
display as text _n "=== Accuracy Comparison ==="

gen double diff_p1 = abs(yhat_cpu_p1 - yhat_gpu_p1)
quietly summarize diff_p1

display as text "  poly=1 max diff: " %12.6e r(max)
display as text "  poly=1 mean diff: " %12.6e r(mean)

gen double diff_p2 = abs(yhat_cpu_p2 - yhat_gpu_p2)
quietly summarize diff_p2

display as text "  poly=2 max diff: " %12.6e r(max)
display as text "  poly=2 mean diff: " %12.6e r(mean)

* ================================================================
* Phase 4: Cleanup & Restore
* ================================================================
shell cp ~/ado/plus/nwreg.plugin.cpu_backup ~/ado/plus/nwreg.plugin
program drop _nwreg_plugin

display as text _n "{hline 80}"
display as text "CPU vs GPU test complete."
display as text "Speedup poly=1: " %5.2f (`cpu_p1' / `gpu_p1') "x"
display as text "Speedup poly=2: " %5.2f (`cpu_p2' / `gpu_p2') "x"
display as text "{hline 80}"
