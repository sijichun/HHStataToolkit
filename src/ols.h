#ifndef OLS_H
#define OLS_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double *beta;
    double constant;
    int n;
    int p;
    int has_constant;
    int rank;
    int converged;
    char error_msg[256];
} ols_result_t;

typedef struct {
    double *fitted;
    double *residuals;
    double rss;
    double tss;
    double r_squared;
    double adj_r_squared;
    double rmse;
} ols_stats_t;

int check_invertible_svd(const double *X, int n, int p,
                         const double *tol, double *min_sv, int *rank);

ols_result_t* ols_fit(const double *X, const double *y,
                      int n, int p, int constant);

ols_result_t* wls_fit(const double *X, const double *y, const double *w,
                      int n, int p, int constant);

void ols_result_free(ols_result_t *result);

void ols_predict(const double *X, int n, int p,
                 const ols_result_t *result, double *out);

ols_stats_t* ols_compute_stats(const double *X, const double *y,
                               int n, int p,
                               const ols_result_t *result);

void ols_stats_free(ols_stats_t *stats);

#ifdef __cplusplus
}
#endif

#endif
