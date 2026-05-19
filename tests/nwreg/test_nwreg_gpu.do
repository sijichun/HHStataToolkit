*! nwreg GPU benchmark and correctness test
*!
*! Sections:
*!   1. Performance Benchmark — Silverman bandwidth across N sizes
*!   2. Performance Benchmark — CV bandwidth across N sizes
*!   3. GPU correctness tests (multivariate, target split, grouped, CV)
*!
*! CPU thread count controlled via set processors N.
*! The ado layer passes nproc=c(processors) to the C plugin, which calls
*! omp_set_num_threads(nproc) at each stata_call().
*!
*! DGP: y = sin(x1) + 0.5*log(|x2|+1) + 0.3*x3^2 + eps
*!      eps ~ N(0, 0.2 + 0.3*|x1|)  (heteroskedastic)
*!
*! Run: stata -b do test/nwreg/test_nwreg_gpu.do

clear all
set seed 42
local max_cores = c(processors)

display as text _n "{hline 88}"
display as text "nwreg GPU Performance Benchmark"
display as text "Date: $S_DATE  Time: $S_TIME   Cores: `max_cores'"
display as text "{hline 88}"

* Check if GPU plugin exists
capture confirm file "nwreg/nwreg_cuda.plugin"
local have_gpu = (_rc == 0)
if !`have_gpu' {
    display as error "nwreg_cuda.plugin not found. GPU tests will be skipped."
    display as error "Run 'make nwreg_cuda' to build the GPU plugin."
}

* =========================================================================
* Section 1: Performance Benchmark — Silverman bandwidth
* DGP: y = sin(x1) + 0.5*log(|x2|+1) + 0.3*x3^2 + eps
*      eps ~ N(0, 0.2 + 0.3*|x1|)
* =========================================================================
display as text _n "Section 1: 3-Variate Regression (Gaussian kernel, Silverman bw)"
display as text "DGP: y = sin(x1) + 0.5*log(|x2|+1) + 0.3*x3^2 + eps, eps ~ heteroskedastic"
display as text "{hline 88}"
display as text "  {hline 80}"
display as text "  {bf:N}       {bf:OMP}    {bf:CPU 1t}  {bf:CPU Nt}  {bf:GPU}    {bf:Status}"
display as text "  {bf:}        {bf:}      {bf:(ms)}    {bf:(ms)}    {bf:(ms)}"
display as text "  {hline 80}"

local sizes "1000 5000 10000 50000 100000"
foreach n of local sizes {

    clear
    set obs `n'
    * Multivariate DGP with heteroskedastic noise
    gen double x1 = rnormal()
    gen double x2 = runiform(-3, 3)
    gen double x3 = rchi2(3)
    gen double y  = sin(x1) + 0.5*ln(abs(x2) + 1) + 0.3*x3^2 ///
                  + rnormal(0, sqrt(0.2 + 0.3*abs(x1)))

    * --- CPU single-core (OMP_NUM_THREADS=1) ---
    set processors 1
    local t0 = clock(c(current_time), "hms")
    capture nwreg y x1 x2 x3, generate(yhat_cpu1) kernel(gaussian) bw(silverman)
    local t1 = clock(c(current_time), "hms")
    local cpu1_ms = `t1' - `t0'
    local cpu1_rc = _rc

    * --- CPU multi-core (OMP_NUM_THREADS=max) ---
    set processors `max_cores'
    local t0 = clock(c(current_time), "hms")
    capture nwreg y x1 x2 x3, generate(yhat_cpum) kernel(gaussian) bw(silverman)
    local t1 = clock(c(current_time), "hms")
    local cpum_ms = `t1' - `t0'
    local cpum_rc = _rc

    * --- GPU (if available) ---
    if `have_gpu' {
        local t0 = clock(c(current_time), "hms")
        capture nwreg y x1 x2 x3, generate(yhat_gpu) kernel(gaussian) bw(silverman) gpu(0)
        local t1 = clock(c(current_time), "hms")
        local gpu_ms = `t1' - `t0'
        local gpu_rc = _rc
    }
    else {
        local gpu_ms = .
        local gpu_rc = 111
    }

    local ok = (`cpu1_rc' == 0 & `cpum_rc' == 0)
    local status_txt ""
    if `ok' {
        if `gpu_rc' == 0  local status_txt "OK"
        else               local status_txt "GPU rc=`gpu_rc'"
    }
    else {
        if `cpu1_rc' != 0 local status_txt "CPU1 rc=`cpu1_rc'"
        else              local status_txt "CPUn rc=`cpum_rc'"
    }

    display as text "  %8s" "`: di %8.0fc `n''" ///
        _col(11) "1/`max_cores'" ///
        _col(21) as result %9.2f `cpu1_ms' ///
        _col(31) %9.2f `cpum_ms' ///
        _col(42) as result %9.2f `gpu_ms' ///
        _col(53) as text "`status_txt'"

    capture drop x1 x2 x3 y yhat_*
    drop _all
}

display as text "  {hline 80}"

* =========================================================================
* Section 2: Performance Benchmark — CV bandwidth
* CV is O(N^2 × nreg) — use smaller N
* =========================================================================
if `have_gpu' {
    display as text _n "Section 2: 3-Variate Regression — CV Bandwidth"
    display as text "{hline 88}"
    display as text "  {hline 80}"
    display as text "  {bf:N}       {bf:OMP}    {bf:CPU 1t}  {bf:CPU Nt}  {bf:GPU}    {bf:Status}"
    display as text "  {bf:}        {bf:}      {bf:(ms)}    {bf:(ms)}    {bf:(ms)}"
    display as text "  {hline 80}"

    local sizes "500 1000 2000 5000 10000"
    foreach n of local sizes {

        clear
        set obs `n'
        gen double x1 = rnormal()
        gen double x2 = runiform(-3, 3)
        gen double y  = sin(x1) + 0.5*ln(abs(x2) + 1) + rnormal(0, 0.3)

        * --- CPU single-core ---
        set seed 42
        set processors 1
        local t0 = clock(c(current_time), "hms")
        capture nwreg y x1 x2, generate(yhat_cpu1) kernel(gaussian) bw(cv) folds(5) grids(5)
        local t1 = clock(c(current_time), "hms")
        local cpu1_ms = `t1' - `t0'
        local cpu1_rc = _rc

        * --- CPU multi-core ---
        set seed 42
        set processors `max_cores'
        local t0 = clock(c(current_time), "hms")
        capture nwreg y x1 x2, generate(yhat_cpum) kernel(gaussian) bw(cv) folds(5) grids(5)
        local t1 = clock(c(current_time), "hms")
        local cpum_ms = `t1' - `t0'
        local cpum_rc = _rc

        * --- GPU ---
        set seed 42
        local t0 = clock(c(current_time), "hms")
        capture nwreg y x1 x2, generate(yhat_gpu) kernel(gaussian) bw(cv) folds(5) grids(5) gpu(0)
        local t1 = clock(c(current_time), "hms")
        local gpu_ms = `t1' - `t0'
        local gpu_rc = _rc

        local ok = (`cpu1_rc' == 0 & `cpum_rc' == 0)
        local status_txt ""
        if `ok' {
            if `gpu_rc' == 0  local status_txt "OK"
            else               local status_txt "GPU rc=`gpu_rc'"
        }
        else {
            if `cpu1_rc' != 0 local status_txt "CPU1 rc=`cpu1_rc'"
            else              local status_txt "CPUn rc=`cpum_rc'"
        }

        display as text "  %8s" "`: di %8.0fc `n''" ///
            _col(11) "1/`max_cores'" ///
            _col(21) as result %9.2f `cpu1_ms' ///
            _col(31) %9.2f `cpum_ms' ///
            _col(42) as result %9.2f `gpu_ms' ///
            _col(53) as text "`status_txt'"

        capture drop x1 x2 y yhat_*
        drop _all
    }
    display as text "  {hline 80}"
}

* =========================================================================
* Section 3: GPU Correctness — Multivariate regression (CPU vs GPU parity)
* =========================================================================
display as text _n "{hline 88}"
display as text "Section 3: GPU Correctness Tests"
display as text "{hline 88}"

* --- Test 3a: 1D regression — cross-check CPU vs GPU ---
display as text _n "  Test 3a: 1D regression — CPU/GPU parity (n=50000)"

clear
set obs 50000
gen double x = rnormal()
gen double y = sin(x) + 0.5*rnormal()

set processors 1
nwreg y x, generate(yhat_cpu1) kernel(gaussian) bw(silverman)

set processors `max_cores'
nwreg y x, generate(yhat_cpum) kernel(gaussian) bw(silverman)

if `have_gpu' {
    nwreg y x, generate(yhat_gpu) kernel(gaussian) bw(silverman) gpu(0)
    gen double diff_cpu1_gpu = abs(yhat_cpu1 - yhat_gpu)
    gen double diff_cpum_gpu = abs(yhat_cpum - yhat_gpu)
    summarize diff_cpu1_gpu, meanonly
    local max_diff1 = r(max)
    summarize diff_cpum_gpu, meanonly
    local max_diffm = r(max)

    display as text "    Max |CPU1 - GPU|: " as result %12.6e `max_diff1'
    display as text "    Max |CPU`max_cores' - GPU|: " as result %12.6e `max_diffm'

    if `max_diff1' > 1e-4 {
        display as error "    FAIL: CPU1 vs GPU difference too large"
        exit 1
    }
    if `max_diffm' > 1e-4 {
        display as error "    FAIL: CPU`max_cores' vs GPU difference too large"
        exit 1
    }
    display as text "    Result: " as result "PASS"
}
else {
    display as text "    GPU not available — skipping"
}

drop x y yhat_cpu1 yhat_cpum yhat_gpu diff_cpu1_gpu diff_cpum_gpu

* --- Test 3b: Multivariate regression ---
display as text _n "  Test 3b: Multivariate regression (n=20000)"

clear
set obs 20000
gen double x1 = rnormal()
gen double x2 = runiform(-2, 2)
gen double y  = x1 + 2*cos(x2) + 0.5*rnormal()

nwreg y x1 x2, generate(yhat_cpu) kernel(gaussian) bw(silverman)

if `have_gpu' {
    nwreg y x1 x2, generate(yhat_gpu) kernel(gaussian) bw(silverman) gpu(0)
    gen double diff = abs(yhat_cpu - yhat_gpu)
    summarize diff, meanonly
    local max_diff = r(max)
    display as text "    Max |CPU - GPU|: " as result %12.6e `max_diff'

    if `max_diff' > 1e-4 {
        display as error "    FAIL: Multivariate CPU vs GPU difference too large"
        exit 1
    }
    display as text "    Result: " as result "PASS"
}
else {
    display as text "    GPU not available — skipping"
}

drop x1 x2 y yhat_cpu yhat_gpu diff

* --- Test 3c: Target split ---
display as text _n "  Test 3c: Target split (n=10000)"

clear
set obs 10000
gen double x = rnormal()
gen double y = sin(x) + 0.3*rnormal()
gen byte target = (_n > 7000)

nwreg y x, generate(yhat_cpu) target(target) kernel(gaussian) bw(silverman)

if `have_gpu' {
    nwreg y x, generate(yhat_gpu) target(target) kernel(gaussian) bw(silverman) gpu(0)
    gen double diff = abs(yhat_cpu - yhat_gpu)
    summarize diff, meanonly
    local max_diff = r(max)
    display as text "    Max |CPU - GPU|: " as result %12.6e `max_diff'

    if `max_diff' > 1e-4 {
        display as error "    FAIL: Target split CPU vs GPU difference too large"
        exit 1
    }
    display as text "    Result: " as result "PASS"
}
else {
    display as text "    GPU not available — skipping"
}

drop x y target yhat_cpu yhat_gpu diff

* --- Test 3d: Grouped regression ---
display as text _n "  Test 3d: Grouped regression (n=15000)"

clear
set obs 15000
gen double group = ceil(_n / 5000)
gen double x = rnormal()
gen double y = sin(x) + group*0.5 + 0.3*rnormal()

nwreg y x, generate(yhat_cpu) group(group) kernel(gaussian) bw(silverman)

if `have_gpu' {
    nwreg y x, generate(yhat_gpu) group(group) kernel(gaussian) bw(silverman) gpu(0)
    gen double diff = abs(yhat_cpu - yhat_gpu)
    summarize diff, meanonly
    local max_diff = r(max)
    display as text "    Max |CPU - GPU|: " as result %12.6e `max_diff'

    if `max_diff' > 1e-4 {
        display as error "    FAIL: Grouped CPU vs GPU difference too large"
        exit 1
    }
    display as text "    Result: " as result "PASS"
}
else {
    display as text "    GPU not available — skipping"
}

drop group x y yhat_cpu yhat_gpu diff

* --- Test 3e: CV bandwidth selection ---
display as text _n "  Test 3e: CV bandwidth (n=5000)"

clear
set obs 5000
gen double x = rnormal()
gen double y = sin(x) + 0.3*rnormal()

nwreg y x, generate(yhat_cpu) kernel(gaussian) bw(cv) folds(5) grids(5)

if `have_gpu' {
    nwreg y x, generate(yhat_gpu) kernel(gaussian) bw(cv) folds(5) grids(5) gpu(0)
    gen double diff = abs(yhat_cpu - yhat_gpu)
    summarize diff, meanonly
    local max_diff = r(max)
    display as text "    Max |CPU - GPU|: " as result %12.6e `max_diff'

    if `max_diff' > 1e-4 {
        display as error "    FAIL: CV bandwidth CPU vs GPU difference too large"
        exit 1
    }
    display as text "    Result: " as result "PASS"
}
else {
    display as text "    GPU not available — skipping"
}

drop x y yhat_cpu yhat_gpu diff

* =========================================================================
* Summary
* =========================================================================
display as text _n "{hline 88}"
display as text "Benchmark Summary"
display as text "{hline 88}"
display as text _n "  Configuration:"
display as text "    CPU cores available: `max_cores'"
if `have_gpu' {
    display as text "    GPU plugin: available"
}
else {
    display as text "    GPU plugin: NOT available (skip GPU columns)"
}
display as text "    CPU thread control: set processors → nproc plugin option"
display as text "    Timing method: clock(c(current_time), 'hms') — 1 s resolution"
display as text ""
display as text "  Interpretation:"
display as text "    - CPU 1t: set processors 1 (nproc=1 passed to plugin)"
display as text "    - CPU Nt: set processors `max_cores' (nproc=`max_cores')"
display as text "    - GPU: CUDA float path (if available)"
display as text "    - All times in milliseconds (ms)"
display as text "    - 0.00 ms means < 1 clock tick (< 1000 ms)"
display as text "{hline 88}"

display as text _n "All tests completed."
exit 0
