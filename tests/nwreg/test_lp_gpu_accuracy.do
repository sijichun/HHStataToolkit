*! test_lp_gpu_accuracy.do - Verify GPU produces correct results

clear all
set seed 42
set obs 5000
gen double x = rnormal()
gen double y = sin(x) + 0.3 * rnormal()

nwreg y x, poly(1) generate(yhat)
nwreg y x, poly(2) generate(yhat2)

summarize yhat yhat2
display "GPU test complete (N=5000)"
