#!/usr/bin/env Rscript

# =============================================================================
# 52_aggregated_firm_sector_first_stage.R - Sector-Level Spec Engine
# =============================================================================
#
# Collapses the firm panel to (sector, muni, year) cells and estimates
# sector-level first-stage IV regressions across a configurable grid of
# 9 dimensions:
#   outcome, exposure, aggregation, regression_weight, sector_var,
#   baseline, alignment, fe, exposure_control
#
# USAGE:
#   Rscript run_politicsregs.R 52 [OPTIONS]
#
# OPTIONS:
#   --specs=NAME[,NAME]              Named bundles (default: baseline)
#   --outcome=VAL[,VAL]              bndes_extensive, bndes_share, log_employment, employment_share
#   --exposure=VAL[,VAL]             pooled_count, binary
#   --aggregation=VAL[,VAL]          owner_count, equal_firm, employment
#   --regression-weight=VAL[,VAL]    unweighted, emp_weighted, emp_share_weighted, n_firms_weighted
#   --sector-var=VAL[,VAL]           cnae_section, custom_sector, bndes_sector, size_bin,
#                                    cnae_size_bin, sector_group_size_bin
#   --baseline=VAL[,VAL]             cycle_specific, 2002_fixed
#   --alignment=VAL[,VAL]            coalition, party
#   --fe=VAL[,VAL]                   mxj_jxt, mxj_mxt
#   --exposure-control=VAL[,VAL]     yes, no
#   --family=VAL[,VAL]               main, interaction_mqemp
#   --muni-sample=VAL[,VAL]          all, top_q4, bottom_3q
#   --test                           10% municipality subsample
#   --dry-run                        Print resolved configs and exit
#
# NAMED BUNDLES:
#   baseline             - all defaults (bndes_extensive, owner_count, unweighted, etc.)
#   emp_weighted         - aggregation=employment, regression_weight=emp_weighted
#   emp_share_weighted   - regression_weight=emp_share_weighted (muni emp-share weights)
#   equal_firm           - aggregation=equal_firm
#   party                - alignment=party
#   fixed_baseline       - baseline=2002_fixed
#   binary               - exposure=binary
#   fe_muni_year         - fe=mxj_mxt
#   no_controls          - exposure_control=no
#   all_outcomes         - all 4 outcomes
#   all_sectors          - all 4 sector classifications (cnae_section/custom_sector/bndes_sector/size_bin)
#   weight_battery       - all 3 aggregation weights
#   interaction_muni_emp - family=interaction_mqemp (instruments × top_q4_muni)
#   top_q4_sample        - muni_sample=top_q4 (top-quartile municipalities only)
#   bottom_3q_sample     - muni_sample=bottom_3q (bottom-three-quartile municipalities)
#   size_bin_battery     - sector_var loops over cnae_section/custom_sector/cnae_size_bin/sector_group_size_bin
#
# INSTRUMENT COMBOS:
#   M, G, P, M+G, M+P, M+G+P (main family only)
#
# OUTPUT:
#   Tables:   paper/tables/agg_firm_{sector_var}/agg_firm__<slug>.tex
#   Manifest: paper/tables/agg_firm_{sector_var}/agg_firm_run_manifest.csv/.qs2
#   Summary:  paper/tables/agg_firm_{sector_var}/agg_firm_fc_battery_summary.qs2
#
# =============================================================================

cat("==============================================================================\n")
cat("Aggregated Firm -> Sector First Stage (Spec Engine)\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})

# Bootstrap shared path helpers from this script location.
bootstrap_file <- local({
  project_root_opt <- getOption("politicsregs.project_root", default = NULL)
  if (is.character(project_root_opt) && length(project_root_opt) == 1L && nzchar(project_root_opt)) {
    return(file.path(project_root_opt, "scripts", "R", "_utils", "script_bootstrap.R"))
  }

  script_args_full <- commandArgs(trailingOnly = FALSE)
  script_file <- grep("^--file=", script_args_full, value = TRUE)
  if (length(script_file)) {
    script_file <- normalizePath(sub("^--file=", "", script_file[[1L]]), winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }

  frame_paths <- vapply(sys.frames(), function(env) {
    ofile <- env$ofile
    if (is.null(ofile) || !nzchar(ofile)) return(NA_character_)
    ofile
  }, character(1))
  frame_paths <- frame_paths[!is.na(frame_paths)]
  if (length(frame_paths)) {
    script_file <- normalizePath(frame_paths[[length(frame_paths)]], winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }

  stop("Cannot determine bootstrap path. In an interactive session, call `init_politicsregs_session()` first.")
})
source(normalizePath(bootstrap_file, winslash = "/", mustWork = TRUE))
bootstrap_politicsregs()

setDTthreads(1L)
fixest::setFixest_nthreads(10L)

source(politicsregs_path("_utils", "beamer_tables.R"))
source(politicsregs_path("_utils", "load_firm_panel.R"))

# =============================================================================
# Spec Engine Configuration
# =============================================================================

DIMENSION_OPTIONS <- list(
  outcome          = c("bndes_extensive", "bndes_share", "log_employment", "employment_share"),
  exposure         = c("pooled_count", "binary"),
  aggregation      = c("owner_count", "equal_firm", "employment"),
  regression_weight = c("unweighted", "emp_weighted", "emp_share_weighted", "n_firms_weighted"),
  sector_var       = c("cnae_section", "custom_sector", "bndes_sector", "size_bin",
                       "cnae_size_bin", "sector_group_size_bin", "bndes_sector_size_bin"),
  baseline         = c("cycle_specific", "2002_fixed"),
  alignment        = c("coalition", "party"),
  fe               = c("mxj_jxt", "mxj_mxt"),
  exposure_control = c("yes", "no"),
  family           = c("main", "interaction_mqemp"),
  muni_sample      = c("all", "top_q4", "bottom_3q")
)

DEFAULT_DIMENSIONS <- list(
  outcome          = "bndes_extensive",
  exposure         = "pooled_count",
  aggregation      = "owner_count",
  regression_weight = "unweighted",
  sector_var       = "custom_sector",
  baseline         = "cycle_specific",
  alignment        = "coalition",
  fe               = "mxj_jxt",
  exposure_control = "yes",
  family           = "main",
  muni_sample      = "all"
)

SPEC_CATALOG <- list(
  baseline             = list(),
  emp_weighted         = list(aggregation = "employment", regression_weight = "emp_weighted"),
  emp_share_weighted   = list(regression_weight = "emp_share_weighted"),
  n_firms_weighted     = list(regression_weight = "n_firms_weighted"),
  equal_firm           = list(aggregation = "equal_firm"),
  party                = list(alignment = "party"),
  fixed_baseline       = list(baseline = "2002_fixed"),
  binary               = list(exposure = "binary"),
  fe_muni_year         = list(fe = "mxj_mxt"),
  no_controls          = list(exposure_control = "no"),
  all_outcomes         = list(outcome = c("bndes_extensive", "bndes_share", "log_employment", "employment_share")),
  all_sectors          = list(sector_var = c("cnae_section", "custom_sector", "bndes_sector", "size_bin")),
  weight_battery       = list(aggregation = c("owner_count", "equal_firm", "employment")),
  interaction_muni_emp = list(family = "interaction_mqemp"),
  top_q4_sample        = list(muni_sample = "top_q4"),
  bottom_3q_sample     = list(muni_sample = "bottom_3q"),
  size_bin_battery     = list(sector_var = c("cnae_section", "custom_sector",
                                             "cnae_size_bin", "sector_group_size_bin",
                                             "bndes_sector_size_bin"))
)

COMBOS <- c("M", "G", "P", "M+G", "M+P", "M+G+P")
MAYOR_TREATMENT_YEARS <- c(2005L, 2009L, 2013L, 2017L)
GP_TREATMENT_YEARS <- c(2007L, 2011L, 2015L)
CONTROL_COLS <- c(
  "control_share_mayor",
  "control_share_gp",
  "control_binary_mayor",
  "control_binary_gp"
)

DEPVAR_INFO <- list(
  bndes_extensive = list(
    depvar = "Y_bndes_extensive",
    dep_label = "$\\text{Share of firms receiving a BNDES loan}_{jmt}$",
    sample_note = NA_character_
  ),
  bndes_share = list(
    depvar = "Y_bndes_share",
    dep_label = "$\\text{BNDES share}_{jmt}$",
    sample_note = NA_character_
  ),
  log_employment = list(
    depvar = "Y_log_employment",
    dep_label = "$\\log(\\text{Emp}_{jmt})$",
    sample_note = NA_character_
  ),
  employment_share = list(
    depvar = "Y_employment_share",
    dep_label = "$\\text{Emp share}_{jmt}$",
    sample_note = NA_character_
  )
)

# =============================================================================
# Utility Functions
# =============================================================================

weighted_mean_safe <- function(x, w) {
  ok <- !is.na(x) & !is.na(w) & is.finite(w) & w > 0
  if (!any(ok)) return(NA_real_)
  sum(x[ok] * w[ok]) / sum(w[ok])
}

mean_if_any <- function(x) {
  ok <- !is.na(x)
  if (!any(ok)) return(NA_real_)
  mean(x[ok], na.rm = TRUE)
}

sum_if_any <- function(x) {
  ok <- !is.na(x) & is.finite(x)
  if (!any(ok)) return(NA_real_)
  sum(x[ok], na.rm = TRUE)
}

safe_wald <- function(mod, keep = "^FA_bar_") {
  if (is.null(mod)) return(NA_real_)
  tryCatch(fixest::wald(mod, keep = keep)$stat, error = function(e) NA_real_)
}

write_csv_atomic <- function(dt, path) {
  tmp <- tempfile(pattern = "agg-firm-", tmpdir = dirname(path), fileext = ".csv")
  fwrite(dt, tmp)
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Failed to write file: ", path)
}

write_qs_atomic <- function(obj, path) {
  tmp <- tempfile(pattern = "agg-firm-", tmpdir = dirname(path), fileext = ".qs2")
  qs_save(obj, tmp)
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Failed to write file: ", path)
}

read_existing_artifact <- function(path, reader) {
  if (!file.exists(path)) return(NULL)
  tryCatch(reader(path), error = function(e) {
    cat(sprintf("WARNING: failed to read existing artifact '%s': %s\n", path, conditionMessage(e)))
    NULL
  })
}

merge_existing_runs <- function(existing_dt, new_dt, replace_slugs, order_cols = NULL) {
  if (is.null(existing_dt) || !nrow(existing_dt)) {
    out <- copy(new_dt)
  } else if (is.null(new_dt) || !nrow(new_dt)) {
    out <- copy(existing_dt)
  } else {
    existing_dt <- as.data.table(existing_dt)
    new_dt <- as.data.table(new_dt)
    if ("canonical_slug" %in% names(existing_dt)) {
      existing_dt <- existing_dt[!canonical_slug %in% replace_slugs]
    }
    out <- rbindlist(list(existing_dt, new_dt), fill = TRUE, use.names = TRUE)
  }
  if (!is.null(order_cols)) {
    order_cols <- order_cols[order_cols %in% names(out)]
    if (length(order_cols)) setorderv(out, order_cols)
  }
  out
}

# =============================================================================
# CLI Parsing (mirrors script 51 / script 53)
# =============================================================================

normalize_dimension_name <- function(name) {
  gsub("-", "_", name)
}

valid_option_flags <- function() {
  c(
    "--specs",
    "--outcome",
    "--exposure",
    "--aggregation",
    "--regression-weight", "--regression_weight",
    "--sector-var", "--sector_var",
    "--baseline",
    "--alignment",
    "--fe",
    "--exposure-control", "--exposure_control",
    "--family",
    "--muni-sample", "--muni_sample",
    "--test",
    "--dry-run"
  )
}

build_slug <- function(row) {
  parts <- c(
    "agg_firm",
    row$sector_var,
    row$outcome,
    row$alignment,
    row$baseline,
    row$aggregation,
    row$regression_weight,
    row$fe,
    if (identical(row$exposure_control, "yes")) "ctrl" else "noctrl",
    row$exposure
  )
  # Append non-default dimensions only (preserves existing slug structure)
  if (!is.null(row$family) && !identical(row$family, "main")) {
    parts <- c(parts, row$family)
  }
  if (!is.null(row$muni_sample) && !identical(row$muni_sample, "all")) {
    parts <- c(parts, row$muni_sample)
  }
  paste(parts, sep = "__", collapse = "__")
}

merge_dimension_overrides <- function(base_dims, overrides) {
  out <- base_dims
  for (nm in names(overrides)) out[[nm]] <- overrides[[nm]]
  out
}

expand_dimension_grid <- function(dim_list) {
  as.data.table(expand.grid(
    dim_list,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  ))
}

parse_cli_args <- function(args) {
  parsed <- list(
    spec_names = "baseline",
    dim_overrides = list(),
    test = FALSE,
    dry_run = FALSE
  )

  valid_dims <- names(DIMENSION_OPTIONS)

  for (arg in args) {
    if (identical(arg, "--test")) { parsed$test <- TRUE; next }
    if (identical(arg, "--dry-run")) { parsed$dry_run <- TRUE; next }

    if (!grepl("^--[^=]+=", arg)) {
      stop("Unknown option: ", arg, ". Valid options: ", paste(valid_option_flags(), collapse = ", "))
    }

    key <- sub("^--([^=]+)=.*$", "\\1", arg)
    value <- sub("^--[^=]+=", "", arg)
    key <- normalize_dimension_name(key)

    if (!nzchar(value)) stop("Option requires a value: --", key)

    values <- strsplit(value, ",", fixed = TRUE)[[1L]]
    values <- trimws(values)
    values <- values[nzchar(values)]
    if (!length(values)) stop("Option requires at least one value: --", key)

    if (identical(key, "specs")) {
      spec_names <- unique(values)
      if ("all" %in% spec_names) spec_names <- names(SPEC_CATALOG)
      unknown_specs <- setdiff(spec_names, names(SPEC_CATALOG))
      if (length(unknown_specs)) {
        stop("Unknown spec bundle: ", paste(unknown_specs, collapse = ", "),
             ". Valid: ", paste(c(names(SPEC_CATALOG), "all"), collapse = ", "))
      }
      parsed$spec_names <- spec_names
      next
    }

    if (!key %in% valid_dims) {
      stop("Unknown option: --", key, ". Valid options: ", paste(valid_option_flags(), collapse = ", "))
    }

    invalid_vals <- setdiff(values, DIMENSION_OPTIONS[[key]])
    if (length(invalid_vals)) {
      stop("Invalid value '", invalid_vals[[1L]], "' for --", key,
           ". Valid: ", paste(DIMENSION_OPTIONS[[key]], collapse = ", "))
    }

    parsed$dim_overrides[[key]] <- unique(values)
  }

  parsed
}

resolve_requested_configs <- function(parsed_args) {
  seeded_configs <- vector("list", length(parsed_args$spec_names))
  for (i in seq_along(parsed_args$spec_names)) {
    spec_name <- parsed_args$spec_names[[i]]
    seeded <- merge_dimension_overrides(DEFAULT_DIMENSIONS, SPEC_CATALOG[[spec_name]])

    for (nm in names(parsed_args$dim_overrides)) {
      bundle_value <- SPEC_CATALOG[[spec_name]][[nm]]
      override_vals <- parsed_args$dim_overrides[[nm]]
      if (!is.null(bundle_value) && !all(bundle_value %in% override_vals)) {
        cat(sprintf("WARNING: --%s=%s overrides the defining dimension of bundle '%s'.\n",
                    gsub("_", "-", nm), paste(override_vals, collapse = ","), spec_name))
      }
    }

    seeded <- merge_dimension_overrides(seeded, parsed_args$dim_overrides)
    seeded_configs[[i]] <- expand_dimension_grid(seeded)
  }

  config_dt <- unique(rbindlist(seeded_configs, fill = TRUE))
  config_dt[, canonical_slug := vapply(seq_len(.N), function(i) build_slug(config_dt[i]), character(1))]
  config_dt[, baseline_ord := match(baseline, c("cycle_specific", "2002_fixed"))]
  setorder(config_dt, sector_var, baseline_ord, canonical_slug)
  config_dt[, baseline_ord := NULL]
  config_dt
}

print_config_table <- function(config_dt) {
  print(config_dt[, .(
    canonical_slug,
    outcome, exposure, aggregation, regression_weight,
    sector_var, baseline, alignment, fe, exposure_control,
    family, muni_sample
  )])
}

# =============================================================================
# F_pre Support Map (same as script 52 original)
# =============================================================================

build_f_pre_year_map <- function() {
  term_specs <- list(
    list(current_years = 2005L:2008L, baseline_years = 2002L:2003L),
    list(current_years = 2009L:2012L, baseline_years = 2004L:2007L),
    list(current_years = 2013L:2016L, baseline_years = 2008L:2011L),
    list(current_years = 2017L:2017L, baseline_years = 2012L:2015L),
    list(current_years = 2007L:2010L, baseline_years = 2002L:2005L),
    list(current_years = 2011L:2014L, baseline_years = 2006L:2009L),
    list(current_years = 2015L:2017L, baseline_years = 2010L:2013L)
  )
  year_map <- rbindlist(lapply(term_specs, function(spec) {
    CJ(year = spec$current_years, baseline_year = spec$baseline_years, unique = TRUE)
  }))
  unique(year_map[baseline_year >= 2002L & baseline_year <= 2017L])
}

mayor_treatment_year <- function(year) {
  fcase(
    year >= 2005L & year <= 2008L, 2005L,
    year >= 2009L & year <= 2012L, 2009L,
    year >= 2013L & year <= 2016L, 2013L,
    year == 2017L, 2017L,
    default = NA_integer_
  )
}

gp_treatment_year <- function(year) {
  fcase(
    year >= 2007L & year <= 2010L, 2007L,
    year >= 2011L & year <= 2014L, 2011L,
    year >= 2015L & year <= 2017L, 2015L,
    default = NA_integer_
  )
}

# =============================================================================
# FE and Table Helpers
# =============================================================================

build_fe_formula <- function(fe_key, sector_col) {
  switch(
    fe_key,
    mxj_jxt = paste0("muni_id^", sector_col, " + ", sector_col, "^year"),
    mxj_mxt = paste0("muni_id^", sector_col, " + muni_id^year"),
    stop("Unknown FE key: ", fe_key)
  )
}

get_combo_instruments <- function(combo, align_type, exposure) {
  prefix <- if (identical(exposure, "binary")) "FA_bar_binary_" else "FA_bar_"
  switch(combo,
    "M"     = paste0(prefix, "mayor_", align_type),
    "G"     = paste0(prefix, "gov_", align_type),
    "P"     = paste0(prefix, "pres_", align_type),
    "M+G"   = paste0(prefix, c("mayor", "gov"), "_", align_type),
    "M+P"   = paste0(prefix, c("mayor", "pres"), "_", align_type),
    "M+G+P" = paste0(prefix, c("mayor", "gov", "pres"), "_", align_type),
    stop("Unknown combo: ", combo)
  )
}

get_combo_control_cols <- function(combo, exposure) {
  family <- if (identical(exposure, "binary")) "binary" else "share"
  mayor_col <- paste0("control_", family, "_mayor")
  gp_col <- paste0("control_", family, "_gp")
  switch(
    combo,
    "M" = mayor_col,
    "G" = gp_col,
    "P" = gp_col,
    "M+G" = c(mayor_col, gp_col),
    "M+P" = c(mayor_col, gp_col),
    "M+G+P" = c(mayor_col, gp_col),
    stop("Unknown combo: ", combo)
  )
}

get_sector_label <- function(sector_var) {
  switch(
    sector_var,
    cnae_section          = "CNAE section",
    custom_sector         = "sector group",
    bndes_sector          = "BNDES sector",
    size_bin              = "size bin",
    cnae_size_bin         = "CNAE section $\\times$ firm-size tercile",
    sector_group_size_bin = "sector group $\\times$ firm-size tercile",
    bndes_sector_size_bin = "BNDES sector $\\times$ firm-size tercile",
    stop("Unknown sector_var: ", sector_var)
  )
}

owner_weight_col_for_var <- function(var_name) {
  if (grepl("mayor", var_name, fixed = TRUE)) "owner_w_mayor" else "owner_w_gp"
}

build_table_notes <- function(cfg) {
  fe_label <- switch(
    cfg$fe,
    mxj_jxt = "Muni $\\times$ sector + sector $\\times$ year FE.",
    mxj_mxt = "Muni $\\times$ sector + muni $\\times$ year FE."
  )
  agg_label <- switch(
    cfg$aggregation,
    owner_count = "Owner-count aggregation.",
    equal_firm  = "Equal-firm aggregation.",
    employment  = "Employment-weighted aggregation."
  )
  wt_label <- switch(
    cfg$regression_weight,
    unweighted         = "Unweighted regressions.",
    emp_weighted       = "WLS uses pre-election cell employment.",
    emp_share_weighted = "WLS uses sector's share of pre-election municipality employment.",
    n_firms_weighted   = "WLS uses number of firms in the cell (N_pre)."
  )
  family_label <- if (!is.null(cfg$family) && identical(cfg$family, "interaction_mqemp")) {
    "Instruments interacted with top-quartile municipality employment dummy."
  } else {
    NA_character_
  }
  sample_label <- if (!is.null(cfg$muni_sample)) {
    switch(
      cfg$muni_sample,
      all       = NA_character_,
      top_q4    = "Sample: top-quartile municipalities by mean RAIS employment (2002--2017).",
      bottom_3q = "Sample: bottom three quartiles by mean RAIS employment (2002--2017).",
      NA_character_
    )
  } else {
    NA_character_
  }
  notes <- c(
    fe_label,
    if (identical(cfg$alignment, "coalition")) "Coalition alignment." else "Party alignment.",
    if (identical(cfg$baseline, "cycle_specific")) "Cycle-specific baseline." else "2002-fixed baseline.",
    if (identical(cfg$exposure, "binary")) "Binary exposure." else "Pooled-count exposure.",
    agg_label,
    wt_label,
    family_label,
    sample_label,
    if (identical(cfg$exposure_control, "yes")) "Exposure controls interacted with year." else "No exposure controls.",
    sprintf("SEs clustered by muni + %s in parentheses.", get_sector_label(cfg$sector_var)),
    "$^{***}p<0.01$, $^{**}p<0.05$, $^{*}p<0.10$."
  )
  paste(notes[!is.na(notes) & nzchar(notes)], collapse = " ")
}

# =============================================================================
# Collapse Functions
# =============================================================================

collapse_agg_panel <- function(dt_in, fa_terms, sector_col, aggregation = "owner_count") {
  by_cols <- c(sector_col, "muni_id", "year")
  agg_terms <- sub("^FA_", "FA_bar_", fa_terms)

  # Detect which optional columns are present
  has_share_cols <- all(c("emp_share_muni_pre_mayor", "emp_share_muni_pre_gp") %in% names(dt_in))
  has_top_q4     <- "top_q4_muni" %in% names(dt_in)

  if (!nrow(dt_in)) {
    empty_dt <- data.table(muni_id = integer(), year = integer())
    empty_dt[, (sector_col) := character()]
    extra_cols <- c("Y_bndes_extensive", "Y_bndes_share", "Y_log_employment",
                    "Y_employment_share", "N_pre", "emp_pre", agg_terms, CONTROL_COLS)
    if (has_share_cols) extra_cols <- c(extra_cols, "emp_share_sector_pre_mayor", "emp_share_sector_pre_gp")
    if (has_top_q4)     extra_cols <- c(extra_cols, "top_q4_muni")
    for (col in extra_cols) empty_dt[, (col) := numeric()]
    return(empty_dt)
  }

  agg_dt <- dt_in[, {
    out <- list(
      Y_bndes_extensive = mean_if_any(has_bndes_fmt),
      total_bndes = sum(value_dis_real_2018_total, na.rm = TRUE),
      total_emp = sum_if_any(n_employees),
      N_pre = .N,
      emp_pre = sum_if_any(bl_n_employees)
    )
    # Employment-share columns: sum firm-level shares to get sector's share of muni employment
    if (has_share_cols) {
      out$emp_share_sector_pre_mayor <- sum_if_any(emp_share_muni_pre_mayor)
      out$emp_share_sector_pre_gp    <- sum_if_any(emp_share_muni_pre_gp)
    }
    # top_q4_muni is constant within muni; take max to carry through
    if (has_top_q4) {
      out$top_q4_muni <- max(top_q4_muni, na.rm = TRUE)
    }

    if (identical(aggregation, "equal_firm")) {
      for (col in fa_terms) out[[sub("^FA_", "FA_bar_", col)]] <- mean_if_any(get(col))
      out$control_share_mayor <- mean_if_any(firm_control_share_mayor)
      out$control_share_gp <- mean_if_any(firm_control_share_gp)
      out$control_binary_mayor <- mean_if_any(firm_control_binary_mayor)
      out$control_binary_gp <- mean_if_any(firm_control_binary_gp)
    } else if (identical(aggregation, "employment")) {
      for (col in fa_terms) out[[sub("^FA_", "FA_bar_", col)]] <- weighted_mean_safe(get(col), bl_n_employees)
      out$control_share_mayor <- weighted_mean_safe(firm_control_share_mayor, bl_n_employees)
      out$control_share_gp <- weighted_mean_safe(firm_control_share_gp, bl_n_employees)
      out$control_binary_mayor <- weighted_mean_safe(firm_control_binary_mayor, bl_n_employees)
      out$control_binary_gp <- weighted_mean_safe(firm_control_binary_gp, bl_n_employees)
    } else if (identical(aggregation, "owner_count")) {
      for (col in fa_terms) {
        out[[sub("^FA_", "FA_bar_", col)]] <- weighted_mean_safe(get(col), get(owner_weight_col_for_var(col)))
      }
      out$control_share_mayor <- weighted_mean_safe(firm_control_share_mayor, owner_w_mayor)
      out$control_share_gp <- weighted_mean_safe(firm_control_share_gp, owner_w_gp)
      out$control_binary_mayor <- weighted_mean_safe(firm_control_binary_mayor, owner_w_mayor)
      out$control_binary_gp <- weighted_mean_safe(firm_control_binary_gp, owner_w_gp)
    } else {
      stop("Unknown aggregation: ", aggregation)
    }

    out
  }, by = by_cols]

  agg_dt[, muni_year_bndes := sum_if_any(total_bndes), by = .(muni_id, year)]
  agg_dt[, muni_year_emp := sum_if_any(total_emp), by = .(muni_id, year)]

  agg_dt[, Y_bndes_share := fifelse(
    is.finite(total_bndes) & is.finite(muni_year_bndes) & muni_year_bndes > 0,
    total_bndes / muni_year_bndes,
    NA_real_
  )]
  agg_dt[, Y_log_employment := fifelse(
    is.finite(total_emp) & total_emp > 0,
    log(total_emp),
    NA_real_
  )]
  agg_dt[, Y_employment_share := fifelse(
    is.finite(muni_year_emp) & muni_year_emp > 0,
    total_emp / muni_year_emp,
    NA_real_
  )]

  # Clean up intermediate columns
  agg_dt[, c("total_bndes", "total_emp", "muni_year_bndes", "muni_year_emp") := NULL]

  agg_dt[]
}

# =============================================================================
# Estimation Loop
# =============================================================================

# Map a combo to its office-tier employment-share weight column (sector level).
# Pure G/P combos (G, P) use the G/P-cycle denominator; all others use mayor.
# Mixed-tier combos (M+G, M+P, M+G+P) use the mayor share as single-denominator
# approximation (deferred design decision per plan Appendix D).
get_emp_share_weight_col_52 <- function(combo) {
  if (combo %in% c("G", "P")) "emp_share_sector_pre_gp" else "emp_share_sector_pre_mayor"
}

run_six_combos <- function(cfg, agg_dt, sector_col, year_ref) {
  dep_info <- DEPVAR_INFO[[cfg$outcome]]
  depvar <- dep_info$depvar
  fe_formula <- build_fe_formula(cfg$fe, sector_col)
  vcov_formula <- as.formula(paste0("~ muni_id + ", sector_col))

  # Base weight formula (NULL for unweighted / emp_share_weighted which is per-combo)
  use_emp_share_wt <- identical(cfg$regression_weight, "emp_share_weighted")
  wt_formula <- if (identical(cfg$regression_weight, "emp_weighted")) {
    ~emp_pre
  } else if (identical(cfg$regression_weight, "n_firms_weighted")) {
    # Precision-weighting: cells with more firms carry more information.
    ~N_pre
  } else {
    NULL
  }

  family <- if (is.null(cfg$family)) "main" else cfg$family

  if (identical(cfg$exposure_control, "yes")) {
    need_ctrl <- unique(unlist(lapply(COMBOS, get_combo_control_cols, exposure = cfg$exposure)))
    missing_ctrl <- need_ctrl[!need_ctrl %in% names(agg_dt)]
    if (length(missing_ctrl)) {
      stop(
        "Required exposure-control columns missing for config '", cfg$canonical_slug,
        "': ", paste(missing_ctrl, collapse = ", ")
      )
    }
  }

  # For interaction_mqemp, top_q4_muni must be present
  if (identical(family, "interaction_mqemp") && !"top_q4_muni" %in% names(agg_dt)) {
    stop(
      "Column `top_q4_muni` not found in collapsed panel for config '", cfg$canonical_slug,
      "'. Run scripts 32b + 41 + 42 first (Unit 1 + 2)."
    )
  }

  mods <- list()
  failed <- character(0)

  for (combo in COMBOS) {
    inst_cols <- get_combo_instruments(combo, cfg$alignment, cfg$exposure)
    missing <- inst_cols[!inst_cols %in% names(agg_dt)]
    if (length(missing)) {
      failed <- c(failed, combo)
      next
    }

    ctrl_str <- ""
    if (identical(cfg$exposure_control, "yes")) {
      ctrl_cols <- unique(get_combo_control_cols(combo, cfg$exposure))
      terms <- paste0("i(year, ", ctrl_cols, ", ref = ", year_ref, ")")
      ctrl_str <- paste0(" + ", paste(terms, collapse = " + "))
    }

    # Build RHS: for interaction_mqemp add FA_bar_*:top_q4_muni terms.
    # The main effect of top_q4_muni is absorbed by muni^sector FE (time-invariant).
    if (identical(family, "interaction_mqemp")) {
      interaction_terms <- paste(paste0(inst_cols, ":top_q4_muni"), collapse = " + ")
      rhs <- paste(paste(inst_cols, collapse = " + "), "+", interaction_terms)
    } else {
      rhs <- paste(inst_cols, collapse = " + ")
    }

    fml <- as.formula(paste0(depvar, " ~ ", rhs, ctrl_str, " | ", fe_formula))

    # Determine weight: emp_share_weighted uses a per-combo column
    combo_wt <- if (use_emp_share_wt) {
      wt_col <- get_emp_share_weight_col_52(combo)
      if (!wt_col %in% names(agg_dt)) {
        cat(sprintf("  WARNING: weight column '%s' missing for combo '%s' — skipping.\n", wt_col, combo))
        failed <- c(failed, combo)
        next
      }
      as.formula(paste0("~", wt_col))
    } else {
      wt_formula
    }

    mod <- tryCatch({
      fit_args <- list(
        fml = fml,
        data = agg_dt,
        vcov = vcov_formula,
        lean = TRUE,
        mem.clean = TRUE
      )
      if (!is.null(combo_wt)) fit_args$weights <- combo_wt
      do.call(feols, fit_args)
    }, error = function(e) {
      cat(sprintf("  WARNING: combo '%s' failed: %s\n", combo, conditionMessage(e)))
      NULL
    })

    if (!is.null(mod)) {
      if (length(mod$collin.var) > 0) {
        cat(sprintf("  Collinearity in '%s': dropped %s\n",
                    combo, paste(mod$collin.var, collapse = ", ")))
      }
      mods[[combo]] <- mod
    } else {
      failed <- c(failed, combo)
    }
  }

  list(mods = mods, failed_combos = unique(failed))
}

extract_summary <- function(mods, cfg, spec_label) {
  if (!length(mods)) return(NULL)
  rbindlist(lapply(names(mods), function(combo_name) {
    mod <- mods[[combo_name]]
    ct <- coeftable(mod)
    inst_rows <- grepl("^FA_bar_", rownames(ct))
    if (!any(inst_rows)) return(NULL)
    data.table(
      canonical_slug = spec_label,
      combo = combo_name,
      variable = rownames(ct)[inst_rows],
      coef = ct[inst_rows, "Estimate"],
      se = ct[inst_rows, "Std. Error"],
      t_stat = ct[inst_rows, "t value"],
      p_value = ct[inst_rows, "Pr(>|t|)"],
      r2 = tryCatch(fixest::r2(mod, "r2"), error = function(e) NA_real_),
      wald_f = safe_wald(mod, "^FA_bar_"),
      control_wald_f = safe_wald(mod, "^control_"),
      n_obs = nobs(mod),
      n_collin = length(mod$collin.var),
      outcome = cfg$outcome,
      exposure = cfg$exposure,
      aggregation = cfg$aggregation,
      regression_weight = cfg$regression_weight,
      sector_var = cfg$sector_var,
      baseline = cfg$baseline,
      alignment = cfg$alignment,
      fe = cfg$fe,
      exposure_control = cfg$exposure_control
    )
  }), fill = TRUE)
}

append_manifest_row <- function(cfg, depvar, mods, failed_combos,
                                elapsed_fit_sec, elapsed_table_sec,
                                elapsed_summary_sec, elapsed_sec,
                                status, skip_reason = NA_character_,
                                tex_path = NA_character_) {
  fstats <- if (length(mods)) vapply(mods, safe_wald, numeric(1), keep = "^FA_bar_") else numeric(0)
  fstats <- fstats[is.finite(fstats)]
  ctrl_fstats <- if (length(mods)) vapply(mods, safe_wald, numeric(1), keep = "^control_") else numeric(0)
  ctrl_fstats <- ctrl_fstats[is.finite(ctrl_fstats)]

  data.table(
    canonical_slug = cfg$canonical_slug,
    outcome = cfg$outcome,
    exposure = cfg$exposure,
    aggregation = cfg$aggregation,
    regression_weight = cfg$regression_weight,
    sector_var = cfg$sector_var,
    baseline = cfg$baseline,
    alignment = cfg$alignment,
    fe = cfg$fe,
    exposure_control = cfg$exposure_control,
    depvar = depvar,
    n_obs = if (length(mods)) as.integer(min(vapply(mods, nobs, numeric(1)))) else NA_integer_,
    n_combos_run = length(mods),
    n_combos_failed = length(failed_combos),
    wald_f_min = if (length(fstats)) min(fstats) else NA_real_,
    wald_f_max = if (length(fstats)) max(fstats) else NA_real_,
    control_wald_f_min = if (length(ctrl_fstats)) min(ctrl_fstats) else NA_real_,
    control_wald_f_max = if (length(ctrl_fstats)) max(ctrl_fstats) else NA_real_,
    elapsed_fit_sec = as.numeric(elapsed_fit_sec),
    elapsed_table_sec = as.numeric(elapsed_table_sec),
    elapsed_summary_sec = as.numeric(elapsed_summary_sec),
    elapsed_sec = as.numeric(elapsed_sec),
    status = status,
    skip_reason = skip_reason,
    tex_path = tex_path
  )
}

load_mapping_qs2 <- function(path, required_cols = character(0), missing_msg = NULL) {
  if (!file.exists(path)) {
    if (is.null(missing_msg)) missing_msg <- paste0("Required mapping not found: ", path)
    stop(missing_msg)
  }
  out <- qs_read(path)
  setDT(out)
  missing_cols <- required_cols[!required_cols %in% names(out)]
  if (length(missing_cols)) {
    stop("Mapping file missing required columns [", paste(missing_cols, collapse = ", "), "]: ", path)
  }
  out
}

load_size_bin_mapping <- function() {
  size_map <- load_mapping_qs2(
    make_output_path("size_bin_mapping.qs2"),
    required_cols = c("firm_id", "election_cycle", "size_bin"),
    missing_msg = "size_bin mapping not found. Run script 30c first."
  )
  size_map[, firm_id := as.integer(firm_id)]
  size_map[, election_cycle := as.integer(election_cycle)]
  size_map[, size_bin := as.integer(size_bin)]
  if (!"size_bin_label" %in% names(size_map)) {
    size_map[, size_bin_label := paste0("T", size_bin)]
  }
  unique(size_map[, .(firm_id, election_cycle, size_bin, size_bin_label)])
}

load_sector_size_bin_mappings <- function() {
  cnae_map <- load_mapping_qs2(
    make_output_path("sector_size_bin_cnae_mapping.qs2"),
    required_cols = c("firm_id", "election_cycle", "cnae_size_bin"),
    missing_msg = "sector_size_bin_cnae_mapping.qs2 not found. Run script 30d first."
  )
  cnae_map[, firm_id       := as.integer(firm_id)]
  cnae_map[, election_cycle := as.integer(election_cycle)]
  cnae_map[, cnae_size_bin  := as.character(cnae_size_bin)]
  cnae_map <- unique(cnae_map[, .(firm_id, election_cycle, cnae_size_bin)])

  group_map <- load_mapping_qs2(
    make_output_path("sector_size_bin_group_mapping.qs2"),
    required_cols = c("firm_id", "election_cycle", "sector_group_size_bin"),
    missing_msg = "sector_size_bin_group_mapping.qs2 not found. Run script 30d first."
  )
  group_map[, firm_id              := as.integer(firm_id)]
  group_map[, election_cycle       := as.integer(election_cycle)]
  group_map[, sector_group_size_bin := as.character(sector_group_size_bin)]
  group_map <- unique(group_map[, .(firm_id, election_cycle, sector_group_size_bin)])

  bndes_map <- load_mapping_qs2(
    make_output_path("sector_size_bin_bndes_mapping.qs2"),
    required_cols = c("firm_id", "election_cycle", "bndes_sector_size_bin"),
    missing_msg = "sector_size_bin_bndes_mapping.qs2 not found. Run script 30d first."
  )
  bndes_map[, firm_id               := as.integer(firm_id)]
  bndes_map[, election_cycle        := as.integer(election_cycle)]
  bndes_map[, bndes_sector_size_bin := as.character(bndes_sector_size_bin)]
  bndes_map <- unique(bndes_map[, .(firm_id, election_cycle, bndes_sector_size_bin)])

  list(cnae = cnae_map, group = group_map, bndes = bndes_map)
}

load_baseline_exposure_aux <- function() {
  baseline <- load_mapping_qs2(
    make_output_path("firm_baseline_exposures.qs2"),
    required_cols = c("firm_id", "party", "baseline_type", "election_year", "share_fp_0", "binary_fp_0", "L_f_0"),
    missing_msg = "firm_baseline_exposures.qs2 not found. Run script 36 first."
  )
  baseline <- unique(baseline[, .(
    firm_id = as.integer(firm_id),
    party = as.character(party),
    baseline_type = as.character(baseline_type),
    election_year = as.integer(election_year),
    share_fp_0 = as.numeric(share_fp_0),
    binary_fp_0 = as.numeric(binary_fp_0),
    L_f_0 = as.numeric(L_f_0)
  )])

  lf_check <- baseline[, .(n_vals = uniqueN(L_f_0)), by = .(firm_id, baseline_type, election_year)]
  if (any(lf_check$n_vals > 1L)) {
    bad <- lf_check[n_vals > 1L][1L]
    stop(
      "Inconsistent L_f_0 across duplicated baseline rows for firm_id=", bad$firm_id,
      ", baseline_type=", bad$baseline_type,
      ", election_year=", bad$election_year
    )
  }

  list(
    owner_weights = unique(baseline[, .(firm_id, baseline_type, election_year, L_f_0)]),
    control_primitives = baseline[party != "No party", .(
      control_share = sum(share_fp_0, na.rm = TRUE),
      control_binary = sum(binary_fp_0, na.rm = TRUE)
    ), by = .(firm_id, baseline_type, election_year)]
  )
}

load_panel_bundle <- function(baseline, need_bndes_amount = FALSE) {
  paths <- firm_panel_paths(baseline)

  if (!file.exists(paths$base)) {
    stop("Firm panel not found for baseline '", baseline, "'. Run script 42 first.")
  }

  # Enumerate available FA columns from the sparse instruments file.
  avail_inst_cols <- if (file.exists(paths$sparse) && requireNamespace("fst", quietly = TRUE)) {
    fst::metadata_fst(paths$sparse)$columnNames
  } else character(0)
  fa_cols_all    <- grep("^FA_", avail_inst_cols, value = TRUE)
  fa_cols_pooled <- grep("^FA_(mayor|gov|pres)_(coalition|party)$", fa_cols_all, value = TRUE)
  fa_cols_binary <- grep("^FA_binary_(mayor|gov|pres)_(coalition|party)$", fa_cols_all, value = TRUE)
  fa_cols <- c(fa_cols_pooled, fa_cols_binary)

  # Optional base columns (emp-share weights, top-quartile flag).
  avail_base_cols <- fst::metadata_fst(paths$base)$columnNames
  optional_cols <- intersect(
    c("emp_share_muni_pre_mayor", "emp_share_muni_pre_gp", "top_q4_muni", "value_dis_real_2018_total"),
    avail_base_cols
  )
  keep_base_cols <- intersect(
    unique(c("firm_id", "muni_id", "year", "cnae_section",
             "has_bndes_fmt", "n_employees", "bl_n_employees", optional_cols)),
    avail_base_cols
  )

  dt <- load_firm_panel(
    baseline_type = baseline,
    columns       = keep_base_cols,
    instruments   = if (length(fa_cols)) fa_cols else character(0),
    zero_fill     = TRUE,
    as_data_table = TRUE
  )

  dt[, firm_id := as.integer(firm_id)]
  dt[, muni_id := as.integer(muni_id)]
  dt[, year := as.integer(year)]
  dt[, cnae_section := as.character(cnae_section)]
  dt[, has_bndes_fmt := as.numeric(has_bndes_fmt)]
  dt[, n_employees := as.numeric(n_employees)]
  if ("bl_n_employees" %in% names(dt)) {
    dt[, bl_n_employees := as.numeric(bl_n_employees)]
  } else {
    dt[, bl_n_employees := NA_real_]
  }
  for (col in intersect(fa_cols, names(dt))) dt[, (col) := as.numeric(get(col))]
  for (col in c("emp_share_muni_pre_mayor", "emp_share_muni_pre_gp")) {
    if (col %in% names(dt)) dt[, (col) := as.numeric(get(col))]
  }
  if ("top_q4_muni" %in% names(dt)) dt[, top_q4_muni := as.integer(top_q4_muni)]

  if (!"value_dis_real_2018_total" %in% names(dt) && need_bndes_amount) {
    recon_fst <- make_output_path("rais_bndes_reconstructed.fst")
    recon_qs2 <- make_output_path("rais_bndes_reconstructed.qs2")
    if (file.exists(recon_fst) && requireNamespace("fst", quietly = TRUE)) {
      raw_bndes <- fst::read_fst(recon_fst, columns = c("firm_id", "muni_id", "year", "value_dis_real_2018_total"), as.data.table = TRUE)
    } else if (file.exists(recon_qs2)) {
      raw_bndes <- qs_read(recon_qs2)
      setDT(raw_bndes)
      raw_bndes <- raw_bndes[, .(firm_id, muni_id, year, value_dis_real_2018_total)]
    } else {
      stop("Reconstructed panel not found; cannot recover value_dis_real_2018_total.")
    }
    raw_bndes[, `:=`(firm_id = as.integer(firm_id), muni_id = as.integer(muni_id), year = as.integer(year))]
    raw_bndes[, value_dis_real_2018_total := as.numeric(value_dis_real_2018_total)]
    dt[raw_bndes, value_dis_real_2018_total := i.value_dis_real_2018_total, on = .(firm_id, muni_id, year)]
    rm(raw_bndes)
    invisible(gc())
  }

  if (!"value_dis_real_2018_total" %in% names(dt)) dt[, value_dis_real_2018_total := 0]
  dt[is.na(value_dis_real_2018_total), value_dis_real_2018_total := 0]

  list(dt = dt, fa_cols = fa_cols)
}

attach_baseline_aux <- function(dt, baseline, aux_lookups) {
  dt[, treat_mayor := mayor_treatment_year(year)]
  dt[, treat_gp := gp_treatment_year(year)]
  dt[, `:=`(
    owner_w_mayor = 0,
    owner_w_gp = 0,
    firm_control_share_mayor = 0,
    firm_control_share_gp = 0,
    firm_control_binary_mayor = 0,
    firm_control_binary_gp = 0
  )]

  owner_weights <- aux_lookups$owner_weights[baseline_type == baseline]
  control_primitives <- aux_lookups$control_primitives[baseline_type == baseline]

  dt[owner_weights[election_year %in% MAYOR_TREATMENT_YEARS, .(firm_id, treat_mayor = election_year, owner_w_mayor = L_f_0)],
     owner_w_mayor := i.owner_w_mayor, on = .(firm_id, treat_mayor)]
  dt[owner_weights[election_year %in% GP_TREATMENT_YEARS, .(firm_id, treat_gp = election_year, owner_w_gp = L_f_0)],
     owner_w_gp := i.owner_w_gp, on = .(firm_id, treat_gp)]

  dt[control_primitives[election_year %in% MAYOR_TREATMENT_YEARS, .(
      firm_id, treat_mayor = election_year,
      firm_control_share_mayor = control_share,
      firm_control_binary_mayor = control_binary
    )],
    `:=`(
      firm_control_share_mayor = i.firm_control_share_mayor,
      firm_control_binary_mayor = i.firm_control_binary_mayor
    ),
    on = .(firm_id, treat_mayor)
  ]
  dt[control_primitives[election_year %in% GP_TREATMENT_YEARS, .(
      firm_id, treat_gp = election_year,
      firm_control_share_gp = control_share,
      firm_control_binary_gp = control_binary
    )],
    `:=`(
      firm_control_share_gp = i.firm_control_share_gp,
      firm_control_binary_gp = i.firm_control_binary_gp
    ),
    on = .(firm_id, treat_gp)
  ]

  for (col in c(
    "owner_w_mayor", "owner_w_gp",
    "firm_control_share_mayor", "firm_control_share_gp",
    "firm_control_binary_mayor", "firm_control_binary_gp"
  )) {
    dt[is.na(get(col)), (col) := 0]
  }
  dt[]
}

# =============================================================================
# Sector Classification Join
# =============================================================================

join_sector_classification_legacy <- function(dt, sector_var, size_bin_map = NULL) {
  if (sector_var == "cnae_section") {
    # Already in panel — nothing to do
    return(dt)
  }

  if (sector_var == "custom_sector") {
    if ("sector_group" %in% names(dt)) {
      # Already joined — rename for consistency
      return(dt)
    }
    sg_map <- load_mapping_qs2(
      make_output_path("sector_group_mapping.qs2"),
      required_cols = c("cnae_section", "sector_group"),
      missing_msg = "sector_group mapping not found. Run script 30 first."
    )
    sg_map[, `:=`(cnae_section = as.character(cnae_section), sector_group = as.character(sector_group))]
    dt[sg_map, sector_group := i.sector_group, on = "cnae_section"]
    return(dt)
  }

  if (sector_var == "bndes_sector") {
    bs_map <- load_mapping_qs2(
      make_output_path("bndes_sector_mapping.qs2"),
      required_cols = c("cnae_section", "bndes_sector"),
      missing_msg = "bndes_sector mapping not found. Run script 30b first."
    )
    bs_map[, `:=`(cnae_section = as.character(cnae_section), bndes_sector = as.character(bndes_sector))]
    dt[bs_map, bndes_sector := i.bndes_sector, on = "cnae_section"]
    return(dt)
  }

  if (sector_var == "size_bin") {
    if ("size_bin" %in% names(dt)) return(dt)
    if (is.null(size_bin_map)) stop("size_bin mapping not loaded.")
    if (!file.exists(mapping_path)) {
      stop("size_bin mapping not found. Run script 30c first.")
    }
    sb_map <- qs_read(mapping_path)
    setDT(sb_map)
    if (!"size_bin_label" %in% names(sb_map)) {
      sb_map[, size_bin_label := paste0("T", size_bin)]
    }
    # Map each year to its election cycle so we join the correct size_bin.
    # Mayor terms: 2005-2008, 2009-2012, 2013-2016, 2017+
    # Gov/Pres terms: 2007-2010, 2011-2014, 2015-2017
    # Each year can belong to both a mayor and gov cycle; use the mayor cycle
    # as the primary mapping since mayor elections are the main variation.
    year_to_cycle <- data.table(
      year = 2002L:2017L,
      election_cycle = c(
        rep(2005L, 4L),  # 2002-2004 → 2005 cycle (baseline + first year)
        rep(2005L, 1L),  # 2005
        rep(2009L, 4L),  # 2006-2008 + 2009
        rep(2013L, 4L),  # 2010-2012 + 2013
        rep(2017L, 4L)   # 2014-2016 + 2017
      )
    )
    dt[year_to_cycle, election_cycle := i.election_cycle, on = "year"]
    dt[sb_map, c("size_bin", "size_bin_label") := .(i.size_bin, i.size_bin_label),
       on = c("firm_id", "election_cycle")]
    # Firms without a match get bin 2 (middle) as fallback
    dt[is.na(size_bin), c("size_bin", "size_bin_label") := .(2L, "T2")]
    dt[, election_cycle := NULL]
    return(dt)
  }

  stop("Unknown sector_var: ", sector_var)
}

get_sector_col <- function(sector_var) {
  switch(
    sector_var,
    cnae_section          = "cnae_section",
    custom_sector         = "sector_group",
    bndes_sector          = "bndes_sector",
    size_bin              = "size_bin_label",
    cnae_size_bin         = "cnae_size_bin",
    sector_group_size_bin = "sector_group_size_bin",
    bndes_sector_size_bin = "bndes_sector_size_bin",
    stop("Unknown sector_var: ", sector_var)
  )
}

get_table_dir_suffix <- function(sector_var) {
  switch(
    sector_var,
    cnae_section          = "",
    custom_sector         = "_grouped",
    bndes_sector          = "_bndes_sector",
    size_bin              = "_size_bin",
    cnae_size_bin         = "_cnae_size_bin",
    sector_group_size_bin = "_sector_group_size_bin",
    bndes_sector_size_bin = "_bndes_sector_size_bin",
    stop("Unknown sector_var: ", sector_var)
  )
}

join_sector_classification <- function(dt, sector_var, size_bin_map = NULL,
                                       sector_size_bin_maps = NULL) {
  if (sector_var == "cnae_section") return(dt)

  if (sector_var == "custom_sector") {
    sg_map <- load_mapping_qs2(
      make_output_path("sector_group_mapping.qs2"),
      required_cols = c("cnae_section", "sector_group"),
      missing_msg = "sector_group mapping not found. Run script 30 first."
    )
    sg_map[, `:=`(cnae_section = as.character(cnae_section), sector_group = as.character(sector_group))]
    dt[sg_map, sector_group := i.sector_group, on = "cnae_section"]
    return(dt)
  }

  if (sector_var == "bndes_sector") {
    bs_map <- load_mapping_qs2(
      make_output_path("bndes_sector_mapping.qs2"),
      required_cols = c("cnae_section", "bndes_sector"),
      missing_msg = "bndes_sector mapping not found. Run script 30b first."
    )
    bs_map[, `:=`(cnae_section = as.character(cnae_section), bndes_sector = as.character(bndes_sector))]
    dt[bs_map, bndes_sector := i.bndes_sector, on = "cnae_section"]
    return(dt)
  }

  if (sector_var == "size_bin") {
    if (is.null(size_bin_map)) stop("size_bin mapping not loaded.")
    dt[, size_bin_cycle := mayor_treatment_year(year)]
    dt[size_bin_map[election_cycle %in% MAYOR_TREATMENT_YEARS, .(
        firm_id,
        size_bin_cycle = election_cycle,
        size_bin,
        size_bin_label
      )],
      `:=`(size_bin = i.size_bin, size_bin_label = i.size_bin_label),
      on = .(firm_id, size_bin_cycle)
    ]
    dt[, size_bin_cycle := NULL]
    return(dt)
  }

  if (sector_var == "cnae_size_bin") {
    if (is.null(sector_size_bin_maps) || is.null(sector_size_bin_maps$cnae)) {
      stop("cnae_size_bin crosswalk not loaded. Run script 30d first.")
    }
    csb_map <- sector_size_bin_maps$cnae
    dt[, sz_cycle := mayor_treatment_year(year)]
    dt[csb_map[, .(firm_id, sz_cycle = election_cycle, cnae_size_bin)],
       cnae_size_bin := i.cnae_size_bin,
       on = .(firm_id, sz_cycle)]
    dt[, sz_cycle := NULL]
    return(dt)
  }

  if (sector_var == "sector_group_size_bin") {
    if (is.null(sector_size_bin_maps) || is.null(sector_size_bin_maps$group)) {
      stop("sector_group_size_bin crosswalk not loaded. Run script 30d first.")
    }
    gsb_map <- sector_size_bin_maps$group
    dt[, sz_cycle := mayor_treatment_year(year)]
    dt[gsb_map[, .(firm_id, sz_cycle = election_cycle, sector_group_size_bin)],
       sector_group_size_bin := i.sector_group_size_bin,
       on = .(firm_id, sz_cycle)]
    dt[, sz_cycle := NULL]
    return(dt)
  }

  if (sector_var == "bndes_sector_size_bin") {
    if (is.null(sector_size_bin_maps) || is.null(sector_size_bin_maps$bndes)) {
      stop("bndes_sector_size_bin crosswalk not loaded. Run script 30d first.")
    }
    bsb_map <- sector_size_bin_maps$bndes
    dt[, sz_cycle := mayor_treatment_year(year)]
    dt[bsb_map[, .(firm_id, sz_cycle = election_cycle, bndes_sector_size_bin)],
       bndes_sector_size_bin := i.bndes_sector_size_bin,
       on = .(firm_id, sz_cycle)]
    dt[, sz_cycle := NULL]
    return(dt)
  }

  stop("Unknown sector_var: ", sector_var)
}

build_supported_keys <- function(dt, sector_var, sector_col, f_pre_year_map,
                                 size_bin_map = NULL, sector_size_bin_maps = NULL) {
  f_pre_year_map <- f_pre_year_map[year %in% unique(dt$year)]

  # Helper: build support keys from a per-(firm_id, cycle) lookup table
  # lookup must have columns: firm_id, size_bin_cycle (= election_cycle), <label_col>
  build_from_cycle_lookup <- function(lookup, label_col) {
    presence <- unique(dt[, .(firm_id, muni_id, year)])
    support_list <- list()
    for (curr_year in sort(unique(f_pre_year_map$year))) {
      base_years <- f_pre_year_map[year == curr_year, baseline_year]
      base_cells <- unique(presence[year %in% base_years, .(firm_id, muni_id)])
      if (!nrow(base_cells)) next
      base_cells[, size_bin_cycle := mayor_treatment_year(curr_year)]
      base_cells <- base_cells[lookup, on = .(firm_id, size_bin_cycle), nomatch = 0L]
      if (!nrow(base_cells)) next
      base_cells[, year := curr_year]
      support_list[[length(support_list) + 1L]] <- unique(base_cells[, c("firm_id", "muni_id", "year", label_col), with = FALSE])
    }
    if (!length(support_list)) {
      empty <- data.table(firm_id = integer(), muni_id = integer(), year = integer())
      empty[, (label_col) := character()]
      return(empty)
    }
    rbindlist(support_list, use.names = TRUE, fill = TRUE)
  }

  # Firm-specific cycle-mapped sector_vars
  if (sector_var == "size_bin") {
    if (is.null(size_bin_map)) stop("size_bin mapping not loaded.")
    lookup <- unique(size_bin_map[election_cycle %in% MAYOR_TREATMENT_YEARS,
                                  .(firm_id, size_bin_cycle = election_cycle, size_bin_label)])
    return(build_from_cycle_lookup(lookup, "size_bin_label"))
  }

  if (sector_var == "cnae_size_bin") {
    if (is.null(sector_size_bin_maps) || is.null(sector_size_bin_maps$cnae)) {
      stop("cnae_size_bin crosswalk not loaded. Run script 30d first.")
    }
    csb <- sector_size_bin_maps$cnae
    lookup <- unique(csb[, .(firm_id, size_bin_cycle = election_cycle, cnae_size_bin)])
    return(build_from_cycle_lookup(lookup, "cnae_size_bin"))
  }

  if (sector_var == "sector_group_size_bin") {
    if (is.null(sector_size_bin_maps) || is.null(sector_size_bin_maps$group)) {
      stop("sector_group_size_bin crosswalk not loaded. Run script 30d first.")
    }
    gsb <- sector_size_bin_maps$group
    lookup <- unique(gsb[, .(firm_id, size_bin_cycle = election_cycle, sector_group_size_bin)])
    return(build_from_cycle_lookup(lookup, "sector_group_size_bin"))
  }

  if (sector_var == "bndes_sector_size_bin") {
    if (is.null(sector_size_bin_maps) || is.null(sector_size_bin_maps$bndes)) {
      stop("bndes_sector_size_bin crosswalk not loaded. Run script 30d first.")
    }
    bsb <- sector_size_bin_maps$bndes
    lookup <- unique(bsb[, .(firm_id, size_bin_cycle = election_cycle, bndes_sector_size_bin)])
    return(build_from_cycle_lookup(lookup, "bndes_sector_size_bin"))
  }

  # Panel-based sector_vars (cnae_section, custom_sector, bndes_sector)
  cell_years <- unique(dt[!is.na(get(sector_col)), .(
    firm_id, muni_id, year, sector_value = as.character(get(sector_col))
  )])
  cell_years[, in_f_pre := FALSE]
  for (curr_year in sort(unique(f_pre_year_map$year))) {
    base_years <- f_pre_year_map[year == curr_year, baseline_year]
    base_cells <- unique(cell_years[year %in% base_years, .(firm_id, muni_id, sector_value)])
    if (!nrow(base_cells)) next
    base_cells[, year := curr_year]
    cell_years[base_cells, in_f_pre := TRUE, on = .(firm_id, muni_id, year, sector_value)]
  }
  out <- unique(cell_years[in_f_pre == TRUE, .(firm_id, muni_id, year, sector_value)])
  setnames(out, "sector_value", sector_col)
  out
}

# =============================================================================
# Parse CLI and Resolve Configs
# =============================================================================

script_t0 <- proc.time()
args <- commandArgs(trailingOnly = TRUE)
parsed_args <- parse_cli_args(args)
config_dt <- resolve_requested_configs(parsed_args)

cat("Specs:", paste(parsed_args$spec_names, collapse = ", "), "\n")
cat("Test mode:", if (parsed_args$test) "yes" else "no", "\n")
cat("Resolved configs:", nrow(config_dt), "\n\n")

if (parsed_args$dry_run) {
  print_config_table(config_dt)
  cat("\nCanonical outputs per sector_var:\n")
  for (sv in unique(config_dt$sector_var)) {
    suffix <- get_table_dir_suffix(sv)
    tdir <- file.path(TABLES_DIR, paste0("agg_firm", suffix))
    cat(sprintf("\n  %s -> %s\n", sv, tdir))
    sv_slugs <- config_dt[sector_var == sv, canonical_slug]
    for (slug in sv_slugs) {
      cat("    ", slug, ".tex\n", sep = "")
    }
  }
  cat("\nDry run complete.\n")
  quit(save = "no", status = 0)
}

size_bin_map <- if ("size_bin" %in% config_dt$sector_var) load_size_bin_mapping() else NULL
sector_size_bin_maps <- if (any(c("cnae_size_bin", "sector_group_size_bin", "bndes_sector_size_bin") %in% config_dt$sector_var)) {
  load_sector_size_bin_mappings()
} else {
  NULL
}
baseline_aux <- if (any(config_dt$aggregation == "owner_count") || any(config_dt$exposure_control == "yes")) {
  load_baseline_exposure_aux()
} else {
  NULL
}
f_pre_year_map <- build_f_pre_year_map()

cat("\nStep 1: Running grouped estimation loop...\n")

manifest_rows <- list()
summary_rows <- list()
total_models <- 0L
group_dt <- unique(config_dt[, .(sector_var, baseline)])

for (g in seq_len(nrow(group_dt))) {
  sv <- group_dt$sector_var[g]
  baseline_key <- group_dt$baseline[g]
  sector_col <- get_sector_col(sv)
  suffix <- get_table_dir_suffix(sv)
  table_dir <- file.path(TABLES_DIR, paste0("agg_firm", suffix))
  if (parsed_args$test) table_dir <- file.path(table_dir, "test")
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

  group_configs <- config_dt[sector_var == sv & baseline == baseline_key]
  cat(sprintf("\n=== Group: sector_var=%s, baseline=%s ===\n", sv, baseline_key))

  panel_bundle <- load_panel_bundle(baseline_key, need_bndes_amount = any(group_configs$outcome == "bndes_share"))
  dt <- panel_bundle$dt
  fa_cols <- panel_bundle$fa_cols
  rm(panel_bundle)
  invisible(gc())

  if (parsed_args$test) {
    set.seed(20260406L)
    muni_ids <- sort(unique(dt$muni_id))
    sample_size <- max(1L, ceiling(0.10 * length(muni_ids)))
    dt <- dt[muni_id %in% sort(sample(muni_ids, size = sample_size))]
    cat(sprintf("  Test subsample rows: %s\n", format(nrow(dt), big.mark = ",")))
  }

  if (!is.null(baseline_aux)) {
    dt <- attach_baseline_aux(dt, baseline_key, baseline_aux)
  } else {
    dt[, `:=`(
      owner_w_mayor = 0, owner_w_gp = 0,
      firm_control_share_mayor = 0, firm_control_share_gp = 0,
      firm_control_binary_mayor = 0, firm_control_binary_gp = 0
    )]
  }

  dt <- join_sector_classification(dt, sv, size_bin_map = size_bin_map,
                                   sector_size_bin_maps = sector_size_bin_maps)
  supported_keys <- build_supported_keys(dt, sv, sector_col, f_pre_year_map,
                                         size_bin_map = size_bin_map,
                                         sector_size_bin_maps = sector_size_bin_maps)
  dt_pre <- dt[supported_keys, on = c("firm_id", "muni_id", "year", sector_col), nomatch = 0L]
  dt_pre[, (sector_col) := as.character(get(sector_col))]
  dt_pre <- dt_pre[!is.na(get(sector_col))]
  cat(sprintf("  Supported rows: %s\n", format(nrow(dt_pre), big.mark = ",")))

  if (!nrow(dt_pre)) {
    for (i in seq_len(nrow(group_configs))) {
      cfg <- group_configs[i]
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg, DEPVAR_INFO[[cfg$outcome]]$depvar, list(), COMBOS, 0, 0, 0, 0,
        "failed", "empty support-filtered sample"
      )
    }
    rm(dt, dt_pre, supported_keys)
    invisible(gc())
    next
  }

  collapsed_cache <- list()

  for (i in seq_len(nrow(group_configs))) {
    cfg <- group_configs[i]
    dep_info <- DEPVAR_INFO[[cfg$outcome]]
    depvar <- dep_info$depvar
    slug <- cfg$canonical_slug
    config_t0 <- proc.time()

    if (is.null(collapsed_cache[[cfg$aggregation]])) {
      cat(sprintf("  Collapsing aggregation=%s\n", cfg$aggregation))
      collapsed_cache[[cfg$aggregation]] <- collapse_agg_panel(dt_pre, fa_cols, sector_col, aggregation = cfg$aggregation)
    }
    agg_dt <- collapsed_cache[[cfg$aggregation]]

    sample_mask <- !is.na(agg_dt[[depvar]])
    if (identical(cfg$regression_weight, "emp_weighted")) {
      sample_mask <- sample_mask & is.finite(agg_dt$emp_pre) & agg_dt$emp_pre > 0
    }
    if (identical(cfg$regression_weight, "emp_share_weighted")) {
      # Require both share columns to be finite and positive so any combo can be weighted
      share_ok_m <- "emp_share_sector_pre_mayor" %in% names(agg_dt) &
                    is.finite(agg_dt$emp_share_sector_pre_mayor) &
                    agg_dt$emp_share_sector_pre_mayor > 0
      share_ok_g <- "emp_share_sector_pre_gp" %in% names(agg_dt) &
                    is.finite(agg_dt$emp_share_sector_pre_gp) &
                    agg_dt$emp_share_sector_pre_gp > 0
      # Keep rows where at least one tier is valid (per-combo selection handles the rest)
      sample_mask <- sample_mask & (share_ok_m | share_ok_g)
    }
    # muni_sample filter on collapsed panel (top_q4_muni is constant within muni)
    muni_sample <- if (is.null(cfg$muni_sample)) "all" else cfg$muni_sample
    if (!identical(muni_sample, "all")) {
      if (!"top_q4_muni" %in% names(agg_dt)) {
        manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
          cfg, depvar, list(), COMBOS, 0, 0, 0,
          as.numeric((proc.time() - config_t0)[["elapsed"]]),
          "failed", "top_q4_muni column missing; run 32b + 41 + 42 first"
        )
        next
      }
      if (identical(muni_sample, "top_q4")) {
        sample_mask <- sample_mask & !is.na(agg_dt$top_q4_muni) & agg_dt$top_q4_muni == 1L
      } else if (identical(muni_sample, "bottom_3q")) {
        sample_mask <- sample_mask & !is.na(agg_dt$top_q4_muni) & agg_dt$top_q4_muni == 0L
      }
    }
    agg_sample <- agg_dt[sample_mask]

    if (!nrow(agg_sample)) {
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg, depvar, list(), COMBOS, 0, 0, 0,
        as.numeric((proc.time() - config_t0)[["elapsed"]]),
        "failed", "empty estimation sample"
      )
      next
    }

    fit_t0 <- proc.time()
    run_result <- run_six_combos(cfg, agg_sample, sector_col, min(agg_sample$year, na.rm = TRUE))
    elapsed_fit <- as.numeric((proc.time() - fit_t0)[["elapsed"]])
    mods <- run_result$mods
    failed_combos <- run_result$failed_combos

    if (!length(mods)) {
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg, depvar, list(), if (length(failed_combos)) failed_combos else COMBOS, elapsed_fit, 0, 0,
        as.numeric((proc.time() - config_t0)[["elapsed"]]),
        "failed", "all combos failed"
      )
      next
    }

    ctrl_fstats <- vapply(mods, safe_wald, numeric(1), keep = "^control_")
    table_t0 <- proc.time()
    status <- "completed"
    skip_reason <- NA_character_
    tex_path <- NA_character_
    tryCatch({
      save_beamer_table(
        mods = mods,
        filename = slug,
        dep_var = dep_info$dep_label,
        notes = build_table_notes(cfg),
        add_f_stat = TRUE,
        fstat_keep = "^FA_bar_",
        exposure_control_gof = identical(cfg$exposure_control, "yes"),
        exposure_control_fstat = if (identical(cfg$exposure_control, "yes")) ctrl_fstats else NULL,
        table_dir = table_dir
      )
      tex_path <- file.path(table_dir, paste0(slug, ".tex"))
    }, error = function(e) {
      status <<- "failed"
      skip_reason <<- paste0("table save failed: ", conditionMessage(e))
    })
    elapsed_table <- as.numeric((proc.time() - table_t0)[["elapsed"]])

    if (!identical(status, "completed")) {
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg, depvar, mods, failed_combos,
        elapsed_fit, elapsed_table, 0,
        as.numeric((proc.time() - config_t0)[["elapsed"]]),
        status, skip_reason, tex_path
      )
      next
    }

    summary_t0 <- proc.time()
    summary_dt <- extract_summary(mods, cfg, slug)
    elapsed_summary <- as.numeric((proc.time() - summary_t0)[["elapsed"]])
    if (!is.null(summary_dt) && nrow(summary_dt)) {
      summary_rows[[length(summary_rows) + 1L]] <- summary_dt
    }
    total_models <- total_models + length(mods)

    manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
      cfg, depvar, mods, failed_combos,
      elapsed_fit, elapsed_table, elapsed_summary,
      as.numeric((proc.time() - config_t0)[["elapsed"]]),
      "completed", tex_path = tex_path
    )
  }

  rm(dt, dt_pre, supported_keys, collapsed_cache)
  invisible(gc())
}

cat("\nStep 2: Saving manifests and summaries...\n")

manifest_dt_all <- if (length(manifest_rows)) rbindlist(manifest_rows, fill = TRUE) else data.table()
summary_dt_all <- if (length(summary_rows)) rbindlist(summary_rows, fill = TRUE) else data.table()

for (sv in unique(config_dt$sector_var)) {
  suffix <- get_table_dir_suffix(sv)
  table_dir <- file.path(TABLES_DIR, paste0("agg_firm", suffix))
  if (parsed_args$test) table_dir <- file.path(table_dir, "test")
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

  sv_manifest <- manifest_dt_all[sector_var == sv]
  sv_summary <- summary_dt_all[sector_var == sv]

  if (nrow(sv_manifest)) {
    manifest_csv_path <- file.path(table_dir, "agg_firm_run_manifest.csv")
    manifest_qs2_path <- file.path(table_dir, "agg_firm_run_manifest.qs2")
    replace_slugs <- unique(sv_manifest$canonical_slug)
    existing_manifest <- read_existing_artifact(manifest_qs2_path, qs_read)
    if (is.null(existing_manifest)) existing_manifest <- read_existing_artifact(manifest_csv_path, fread)
    merged_manifest <- merge_existing_runs(existing_manifest, sv_manifest, replace_slugs, c("baseline", "canonical_slug"))
    write_csv_atomic(merged_manifest, manifest_csv_path)
    write_qs_atomic(merged_manifest, manifest_qs2_path)
  }

  if (nrow(sv_summary)) {
    summary_path <- file.path(table_dir, "agg_firm_fc_battery_summary.qs2")
    replace_slugs <- unique(sv_summary$canonical_slug)
    existing_summary <- read_existing_artifact(summary_path, qs_read)
    merged_summary <- merge_existing_runs(existing_summary, sv_summary, replace_slugs, c("baseline", "canonical_slug", "combo", "variable"))
    write_qs_atomic(merged_summary, summary_path)
  }
}

elapsed_total <- as.numeric((proc.time() - script_t0)[["elapsed"]])
cat("\n==============================================================================\n")
cat("Aggregated firm -> sector first stage complete.\n")
cat(sprintf("Total: %.1f min (%d configs, %d models)\n", elapsed_total / 60, nrow(config_dt), total_models))
cat("==============================================================================\n")
quit(save = "no", status = 0)

# =============================================================================
# Load Firm Panel
# =============================================================================

cat("Step 1: Loading firm panel...\n")

panel_fst <- make_output_path("firm_panel_for_regs.fst")
panel_qs2 <- make_output_path("firm_panel_for_regs.qs2")

if (file.exists(panel_fst) && requireNamespace("fst", quietly = TRUE)) {
  avail_cols <- fst::metadata_fst(panel_fst)$columnNames
} else if (file.exists(panel_qs2)) {
  tmp <- qs_read(panel_qs2)
  avail_cols <- names(tmp)
  rm(tmp); invisible(gc())
} else {
  stop("Firm panel not found. Run script 42 first.")
}

fa_cols_all <- grep("^FA_", avail_cols, value = TRUE)
fa_cols_pooled <- grep("^FA_(mayor|gov|pres)_(coalition|party)$", fa_cols_all, value = TRUE)
fa_cols_binary <- grep("^FA_binary_(mayor|gov|pres)_(coalition|party)$", fa_cols_all, value = TRUE)
fa_cols <- c(fa_cols_pooled, fa_cols_binary)

keep_cols <- unique(c(
  "firm_id", "muni_id", "year", "cnae_section",
  "has_bndes_fmt", "n_employees", "value_dis_real_2018_total",
  fa_cols
))

if (file.exists(panel_fst) && requireNamespace("fst", quietly = TRUE)) {
  read_cols <- intersect(keep_cols, avail_cols)
  dt <- fst::read_fst(panel_fst, columns = read_cols, as.data.table = TRUE)
  cat(sprintf("  Loaded from fst: %s rows\n", format(nrow(dt), big.mark = ",")))
} else {
  dt <- qs_read(panel_qs2)
  setDT(dt)
  read_cols <- intersect(keep_cols, names(dt))
  dt <- dt[, ..read_cols]
  cat(sprintf("  Loaded from qs2: %s rows\n", format(nrow(dt), big.mark = ",")))
}

dt[, firm_id := as.integer(firm_id)]
dt[, muni_id := as.integer(muni_id)]
dt[, year := as.integer(year)]
dt[, n_employees := as.numeric(n_employees)]
if ("value_dis_real_2018_total" %in% names(dt)) {
  dt[, value_dis_real_2018_total := as.numeric(value_dis_real_2018_total)]
} else {
  dt[, value_dis_real_2018_total := 0]
  cat("  WARNING: value_dis_real_2018_total not in panel; bndes_share will be NA.\n")
}

# =============================================================================
# Filter to F_pre Support
# =============================================================================

cat("\nStep 2: Filtering to F_pre support...\n")

f_pre_year_map <- build_f_pre_year_map()
f_pre_year_map <- f_pre_year_map[year %in% unique(dt$year)]

support_cols <- c("firm_id", "muni_id", "cnae_section")
join_cols <- c(support_cols, "year")

cell_years <- unique(dt[, ..join_cols])
cell_years[, in_f_pre := FALSE]
for (curr_year in sort(unique(f_pre_year_map$year))) {
  base_years <- f_pre_year_map[year == curr_year, baseline_year]
  base_cells <- unique(cell_years[year %in% base_years, ..support_cols])
  if (!nrow(base_cells)) next
  base_cells[, year := curr_year]
  cell_years[base_cells, in_f_pre := TRUE, on = join_cols]
}

supported_keys <- cell_years[in_f_pre == TRUE, ..join_cols]
dt_pre <- dt[supported_keys, on = join_cols, nomatch = 0L]

cat(sprintf("  F_pre base: %s rows (%.1f%% of panel)\n",
            format(nrow(dt_pre), big.mark = ","),
            100 * nrow(dt_pre) / nrow(dt)))
cat(sprintf("  Unique firms: %s, munis: %s\n",
            format(uniqueN(dt_pre$firm_id), big.mark = ","),
            format(uniqueN(dt_pre$muni_id), big.mark = ",")))

rm(dt, cell_years, supported_keys)
invisible(gc())

# Test subsample
if (parsed_args$test) {
  set.seed(20260406L)
  muni_ids <- sort(unique(dt_pre$muni_id))
  sample_size <- max(1L, ceiling(0.10 * length(muni_ids)))
  sample_munis <- sort(sample(muni_ids, size = sample_size))
  dt_pre <- dt_pre[muni_id %in% sample_munis]
  cat(sprintf("  Test subsample: %d / %d munis (%s rows)\n",
              sample_size, length(muni_ids), format(nrow(dt_pre), big.mark = ",")))
}

# =============================================================================
# Join All Required Sector Classifications
# =============================================================================

cat("\nStep 3: Joining sector classifications...\n")

required_sector_vars <- unique(config_dt$sector_var)
for (sv in required_sector_vars) {
  cat(sprintf("  Joining: %s\n", sv))
  dt_pre <- join_sector_classification(dt_pre, sv)
}

# =============================================================================
# Main Loop: Group by (sector_var, baseline) -> aggregation -> config
# =============================================================================

cat("\nStep 4: Running estimation loop...\n")

manifest_rows <- list()
summary_rows <- list()
total_models <- 0L

# Group configs by sector_var for output directory
for (sv in unique(config_dt$sector_var)) {
  sv_configs <- config_dt[sector_var == sv]
  sector_col <- get_sector_col(sv)
  suffix <- get_table_dir_suffix(sv)
  table_dir <- file.path(TABLES_DIR, paste0("agg_firm", suffix))
  if (parsed_args$test) table_dir <- file.path(table_dir, "test")
  TABLE_DIR <- table_dir
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

  cat(sprintf("\n=== Sector var: %s (col=%s, dir=%s) ===\n", sv, sector_col, table_dir))

  if (!sector_col %in% names(dt_pre)) {
    cat(sprintf("  WARNING: column '%s' not found — skipping all configs for %s.\n", sector_col, sv))
    for (i in seq_len(nrow(sv_configs))) {
      cfg <- sv_configs[i]
      dep_info <- DEPVAR_INFO[[cfg$outcome]]
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg, dep_info$depvar, list(), COMBOS, 0, 0, 0, 0,
        "skipped", paste0("sector column '", sector_col, "' not found")
      )
    }
    next
  }

  # Cache collapsed panels by aggregation
  collapsed_cache <- list()

  for (i in seq_len(nrow(sv_configs))) {
    cfg <- sv_configs[i]
    dep_info <- DEPVAR_INFO[[cfg$outcome]]
    slug <- cfg$canonical_slug

    cat(sprintf("\n[%s]\n", slug))

    config_t0 <- proc.time()

    # Get or build collapsed panel for this aggregation
    cache_key <- cfg$aggregation
    if (is.null(collapsed_cache[[cache_key]])) {
      cat(sprintf("  Collapsing: aggregation=%s\n", cfg$aggregation))
      agg_dt <- collapse_agg_panel(dt_pre, fa_cols, sector_col, aggregation = cfg$aggregation)
      cat(sprintf("  Cells: %s\n", format(nrow(agg_dt), big.mark = ",")))
      collapsed_cache[[cache_key]] <- agg_dt
    }
    agg_dt <- collapsed_cache[[cache_key]]

    # Filter to valid outcome
    depvar <- dep_info$depvar
    if (!depvar %in% names(agg_dt)) {
      elapsed_total <- as.numeric((proc.time() - config_t0)[["elapsed"]])
      cat(sprintf("  WARNING: depvar '%s' not in collapsed panel — skipping.\n", depvar))
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg, depvar, list(), COMBOS, 0, 0, 0, elapsed_total,
        "skipped", paste0("depvar '", depvar, "' not available")
      )
      next
    }

    # Filter to non-NA outcome rows; for emp_weighted, also filter emp_pre > 0
    sample_mask <- !is.na(agg_dt[[depvar]])
    if (identical(cfg$regression_weight, "emp_weighted")) {
      sample_mask <- sample_mask & is.finite(agg_dt$emp_pre) & agg_dt$emp_pre > 0
    }
    agg_sample <- agg_dt[sample_mask]

    if (!nrow(agg_sample)) {
      elapsed_total <- as.numeric((proc.time() - config_t0)[["elapsed"]])
      cat("  WARNING: empty estimation sample.\n")
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg, depvar, list(), COMBOS, 0, 0, 0, elapsed_total,
        "failed", "empty estimation sample"
      )
      next
    }

    cat(sprintf("  Sample: %s cells\n", format(nrow(agg_sample), big.mark = ",")))

    year_ref <- min(agg_sample$year, na.rm = TRUE)

    # Run 6 combos
    fit_t0 <- proc.time()
    run_result <- run_six_combos(cfg, agg_sample, sector_col, year_ref)
    elapsed_fit <- as.numeric((proc.time() - fit_t0)[["elapsed"]])
    mods <- run_result$mods
    failed_combos <- run_result$failed_combos

    if (!length(mods)) {
      elapsed_total <- as.numeric((proc.time() - config_t0)[["elapsed"]])
      cat("  WARNING: all combos failed.\n")
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg, depvar, mods, if (length(failed_combos)) failed_combos else COMBOS,
        elapsed_fit, 0, 0, elapsed_total, "failed", "all combos failed"
      )
      rm(mods); gc(verbose = FALSE)
      next
    }

    # F-stats
    fstats <- vapply(mods, safe_wald, numeric(1))
    cat(sprintf("  F-stat range: [%.2f, %.2f]\n",
                if (any(is.finite(fstats))) min(fstats, na.rm = TRUE) else NA_real_,
                if (any(is.finite(fstats))) max(fstats, na.rm = TRUE) else NA_real_))

    # Save table
    elapsed_table <- 0
    tex_path <- NA_character_
    status <- "completed"
    skip_reason <- NA_character_

    table_t0 <- proc.time()
    tryCatch({
      save_beamer_table(
        mods = mods,
        filename = slug,
        dep_var = dep_info$dep_label,
        notes = build_table_notes(cfg, sector_col),
        add_f_stat = TRUE,
        fstat_keep = "^FA_bar_",
        table_dir = table_dir
      )
      tex_path <- file.path(table_dir, paste0(slug, ".tex"))
    }, error = function(e) {
      status <<- "failed"
      skip_reason <<- paste0("table save failed: ", conditionMessage(e))
    })
    elapsed_table <- as.numeric((proc.time() - table_t0)[["elapsed"]])

    # Extract summary
    elapsed_summary <- 0
    if (identical(status, "completed")) {
      summary_t0 <- proc.time()
      summary_dt <- extract_summary(mods, cfg, slug)
      elapsed_summary <- as.numeric((proc.time() - summary_t0)[["elapsed"]])
      if (!is.null(summary_dt) && nrow(summary_dt)) {
        summary_rows[[length(summary_rows) + 1L]] <- summary_dt
      }
      total_models <- total_models + length(mods)
    }

    elapsed_total <- as.numeric((proc.time() - config_t0)[["elapsed"]])
    manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
      cfg, depvar, mods, failed_combos,
      elapsed_fit, elapsed_table, elapsed_summary, elapsed_total,
      status, skip_reason,
      if (identical(status, "completed")) tex_path else NA_character_
    )

    cat(sprintf("  Timing: fit=%.1fs, table=%.1fs, total=%.1fs\n",
                elapsed_fit, elapsed_table, elapsed_total))

    rm(mods, agg_sample)
    gc(verbose = FALSE)
  }

  # Save manifest and summary per sector_var
  manifest_dt <- if (length(manifest_rows)) {
    rbindlist(manifest_rows, fill = TRUE)
  } else {
    data.table()
  }

  # Filter to this sector_var's rows for saving
  sv_manifest <- manifest_dt[sector_var == sv]
  sv_summary <- if (length(summary_rows)) {
    tmp <- rbindlist(summary_rows, fill = TRUE)
    tmp[sector_var == sv]
  } else {
    data.table()
  }

  if (nrow(sv_manifest)) {
    manifest_csv_path <- file.path(table_dir, "agg_firm_run_manifest.csv")
    manifest_qs2_path <- file.path(table_dir, "agg_firm_run_manifest.qs2")
    replace_slugs <- unique(sv_manifest$canonical_slug)

    existing_manifest <- read_existing_artifact(manifest_qs2_path, qs_read)
    if (is.null(existing_manifest)) {
      existing_manifest <- read_existing_artifact(manifest_csv_path, fread)
    }
    merged_manifest <- merge_existing_runs(existing_manifest, sv_manifest, replace_slugs,
                                           order_cols = c("baseline", "canonical_slug"))
    write_csv_atomic(merged_manifest, manifest_csv_path)
    write_qs_atomic(merged_manifest, manifest_qs2_path)
    cat(sprintf("  Manifest saved: %s\n", manifest_csv_path))
  }

  if (nrow(sv_summary)) {
    summary_path <- file.path(table_dir, "agg_firm_fc_battery_summary.qs2")
    replace_slugs <- unique(sv_summary$canonical_slug)
    existing_summary <- read_existing_artifact(summary_path, qs_read)
    merged_summary <- merge_existing_runs(existing_summary, sv_summary, replace_slugs,
                                          order_cols = c("baseline", "canonical_slug", "combo", "variable"))
    write_qs_atomic(merged_summary, summary_path)
    cat(sprintf("  Summary saved: %s\n", summary_path))
  }

  rm(collapsed_cache)
  gc(verbose = FALSE)
}

# =============================================================================
# Final Summary
# =============================================================================

elapsed_total <- as.numeric((proc.time() - script_t0)[["elapsed"]])

cat("\n==============================================================================\n")
cat("Aggregated firm -> sector first stage complete.\n")
cat(sprintf("Total: %.1f min (%d configs, %d models)\n",
            elapsed_total / 60, nrow(config_dt), total_models))
cat("==============================================================================\n")
