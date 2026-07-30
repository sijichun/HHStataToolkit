# README4AI — HHStataToolkit: Command Reference for AI

> **Purpose**: Quick-reference guide describing every Stata command in this project, its syntax, options, return values, and usage examples. No C implementation details.

---

## Common Patterns (All Plugin Commands)

- **target(varname)**: `target=0` = training set, `target=1` = prediction set. Training observations determine bandwidth/model; all obs get predictions.
- **group(varlist)**: Multiple grouping variables supported natively. String vars auto-encoded to numeric. Max 50,000 unique combos.
- **if(exp) / in(range)**: Used as **string options** (not Stata qualifiers) due to Stata 18 bug. Example: `nwreg y x, generate(yhat) if(flag==1)`.
- **nproc(#)**: OpenMP threads (default 16). Bit-identical results regardless of thread count.

---

## 1. kdensity2 — Kernel Density Estimation

Estimate kernel density at each observation.

```stata
kdensity2 varlist [, options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `kernel(name)` | `gaussian`, `epanechnikov`, `uniform`, `triweight`, `cosine` | `gaussian` |
| `bw(method)` | `silverman`, `scott`, `cv`, or positive number | `silverman` |
| `target(varname)` | 0/1: 0=training, 1=test | all train |
| `group(varlist)` | Grouping variables | none |
| `gnormalize` | Scale group densities by sample shares (mixture scale) | off |
| `mincount(#)` | Skip groups with < # obs | 0 |
| `generate(newvar)` | Output density variable | `kdensity2` |
| `folds(#)` | CV folds | 10 |
| `grids(#)` | CV grid candidates per side | 10 |
| `nproc(#)` | OpenMP threads | 16 |
| `if(exp)` / `in(range)` | Observation filters | all |

```stata
* Basic 1D density
kdensity2 x, generate(d)

* CV bandwidth
kdensity2 x, bw(cv) folds(5) grids(15)

* Multivariate density with grouping
kdensity2 x y, group(g1 g2) target(t)

* Group-normalized mixture density
kdensity2 x, group(g) gnormalize

* Filter
kdensity2 x, generate(d) if(flag==1)
```

---

## 2. nwreg — Kernel & Local Polynomial Regression

Estimate conditional mean E[Y|X] via Nadaraya-Watson or local polynomial regression.

```stata
nwreg depvar indepvars [, options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `kernel(name)` | `gaussian`, `epanechnikov`, `uniform`, `triweight`, `cosine` | `gaussian` |
| `bw(method)` | `silverman`, `scott`, `cv`, or positive number | `silverman` |
| `poly(#)` | Polynomial degree: 0=NW, 1=local linear, 2=local quadratic... | 0 |
| `derivatives(prefix)` | Creates `prefix1`, `prefix2`, ... derivative vars (requires `poly≥1`) | none |
| `target(varname)` | 0/1: 0=training, 1=test | all train |
| `group(varlist)` | Grouping variables | none |
| `mincount(#)` | Skip groups with < # obs | 0 |
| `generate(newvar)` | Output prediction variable | `nwreg` |
| `se(newvar)` | Standard error (NOT available with `poly≥1`) | none |
| `se_type(#)` | 0=full-sample, 1=leave-one-out, 2=leverage-corrected | 2 |
| `folds(#)` | CV folds | 10 |
| `grids(#)` | CV grid candidates per side | 10 |
| `nproc(#)` | OpenMP threads | 16 |
| `if(exp)` / `in(range)` | Observation filters | all |

**Constraints**:
- `poly>1` with **multiple regressors** → error (only poly=0 or poly=1 for multivariate)
- `se()` with `poly≥1` → rejected in ado layer
- `poly=1` with multivariate → generates **partial derivatives** (one per regressor)
- `poly≥1` with 1D regressor → `derivatives(prefix)` gives k-th derivatives: d1 = 1st, d2 = 2nd, etc.

```stata
* Basic NW
nwreg y x, generate(yhat)

* Local linear
nwreg y x, poly(1) generate(yhat_ll)

* Local quadratic with derivatives
nwreg y x, poly(2) generate(yhat_lq) derivatives(dydx)

* Multivariate local linear with partial derivatives
nwreg y x1 x2, poly(1) generate(yhat_mv) derivatives(dydx)

* NW with standard error
nwreg y x, generate(yhat) se(yhat_se)
nwreg y x, generate(yhat) se(yhat_se) se_type(1)

* CV bandwidth
nwreg y x, bw(cv) folds(5) grids(15)

* Grouped + target split
nwreg y x, group(g1 g2) target(t) generate(yhat)
```

---

## 3. fangorn — CART Decision Tree & Random Forest

Classification and regression trees with optional random forest ensemble.

```stata
fangorn depvar indepvars, generate(name) [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `type(classify|regress)` | Task type | `classify` |
| `ntree(#)` | 1=single tree, >1=random forest | 1 |
| `maxdepth(#)` | Maximum tree depth | 20 |
| `entcvdepth(#)` | CV depth selection folds (0=disable) | 10 |
| `minsamplessplit(#)` | Min samples to split | 2 |
| `minsamplesleaf(#)` | Min samples per leaf | 1 |
| `minimpuritydecrease(#)` | Absolute impurity threshold | 0.0 |
| `relimpdec(#)` | Relative impurity threshold (× root gain) | 0.0 |
| `maxleafnodes(#)` | Post-pruning leaf limit | unlimited |
| `criterion(gini|entropy|mse)` | Split criterion | auto |
| `seed(#)` | RNG seed | 12345 |
| `nclasses(#)` | Number of classes (classification) | auto-detect |
| `mtry(#)` | Features per split (RF) | √p classify, p/3 regress |
| `ntiles(#)` | Quantile thresholds (0=all unique) | 0 |
| `target(varname)` | 0=train, 1=test | all train |
| `group(varlist)` | Grouping variables | none |
| `mermaid(filename)` | Export tree as Mermaid flowchart | none |
| `predname(name)` | Custom prediction var name | `{generate}_pred` |
| `nproc(#)` | OpenMP threads | 16 |
| `if(exp)` / `in(range)` | Observation filters | all |

**Prediction output**:
- **Binary classification**: `{predname}` = P(y=1|X), continuous in [0,1]
- **Multi-class (K classes)**: `{predname}_0` ... `{predname}_{K-1}` = P(y=c|X) each in [0,1], sum to 1
- **Regression**: `{predname}` = conditional mean E[y|X]
- **Always**: `{predname}_leaf` = leaf node ID

```stata
* Single classification tree
fangorn y x1 x2, generate(pred)

* Random forest (100 trees)
fangorn y x1 x2, generate(pred) ntree(100) seed(42)

* Regression with CV depth
fangorn y x1 x2, generate(pred) type(regress) entcvdepth(5)

* Regularization
fangorn y x1 x2, generate(pred) relimpdec(0.1) maxleafnodes(8)

* Export tree
fangorn y x1 x2, generate(pred) mermaid(tree.md)

* Target split
fangorn y x1 x2, generate(pred) target(t)
```

---

## 4. xpofangorn — Partially Linear Model via DML

Double machine learning estimator: `y = β·w + g(X) + u`. Calls `fangorn` internally.

```stata
xpofangorn depvar treatvar [indepvars] [, options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `generate(prefix)` | Save residuals as `prefix_ey`, `prefix_ew` | not saved |
| `debug` | Shorthand for `generate(_xpofangorn)` | — |
| `kfold(#)` | Cross-fitting folds | 5 |
| `type(classify|regress)` | Force w model type | auto |
| `vce(robust|cluster(varname))` | Variance estimator | `robust` |
| `ntree(#)` | Trees for fangorn | 1 |
| `maxdepth(#)` | Max depth | 20 |
| `entcvdepth(#)` | CV depth selection | 10 |
| `minsamplessplit(#)` | Min samples to split | 2 |
| `minsamplesleaf(#)` | Min samples per leaf | 1 |
| `minimpuritydecrease(#)` | Impurity threshold | 0.0 |
| `relimpdec(#)` | Relative impurity threshold | 0.0 |
| `maxleafnodes(#)` | Leaf limit | unlimited |
| `criterion(gini|entropy|mse)` | Split criterion | auto |
| `seed(#)` | RNG seed | 12345 |
| `mtry(#)` | Features per split | auto |
| `ntiles(#)` | Quantile thresholds | 0 |
| `nproc(#)` | OpenMP threads | 16 |
| `if(exp)` / `in(range)` | Observation filters | all |

**Auto-detect w type**: Binary (0/1) → classify. Continuous (outside [0,1]) → regress.

**Stored results**:
```
r(N)      → Observations in final regression
r(kfold)  → Folds used
r(beta)   → Treatment effect
r(se)     → Standard error
r(t)      → t-statistic
r(p)      → p-value
```

```stata
* Default 5-fold DML
xpofangorn y w x1 x2 x3

* RF with 10-fold cross-fitting
xpofangorn y w x1 x2 x3, kfold(10) ntree(100) seed(42)

* Binary treatment with cluster SE
xpofangorn y w x1 x2, type(classify) ntree(200) vce(cluster city)

* Save residuals
xpofangorn y w x1 x2 x3, generate(res)
summarize res_ey res_ew

* Quick debug
xpofangorn y w x1 x2 x3, debug
```

---

## 5. grf — Generalized Random Forest (Causal Forest)

Heterogeneous treatment effect (CATE) estimation via causal forest (Athey, Tibshirani & Wager, 2019). Wraps the upstream [GRF C++ core library](https://github.com/grf-labs/grf) v2.6.1. Requires C++17 to build; pre-built plugin available in releases.

```stata
grf depvar treatvar indepvars, generate(newvar) [options]
```

**Positional**: `grf y w x1 x2` — first variable = outcome, second = treatment, rest = covariates (at least 1).

| Option | Description | Default |
|--------|-------------|---------|
| `generate(newvar)` | CATE estimates (required) | — |
| `yhat(varname)` | Pre-computed E[Y\|X] | internal regression forest |
| `what(varname)` | Pre-computed E[W\|X] | internal regression forest |
| `weights(varname)` | Sample weights | equal (1) |
| `cluster(varname)` | Cluster IDs | unique per obs |
| `equalizeclusterweights` | Equal-weight clusters | off |
| `ntree(#)` | Number of trees | 2000 |
| `samplefraction(#)` | Subsample fraction | 0.5 |
| `mtry(#)` | Features per split | auto (√p + 20) |
| `minnodesize(#)` | Minimum node size | 5 |
| `nohonesty` | Disable honest splitting | off (honesty=on) |
| `honestyfraction(#)` | Fraction for honest estimation | 0.5 |
| `nohonestyprune` | Don't prune empty honesty leaves | off |
| `alpha(#)` | Maximum imbalance in a split | 0.05 |
| `imbalancepenalty(#)` | Imbalance penalty | 0 |
| `nostabilizesplits` | Disable split stabilization | off |
| `cigroupsize(#)` | CI group size (≥2 for variance) | 2 |
| `vargenerate(newvar)` | Variance of CATE | off |
| `oobgenerate(newvar)` | Out-of-bag CATE predictions | off |
| `seed(#)` | RNG seed | 12345 |
| `nproc(#)` | OpenMP threads | 16 |
| `if(exp)` / `in(range)` | Observation filters | all |

**Stored results**:
```
r(N)              → Observations
r(ntree)          → Trees used
r(seed)           → Seed
r(mtry)           → Features per split
r(ci_group_size)  → CI group size
```

**Algorithm notes**:
- **Honest splitting** (default): split sample into two halves — one selects splits, one estimates leaf effects. Reduces overfitting; required for valid inference.
- **R-learner orthogonalization**: nuisance forests estimate E[Y|X] and E[W|X] internally (or via `yhat()`/`what()`). Outcomes are centered before causal forest training. `yhat()` and `what()` must be provided together.
- **Variance estimation**: "bootstrap of little bags" delta method. Activate with `vargenerate()`; requires `cigroupsize(>=2)`.
- **OOB predictions**: unbiased CATE from trees where the observation was not in the bootstrap sample.
- **R-vs-Stata parity**: CATE estimates correlate at **0.997** with the official R package under identical settings.

```stata
* Basic causal forest (internal nuisance)
grf y w x1 x2 x3, generate(tauhat) ntree(500)

* With variance and OOB
grf y w x1 x2, generate(tauhat) vargenerate(vartau) oobgenerate(tau_oob) ntree(1000)

* Pre-computed nuisance estimates
grf y w x1 x2, yhat(ey) what(ew) generate(tauhat)

* Cluster-robust SE
grf y w x1, generate(tauhat) cluster(city) equalizeclusterweights

* Honesty off + higher subsample fraction
grf y w x1 x2, generate(tauhat) nohonesty samplefraction(0.8)
```

---

## 6. Standalone Commands (`single_ado/`)

### 6.1 csadensity — Common Support Area

Detect common support between treatment and control groups via kernel density overlap.

```stata
csadensity varlist, treatment(varname) generate(name) [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `treatment(varname)` | **Required.** Binary 0/1 treatment indicator | — |
| `generate(name)` | **Required.** Output CSA indicator (0/1) | — |
| `threshold(#)` | Normalized density threshold | 0.2 |
| `group(varlist)` | Grouping variables | none |
| `kernel(name)` | Kernel for kdensity2 | `triweight` |
| `bw(method)` | Bandwidth for kdensity2 | default |
| `debug` | Keep intermediate variables | drop |

**Returns**: `r(N)`, `r(N_csa)`, `r(threshold)`, `r(treatment)`

```stata
csadensity x1 x2, treatment(d) generate(csa)
csadensity x1 x2, treatment(d) generate(csa) group(g) threshold(0.15)
csadensity x1 x2, treatment(d) generate(csa) debug
```

### 6.2 bprecall — Binary Classification Metrics

Precision, recall, accuracy, F1 across multiple thresholds.

```stata
bprecall depvar phat [, divide(#)]
```

| Option | Description | Default |
|--------|-------------|---------|
| `divide(#)` | Number of thresholds | 9 |

Thresholds = `1/(K+1), 2/(K+1), ..., K/(K+1)` where `K = divide`.

**Returns**: `r(results)` = matrix (threshold, precision, recall, accuracy, f1), `r(divide)`

```stata
bprecall y yhat
bprecall y yhat, divide(19)
matrix list r(results)
```

### 6.3 countdistinct — Count Distinct Combinations

```stata
countdistinct varlist [if] [in] [, generate(name)]
```

| Option | Description | Default |
|--------|-------------|---------|
| `generate(name)` | First-occurrence indicator | none |

**Returns**: `r(count)`

```stata
countdistinct country year
countdistinct country year, generate(first_obs)
```

### 6.4 dta2md — Dataset → Markdown Export

Export .dta metadata to Markdown for AI consumption.

```stata
dta2md filepath [, options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `using(filename)` | Output path | `{filepath_base}_metadata.md` |
| `descriptive` | Per-variable details (stats, freq tables) | simple only |
| `maxcat(#)` | Max unique values for freq table | 20 |
| `maxfreq(#)` | Max freq table rows | 30 |
| `english` | English labels (default: Chinese) | Chinese |
| `varlist(varlist)` | Subset of variables | all |
| `labeled` | Only labeled variables | all |

**Output**: Dataset overview → variable list table → per-variable detail.

```stata
dta2md "mydata.dta"
dta2md "mydata.dta", descriptive english
dta2md "mydata.dta", descriptive labeled
dta2md "mydata.dta", using("docs/mydata.md") descriptive
```

### 6.5 gen_init_var — Panel Base-Year Carry-Forward

Fill forward a variable's base-year value within groups.

```stata
gen_init_var varname, yearvar(varname) year(string) by(varname) generate(name) [stringyear]
```

| Option | Description | Required |
|--------|-------------|----------|
| `yearvar(varname)` | Year/time variable | Yes |
| `year(string)` | Base year value | Yes |
| `by(varname)` | Panel grouping variable | Yes |
| `generate(name)` | Output variable | Yes |
| `stringyear` | Use if year is stored as string | No |

**Returns**: `r(varname)`, `r(sourcevar)`, `r(yearvar)`, `r(year)`, `r(byvar)`

```stata
gen_init_var gdp, yearvar(year) year(2000) by(country) generate(gdp2000)
gen_init_var gdp, yearvar(year) year("2000") by(country) generate(gdp2000) stringyear
```

### 6.6 gencatutility — Categorical Utility Scores

Compute continuous utility scores for ordered categorical variables via inverse normal.

```stata
gencatutility varname, generate(name) [display]
```

| Option | Description | Default |
|--------|-------------|---------|
| `generate(name)` | **Required.** Output utility score | — |
| `display` | Show level-utility table | silent |

**Returns**: `r(n_levels)`, `r(n_obs)`, `r(levels)`, `r(varname)`, `r(generate)`

```stata
gencatutility satisfaction, generate(sat_util) display
gencatutility education_level, generate(edu_util)
```

### 6.7 labelvalidsample — Complete-Case Marker

Flag observations with no missing values in specified variables.

```stata
labelvalidsample varlist [if] [in], generate(name)
```

| Option | Description | Required |
|--------|-------------|----------|
| `generate(name)` | **Required.** Output binary (1=complete) | Yes |

```stata
labelvalidsample y x1 x2 x3, generate(complete)
labelvalidsample y x1 x2, generate(complete) if(age > 18)
```

---

## 7. Build

```bash
make                    # Build all CPU plugins (kdensity2, nwreg, fangorn, grf)
make kdensity2          # Single plugin
make nwreg
make fangorn
make grf                # Requires C++17 (gcc ≥8 or clang ≥7)
make kdensity2_cuda     # GPU (hidden feature, needs nvcc + NVIDIA GPU)
make nwreg_cuda
make install            # Copy .plugin, .ado, .sthlp to ~/ado/plus/
make clean              # Remove .plugin files
make dist               # Package for distribution
```

| Platform | Requirements |
|----------|-------------|
| Linux | `libopenblas-dev` (`pkg-config openblas` must succeed) |
| macOS | `brew install libomp` |
| Windows | `x86_64-w64-mingw32-gcc` cross-compiler |

GPU plugins use single-precision float. CPU vs GPU tolerance ~1e-5.

---

## 8. Gotchas

1. **`if()` trap in kdensity2**: Do NOT pass `if(touse)` from a caller. Compute on all obs, filter externally.
2. **`~` in plugin path**: `plugin using("~/...")` doesn't expand `~`. Ado uses `: env HOME` + `subinstr()`.
3. **Stata 18 plugin quirk**: `program list` can't find plugin programs (rc=111). The load block treats `_rc==110` as success.
4. **`count`/`summarize`/`tabulate` overwrite `r()`**: Save to local before calling if you need previous values.
5. **`se()` + `poly()`**: Mutually exclusive. `se()` with `poly≥1` is rejected.
6. **Multivariate `poly>1`**: Not supported (basis too large). Error raised.
7. **String group variables**: Auto-encoded in ado layer via `egen group()`. Works transparently.
8. **grf `yhat()`/`what()` must be paired**: Provide both or neither; providing only one raises an error.
9. **grf C++17 build requirement**: Building from source requires a C++17 compiler. Pre-built plugin available in releases.

---

*2026-07-30 · HHStataToolkit*
