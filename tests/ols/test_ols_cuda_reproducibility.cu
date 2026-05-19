/**
 * test_ols_cuda_reproducibility.cu
 * Comprehensive reproducibility and performance test for OLS CPU vs CUDA.
 *
 * Tests:
 *   1. CPU OLS 10-run reproducibility (same seed → same results)
 *   2. GPU OLS 10-run reproducibility (same seed → same results)
 *   3. CPU vs GPU result comparison (betas, predictions)
 *   4. CPU vs GPU runtime comparison
 *
 * Compile:
 *   nvcc -O3 -Isrc test/ols/test_ols_cuda_reproducibility.cu \
 *        src/ols.c src/ols_cuda.cu -o test/ols/test_ols_cuda_reproducibility \
 *        -lcudart -lcublas -lcusolver -lm
 *
 * Run:
 *   ./test/ols/test_ols_cuda_reproducibility
 */

#include "ols.h"
#include "ols_cuda.h"

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <string.h>
#include <cuda_runtime.h>
#include <cublas_v2.h>

static double rand_normal()
{
    double u1 = (double)rand() / RAND_MAX;
    double u2 = (double)rand() / RAND_MAX;
    return sqrt(-2.0 * log(u1 + 1e-10)) * cos(2.0 * M_PI * u2);
}

static double elapsed_ms(struct timespec *start, struct timespec *end)
{
    return (end->tv_sec - start->tv_sec) * 1000.0 +
           (end->tv_nsec - start->tv_nsec) / 1e6;
}

static int approx_eq(double a, double b, double tol)
{
    return fabs(a - b) <= tol;
}

#define N_RUNS 10
#define TOL_CPU 1e-12
#define TOL_GPU_FLOAT 1e-5

int main(void)
{
    int n = 50000;
    int p = 5;
    int constant = 1;
    int seed = 42;

    printf("========================================\n");
    printf("OLS CUDA Comprehensive Reproducibility Test\n");
    printf("========================================\n");
    printf("n=%d, p=%d, constant=%d, seed=%d\n\n", n, p, constant, seed);

    /* Generate synthetic data once */
    srand(seed);
    double *X = (double*)malloc((size_t)n * p * sizeof(double));
    double *y = (double*)malloc((size_t)n * sizeof(double));
    for (int i = 0; i < n; i++) {
        double val = constant ? 1.0 : 0.0;
        for (int j = 0; j < p; j++) {
            X[j * n + i] = rand_normal();
            val += (j + 1) * 0.5 * X[j * n + i];
        }
        y[i] = val + 0.5 * rand_normal();
    }

    /* ================================================================ */
    /* Test 1: CPU OLS 10-run reproducibility                           */
    /* ================================================================ */
    printf("--- Test 1: CPU OLS 10-run reproducibility ---\n");

    double cpu_const[N_RUNS];
    double cpu_beta[N_RUNS][5];
    double cpu_time[N_RUNS];

    int all_cpu_equal = 1;
    for (int r = 0; r < N_RUNS; r++) {
        struct timespec t0, t1;
        clock_gettime(CLOCK_MONOTONIC, &t0);

        /* Re-seed with same seed each time for determinism */
        srand(seed);
        /* Re-generate data identically each run */
        for (int i = 0; i < n; i++) {
            double val = constant ? 1.0 : 0.0;
            for (int j = 0; j < p; j++) {
                X[j * n + i] = rand_normal();
                val += (j + 1) * 0.5 * X[j * n + i];
            }
            y[i] = val + 0.5 * rand_normal();
        }

        ols_result_t *res = ols_fit(X, y, n, p, constant);
        clock_gettime(CLOCK_MONOTONIC, &t1);
        cpu_time[r] = elapsed_ms(&t0, &t1);

        if (!res || !res->converged) {
            printf("  Run %d: CPU OLS FAILED\n", r + 1);
            all_cpu_equal = 0;
            cpu_const[r] = -1;
            for (int j = 0; j < p; j++) cpu_beta[r][j] = -1;
            if (res) ols_result_free(res);
            continue;
        }

        cpu_const[r] = res->constant;
        for (int j = 0; j < p; j++) cpu_beta[r][j] = res->beta[j];
        ols_result_free(res);

        /* Compare with first run */
        if (r > 0) {
            if (!approx_eq(cpu_const[r], cpu_const[0], TOL_CPU))
                all_cpu_equal = 0;
            for (int j = 0; j < p; j++) {
                if (!approx_eq(cpu_beta[r][j], cpu_beta[0][j], TOL_CPU))
                    all_cpu_equal = 0;
            }
        }
    }

    printf("  CPU constant (run 1): %.10f\n", cpu_const[0]);
    for (int j = 0; j < p; j++)
        printf("  CPU beta[%d] (run 1): %.10f\n", j, cpu_beta[0][j]);
    printf("  All %d runs identical: %s\n\n", N_RUNS,
           all_cpu_equal ? "PASS" : "FAIL");

    /* ================================================================ */
    /* Test 2: GPU OLS 10-run reproducibility                           */
    /* ================================================================ */
    printf("--- Test 2: GPU OLS 10-run reproducibility ---\n");

    float gpu_const[N_RUNS];
    float gpu_beta[N_RUNS][5];
    double gpu_time[N_RUNS];

    int all_gpu_equal = 1;
    for (int r = 0; r < N_RUNS; r++) {
        /* Re-generate data identically */
        srand(seed);
        float *h_Xf = (float*)malloc((size_t)n * p * sizeof(float));
        float *h_yf = (float*)malloc((size_t)n * sizeof(float));
        for (int i = 0; i < n; i++) {
            double val = constant ? 1.0 : 0.0;
            for (int j = 0; j < p; j++) {
                X[j * n + i] = rand_normal();
                val += (j + 1) * 0.5 * X[j * n + i];
            }
            y[i] = val + 0.5 * rand_normal();
        }
        for (int i = 0; i < n * p; i++) h_Xf[i] = (float)X[i];
        for (int i = 0; i < n; i++) h_yf[i] = (float)y[i];

        float *d_X = NULL, *d_y = NULL;
        float *d_beta = NULL, *d_const = NULL;
        cudaMalloc(&d_X, (size_t)n * p * sizeof(float));
        cudaMalloc(&d_y, (size_t)n * sizeof(float));
        cudaMalloc(&d_beta, (size_t)p * sizeof(float));
        cudaMalloc(&d_const, sizeof(float));

        cudaMemcpy(d_X, h_Xf, (size_t)n * p * sizeof(float), cudaMemcpyHostToDevice);
        cudaMemcpy(d_y, h_yf, (size_t)n * sizeof(float), cudaMemcpyHostToDevice);

        struct timespec t0, t1;
        cudaDeviceSynchronize();
        clock_gettime(CLOCK_MONOTONIC, &t0);
        int ret = ols_cuda_fit(d_X, d_y, n, p, constant, d_beta, d_const);
        cudaDeviceSynchronize();
        clock_gettime(CLOCK_MONOTONIC, &t1);
        gpu_time[r] = elapsed_ms(&t0, &t1);

        free(h_Xf); free(h_yf);

        if (ret != 0) {
            printf("  Run %d: GPU OLS FAILED (ret=%d)\n", r + 1, ret);
            all_gpu_equal = 0;
            gpu_const[r] = -1;
            for (int j = 0; j < p; j++) gpu_beta[r][j] = -1;
            cudaFree(d_X); cudaFree(d_y); cudaFree(d_beta); cudaFree(d_const);
            continue;
        }

        cudaMemcpy(&gpu_const[r], d_const, sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(gpu_beta[r], d_beta, (size_t)p * sizeof(float), cudaMemcpyDeviceToHost);
        cudaFree(d_X); cudaFree(d_y); cudaFree(d_beta); cudaFree(d_const);

        if (r > 0) {
            if (!approx_eq((double)gpu_const[r], (double)gpu_const[0], TOL_GPU_FLOAT))
                all_gpu_equal = 0;
            for (int j = 0; j < p; j++) {
                if (!approx_eq((double)gpu_beta[r][j], (double)gpu_beta[0][j], TOL_GPU_FLOAT))
                    all_gpu_equal = 0;
            }
        }
    }

    printf("  GPU constant (run 1): %.10f\n", (double)gpu_const[0]);
    for (int j = 0; j < p; j++)
        printf("  GPU beta[%d] (run 1): %.10f\n", j, (double)gpu_beta[0][j]);
    printf("  All %d runs identical: %s\n\n", N_RUNS,
           all_gpu_equal ? "PASS" : "FAIL");

    /* ================================================================ */
    /* Test 3: CPU vs GPU comparison                                    */
    /* ================================================================ */
    printf("--- Test 3: CPU vs GPU result comparison ---\n");

    double diff_const = fabs(cpu_const[0] - (double)gpu_const[0]);
    printf("  Constant diff: %.6e\n", diff_const);

    double max_beta_diff = diff_const;
    for (int j = 0; j < p; j++) {
        double diff = fabs(cpu_beta[0][j] - (double)gpu_beta[0][j]);
        printf("  Beta[%d] diff: %.6e\n", j, diff);
        if (diff > max_beta_diff) max_beta_diff = diff;
    }
    printf("  Max beta diff: %.6e\n", max_beta_diff);
    int beta_pass = (max_beta_diff < 1e-4);
    printf("  Beta comparison: %s (tol=1e-4)\n\n", beta_pass ? "PASS" : "FAIL");

    /* ================================================================ */
    /* Test 4: Prediction comparison (full vector)                      */
    /* ================================================================ */
    printf("--- Test 4: Prediction comparison ---\n");

    /* CPU prediction */
    ols_result_t *res_cpu = ols_fit(X, y, n, p, constant);
    double *pred_cpu = (double*)malloc((size_t)n * sizeof(double));
    ols_predict(X, n, p, res_cpu, pred_cpu);

    /* GPU prediction */
    float *h_Xf = (float*)malloc((size_t)n * p * sizeof(float));
    float *h_yf = (float*)malloc((size_t)n * sizeof(float));
    for (int i = 0; i < n * p; i++) h_Xf[i] = (float)X[i];
    for (int i = 0; i < n; i++) h_yf[i] = (float)y[i];

    float *d_X = NULL, *d_y = NULL;
    float *d_beta = NULL, *d_const = NULL;
    cudaMalloc(&d_X, (size_t)n * p * sizeof(float));
    cudaMalloc(&d_y, (size_t)n * sizeof(float));
    cudaMalloc(&d_beta, (size_t)p * sizeof(float));
    cudaMalloc(&d_const, sizeof(float));
    cudaMemcpy(d_X, h_Xf, (size_t)n * p * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_y, h_yf, (size_t)n * sizeof(float), cudaMemcpyHostToDevice);

    ols_cuda_fit(d_X, d_y, n, p, constant, d_beta, d_const);

    float *d_pred = NULL;
    cudaMalloc(&d_pred, (size_t)n * sizeof(float));
    ols_cuda_predict(d_X, n, p, constant, d_beta, d_pred);

    float *h_pred = (float*)malloc((size_t)n * sizeof(float));
    cudaMemcpy(h_pred, d_pred, (size_t)n * sizeof(float), cudaMemcpyDeviceToHost);

    double max_pred_diff = 0.0;
    for (int i = 0; i < n; i++) {
        double diff = fabs(pred_cpu[i] - (double)h_pred[i]);
        if (diff > max_pred_diff) max_pred_diff = diff;
    }
    printf("  Max prediction diff: %.6e\n", max_pred_diff);
    /* GPU uses float internally while CPU uses double + different solver (SVD vs QR).
     * Float QR can accumulate larger errors for predictions than for coefficients.
     * A tolerance of 5e-3 accounts for float precision amplification in prediction
     * differences across the full data vector. */
    int pred_pass = (max_pred_diff < 5e-3);
    printf("  Prediction comparison: %s (tol=5e-3)\n\n", pred_pass ? "PASS" : "FAIL");

    free(pred_cpu); free(h_pred);
    cudaFree(d_pred); cudaFree(d_X); cudaFree(d_y); cudaFree(d_beta); cudaFree(d_const);
    free(h_Xf); free(h_yf);
    ols_result_free(res_cpu);

    /* ================================================================ */
    /* Test 5: Runtime comparison                                       */
    /* ================================================================ */
    printf("--- Test 5: Runtime comparison ---\n");

    double cpu_avg = 0, cpu_min = cpu_time[0], cpu_max = cpu_time[0];
    double gpu_avg = 0, gpu_min = gpu_time[0], gpu_max = gpu_time[0];
    for (int r = 0; r < N_RUNS; r++) {
        cpu_avg += cpu_time[r];
        gpu_avg += gpu_time[r];
        if (cpu_time[r] < cpu_min) cpu_min = cpu_time[r];
        if (cpu_time[r] > cpu_max) cpu_max = cpu_time[r];
        if (gpu_time[r] < gpu_min) gpu_min = gpu_time[r];
        if (gpu_time[r] > gpu_max) gpu_max = gpu_time[r];
    }
    cpu_avg /= N_RUNS;
    gpu_avg /= N_RUNS;

    printf("  CPU  (n=%d, p=%d): avg=%.3f ms  min=%.3f ms  max=%.3f ms\n",
           n, p, cpu_avg, cpu_min, cpu_max);
    printf("  GPU  (n=%d, p=%d): avg=%.3f ms  min=%.3f ms  max=%.3f ms\n",
           n, p, gpu_avg, gpu_min, gpu_max);
    printf("  Speedup (CPU/GPU): %.2fx\n\n", cpu_avg / gpu_avg);

    /* ================================================================ */
    /* Summary                                                          */
    /* ================================================================ */
    int all_pass = all_cpu_equal && all_gpu_equal && beta_pass && pred_pass;
    printf("========================================\n");
    printf("Summary:\n");
    printf("  CPU 10-run reproducibility: %s\n", all_cpu_equal ? "PASS" : "FAIL");
    printf("  GPU 10-run reproducibility: %s\n", all_gpu_equal ? "PASS" : "FAIL");
    printf("  CPU vs GPU betas:          %s\n", beta_pass ? "PASS" : "FAIL");
    printf("  CPU vs GPU predictions:    %s\n", pred_pass ? "PASS" : "FAIL");
    printf("========================================\n");
    printf("%s\n\n", all_pass ? "ALL TESTS PASSED" : "SOME TESTS FAILED");

    free(X); free(y);
    return all_pass ? 0 : 1;
}
