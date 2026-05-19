*! Test script for kdensity2
* Compares theoretical chi2 density with kdensity2 estimates
* Two group variables: d1=0/1, d2=0/1
* x ~ chi2((1+d1)^2 + d2)

* Ensure we run from project root where kdensity2/ directory exists
capture cd ".."

clear all
set obs 5000

* Generate group variables d1 = 0/1, d2 = 0/1
* 4 groups: (0,0), (0,1), (1,0), (1,1), each with 1250 obs
gen d1 = mod(floor((_n-1)/1250), 2)
gen d2 = mod(floor((_n-1)/625), 2)

* Compute degrees of freedom: df = (1+d1)^2 + d2
gen int df = (1+d1)^2 + d2

* x ~ chi2(df)
gen double x = rchi2(df)

* Ensure x > 0 (chi2 is positive)
replace x = x if x > 0

* -----------------------------------------
* 1. Compute theoretical density
* Chi2 PDF: f(x) = x^(k/2-1) * exp(-x/2) / (2^(k/2) * gamma(k/2))
* In Stata: chi2den(df, x)
* -----------------------------------------
gen double f_theory = chi2den(df, x)

* -----------------------------------------
* 2. Estimate density using kdensity2
* -----------------------------------------
* First verify plugin exists
capture which kdensity2
if _rc {
    display as error "kdensity2 not found. Run 'make install' first."
    exit 111
}

* Run kdensity2 with group variables d1 d2
kdensity2 x, group(d1 d2) generate(f_kde)

* -----------------------------------------
* 3. Compare: compute absolute error
* -----------------------------------------
gen double abs_err = abs(f_kde - f_theory)
summarize abs_err, detail

* -----------------------------------------
* 4. Plot: theory vs estimate by group
* -----------------------------------------
* Create group label for display
egen group_id = group(d1 d2)
label define grouplbl 1 "(0,0): df=1" 2 "(0,1): df=2" 3 "(1,0): df=4" 4 "(1,1): df=5"
label values group_id grouplbl

* Sort for line plots
sort group_id x

* Panel plot: one panel per group
forvalues g = 1/4 {
    quietly summarize x if group_id==`g'
    local x_min`g' = r(min)
    local x_max`g' = r(max)
}

twoway (line f_theory x if group_id==1, sort lcolor(navy) lpattern(solid)) ///
       (scatter f_kde x if group_id==1, mcolor(navy%30) msymbol(o) msize(small)) ///
       (line f_theory x if group_id==2, sort lcolor(maroon) lpattern(solid)) ///
       (scatter f_kde x if group_id==2, mcolor(maroon%30) msymbol(o) msize(small)) ///
       (line f_theory x if group_id==3, sort lcolor(forest_green) lpattern(solid)) ///
       (scatter f_kde x if group_id==3, mcolor(forest_green%30) msymbol(o) msize(small)) ///
       (line f_theory x if group_id==4, sort lcolor(purple) lpattern(solid)) ///
       (scatter f_kde x if group_id==4, mcolor(purple%30) msymbol(o) msize(small)), ///
       by(group_id, title("Theoretical vs Estimated Chi-square Density") ///
             note("Blue solid = theoretical, Red dots = kdensity2 estimate") ///
             rows(2)) ///
       xtitle("x") ytitle("Density") ///
       legend(order(1 "Theoretical" 2 "kdensity2") rows(1))

graph export "kdensity2_test_bygroup.png", replace width(1200)

* Overlay plot: all groups on same graph
twoway (line f_theory x if group_id==1, sort lcolor(navy) lpattern(solid)) ///
       (line f_theory x if group_id==2, sort lcolor(maroon) lpattern(solid)) ///
       (line f_theory x if group_id==3, sort lcolor(forest_green) lpattern(solid)) ///
       (line f_theory x if group_id==4, sort lcolor(purple) lpattern(solid)) ///
       (scatter f_kde x if group_id==1, mcolor(navy%30) msymbol(o) msize(small)) ///
       (scatter f_kde x if group_id==2, mcolor(maroon%30) msymbol(o) msize(small)) ///
       (scatter f_kde x if group_id==3, mcolor(forest_green%30) msymbol(o) msize(small)) ///
       (scatter f_kde x if group_id==4, mcolor(purple%30) msymbol(o) msize(small)), ///
       xtitle("x") ytitle("Density") ///
       title("Theoretical vs Estimated Chi-square Density by Group") ///
       subtitle("Solid lines = theoretical, Scattered dots = kdensity2") ///
       legend(order(1 "(0,0): df=1" 2 "(0,1): df=2" 3 "(1,0): df=4" 4 "(1,1): df=5" ///
                    5 "kde (0,0)" 6 "kde (0,1)" 7 "kde (1,0)" 8 "kde (1,1)") rows(2))

graph export "kdensity2_test_overlay.png", replace width(1200)

* -----------------------------------------
* 5. Summary statistics
* -----------------------------------------
display as text _n "{hline 60}"
display as text "Test Summary: Chi-square distribution with 2-way grouping"
display as text "  x ~ chi2((1+d1)^2 + d2), d1=0/1, d2=0/1"
display as text "{hline 60}"
summarize f_theory f_kde abs_err
display as text "Mean absolute error: " as result r(mean)
display as text "Max absolute error:  " as result r(max)
display as text "{hline 60}"

* Correlation between theory and estimate by group
display as text _n "Correlation (theory, estimate) by group:"
forvalues g = 1/4 {
    quietly correlate f_theory f_kde if group_id==`g'
    display as text "  Group `g': " as result %6.4f r(rho)
}

* -----------------------------------------
* 6. Bandwidth comparison by group
* -----------------------------------------
display as text _n "{hline 60}"
display as text "Bandwidth summary by group (Silverman's rule):"
display as text "{hline 60}"

forvalues g = 1/4 {
    quietly summarize x if group_id==`g', detail
    local n_g = r(N)
    local sd_g = r(sd)
    local iqr_g = r(p75) - r(p25)
    local A = min(`sd_g', `iqr_g'/1.34)
    local h_g = 0.9 * `A' * (`n_g'^(-0.2))
    display as text "  Group `g' (d1=`=(`g'-1)\2', d2=`=mod(`g'-1,2)'): " ///
        "n=`n_g', h=" as result %6.4f `h_g'
}

display as text "{hline 60}"
