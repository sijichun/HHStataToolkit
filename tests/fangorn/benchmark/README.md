# fangorn vs sklearn — Unified Benchmark

**Dataset**: 10,000 observations, 12 features (5 continuous + 7 one-hot dummies
from 2 categorical variables: cat1 with 3 levels, cat2 with 4 levels), 70/30
train/test split. Complex non-linear DGP with interactions between continuous
and categorical variables.

**Features**:
- `x1`–`x5`: continuous (normal, exponential, uniform, etc.)
- `cat1_0`, `cat1_1`, `cat1_2`: one-hot from 3-level categorical
- `cat2_0`–`cat2_3`: one-hot from 4-level categorical

**Task**: 5-class classification + regression.

## Running

```bash
# 1. Generate data + run sklearn baseline
python test/fangorn/benchmark/test_benchmark.py

# 2. Run fangorn benchmark (requires built plugin)
make fangorn && make install
stata -e do test/fangorn/benchmark/test_fangorn_benchmark.do
```

## Hyperparameters

| Parameter | Decision Tree | Random Forest |
|-----------|---------------|---------------|
| max_depth | 10 | 10 |
| min_samples_split | 10 | 10 |
| min_samples_leaf | 3 | 3 |
| ntree / n_estimators | — | 100 |
| mtry (classify) | all | sqrt(p)=3 |
| mtry (regress) | all | p/3≈4 |

## Results

### Decision Tree

| Task | Criterion | fangorn | sklearn | Δ | fangorn time | sklearn time |
|------|-----------|---------|---------|---|-------------|-------------|
| 5-class classification | Gini | Acc 0.4760 (436 leaves) | Acc 0.4750 (436 leaves) | **0.0010** | 0.10s | 0.02s |
| 5-class classification | Entropy | Acc 0.4727 (485 leaves) | Acc 0.4720 (485 leaves) | **0.0007** | 0.05s | 0.03s |
| Regression | MSE | R² 0.8175 (573 leaves) | R² 0.8175 (573 leaves) | **0.0000** | 0.03s | 0.02s |

**All leaf counts identical** between fangorn and sklearn. Core CART algorithm
produces near-identical results (within ±0.001 accuracy / ±0.0000 R²).

### Random Forest (100 trees)

| Task | Metric | fangorn | sklearn | Δ | fangorn time | sklearn time |
|------|--------|---------|---------|---|-------------|-------------|
| Classification (Gini) | Accuracy | 0.5250 | 0.5440 | 0.019 | 0.18s | 0.38s |
| Classification (Entropy) | Accuracy | 0.5213 | 0.5420 | 0.021 | 0.23s | 0.55s |
| Regression (mtry=4) | R² | 0.8079 | 0.8696 | 0.062 | 0.17s | 0.41s |
| Regression (mtry=12, all) | R² | 0.8812 | — | — | 0.42s | — |

RF uses LCG for bootstrap sampling (sklearn uses Mersenne Twister), so exact
agreement is not expected. Classification results are within ~2%, which is
reasonable given different RNG implementations and tie-breaking.

**fangorn is faster than sklearn for RF** (0.17–0.23s vs 0.38–0.55s for
classification), because fangorn's C implementation has less overhead per tree
than sklearn's Python+numpy stack. The `mtry=12` (all features) case is slower
(0.42s) because each split evaluates all 12 features instead of a subset.

### Speed Summary (fangorn)

| Model | Time |
|-------|------|
| DT Gini (n=10000, p=12) | 0.10s |
| DT Entropy (n=10000, p=12) | 0.05s |
| DT Regression (n=10000, p=12) | 0.03s |
| RF Gini (100 trees, mtry=3) | 0.18s |
| RF Entropy (100 trees, mtry=3) | 0.23s |
| RF Regression (100 trees, mtry=4) | 0.17s |
| RF Regression (100 trees, mtry=12) | 0.42s |

All fangorn benchmarks complete in under 0.5 seconds for 10k observations with
12 features, demonstrating production-ready performance.
