*! test_gpu_benchmark.do — Performance benchmark for kdensity2
*!
*! Compares single-core, multi-core CPU and GPU computation time
*! across various dataset sizes with complex multi-modal data.
*!
*! CPU thread count controlled via set processors N.
*! The ado layer passes nproc=c(processors) to the C plugin, which calls
*! omp_set_num_threads(nproc) at each stata_call().
*!
*! Alternatively, set OMP_NUM_THREADS in the shell environment before starting
*! Stata, which the C plugin reads via UTILS_OMP_SET_NTHREADS().
*!
*! Units: Milliseconds (ms). clock() diff is in ms (1 sec precision).
*!
*! Note: GPU uses float internally for ~2x performance over double.
*!       CPU always uses double precision.
*!
*! Methodology:
*!   - Wall-clock time via clock(c(current_time), "hms") (1 s precision)
*!   - Single iteration per N size
*!   - CPU single-core: set processors 1 (nproc=1 passed to C plugin)
*!   - CPU multi-core:  set processors N (nproc=N passed to C plugin)
*!   - GPU calls are capture-wrapped; GPU failures do not abort the benchmark
*!   - All runs use the same random seed for reproducibility
*!
*! Requires: kdensity2 installed, kdensity2_cuda.plugin for GPU tests
*!
*! Run: stata -b do test/kdensity2/test_gpu_benchmark.do

capture cd ".."

clear all
set seed 42
local max_cores = c(processors)

display as text _n "{hline 88}"
display as text "kdensity2 GPU Performance Benchmark"
display as text "Date: $S_DATE  Time: $S_TIME   Cores: `max_cores'"
display as text "{hline 88}"

* =========================================================================
* Section 1: Silverman bandwidth — Bimodal normal mixture
* Data: 0.5*N(-2, 0.5) + 0.5*N(2, 0.5) — bimodal, more realistic
* =========================================================================
display as text _n "Section 1: 1D Density — Bimodal Mixture (Gaussian kernel, Silverman bw)"
display as text "{hline 88}"
display as text "  {hline 80}"
display as text "  {bf:N}       {bf:OMP}    {bf:CPU 1t}  {bf:CPU Nt}  {bf:GPU}    {bf:Status}"
display as text "  {bf:}        {bf:}      {bf:(ms)}    {bf:(ms)}    {bf:(ms)}"
display as text "  {hline 80}"

local sizes "1000 5000 10000 50000 100000"
foreach n of local sizes {

    clear
    set obs `n'
    * Bimodal mixture: 0.5*N(-2, 0.5) + 0.5*N(2, 0.5)
    gen byte   _g = runiform() < 0.5
    gen double _x = cond(_g, rnormal(-2, 0.5), rnormal(2, 0.5))
    drop _g
    rename _x x

    * --- CPU single-core (OMP_NUM_THREADS=1) ---
    set processors 1
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 x, generate(f_cpu1) kernel(gaussian)
    local t1 = clock(c(current_time), "hms")
    local cpu1_ms = `t1' - `t0'
    local cpu1_rc = _rc

    * --- CPU multi-core (OMP_NUM_THREADS=max) ---
    set processors `max_cores'
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 x, generate(f_cpum) kernel(gaussian)
    local t1 = clock(c(current_time), "hms")
    local cpum_ms = `t1' - `t0'
    local cpum_rc = _rc

    * --- GPU timing ---
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 x, generate(f_gpu) kernel(gaussian) gpu(0)
    local t1 = clock(c(current_time), "hms")
    local gpu_ms = `t1' - `t0'
    local gpu_rc = _rc

    * Format display
    local ok = (`cpu1_rc' == 0 & `cpum_rc' == 0)
    local status_txt ""
    if `ok' {
        if `gpu_rc' == 0 local status_txt "OK"
        else              local status_txt "GPU rc=`gpu_rc'"
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

    drop _all
}

display as text "  {hline 80}"

* =========================================================================
* Section 2: CV bandwidth — Bimodal mixture (CV is O(N^2), smaller N)
* =========================================================================
display as text _n "Section 2: 1D Density — Bimodal Mixture with CV Bandwidth"
display as text "{hline 88}"
display as text "  {hline 80}"
display as text "  {bf:N}       {bf:OMP}    {bf:CPU 1t}  {bf:CPU Nt}  {bf:GPU}    {bf:Status}"
display as text "  {bf:}        {bf:}      {bf:(ms)}    {bf:(ms)}    {bf:(ms)}"
display as text "  {hline 80}"

local sizes "500 1000 2000 5000 10000"
foreach n of local sizes {

    clear
    set obs `n'
    * Bimodal mixture (same as above)
    gen byte   _g = runiform() < 0.5
    gen double _x = cond(_g, rnormal(-2, 0.5), rnormal(2, 0.5))
    drop _g
    rename _x x

    set seed 42   * Fixed seed for CV fold shuffle reproducibility

    * --- CPU single-core ---
    set processors 1
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 x, generate(f_cpu1) kernel(gaussian) bw(cv)
    local t1 = clock(c(current_time), "hms")
    local cpu1_ms = `t1' - `t0'
    local cpu1_rc = _rc

    * --- CPU multi-core ---
    set processors `max_cores'
    set seed 42
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 x, generate(f_cpum) kernel(gaussian) bw(cv)
    local t1 = clock(c(current_time), "hms")
    local cpum_ms = `t1' - `t0'
    local cpum_rc = _rc

    * --- GPU timing ---
    set seed 42
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 x, generate(f_gpu) kernel(gaussian) bw(cv) gpu(0)
    local t1 = clock(c(current_time), "hms")
    local gpu_ms = `t1' - `t0'
    local gpu_rc = _rc

    local ok = (`cpu1_rc' == 0 & `cpum_rc' == 0)
    local status_txt ""
    if `ok' {
        if `gpu_rc' == 0 local status_txt "OK"
        else              local status_txt "GPU rc=`gpu_rc'"
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

    drop _all
}

display as text "  {hline 80}"

* =========================================================================
* Section 3: Skewed / heavy-tail distribution — chi2(3)
* =========================================================================
display as text _n "Section 3: 1D Density — Skewed (chi2(3)) Silverman bw"
display as text "{hline 88}"
display as text "  {hline 80}"
display as text "  {bf:N}       {bf:OMP}    {bf:CPU 1t}  {bf:CPU Nt}  {bf:GPU}    {bf:Status}"
display as text "  {bf:}        {bf:}      {bf:(ms)}    {bf:(ms)}    {bf:(ms)}"
display as text "  {hline 80}"

local sizes "1000 10000 100000"
foreach n of local sizes {

    clear
    set obs `n'
    gen double x = rchi2(3)

    * --- CPU single-core ---
    set processors 1
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 x, generate(f_cpu1) kernel(gaussian)
    local t1 = clock(c(current_time), "hms")
    local cpu1_ms = `t1' - `t0'
    local cpu1_rc = _rc

    * --- CPU multi-core ---
    set processors `max_cores'
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 x, generate(f_cpum) kernel(gaussian)
    local t1 = clock(c(current_time), "hms")
    local cpum_ms = `t1' - `t0'
    local cpum_rc = _rc

    * --- GPU ---
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 x, generate(f_gpu) kernel(gaussian) gpu(0)
    local t1 = clock(c(current_time), "hms")
    local gpu_ms = `t1' - `t0'
    local gpu_rc = _rc

    local ok = (`cpu1_rc' == 0 & `cpum_rc' == 0)
    local status_txt ""
    if `ok' {
        if `gpu_rc' == 0 local status_txt "OK"
        else              local status_txt "GPU rc=`gpu_rc'"
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

    drop _all
}

display as text "  {hline 80}"

* =========================================================================
* Summary
* =========================================================================
display as text _n "{hline 88}"
display as text "Notes"
display as text "{hline 88}"
display as text _n "CPU thread control:"
display as text "  - CPU 1t: set processors 1 → nproc=1 passed to C plugin"
display as text "  - CPU Nt: set processors `max_cores' → nproc=`max_cores' passed"
display as text "  - The ado layer passes nproc=c(processors) as a plugin option"
display as text "  - C plugin calls omp_set_num_threads(nproc) in stata_call()"
display as text "  - Set OMP_NUM_THREADS in the shell to override at OS level"
display as text ""
display as text "Timing:"
display as text "  - clock(c(current_time), 'hms') — 1 sec resolution"
display as text "  - Values of 0.00 mean total time < 1 clock tick"
display as text "  - All times in milliseconds (ms)"
display as text ""
display as text "GPU:"
display as text "  - GPU uses float internally — ~2x performance vs double on GPU"
display as text "  - CPU always uses double precision"
display as text "  - Without CUDA: GPU column shows rc=111 (plugin not found)"
display as text "{hline 88}"

display as text _n "Benchmark complete."
