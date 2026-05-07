program define labelvalidsample
	version 16
	syntax varlist [if] [in], GENerate(name)

	// Mark sample: respects if/in and excludes obs with any missing value
	marksample touse, novarlist
	markout `touse' `varlist'

	quietly gen byte `generate' = (`touse' == 1)
end
