#include "ols_cuda.h"

#include <cublas_v2.h>
#include <cusolverDn.h>
#include <cuda_runtime.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define CUDA_CHECK(call) \
    do { \
        cudaError_t _e = (call); \
        if (_e != cudaSuccess) { \
            return (int)_e; \
        } \
    } while(0)

static int solve_linear_system(cusolverDnHandle_t cusolver, cublasHandle_t cublas,
                                float *A, float *b, int m, int n, int nrhs)
{
    int *d_info = NULL;
    CUDA_CHECK(cudaMalloc(&d_info, sizeof(int)));

    int lwork = 0;
    cusolverStatus_t status = cusolverDnSgetrf_bufferSize(cusolver, m, n, A, m, &lwork);
    if (status != CUSOLVER_STATUS_SUCCESS) {
        cudaFree(d_info);
        return -1;
    }

    float *d_work = NULL;
    int *d_ipiv = NULL;
    CUDA_CHECK(cudaMalloc(&d_work, lwork * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_ipiv, n * sizeof(int)));

    status = cusolverDnSgetrf(cusolver, m, n, A, m, d_work, d_ipiv, d_info);
    if (status != CUSOLVER_STATUS_SUCCESS) {
        cudaFree(d_info); cudaFree(d_work); cudaFree(d_ipiv);
        return -2;
    }

    int h_info = 0;
    CUDA_CHECK(cudaMemcpy(&h_info, d_info, sizeof(int), cudaMemcpyDeviceToHost));
    if (h_info != 0) {
        cudaFree(d_info); cudaFree(d_work); cudaFree(d_ipiv);
        return -3;
    }

    status = cusolverDnSgetrs(cusolver, CUBLAS_OP_N, n, nrhs, A, m, d_ipiv, b, m, d_info);
    if (status != CUSOLVER_STATUS_SUCCESS) {
        cudaFree(d_info); cudaFree(d_work); cudaFree(d_ipiv);
        return -4;
    }

    CUDA_CHECK(cudaMemcpy(&h_info, d_info, sizeof(int), cudaMemcpyDeviceToHost));
    if (h_info != 0) {
        cudaFree(d_info); cudaFree(d_work); cudaFree(d_ipiv);
        return -5;
    }

    cudaFree(d_info); cudaFree(d_work); cudaFree(d_ipiv);
    return 0;
}

int ols_cuda_fit(const float *X_device, const float *y_device,
                 int n, int p, int constant,
                 float *beta_out, float *constant_out)
{
    if (n <= 0 || p < 0) return -10;
    if (constant && n < p + 1) return -11;
    if (!constant && n < p) return -12;

    int p_total = p + (constant ? 1 : 0);
    if (p_total <= 0) return -13;

    cublasHandle_t cublas;
    cusolverDnHandle_t cusolver;
    cublasStatus_t blas_status = cublasCreate(&cublas);
    if (blas_status != CUBLAS_STATUS_SUCCESS) return -20;
    cusolverStatus_t solver_status = cusolverDnCreate(&cusolver);
    if (solver_status != CUSOLVER_STATUS_SUCCESS) {
        cublasDestroy(cublas);
        return -21;
    }

    float *A_aug = NULL;
    float *b_aug = NULL;
    float *XtX = NULL;
    float *Xty = NULL;

    CUDA_CHECK(cudaMalloc(&A_aug, (size_t)n * p_total * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&b_aug, (size_t)n * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&XtX, (size_t)p_total * p_total * sizeof(float)));
    CUDA_CHECK(cudaMalloc(&Xty, (size_t)p_total * sizeof(float)));

    const float alpha = 1.0f;
    const float beta = 0.0f;

    if (constant) {
        float *ones = NULL;
        CUDA_CHECK(cudaMalloc(&ones, (size_t)n * sizeof(float)));
        float one_val = 1.0f;
        cublasSscal(cublas, n, &one_val, ones, 1);
        cudaMemcpy(ones, &one_val, sizeof(float), cudaMemcpyHostToDevice);

        float *host_ones = (float*)malloc(n * sizeof(float));
        for (int i = 0; i < n; i++) host_ones[i] = 1.0f;
        cudaMemcpy(ones, host_ones, n * sizeof(float), cudaMemcpyHostToDevice);
        free(host_ones);

        cublasScopy(cublas, n, ones, 1, A_aug, 1);
        cudaFree(ones);

        for (int j = 0; j < p; j++) {
            cublasScopy(cublas, n, X_device + j * n, 1, A_aug + (j + 1) * n, 1);
        }
    } else {
        for (int j = 0; j < p; j++) {
            cublasScopy(cublas, n, X_device + j * n, 1, A_aug + j * n, 1);
        }
    }

    cublasScopy(cublas, n, (float*)y_device, 1, b_aug, 1);

    cublasSgemm(cublas, CUBLAS_OP_T, CUBLAS_OP_N,
                p_total, p_total, n,
                &alpha, A_aug, n, A_aug, n,
                &beta, XtX, p_total);

    cublasSgemv(cublas, CUBLAS_OP_T,
                n, p_total,
                &alpha, A_aug, n, b_aug, 1,
                &beta, Xty, 1);

    int ret = solve_linear_system(cusolver, cublas, XtX, Xty, p_total, p_total, 1);

    if (ret == 0) {
        if (constant) {
            cudaMemcpy(constant_out, Xty, sizeof(float), cudaMemcpyDeviceToHost);
            if (p > 0) {
                cudaMemcpy(beta_out, Xty + 1, p * sizeof(float), cudaMemcpyDeviceToHost);
            }
        } else {
            if (p > 0) {
                cudaMemcpy(beta_out, Xty, p * sizeof(float), cudaMemcpyDeviceToHost);
            }
        }
    }

    cudaFree(A_aug); cudaFree(b_aug); cudaFree(XtX); cudaFree(Xty);
    cusolverDnDestroy(cusolver);
    cublasDestroy(cublas);

    return ret;
}

__global__ void ols_predict_kernel(const float *X, int n, int p,
                                    float constant, const float *beta,
                                    float *out)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;

    float val = constant;
    for (int j = 0; j < p; j++) {
        val += beta[j] * X[j * n + i];
    }
    out[i] = val;
}

int ols_cuda_predict(const float *X_device, int n, int p,
                     float constant, const float *beta,
                     float *out)
{
    if (n <= 0) return -10;

    int block_size = 256;
    int grid_size = (n + block_size - 1) / block_size;

    ols_predict_kernel<<<grid_size, block_size>>>(
        X_device, n, p, constant, beta, out);

    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) return (int)err;
    err = cudaDeviceSynchronize();
    if (err != cudaSuccess) return (int)err;

    return 0;
}
