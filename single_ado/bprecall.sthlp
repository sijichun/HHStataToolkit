{smcl}
{* *! bprecall 1.0.0  08may2026}{...}
{viewerjumpto "Syntax" "bprecall##syntax"}{...}
{viewerjumpto "Description" "bprecall##description"}{...}
{viewerjumpto "Options" "bprecall##options"}{...}
{viewerjumpto "Stored results" "bprecall##results"}{...}
{viewerjumpto "Examples" "bprecall##examples"}{...}
{viewerjumpto "Also see" "bprecall##alsosee"}{...}

{title:Title}

{phang}
{bf:bprecall} {hline 2} Precision, recall, accuracy, and F1 score at multiple classification thresholds

{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:bprecall} {it:depvar} {it:probvar} {ifin}
[{cmd:,} {it:options}]

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt div:ide(#)}}number of threshold grid points; default is {cmd:divide(9)}{p_end}
{synoptline}
{p2colreset}{...}

{p 4 6 2}
{it:depvar} must be a binary (0/1) outcome variable.{p_end}
{p 4 6 2}
{it:probvar} must contain predicted probabilities in [0, 1].{p_end}


{marker description}{...}
{title:Description}

{pstd}
{cmd:bprecall} evaluates binary classification performance across a grid of
decision thresholds. For each threshold {it:c}, a predicted label of 1 is
assigned when {it:probvar} > {it:c}; otherwise 0. The command then computes:

{phang2}{bf:Precision} = TP / (TP + FP){p_end}
{phang2}{bf:Recall}    = TP / (TP + FN){p_end}
{phang2}{bf:Accuracy}  = (TP + TN) / (TP + FP + TN + FN){p_end}
{phang2}{bf:F1}        = 2 * Precision * Recall / (Precision + Recall){p_end}

{pstd}
where TP = true positives, FP = false positives, TN = true negatives, and
FN = false negatives.

{pstd}
Thresholds are evenly spaced between 0 and 1, excluding the endpoints.
With {cmd:divide(}{it:k}{cmd:)}, the {it:i}-th threshold is
{it:c_i} = {it:i} / ({it:k} + 1) for {it:i} = 1, ..., {it:k}.
The default of {cmd:divide(9)} produces thresholds 0.1, 0.2, ..., 0.9.

{pstd}
Metrics are set to missing (.) for any threshold where the denominator
is zero (e.g., no positive predictions for precision).

{pstd}
Results are returned in {cmd:r(results)}, a matrix with one row per
threshold and columns {it:threshold}, {it:precision}, {it:recall},
{it:accuracy}, and {it:f1}.


{marker options}{...}
{title:Options}

{phang}
{opt divide(#)} specifies the number of evenly-spaced threshold grid points.
Must be a positive integer. Default is 9, giving thresholds 0.1 through 0.9.
For a finer grid use, e.g., {cmd:divide(19)} (thresholds 0.05, 0.10, ..., 0.95).


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:bprecall} stores the following in {cmd:r()}:

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars}{p_end}
{synopt:{cmd:r(divide)}}value of the {cmd:divide()} option{p_end}

{p2col 5 20 24 2: Matrices}{p_end}
{synopt:{cmd:r(results)}}({it:divide} x 5) matrix: threshold, precision,
recall, accuracy, f1{p_end}
{p2colreset}{...}


{marker examples}{...}
{title:Examples}

{pstd}Setup: simulate a dataset with a binary outcome and predicted probabilities{p_end}

{phang2}{cmd:. clear}{p_end}
{phang2}{cmd:. set obs 500}{p_end}
{phang2}{cmd:. set seed 42}{p_end}
{phang2}{cmd:. gen x = rnormal()}{p_end}
{phang2}{cmd:. gen y = (x + rnormal() > 0)}{p_end}
{phang2}{cmd:. logit y x}{p_end}
{phang2}{cmd:. predict phat}{p_end}

{pstd}Evaluate at default 9 thresholds (0.1, 0.2, ..., 0.9){p_end}

{phang2}{cmd:. bprecall y phat}{p_end}

{pstd}Use a finer grid of 19 thresholds{p_end}

{phang2}{cmd:. bprecall y phat, divide(19)}{p_end}

{pstd}Restrict evaluation to a subsample{p_end}

{phang2}{cmd:. bprecall y phat if x > 0}{p_end}

{pstd}Access the results matrix after running{p_end}

{phang2}{cmd:. bprecall y phat}{p_end}
{phang2}{cmd:. matrix list r(results)}{p_end}


{marker alsosee}{...}
{title:Also see}

{psee}
Manual: {manlink R logit}, {manlink R probit}

{psee}
{helpb predict}, {helpb roc}, {helpb lroc}
{p_end}
