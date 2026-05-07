{smcl}
{* gen_init_var.sthlp  2026-05-08}{...}
{vieweralsosee "" "--"}{...}
{vieweralsosee "egen" "help egen"}{...}
{vieweralsosee "xtset" "help xtset"}{...}
{hline}
help for {cmd:gen_init_var}
{hline}

{title:Title}

{phang}
{bf:gen_init_var} {hline 2} Initialize a panel variable from a base-year observation within groups


{title:Syntax}

{p 8 17 2}
{cmd:gen_init_var}
{varname}
{cmd:,}
{opth yearvar(varname)}
{opt year(value)}
{opth by(varname)}
{opt generate(newvar)}
[{opt stringyear}]


{title:Description}

{pstd}
{cmd:gen_init_var} is a panel-data utility that creates a new variable containing,
for every observation in a group, the value of {varname} recorded in a specified
base year.  This is useful when you need to attach initial (time-invariant)
conditions to all rows of a panel — for example, carrying a firm's founding-year
size to all subsequent years.

{pstd}
Internally the command finds observations where {opt yearvar()} equals {opt year()},
extracts {varname} for those rows, and then propagates (broadcasts) that value to
every observation sharing the same {opt by()} identifier via {cmd:egen … min()}.


{title:Options}

{phang}
{opth yearvar(varname)} specifies the variable that identifies the calendar year
(or any time period).  Required.

{phang}
{opt year(value)} specifies the base year from which {varname} is read.
Must be numeric unless {opt stringyear} is also specified.  Required.

{phang}
{opth by(varname)} specifies the panel identifier (e.g., firm ID, household ID).
The initial value is broadcast within each level of this variable.  Required.

{phang}
{opt generate(newvar)} specifies the name of the new variable to create.  Required.

{phang}
{opt stringyear} indicates that the year variable is stored as a string, so the
comparison {cmd:`yearvar' == "`year'"} is used instead of a numeric equality check.


{title:Saved results}

{pstd}
{cmd:gen_init_var} saves the following in {cmd:r()}:

{synoptset 20 tabbed}{...}
{synopt:{cmd:r(varname)}}name of the generated variable{p_end}
{synopt:{cmd:r(sourcevar)}}name of the source variable{p_end}
{synopt:{cmd:r(yearvar)}}name of the year variable{p_end}
{synopt:{cmd:r(year)}}base-year value used{p_end}
{synopt:{cmd:r(byvar)}}name of the group variable{p_end}


{title:Examples}

{pstd}
{bf:Example 1 — numeric year variable}

{phang2}{cmd:. use panel_firms.dta, clear}{p_end}
{phang2}{cmd:. gen_init_var sales, yearvar(year) year(2000) by(firmid) generate(sales0)}{p_end}

{pstd}
Creates {cmd:sales0} equal to each firm's year-2000 sales for all observations.

{pstd}
{bf:Example 2 — string year variable}

{phang2}{cmd:. gen_init_var revenue, yearvar(period) year(2010) by(id) generate(rev_init) stringyear}{p_end}

{pstd}
When {cmd:period} is stored as a string (e.g., "2010"), use {opt stringyear} so the
comparison is made with quoted equality.

{pstd}
{bf:Example 3 — recover generated variable name}

{phang2}{cmd:. gen_init_var emp, yearvar(yr) year(1995) by(cid) generate(emp_base)}{p_end}
{phang2}{cmd:. display r(varname)}{p_end}


{title:Remarks}

{pstd}
The command issues an error if no observations are found for the requested base year,
or if the output variable name already exists in the dataset.

{pstd}
Because {cmd:egen … min()} is used to broadcast the base-year value, the result is
well-defined only when {varname} takes a unique value per group in the base year.
If a group has multiple observations in the base year with different values, the
minimum is used; a warning is not issued.  Pre-filter your data if necessary.


{title:Also see}

{psee}
Online:  {helpb xtset}, {helpb egen}, {helpb generate}
{p_end}
