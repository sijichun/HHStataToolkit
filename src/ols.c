#include "ols.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>

extern void dgesvd_(const char *jobu, const char *jobvt,
                    int *m, int *n, double *a, int *lda,
                    double *s, double *u, int *ldu,
                    double *vt, int *ldvt,
                    double *work, int *lwork, int *info);

extern void dgelsd_(int *m, int *n, int *nrhs,
                    double *a, int *lda,
                    double *b, int *ldb,
                    double *s,
                    double *rcond, int *rank,
                    double *work, int *lwork, int *iwork, int *info);

static double dmax(double a, double b)
{
    return (a > b) ? a : b;
}

static int imin(int a, int b)
{
    return (a < b) ? a : b;
}

int check_invertible_svd(const double *X, int n, int p,
                         const double *tol, double *min_sv, int *rank)
{
    int m = n, np = p, lda = m, info = 0, lwork = -1;
    double wopt = 0.0;
    double *a = malloc((size_t)m * np * sizeof(double));
    double *s = malloc((size_t)imin(m, np) * sizeof(double));
    if (!a || !s) { free(a); free(s); return 0; }
    memcpy(a, X, (size_t)m * np * sizeof(double));

    dgesvd_("N", "N", &m, &np, a, &lda, s, NULL, &m, NULL, &np,
            &wopt, &lwork, &info);
    if (info != 0) { free(a); free(s); return 0; }

    lwork = (int)(wopt + 0.5);
    double *work = malloc((size_t)lwork * sizeof(double));
    if (!work) { free(a); free(s); return 0; }

    dgesvd_("N", "N", &m, &np, a, &lda, s, NULL, &m, NULL, &np,
            work, &lwork, &info);
    if (info != 0) { free(a); free(s); free(work); return 0; }

    int mn = imin(m, np);
    double s_max = s[0];
    double threshold = (tol && *tol > 0.0) ? *tol
                        : dmax(m, np) * DBL_EPSILON * s_max;
    int r = 0;
    for (int i = 0; i < mn; i++) if (s[i] > threshold) r++;
    int full_rank = (r >= np && np <= m) ? 1 : 0;

    if (min_sv) *min_sv = s[mn - 1];
    if (rank)   *rank   = r;

    free(a); free(s); free(work);
    return full_rank;
}

static ols_result_t* ols_fit_core(const double *A, const double *b,
                                  int n, int p_total, int has_constant)
{
    int m = n, np = p_total, nrhs = 1;
    int lda = m, ldb = dmax(m, np);
    int info = 0, rank = 0;
    double rcond = -1.0;
    int lwork = -1, liwork = -1;
    double wopt = 0.0;
    int iopt = 0;

    double *a = malloc((size_t)m * np * sizeof(double));
    double *bb = malloc((size_t)ldb * sizeof(double));
    double *s = malloc((size_t)imin(m, np) * sizeof(double));
    ols_result_t *res = calloc(1, sizeof(ols_result_t));

    if (!a || !bb || !s || !res) {
        if (res) snprintf(res->error_msg, sizeof(res->error_msg),
                          "Memory allocation failed");
        goto cleanup;
    }

    memcpy(a, A, (size_t)m * np * sizeof(double));
    memcpy(bb, b, (size_t)m * sizeof(double));

    dgelsd_(&m, &np, &nrhs, a, &lda, bb, &ldb, s, &rcond, &rank,
            &wopt, &lwork, &iopt, &info);
    if (info != 0) {
        snprintf(res->error_msg, sizeof(res->error_msg),
                 "DGELSD workspace query failed (info=%d)", info);
        goto cleanup;
    }

    lwork = (int)(wopt + 0.5);
    liwork = iopt;
    int mn = imin(m, np);
    int smlsiz = 25;
    int nlvl = (int)(log2((double)mn / (double)(smlsiz + 1))) + 1;
    if (nlvl < 0) nlvl = 0;
    int min_lwork = 12 * mn + 2 * mn * smlsiz + 8 * mn * nlvl + mn * nrhs
                    + (smlsiz + 1) * (smlsiz + 1);
    int min_liwork = 3 * mn * nlvl + 11 * mn;
    if (lwork < min_lwork) lwork = min_lwork;
    if (liwork < min_liwork) liwork = min_liwork;

    double *work = malloc((size_t)lwork * sizeof(double));
    int *iwork = malloc((size_t)liwork * sizeof(int));
    if (!work || !iwork) {
        snprintf(res->error_msg, sizeof(res->error_msg),
                 "Workspace allocation failed");
        goto cleanup;
    }

    dgelsd_(&m, &np, &nrhs, a, &lda, bb, &ldb, s, &rcond, &rank,
            work, &lwork, iwork, &info);
    if (info != 0) {
        snprintf(res->error_msg, sizeof(res->error_msg),
                 "DGELSD failed (info=%d)", info);
        free(work); free(iwork);
        goto cleanup;
    }

    int p_out = np - (has_constant ? 1 : 0);
    res->beta = malloc((size_t)p_out * sizeof(double));
    if (!res->beta) {
        snprintf(res->error_msg, sizeof(res->error_msg),
                 "Beta allocation failed");
        free(work); free(iwork);
        goto cleanup;
    }

    if (has_constant) {
        res->constant = bb[0];
        memcpy(res->beta, bb + 1, (size_t)p_out * sizeof(double));
    } else {
        res->constant = 0.0;
        memcpy(res->beta, bb, (size_t)p_out * sizeof(double));
    }

    res->n = m;
    res->p = p_out;
    res->rank = rank;
    res->converged = 1;

    free(work); free(iwork);

cleanup:
    free(a); free(bb); free(s);
    if (!res->converged) {
        ols_result_free(res);
        return NULL;
    }
    return res;
}

ols_result_t* ols_fit(const double *X, const double *y,
                      int n, int p, int constant)
{
    int p_total = p + (constant ? 1 : 0);
    double *A = malloc((size_t)n * p_total * sizeof(double));
    double *b = malloc((size_t)n * sizeof(double));
    if (!A || !b) { free(A); free(b); return NULL; }

    for (int i = 0; i < n; i++) {
        b[i] = y[i];
        if (constant) A[0 * n + i] = 1.0;
        int offset = constant ? 1 : 0;
        for (int j = 0; j < p; j++) {
            A[(offset + j) * n + i] = X[j * n + i];
        }
    }

    ols_result_t *res = ols_fit_core(A, b, n, p_total, constant);
    if (res) res->has_constant = constant;
    free(A); free(b);
    return res;
}

ols_result_t* wls_fit(const double *X, const double *y, const double *w,
                      int n, int p, int constant)
{
    if (!w) return ols_fit(X, y, n, p, constant);

    int p_total = p + (constant ? 1 : 0);
    double *A = malloc((size_t)n * p_total * sizeof(double));
    double *b = malloc((size_t)n * sizeof(double));
    if (!A || !b) { free(A); free(b); return NULL; }

    for (int i = 0; i < n; i++) {
        double wi = w[i];
        b[i] = wi * y[i];
        if (constant) A[0 * n + i] = wi;
        int offset = constant ? 1 : 0;
        for (int j = 0; j < p; j++) {
            A[(offset + j) * n + i] = wi * X[j * n + i];
        }
    }

    ols_result_t *res = ols_fit_core(A, b, n, p_total, constant);
    if (res) res->has_constant = constant;
    free(A); free(b);
    return res;
}

void ols_result_free(ols_result_t *result)
{
    if (!result) return;
    if (result->beta) free(result->beta);
    free(result);
}

void ols_predict(const double *X, int n, int p,
                 const ols_result_t *result, double *out)
{
    if (!result || !result->converged || !out) return;

    for (int i = 0; i < n; i++) {
        double val = result->constant;
        for (int j = 0; j < p; j++) {
            val += result->beta[j] * X[j * n + i];
        }
        out[i] = val;
    }
}

ols_stats_t* ols_compute_stats(const double *X, const double *y,
                               int n, int p,
                               const ols_result_t *result)
{
    if (!result || !result->converged) return NULL;

    ols_stats_t *stats = calloc(1, sizeof(ols_stats_t));
    stats->fitted = malloc((size_t)n * sizeof(double));
    stats->residuals = malloc((size_t)n * sizeof(double));
    if (!stats->fitted || !stats->residuals) {
        ols_stats_free(stats);
        return NULL;
    }

    ols_predict(X, n, p, result, stats->fitted);

    double rss = 0.0, tss = 0.0;
    if (result->has_constant) {
        double y_mean = 0.0;
        for (int i = 0; i < n; i++) y_mean += y[i];
        y_mean /= n;
        for (int i = 0; i < n; i++) {
            stats->residuals[i] = y[i] - stats->fitted[i];
            rss += stats->residuals[i] * stats->residuals[i];
            double dy = y[i] - y_mean;
            tss += dy * dy;
        }
    } else {
        for (int i = 0; i < n; i++) {
            stats->residuals[i] = y[i] - stats->fitted[i];
            rss += stats->residuals[i] * stats->residuals[i];
            tss += y[i] * y[i];
        }
    }

    int p_total = result->p + (result->has_constant ? 1 : 0);
    stats->rss = rss;
    stats->tss = tss;
    stats->rmse = sqrt(rss / dmax(1, n - p_total));

    if (tss > 0.0) {
        stats->r_squared = 1.0 - rss / tss;
        if (n > p_total) {
            stats->adj_r_squared = 1.0 - (rss / (n - p_total)) / (tss / (n - 1));
        } else {
            stats->adj_r_squared = stats->r_squared;
        }
    } else {
        stats->r_squared = 0.0;
        stats->adj_r_squared = 0.0;
    }

    return stats;
}

void ols_stats_free(ols_stats_t *stats)
{
    if (!stats) return;
    if (stats->fitted) free(stats->fitted);
    if (stats->residuals) free(stats->residuals);
    free(stats);
}
