/**
 * nwreg_cuda.h - GPU dispatch interface for nwreg
 *
 * Declares GPU dispatch function prototypes used by nwreg.c when compiled
 * with -DUSE_CUDA. C-compatible (no C++ required).
 */

#ifndef NWREG_CUDA_H
#define NWREG_CUDA_H

#ifdef USE_CUDA

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * GPU NW regression evaluation — 1D.
 */
int gpu_nw_eval_1d(double *x, double *train_x, double *train_y,
                   int n_train, int n_eval,
                   double h, int kernel_type, double *result,
                   int device_id);

/**
 * GPU NW regression evaluation — multivariate (product kernel).
 *
 * x_flat is [dim][n_eval] column-major flat array.
 * train_x is [dim][n_train] (pointer-to-pointer on host), needs flattening.
 */
int gpu_nw_eval_mv(double *x_flat, double **train_x, double *train_y,
                   int n_train, int n_eval, int dim,
                   double *h, int kernel_type, double *result,
                   int device_id);

/**
 * GPU K-fold CV negative MSE score — 1D.
 */
int gpu_cv_mse_1d(double *data_x, double *data_y, int n,
                  double h, int kernel_type, int k,
                  double *score, int device_id);

/**
 * GPU K-fold CV negative MSE score — multivariate.
 */
int gpu_cv_mse_mv(double **data_x, double *data_y, int n, int dim,
                  double *h, int kernel_type, int k,
                  double *score, int device_id);

/**
 * GPU preflight check.
 */
int gpu_preflight_check(int device_id, size_t required_bytes);

#ifdef __cplusplus
}
#endif

#endif /* USE_CUDA */

/* CPU evaluation functions — always available */
#ifdef __cplusplus
extern "C" {
#endif

double nw_eval_1d_cpu(double x, double *train_x, double *train_y,
                      int n_train, double h, int kernel_type);

double nw_eval_mv_cpu(double *x, double **train_x, double *train_y,
                      int n_train, int dim, double *h, int kernel_type);

double cv_mse_1d_cpu(double *data_x, double *data_y, int n,
                     double h, int kernel_type, int k);

double cv_mse_mv_cpu(double **data_x, double *data_y, int n, int dim,
                     double *h, int kernel_type, int k);

#ifdef __cplusplus
}
#endif

#endif /* NWREG_CUDA_H */
