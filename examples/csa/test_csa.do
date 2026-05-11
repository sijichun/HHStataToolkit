clear
set seed 20250211
set obs 1000
gen treatment = runiform()<0.5
gen g = mod(_n,2)==0
gen x1 = rnormal(1+2*treatment+10*treatment*g,2)
gen x2 = rnormal(1+4*g,2)
csadensity x1 x2, group(g) treatment(treatment) gen(csa) 
twoway (scatter x2 x1 if treatment==0 & g==0) ///
       (scatter x2 x1 if treatment==1 & g==0) ///
       (scatter x2 x1 if treatment==0 & g==1) ///
       (scatter x2 x1 if treatment==1 & g==1) 
graph export csa1.png, replace
twoway (scatter x2 x1 if treatment==0 & g==0 & csa==1) ///
       (scatter x2 x1 if treatment==1 & g==0 & csa==1) ///
       (scatter x2 x1 if treatment==0 & g==1 & csa==1) ///
       (scatter x2 x1 if treatment==1 & g==1 & csa==1) 
graph export csa2.png, replace

clear
set seed 42
set obs 1000
gen x1 = runiform()*5
gen x2 = runiform()*10
gen treatment = runiform()<0.5
drop if treatment == 0 & (x2>2*x1+rnormal()*0.2 | x2<x1+rnormal()*0.2)
drop if treatment == 1 & (x2>-2*x1+10+rnormal()*0.2 | x2< -x1+5+rnormal()*0.2) 
csadensity x1 x2, treatment(treatment) generate(csa) debug

twoway (scatter x2 x1 if treatment==0) ///
       (scatter x2 x1 if treatment==1)
graph export csa3.png, replace
twoway (scatter x2 x1 if treatment==0 & csa==1) ///
       (scatter x2 x1 if treatment==1 & csa==1)
graph export csa4.png, replace
save csa, replace