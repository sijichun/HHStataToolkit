clear
set seed 20250211
set obs 5000
gen g = mod(_n,2)==0
gen x = rnormal(1+2*g,2)
gen treatment = x > runiform()
gen y = 1 + 2*treatment + 10*treatment*g + 10*sin(x) + rnormal(0,2)
csadensity x, group(g) treatment(treatment) gen(csa)
nwreg y x, target(treatment) group(g) gen(conterfacurals) if(csa==1)
gen te = y - conterfacurals if treatment==1 & csa==1
bysort g: su te
twoway (scatter y x if treatment==0 & g==0) ///
(scatter y x if treatment==0 & g==1) ///
(scatter y x if treatment==1 & g==0) ///
(scatter y x if treatment==1 & g==1), legend(order(1 "Control, Group 0" 2 "Control, Group 1" 3 "Treatment, Group 0" 4 "Treatment, Group 1")) 
graph export "scatter_plot1.png", replace
twoway (scatter y x if csa==1 & treatment==1 & g==0) ///
(scatter y x if csa==1 & treatment==0 & g==0) ///
(scatter y x if csa==1 & treatment==1 & g==1) ///
(scatter y x if csa==1 & treatment==0 & g==1) ///
(scatter conterfacurals x if csa==1 & treatment==1), legend(order(1 "Treatment, Group 0" 2 "Control, Group 0" 3 "Treatment, Group 1" 4 "Control, Group 1" 5 "Counterfactuals"))
graph export "scatter_plot2.png", replace