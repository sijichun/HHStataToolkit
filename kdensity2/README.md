# kdensity2 — Technical Documentation

## Overview

`kdensity2` is a Stata plugin for kernel density estimation (KDE) written in C. It supports one-dimensional and multivariate density estimation with target split (`target=0` for training, `target=1` for test), multi-dimensional grouped estimation, and cross-validated bandwidth selection.

---

## Mathematical Principles

### 1D Kernel Density Estimation

Given a set of training observations $X_1, X_2, \ldots, X_{n_{\text{train}}}$, the kernel density estimate at point $x$ is:

$$
\hat{f}_h(x) = \frac{1}{n_{\text{train}} \cdot h} \sum_{i=1}^{n_{\text{train}}} K\left(\frac{x - X_i}{h}\right)
$$

where:

- $K(\cdot)$ is the kernel function (a symmetric, non-negative, unit-integral smoothing function)
- $h$ is the bandwidth (smoothing parameter)
- $n_{\text{train}}$ is the number of training observations

The estimator places a scaled kernel at each training data point and averages them. The bandwidth $h$ controls the degree of smoothing: smaller $h$ produces a wiggly estimate, larger $h$ produces a smoother estimate.

### Multivariate Kernel Density Estimation (Product Kernel)

For a $D$-dimensional point $\mathbf{x} = (x_1, x_2, \ldots, x_D)$, the product kernel density estimate is:

$$
\hat{f}_H(\mathbf{x}) = \frac{1}{n_{\text{train}} \cdot |H|} \sum_{i=1}^{n_{\text{train}}} \prod_{d=1}^{D} K\left(\frac{x_d - X_{id}}{h_d}\right)
$$

where:

- $D$ is the dimension of the density variables
- $H = \text{diag}(h_1, h_2, \ldots, h_D)$ is the diagonal bandwidth matrix
- $|H| = h_1 \cdot h_2 \cdot \ldots \cdot h_D$ is the product of bandwidths (the "volume" of the bandwidth matrix)

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

where $s$ is the sample standard deviation and IQR is the interquartile range. This rule assumes the underlying distribution is approximately Gaussian and optimizes the mean integrated squared error (MISE) under that assumption.

#### Scott's Rule (1D)

$$
h = 1.06 \times s \times n^{-1/5}
$$

A simpler rule that uses only the standard deviation. Optimal for Gaussian data but less robust to outliers than Silverman's rule.

#### Multivariate Generalization

For $D$-dimensional data, both rules generalize to:

$$
h_d = s_d \times n^{-1/(D+4)}
$$

where $s_d$ is the standard deviation in dimension $d$. For Silverman's rule, $\min(s_d, \text{IQR}_d / 1.34)$ replaces $s_d$.

#### Cross-Validation (CV)

The plugin supports $K$-fold likelihood cross-validation for bandwidth selection. The CV score for a candidate bandwidth $h$ is:

$$
\text{CV}(h) = \frac{1}{n} \sum_{k=1}^{K} \sum_{i \in \mathcal{F}_k} \log \hat{f}_{-k}(X_i)
$$

where $\mathcal{F}_k$ is the $k$-th fold and $\hat{f}_{-k}$ is the density estimated using all data except $\mathcal{F}_k$. The bandwidth maximizing this score is selected.

The grid search proceeds as follows:

1. Compute the Silverman bandwidth $h_0$ as the reference
2. Generate a log-scale grid: $\log h_j = \log h_0 + j \cdot 0.05$, for $j = -20, -19, \ldots, 19, 20$
3. This produces 41 candidate bandwidths centered on $h_0$
4. Evaluate $\text{CV}(h_j)$ for each candidate and select the maximizer

For multivariate CV, all bandwidths are scaled proportionally: $\mathbf{h}_j = \mathbf{h}_0 \times \exp(j \cdot 0.05)$.

---

## C Code Architecture

### File Structure

```
HHStataToolkit/
├── src/
│   ├── stplugin.h/c     — Stata plugin interface (official, do not modify)
│   ├── utils.h/c         — Shared utilities (kernels, bandwidth, I/O, OMP init)
├── kdensity2/
│   ├── kdensity2.c       — This file: KDE-specific implementation
│   ├── kdensity2.ado     — Stata command wrapper
│   ├── kdensity2.plugin  — Compiled binary
│   ├── kdensity2.sthlp   — Stata help file
│   └── README.md         — This file
```

### Function Reference

#### Density Evaluation

##### `kde_eval_1d`

```c
static double kde_eval_1d(double x, double *train_data, int n_train,
                           double h, int kernel_type)
```

**Purpose**: Evaluate the 1D kernel density at a single point $x$.

**Parameters**:
- `x`: evaluation point
- `train_data`: flat array of training observations $[X_0, X_1, \ldots, X_{n-1}]$
- `n_train`: number of training observations
- `h`: bandwidth
- `kernel_type`: kernel function selector (`KERNEL_GAUSSIAN`, `KERNEL_EPANECHNIKOV`, etc.)

**Algorithm**:
1. Retrieve the kernel function $K$ via `get_kernel_1d(kernel_type)`
2. For each training observation $X_i$, compute the scaled distance $u = (x - X_i) / h$
3. Accumulate $\sum K(u)$
4. Normalize by $n_{\text{train}} \cdot h$

**Complexity**: $O(n_{\text{train}})$ per evaluation point.

---

##### `kde_eval_mv`

```c
static double kde_eval_mv(double *x, double **train_data, int n_train,
                           int dim, double *h, int kernel_type)
```

**Purpose**: Evaluate the multivariate product kernel density at a single point $\mathbf{x}$.

**Parameters**:
- `x`: evaluation point vector of length `dim`
- `train_data`: training data matrix, shape `[dim][n_train]`
- `n_train`: number of training observations
- `dim`: number of dimensions
- `h`: bandwidth vector of length `dim`
- `kernel_type`: kernel function selector

**Algorithm**:
1. Compute the product of bandwidths: $h_{\text{prod}} = \prod_{d=1}^{\dim} h_d$
2. For each training observation $j$:
   - For each dimension $d$, compute $u_d = (x_d - X_{d,j}) / h_d$
   - Compute the product kernel $\prod_{d=1}^{\dim} K(u_d)$
   - Accumulate the product
3. Normalize by $n_{\text{train}} \cdot h_{\text{prod}}$

**OpenMP**: The training loop is parallelized with `#pragma omp parallel for reduction(+:sum)`.

**Complexity**: $O(n_{\text{train}} \cdot \dim)$ per evaluation point.

---

#### Bandwidth Selection

##### `compute_bandwidth`

```c
static void compute_bandwidth(double **train_data, int n_train, int dim,
                               int bandwidth_rule, double manual_h,
                               double *h)
```

**Purpose**: Compute bandwidth(s) using Silverman's rule, Scott's rule, or a manual value.

**Parameters**:
- `train_data`: training data matrix `[dim][n_train]`
- `n_train`: number of training observations
- `dim`: number of dimensions
- `bandwidth_rule`: `BANDWIDTH_SILVERMAN`, `BANDWIDTH_SCOTT`, or `BANDWIDTH_MANUAL`
- `manual_h`: user-supplied bandwidth (used when `BANDWIDTH_MANUAL`)
- `h`: output bandwidth vector of length `dim`

**Behavior**:
- For `BANDWIDTH_SILVERMAN`: calls `silverman_bandwidth()` (1D) or `silverman_bandwidth_mv()` (MV)
- For `BANDWIDTH_SCOTT`: calls `scott_bandwidth()` (1D) or `scott_bandwidth_mv()` (MV)
- For `BANDWIDTH_MANUAL`: sets all dimensions to `manual_h`

---

##### `cv_score_1d`

```c
static double cv_score_1d(double *data, int n, double h,
                           int kernel_type, int k)
```

**Purpose**: Compute the $K$-fold log-likelihood CV score for a given bandwidth in 1D.

**Parameters**:
- `data`: the training data (1D array)
- `n`: number of observations
- `h`: candidate bandwidth
- `kernel_type`: kernel function
- `k`: number of folds

**Algorithm**:
For each fold $f = 0, \ldots, k-1$:
1. Split: test fold $\mathcal{F}_f = [f \cdot n/k, (f+1) \cdot n/k)$, training set = complement
2. For each test point $X_i \in \mathcal{F}_f$:
   - Compute $\sum_{j \notin \mathcal{F}_f} K((X_i - X_j) / h)$
   - Normalize by $n_{\text{train}} \cdot h$ and take the log
3. Sum across test points and folds

**Returns**: $\frac{1}{n} \sum_f \sum_{i \in \mathcal{F}_f} \log \hat{f}_{-f}(X_i)$

**Complexity**: $O(k \cdot (n/k) \cdot (n - n/k)) = O(n^2)$ per bandwidth candidate.

---

##### `cv_score_mv`

```c
static double cv_score_mv(double **data, int n, int dim, double *h,
                           int kernel_type, int k)
```

**Purpose**: Multivariate version of `cv_score_1d`. Same K-fold logic but uses product kernel evaluation within each fold.

**Complexity**: $O(n^2 \cdot \dim)$ per bandwidth candidate.

---

##### `cv_select_1d`

```c
static double cv_select_1d(double *data, int n, int kernel_type,
                            int k, double ref_h)
```

**Purpose**: Select the optimal 1D bandwidth by grid search with CV.

**Parameters**:
- `data`: training data
- `n`: number of observations
- `kernel_type`: kernel function
- `k`: number of CV folds
- `ref_h`: reference bandwidth (Silverman rule)

**Algorithm**:
1. Generate 41 candidate bandwidths on a log grid centered at `ref_h` with step 0.05
2. Evaluate `cv_score_1d` for each candidate
3. Return the candidate with the highest score

---

##### `cv_select_mv`

```c
static void cv_select_mv(double **data, int n, int dim, int kernel_type,
                          int k, double *ref_h, double *h_out)
```

**Purpose**: Select the optimal multivariate bandwidth by grid search with CV.

**Algorithm**:
1. Compute the geometric mean of the reference bandwidths: $\log \bar{h} = \frac{1}{\dim} \sum \log h_d$
2. Generate a log grid around $\bar{h}$ (41 candidates, step 0.05)
3. For each candidate, scale all dimensions proportionally: $h_d = \text{ref}_d \cdot (\text{candidate} / \bar{h})$
4. Evaluate `cv_score_mv` for each candidate
5. Return the candidate with the highest score

---

##### `compute_bandwidth_cv`

```c
static void compute_bandwidth_cv(double **train_data, int n_train, int dim,
                                  int bandwidth_rule, double manual_h,
                                  int cv_folds, int kernel_type,
                                  double *h)
```

**Purpose**: Unified bandwidth selector that dispatches to either CV grid search or the classic rules.

**Behavior**:
- If `bandwidth_rule == BANDWIDTH_CV`: calls `cv_select_1d` or `cv_select_mv`
- Otherwise: calls `compute_bandwidth` (delegates to Silverman/Scott/manual)

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

Stores the set of unique multi-dimensional group combinations.

---

##### `init_unique_groups`

```c
static unique_groups_t* init_unique_groups(int ngroup)
```

**Purpose**: Allocate and initialize the group storage structure. Pre-allocates space for `MAX_GROUPS` (1000) unique combinations.

---

##### `free_unique_groups`

```c
static void free_unique_groups(unique_groups_t *ug)
```

**Purpose**: Free all memory associated with a `unique_groups_t`.

---

##### `match_group_combo`

```c
static int match_group_combo(double **group, int ngroup, int obs_idx,
                               double *combo)
```

**Purpose**: Test whether observation `obs_idx` belongs to a given group combination. Returns 1 if all group variables match within tolerance $10^{-9}$, 0 otherwise.

---

##### `collect_unique_groups`

```c
static void collect_unique_groups(double **group, int n_obs, int ngroup,
                                   unique_groups_t *out)
```

**Purpose**: Scan all observations and record each unique combination of group variable values.

**Algorithm**: For each observation, compare its group combination against all previously found combinations using `match_group_combo`. If not found, add to the list.

---

#### Main Entry Point

##### `stata_call`

```c
STDLL stata_call(int argc, char *argv[])
```

**Purpose**: Stata plugin entry point. Called when Stata executes `plugin call _kdensity2_plugin ...`.

**Argument parsing**:
- `kernel(name)` — kernel function type
- `bw(method)` — bandwidth rule (`silverman`, `scott`, number, `cv`, `cv5`, etc.)
- `ndensity(N)` — number of density variables
- `ntarget(N)` — 0 or 1 (whether target variable is provided)
- `ngroup(N)` — number of group variables
- `minobs(N)` — minimum observations per group

**Data flow**:

```
┌─────────────────────────────────────────────────────────────┐
│ Stata Variables                                             │
│  1..ndensity  : density variables                            │
│  ndensity+1   : target variable (if ntarget>0)              │
│  ndensity+ntarget+1.. : group variables (if ngroup>0)       │
│  last-1       : result variable                             │
│  last         : touse indicator (0/1)                        │
└─────────────────────────────────────────────────────────────┘
                               ↓
                   Read all data into C arrays
                    (density_data, target, group)
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
           For each unique         1. Count training obs
           combination:               (target=0 or all)
                      ↓             2. Extract train data
           1. Count obs in          3. compute_bandwidth_cv
              this group            4. Evaluate density for
           2. If < minobs → skip       ALL observations
           3. Count training
              obs (target=0)
           4. compute_bandwidth_cv
           5. Evaluate density for
              ALL obs in group
                               ↓
                    ┌─────────────────────┐
                    │ Write result to      │
                    │ Stata output var     │
                    │ (only in_if obs)     │
                    └─────────────────────┘
```

**Key behaviors**:
- Results are initialized to `SV_missval` (Stata's missing value `.`) before computation; skipped groups remain missing
- Only observations with `in_if = 1` (the `touse` variable, reflecting `if()`/`in()` conditions) are included in training and evaluation
- `target=0` observations form the training set; `target=1` observations get density predictions but do not contribute to bandwidth estimation
- In grouped estimation, each group uses only its own training data, producing group-specific bandwidths

---

## Variable Layout in Stata

The variables are passed to the plugin via `plugin_vars` in the ado file, in this order:

| Index Range | Content |
|-------------|---------|
| `1 .. ndensity` | Density variables |
| `ndensity + 1` | Target variable (if `target()` specified) |
| `ndensity + ntarget + 1` | Group variables (if `group()` specified) |
| `ndensity + ntarget + ngroup + 1` | Result (output) variable |
| `ndensity + ntarget + ngroup + 2` | `touse` variable (internal) |

---

## Notes

- The plugin evaluates density at **data points only** — no grid generation
- `MAX_DIM = 10`: maximum number of density variables
- `MAX_GROUPS = 1000`: maximum number of unique group combinations
- `MAX_GRID_POINTS = 10000`: unused (grid generation was removed)
- OpenMP is enabled by default with 8 threads; override via `OMP_NUM_THREADS`
- Group variables are read as `double` directly from Stata; string group variables are encoded to numeric in the ado layer via `egen group()`
