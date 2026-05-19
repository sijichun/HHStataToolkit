*! test_local_polynomial_performance.do
*! Performance benchmark for local polynomial regression
*! Run: stata -b do test/nwreg/test_local_polynomial_performance.do

clear all
set seed 42
set maxvar 10000

local max_cores = c(processors)

display as text _n "{hline 80}"
display as text "Local Polynomial Regression Performance Benchmark"
display as text "Date: $S_DATE  Time: $S_TIME"
display as text "CPU cores: `max_cores'"
display as text "{hline 80}"

* DGP: y = sin(x) + 0.3*rnormal()
* Single regressor, Silverman bandwidth

foreach N in 1000 5000 10000 50000 {
    display as text _n "=== N = `N' ==="

    clear
    set obs `N'
    gen double x = rnormal()
    gen double y = sin(x) + 0.3 * rnormal()

    foreach poly in 0 1 2 {
        foreach nthr in 1 `max_cores' {
            local t0 = clock(c(current_time), "hms")

            if `poly' == 0 {
                nwreg y x, generate(yhat) nproc(`nthr')
            }
            else {
                nwreg y x, poly(`poly') generate(yhat) nproc(`nthr')
            }

            local t1 = clock(c(current_time), "hms")
            local elapsed = (`t1' - `t0') / 1000

            display as text "  poly=`poly', nproc=`nthr': " %10.2f `elapsed' " ms"

            drop yhat
        }
    }
}

display as text _n "{hline 80}"
display as text "Benchmark complete."
display as text "{hline 80}"
