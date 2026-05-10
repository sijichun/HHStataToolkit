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

#ifdef USE_CUDA
#include "kdensity2_cuda.h"
#endif

double kde_eval_1d_cpu(double x, double *train_data, int n_train,
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

double kde_eval_mv_cpu(double *x, double **train_data, int n_train,
                       int dim, double *h, int kernel_type)
{
    double sum = 0.0;
    int j, d;
    double *u = (double*)malloc(dim * sizeof(double));
    if (!u) return 0.0;

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

double cv_score_1d_cpu(double *data, int n, double h,
                       int kernel_type, int k)
{
    kernel_1d_func K = get_kernel_1d(kernel_type);
    double score = 0.0;
    int fold, i;

    for (fold = 0; fold < k; fold++) {
        int test_start = (fold * n) / k;
        int test_end   = ((fold + 1) * n) / k;
        int test_size  = test_end - test_start;
        int train_size = n - test_size;
        if (train_size < 2 || test_size < 1) continue;

        double fold_score = 0.0;
#ifdef _OPENMP
#pragma omp parallel for reduction(+:fold_score)
#endif
        for (i = test_start; i < test_end; i++) {
            double sum = 0.0;
            int j;
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

double cv_score_mv_cpu(double **data, int n, int dim, double *h,
                       int kernel_type, int k)
{
    double score = 0.0;
    int fold, i, d;

    for (fold = 0; fold < k; fold++) {
        int test_start = (fold * n) / k;
        int test_end   = ((fold + 1) * n) / k;
        int test_size  = test_end - test_start;
        int train_size = n - test_size;
        if (train_size < 2 || test_size < 1) continue;

        double h_prod = 1.0;
        for (d = 0; d < dim; d++) h_prod *= h[d];

        double fold_score = 0.0;
#ifdef _OPENMP
#pragma omp parallel for reduction(+:fold_score)
#endif
        for (i = test_start; i < test_end; i++) {
            double sum = 0.0;
            int j, d;
            double u_local[MAX_DIM];
            for (j = 0; j < n; j++) {
                if (j >= test_start && j < test_end) continue;
                for (d = 0; d < dim; d++)
                    u_local[d] = (data[d][i] - data[d][j]) / h[d];
                sum += kernel_product(u_local, dim, kernel_type);
            }
            fold_score += log(sum / (train_size * h_prod));
        }
        score += fold_score;
    }
    return score / n;
}

static int cv_select_1d(double *data, int n, int kernel_type,
                         int k, int ngrids, double ref_h,
                         double *h_out, int gpu_device)
{
    double grid[201];
    int n_candidates;
    generate_log_grid(ref_h, CV_GRID_STEP, ngrids, grid, &n_candidates);

#ifdef USE_CUDA
    if (gpu_device >= 0) {
        double best_h = ref_h, best_score = -1e100;
        int i;
        for (i = 0; i < n_candidates; i++) {
            double score;
            if (gpu_cv_score_1d(data, n, grid[i], kernel_type, k, &score, gpu_device) != 0) {
                SF_error("Error: GPU cross-validation (1D) failed\n");
                return 1;
            }
            if (score > best_score) {
                best_score = score;
                best_h = grid[i];
            }
        }
        *h_out = best_h;
        return 0;
    }
#endif

    double best_h = ref_h, best_score = -1e100;
    int i;
#ifdef _OPENMP
#pragma omp parallel
    {
        double local_best_h = ref_h;
        double local_best_score = -1e100;
        #pragma omp for nowait
        for (i = 0; i < n_candidates; i++) {
            double score = cv_score_1d_cpu(data, n, grid[i], kernel_type, k);
            if (score > local_best_score) {
                local_best_score = score;
                local_best_h = grid[i];
            }
        }
        #pragma omp critical
        {
            if (local_best_score > best_score) {
                best_score = local_best_score;
                best_h = local_best_h;
            }
        }
    }
#else
    for (i = 0; i < n_candidates; i++) {
        double score = cv_score_1d_cpu(data, n, grid[i], kernel_type, k);
        if (score > best_score) {
            best_score = score;
            best_h = grid[i];
        }
    }
#endif
    *h_out = best_h;
    return 0;
}

static int cv_select_mv(double **data, int n, int dim, int kernel_type,
                         int k, int ngrids, double *ref_h, double *h_out,
                         int gpu_device)
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
        SF_error("Error: Memory allocation failed for CV grid\n");
        return 1;
    }
    int i;

#ifdef USE_CUDA
    if (gpu_device >= 0) {
        for (i = 0; i < n_candidates; i++) {
            double scale = grid[i] / ref_scale;
            for (d = 0; d < dim; d++) cand_h[d] = ref_h[d] * scale;
            double score;
            if (gpu_cv_score_mv(data, n, dim, cand_h, kernel_type, k, &score, gpu_device) != 0) {
                SF_error("Error: GPU cross-validation (multivariate) failed\n");
                free(cand_h);
                return 1;
            }
            if (score > best_score) {
                best_score = score;
                for (d = 0; d < dim; d++) h_out[d] = cand_h[d];
            }
        }
        free(cand_h);
        return 0;
    }
#endif

#ifdef _OPENMP
#pragma omp parallel
    {
        double local_best_score = -1e100;
        double local_best_h[MAX_DIM];
        double local_h[MAX_DIM];
        #pragma omp for nowait
        for (i = 0; i < n_candidates; i++) {
            double scale = grid[i] / ref_scale;
            int d;
            for (d = 0; d < dim; d++) local_h[d] = ref_h[d] * scale;
            double score = cv_score_mv_cpu(data, n, dim, local_h, kernel_type, k);
            if (score > local_best_score) {
                local_best_score = score;
                for (d = 0; d < dim; d++) local_best_h[d] = local_h[d];
            }
        }
        #pragma omp critical
        {
            if (local_best_score > best_score) {
                best_score = local_best_score;
                int d;
                for (d = 0; d < dim; d++) h_out[d] = local_best_h[d];
            }
        }
    }
#else
    for (i = 0; i < n_candidates; i++) {
        double scale = grid[i] / ref_scale;
        for (d = 0; d < dim; d++) cand_h[d] = ref_h[d] * scale;
        double score = cv_score_mv_cpu(data, n, dim, cand_h, kernel_type, k);
        if (score > best_score) {
            best_score = score;
            for (d = 0; d < dim; d++) h_out[d] = cand_h[d];
        }
    }
#endif
    free(cand_h);
    return 0;
}

static int compute_bandwidth_cv(double **train_data, int n_train, int dim,
                                 int bandwidth_rule, double manual_h,
                                 int cv_folds, int cv_grids, int kernel_type,
                                 double *h, int gpu_device)
{
    if (bandwidth_rule == BANDWIDTH_CV) {
        if (dim == 1) {
            double ref_h = silverman_bandwidth(train_data[0], n_train);
            return cv_select_1d(train_data[0], n_train, kernel_type,
                                 cv_folds, cv_grids, ref_h, &h[0], gpu_device);
        } else {
            double *ref_h = (double*)malloc(dim * sizeof(double));
            if (!ref_h) {
                SF_error("Error: Memory allocation failed for CV bandwidth\n");
                return 1;
            }
            silverman_bandwidth_mv(train_data, n_train, dim, ref_h);
            int ret = cv_select_mv(train_data, n_train, dim, kernel_type,
                                    cv_folds, cv_grids, ref_h, h, gpu_device);
            free(ref_h);
            return ret;
        }
    } else {
        compute_bandwidth(train_data, n_train, dim,
                          bandwidth_rule, manual_h, h);
        return 0;
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

/* Evaluate density for a batch of observations using CPU or GPU.
   Returns 0 on success, 1 on GPU error (CPU path never errors). */
static int eval_density_batch(double **density_data, int dim,
                               double **train_data, int n_train,
                               double *h, int kernel_type,
                               int *obs_indices, int n_eval,
                               double *result, int gpu_device)
{
    int i, d;

#ifdef USE_CUDA
    if (gpu_device >= 0) {
        if (dim == 1) {
            double *x_batch = (double*)malloc(n_eval * sizeof(double));
            double *res_batch = (double*)malloc(n_eval * sizeof(double));
            if (!x_batch || !res_batch) {
                free(x_batch); free(res_batch);
                SF_error("Error: Memory allocation failed for GPU batch\n");
                return 1;
            }
            for (i = 0; i < n_eval; i++)
                x_batch[i] = density_data[0][obs_indices[i]];
            if (gpu_kde_eval_1d(x_batch, train_data[0], n_train, n_eval,
                                h[0], kernel_type, res_batch, gpu_device) != 0) {
                SF_error("Error: GPU kernel density evaluation failed\n");
                free(x_batch); free(res_batch);
                return 1;
            }
            for (i = 0; i < n_eval; i++)
                result[obs_indices[i]] = res_batch[i];
            free(x_batch);
            free(res_batch);
            return 0;
        } else {
            double *x_batch_flat = (double*)malloc((size_t)dim * n_eval * sizeof(double));
            double *res_batch = (double*)malloc(n_eval * sizeof(double));
            if (!x_batch_flat || !res_batch) {
                free(x_batch_flat); free(res_batch);
                SF_error("Error: Memory allocation failed for GPU batch\n");
                return 1;
            }
            for (i = 0; i < n_eval; i++)
                for (d = 0; d < dim; d++)
                    x_batch_flat[d * n_eval + i] = density_data[d][obs_indices[i]];
            if (gpu_kde_eval_mv(x_batch_flat, train_data, n_train, n_eval,
                                dim, h, kernel_type, res_batch, gpu_device) != 0) {
                SF_error("Error: GPU multivariate kernel density evaluation failed\n");
                free(x_batch_flat); free(res_batch);
                return 1;
            }
            for (i = 0; i < n_eval; i++)
                result[obs_indices[i]] = res_batch[i];
            free(x_batch_flat);
            free(res_batch);
            return 0;
        }
    }
#else
    (void)gpu_device;
#endif

#ifdef _OPENMP
#pragma omp parallel for
#endif
    for (i = 0; i < n_eval; i++) {
        int j = obs_indices[i];
        if (dim == 1) {
            result[j] = kde_eval_1d_cpu(density_data[0][j],
                                         train_data[0], n_train,
                                         h[0], kernel_type);
        } else {
            double *x = (double*)malloc(dim * sizeof(double));
            for (d = 0; d < dim; d++) x[d] = density_data[d][j];
            result[j] = kde_eval_mv_cpu(x, train_data, n_train,
                                         dim, h, kernel_type);
            free(x);
        }
    }
    return 0;
}

STDLL stata_call(int argc, char *argv[])
{
    UTILS_OMP_SET_NTHREADS();

    int kernel_type = KERNEL_GAUSSIAN;
    int bandwidth_rule = BANDWIDTH_SILVERMAN;
    double manual_h = -1.0;
    int cv_folds = 0;
    int cv_grids = 10;
    int gpu_device = -1;

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
            if (cv_grids > 100) cv_grids = 100;  /* protect fixed grid[201] buffer */
        }
        else if (extract_option_value(arg, "gpu", buf, sizeof(buf))) {
            gpu_device = atoi(buf);
        }
    }

#ifdef USE_CUDA
    if (gpu_device >= 0) {
        int preflight = gpu_preflight_check(gpu_device, 0);
        if (preflight != 0) {
            char buf[128];
            switch (preflight) {
                case -1: snprintf(buf, sizeof(buf), "Error: No CUDA devices found\n"); break;
                case -2: snprintf(buf, sizeof(buf), "Error: Invalid GPU device ID (%d)\n", gpu_device); break;
                case -3: snprintf(buf, sizeof(buf), "Error: GPU compute capability < 6.0 not supported\n"); break;
                case -4: snprintf(buf, sizeof(buf), "Error: Insufficient GPU memory\n"); break;
                default: snprintf(buf, sizeof(buf), "Error: GPU preflight check failed (code %d)\n", preflight); break;
            }
            SF_error(buf);
            return 1;
        }
    }
#endif

    ST_int n_vars = SF_nvar();
    ST_int n_obs  = SF_nobs();

    if (ndensity < 0) ndensity = n_vars;
    if (ndensity < 1) {
        SF_error("Error: No density variables specified\n");
        return 1;
    }

    int dim = ndensity;
    if (dim > MAX_DIM) {
        char buf[64];
        snprintf(buf, sizeof(buf), "Error: Too many density variables (max %d)\n", MAX_DIM);
        SF_error(buf);
        return 1;
    }

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
            if (!train_data) {
                SF_error("Error: Memory allocation failed\n");
                free_unique_groups(ug);
                free(in_if); free_matrix(density_data, dim);
                free(target); free_matrix(group, ngroup);
                free(result);
                return 1;
            }

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
            if (!h) {
                SF_error("Error: Memory allocation failed for bandwidth vector\n");
                free_matrix(train_data, dim);
                free_unique_groups(ug);
                free(in_if); free_matrix(density_data, dim);
                free(target); free_matrix(group, ngroup);
                free(result);
                return 1;
            }
            if (compute_bandwidth_cv(train_data, n_train_g, dim,
                                      bandwidth_rule, manual_h,
                                      cv_folds, cv_grids, kernel_type, h,
                                      gpu_device) != 0) {
                free(h);
                free_matrix(train_data, dim);
                free_unique_groups(ug);
                free(in_if); free_matrix(density_data, dim);
                free(target); free_matrix(group, ngroup);
                free(result);
                return 1;
            }

            int n_eval_g = 0;
            for (j = 0; j < n_obs; j++) {
                if (in_if[j] && match_group_combo(group, ngroup, j, ug->values[i]))
                    n_eval_g++;
            }

            int *eval_indices = (int*)malloc(n_eval_g * sizeof(int));
            if (!eval_indices) {
                SF_error("Error: Memory allocation failed\n");
                free(h);
                free_matrix(train_data, dim);
                free_unique_groups(ug);
                free(in_if); free_matrix(density_data, dim);
                free(target); free_matrix(group, ngroup);
                free(result);
                return 1;
            }
            {
                int ei = 0;
                for (j = 0; j < n_obs; j++) {
                    if (in_if[j] && match_group_combo(group, ngroup, j, ug->values[i]))
                        eval_indices[ei++] = j;
                }
                if (eval_density_batch(density_data, dim, train_data, n_train_g,
                                       h, kernel_type, eval_indices, n_eval_g,
                                       result, gpu_device) != 0) {
                    free(eval_indices);
                    free(h);
                    free_matrix(train_data, dim);
                    free_unique_groups(ug);
                    free(in_if); free_matrix(density_data, dim);
                    free(target); free_matrix(group, ngroup);
                    free(result);
                    return 1;
                }
                free(eval_indices);
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
        if (!h) {
            SF_error("Error: Memory allocation failed for bandwidth vector\n");
            free_matrix(train_data, dim);
            free(in_if); free_matrix(density_data, dim);
            free(target); free_matrix(group, ngroup);
            free(result);
            return 1;
        }
        if (compute_bandwidth_cv(train_data, n_train, dim,
                                  bandwidth_rule, manual_h,
                                  cv_folds, cv_grids, kernel_type, h,
                                  gpu_device) != 0) {
            free(h);
            free_matrix(train_data, dim);
            free(in_if); free_matrix(density_data, dim);
            free(target); free_matrix(group, ngroup);
            free(result);
            return 1;
        }

        int n_eval = 0;
        for (j = 0; j < n_obs; j++) {
            if (in_if[j]) n_eval++;
        }

        int *eval_indices = (int*)malloc(n_eval * sizeof(int));
        if (!eval_indices) {
            SF_error("Error: Memory allocation failed\n");
            free(h);
            free_matrix(train_data, dim);
            free(in_if); free_matrix(density_data, dim);
            free(target); free_matrix(group, ngroup);
            free(result);
            return 1;
        }
        {
            int ei = 0;
            for (j = 0; j < n_obs; j++) {
                if (in_if[j]) eval_indices[ei++] = j;
            }
            if (eval_density_batch(density_data, dim, train_data, n_train,
                                   h, kernel_type, eval_indices, n_eval,
                                   result, gpu_device) != 0) {
                free(eval_indices);
                free(h);
                free_matrix(train_data, dim);
                free(in_if); free_matrix(density_data, dim);
                free(target); free_matrix(group, ngroup);
                free(result);
                return 1;
            }
            free(eval_indices);
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
