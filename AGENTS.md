# HHStataToolkit - Project Knowledge Base

**Generated:** 2026-05-09

## OVERVIEW

Stata plugin collection for kernel-based methods and decision trees. C plugins + ado wrappers.

| Plugin | Description | C Files |
|--------|-------------|---------|
| `kdensity2` | 1D/MV kernel density estimation | `kdensity2.c` (single) |
| `nwreg` | Nadaraya-Watson kernel regression | `nwreg.c` (single) |
| `fangorn` | CART decision tree / random forest | `fangorn.c`, `ent.c`, `split.c`, `utils_rf.c` (multi) |

Standalone utilities (no C compilation): `bprecall`, `countdistinct`, `gen_init_var`, `gencatutility`, `labelvalidsample` in `single_ado/`.

## STRUCTURE

```
HHStataToolkit/
├── src/
│   ├── stplugin.h/c     # Stata official plugin interface (NEVER modify)
│   └── utils.h/c        # Shared: kernels, bandwidth, Stata↔C I/O, memory
├── kdensity2/
│   ├── kdensity2.c / .ado / .sthlp / README.md
├── nwreg/
│   ├── nwreg.c / .ado / .sthlp / README.md
├── fangorn/             # Multi-file plugin (special Makefile rule)
│   ├── fangorn.c / ent.c / split.c / utils_rf.c
│   ├── ent.h / split.h / utils_rf.h
│   ├── fangorn.ado / .sthlp / README.md
├── single_ado/          # Pure Stata commands (no C code)
│   ├── bprecall.ado / .sthlp
│   ├── countdistinct.ado / .sthlp
│   ├── gen_init_var.ado / .sthlp
│   ├── gencatutility.ado / .sthlp
│   └── labelvalidsample.ado / .sthlp
├── test/
│   ├── test_chi2_group.do
│   ├── test_bivariate_group.do
│   ├── test_minobs.do
│   ├── test_cv_compare.do
│   ├── test_nwreg_simulation.do
│   ├── test_fangorn_phase1.do
│   ├── test_fangorn_regularization.do
│   ├── test_ent/        # fangorn benchmark vs scikit-learn
│   └── test_mermaid_output.do
├── Makefile
└── AGENTS.md            # This file
```

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Add a new kernel function | `src/utils.c` → kernel table, `src/utils.h` → enum |
| Add a new bandwidth rule | `src/utils.c` → bandwidth selectors |
| Add a new Stata↔C utility | `src/utils.h/c` |
| Modify density estimation | `kdensity2/kdensity2.c` |
| Modify regression estimation | `nwreg/nwreg.c` |
| Modify decision tree logic | `fangorn/ent.c`, `fangorn/split.c` |
| Modify Stata syntax/options | `*/<name>.ado` |
| Build a single-file plugin | `make kdensity2`, `make nwreg` |
| Build fangorn (multi-file) | `make fangorn` |
| Build everything | `make` |
| Install to user's Stata | `make install` |
| Package for distribution | `make dist` |
| Run a test | `stata -e do test/test_chi2_group.do` |
| Check technical docs | `kdensity2/README.md`, `nwreg/README.md`, `fangorn/README.md` |

## CONVENTIONS

- **File naming**: Plugin directory = command name; files inside use same prefix.
- **Includes**: Plugin `.c` files include `"stplugin.h"` and `"utils.h"` (Makefile adds `-Isrc`).
- **Single-file plugins** (`kdensity2`, `nwreg`): One `.c` file per plugin. Generic build rule in Makefile.
- **Multi-file plugins** (`fangorn`): Custom Makefile rule listing all object files. Follow the `fangorn:` target pattern.
- **Variable layouts differ by plugin**:
  - `kdensity2` / `nwreg`: density/regressors → target → group → result → touse
  - `fangorn`: features → y → target → group → result → leaf_id → touse
- **Target convention**: `target=0` = training data, `target=1` = test data. All obs receive predictions.
- **Group handling**: String group vars are auto-encoded to numeric in ado layer via `egen group()`.
- **Memory**: Use `alloc_double_array()` / `alloc_double_matrix()` from utils; always `free()`.
- **Install layout**: `.plugin` → `~/ado/plus/` (top level), `.ado`/`.sthlp` → `~/ado/plus/<first-letter>/`.
- **OpenMP**: Default 8 threads. Override via `OMP_NUM_THREADS`. Uses `UTILS_OMP_SET_NTHREADS()` macro in utils.h. macOS needs `brew install libomp`.
- **Plugin loading**: `capture program _<name>_plugin, plugin using(...)` (capture avoids "already defined" on repeated calls).

## CRITICAL GOTCHAS

- **Stata 18 `if` qualifier bug**: `syntax varlist [if] [in] , generate(string)` fails with "option if not allowed". Workaround: use `if(exp)` as a standard option, not Stata's built-in qualifier.
- **`~` not expanded in `plugin using()`**: When `findfile` returns `~/ado/plus/kdensity2.plugin`, `program define, plugin using("~/...")` fails. Always expand via `:env HOME`.
- **`SF_nvar()` returns TOTAL dataset vars, not varlist count**: Index calculations must use `ndensity + ntarget + ngroup + ...`, not `SF_nvar()`.
- **`SF_ifobs()` unreliable**: Don't use `plugin call ... if touse` + `SF_ifobs()` — pass `touse` as an explicit variable instead.
- **CV shuffle**: When `bw(cv)`, the ado file randomly shuffles data before calling the plugin (ensures randomized CV folds), then restores original sort order.

## ANTI-PATTERNS

- **Do NOT** modify `stplugin.h` or `stplugin.c` — official StataCorp files.
- **Do NOT** add grid generation — plugins evaluate at data points only.
- **Do NOT** hardcode bandwidth — always use `compute_bandwidth()` or utils selectors.
- **Do NOT** forget `free()` for `double*`/`double**` allocated inside loops (grouped estimation).
- **Do NOT** mix `train` and `target` naming — project uses `target` exclusively (0=train, 1=test).

## COMMANDS

```bash
# Build
make                    # Build all plugins
make kdensity2          # Build specific single-file plugin
make nwreg              # Build nwreg
make fangorn            # Build fangorn (multi-file, custom rule)
make clean              # Remove .plugin files and ado/
make install            # Copy to ~/ado/plus/ (letter-based for .ado/.sthlp)
make dist               # Package to ado/ in project root

# Run Stata do-file from command line
stata -e do test/test_chi2_group.do
stata -e do test/test_nwreg_simulation.do
stata -e do test/test_fangorn_phase1.do

# Windows cross-compile (from Linux/macOS)
# Single-file plugin:
x86_64-w64-mingw32-gcc -shared -fPIC -DSYSTEM=STWIN32 \
  src/stplugin.c src/utils.c kdensity2/kdensity2.c \
  -o kdensity2/kdensity2.plugin -lm

# Multi-file plugin (fangorn):
x86_64-w64-mingw32-gcc -shared -fPIC -O3 -fopenmp -static-libgcc \
  -Wl,-Bstatic -lgomp -Wl,-Bdynamic \
  src/stplugin.c src/utils.c \
  fangorn/fangorn.c fangorn/ent.c fangorn/split.c fangorn/utils_rf.c \
  -o fangorn/fangorn.plugin
```

## ADDING A NEW PLUGIN

### Single-file plugin (like kdensity2, nwreg)

1. `mkdir myplugin && touch myplugin/myplugin.c myplugin/myplugin.ado myplugin/myplugin.sthlp`
2. In `myplugin.c`: `#include "stplugin.h"` + `#include "utils.h"`, implement `stata_call()`
3. Call `UTILS_OMP_SET_NTHREADS();` at the top of `stata_call()`
4. In `Makefile`: add `myplugin` to `PLUGINS` list
5. `make myplugin`

### Multi-file plugin (like fangorn)

1. Create directory with all `.c` / `.h` files
2. Add a custom target in `Makefile` (see `fangorn:` target for pattern)
3. `make myplugin`

## NOTES

- `utils.h` defines `MAX_DIM=10` and `MAX_GRID_POINTS=10000`
- `MAX_GROUPS=1000` hardcoded in `kdensity2.c` and `nwreg.c`
- Plugin reads all data into C arrays first (not streaming), so memory scales with `n_obs × n_vars`
- LSP errors on `__declspec` in `stplugin.h` are false positives (Windows-specific macro, harmless on Linux)
- CV bandwidth: `bw(cv)` default 10 folds, 10 grid candidates per side. Customize via `folds(N)`, `grids(N)`.
- `mincount(N)` skips groups with fewer than N observations (result set to missing)
- `fangorn` outputs both prediction and `leaf_id` (heap-style node ID); use `mermaid(filename)` to export tree diagram
