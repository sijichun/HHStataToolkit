#ifndef OLS_CUDA_H
#define OLS_CUDA_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * OLS fit on GPU data.
 *
 * Assumes X and y are already in device (GPU) memory.
 * Writes results to device memory beta_out and constant_out.
 * Caller must allocate and free all device memory.
 *
 * @param X_device      Regressor matrix [n x p] in device memory, column-major
 * @param y_device      Response vector [n] in device memory
 * @param n             Number of observations
 * @param p             Number of regressors (excluding constant)
 * @param constant      1 = include intercept, 0 = no intercept
 * @param beta_out      Output: coefficients [p] in device memory (valid if p > 0)
 * @param constant_out  Output: intercept scalar in device memory (valid if constant=1)
 * @return 0 on success, non-zero on error
 *
 * All data is float (single precision).
 */
int ols_cuda_fit(const float *X_device, const float *y_device,
                 int n, int p, int constant,
                 float *beta_out, float *constant_out);

/**
 * OLS prediction on GPU data.
 *
 * Assumes X and beta are in device memory.
 * Writes predictions to device memory out.
 *
 * @param X_device   Regressor matrix [n x p] in device memory, column-major
 * @param n          Number of observations
 * @param p          Number of regressors
 * @param constant   Intercept value (0.0 if no intercept)
 * @param beta       Coefficients [p] in device memory
 * @param out        Output predictions [n] in device memory
 * @return 0 on success, non-zero on error
 */
int ols_cuda_predict(const float *X_device, int n, int p,
                     float constant, const float *beta,
                     float *out);

#ifdef __cplusplus
}
#endif

#endif
