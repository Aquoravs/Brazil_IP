# ==============================================================================
# 04_standalone_size_f1.R
#
# F1 within-muni × time variance decomposition for STANDALONE size margins
# (no sector cross). Tests whether the share of BNDES credit going to each
# size bin varies within municipalities over time.
#
# Foundation under test (docs/PROJECT_BLUEPRINT.md, F1):
#   "For at least one F0-margin, BNDES credit shares have meaningful
#    within-muni × time variation."
#   Standalone size is the third F0-admissible margin family, after
#   CNAE-based (round 1, D15) and CNAE × size (round 2, D16).
#
# Size classifiers (S-prefix, per D19):
#   S3 — 3-bin: MPME (0–49) / Media (50–499) / Grande (500+)
#   S4 — 4-bin: Micro (0–9) / Pequena (10–49) / Media (50–499) / Grande (500+)
#
# Denominator: single definition — all size bins sum to 1 within each
# muni-year. The V1/V2 distinction (active-only vs. full-economy) is
# sector-specific and does not apply to standalone size.
#
# Inputs:
#   explorations/anderson_rubin/diagnostics/output/coverage_cells_optionA3.csv
#   explorations/anderson_rubin/diagnostics/output/coverage_cells_optionA4.csv
#   explorations/anderson_rubin/diagnostics/output/variation_decomposition.csv
#   explorations/anderson_rubin/diagnostics/output/f1_policy_block_size_summary.csv
#
# Outputs (explorations/anderson_rubin/diagnostics/output/):
#   f1_standalone_S3_decomposition.csv
#   f1_standalone_S4_decomposition.csv
#   f1_standalone_size_summary.csv
#   f1_standalone_size_report.md
# ==============================================================================

library(data.table)
library(here)

setDTthreads(0L)

OUT <- here::here("explorations", "anderson_rubin", "diagnostics", "output")

S3_LABELS <- c("MPME", "Media", "Grande")
S4_LABELS <- c("Micro", "Pequena", "Media", "Grande")

F1_SIGMA_MIN    <- 0.05
F1_SHARE_MIN    <- 0.20
F1_REJECT_BELOW <- 0.10

# ------------------------------------------------------------------------------
# 1. Load coverage cells (pre-computed by 02_size_bin_coverage.R, T3 applied)
# ------------------------------------------------------------------------------
path_S3 <- file.path(OUT, "coverage_cells_optionA3.csv")
path_S4 <- file.path(OUT, "coverage_cells_optionA4.csv")

stopifnot(file.exists(path_S3), file.exists(path_S4))

message("Loading coverage cells...")
cells_S3 <- fread(path_S3)
cells_S4 <- fread(path_S4)

for (dt in list(cells_S3, cells_S4)) {
  dt[, muni_id  := as.character(muni_id)]
  dt[, year     := as.integer(year)]
  dt[, size_bin := as.integer(size_bin)]
}

# Collapse across cnae_section → standalone size
standalone_S3 <- cells_S3[
  !is.na(size_bin),
  .(L = sum(L_total, na.rm = TRUE)),
  by = .(muni_id, year, bin = as.character(size_bin))
]

standalone_S4 <- cells_S4[
  !is.na(size_bin),
  .(L = sum(L_total, na.rm = TRUE)),
  by = .(muni_id, year, bin = as.character(size_bin))
]

message(sprintf("  S3 standalone: %s rows, %s munis, years %d–%d",
                format(nrow(standalone_S3), big.mark = ","),
                format(uniqueN(standalone_S3$muni_id), big.mark = ","),
                min(standalone_S3$year), max(standalone_S3$year)))
message(sprintf("  S4 standalone: %s rows, %s munis, years %d–%d",
                format(nrow(standalone_S4), big.mark = ","),
                format(uniqueN(standalone_S4$muni_id), big.mark = ","),
                min(standalone_S4$year), max(standalone_S4$year)))

rm(cells_S3, cells_S4); invisible(gc())

# ------------------------------------------------------------------------------
# 2. Variance decomposition
# ------------------------------------------------------------------------------
decompose_standalone <- function(cell_dt, all_bins, margin_label) {

  totals <- cell_dt[, .(total = sum(L, na.rm = TRUE)), by = .(muni_id, year)]
  totals <- totals[total > 0]

  dense_keys <- totals[, .(bin = all_bins), by = .(muni_id, year)]
  dense <- merge(dense_keys, totals, by = c("muni_id", "year"))
  dense <- merge(dense, cell_dt, by = c("muni_id", "year", "bin"), all.x = TRUE)
  dense[is.na(L), L := 0]

  dense[, share := L / total]

  by_muni <- dense[
    !is.na(share),
    .(n_years      = .N,
      mean_share   = mean(share),
      sigma_within = if (.N >= 2L) stats::sd(share) else NA_real_),
    by = .(muni_id, bin)
  ]

  shares_with_means <- merge(
    dense[!is.na(share)],
    by_muni[, .(muni_id, bin, mean_share)],
    by = c("muni_id", "bin")
  )
  shares_with_means[, residual := share - mean_share]

  decomp_core <- shares_with_means[, .(
    n_obs              = .N,
    n_munis            = uniqueN(muni_id),
    mean_share_overall = mean(share),
    total_var          = if (.N >= 2L) stats::var(share)    else NA_real_,
    within_muni_var    = if (.N >= 2L) stats::var(residual) else NA_real_
  ), by = bin]

  between_var <- by_muni[, .(
    between_muni_var = if (.N >= 2L) stats::var(mean_share) else NA_real_
  ), by = bin]

  decomp <- merge(decomp_core, between_var, by = "bin")
  decomp[, share_within := fifelse(
    !is.na(total_var) & total_var > 0,
    within_muni_var / total_var,
    NA_real_
  )]

  qs <- by_muni[!is.na(sigma_within), {
    q <- stats::quantile(sigma_within, probs = c(0.10, 0.50, 0.90),
                         names = FALSE)
    .(p10_sigma_within   = q[1],
      med_sigma_within   = q[2],
      p90_sigma_within   = q[3],
      n_munis_with_sigma = .N)
  }, by = bin]

  decomp <- merge(decomp, qs, by = "bin", all.x = TRUE)

  decomp[, margin := margin_label]
  decomp[, denom  := "all"]

  setcolorder(decomp, c(
    "margin", "denom", "bin",
    "n_obs", "n_munis", "n_munis_with_sigma",
    "mean_share_overall",
    "total_var", "between_muni_var", "within_muni_var", "share_within",
    "p10_sigma_within", "med_sigma_within", "p90_sigma_within"
  ))

  decomp[]
}

message("\nRunning variance decomposition...")

decomp_S3 <- decompose_standalone(standalone_S3, as.character(1:3), "standalone_S3")
decomp_S4 <- decompose_standalone(standalone_S4, as.character(1:4), "standalone_S4")

fwrite(decomp_S3, file.path(OUT, "f1_standalone_S3_decomposition.csv"))
fwrite(decomp_S4, file.path(OUT, "f1_standalone_S4_decomposition.csv"))

message("  S3 decomposition written.")
message("  S4 decomposition written.")

# ------------------------------------------------------------------------------
# 3. Summary and verdict
# ------------------------------------------------------------------------------
summarize_standalone <- function(decomp) {
  d <- decomp[!is.na(share_within)]
  data.table(
    margin            = decomp$margin[1L],
    denom             = "all",
    n_bins            = nrow(decomp),
    n_supported       = decomp[
      !is.na(med_sigma_within) & !is.na(share_within) &
        med_sigma_within > F1_SIGMA_MIN &
        share_within     > F1_SHARE_MIN, .N],
    max_share_within  = if (nrow(d)) max(d$share_within)             else NA_real_,
    mean_share_within = if (nrow(d)) mean(d$share_within)            else NA_real_,
    med_share_within  = if (nrow(d)) stats::median(d$share_within)   else NA_real_,
    max_med_sigma     = if (any(!is.na(decomp$med_sigma_within)))
                          max(decomp$med_sigma_within, na.rm = TRUE) else NA_real_,
    med_med_sigma     = if (any(!is.na(decomp$med_sigma_within)))
                          stats::median(decomp$med_sigma_within, na.rm = TRUE)
                        else NA_real_,
    verdict           = NA_character_
  )
}

summary_dt <- rbindlist(list(
  summarize_standalone(decomp_S3),
  summarize_standalone(decomp_S4)
))

summary_dt[, verdict := fcase(
  n_supported >= 1L,                              "SUPPORTED",
  is.na(max_share_within),                        "INCONCLUSIVE",
  max_share_within < F1_REJECT_BELOW,             "REJECTED",
  default                                          = "INCONCLUSIVE"
)]

fwrite(summary_dt, file.path(OUT, "f1_standalone_size_summary.csv"))
message("\n  Summary written.")

# ------------------------------------------------------------------------------
# 4. Comparison to round-1 and D16 margins
# ------------------------------------------------------------------------------
path_round1 <- file.path(OUT, "variation_decomposition.csv")
path_d16    <- file.path(OUT, "f1_policy_block_size_summary.csv")

comparison_rows <- list()

if (file.exists(path_round1)) {
  round1 <- fread(path_round1)
  for (m in c("cnae_section", "policy_block", "policy_block_active")) {
    for (d in c("V1", "V2")) {
      sub <- round1[margin == m & denom == d]
      if (nrow(sub) == 0L) next
      comparison_rows[[length(comparison_rows) + 1L]] <- data.table(
        margin = m, denom = d,
        n_bins = nrow(sub),
        mean_share_within = mean(sub$share_within, na.rm = TRUE),
        source = "round 1 sector-only (D15)"
      )
    }
  }
}

if (file.exists(path_d16)) {
  d16 <- fread(path_d16)
  for (i in seq_len(nrow(d16))) {
    r <- d16[i]
    comparison_rows[[length(comparison_rows) + 1L]] <- data.table(
      margin = r$option, denom = r$denom,
      n_bins = r$n_bins,
      mean_share_within = r$mean_share_within,
      source = "round 2 sector x size (D16)"
    )
  }
}

for (i in seq_len(nrow(summary_dt))) {
  r <- summary_dt[i]
  comparison_rows[[length(comparison_rows) + 1L]] <- data.table(
    margin = r$margin, denom = r$denom,
    n_bins = r$n_bins,
    mean_share_within = r$mean_share_within,
    source = "standalone size (this run)"
  )
}

comparison <- rbindlist(comparison_rows, fill = TRUE)

# ------------------------------------------------------------------------------
# 5. Report
# ------------------------------------------------------------------------------
fmt_n <- function(x, d = 4) {
  ifelse(is.na(x), "—", sprintf(paste0("%.", d, "f"), x))
}

report <- c(
  "# F1 Within-Muni Variance Decomposition — Standalone Size (S3, S4)",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Goal",
  "",
  "Test F1 (within-muni × time variation) on **standalone size margins** — the",
  "third F0-admissible margin family, after CNAE-based (round 1, D15) and",
  "CNAE × size (round 2, D16). Here the aggregation bins are size bins alone,",
  "with no sector cross.",
  "",
  "**Size classifiers (S-prefix per D19):**",
  "- S3: MPME (0–49) / Media (50–499) / Grande (500+) — 3 bins",
  "- S4: Micro (0–9) / Pequena (10–49) / Media (50–499) / Grande (500+) — 4 bins",
  "",
  "**Denominator:** single (all bins sum to 1; no XX exclusion applies to size).",
  "",
  sprintf("**SUPPORTED rule:** at least one bin with med σ_within > %g AND share_within > %g.",
          F1_SIGMA_MIN, F1_SHARE_MIN),
  "",
  "---",
  "",
  "## 1. Per-bin decomposition",
  "",
  "### S3 (3 bins: MPME / Media / Grande)",
  "",
  "| Bin | Label | n_munis | mean_share | total_var | share_within | med σ_within | p10 σ | p90 σ |",
  "|-----|-------|--------:|----------:|---------:|------------:|------------:|------:|------:|"
)

for (i in seq_len(nrow(decomp_S3))) {
  r <- decomp_S3[i]
  lbl <- S3_LABELS[as.integer(r$bin)]
  report <- c(report, sprintf(
    "| %s | %s | %s | %s | %s | %s | %s | %s | %s |",
    r$bin, lbl,
    format(r$n_munis, big.mark = ","),
    fmt_n(r$mean_share_overall),
    fmt_n(r$total_var, 6),
    fmt_n(r$share_within),
    fmt_n(r$med_sigma_within),
    fmt_n(r$p10_sigma_within),
    fmt_n(r$p90_sigma_within)
  ))
}

report <- c(report,
  "",
  "### S4 (4 bins: Micro / Pequena / Media / Grande)",
  "",
  "| Bin | Label | n_munis | mean_share | total_var | share_within | med σ_within | p10 σ | p90 σ |",
  "|-----|-------|--------:|----------:|---------:|------------:|------------:|------:|------:|"
)

for (i in seq_len(nrow(decomp_S4))) {
  r <- decomp_S4[i]
  lbl <- S4_LABELS[as.integer(r$bin)]
  report <- c(report, sprintf(
    "| %s | %s | %s | %s | %s | %s | %s | %s | %s |",
    r$bin, lbl,
    format(r$n_munis, big.mark = ","),
    fmt_n(r$mean_share_overall),
    fmt_n(r$total_var, 6),
    fmt_n(r$share_within),
    fmt_n(r$med_sigma_within),
    fmt_n(r$p10_sigma_within),
    fmt_n(r$p90_sigma_within)
  ))
}

report <- c(report,
  "",
  "---",
  "",
  "## 2. Summary verdicts",
  "",
  "| Margin | n_bins | n_supported | mean share_within | med share_within | max med σ | verdict |",
  "|--------|-------:|------------:|-----------------:|----------------:|----------:|---------|"
)

for (i in seq_len(nrow(summary_dt))) {
  r <- summary_dt[i]
  report <- c(report, sprintf(
    "| %s | %d | %d | %s | %s | %s | %s |",
    r$margin, r$n_bins, r$n_supported,
    fmt_n(r$mean_share_within), fmt_n(r$med_share_within),
    fmt_n(r$max_med_sigma), r$verdict
  ))
}

report <- c(report,
  "",
  "---",
  "",
  "## 3. Comparison to existing margins",
  "",
  "| Margin | Denom | n_bins | mean share_within | Source |",
  "|--------|-------|-------:|-----------------:|--------|"
)

for (i in seq_len(nrow(comparison))) {
  r <- comparison[i]
  report <- c(report, sprintf(
    "| %s | %s | %d | %s | %s |",
    r$margin, r$denom, r$n_bins,
    fmt_n(r$mean_share_within), r$source
  ))
}

report <- c(report,
  "",
  "---",
  "",
  "## 4. Interpretation",
  "",
  "### What this tests",
  "",
  "Standalone size margins collapse the sector dimension entirely — the IV",
  "projects alignment shocks onto size bins only. Compared to the production",
  "margin `policy_block_active × S3` (12 bins, mean share_within = 0.642),",
  "standalone S3 has 3 bins and S4 has 4 bins — a strictly coarser partition.",
  "",
  "### Key questions for downstream",
  "",
  "1. **K = 3–4 instruments.** BHJ (2022) many-sector asymptotics require a",
  "   growing number of sectors. With K = 3–4, standard SSIV inference may not",
  "   apply; however, the Anderson–Rubin test is valid with any number of",
  "   instruments.",
  "2. **Coverage improvement.** E2 flagged Media and Grande as thin when crossed",
  "   with sector. Standalone size aggregates across sectors, so cells should be",
  "   fatter. Whether this translates into broader muni coverage is reported above.",
  "3. **Institutional channel.** BNDES targets by porte (firm size), but the",
  "   political alignment mechanism (P1) may operate more through sectors than",
  "   size. This is an F4 question, not F1.",
  "",
  "### Caveats",
  "",
  "- T3 imputation: cells from `02_size_bin_coverage.R` — stated Micro/Pequena",
  "  unmatched loans imputed to MPME (S3 bin 1, S4 bins 1–2); stated",
  "  Media/Grande unmatched dropped.",
  "- S4 was dropped at E2 for the sector × size cross due to thin coverage.",
  "  Standalone aggregation across sectors may rescue it by fattening cells,",
  "  but the same structural thinness on Media and Grande persists.",
  "",
  "---",
  "",
  "## 5. Files written",
  "",
  "| File | Description |",
  "|------|-------------|",
  "| `f1_standalone_S3_decomposition.csv` | Per-bin variance decomposition, S3 |",
  "| `f1_standalone_S4_decomposition.csv` | Per-bin variance decomposition, S4 |",
  "| `f1_standalone_size_summary.csv` | Summary + verdict for S3 and S4 |",
  "| `f1_standalone_size_report.md` | This file |",
  ""
)

writeLines(report, file.path(OUT, "f1_standalone_size_report.md"))

# ------------------------------------------------------------------------------
# 6. Console summary
# ------------------------------------------------------------------------------
message("\n================================================================")
message("  Standalone size F1 summary")
message("================================================================")
for (i in seq_len(nrow(summary_dt))) {
  r <- summary_dt[i]
  message(sprintf("  %s: n_bins=%d, n_supported=%d, mean share_within=%s, max med σ=%s, verdict=%s",
                  r$margin, r$n_bins, r$n_supported,
                  fmt_n(r$mean_share_within), fmt_n(r$max_med_sigma), r$verdict))
}
message(sprintf("\nReport written: %s",
                file.path(OUT, "f1_standalone_size_report.md")))
message("================================================================")

invisible(list(
  decomp_S3  = decomp_S3,
  decomp_S4  = decomp_S4,
  summary    = summary_dt,
  comparison = comparison
))
