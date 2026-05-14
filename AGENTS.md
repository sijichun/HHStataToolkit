# HHStataToolkit — Agent Guide

**Updated:** 2026-05-14 · **Branch:** main

Stata plugin collection: kernel density (`kdensity2`), kernel regression (`nwreg`),
random forest (`fangorn`). C plugins + ado wrappers + pure-Stata utilities (`dta2md`, `bprecall`, etc.).

## Quick Start

```bash
make               # Build CPU plugins only (kdensity2, nwreg, fangorn)
make kdensity2     # Single CPU plugin
make kdensity2_cuda # Hidden feature: CUDA plugin (requires nvcc + GPU)
make install       # .plugin → ~/ado/plus/, .ado/.sthlp → ~/ado/plus/<letter>/
make clean         # Remove all .plugin files
make dist          # Package to ado/plus/ for distribution
```

**Platform gotchas:**
- Linux: needs `libopenblas-dev` (`pkg-config openblas` must succeed)
- macOS: `brew install libomp` (OpenMP not bundled with Apple Clang)
- Windows: cross-compiles with `x86_64-w64-mingw32-gcc`, static-links OpenBLAS

**GPU is a hidden feature**: Not built by default, not exposed in ado syntax.
Build with `make kdensity2_cuda` or `make nwreg_cuda` if needed.

## Parallelism

All three plugins accept `nproc(#)` option (default 16). This controls OpenMP
thread count in the C plugin via `omp_set_num_threads()`. Also overridable
via `OMP_NUM_THREADS` environment variable.

- `nproc(1)` = single-core (for reproducibility checks)
- `nproc(N)` = N threads (N > 0)
- `set processors` in Stata does NOT affect plugin parallelism.

OpenMP is fully deterministic: all three plugins produce bit-identical
results regardless of thread count.

## Project Structure

```
src/                  # Shared C: stplugin.h/c (NEVER modify), utils.h/c, ols.h/c
kdensity2/            # Single-file C plugin + ado + sthlp
nwreg/                # Single-file C plugin + ado + sthlp
fangorn/              # Multi-file C: fangorn.c ent.c split.c utils_rf.c
single_ado/           # Pure Stata commands (no compilation): dta2md, bprecall, csadensity, ...
test/                 # Per-plugin subdirs; all tests are Stata .do files
```

## How Plugins Work

1. ado layer parses syntax, builds variable list, loads `.plugin` via `plugin using()`
2. C plugin reads data into arrays, computes, writes back via `SF_vstore()`
3. `make install` copies `.plugin` to `~/ado/plus/` (this shadows repo copies)

**Critical**: `.ado` and `.sthlp` files installed to `~/ado/plus/<letter>/` also
shadow repo copies. Stata searches `adopath` (which includes `~/ado/plus/`)
before CWD. After editing any .ado file, always `cp` to the installed path or
run `make install`.

**Logging**: `stata -b do ...` writes the log to CWD as `<basename>.log`, not
to the do file's directory. `stata -e` echoes to stdout.

**Documentation**: Every code change must check whether the following need updating:
- Subproject `README.md` (e.g., `kdensity2/README.md`, `nwreg/README.md`)
- `.sthlp` help files (e.g., `kdensity2/kdensity2.sthlp`, `nwreg/nwreg.sthlp`)
- Project root `README.md` (test results, feature tables)
- `AGENTS.md` (agent instructions)

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

## Testing

See `test/AGENTS.md` for full test suite structure, conventions, and
how to run timing benchmarks.

### Mandatory reproducibility tests (every C change)

```bash
stata -b do test/kdensity2/test_seed_reproducibility.do
stata -b do test/nwreg/test_seed_reproducibility.do
stata -b do test/fangorn/test_fangorn_seed_reproducibility.do
```

### Randomness sources

| Plugin | Source | Control |
|--------|--------|---------|
| fangorn | Internal LCG | `seed(12345)` → bit-identical |
| kdensity2/nwreg CV | ado `runiform()` shuffle | Re-`set seed` before each call |

### Stata 18 plugin program quirk

`program list` does NOT find plugin programs (rc=111 even when loaded).
The ado files handle this by attempting load and treating `_rc == 110`
("already defined") as success:
```stata
capture program _NAME, plugin using("`path'")
if _rc & _rc != 110 { display as error "..."; exit 111 }
```
This means the plugin loading block runs on EVERY call to the ado command,
but the second+ calls silently succeed via the rc=110 bypass.

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
- Limits: `MAX_DIM=10`, `MAX_GRID_POINTS=10000`, `MAX_GROUPS=50000`.

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
| Dataset documentation | `single_ado/dta2md.ado` | Export .dta metadata to Markdown for LLMs |
| GPU code (hidden feature) | `kdensity2/kdensity2_cuda.cu` | Float internally, tolerance 1e-5 |
| Reproducibility tests | `test/*/test_*_seed_reproducibility.do` | 10-run bit-identical checks |
| Python benchmark | `test/fangorn/benchmark/` | sklearn vs fangorn |

## Performance Benchmarks (16-core, Stata 18 MP)

Commands to reproduce timing:

```bash
# kdensity2
stata -b do test/kdensity2/test_cpu_reproducibility.do

# nwreg (3-variate)
stata -b do test/nwreg/test_cpu_reproducibility.do

# fangorn (n=10000, 10 features) — results from custom script
nproc(1) 1.0-9.0s → nproc(16) 1.0s (up to 9× speedup)
```

## opencode Skill

Local skill at `.opencode/skills/stata-plugin/SKILL.md` covers:
- Stata-C data transfer (`SF_vdata()`, `SF_vstore()`, `SF_mat_el()`)
- BLAS matrix operations via OpenBLAS
- Cross-platform Makefile templates (Linux/macOS/Windows)
- Plugin debugging (`stata_printf()` for C-level output)

Load with: `skill(name="stata-plugin")`
