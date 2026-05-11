# fangorn/ — Decision Tree & Random Forest Plugin

**Scope:** Multi-file C plugin implementing CART and Breiman Random Forest
with OpenMP parallel tree construction, OOB error, MDI importance, and
Mermaid export.

## Files

| File | Role |
|------|------|
| `fangorn.c` | Stata plugin entry (`stata_call`), option parsing, variable layout |
| `ent.h/c` | Tree structures (`TreeNode`, `DecisionTree`, `RandomForest`), build logic |
| `split.h/c` | Impurity functions (Gini, Entropy, MSE) and split finding |
| `utils_rf.h/c` | LCG RNG, bootstrap sampling, feature subsampling, argsort |
| `fangorn.ado` | ado wrapper: touse, group encoding, plugin call |
| `fangorn.sthlp` | Help file |
| `README.md` | Full algorithm docs, C API reference, benchmarks |

## Data Structures

- **TreeNode:** heap-style ID (`root=0, left=2p+1, right=2p+2`)
- **DecisionTree:** dynamic array of nodes, capacity doubles on realloc
- **Dataset:** column-major `X[n_features][n_obs]`, pre-sorted indices
- **RandomForest:** array of `ntree` trees + MDI importance + OOB error

## Critical Memory Warning

`add_node_to_tree()` may realloc `tree->nodes`. **Never hold a `TreeNode*`
across this call** — always re-fetch via `tree->nodes[idx]`.

## RNG & Reproducibility

- Single tree: deterministic, no seed needed.
- Random forest: per-tree LCG seeded `seed + 9999 + tree_idx`.
- Bootstrap: seeded `seed + tree_idx`.
- CV fold shuffle: seeded by `seed()` option directly.
- OpenMP: per-thread LCG states guarantee thread-count-independent results.

## Build Note

fangorn uses a custom Makefile target (not the generic `PLUGINS` rule):
```makefile
fangorn: check-openblas $(PLUGINS)
	$(CC) $(CFLAGS) $(COMMON_SRC) fangorn/fangorn.c fangorn/ent.c \
	  fangorn/split.c fangorn/utils_rf.c -o fangorn/fangorn.plugin ...
```

## Variable Layout

| Position | Content |
|----------|---------|
| 1..p | Features (indepvars) |
| p+1 | depvar |
| p+2 | target (opt) |
| p+3..p+2+g | group vars (opt) |
| p+3+g | result (prediction) |
| p+4+g | leaf_id |
| p+5+g | touse |

## Where to Look

| Task | File |
|------|------|
| Add splitting criterion | `split.c` |
| Change tree structure | `ent.h/c` |
| Modify RNG | `utils_rf.c` |
| Add export format | `fangorn.c` (after build), or `ent.c` |
| Stata interface changes | `fangorn.ado` + `fangorn.c` |

## Anti-Patterns

- **Keeping `TreeNode*` across `add_node_to_tree()`** — will dangle on realloc.
- **Passing `rng=NULL` to `find_best_split()`** — silently ignores `mtry` (fixed 2026-05-10).
- **Forgetting `seed()` in RF tests** — results won't be reproducible.
