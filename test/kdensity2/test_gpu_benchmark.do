*! test_gpu_benchmark.do — Performance benchmark for kdensity2 GPU vs CPU
*!
*! Compares computation time for CPU and GPU paths at various dataset sizes.
*! If GPU is unavailable, GPU columns show error codes.
*!
*! Note: GPU uses float internally for ~2x performance over double.
*! CPU always uses double precision.
*!
*! Methodology:
*!   - Each timing is computed as wall-clock time using clock(c(current_time), "hms")
*!   - For small datasets where single calls are sub-second, multiple iterations
*!     are run and averaged to get stable measurements
*!   - All runs use the same random seed for reproducibility
*!   - GPU calls are wrapped in capture; GPU failures do not abort the benchmark
*!
*! Requires: kdensity2 installed, kdensity2_cuda.plugin for GPU tests

capture cd ".."

clear all
set seed 42

display as text _n "{hline 80}"
display as text "kdensity2 GPU Performance Benchmark"
display as text "Date: $S_DATE  Time: $S_TIME"
display as text "{hline 80}"

* =========================================================================
* Section 1: Silverman bandwidth — 1D density at multiple dataset sizes
* =========================================================================
display as text _n "Section 1: 1D Density (Gaussian kernel, Silverman bandwidth)"
display as text "{hline 80}"
display as text "  {hline 72}"
display as text "  {bf:N}       {bf:Reps}  {bf:CPU (s)}  {bf:GPU (s)}  {bf:Speedup}  {bf:GPU Status}"
display as text "  {hline 72}"

local sizes_silverman "1000 10  10000 5  100000 3  500000 1  1000000 1"
local n_items: word count `sizes_silverman'
forvalues i = 1(2)`n_items' {
    local n   : word `i' of `sizes_silverman'
    local loc = `i' + 1
    local reps : word `loc' of `sizes_silverman'

    clear
    set obs `n'
    gen double x = rnormal()

    * CPU timing
    local t0 = clock(c(current_time), "hms")
    forvalues r = 1/`reps' {
        capture kdensity2 x, generate(f_cpu) kernel(gaussian)
    }
    local t1 = clock(c(current_time), "hms")
    local cpu_t = (`t1' - `t0') / 1000 / `reps'
    local cpu_rc = _rc

    * GPU timing
    local t0 = clock(c(current_time), "hms")
    forvalues r = 1/`reps' {
        capture kdensity2 x, generate(f_gpu) kernel(gaussian) gpu(0)
    }
    local t1 = clock(c(current_time), "hms")
    local gpu_t = (`t1' - `t0') / 1000 / `reps'
    local gpu_rc = _rc

    if `cpu_rc' == 0 & `gpu_rc' == 0 {
        local speedup = `cpu_t' / `gpu_t'
        local status "OK"
        display as text "  %8s" "`n'" "   %3s" "`reps'"  ///
            _col(21) as result %9.4f `cpu_t' ///
            _col(31) %9.4f `gpu_t' ///
            _col(41) %9.2f `speedup' ///
            _col(52) as text "`status'"
    }
    else {
        if `cpu_rc' != 0 {
            local status "CPU rc=`cpu_rc'"
        }
        else {
            local status "GPU rc=`gpu_rc'"
        }
        display as text "  %8s" "`n'" "   %3s" "`reps'"  ///
            _col(21) as result %9.4f `cpu_t' ///
            _col(31) as text "     N/A" ///
            _col(41) as text "    N/A" ///
            _col(52) as text "`status'"
    }

    drop _all
}
display as text "  {hline 72}"

* =========================================================================
* Section 2: CV bandwidth — 1D density (CV is O(N^2), smaller sizes)
* =========================================================================
display as text _n "Section 2: 1D Density with CV Bandwidth"
display as text "{hline 80}"
display as text "  {hline 72}"
display as text "  {bf:N}       {bf:Reps}  {bf:CPU (s)}  {bf:GPU (s)}  {bf:Speedup}  {bf:GPU Status}"
display as text "  {hline 72}"

local sizes_cv "1000 1  5000 1  10000 1  20000 1"
local n_items: word count `sizes_cv'
forvalues i = 1(2)`n_items' {
    local n   : word `i' of `sizes_cv'
    local loc = `i' + 1
    local reps : word `loc' of `sizes_cv'

    clear
    set obs `n'
    gen double x = rnormal()

    * CPU timing
    local t0 = clock(c(current_time), "hms")
    forvalues r = 1/`reps' {
        capture kdensity2 x, generate(f_cpu) kernel(gaussian) bw(cv)
    }
    local t1 = clock(c(current_time), "hms")
    local cpu_t = (`t1' - `t0') / 1000 / `reps'
    local cpu_rc = _rc

    * GPU timing
    local t0 = clock(c(current_time), "hms")
    forvalues r = 1/`reps' {
        capture kdensity2 x, generate(f_gpu) kernel(gaussian) bw(cv) gpu(0)
    }
    local t1 = clock(c(current_time), "hms")
    local gpu_t = (`t1' - `t0') / 1000 / `reps'
    local gpu_rc = _rc

    if `cpu_rc' == 0 & `gpu_rc' == 0 {
        local speedup = `cpu_t' / `gpu_t'
        local status "OK"
        display as text "  %8s" "`n'" "   %3s" "`reps'"  ///
            _col(21) as result %9.4f `cpu_t' ///
            _col(31) %9.4f `gpu_t' ///
            _col(41) %9.2f `speedup' ///
            _col(52) as text "`status'"
    }
    else {
        if `cpu_rc' != 0 {
            local status "CPU rc=`cpu_rc'"
        }
        else {
            local status "GPU rc=`gpu_rc'"
        }
        display as text "  %8s" "`n'" "   %3s" "`reps'"  ///
            _col(21) as result %9.4f `cpu_t' ///
            _col(31) as text "     N/A" ///
            _col(41) as text "    N/A" ///
            _col(52) as text "`status'"
    }

    drop _all
}
display as text "  {hline 72}"

* =========================================================================
* Summary notes
* =========================================================================
display as text _n "{hline 80}"
display as text "Notes"
display as text "{hline 80}"
display as text _n "GPU performance characteristics:"
display as text "  - GPU overhead (device init + memory transfer) dominates at small N"
display as text "  - GPU benefits typically appear at N > 10,000 for Silverman bandwidth"
display as text "  - CV bandwidth is O(N^2 x grid_size) — GPU can show benefits at smaller N"
display as text "  - GPU uses float internally — ~2x performance vs double on GPU"
display as text "  - CPU always uses double precision (15-16 significant digits)"
display as text "  - On systems without CUDA, GPU tests will show rc=111 (plugin not found)"
display as text _n "Recommendations:"
display as text "  - Use GPU for large datasets (N > 10,000) or repeated estimation"
display as text "  - Use CPU for small datasets or single-shot estimation"
display as text "  - CV bandwidth on GPU is beneficial at N > 5,000"
display as text "{hline 80}"

display as text _n "Benchmark complete."
