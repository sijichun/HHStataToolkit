*! test_fangorn_phase1.do - Phase 1 decision tree tests
* Tests: regression, classification, target split, parameter sensitivity

clear all
set seed 42
set obs 200

* ============================================================
* Test 1: Simple regression with one feature
* y = 2*x + noise, should learn approximately y = 2*x
* ============================================================
di _n "=== Test 1: Simple regression (y = 2*x + noise) ==="

gen double x1 = runiform() * 10
gen double y_reg = 2 * x1 + rnormal(0, 1)

* Basic regression tree
fangorn y_reg x1, type(regress) generate(reg1) maxdepth(5)
di "  Observations: " r(N)
di "  Max depth:    " r(maxdepth)
di "  Type:         " r(type)

* Check predictions are not all missing
quietly count if reg1_pred != .
di "  Non-missing predictions: " r(N)
assert r(N) == 200

* With one feature and depth 5, should fit well - check correlation
correlate y_reg reg1_pred
di "  Correlation (y, pred): " r(rho)
assert r(rho) > 0.85

* Check leaf IDs are assigned
quietly count if reg1 != .
di "  Non-missing leaf IDs:  " r(N)
assert r(N) == 200

* Check some leaf IDs differ (tree actually split)
quietly summarize reg1
di "  Unique leaf IDs (approx): " r(max) - r(min) + 1
assert r(max) > r(min)

drop reg1_pred reg1

* ============================================================
* Test 2: Regression with two features
* y = x1 + 3*x2 + noise
* ============================================================
di _n "=== Test 2: Regression with 2 features ==="

gen double x2 = runiform() * 5
gen double y_reg2 = x1 + 3*x2 + rnormal(0, 2)

fangorn y_reg2 x1 x2, type(regress) generate(reg2) maxdepth(10)

quietly count if reg2_pred != .
assert r(N) == 200

correlate y_reg2 reg2_pred
di "  Correlation (y, pred): " r(rho)
assert r(rho) > 0.80

drop reg2_pred reg2 y_reg2

* ============================================================
* Test 3: Classification - binary outcome
* class = 0 if x1 < 5, class = 1 if x1 >= 5 (with some noise)
* ============================================================
di _n "=== Test 3: Binary classification ==="

gen int class = (x1 >= 5)
* Add a few misclassified points for realism
replace class = 1 - class if runiform() < 0.05

fangorn class x1, type(classify) generate(clf1) maxdepth(5)

quietly count if clf1_pred != .
assert r(N) == 200

* Check accuracy (should be high since data is mostly separable)
gen double correct = (class == clf1_pred)
quietly summarize correct
di "  Accuracy: " r(mean)
assert r(mean) > 0.85

drop correct clf1_pred clf1

* ============================================================
* Test 4: Classification - multi-class with 2 features
* 3 classes based on x1 and x2 regions
* ============================================================
di _n "=== Test 4: Multi-class classification (3 classes) ==="

gen int multi_class = 0
replace multi_class = 1 if x1 > 3 & x1 < 7
replace multi_class = 2 if x1 >= 7

fangorn multi_class x1 x2, type(classify) generate(clf2) maxdepth(10)

quietly count if clf2_pred != .
assert r(N) == 200

* Check accuracy
gen double correct2 = (multi_class == clf2_pred)
quietly summarize correct2
di "  Accuracy: " r(mean)
assert r(mean) > 0.70

drop correct2 clf2_pred clf2

* ============================================================
* Test 5: Target split (train/test)
* Train on target=0, predict on all including target=1
* ============================================================
di _n "=== Test 5: Target split (train/test) ==="

gen byte target_split = (_n <= 150)  /* 150 train, 50 test */

fangorn class x1, type(classify) generate(clf3) target(target_split) maxdepth(5)

* All observations should have predictions
quietly count if clf3_pred != .
di "  Predictions (all obs): " r(N)
assert r(N) == 200

* Train set accuracy
gen double correct3 = (class == clf3_pred)
quietly summarize correct3 if target_split == 0
di "  Train accuracy: " r(mean)

* Test set accuracy  
quietly summarize correct3 if target_split == 1
di "  Test accuracy:  " r(mean)

drop correct3 clf3_pred clf3 target_split

* ============================================================
* Test 6: Parameter sensitivity - minsamplessplit
* ============================================================
di _n "=== Test 6: Parameter sensitivity (minsamplessplit) ==="

* With minsamplessplit=100, tree should be very shallow
fangorn class x1, type(classify) generate(clf4) maxdepth(20) minsamplessplit(100)
quietly levelsof clf4, local(leaves4)
di "  Leaves with minsamplessplit=100: `: word count `leaves4''"

* With minsamplessplit=2, tree should be deeper
fangorn class x1, type(classify) generate(clf5) maxdepth(20) minsamplessplit(2)
quietly levelsof clf5, local(leaves5)
di "  Leaves with minsamplessplit=2:   `: word count `leaves5''"
assert `: word count `leaves5'' > `: word count `leaves4''

drop clf4_pred clf4 clf5_pred clf5

* ============================================================
* Test 7: Parameter sensitivity - maxdepth
* ============================================================
di _n "=== Test 7: Parameter sensitivity (maxdepth) ==="

* maxdepth=1: single split (at most 2 leaves)
fangorn class x1, type(classify) generate(clf6) maxdepth(1)
quietly levelsof clf6, local(leaves6)
di "  Leaves with maxdepth=1: `: word count `leaves6''"
assert `: word count `leaves6'' <= 2

* maxdepth=3: at most 8 leaves
fangorn class x1, type(classify) generate(clf7) maxdepth(3)
quietly levelsof clf7, local(leaves7)
di "  Leaves with maxdepth=3: `: word count `leaves7''"
assert `: word count `leaves7'' <= 8

drop clf6_pred clf6 clf7_pred clf7

* ============================================================
* Test 8: Different impurity criteria for classification
* ============================================================
di _n "=== Test 8: Impurity criteria (gini vs entropy) ==="

fangorn class x1, type(classify) generate(gini_test) criterion(gini) maxdepth(5)
fangorn class x1, type(classify) generate(ent_test) criterion(entropy) maxdepth(5)

* Both should produce valid predictions
quietly count if gini_test_pred != .
assert r(N) == 200
quietly count if ent_test_pred != .
assert r(N) == 200

gen double acc_gini = (class == gini_test_pred)
gen double acc_ent = (class == ent_test_pred)
quietly summarize acc_gini
di "  Gini accuracy:    " r(mean)
quietly summarize acc_ent  
di "  Entropy accuracy: " r(mean)

drop acc_gini acc_ent gini_test_pred gini_test ent_test_pred ent_test

* ============================================================
* Test 9: if() condition filtering
* ============================================================
di _n "=== Test 9: if() condition ==="

fangorn class x1, type(classify) generate(clf8) if(x1 < 8) maxdepth(5)

* Only x1 < 8 should have predictions
quietly count if clf8_pred != . & x1 < 8
di "  Predictions for x1<8: " r(N)
assert r(N) > 0

quietly count if clf8_pred != . & x1 >= 8
di "  Predictions for x1>=8 (should be 0): " r(N)
assert r(N) == 0

drop clf8_pred clf8

* ============================================================
* Test 10: group variable (Phase 1: read but not group-specific)
* ============================================================
di _n "=== Test 10: Group variable ==="

gen int grp = (_n <= 100)

fangorn class x1, type(classify) generate(clf9) group(grp) maxdepth(5)

    quietly count if clf9_pred != .
    assert r(N) == 200

    drop clf9_pred clf9 grp

    * ============================================================
    * Test 11: Mermaid diagram export
    * ============================================================
    di _n "=== Test 11: Mermaid diagram export ==="

    fangorn class x1, type(classify) generate(clf10) maxdepth(2) mermaid(test_tree.md)

    * Check file was created
    confirm file "test_tree.md"
    di "  Mermaid file created: test_tree.md"
    type test_tree.md

    erase test_tree.md

    drop clf10_pred clf10

    * ============================================================
    * Cleanup
    * ============================================================
    di _n "=== All Phase 1 tests passed! ==="

* Keep only original vars for clean exit
drop x1 x2 class multi_class y_reg
