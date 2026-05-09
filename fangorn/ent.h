/**
 * tree.h - Decision tree structures and function declarations for fangorn plugin
 *
 * Heap-style binary tree: root=0, left=2*p+1, right=2*p+2
 * Data layout: column-major X[n_features][n_obs], y[n_obs]
 */

#ifndef TREE_H
#define TREE_H

#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ============================================================================
 * Criterion Codes
 * ============================================================================ */

#define CRITERION_GINI    0
#define CRITERION_ENTROPY 1
#define CRITERION_MSE     2

/* ============================================================================
 * Structures
 * ============================================================================ */

typedef struct {
    int    node_id;             /* heap-style unique ID (root=0) */
    int    parent_id;           /* heap ID of parent, -1 for root */
    int    depth;

    int    split_feature;       /* feature index (0-based), -1 if leaf */
    double split_threshold;     /* split value: go left if X[feat][i] <= threshold */
    double impurity_decrease;   /* impurity decrease achieved at this split */

    int    is_leaf;
    double leaf_value;          /* predicted value (class majority or mean) */
    double leaf_impurity;       /* impurity at this leaf */
    int    n_samples;           /* number of training samples in this node */

    int    left_child;          /* array index into tree->nodes[], -1 if none */
    int    right_child;         /* array index into tree->nodes[], -1 if none */
} TreeNode;

typedef struct {
    TreeNode *nodes;
    int       n_nodes;
    int       capacity;         /* initial 128, doubles on realloc */
} DecisionTree;

typedef struct {
    double **X;                 /* [n_features][n_obs] column-major */
    double  *y;
    int      n_obs;
    int      n_features;
    int      n_classes;         /* 0 for regression */
    int    **sorted_indices;    /* [n_features][n_obs] global pre-sorted */
    int      has_sorted_indices;
} Dataset;

typedef struct {
    int    max_depth;
    int    min_samples_split;
    int    min_samples_leaf;
    double min_impurity_decrease;
    double min_impurity_decrease_factor; /* relative to root split gain; 0=disabled */
    int    max_leaf_nodes;      /* -1 or 0 = unlimited */
    int    criterion;           /* CRITERION_GINI / ENTROPY / MSE */
    int    is_classifier;
    int    n_classes;
} TreeParams;

/* ============================================================================
 * Function Declarations
 * ============================================================================ */

/* Create an empty decision tree (capacity=128). Returns NULL on alloc failure. */
DecisionTree *create_tree(void);

/* Free all memory associated with tree */
void free_tree(DecisionTree *tree);

/*
 * Add a new node to the tree at the given depth and heap_id.
 * Returns array index of the new node, or -1 on failure.
 * NOTE: May realloc tree->nodes — never hold a pointer to a node
 * across this call; always re-fetch via tree->nodes[idx].
 */
int add_node_to_tree(DecisionTree *tree, int depth, int heap_id, int parent_id);

/*
 * Make node at array index node_idx a leaf.
 * Computes leaf_value from sample_idx[0..n_samples-1] in data.
 * For classification: majority class (integer cast).
 * For regression: mean y.
 */
void make_leaf(DecisionTree *tree, int node_idx,
               const Dataset *data, const int *sample_idx, int n_samples,
               const TreeParams *params);

/* Return 1 if all y values in sample_idx are equal, 0 otherwise */
int all_same_y(const Dataset *data, const int *sample_idx, int n_samples);

/*
 * Recursively build the subtree rooted at node_idx.
 * sample_idx[0..n_samples-1] are the original observation indices in this node.
 */
void build_node_recursive(DecisionTree *tree, int node_idx,
                            Dataset *data, int *sample_idx, int n_samples,
                            const TreeParams *params, int depth,
                            int *n_leaves);

/* Build the full tree: allocates root node and starts recursion. */
void build_tree(DecisionTree *tree, Dataset *data, const TreeParams *params,
                int *sample_idx, int n_samples);

/*
 * Predict for observation obs_idx (original index into data).
 * Returns predicted value (class or regression mean).
 */
double predict_tree(const DecisionTree *tree, const Dataset *data, int obs_idx);

/*
 * Get the heap-style leaf node ID for observation obs_idx.
 * Returns the node_id field of the leaf.
 */
int get_leaf_id(const DecisionTree *tree, const Dataset *data, int obs_idx);

/*
 * Pre-compute sorted_indices[f][k] = original obs index of k-th smallest
 * value in feature f, for all features.
 * Allocates data->sorted_indices; caller must call free_sorted_indices().
 * Returns 0 on success, -1 on failure.
 */
int precompute_sorted_indices(Dataset *data);

/* Free sorted_indices allocated by precompute_sorted_indices */
void free_sorted_indices(Dataset *data);

/*
 * Export tree structure to a Mermaid flowchart file.
 * filename: path to output .md file (will be overwritten)
 * feature_names: optional array of feature names (NULL ok), length = data->n_features
 * Returns 0 on success, -1 on file I/O error.
 */
int export_tree_mermaid(const DecisionTree *tree, const char *filename,
                        const char **feature_names, const TreeParams *params);

#endif /* TREE_H */
