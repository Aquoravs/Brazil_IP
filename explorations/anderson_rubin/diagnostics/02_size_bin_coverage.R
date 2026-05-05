# ==============================================================================
# 02_size_bin_coverage.R
#
# E2: Coverage check for firm-size aggregation margin candidates
#     (Options A4, A3, B) at the cell unit (size_bin x cnae_section x muni_id x year).
#
# Goal: Determine which of {A4, A3, B} produces cells with adequate BNDES
# borrower coverage for the shift-share IV. A cell is "thin" if n_borrowers < 5.
# A bin is "structurally thin" if share_munis_with_bin_borrower < 0.10 in the
# median year. Decision logic (plan §5 / §8) selects which option(s) advance to E3.
#
# Foundation under test:
#   F0 admissibility (docs/PROJECT_BLUEPRINT.md §3 F0) — every RAIS firm gets a
#   bin assignment; cells are year-level. This script verifies that the resulting
#   (size_bin x cnae_section x muni_id x year) cells are adequately populated
#   for the SSIV first stage.
#   F1 (sector x size margin, under test) — cells are the unit of analysis for
#   the shift-share IV first stage.
#
# Plan reference: logs/plans/2026-05-04_size-bin-diagnostics.md §5 (E2)
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst
#     columns: firm_id, muni_id, year, cnae_section, in_bndes,
#              value_dis_real_2018_total, n_employees
#
# Outputs (explorations/anderson_rubin/diagnostics/output/):
#   coverage_optionA4.csv            — one row per size_bin, A4 coverage metrics
#   coverage_optionA3.csv            — one row per size_bin, A3 coverage metrics
#   coverage_optionB.csv             — one row per size_bin, B coverage metrics
#   coverage_cells_optionA4.csv      — full cell long table (downstream E3 input)
#   coverage_cells_optionA3.csv      — full cell long table
#   coverage_cells_optionB.csv       — full cell long table
#   coverage_summary.csv             — one row per option with verdict
#   coverage_report.md               — readable markdown, decision logic per plan §8
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

path_fst <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst")
path_qs2 <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.qs2")

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

# Panel year -> election_cycle mapping (post-baseline outcome window rule, all
# 7 cycles). Plan §5 step 3 and §4 step 2 hardcoded mapping.
#   y=2004              -> 2005
#   y in {2005,2006}    -> 2007
#   y in {2007,2008}    -> 2009
#   y in {2009,2010}    -> 2011
#   y in {2011,2012}    -> 2013
#   y in {2013,2014}    -> 2015
#   y in {2015,2016,2017} -> 2017
#   y in {2002,2003}    -> drop (no preceding cycle)
#   y >= 2018           -> drop (beyond panel)
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

# Sections excluded from "active" category (plan §0.2)
XX_SECTIONS <- c("K", "O", "T", "U")

# A4 / A3 labels
A4_LABELS <- c("Micro", "Pequena", "Media", "Grande")
A3_LABELS <- c("MPME", "Media", "Grande")
B_LABELS  <- c("Tercile_1", "Tercile_2", "Tercile_3")

# Coverage thresholds (plan §5 step 8 and §8)
THIN_CELL_N_THRESHOLD          <- 5L    # n_borrowers < this -> thin cell
THIN_CELL_SHARE_MAX            <- 0.30  # overall thin-cell share threshold for PASS
STRUCT_THIN_SHARE_MUNIS_MIN    <- 0.10  # share_munis_with_bin_borrower threshold

# ------------------------------------------------------------------------------
# 4. Helper: assign_size_bins (verbatim from 00_size_bin_stability.R lines 104–121)
#    Equal-frequency tercile assignment; rank fallback when <= n_bins unique values.
# ------------------------------------------------------------------------------
#' @param x      numeric vector of mean_emp values
#' @param n_bins integer, number of bins (default 3L)
#' @return integer vector 1..n_bins (NA where x is NA)
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

  # Rank fallback: distribute evenly when <= n_bins unique values
  ranks <- frank(x, ties.method = "average", na.last = "keep")
  n_obs <- sum(!is.na(x))
  pmax.int(1L, pmin.int(n_bins, as.integer(ceiling(ranks / n_obs * n_bins))))
}

# ------------------------------------------------------------------------------
# 5. Load panel (column-selective; INV-16; coerce firm_id to character)
# ------------------------------------------------------------------------------
COLS_NEEDED <- c("firm_id", "muni_id", "year", "cnae_section",
                 "in_bndes", "value_dis_real_2018_total", "n_employees")

message("Loading RAIS-BNDES panel (column-selective)...")

if (file.exists(path_fst)) {
  message("  Source: fst (column-selective) — ", basename(path_fst))
  panel <- fst::read_fst(path_fst, columns = COLS_NEEDED, as.data.table = TRUE)
} else if (file.exists(path_qs2)) {
  message("  Source: qs2 — ", basename(path_qs2))
  raw <- qs_read(path_qs2)
  setDT(raw)
  missing_cols <- setdiff(COLS_NEEDED, names(raw))
  if (length(missing_cols) > 0L) {
    stop("qs2 file missing columns: ", paste(missing_cols, collapse = ", "))
  }
  panel <- raw[, .SD, .SDcols = COLS_NEEDED]
  rm(raw); invisible(gc())
} else {
  stop("Panel file not found.\nExpected:\n  ", path_fst,
       "\nor\n  ", path_qs2)
}

stopifnot(is.data.table(panel))
stopifnot(all(COLS_NEEDED %in% names(panel)))

# Coerce types — firm_id as character to avoid type-mismatch bugs
panel[, firm_id     := as.character(firm_id)]
panel[, muni_id     := as.character(muni_id)]
panel[, year        := as.integer(year)]
panel[, in_bndes    := as.integer(in_bndes)]
panel[, n_employees := as.numeric(n_employees)]
panel[is.na(value_dis_real_2018_total), value_dis_real_2018_total := 0]

message(sprintf("  Panel loaded: %s firm-years.",
                format(nrow(panel), big.mark = ",")))

# ------------------------------------------------------------------------------
# 6. Step 1–2: Drop out-of-window years; assign election_cycle
# ------------------------------------------------------------------------------
message("\nStep 1-2: Assigning election cycle and dropping out-of-window years...")

n_before_year_filter <- nrow(panel)

# Identify years that get dropped
years_in_panel <- unique(panel$year)
years_2002_2003 <- years_in_panel[years_in_panel %in% 2002L:2003L]
years_2018_plus <- years_in_panel[years_in_panel >= 2018L]

n_drop_early <- panel[year %in% 2002L:2003L, .N]
n_drop_late  <- panel[year >= 2018L,          .N]

if (n_drop_early > 0L) {
  message(sprintf("  Dropping %s firm-years in 2002-2003 (no preceding cycle window).",
                  format(n_drop_early, big.mark = ",")))
}
if (n_drop_late > 0L) {
  message(sprintf("  Dropping %s firm-years in years >= 2018 (beyond panel).",
                  format(n_drop_late, big.mark = ",")))
}

# Merge election_cycle (NA for dropped years)
panel <- merge(panel, YEAR_TO_CYCLE, by = "year", all.x = TRUE)
panel <- panel[!is.na(election_cycle)]

message(sprintf("  Panel rows after year filter: %s (dropped %s)",
                format(nrow(panel), big.mark = ","),
                format(n_before_year_filter - nrow(panel), big.mark = ",")))

# ------------------------------------------------------------------------------
# 7. Step 2: Compute mean_emp_{f,c} per (firm, cycle)
#    Mirror 00_size_bin_stability.R steps 6–7; pre-allocated cycle loop.
#    Uses full panel (all firms, not just borrowers) for admissibility.
# ------------------------------------------------------------------------------
message("\nStep 2: Computing per-firm baseline mean employment per cycle...")

# Collapse panel to firm-year totals (same approach as 00_size_bin_stability.R)
panel_fy <- panel[, .(
  has_emp_obs  = any(!is.na(n_employees)),
  emp_total    = sum(n_employees, na.rm = TRUE),
  cnae_section = cnae_section[1L]
), by = .(firm_id, year)]
panel_fy <- panel_fy[has_emp_obs == TRUE,
                     .(firm_id, year, cnae_section, n_employees = emp_total)]

message(sprintf("  Firm-year totals: %s rows",
                format(nrow(panel_fy), big.mark = ",")))

# Pre-allocated list for cycle loop
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

  message(sprintf("  Cycle %d (bl %d-%d): %s firms, mean_emp = %.1f",
                  ec, bl_start, bl_end,
                  format(nrow(firm_avg), big.mark = ","),
                  mean(firm_avg$mean_emp, na.rm = TRUE)))

  all_means[[i]] <- firm_avg
}

firm_cycle <- rbindlist(all_means, fill = TRUE)
rm(all_means); invisible(gc())

message(sprintf("  firm_cycle rows before fall-back: %s",
                format(nrow(firm_cycle), big.mark = ",")))

# Full (firm x cycle) grid to detect missing cycles
all_firms  <- unique(firm_cycle$firm_id)
full_grid  <- CJ(firm_id = all_firms,
                  election_cycle = BASELINE_WINDOWS$election_cycle)
firm_cycle <- merge(full_grid, firm_cycle, by = c("firm_id", "election_cycle"),
                    all.x = TRUE)
rm(full_grid)

n_grid_rows      <- nrow(firm_cycle)
n_missing_before <- sum(is.na(firm_cycle$mean_emp))

message(sprintf("  Full grid: %s rows | missing mean_emp: %s (%.1f%%)",
                format(n_grid_rows,      big.mark = ","),
                format(n_missing_before, big.mark = ","),
                100 * n_missing_before / n_grid_rows))

# Apply fall-back rule (plan §3): LOCF then NOCB within firm
setorder(firm_cycle, firm_id, election_cycle)
firm_cycle[, mean_emp_filled := mean_emp]
firm_cycle[, mean_emp_filled := nafill(mean_emp_filled, type = "locf"),
           by = firm_id]
firm_cycle[, mean_emp_filled := nafill(mean_emp_filled, type = "nocb"),
           by = firm_id]

n_fallback_used <- sum(is.na(firm_cycle$mean_emp) & !is.na(firm_cycle$mean_emp_filled))
n_still_missing <- sum(is.na(firm_cycle$mean_emp_filled))
fallback_rate   <- n_fallback_used / n_grid_rows

message(sprintf("  Fall-backs applied: %s (%.2f%% of grid)",
                format(n_fallback_used, big.mark = ","),
                100 * fallback_rate))
message(sprintf("  Still missing after fall-back: %s",
                format(n_still_missing, big.mark = ",")))

# Use filled values; drop rows still NA (firm has no obs in any cycle)
firm_cycle <- firm_cycle[!is.na(mean_emp_filled)]
firm_cycle[, mean_emp := mean_emp_filled]
firm_cycle[, mean_emp_filled := NULL]

# ------------------------------------------------------------------------------
# 8. Step 4: Assign size_bin_A4 and size_bin_A3 per (firm, cycle)
#    Verbatim fcase blocks from 00_size_bin_stability.R lines 297-312.
# ------------------------------------------------------------------------------
message("\nStep 4: Assigning size_bin_A4 and size_bin_A3...")

# Option A4: fixed BNDES thresholds, 4 bins
firm_cycle[, size_bin_A4 := fcase(
  mean_emp >=   0 & mean_emp <=   9, 1L,
  mean_emp >=  10 & mean_emp <=  49, 2L,
  mean_emp >=  50 & mean_emp <= 499, 3L,
  mean_emp >= 500,                   4L,
  default = NA_integer_
)]

# Option A3: 3-bin collapse (Micro+Pequena -> MPME)
firm_cycle[, size_bin_A3 := fcase(
  mean_emp >=   0 & mean_emp <=  49, 1L,
  mean_emp >=  50 & mean_emp <= 499, 2L,
  mean_emp >= 500,                   3L,
  default = NA_integer_
)]

message("  A4 distribution:")
firm_cycle[!is.na(size_bin_A4), .N, by = size_bin_A4][order(size_bin_A4)] |>
  (\(dt) for (j in seq_len(nrow(dt))) {
    message(sprintf("    Bin %d (%s): %s",
                    dt$size_bin_A4[j],
                    A4_LABELS[dt$size_bin_A4[j]],
                    format(dt$N[j], big.mark = ",")))
  })()

# Keep only (firm_id, election_cycle, size_bin_A4, size_bin_A3) for the merge
firm_cycle_bins <- firm_cycle[, .(firm_id, election_cycle, mean_emp,
                                   size_bin_A4, size_bin_A3)]

# ------------------------------------------------------------------------------
# 9. Step 4 cont.: Merge size_bin_A4 and size_bin_A3 into the year-level panel.
#    Join on (firm_id, election_cycle) so each panel row inherits the bin for
#    the cycle that its year t belongs to (plan §0.1).
# ------------------------------------------------------------------------------
message("\nStep 4 cont.: Merging cycle bins into year-level panel...")

panel_with_bins <- merge(
  panel,
  firm_cycle_bins[, .(firm_id, election_cycle, mean_emp,
                       size_bin_A4, size_bin_A3)],
  by  = c("firm_id", "election_cycle"),
  all.x = TRUE
)

message(sprintf("  Panel rows after bin merge: %s",
                format(nrow(panel_with_bins), big.mark = ",")))
message(sprintf("  Rows with NA size_bin_A4: %s",
                format(sum(is.na(panel_with_bins$size_bin_A4)), big.mark = ",")))

# ------------------------------------------------------------------------------
# 10. Step 5: Assign size_bin_B per (firm, year)
#     Within-(cnae_section, year) terciles; input = per-cycle baseline mean_emp.
#     Plan §3 Option B definition.
# ------------------------------------------------------------------------------
message("\nStep 5: Assigning size_bin_B (within cnae_section x year terciles)...")

panel_with_bins[
  !is.na(cnae_section) & cnae_section != "" & !is.na(mean_emp),
  size_bin_B := assign_size_bins(mean_emp, n_bins = 3L),
  by = .(cnae_section, year)
]

message(sprintf("  Rows with NA size_bin_B: %s",
                format(sum(is.na(panel_with_bins$size_bin_B)), big.mark = ",")))
message("  B bin distribution:")
panel_with_bins[!is.na(size_bin_B), .N, by = size_bin_B][order(size_bin_B)] |>
  (\(dt) for (j in seq_len(nrow(dt))) {
    message(sprintf("    Bin %d: %s", dt$size_bin_B[j],
                    format(dt$N[j], big.mark = ",")))
  })()

# Free firm_cycle memory
rm(firm_cycle, firm_cycle_bins, panel_fy)
invisible(gc())

# ------------------------------------------------------------------------------
# 11. Step 6: Admissibility check
#     Print share(is.na(size_bin)) for active sections vs. XX sections.
#     Must be near zero for active sections.
# ------------------------------------------------------------------------------
message("\nStep 6: Admissibility check — NA share by active vs. XX sections...")

for (opt in c("A4", "A3", "B")) {
  bin_col <- paste0("size_bin_", opt)

  active_rows <- panel_with_bins[!is.na(cnae_section) & cnae_section != "" &
                                    !cnae_section %in% XX_SECTIONS]
  xx_rows     <- panel_with_bins[cnae_section %in% XX_SECTIONS]

  na_active <- sum(is.na(active_rows[[bin_col]])) / nrow(active_rows)
  na_xx     <- if (nrow(xx_rows) > 0L) {
    sum(is.na(xx_rows[[bin_col]])) / nrow(xx_rows)
  } else NA_real_

  message(sprintf("  [%s] NA share — active sections: %.4f  |  XX sections: %s",
                  opt,
                  na_active,
                  if (is.na(na_xx)) "—" else sprintf("%.4f", na_xx)))

  if (na_active > 0.05) {
    warning(sprintf("[%s] NA share for ACTIVE sections is %.2f%% — above 5%% threshold.",
                    opt, 100 * na_active))
  }
}

# ------------------------------------------------------------------------------
# 12. Step 7: Build cell tables per option
#     Cell unit: (size_bin x cnae_section x muni_id x year)
#     Plan §5 step 7 (exact aggregation code from brief).
# ------------------------------------------------------------------------------
message("\nStep 7: Building cell tables per option...")

build_cell_table <- function(panel_dt, bin_col) {
  panel_dt[
    !is.na(get(bin_col)) & !is.na(cnae_section) & cnae_section != "",
    .(n_borrowers = sum(in_bndes == 1L, na.rm = TRUE),
      L_total    = sum(fifelse(in_bndes == 1L, value_dis_real_2018_total, 0),
                       na.rm = TRUE),
      n_firms    = uniqueN(firm_id),
      emp_total  = sum(n_employees, na.rm = TRUE)),
    by = .(size_bin = get(bin_col), cnae_section, muni_id, year)
  ]
}

message("  Building cell table for A4...")
cell_A4 <- build_cell_table(panel_with_bins, "size_bin_A4")
message(sprintf("    A4 cells: %s", format(nrow(cell_A4), big.mark = ",")))
invisible(gc())

message("  Building cell table for A3...")
cell_A3 <- build_cell_table(panel_with_bins, "size_bin_A3")
message(sprintf("    A3 cells: %s", format(nrow(cell_A3), big.mark = ",")))
invisible(gc())

message("  Building cell table for B...")
cell_B <- build_cell_table(panel_with_bins, "size_bin_B")
message(sprintf("    B cells: %s", format(nrow(cell_B), big.mark = ",")))
invisible(gc())

# Free main panel — no longer needed
rm(panel_with_bins, panel)
invisible(gc())

# ------------------------------------------------------------------------------
# 13. Step 8: Reporting function per option
#     For each cell table, compute:
#       - n_cells_total, n_cells_with_borrower
#       - share_munis_with_bin_borrower (per size_bin, median across years)
#       - n_borrowers distribution across populated cells: p10, p50, p90
#       - share_thin: share of populated cells with n_borrowers < 5
#       - structurally_thin: flag if share_munis_with_bin_borrower < 0.10
#         in the median year
# ------------------------------------------------------------------------------
message("\nStep 8: Computing coverage metrics per option...")

compute_coverage_metrics <- function(cell_dt, bin_labels, option_label) {

  bins_present <- sort(unique(cell_dt$size_bin))

  # Total cells and cells with at least one borrower
  n_cells_total        <- nrow(cell_dt)
  n_cells_with_borrower <- cell_dt[n_borrowers >= 1L, .N]

  # share_munis_with_bin_borrower per (size_bin, year)
  # Among (muni_id x year) cells where the muni has any RAIS firms in that bin,
  # share that have >= 1 BNDES borrower.
  # "Has RAIS firms in that bin" = n_firms > 0 (cell exists in cell_dt).
  muni_year_bin <- cell_dt[, .(
    has_borrower = as.integer(n_borrowers >= 1L),
    n_firms      = n_firms
  ), by = .(size_bin, muni_id, year)]

  # Share of (muni x year) pairs with borrower, per (size_bin, year)
  share_by_bin_year <- muni_year_bin[, .(
    share_munis_with_borrower = mean(has_borrower)
  ), by = .(size_bin, year)]

  # Median across years per size_bin
  share_by_bin_med <- share_by_bin_year[, .(
    share_munis_with_bin_borrower_med = median(share_munis_with_borrower)
  ), by = size_bin]

  # Distribution of n_borrowers across populated cells (n_borrowers >= 1)
  populated <- cell_dt[n_borrowers >= 1L]
  quantile_dt <- populated[, .(
    n_borrowers_p10 = as.numeric(quantile(n_borrowers, 0.10, names = FALSE)),
    n_borrowers_p50 = as.numeric(quantile(n_borrowers, 0.50, names = FALSE)),
    n_borrowers_p90 = as.numeric(quantile(n_borrowers, 0.90, names = FALSE))
  ), by = size_bin]

  # share_thin: share of populated cells with n_borrowers < 5
  share_thin_by_bin <- populated[, .(
    share_thin = mean(n_borrowers < THIN_CELL_N_THRESHOLD)
  ), by = size_bin]

  # Overall share_thin (across all populated cells, all bins)
  overall_share_thin <- mean(populated$n_borrowers < THIN_CELL_N_THRESHOLD)

  # Structurally thin: share_munis_with_bin_borrower_med < 0.10
  struct_thin_bins <- share_by_bin_med[
    share_munis_with_bin_borrower_med < STRUCT_THIN_SHARE_MUNIS_MIN,
    size_bin
  ]

  # Per-bin summary table
  per_bin <- merge(share_by_bin_med, quantile_dt, by = "size_bin", all.x = TRUE)
  per_bin <- merge(per_bin, share_thin_by_bin, by = "size_bin", all.x = TRUE)

  # Add cell counts per bin
  cell_counts_per_bin <- cell_dt[, .(
    n_cells_total_bin    = .N,
    n_cells_with_borrow  = sum(n_borrowers >= 1L)
  ), by = size_bin]
  per_bin <- merge(per_bin, cell_counts_per_bin, by = "size_bin", all.x = TRUE)

  # Structurally thin flag
  per_bin[, structurally_thin := size_bin %in% struct_thin_bins]

  # Add bin labels
  per_bin[, option := option_label]
  per_bin[, bin_label := vapply(
    size_bin,
    function(b) {
      if (b >= 1L && b <= length(bin_labels)) bin_labels[b] else as.character(b)
    },
    character(1L)
  )]

  # Verdict: PASS / THIN_BIN / FAIL
  verdict <- if (length(struct_thin_bins) == 0L && overall_share_thin < THIN_CELL_SHARE_MAX) {
    "PASS"
  } else if (length(struct_thin_bins) > 0L) {
    "THIN_BIN"
  } else {
    "FAIL"
  }

  # Structurally thin bin names
  if (length(struct_thin_bins) > 0L) {
    thin_bin_names <- vapply(
      struct_thin_bins,
      function(b) if (b >= 1L && b <= length(bin_labels)) bin_labels[b] else as.character(b),
      character(1L)
    )
    struct_thin_str <- paste(thin_bin_names, collapse = ", ")
  } else {
    struct_thin_str <- ""
  }

  # Overall summary row
  summary_row <- data.table(
    option               = option_label,
    n_cells_total        = n_cells_total,
    n_cells_with_borrower = n_cells_with_borrower,
    share_cells_with_borrower = n_cells_with_borrower / n_cells_total,
    overall_thin_cell_share  = overall_share_thin,
    max_share_munis_with_bin_borrower = max(per_bin$share_munis_with_bin_borrower_med,
                                            na.rm = TRUE),
    min_share_munis_with_bin_borrower = min(per_bin$share_munis_with_bin_borrower_med,
                                            na.rm = TRUE),
    n_structurally_thin_bins = length(struct_thin_bins),
    structurally_thin_bins   = struct_thin_str,
    verdict                  = verdict
  )

  # Console log
  message(sprintf("  [%s] Total cells: %s | With borrower: %s (%.1f%%)",
                  option_label,
                  format(n_cells_total,        big.mark = ","),
                  format(n_cells_with_borrower, big.mark = ","),
                  100 * n_cells_with_borrower / n_cells_total))
  message(sprintf("  [%s] Overall thin-cell share (n_borrow<5): %.3f | Threshold: %.2f",
                  option_label, overall_share_thin, THIN_CELL_SHARE_MAX))
  message(sprintf("  [%s] Struct. thin bins: %s | Verdict: %s",
                  option_label,
                  if (nchar(struct_thin_str) > 0L) struct_thin_str else "none",
                  verdict))

  list(
    per_bin     = per_bin,
    summary_row = summary_row,
    struct_thin_bins = struct_thin_bins
  )
}

res_A4 <- compute_coverage_metrics(cell_A4, A4_LABELS, "A4")
res_A3 <- compute_coverage_metrics(cell_A3, A3_LABELS, "A3")
res_B  <- compute_coverage_metrics(cell_B,  B_LABELS,  "B")

# Combine summary
coverage_summary <- rbindlist(list(
  res_A4$summary_row,
  res_A3$summary_row,
  res_B$summary_row
))

# Per-bin tables with standardized column names for output CSVs
build_per_bin_csv <- function(per_bin_dt) {
  per_bin_dt[, .(
    option,
    size_bin,
    bin_label,
    n_cells_total    = n_cells_total_bin,
    n_cells_with_borrower = n_cells_with_borrow,
    share_cells_with_borrower = n_cells_with_borrow / n_cells_total_bin,
    share_munis_with_bin_borrower_med,
    n_borrowers_p10,
    n_borrowers_p50,
    n_borrowers_p90,
    share_thin,
    structurally_thin
  )]
}

out_A4 <- build_per_bin_csv(res_A4$per_bin)
out_A3 <- build_per_bin_csv(res_A3$per_bin)
out_B  <- build_per_bin_csv(res_B$per_bin)

# ------------------------------------------------------------------------------
# 14. Write CSV outputs
# ------------------------------------------------------------------------------
message("\nStep 9: Writing CSV outputs...")

fwrite(out_A4, file.path(OUTPUT_DIR, "coverage_optionA4.csv"))
message("  Written: coverage_optionA4.csv")

fwrite(out_A3, file.path(OUTPUT_DIR, "coverage_optionA3.csv"))
message("  Written: coverage_optionA3.csv")

fwrite(out_B, file.path(OUTPUT_DIR, "coverage_optionB.csv"))
message("  Written: coverage_optionB.csv")

fwrite(cell_A4, file.path(OUTPUT_DIR, "coverage_cells_optionA4.csv"))
message("  Written: coverage_cells_optionA4.csv")

fwrite(cell_A3, file.path(OUTPUT_DIR, "coverage_cells_optionA3.csv"))
message("  Written: coverage_cells_optionA3.csv")

fwrite(cell_B, file.path(OUTPUT_DIR, "coverage_cells_optionB.csv"))
message("  Written: coverage_cells_optionB.csv")

fwrite(coverage_summary, file.path(OUTPUT_DIR, "coverage_summary.csv"))
message("  Written: coverage_summary.csv")

# ------------------------------------------------------------------------------
# 15. Decision logic (plan §5 / §8) — applied to per-bin results
# ------------------------------------------------------------------------------
message("\nStep 10: Applying decision logic (plan §8)...")

# A4 bin flags
a4_micro_thin  <- 1L %in% res_A4$struct_thin_bins
a4_pequena_thin <- 2L %in% res_A4$struct_thin_bins
a4_media_thin  <- 3L %in% res_A4$struct_thin_bins
a4_grande_thin <- 4L %in% res_A4$struct_thin_bins
a4_overall_thin_flag <- res_A4$summary_row$overall_thin_cell_share >= THIN_CELL_SHARE_MAX

# A3 bin flags
a3_mpme_thin   <- 1L %in% res_A3$struct_thin_bins
a3_media_thin  <- 2L %in% res_A3$struct_thin_bins
a3_grande_thin <- 3L %in% res_A3$struct_thin_bins
a3_overall_thin_flag <- res_A3$summary_row$overall_thin_cell_share >= THIN_CELL_SHARE_MAX

# B bin flags
b_bin3_thin <- 3L %in% res_B$struct_thin_bins
b_overall_thin_flag <- res_B$summary_row$overall_thin_cell_share >= THIN_CELL_SHARE_MAX

# Determine A-option survivor
a4_passes <- !a4_micro_thin && !a4_pequena_thin && !a4_media_thin &&
             !a4_grande_thin && !a4_overall_thin_flag

if (a4_passes) {
  a_survivor    <- "A4"
  a_survivor_reason <- "A4 passes all four bins; A3 dropped."
  a4_advances_to_e3 <- TRUE
  a3_advances_to_e3 <- FALSE
} else if (a4_micro_thin && !a4_pequena_thin && !a4_media_thin && !a4_grande_thin) {
  a_survivor    <- "A3"
  a_survivor_reason <- "A4 fails only on Micro bin — escalate to A3 (collapses Micro into Pequena)."
  a4_advances_to_e3 <- FALSE
  a3_advances_to_e3 <- TRUE
} else if (a4_grande_thin) {
  # A3 advances only if remaining bins are healthy
  a3_remaining_healthy <- !a3_mpme_thin && !a3_media_thin
  a_survivor    <- if (a3_remaining_healthy) "A3" else "NONE"
  a_survivor_reason <- paste0(
    "A4 fails on Grande (structurally rare large firms in small munis). ",
    if (a3_remaining_healthy) {
      "A3 advances (remaining bins healthy); Grande caveat flagged."
    } else {
      "A3 also fails — no rescue. Escalate to user."
    }
  )
  a4_advances_to_e3 <- FALSE
  a3_advances_to_e3 <- a3_remaining_healthy
} else if (a4_pequena_thin || a4_media_thin) {
  a_survivor    <- "FLAG"
  a_survivor_reason <- paste0(
    "UNUSUAL: A4 fails on ",
    if (a4_pequena_thin && a4_media_thin) "Pequena AND Media" else
      if (a4_pequena_thin) "Pequena" else "Media",
    ". Flag for manual inspection."
  )
  a4_advances_to_e3 <- FALSE
  a3_advances_to_e3 <- TRUE
} else {
  a_survivor    <- "FLAG"
  a_survivor_reason <- "A4 fails on multiple bins; flag for inspection."
  a4_advances_to_e3 <- FALSE
  a3_advances_to_e3 <- TRUE
}

# B advances unless bin 3 fails in median year
b_advances_to_e3 <- !b_bin3_thin

message(sprintf("  A-option survivor: %s — %s", a_survivor, a_survivor_reason))
message(sprintf("  A4 advances to E3: %s", a4_advances_to_e3))
message(sprintf("  A3 advances to E3: %s", a3_advances_to_e3))
message(sprintf("  B  advances to E3: %s", b_advances_to_e3))

# ------------------------------------------------------------------------------
# 16. Markdown report
# ------------------------------------------------------------------------------
message("\nStep 11: Writing coverage_report.md...")

fmt_pct <- function(x, d = 1) {
  ifelse(is.na(x), "—", sprintf(paste0("%.", d, "f%%"), 100 * x))
}
fmt_num <- function(x, d = 3) {
  ifelse(is.na(x), "—", sprintf(paste0("%.", d, "f"), x))
}
fmt_int <- function(x) {
  ifelse(is.na(x), "—", format(as.integer(x), big.mark = ","))
}

# Per-bin table builder
build_bin_table <- function(per_bin_csv) {
  header <- "| Bin | n_cells_total | n_cells_with_borrower | share_cells | share_munis_med | p50_n_borrow | share_thin | struct_thin |"
  sep    <- "|-----|--------------|----------------------|-------------|-----------------|-------------|------------|------------|"
  rows   <- vapply(seq_len(nrow(per_bin_csv)), function(j) {
    r <- per_bin_csv[j]
    sprintf("| %s | %s | %s | %s | %s | %s | %s | %s |",
            r$bin_label,
            fmt_int(r$n_cells_total),
            fmt_int(r$n_cells_with_borrower),
            fmt_pct(r$share_cells_with_borrower),
            fmt_pct(r$share_munis_with_bin_borrower_med),
            fmt_int(r$n_borrowers_p50),
            fmt_pct(r$share_thin),
            if (isTRUE(r$structurally_thin)) "YES" else "no")
  }, character(1L))
  c(header, sep, rows)
}

# E3 survivor note
e3_survivors <- c(
  if (a4_advances_to_e3) "A4",
  if (a3_advances_to_e3) "A3",
  if (b_advances_to_e3)  "B"
)
e3_survivor_str <- if (length(e3_survivors) > 0L) {
  paste(e3_survivors, collapse = ", ")
} else {
  "NONE — all options fail; escalate to user"
}

report_lines <- c(
  "# E2: Coverage Check — Size-Bin Aggregation Margin Candidates (A4, A3, B)",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Goal",
  "",
  "Evaluate whether the proposed firm-size aggregation margins produce",
  "`(size_bin x cnae_section x muni_id x year)` cells with adequate BNDES",
  "borrower coverage for the shift-share IV first stage.",
  "",
  "**Cell unit:** `(size_bin, cnae_section, muni_id, year)` — year-level,",
  "matching the IV and the A2 round-1 decomposition (plan §0.1).",
  "",
  "**F0/F1 link:** `docs/PROJECT_BLUEPRINT.md` §3 F0 (admissibility) and F1",
  "(within-muni variation in credit shares requires non-degenerate cells).",
  "",
  paste0("**Thresholds:** structurally thin if `share_munis_with_bin_borrower_med < ",
         STRUCT_THIN_SHARE_MUNIS_MIN, "`; overall thin-cell PASS requires share < ",
         THIN_CELL_SHARE_MAX, "."),
  "",
  "---",
  "",
  "## 1. Headline Numbers",
  "",
  "| Option | n_cells_total | n_cells_with_borrower | share_cells | thin_cell_share | verdict |",
  "|--------|--------------|----------------------|-------------|----------------|---------|",
  sprintf("| **A4** | %s | %s | %s | %s | **%s** |",
          fmt_int(res_A4$summary_row$n_cells_total),
          fmt_int(res_A4$summary_row$n_cells_with_borrower),
          fmt_pct(res_A4$summary_row$share_cells_with_borrower),
          fmt_pct(res_A4$summary_row$overall_thin_cell_share),
          res_A4$summary_row$verdict),
  sprintf("| **A3** | %s | %s | %s | %s | **%s** |",
          fmt_int(res_A3$summary_row$n_cells_total),
          fmt_int(res_A3$summary_row$n_cells_with_borrower),
          fmt_pct(res_A3$summary_row$share_cells_with_borrower),
          fmt_pct(res_A3$summary_row$overall_thin_cell_share),
          res_A3$summary_row$verdict),
  sprintf("| **B**  | %s | %s | %s | %s | **%s** |",
          fmt_int(res_B$summary_row$n_cells_total),
          fmt_int(res_B$summary_row$n_cells_with_borrower),
          fmt_pct(res_B$summary_row$share_cells_with_borrower),
          fmt_pct(res_B$summary_row$overall_thin_cell_share),
          res_B$summary_row$verdict),
  "",
  "---",
  "",
  "## 2. Per-Bin Tables",
  "",
  "### Option A4 (4-bin BNDES native: Micro / Pequena / Media / Grande)",
  "",
  build_bin_table(out_A4),
  "",
  paste0("Structurally thin A4 bins: **",
         if (nchar(res_A4$summary_row$structurally_thin_bins) > 0L)
           res_A4$summary_row$structurally_thin_bins
         else "none", "**"),
  "",
  "### Option A3 (3-bin collapse: MPME / Media / Grande)",
  "",
  build_bin_table(out_A3),
  "",
  paste0("Structurally thin A3 bins: **",
         if (nchar(res_A3$summary_row$structurally_thin_bins) > 0L)
           res_A3$summary_row$structurally_thin_bins
         else "none", "**"),
  "",
  "### Option B (within-(cnae_section x year) terciles)",
  "",
  build_bin_table(out_B),
  "",
  paste0("Structurally thin B bins: **",
         if (nchar(res_B$summary_row$structurally_thin_bins) > 0L)
           res_B$summary_row$structurally_thin_bins
         else "none", "**"),
  "",
  "---",
  "",
  "## 3. Decision Read (plan §5 / §8)",
  "",
  paste0("**A-option logic:** ", a_survivor_reason),
  "",
  paste0("- A4 Micro thin: ", if (a4_micro_thin) "YES" else "no"),
  paste0("- A4 Pequena thin: ", if (a4_pequena_thin) "YES" else "no"),
  paste0("- A4 Media thin: ", if (a4_media_thin) "YES" else "no"),
  paste0("- A4 Grande thin: ", if (a4_grande_thin) "YES" else "no"),
  paste0("- A4 overall thin-cell share >= 0.30: ",
         if (a4_overall_thin_flag) "YES" else "no"),
  "",
  paste0("**Option B logic:** B ",
         if (b_advances_to_e3) "PASSES (bin 3 not structurally thin) — advances to E3."
         else "FAILS (bin 3 structurally thin) — does not advance to E3. Escalate to user."),
  "",
  "---",
  "",
  "## 4. Which Options Survive into E3",
  "",
  paste0("**E3 survivors: ", e3_survivor_str, "**"),
  "",
  if ("A4" %in% e3_survivors) "- **A4** is the production Option-A candidate.",
  if ("A3" %in% e3_survivors && !("A4" %in% e3_survivors)) {
    "- **A3** replaces A4 as the Option-A candidate (A4 failed E2)."
  },
  if ("A3" %in% e3_survivors && "A4" %in% e3_survivors) {
    "- **A3** also advances (rare: both A4 and A3 pass; carry both into E3)."
  },
  if ("B" %in% e3_survivors) "- **B** advances to E3 alongside the surviving A-option.",
  if (length(e3_survivors) == 0L) {
    "- **No options survive** — all fail E2. Escalate to user before proceeding."
  },
  "",
  "---",
  "",
  "## 5. Files Written",
  "",
  "| File | Description |",
  "|------|-------------|",
  "| `coverage_optionA4.csv` | Per-bin metrics for A4 |",
  "| `coverage_optionA3.csv` | Per-bin metrics for A3 |",
  "| `coverage_optionB.csv` | Per-bin metrics for B |",
  "| `coverage_cells_optionA4.csv` | Full cell long table (downstream E3 input), A4 |",
  "| `coverage_cells_optionA3.csv` | Full cell long table, A3 |",
  "| `coverage_cells_optionB.csv` | Full cell long table, B |",
  "| `coverage_summary.csv` | One row per option with overall verdict |",
  ""
)

# Filter NULL entries from conditional lines
report_lines <- report_lines[!vapply(report_lines, is.null, logical(1L))]

writeLines(report_lines, file.path(OUTPUT_DIR, "coverage_report.md"))
message("  Written: coverage_report.md")

# ------------------------------------------------------------------------------
# 17. Console summary
# ------------------------------------------------------------------------------
message("\n")
message("=================================================================")
message("  E2: Coverage Check — Summary")
message("=================================================================")
message(sprintf("  Fall-back rate:  %.2f%%", 100 * fallback_rate))
message("")
for (opt in c("A4", "A3", "B")) {
  res_obj <- switch(opt, A4 = res_A4, A3 = res_A3, B = res_B)
  sr <- res_obj$summary_row
  message(sprintf("  [%s] cells: %s | w/ borrower: %s (%.1f%%) | thin: %.1f%% | verdict: %s",
                  opt,
                  format(sr$n_cells_total,        big.mark = ","),
                  format(sr$n_cells_with_borrower, big.mark = ","),
                  100 * sr$share_cells_with_borrower,
                  100 * sr$overall_thin_cell_share,
                  sr$verdict))
}
message("")
message(sprintf("  A-option survivor: %s", a_survivor))
message(sprintf("  E3 survivors: %s", e3_survivor_str))
message("")
message("  Output files written to:")
message("    ", OUTPUT_DIR)
message("=================================================================")

# ------------------------------------------------------------------------------
# 18. Return invisible list for interactive inspection
# ------------------------------------------------------------------------------
invisible(list(
  coverage_summary  = coverage_summary,
  out_A4            = out_A4,
  out_A3            = out_A3,
  out_B             = out_B,
  cell_A4           = cell_A4,
  cell_A3           = cell_A3,
  cell_B            = cell_B,
  a_survivor        = a_survivor,
  a4_advances_to_e3 = a4_advances_to_e3,
  a3_advances_to_e3 = a3_advances_to_e3,
  b_advances_to_e3  = b_advances_to_e3,
  e3_survivors      = e3_survivors
))
