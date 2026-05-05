# ==============================================================================
# 03c_policy_block_size_f1.R
#
# E3c (companion to E3): F1 within-muni variance decomposition for the
# policy_block × size margin (4 active blocks × {A2, A3} sizes), under V1 and V2.
#
# Goal: compare a coarser sector dimension (policy_block, 4 active blocks) crossed
# with size (A2 or A3) against the finer cnae_section × size results from E3.
# Active bin counts: A2 → 4×2 = 8; A3 → 4×3 = 12. Much fatter cells.
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst
#   data/processed/policy_block_mapping.qs2
#   explorations/anderson_rubin/diagnostics/output/coverage_cells_optionA2.csv
#   explorations/anderson_rubin/diagnostics/output/coverage_cells_optionA3.csv
#
# Outputs (explorations/anderson_rubin/diagnostics/output/):
#   f1_policy_block_A2_V1_decomposition.csv
#   f1_policy_block_A2_V2_decomposition.csv
#   f1_policy_block_A3_V1_decomposition.csv
#   f1_policy_block_A3_V2_decomposition.csv
#   f1_policy_block_size_summary.csv
#   f1_policy_block_size_report.md
# ==============================================================================

library(data.table)
library(qs2)
library(here)
library(fst)

setDTthreads(0L)

OUT  <- here::here("explorations", "anderson_rubin", "diagnostics", "output")
PROC <- here::here("data", "processed")

ACTIVE_BLOCKS <- c("Agro", "Ind", "Infra", "Serv")
ALL_BLOCKS    <- c("Agro", "Ind", "Infra", "Serv", "XX")
F1_SIGMA_MIN  <- 0.05
F1_SHARE_MIN  <- 0.20
F1_REJECT_BELOW <- 0.10

# ------------------------------------------------------------------------------
# 1. Load policy_block crosswalk and size-cell tables
# ------------------------------------------------------------------------------
cw <- setDT(qs_read(file.path(PROC, "policy_block_mapping.qs2")))
stopifnot(all(c("cnae_section", "policy_block") %in% names(cw)))

cells_A2 <- fread(file.path(OUT, "coverage_cells_optionA2.csv"))
cells_A3 <- fread(file.path(OUT, "coverage_cells_optionA3.csv"))

# Merge in policy_block; collapse to (size_bin, policy_block, muni, year)
collapse_to_block <- function(cells, size_levels) {
  m <- merge(cells, cw[, .(cnae_section, policy_block)],
             by = "cnae_section", all.x = TRUE)
  m <- m[!is.na(policy_block)]
  m[, .(L = sum(L_total, na.rm = TRUE),
        n_borrowers = sum(n_borrowers, na.rm = TRUE),
        n_firms = sum(n_firms, na.rm = TRUE)),
    by = .(size_bin, policy_block, muni_id, year)]
}

cells_blk_A2 <- collapse_to_block(cells_A2, 1:2)
cells_blk_A3 <- collapse_to_block(cells_A3, 1:3)

# ------------------------------------------------------------------------------
# 2. f1_decompose — copied from E3 logic (mirrors within_muni_variation.R math)
# ------------------------------------------------------------------------------
f1_decompose <- function(cells, all_bins, active_bins) {
  # cells has columns: muni_id, year, bin, L
  totals <- cells[, .(total_full   = sum(L, na.rm = TRUE),
                       total_active = sum(L[bin %in% active_bins], na.rm = TRUE)),
                   by = .(muni_id, year)]
  totals <- totals[total_full > 0]

  dense_keys <- totals[, .(bin = all_bins), by = .(muni_id, year)]
  dense <- merge(dense_keys, totals, by = c("muni_id", "year"))
  dense <- merge(dense, cells[, .(muni_id, year, bin, L)],
                 by = c("muni_id", "year", "bin"), all.x = TRUE)
  dense[is.na(L), L := 0]

  is_active <- dense$bin %in% active_bins
  dense[, s_v1 := fifelse(is_active & total_active > 0, L / total_active, NA_real_)]
  dense[, s_v2 := L / total_full]

  long_v1 <- dense[bin %in% active_bins,
                    .(denom = "V1", muni_id, year, bin, share = s_v1)]
  long_v2 <- dense[bin %in% active_bins,
                    .(denom = "V2", muni_id, year, bin, share = s_v2)]
  rbind(long_v1, long_v2)
}

decompose_long <- function(long_dt) {
  by_muni <- long_dt[!is.na(share),
                      .(n_years = .N,
                        mean_share = mean(share),
                        sigma_within = if (.N >= 2L) stats::sd(share) else NA_real_),
                      by = .(denom, muni_id, bin)]

  shares_with_means <- merge(long_dt[!is.na(share)],
                              by_muni[, .(denom, muni_id, bin, mean_share)],
                              by = c("denom", "muni_id", "bin"))
  shares_with_means[, residual := share - mean_share]

  decomp_core <- shares_with_means[, .(
    n_obs = .N,
    n_munis = uniqueN(muni_id),
    mean_share_overall = mean(share),
    total_var      = if (.N >= 2L) stats::var(share)    else NA_real_,
    within_muni_var = if (.N >= 2L) stats::var(residual) else NA_real_
  ), by = .(denom, bin)]

  between_var <- by_muni[, .(
    between_muni_var = if (.N >= 2L) stats::var(mean_share) else NA_real_
  ), by = .(denom, bin)]

  decomp <- merge(decomp_core, between_var, by = c("denom", "bin"))
  decomp[, share_within := fifelse(!is.na(total_var) & total_var > 0,
                                    within_muni_var / total_var, NA_real_)]

  qs <- by_muni[!is.na(sigma_within), {
    q <- stats::quantile(sigma_within, probs = c(0.10, 0.50, 0.90),
                         names = FALSE)
    .(p10_sigma_within = q[1], med_sigma_within = q[2], p90_sigma_within = q[3],
      n_munis_with_sigma = .N)
  }, by = .(denom, bin)]

  merge(decomp, qs, by = c("denom", "bin"), all.x = TRUE)
}

# ------------------------------------------------------------------------------
# 3. Build size_x_block bins and decompose
# ------------------------------------------------------------------------------
run_one <- function(cells_blk, size_levels, label) {
  cells_blk[, bin := paste(policy_block, size_bin, sep = "_")]
  all_bins    <- as.vector(outer(ALL_BLOCKS,    size_levels, paste, sep = "_"))
  active_bins <- as.vector(outer(ACTIVE_BLOCKS, size_levels, paste, sep = "_"))

  long <- f1_decompose(cells_blk, all_bins, active_bins)
  decomp <- decompose_long(long)

  decomp_v1 <- decomp[denom == "V1"]
  decomp_v2 <- decomp[denom == "V2"]
  fwrite(decomp_v1, file.path(OUT, sprintf("f1_policy_block_%s_V1_decomposition.csv", label)))
  fwrite(decomp_v2, file.path(OUT, sprintf("f1_policy_block_%s_V2_decomposition.csv", label)))

  list(label = label, decomp_v1 = decomp_v1, decomp_v2 = decomp_v2)
}

res_A2 <- run_one(cells_blk_A2, 1:2, "A2")
res_A3 <- run_one(cells_blk_A3, 1:3, "A3")

# ------------------------------------------------------------------------------
# 4. Summary
# ------------------------------------------------------------------------------
summarize <- function(decomp, option, denom) {
  d <- decomp[!is.na(share_within)]
  data.table(
    option = option, denom = denom,
    n_bins = nrow(decomp),
    n_supported = decomp[!is.na(med_sigma_within) & !is.na(share_within) &
                          med_sigma_within > F1_SIGMA_MIN &
                          share_within > F1_SHARE_MIN, .N],
    max_share_within = if (nrow(d)) max(d$share_within) else NA_real_,
    mean_share_within = if (nrow(d)) mean(d$share_within) else NA_real_,
    med_share_within = if (nrow(d)) stats::median(d$share_within) else NA_real_,
    max_med_sigma = if (any(!is.na(decomp$med_sigma_within)))
                       max(decomp$med_sigma_within, na.rm = TRUE) else NA_real_,
    med_med_sigma = if (any(!is.na(decomp$med_sigma_within)))
                       stats::median(decomp$med_sigma_within, na.rm = TRUE) else NA_real_,
    verdict = NA_character_
  )
}

summary_dt <- rbindlist(list(
  summarize(res_A2$decomp_v1, "policy_block_A2", "V1"),
  summarize(res_A2$decomp_v2, "policy_block_A2", "V2"),
  summarize(res_A3$decomp_v1, "policy_block_A3", "V1"),
  summarize(res_A3$decomp_v2, "policy_block_A3", "V2")
))

summary_dt[, verdict := fcase(
  n_supported >= 1L, "SUPPORTED",
  is.na(max_share_within), "INCONCLUSIVE",
  max_share_within < F1_REJECT_BELOW, "REJECTED",
  default = "INCONCLUSIVE"
)]

fwrite(summary_dt, file.path(OUT, "f1_policy_block_size_summary.csv"))

# ------------------------------------------------------------------------------
# 5. Report
# ------------------------------------------------------------------------------
fmt_n <- function(x, d = 3) ifelse(is.na(x), "—", sprintf(paste0("%.", d, "f"), x))

report <- c(
  "# E3c — F1 Decomposition for `policy_block × size` margin",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "Coarser sector dimension (policy_block, 4 active blocks: Agro/Ind/Infra/Serv) ",
  "crossed with A2 (2 sizes) or A3 (3 sizes). Active bins:",
  "",
  "- policy_block × A2 → 8 active bins",
  "- policy_block × A3 → 12 active bins",
  "",
  "Compared to E3 (`cnae_section × size`): 17×{2,3} = {34, 51} active bins.",
  "",
  "## Per-spec summary",
  "",
  "| Option | Denom | n_bins | n_supported | mean share_within | med share_within | max med σ | verdict |",
  "|--------|-------|-------:|------------:|-----------------:|----------------:|----------:|---------|",
  vapply(seq_len(nrow(summary_dt)), function(i) {
    r <- summary_dt[i]
    sprintf("| %s | %s | %d | %d | %s | %s | %s | %s |",
            r$option, r$denom, r$n_bins, r$n_supported,
            fmt_n(r$mean_share_within), fmt_n(r$med_share_within),
            fmt_n(r$max_med_sigma), r$verdict)
  }, character(1L)),
  "",
  "## Comparison to E3 (cnae_section × size)",
  "",
  "From `f1_combined_report.md`:",
  "- cnae_section × A2 V1: mean share_within = 0.755, med = 0.799",
  "- cnae_section × A3 V1: mean share_within = 0.769, med = 0.808",
  "",
  "## Comparison to round 1 (sector-only)",
  "",
  "From `variation_decomposition.csv`:",
  "- policy_block × V1 (5 bins, includes XX): see round 1",
  "- policy_block_active × V1 (4 bins): see round 1",
  "",
  "## Implication",
  "",
  "Coarser sector × finer size produces fatter cells but loses sector granularity. ",
  "If `mean share_within` here is comparable to E3 (within ~0.05), the policy_block ",
  "× size margin is preferable for production: same identification with much fewer ",
  "instruments and less coverage risk.",
  ""
)
writeLines(report, file.path(OUT, "f1_policy_block_size_report.md"))

# Console
message("\n=== E3c summary ===")
for (i in seq_len(nrow(summary_dt))) {
  r <- summary_dt[i]
  message(sprintf("  %s %s: n_bins=%d, n_supported=%d, mean share_within=%s, max med σ=%s, verdict=%s",
                  r$option, r$denom, r$n_bins, r$n_supported,
                  fmt_n(r$mean_share_within), fmt_n(r$max_med_sigma), r$verdict))
}
