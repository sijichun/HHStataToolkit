{smcl}
{* *! gencatutility 1.1.0  2026-05-08}{...}
{vieweralsosee "" "--"}{...}
{vieweralsosee "[R] egen" "help egen"}{...}
{vieweralsosee "[R] levelsof" "help levelsof"}{...}
{viewerjumpto "Syntax" "gencatutility##syntax"}{...}
{viewerjumpto "Description" "gencatutility##description"}{...}
{viewerjumpto "Algorithm" "gencatutility##algorithm"}{...}
{viewerjumpto "Options" "gencatutility##options"}{...}
{viewerjumpto "Stored results" "gencatutility##results"}{...}
{viewerjumpto "Examples" "gencatutility##examples"}{...}
{viewerjumpto "Also see" "gencatutility##alsosee"}{...}
{hline}
{title:Title}

{phang}
{bf:gencatutility} {hline 2} Generate category utility scores for an ordered categorical variable

{hline}

{marker syntax}
{title:Syntax}

{p 8 17 2}
{cmdab:gencatutility} {varname}{cmd:,} {opt gen:erate(newvar)} [{opt display}]

{synoptset 20 tabbed}
{synopthdr}
{synoptline}
{synopt:{opt gen:erate(newvar)}}name of new variable to contain utility scores{p_end}
{synopt:{opt display}}print a table of level-to-utility mappings{p_end}
{synoptline}

{hline}

{marker description}
{title:Description}

{pstd}
{cmd:gencatutility} computes a continuous {it:category utility} score for each
level of an ordered categorical variable and stores those scores in a new
variable.  The resulting variable can replace discrete category codes with a
smooth, interval-scaled measure that preserves the ordinality of the original
categories while reflecting the relative frequency of each category.

{pstd}
The output variable is of type {bf:double} and contains one unique value per
level of {it:varname}.  Observations belonging to the same level receive the
same utility score.

{hline}

{marker algorithm}
{title:Algorithm}

{pstd}
Let there be {it:K} ordered levels with counts {it:n_1}, ..., {it:n_K} and
total {it:N} = sum({it:n_k}).  The algorithm proceeds as follows:

{phang2}
1. Compute cumulative proportions:
   {it:p_k} = (n_1 + ... + n_k) / N,  k = 1, ..., K.

{phang2}
2. Transform via the inverse standard-normal CDF:
   {it:z_k} = {bf:invnormal}({it:p_k}).
   By convention {it:phi}(z_K) = 0 when p_K = 1.

{phang2}
3. Evaluate the standard-normal PDF at each {it:z_k}:
   {it:f_k} = {bf:normalden}({it:z_k}, 0, 1).

{phang2}
4. Compute utility scores as first-differences of {it:f} divided by
   first-differences of {it:p}:

{p 12 12 2}
   u_1 = (0 - f_1) / p_1

{p 12 12 2}
   u_k = (f_{k-1} - f_k) / (p_k - p_{k-1}),  k = 2, ..., K.

{pstd}
This formula gives each category an interval-level score proportional to the
slope of the normal density function across its probability interval.

{hline}

{marker options}
{title:Options}

{phang}
{opt generate(newvar)} is required.  Specifies the name of the new variable
that will be created to hold the utility scores.  The variable must not already
exist.

{phang}
{opt display} prints a formatted table showing each category level and its
corresponding utility score.

{hline}

{marker results}
{title:Stored results}

{pstd}
{cmd:gencatutility} stores the following in {cmd:r()}:

{synoptset 20 tabbed}
{synopt:{cmd:r(n_levels)}}number of distinct levels{p_end}
{synopt:{cmd:r(n_obs)}}total number of non-missing observations used{p_end}
{synopt:{cmd:r(levels)}}space-separated list of levels{p_end}
{synopt:{cmd:r(varname)}}name of the source variable{p_end}
{synopt:{cmd:r(generate)}}name of the generated variable{p_end}
{synoptline}

{hline}

{marker examples}
{title:Examples}

{pstd}
{bf:Basic usage}

{phang2}
{cmd:. sysuse nlsw88, clear}{p_end}
{phang2}
{cmd:. gencatutility occupation, generate(occ_utility)}{p_end}

{pstd}
{bf:Display the level-to-utility mapping}

{phang2}
{cmd:. gencatutility occupation, generate(occ_utility) display}{p_end}

{pstd}
{bf:Use in a regression}

{phang2}
{cmd:. gencatutility grade, generate(grade_u)}{p_end}
{phang2}
{cmd:. regress wage grade_u tenure}{p_end}

{pstd}
{bf:Inspect returned values}

{phang2}
{cmd:. gencatutility industry, generate(ind_u)}{p_end}
{phang2}
{cmd:. return list}{p_end}

{hline}

{marker alsosee}
{title:Also see}

{psee}
Manual: {bf:[R] egen}, {bf:[R] levelsof}

{psee}
Online: {helpb egen}, {helpb levelsof}
{p_end}
