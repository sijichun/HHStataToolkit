/**
 * kdensity2_cuda.h - GPU dispatch interface for kdensity2
 *
 * This header declares the GPU dispatch function prototypes used by kdensity2.c
 * when compiled with -DUSE_CUDA. The actual implementations live in T2/T5.
 *
 * C-compatible (no C++ required). Include this file inside an #ifdef USE_CUDA
 * guard in kdensity2.c.
 *
 * NOTE: GPU internally uses float for performance (~2x memory bandwidth,
 * 2x peak FLOPs on most NVIDIA GPUs vs double). Double-to-float conversion
 * happens inside the host dispatch functions at the host/device boundary.
 * The public API below stays double* for compatibility with kdensity2.c.
 */

#ifndef KDENSITY2_CUDA_H
#define KDENSITY2_CUDA_H

#ifdef USE_CUDA

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * GPU kernel density evaluation — 1D.
 *
 * @param x          Evaluation points [n_eval]
 * @param train      Training data [n_train]
 * @param n_train    Number of training observations
 * @param n_eval     Number of evaluation points
 * @param h          Bandwidth
 * @param kernel_type  Kernel selector (KERNEL_* constants from utils.h)
 * @param result     Output array [n_eval] — caller allocates
 * @param device_id  CUDA device index (0-based)
 * @return 0 on success, non-zero on error
 */
int gpu_kde_eval_1d(double *x, double *train, int n_train, int n_eval,
                    double h, int kernel_type, double *result, int device_id);

/**
 * GPU kernel density evaluation — multivariate (product kernel).
 *
 * @param x          Evaluation points [dim][n_eval]
 * @param train      Training data [dim][n_train]
 * @param n_train    Number of training observations
 * @param n_eval     Number of evaluation points
 * @param dim        Number of dimensions
 * @param h          Bandwidth vector [dim]
 * @param kernel_type  Kernel selector
 * @param result     Output array [n_eval] — caller allocates
 * @param device_id  CUDA device index
 * @return 0 on success, non-zero on error
 */
int gpu_kde_eval_mv(double *x, double **train, int n_train, int n_eval,
                    int dim, double *h, int kernel_type, double *result,
                    int device_id);

/**
 * GPU K-fold CV log-likelihood score — 1D.
 *
 * @param data        Training data [n]
 * @param n           Number of observations
 * @param h           Candidate bandwidth
 * @param kernel_type Kernel selector
 * @param k           Number of CV folds
 * @param score       Output scalar (log-likelihood per observation)
 * @param device_id   CUDA device index
 * @return 0 on success, non-zero on error
 */
int gpu_cv_score_1d(double *data, int n, double h, int kernel_type,
                    int k, double *score, int device_id);

/**
 * GPU K-fold CV log-likelihood score — multivariate.
 *
 * @param data        Training data [dim][n]
 * @param n           Number of observations
 * @param dim         Number of dimensions
 * @param h           Bandwidth vector [dim]
 * @param kernel_type Kernel selector
 * @param k           Number of CV folds
 * @param score       Output scalar
 * @param device_id   CUDA device index
 * @return 0 on success, non-zero on error
 */
int gpu_cv_score_mv(double **data, int n, int dim, double *h, int kernel_type,
                    int k, double *score, int device_id);

/**
 * Check whether the requested device has enough free memory.
 *
 * @param device_id      CUDA device index
 * @param required_bytes Minimum free bytes required
 * @return 0 if GPU is ready, non-zero if check fails (fall back to CPU)
 */
int gpu_preflight_check(int device_id, size_t required_bytes);

#ifdef __cplusplus
}
#endif

#endif /* USE_CUDA */

/* ============================================================================
 * CPU evaluation functions — declared here for external use by other
 * translation units (e.g. tests, csadensity). Always available.
 * ============================================================================ */

#ifdef __cplusplus
extern "C" {
#endif

double kde_eval_1d_cpu(double x, double *train_data, int n_train,
                       double h, int kernel_type);

double kde_eval_mv_cpu(double *x, double **train_data, int n_train,
                       int dim, double *h, int kernel_type);

double cv_score_1d_cpu(double *data, int n, double h,
                       int kernel_type, int k);

double cv_score_mv_cpu(double **data, int n, int dim, double *h,
                       int kernel_type, int k);

#ifdef __cplusplus
}
#endif

#endif /* KDENSITY2_CUDA_H */
