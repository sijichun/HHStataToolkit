# src/ols.h / src/ols.c — OLS/WLS Linear Regression Module

Internal C library for **ordinary least squares (OLS)** and **weighted least squares (WLS)** using LAPACK (OpenBLAS). This module is **not** a Stata plugin itself; it is consumed by other plugins that need numerically-stable linear regression primitives.

---

## 1. Design Overview

| Aspect | Choice | Rationale |
|--------|--------|-----------|
| Solver | LAPACK `dgelsd_` (SVD-based least squares) | Handles rank-deficient X gracefully; returns minimum-norm solution |
| Invertibility check | LAPACK `dgesvd_` | Singular-value decomposition gives explicit singular values and rank |
| Matrix layout | Column-major (Fortran convention) | Matches LAPACK/BLAS; `X[j*n + i]` = row *i*, col *j* |
| Constant term | Stored separately in `result->constant` | `beta` always has *p* elements regardless of `has_constant` |
| Weights | Caller passes **square-root** of raw weights | Avoids `sqrt()` inside the solver; standard in statistical packages |
| LAPACK interface | Raw Fortran ABI (manual `extern` declarations) | System has no `lapacke.h` / `cblas.h` installed |

---

## 2. Data Structures

### `ols_result_t`

```c
typedef struct {
    double *beta;           /* p coefficients (slopes)               */
    double constant;        /* Intercept (0.0 if has_constant==0)   */
    int n;                  /* Number of observations                */
    int p;                  /* Number of slope coefficients          */
    int has_constant;       /* 1 = intercept estimated, 0 = none    */
    int rank;               /* Effective rank reported by DGELSD    */
    int converged;          /* 1 = success, 0 = failure             */
    char error_msg[256];    /* Error description on failure         */
} ols_result_t;
```

- `beta` is `NULL` until a successful fit; caller must free via `ols_result_free()`.
- `constant` and `beta` are **separated** intentionally: the caller always indexes `beta[j]` for the *j*-th regressor regardless of whether an intercept was included.

### `ols_stats_t`

```c
typedef struct {
    double *fitted;         /* y_hat  (n x 1)                        */
    double *residuals;      /* e = y - y_hat  (n x 1)               */
    double rss;             /* Residual sum of squares               */
    double tss;             /* Total sum of squares                  */
    double r_squared;       /* Coefficient of determination          */
    double adj_r_squared;   /* Adjusted R-squared                    */
    double rmse;            /* Root mean squared error               */
} ols_stats_t;
```

- Allocated on demand by `ols_compute_stats()`; free with `ols_stats_free()`.

---

## 3. API Reference

### `check_invertible_svd`

```c
int check_invertible_svd(const double *X, int n, int p,
                         const double *tol,
                         double *min_sv, int *rank);
```

Computes the singular-value decomposition of the design matrix `X` (column-major, `n × p`) and returns whether `X` has **full column rank**.

| Parameter | In/Out | Description |
|-----------|--------|-------------|
| `X` | in | Design matrix, column-major, size `n × p`. **Not modified.** |
| `n` | in | Number of rows (observations). |
| `p` | in | Number of columns (parameters). |
| `tol` | in | Singular-value threshold. If `NULL` or `≤ 0`, defaults to `max(n,p) × eps × s_max` where `eps = DBL_EPSILON`. |
| `min_sv` | out | Smallest singular value (optional, may be `NULL`). |
| `rank` | out | Number of singular values strictly greater than `tol` (optional, may be `NULL`). |

**Returns:** `1` if full rank (`rank == p` and `p ≤ n`), `0` otherwise. Returns `0` on any LAPACK or memory failure.

---

### `ols_fit`

```c
ols_result_t* ols_fit(const double *X, const double *y,
                      int n, int p, int constant);
```

Fits ordinary least squares:

```
min || y - X·beta - constant ||_2
```

| Parameter | In/Out | Description |
|-----------|--------|-------------|
| `X` | in | Regressor matrix, column-major, `n × p`. |
| `y` | in | Response vector, length `n`. |
| `n` | in | Number of observations. |
| `p` | in | Number of regressors (columns in `X`). |
| `constant` | in | `1` = prepend intercept and estimate it; `0` = no intercept. |

**Returns:** pointer to `ols_result_t` on success; `NULL` on failure (check `error_msg` in the returned struct if non-NULL). Caller must free with `ols_result_free()`.

**Note:** This function **does not** check invertibility. If you need to reject rank-deficient systems, call `check_invertible_svd()` first.

---

### `wls_fit`

```c
ols_result_t* wls_fit(const double *X, const double *y, const double *w,
                      int n, int p, int constant);
```

Fits weighted least squares by transforming to an OLS problem on weighted data:

```
min || W · (y - X·beta - constant) ||_2
```

where `W = diag(w)` and `w` is **already the square root** of the raw weights (i.e. `w[i] = sqrt(raw_weight[i])`).

| Parameter | In/Out | Description |
|-----------|--------|-------------|
| `w` | in | Square-root weight vector, length `n`. Pass `NULL` for equal weights (falls back to `ols_fit`). |

All other parameters are identical to `ols_fit`.

---

### `ols_predict`

```c
void ols_predict(const double *X, int n, int p,
                 const ols_result_t *result, double *out);
```

Computes `out = X·beta + constant`. `out` must be pre-allocated by the caller (length `n`).

---

### `ols_compute_stats`

```c
ols_stats_t* ols_compute_stats(const double *X, const double *y,
                               int n, int p,
                               const ols_result_t *result);
```

Computes fitted values, residuals, RSS, TSS, R², adjusted R², and RMSE.

- **With constant** (`has_constant == 1`): TSS is centered around `mean(y)`.
- **Without constant** (`has_constant == 0`): TSS is `Σ yᵢ²` (uncentered).

Degrees of freedom for adjusted R² and RMSE: `n - p_total` where `p_total = p + has_constant`.

**Returns:** pointer to `ols_stats_t` on success; `NULL` on failure. Caller must free with `ols_stats_free()`.

---

### `ols_result_free`

```c
void ols_result_free(ols_result_t *result);
```

Frees `result->beta` and the struct itself. Safe to call with `NULL`.

### `ols_stats_free`

```c
void ols_stats_free(ols_stats_t *stats);
```

Frees `stats->fitted`, `stats->residuals`, and the struct itself. Safe to call with `NULL`.

---

## 4. Implementation Details

### 4.1 LAPACK / BLAS Interface

The target build environment does **not** provide `lapacke.h` or `cblas.h`. The module declares the necessary Fortran routines directly:

```c
extern void dgesvd_(const char *jobu, const char *jobvt,
                    int *m, int *n, double *a, int *lda,
                    double *s, double *u, int *ldu,
                    double *vt, int *ldvt,
                    double *work, int *lwork, int *info);

extern void dgelsd_(int *m, int *n, int *nrhs,
                    double *a, int *lda,
                    double *b, int *ldb,
                    double *s,
                    double *rcond, int *rank,
                    double *work, int *lwork, int *iwork, int *info);
```

These symbols are provided by **OpenBLAS** (which bundles LAPACK). Both routines follow the Fortran calling convention: all arguments are passed by pointer, even scalars.

### 4.2 Workspace Management for `dgelsd_`

`dgelsd_` requires two workspace queries before the actual solve:

1. **First call** with `lwork = -1` and `work` as a single `double` → returns optimal `lwork` in `work[0]` and optimal `liwork` in `iwork`.
2. **Allocate** `work[lwork]` and `iwork[liwork]`.
3. **Second call** performs the actual solve.

The implementation applies a **documented lower-bound guard** to ensure the query result is never smaller than the theoretical minimum:

```
lwork ≥ 12·mn + 2·mn·smlsiz + 8·mn·nlvl + mn·nrhs + (smlsiz+1)²
liwork ≥ 3·mn·nlvl + 11·mn
```

where `mn = min(m, n)` and `nlvl = max(0, floor(log2(mn / (smlsiz + 1))) + 1)` with `smlsiz = 25`.

### 4.3 Constant-Term Handling

When `constant == 1`, the module internally builds an **augmented matrix** `A` of size `n × (p+1)`:

```
A = [ 1  |  X ]
    [ 1  |    ]
    [... |    ]
```

`dgelsd_` solves for coefficients `[c, β₁, …, βₚ]`. After solving, the first element is extracted into `result->constant` and the remaining `p` elements into `result->beta`. This guarantees that the caller always sees `beta` with exactly `p` elements.

### 4.4 Weighted Least Squares

WLS is implemented by **pre-scaling** both `X` and `y` by `w[i]` and then calling the standard OLS solver:

```
yw[i] = w[i] · y[i]
Aw[i,j] = w[i] · X[i,j]
min || yw - Aw·beta ||_2
```

This is mathematically equivalent to `min (y - X·beta)' W² (y - X·beta)`.

---

## 5. Memory Model

| Object | Allocator | Owner | Free with |
|--------|-----------|-------|-----------|
| `ols_result_t` | `calloc` | Library | `ols_result_free()` |
| `ols_result_t.beta` | `malloc` | Library | `ols_result_free()` |
| `ols_stats_t` | `calloc` | Library | `ols_stats_free()` |
| `ols_stats_t.fitted` | `malloc` | Library | `ols_stats_free()` |
| `ols_stats_t.residuals` | `malloc` | Library | `ols_stats_free()` |
| `out` (prediction) | Caller | Caller | `free()` |

All internal workspace arrays (`A`, `b`, `work`, `iwork`, `s`) are freed before the public function returns.

---

## 6. Usage Example

```c
#include "ols.h"
#include <stdio.h>

int main(void)
{
    /* y = 2 + 3*x + noise */
    double X[] = {1.0, 2.0, 3.0, 4.0, 5.0};   /* 1 regressor, 5 obs */
    double y[] = {5.1, 7.9, 11.1, 13.8, 17.2};

    /* Optional: check invertibility first */
    if (!check_invertible_svd(X, 5, 1, NULL, NULL, NULL)) {
        fprintf(stderr, "X is rank-deficient\n");
        return 1;
    }

    /* Fit OLS with constant */
    ols_result_t *res = ols_fit(X, y, 5, 1, 1);
    if (!res) {
        fprintf(stderr, "Fit failed: %s\n", res ? res->error_msg : "unknown");
        return 1;
    }

    printf("Intercept: %.4f\n", res->constant);
    printf("Slope:     %.4f\n", res->beta[0]);

    /* Compute stats */
    ols_stats_t *stats = ols_compute_stats(X, y, 5, 1, res);
    if (stats) {
        printf("R² = %.6f, RMSE = %.4f\n", stats->r_squared, stats->rmse);
        ols_stats_free(stats);
    }

    ols_result_free(res);
    return 0;
}
```

Compile:

```bash
gcc -O3 -Wall -Isrc example.c src/ols.c -o example -lm -fopenmp -lopenblas
```

---

## 7. Error Handling

On failure, the module follows these conventions:

1. **Memory allocation failure** → returns `NULL` (or `0` for `check_invertible_svd`).
2. **LAPACK workspace query failure** → sets `res->converged = 0`, copies error to `res->error_msg`, frees partial allocations, returns `NULL`.
3. **LAPACK solve failure** (`info ≠ 0`) → same as above.

The caller should always check the return value before dereferencing.

---

## 8. Platform Notes

| Platform | OpenBLAS linking | Notes |
|----------|------------------|-------|
| Linux | Dynamic (`-lopenblas`) | Build system checks `ldconfig -p` for `libopenblas`; fails fast if missing |
| Windows | Static (`-Wl,-Bstatic -lopenblas -lgfortran -lquadmath …`) | Plugin works on machines without OpenBLAS installed |
| macOS | Dynamic (`-lopenblas` or Accelerate) | Not yet tested with this module |

The Fortran runtime (`libgfortran`) is pulled in on Linux dynamically as a transitive dependency of OpenBLAS. On Windows it is bundled statically.

---

## 9. Gotchas

- **Column-major layout**: `X[j*n + i]` is row *i*, column *j*. Do **not** pass row-major matrices.
- **Weight format**: `wls_fit` expects `w = sqrt(raw_weight)`. Passing raw weights without square-rooting will yield incorrect coefficients.
- **DGELSD overwrites inputs**: The internal working copies `A` and `b` are allocated and destroyed; the caller's `X` and `y` are never modified.
- **Rank-deficient X**: `ols_fit` does **not** reject rank-deficient matrices. It returns a minimum-norm solution. Use `check_invertible_svd()` beforehand if you need strict invertibility.
