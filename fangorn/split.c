#include "split.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

double gini_impurity(const double *y, const int *idx, int n, int n_classes)
{
    int *counts;
    int i, c;
    double gini, p;

    if (n <= 0) return 0.0;
    counts = (int *)calloc((size_t)n_classes, sizeof(int));
    if (!counts) return 0.0;

    for (i = 0; i < n; i++) {
        c = (int)y[idx[i]];
        if (c >= 0 && c < n_classes) counts[c]++;
    }
    gini = 1.0;
    for (c = 0; c < n_classes; c++) {
        p = (double)counts[c] / (double)n;
        gini -= p * p;
    }
    free(counts);
    return gini;
}

double entropy_impurity(const double *y, const int *idx, int n, int n_classes)
{
    int *counts;
    int i, c;
    double ent, p;

    if (n <= 0) return 0.0;
    counts = (int *)calloc((size_t)n_classes, sizeof(int));
    if (!counts) return 0.0;

    for (i = 0; i < n; i++) {
        c = (int)y[idx[i]];
        if (c >= 0 && c < n_classes) counts[c]++;
    }
    ent = 0.0;
    for (c = 0; c < n_classes; c++) {
        if (counts[c] > 0) {
            p = (double)counts[c] / (double)n;
            ent -= p * log(p);
        }
    }
    free(counts);
    return ent;
}

double mse_impurity(const double *y, const int *idx, int n, int n_classes)
{
    double mean, var, diff;
    int i;
    (void)n_classes;

    if (n <= 0) return 0.0;
    mean = 0.0;
    for (i = 0; i < n; i++) mean += y[idx[i]];
    mean /= (double)n;

    var = 0.0;
    for (i = 0; i < n; i++) {
        diff = y[idx[i]] - mean;
        var += diff * diff;
    }
    return var / (double)n;
}

ImpurityFunc get_impurity_func(int criterion)
{
    if (criterion == CRITERION_GINI)    return gini_impurity;
    if (criterion == CRITERION_ENTROPY) return entropy_impurity;
    return mse_impurity;
}

static void find_best_split_feature(
    const Dataset *data, int feat,
    const int *node_sorted, int n_sorted,
    double parent_impurity, const TreeParams *params,
    SplitResult *best)
{
    int i, left_n, right_n;
    double threshold, gain;
    int n_classes = params->n_classes;
    int is_clf = params->is_classifier;

    double left_sum = 0.0, left_sum_sq = 0.0;
    double right_sum = 0.0, right_sum_sq = 0.0;
    double total_sum = 0.0, total_sum_sq = 0.0;
    int *left_counts = NULL, *right_counts = NULL;
    double left_imp, right_imp, weighted_imp;

    if (is_clf) {
        left_counts  = (int *)calloc((size_t)n_classes, sizeof(int));
        right_counts = (int *)calloc((size_t)n_classes, sizeof(int));
        if (!left_counts || !right_counts) {
            free(left_counts);
            free(right_counts);
            return;
        }
        for (i = 0; i < n_sorted; i++) {
            int c = (int)data->y[node_sorted[i]];
            if (c >= 0 && c < n_classes) right_counts[c]++;
        }
    } else {
        for (i = 0; i < n_sorted; i++) {
            double v = data->y[node_sorted[i]];
            right_sum    += v;
            right_sum_sq += v * v;
            total_sum     = right_sum;
            total_sum_sq  = right_sum_sq;
        }
    }

    left_n  = 0;
    right_n = n_sorted;

    for (i = 0; i < n_sorted - 1; i++) {
        int orig = node_sorted[i];
        double xval = data->X[feat][orig];
        double xnext = data->X[feat][node_sorted[i+1]];

        if (is_clf) {
            int c = (int)data->y[orig];
            if (c >= 0 && c < n_classes) {
                left_counts[c]++;
                right_counts[c]--;
            }
        } else {
            double v = data->y[orig];
            left_sum    += v;
            left_sum_sq += v * v;
            right_sum    -= v;
            right_sum_sq -= v * v;
        }
        left_n++;
        right_n--;

        if (xval >= xnext) continue;
        if (left_n  < params->min_samples_leaf) continue;
        if (right_n < params->min_samples_leaf) continue;

        if (is_clf) {
            int c;
            double lp, rp;
            left_imp = 1.0; right_imp = 1.0;
            if (params->criterion == CRITERION_GINI) {
                for (c = 0; c < n_classes; c++) {
                    lp = (double)left_counts[c]  / (double)left_n;
                    rp = (double)right_counts[c] / (double)right_n;
                    left_imp  -= lp * lp;
                    right_imp -= rp * rp;
                }
            } else {
                left_imp  = 0.0;
                right_imp = 0.0;
                for (c = 0; c < n_classes; c++) {
                    if (left_counts[c] > 0) {
                        lp = (double)left_counts[c] / (double)left_n;
                        left_imp -= lp * log(lp);
                    }
                    if (right_counts[c] > 0) {
                        rp = (double)right_counts[c] / (double)right_n;
                        right_imp -= rp * log(rp);
                    }
                }
            }
        } else {
            double lmean = left_sum  / (double)left_n;
            double rmean = right_sum / (double)right_n;
            left_imp  = left_sum_sq  / (double)left_n  - lmean * lmean;
            right_imp = right_sum_sq / (double)right_n - rmean * rmean;
        }

        threshold   = (xval + xnext) * 0.5;
        weighted_imp = ((double)left_n * left_imp + (double)right_n * right_imp)
                       / (double)n_sorted;
        gain = parent_impurity - weighted_imp;

        if (gain > best->impurity_decrease) {
            best->feature           = feat;
            best->threshold         = threshold;
            best->impurity_decrease = gain;
            best->left_n            = left_n;
            best->right_n           = right_n;
            best->found             = 1;
        }
    }

    if (is_clf) {
        free(left_counts);
        free(right_counts);
    }
    (void)total_sum;
    (void)total_sum_sq;
}

void find_best_split(Dataset *data, const int *sample_idx, int n_samples,
                     double parent_impurity, const TreeParams *params,
                     SplitResult *result, lcg_state_t *rng)
{
    int feat, k, n_sorted;
    int *in_node;
    int *node_sorted;
    int *feat_subset = NULL;
    int n_feat_eval;

    result->found             = 0;
    result->impurity_decrease = params->min_impurity_decrease;

    in_node    = (int *)calloc((size_t)data->n_obs, sizeof(int));
    node_sorted = (int *)malloc((size_t)n_samples * sizeof(int));
    if (!in_node || !node_sorted) {
        free(in_node);
        free(node_sorted);
        return;
    }

    for (k = 0; k < n_samples; k++) in_node[sample_idx[k]] = 1;

    if (rng && params->mtry > 0 && params->mtry < data->n_features) {
        feat_subset = (int *)malloc((size_t)params->mtry * sizeof(int));
        if (feat_subset) {
            sample_features(data->n_features, params->mtry, feat_subset, rng);
            n_feat_eval = params->mtry;
        } else {
            n_feat_eval = data->n_features;
        }
    } else {
        n_feat_eval = data->n_features;
    }

    for (k = 0; k < n_feat_eval; k++) {
        int fidx;
        feat = feat_subset ? feat_subset[k] : k;
        n_sorted = 0;
        for (fidx = 0; fidx < data->n_obs; fidx++) {
            int orig = data->sorted_indices[feat][fidx];
            if (in_node[orig]) node_sorted[n_sorted++] = orig;
        }
        find_best_split_feature(data, feat, node_sorted, n_sorted,
                                parent_impurity, params, result);
    }

    free(feat_subset);
    free(in_node);
    free(node_sorted);
}
