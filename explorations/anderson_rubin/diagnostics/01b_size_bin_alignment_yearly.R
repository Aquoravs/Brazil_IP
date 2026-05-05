# ==============================================================================
# 01b_size_bin_alignment_yearly.R
#
# E1 (revised): Alignment of A4 with BNDES porte at the YEAR level.
#
# For every loan in year y with known porte, look up the borrower firm's
# n_employees in year y from RAIS, assign A4, and cross-tab. No cycle
# aggregation, no fall-back, no modal-porte. Each loan is one observation.
#
# This is a pure "do RAIS-headcount and BNDES-porte agree?" test, with no
# cycle-baseline machinery in the way.
#
# Inputs:
#   data/processed/bndes_loan_level.qs2
#   data/processed/rais_bndes_reconstructed.fst
#
# Outputs (explorations/anderson_rubin/diagnostics/output/):
#   alignment_porte_A4_4x4_unweighted_yearly.csv
#   alignment_porte_A4_4x4_value_weighted_yearly.csv
#   alignment_porte_A4_3x3_collapsed_yearly.csv
#   alignment_summary_yearly.csv
#   alignment_report_yearly.md
# ==============================================================================

library(data.table)
library(qs2)
library(here)
library(fst)

setDTthreads(0L)

PROCESSED_DIR <- here::here("data", "processed")
OUTPUT_DIR    <- here::here(
  "explorations", "anderson_rubin", "diagnostics", "output"
)
if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)

PORTE_LEVELS <- c("Micro", "Pequena", "Media", "Grande")

# ------------------------------------------------------------------------------
# 1. Load BNDES loan-level
# ------------------------------------------------------------------------------
message("Loading BNDES loan-level...")
loans <- setDT(qs_read(file.path(PROCESSED_DIR, "bndes_loan_level.qs2")))

val_col <- grep("^value_dis.*real.*2018", names(loans), value = TRUE)[1L]
if (is.na(val_col)) val_col <- "value_dis"
stopifnot(val_col %in% names(loans))
message("  Real-value column: ", val_col)

setnames(loans, val_col, "value_dis_real")

bndes_porte_norm <- function(s) {
  s <- toupper(iconv(trimws(s), to = "ASCII//TRANSLIT"))
  fcase(
    grepl("MICRO", s),                              "Micro",
    grepl("PEQUEN", s),                             "Pequena",
    grepl("MEDIA|MEDIO|MEDIANO", s),                "Media",
    grepl("GRANDE", s),                             "Grande",
    default = NA_character_
  )
}

loans[, porte := bndes_porte_norm(size)]
loans[, firm_id := as.character(firm_id)]
loans[, year    := as.integer(year)]

n_total <- nrow(loans)
loans <- loans[!is.na(firm_id) & !is.na(value_dis_real) & !is.na(porte) &
                 !is.na(year)]
message(sprintf("  Loans after dropping NAs: %s / %s",
                format(nrow(loans), big.mark = ","),
                format(n_total, big.mark = ",")))

# ------------------------------------------------------------------------------
# 2. Load RAIS firm-year employment (column-selective, restricted to borrowers)
# ------------------------------------------------------------------------------
message("Loading RAIS panel (column-selective)...")
rais <- fst::read_fst(
  file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst"),
  columns = c("firm_id", "year", "n_employees"),
  as.data.table = TRUE
)
rais[, firm_id := as.character(firm_id)]
rais[, year    := as.integer(year)]
rais[, n_employees := as.numeric(n_employees)]

borrower_firms <- unique(loans$firm_id)
rais <- rais[firm_id %in% borrower_firms]
message(sprintf("  RAIS rows for borrower firms: %s",
                format(nrow(rais), big.mark = ",")))

# Collapse to firm-year totals (some firms appear with multiple cnae rows)
rais_fy <- rais[, .(n_employees = sum(n_employees, na.rm = TRUE),
                    has_obs = any(!is.na(n_employees))),
                by = .(firm_id, year)][has_obs == TRUE,
                                        .(firm_id, year, n_employees)]

rm(rais); invisible(gc())

# ------------------------------------------------------------------------------
# 3. Assign A4 per (firm, year)
# ------------------------------------------------------------------------------
rais_fy[, size_bin_A4 := fcase(
  n_employees >=   0 & n_employees <=   9, 1L,
  n_employees >=  10 & n_employees <=  49, 2L,
  n_employees >=  50 & n_employees <= 499, 3L,
  n_employees >= 500,                      4L,
  default = NA_integer_
)]

# ------------------------------------------------------------------------------
# 4. Merge loans <-> RAIS firm-year by (firm_id, year)
# ------------------------------------------------------------------------------
message("Merging loans with RAIS firm-year on (firm_id, year)...")
merged <- merge(
  loans[, .(firm_id, year, porte, value_dis_real)],
  rais_fy[, .(firm_id, year, size_bin_A4)],
  by = c("firm_id", "year"),
  all.x = FALSE  # drop loans where firm has no RAIS row that year
)
n_loans_clean <- nrow(loans)
n_merged      <- nrow(merged)
n_dropped     <- n_loans_clean - n_merged
message(sprintf("  Loans: %s | matched to RAIS: %s | dropped (no RAIS row): %s (%.1f%%)",
                format(n_loans_clean, big.mark = ","),
                format(n_merged,      big.mark = ","),
                format(n_dropped,     big.mark = ","),
                100 * n_dropped / n_loans_clean))

merged <- merged[!is.na(size_bin_A4)]
message(sprintf("  Cross-tab loans (porte known + A4 known): %s",
                format(nrow(merged), big.mark = ",")))

merged[, porte := factor(porte, levels = PORTE_LEVELS)]

# ------------------------------------------------------------------------------
# 5. Build 4x4 cross-tabs (per-loan; one row per loan)
# ------------------------------------------------------------------------------
# Unweighted = loan counts; value-weighted = sum(value_dis_real)
mat_uw <- merged[, .N, by = .(porte, size_bin_A4)]
mat_vw <- merged[, .(V = sum(value_dis_real, na.rm = TRUE)),
                 by = .(porte, size_bin_A4)]

# Long format with row percents
add_row_pct <- function(dt, val_col) {
  dt[, total_row := sum(get(val_col)), by = porte]
  dt[, row_pct   := get(val_col) / total_row]
  dt[, total_row := NULL]
  dt[]
}

mat_uw <- add_row_pct(mat_uw, "N")
mat_vw <- add_row_pct(mat_vw, "V")

# Diagonal masses
porte_to_a4 <- c("Micro" = 1L, "Pequena" = 2L, "Media" = 3L, "Grande" = 4L)
diag_uw <- mat_uw[porte_to_a4[as.character(porte)] == size_bin_A4, sum(N)] /
           mat_uw[, sum(N)]
diag_vw <- mat_vw[porte_to_a4[as.character(porte)] == size_bin_A4, sum(V)] /
           mat_vw[, sum(V)]

# ------------------------------------------------------------------------------
# 6. 3x3 collapsed (Micro+Pequena -> MPME)
# ------------------------------------------------------------------------------
collapse_a4 <- function(b) fcase(b %in% c(1L, 2L), 1L,
                                  b == 3L,         2L,
                                  b == 4L,         3L)
collapse_porte <- function(p) fcase(p %in% c("Micro", "Pequena"), "MPME",
                                     p == "Media",                 "Media",
                                     p == "Grande",                "Grande")

merged[, porte_3 := collapse_porte(as.character(porte))]
merged[, a4_3    := collapse_a4(size_bin_A4)]

mat_3x3 <- merged[, .(N = .N,
                       V = sum(value_dis_real, na.rm = TRUE)),
                   by = .(porte_3, a4_3)]
mat_3x3[, row_pct_uw := N / sum(N), by = porte_3]
mat_3x3[, row_pct_vw := V / sum(V), by = porte_3]

p3_to_a3 <- c("MPME" = 1L, "Media" = 2L, "Grande" = 3L)
diag_3x3_uw <- mat_3x3[p3_to_a3[porte_3] == a4_3, sum(N)] / mat_3x3[, sum(N)]
diag_3x3_vw <- mat_3x3[p3_to_a3[porte_3] == a4_3, sum(V)] / mat_3x3[, sum(V)]

# ------------------------------------------------------------------------------
# 7. Top off-diagonal cells (4x4 unweighted)
# ------------------------------------------------------------------------------
off_diag <- mat_uw[porte_to_a4[as.character(porte)] != size_bin_A4]
setorder(off_diag, -N)
top_off <- head(off_diag, 5L)

# ------------------------------------------------------------------------------
# 8. Write outputs
# ------------------------------------------------------------------------------
fwrite(mat_uw, file.path(OUTPUT_DIR, "alignment_porte_A4_4x4_unweighted_yearly.csv"))
fwrite(mat_vw, file.path(OUTPUT_DIR, "alignment_porte_A4_4x4_value_weighted_yearly.csv"))
fwrite(mat_3x3, file.path(OUTPUT_DIR, "alignment_porte_A4_3x3_collapsed_yearly.csv"))

summary_dt <- data.table(
  metric = c("4x4_unweighted_diag",
             "4x4_value_weighted_diag",
             "3x3_collapsed_unweighted_diag",
             "3x3_collapsed_value_weighted_diag",
             "n_loans_after_clean",
             "n_loans_matched_rais",
             "n_loans_dropped_no_rais",
             "n_loans_in_crosstab"),
  value  = c(diag_uw, diag_vw, diag_3x3_uw, diag_3x3_vw,
             n_loans_clean, n_merged, n_dropped, nrow(merged))
)
fwrite(summary_dt, file.path(OUTPUT_DIR, "alignment_summary_yearly.csv"))

# ------------------------------------------------------------------------------
# 9. Markdown report
# ------------------------------------------------------------------------------
fmt_pct <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)
fmt_int <- function(x) format(as.integer(x), big.mark = ",")

# 4x4 matrix as table (counts + row pct)
mat_uw_wide <- dcast(mat_uw, porte ~ size_bin_A4, value.var = "N", fill = 0L)
setcolorder(mat_uw_wide, c("porte", as.character(1:4)))
mat_vw_wide <- dcast(mat_vw, porte ~ size_bin_A4, value.var = "V", fill = 0)
setcolorder(mat_vw_wide, c("porte", as.character(1:4)))

verdict <- if (diag_vw >= 0.60 && diag_3x3_uw >= 0.65) {
  "PASS"
} else if (diag_3x3_uw >= 0.65) {
  "WEAK PASS (3x3 collapse aligns; 4x4 value-weighted does not)"
} else {
  "FAIL"
}

build_uw_table <- function() {
  out <- c("| Porte \\ A4 | Micro (1) | Pequena (2) | Media (3) | Grande (4) | Row total |",
           "|-------------|----------:|------------:|----------:|-----------:|----------:|")
  for (p in PORTE_LEVELS) {
    row <- mat_uw_wide[porte == p]
    if (!nrow(row)) next
    rt <- sum(row[, .SD, .SDcols = as.character(1:4)])
    cells <- vapply(as.character(1:4), function(b) {
      v <- row[[b]]
      if (length(v) == 0L || is.na(v)) "0" else fmt_int(v)
    }, character(1L))
    out <- c(out, paste0("| **", p, "** | ", paste(cells, collapse = " | "),
                          " | ", fmt_int(rt), " |"))
  }
  out
}

build_3x3_table <- function() {
  out <- c("| Porte \\ A3 | MPME (1) | Media (2) | Grande (3) | Row total |",
           "|-------------|---------:|----------:|-----------:|----------:|")
  m <- dcast(mat_3x3, porte_3 ~ a4_3, value.var = "N", fill = 0L)
  for (p in c("MPME", "Media", "Grande")) {
    row <- m[porte_3 == p]
    if (!nrow(row)) next
    cells <- vapply(as.character(1:3), function(b) {
      v <- row[[b]]
      if (is.null(v) || length(v) == 0L || is.na(v)) "0" else fmt_int(v)
    }, character(1L))
    rt <- sum(as.numeric(cells |> gsub(",", "", x = _)))
    out <- c(out, paste0("| **", p, "** | ", paste(cells, collapse = " | "),
                          " | ", fmt_int(rt), " |"))
  }
  out
}

top_off_lines <- vapply(seq_len(nrow(top_off)), function(i) {
  r <- top_off[i]
  sprintf("  %d. porte=%s × A4=%d (n=%s, %s of porte-row)",
          i, as.character(r$porte), r$size_bin_A4,
          fmt_int(r$N), fmt_pct(r$row_pct))
}, character(1L))

report <- c(
  "# E1 Alignment — Year-Level (revised)",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Question",
  "",
  "For every BNDES loan with known porte in year y, what A4 bin does the",
  "borrower's RAIS n_employees in year y put it in? **Per-loan; no cycle;",
  "no fall-back.** This is the cleanest test of whether RAIS-headcount and",
  "BNDES-porte agree on firm size.",
  "",
  "---",
  "",
  "## 1. Headline metrics",
  "",
  paste0("- Loans after NA filtering: ",            fmt_int(n_loans_clean)),
  paste0("- Matched to a RAIS firm-year:           ", fmt_int(n_merged),
         " (", fmt_pct(n_merged / n_loans_clean), ")"),
  paste0("- Dropped (no RAIS obs that year):       ", fmt_int(n_dropped)),
  paste0("- Cross-tab loans (porte + A4 known):    ", fmt_int(nrow(merged))),
  "",
  "| Metric | Value | Threshold | Status |",
  "|--------|------:|----------:|--------|",
  paste0("| **4×4 unweighted diagonal**            | **", fmt_pct(diag_uw, 2),
         "** | — | informational |"),
  paste0("| **4×4 value-weighted diagonal**        | **", fmt_pct(diag_vw, 2),
         "** | ≥ 60% | ", if (diag_vw >= 0.60) "**PASS**" else "**FAIL**", " |"),
  paste0("| **3×3 collapsed unweighted diagonal**  | **", fmt_pct(diag_3x3_uw, 2),
         "** | ≥ 65% | ", if (diag_3x3_uw >= 0.65) "**PASS**" else "**FAIL**", " |"),
  paste0("| **3×3 collapsed value-weighted diag**  | **", fmt_pct(diag_3x3_vw, 2),
         "** | — | informational |"),
  "",
  paste0("**Verdict: ", verdict, "**"),
  "",
  "---",
  "",
  "## 2. 4×4 cross-tab (loan counts)",
  "",
  build_uw_table(),
  "",
  "---",
  "",
  "## 3. 3×3 collapsed cross-tab (loan counts)",
  "",
  build_3x3_table(),
  "",
  "---",
  "",
  "## 4. Top off-diagonal cells (4×4 unweighted)",
  "",
  top_off_lines,
  "",
  "---",
  "",
  "## 5. Files",
  "",
  "- `alignment_porte_A4_4x4_unweighted_yearly.csv`",
  "- `alignment_porte_A4_4x4_value_weighted_yearly.csv`",
  "- `alignment_porte_A4_3x3_collapsed_yearly.csv`",
  "- `alignment_summary_yearly.csv`",
  ""
)

writeLines(report, file.path(OUTPUT_DIR, "alignment_report_yearly.md"))

# ------------------------------------------------------------------------------
# 10. Console summary
# ------------------------------------------------------------------------------
message("\n=================================================================")
message("  E1 (year-level): A4 vs. BNDES porte — summary")
message("=================================================================")
message(sprintf("  Loans in cross-tab:               %s", fmt_int(nrow(merged))))
message(sprintf("  4x4 unweighted diagonal:          %s", fmt_pct(diag_uw, 2)))
message(sprintf("  4x4 value-weighted diagonal:      %s  (>= 60%%?)", fmt_pct(diag_vw, 2)))
message(sprintf("  3x3 collapsed uw diagonal:        %s  (>= 65%%?)", fmt_pct(diag_3x3_uw, 2)))
message(sprintf("  3x3 collapsed vw diagonal:        %s", fmt_pct(diag_3x3_vw, 2)))
message(sprintf("  Verdict: %s", verdict))
message("=================================================================")

invisible(list(mat_uw = mat_uw, mat_vw = mat_vw, mat_3x3 = mat_3x3,
               diag_uw = diag_uw, diag_vw = diag_vw,
               diag_3x3_uw = diag_3x3_uw, diag_3x3_vw = diag_3x3_vw))
