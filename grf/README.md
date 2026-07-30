# grf — Generalized Random Forest Stata Plugin

**Adapted from** [grf-labs/grf](https://github.com/grf-labs/grf) v2.6.1 (GPL-3.0).
The upstream GRF C++ core provides forest-based heterogeneous treatment effect
estimation (Athey, Tibshirani & Wager, 2019). This Stata plugin wraps that core
via a thin C++ adapter layer.

---

## Table of Contents

1. [Principles](#principles)
   - [Causal Forest Algorithm](#causal-forest-algorithm)
   - [Honest Splitting](#honest-splitting)
   - [Out-of-Bag Predictions](#out-of-bag-predictions)
   - [Orthogonalization](#orthogonalization)
   - [Variance Estimation](#variance-estimation)
2. [Stata Syntax](#stata-syntax)
3. [Data Structures](#data-structures)
4. [C++ Function Reference](#c-function-reference)
   - [grf_stata.cpp](#grf_statacpp---stata-plugin-entry)
   - [grf_stata_data.cpp](#grf_stata_datacpp---data-bridge)
   - [grf_stata_options.cpp](#grf_stata_optionscpp---option-parsing)
   - [grf_stata_output.cpp](#grf_stata_outputcpp---result-writeback)
5. [Variable Layout](#variable-layout)
6. [Test Results](#test-results)
7. [Benchmarks](#benchmarks)

---

## Principles

### Causal Forest Algorithm

GRF implements the generalized random forest framework of Athey, Tibshirani
and Wager (2019). For heterogeneous treatment effect (CATE) estimation, the
causal forest grows trees using gradient-based splitting:

1. **Subsample**: draw a subsample of the training data for each tree
2. **Split**: for each node, find the split that maximises heterogeneity in
   the treatment effect estimate
3. **Honest estimation**: use separate subsamples for split selection and
   leaf estimation
4. **Predict**: average the CATE estimates across all trees for each
   observation

### Honest Splitting

When `honesty(true)` (the default), the training subsample is split into two
parts: one for choosing splits and one for estimating leaf-level treatment
effects. This reduces overfitting and is required for valid confidence
intervals.

### Orthogonalization

The causal forest uses the "R-learner" framework (Nie & Wager, 2021):
- Fit nuisance models: `Y.hat = E[Y|X]`, `W.hat = E[W|X]`
- Center outcomes: `Y - Y.hat`, `W - W.hat`
- Train forest on centered residuals

When `yhat()` and `what()` are not provided, the ado wrapper estimates them
using internal regression forests.

### Out-of-Bag Predictions

Each tree is trained on a bootstrap sample. Observations not included in the
bootstrap (out-of-bag) receive predictions only from trees that did not use
them in training, providing unbiased CATE estimates.

### Variance Estimation

Variance is estimated using the "bootstrap of little bags" delta method,
which accounts for both tree-level and forest-level uncertainty. Requires
`ci_group_size >= 2`.

---

## Stata Syntax

```stata
grf depvar treatvar [indepvars], generate(newvar) [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `generate(newvar)` | CATE estimates (required) | — |
| `yhat(varname)` | Pre-computed E[Y\|X] | internal regression forest |
| `what(varname)` | Pre-computed E[W\|X] | internal regression forest |
| `weights(varname)` | Sample weights | equal |
| `cluster(varname)` | Cluster IDs | none |
| `equalizeclusterweights` | Equal-weight clusters | off |
| `ntree(#)` | Number of trees | 2000 |
| `samplefraction(#)` | Subsample fraction | 0.5 |
| `mtry(#)` | Features per split | auto (√p + 20) |
| `minnodesize(#)` | Minimum node size | 5 |
| `nohonesty` | Disable honest splitting | off (honesty on by default) |
| `honestyfraction(#)` | Honest split fraction | 0.5 |
| `nohonestyprune` | Don't prune empty leaves | off |
| `alpha(#)` | Max imbalance | 0.05 |
| `imbalancepenalty(#)` | Imbalance penalty | 0 |
| `nostabilizesplits` | No split stabilization | off |
| `cigroupsize(#)` | CI group size (≥2 for variance) | 2 |
| `vargenerate(newvar)` | Variance estimates | off |
| `oobgenerate(newvar)` | OOB CATE estimates | off |
| `seed(#)` | RNG seed | 12345 |
| `nproc(#)` | Thread count | 16 |
| `if(string)` / `in(string)` | Observation filters | all |

**Positional syntax**: `grf y w x1 x2 x3` — first variable = outcome,
second = treatment, remainder = covariates (at least one required).

---

## Data Structures

Variables are passed to the C++ plugin as a column-major `double` buffer
(`variables × observations`), wrapped by `grf::Data`. Column indices
follow a fixed layout (see [Variable Layout](#variable-layout) below).

```cpp
// Core data wrapper (from upstream GRF)
class Data {
    const double* data_ptr;     // column-major: [col * n_rows + row]
    size_t num_rows, num_cols;
    std::optional<std::vector<size_t>> outcome_index;
    std::optional<std::vector<size_t>> treatment_index;
    std::optional<size_t> instrument_index;
    // ...
};
```

The `ForestOptions` class bundles all tuning parameters:

```cpp
class ForestOptions {
    uint num_trees;        size_t ci_group_size;
    double sample_fraction; uint mtry;
    uint min_node_size;    bool honesty;
    double honesty_fraction; bool honesty_prune_leaves;
    double alpha;          double imbalance_penalty;
    uint num_threads;      uint random_seed;
    bool legacy_seed;      // false = thread-independent (default)
    std::vector<size_t> clusters;
    uint samples_per_cluster;
};
```

---

## C++ Function Reference

### grf_stata.cpp — Stata Plugin Entry

`STDLL stata_call(int argc, char *argv[])` — Main entry point:
1. Parses options via `grf_stata_options`
2. Routes to `run_regression` (nuisance fitting) or `run_causal` (CATE)
3. Handles exception safety — all C++ exceptions caught at the boundary

### grf_stata_data.cpp — Data Bridge

```cpp
bool build_training_data(n_total_vars, n_input_cols,
    touse_col_idx, outcome_idx, treatment_idx, ...,
    grf::Data*& out_data, vector<size_t>& row_map);
```
- Reads Stata variables via `SF_vdata()` into column-major buffer
- Selects training rows via touse marker
- Returns compact `grf::Data` with row mapping
- Skips missing-value checks on output columns

### grf_stata_options.cpp — Option Parsing

```cpp
bool parse_options(argc, argv, GrfOptions& opts, char* error_msg);
grf::ForestOptions build_forest_options(GrfOptions& opts, clusters);
```
- Extracts `key(value)` tokens from argv
- Defaults match R `causal_forest()` (ntree=2000, honesty=true, ...)
- `legacy_seed=false` for thread-independent reproducibility

### grf_stata_output.cpp — Result Writeback

```cpp
bool write_predictions_to_stata(predictions, row_map,
    output_col_idx, n_obs, char* error_msg);
```
- Writes CATE only for touse==1 observations
- Non-touse observations set to Stata missing

---

## Variable Layout

Plugin internal column order (1-based Stata indices):

| Position | Content | Input/Output |
|----------|---------|-------------|
| `1..p` | Features (`xvars`) | Input |
| `p+1` | Outcome (`y`) — centered when yhat provided | Input |
| `p+2` | Treatment (`w`) — centered when what provided | Input |
| `p+3` | `yhat()` estimate | Input |
| `p+4` | `what()` estimate | Input |
| `p+5` | `weights()` (1 if none) | Input |
| `p+6` | `cluster()` (unique id if none) | Input |
| `p+7` | `generate()` CATE | Output |
| `p+8` | `vargenerate()` variance | Output |
| `p+9` | `oobgenerate()` OOB CATE | Output |
| `p+10` | `touse` marker | Control |

The ado wrapper reorders user input `y w x1 x2 ...` to this layout before
calling the plugin. Output columns (`p+7` to `p+9`) are allowed to have
initial missing values.

---

## Test Results

All tests run on Linux x86_64, Stata 18 MP, R 4.3.1 + grf 2.6.1.

| Test | Result | Detail |
|------|--------|--------|
| `test_grf_basic` | ✅ | Smoke test: command loads, predictions non-missing, corr(y, pred) > 0.3 |
| `test_grf_seed_reproducibility` | ✅ | 10 runs with same seed → bit-identical (max diff < 1e-10) |
| `test_grf_cpu_reproducibility` | ✅ | nproc(1) vs nproc(4): small floating-point differences (expected) |
| `test_grf_honesty` | ✅ | Default and custom honesty fraction run without error |
| `test_grf_cluster` | ✅ | Numeric cluster and equalizeclusterweights succeed |
| `test_grf_oob` | ✅ | oobgenerate() creates output variable |
| `test_grf_variance` | ✅ | cigroupsize(2) + vargenerate() runs without error |
| `test_grf_orthogonalization` | ✅ | Both yhat/what → success; only yhat → error |
| Core C++ unit tests | ✅ | 3 suites, 8 cases, 19 assertions all pass |
| **R-vs-Stata parity** | **0.997 corr** | n=2000, identical data/seed/nuisance/mtry → near-identical CATE |

### R-vs-Stata Parity Details

| Metric | Value |
|--------|-------|
| Correlation (R vs Stata CATE) | **0.9974** |
| Mean absolute difference | 0.0320 |
| Max absolute difference | 0.1967 |
| Stata CATE range | [−0.174, 1.767] |
| R CATE range | [−0.160, 1.780] |

The 0.997 correlation demonstrates near-identical CATE estimates. The residual
difference (0.032 mean, 0.180 max) arises from RNG sequence divergence in
Poisson `mtry` sampling and bootstrap draws — C++ `std::mt19937_64` and R's
MT19937 produce different state from the same seed. Within R alone, running
on different platforms produces comparable differences.

---

## Benchmarks

Preliminary timing (single-threaded, n=2000, p=10, ntree=100):

| Task | Causal forest |
|------|:------------:|
| Training + OOB prediction | ~8 s (nproc=1) |

Multi-threaded speedup and larger-sample benchmarks are pending.

---

## Upstream

This plugin is a Stata adaptation of the **generalized random forests** package:

- **Repository**: [github.com/grf-labs/grf](https://github.com/grf-labs/grf)
- **Version**: 2.6.1
- **License**: GPL-3.0
- **Papers**:
  - Athey, Tibshirani & Wager (2019). Generalized Random Forests. *Annals of Statistics*, 47(2).
  - Wager & Athey (2018). Estimation and Inference of Heterogeneous Treatment Effects using Random Forests. *JASA*, 113(523).
  - Nie & Wager (2021). Quasi-Oracle Estimation of Heterogeneous Treatment Effects. *Biometrika*, 108(2).

## License

The grf Stata plugin's own code is licensed under GPL-3.0-or-later.
The vendored GRF C++ core is GPL-3.0; Eigen is MPL-2.0; StataCorp's
`stplugin.h/c` retain their original terms. See `COPYING` and `LICENSES.md`.
