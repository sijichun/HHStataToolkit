#include "../src/stplugin.h"
#include "../src/utils.h"
#include "ent.h"
#include "split.h"
#include "utils_rf.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int cv_select_depth(Dataset *data, int *sample_idx, int n_samples,
                           TreeParams *params, int entcvdepth, int max_depth,
                           int is_classifier, unsigned int seed)
{
    if (entcvdepth < 2 || n_samples < entcvdepth * 2)
        return max_depth;

    int *cv_idx = (int *)malloc((size_t)n_samples * sizeof(int));
    if (!cv_idx) return max_depth;
    memcpy(cv_idx, sample_idx, (size_t)n_samples * sizeof(int));

    lcg_state_t rng;
    lcg_seed(&rng, seed);
    int i;
    for (i = n_samples - 1; i > 0; i--) {
        int j = (int)(lcg_uniform(&rng) * (i + 1));
        int tmp = cv_idx[i]; cv_idx[i] = cv_idx[j]; cv_idx[j] = tmp;
    }

    int *fold_of = (int *)malloc((size_t)n_samples * sizeof(int));
    if (!fold_of) { free(cv_idx); return max_depth; }
    for (i = 0; i < n_samples; i++) fold_of[i] = i % entcvdepth;
    for (i = n_samples - 1; i > 0; i--) {
        int j = (int)(lcg_uniform(&rng) * (i + 1));
        int tmp = fold_of[i]; fold_of[i] = fold_of[j]; fold_of[j] = tmp;
    }

    int depth_upper = (max_depth > 0) ? max_depth : 20;
    double *cv_scores = (double *)calloc((size_t)(depth_upper + 1), sizeof(double));
    if (!cv_scores) { free(fold_of); free(cv_idx); return max_depth; }

    int di;
    for (di = 1; di <= depth_upper; di++) cv_scores[di] = -1e100;

    #pragma omp parallel for schedule(dynamic, 1) if(depth_upper > 1)
    for (di = 1; di <= depth_upper; di++) {
        TreeParams cv_params = *params;
        cv_params.max_depth = di;

        double total_score = 0.0;
        int valid_folds = 0;
        int fi;

        for (fi = 0; fi < entcvdepth; fi++) {
            int n_cv_train = 0, n_cv_test = 0;
            int vi;
            for (vi = 0; vi < n_samples; vi++) {
                if (fold_of[vi] == fi) n_cv_test++;
                else n_cv_train++;
            }
            if (n_cv_train < 2 || n_cv_test < 1) continue;

            int *cv_train = (int *)malloc((size_t)n_cv_train * sizeof(int));
            int *cv_test  = (int *)malloc((size_t)n_cv_test  * sizeof(int));
            if (!cv_train || !cv_test) {
                free(cv_train); free(cv_test); continue;
            }

            int ti = 0, tti = 0;
            for (vi = 0; vi < n_samples; vi++) {
                if (fold_of[vi] == fi) cv_test[tti++] = cv_idx[vi];
                else cv_train[ti++] = cv_idx[vi];
            }

            DecisionTree *cv_tree = create_tree();
            if (!cv_tree) { free(cv_train); free(cv_test); continue; }
            build_tree(cv_tree, data, &cv_params, cv_train, n_cv_train, NULL);

            double fold_score = 0.0;
            if (is_classifier) {
                int correct = 0;
                for (vi = 0; vi < n_cv_test; vi++) {
                    double pred = predict_tree(cv_tree, data, cv_test[vi]);
                    if (pred == data->y[cv_test[vi]]) correct++;
                }
                fold_score = (double)correct / n_cv_test;
            } else {
                double sum_sq = 0.0;
                for (vi = 0; vi < n_cv_test; vi++) {
                    double pred = predict_tree(cv_tree, data, cv_test[vi]);
                    double resid = data->y[cv_test[vi]] - pred;
                    sum_sq += resid * resid;
                }
                fold_score = -sum_sq / n_cv_test;
            }

            total_score += fold_score;
            valid_folds++;
            free_tree(cv_tree);
            free(cv_train);
            free(cv_test);
        }

        if (valid_folds >= entcvdepth / 2)
            cv_scores[di] = total_score / valid_folds;
    }

    int best_depth = 1;
    double best_score = cv_scores[1];
    for (di = 2; di <= depth_upper; di++) {
        if (cv_scores[di] > best_score) {
            best_score = cv_scores[di];
            best_depth = di;
        }
    }

    free(cv_scores);
    free(fold_of);
    free(cv_idx);
    return best_depth;
}

STDLL stata_call(int argc, char *argv[])
{
    char buf[64];
    int i, j;

    UTILS_OMP_SET_NTHREADS();

    /* -----------------------------------------------------------------------
     * Parse argc/argv options
     * ----------------------------------------------------------------------- */
    int n_features = 0, ntarget = 0, ngroup = 0, nclasses = 0;
    int ntree = 1;
    int max_depth = 20, min_samples_split = 2, min_samples_leaf = 1;
    double min_impurity_decrease = 0.0;
    double min_impurity_decrease_factor = 0.0;
    int max_leaf_nodes = -1;
    int criterion = CRITERION_GINI;
    int is_classifier = 1;
    unsigned int seed = 12345;
    int mtry = -1;

    char mermaid_file[512] = "";
    char feature_names_buf[1024] = "";

    for (i = 0; i < argc; i++) {
        if (extract_option_value(argv[i], "nfeatures",           buf, sizeof(buf))) n_features           = atoi(buf);
        if (extract_option_value(argv[i], "ntarget",             buf, sizeof(buf))) ntarget               = atoi(buf);
        if (extract_option_value(argv[i], "ngroup",              buf, sizeof(buf))) ngroup                = atoi(buf);
        if (extract_option_value(argv[i], "nclasses",            buf, sizeof(buf))) nclasses              = atoi(buf);
        if (extract_option_value(argv[i], "ntree",               buf, sizeof(buf))) ntree                 = atoi(buf);
        if (extract_option_value(argv[i], "maxdepth",            buf, sizeof(buf))) max_depth             = atoi(buf);
        if (extract_option_value(argv[i], "minsamplessplit",     buf, sizeof(buf))) min_samples_split     = atoi(buf);
        if (extract_option_value(argv[i], "minsamplesleaf",      buf, sizeof(buf))) min_samples_leaf      = atoi(buf);
        if (extract_option_value(argv[i], "minimpuritydecrease",        buf, sizeof(buf))) min_impurity_decrease        = atof(buf);
        if (extract_option_value(argv[i], "minimpuritydecreasefactor",  buf, sizeof(buf))) min_impurity_decrease_factor = atof(buf);
        if (extract_option_value(argv[i], "maxleafnodes",               buf, sizeof(buf))) max_leaf_nodes               = atoi(buf);
        if (extract_option_value(argv[i], "seed",                       buf, sizeof(buf))) seed                         = (unsigned int)atoi(buf);
        if (extract_option_value(argv[i], "mtry",                       buf, sizeof(buf))) mtry                         = atoi(buf);
        if (extract_option_value(argv[i], "mermaid",             buf, sizeof(buf))) strncpy(mermaid_file, buf, sizeof(mermaid_file) - 1);
        if (extract_option_value(argv[i], "featurenames",        buf, sizeof(buf))) strncpy(feature_names_buf, buf, sizeof(feature_names_buf) - 1);
        if (extract_option_value(argv[i], "type", buf, sizeof(buf))) {
            if (strcmp(buf, "regress") == 0) is_classifier = 0;
        }
        if (extract_option_value(argv[i], "criterion", buf, sizeof(buf))) {
            if      (strcmp(buf, "gini")    == 0) criterion = CRITERION_GINI;
            else if (strcmp(buf, "entropy") == 0) criterion = CRITERION_ENTROPY;
            else if (strcmp(buf, "mse")     == 0) criterion = CRITERION_MSE;
        }
    }

    if (n_features <= 0) {
        SF_error("fangorn: nfeatures() must be specified and > 0\n");
        return 1;
    }
    if (is_classifier && nclasses <= 0) {
        SF_error("fangorn: nclasses() must be specified for classification\n");
        return 1;
    }
    if (!is_classifier) {
        criterion = CRITERION_MSE;
        nclasses  = 0;
    }

    /* -----------------------------------------------------------------------
     * Variable layout:
     *   features: 1 .. n_features
     *   y:        n_features + 1
     *   target:   n_features + 2          (if ntarget > 0)
     *   group:    n_features + 2 + ntarget  .. n_features + 1 + ntarget + ngroup
     *   result:   n_features + 2 + ntarget + ngroup
     *   leaf_id:  n_features + 3 + ntarget + ngroup
     *   touse:    n_features + 4 + ntarget + ngroup
     * ----------------------------------------------------------------------- */
    int idx_y       = n_features + 1;
    int idx_target  = n_features + 2;
    int idx_result  = n_features + 2 + ntarget + ngroup;
    int idx_leaf_id = idx_result  + 1;
    int idx_touse   = idx_result  + 2;

    /* -----------------------------------------------------------------------
     * Count observations
     * ----------------------------------------------------------------------- */
    ST_int n_obs_total = SF_nobs();
    int n_obs = 0;

    for (j = SF_in1(); j <= SF_in2(); j++) {
        ST_double tval;
        if (SF_vdata(idx_touse, j, &tval) != 0) continue;
        if ((int)tval == 1) n_obs++;
    }

    if (n_obs <= 0) {
        SF_error("fangorn: no usable observations\n");
        return 1;
    }
    (void)n_obs_total;

    /* -----------------------------------------------------------------------
     * Load data into C arrays
     * ----------------------------------------------------------------------- */
    double **X = alloc_double_matrix(n_features, n_obs);
    double  *y = alloc_double_array(n_obs);
    double  *target_arr = ntarget > 0 ? alloc_double_array(n_obs) : NULL;
    int     *stata_row  = (int *)malloc((size_t)n_obs * sizeof(int));

    if (!X || !y || (ntarget > 0 && !target_arr) || !stata_row) {
        SF_error("fangorn: memory allocation failed\n");
        free_matrix(X, n_features);
        free(y);
        free(target_arr);
        free(stata_row);
        return 1;
    }

    {
        int obs_i = 0;
        ST_double val;
        for (j = SF_in1(); j <= SF_in2(); j++) {
            if (SF_vdata(idx_touse, j, &val) != 0) continue;
            if ((int)val != 1) continue;

            stata_row[obs_i] = j;
            for (i = 0; i < n_features; i++) {
                SF_vdata(i + 1, j, &val);
                X[i][obs_i] = val;
            }
            SF_vdata(idx_y, j, &val);
            y[obs_i] = val;

            if (ntarget > 0) {
                SF_vdata(idx_target, j, &val);
                target_arr[obs_i] = val;
            }
            obs_i++;
        }
    }

    /* -----------------------------------------------------------------------
     * Build training sample indices (target == 0 or no target variable)
     * ----------------------------------------------------------------------- */
    int *train_idx = (int *)malloc((size_t)n_obs * sizeof(int));
    int  n_train   = 0;

    if (!train_idx) {
        SF_error("fangorn: memory allocation failed\n");
        free_matrix(X, n_features);
        free(y);
        free(target_arr);
        free(stata_row);
        return 1;
    }

    for (i = 0; i < n_obs; i++) {
        if (ntarget == 0 || target_arr[i] == 0.0)
            train_idx[n_train++] = i;
    }

    if (n_train == 0) {
        SF_error("fangorn: no training observations (target=0)\n");
        free(train_idx);
        free_matrix(X, n_features);
        free(y);
        free(target_arr);
        free(stata_row);
        return 1;
    }

    /* -----------------------------------------------------------------------
     * Build Dataset and pre-sort indices
     * ----------------------------------------------------------------------- */
    Dataset data;
    data.X                  = X;
    data.y                  = y;
    data.n_obs              = n_obs;
    data.n_features         = n_features;
    data.n_classes          = nclasses;
    data.sorted_indices     = NULL;
    data.has_sorted_indices = 0;

    if (precompute_sorted_indices(&data) != 0) {
        SF_error("fangorn: failed to precompute sorted indices\n");
        free(train_idx);
        free_matrix(X, n_features);
        free(y);
        free(target_arr);
        free(stata_row);
        return 1;
    }

    /* -----------------------------------------------------------------------
     * Set tree parameters and build tree
     * ----------------------------------------------------------------------- */
    if (mtry < 0) {
        if (is_classifier)
            mtry = (int)sqrt((double)n_features);
        else
            mtry = n_features / 3;
        if (mtry < 1) mtry = 1;
    }

    TreeParams params;
    params.max_depth                   = max_depth;
    params.min_samples_split           = min_samples_split;
    params.min_samples_leaf            = min_samples_leaf;
    params.min_impurity_decrease       = min_impurity_decrease;
    params.min_impurity_decrease_factor= min_impurity_decrease_factor;
    params.max_leaf_nodes              = max_leaf_nodes;
    params.criterion                   = criterion;
    params.is_classifier               = is_classifier;
    params.n_classes                   = nclasses;
    params.mtry                        = mtry;

    DecisionTree *tree = NULL;
    RandomForest *forest = NULL;

    /* -----------------------------------------------------------------------
     * Cross-validated depth selection (entcvdepth > 0)
     * ----------------------------------------------------------------------- */
    int entcvdepth = 0;
    for (i = 0; i < argc; i++) {
        if (extract_option_value(argv[i], "entcvdepth", buf, sizeof(buf)))
            entcvdepth = atoi(buf);
    }

    if (entcvdepth >= 2 && n_train >= entcvdepth * 2) {
        int best_depth = cv_select_depth(&data, train_idx, n_train, &params,
                                         entcvdepth, max_depth, is_classifier, seed);
        max_depth = best_depth;
        params.max_depth = best_depth;
    }

    if (ntree == 1) {
        tree = create_tree();
        if (!tree) {
            SF_error("fangorn: failed to allocate decision tree\n");
            free_sorted_indices(&data);
            free(train_idx);
            free_matrix(X, n_features);
            free(y);
            free(target_arr);
            free(stata_row);
            return 1;
        }

        build_tree(tree, &data, &params, train_idx, n_train, NULL);

        if (mermaid_file[0] != '\0') {
            char **feature_names = NULL;
            char *feature_names_tmp = NULL;
            if (feature_names_buf[0] != '\0') {
                feature_names = (char **)malloc((size_t)n_features * sizeof(char *));
                feature_names_tmp = strdup(feature_names_buf);
                if (feature_names && feature_names_tmp) {
                    char *token = strtok(feature_names_tmp, " ");
                    int fidx = 0;
                    while (token && fidx < n_features) {
                        feature_names[fidx] = token;
                        fidx++;
                        token = strtok(NULL, " ");
                    }
                    while (fidx < n_features) {
                        feature_names[fidx] = (char *)"X";
                        fidx++;
                    }
                }
            }
            if (export_tree_mermaid(tree, mermaid_file, (const char **)feature_names, &params) != 0) {
                SF_error("fangorn: failed to write Mermaid file\n");
            }
            free(feature_names_tmp);
            free(feature_names);
        }

        for (i = 0; i < n_obs; i++) {
            double pred    = predict_tree(tree, &data, i);
            double leaf_id = (double)get_leaf_id(tree, &data, i);
            SF_vstore(idx_result,  stata_row[i], pred);
            SF_vstore(idx_leaf_id, stata_row[i], leaf_id);
        }

        free_tree(tree);
    } else {
        forest = create_forest(ntree, n_features);
        if (!forest) {
            SF_error("fangorn: failed to allocate random forest\n");
            free_sorted_indices(&data);
            free(train_idx);
            free_matrix(X, n_features);
            free(y);
            free(target_arr);
            free(stata_row);
            return 1;
        }

        build_random_forest(forest, &data, &params, train_idx, n_train, seed);

        for (i = 0; i < n_obs; i++) {
            double pred;
            if (is_classifier)
                pred = (double)predict_forest_class(forest, &data, i, nclasses);
            else
                pred = predict_forest(forest, &data, i);
            SF_vstore(idx_result,  stata_row[i], pred);
            SF_vstore(idx_leaf_id, stata_row[i], 0.0);
        }

        SF_scal_save("__fangorn_oob_err", forest->oob_error);

        free_forest(forest, n_features);
    }

    free_sorted_indices(&data);
    free(train_idx);
    free_matrix(X, n_features);
    free(y);
    free(target_arr);
    free(stata_row);

    return 0;
}
