clear all
set seed 42
set obs 3000
gen double x = rnormal()
gen double y = x^2 + rnormal()
tempvar t
gen byte `t' = 1

capture program drop _nw2
program _nw2, plugin using("/home/aragorn/ado/plus/nwreg_cuda.plugin")

display "=== nwreg GPU Silverman 10-run ==="
forvalues i = 1/10 {
    gen double s`i' = .
    plugin call _nw2 x y s`i' `t', kernel(gaussian) bw(silverman) nreg(1) ntarget(0) ngroup(0) nse(0) gpu(0)
}
local ok = 1
forvalues i = 2/10 {
    gen double d = abs(s1 - s`i')
    summarize d
    if r(max) >= 1e-5 {
        local ok = 0
    }
    drop d
}
display "Silverman 10-run: " cond(`ok',"PASS","FAIL")

display "=== nwreg GPU CV 10-run ==="
forvalues i = 1/10 {
    gen double c`i' = .
    set seed 123
    plugin call _nw2 x y c`i' `t', kernel(gaussian) bw(cv) nreg(1) ntarget(0) ngroup(0) nse(0) gpu(0)
}
local ok = 1
forvalues i = 2/10 {
    gen double d = abs(c1 - c`i')
    summarize d
    if r(max) >= 1e-5 {
        local ok = 0
    }
    drop d
}
display "CV 10-run: " cond(`ok',"PASS","FAIL")

display "=== GPU vs CPU (Silverman) ==="
gen double fg = .
plugin call _nw2 x y fg `t', kernel(gaussian) bw(silverman) nreg(1) ntarget(0) ngroup(0) nse(0) gpu(0)
drop `t'
nwreg y x, bw(silverman) generate(fc)
gen double d = abs(fg - fc)
summarize d
display "GPU vs CPU max diff: " %12.2e r(max)
display "Result: " cond(r(max)<1e-5,"PASS","FAIL")
exit 0
