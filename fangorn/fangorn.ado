*! version 1.0.0  09may2026
program define fangorn, rclass
    version 14
    
    /*
     * Syntax:
     *   fangorn depvar indepvars [, options]
     *
     * Note: if() and in() are used instead of Stata qualifiers
     * due to a Stata 18 syntax parsing interaction with string options.
     * Usage: fangorn y x1 x2, generate(myresult) if(flag==1)
     *
     * Phase 1: single decision tree (ntree=1 only).
     * Phase 1.5: added relimpdec() and maxleafnodes() regularization.
     * Phase 1.6: added entcvdepth() for cross-validated depth selection.
     * Phase 2: added random forest (ntree>1), bootstrap, OOB, mtry.
     * Phase 3 will add ntiles, strategy.
     */
    
    syntax varlist(min=2 numeric) ///
        [, TYpe(string) ///
           NTree(integer 1) ///
           MAXDepth(integer 20) ///
           ENTCVDEPth(integer 10) ///
           MINSAMPLESSplit(integer 2) ///
           MINSAMPLESLeaf(integer 1) ///
           MINIMPURITYDecrease(real 0.0) ///
           RELIMPDEC(real 0.0) ///
           MAXLeafnodes(string) ///
           CRITerion(string) ///
           SEED(integer 12345) ///
           NCLasses(integer -1) ///
           MTRY(integer -1) ///
           NTiles(integer 0) ///
           GENerate(string) ///
           PREDname(string) ///
           TARget(varname numeric) ///
           GRoup(varlist) ///
           MERmaid(string) ///
           NPROC(integer 16) ///
           IF(string) IN(string) ]
    
    /* Create touse marker from if/in option */
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
    
    /* Validate generate() option */
    if "`generate'" == "" {
        display as error "generate() option is required"
        exit 198
    }
    
    /* Parse depvar and indepvars */
    local depvar : word 1 of `varlist'
    local nwords : word count `varlist'
    local indepvars ""
    forvalues i = 2/`nwords' {
        local indepvars "`indepvars' `: word `i' of `varlist''"
    }
    local indepvars = strtrim("`indepvars'")
    local nindepvars : word count `indepvars'
    
    /* Validate type option */
    local type_opt = cond("`type'" == "", "classify", "`type'")
    if "`type_opt'" != "classify" & "`type_opt'" != "regress" {
        display as error "Invalid type: `type_opt'"
        display as error "Valid types: classify, regress"
        exit 198
    }
    
    /* For classification: auto-detect nclasses if not specified */
    local nclasses_opt = `nclasses'
    if "`type_opt'" == "classify" & `nclasses_opt' == -1 {
        quietly levelsof `depvar' if `touse', local(levels)
        local nclasses_opt : word count `levels'
        if `nclasses_opt' < 2 {
            display as error "depvar must have at least 2 distinct classes for classification"
            exit 198
        }
    }
    
    /* Set default criterion based on type */
    if "`criterion'" == "" {
        if "`type_opt'" == "classify" {
            local criterion_opt "gini"
        }
        else {
            local criterion_opt "mse"
        }
    }
    else {
        local criterion_opt "`criterion'"
    }
    
    /* Handle group variables: convert string vars to numeric encoding */
    local ngroup = 0
    local groupvars ""
    foreach gv in `group' {
        local ngroup = `ngroup' + 1
        capture confirm numeric variable `gv'
        if _rc {
            tempvar group_num`ngroup'
            egen `group_num`ngroup'' = group(`gv') if `touse'
            local groupvars "`groupvars' `group_num`ngroup''"
        }
        else {
            local groupvars "`groupvars' `gv'"
        }
    }
    
    /* Check target variable */
    local ntarget = 0
    if "`target'" != "" {
        local ntarget 1
        quietly summarize `target' if `touse'
        if r(min) < 0 | r(max) > 1 {
            display as error "target() variable must be 0 or 1"
            exit 198
        }
    }
    
    /* Generate prediction output variable (result) */
    local pred_var = cond("`predname'" == "", "`generate'_pred", "`predname'")
    capture confirm new variable `pred_var'
    if _rc {
        quietly replace `pred_var' = .
    }
    else {
        quietly generate double `pred_var' = .
    }
    
    /* Generate leaf_id output variable */
    local leaf_var "`generate'"
    capture confirm new variable `leaf_var'
    if _rc {
        quietly replace `leaf_var' = .
    }
    else {
        quietly generate double `leaf_var' = .
    }
    
    /* Build variable list for plugin:
     * indepvars depvar [target] [groupvars] result leaf_id touse
     * C plugin expects: features(1..n_features) y(n_features+1) */
    local plugin_vars "`indepvars' `depvar'"
    if `ntarget' local plugin_vars "`plugin_vars' `target'"
    if `ngroup' > 0 local plugin_vars "`plugin_vars' `groupvars'"
    local plugin_vars "`plugin_vars' `pred_var'"
    local plugin_vars "`plugin_vars' `leaf_var'"
    local plugin_vars "`plugin_vars' `touse'"
    
    /* Count variables for plugin args */
    local nindep = `nindepvars'
    
    /* Load plugin (capture avoids "already defined" on repeated calls) */
    local plugin_path "fangorn/fangorn.plugin"
    capture findfile fangorn.plugin
    if _rc capture findfile p/fangorn.plugin
    if _rc capture findfile fangorn/fangorn.plugin
    if !_rc local plugin_path "`r(fn)'"
    * Expand ~ to full path (plugin using() doesn't handle tilde)
    local homedir : env HOME
    local plugin_path = subinstr("`plugin_path'", "~", "`homedir'", .)
    capture program _fangorn_plugin, plugin using("`plugin_path'")
    
    /* Build options for plugin */
    local plugin_args "type(`type_opt')"
    local plugin_args "`plugin_args' ntree(`ntree')"
    local plugin_args "`plugin_args' maxdepth(`maxdepth')"
    local plugin_args "`plugin_args' entcvdepth(`entcvdepth')"
    local plugin_args "`plugin_args' minsamplessplit(`minsamplessplit')"
    local plugin_args "`plugin_args' minsamplesleaf(`minsamplesleaf')"
    local plugin_args "`plugin_args' minimpuritydecrease(`minimpuritydecrease')"
    local plugin_args "`plugin_args' minimpuritydecreasefactor(`relimpdec')"
    if "`maxleafnodes'" == "" {
        local plugin_args "`plugin_args' maxleafnodes(-1)"
    }
    else {
        local plugin_args "`plugin_args' maxleafnodes(`maxleafnodes')"
    }
    local plugin_args "`plugin_args' criterion(`criterion_opt')"

    local plugin_args "`plugin_args' seed(`seed')"
    local plugin_args "`plugin_args' mtry(`mtry')"
    local plugin_args "`plugin_args' ntiles(`ntiles')"
    local plugin_args "`plugin_args' nclasses(`nclasses_opt')"
    local plugin_args "`plugin_args' nfeatures(`nindep')"
    local plugin_args "`plugin_args' ntarget(`ntarget')"
    local plugin_args "`plugin_args' ngroup(`ngroup')"
    local plugin_args "`plugin_args' nproc(`nproc')"
    if `nindep' > 0 {
        local plugin_args "`plugin_args' featurenames(`indepvars')"
    }
    if "`mermaid'" != "" {
        local plugin_args "`plugin_args' mermaid(`mermaid')"
    }
    
    /* Call plugin: no if qualifier, touse is explicit variable */
    plugin call _fangorn_plugin `plugin_vars', `plugin_args'
    
    /* Store results */
    return scalar N        = r(N)
    return scalar ntree    = `ntree'
    return scalar maxdepth = `maxdepth'
    return local  type     "`type_opt'"
    
    if `ntree' > 1 {
        capture scalar oob_err = __fangorn_oob_err
        if !_rc {
            return scalar oob_error = scalar(oob_err)
            scalar drop __fangorn_oob_err
        }
    }
    
    /* Display results */
    display as text _n "Random forest / decision tree"
    display as text "{hline 40}"
    display as text "Dep. variable: " as result "`depvar'"
    display as text "Indep. vars:   " as result "`indepvars'"
    if `ntarget' {
        display as text "Target var:    " as result "`target'"
        display as text "               (target=0: training, target=1: test)"
    }
    if `ngroup' > 0 {
        display as text "Group vars:    " as result "`group'"
    }
    display as text "Type:          " as result "`type_opt'"
    display as text "Criterion:     " as result "`criterion_opt'"
    display as text "Trees:         " as result `ntree'
    display as text "Max depth:     " as result `maxdepth'
    if `ntree' > 1 {
        display as text "Mtry:          " as result `mtry'
        if r(oob_error) != . {
            display as text "OOB error:     " as result %9.4f r(oob_error)
        }
    }
    display as text "Observations:  " as result `nobs'
    display as text "Prediction var:" as result " `pred_var'"
    if `ntree' == 1 {
        display as text "Leaf ID var:   " as result " `leaf_var'"
    }
    if "`mermaid'" != "" {
        display as text "Mermaid file:  " as result " `mermaid'"
    }
    display as text "{hline 40}"
    
    /* Label output variables */
    label variable `pred_var' "fangorn prediction"
    if `ntree' == 1 {
        label variable `leaf_var' "fangorn leaf ID"
    }
    else {
        label variable `leaf_var' "fangorn forest placeholder"
    }
    
end
