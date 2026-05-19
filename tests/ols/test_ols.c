#include "ols.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

static int approx_eq(double a, double b, double tol)
{
    return fabs(a - b) <= tol;
}

static void print_result(const char *name, int pass)
{
    printf("  %-55s %s\n", name, pass ? "PASS" : "FAIL");
}

int main(void)
{
    int all_pass = 1;
    printf("=== OLS/WLS Test Suite ===\n\n");

    {
        double X[] = {1.0,1.0,1.0,1.0, 1.0,2.0,3.0,4.0};
        int ok = check_invertible_svd(X, 4, 2, NULL, NULL, NULL);
        print_result("check_invertible_svd: full-rank X", ok == 1);
        all_pass &= (ok == 1);
    }

    {
        double X[] = {1.0,1.0,1.0,1.0, 2.0,2.0,2.0,2.0};
        int ok = check_invertible_svd(X, 4, 2, NULL, NULL, NULL);
        print_result("check_invertible_svd: rank-deficient X", ok == 0);
        all_pass &= (ok == 0);
    }

    {
        double X[] = {1,0,0, 0,1,0, 0,0,1};
        double min_sv; int rank;
        int ok = check_invertible_svd(X, 3, 3, NULL, &min_sv, &rank);
        print_result("check_invertible_svd: 3x3 identity", ok==1 && rank==3 && approx_eq(min_sv,1.0,1e-10));
        all_pass &= (ok==1 && rank==3 && approx_eq(min_sv,1.0,1e-10));
    }

    {
        double X[] = {1.0,2.0,3.0,4.0,5.0};
        double y[] = {5.1,7.9,11.1,13.8,17.2};
        ols_result_t *res = ols_fit(X, y, 5, 1, 1);
        int pass = (res != NULL && res->converged);
        if (pass) {
            pass = approx_eq(res->constant, 2.0, 0.2) &&
                   approx_eq(res->beta[0], 3.0, 0.1) &&
                   res->has_constant == 1 && res->p == 1;
            printf("    constant=%.4f, beta[0]=%.4f\n", res->constant, res->beta[0]);
        }
        print_result("ols_fit: y=2+3x (constant=1)", pass);
        all_pass &= pass;
        ols_result_free(res);
    }

    {
        double X[] = {1.0,2.0,3.0,4.0,5.0};
        double y[] = {2.0,4.0,6.0,8.0,10.0};
        ols_result_t *res = ols_fit(X, y, 5, 1, 0);
        int pass = (res != NULL && res->converged);
        if (pass) {
            pass = approx_eq(res->beta[0], 2.0, 1e-10) &&
                   res->has_constant == 0 && res->p == 1;
        }
        print_result("ols_fit: y=2x (constant=0)", pass);
        all_pass &= pass;
        ols_result_free(res);
    }

    {
        double X[] = {1.0,2.0,3.0};
        double y[] = {3.0,5.0,7.0};
        ols_result_t *res = ols_fit(X, y, 3, 1, 1);
        int pass = (res != NULL && res->converged);
        if (pass) {
            pass = approx_eq(res->constant, 1.0, 1e-10) &&
                   approx_eq(res->beta[0], 2.0, 1e-10);
        }
        print_result("ols_fit: perfect fit (constant=1)", pass);
        all_pass &= pass;
        ols_result_free(res);
    }

    {
        double X[] = {1.0,2.0,3.0,4.0,5.0};
        double y[] = {5.1,7.9,11.1,13.8,17.2};
        double w[] = {1.0,1.0,1.0,1.0,1.0};
        ols_result_t *ols = ols_fit(X, y, 5, 1, 1);
        ols_result_t *wls = wls_fit(X, y, w, 5, 1, 1);
        int pass = (ols && wls && ols->converged && wls->converged);
        if (pass) {
            pass = approx_eq(ols->constant, wls->constant, 1e-10) &&
                   approx_eq(ols->beta[0], wls->beta[0], 1e-10);
        }
        print_result("wls_fit: equal weights == ols_fit", pass);
        all_pass &= pass;
        ols_result_free(ols); ols_result_free(wls);
    }

    {
        double X[] = {1.0,2.0,3.0,4.0,5.0};
        double y[] = {5.0,7.0,9.0,11.0,50.0};
        double w[] = {1.0,1.0,1.0,1.0,0.1};
        ols_result_t *ols = ols_fit(X, y, 5, 1, 1);
        ols_result_t *wls = wls_fit(X, y, w, 5, 1, 1);
        int pass = (ols && wls && ols->converged && wls->converged);
        if (pass) {
            pass = fabs(wls->beta[0] - 2.0) < fabs(ols->beta[0] - 2.0);
            printf("    OLS slope=%.4f, WLS slope=%.4f (true=2.0)\n",
                   ols->beta[0], wls->beta[0]);
        }
        print_result("wls_fit: down-weight outlier shifts coeff", pass);
        all_pass &= pass;
        ols_result_free(ols); ols_result_free(wls);
    }

    {
        double X[] = {1.0,2.0,3.0,4.0,5.0};
        double y[] = {5.1,7.9,11.1,13.8,17.2};
        ols_result_t *ols = ols_fit(X, y, 5, 1, 1);
        ols_result_t *wls = wls_fit(X, y, NULL, 5, 1, 1);
        int pass = (ols && wls && ols->converged && wls->converged);
        if (pass) {
            pass = approx_eq(ols->constant, wls->constant, 1e-10) &&
                   approx_eq(ols->beta[0], wls->beta[0], 1e-10);
        }
        print_result("wls_fit: w=NULL == ols_fit", pass);
        all_pass &= pass;
        ols_result_free(ols); ols_result_free(wls);
    }

    {
        double X[] = {1.0,2.0,3.0};
        double y[] = {3.0,5.0,7.0};
        ols_result_t *res = ols_fit(X, y, 3, 1, 1);
        double out[3];
        ols_predict(X, 3, 1, res, out);
        int pass = approx_eq(out[0], 3.0, 1e-10) &&
                   approx_eq(out[1], 5.0, 1e-10) &&
                   approx_eq(out[2], 7.0, 1e-10);
        print_result("ols_predict: with constant", pass);
        all_pass &= pass;
        ols_result_free(res);
    }

    {
        double X[] = {1.0,2.0,3.0};
        double y[] = {2.0,4.0,6.0};
        ols_result_t *res = ols_fit(X, y, 3, 1, 0);
        double out[3];
        ols_predict(X, 3, 1, res, out);
        int pass = approx_eq(out[0], 2.0, 1e-10) &&
                   approx_eq(out[1], 4.0, 1e-10) &&
                   approx_eq(out[2], 6.0, 1e-10);
        print_result("ols_predict: without constant", pass);
        all_pass &= pass;
        ols_result_free(res);
    }

    {
        double X[] = {1.0,2.0,3.0,4.0,5.0};
        double y[] = {5.1,7.9,11.1,13.8,17.2};
        ols_result_t *res = ols_fit(X, y, 5, 1, 1);
        ols_stats_t *stats = ols_compute_stats(X, y, 5, 1, res);
        int pass = (stats != NULL);
        if (pass) {
            pass = stats->rss > 0.0 && stats->tss > 0.0 &&
                   stats->r_squared > 0.99 && stats->rmse > 0.0;
            printf("    R2=%.6f, RMSE=%.4f, RSS=%.4f\n",
                   stats->r_squared, stats->rmse, stats->rss);
        }
        print_result("ols_compute_stats: with constant", pass);
        all_pass &= pass;
        ols_stats_free(stats);
        ols_result_free(res);
    }

    {
        double X[] = {1.0,2.0,3.0};
        double y[] = {3.0,5.0,7.0};
        ols_result_t *res = ols_fit(X, y, 3, 1, 1);
        ols_stats_t *stats = ols_compute_stats(X, y, 3, 1, res);
        int pass = (stats != NULL);
        if (pass) {
            pass = approx_eq(stats->rss, 0.0, 1e-10) &&
                   approx_eq(stats->r_squared, 1.0, 1e-10);
        }
        print_result("ols_compute_stats: perfect fit R2=1", pass);
        all_pass &= pass;
        ols_stats_free(stats);
        ols_result_free(res);
    }

    printf("\n=== %s ===\n", all_pass ? "ALL TESTS PASSED" : "SOME TESTS FAILED");
    return all_pass ? 0 : 1;
}
