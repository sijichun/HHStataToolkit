clear all
set seed 19880505
set obs 1000

* New DGP
gen tx = rchi2(2)
gen x = log(tx) * 3
gen d = runiform() < 1/(1+exp(-1*x))
gen u = rnormal(0, 4)
gen y = (3+exp(x/20))^2 + 20 * d + u

* Create target variable (0=training, 1=test)
gen target = d

* Run nwreg with default leverage-corrected SE
nwreg y x, generate(yhat) se(se) setype(2) target(target)

* Compute 95% confidence intervals
gen ci_lower = yhat - 1.96 * se
gen ci_upper = yhat + 1.96 * se

* Sort by x for plotting
sort x

* Single plot with both target=0 and target=1
twoway (rarea ci_lower ci_upper x, color(gs14%80) lwidth(none)) ///
       (scatter y x if target==0, mcolor(gs10%25) msymbol(circle) msize(tiny)) ///
       (scatter y x if target==1, mcolor(navy%35) msymbol(circle) msize(tiny)) ///
       (line yhat x if target==0, lcolor(blue) lwidth(medium)) ///
       (line yhat x if target==1, lcolor(cranberry) lwidth(medium)) ///
       , title("NW Regression: Training + Test Sets") ///
         subtitle("N=1000, 70% training / 30% test, SE=leverage-corrected") ///
         xtitle("x = 3 * log(χ²(2))") ///
         ytitle("y = (3+exp(x/20))² + 20·d + u") ///
         legend(order(4 "Predicted Training" 5 "Predicted Test" 1 "95% CI" 2 "Training (target=0)" 3 "Test (target=1)") ///
                ring(0) pos(10) cols(1))
graph export "test_nwreg_combined.png", replace width(2400)

* Summary stats by target
tabstat y yhat se, by(target) stat(mean sd min max) nototal

