{smcl}
{* *! version 2.3.0  07may2026}{...}
{cmd:help kdensity2}{right: ({stata "viewsource kdensity2/kdensity2.ado":view source})}
{hline}

{title:Title}

{p2colset 5 18 20 2}{...}
{p2col :{hi:kdensity2} {hline 2}}Kernel density estimation with target split and group support{p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:kdensity2} {it:varlist} [{cmd:,} {it:options}]

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
{synopt :{opt gen:erate(newvar)}}output variable; default is {cmd:kdensity2}{p_end}
{synopt :{opt if(exp)}}observations to include (use parentheses){p_end}
{synoptline}
{p2colreset}{...}

{marker description}{...}
{title:Description}

{pstd}{cmd:kdensity2} estimates kernel density at each observation.  Supports
target split (target=0 trains, all get density), grouped estimation with
one or more categorical variables, and minimum group size filtering.
Cross-validation bandwidth selection is available via {cmd:bw(cv)} with
customizable folds and grid density.

{marker options}{...}
{title:Options}

{phang}{opt kernel(kernel_name)}: {cmd:gaussian}, {cmd:epanechnikov},
{cmd:uniform}, {cmd:triweight}, {cmd:cosine}. Default {cmd:gaussian}.

{phang}{opt bw(bandwidth)}: {cmd:silverman}, {cmd:scott}, {cmd:cv}, or a
positive number.  Default {cmd:silverman}.  {cmd:cv} selects bandwidth by
K-fold likelihood cross-validation with a log-scale grid search.

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

{phang}{opt if(exp)}: use {cmd:if(exp)} syntax (not Stata qualifier) to avoid
a Stata 18 parsing bug.

{marker examples}{...}
{title:Examples}

{phang2}{cmd:. kdensity2 x}{p_end}
{phang2}{cmd:. kdensity2 x, bw(cv)}{p_end}
{phang2}{cmd:. kdensity2 x, bw(cv) folds(5) grids(15)}{p_end}
{phang2}{cmd:. kdensity2 x, generate(d) if(flag==1)}{p_end}
{phang2}{cmd:. kdensity2 x, group(g) mincount(50)}{p_end}
{phang2}{cmd:. kdensity2 x y, group(g1 g2) target(t)}{p_end}

{marker also_see}{...}
{title:Also see}
{psee}Online: {helpb kdensity}{p_end}
