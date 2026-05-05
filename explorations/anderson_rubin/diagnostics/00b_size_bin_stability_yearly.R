# ==============================================================================
# 00b_size_bin_stability_yearly.R
#
# E0 (revised): Bin-stability pre-exercise at the YEAR level.
#
# The original 00_size_bin_stability.R measured migration across election cycles,
# which required the cycle-baseline construction and a fall-back rule (47.3% of
# cells were LOCF/NOCB filled). That confounded the question.
#
# This script asks the cleaner question: for each candidate size classifier
# (A4 / A3 / B), how often does a firm's bin change year-over-year over the
# 2002–2017 RAIS panel? Each (firm, year) gets a bin from that year's observed
# n_employees alone — no fall-back, no cycle aggregation.
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst
#     columns: firm_id, year, cnae_section, n_employees
#
# Outputs (explorations/anderson_rubin/diagnostics/output/):
#   bin_stability_yearly_A4_distribution.csv
#   bin_stability_yearly_A4_transitions.csv
#   bin_stability_yearly_A3_distribution.csv
#   bin_stability_yearly_A3_transitions.csv
#   bin_stability_yearly_B_distribution.csv
#   bin_stability_yearly_B_transitions.csv
#   bin_stability_yearly_summary.csv
#   bin_stability_yearly_report.md
#
# Plan reference: logs/plans/2026-05-04_size-bin-diagnostics.md §3.5 (revised
# at user's direction 2026-05-04 — measure persistence at year level, not cycle).
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

path_fst <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst")
path_qs2 <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.qs2")

# ------------------------------------------------------------------------------
# 3. Constants
# ------------------------------------------------------------------------------
A4_LABELS <- c("Micro", "Pequena", "Media", "Grande")
N_BINS_B  <- 3L
STABILITY_THRESHOLD <- 0.20

# ------------------------------------------------------------------------------
# 4. Helper: equal-frequency tertile assignment with rank fallback
#    (mirrors scripts/R/3_instruments/30c_build_size_bin_mapping.R lines 91–105)
# ------------------------------------------------------------------------------
assign_size_bins <- function(x, n_bins = 3L) {
  if (!length(x)) return(integer(0L))
  if (all(is.na(x))) return(rep(NA_integer_, length(x)))

  probs  <- seq(0, 1, length.out = n_bins + 1L)
  breaks <- unique(as.numeric(quantile(x, probs = probs, na.rm = TRUE,
                                       names = FALSE)))

  if (length(breaks) >= n_bins + 1L) {
    return(as.integer(cut(x, breaks = breaks, include.lowest = TRUE,
                          labels = FALSE)))
  }

  ranks <- frank(x, ties.method = "average", na.last = "keep")
  n_obs <- sum(!is.na(x))
  pmax.int(1L, pmin.int(n_bins, as.integer(ceiling(ranks / n_obs * n_bins))))
}

# ------------------------------------------------------------------------------
# 5. Load panel (column-selective)
# ------------------------------------------------------------------------------
COLS_NEEDED <- c("firm_id", "year", "cnae_section", "n_employees")

message("Loading RAIS-BNDES panel (column-selective)...")

if (file.exists(path_fst)) {
  message("  Source: fst — ", basename(path_fst))
  panel <- fst::read_fst(path_fst, columns = COLS_NEEDED, as.data.table = TRUE)
} else if (file.exists(path_qs2)) {
  message("  Source: qs2 — ", basename(path_qs2))
  raw <- qs_read(path_qs2)
  setDT(raw)
  panel <- raw[, .SD, .SDcols = COLS_NEEDED]
  rm(raw); invisible(gc())
} else {
  stop("Panel file not found.")
}

panel[, firm_id     := as.integer(firm_id)]
panel[, year        := as.integer(year)]
panel[, n_employees := as.numeric(n_employees)]

message(sprintf("  Panel loaded: %s firm-years.",
                format(nrow(panel), big.mark = ",")))

# Collapse to firm-year totals (sum employment across cnae rows per firm-year;
# take first non-empty cnae_section).
panel_fy <- panel[
  , .(
    has_emp_obs   = any(!is.na(n_employees)),
    n_employees  = sum(n_employees, na.rm = TRUE),
    cnae_section = {
      cs <- cnae_section[!is.na(cnae_section) & cnae_section != ""]
      if (length(cs)) cs[1L] else NA_character_
    }
  ),
  by = .(firm_id, year)
]
panel_fy <- panel_fy[has_emp_obs == TRUE]
panel_fy[, has_emp_obs := NULL]

rm(panel); invisible(gc())

message(sprintf("  Firm-year totals retained: %s",
                format(nrow(panel_fy), big.mark = ",")))

# ------------------------------------------------------------------------------
# 6. Assign size bins per (firm, year) — no cycle, no fall-back
# ------------------------------------------------------------------------------
message("\nAssigning size bins at the firm-year level...")

# A4: fixed BNDES thresholds (Micro 0–9, Pequena 10–49, Media 50–499, Grande 500+)
panel_fy[, size_bin_A4 := fcase(
  n_employees >=   0 & n_employees <=   9, 1L,
  n_employees >=  10 & n_employees <=  49, 2L,
  n_employees >=  50 & n_employees <= 499, 3L,
  n_employees >= 500,                      4L,
  default = NA_integer_
)]

# A3: 3-bin collapse (MPME 0–49, Media 50–499, Grande 500+)
panel_fy[, size_bin_A3 := fcase(
  n_employees >=   0 & n_employees <=  49, 1L,
  n_employees >=  50 & n_employees <= 499, 2L,
  n_employees >= 500,                      3L,
  default = NA_integer_
)]

# B: within-(cnae_section, year) equal-frequency tertiles of n_employees
panel_fy[
  !is.na(cnae_section) & cnae_section != "" & !is.na(n_employees),
  size_bin_B := assign_size_bins(n_employees, n_bins = N_BINS_B),
  by = .(cnae_section, year)
]

message(sprintf("  Years covered: %d–%d",
                min(panel_fy$year), max(panel_fy$year)))
message("  A4 bin distribution across all firm-years:")
panel_fy[!is.na(size_bin_A4), .N, by = size_bin_A4][order(size_bin_A4)] |>
  (\(dt) for (j in seq_len(nrow(dt))) {
    message(sprintf("    Bin %d (%s): %s",
                    dt$size_bin_A4[j], A4_LABELS[dt$size_bin_A4[j]],
                    format(dt$N[j], big.mark = ",")))
  })()

# ------------------------------------------------------------------------------
# 7. Migration metrics — helper
# ------------------------------------------------------------------------------
compute_yearly_migration <- function(fy_dt, bin_col, option_label) {
  dt <- fy_dt[!is.na(get(bin_col)),
              .(firm_id, year, bin = get(bin_col))]

  # n_distinct_bins per firm (firms observed in >= 2 years)
  firm_summary <- dt[, .(
    n_years_obs    = .N,
    n_distinct_bins = uniqueN(bin)
  ), by = firm_id]

  firm_multi <- firm_summary[n_years_obs >= 2L]
  n_multi     <- nrow(firm_multi)
  n_changed   <- firm_multi[n_distinct_bins > 1L, .N]
  share_changed <- if (n_multi > 0L) n_changed / n_multi else NA_real_

  dist_dt <- firm_multi[, .N, by = n_distinct_bins][order(n_distinct_bins)]
  dist_dt[, option := option_label]
  dist_dt[, share_firms := N / n_multi]
  setcolorder(dist_dt, c("option", "n_distinct_bins", "N", "share_firms"))

  # Year-on-year transition: for each (firm, t) with bin_t, find bin_{t+1}
  setorder(dt, firm_id, year)
  dt[, next_year := shift(year, type = "lead"), by = firm_id]
  dt[, next_bin  := shift(bin,  type = "lead"), by = firm_id]
  pairs <- dt[!is.na(next_bin) & next_year == year + 1L]

  trans_dt <- pairs[, .N, by = .(year_from = year, year_to = next_year,
                                  bin_from = bin, bin_to = next_bin)]
  trans_dt[, option := option_label]
  setcolorder(trans_dt, c("option", "year_from", "year_to",
                           "bin_from", "bin_to", "N"))

  # Year-on-year migration rate: among (firm, t→t+1) consecutive observations,
  # share where bin changed.
  n_pairs    <- nrow(pairs)
  n_yoy_chg  <- pairs[bin != next_bin, .N]
  yoy_rate   <- if (n_pairs > 0L) n_yoy_chg / n_pairs else NA_real_

  # Direction (A options only — bins are ordinal)
  up_moves <- down_moves <- skip_moves <- NA_integer_
  if (grepl("^A", option_label) && n_pairs > 0L) {
    pairs[, delta := next_bin - bin]
    up_moves   <- pairs[delta >  0L, .N]
    down_moves <- pairs[delta <  0L, .N]
    skip_moves <- pairs[abs(delta) >= 2L, .N]
  }

  message(sprintf(
    "  [%s] Multi-year firms: %s | ever changed: %s (%.2f%%) | YoY change rate: %.2f%%",
    option_label,
    format(n_multi,   big.mark = ","),
    format(n_changed, big.mark = ","),
    100 * share_changed,
    100 * yoy_rate
  ))

  list(
    dist_dt        = dist_dt,
    trans_dt       = trans_dt,
    n_multi        = n_multi,
    n_changed      = n_changed,
    share_changed  = share_changed,
    n_yoy_pairs    = n_pairs,
    n_yoy_changed  = n_yoy_chg,
    yoy_change_rate = yoy_rate,
    up_moves       = up_moves,
    down_moves     = down_moves,
    skip_moves     = skip_moves
  )
}

# ------------------------------------------------------------------------------
# 8. Run for A4, A3, B
# ------------------------------------------------------------------------------
message("\nComputing year-level migration metrics...")

res_A4 <- compute_yearly_migration(panel_fy, "size_bin_A4", "A4")
res_A3 <- compute_yearly_migration(panel_fy, "size_bin_A3", "A3")
res_B  <- compute_yearly_migration(panel_fy, "size_bin_B",  "B")

# ------------------------------------------------------------------------------
# 9. Write CSVs
# ------------------------------------------------------------------------------
message("\nWriting outputs...")

fwrite(res_A4$dist_dt,
       file.path(OUTPUT_DIR, "bin_stability_yearly_A4_distribution.csv"))
fwrite(res_A3$dist_dt,
       file.path(OUTPUT_DIR, "bin_stability_yearly_A3_distribution.csv"))
fwrite(res_B$dist_dt,
       file.path(OUTPUT_DIR, "bin_stability_yearly_B_distribution.csv"))

fwrite(res_A4$trans_dt,
       file.path(OUTPUT_DIR, "bin_stability_yearly_A4_transitions.csv"))
fwrite(res_A3$trans_dt,
       file.path(OUTPUT_DIR, "bin_stability_yearly_A3_transitions.csv"))
fwrite(res_B$trans_dt,
       file.path(OUTPUT_DIR, "bin_stability_yearly_B_transitions.csv"))

n_total_moves_A4 <- if (!is.na(res_A4$up_moves) && !is.na(res_A4$down_moves)) {
  res_A4$up_moves + res_A4$down_moves
} else NA_integer_

summary_dt <- data.table(
  option                   = c("A4", "A3", "B"),
  share_firms_ever_changed = c(res_A4$share_changed, res_A3$share_changed, res_B$share_changed),
  yoy_change_rate          = c(res_A4$yoy_change_rate, res_A3$yoy_change_rate, res_B$yoy_change_rate),
  n_multi_year_firms       = c(res_A4$n_multi, res_A3$n_multi, res_B$n_multi),
  n_firms_ever_changed     = c(res_A4$n_changed, res_A3$n_changed, res_B$n_changed),
  n_yoy_pairs              = c(res_A4$n_yoy_pairs, res_A3$n_yoy_pairs, res_B$n_yoy_pairs),
  n_yoy_changed            = c(res_A4$n_yoy_changed, res_A3$n_yoy_changed, res_B$n_yoy_changed),
  up_moves                 = c(res_A4$up_moves, NA_integer_, NA_integer_),
  down_moves               = c(res_A4$down_moves, NA_integer_, NA_integer_),
  skip_bin_moves           = c(res_A4$skip_moves, NA_integer_, NA_integer_),
  share_skip_bin_moves     = c(
    if (!is.na(n_total_moves_A4) && n_total_moves_A4 > 0L) res_A4$skip_moves / n_total_moves_A4 else NA_real_,
    NA_real_, NA_real_
  ),
  recommendation_flag      = c(
    as.integer(!is.na(res_A4$share_changed) & res_A4$share_changed < STABILITY_THRESHOLD),
    NA_integer_, NA_integer_
  )
)
fwrite(summary_dt,
       file.path(OUTPUT_DIR, "bin_stability_yearly_summary.csv"))

message("  Wrote 7 CSVs.")

# ------------------------------------------------------------------------------
# 10. Markdown report
# ------------------------------------------------------------------------------
fmt_pct <- function(x, d = 2) ifelse(is.na(x), "—", sprintf(paste0("%.", d, "f%%"), 100 * x))
fmt_int <- function(x)        ifelse(is.na(x), "—", format(as.integer(x), big.mark = ","))

# Aggregate A4 transition matrix
agg_A4 <- res_A4$trans_dt[, .(N = sum(N)), by = .(bin_from, bin_to)]
m_A4   <- dcast(agg_A4, bin_from ~ bin_to, value.var = "N", fill = 0)

trans_lines <- c(
  "| From \\ To | Micro | Pequena | Media | Grande |",
  "|------------|------:|--------:|------:|-------:|"
)
for (bf in 1:4) {
  row_vals <- vapply(1:4, function(bt) {
    col <- as.character(bt)
    if (col %in% names(m_A4)) {
      v <- m_A4[bin_from == bf][[col]]
      if (length(v) && !is.na(v)) format(as.integer(v), big.mark = ",") else "0"
    } else "0"
  }, character(1L))
  trans_lines <- c(trans_lines,
    sprintf("| **%s** | %s |", A4_LABELS[bf], paste(row_vals, collapse = " | "))
  )
}

decision <- if (!is.na(res_A4$share_changed) && res_A4$share_changed < STABILITY_THRESHOLD) {
  paste0("Under A4, ", fmt_pct(res_A4$share_changed),
         " of multi-year firms ever change bin — below the 20% threshold. ",
         "**Lifetime-mean rule is defensible.**")
} else {
  paste0("Under A4, ", fmt_pct(res_A4$share_changed),
         " of multi-year firms ever change bin — at or above the 20% threshold. ",
         "**Cycle-baseline (or year-level) rule is justified — firm size moves over time.**")
}

report_lines <- c(
  "# Bin Stability — Year-Level (E0 revised)",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Question",
  "",
  "How often does a firm's size-bin classification change year-over-year",
  "across the 2002–2017 RAIS panel, under each candidate rule (A4, A3, B)?",
  "",
  "**No fall-back.** Each (firm, year) is binned from that year's observed",
  "`n_employees` directly. A firm contributes to migration metrics only",
  "for years in which it appears in RAIS.",
  "",
  "---",
  "",
  "## 1. Top-line numbers",
  "",
  "| Option | Multi-year firms | Ever changed | Share changed | YoY change rate |",
  "|--------|-----------------:|-------------:|--------------:|----------------:|",
  sprintf("| **A4** | %s | %s | **%s** | %s |",
          fmt_int(res_A4$n_multi), fmt_int(res_A4$n_changed),
          fmt_pct(res_A4$share_changed), fmt_pct(res_A4$yoy_change_rate)),
  sprintf("| **A3** | %s | %s | **%s** | %s |",
          fmt_int(res_A3$n_multi), fmt_int(res_A3$n_changed),
          fmt_pct(res_A3$share_changed), fmt_pct(res_A3$yoy_change_rate)),
  sprintf("| **B**  | %s | %s | **%s** | %s |",
          fmt_int(res_B$n_multi), fmt_int(res_B$n_changed),
          fmt_pct(res_B$share_changed), fmt_pct(res_B$yoy_change_rate)),
  "",
  sprintf("A4 movers: **%s up**, **%s down**, **%s skip-bin** (|Δbin|≥2; %s of all A4 yoy moves).",
          fmt_int(res_A4$up_moves), fmt_int(res_A4$down_moves),
          fmt_int(res_A4$skip_moves),
          fmt_pct(if (!is.na(n_total_moves_A4) && n_total_moves_A4 > 0L)
                  res_A4$skip_moves / n_total_moves_A4 else NA_real_)),
  "",
  "- **`share_firms_ever_changed`** = share of firms with ≥ 2 RAIS-observed years",
  "  whose bin is not constant across all observed years.",
  "- **`yoy change rate`** = share of consecutive (year, year+1) firm pairs where",
  "  the bin changed. Picks up high-frequency churn that the lifetime metric hides.",
  "",
  "---",
  "",
  "## 2. A4 year-on-year transition matrix (aggregate, all year pairs)",
  "",
  "Rows = bin in year t, columns = bin in year t+1.",
  "",
  trans_lines,
  "",
  "_Diagonal = firms that stay in the same bin from year t to year t+1._",
  "",
  "---",
  "",
  "## 3. Distribution of distinct bins per firm",
  "",
  "How many distinct bins does each multi-year firm pass through?",
  "",
  "**A4:**",
  "",
  "| n_distinct_bins | N firms | Share |",
  "|----------------:|--------:|------:|",
  do.call(c, lapply(seq_len(nrow(res_A4$dist_dt)), function(i) {
    r <- res_A4$dist_dt[i]
    sprintf("| %d | %s | %s |", r$n_distinct_bins,
            fmt_int(r$N), fmt_pct(r$share_firms))
  })),
  "",
  "**A3:**",
  "",
  "| n_distinct_bins | N firms | Share |",
  "|----------------:|--------:|------:|",
  do.call(c, lapply(seq_len(nrow(res_A3$dist_dt)), function(i) {
    r <- res_A3$dist_dt[i]
    sprintf("| %d | %s | %s |", r$n_distinct_bins,
            fmt_int(r$N), fmt_pct(r$share_firms))
  })),
  "",
  "**B:**",
  "",
  "| n_distinct_bins | N firms | Share |",
  "|----------------:|--------:|------:|",
  do.call(c, lapply(seq_len(nrow(res_B$dist_dt)), function(i) {
    r <- res_B$dist_dt[i]
    sprintf("| %d | %s | %s |", r$n_distinct_bins,
            fmt_int(r$N), fmt_pct(r$share_firms))
  })),
  "",
  "---",
  "",
  "## 4. Verdict",
  "",
  decision,
  "",
  "Note that A3 and B should be read alongside A4. If A4 is unstable but A3 is",
  "(near-)constant per firm, the cycle/year structure is mostly absorbing",
  "Micro/Pequena boundary noise, not real growth. If B is much more migratory",
  "than A4, within-sector rank shifts dominate absolute-level movement.",
  "",
  "---",
  "",
  "## 5. Files written",
  "",
  "- `bin_stability_yearly_summary.csv`",
  "- `bin_stability_yearly_{A4,A3,B}_distribution.csv`",
  "- `bin_stability_yearly_{A4,A3,B}_transitions.csv`  (long format, year-on-year)",
  "- `bin_stability_yearly_report.md` (this file)",
  ""
)

writeLines(report_lines,
           file.path(OUTPUT_DIR, "bin_stability_yearly_report.md"))
message("  Wrote report: bin_stability_yearly_report.md")

# ------------------------------------------------------------------------------
# 11. Console summary
# ------------------------------------------------------------------------------
message("\n==========================================================")
message("  E0 (year-level): Bin stability — summary")
message("==========================================================")
message(sprintf("  [A4] Ever changed: %s (%.2f%%)  |  YoY rate: %.2f%%",
                format(res_A4$n_changed, big.mark = ","),
                100 * res_A4$share_changed,
                100 * res_A4$yoy_change_rate))
message(sprintf("  [A3] Ever changed: %s (%.2f%%)  |  YoY rate: %.2f%%",
                format(res_A3$n_changed, big.mark = ","),
                100 * res_A3$share_changed,
                100 * res_A3$yoy_change_rate))
message(sprintf("  [B]  Ever changed: %s (%.2f%%)  |  YoY rate: %.2f%%",
                format(res_B$n_changed, big.mark = ","),
                100 * res_B$share_changed,
                100 * res_B$yoy_change_rate))
message("==========================================================")

invisible(list(
  res_A4 = res_A4, res_A3 = res_A3, res_B = res_B,
  summary_dt = summary_dt
))
