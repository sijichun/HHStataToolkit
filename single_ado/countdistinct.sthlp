{smcl}
{* *! countdistinct 1.1.0  08may2026}{...}
{vieweralsosee "duplicates" "help duplicates"}{...}
{vieweralsosee "isid" "help isid"}{...}
{viewerjumpto "Syntax" "countdistinct##syntax"}{...}
{viewerjumpto "Description" "countdistinct##description"}{...}
{viewerjumpto "Options" "countdistinct##options"}{...}
{viewerjumpto "Stored results" "countdistinct##results"}{...}
{viewerjumpto "Examples" "countdistinct##examples"}{...}
{title:Title}

{phang}
{bf:countdistinct} {hline 2} Count distinct combinations of variables


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:countdistinct} {varlist} {ifin}
[{cmd:,} {it:options}]

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt gen:erate(newvar)}}create an indicator variable equal to 1 for the first occurrence of each distinct combination{p_end}
{synoptline}
{p2colreset}{...}


{marker description}{...}
{title:Description}

{pstd}
{cmd:countdistinct} counts the number of distinct combinations of the variables
in {varlist} within the current sample.  The result is displayed and stored as
{cmd:r(count)}.

{pstd}
A {it:combination} is considered distinct if the values of all listed variables
jointly differ from every other observation.  Observations excluded by {cmd:if}
or {cmd:in} are ignored.


{marker options}{...}
{title:Options}

{phang}
{opt generate(newvar)} creates a new byte variable {it:newvar} equal to 1 for
the first occurrence of each distinct combination (in sort order) and missing
for all other occurrences.  This mirrors the internal indicator used to count
distinct combinations.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:countdistinct} stores the following in {cmd:r()}:

{synoptset 15 tabbed}{...}
{p2col 5 15 19 2: Scalars}{p_end}
{synopt:{cmd:r(count)}}number of distinct combinations{p_end}
{p2colreset}{...}


{marker examples}{...}
{title:Examples}

{pstd}Count distinct values of a single variable:{p_end}
{phang2}{cmd:. countdistinct rep78}{p_end}

{pstd}Count distinct combinations of two variables:{p_end}
{phang2}{cmd:. countdistinct foreign rep78}{p_end}

{pstd}Count within a subset:{p_end}
{phang2}{cmd:. countdistinct rep78 if foreign == 1}{p_end}

{pstd}Save the first-occurrence indicator:{p_end}
{phang2}{cmd:. countdistinct foreign rep78, generate(first_combo)}{p_end}

{pstd}Use the stored result:{p_end}
{phang2}{cmd:. countdistinct foreign rep78}{p_end}
{phang2}{cmd:. display r(count)}{p_end}


{marker alsosee}{...}
{title:Also see}

{psee}
{helpb duplicates} {hline 2} report, tag, or drop duplicate observations{break}
{helpb isid} {hline 2} check whether variables uniquely identify observations{break}
{helpb bysort} {hline 2} sort and perform operations by group
{p_end}
