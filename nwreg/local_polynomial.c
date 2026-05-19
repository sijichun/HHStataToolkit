/*
 * local_polynomial.c - Local Polynomial Regression for nwreg
 * Designed to be #include'd from nwreg.c.
 * 1D basis: 1, (x-a), (x-a)^2, ..., (x-a)^p
 * MV basis: 1, (x1-a1), ..., (xd-ad)  (poly=1 only)
 * Prediction = beta_0, k-th derivative = k! * beta_k
 */

#define CV_GRID_STEP 0.05

static double factorial_int(int n)
{
    double f = 1.0;
    int i;
    for (i = 2; i <= n; i++) f *= (double)i;
    return f;
}

static double lp_eval_1d(double x, double *train_x, double *train_y,
                         int n_train, double h, int kernel_type, int poly,
                         double *derivatives)
{
    if (poly < 1) return SV_missval;

    kernel_1d_func K = get_kernel_1d(kernel_type);
    double *X = (double*)malloc((size_t)n_train * poly * sizeof(double));
    double *w = (double*)malloc((size_t)n_train * sizeof(double));
    if (!X || !w) {
        free(X); free(w);
        return SV_missval;
    }

    int i, k;
    for (i = 0; i < n_train; i++) {
        double u = (train_x[i] - x) / h;
        w[i] = K(u);
        double dx = train_x[i] - x;
        double power = dx;
        for (k = 0; k < poly; k++) {
            X[k * n_train + i] = power;
            power *= dx;
        }
    }

    ols_result_t *res = wls_fit(X, train_y, w, n_train, poly, 1);

    double pred = SV_missval;
    if (res && res->converged) {
        pred = res->constant;
        if (derivatives) {
            for (k = 0; k < poly; k++) {
                derivatives[k] = factorial_int(k + 1) * res->beta[k];
            }
        }
    }

    free(X); free(w);
    ols_result_free(res);
    return pred;
}

static double lp_eval_mv(double *x, double **train_x, double *train_y,
                         int n_train, int dim, double *h, int kernel_type,
                         double *derivatives)
{
    if (dim < 1) return SV_missval;

    double *X = (double*)malloc((size_t)n_train * dim * sizeof(double));
    double *w = (double*)malloc((size_t)n_train * sizeof(double));
    if (!X || !w) {
        free(X); free(w);
        return SV_missval;
    }

    int i, d;
    for (i = 0; i < n_train; i++) {
        double u[MAX_DIM];
        for (d = 0; d < dim; d++) {
            u[d] = (train_x[d][i] - x[d]) / h[d];
            X[d * n_train + i] = train_x[d][i] - x[d];
        }
        w[i] = kernel_product(u, dim, kernel_type);
    }

    ols_result_t *res = wls_fit(X, train_y, w, n_train, dim, 1);

    double pred = SV_missval;
    if (res && res->converged) {
        pred = res->constant;
        if (derivatives) {
            for (d = 0; d < dim; d++) {
                derivatives[d] = res->beta[d];
            }
        }
    }

    free(X); free(w);
    ols_result_free(res);
    return pred;
}

static double cv_mse_lp_1d(double *data_x, double *data_y, int n, double h,
                           int kernel_type, int k, int poly)
{
    (void)kernel_type;
    double total_sq = 0.0;
    int n_test_total = 0;
    int fold, i;

    for (fold = 0; fold < k; fold++) {
        int test_start = (fold * n) / k;
        int test_end   = ((fold + 1) * n) / k;
        int test_size  = test_end - test_start;
        if (test_size < 1) continue;

        int n_train_f = n - test_size;
        if (n_train_f < poly + 1) continue;

#ifdef _OPENMP
#pragma omp parallel for reduction(+:total_sq, n_test_total)
#endif
        for (i = test_start; i < test_end; i++) {
            double *tx = (double*)malloc((size_t)n_train_f * sizeof(double));
            double *ty = (double*)malloc((size_t)n_train_f * sizeof(double));
            if (!tx || !ty) {
                free(tx); free(ty);
                continue;
            }

            int idx = 0;
            int j;
            for (j = 0; j < n; j++) {
                if (j >= test_start && j < test_end) continue;
                tx[idx] = data_x[j];
                ty[idx] = data_y[j];
                idx++;
            }

            double pred = lp_eval_1d(data_x[i], tx, ty, n_train_f, h,
                                     kernel_type, poly, NULL);
            free(tx); free(ty);

            if (!SF_is_missing(pred)) {
                double resid = data_y[i] - pred;
                total_sq += resid * resid;
                n_test_total++;
            }
        }
    }
    if (n_test_total == 0) return -1e100;
    return -(total_sq / n_test_total);
}

static double cv_mse_lp_mv(double **data_x, double *data_y, int n, int dim,
                           double *h, int kernel_type, int k)
{
    double total_sq = 0.0;
    int n_test_total = 0;
    int fold;

    for (fold = 0; fold < k; fold++) {
        int test_start = (fold * n) / k;
        int test_end   = ((fold + 1) * n) / k;
        int test_size  = test_end - test_start;
        if (test_size < 1) continue;

        int n_train_f = n - test_size;
        if (n_train_f < dim + 1) continue;

#ifdef _OPENMP
#pragma omp parallel for reduction(+:total_sq, n_test_total)
#endif
        for (int i = test_start; i < test_end; i++) {
            double **tx = alloc_double_matrix(dim, n_train_f);
            double *ty = alloc_double_array(n_train_f);
            if (!tx || !ty) {
                if (tx) free_matrix(tx, dim);
                free(ty);
                continue;
            }

            int idx = 0;
            int j;
            for (j = 0; j < n; j++) {
                if (j >= test_start && j < test_end) continue;
                int d;
                for (d = 0; d < dim; d++)
                    tx[d][idx] = data_x[d][j];
                ty[idx] = data_y[j];
                idx++;
            }

            double *x = (double*)malloc((size_t)dim * sizeof(double));
            double pred = SV_missval;
            if (x) {
                int d;
                for (d = 0; d < dim; d++) x[d] = data_x[d][i];
                pred = lp_eval_mv(x, tx, ty, n_train_f, dim, h,
                                  kernel_type, NULL);
                free(x);
            }

            free_matrix(tx, dim);
            free(ty);

            if (!SF_is_missing(pred)) {
                double resid = data_y[i] - pred;
                total_sq += resid * resid;
                n_test_total++;
            }
        }
    }
    if (n_test_total == 0) return -1e100;
    return -(total_sq / n_test_total);
}

static double cv_select_lp_1d(double *data_x, double *data_y, int n,
                              int kernel_type, int k, int ngrids,
                              double ref_h, int poly, int gpu_device)
{
    double grid[201];
    int n_candidates;
    generate_log_grid(ref_h, CV_GRID_STEP, ngrids, grid, &n_candidates);

    (void)gpu_device;

    double best_h = ref_h, best_score = -1e100;
    int i;
    for (i = 0; i < n_candidates; i++) {
        double score = cv_mse_lp_1d(data_x, data_y, n, grid[i],
                                     kernel_type, k, poly);
        if (score > best_score) {
            best_score = score;
            best_h = grid[i];
        }
    }
    return best_h;
}

static void cv_select_lp_mv(double **data_x, double *data_y, int n, int dim,
                            int kernel_type, int k, int ngrids,
                            double *ref_h, double *h_out, int gpu_device)
{
    double grid[201];
    int n_candidates;
    double log_mean = 0.0;
    int d;
    for (d = 0; d < dim; d++) log_mean += log(ref_h[d]);
    log_mean /= dim;
    double ref_scale = exp(log_mean);

    generate_log_grid(ref_scale, CV_GRID_STEP, ngrids, grid, &n_candidates);

    (void)gpu_device;

    double best_score = -1e100;
    double *cand_h = (double*)malloc(dim * sizeof(double));
    if (!cand_h) {
        for (d = 0; d < dim; d++) h_out[d] = ref_h[d];
        return;
    }

    int i;
    for (i = 0; i < n_candidates; i++) {
        double scale = grid[i] / ref_scale;
        for (d = 0; d < dim; d++) cand_h[d] = ref_h[d] * scale;
        double score = cv_mse_lp_mv(data_x, data_y, n, dim, cand_h,
                                     kernel_type, k);
        if (score > best_score) {
            best_score = score;
            for (d = 0; d < dim; d++) h_out[d] = cand_h[d];
        }
    }
    free(cand_h);
}

static void compute_bw_cv_lp(double **train_x, double *train_y, int n_train,
                             int dim, int bandwidth_rule, double manual_h,
                             int cv_folds, int cv_grids, int kernel_type,
                             double *h, int poly, int gpu_device)
{
    if (bandwidth_rule == BANDWIDTH_CV) {
        if (dim == 1) {
            double ref_h = silverman_bandwidth(train_x[0], n_train);
            h[0] = cv_select_lp_1d(train_x[0], train_y, n_train, kernel_type,
                                    cv_folds, cv_grids, ref_h, poly, gpu_device);
        } else {
            double *ref_h = (double*)malloc(dim * sizeof(double));
            if (!ref_h) {
                silverman_bandwidth_mv(train_x, n_train, dim, h);
                return;
            }
            silverman_bandwidth_mv(train_x, n_train, dim, ref_h);
            cv_select_lp_mv(train_x, train_y, n_train, dim, kernel_type,
                            cv_folds, cv_grids, ref_h, h, gpu_device);
            free(ref_h);
        }
    } else {
        compute_bw(train_x, n_train, dim, bandwidth_rule, manual_h, h);
    }
}

static int eval_lp_batch(double **reg_data, int dim,
                         double **train_x, double *train_y,
                         int n_train, double *h, int kernel_type, int poly,
                         int *obs_indices, int n_eval,
                         double *result, double **deriv_results, int nderiv,
                         int gpu_device)
{
#ifdef USE_CUDA
    if (gpu_device >= 0) {
        if (dim == 1) {
            double *deriv_flat = NULL;
            if (nderiv > 0 && deriv_results) {
                deriv_flat = (double*)malloc((size_t)nderiv * n_eval * sizeof(double));
                if (!deriv_flat) return 1;
            }
            int ret = gpu_lp_eval_1d(reg_data[0], train_x[0], train_y,
                                      n_train, n_eval, h[0], kernel_type, poly,
                                      result, deriv_flat, nderiv, gpu_device);
            if (ret != 0) {
                free(deriv_flat);
                return ret;
            }
            if (nderiv > 0 && deriv_results && deriv_flat) {
                int k;
                for (k = 0; k < nderiv; k++) {
                    int i;
                    for (i = 0; i < n_eval; i++) {
                        int j = obs_indices[i];
                        if (k < poly) {
                            deriv_results[k][j] = deriv_flat[k * n_eval + i];
                        } else {
                            deriv_results[k][j] = SV_missval;
                        }
                    }
                }
                free(deriv_flat);
            }
            return 0;
        } else {
            double *x_batch = (double*)malloc((size_t)dim * n_eval * sizeof(double));
            if (!x_batch) return 1;
            int i;
            for (i = 0; i < n_eval; i++) {
                int j = obs_indices[i];
                int d;
                for (d = 0; d < dim; d++) x_batch[d * n_eval + i] = reg_data[d][j];
            }
            double *deriv_flat = NULL;
            if (nderiv > 0 && deriv_results) {
                deriv_flat = (double*)malloc((size_t)nderiv * n_eval * sizeof(double));
                if (!deriv_flat) { free(x_batch); return 1; }
            }
            int ret = gpu_lp_eval_mv(x_batch, train_x, train_y,
                                      n_train, n_eval, dim, h, kernel_type,
                                      result, deriv_flat, nderiv, gpu_device);
            if (ret != 0) {
                free(x_batch); free(deriv_flat);
                return ret;
            }
            if (nderiv > 0 && deriv_results && deriv_flat) {
                int d;
                for (d = 0; d < nderiv; d++) {
                    int i;
                    for (i = 0; i < n_eval; i++) {
                        int j = obs_indices[i];
                        if (d < dim) {
                            deriv_results[d][j] = deriv_flat[d * n_eval + i];
                        } else {
                            deriv_results[d][j] = SV_missval;
                        }
                    }
                }
                free(deriv_flat);
            }
            free(x_batch);
            return 0;
        }
    }
#else
    (void)gpu_device;
#endif

    int i;

#ifdef _OPENMP
#pragma omp parallel for
#endif
    for (i = 0; i < n_eval; i++) {
        int j = obs_indices[i];
        if (dim == 1) {
            double deriv_buf[10];
            double *deriv_ptr = (nderiv > 0) ? deriv_buf : NULL;
            result[j] = lp_eval_1d(reg_data[0][j], train_x[0], train_y,
                                   n_train, h[0], kernel_type, poly, deriv_ptr);
            if (nderiv > 0 && deriv_results) {
                int k;
                int max_k = (nderiv < poly) ? nderiv : poly;
                for (k = 0; k < max_k; k++) {
                    deriv_results[k][j] = deriv_ptr[k];
                }
                for (k = max_k; k < nderiv; k++) {
                    deriv_results[k][j] = SV_missval;
                }
            }
        } else {
            double deriv_buf[MAX_DIM];
            double *x = (double*)malloc(dim * sizeof(double));
            if (!x) continue;
            int d;
            for (d = 0; d < dim; d++) x[d] = reg_data[d][j];
            double *deriv_ptr = (nderiv > 0) ? deriv_buf : NULL;
            result[j] = lp_eval_mv(x, train_x, train_y, n_train, dim, h,
                                   kernel_type, deriv_ptr);
            if (nderiv > 0 && deriv_results) {
                int d;
                int max_d = (nderiv < dim) ? nderiv : dim;
                for (d = 0; d < max_d; d++) {
                    deriv_results[d][j] = deriv_ptr[d];
                }
                for (d = max_d; d < nderiv; d++) {
                    deriv_results[d][j] = SV_missval;
                }
            }
            free(x);
        }
    }
    return 0;
}
