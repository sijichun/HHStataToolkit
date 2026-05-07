*! Test script for nwreg: simulation with known DGP
* DGP: y = sin(x1) / exp(x2 * d) + u
*      u ~ N(0,1), d ~ Bernoulli(0.5), x1 ~ chi2(5), x2 ~ N(0,1)

clear all
set obs 1000
set seed 42

* Generate regressors and grouping variable
gen double x1 = rchi2(5)
gen double x2 = rnormal(0, 1)
gen byte   d  = runiform() < 0.5

* Generate error and response
gen double u = rnormal(0, 1)
gen double y = sin(x1) / exp(x2 * d) + u

* True conditional mean (for evaluation)
gen double y_true = sin(x1) / exp(x2 * d)

* --- nwreg with default bandwidth (silverman) ---
nwreg y x1 x2, group(d) generate(yhat_nwreg_silv)

* --- nwreg with CV bandwidth ---
nwreg y x1 x2, group(d) bw(cv) generate(yhat_nwreg_cv)

* --- Linear regression benchmark (interacted with d) ---
reg y c.x1##i.d c.x2##i.d
predict double yhat_ols, xb

* --- Compute metrics ---
* RMSE against true conditional mean
gen double sqerr_nwreg_silv = (yhat_nwreg_silv - y_true)^2
gen double sqerr_nwreg_cv   = (yhat_nwreg_cv - y_true)^2
gen double sqerr_ols        = (yhat_ols - y_true)^2

quietly summarize sqerr_nwreg_silv
gen double rmse_nwreg_silv = sqrt(r(mean))

quietly summarize sqerr_nwreg_cv
gen double rmse_nwreg_cv = sqrt(r(mean))

quietly summarize sqerr_ols
gen double rmse_ols = sqrt(r(mean))

* Correlation with true conditional mean
quietly correlate yhat_nwreg_silv y_true
gen double corr_nwreg_silv = r(rho)

quietly correlate yhat_nwreg_cv y_true
gen double corr_nwreg_cv = r(rho)

quietly correlate yhat_ols y_true
gen double corr_ols = r(rho)

* --- Display results ---
display as text _n "{hline 65}"
display as text "  Simulation: y = sin(x1) / exp(x2 * d) + u, N = 1000"
display as text "{hline 65}"
display as text ""
display as text "  Method                RMSE (vs true E[y|x])    Corr(yhat, y_true)"
display as text "  {hline 63}"
display as text "  nwreg (silverman)     " as result %9.4f rmse_nwreg_silv[1] "              " %9.4f corr_nwreg_silv[1]
display as text "  nwreg (cv)            " as result %9.4f rmse_nwreg_cv[1]   "              " %9.4f corr_nwreg_cv[1]
display as text "  OLS (interacted)      " as result %9.4f rmse_ols[1]        "              " %9.4f corr_ols[1]
display as text "{hline 65}"

* --- By-group summary ---
display as text _n "  By-group RMSE:"
bysort d: egen double rmse_silv_g = mean(sqerr_nwreg_silv)
bysort d: egen double rmse_cv_g   = mean(sqerr_nwreg_cv)
bysort d: egen double rmse_ols_g  = mean(sqerr_ols)
bysort d: gen double rmse_silv_sqrt = sqrt(rmse_silv_g)
bysort d: gen double rmse_cv_sqrt   = sqrt(rmse_cv_g)
bysort d: gen double rmse_ols_sqrt  = sqrt(rmse_ols_g)

display as text _n "  nwreg (silverman):"
tabulate d, summarize(rmse_silv_sqrt)

display as text _n "  nwreg (cv):"
tabulate d, summarize(rmse_cv_sqrt)

display as text _n "  OLS (interacted):"
tabulate d, summarize(rmse_ols_sqrt)
