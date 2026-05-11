# HHStataToolkit — Agent Guide

**Generated:** 2026-05-11 · **Commit:** 75e7b7d · **Branch:** main

Stata plugin collection: kernel density (`kdensity2`), kernel regression (`nwreg`),
random forest (`fangorn`). C plugins + ado wrappers + pure-Stata utilities.

## Quick Start

```bash
make               # Build all plugins (Linux/macOS/Windows cross)
make kdensity2     # Single plugin
make kdensity2_cuda # Requires nvcc + NVIDIA GPU
make install       # .plugin → ~/ado/plus/, .ado/.sthlp → ~/ado/plus/<letter>/
make clean         # Remove all .plugin files
make dist          # Package to ado/plus/ for distribution
```

**Platform gotchas:**
- Linux: needs `libopenblas-dev` (`pkg-config openblas` must succeed)
- macOS: `brew install libomp` (OpenMP not bundled with Apple Clang)
- Windows: cross-compiles with `x86_64-w64-mingw32-gcc`, static-links OpenBLAS

## Project Structure

```
src/                  # Shared C: stplugin.h/c (NEVER modify), utils.h/c, ols.h/c
kdensity2/            # Single-file C plugin + ado + sthlp
nwreg/                # Single-file C plugin + ado + sthlp
fangorn/              # Multi-file C plugin: fangorn.c ent.c split.c utils_rf.c
single_ado/           # Pure Stata commands (no compilation): bprecall, csadensity, ...
test/                 # Per-plugin subdirs; all tests are Stata .do files
```

## How Plugins Work

1. ado layer parses syntax, builds variable list, loads `.plugin` via `plugin using()`
2. C plugin reads data into arrays, computes, writes back via `SF_vstore()`
3. `make install` copies `.plugin` to `~/ado/plus/` (this shadows repo copies)

**Critical**: After editing C, always `make install`. The `.plugin` in `~/ado/plus/`
takes precedence over the repo copy. `findfile` searches adopath.

## Plugin Variable Layout (1-based Stata indices)

| Plugin | Variable order passed to C |
|--------|---------------------------|
| **kdensity2** | density vars → [target] → [group vars] → generate result → touse |
| **nwreg** | regressors → depvar → [target] → [group vars] → result → [se] → touse |
| **fangorn** | features → depvar → [target] → [group vars] → result → leaf_id → touse |

`target=0` = training, `target=1` = prediction. Only target=0 trains; all obs get predictions.

## Syntax Quirk

All ado files use `IF(string) IN(string)` as **options**, not Stata qualifiers:
```stata
fangorn y x1 x2, generate(pred) if(flag==1)
```
Stata 18 has a bug where `syntax varlist [if] [in]` collides with string options
and produces "option if not allowed".

## Testing Requirements

Every plugin change must pass 10-run reproducibility:

```bash
stata -e do test/fangorn/test_fangorn_seed_reproducibility.do
stata -e do test/kdensity2/test_seed_reproducibility.do
stata -e do test/nwreg/test_seed_reproducibility.do
stata -e do test/kdensity2/test_gpu_seed_reproducibility.do   # CUDA only
```

| Plugin | Randomness source | How to control |
|--------|------------------|----------------|
| fangorn | Internal LCG (`seed()` option) | `seed(12345)` → bit-identical |
| kdensity2/nwreg CV | ado `runiform()` shuffle | Must **re-`set seed`** before each call |
| kdensity2 GPU | Deterministic CUDA kernels | `set seed` + `gpu(0)`, tolerance `1e-5` |

**OpenMP reproducibility**: thread count must NOT affect results.
- fangorn: per-thread LCG (`seed + 9999 + t`)
- kdensity2/nwreg: serial evaluation loops (OpenMP removed from eval)

## Key Gotchas

### Plugin path / tilde
`plugin using("~/...")` does **not** expand `~`. ado workaround:
```stata
local homedir : env HOME
local path = subinstr("`path'", "~", "`homedir'", .)
```

### kdensity2 `if()` trap
Never pass `if(touse)` from a caller program. kdensity2's `if(string)` causes
density estimates to differ even when `touse=1` for all obs. Compute on all obs,
filter externally.

### Memory / data flow
- Plugins read ALL data into C arrays first. Memory = `n_obs × n_vars`.
- `SF_nvar()` returns TOTAL dataset variables — **never** use for index math.
- Use `alloc_double_array()`, `alloc_double_matrix()` from `utils.c`. Always `free()`.
- Limits: `MAX_DIM=10`, `MAX_GRID_POINTS=10000`, `MAX_GROUPS=1000`.

### Stata return values
`count` / `summarize` / `tabulate` **overwrite all `r()` scalars**. Save to a local
before calling them if you need previous `r()` values.

### LSP false positives
`__declspec` errors in `stplugin.h` are harmless Windows macros; GCC on Linux ignores them.

## Where to Look

| Task | Location | Notes |
|------|----------|-------|
| Add shared C utility | `src/utils.c` | Kernels, bandwidth, alloc helpers |
| New single-file plugin | Copy `kdensity2/` pattern | Makefile PLUGINS += name |
| New multi-file plugin | Copy `fangorn/` pattern | Custom Makefile target needed |
| Pure Stata command | `single_ado/` | No compilation, just .ado + .sthlp |
| GPU code | `kdensity2/kdensity2_cuda.cu` | Float internally, tolerance 1e-5 |
| Reproducibility tests | `test/*/test_*_seed_reproducibility.do` | 10-run bit-identical checks |
| Python benchmark | `test/fangorn/benchmark/` | sklearn vs fangorn |

## opencode Skill

Local skill at `.opencode/skills/stata-plugin/SKILL.md` covers:
- Stata-C data transfer (`SF_vdata()`, `SF_vstore()`, `SF_mat_el()`)
- BLAS matrix operations via OpenBLAS
- Cross-platform Makefile templates (Linux/macOS/Windows)
- Plugin debugging (`stata_printf()` for C-level output)

Load with: `skill(name="stata-plugin")`
