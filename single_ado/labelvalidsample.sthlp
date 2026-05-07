{smcl}
{* *! version 1.0.0  2026-05-08}{...}
{viewerjumpto "Syntax" "labelvalidsample##syntax"}{...}
{viewerjumpto "Description" "labelvalidsample##description"}{...}
{viewerjumpto "Options" "labelvalidsample##options"}{...}
{viewerjumpto "Examples" "labelvalidsample##examples"}{...}
{viewerjumpto "Also see" "labelvalidsample##alsosee"}{...}

{title:Title}

{phang}
{bf:labelvalidsample} {hline 2} Generate a complete-observation indicator variable


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:labelvalidsample} {varlist} {ifin}{cmd:,} {opt gen:erate(newvar)}


{marker description}{...}
{title:Description}

{pstd}
{cmd:labelvalidsample} creates a binary (0/1) variable that marks observations
which have non-missing values for {it:all} variables in {varlist}.  Observations
satisfying any {cmd:if}/{cmd:in} restriction {it:and} having no missing values
in {varlist} are coded 1; all other observations are coded 0.

{pstd}
This command is a data-cleaning utility for building analysis samples.  It is
equivalent to identifying "complete cases" across a set of variables.


{marker options}{...}
{title:Options}

{phang}
{opt gen:erate(newvar)} specifies the name of the new binary indicator variable
to be created.  {it:newvar} must not already exist in the dataset.  This option
is required.


{marker examples}{...}
{title:Examples}

{pstd}Mark observations complete across three variables:{p_end}
{phang2}{cmd:. labelvalidsample age income educ, generate(insample)}{p_end}

{pstd}Restrict the eligible population before marking:{p_end}
{phang2}{cmd:. labelvalidsample wage hours tenure if female == 1, generate(valid)}{p_end}

{pstd}Use the resulting indicator to restrict subsequent analysis:{p_end}
{phang2}{cmd:. labelvalidsample mpg weight foreign, generate(complete)}{p_end}
{phang2}{cmd:. summarize mpg weight foreign if complete}{p_end}

{pstd}Count complete observations:{p_end}
{phang2}{cmd:. labelvalidsample y x1 x2 x3, generate(ok)}{p_end}
{phang2}{cmd:. count if ok}{p_end}


{marker alsosee}{...}
{title:Also see}

{psee}
Stata manual: {helpb mark}, {helpb markout}, {helpb marksample},
{helpb misstable}, {helpb egen}
{p_end}
