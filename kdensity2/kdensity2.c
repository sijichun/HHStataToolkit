/**
 * kdensity2.c - Kernel Density Estimation Plugin for Stata
 *
 * Features:
 *   - Evaluates density at each observation (no grid)
 *   - Supports target split: target=0 = training set, target=1 = test set
 *   - Supports multi-dimensional grouped estimation
 *   - minobs(N): skip groups with fewer than N observations
 *   - Uses shared utils for kernels, bandwidth, data I/O
 */

#include "stplugin.h"
#include "utils.h"

static double kde_eval_1d(double x, double *train_data, int n_train,
                           double h, int kernel_type)
{
    kernel_1d_func K = get_kernel_1d(kernel_type);
    double sum = 0.0;
    int j;
    for (j = 0; j < n_train; j++) {
        double u = (x - train_data[j]) / h;
        sum += K(u);
    }
    return sum / (n_train * h);
}

static double kde_eval_mv(double *x, double **train_data, int n_train,
                           int dim, double *h, int kernel_type)
{
    double sum = 0.0;
    int j, d;
    double *u = (double*)malloc(dim * sizeof(double));
    if (!u) return 0.0;

#ifdef _OPENMP
#pragma omp parallel for reduction(+:sum)
#endif
    for (j = 0; j < n_train; j++) {
        for (d = 0; d < dim; d++) {
            u[d] = (x[d] - train_data[d][j]) / h[d];
        }
        sum += kernel_product(u, dim, kernel_type);
    }

    double h_prod = 1.0;
    for (d = 0; d < dim; d++) h_prod *= h[d];

    free(u);
    return sum / (n_train * h_prod);
}

static void compute_bandwidth(double **train_data, int n_train, int dim,
                               int bandwidth_rule, double manual_h,
                               double *h)
{
    int j;
    if (dim == 1) {
        if (bandwidth_rule == BANDWIDTH_SILVERMAN)
            h[0] = silverman_bandwidth(train_data[0], n_train);
        else if (bandwidth_rule == BANDWIDTH_SCOTT)
            h[0] = scott_bandwidth(train_data[0], n_train);
        else
            h[0] = manual_h;
    } else {
        if (bandwidth_rule == BANDWIDTH_SILVERMAN)
            silverman_bandwidth_mv(train_data, n_train, dim, h);
        else if (bandwidth_rule == BANDWIDTH_SCOTT)
            scott_bandwidth_mv(train_data, n_train, dim, h);
        else
            for (j = 0; j < dim; j++) h[j] = manual_h;
    }
}

/* ============================================================================
 * Cross-Validation for Bandwidth Selection
 * ============================================================================ */

#define CV_GRID_STEP    0.05

/* K-fold CV log-likelihood score for 1D KDE (larger = better) */
static double cv_score_1d(double *data, int n, double h,
                           int kernel_type, int k)
{
    kernel_1d_func K = get_kernel_1d(kernel_type);
    double score = 0.0;
    int fold, i, j;

    for (fold = 0; fold < k; fold++) {
        int test_start = (fold * n) / k;
        int test_end   = ((fold + 1) * n) / k;
        int test_size  = test_end - test_start;
        int train_size = n - test_size;
        if (train_size < 2 || test_size < 1) continue;

        double fold_score = 0.0;
        for (i = test_start; i < test_end; i++) {
            double sum = 0.0;
            for (j = 0; j < n; j++) {
                if (j < test_start || j >= test_end)
                    sum += K((data[i] - data[j]) / h);
            }
            fold_score += log(sum / (train_size * h));
        }
        score += fold_score;
    }
    return score / n;
}

/* K-fold CV log-likelihood score for multivariate KDE */
static double cv_score_mv(double **data, int n, int dim, double *h,
                           int kernel_type, int k)
{
    double score = 0.0;
    int fold, i, j, d;
    double *u = (double*)malloc(dim * sizeof(double));
    if (!u) return -1e100;

    for (fold = 0; fold < k; fold++) {
        int test_start = (fold * n) / k;
        int test_end   = ((fold + 1) * n) / k;
        int test_size  = test_end - test_start;
        int train_size = n - test_size;
        if (train_size < 2 || test_size < 1) continue;

        double h_prod = 1.0;
        for (d = 0; d < dim; d++) h_prod *= h[d];

        double fold_score = 0.0;
        for (i = test_start; i < test_end; i++) {
            double sum = 0.0;
            for (j = 0; j < n; j++) {
                if (j >= test_start && j < test_end) continue;
                for (d = 0; d < dim; d++)
                    u[d] = (data[d][i] - data[d][j]) / h[d];
                sum += kernel_product(u, dim, kernel_type);
            }
            fold_score += log(sum / (train_size * h_prod));
        }
        score += fold_score;
    }
    free(u);
    return score / n;
}

/* Select 1D bandwidth by K-fold CV grid search */
static double cv_select_1d(double *data, int n, int kernel_type,
                            int k, int ngrids, double ref_h)
{
    double grid[201];  /* max 201 candidates */
    int n_candidates;
    generate_log_grid(ref_h, CV_GRID_STEP, ngrids, grid, &n_candidates);

    double best_h = ref_h, best_score = -1e100;
    int i;
    for (i = 0; i < n_candidates; i++) {
        double score = cv_score_1d(data, n, grid[i], kernel_type, k);
        if (score > best_score) {
            best_score = score;
            best_h = grid[i];
        }
    }
    return best_h;
}

/* Select multivariate bandwidth by log-scale grid search (scale all dims) */
static void cv_select_mv(double **data, int n, int dim, int kernel_type,
                          int k, int ngrids, double *ref_h, double *h_out)
{
    double grid[201];  /* max 201 candidates */
    int n_candidates;
    /* Use the geometric mean of ref_h as the reference for the log grid */
    double log_mean = 0.0;
    int d;
    for (d = 0; d < dim; d++) log_mean += log(ref_h[d]);
    log_mean /= dim;
    double ref_scale = exp(log_mean);

    generate_log_grid(ref_scale, CV_GRID_STEP, ngrids, grid, &n_candidates);

    double best_score = -1e100;
    double *cand_h = (double*)malloc(dim * sizeof(double));
    int i;

    for (i = 0; i < n_candidates; i++) {
        double scale = grid[i] / ref_scale;  /* relative to reference */
        for (d = 0; d < dim; d++) cand_h[d] = ref_h[d] * scale;
        double score = cv_score_mv(data, n, dim, cand_h, kernel_type, k);
        if (score > best_score) {
            best_score = score;
            for (d = 0; d < dim; d++) h_out[d] = cand_h[d];
        }
    }
    free(cand_h);
}

/* Multi-purpose bandwidth selector (adds CV support) */
static void compute_bandwidth_cv(double **train_data, int n_train, int dim,
                                  int bandwidth_rule, double manual_h,
                                  int cv_folds, int cv_grids, int kernel_type,
                                  double *h)
{
    if (bandwidth_rule == BANDWIDTH_CV) {
        if (dim == 1) {
            double ref_h = silverman_bandwidth(train_data[0], n_train);
            h[0] = cv_select_1d(train_data[0], n_train, kernel_type,
                                 cv_folds, cv_grids, ref_h);
        } else {
            double *ref_h = (double*)malloc(dim * sizeof(double));
            silverman_bandwidth_mv(train_data, n_train, dim, ref_h);
            cv_select_mv(train_data, n_train, dim, kernel_type,
                          cv_folds, cv_grids, ref_h, h);
            free(ref_h);
        }
    } else {
        compute_bandwidth(train_data, n_train, dim,
                          bandwidth_rule, manual_h, h);
    }
}

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

STDLL stata_call(int argc, char *argv[])
{
    UTILS_OMP_SET_NTHREADS();

    int kernel_type = KERNEL_GAUSSIAN;
    int bandwidth_rule = BANDWIDTH_SILVERMAN;
    double manual_h = -1.0;
    int cv_folds = 0;
    int cv_grids = 10;

    int ndensity = -1;
    int ntarget = 0;
    int ngroup = 0;
    int minobs = 0;

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
            }
            else if (strcmp(buf, "silverman") == 0 || strcmp(buf, "scott") == 0) {
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
        else if (extract_option_value(arg, "ndensity", buf, sizeof(buf))) {
            ndensity = atoi(buf);
        }
        else if (extract_option_value(arg, "ntarget", buf, sizeof(buf))) {
            ntarget = atoi(buf);
        }
        else if (extract_option_value(arg, "ngroup", buf, sizeof(buf))) {
            ngroup = atoi(buf);
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

    ST_int n_vars = SF_nvar();
    ST_int n_obs  = SF_nobs();

    if (ndensity < 0) ndensity = n_vars;
    if (ndensity < 1) {
        SF_error("Error: No density variables specified\n");
        return 1;
    }

    int dim = ndensity;

    int idx_target_start = ndensity + 1;
    int idx_group_start  = ndensity + ntarget + 1;
    int idx_result       = ndensity + ntarget + ngroup + 1;
    int idx_touse        = idx_result + 1;

    if (n_obs < 2) {
        SF_error("Error: Need at least 2 observations\n");
        return 1;
    }

    double **density_data = alloc_double_matrix(dim, n_obs);
    double *target = (ntarget > 0) ? alloc_double_array(n_obs) : NULL;
    double **group = (ngroup > 0) ? alloc_double_matrix(ngroup, n_obs) : NULL;
    double *result = alloc_double_array(n_obs);

    int *in_if = (int*)malloc(n_obs * sizeof(int));
    if (!in_if) {
        SF_error("Error: Memory allocation failed\n");
        free_matrix(density_data, dim);
        free(target);
        if (group) free_matrix(group, ngroup);
        free(result);
        return 1;
    }

    if (!density_data || (ntarget > 0 && !target) || (ngroup > 0 && !group) || !result) {
        SF_error("Error: Memory allocation failed\n");
        free(in_if);
        free_matrix(density_data, dim);
        free(target);
        if (group) free_matrix(group, ngroup);
        free(result);
        return 1;
    }

    int j;
    /* Initialize result with Stata missing values */
    for (j = 0; j < n_obs; j++) result[j] = SV_missval;

    int n_eff = 0;
    for (j = 1; j <= n_obs; j++) {
        ST_double tval;
        if (SF_vdata(idx_touse, j, &tval) != 0) tval = 0.0;
        in_if[j - 1] = (tval == 1.0) ? 1 : 0;
        if (in_if[j - 1]) n_eff++;
    }
    if (n_eff < 2) {
        SF_error("Error: Need at least 2 observations\n");
        free(in_if);
        free_matrix(density_data, dim);
        free(target);
        if (group) free_matrix(group, ngroup);
        free(result);
        return 1;
    }

    for (j = 1; j <= n_obs; j++) {
        int d;
        for (d = 0; d < dim; d++) {
            ST_double val;
            if (SF_vdata(d + 1, j, &val) != 0 || SF_is_missing(val)) val = 0.0;
            density_data[d][j - 1] = val;
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

    if (ngroup > 0) {
        unique_groups_t *ug = init_unique_groups(ngroup);
        if (!ug) {
            SF_error("Error: Memory allocation failed\n");
            free(in_if);
            free_matrix(density_data, dim);
            free(target);
            free_matrix(group, ngroup);
            free(result);
            return 1;
        }

        collect_unique_groups(group, n_obs, ngroup, ug);

        for (i = 0; i < ug->count; i++) {
            int n_group_total = 0;
            for (j = 0; j < n_obs; j++) {
                if (in_if[j] &&
                    match_group_combo(group, ngroup, j, ug->values[i]))
                    n_group_total++;
            }
            if (minobs > 0 && n_group_total < minobs) continue;

            int n_train_g = 0;
            for (j = 0; j < n_obs; j++) {
                if (in_if[j] &&
                    match_group_combo(group, ngroup, j, ug->values[i]) &&
                    (ntarget == 0 || target[j] == 0.0)) {
                    n_train_g++;
                }
            }
            if (n_train_g < 2) continue;

            double **train_data = alloc_double_matrix(dim, n_train_g);
            if (!train_data) continue;

            int idx = 0;
            for (j = 0; j < n_obs; j++) {
                if (in_if[j] &&
                    match_group_combo(group, ngroup, j, ug->values[i]) &&
                    (ntarget == 0 || target[j] == 0.0)) {
                    int d;
                    for (d = 0; d < dim; d++)
                        train_data[d][idx] = density_data[d][j];
                    idx++;
                }
            }

            double *h = (double*)malloc(dim * sizeof(double));
            compute_bandwidth_cv(train_data, n_train_g, dim,
                                  bandwidth_rule, manual_h,
                                  cv_folds, cv_grids, kernel_type, h);

            for (j = 0; j < n_obs; j++) {
                if (in_if[j] &&
                    match_group_combo(group, ngroup, j, ug->values[i])) {
                    if (dim == 1) {
                        result[j] = kde_eval_1d(density_data[0][j],
                                                 train_data[0], n_train_g,
                                                 h[0], kernel_type);
                    } else {
                        double *x = (double*)malloc(dim * sizeof(double));
                        int d;
                        for (d = 0; d < dim; d++) x[d] = density_data[d][j];
                        result[j] = kde_eval_mv(x, train_data, n_train_g,
                                                 dim, h, kernel_type);
                        free(x);
                    }
                }
            }

            free(h);
            free_matrix(train_data, dim);
        }

        SF_scal_save("kdensity2_ngroups", (double)ug->count);
        free_unique_groups(ug);
    } else {
        int n_train = 0;
        for (j = 0; j < n_obs; j++) {
            if (in_if[j] && (ntarget == 0 || target[j] == 0.0))
                n_train++;
        }
        if (n_train < 2) {
            SF_error("Error: Need at least 2 target=0 observations\n");
            free(in_if);
            free_matrix(density_data, dim);
            free(target);
            if (group) free_matrix(group, ngroup);
            free(result);
            return 1;
        }

        double **train_data = alloc_double_matrix(dim, n_train);
        if (!train_data) {
            SF_error("Error: Memory allocation failed\n");
            free(in_if);
            free_matrix(density_data, dim);
            free(target);
            if (group) free_matrix(group, ngroup);
            free(result);
            return 1;
        }

        int idx = 0;
        for (j = 0; j < n_obs; j++) {
            if (in_if[j] && (ntarget == 0 || target[j] == 0.0)) {
                int d;
                for (d = 0; d < dim; d++)
                    train_data[d][idx] = density_data[d][j];
                idx++;
            }
        }

        double *h = (double*)malloc(dim * sizeof(double));
        compute_bandwidth_cv(train_data, n_train, dim,
                               bandwidth_rule, manual_h,
                               cv_folds, cv_grids, kernel_type, h);

        for (j = 0; j < n_obs; j++) {
            if (in_if[j]) {
                if (dim == 1) {
                    result[j] = kde_eval_1d(density_data[0][j],
                                             train_data[0], n_train,
                                             h[0], kernel_type);
                } else {
                    double *x = (double*)malloc(dim * sizeof(double));
                    int d;
                    for (d = 0; d < dim; d++) x[d] = density_data[d][j];
                    result[j] = kde_eval_mv(x, train_data, n_train,
                                             dim, h, kernel_type);
                    free(x);
                }
            }
        }

        free(h);
        free_matrix(train_data, dim);
    }

    for (j = 1; j <= n_obs; j++) {
        if (in_if[j - 1]) {
            SF_vstore(idx_result, j, result[j - 1]);
        }
    }

    stata_printf("Kernel density estimation complete\n");
    stata_printf("  Dimensions: %d\n", dim);
    stata_printf("  Observations: %ld\n", (long)n_obs);
    stata_printf("  Kernel: %s\n", get_kernel_name(kernel_type));
    if (ngroup > 0) {
        ST_double ng;
        SF_scal_use("kdensity2_ngroups", &ng);
        stata_printf("  Group variables: %d\n", ngroup);
        stata_printf("  Groups: %d\n", (int)ng);
    }

    free(in_if);
    free_matrix(density_data, dim);
    free(target);
    if (group) free_matrix(group, ngroup);
    free(result);

    return 0;
}
