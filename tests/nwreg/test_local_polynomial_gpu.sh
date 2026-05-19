#!/bin/bash

echo "========================================"
echo "Local Polynomial: CPU vs GPU Test"
echo "========================================"

cp ~/ado/plus/nwreg.plugin.cpu_backup ~/ado/plus/nwreg.plugin 2>/dev/null || true

echo ""
echo "Running CPU baseline..."
stata -e do test/nwreg/_lp_cpu.do

echo ""
echo "Switching to GPU plugin..."
cp nwreg/nwreg_cuda.plugin ~/ado/plus/nwreg.plugin

echo ""
echo "Running GPU test..."
stata -e do test/nwreg/_lp_gpu.do

cp ~/ado/plus/nwreg.plugin.cpu_backup ~/ado/plus/nwreg.plugin

echo ""
echo "Comparing results..."
stata -e do test/nwreg/_lp_compare.do

rm -f _lp_cpu.dta _lp_gpu.dta

echo ""
echo "Test complete."
