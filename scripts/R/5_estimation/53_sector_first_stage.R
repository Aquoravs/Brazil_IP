#!/usr/bin/env Rscript

# ==============================================================================
# First-Stage Regressions: Sector-Level BNDES Reallocation
# ==============================================================================
#
# Spec-engine refactor of the sector first stage. The default config matches the
# current baseline levels specification:
#   s_mjt ~ Z_mjt + exposure controls interacted with year dummies
#   FE: municipality x sector + sector x year
#   SE: two-way clustered by municipality and sector
#
# Dimensions:
#   time_variation   = changes | levels
#   instrument_weight= owner_count | employment | equal_firm | binary
#   baseline         = cycle_specific | 2002_fixed
#   alignment        = coalition | party
#   fe               = mxj_jxt | mxj_mxt | mxj_year
#   exposure_control = yes | no
#   muni_sample      = all | top_q4 | bottom_3q
#   muni_interaction = none | top_q4_muni
#
# Named specs (new):
#   top_q4_sample       - muni_sample=top_q4 (top-quartile munis only)
#   bottom_3q_sample    - muni_sample=bottom_3q (bottom three-quartile munis only)
#   muni_interaction    - muni_interaction=top_q4_muni (instruments × top_q4_muni dummy)
#
# Usage examples:
#   Rscript 53_sector_first_stage.R --specs=baseline
#   Rscript 53_sector_first_stage.R --specs=weight_battery
#   Rscript 53_sector_first_stage.R --specs=baseline --fe=mxj_mxt --alignment=party
#   Rscript 53_sector_first_stage.R --specs=all --dry-run
#   Rscript 53_sector_first_stage.R --specs=baseline --test
#   Rscript 53_sector_first_stage.R --specs=baseline --muni-interaction=top_q4_muni
#   Rscript 53_sector_first_stage.R --specs=baseline --muni-sample=top_q4,bottom_3q
# ==============================================================================

cat("==============================================================================\n")
cat("First-Stage: Sector-Level BNDES Reallocation\n")
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
    script_file <- normalizePath(sub("^--file=", "", script_file[[1]]), winslash = "/", mustWork = TRUE)
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

fixest::setFixest_nthreads(4)
source(politicsregs_path("_utils", "beamer_tables.R"))

DIMENSION_OPTIONS <- list(
  time_variation = c("changes", "levels"),
  instrument_weight = c("owner_count", "employment", "equal_firm", "binary"),
  baseline = c("cycle_specific", "2002_fixed"),
  alignment = c("coalition", "party"),
  fe = c("mxj_jxt", "mxj_mxt", "mxj_year"),
  exposure_control = c("yes", "no"),
  muni_sample = c("all", "top_q4", "bottom_3q"),
  muni_interaction = c("none", "top_q4_muni")
)

DEFAULT_DIMENSIONS <- list(
  time_variation = "levels",
  instrument_weight = "owner_count",
  baseline = "cycle_specific",
  alignment = "coalition",
  fe = "mxj_jxt",
  exposure_control = "yes",
  muni_sample = "all",
  muni_interaction = "none"
)

SPEC_CATALOG <- list(
  baseline        = list(),
  changes         = list(),
  levels          = list(time_variation = "levels"),
  fe_muni_year    = list(fe = "mxj_mxt"),
  fe_year         = list(fe = "mxj_year"),
  party           = list(alignment = "party"),
  no_controls     = list(exposure_control = "no"),
  fixed_baseline  = list(baseline = "2002_fixed"),
  weight_battery  = list(instrument_weight = DIMENSION_OPTIONS$instrument_weight),
  top_q4_sample   = list(muni_sample = "top_q4"),
  bottom_3q_sample = list(muni_sample = "bottom_3q"),
  muni_interaction = list(muni_interaction = "top_q4_muni")
)

COMBOS <- list(
  Mayor = "mayor",
  Governor = "gov",
  President = "pres",
  `M+G` = c("mayor", "gov"),
  `M+P` = c("mayor", "pres"),
  All = c("mayor", "gov", "pres")
)

DEPVAR_INFO <- list(
  changes = list(depvar = "delta_s_mjt", dep_label = "$\\Delta s_{mjt}$"),
  levels = list(depvar = "s_mjt", dep_label = "$s_{mjt}$")
)

# Build DEPVAR_INFO from panel attributes (share_col / dshare_col set by script 41).
# Under --endogenous=emp_share: share_col=s_emp_mjt, dshare_col=delta_s_emp_mjt.
# Under --endogenous=bndes_credit (legacy): share_col=s_mjt, dshare_col=delta_s_mjt.
build_depvar_info <- function(share_col, dshare_col, endogenous) {
  share_label <- if (identical(endogenous, "emp_share")) {
    "$s^{\\text{emp}}_{mjt}$"
  } else {
    "$s^{\\text{credit}}_{mjt}$"
  }
  dshare_label <- if (identical(endogenous, "emp_share")) {
    "$\\Delta s^{\\text{emp}}_{mjt}$"
  } else {
    "$\\Delta s^{\\text{credit}}_{mjt}$"
  }
  list(
    changes = list(depvar = dshare_col, dep_label = dshare_label),
    levels  = list(depvar = share_col,  dep_label = share_label)
  )
}

normalize_dimension_name <- function(name) {
  gsub("-", "_", name)
}

valid_option_flags <- function() {
  c(
    "--specs",
    "--time-variation",
    "--time_variation",
    "--instrument-weight",
    "--instrument_weight",
    "--baseline",
    "--alignment",
    "--fe",
    "--exposure-control",
    "--exposure_control",
    "--muni-sample",
    "--muni_sample",
    "--muni-interaction",
    "--muni_interaction",
    "--test",
    "--dry-run",
    "--sector-var",
    "--endogenous"
  )
}

build_slug <- function(row) {
  parts <- c(
    "sector",
    row$time_variation,
    row$instrument_weight,
    row$alignment,
    row$baseline,
    row$fe,
    if (identical(row$exposure_control, "yes")) "ctrl" else "noctrl"
  )
  if (!is.null(row$muni_sample) && !identical(row$muni_sample, "all")) {
    parts <- c(parts, row$muni_sample)
  }
  if (!is.null(row$muni_interaction) && !identical(row$muni_interaction, "none")) {
    parts <- c(parts, "mint")
  }
  paste(parts, collapse = "__")
}

merge_dimension_overrides <- function(base_dims, overrides) {
  out <- base_dims
  for (nm in names(overrides)) {
    out[[nm]] <- overrides[[nm]]
  }
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
    if (identical(arg, "--test")) {
      parsed$test <- TRUE
      next
    }
    if (identical(arg, "--dry-run")) {
      parsed$dry_run <- TRUE
      next
    }

    if (!grepl("^--[^=]+=", arg)) {
      stop("Unknown option: ", arg, ". Valid options: ", paste(valid_option_flags(), collapse = ", "))
    }

    key <- sub("^--([^=]+)=.*$", "\\1", arg)
    value <- sub("^--[^=]+=", "", arg)
    key <- normalize_dimension_name(key)

    if (!nzchar(value)) {
      stop("Option requires a value: --", key)
    }

    values <- strsplit(value, ",", fixed = TRUE)[[1L]]
    values <- trimws(values)
    values <- values[nzchar(values)]
    if (!length(values)) {
      stop("Option requires at least one value: --", key)
    }

    if (identical(key, "specs")) {
      spec_names <- unique(values)
      if ("all" %in% spec_names) {
        spec_names <- names(SPEC_CATALOG)
      }
      unknown_specs <- setdiff(spec_names, names(SPEC_CATALOG))
      if (length(unknown_specs)) {
        stop(
          "Unknown spec bundle: ", paste(unknown_specs, collapse = ", "),
          ". Valid: ", paste(c(names(SPEC_CATALOG), "all"), collapse = ", ")
        )
      }
      parsed$spec_names <- spec_names
      next
    }

    if (!key %in% valid_dims) {
      stop("Unknown option: --", key, ". Valid options: ", paste(valid_option_flags(), collapse = ", "))
    }

    invalid_vals <- setdiff(values, DIMENSION_OPTIONS[[key]])
    if (length(invalid_vals)) {
      stop(
        "Invalid value '", invalid_vals[[1L]], "' for --", key,
        ". Valid: ", paste(DIMENSION_OPTIONS[[key]], collapse = ", ")
      )
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
        cat(sprintf(
          "WARNING: --%s=%s overrides the defining dimension of bundle '%s'.\n",
          gsub("_", "-", nm),
          paste(override_vals, collapse = ","),
          spec_name
        ))
      }
    }

    seeded <- merge_dimension_overrides(seeded, parsed_args$dim_overrides)
    seeded_configs[[i]] <- expand_dimension_grid(seeded)
  }

  config_dt <- unique(rbindlist(seeded_configs, fill = TRUE))
  config_dt[, canonical_slug := vapply(seq_len(.N), function(i) build_slug(config_dt[i]), character(1))]
  # FE guardrail: interaction with time-invariant muni flag is not identified under mxj_mxt.
  invalid_int_fe <- config_dt[muni_interaction != "none" & fe == "mxj_mxt"]
  if (nrow(invalid_int_fe)) {
    stop(
      "Interaction with time-invariant muni flag (top_q4_muni) is not identified under mxj_mxt FE; ",
      "use mxj_jxt instead.\n  Affected configs: ",
      paste(invalid_int_fe$canonical_slug, collapse = ", ")
    )
  }

  config_dt[, degenerate_warning := fifelse(
    fe == "mxj_mxt" & exposure_control == "yes",
    "exposure_control near-collinear with FE",
    NA_character_
  )]
  config_dt[, order_baseline := match(baseline, c("cycle_specific", "2002_fixed"))]
  config_dt[, order_time := match(time_variation, c("changes", "levels"))]
  setorder(config_dt, order_baseline, order_time, canonical_slug)
  config_dt[, c("order_baseline", "order_time") := NULL]
  config_dt
}

print_config_table <- function(config_dt) {
  cols <- c("canonical_slug", "time_variation", "instrument_weight", "alignment",
            "baseline", "fe", "exposure_control", "muni_sample", "muni_interaction",
            "degenerate_warning")
  cols <- intersect(cols, names(config_dt))
  print(config_dt[, ..cols])
}

weight_infix <- function(instrument_weight) {
  switch(
    instrument_weight,
    owner_count = "",
    employment = "emp_",
    equal_firm = "firm_",
    binary = "binary_",
    stop("Unknown instrument_weight: ", instrument_weight)
  )
}

control_stub <- function(instrument_weight) {
  switch(
    instrument_weight,
    owner_count = "",
    employment = "emp_",
    equal_firm = "firm_",
    binary = "binary_",
    stop("Unknown instrument_weight: ", instrument_weight)
  )
}

build_instrument_col <- function(time_variation, tier, alignment, baseline, instrument_weight) {
  infix <- weight_infix(instrument_weight)
  prefix <- if (identical(time_variation, "changes")) "dZ_" else "Z_"
  paste0(prefix, infix, tier, "_", alignment, "_", baseline)
}

build_control_cols <- function(baseline, instrument_weight) {
  stub <- control_stub(instrument_weight)
  base <- if (nzchar(stub)) paste0("exposure_control_", sub("_$", "", stub)) else "exposure_control"
  c(
    mayor = paste0(base, "_mayor_", baseline),
    gov_pres = paste0(base, "_gov_pres_", baseline)
  )
}

build_fe_formula <- function(fe_key, sector_col) {
  switch(
    fe_key,
    mxj_jxt = paste0("muni_id^", sector_col, " + ", sector_col, "^year"),
    mxj_mxt = paste0("muni_id^", sector_col, " + muni_id^year"),
    mxj_year = paste0("muni_id^", sector_col, " + year"),
    stop("Unknown FE key: ", fe_key)
  )
}

safe_wald <- function(mod, pattern) {
  tryCatch({
    fixest::wald(mod, keep = pattern)$stat
  }, error = function(e) NA_real_)
}

write_qs_atomic <- function(obj, path) {
  tmp <- tempfile(pattern = "sector-run-", tmpdir = dirname(path), fileext = ".qs2")
  qs_save(obj, tmp)
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Failed to write file: ", path)
}

write_csv_atomic <- function(dt, path) {
  tmp <- tempfile(pattern = "sector-run-", tmpdir = dirname(path), fileext = ".csv")
  fwrite(dt, tmp)
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Failed to write file: ", path)
}

coerce_panel_types <- function(dt, sector_col) {
  setDT(dt)
  dt[, muni_id := as.integer(muni_id)]
  dt[, year := as.integer(year)]
  if (sector_col %in% names(dt)) {
    dt[, (sector_col) := as.character(get(sector_col))]
  }
  dt
}

fit_model <- function(formula_str, data, sector_col) {
  feols(
    as.formula(formula_str),
    data = data,
    vcov = as.formula(paste0("~ muni_id + ", sector_col)),
    lean = TRUE
  )
}

make_ctrl_interactions <- function(ctrl_vec, year_ref, include_control = TRUE) {
  if (!include_control) return("")
  ctrl_vec <- unique(ctrl_vec[!is.na(ctrl_vec) & nzchar(ctrl_vec)])
  if (!length(ctrl_vec)) return("")
  terms <- paste0("i(year, ", ctrl_vec, ", ref = ", year_ref, ")")
  paste0(" + ", paste(terms, collapse = " + "))
}

record_collinearity <- function(mod, combo_name) {
  if (length(mod$collin.var) > 0) {
    cat(sprintf("  Collinearity in '%s': dropped %s\n",
                combo_name, paste(mod$collin.var, collapse = ", ")))
  }
}

run_six_combos <- function(cfg, dt, sector_col, year_ref) {
  dep_info <- DEPVAR_INFO[[cfg$time_variation]]
  depvar <- dep_info$depvar
  fe_formula <- build_fe_formula(cfg$fe, sector_col)
  ctrl <- build_control_cols(cfg$baseline, cfg$instrument_weight)
  include_control <- identical(cfg$exposure_control, "yes")
  use_muni_int <- !is.null(cfg$muni_interaction) && !identical(cfg$muni_interaction, "none")

  z_m <- build_instrument_col(cfg$time_variation, "mayor", cfg$alignment, cfg$baseline, cfg$instrument_weight)
  z_g <- build_instrument_col(cfg$time_variation, "gov", cfg$alignment, cfg$baseline, cfg$instrument_weight)
  z_p <- build_instrument_col(cfg$time_variation, "pres", cfg$alignment, cfg$baseline, cfg$instrument_weight)

  # Add interaction terms (instrument × top_q4_muni) when flag is set.
  # The main effect of top_q4_muni is time-invariant per muni and is absorbed by
  # the muni^sector FE. Only the interaction is identified.
  add_interactions <- function(insts) {
    if (!use_muni_int) return(insts)
    c(insts, paste0(insts, ":top_q4_muni"))
  }

  mods <- list()
  failed <- character(0)

  fit_combo <- function(name, rhs_terms, ctrl_terms) {
    ctrl_str <- make_ctrl_interactions(ctrl_terms, year_ref = year_ref, include_control = include_control)
    fml <- paste0(depvar, " ~ ", paste(rhs_terms, collapse = " + "), ctrl_str, " | ", fe_formula)
    mod <- tryCatch(
      fit_model(fml, dt, sector_col = sector_col),
      error = function(e) {
        cat(sprintf("  WARNING: combo '%s' failed: %s\n", name, conditionMessage(e)))
        NULL
      }
    )
    if (is.null(mod)) {
      failed <<- c(failed, name)
      return(invisible(NULL))
    }
    record_collinearity(mod, name)
    mods[[name]] <<- mod
    invisible(NULL)
  }

  if (z_m %in% names(dt)) fit_combo("Mayor",     add_interactions(z_m),           ctrl["mayor"])
  if (z_g %in% names(dt)) fit_combo("Governor",  add_interactions(z_g),           ctrl["gov_pres"])
  if (z_p %in% names(dt)) fit_combo("President", add_interactions(z_p),           ctrl["gov_pres"])
  if (all(c(z_m, z_g) %in% names(dt)))       fit_combo("M+G", add_interactions(c(z_m, z_g)), ctrl)
  if (all(c(z_m, z_p) %in% names(dt)))       fit_combo("M+P", add_interactions(c(z_m, z_p)), ctrl)
  if (all(c(z_m, z_g, z_p) %in% names(dt))) fit_combo("All", add_interactions(c(z_m, z_g, z_p)), ctrl)

  list(mods = mods, failed_combos = unique(failed))
}

build_table_notes <- function(cfg, sector_col, endogenous = "emp_share") {
  endo_label <- if (identical(endogenous, "emp_share")) {
    "Endogenous variable: sector employment share $s^{\\text{emp}}_{mjt}$ (D24 primary)."
  } else {
    "Endogenous variable: BNDES credit share $s^{\\text{credit}}_{mjt}$ (mechanism check)."
  }
  fe_label <- switch(
    cfg$fe,
    mxj_jxt = "Muni $\\times$ sector + sector $\\times$ year FE.",
    mxj_mxt = "Muni $\\times$ sector + muni $\\times$ year FE.",
    mxj_year = "Muni $\\times$ sector + year FE."
  )
  weight_label <- switch(
    cfg$instrument_weight,
    owner_count = "Owner-count exposure weights.",
    employment = "Employment-weighted exposure weights.",
    equal_firm = "Equal-firm exposure weights.",
    binary = "Binary exposure weights."
  )
  muni_sample_label <- if (!is.null(cfg$muni_sample)) {
    switch(
      cfg$muni_sample,
      all      = NULL,
      top_q4   = "Sample: top-quartile municipalities by mean RAIS employment (2002--2017).",
      bottom_3q = "Sample: bottom three-quartile municipalities by mean RAIS employment (2002--2017).",
      NULL
    )
  } else {
    NULL
  }
  muni_int_label <- if (!is.null(cfg$muni_interaction) && cfg$muni_interaction != "none") {
    "Instruments interacted with top-quartile municipality employment dummy."
  } else {
    NULL
  }
  notes <- c(
    endo_label,
    fe_label,
    if (identical(cfg$alignment, "coalition")) "Coalition alignment." else "Party alignment.",
    if (identical(cfg$baseline, "cycle_specific")) "Cycle-specific baseline." else "2002-fixed baseline.",
    weight_label,
    if (identical(cfg$exposure_control, "yes")) {
      "Municipality-sector exposure controls interacted with year dummies."
    } else {
      "No municipality-sector exposure controls."
    },
    muni_sample_label,
    muni_int_label,
    sprintf("SEs clustered by muni + %s in parentheses.", if (identical(sector_col, "sector_group")) "sector" else "sector"),
    "$^{***}p<0.01$, $^{**}p<0.05$, $^{*}p<0.10$."
  )
  paste(notes[!is.na(notes) & nzchar(notes)], collapse = " ")
}

extract_sector_summary <- function(mods, cfg, spec_label) {
  if (!length(mods)) {
    return(NULL)
  }

  rbindlist(lapply(names(mods), function(combo_name) {
    mod <- mods[[combo_name]]
    ct <- coeftable(mod)
    inst_rows <- grepl("^(dZ_|Z_)", rownames(ct))
    if (!any(inst_rows)) {
      return(NULL)
    }

    data.table(
      canonical_slug = spec_label,
      combo = combo_name,
      variable = rownames(ct)[inst_rows],
      coef = ct[inst_rows, "Estimate"],
      se = ct[inst_rows, "Std. Error"],
      t_stat = ct[inst_rows, "t value"],
      p_value = ct[inst_rows, "Pr(>|t|)"],
      r2 = tryCatch(fixest::r2(mod, "r2"), error = function(e) NA_real_),
      wald_f = safe_wald(mod, "^(dZ_|Z_)"),
      control_wald_f = safe_wald(mod, "exposure_control"),
      n_obs = nobs(mod),
      n_collin = length(mod$collin.var),
      time_variation = cfg$time_variation,
      instrument_weight = cfg$instrument_weight,
      alignment = cfg$alignment,
      baseline = cfg$baseline,
      fe = cfg$fe,
      exposure_control = cfg$exposure_control
    )
  }), fill = TRUE)
}

append_manifest_row <- function(cfg, depvar, mods, failed_combos, elapsed_fit_sec,
                                elapsed_table_sec, elapsed_summary_sec, elapsed_sec,
                                status, skip_reason = NA_character_,
                                tex_path = NA_character_) {
  inst_fstats <- if (length(mods)) vapply(mods, safe_wald, numeric(1), pattern = "^(dZ_|Z_)") else numeric(0)
  inst_fstats <- inst_fstats[is.finite(inst_fstats)]
  ctrl_fstats <- if (length(mods)) vapply(mods, safe_wald, numeric(1), pattern = "exposure_control") else numeric(0)
  ctrl_fstats <- ctrl_fstats[is.finite(ctrl_fstats)]

  data.table(
    canonical_slug = cfg$canonical_slug,
    time_variation = cfg$time_variation,
    instrument_weight = cfg$instrument_weight,
    alignment = cfg$alignment,
    baseline = cfg$baseline,
    fe = cfg$fe,
    exposure_control = cfg$exposure_control,
    muni_sample = if (!is.null(cfg$muni_sample)) cfg$muni_sample else "all",
    muni_interaction = if (!is.null(cfg$muni_interaction)) cfg$muni_interaction else "none",
    depvar = depvar,
    n_obs = if (length(mods)) as.integer(min(vapply(mods, nobs, numeric(1)))) else NA_integer_,
    n_combos_run = length(mods),
    n_combos_failed = length(failed_combos),
    wald_f_min = if (length(inst_fstats)) min(inst_fstats) else NA_real_,
    wald_f_max = if (length(inst_fstats)) max(inst_fstats) else NA_real_,
    control_wald_f_min = if (length(ctrl_fstats)) min(ctrl_fstats) else NA_real_,
    control_wald_f_max = if (length(ctrl_fstats)) max(ctrl_fstats) else NA_real_,
    elapsed_fit_sec = as.numeric(elapsed_fit_sec),
    elapsed_table_sec = as.numeric(elapsed_table_sec),
    elapsed_summary_sec = as.numeric(elapsed_summary_sec),
    elapsed_sec = as.numeric(elapsed_sec),
    status = status,
    skip_reason = skip_reason,
    degenerate_warning = cfg$degenerate_warning,
    tex_path = tex_path
  )
}

validate_required_columns <- function(config_dt, dt_cols) {
  for (i in seq_len(nrow(config_dt))) {
    cfg <- config_dt[i]
    inst_cols <- c(
      build_instrument_col(cfg$time_variation, "mayor", cfg$alignment, cfg$baseline, cfg$instrument_weight),
      build_instrument_col(cfg$time_variation, "gov", cfg$alignment, cfg$baseline, cfg$instrument_weight),
      build_instrument_col(cfg$time_variation, "pres", cfg$alignment, cfg$baseline, cfg$instrument_weight)
    )
    missing_inst <- inst_cols[!inst_cols %in% dt_cols]
    if (length(missing_inst)) {
      stop(
        "Required instrument columns missing for config '", cfg$canonical_slug,
        "': ", paste(missing_inst, collapse = ", ")
      )
    }

    if (identical(cfg$exposure_control, "yes")) {
      ctrl_cols <- build_control_cols(cfg$baseline, cfg$instrument_weight)
      missing_ctrl <- ctrl_cols[!ctrl_cols %in% dt_cols]
      if (length(missing_ctrl)) {
        stop(
          "Required exposure-control columns missing for config '", cfg$canonical_slug,
          "': ", paste(missing_ctrl, collapse = ", ")
        )
      }
    }

    needs_q4 <- (!is.null(cfg$muni_sample) && cfg$muni_sample != "all") ||
                (!is.null(cfg$muni_interaction) && cfg$muni_interaction != "none")
    if (needs_q4 && !"top_q4_muni" %in% dt_cols) {
      stop(
        "Column `top_q4_muni` not found for config '", cfg$canonical_slug,
        "'. Run scripts 41 and 32b first."
      )
    }
  }
}

# --- Parse CLI args ----------------------------------------------------------

script_t0 <- proc.time()
args <- commandArgs(trailingOnly = TRUE)

svar_flag <- grep("^--sector-var=", args, value = TRUE)
SECTOR_VAR <- "sector_group"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[1])))
  if (!SECTOR_VAR %in% c("cnae_section", "sector_group", "policy_block")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'. Use 'cnae_section', 'sector_group', or 'policy_block'.")
  }
}
USE_GROUPS <- identical(SECTOR_VAR, "sector_group")
USE_POLICY_BLOCKS <- identical(SECTOR_VAR, "policy_block")
SCOL <- SECTOR_VAR

# --endogenous flag: governs labels and mechanism-check side regressions.
# The wide-column prefixes in Panel A (s_mjt / delta_s_mjt long) follow the
# panel's `share_col` / `dshare_col` attributes set by script 41.
endo_flag <- grep("^--endogenous=", args, value = TRUE)
ENDOGENOUS <- NA_character_  # NA means: trust the panel attribute
if (length(endo_flag)) {
  ENDOGENOUS <- tolower(trimws(sub("^--endogenous=", "", endo_flag[1])))
  if (!ENDOGENOUS %in% c("emp_share", "bndes_credit")) {
    stop("Invalid --endogenous value: '", ENDOGENOUS,
         "'. Use 'emp_share' or 'bndes_credit'.")
  }
}

spec_args <- args[!grepl("^--sector-var=|^--endogenous=", args)]
parsed_args <- parse_cli_args(spec_args)
config_dt <- resolve_requested_configs(parsed_args)

if (USE_GROUPS) {
  panel_path <- make_output_path("muni_sector_panel_grouped.qs2")
  base_table_dir <- file.path(TABLES_DIR, "sector_grouped")
} else if (USE_POLICY_BLOCKS) {
  panel_path <- make_output_path("muni_sector_panel_policy_block.qs2")
  base_table_dir <- file.path(TABLES_DIR, "sector_policy_block")
} else {
  panel_path <- make_output_path("muni_sector_panel.qs2")
  base_table_dir <- file.path(TABLES_DIR, "sector")
}
table_dir <- if (parsed_args$test) file.path(base_table_dir, "test") else base_table_dir
TABLE_DIR <- table_dir
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

cat("Sector variable:", SECTOR_VAR, "\n")
cat("Specs:", paste(parsed_args$spec_names, collapse = ", "), "\n")
cat("Test mode:", if (parsed_args$test) "yes" else "no", "\n")
cat("Resolved configs:", nrow(config_dt), "\n\n")

if (parsed_args$dry_run) {
  print_config_table(config_dt)
  cat("\nCanonical outputs:\n")
  for (slug in config_dt$canonical_slug) {
    cat("  ", slug, ".tex\n", sep = "")
  }
  cat("\nDry run complete.\n")
  quit(save = "no", status = 0)
}

# --- Load panel --------------------------------------------------------------

cat("Loading muni x sector x year panel...\n")

if (!file.exists(panel_path)) {
  stop("Panel not found: ", panel_path, "\n  Run script 41 first.")
}

dt <- qs_read(panel_path)

# Resolve endogenous variable from panel attributes; --endogenous CLI flag
# (if provided) must agree with the panel attribute.
panel_endo <- attr(dt, "endogenous")
panel_share_col <- attr(dt, "share_col")
panel_dshare_col <- attr(dt, "dshare_col")
if (is.null(panel_endo) || is.null(panel_share_col) || is.null(panel_dshare_col)) {
  # Legacy panels without attributes: fall back to bndes_credit defaults.
  panel_endo <- "bndes_credit"
  panel_share_col <- "s_mjt"
  panel_dshare_col <- "delta_s_mjt"
  cat("  Panel attributes missing; assuming legacy --endogenous=bndes_credit.\n")
}
if (!is.na(ENDOGENOUS) && !identical(ENDOGENOUS, panel_endo)) {
  stop(
    "CLI --endogenous=", ENDOGENOUS,
    " disagrees with panel attribute (endogenous=", panel_endo, ").",
    "\n  Rebuild Panel A with `Rscript run_politicsregs.R 41 -- --endogenous=", ENDOGENOUS,
    "` (and matching --sector-var) before running stage 53."
  )
}
ENDOGENOUS <- panel_endo
DEPVAR_INFO <- build_depvar_info(panel_share_col, panel_dshare_col, ENDOGENOUS)
cat("  Endogenous:", ENDOGENOUS,
    "| share col:", panel_share_col,
    "| dshare col:", panel_dshare_col, "\n")

dt <- coerce_panel_types(dt, sector_col = SCOL)
cat("  Loaded:", format(nrow(dt), big.mark = ","), "rows,", ncol(dt), "cols\n")

# Merge top_q4_muni from muni_employment_classification.qs2 (produced by script 41).
# Required for muni_sample != "all" and muni_interaction != "none".
needs_q4 <- any(config_dt$muni_sample != "all") || any(config_dt$muni_interaction != "none")
if (!"top_q4_muni" %in% names(dt)) {
  muni_class_path <- make_output_path("muni_employment_classification.qs2")
  if (needs_q4 && !file.exists(muni_class_path)) {
    stop(
      "Column `top_q4_muni` not in sector panel and classification file not found: ",
      muni_class_path, "\n  Run scripts 41 (Unit 1) first."
    )
  }
  if (file.exists(muni_class_path)) {
    muni_class <- qs_read(muni_class_path)
    muni_class <- muni_class[, .(muni_id = as.integer(muni_id), top_q4_muni)]
    dt[, top_q4_muni := NA_integer_]
    dt[muni_class, top_q4_muni := i.top_q4_muni, on = "muni_id"]
    n_q4_na <- sum(is.na(dt$top_q4_muni))
    cat(sprintf("  Merged top_q4_muni: %d/%d rows classified, %d NA\n",
                sum(!is.na(dt$top_q4_muni)), nrow(dt), n_q4_na))
    rm(muni_class)
  }
}

if (parsed_args$test) {
  set.seed(20260324L)
  muni_ids <- sort(unique(dt$muni_id))
  sample_size <- max(1L, ceiling(0.10 * length(muni_ids)))
  sample_munis <- sort(sample(muni_ids, size = sample_size))
  dt <- dt[muni_id %in% sample_munis]
  cat(sprintf("  Test subsample: %d / %d municipalities (%d rows)\n",
              sample_size, length(muni_ids), nrow(dt)))
}

validate_required_columns(config_dt, names(dt))

sample_masks <- list(
  changes = !is.na(dt[[DEPVAR_INFO$changes$depvar]]),
  levels  = !is.na(dt[[DEPVAR_INFO$levels$depvar]])
)

cat(sprintf("  Final sample frame: %s obs, %d munis, %d sectors, %d years\n\n",
            format(nrow(dt), big.mark = ","),
            uniqueN(dt$muni_id),
            uniqueN(dt[[SCOL]]),
            uniqueN(dt$year)))

# --- Run configs -------------------------------------------------------------

manifest_rows <- list()
summary_rows <- list()
total_models <- 0L

for (i in seq_len(nrow(config_dt))) {
  cfg <- config_dt[i]
  dep_info <- DEPVAR_INFO[[cfg$time_variation]]
  cfg_slug <- cfg$canonical_slug

  sample_idx <- sample_masks[[cfg$time_variation]]
  if (is.null(sample_idx) || !any(sample_idx)) {
    manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
      cfg = cfg,
      depvar = dep_info$depvar,
      mods = list(),
      failed_combos = names(COMBOS),
      elapsed_fit_sec = 0,
      elapsed_table_sec = 0,
      elapsed_summary_sec = 0,
      elapsed_sec = 0,
      status = "failed",
      skip_reason = "empty estimation sample"
    )
    next
  }

  dt_cfg <- dt[sample_idx]

  # Apply muni_sample filter (restricts to top-quartile or bottom-3-quartile munis).
  cfg_muni_sample <- if (!is.null(cfg$muni_sample)) cfg$muni_sample else "all"
  if (identical(cfg_muni_sample, "top_q4")) {
    dt_cfg <- dt_cfg[!is.na(top_q4_muni) & top_q4_muni == 1L]
  } else if (identical(cfg_muni_sample, "bottom_3q")) {
    dt_cfg <- dt_cfg[!is.na(top_q4_muni) & top_q4_muni == 0L]
  }

  year_ref_cfg <- min(dt_cfg$year, na.rm = TRUE)

  cat(sprintf("[%s]\n", cfg_slug))
  cat(sprintf("  Sample rows: %s\n", format(nrow(dt_cfg), big.mark = ",")))
  if (!is.na(cfg$degenerate_warning)) {
    cat(sprintf("  Warning: %s\n", cfg$degenerate_warning))
  }

  cfg_t0 <- proc.time()

  fit_t0 <- proc.time()
  run_result <- run_six_combos(cfg, dt_cfg, sector_col = SCOL, year_ref = year_ref_cfg)
  elapsed_fit <- as.numeric((proc.time() - fit_t0)[["elapsed"]])
  mods <- run_result$mods
  failed_combos <- run_result$failed_combos

  if (!length(mods)) {
    elapsed_total <- as.numeric((proc.time() - cfg_t0)[["elapsed"]])
    manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
      cfg = cfg,
      depvar = dep_info$depvar,
      mods = mods,
      failed_combos = if (length(failed_combos)) failed_combos else names(COMBOS),
      elapsed_fit_sec = elapsed_fit,
      elapsed_table_sec = 0,
      elapsed_summary_sec = 0,
      elapsed_sec = elapsed_total,
      status = "failed",
      skip_reason = "all combos failed"
    )
    cat("  WARNING: all combos failed; no table saved.\n\n")
    rm(mods)
    gc(verbose = FALSE)
    next
  }

  instrument_fstats <- vapply(mods, safe_wald, numeric(1), pattern = "^(dZ_|Z_)")
  control_fstats <- if (identical(cfg$exposure_control, "yes")) {
    vapply(mods, safe_wald, numeric(1), pattern = "exposure_control")
  } else {
    rep(NA_real_, length(mods))
  }

  elapsed_table <- 0
  elapsed_summary <- 0
  tex_path <- NA_character_
  status <- "completed"
  skip_reason <- NA_character_

  table_t0 <- proc.time()
  tryCatch({
    save_beamer_table(
      mods = mods,
      filename = cfg_slug,
      dep_var = dep_info$dep_label,
      notes = build_table_notes(cfg, sector_col = SCOL, endogenous = ENDOGENOUS),
      exposure_control_gof = if (identical(cfg$exposure_control, "yes")) "Yes" else "No",
      exposure_control_fstat = control_fstats,
      add_f_stat = TRUE,
      fstat_keep = "^(dZ_|Z_)",
      table_dir = table_dir
    )
    tex_path <- file.path(table_dir, paste0(cfg_slug, ".tex"))
  }, error = function(e) {
    status <<- "failed"
    skip_reason <<- paste0("table save failed: ", conditionMessage(e))
  })
  elapsed_table <- as.numeric((proc.time() - table_t0)[["elapsed"]])

  if (identical(status, "completed")) {
    summary_t0 <- proc.time()
    summary_dt <- extract_sector_summary(mods, cfg, cfg_slug)
    elapsed_summary <- as.numeric((proc.time() - summary_t0)[["elapsed"]])
    if (!is.null(summary_dt) && nrow(summary_dt)) {
      summary_rows[[length(summary_rows) + 1L]] <- summary_dt
    }
    total_models <- total_models + length(mods)
  } else {
    cat(sprintf("  WARNING: failed to save table [%s]: %s\n", cfg_slug, skip_reason))
  }

  elapsed_total <- as.numeric((proc.time() - cfg_t0)[["elapsed"]])
  manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
    cfg = cfg,
    depvar = dep_info$depvar,
    mods = mods,
    failed_combos = failed_combos,
    elapsed_fit_sec = elapsed_fit,
    elapsed_table_sec = elapsed_table,
    elapsed_summary_sec = elapsed_summary,
    elapsed_sec = elapsed_total,
    status = status,
    skip_reason = skip_reason,
    tex_path = if (identical(status, "completed")) tex_path else NA_character_
  )

  cat(sprintf(
    "  Timing (sec): fit=%.1f, table=%.1f, summary=%.1f, total=%.1f\n",
    elapsed_fit, elapsed_table, elapsed_summary, elapsed_total
  ))
  cat(sprintf(
    if (any(is.finite(instrument_fstats))) {
      "  Instrument F range: [%.2f, %.2f]\n"
    } else {
      "  Instrument F range: [NA, NA]\n"
    },
    if (any(is.finite(instrument_fstats))) min(instrument_fstats, na.rm = TRUE) else NA_real_,
    if (any(is.finite(instrument_fstats))) max(instrument_fstats, na.rm = TRUE) else NA_real_
  ))
  if (identical(cfg$exposure_control, "yes") && any(is.finite(control_fstats))) {
    cat(sprintf(
      "  Control F range: [%.2f, %.2f]\n",
      min(control_fstats, na.rm = TRUE), max(control_fstats, na.rm = TRUE)
    ))
  }
  cat("\n")

  rm(mods, dt_cfg)
  gc(verbose = FALSE)
}

# --- Mechanism-check side regressions ----------------------------------------
# When the primary endogenous is employment share, run a small companion battery
# with BNDES credit share as the depvar so readers can compare composition
# (employment) vs. mechanism (credit). Only the requested specs are re-run.
mech_dir <- NA_character_
if (identical(ENDOGENOUS, "emp_share") &&
    all(c("s_credit_mjt", "delta_s_credit_mjt") %in% names(dt))) {
  cat("\n--- Mechanism-check pass: BNDES credit share depvar ---\n")

  mech_dir <- file.path(table_dir, "mech_credit")
  dir.create(mech_dir, recursive = TRUE, showWarnings = FALSE)

  mech_depvar_info <- build_depvar_info(
    share_col = "s_credit_mjt",
    dshare_col = "delta_s_credit_mjt",
    endogenous = "bndes_credit"
  )
  mech_sample_masks <- list(
    changes = !is.na(dt$delta_s_credit_mjt),
    levels  = !is.na(dt$s_credit_mjt)
  )

  for (i in seq_len(nrow(config_dt))) {
    cfg <- config_dt[i]
    dep_info <- mech_depvar_info[[cfg$time_variation]]
    cfg_slug <- paste0(cfg$canonical_slug, "__mech_credit")
    sample_idx <- mech_sample_masks[[cfg$time_variation]]
    if (is.null(sample_idx) || !any(sample_idx)) next
    dt_cfg <- dt[sample_idx]
    cfg_muni_sample <- if (!is.null(cfg$muni_sample)) cfg$muni_sample else "all"
    if (identical(cfg_muni_sample, "top_q4")) {
      dt_cfg <- dt_cfg[!is.na(top_q4_muni) & top_q4_muni == 1L]
    } else if (identical(cfg_muni_sample, "bottom_3q")) {
      dt_cfg <- dt_cfg[!is.na(top_q4_muni) & top_q4_muni == 0L]
    }

    # Temporarily swap depvar by aliasing in the run_six_combos helper.
    # Easiest path: copy dt_cfg with the credit column renamed to the
    # default depvar name expected by run_six_combos.
    dt_alias <- copy(dt_cfg)
    dt_alias[, (panel_dshare_col) := delta_s_credit_mjt]
    dt_alias[, (panel_share_col)  := s_credit_mjt]

    year_ref_cfg <- min(dt_alias$year, na.rm = TRUE)
    cat(sprintf("[mech: %s] sample rows: %s\n",
                cfg_slug, format(nrow(dt_alias), big.mark = ",")))
    run_result <- tryCatch(
      run_six_combos(cfg, dt_alias, sector_col = SCOL, year_ref = year_ref_cfg),
      error = function(e) {
        cat("  WARNING: mech-check run failed:", conditionMessage(e), "\n")
        list(mods = list(), failed_combos = names(COMBOS))
      }
    )
    mods <- run_result$mods
    if (!length(mods)) {
      rm(dt_alias, dt_cfg); gc(verbose = FALSE)
      next
    }
    control_fstats <- if (identical(cfg$exposure_control, "yes")) {
      vapply(mods, safe_wald, numeric(1), pattern = "exposure_control")
    } else {
      rep(NA_real_, length(mods))
    }
    tryCatch({
      save_beamer_table(
        mods = mods,
        filename = cfg_slug,
        dep_var = dep_info$dep_label,
        notes = build_table_notes(cfg, sector_col = SCOL, endogenous = "bndes_credit"),
        exposure_control_gof = if (identical(cfg$exposure_control, "yes")) "Yes" else "No",
        exposure_control_fstat = control_fstats,
        add_f_stat = TRUE,
        fstat_keep = "^(dZ_|Z_)",
        table_dir = mech_dir
      )
    }, error = function(e) {
      cat("  WARNING: mech-check table save failed:", conditionMessage(e), "\n")
    })
    rm(mods, dt_alias, dt_cfg); gc(verbose = FALSE)
  }
  cat(sprintf("Mechanism-check tables saved to: %s\n", mech_dir))
} else if (identical(ENDOGENOUS, "emp_share")) {
  cat("\nNote: s_credit_mjt / delta_s_credit_mjt not present in Panel A; ",
      "mechanism-check pass skipped.\n", sep = "")
}

# --- Save manifest and summary ----------------------------------------------

manifest_dt <- if (length(manifest_rows)) {
  rbindlist(manifest_rows, fill = TRUE)
} else {
  data.table(
    canonical_slug = character(),
    time_variation = character(),
    instrument_weight = character(),
    alignment = character(),
    baseline = character(),
    fe = character(),
    exposure_control = character(),
    muni_sample = character(),
    muni_interaction = character(),
    depvar = character(),
    n_obs = integer(),
    n_combos_run = integer(),
    n_combos_failed = integer(),
    wald_f_min = numeric(),
    wald_f_max = numeric(),
    control_wald_f_min = numeric(),
    control_wald_f_max = numeric(),
    elapsed_fit_sec = numeric(),
    elapsed_table_sec = numeric(),
    elapsed_summary_sec = numeric(),
    elapsed_sec = numeric(),
    status = character(),
    skip_reason = character(),
    degenerate_warning = character(),
    tex_path = character()
  )
}

summary_dt <- if (length(summary_rows)) rbindlist(summary_rows, fill = TRUE) else data.table()

summary_path <- file.path(table_dir, "sector_fc_battery_summary.qs2")
manifest_csv_path <- file.path(table_dir, "sector_run_manifest.csv")
manifest_qs2_path <- file.path(table_dir, "sector_run_manifest.qs2")

write_qs_atomic(summary_dt, summary_path)
write_csv_atomic(manifest_dt, manifest_csv_path)
write_qs_atomic(manifest_dt, manifest_qs2_path)

elapsed_total <- as.numeric((proc.time() - script_t0)[["elapsed"]])

cat("==============================================================================\n")
cat("Sector-level first-stage regressions complete.\n")
cat("Tables saved to:", table_dir, "\n")
cat("Summary saved to:", summary_path, "\n")
cat("Manifest saved to:", manifest_csv_path, "and", manifest_qs2_path, "\n")
cat(sprintf("Total: %.1f min (%d configs, %d models)\n",
            elapsed_total / 60,
            nrow(config_dt),
            total_models))
cat("==============================================================================\n")
