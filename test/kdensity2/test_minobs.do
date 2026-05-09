capture program drop kdensity2
capture program drop _kdensity2_plugin
clear all
set obs 500
set seed 42
gen x = rnormal()
gen g = floor((_n-1)/250)   /* 2 groups: g=0 has 250, g=1 has 250 */

di "=== Test: mincount(300) ==="
kdensity2 x, group(g) generate(f1) mincount(300)
quietly count if !missing(f1)
di "f1 non-missing (should be 0, both groups <300): " r(N)

di "=== Test: mincount(200) ==="
kdensity2 x, group(g) generate(f2) mincount(200)
quietly count if !missing(f2)
di "f2 non-missing (should be 500, both groups >=200): " r(N)

di "=== Test: default (0) ==="
kdensity2 x, group(g) generate(f3)
quietly count if !missing(f3)
di "f3 non-missing (should be 500): " r(N)

di "=== All done ==="
