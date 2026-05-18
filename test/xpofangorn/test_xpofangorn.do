*! test_xpofangorn.do — Monte Carlo simulation for xpofangorn
* Run: stata -b do test/xpofangorn/test_xpofangorn.do
*
* Monte Carlo simulation: 50 repetitions per configuration.
* For each setting, reports:
*   - Mean and SD of beta_hat (across repetitions)
*   - Mean of estimated SE (across repetitions)
*   - Mean runtime per repetition
*
* DGP: Partially linear model, y = 3*w + g(x) + u
*   x1 ~ N(0, 1)
*   x2 ~ chi2(3) + exp(x1)
*   d1 = ceil(20*runiform())     (19 categories)
*   d2 = runiform() < 0.4
*   w  = x1 + log(x2) + d1*sin(exp(x1)) + exp(x1*x2*d2/20) + N(0,2)
*   y  = 3*w + exp((d1*cos(x2) - d2*x1 + x1/x2)/5) + log(chi2(8))

clear all
set more off

local nrep  = 50
local N     = 5000
local beta0 = 3

* ============================================================
* Create results dataset
* ============================================================
clear
set obs 300
gen str20 config = ""
gen int    rep   = .
gen double beta  = .
gen double se    = .
gen double time  = .

local row = 0

* ============================================================
* Monte Carlo loop — Config 1: RF50, K=5, D=10
* ============================================================
local cfgname "RF50_K5_D10"
display _n "{hline 72}"
display "=== Config: `cfgname' (ntree=50, kfold=5, maxdepth=10) ==="
display "{hline 72}"

forvalues r = 1/`nrep' {
    local row = `row' + 1
    preserve
    clear
    set obs `N'
    set seed `= 100000 + `r''

    gen double x1 = rnormal()
    gen double chi2_3 = rnormal()^2 + rnormal()^2 + rnormal()^2
    gen double x2 = chi2_3 + exp(x1)
    gen double d1 = ceil(20 * runiform())
    gen byte   d2 = (runiform() < 0.4)
    gen double w  = x1 + log(x2) + d1 * sin(exp(x1)) ///
        + exp(x1 * x2 * d2 / 20) + 2 * rnormal()
    gen double chi2_8 = rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2
    gen double g_x = exp((d1 * cos(x2) - d2 * x1 + x1 / x2) / 5) + log(chi2_8)
    gen double y = 3 * w + g_x + rnormal()

    quietly tabulate d1, gen(d1_dum)
    local controls "x1 x2 d1_dum1-d1_dum19 d2"

    local t0 = clock(c(current_time), "hms")
    capture noisily xpofangorn y w `controls', kfold(5) ntree(50) maxdepth(10) seed(`r')

    if _rc == 0 {
        local this_beta  = r(beta)
        local this_se   = r(se)
        local this_time = (`t1' - `t0') / 1000
    }
    else {
        local this_beta  = .
        local this_se   = .
        local this_time = .
        display as error "  Rep `r' failed (rc=" _rc ")"
    }

    restore
    replace config = "`cfgname'" in `row'
    replace rep   = `r'          in `row'
    replace beta  = `this_beta'  in `row'
    replace se    = `this_se'    in `row'
    replace time  = `this_time'  in `row'

    if mod(`r', 10) == 0 | `r' == `nrep' {
        display "  Rep `r'/`nrep': beta=" %9.4f `this_beta' " se=" %9.4f `this_se' " time=" %5.1f `this_time' "s"
    }
}

* ============================================================
* Config 2: RF100, K=5, D=10
* ============================================================
local cfgname "RF100_K5_D10"
display _n "{hline 72}"
display "=== Config: `cfgname' (ntree=100, kfold=5, maxdepth=10) ==="
display "{hline 72}"

forvalues r = 1/`nrep' {
    local row = `row' + 1
    preserve
    clear
    set obs `N'
    set seed `= 200000 + `r''

    gen double x1 = rnormal()
    gen double chi2_3 = rnormal()^2 + rnormal()^2 + rnormal()^2
    gen double x2 = chi2_3 + exp(x1)
    gen double d1 = ceil(20 * runiform())
    gen byte   d2 = (runiform() < 0.4)
    gen double w  = x1 + log(x2) + d1 * sin(exp(x1)) ///
        + exp(x1 * x2 * d2 / 20) + 2 * rnormal()
    gen double chi2_8 = rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2
    gen double g_x = exp((d1 * cos(x2) - d2 * x1 + x1 / x2) / 5) + log(chi2_8)
    gen double y = 3 * w + g_x + rnormal()

    quietly tabulate d1, gen(d1_dum)
    local controls "x1 x2 d1_dum1-d1_dum19 d2"

    local t0 = clock(c(current_time), "hms")
    capture noisily xpofangorn y w `controls', kfold(5) ntree(100) maxdepth(10) seed(`r')

    if _rc == 0 {
        local this_beta  = r(beta)
        local this_se   = r(se)
        local this_time = (`t1' - `t0') / 1000
    }
    else {
        local this_beta  = .
        local this_se   = .
        local this_time = .
        display as error "  Rep `r' failed (rc=" _rc ")"
    }

    restore
    replace config = "`cfgname'" in `row'
    replace rep   = `r'          in `row'
    replace beta  = `this_beta'  in `row'
    replace se    = `this_se'    in `row'
    replace time  = `this_time'  in `row'

    if mod(`r', 10) == 0 | `r' == `nrep' {
        display "  Rep `r'/`nrep': beta=" %9.4f `this_beta' " se=" %9.4f `this_se' " time=" %5.1f `this_time' "s"
    }
}

* ============================================================
* Config 3: RF50, K=2, D=10
* ============================================================
local cfgname "RF50_K2_D10"
display _n "{hline 72}"
display "=== Config: `cfgname' (ntree=50, kfold=2, maxdepth=10) ==="
display "{hline 72}"

forvalues r = 1/`nrep' {
    local row = `row' + 1
    preserve
    clear
    set obs `N'
    set seed `= 300000 + `r''

    gen double x1 = rnormal()
    gen double chi2_3 = rnormal()^2 + rnormal()^2 + rnormal()^2
    gen double x2 = chi2_3 + exp(x1)
    gen double d1 = ceil(20 * runiform())
    gen byte   d2 = (runiform() < 0.4)
    gen double w  = x1 + log(x2) + d1 * sin(exp(x1)) ///
        + exp(x1 * x2 * d2 / 20) + 2 * rnormal()
    gen double chi2_8 = rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2
    gen double g_x = exp((d1 * cos(x2) - d2 * x1 + x1 / x2) / 5) + log(chi2_8)
    gen double y = 3 * w + g_x + rnormal()

    quietly tabulate d1, gen(d1_dum)
    local controls "x1 x2 d1_dum1-d1_dum19 d2"

    local t0 = clock(c(current_time), "hms")
    capture noisily xpofangorn y w `controls', kfold(2) ntree(50) maxdepth(10) seed(`r')

    if _rc == 0 {
        local this_beta  = r(beta)
        local this_se   = r(se)
        local this_time = (`t1' - `t0') / 1000
    }
    else {
        local this_beta  = .
        local this_se   = .
        local this_time = .
        display as error "  Rep `r' failed (rc=" _rc ")"
    }

    restore
    replace config = "`cfgname'" in `row'
    replace rep   = `r'          in `row'
    replace beta  = `this_beta'  in `row'
    replace se    = `this_se'    in `row'
    replace time  = `this_time'  in `row'

    if mod(`r', 10) == 0 | `r' == `nrep' {
        display "  Rep `r'/`nrep': beta=" %9.4f `this_beta' " se=" %9.4f `this_se' " time=" %5.1f `this_time' "s"
    }
}

* ============================================================
* Config 4: RF50, K=10, D=10
* ============================================================
local cfgname "RF50_K10_D10"
display _n "{hline 72}"
display "=== Config: `cfgname' (ntree=50, kfold=10, maxdepth=10) ==="
display "{hline 72}"

forvalues r = 1/`nrep' {
    local row = `row' + 1
    preserve
    clear
    set obs `N'
    set seed `= 400000 + `r''

    gen double x1 = rnormal()
    gen double chi2_3 = rnormal()^2 + rnormal()^2 + rnormal()^2
    gen double x2 = chi2_3 + exp(x1)
    gen double d1 = ceil(20 * runiform())
    gen byte   d2 = (runiform() < 0.4)
    gen double w  = x1 + log(x2) + d1 * sin(exp(x1)) ///
        + exp(x1 * x2 * d2 / 20) + 2 * rnormal()
    gen double chi2_8 = rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2
    gen double g_x = exp((d1 * cos(x2) - d2 * x1 + x1 / x2) / 5) + log(chi2_8)
    gen double y = 3 * w + g_x + rnormal()

    quietly tabulate d1, gen(d1_dum)
    local controls "x1 x2 d1_dum1-d1_dum19 d2"

    local t0 = clock(c(current_time), "hms")
    capture noisily xpofangorn y w `controls', kfold(10) ntree(50) maxdepth(10) seed(`r')

    if _rc == 0 {
        local this_beta  = r(beta)
        local this_se   = r(se)
        local this_time = (`t1' - `t0') / 1000
    }
    else {
        local this_beta  = .
        local this_se   = .
        local this_time = .
        display as error "  Rep `r' failed (rc=" _rc ")"
    }

    restore
    replace config = "`cfgname'" in `row'
    replace rep   = `r'          in `row'
    replace beta  = `this_beta'  in `row'
    replace se    = `this_se'    in `row'
    replace time  = `this_time'  in `row'

    if mod(`r', 10) == 0 | `r' == `nrep' {
        display "  Rep `r'/`nrep': beta=" %9.4f `this_beta' " se=" %9.4f `this_se' " time=" %5.1f `this_time' "s"
    }
}

* ============================================================
* Config 5: RF100, K=5, D=5
* ============================================================
local cfgname "RF100_K5_D5"
display _n "{hline 72}"
display "=== Config: `cfgname' (ntree=100, kfold=5, maxdepth=5) ==="
display "{hline 72}"

forvalues r = 1/`nrep' {
    local row = `row' + 1
    preserve
    clear
    set obs `N'
    set seed `= 500000 + `r''

    gen double x1 = rnormal()
    gen double chi2_3 = rnormal()^2 + rnormal()^2 + rnormal()^2
    gen double x2 = chi2_3 + exp(x1)
    gen double d1 = ceil(20 * runiform())
    gen byte   d2 = (runiform() < 0.4)
    gen double w  = x1 + log(x2) + d1 * sin(exp(x1)) ///
        + exp(x1 * x2 * d2 / 20) + 2 * rnormal()
    gen double chi2_8 = rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2
    gen double g_x = exp((d1 * cos(x2) - d2 * x1 + x1 / x2) / 5) + log(chi2_8)
    gen double y = 3 * w + g_x + rnormal()

    quietly tabulate d1, gen(d1_dum)
    local controls "x1 x2 d1_dum1-d1_dum19 d2"

    local t0 = clock(c(current_time), "hms")
    capture noisily xpofangorn y w `controls', kfold(5) ntree(100) maxdepth(5) seed(`r')

    if _rc == 0 {
        local this_beta  = r(beta)
        local this_se   = r(se)
        local this_time = (`t1' - `t0') / 1000
    }
    else {
        local this_beta  = .
        local this_se   = .
        local this_time = .
        display as error "  Rep `r' failed (rc=" _rc ")"
    }

    restore
    replace config = "`cfgname'" in `row'
    replace rep   = `r'          in `row'
    replace beta  = `this_beta'  in `row'
    replace se    = `this_se'    in `row'
    replace time  = `this_time'  in `row'

    if mod(`r', 10) == 0 | `r' == `nrep' {
        display "  Rep `r'/`nrep': beta=" %9.4f `this_beta' " se=" %9.4f `this_se' " time=" %5.1f `this_time' "s"
    }
}

* ============================================================
* Config 6: RF100, K=5, D=20
* ============================================================
local cfgname "RF100_K5_D20"
display _n "{hline 72}"
display "=== Config: `cfgname' (ntree=100, kfold=5, maxdepth=20) ==="
display "{hline 72}"

forvalues r = 1/`nrep' {
    local row = `row' + 1
    preserve
    clear
    set obs `N'
    set seed `= 600000 + `r''

    gen double x1 = rnormal()
    gen double chi2_3 = rnormal()^2 + rnormal()^2 + rnormal()^2
    gen double x2 = chi2_3 + exp(x1)
    gen double d1 = ceil(20 * runiform())
    gen byte   d2 = (runiform() < 0.4)
    gen double w  = x1 + log(x2) + d1 * sin(exp(x1)) ///
        + exp(x1 * x2 * d2 / 20) + 2 * rnormal()
    gen double chi2_8 = rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2 + rnormal()^2 ///
        + rnormal()^2 + rnormal()^2
    gen double g_x = exp((d1 * cos(x2) - d2 * x1 + x1 / x2) / 5) + log(chi2_8)
    gen double y = 3 * w + g_x + rnormal()

    quietly tabulate d1, gen(d1_dum)
    local controls "x1 x2 d1_dum1-d1_dum19 d2"

    local t0 = clock(c(current_time), "hms")
    capture noisily xpofangorn y w `controls', kfold(5) ntree(100) maxdepth(20) seed(`r')

    if _rc == 0 {
        local this_beta  = r(beta)
        local this_se   = r(se)
        local this_time = (`t1' - `t0') / 1000
    }
    else {
        local this_beta  = .
        local this_se   = .
        local this_time = .
        display as error "  Rep `r' failed (rc=" _rc ")"
    }

    restore
    replace config = "`cfgname'" in `row'
    replace rep   = `r'          in `row'
    replace beta  = `this_beta'  in `row'
    replace se    = `this_se'    in `row'
    replace time  = `this_time'  in `row'

    if mod(`r', 10) == 0 | `r' == `nrep' {
        display "  Rep `r'/`nrep': beta=" %9.4f `this_beta' " se=" %9.4f `this_se' " time=" %5.1f `this_time' "s"
    }
}

* ============================================================
* Summary statistics
* ============================================================
display _n _n "{hline 72}"
display "=== Monte Carlo Summary ==="
display "    N = `N', reps = `nrep', true beta = `beta0'"
display "{hline 72}"
display ""
display %20s "Config" "  " %9s "Mean(b)" "  " %9s "SD(b)" "  " %9s "Mean(SE)" "  " %6s "Time"
display "{hline 72}"

foreach cfgname in RF50_K5_D10 RF100_K5_D10 RF50_K2_D10 RF50_K10_D10 RF100_K5_D5 RF100_K5_D20 {
    quietly summarize beta if config == "`cfgname'"
    local mean_beta = r(mean)
    local sd_beta   = r(sd)

    quietly summarize se if config == "`cfgname'"
    local mean_se = r(mean)

    quietly summarize time if config == "`cfgname'"
    local mean_time = r(mean)

    display %20s "`cfgname'" "  " %9.4f `mean_beta' "  " %9.4f `sd_beta' ///
        "  " %9.4f `mean_se' "  " %5.1f `mean_time' "s"
}

display "{hline 72}"
display "Mean(b)  = average of beta_hat across 50 reps"
display "SD(b)    = standard deviation of beta_hat (simulation SE)"
display "Mean(SE) = average of estimated standard errors"
display "Time     = average wall-clock time per repetition (1s resolution)"
display "{hline 72}"

exit 0
