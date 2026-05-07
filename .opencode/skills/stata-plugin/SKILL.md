---
name: stata-plugin
description: >
  Creating high-performance plugins for Stata using C with BLAS integration 
  and cross-platform compilation. Covers Stata-C data transfer, BLAS matrix 
  operations, makefile templates for Linux/macOS/Windows, and reusable utility 
  libraries.
version: 1.0.0
author: Sisyphus
tags:
  - stata
  - plugin
  - c
  - blas
  - openblas
  - gsl
  - matrix
  - cross-platform
  - makefile
triggers:
  - stata plugin
  - C plugin for Stata
  - BLAS Stata
  - Stata C extension
  - write stata plugin
  - stata plugin development
  - stata BLAS integration
---

# Stata Plugin Development Skill

Creating high-performance plugins for Stata using C with BLAS integration and cross-platform compilation.

## Quick Reference

**Required Files:**
- `stplugin.h` - Stata plugin interface header (version 3.0)
- `stplugin.c` - Stata plugin initialization code

**Basic Plugin Structure:**
```c
#include "stplugin.h"

STDLL stata_call(int argc, char *argv[])
{
    // Your code here
    return(0);  // Return 0 for success
}
```

**Stata Types (use these instead of C primitives):**
```c
ST_sbyte    // signed char
ST_ubyte    // unsigned char  
ST_int      // int
ST_long     // long
ST_float    // float
ST_double   // double
ST_boolean  // unsigned char (1=true, 0=false)
ST_retcode  // int (return code)
```

---

## 1. Required Files Setup

### Download Official Files

Download these files from [Stata Plugin Interface](https://www.stata.com/plugins/):

1. **stplugin.h** - Main header file with all type definitions and function declarations
2. **stplugin.c** - Plugin initialization (do NOT modify)

### Project Structure

```
my_stata_plugin/
├── stplugin.h          # Official header (downloaded)
├── stplugin.c          # Official init code (downloaded)
├── myplugin.c          # Your plugin code
├── utils.c             # Common utility functions (optional)
├── utils.h             # Utility header (optional)
└── Makefile            # Build configuration
```

### Include in Your Code

```c
#include "stplugin.h"
```

**Important:** Never modify `stplugin.h` or `stplugin.c`. Put all your code in separate files.

---

## 2. Compiling by Platform

### 2.1 Unix/Linux (gcc)

**Command:**
```bash
gcc -shared -fPIC -DSYSTEM=OPUNIX stplugin.c myplugin.c -o myplugin.plugin
```

**With BLAS:**
```bash
gcc -shared -fPIC -DSYSTEM=OPUNIX -I/usr/include/openblas \
    stplugin.c myplugin.c -o myplugin.plugin -lopenblas -lm
```

**With optimization:**
```bash
gcc -shared -fPIC -O3 -march=native -DSYSTEM=OPUNIX \
    stplugin.c myplugin.c -o myplugin.plugin -lopenblas -lm
```

**For 64-bit Stata:** Ensure you use 64-bit compilation flags (default on modern systems).

### 2.2 macOS (clang/Xcode)

**Universal Binary (Intel + Apple Silicon):**
```bash
# Build for Intel
clang -bundle -DSYSTEM=APPLEMAC stplugin.c myplugin.c \
    -o myplugin.plugin.x86_64 -target x86_64-apple-macos10.12

# Build for Apple Silicon
clang -bundle -DSYSTEM=APPLEMAC stplugin.c myplugin.c \
    -o myplugin.plugin.arm64 -target arm64-apple-macos11

# Combine into universal binary
lipo -create -output myplugin.plugin \
    myplugin.plugin.x86_64 myplugin.plugin.arm64
```

**With BLAS (Accelerate Framework):**
```bash
clang -bundle -DSYSTEM=APPLEMAC -framework Accelerate \
    stplugin.c myplugin.c -o myplugin.plugin
```

**With OpenBLAS:**
```bash
clang -bundle -DSYSTEM=APPLEMAC -I/opt/homebrew/opt/openblas/include \
    stplugin.c myplugin.c -o myplugin.plugin \
    -L/opt/homebrew/opt/openblas/lib -lopenblas
```

### 2.3 Windows (MinGW / Cygwin)

**Using MinGW-w64 (Recommended):**
```bash
# With MinGW 64-bit (from MSYS2, Cygwin, or standalone)
x86_64-w64-mingw32-gcc -shared -fPIC -DSYSTEM=STWIN32 stplugin.c myplugin.c -o myplugin.plugin
```

**Using Cygwin with MinGW cross-compiler:**
```bash
# Install mingw64-x86_64-gcc-core via Cygwin package manager first
cygwin$ x86_64-w64-mingw32-gcc -shared -fPIC -DSYSTEM=STWIN32 stplugin.c myplugin.c -o myplugin.plugin
```

**Important Cygwin Note:**
Do NOT use plain `gcc` under Cygwin without `-mno-cygwin` (deprecated) or the MinGW cross-compiler. Linking against the Cygwin DLL will cause Stata to fail when reloading the plugin.

**With BLAS on Windows:**
```bash
# With OpenBLAS (download prebuilt binaries from https://github.com/xianyi/OpenBLAS/releases)
x86_64-w64-mingw32-gcc -shared -fPIC -DSYSTEM=STWIN32 -I/path/to/openblas/include \
    stplugin.c myplugin.c -o myplugin.plugin \
    -L/path/to/openblas/lib -lopenblas
```

**With GSL on Windows:**
```bash
# With GSL (download from http://gnuwin32.sourceforge.net/packages/gsl.htm or build via MSYS2)
x86_64-w64-mingw32-gcc -shared -fPIC -DSYSTEM=STWIN32 -I/path/to/gsl/include \
    stplugin.c myplugin.c -o myplugin.plugin \
    -L/path/to/gsl/lib -lgsl -lgslcblas -lm
```

### 2.4 Platform Detection

The `stplugin.h` header automatically handles platform differences:

```c
#if SYSTEM==STWIN32    // Windows
#if SYSTEM==OPUNIX     // Unix/Linux  
#if SYSTEM==APPLEMAC   // macOS
```

You only need to define `SYSTEM` during compilation (see commands above).

---

## 3. Makefile Templates

### 3.1 Basic Cross-Platform Makefile

```makefile
# Stata Plugin Makefile
# Supports: Linux, macOS, Windows (cross-compile)

PLUGIN_NAME = myplugin
SOURCES = stplugin.c myplugin.c

# Detect platform
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Linux)
    CC = gcc
    CFLAGS = -shared -fPIC -DSYSTEM=OPUNIX -O2
    LDFLAGS = -lm
    TARGET = $(PLUGIN_NAME).plugin
endif

ifeq ($(UNAME_S),Darwin)
    CC = clang
    CFLAGS = -bundle -DSYSTEM=APPLEMAC -O2
    LDFLAGS = -lm
    TARGET = $(PLUGIN_NAME).plugin
endif

# For Windows cross-compile (from Linux/macOS)
ifeq ($(OS),Windows_NT)
    CC = x86_64-w64-mingw32-gcc
    CFLAGS = -shared -fPIC -DSYSTEM=STWIN32 -O2
    LDFLAGS = -lm
    TARGET = $(PLUGIN_NAME).plugin
endif

# BLAS support (optional)
USE_BLAS = 1
ifeq ($(USE_BLAS),1)
    ifeq ($(UNAME_S),Linux)
        CFLAGS += -DUSE_BLAS
        LDFLAGS += -lopenblas
    endif
    ifeq ($(UNAME_S),Darwin)
        CFLAGS += -DUSE_BLAS -framework Accelerate
    endif
endif

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $(SOURCES) -o $@ $(LDFLAGS)

clean:
	rm -f $(TARGET)
```

### 3.2 Advanced Makefile with BLAS Detection

```makefile
# Advanced Stata Plugin Makefile with auto BLAS detection

PLUGIN_NAME = myplugin
SOURCES = stplugin.c myplugin.c

# Compiler settings by platform
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Default settings
CC = gcc
CFLAGS = -O3 -Wall
LDFLAGS = -lm

# Platform-specific compilation flags
ifeq ($(UNAME_S),Linux)
    CFLAGS += -shared -fPIC -DSYSTEM=OPUNIX
    
    # Auto-detect BLAS
    ifneq ($(shell pkg-config --exists openblas && echo yes),)
        BLAS_CFLAGS = $(shell pkg-config --cflags openblas)
        BLAS_LIBS = $(shell pkg-config --libs openblas)
        CFLAGS += -DUSE_OPENBLAS $(BLAS_CFLAGS)
        LDFLAGS += $(BLAS_LIBS)
    else ifneq ($(shell pkg-config --exists blas && echo yes),)
        BLAS_LIBS = $(shell pkg-config --libs blas)
        CFLAGS += -DUSE_BLAS $(shell pkg-config --cflags blas)
        LDFLAGS += $(BLAS_LIBS)
    else
        LDFLAGS += -lblas
    endif
    
    TARGET = $(PLUGIN_NAME).plugin
endif

ifeq ($(UNAME_S),Darwin)
    CC = clang
    CFLAGS += -bundle -DSYSTEM=APPLEMAC
    
    # Prefer Accelerate Framework on macOS
    CFLAGS += -DUSE_BLAS -framework Accelerate
    
    TARGET = $(PLUGIN_NAME).plugin
endif

# Windows (MinGW from MSYS2, Cygwin, or cross-compile)
ifeq ($(OS),Windows_NT)
    CC = x86_64-w64-mingw32-gcc
    CFLAGS += -shared -fPIC -DSYSTEM=STWIN32
    
    # For GSL on Windows, adjust paths as needed
    # CFLAGS += -I/mingw64/include
    # LDFLAGS += -L/mingw64/lib -lgsl -lgslcblas
    
    TARGET = $(PLUGIN_NAME).plugin
endif

# Build targets
.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

# Install to Stata's ado path (optional)
install: $(TARGET)
	cp $(TARGET) ~/ado/plus/

clean:
	rm -f $(TARGET) *.o
```

### 3.3 Makefile for Multiple Plugins

```makefile
# Build multiple Stata plugins

PLUGINS = plugin1 plugin2 plugin3
SOURCES_common = stplugin.c utils.c

CC = gcc
CFLAGS = -shared -fPIC -DSYSTEM=OPUNIX -O3 -Wall
LDFLAGS = -lopenblas -lm

.PHONY: all clean

all: $(addsuffix .plugin,$(PLUGINS))

%.plugin: %.c $(SOURCES_common)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

clean:
	rm -f *.plugin
```

---

## 4. Stata ↔ C Data Transfer (Core API)

### 4.1 Variable Data Access

**Numeric Variables:**
```c
ST_retcode SF_vdata(ST_int i, ST_int j, ST_double *z);   // Read
ST_retcode SF_vstore(ST_int i, ST_int j, ST_double val); // Write
```

- `i`: Variable index (1-based, from varlist)
- `j`: Observation index (1-based)
- `z`: Pointer to store/read value
- All numeric data transfers as `ST_double` (double precision)

**String Variables (str#):**
```c
ST_retcode SF_sdata(ST_int i, ST_int j, char *s);  // Read
ST_retcode SF_sstore(ST_int i, ST_int j, char *s); // Write
```

**Long String Variables (strL):**
```c
ST_int     SF_sdatalen(ST_int i, ST_int j);                    // Get length
ST_retcode SF_strldata(ST_int i, ST_int j, char *s, ST_int len); // Read
```

**Variable Type Checks:**
```c
ST_boolean SF_var_is_string(ST_int i);   // 1 if string, 0 if numeric
ST_boolean SF_var_is_strl(ST_int i);     // 1 if strL, 0 if str#
ST_boolean SF_var_is_binary(ST_int i, ST_int j); // 1 if binary strL
```

### 4.2 Data Dimensions

```c
ST_int SF_nobs(void);    // Number of observations
ST_int SF_nvar(void);    // Number of variables (in varlist)
ST_int SF_nvars(void);   // Total variables in dataset
ST_int SF_in1(void);     // First observation (if in range specified)
ST_int SF_in2(void);     // Last observation (if in range specified)
```

### 4.3 Complete Data Transfer Examples

**Example 1: Read all numeric data into C array**
```c
#include "stplugin.h"
#include <stdlib.h>

// Transfer Stata numeric data to C double array
// Returns: pointer to data (caller must free), or NULL on error
ST_double* stata_to_c_numeric(ST_int var_idx, ST_int *n_obs)
{
    ST_int n = SF_nobs();
    ST_double *data = (ST_double*)malloc(n * sizeof(ST_double));
    if (!data) return NULL;
    
    for (ST_int j = 1; j <= n; j++) {
        if (SF_vdata(var_idx, j, &data[j-1]) != 0) {
            free(data);
            return NULL;
        }
    }
    
    *n_obs = n;
    return data;
}
```

**Example 2: Write C array to Stata variable**
```c
// Write C double array to Stata variable
// data: C array (0-indexed)
// n: number of elements
// var_idx: Stata variable index (1-based)
ST_retcode c_to_stata_numeric(const ST_double *data, ST_int n, ST_int var_idx)
{
    for (ST_int j = 1; j <= n; j++) {
        ST_retcode rc = SF_vstore(var_idx, j, data[j-1]);
        if (rc != 0) return rc;
    }
    return 0;
}
```

**Example 3: Transfer multiple variables to column-major matrix**
```c
#include "stplugin.h"
#include <stdlib.h>

/*
 * Transfer Stata variables to C matrix (column-major, suitable for BLAS)
 * 
 * Stata layout: var1_obs1, var1_obs2, ... (column-major naturally)
 * C layout for BLAS: same column-major ordering
 * 
 * Returns: pointer to matrix data, or NULL on error
 *          Matrix is nobs x nvars, stored column-major
 */
ST_double* stata_to_c_matrix(ST_int n_vars, ST_int *n_rows, ST_int *n_cols)
{
    ST_int n = SF_nobs();
    ST_int total_vars = SF_nvar();  // Variables in varlist
    
    if (n_vars > total_vars) n_vars = total_vars;
    
    ST_double *matrix = (ST_double*)malloc(n * n_vars * sizeof(ST_double));
    if (!matrix) return NULL;
    
    for (ST_int i = 1; i <= n_vars; i++) {
        // Check if numeric
        if (SF_var_is_string(i)) {
            free(matrix);
            return NULL;  // Cannot handle strings in numeric matrix
        }
        
        for (ST_int j = 1; j <= n; j++) {
            ST_double val;
            if (SF_vdata(i, j, &val) != 0) {
                free(matrix);
                return NULL;
            }
            // Column-major: matrix[j-1 + (i-1)*n]
            matrix[(i-1)*n + (j-1)] = val;
        }
    }
    
    *n_rows = n;
    *n_cols = n_vars;
    return matrix;
}
```

---

## 5. BLAS Integration

### 5.1 Why BLAS?

When transferring large datasets from Stata to C:
- Stata stores data in column-major order (same as Fortran/BLAS)
- Direct memory mapping is possible for efficient transfer
- BLAS routines (matrix multiplication, decomposition) run at near-optimal speed

### 5.2 BLAS-Compatible Data Transfer

**For matrix operations with OpenBLAS:**
```c
#include "stplugin.h"
#include <stdlib.h>

#ifdef USE_BLAS
#include <cblas.h>  // or appropriate BLAS header
#endif

/*
 * Transfer Stata variables to BLAS-compatible column-major matrix
 * Suitable for dgemm, dgesv, etc.
 * 
 * Layout: matrix[i + j*lda] = element (i,j)
 * where lda = leading dimension = n_rows
 */
ST_double* stata_to_blas_matrix(ST_int *m, ST_int *n, ST_int *lda)
{
    ST_int nobs = SF_nobs();
    ST_int nvars = SF_nvar();
    
    ST_double *A = (ST_double*)malloc(nobs * nvars * sizeof(ST_double));
    if (!A) return NULL;
    
    for (ST_int var = 1; var <= nvars; var++) {
        for (ST_int obs = 1; obs <= nobs; obs++) {
            ST_double val;
            SF_vdata(var, obs, &val);
            // Column-major: A[(obs-1) + (var-1)*nobs]
            A[(obs-1) + (var-1)*nobs] = val;
        }
    }
    
    *m = nobs;      // rows
    *n = nvars;     // columns
    *lda = nobs;    // leading dimension
    return A;
}

/*
 * Write BLAS result back to Stata
 * Assumes column-major input matching Stata variable count
 */
ST_retcode blas_to_stata(const ST_double *A, ST_int m, ST_int n)
{
    ST_int nvars = SF_nvar();
    if (n > nvars) n = nvars;
    if (m > SF_nobs()) m = SF_nobs();
    
    for (ST_int var = 1; var <= n; var++) {
        for (ST_int obs = 1; obs <= m; obs++) {
            ST_double val = A[(obs-1) + (var-1)*m];
            ST_retcode rc = SF_vstore(var, obs, val);
            if (rc != 0) return rc;
        }
    }
    return 0;
}
```

### 5.3 Example: Matrix Multiplication with BLAS

```c
#include "stplugin.h"
#include <stdlib.h>
#include <string.h>

#ifdef USE_BLAS
#include <cblas.h>
#endif

STDLL stata_call(int argc, char *argv[])
{
    ST_int m, n, k, lda, ldb, ldc;
    ST_double *A, *B, *C;
    
    // Read two sets of variables (simplified example)
    // In practice, parse argv to determine which variables
    
    A = stata_to_blas_matrix(&m, &k, &lda);
    if (!A) {
        SF_error("Failed to read matrix A\n");
        return 1;
    }
    
    B = stata_to_blas_matrix(&k, &n, &ldb);  // Adjust as needed
    if (!B) {
        free(A);
        SF_error("Failed to read matrix B\n");
        return 1;
    }
    
    C = (ST_double*)calloc(m * n, sizeof(ST_double));
    if (!C) {
        free(A); free(B);
        return 1;
    }
    ldc = m;
    
#ifdef USE_BLAS
    // C = A * B using BLAS
    cblas_dgemm(CblasColMajor, CblasNoTrans, CblasNoTrans,
                m, n, k, 1.0, A, lda, B, ldb, 0.0, C, ldc);
#else
    // Fallback manual multiplication
    for (ST_int i = 0; i < m; i++)
        for (ST_int j = 0; j < n; j++)
            for (ST_int l = 0; l < k; l++)
                C[i + j*ldc] += A[i + l*lda] * B[l + j*ldb];
#endif
    
    // Write result back to Stata
    ST_retcode rc = blas_to_stata(C, m, n);
    
    free(A); free(B); free(C);
    return rc;
}
```

### 5.4 Platform-Specific BLAS Notes

**Linux:**
```bash
# OpenBLAS (recommended)
sudo apt-get install libopenblas-dev
# Compile with: -lopenblas

# GSL (GNU Scientific Library)
sudo apt-get install libgsl-dev
# Compile with: -lgsl -lgslcblas
```

**macOS:**
```bash
# Use Accelerate Framework (pre-installed, optimized)
# Compile with: -framework Accelerate

# Or Homebrew OpenBLAS
brew install openblas
# Compile with: -I/opt/homebrew/opt/openblas/include -L/opt/homebrew/opt/openblas/lib -lopenblas
```

**Windows:**
```bash
# Download OpenBLAS binaries
# Link with: -lopenblas
```

---

## 6. Complete Utility Library

### 6.1 Utility Header (stata_utils.h)

```c
#ifndef STATA_UTILS_H
#define STATA_UTILS_H

#include "stplugin.h"
#include <stdlib.h>

/* Data Transfer */
ST_double* stata_to_c_vector(ST_int var_idx, ST_int *n);
ST_double* stata_to_c_matrix_all(ST_int *rows, ST_int *cols);
ST_double* stata_to_c_matrix_cols(ST_int start_var, ST_int end_var, ST_int *rows, ST_int *cols);
ST_retcode c_vector_to_stata(const ST_double *data, ST_int n, ST_int var_idx);
ST_retcode c_matrix_to_stata(const ST_double *data, ST_int rows, ST_int cols);

/* String Handling */
char** stata_to_c_strings(ST_int var_idx, ST_int *n);
void free_string_array(char **arr, ST_int n);

/* Variable Information */
ST_int count_numeric_vars(void);
ST_int count_string_vars(void);
void get_var_indices_numeric(ST_int *indices, ST_int *count);

/* Missing Values */
ST_boolean is_stata_missing(ST_double val);
ST_double get_missing_val(void);

/* Matrix Operations (Stata matrices) */
ST_double* stata_matrix_get(const char *name, ST_int *rows, ST_int *cols);
ST_retcode stata_matrix_put(const char *name, const ST_double *data, 
                             ST_int rows, ST_int cols);

#endif
```

### 6.2 Utility Implementation (stata_utils.c)

```c
#include "stata_utils.h"
#include <string.h>

/* Get all numeric data as column-major matrix */
ST_double* stata_to_c_matrix_all(ST_int *rows, ST_int *cols)
{
    ST_int n = SF_nobs();
    ST_int nvars = SF_nvar();
    ST_int numeric_count = 0;
    
    // Count numeric variables
    for (ST_int i = 1; i <= nvars; i++) {
        if (!SF_var_is_string(i)) numeric_count++;
    }
    
    if (numeric_count == 0) return NULL;
    
    ST_double *matrix = (ST_double*)malloc(n * numeric_count * sizeof(ST_double));
    if (!matrix) return NULL;
    
    ST_int col = 0;
    for (ST_int i = 1; i <= nvars && col < numeric_count; i++) {
        if (SF_var_is_string(i)) continue;
        
        for (ST_int j = 1; j <= n; j++) {
            SF_vdata(i, j, &matrix[(j-1) + col*n]);
        }
        col++;
    }
    
    *rows = n;
    *cols = numeric_count;
    return matrix;
}

/* Write column-major matrix back to Stata variables */
ST_retcode c_matrix_to_stata(const ST_double *data, ST_int rows, ST_int cols)
{
    ST_int nvars = SF_nvar();
    ST_int n = SF_nobs();
    
    if (rows > n) rows = n;
    if (cols > nvars) cols = nvars;
    
    for (ST_int col = 0; col < cols; col++) {
        if (SF_var_is_string(col + 1)) continue;
        
        for (ST_int row = 0; row < rows; row++) {
            ST_retcode rc = SF_vstore(col + 1, row + 1, data[row + col*rows]);
            if (rc != 0) return rc;
        }
    }
    return 0;
}

/* Get single variable as C vector */
ST_double* stata_to_c_vector(ST_int var_idx, ST_int *n)
{
    ST_int nobs = SF_nobs();
    ST_double *vec = (ST_double*)malloc(nobs * sizeof(ST_double));
    if (!vec) return NULL;
    
    for (ST_int j = 1; j <= nobs; j++) {
        if (SF_vdata(var_idx, j, &vec[j-1]) != 0) {
            free(vec);
            return NULL;
        }
    }
    
    *n = nobs;
    return vec;
}

/* Write C vector to Stata variable */
ST_retcode c_vector_to_stata(const ST_double *data, ST_int n, ST_int var_idx)
{
    for (ST_int j = 1; j <= n; j++) {
        ST_retcode rc = SF_vstore(var_idx, j, data[j-1]);
        if (rc != 0) return rc;
    }
    return 0;
}

/* Get Stata matrix by name */
ST_double* stata_matrix_get(const char *name, ST_int *rows, ST_int *cols)
{
    ST_int r = SF_row(name);
    ST_int c = SF_col(name);
    if (r <= 0 || c <= 0) return NULL;
    
    ST_double *mat = (ST_double*)malloc(r * c * sizeof(ST_double));
    if (!mat) return NULL;
    
    for (ST_int i = 1; i <= r; i++) {
        for (ST_int j = 1; j <= c; j++) {
            ST_double val;
            if (SF_mat_el(name, i, j, &val) != 0) {
                free(mat);
                return NULL;
            }
            mat[(i-1) + (j-1)*r] = val;
        }
    }
    
    *rows = r;
    *cols = c;
    return mat;
}

/* Missing value helpers */
ST_boolean is_stata_missing(ST_double val) {
    return SF_is_missing(val);
}

ST_double get_missing_val(void) {
    return SV_missval;
}
```

---

## 7. Working with Stata Matrices

### 7.1 Matrix API

```c
// Get matrix dimensions
ST_int SF_row(const char *name);  // Number of rows
ST_int SF_col(const char *name);  // Number of columns

// Access elements
#if defined(SD_SAFEMODE)
ST_retcode SF_mat_el(const char *name, ST_int row, ST_int col, ST_double *val);
ST_retcode SF_mat_store(const char *name, ST_int row, ST_int col, ST_double val);
#else
// Fast mode - no bounds checking
#endif

// Matrix info
ST_int SV_matsize;  // Maximum matrix size
```

### 7.2 Matrix Example

```c
STDLL stata_call(int argc, char *argv[])
{
    if (argc < 1) {
        SF_error("Usage: plugin call myplugin matrixname\n");
        return 1;
    }
    
    char *matname = argv[0];
    ST_int rows = SF_row(matname);
    ST_int cols = SF_col(matname);
    
    SF_display("Matrix "); SF_display(matname);
    SF_display(": "); 
    // Print dimensions...
    
    // Read element (2,3)
    ST_double val;
    if (SF_mat_el(matname, 2, 3, &val) == 0) {
        // Use val...
    }
    
    // Store value
    SF_mat_store(matname, 1, 1, 3.14159);
    
    return 0;
}
```

---

## 8. Macros and Scalars

### 8.1 Macros

```c
// Save macro
SF_macro_save("macname", "macro contents");

// Use macro (read)
char buffer[256];
SF_macro_use("macname", buffer, 256);
```

### 8.2 Scalars

```c
// Save scalar
SF_scal_save("scalarname", 3.14159);

// Use scalar
ST_double val;
SF_scal_use("scalarname", &val);
```

---

## 9. Output and Error Handling

### 9.1 Display

```c
SF_display("Hello World\n");     // Regular output
SF_error("Error message\n");      // Error output (red in Stata)
```

### 9.2 Return Codes

```c
return 0;    // Success
return 1;    // General error
return 498;  // Out of range (obs/var index invalid)
// etc.
```

### 9.3 Checking for User Interrupt

```c
if (SF_poll()) {
    // User pressed Break
    return 1;
}
```

---

## 10. Complete Example Plugin

**File: regress_fast.c**
```c
#include "stplugin.h"
#include <stdlib.h>
#include <math.h>

#ifdef USE_BLAS
#include <cblas.h>
#include <gsl/gsl_linalg.h>
#endif

/*
 * Fast OLS regression using OpenBLAS and GSL
 * Usage: plugin call regress_fast y x1 x2 x3, b_matrix
 */
STDLL stata_call(int argc, char *argv[])
{
    ST_int n = SF_nobs();
    ST_int k = SF_nvar() - 1;  // Assuming first var is Y, rest are X
    
    if (k < 1) {
        SF_error("Need at least one independent variable\n");
        return 1;
    }
    
    // Allocate memory for X (n x k) and y (n)
    ST_double *X = (ST_double*)malloc(n * k * sizeof(ST_double));
    ST_double *y = (ST_double*)malloc(n * sizeof(ST_double));
    
    if (!X || !y) {
        free(X); free(y);
        SF_error("Memory allocation failed\n");
        return 1;
    }
    
    // Read Y (first variable)
    for (ST_int i = 1; i <= n; i++) {
        SF_vdata(1, i, &y[i-1]);
    }
    
    // Read X (remaining variables)
    for (ST_int j = 1; j <= k; j++) {
        for (ST_int i = 1; i <= n; i++) {
            SF_vdata(j+1, i, &X[(i-1) + (j-1)*n]);
        }
    }
    
    // Compute X'X and X'y
    ST_double *XtX = (ST_double*)malloc(k * k * sizeof(ST_double));
    ST_double *Xty = (ST_double*)malloc(k * sizeof(ST_double));
    
#ifdef USE_BLAS
    // X'X using dgemm
    cblas_dgemm(CblasColMajor, CblasTrans, CblasNoTrans,
                k, k, n, 1.0, X, n, X, n, 0.0, XtX, k);
    
    // X'y using dgemv
    cblas_dgemv(CblasColMajor, CblasTrans, n, k,
                1.0, X, n, y, 1, 0.0, Xty, 1);
    
    // Solve (X'X)b = X'y using GSL LU decomposition
    gsl_matrix_view m = gsl_matrix_view_array(XtX, k, k);
    gsl_vector_view b = gsl_vector_view_array(Xty, k);
    gsl_vector *x = gsl_vector_alloc(k);
    ST_int *perm = (ST_int*)malloc(k * sizeof(ST_int));
    int signum;
    gsl_linalg_LU_decomp(&m.matrix, perm, &signum);
    gsl_linalg_LU_solve(&m.matrix, perm, &b.vector, x);
    for (ST_int i = 0; i < k; i++) {
        Xty[i] = gsl_vector_get(x, i);
    }
    gsl_vector_free(x);
    free(perm);
#else
    // Manual computation (slower but no dependencies)
    // ... implementation ...
#endif
    
    // Store coefficients in Stata matrix if requested
    if (argc > 0) {
        // argv[0] contains matrix name
        for (ST_int i = 0; i < k; i++) {
            SF_mat_store(argv[0], i+1, 1, Xty[i]);
        }
    }
    
    // Display results
    SF_display("Regression coefficients:\n");
    for (ST_int i = 0; i < k; i++) {
        char buf[64];
        snprintf(buf, 64, "b%d = %f\n", i+1, Xty[i]);
        SF_display(buf);
    }
    
    free(X); free(y); free(XtX); free(Xty);
    return 0;
}
```

---

## 11. Loading and Using in Stata

### 11.1 Interactive Usage

```stata
* Compile first (outside Stata, using make or gcc)

* Load plugin
program myplugin, plugin

* Execute with all variables
plugin call myplugin y x1 x2 x3

* Execute with subset
plugin call myplugin y x1 x2 if age > 18

* Execute with options
plugin call myplugin y x1, matrix(b) verbose

* Unload when done
program drop myplugin
```

### 11.2 Ado-File Wrapper (Recommended)

```stata
* File: mycommand.ado
program define mycommand
    version 16
    syntax varlist [if] [in] [, Matrix(name) *]
    
    * Mark sample
    marksample touse
    
    * Load plugin
    cap program drop _myplugin
    program _myplugin, plugin using("myplugin.plugin")
    
    * Call plugin
    plugin call _myplugin `varlist' if `touse', `options'
    
    * Cleanup
    program drop _myplugin
end
```

### 11.3 Stata Variables → Plugin Flow

```
Stata                      C Plugin
─────────────────────────────────────────
varlist specified    →    argc/argv get options
if/in conditions     →    SF_nobs(), SF_in1(), SF_in2()
Variables 1..k       →    SF_vdata(i, j, &val) reads data
Results written      →    SF_vstore(i, j, val) writes back
Macros set           →    SF_macro_save()
Scalars returned     →    SF_scal_save()
Matrices passed      →    SF_mat_el(), SF_mat_store()
```

---

## 12. Best Practices

### 12.1 Performance

1. **Minimize data transfers**: Read data once, process in C, write back once
2. **Use BLAS for matrix ops**: Orders of magnitude faster than manual loops
3. **Batch operations**: Process multiple observations together when possible
4. **Avoid repeated SF_* calls in tight loops**: Cache data in C arrays

### 12.2 Memory Management

```c
// Always check allocations
ST_double *data = malloc(n * sizeof(ST_double));
if (!data) {
    SF_error("Out of memory\n");
    return 1;
}

// Always free in reverse allocation order
free(data);
```

### 12.3 Error Handling

```c
// Check variable exists
if (SF_nvar() < required_vars) {
    SF_error("Insufficient variables specified\n");
    return 1;
}

// Check numeric
if (SF_var_is_string(var_idx)) {
    SF_error("String variable not allowed\n");
    return 1;
}

// Check return codes
ST_retcode rc = SF_vdata(i, j, &val);
if (rc != 0) {
    SF_error("Error reading data\n");
    return rc;
}
```

### 12.4 Platform Compatibility

1. Use `ST_double` instead of `double`
2. Use `ST_int` instead of `int`
3. Don't assume structure packing
4. Test on all target platforms

---

## 13. Troubleshooting

| Problem | Solution |
|---------|----------|
| "plugin not found" | Check `.plugin` file is in ado-path or use `using()` |
| "incompatible version" | Recompile with latest `stplugin.h`/`stplugin.c` |
| Segmentation fault | Check array bounds, don't exceed SF_nobs()/SF_nvar() |
| Wrong results | Verify column-major ordering for matrices |
| Slow performance | Use BLAS, minimize SF_vdata() calls |
| Windows DLL error | Use MinGW-w64 cross-compiler instead of Cygwin gcc |
| macOS bundle error | Use `-bundle` not `-shared` with clang |

---

## 14. Resources

- **Official Documentation**: https://www.stata.com/plugins/
- **Stata Plugin Interface**: Version 3.0 (Stata 14.1+)
- **BLAS Reference**: https://netlib.org/blas/
- **OpenBLAS**: https://www.openblas.net/
- **GSL Reference**: https://www.gnu.org/software/gsl/
- **GSL Documentation**: https://www.gnu.org/software/gsl/doc/html/

**Note on versions:** Stata 14.0 and earlier use SPI 2.0. Stata 14.1+ uses SPI 3.0. Plugins compiled with older versions generally work with newer Stata versions, but not vice versa.
