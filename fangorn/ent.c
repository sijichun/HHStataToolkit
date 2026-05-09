#include "ent.h"
#include "split.h"
#include "utils_rf.h"
#include <stdio.h>
#include <string.h>

static int count_subtree_leaves(const DecisionTree *tree, int node)
{
    if (node < 0) return 0;
    if (tree->nodes[node].is_leaf) return 1;
    return count_subtree_leaves(tree, tree->nodes[node].left_child)
         + count_subtree_leaves(tree, tree->nodes[node].right_child);
}

DecisionTree *create_tree(void)
{
    DecisionTree *tree = (DecisionTree *)malloc(sizeof(DecisionTree));
    if (!tree) return NULL;
    tree->capacity = 128;
    tree->n_nodes  = 0;
    tree->nodes    = (TreeNode *)malloc((size_t)tree->capacity * sizeof(TreeNode));
    if (!tree->nodes) {
        free(tree);
        return NULL;
    }
    return tree;
}

void free_tree(DecisionTree *tree)
{
    if (!tree) return;
    free(tree->nodes);
    free(tree);
}

int add_node_to_tree(DecisionTree *tree, int depth, int heap_id, int parent_id)
{
    TreeNode *n;
    if (tree->n_nodes >= tree->capacity) {
        int new_cap = tree->capacity * 2;
        TreeNode *tmp = (TreeNode *)realloc(tree->nodes,
                                            (size_t)new_cap * sizeof(TreeNode));
        if (!tmp) return -1;
        tree->nodes    = tmp;
        tree->capacity = new_cap;
    }
    n = &tree->nodes[tree->n_nodes];
    n->node_id            = heap_id;
    n->parent_id          = parent_id;
    n->depth              = depth;
    n->split_feature      = -1;
    n->split_threshold    = 0.0;
    n->impurity_decrease  = 0.0;
    n->is_leaf            = 0;
    n->leaf_value         = 0.0;
    n->leaf_impurity      = 0.0;
    n->n_samples          = 0;
    n->left_child         = -1;
    n->right_child        = -1;
    return tree->n_nodes++;
}

void make_leaf(DecisionTree *tree, int node_idx,
               const Dataset *data, const int *sample_idx, int n_samples,
               const TreeParams *params)
{
    TreeNode *node = &tree->nodes[node_idx];
    ImpurityFunc imp_fn = get_impurity_func(params->criterion);
    int i;

    node->is_leaf    = 1;
    node->n_samples  = n_samples;
    node->leaf_impurity = imp_fn(data->y, sample_idx, n_samples, params->n_classes);

    if (params->is_classifier) {
        int *counts = (int *)calloc((size_t)params->n_classes, sizeof(int));
        int best_class = 0, best_count = 0, c;
        if (counts) {
            for (i = 0; i < n_samples; i++) {
                c = (int)data->y[sample_idx[i]];
                if (c >= 0 && c < params->n_classes) counts[c]++;
            }
            for (c = 0; c < params->n_classes; c++) {
                if (counts[c] > best_count) {
                    best_count = counts[c];
                    best_class = c;
                }
            }
            free(counts);
        }
        node->leaf_value = (double)best_class;
    } else {
        double sum = 0.0;
        for (i = 0; i < n_samples; i++) sum += data->y[sample_idx[i]];
        node->leaf_value = (n_samples > 0) ? sum / (double)n_samples : 0.0;
    }
}

int all_same_y(const Dataset *data, const int *sample_idx, int n_samples)
{
    int i;
    double first;
    if (n_samples <= 1) return 1;
    first = data->y[sample_idx[0]];
    for (i = 1; i < n_samples; i++) {
        if (data->y[sample_idx[i]] != first) return 0;
    }
    return 1;
}

void build_node_recursive(DecisionTree *tree, int node_idx,
                           Dataset *data, int *sample_idx, int n_samples,
                           const TreeParams *params, int depth,
                           int *n_leaves, lcg_state_t *rng)
{
    SplitResult split;
    ImpurityFunc imp_fn;
    double parent_impurity;
    int *left_idx, *right_idx, left_n, right_n, k;
    int left_child_idx, right_child_idx;
    int left_heap_id, right_heap_id;
    int parent_heap_id;

    tree->nodes[node_idx].n_samples = n_samples;

    if (n_samples < params->min_samples_split ||
        (params->max_depth >= 0 && depth >= params->max_depth) ||
        all_same_y(data, sample_idx, n_samples))
    {
        make_leaf(tree, node_idx, data, sample_idx, n_samples, params);
        if (n_leaves) (*n_leaves)++;
        return;
    }

    imp_fn = get_impurity_func(params->criterion);
    parent_impurity = imp_fn(data->y, sample_idx, n_samples, params->n_classes);

    find_best_split(data, sample_idx, n_samples, parent_impurity, params, &split, rng);

    if (!split.found) {
        make_leaf(tree, node_idx, data, sample_idx, n_samples, params);
        if (n_leaves) (*n_leaves)++;
        return;
    }

    (void)n_leaves;

    tree->nodes[node_idx].split_feature     = split.feature;
    tree->nodes[node_idx].split_threshold   = split.threshold;
    tree->nodes[node_idx].impurity_decrease = split.impurity_decrease;

    left_idx  = (int *)malloc((size_t)n_samples * sizeof(int));
    right_idx = (int *)malloc((size_t)n_samples * sizeof(int));
    if (!left_idx || !right_idx) {
        free(left_idx);
        free(right_idx);
        make_leaf(tree, node_idx, data, sample_idx, n_samples, params);
        if (n_leaves) (*n_leaves)++;
        return;
    }

    left_n = right_n = 0;
    for (k = 0; k < n_samples; k++) {
        int obs = sample_idx[k];
        if (data->X[split.feature][obs] <= split.threshold)
            left_idx[left_n++]   = obs;
        else
            right_idx[right_n++] = obs;
    }

    parent_heap_id = tree->nodes[node_idx].node_id;
    left_heap_id   = 2 * parent_heap_id + 1;
    right_heap_id  = 2 * parent_heap_id + 2;

    left_child_idx  = add_node_to_tree(tree, depth + 1, left_heap_id,  parent_heap_id);
    right_child_idx = add_node_to_tree(tree, depth + 1, right_heap_id, parent_heap_id);

    if (left_child_idx < 0 || right_child_idx < 0) {
        free(left_idx);
        free(right_idx);
        make_leaf(tree, node_idx, data, sample_idx, n_samples, params);
        if (n_leaves) (*n_leaves)++;
        return;
    }

    tree->nodes[node_idx].left_child  = left_child_idx;
    tree->nodes[node_idx].right_child = right_child_idx;

    build_node_recursive(tree, left_child_idx,  data, left_idx,  left_n,
                         params, depth + 1, n_leaves, rng);
    build_node_recursive(tree, right_child_idx, data, right_idx, right_n,
                         params, depth + 1, n_leaves, rng);

    free(left_idx);
    free(right_idx);
}

void build_tree(DecisionTree *tree, Dataset *data, const TreeParams *params,
                int *sample_idx, int n_samples, lcg_state_t *rng)
{
    int root_idx = add_node_to_tree(tree, 0, 0, -1);
    if (root_idx < 0) return;

    TreeParams params_copy = *params;

    if (params->min_impurity_decrease_factor > 0.0) {
        ImpurityFunc imp_fn = get_impurity_func(params->criterion);
        double parent_impurity = imp_fn(data->y, sample_idx, n_samples, params->n_classes);
        TreeParams temp_params = *params;
        temp_params.min_impurity_decrease = 0.0;
        SplitResult split;
        find_best_split(data, sample_idx, n_samples, parent_impurity, &temp_params, &split, rng);
        if (split.found) {
            params_copy.min_impurity_decrease = params->min_impurity_decrease_factor * split.impurity_decrease;
        }
    }

    int n_leaves = 0;
    build_node_recursive(tree, root_idx, data, sample_idx, n_samples, &params_copy, 0, &n_leaves, rng);

    if (params->max_leaf_nodes > 0) {
        while (n_leaves > params->max_leaf_nodes) {
            int best_idx = -1;
            double best_gain = -1.0;
            int i;
            for (i = 0; i < tree->n_nodes; i++) {
                if (!tree->nodes[i].is_leaf && tree->nodes[i].impurity_decrease > 0) {
                    if (best_idx < 0 || tree->nodes[i].impurity_decrease < best_gain) {
                        best_idx = i;
                        best_gain = tree->nodes[i].impurity_decrease;
                    }
                }
            }
            if (best_idx < 0) break;

            tree->nodes[best_idx].is_leaf = 1;
            tree->nodes[best_idx].split_feature = -1;
            n_leaves = count_subtree_leaves(tree, root_idx);
        }
    }
}

double predict_tree(const DecisionTree *tree, const Dataset *data, int obs_idx)
{
    int cur = 0;
    while (!tree->nodes[cur].is_leaf) {
        int feat = tree->nodes[cur].split_feature;
        double thr = tree->nodes[cur].split_threshold;
        int nxt = (data->X[feat][obs_idx] <= thr)
                  ? tree->nodes[cur].left_child
                  : tree->nodes[cur].right_child;
        if (nxt < 0) break;
        cur = nxt;
    }
    return tree->nodes[cur].leaf_value;
}

int get_leaf_id(const DecisionTree *tree, const Dataset *data, int obs_idx)
{
    int cur = 0;
    while (!tree->nodes[cur].is_leaf) {
        int feat = tree->nodes[cur].split_feature;
        double thr = tree->nodes[cur].split_threshold;
        int nxt = (data->X[feat][obs_idx] <= thr)
                  ? tree->nodes[cur].left_child
                  : tree->nodes[cur].right_child;
        if (nxt < 0 || nxt >= tree->n_nodes) break;
        cur = nxt;
    }
    return tree->nodes[cur].node_id;
}

int precompute_sorted_indices(Dataset *data)
{
    int f, i;
    double *feat_vals;

    data->sorted_indices = (int **)malloc((size_t)data->n_features * sizeof(int *));
    if (!data->sorted_indices) return -1;

    for (f = 0; f < data->n_features; f++)
        data->sorted_indices[f] = NULL;

    feat_vals = (double *)malloc((size_t)data->n_obs * sizeof(double));
    if (!feat_vals) {
        free(data->sorted_indices);
        data->sorted_indices = NULL;
        return -1;
    }

    for (f = 0; f < data->n_features; f++) {
        data->sorted_indices[f] = (int *)malloc((size_t)data->n_obs * sizeof(int));
        if (!data->sorted_indices[f]) {
            free(feat_vals);
            free_sorted_indices(data);
            return -1;
        }
        for (i = 0; i < data->n_obs; i++) feat_vals[i] = data->X[f][i];
        argsort_double(feat_vals, data->sorted_indices[f], data->n_obs);
    }
    free(feat_vals);
    data->has_sorted_indices = 1;
    return 0;
}

void free_sorted_indices(Dataset *data)
{
    int f;
    if (!data->sorted_indices) return;
    for (f = 0; f < data->n_features; f++)
        free(data->sorted_indices[f]);
    free(data->sorted_indices);
    data->sorted_indices     = NULL;
    data->has_sorted_indices = 0;
}

int export_tree_mermaid(const DecisionTree *tree, const char *filename,
                        const char **feature_names, const TreeParams *params)
{
    FILE *fp;
    int i;
    const TreeNode *node;

    fp = fopen(filename, "w");
    if (!fp) return -1;

    fprintf(fp, "```mermaid\n");
    fprintf(fp, "graph TD\n");

    for (i = 0; i < tree->n_nodes; i++) {
        node = &tree->nodes[i];

        if (node->is_leaf) {
            if (params->is_classifier) {
                fprintf(fp, "    N%d[[\"class=%.0f<br>n=%d<br>impurity=%.4f\"]]\n",
                        node->node_id, node->leaf_value,
                        node->n_samples, node->leaf_impurity);
            } else {
                fprintf(fp, "    N%d[[\"predict=%.4f<br>n=%d<br>MSE=%.4f\"]]\n",
                        node->node_id, node->leaf_value,
                        node->n_samples, node->leaf_impurity);
            }
        } else {
            const char *fname = (feature_names && node->split_feature >= 0)
                                ? feature_names[node->split_feature]
                                : "X";
            fprintf(fp, "    N%d[\"%s <= %.4f<br>n=%d<br>gain=%.4f\"]\n",
                    node->node_id, fname,
                    node->split_threshold, node->n_samples,
                    node->impurity_decrease);
        }
    }

    fprintf(fp, "\n");

    for (i = 0; i < tree->n_nodes; i++) {
        node = &tree->nodes[i];
        if (!node->is_leaf) {
            fprintf(fp, "    N%d -->|\"<= %.4f\"| N%d\n",
                    node->node_id, node->split_threshold,
                    tree->nodes[node->left_child].node_id);
            fprintf(fp, "    N%d -->|\" > %.4f\"| N%d\n",
                    node->node_id, node->split_threshold,
                    tree->nodes[node->right_child].node_id);
        }
    }

    fprintf(fp, "```\n");
    fclose(fp);
    return 0;
}

/* ============================================================================
 * Random Forest: create / free
 * ============================================================================ */

RandomForest *create_forest(int ntree, int n_features)
{
    RandomForest *forest;
    int t;

    forest = (RandomForest *)malloc(sizeof(RandomForest));
    if (!forest) return NULL;

    forest->ntree      = ntree;
    forest->oob_error  = 0.0;

    forest->trees = (DecisionTree **)malloc((size_t)ntree * sizeof(DecisionTree *));
    if (!forest->trees) { free(forest); return NULL; }
    for (t = 0; t < ntree; t++) forest->trees[t] = NULL;

    forest->importance = (double *)calloc((size_t)n_features, sizeof(double));
    if (!forest->importance) {
        free(forest->trees);
        free(forest);
        return NULL;
    }

    return forest;
}

void free_forest(RandomForest *forest, int n_features)
{
    int t;
    (void)n_features;
    if (!forest) return;
    if (forest->trees) {
        for (t = 0; t < forest->ntree; t++)
            free_tree(forest->trees[t]);
        free(forest->trees);
    }
    free(forest->importance);
    free(forest);
}

/* ============================================================================
 * Random Forest: build
 *
 * Strategy (avoids all race conditions):
 *   Pass 1 — OpenMP parallel: build each tree on its own bootstrap sample.
 *   Pass 2 — Serial: re-generate each bootstrap mask (deterministic), accumulate
 *             OOB predictions and MDI importance.
 * ============================================================================ */

void build_random_forest(RandomForest *forest, Dataset *data, TreeParams *params,
                         int *train_idx, int n_train, unsigned int seed)
{
    int t, i, j, f, c;
    int n_features = data->n_features;
    int n_classes  = params->n_classes;

    double *oob_sum;
    int    *oob_count;
    int    *oob_votes;   /* flat [n_train * n_classes], classification only */

    double oob_err_sum;
    int    n_oob_obs;
    double imp_total;
    double pred;
    int    best_vote, best_class;
    BootstrapSample bs;
    int    *boot_obs;
    int     rc;

    /* ------------------------------------------------------------------ */
    /* Pass 1: parallel tree construction                                  */
    /* ------------------------------------------------------------------ */
#pragma omp parallel for schedule(dynamic, 1) private(t, bs, boot_obs, rc, i)
    for (t = 0; t < forest->ntree; t++) {
        forest->trees[t] = create_tree();
        if (!forest->trees[t]) continue;

        rc = bootstrap_sample(n_train, seed + (unsigned int)t, &bs);
        if (rc != 0) continue;

        boot_obs = (int *)malloc((size_t)bs.n_samples * sizeof(int));
        if (boot_obs) {
            lcg_state_t tree_rng;
            lcg_seed(&tree_rng, seed + 9999 + (unsigned int)t);
            for (i = 0; i < bs.n_samples; i++)
                boot_obs[i] = train_idx[bs.indices[i]];
            build_tree(forest->trees[t], data, params, boot_obs, bs.n_samples, &tree_rng);
            free(boot_obs);
        }
        free_bootstrap(&bs);
    }

    /* ------------------------------------------------------------------ */
    /* Pass 2: serial OOB accumulation                                    */
    /* ------------------------------------------------------------------ */
    oob_sum   = (double *)calloc((size_t)n_train, sizeof(double));
    oob_count = (int    *)calloc((size_t)n_train, sizeof(int));
    oob_votes = NULL;

    if (params->is_classifier && n_classes > 0)
        oob_votes = (int *)calloc((size_t)(n_train * n_classes), sizeof(int));

    if (oob_sum && oob_count) {
        for (t = 0; t < forest->ntree; t++) {
            if (!forest->trees[t]) continue;

            rc = bootstrap_sample(n_train, seed + (unsigned int)t, &bs);
            if (rc != 0) continue;

            for (i = 0; i < n_train; i++) {
                if (!bs.oob_mask[i]) continue;
                pred = predict_tree(forest->trees[t], data, train_idx[i]);
                if (params->is_classifier && oob_votes && n_classes > 0) {
                    c = (int)pred;
                    if (c >= 0 && c < n_classes)
                        oob_votes[i * n_classes + c]++;
                } else {
                    oob_sum[i] += pred;
                }
                oob_count[i]++;
            }

            free_bootstrap(&bs);

            /* MDI: accumulate impurity_decrease per split_feature */
            for (j = 0; j < forest->trees[t]->n_nodes; j++) {
                TreeNode *nd = &forest->trees[t]->nodes[j];
                f = nd->split_feature;
                if (!nd->is_leaf && f >= 0 && f < n_features)
                    forest->importance[f] += nd->impurity_decrease;
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /* Compute OOB error                                                   */
    /* ------------------------------------------------------------------ */
    oob_err_sum = 0.0;
    n_oob_obs   = 0;

    for (i = 0; i < n_train; i++) {
        if (oob_count == NULL || oob_count[i] == 0) continue;

        if (params->is_classifier && oob_votes && n_classes > 0) {
            best_vote  = -1;
            best_class = 0;
            for (c = 0; c < n_classes; c++) {
                if (oob_votes[i * n_classes + c] > best_vote) {
                    best_vote  = oob_votes[i * n_classes + c];
                    best_class = c;
                }
            }
            if (best_class != (int)data->y[train_idx[i]])
                oob_err_sum += 1.0;
        } else if (oob_sum) {
            double mean_pred = oob_sum[i] / (double)oob_count[i];
            double diff      = mean_pred - data->y[train_idx[i]];
            oob_err_sum += diff * diff;
        }
        n_oob_obs++;
    }

    forest->oob_error = (n_oob_obs > 0) ? oob_err_sum / (double)n_oob_obs : 0.0;

    /* ------------------------------------------------------------------ */
    /* Normalize MDI importance: divide by ntree, then normalize to sum=1  */
    /* ------------------------------------------------------------------ */
    imp_total = 0.0;
    for (f = 0; f < n_features; f++) {
        forest->importance[f] /= (double)forest->ntree;
        imp_total += forest->importance[f];
    }
    if (imp_total > 0.0) {
        for (f = 0; f < n_features; f++)
            forest->importance[f] /= imp_total;
    }

    free(oob_sum);
    free(oob_count);
    free(oob_votes);
}

/* ============================================================================
 * Random Forest: predict
 * ============================================================================ */

double predict_forest(RandomForest *forest, Dataset *data, int obs_idx)
{
    int t, count;
    double total;

    total = 0.0;
    count = 0;
    for (t = 0; t < forest->ntree; t++) {
        if (!forest->trees[t]) continue;
        total += predict_tree(forest->trees[t], data, obs_idx);
        count++;
    }
    return (count > 0) ? total / (double)count : 0.0;
}

int predict_forest_class(RandomForest *forest, Dataset *data, int obs_idx, int n_classes)
{
    int t, c, best_class, best_votes;
    int *votes;

    if (n_classes <= 0) return 0;

    votes = (int *)calloc((size_t)n_classes, sizeof(int));
    if (!votes) return 0;

    for (t = 0; t < forest->ntree; t++) {
        if (!forest->trees[t]) continue;
        c = (int)predict_tree(forest->trees[t], data, obs_idx);
        if (c >= 0 && c < n_classes) votes[c]++;
    }

    best_class = 0;
    best_votes = votes[0];
    for (c = 1; c < n_classes; c++) {
        if (votes[c] > best_votes) {
            best_votes = votes[c];
            best_class = c;
        }
    }

    free(votes);
    return best_class;
}
