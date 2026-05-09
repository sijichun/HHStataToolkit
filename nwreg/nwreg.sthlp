{smcl}
{* *! version 1.0.0  08may2026}{...}
{cmd:help nwreg}{right: ({stata "viewsource nwreg/nwreg.ado":view source})}
{hline}

{title:Title}

{p2colset 5 18 20 2}{...}
{p2col :{hi:nwreg} {hline 2}}Nadaraya-Watson kernel regression with target split and group support{p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:nwreg} {it:depvar indepvars} [{cmd:,} {it:options}]

{synoptset 25 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Main}
{synopt :{opt kernel(kernel_name)}}kernel function; default is {cmd:gaussian}{p_end}
{synopt :{opt bw(bandwidth)}}bandwidth selection; default is {cmd:silverman}{p_end}
{synopt :{opt target(varname)}}0/1 variable: 0=training, 1=test{p_end}
{synopt :{opt group(varlist)}}one or more grouping variables{p_end}
{synopt :{opt mincount(#)}}skip groups with fewer than # observations{p_end}
{synopt :{opt folds(#)}}CV folds (used with {cmd:bw(cv)}); default is 10{p_end}
{synopt :{opt grids(#)}}CV grid candidates per side; default is 10{p_end}
{synopt :{opt gen:erate(newvar)}}output variable; default is {cmd:nwreg}{p_end}
{synopt :{opt se(newvar)}}standard error variable; if specified, computes a heteroskedasticity-robust local standard error for each prediction{p_end}
{synopt :{opt setype(#)}}SE computation method: 0=full-sample, 1=leave-one-out, 2=leverage-corrected (default){p_end}
{synopt :{opt if(exp)}}observations to include (use parentheses){p_end}
{synoptline}
{p2colreset}{...}

{marker description}{...}
{title:Description}

{pstd}{cmd:nwreg} performs Nadaraya-Watson kernel regression.  It estimates
E[Y|X] at each observation using kernel-weighted local averaging.  Supports
target split (target=0 trains, all get predictions), grouped estimation with
one or more categorical variables, and minimum group size filtering.
Cross-validation bandwidth selection is available via {cmd:bw(cv)} with
customizable folds and grid density.

{marker options}{...}
{title:Options}

{phang}{opt kernel(kernel_name)}: {cmd:gaussian}, {cmd:epanechnikov},
{cmd:uniform}, {cmd:triweight}, {cmd:cosine}. Default {cmd:gaussian}.

{phang}{opt bw(bandwidth)}: {cmd:silverman}, {cmd:scott}, {cmd:cv}, or a
positive number.  Default {cmd:silverman}.  {cmd:cv} selects bandwidth by
K-fold cross-validation minimizing mean squared prediction error.

{phang}{opt target(varname)}: 0/1 variable; target=0 is training set.

{phang}{opt group(varlist)}: grouping variables for separate estimation.

{phang}{opt mincount(#)}: skip groups with fewer than # observations.

{phang}{opt folds(#)}: number of CV folds when {cmd:bw(cv)} is specified.
Default is 10.  Minimum is 2.

{phang}{opt grids(#)}: number of grid candidates on each side of the
reference bandwidth when {cmd:bw(cv)} is specified.  Total candidates =
{cmd:grids} {cmd:* 2 + 1}.  Default is 10 (=21 candidates).  The grid is
log-spaced with step 0.05.

{phang}{opt generate(newvar)}: output variable name.

{phang}{opt se(newvar)}: if specified, computes a heteroskedasticity-robust
local standard error for each prediction and stores it in {it:newvar}.  The
standard error is based on local weighted squared residuals from the training
set and is computed for both target=0 (training) and target=1 (test)
observations.

{phang}{opt se_type(#)}: method for computing residuals used in the standard
error formula.  {cmd:0} uses full-sample fitted values (fastest, slight finite-
sample downward bias).  {cmd:1} uses leave-one-out fitted values (most accurate,
about 2x compute).  {cmd:2} applies a leverage correction (HC3-style) to full-
sample residuals (recommended default: nearly unbiased with minimal overhead).

{phang}{opt if(exp)}: use {cmd:if(exp)} syntax (not Stata qualifier) to avoid
a Stata 18 parsing bug.

{marker examples}{...}
{title:Examples}

{phang2}{cmd:. nwreg y x}{p_end}
{phang2}{cmd:. nwreg y x, bw(cv)}{p_end}
{phang2}{cmd:. nwreg y x1 x2, bw(cv) folds(5) grids(15)}{p_end}
{phang2}{cmd:. nwreg y x, generate(yhat) if(flag==1)}{p_end}
{phang2}{cmd:. nwreg y x, group(g) mincount(50)}{p_end}
{phang2}{cmd:. nwreg y x1 x2, group(g1 g2) target(t)}{p_end}
{phang2}{cmd:. nwreg y x, generate(yhat) se(yhat_se)}{p_end}
{phang2}{cmd:. nwreg y x, target(t) generate(yhat) se(yhat_se)}{p_end}
{phang2}{cmd:. nwreg y x, generate(yhat) se(yhat_se) se_type(1)}{p_end}
{phang2}{cmd:. nwreg y x, generate(yhat) se(yhat_se) se_type(0)}{p_end}

{marker also_see}{...}
{title:Also see}
{psee}Online: {helpb npregress}, {helpb kdensity2}{p_end}
