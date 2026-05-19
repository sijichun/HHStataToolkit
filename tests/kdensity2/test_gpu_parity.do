*! test_gpu_parity.do — GPU vs CPU numerical parity tests for kdensity2
*!
*! Purpose: Verify that GPU and CPU computation paths produce
*! numerically equivalent results within floating-point tolerance.
*!
*! Tolerance rationale (float GPU):
*!   - GPU uses float internally (7 decimal digits of precision)
*!   - CPU uses double (15-16 decimal digits)
*!   - density values: max_abs_diff <= 1e-5
*!   - CV scores: max_abs_diff <= 1e-4
*!   - Float gives ~2x performance on NVIDIA GPUs
*!
*! Requires: kdensity2_cuda.plugin built via 'make kdensity2_cuda'
*! If GPU plugin is missing, the first GPU call will error and exit.

capture cd ".."

clear all
set seed 42

* Ensure kdensity2 is available
capture which kdensity2
if _rc {
    display as error "kdensity2 not found. Run 'make install' first."
    exit 111
}

display as text _n "{hline 70}"
display as text "GPU Parity Test Suite"
display as text "Comparing CPU (default) vs GPU (gpu(0)) results"
display as text "{hline 70}"

* ------------------------------------------------------------------
* Section 1: 1D Density Parity — Gaussian kernel
* ------------------------------------------------------------------
display as text _n "Section 1: 1D Density (Gaussian kernel)"
set obs 1000
gen double x1 = rnormal()

kdensity2 x1, generate(f1_cpu) kernel(gaussian)
capture kdensity2 x1, generate(f1_gpu) kernel(gaussian) gpu(0)
assert _rc == 0

gen double diff1 = abs(f1_cpu - f1_gpu)
quietly summarize diff1
local max_diff1 = r(max)
display as text "  Max |diff| (1D gaussian): " as result %12.8f `max_diff1'
assert `max_diff1' < 1e-5
drop x1 f1_cpu f1_gpu diff1

* ------------------------------------------------------------------
* Section 2: 1D Density Parity — Epanechnikov kernel
* ------------------------------------------------------------------
display as text "Section 2: 1D Density (Epanechnikov kernel)"
set obs 1000
gen double x2 = rnormal()

kdensity2 x2, generate(f2_cpu) kernel(epanechnikov)
capture kdensity2 x2, generate(f2_gpu) kernel(epanechnikov) gpu(0)
assert _rc == 0

gen double diff2 = abs(f2_cpu - f2_gpu)
quietly summarize diff2
local max_diff2 = r(max)
display as text "  Max |diff| (1D epanechnikov): " as result %12.8f `max_diff2'
assert `max_diff2' < 1e-5
drop x2 f2_cpu f2_gpu diff2

* ------------------------------------------------------------------
* Section 3: 1D Density Parity — Triweight kernel
* ------------------------------------------------------------------
display as text "Section 3: 1D Density (Triweight kernel)"
set obs 1000
gen double x3 = rnormal()

kdensity2 x3, generate(f3_cpu) kernel(triweight)
capture kdensity2 x3, generate(f3_gpu) kernel(triweight) gpu(0)
assert _rc == 0

gen double diff3 = abs(f3_cpu - f3_gpu)
quietly summarize diff3
local max_diff3 = r(max)
display as text "  Max |diff| (1D triweight): " as result %12.8f `max_diff3'
assert `max_diff3' < 1e-5
drop x3 f3_cpu f3_gpu diff3

* ------------------------------------------------------------------
* Section 4: Multivariate Density Parity
* ------------------------------------------------------------------
display as text "Section 4: Multivariate Density (Epanechnikov kernel)"
set obs 500
gen double x4a = rnormal()
gen double x4b = rnormal()

kdensity2 x4a x4b, generate(f4_cpu) kernel(epanechnikov)
capture kdensity2 x4a x4b, generate(f4_gpu) kernel(epanechnikov) gpu(0)
assert _rc == 0

gen double diff4 = abs(f4_cpu - f4_gpu)
quietly summarize diff4
local max_diff4 = r(max)
display as text "  Max |diff| (multivariate): " as result %12.8f `max_diff4'
assert `max_diff4' < 1e-5
drop x4a x4b f4_cpu f4_gpu diff4

* ------------------------------------------------------------------
* Section 5: Grouped Estimation Parity
* ------------------------------------------------------------------
display as text "Section 5: Grouped Estimation (Triweight kernel)"
set obs 1000
gen double x5 = rnormal()
gen int g5 = mod(_n, 4)

kdensity2 x5, group(g5) generate(f5_cpu) kernel(triweight)
capture kdensity2 x5, group(g5) generate(f5_gpu) kernel(triweight) gpu(0)
assert _rc == 0

gen double diff5 = abs(f5_cpu - f5_gpu)
quietly summarize diff5
local max_diff5 = r(max)
display as text "  Max |diff| (grouped): " as result %12.8f `max_diff5'
assert `max_diff5' < 1e-5
drop x5 g5 f5_cpu f5_gpu diff5

* ------------------------------------------------------------------
* Section 6: CV Bandwidth Parity
* ------------------------------------------------------------------
display as text "Section 6: CV Bandwidth (Gaussian kernel)"
set obs 500
gen double x6 = rnormal()

kdensity2 x6, generate(f6_cpu) bw(cv) kernel(gaussian)
capture kdensity2 x6, generate(f6_gpu) bw(cv) kernel(gaussian) gpu(0)
assert _rc == 0

gen double diff6 = abs(f6_cpu - f6_gpu)
quietly summarize diff6
local max_diff6 = r(max)
display as text "  Max |diff| (CV bw): " as result %12.8f `max_diff6'
assert `max_diff6' < 1e-4
drop x6 f6_cpu f6_gpu diff6

* ------------------------------------------------------------------
* Section 7: Target + Grouped Estimation Parity
* ------------------------------------------------------------------
display as text "Section 7: Target + Grouped Estimation (Gaussian kernel)"
set obs 1000
gen double x7 = rnormal()
gen byte t7 = (_n <= 800)  // 800 training (target=0), 200 test/predict (target=1)
gen int g7 = mod(_n, 4)

kdensity2 x7 if t7 == 0, target(t7) group(g7) generate(f7_cpu) kernel(gaussian)
capture kdensity2 x7 if t7 == 0, target(t7) group(g7) generate(f7_gpu) kernel(gaussian) gpu(0)
assert _rc == 0

gen double diff7 = abs(f7_cpu - f7_gpu)
quietly summarize diff7
local max_diff7 = r(max)
display as text "  Max |diff| (target+group): " as result %12.8f `max_diff7'
assert `max_diff7' < 1e-5
drop x7 t7 g7 f7_cpu f7_gpu diff7

* ------------------------------------------------------------------
* Summary
* ------------------------------------------------------------------
display as text _n "{hline 70}"
display as text "All GPU parity tests passed"
display as text "{hline 70}"
