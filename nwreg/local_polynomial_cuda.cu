/**
 * local_polynomial_cuda.cu - GPU dispatch functions for local polynomial regression
 *
 * Implements CUDA kernels and host dispatch functions for:
 *   - 1D local polynomial regression evaluation (poly >= 1)
 *   - Multivariate local linear regression evaluation (poly = 1)
 *
 * All GPU computation uses single-precision float internally.
 * Each thread handles one evaluation point, building and solving a small WLS
 * system using Gaussian elimination with partial pivoting.
 */

#include "local_polynomial_cuda.h"

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

#define BLOCK_SIZE 256

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

/**
 * Solve small linear system A * x = b using Gaussian elimination with partial pivoting.
 * A is n x n (column-major), b is length n.
 * Overwrites b with solution x. Returns 0 on success.
 * Uses shared memory-like scratch space on thread-local stack.
 */
__device__ static int solve_small_wls(float *A, float *b, int n)
{
    // Forward elimination with partial pivoting
    for (int col = 0; col < n; col++) {
        // Find pivot
        int pivot_row = col;
        float pivot_val = fabsf(A[col * n + col]);
        for (int r = col + 1; r < n; r++) {
            float v = fabsf(A[col * n + r]);
            if (v > pivot_val) {
                pivot_val = v;
                pivot_row = r;
            }
        }

        if (pivot_val < 1e-8f) return -1;  // Singular or near-singular

        // Swap rows if needed
        if (pivot_row != col) {
            for (int c = 0; c < n; c++) {
                float tmp = A[c * n + col];
                A[c * n + col] = A[c * n + pivot_row];
                A[c * n + pivot_row] = tmp;
            }
            float tmp = b[col];
            b[col] = b[pivot_row];
            b[pivot_row] = tmp;
        }

        // Eliminate below
        for (int r = col + 1; r < n; r++) {
            float factor = A[col * n + r] / A[col * n + col];
            b[r] -= factor * b[col];
            for (int c = col; c < n; c++) {
                A[c * n + r] -= factor * A[c * n + col];
            }
        }
    }

    // Back substitution
    for (int i = n - 1; i >= 0; i--) {
        float sum = b[i];
        for (int j = i + 1; j < n; j++) {
            sum -= A[j * n + i] * b[j];
        }
        b[i] = sum / A[i * n + i];
    }

    return 0;
}

/**
 * 1D Local Polynomial kernel.
 * Each thread evaluates at one point, solving a small WLS with basis:
 *   1, (x - a), (x - a)^2, ..., (x - a)^poly
 * Max poly = 3 (4x4 system).
 */
__global__ void lp_eval_1d_kernel(const float *eval_x,
                                   const float *train_x,
                                   const float *train_y,
                                   int n_train, int n_eval,
                                   float h, int kernel_type, int poly,
                                   float *result, float *derivatives,
                                   int nderiv)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n_eval) return;

    float xi = eval_x[i];

    // Max system size: poly=3 => 4x4 (constant + 3 powers)
    // A = X'WX, b = X'Wy
    float A[16];  // 4x4 max
    float b[4];

    // Zero-initialize
    for (int j = 0; j < (poly + 1) * (poly + 1); j++) A[j] = 0.0f;
    for (int j = 0; j < poly + 1; j++) b[j] = 0.0f;

    // Accumulate X'WX and X'Wy
    for (int t = 0; t < n_train; t++) {
        float u = (train_x[t] - xi) / h;
        float w = dev_kernel_1d(u, kernel_type);
        if (w == 0.0f) continue;

        float dx = train_x[t] - xi;
        float powers[4];
        powers[0] = 1.0f;
        for (int p = 1; p <= poly; p++) {
            powers[p] = powers[p - 1] * dx;
        }

        // X'WX
        for (int r = 0; r <= poly; r++) {
            for (int c = 0; c <= poly; c++) {
                A[c * (poly + 1) + r] += w * powers[r] * powers[c];
            }
            // X'Wy
            b[r] += w * powers[r] * train_y[t];
        }
    }

    // Solve
    int ret = solve_small_wls(A, b, poly + 1);
    if (ret != 0) {
        result[i] = 0.0f;
        if (derivatives && nderiv > 0) {
            for (int d = 0; d < nderiv; d++) {
                derivatives[d * n_eval + i] = 0.0f;
            }
        }
        return;
    }

    // b[0] = constant coefficient = prediction
    result[i] = b[0];

    // Derivatives: k-th derivative = k! * beta_k
    if (derivatives && nderiv > 0) {
        for (int d = 0; d < nderiv; d++) {
            if (d < poly) {
                float fact = 1.0f;
                for (int f = 2; f <= d + 1; f++) fact *= (float)f;
                derivatives[d * n_eval + i] = fact * b[d + 1];
            } else {
                derivatives[d * n_eval + i] = 0.0f;
            }
        }
    }
}

/**
 * Multivariate local linear kernel (poly = 1).
 * Each thread evaluates at one point, solving a (dim+1) x (dim+1) WLS system.
 * Basis: 1, (x1 - a1), (x2 - a2), ..., (xd - ad)
 */
__global__ void lp_eval_mv_kernel(const float *eval_x_flat,
                                   const float *train_x_flat,
                                   const float *train_y,
                                   int n_train, int n_eval, int dim,
                                   const float *h, int kernel_type,
                                   float *result, float *derivatives,
                                   int nderiv)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n_eval) return;

    int p_total = dim + 1;
    float A[121];  // 11x11 max (dim <= 10)
    float b[11];

    for (int j = 0; j < p_total * p_total; j++) A[j] = 0.0f;
    for (int j = 0; j < p_total; j++) b[j] = 0.0f;

    for (int t = 0; t < n_train; t++) {
        float u[10];
        for (int d = 0; d < dim; d++) {
            float xi_d = eval_x_flat[d * n_eval + i];
            float xj_d = train_x_flat[d * n_train + t];
            u[d] = (xi_d - xj_d) / h[d];
        }
        float w = dev_kernel_product(u, dim, kernel_type);
        if (w == 0.0f) continue;

        // Basis: 1, (x1 - a1), ..., (xd - ad)
        float phi[11];
        phi[0] = 1.0f;
        for (int d = 0; d < dim; d++) {
            phi[d + 1] = eval_x_flat[d * n_eval + i] - train_x_flat[d * n_train + t];
        }

        for (int r = 0; r < p_total; r++) {
            for (int c = 0; c < p_total; c++) {
                A[c * p_total + r] += w * phi[r] * phi[c];
            }
            b[r] += w * phi[r] * train_y[t];
        }
    }

    int ret = solve_small_wls(A, b, p_total);
    if (ret != 0) {
        result[i] = 0.0f;
        if (derivatives && nderiv > 0) {
            for (int d = 0; d < nderiv; d++) {
                derivatives[d * n_eval + i] = 0.0f;
            }
        }
        return;
    }

    result[i] = b[0];  // constant = prediction

    if (derivatives && nderiv > 0) {
        for (int d = 0; d < nderiv; d++) {
            if (d < dim) {
                derivatives[d * n_eval + i] = b[d + 1];  // partial derivative
            } else {
                derivatives[d * n_eval + i] = 0.0f;
            }
        }
    }
}

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

static void _cuda_free5(void *a, void *b, void *c, void *d, void *e)
{
    if (a) cudaFree(a);
    if (b) cudaFree(b);
    if (c) cudaFree(c);
    if (d) cudaFree(d);
    if (e) cudaFree(e);
}

extern "C" {

int gpu_lp_eval_1d(double *eval_x, double *train_x, double *train_y,
                   int n_train, int n_eval,
                   double h, int kernel_type, int poly,
                   double *result, double *derivatives, int nderiv,
                   int device_id)
{
    CUDA_CHECK(cudaSetDevice(device_id));

    float *h_evalx   = (float*)malloc(n_eval  * sizeof(float));
    float *h_trainx  = (float*)malloc(n_train * sizeof(float));
    float *h_trainy  = (float*)malloc(n_train * sizeof(float));
    float *h_result  = (float*)malloc(n_eval  * sizeof(float));
    float *h_deriv   = NULL;
    if (nderiv > 0) {
        h_deriv = (float*)malloc((size_t)nderiv * n_eval * sizeof(float));
    }

    if (!h_evalx || !h_trainx || !h_trainy || !h_result) {
        free(h_evalx); free(h_trainx); free(h_trainy); free(h_result); free(h_deriv);
        return -100;
    }

    for (int i = 0; i < n_eval;  i++) h_evalx[i]  = (float)eval_x[i];
    for (int j = 0; j < n_train; j++) h_trainx[j] = (float)train_x[j];
    for (int j = 0; j < n_train; j++) h_trainy[j] = (float)train_y[j];

    float *d_evalx = NULL, *d_trainx = NULL, *d_trainy = NULL;
    float *d_result = NULL, *d_deriv = NULL;
    cudaError_t err;

    err = cudaMalloc(&d_evalx,   n_eval  * sizeof(float));
    if (err != cudaSuccess) goto lp1d_err;
    err = cudaMalloc(&d_trainx,  n_train * sizeof(float));
    if (err != cudaSuccess) goto lp1d_err;
    err = cudaMalloc(&d_trainy,  n_train * sizeof(float));
    if (err != cudaSuccess) goto lp1d_err;
    err = cudaMalloc(&d_result,  n_eval  * sizeof(float));
    if (err != cudaSuccess) goto lp1d_err;
    if (nderiv > 0) {
        err = cudaMalloc(&d_deriv, (size_t)nderiv * n_eval * sizeof(float));
        if (err != cudaSuccess) goto lp1d_err;
    }

    err = cudaMemcpy(d_evalx,  h_evalx,  n_eval  * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto lp1d_err;
    err = cudaMemcpy(d_trainx, h_trainx, n_train * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto lp1d_err;
    err = cudaMemcpy(d_trainy, h_trainy, n_train * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto lp1d_err;

    lp_eval_1d_kernel<<<grid_size(n_eval), BLOCK_SIZE>>>(
        d_evalx, d_trainx, d_trainy, n_train, n_eval,
        (float)h, kernel_type, poly,
        d_result, d_deriv, nderiv);

    err = cudaGetLastError();
    if (err != cudaSuccess) goto lp1d_err;
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) goto lp1d_err;

    err = cudaMemcpy(h_result, d_result, n_eval * sizeof(float), cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) goto lp1d_err;
    if (nderiv > 0 && h_deriv) {
        err = cudaMemcpy(h_deriv, d_deriv, (size_t)nderiv * n_eval * sizeof(float), cudaMemcpyDeviceToHost);
        if (err != cudaSuccess) goto lp1d_err;
    }

    for (int i = 0; i < n_eval; i++) result[i] = (double)h_result[i];
    if (nderiv > 0 && derivatives) {
        for (int d = 0; d < nderiv; d++) {
            for (int i = 0; i < n_eval; i++) {
                derivatives[d * n_eval + i] = (double)h_deriv[d * n_eval + i];
            }
        }
    }

    free(h_evalx); free(h_trainx); free(h_trainy); free(h_result); free(h_deriv);
    _cuda_free5(d_evalx, d_trainx, d_trainy, d_result, d_deriv);
    return 0;

lp1d_err:
    free(h_evalx); free(h_trainx); free(h_trainy); free(h_result); free(h_deriv);
    _cuda_free5(d_evalx, d_trainx, d_trainy, d_result, d_deriv);
    return (int)err;
}

int gpu_lp_eval_mv(double *eval_x_flat, double **train_x, double *train_y,
                   int n_train, int n_eval, int dim,
                   double *h, int kernel_type,
                   double *result, double *derivatives, int nderiv,
                   int device_id)
{
    CUDA_CHECK(cudaSetDevice(device_id));

    size_t eval_elems  = (size_t)dim * n_eval;
    size_t train_elems = (size_t)dim * n_train;

    float *h_evalx_f   = (float*)malloc(eval_elems  * sizeof(float));
    float *h_trainx_f  = (float*)malloc(train_elems * sizeof(float));
    float *h_trainy    = (float*)malloc(n_train     * sizeof(float));
    float *h_h_f       = (float*)malloc(dim         * sizeof(float));
    float *h_result    = (float*)malloc(n_eval      * sizeof(float));
    float *h_deriv     = NULL;
    if (nderiv > 0) {
        h_deriv = (float*)malloc((size_t)nderiv * n_eval * sizeof(float));
    }

    if (!h_evalx_f || !h_trainx_f || !h_trainy || !h_h_f || !h_result) {
        free(h_evalx_f); free(h_trainx_f); free(h_trainy); free(h_h_f); free(h_result); free(h_deriv);
        return -100;
    }

    for (int d = 0; d < dim; d++) {
        for (int i = 0; i < n_eval; i++)
            h_evalx_f[d * n_eval + i] = (float)eval_x_flat[d * n_eval + i];
        for (int j = 0; j < n_train; j++)
            h_trainx_f[d * n_train + j] = (float)train_x[d][j];
        h_h_f[d] = (float)h[d];
    }
    for (int j = 0; j < n_train; j++) h_trainy[j] = (float)train_y[j];

    float *d_evalx = NULL, *d_trainx = NULL, *d_trainy = NULL;
    float *d_h = NULL, *d_result = NULL, *d_deriv = NULL;
    cudaError_t err;

    err = cudaMalloc(&d_evalx,   eval_elems  * sizeof(float));
    if (err != cudaSuccess) goto lpmv_err;
    err = cudaMalloc(&d_trainx,  train_elems * sizeof(float));
    if (err != cudaSuccess) goto lpmv_err;
    err = cudaMalloc(&d_trainy,  n_train     * sizeof(float));
    if (err != cudaSuccess) goto lpmv_err;
    err = cudaMalloc(&d_h,       dim         * sizeof(float));
    if (err != cudaSuccess) goto lpmv_err;
    err = cudaMalloc(&d_result,  n_eval      * sizeof(float));
    if (err != cudaSuccess) goto lpmv_err;
    if (nderiv > 0) {
        err = cudaMalloc(&d_deriv, (size_t)nderiv * n_eval * sizeof(float));
        if (err != cudaSuccess) goto lpmv_err;
    }

    err = cudaMemcpy(d_evalx,  h_evalx_f,  eval_elems  * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto lpmv_err;
    err = cudaMemcpy(d_trainx, h_trainx_f, train_elems * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto lpmv_err;
    err = cudaMemcpy(d_trainy, h_trainy,   n_train     * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto lpmv_err;
    err = cudaMemcpy(d_h,      h_h_f,      dim         * sizeof(float), cudaMemcpyHostToDevice);
    if (err != cudaSuccess) goto lpmv_err;

    lp_eval_mv_kernel<<<grid_size(n_eval), BLOCK_SIZE>>>(
        d_evalx, d_trainx, d_trainy, n_train, n_eval, dim,
        d_h, kernel_type, d_result, d_deriv, nderiv);

    err = cudaGetLastError();
    if (err != cudaSuccess) goto lpmv_err;
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) goto lpmv_err;

    err = cudaMemcpy(h_result, d_result, n_eval * sizeof(float), cudaMemcpyDeviceToHost);
    if (err != cudaSuccess) goto lpmv_err;
    if (nderiv > 0 && h_deriv) {
        err = cudaMemcpy(h_deriv, d_deriv, (size_t)nderiv * n_eval * sizeof(float), cudaMemcpyDeviceToHost);
        if (err != cudaSuccess) goto lpmv_err;
    }

    for (int i = 0; i < n_eval; i++) result[i] = (double)h_result[i];
    if (nderiv > 0 && derivatives) {
        for (int d = 0; d < nderiv; d++) {
            for (int i = 0; i < n_eval; i++) {
                derivatives[d * n_eval + i] = (double)h_deriv[d * n_eval + i];
            }
        }
    }

    free(h_evalx_f); free(h_trainx_f); free(h_trainy); free(h_h_f); free(h_result); free(h_deriv);
    _cuda_free5(d_evalx, d_trainx, d_trainy, d_h, d_result);
    if (d_deriv) cudaFree(d_deriv);
    return 0;

lpmv_err:
    free(h_evalx_f); free(h_trainx_f); free(h_trainy); free(h_h_f); free(h_result); free(h_deriv);
    _cuda_free5(d_evalx, d_trainx, d_trainy, d_h, d_result);
    if (d_deriv) cudaFree(d_deriv);
    return (int)err;
}

} /* extern "C" */
