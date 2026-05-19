*! test_gpu_errors.do
*! Tests GPU error handling for kdensity2
*! Verifies proper error messages for invalid GPU usage
*! Version 1.0.0  10may2026

capture cd ".."

local cuda_plugin "kdensity2/kdensity2_cuda.plugin"
local cuda_backup "/tmp/kdensity2_cuda_plugin_backup"

* Restore CUDA plugin from any previous interrupted run
capture confirm file "`cuda_backup'"
if _rc == 0 {
    capture shell mv "`cuda_backup'" "`cuda_plugin'"
}

capture confirm file "`cuda_plugin'"
local has_cuda = (_rc == 0)

display as text _n "{hline 60}"
display as text "kdensity2 GPU Error Handling Tests"
display as text "{hline 60}"
display as text "CUDA plugin present: `has_cuda'"

* =====================================================
* Test 1: gpu(-1) is CPU mode (valid), gpu(-2) errors
* gpu(-1) is the default meaning CPU computation.
* Explicit negative values below -1 must produce error.
* =====================================================
display as text _n "Test 1a: gpu(-1) CPU mode (valid)"
display as text "{hline 40}"

clear all
set obs 10
gen double x = rnormal()
capture kdensity2 x, generate(f) gpu(-1)
assert _rc == 0
display as text "  PASS: gpu(-1) returned rc=0"
drop _all

display as text _n "Test 1b: gpu(-2) must error"
display as text "{hline 40}"

clear all
set obs 10
gen double x = rnormal()
capture kdensity2 x, generate(f) gpu(-2)
assert _rc == 198
display as text "  PASS: gpu(-2) returned rc=198"
drop _all

* =====================================================
* Test 2: Missing CUDA binary produces clear error
* Temporarily hide the CUDA plugin, then request GPU
* computation. Expect exit code 111 with message
* "kdensity2_cuda.plugin not found".
* =====================================================
display as text _n "Test 2: Missing CUDA binary"
display as text "{hline 40}"

if `has_cuda' {
    shell mv "`cuda_plugin'" "`cuda_backup'"
}

clear all
set obs 10
gen double x = rnormal()
capture kdensity2 x, generate(f) gpu(0)
local rc2 = _rc

* Restore CUDA plugin immediately
if `has_cuda' {
    capture confirm file "`cuda_backup'"
    if _rc == 0 {
        shell mv "`cuda_backup'" "`cuda_plugin'"
    }
}

if `has_cuda' {
    assert `rc2' == 111
}
else {
    assert `rc2' != 0
}
display as text "  PASS: gpu(0) returned rc=`rc2'"
drop _all

* =====================================================
* Test 3: Invalid GPU device number
* Device 999 does not exist on any system. The CUDA
* plugin should return non-zero (plugin-level error or
* CUDA runtime error). If no CUDA plugin, the ado
* still catches it (rc != 0).
* =====================================================
display as text _n "Test 3: Invalid GPU device (999)"
display as text "{hline 40}"

clear all
set obs 10
gen double x = rnormal()
capture kdensity2 x, generate(f) gpu(999)
local rc3 = _rc
assert `rc3' != 0
display as text "  PASS: gpu(999) returned rc=`rc3'"
drop _all

* =====================================================
display as text _n "{hline 60}"
display as text "All GPU error handling tests passed"
display as text "{hline 60}"

* Clean up any temporary files
capture erase "kdensity2_test_bygroup.png"
capture erase "kdensity2_test_overlay.png"
