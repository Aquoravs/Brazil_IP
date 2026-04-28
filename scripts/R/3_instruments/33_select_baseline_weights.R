#!/usr/bin/env Rscript

# ==============================================================================
# Select Baseline Sector Exposure Weights for Shift-Share Instrument
# ==============================================================================
# For each election cycle, pools owner-count exposure counts across a 4-year
# baseline window [election_year - 4, election_year - 1] and recomputes
# pooled-count weights from the aggregated counts. Alternative sector-level
# exposure variants already aggregated at the year level in script 31
# (employment, equal-firm, binary) are averaged across the same window.
#
# Mayor elections:       2004, 2008, 2012, 2016
#   -> baseline windows: 2000-2003 (use 2002-2003), 2004-2007, 2008-2011, 2012-2015
# Governor/Pres elections: 2006, 2010, 2014
#   -> baseline windows:   2002-2005, 2006-2009, 2010-2013
# Note: 2003 gov/pres cycle dropped (baseline 1998-2001 has no data; starts 2002)
#
# Also produces a "2002_fixed" robustness variant using 2002 for all cycles.
#
# Dependencies: script 31 (sector_exposure_weights_owner_grouped.qs2 by default)
# ==============================================================================

cat("==============================================================================\n")
cat("Selecting Baseline-Year Sector Exposure Weights\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
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

setDTthreads(0)

# --- Configuration -----------------------------------------------------------

baseline_window_map <- rbindlist(list(
  data.table(treatment_year = 2005L, bl_start = 2000L, bl_end = 2003L, tier = "mayor"),
  data.table(treatment_year = 2009L, bl_start = 2004L, bl_end = 2007L, tier = "mayor"),
  data.table(treatment_year = 2013L, bl_start = 2008L, bl_end = 2011L, tier = "mayor"),
  data.table(treatment_year = 2017L, bl_start = 2012L, bl_end = 2015L, tier = "mayor"),
  data.table(treatment_year = 2007L, bl_start = 2002L, bl_end = 2005L, tier = "gov_pres"),
  data.table(treatment_year = 2011L, bl_start = 2006L, bl_end = 2009L, tier = "gov_pres"),
  data.table(treatment_year = 2015L, bl_start = 2010L, bl_end = 2013L, tier = "gov_pres")
))

# --- Parse CLI arguments -----------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

svar_flag <- grep("^--sector-var=", args, value = TRUE)
SECTOR_VAR <- "sector_group"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[1])))
  if (!SECTOR_VAR %in% c("cnae_section", "sector_group")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'. Use 'cnae_section' or 'sector_group'.")
  }
}
USE_GROUPS <- (SECTOR_VAR == "sector_group")
SCOL <- SECTOR_VAR
cat("Sector variable:", SECTOR_VAR, "\n\n")

if (USE_GROUPS) {
  weights_path <- make_output_path("sector_exposure_weights_owner_grouped.qs2")
  out_path     <- make_output_path("baseline_sector_weights_grouped.qs2")
  summary_path <- make_output_path("baseline_sector_weights_grouped_summary.csv")
} else {
  weights_path <- make_output_path("sector_exposure_weights_owner.qs2")
  out_path     <- make_output_path("baseline_sector_weights.qs2")
  summary_path <- make_output_path("baseline_sector_weights_summary.csv")
}

# --- Step 1: Load full weight panel ------------------------------------------

cat("Step 1: Loading sector exposure weights...\n")

if (!file.exists(weights_path)) {
  stop("Weights file not found: ", weights_path, "\n  Run script 31 first.")
}

wt <- qs_read(weights_path)
setDT(wt)
cat("  Loaded:", nrow(wt), "rows\n")
cat("  Year range:", paste(range(wt$year), collapse = "-"), "\n")
cat("  Available years:", paste(sort(unique(wt$year)), collapse = ", "), "\n\n")

required_cols <- c(
  "muni_id", SCOL, "year", "party",
  "L_mjp", "L_mj", "L_mj_affiliated",
  "w_mjp", "w_mjp_emp", "w_mjp_firm", "w_mjp_binary"
)
missing_cols <- setdiff(required_cols, names(wt))
if (length(missing_cols)) {
  stop("Weights file is missing required columns: ", paste(missing_cols, collapse = ", "))
}

mean_or_na <- function(x) {
  x <- x[is.finite(x) & !is.na(x)]
  if (!length(x)) {
    return(NA_real_)
  }
  mean(x)
}

build_baseline_rows <- function(wt_slice, treatment_year, tier, baseline_type, baseline_years_used) {
  if (!nrow(wt_slice)) {
    return(NULL)
  }

  by_party <- c("muni_id", SCOL, "party")
  by_sector <- c("muni_id", SCOL)

  owner_party <- wt_slice[, .(L_rjp = sum(L_mjp, na.rm = TRUE)), by = by_party]
  sector_counts <- unique(
    wt_slice[, c(by_sector, "year", "L_mj", "L_mj_affiliated"), with = FALSE]
  )
  sector_counts <- sector_counts[, .(
    L_rj = sum(L_mj_affiliated, na.rm = TRUE),
    N_rj = sum(L_mj, na.rm = TRUE)
  ), by = by_sector]

  out <- merge(owner_party, sector_counts, by = by_sector, all.x = TRUE)
  out[, w_rjp := fifelse(N_rj > 0, L_rjp / N_rj, 0)]
  out[, w_rjp_owners := w_rjp]

  variant_means <- wt_slice[, .(
    w_rjp_emp = mean_or_na(w_mjp_emp),
    w_rjp_firm = mean_or_na(w_mjp_firm),
    w_rjp_binary = mean_or_na(w_mjp_binary)
  ), by = by_party]
  out <- merge(out, variant_means, by = by_party, all.x = TRUE)

  out[, `:=`(
    treatment_year = treatment_year,
    tier = tier,
    baseline_years_used = as.integer(baseline_years_used),
    baseline_type = baseline_type
  )]

  out
}

# --- Step 2: Average weights across baseline windows -------------------------

cat("Step 2: Pooling counts across baseline windows...\n\n")

available_years <- sort(unique(wt$year))
cat("  Available years in data:", paste(available_years, collapse = ", "), "\n\n")

baseline_list <- list()

for (i in seq_len(nrow(baseline_window_map))) {
  ty <- baseline_window_map$treatment_year[i]
  bstart <- baseline_window_map$bl_start[i]
  bend <- baseline_window_map$bl_end[i]
  tier <- baseline_window_map$tier[i]

  window_years <- intersect(seq(bstart, bend), available_years)
  if (!length(window_years)) {
    cat(sprintf(
      "  WARNING: No data in window %d-%d (treatment %d, %s) -- skipping\n",
      bstart, bend, ty, tier
    ))
    next
  }

  wt_window <- wt[year %in% window_years]
  wt_avg <- build_baseline_rows(
    wt_slice = wt_window,
    treatment_year = ty,
    tier = tier,
    baseline_type = "cycle_specific",
    baseline_years_used = length(window_years)
  )

  cat(sprintf(
    "  %s treatment=%d, window=%d-%d (used %d yrs: %s): %d rows\n",
    tier,
    ty,
    bstart,
    bend,
    length(window_years),
    paste(window_years, collapse = ","),
    nrow(wt_avg)
  ))
  baseline_list[[length(baseline_list) + 1L]] <- wt_avg
}

# --- Step 3: Create 2002-fixed robustness variant ----------------------------

cat("\nStep 3: Creating 2002-fixed robustness variant...\n")

wt_2002 <- wt[year == 2002L]
if (!nrow(wt_2002)) {
  cat("  WARNING: No data for year 2002 -- skipping 2002-fixed variant\n")
} else {
  for (i in seq_len(nrow(baseline_window_map))) {
    ty <- baseline_window_map$treatment_year[i]
    tier <- baseline_window_map$tier[i]

    baseline_list[[length(baseline_list) + 1L]] <- build_baseline_rows(
      wt_slice = wt_2002,
      treatment_year = ty,
      tier = tier,
      baseline_type = "2002_fixed",
      baseline_years_used = 1L
    )
  }
  cat("  Created 2002-fixed weights for", nrow(baseline_window_map),
      "treatment-year x tier combinations\n")
}

# --- Step 4: Combine and compute municipality totals -------------------------

cat("\nStep 4: Combining and computing municipality-level totals...\n")

baseline_dt <- rbindlist(baseline_list, use.names = TRUE, fill = TRUE)

setnames(
  baseline_dt,
  c("L_rjp", "L_rj", "N_rj", "w_rjp", "w_rjp_owners", "w_rjp_emp", "w_rjp_firm", "w_rjp_binary"),
  c("L_rjp_0", "L_rj_0", "N_rj_0", "w_rjp_0", "w_rjp_owners_0", "w_rjp_emp_0", "w_rjp_firm_0", "w_rjp_binary_0"),
  skip_absent = TRUE
)

group_keys <- c("muni_id", "treatment_year", "tier", "baseline_type")

if ("N_rj_0" %in% names(baseline_dt)) {
  nrj_unique <- unique(baseline_dt[!is.na(N_rj_0), c(group_keys, SCOL, "N_rj_0"), with = FALSE])
  Nr_dt <- nrj_unique[, .(N_r_0 = sum(N_rj_0, na.rm = TRUE)), by = group_keys]
  baseline_dt <- merge(baseline_dt, Nr_dt, by = group_keys, all.x = TRUE)
  baseline_dt[is.na(N_r_0), N_r_0 := 0]
}

baseline_dt[, L_r_0 := sum(L_rjp_0, na.rm = TRUE), by = group_keys]

setorderv(baseline_dt, c("baseline_type", "tier", "treatment_year", "muni_id", SCOL, "party"))

cat("  Combined dataset:", nrow(baseline_dt), "rows\n")
cat("  Unique municipalities:", uniqueN(baseline_dt$muni_id), "\n")
cat(sprintf("  Unique %s: %d\n", SCOL, uniqueN(baseline_dt[[SCOL]])))
cat("  Columns:", paste(names(baseline_dt), collapse = ", "), "\n")

check_share_constraint <- function(dt, col, label, enforce_sum_constraint = TRUE) {
  vals <- dt[[col]]
  vals <- vals[is.finite(vals) & !is.na(vals)]
  if (!length(vals)) {
    cat(sprintf("  %s: no non-missing values\n", label))
    return(invisible(NULL))
  }

  cat(sprintf(
    "  %s: mean=%.6f, sd=%.6f, min=%.6f, max=%.6f\n",
    label, mean(vals), sd(vals), min(vals), max(vals)
  ))

  if (!isTRUE(enforce_sum_constraint)) {
    return(invisible(NULL))
  }

  share_sums <- dt[, .(sum_w = sum(get(col), na.rm = TRUE)), by = c(group_keys, SCOL)]
  n_violate <- sum(share_sums$sum_w > 1 + 1e-10, na.rm = TRUE)
  cat(sprintf("    sum_p %s <= 1 check: %d violations out of %d cells\n",
              col, n_violate, nrow(share_sums)))
  if (n_violate > 0L) {
    cat("    WARNING: Some muni-sector cells have party weights summing to > 1\n")
    print(head(share_sums[sum_w > 1 + 1e-10], 5))
  }
  invisible(NULL)
}

check_share_constraint(baseline_dt, "w_rjp_0", "Owner-count baseline")
check_share_constraint(baseline_dt, "w_rjp_emp_0", "Employment baseline")
check_share_constraint(baseline_dt, "w_rjp_firm_0", "Equal-firm baseline")
check_share_constraint(
  baseline_dt,
  "w_rjp_binary_0",
  "Binary baseline",
  enforce_sum_constraint = FALSE
)

# --- Step 5: Save ------------------------------------------------------------

cat("\nStep 5: Saving...\n")

qs_save(baseline_dt, out_path)

summ <- baseline_dt[, .(
  n_rows = .N,
  n_munis = uniqueN(muni_id),
  n_sectors = uniqueN(get(SCOL)),
  n_parties = uniqueN(party),
  baseline_yrs = baseline_years_used[1],
  mean_L_rjp_0 = mean(L_rjp_0, na.rm = TRUE),
  mean_L_r_0 = mean(L_r_0, na.rm = TRUE),
  mean_w_rjp_0 = mean(w_rjp_0, na.rm = TRUE),
  mean_w_rjp_emp_0 = mean(w_rjp_emp_0, na.rm = TRUE),
  mean_w_rjp_firm_0 = mean(w_rjp_firm_0, na.rm = TRUE),
  mean_w_rjp_binary_0 = mean(w_rjp_binary_0, na.rm = TRUE)
), by = .(baseline_type, tier, treatment_year)]

fwrite(summ, summary_path)

cat(sprintf("  Saved %s (%.2f MB)\n", out_path, file.size(out_path) / 1024^2))
cat(sprintf("  Saved %s\n", summary_path))

cat("\nBaseline weight selection complete.\n")
