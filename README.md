# HHStataToolkit

High-performance Stata plugins for kernel-based statistical methods and
decision trees, written in C. Includes standalone utility commands.

## Plugins

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **kdensity2** | Kernel density estimation | 1D/MV, target split, multi-group, product kernel, CV bandwidth |
| **nwreg** | Nadaraya-Watson kernel regression | 1D/MV, target split, multi-group, CV bandwidth, robust SE |
| **fangorn** | CART decision tree / random forest | Gini/Entropy/MSE, pre-sorted splits, CV depth selection, OOB error, MDI importance, mtry, Mermaid export |

## Standalone Utilities

| Command | Description |
|---------|-------------|
| **csadensity** | Common support area between treatment and control groups (kernel-based) |
| **bprecall** | Binary classification metrics (precision, recall, accuracy, F1) |
| **countdistinct** | Count distinct value combinations across variables |
| **gen_init_var** | Initialize panel variable by carrying forward a base-year value |
| **gencatutility** | Compute continuous utility scores for categorical variables |
| **labelvalidsample** | Create binary marker for complete-case observations |

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
├── single_ado/              # Pure Stata commands (no compilation needed)
├── test/                    # Test do-files, organised per plugin
│   ├── kdensity2/
│   ├── nwreg/
│   ├── fangorn/
│   │   ├── test_ent/        # Decision tree benchmark vs scikit-learn
│   │   └── test_rf/         # Random forest benchmark vs scikit-learn
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

# Run tests
stata -e do test/kdensity2/test_chi2_group.do
stata -e do test/nwreg/test_nwreg_simulation.do
stata -e do test/fangorn/test_fangorn_phase1.do
stata -e do test/fangorn/test_fangorn_phase2.do
stata -e do test/csa/test_csadensity.do
```

## Platform Support

- Linux (64-bit, GCC)
- macOS (Intel & Apple Silicon, Clang + brew install libomp)
- Windows (64-bit, MinGW cross-compile)

## License

MIT. `stplugin.h` and `stplugin.c` are official StataCorp files distributed
under their own terms.
