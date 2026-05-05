# ==============================================================================
# 03b_agro_conditional_f1.R
#
# E3b: Conditional F1 diagnostic for policy_block x Agro x V2.
#
# Why this exists:
#   Round-1 (D15) reports policy_block x Agro x V2 as SUPPORTED in aggregate
#   (share_within = 0.60) but with med_sigma_within = 0 because most munis are
#   urban/service-heavy and have zero Agro BNDES credit in most years. The
#   pattern "Agro varies where it appears" is the correct IV regime, but warrants
#   a positive conditional check: restrict to munis that actually receive Agro
#   credit and re-run the decomposition.
#
# F-link tested: F1 Agro tail diagnostic; complement to D15
#   (docs/PROJECT_BLUEPRINT.md §3, F1 foundation)
#
# Plan reference: logs/plans/2026-05-04_size-bin-diagnostics.md §7 + §0.2
#
# Denominator: V2 only (full-economy denominator; mirrors round-1 spec)
#   V2 denominator = sum of L over ALL 5 policy blocks (Agro, Ind, Infra,
#   Serv, XX) for that (muni, year). Does not drop XX bins from the denominator.
#
# Baseline window: cycle 2009 baseline 2004-2007 (mirrors script 33 and the
#   muni-level baseline used by the production pipeline). Alternative would be
#   per-(muni, cycle) baseline, but we use the single 2009-cycle window for
#   comparability with the production SSIV and simplicity of exposition.
#
# Samples defined:
#   all_munis     - universe of (muni, year) with total BNDES > 0 (= round 1).
#   agro_having   - munis with muni_baseline_agro_share > 0.
#   above_median  - munis with muni_baseline_agro_share > p50 of strictly-pos.
#   above_p25     - stricter cut at p25 of strictly-positive distribution.
#
# Sanity gate:
#   Before writing conditional outputs, reproduce round-1 numbers for
#   policy_block x Agro x V2 on the all_munis sample.
#   Tolerance: |delta share_within| <= 0.005, |delta med_sigma_within| <= 0.005.
#   Halt if FAIL.
#
# Verdict rule (plan §7 step 5):
#   If above_median med_sigma_within > 0.05 -> AGRO_OK
#   Else                                     -> AGRO_FLAT_CAVEAT
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst
#   data/processed/policy_block_mapping.qs2
#   explorations/anderson_rubin/diagnostics/output/variation_decomposition.csv
#
# Outputs (explorations/anderson_rubin/diagnostics/output/):
#   agro_conditional_f1_decomposition.csv
#     Four rows (all / agro_having / above_median / above_p25) with full
#     variance decomposition stats.
#   agro_conditional_summary.csv
#     One row with verdict, headline numbers for above_median sample.
#   Appends section "## 7. Agro Conditional F1 Diagnostic" to
#     f1_combined_report.md (does not overwrite the file).
#
# Paper-to-Code Naming Map:
#   s_{m, Agro, t} (V2)    | share_v2          | Agro V2 share in (muni, year)
#   muni_baseline_agro_share| muni_baseline_agro| Mean Agro V2 share over 2004-2007
#   all_munis sample        | "all"             | Reproduces round 1
#   agro_having             | "agro_having"     | Baseline Agro > 0
#   above_median            | "above_median"    | Baseline > p50 of strictly-pos
#   above_p25               | "above_p25"       | Baseline > p25 of strictly-pos
#   med_sigma_within        | med_sigma_within  | Cross-muni median sigma_within
#   REPRO_TOL_*             | REPRO_TOL_*       | |0.005| tolerance
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Packages (INV-15: all at top)
# ------------------------------------------------------------------------------
library(data.table)
library(qs2)
library(here)
library(fst)

setDTthreads(0L)

# ------------------------------------------------------------------------------
# 2. Paths (INV-16: here::here() only, no absolute paths)
# ------------------------------------------------------------------------------
PROCESSED_DIR <- here::here("data", "processed")
OUTPUT_DIR    <- here::here(
  "explorations", "anderson_rubin", "diagnostics", "output"
)

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  message("Created output directory: ", OUTPUT_DIR)
}

path_fst    <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst")
path_cw     <- file.path(PROCESSED_DIR, "policy_block_mapping.qs2")
path_round1 <- file.path(OUTPUT_DIR,    "variation_decomposition.csv")
path_report <- file.path(OUTPUT_DIR,    "f1_combined_report.md")

# ------------------------------------------------------------------------------
# 3. Constants
# ------------------------------------------------------------------------------
BLOCK_ORDER   <- c("Agro", "Ind", "Infra", "Serv", "XX")
ACTIVE_BLOCKS <- c("Agro", "Ind", "Infra", "Serv")

# Cycle 2009 baseline window (mirrors script 33 and plan §2)
BASELINE_YEARS <- c(2004L, 2005L, 2006L, 2007L)

# Round-1 reproduction tolerance (mirrors 03_size_bin_f1.R)
REPRO_TOL_SHARE <- 0.005
REPRO_TOL_SIGMA <- 0.005

# Verdict threshold (plan §7 step 5)
AGRO_SIGMA_THRESHOLD <- 0.05

# ------------------------------------------------------------------------------
# 4. Local variance decomposition helper
#    Replicates the math from 03_size_bin_f1.R::compute_decomposition() and
#    within_muni_variation.R sections 9-10.
#
#    Input:  shares_long — data.table with columns muni_id, year, share
#            (already filtered to a single (margin, denom, bin) = Agro/V2)
#    Output: named list with all decomposition stats + per-muni sigma_within
# ------------------------------------------------------------------------------
decompose_agro_v2 <- function(shares_long) {
  stopifnot(is.data.table(shares_long))
  stopifnot(all(c("muni_id", "year", "share") %in% names(shares_long)))

  dt <- shares_long[!is.na(share)]
  if (nrow(dt) < 2L) {
    return(list(
      n_munis = 0L, n_obs = 0L,
      mean_share_overall = NA_real_,
      total_var = NA_real_, between_muni_var = NA_real_,
      within_muni_var = NA_real_, share_within = NA_real_,
      p10_sigma_within = NA_real_, med_sigma_within = NA_real_,
      p90_sigma_within = NA_real_,
      by_muni = data.table()
    ))
  }

  # Per-muni: mean share and sigma_within
  by_muni <- dt[, .(
    n_years      = .N,
    mean_share   = mean(share),
    sigma_within = if (.N >= 2L) stats::sd(share) else NA_real_
  ), by = .(muni_id)]

  # Merge muni means back
  dt2 <- merge(dt, by_muni[, .(muni_id, mean_share)], by = "muni_id")
  dt2[, residual := share - mean_share]

  n_obs   <- nrow(dt2)
  n_munis <- uniqueN(dt2$muni_id)

  mean_share_overall <- mean(dt2$share)

  total_var       <- if (n_obs >= 2L) stats::var(dt2$share)    else NA_real_
  within_muni_var <- if (n_obs >= 2L) stats::var(dt2$residual) else NA_real_

  # Between-muni variance: Var of per-muni means (need >= 2 munis)
  between_muni_var <- if (n_munis >= 2L) {
    stats::var(by_muni$mean_share)
  } else NA_real_

  share_within <- if (!is.na(total_var) && total_var > 0) {
    within_muni_var / total_var
  } else NA_real_

  # Cross-muni quantiles of sigma_within (munis with >= 2 year obs)
  sigma_vec <- by_muni[!is.na(sigma_within), sigma_within]
  if (length(sigma_vec) >= 1L) {
    q <- stats::quantile(sigma_vec, probs = c(0.10, 0.50, 0.90), names = FALSE)
    p10_sigma_within <- q[1L]
    med_sigma_within <- q[2L]
    p90_sigma_within <- q[3L]
  } else {
    p10_sigma_within <- NA_real_
    med_sigma_within <- NA_real_
    p90_sigma_within <- NA_real_
  }

  list(
    n_munis            = n_munis,
    n_obs              = n_obs,
    mean_share_overall = mean_share_overall,
    total_var          = total_var,
    between_muni_var   = between_muni_var,
    within_muni_var    = within_muni_var,
    share_within       = share_within,
    p10_sigma_within   = p10_sigma_within,
    med_sigma_within   = med_sigma_within,
    p90_sigma_within   = p90_sigma_within,
    by_muni            = by_muni
  )
}

# ------------------------------------------------------------------------------
# 5. Verify required input files exist
# ------------------------------------------------------------------------------
if (!file.exists(path_fst)) {
  stop("Missing fst panel: ", path_fst)
}
if (!file.exists(path_cw)) {
  stop("Missing crosswalk: ", path_cw, "\nRun script 30e first.")
}
if (!file.exists(path_round1)) {
  stop("Missing round-1 reference: ", path_round1,
       "\nRun within_muni_variation.R first.")
}

# ------------------------------------------------------------------------------
# 6. Load crosswalk (mirrors within_muni_variation.R §4)
# ------------------------------------------------------------------------------
message("Loading policy_block crosswalk...")
crosswalk <- setDT(qs_read(path_cw))
stopifnot(all(c("cnae_section", "policy_block") %in% names(crosswalk)))
stopifnot(nrow(crosswalk) == 21L)
message(sprintf("  Crosswalk loaded: %d CNAE sections.", nrow(crosswalk)))

# ------------------------------------------------------------------------------
# 7. Load panel (column-selective, mirrors within_muni_variation.R §5)
# ------------------------------------------------------------------------------
COLS_NEEDED <- c("firm_id", "muni_id", "year", "cnae_section",
                 "in_bndes", "value_dis_real_2018_total")

message("Loading reconstructed RAIS-BNDES panel (column-selective)...")
panel <- fst::read_fst(path_fst, columns = COLS_NEEDED, as.data.table = TRUE)

# Coerce types defensively (firm_id as character per hard constraint)
panel[, firm_id  := as.character(firm_id)]
panel[, muni_id  := as.character(muni_id)]
panel[, year     := as.integer(year)]
panel[, in_bndes := as.integer(in_bndes)]
panel[is.na(value_dis_real_2018_total), value_dis_real_2018_total := 0]

message(sprintf("  Panel loaded: %s firm-years.",
                format(nrow(panel), big.mark = ",")))

# ------------------------------------------------------------------------------
# 8. Build BNDES-only working dataset (mirrors within_muni_variation.R §6)
# ------------------------------------------------------------------------------
message("Building BNDES-only working dataset...")

bndes_panel <- panel[in_bndes == 1L &
                       !is.na(cnae_section) &
                       cnae_section != ""]

bndes_panel <- merge(
  bndes_panel,
  crosswalk[, .(cnae_section, policy_block)],
  by    = "cnae_section",
  all.x = TRUE
)

n_unmatched <- bndes_panel[is.na(policy_block), .N]
if (n_unmatched > 0L) {
  warning(sprintf(
    "%d BNDES firm-years unmatched in crosswalk; dropped from analysis.",
    n_unmatched
  ))
  bndes_panel <- bndes_panel[!is.na(policy_block)]
}

message(sprintf(
  "  BNDES-only dataset: %s firm-years, %s munis, %d years.",
  format(nrow(bndes_panel),                   big.mark = ","),
  format(uniqueN(bndes_panel$muni_id),        big.mark = ","),
  uniqueN(bndes_panel$year)
))

# Free full panel — analysis only needs BNDES rows
rm(panel); invisible(gc())

# ------------------------------------------------------------------------------
# 9. Aggregate to (muni, year, policy_block) level
#    Produces cell_dt with columns: muni_id, year, bin, L
# ------------------------------------------------------------------------------
message("Aggregating to (muni, year, policy_block)...")

cell_dt <- bndes_panel[
  , .(L = sum(value_dis_real_2018_total, na.rm = TRUE)),
  by = .(muni_id, year, bin = policy_block)
]

rm(bndes_panel); invisible(gc())

message(sprintf("  Cell rows: %s", format(nrow(cell_dt), big.mark = ",")))

# ------------------------------------------------------------------------------
# 10. Compute V2 shares for ALL policy blocks per (muni, year)
#     V2 denominator = sum over ALL 5 blocks (including XX)
#     Universe restricted to (muni, year) with total_full > 0
# ------------------------------------------------------------------------------
message("Computing V2 shares...")

# Per-(muni, year) totals over ALL blocks
totals <- cell_dt[, .(
  total_full   = sum(L, na.rm = TRUE),
  total_active = sum(L[bin %in% ACTIVE_BLOCKS], na.rm = TRUE)
), by = .(muni_id, year)]

totals <- totals[total_full > 0]
message(sprintf("  Universe: %s muni-years with total BNDES > 0.",
                format(nrow(totals), big.mark = ",")))

# Dense expansion over all 5 policy blocks so zeros are explicit
dense_keys <- totals[, .(bin = BLOCK_ORDER), by = .(muni_id, year)]
dense      <- merge(dense_keys, totals, by = c("muni_id", "year"))
dense      <- merge(dense, cell_dt, by = c("muni_id", "year", "bin"), all.x = TRUE)
dense[is.na(L), L := 0]

# V2 shares (full-economy denominator, total_full > 0 by construction)
dense[, share_v2 := L / total_full]

message(sprintf("  Dense rows: %s (5 blocks x %s muni-years)",
                format(nrow(dense), big.mark = ","),
                format(nrow(totals), big.mark = ",")))

# Restrict to Agro bin for decomposition; rename to 'share' for decompose_agro_v2()
agro_shares <- dense[bin == "Agro", .(muni_id, year, share = share_v2)]

rm(dense_keys); invisible(gc())

# ------------------------------------------------------------------------------
# 11. Compute muni-level baseline Agro share (cycle 2009: 2004-2007)
#     muni_baseline_agro = mean of s_{m, Agro, t} over t in {2004..2007}
#     Munis with no obs in window get baseline = 0 (agro-absent)
# ------------------------------------------------------------------------------
message("Computing muni baseline Agro share (2004-2007)...")

baseline_dt <- agro_shares[year %in% BASELINE_YEARS,
                            .(muni_baseline_agro = mean(share, na.rm = TRUE)),
                            by = .(muni_id)]

# Get the full universe of munis (all munis in V2 panel)
all_munis_dt <- data.table(muni_id = unique(totals$muni_id))
baseline_dt  <- merge(all_munis_dt, baseline_dt,
                      by = "muni_id", all.x = TRUE)
# Munis with no BNDES Agro activity in 2004-2007 get baseline = 0
baseline_dt[is.na(muni_baseline_agro), muni_baseline_agro := 0]

n_agro_having <- baseline_dt[muni_baseline_agro > 0, .N]
n_agro_zero   <- baseline_dt[muni_baseline_agro == 0, .N]
message(sprintf("  Total munis in universe: %s",
                format(nrow(baseline_dt), big.mark = ",")))
message(sprintf("  Agro-having (baseline > 0): %s",
                format(n_agro_having, big.mark = ",")))
message(sprintf("  Agro-absent (baseline = 0): %s",
                format(n_agro_zero, big.mark = ",")))

# Percentile thresholds on the strictly-positive distribution
pos_baselines <- baseline_dt[muni_baseline_agro > 0, muni_baseline_agro]
p50_pos <- stats::quantile(pos_baselines, 0.50, names = FALSE)
p25_pos <- stats::quantile(pos_baselines, 0.25, names = FALSE)

message(sprintf("  Strictly-positive distribution: n=%d, p25=%.4f, p50=%.4f",
                length(pos_baselines), p25_pos, p50_pos))

# ------------------------------------------------------------------------------
# 12. Define samples
#     all_munis:    all munis in V2 panel universe
#     agro_having:  baseline > 0
#     above_median: baseline > p50 of strictly-positive
#     above_p25:    baseline > p25 of strictly-positive (stricter)
# ------------------------------------------------------------------------------
samp_all       <- baseline_dt[, muni_id]
samp_agro      <- baseline_dt[muni_baseline_agro > 0, muni_id]
samp_above_med <- baseline_dt[muni_baseline_agro > p50_pos, muni_id]
samp_above_p25 <- baseline_dt[muni_baseline_agro > p25_pos, muni_id]

message(sprintf("  Sample sizes — all: %d | agro_having: %d | above_median: %d | above_p25: %d",
                length(samp_all), length(samp_agro),
                length(samp_above_med), length(samp_above_p25)))

# ------------------------------------------------------------------------------
# 13. SANITY GATE — reproduce round-1 ALL-MUNIS numbers
#     Compare against variation_decomposition.csv for policy_block x Agro x V2
#     Tolerance: |delta share_within| <= 0.005, |delta med_sigma_within| <= 0.005
# ------------------------------------------------------------------------------
message("\n================================================================")
message("  SANITY GATE: reproduce round-1 policy_block x Agro x V2")
message("================================================================")

round1_dt <- fread(path_round1)
round1_agro_v2 <- round1_dt[margin == "policy_block" & denom == "V2" & bin == "Agro"]

if (nrow(round1_agro_v2) != 1L) {
  stop("Round-1 reference missing: expected one row for policy_block x V2 x Agro.")
}

r1_share_within   <- round1_agro_v2$share_within
r1_med_sigma      <- round1_agro_v2$med_sigma_within

# Run decomposition on the full universe (all_munis)
shares_all <- agro_shares[muni_id %in% samp_all]
decomp_all <- decompose_agro_v2(shares_all)

delta_share <- abs(decomp_all$share_within - r1_share_within)
delta_sigma <- abs(decomp_all$med_sigma_within - r1_med_sigma)

# NA-safe delta comparisons
fail_share <- !is.na(delta_share) && delta_share > REPRO_TOL_SHARE
fail_sigma <- !is.na(delta_sigma) && delta_sigma > REPRO_TOL_SIGMA

message(sprintf("  Round-1 reference:  share_within=%.6f | med_sigma_within=%.6f",
                r1_share_within, r1_med_sigma))
message(sprintf("  This run (all):     share_within=%.6f | med_sigma_within=%.6f",
                decomp_all$share_within, decomp_all$med_sigma_within))
message(sprintf("  |delta share_within| = %.6f  (tol %.4f) -> %s",
                ifelse(is.na(delta_share), NA_real_, delta_share),
                REPRO_TOL_SHARE,
                if (is.na(delta_share)) "NA" else if (fail_share) "FAIL" else "OK"))
message(sprintf("  |delta med_sigma|    = %.6f  (tol %.4f) -> %s",
                ifelse(is.na(delta_sigma), NA_real_, delta_sigma),
                REPRO_TOL_SIGMA,
                if (is.na(delta_sigma)) "NA" else if (fail_sigma) "FAIL" else "OK"))

if (fail_share || fail_sigma) {
  stop(sprintf(
    paste0(
      "SANITY GATE FAILED:\n",
      "  |delta share_within| = %.6f  (tol %.4f, FAIL=%s)\n",
      "  |delta med_sigma_within| = %.6f  (tol %.4f, FAIL=%s)\n",
      "Do not write conditional outputs until the panel filter matches round 1.\n",
      "Check that within_muni_variation.R was run on the same source data."
    ),
    delta_share, REPRO_TOL_SHARE, fail_share,
    delta_sigma, REPRO_TOL_SIGMA, fail_sigma
  ))
}

message("  SANITY GATE: PASS")

# ------------------------------------------------------------------------------
# 14. Run decomposition for all four samples
# ------------------------------------------------------------------------------
message("\n================================================================")
message("  F1 decomposition by sample")
message("================================================================")

sample_specs <- list(
  list(label = "all",          munis = samp_all),
  list(label = "agro_having",  munis = samp_agro),
  list(label = "above_median", munis = samp_above_med),
  list(label = "above_p25",    munis = samp_above_p25)
)

# Pre-allocate results list (INV-17: no growing containers in loop)
decomp_results <- vector("list", length(sample_specs))

for (i in seq_along(sample_specs)) {
  sp    <- sample_specs[[i]]
  shard <- agro_shares[muni_id %in% sp$munis]
  res   <- decompose_agro_v2(shard)
  decomp_results[[i]] <- c(list(sample = sp$label), res)

  message(sprintf(
    "  Sample %-14s | n_munis=%4d | n_obs=%5d | share_within=%.4f | med_sigma=%.4f",
    sp$label,
    res$n_munis, res$n_obs,
    ifelse(is.na(res$share_within),    NA_real_, res$share_within),
    ifelse(is.na(res$med_sigma_within), NA_real_, res$med_sigma_within)
  ))
}

# ------------------------------------------------------------------------------
# 15. Build output CSV: agro_conditional_f1_decomposition.csv
#     Columns: sample, n_munis, n_obs, mean_share_overall, total_var,
#              between_muni_var, within_muni_var, share_within,
#              p10_sigma_within, med_sigma_within, p90_sigma_within
# ------------------------------------------------------------------------------
message("\nBuilding output tables...")

decomp_rows <- vector("list", length(decomp_results))
for (i in seq_along(decomp_results)) {
  r <- decomp_results[[i]]
  decomp_rows[[i]] <- data.table(
    sample             = r$sample,
    n_munis            = r$n_munis,
    n_obs              = r$n_obs,
    mean_share_overall = r$mean_share_overall,
    total_var          = r$total_var,
    between_muni_var   = r$between_muni_var,
    within_muni_var    = r$within_muni_var,
    share_within       = r$share_within,
    p10_sigma_within   = r$p10_sigma_within,
    med_sigma_within   = r$med_sigma_within,
    p90_sigma_within   = r$p90_sigma_within
  )
}

decomp_out <- rbindlist(decomp_rows)

path_decomp_out <- file.path(OUTPUT_DIR, "agro_conditional_f1_decomposition.csv")
fwrite(decomp_out, path_decomp_out)
message(sprintf("  Written: %s (%d rows)", basename(path_decomp_out), nrow(decomp_out)))

# ------------------------------------------------------------------------------
# 16. Verdict and summary CSV
# ------------------------------------------------------------------------------

# Extract above_median stats for the headline verdict
above_med_res <- decomp_results[[which(vapply(decomp_results,
                                               function(x) x$sample,
                                               character(1L)) == "above_median")]]

med_sigma_above_med <- above_med_res$med_sigma_within
share_within_above_med <- above_med_res$share_within
n_munis_above_med <- above_med_res$n_munis

# Verdict
verdict <- if (!is.na(med_sigma_above_med) && med_sigma_above_med > AGRO_SIGMA_THRESHOLD) {
  "AGRO_OK"
} else {
  "AGRO_FLAT_CAVEAT"
}

summary_out <- data.table(
  verdict                = verdict,
  med_sigma_above_median = med_sigma_above_med,
  share_within_above_median = share_within_above_med,
  n_munis_above_median   = n_munis_above_med,
  threshold_med_sigma    = AGRO_SIGMA_THRESHOLD,
  p25_pos_baseline       = p25_pos,
  p50_pos_baseline       = p50_pos,
  n_agro_having_munis    = n_agro_having,
  sanity_gate_passed     = TRUE
)

path_summary_out <- file.path(OUTPUT_DIR, "agro_conditional_summary.csv")
fwrite(summary_out, path_summary_out)
message(sprintf("  Written: %s", basename(path_summary_out)))

# ------------------------------------------------------------------------------
# 17. Append section to f1_combined_report.md
# ------------------------------------------------------------------------------
message("Appending to f1_combined_report.md...")

if (!file.exists(path_report)) {
  stop("Cannot append: f1_combined_report.md not found at ", path_report,
       "\nRun 03_size_bin_f1.R first.")
}

fmt_num <- function(x, d = 4L) {
  ifelse(is.na(x), "---", sprintf(paste0("%.", d, "f"), x))
}
fmt_int <- function(x) {
  ifelse(is.na(x), "---", format(as.integer(x), big.mark = ","))
}

# Verdict annotation
verdict_note <- if (verdict == "AGRO_OK") {
  paste0("**AGRO_OK** — Agro varies substantially where it exists. ",
         "The flat tail in round 1 is 'where's the action,' not structural ",
         "flatness. No change to D15.")
} else {
  paste0("**AGRO_FLAT_CAVEAT** — Even conditioning on agro-having munis, ",
         "med sigma_within does not exceed the 0.05 threshold. ",
         "Agro is structurally flat under V2 at the muni x year level. ",
         "Add Agro caveat to docs/PROJECT_BLUEPRINT.md §3 F1 row.")
}

new_section <- c(
  "",
  "---",
  "",
  "## 7. Agro Conditional F1 Diagnostic",
  "",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "### 7.1 Motivation",
  "",
  paste0(
    "Round-1 (D15) reports `policy_block x Agro x V2` as SUPPORTED in aggregate ",
    "(share_within = ", fmt_num(r1_share_within, 4L), ") but with ",
    "`med_sigma_within = ", fmt_num(r1_med_sigma, 4L), "` because most munis ",
    "have zero Agro BNDES credit in most years. The pattern is 'Agro moves where ",
    "Agro is a thing' -- correct IV regime, but warrants a positive conditional check."
  ),
  "",
  "### 7.2 Setup",
  "",
  paste0("- Denominator: V2 (full-economy)."),
  paste0("- Baseline window: cycle 2009 (2004-2007); ",
         "`muni_baseline_agro_share` = mean Agro V2 share over that window."),
  paste0("- Strictly-positive distribution (n=", fmt_int(n_agro_having), " munis): ",
         "p25=", fmt_num(p25_pos, 4L), ", p50=", fmt_num(p50_pos, 4L), "."),
  "",
  "### 7.3 Decomposition by sample",
  "",
  paste0("| Sample | n_munis | n_obs | mean_share | total_var | share_within | ",
         "p10 sigma | med sigma | p90 sigma |"),
  paste0("|--------|---------|-------|------------|-----------|--------------|",
         "-----------|-----------|-----------|")
)

for (i in seq_along(decomp_results)) {
  r <- decomp_results[[i]]
  new_section <- c(new_section, sprintf(
    "| %s | %s | %s | %s | %s | %s | %s | %s | %s |",
    r$sample,
    fmt_int(r$n_munis),
    fmt_int(r$n_obs),
    fmt_num(r$mean_share_overall, 4L),
    fmt_num(r$total_var, 5L),
    fmt_num(r$share_within, 4L),
    fmt_num(r$p10_sigma_within, 4L),
    fmt_num(r$med_sigma_within, 4L),
    fmt_num(r$p90_sigma_within, 4L)
  ))
}

new_section <- c(new_section,
  "",
  "### 7.4 Sanity check vs. round 1",
  "",
  sprintf(
    "Round-1 `policy_block x Agro x V2`: share_within=%.6f, med_sigma=%.6f.",
    r1_share_within, r1_med_sigma
  ),
  sprintf(
    "This run (all_munis): share_within=%.6f, med_sigma=%.6f. Delta: |%.6f|, |%.6f|. **PASS**.",
    decomp_all$share_within,
    decomp_all$med_sigma_within,
    abs(decomp_all$share_within - r1_share_within),
    abs(decomp_all$med_sigma_within - r1_med_sigma)
  ),
  "",
  "### 7.5 Verdict",
  "",
  verdict_note,
  "",
  sprintf(
    "Above-median sample (n=%d munis, baseline > p50=%.4f): ",
    n_munis_above_med, p50_pos
  ),
  sprintf(
    "  share_within = %.4f, med_sigma_within = %.4f.",
    ifelse(is.na(share_within_above_med), NA_real_, share_within_above_med),
    ifelse(is.na(med_sigma_above_med), NA_real_, med_sigma_above_med)
  ),
  "",
  "### 7.6 Implication for D15",
  "",
  if (verdict == "AGRO_OK") {
    paste0(
      "No change to D15. The round-1 verdict on `policy_block x Agro x V2` holds ",
      "under conditioning: the flat tail is driven by urban munis where Agro BNDES ",
      "is mechanically zero, not by structural time-flatness of Agro shares where ",
      "the instrument actually bites."
    )
  } else {
    paste0(
      "Add caveat to docs/PROJECT_BLUEPRINT.md §3 F1 row: Agro shares are ",
      "structurally flat under V2 even among agro-having munis. This is not a ",
      "chain-breaker (share_within is strong), but the per-muni sigma_within ",
      "is weak even where Agro credit exists. The IV identification on Agro bites ",
      "via cross-muni variation, not within-muni x time variation."
    )
  },
  ""
)

# Append (write to file, append mode)
write(new_section,
      file      = path_report,
      append    = TRUE,
      sep       = "\n")

message(sprintf("  Appended section 7 to: %s", basename(path_report)))

# ------------------------------------------------------------------------------
# 18. Console summary
# ------------------------------------------------------------------------------
message("\n================================================================")
message("  E3b: Agro Conditional F1 — Summary")
message("================================================================")
message(sprintf("  Sanity gate (round-1 reproduction): PASS"))
message(sprintf("  Verdict: %s", verdict))
message("")
message("  Three-sample table (Agro x V2 decomposition):")
message(sprintf("  %-14s | %7s | %6s | %12s | %11s",
                "sample", "n_munis", "n_obs", "share_within", "med_sigma"))
message(sprintf("  %-14s | %7s | %6s | %12s | %11s",
                "--------------", "-------", "------", "------------", "-----------"))
for (i in seq_len(3L)) {
  r <- decomp_results[[i]]
  message(sprintf("  %-14s | %7s | %6s | %12s | %11s",
                  r$sample,
                  format(r$n_munis, big.mark = ","),
                  format(r$n_obs, big.mark = ","),
                  fmt_num(r$share_within, 4L),
                  fmt_num(r$med_sigma_within, 4L)))
}
message("")
message(sprintf("  D15 caveat needed? %s",
                if (verdict == "AGRO_OK") "NO — Agro is fine conditionally."
                else "YES — add Agro caveat to Blueprint §3 F1 row."))
message("")
message("  Output files written to:")
message("    ", OUTPUT_DIR)
message("================================================================")

invisible(list(
  decomp_out   = decomp_out,
  summary_out  = summary_out,
  verdict      = verdict,
  sanity_pass  = TRUE
))
