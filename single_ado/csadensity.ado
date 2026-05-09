*! csadensity 1.0.0  10may2026
program define csadensity, rclass
	version 14
	
	syntax varlist(min=1 numeric) [if] [in] ///
		[, TREatment(varname numeric) ///
		   GENerate(name) ///
		   THreshold(real 0.2) ///
		   GRoup(varlist) ///
		   Kernel(string) ///
		   BW(string) ///
		   DEBUG ]
	
	/* Validate required options */
	if "`treatment'" == "" {
		display as error "treatment() is required"
		exit 198
	}
	
	if "`generate'" == "" {
		display as error "generate() is required"
		exit 198
	}
	
	/* Create touse marker from if/in */
	marksample touse, novarlist
	
	/* Verify all varlist variables are numeric */
	local numeric_varlist ""
	local tempvars ""
	local markout_vars "`treatment'"
	foreach var of local varlist {
		confirm numeric variable `var'
		local numeric_varlist "`numeric_varlist' `var'"
		local markout_vars "`markout_vars' `var'"
	}
	
	/* Handle group variables: encode string vars to numeric */
	local ngroup = 0
	local groupvars ""
	foreach gv in `group' {
		local ngroup = `ngroup' + 1
		capture confirm numeric variable `gv'
		if _rc {
			/* String group variable: encode using group() */
			tempvar group_num`ngroup'
			quietly egen `group_num`ngroup'' = group(`gv') if `touse'
			local groupvars "`groupvars' `group_num`ngroup''"
			local tempvars "`tempvars' `group_num`ngroup''"
		}
		else {
			local groupvars "`groupvars' `gv'"
			local markout_vars "`markout_vars' `gv'"
		}
	}
	
	/* Exclude observations with missing values in numeric variables */
	markout `touse' `markout_vars'
	
	quietly count if `touse'
	if r(N) < 2 {
		display as error "Need at least 2 observations"
		exit 2001
	}
	
	/* Validate treatment variable */
	quietly tabulate `treatment' if `touse'
	if r(r) != 2 {
		display as error "treatment() variable must contain both 0 and 1"
		exit 198
	}
	
	quietly summarize `treatment' if `touse'
	if r(min) != 0 | r(max) != 1 {
		display as error "treatment() variable must be binary (0 or 1)"
		exit 198
	}
	
	/* Number of dimensions */
	local num_var : word count `varlist'
	
	/* Create complement treatment indicator */
	tempvar ntreatment
	quietly gen double `ntreatment' = 1 - `treatment'
	local tempvars "`tempvars' `ntreatment'"
	
	/* Variable names for density estimates.
	   In debug mode, use fixed names so user can inspect them.
	   Do NOT create them beforehand — kdensity2 must generate
	   new variables itself to match the manual reference result. */
	if "`debug'" != "" {
		local f_t "_csad_f_t"
		local f_nt "_csad_f_nt"
		capture drop _csad_f_t _csad_f_nt _csad_f_geom _csad_f_norm
	}
	else {
		tempvar f_t f_nt
		local tempvars "`tempvars' `f_t' `f_nt'"
	}
	
	/* Build optional arguments for kdensity2 */
	local k_opt "kernel(triweight)"
	if "`kernel'" != "" {
		local k_opt "kernel(`kernel')"
	}
	local bw_opt ""
	if "`bw'" != "" {
		local bw_opt "bw(`bw')"
	}
	local group_opt ""
	if `ngroup' > 0 {
		local group_opt "group(`groupvars')"
	}
	
	/* Call kdensity2 for treatment = 1 group */
	quietly kdensity2 `numeric_varlist', ///
		target(`treatment') ///
		generate(`f_t') ///
		`group_opt' ///
		`k_opt' `bw_opt'
	
	/* Call kdensity2 for treatment = 0 group */
	quietly kdensity2 `numeric_varlist', ///
		target(`ntreatment') ///
		generate(`f_nt') ///
		`group_opt' ///
		`k_opt' `bw_opt'
	
	/* Take minimum of the two density estimates (pointwise).
	   kdensity2 may return missing (.) density values for observations
	   with insufficient support. In Stata, . > any_number is true, so
	   we must explicitly exclude missing values. */
	if "`debug'" != "" {
		local f_geom "_csad_f_geom"
		local f_norm "_csad_f_norm"
	}
	else {
		tempvar f_geom f_norm
		local tempvars "`tempvars' `f_geom'"
	}
	quietly gen double `f_geom' = min(`f_t' , `f_nt') if `touse'
	
	/* Normalize f_geom by its maximum so threshold is scale-invariant */
	quietly summarize `f_geom' if `touse' & !missing(`f_geom')
	local max_f = r(max)
	if `max_f' > 0 {
		quietly gen double `f_norm' = `f_geom' / `max_f' if `touse'
	}
	else {
		quietly gen double `f_norm' = 0 if `touse'
	}
	if "`debug'" == "" {
		local tempvars "`tempvars' `f_norm'"
	}
	else {
		label variable `f_norm' "Normalized geometric mean density"
		label variable `f_geom' "Minimum density (raw)"
		label variable `f_t' "Density under treatment"
		label variable `f_nt' "Density under control"
	}
	
	/* Generate common support area indicator */
	quietly gen byte `generate' = ((`f_norm' > `threshold') & !missing(`f_norm')) if `touse'
	
	/* Clean up temporary variables */
	foreach tv of local tempvars {
		capture drop `tv'
	}
	
	/* Label the output variable */
	label variable `generate' "Common support area indicator"
	
	/* Compute and store results */
	quietly count if `generate' == 1
	local n_csa = r(N)
	quietly count if `touse'
	local n_total = r(N)
	
	return scalar N = `n_total'
	return scalar N_csa = `n_csa'
	return scalar threshold = `threshold'
	return local treatment "`treatment'"
	return local varlist "`varlist'"
	return local groupvars "`group'"
	return local kernel "`kernel'"
	return local bw "`bw'"
	
	/* Display results */
	display as text _n "Common Support Area (CSA)"
	display as text "{hline 40}"
	display as text "Variables:    " as result "`varlist'"
	display as text "Treatment:    " as result "`treatment'"
	if `ngroup' > 0 {
		display as text "Group vars:   " as result "`group'"
	}
	display as text "Observations: " as result `n_total'
	display as text "CSA obs:      " as result `n_csa'
	display as text "Threshold:    " as result `threshold'
	if "`debug'" != "" {
		display as text "Debug:        " as result "_csad_f_t _csad_f_nt _csad_f_geom _csad_f_norm kept"
	}
	display as text "{hline 40}"
	
end
