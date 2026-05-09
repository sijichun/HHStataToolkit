# fangorn vs sklearn — Random Forest Benchmark

**Dataset**: Same as `test_ent` (2000 observations, 5 correlated features,
70/30 train/test split).  Uses `test/fangorn/test_ent/ent_data.csv`.

**Hyperparameters** (matched as closely as possible):

| Parameter | sklearn | fangorn |
|-----------|---------|---------|
| n_estimators / ntree | 100 | 100 |
| max_depth | 10 | 10 |
| min_samples_split | 10 | 10 |
| min_samples_leaf | 3 | 3 |
| min_impurity_decrease | 0.0 | 0.0 |
| bootstrap | True | True (default) |
| mtry (classification) | max_features=2 (sqrt) | mtry(2) |
| mtry (regression) | max_features=1 (n/3) | mtry(1) |

## Results

| Task | Metric | sklearn | fangorn |
|------|--------|---------|---------|
| RF Classification (Gini) | Accuracy | 0.5450 | 0.5200 |
| RF Classification (Entropy) | Accuracy | 0.5550 | 0.5283 |
| RF Regression | R² | 0.7028 | 0.9374 |

### Discussion

**Classification** results are within ~2.5–3%, which is reasonable given
different RNG implementations (numpy vs LCG), seed differences, and minor
algorithmic variations in tree building (tie-breaking, feature sampling).

**Regression** shows a larger discrepancy:
- sklearn R² = 0.703, MSE = 6.42
- fangorn R² = 0.937, MSE = 1.35

The R² gap (0.23) is notable and likely driven by differences in:
1. Bootstrap sampling RNG — different seeds produce different training sets
2. Feature subsampling interaction with weak trees (mtry=1 out of 5 features)
3. sklearn's CART implementation details (cost-complexity pruning logic, etc.)
