* Test fangorn Phase 2: Random Forest
* Prerequisites: plugin already built via `make fangorn` and `make install`
* Run with: cd test; stata -b do test_fangorn_phase2.do

clear
set obs 500
set seed 42

* Generate synthetic data for classification
gen x1 = rnormal()
gen x2 = rnormal()
gen x3 = rnormal()
gen x4 = rnormal()
gen y_class = (x1 + x2 + x3 + rnormal() > 0)
gen y_reg = x1 + 2*x2 - x3 + rnormal()

* Test 1: Single tree (baseline, should work as before)
display _n "=== Test 1: Single Tree ==="
fangorn y_class x1 x2 x3, type(classify) generate(tree1) maxdepth(5) entcvdepth(0)
summarize tree1_pred
tab y_class tree1_pred

* Test 2: Random forest classification
display _n "=== Test 2: RF Classification (ntree=50) ==="
fangorn y_class x1 x2 x3, type(classify) generate(rf_clf) ntree(50) maxdepth(5) entcvdepth(0) seed(42)
local oob_clf = r(oob_error)
summarize rf_clf_pred
tab y_class rf_clf_pred
display "OOB error: " `oob_clf'

* Test 3: Random forest regression
display _n "=== Test 3: RF Regression (ntree=50) ==="
fangorn y_reg x1 x2 x3, type(regress) generate(rf_reg) ntree(50) maxdepth(5) entcvdepth(0) seed(42)
local oob_reg = r(oob_error)
summarize rf_reg_pred
correlate y_reg rf_reg_pred
display "OOB error (MSE): " `oob_reg'

* Test 4: Custom mtry
display _n "=== Test 4: Custom mtry=2 ==="
fangorn y_class x1 x2 x3, type(classify) generate(rf_mtry) ntree(20) mtry(2) maxdepth(5) entcvdepth(0) seed(42)
summarize rf_mtry_pred
tab y_class rf_mtry_pred

* Test 5: Reproducibility - same seed should give same OOB
display _n "=== Test 5: Reproducibility ==="
fangorn y_class x1 x2 x3, type(classify) generate(rf_rep1) ntree(30) maxdepth(5) entcvdepth(0) seed(123)
local oob1 = r(oob_error)
fangorn y_class x1 x2 x3, type(classify) generate(rf_rep2) ntree(30) maxdepth(5) entcvdepth(0) seed(123)
local oob2 = r(oob_error)
display "OOB1: `oob1', OOB2: `oob2'"
assert abs(`oob1' - `oob2') < 1e-10

* Test 6: Different seeds give different results
display _n "=== Test 6: Different Seeds ==="
fangorn y_class x1 x2 x3, type(classify) generate(rf_s1) ntree(30) maxdepth(5) entcvdepth(0) seed(1)
local oob_s1 = r(oob_error)
fangorn y_class x1 x2 x3, type(classify) generate(rf_s2) ntree(30) maxdepth(5) entcvdepth(0) seed(999)
local oob_s2 = r(oob_error)
display "OOB seed=1: `oob_s1', OOB seed=999: `oob_s2'"

* Test 7: Forest with CV depth selection
display _n "=== Test 7: RF with CV ==="
fangorn y_class x1 x2 x3, type(classify) generate(rf_cv) ntree(20) maxdepth(10) entcvdepth(3) seed(42)
local oob_cv = r(oob_error)
local depth_cv = r(maxdepth)
summarize rf_cv_pred
display "OOB error: " `oob_cv'
display "Selected depth: " `depth_cv'

display _n "=== All tests passed ==="
