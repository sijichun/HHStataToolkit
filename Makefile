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
COMMON_SRC = src/stplugin.c src/utils.c

# Plugin subdirectories
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

# Platform-specific flags
ifeq ($(UNAME_S),Linux)
    CFLAGS += -shared -fPIC -DSYSTEM=OPUNIX
    PLUGIN_EXT = .plugin
endif

ifeq ($(UNAME_S),Darwin)
    CC = clang
    CFLAGS += -bundle -DSYSTEM=APPLEMAC
    PLUGIN_EXT = .plugin
endif

ifeq ($(OS),Windows_NT)
    CC = x86_64-w64-mingw32-gcc
    CFLAGS += -shared -fPIC -DSYSTEM=STWIN32
    PLUGIN_EXT = .plugin
endif

# Build targets
.PHONY: all clean install dist help $(PLUGINS)

all: $(PLUGINS)

# Generic plugin build rule
$(PLUGINS):
	@echo "Building $@..."
	$(CC) $(CFLAGS) $(COMMON_SRC) $@/$@.c -o $@/$@$(PLUGIN_EXT) $(LDFLAGS)
	@echo "$@ build complete."

# Clean all plugins
clean:
	@for p in $(PLUGINS); do \
		echo "Cleaning $$p..."; \
		rm -f $$p/$$p.plugin; \
	done
	@rm -rf ado/*

# Install: .plugin → ~/ado/plus/, .ado/.sthlp → ~/ado/plus/<letter>/
install: all
	@echo "Installing to ~/ado/plus/..."
	@for p in $(PLUGINS); do \
		letter=$$(echo $$p | cut -c1); \
		cp $$p/$$p.plugin ~/ado/plus/ 2>/dev/null || true; \
		cp $$p/$$p.ado ~/ado/plus/$$letter/ 2>/dev/null || mkdir -p ~/ado/plus/$$letter && cp $$p/$$p.ado ~/ado/plus/$$letter/ 2>/dev/null || true; \
		cp $$p/$$p.sthlp ~/ado/plus/$$letter/ 2>/dev/null || mkdir -p ~/ado/plus/$$letter && cp $$p/$$p.sthlp ~/ado/plus/$$letter/ 2>/dev/null || true; \
		echo "  Installed $$p"; \
	done
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
	@echo "Packaging to ado/..."
	@mkdir -p ado/p
	@for p in $(PLUGINS); do \
		letter=$$(echo $$p | cut -c1); \
		cp $$p/$$p.plugin ado/p/ 2>/dev/null || true; \
		mkdir -p ado/$$letter; \
		cp $$p/$$p.ado ado/$$letter/ 2>/dev/null || true; \
		cp $$p/$$p.sthlp ado/$$letter/ 2>/dev/null || true; \
		echo "  Packaged $$p"; \
	done
	@echo "Packaging single_ado files..."
	@for f in $(SINGLE_ADO_FILES); do \
		base=$$(basename $$f .ado); \
		letter=$$(echo $$base | cut -c1); \
		mkdir -p ado/$$letter; \
		cp $$f ado/$$letter/ 2>/dev/null || true; \
		if [ -f $(SINGLE_ADO_DIR)/$$base.sthlp ]; then \
			cp $(SINGLE_ADO_DIR)/$$base.sthlp ado/$$letter/ 2>/dev/null || true; \
		fi; \
		echo "  Packaged $$base"; \
	done
	@echo "Package complete: ado/ directory ready for distribution."

help:
	@echo "Stata Kernel Plugins Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build all plugins (default)"
	@echo "  kdensity2    - Build kdensity2 plugin only"
	@echo "  clean        - Remove all built files"
	@echo "  install      - Install all plugins (and single_ado) to ~/ado/plus/"
	@echo "  dist         - Package plugins (and single_ado) to ado/ directory"
	@echo "  help         - Show this help"
	@echo ""
	@echo "Project layout:"
	@echo "  HHStataToolkit/"
	@echo "    ├── src/"
	@echo "    │     ├── stplugin.h, utils.h"
	@echo "    │     └── stplugin.c, utils.c"
	@echo "    ├── Makefile"
	@echo "    ├── kdensity2/"
	@echo "    │     ├── kdensity2.c / kdensity2.ado"
	@echo "    ├── nwreg/"
	@echo "    │     ├── nwreg.c / nwreg.ado"
	@echo "    └── single_ado/"
	@echo "          ├── bprecall.ado"
	@echo "          ├── countdistinct.ado"
	@echo "          ├── gen_init_var.ado"
	@echo "          ├── gencatutility.ado"
	@echo "          └── labelvalidsample.ado"
	@echo ""
	@echo "To add a new plugin:"
	@echo "  1. mkdir myplugin && create myplugin.c / myplugin.ado"
	@echo "  2. Add 'myplugin' to PLUGINS in this Makefile"
	@echo "  3. make myplugin"
	@echo ""
	@echo "Platform: $(UNAME_S)"
