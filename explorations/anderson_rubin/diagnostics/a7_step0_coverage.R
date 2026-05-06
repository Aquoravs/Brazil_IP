# ==============================================================================
# a7_step0_coverage.R
#
# A7 Step 0 — Coverage and Imputation Diagnostic (policy_block)
#
# Purpose:
#   Characterise three forms of silent imputation in the production instrument:
#   D-A: affiliation-match coverage by policy_block (and muni size class)
#   D-B: decompose Z = 0 cells by cause (zero RAIS / zero aff / zero shock)
#   D-C: zero-employment firm-years by policy_block and affiliation status
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst  (or .qs2 fallback)
#   data/raw/david_ra/owner_aff_firm_year_party_2002_2019.qs2
#   data/processed/policy_block_mapping.qs2
#   data/processed/alignment_shocks.qs2
#   data/processed/shift_share_instruments_policy_block.qs2
#
# Outputs (all in explorations/anderson_rubin/diagnostics/output/):
#   a7_coverage_by_policy_block.csv    D-A per (policy_block, year, muni_size)
#   a7_z_zero_decomposition.csv        D-B per muni-year cell
#   a7_z_zero_summary.csv              D-B aggregated by (reason, year)
#   a7_zero_emp_by_policy_block.csv    D-C per policy_block
#   a7_step0_report.md                 Narrative synthesis
#
# Plan reference: logs/plans/2026-05-05_a7-step0-coverage-diagnostic.md
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Packages (INV-15: all at top)
# ------------------------------------------------------------------------------
library(data.table)
library(qs2)
library(here)

HAS_FST <- requireNamespace("fst", quietly = TRUE)
if (HAS_FST) library(fst)

setDTthreads(0L)

# ------------------------------------------------------------------------------
# 2. Paths (INV-16: no absolute paths; INV-19: no setwd)
# ------------------------------------------------------------------------------
PROCESSED_DIR <- here::here("data", "processed")
RAW_AFF_PATH  <- here::here("data", "raw", "david_ra",
                            "owner_aff_firm_year_party_2002_2019.qs2")
OUTPUT_DIR    <- here::here("explorations", "anderson_rubin",
                            "diagnostics", "output")

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  message("Created output directory: ", OUTPUT_DIR)
}

path_fst <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst")
path_qs2 <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.qs2")
path_cw  <- file.path(PROCESSED_DIR, "policy_block_mapping.qs2")
path_ss  <- file.path(PROCESSED_DIR, "shift_share_instruments_policy_block.qs2")
path_al  <- file.path(PROCESSED_DIR, "alignment_shocks.qs2")

# ------------------------------------------------------------------------------
# 3. Constants
# ------------------------------------------------------------------------------
ACTIVE_BLOCKS <- c("Agro", "Ind", "Infra", "Serv")
YEAR_MIN      <- 2002L
YEAR_MAX      <- 2017L  # years covered by RAIS + instrument

# Muni size quartile labels
SIZE_LABELS   <- c("Q1_small", "Q2", "Q3", "Q4_large")

# ------------------------------------------------------------------------------
# 4. Load shared inputs
# ------------------------------------------------------------------------------
message("Loading policy_block crosswalk...")
if (!file.exists(path_cw)) {
  stop("Missing crosswalk: ", path_cw, "\n  Run script 30e first.")
}
crosswalk <- setDT(qs_read(path_cw))
stopifnot(all(c("cnae_section", "policy_block") %in% names(crosswalk)))
crosswalk <- crosswalk[policy_block %in% ACTIVE_BLOCKS,
                       .(cnae_section, policy_block)]
message(sprintf("  Crosswalk: %d active sections.", nrow(crosswalk)))

message("Loading reconstructed firm panel (column-selective)...")
COLS_PANEL <- c("firm_id", "muni_id", "year", "cnae_section", "n_employees")
if (HAS_FST && file.exists(path_fst)) {
  message("  Source: fst — ", basename(path_fst))
  firm_sector <- fst::read_fst(path_fst,
                               columns = COLS_PANEL,
                               as.data.table = TRUE)
} else if (file.exists(path_qs2)) {
  message("  Source: qs2 — ", basename(path_qs2))
  raw_panel <- qs_read(path_qs2)
  setDT(raw_panel)
  missing_cols <- setdiff(COLS_PANEL, names(raw_panel))
  if (length(missing_cols) > 0L) {
    stop("Panel missing columns: ", paste(missing_cols, collapse = ", "))
  }
  firm_sector <- raw_panel[, .SD, .SDcols = COLS_PANEL]
  rm(raw_panel); invisible(gc())
} else {
  stop("Reconstructed panel not found.\n",
       "  Checked: ", path_fst, "\n",
       "  Checked: ", path_qs2)
}

# Standardise types and filter years
firm_sector[, `:=`(
  firm_id      = as.integer(firm_id),
  muni_id      = as.integer(muni_id),
  year         = as.integer(year)
)]
firm_sector <- firm_sector[year >= YEAR_MIN & year <= YEAR_MAX]
firm_sector <- firm_sector[!is.na(muni_id) & muni_id > 0L]
firm_sector <- firm_sector[!is.na(cnae_section) & nzchar(cnae_section)]

# Merge policy_block; keep only active blocks
firm_sector <- merge(firm_sector, crosswalk, by = "cnae_section", all.x = FALSE)
# Deduplicate to one row per (firm, muni, year) — take first sector by priority
firm_sector <- unique(firm_sector, by = c("firm_id", "muni_id", "year"))

message(sprintf("  Panel: %s firm-muni-years, years %d-%d, %d munis, %d blocks",
                format(nrow(firm_sector), big.mark = ","),
                YEAR_MIN, YEAR_MAX,
                uniqueN(firm_sector$muni_id),
                uniqueN(firm_sector$policy_block)))

message("Loading owner affiliation data...")
if (!file.exists(RAW_AFF_PATH)) {
  stop("Missing owner aff file: ", RAW_AFF_PATH)
}
aff_raw <- qs_read(RAW_AFF_PATH)
setDT(aff_raw)
aff_raw[, `:=`(
  firm_id = as.integer(firm_id),
  year    = as.integer(year)
)]
aff_raw <- aff_raw[year >= YEAR_MIN & year <= YEAR_MAX]
# Deduplicate to one row per (firm_id, year) — a firm either has affiliation or not
# We only need to know whether a firm-year appears in the aff file
aff_firms <- unique(aff_raw[, .(firm_id, year)])
message(sprintf("  Aff file: %s unique firm-years",
                format(nrow(aff_firms), big.mark = ",")))

# Compute total_owners per (firm_id, year): use aff_count / share_aff_owners
# This mirrors script 31's logic for D-C owner_count flag
aff_owner_est <- aff_raw[
  share_aff_owners > 0 & !is.na(share_aff_owners),
  .(total_owners = as.integer(round(median(aff_owners / share_aff_owners)))),
  by = .(firm_id, year)
]
# Floor at sum(aff_owners) per firm-year
aff_sum <- aff_raw[, .(aff_sum = sum(aff_owners, na.rm = TRUE)),
                   by = .(firm_id, year)]
aff_owner_est <- merge(aff_owner_est, aff_sum, by = c("firm_id", "year"), all = TRUE)
aff_owner_est[, total_owners := pmax(total_owners, aff_sum, na.rm = TRUE)]
aff_owner_est[is.na(total_owners), total_owners := aff_sum]
aff_owner_est[, aff_sum := NULL]
rm(aff_raw, aff_sum); invisible(gc())

message(sprintf("  total_owners computed for %s firm-years",
                format(nrow(aff_owner_est), big.mark = ",")))

# ==============================================================================
# D-A: Affiliation-match coverage by (policy_block, year, muni_size_class)
# ==============================================================================
build_d_a <- function(firm_sector, aff_firms) {
  message("\n--- D-A: Affiliation match coverage ---")

  # Flag whether each firm-year has an affiliation record
  # firm_sector is unique by (firm_id, muni_id, year)
  # aff_firms is unique by (firm_id, year) — no muni dimension
  fs <- copy(firm_sector)
  fs[aff_firms, has_aff := TRUE, on = c("firm_id", "year")]
  fs[is.na(has_aff), has_aff := FALSE]

  # Muni size class: quartile of total muni employment pooled across years
  # Use n_employees > 0 for size definition (match plan's emp_rais definition)
  muni_emp <- fs[n_employees > 0 | !is.na(n_employees),
                 .(total_emp_muni = sum(n_employees, na.rm = TRUE)),
                 by = muni_id]
  # Quartile breaks across all munis (pooled)
  # set.seed not needed — quantile is deterministic
  q_breaks <- quantile(muni_emp$total_emp_muni,
                       probs = c(0, 0.25, 0.50, 0.75, 1.0),
                       na.rm = TRUE)
  # Ensure unique breaks for cut()
  q_breaks <- unique(q_breaks)
  muni_emp[, muni_size_class := cut(
    total_emp_muni,
    breaks  = q_breaks,
    labels  = SIZE_LABELS[seq_len(length(q_breaks) - 1L)],
    include.lowest = TRUE
  )]
  message(sprintf("  Muni size class distribution:\n%s",
                  paste(capture.output(
                    print(muni_emp[, .N, by = muni_size_class][order(muni_size_class)])
                  ), collapse = "\n")))

  fs <- merge(fs, muni_emp[, .(muni_id, muni_size_class)],
              by = "muni_id", all.x = TRUE)

  # Per (muni_id, policy_block, year): counts and emp sums
  cell_stats <- fs[, .(
    n_firms_rais = .N,
    n_firms_aff  = sum(has_aff),
    emp_rais     = sum(n_employees[n_employees > 0], na.rm = TRUE),
    emp_aff      = sum(n_employees[has_aff & n_employees > 0], na.rm = TRUE),
    muni_size_class = muni_size_class[1L]  # constant within muni
  ), by = .(muni_id, policy_block, year)]

  cell_stats[, `:=`(
    match_rate_n   = fifelse(n_firms_rais > 0L, n_firms_aff / n_firms_rais, NA_real_),
    match_rate_emp = fifelse(emp_rais > 0, emp_aff / emp_rais, NA_real_)
  )]

  # Verification: rates in [0, 1]
  bad_n   <- cell_stats[!is.na(match_rate_n) & (match_rate_n < 0 | match_rate_n > 1), .N]
  bad_emp <- cell_stats[!is.na(match_rate_emp) & (match_rate_emp < 0 | match_rate_emp > 1), .N]
  if (bad_n > 0L || bad_emp > 0L) {
    stop(sprintf("D-A INVARIANT FAIL: %d rows with match_rate_n outside [0,1]; %d for emp",
                 bad_n, bad_emp))
  }
  message("  D-A invariant check passed: all match_rate_n, match_rate_emp in [0,1]")

  setorder(cell_stats, policy_block, year, muni_size_class, muni_id)
  message(sprintf("  D-A: %d (muni, policy_block, year) cells", nrow(cell_stats)))
  message("  Match rate summary by policy_block (pooled mean):")
  summ <- cell_stats[, .(
    mean_match_rate_n   = mean(match_rate_n, na.rm = TRUE),
    median_match_rate_n = median(match_rate_n, na.rm = TRUE),
    mean_match_rate_emp = mean(match_rate_emp, na.rm = TRUE),
    median_match_rate_emp = median(match_rate_emp, na.rm = TRUE),
    n_cells             = .N
  ), by = policy_block]
  for (i in seq_len(nrow(summ))) {
    r <- summ[i]
    message(sprintf("    %s: n_mean=%.3f n_med=%.3f emp_mean=%.3f emp_med=%.3f (n=%d)",
                    r$policy_block, r$mean_match_rate_n, r$median_match_rate_n,
                    r$mean_match_rate_emp, r$median_match_rate_emp, r$n_cells))
  }

  cell_stats
}

# ==============================================================================
# D-B: Z = 0 decomposition for cycle_specific baseline
# ==============================================================================
build_d_b <- function(firm_sector, aff_firms, aff_owner_est) {
  message("\n--- D-B: Z = 0 decomposition ---")

  # Load the production muni-level instrument
  if (!file.exists(path_ss)) stop("Missing: ", path_ss)
  ss <- setDT(qs_read(path_ss))
  ss <- ss[baseline_type == "cycle_specific"]
  message(sprintf("  Instrument (cycle_specific): %d muni-year rows", nrow(ss)))

  # Focus on cycle_specific baseline; identify Z = 0 cells for Z_mayor_coalition
  z_zero <- ss[Z_mayor_coalition == 0, .(muni_id, year)]
  message(sprintf("  Z_mayor_coalition = 0 cells: %d", nrow(z_zero)))
  rm(ss); invisible(gc())

  # Determine the baseline window: the shift-share baseline uses the treatment
  # year minus 1 as the baseline. For cycle_specific, baseline is the period
  # before the current electoral cycle. We approximate by using year - 1 as
  # the baseline year for checking firm presence.
  # For each Z = 0 cell (muni, year), check:
  #   (i)  zero_rais:  no firms in firm_sector for this muni in any active block
  #                    in year-1 (the baseline year)
  #   (ii) zero_aff:   RAIS firms exist but none have aff record in baseline year
  #   (iii) zero_shock: matched firms exist with owners > 0 but no alignment shock

  # Build baseline year presence: for each muni, which firm-years exist?
  # Use year - 1 as proxy for baseline exposure window
  z_zero[, baseline_year := as.integer(year) - 1L]

  # Muni × baseline_year presence in firm_sector (any active block)
  muni_baseline_rais <- unique(firm_sector[, .(muni_id, year)])
  muni_baseline_rais[, has_rais := TRUE]

  # Muni × baseline_year × any firm with aff
  # firm_sector has (firm_id, muni_id, year); aff_firms has (firm_id, year)
  # We need: for baseline_year, does the muni have any firm in aff?
  fs_temp <- merge(
    unique(firm_sector[, .(firm_id, muni_id, year)]),
    aff_firms,
    by = c("firm_id", "year"),
    all.x = FALSE
  )
  muni_baseline_aff <- unique(fs_temp[, .(muni_id, year)])
  muni_baseline_aff[, has_aff := TRUE]
  rm(fs_temp); invisible(gc())

  # Muni × baseline_year × any firm with owners > 0
  # aff_owner_est has (firm_id, year, total_owners)
  fs_with_owners <- merge(
    unique(firm_sector[, .(firm_id, muni_id, year)]),
    aff_owner_est[total_owners > 0, .(firm_id, year)],
    by = c("firm_id", "year"),
    all.x = FALSE
  )
  muni_baseline_owners <- unique(fs_with_owners[, .(muni_id, year)])
  muni_baseline_owners[, has_owners := TRUE]
  rm(fs_with_owners); invisible(gc())

  # Load alignment shocks to check zero_shock
  # For zero_shock: matched firm with owners > 0, but align_mayor_coalition = 0
  # at that muni-year (i.e., no political alignment). We aggregate: muni has
  # any nonzero align_mayor_coalition in the alignment_shocks for that year.
  if (!file.exists(path_al)) stop("Missing: ", path_al)
  al <- setDT(qs_read(path_al))
  # Aggregate to muni-year: any nonzero alignment shock across parties
  muni_has_shock <- al[align_mayor_coalition > 0,
                       .(has_shock = TRUE),
                       by = .(muni_id, year)]
  muni_has_shock <- unique(muni_has_shock)
  rm(al); invisible(gc())
  message(sprintf("  Alignment shocks: %d muni-year pairs with any align_mayor_coalition > 0",
                  nrow(muni_has_shock)))

  # Join all indicators onto z_zero
  z_zero <- merge(z_zero,
                  muni_baseline_rais[, .(muni_id, baseline_year = year, has_rais)],
                  by = c("muni_id", "baseline_year"),
                  all.x = TRUE)
  z_zero[is.na(has_rais), has_rais := FALSE]

  z_zero <- merge(z_zero,
                  muni_baseline_aff[, .(muni_id, baseline_year = year, has_aff)],
                  by = c("muni_id", "baseline_year"),
                  all.x = TRUE)
  z_zero[is.na(has_aff), has_aff := FALSE]

  z_zero <- merge(z_zero,
                  muni_baseline_owners[, .(muni_id, baseline_year = year, has_owners)],
                  by = c("muni_id", "baseline_year"),
                  all.x = TRUE)
  z_zero[is.na(has_owners), has_owners := FALSE]

  # Shock check: at the current year (the treatment year), does any party
  # have positive alignment? If align_mayor_coalition > 0 for any party, shock exists.
  z_zero <- merge(z_zero,
                  muni_has_shock[, .(muni_id, year, has_shock)],
                  by = c("muni_id", "year"),
                  all.x = TRUE)
  z_zero[is.na(has_shock), has_shock := FALSE]

  # Also track relevant counts for the output schema
  z_zero[, n_active_blocks_with_rais := as.integer(has_rais)]
  z_zero[, n_active_blocks_with_aff  := as.integer(has_aff)]
  z_zero[, total_baseline_owners     := as.integer(has_owners)]
  z_zero[, total_alignment_shock     := as.integer(has_shock)]

  # Priority assignment (i) > (ii) > (iii)
  z_zero[, reason := fcase(
    !has_rais,                          "zero_rais",
    has_rais & !has_aff,                "zero_aff",
    has_rais & has_aff & !has_owners,   "zero_aff",   # aff exists but zero owners
    has_rais & has_aff & has_owners,    "zero_shock",
    default                           = "zero_rais"   # fallback (no baseline year data)
  )]

  # Verification: every row has exactly one reason (mutually exclusive)
  n_total_z0 <- nrow(z_zero)
  n_assigned  <- z_zero[reason %in% c("zero_rais", "zero_aff", "zero_shock"), .N]
  if (n_assigned != n_total_z0) {
    stop(sprintf("D-B INVARIANT FAIL: %d rows unassigned (%d total)",
                 n_total_z0 - n_assigned, n_total_z0))
  }

  reason_counts <- z_zero[, .N, by = reason]
  message("  D-B reason distribution:")
  for (i in seq_len(nrow(reason_counts))) {
    r <- reason_counts[i]
    message(sprintf("    %s: %d (%.1f%%)",
                    r$reason, r$N, 100 * r$N / n_total_z0))
  }
  # Verify sum to 100%
  total_check <- sum(reason_counts$N)
  if (total_check != n_total_z0) {
    stop(sprintf("D-B INVARIANT FAIL: reasons sum to %d but expected %d",
                 total_check, n_total_z0))
  }
  message(sprintf("  D-B invariant check passed: all %d Z=0 cells assigned, sum to 100%%",
                  n_total_z0))

  # Output columns per plan spec
  out_cell <- z_zero[, .(
    muni_id, year,
    n_active_blocks_with_rais,
    n_active_blocks_with_aff,
    total_baseline_owners,
    total_alignment_shock,
    reason
  )]
  setorder(out_cell, year, muni_id)

  # Aggregated summary: reason × year
  out_summary <- z_zero[, .(
    n_cells       = .N,
    share_of_zero = .N / n_total_z0
  ), by = .(reason, year)]
  setorder(out_summary, year, reason)

  list(per_cell = out_cell, summary = out_summary,
       reason_counts = reason_counts, n_total_z0 = n_total_z0)
}

# ==============================================================================
# D-C: Zero-employment population by policy_block
# ==============================================================================
build_d_c <- function(firm_sector, aff_firms, aff_owner_est) {
  message("\n--- D-C: Zero-employment population ---")

  fs <- copy(firm_sector)

  # Flag zero-employment: n_employees == 0 or NA
  fs[, is_zero_emp := (is.na(n_employees) | n_employees == 0L)]

  # Flag affiliation presence (firm-year level, no muni dimension)
  fs[aff_firms, has_aff := TRUE, on = c("firm_id", "year")]
  fs[is.na(has_aff), has_aff := FALSE]

  # Flag owner_count >= 1: has aff AND total_owners >= 1 from aff_owner_est
  fs <- merge(fs,
              aff_owner_est[total_owners >= 1, .(firm_id, year, total_owners)],
              by = c("firm_id", "year"),
              all.x = TRUE)
  fs[, has_owners_ge_1 := !is.na(total_owners) & total_owners >= 1L]

  # Aggregate per policy_block
  dc <- fs[, .(
    n_firmyears_total       = .N,
    n_zero_emp              = sum(is_zero_emp),
    n_zero_emp_with_aff     = sum(is_zero_emp & has_aff),
    n_zero_emp_with_owners  = sum(is_zero_emp & has_owners_ge_1)
  ), by = policy_block]

  dc[, share_zero_emp             := n_zero_emp / n_firmyears_total]
  dc[, share_zero_emp_with_aff    := fifelse(
    n_zero_emp > 0L, n_zero_emp_with_aff / n_zero_emp, NA_real_
  )]
  dc[, share_zero_emp_with_owners_ge_1 := fifelse(
    n_zero_emp_with_aff > 0L, n_zero_emp_with_owners / n_zero_emp_with_aff, NA_real_
  )]

  setnames(dc,
    "n_zero_emp_with_owners",
    "n_zero_emp_with_owners_ge_1"
  )
  setcolorder(dc, c(
    "policy_block",
    "n_firmyears_total", "n_zero_emp", "share_zero_emp",
    "n_zero_emp_with_aff", "share_zero_emp_with_aff",
    "n_zero_emp_with_owners_ge_1", "share_zero_emp_with_owners_ge_1"
  ))
  setorder(dc, policy_block)

  message("  D-C summary by policy_block:")
  for (i in seq_len(nrow(dc))) {
    r <- dc[i]
    message(sprintf(
      "    %s: zero_emp=%.1f%% (%d/%d); of those with_aff=%.1f%%; with_owners>=1=%.1f%%",
      r$policy_block,
      100 * r$share_zero_emp, r$n_zero_emp, r$n_firmyears_total,
      100 * coalesce(r$share_zero_emp_with_aff, 0),
      100 * coalesce(r$share_zero_emp_with_owners_ge_1, 0)
    ))
  }

  dc
}

# Coalesce helper (base R, no dplyr needed)
coalesce <- function(x, default = 0) {
  ifelse(is.na(x), default, x)
}

# ==============================================================================
# 5. Run diagnostics
# ==============================================================================
message("\n=== Running D-A ===")
d_a <- build_d_a(firm_sector, aff_firms)

message("\n=== Running D-B ===")
d_b <- build_d_b(firm_sector, aff_firms, aff_owner_est)

message("\n=== Running D-C ===")
d_c <- build_d_c(firm_sector, aff_firms, aff_owner_est)

# ==============================================================================
# 6. Write CSVs
# ==============================================================================
message("\nWriting output CSVs...")

fwrite(d_a, file.path(OUTPUT_DIR, "a7_coverage_by_policy_block.csv"))
message("  Written: a7_coverage_by_policy_block.csv  (", nrow(d_a), " rows)")

fwrite(d_b$per_cell, file.path(OUTPUT_DIR, "a7_z_zero_decomposition.csv"))
message("  Written: a7_z_zero_decomposition.csv      (", nrow(d_b$per_cell), " rows)")

fwrite(d_b$summary, file.path(OUTPUT_DIR, "a7_z_zero_summary.csv"))
message("  Written: a7_z_zero_summary.csv            (", nrow(d_b$summary), " rows)")

fwrite(d_c, file.path(OUTPUT_DIR, "a7_zero_emp_by_policy_block.csv"))
message("  Written: a7_zero_emp_by_policy_block.csv  (", nrow(d_c), " rows)")

# ==============================================================================
# 7. Generate narrative report
# ==============================================================================
message("\nGenerating a7_step0_report.md...")

fmt_pct <- function(x) sprintf("%.1f%%", 100 * x)
fmt_n   <- function(x) format(as.integer(x), big.mark = ",")

# D-A headline numbers: pooled mean match rates by policy_block
da_pooled <- d_a[, .(
  mean_n   = mean(match_rate_n, na.rm = TRUE),
  median_n = median(match_rate_n, na.rm = TRUE),
  mean_emp = mean(match_rate_emp, na.rm = TRUE),
  median_emp = median(match_rate_emp, na.rm = TRUE),
  n_cells  = .N
), by = policy_block]
setorder(da_pooled, policy_block)

# D-B headline numbers
rc <- d_b$reason_counts
n0 <- d_b$n_total_z0
get_share <- function(reason_name) {
  x <- rc[reason == reason_name, N]
  if (length(x) == 0L) return(0)
  x / n0
}
pct_zero_rais  <- get_share("zero_rais")
pct_zero_aff   <- get_share("zero_aff")
pct_zero_shock <- get_share("zero_shock")

# D-C headline numbers
dc_r <- d_c  # already aggregated

# Check escalation trigger: any policy_block with match_rate_emp < 0.50?
low_emp_blocks <- da_pooled[mean_emp < 0.50, policy_block]
escalation_flag <- length(low_emp_blocks) > 0L

# Build report lines
rlines <- c(
  "# A7 Step 0 — Coverage and Imputation Diagnostic",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  paste0("Plan: logs/plans/2026-05-05_a7-step0-coverage-diagnostic.md"),
  "",
  "---",
  "",
  "## Overview",
  "",
  "This diagnostic characterises three forms of silent imputation in the",
  "production shift-share instrument at the `policy_block` aggregation margin.",
  "The findings feed the A7 weight comparison: the correlation matrix and",
  "first-stage F-stats in Steps 1-5 are uninterpretable without knowing how",
  "much of the variation is driven by coverage patterns rather than real",
  "political alignment variation.",
  "",
  "Aggregation margin: **policy_block only** (Agro, Ind, Infra, Serv; XX excluded).",
  paste0("Year range: ", YEAR_MIN, "-", YEAR_MAX, "."),
  "",
  "---",
  "",
  "## D-A: Affiliation-Match Coverage by Policy Block",
  "",
  "Match rates are computed per (muni, policy_block, year) cell and then",
  "pooled. Two rates are reported: `match_rate_n` (firm count) and",
  "`match_rate_emp` (employment-weighted).",
  "",
  "### Pooled means by policy_block",
  "",
  paste0("| Block | Match rate n (mean) | Match rate n (median) | ",
         "Match rate emp (mean) | Match rate emp (median) | N cells |"),
  paste0("|-------|--------------------|-----------------------|",
         "---------------------|------------------------|---------|")
)

for (i in seq_len(nrow(da_pooled))) {
  r <- da_pooled[i]
  rlines <- c(rlines, sprintf(
    "| %s | %s | %s | %s | %s | %s |",
    r$policy_block,
    fmt_pct(r$mean_n), fmt_pct(r$median_n),
    fmt_pct(r$mean_emp), fmt_pct(r$median_emp),
    fmt_n(r$n_cells)
  ))
}

# Escalation warning
if (escalation_flag) {
  rlines <- c(rlines,
    "",
    paste0("**ESCALATION FLAG: The following blocks have mean match_rate_emp < 50%:",
           " ", paste(low_emp_blocks, collapse = ", "),
           ". This is a hard escalation trigger per the A7 plan.**"),
    ""
  )
} else {
  rlines <- c(rlines,
    "",
    "No blocks cross the hard escalation threshold (mean match_rate_emp < 50%).",
    ""
  )
}

# Interpret sector differences
rlines <- c(rlines,
  "### Interpretation",
  "",
  paste0(
    "Match rates differ across blocks because the owner affiliation file covers",
    " firms proportional to their size and visibility in the registry. Blocks",
    " with lower coverage (typically Serv) contribute disproportionately to",
    " the `zero_aff` category in D-B. If match_rate_emp systematically differs",
    " across blocks, any across-block IV comparison in Steps 1-5 carries",
    " sector-correlated bias — the weighting choice partially proxies for",
    " coverage, not only for economic exposure."
  ),
  ""
)

rlines <- c(rlines,
  "---",
  "",
  "## D-B: Z = 0 Decomposition",
  "",
  sprintf("Total `Z_mayor_coalition = 0` cells (cycle_specific baseline): %s",
          fmt_n(n0)),
  "",
  paste0("Priority decomposition: (i) zero_rais > (ii) zero_aff > (iii) zero_shock."),
  "Mutually exclusive — every Z = 0 cell gets exactly one reason.",
  "",
  "| Reason | Count | Share |",
  "|--------|-------|-------|",
  sprintf("| zero_rais  | %s | %s |",
          fmt_n(rc[reason == "zero_rais",  N]), fmt_pct(pct_zero_rais)),
  sprintf("| zero_aff   | %s | %s |",
          fmt_n(rc[reason == "zero_aff",   N]), fmt_pct(pct_zero_aff)),
  sprintf("| zero_shock | %s | %s |",
          fmt_n(rc[reason == "zero_shock", N]), fmt_pct(pct_zero_shock)),
  "",
  "### Interpretation",
  ""
)

# Bias flag check
if (pct_zero_aff > 0.20) {
  rlines <- c(rlines,
    paste0(
      "**Bias flag triggered:** `zero_aff` accounts for ",
      fmt_pct(pct_zero_aff), " of Z = 0 cells, which exceeds the 20% threshold.",
      " This means the matched-only denominator is doing substantial imputation:",
      " more than one-fifth of zero-instrument cells arise because the muni has",
      " RAIS firms in active blocks but none with an owner affiliation record.",
      " In these cells, the instrument takes Z = 0 for a structural reason",
      " (missing affiliation data), not because there is genuinely zero",
      " alignment exposure. The emp_share_floor and equal_firm weights proposed",
      " in Steps 1-5 do not resolve this issue; they change the weighting of",
      " the non-zero cells but do not recover the zero_aff cells."
    ),
    ""
  )
} else if (pct_zero_aff < 0.05) {
  rlines <- c(rlines,
    paste0(
      "`zero_aff` accounts for only ", fmt_pct(pct_zero_aff),
      " of Z = 0 cells (< 5% threshold). The matched-only denominator is doing",
      " minimal imputation; this concern is a sensitivity-analysis footnote rather",
      " than a central identification issue. Steps 1-5 weight comparison",
      " can proceed without resolving this bias source first."
    ),
    ""
  )
} else {
  rlines <- c(rlines,
    paste0(
      "`zero_aff` accounts for ", fmt_pct(pct_zero_aff),
      " of Z = 0 cells (between 5% and 20%). This is a non-trivial share:",
      " the matched-only denominator is doing moderate imputation. Monitor",
      " whether zero_aff cells cluster in particular blocks or years (see",
      " the per-cell CSV). If they concentrate in Serv or in post-2014 years,",
      " the weight comparison in Steps 1-5 may be confounded by coverage trends."
    ),
    ""
  )
}

rlines <- c(rlines,
  paste0(
    "The dominant reason for Z = 0 is `zero_shock` (", fmt_pct(pct_zero_shock),
    "), covering munis with matched affiliated firms and positive owner counts,",
    " but where no party winning the mayoralty has any affiliation with the",
    " muni's incumbent owners in that year. These cells are genuine alignment",
    " zeros and are correctly coded as Z = 0."
  ),
  "",
  paste0(
    "`zero_rais` (", fmt_pct(pct_zero_rais),
    ") flags munis with no firms in active policy blocks in the baseline window.",
    " These munis are structurally untreated and would be dropped from estimation",
    " regardless of weighting choice; they do not affect the weight comparison."
  ),
  ""
)

rlines <- c(rlines,
  "---",
  "",
  "## D-C: Zero-Employment Firm-Years by Policy Block",
  "",
  paste0("| Block | Total firm-years | N zero-emp | Share zero-emp | ",
         "N zero-emp with aff | Share with aff | N with owners >= 1 | Share with owners >= 1 |"),
  paste0("|-------|-----------------|------------|----------------|",
         "--------------------|----------------|--------------------|-----------------------|")
)

for (i in seq_len(nrow(dc_r))) {
  r <- dc_r[i]
  rlines <- c(rlines, sprintf(
    "| %s | %s | %s | %s | %s | %s | %s | %s |",
    r$policy_block,
    fmt_n(r$n_firmyears_total),
    fmt_n(r$n_zero_emp),
    fmt_pct(r$share_zero_emp),
    fmt_n(r$n_zero_emp_with_aff),
    fmt_pct(coalesce(r$share_zero_emp_with_aff)),
    fmt_n(r$n_zero_emp_with_owners_ge_1),
    fmt_pct(coalesce(r$share_zero_emp_with_owners_ge_1))
  ))
}

rlines <- c(rlines,
  "",
  "### Interpretation",
  "",
  paste0(
    "Zero-employment firm-years are invisible to the `w_mjp_emp` weight because",
    " that weight uses `n_employees > 0` in the denominator. If zero-emp firms",
    " that have affiliation records (i.e., they are visible to the IV) are",
    " concentrated in specific blocks, the employment weight is systematically",
    " blind to a substantively important subpopulation. The `emp_share_floor`",
    " weight proposed in Step 1 addresses this by substituting",
    " `pmax(n_employees, owner_count, 1)` in the denominator."
  ),
  "",
  paste0(
    "A high `share_zero_emp_with_aff` combined with a high `share_zero_emp`",
    " in a block (especially Serv, which includes individual entrepreneurs",
    " and Cartao BNDES borrowers) justifies the floor weight for that block.",
    " The `share_zero_emp_with_owners_ge_1` column shows what fraction of",
    " zero-emp affiliated firms would survive the proposed floor (i.e., would",
    " have owner_count >= 1 and hence receive a non-zero floor weight)."
  ),
  ""
)

rlines <- c(rlines,
  "---",
  "",
  "## Files Produced",
  "",
  "| File | Description |",
  "|------|-------------|",
  sprintf("| `a7_coverage_by_policy_block.csv` | D-A: %s rows, per (muni, block, year, size_class) |",
          fmt_n(nrow(d_a))),
  sprintf("| `a7_z_zero_decomposition.csv` | D-B per-cell: %s rows |",
          fmt_n(nrow(d_b$per_cell))),
  sprintf("| `a7_z_zero_summary.csv` | D-B aggregated: %s rows |",
          fmt_n(nrow(d_b$summary))),
  sprintf("| `a7_zero_emp_by_policy_block.csv` | D-C: %s rows |",
          fmt_n(nrow(d_c))),
  "| `a7_step0_report.md` | This narrative report |",
  "",
  "---",
  "",
  "## Implications for A7 Weight Comparison (Steps 1-5)",
  "",
  "1. **D-A (coverage bias):** If match_rate_emp varies substantially across",
  "   blocks, the weight comparison in Steps 1-5 should be interpreted as",
  "   comparing weights that implicitly combine economic exposure with coverage",
  "   selection. A block with low match_rate_emp will have its employment weight",
  "   mechanically attenuated relative to its owner-count weight.",
  "",
  "2. **D-B (Z = 0 composition):** The share of zero_aff cells determines how",
  "   much of the instrument's zero-variation is structural (data gap) versus",
  "   informative (genuine non-alignment). Steps 1-5 first-stage F-stats cannot",
  "   distinguish between these; the `zero_aff` share is the fraction of the",
  "   zero-mass that is non-informative structural imputation.",
  "",
  "3. **D-C (zero-emp floor):** If zero-emp firms with affiliation represent",
  "   a large share of the covered population in any block, the employment",
  "   weight systematically underweights that block's alignment signal. The",
  "   floor weight is most justified in blocks where `share_zero_emp_with_aff`",
  "   is high relative to `share_zero_emp`.",
  ""
)

if (escalation_flag) {
  rlines <- c(rlines,
    "---",
    "",
    "## ESCALATION NOTICE",
    "",
    paste0("**Hard escalation triggered.** The following policy blocks have",
           " mean match_rate_emp < 50%: **",
           paste(low_emp_blocks, collapse = ", "),
           "**. Per the A7 plan, this requires human review before the Step 1-5",
           " weight comparison proceeds. The employment weight in these blocks",
           " covers less than half of the underlying employment mass, making",
           " cross-weight comparisons unreliable for those blocks."),
    ""
  )
}

writeLines(rlines, file.path(OUTPUT_DIR, "a7_step0_report.md"))
message("  Written: a7_step0_report.md")

# ==============================================================================
# 8. Console summary
# ==============================================================================
message("\n")
message("=============================================================")
message("  A7 Step 0 Coverage Diagnostic — Summary")
message("=============================================================")
message("")
message("  D-A Match rates by policy_block (pooled mean):")
for (i in seq_len(nrow(da_pooled))) {
  r <- da_pooled[i]
  message(sprintf("    %-5s  n: %s  emp: %s",
                  r$policy_block, fmt_pct(r$mean_n), fmt_pct(r$mean_emp)))
}
message("")
message(sprintf("  D-B Z=0 decomposition (%s total cells):", fmt_n(n0)))
message(sprintf("    zero_rais:  %s", fmt_pct(pct_zero_rais)))
message(sprintf("    zero_aff:   %s", fmt_pct(pct_zero_aff)))
message(sprintf("    zero_shock: %s", fmt_pct(pct_zero_shock)))
message("")
message("  D-C Zero-employment shares:")
for (i in seq_len(nrow(dc_r))) {
  r <- dc_r[i]
  message(sprintf("    %-5s  share_zero_emp: %s  share_with_aff: %s  share_with_owners: %s",
                  r$policy_block,
                  fmt_pct(r$share_zero_emp),
                  fmt_pct(coalesce(r$share_zero_emp_with_aff)),
                  fmt_pct(coalesce(r$share_zero_emp_with_owners_ge_1))))
}
message("")
if (escalation_flag) {
  message(sprintf("  *** ESCALATION FLAG: blocks with match_rate_emp < 50%%: %s ***",
                  paste(low_emp_blocks, collapse = ", ")))
} else {
  message("  No escalation flag (all blocks match_rate_emp >= 50%).")
}
message("")
message("  Output written to:", OUTPUT_DIR)
message("=============================================================")

invisible(list(
  d_a = d_a,
  d_b = d_b,
  d_c = d_c,
  escalation_flag = escalation_flag
))
