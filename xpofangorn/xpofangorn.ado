*! xpofangorn 1.0.0  15may2026
* Partially linear model via double machine learning (DML)
* Uses fangorn internally for K-fold cross-fitting
program define xpofangorn, rclass
    version 14

    /*
     * Syntax:
     *   xpofangorn depvar treatvar [indepvars] [, options]
     *
     * Implements the partially linear model:
     *   y_i = beta * w_i + g(x_i) + u_i
     *
     * via double machine learning (Chernozhukov et al., 2018):
     *   1. Split data into K folds (random shuffle, restore order)
     *   2. For each fold k:
     *      a. Train E[y|X] on K-1 folds via fangorn, predict on fold k → e_y
     *      b. Train E[w|X] on K-1 folds via fangorn, predict on fold k → e_w
     *   3. Regress e_y on e_w to get beta
     *
     * Note: if() and in() are used as options (not Stata qualifiers),
     * consistent with fangorn syntax.
     */

    syntax varlist(min=2 numeric) ///
        [, GENerate(string) ///
            DEBUG ///
            KFOLD(integer 5) ///
            TYpe(string) ///
            VCE(string) ///
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
           MTRY(integer -1) ///
           NTiles(integer 0) ///
           NPROC(integer 16) ///
           IF(string) IN(string) ]

    /* ---- Create touse marker from if/in option ---- */
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
    local N = r(N)
    if `N' < 2 {
        display as error "Need at least 2 observations"
        exit 2001
    }
    if `N' < `kfold' * 2 {
        display as error "Need at least " `kfold' * 2 " observations for `kfold'-fold cross-fitting"
        exit 2001
    }

    /* ---- Validate minimum varlist (y + w required) ---- */
    local depvar : word 1 of `varlist'
    local treatvar : word 2 of `varlist'
    local nwords : word count `varlist'
    local indepvars ""
    if `nwords' >= 3 {
        forvalues i = 3/`nwords' {
            local indepvars "`indepvars' `: word `i' of `varlist''"
        }
        local indepvars = strtrim("`indepvars'")
    }
    else {
        display as error "At least 3 variables required: depvar treatvar indepvars"
        exit 198
    }
    local nindepvars : word count `indepvars'

    /* ---- Determine w model type ---- */
    * DML requires E[w|X] as a continuous prediction, so default to regression.
    * If user explicitly specifies type(classify):
    *   - Binary w (0/1): fangorn returns P(y=1|X) = E[w|X], works correctly.
    *   - Continuous w: classification not meaningful — error.
    if "`type'" != "" {
        if "`type'" != "classify" & "`type'" != "regress" {
            display as error "Invalid type(`type'); valid: classify, regress"
            exit 198
        }
        if "`type'" == "classify" {
            * Verify w is binary
            quietly count if `touse' & (`treatvar' != 0 & `treatvar' != 1)
            if r(N) > 0 {
                display as error "type(classify) requires a binary (0/1) treatment variable"
                exit 198
            }
        }
        local w_type "`type'"
    }
    else {
        local w_type "regress"
    }

    /* ---- Set default criterion for w model ---- */
    if "`criterion'" == "" {
        if "`w_type'" == "classify" {
            local w_criterion "criterion(gini)"
        }
        else {
            local w_criterion "criterion(mse)"
        }
    }
    else {
        local w_criterion "criterion(`criterion')"
    }

    /* ---- Parse vce option ---- */
    local reg_vce "robust"
    if "`vce'" != "" {
        gettoken vce_type vce_arg : vce
        if "`vce_type'" == "robust" {
            local reg_vce "robust"
        }
        else if "`vce_type'" == "cluster" {
            if "`vce_arg'" == "" {
                display as error "vce(cluster ...) requires a variable name"
                exit 198
            }
            capture confirm numeric variable `vce_arg'
            if _rc {
                display as error "cluster variable `vce_arg' not found"
                exit 198
            }
            local reg_vce "cluster(`vce_arg')"
        }
        else {
            display as error "Invalid vce() option; valid: robust, cluster(varname)"
            exit 198
        }
    }

    /* ---- Validate kfold ---- */
    if `kfold' < 2 {
        display as error "kfold() must be at least 2"
        exit 198
    }
    if `kfold' > `N' {
        display as error "kfold() cannot exceed number of observations"
        exit 198
    }

    /* ---- Markout: exclude obs with missing values in any analysis variable ---- */
    * This ensures fangorn doesn't receive NaN/inf values
    tempvar touse_mark
    gen byte `touse_mark' = `touse'
    markout `touse_mark' `depvar' `treatvar' `indepvars'
    * Update touse to exclude missing-value obs
    quietly replace `touse' = `touse_mark'
    quietly count if `touse'
    local N = r(N)
    if `N' < 2 {
        display as error "Need at least 2 observations after removing missing values"
        exit 2001
    }
    if `N' < `kfold' * 2 {
        display as error "Need at least " `kfold' * 2 " observations for `kfold'-fold cross-fitting"
        exit 2001
    }
    drop `touse_mark'

    /* ---- Build common fangorn options string (shared between both models) ---- */
    local f_opts "ntree(`ntree')"
    local f_opts "`f_opts' maxdepth(`maxdepth')"
    local f_opts "`f_opts' entcvdepth(`entcvdepth')"
    local f_opts "`f_opts' minsamplessplit(`minsamplessplit')"
    local f_opts "`f_opts' minsamplesleaf(`minsamplesleaf')"
    local f_opts "`f_opts' minimpuritydecrease(`minimpuritydecrease')"
    local f_opts "`f_opts' seed(`seed')"
    local f_opts "`f_opts' mtry(`mtry')"
    local f_opts "`f_opts' ntiles(`ntiles')"
    local f_opts "`f_opts' nproc(`nproc')"
    if "`maxleafnodes'" != "" {
        local f_opts "`f_opts' maxleafnodes(`maxleafnodes')"
    }

    /* ---- K-fold cross-fitting: shuffle, assign folds, restore ---- */
    * Set Stata seed for reproducible fold assignment.
    * fangorn's internal seed() option controls its own RNG independently.
    set seed `seed'

    tempvar orig_order rand fold_id
    gen long `orig_order' = _n
    gen double `rand' = runiform()
    * Set non-touse obs to missing so they sort last
    replace `rand' = . if !`touse'
    sort `rand'

    * Assign fold IDs only for touse=1 observations
    * (they are first N_touse obs after sort since missing sorts last)
    gen byte `fold_id' = .
    local fold_size = ceil(`N' / `kfold')
    forvalues k = 1/`kfold' {
        local start = (`k' - 1) * `fold_size' + 1
        local end = min(`k' * `fold_size', `N')
        replace `fold_id' = `k' in `start'/`end'
    }
    * Ensure last fold gets exactly the remaining observations
    replace `fold_id' = `kfold' if `fold_id' == . & `touse'

    * Restore original order
    sort `orig_order'

    /* ---- Cross-fitting loop ---- */
    tempvar e_y e_w
    gen double `e_y' = .
    gen double `e_w' = .

    display as text _n "-> DML cross-fitting: " as result "`kfold'" as text " folds ..."

    forvalues k = 1/`kfold' {
        * Create target for this fold: target=1 for held-out fold, target=0 for training
        tempvar target
        gen byte `target' = (`fold_id' == `k')

        * === Model 1: E[y | X] (always regression) ===
        tempvar tmp_y
        quietly fangorn `depvar' `indepvars', ///
            if(`touse') ///
            type(regress) ///
            criterion(mse) ///
            `f_opts' ///
            target(`target') ///
            generate(`tmp_y')
        * Store residual for held-out fold only
        quietly replace `e_y' = `depvar' - `tmp_y'_pred if `touse' & `fold_id' == `k'
        * Clean up
        capture drop `tmp_y' `tmp_y'_pred

        * === Model 2: E[w | X] (type depends on w) ===
        tempvar tmp_w
        quietly fangorn `treatvar' `indepvars', ///
            if(`touse') ///
            type(`w_type') ///
            `w_criterion' ///
            `f_opts' ///
            target(`target') ///
            generate(`tmp_w')
        * Store residual for held-out fold only
        quietly replace `e_w' = `treatvar' - `tmp_w'_pred if `touse' & `fold_id' == `k'
        * Clean up
        capture drop `tmp_w' `tmp_w'_pred

        if mod(`k', max(1, `kfold' / 10)) == 0 | `k' == `kfold' {
            display as text "  Fold " as result "`k'" as text "/`kfold' complete"
        }
    }

    /* ---- Final stage: regress e_y on e_w ---- */
    display as text _n "-> Estimating treatment effect (reg e_y e_w, `reg_vce') ..."

    * Drop observations with missing residuals (should not happen for touse=1)
    quietly count if `touse' & missing(`e_y')
    if r(N) > 0 {
        display as text "  Warning: " as result r(N) as text " observations have missing residuals (dropped from final regression)"
    }

    reg `e_y' `e_w' if `touse' & !missing(`e_y') & !missing(`e_w'), `reg_vce'

    * Capture key results
    local beta = _b[`e_w']
    local se = _se[`e_w']
    local t = _b[`e_w'] / _se[`e_w']
    local p = 2 * ttail(e(df_r), abs(`t'))

    * Store results
    return scalar N        = e(N)
    return scalar kfold    = `kfold'
    return scalar beta     = `beta'
    return scalar se       = `se'
    return scalar t        = `t'
    return scalar p        = `p'
    return local  depvar   "`depvar'"
    return local  treatvar "`treatvar'"
    return local  w_type   "`w_type'"
    return local  vce      "`reg_vce'"
    if "`type'" != "" {
        return local  type  "`type'"
    }

    /* ---- Handle debug option: auto-save residuals with default prefix ---- */
    if "`debug'" != "" & "`generate'" == "" {
        local generate "_xpofangorn"
    }

    /* ---- Optionally generate residual variables ---- */
    if "`generate'" != "" {
        capture drop `generate'_ey
        capture drop `generate'_ew
        quietly gen double `generate'_ey = `e_y' if `touse'
        quietly gen double `generate'_ew = `e_w' if `touse'
        label variable `generate'_ey "DML residual: y - E[y|X]"
        label variable `generate'_ew "DML residual: w - E[w|X]"
        display as text "Residuals saved as: " as result "`generate'_ey" as text " and " as result "`generate'_ew"
    }

    /* ---- Display results ---- */
    display as text _n "{hline 62}"
    display as text " Partially linear model — Double Machine Learning"
    display as text "{hline 62}"
    display as text " Outcome variable:  " as result "`depvar'"
    display as text " Treatment variable:" as result "`treatvar'"
    display as text " Control variables: " as result "`indepvars'"
    display as text " Model for w:       " as result "`w_type'"
    display as text " Cross-fitting K:   " as result `kfold'
    display as text " Observations:      " as result %9.0f e(N)
    display as text " SE type:           " as result "`reg_vce'"
    if "`type'" != "" {
        display as text " w type (forced):   " as result "`type'"
    }
    display as text "{hline 62}"
    display as text "            Coefficient  Std. Err.      t   P>|t|"
    display as text " " as result %12s abbrev("`treatvar'", 12) ///
        as result "  " %9.4f `beta' ///
        as result "  " %9.4f `se' ///
        as result "  " %7.3f `t' ///
        as result "  " %6.4f `p'
    display as text "{hline 62}"

end
