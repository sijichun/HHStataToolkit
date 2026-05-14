/**
 * utils.h - Common utilities for Stata kernel-based plugins
 * 
 * Shared components:
 *   - Kernel function definitions (1D and multivariate product kernel)
 *   - Bandwidth selection rules (Silverman, Scott, manual)
 *   - Statistical utilities (mean, std, IQR, etc.)
 *   - Stata <-> C data transfer helpers
 *   - Memory management helpers
 *   - Argument parsing utilities
 *   - OpenMP thread count initialization (all plugins share the same default)
 * 
 * Designed to be reused across kdensity, kregress, and future plugins.
 */

#ifndef UTILS_H
#define UTILS_H

#include "stplugin.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ============================================================================
 * Mathematical Constants
 * ============================================================================ */

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ============================================================================
 * Kernel Function Types
 * ============================================================================ */

#define KERNEL_GAUSSIAN     0
#define KERNEL_EPANECHNIKOV 1
#define KERNEL_UNIFORM      2
#define KERNEL_TRIWEIGHT    3
#define KERNEL_COSINE       4
#define KERNEL_NUM_TYPES    5

typedef double (*kernel_1d_func)(double);

/* ============================================================================
 * Bandwidth Selection Rules
 * ============================================================================ */

#define BANDWIDTH_SILVERMAN 0
#define BANDWIDTH_SCOTT     1
#define BANDWIDTH_MANUAL    2
#define BANDWIDTH_CV        3

/* ============================================================================
 * General Limits
 * ============================================================================ */

#define MAX_DIM 10
#define MAX_GRID_POINTS 10000
#define MAX_VARNAME_LEN 32

/* ============================================================================
 * Kernel Functions (1D)
 * ============================================================================ */

/* Individual kernel functions */
double kernel_gaussian_1d(double u);
double kernel_epanechnikov_1d(double u);
double kernel_uniform_1d(double u);
double kernel_triweight_1d(double u);
double kernel_cosine_1d(double u);

/* Get kernel function by type */
kernel_1d_func get_kernel_1d(int kernel_type);

/* Get kernel name string */
const char* get_kernel_name(int kernel_type);

/* Multivariate product kernel: K(u1)*K(u2)*...*K(ud) */
double kernel_product(double *u, int dim, int kernel_type);

/* ============================================================================
 * Statistical Utilities
 * ============================================================================ */

double compute_mean(double *data, int n);
double compute_std(double *data, int n);
double compute_iqr(double *data, int n);
double compute_min(double *data, int n);
double compute_max(double *data, int n);

/* ============================================================================
 * Bandwidth Selection
 * ============================================================================ */

/* 1D bandwidth selectors */
double silverman_bandwidth(double *data, int n);
double scott_bandwidth(double *data, int n);

/* Multivariate bandwidth selectors (fills h array) */
void silverman_bandwidth_mv(double **data, int n, int dim, double *h);
void scott_bandwidth_mv(double **data, int n, int dim, double *h);

/* ============================================================================
 * Stata <-> C Data Transfer
 * ============================================================================ */

/* 
 * Read numeric variables from Stata into C matrix.
 * Returns: pointer to matrix[dim][nobs], or NULL on error.
 * Caller must free with free_matrix().
 */
double** stata_to_c_matrix(ST_int n_vars, ST_int *n_rows);

/* Free matrix allocated by stata_to_c_matrix */
void free_matrix(double **matrix, int n_vars);

/* Write C vector back to Stata variable */
int c_vector_to_stata(const double *data, int n, ST_int var_idx);

/* ============================================================================
 * Memory Allocation Helpers
 * ============================================================================ */

/* Allocate and zero-initialize a double array */
double* alloc_double_array(int n);

/* Allocate a 2D double matrix [n_vars][n_obs] */
double** alloc_double_matrix(int n_vars, int n_obs);

/* ============================================================================
 * Argument Parsing Helpers
 * ============================================================================ */

/* Parse kernel type string */
int parse_kernel_type(const char *str);

/* Parse bandwidth rule string */
int parse_bandwidth_rule(const char *str);

/* Extract value from "key(value)" format in argv string */
int extract_option_value(const char *arg, const char *key, char *out, int out_len);

/* ============================================================================
 * CV / Grid Search Helpers
 * ============================================================================ */

/* Generate a symmetric log-spaced grid around a reference value.
 * grid[i] = log(ref) + (i - half) * step, where i = 0..n_candidates-1.
 * Returns the number of candidates (odd, to include ref). */
int generate_log_grid(double ref, double step, int half_range,
                       double *grid, int *n_candidates);

/* Parse "cv" or "cvN" from a string. Returns number of folds, or 0 if not CV. */
int parse_cv_folds(const char *str);

/* ============================================================================
 * Display Helpers
 * ============================================================================ */

/* Display a formatted message via Stata */
void stata_printf(const char *fmt, ...);

/* ============================================================================
 * OpenMP Initialization
 * ============================================================================ */

/* 
 * Set default OpenMP thread count for all plugins.
 * Reads OMP_NUM_THREADS env var explicitly and calls omp_set_num_threads()
 * to ensure the plugin honors it. Falls back to 8 threads if unset.
 * Also disables dynamic thread adjustment for deterministic behavior.
 * Call this at the start of each plugin's stata_call().
 */
#ifdef _OPENMP
#include <omp.h>
#define UTILS_OMP_SET_NTHREADS() do { \
    const char *_omp_env = getenv("OMP_NUM_THREADS"); \
    int _nthr = (_omp_env) ? atoi(_omp_env) : 8; \
    if (_nthr < 1) _nthr = 1; \
    omp_set_num_threads(_nthr); \
    omp_set_dynamic(0); \
} while(0)
#else
#define UTILS_OMP_SET_NTHREADS() /* no-op */
#endif

/* Group Limits (moved from plugin-specific .c files) */
#define MAX_GROUPS  5000

#endif
