# HHStataToolkit — Project Knowledge Base

**Generated:** 2026-05-10

**Stata plugin collection** for kernel density estimation (kdensity2), kernel regression (nwreg), and CART decision trees / random forests (fangorn). C plugins + ado wrappers + standalone Stata utilities.

---

## TOPOGRAPHY

```
HHStataToolkit/
├── src/                  # Shared C: stplugin.h/c (NEVER modify), utils.h/c
├── kdensity2/            # Kernel density .c .ado .sthlp (single-file plugin)
├── nwreg/                # Nadaraya-Watson .c .ado .sthlp (single-file plugin)
├── fangorn/              # CART/RF: fangorn.c ent.c split.c utils_rf.c (multi-file)
├── single_ado/           # Pure Stata commands: bprecall, countdistinct, gen_*,
│                         #   gencatutility, labelvalidsample, csadensity
├── test/                 # Per-plugin subdirs: kdensity2/ nwreg/ fangorn/ csa/
├── Makefile              # Multi-plugin build system
└── AGENTS.md
```

---

## COMMANDS

### Build

```bash
make              # Build all plugins
make kdensity2    # Build single-file plugin
make nwreg
make fangorn      # Multi-file: custom rule in Makefile
make clean        # Remove .plugin files
make install      # .plugin → ~/ado/plus/, .ado/.sthlp → ~/ado/plus/<letter>/
                  #   ⚠ also installs single_ado/ — authoritative copy is in repo
make dist         # Package to ado/plus/ for distribution
```

### Test

```bash
stata -e do test/kdensity2/test_chi2_group.do
stata -e do test/nwreg/test_nwreg_simulation.do
stata -e do test/fangorn/test_fangorn_phase1.do
stata -e do test/fangorn/test_fangorn_phase2.do
stata -e do test/csa/test_csadensity.do

# sklearn vs fangorn unified benchmark (decision tree + random forest)
python test/fangorn/benchmark/test_benchmark.py
stata -e do test/fangorn/benchmark/test_fangorn_benchmark.do
```

---

## PLUGIN VARIABLE LAYOUT (1-based Stata indices)

| Plugin | Order |
|--------|-------|
| **kdensity2** | `varlist` → target → group → generate → touse |
| **nwreg** | `varlist`(regressors) → y → target → group → result → [se] → touse |
| **fangorn** | features → y → target → group → result → leaf_id → touse |

- **target=0** = training set, **target=1** = target/prediction set. All observations receive predictions, but only target=0 contributes to bandwidth/training. Typical use: treatment/control group analysis — train on control group (target=0), predict counterfactual density/regression for treatment group (target=1).
- **group**: string vars auto-encoded to numeric via `egen group()` in ado layer.
  Key advantage over official Stata commands: plugins handle multi-dimensional grouping (2+ group vars) natively.
  Official `kdensity` only supports a single `by()` group variable and cannot use string groups directly.

---

## GOTCHAS (miss these → bugs)

### OpenMP / Reproducibility

- **kdensity2 `kde_eval_mv` had a DATA RACE** (shared `u` array, OpenMP `reduction`). Fixed by removing `#pragma omp parallel for`. The function is now fully serial and reproducible.
- **nwreg `nw_eval_mv` and `nw_eval_mv_with_se`** same pattern — OpenMP removal ensures bit-identical results on repeated calls.
- **fangorn `build_random_forest`** uses OpenMP for parallel tree construction. Each thread gets its own LCG state (`seed + 9999 + t`). This is data-race-free and seeded for deterministic reproducibility per run.
- **fangorn `cv_select_depth`** uses OpenMP for independent depth candidates — safe.
- Default 8 threads. Override via `OMP_NUM_THREADS`. macOS needs `brew install libomp`.

### kdensity2 `if()` option

- **DO NOT pass `if(touse)` from a caller program.** kdensity2's `if(string)` option causes density estimates to differ from the no-if case, even when `touse=1` for all obs. Root cause unknown (likely data layout interaction). Instead, let kdensity2 compute on all obs and filter results externally.

### Stata 18 `if` qualifier bug

- `syntax varlist [if] [in], generate(string)` → "option if not allowed".
- Workaround: all ado files use `IF(string) IN(string)` as standard string options, not Stata's built-in qualifiers.

### Plugin path / tilde

- `plugin using("~/...")` does NOT expand `~`. Always: `local homedir : env HOME` + `subinstr(path, "~", "`homedir'")`.
- `findfile` searches adopath — the `.plugin` file in `~/ado/plus/` shadows the one in the repo subdir. After editing C code, always `make install` (or manually `cp`) to update `~/ado/plus/`.

### fangorn mtry

- **mtry was a no-op until 2026-05-10 fix.** `build_node_recursive` passed `rng=NULL` to `find_best_split`, so the condition `if (rng && mtry > 0)` was always false and all features were used.
- Fix: threaded `lcg_state_t*` through `build_tree()` → `build_node_recursive()` → `find_best_split()`.
- All call sites updated: `build_tree(tree, data, params, idx, n, rng)` with 6th arg. Single tree / CV pass `NULL`.
- For LCG state in RF: `lcg_seed(&rng, seed + 9999 + tree_idx)` (9999 avoids collision with bootstrap seed `seed + t`).

### fangorn model IO

- `generate(name)` creates leaf_id variable; prediction variable is `name_pred` (or custom via `predname()`).
- Single tree (`ntree=1`): leaf_id = heap-style node ID (root=0, left=2p+1, right=2p+2).
- Forest (`ntree>1`): leaf_id = 0 (placeholder). Predictions are ensemble averages.
- OOB error stored in scalar `__fangorn_oob_err`, returned via `r(oob_error)`.

### csadensity

- `varlist(min=1 numeric)` — string vars are REJECTED (unlike kdensity2 group vars).
- Internal formula: `min(f_t, f_nt)` → normalize by max → compare to `threshold(default=0.2)`.
- Inner call to kdensity2 with default kernel `triweight`.
- `debug` option keeps intermediate vars `_csad_f_t _csad_f_nt _csad_f_geom _csad_f_norm`.

### Stata return values

- `count` / `summarize` / `tabulate` commands **overwrite all `r()` scalars** from previous rclass programs. If you need `r(N_csa)` after csadensity, save it to a local before any `quietly count ...`.

### Memory / data flow

- Plugins read ALL data into C arrays first. Memory scales as `n_obs × n_vars`.
- `SF_nvar()` returns TOTAL dataset variables — never use for index math. Plugin index calculations are based on `ndensity + ntarget + ngroup + ...` from ado-level variable layout.
- `alloc_double_array()`, `alloc_double_matrix()` from `utils.c`. Always `free()`.
- `MAX_DIM=10`, `MAX_GRID_POINTS=10000`, `MAX_GROUPS=1000`.

### LSP false positives

- `__declspec` errors in `stplugin.h`: harmless Windows macro, ignored by GCC on Linux.

---

## fangorn SYNTAX REFERENCE

```stata
fangorn depvar indepvars, generate(name) [options]

  type(classify|regress)        Default: classify
  ntree(N)                      N=1: single tree; N>1: random forest (default 1)
  maxdepth(N)                   Default 20
  minsamplessplit(N)            Default 2
  minsamplesleaf(N)             Default 1
  minimpuritydecrease(real)     Absolute threshold (default 0.0)
  relimpdec(real)               Relative to root split gain (default 0.0)
  maxleafnodes(N)               Post-pruning limit
  criterion(gini|entropy|mse)   Auto: gini (classify), mse (regress)
  entcvdepth(N)                 CV depth selection (default 10, 0=disable)
  mtry(N)                       Features per split (auto: sqrt for classify, n/3 for regress)
  seed(N)                       RNG seed for bootstrap / CV shuffling (default 12345)
  target(varname)               Train/test split (0=train, 1=test/predict)
  group(varlist)                String vars auto-encoded
  mermaid(filename)             Export tree to Mermaid flowchart
  predname(name)                Custom prediction var name (default: generate_pred)
  if(string) in(string)         Standard options (not qualifiers)
```

---

## TEST FILES MAP

| File | What it tests |
|------|---------------|
| `test/kdensity2/test_chi2_group.do` | Chi-squared grouped density |
| `test/kdensity2/test_bivariate_group.do` | Bivariate grouped density |
| `test/kdensity2/test_minobs.do` | mincount option |
| `test/kdensity2/test_cv_compare.do` | CV bandwidth |
| `test/nwreg/test_nwreg_simulation.do` | NW regression simulation |
| `test/fangorn/test_fangorn_phase1.do` | Single decision tree |
| `test/fangorn/test_fangorn_phase2.do` | Random forest (ntree>1) |
| `test/fangorn/test_fangorn_regularization.do` | relimpdec, maxleafnodes |
| `test/csa/test_csadensity.do` | csadensity common support |
| `test/fangorn/benchmark/` | Unified DT + RF benchmark vs sklearn (10k obs, 12 features) |
