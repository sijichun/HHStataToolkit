#!/bin/bash
# test_gpu_reproducibility.sh
# Workaround for Stata+CUDA plugin reload limitation:
# Run each GPU call in a separate Stata process.
# Each process loads the CUDA plugin fresh, so no reload issue.

set -e
cd "$(dirname "$0")/.."
N_RUNS=10
N_OBS=3000
SEED=42

echo "kdensity2 GPU Reproducibility Test (separate-process method)"
echo "Running $N_RUNS separate Stata invocations per test"
echo ""

# Generate data once
STATA_DATA_SETUP=$(cat <<'SETUP'
clear all
set seed 42
set obs 3000
gen double x = rnormal()
gen __touse = 1
save test/kdensity2/gpu_test_data.dta, replace
exit 0
SETUP
)
echo "$STATA_DATA_SETUP" | stata -bq 2>/dev/null
echo "Data generated: test/kdensity2/gpu_test_data.dta"

# --- GPU Silverman 10-run ---
echo ""
echo "=== GPU Silverman 10-run ==="
for i in $(seq 1 $N_RUNS); do
    STATA_CALL=$(cat <<CALL
clear all
use test/kdensity2/gpu_test_data.dta
capture program drop _kd2_gpu
program _kd2_gpu, plugin using("~/ado/plus/kdensity2_cuda.plugin")
plugin call _kd2_gpu, args("kernel(gaussian) bw(silverman) ndensity(1) ntarget(0) ngroup(0) gpu(0)") vars("x s$i __touse")
save test/kdensity2/gpu_silverman_run$i.dta, replace
exit 0
CALL
    )
    echo "$STATA_CALL" | stata -bq 2>/dev/null
    echo "  Run $i: done"
done

# Compare results
FIRST=1
ALL_OK=1
for i in $(seq 2 $N_RUNS); do
    stata -bq <<'CMP' 2>/dev/null
clear all
use test/kdensity2/gpu_silverman_run1.dta
merge 1:1 _n using test/kdensity2/gpu_silverman_run$i.dta
gen double d = abs(s1 - s$i)
summarize d
if r(max) >= 1e-5 {
    display as error "FAIL: run 1 vs $i: max diff = " %12.2e r(max)
    exit 1
}
else {
    display as text "  Run 1 vs $i: PASS (max diff = " %12.2e r(max) ")"
    exit 0
}
CMP
    RC=$?
    if [ $RC -ne 0 ]; then ALL_OK=0; fi
done

if [ $ALL_OK -eq 1 ]; then
    echo "  Silverman 10-run: ALL PASS"
else
    echo "  Silverman 10-run: SOME FAILED"
fi

# Cleanup
rm -f test/kdensity2/gpu_silverman_run*.dta

# --- GPU CV 10-run ---
echo ""
echo "=== GPU CV 10-run ==="
for i in $(seq 1 $N_RUNS); do
    STATA_CALL=$(cat <<CALL
clear all
use test/kdensity2/gpu_test_data.dta
set seed 123
capture program drop _kd2_gpu
program _kd2_gpu, plugin using("~/ado/plus/kdensity2_cuda.plugin")
plugin call _kd2_gpu, args("kernel(gaussian) bw(cv) ndensity(1) ntarget(0) ngroup(0) gpu(0)") vars("x c$i __touse")
save test/kdensity2/gpu_cv_run$i.dta, replace
exit 0
CALL
    )
    echo "$STATA_CALL" | stata -bq 2>/dev/null
    echo "  CV Run $i: done"
done

# Compare CV results
for i in $(seq 2 $N_RUNS); do
    stata -bq <<'CMP' 2>/dev/null
clear all
use test/kdensity2/gpu_cv_run1.dta
merge 1:1 _n using test/kdensity2/gpu_cv_run$i.dta
gen double d = abs(c1 - c$i)
summarize d
if r(max) >= 1e-5 {
    display as error "FAIL: CV run 1 vs $i: max diff = " %12.2e r(max)
    exit 1
}
else {
    display as text "  CV Run 1 vs $i: PASS"
}
CMP
    RC=$?
    if [ $RC -ne 0 ]; then ALL_OK=0; fi
done

if [ $ALL_OK -eq 1 ]; then
    echo "  CV 10-run: ALL PASS"
else
    echo "  CV 10-run: SOME FAILED"
fi

# Cleanup
rm -f test/kdensity2/gpu_cv_run*.dta
rm -f test/kdensity2/gpu_test_data.dta

echo ""
echo "All GPU tests complete."
