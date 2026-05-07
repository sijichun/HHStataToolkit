# HHStataToolkit

A collection of high-performance Stata plugins for kernel-based statistical methods, written in C.

## Plugins

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **kdensity2** | Kernel density estimation | 1D/MV, target split, multi-group, product kernel |

## Project Structure

```
HHStataToolkit/
├── src/                     # Shared infrastructure
│   ├── stplugin.h/c         # Stata plugin interface (official)
│   ├── utils.h/c            # Common utilities (kernels, bandwidth, I/O)
├── Makefile                 # Multi-plugin build system
├── README.md                # This file
└── kdensity2/               # Plugin directory
    ├── kdensity2.c          # C implementation
    ├── kdensity2.ado        # Stata wrapper
    ├── kdensity2.plugin     # Compiled binary
    ├── kdensity2.sthlp      # Help file
    └── README.md            # Technical documentation
```

The `src/utils.h` and `src/utils.c` files provide reusable components (kernel functions, bandwidth selectors, Stata-C data transfer, memory helpers) for all plugins.

## Quick Start

### Linux / macOS

```bash
make              # Build all plugins
make kdensity2    # Build specific plugin
make install      # Install to ~/ado/plus/
make clean        # Remove build artifacts
```

### Windows (MinGW)

```bash
x86_64-w64-mingw32-gcc -shared -fPIC -DSYSTEM=STWIN32 \
  src/stplugin.c src/utils.c kdensity2/kdensity2.c \
  -o kdensity2/kdensity2.plugin -lm
```

## Adding a New Plugin

1. Create a subdirectory: `mkdir myplugin`
2. Write `myplugin/myplugin.c` (include `"stplugin.h"` and `"utils.h"`)
3. Write `myplugin/myplugin.ado`
4. Add `myplugin` to the `PLUGINS` variable in `Makefile`
5. Run `make myplugin`

See `kdensity2/README.md` for detailed implementation guidance.

## Platform Support

- Linux (64-bit)
- macOS (Intel & Apple Silicon)
- Windows (64-bit, MinGW)

## License

MIT License. `stplugin.h` and `stplugin.c` are official StataCorp files.
