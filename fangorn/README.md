# fangorn — Decision Tree & Random Forest Stata Plugin

High-performance C plugin implementing CART trees and Random Forests, with
OpenMP parallel tree construction, OOB error, MDI feature importance, and
CV-based depth selection.

---

## Table of Contents

1. [Principles](#principles)
   - [CART Algorithm](#cart-algorithm)
   - [Impurity Functions](#impurity-functions)
   - [Pre-sorted Index Inheritance](#pre-sorted-index-inheritance)
   - [Incremental Split Evaluation](#incremental-split-evaluation)
   - [Random Forest: Bootstrap Aggregation](#random-forest-bootstrap-aggregation)
   - [OOB Error](#oob-error)
   - [MDI Feature Importance](#mdi-feature-importance)
   - [mtry: Random Feature Subsampling](#mtry-random-feature-subsampling)
   - [Cross-Validated Depth Selection](#cross-validated-depth-selection)
   - [Regularization Methods](#regularization-methods)
2. [Stata Syntax](#stata-syntax)
3. [Data Structures](#data-structures)
4. [C Function Reference](#c-function-reference)
   - [ent.h / ent.c](#enth--entc---tree-structures-and-construction)
   - [split.h / split.c](#splith--splitc---impurity-and-split-finding)
   - [utils_rf.h / utils_rf.c](#utils_rfh--utils_rfc---utilities)
   - [fangorn.c](#fangornc---stata-plugin-entry)
5. [Variable Layout](#variable-layout)
6. [Mermaid Export](#mermaid-export)
7. [Benchmarks](#benchmarks)

---

## Principles

### CART Algorithm

fangorn implements CART (Breiman et al., 1984) with recursive binary splitting:

1. **Start with all training data at the root node**
2. **For each node**, evaluate every feature and every possible split point to find the split maximising impurity decrease
3. **Split** into left (X ≤ threshold) and right (X > threshold) children
4. **Recursively repeat** until a stopping condition is met
5. **Stopping conditions** (configurable):
   - `max_depth` reached
   - `min_samples_split` not met
   - `min_samples_leaf` would be violated in either child
   - `min_impurity_decrease` not achieved (absolute or relative via `relimpdec`)
   - `max_leaf_nodes` exceeded (post-prune)
   - All y values identical (perfect purity)

**Tree encoding**: heap-style binary tree: root = 0, left child of node p = 2p+1,
right child = 2p+2. Each node stores its heap `node_id` for leaf identification.

### Impurity Functions

#### Gini (Classification)

$$
G = 1 - \sum_{i=1}^{k} \left(\frac{c_i}{n}\right)^2
$$

Range [0, 1 − 1/k]. Default for classification.

#### Entropy (Classification)

$$
H = -\sum_{i=1}^{k} p_i \log(p_i), \quad p_i = \frac{c_i}{n}
$$

Range [0, log(k)].

#### MSE (Regression)

$$
\text{MSE} = \frac{1}{n}\sum_{i=1}^{n}(y_i - \bar{y})^2
$$

Leaf prediction = mean of training y in leaf.

#### Split Quality

Impurity decrease (information gain):

$$
\Delta = I_{\text{parent}} - \frac{n_L}{n} I_L - \frac{n_R}{n} I_R
$$

The split with maximum Δ is chosen.

### Pre-sorted Index Inheritance

**Problem**: Naive CART sorts at each node: O(m · n log n) per node.

**Solution**: Pre-sort all features once (`precompute_sorted_indices`), then
inherit sorted order via linear scan:

1. Build boolean mask `in_node[obs]` for the node's sample subset
2. For each feature f, scan global `sorted_indices[f]` and collect indices
   where `in_node[orig] == 1`
3. Result: node samples sorted by feature f — O(n) per feature, no re-sorting

### Incremental Split Evaluation

Linear scan through sorted samples, moving one sample left → right at each
step, incrementally updating left/right impurity. O(m · n) per node total
(vs O(m · n log n) without pre-sorting).

### Random Forest: Bootstrap Aggregation

fangorn implements Breiman's Random Forest (2001) when `ntree > 1`:

**Bootstrap sampling** (`bootstrap_sample`):
- Each of the `ntree` trees is trained on an independent bootstrap sample
  (size n_train, drawn with replacement)
- On average ≈ 63.2% of unique observations appear in each bootstrap sample;
  the remaining ≈ 36.8% are Out-Of-Bag (OOB)

**Tree construction**:
- Trees are built using `build_random_forest` → `build_tree` for each tree
- The per-tree LCG seed is `seed + 9999 + tree_idx` (separate from the
  bootstrap seed `seed + tree_idx`)
- OpenMP parallel: `#pragma omp parallel for schedule(dynamic, 1)` distributes
  tree construction across threads, each with its own LCG state

**Prediction** (`predict_forest`):
- Regression: average of all tree predictions
- Classification: majority vote across trees

### OOB Error

Computed in two passes:

1. **Pass 1** (parallel): build each tree on its bootstrap sample
2. **Pass 2** (serial): re-generate each bootstrap mask, accumulate OOB
   predictions without re-building the tree:
   - Classification: count votes per class → majority class → error rate
   - Regression: average predictions → MSE

Stored in scalar `__fangorn_oob_err`, returned via `r(oob_error)`.

### MDI Feature Importance

Mean Decrease in Impurity: for each feature f, sum `impurity_decrease`
across all splits on feature f, across all trees. After forest construction:

1. Divide each feature's total by `ntree` (per-tree average)
2. Normalise dividing by the sum across all features (so importance sums to 1)

### mtry: Random Feature Subsampling

At each node, `mtry` features are randomly sampled without replacement using
Fisher-Yates shuffle (`sample_features`). Only the sampled features are
evaluated for splitting. Seeded via the per-tree LCG state threaded through
`build_tree()` → `build_node_recursive()` → `find_best_split()`.

Defaults:
- Classification: `mtry = floor(sqrt(n_features))`
- Regression: `mtry = max(1, n_features / 3)`

**Note**: Prior to 2026-05-10, `mtry` was a no-op because
`build_node_recursive` passed `rng=NULL` to `find_best_split`, always using
all features. Fixed by threading `lcg_state_t*` through the build pipeline.

### Cross-Validated Depth Selection

When `entcvdepth ≥ 2` and `n_train ≥ entcvdepth × 2`:

1. Shuffle training indices using LCG (seeded by `seed()`)
2. Assign fold IDs via LCG Fisher-Yates shuffle
3. For each candidate depth d = 1 .. `max_depth`:
   - K-fold CV: train tree at depth d, compute test accuracy or negative MSE
4. Select depth with highest average CV score

Parallelised: `#pragma omp parallel for schedule(dynamic, 1)` over depths.

In RF mode (`ntree > 1`), CV uses a single proxy tree (saves overhead).

### Regularization Methods

#### `relimpdec(a)`

Minimum impurity decrease = `a × Δ_root`. Root gain is computed first with
`min_impurity_decrease = 0`, then scaled. Higher a → shallower tree.

#### `maxleafnodes(N)`

Post-pruning: grow a full tree, then greedily prune the internal node with
the smallest positive `impurity_decrease` until `n_leaves ≤ N`.

#### Combined

```stata
fangorn y x1 x2, generate(pred) relimpdec(0.1) maxleafnodes(8)
```

### Reproducibility

fangorn is fully deterministic when the same `seed()` is specified. The `seed`
option controls three sources of randomness:

1. **Bootstrap sampling** (`ntree > 1`): per-tree bootstrap draws use seed
   `seed + tree_index`
2. **mtry feature subsampling** (`ntree > 1`): per-tree LCG state starts at
   `seed + 9999 + tree_index`
3. **CV fold shuffle** (`entcvdepth ≥ 2`): fold assignment uses the `seed()`
   value directly

Single trees (`ntree = 1`) without CV are completely deterministic and do not
use randomness at all — repeated runs without specifying `seed()` will always
produce identical results.

**OpenMP note**: The OpenMP parallel tree construction in `build_random_forest`
uses per-thread LCG states (`seed + 9999 + t`), so results are reproducible
regardless of the number of threads. Set `OMP_NUM_THREADS` to control
parallelism without affecting output.

---

## Stata Syntax

```stata
fangorn depvar indepvars, generate(name) [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `type(classify\|regress)` | Task type | `classify` |
| `ntree(N)` | Number of trees (1 = single tree, >1 = RF) | `1` |
| `maxdepth(N)` | Maximum tree depth | `20` |
| `minsamplessplit(N)` | Min samples to attempt a split | `2` |
| `minsamplesleaf(N)` | Min samples in any leaf | `1` |
| `minimpuritydecrease(real)` | Absolute impurity threshold | `0.0` |
| `relimpdec(real)` | Relative to root split gain | `0.0` |
| `maxleafnodes(N)` | Post-pruning leaf limit | unlimited |
| `criterion(gini\|entropy\|mse)` | Split criterion | auto |
| `entcvdepth(N)` | CV depth selection (0 = disable) | `10` |
| `mtry(N)` | Features per split | auto |
| `ntiles(N)` | Quantile candidate thresholds; 0=all unique midpoints (exact CART), N>0 uses N-1 quantile thresholds for faster split finding | `0` |
| `seed(N)` | RNG seed | `12345` |
| `target(varname)` | Train/test split (0=train, 1=test) | all train |
| `group(varlist)` | String vars auto-encoded | none |
| `mermaid(filename)` | Export tree as flowchart | none |
| `predname(name)` | Custom prediction var name | `generate_pred` |
| `if(string)`/`in(string)` | Observation filters | all |

---

## Data Structures

```c
// TreeNode — single node in a binary decision tree
typedef struct {
    int    node_id;             // heap ID: root=0, left=2p+1, right=2p+2
    int    parent_id;           // heap ID of parent, -1 for root
    int    depth;
    int    split_feature;       // -1 if leaf
    double split_threshold;     // X[feat] <= threshold → left
    double impurity_decrease;
    int    is_leaf;
    double leaf_value;          // class majority or regression mean
    double leaf_impurity;
    int    n_samples;
    int    left_child;          // array index, -1 if none
    int    right_child;
} TreeNode;

// DecisionTree — dynamic array of nodes with doubling realloc
typedef struct {
    TreeNode *nodes;
    int       n_nodes;
    int       capacity;         // initial 128
} DecisionTree;

// Dataset — column-major X[n_features][n_obs], pre-sorted indices
typedef struct {
    double **X;
    double  *y;
    int      n_obs;
    int      n_features;
    int      n_classes;         // 0 for regression
    int    **sorted_indices;
    int      has_sorted_indices;
} Dataset;

// TreeParams — all hyperparameters bundled for passing through recursions
typedef struct {
    int    max_depth;
    int    min_samples_split;
    int    min_samples_leaf;
    double min_impurity_decrease;
    double min_impurity_decrease_factor;  // relimpdec scaling
    int    max_leaf_nodes;
    int    criterion;            // CRITERION_GINI / ENTROPY / MSE
    int    is_classifier;
    int    n_classes;
    int    mtry;                 // -1 = use all features
} TreeParams;

// SplitResult — output of find_best_split
typedef struct {
    int    feature;
    double threshold;
    double impurity_decrease;
    int    left_n;
    int    right_n;
    int    found;
} SplitResult;

// RandomForest — ensemble of ntree trees with importance + OOB
typedef struct {
    DecisionTree **trees;
    int            ntree;
    double        *importance;   // MDI, length = n_features
    double         oob_error;    // MSE (regression) or error rate (classify)
} RandomForest;

// BootstrapSample — per-tree bootstrap draw
typedef struct {
    int *indices;      // bootstrap sample (length = n_total)
    int  n_samples;
    int *oob_mask;     // 1 if OOB, length = n_total
    int  n_oob;
} BootstrapSample;
```

---

## C Function Reference

### ent.h / ent.c — Tree Structures and Construction

#### `DecisionTree *create_tree(void)`

Allocate tree with capacity 128. Returns NULL on failure.

#### `void free_tree(DecisionTree *tree)`

Free nodes array and struct. Safe with NULL.

#### `int add_node_to_tree(DecisionTree *tree, int depth, int heap_id, int parent_id)`

Append node; doubles capacity on realloc. Returns array index or -1.
**Warning**: May realloc `tree->nodes` — never hold a `TreeNode*` across call.

#### `void make_leaf(DecisionTree *tree, int node_idx, const Dataset *data, const int *sample_idx, int n_samples, const TreeParams *params)`

Set node as leaf. Classification: majority class. Regression: mean y.

#### `int all_same_y(const Dataset *data, const int *sample_idx, int n_samples)`

1 if all y equal (or n ≤ 1), 0 otherwise. Early stopping for pure nodes.

#### `void build_node_recursive(DecisionTree *tree, int node_idx, Dataset *data, int *sample_idx, int n_samples, const TreeParams *params, int depth, int *n_leaves, lcg_state_t *rng)`

Recursive CART builder. rng = NULL → use all features (single tree).
rng != NULL → mtry feature subsampling (RF).

1. Check stopping conditions → make_leaf or continue
2. Compute parent impurity
3. `find_best_split(data, ..., rng)` — with rng for mtry
4. Partition, create children, recurse

#### `void build_tree(DecisionTree *tree, Dataset *data, const TreeParams *params, int *sample_idx, int n_samples, lcg_state_t *rng)`

Entry point. Creates root, applies `relimpdec` scaling, calls
`build_node_recursive`, then post-prunes if `max_leaf_nodes > 0`.

#### `double predict_tree(const DecisionTree *tree, const Dataset *data, int obs_idx)`

Traverse tree from root to leaf. Return `leaf_value`.

#### `int get_leaf_id(const DecisionTree *tree, const Dataset *data, int obs_idx)`

Same traversal, returns heap-style `node_id`.

#### `int precompute_sorted_indices(Dataset *data)`

Pre-sort all features via `argsort_double`. O(m · n log n) once.

#### `void free_sorted_indices(Dataset *data)`

Free pre-sorted indices.

#### Random Forest API

```c
RandomForest *create_forest(int ntree, int n_features);
void free_forest(RandomForest *forest, int n_features);

void build_random_forest(RandomForest *forest, Dataset *data,
                         TreeParams *params, int *train_idx,
                         int n_train, unsigned int seed);

double predict_forest(RandomForest *forest, Dataset *data, int obs_idx);
int    predict_forest_class(RandomForest *forest, Dataset *data,
                            int obs_idx, int n_classes);
```

**`build_random_forest`**:
- Pass 1 (OpenMP parallel): for each tree t, create bootstrap sample with
  seed `seed + t`, build tree with LCG state `seed + 9999 + t`
- Pass 2 (serial): re-generate bootstrap, accumulate OOB predictions,
  aggregate MDI importance across all non-leaf nodes

#### Mermaid Export

```c
int export_tree_mermaid(const DecisionTree *tree, const char *filename,
                        const char **feature_names, const TreeParams *params);
```

Generates `graph TD` flowchart. Returns 0 on success, -1 on error.

---

### split.h / split.c — Impurity and Split Finding

#### Impurity Functions

```c
double gini_impurity(const double *y, const int *idx, int n, int n_classes);
double entropy_impurity(const double *y, const int *idx, int n, int n_classes);
double mse_impurity(const double *y, const int *idx, int n, int n_classes);
ImpurityFunc get_impurity_func(int criterion);
```

#### `void find_best_split(Dataset *data, const int *sample_idx, int n_samples, double parent_impurity, const TreeParams *params, SplitResult *result, lcg_state_t *rng)`

Core split search:
1. Build `in_node[]` mask
2. If `rng && mtry > 0 && mtry < n_features`: sample `mtry` features via
   `sample_features()` with Fisher-Yates shuffle
3. For each candidate feature, inherit sorted indices and call
   `find_best_split_feature()` (internal, incremental scan)

---

### utils_rf.h / utils_rf.c — Utilities

#### LCG Random Number Generator

```c
typedef unsigned int lcg_state_t;
void lcg_seed(lcg_state_t *state, unsigned int seed);
unsigned int lcg_next(lcg_state_t *state);
double lcg_uniform(lcg_state_t *state);
```

Park-Miller LCG: `state = 1664525 × state + 1013904223 (mod 2³²)`.
Used for bootstrap sampling, fold shuffling, and mtry feature selection.

#### `int bootstrap_sample(int n_total, unsigned int seed, BootstrapSample *bs)`

Draw n_total samples with replacement. Sets `oob_mask[i] = 1` for unsampled
observations. Returns 0 on success, -1 on allocation failure.

#### `void sample_features(int n_features, int mtry, int *out_features, lcg_state_t *rng)`

Fisher-Yates partial shuffle: sample `mtry` unique features from [0,
n_features). If `mtry >= n_features`, copies all features in order.

#### `void argsort_double(double *values, int *indices, int n)`

qsort-based argsort for pre-sorting feature values.

---

### fangorn.c — Stata Plugin Entry

#### `STDLL stata_call(int argc, char *argv[])`

**Variable layout** (1-based Stata indices):

| Range | Content |
|-------|---------|
| 1 .. n_features | Features (indepvars) |
| n_features + 1 | Dependent variable (depvar) |
| n_features + 2 | Target (if ntarget > 0) |
| n_features + 2 + ntarget .. + ngroup | Group vars (if ngroup > 0) |
| n_features + 2 + ntarget + ngroup | Result (prediction output) |
| n_features + 3 + ntarget + ngroup | leaf_id (leaf node ID) |
| n_features + 4 + ntarget + ngroup | touse (0/1 marker) |

**Flow**:
1. Parse argv options (nfeatures, ntarget, ngroup, nclasses, ntree, maxdepth,
   minsamplessplit, minsamplesleaf, minimpuritydecrease, relimpdec,
   maxleafnodes, seed, mtry, criterion, type, mermaid, featurenames)
2. Count touse == 1 observations
3. Load features, y, target into C arrays
4. Build training set: target == 0 (or all if no target)
5. Pre-sort indices
6. Build single tree (`ntree=1`) or random forest (`ntree>1`)
7. Predict for ALL touse observations, write result + leaf_id
8. Free memory

---

## Variable Layout

| Position | Variable | Description |
|----------|----------|-------------|
| 1..p | indepvars | Features (X) |
| p+1 | depvar | Target (y) |
| p+2 | target (opt) | 0=train, 1=test |
| p+3 .. p+2+g | group (opt) | Group variables |
| p+3+g | result | Prediction output |
| p+4+g | leaf_id | Leaf node ID (heap-style) |
| p+5+g | touse | 0/1 marker |

p = #features, g = #group vars.

---

## Mermaid Export

```stata
fangorn y x1 x2, generate(pred) mermaid(tree.md)
```

Output format:
- Internal nodes: `N{id}[feature ≤ val<br/>n=N<br/>gain=G]`
- Leaves (classify): `N{id}[[class=C<br/>n=N<br/>impurity=I]]`
- Leaves (regress): `N{id}[[predict=V<br/>n=N<br/>MSE=M]]`

---

## Reproducibility

fangorn is fully deterministic when the same `seed()` is specified. Tested with
10 consecutive runs:

| Test | Configuration | Result |
|------|--------------|--------|
| **CV depth selection 10-run** | single tree, CV folds=10, seed=12345 | PASS (bit-identical) |
| **RF 10-run (ntree=10)** | seed=42, 10 runs | PASS (bit-identical predictions) |
| **RF OOB error 10-run** | 10 runs, OOB error identical | PASS (0.232000 all 10 runs) |

### Single Tree (nproc(1) vs nproc(16))

Run: `stata -b do test/fangorn/test_fangorn_phase1.do`

Test environment: 16-core CPU, Stata 18 MP. Timed via `clock()` (1s resolution).
n=10000, 10 features, classification (Gini/Entropy) + regression (MSE).

| Task | 1-core (ms) | 16-core (ms) | Speedup |
|------|:-----------:|:------------:|:-------:|
| Gini | 4,000 | 1,000 | **4.0×** |
| Entropy | 6,000 | 1,000 | **6.0×** |
| MSE (regression) | 9,000 | 2,000 | **4.5×** |

### Random Forest (nproc(1) vs nproc(16))

Run: `stata -b do test/fangorn/test_fangorn_phase2.do`

ntree=100, n=10000, 10 features.

| Task | 1-core (ms) | 16-core (ms) | Speedup |
|------|:-----------:|:------------:|:-------:|
| RF Gini | 4,000 | 1,000 | **4.0×** |
| RF Entropy | 7,000 | 1,000 | **7.0×** |
| RF MSE (regression) | 9,000 | 1,000 | **9.0×** |

Key observations:

- **Single tree**: near-linear speedup on 16 cores (up to 6× for entropy).
- **Random Forest**: tree construction is embarrassingly parallel via
  `#pragma omp parallel for schedule(dynamic, 1)` — Entropy and MSE achieve
  7-9× speedup.
- OpenMP thread count controlled via `nproc(#)` option (default 16).
- The `nproc()` option is passed to the C plugin which calls
  `omp_set_num_threads()`, overriding the `UTILS_OMP_SET_NTHREADS()` default
  from `src/utils.h`.

---

## Benchmarks

Unified benchmark suite at `test/fangorn/benchmark/`:
- **10,000 observations**, 12 features (5 continuous + 7 one-hot dummies from 2 categorical variables)
- Complex non-linear DGP with interactions between continuous and categorical variables
- 5-class classification + regression tasks
- Reports computation speed for both fangorn and sklearn

Run:
```bash
python test/fangorn/benchmark/test_benchmark.py
stata -e do test/fangorn/benchmark/test_fangorn_benchmark.do
```

Results are written to `test/fangorn/benchmark/README.md` after execution.
