# ==============================================================================
# 01_size_bin_alignment.R
#
# E1: Alignment of Option A4 (4-bin BNDES native) with BNDES porte (size
# category recorded at loan origination). Tests whether fixed employment
# thresholds [0-9 / 10-49 / 50-499 / 500+] reproduce the lender's own
# categorisation.
#
# Foundation under test:
#   F0 admissibility (docs/PROJECT_BLUEPRINT.md §3 F0) — interpretability
#   sub-claim: if A4's employment thresholds diverge substantially from
#   BNDES porte, the "employment proxy for BNDES categories" framing is
#   weakened. E1 quantifies this divergence.
#
# Inputs:
#   data/processed/bndes_loan_level.qs2
#     columns used: firm_id, year, size (porte), value_dis_real_2018
#                   (or nearest match), value_dis, cnae_section
#   data/processed/rais_bndes_reconstructed.fst
#     columns used: firm_id, year, cnae_section, n_employees
#
# Outputs (explorations/anderson_rubin/diagnostics/output/):
#   alignment_porte_A4_4x4_unweighted.csv   — long: porte_row, a4_col, n, row_pct
#   alignment_porte_A4_4x4_value_weighted.csv — long: same, weighted by real value
#   alignment_porte_A4_3x3_collapsed.csv    — long: collapsed 3x3 with both weights
#   alignment_summary.csv                   — top-line metrics + n counts
#   alignment_report.md                     — plain-language verdict
#
# Plan reference: logs/plans/2026-05-04_size-bin-diagnostics.md §4
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
# 2. Paths via here::here() (INV-16: no absolute paths)
# ------------------------------------------------------------------------------
PROCESSED_DIR <- here::here("data", "processed")
OUTPUT_DIR    <- here::here(
  "explorations", "anderson_rubin", "diagnostics", "output"
)

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  message("Created output directory: ", OUTPUT_DIR)
}

path_loans <- file.path(PROCESSED_DIR, "bndes_loan_level.qs2")
path_fst   <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst")
path_qs2   <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.qs2")

# ------------------------------------------------------------------------------
# 3. Constants
# ------------------------------------------------------------------------------

# Election-cycle baseline windows (all 7 cycles — mayor + gov/pres)
# Source: plan §2, mirroring scripts/R/3_instruments/30c and 33.
BASELINE_WINDOWS <- rbindlist(list(
  data.table(election_cycle = 2005L, bl_start = 2002L, bl_end = 2003L),
  data.table(election_cycle = 2007L, bl_start = 2002L, bl_end = 2005L),
  data.table(election_cycle = 2009L, bl_start = 2004L, bl_end = 2007L),
  data.table(election_cycle = 2011L, bl_start = 2006L, bl_end = 2009L),
  data.table(election_cycle = 2013L, bl_start = 2008L, bl_end = 2011L),
  data.table(election_cycle = 2015L, bl_start = 2010L, bl_end = 2013L),
  data.table(election_cycle = 2017L, bl_start = 2012L, bl_end = 2015L)
))

N_CYCLES <- nrow(BASELINE_WINDOWS)

# Loan-year -> election_cycle mapping (post-baseline outcome window rule, all
# 7 cycles). Plan §4 step 2 hardcodes this to avoid edge bugs.
#   cycle c's outcome window: (bl_end_c, bl_end_{c+1}]
#   Concretely derived from BASELINE_WINDOWS above:
#     2004            -> 2005  (bl_end_2005 = 2003, next = 2005)
#     2005, 2006      -> 2007  (bl_end_2007 = 2005, next = 2007)
#     2007, 2008      -> 2009
#     2009, 2010      -> 2011
#     2011, 2012      -> 2013
#     2013, 2014      -> 2015
#     2015, 2016, 2017-> 2017  (last cycle: 2015+1 through panel end)
#     2002, 2003      -> NA  (before any cycle's outcome window)
#     >= 2018         -> NA  (beyond last cycle)
YEAR_TO_CYCLE <- data.table(
  year = c(2004L,
           2005L, 2006L,
           2007L, 2008L,
           2009L, 2010L,
           2011L, 2012L,
           2013L, 2014L,
           2015L, 2016L, 2017L),
  election_cycle = c(2005L,
                     2007L, 2007L,
                     2009L, 2009L,
                     2011L, 2011L,
                     2013L, 2013L,
                     2015L, 2015L,
                     2017L, 2017L, 2017L)
)

# A4 labels (bins 1-4)
A4_LABELS   <- c("Micro", "Pequena", "Media", "Grande")
PORTE_LEVELS <- c("Micro", "Pequena", "Media", "Grande")

# E1 pass/fail thresholds (plan §8)
THRESH_4X4_VALUE_WEIGHTED  <- 0.60
THRESH_3X3_UNWEIGHTED      <- 0.65

# ------------------------------------------------------------------------------
# 4. Helper: normalize BNDES porte string -> {Micro, Pequena, Media, Grande, NA}
#    Plan §4 step 1 (exact specification)
# ------------------------------------------------------------------------------
#' @param s  character vector of raw porte values
#' @return character vector with normalized category or NA_character_
bndes_porte_norm <- function(s) {
  s <- toupper(iconv(trimws(s), to = "ASCII//TRANSLIT"))
  fcase(
    grepl("MICRO",                s), "Micro",
    grepl("PEQUEN",               s), "Pequena",
    grepl("MEDIA|MEDIO|MEDIANO",  s), "Media",
    grepl("GRANDE",               s), "Grande",
    default = NA_character_
  )
}

# ------------------------------------------------------------------------------
# 5. Load BNDES loan-level data
# ------------------------------------------------------------------------------
message("Loading BNDES loan-level data...")

if (!file.exists(path_loans)) {
  stop("BNDES loan-level file not found:\n  ", path_loans)
}

loans <- setDT(qs_read(path_loans))
message(sprintf("  Raw loans loaded: %s rows.", format(nrow(loans), big.mark = ",")))

# Defensive: find the real-value column (plan edge-case block)
val_col <- grep("^value_dis.*real.*2018", names(loans), value = TRUE)[1L]
if (is.na(val_col)) {
  message("  Warning: no column matching ^value_dis.*real.*2018 found; falling back to 'value_dis'.")
  val_col <- "value_dis"
}
stopifnot(val_col %in% names(loans))
message(sprintf("  Real value column used: '%s'", val_col))

# Normalise to a consistent internal column name
if (val_col != "value_dis_real") {
  loans[, value_dis_real := get(val_col)]
} else {
  loans[, value_dis_real := get(val_col)]
}

# Required columns check
required_loan_cols <- c("firm_id", "year", "size")
missing_loan_cols  <- setdiff(required_loan_cols, names(loans))
if (length(missing_loan_cols) > 0L) {
  stop("BNDES loan-level file missing required columns: ",
       paste(missing_loan_cols, collapse = ", "))
}

# Coerce types
loans[, firm_id := as.integer(firm_id)]
loans[, year    := as.integer(year)]

n_total_loans <- nrow(loans)

# Drop loans with missing firm_id, missing real value, or missing size
n_before_drop <- n_total_loans
loans <- loans[!is.na(firm_id)]
n_after_firm  <- nrow(loans)
loans <- loans[!is.na(value_dis_real)]
n_after_val   <- nrow(loans)
loans <- loans[!is.na(size) & size != ""]
n_after_size  <- nrow(loans)

message(sprintf("  Dropped (missing firm_id):    %s",
                format(n_before_drop - n_after_firm, big.mark = ",")))
message(sprintf("  Dropped (missing value_dis):  %s",
                format(n_after_firm - n_after_val,   big.mark = ",")))
message(sprintf("  Dropped (missing size/porte): %s",
                format(n_after_val - n_after_size,   big.mark = ",")))
message(sprintf("  Remaining loans:              %s",
                format(n_after_size, big.mark = ",")))

# Normalize porte
loans[, porte := bndes_porte_norm(size)]

n_porte_known <- loans[!is.na(porte), .N]
n_porte_na    <- loans[is.na(porte),  .N]
porte_known_share <- n_porte_known / nrow(loans)

message(sprintf("  Porte known: %s / %s loans (%.1f%%)",
                format(n_porte_known, big.mark = ","),
                format(nrow(loans),   big.mark = ","),
                100 * porte_known_share))

# Keep only porte-known loans for cross-tabulation
loans_known <- loans[!is.na(porte)]

# ------------------------------------------------------------------------------
# 6. Map loan year to election cycle (plan §4 step 2)
# ------------------------------------------------------------------------------
message("\nStep 6: Mapping loan years to election cycles...")

# Merge year->cycle map
loans_known <- merge(loans_known, YEAR_TO_CYCLE, by = "year", all.x = TRUE)

n_dropped_year_edge <- loans_known[is.na(election_cycle), .N]
loans_known <- loans_known[!is.na(election_cycle)]

message(sprintf("  Dropped (year outside cycle windows, i.e. 2002-2003 or >=2018): %s",
                format(n_dropped_year_edge, big.mark = ",")))
message(sprintf("  Loans remaining for cross-tab: %s",
                format(nrow(loans_known), big.mark = ",")))

# ------------------------------------------------------------------------------
# 7. Aggregate to (firm x cycle): modal porte, tie-broken by total real value
#    Plan §4 step 3
#
#    Strategy:
#      (a) compute per (firm, cycle, porte): N and sum(value_dis_real)
#      (b) within each (firm, cycle) pick the porte with highest N;
#          tie-break on sum_value (larger sum wins)
# ------------------------------------------------------------------------------
message("\nStep 7: Aggregating to (firm x cycle) — modal porte, value-weighted tie-break...")

# Step 7a: per (firm, cycle, porte) summaries
fc_porte_agg <- loans_known[, .(
  n_loans    = .N,
  sum_value  = sum(value_dis_real, na.rm = TRUE)
), by = .(firm_id, election_cycle, porte)]

# Step 7b: within (firm, cycle), rank by (n_loans DESC, sum_value DESC)
# We want argmax(n_loans) with tie-break on argmax(sum_value).
# data.table: order descending by n_loans then sum_value, take first row.
setorder(fc_porte_agg, firm_id, election_cycle, -n_loans, -sum_value)
firm_cycle_porte <- fc_porte_agg[, head(.SD, 1L), by = .(firm_id, election_cycle)]
firm_cycle_porte <- firm_cycle_porte[, .(firm_id, election_cycle, firm_cycle_porte = porte,
                                          total_value = sum_value)]

# Also aggregate total real value over ALL loans in (firm, cycle) for weighting
fc_total_value <- loans_known[, .(
  total_loan_value = sum(value_dis_real, na.rm = TRUE)
), by = .(firm_id, election_cycle)]

firm_cycle_porte <- merge(firm_cycle_porte, fc_total_value,
                           by = c("firm_id", "election_cycle"), all.x = TRUE)

n_firm_cycle_pairs <- nrow(firm_cycle_porte)
message(sprintf("  Unique (firm x cycle) pairs with known porte: %s",
                format(n_firm_cycle_pairs, big.mark = ",")))

# ------------------------------------------------------------------------------
# 8. Compute baseline mean_emp per (firm, cycle) from RAIS panel
#    Plan §4 step 4; reuses cycle-loop pattern + fall-back rule from
#    00_size_bin_stability.R (lines ~199-275).
#
#    To bound memory: restrict RAIS loading to firms in the BNDES borrower set.
# ------------------------------------------------------------------------------
message("\nStep 8: Computing baseline mean_emp per (firm, cycle) from RAIS panel...")

COLS_RAIS <- c("firm_id", "year", "cnae_section", "n_employees")

if (file.exists(path_fst)) {
  message("  Source: fst (column-selective) — ", basename(path_fst))
  rais_raw <- fst::read_fst(path_fst, columns = COLS_RAIS, as.data.table = TRUE)
} else if (file.exists(path_qs2)) {
  message("  Source: qs2 — ", basename(path_qs2))
  rais_raw <- setDT(qs_read(path_qs2))
  missing_rais <- setdiff(COLS_RAIS, names(rais_raw))
  if (length(missing_rais) > 0L) {
    stop("RAIS qs2 file missing columns: ", paste(missing_rais, collapse = ", "))
  }
  rais_raw <- rais_raw[, .SD, .SDcols = COLS_RAIS]
  invisible(gc())
} else {
  stop("RAIS-BNDES panel not found.\nExpected:\n  ", path_fst, "\nor\n  ", path_qs2)
}

stopifnot(is.data.table(rais_raw))
rais_raw[, firm_id     := as.integer(firm_id)]
rais_raw[, year        := as.integer(year)]
rais_raw[, n_employees := as.numeric(n_employees)]

message(sprintf("  RAIS raw rows loaded: %s", format(nrow(rais_raw), big.mark = ",")))

# Restrict to borrower firms to bound memory
borrower_firms <- unique(firm_cycle_porte$firm_id)
rais_panel <- rais_raw[firm_id %in% borrower_firms]
rm(rais_raw); invisible(gc())

message(sprintf("  RAIS restricted to borrower firms: %s firm-years",
                format(nrow(rais_panel), big.mark = ",")))

# Collapse to firm-year (mirror 00_size_bin_stability.R lines 163-175)
panel_fy <- rais_panel[, .(
  has_emp_obs  = any(!is.na(n_employees)),
  emp_total    = sum(n_employees, na.rm = TRUE),
  cnae_section = cnae_section[1L]
), by = .(firm_id, year)]
panel_fy <- panel_fy[has_emp_obs == TRUE,
                     .(firm_id, year, cnae_section, n_employees = emp_total)]

rm(rais_panel); invisible(gc())

message(sprintf("  Firm-year totals: %s rows", format(nrow(panel_fy), big.mark = ",")))

# Cycle loop: compute per-(firm, cycle) baseline mean (pre-allocated container)
all_means <- vector("list", N_CYCLES)

for (i in seq_len(N_CYCLES)) {
  ec       <- BASELINE_WINDOWS$election_cycle[i]
  bl_start <- BASELINE_WINDOWS$bl_start[i]
  bl_end   <- BASELINE_WINDOWS$bl_end[i]

  dt_bl <- panel_fy[year >= bl_start & year <= bl_end]

  if (!nrow(dt_bl)) {
    message(sprintf("  Cycle %d: no observations in baseline window — skipped.", ec))
    next
  }

  firm_avg <- dt_bl[, .(
    mean_emp   = mean(n_employees, na.rm = TRUE),
    n_bl_years = .N
  ), by = firm_id]

  firm_avg[, election_cycle := ec]

  message(sprintf("  Cycle %d (bl %d-%d): %s firms, mean emp = %.1f",
                  ec, bl_start, bl_end,
                  format(nrow(firm_avg), big.mark = ","),
                  mean(firm_avg$mean_emp, na.rm = TRUE)))

  all_means[[i]] <- firm_avg
}

firm_cycle_emp <- rbindlist(all_means, fill = TRUE)
rm(all_means); invisible(gc())

# Full (firm x cycle) grid restricted to borrower firms
full_grid  <- CJ(firm_id = borrower_firms,
                  election_cycle = BASELINE_WINDOWS$election_cycle)
firm_cycle_emp <- merge(full_grid, firm_cycle_emp,
                         by = c("firm_id", "election_cycle"), all.x = TRUE)
rm(full_grid)

n_grid_rows      <- nrow(firm_cycle_emp)
n_missing_before <- sum(is.na(firm_cycle_emp$mean_emp))
message(sprintf("  Grid rows: %s | missing mean_emp: %s (%.1f%%)",
                format(n_grid_rows,      big.mark = ","),
                format(n_missing_before, big.mark = ","),
                100 * n_missing_before / n_grid_rows))

# Fall-back rule (plan §3): LOCF then NOCB within firm
setorder(firm_cycle_emp, firm_id, election_cycle)
firm_cycle_emp[, mean_emp_filled := mean_emp]
firm_cycle_emp[, mean_emp_filled := nafill(mean_emp_filled, type = "locf"),
               by = firm_id]
firm_cycle_emp[, mean_emp_filled := nafill(mean_emp_filled, type = "nocb"),
               by = firm_id]

n_fallback_used  <- sum(is.na(firm_cycle_emp$mean_emp) & !is.na(firm_cycle_emp$mean_emp_filled))
n_still_missing  <- sum(is.na(firm_cycle_emp$mean_emp_filled))
fallback_rate    <- n_fallback_used / n_grid_rows

message(sprintf("  Fall-backs applied: %s (%.2f%% of grid)",
                format(n_fallback_used, big.mark = ","),
                100 * fallback_rate))
message(sprintf("  Still missing after fall-back: %s",
                format(n_still_missing, big.mark = ",")))

firm_cycle_emp <- firm_cycle_emp[!is.na(mean_emp_filled)]
firm_cycle_emp[, mean_emp := mean_emp_filled]
firm_cycle_emp[, mean_emp_filled := NULL]

# ------------------------------------------------------------------------------
# 9. Build size_bin_A4 per (firm, cycle)
#    Plan §4 step 5; A4 fcase block verbatim from 00_size_bin_stability.R
#    lines 297-303.
# ------------------------------------------------------------------------------
message("\nStep 9: Assigning size_bin_A4...")

firm_cycle_emp[, size_bin_A4 := fcase(
  mean_emp >=   0 & mean_emp <=   9, 1L,
  mean_emp >=  10 & mean_emp <=  49, 2L,
  mean_emp >=  50 & mean_emp <= 499, 3L,
  mean_emp >= 500,                   4L,
  default = NA_integer_
)]

message("  A4 bin distribution (borrower set):")
firm_cycle_emp[!is.na(size_bin_A4), .N, by = size_bin_A4][order(size_bin_A4)] |>
  (\(dt) for (j in seq_len(nrow(dt))) {
    message(sprintf("    Bin %d (%s): %s",
                    dt$size_bin_A4[j],
                    A4_LABELS[dt$size_bin_A4[j]],
                    format(dt$N[j], big.mark = ",")))
  })()

# ------------------------------------------------------------------------------
# 10. Merge porte assignment with size_bin_A4 on the borrower set
# ------------------------------------------------------------------------------
message("\nStep 10: Merging porte and A4 bin for cross-tabulation...")

crosstab_dt <- merge(
  firm_cycle_porte[, .(firm_id, election_cycle, firm_cycle_porte, total_loan_value)],
  firm_cycle_emp[, .(firm_id, election_cycle, size_bin_A4)],
  by  = c("firm_id", "election_cycle"),
  all = FALSE   # inner join: only (firm, cycle) with both porte and A4
)

# Drop any remaining NA bins
crosstab_dt <- crosstab_dt[!is.na(firm_cycle_porte) & !is.na(size_bin_A4)]

n_crosstab <- nrow(crosstab_dt)
message(sprintf("  Cross-tab rows (firm x cycle with both porte and A4): %s",
                format(n_crosstab, big.mark = ",")))

# Enforce factor levels for ordering
crosstab_dt[, porte_f  := factor(firm_cycle_porte, levels = PORTE_LEVELS)]
crosstab_dt[, size_bin := size_bin_A4]

# ------------------------------------------------------------------------------
# 11. Table 1 (primary): 4x4 unweighted counts + row percentages
#     Plan §4 step 6
# ------------------------------------------------------------------------------
message("\nStep 11: Building 4x4 cross-tabs...")

# Unweighted: count (firm x cycle) pairs
tab4_unweighted <- crosstab_dt[, .N, by = .(porte_row = porte_f, a4_col = size_bin)]

# Complete the 4x4 grid (fill 0 for missing cells)
full_4x4 <- CJ(
  porte_row = factor(PORTE_LEVELS, levels = PORTE_LEVELS),
  a4_col    = 1L:4L
)
tab4_unweighted <- merge(full_4x4, tab4_unweighted,
                          by = c("porte_row", "a4_col"), all.x = TRUE)
tab4_unweighted[is.na(N), N := 0L]

# Row totals for row percentages
row_totals_uw <- tab4_unweighted[, .(row_total = sum(N)), by = porte_row]
tab4_unweighted <- merge(tab4_unweighted, row_totals_uw, by = "porte_row")
tab4_unweighted[, row_pct := fifelse(row_total > 0L, N / row_total, 0)]
tab4_unweighted[, row_total := NULL]

# Diagonal shares (unweighted)
diag_uw <- tab4_unweighted[
  (porte_row == "Micro"   & a4_col == 1L) |
  (porte_row == "Pequena" & a4_col == 2L) |
  (porte_row == "Media"   & a4_col == 3L) |
  (porte_row == "Grande"  & a4_col == 4L),
  sum(N)
] / n_crosstab

# Table 1w (value-weighted): weight by total_loan_value over (firm, cycle)
tab4_weighted <- crosstab_dt[, .(
  sum_value = sum(total_loan_value, na.rm = TRUE)
), by = .(porte_row = porte_f, a4_col = size_bin)]

tab4_weighted <- merge(full_4x4, tab4_weighted,
                        by = c("porte_row", "a4_col"), all.x = TRUE)
tab4_weighted[is.na(sum_value), sum_value := 0]

# Row totals for row percentages
row_totals_vw <- tab4_weighted[, .(row_value_total = sum(sum_value)), by = porte_row]
tab4_weighted <- merge(tab4_weighted, row_totals_vw, by = "porte_row")
tab4_weighted[, row_pct_value := fifelse(row_value_total > 0, sum_value / row_value_total, 0)]
tab4_weighted[, row_value_total := NULL]

# Diagonal shares (value-weighted)
total_value_all <- sum(tab4_weighted$sum_value, na.rm = TRUE)
diag_vw <- tab4_weighted[
  (porte_row == "Micro"   & a4_col == 1L) |
  (porte_row == "Pequena" & a4_col == 2L) |
  (porte_row == "Media"   & a4_col == 3L) |
  (porte_row == "Grande"  & a4_col == 4L),
  sum(sum_value)
] / total_value_all

message(sprintf("  4x4 unweighted diagonal mass:    %.3f", diag_uw))
message(sprintf("  4x4 value-weighted diagonal mass: %.3f", diag_vw))

# ------------------------------------------------------------------------------
# 12. Table 1c: 3x3 collapsed
#     A4: bin 1+2 -> 1 (MPME), bin 3 -> 2, bin 4 -> 3
#     porte: Micro+Pequena -> MPME, Media -> 2, Grande -> 3
#     Plan §4 step 6 (informational)
# ------------------------------------------------------------------------------
message("\nStep 12: Building 3x3 collapsed cross-tab...")

crosstab_dt[, porte_3 := fcase(
  firm_cycle_porte %in% c("Micro", "Pequena"), 1L,
  firm_cycle_porte == "Media",                 2L,
  firm_cycle_porte == "Grande",                3L,
  default = NA_integer_
)]

crosstab_dt[, a4_3 := fcase(
  size_bin_A4 %in% c(1L, 2L), 1L,
  size_bin_A4 == 3L,           2L,
  size_bin_A4 == 4L,           3L,
  default = NA_integer_
)]

# Unweighted 3x3
tab3_uw <- crosstab_dt[!is.na(porte_3) & !is.na(a4_3),
                        .N,
                        by = .(porte_row_3 = porte_3, a4_col_3 = a4_3)]

full_3x3 <- CJ(porte_row_3 = 1L:3L, a4_col_3 = 1L:3L)
tab3_uw  <- merge(full_3x3, tab3_uw, by = c("porte_row_3", "a4_col_3"), all.x = TRUE)
tab3_uw[is.na(N), N := 0L]

n_3x3 <- crosstab_dt[!is.na(porte_3) & !is.na(a4_3), .N]
diag_3x3_uw <- tab3_uw[porte_row_3 == a4_col_3, sum(N)] / n_3x3

# Value-weighted 3x3
tab3_vw <- crosstab_dt[!is.na(porte_3) & !is.na(a4_3), .(
  sum_value = sum(total_loan_value, na.rm = TRUE)
), by = .(porte_row_3 = porte_3, a4_col_3 = a4_3)]

tab3_vw <- merge(full_3x3, tab3_vw, by = c("porte_row_3", "a4_col_3"), all.x = TRUE)
tab3_vw[is.na(sum_value), sum_value := 0]

total_3x3_value <- sum(tab3_vw$sum_value, na.rm = TRUE)
diag_3x3_vw <- tab3_vw[porte_row_3 == a4_col_3, sum(sum_value)] / total_3x3_value

message(sprintf("  3x3 unweighted diagonal mass:    %.3f", diag_3x3_uw))
message(sprintf("  3x3 value-weighted diagonal mass: %.3f", diag_3x3_vw))

# Merge into single 3x3 file
tab3_combined <- merge(tab3_uw, tab3_vw, by = c("porte_row_3", "a4_col_3"))

# Label columns
porte_3_labels <- c("MPME", "Media", "Grande")
tab3_combined[, porte_label := porte_3_labels[porte_row_3]]
tab3_combined[, a4_label    := paste0("A4_", c("1_MPME", "2_Media", "3_Grande")[a4_col_3])]

# Row totals for row pcts
row3_totals_uw <- tab3_combined[, .(row_total_n = sum(N)),        by = porte_row_3]
row3_totals_vw <- tab3_combined[, .(row_total_v = sum(sum_value)), by = porte_row_3]
tab3_combined  <- merge(tab3_combined, row3_totals_uw, by = "porte_row_3")
tab3_combined  <- merge(tab3_combined, row3_totals_vw, by = "porte_row_3")
tab3_combined[, row_pct_uw := fifelse(row_total_n > 0L, N / row_total_n, 0)]
tab3_combined[, row_pct_vw := fifelse(row_total_v > 0, sum_value / row_total_v, 0)]
tab3_combined[, c("row_total_n", "row_total_v") := NULL]

# ------------------------------------------------------------------------------
# 13. Off-diagonal analysis: flag largest 3 off-diagonal cells (4x4 unweighted)
#     Plan §4 step 7
# ------------------------------------------------------------------------------
message("\nStep 13: Identifying largest off-diagonal cells (4x4 unweighted)...")

# Build readable labels for the 4x4 table
tab4_unweighted_lab <- copy(tab4_unweighted)
tab4_unweighted_lab[, porte_label := as.character(porte_row)]
tab4_unweighted_lab[, a4_label    := A4_LABELS[a4_col]]
tab4_unweighted_lab[, is_diag     := (
  (porte_row == "Micro"   & a4_col == 1L) |
  (porte_row == "Pequena" & a4_col == 2L) |
  (porte_row == "Media"   & a4_col == 3L) |
  (porte_row == "Grande"  & a4_col == 4L)
)]

off_diag <- tab4_unweighted_lab[is_diag == FALSE]
setorder(off_diag, -N)
top3_offdiag <- head(off_diag, 3L)

message("  Top 3 off-diagonal cells (unweighted):")
for (j in seq_len(nrow(top3_offdiag))) {
  r <- top3_offdiag[j]
  message(sprintf("    porte=%s x A4=%s (%s): n=%s",
                  r$porte_label, r$a4_label,
                  if (r$is_diag) "DIAG" else "off",
                  format(r$N, big.mark = ",")))
}

# ------------------------------------------------------------------------------
# 14. Build alignment_summary.csv
#     Plan §4 step 7 — one row per metric plus count fields
# ------------------------------------------------------------------------------
message("\nStep 14: Building alignment_summary.csv...")

# Off-diagonal details for summary
offdiag_str <- paste(
  vapply(seq_len(nrow(top3_offdiag)), function(j) {
    r <- top3_offdiag[j]
    paste0(r$porte_label, "->A4_", r$a4_label, "(n=", r$N, ")")
  }, character(1L)),
  collapse = "; "
)

summary_dt <- data.table(
  metric                       = c("unweighted_diag_4x4",
                                   "value_weighted_diag_4x4",
                                   "collapsed_diag_3x3_unweighted",
                                   "collapsed_diag_3x3_value_weighted"),
  value                        = c(diag_uw, diag_vw, diag_3x3_uw, diag_3x3_vw),
  threshold                    = c(NA_real_,
                                   THRESH_4X4_VALUE_WEIGHTED,
                                   THRESH_3X3_UNWEIGHTED,
                                   NA_real_),
  pass                         = c(NA,
                                   diag_vw    >= THRESH_4X4_VALUE_WEIGHTED,
                                   diag_3x3_uw >= THRESH_3X3_UNWEIGHTED,
                                   NA)
)

# Append count fields as a second table (rather than wide columns on each row)
count_row <- data.table(
  metric    = "counts",
  value     = NA_real_,
  threshold = NA_real_,
  pass      = NA
)

# These are stored separately in the summary
summary_counts <- data.table(
  n_total_loans          = n_total_loans,
  n_porte_known_loans    = n_porte_known,
  n_dropped_year_edge    = n_dropped_year_edge,
  n_firm_cycle_pairs     = n_firm_cycle_pairs,
  n_crosstab_pairs       = n_crosstab,
  fallback_rate          = fallback_rate,
  top3_offdiag_cells     = offdiag_str
)

# ------------------------------------------------------------------------------
# 15. Write CSV outputs
# ------------------------------------------------------------------------------
message("\nStep 15: Writing output CSVs...")

# Table 1: 4x4 unweighted (long format)
out_4x4_uw <- tab4_unweighted[, .(
  porte_row = as.character(porte_row),
  a4_col,
  n       = N,
  row_pct
)]
fwrite(out_4x4_uw,
       file.path(OUTPUT_DIR, "alignment_porte_A4_4x4_unweighted.csv"))
message("  Written: alignment_porte_A4_4x4_unweighted.csv")

# Table 1w: 4x4 value-weighted (long format)
out_4x4_vw <- tab4_weighted[, .(
  porte_row = as.character(porte_row),
  a4_col,
  sum_value,
  row_pct_value
)]
fwrite(out_4x4_vw,
       file.path(OUTPUT_DIR, "alignment_porte_A4_4x4_value_weighted.csv"))
message("  Written: alignment_porte_A4_4x4_value_weighted.csv")

# Table 1c: 3x3 collapsed (long format, both weights)
out_3x3 <- tab3_combined[, .(
  porte_row_3,
  porte_label,
  a4_col_3,
  a4_label,
  n_unweighted   = N,
  sum_value,
  row_pct_uw,
  row_pct_vw
)]
fwrite(out_3x3,
       file.path(OUTPUT_DIR, "alignment_porte_A4_3x3_collapsed.csv"))
message("  Written: alignment_porte_A4_3x3_collapsed.csv")

# Alignment summary (metrics + counts as a wide row appended)
fwrite(summary_dt,
       file.path(OUTPUT_DIR, "alignment_summary.csv"))
fwrite(summary_counts,
       file.path(OUTPUT_DIR, "alignment_summary_counts.csv"))
message("  Written: alignment_summary.csv")
message("  Written: alignment_summary_counts.csv")

# ------------------------------------------------------------------------------
# 16. Build alignment_report.md
#     Plan §4 — plain-language verdict: A4 alignment check
# ------------------------------------------------------------------------------
message("\nStep 16: Writing alignment_report.md...")

fmt_pct  <- function(x, d = 1) ifelse(is.na(x), "-", paste0(round(100 * x, d), "%"))
fmt_num  <- function(x, d = 3) ifelse(is.na(x), "-", sprintf(paste0("%.", d, "f"), x))
fmt_int  <- function(x)        ifelse(is.na(x), "-", format(as.integer(x), big.mark = ","))

# E1 verdict
e1_pass <- (diag_vw >= THRESH_4X4_VALUE_WEIGHTED) && (diag_3x3_uw >= THRESH_3X3_UNWEIGHTED)
e1_pass_vw_only <- diag_vw >= THRESH_4X4_VALUE_WEIGHTED
e1_pass_3x3_only <- diag_3x3_uw >= THRESH_3X3_UNWEIGHTED

verdict_line <- if (e1_pass) {
  paste0("**PASS** — A4 aligns with BNDES porte on both thresholds (4x4 value-weighted diag = ",
         fmt_pct(diag_vw), " >= 60%; 3x3 unweighted diag = ", fmt_pct(diag_3x3_uw), " >= 65%).",
         " A4 is the Option-A candidate; proceed to E2 (coverage check).")
} else if (e1_pass_vw_only) {
  paste0("**MARGINAL PASS** — A4 passes the 4x4 value-weighted threshold (",
         fmt_pct(diag_vw), " >= 60%) but the 3x3 collapsed threshold is not met (",
         fmt_pct(diag_3x3_uw), " vs. 65%). ",
         "A4 advances to E2; the 3x3 weakness may reflect Micro/Pequena boundary noise.")
} else if (e1_pass_3x3_only) {
  paste0("**WEAK PASS** — A4 fails the 4x4 value-weighted threshold (",
         fmt_pct(diag_vw), " < 60%) but passes the 3x3 collapsed threshold (",
         fmt_pct(diag_3x3_uw), " >= 65%). ",
         "This suggests misalignment is concentrated at the Micro/Pequena or ",
         "Media/Grande boundaries. A3 (3-bin collapse) may be a more appropriate ",
         "production option. Flag for user review before E3.")
} else {
  paste0("**FAIL** — A4 fails both thresholds (4x4 value-weighted = ",
         fmt_pct(diag_vw), " < 60%; 3x3 = ", fmt_pct(diag_3x3_uw), " < 65%). ",
         "Employment thresholds do not reproduce BNDES porte. A4 interpretability ",
         "claim is weakened; A3 inherits the same misalignment. ",
         "Consider Option B or review porte/employment data for anomalies.")
}

# Confusion pattern note
confusion_note <- if (nrow(top3_offdiag) > 0L) {
  rows <- vapply(seq_len(nrow(top3_offdiag)), function(j) {
    r <- top3_offdiag[j]
    paste0("  - porte=", r$porte_label, " x A4=", r$a4_label,
           " (n=", format(r$N, big.mark = ","), ", ",
           fmt_pct(r$N / n_crosstab), " of crosstab)")
  }, character(1L))
  paste0("Largest off-diagonal cells (4x4 unweighted):\n", paste(rows, collapse = "\n"))
} else {
  "No off-diagonal cells (perfect alignment or empty table)."
}

# Build 4x4 display table for the report
build_md_4x4_uw <- function() {
  header <- paste0("| porte \\ A4 | Micro (1) | Pequena (2) | Media (3) | Grande (4) | Total |")
  sep    <- paste0("|---|---|---|---|---|---|")
  rows_out <- vapply(PORTE_LEVELS, function(p) {
    row_vals <- vapply(1L:4L, function(b) {
      r <- tab4_unweighted_lab[porte_label == p & a4_col == b]
      n_val  <- if (nrow(r)) r$N else 0L
      pct    <- if (nrow(r) && r$row_pct > 0) paste0(" (", round(100 * r$row_pct, 1), "%)") else ""
      paste0(format(n_val, big.mark = ","), pct)
    }, character(1L))
    row_total <- sum(tab4_unweighted_lab[porte_label == p, N])
    paste0("| **", p, "** | ", paste(row_vals, collapse = " | "), " | ",
           format(row_total, big.mark = ","), " |")
  }, character(1L))
  c(header, sep, rows_out)
}

build_md_4x4_vw <- function() {
  header <- paste0("| porte \\ A4 | Micro (1) | Pequena (2) | Media (3) | Grande (4) |")
  sep    <- paste0("|---|---|---|---|---|")
  rows_out <- vapply(PORTE_LEVELS, function(p) {
    row_vals <- vapply(1L:4L, function(b) {
      r <- tab4_weighted[porte_row == p & a4_col == b]
      if (!nrow(r)) return("0")
      pct <- if (r$row_pct_value > 0) paste0(" (", round(100 * r$row_pct_value, 1), "%)") else ""
      paste0(sprintf("%.1fM", r$sum_value / 1e6), pct)
    }, character(1L))
    paste0("| **", p, "** | ", paste(row_vals, collapse = " | "), " |")
  }, character(1L))
  c(header, sep, rows_out)
}

build_md_3x3 <- function() {
  labels3 <- c("MPME (1+2)", "Media (3)", "Grande (4)")
  header  <- paste0("| porte \\ A4 | MPME (1) | Media (2) | Grande (3) |")
  sep     <- paste0("|---|---|---|---|")
  rows_out <- vapply(1L:3L, function(p) {
    row_vals <- vapply(1L:3L, function(b) {
      r <- tab3_combined[porte_row_3 == p & a4_col_3 == b]
      if (!nrow(r)) return("0 / 0")
      paste0(format(r$n_unweighted, big.mark = ","),
             " (", round(100 * r$row_pct_uw, 1), "%",
             " / vw=", round(100 * r$row_pct_vw, 1), "%)")
    }, character(1L))
    paste0("| **", labels3[p], "** | ", paste(row_vals, collapse = " | "), " |")
  }, character(1L))
  c(header, sep, rows_out)
}

report_lines <- c(
  "# E1: Alignment of Option A4 with BNDES Porte",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Goal",
  "",
  "Cross-tabulate Option A4 (4-bin fixed employment thresholds) against BNDES porte",
  "(the size category recorded by BNDES at loan origination). Determines whether the",
  "interpretability claim 'A4 bin k corresponds to BNDES porte category k' holds in data.",
  "",
  "**F0 link:** `docs/PROJECT_BLUEPRINT.md` §3 F0 admissibility + interpretability.",
  "",
  "---",
  "",
  "## 1. Data Summary",
  "",
  paste0("- Total raw loans: ", fmt_int(n_total_loans)),
  paste0("- Loans with known (normalized) porte: ", fmt_int(n_porte_known),
         " (", fmt_pct(porte_known_share), " of post-filter loans)"),
  paste0("- Loans dropped (year outside cycle windows 2002-2003 or >=2018): ",
         fmt_int(n_dropped_year_edge)),
  paste0("- Unique (firm x cycle) pairs used in cross-tab: ", fmt_int(n_firm_cycle_pairs)),
  paste0("- Pairs with both porte and A4 bin: ", fmt_int(n_crosstab)),
  paste0("- Baseline fall-back rate: ", fmt_pct(fallback_rate, d = 2)),
  "",
  "---",
  "",
  "## 2. E1 Verdict",
  "",
  verdict_line,
  "",
  "| Metric | Value | Threshold | Pass |",
  "|--------|-------|-----------|------|",
  paste0("| 4x4 unweighted diagonal | ", fmt_pct(diag_uw), " | — | — |"),
  paste0("| 4x4 value-weighted diagonal | ", fmt_pct(diag_vw), " | >=60% | ",
         if (e1_pass_vw_only) "YES" else "NO", " |"),
  paste0("| 3x3 collapsed unweighted diagonal | ", fmt_pct(diag_3x3_uw), " | >=65% | ",
         if (e1_pass_3x3_only) "YES" else "NO", " |"),
  paste0("| 3x3 collapsed value-weighted diagonal | ", fmt_pct(diag_3x3_vw), " | — | — |"),
  "",
  "---",
  "",
  "## 3. 4x4 Cross-Tab: porte (rows) vs. A4 bin (cols)",
  "",
  "### Unweighted (firm x cycle counts; row % in parentheses)",
  "",
  build_md_4x4_uw(),
  "",
  "### Value-weighted (total real disbursement in millions R$; row % in parentheses)",
  "",
  build_md_4x4_vw(),
  "",
  "---",
  "",
  "## 4. 3x3 Collapsed Cross-Tab",
  "",
  "Collapse: A4 bins 1+2 -> MPME, bin 3 -> Media, bin 4 -> Grande.",
  "porte: Micro+Pequena -> MPME, Media -> 2, Grande -> 3.",
  "Cells show: n (row_pct_unweighted / vw=row_pct_value_weighted).",
  "",
  build_md_3x3(),
  "",
  "---",
  "",
  "## 5. Confusion Pattern",
  "",
  confusion_note,
  "",
  "---",
  "",
  "## 6. Implied A3 Alignment",
  "",
  paste0("Option A3 (3-bin collapse) inherits A4's alignment by construction.",
         " The 3x3 collapsed diagonal (", fmt_pct(diag_3x3_uw), " unweighted,",
         " ", fmt_pct(diag_3x3_vw), " value-weighted) is the alignment metric",
         " for A3. No separate E1 run is needed for A3."),
  "",
  "---",
  "",
  "## 7. Files Written",
  "",
  "| File | Description |",
  "|------|-------------|",
  "| `alignment_porte_A4_4x4_unweighted.csv` | 4x4 long format: porte_row, a4_col, n, row_pct |",
  "| `alignment_porte_A4_4x4_value_weighted.csv` | 4x4 long format: porte_row, a4_col, sum_value, row_pct_value |",
  "| `alignment_porte_A4_3x3_collapsed.csv` | 3x3 long format: both unweighted and value-weighted |",
  "| `alignment_summary.csv` | Top-line metrics with threshold and pass/fail |",
  "| `alignment_summary_counts.csv` | n_loans, n_porte_known, n_dropped, n_firm_cycle_pairs, fall-back rate |",
  ""
)

writeLines(report_lines,
           file.path(OUTPUT_DIR, "alignment_report.md"))
message("  Written: alignment_report.md")

# ------------------------------------------------------------------------------
# 17. Console summary
# ------------------------------------------------------------------------------
message("\n")
message("=================================================================")
message("  E1: A4 Alignment vs. BNDES Porte — Summary")
message("=================================================================")
message(sprintf("  Total raw loans:            %s", fmt_int(n_total_loans)))
message(sprintf("  Porte-known loans:          %s (%s)",
                fmt_int(n_porte_known), fmt_pct(porte_known_share)))
message(sprintf("  Dropped (year edge):        %s", fmt_int(n_dropped_year_edge)))
message(sprintf("  (firm x cycle) pairs:       %s", fmt_int(n_firm_cycle_pairs)))
message(sprintf("  Cross-tab pairs:            %s", fmt_int(n_crosstab)))
message("")
message(sprintf("  4x4 unweighted diag:        %s", fmt_pct(diag_uw)))
message(sprintf("  4x4 value-weighted diag:    %s  (threshold: >=60%%)", fmt_pct(diag_vw)))
message(sprintf("  3x3 collapsed uw diag:      %s  (threshold: >=65%%)", fmt_pct(diag_3x3_uw)))
message(sprintf("  3x3 collapsed vw diag:      %s", fmt_pct(diag_3x3_vw)))
message("")
message(sprintf("  E1 verdict: %s", if (e1_pass) "PASS" else if (e1_pass_vw_only) "MARGINAL PASS" else if (e1_pass_3x3_only) "WEAK PASS" else "FAIL"))
message("")
message("  Output files written to:")
message("    ", OUTPUT_DIR)
message("=================================================================")

# ------------------------------------------------------------------------------
# 18. Return invisible list for interactive inspection
# ------------------------------------------------------------------------------
invisible(list(
  crosstab_dt       = crosstab_dt,
  tab4_unweighted   = tab4_unweighted,
  tab4_weighted     = tab4_weighted,
  tab3_combined     = tab3_combined,
  summary_dt        = summary_dt,
  summary_counts    = summary_counts,
  diag_uw           = diag_uw,
  diag_vw           = diag_vw,
  diag_3x3_uw       = diag_3x3_uw,
  diag_3x3_vw       = diag_3x3_vw,
  e1_pass           = e1_pass,
  val_col_used      = val_col
))
