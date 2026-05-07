# HHStataToolkit - Project Knowledge Base

**Generated:** 2026-05-07

## OVERVIEW

Stata plugin collection for kernel-based methods. C plugins + ado wrappers. Currently ships `kdensity2` (1D/MV kernel density estimation with target split and multi-group support).

## STRUCTURE

```
HHStataToolkit/
├── src/
│   ├── stplugin.h/c     # Stata official plugin interface (NEVER modify)
│   └── utils.h/c        # Shared: kernels, bandwidth, Stata↔C I/O, memory
├── kdensity2/
│   ├── kdensity2.c      # Plugin: density eval, group handling, target split
│   ├── kdensity2.ado    # Stata wrapper: syntax parsing, plugin invocation
│   ├── kdensity2.sthlp  # Help file
│   └── README.md        # Technical docs (math, API, design decisions)
├── test/
│   ├── test_chi2_group.do       # Chi-square grouped test
│   ├── test_bivariate_group.do  # Bivariate grouped test
│   ├── test_minobs.do           # mincount() test
│   └── test_cv_compare.do       # CV vs Silverman comparison
├── Makefile             # Multi-plugin build (Linux/macOS/Windows)
├── README.md
└── AGENTS.md            # This file
```

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Add a new kernel function | `src/utils.c` → kernel table, `src/utils.h` → enum |
| Add a new bandwidth rule | `src/utils.c` → bandwidth selectors |
| Add a new Stata↔C utility | `src/utils.h/c` |
| Modify density estimation logic | `kdensity2/kdensity2.c` |
| Modify Stata syntax/options | `kdensity2/kdensity2.ado` |
| Build the plugin | `make` or `make kdensity2` |
| Install to user's Stata | `make install` (copies to `~/ado/plus/`) |
| Package for distribution | `make dist` (copies to `ado/` in project root) |
| Run tests | `stata -e do test/test_chi2_group.do` |
| Check technical docs | `kdensity2/README.md` (math, all C functions) |

## CONVENTIONS

- **File naming**: Plugin directory = command name; files inside use same prefix (`kdensity2.c`, `kdensity2.ado`, etc.)
- **Includes**: Plugin `.c` files include `"stplugin.h"` and `"utils.h"` (Makefile adds `-Isrc`)
- **Variable layout in Stata→C**: density vars first, then target (if any), then group vars, last = output var, last+1 = touse var
- **Target convention**: `target=0` = training data, `target=1` = test data. All obs (0 and 1) receive density values.
- **Group handling**: String group vars are auto-encoded to numeric in ado layer via `egen group()`
- **Memory**: Use `alloc_double_array()` / `alloc_double_matrix()` from utils; always `free()`
- **Install layout**: `.plugin` → `~/ado/plus/` (top level), `.ado`/`.sthlp` → `~/ado/plus/<first-letter>/` (Stata auto-finds subdirs for ado files, but `findfile` only finds `.plugin` at top level)
- **OpenMP**: Default 8 threads. Override via `OMP_NUM_THREADS`. Uses `UTILS_OMP_SET_NTHREADS()` macro in utils.h. macOS needs `brew install libomp`.
- **Plugin loading**: `capture program _kdensity2_plugin, plugin using(...)` (capture avoids "already defined" on repeated calls per session)

## CRITICAL GOTCHAS

- **Stata 18 `if` qualifier bug**: `syntax varlist [if] [in] , generate(string)` fails with "option if not allowed". Workaround: use `if(exp)` as a standard option, not Stata's built-in qualifier.
- **`~` not expanded in `plugin using()`**: When `findfile` returns `~/ado/plus/kdensity2.plugin`, `program define, plugin using("~/...")` fails. Always expand via `:env HOME`.
- **`SF_nvar()` returns TOTAL dataset vars, not varlist count**: Index calculations must use `ndensity + ntarget + ngroup + ...`, not `SF_nvar()`.
- **`SF_ifobs()` unreliable**: Don't use `plugin call ... if touse` + `SF_ifobs()` — pass `touse` as an explicit variable instead.
- **CV shuffle**: When `bw(cv)`, the ado file randomly shuffles data before calling the plugin (ensures randomized CV folds), then restores original sort order.

## ANTI-PATTERNS

- **Do NOT** modify `stplugin.h` or `stplugin.c` — official Stata files
- **Do NOT** add grid generation — this plugin evaluates at data points only
- **Do NOT** hardcode bandwidth — always use `compute_bandwidth()` or utils selectors
- **Do NOT** forget `free()` for `double*`/`double**` allocated inside loops (grouped estimation)
- **Do NOT** mix `train` and `target` naming — project uses `target` exclusively (0=train, 1=test)

## COMMANDS

```bash
# Build
make                    # Build all plugins
make kdensity2          # Build specific plugin
make clean              # Remove .plugin files and ado/
make install            # Copy to ~/ado/plus/ (letter-based for .ado/.sthlp)
make dist               # Package to ado/ in project root

# Run Stata do-file from command line
stata -e do test/test_chi2_group.do

# Windows cross-compile (from Linux/macOS)
x86_64-w64-mingw32-gcc -shared -fPIC -DSYSTEM=STWIN32 \
  src/stplugin.c src/utils.c kdensity2/kdensity2.c \
  -o kdensity2/kdensity2.plugin -lm
```

## ADDING A NEW PLUGIN

1. `mkdir myplugin && touch myplugin/myplugin.c myplugin/myplugin.ado`
2. In `myplugin.c`: `#include "stplugin.h"` + `#include "utils.h"`, implement `stata_call()`
3. Call `UTILS_OMP_SET_NTHREADS();` at the top of `stata_call()`
4. In `Makefile`: add `myplugin` to `PLUGINS` list
5. `make myplugin`

## NOTES

- `utils.h` defines `MAX_DIM=10` and `MAX_GRID_POINTS=10000`
- `MAX_GROUPS=1000` hardcoded in `kdensity2.c`
- Plugin reads all data into C arrays first (not streaming), so memory scales with `n_obs × n_vars`
- LSP errors on `__declspec` in `stplugin.h` are false positives (Windows-specific macro, harmless on Linux)
- CV bandwidth: `bw(cv)` default 10 folds, 10 grid candidates per side. Customize via `folds(N)`, `grids(N)`.
- `mincount(N)` skips groups with fewer than N observations (result set to missing)
