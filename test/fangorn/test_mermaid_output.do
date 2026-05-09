*! test_mermaid_output.do - Generate Mermaid tree diagrams for visual inspection

clear all
set seed 42
set obs 200

* ============================================================
* Generate sample data
* ============================================================
gen double income = runiform() * 100000
gen double age = runiform() * 80
gen double credit_score = runiform() * 850
gen int purchased = (income > 50000 & age > 40 & credit_score > 600)

* ============================================================
* Test 1: Single feature classification tree
* ============================================================
di _n "=== Mermaid Test 1: Single feature (income) ==="

fangorn purchased income, type(classify) generate(m1) maxdepth(3) mermaid(test/mermaid_single.md)

confirm file "test/mermaid_single.md"
di "  Generated: test/mermaid_single.md"

* ============================================================
* Test 2: Two features classification tree
* ============================================================
di _n "=== Mermaid Test 2: Two features (income + age) ==="

fangorn purchased income age, type(classify) generate(m2) maxdepth(3) mermaid(test/mermaid_two_features.md)

confirm file "test/mermaid_two_features.md"
di "  Generated: test/mermaid_two_features.md"

* ============================================================
* Test 3: Three features classification tree
* ============================================================
di _n "=== Mermaid Test 3: Three features (income + age + credit_score) ==="

fangorn purchased income age credit_score, type(classify) generate(m3) maxdepth(4) mermaid(test/mermaid_three_features.md)

confirm file "test/mermaid_three_features.md"
di "  Generated: test/mermaid_three_features.md"

* ============================================================
* Test 4: Regression tree
* ============================================================
di _n "=== Mermaid Test 4: Regression tree ==="

gen double spending = income * 0.3 + age * 500 + rnormal(0, 5000)

fangorn spending income age, type(regress) generate(m4) maxdepth(3) mermaid(test/mermaid_regression.md)

confirm file "test/mermaid_regression.md"
di "  Generated: test/mermaid_regression.md"

di _n "=== All Mermaid diagrams generated in test/ folder ==="

* Keep data for inspection if needed
* To view: type test/mermaid_*.md
