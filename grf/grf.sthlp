{smcl}
{* 30 Jul 2026}{...}
{cmd:grf} — Generalized random forest for heterogeneous treatment effects

{title:Syntax}

{p 8 15 2}
{cmd:grf} {it:depvar treatvar} {it:indepvars} {opth generate(newvar)} 
    [{opt yhat(varname)} {opt what(varname)} 
    {opt weights(varname)} {opt cluster(varname)} {opt equalizeclusterweights}
    {opt ntree(#)} {opt samplefraction(#)} {opt mtry(#)} 
    {opt minnodesize(#)} {opt honesty} {opt honestyfraction(#)} 
    {opt nohonestyprune} {opt alpha(#)} {opt imbalancepenalty(#)} 
    {opt nostabilizesplits} {opt cigroupsize(#)} 
    {opt vargenerate(newvar)} {opt oobgenerate(newvar)} 
    {opt seed(#)} {opt nproc(#)} 
    {opt if(string)} {opt in(string)}]

{title:Description}

{cmd:grf} implements the generalized random forest algorithm of 
Athey, Tibshirani, and Wager (2019) for estimating heterogeneous 
treatment effects (CATE). The command uses a Stata plugin wrapping 
the GRF C++ core library.

{title:Options}

{opt generate(newvar)} creates a new variable with CATE estimates.

{opt yhat(varname)} and {opt what(varname)} specify pre-computed 
orthogonalization estimates. If both are omitted, {cmd:grf} fits 
internal regression forests.

{opt vargenerate(newvar)} creates a variable with variance estimates.
{opt oobgenerate(newvar)} creates a variable with out-of-bag predictions.

{opt ntree(#)} specifies the number of trees (default 2000).
{opt samplefraction(#)} specifies subsample fraction (default 0.5).
{opt mtry(#)} specifies features per split (0=auto, default 0).
{opt minnodesize(#)} specifies minimum node size (default 5).
{opt honesty} enables honest splitting (default on).
{opt honestyfraction(#)} specifies honesty fraction (default 0.5).
{opt alpha(#)} controls maximum imbalance (default 0.05).
{opt cigroupsize(#)} sets CI group size (default 2, min 2 for variance).

{opt cluster(varname)} specifies cluster IDs.
{opt equalizeclusterweights} weights clusters equally.

{opt seed(#)} sets RNG seed (default 12345).
{opt nproc(#)} sets thread count (default 16).

{title:Example}

{cmd:. grf y w x1 x2, generate(tauhat) ntree(500)}

{title:References}

Athey, Tibshirani, and Wager (2019). Generalized Random Forests.
Annals of Statistics, 47(2).

Wager and Athey (2018). Estimation and Inference of Heterogeneous 
Treatment Effects using Random Forests. JASA, 113(523).
