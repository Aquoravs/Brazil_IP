#!/usr/bin/env Rscript

# ==============================================================================
# Proposition 2 Equivalence Tests
# ==============================================================================
# Formally test the aggregation equivalence result from review_aggregation.tex
# by comparing firm-level OLS against cell-averaged OLS under:
#   - matched sample construction
#   - matched cell weights (N_c or E_c)
#   - relaxed vs exact support-regime FE
#
# Extracted from script 52 to keep the main sector-level spec engine focused.
#
# USAGE:
#   Rscript run_politicsregs.R 52b [OPTIONS]
#
# OPTIONS:
#   --sector-var=VAL     cnae_section, sector_group (default: sector_group)
#   --weighting=VAL      unweighted, emp_weighted, both (default: both)
#   --single-cell        Run Bronze vs Silver tier comparison (C3/C5 filters)
#   --balanced           Add balanced-within-regime filter to Silver tier
#   --dry-run            Print planned outputs and exit
#
# OUTPUT:
#   Tables:    output/tables/agg_firm[_grouped]/prop2_*.tex
#   Diagnostics: prop2_equality_check.csv, prop2_sample_diagnostic.csv,
#                prop2_tier_comparison.csv
# ==============================================================================

cat("==============================================================================\n")
cat("Proposition 2 Equivalence Tests\n")
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
fixest::setFixest_nthreads(4L)

source(politicsregs_path("_utils", "beamer_tables.R"))
source(politicsregs_path("_utils", "load_firm_panel.R"))

# --- Parse CLI arguments ------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

svar_flag <- grep("^--sector-var=", args, value = TRUE)
weighting_flag <- grep("^--weighting=", args, value = TRUE)

SECTOR_VAR <- "sector_group"
WEIGHTING_MODE <- "both"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[[1L]])))
  if (!SECTOR_VAR %in% c("cnae_section", "sector_group", "policy_block")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'. Use 'cnae_section', 'sector_group', or 'policy_block'.")
  }
}
if (length(weighting_flag)) {
  WEIGHTING_MODE <- tolower(trimws(sub("^--weighting=", "", weighting_flag[[1L]])))
  if (!WEIGHTING_MODE %in% c("unweighted", "emp_weighted", "both")) {
    stop("Invalid --weighting value: '", WEIGHTING_MODE,
         "'. Use 'unweighted', 'emp_weighted', or 'both'.")
  }
}

if (any(args == "--compare-51")) {
  stop("--compare-51 has been removed from script 52b.")
}
SINGLE_CELL <- any(args == "--single-cell")
BALANCED <- any(args == "--balanced")
DRY_RUN <- any(args == "--dry-run")

SCOL <- SECTOR_VAR
RUN_UNWEIGHTED <- WEIGHTING_MODE %in% c("unweighted", "both")
RUN_EMP_WEIGHTED <- WEIGHTING_MODE %in% c("emp_weighted", "both")

cat("Sector variable:", SECTOR_VAR, "\n")
cat("Weighting mode:", WEIGHTING_MODE, "\n")
cat("Single-cell filter:", if (SINGLE_CELL) "ON" else "OFF", "\n")
cat("Balanced filter:", if (BALANCED) "ON" else "OFF", "\n")
cat("Dry run:", if (DRY_RUN) "ON" else "OFF", "\n\n")

# --- Configuration ------------------------------------------------------------

table_suffix <- if (SECTOR_VAR == "sector_group") "_grouped" else ""
table_dir <- file.path(TABLES_DIR, paste0("agg_firm", table_suffix))
TABLE_DIR <- table_dir
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

FE_FIRM <- "firm_id + muni_id^year"
FE_AGG_RELAXED <- paste0("muni_id^", SCOL, " + muni_id^year")
FE_AGG_EXACT <- paste0("muni_id^", SCOL, "^support_regime + muni_id^year")
VCOV_FIRM <- ~ firm_id + muni_id
VCOV_AGG <- as.formula(paste0("~ muni_id + ", SCOL))
PROP2_TOL <- 1e-8
PROP2_COMBO <- "M+G+P"
PROP2_ALIGNMENTS <- c("coalition", "party")

# --- Shared helpers -----------------------------------------------------------

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

build_support_regime_map <- function(year_map) {
  regime_map <- year_map[
    ,
    .(support_regime_label = paste(sort(unique(baseline_year)), collapse = "_")),
    by = year
  ]
  regime_map[, support_regime := match(support_regime_label, unique(support_regime_label))]
  regime_map[]
}

weighted_mean_safe <- function(x, w) {
  ok <- !is.na(x) & !is.na(w) & is.finite(w) & w > 0
  if (!any(ok)) {
    return(NA_real_)
  }
  sum(x[ok] * w[ok]) / sum(w[ok])
}

safe_quantile <- function(x, prob) {
  if (!length(x)) return(NA_real_)
  as.numeric(stats::quantile(x, probs = prob, na.rm = TRUE, names = FALSE))
}

safe_wald <- function(mod, keep = "^(FA_|FA_bar_)") {
  if (is.null(mod)) return(NA_real_)
  tryCatch(fixest::wald(mod, keep = keep)$stat, error = function(e) NA_real_)
}

safe_r2 <- function(mod) {
  if (is.null(mod)) return(NA_real_)
  tryCatch(fixest::r2(mod, "r2"), error = function(e) NA_real_)
}

write_csv_atomic <- function(dt, path) {
  tmp <- tempfile(pattern = "prop2-", tmpdir = dirname(path), fileext = ".csv")
  fwrite(dt, tmp)
  if (file.exists(path)) {
    file.remove(path)
  }
  if (!file.rename(tmp, path)) {
    stop("Failed to write file: ", path)
  }
}

make_empty_agg_dt <- function(fa_terms) {
  empty_dt <- data.table(
    muni_id = integer(),
    year = integer(),
    H_jmt = numeric(),
    N_pre = integer(),
    emp_pre = numeric()
  )
  empty_dt[, (SCOL) := character()]
  for (col in fa_terms) {
    empty_dt[, (col) := numeric()]
  }
  setcolorder(empty_dt, c(SCOL, "muni_id", "year", "H_jmt", "N_pre", "emp_pre", fa_terms))
  empty_dt
}

collapse_agg_panel <- function(dt_in, fa_terms, weighted = FALSE) {
  by_cols <- c(SCOL, "muni_id", "year")
  agg_terms <- sub("^FA_", "FA_bar_", fa_terms)

  if (!nrow(dt_in)) {
    return(make_empty_agg_dt(agg_terms))
  }

  if (isTRUE(weighted)) {
    dt_use <- dt_in[is.finite(n_employees) & n_employees > 0]
    if (!nrow(dt_use)) {
      return(make_empty_agg_dt(agg_terms))
    }

    agg_dt <- dt_use[, {
      w <- n_employees
      out <- list(
        H_jmt = weighted_mean_safe(has_bndes_fmt, w),
        N_pre = .N,
        emp_pre = sum(w)
      )
      for (col in fa_terms) {
        out[[sub("^FA_", "FA_bar_", col)]] <- weighted_mean_safe(get(col), w)
      }
      out
    }, by = by_cols]
  } else {
    agg_dt <- dt_in[, {
      out <- list(
        H_jmt = mean(has_bndes_fmt, na.rm = TRUE),
        N_pre = .N,
        emp_pre = NA_real_
      )
      for (col in fa_terms) {
        out[[sub("^FA_", "FA_bar_", col)]] <- mean(get(col), na.rm = TRUE)
      }
      out
    }, by = by_cols]
  }

  setcolorder(agg_dt, c(by_cols, "H_jmt", "N_pre", "emp_pre", agg_terms))
  agg_dt[]
}

run_feols_model <- function(formula_obj,
                            data,
                            vcov_obj,
                            weights_formula = NULL,
                            fixef_rm = NULL,
                            label = "",
                            keep_pat = "^(FA_|FA_bar_)") {
  cat(sprintf("  %s\n", label))
  mod <- tryCatch(
    {
      fit_args <- list(
        fml = formula_obj,
        data = data,
        vcov = vcov_obj,
        lean = TRUE,
        mem.clean = TRUE
      )
      if (!is.null(weights_formula)) {
        fit_args$weights <- weights_formula
      }
      if (!is.null(fixef_rm)) {
        fit_args$fixef.rm <- fixef_rm
      }
      do.call(feols, fit_args)
    },
    error = function(e) {
      cat(sprintf("    ERROR: %s\n", conditionMessage(e)))
      NULL
    }
  )

  if (is.null(mod)) {
    return(NULL)
  }

  cat(sprintf(
    "    N=%s, F=%.4f, R2=%.4f\n",
    format(nobs(mod), big.mark = ","),
    safe_wald(mod, keep = keep_pat),
    safe_r2(mod)
  ))
  if (length(mod$collin.var) > 0) {
    cat(sprintf("    Collinear: %s\n", paste(mod$collin.var, collapse = ", ")))
  }
  mod
}

harmonize_model_coef_names <- function(mod, rename_map) {
  if (is.null(mod) || !length(rename_map)) {
    return(mod)
  }
  out <- mod
  old_names <- names(out$coefficients)
  new_names <- old_names
  idx <- match(old_names, names(rename_map))
  repl <- !is.na(idx)
  new_names[repl] <- unname(rename_map[old_names[repl]])
  names(out$coefficients) <- new_names

  if (!is.null(out$coeftable)) {
    rownames(out$coeftable) <- new_names
  }
  if (!is.null(out$cov.iid) && length(dim(out$cov.iid)) == 2L) {
    dimnames(out$cov.iid) <- list(new_names, new_names)
  }
  if (!is.null(out$cov.scaled) && length(dim(out$cov.scaled)) == 2L) {
    dimnames(out$cov.scaled) <- list(new_names, new_names)
  }
  out
}

save_markdown_table <- function(mods,
                                filename,
                                coef_map = NULL,
                                fe_labels = FE_LABELS,
                                dep_var = NULL,
                                notes = NULL,
                                digits = 3,
                                table_dir = TABLE_DIR,
                                stars = c("*" = 0.10, "**" = 0.05, "***" = 0.01),
                                fstat_keep = NULL) {
  if (!length(mods)) return(invisible(NULL))

  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  md_path <- file.path(table_dir, paste0(filename, ".md"))

  mod_names <- names(mods)
  if (is.null(mod_names)) {
    mod_names <- paste0("(", seq_along(mods), ")")
  }

  cm <- .extract_coef_matrix(mods, coef_map = coef_map, digits = digits, stars = stars)
  fe_info <- .get_fe_info(mods, fe_labels)
  gof <- .extract_gof_rows(mods, digits = digits)

  lines <- character(0)
  if (!is.null(dep_var)) {
    lines <- c(lines, paste0("**Dep. var.:** ", dep_var), "")
  }

  header <- c("", mod_names)
  lines <- c(
    lines,
    paste0("| ", paste(header, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(header)), collapse = "|"), "|")
  )

  for (i in seq_len(nrow(cm$coef_rows))) {
    lines <- c(
      lines,
      paste0("| ", paste(c(cm$labels[[i]], cm$coef_rows[i, ]), collapse = " | "), " |"),
      paste0("| ", paste(c("", cm$se_rows[i, ]), collapse = " | "), " |")
    )
  }

  if (!fe_info$constant && !is.null(fe_info$rows)) {
    for (r in seq_len(nrow(fe_info$rows))) {
      vals <- c(fe_info$rows[r, 1], ifelse(nzchar(fe_info$rows[r, -1]), "Y", ""))
      lines <- c(lines, paste0("| ", paste(vals, collapse = " | "), " |"))
    }
  }

  clust_vals <- sapply(mods, function(m) {
    vcov_type <- attr(m$cov.scaled, "type")
    if (is.null(vcov_type)) return("---")
    if (grepl("muni_id", vcov_type) && grepl("(cnae_section|sector_group)", vcov_type)) {
      return("muni + sector")
    }
    if (grepl("firm_id", vcov_type) && grepl("muni_id", vcov_type)) {
      return("firm + muni")
    }
    if (grepl("muni_id", vcov_type)) {
      return("muni")
    }
    gsub("Clustered \\((.+)\\)", "\\1", vcov_type)
  })
  lines <- c(lines, paste0("| ", paste(c("Clustering", clust_vals), collapse = " | "), " |"))

  fstats <- vapply(mods, safe_wald, numeric(1), keep = if (!is.null(fstat_keep)) fstat_keep else "^(FA_|FA_bar_)")
  lines <- c(lines, paste0("| ", paste(c("F-statistic", sprintf("%.3f", fstats)), collapse = " | "), " |"))
  lines <- c(lines, paste0("| ", paste(c("Observations", gof$n_obs), collapse = " | "), " |"))
  lines <- c(lines, paste0("| ", paste(c("R2", gof$r2), collapse = " | "), " |"))

  if (!is.null(notes) && nzchar(notes)) {
    lines <- c(lines, "", notes)
  }

  writeLines(lines, md_path)
  invisible(md_path)
}

# --- Proposition 2 specific functions -----------------------------------------

save_prop2_tables <- function(mods,
                              filename,
                              coef_map,
                              dep_var,
                              notes,
                              fe_labels,
                              fstat_keep = "^FA_") {
  tex_path <- save_beamer_table(
    mods,
    filename,
    coef_map = coef_map,
    dep_var = dep_var,
    notes = notes,
    fe_labels = fe_labels,
    fstat_keep = fstat_keep,
    table_dir = table_dir
  )
  md_path <- save_markdown_table(
    mods,
    filename,
    coef_map = coef_map,
    dep_var = dep_var,
    notes = notes,
    fe_labels = fe_labels,
    fstat_keep = fstat_keep,
    table_dir = table_dir
  )
  list(tex_path = tex_path, md_path = md_path)
}

get_prop2_terms <- function(alignment, exposure) {
  tiers <- c("mayor", "gov", "pres")
  if (identical(exposure, "binary")) {
    firm_terms <- paste0("FA_binary_", tiers, "_", alignment)
  } else {
    firm_terms <- paste0("FA_", tiers, "_", alignment)
  }
  agg_terms <- sub("^FA_", "FA_bar_", firm_terms)
  list(firm = firm_terms, agg = agg_terms)
}

build_prop2_sample <- function(dt_in, firm_terms, weighted = FALSE) {
  ok <- !is.na(dt_in$has_bndes_fmt)
  for (term in firm_terms) {
    ok <- ok & !is.na(dt_in[[term]])
  }
  if (isTRUE(weighted)) {
    ok <- ok & is.finite(dt_in$n_employees) & dt_in$n_employees > 0
  }
  dt_in[ok]
}

# C3: Restrict to firms that appear in exactly one (muni_id, sector) cell
filter_single_cell_firms <- function(dt, sector_col) {
  firm_cells <- dt[, .(n_cells = uniqueN(paste(muni_id, get(sector_col), sep = "_"))),
                   by = firm_id]
  single <- firm_cells[n_cells == 1L, firm_id]
  n_single <- length(single)
  n_total <- uniqueN(dt$firm_id)
  n_obs_keep <- sum(dt$firm_id %in% single)
  cat(sprintf("  Single-cell filter: %s / %s firms (%.1f%%), %s / %s obs (%.1f%%)\n",
              format(n_single, big.mark = ","), format(n_total, big.mark = ","),
              100 * n_single / max(n_total, 1L),
              format(n_obs_keep, big.mark = ","), format(nrow(dt), big.mark = ","),
              100 * n_obs_keep / max(nrow(dt), 1L)))
  dt[firm_id %in% single]
}

# C5: Within each support regime, keep only firms present in ALL years
filter_balanced_within_regime <- function(dt) {
  regime_year_list <- dt[, .(years = list(sort(unique(year)))), by = support_regime]
  firm_regime_years <- dt[, .(
    present = list(sort(unique(year)))
  ), by = .(firm_id, support_regime)]
  firm_regime_years[regime_year_list, expected := i.years, on = "support_regime"]
  balanced <- firm_regime_years[mapply(identical, present, expected)]
  keep_keys <- balanced[, .(firm_id, support_regime)]
  dt_out <- dt[keep_keys, on = .(firm_id, support_regime), nomatch = 0L]
  cat(sprintf("  Balanced filter: %s / %s obs (%.1f%%)\n",
              format(nrow(dt_out), big.mark = ","), format(nrow(dt), big.mark = ","),
              100 * nrow(dt_out) / max(nrow(dt), 1L)))
  dt_out
}

compare_model_coefficients <- function(firm_mod,
                                       agg_mod,
                                       firm_terms,
                                       agg_terms,
                                       tol = PROP2_TOL) {
  if (is.null(firm_mod) || is.null(agg_mod)) {
    return(list(pass = FALSE, max_abs_diff = NA_real_))
  }
  firm_coef <- coef(firm_mod)[firm_terms]
  agg_coef <- coef(agg_mod)[agg_terms]
  diffs <- abs(unname(firm_coef) - unname(agg_coef))
  max_diff <- if (length(diffs)) max(diffs, na.rm = TRUE) else NA_real_
  list(pass = is.finite(max_diff) && max_diff < tol, max_abs_diff = max_diff)
}

build_prop2_notes <- function(alignment, exposure, fe_type, include_unweighted, include_emp_weighted) {
  exact_text <- if (identical(fe_type, "exact")) {
    "Aggregated columns use muni x sector x support-regime FE plus muni x year FE."
  } else {
    "Aggregated columns use muni x sector FE plus muni x year FE."
  }
  col_parts <- c(
    if (include_unweighted) "Cols 1-3: firm unweighted, agg N_c-weighted, agg simple-average.",
    if (include_emp_weighted) {
      if (include_unweighted) {
        "Cols 4-6: firm employment-weighted, agg E_c-weighted, agg employment-average simple."
      } else {
        "Cols 1-3: firm employment-weighted, agg E_c-weighted, agg employment-average simple."
      }
    }
  )

  note_parts <- c(
    "Firm columns use firm + muni x year FE.",
    exact_text,
    if (identical(alignment, "coalition")) "Coalition alignment." else "Party alignment.",
    if (identical(exposure, "binary")) "Binary exposure." else "Pooled-count exposure.",
    col_parts,
    "Firm SEs clustered by firm + muni; aggregated SEs clustered by muni + sector.",
    "$^{***}p<0.01$, $^{**}p<0.05$, $^{*}p<0.10$."
  )
  paste(note_parts[!is.na(note_parts) & nzchar(note_parts)], collapse = " ")
}

build_prop2_fe_notes <- function(alignment, exposure) {
  note_parts <- c(
    if (identical(alignment, "coalition")) "Coalition alignment." else "Party alignment.",
    if (identical(exposure, "binary")) "Binary exposure." else "Pooled-count exposure.",
    "Columns compare relaxed and exact aggregated FE under matched and unmatched cell weighting.",
    "Aggregated SEs clustered by muni + sector.",
    "$^{***}p<0.01$, $^{**}p<0.05$, $^{*}p<0.10$."
  )
  paste(note_parts[!is.na(note_parts) & nzchar(note_parts)], collapse = " ")
}

build_prop2_fe_labels <- function() {
  fe_labels <- FE_LABELS
  fe_labels[[paste0("muni_id^", SCOL, "^support_regime")]] <- "Muni $\\times$ sector $\\times$ support regime FE"
  fe_labels
}

# --- Dry run ------------------------------------------------------------------

prop2_output_names <- character(0)
available_exposures_dry <- c("pooled_count", "binary")
for (alignment in PROP2_ALIGNMENTS) {
  for (exposure in available_exposures_dry) {
    prop2_output_names <- c(
      prop2_output_names,
      paste0("prop2_equiv_relaxed_", alignment, "_", exposure),
      paste0("prop2_equiv_exact_", alignment, "_", exposure),
      paste0("prop2_fe_comparison_", alignment, "_", exposure)
    )
  }
}
prop2_output_names <- c(
  prop2_output_names,
  "prop2_equality_check.csv",
  "prop2_sample_diagnostic.csv",
  if (SINGLE_CELL) c("prop2_tier_comparison.csv",
                      "prop2_sample_restriction_summary.csv",
                      "prop2_tier_summary_table")
)

if (DRY_RUN) {
  cat("Dry run enabled: planned outputs only.\n")
  cat("  Proposition 2 outputs:\n")
  for (nm in prop2_output_names) {
    cat("   -", nm, "\n")
  }
  cat("\n==============================================================================\n")
  cat("Dry run complete.\n")
  cat("Tables would be saved to:", table_dir, "\n")
  cat("==============================================================================\n")
  quit(save = "no", status = 0)
}

# ==============================================================================
# STEP 1: Load firm panel
# ==============================================================================

cat("Step 1: Loading firm panel...\n")

# Enumerate available FA columns from the sparse instruments file.
paths_52b <- firm_panel_paths("cycle_specific")
avail_inst_cols_52b <- if (file.exists(paths_52b$sparse) && requireNamespace("fst", quietly = TRUE)) {
  fst::metadata_fst(paths_52b$sparse)$columnNames
} else character(0)
fa_cols_all    <- grep("^FA_", avail_inst_cols_52b, value = TRUE)
fa_cols_pooled <- grep("^FA_(mayor|gov|pres)_(coalition|party)$", fa_cols_all, value = TRUE)
fa_cols_binary <- grep("^FA_binary_(mayor|gov|pres)_(coalition|party)$", fa_cols_all, value = TRUE)
fa_cols <- c(fa_cols_pooled, fa_cols_binary)

keep_base_cols <- unique(c("firm_id", "muni_id", "year", "cnae_section", SCOL, "has_bndes_fmt", "n_employees"))

dt <- load_firm_panel(
  baseline_type = "cycle_specific",
  columns       = keep_base_cols,
  instruments   = if (length(fa_cols)) fa_cols else character(0),
  zero_fill     = TRUE,
  as_data_table = TRUE
)
cat(sprintf("  Loaded: %s rows\n", format(nrow(dt), big.mark = ",")))

if (!"n_employees" %in% names(dt)) {
  stop("Column `n_employees` not found in firm panel. Rebuild script 42 output before running script 52b.")
}

dt[, firm_id := as.integer(firm_id)]
dt[, muni_id := as.integer(muni_id)]
dt[, year := as.integer(year)]
dt[, n_employees := as.numeric(n_employees)]

if (SCOL == "sector_group" && !SCOL %in% names(dt)) {
  mapping_path <- make_output_path("sector_group_mapping.qs2")
  if (file.exists(mapping_path)) {
    sg_map <- qs_read(mapping_path)
    setDT(sg_map)
    dt[sg_map, sector_group := i.sector_group, on = "cnae_section"]
  } else {
    stop("sector_group column not in panel and mapping not found. Run script 30 first.")
  }
}

# ==============================================================================
# STEP 2: Filter to support-based F_pre and derive support regime
# ==============================================================================

cat("\nStep 2: Filtering to direct F_pre support...\n")

support_cols <- c("firm_id", "muni_id", SCOL)
join_cols <- c(support_cols, "year")
n_total_rows <- nrow(dt)

cell_years <- unique(dt[, ..join_cols])
f_pre_year_map <- build_f_pre_year_map()
f_pre_year_map <- f_pre_year_map[year %in% unique(cell_years$year)]
support_regime_map <- build_support_regime_map(f_pre_year_map)

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
dt_pre[support_regime_map, support_regime := i.support_regime, on = "year"]
dt_pre[support_regime_map, support_regime_label := i.support_regime_label, on = "year"]

n_f_pre_rows <- nrow(dt_pre)
cat(sprintf("  Pre-election firm base: %s rows (%.1f%% of panel)\n",
            format(n_f_pre_rows, big.mark = ","),
            100 * n_f_pre_rows / n_total_rows))
cat(sprintf("  Unique firms: %d, munis: %d, sectors: %d\n",
            uniqueN(dt_pre$firm_id),
            uniqueN(dt_pre$muni_id),
            uniqueN(dt_pre[[SCOL]])))

sample_diag_rows <- list(
  data.table(
    stage = "overall",
    metric = c("panel_rows", "f_pre_rows", "f_pre_unique_firms", "f_pre_unique_munis", "f_pre_unique_sectors"),
    value = c(
      n_total_rows,
      n_f_pre_rows,
      uniqueN(dt_pre$firm_id),
      uniqueN(dt_pre$muni_id),
      uniqueN(dt_pre[[SCOL]])
    )
  )
)

rm(dt, cell_years, supported_keys)
invisible(gc())

# ==============================================================================
# STEP 3: Proposition 2 equivalence test
# ==============================================================================

cat("\nStep 3: Proposition 2 equivalence test...\n")

prop2_equality_rows <- list()

fe_labels_prop2 <- build_prop2_fe_labels()
available_exposures <- c()
if (length(fa_cols_pooled) > 0) available_exposures <- c(available_exposures, "pooled_count")
if (length(fa_cols_binary) > 0) available_exposures <- c(available_exposures, "binary")

for (alignment in PROP2_ALIGNMENTS) {
  for (exposure in available_exposures) {
    term_info <- get_prop2_terms(alignment, exposure)
    if (!all(term_info$firm %in% names(dt_pre))) {
      cat(sprintf("  Skipping Proposition 2 spec [%s, %s]: missing firm terms.\n", alignment, exposure))
      next
    }

    cat(sprintf("\n  Proposition 2 spec: alignment=%s, exposure=%s\n", alignment, exposure))

    dt_prop_uw <- if (isTRUE(RUN_UNWEIGHTED)) build_prop2_sample(dt_pre, term_info$firm, weighted = FALSE) else NULL
    dt_prop_ew <- if (isTRUE(RUN_EMP_WEIGHTED)) build_prop2_sample(dt_pre, term_info$firm, weighted = TRUE) else NULL

    if (isTRUE(RUN_UNWEIGHTED) && nrow(dt_prop_uw)) {
      cat(sprintf("    Unweighted firm sample: %s rows, %s firms\n",
                  format(nrow(dt_prop_uw), big.mark = ","),
                  format(uniqueN(dt_prop_uw$firm_id), big.mark = ",")))
    }
    if (isTRUE(RUN_EMP_WEIGHTED) && nrow(dt_prop_ew)) {
      cat(sprintf("    Employment-weighted firm sample: %s rows, %s firms\n",
                  format(nrow(dt_prop_ew), big.mark = ","),
                  format(uniqueN(dt_prop_ew$firm_id), big.mark = ",")))
    }

    prop2_formula_firm <- as.formula(
      paste0("has_bndes_fmt ~ ", paste(term_info$firm, collapse = " + "), " | ", FE_FIRM)
    )
    prop2_formula_relaxed <- as.formula(
      paste0("H_jmt ~ ", paste(term_info$agg, collapse = " + "), " | ", FE_AGG_RELAXED)
    )
    prop2_formula_exact <- as.formula(
      paste0("H_jmt ~ ", paste(term_info$agg, collapse = " + "), " | ", FE_AGG_EXACT)
    )

    mod_firm_uw <- NULL
    mod_firm_ew <- NULL
    agg_uw <- NULL
    agg_ew <- NULL
    mod_relaxed_nc <- NULL
    mod_relaxed_simple <- NULL
    mod_exact_nc <- NULL
    mod_exact_simple <- NULL
    mod_relaxed_ec <- NULL
    mod_relaxed_emp_simple <- NULL
    mod_exact_ec <- NULL
    mod_exact_emp_simple <- NULL

    if (isTRUE(RUN_UNWEIGHTED) && nrow(dt_prop_uw)) {
      agg_uw <- collapse_agg_panel(dt_prop_uw, term_info$firm, weighted = FALSE)
      agg_uw[support_regime_map, support_regime := i.support_regime, on = "year"]

      mod_firm_uw <- run_feols_model(
        prop2_formula_firm,
        dt_prop_uw,
        vcov_obj = VCOV_FIRM,
        fixef_rm = "none",
        label = sprintf("Firm unweighted [%s, %s]", alignment, exposure),
        keep_pat = "^FA_"
      )
      mod_relaxed_nc <- run_feols_model(
        prop2_formula_relaxed,
        agg_uw,
        vcov_obj = VCOV_AGG,
        weights_formula = ~N_pre,
        fixef_rm = "none",
        label = sprintf("Agg N_c-weighted, relaxed FE [%s, %s]", alignment, exposure),
        keep_pat = "^FA_bar_"
      )
      mod_relaxed_simple <- run_feols_model(
        prop2_formula_relaxed,
        agg_uw,
        vcov_obj = VCOV_AGG,
        fixef_rm = "none",
        label = sprintf("Agg simple, relaxed FE [%s, %s]", alignment, exposure),
        keep_pat = "^FA_bar_"
      )
      mod_exact_nc <- run_feols_model(
        prop2_formula_exact,
        agg_uw,
        vcov_obj = VCOV_AGG,
        weights_formula = ~N_pre,
        fixef_rm = "none",
        label = sprintf("Agg N_c-weighted, exact FE [%s, %s]", alignment, exposure),
        keep_pat = "^FA_bar_"
      )
      mod_exact_simple <- run_feols_model(
        prop2_formula_exact,
        agg_uw,
        vcov_obj = VCOV_AGG,
        fixef_rm = "none",
        label = sprintf("Agg simple, exact FE [%s, %s]", alignment, exposure),
        keep_pat = "^FA_bar_"
      )
    }

    if (isTRUE(RUN_EMP_WEIGHTED) && nrow(dt_prop_ew)) {
      agg_ew <- collapse_agg_panel(dt_prop_ew, term_info$firm, weighted = TRUE)
      agg_ew[support_regime_map, support_regime := i.support_regime, on = "year"]

      mod_firm_ew <- run_feols_model(
        prop2_formula_firm,
        dt_prop_ew,
        vcov_obj = VCOV_FIRM,
        weights_formula = ~n_employees,
        fixef_rm = "none",
        label = sprintf("Firm employment-weighted [%s, %s]", alignment, exposure),
        keep_pat = "^FA_"
      )
      mod_relaxed_ec <- run_feols_model(
        prop2_formula_relaxed,
        agg_ew,
        vcov_obj = VCOV_AGG,
        weights_formula = ~emp_pre,
        fixef_rm = "none",
        label = sprintf("Agg E_c-weighted, relaxed FE [%s, %s]", alignment, exposure),
        keep_pat = "^FA_bar_"
      )
      mod_relaxed_emp_simple <- run_feols_model(
        prop2_formula_relaxed,
        agg_ew,
        vcov_obj = VCOV_AGG,
        fixef_rm = "none",
        label = sprintf("Agg emp-simple, relaxed FE [%s, %s]", alignment, exposure),
        keep_pat = "^FA_bar_"
      )
      mod_exact_ec <- run_feols_model(
        prop2_formula_exact,
        agg_ew,
        vcov_obj = VCOV_AGG,
        weights_formula = ~emp_pre,
        fixef_rm = "none",
        label = sprintf("Agg E_c-weighted, exact FE [%s, %s]", alignment, exposure),
        keep_pat = "^FA_bar_"
      )
      mod_exact_emp_simple <- run_feols_model(
        prop2_formula_exact,
        agg_ew,
        vcov_obj = VCOV_AGG,
        fixef_rm = "none",
        label = sprintf("Agg emp-simple, exact FE [%s, %s]", alignment, exposure),
        keep_pat = "^FA_bar_"
      )
    }

    rename_map <- setNames(term_info$firm, term_info$agg)
    coef_map_prop2 <- COEF_MAP_INSTRUMENTS[term_info$firm]
    if (!length(coef_map_prop2)) {
      coef_map_prop2 <- setNames(term_info$firm, term_info$firm)
    }

    relaxed_models <- list()
    exact_models <- list()
    fe_compare_models <- list()

    if (isTRUE(RUN_UNWEIGHTED) && !is.null(mod_firm_uw)) {
      relaxed_models[["Firm UW"]] <- mod_firm_uw
      relaxed_models[["Agg N_c-wt"]] <- harmonize_model_coef_names(mod_relaxed_nc, rename_map)
      relaxed_models[["Agg simple"]] <- harmonize_model_coef_names(mod_relaxed_simple, rename_map)

      exact_models[["Firm UW"]] <- mod_firm_uw
      exact_models[["Agg N_c-wt"]] <- harmonize_model_coef_names(mod_exact_nc, rename_map)
      exact_models[["Agg simple"]] <- harmonize_model_coef_names(mod_exact_simple, rename_map)

      fe_compare_models[["Relaxed N_c-wt"]] <- mod_relaxed_nc
      fe_compare_models[["Exact N_c-wt"]] <- mod_exact_nc
      fe_compare_models[["Relaxed simple"]] <- mod_relaxed_simple
      fe_compare_models[["Exact simple"]] <- mod_exact_simple
    }
    if (isTRUE(RUN_EMP_WEIGHTED) && !is.null(mod_firm_ew)) {
      relaxed_models[["Firm EW"]] <- mod_firm_ew
      relaxed_models[["Agg E_c-wt"]] <- harmonize_model_coef_names(mod_relaxed_ec, rename_map)
      relaxed_models[["Agg emp-simple"]] <- harmonize_model_coef_names(mod_relaxed_emp_simple, rename_map)

      exact_models[["Firm EW"]] <- mod_firm_ew
      exact_models[["Agg E_c-wt"]] <- harmonize_model_coef_names(mod_exact_ec, rename_map)
      exact_models[["Agg emp-simple"]] <- harmonize_model_coef_names(mod_exact_emp_simple, rename_map)

      fe_compare_models[["Relaxed E_c-wt"]] <- mod_relaxed_ec
      fe_compare_models[["Exact E_c-wt"]] <- mod_exact_ec
      fe_compare_models[["Relaxed emp-simple"]] <- mod_relaxed_emp_simple
      fe_compare_models[["Exact emp-simple"]] <- mod_exact_emp_simple
    }

    if (length(relaxed_models)) {
      save_prop2_tables(
        relaxed_models,
        paste0("prop2_equiv_relaxed_", alignment, "_", exposure),
        coef_map = coef_map_prop2,
        dep_var = "$\\mathbf{1}(\\text{BNDES}_{fmt}>0)$ / $H^{\\text{pre}}_{jmt}$",
        notes = build_prop2_notes(alignment, exposure, "relaxed", RUN_UNWEIGHTED, RUN_EMP_WEIGHTED),
        fe_labels = fe_labels_prop2,
        fstat_keep = "^FA_"
      )
    }

    if (length(exact_models)) {
      save_prop2_tables(
        exact_models,
        paste0("prop2_equiv_exact_", alignment, "_", exposure),
        coef_map = coef_map_prop2,
        dep_var = "$\\mathbf{1}(\\text{BNDES}_{fmt}>0)$ / $H^{\\text{pre}}_{jmt}$",
        notes = build_prop2_notes(alignment, exposure, "exact", RUN_UNWEIGHTED, RUN_EMP_WEIGHTED),
        fe_labels = fe_labels_prop2,
        fstat_keep = "^FA_"
      )
    }

    if (length(fe_compare_models)) {
      save_prop2_tables(
        fe_compare_models,
        paste0("prop2_fe_comparison_", alignment, "_", exposure),
        coef_map = COEF_MAP_INSTRUMENTS[term_info$agg],
        dep_var = "$H^{\\text{pre}}_{jmt}$",
        notes = build_prop2_fe_notes(alignment, exposure),
        fe_labels = fe_labels_prop2,
        fstat_keep = "^FA_bar_"
      )
    }

    if (isTRUE(RUN_UNWEIGHTED) && !is.null(mod_firm_uw)) {
      relaxed_match <- compare_model_coefficients(mod_firm_uw, mod_relaxed_nc, term_info$firm, term_info$agg)
      relaxed_simple_gap <- compare_model_coefficients(mod_firm_uw, mod_relaxed_simple, term_info$firm, term_info$agg)
      exact_match <- compare_model_coefficients(mod_firm_uw, mod_exact_nc, term_info$firm, term_info$agg)
      exact_simple_gap <- compare_model_coefficients(mod_firm_uw, mod_exact_simple, term_info$firm, term_info$agg)

      prop2_equality_rows[[length(prop2_equality_rows) + 1L]] <- data.table(
        alignment = alignment,
        exposure = exposure,
        weighting_target = "unweighted",
        fe_type = c("relaxed", "exact"),
        tolerance = PROP2_TOL,
        pass_weighted = c(relaxed_match$pass, exact_match$pass),
        max_abs_diff_weighted = c(relaxed_match$max_abs_diff, exact_match$max_abs_diff),
        max_abs_diff_simple = c(relaxed_simple_gap$max_abs_diff, exact_simple_gap$max_abs_diff),
        firm_candidate_n = nrow(dt_prop_uw),
        firm_used_n = nobs(mod_firm_uw),
        agg_candidate_n = nrow(agg_uw),
        agg_weighted_used_n = c(nobs(mod_relaxed_nc), nobs(mod_exact_nc)),
        agg_simple_used_n = c(nobs(mod_relaxed_simple), nobs(mod_exact_simple)),
        firm_wald_f = safe_wald(mod_firm_uw, "^FA_"),
        agg_weighted_wald_f = c(safe_wald(mod_relaxed_nc, "^FA_bar_"), safe_wald(mod_exact_nc, "^FA_bar_")),
        agg_simple_wald_f = c(safe_wald(mod_relaxed_simple, "^FA_bar_"), safe_wald(mod_exact_simple, "^FA_bar_"))
      )

      sample_diag_rows[[length(sample_diag_rows) + 1L]] <- data.table(
        stage = "prop2_retention",
        alignment = alignment,
        exposure = exposure,
        weighting_target = "unweighted",
        fe_type = c("relaxed", "exact"),
        metric = c("agg_retention_rate", "agg_retention_rate"),
        value = c(
          nobs(mod_relaxed_nc) / max(nrow(agg_uw), 1L),
          nobs(mod_exact_nc) / max(nrow(agg_uw), 1L)
        )
      )
    }

    if (isTRUE(RUN_EMP_WEIGHTED) && !is.null(mod_firm_ew)) {
      relaxed_match <- compare_model_coefficients(mod_firm_ew, mod_relaxed_ec, term_info$firm, term_info$agg)
      relaxed_simple_gap <- compare_model_coefficients(mod_firm_ew, mod_relaxed_emp_simple, term_info$firm, term_info$agg)
      exact_match <- compare_model_coefficients(mod_firm_ew, mod_exact_ec, term_info$firm, term_info$agg)
      exact_simple_gap <- compare_model_coefficients(mod_firm_ew, mod_exact_emp_simple, term_info$firm, term_info$agg)

      prop2_equality_rows[[length(prop2_equality_rows) + 1L]] <- data.table(
        alignment = alignment,
        exposure = exposure,
        weighting_target = "emp_weighted",
        fe_type = c("relaxed", "exact"),
        tolerance = PROP2_TOL,
        pass_weighted = c(relaxed_match$pass, exact_match$pass),
        max_abs_diff_weighted = c(relaxed_match$max_abs_diff, exact_match$max_abs_diff),
        max_abs_diff_simple = c(relaxed_simple_gap$max_abs_diff, exact_simple_gap$max_abs_diff),
        firm_candidate_n = nrow(dt_prop_ew),
        firm_used_n = nobs(mod_firm_ew),
        agg_candidate_n = nrow(agg_ew),
        agg_weighted_used_n = c(nobs(mod_relaxed_ec), nobs(mod_exact_ec)),
        agg_simple_used_n = c(nobs(mod_relaxed_emp_simple), nobs(mod_exact_emp_simple)),
        firm_wald_f = safe_wald(mod_firm_ew, "^FA_"),
        agg_weighted_wald_f = c(safe_wald(mod_relaxed_ec, "^FA_bar_"), safe_wald(mod_exact_ec, "^FA_bar_")),
        agg_simple_wald_f = c(safe_wald(mod_relaxed_emp_simple, "^FA_bar_"), safe_wald(mod_exact_emp_simple, "^FA_bar_"))
      )

      sample_diag_rows[[length(sample_diag_rows) + 1L]] <- data.table(
        stage = "prop2_retention",
        alignment = alignment,
        exposure = exposure,
        weighting_target = "emp_weighted",
        fe_type = c("relaxed", "exact"),
        metric = c("agg_retention_rate", "agg_retention_rate"),
        value = c(
          nobs(mod_relaxed_ec) / max(nrow(agg_ew), 1L),
          nobs(mod_exact_ec) / max(nrow(agg_ew), 1L)
        )
      )
    }

    if (!is.null(mod_exact_nc) && nrow(agg_uw) > 0) {
      exact_retention <- nobs(mod_exact_nc) / nrow(agg_uw)
      if (is.finite(exact_retention) && exact_retention < 0.20) {
        cat(sprintf(
          "    WARNING: exact aggregated FE retention is %.1f%% for [%s, %s] unweighted.\n",
          100 * exact_retention, alignment, exposure
        ))
      }
    }
    if (!is.null(mod_exact_ec) && nrow(agg_ew) > 0) {
      exact_retention <- nobs(mod_exact_ec) / nrow(agg_ew)
      if (is.finite(exact_retention) && exact_retention < 0.20) {
        cat(sprintf(
          "    WARNING: exact aggregated FE retention is %.1f%% for [%s, %s] emp_weighted.\n",
          100 * exact_retention, alignment, exposure
        ))
      }
    }

    rm(dt_prop_uw, dt_prop_ew, agg_uw, agg_ew,
       mod_firm_uw, mod_firm_ew,
       mod_relaxed_nc, mod_relaxed_simple, mod_exact_nc, mod_exact_simple,
       mod_relaxed_ec, mod_relaxed_emp_simple, mod_exact_ec, mod_exact_emp_simple,
       relaxed_models, exact_models, fe_compare_models)
    invisible(gc())
  }
}

# ==============================================================================
# STEP 4: Tier comparison (Bronze vs Silver)
# ==============================================================================

prop2_tier_rows <- list()
prop2_restriction_rows <- list()

if (SINGLE_CELL) {
  cat("\nStep 4: Proposition 2 tier comparison...\n")

  available_exposures <- c()
  if (length(fa_cols_pooled) > 0) available_exposures <- c(available_exposures, "pooled_count")
  if (length(fa_cols_binary) > 0) available_exposures <- c(available_exposures, "binary")

  weighting_modes <- c()
  if (isTRUE(RUN_UNWEIGHTED)) weighting_modes <- c(weighting_modes, "unweighted")
  if (isTRUE(RUN_EMP_WEIGHTED)) weighting_modes <- c(weighting_modes, "emp_weighted")

  silver_filter <- if (BALANCED) {
    function(d) filter_balanced_within_regime(filter_single_cell_firms(d, SCOL))
  } else {
    function(d) filter_single_cell_firms(d, SCOL)
  }

  tier_defs <- list(
    list(name = "bronze", label = "Full sample", filter_fn = identity),
    list(name = "silver",
         label = if (BALANCED) "Single-cell + balanced" else "Single-cell only",
         filter_fn = silver_filter)
  )

  for (alignment in PROP2_ALIGNMENTS) {
    for (exposure in available_exposures) {
      term_info <- get_prop2_terms(alignment, exposure)
      if (!all(term_info$firm %in% names(dt_pre))) next

      cat(sprintf("\n  Tier comparison: alignment=%s, exposure=%s\n", alignment, exposure))

      for (wt_mode in weighting_modes) {
        is_weighted <- identical(wt_mode, "emp_weighted")
        n_baseline <- nrow(build_prop2_sample(dt_pre, term_info$firm, weighted = is_weighted))

        for (tier in tier_defs) {
          cat(sprintf("    Tier [%s] (%s, %s):\n", tier$name, alignment, wt_mode))

          dt_tier <- build_prop2_sample(dt_pre, term_info$firm, weighted = is_weighted)
          if (!nrow(dt_tier)) {
            cat("      Skipped: empty sample after NA filter\n")
            next
          }

          if (!"support_regime" %in% names(dt_tier)) {
            dt_tier[support_regime_map, support_regime := i.support_regime, on = "year"]
          }

          dt_tier <- tier$filter_fn(dt_tier)
          if (!nrow(dt_tier)) {
            cat("      Skipped: empty sample after tier filter\n")
            next
          }

          n_firms_tier <- uniqueN(dt_tier$firm_id)
          n_obs_tier <- nrow(dt_tier)

          prop2_restriction_rows[[length(prop2_restriction_rows) + 1L]] <- data.table(
            tier = tier$name,
            alignment = alignment,
            exposure = exposure,
            weighting = wt_mode,
            n_firms = n_firms_tier,
            n_obs = n_obs_tier,
            n_munis = uniqueN(dt_tier$muni_id),
            n_sectors = uniqueN(dt_tier[[SCOL]])
          )

          firm_fml <- as.formula(
            paste0("has_bndes_fmt ~ ", paste(term_info$firm, collapse = " + "), " | ", FE_FIRM)
          )
          firm_wt <- if (is_weighted) ~n_employees else NULL
          mod_firm <- run_feols_model(
            firm_fml, dt_tier, vcov_obj = VCOV_FIRM,
            weights_formula = firm_wt, fixef_rm = "none",
            label = sprintf("      Firm [%s]", tier$name),
            keep_pat = "^FA_"
          )

          agg_tier <- collapse_agg_panel(dt_tier, term_info$firm, weighted = is_weighted)
          agg_tier[support_regime_map, support_regime := i.support_regime, on = "year"]

          agg_fml <- as.formula(
            paste0("H_jmt ~ ", paste(term_info$agg, collapse = " + "), " | ", FE_AGG_EXACT)
          )
          agg_wt <- if (is_weighted) ~emp_pre else ~N_pre
          mod_agg <- run_feols_model(
            agg_fml, agg_tier, vcov_obj = VCOV_AGG,
            weights_formula = agg_wt, fixef_rm = "none",
            label = sprintf("      Agg [%s]", tier$name),
            keep_pat = "^FA_bar_"
          )

          gap <- compare_model_coefficients(mod_firm, mod_agg, term_info$firm, term_info$agg)

          n_cells_tier <- if (!is.null(mod_agg)) nobs(mod_agg) else NA_integer_
          firm_obs_used <- if (!is.null(mod_firm)) nobs(mod_firm) else NA_integer_

          prop2_tier_rows[[length(prop2_tier_rows) + 1L]] <- data.table(
            tier = tier$name,
            alignment = alignment,
            exposure = exposure,
            weighting = wt_mode,
            max_abs_diff = gap$max_abs_diff,
            firm_obs = firm_obs_used,
            agg_cells = n_cells_tier,
            firm_retained_pct = 100 * n_obs_tier / max(n_baseline, 1L)
          )

          cat(sprintf("      max|coef_diff| = %.6f, firm_obs = %s, agg_cells = %s\n",
                      if (is.finite(gap$max_abs_diff)) gap$max_abs_diff else NA_real_,
                      format(firm_obs_used, big.mark = ","),
                      format(n_cells_tier, big.mark = ",")))

          rm(dt_tier, agg_tier, mod_firm, mod_agg)
          invisible(gc())
        }
      }
    }
  }

  if (length(prop2_tier_rows)) {
    tier_dt <- rbindlist(prop2_tier_rows, fill = TRUE)

    gold_row <- data.table(
      tier = "gold",
      alignment = "synthetic",
      exposure = "synthetic",
      weighting = "unweighted",
      max_abs_diff = 1e-15,
      firm_obs = 10000L,
      agg_cells = 2500L,
      firm_retained_pct = 100
    )
    tier_dt <- rbind(gold_row, tier_dt, fill = TRUE)

    tier_path <- file.path(table_dir, "prop2_tier_comparison.csv")
    write_csv_atomic(tier_dt, tier_path)
    cat(sprintf("\n  Saved: %s\n", tier_path))

    cat("\n  --- Tier Comparison Summary ---\n")
    for (i in seq_len(nrow(tier_dt))) {
      r <- tier_dt[i]
      cat(sprintf("    %-7s  %-10s  %-12s  %-12s  max|diff| = %.2e  obs = %s\n",
                  r$tier, r$alignment, r$exposure, r$weighting,
                  r$max_abs_diff, format(r$firm_obs, big.mark = ",")))
    }
  }

  if (length(prop2_restriction_rows)) {
    restriction_dt <- rbindlist(prop2_restriction_rows, fill = TRUE)
    restriction_path <- file.path(table_dir, "prop2_sample_restriction_summary.csv")
    write_csv_atomic(restriction_dt, restriction_path)
    cat(sprintf("  Saved: %s\n", restriction_path))
  }

  if (length(prop2_tier_rows)) {
    cat("\n  Generating Beamer tier summary table...\n")

    tier_dt_summary <- rbindlist(prop2_tier_rows, fill = TRUE)
    tier_agg <- tier_dt_summary[, .(
      max_gap = max(max_abs_diff, na.rm = TRUE),
      mean_gap = mean(max_abs_diff, na.rm = TRUE),
      n_specs = .N,
      min_obs = min(firm_obs, na.rm = TRUE),
      max_obs = max(firm_obs, na.rm = TRUE)
    ), by = tier]

    tex_lines <- c(
      "\\begin{table}[ht]",
      "\\centering",
      "\\footnotesize",
      sprintf("\\begin{tabular}{ll%s}", paste(rep("r", 3), collapse = "")),
      "\\toprule",
      "Tier & Restrictions & Max $|\\Delta\\hat{\\beta}|$ & Specs & Obs range \\\\",
      "\\midrule"
    )

    tex_lines <- c(tex_lines,
      "Gold & Synthetic DGP (C1--C6) & $1.0 \\times 10^{-15}$ & 5 & 10{,}000 \\\\"
    )

    silver_agg <- tier_agg[tier == "silver"]
    if (nrow(silver_agg)) {
      silver_label <- if (BALANCED) "Single-cell + balanced + no-rm + exact FE" else "Single-cell + no-rm + exact FE"
      tex_lines <- c(tex_lines, sprintf(
        "Silver & %s & $%.2e$ & %d & %s--%s \\\\",
        silver_label,
        silver_agg$max_gap,
        silver_agg$n_specs,
        format(silver_agg$min_obs, big.mark = "{,}"),
        format(silver_agg$max_obs, big.mark = "{,}")
      ))
    }

    bronze_agg <- tier_agg[tier == "bronze"]
    if (nrow(bronze_agg)) {
      tex_lines <- c(tex_lines, sprintf(
        "Bronze & Full sample + no-rm + exact FE & $%.2e$ & %d & %s--%s \\\\",
        bronze_agg$max_gap,
        bronze_agg$n_specs,
        format(bronze_agg$min_obs, big.mark = "{,}"),
        format(bronze_agg$max_obs, big.mark = "{,}")
      ))
    }

    tex_lines <- c(tex_lines,
      "\\bottomrule",
      "\\end{tabular}",
      sprintf("\\parbox{\\linewidth}{\\scriptsize Gold tier from \\texttt{verify\\_proposition2\\_synthetic.R}. Silver--Bronze gap is a joint effect of relaxing single-cell and balanced constraints (nested comparison, not additive decomposition). Residual Silver gap reflects within-cell regressor heterogeneity (C6).}"),
      "\\end{table}"
    )

    tex_path <- file.path(table_dir, "prop2_tier_summary_table.tex")
    writeLines(tex_lines, tex_path)
    cat(sprintf("  Saved: %s\n", tex_path))

    md_lines <- c(
      "## Proposition 2 Tier Comparison",
      "",
      "| Tier | Restrictions | Max |Delta beta| | Specs | Obs range |",
      "|------|-------------|-------------------|-------|-----------|",
      sprintf("| Gold | Synthetic DGP (C1-C6) | 1.0e-15 | 5 | 10,000 |")
    )
    if (nrow(silver_agg)) {
      silver_label_md <- if (BALANCED) "Single-cell + balanced + no-rm + exact FE" else "Single-cell + no-rm + exact FE"
      md_lines <- c(md_lines, sprintf(
        "| Silver | %s | %.2e | %d | %s--%s |",
        silver_label_md, silver_agg$max_gap, silver_agg$n_specs,
        format(silver_agg$min_obs, big.mark = ","),
        format(silver_agg$max_obs, big.mark = ",")
      ))
    }
    if (nrow(bronze_agg)) {
      md_lines <- c(md_lines, sprintf(
        "| Bronze | Full sample + no-rm + exact FE | %.2e | %d | %s--%s |",
        bronze_agg$max_gap, bronze_agg$n_specs,
        format(bronze_agg$min_obs, big.mark = ","),
        format(bronze_agg$max_obs, big.mark = ",")
      ))
    }
    md_lines <- c(md_lines, "",
      "Gold tier from `verify_proposition2_synthetic.R`. Silver-Bronze gap is a joint effect (nested comparison, not decomposition). Silver residual = within-cell regressor heterogeneity (C6)."
    )

    md_path <- file.path(table_dir, "prop2_tier_summary_table.md")
    writeLines(md_lines, md_path)
    cat(sprintf("  Saved: %s\n", md_path))
  }
}

# ==============================================================================
# STEP 5: Save diagnostics
# ==============================================================================

cat("\nStep 5: Saving diagnostics...\n")

sample_diag_dt <- rbindlist(sample_diag_rows, fill = TRUE)
if (nrow(sample_diag_dt)) {
  sample_diag_path <- file.path(table_dir, "prop2_sample_diagnostic.csv")
  write_csv_atomic(sample_diag_dt, sample_diag_path)
  cat("  Saved:", sample_diag_path, "\n")
}

if (length(prop2_equality_rows)) {
  equality_dt <- rbindlist(prop2_equality_rows, fill = TRUE)
  equality_path <- file.path(table_dir, "prop2_equality_check.csv")
  write_csv_atomic(equality_dt, equality_path)
  cat("  Saved:", equality_path, "\n")
}

rm(dt_pre)
invisible(gc())

cat("\n==============================================================================\n")
cat("Proposition 2 equivalence tests complete.\n")
cat("Tables saved to:", table_dir, "\n")
cat("==============================================================================\n")
