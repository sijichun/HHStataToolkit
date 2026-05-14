/**
 * nwreg_cuda.cu - GPU dispatch functions for nwreg (Nadaraya-Watson regression)
 *
 * Implements CUDA kernels and host dispatch functions for:
 *   - 1D NW regression evaluation
 *   - Multivariate (product kernel) NW regression evaluation
 *   - 1D K-fold CV negative MSE score
 *   - Multivariate K-fold CV negative MSE score
 *   - GPU preflight check
 *
 * All host functions use extern "C" linkage for Stata ABI compatibility.
 * All GPU computation uses single-precision float internally.
 */

#include "nwreg_cuda.h"

#include <cuda_runtime.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NW_DENOM_TOL_F 1e-3f

#define _KERNEL_GAUSSIAN     0
#define _KERNEL_EPANECHNIKOV 1
#define _KERNEL_UNIFORM      2
#define _KERNEL_TRIWEIGHT    3
#define _KERNEL_COSINE       4

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define M_PI_F 3.14159265358979f

__device__ static float dev_kernel_1d(float u, int kernel_type)
{
    switch (kernel_type) {
    case _KERNEL_GAUSSIAN:
        return (1.0f / sqrtf(2.0f * M_PI_F)) * expf(-0.5f * u * u);
    case _KERNEL_EPANECHNIKOV:
        if (u < -1.0f || u > 1.0f) return 0.0f;
        return 0.75f * (1.0f - u * u);
    case _KERNEL_UNIFORM:
        if (u < -1.0f || u > 1.0f) return 0.0f;
        return 0.5f;
    case _KERNEL_TRIWEIGHT:
        if (u < -1.0f || u > 1.0f) return 0.0f;
        {
            float t = 1.0f - u * u;
            return (35.0f / 32.0f) * t * t * t;
        }
    case _KERNEL_COSINE:
        if (u < -1.0f || u > 1.0f) return 0.0f;
        return (M_PI_F / 4.0f) * cosf((M_PI_F / 2.0f) * u);
    default:
        return (1.0f / sqrtf(2.0f * M_PI_F)) * expf(-0.5f * u * u);
    }
}

__device__ static float dev_kernel_product(const float *u, int dim, int kernel_type)
{
    float prod = 1.0f;
    for (int d = 0; d < dim; d++) {
        prod *= dev_kernel_1d(u[d], kernel_type);
        if (prod == 0.0f) return 0.0f;
    }
    return prod;
}

__global__ void nw_eval_1d_kernel(const float *x,
                                   const float *train_x,
                                   const float *train_y,
                                   int n_train, int n_eval,
                                   float h, int kernel_type,
                                   float *result)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n_eval) return;

    float xi = x[i];
    float num = 0.0f, den = 0.0f;
    for (int j = 0; j < n_train; j++) {
        float u = (xi - train_x[j]) / h;
        float w = dev_kernel_1d(u, kernel_type);
        num += w * train_y[j];
        den += w;
    }
    result[i] = (den < NW_DENOM_TOL_F) ? 0.0f : (num / den);
}

__global__ void nw_eval_mv_kernel(const float *x_flat,
                                   const float *train_x_flat,
                                   const float *train_y,
                                   int n_train, int n_eval, int dim,
                                   const float *h, int kernel_type,
                                   float *result)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n_eval) return;

    float num = 0.0f, den = 0.0f;
    float u[10];

    for (int j = 0; j < n_train; j++) {
        for (int d = 0; d < dim; d++) {
            float xi_d = x_flat[d * n_eval + i];
            float xj_d = train_x_flat[d * n_train + j];
            u[d] = (xi_d - xj_d) / h[d];
        }
        float w = dev_kernel_product(u, dim, kernel_type);
        num += w * train_y[j];
        den += w;
    }

    result[i] = (den < NW_DENOM_TOL_F) ? 0.0f : (num / den);
}

__global__ void cv_mse_1d_kernel(const float *data_x,
                                  const float *data_y,
                                  int n,
                                  const int *fold_starts,
                                  const int *fold_ends,
                                  int k,
                                  float h, int kernel_type,
                                  float *partials)
{
    int global_i = blockIdx.x * blockDim.x + threadIdx.x;
    if (global_i >= n) return;

    int my_fold = -1;
    for (int f = 0; f < k; f++) {
        if (global_i >= fold_starts[f] && global_i < fold_ends[f]) {
            my_fold = f;
            break;
        }
    }
    if (my_fold < 0) {
        partials[global_i] = 0.0f;
        return;
    }

    int test_start = fold_starts[my_fold];
    int test_end   = fold_ends[my_fold];

    float xi = data_x[global_i];
    float yi = data_y[global_i];
    float num = 0.0f, den = 0.0f;

    for (int j = 0; j < n; j++) {
        if (j >= test_start && j < test_end) continue;
        float u = (xi - data_x[j]) / h;
        float w = dev_kernel_1d(u, kernel_type);
        num += w * data_y[j];
        den += w;
    }

    if (den < NW_DENOM_TOL_F) {
        partials[global_i] = 0.0f;
    } else {
        float resid = yi - (num / den);
        partials[global_i] = -(resid * resid);
    }
}

__global__ void cv_mse_mv_kernel(const float *data_x_flat,
                                  const float *data_y,
                                  int n, int dim,
                                  const int *fold_starts,
                                  const int *fold_ends,
                                  int k,
                                  const float *h, int kernel_type,
                                  float *partials)
{
    int global_i = blockIdx.x * blockDim.x + threadIdx.x;
    if (global_i >= n) return;

    int my_fold = -1;
    for (int f = 0; f < k; f++) {
        if (global_i >= fold_starts[f] && global_i < fold_ends[f]) {
            my_fold = f;
            break;
        }
    }
    if (my_fold < 0) {
        partials[global_i] = 0.0f;
        return;
    }

    int test_start = fold_starts[my_fold];
    int test_end   = fold_ends[my_fold];

    float u[10];
    float num = 0.0f, den = 0.0f;

    for (int j = 0; j < n; j++) {
        if (j >= test_start && j < test_end) continue;
        for (int d = 0; d < dim; d++) {
            float xi_d = data_x_flat[d * n + global_i];
            float xj_d = data_x_flat[d * n + j];
            u[d] = (xi_d - xj_d) / h[d];
        }
        float w = dev_kernel_product(u, dim, kernel_type);
        num += w * data_y[j];
        den += w;
    }

    if (den < NW_DENOM_TOL_F) {
        partials[global_i] = 0.0f;
    } else {
        float resid = data_y[global_i] - (num / den);
        partials[global_i] = -(resid * resid);
    }
}

static void compute_fold_boundaries(int n, int k, int *fold_starts, int *fold_ends)
{
    for (int f = 0; f < k; f++) {
        fold_starts[f] = (f * n) / k;
        fold_ends[f]   = ((f + 1) * n) / k;
    }
}

#define BLOCK_SIZE 256

static int grid_size(int n)
{
    return (n + BLOCK_SIZE - 1) / BLOCK_SIZE;
}

#define CUDA_CHECK(call) \
    do { \
        cudaError_t _e = (call); \
        if (_e != cudaSuccess) { \
            return (int)_e; \
        } \
    } while(0)

static void _cuda_free4(void *a, void *b, void *c, void *d)
{
    if (a) cudaFree(a);
    if (b) cudaFree(b);
    if (c) cudaFree(c);
    if (d) cudaFree(d);
}

extern "C" {

int gpu_preflight_check(int device_id, size_t required_bytes)
{
    int device_count = 0;
    CUDA_CHECK(cudaGetDeviceCount(&device_count));
    if (device_count == 0) return -1;
    if (device_id < 0 || device_id >= device_count) return -2;

    struct cudaDeviceProp props;
    CUDA_CHECK(cudaGetDeviceProperties(&props, device_id));
    if (props.major < 6) return -3;

    size_t free_mem = 0, total_mem = 0;
    CUDA_CHECK(cudaSetDevice(device_id));
    CUDA_CHECK(cudaMemGetInfo(&free_mem, &total_mem));
    if (required_bytes > free_mem) return -4;

    return 0;
}

int gpu_nw_eval_1d(double *x, double *train_x, double *train_y,
                   int n_train, int n_eval,
                   double h, int kernel_type, double *result,
                   int device_id)
{
    CUDA_CHECK(cudaSetDevice(device_id));

    float *h_x      = (float*)malloc(n_eval  * sizeof(float));
    float *h_trainx = (float*)malloc(n_train * sizeof(float));
    float *h_trainy = (float*)malloc(n_train * sizeof(float));
    float *h_result = (float*)malloc(n_eval  * sizeof(float));
    if (!h_x || !h_trainx || !h_trainy || !h_result) {
        free(h_x); free(h_trainx); free(h_trainy); free(h_result);
        return -100;
    }

    for (int i = 0; i < n_eval;  i++) h_x[i]      = (float)x[i];
    for (int j = 0; j < n_train; j++) h_trainx[j]  = (float)train_x[j];
    for (int j = 0; j < n_train; j++) h_trainy[j]  = (float)train_y[j];

    float *d_x = NULL, *d_trainx = NULL, *d_trainy = NULL, *d_result = NULL;
    cudaError_t err;

    err = cudaMalloc(&d_x,       n_eval  * sizeof(float));
    if (err != cudaSuccess) goto eval1d_err;
    err = cudaMalloc(&d_trainx,  n_train * sizeof(float));
    if (err != cudaSuccess) goto eval1d_err;
    err = cudaMalloc(&d_trainy,  n_train * sizeof(float));
    if (err != cudaSuccess) goto eval1d_err;
    err = cudaMalloc(&d_result,  n_eval  * sizeof(float));
    if (err != cudaSuccess) goto eval1d_err;

    err = cudaMemcpy(d_x,      h_x,      n_eval  * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto eval1d_err;
    err = cudaMemcpy(d_trainx, h_trainx, n_train * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto eval1d_err;
    err = cudaMemcpy(d_trainy, h_trainy, n_train * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto eval1d_err;

    nw_eval_1d_kernel<<<grid_size(n_eval), BLOCK_SIZE>>>(
        d_x, d_trainx, d_trainy, n_train, n_eval, (float)h, kernel_type, d_result);

    err = cudaGetLastError();
    if (err != cudaSuccess) goto eval1d_err;
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) goto eval1d_err;

    err = cudaMemcpy(h_result, d_result, n_eval * sizeof(float), cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) goto eval1d_err;

    for (int i = 0; i < n_eval; i++) result[i] = (double)h_result[i];

    free(h_x); free(h_trainx); free(h_trainy); free(h_result);
    _cuda_free4(d_x, d_trainx, d_trainy, d_result);
    return 0;

eval1d_err:
    free(h_x); free(h_trainx); free(h_trainy); free(h_result);
    _cuda_free4(d_x, d_trainx, d_trainy, d_result);
    return (int)err;
}

int gpu_nw_eval_mv(double *x_flat, double **train_x, double *train_y,
                   int n_train, int n_eval, int dim,
                   double *h, int kernel_type, double *result,
                   int device_id)
{
    CUDA_CHECK(cudaSetDevice(device_id));

    size_t x_elems     = (size_t)dim * n_eval;
    size_t train_elems = (size_t)dim * n_train;

    float *h_x_f      = (float*)malloc(x_elems     * sizeof(float));
    float *h_trainx_f = (float*)malloc(train_elems * sizeof(float));
    float *h_trainy   = (float*)malloc(n_train     * sizeof(float));
    float *h_h_f      = (float*)malloc(dim         * sizeof(float));
    float *h_result_f = (float*)malloc(n_eval      * sizeof(float));

    if (!h_x_f || !h_trainx_f || !h_trainy || !h_h_f || !h_result_f) {
        free(h_x_f); free(h_trainx_f); free(h_trainy); free(h_h_f); free(h_result_f);
        return -100;
    }

    for (int d = 0; d < dim; d++) {
        for (int i = 0; i < n_eval; i++)
            h_x_f[d * n_eval + i] = (float)x_flat[d * n_eval + i];
        for (int j = 0; j < n_train; j++)
            h_trainx_f[d * n_train + j] = (float)train_x[d][j];
        h_h_f[d] = (float)h[d];
    }
    for (int j = 0; j < n_train; j++) h_trainy[j] = (float)train_y[j];

    float *d_x = NULL, *d_trainx = NULL, *d_trainy = NULL, *d_h = NULL, *d_result = NULL;
    cudaError_t err;

    err = cudaMalloc(&d_x,       x_elems     * sizeof(float));
    if (err != cudaSuccess) goto evalmv_err;
    err = cudaMalloc(&d_trainx,  train_elems * sizeof(float));
    if (err != cudaSuccess) goto evalmv_err;
    err = cudaMalloc(&d_trainy,  n_train     * sizeof(float));
    if (err != cudaSuccess) goto evalmv_err;
    err = cudaMalloc(&d_h,       dim         * sizeof(float));
    if (err != cudaSuccess) goto evalmv_err;
    err = cudaMalloc(&d_result,  n_eval      * sizeof(float));
    if (err != cudaSuccess) goto evalmv_err;

    err = cudaMemcpy(d_x,      h_x_f,      x_elems     * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto evalmv_err;
    err = cudaMemcpy(d_trainx, h_trainx_f, train_elems * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto evalmv_err;
    err = cudaMemcpy(d_trainy, h_trainy,   n_train     * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto evalmv_err;
    err = cudaMemcpy(d_h,      h_h_f,      dim         * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto evalmv_err;

    nw_eval_mv_kernel<<<grid_size(n_eval), BLOCK_SIZE>>>(
        d_x, d_trainx, d_trainy, n_train, n_eval, dim, d_h, kernel_type, d_result);

    err = cudaGetLastError();
    if (err != cudaSuccess) goto evalmv_err;
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) goto evalmv_err;

    err = cudaMemcpy(h_result_f, d_result, n_eval * sizeof(float), cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) goto evalmv_err;

    for (int i = 0; i < n_eval; i++) result[i] = (double)h_result_f[i];

    free(h_x_f); free(h_trainx_f); free(h_trainy); free(h_h_f); free(h_result_f);
    _cuda_free4(d_x, d_trainx, d_trainy, d_h);
    if (d_result) cudaFree(d_result);
    return 0;

evalmv_err:
    free(h_x_f); free(h_trainx_f); free(h_trainy); free(h_h_f); free(h_result_f);
    _cuda_free4(d_x, d_trainx, d_trainy, d_h);
    if (d_result) cudaFree(d_result);
    return (int)err;
}

int gpu_cv_mse_1d(double *data_x, double *data_y, int n,
                  double h, int kernel_type, int k,
                  double *score, int device_id)
{
    CUDA_CHECK(cudaSetDevice(device_id));

    int   *fold_starts = (int*)  malloc(k * sizeof(int));
    int   *fold_ends   = (int*)  malloc(k * sizeof(int));
    float *h_datax_f   = (float*)malloc(n * sizeof(float));
    float *h_datay_f   = (float*)malloc(n * sizeof(float));
    float *h_partials  = (float*)malloc(n * sizeof(float));

    if (!fold_starts || !fold_ends || !h_datax_f || !h_datay_f || !h_partials) {
        free(fold_starts); free(fold_ends); free(h_datax_f); free(h_datay_f); free(h_partials);
        return -100;
    }
    compute_fold_boundaries(n, k, fold_starts, fold_ends);

    for (int i = 0; i < n; i++) {
        h_datax_f[i] = (float)data_x[i];
        h_datay_f[i] = (float)data_y[i];
    }

    float *d_datax    = NULL, *d_datay = NULL, *d_partials = NULL;
    int   *d_fstarts  = NULL, *d_fends = NULL;
    cudaError_t err = cudaSuccess;

    err = cudaMalloc(&d_datax,    n * sizeof(float));
    if (err != cudaSuccess) goto cvmse1_cleanup;
    err = cudaMalloc(&d_datay,    n * sizeof(float));
    if (err != cudaSuccess) goto cvmse1_cleanup;
    err = cudaMalloc(&d_fstarts,  k * sizeof(int));
    if (err != cudaSuccess) goto cvmse1_cleanup;
    err = cudaMalloc(&d_fends,    k * sizeof(int));
    if (err != cudaSuccess) goto cvmse1_cleanup;
    err = cudaMalloc(&d_partials, n * sizeof(float));
    if (err != cudaSuccess) goto cvmse1_cleanup;

    err = cudaMemcpy(d_datax,  h_datax_f, n * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmse1_cleanup;
    err = cudaMemcpy(d_datay,  h_datay_f, n * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmse1_cleanup;
    err = cudaMemcpy(d_fstarts, fold_starts, k * sizeof(int), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmse1_cleanup;
    err = cudaMemcpy(d_fends,   fold_ends,   k * sizeof(int), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmse1_cleanup;

    cv_mse_1d_kernel<<<grid_size(n), BLOCK_SIZE>>>(
        d_datax, d_datay, n, d_fstarts, d_fends, k, (float)h, kernel_type, d_partials);

    err = cudaGetLastError();
    if (err != cudaSuccess) goto cvmse1_cleanup;
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) goto cvmse1_cleanup;

    err = cudaMemcpy(h_partials, d_partials, n * sizeof(float), cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) goto cvmse1_cleanup;

    {
        double total = 0.0;
        int n_test_total = 0;
        for (int i = 0; i < n; i++) {
            if (h_partials[i] != 0.0f) {
                total += (double)h_partials[i];
                n_test_total++;
            }
        }
        *score = (n_test_total > 0) ? (total / n_test_total) : -1e100;
    }

cvmse1_cleanup:
    free(fold_starts); free(fold_ends); free(h_datax_f); free(h_datay_f); free(h_partials);
    if (d_datax)    cudaFree(d_datax);
    if (d_datay)    cudaFree(d_datay);
    if (d_fstarts)  cudaFree(d_fstarts);
    if (d_fends)    cudaFree(d_fends);
    if (d_partials) cudaFree(d_partials);
    return (int)err;
}

int gpu_cv_mse_mv(double **data_x, double *data_y, int n, int dim,
                  double *h, int kernel_type, int k,
                  double *score, int device_id)
{
    CUDA_CHECK(cudaSetDevice(device_id));

    size_t data_elems = (size_t)dim * n;

    float *h_datax_f   = (float*)malloc(data_elems * sizeof(float));
    float *h_datay_f   = (float*)malloc(n        * sizeof(float));
    float *h_h_f       = (float*)malloc(dim      * sizeof(float));
    int   *fold_starts = (int*)  malloc(k        * sizeof(int));
    int   *fold_ends   = (int*)  malloc(k        * sizeof(int));
    float *h_partials  = (float*)malloc(n        * sizeof(float));

    if (!h_datax_f || !h_datay_f || !h_h_f || !fold_starts || !fold_ends || !h_partials) {
        free(h_datax_f); free(h_datay_f); free(h_h_f); free(fold_starts); free(fold_ends); free(h_partials);
        return -100;
    }

    for (int d = 0; d < dim; d++) {
        for (int i = 0; i < n; i++)
            h_datax_f[d * n + i] = (float)data_x[d][i];
        h_h_f[d] = (float)h[d];
    }
    for (int i = 0; i < n; i++) h_datay_f[i] = (float)data_y[i];

    compute_fold_boundaries(n, k, fold_starts, fold_ends);

    float *d_datax = NULL, *d_datay = NULL, *d_h = NULL, *d_partials = NULL;
    int   *d_fstarts = NULL, *d_fends = NULL;
    cudaError_t err = cudaSuccess;

    err = cudaMalloc(&d_datax,    data_elems * sizeof(float));
    if (err != cudaSuccess) goto cvmsemv_cleanup;
    err = cudaMalloc(&d_datay,    n          * sizeof(float));
    if (err != cudaSuccess) goto cvmsemv_cleanup;
    err = cudaMalloc(&d_h,        dim        * sizeof(float));
    if (err != cudaSuccess) goto cvmsemv_cleanup;
    err = cudaMalloc(&d_fstarts,  k          * sizeof(int));
    if (err != cudaSuccess) goto cvmsemv_cleanup;
    err = cudaMalloc(&d_fends,    k          * sizeof(int));
    if (err != cudaSuccess) goto cvmsemv_cleanup;
    err = cudaMalloc(&d_partials, n          * sizeof(float));
    if (err != cudaSuccess) goto cvmsemv_cleanup;

    err = cudaMemcpy(d_datax,   h_datax_f,  data_elems * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmsemv_cleanup;
    err = cudaMemcpy(d_datay,   h_datay_f,  n          * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmsemv_cleanup;
    err = cudaMemcpy(d_h,       h_h_f,      dim        * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmsemv_cleanup;
    err = cudaMemcpy(d_fstarts, fold_starts, k         * sizeof(int),   cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmsemv_cleanup;
    err = cudaMemcpy(d_fends,   fold_ends,   k         * sizeof(int),   cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmsemv_cleanup;

    cv_mse_mv_kernel<<<grid_size(n), BLOCK_SIZE>>>(
        d_datax, d_datay, n, dim, d_fstarts, d_fends, k, d_h, kernel_type, d_partials);

    err = cudaGetLastError();
    if (err != cudaSuccess) goto cvmsemv_cleanup;
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) goto cvmsemv_cleanup;

    err = cudaMemcpy(h_partials, d_partials, n * sizeof(float), cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) goto cvmsemv_cleanup;

    {
        double total = 0.0;
        int n_test_total = 0;
        for (int i = 0; i < n; i++) {
            if (h_partials[i] != 0.0f) {
                total += (double)h_partials[i];
                n_test_total++;
            }
        }
        *score = (n_test_total > 0) ? (total / n_test_total) : -1e100;
    }

cvmsemv_cleanup:
    free(h_datax_f); free(h_datay_f); free(h_h_f); free(fold_starts); free(fold_ends); free(h_partials);
    if (d_datax)    cudaFree(d_datax);
    if (d_datay)    cudaFree(d_datay);
    if (d_h)        cudaFree(d_h);
    if (d_fstarts)  cudaFree(d_fstarts);
    if (d_fends)    cudaFree(d_fends);
    if (d_partials) cudaFree(d_partials);
    return (int)err;
}

} /* extern "C" */
