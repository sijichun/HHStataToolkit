*! test_fangorn_basic.do - Quick integration smoke test
* Tests: single tree, random forest, target split, if(), ntiles
* Run: stata -b do test/fangorn/test_fangorn_basic.do

clear all
set seed 42
set obs 500

* ============================================================
* Setup: generate test data
* ============================================================
gen double x1 = runiform() * 10
gen double x2 = runiform() * 10
gen double x3 = rnormal()
gen int    y_class = 0
replace y_class = 1 if x1 > 3 & x1 < 7
replace y_class = 2 if x1 >= 7
gen double y_reg = x1 + 2*x2 + rnormal(0, 2)

di _n "{hline 60}"
di "=== Test 1: Single classification tree (default) ==="
di "{hline 60}"
fangorn y_class x1 x2, type(classify) generate(t1) maxdepth(5) entcvdepth(0)
gen byte t1_correct = (y_class == t1_pred)
quietly summarize t1_correct
di "  Accuracy: " %9.4f r(mean)
assert r(N) == 500
assert r(mean) > 0.65
drop t1_pred t1 t1_correct

di _n "{hline 60}"
di "=== Test 2: Single regression tree ==="
di "{hline 60}"
fangorn y_reg x1 x2, type(regress) generate(t2) maxdepth(5) entcvdepth(0)
correlate y_reg t2_pred
di "  Correlation (y, pred): " %9.4f r(rho)
assert r(rho) > 0.80
drop t2_pred t2

di _n "{hline 60}"
di "=== Test 3: Random forest classification (ntree=50) ==="
di "{hline 60}"
fangorn y_class x1 x2, type(classify) generate(t3) ntree(50) maxdepth(5) entcvdepth(0) seed(42)
gen byte t3_correct = (y_class == t3_pred)
quietly summarize t3_correct
di "  Accuracy: " %9.4f r(mean)
di "  OOB error: " %9.4f r(oob_error)
assert r(mean) > 0.65
drop t3_pred t3 t3_correct

di _n "{hline 60}"
di "=== Test 4: Random forest regression (ntree=50) ==="
di "{hline 60}"
fangorn y_reg x1 x2, type(regress) generate(t4) ntree(50) maxdepth(5) entcvdepth(0) seed(42)
correlate y_reg t4_pred
di "  Correlation (y, pred): " %9.4f r(rho)
di "  OOB error (MSE): " %9.4f r(oob_error)
assert r(rho) > 0.85
drop t4_pred t4

di _n "{hline 60}"
di "=== Test 5: Target split (train/test) ==="
di "{hline 60}"
gen byte target_split = (_n <= 350)
fangorn y_class x1 x2, type(classify) generate(t5) target(target_split) maxdepth(5) entcvdepth(0)
* All obs should have predictions
quietly count if t5_pred != .
assert r(N) == 500
* Train accuracy
gen byte t5_correct = (y_class == t5_pred)
quietly summarize t5_correct if target_split == 0
di "  Train accuracy: " %9.4f r(mean)
quietly summarize t5_correct if target_split == 1
di "  Test accuracy:  " %9.4f r(mean)
assert r(mean) > 0.40
drop t5_pred t5 t5_correct target_split

di _n "{hline 60}"
di "=== Test 6: if() condition filtering ==="
di "{hline 60}"
fangorn y_class x1, type(classify) generate(t6) if(x1 < 9) maxdepth(5) entcvdepth(0)
quietly count if t6_pred != . & x1 < 9
di "  Predictions for x1<9: " r(N)
assert r(N) > 0
quietly count if t6_pred != . & x1 >= 9
di "  Predictions for x1>=9 (should be 0): " r(N)
assert r(N) == 0
drop t6_pred t6

di _n "{hline 60}"
di "=== Test 7: ntiles quantile split (ntiles=10) ==="
di "{hline 60}"
* Compare ntiles results vs exact (ntiles=0)
fangorn y_class x1 x2, type(classify) generate(t7_exact) maxdepth(5) entcvdepth(0) ntiles(0)
fangorn y_class x1 x2, type(classify) generate(t7_quant) maxdepth(5) entcvdepth(0) ntiles(10)
gen byte t7_correct = (y_class == t7_exact_pred)
quietly summarize t7_correct
di "  Exact accuracy:  " %9.4f r(mean)
drop t7_correct
gen byte t7_correct = (y_class == t7_quant_pred)
quietly summarize t7_correct
di "  Quantile accuracy: " %9.4f r(mean)
* Accuracy should be reasonable (exact CART might differ from quantile but both should work)
assert r(mean) > 0.50
drop t7_exact_pred t7_exact t7_quant_pred t7_quant t7_correct

di _n "{hline 60}"
di "=== Test 8: ntiles with RF (ntiles=20, ntree=20) ==="
di "{hline 60}"
fangorn y_class x1 x2, type(classify) generate(t8) ntree(20) maxdepth(5) entcvdepth(0) ntiles(20) seed(42)
gen byte t8_correct = (y_class == t8_pred)
quietly summarize t8_correct
di "  RF+quantile accuracy: " %9.4f r(mean)
di "  OOB error: " %9.4f r(oob_error)
assert r(mean) > 0.50
drop t8_pred t8 t8_correct

di _n "{hline 60}"
di "=== Test 9: ntiles regression ==="
di "{hline 60}"
fangorn y_reg x1 x2, type(regress) generate(t9) maxdepth(5) entcvdepth(0) ntiles(15)
correlate y_reg t9_pred
di "  Regression+quantile correlation: " %9.4f r(rho)
assert r(rho) > 0.70
drop t9_pred t9

di _n "{hline 60}"
di "=== Test 10: Reproducibility (same seed → same results) ==="
di "{hline 60}"
fangorn y_class x1 x2, type(classify) generate(t10a) ntree(20) maxdepth(5) entcvdepth(0) seed(999)
fangorn y_class x1 x2, type(classify) generate(t10b) ntree(20) maxdepth(5) entcvdepth(0) seed(999)
gen byte t10_match = (t10a_pred == t10b_pred)
quietly summarize t10_match
di "  Match rate: " %9.4f r(mean)
assert r(mean) == 1.0
drop t10a_pred t10a t10b_pred t10b t10_match

di _n "{hline 60}"
di "=== All basic tests passed! ==="
di "{hline 60}"
exit 0
