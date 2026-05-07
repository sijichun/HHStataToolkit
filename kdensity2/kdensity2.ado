*! version 2.2.0  07may2026
program define kdensity2, rclass
    version 14
    
    /*
     * Syntax:
     *   kdensity2 varlist [if] [in] [, options]
     *
     * Note: if() and in() are used instead of Stata qualifiers
     * due to a Stata 18 syntax parsing interaction with string options.
     * Usage: kdensity2 x, generate(myf) if(flag==1)
     */
    
    syntax varlist(min=1 numeric) ///
        [, Kernel(string) BW(string) ///
           TARget(varname numeric) ///
           GRoup(varlist) ///
           GENerate(string) ///
           MINcount(integer 0) ///
           FOLDS(integer 10) ///
           GRIDs(integer 10) ///
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
    
    /* Parse options */
    local kernel_opt = cond("`kernel'" == "", "gaussian", "`kernel'")
    local bw_opt = cond("`bw'" == "", "silverman", "`bw'")
    local gen_var = cond("`generate'" == "", "kdensity2", "`generate'")
    
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
    local ndensity : word count `varlist'
    
    /* Create output variable */
    capture confirm new variable `gen_var'
    if _rc {
        quietly replace `gen_var' = .
    }
    else {
        quietly generate double `gen_var' = .
    }
    
    /* Build variable list for plugin */
    local plugin_vars "`varlist'"
    if `ntarget' local plugin_vars "`plugin_vars' `target'"
    if `ngroup' > 0 local plugin_vars "`plugin_vars' `groupvars'"
    local plugin_vars "`plugin_vars' `gen_var'"
    local plugin_vars "`plugin_vars' `touse'"
    
    /* Load plugin (capture avoids "already defined" on repeated calls) */
    local plugin_path "kdensity2/kdensity2.plugin"
    capture findfile kdensity2.plugin
    if _rc capture findfile p/kdensity2.plugin
    if _rc capture findfile kdensity2/kdensity2.plugin
    if !_rc local plugin_path "`r(fn)'"
    * Expand ~ to full path (plugin using() doesn't handle tilde)
    local homedir : env HOME
    local plugin_path = subinstr("`plugin_path'", "~", "`homedir'", .)
    capture program _kdensity2_plugin, plugin using("`plugin_path'")
    
    /* Build options for plugin */
    local plugin_args "kernel(`kernel_opt')"
    local plugin_args "`plugin_args' bw(`bw_opt')"
    local plugin_args "`plugin_args' ndensity(`ndensity')"
    local plugin_args "`plugin_args' ntarget(`ntarget')"
    local plugin_args "`plugin_args' ngroup(`ngroup')"
    local plugin_args "`plugin_args' minobs(`mincount')"
    local plugin_args "`plugin_args' nfolds(`folds')"
    local plugin_args "`plugin_args' ngrids(`grids')"
    
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
    plugin call _kdensity2_plugin `plugin_vars', `plugin_args'
    
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
    
    /* Display results */
    display as text _n "Kernel density estimation"
    display as text "{hline 40}"
    display as text "Variables:    " as result "`varlist'"
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
    display as text "{hline 40}"
    
    /* Label variable */
    label variable `gen_var' "Kernel density estimate"
    
end
