/**
 * utils.c - Common utilities implementation for Stata kernel-based plugins
 */

#include "utils.h"
#include <stdarg.h>

/* ============================================================================
 * Kernel Functions (1D)
 * ============================================================================ */

double kernel_gaussian_1d(double u)
{
    return exp(-0.5 * u * u) / sqrt(2.0 * M_PI);
}

double kernel_epanechnikov_1d(double u)
{
    if (fabs(u) > 1.0) return 0.0;
    return 0.75 * (1.0 - u * u);
}

double kernel_uniform_1d(double u)
{
    if (fabs(u) > 1.0) return 0.0;
    return 0.5;
}

double kernel_triweight_1d(double u)
{
    if (fabs(u) > 1.0) return 0.0;
    double tmp = 1.0 - u * u;
    return (35.0 / 32.0) * tmp * tmp * tmp;
}

double kernel_cosine_1d(double u)
{
    if (fabs(u) > 1.0) return 0.0;
    return (M_PI / 4.0) * cos(M_PI * u / 2.0);
}

static kernel_1d_func kernel_table[KERNEL_NUM_TYPES] = {
    kernel_gaussian_1d,
    kernel_epanechnikov_1d,
    kernel_uniform_1d,
    kernel_triweight_1d,
    kernel_cosine_1d
};

static const char* kernel_names[KERNEL_NUM_TYPES] = {
    "gaussian",
    "epanechnikov",
    "uniform",
    "triweight",
    "cosine"
};

kernel_1d_func get_kernel_1d(int kernel_type)
{
    if (kernel_type < 0 || kernel_type >= KERNEL_NUM_TYPES)
        return kernel_gaussian_1d;
    return kernel_table[kernel_type];
}

const char* get_kernel_name(int kernel_type)
{
    if (kernel_type < 0 || kernel_type >= KERNEL_NUM_TYPES)
        return "gaussian";
    return kernel_names[kernel_type];
}

double kernel_product(double *u, int dim, int kernel_type)
{
    kernel_1d_func k = get_kernel_1d(kernel_type);
    double result = 1.0;
    int i;
    for (i = 0; i < dim; i++) {
        result *= k(u[i]);
    }
    return result;
}

/* ============================================================================
 * Statistical Utilities
 * ============================================================================ */

double compute_mean(double *data, int n)
{
    double sum = 0.0;
    int i;
    for (i = 0; i < n; i++) sum += data[i];
    return sum / n;
}

double compute_std(double *data, int n)
{
    double mean = compute_mean(data, n);
    double sum_sq = 0.0;
    int i;
    for (i = 0; i < n; i++) {
        double diff = data[i] - mean;
        sum_sq += diff * diff;
    }
    return sqrt(sum_sq / (n - 1));
}

static int compare_double(const void *a, const void *b)
{
    double da = *(const double*)a;
    double db = *(const double*)b;
    if (da < db) return -1;
    if (da > db) return 1;
    return 0;
}

double compute_iqr(double *data, int n)
{
    double *sorted = (double*)malloc(n * sizeof(double));
    if (!sorted) return 0.0;
    
    memcpy(sorted, data, n * sizeof(double));
    qsort(sorted, n, sizeof(double), compare_double);
    
    int idx25 = (int)(0.25 * (n - 1));
    int idx75 = (int)(0.75 * (n - 1));
    double q25 = sorted[idx25];
    double q75 = sorted[idx75];
    
    free(sorted);
    return q75 - q25;
}

double compute_min(double *data, int n)
{
    double min_val = data[0];
    int i;
    for (i = 1; i < n; i++) {
        if (data[i] < min_val) min_val = data[i];
    }
    return min_val;
}

double compute_max(double *data, int n)
{
    double max_val = data[0];
    int i;
    for (i = 1; i < n; i++) {
        if (data[i] > max_val) max_val = data[i];
    }
    return max_val;
}

/* ============================================================================
 * Bandwidth Selection
 * ============================================================================ */

double silverman_bandwidth(double *data, int n)
{
    double std = compute_std(data, n);
    double iqr = compute_iqr(data, n);
    double A = fmin(std, iqr / 1.34);
    if (A <= 0) A = std;
    if (A <= 0) A = 1.0;
    return 0.9 * A * pow(n, -0.2);
}

double scott_bandwidth(double *data, int n)
{
    double std = compute_std(data, n);
    if (std <= 0) std = 1.0;
    return 1.06 * std * pow(n, -0.2);
}

void scott_bandwidth_mv(double **data, int n, int dim, double *h)
{
    int j;
    for (j = 0; j < dim; j++) {
        double std = compute_std(data[j], n);
        if (std <= 0) std = 1.0;
        h[j] = std * pow(n, -1.0 / (dim + 4.0));
    }
}

void silverman_bandwidth_mv(double **data, int n, int dim, double *h)
{
    int j;
    for (j = 0; j < dim; j++) {
        double std = compute_std(data[j], n);
        double iqr = compute_iqr(data[j], n);
        double A = fmin(std, iqr / 1.34);
        if (A <= 0) A = std;
        if (A <= 0) A = 1.0;
        h[j] = A * pow(n, -1.0 / (dim + 4.0));
    }
}

/* ============================================================================
 * Stata <-> C Data Transfer
 * ============================================================================ */

double** stata_to_c_matrix(ST_int n_vars, ST_int *n_rows)
{
    ST_int n = SF_nobs();
    int i, j;
    
    double **matrix = (double**)malloc(n_vars * sizeof(double*));
    if (!matrix) return NULL;
    
    for (i = 0; i < n_vars; i++) {
        matrix[i] = (double*)malloc(n * sizeof(double));
        if (!matrix[i]) {
            for (j = 0; j < i; j++) free(matrix[j]);
            free(matrix);
            return NULL;
        }
        
        for (j = 1; j <= n; j++) {
            ST_double val;
            if (SF_vdata(i + 1, j, &val) != 0 || SF_is_missing(val)) {
                val = 0.0;
            }
            matrix[i][j - 1] = val;
        }
    }
    
    *n_rows = n;
    return matrix;
}

void free_matrix(double **matrix, int n_vars)
{
    int i;
    for (i = 0; i < n_vars; i++) {
        if (matrix[i]) free(matrix[i]);
    }
    free(matrix);
}

int c_vector_to_stata(const double *data, int n, ST_int var_idx)
{
    int j;
    for (j = 1; j <= n; j++) {
        if (SF_vstore(var_idx, j, data[j - 1]) != 0)
            return 1;
    }
    return 0;
}

/* ============================================================================
 * Memory Allocation Helpers
 * ============================================================================ */

double* alloc_double_array(int n)
{
    return (double*)calloc(n, sizeof(double));
}

double** alloc_double_matrix(int n_vars, int n_obs)
{
    int i;
    double **matrix = (double**)malloc(n_vars * sizeof(double*));
    if (!matrix) return NULL;
    
    for (i = 0; i < n_vars; i++) {
        matrix[i] = (double*)calloc(n_obs, sizeof(double));
        if (!matrix[i]) {
            free_matrix(matrix, i);
            return NULL;
        }
    }
    return matrix;
}

/* ============================================================================
 * Argument Parsing Helpers
 * ============================================================================ */

int parse_kernel_type(const char *str)
{
    if (strcmp(str, "gaussian") == 0) return KERNEL_GAUSSIAN;
    if (strcmp(str, "epanechnikov") == 0) return KERNEL_EPANECHNIKOV;
    if (strcmp(str, "uniform") == 0) return KERNEL_UNIFORM;
    if (strcmp(str, "triweight") == 0) return KERNEL_TRIWEIGHT;
    if (strcmp(str, "cosine") == 0) return KERNEL_COSINE;
    return KERNEL_GAUSSIAN;
}

int parse_bandwidth_rule(const char *str)
{
    if (strcmp(str, "silverman") == 0) return BANDWIDTH_SILVERMAN;
    if (strcmp(str, "scott") == 0) return BANDWIDTH_SCOTT;
    if (strcmp(str, "manual") == 0) return BANDWIDTH_MANUAL;
    return BANDWIDTH_SILVERMAN;
}

int extract_option_value(const char *arg, const char *key, char *out, int out_len)
{
    int key_len = strlen(key);
    if (strncmp(arg, key, key_len) != 0) return 0;
    if (arg[key_len] != '(') return 0;
    
    const char *start = arg + key_len + 1;
    const char *end = strrchr(arg, ')');
    if (!end) return 0;
    
    int len = end - start;
    if (len >= out_len) len = out_len - 1;
    strncpy(out, start, len);
    out[len] = '\0';
    return 1;
}

/* ============================================================================
 * Display Helpers
 * ============================================================================ */

void stata_printf(const char *fmt, ...)
{
    char buf[512];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    SF_display(buf);
}

/* ============================================================================
 * CV / Grid Search Helpers
 * ============================================================================ */

int generate_log_grid(double ref, double step, int half_range,
                       double *grid, int *n_candidates)
{
    double log_ref = log(ref);
    int n = 2 * half_range + 1;
    int i;
    for (i = 0; i < n; i++) {
        grid[i] = exp(log_ref + (i - half_range) * step);
    }
    *n_candidates = n;
    return 0;
}

int parse_cv_folds(const char *str)
{
    if (strncmp(str, "cv", 2) != 0) return 0;
    if (str[2] == '\0') return 10;           /* "cv" = default 10 */
    if (str[2] >= '1' && str[2] <= '9') {   /* "cv5", "cv10", etc. */
        int n = 0;
        const char *p = str + 2;
        while (*p >= '0' && *p <= '9') {
            n = n * 10 + (*p - '0');
            p++;
        }
        if (*p == '\0' && n >= 2) return n;
    }
    return 0;  /* not valid CV */
}
