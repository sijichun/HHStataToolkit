*! test_fangorn_cv.do - Cross-validated depth selection tests
* Tests: entcvdepth option with different settings, regression, RF+CV
* Run: stata -b do test/fangorn/test_fangorn_cv.do

clear all
set seed 42
set obs 1000

* ============================================================
* Setup: generate test data with 5 features, clear structure
* ============================================================
gen double x1 = runiform() * 10
gen double x2 = runiform() * 10
gen double x3 = rnormal()
gen double x4 = rnormal()
gen double x5 = rnormal()
* Non-linear classification boundary
gen int y_class = 0
replace y_class = 1 if x1 > 3 & x1 < 7 & x2 > 4
replace y_class = 2 if x1 >= 7 | (x1 > 3 & x1 < 7 & x2 <= 4)
gen double y_reg = x1 + 2*x2 - 0.5*x3 + x4*x5 + rnormal(0, 3)

* ============================================================
* Test 1: CV depth selection — basic classification
* ============================================================
di _n "{hline 60}"
di "=== Test 1: CV depth selection (classification, entcvdepth=5) ==="
di "{hline 60}"
fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(cv1) ///
    maxdepth(15) entcvdepth(5) seed(42)
local cv1_depth = r(maxdepth)
di "  Selected depth: " `cv1_depth'
* Depth should be between 1 and 15
assert `cv1_depth' >= 1 & `cv1_depth' <= 15
* Predictions should be valid
quietly count if cv1_pred != .
assert r(N) == 1000
gen byte cv1_correct = (y_class == cv1_pred)
quietly summarize cv1_correct
di "  Accuracy: " %9.4f r(mean)
assert r(mean) > 0.50
drop cv1_pred cv1 cv1_correct

* ============================================================
* Test 2: CV with different fold counts
* ============================================================
di _n "{hline 60}"
di "=== Test 2: CV with entcvdepth=3 (3-fold) ==="
di "{hline 60}"
fangorn y_class x1 x2 x3, type(classify) generate(cv2) ///
    maxdepth(10) entcvdepth(3) seed(42)
local cv2_depth = r(maxdepth)
di "  Selected depth (entcvdepth=3): " `cv2_depth'
assert `cv2_depth' >= 1 & `cv2_depth' <= 10
quietly count if cv2_pred != .
assert r(N) == 1000
drop cv2_pred cv2

* ============================================================
* Test 3: CV depth selection — regression
* ============================================================
di _n "{hline 60}"
di "=== Test 3: CV depth selection (regression, entcvdepth=5) ==="
di "{hline 60}"
fangorn y_reg x1 x2 x3 x4 x5, type(regress) generate(cv3) ///
    maxdepth(10) entcvdepth(5) seed(42)
local cv3_depth = r(maxdepth)
di "  Selected depth (regression): " `cv3_depth'
assert `cv3_depth' >= 1 & `cv3_depth' <= 10
quietly count if cv3_pred != .
assert r(N) == 1000
correlate y_reg cv3_pred
di "  Correlation (y, pred): " %9.4f r(rho)
assert r(rho) > 0.50
drop cv3_pred cv3

* ============================================================
* Test 4: CV disabled (entcvdepth=0) vs enabled
* ============================================================
di _n "{hline 60}"
di "=== Test 4: CV disabled (entcvdepth=0) ==="
di "{hline 60}"
fangorn y_class x1 x2 x3, type(classify) generate(cv4_disabled) ///
    maxdepth(10) entcvdepth(0) seed(42)
local d4_depth = r(maxdepth)
di "  Depth (entcvdepth=0, uses maxdepth): " `d4_depth'
* Without CV, maxdepth should be exactly what was specified
assert `d4_depth' == 10
* With CV enabled, depth is chosen by CV
fangorn y_class x1 x2 x3, type(classify) generate(cv4_enabled) ///
    maxdepth(10) entcvdepth(5) seed(42)
local e4_depth = r(maxdepth)
di "  Depth (entcvdepth=5, CV selected): " `e4_depth'
* Depths should differ (CV makes its own choice)
* (They could theoretically be the same, but that's fine)
assert `e4_depth' >= 1 & `e4_depth' <= 10
drop cv4_disabled_pred cv4_disabled cv4_enabled_pred cv4_enabled

* ============================================================
* Test 5: CV with target split
* ============================================================
di _n "{hline 60}"
di "=== Test 5: CV with target split ==="
di "{hline 60}"
gen byte target_cv = (_n <= 700)
fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(cv5) ///
    maxdepth(10) entcvdepth(4) target(target_cv) seed(42)
local cv5_depth = r(maxdepth)
di "  Selected depth (with target): " `cv5_depth'
assert `cv5_depth' >= 1 & `cv5_depth' <= 10
* All should have predictions
quietly count if cv5_pred != .
assert r(N) == 1000
gen byte cv5_correct = (y_class == cv5_pred)
* Test set accuracy should be reasonable
quietly summarize cv5_correct if target_cv == 1
di "  Test accuracy: " %9.4f r(mean)
assert r(mean) > 0.30
drop cv5_pred cv5 cv5_correct target_cv

* ============================================================
* Test 6: Reproducibility of CV selection
* ============================================================
di _n "{hline 60}"
di "=== Test 6: CV reproducibility ==="
di "{hline 60}"
fangorn y_class x1 x2 x3, type(classify) generate(cv6a) ///
    maxdepth(10) entcvdepth(5) seed(777)
local d6a = r(maxdepth)
fangorn y_class x1 x2 x3, type(classify) generate(cv6b) ///
    maxdepth(10) entcvdepth(5) seed(777)
local d6b = r(maxdepth)
di "  Run 1 depth: " `d6a'
di "  Run 2 depth: " `d6b'
* Same seed → same depth
assert `d6a' == `d6b'
* Same seed → same predictions
gen byte cv6_match = (cv6a_pred == cv6b_pred)
quietly summarize cv6_match
assert r(mean) == 1.0
drop cv6a_pred cv6a cv6b_pred cv6b cv6_match

* ============================================================
* Test 7: CV with ntiles (combined options)
* ============================================================
di _n "{hline 60}"
di "=== Test 7: CV + ntiles combined ==="
di "{hline 60}"
fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(cv7) ///
    maxdepth(10) entcvdepth(4) ntiles(20) seed(42)
local cv7_depth = r(maxdepth)
di "  Selected depth (CV+ntiles): " `cv7_depth'
assert `cv7_depth' >= 1 & `cv7_depth' <= 10
quietly count if cv7_pred != .
assert r(N) == 1000
gen byte cv7_correct = (y_class == cv7_pred)
quietly summarize cv7_correct
di "  Accuracy (CV+ntiles): " %9.4f r(mean)
assert r(mean) > 0.40
drop cv7_pred cv7 cv7_correct

* ============================================================
* Test 8: CV with RF (ntree > 1)
* ============================================================
di _n "{hline 60}"
di "=== Test 8: CV with RF (ntree=30) ==="
di "{hline 60}"
fangorn y_class x1 x2 x3 x4 x5, type(classify) generate(cv8) ///
    ntree(30) maxdepth(10) entcvdepth(4) seed(42)
local cv8_depth = r(maxdepth)
di "  Selected depth (RF+CV): " `cv8_depth'
di "  OOB error: " %9.4f r(oob_error)
assert `cv8_depth' >= 1 & `cv8_depth' <= 10
quietly count if cv8_pred != .
assert r(N) == 1000
gen byte cv8_correct = (y_class == cv8_pred)
quietly summarize cv8_correct
di "  RF+CV accuracy: " %9.4f r(mean)
assert r(mean) > 0.50
drop cv8_pred cv8 cv8_correct

* ============================================================
* Test 9: High maxdepth with CV
* ============================================================
di _n "{hline 60}"
di "=== Test 9: High maxdepth=20 with CV ==="
di "{hline 60}"
fangorn y_class x1 x2 x3, type(classify) generate(cv9) ///
    maxdepth(20) entcvdepth(5) seed(42)
local cv9_depth = r(maxdepth)
di "  Selected depth (maxdepth=20): " `cv9_depth'
* CV should pick a depth <= 20
assert `cv9_depth' >= 1 & `cv9_depth' <= 20
quietly count if cv9_pred != .
assert r(N) == 1000
drop cv9_pred cv9

* ============================================================
* Test 10: RF with CV and ntiles combined
* ============================================================
di _n "{hline 60}"
di "=== Test 10: RF + CV + ntiles combined ==="
di "{hline 60}"
fangorn y_reg x1 x2 x3 x4 x5, type(regress) generate(cv10) ///
    ntree(20) maxdepth(10) entcvdepth(3) ntiles(15) seed(42)
local cv10_depth = r(maxdepth)
di "  Selected depth (RF+CV+ntiles): " `cv10_depth'
di "  OOB error (MSE): " %9.4f r(oob_error)
assert `cv10_depth' >= 1 & `cv10_depth' <= 10
quietly count if cv10_pred != .
assert r(N) == 1000
correlate y_reg cv10_pred
di "  Correlation: " %9.4f r(rho)
assert r(rho) > 0.40
drop cv10_pred cv10

di _n "{hline 60}"
di "=== All CV tests passed! ==="
di "{hline 60}"
exit 0
