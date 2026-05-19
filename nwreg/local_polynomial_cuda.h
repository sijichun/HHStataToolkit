#ifndef LOCAL_POLYNOMIAL_CUDA_H
#define LOCAL_POLYNOMIAL_CUDA_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * gpu_lp_eval_1d - GPU-accelerated 1D local polynomial regression evaluation.
 *
 * @param eval_x      evaluation points (length n_eval)
 * @param train_x     training regressors (length n_train)
 * @param train_y     training responses (length n_train)
 * @param n_train     number of training observations
 * @param n_eval      number of evaluation points
 * @param h           bandwidth
 * @param kernel_type kernel selector
 * @param poly        polynomial degree (>= 1)
 * @param result      output predictions (length n_eval)
 * @param derivatives output derivatives, column-major [nderiv][n_eval] (or NULL)
 * @param nderiv      number of derivative outputs (0 if no derivatives)
 * @param device_id   CUDA device ID
 * @return            0 on success, non-zero on error
 */
int gpu_lp_eval_1d(double *eval_x, double *train_x, double *train_y,
                   int n_train, int n_eval,
                   double h, int kernel_type, int poly,
                   double *result, double *derivatives, int nderiv,
                   int device_id);

/**
 * gpu_lp_eval_mv - GPU-accelerated multivariate local linear regression.
 *
 * @param eval_x_flat evaluation points, column-major [dim][n_eval]
 * @param train_x     training regressors, column-major [dim][n_train]
 * @param train_y     training responses (length n_train)
 * @param n_train     number of training observations
 * @param n_eval      number of evaluation points
 * @param dim         number of regressors
 * @param h           bandwidth vector (length dim)
 * @param kernel_type kernel selector
 * @param result      output predictions (length n_eval)
 * @param derivatives output partial derivatives, column-major [nderiv][n_eval] (or NULL)
 * @param nderiv      number of derivative outputs (0 if no derivatives)
 * @param device_id   CUDA device ID
 * @return            0 on success, non-zero on error
 */
int gpu_lp_eval_mv(double *eval_x_flat, double **train_x, double *train_y,
                   int n_train, int n_eval, int dim,
                   double *h, int kernel_type,
                   double *result, double *derivatives, int nderiv,
                   int device_id);

#ifdef __cplusplus
}
#endif

#endif
