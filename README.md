# HHStataToolkit

High-performance Stata plugins for kernel-based statistical methods and
decision trees, written in C. Includes standalone utility commands.

## Plugins

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **kdensity2** | Kernel density estimation | 1D/MV, target split (train/predict), multi-group, product kernel, CV bandwidth. GPU acceleration via `make kdensity2_cuda` (hidden feature). |
| **nwreg** | Nadaraya-Watson / local polynomial kernel regression | 1D/MV, target split (train/predict), multi-group, CV bandwidth, robust SE, local polynomial (`poly()`), derivatives (`derivatives()`). GPU acceleration via `make nwreg_cuda` (hidden feature). |
| **fangorn** | CART decision tree / random forest | Gini/Entropy/MSE, pre-sorted splits, CV depth selection, OOB error, MDI importance, mtry, ntiles quantile strategy, Mermaid export |
| **xpofangorn** | Partially linear model via DML | Double machine learning, K-fold cross-fitting, auto-detect binary/continuous treatment, robust and cluster SE, all fangorn options pass-through |
| **grf** | Causal forest for heterogeneous treatment effects (CATE) | Honest splitting, R-learner orthogonalization (internal nuisance forests), OOB predictions, variance estimation via "bootstrap of little bags", cluster/weights support. C++17 required. Adapted from [grf-labs/grf](https://github.com/grf-labs/grf) v2.6.1 (GPL-3.0). R-vs-Stata parity: 0.997 correlation. |



## Standalone Utilities

| Command | Description |
|---------|-------------|
| **csadensity** | Common support area between treatment and control groups (kernel-based) |
| **bprecall** | Binary classification metrics (precision, recall, accuracy, F1) |
| **countdistinct** | Count distinct value combinations across variables |
| **dta2md** | Export .dta metadata & descriptive statistics to Markdown (LLM-readable dataset documentation) |
| **gen_init_var** | Initialize panel variable by carrying forward a base-year value |
| **gencatutility** | Compute continuous utility scores for categorical variables |
| **labelvalidsample** | Create binary marker for complete-case observations |

## Core Features

### Target Split (Training / Prediction)

All estimation plugins (`kdensity2`, `nwreg`, `fangorn`) support a **target split** via the `target(varname)` option:

- **target=0** = **training set** — these observations contribute to bandwidth selection / model training
- **target=1** = **target/prediction set** — these observations receive predictions but do NOT influence training

This is particularly useful for **treatment/control analysis**: train on the control group (`target=0`), then predict the counterfactual density or regression outcome for the treatment group (`target=1`). Both groups receive estimates, but bandwidths and model parameters are determined solely by the training set.

### Group Variable Handling

An advantage over official Stata commands: `kdensity2` and `nwreg` handle **multi-dimensional grouping** natively (2+ group variables). Official `kdensity` only supports a single `by()` group variable and cannot use string group variables directly. In this toolkit, string group variables are auto-encoded to numeric via `egen group()` in the ado layer, and observations with missing group values are excluded from estimation.

By default, grouped estimation in `kdensity2` yields **conditional densities** f(x|g) — each group's estimate integrates to 1 within the group (the same convention as official `kdensity`). With the `gnormalize` option, each group's density is scaled by its sample share p(g) = n_g/N, so the group curves aggregate to the overall **mixture density** f(x) = Σ_g p(g)·f(x|g). Use the default for comparing distribution shapes across groups; use `gnormalize` for decomposition/counterfactual analysis (e.g., DFL-style decompositions, stacked-area plots). Note: because each group selects its own bandwidth, the weighted sum approximates — but is not identical to — the density estimated on the pooled sample.

### Causal Forest — Heterogeneous Treatment Effects (`grf`)

`grf` implements the causal forest algorithm (Athey, Tibshirani & Wager, 2019) for estimating **conditional average treatment effects** (CATE | X). It wraps the upstream [GRF C++ core library](https://github.com/grf-labs/grf) v2.6.1 via a thin C++ adapter.

**Syntax**: `grf y w x1 x2 ... , generate(newvar) [options]`

Key characteristics:

- **Honest splitting** (default): the training subsample is split into two independent parts — one for choosing splits, one for estimating leaf-level treatment effects. Reduces overfitting; required for valid confidence intervals.
- **R-learner orthogonalization**: nuisance functions E[Y|X] and E[W|X] are estimated via internal regression forests (or user-provided via `yhat()`/`what()`). Outcomes and treatments are centered before forest training, isolating the treatment effect from confounding (Nie & Wager, 2021).
- **Out-of-bag (OOB) predictions**: each tree is trained on a bootstrap subsample; observations left out receive predictions only from trees that did not use them, providing unbiased CATE estimates. Saved via `oobgenerate()`.
- **Variance estimation**: the "bootstrap of little bags" delta method accounting for both tree- and forest-level uncertainty. Activated via `vargenerate()`; requires `cigroupsize(>=2)`.
- **Cluster and weight support**: cluster-robust variance (`cluster(varname)`), sample weights (`weights(varname)`), optional `equalizeclusterweights`.
- **R-vs-Stata parity**: CATE estimates correlate at **0.997** with the official [grf R package](https://github.com/grf-labs/grf) under identical data, seed, nuisance, and mtry settings.
- **Build requirement**: C++17 (pre-built plugin included in releases; downstream users do not need to build).

## Project Structure

```
HHStataToolkit/
├── src/                     # Shared C infrastructure
│   ├── stplugin.h/c         # Stata plugin interface (official, do not modify)
│   └── utils.h/c            # Kernels, bandwidth, Stata↔C I/O, memory helpers
├── Makefile                 # Multi-plugin build system
├── kdensity2/               # Kernel density plugin (single-file C)
├── nwreg/                   # Nadaraya-Watson regression plugin (single-file C)
├── fangorn/                 # Decision tree / random forest (multi-file C)
├── grf/                     # Causal forest (C++17, wraps grf-labs/grf v2.6.1)
│   ├── grf_stata.cpp        # Stata plugin entry + data bridge
│   ├── vendor/              # Upstream GRF C++ core + Eigen
│   └── grf.ado / .sthlp     # Stata command and help
├── xpofangorn/              # DML partially linear model (pure Stata, calls fangorn)
├── single_ado/              # Pure Stata commands (no compilation needed)
├── tests/                   # Test do-files, organised per plugin
│   ├── kdensity2/
│   │   ├── test_gnormalize.do  # gnormalize option
│   ├── nwreg/
│   ├── fangorn/
│   │   ├── benchmark/       # Unified DT + RF benchmark vs scikit-learn
│   │   └── ...
│   ├── grf/                 # Causal forest tests (9 suites)
│   ├── xpofangorn/
│   └── csa/                 # csadensity tests
├── AGENTS.md                # Agent instruction file (replaces CLI help for AI)
├── README.md
├── README4AI.md             # LLM-oriented command reference
└── LICENSE.md / LICENSES.md / TODO.md / Releases/
```

## Quick Start

```bash
# Build all plugins
make

# Build individual plugins
make kdensity2
make nwreg
make fangorn
make grf

# Install to ~/ado/plus/ (all plugins + single_ado, including grf)
make install

# Package for distribution
make dist

# Test suite
stata -b do tests/run_all.do
```
```

## Development

This project was developed with AI-assisted tooling:
- **Orchestration**: [OpenCode](https://github.com/OhMyOpenCode/oh-my-opencode) + Oh-My-OpenAgent
- **Models**: kimi-for-coding (frontend/reasoning) + DeepSeek V4 Flash (backend/execution)

## Platform Support

- Linux (64-bit, GCC)
- macOS (Intel & Apple Silicon, Clang + `brew install libomp` for OpenMP, see below for build details)
- Windows (64-bit, MinGW-w64 cross-compile; pre-built binary in Releases)

> **Note**: Pre-built binary releases include plugins for Linux and Windows only. macOS users need to build from source.

### macOS Build Notes

Building from source on macOS requires a few dependencies:

```bash
# Install OpenMP (not bundled with Apple Clang)
brew install libomp

# Install OpenBLAS (for BLAS-accelerated routines)
brew install openblas

# pkg-config must be able to find openblas
export PKG_CONFIG_PATH="/opt/homebrew/opt/openblas/lib/pkgconfig:$PKG_CONFIG_PATH"

# Build
make
make install
```

Intel Macs may use `/usr/local` instead of `/opt/homebrew`. Adjust `PKG_CONFIG_PATH` accordingly. Once built, the plugin works on both Intel and Apple Silicon Stata versions.

## License

HHStataToolkit's own code and documentation are licensed under GPL-3.0-or-later.
`stplugin.h` and `stplugin.c` are official StataCorp files distributed under
their own terms. The `grf/` plugin incorporates code from
[grf-labs/grf](https://github.com/grf-labs/grf) v2.6.1 (GPL-3.0).
GRF and other bundled third-party material retain their original notices and
licenses; see [LICENSES.md](LICENSES.md).
