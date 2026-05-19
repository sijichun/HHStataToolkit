clear all

use "_lp_cpu.dta", clear
merge 1:1 _n using "_lp_gpu.dta", nogen

gen double diff_p1 = abs(yhat_p1_cpu - yhat_p1_gpu)
quietly summarize diff_p1
display as text "poly=1 max diff: " %12.6e r(max) "  mean: " %12.6e r(mean)

gen double diff_p2 = abs(yhat_p2_cpu - yhat_p2_gpu)
quietly summarize diff_p2
display as text "poly=2 max diff: " %12.6e r(max) "  mean: " %12.6e r(mean)
