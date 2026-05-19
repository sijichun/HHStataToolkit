/**
 * test_ols_cuda.c - Benchmark and correctness test for ols_cuda vs ols.c
 *
 * Compile:
 *   nvcc -O3 -Isrc test/test_ols_cuda.c src/ols.c src/ols_cuda.c -o test_ols_cuda \
 *        -lcudart -lcublas -lcusolver -lm
 *
 * Run:
 *   ./test_ols_cuda
 */

#include "ols.h"
#include "ols_cuda.h"

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <cuda_runtime.h>

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

int main(int argc, char **argv)
{
    (void)argc; (void)argv;

    int n = 50000;
    int p = 5;
    int constant = 1;
    int seed = 42;

    printf("=== OLS CUDA Benchmark ===\n");
    printf("n=%d, p=%d, constant=%d\n\n", n, p, constant);

    srand(seed);

    /* Generate synthetic data */
    double *X = (double*)malloc((size_t)n * p * sizeof(double));
    double *y = (double*)malloc((size_t)n * sizeof(double));
    double *beta_true = (double*)malloc((size_t)p * sizeof(double));

    for (int j = 0; j < p; j++) beta_true[j] = (j + 1) * 0.5;
    double const_true = 1.0;

    for (int i = 0; i < n; i++) {
        double val = const_true;
        for (int j = 0; j < p; j++) {
            X[j * n + i] = rand_normal();
            val += beta_true[j] * X[j * n + i];
        }
        y[i] = val + 0.5 * rand_normal();
    }

    /* -------------------- CPU OLS (ols.c) -------------------- */
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    ols_result_t *res_cpu = ols_fit(X, y, n, p, constant);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double t_cpu = elapsed_ms(&t0, &t1);

    if (!res_cpu || !res_cpu->converged) {
        printf("CPU OLS failed!\n");
        return 1;
    }

    printf("CPU OLS time: %.3f ms\n", t_cpu);
    printf("CPU constant: %.6f\n", res_cpu->constant);
    for (int j = 0; j < p; j++)
        printf("CPU beta[%d]: %.6f\n", j, res_cpu->beta[j]);

    /* -------------------- GPU OLS (ols_cuda.c) -------------------- */
    /* Convert to float and copy to device */
    float *d_X = NULL, *d_y = NULL;
    float *d_beta = NULL, *d_const = NULL;
    cudaMalloc(&d_X, (size_t)n * p * sizeof(float));
    cudaMalloc(&d_y, (size_t)n * sizeof(float));
    cudaMalloc(&d_beta, (size_t)p * sizeof(float));
    cudaMalloc(&d_const, sizeof(float));

    float *h_Xf = (float*)malloc((size_t)n * p * sizeof(float));
    float *h_yf = (float*)malloc((size_t)n * sizeof(float));
    for (int i = 0; i < n * p; i++) h_Xf[i] = (float)X[i];
    for (int i = 0; i < n; i++) h_yf[i] = (float)y[i];

    cudaMemcpy(d_X, h_Xf, (size_t)n * p * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_y, h_yf, (size_t)n * sizeof(float), cudaMemcpyHostToDevice);

    cudaDeviceSynchronize();
    clock_gettime(CLOCK_MONOTONIC, &t0);
    int ret = ols_cuda_fit(d_X, d_y, n, p, constant, d_beta, d_const);
    cudaDeviceSynchronize();
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double t_gpu = elapsed_ms(&t0, &t1);

    if (ret != 0) {
        printf("GPU OLS failed! ret=%d\n", ret);
        return 1;
    }

    float *h_beta = (float*)malloc((size_t)p * sizeof(float));
    float h_const;
    cudaMemcpy(h_beta, d_beta, p * sizeof(float), cudaMemcpyDeviceToHost);
    cudaMemcpy(&h_const, d_const, sizeof(float), cudaMemcpyDeviceToHost);

    printf("\nGPU OLS time: %.3f ms\n", t_gpu);
    printf("GPU constant: %.6f\n", h_const);
    for (int j = 0; j < p; j++)
        printf("GPU beta[%d]: %.6f\n", j, h_beta[j]);

    /* -------------------- Comparison -------------------- */
    printf("\n=== Comparison ===\n");
    double diff_const = fabs(res_cpu->constant - h_const);
    printf("Constant diff: %.6e\n", diff_const);

    double max_diff = diff_const;
    for (int j = 0; j < p; j++) {
        double diff = fabs(res_cpu->beta[j] - h_beta[j]);
        printf("Beta[%d] diff: %.6e\n", j, diff);
        if (diff > max_diff) max_diff = diff;
    }

    printf("\nMax abs diff (CPU vs GPU): %.6e\n", max_diff);
    printf("Speedup (CPU vs GPU): %.2fx\n", t_cpu / t_gpu);

    if (max_diff > 1e-3) {
        printf("FAIL: Difference too large!\n");
        return 1;
    }

    /* -------------------- Prediction test -------------------- */
    printf("\n=== Prediction test ===\n");
    double *pred_cpu = (double*)malloc((size_t)n * sizeof(double));
    ols_predict(X, n, p, res_cpu, pred_cpu);

    float *d_pred = NULL;
    cudaMalloc(&d_pred, (size_t)n * sizeof(float));
    ols_cuda_predict(d_X, n, p, h_const, d_beta, d_pred);

    float *h_pred = (float*)malloc((size_t)n * sizeof(float));
    cudaMemcpy(h_pred, d_pred, n * sizeof(float), cudaMemcpyDeviceToHost);

    max_diff = 0.0;
    for (int i = 0; i < n; i++) {
        double diff = fabs(pred_cpu[i] - h_pred[i]);
        if (diff > max_diff) max_diff = diff;
    }
    printf("Max pred diff: %.6e\n", max_diff);

    if (max_diff > 1e-3) {
        printf("FAIL: Prediction difference too large!\n");
        return 1;
    }

    printf("\n=== All tests passed! ===\n");

    /* Cleanup */
    free(X); free(y); free(beta_true);
    free(h_Xf); free(h_yf); free(h_beta); free(pred_cpu); free(h_pred);
    cudaFree(d_X); cudaFree(d_y); cudaFree(d_beta); cudaFree(d_const); cudaFree(d_pred);
    ols_result_free(res_cpu);

    return 0;
}
