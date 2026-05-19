# xpofangorn — Partially Linear Model via Double Machine Learning

Stata command implementing the partially linear model

$$y_i = \beta w_i + g(x_i) + u_i$$

using **double machine learning (DML)** with K-fold cross-fitting
(Chernozhukov et al., 2018). The nuisance functions $E[y|X]$ and $E[w|X]$
are estimated using `fangorn` (CART / random forest).

## Algorithm

1. **Split** the data randomly into $K$ folds (default $K=5$). The original
   observation order is preserved — the fold assignment is a temporary
   shuffle that is restored before any output is produced.
2. **For each fold** $k = 1, \dots, K$:
   - Train `fangorn` to estimate $E[y \mid X]$ on the $K-1$ training folds
     (target=0); predict on the held-out fold $k$ (target=1).
     Residual: $e_y = y - \hat{E}[y \mid X]$.
   - Train `fangorn` to estimate $E[w \mid X]$ on the $K-1$ training folds;
     predict on held-out fold $k$.
     Residual: $e_w = w - \hat{E}[w \mid X]$.
3. **Regress** $e_y$ on $e_w$ to obtain $\hat{\beta}$ with heteroskedasticity-robust
   or cluster-robust standard errors.

## Syntax

```stata
xpofangorn depvar treatvar indepvars [, options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `generate(prefix)` | Save residuals as `prefix_ey`, `prefix_ew` | not saved |
| `debug` | Shorthand for `generate(_xpofangorn)` | not saved |
| `kfold(#)` | Number of cross-fitting folds | 5 |
| `type(classify|regress)` | Force w model type | auto-detect |
| `vce(robust|cluster(varname))` | Variance estimator | robust |
| `ntree(#)` | Number of trees (fangorn) | 1 |
| `maxdepth(#)` | Max tree depth | 20 |
| `entcvdepth(#)` | CV depth selection folds (fangorn) | 10 |
| `minsamplessplit(#)` | Min samples to split | 2 |
| `minsamplesleaf(#)` | Min samples per leaf | 1 |
| `minimpuritydecrease(#)` | Impurity threshold | 0.0 |
| `relimpdec(#)` | Relative impurity threshold | 0.0 |
| `maxleafnodes(#)` | Post-pruning leaf limit | unlimited |
| `criterion(gini|entropy|mse)` | Split criterion for w | auto |
| `seed(#)` | RNG seed | 12345 |
| `mtry(#)` | Features per split | auto |
| `ntiles(#)` | Quantile thresholds | 0 (exact) |
| `nproc(#)` | OpenMP threads | 16 |
| `if(exp)` / `in(range)` | Observation filters | all |

### Auto-detection of w type

If `type()` is not specified, `xpofangorn` inspects the treatment variable:

- **Binary** (all values are 0 or 1): uses `fangorn` with `type(classify)`,
  which predicts class labels using Gini impurity. The residual
  $e_w = w - \hat{w}$ takes values in $\{-1, 0, 1\}$.
- **Continuous** (any value outside [0,1]): uses `fangorn` with `type(regress)`,
  which predicts the conditional mean.

Override with the `type()` option.

### Variance Estimation

The final regression supports:

- `vce(robust)` — Heteroskedasticity-consistent standard errors
  (default)
- `vce(cluster clustvar)` — Cluster-robust standard errors

## Examples

```stata
* Basic usage (5-fold DML, auto-detect w type)
xpofangorn y w x1 x2 x3

* 10-fold cross-fitting with random forest
xpofangorn y w x1 x2 x3, kfold(10) ntree(100) seed(42)

* Binary treatment with forest, cluster SE by city
xpofangorn y w x1 x2, type(classify) ntree(200) vce(cluster city) generate(res)

* Save residuals for diagnostic checking
xpofangorn y w x1 x2 x3, generate(res)
summarize res_ey res_ew

* Quick debug: save residuals with default names
xpofangorn y w x1 x2 x3, debug
summarize _xpofangorn_ey _xpofangorn_ew
```

## Stored Results

`xpofangorn` stores in `r()`:

| Scalar | Description |
|--------|-------------|
| `r(N)` | Observations in final regression |
| `r(kfold)` | Cross-fitting folds |
| `r(beta)` | Treatment effect estimate |
| `r(se)` | Standard error |
| `r(t)` | t-statistic |
| `r(p)` | p-value |

Additionally, the `regress` command stores full results in `e()`.

## Test Results (16-core, Stata 18 MP)

DML test for the partially linear model $y_i = \beta w_i + g(x_i) + u_i$.
Data generating process: N=5000, 24 features (x1, x2, 19 d1 dummies, d2),
complex non-linear $g(x)$. True $\beta = 3$.

```
x1 ~ N(0, 1)
x2 ~ χ²(3) + exp(x1)
d1 = ceil(20×Uniform(0,1))    → 19 dummy variables
d2 = Uniform(0,1) < 0.4       → binary

w  = x1 + log(x2) + d1·sin(exp(x1)) + exp(x1·x2·d2/20) + N(0,2)
g  = exp((d1·cos(x2) - d2·x1 + x1/x2)/5) + log(χ²(8))
y  = 3·w + g + N(0,1)
```

### Monte Carlo Simulation (50 reps, 16-core, Stata 18 MP)

| Config | ntree | kfold | maxdepth | Mean(β̂) | SD(β̂) | Mean(SE) | Time |
|--------|------:|------:|---------:|--------:|-------:|---------:|-----:|
| RF50_K5_D10 | 50 | 5 | 10 | 3.0567 | 0.0751 | 0.0244 | 2.5s |
| RF100_K5_D10 | 100 | 5 | 10 | 3.0526 | 0.0709 | 0.0231 | 2.7s |
| RF50_K2_D10 | 50 | 2 | 10 | 3.0438 | 0.0702 | 0.0217 | 0.8s |
| RF50_K10_D10 | 50 | 10 | 10 | 3.0498 | 0.0560 | 0.0301 | 5.2s |
| RF100_K5_D5 | 100 | 5 | 5 | 3.0260 | 0.0399 | 0.0173 | 0.8s |
| RF100_K5_D20 | 100 | 5 | 20 | 3.0567 | 0.0716 | 0.0290 | 8.3s |

- **Mean(β̂)**: average of β̂ across 50 reps; **SD(β̂)**: simulation standard
  deviation; **Mean(SE)**: average estimated standard error; **Time**:
  average wall-clock time per rep (1s resolution).

### Key Observations

- All configurations produce unbiased estimates (Mean(β̂) ≈ 3.0), with
  small upward bias (~0.03–0.06) consistent across settings.
- **Shallow trees (maxdepth=5)** yield the smallest SD(β̂) = 0.0399,
  but Mean(SE) = 0.0173 substantially underestimates the true variability,
  indicating anti-conservative inference.
- **Deeper trees (maxdepth=20)** have larger SD(β̂) = 0.0716 but also
  larger Mean(SE) = 0.0290 — still underestimating variability.
- **More folds (K=10)** reduces SD(β̂) = 0.0560 vs K=5 (0.0751) and
  K=2 (0.0702), but is slower (5.2s vs 2.5s vs 0.8s).
- **More trees (ntree=100 vs 50)**: marginal improvement in bias and SE;
  similar SD(β̂) at same depth.
- The persistent gap between SD(β̂) and Mean(SE) across all settings
  indicates the DML standard errors are anti-conservative for this DGP,
  likely due to the extreme non-linearity of g(x).

### Reproducibility

| Test | nproc(1) 10-run | nproc(16) 10-run | nproc(1) vs nproc(16) |
|------|:---------------:|:----------------:|:---------------------:|
| RF basic (seed=12345, ntree=50, K=5, D=5) | PASS | PASS | PASS (bit-identical) |
| Deep RF (seed=99999, ntree=100, K=5, D=10) | PASS | PASS | PASS (bit-identical) |
| K=10 cross-fitting (seed=777, ntree=50) | PASS | PASS | PASS (bit-identical) |
| Different seeds → different betas | — | — | seed=1 vs 999: diff > 0 ✓ |

Run: `stata -b do test/xpofangorn/test_xpofangorn_seed_reproducibility.do`

## References

- Chernozhukov, V., Chetverikov, D., Demirer, M., Duflo, E., Hansen, C.,
  Newey, W., & Robins, J. (2018). Double/debiased machine learning for
  treatment and structural parameters. *The Econometrics Journal*, 21(1),
  C1-C68.
- Breiman, L. (2001). Random forests. *Machine Learning*, 45(1), 5-32.
- Breiman, L., Friedman, J. H., Olshen, R. A., & Stone, C. J. (1984).
  *Classification and Regression Trees*. Wadsworth & Brooks/Cole.
