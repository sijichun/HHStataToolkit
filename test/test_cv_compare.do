*! Test: Compare CV vs default bandwidth (accuracy + time)
capture cd ".."
clear all
set seed 42
capture program drop _kdensity2_plugin
capture program drop kdensity2

local methods "silverman cv cv5"
local mlabels "Silverman CV-10  CV-5"

* ------------------------------------------------------------------
* Test 1: Normal mixture — 0.5*N(-2,1) + 0.5*N(2,1)
* ------------------------------------------------------------------
display as text _n "{hline 60}"
display as text "Test 1: Normal mixture"
set obs 2000
gen double mix = runiform()
gen double y1 = cond(mix<0.5, rnormal(-2,1), rnormal(2,1))
gen double f_th1 = 0.5*normalden(y1,-2,1) + 0.5*normalden(y1,2,1)
sort y1

forvalues i = 1/3 {
    local m : word `i' of `methods'
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 y1, bw(`m') generate(f1_`m')
    local t1 = clock(c(current_time), "hms")
    local elapsed = (`t1' - `t0') / 1000
    gen double e1_`m' = abs(f1_`m' - f_th1)
    quietly sum e1_`m'
    local _mae = r(mean)
    quietly correlate f1_`m' f_th1
    local _rho = r(rho)
    display as text "  bw(`m'): " as result %7.1f `elapsed' "s" ///
        _col(14) "MAE=" %9.6f `_mae' _col(30) "Corr=" %7.4f `_rho'
}

twoway (line f_th1 y1, sort lc(black) lp(solid) lw(medthick)) ///
       (line f1_silverman y1, sort lc(navy) lp(dash)) ///
       (line f1_cv y1, sort lc(maroon) lp(dot)) ///
       (line f1_cv5 y1, sort lc(forest_green) lp(dash_dot)), ///
       legend(order(1 "Theory" 2 "Silverman" 3 "CV-10" 4 "CV-5") rows(1)) ///
       title("Normal Mixture")
graph export "test_cv_compare1.png", replace width(1200)
drop y1 f_th1 f1_* e1_*

* ------------------------------------------------------------------
* Test 2: t(3) — heavy tail
* ------------------------------------------------------------------
display as text _n "{hline 60}"
display as text "Test 2: t(3)"
set obs 2000
gen double y2 = rt(3)
gen double f_th2 = tden(3, y2)
sort y2

forvalues i = 1/3 {
    local m : word `i' of `methods'
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 y2, bw(`m') generate(f2_`m')
    local t1 = clock(c(current_time), "hms")
    local elapsed = (`t1' - `t0') / 1000
    gen double e2_`m' = abs(f2_`m' - f_th2)
    quietly sum e2_`m'
    local _mae = r(mean)
    quietly correlate f2_`m' f_th2
    local _rho = r(rho)
    display as text "  bw(`m'): " as result %7.1f `elapsed' "s" ///
        _col(14) "MAE=" %9.6f `_mae' _col(30) "Corr=" %7.4f `_rho'
}

twoway (line f_th2 y2, sort lc(black) lp(solid) lw(medthick)) ///
       (line f2_silverman y2, sort lc(navy) lp(dash)) ///
       (line f2_cv y2, sort lc(maroon) lp(dot)) ///
       (line f2_cv5 y2, sort lc(forest_green) lp(dash_dot)), ///
       legend(order(1 "Theory" 2 "Silverman" 3 "CV-10" 4 "CV-5") rows(1)) ///
       title("t(3)")
graph export "test_cv_compare2.png", replace width(1200)
drop y2 f_th2 f2_* e2_*

* ------------------------------------------------------------------
* Test 3: chi2(3) — skewed
* ------------------------------------------------------------------
display as text _n "{hline 60}"
display as text "Test 3: chi2(3)"
set obs 2000
gen double y3 = rchi2(3)
gen double f_th3 = chi2den(3, y3)
sort y3

forvalues i = 1/3 {
    local m : word `i' of `methods'
    local t0 = clock(c(current_time), "hms")
    capture kdensity2 y3, bw(`m') generate(f3_`m')
    local t1 = clock(c(current_time), "hms")
    local elapsed = (`t1' - `t0') / 1000
    gen double e3_`m' = abs(f3_`m' - f_th3)
    quietly sum e3_`m'
    local _mae = r(mean)
    quietly correlate f3_`m' f_th3
    local _rho = r(rho)
    display as text "  bw(`m'): " as result %7.1f `elapsed' "s" ///
        _col(14) "MAE=" %9.6f `_mae' _col(30) "Corr=" %7.4f `_rho'
}

twoway (line f_th3 y3, sort lc(black) lp(solid) lw(medthick)) ///
       (line f3_silverman y3, sort lc(navy) lp(dash)) ///
       (line f3_cv y3, sort lc(maroon) lp(dot)) ///
       (line f3_cv5 y3, sort lc(forest_green) lp(dash_dot)), ///
       legend(order(1 "Theory" 2 "Silverman" 3 "CV-10" 4 "CV-5") rows(1)) ///
       title("chi2(3)")
graph export "test_cv_compare3.png", replace width(1200)
drop y3 f_th3 f3_* e3_*

display as text _n "{hline 60}"
display as text "All tests complete. Plots: test_cv_compare{1,2,3}.png"
display as text "{hline 60}"
