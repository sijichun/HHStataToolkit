{smcl}
{* *! csadensity 1.0.0  10may2026}{...}
{vieweralsosee "kdensity2" "help kdensity2"}{...}
{viewerjumpto "Syntax" "csadensity##syntax"}{...}
{viewerjumpto "Description" "csadensity##description"}{...}
{viewerjumpto "Options" "csadensity##options"}{...}
{viewerjumpto "Stored results" "csadensity##results"}{...}
{viewerjumpto "Examples" "csadensity##examples"}{...}
{title:Title}

{phang}
{bf:csadensity} {hline 2} Identify common support area between treatment and control groups


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:csadensity} {varlist} {ifin}
{cmd:,} {opt treat:ment(varname)} {opt gen:erate(newvar)} [{it:options}]

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt treat:ment(varname)}}binary treatment indicator (0 = control, 1 = treatment){p_end}
{synopt:{opt gen:erate(newvar)}}create a new byte variable marking common support area{p_end}
{syntab:Optional}
{synopt:{opt thres:hold(#)}}density threshold for common support (default 0.2); compared against the normalized minimum density{p_end}
{synopt:{opt group(varlist)}}group variables for within-group CSA estimation; string group variables are auto-encoded to numeric{p_end}
{synopt:{opt kernel(kernel)}}kernel function (default {cmd:triweight}); see {helpb kdensity2}{p_end}
{synopt:{opt bw(bw)}}bandwidth selector (default {cmd:silverman}); see {helpb kdensity2}{p_end}
{synopt:{opt debug}}keep intermediate variables {it:_csad_f_t}, {it:_csad_f_nt}, {it:_csad_f_geom}, {it:_csad_f_norm} in the dataset for inspection{p_end}
{synoptline}
{p2colreset}{...}


{marker description}{...}
{title:Description}

{pstd}
{cmd:csadensity} identifies observations that lie in the common support area (CSA)
between a treatment group and a control group.  For each observation,
the command computes kernel density estimates under both the treatment
and control distributions, takes the pointwise minimum of the two densities,
normalises by the maximum, and marks the observation as being in the common
support area if the normalised minimum exceeds a user-specified threshold
and is non-missing.

{pstd}
Formally, for a D-dimensional covariate vector {bf:x}:

{p 8 8 2}
f_t({bf:x}) = KDE of {bf:x} using only treatment observations

{p 8 8 2}
f_c({bf:x}) = KDE of {bf:x} using only control observations

{p 8 8 2}
g({bf:x}) = min(f_t({bf:x}), f_c({bf:x}))

{p 8 8 2}
{bf:g_norm}({bf:x}) = g({bf:x}) / max(g)

{pstd}
An observation is assigned {cmd:generate} = 1 if {bf:g_norm} > threshold and
{bf:g_norm} is non-missing, and 0 otherwise.

{pstd}
When the {cmd:group()} option is specified, the CSA is computed separately
within each group, allowing for group-specific bandwidths and density
estimates.

{pstd}
All variables in {it:varlist} must be numeric.  String variables in the
{cmd:group()} option are automatically encoded using {cmd:egen group()},
matching the behaviour of {helpb kdensity2}.


{marker options}{...}
{title:Options}

{phang}
{opt treatment(varname)} specifies the binary treatment indicator.
Must contain exactly two distinct values: 0 (control) and 1 (treatment).
This option is required.

{phang}
{opt generate(newvar)} creates a new byte variable {it:newvar} equal to 1
for observations inside the common support area and 0 for those outside.
Observations with missing density estimates or excluded by {cmd:if} or
{cmd:in} are set to missing.  This option is required.

{phang}
{opt threshold(#)} sets the cutoff for the normalised minimum density.
{bf:g_norm} is scaled to [0, 1], so threshold is interpreted relative to the
maximum observed density.  Higher values yield a smaller common support area.
The default is 0.2.

{phang}
{opt group(varlist)} specifies group variables for within-group CSA
estimation.  Passthrough to {helpb kdensity2}.  String group variables
are automatically encoded to numeric.

{phang}
{opt kernel(kernel)} passes the kernel specification to {helpb kdensity2}.
Valid choices are {cmd:gaussian}, {cmd:epanechnikov}, {cmd:uniform},
{cmd:triweight}, and {cmd:cosine}.  The default is {cmd:triweight}.

{phang}
{opt bw(bw)} passes the bandwidth selector to {helpb kdensity2}.
Valid choices are {cmd:silverman}, {cmd:scott}, {cmd:cv}, or a positive
number.  The default is {cmd:silverman}.

{phang}
{opt debug} preserves the intermediate variables used in the CSA computation:
{cmd:_csad_f_t} (density under treatment), {cmd:_csad_f_nt} (density under
control), {cmd:_csad_f_geom} (pointwise minimum density), and
{cmd:_csad_f_norm} (normalised minimum density).  These are normally
cleaned up automatically.


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:csadensity} stores the following in {cmd:r()}:

{synoptset 15 tabbed}{...}
{p2col 5 15 19 2: Scalars}{p_end}
{synopt:{cmd:r(N)}}total number of observations used{p_end}
{synopt:{cmd:r(N_csa)}}number of observations in common support area{p_end}
{synopt:{cmd:r(threshold)}}threshold used{p_end}
{p2colreset}{...}

{synoptset 15 tabbed}{...}
{p2col 5 15 19 2: Macros}{p_end}
{synopt:{cmd:r(treatment)}}name of treatment variable{p_end}
{synopt:{cmd:r(varlist)}}covariate list{p_end}
{synopt:{cmd:r(groupvars)}}group variables (if specified){p_end}
{synopt:{cmd:r(kernel)}}kernel used{p_end}
{synopt:{cmd:r(bw)}}bandwidth selector used{p_end}
{p2colreset}{...}


{marker examples}{...}
{title:Examples}

{pstd}Basic usage with two continuous covariates:{p_end}
{phang2}{cmd:. csadensity x1 x2, treatment(d) generate(csa)}{p_end}

{pstd}With a stricter threshold:{p_end}
{phang2}{cmd:. csadensity x1 x2, treatment(d) generate(csa) threshold(0.10)}{p_end}

{pstd}With within-group CSA estimation:{p_end}
{phang2}{cmd:. csadensity x1 x2, treatment(d) generate(csa) group(region)}{p_end}

{pstd}Custom kernel and bandwidth:{p_end}
{phang2}{cmd:. csadensity x1 x2, treatment(d) generate(csa) kernel(epanechnikov) bw(scott)}{p_end}

{pstd}Inspect intermediate variables:{p_end}
{phang2}{cmd:. csadensity x1 x2, treatment(d) generate(csa) debug}{p_end}
{phang2}{cmd:. summarize _csad_f_t _csad_f_nt _csad_f_norm}{p_end}


{marker alsosee}{...}
{title:Also see}

{psee}
{helpb kdensity2} {hline 2} kernel density estimation (used internally){p_end}
