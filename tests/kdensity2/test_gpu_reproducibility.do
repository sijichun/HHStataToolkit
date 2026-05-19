clear all
set seed 42
set obs 3000
gen double x = rnormal()
tempvar t
gen byte `t' = 1

capture program drop _kd2
program _kd2, plugin using("/home/aragorn/ado/plus/kdensity2_cuda.plugin")

display "=== kdensity2 GPU Silverman 10-run ==="
forvalues i = 1/10 {
    gen double s`i' = .
    plugin call _kd2 x s`i' `t', kernel(gaussian) bw(silverman) ndensity(1) ntarget(0) ngroup(0) gpu(0)
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

display "=== kdensity2 GPU CV 10-run ==="
forvalues i = 1/10 {
    gen double c`i' = .
    set seed 123
    plugin call _kd2 x c`i' `t', kernel(gaussian) bw(cv) ndensity(1) ntarget(0) ngroup(0) gpu(0)
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
plugin call _kd2 x fg `t', kernel(gaussian) bw(silverman) ndensity(1) ntarget(0) ngroup(0) gpu(0)
drop `t'
kdensity2 x, bw(silverman) generate(fc)
gen double d = abs(fg - fc)
summarize d
display "GPU vs CPU max diff: " %12.2e r(max)
display "Result: " cond(r(max)<1e-5,"PASS","FAIL")
exit 0
