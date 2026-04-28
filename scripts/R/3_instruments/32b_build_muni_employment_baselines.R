#!/usr/bin/env Rscript

# ==============================================================================
# Build Municipality Pre-Election Employment Baselines  (Script 32b)
# ==============================================================================
# Produces two outputs:
#
# (A) muni_employment_baselines.qs2
#     Keys: (muni_id, election_cycle, office_tier)
#     Column: muni_emp_bl — sum of muni-total n_employees across the office-
#       specific pre-election baseline window.  Used as share denominator in
#       scripts 51 and 52 (regression_weight = emp_share_weighted).
#     One row per (muni_id, election_cycle, office_tier).
#
# (B) muni_employment_classification.qs2
#     (Also produced by script 41; 32b builds a standalone early version.)
#     Keys: (muni_id)  — time-invariant
#     Columns: muni_emp_whole, muni_emp_quartile, top_q4_muni
#     Produced here so downstream scripts can reference the classification
#     even before script 41 has been run.  Script 41 produces the same file
#     as an authoritative side-output of its own build.
#
# Baseline windows (matching script 33 / 30c):
#   Mayor cycles (treatment_year / election_cycle):
#     2005 → 2000–2003   (data starts 2002, so effective 2002–2003)
#     2009 → 2004–2007
#     2013 → 2008–2011
#     2017 → 2012–2015
#   Gov/Pres cycles:
#     2007 → 2002–2005
#     2011 → 2006–2009
#     2015 → 2010–2013
#
# Office tiers: "mayor", "gov_pres"  (separate rows per tier per cycle)
#
# muni_emp_bl is the sum of annual municipality-level n_employees totals
# across the years that fall within the baseline window (intersected with
# available data).  Dividing the firm's bl_n_employees by muni_emp_bl and
# then multiplying by n_window_years recovers the pre-election employment
# share — but for regression weighting only relative magnitudes matter, so
# the raw ratio emp_share_muni_pre = bl_n_employees / muni_emp_bl is used
# directly as the regression weight in script 51/52.
#
# Dependencies: script 22 (rais_bndes_reconstructed.fst/.qs2)
# ==============================================================================

cat("==============================================================================\n")
cat("Building Municipality Pre-Election Employment Baselines (Script 32b)\n")
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

setDTthreads(0)

# --- Configuration ------------------------------------------------------------

out_baselines_path       <- make_output_path("muni_employment_baselines.qs2")
out_classification_path  <- make_output_path("muni_employment_classification.qs2")
summary_baselines_path   <- make_output_path("muni_employment_baselines_summary.csv")
summary_class_path       <- make_output_path("muni_employment_classification_summary.csv")

# Baseline windows — match script 33's baseline_window_map exactly.
# election_cycle = treatment_year from script 33.
BASELINE_WINDOWS <- rbindlist(list(
  data.table(election_cycle = 2005L, bl_start = 2000L, bl_end = 2003L, office_tier = "mayor"),
  data.table(election_cycle = 2009L, bl_start = 2004L, bl_end = 2007L, office_tier = "mayor"),
  data.table(election_cycle = 2013L, bl_start = 2008L, bl_end = 2011L, office_tier = "mayor"),
  data.table(election_cycle = 2017L, bl_start = 2012L, bl_end = 2015L, office_tier = "mayor"),
  data.table(election_cycle = 2007L, bl_start = 2002L, bl_end = 2005L, office_tier = "gov_pres"),
  data.table(election_cycle = 2011L, bl_start = 2006L, bl_end = 2009L, office_tier = "gov_pres"),
  data.table(election_cycle = 2015L, bl_start = 2010L, bl_end = 2013L, office_tier = "gov_pres")
))

# Years used for the whole-period quartile classification (per regs.tex / B.4)
WHOLE_PERIOD_YEARS <- 2002L:2017L

# ==============================================================================
# STEP 1: Load RAIS panel — aggregate to (muni_id, year)
# ==============================================================================

cat("Step 1: Loading RAIS reconstructed panel...\n")

recon_fst_path <- make_output_path("rais_bndes_reconstructed.fst")
recon_qs2_path <- make_output_path("rais_bndes_reconstructed.qs2")

need_cols <- c("muni_id", "year", "n_employees")

if (file.exists(recon_fst_path) && requireNamespace("fst", quietly = TRUE)) {
  avail_cols <- fst::metadata_fst(recon_fst_path)$columnNames
  read_cols  <- intersect(need_cols, avail_cols)
  recon <- fst::read_fst(recon_fst_path, columns = read_cols, as.data.table = TRUE)
  cat(sprintf("  Loaded from fst: %s rows\n", format(nrow(recon), big.mark = ",")))
} else if (file.exists(recon_qs2_path)) {
  raw   <- qs_read(recon_qs2_path)
  setDT(raw)
  read_cols <- intersect(need_cols, names(raw))
  recon <- raw[, ..read_cols]
  rm(raw); invisible(gc())
  cat(sprintf("  Loaded from qs2: %s rows\n", format(nrow(recon), big.mark = ",")))
} else {
  stop("RAIS reconstructed panel not found. Run script 22 first.")
}

# Coerce types
recon[, muni_id     := as.integer(muni_id)]
recon[, year        := as.integer(year)]
recon[, n_employees := as.numeric(n_employees)]

# Drop invalid municipalities (code 0 is not a valid IBGE code)
n_invalid <- sum(is.na(recon$muni_id) | recon$muni_id == 0L)
if (n_invalid > 0L) {
  cat(sprintf("  Dropping %d rows with invalid muni_id\n", n_invalid))
  recon <- recon[!is.na(muni_id) & muni_id > 0L]
}

# Replace NA employment with 0 for aggregation (consistent with script 41)
recon[is.na(n_employees), n_employees := 0]

cat(sprintf("  Year range in data: %d–%d\n",
            min(recon$year, na.rm = TRUE),
            max(recon$year, na.rm = TRUE)))

# Aggregate to (muni_id, year)
cat("\n  Aggregating to muni × year totals...\n")
muni_yr <- recon[, .(
  total_employment = sum(n_employees, na.rm = TRUE)
), by = .(muni_id, year)]

rm(recon); invisible(gc())

cat(sprintf("  Muni-year panel: %s rows, %d municipalities, %d years\n",
            format(nrow(muni_yr), big.mark = ","),
            uniqueN(muni_yr$muni_id),
            uniqueN(muni_yr$year)))

available_years <- sort(unique(muni_yr$year))
cat(sprintf("  Available years: %s\n", paste(available_years, collapse = ", ")))

# ==============================================================================
# STEP 2: Build per-cycle, per-tier muni employment baseline totals
# ==============================================================================

cat("\nStep 2: Building office-specific baseline employment totals...\n")

baseline_list <- vector("list", nrow(BASELINE_WINDOWS))

for (i in seq_len(nrow(BASELINE_WINDOWS))) {
  ec   <- BASELINE_WINDOWS$election_cycle[i]
  bst  <- BASELINE_WINDOWS$bl_start[i]
  ben  <- BASELINE_WINDOWS$bl_end[i]
  tier <- BASELINE_WINDOWS$office_tier[i]

  window_years <- intersect(seq(bst, ben), available_years)

  if (!length(window_years)) {
    cat(sprintf(
      "  WARNING: No data for %s cycle=%d window=%d-%d — skipping\n",
      tier, ec, bst, ben
    ))
    next
  }

  # Sum annual totals across baseline window years per muni_id
  bl_dt <- muni_yr[year %in% window_years, .(
    muni_emp_bl      = sum(total_employment, na.rm = TRUE),
    n_years_used     = .N
  ), by = muni_id]

  bl_dt[, election_cycle := ec]
  bl_dt[, office_tier    := tier]
  bl_dt[, bl_start       := min(window_years)]
  bl_dt[, bl_end         := max(window_years)]

  cat(sprintf(
    "  %s cycle=%d window=%d-%d (used %d yrs: %s): %d munis, mean=%.0f\n",
    tier, ec, bst, ben, length(window_years),
    paste(window_years, collapse = ","),
    nrow(bl_dt),
    mean(bl_dt$muni_emp_bl, na.rm = TRUE)
  ))

  baseline_list[[i]] <- bl_dt
}

baselines <- rbindlist(baseline_list, use.names = TRUE, fill = TRUE)
setorder(baselines, office_tier, election_cycle, muni_id)

n_munis_total <- uniqueN(muni_yr$muni_id)
n_munis_bl    <- uniqueN(baselines$muni_id)
cat(sprintf(
  "\n  Combined: %s rows, %d munis (RAIS total: %d)\n",
  format(nrow(baselines), big.mark = ","), n_munis_bl, n_munis_total
))
if (n_munis_bl < n_munis_total) {
  cat(sprintf(
    "  NOTE: %d munis had no observations in any baseline window\n",
    n_munis_total - n_munis_bl
  ))
}

# Verify no duplicates
dup_check <- baselines[, .N, by = .(muni_id, election_cycle, office_tier)]
n_dups <- sum(dup_check$N > 1L)
if (n_dups > 0L) {
  stop("Duplicate (muni_id, election_cycle, office_tier) rows found: ", n_dups)
}

# ==============================================================================
# STEP 3: Whole-period classification (2002–2017, time-invariant per muni_id)
# ==============================================================================

cat("\nStep 3: Building whole-period quartile classification (2002–2017)...\n")

muni_whole <- muni_yr[year %in% WHOLE_PERIOD_YEARS, .(
  muni_emp_whole = mean(total_employment, na.rm = TRUE),
  n_years_obs    = .N
), by = muni_id]

# Munis with zero or missing employment get muni_emp_whole = 0 → land in Q1
muni_whole[is.na(muni_emp_whole) | !is.finite(muni_emp_whole), muni_emp_whole := 0]

# National quartile classification (unconditional, time-invariant)
# ntile assigns roughly equal-count quartiles; ties broken by order (stable)
muni_whole[, muni_emp_quartile := as.integer(
  cut(muni_emp_whole,
      breaks = quantile(muni_emp_whole, probs = c(0, 0.25, 0.50, 0.75, 1.0),
                        na.rm = TRUE, names = FALSE),
      include.lowest = TRUE,
      labels = FALSE)
)]

# Edge case: all identical values → cut() returns NA; assign Q1
muni_whole[is.na(muni_emp_quartile), muni_emp_quartile := 1L]

muni_whole[, top_q4_muni := as.integer(muni_emp_quartile == 4L)]

cat(sprintf("  Municipalities classified: %d\n", nrow(muni_whole)))
cat(sprintf("  mean muni_emp_whole: %.0f\n", mean(muni_whole$muni_emp_whole)))
cat(sprintf("  Quartile distribution:\n"))
q_dist <- muni_whole[, .N, by = muni_emp_quartile][order(muni_emp_quartile)]
for (k in seq_len(nrow(q_dist))) {
  cat(sprintf(
    "    Q%d: %d munis (%.1f%%)\n",
    q_dist$muni_emp_quartile[k],
    q_dist$N[k],
    100 * q_dist$N[k] / nrow(muni_whole)
  ))
}
cat(sprintf("  top_q4_muni == 1: %d munis\n", sum(muni_whole$top_q4_muni)))

# Verify: Q4 should contain ≈ 25% of munis
q4_pct <- mean(muni_whole$top_q4_muni) * 100
if (abs(q4_pct - 25) > 2) {
  cat(sprintf(
    "  WARNING: Q4 share = %.1f%% (expected ~25%%) — possible tied values\n",
    q4_pct
  ))
}

# ==============================================================================
# STEP 4: Save outputs
# ==============================================================================

cat("\nStep 4: Saving outputs...\n")

# (A) Baselines: keep only the columns needed downstream
out_baselines <- baselines[, .(
  muni_id, election_cycle, office_tier,
  muni_emp_bl, n_years_used, bl_start, bl_end
)]

qs_save(out_baselines, out_baselines_path)
cat(sprintf("  Saved: %s (%.2f MB)\n",
            out_baselines_path, file.size(out_baselines_path) / 1024^2))

# Summary CSV — one row per (election_cycle, office_tier)
summ_bl <- out_baselines[, .(
  n_munis          = .N,
  mean_muni_emp_bl = mean(muni_emp_bl, na.rm = TRUE),
  p25_muni_emp_bl  = quantile(muni_emp_bl, 0.25, na.rm = TRUE),
  p50_muni_emp_bl  = quantile(muni_emp_bl, 0.50, na.rm = TRUE),
  p75_muni_emp_bl  = quantile(muni_emp_bl, 0.75, na.rm = TRUE),
  n_zero_emp       = sum(muni_emp_bl == 0, na.rm = TRUE),
  years_used       = n_years_used[1]
), by = .(office_tier, election_cycle)]
setorder(summ_bl, office_tier, election_cycle)
fwrite(summ_bl, summary_baselines_path)
cat(sprintf("  Saved: %s\n", summary_baselines_path))

# (B) Classification: keep only muni_id + classification columns
out_class <- muni_whole[, .(
  muni_id, muni_emp_whole, muni_emp_quartile, top_q4_muni
)]
setorder(out_class, muni_id)

qs_save(out_class, out_classification_path)
cat(sprintf("  Saved: %s (%.2f MB)\n",
            out_classification_path, file.size(out_classification_path) / 1024^2))

# Classification summary CSV
summ_class <- muni_whole[, .(
  n_munis          = .N,
  mean_emp         = mean(muni_emp_whole, na.rm = TRUE),
  p25_emp          = quantile(muni_emp_whole, 0.25, na.rm = TRUE),
  p50_emp          = quantile(muni_emp_whole, 0.50, na.rm = TRUE),
  p75_emp          = quantile(muni_emp_whole, 0.75, na.rm = TRUE),
  pct_top_q4       = mean(top_q4_muni) * 100
), by = muni_emp_quartile]
setorder(summ_class, muni_emp_quartile)
fwrite(summ_class, summary_class_path)
cat(sprintf("  Saved: %s\n", summary_class_path))

cat("\nMunicipality employment baselines complete.\n")
cat(sprintf("  Baselines:      %s\n", out_baselines_path))
cat(sprintf("  Classification: %s\n", out_classification_path))
cat("==============================================================================\n")
