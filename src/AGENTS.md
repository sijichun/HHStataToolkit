# src/ — Shared C Infrastructure

**Scope:** Stata plugin API glue, kernel functions, bandwidth selectors,
memory helpers, and OpenMP initialization. Used by all plugins.

## Files

| File | Role |
|------|------|
| `stplugin.h/c` | Official StataCorp plugin interface. **Never modify.** |
| `utils.h/c` | Kernels, bandwidth rules, alloc helpers, Stata↔C I/O |
| `ols.h/c` | OLS reference implementation (used by tests) |

## Key APIs

**Memory:** `alloc_double_array(n)`, `alloc_double_matrix(n_vars, n_obs)`,
`free_matrix(m, n_vars)`. Always free on error paths.

**Kernels:** `get_kernel_1d(type)` returns function pointer. Types:
`KERNEL_GAUSSIAN`, `KERNEL_EPANECHNIKOV`, `KERNEL_UNIFORM`,
`KERNEL_TRIWEIGHT`, `KERNEL_COSINE`.

**Bandwidth:** `silverman_bandwidth()`, `scott_bandwidth()` (1D);
`silverman_bandwidth_mv()`, `scott_bandwidth_mv()` (multivariate).

**Stata I/O:** `stata_to_c_matrix(n_vars, n_rows)` reads data;
`c_vector_to_stata(data, n, var_idx)` writes back.

**OpenMP:** Call `UTILS_OMP_SET_NTHREADS()` at start of `stata_call()`.
Defaults to 8 threads unless `OMP_NUM_THREADS` is set.

## Hard Limits

| Constant | Value | Meaning |
|----------|-------|---------|
| `MAX_DIM` | 10 | Max density/regression dimensions |
| `MAX_GRID_POINTS` | 10000 | Max grid points (mostly unused) |
| `MAX_GROUPS` | 1000 | Max unique group combinations |
| `MAX_VARNAME_LEN` | 32 | Max Stata variable name length |

## Conventions

- Use `snake_case` for functions.
- Pass `argc/argv` strings from ado layer; parse with `extract_option_value()`.
- Never use `SF_nvar()` for index math — it returns total dataset variables.
- `stata_printf()` for C-level debug output (visible in Stata results window).

## Anti-Patterns

- **Modifying `stplugin.h/c`** — these are vendor files; updates must come from StataCorp.
- **Raw `malloc`/`free`** — use the helpers to ensure zero-init and consistent error handling.
- **Missing `free()` on error paths** — every `alloc_*` must have a corresponding `free()`.
