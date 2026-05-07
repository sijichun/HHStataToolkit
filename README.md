# HHStataToolkit

A collection of high-performance Stata plugins for kernel-based statistical methods, written in C, with additional standalone utility commands.

## Plugins

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **kdensity2** | Kernel density estimation | 1D/MV, target split, multi-group, product kernel |
| **nwreg** | Nadaraya-Watson kernel regression | 1D/MV, target split, multi-group, CV bandwidth |

## Standalone Utilities

| Command | Description |
|---------|-------------|
| **bprecall** | Binary classification metrics (precision, recall, accuracy, F1) across multiple thresholds |
| **countdistinct** | Count distinct value combinations across variables |
| **gen_init_var** | Initialize panel variable by carrying forward a base-year value within groups |
| **gencatutility** | Compute continuous utility scores for categorical variables |
| **labelvalidsample** | Create binary marker for complete-case observations |

## Project Structure

```
HHStataToolkit/
├── src/                     # Shared infrastructure
│   ├── stplugin.h/c         # Stata plugin interface (official)
│   ├── utils.h/c            # Common utilities (kernels, bandwidth, I/O)
├── Makefile                 # Multi-plugin build system
├── README.md                # This file
├── kdensity2/               # Kernel density plugin
│   ├── kdensity2.c / .ado / .sthlp / .plugin
│   └── README.md            # Technical documentation
├── nwreg/                   # Nadaraya-Watson regression plugin
│   ├── nwreg.c / .ado / .sthlp / .plugin
│   └── README.md            # Technical documentation
├── single_ado/              # Standalone Stata commands (no C code)
│   ├── bprecall.ado / .sthlp
│   ├── countdistinct.ado / .sthlp
│   ├── gen_init_var.ado / .sthlp
│   ├── gencatutility.ado / .sthlp
│   └── labelvalidsample.ado / .sthlp
└── test/                    # Test do-files
```

The `src/utils.h` and `src/utils.c` files provide reusable components (kernel functions, bandwidth selectors, Stata-C data transfer, memory helpers) for all plugins.

## Quick Start

### Linux / macOS

```bash
make              # Build all plugins
make kdensity2    # Build specific plugin
make nwreg        # Build nwreg plugin
make install      # Install all plugins and utilities to ~/ado/plus/
make dist         # Package for distribution to ado/
make clean        # Remove build artifacts
```

### Windows (MinGW)

```bash
# kdensity2
x86_64-w64-mingw32-gcc -shared -fPIC -DSYSTEM=STWIN32 \
  src/stplugin.c src/utils.c kdensity2/kdensity2.c \
  -o kdensity2/kdensity2.plugin -lm

# nwreg
x86_64-w64-mingw32-gcc -shared -fPIC -DSYSTEM=STWIN32 \
  src/stplugin.c src/utils.c nwreg/nwreg.c \
  -o nwreg/nwreg.plugin -lm
```

## Adding a New Plugin

1. Create a subdirectory: `mkdir myplugin`
2. Write `myplugin/myplugin.c` (include `"stplugin.h"` and `"utils.h"`)
3. Write `myplugin/myplugin.ado`
4. Write `myplugin/myplugin.sthlp` (help file)
5. Add `myplugin` to the `PLUGINS` variable in `Makefile`
6. Run `make myplugin`

See `kdensity2/README.md` or `nwreg/README.md` for detailed implementation guidance.

## Platform Support

- Linux (64-bit)
- macOS (Intel & Apple Silicon)
- Windows (64-bit, MinGW)

## License

MIT License. `stplugin.h` and `stplugin.c` are official StataCorp files.
