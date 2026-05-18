{smcl}
{* *! version 1.0.0  15may2026}{...}
{cmd:help xpofangorn}{right: ({stata "viewsource xpofangorn/xpofangorn.ado":view source})}
{hline}

{title:Title}

{p2colset 5 18 20 2}{...}
{p2col :{hi:xpofangorn} {hline 2}}Partially linear model via double machine learning{p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:xpofangorn} {it:depvar treatvar indepvars} [{cmd:,} {it:options}]

{synoptset 30 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Main}
{synopt :{opt generate(prefix)}}save residuals as {it:prefix}_ey and {it:prefix}_ew{p_end}
{synopt :{opt kfold(#)}}number of cross-fitting folds; default is 5{p_end}
{synopt :{opt type(string)}}force w model type: {cmd:classify} or {cmd:regress}; default is auto-detect{p_end}
{synopt :{opt vce(string)}}variance estimator: {cmd:robust} (default) or {cmd:cluster(varname)}{p_end}
{synoptline}
{syntab:Fangorn Options}
{synopt :{opt ntree(#)}}number of trees; default is 1 (single tree; use 100+ for DML){p_end}
{synopt :{opt maxdepth(#)}}maximum tree depth; default is 20{p_end}
{synopt :{opt entcvdepth(#)}}CV folds for depth selection; default is 10 (0 to disable){p_end}
{synopt :{opt minsamplessplit(#)}}minimum samples to split a node; default is 2{p_end}
{synopt :{opt minsamplesleaf(#)}}minimum samples in any leaf; default is 1{p_end}
{synopt :{opt minimpuritydecrease(#)}}min impurity decrease (absolute); default is 0{p_end}
{synopt :{opt relimpdec(#)}}relative min impurity decrease factor; default is 0 (disabled){p_end}
{synopt :{opt maxleafnodes(#)}}maximum number of leaf nodes; default is unlimited{p_end}
{synopt :{opt criterion(string)}}split criterion for w model: {cmd:gini}, {cmd:entropy}, {cmd:mse}{p_end}
{synopt :{opt mtry(#)}}features sampled per split; default is -1 (auto){p_end}
{synopt :{opt ntiles(#)}}quantile candidate thresholds; 0=all unique values (default){p_end}
{synopt :{opt seed(#)}}random seed; default is 12345{p_end}
{synopt :{opt nproc(#)}}OpenMP threads; default is 16{p_end}
{synopt :{opt if(exp)}}observations to include (use parentheses){p_end}
{synopt :{opt in(string)}}observation range to include{p_end}
{synoptline}
{p2colreset}{...}

{marker description}{...}
{title:Description}

{pstd}{cmd:xpofangorn} estimates the treatment effect {cmd:beta} in a partially
linear model:{p_end}

{p 8 12 2}
{p 4 12 2}{it:y_i = beta w_i + g(x_i) + u_i}{p_end}

{pstd}using the double machine learning (DML) approach of Chernozhukov et al.
(2018).  The method uses {hi:K-fold cross-fitting} to avoid overfitting bias:{p_end}

{pstd}1. Randomly split the data into {it:K} folds (order is restored afterwards).{p_end}
{pstd}2. For each fold {it:k}:{p_end}
{pmore}
{phang2}a. Train {cmd:fangorn} to estimate E[{it:y}|{it:X}] on the {it:K-1}
training folds; predict on the held-out fold {it:k} to obtain residual
{it:e_y = y - E[y|X]}.{p_end}
{phang2}b. Train {cmd:fangorn} to estimate E[{it:w}|{it:X}] on the {it:K-1}
training folds; predict on the held-out fold {it:k} to obtain residual
{it:e_w = w - E[w|X]}.{p_end}
{p_end}
{pstd}3. After all {it:K} folds, regress {it:e_y} on {it:e_w} to obtain
the treatment effect {cmd:beta}.{p_end}

{pstd}The nuisance functions E[{it:y}|{it:X}] and E[{it:w}|{it:X}] are estimated
using {cmd:fangorn} (CART / random forest).  E[{it:y}|{it:X}] always uses
regression ({cmd:type(regress)}).  The model for E[{it:w}|{it:X}] is
auto-detected: if {it:w} is a 0/1 binary variable, classification is used;
otherwise regression.  Override with the {cmd:type()} option.{p_end}

{marker options}{...}
{title:Options}

{phang}{opt generate(prefix)}: saves the cross-fitted residuals as
{it:prefix}_ey (residual of y) and {it:prefix}_ew (residual of w).  Useful for
diagnostics and manual analysis.  Optional; residuals are always computed
internally but only saved to the dataset when this option is specified.{p_end}

{phang}{opt kfold(#)}: number of cross-fitting folds.  Default is 5.
Larger values (e.g. 10) reduce bias but increase computation time.  Must be
at least 2 and less than the number of observations.{p_end}

{phang}{opt type(string)}: force the type for the E[{it:w}|{it:X}] model.
{cmd:classify} uses Gini/Entropy splitting (for binary treatment variables).
{cmd:regress} uses MSE splitting (for continuous treatment variables).
If not specified, type is auto-detected from the values of {it:w}.{p_end}

{phang}{opt vce(string)}: variance estimator for the final linear regression.
{cmd:robust} (default) gives heteroskedasticity-robust standard errors.
{cmd:cluster(varname)} gives cluster-robust standard errors (e.g.
{cmd:vce(cluster city_id)}).{p_end}

{phang}{opt ntree(#)}: number of trees for {cmd:fangorn}.  Default is 1
(single tree).  For DML, we recommend at least 100 trees for stable
predictions.  See {cmd:help fangorn} for details.{p_end}

{phang}{opt maxdepth(#)}: maximum tree depth for {cmd:fangorn}.  Default is
20.  Deeper trees capture more complex non-linearities but may overfit.
Cross-validation via {cmd:entcvdepth()} can help select optimal depth.{p_end}

{phang}{opt entcvdepth(#)}: number of cross-validation folds for depth
selection in {cmd:fangorn}.  Default is 10.  Set to 0 or 1 to disable.{p_end}

{phang}{opt criterion(string)}: split criterion for the E[{it:w}|{it:X}]
model.  {cmd:gini} (default for classification), {cmd:entropy}, or
{cmd:mse} (default for regression).  The E[{it:y}|{it:X}] model always uses
{cmd:mse}.{p_end}

{phang}{opt seed(#)}: random seed for reproducibility.  Controls both the
fold assignment and {cmd:fangorn}'s internal randomness.  Default is 12345.{p_end}

{phang}{opt nproc(#)}: number of OpenMP threads for {cmd:fangorn}'s CPU
parallelism.  Default is 16.  Overridden by
{envvar:OMP_NUM_THREADS}.{p_end}

{phang}{opt if(exp)}: Stata {cmd:if} qualifier as an option, using
parentheses: {cmd:if(condition)}.{p_end}

{phang}{opt in(range)}: Stata {cmd:in} qualifier as an option.{p_end}

{marker stored_results}{...}
{title:Stored Results}

{pstd}{cmd:xpofangorn} stores the following in {cmd:r()}:

{p 12 24 2}
{cmd:r(N)}        number of observations used in the final regression{p_end}
{cmd:r(kfold)}    number of cross-fitting folds used{p_end}
{cmd:r(beta)}     estimated treatment effect{p_end}
{cmd:r(se)}       standard error of the treatment effect{p_end}
{cmd:r(t)}        t-statistic for beta = 0{p_end}
{cmd:r(p)}        p-value for beta = 0{p_end}
{cmd:r(depvar)}   name of the outcome variable{p_end}
{cmd:r(treatvar)} name of the treatment variable{p_end}
{cmd:r(w_type)}   model type used for w (classify or regress){p_end}
{cmd:r(vce)}      variance estimator used{p_end}

{pstd}Additionally, the final linear regression results are stored in
{cmd:e()} by Stata's {cmd:regress} command, so {cmd:ereturn list} shows the
full regression output.{p_end}

{marker examples}{...}
{title:Examples}

{phang2}. {cmd:xpofangorn y w x1 x2 x3}{p_end}
Default DML with 5-fold cross-fitting, auto-detected w type.

{phang2}. {cmd:xpofangorn y w x1 x2 x3, kfold(10) seed(42)}{p_end}
10-fold cross-fitting with explicit seed.

{phang2}. {cmd:xpofangorn y w x1 x2 x3, type(classify) ntree(100) maxdepth(10)}{p_end}
DML with random forest (100 trees) for a binary treatment, max depth 10.

{phang2}. {cmd:xpofangorn y w x1 x2 x3, generate(res) vce(cluster city)}{p_end}
DML with cluster-robust standard errors; residuals saved as res_ey, res_ew.

{phang2}. {cmd:xpofangorn y w x1 x2 x3, ntree(200) entcvdepth(5) seed(777)}{p_end}
Random forest with 200 trees and 5-fold CV for depth selection.

{phang2}. {cmd:xpofangorn y w x1 x2 x3, kfold(2) type(regress) ntree(50)}{p_end}
2-fold cross-fitting (minimum), forcing regression for w.

{marker references}{...}
{title:References}

{pstd}Chernozhukov, V., Chetverikov, D., Demirer, M., Duflo, E., Hansen, C.,
Newey, W., & Robins, J. (2018). Double/debiased machine learning for treatment
and structural parameters. {it:The Econometrics Journal}, 21(1), C1-C68.{p_end}

{pstd}Breiman, L. (2001). Random forests. {it:Machine Learning}, 45(1), 5-32.{p_end}

{marker seealso}{...}
{title:Also See}

{p 4 14 2}{cmd:help fangorn}{p_end}
{cmd:help kdensity2}{p_end}
{cmd:help nwreg}{p_end}
