*! Test script for kdensity2 - Multivariate (2D) density estimation
* x1 ~ N(0,1), x2 = 2*x1 + x3 + u, u ~ N(0,1)
* x3 ~ Bernoulli(invlogit(x1)) - grouping variable
* Estimate 2D density of (x1, x2) by x3 groups
* N=5000

capture cd ".."

clear all
set obs 5000
set seed 42

* Generate x1 ~ N(0,1)
gen double x1 = rnormal(0, 1)

* Generate x3 ~ Bernoulli(p), p = invlogit(x1)
gen double p = invlogit(x1)
gen byte x3 = runiform() < p

* Generate x2 = 2*x1 + x3 + u, u ~ N(0,1)
gen double u = rnormal(0, 1)
gen double x2 = 2*x1 + x3 + u

* -----------------------------------------
* 1. Compute theoretical 2D density
* Joint: f(x1, x2 | x3) = f(x1) * P(x3|x1) * f(x2|x1,x3) / P(x3)
* where f(x2|x1,x3=0) = N(2*x1, 1), f(x2|x1,x3=1) = N(2*x1+1, 1)
* -----------------------------------------

* Empirical P(x3=0) and P(x3=1) from data
quietly summarize x3
local p1 = r(mean)
local p0 = 1 - `p1'

gen double f_theory = .

* Group x3=0: f(x1,x2|x3=0) = normalden(x1) * invlogit(-x1) * normalden(x2-2*x1) / p0
replace f_theory = normalden(x1) * invlogit(-x1) * normalden(x2 - 2*x1) / `p0' if x3==0

* Group x3=1: f(x1,x2|x3=1) = normalden(x1) * invlogit(x1) * normalden(x2-(2*x1+1)) / p1
replace f_theory = normalden(x1) * invlogit(x1) * normalden(x2 - 2*x1 - 1) / `p1' if x3==1

* -----------------------------------------
* 2. Estimate 2D density using kdensity2
* -----------------------------------------
capture which kdensity2
if _rc {
    display as error "kdensity2 not found. Run 'make install' first."
    exit 111
}

* Multivariate KDE: x1 x2, grouped by x3
kdensity2 x1 x2, group(x3) generate(f_kde)

* -----------------------------------------
* 3. Compare: MAE and correlation
* -----------------------------------------
gen double abs_err = abs(f_kde - f_theory)

* Overall
quietly summarize abs_err
display as text _n "{hline 60}"
display as text "Overall Comparison (all observations, N=5000)"
display as text "{hline 60}"
display as text "  P(x3=0) = " as result %5.3f `p0' ", P(x3=1) = " as result %5.3f `p1'
display as text "  Mean Absolute Error (MAE): " as result %10.6f r(mean)
display as text "  Max Absolute Error:        " as result %10.6f r(max)

quietly correlate f_theory f_kde
display as text "  Correlation (theory, kde): " as result %10.6f r(rho)
display as text "{hline 60}"

* By group (x3 = 0 vs 1)
display as text _n "{hline 60}"
display as text "By-Group Comparison"
display as text "{hline 60}"

forvalues g = 0/1 {
    quietly summarize abs_err if x3==`g'
    local mae`g' = r(mean)
    local maxe`g' = r(max)
    
    quietly correlate f_theory f_kde if x3==`g'
    local rho`g' = r(rho)
    
    quietly count if x3==`g'
    local n`g' = r(N)
    
    display as text "  Group x3=`g' (n=`n`g''):"
    display as text "    MAE:         " as result %10.6f `mae`g''
    display as text "    Max Error:   " as result %10.6f `maxe`g''
    display as text "    Correlation: " as result %10.6f `rho`g''
}

display as text "{hline 60}"

* -----------------------------------------
* 4. Summary statistics by group
* -----------------------------------------
display as text _n "{hline 60}"
display as text "Descriptive Statistics by Group"
display as text "{hline 60}"

forvalues g = 0/1 {
    quietly summarize x1 if x3==`g'
    display as text "  Group x3=`g' (n=`n`g''):"
    display as text "    x1: mean=" as result %7.3f r(mean) " sd=" as result %6.3f r(sd)
    
    quietly summarize x2 if x3==`g'
    display as text "    x2: mean=" as result %7.3f r(mean) " sd=" as result %6.3f r(sd)
    
    quietly correlate x1 x2 if x3==`g'
    display as text "    corr(x1,x2): " as result %6.4f r(rho)
    display as text ""
}

display as text "{hline 60}"

* -----------------------------------------
* 5. Density value summaries
* -----------------------------------------
display as text _n "{hline 60}"
display as text "Density Value Summaries"
display as text "{hline 60}"

quietly summarize f_theory
display as text "  f_theory: mean=" as result %10.6f r(mean) " sd=" as result %10.6f r(sd) ///
    " min=" as result %10.6f r(min) " max=" as result %10.6f r(max)

quietly summarize f_kde
display as text "  f_kde:    mean=" as result %10.6f r(mean) " sd=" as result %10.6f r(sd) ///
    " min=" as result %10.6f r(min) " max=" as result %10.6f r(max)

display as text "{hline 60}"
