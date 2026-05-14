# Stata Kernel Plugins - Multi-plugin Makefile
# Supports: Linux, macOS, Windows (cross-compile)
#
# Project root = HHStataToolkit/
# Plugin sources live in subdirectories: kdensity/kdensity.c, kregress/kregress.c, etc.
# Shared headers are at root level: stplugin.h, utils.h
#
# Usage:
#   make              - Build all plugins
#   make kdensity     - Build kdensity only
#   make clean        - Remove all built files
#   make install      - Install all plugins to ~/ado/plus/

# Shared source files (under src/)
COMMON_SRC = src/stplugin.c src/utils.c src/ols.c

# Plugin subdirectories (single-file plugins)
PLUGINS = kdensity2 nwreg

# Standalone ado files (no C compilation needed)
SINGLE_ADO_DIR = single_ado
SINGLE_ADO_FILES = $(wildcard $(SINGLE_ADO_DIR)/*.ado)

# Detect platform
UNAME_S := $(shell uname -s)

# Compiler settings
CC = gcc
CFLAGS = -O3 -Wall -Isrc -fopenmp
LDFLAGS = -lm -fopenmp
BLAS_LIBS = -lopenblas

# CUDA settings (optional)
NVCC := $(shell which nvcc 2>/dev/null)
CUDA_ARCH ?= sm_60
CUDA_FLAGS = -shared -Xcompiler -fPIC -arch=$(CUDA_ARCH) -Isrc -DUSE_CUDA -DSYSTEM=OPUNIX

# Windows OpenBLAS static-link settings (override as needed)
# Example:
#   make OS=Windows_NT OPENBLAS_DIR=/opt/mingw-openblas
OPENBLAS_DIR ?= /usr/x86_64-w64-mingw32
OPENBLAS_INC ?= $(OPENBLAS_DIR)/include
OPENBLAS_LIB ?= $(OPENBLAS_DIR)/lib
WINDOWS_OPENBLAS_STATIC_LIBS ?= -Wl,-Bstatic -lopenblas -lgfortran -lquadmath -lgomp -lwinpthread -Wl,-Bdynamic -lm

# Platform-specific flags (mutually exclusive)
ifeq ($(OS),Windows_NT)
    CC = x86_64-w64-mingw32-gcc
    # Note: -DSYSTEM=STWIN32 not needed; stplugin.h defaults to STWIN32
    CFLAGS += -shared -fPIC -O3 -Wall -Isrc -I$(OPENBLAS_INC)
    # Static-link OpenBLAS and MinGW runtime deps so the plugin works
    # without a separate OpenBLAS install on the target Windows machine.
    LDFLAGS = -fopenmp -static-libgcc -static -L$(OPENBLAS_LIB)
    BLAS_LIBS = $(WINDOWS_OPENBLAS_STATIC_LIBS)
    PLUGIN_EXT = .plugin
else ifeq ($(UNAME_S),Linux)
    CFLAGS += -shared -fPIC -DSYSTEM=OPUNIX
    PLUGIN_EXT = .plugin
else ifeq ($(UNAME_S),Darwin)
    CC = clang
    CFLAGS += -bundle -DSYSTEM=APPLEMAC
    PLUGIN_EXT = .plugin
endif

# Build targets
.PHONY: all clean install dist help check-openblas $(PLUGINS) fangorn kdensity2_cuda nwreg_cuda

CUDA_TARGETS :=
ifneq ($(NVCC),)
CUDA_TARGETS += kdensity2_cuda nwreg_cuda
endif

check-openblas:
ifeq ($(UNAME_S),Linux)
ifneq ($(OS),Windows_NT)
	@pkg-config --exists openblas 2>/dev/null || ldconfig -p 2>/dev/null | grep -q libopenblas || { \
		echo ""; \
		echo "Error: OpenBLAS not found."; \
		echo "Install with:"; \
		echo "  Debian/Ubuntu:  sudo apt install libopenblas-dev"; \
		echo "  RHEL/Fedora:    sudo dnf install openblas-devel"; \
		echo "  Arch:           sudo pacman -S openblas"; \
		echo ""; \
		exit 1; \
	}
endif
endif

all: $(PLUGINS) fangorn

# Generic plugin build rule (for single-file plugins)
$(PLUGINS): check-openblas
	@echo "Building $@..."
	$(CC) $(CFLAGS) $(COMMON_SRC) $@/$@.c -o $@/$@$(PLUGIN_EXT) $(LDFLAGS) $(BLAS_LIBS)
	@echo "$@ build complete."

# Special rule for fangorn (multiple source files)
fangorn: check-openblas $(PLUGINS)
	@echo "Building fangorn..."
	$(CC) $(CFLAGS) $(COMMON_SRC) fangorn/fangorn.c fangorn/ent.c fangorn/split.c fangorn/utils_rf.c -o fangorn/fangorn.plugin $(LDFLAGS) $(BLAS_LIBS)
	@echo "fangorn build complete."

# CUDA-accelerated kdensity2 plugin (requires nvcc)
kdensity2_cuda:
ifeq ($(NVCC),)
	@echo "Error: nvcc not found; cannot build kdensity2_cuda."
	@exit 1
else
	@echo "Building kdensity2_cuda..."
	$(NVCC) $(CUDA_FLAGS) $(COMMON_SRC) kdensity2/kdensity2.c kdensity2/kdensity2_cuda.cu -o kdensity2/kdensity2_cuda.plugin -lm -lcudart_static -lpthread -ldl
	@echo "kdensity2_cuda build complete (cudart statically linked)."
endif

# CUDA-accelerated nwreg plugin (requires nvcc)
nwreg_cuda:
ifeq ($(NVCC),)
	@echo "Error: nvcc not found; cannot build nwreg_cuda."
	@exit 1
else
	@echo "Building nwreg_cuda..."
	$(NVCC) $(CUDA_FLAGS) $(COMMON_SRC) nwreg/nwreg.c nwreg/nwreg_cuda.cu -o nwreg/nwreg_cuda.plugin -lm -lcudart_static -lpthread -ldl
	@echo "nwreg_cuda build complete (cudart statically linked)."
endif

# Clean all plugins
clean:
	@for p in $(PLUGINS); do \
		echo "Cleaning $$p..."; \
		rm -f $$p/$$p.plugin; \
	done
	@echo "Cleaning fangorn..."
	@rm -f fangorn/fangorn.plugin
	@echo "Cleaning kdensity2_cuda..."
	@rm -f kdensity2/kdensity2_cuda.plugin
	@echo "Cleaning nwreg_cuda..."
	@rm -f nwreg/nwreg_cuda.plugin
	@rm -rf ado/plus

# Install: .plugin → ~/ado/plus/, .ado/.sthlp → ~/ado/plus/<letter>/
install: all
	@echo "Installing to ~/ado/plus/"
	@mkdir -p ~/ado/plus
	@for p in $(PLUGINS); do \
		letter=$$(echo $$p | cut -c1); \
		cp $$p/$$p.plugin ~/ado/plus/ 2>/dev/null || true; \
		cp $$p/$$p.ado ~/ado/plus/$$letter/ 2>/dev/null || mkdir -p ~/ado/plus/$$letter && cp $$p/$$p.ado ~/ado/plus/$$letter/ 2>/dev/null || true; \
		cp $$p/$$p.sthlp ~/ado/plus/$$letter/ 2>/dev/null || mkdir -p ~/ado/plus/$$letter && cp $$p/$$p.sthlp ~/ado/plus/$$letter/ 2>/dev/null || true; \
		echo "  Installed $$p"; \
	done
	@echo "Installing fangorn..."
	@cp fangorn/fangorn.plugin ~/ado/plus/ 2>/dev/null || true
	@mkdir -p ~/ado/plus/f && cp fangorn/fangorn.ado ~/ado/plus/f/ 2>/dev/null || true
	@cp fangorn/fangorn.sthlp ~/ado/plus/f/ 2>/dev/null || true
	@echo "  Installed fangorn"
ifneq ($(wildcard kdensity2/kdensity2_cuda.plugin),)
	@echo "Installing kdensity2_cuda..."
	@cp kdensity2/kdensity2_cuda.plugin ~/ado/plus/ 2>/dev/null || true
	@echo "  Installed kdensity2_cuda"
endif
ifneq ($(wildcard nwreg/nwreg_cuda.plugin),)
	@echo "Installing nwreg_cuda..."
	@cp nwreg/nwreg_cuda.plugin ~/ado/plus/ 2>/dev/null || true
	@echo "  Installed nwreg_cuda"
endif
	@echo "Installing single_ado files..."
	@for f in $(SINGLE_ADO_FILES); do \
		base=$$(basename $$f .ado); \
		letter=$$(echo $$base | cut -c1); \
		mkdir -p ~/ado/plus/$$letter; \
		cp $$f ~/ado/plus/$$letter/ 2>/dev/null || true; \
		if [ -f $(SINGLE_ADO_DIR)/$$base.sthlp ]; then \
			cp $(SINGLE_ADO_DIR)/$$base.sthlp ~/ado/plus/$$letter/ 2>/dev/null || true; \
		fi; \
		echo "  Installed $$base"; \
	done
	@echo "Installation complete."

# Package: .plugin → ado/p/, .ado/.sthlp → ado/<letter>/
dist: all
	@echo "Packaging to ado/plus/..."
	@mkdir -p ado/plus
	@for p in $(PLUGINS); do \
		letter=$$(echo $$p | cut -c1); \
		cp $$p/$$p.plugin ado/plus/ 2>/dev/null || true; \
		mkdir -p ado/plus/$$letter; \
		cp $$p/$$p.ado ado/plus/$$letter/ 2>/dev/null || true; \
		cp $$p/$$p.sthlp ado/plus/$$letter/ 2>/dev/null || true; \
		echo "  Packaged $$p"; \
	done
	@echo "Packaging fangorn..."
	@cp fangorn/fangorn.plugin ado/plus/ 2>/dev/null || true
	@mkdir -p ado/plus/f && cp fangorn/fangorn.ado ado/plus/f/ 2>/dev/null || true
	@cp fangorn/fangorn.sthlp ado/plus/f/ 2>/dev/null || true
	@echo "  Packaged fangorn"
ifneq ($(wildcard kdensity2/kdensity2_cuda.plugin),)
	@echo "Packaging kdensity2_cuda..."
	@cp kdensity2/kdensity2_cuda.plugin ado/plus/ 2>/dev/null || true
	@echo "  Packaged kdensity2_cuda"
endif
ifneq ($(wildcard nwreg/nwreg_cuda.plugin),)
	@echo "Packaging nwreg_cuda..."
	@cp nwreg/nwreg_cuda.plugin ado/plus/ 2>/dev/null || true
	@echo "  Packaged nwreg_cuda"
endif
	@echo "Packaging single_ado files..."
	@for f in $(SINGLE_ADO_FILES); do \
		base=$$(basename $$f .ado); \
		letter=$$(echo $$base | cut -c1); \
		mkdir -p ado/plus/$$letter; \
		cp $$f ado/plus/$$letter/ 2>/dev/null || true; \
		if [ -f $(SINGLE_ADO_DIR)/$$base.sthlp ]; then \
			cp $(SINGLE_ADO_DIR)/$$base.sthlp ado/plus/$$letter/ 2>/dev/null || true; \
		fi; \
		echo "  Packaged $$base"; \
	done
	@echo "Package complete: ado/plus/ directory ready for distribution."

help:
	@echo "Stata Kernel Plugins Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build all plugins (default, CPU only)"
	@echo "  kdensity2    - Build kdensity2 plugin only"
	@echo "  kdensity2_cuda - Build kdensity2 with CUDA (hidden feature, requires nvcc)"
	@echo "  nwreg_cuda   - Build nwreg with CUDA (hidden feature, requires nvcc)"
	@echo "  clean        - Remove all built files"
	@echo "  install      - Install all plugins (and single_ado) to ~/ado/plus/"
	@echo "  dist         - Package plugins (and single_ado) to ado/ directory"
	@echo "  help         - Show this help"
	@echo ""
	@echo "Platform: $(UNAME_S)"
	@echo "CUDA arch: $(CUDA_ARCH) (if nvcc available)"
