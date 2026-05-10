/**
 * kdensity2_cuda.cu - GPU dispatch functions for kdensity2
 *
 * Implements CUDA kernels and host dispatch functions for:
 *   - 1D kernel density evaluation
 *   - Multivariate (product) kernel density evaluation
 *   - 1D K-fold CV log-likelihood score
 *   - Multivariate K-fold CV log-likelihood score
 *   - GPU preflight check
 *
 * Kernel type constants from utils.h:
 *   KERNEL_GAUSSIAN=0, KERNEL_EPANECHNIKOV=1, KERNEL_UNIFORM=2,
 *   KERNEL_TRIWEIGHT=3, KERNEL_COSINE=4
 *
 * All host functions use extern "C" linkage for Stata ABI compatibility.
 *
 * NOTE: GPU computation uses single-precision float internally for ~2x
 * performance over double on NVIDIA GPUs (half memory bandwidth, 2x peak
 * FLOPs on most architectures). Host dispatch functions convert double* <->
 * float* at the host/device boundary. The public API stays double*.
 */

#include "kdensity2_cuda.h"

#include <cuda_runtime.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ============================================================================
 * Kernel Constants (mirror utils.h — cannot include C header in .cu directly
 * because utils.h includes stplugin.h which redefines things in C++ context)
 * ============================================================================ */

#define _KERNEL_GAUSSIAN     0
#define _KERNEL_EPANECHNIKOV 1
#define _KERNEL_UNIFORM      2
#define _KERNEL_TRIWEIGHT    3
#define _KERNEL_COSINE       4

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define M_PI_F 3.14159265358979f

/* ============================================================================
 * Device-side kernel evaluation helpers — all float
 * ============================================================================ */

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

/* Product kernel across dim dimensions — all float */
__device__ static float dev_kernel_product(const float *u, int dim, int kernel_type)
{
    float prod = 1.0f;
    for (int d = 0; d < dim; d++) {
        prod *= dev_kernel_1d(u[d], kernel_type);
        if (prod == 0.0f) return 0.0f; /* early exit for bounded kernels */
    }
    return prod;
}

/* ============================================================================
 * CUDA Kernels — all float
 * ============================================================================ */

/**
 * kde_eval_1d_kernel — one thread per evaluation point.
 *
 * x[n_eval]      — evaluation points (float)
 * train[n_train] — training data (float)
 * result[n_eval] — output densities (float)
 */
__global__ void kde_eval_1d_kernel(const float *x, const float *train,
                                    int n_train, int n_eval,
                                    float h, int kernel_type,
                                    float *result)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n_eval) return;

    float xi = x[i];
    float sum = 0.0f;
    for (int j = 0; j < n_train; j++) {
        float u = (xi - train[j]) / h;
        sum += dev_kernel_1d(u, kernel_type);
    }
    result[i] = sum / ((float)n_train * h);
}

/**
 * kde_eval_mv_kernel — one thread per evaluation point.
 *
 * x_flat[dim * n_eval]      — evaluation points, column-major: x_flat[d * n_eval + i]
 * train_flat[dim * n_train] — training data, column-major: train_flat[d * n_train + j]
 * h[dim]                    — bandwidth per dimension (float)
 * result[n_eval]             — output densities (float)
 */
__global__ void kde_eval_mv_kernel(const float *x_flat, const float *train_flat,
                                    int n_train, int n_eval, int dim,
                                    const float *h, int kernel_type,
                                    float *result)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n_eval) return;

    float sum = 0.0f;
    /* reuse stack array; dim <= MAX_DIM=10 */
    float u[10];

    for (int j = 0; j < n_train; j++) {
        for (int d = 0; d < dim; d++) {
            float xi_d   = x_flat[d * n_eval  + i];
            float xj_d   = train_flat[d * n_train + j];
            u[d] = (xi_d - xj_d) / h[d];
        }
        sum += dev_kernel_product(u, dim, kernel_type);
    }

    float h_prod = 1.0f;
    for (int d = 0; d < dim; d++) h_prod *= h[d];

    result[i] = sum / ((float)n_train * h_prod);
}

/**
 * cv_score_1d_kernel — one thread per test point.
 *
 * Each thread computes the leave-fold-out density contribution for one test point.
 * data[n]           — full dataset (float)
 * fold_starts[k]    — start index of each fold
 * fold_ends[k]      — end index (exclusive) of each fold
 * n                 — total observations
 * k                 — number of folds
 * partials[n]       — output: log-density contribution per test observation (float)
 *                     (written by thread owning that test obs)
 */
__global__ void cv_score_1d_kernel(const float *data, int n,
                                    const int *fold_starts, const int *fold_ends,
                                    int k, float h, int kernel_type,
                                    float *partials)
{
    int global_i = blockIdx.x * blockDim.x + threadIdx.x;
    if (global_i >= n) return;

    /* Find which fold this observation belongs to */
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
    int train_size = n - (test_end - test_start);

    if (train_size < 2) {
        partials[global_i] = 0.0f;
        return;
    }

    float xi = data[global_i];
    float sum = 0.0f;
    for (int j = 0; j < n; j++) {
        if (j >= test_start && j < test_end) continue;
        float u = (xi - data[j]) / h;
        sum += dev_kernel_1d(u, kernel_type);
    }

    float density = sum / ((float)train_size * h);
    partials[global_i] = (density > 0.0f) ? logf(density) : -1e15f;
}

/**
 * cv_score_mv_kernel — one thread per test point (multivariate).
 *
 * data_flat[dim * n] — full dataset, column-major: data_flat[d * n + i] (float)
 * h[dim]             — bandwidth per dimension (float)
 * partials[n]        — output: log-density contribution per test observation (float)
 */
__global__ void cv_score_mv_kernel(const float *data_flat, int n, int dim,
                                    const int *fold_starts, const int *fold_ends,
                                    int k, const float *h, int kernel_type,
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
    int train_size = n - (test_end - test_start);

    if (train_size < 2) {
        partials[global_i] = 0.0f;
        return;
    }

    float u[10];
    float sum = 0.0f;

    for (int j = 0; j < n; j++) {
        if (j >= test_start && j < test_end) continue;
        for (int d = 0; d < dim; d++) {
            float xi_d = data_flat[d * n + global_i];
            float xj_d = data_flat[d * n + j];
            u[d] = (xi_d - xj_d) / h[d];
        }
        sum += dev_kernel_product(u, dim, kernel_type);
    }

    float h_prod = 1.0f;
    for (int d = 0; d < dim; d++) h_prod *= h[d];

    float density = sum / ((float)train_size * h_prod);
    partials[global_i] = (density > 0.0f) ? logf(density) : -1e15f;
}

/* ============================================================================
 * Helper: compute fold boundaries on the host
 * ============================================================================ */

static void compute_fold_boundaries(int n, int k, int *fold_starts, int *fold_ends)
{
    for (int f = 0; f < k; f++) {
        fold_starts[f] = (f * n) / k;
        fold_ends[f]   = ((f + 1) * n) / k;
    }
}

/* ============================================================================
 * Kernel launch configuration
 * ============================================================================ */

#define BLOCK_SIZE 256

static int grid_size(int n)
{
    return (n + BLOCK_SIZE - 1) / BLOCK_SIZE;
}

/* ============================================================================
 * Error checking macro
 * ============================================================================ */

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

static void _cuda_free3(void *a, void *b, void *c)
{
    _cuda_free4(a, b, c, NULL);
}

/* ============================================================================
 * Host dispatch functions — extern "C" for Stata ABI
 *
 * Public API stays double*. Double<->float conversion happens here at the
 * host/device boundary before and after cudaMemcpy.
 * ============================================================================ */

extern "C" {

/**
 * gpu_preflight_check — verify CUDA device and free memory.
 */
int gpu_preflight_check(int device_id, size_t required_bytes)
{
    int device_count = 0;
    CUDA_CHECK(cudaGetDeviceCount(&device_count));
    if (device_count == 0) return -1;
    if (device_id < 0 || device_id >= device_count) return -2;

    struct cudaDeviceProp props;
    CUDA_CHECK(cudaGetDeviceProperties(&props, device_id));
    if (props.major < 6) return -3; /* require sm_60+ */

    size_t free_mem = 0, total_mem = 0;
    CUDA_CHECK(cudaSetDevice(device_id));
    CUDA_CHECK(cudaMemGetInfo(&free_mem, &total_mem));
    if (required_bytes > free_mem) return -4;

    return 0;
}

/**
 * gpu_kde_eval_1d — 1D kernel density evaluation on GPU.
 *
 * Public API: double*. Internally converts to float before GPU dispatch.
 */
int gpu_kde_eval_1d(double *x, double *train, int n_train, int n_eval,
                    double h, int kernel_type, double *result, int device_id)
{
    CUDA_CHECK(cudaSetDevice(device_id));

    /* Host-side float conversion buffers */
    float *h_x      = (float*)malloc(n_eval  * sizeof(float));
    float *h_train  = (float*)malloc(n_train * sizeof(float));
    float *h_result = (float*)malloc(n_eval  * sizeof(float));
    if (!h_x || !h_train || !h_result) {
        free(h_x); free(h_train); free(h_result);
        return -100;
    }

    for (int i = 0; i < n_eval;  i++) h_x[i]     = (float)x[i];
    for (int j = 0; j < n_train; j++) h_train[j]  = (float)train[j];

    /* Device float buffers — half the bytes of double */
    float *d_x = NULL, *d_train = NULL, *d_result = NULL;

    CUDA_CHECK(cudaMalloc(&d_x,      n_eval  * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_train,  n_train * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_result, n_eval  * sizeof(float)));

    cudaError_t err;
    err = cudaMemcpy(d_x,     h_x,    n_eval  * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) { free(h_x); free(h_train); free(h_result); _cuda_free3(d_x,d_train,d_result); return (int)err; }
    err = cudaMemcpy(d_train, h_train, n_train * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) { free(h_x); free(h_train); free(h_result); _cuda_free3(d_x,d_train,d_result); return (int)err; }

    kde_eval_1d_kernel<<<grid_size(n_eval), BLOCK_SIZE>>>(
        d_x, d_train, n_train, n_eval, (float)h, kernel_type, d_result);

    err = cudaGetLastError();
    if (err != cudaSuccess) { free(h_x); free(h_train); free(h_result); _cuda_free3(d_x,d_train,d_result); return (int)err; }
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) { free(h_x); free(h_train); free(h_result); _cuda_free3(d_x,d_train,d_result); return (int)err; }

    err = cudaMemcpy(h_result, d_result, n_eval * sizeof(float), cudaMemcpyDeviceToHost);
    _cuda_free3(d_x, d_train, d_result);
    if (err != cudaSuccess) { free(h_x); free(h_train); free(h_result); return (int)err; }

    /* Convert float results back to double for caller */
    for (int i = 0; i < n_eval; i++) result[i] = (double)h_result[i];

    free(h_x); free(h_train); free(h_result);
    return 0;
}

/**
 * gpu_kde_eval_mv — multivariate kernel density evaluation on GPU.
 *
 * x is [dim][n_eval] (row-major pointer-to-pointer on host), contiguous flat.
 * train is [dim][n_train] (pointer-to-pointer on host), needs flattening.
 * Public API: double*. Internally converts to float before GPU dispatch.
 */
int gpu_kde_eval_mv(double *x, double **train, int n_train, int n_eval,
                    int dim, double *h, int kernel_type, double *result,
                    int device_id)
{
    CUDA_CHECK(cudaSetDevice(device_id));

    size_t x_elems     = (size_t)dim * n_eval;
    size_t train_elems = (size_t)dim * n_train;

    /* Host-side float conversion buffers */
    float *h_x_f      = (float*)malloc(x_elems     * sizeof(float));
    float *h_train_f  = (float*)malloc(train_elems  * sizeof(float));
    float *h_h_f      = (float*)malloc(dim          * sizeof(float));
    float *h_result_f = (float*)malloc(n_eval       * sizeof(float));

    if (!h_x_f || !h_train_f || !h_h_f || !h_result_f) {
        free(h_x_f); free(h_train_f); free(h_h_f); free(h_result_f);
        return -100;
    }

    /* x is already contiguous flat: x[d * n_eval + i] */
    for (size_t k = 0; k < x_elems; k++) h_x_f[k] = (float)x[k];

    /* train is double** — flatten and convert */
    for (int d = 0; d < dim; d++)
        for (int j = 0; j < n_train; j++)
            h_train_f[d * n_train + j] = (float)train[d][j];

    for (int d = 0; d < dim; d++) h_h_f[d] = (float)h[d];

    /* Device float buffers */
    float *d_x = NULL, *d_train = NULL, *d_h = NULL, *d_result = NULL;
    cudaError_t err;

    err = cudaMalloc(&d_x,      x_elems     * sizeof(float));
    if (err != cudaSuccess) goto mv_err;
    err = cudaMalloc(&d_train,  train_elems * sizeof(float));
    if (err != cudaSuccess) goto mv_err;
    err = cudaMalloc(&d_h,      dim         * sizeof(float));
    if (err != cudaSuccess) goto mv_err;
    err = cudaMalloc(&d_result, n_eval      * sizeof(float));
    if (err != cudaSuccess) goto mv_err;

    err = cudaMemcpy(d_x,     h_x_f,     x_elems     * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto mv_err;
    err = cudaMemcpy(d_train, h_train_f,  train_elems * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto mv_err;
    err = cudaMemcpy(d_h,     h_h_f,      dim         * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto mv_err;

    kde_eval_mv_kernel<<<grid_size(n_eval), BLOCK_SIZE>>>(
        d_x, d_train, n_train, n_eval, dim, d_h, kernel_type, d_result);

    err = cudaGetLastError();
    if (err != cudaSuccess) goto mv_err;
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) goto mv_err;

    err = cudaMemcpy(h_result_f, d_result, n_eval * sizeof(float), cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) goto mv_err;

    /* Convert float results back to double for caller */
    for (int i = 0; i < n_eval; i++) result[i] = (double)h_result_f[i];

    free(h_x_f); free(h_train_f); free(h_h_f); free(h_result_f);
    _cuda_free4(d_x, d_train, d_h, d_result);
    return 0;

mv_err:
    free(h_x_f); free(h_train_f); free(h_h_f); free(h_result_f);
    _cuda_free4(d_x, d_train, d_h, d_result);
    return (int)err;
}

/**
 * gpu_cv_score_1d — 1D K-fold CV log-likelihood score on GPU.
 *
 * Public API: double*. Internally converts to float before GPU dispatch.
 * Partials are summed back in double precision.
 */
int gpu_cv_score_1d(double *data, int n, double h, int kernel_type,
                    int k, double *score, int device_id)
{
    CUDA_CHECK(cudaSetDevice(device_id));

    /* Compute fold boundaries on host */
    int   *fold_starts = (int*)  malloc(k * sizeof(int));
    int   *fold_ends   = (int*)  malloc(k * sizeof(int));
    float *h_data_f    = (float*)malloc(n * sizeof(float));
    float *h_partials  = (float*)malloc(n * sizeof(float));

    if (!fold_starts || !fold_ends || !h_data_f || !h_partials) {
        free(fold_starts); free(fold_ends); free(h_data_f); free(h_partials);
        return -100;
    }
    compute_fold_boundaries(n, k, fold_starts, fold_ends);

    /* Convert data to float */
    for (int i = 0; i < n; i++) h_data_f[i] = (float)data[i];

    float *d_data     = NULL, *d_partials = NULL;
    int   *d_fstarts  = NULL, *d_fends    = NULL;
    cudaError_t err = cudaSuccess;

    err = cudaMalloc(&d_data,     n * sizeof(float));
    if (err != cudaSuccess) goto cv1_cleanup;
    err = cudaMalloc(&d_fstarts,  k * sizeof(int));
    if (err != cudaSuccess) goto cv1_cleanup;
    err = cudaMalloc(&d_fends,    k * sizeof(int));
    if (err != cudaSuccess) goto cv1_cleanup;
    err = cudaMalloc(&d_partials, n * sizeof(float));
    if (err != cudaSuccess) goto cv1_cleanup;

    err = cudaMemcpy(d_data,    h_data_f,    n * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cv1_cleanup;
    err = cudaMemcpy(d_fstarts, fold_starts, k * sizeof(int),   cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cv1_cleanup;
    err = cudaMemcpy(d_fends,   fold_ends,   k * sizeof(int),   cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cv1_cleanup;

    cv_score_1d_kernel<<<grid_size(n), BLOCK_SIZE>>>(
        d_data, n, d_fstarts, d_fends, k, (float)h, kernel_type, d_partials);

    err = cudaGetLastError();
    if (err != cudaSuccess) goto cv1_cleanup;
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) goto cv1_cleanup;

    err = cudaMemcpy(h_partials, d_partials, n * sizeof(float), cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) goto cv1_cleanup;

    /* Sum float partials into double score */
    {
        double total = 0.0;
        for (int i = 0; i < n; i++) total += (double)h_partials[i];
        *score = total / n;
    }

cv1_cleanup:
    free(fold_starts); free(fold_ends); free(h_data_f); free(h_partials);
    if (d_data)     cudaFree(d_data);
    if (d_fstarts)  cudaFree(d_fstarts);
    if (d_fends)    cudaFree(d_fends);
    if (d_partials) cudaFree(d_partials);
    return (int)err;
}

/**
 * gpu_cv_score_mv — multivariate K-fold CV log-likelihood score on GPU.
 *
 * data is [dim][n] (pointer-to-pointer on host).
 * Public API: double**. Internally converts to float before GPU dispatch.
 * Partials are summed back in double precision.
 */
int gpu_cv_score_mv(double **data, int n, int dim, double *h, int kernel_type,
                    int k, double *score, int device_id)
{
    CUDA_CHECK(cudaSetDevice(device_id));

    size_t data_elems = (size_t)dim * n;

    /* Flatten data and convert to float */
    float *h_data_f    = (float*)malloc(data_elems * sizeof(float));
    float *h_h_f       = (float*)malloc(dim        * sizeof(float));
    int   *fold_starts = (int*)  malloc(k          * sizeof(int));
    int   *fold_ends   = (int*)  malloc(k          * sizeof(int));
    float *h_partials  = (float*)malloc(n          * sizeof(float));

    if (!h_data_f || !h_h_f || !fold_starts || !fold_ends || !h_partials) {
        free(h_data_f); free(h_h_f); free(fold_starts); free(fold_ends); free(h_partials);
        return -100;
    }

    for (int d = 0; d < dim; d++)
        for (int i = 0; i < n; i++)
            h_data_f[d * n + i] = (float)data[d][i];

    for (int d = 0; d < dim; d++) h_h_f[d] = (float)h[d];

    compute_fold_boundaries(n, k, fold_starts, fold_ends);

    float *d_data     = NULL, *d_h = NULL, *d_partials = NULL;
    int   *d_fstarts  = NULL, *d_fends = NULL;
    cudaError_t err = cudaSuccess;

    err = cudaMalloc(&d_data,     data_elems * sizeof(float));
    if (err != cudaSuccess) goto cvmv_cleanup;
    err = cudaMalloc(&d_h,        dim        * sizeof(float));
    if (err != cudaSuccess) goto cvmv_cleanup;
    err = cudaMalloc(&d_fstarts,  k          * sizeof(int));
    if (err != cudaSuccess) goto cvmv_cleanup;
    err = cudaMalloc(&d_fends,    k          * sizeof(int));
    if (err != cudaSuccess) goto cvmv_cleanup;
    err = cudaMalloc(&d_partials, n          * sizeof(float));
    if (err != cudaSuccess) goto cvmv_cleanup;

    err = cudaMemcpy(d_data,    h_data_f,    data_elems * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmv_cleanup;
    err = cudaMemcpy(d_h,       h_h_f,       dim        * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmv_cleanup;
    err = cudaMemcpy(d_fstarts, fold_starts, k          * sizeof(int),   cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmv_cleanup;
    err = cudaMemcpy(d_fends,   fold_ends,   k          * sizeof(int),   cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto cvmv_cleanup;

    cv_score_mv_kernel<<<grid_size(n), BLOCK_SIZE>>>(
        d_data, n, dim, d_fstarts, d_fends, k, d_h, kernel_type, d_partials);

    err = cudaGetLastError();
    if (err != cudaSuccess) goto cvmv_cleanup;
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) goto cvmv_cleanup;

    err = cudaMemcpy(h_partials, d_partials, n * sizeof(float), cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) goto cvmv_cleanup;

    /* Sum float partials into double score */
    {
        double total = 0.0;
        for (int i = 0; i < n; i++) total += (double)h_partials[i];
        *score = total / n;
    }

cvmv_cleanup:
    free(h_data_f); free(h_h_f); free(fold_starts); free(fold_ends); free(h_partials);
    if (d_data)     cudaFree(d_data);
    if (d_h)        cudaFree(d_h);
    if (d_fstarts)  cudaFree(d_fstarts);
    if (d_fends)    cudaFree(d_fends);
    if (d_partials) cudaFree(d_partials);
    return (int)err;
}

} /* extern "C" */
