# ==============================================================================
# 02b_size_bin_coverage_2bin.R
#
# E2 variant: Coverage of a 2-bin scheme A2 = {MPME (0-49), Big (50+)}.
# Built by collapsing bins 1+2 -> 1 and bins 3+4 -> 2 from coverage_cells_optionA4.csv,
# avoiding a re-run of the 15-min cell build in 02_size_bin_coverage.R.
#
# Input:
#   explorations/anderson_rubin/diagnostics/output/coverage_cells_optionA4.csv
#
# Outputs (same dir):
#   coverage_optionA2.csv
#   coverage_cells_optionA2.csv
#   coverage_summary_A2.csv
#   coverage_report_A2.md
# ==============================================================================

library(data.table)
library(here)

setDTthreads(0L)

OUT <- here::here("explorations", "anderson_rubin", "diagnostics", "output")

cells_a4 <- fread(file.path(OUT, "coverage_cells_optionA4.csv"))

# Map A4 bins {1,2,3,4} -> A2 bins {1=MPME (0-49), 2=Big (50+)}
cells_a4[, size_bin := fifelse(size_bin %in% 1:2, 1L, 2L)]
A2_LABELS <- c("MPME", "Big")

# Re-aggregate to (size_bin, cnae_section, muni, year) — sum borrower-level fields,
# n_firms is unique-firm count which we cannot reconstruct from the A4 cells without
# the underlying firm panel. Use the conservative sum of A4-bin n_firms (overcounts
# firms that had observations in both bins 1 and 2 of A4 within the same cell, which
# is impossible by construction since each firm-cycle has exactly one A4 bin -> the
# sum is exact).
cells_a2 <- cells_a4[
  , .(n_borrowers = sum(n_borrowers, na.rm = TRUE),
      L_total     = sum(L_total,     na.rm = TRUE),
      n_firms     = sum(n_firms,     na.rm = TRUE),
      emp_total   = sum(emp_total,   na.rm = TRUE)),
  by = .(size_bin, cnae_section, muni_id, year)
]

# Reporting per bin: same logic as 02_size_bin_coverage.R
report_per_bin <- function(cells) {
  cells[, n_cells_total := .N, by = size_bin]
  per_bin <- cells[, .(
    n_cells_total          = .N,
    n_cells_with_borrower  = sum(n_borrowers >= 1L),
    share_cells_with_borrower = mean(n_borrowers >= 1L),
    n_borrowers_p10 = quantile(n_borrowers[n_borrowers > 0L], 0.10, na.rm = TRUE),
    n_borrowers_p50 = quantile(n_borrowers[n_borrowers > 0L], 0.50, na.rm = TRUE),
    n_borrowers_p90 = quantile(n_borrowers[n_borrowers > 0L], 0.90, na.rm = TRUE),
    share_thin = mean(n_borrowers > 0L & n_borrowers < 5L) /
                 mean(n_borrowers > 0L)  # share thin among populated
  ), by = size_bin]
  per_bin
}

# share_munis_with_bin_borrower per (size_bin, year): among munis where the bin
# has any RAIS firms (n_firms >= 1), share with at least one BNDES borrower.
muni_year_bin <- cells_a2[
  n_firms >= 1L,
  .(any_borrower = any(n_borrowers >= 1L)),
  by = .(size_bin, muni_id, year)
]
share_by_year <- muni_year_bin[
  , .(share_munis_with_bin_borrower = mean(any_borrower)),
  by = .(size_bin, year)
]
share_med <- share_by_year[
  , .(share_munis_with_bin_borrower_med = median(share_munis_with_bin_borrower)),
  by = size_bin
]

per_bin <- report_per_bin(cells_a2)
per_bin <- merge(per_bin, share_med, by = "size_bin", all.x = TRUE)
per_bin[, struct_thin := share_munis_with_bin_borrower_med < 0.10]
per_bin[, bin_label := A2_LABELS[size_bin]]
setcolorder(per_bin, c("size_bin", "bin_label"))

fwrite(per_bin, file.path(OUT, "coverage_optionA2.csv"))
fwrite(cells_a2, file.path(OUT, "coverage_cells_optionA2.csv"))

# Summary verdict
overall_thin_share <- cells_a2[
  n_borrowers > 0L,
  mean(n_borrowers < 5L)
]
struct_thin_bins <- per_bin[struct_thin == TRUE, paste(bin_label, collapse = ",")]
verdict <- if (per_bin[struct_thin == TRUE, .N] == 0L && overall_thin_share < 0.30) {
  "PASS"
} else if (per_bin[struct_thin == TRUE, .N] == 0L) {
  "THIN_BIN_OK"  # all bins above 0.10 but overall thin >= 0.30
} else {
  "FAIL"
}

summary_dt <- data.table(
  option = "A2",
  n_bins = 2L,
  thin_cell_share_overall = overall_thin_share,
  max_share_munis_borrower = per_bin[, max(share_munis_with_bin_borrower_med, na.rm = TRUE)],
  min_share_munis_borrower = per_bin[, min(share_munis_with_bin_borrower_med, na.rm = TRUE)],
  structurally_thin_bins   = struct_thin_bins,
  verdict                  = verdict
)
fwrite(summary_dt, file.path(OUT, "coverage_summary_A2.csv"))

# Markdown report
fmt_pct <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)
fmt_num <- function(x, d = 3) sprintf(paste0("%.", d, "f"), x)
fmt_int <- function(x) format(as.integer(x), big.mark = ",")

report <- c(
  "# E2 Variant — 2-bin scheme A2 = {MPME (0-49), Big (50+)}",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Question",
  "",
  "Does collapsing Media+Grande into a single Big bin (50+) salvage coverage?",
  "Built by aggregating `coverage_cells_optionA4.csv` from 02_size_bin_coverage.R;",
  "no re-run of the 15-min cell build.",
  "",
  "---",
  "",
  "## Per-bin coverage",
  "",
  "| Bin | n_cells_total | n_cells_with_borrower | share_cells | share_munis_borrower_med | p50 n_borr | share_thin | struct_thin? |",
  "|-----|--------------:|----------------------:|------------:|-------------------------:|-----------:|-----------:|:-------------|",
  vapply(seq_len(nrow(per_bin)), function(i) {
    r <- per_bin[i]
    sprintf("| %s (%d) | %s | %s | %s | %s | %s | %s | %s |",
            r$bin_label, r$size_bin,
            fmt_int(r$n_cells_total),
            fmt_int(r$n_cells_with_borrower),
            fmt_pct(r$share_cells_with_borrower),
            fmt_num(r$share_munis_with_bin_borrower_med),
            fmt_int(r$n_borrowers_p50),
            fmt_pct(r$share_thin),
            if (isTRUE(r$struct_thin)) "**YES**" else "no")
  }, character(1L)),
  "",
  "---",
  "",
  "## Headline",
  "",
  paste0("- Overall thin-cell share (populated cells with n_borrowers<5): **",
         fmt_pct(overall_thin_share), "**"),
  paste0("- Structurally thin bins (share_munis_borrower_med < 0.10): **",
         if (struct_thin_bins == "") "none" else struct_thin_bins, "**"),
  paste0("- **Verdict: ", verdict, "**"),
  "",
  "---",
  "",
  "## Reading vs. A4 / A3",
  "",
  "Compared to the per-bin numbers in `coverage_report.md` (E2 main):",
  "",
  "- A4 Grande: share_munis_borrower_med = 0.044 (FAILED)",
  "- A4 Media:  0.098 (FAILED, just under)",
  "- A4 Pequena: 0.123 (passed)",
  "- A4 Micro:   0.094 (FAILED, just under)",
  "- A3 MPME:   0.118 (passed)",
  "- A3 Media:  0.098 (FAILED)",
  "- A3 Grande: 0.044 (FAILED)",
  "",
  "If A2's MPME and Big both clear 0.10, this is the cleanest BNDES-interpretable",
  "scheme that survives E2.",
  ""
)
writeLines(report, file.path(OUT, "coverage_report_A2.md"))

message("\n=== A2 (MPME / Big) coverage ===")
message(sprintf("  Verdict: %s", verdict))
message("  Per-bin:")
for (i in seq_len(nrow(per_bin))) {
  r <- per_bin[i]
  message(sprintf("    %-6s share_munis_borrower_med = %.3f, share_thin = %.1f%%, struct_thin = %s",
                  r$bin_label,
                  r$share_munis_with_bin_borrower_med,
                  100 * r$share_thin,
                  ifelse(isTRUE(r$struct_thin), "YES", "no")))
}
message(sprintf("  Overall thin share: %.1f%%", 100 * overall_thin_share))
