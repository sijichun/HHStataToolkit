*! bprecall 1.0.0  08may2026
* Precision, recall, accuracy, and F1 at multiple classification thresholds

program define bprecall, rclass
	version 16

	syntax varlist(min=2 max=2) [if] [in] [, Divide(integer 9)]

	// Parse varlist: depvar (0/1) and predicted probability
	tokenize `varlist'
	local y    `1'
	local phat `2'

	// Validate divide()
	if `divide' < 1 {
		di as error "divide() must be a positive integer"
		exit 198
	}

	marksample touse

	tempvar yhat tp fp tn fn

	qui {
		gen byte `yhat' = 0 if `touse'
		gen byte `tp'   = 0 if `touse'
		gen byte `fp'   = 0 if `touse'
		gen byte `tn'   = 0 if `touse'
		gen byte `fn'   = 0 if `touse'
	}

	// Print table header
	di ""
	di as text %8s "Threshold" _col(20) %8s "Precision" _col(32) %8s "Recall" ///
	           _col(43) %8s "Accuracy" _col(54) %8s "F1"
	di as text "{hline 62}"

	// Store results in matrices for rreturn
	tempname mat_results
	matrix `mat_results' = J(`divide', 5, .)

	forvalues i = 1/`divide' {

		local c = `i' / (`divide' + 1)

		qui {
			replace `yhat' = (`phat' > `c') if `touse'

			replace `tp' = ((`y' == 1) & (`yhat' == 1)) if `touse'
			summarize `tp' if `touse', meanonly
			local ntp = r(sum)

			replace `fp' = ((`y' == 0) & (`yhat' == 1)) if `touse'
			summarize `fp' if `touse', meanonly
			local nfp = r(sum)

			replace `tn' = ((`y' == 0) & (`yhat' == 0)) if `touse'
			summarize `tn' if `touse', meanonly
			local ntn = r(sum)

			replace `fn' = ((`y' == 1) & (`yhat' == 0)) if `touse'
			summarize `fn' if `touse', meanonly
			local nfn = r(sum)
		}

		// Compute metrics (guard against division by zero)
		if (`ntp' + `nfp') > 0 {
			local precision = `ntp' / (`ntp' + `nfp')
		}
		else {
			local precision = .
		}

		if (`ntp' + `nfn') > 0 {
			local recall = `ntp' / (`ntp' + `nfn')
		}
		else {
			local recall = .
		}

		local denom = `ntp' + `nfp' + `ntn' + `nfn'
		if `denom' > 0 {
			local accuracy = (`ntp' + `ntn') / `denom'
		}
		else {
			local accuracy = .
		}

		if !missing(`precision') & !missing(`recall') & (`precision' + `recall') > 0 {
			local f1 = (2 * `precision' * `recall') / (`precision' + `recall')
		}
		else {
			local f1 = .
		}

		// Display row
		di as result %8.3f `c'        _col(20) %8.3f `precision' ///
		             _col(32) %8.3f `recall'   _col(43) %8.3f `accuracy' ///
		             _col(54) %8.3f `f1'

		// Store in matrix
		matrix `mat_results'[`i', 1] = `c'
		matrix `mat_results'[`i', 2] = `precision'
		matrix `mat_results'[`i', 3] = `recall'
		matrix `mat_results'[`i', 4] = `accuracy'
		matrix `mat_results'[`i', 5] = `f1'
	}

	di as text "{hline 62}"

	// Label matrix and return
	matrix colnames `mat_results' = threshold precision recall accuracy f1
	return matrix results = `mat_results'
	return scalar divide = `divide'

end
