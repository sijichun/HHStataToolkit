{smcl}
{* *! version 1.0.0  09may2026}{...}
{cmd:help fangorn}{right: ({stata "viewsource fangorn/fangorn.ado":view source})}
{hline}

{title:Title}

{p2colset 5 18 20 2}{...}
{p2col :{hi:fangorn} {hline 2}}Decision tree and random forest (classification & regression){p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:fangorn} {it:depvar indepvars} [{cmd:,} {it:options}]

{synoptset 30 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Main}
{synopt :{opt type(string)}}model type: {cmd:classify} or {cmd:regress}{p_end}
{synopt :{opt ntree(#)}}number of trees; default is 1 (single tree){p_end}
{synopt :{opt maxdepth(#)}}maximum tree depth; default is 20{p_end}
{synopt :{opt entcvdepth(#)}}cross-validation folds for depth selection; default is 10 (use 0 to disable){p_end}
{synopt :{opt minsamplessplit(#)}}minimum samples to split a node; default is 2{p_end}
{synopt :{opt minsamplesleaf(#)}}minimum samples in any leaf; default is 1{p_end}
{synopt :{opt minimpuritydecrease(#)}}min impurity decrease (absolute); default is 0{p_end}
{synopt :{opt relimpdec(#)}}relative min impurity decrease factor; default is 0 (disabled){p_end}
{synopt :{opt maxleafnodes(#)}}maximum number of leaf nodes; default is unlimited{p_end}
{synopt :{opt criterion(string)}}split criterion: {cmd:gini}, {cmd:entropy}, {cmd:mse}{p_end}
{synopt :{opt nclasses(#)}}number of classes (auto-detected for classification){p_end}
{synopt :{opt mtry(#)}}features sampled per split; default is -1 (auto: sqrt(p) for classify, p/3 for regress){p_end}
{synopt :{opt generate(string)}}prefix for output variables (required){p_end}
{synopt :{opt predname(string)}}name for prediction variable{p_end}
{synopt :{opt target(varname)}}0/1 variable: 0=training, 1=test{p_end}
{synopt :{opt group(varlist)}}grouping variable(s){p_end}
{synopt :{opt mermaid(string)}}filename for Mermaid diagram export{p_end}
{synopt :{opt seed(#)}}random seed; default is 12345{p_end}
{synopt :{opt if(exp)}}observations to include (use parentheses){p_end}
{synopt :{opt in(string)}}observation range to include{p_end}
{synoptline}
{p2colreset}{...}

{marker description}{...}
{title:Description}

{pstd}{cmd:fangorn} grows a CART (Classification and Regression Tree) using
recursive binary splitting.  It supports both classification (Gini, Entropy)
and regression (MSE).  The algorithm pre-sorts all features once for O(m n)
split finding per node.

{title:Options}

{phang}{opt type(string)}: specifies the model type.  {cmd:classify} (default)
for categorical outcomes, {cmd:regress} for continuous outcomes.

{phang}{opt ntree(#)}: number of trees in the forest.  {cmd:ntree(1)} (default)
trains a single decision tree; {cmd:ntree(#)} with # > 1 trains a random forest
using bootstrap sampling and feature subsampling.  When {cmd:ntree} > 1, per-tree
leaf IDs are not available; the plugin returns aggregated predictions and an
out-of-bag (OOB) error estimate.

{phang}{opt maxdepth(#)}: maximum depth of the tree (root=0).  Default is 20.
The tree stops growing when this depth is reached.

{phang}{opt entcvdepth(#)}: number of folds for cross-validated depth
selection.  When {it:#} is 2 or larger and there are at least {it:#} × 2
training observations, {cmd:fangorn} builds a separate tree for each candidate
depth (1 to {cmd:maxdepth()}) and evaluates it on held-out folds.  The depth
with the best cross-validation score is used for the final tree.

For classification, the score is prediction accuracy; for regression, the
score is negative mean squared error (higher = better).  The random fold
assignment uses the {cmd:seed()} option for reproducibility, and the depth
search is parallelized via OpenMP.  Default is 10.  Set to 0 or 1 to disable
cross-validation and use {cmd:maxdepth()} directly.

{phang}{opt minsamplessplit(#)}: minimum number of samples required to split
an internal node.  Default is 2.

{phang}{opt minsamplesleaf(#)}: minimum number of samples required in a leaf
node.  Default is 1.

{phang}{opt minimpuritydecrease(#)}: a split will only be considered if its
impurity decrease is at least this value (absolute threshold).  Default is 0
(no restriction).  For classification, impurity is Gini or Entropy; for
regression, it is MSE.

{phang}{opt relimpdec(#)}: relative impurity decrease threshold applied as a
fraction of the root node's impurity decrease.  If set to 0.1, the minimum
impurity decrease for all splits is 0.1 times the impurity decrease achieved
at the first split (root node).  Default is 0 (disabled, uses
{cmd:minimpuritydecrease()} as an absolute threshold).

{phang}{opt maxleafnodes(#)}: hard limit on the number of leaf nodes in the
tree.  When the tree exceeds this limit, the algorithm prunes the least
important splits (smallest impurity decrease) until the limit is satisfied.
Specify {cmd:.} (missing, the default) for unlimited leaves.

{phang}{opt criterion(string)}: split criterion.  {cmd:gini} (default for
classification), {cmd:entropy}, or {cmd:mse} (default for regression).  Gini
and Entropy are for classification only; MSE is for regression only.

{phang}{opt nclasses(#)}: number of output classes for classification.  If
not specified, the number of distinct values of {it:depvar} is used.

{phang}{opt generate(string)}: prefix for the output variables.  Two variables
are created: {it:prefix}_pred (prediction) and {it:prefix} (leaf node ID).
This option is required.

{phang}{opt predname(string)}: custom name for the prediction variable.
Default is {it:generate}_pred.

{phang}{opt target(varname)}: 0/1 variable marking training ({cmd:target=0})
and test ({cmd:target=1}) observations.  When specified, the tree is built
using only observations with {cmd:target=0}, but predictions are generated
for all observations (both training and test).

{phang}{opt group(varlist)}: one or more grouping variables.  String group
variables are automatically encoded to numeric.  Groups are read by the C
plugin but not yet used for group-specific tree building (Phase 2).{p_end}

{phang}{opt mermaid(filename)}: exports the trained tree structure to a
Mermaid flowchart file for documentation or visualization.  The file is
overwritten if it exists.

{phang}{opt seed(#)}: random seed for the internal PRNG.  Default is 12345.
Controls reproducibility of bootstrap sampling and feature subsampling.  Each
tree uses {cmd:seed} + tree_index as its own seed, so the forest is fully
reproducible when the same {cmd:seed()} is specified.

{phang}{opt mtry(#)}: number of features randomly sampled as candidates at each
split.  Default is -1 (automatic): {cmd:sqrt(p)} for classification, {cmd:p/3}
for regression, where p is the number of independent variables.  Set to a
positive integer to override.  When {cmd:ntree(1)}, this option is ignored.

{phang}{opt if(exp)}: Stata {cmd:if} qualifier, but specified as an option
using parentheses: {cmd:if(condition)}.  This workaround avoids a Stata 18
syntax parsing issue with long option lists.{p_end}

{phang}{opt in(string)}: Stata {cmd:in} qualifier as an option:
{cmd:in(range)}.{p_end}

{marker output}{...}
{title:Output Variables}

{pstd}Two output variables are created:

{pmore}
{phang2}{it:prefix}_pred: predicted value.  For classification, this is the
predicted class label (integer).  For regression, this is the predicted mean.
With {cmd:ntree} > 1, predictions are aggregated across all trees (majority
vote for classification, mean for regression).

{phang2}{it:prefix}: leaf node ID (heap-style binary tree identifier).  Each
unique value identifies a distinct leaf in the tree.  When {cmd:ntree} > 1,
this variable is set to 0 for all observations (leaf IDs are not meaningful
for a forest).

{marker stored_results}{...}
{title:Stored Results}

{pstd}{cmd:fangorn} stores the following in {cmd:r()}:

{p 12 24 2}
{cmd:r(N)}        number of observations used in estimation{p_end}
{cmd:r(ntree)}    number of trees{p_end}
{cmd:r(maxdepth)} maximum tree depth{p_end}
{cmd:r(type)}     model type ({cmd:classify} or {cmd:regress}){p_end}
{cmd:r(oob_error)}out-of-bag error estimate (misclassification rate for classify, MSE for regress); only when {cmd:ntree} > 1{p_end}

{marker examples}{...}
{title:Examples}

{phang2}. {cmd:fangorn y x1 x2, generate(pred)}{p_end}
Basic classification with auto-detected classes.

{phang2}. {cmd:fangorn y x1 x2, type(regress) generate(pred) maxdepth(5)}{p_end}
Regression tree with max depth 5.

{phang2}. {cmd:fangorn y x1 x2, generate(pred) minimpuritydecrease(0.01)}{p_end}
Classification with absolute impurity decrease threshold.

{phang2}. {cmd:fangorn y x1 x2, generate(pred) relimpdec(0.1)}{p_end}
Classification with relative impurity decrease threshold set to 10% of the
root split's impurity decrease.

{phang2}. {cmd:fangorn y x1 x2, generate(pred) maxleafnodes(8)}{p_end}
Tree limited to at most 8 leaves.

{phang2}. {cmd:fangorn y x1 x2, generate(pred) relimpdec(0.05) maxleafnodes(16)}{p_end}
Combined regularization: relative threshold and leaf count limit.

{phang2}. {cmd:fangorn y x1 x2, generate(pred) target(train) mermaid(tree.md)}{p_end}
Classification with training/test split and Mermaid diagram export.  Train
on target=0, predict on all observations.

{phang2}. {cmd:fangorn y x1 x2, generate(pred) entcvdepth(5)}{p_end}
Use 5-fold cross-validation to select the optimal tree depth.

{phang2}. {cmd:fangorn y x1 x2, type(regress) generate(pred) entcvdepth(10) maxdepth(15)}{p_end}
Regression tree with 10-fold CV for depth selection, considering depths 1 to 15.

{phang2}. {cmd:fangorn y x1 x2, generate(pred) ntree(100) mtry(3)}{p_end}
Random forest with 100 trees, sampling 3 features per split.

{phang2}. {cmd:fangorn y x1 x2, type(regress) generate(pred) ntree(50) seed(42)}{p_end}
Regression random forest with 50 trees and reproducible seed.

{marker references}{...}
{title:References}

{pstd}Breiman, L., Friedman, J. H., Olshen, R. A., & Stone, C. J. (1984).
{it:Classification and Regression Trees}. Wadsworth & Brooks/Cole.

{pstd}Hastie, T., Tibshirani, R., & Friedman, J. (2009).
{it:The Elements of Statistical Learning} (2nd ed.). Springer.

{marker seealso}{...}
{title:Also See}

{p 4 14 2}{cmd:help kdensity2}{p_end}
{cmd:help nwreg}{p_end}
{cmd:help bprecall}{p_end}
