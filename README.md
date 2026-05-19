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

> **Note**: 对于因果推断，更好的方法是使用 **causal forest** 和 **generalized random forest**（Athey & Imbens, 2016; Athey, Tibshirani & Wager, 2019），仍待开发。当前 `xpofangorn` 通过双重机器学习（DML）提供了部分线性模型的估计，而 `fangorn` 的 `target()` 选项提供了一种简化的反事实预测方式，但两者尚不具备异质性处理效应（CATE）的无偏估计、honest 分裂等 causal forest 的核心特性。

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

An advantage over official Stata commands: `kdensity2` and `nwreg` handle **multi-dimensional grouping** natively (2+ group variables). Official `kdensity` only supports a single `by()` group variable and cannot use string group variables directly. In this toolkit, string group variables are auto-encoded to numeric via `egen group()` in the ado layer.

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
├── xpofangorn/              # DML partially linear model (pure Stata, calls fangorn)
├── single_ado/              # Pure Stata commands (no compilation needed)
├── test/                    # Test do-files, organised per plugin
│   ├── kdensity2/
│   ├── nwreg/
│   ├── fangorn/
│   │   ├── benchmark/       # Unified DT + RF benchmark vs scikit-learn
│   │   ├── test_fangorn_basic.do      # Quick integration smoke test
│   ├── xpofangorn/               # DML partially linear model tests
│   │   ├── test_fangorn_cv.do         # CV depth selection test
│   │   ├── test_fangorn_phase1.do     # Phase 1 decision tree tests
│   │   ├── test_fangorn_phase2.do     # Phase 2 random forest tests
│   │   ├── test_fangorn_regularization.do # Regularization tests
│   │   └── test_mermaid_output.do     # Mermaid export tests
│   └── csa/                 # csadensity tests
└── AGENTS.md                # Agent instruction file (replaces CLI help for AI)
```

## Quick Start

```bash
# Build all plugins
make

# Build individual plugins
make kdensity2
make nwreg
make fangorn

# Install to ~/ado/plus/ (both plugins + single_ado)
make install

# Package for distribution
make dist

# Reproducibility tests (bit-identical 10-run)
stata -b do test/kdensity2/test_seed_reproducibility.do
stata -b do test/kdensity2/test_cpu_reproducibility.do
stata -b do test/nwreg/test_seed_reproducibility.do
stata -b do test/nwreg/test_cpu_reproducibility.do
stata -b do test/fangorn/test_fangorn_seed_reproducibility.do

# Functional tests
stata -b do test/kdensity2/test_chi2_group.do
stata -b do test/nwreg/test_nwreg_simulation.do
stata -b do test/nwreg/test_local_polynomial.do
stata -b do test/nwreg/test_local_polynomial_reproducibility.do
stata -b do test/fangorn/test_fangorn_phase1.do
stata -b do test/fangorn/test_fangorn_phase2.do
stata -b do test/fangorn/test_fangorn_regularization.do
stata -b do test/fangorn/test_fangorn_basic.do
stata -b do test/fangorn/test_fangorn_cv.do
stata -b do test/csa/test_csadensity.do
```

## Development

This project was developed with AI-assisted tooling:
- **Orchestration**: [OpenCode](https://github.com/OhMyOpenCode/oh-my-opencode) + Oh-My-OpenAgent
- **Models**: kimi-for-coding (frontend/reasoning) + DeepSeek V4 Flash (backend/execution)

## Platform Support

- Linux (64-bit, GCC)
- macOS (Intel & Apple Silicon, Clang + brew install libomp)
- Windows (64-bit, MinGW cross-compile)

## License

MIT. `stplugin.h` and `stplugin.c` are official StataCorp files distributed
under their own terms.
