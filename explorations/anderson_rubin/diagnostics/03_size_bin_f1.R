# ==============================================================================
# 03_size_bin_f1.R
#
# E3: F1 within-muni x time variance decomposition for size x sector aggregation
#     margins. Run for surviving options A2 and A3 (post-E2, user-confirmed),
#     each under V1 (active-only, primary) and V2 (full-economy, robustness).
#     Four spec runs total.
#
# Foundation under test (docs/PROJECT_BLUEPRINT.md, F1):
#   "For at least one F0-margin, BNDES credit shares have meaningful within-muni
#    x time variation."  If shares are flat within muni over time, muni FE
#    absorb all variation and the IV first stage degenerates.
#
# Plan reference: logs/plans/2026-05-04_size-bin-diagnostics.md §6 + §0.2 + §10
#
# Surviving options (deviation from plan §6 default; see brief):
#   A2 — 2-bin scheme: MPME (0-49) + Big (50+). 17 active sections x 2 = 34 bins
#   A3 — 3-bin scheme: MPME (0-49) + Media (50-499) + Grande (500+).
#                       17 active sections x 3 = 51 bins
#   B  (terciles) is dropped per user.
#
# Round-1 reproduction gate (CRITICAL):
#   Before running A2/A3 outputs, reproduce variation_decomposition.csv on
#   cnae_section x {V1,V2} and policy_block x {V1,V2} using the refactored
#   f1_decompose() function. Tolerance: |delta share_within| <= 0.005,
#   |delta med_sigma_within| <= 0.005. If FAIL: write *_FAILED.csv and stop.
#
# Inputs:
#   explorations/anderson_rubin/diagnostics/output/coverage_cells_optionA2.csv
#   explorations/anderson_rubin/diagnostics/output/coverage_cells_optionA3.csv
#   data/processed/rais_bndes_reconstructed.fst
#   data/processed/policy_block_mapping.qs2
#   explorations/anderson_rubin/diagnostics/output/variation_decomposition.csv
#
# Outputs (explorations/anderson_rubin/diagnostics/output/):
#   f1_round1_reproduction_PASS.csv  (or _FAILED.csv if gate fails)
#   f1_optionA2_V1_decomposition.csv
#   f1_optionA2_V1_summary.csv
#   f1_optionA2_V1_vs_round1.csv
#   f1_optionA2_V2_decomposition.csv
#   f1_optionA2_V2_summary.csv
#   f1_optionA2_V2_vs_round1.csv
#   f1_optionA3_V1_decomposition.csv
#   f1_optionA3_V1_summary.csv
#   f1_optionA3_V1_vs_round1.csv
#   f1_optionA3_V2_decomposition.csv
#   f1_optionA3_V2_summary.csv
#   f1_optionA3_V2_vs_round1.csv
#   f1_combined_report.md
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Packages
# ------------------------------------------------------------------------------
library(data.table)
library(qs2)
library(here)
library(fst)

setDTthreads(0L)

# ------------------------------------------------------------------------------
# 2. Paths
# ------------------------------------------------------------------------------
PROCESSED_DIR <- here::here("data", "processed")
OUTPUT_DIR    <- here::here(
  "explorations", "anderson_rubin", "diagnostics", "output"
)

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
}

path_cells_A2 <- file.path(OUTPUT_DIR, "coverage_cells_optionA2.csv")
path_cells_A3 <- file.path(OUTPUT_DIR, "coverage_cells_optionA3.csv")
path_round1   <- file.path(OUTPUT_DIR, "variation_decomposition.csv")

path_fst <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst")
path_cw  <- file.path(PROCESSED_DIR, "policy_block_mapping.qs2")

# ------------------------------------------------------------------------------
# 3. Constants
# ------------------------------------------------------------------------------
CNAE_ORDER  <- c("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K",
                 "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U")
XX_SECTIONS <- c("K", "O", "T", "U")
ACTIVE_SECTIONS <- setdiff(CNAE_ORDER, XX_SECTIONS)  # 17 sections

BLOCK_ORDER   <- c("Agro", "Ind", "Infra", "Serv", "XX")
ACTIVE_BLOCKS <- c("Agro", "Ind", "Infra", "Serv")

# F1 verdict thresholds (mirror within_muni_variation.R lines 84-86)
F1_SIGMA_MEDIAN_MIN          <- 0.05
F1_SHARE_WITHIN_MIN          <- 0.20
F1_SHARE_WITHIN_REJECT_BELOW <- 0.10

# Round-1 reproduction tolerance
REPRO_TOL_SHARE <- 0.005
REPRO_TOL_SIGMA <- 0.005

# ------------------------------------------------------------------------------
# 4. f1_decompose() — refactor of within_muni_variation.R sections 7 + 9 + 10
#
#    Inputs:
#      cell_dt      data.table with columns: muni_id, year, bin, L
#      margin_label character, e.g. "A2_size_x_sec"
#      all_bins     character vector — full universe of bins for this margin
#      active_bins  character vector — non-XX bins
#      output_bins  character vector — bins to keep in returned long DT
#      denom_label  "V1" or "V2"
#
#    Returns long DT: margin, denom, muni_id, year, bin, share
#
#    Mirrors the math in within_muni_variation.R lines 185-234.
# ------------------------------------------------------------------------------
f1_decompose <- function(cell_dt,
                         margin_label,
                         all_bins,
                         active_bins,
                         output_bins,
                         denom_label) {
  stopifnot(is.data.table(cell_dt))
  stopifnot(all(c("muni_id", "year", "bin", "L") %in% names(cell_dt)))
  stopifnot(denom_label %in% c("V1", "V2"))

  # Aggregate (defensive — cell_dt may have duplicates if rebuilt)
  agg <- cell_dt[bin %in% all_bins,
                 .(L = sum(L, na.rm = TRUE)),
                 by = .(muni_id, year, bin)]

  totals <- agg[, .(
    total_full   = sum(L, na.rm = TRUE),
    total_active = sum(L[bin %in% active_bins], na.rm = TRUE)
  ), by = .(muni_id, year)]

  totals <- totals[total_full > 0]

  # Dense expansion
  dense_keys <- totals[, .(bin = all_bins), by = .(muni_id, year)]
  dense      <- merge(dense_keys, totals, by = c("muni_id", "year"))
  dense      <- merge(dense, agg, by = c("muni_id", "year", "bin"), all.x = TRUE)
  dense[is.na(L), L := 0]

  is_active <- dense$bin %in% active_bins

  if (denom_label == "V1") {
    dense[, share := fifelse(is_active & total_active > 0,
                              L / total_active,
                              NA_real_)]
  } else {
    dense[, share := L / total_full]
  }

  dense <- dense[bin %in% output_bins]

  dense[, .(margin = margin_label,
            denom  = denom_label,
            muni_id, year, bin, share)]
}

# ------------------------------------------------------------------------------
# 5. compute_decomposition() — variance decomposition + sigma quantiles
#    Mirrors within_muni_variation.R sections 9-10 (lines 268-328).
# ------------------------------------------------------------------------------
compute_decomposition <- function(shares_long) {

  by_muni <- shares_long[!is.na(share),
                         .(n_years      = .N,
                           mean_share   = mean(share),
                           sigma_within = if (.N >= 2L) stats::sd(share) else NA_real_),
                         by = .(margin, denom, muni_id, bin)]

  shares_with_means <- merge(
    shares_long[!is.na(share)],
    by_muni[, .(margin, denom, muni_id, bin, mean_share)],
    by = c("margin", "denom", "muni_id", "bin")
  )
  shares_with_means[, residual := share - mean_share]

  decomp_core <- shares_with_means[, .(
    n_obs            = .N,
    n_munis          = uniqueN(muni_id),
    mean_share_overall = mean(share),
    total_var        = if (.N >= 2L) stats::var(share)    else NA_real_,
    within_muni_var  = if (.N >= 2L) stats::var(residual) else NA_real_
  ), by = .(margin, denom, bin)]

  between_var <- by_muni[, .(
    between_muni_var = if (.N >= 2L) stats::var(mean_share) else NA_real_
  ), by = .(margin, denom, bin)]

  decomposition <- merge(decomp_core, between_var,
                         by = c("margin", "denom", "bin"), all.x = TRUE)

  decomposition[, share_within := fifelse(
    !is.na(total_var) & total_var > 0,
    within_muni_var / total_var,
    NA_real_
  )]

  sigma_quantiles <- by_muni[!is.na(sigma_within), {
    q <- stats::quantile(sigma_within, probs = c(0.10, 0.50, 0.90), names = FALSE)
    .(p10_sigma_within   = q[1],
      med_sigma_within   = q[2],
      p90_sigma_within   = q[3],
      n_munis_with_sigma = .N)
  }, by = .(margin, denom, bin)]

  decomposition <- merge(decomposition, sigma_quantiles,
                         by = c("margin", "denom", "bin"), all.x = TRUE)

  setcolorder(decomposition, c(
    "margin", "denom", "bin",
    "n_obs", "n_munis", "n_munis_with_sigma",
    "mean_share_overall",
    "total_var", "between_muni_var", "within_muni_var", "share_within",
    "p10_sigma_within", "med_sigma_within", "p90_sigma_within"
  ))

  decomposition[]
}

# ------------------------------------------------------------------------------
# 6. compute_summary() — per-spec summary + verdict
# ------------------------------------------------------------------------------
compute_summary <- function(decomposition_dt) {
  s <- decomposition_dt[, .(
    n_bins_total                  = .N,
    n_bins_with_share_within      = sum(!is.na(share_within)),
    max_share_within              = if (any(!is.na(share_within))) {
      max(share_within, na.rm = TRUE)
    } else NA_real_,
    med_share_within_across_bins  = if (any(!is.na(share_within))) {
      stats::median(share_within, na.rm = TRUE)
    } else NA_real_,
    mean_share_within_across_bins = if (any(!is.na(share_within))) {
      mean(share_within, na.rm = TRUE)
    } else NA_real_,
    max_med_sigma_within          = if (any(!is.na(med_sigma_within))) {
      max(med_sigma_within, na.rm = TRUE)
    } else NA_real_,
    med_med_sigma_within          = if (any(!is.na(med_sigma_within))) {
      stats::median(med_sigma_within, na.rm = TRUE)
    } else NA_real_,
    n_bins_supported              = sum(
      !is.na(med_sigma_within) & !is.na(share_within) &
        med_sigma_within > F1_SIGMA_MEDIAN_MIN &
        share_within     > F1_SHARE_WITHIN_MIN,
      na.rm = TRUE
    ),
    any_bin_supports_f1           = any(
      !is.na(med_sigma_within) & !is.na(share_within) &
        med_sigma_within > F1_SIGMA_MEDIAN_MIN &
        share_within     > F1_SHARE_WITHIN_MIN,
      na.rm = TRUE
    )
  ), by = .(margin, denom)]

  s[, verdict := fcase(
    any_bin_supports_f1,                                "SUPPORTED",
    is.na(max_share_within),                            "INCONCLUSIVE",
    max_share_within < F1_SHARE_WITHIN_REJECT_BELOW,    "REJECTED",
    default                                             = "INCONCLUSIVE"
  )]

  s[]
}

# ------------------------------------------------------------------------------
# 7. ROUND-1 REPRODUCTION GATE
#
#    Reproduce variation_decomposition.csv on cnae_section x {V1,V2} and
#    policy_block x {V1,V2} from raw data via f1_decompose. Compare to
#    round-1 numbers; halt on failure.
# ------------------------------------------------------------------------------
message("================================================================")
message("  STEP 1: Round-1 reproduction gate")
message("================================================================")

if (!file.exists(path_round1)) {
  stop("Missing round-1 reference: ", path_round1)
}
round1_dt <- fread(path_round1)

# Round-1 source data: rais_bndes_reconstructed.fst -> in_bndes==1 ->
# merge policy_block_mapping.qs2 -> aggregate.
COLS_NEEDED <- c("firm_id", "muni_id", "year", "cnae_section",
                 "in_bndes", "value_dis_real_2018_total")

message("  Loading reconstructed RAIS-BNDES panel (column-selective)...")

if (!file.exists(path_fst)) {
  stop("Missing fst panel: ", path_fst)
}

panel <- fst::read_fst(path_fst, columns = COLS_NEEDED, as.data.table = TRUE)

panel[, firm_id  := as.character(firm_id)]
panel[, muni_id  := as.character(muni_id)]
panel[, year     := as.integer(year)]
panel[, in_bndes := as.integer(in_bndes)]
panel[is.na(value_dis_real_2018_total), value_dis_real_2018_total := 0]

message(sprintf("    Panel rows: %s",
                format(nrow(panel), big.mark = ",")))

if (!file.exists(path_cw)) {
  stop("Missing crosswalk: ", path_cw)
}
crosswalk <- setDT(qs_read(path_cw))
stopifnot(all(c("cnae_section", "policy_block") %in% names(crosswalk)))

bndes_panel <- panel[in_bndes == 1L &
                       !is.na(cnae_section) &
                       cnae_section != ""]
bndes_panel <- merge(bndes_panel,
                     crosswalk[, .(cnae_section, policy_block)],
                     by = "cnae_section", all.x = TRUE)
bndes_panel <- bndes_panel[!is.na(policy_block)]

rm(panel); invisible(gc())

message(sprintf("    BNDES rows: %s | munis: %s | years: %d",
                format(nrow(bndes_panel),            big.mark = ","),
                format(uniqueN(bndes_panel$muni_id), big.mark = ","),
                uniqueN(bndes_panel$year)))

# Build margin-specific cell tables expected by f1_decompose
cell_cnae <- bndes_panel[
  , .(L = sum(value_dis_real_2018_total, na.rm = TRUE)),
  by = .(muni_id, year, bin = cnae_section)
]

cell_block <- bndes_panel[
  , .(L = sum(value_dis_real_2018_total, na.rm = TRUE)),
  by = .(muni_id, year, bin = policy_block)
]

rm(bndes_panel); invisible(gc())

# Run f1_decompose for the four round-1 specs
repro_specs <- list(
  list(label = "cnae_section", denom = "V1",
       cell  = cell_cnae,  all_b = CNAE_ORDER,
       active = ACTIVE_SECTIONS, output = CNAE_ORDER),
  list(label = "cnae_section", denom = "V2",
       cell  = cell_cnae,  all_b = CNAE_ORDER,
       active = ACTIVE_SECTIONS, output = CNAE_ORDER),
  list(label = "policy_block", denom = "V1",
       cell  = cell_block, all_b = BLOCK_ORDER,
       active = ACTIVE_BLOCKS,  output = BLOCK_ORDER),
  list(label = "policy_block", denom = "V2",
       cell  = cell_block, all_b = BLOCK_ORDER,
       active = ACTIVE_BLOCKS,  output = BLOCK_ORDER)
)

repro_long <- vector("list", length(repro_specs))
for (i in seq_along(repro_specs)) {
  sp <- repro_specs[[i]]
  message(sprintf("    Reproducing: %s x %s ...", sp$label, sp$denom))
  repro_long[[i]] <- f1_decompose(
    cell_dt      = sp$cell,
    margin_label = sp$label,
    all_bins     = sp$all_b,
    active_bins  = sp$active,
    output_bins  = sp$output,
    denom_label  = sp$denom
  )
}
repro_long <- rbindlist(repro_long)

repro_decomp <- compute_decomposition(repro_long)

# Compare to round 1 — only on rows where round-1 reports both metrics
round1_compare <- round1_dt[
  margin %in% c("cnae_section", "policy_block") &
    !is.na(share_within) | !is.na(med_sigma_within),
  .(margin, denom, bin,
    share_within_old   = share_within,
    med_sigma_within_old = med_sigma_within)
]

cmp <- merge(
  repro_decomp[, .(margin, denom, bin,
                   share_within_new     = share_within,
                   med_sigma_within_new = med_sigma_within)],
  round1_compare,
  by = c("margin", "denom", "bin"),
  all = FALSE
)

cmp[, delta_share := share_within_new       - share_within_old]
cmp[, delta_sigma := med_sigma_within_new   - med_sigma_within_old]
cmp[, abs_delta_share := abs(delta_share)]
cmp[, abs_delta_sigma := abs(delta_sigma)]

# Identify failures
cmp[, fail_share := !is.na(abs_delta_share) & abs_delta_share > REPRO_TOL_SHARE]
cmp[, fail_sigma := !is.na(abs_delta_sigma) & abs_delta_sigma > REPRO_TOL_SIGMA]
cmp[, fail_any   := fail_share | fail_sigma]

n_fails <- sum(cmp$fail_any, na.rm = TRUE)

repro_pass_path   <- file.path(OUTPUT_DIR, "f1_round1_reproduction_PASS.csv")
repro_failed_path <- file.path(OUTPUT_DIR, "f1_round1_reproduction_FAILED.csv")

if (n_fails > 0L) {
  fwrite(cmp[fail_any == TRUE], repro_failed_path)
  # Clean up any stale PASS file
  if (file.exists(repro_pass_path)) file.remove(repro_pass_path)
  message(sprintf("\n  REPRODUCTION FAILED: %d cells exceed tolerance.", n_fails))
  message(sprintf("    See: %s", repro_failed_path))
  stop(sprintf(
    "Round-1 reproduction failed for %d (margin x denom x bin) cells. ",
    n_fails
  ),
  "Halting before A2/A3 outputs to avoid silently producing incomparable numbers.")
} else {
  fwrite(cmp, repro_pass_path)
  if (file.exists(repro_failed_path)) file.remove(repro_failed_path)
  message(sprintf("\n  REPRODUCTION PASS: %d cells, all within tolerance.",
                  nrow(cmp)))
  message(sprintf("    Max |delta share_within|: %.6f (tol %.4f)",
                  max(cmp$abs_delta_share, na.rm = TRUE), REPRO_TOL_SHARE))
  message(sprintf("    Max |delta med_sigma_within|: %.6f (tol %.4f)",
                  max(cmp$abs_delta_sigma, na.rm = TRUE), REPRO_TOL_SIGMA))
  message(sprintf("    Written: %s", repro_pass_path))
}

# Round-1 cnae_section reference for vs_round1 tables (V1 + V2)
round1_cnae <- round1_dt[
  margin == "cnae_section",
  .(denom, cnae_section = bin,
    round1_share_within     = share_within,
    round1_med_sigma_within = med_sigma_within,
    round1_n_munis          = n_munis,
    round1_mean_share       = mean_share_overall)
]

# Free memory before size-bin runs
rm(cell_cnae, cell_block, repro_long, repro_decomp, cmp, round1_compare)
invisible(gc())

# ------------------------------------------------------------------------------
# 8. Load A2 and A3 cell tables
# ------------------------------------------------------------------------------
message("\n================================================================")
message("  STEP 2: Load A2 and A3 cell tables")
message("================================================================")

if (!file.exists(path_cells_A2)) stop("Missing: ", path_cells_A2)
if (!file.exists(path_cells_A3)) stop("Missing: ", path_cells_A3)

cell_A2 <- fread(path_cells_A2)
cell_A3 <- fread(path_cells_A3)

# Strip any extra columns (A2 file has n_cells_total)
needed_cols <- c("size_bin", "cnae_section", "muni_id", "year", "L_total")
stopifnot(all(needed_cols %in% names(cell_A2)))
stopifnot(all(needed_cols %in% names(cell_A3)))

cell_A2 <- cell_A2[, .(size_bin, cnae_section, muni_id, year, L_total)]
cell_A3 <- cell_A3[, .(size_bin, cnae_section, muni_id, year, L_total)]

# Coerce types
for (dt in list(cell_A2, cell_A3)) {
  dt[, muni_id      := as.character(muni_id)]
  dt[, cnae_section := as.character(cnae_section)]
  dt[, year         := as.integer(year)]
  dt[, size_bin     := as.integer(size_bin)]
}

# Build size_x_sec
cell_A2[, bin := paste(cnae_section, size_bin, sep = "_")]
cell_A3[, bin := paste(cnae_section, size_bin, sep = "_")]

# Aggregate over (muni, year, bin) (rename L_total -> L)
cell_A2_long <- cell_A2[
  !is.na(cnae_section) & cnae_section != "" & !is.na(size_bin),
  .(L = sum(L_total, na.rm = TRUE)),
  by = .(muni_id, year, bin)
]
cell_A3_long <- cell_A3[
  !is.na(cnae_section) & cnae_section != "" & !is.na(size_bin),
  .(L = sum(L_total, na.rm = TRUE)),
  by = .(muni_id, year, bin)
]

rm(cell_A2, cell_A3); invisible(gc())

message(sprintf("  A2 long rows: %s", format(nrow(cell_A2_long), big.mark = ",")))
message(sprintf("  A3 long rows: %s", format(nrow(cell_A3_long), big.mark = ",")))

# Build all_bins and active_bins per option
build_bin_sets <- function(cell_long_dt, n_size_bins) {
  all_bins_present <- sort(unique(cell_long_dt$bin))
  # Canonical universe = full Cartesian over CNAE_ORDER x 1..n_size_bins
  full <- as.vector(t(outer(CNAE_ORDER, seq_len(n_size_bins),
                             function(s, b) paste(s, b, sep = "_"))))
  active <- as.vector(t(outer(ACTIVE_SECTIONS, seq_len(n_size_bins),
                               function(s, b) paste(s, b, sep = "_"))))
  list(all = full, active = active, present = all_bins_present)
}

bins_A2 <- build_bin_sets(cell_A2_long, 2L)
bins_A3 <- build_bin_sets(cell_A3_long, 3L)

message(sprintf("  A2: %d all bins (canonical), %d active, %d present in data",
                length(bins_A2$all), length(bins_A2$active), length(bins_A2$present)))
message(sprintf("  A3: %d all bins (canonical), %d active, %d present in data",
                length(bins_A3$all), length(bins_A3$active), length(bins_A3$present)))

stopifnot(length(bins_A2$active) == 34L)
stopifnot(length(bins_A3$active) == 51L)

# ------------------------------------------------------------------------------
# 9. Run all four (option, denom) decompositions
# ------------------------------------------------------------------------------
message("\n================================================================")
message("  STEP 3: Run F1 decompositions (4 specs)")
message("================================================================")

specs <- list(
  list(option = "A2", denom = "V1", cell = cell_A2_long,
       all_b = bins_A2$all, active = bins_A2$active, output = bins_A2$active),
  list(option = "A2", denom = "V2", cell = cell_A2_long,
       all_b = bins_A2$all, active = bins_A2$active, output = bins_A2$active),
  list(option = "A3", denom = "V1", cell = cell_A3_long,
       all_b = bins_A3$all, active = bins_A3$active, output = bins_A3$active),
  list(option = "A3", denom = "V2", cell = cell_A3_long,
       all_b = bins_A3$all, active = bins_A3$active, output = bins_A3$active)
)

results <- vector("list", length(specs))

for (i in seq_along(specs)) {
  sp <- specs[[i]]
  margin_label <- sprintf("%s_size_x_sec", sp$option)
  message(sprintf("\n  Spec %d/4: option=%s denom=%s (%d active bins)",
                  i, sp$option, sp$denom, length(sp$active)))

  long_dt <- f1_decompose(
    cell_dt      = sp$cell,
    margin_label = margin_label,
    all_bins     = sp$all_b,
    active_bins  = sp$active,
    output_bins  = sp$output,
    denom_label  = sp$denom
  )

  decomp_dt <- compute_decomposition(long_dt)
  summary_dt <- compute_summary(decomp_dt)

  # Annotate with cnae_section and size_bin parts for vs_round1 join
  decomp_dt[, cnae_section := sub("_[0-9]+$", "", bin)]
  decomp_dt[, size_bin_int := as.integer(sub("^.*_", "", bin))]

  # vs_round1: join on (denom, cnae_section)
  vs_r1 <- merge(
    decomp_dt[, .(option = sp$option, denom, bin, cnae_section, size_bin_int,
                  n_munis_with_sigma, mean_share_overall,
                  share_within, med_sigma_within)],
    round1_cnae[denom == sp$denom],
    by = c("denom", "cnae_section"),
    all.x = TRUE
  )
  vs_r1[, delta_share_within     := share_within     - round1_share_within]
  vs_r1[, delta_med_sigma_within := med_sigma_within - round1_med_sigma_within]

  setcolorder(vs_r1, c(
    "option", "denom", "bin", "cnae_section", "size_bin_int",
    "n_munis_with_sigma", "mean_share_overall",
    "share_within",     "round1_share_within",     "delta_share_within",
    "med_sigma_within", "round1_med_sigma_within", "delta_med_sigma_within",
    "round1_n_munis", "round1_mean_share"
  ))

  # Strip helper cols from decomp output
  decomp_out <- decomp_dt[, .(margin, denom, bin,
                              n_obs, n_munis, n_munis_with_sigma,
                              mean_share_overall,
                              total_var, between_muni_var, within_muni_var,
                              share_within,
                              p10_sigma_within, med_sigma_within, p90_sigma_within)]

  decomp_path  <- file.path(OUTPUT_DIR,
    sprintf("f1_option%s_%s_decomposition.csv", sp$option, sp$denom))
  summary_path <- file.path(OUTPUT_DIR,
    sprintf("f1_option%s_%s_summary.csv",       sp$option, sp$denom))
  vs_path      <- file.path(OUTPUT_DIR,
    sprintf("f1_option%s_%s_vs_round1.csv",     sp$option, sp$denom))

  fwrite(decomp_out, decomp_path)
  fwrite(summary_dt, summary_path)
  fwrite(vs_r1,      vs_path)

  message(sprintf("    Verdict: %s | mean share_within = %.4f | med = %.4f | n_supported = %d / %d",
                  summary_dt$verdict,
                  summary_dt$mean_share_within_across_bins,
                  summary_dt$med_share_within_across_bins,
                  summary_dt$n_bins_supported,
                  summary_dt$n_bins_total))
  message(sprintf("    Written: %s", basename(decomp_path)))
  message(sprintf("    Written: %s", basename(summary_path)))
  message(sprintf("    Written: %s", basename(vs_path)))

  results[[i]] <- list(
    option = sp$option, denom = sp$denom,
    decomp = decomp_out, summary = summary_dt, vs_r1 = vs_r1
  )

  invisible(gc())
}

# ------------------------------------------------------------------------------
# 10. Combined report
# ------------------------------------------------------------------------------
message("\n================================================================")
message("  STEP 4: Writing combined report")
message("================================================================")

fmt_num <- function(x, d = 4) {
  ifelse(is.na(x), "—", sprintf(paste0("%.", d, "f"), x))
}
fmt_int <- function(x) {
  ifelse(is.na(x), "—", format(as.integer(x), big.mark = ","))
}

# Round-1 summary stats (for headline comparison)
round1_summary <- round1_dt[
  margin %in% c("cnae_section", "policy_block", "policy_block_active"),
  .(
    mean_share_within  = mean(share_within, na.rm = TRUE),
    med_share_within   = stats::median(share_within, na.rm = TRUE),
    mean_med_sigma     = mean(med_sigma_within, na.rm = TRUE),
    med_med_sigma      = stats::median(med_sigma_within, na.rm = TRUE),
    n_bins             = .N
  ),
  by = .(margin, denom)
]

# Build per-spec summary rows
all_summaries <- rbindlist(lapply(results, function(r) r$summary))

# Selection rule (plan §8): pick highest mean share_within across bins (V1 primary)
v1_summaries <- all_summaries[denom == "V1"]
setorder(v1_summaries, -mean_share_within_across_bins)
top_v1 <- v1_summaries[1L]
runner_v1 <- if (nrow(v1_summaries) >= 2L) v1_summaries[2L] else NULL

# Tiebreaker per brief: if Δ < 0.05, prefer A3 over A2 (granularity)
delta_v1 <- if (!is.null(runner_v1)) {
  top_v1$mean_share_within_across_bins - runner_v1$mean_share_within_across_bins
} else NA_real_

if (!is.na(delta_v1) && abs(delta_v1) < 0.05) {
  # Tiebreaker: prefer A3
  has_a3 <- "A3_size_x_sec" %in% v1_summaries$margin
  winner_margin <- if (has_a3) "A3_size_x_sec" else top_v1$margin
  tiebreaker_applied <- TRUE
} else {
  winner_margin <- top_v1$margin
  tiebreaker_applied <- FALSE
}
winner_option <- sub("_size_x_sec$", "", winner_margin)

# Sanity: ensure both V1 and V2 verdicts agree for the winner
winner_v1 <- all_summaries[margin == winner_margin & denom == "V1"]
winner_v2 <- all_summaries[margin == winner_margin & denom == "V2"]
verdict_agree <- nrow(winner_v1) == 1L && nrow(winner_v2) == 1L &&
  winner_v1$verdict == winner_v2$verdict

# Round-1 reproduction headline
repro_status <- "PASS"
repro_note <- sprintf(
  "All %d (margin x denom x bin) cells within tolerance (|Δshare_within| <= %g, |Δmed_σ_within| <= %g).",
  nrow(fread(repro_pass_path)), REPRO_TOL_SHARE, REPRO_TOL_SIGMA
)

# Compose markdown
report_lines <- c(
  "# E3: F1 Within-Muni Variance Decomposition — A2 vs. A3 (V1 primary, V2 robustness)",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Goal",
  "",
  "Decide whether the size x sector aggregation margin (A2 = MPME/Big, ",
  "A3 = MPME/Media/Grande) adds identifying within-muni x time variation ",
  "beyond the round-1 `cnae_section`-only margin. Run V1 (active-only ",
  "denominator, primary) and V2 (full-economy denominator, robustness) for ",
  "both A2 and A3 — four spec runs.",
  "",
  paste0("**SUPPORTED rule:** at least one bin has cross-muni median ",
         "sigma_within > ", F1_SIGMA_MEDIAN_MIN,
         " AND share_within > ", F1_SHARE_WITHIN_MIN, "."),
  "",
  "---",
  "",
  "## 1. Round-1 reproduction gate",
  "",
  paste0("**Status: ", repro_status, "**"),
  "",
  repro_note,
  "",
  paste0("This confirms the refactored `f1_decompose()` reproduces the ",
         "round-1 numbers in `variation_decomposition.csv` for `cnae_section` ",
         "and `policy_block` x {V1, V2} on the same source data. A2/A3 ",
         "outputs below are therefore directly comparable to round 1."),
  "",
  "---",
  "",
  "## 2. Per-spec verdicts",
  "",
  "| Margin | Denom | Verdict | n_bins | n_supported | mean share_within | med share_within | max share_within | med med σ_within |",
  "|--------|-------|---------|--------|-------------|-------------------|------------------|------------------|------------------|"
)

for (i in seq_len(nrow(all_summaries))) {
  r <- all_summaries[i]
  report_lines <- c(report_lines, sprintf(
    "| %s | %s | %s | %d | %d | %s | %s | %s | %s |",
    r$margin, r$denom, r$verdict,
    r$n_bins_total, r$n_bins_supported,
    fmt_num(r$mean_share_within_across_bins, 4),
    fmt_num(r$med_share_within_across_bins,  4),
    fmt_num(r$max_share_within,              4),
    fmt_num(r$med_med_sigma_within,          4)
  ))
}

# Head-to-head vs round 1
report_lines <- c(report_lines,
  "",
  "---",
  "",
  "## 3. Head-to-head: A2 / A3 vs. round-1 baselines",
  "",
  "Round-1 reference (from `variation_decomposition.csv`):",
  "",
  "| Margin | Denom | n_bins | mean share_within | med share_within | mean med σ | med med σ |",
  "|--------|-------|--------|-------------------|------------------|-----------|-----------|"
)

for (i in seq_len(nrow(round1_summary))) {
  r <- round1_summary[i]
  report_lines <- c(report_lines, sprintf(
    "| %s | %s | %d | %s | %s | %s | %s |",
    r$margin, r$denom, r$n_bins,
    fmt_num(r$mean_share_within, 4),
    fmt_num(r$med_share_within,  4),
    fmt_num(r$mean_med_sigma,    4),
    fmt_num(r$med_med_sigma,     4)
  ))
}

report_lines <- c(report_lines,
  "",
  "Size x sector candidates (this run):",
  "",
  "| Margin | Denom | n_bins | mean share_within | med share_within | mean med σ | med med σ |",
  "|--------|-------|--------|-------------------|------------------|-----------|-----------|"
)

# Per-spec A2/A3 mean med sigma across bins
for (r in results) {
  d  <- r$decomp
  sm <- r$summary
  mean_sigma <- mean(d$med_sigma_within, na.rm = TRUE)
  med_sigma  <- stats::median(d$med_sigma_within, na.rm = TRUE)
  report_lines <- c(report_lines, sprintf(
    "| %s | %s | %d | %s | %s | %s | %s |",
    sm$margin, sm$denom, sm$n_bins_total,
    fmt_num(sm$mean_share_within_across_bins, 4),
    fmt_num(sm$med_share_within_across_bins,  4),
    fmt_num(mean_sigma, 4),
    fmt_num(med_sigma,  4)
  ))
}

# Interpretation
report_lines <- c(report_lines,
  "",
  "---",
  "",
  "## 4. Interpretation: does size x sector add identifying variation?",
  ""
)

for (opt in c("A2", "A3")) {
  v1_row <- all_summaries[margin == sprintf("%s_size_x_sec", opt) & denom == "V1"]
  v2_row <- all_summaries[margin == sprintf("%s_size_x_sec", opt) & denom == "V2"]

  r1_cnae_v1 <- round1_summary[margin == "cnae_section" & denom == "V1"]
  r1_cnae_v2 <- round1_summary[margin == "cnae_section" & denom == "V2"]

  delta_mean_v1 <- v1_row$mean_share_within_across_bins -
                   r1_cnae_v1$mean_share_within
  delta_mean_v2 <- v2_row$mean_share_within_across_bins -
                   r1_cnae_v2$mean_share_within

  report_lines <- c(report_lines,
    sprintf("### Option %s", opt),
    "",
    sprintf("- V1 verdict: **%s**, %d / %d bins SUPPORTED, mean share_within = %s.",
            v1_row$verdict, v1_row$n_bins_supported, v1_row$n_bins_total,
            fmt_num(v1_row$mean_share_within_across_bins, 4)),
    sprintf("- V2 verdict: **%s**, %d / %d bins SUPPORTED, mean share_within = %s.",
            v2_row$verdict, v2_row$n_bins_supported, v2_row$n_bins_total,
            fmt_num(v2_row$mean_share_within_across_bins, 4)),
    sprintf("- Delta vs. round-1 cnae_section (V1): %s",
            fmt_num(delta_mean_v1, 4)),
    sprintf("- Delta vs. round-1 cnae_section (V2): %s",
            fmt_num(delta_mean_v2, 4)),
    if (!is.na(delta_mean_v1) && delta_mean_v1 >= -0.05) {
      paste0("- Conclusion: under V1, %s preserves or improves on round-1's ",
             "section-only mean within-share; the size x sector decomposition ",
             "is a viable production margin." ) |>
        sprintf(opt)
    } else {
      sprintf(paste0("- Conclusion: under V1, %s loses identifying mean ",
                     "share_within vs round-1 by more than the 0.05 ",
                     "tolerance — caveat the loss when reporting."), opt)
    },
    ""
  )
}

# Selection rule
report_lines <- c(report_lines,
  "---",
  "",
  "## 5. Selection rule (plan §8)",
  "",
  "Plan §8: pick the candidate with highest mean `share_within` across bins (V1 primary).",
  "",
  sprintf("- Top by V1 mean share_within: **%s** (mean = %s).",
          top_v1$margin,
          fmt_num(top_v1$mean_share_within_across_bins, 4)),
  if (!is.null(runner_v1)) {
    sprintf("- Runner-up: %s (mean = %s); delta = %s.",
            runner_v1$margin,
            fmt_num(runner_v1$mean_share_within_across_bins, 4),
            fmt_num(delta_v1, 4))
  } else "",
  if (tiebreaker_applied) {
    paste0("- Tiebreaker (|delta| < 0.05): plan §8 prefers A4 > A3 > B; ",
           "deviation here — A2 was not in the original plan, so prefer ",
           "A3 over A2 for granularity (3 size bins > 2). Documented choice.")
  } else {
    "- No tiebreaker triggered; gap >= 0.05."
  },
  "",
  sprintf("- V1 / V2 verdict agreement for winner: %s",
          if (verdict_agree) "YES (consistent)." else "NO — flag for re-inspection."),
  "",
  sprintf("**Final winner: %s** (option %s).", winner_margin, winner_option),
  "",
  "Caveats:",
  "- A2 was added to the candidate set after E2 with user input; the plan's ",
  "  original scope was {A4, A3, B}.",
  "- E2 nominally FAILED A3's Media and Grande bins on coverage; user opted ",
  "  to keep A3 in E3 since V1 / active-only renormalization makes the IV ",
  "  mechanic valid even with thin coverage (thin bins simply contribute ",
  "  less to identification per muni).",
  "- V2 (full-economy denominator including KOTU) is reported as robustness; ",
  "  V1 wins the tiebreaker on any disagreement.",
  "",
  "---",
  "",
  "## 6. Files written",
  "",
  "| File | Description |",
  "|------|-------------|",
  "| `f1_round1_reproduction_PASS.csv` | Cell-level reproduction check vs. round 1 |",
  "| `f1_optionA2_V1_decomposition.csv` | Per-bin variance decomposition, A2 V1 |",
  "| `f1_optionA2_V1_summary.csv` | Spec-level summary + verdict, A2 V1 |",
  "| `f1_optionA2_V1_vs_round1.csv` | Per-bin comparison to round-1 cnae_section |",
  "| `f1_optionA2_V2_decomposition.csv` | A2 V2 |",
  "| `f1_optionA2_V2_summary.csv` | A2 V2 |",
  "| `f1_optionA2_V2_vs_round1.csv` | A2 V2 vs round 1 |",
  "| `f1_optionA3_V1_decomposition.csv` | A3 V1 |",
  "| `f1_optionA3_V1_summary.csv` | A3 V1 |",
  "| `f1_optionA3_V1_vs_round1.csv` | A3 V1 vs round 1 |",
  "| `f1_optionA3_V2_decomposition.csv` | A3 V2 |",
  "| `f1_optionA3_V2_summary.csv` | A3 V2 |",
  "| `f1_optionA3_V2_vs_round1.csv` | A3 V2 vs round 1 |",
  "| `f1_combined_report.md` | This file |",
  ""
)

# Drop empty strings from conditional inserts
report_lines <- report_lines[!is.na(report_lines) & nchar(report_lines) >= 0L]

writeLines(report_lines, file.path(OUTPUT_DIR, "f1_combined_report.md"))
message(sprintf("  Written: %s", file.path(OUTPUT_DIR, "f1_combined_report.md")))

# ------------------------------------------------------------------------------
# 11. Console summary
# ------------------------------------------------------------------------------
message("\n================================================================")
message("  E3: F1 size x sector decomposition — Summary")
message("================================================================")
message(sprintf("  Round-1 reproduction: %s", repro_status))
message("")
message("  Per-spec verdicts:")
for (i in seq_len(nrow(all_summaries))) {
  r <- all_summaries[i]
  message(sprintf("    %-20s %s : %-12s | mean share_within = %.4f | n_supported = %d / %d",
                  r$margin, r$denom, r$verdict,
                  r$mean_share_within_across_bins,
                  r$n_bins_supported, r$n_bins_total))
}
message("")
message(sprintf("  Final recommended margin: %s (option %s)",
                winner_margin, winner_option))
message(sprintf("  V1/V2 verdict agreement (winner): %s",
                if (verdict_agree) "YES" else "NO"))
message("")
message("  Output files written to:")
message("    ", OUTPUT_DIR)
message("================================================================")

invisible(list(
  repro_status   = repro_status,
  results        = results,
  winner_margin  = winner_margin,
  winner_option  = winner_option,
  verdict_agree  = verdict_agree
))
