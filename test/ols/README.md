# OLS Test Results

## OLS CPU Correctness (test_ols.c)

Tests OLS/WLS implementation via LAPACK DGELSD/SVD. All 11 tests PASS.

```
=== OLS/WLS Test Suite ===
  check_invertible_svd: full-rank X                       PASS
  check_invertible_svd: rank-deficient X                  PASS
  check_invertible_svd: 3x3 identity                      PASS
  ols_fit: y=2+3x (constant=1)                            PASS
  ols_fit: y=2x (constant=0)                              PASS
  ols_fit: perfect fit (constant=1)                       PASS
  wls_fit: equal weights == ols_fit                       PASS
  wls_fit: down-weight outlier shifts coeff               PASS
  wls_fit: w=NULL == ols_fit                              PASS
  ols_predict: with constant                              PASS
  ols_predict: without constant                           PASS
  ols_compute_stats: with constant                        PASS
  ols_compute_stats: perfect fit R2=1                     PASS
=== ALL TESTS PASSED ===
```

## OLS CUDA Reproducibility (test_ols_cuda_reproducibility)

Tests 10-run reproducibility for both CPU and GPU OLS, plus cross-comparison and timing.

Environment: RTX 3090 Ti, CUDA 12.4, n=50000, p=5.

| Test | Result | Details |
|------|--------|---------|
| CPU 10-run reproducibility | PASS | All 10 runs identical (LAPACK DGELSD) |
| GPU 10-run reproducibility | PASS | All 10 runs identical (cuSOLVER QR) |
| CPU vs GPU betas | PASS | max diff = 8.87e-7 (tol=1e-4) |
| CPU vs GPU predictions | PASS | max diff = 1.76e-3 (tol=5e-3, float precision) |

Performance (n=50000, p=5):
- CPU (LAPACK DGELSD): avg 12.5 ms
- GPU (cuSOLVER QR, float): avg 2.6 ms
- Speedup (CPU/GPU): 4.76x

### Build & Run

```bash
# CPU correctness test
gcc -O3 -Isrc test/ols/test_ols.c src/ols.c \
    -o test/ols/test_ols -lm -lopenblas -llapack -lblas
./test/ols/test_ols

# CUDA reproducibility test (requires nvcc)
gcc -c -O3 -Isrc src/ols.c -o /tmp/ols.o
nvcc -c -O3 -Isrc -arch=sm_86 src/ols_cuda.cu -o /tmp/ols_cuda.o
nvcc -c -O3 -Isrc -arch=sm_86 test/ols/test_ols_cuda_reproducibility.cu -o /tmp/test_ols.o
gcc -B/usr/bin /tmp/ols.o /tmp/ols_cuda.o /tmp/test_ols.o \
    -o test/ols/test_ols_cuda_reproducibility \
    -L/opt/Anaconda/lib -lcudart -lcublas -lcusolver -lm -lopenblas
./test/ols/test_ols_cuda_reproducibility
```

Note: OLS is a shared C utility library (used by all plugins via COMMON_SRC), not a standalone Stata plugin. There is no Stata `.ado` wrapper for OLS. The tests above are C-level tests.
