/**
 * nwreg.c - Nadaraya-Watson Kernel Regression Plugin for Stata
 *
 * Features:
 *   - Evaluates NW conditional mean estimate at each observation (no grid)
 *   - Supports target split: target=0 = training set, target=1 = test set
 *   - Supports multi-dimensional grouped estimation
 *   - Multivariate regressors with product kernel
 *   - minobs(N): skip groups with fewer than N observations
 *   - Bandwidth selection: silverman, scott, manual, or CV (MSE-based)
 *   - Uses shared utils for kernels, bandwidth, data I/O
 */

#include "stplugin.h"
#include "utils.h"

/* ============================================================================
 * Nadaraya-Watson Estimator
 * ============================================================================ */

/**
 * nw_eval_1d - Evaluate NW estimate at a single 1D point x.
 *
 * Returns Σ K_h(x - x_i) * y_i / Σ K_h(x - x_i) over training set.
 * Returns SV_missval if denominator is zero.
 */
static double nw_eval_1d(double x, double *train_x, double *train_y,
                          int n_train, double h, int kernel_type)
{
    kernel_1d_func K = get_kernel_1d(kernel_type);
    double num = 0.0, den = 0.0;
    int i;
    for (i = 0; i < n_train; i++) {
        double w = K((x - train_x[i]) / h);
        num += w * train_y[i];
        den += w;
    }
    if (den == 0.0) return SV_missval;
    return num / den;
}

/**
 * nw_eval_mv - Evaluate NW estimate at a single multivariate point x[dim].
 *
 * Uses product kernel K_h(x) = Π_d K((x_d - x_i_d) / h_d).
 * Returns SV_missval if denominator is zero.
 */
static double nw_eval_mv(double *x, double **train_x, double *train_y,
                          int n_train, int dim, double *h, int kernel_type)
{
    double num = 0.0, den = 0.0;
    int i;

    for (i = 0; i < n_train; i++) {
        int d;
        double u[MAX_DIM];
        for (d = 0; d < dim; d++)
            u[d] = (x[d] - train_x[d][i]) / h[d];
        double w = kernel_product(u, dim, kernel_type);
        num += w * train_y[i];
        den += w;
    }

    if (den == 0.0) return SV_missval;
    return num / den;
}

/* ============================================================================
 * Standard Error Calculation
 * ============================================================================
 *
 * Three se_type options:
 *   0 = full-sample residuals (fast, slight downward bias in finite samples)
 *   1 = leave-one-out residuals (unbiased, 2x compute)
 *   2 = leverage-corrected residuals (HC3-style, almost no extra compute)
 *
 * Core formula (heteroskedasticity-robust local variance):
 *   SE(x)^2 = sum_i w_i^2 * e_i^2 / (sum_i w_i)^2
 * where w_i = K_h(x - X_i) and e_i is the chosen residual type.
 */

static double kernel_at_zero(int kernel_type)
{
    switch (kernel_type) {
        case KERNEL_GAUSSIAN:     return 1.0 / sqrt(2.0 * M_PI);
        case KERNEL_EPANECHNIKOV: return 0.75;
        case KERNEL_UNIFORM:      return 0.5;
        case KERNEL_TRIWEIGHT:    return 35.0 / 32.0;
        case KERNEL_COSINE:       return M_PI / 4.0;
        default:                  return 1.0 / sqrt(2.0 * M_PI);
    }
}

static void compute_se_residuals_1d(double *train_x, double *train_y,
                                     int n_train, double h, int kernel_type,
                                     int se_type, double *se_resid)
{
    kernel_1d_func K = get_kernel_1d(kernel_type);
    double K0 = kernel_at_zero(kernel_type);
    int i;

    for (i = 0; i < n_train; i++) {
        double num = 0.0, den = 0.0;
        int j;
        for (j = 0; j < n_train; j++) {
            double w = K((train_x[i] - train_x[j]) / h);
            num += w * train_y[j];
            den += w;
        }
        if (den == 0.0) {
            se_resid[i] = 0.0;
            continue;
        }
        double pred = num / den;
        double raw_resid = train_y[i] - pred;

        if (se_type == 0) {
            se_resid[i] = raw_resid;
        } else if (se_type == 1) {
            double den_loo = den - K0;
            if (den_loo <= 0.0) {
                se_resid[i] = raw_resid;
            } else {
                double num_loo = num - K0 * train_y[i];
                double pred_loo = num_loo / den_loo;
                se_resid[i] = train_y[i] - pred_loo;
            }
        } else {
            double leverage = K0 / den;
            double adj = 1.0 - leverage;
            if (adj > 1e-12) {
                se_resid[i] = raw_resid / adj;
            } else {
                se_resid[i] = raw_resid;
            }
        }
    }
}

static void compute_se_residuals_mv(double **train_x, double *train_y,
                                     int n_train, int dim, double *h,
                                     int kernel_type, int se_type,
                                     double *se_resid)
{
    double K0 = kernel_at_zero(kernel_type);
    double K0_prod = pow(K0, dim);
    int i;

    for (i = 0; i < n_train; i++) {
        double num = 0.0, den = 0.0;
        int j;
        for (j = 0; j < n_train; j++) {
            int d;
            double u[MAX_DIM];
            for (d = 0; d < dim; d++)
                u[d] = (train_x[d][i] - train_x[d][j]) / h[d];
            double w = kernel_product(u, dim, kernel_type);
            num += w * train_y[j];
            den += w;
        }
        if (den == 0.0) {
            se_resid[i] = 0.0;
            continue;
        }
        double pred = num / den;
        double raw_resid = train_y[i] - pred;

        if (se_type == 0) {
            se_resid[i] = raw_resid;
        } else if (se_type == 1) {
            double den_loo = den - K0_prod;
            if (den_loo <= 0.0) {
                se_resid[i] = raw_resid;
            } else {
                double num_loo = num - K0_prod * train_y[i];
                double pred_loo = num_loo / den_loo;
                se_resid[i] = train_y[i] - pred_loo;
            }
        } else {
            double leverage = K0_prod / den;
            double adj = 1.0 - leverage;
            if (adj > 1e-12) {
                se_resid[i] = raw_resid / adj;
            } else {
                se_resid[i] = raw_resid;
            }
        }
    }
}

static double nw_eval_1d_with_se(double x, double *train_x, double *train_y,
                                  double *se_resid, int n_train, double h,
                                  int kernel_type, double *se)
{
    kernel_1d_func K = get_kernel_1d(kernel_type);
    double num = 0.0, den = 0.0, se_num = 0.0;
    int i;
    for (i = 0; i < n_train; i++) {
        double w = K((x - train_x[i]) / h);
        num += w * train_y[i];
        den += w;
        se_num += w * w * se_resid[i] * se_resid[i];
    }
    if (den == 0.0) {
        *se = SV_missval;
        return SV_missval;
    }
    *se = sqrt(se_num) / den;
    return num / den;
}

static double nw_eval_mv_with_se(double *x, double **train_x, double *train_y,
                                  double *se_resid, int n_train, int dim,
                                  double *h, int kernel_type, double *se)
{
    double num = 0.0, den = 0.0, se_num = 0.0;
    int i;

    for (i = 0; i < n_train; i++) {
        int d;
        double u[MAX_DIM];
        for (d = 0; d < dim; d++)
            u[d] = (x[d] - train_x[d][i]) / h[d];
        double w = kernel_product(u, dim, kernel_type);
        num += w * train_y[i];
        den += w;
        se_num += w * w * se_resid[i] * se_resid[i];
    }

    if (den == 0.0) {
        *se = SV_missval;
        return SV_missval;
    }
    *se = sqrt(se_num) / den;
    return num / den;
}

/* ============================================================================
 * Bandwidth Computation (wraps utils, same pattern as kdensity2)
 * ============================================================================ */

static void compute_bw(double **train_x, int n_train, int dim,
                        int bandwidth_rule, double manual_h, double *h)
{
    int d;
    if (dim == 1) {
        if (bandwidth_rule == BANDWIDTH_SILVERMAN)
            h[0] = silverman_bandwidth(train_x[0], n_train);
        else if (bandwidth_rule == BANDWIDTH_SCOTT)
            h[0] = scott_bandwidth(train_x[0], n_train);
        else
            h[0] = manual_h;
    } else {
        if (bandwidth_rule == BANDWIDTH_SILVERMAN)
            silverman_bandwidth_mv(train_x, n_train, dim, h);
        else if (bandwidth_rule == BANDWIDTH_SCOTT)
            scott_bandwidth_mv(train_x, n_train, dim, h);
        else
            for (d = 0; d < dim; d++) h[d] = manual_h;
    }
}

/* ============================================================================
 * Cross-Validation for Bandwidth Selection (regression MSE)
 * ============================================================================ */

#define CV_GRID_STEP 0.05

/**
 * cv_mse_1d - K-fold CV negative MSE for 1D NW regression.
 *
 * Returns -MSE so that maximising the score = minimising MSE,
 * consistent with the kdensity2 convention of "larger = better".
 */
static double cv_mse_1d(double *data_x, double *data_y, int n, double h,
                         int kernel_type, int k)
{
    kernel_1d_func K = get_kernel_1d(kernel_type);
    double total_sq = 0.0;
    int n_test_total = 0;
    int fold, i;

    for (fold = 0; fold < k; fold++) {
        int test_start = (fold * n) / k;
        int test_end   = ((fold + 1) * n) / k;
        int test_size  = test_end - test_start;
        if (test_size < 1) continue;

#ifdef _OPENMP
#pragma omp parallel for reduction(+:total_sq, n_test_total)
#endif
        for (i = test_start; i < test_end; i++) {
            double num = 0.0, den = 0.0;
            int j;
            for (j = 0; j < n; j++) {
                if (j >= test_start && j < test_end) continue;
                double w = K((data_x[i] - data_x[j]) / h);
                num += w * data_y[j];
                den += w;
            }
            if (den == 0.0) continue;
            double resid = data_y[i] - num / den;
            total_sq += resid * resid;
            n_test_total++;
        }
    }
    if (n_test_total == 0) return -1e100;
    return -(total_sq / n_test_total);
}

/**
 * cv_mse_mv - K-fold CV negative MSE for multivariate NW regression.
 */
static double cv_mse_mv(double **data_x, double *data_y, int n, int dim,
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

#ifdef _OPENMP
#pragma omp parallel for reduction(+:total_sq, n_test_total)
#endif
        for (int i = test_start; i < test_end; i++) {
            double num = 0.0, den = 0.0;
            int j, d;
            double u[MAX_DIM];
            for (j = 0; j < n; j++) {
                if (j >= test_start && j < test_end) continue;
                for (d = 0; d < dim; d++)
                    u[d] = (data_x[d][i] - data_x[d][j]) / h[d];
                double w = kernel_product(u, dim, kernel_type);
                num += w * data_y[j];
                den += w;
            }
            if (den == 0.0) continue;
            double resid = data_y[i] - num / den;
            total_sq += resid * resid;
            n_test_total++;
        }
    }
    if (n_test_total == 0) return -1e100;
    return -(total_sq / n_test_total);
}

static double cv_select_1d(double *data_x, double *data_y, int n,
                            int kernel_type, int k, int ngrids, double ref_h)
{
    double grid[201];
    int n_candidates;
    generate_log_grid(ref_h, CV_GRID_STEP, ngrids, grid, &n_candidates);

    double best_h = ref_h, best_score = -1e100;
    int i;
    for (i = 0; i < n_candidates; i++) {
        double score = cv_mse_1d(data_x, data_y, n, grid[i], kernel_type, k);
        if (score > best_score) {
            best_score = score;
            best_h = grid[i];
        }
    }
    return best_h;
}

static void cv_select_mv(double **data_x, double *data_y, int n, int dim,
                          int kernel_type, int k, int ngrids,
                          double *ref_h, double *h_out)
{
    double grid[201];
    int n_candidates;
    double log_mean = 0.0;
    int d;
    for (d = 0; d < dim; d++) log_mean += log(ref_h[d]);
    log_mean /= dim;
    double ref_scale = exp(log_mean);

    generate_log_grid(ref_scale, CV_GRID_STEP, ngrids, grid, &n_candidates);

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
        double score = cv_mse_mv(data_x, data_y, n, dim, cand_h, kernel_type, k);
        if (score > best_score) {
            best_score = score;
            for (d = 0; d < dim; d++) h_out[d] = cand_h[d];
        }
    }
    free(cand_h);
}

/**
 * compute_bw_cv - Full bandwidth selector including CV path.
 *
 * Requires access to both regressors (train_x) AND response (train_y) for CV.
 */
static void compute_bw_cv(double **train_x, double *train_y, int n_train,
                            int dim, int bandwidth_rule, double manual_h,
                            int cv_folds, int cv_grids, int kernel_type,
                            double *h)
{
    if (bandwidth_rule == BANDWIDTH_CV) {
        if (dim == 1) {
            double ref_h = silverman_bandwidth(train_x[0], n_train);
            h[0] = cv_select_1d(train_x[0], train_y, n_train, kernel_type,
                                 cv_folds, cv_grids, ref_h);
        } else {
            double *ref_h = (double*)malloc(dim * sizeof(double));
            if (!ref_h) {
                silverman_bandwidth_mv(train_x, n_train, dim, h);
                return;
            }
            silverman_bandwidth_mv(train_x, n_train, dim, ref_h);
            cv_select_mv(train_x, train_y, n_train, dim, kernel_type,
                          cv_folds, cv_grids, ref_h, h);
            free(ref_h);
        }
    } else {
        compute_bw(train_x, n_train, dim, bandwidth_rule, manual_h, h);
    }
}

/* ============================================================================
 * Group Handling (identical pattern to kdensity2)
 * ============================================================================ */

#define MAX_GROUPS 1000

typedef struct {
    double **values;
    int count;
    int ngroup;
} unique_groups_t;

static unique_groups_t* init_unique_groups(int ngroup)
{
    unique_groups_t *ug = (unique_groups_t*)malloc(sizeof(unique_groups_t));
    if (!ug) return NULL;
    ug->values = (double**)malloc(MAX_GROUPS * sizeof(double*));
    if (!ug->values) { free(ug); return NULL; }
    int i;
    for (i = 0; i < MAX_GROUPS; i++) {
        ug->values[i] = (double*)malloc(ngroup * sizeof(double));
        if (!ug->values[i]) {
            int j;
            for (j = 0; j < i; j++) free(ug->values[j]);
            free(ug->values); free(ug);
            return NULL;
        }
    }
    ug->count = 0;
    ug->ngroup = ngroup;
    return ug;
}

static void free_unique_groups(unique_groups_t *ug)
{
    if (!ug) return;
    int i;
    for (i = 0; i < MAX_GROUPS; i++) {
        if (ug->values[i]) free(ug->values[i]);
    }
    free(ug->values);
    free(ug);
}

static int match_group_combo(double **group, int ngroup, int obs_idx,
                              double *combo)
{
    int g;
    for (g = 0; g < ngroup; g++) {
        if (fabs(group[g][obs_idx] - combo[g]) >= 1e-9) return 0;
    }
    return 1;
}

static void collect_unique_groups(double **group, int n_obs, int ngroup,
                                   unique_groups_t *out)
{
    out->count = 0;
    int i, j;
    for (i = 0; i < n_obs; i++) {
        int found = 0;
        for (j = 0; j < out->count; j++) {
            if (match_group_combo(group, ngroup, i, out->values[j])) {
                found = 1;
                break;
            }
        }
        if (!found && out->count < MAX_GROUPS) {
            int g;
            for (g = 0; g < ngroup; g++)
                out->values[out->count][g] = group[g][i];
            out->count++;
        }
    }
}

/* ============================================================================
 * Main Plugin Entry Point
 * ============================================================================ */

STDLL stata_call(int argc, char *argv[])
{
    UTILS_OMP_SET_NTHREADS();

    /* ---- Default parameter values ---- */
    int kernel_type    = KERNEL_GAUSSIAN;
    int bandwidth_rule = BANDWIDTH_SILVERMAN;
    double manual_h    = -1.0;
    int cv_folds       = 10;
    int cv_grids       = 10;

    int nreg    = -1;
    int ntarget = 0;
    int ngroup  = 0;
    int nse     = 0;
    int se_type = 2;
    int minobs  = 0;

    /* ---- Parse argv ---- */
    int i;
    char buf[64];
    for (i = 0; i < argc; i++) {
        char *arg = argv[i];

        if (extract_option_value(arg, "kernel", buf, sizeof(buf))) {
            kernel_type = parse_kernel_type(buf);
        }
        else if (extract_option_value(arg, "bw", buf, sizeof(buf))) {
            if (strcmp(buf, "cv") == 0) {
                bandwidth_rule = BANDWIDTH_CV;
            } else if (strcmp(buf, "silverman") == 0 || strcmp(buf, "scott") == 0) {
                bandwidth_rule = parse_bandwidth_rule(buf);
            } else {
                bandwidth_rule = BANDWIDTH_MANUAL;
                manual_h = atof(buf);
                if (manual_h <= 0) {
                    SF_error("Error: Bandwidth must be positive\n");
                    return 1;
                }
            }
        }
        else if (extract_option_value(arg, "nreg", buf, sizeof(buf))) {
            nreg = atoi(buf);
        }
        else if (extract_option_value(arg, "ntarget", buf, sizeof(buf))) {
            ntarget = atoi(buf);
        }
        else if (extract_option_value(arg, "ngroup", buf, sizeof(buf))) {
            ngroup = atoi(buf);
        }
        else if (extract_option_value(arg, "nse", buf, sizeof(buf))) {
            nse = atoi(buf);
        }
        else if (extract_option_value(arg, "se_type", buf, sizeof(buf))) {
            se_type = atoi(buf);
            if (se_type < 0 || se_type > 2) se_type = 2;
        }
        else if (extract_option_value(arg, "minobs", buf, sizeof(buf))) {
            minobs = atoi(buf);
            if (minobs < 0) minobs = 0;
        }
        else if (extract_option_value(arg, "nfolds", buf, sizeof(buf))) {
            cv_folds = atoi(buf);
            if (cv_folds < 2) cv_folds = 2;
        }
        else if (extract_option_value(arg, "ngrids", buf, sizeof(buf))) {
            cv_grids = atoi(buf);
            if (cv_grids < 2) cv_grids = 2;
        }
    }

    ST_int n_obs = SF_nobs();

    /* Default nreg to 1 if not supplied */
    if (nreg < 0) nreg = 1;
    if (nreg < 1) {
        SF_error("Error: nreg must be >= 1\n");
        return 1;
    }

    int dim = nreg;

    /*
     * Variable layout (1-based Stata indices):
     *   1 .. nreg                          regressors (X)
     *   nreg+1                             dependent variable (Y)
     *   nreg+2 .. nreg+1+ntarget          target variable (0=train,1=test)
     *   nreg+2+ntarget .. nreg+1+ntarget+ngroup  group variables
     *   nreg+2+ntarget+ngroup              output (predicted y)
     *   nreg+3+ntarget+ngroup              SE output (if nse>0)
     *   nreg+3+ntarget+ngroup+nse          touse
     */
    int idx_y            = nreg + 1;
    int idx_target_start = nreg + 2;                          /* only used if ntarget > 0 */
    int idx_group_start  = nreg + 2 + ntarget;               /* first group var */
    int idx_result       = nreg + 2 + ntarget + ngroup;
    int idx_se           = (nse > 0) ? (nreg + 3 + ntarget + ngroup) : -1;
    int idx_touse        = nreg + 3 + ntarget + ngroup + nse;

    if (n_obs < 2) {
        SF_error("Error: Need at least 2 observations\n");
        return 1;
    }

    /* ---- Allocate data arrays ---- */
    double **reg_data = alloc_double_matrix(dim, n_obs);   /* regressors X */
    double *y_data    = alloc_double_array(n_obs);          /* response Y */
    double *target    = (ntarget > 0) ? alloc_double_array(n_obs) : NULL;
    double **group    = (ngroup  > 0) ? alloc_double_matrix(ngroup, n_obs) : NULL;
    double *result    = alloc_double_array(n_obs);
    double *se_result = (nse > 0) ? alloc_double_array(n_obs) : NULL;
    int    *in_if     = (int*)malloc(n_obs * sizeof(int));

    if (!reg_data || !y_data || !result || !in_if ||
        (ntarget > 0 && !target) || (ngroup > 0 && !group) ||
        (nse > 0 && !se_result)) {
        SF_error("Error: Memory allocation failed\n");
        free(in_if);
        free_matrix(reg_data, dim);
        free(y_data);
        free(target);
        if (group) free_matrix(group, ngroup);
        free(result);
        free(se_result);
        return 1;
    }

    /* ---- Initialise result and SE to Stata missing ---- */
    int j;
    for (j = 0; j < n_obs; j++) {
        result[j] = SV_missval;
        if (se_result) se_result[j] = SV_missval;
    }

    /* ---- Read touse ---- */
    int n_eff = 0;
    for (j = 1; j <= n_obs; j++) {
        ST_double tval;
        if (SF_vdata(idx_touse, j, &tval) != 0) tval = 0.0;
        in_if[j - 1] = (tval == 1.0) ? 1 : 0;
        if (in_if[j - 1]) n_eff++;
    }
    if (n_eff < 2) {
        SF_error("Error: Need at least 2 observations in if/in sample\n");
        free(in_if);
        free_matrix(reg_data, dim);
        free(y_data);
        free(target);
        if (group) free_matrix(group, ngroup);
        free(result);
        free(se_result);
        return 1;
    }

    /* ---- Read data ---- */
    for (j = 1; j <= n_obs; j++) {
        int d;
        for (d = 0; d < dim; d++) {
            ST_double val;
            if (SF_vdata(d + 1, j, &val) != 0 || SF_is_missing(val)) val = 0.0;
            reg_data[d][j - 1] = val;
        }
        {
            ST_double val;
            if (SF_vdata(idx_y, j, &val) != 0 || SF_is_missing(val)) val = 0.0;
            y_data[j - 1] = val;
        }
        if (ntarget > 0) {
            ST_double val;
            if (SF_vdata(idx_target_start, j, &val) != 0 || SF_is_missing(val)) val = 0.0;
            target[j - 1] = val;
        }
        if (ngroup > 0) {
            int g;
            for (g = 0; g < ngroup; g++) {
                ST_double val;
                if (SF_vdata(idx_group_start + g, j, &val) != 0 || SF_is_missing(val)) val = 0.0;
                group[g][j - 1] = val;
            }
        }
    }

    /* ================================================================
     * Estimation: grouped vs. ungrouped
     * ================================================================ */

    if (ngroup > 0) {
        /* ---- Grouped estimation ---- */
        unique_groups_t *ug = init_unique_groups(ngroup);
        if (!ug) {
            SF_error("Error: Memory allocation failed\n");
            free(in_if);
            free_matrix(reg_data, dim);
            free(y_data);
            free(target);
            free_matrix(group, ngroup);
            free(result);
            return 1;
        }

        collect_unique_groups(group, n_obs, ngroup, ug);

        for (i = 0; i < ug->count; i++) {
            /* Count total in-sample obs for this group */
            int n_group_total = 0;
            for (j = 0; j < n_obs; j++) {
                if (in_if[j] &&
                    match_group_combo(group, ngroup, j, ug->values[i]))
                    n_group_total++;
            }
            if (minobs > 0 && n_group_total < minobs) continue;

            /* Count training obs for this group */
            int n_train_g = 0;
            for (j = 0; j < n_obs; j++) {
                if (in_if[j] &&
                    match_group_combo(group, ngroup, j, ug->values[i]) &&
                    (ntarget == 0 || target[j] == 0.0))
                    n_train_g++;
            }
            if (n_train_g < 2) continue;

            /* Gather training data */
            double **train_x = alloc_double_matrix(dim, n_train_g);
            double *train_y  = alloc_double_array(n_train_g);
            if (!train_x || !train_y) {
                if (train_x) free_matrix(train_x, dim);
                free(train_y);
                continue;
            }

            int idx = 0;
            for (j = 0; j < n_obs; j++) {
                if (in_if[j] &&
                    match_group_combo(group, ngroup, j, ug->values[i]) &&
                    (ntarget == 0 || target[j] == 0.0)) {
                    int d;
                    for (d = 0; d < dim; d++)
                        train_x[d][idx] = reg_data[d][j];
                    train_y[idx] = y_data[j];
                    idx++;
                }
            }

            /* Select bandwidth */
            double *h = (double*)malloc(dim * sizeof(double));
            if (!h) {
                free_matrix(train_x, dim);
                free(train_y);
                continue;
            }
            compute_bw_cv(train_x, train_y, n_train_g, dim,
                           bandwidth_rule, manual_h,
                           cv_folds, cv_grids, kernel_type, h);

            /* ---- Compute standard errors (if requested) ---- */
            if (nse > 0) {
                double *se_resid = alloc_double_array(n_train_g);
                if (!se_resid) {
                    free(h);
                    free_matrix(train_x, dim);
                    free(train_y);
                    continue;
                }
                if (dim == 1) {
                    compute_se_residuals_1d(train_x[0], train_y, n_train_g,
                                             h[0], kernel_type, se_type,
                                             se_resid);
                } else {
                    compute_se_residuals_mv(train_x, train_y, n_train_g,
                                             dim, h, kernel_type, se_type,
                                             se_resid);
                }

                for (j = 0; j < n_obs; j++) {
                    if (in_if[j] &&
                        match_group_combo(group, ngroup, j, ug->values[i])) {
                        if (dim == 1) {
                            result[j] = nw_eval_1d_with_se(reg_data[0][j],
                                                            train_x[0], train_y,
                                                            se_resid,
                                                            n_train_g, h[0],
                                                            kernel_type,
                                                            &se_result[j]);
                        } else {
                            double *x = (double*)malloc(dim * sizeof(double));
                            if (x) {
                                int d;
                                for (d = 0; d < dim; d++) x[d] = reg_data[d][j];
                                result[j] = nw_eval_mv_with_se(x, train_x, train_y,
                                                                se_resid,
                                                                n_train_g, dim, h,
                                                                kernel_type,
                                                                &se_result[j]);
                                free(x);
                            }
                        }
                    }
                }
                free(se_resid);
            } else {
                /* Evaluate NW estimator for ALL obs in this group (no SE) */
#ifdef _OPENMP
#pragma omp parallel for
#endif
                for (j = 0; j < n_obs; j++) {
                    if (in_if[j] &&
                        match_group_combo(group, ngroup, j, ug->values[i])) {
                        if (dim == 1) {
                            result[j] = nw_eval_1d(reg_data[0][j],
                                                   train_x[0], train_y,
                                                   n_train_g, h[0], kernel_type);
                        } else {
                            double *x = (double*)malloc(dim * sizeof(double));
                            if (x) {
                                int d;
                                for (d = 0; d < dim; d++) x[d] = reg_data[d][j];
                                result[j] = nw_eval_mv(x, train_x, train_y,
                                                        n_train_g, dim, h,
                                                        kernel_type);
                                free(x);
                            }
                        }
                    }
                }
            }

            free(h);
            free_matrix(train_x, dim);
            free(train_y);
        }

        SF_scal_save("nwreg_ngroups", (double)ug->count);
        free_unique_groups(ug);

    } else {
        /* ---- Ungrouped estimation ---- */
        int n_train = 0;
        for (j = 0; j < n_obs; j++) {
            if (in_if[j] && (ntarget == 0 || target[j] == 0.0))
                n_train++;
        }
        if (n_train < 2) {
            SF_error("Error: Need at least 2 training observations\n");
            free(in_if);
            free_matrix(reg_data, dim);
            free(y_data);
            free(target);
            free(result);
            return 1;
        }

        double **train_x = alloc_double_matrix(dim, n_train);
        double *train_y  = alloc_double_array(n_train);
        if (!train_x || !train_y) {
            SF_error("Error: Memory allocation failed\n");
            free(in_if);
            free_matrix(reg_data, dim);
            free(y_data);
            free(target);
            free(result);
            if (train_x) free_matrix(train_x, dim);
            free(train_y);
            return 1;
        }

        int idx = 0;
        for (j = 0; j < n_obs; j++) {
            if (in_if[j] && (ntarget == 0 || target[j] == 0.0)) {
                int d;
                for (d = 0; d < dim; d++)
                    train_x[d][idx] = reg_data[d][j];
                train_y[idx] = y_data[j];
                idx++;
            }
        }

        double *h = (double*)malloc(dim * sizeof(double));
        if (!h) {
            SF_error("Error: Memory allocation failed\n");
            free(in_if);
            free_matrix(reg_data, dim);
            free(y_data);
            free(target);
            free(result);
            free_matrix(train_x, dim);
            free(train_y);
            return 1;
        }

        compute_bw_cv(train_x, train_y, n_train, dim,
                       bandwidth_rule, manual_h,
                       cv_folds, cv_grids, kernel_type, h);

        /* ---- Compute standard errors (if requested) ---- */
        if (nse > 0) {
            double *se_resid = alloc_double_array(n_train);
            if (!se_resid) {
                free(h);
                free_matrix(train_x, dim);
                free(train_y);
                free(in_if);
                free_matrix(reg_data, dim);
                free(y_data);
                free(target);
                free(result);
                free(se_result);
                return 1;
            }
            if (dim == 1) {
                compute_se_residuals_1d(train_x[0], train_y, n_train,
                                         h[0], kernel_type, se_type,
                                         se_resid);
            } else {
                compute_se_residuals_mv(train_x, train_y, n_train,
                                         dim, h, kernel_type, se_type,
                                         se_resid);
            }

            for (j = 0; j < n_obs; j++) {
                if (in_if[j]) {
                    if (dim == 1) {
                        result[j] = nw_eval_1d_with_se(reg_data[0][j],
                                                        train_x[0], train_y,
                                                        se_resid,
                                                        n_train, h[0],
                                                        kernel_type,
                                                        &se_result[j]);
                    } else {
                        double *x = (double*)malloc(dim * sizeof(double));
                        if (x) {
                            int d;
                            for (d = 0; d < dim; d++) x[d] = reg_data[d][j];
                            result[j] = nw_eval_mv_with_se(x, train_x, train_y,
                                                            se_resid,
                                                            n_train, dim, h,
                                                            kernel_type,
                                                            &se_result[j]);
                            free(x);
                        }
                    }
                }
            }
            free(se_resid);
        } else {
            /* Evaluate NW estimator for ALL in-sample obs (no SE) */
#ifdef _OPENMP
#pragma omp parallel for
#endif
            for (j = 0; j < n_obs; j++) {
                if (in_if[j]) {
                    if (dim == 1) {
                        result[j] = nw_eval_1d(reg_data[0][j],
                                                train_x[0], train_y,
                                                n_train, h[0], kernel_type);
                    } else {
                        double *x = (double*)malloc(dim * sizeof(double));
                        if (x) {
                            int d;
                            for (d = 0; d < dim; d++) x[d] = reg_data[d][j];
                            result[j] = nw_eval_mv(x, train_x, train_y,
                                                    n_train, dim, h, kernel_type);
                            free(x);
                        }
                    }
                }
            }
        }

        free(h);
        free_matrix(train_x, dim);
        free(train_y);
    }

    /* ---- Write results back to Stata ---- */
    for (j = 1; j <= n_obs; j++) {
        if (in_if[j - 1]) {
            SF_vstore(idx_result, j, result[j - 1]);
            if (nse > 0) {
                SF_vstore(idx_se, j, se_result[j - 1]);
            }
        }
    }

    /* ---- Summary output ---- */
    stata_printf("Nadaraya-Watson kernel regression complete\n");
    stata_printf("  Regressors: %d\n", nreg);
    stata_printf("  Observations: %ld\n", (long)n_obs);
    stata_printf("  Kernel: %s\n", get_kernel_name(kernel_type));
    if (nse > 0) {
        const char *se_name = (se_type == 1) ? "leave-one-out" :
                               (se_type == 2) ? "leverage-corrected" : "full-sample";
        stata_printf("  Standard errors: %s\n", se_name);
    }
    if (ngroup > 0) {
        ST_double ng;
        SF_scal_use("nwreg_ngroups", &ng);
        stata_printf("  Group variables: %d\n", ngroup);
        stata_printf("  Groups: %d\n", (int)ng);
    }

    /* ---- Free all memory ---- */
    free(in_if);
    free_matrix(reg_data, dim);
    free(y_data);
    free(target);
    if (group) free_matrix(group, ngroup);
    free(result);
    free(se_result);

    return 0;
}
