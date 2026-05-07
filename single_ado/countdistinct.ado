*! countdistinct 1.1.0  08may2026
program countdistinct, rclass
	version 16
	syntax varlist [if] [in] [, GENerate(name)]

	// Mark sample
	marksample touse, novarlist

	tempvar first

	quietly {
		bysort `varlist': gen byte `first' = (_n == 1) if `touse'
		count if `first' == 1
	}

	local ndistinct = r(N)

	display as text "Number of distinct observations: " as result `ndistinct'
	return scalar count = `ndistinct'

	if "`generate'" != "" {
		gen byte `generate' = `first'
		label variable `generate' "Distinct-combination indicator"
	}
end
