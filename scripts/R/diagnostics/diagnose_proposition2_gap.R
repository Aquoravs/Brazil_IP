#!/usr/bin/env Rscript

# ==============================================================================
# Diagnostic: Proposition 2 Gap — Real-Data Condition Violations
# ==============================================================================
# Quantifies exactly why real data violates Proposition 2's conditions:
#   1. Sample mismatch from singleton absorption (Condition 2)
#   2. FE nesting violation from multi-cell firms (Condition 3)
#
# Tests two fixes:
#   a. Force fixef.rm = "none" to eliminate sample mismatch
#   b. Restrict to single-cell firms to restore FE nesting
#
# Uses one reference spec: coalition alignment, pooled-count exposure,
# unweighted, relaxed FE.
#
# Outputs:
#   - Console summary
#   - CSV at output/diagnostics/prop2_real_data_diagnostics.csv
#
# Usage:
#   Rscript diagnose_proposition2_gap.R [--sector-var=sector_group]
# ==============================================================================

cat("==============================================================================\n")
cat("Diagnostic: Proposition 2 Gap (Real Data)\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})

# --- Bootstrap ----------------------------------------------------------------

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
source(politicsregs_path("_utils", "load_firm_panel.R"))

# --- Check fixest version -----------------------------------------------------

if (packageVersion("fixest") < "0.11") {
  stop("fixest >= 0.11 required for fixef.rm = 'none'. Current: ", packageVersion("fixest"))
}

# --- Parse CLI arguments ------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
svar_flag <- grep("^--sector-var=", args, value = TRUE)

SECTOR_VAR <- "sector_group"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[[1L]])))
  if (!SECTOR_VAR %in% c("cnae_section", "sector_group")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'.")
  }
}

SCOL <- SECTOR_VAR
cat("Sector variable:", SECTOR_VAR, "\n\n")

# --- Configuration ------------------------------------------------------------

FE_FIRM <- "firm_id + muni_id^year"
FE_AGG_RELAXED <- paste0("muni_id^", SCOL, " + muni_id^year")
VCOV_FIRM <- ~ firm_id + muni_id
VCOV_AGG <- as.formula(paste0("~ muni_id + ", SCOL))

# Reference spec: coalition, pooled-count
FIRM_TERMS <- c("FA_mayor_coalition", "FA_gov_coalition", "FA_pres_coalition")
AGG_TERMS <- sub("^FA_", "FA_bar_", FIRM_TERMS)

diag_dir <- file.path(OUTPUT_DIR, "diagnostics")
dir.create(diag_dir, recursive = TRUE, showWarnings = FALSE)

results <- list()

# ==============================================================================
# STEP 1: Load firm panel
# ==============================================================================

cat("Step 1: Loading firm panel...\n")

inst_cols_gap <- grep("^(FA_|dFA_)", FIRM_TERMS, value = TRUE)
base_cols_gap  <- unique(c("firm_id", "muni_id", "year", "cnae_section", SCOL,
                            "has_bndes_fmt", "n_employees",
                            setdiff(FIRM_TERMS, inst_cols_gap)))

dt <- load_firm_panel(
  baseline_type = "cycle_specific",
  columns       = base_cols_gap,
  instruments   = if (length(inst_cols_gap)) inst_cols_gap else character(0),
  zero_fill     = TRUE,
  as_data_table = TRUE
)
cat(sprintf("  Loaded: %s rows\n", format(nrow(dt), big.mark = ",")))

dt[, firm_id := as.integer(firm_id)]
dt[, muni_id := as.integer(muni_id)]
dt[, year := as.integer(year)]

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
# STEP 2: Replicate script 52 F_pre sample construction
# ==============================================================================

cat("\nStep 2: Applying F_pre support filter (replicating script 52)...\n")

# Build F_pre year map (same logic as script 52)
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

support_cols <- c("firm_id", "muni_id", SCOL)
join_cols <- c(support_cols, "year")
n_total_rows <- nrow(dt)

cell_years <- unique(dt[, ..join_cols])
f_pre_year_map <- build_f_pre_year_map()
f_pre_year_map <- f_pre_year_map[year %in% unique(cell_years$year)]

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

cat(sprintf("  Full panel: %s rows\n", format(n_total_rows, big.mark = ",")))
cat(sprintf("  After F_pre filter: %s rows\n", format(nrow(dt_pre), big.mark = ",")))

rm(dt, cell_years, supported_keys)
invisible(gc())

# Apply non-missing variable filter (same as build_prop2_sample in script 52)
ok <- !is.na(dt_pre$has_bndes_fmt)
for (term in FIRM_TERMS) {
  ok <- ok & !is.na(dt_pre[[term]])
}
dt_pre <- dt_pre[ok]

cat(sprintf("  After non-missing filter: %s rows\n", format(nrow(dt_pre), big.mark = ",")))

# ==============================================================================
# STEP 3: Quantify sample mismatch (Condition 2)
# ==============================================================================

cat("\nStep 3: Quantifying sample mismatch from singleton absorption...\n")

setDTthreads(1L)
fixest::setFixest_nthreads(data.table::getDTthreads())

firm_fml <- as.formula(paste0("has_bndes_fmt ~ ", paste(FIRM_TERMS, collapse = " + "), " | ", FE_FIRM))

# Firm-level: with vs. without singleton absorption
cat("  Running firm regression with fixef.rm = 'none'...\n")
mod_firm_no_rm <- feols(firm_fml, data = dt_pre, vcov = VCOV_FIRM,
                        fixef.rm = "none", lean = TRUE, mem.clean = TRUE,
                        nthreads = data.table::getDTthreads())
n_firm_no_rm <- nobs(mod_firm_no_rm)

cat("  Running firm regression with default singleton absorption...\n")
mod_firm_default <- feols(firm_fml, data = dt_pre, vcov = VCOV_FIRM,
                          lean = TRUE, mem.clean = TRUE,
                          nthreads = data.table::getDTthreads())
n_firm_default <- nobs(mod_firm_default)

cat(sprintf("  Firm-level N_obs: no removal = %s, default = %s, dropped = %s\n",
            format(n_firm_no_rm, big.mark = ","),
            format(n_firm_default, big.mark = ","),
            format(n_firm_no_rm - n_firm_default, big.mark = ",")))

results[[length(results) + 1L]] <- data.table(
  diagnostic = "firm_singleton_absorption",
  metric = c("N_obs_no_removal", "N_obs_default", "N_obs_dropped"),
  value = c(n_firm_no_rm, n_firm_default, n_firm_no_rm - n_firm_default)
)

# Collapse to cells
collapse_panel <- function(dt_in) {
  by_cols <- c(SCOL, "muni_id", "year")
  agg <- dt_in[, {
    out <- list(
      H_jmt = mean(has_bndes_fmt, na.rm = TRUE),
      N_pre = .N
    )
    for (col in FIRM_TERMS) {
      out[[sub("^FA_", "FA_bar_", col)]] <- mean(get(col), na.rm = TRUE)
    }
    out
  }, by = by_cols]
  agg
}

agg <- collapse_panel(dt_pre)
agg_fml <- as.formula(paste0("H_jmt ~ ", paste(AGG_TERMS, collapse = " + "), " | ", FE_AGG_RELAXED))

cat("  Running aggregated regression with fixef.rm = 'none'...\n")
mod_agg_no_rm <- feols(agg_fml, data = agg, weights = ~N_pre, vcov = VCOV_AGG,
                       fixef.rm = "none", lean = TRUE,
                       nthreads = data.table::getDTthreads())
n_agg_no_rm <- nobs(mod_agg_no_rm)

cat("  Running aggregated regression with default singleton absorption...\n")
mod_agg_default <- feols(agg_fml, data = agg, weights = ~N_pre, vcov = VCOV_AGG,
                         lean = TRUE,
                         nthreads = data.table::getDTthreads())
n_agg_default <- nobs(mod_agg_default)

cat(sprintf("  Aggregated cells: no removal = %s, default = %s, dropped = %s\n",
            format(n_agg_no_rm, big.mark = ","),
            format(n_agg_default, big.mark = ","),
            format(n_agg_no_rm - n_agg_default, big.mark = ",")))

results[[length(results) + 1L]] <- data.table(
  diagnostic = "agg_singleton_absorption",
  metric = c("N_cells_no_removal", "N_cells_default", "N_cells_dropped"),
  value = c(n_agg_no_rm, n_agg_default, n_agg_no_rm - n_agg_default)
)

# ==============================================================================
# STEP 4: Quantify FE nesting violation (Condition 3)
# ==============================================================================

cat("\nStep 4: Quantifying FE nesting violation (multi-cell firms)...\n")

# A multi-cell firm appears in more than one (muni_id, sector_group) pair
firm_cells <- unique(dt_pre[, .(firm_id, muni_id, sector_cell = get(SCOL))])
cells_per_firm <- firm_cells[, .N, by = firm_id]

n_single_cell <- sum(cells_per_firm$N == 1L)
n_multi_cell <- sum(cells_per_firm$N > 1L)
n_total_firms <- nrow(cells_per_firm)

# Fraction of firm-year observations from multi-cell firms
multi_cell_firms <- cells_per_firm[N > 1L, firm_id]
n_obs_multi <- nrow(dt_pre[firm_id %in% multi_cell_firms])
pct_obs_multi <- 100 * n_obs_multi / nrow(dt_pre)

cat(sprintf("  Single-cell firms: %s (%.1f%%)\n",
            format(n_single_cell, big.mark = ","), 100 * n_single_cell / n_total_firms))
cat(sprintf("  Multi-cell firms: %s (%.1f%%)\n",
            format(n_multi_cell, big.mark = ","), 100 * n_multi_cell / n_total_firms))
cat(sprintf("  Firm-year obs from multi-cell firms: %s (%.1f%%)\n",
            format(n_obs_multi, big.mark = ","), pct_obs_multi))

results[[length(results) + 1L]] <- data.table(
  diagnostic = "fe_nesting_violation",
  metric = c("n_single_cell_firms", "n_multi_cell_firms", "pct_multi_cell_firms",
             "n_obs_multi_cell", "pct_obs_multi_cell"),
  value = c(n_single_cell, n_multi_cell, 100 * n_multi_cell / n_total_firms,
            n_obs_multi, pct_obs_multi)
)

# ==============================================================================
# STEP 5: Test fix — fixef.rm = "none" on both sides
# ==============================================================================

cat("\nStep 5: Testing whether fixef.rm = 'none' closes the gap...\n")

compare_coefs <- function(mod_f, mod_a) {
  fc <- coef(mod_f)[FIRM_TERMS]
  ac <- coef(mod_a)[AGG_TERMS]
  diffs <- abs(unname(fc) - unname(ac))
  max_dev <- max(diffs, na.rm = TRUE)
  worst <- c("mayor", "gov", "pres")[which.max(diffs)]
  list(max_dev = max_dev, worst = worst, firm_coef = fc, agg_coef = ac)
}

# Baseline gap (default singleton absorption on both sides)
gap_default <- compare_coefs(mod_firm_default, mod_agg_default)
cat(sprintf("  Baseline gap (default): max|diff| = %.6f (%s)\n",
            gap_default$max_dev, gap_default$worst))

# Gap with fixef.rm = "none" on both sides
gap_no_rm <- compare_coefs(mod_firm_no_rm, mod_agg_no_rm)
cat(sprintf("  Gap with fixef.rm='none': max|diff| = %.6f (%s)\n",
            gap_no_rm$max_dev, gap_no_rm$worst))

results[[length(results) + 1L]] <- data.table(
  diagnostic = "gap_comparison",
  metric = c("max_dev_default", "max_dev_fixef_rm_none",
             "worst_coef_default", "worst_coef_fixef_rm_none"),
  value = c(gap_default$max_dev, gap_no_rm$max_dev, NA, NA),
  label = c(NA, NA, gap_default$worst, gap_no_rm$worst)
)

# ==============================================================================
# STEP 6: Test fix — single-cell firm restriction
# ==============================================================================

cat("\nStep 6: Testing single-cell firm restriction...\n")

single_cell_firms <- cells_per_firm[N == 1L, firm_id]
dt_single <- dt_pre[firm_id %in% single_cell_firms]

cat(sprintf("  Restricted sample: %s rows, %s firms\n",
            format(nrow(dt_single), big.mark = ","),
            format(length(single_cell_firms), big.mark = ",")))

if (nrow(dt_single) > 0) {
  mod_firm_single <- feols(firm_fml, data = dt_single, vcov = VCOV_FIRM,
                           fixef.rm = "none", lean = TRUE, mem.clean = TRUE,
                           nthreads = data.table::getDTthreads())

  agg_single <- collapse_panel(dt_single)
  mod_agg_single <- feols(agg_fml, data = agg_single, weights = ~N_pre, vcov = VCOV_AGG,
                          fixef.rm = "none", lean = TRUE,
                          nthreads = data.table::getDTthreads())

  gap_single <- compare_coefs(mod_firm_single, mod_agg_single)
  cat(sprintf("  Gap with single-cell restriction + fixef.rm='none': max|diff| = %.6f (%s)\n",
              gap_single$max_dev, gap_single$worst))
  cat(sprintf("  N_obs: firm = %s, agg = %s\n",
              format(nobs(mod_firm_single), big.mark = ","),
              format(nobs(mod_agg_single), big.mark = ",")))

  results[[length(results) + 1L]] <- data.table(
    diagnostic = "single_cell_restriction",
    metric = c("max_dev", "firm_N_obs", "agg_N_obs", "worst_coef"),
    value = c(gap_single$max_dev, nobs(mod_firm_single), nobs(mod_agg_single), NA),
    label = c(NA, NA, NA, gap_single$worst)
  )
} else {
  cat("  WARNING: No single-cell firms found. Skipping.\n")
}

# ==============================================================================
# STEP 7: Summary and save
# ==============================================================================

cat("\n--- Summary ---\n\n")
cat(sprintf("  Singleton absorption (firm): %s obs dropped\n",
            format(n_firm_no_rm - n_firm_default, big.mark = ",")))
cat(sprintf("  Singleton absorption (agg): %s cells dropped\n",
            format(n_agg_no_rm - n_agg_default, big.mark = ",")))
cat(sprintf("  Multi-cell firms: %s / %s (%.1f%%), covering %.1f%% of obs\n",
            format(n_multi_cell, big.mark = ","),
            format(n_total_firms, big.mark = ","),
            100 * n_multi_cell / n_total_firms,
            pct_obs_multi))
cat(sprintf("  Gap (default): %.6f\n", gap_default$max_dev))
cat(sprintf("  Gap (fixef.rm='none'): %.6f\n", gap_no_rm$max_dev))
if (exists("gap_single")) {
  cat(sprintf("  Gap (single-cell + fixef.rm='none'): %.6f\n", gap_single$max_dev))
}

results_dt <- rbindlist(results, fill = TRUE)
out_path <- file.path(diag_dir, "prop2_real_data_diagnostics.csv")
fwrite(results_dt, out_path)
cat(sprintf("\nSaved: %s\n", out_path))

cat("\nDone.\n")
