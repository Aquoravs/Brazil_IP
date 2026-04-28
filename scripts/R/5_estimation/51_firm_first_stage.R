#!/usr/bin/env Rscript
# =============================================================================
# 51_firm_first_stage.R - Firm-Level First Stage IV Regressions
# =============================================================================
#
# Estimates firm-level first-stage IV regressions linking political alignment
# instruments (FA_*, dFA_*) to firm-level outcomes. The script is driven by a
# spec engine that resolves CLI arguments into a grid of regression
# configurations and runs each config through a single execution loop.
#
# USAGE:
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 [OPTIONS]
#
# OPTIONS:
#   --specs=NAME[,NAME]     Named bundles to run (default: baseline)
#                           Values: baseline, changes, weighted, party,
#                                   fixed_baseline, single_muni, intensive, all
#   --outcome=VAL[,VAL]     bndes_extensive, bndes_intensive, employment_log,
#                           employment_share (default: bndes_extensive)
#   --exposure=VAL[,VAL]    pooled_count, binary (max-binary: any-year indicator) (default: both)
#   --weighting=VAL[,VAL]   unweighted, emp_weighted, emp_share_weighted (default: unweighted)
#   --baseline=VAL[,VAL]    cycle_specific, 2002_fixed (default: cycle_specific)
#   --alignment=VAL[,VAL]   coalition, party (default: coalition)
#   --time-variation=VAL[,VAL] levels, changes (default: levels)
#   --sample=VAL[,VAL]      all_firms, single_muni, top_q4, bottom_3q (default: all_firms)
#   --family=VAL[,VAL]      main, interaction, interaction_mqemp (default: both)
#   --unweighted            Force unweighted (warns on conflict)
#   --test                  Use 1% firm sample for fast dev iteration
#   --dry-run               Print resolved config table and exit
#
# EXAMPLES:
#   Rscript BNDES/politicsregs/run_politicsregs.R 51
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=weighted
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=all
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 --baseline=2002_fixed
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 --outcome=bndes_intensive --alignment=party
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 --outcome=employment_log --time-variation=changes
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 --alignment=coalition,party --sample=all_firms,single_muni
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 --family=interaction
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 --exposure=binary
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 --test
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 --dry-run
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 -- --specs=weighted
#
# OUTPUT:
#   Tables:   output/firm_reg_tables/firm__<family>__<tv>__<outcome>__<align>__
#             <baseline>__<weighting>__<sample>__<exposure>.tex
#   Manifest: output/firm_reg_tables/firm_run_manifest.csv/.qs2
#   Summary:  output/firm_reg_tables/fc_battery_summary.qs2
#
# NAMED BUNDLES:
#   baseline             - bndes_extensive, both exposures, unweighted, cycle-specific,
#                          coalition, levels, all_firms, both families
#   changes              - baseline + time_variation=changes
#   weighted             - baseline + weighting=emp_weighted (pre-election baseline)
#   party                - baseline + alignment=party
#   fixed_baseline       - baseline + baseline=2002_fixed
#   single_muni          - baseline + sample=single_muni
#   intensive            - baseline + outcome=bndes_intensive
#   emp_share_weighted   - baseline + weighting=emp_share_weighted (muni emp-share weights)
#   top_q4_sample        - baseline + sample=top_q4 (top-quartile munis only)
#   bottom_3q_sample     - baseline + sample=bottom_3q (bottom-three-quartile munis)
#   interaction_muni_emp - baseline + family=interaction_mqemp (instruments × top_q4_muni)
#   all                  - union of all above
#
# INSTRUMENT COMBOS:
#   Main family:        M, G, P, M+G, M+P, M+G+P
#   Interaction family: M+G+MxG, M+G+P+MxG, M+G+P+MxP
# =============================================================================

cat("==============================================================================\n")
cat("Firm-Level First Stage: Political Alignment -> Firm Outcomes\n")
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

n_cores <- suppressWarnings(parallel::detectCores(logical = FALSE))
if (!is.finite(n_cores) || n_cores < 1L) {
  n_cores <- suppressWarnings(parallel::detectCores())
}
if (!is.finite(n_cores) || n_cores < 1L) {
  n_cores <- 1L
}
N_THREADS <- as.integer(n_cores)
setDTthreads(1L)
fixest::setFixest_nthreads(N_THREADS-1)

source(politicsregs_path("_utils", "beamer_tables.R"))
source(politicsregs_path("_utils", "load_firm_panel.R"))

FE_FIRM <- "firm_id + muni_id^year"
VCOV_FIRM <- ~ firm_id + muni_id
WALD_KEEP_PATTERN <- "^(dZ_|Z_|FA_|dFA_)"

DIMENSION_OPTIONS <- list(
  outcome        = c("bndes_extensive", "bndes_intensive", "employment_log", "employment_share"),
  exposure       = c("pooled_count", "binary"),
  weighting      = c("unweighted", "emp_weighted", "emp_share_weighted"),
  baseline       = c("cycle_specific", "2002_fixed"),
  alignment      = c("coalition", "party"),
  time_variation = c("levels", "changes"),
  sample         = c("all_firms", "single_muni", "top_q4", "bottom_3q"),
  family         = c("main", "interaction", "interaction_mqemp")
)

DEFAULT_DIMENSIONS <- list(
  outcome        = "bndes_extensive",
  exposure       = c("pooled_count", "binary"),
  weighting      = "unweighted",
  baseline       = "cycle_specific",
  alignment      = "coalition",
  time_variation = "levels",
  sample         = "all_firms",
  family         = c("main", "interaction")
)

SPEC_CATALOG <- list(
  baseline             = list(),
  changes              = list(time_variation = "changes"),
  weighted             = list(weighting = "emp_weighted"),
  party                = list(alignment = "party"),
  fixed_baseline       = list(baseline = "2002_fixed"),
  single_muni          = list(sample = "single_muni"),
  intensive            = list(outcome = "bndes_intensive"),
  emp_share_weighted   = list(weighting = "emp_share_weighted"),
  top_q4_sample        = list(sample = "top_q4"),
  bottom_3q_sample     = list(sample = "bottom_3q"),
  interaction_muni_emp = list(family = "interaction_mqemp")
)

MAIN_COMBOS <- c("M", "G", "P", "M+G", "M+P", "M+G+P")
INTERACTION_COMBOS <- c("M+G+MxG", "M+G+P+MxG", "M+G+P+MxP")

DEPVAR_INFO <- list(
  bndes_extensive = list(
    levels = list(
      depvar = "has_bndes_fmt",
      dep_label = "$\\mathbf{1}(\\text{BNDES}_{fmt}>0)$",
      sample_note = NA_character_
    ),
    changes = list(
      depvar = "delta_has_bndes_fmt",
      dep_label = "$\\Delta\\mathbf{1}(\\text{BNDES}_{fmt}>0)$",
      sample_note = NA_character_
    )
  ),
  bndes_intensive = list(
    levels = list(
      depvar = "log_bndes_fmt",
      dep_label = "$\\log(\\text{BNDES}_{fmt})$",
      sample_note = "Sample: BNDES $> 0$."
    ),
    changes = list(
      depvar = "delta_log_bndes_fmt",
      dep_label = "$\\Delta\\log(\\text{BNDES}_{fmt})$",
      sample_note = "Sample: BNDES $> 0$ in both $t$ and $t-1$."
    )
  ),
  employment_log = list(
    levels = list(
      depvar = "log_n_employees",
      dep_label = "$\\log(\\text{Employment}_{fmt})$",
      sample_note = "Sample: employment $> 0$."
    ),
    changes = list(
      depvar = "delta_log_n_employees",
      dep_label = "$\\Delta\\log(\\text{Employment}_{fmt})$",
      sample_note = "Sample: employment $> 0$ in both $t$ and $t-1$."
    )
  ),
  employment_share = list(
    levels = list(
      depvar = "emp_share_muni_rais",
      dep_label = "$\\text{RAIS employment share}_{fmt,mt}$",
      sample_note = NA_character_
    ),
    changes = list(
      depvar = "delta_emp_share_muni_rais",
      dep_label = "$\\Delta\\text{RAIS employment share}_{fmt,mt}$",
      sample_note = NA_character_
    )
  )
)

normalize_dimension_name <- function(name) {
  if (identical(name, "time-variation")) {
    return("time_variation")
  }
  name
}

valid_option_flags <- function() {
  c(
    "--specs",
    "--outcome",
    "--exposure",
    "--weighting",
    "--baseline",
    "--alignment",
    "--time-variation",
    "--time_variation",
    "--sample",
    "--family",
    "--unweighted",
    "--test",
    "--dry-run"
  )
}

build_slug <- function(row) {
  paste(
    "firm",
    row$family,
    row$time_variation,
    row$outcome,
    row$alignment,
    row$baseline,
    row$weighting,
    row$sample,
    row$exposure,
    sep = "__"
  )
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
    unweighted = FALSE,
    test = FALSE,
    dry_run = FALSE
  )

  valid_dims <- names(DIMENSION_OPTIONS)

  for (arg in args) {
    if (identical(arg, "--unweighted")) {
      parsed$unweighted <- TRUE
      next
    }
    if (identical(arg, "--test")) {
      parsed$test <- TRUE
      next
    }
    if (identical(arg, "--dry-run")) {
      parsed$dry_run <- TRUE
      next
    }

    if (!grepl("^--[^=]+=", arg)) {
      stop(
        "Unknown option: ", arg,
        ". Valid options: ", paste(valid_option_flags(), collapse = ", ")
      )
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
      stop(
        "Unknown option: --", key,
        ". Valid options: ", paste(valid_option_flags(), collapse = ", ")
      )
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
      if (!is.null(bundle_value) && !bundle_value %in% override_vals) {
        cat(sprintf(
          "WARNING: --%s=%s overrides the defining dimension of bundle '%s'.\n",
          gsub("_", "-", nm),
          paste(override_vals, collapse = ","),
          spec_name
        ))
      }
    }

    seeded <- merge_dimension_overrides(seeded, parsed_args$dim_overrides)
    if (parsed_args$unweighted) {
      if (!identical(seeded$weighting, "unweighted")) {
        cat("WARNING: --unweighted overrides weighting=emp_weighted.\n")
      }
      seeded$weighting <- "unweighted"
    }

    seeded_configs[[i]] <- expand_dimension_grid(seeded)
  }

  config_dt <- unique(rbindlist(seeded_configs, fill = TRUE))
  config_dt[, canonical_slug := vapply(seq_len(.N), function(i) build_slug(config_dt[i]), character(1))]
  config_dt[, baseline_ord := match(baseline, c("cycle_specific", "2002_fixed"))]
  setorder(config_dt, baseline_ord, canonical_slug)
  config_dt[, baseline_ord := NULL]
  config_dt
}

coerce_panel_types <- function(dt) {
  setDT(dt)

  for (col in intersect(c(
    "firm_id", "muni_id", "year",
    "has_bndes_fmt", "delta_has_bndes_fmt",
    "is_multi_muni"
  ), names(dt))) {
    dt[, (col) := as.integer(get(col))]
  }

  if ("n_employees" %in% names(dt)) {
    dt[, n_employees := as.numeric(n_employees)]
  }

  dt
}

get_panel_paths <- function(baseline_value, test_mode = FALSE) {
  # Delegate to the shared loader's path resolver.
  paths <- firm_panel_paths(baseline_value, test_mode = test_mode)
  list(fst = paths$base, qs2 = NULL)
}

get_panel_column_names <- function(paths) {
  # Post-split: base file has panel cols; sparse _instruments file has FA/dFA.
  # Return union so validation logic sees all available columns.
  base_cols <- character(0)
  if (file.exists(paths$fst) && requireNamespace("fst", quietly = TRUE)) {
    base_cols <- fst::metadata_fst(paths$fst)$columnNames
  }
  if (!length(base_cols)) return(NULL)

  # Also enumerate sparse instrument columns if the split file exists.
  inst_path <- sub("\\.fst$", "_instruments.fst", paths$fst)
  inst_cols <- character(0)
  if (file.exists(inst_path) && requireNamespace("fst", quietly = TRUE)) {
    inst_cols <- grep("^(FA_|dFA_)", fst::metadata_fst(inst_path)$columnNames, value = TRUE)
  }

  union(base_cols, inst_cols)
}

load_panel_subset <- function(baseline_value, test_mode = FALSE, keep_cols = NULL) {
  cat(sprintf("Loading panel [%s]%s...\n",
              baseline_value,
              if (isTRUE(test_mode)) " [sample]" else ""))

  # Split keep_cols into base columns vs FA/dFA instrument columns.
  if (!is.null(keep_cols)) {
    inst_cols <- grep("^(FA_|dFA_)", keep_cols, value = TRUE)
    base_cols  <- setdiff(keep_cols, inst_cols)
    if (!length(inst_cols)) inst_cols <- character(0)
    if (!length(base_cols)) base_cols <- NULL
  } else {
    base_cols <- NULL
    inst_cols <- NULL  # NULL = all instruments
  }

  dt_sub <- load_firm_panel(
    baseline_type = baseline_value,
    columns       = base_cols,
    instruments   = inst_cols,
    zero_fill     = TRUE,
    as_data_table = TRUE,
    test_mode     = test_mode
  )
  cat(sprintf("  Source: split fst (%s rows)\n", format(nrow(dt_sub), big.mark = ",")))
  dt_sub
}

get_combos_for_family <- function(family) {
  if (identical(family, "main") || identical(family, "interaction_mqemp")) MAIN_COMBOS
  else INTERACTION_COMBOS
}

get_combo_instruments <- function(combo, align_type, spec_type, exposure = "pooled_count") {
  base_prefix <- if (identical(spec_type, "levels")) "FA_" else "dFA_"
  prefix <- if (identical(exposure, "binary")) paste0(base_prefix, "binary_") else base_prefix

  switch(combo,
    "M"          = paste0(prefix, "mayor_", align_type),
    "G"          = paste0(prefix, "gov_", align_type),
    "P"          = paste0(prefix, "pres_", align_type),
    "M+G"        = paste0(prefix, c("mayor", "gov"), "_", align_type),
    "M+P"        = paste0(prefix, c("mayor", "pres"), "_", align_type),
    "M+G+P"      = paste0(prefix, c("mayor", "gov", "pres"), "_", align_type),
    "M+G+MxG"    = paste0(prefix, c("mayor", "gov", "mayor_gov"), "_", align_type),
    "M+G+P+MxG"  = paste0(prefix, c("mayor", "gov", "pres", "mayor_gov"), "_", align_type),
    "M+G+P+MxP"  = paste0(prefix, c("mayor", "gov", "pres", "mayor_pres"), "_", align_type),
    stop("Unknown instrument combo: ", combo)
  )
}

build_combo_map <- function(align_type, spec_type, exposure, combos) {
  setNames(lapply(combos, function(combo) {
    get_combo_instruments(combo, align_type, spec_type, exposure = exposure)
  }), combos)
}

# Build formulas where each instrument is interacted with top_q4_muni.
# The top_q4_muni main effect is time-invariant within muni and is absorbed by the
# muni_id^year FE (which demeans within each muni-year cell, eliminating any
# muni-level constant). Only the interaction term FA_*:top_q4_muni is identified.
build_interaction_mqemp_formula_cache <- function(combo_map, depvar, combos) {
  formula_cache <- vector("list", length(combos))
  names(formula_cache) <- combos

  for (combo in combos) {
    insts <- combo_map[[combo]]
    main_terms        <- paste(insts, collapse = " + ")
    interaction_terms <- paste(paste0(insts, ":top_q4_muni"), collapse = " + ")
    rhs <- paste(main_terms, interaction_terms, sep = " + ")
    formula_cache[[combo]] <- as.formula(paste0(depvar, " ~ ", rhs, " | ", FE_FIRM))
  }

  formula_cache
}

build_formula_cache <- function(combo_map, depvar, combos, family = "main") {
  if (identical(family, "interaction_mqemp")) {
    return(build_interaction_mqemp_formula_cache(combo_map, depvar, combos))
  }

  formula_cache <- vector("list", length(combos))
  names(formula_cache) <- combos

  for (combo in combos) {
    rhs <- paste(combo_map[[combo]], collapse = " + ")
    formula_cache[[combo]] <- as.formula(paste0(depvar, " ~ ", rhs, " | ", FE_FIRM))
  }

  formula_cache
}

build_sw_formula <- function(depvar, base_terms = character(0), sw_terms) {
  rhs_parts <- character(0)
  if (length(base_terms)) {
    rhs_parts <- c(rhs_parts, paste(base_terms, collapse = " + "))
  }
  rhs_parts <- c(rhs_parts, paste0("sw(", paste(sw_terms, collapse = ", "), ")"))
  as.formula(paste0(depvar, " ~ ", paste(rhs_parts, collapse = " + "), " | ", FE_FIRM))
}

outcome_mask_key <- function(outcome, time_variation) {
  paste(outcome, time_variation, sep = "__")
}

build_sample_masks <- function(dt) {
  # Raw headcount weight (emp_weighted)
  weight_ok <- if ("bl_n_employees" %in% names(dt)) {
    is.finite(dt$bl_n_employees) & dt$bl_n_employees > 0
  } else {
    rep(FALSE, nrow(dt))
  }

  # Municipality employment-share weight (emp_share_weighted).
  # Both mayor and G/P share columns must be finite and positive.
  emp_share_weight_ok <- if (all(c("emp_share_muni_pre_mayor", "emp_share_muni_pre_gp") %in% names(dt))) {
    is.finite(dt$emp_share_muni_pre_mayor) & dt$emp_share_muni_pre_mayor > 0 &
    is.finite(dt$emp_share_muni_pre_gp)   & dt$emp_share_muni_pre_gp   > 0
  } else {
    rep(FALSE, nrow(dt))
  }

  # Muni quartile sample flags
  top_q4_ok <- if ("top_q4_muni" %in% names(dt)) {
    !is.na(dt$top_q4_muni) & dt$top_q4_muni == 1L
  } else {
    NULL
  }
  bottom_3q_ok <- if ("top_q4_muni" %in% names(dt)) {
    !is.na(dt$top_q4_muni) & dt$top_q4_muni == 0L
  } else {
    NULL
  }

  single_muni <- if ("is_multi_muni" %in% names(dt)) {
    !is.na(dt$is_multi_muni) & dt$is_multi_muni == 0L
  } else {
    NULL
  }

  availability <- list()
  for (outcome_name in names(DEPVAR_INFO)) {
    for (tv_name in names(DEPVAR_INFO[[outcome_name]])) {
      depvar_name <- DEPVAR_INFO[[outcome_name]][[tv_name]]$depvar
      availability[[outcome_mask_key(outcome_name, tv_name)]] <- if (depvar_name %in% names(dt)) {
        !is.na(dt[[depvar_name]])
      } else {
        rep(FALSE, nrow(dt))
      }
    }
  }

  # Helper: build mask list for a given base selector (logical vector or NULL)
  make_group <- function(base) {
    lapply(availability, function(m) if (is.null(base)) m else base & m)
  }

  masks <- list(
    "unweighted"          = make_group(NULL),
    "weighted"            = make_group(weight_ok),
    "emp_share_weighted"  = make_group(emp_share_weight_ok)
  )

  if (!is.null(single_muni)) {
    masks[["unweighted_single_muni"]]         <- make_group(single_muni)
    masks[["weighted_single_muni"]]           <- make_group(weight_ok & single_muni)
    masks[["emp_share_weighted_single_muni"]] <- make_group(emp_share_weight_ok & single_muni)
  }

  if (!is.null(top_q4_ok)) {
    masks[["unweighted_top_q4"]]         <- make_group(top_q4_ok)
    masks[["weighted_top_q4"]]           <- make_group(weight_ok & top_q4_ok)
    masks[["emp_share_weighted_top_q4"]] <- make_group(emp_share_weight_ok & top_q4_ok)
  }

  if (!is.null(bottom_3q_ok)) {
    masks[["unweighted_bottom_3q"]]         <- make_group(bottom_3q_ok)
    masks[["weighted_bottom_3q"]]           <- make_group(weight_ok & bottom_3q_ok)
    masks[["emp_share_weighted_bottom_3q"]] <- make_group(emp_share_weight_ok & bottom_3q_ok)
  }

  masks
}

# Map (weighting, sample) to the masks list key built by build_sample_masks().
get_mask_key <- function(weighting, sample) {
  weight_tag <- switch(weighting,
    "emp_weighted"       = "weighted",
    "emp_share_weighted" = "emp_share_weighted",
    "unweighted"
  )
  if (identical(sample, "all_firms")) weight_tag
  else paste(weight_tag, sample, sep = "_")
}

build_sample_mask <- function(masks, cfg) {
  key       <- outcome_mask_key(cfg$outcome, cfg$time_variation)
  mask_key  <- get_mask_key(cfg$weighting, cfg$sample)
  mask_group <- masks[[mask_key]]
  if (is.null(mask_group)) return(NULL)
  mask_group[[key]]
}

get_depvar_info <- function(outcome, time_variation) {
  dep_info <- DEPVAR_INFO[[outcome]][[time_variation]]
  if (is.null(dep_info)) {
    stop("Unsupported outcome/time_variation combination: ", outcome, " / ", time_variation)
  }
  dep_info
}

build_table_notes <- function(cfg, dep_info) {
  note_parts <- c(
    "Firm + muni $\\times$ year FE.",
    if (identical(cfg$alignment, "coalition")) "Coalition alignment." else "Party alignment.",
    if (identical(cfg$baseline, "cycle_specific")) "Cycle-specific baseline." else "2002-fixed baseline.",
    if (identical(cfg$exposure, "binary")) "Binary exposure (any-year)." else "Pooled-count exposure.",
    if (identical(cfg$family, "interaction"))       "Interaction instruments.",
    if (identical(cfg$family, "interaction_mqemp")) "Instruments interacted with top-quartile municipality employment dummy.",
    if (identical(cfg$sample, "single_muni")) "Single-municipality firms only.",
    if (identical(cfg$sample, "top_q4"))      "Sample: top-quartile municipalities by mean RAIS employment (2002--2017).",
    if (identical(cfg$sample, "bottom_3q"))   "Sample: bottom three quartiles by mean RAIS employment (2002--2017).",
    dep_info$sample_note,
    "SEs clustered by firm + muni in parentheses.",
    if (identical(cfg$weighting, "emp_weighted"))      "Weighted by pre-election baseline employment.",
    if (identical(cfg$weighting, "emp_share_weighted")) "Weighted by firm's pre-election municipality employment share.",
    "$^{***}p<0.01$, $^{**}p<0.05$, $^{*}p<0.10$."
  )

  paste(note_parts[!is.na(note_parts) & nzchar(note_parts)], collapse = " ")
}

compute_wald_stat <- function(mod, pattern = WALD_KEEP_PATTERN) {
  wald_obj <- NULL
  tryCatch({
    utils::capture.output(
      wald_obj <- fixest::wald(mod, keep = pattern),
      file = NULL
    )
    wald_obj$stat
  }, error = function(e) NA_real_)
}

cache_model_wald <- function(mod, pattern = WALD_KEEP_PATTERN) {
  if (!inherits(mod, "fixest")) {
    return(mod)
  }

  inst_names <- grep(pattern, names(coef(mod)), value = TRUE)
  stat <- NA_real_
  if (!length(inst_names)) {
    attr(mod, "politicsregs_wald_stat") <- stat
    attr(mod, "politicsregs_wald_pattern") <- pattern
    return(mod)
  }

  stat <- compute_wald_stat(mod, pattern = pattern)
  attr(mod, "politicsregs_wald_stat") <- stat
  attr(mod, "politicsregs_wald_pattern") <- pattern
  mod
}

safe_wald <- function(mod, pattern = WALD_KEEP_PATTERN) {
  cached_stat <- attr(mod, "politicsregs_wald_stat", exact = TRUE)
  cached_pattern <- attr(mod, "politicsregs_wald_pattern", exact = TRUE)
  if (!is.null(cached_stat) && identical(cached_pattern, pattern)) {
    return(cached_stat)
  }

  inst_names <- grep(pattern, names(coef(mod)), value = TRUE)
  if (!length(inst_names)) {
    return(NA_real_)
  }
  compute_wald_stat(mod, pattern = pattern)
}

extract_firm_summary <- function(mods, spec_label, extra_info = list()) {
  if (!length(mods)) {
    return(NULL)
  }

  rbindlist(lapply(names(mods), function(nm) {
    mod <- mods[[nm]]
    ct <- coeftable(mod)
    inst_rows <- grepl("^(FA_|dFA_)", rownames(ct))
    if (!any(inst_rows)) {
      return(NULL)
    }

    base_dt <- data.table(
      variable = rownames(ct)[inst_rows],
      coef = ct[inst_rows, "Estimate"],
      se = ct[inst_rows, "Std. Error"],
      t_stat = ct[inst_rows, "t value"],
      p_value = ct[inst_rows, "Pr(>|t|)"],
      combo = nm,
      spec = spec_label,
      r2 = tryCatch(fixest::r2(mod, "r2"), error = function(e) NA_real_),
      wald_f = safe_wald(mod),
      n_obs = nobs(mod),
      n_collin = length(mod$collin.var)
    )

    for (k in names(extra_info)) {
      base_dt[[k]] <- extra_info[[k]]
    }

    base_dt
  }), fill = TRUE)
}

record_collinearity <- function(mod, combo) {
  if (length(mod$collin.var) > 0) {
    cat(sprintf("  Collinearity in '%s': dropped %s\n",
                combo, paste(mod$collin.var, collapse = ", ")))
  }
}

# Map an instrument combo to the appropriate pre-election muni employment-share
# column for emp_share_weighted regressions.
# Pure G/P combos use the gov/pres-cycle share; all other combos (including
# mixed-tier) use the mayor-cycle share.
# NOTE: for mixed-tier combos (M+G, M+P, M+G+P) the mayor share is used as a
# single-denominator approximation — a deferred design decision.
get_emp_share_weight_col <- function(combo) {
  if (combo %in% c("G", "P")) "emp_share_muni_pre_gp" else "emp_share_muni_pre_mayor"
}

# weight_col, when non-NULL, directly specifies the weight column as a formula
# string and takes precedence over the weighting= string argument.
fit_firm_model <- function(formula_obj, data, subset_idx, weighting = "unweighted",
                           weight_col = NULL, multi = FALSE) {
  fit_args <- list(
    fml = formula_obj,
    data = data,
    subset = subset_idx,
    vcov = VCOV_FIRM,
    lean = TRUE,
    mem.clean = !isTRUE(multi)
  )
  if (!is.null(weight_col)) {
    fit_args$weights <- as.formula(paste0("~", weight_col))
  } else if (identical(weighting, "emp_weighted")) {
    fit_args$weights <- ~bl_n_employees
  }
  do.call(feols, fit_args)
}

run_batched_combos <- function(formula_cache, combo_map, data, subset_idx, weighting, family) {
  mods <- list()
  failed <- character(0)

  # emp_share_weighted requires a per-combo weight column (mayor vs G/P tier).
  use_per_combo_weight <- identical(weighting, "emp_share_weighted")

  run_single <- function(combo) {
    weight_col        <- if (use_per_combo_weight) get_emp_share_weight_col(combo) else NULL
    effective_weighting <- if (use_per_combo_weight) "unweighted" else weighting
    mod <- tryCatch(
      fit_firm_model(formula_cache[[combo]], data, subset_idx,
                     weighting = effective_weighting,
                     weight_col = weight_col,
                     multi = FALSE),
      error = function(e) {
        cat(sprintf("  WARNING: combo '%s' failed: %s\n", combo, conditionMessage(e)))
        NULL
      }
    )

    if (!is.null(mod)) {
      mod <- cache_model_wald(mod)
      record_collinearity(mod, combo)
      mods[[combo]] <<- mod
    } else {
      failed <<- unique(c(failed, combo))
    }
  }

  run_batch <- function(batch_combos, batch_formula = NULL) {
    batch_combos <- batch_combos[batch_combos %in% names(formula_cache)]
    if (!length(batch_combos)) {
      return(invisible(NULL))
    }
    if (length(batch_combos) == 1L || is.null(batch_formula)) {
      for (combo in batch_combos) {
        run_single(combo)
      }
      return(invisible(NULL))
    }

    batch_fit <- tryCatch(
      fit_firm_model(batch_formula, data, subset_idx, weighting = weighting, multi = TRUE),
      error = function(e) {
        cat(sprintf(
          "  WARNING: batched estimation failed for [%s]: %s\n",
          paste(batch_combos, collapse = ", "),
          conditionMessage(e)
        ))
        NULL
      }
    )

    if (is.null(batch_fit)) {
      for (combo in batch_combos) {
        run_single(combo)
      }
      return(invisible(NULL))
    }

    batch_models <- if (inherits(batch_fit, "fixest_multi")) as.list(batch_fit) else list(batch_fit)
    if (length(batch_models) != length(batch_combos)) {
      cat(sprintf(
        "  WARNING: batched estimation returned %d models for %d combos; falling back.\n",
        length(batch_models), length(batch_combos)
      ))
      for (combo in batch_combos) {
        run_single(combo)
      }
      return(invisible(NULL))
    }

    names(batch_models) <- batch_combos
    for (combo in batch_combos) {
      mod <- cache_model_wald(batch_models[[combo]])
      record_collinearity(mod, combo)
      mods[[combo]] <<- mod
    }
  }

  # emp_share_weighted: different weight column per combo — skip batch optimisation.
  # interaction_mqemp:  formulas include per-instrument interaction terms — skip batch.
  if (use_per_combo_weight || identical(family, "interaction_mqemp")) {
    for (combo in names(formula_cache)) {
      run_single(combo)
    }
    return(list(mods = mods, failed_combos = failed))
  }

  if (identical(family, "main")) {
    run_batch(
      c("M", "G", "P"),
      build_sw_formula(
        depvar = all.vars(formula_cache[[1L]])[1L],
        sw_terms = c(
          combo_map[["M"]][1L],
          combo_map[["G"]][1L],
          combo_map[["P"]][1L]
        )
      )
    )

    run_batch(
      c("M+G", "M+P", "M+G+P"),
      build_sw_formula(
        depvar = all.vars(formula_cache[[1L]])[1L],
        base_terms = combo_map[["M+G"]][1L],
        sw_terms = c(
          combo_map[["M+G"]][2L],
          combo_map[["M+P"]][2L],
          paste(combo_map[["M+G+P"]][2:3], collapse = " + ")
        )
      )
    )
  } else {
    run_batch("M+G+MxG", NULL)
    run_batch(
      c("M+G+P+MxG", "M+G+P+MxP"),
      build_sw_formula(
        depvar = all.vars(formula_cache[[1L]])[1L],
        base_terms = combo_map[["M+G+P+MxG"]][1:3],
        sw_terms = c(
          combo_map[["M+G+P+MxG"]][4L],
          combo_map[["M+G+P+MxP"]][4L]
        )
      )
    )
  }

  list(mods = mods, failed_combos = failed)
}

append_manifest_row <- function(
    cfg,
    depvar,
    slug,
    mods,
    failed_combos,
    elapsed_sec,
    elapsed_fit_sec = NA_real_,
    elapsed_table_sec = NA_real_,
    elapsed_summary_sec = NA_real_,
    status,
    skip_reason = NA_character_,
    tex_path = NA_character_,
    md_path = NA_character_) {

  n_obs <- if (length(mods)) {
    as.integer(min(vapply(mods, nobs, numeric(1))))
  } else {
    NA_integer_
  }

  fstats <- if (length(mods)) vapply(mods, safe_wald, numeric(1)) else numeric(0)
  fstats <- fstats[is.finite(fstats)]

  data.table(
    canonical_slug = slug,
    family = cfg$family,
    outcome = cfg$outcome,
    exposure = cfg$exposure,
    weighting = cfg$weighting,
    baseline = cfg$baseline,
    alignment = cfg$alignment,
    time_variation = cfg$time_variation,
    sample = cfg$sample,
    depvar = depvar,
    n_obs = n_obs,
    n_combos_run = length(mods),
    n_combos_failed = length(failed_combos),
    wald_f_min = if (length(fstats)) min(fstats) else NA_real_,
    wald_f_max = if (length(fstats)) max(fstats) else NA_real_,
    elapsed_fit_sec = as.numeric(elapsed_fit_sec),
    elapsed_table_sec = as.numeric(elapsed_table_sec),
    elapsed_summary_sec = as.numeric(elapsed_summary_sec),
    elapsed_sec = as.numeric(elapsed_sec),
    status = status,
    skip_reason = skip_reason,
    tex_path = tex_path,
    md_path = md_path
  )
}

write_qs_atomic <- function(obj, path) {
  tmp <- tempfile(pattern = "firm-run-", tmpdir = dirname(path), fileext = ".qs2")
  qs_save(obj, tmp)
  if (file.exists(path)) {
    file.remove(path)
  }
  if (!file.rename(tmp, path)) {
    stop("Failed to write file: ", path)
  }
}

write_csv_atomic <- function(dt, path) {
  tmp <- tempfile(pattern = "firm-run-", tmpdir = dirname(path), fileext = ".csv")
  fwrite(dt, tmp)
  if (file.exists(path)) {
    file.remove(path)
  }
  if (!file.rename(tmp, path)) {
    stop("Failed to write file: ", path)
  }
}

read_existing_artifact <- function(path, reader) {
  if (!file.exists(path)) {
    return(NULL)
  }

  tryCatch(
    reader(path),
    error = function(e) {
      cat(sprintf("WARNING: failed to read existing artifact '%s': %s\n", path, conditionMessage(e)))
      NULL
    }
  )
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
    if (length(order_cols)) {
      setorderv(out, order_cols)
    }
  }

  out
}

validate_requested_configs <- function(config_dt, test_mode = FALSE) {
  cfg <- copy(config_dt)
  cfg[, pre_skip_reason := NA_character_]
  panel_info <- list()

  for (baseline_value in unique(cfg$baseline)) {
    paths <- get_panel_paths(baseline_value, test_mode = test_mode)
    if (!file.exists(paths$fst)) {
      if (isTRUE(test_mode)) {
        stop("Sample panel not found. Run: Rscript BNDES/politicsregs/diagnostics/create_firm_sample.R")
      }
      stop("Panel file not found: ", paths$fst, ". Run scripts 22, 36, 42 first.")
    }

    cols <- get_panel_column_names(paths)
    if (is.null(cols)) {
      stop("Could not inspect panel columns for baseline: ", baseline_value)
    }

    panel_info[[baseline_value]] <- list(
      paths = paths,
      columns = cols
    )
  }

  for (i in seq_len(nrow(cfg))) {
    row <- cfg[i]
    panel_cols <- panel_info[[row$baseline]]$columns
    dep_info <- get_depvar_info(row$outcome, row$time_variation)

    if (identical(row$sample, "single_muni") && !"is_multi_muni" %in% panel_cols) {
      stop("Column `is_multi_muni` not found for single_muni sample in config: ", row$canonical_slug)
    }

    if (identical(row$weighting, "emp_share_weighted")) {
      missing_share_cols <- setdiff(
        c("emp_share_muni_pre_mayor", "emp_share_muni_pre_gp"),
        panel_cols
      )
      if (length(missing_share_cols)) {
        stop(
          "emp_share_weighted requires columns missing in panel for config '", row$canonical_slug,
          "': ", paste(missing_share_cols, collapse = ", "),
          ". Run scripts 32b and 42 first."
        )
      }
    }

    if (row$sample %in% c("top_q4", "bottom_3q") || identical(row$family, "interaction_mqemp")) {
      if (!"top_q4_muni" %in% panel_cols) {
        stop(
          "Column `top_q4_muni` not found for config '", row$canonical_slug,
          "'. Run scripts 41 and 42 first."
        )
      }
    }

    if (!dep_info$depvar %in% panel_cols) {
      stop(
        "Required outcome column missing for config '", row$canonical_slug,
        "': ", dep_info$depvar
      )
    }

    combos <- get_combos_for_family(row$family)
    combo_map <- build_combo_map(row$alignment, row$time_variation, row$exposure, combos)
    required_cols <- unique(unlist(combo_map, use.names = FALSE))
    missing_cols <- required_cols[!required_cols %in% panel_cols]

    if (length(missing_cols)) {
      if (row$family %in% c("interaction", "interaction_mqemp") && identical(row$exposure, "binary")) {
        cfg[i, pre_skip_reason := "binary interaction instruments not available"]
      } else {
        stop(
          "Required instrument columns missing for config '", row$canonical_slug,
          "': ", paste(missing_cols, collapse = ", ")
        )
      }
    }
  }

  list(config_dt = cfg, panel_info = panel_info)
}

print_config_table <- function(config_dt) {
  display_dt <- copy(config_dt)
  display_dt[, action := fifelse(is.na(pre_skip_reason), "run", "skip")]
  display_dt[, skip_reason := fifelse(is.na(pre_skip_reason), "", pre_skip_reason)]
  print(display_dt[, .(
    canonical_slug,
    family,
    time_variation,
    outcome,
    alignment,
    baseline,
    weighting,
    sample,
    exposure,
    action,
    skip_reason
  )])
}

script_t0 <- proc.time()
args <- commandArgs(trailingOnly = TRUE)
parsed_args <- parse_cli_args(args)
table_dir <- if (parsed_args$test) {
  file.path(TABLES_DIR, "firm", "test")
} else {
  file.path(TABLES_DIR, "firm")
}
TABLE_DIR <- table_dir
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

config_dt <- resolve_requested_configs(parsed_args)
validation <- validate_requested_configs(config_dt, test_mode = parsed_args$test)
config_dt <- validation$config_dt
panel_info <- validation$panel_info

cat("Specs:", paste(parsed_args$spec_names, collapse = ", "), "\n")
cat("fixest threads:", fixest::getFixest_nthreads(), "\n")
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

manifest_rows <- list()
summary_rows <- list()
total_models <- 0L

baseline_order <- unique(config_dt$baseline)
for (baseline_value in baseline_order) {
  bl_configs <- config_dt[baseline == baseline_value]
  if (!nrow(bl_configs)) {
    next
  }

  cat(sprintf("\n=== Baseline group: %s ===\n", baseline_value))

  skipped_configs <- bl_configs[!is.na(pre_skip_reason)]
  if (nrow(skipped_configs)) {
    for (i in seq_len(nrow(skipped_configs))) {
      cfg <- skipped_configs[i]
      dep_info <- get_depvar_info(cfg$outcome, cfg$time_variation)
      cat(sprintf("WARNING: skipping [%s]: %s\n", cfg$canonical_slug, cfg$pre_skip_reason))
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg = cfg,
        depvar = dep_info$depvar,
        slug = cfg$canonical_slug,
        mods = list(),
        failed_combos = character(0),
        elapsed_sec = 0,
        status = "skipped",
        skip_reason = cfg$pre_skip_reason
      )
    }
  }

  runnable_configs <- bl_configs[is.na(pre_skip_reason)]
  if (!nrow(runnable_configs)) {
    next
  }

  panel_cols <- panel_info[[baseline_value]]$columns
  dep_cols <- unique(vapply(seq_len(nrow(runnable_configs)), function(i) {
    cfg <- runnable_configs[i]
    get_depvar_info(cfg$outcome, cfg$time_variation)$depvar
  }, character(1)))
  keep_cols <- c(
    "firm_id", "muni_id", "year", "n_employees",
    if ("bl_n_employees" %in% panel_cols) "bl_n_employees",
    if ("emp_share_muni_pre_mayor" %in% panel_cols) "emp_share_muni_pre_mayor",
    if ("emp_share_muni_pre_gp"    %in% panel_cols) "emp_share_muni_pre_gp",
    if ("top_q4_muni"              %in% panel_cols) "top_q4_muni",
    dep_cols,
    if ("is_multi_muni" %in% panel_cols) "is_multi_muni"
  )

  required_cols <- unique(unlist(lapply(seq_len(nrow(runnable_configs)), function(i) {
    cfg <- runnable_configs[i]
    combos <- get_combos_for_family(cfg$family)
    unlist(build_combo_map(cfg$alignment, cfg$time_variation, cfg$exposure, combos), use.names = FALSE)
  }), use.names = FALSE))

  keep_cols <- unique(c(keep_cols, required_cols))
  dt <- load_panel_subset(baseline_value, test_mode = parsed_args$test, keep_cols = keep_cols)

  dt[, firm_id := as.factor(firm_id)]
  dt[, muni_id := as.factor(muni_id)]
  dt[, year := as.factor(year)]

  masks <- build_sample_masks(dt)

  for (i in seq_len(nrow(runnable_configs))) {
    cfg <- runnable_configs[i]
    dep_info <- get_depvar_info(cfg$outcome, cfg$time_variation)
    slug <- cfg$canonical_slug
    combos <- get_combos_for_family(cfg$family)
    combo_map <- build_combo_map(cfg$alignment, cfg$time_variation, cfg$exposure, combos)
    formula_cache <- build_formula_cache(combo_map, dep_info$depvar, combos, family = cfg$family)
    subset_idx <- build_sample_mask(masks, cfg)

    if (is.null(subset_idx) || !any(subset_idx)) {
      cat(sprintf("[%s]\n", slug))
      cat("  WARNING: empty estimation sample; skipping save.\n")
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg = cfg,
        depvar = dep_info$depvar,
        slug = slug,
        mods = list(),
        failed_combos = combos,
        elapsed_sec = 0,
        status = "failed",
        skip_reason = "empty estimation sample"
      )
      next
    }

    cat(sprintf("\n[%s]\n", slug))
    cat(sprintf("  Sample rows: %s\n", format(sum(subset_idx), big.mark = ",")))

    config_t0 <- proc.time()
    fit_t0 <- proc.time()
    run_result <- run_batched_combos(
      formula_cache = formula_cache,
      combo_map = combo_map,
      data = dt,
      subset_idx = subset_idx,
      weighting = cfg$weighting,
      family = cfg$family
    )
    elapsed_fit <- as.numeric((proc.time() - fit_t0)[["elapsed"]])
    mods <- run_result$mods
    failed_combos <- run_result$failed_combos

    if (!length(mods)) {
      elapsed_total <- as.numeric((proc.time() - config_t0)[["elapsed"]])
      cat("  WARNING: all combos failed; no table saved.\n")
      manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
        cfg = cfg,
        depvar = dep_info$depvar,
        slug = slug,
        mods = mods,
        failed_combos = if (length(failed_combos)) failed_combos else combos,
        elapsed_sec = elapsed_total,
        elapsed_fit_sec = elapsed_fit,
        elapsed_table_sec = 0,
        elapsed_summary_sec = 0,
        status = "failed",
        skip_reason = "all combos failed"
      )
      rm(mods)
      gc(verbose = FALSE)
      next
    }

    tex_path <- md_path <- NA_character_
    save_ok <- TRUE
    save_error <- NA_character_
    elapsed_table <- 0
    elapsed_summary <- 0

    table_t0 <- proc.time()
    tryCatch({
      save_beamer_table(
        mods = mods,
        filename = slug,
        dep_var = dep_info$dep_label,
        notes = build_table_notes(cfg, dep_info),
        font_size = if (identical(cfg$family, "interaction")) 7 else 8
      )
      elapsed_table <- as.numeric((proc.time() - table_t0)[["elapsed"]])
      tex_path <- file.path(table_dir, paste0(slug, ".tex"))
    }, error = function(e) {
      elapsed_table <<- as.numeric((proc.time() - table_t0)[["elapsed"]])
      save_ok <<- FALSE
      save_error <<- conditionMessage(e)
    })

    status <- if (save_ok) "completed" else "failed"
    skip_reason <- if (save_ok) NA_character_ else paste0("table save failed: ", save_error)

    if (save_ok) {
      summary_t0 <- proc.time()
      summary_dt <- extract_firm_summary(mods, slug, list(
        canonical_slug = slug,
        family = cfg$family,
        outcome = cfg$outcome,
        exposure = cfg$exposure,
        weighting = cfg$weighting,
        baseline = cfg$baseline,
        alignment = cfg$alignment,
        time_variation = cfg$time_variation,
        sample = cfg$sample,
        depvar = dep_info$depvar
      ))
      elapsed_summary <- as.numeric((proc.time() - summary_t0)[["elapsed"]])
      if (!is.null(summary_dt) && nrow(summary_dt)) {
        summary_rows[[length(summary_rows) + 1L]] <- summary_dt
      }
      total_models <- total_models + length(mods)
    } else {
      cat(sprintf("  WARNING: failed to save table [%s]: %s\n", slug, save_error))
    }

    elapsed_total <- as.numeric((proc.time() - config_t0)[["elapsed"]])
    manifest_rows[[length(manifest_rows) + 1L]] <- append_manifest_row(
      cfg = cfg,
      depvar = dep_info$depvar,
      slug = slug,
      mods = mods,
      failed_combos = failed_combos,
      elapsed_sec = elapsed_total,
      elapsed_fit_sec = elapsed_fit,
      elapsed_table_sec = elapsed_table,
      elapsed_summary_sec = elapsed_summary,
      status = status,
      skip_reason = skip_reason,
      tex_path = if (save_ok) tex_path else NA_character_,
      md_path = NA_character_
    )

    cat(sprintf(
      "  Timing (sec): fit=%.1f, table=%.1f, summary=%.1f, total=%.1f\n",
      elapsed_fit,
      elapsed_table,
      elapsed_summary,
      elapsed_total
    ))
    cat(sprintf(
      "  %d models fit in %.1f sec (%.1f sec/model)\n",
      length(mods),
      elapsed_fit,
      elapsed_fit / length(mods)
    ))

    rm(mods)
    gc(verbose = FALSE)
  }

  rm(dt, masks)
  gc(verbose = FALSE)
}

manifest_dt <- if (length(manifest_rows)) {
  rbindlist(manifest_rows, fill = TRUE)
} else {
  data.table(
    canonical_slug = character(),
    family = character(),
    outcome = character(),
    exposure = character(),
    weighting = character(),
    baseline = character(),
    alignment = character(),
    time_variation = character(),
    sample = character(),
    depvar = character(),
    n_obs = integer(),
    n_combos_run = integer(),
    n_combos_failed = integer(),
    wald_f_min = numeric(),
    wald_f_max = numeric(),
    elapsed_fit_sec = numeric(),
    elapsed_table_sec = numeric(),
    elapsed_summary_sec = numeric(),
    elapsed_sec = numeric(),
    status = character(),
    skip_reason = character(),
    tex_path = character(),
    md_path = character()
  )
}

summary_dt <- if (length(summary_rows)) rbindlist(summary_rows, fill = TRUE) else data.table()

final_write_t0 <- proc.time()
summary_path <- file.path(table_dir, "fc_battery_summary.qs2")
manifest_csv_path <- file.path(table_dir, "firm_run_manifest.csv")
manifest_qs2_path <- file.path(table_dir, "firm_run_manifest.qs2")
replace_slugs <- unique(config_dt$canonical_slug)

existing_summary_dt <- read_existing_artifact(summary_path, qs_read)
summary_dt <- merge_existing_runs(
  existing_dt = existing_summary_dt,
  new_dt = summary_dt,
  replace_slugs = replace_slugs,
  order_cols = c("baseline", "canonical_slug", "combo", "variable")
)
write_qs_atomic(summary_dt, summary_path)

existing_manifest_dt <- read_existing_artifact(
  manifest_qs2_path,
  qs_read
)
if (is.null(existing_manifest_dt)) {
  existing_manifest_dt <- read_existing_artifact(
    manifest_csv_path,
    fread
  )
}
manifest_dt <- merge_existing_runs(
  existing_dt = existing_manifest_dt,
  new_dt = manifest_dt,
  replace_slugs = replace_slugs,
  order_cols = c("baseline", "canonical_slug")
)
write_csv_atomic(manifest_dt, manifest_csv_path)
write_qs_atomic(manifest_dt, manifest_qs2_path)
elapsed_final_writes <- as.numeric((proc.time() - final_write_t0)[["elapsed"]])

elapsed_total <- as.numeric((proc.time() - script_t0)[["elapsed"]])

cat("\n==============================================================================\n")
cat("Firm-level first-stage regressions complete.\n")
cat("Tables saved to:", table_dir, "\n")
cat("Summary saved to:", summary_path, "\n")
cat("Manifest saved to:", manifest_csv_path, "and", manifest_qs2_path, "\n")
cat(sprintf("Final artifact writes: %.1f sec\n", elapsed_final_writes))
cat(sprintf("Total: %.1f min (%d configs, %d models)\n",
            elapsed_total / 60,
            nrow(config_dt),
            total_models))
cat("==============================================================================\n")
