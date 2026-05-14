# nwreg — Technical Documentation

## Overview

`nwreg` is a Stata plugin for Nadaraya-Watson kernel regression written in C. It estimates the conditional mean $\mathbb{E}[Y | X]$ at each observation using kernel-weighted local averaging. Supports one-dimensional and multivariate regressors with target split (`target=0` for training, `target=1` for test), multi-dimensional grouped estimation, and cross-validated bandwidth selection.

---

## Mathematical Principles

### Nadaraya-Watson Estimator

Given a set of training observations $(X_1, Y_1), (X_2, Y_2), \ldots, (X_{n_{\text{train}}}, Y_{n_{\text{train}}})$, the Nadaraya-Watson estimate at point $x$ is:

$$
\hat{m}_h(x) = \frac{\sum_{i=1}^{n_{\text{train}}} K_h(x - X_i) \cdot Y_i}{\sum_{i=1}^{n_{\text{train}}} K_h(x - X_i)}
$$

where:

- $K_h(u) = K(u / h)$ is the scaled kernel function
- $K(\cdot)$ is a symmetric, non-negative kernel function
- $h$ is the bandwidth (smoothing parameter)
- $n_{\text{train}}$ is the number of training observations

The estimator is a local weighted average: observations closer to $x$ (in terms of $X$) receive higher weight. The bandwidth $h$ controls the degree of smoothing: smaller $h$ produces a more wiggly estimate, larger $h$ produces a smoother estimate.

### Multivariate Product Kernel

For a $D$-dimensional regressor vector $\mathbf{x} = (x_1, x_2, \ldots, x_D)$, the product kernel extension uses a separate bandwidth for each dimension:

$$
\hat{m}_H(\mathbf{x}) = \frac{\sum_{i=1}^{n_{\text{train}}} \left[\prod_{d=1}^{D} K\left(\frac{x_d - X_{id}}{h_d}\right)\right] \cdot Y_i}{\sum_{i=1}^{n_{\text{train}}} \prod_{d=1}^{D} K\left(\frac{x_d - X_{id}}{h_d}\right)}
$$

where:

- $D$ is the number of regressors
- $H = \text{diag}(h_1, h_2, \ldots, h_D)$ is the diagonal bandwidth matrix
- Each dimension $d$ has its own bandwidth $h_d$

The product kernel assumes local independence across dimensions, which simplifies computation while giving reasonable results for most applications.

### Kernel Functions

Five kernel functions are supported. All satisfy $\int K(u)\,du = 1$.

| Kernel | Formula $K(u)$ | Support |
|--------|---------------|---------|
| Gaussian | $\frac{1}{\sqrt{2\pi}} e^{-u^2/2}$ | $(-\infty, \infty)$ |
| Epanechnikov | $\frac{3}{4}(1 - u^2)$ | $[-1, 1]$ |
| Uniform | $\frac{1}{2}$ | $[-1, 1]$ |
| Triweight | $\frac{35}{32}(1 - u^2)^3$ | $[-1, 1]$ |
| Cosine | $\frac{\pi}{4}\cos\left(\frac{\pi u}{2}\right)$ | $[-1, 1]$ |

The Gaussian kernel is the default and the only one with unbounded support. The bounded kernels (Epanechnikov, Uniform, Triweight, Cosine) are computationally more efficient since the kernel evaluation can skip observations where $|u| > 1$.

### Bandwidth Selection

#### Silverman's Rule of Thumb (1D)

$$
h = 0.9 \times \min\left(s, \frac{\text{IQR}}{1.34}\right) \times n^{-1/5}
$$

where $s$ is the sample standard deviation and IQR is the interquartile range.

#### Scott's Rule (1D)

$$
h = 1.06 \times s \times n^{-1/5}
$$

A simpler rule that uses only the standard deviation.

#### Multivariate Generalization

For $D$-dimensional regressors, both rules generalize to:

$$
h_d = s_d \times n^{-1/(D+4)}
$$

where $s_d$ is the standard deviation in dimension $d$. For Silverman's rule, $\min(s_d, \text{IQR}_d / 1.34)$ replaces $s_d$.

#### Cross-Validation (CV)

The plugin supports $K$-fold cross-validation for bandwidth selection minimizing mean squared prediction error (MSE). The CV score for a candidate bandwidth $h$ is:

$$
\text{CV}(h) = -\frac{1}{n} \sum_{k=1}^{K} \sum_{i \in \mathcal{F}_k} \left(Y_i - \hat{m}_{-k}(X_i)\right)^2
$$

where:

- $\mathcal{F}_k$ is the $k$-th fold (test set)
- $\hat{m}_{-k}$ is the NW estimate using all data except $\mathcal{F}_k$
- The score returns **negative MSE** so that maximising the score = minimising MSE, consistent with the `kdensity2` convention of "larger = better"

The grid search proceeds as follows:

1. Compute the Silverman bandwidth $h_0$ as the reference
2. For 1D: generate a log-scale grid: $\log h_j = \log h_0 + j \cdot 0.05$, for $j = -\text{ngrids}, \ldots, \text{ngrids}$
3. For MV: compute the geometric mean $\bar{h} = \exp(\frac{1}{D}\sum \log h_d)$, generate log grid around $\bar{h}$, and scale all bandwidths proportionally
4. Evaluate $\text{CV}(h_j)$ for each candidate and select the maximizer

#### Standard Error Estimation

When `se(varname)` is specified, the plugin computes a heteroskedasticity-robust local standard error for each prediction.  The formula is:

$$
\widehat{SE}(\hat{m}(x)) = \frac{\sqrt{\sum_{i=1}^{n_{\text{train}}} K_h(x - X_i)^2 \cdot \tilde{\epsilon}_i^2}}{\sum_{i=1}^{n_{\text{train}}} K_h(x - X_i)}
$$

where $\tilde{\epsilon}_i$ is a bias-corrected residual at training point $X_i$.  Three methods for computing $\tilde{\epsilon}_i$ are available via the `se_type()` option:

| `se_type` | Method | Bias | Speed |
|-----------|--------|------|-------|
| 0 | Full-sample residual: $\tilde{\epsilon}_i = Y_i - \hat{m}(X_i)$ | Slight downward bias | Fastest |
| 1 | Leave-one-out residual: $\tilde{\epsilon}_i = Y_i - \hat{m}_{-i}(X_i)$ | Unbiased | ~2x |
| 2 | Leverage-corrected residual: $\tilde{\epsilon}_i = (Y_i - \hat{m}(X_i)) / (1 - L_{ii})$ | Nearly unbiased | Minimal overhead |

**Leverage correction** (default, `se_type=2`):
The leverage of observation $i$ in NW regression is
$$L_{ii} = \frac{K(0)}{\sum_{j=1}^{n_{\text{train}}} K_h(X_i - X_j)}$$
for 1D, and $L_{ii} = K(0)^{\dim} / \sum_j w_j$ for multivariate.  Dividing by $(1 - L_{ii})$ corrects the well-known downward bias from using in-sample fitted values (analogous to the HC3 correction in linear regression; MacKinnon & White, 1985).

**Leave-one-out** (`se_type=1`):
The leave-one-out fitted value is computed efficiently without re-running the full NW estimator:
$$\hat{m}_{-i}(X_i) = \frac{\sum_{j \neq i} K_h(X_i - X_j) Y_j}{\sum_{j \neq i} K_h(X_i - X_j)} = \frac{\text{num} - K(0) \cdot Y_i}{\text{den} - K(0)}$$
where `num` and `den` are the full-sample numerator and denominator.  This is the most accurate finite-sample method (Fan & Gijbels, 1996, §4.2).

**Key properties**:
- The standard error is computed for **all** observations that receive predictions, including both `target=0` (training) and `target=1` (test) observations.
- Residuals are computed on the training set only; the same residual vector is used for all evaluation points within a group.
- The estimator is locally weighted: observations closer to the evaluation point $x$ contribute more to the variance estimate.
- It is robust to heteroskedasticity because it uses squared residuals rather than assuming a constant error variance.

**Computation steps** (per group, if grouping is used):
1. Fit the NW estimator on the training data and compute bandwidth $h$.
2. Compute adjusted residuals $\tilde{\epsilon}_i$ for each training point using the chosen `se_type`.
3. For every observation $j$ in the group (training or test), evaluate:
   - Prediction $\hat{m}(x_j)$ via the usual NW formula.
   - Standard error using the adjusted residual vector from Step 2.

---

## C Code Architecture

### File Structure

```
HHStataToolkit/
├── src/
│   ├── stplugin.h/c     — Stata plugin interface (official, do not modify)
│   ├── utils.h/c         — Shared utilities (kernels, bandwidth, I/O, OMP init)
├── nwreg/
│   ├── nwreg.c           — This file: NW-specific implementation
│   ├── nwreg.ado         — Stata command wrapper
│   ├── nwreg.plugin      — Compiled binary
│   ├── nwreg.sthlp       — Stata help file
│   └── README.md         — This file
```

All kernel functions, bandwidth selectors, statistical utilities, and memory helpers used by `nwreg` are defined in `src/utils.c` / `src/utils.h`. See `kdensity2/README.md` for the shared utility API reference.

### Function Reference

#### NW Evaluation

##### `nw_eval_1d`

```c
static double nw_eval_1d(double x, double *train_x, double *train_y,
                          int n_train, double h, int kernel_type)
```

**Purpose**: Evaluate the Nadaraya-Watson conditional mean at a single 1D point $x$.

**Parameters**:
- `x`: evaluation point (scalar regressor value)
- `train_x`: flat array of training regressor values $[X_0, X_1, \ldots, X_{n-1}]$
- `train_y`: flat array of training response values $[Y_0, Y_1, \ldots, Y_{n-1}]$
- `n_train`: number of training observations
- `h`: bandwidth
- `kernel_type`: kernel function selector (`KERNEL_GAUSSIAN`, `KERNEL_EPANECHNIKOV`, etc.)

**Algorithm**:
1. Retrieve the kernel function $K$ via `get_kernel_1d(kernel_type)`
2. For each training observation $i$, compute scaled distance $u = (x - X_i) / h$
3. Accumulate numerator $\sum K(u) \cdot Y_i$ and denominator $\sum K(u)$
4. Return numerator / denominator, or `SV_missval` if denominator is zero

**Complexity**: $O(n_{\text{train}})$ per evaluation point.

---

##### `nw_eval_mv`

```c
static double nw_eval_mv(double *x, double **train_x, double *train_y,
                          int n_train, int dim, double *h, int kernel_type)
```

**Purpose**: Evaluate the NW conditional mean at a single multivariate point $\mathbf{x}$.

**Parameters**:
- `x`: evaluation point vector of length `dim`
- `train_x`: training regressor matrix, shape `[dim][n_train]`
- `train_y`: training response array of length `n_train`
- `n_train`: number of training observations
- `dim`: number of regressors
- `h`: bandwidth vector of length `dim`
- `kernel_type`: kernel function selector

**Algorithm**:
1. For each training observation $j$:
   - For each dimension $d$, compute $u_d = (x_d - X_{d,j}) / h_d$
   - Compute product kernel $w_j = \prod_{d=1}^{\dim} K(u_d)$
   - Accumulate numerator $\sum w_j \cdot Y_j$ and denominator $\sum w_j$
2. Return numerator / denominator, or `SV_missval` if denominator is zero

**OpenMP**: The training loop is parallelized with `#pragma omp parallel for reduction(+:num, den)`.

**Complexity**: $O(n_{\text{train}} \cdot \dim)$ per evaluation point.

---

##### `nw_eval_1d_with_se`

```c
static double nw_eval_1d_with_se(double x, double *train_x, double *train_y,
                                  double *se_resid, int n_train, double h,
                                  int kernel_type, double *se)
```

**Purpose**: Evaluate the NW conditional mean and its heteroskedasticity-robust standard error at a single 1D point $x$.

**Parameters**:
- `x`: evaluation point (scalar regressor value)
- `train_x`: flat array of training regressor values
- `train_y`: flat array of training response values
- `se_resid`: pre-computed adjusted residuals $\tilde{\epsilon}_i$ (length `n_train`); computed by `compute_se_residuals_1d`
- `n_train`: number of training observations
- `h`: bandwidth
- `kernel_type`: kernel function selector
- `se`: output pointer for the standard error

**Algorithm**:
1. For each training observation $i$:
   - Compute weight $w_i = K((x - X_i) / h)$
   - Accumulate numerator $\sum w_i Y_i$ and denominator $\sum w_i$
   - Accumulate variance numerator $\sum w_i^2 \tilde{\epsilon}_i^2$
2. Prediction = numerator / denominator
3. Standard error = $\sqrt{\sum w_i^2 \tilde{\epsilon}_i^2} \;/\; \sum w_i$
4. Return prediction, or `SV_missval` and set `*se = SV_missval` if denominator is zero

---

##### `nw_eval_mv_with_se`

```c
static double nw_eval_mv_with_se(double *x, double **train_x, double *train_y,
                                  double *se_resid, int n_train, int dim,
                                  double *h, int kernel_type, double *se)
```

**Purpose**: Multivariate version of `nw_eval_1d_with_se`.  Computes NW prediction and standard error using the product kernel.

**OpenMP**: The training loop is parallelized with `#pragma omp parallel for reduction(+:num, den, se_num)`.

**Complexity**: $O(n_{\text{train}} \cdot \dim)$ per evaluation point.

---

##### `compute_se_residuals_1d`

```c
static void compute_se_residuals_1d(double *train_x, double *train_y,
                                     int n_train, double h, int kernel_type,
                                     int se_type, double *se_resid)
```

**Purpose**: Compute bias-adjusted residuals $\tilde{\epsilon}_i$ for the standard error formula in 1D NW regression.

**Parameters**:
- `train_x`, `train_y`: training data arrays
- `n_train`: number of training observations
- `h`: bandwidth
- `kernel_type`: kernel selector
- `se_type`: 0=full-sample, 1=leave-one-out, 2=leverage-corrected
- `se_resid`: output array (length `n_train`)

**Behavior by `se_type`**:
- **0**: $\tilde{\epsilon}_i = Y_i - \hat{m}(X_i)$ (full-sample fit)
- **1**: $\tilde{\epsilon}_i = Y_i - \hat{m}_{-i}(X_i)$ (leave-one-out; computed analytically as $(\text{num} - K(0) Y_i) / (\text{den} - K(0))$)
- **2**: $\tilde{\epsilon}_i = (Y_i - \hat{m}(X_i)) / (1 - L_{ii})$ where $L_{ii} = K(0) / \text{den}$ (leverage correction)

---

##### `compute_se_residuals_mv`

```c
static void compute_se_residuals_mv(double **train_x, double *train_y,
                                     int n_train, int dim, double *h,
                                     int kernel_type, int se_type,
                                     double *se_resid)
```

**Purpose**: Multivariate version of `compute_se_residuals_1d`.

**Key difference**: Leverage uses the product kernel at zero: $L_{ii} = K(0)^{\dim} / \text{den}$.

---

#### Bandwidth Selection

##### `compute_bw`

```c
static void compute_bw(double **train_x, int n_train, int dim,
                        int bandwidth_rule, double manual_h, double *h)
```

**Purpose**: Compute bandwidth(s) using Silverman's rule, Scott's rule, or a manual value (non-CV path).

**Parameters**:
- `train_x`: training regressor matrix `[dim][n_train]`
- `n_train`: number of training observations
- `dim`: number of regressors
- `bandwidth_rule`: `BANDWIDTH_SILVERMAN`, `BANDWIDTH_SCOTT`, or `BANDWIDTH_MANUAL`
- `manual_h`: user-supplied bandwidth (used when `BANDWIDTH_MANUAL`)
- `h`: output bandwidth vector of length `dim`

**Behavior**:
- For `BANDWIDTH_SILVERMAN`: calls `silverman_bandwidth()` (1D) or `silverman_bandwidth_mv()` (MV)
- For `BANDWIDTH_SCOTT`: calls `scott_bandwidth()` (1D) or `scott_bandwidth_mv()` (MV)
- For `BANDWIDTH_MANUAL`: sets all dimensions to `manual_h`

---

##### `cv_mse_1d`

```c
static double cv_mse_1d(double *data_x, double *data_y, int n, double h,
                         int kernel_type, int k)
```

**Purpose**: Compute the $K$-fold cross-validated negative MSE for a given bandwidth in 1D NW regression.

**Parameters**:
- `data_x`: regressor data (1D array)
- `data_y`: response data (1D array)
- `n`: number of observations
- `h`: candidate bandwidth
- `kernel_type`: kernel function
- `k`: number of folds

**Algorithm**:
For each fold $f = 0, \ldots, k-1$:
1. Split: test fold $\mathcal{F}_f = [f \cdot n/k, (f+1) \cdot n/k)$, training set = complement
2. For each test point $i \in \mathcal{F}_f$:
   - Compute NW estimate using only training data
   - Accumulate squared residual $(Y_i - \hat{m}_{-f}(X_i))^2$
3. Sum across test points and folds

**Returns**: $-\frac{1}{n_{\text{test}}} \sum_f \sum_{i \in \mathcal{F}_f} (Y_i - \hat{m}_{-f}(X_i))^2$

Returns `-1e100` if no test observations were evaluated (degenerate case).

**Complexity**: $O(k \cdot (n/k) \cdot (n - n/k)) = O(n^2)$ per bandwidth candidate.

---

##### `cv_mse_mv`

```c
static double cv_mse_mv(double **data_x, double *data_y, int n, int dim,
                         double *h, int kernel_type, int k)
```

**Purpose**: Multivariate version of `cv_mse_1d`. Same $K$-fold logic but uses product kernel evaluation within each fold.

**Complexity**: $O(n^2 \cdot \dim)$ per bandwidth candidate.

---

##### `cv_select_1d`

```c
static double cv_select_1d(double *data_x, double *data_y, int n,
                            int kernel_type, int k, int ngrids, double ref_h)
```

**Purpose**: Select the optimal 1D bandwidth by grid search with CV.

**Parameters**:
- `data_x`: regressor data
- `data_y`: response data
- `n`: number of observations
- `kernel_type`: kernel function
- `k`: number of CV folds
- `ngrids`: number of grid candidates on each side of the reference
- `ref_h`: reference bandwidth (from Silverman's rule)

**Algorithm**:
1. Generate $(2 \cdot \text{ngrids} + 1)$ candidate bandwidths on a log grid centered at `ref_h` with step `CV_GRID_STEP = 0.05`
2. Evaluate `cv_mse_1d` for each candidate
3. Return the candidate with the highest score (least negative MSE)

---

##### `cv_select_mv`

```c
static void cv_select_mv(double **data_x, double *data_y, int n, int dim,
                          int kernel_type, int k, int ngrids,
                          double *ref_h, double *h_out)
```

**Purpose**: Select the optimal multivariate bandwidth by grid search with CV.

**Algorithm**:
1. Compute the geometric mean of reference bandwidths: $\log \bar{h} = \frac{1}{\dim} \sum \log h_d$
2. Generate $(2 \cdot \text{ngrids} + 1)$ log-spaced candidates around $\bar{h}$ with step 0.05
3. For each candidate scale factor $s_j$, scale all dimensions: $h_d^{(j)} = \text{ref}_d \cdot (s_j / \bar{h})$
4. Evaluate `cv_mse_mv` for each candidate set
5. Return the candidate set with the highest score

---

##### `compute_bw_cv`

```c
static void compute_bw_cv(double **train_x, double *train_y, int n_train,
                            int dim, int bandwidth_rule, double manual_h,
                            int cv_folds, int cv_grids, int kernel_type,
                            double *h)
```

**Purpose**: Unified bandwidth selector that dispatches to either CV grid search or the classic rules.

**Behavior**:
- If `bandwidth_rule == BANDWIDTH_CV`: calls `cv_select_1d` or `cv_select_mv` (requires access to both regressors AND response for CV)
- Otherwise: calls `compute_bw` (delegates to Silverman/Scott/manual)

**Note**: This function requires `train_y` in addition to `train_x`, unlike `compute_bw` which only needs regressor data. This is because CV evaluates prediction error, which requires the true responses.

---

#### Group Handling

##### `unique_groups_t`

```c
typedef struct {
    double **values;  // values[group_idx][var_idx]
    int count;        // number of unique combinations found
    int ngroup;       // number of group variables
} unique_groups_t;
```

Stores the set of unique multi-dimensional group combinations. The `values` matrix is pre-allocated for up to `MAX_GROUPS` (1000) combinations.

---

##### `init_unique_groups`

```c
static unique_groups_t* init_unique_groups(int ngroup)
```

**Purpose**: Allocate and initialize the group storage structure. Pre-allocates space for `MAX_GROUPS` (1000) unique combinations, each with `ngroup` variables.

**Returns**: Pointer to newly allocated `unique_groups_t`, or `NULL` on allocation failure.

---

##### `free_unique_groups`

```c
static void free_unique_groups(unique_groups_t *ug)
```

**Purpose**: Free all memory associated with a `unique_groups_t` structure, including the internal values matrix and the struct itself. Safe to call with `NULL`.

---

##### `match_group_combo`

```c
static int match_group_combo(double **group, int ngroup, int obs_idx,
                              double *combo)
```

**Purpose**: Test whether observation `obs_idx` belongs to a given group combination.

**Parameters**:
- `group`: group data matrix `[ngroup][n_obs]`
- `ngroup`: number of group variables
- `obs_idx`: observation index (0-based)
- `combo`: reference group combination vector of length `ngroup`

**Returns**: `1` if all group values match within tolerance $10^{-9}$, `0` otherwise.

---

##### `collect_unique_groups`

```c
static void collect_unique_groups(double **group, int n_obs, int ngroup,
                                   unique_groups_t *out)
```

**Purpose**: Scan all observations and record each unique combination of group variable values.

**Algorithm**: For each observation, compare its group combination against all previously found combinations using `match_group_combo`. If not found (and `out->count < MAX_GROUPS`), add to the list.

---

#### Main Entry Point

##### `stata_call`

```c
STDLL stata_call(int argc, char *argv[])
```

**Purpose**: Stata plugin entry point. Called when Stata executes `plugin call _nwreg_plugin ...`.

**Argument parsing** (via `extract_option_value`):
- `kernel(name)` — kernel function type (`gaussian`, `epanechnikov`, `uniform`, `triweight`, `cosine`)
- `bw(method)` — bandwidth rule (`silverman`, `scott`, numeric value, or `cv`)
- `nreg(N)` — number of regressors (default: 1)
- `ntarget(N)` — 0 or 1 (whether a target variable is provided)
- `ngroup(N)` — number of group variables
- `nse(N)` — 0 or 1 (whether an SE output variable is provided)
- `se_type(N)` — SE residual method: 0=full-sample, 1=leave-one-out, 2=leverage-corrected (default: 2)
- `minobs(N)` — minimum observations per group (default: 0)
- `nfolds(N)` — number of CV folds (default: 10)
- `ngrids(N)` — CV grid candidates per side (default: 10)

**Data variable layout** (1-based Stata indices):

| Index Range | Content |
|-------------|---------|
| `1 .. nreg` | Regressors ($X$) |
| `nreg + 1` | Dependent variable ($Y$) |
| `nreg + 2 .. nreg + 1 + ntarget` | Target variable (if `ntarget > 0`) |
| `nreg + 2 + ntarget .. nreg + 1 + ntarget + ngroup` | Group variables (if `ngroup > 0`) |
| `nreg + 2 + ntarget + ngroup` | Result (output) variable |
| `nreg + 3 + ntarget + ngroup` | SE output variable (if `nse > 0`) |
| `nreg + 3 + ntarget + ngroup + nse` | `touse` variable (internal) |

**Execution flow**:

```
┌─────────────────────────────────────────────────────────────┐
│ Stata Variables                                              │
│  1..nreg       : regressors (X)                               │
│  nreg+1        : response (Y)                                 │
│  nreg+2..      : target (if ntarget>0)                        │
│  nreg+2+ntarget.. : group variables (if ngroup>0)             │
│  last-1-nse    : result variable                              │
│  last-nse      : SE variable (if nse>0)                       │
│  last          : touse indicator (0/1)                        │
└─────────────────────────────────────────────────────────────┘
                               ↓
                   Read all data into C arrays
                    (reg_data, y_data, target, group)
                               ↓
                    ┌─────────────────────┐
                    │  ngroup > 0?         │
                    └─────────┬───────────┘
                              │
                    Yes ──────┴────── No
                      ↓                   ↓
           collect_unique_          No grouping:
           groups(group, ...)       single-band estimation
                      ↓
           For each unique          1. Count training obs
           combination:                (target=0 or all)
                      ↓             2. Extract train data
           1. Count obs in          3. compute_bw_cv
              this group            4. Evaluate NW for
           2. If < minobs → skip       ALL obs
           3. Count training
              obs (target=0)
           4. compute_bw_cv
           5. Evaluate NW for
              ALL obs in group
                               ↓
                    ┌─────────────────────┐
                    │ Write result to      │
                    │ Stata output var     │
                    │ (only in_if obs)     │
                    └─────────────────────┘
```

**Key behaviors**:
- Results are initialized to `SV_missval` before computation; skipped groups (insufficient training data or filtered by `minobs`) remain missing
- Only observations with `in_if = 1` (the `touse` variable, reflecting `if()`/`in()` conditions) are included in training and evaluation
- `target=0` observations form the training set; `target=1` observations get predictions but do not contribute to bandwidth estimation or training
- In grouped estimation, each group uses only its own training data, producing group-specific bandwidths
- The group count is saved to Stata scalar `nwreg_ngroups` via `SF_scal_save`
- When `nse > 0`, standard errors are computed using a heteroskedasticity-robust local variance estimator based on training-set residuals (see "Standard Error Estimation" section above)

---

## Test Results

Test environment: 16-core CPU, Stata 18 MP.

### Reproducibility

All tests run 10 consecutive calls with identical parameters and compare pairwise differences.
Thread count is controlled via the `nproc()` option.

| Test | Configuration | Result | Tolerance |
|------|--------------|--------|-----------|
| **Silverman 10-run** | `nproc(1)` (single-core) | PASS | max diff < 1e-12 |
| **Silverman 10-run** | `nproc(16)` (multi-core) | PASS | max diff < 1e-12 |
| **CV 10-run** | `nproc(1)` (single-core) | PASS | max diff < 1e-10 |
| **CV 10-run** | `nproc(16)` (multi-core) | PASS | max diff < 1e-10 |
| **1-core vs 16-core** | Silverman | PASS | bit-identical (0.00e+00) |
| **1-core vs 16-core** | CV | PASS | bit-identical (0.00e+00) |

**Conclusion**: nwreg produces bit-identical results regardless of thread count for both Silverman and CV bandwidth selection. OpenMP parallelism does not introduce any numerical non-determinism.

### Performance

Measured on 16-core CPU, Stata 18 MP. Timed via `clock(c(current_time), "hms")`
(single iteration per N). All times in **milliseconds (ms)**.

Thread count is controlled via the `nproc()` option:
- 1-core: `nproc(1)`
- 16-core: `nproc(16)`

The benchmark uses a 3-variate DGP with heteroskedastic noise:

$$y = \sin(x_1) + 0.5 \cdot \log(|x_2| + 1) + 0.3 \cdot x_3^2 + \varepsilon,\quad
\varepsilon \sim N(0,\, 0.2 + 0.3 \cdot |x_1|)$$

#### Silverman Bandwidth (Gaussian kernel, 3-variate)

Single iteration per N.

| N        | CPU 1t (ms) | CPU 16t (ms) | Speedup |
|---------|:-----------:|:------------:|:-------:|
| 1,000   |       0.00¹ |        0.00¹ |      — |
| 5,000   |       0.00¹ |        0.00¹ |      — |
| 10,000  |    2000.00  |        0.00¹ |      — |
| 50,000  |   33000.00  |     3000.00  | **11.0×** |
| 100,000 |  132000.00  |    12000.00  | **11.0×** |

¹ Total wall time < 1 clock tick (1000 ms).

#### CV Bandwidth (Gaussian kernel, 5 folds × 5 grids)

CV is $O(N^2 \cdot \dim)$ per candidate. Smaller N range, single iteration.

| N       | CPU 1t (ms) | CPU 16t (ms) | Speedup |
|--------|:-----------:|:------------:|:-------:|
| 500    |       0.00¹ |        0.00¹ |      — |
| 1,000  |       0.00¹ |        0.00¹ |      — |
| 2,000  |    1000.00  |        0.00¹ |      — |
| 5,000  |    2000.00  |        0.00¹ |      — |
| 10,000 |    8000.00  |     1000.00  | **8.0×** |

Key observations:

- **Near-linear speedup**: Silverman at N=100K achieves **11.0×** speedup on
  16 cores for 3-variate NW regression (132s → 12s).
- At N < 10,000, total wall time is below `clock()` resolution (1 sec), giving
  `0.00` ms readings.
- The heteroskedastic DGP does not affect timing vs homoskedastic — cost depends
  only on N and $\dim$.
- The 3-variate benchmark is ≈ 3× more expensive per observation than 1D regression,
  due to product kernel evaluation over 3 dimensions.
- The `nproc()` option directly controls OpenMP thread count in the C plugin.

### GPU (Hidden Feature)

CUDA-accelerated GPU plugins (`nwreg_cuda.plugin`) are available as a hidden
feature. They are **not** built by default and the `gpu()` syntax option has
been removed from the user-facing ado wrapper. To use GPU acceleration:

```bash
make nwreg_cuda        # Build the CUDA plugin (requires nvcc)
```

The GPU plugin is loaded by passing `gpu(-1)` to the C plugin internally
(the ado wrapper now hardcodes this). Results are comparable to CPU within
float-precision tolerance (~1e-5).

### Running Tests

```bash
# Reproducibility (10-run, 1-core + multi-core, cross-comparison)
stata -b do test/nwreg/test_cpu_reproducibility.do

# Seed reproducibility (CV)
stata -b do test/nwreg/test_seed_reproducibility.do

# Simulation / functional tests
stata -b do test/nwreg/test_nwreg_simulation.do

# GPU reproducibility (requires CUDA plugin)
stata -b do test/nwreg/test_gpu_reproducibility.do
```

## Notes

- The plugin evaluates the conditional mean at **data points only** — no grid generation
- `MAX_DIM = 10`: maximum number of regressors (from `utils.h`)
- `MAX_GROUPS = 1000`: maximum number of unique group combinations
- `CV_GRID_STEP = 0.05`: log-scale step size for CV grid search
- OpenMP thread count controlled via `nproc(#)` option in the ado syntax; default is 16. Also overridable via `OMP_NUM_THREADS` environment variable.
- When `denominator == 0` (no training observations within kernel support of the evaluation point), the result is set to `SV_missval` (Stata missing value `.`)
- Group variables are read as `double` directly from Stata; string group variables are encoded to numeric in the ado layer via `egen group()`
- For CV bandwidth selection, the ado wrapper shuffles the data before calling the plugin to ensure randomized folds, then restores original sort order
- If `bw(cv)` is combined with grouped estimation, the shuffle is applied globally (not per-group); this is a known limitation
- GPU acceleration is a hidden feature: not built by default, not exposed in syntax. Build with `make nwreg_cuda` if needed.
