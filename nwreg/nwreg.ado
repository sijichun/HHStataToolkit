*! version 1.0.0  08may2026
program define nwreg, rclass
    version 14
    
    /*
     * Syntax:
     *   nwreg depvar indepvars [if] [in] [, options]
     *
     * Note: if() and in() are used instead of Stata qualifiers
     * due to a Stata 18 syntax parsing interaction with string options.
     * Usage: nwreg y x1 x2, generate(fitted) if(flag==1)
     */
    
    syntax varlist(min=2 numeric) ///
        [, Kernel(string) BW(string) ///
           TARget(varname numeric) ///
           GRoup(varlist) ///
           GENerate(string) ///
           POLY(integer 0) ///
           DERivatives(string) ///
           SEType(integer 2) ///
           SE(string) ///
           MINcount(integer 0) ///
           FOLDS(integer 10) ///
           GRIDs(integer 10) ///
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
    if r(N) < 2 {
        display as error "Need at least 2 observations"
        exit 2001
    }
    
    /* Extract depvar and indepvars from varlist */
    local depvar : word 1 of `varlist'
    local indepvars : list varlist - depvar
    
    /* Parse options */
    local kernel_opt = cond("`kernel'" == "", "gaussian", "`kernel'")
    local bw_opt = cond("`bw'" == "", "silverman", "`bw'")
    local gen_var = cond("`generate'" == "", "nwreg", "`generate'")
    
    /* Validate kernel */
    local valid_kernel 0
    foreach k in gaussian epanechnikov uniform triweight cosine {
        if "`kernel_opt'" == "`k'" {
            local valid_kernel 1
        }
    }
    if !`valid_kernel' {
        display as error "Invalid kernel: `kernel_opt'"
        display as error "Valid kernels: gaussian, epanechnikov, uniform, triweight, cosine"
        exit 198
    }
    
    /* Validate bandwidth */
    local valid_bw 0
    foreach b in silverman scott cv {
        if "`bw_opt'" == "`b'" {
            local valid_bw 1
        }
    }
    capture confirm number `bw_opt'
    if !_rc local valid_bw 1
    if !`valid_bw' {
        display as error "Invalid bandwidth: `bw_opt'"
        display as error "Valid options: silverman, scott, cv, or a positive number"
        exit 198
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
    
    /* Determine dimensions */
    local nreg : word count `indepvars'
    
    /* Create output variable */
    capture confirm new variable `gen_var'
    if _rc {
        quietly replace `gen_var' = .
    }
    else {
        quietly generate double `gen_var' = .
    }
    
    /* Create SE output variable (if requested) */
    local nse = 0
    if "`se'" != "" {
        local nse 1
        capture confirm new variable `se'
        if _rc {
            quietly replace `se' = .
        }
        else {
            quietly generate double `se' = .
        }
    }

    /* Create derivative output variables (if requested) */
    local nderiv = 0
    local deriv_vars ""
    if "`derivatives'" != "" {
        if `poly' == 0 {
            display as error "derivatives() requires poly >= 1"
            exit 198
        }
        local max_deriv = `poly'
        if `nreg' > 1 {
            local max_deriv = `nreg'
        }
        forvalues d = 1/`max_deriv' {
            local deriv_name = "`derivatives'`d'"
            capture confirm new variable `deriv_name'
            if _rc {
                quietly replace `deriv_name' = .
            }
            else {
                quietly generate double `deriv_name' = .
            }
            local deriv_vars "`deriv_vars' `deriv_name'"
        }
        local nderiv = `max_deriv'
    }
    
    /* Validate se_type */
    if `setype' < 0 | `setype' > 2 {
        display as error "se_type must be 0, 1, or 2"
        exit 198
    }

    /* Local polynomial does not support SE in phase 1 */
    if `poly' > 0 & "`se'" != "" {
        display as error "se() is not supported with poly > 0"
        exit 198
    }
    
    /* Build variable list for plugin */
    local plugin_vars "`indepvars' `depvar'"
    if `ntarget' local plugin_vars "`plugin_vars' `target'"
    if `ngroup' > 0 local plugin_vars "`plugin_vars' `groupvars'"
    local plugin_vars "`plugin_vars' `gen_var'"
    if `nse' local plugin_vars "`plugin_vars' `se'"
    if `nderiv' > 0 local plugin_vars "`plugin_vars' `deriv_vars'"
    local plugin_vars "`plugin_vars' `touse'"
    
    * Load CPU plugin
    local plugin_path "nwreg/nwreg.plugin"
    capture findfile nwreg.plugin
    if _rc capture findfile p/nwreg.plugin
    if _rc capture findfile nwreg/nwreg.plugin
    if !_rc local plugin_path "`r(fn)'"
    local homedir : env HOME
    local plugin_path = subinstr("`plugin_path'", "~", "`homedir'", .)
    capture program _nwreg_plugin, plugin using("`plugin_path'")
    
    /* Build options for plugin */
    local nproc = `nproc'
    local plugin_args "kernel(`kernel_opt')"
    local plugin_args "`plugin_args' bw(`bw_opt')"
    local plugin_args "`plugin_args' nreg(`nreg')"
    local plugin_args "`plugin_args' ntarget(`ntarget')"
    local plugin_args "`plugin_args' ngroup(`ngroup')"
    local plugin_args "`plugin_args' nse(`nse')"
    local plugin_args "`plugin_args' se_type(`setype')"
    local plugin_args "`plugin_args' minobs(`mincount')"
    local plugin_args "`plugin_args' nfolds(`folds')"
    local plugin_args "`plugin_args' ngrids(`grids')"
    local plugin_args "`plugin_args' gpu(-1)"
    local plugin_args "`plugin_args' nproc(`nproc')"
    local plugin_args "`plugin_args' poly(`poly')"
    local plugin_args "`plugin_args' nderiv(`nderiv')"
    
    /* If CV bandwidth: shuffle data order for randomized folds */
    local is_cv = ("`bw_opt'" == "cv")
    if `is_cv' {
        tempvar shuffle_order
        gen double `shuffle_order' = runiform()
        tempvar orig_order
        quietly gen long `orig_order' = _n
        sort `shuffle_order'
    }
    
    /* Call plugin: no if qualifier, touse is explicit variable */
    plugin call _nwreg_plugin `plugin_vars', `plugin_args'
    
    /* If CV was used: restore original data order */
    if `is_cv' {
        sort `orig_order'
    }
    
    /* Store results */
    return scalar N = r(N)
    return scalar ngroups = r(ngroups)
    return local kernel "`kernel_opt'"
    return local bw_method "`bw_opt'"
    return local groupvars "`group'"
    return local depvar "`depvar'"
    return local indepvars "`indepvars'"
    
    /* Display results */
    display as text _n "Nadaraya-Watson regression"
    display as text "{hline 40}"
    display as text "Dependent:    " as result "`depvar'"
    display as text "Regressors:   " as result "`indepvars'"
    if `ntarget' {
        display as text "Target var:   " as result "`target'"
        display as text "              (target=0: training, target=1: test)"
    }
    if `ngroup' > 0 {
        display as text "Group vars:   " as result "`group'"
        display as text "Groups:       " as result r(ngroups)
    }
    display as text "Observations: " as result r(N)
    display as text "Kernel:       " as result "`kernel_opt'"
    display as text "Bandwidth:    " as result "`bw_opt'"
    if `poly' > 0 {
        display as text "Polynomial:   " as result "`poly'"
    }
    if `nse' {
        display as text "SE variable:  " as result "`se'"
    }
    if `nderiv' > 0 {
        display as text "Derivatives:  " as result "`derivatives'*"
    }
    display as text "{hline 40}"
    
    /* Label variables */
    if `poly' > 0 {
        label variable `gen_var' "Local polynomial regression estimate"
    }
    else {
        label variable `gen_var' "Nadaraya-Watson regression estimate"
    }
    if `nse' {
        label variable `se' "NW regression standard error"
    }
    if `nderiv' > 0 {
        local max_deriv = `nderiv'
        forvalues d = 1/`max_deriv' {
            local deriv_name = "`derivatives'`d'"
            if `nreg' == 1 {
                label variable `deriv_name' "`d'-th derivative of LP regression"
            }
            else {
                label variable `deriv_name' "Partial derivative w.r.t. regressor `d'"
            }
        }
    }
    
end
