{smcl}
{* *! version 1.2.0  2026-03-11}{...}
{vieweralsosee "[D] describe" "help describe"}{...}
{vieweralsosee "[D] codebook" "help codebook"}{...}
{viewerjumpto "Syntax" "dta2md##syntax"}{...}
{viewerjumpto "Description" "dta2md##description"}{...}
{viewerjumpto "Options" "dta2md##options"}{...}
{viewerjumpto "Output format" "dta2md##output"}{...}
{viewerjumpto "Examples" "dta2md##examples"}{...}
{viewerjumpto "Author" "dta2md##author"}{...}
{title:Title}

{phang}
{bf:dta2md} {hline 2} Export .dta metadata and descriptive statistics to Markdown


{marker syntax}{...}
{title:Syntax}

{p 8 16 2}
{cmd:dta2md}
{it:"filepath.dta"}
[{cmd:using} {it:"outputfile.md"}]
[{cmd:,} {it:options}]

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{synopt:{opt des:criptive}}output per-variable details including frequency
tables and descriptive statistics{p_end}
{synopt:{opt var:list(varlist)}}specify variables to export; default is all variables{p_end}
{synopt:{opt lab:eled}}export only variables that have variable labels{p_end}
{synopt:{opt maxcat(#)}}maximum number of unique values for frequency table;
default is {cmd:maxcat(20)}{p_end}
{synopt:{opt maxfreq(#)}}maximum rows displayed in frequency table;
default is {cmd:maxfreq(30)}{p_end}
{synopt:{opt eng:lish}}output English titles instead of Chinese titles{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:dta2md} reads a Stata {cmd:.dta} file and exports its metadata and
descriptive statistics to a Markdown ({cmd:.md}) file.

{pstd}
By default, the output file is saved in the same directory as the input
file with the suffix {cmd:_metadata.md}. Use {cmd:using} to specify a
custom output path. The output file is always overwritten if it already
exists.

{pstd}
The Markdown output is designed to be read and understood by large language
models (LLMs) such as GPT, Claude, etc. It contains structured information
that enables an LLM to understand the dataset without directly reading the
binary {cmd:.dta} file.

{pstd}
The command uses a temporary {help frame} to load the data, so it does
{bf:not} disturb the data currently in memory.

{pstd}
The output Markdown file contains the following sections:

{phang2}1. {bf:数据集概览 (Dataset Overview)}: dataset label, number of
observations and variables, panel/time-series structure if set via
{cmd:xtset}/{cmd:tsset}.{p_end}

{phang2}2. {bf:变量清单 (Variable List)}: a table listing all variables with
their storage type and variable label.{p_end}

{phang2}3. {bf:变量详情 (Variable Details)}: per-variable information
(included when {opt descriptive} is specified):{p_end}

{phang3}(a) {it:Labeled numeric variables} with unique values {ul:<}=
{opt maxcat()}: frequency table showing numeric value, value label, count,
and percentage.{p_end}

{phang3}(b) {it:Unlabeled numeric variables} or labeled numeric with unique
values > {opt maxcat()}: descriptive statistics (N, mean, SD, min, max).
If the variable range includes negative values, the proportion < 0 is
also reported.{p_end}

{phang3}(c) {it:String variables} with unique values {ul:<}= {opt maxcat()}:
frequency table of string values with count and percentage.{p_end}

{phang3}(d) {it:String variables} with unique values > {opt maxcat()}:
only the count of unique values and missing values is reported.{p_end}


{marker options}{...}
{title:Options}

{phang}
{cmd:using} {it:"outputfile.md"} specifies the output file path. If not
specified, the output file is saved in the same directory as the input
{cmd:.dta} file, with the filename {it:basename}{cmd:_metadata.md}.
The output file is always overwritten if it already exists.

{phang}
{opt descriptive} requests per-variable details including frequency tables
and descriptive statistics. By default, only the dataset overview and
variable list table are output. This option is useful when detailed
statistics are needed.

{phang}
{opt var:list(varlist)} specifies which variables to export. Variable names
should be separated by spaces. If not specified, all variables in the dataset
are exported. This option is useful for exporting metadata for a subset of
variables of interest.

{phang}
{opt lab:eled} requests that only variables with variable labels be exported.
Variables without labels are skipped. This is useful for datasets where only
labeled variables are meaningful (e.g., survey data where unlabeled variables
are temporary or intermediate). This filter is applied after {opt varlist()}
if both are specified.

{phang}
{opt maxcat(#)} specifies the maximum number of unique values a variable
can have to be displayed as a frequency table. Variables with more unique
values are shown as descriptive statistics (numeric) or summary counts
(string). The default is {cmd:maxcat(20)}. Ignored when {opt descriptive}
is not specified.

{phang}
{opt maxfreq(#)} specifies the maximum number of rows displayed in any
frequency table. The default is {cmd:maxfreq(30)}. This serves as a safety
limit for variables with many categories. Ignored when {opt descriptive}
is not specified.

{phang}
{opt eng:lish} outputs English titles and labels in the Markdown file.
By default (when this option is not specified), the output uses Chinese titles
(e.g., "数据集概览" instead of "Dataset Overview", "变量清单" instead of 
"Variable List", etc.). This option is useful for generating reports in English.


{marker output}{...}
{title:Output format}

{pstd}
The output file is a UTF-8 encoded Markdown file using GitHub-Flavored
Markdown (GFM) tables.

{pstd}
Default output path (without {cmd:using}):

{phang2}{cmd:mydata.dta} -> {cmd:mydata_metadata.md} (same directory){p_end}

{pstd}
Custom output path (with {cmd:using}):

{phang2}{cmd:dta2md "mydata.dta" using "D:/output/report.md"}{p_end}

{pstd}
The file is always overwritten if it already exists.


{marker examples}{...}
{title:Examples}

    {hline}
    {pstd}Basic usage — export overview and variable list only{p_end}

{phang}{cmd:. dta2md "C:/data/survey2024.dta"}{p_end}
{pstd}Exports metadata to {cmd:C:/data/survey2024_metadata.md} with only
the dataset overview and variable list table.

    {hline}
    {pstd}Specify output file path{p_end}

{phang}{cmd:. dta2md "C:/data/survey2024.dta" using "D:/reports/survey_meta.md"}{p_end}
{pstd}Exports metadata to the specified path instead of the default.

    {hline}
    {pstd}Descriptive mode — include detailed statistics{p_end}

{phang}{cmd:. dta2md "C:/data/survey2024.dta", descriptive}{p_end}
{pstd}Outputs the dataset overview, variable list table, and per-variable
frequency tables and descriptive statistics, using default thresholds
(maxcat=20, maxfreq=30).

    {hline}
    {pstd}Custom thresholds with descriptive mode{p_end}

{phang}{cmd:. dta2md "~/research/panel.dta", descriptive maxcat(50)}{p_end}
{pstd}Variables with up to 50 unique values will display frequency tables.

{phang}{cmd:. dta2md "D:/project/census.dta", descriptive maxcat(10) maxfreq(15)}{p_end}
{pstd}Only variables with {ul:<}= 10 unique values get frequency tables,
and tables are limited to 15 rows.

    {hline}
    {pstd}Combine all options{p_end}

{phang}{cmd:. dta2md "data.dta" using "out.md"}{p_end}
{pstd}Simple mode with custom output path.

{phang}{cmd:. dta2md "data.dta" using "out.md", descriptive maxcat(50) maxfreq(20)}{p_end}
{pstd}Full details with custom output path and thresholds.

    {hline}
    {pstd}English titles{p_end}

{phang}{cmd:. dta2md "data.dta", descriptive english}{p_end}
{pstd}Output with English section titles and labels, including descriptive statistics.

    {hline}
    {pstd}Export specific variables only{p_end}

{phang}{cmd:. dta2md "survey.dta", varlist(age income education)}{p_end}
{pstd}Exports metadata for only the three specified variables.

{phang}{cmd:. dta2md "survey.dta", descriptive varlist(age income gender)}{p_end}
{pstd}Exports descriptive statistics for the specified variables.

    {hline}
    {pstd}Export only labeled variables{p_end}

{phang}{cmd:. dta2md "survey.dta", labeled}{p_end}
{pstd}Exports only variables that have variable labels, skipping unlabeled ones.

{phang}{cmd:. dta2md "survey.dta", descriptive labeled}{p_end}
{pstd}Exports descriptive statistics for labeled variables only.

    {hline}
    {pstd}Combine varlist and labeled options{p_end}

{phang}{cmd:. dta2md "survey.dta", varlist(age income temp1 temp2) labeled}{p_end}
{pstd}From the four specified variables, only those with labels are exported.

    {hline}
    {pstd}Quick test with built-in data{p_end}

{phang}{cmd:. sysuse auto, clear}{p_end}
{phang}{cmd:. save "auto.dta", replace}{p_end}
{phang}{cmd:. dta2md "auto.dta"}{p_end}
{pstd}Quick test with the built-in {cmd:auto} dataset.


{marker author}{...}
{title:Author}

{pstd}
VibeStata project{p_end}

{pstd}
Requires Stata 16.0 or later.{p_end}
{smcl}
