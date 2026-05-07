*! gen_init_var 1.0.0  2026-05-08
*! Initialize a panel variable from a base-year observation within groups.

program define gen_init_var, rclass
	version 16

	syntax varname, 						///
		yearvar(varname) 					///
		year(string) 						///
		by(varname) 						///
		generate(name) 						///
		[STRINGyear]

	// ----------------------------------------------------------------
	// Validate: ensure the requested base year actually exists
	// ----------------------------------------------------------------
	if "`stringyear'" == "stringyear" {
		quietly count if `yearvar' == "`year'"
	}
	else {
		capture confirm number `year'
		if _rc {
			di as error "option year(): {bf:`year'} is not a valid number"
			di as error "  (specify {bf:stringyear} if year is stored as a string)"
			exit 7
		}
		quietly count if `yearvar' == `year'
	}

	if r(N) == 0 {
		di as error "no observations found where {bf:`yearvar'} == {bf:`year'}"
		exit 2000
	}

	// ----------------------------------------------------------------
	// Check output variable does not already exist
	// ----------------------------------------------------------------
	confirm new variable `generate'

	// ----------------------------------------------------------------
	// Core logic: carry forward base-year value within groups
	// ----------------------------------------------------------------
	tempvar _src

	quietly {
		if "`stringyear'" == "stringyear" {
			generate `_src' = `varlist' if `yearvar' == "`year'"
		}
		else {
			generate `_src' = `varlist' if `yearvar' == `year'
		}
		egen `generate' = min(`_src'), by(`by')
	}

	// ----------------------------------------------------------------
	// Label and return
	// ----------------------------------------------------------------
	label variable `generate' "Initial value of `varlist' (base year `year')"

	return local varname "`generate'"
	return local sourcevar "`varlist'"
	return local yearvar "`yearvar'"
	return local year "`year'"
	return local byvar "`by'"

	di as result "Variable {bf:`generate'} created."
end
