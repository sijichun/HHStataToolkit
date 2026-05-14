*! dta2md v1.2.0 — Export .dta metadata & descriptive statistics to Markdown
*! Author: VibeStata project
*! Requires: Stata 16.0+

capture program drop dta2md
program define dta2md
    version 16.0
    syntax anything(name=filepath) [using/] [, DEScriptive MAXCat(integer 20) MAXFreq(integer 30) ENGlish VARList(varlist) LABeled]

    * ── 0. Set up titles based on language ───────────────────────────────────
    if "`english'" == "" {
        local ttl_dataset   "数据集概览"
        local ttl_varlist   "变量清单"
        local ttl_vardetail "变量详情"
        local lbl_varnum    "#"
        local lbl_varname   "变量名"
        local lbl_vartype  "类型"
        local lbl_varlbl   "变量标签"
        local lbl_datalbl  "数据集标签"
        local lbl_fname    "文件名"
        local lbl_nobs     "观测数"
        local lbl_nvar     "变量数"
        local lbl_panelvar "面板个体变量"
        local lbl_timevar  "时间变量"
        local lbl_strvar   "字符串变量"
        local lbl_numvar   "数值型变量（连续型）"
        local lbl_valnum   "有值标签的数值型变量，值标签名"
        local lbl_nuniq    "唯一值数量"
        local lbl_nmiss    "缺失值数量"
        local lbl_value    "值"
        local lbl_freq     "频数"
        local lbl_pct      "占比(%)"
        local lbl_vallbl  "值标签"
        local lbl_stat    "统计量"
        local lbl_val     "值"
        local lbl_N        "N"
        local lbl_mean     "均值"
        local lbl_sd       "标准差"
        local lbl_min      "最小值"
        local lbl_max      "最大值"
        local lbl_negpct   "<0 的比例"
    }
    else {
        local ttl_dataset   "Dataset Overview"
        local ttl_varlist   "Variable List"
        local ttl_vardetail "Variable Details"
        local lbl_varnum    "#"
        local lbl_varname   "Variable Name"
        local lbl_vartype   "Type"
        local lbl_varlbl    "Variable Label"
        local lbl_datalbl   "Dataset Label"
        local lbl_fname     "File Name"
        local lbl_nobs      "Observations"
        local lbl_nvar       "Variables"
        local lbl_panelvar  "Panel ID Variable"
        local lbl_timevar   "Time Variable"
        local lbl_strvar    "String Variable"
        local lbl_numvar    "Numeric Variable (Continuous)"
        local lbl_valnum    "Numeric Variable with Value Labels, Label Name"
        local lbl_nuniq     "Unique Values"
        local lbl_nmiss     "Missing Values"
        local lbl_value     "Value"
        local lbl_freq      "Frequency"
        local lbl_pct       "Percent(%)"
        local lbl_vallbl    "Value Label"
        local lbl_stat      "Statistic"
        local lbl_val       "Value"
        local lbl_N         "N"
        local lbl_mean      "Mean"
        local lbl_sd        "SD"
        local lbl_min       "Min"
        local lbl_max       "Max"
        local lbl_negpct    "Proportion <0"
    }

    * ── 0. Parse file path ────────────────────────────────────────────────
    * Remove surrounding quotes if present
    local filepath `filepath'
    local filepath : subinstr local filepath `"""' "", all
    local filepath : subinstr local filepath `"'"' "", all

    * Verify file exists
    capture confirm file "`filepath'"
    if _rc {
        display as error `"文件不存在: `filepath'"'
        exit 601
    }

    * Build output path: use `using' if specified, otherwise default
    _dta2md_output_path "`filepath'"
    local fname "`s(fname)'"
    if `"`using'"' != "" {
        local mdpath `"`using'"'
    }
    else {
        local mdpath "`s(mdpath)'"
    }

    * ── 1. Load data in temporary frame ───────────────────────────────────
    tempname frm
    frame create `frm'
    frame `frm': quietly use "`filepath'", clear

    * Build variable list based on options
    frame `frm' {
        * If varlist() specified, verify variables exist
        if `"`varlist'"' != "" {
            foreach v of local varlist {
                capture confirm variable `v'
                if _rc {
                    display as error `"变量不存在: `v'"'
                    exit 111
                }
            }
            local export_vars `varlist'
        }
        else {
            * Default: all variables
            quietly ds
            local export_vars `r(varlist)'
        }

        * If labeled option, filter to only labeled variables
        if "`labeled'" != "" {
            local labeled_vars ""
            foreach v of local export_vars {
                local vlbl : variable label `v'
                if `"`vlbl'"' != "" {
                    local labeled_vars `"`labeled_vars' `v'"'
                }
            }
            local export_vars `labeled_vars'
        }
    }

    local nvar_export : word count `export_vars'

    * Open output file
    tempname fh
    file open `fh' using "`mdpath'", write replace text

    display as text ""
    display as text "dta2md: 正在导出元数据..."
    display as text `"  输入: `filepath'"'
    display as text `"  输出: `mdpath'"'
    if "`descriptive'" != "" {
        display as text `"  阈值: maxcat(`maxcat') maxfreq(`maxfreq')"'
    }
    else {
        display as text "  模式: simple（仅概览和变量清单）"
    }
    display as text ""

    * ── 2. Dataset overview ───────────────────────────────────────────────
    frame `frm' {
        local datalabel : data label
        local nobs = _N
        quietly describe, short
        local nvar = r(k)
        quietly ds
        local allvars `r(varlist)'

        file write `fh' "# `ttl_dataset'" _n _n

        if `"`datalabel'"' != "" {
            file write `fh' `"- **`lbl_datalbl'**: `datalabel'"' _n
        }
        file write `fh' `"- **`lbl_fname'**: `fname'"' _n
        local nobs_fmt : display %12.0fc (`nobs')
        local nobs_fmt = strtrim("`nobs_fmt'")
        file write `fh' "- **`lbl_nobs'**: `nobs_fmt'" _n
        file write `fh' "- **`lbl_nvar'**: `nvar'" _n

        * Detect panel / time-series structure
        capture xtset
        if !_rc {
            local panelvar "`r(panelvar)'"
            local timevar  "`r(timevar)'"
            if "`panelvar'" != "" {
                file write `fh' `"- **`lbl_panelvar'**: `panelvar'"' _n
            }
            if "`timevar'" != "" {
                file write `fh' `"- **`lbl_timevar'**: `timevar'"' _n
            }
        }
        else {
            capture tsset
            if !_rc {
                local timevar "`r(timevar)'"
                if "`timevar'" != "" {
                    file write `fh' `"- **`lbl_timevar'**: `timevar'"' _n
                }
            }
        }

        file write `fh' _n

        * ── 3. Variable list table ────────────────────────────────────────
        file write `fh' "# `ttl_varlist'" _n _n
        file write `fh' "| `lbl_varnum' | `lbl_varname' | `lbl_vartype' | `lbl_varlbl' |" _n
        file write `fh' "|---|--------|------|----------|" _n

        local i = 0

        foreach v of local export_vars {
            local ++i
            local vtype : type `v'
            local vlbl  : variable label `v'
            * Escape pipe characters in label
            local vlbl : subinstr local vlbl "|" "\|", all
            file write `fh' "| `i' | `v' | `vtype' | `vlbl' |" _n
        }

        file write `fh' _n

        * ── 4. Per-variable details (if descriptive option) ─────────────────
        if "`descriptive'" != "" {

        file write `fh' "# `ttl_vardetail'" _n _n

        local i = 0
        foreach v of local export_vars {
            local ++i

            local vlbl : variable label `v'
            local vlbl : subinstr local vlbl "|" "\|", all
            local vtype : type `v'

            * Determine if string
            local isstr = (substr("`vtype'", 1, 3) == "str")

            if `isstr' {
                * ── String variable ───────────────────────────────────────
                if `"`vlbl'"' != "" {
                    file write `fh' `"## `v' (`vlbl')"' _n _n
                }
                else {
                    file write `fh' "## `v'" _n _n
                }
                file write `fh' "`lbl_strvar'" _n _n

                * Count unique values (capture in case of empty data)
                capture quietly tab `v'
                if _rc {
                    local nuniq = 0
                }
                else {
                    local nuniq = r(r)
                }
                * Count missing
                quietly count if missing(`v')
                local nmiss = r(N)

                if `nuniq' <= `maxcat' & `nuniq' <= `maxfreq' {
                    file write `fh' "`lbl_nuniq': `nuniq'" _n _n
                    file write `fh' "| `lbl_value' | `lbl_freq' | `lbl_pct' |" _n
                    file write `fh' "|----|------|---------|" _n

                    * Get levels
                    quietly levelsof `v', local(lvls)
                    local total_valid = `nobs' - `nmiss'
                    foreach lv of local lvls {
                        quietly count if `v' == `"`lv'"'
                        local freq = r(N)
                        if `total_valid' > 0 {
                            local pct : display %5.1f (`freq' / `total_valid' * 100)
                            local pct = strtrim("`pct'")
                        }
                        else {
                            local pct "—"
                        }
                        * Escape pipe in value
                        local lv_esc `"`lv'"'
                        local lv_esc : subinstr local lv_esc "|" "\|", all
                        local freq_fmt : display %12.0fc (`freq')
                        local freq_fmt = strtrim("`freq_fmt'")
                        file write `fh' `"| `lv_esc' | `freq_fmt' | `pct' |"' _n
                    }
                    if `nmiss' > 0 {
                        local mpct : display %5.1f (`nmiss' / `nobs' * 100)
                        local mpct = strtrim("`mpct'")
                        local nmiss_fmt : display %12.0fc (`nmiss')
                        local nmiss_fmt = strtrim("`nmiss_fmt'")
                        file write `fh' "| *(缺失)* | `nmiss_fmt' | `mpct' |" _n
                    }
                }
                else {
                    file write `fh' "- **`lbl_nuniq'**: `nuniq'" _n
                    if `nmiss' > 0 {
                        local nmiss_fmt : display %12.0fc (`nmiss')
                        local nmiss_fmt = strtrim("`nmiss_fmt'")
                        file write `fh' "- **`lbl_nmiss'**: `nmiss_fmt'" _n
                    }
                }

                file write `fh' _n
            }
            else {
                * ── Numeric variable ──────────────────────────────────────
                local vallbl : value label `v'

                if `"`vlbl'"' != "" {
                    file write `fh' `"## `v' (`vlbl')"' _n _n
                }
                else {
                    file write `fh' "## `v'" _n _n
                }

                * Count unique non-missing values (capture in case of error)
                capture quietly tab `v'
                if _rc {
                    local nuniq = 999999
                }
                else {
                    local nuniq = r(r)
                }

                if `"`vallbl'"' != "" & `nuniq' <= `maxcat' & `nuniq' <= `maxfreq' {
                    * ── Labeled numeric: frequency table ──────────────────
                    file write `fh' `"`lbl_valnum': `vallbl'"' _n _n

                    file write `fh' "| `lbl_value' | `lbl_vallbl' | `lbl_freq' | `lbl_pct' |" _n
                    file write `fh' "|------|--------|------|---------|" _n

                    * Use tab with matrow/matcell
                    quietly tab `v', matrow(__R) matcell(__C)
                    local nrows = r(r)
                    quietly count if missing(`v')
                    local nmiss = r(N)
                    local total_valid = `nobs' - `nmiss'

                    forvalues j = 1/`nrows' {
                        local val = __R[`j', 1]
                        local freq = __C[`j', 1]
                        * Get value label text
                        local vltxt : label `vallbl' `val'
                        local vltxt : subinstr local vltxt "|" "\|", all
                        if `total_valid' > 0 {
                            local pct : display %5.1f (`freq' / `total_valid' * 100)
                            local pct = strtrim("`pct'")
                        }
                        else {
                            local pct "—"
                        }
                        * Format val — show integer if integer
                        local val_fmt : display %12.0g (`val')
                        local val_fmt = strtrim("`val_fmt'")
                        local freq_fmt : display %12.0fc (`freq')
                        local freq_fmt = strtrim("`freq_fmt'")
                        file write `fh' "| `val_fmt' | `vltxt' | `freq_fmt' | `pct' |" _n
                    }

                    if `nmiss' > 0 {
                        local mpct : display %5.1f (`nmiss' / `nobs' * 100)
                        local mpct = strtrim("`mpct'")
                        local nmiss_fmt : display %12.0fc (`nmiss')
                        local nmiss_fmt = strtrim("`nmiss_fmt'")
                        file write `fh' "| . | *(缺失)* | `nmiss_fmt' | `mpct' |" _n
                    }

                    * Clean up matrices
                    capture matrix drop __R
                    capture matrix drop __C

                    file write `fh' _n
                }
                else {
                    * ── Numeric: descriptive statistics ───────────────────
                    if `"`vallbl'"' != "" {
                        if "`english'" == "" {
                            file write `fh' `"有值标签的数值型变量（唯一值 `nuniq' 个，超过阈值 `maxcat'），值标签名: `vallbl'"' _n _n
                        }
                        else {
                            file write `fh' `"Numeric Variable with Value Labels (unique values `nuniq' exceeds threshold `maxcat'), Label Name: `vallbl'"' _n _n
                        }
                    }
                    else {
                        file write `fh' "`lbl_numvar'" _n _n
                    }

                    quietly summarize `v'
                    local s_n    = r(N)
                    local nmiss  = `nobs' - `s_n'

                    file write `fh' "| `lbl_stat' | `lbl_val' |" _n
                    file write `fh' "|--------|-----|" _n

                    local n_fmt : display %12.0fc (`s_n')
                    local n_fmt = strtrim("`n_fmt'")
                    file write `fh' "| `lbl_N' | `n_fmt' |" _n

                    if `nmiss' > 0 {
                        local nmiss_fmt : display %12.0fc (`nmiss')
                        local nmiss_fmt = strtrim("`nmiss_fmt'")
                        file write `fh' "| `lbl_nmiss' | `nmiss_fmt' |" _n
                    }

                    if `s_n' > 0 {
                        local s_mean = r(mean)
                        local s_sd   = r(sd)
                        local s_min  = r(min)
                        local s_max  = r(max)

                        local mean_fmt : display %12.4g (`s_mean')
                        local mean_fmt = strtrim("`mean_fmt'")
                        file write `fh' "| `lbl_mean' | `mean_fmt' |" _n

                        if `s_n' > 1 {
                            local sd_fmt : display %12.4g (`s_sd')
                            local sd_fmt = strtrim("`sd_fmt'")
                            file write `fh' "| `lbl_sd' | `sd_fmt' |" _n
                        }

                        local min_fmt : display %12.4g (`s_min')
                        local min_fmt = strtrim("`min_fmt'")
                        file write `fh' "| `lbl_min' | `min_fmt' |" _n

                        local max_fmt : display %12.4g (`s_max')
                        local max_fmt = strtrim("`max_fmt'")
                        file write `fh' "| `lbl_max' | `max_fmt' |" _n

                        * If range includes negative values, report <0 proportion
                        if `s_min' < 0 {
                            quietly count if `v' < 0 & !missing(`v')
                            local nneg = r(N)
                            local negpct : display %5.1f (`nneg' / `s_n' * 100)
                            local negpct = strtrim("`negpct'")
                            file write `fh' "| `lbl_negpct' | `negpct'% |" _n
                        }
                    }

                    file write `fh' _n
                }
            }

            * Progress display every 20 variables
            if mod(`i', 20) == 0 {
                display as text "  已处理 `i' / `nvar_export' 个变量..."
            }
        }

        } /* end if descriptive */
    }

    * ── 5. Cleanup ────────────────────────────────────────────────────────
    file close `fh'
    frame drop `frm'

    display as result ""
    display as result "dta2md: 导出完成!"
    display as result `"  输出文件: `mdpath'"'
    if "`descriptive'" != "" {
        display as result "  共导出 `nvar_export' 个变量的元数据和统计信息"
    }
    else {
        display as result "  共导出 `nvar_export' 个变量的基本信息（simple 模式）"
    }
    display as result ""
end

* ── Helper: compute output path ───────────────────────────────────────────
capture program drop _dta2md_output_path
program define _dta2md_output_path, sclass
    version 16.0
    args filepath

    * Extract directory part
    local dir ""
    local fname ""

    * Find last slash or backslash
    local flen = strlen("`filepath'")
    local lastslash = 0
    forvalues p = 1/`flen' {
        local ch = substr("`filepath'", `p', 1)
        if "`ch'" == "/" | "`ch'" == "\" {
            local lastslash = `p'
        }
    }

    if `lastslash' > 0 {
        local dir = substr("`filepath'", 1, `lastslash')
        local fname = substr("`filepath'", `lastslash' + 1, .)
    }
    else {
        local dir ""
        local fname "`filepath'"
    }

    * Remove .dta extension
    local base "`fname'"
    local base : subinstr local base ".dta" ""
    local base : subinstr local base ".DTA" ""

    local mdpath "`dir'`base'_metadata.md"

    sreturn local mdpath "`mdpath'"
    sreturn local fname  "`fname'"
end
