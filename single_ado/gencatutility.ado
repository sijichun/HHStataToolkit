*! gencatutility 1.1.0  2026-05-08
*! Compute category utility scores for an ordered categorical variable.

program define gencatutility, rclass
	version 16
	syntax varname, GENerate(name) [Display]

	// ---------------------------------------------------------------------------
	// Validate output variable
	// ---------------------------------------------------------------------------
	confirm new variable `generate'

	// ---------------------------------------------------------------------------
	// Step 1: Collect levels and observation counts
	// ---------------------------------------------------------------------------
	quietly levelsof `varlist', local(levels)

	local n_levels 0
	local n_total  0

	foreach l of local levels {
		quietly count if `varlist' == `l'
		local n`n_levels' = r(N)          // count for level index n_levels
		local n_total = `n_total' + r(N)
		local ++n_levels
	}

	if `n_levels' == 0 {
		display as error "Variable `varlist' has no non-missing levels."
		exit 2000
	}

	// ---------------------------------------------------------------------------
	// Step 2: Build matrices  cum_p (cumulative probability),
	//                         phi_inv (invnormal of cum_p),
	//                         phi_den (standard normal density at phi_inv)
	// ---------------------------------------------------------------------------
	matrix _gcu_p    = J(`n_levels', 1, .)   // cumulative probabilities
	matrix _gcu_finv = J(`n_levels', 1, .)   // invnormal(cum_p)
	matrix _gcu_f    = J(`n_levels', 1, .)   // normalden(invnormal(cum_p))
	matrix _gcu_u    = J(`n_levels', 1, .)   // utility scores

	local cum_count 0
	forvalues i = 1/`n_levels' {
		local idx = `i' - 1
		local cum_count = `cum_count' + `n`idx''
		local cp = `cum_count' / `n_total'

		matrix _gcu_p[`i', 1] = `cp'

		local z = invnormal(`cp')
		matrix _gcu_finv[`i', 1] = `z'

		if `cp' >= 1 {
			// density at +inf is 0
			matrix _gcu_f[`i', 1] = 0
		}
		else {
			matrix _gcu_f[`i', 1] = normalden(`z', 0, 1)
		}
	}

	// ---------------------------------------------------------------------------
	// Step 3: Compute utility scores
	//   For i == 1  :  u_1 = (0 - f_1) / p_1
	//   For i > 1   :  u_i = (f_{i-1} - f_i) / (p_i - p_{i-1})
	// ---------------------------------------------------------------------------
	forvalues i = 1/`n_levels' {
		local fi = _gcu_f[`i', 1]
		local pi = _gcu_p[`i', 1]

		if `i' == 1 {
			matrix _gcu_u[`i', 1] = (0 - `fi') / `pi'
		}
		else {
			local j = `i' - 1
			local fj = _gcu_f[`j', 1]
			local pj = _gcu_p[`j', 1]
			matrix _gcu_u[`i', 1] = (`fj' - `fi') / (`pi' - `pj')
		}
	}

	// ---------------------------------------------------------------------------
	// Step 4: Assign utility scores to output variable and (optionally) display
	// ---------------------------------------------------------------------------
	quietly generate double `generate' = .

	if "`display'" != "" {
		display as text _col(5) "Level" _col(20) "Utility"
		display as text _col(5) "{hline 30}"
	}

	local i 0
	foreach l of local levels {
		local ++i
		local u_val = _gcu_u[`i', 1]
		quietly replace `generate' = `u_val' if `varlist' == `l'

		if "`display'" != "" {
			display as text _col(5) "`l'" _col(20) as result %12.6f `u_val'
		}
	}

	// ---------------------------------------------------------------------------
	// Step 5: Clean up temporary matrices and return results
	// ---------------------------------------------------------------------------
	matrix drop _gcu_p _gcu_finv _gcu_f _gcu_u

	return scalar n_levels = `n_levels'
	return scalar n_obs    = `n_total'
	return local  levels   = "`levels'"
	return local  varname  = "`varlist'"
	return local  generate = "`generate'"
end
