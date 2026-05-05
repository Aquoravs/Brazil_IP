# ==============================================================================
# 01c_alignment_unmatched_diagnostic.R
#
# Coverage gap diagnostic for the E1 alignment inner-join.
#
# In 01b_size_bin_alignment_yearly.R, an inner join on (firm_id, year)
# between bndes_loan_level.qs2 and rais_bndes_reconstructed.fst matched
# only 742,404 of 1,653,310 cleaned loans (55.1% loss). This script
# diagnoses what is being lost and recommends a treatment.
#
# F-link: F0 admissibility (docs/PROJECT_BLUEPRINT.md §3 F0).
#   Coverage of the RAIS-BNDES match underpins every bin assignment.
#   Understanding the unmatched mass is prerequisite to deciding whether
#   to impute, drop, or conditionally impute.
#
# Inputs:
#   data/processed/bndes_loan_level.qs2
#     columns used: firm_id, year, size, value_dis_real_2018, cnae_section
#   data/processed/rais_bndes_reconstructed.fst
#     columns used: firm_id, year (column-selective)
#
# Outputs (explorations/anderson_rubin/diagnostics/output/):
#   unmatched_by_year.csv
#   unmatched_by_porte.csv
#   unmatched_by_cnae.csv
#   unmatched_value_distribution.csv
#   unmatched_firm_persistence.csv
#   unmatched_firm_persistence_summary.csv
#   alignment_yearly_imputed_summary.csv  (if conditional imputation recommended)
#   alignment_unmatched_diagnostic.md
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
# 2. Paths via here::here() (INV-16: no absolute paths, no setwd())
# ------------------------------------------------------------------------------
PROCESSED_DIR <- here::here("data", "processed")
OUTPUT_DIR    <- here::here(
  "explorations", "anderson_rubin", "diagnostics", "output"
)

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  message("Created output directory: ", OUTPUT_DIR)
}

# ------------------------------------------------------------------------------
# 3. Load BNDES loan-level data — reproduce clean set from 01b
# ------------------------------------------------------------------------------
message("Loading BNDES loan-level...")
loans_raw <- setDT(qs_read(file.path(PROCESSED_DIR, "bndes_loan_level.qs2")))
message(sprintf("  Raw rows: %s", format(nrow(loans_raw), big.mark = ",")))

# Defensive val_col lookup — mirrors 01b lines 46-48
val_col <- grep("^value_dis.*real.*2018", names(loans_raw), value = TRUE)[1L]
if (is.na(val_col)) {
  message("  Warning: no ^value_dis.*real.*2018 column found; falling back to 'value_dis'.")
  val_col <- "value_dis"
}
stopifnot(val_col %in% names(loans_raw))
message(sprintf("  Real-value column: '%s'", val_col))

# Rename to internal name
loans_raw[, value_dis_real := get(val_col)]

# Coerce types — must be character before any merge to avoid type-mismatch bug
loans_raw[, firm_id := as.character(firm_id)]
loans_raw[, year    := as.integer(year)]

n_raw <- nrow(loans_raw)

# Reproduce the bndes_porte_norm() function from 01b
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

loans_raw[, porte := bndes_porte_norm(size)]

# Drop loans with missing firm_id, real value, size/porte, or year — mirrors 01b
n_before <- n_raw
loans_raw <- loans_raw[!is.na(firm_id) & firm_id != ""]
n_after_firm <- nrow(loans_raw)

loans_raw <- loans_raw[!is.na(value_dis_real)]
n_after_val <- nrow(loans_raw)

loans_raw <- loans_raw[!is.na(porte)]
n_after_porte <- nrow(loans_raw)

loans_raw <- loans_raw[!is.na(year)]
n_clean <- nrow(loans_raw)

message(sprintf("  Dropped (missing firm_id):    %s", format(n_before     - n_after_firm,  big.mark = ",")))
message(sprintf("  Dropped (missing value_dis):  %s", format(n_after_firm - n_after_val,   big.mark = ",")))
message(sprintf("  Dropped (missing porte):      %s", format(n_after_val  - n_after_porte, big.mark = ",")))
message(sprintf("  Dropped (missing year):       %s", format(n_after_porte - n_clean,      big.mark = ",")))
message(sprintf("  Clean loans for diagnostic:   %s", format(n_clean, big.mark = ",")))

# Keep only columns needed for diagnostics
loans <- loans_raw[, .(firm_id, year, porte, value_dis_real, cnae_section)]

# Check if cnae_section is available and non-trivial
has_cnae <- "cnae_section" %in% names(loans) &&
  loans[!is.na(cnae_section) & cnae_section != "", .N] > 0L
message(sprintf("  cnae_section available: %s", has_cnae))

rm(loans_raw)
invisible(gc())

# ------------------------------------------------------------------------------
# 4. Load RAIS (firm_id, year only) — column-selective for memory efficiency
# ------------------------------------------------------------------------------
message("Loading RAIS panel (firm_id + year only, column-selective)...")
rais_fy_raw <- fst::read_fst(
  file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst"),
  columns = c("firm_id", "year"),
  as.data.table = TRUE
)
rais_fy_raw[, firm_id := as.character(firm_id)]
rais_fy_raw[, year    := as.integer(year)]
message(sprintf("  RAIS rows loaded: %s", format(nrow(rais_fy_raw), big.mark = ",")))

# Unique (firm_id, year) combinations in RAIS
rais_fy <- unique(rais_fy_raw[, .(firm_id, year)])
message(sprintf("  Unique RAIS (firm, year) pairs: %s", format(nrow(rais_fy), big.mark = ",")))

# Also build per-firm RAIS year count (needed for Type A / Type B diagnosis)
# This is the full RAIS coverage — all years any firm appears
rais_firm_years <- rais_fy_raw[, .(n_rais_years_anywhere = .N), by = firm_id]
message(sprintf("  Unique RAIS firms: %s", format(nrow(rais_firm_years), big.mark = ",")))

rm(rais_fy_raw)
invisible(gc())

# ------------------------------------------------------------------------------
# 5. Classify each loan as matched or unmatched
#    matched   = borrower firm has a RAIS row in the loan year
#    unmatched = no RAIS row for (firm_id, year)
# ------------------------------------------------------------------------------
message("Classifying loans as matched / unmatched...")

# Flag: does this (firm_id, year) exist in RAIS?
rais_fy[, in_rais := TRUE]
loans_flagged <- merge(
  loans,
  rais_fy,
  by  = c("firm_id", "year"),
  all.x = TRUE
)
loans_flagged[is.na(in_rais), in_rais := FALSE]

n_matched   <- loans_flagged[in_rais == TRUE,  .N]
n_unmatched <- loans_flagged[in_rais == FALSE, .N]
stopifnot(n_matched + n_unmatched == n_clean)

val_total    <- sum(loans_flagged$value_dis_real, na.rm = TRUE)
val_matched  <- loans_flagged[in_rais == TRUE,  sum(value_dis_real, na.rm = TRUE)]
val_unmatched <- loans_flagged[in_rais == FALSE, sum(value_dis_real, na.rm = TRUE)]

message(sprintf("  Matched:   %s (%.1f%% of loans; %.1f%% of value)",
                format(n_matched,   big.mark = ","),
                100 * n_matched   / n_clean,
                100 * val_matched  / val_total))
message(sprintf("  Unmatched: %s (%.1f%% of loans; %.1f%% of value)",
                format(n_unmatched, big.mark = ","),
                100 * n_unmatched / n_clean,
                100 * val_unmatched / val_total))

# Convenience subsets
matched   <- loans_flagged[in_rais == TRUE]
unmatched <- loans_flagged[in_rais == FALSE]

# ------------------------------------------------------------------------------
# 6. Output 1: unmatched_by_year.csv
# ------------------------------------------------------------------------------
message("Building unmatched_by_year.csv...")

by_year <- loans_flagged[, .(
  n_loans       = .N,
  value_sum     = sum(value_dis_real, na.rm = TRUE)
), by = .(year, in_rais)]

# Pivot to wide
by_year_m  <- by_year[in_rais == TRUE,  .(year, n_matched   = n_loans, value_matched   = value_sum)]
by_year_um <- by_year[in_rais == FALSE, .(year, n_unmatched = n_loans, value_unmatched = value_sum)]

year_range <- data.table(year = sort(unique(loans_flagged$year)))
out_year   <- merge(year_range, by_year_m,  by = "year", all.x = TRUE)
out_year   <- merge(out_year,   by_year_um, by = "year", all.x = TRUE)
out_year[is.na(n_matched),       n_matched       := 0L]
out_year[is.na(n_unmatched),     n_unmatched     := 0L]
out_year[is.na(value_matched),   value_matched   := 0]
out_year[is.na(value_unmatched), value_unmatched := 0]

out_year[, share_unmatched       := fifelse(
  n_matched + n_unmatched > 0L,
  n_unmatched / (n_matched + n_unmatched),
  NA_real_
)]
out_year[, share_value_unmatched := fifelse(
  value_matched + value_unmatched > 0,
  value_unmatched / (value_matched + value_unmatched),
  NA_real_
)]

setorder(out_year, year)
fwrite(out_year, file.path(OUTPUT_DIR, "unmatched_by_year.csv"))
message("  Written: unmatched_by_year.csv")

# Year-loss pattern for report
min_share_yr  <- out_year[which.min(share_unmatched)]
max_share_yr  <- out_year[which.max(share_unmatched)]
early_yrs     <- out_year[year <= 2004, mean(share_unmatched, na.rm = TRUE)]
late_yrs      <- out_year[year >= 2015, mean(share_unmatched, na.rm = TRUE)]
mid_yrs       <- out_year[year >= 2005 & year <= 2014, mean(share_unmatched, na.rm = TRUE)]

# ------------------------------------------------------------------------------
# 7. Output 2: unmatched_by_porte.csv
# ------------------------------------------------------------------------------
message("Building unmatched_by_porte.csv...")

by_porte_m  <- matched[,   .(n_matched   = .N, value_matched   = sum(value_dis_real, na.rm = TRUE)), by = porte]
by_porte_um <- unmatched[, .(n_unmatched = .N, value_unmatched = sum(value_dis_real, na.rm = TRUE)), by = porte]

porte_grid  <- data.table(porte = c("Micro", "Pequena", "Media", "Grande"))
out_porte   <- merge(porte_grid, by_porte_m,  by = "porte", all.x = TRUE)
out_porte   <- merge(out_porte,  by_porte_um, by = "porte", all.x = TRUE)
out_porte[is.na(n_matched),       n_matched       := 0L]
out_porte[is.na(n_unmatched),     n_unmatched     := 0L]
out_porte[is.na(value_matched),   value_matched   := 0]
out_porte[is.na(value_unmatched), value_unmatched := 0]
out_porte[, share_unmatched       := fifelse(
  n_matched + n_unmatched > 0L,
  n_unmatched / (n_matched + n_unmatched),
  NA_real_
)]
out_porte[, share_value_unmatched := fifelse(
  value_matched + value_unmatched > 0,
  value_unmatched / (value_matched + value_unmatched),
  NA_real_
)]

fwrite(out_porte, file.path(OUTPUT_DIR, "unmatched_by_porte.csv"))
message("  Written: unmatched_by_porte.csv")

# ------------------------------------------------------------------------------
# 8. Output 3: unmatched_by_cnae.csv
# ------------------------------------------------------------------------------
message("Building unmatched_by_cnae.csv...")

if (has_cnae) {
  by_cnae_m  <- matched[!is.na(cnae_section) & cnae_section != "",
                         .(n_matched   = .N, value_matched   = sum(value_dis_real, na.rm = TRUE)),
                         by = cnae_section]
  by_cnae_um <- unmatched[!is.na(cnae_section) & cnae_section != "",
                           .(n_unmatched = .N, value_unmatched = sum(value_dis_real, na.rm = TRUE)),
                           by = cnae_section]

  all_cnae  <- data.table(cnae_section = sort(union(by_cnae_m$cnae_section,
                                                      by_cnae_um$cnae_section)))
  out_cnae  <- merge(all_cnae, by_cnae_m,  by = "cnae_section", all.x = TRUE)
  out_cnae  <- merge(out_cnae, by_cnae_um, by = "cnae_section", all.x = TRUE)
  out_cnae[is.na(n_matched),       n_matched       := 0L]
  out_cnae[is.na(n_unmatched),     n_unmatched     := 0L]
  out_cnae[is.na(value_matched),   value_matched   := 0]
  out_cnae[is.na(value_unmatched), value_unmatched := 0]
  out_cnae[, share_unmatched       := fifelse(
    n_matched + n_unmatched > 0L,
    n_unmatched / (n_matched + n_unmatched),
    NA_real_
  )]
  out_cnae[, share_value_unmatched := fifelse(
    value_matched + value_unmatched > 0,
    value_unmatched / (value_matched + value_unmatched),
    NA_real_
  )]
  setorder(out_cnae, cnae_section)
  fwrite(out_cnae, file.path(OUTPUT_DIR, "unmatched_by_cnae.csv"))
  message("  Written: unmatched_by_cnae.csv")
} else {
  out_cnae <- data.table(note = "cnae_section not in bndes_loan_level.qs2")
  fwrite(out_cnae, file.path(OUTPUT_DIR, "unmatched_by_cnae.csv"))
  message("  Written: unmatched_by_cnae.csv (note: cnae_section not available)")
}

# ------------------------------------------------------------------------------
# 9. Output 4: unmatched_value_distribution.csv
# ------------------------------------------------------------------------------
message("Building unmatched_value_distribution.csv...")

quantile_dt <- function(grp, vals) {
  v <- vals[!is.na(vals)]
  data.table(
    group        = grp,
    n            = length(v),
    mean_value   = mean(v),
    median_value = median(v),
    p10          = quantile(v, 0.10),
    p25          = quantile(v, 0.25),
    p75          = quantile(v, 0.75),
    p90          = quantile(v, 0.90),
    p99          = quantile(v, 0.99),
    total_value  = sum(v)
  )
}

out_val_dist <- rbindlist(list(
  quantile_dt("matched",   matched$value_dis_real),
  quantile_dt("unmatched", unmatched$value_dis_real)
))
fwrite(out_val_dist, file.path(OUTPUT_DIR, "unmatched_value_distribution.csv"))
message("  Written: unmatched_value_distribution.csv")

# ------------------------------------------------------------------------------
# 10. Output 5: unmatched_firm_persistence.csv and summary
#
#  For each firm_id that has at least one unmatched loan:
#    n_loans_total, n_loans_matched, n_loans_unmatched,
#    n_rais_years_anywhere (from rais_firm_years — all RAIS years, not just loan years)
#  Then:
#    Type A: n_rais_years_anywhere == 0  -> never in RAIS
#    Type B: n_rais_years_anywhere >= 1  -> in RAIS somewhere, but not in unmatched loan year
# ------------------------------------------------------------------------------
message("Building firm-level persistence table...")

# Per-firm loan counts (over all clean loans, not just unmatched)
firm_loan_counts <- loans_flagged[, .(
  n_loans_total    = .N,
  n_loans_matched  = sum(in_rais == TRUE,  na.rm = TRUE),
  n_loans_unmatched = sum(in_rais == FALSE, na.rm = TRUE)
), by = firm_id]

# Restrict to firms with at least one unmatched loan
unmatched_firms <- firm_loan_counts[n_loans_unmatched >= 1L]
message(sprintf("  Firms with >= 1 unmatched loan: %s",
                format(nrow(unmatched_firms), big.mark = ",")))

# Attach RAIS year count (0 if firm never appears in RAIS)
unmatched_firms <- merge(
  unmatched_firms,
  rais_firm_years,
  by = "firm_id",
  all.x = TRUE
)
unmatched_firms[is.na(n_rais_years_anywhere), n_rais_years_anywhere := 0L]

# Classify
unmatched_firms[, firm_type := fifelse(
  n_rais_years_anywhere == 0L, "A_never_in_RAIS", "B_sometimes_in_RAIS"
)]

fwrite(unmatched_firms, file.path(OUTPUT_DIR, "unmatched_firm_persistence.csv"))
message("  Written: unmatched_firm_persistence.csv")

# Summary
n_unmatched_firms <- nrow(unmatched_firms)
n_type_a  <- unmatched_firms[firm_type == "A_never_in_RAIS",    .N]
n_type_b  <- unmatched_firms[firm_type == "B_sometimes_in_RAIS", .N]
share_type_a <- n_type_a / n_unmatched_firms
share_type_b <- n_type_b / n_unmatched_firms

# Among Type B: distribution of n_rais_years_anywhere
type_b_rais_years <- unmatched_firms[firm_type == "B_sometimes_in_RAIS", n_rais_years_anywhere]
type_b_median_rais_yrs <- if (length(type_b_rais_years) > 0L) {
  median(type_b_rais_years)
} else NA_real_

# Loan-level decomposition by firm type
loans_with_type <- merge(
  loans_flagged[in_rais == FALSE, .(firm_id, year, porte, value_dis_real)],
  unmatched_firms[, .(firm_id, firm_type)],
  by = "firm_id",
  all.x = TRUE
)
n_unmatched_loans_typeA <- loans_with_type[firm_type == "A_never_in_RAIS",    .N]
n_unmatched_loans_typeB <- loans_with_type[firm_type == "B_sometimes_in_RAIS", .N]
val_unmatched_typeA <- loans_with_type[firm_type == "A_never_in_RAIS",    sum(value_dis_real, na.rm = TRUE)]
val_unmatched_typeB <- loans_with_type[firm_type == "B_sometimes_in_RAIS", sum(value_dis_real, na.rm = TRUE)]

persistence_summary <- data.table(
  n_firms_with_unmatched_loans   = n_unmatched_firms,
  n_type_A_never_in_rais         = n_type_a,
  n_type_B_sometimes_in_rais     = n_type_b,
  share_type_A                   = share_type_a,
  share_type_B                   = share_type_b,
  n_loans_unmatched_type_A       = n_unmatched_loans_typeA,
  n_loans_unmatched_type_B       = n_unmatched_loans_typeB,
  share_unmatched_loans_type_A   = n_unmatched_loans_typeA / n_unmatched,
  share_unmatched_loans_type_B   = n_unmatched_loans_typeB / n_unmatched,
  val_unmatched_type_A           = val_unmatched_typeA,
  val_unmatched_type_B           = val_unmatched_typeB,
  type_B_median_rais_years       = type_b_median_rais_yrs
)

fwrite(persistence_summary,
       file.path(OUTPUT_DIR, "unmatched_firm_persistence_summary.csv"))
message("  Written: unmatched_firm_persistence_summary.csv")

message(sprintf("  Type A (never in RAIS):     %s firms (%.1f%% of unmatched-loan firms)",
                format(n_type_a, big.mark = ","), 100 * share_type_a))
message(sprintf("  Type B (sometimes in RAIS): %s firms (%.1f%% of unmatched-loan firms)",
                format(n_type_b, big.mark = ","), 100 * share_type_b))
message(sprintf("  Unmatched loans from Type A: %s (%.1f%%)",
                format(n_unmatched_loans_typeA, big.mark = ","),
                100 * n_unmatched_loans_typeA / n_unmatched))
message(sprintf("  Unmatched loans from Type B: %s (%.1f%%)",
                format(n_unmatched_loans_typeB, big.mark = ","),
                100 * n_unmatched_loans_typeB / n_unmatched))

# ------------------------------------------------------------------------------
# 11. Optional Output: imputed alignment tables
#
#  If Type A is the dominant failure mode and Micro/Pequena dominate the
#  unmatched porte mix, conditional imputation is warranted:
#    - tag unmatched loans with porte in {Micro, Pequena} as size_bin_A4 = 1
#      (treat-as-Micro, 0 employees assumed)
#    - drop unmatched loans with porte in {Media, Grande}
#  Then recompute the 4x4 and 3x3 cross-tabs on matched + imputed set.
#
#  This section computes the imputed diagonals for all three treatment
#  alternatives and stores them in alignment_yearly_imputed_summary.csv.
# ------------------------------------------------------------------------------
message("Building imputed alignment summary (all three treatment alternatives)...")

# The matched cross-tab base: take from matched loans
# Assign A4 bin from RAIS n_employees (inner-join confirmed these exist)
rais_fy_emp <- fst::read_fst(
  file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst"),
  columns = c("firm_id", "year", "n_employees"),
  as.data.table = TRUE
)
rais_fy_emp[, firm_id    := as.character(firm_id)]
rais_fy_emp[, year       := as.integer(year)]
rais_fy_emp[, n_employees := as.numeric(n_employees)]

# Collapse to (firm, year) totals — mirrors 01b lines 93-97
rais_fy_emp <- rais_fy_emp[, .(
  n_employees = sum(n_employees, na.rm = TRUE),
  has_obs     = any(!is.na(n_employees))
), by = .(firm_id, year)][has_obs == TRUE, .(firm_id, year, n_employees)]

# Assign A4 bin
rais_fy_emp[, size_bin_A4 := fcase(
  n_employees >=   0 & n_employees <=   9, 1L,
  n_employees >=  10 & n_employees <=  49, 2L,
  n_employees >=  50 & n_employees <= 499, 3L,
  n_employees >= 500,                      4L,
  default = NA_integer_
)]

# Join A4 bin to matched loans
matched_with_bin <- merge(
  matched[, .(firm_id, year, porte, value_dis_real)],
  rais_fy_emp[, .(firm_id, year, size_bin_A4)],
  by = c("firm_id", "year"),
  all.x = FALSE
)
matched_with_bin <- matched_with_bin[!is.na(size_bin_A4)]
n_crosstab_base  <- nrow(matched_with_bin)
message(sprintf("  Base cross-tab (matched + A4 known): %s", format(n_crosstab_base, big.mark = ",")))

rm(rais_fy_emp)
invisible(gc())

PORTE_LEVELS_VEC <- c("Micro", "Pequena", "Media", "Grande")
porte_to_a4      <- c(Micro = 1L, Pequena = 2L, Media = 3L, Grande = 4L)

compute_diags <- function(dt) {
  # Unweighted 4x4
  tab_uw <- dt[, .N, by = .(porte, size_bin_A4)]
  diag_uw  <- tab_uw[porte_to_a4[porte] == size_bin_A4, sum(N)] / dt[, .N]

  # Value-weighted 4x4
  tab_vw <- dt[, .(V = sum(value_dis_real, na.rm = TRUE)), by = .(porte, size_bin_A4)]
  v_total  <- dt[, sum(value_dis_real, na.rm = TRUE)]
  diag_vw  <- tab_vw[porte_to_a4[porte] == size_bin_A4, sum(V)] / v_total

  # 3x3 collapsed
  dt2 <- copy(dt)
  dt2[, porte_3 := fcase(
    porte %in% c("Micro", "Pequena"), 1L,
    porte == "Media",                 2L,
    porte == "Grande",                3L
  )]
  dt2[, a4_3 := fcase(
    size_bin_A4 %in% c(1L, 2L), 1L,
    size_bin_A4 == 3L,           2L,
    size_bin_A4 == 4L,           3L
  )]
  n3 <- dt2[!is.na(porte_3) & !is.na(a4_3), .N]
  tab3 <- dt2[!is.na(porte_3) & !is.na(a4_3), .N, by = .(porte_3, a4_3)]
  diag_3x3_uw <- tab3[porte_3 == a4_3, sum(N)] / n3

  list(diag_uw = diag_uw, diag_vw = diag_vw, diag_3x3_uw = diag_3x3_uw,
       n = nrow(dt))
}

# --- Treatment 1: drop all unmatched (current behaviour, base case)
t1 <- compute_diags(matched_with_bin)

# --- Treatment 2: treat-as-Micro — impute size_bin_A4 = 1 for ALL unmatched
unmatched_imputed_all <- unmatched[, .(firm_id, year, porte, value_dis_real)]
unmatched_imputed_all[, size_bin_A4 := 1L]
full_t2 <- rbindlist(list(matched_with_bin, unmatched_imputed_all), fill = TRUE)
t2 <- compute_diags(full_t2)

# --- Treatment 3: conditional imputation
#   impute size_bin_A4 = 1 only for porte in {Micro, Pequena}; drop Media/Grande
unmatched_cond <- unmatched[porte %in% c("Micro", "Pequena"),
                             .(firm_id, year, porte, value_dis_real)]
unmatched_cond[, size_bin_A4 := 1L]
n_dropped_mg <- unmatched[porte %in% c("Media", "Grande"), .N]
full_t3 <- rbindlist(list(matched_with_bin, unmatched_cond), fill = TRUE)
t3 <- compute_diags(full_t3)

imputed_summary <- data.table(
  treatment = c(
    "T1_drop_unmatched",
    "T2_treat_as_micro_all",
    "T3_conditional_micro_pequena"
  ),
  n_loans           = c(t1$n, t2$n, t3$n),
  diag_4x4_uw       = c(t1$diag_uw,      t2$diag_uw,      t3$diag_uw),
  diag_4x4_vw       = c(t1$diag_vw,      t2$diag_vw,      t3$diag_vw),
  diag_3x3_uw       = c(t1$diag_3x3_uw,  t2$diag_3x3_uw,  t3$diag_3x3_uw),
  pass_4x4_vw_60pct = c(t1$diag_vw >= 0.60, t2$diag_vw >= 0.60, t3$diag_vw >= 0.60),
  pass_3x3_uw_65pct = c(t1$diag_3x3_uw >= 0.65, t2$diag_3x3_uw >= 0.65, t3$diag_3x3_uw >= 0.65),
  n_unmatched_added = c(0L, n_unmatched, nrow(unmatched_cond)),
  n_unmatched_dropped = c(n_unmatched, 0L, n_dropped_mg)
)

fwrite(imputed_summary,
       file.path(OUTPUT_DIR, "alignment_yearly_imputed_summary.csv"))
message("  Written: alignment_yearly_imputed_summary.csv")

# ------------------------------------------------------------------------------
# 12. Markdown report
# ------------------------------------------------------------------------------
message("Writing alignment_unmatched_diagnostic.md...")

fmt_pct <- function(x, d = 1) {
  if (is.na(x)) return("-")
  sprintf(paste0("%.", d, "f%%"), 100 * x)
}
fmt_int <- function(x) format(as.integer(round(x)), big.mark = ",")
fmt_num <- function(x, d = 2) sprintf(paste0("%.", d, "f"), x)

# Year table (by_year, compact)
year_rows <- vapply(seq_len(nrow(out_year)), function(i) {
  r <- out_year[i]
  sprintf("| %d | %s | %s | %s | %s |",
          r$year,
          fmt_int(r$n_matched),
          fmt_int(r$n_unmatched),
          fmt_pct(r$share_unmatched),
          fmt_pct(r$share_value_unmatched))
}, character(1L))

# Porte table
porte_rows <- vapply(seq_len(nrow(out_porte)), function(i) {
  r <- out_porte[i]
  sprintf("| %s | %s | %s | %s | %s |",
          r$porte,
          fmt_int(r$n_matched),
          fmt_int(r$n_unmatched),
          fmt_pct(r$share_unmatched),
          fmt_pct(r$share_value_unmatched))
}, character(1L))

# CNAE table (if available)
if (has_cnae && nrow(out_cnae) > 1L) {
  cnae_rows <- vapply(seq_len(nrow(out_cnae)), function(i) {
    r <- out_cnae[i]
    sprintf("| %s | %s | %s | %s | %s |",
            r$cnae_section,
            fmt_int(r$n_matched),
            fmt_int(r$n_unmatched),
            fmt_pct(r$share_unmatched),
            fmt_pct(r$share_value_unmatched))
  }, character(1L))
}

# Value distribution rows
val_rows <- vapply(seq_len(nrow(out_val_dist)), function(i) {
  r <- out_val_dist[i]
  sprintf("| %s | %s | %s | %s | %s | %s |",
          r$group,
          fmt_int(r$n),
          sprintf("%.0f", r$mean_value / 1e3),
          sprintf("%.0f", r$median_value / 1e3),
          sprintf("%.0f", r$p10 / 1e3),
          sprintf("%.0f", r$p90 / 1e3))
}, character(1L))

# Imputed diagonals table
imputed_rows <- vapply(seq_len(nrow(imputed_summary)), function(i) {
  r <- imputed_summary[i]
  sprintf("| %s | %s | %s | %s | %s | %s | %s |",
          r$treatment,
          fmt_int(r$n_loans),
          fmt_pct(r$diag_4x4_uw),
          fmt_pct(r$diag_4x4_vw),
          fmt_pct(r$diag_3x3_uw),
          if (r$pass_4x4_vw_60pct) "YES" else "NO",
          if (r$pass_3x3_uw_65pct) "YES" else "NO")
}, character(1L))

# Recommendation logic
# Primary signal: if Type A (never in RAIS) is the dominant fraction of
# unmatched-loan firms, and the unmatched mass skews Micro/Pequena, then
# conditional imputation is appropriate (Type A sole-proprietors that BNDES
# categorises as Micro/Pequena but that never appear in formal employment).
# If Type B (panel gaps) dominates, the mismatch is a coverage artefact,
# not a formal/informal split; dropping with documentation is more defensible.

micro_pequena_share_unmatched <- out_porte[porte %in% c("Micro", "Pequena"),
  sum(n_unmatched)] / n_unmatched
media_grande_share_unmatched  <- out_porte[porte %in% c("Media", "Grande"),
  sum(n_unmatched)] / n_unmatched

# Decision logic:
#   Primary criterion: if Type A (never in RAIS) dominates (>= 60% of firms)
#     AND Micro/Pequena dominate the unmatched porte mix (>= 60%):
#     -> conditional imputation (impute bin 1 for Micro/Pequena; drop Media/Grande)
#   If Type A dominates but Media/Grande are substantial (Micro/Pequena < 60%):
#     -> treat-as-Micro imputation for all (if Micro/Pequena still majority >= 50%)
#        or drop (if the unmatched porte mix is too heterogeneous)
#   If Type B dominates (>= 60%): panel coverage gap; drop with documentation
if (share_type_a >= 0.60 && micro_pequena_share_unmatched >= 0.60) {
  recommendation <- "conditional_imputation"
} else if (share_type_a >= 0.60 && micro_pequena_share_unmatched >= 0.50) {
  recommendation <- "treat_as_micro_imputation"
} else if (share_type_b >= 0.60) {
  recommendation <- "drop_with_documented_loss"
} else if (micro_pequena_share_unmatched >= 0.85) {
  recommendation <- "treat_as_micro_imputation"
} else {
  recommendation <- "drop_with_documented_loss"
}

rec_t3 <- imputed_summary[treatment == "T3_conditional_micro_pequena"]
rec_t1 <- imputed_summary[treatment == "T1_drop_unmatched"]

rec_text <- if (recommendation == "conditional_imputation") {
  c(
    paste0(
      "**Recommended treatment: Conditional imputation** (impute size_bin_A4 = 1 ",
      "for unmatched loans where stated porte = Micro or Pequena; drop unmatched ",
      "loans with porte = Media or Grande). ",
      "Rationale: (1) ", fmt_pct(share_type_a, 1), " of firms with unmatched loans ",
      "never appear in RAIS at any point (Type A), consistent with sole-proprietors ",
      "and unregistered micro-enterprises that hold BNDES credit but are outside ",
      "formal payroll — these firms are economically Micro. ",
      "(2) ", fmt_pct(micro_pequena_share_unmatched, 1), " of unmatched loans are ",
      "categorised as Micro/Pequena by BNDES itself, making the treat-as-bin-1 ",
      "assumption conservative rather than speculative. ",
      "(3) Only ", fmt_int(n_dropped_mg), " Media/Grande unmatched loans are dropped ",
      "under T3 — a small share of the unmatched mass whose RAIS absence cannot be ",
      "plausibly explained by informality. ",
      "(4) The conditional-imputation cross-tab (T3) yields a 4x4 value-weighted ",
      "diagonal of ", fmt_pct(rec_t3$diag_4x4_vw), " and a 3x3 unweighted diagonal ",
      "of ", fmt_pct(rec_t3$diag_3x3_uw), ", compared with ",
      fmt_pct(rec_t1$diag_4x4_vw), " / ", fmt_pct(rec_t1$diag_3x3_uw),
      " for the drop-only baseline."
    )
  )
} else if (recommendation == "treat_as_micro_imputation") {
  c(
    paste0(
      "**Recommended treatment: Treat-as-Micro imputation** (assume unmatched = ",
      "0 employees → A4 Bin 1). Rationale: ",
      fmt_pct(micro_pequena_share_unmatched, 1), " of unmatched loans are ",
      "BNDES-classified Micro/Pequena and ", fmt_pct(share_type_a, 1),
      " of unmatched-loan firms never appear in RAIS, consistent with the ",
      "informal/sole-proprietor hypothesis. The treat-as-Micro assumption is ",
      "conservative and aligns with BNDES's own porte assignment. Imputing all ",
      "unmatched rows (T2) yields diagonals of ", fmt_pct(imputed_summary[treatment == "T2_treat_as_micro_all", diag_4x4_vw]),
      " (4x4 vw) and ", fmt_pct(imputed_summary[treatment == "T2_treat_as_micro_all", diag_3x3_uw]),
      " (3x3 uw)."
    )
  )
} else {
  c(
    paste0(
      "**Recommended treatment: Drop with documented loss** (keep current ",
      fmt_int(n_matched), "-loan cross-tab; document the ",
      fmt_pct(n_unmatched / n_clean), " loss rate). Rationale: ",
      "Type B firms (present in RAIS in some years, absent in loan year) account ",
      "for ", fmt_pct(share_type_b, 1), " of firms with unmatched loans, suggesting ",
      "the dominant mechanism is RAIS panel coverage gaps rather than informality. ",
      "Imputing bin-1 for loans from Type B firms with porte Media/Grande would ",
      "introduce systematic misclassification. Documenting the loss is safer than ",
      "speculative imputation."
    )
  )
}

report_lines <- c(
  "# Unmatched Loan Diagnostic — E1 RAIS Coverage Gap",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "**F0 link:** F0 admissibility (docs/PROJECT_BLUEPRINT.md §3 F0). Coverage of",
  "the RAIS-BNDES match underpins every bin assignment in the A4/A3 options.",
  "",
  "---",
  "",
  "## 1. Headline Numbers",
  "",
  paste0("- Clean loan set (firm_id + value + porte + year non-missing): ",
         fmt_int(n_clean)),
  paste0("- Matched to a RAIS (firm, year) row:   **", fmt_int(n_matched),
         "** (", fmt_pct(n_matched / n_clean), " of loans; ",
         fmt_pct(val_matched / val_total), " of value)"),
  paste0("- Unmatched (no RAIS row in loan year): **", fmt_int(n_unmatched),
         "** (", fmt_pct(n_unmatched / n_clean), " of loans; ",
         fmt_pct(val_unmatched / val_total), " of value)"),
  "",
  "---",
  "",
  "## 2. By Year",
  "",
  "| Year | n_matched | n_unmatched | share_unmatched | share_value_unmatched |",
  "|------|----------:|------------:|----------------:|----------------------:|",
  year_rows,
  "",
  paste0("**Read:** early years (≤ 2004) average unmatched share = ",
         fmt_pct(early_yrs), "; middle years (2005–2014) = ", fmt_pct(mid_yrs),
         "; late years (≥ 2015) = ", fmt_pct(late_yrs), ". ",
         "Peak unmatched year: ", max_share_yr$year, " (", fmt_pct(max_share_yr$share_unmatched), "); ",
         "lowest: ", min_share_yr$year, " (", fmt_pct(min_share_yr$share_unmatched), ")."),
  "",
  "---",
  "",
  "## 3. By Porte",
  "",
  "| Porte | n_matched | n_unmatched | share_unmatched | share_value_unmatched |",
  "|-------|----------:|------------:|----------------:|----------------------:|",
  porte_rows,
  "",
  paste0("**Read:** Micro/Pequena share of unmatched loans = ",
         fmt_pct(micro_pequena_share_unmatched), "; ",
         "Media/Grande = ", fmt_pct(media_grande_share_unmatched), ". ",
         if (micro_pequena_share_unmatched >= 0.70) {
           "Unmatched mass is strongly skewed toward small-firm categories, consistent with the informal/sole-proprietor hypothesis."
         } else {
           "Unmatched mass is broadly distributed across porte categories."
         }),
  "",
  "---",
  "",
  if (has_cnae && nrow(out_cnae) > 1L) {
    c(
      "## 4. By CNAE Section",
      "",
      "| CNAE | n_matched | n_unmatched | share_unmatched | share_value_unmatched |",
      "|------|----------:|------------:|----------------:|----------------------:|",
      cnae_rows,
      ""
    )
  } else {
    c("## 4. By CNAE Section", "", "`cnae_section` not available in loan-level file.", "")
  },
  "---",
  "",
  "## 5. By Loan Size",
  "",
  "Values in thousands R$ (2018 BRL).",
  "",
  "| Group | N | Mean (k R$) | Median (k R$) | p10 (k R$) | p90 (k R$) |",
  "|-------|--:|------------:|--------------:|-----------:|-----------:|",
  val_rows,
  "",
  paste0("**Read:** Mean loan value for unmatched = R$ ",
         fmt_num(out_val_dist[group == "unmatched", mean_value] / 1e3, 0), "K vs. R$ ",
         fmt_num(out_val_dist[group == "matched",   mean_value] / 1e3, 0), "K for matched. ",
         if (out_val_dist[group == "unmatched", mean_value] < out_val_dist[group == "matched", mean_value]) {
           "Unmatched loans are smaller on average — consistent with smaller/informal firms."
         } else {
           "Unmatched loans are similar in size to matched loans."
         }),
  "",
  "---",
  "",
  "## 6. Type A vs. Type B Firms",
  "",
  paste0("Firms with at least one unmatched loan: **", fmt_int(n_unmatched_firms), "**"),
  "",
  "| Firm type | Definition | N firms | Share | N unmatched loans | Share of unmatched loans |",
  "|-----------|-----------|--------:|------:|------------------:|-------------------------:|",
  sprintf("| **Type A — never in RAIS** | n_rais_years_anywhere = 0 | %s | %s | %s | %s |",
          fmt_int(n_type_a), fmt_pct(share_type_a),
          fmt_int(n_unmatched_loans_typeA),
          fmt_pct(n_unmatched_loans_typeA / n_unmatched)),
  sprintf("| **Type B — sometimes in RAIS** | n_rais_years_anywhere ≥ 1 | %s | %s | %s | %s |",
          fmt_int(n_type_b), fmt_pct(share_type_b),
          fmt_int(n_unmatched_loans_typeB),
          fmt_pct(n_unmatched_loans_typeB / n_unmatched)),
  "",
  paste0("**Read:** Type A (truly absent from formal employment) accounts for ",
         fmt_pct(share_type_a), " of unmatched-loan firms and ",
         fmt_pct(n_unmatched_loans_typeA / n_unmatched),
         " of unmatched loans. Type B (panel coverage gap — firm is in RAIS in ",
         "some years but not the loan year) accounts for ",
         fmt_pct(share_type_b), " of firms. Among Type B firms, the median ",
         "RAIS year count is ", fmt_num(type_b_median_rais_yrs, 0), " years."),
  "",
  "---",
  "",
  "## 7. Recommendation",
  "",
  rec_text,
  "",
  "---",
  "",
  "## 8. Imputed Diagonal Comparison",
  "",
  "Three treatment alternatives evaluated on the full clean loan set:",
  "- T1: drop unmatched (current baseline)",
  "- T2: treat-as-Micro for ALL unmatched (size_bin_A4 = 1)",
  "- T3: conditional imputation — bin 1 for Micro/Pequena unmatched; drop Media/Grande unmatched",
  "",
  "| Treatment | N loans | 4x4 uw diag | 4x4 vw diag | 3x3 uw diag | Pass 4x4 vw ≥60% | Pass 3x3 uw ≥65% |",
  "|-----------|--------:|------------:|------------:|------------:|:-----------------:|:-----------------:|",
  imputed_rows,
  "",
  paste0("Files: `alignment_yearly_imputed_summary.csv`"),
  "",
  "---",
  "",
  "## 9. Output Files",
  "",
  "| File | Description |",
  "|------|-------------|",
  "| `unmatched_by_year.csv` | Matched vs. unmatched counts and values by year |",
  "| `unmatched_by_porte.csv` | Matched vs. unmatched by porte category |",
  "| `unmatched_by_cnae.csv` | Matched vs. unmatched by CNAE section |",
  "| `unmatched_value_distribution.csv` | Distribution of loan values for matched vs. unmatched |",
  "| `unmatched_firm_persistence.csv` | Per-firm loan counts and RAIS year count |",
  "| `unmatched_firm_persistence_summary.csv` | Type A / Type B split + loan decomposition |",
  "| `alignment_yearly_imputed_summary.csv` | Diagonal comparison across three treatment options |",
  ""
)

writeLines(report_lines,
           file.path(OUTPUT_DIR, "alignment_unmatched_diagnostic.md"))
message("  Written: alignment_unmatched_diagnostic.md")

# ------------------------------------------------------------------------------
# 13. Console summary
# ------------------------------------------------------------------------------
message("\n================================================================")
message("  01c: Unmatched Loan Diagnostic — Summary")
message("================================================================")
message(sprintf("  Clean loans:             %s", fmt_int(n_clean)))
message(sprintf("  Matched:                 %s (%.1f%% of loans)",
                fmt_int(n_matched), 100 * n_matched / n_clean))
message(sprintf("  Unmatched:               %s (%.1f%% of loans; %.1f%% of value)",
                fmt_int(n_unmatched),
                100 * n_unmatched  / n_clean,
                100 * val_unmatched / val_total))
message(sprintf("  Micro/Pequena share of unmatched loans: %.1f%%",
                100 * micro_pequena_share_unmatched))
message(sprintf("  Type A firms (never in RAIS):     %s (%.1f%%)",
                fmt_int(n_type_a), 100 * share_type_a))
message(sprintf("  Type B firms (sometimes in RAIS): %s (%.1f%%)",
                fmt_int(n_type_b), 100 * share_type_b))
message(sprintf("  Unmatched loans from Type A:  %s (%.1f%%)",
                fmt_int(n_unmatched_loans_typeA),
                100 * n_unmatched_loans_typeA / n_unmatched))
message(sprintf("  Unmatched loans from Type B:  %s (%.1f%%)",
                fmt_int(n_unmatched_loans_typeB),
                100 * n_unmatched_loans_typeB / n_unmatched))
message("")
message(sprintf("  RECOMMENDATION: %s", recommendation))
message("")
message("  Diagonal comparison (4x4 vw / 3x3 uw):")
for (i in seq_len(nrow(imputed_summary))) {
  r <- imputed_summary[i]
  message(sprintf("    %-36s  4x4vw=%s  3x3uw=%s",
                  r$treatment,
                  fmt_pct(r$diag_4x4_vw),
                  fmt_pct(r$diag_3x3_uw)))
}
message("")
message("  Output written to:")
message("    ", OUTPUT_DIR)
message("================================================================")

invisible(list(
  n_clean                    = n_clean,
  n_matched                  = n_matched,
  n_unmatched                = n_unmatched,
  share_unmatched            = n_unmatched / n_clean,
  share_value_unmatched      = val_unmatched / val_total,
  micro_pequena_share_unm    = micro_pequena_share_unmatched,
  n_type_a                   = n_type_a,
  share_type_a               = share_type_a,
  n_type_b                   = n_type_b,
  share_type_b               = share_type_b,
  recommendation             = recommendation,
  imputed_summary            = imputed_summary
))
