*! version 0.2.0  GRF causal forest
program define grf, rclass
    version 14

    syntax varlist(min=3 numeric) ///
        [, GENerate(string) ///
           NTree(integer 2000) ///
           SAMPLEFraction(real 0.5) ///
           MTRY(integer 0) ///
           MINNodesize(integer 5) ///
           NOHONesty ///
           HONestyfraction(real 0.5) ///
           NOHONestyprune ///
           ALPHA(real 0.05) ///
           IMBalancepenalty(real 0) ///
           NOSTABILIZEsplits ///
           CIGROUPsize(integer 2) ///
           YHat(varname numeric) ///
           WHAT(varname numeric) ///
           WEIGhts(varname numeric) ///
           CLUster(varname) ///
           EQUALIZECLUSTERWeights ///
           VARGenerate(string) ///
           OOBGenerate(string) ///
           SEED(integer 12345) ///
           NPROC(integer 16) ///
           IF(string) IN(string) ]

    /* Parse positional variables: y w x1 x2 ... */
    local y : word 1 of `varlist'
    local w : word 2 of `varlist'
    local nwords : word count `varlist'
    local xvars ""
    if `nwords' >= 3 {
        forvalues i = 3/`nwords' {
            local xvars "`xvars' `: word `i' of `varlist''"
        }
        local xvars = strtrim("`xvars'")
    }
    else {
        display as error "At least 3 variables required: outcome treatment covariates"
        exit 198
    }
    local nx : word count `xvars'

    /* Create touse marker */
    tempvar touse
    gen byte `touse' = 1
    if `"`if'"' != "" {
        tempvar tmp
        gen byte `tmp' = 0
        quietly replace `tmp' = 1 if `if'
        quietly replace `touse' = `tmp'
        drop `tmp'
    }
    if `"`in'"' != "" {
        tempvar tmp
        gen byte `tmp' = 0
        quietly replace `tmp' = 1 in `in'
        quietly replace `touse' = `tmp' if `tmp' == 1
        drop `tmp'
    }
    quietly count if `touse'
    local nobs = r(N)
    if `nobs' < 2 {
        display as error "Need at least 2 observations"
        exit 2001
    }

    /* Validate generate() */
    if "`generate'" == "" {
        display as error "generate() is required"
        exit 198
    }

    /* Validate yhat/what pairing */
    local has_yhat = ("`yhat'" != "")
    local has_what = ("`what'" != "")
    if `has_yhat' != `has_what' {
        display as error "yhat() and what() must be provided together"
        exit 198
    }

    /* Create output variables */
    capture confirm new variable `generate'
    if _rc {
        quietly replace `generate' = .
    }
    else {
        quietly generate double `generate' = .
    }

    /* Variance output variable */
    if "`vargenerate'" != "" {
        capture confirm new variable `vargenerate'
        if _rc {
            quietly replace `vargenerate' = .
        }
        else {
            quietly generate double `vargenerate' = .
        }
    }

    /* OOB output variable */
    if "`oobgenerate'" != "" {
        capture confirm new variable `oobgenerate'
        if _rc {
            quietly replace `oobgenerate' = .
        }
        else {
            quietly generate double `oobgenerate' = .
        }
    }

    /* Locate and load plugin early (also needed for internal nuisance forests) */
    local plugin_path "grf/grf.plugin"
    capture findfile grf.plugin
    if _rc capture findfile g/grf.plugin
    if _rc capture findfile grf/grf.plugin
    if !_rc local plugin_path "`r(fn)'"
    local homedir : env HOME
    local plugin_path = subinstr("`plugin_path'", "~", "`homedir'", .)
    capture program _grf_plugin, plugin using("`plugin_path'")
    if _rc & _rc != 110 {
        display as error "Failed to load GRF plugin"
        exit _rc
    }

    /* Handle yhat/what: internal nuisance if not provided */
    local yhat_var ""
    local what_var ""
    tempvar yhat_internal what_internal
    if `has_yhat' {
        local yhat_var "`yhat'"
        local what_var "`what'"
    }
    else {
        /* Internal regression forests for nuisance estimates */
        local nuisance_seed = `seed'
        local nuisance_ntree = max(50, `ntree' / 4)
        quietly generate double `yhat_internal' = .
        quietly generate double `what_internal' = .

        /* The C++ regression trainer still expects the full variable layout
           (features, y, w, yhat, what, weights, cluster, generate, vargen, oobgen, touse).
           Create dummy columns for the fields that are not used in the nuisance fit. */
        tempvar w_dummy yhat_dummy what_dummy weight_dummy cluster_dummy vargen_dummy oobgen_dummy
        quietly generate double `w_dummy' = 0
        quietly generate double `yhat_dummy' = 0
        quietly generate double `what_dummy' = 0
        quietly generate double `weight_dummy' = 1
        quietly generate long   `cluster_dummy' = _n
        quietly generate double `vargen_dummy' = .
        quietly generate double `oobgen_dummy' = .

        local nuisance_layout "`xvars' `y' `w_dummy' `yhat_dummy' `what_dummy' `weight_dummy' `cluster_dummy' `yhat_internal' `vargen_dummy' `oobgen_dummy' `touse'"

        /* Nuisance forest options matching R args.orthog:
           ci.group.size=1, min.node.size=5, honesty=TRUE/fixed-fraction,
           user params passed through for sample.fraction/mtry/alpha/imbalance.penalty */
        local nuisance_opts "ntree(`nuisance_ntree') seed(`nuisance_seed') nproc(`nproc')"
        local nuisance_opts "`nuisance_opts' nfeatures(`nx')"
        local nuisance_opts "`nuisance_opts' cigroupsize(1) minnodesize(5)"
        local nuisance_opts "`nuisance_opts' samplefraction(`samplefraction') mtry(`mtry')"
        local nuisance_opts "`nuisance_opts' alpha(`alpha') imbalancepenalty(`imbalancepenalty')"
        local nuisance_opts "`nuisance_opts' honesty(1) honestyfraction(0.5)"
        if "`nohonestyprune'" != "" {
            local nuisance_opts "`nuisance_opts' honestyprune(0)"
        }
        else {
            local nuisance_opts "`nuisance_opts' honestyprune(1)"
        }

        * Fit Y ~ X
        capture plugin call _grf_plugin `nuisance_layout', `nuisance_opts'
        if _rc {
            display as error "Internal Y nuisance forest failed"
            exit _rc
        }

        * Fit W ~ X
        local nuisance_layout_w "`xvars' `w' `w_dummy' `yhat_dummy' `what_dummy' `weight_dummy' `cluster_dummy' `what_internal' `vargen_dummy' `oobgen_dummy' `touse'"
        capture plugin call _grf_plugin `nuisance_layout_w', `nuisance_opts'
        if _rc {
            display as error "Internal W nuisance forest failed"
            exit _rc
        }

        local yhat_var "`yhat_internal'"
        local what_var "`what_internal'"
    }

    /* Handle weights: constant 1 if not provided */
    tempvar weight_var
    if "`weights'" != "" {
        local weight_var "`weights'"
    }
    else {
        quietly generate double `weight_var' = 1
    }

    /* Handle cluster: unique id if not provided */
    tempvar cluster_var
    local has_cluster = ("`cluster'" != "")
    if `has_cluster' {
        capture confirm numeric variable `cluster'
        if _rc {
            tempvar cluster_num
            egen `cluster_num' = group(`cluster') if `touse'
            local cluster_var "`cluster_num'"
        }
        else {
            local cluster_var "`cluster'"
        }
    }
    else {
        quietly generate long `cluster_var' = _n
    }

    /* Center Y and W using the nuisance/provided yhat/what (for causal path) */
    tempvar y_centered w_centered
    quietly generate double `y_centered' = `y' - `yhat_var'
    quietly generate double `w_centered' = `w' - `what_var'

    /* Build plugin_vars: features -> y_centered -> w_centered -> yhat -> what -> weights -> cluster -> generate -> [vargen] -> [oobgen] -> touse */
    local plugin_vars "`xvars' `y_centered' `w_centered'"
    local plugin_vars "`plugin_vars' `yhat_var' `what_var'"
    local plugin_vars "`plugin_vars' `weight_var' `cluster_var'"
    local plugin_vars "`plugin_vars' `generate'"
    if "`vargenerate'" != "" {
        local plugin_vars "`plugin_vars' `vargenerate'"
    }
    else {
        tempvar vargen_dummy
        quietly generate double `vargen_dummy' = .
        local plugin_vars "`plugin_vars' `vargen_dummy'"
    }
    if "`oobgenerate'" != "" {
        local plugin_vars "`plugin_vars' `oobgenerate'"
    }
    else {
        tempvar oobgen_dummy
        quietly generate double `oobgen_dummy' = .
        local plugin_vars "`plugin_vars' `oobgen_dummy'"
    }
    local plugin_vars "`plugin_vars' `touse'"

    /* Compute column indices for C adapter */
    * xvars: 1..nx
    * y: nx+1
    * w: nx+2
    * yhat: nx+3
    * what: nx+4
    * weights: nx+5
    * cluster: nx+6
    * generate: nx+7
    * vargenerate: nx+8
    * oobgenerate: nx+9
    * touse: nx+10
    local n_total = `nx' + 10

    /* Build plugin arguments */
    local plugin_args "ntree(`ntree') seed(`seed') nproc(`nproc')"
    local plugin_args "`plugin_args' nfeatures(`nx')"
    local plugin_args "`plugin_args' samplefraction(`samplefraction')"
    local plugin_args "`plugin_args' mtry(`mtry')"
    local plugin_args "`plugin_args' minnodesize(`minnodesize')"
    if "`nohonesty'" != "" {
        local plugin_args "`plugin_args' honesty(0)"
    }
    else {
        local plugin_args "`plugin_args' honesty(1)"
    }
    local plugin_args "`plugin_args' honestyfraction(`honestyfraction')"
    if "`nohonestyprune'" != "" {
        local plugin_args "`plugin_args' honestyprune(0)"
    }
    else {
        local plugin_args "`plugin_args' honestyprune(1)"
    }
    local plugin_args "`plugin_args' alpha(`alpha')"
    local plugin_args "`plugin_args' imbalancepenalty(`imbalancepenalty')"
    if "`nostabilizesplits'" != "" {
        local plugin_args "`plugin_args' stabilizesplits(0)"
    }
    else {
        local plugin_args "`plugin_args' stabilizesplits(1)"
    }
    local plugin_args "`plugin_args' cigroupsize(`cigroupsize')"
    if "`vargenerate'" != "" {
        local plugin_args "`plugin_args' estimatevariance(1)"
    }
    if "`oobgenerate'" != "" {
        local plugin_args "`plugin_args' computeoob(1)"
    }
    if "`equalizeclusterweights'" != "" {
        local plugin_args "`plugin_args' equalizeclusterweights(1)"
    }
    local plugin_args "`plugin_args' yhatidx(`=`nx'+3')"
    local plugin_args "`plugin_args' whatidx(`=`nx'+4')"
    local plugin_args "`plugin_args' weightidx(`=`nx'+5')"
    local plugin_args "`plugin_args' clusteridx(`=`nx'+6')"
    local plugin_args "`plugin_args' generateidx(`=`nx'+7')"
    local plugin_args "`plugin_args' vargenerateidx(`=`nx'+8')"
    local plugin_args "`plugin_args' oobgenerateidx(`=`nx'+9')"
    local plugin_args "`plugin_args' ntotalvars(`n_total')"

    /* Call plugin */
    plugin call _grf_plugin `plugin_vars', `plugin_args'

    /* Return results */
    return scalar N        = `nobs'
    return scalar ntree    = `ntree'
    return scalar seed     = `seed'
    return scalar mtry     = `mtry'
    return scalar ci_group_size = `cigroupsize'
end
