# ==============================================================================
# 00_size_bin_stability.R
#
# E0: Bin-stability pre-exercise for firm-size aggregation margin selection.
#
# Goal: Measure how often firms migrate across size bins under Options A4, A3,
# and B over the 7 election cycles 2005–2017. If most firms stay in the same
# bin across all observed cycles (share_firms_ever_changed < 20% under A4),
# the cycle-baseline construction is overhead and a lifetime-mean rule suffices.
# If migration is substantial (>= 20%), keep the cycle-baseline rule and proceed
# to E1–E3.
#
# Foundation under test:
#   F0 admissibility (docs/PROJECT_BLUEPRINT.md §3 F0) — bin stability is a
#   precondition for the cycle-baseline rule. A stable bin assignment would
#   support a simpler lifetime-mean rule; substantial migration confirms that
#   cycle-specific baselines carry genuine information.
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst
#     columns used: firm_id, year, cnae_section, n_employees
#
# Outputs (explorations/anderson_rubin/diagnostics/output/):
#   bin_stability_A4_distribution.csv    — n_distinct_bins distribution, Option A4
#   bin_stability_A4_transitions.csv     — consecutive-cycle transition matrix, A4
#   bin_stability_A3_distribution.csv    — n_distinct_bins distribution, Option A3
#   bin_stability_A3_transitions.csv     — consecutive-cycle transition matrix, A3
#   bin_stability_B_distribution.csv     — n_distinct_bins distribution, Option B
#   bin_stability_B_transitions.csv      — consecutive-cycle transition matrix, B
#   bin_stability_summary.csv            — one row per option: key metrics + flag
#   bin_stability_report.md              — interpretive markdown with top-line nums
#
# Plan reference: logs/plans/2026-05-04_size-bin-diagnostics.md §3.5
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

# A4 thresholds (BNDES native employment proxies)
# Bin 1 = Micro (0–9), Bin 2 = Pequena (10–49),
# Bin 3 = Média (50–499), Bin 4 = Grande (500+)
A4_BREAKS   <- c(0, 9.5, 49.5, 499.5, Inf)   # used with findInterval
A4_LABELS   <- c("Micro", "Pequena", "Media", "Grande")
N_BINS_A4   <- 4L
N_BINS_A3   <- 3L
N_BINS_B    <- 3L

# Decision threshold (plan §3.5 step 8)
STABILITY_THRESHOLD <- 0.20

# Boundary-noise window: A4 moves where employment crosses a threshold by <=2
BOUNDARY_NOISE_TOL <- 2L   # employees

# ------------------------------------------------------------------------------
# 4. Helper: assign_size_bins (mirroring 30c lines 91–105)
#
# Equal-frequency tercile assignment with rank fallback when <= n_bins unique
# values exist. Used for Option B within-(cnae_section, cycle) assignment.
# ------------------------------------------------------------------------------
#' @param x  numeric vector of mean_emp values
#' @param n_bins  integer, number of bins (default 3L)
#' @return integer vector of bin labels 1..n_bins (NA where x is NA)
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
  missing_cols <- setdiff(COLS_NEEDED, names(raw))
  if (length(missing_cols) > 0L) {
    stop("qs2 file missing columns: ", paste(missing_cols, collapse = ", "))
  }
  panel <- raw[, .SD, .SDcols = COLS_NEEDED]
  rm(raw); invisible(gc())
} else {
  stop(
    "Panel file not found.\nExpected:\n  ", path_fst,
    "\nor\n  ", path_qs2
  )
}

stopifnot(is.data.table(panel))
stopifnot(all(COLS_NEEDED %in% names(panel)))

panel[, firm_id     := as.integer(firm_id)]
panel[, year        := as.integer(year)]
panel[, n_employees := as.numeric(n_employees)]

message(sprintf("  Panel loaded: %s firm-years.",
                format(nrow(panel), big.mark = ",")))

# Collapse to national firm-year totals; zero-employment years included;
# firm-years where all employment obs are NA are excluded.
# (mirroring 30c lines 127–135)
panel_fy <- panel[, .(
  has_emp_obs     = any(!is.na(n_employees)),
  emp_total       = sum(n_employees, na.rm = TRUE),
  cnae_section    = cnae_section[1L]         # take first cnae within firm-year
), by = .(firm_id, year)]
panel_fy <- panel_fy[has_emp_obs == TRUE,
                     .(firm_id, year, cnae_section, n_employees = emp_total)]

message(sprintf("  Firm-year totals retained: %s",
                format(nrow(panel_fy), big.mark = ",")))

# Free full panel
rm(panel); invisible(gc())

# Also keep a per-firm cnae_section for Option B's within-(cnae, cycle) cut.
# Use the modal (most frequent) cnae_section across all years for each firm.
firm_cnae <- panel_fy[
  !is.na(cnae_section) & cnae_section != "",
  .N,
  by = .(firm_id, cnae_section)
][order(-N), head(.SD, 1L), by = firm_id][, .(firm_id, cnae_section)]

message(sprintf("  Firms with a modal cnae_section: %s",
                format(nrow(firm_cnae), big.mark = ",")))

# ------------------------------------------------------------------------------
# 6. Compute mean_emp per (firm, cycle) — pre-allocated container
#    (plan §3 + 30c loop pattern lines 141–191)
#
# Fall-back rule (plan §3):
#   If mean_emp_{f,c} is NA (no obs in baseline window), use the closest
#   preceding cycle with obs; if none, use the closest succeeding cycle.
#   Log the count of fall-backs per cycle.
# ------------------------------------------------------------------------------
message("\nStep 6: Computing per-firm baseline mean employment for all 7 cycles...")

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
    mean_emp = mean(n_employees, na.rm = TRUE),
    n_bl_years = .N
  ), by = firm_id]

  firm_avg[, election_cycle := ec]

  message(sprintf("  Cycle %d (bl %d–%d): %s firms, mean emp = %.1f",
                  ec, bl_start, bl_end,
                  format(nrow(firm_avg), big.mark = ","),
                  mean(firm_avg$mean_emp, na.rm = TRUE)))

  all_means[[i]] <- firm_avg
}

# Combine across cycles
firm_cycle <- rbindlist(all_means, fill = TRUE)
rm(all_means); invisible(gc())

# Merge cnae_section for Option B
firm_cycle <- merge(firm_cycle, firm_cnae, by = "firm_id", all.x = TRUE)

message(sprintf("\n  firm_cycle rows before fall-back: %s",
                format(nrow(firm_cycle), big.mark = ",")))

# Full (firm x cycle) grid to detect missing cycles per firm
all_firms   <- unique(firm_cycle$firm_id)
full_grid   <- CJ(firm_id = all_firms, election_cycle = BASELINE_WINDOWS$election_cycle)
firm_cycle  <- merge(full_grid, firm_cycle, by = c("firm_id", "election_cycle"),
                     all.x = TRUE)
n_grid_rows <- nrow(firm_cycle)
n_missing_before <- sum(is.na(firm_cycle$mean_emp))
message(sprintf("  Full grid rows: %s  |  missing mean_emp cells: %s (%.1f%%)",
                format(n_grid_rows,     big.mark = ","),
                format(n_missing_before, big.mark = ","),
                100 * n_missing_before / n_grid_rows))

# Apply fall-back: for each firm, fill NA mean_emp from closest preceding
# cycle, then closest succeeding cycle.
setorder(firm_cycle, firm_id, election_cycle)

firm_cycle[, mean_emp_filled := mean_emp]

# Preceding fill (na.locf forward within each firm)
firm_cycle[, mean_emp_filled := nafill(mean_emp_filled, type = "locf"),
           by = firm_id]

# Succeeding fill (backward) for remaining NAs
firm_cycle[, mean_emp_filled := nafill(mean_emp_filled, type = "nocb"),
           by = firm_id]

n_fallback_used <- sum(is.na(firm_cycle$mean_emp) & !is.na(firm_cycle$mean_emp_filled))
n_still_missing <- sum(is.na(firm_cycle$mean_emp_filled))
fallback_rate   <- n_fallback_used / n_grid_rows

message(sprintf("  Fall-backs applied: %s (%.2f%% of grid)",
                format(n_fallback_used, big.mark = ","),
                100 * fallback_rate))
message(sprintf("  Still missing after fall-back (firm has 0 cycles): %s",
                format(n_still_missing, big.mark = ",")))

# For further analysis, use mean_emp_filled; drop rows still NA (no obs at all)
firm_cycle <- firm_cycle[!is.na(mean_emp_filled)]
firm_cycle[, mean_emp := mean_emp_filled]
firm_cycle[, mean_emp_filled := NULL]

# Re-attach cnae_section for firms that missed it from the merge (corner case)
firm_cycle <- merge(firm_cycle, firm_cnae, by = "firm_id", all.x = TRUE,
                    suffixes = c("", "_modal"))
firm_cycle[is.na(cnae_section) & !is.na(cnae_section_modal),
           cnae_section := cnae_section_modal]
firm_cycle[, cnae_section_modal := NULL]

message(sprintf("  firm_cycle after fall-back: %s rows",
                format(nrow(firm_cycle), big.mark = ",")))

# ------------------------------------------------------------------------------
# 7. Assign size bins
# ------------------------------------------------------------------------------
message("\nStep 7: Assigning size bins (A4, A3, B)...")

# --- Option A4: fixed BNDES thresholds, 4 bins ---
# Bin 1 = Micro [0, 9], Bin 2 = Pequena [10, 49],
# Bin 3 = Media [50, 499], Bin 4 = Grande [500+]
firm_cycle[, size_bin_A4 := fcase(
  mean_emp >=   0 & mean_emp <=   9, 1L,
  mean_emp >=  10 & mean_emp <=  49, 2L,
  mean_emp >=  50 & mean_emp <= 499, 3L,
  mean_emp >= 500,                   4L,
  default = NA_integer_
)]

# --- Option A3: 3-bin collapse (Micro+Pequena combined into MPME) ---
# Bin 1 = MPME [0, 49], Bin 2 = Media [50, 499], Bin 3 = Grande [500+]
firm_cycle[, size_bin_A3 := fcase(
  mean_emp >=   0 & mean_emp <=  49, 1L,
  mean_emp >=  50 & mean_emp <= 499, 2L,
  mean_emp >= 500,                   3L,
  default = NA_integer_
)]

# --- Option B: within-(cnae_section, cycle) equal-frequency tertiles ---
# Input is the per-cycle baseline mean; tertile cut is within (cnae, cycle)
# for a like-for-like comparison with A4/A3 at the cycle level (plan §3.5 step 4).
firm_cycle[
  !is.na(cnae_section) & cnae_section != "" & !is.na(mean_emp),
  size_bin_B := assign_size_bins(mean_emp, n_bins = N_BINS_B),
  by = .(cnae_section, election_cycle)
]

message(sprintf("  A4 bin distribution across all firm-cycles:"))
firm_cycle[!is.na(size_bin_A4), .N, by = size_bin_A4][order(size_bin_A4)] |>
  (\(dt) for (j in seq_len(nrow(dt))) {
    message(sprintf("    Bin %d (%s): %s",
                    dt$size_bin_A4[j],
                    A4_LABELS[dt$size_bin_A4[j]],
                    format(dt$N[j], big.mark = ",")))
  })()

message("  B bin distribution across firm-cycles:")
firm_cycle[!is.na(size_bin_B), .N, by = size_bin_B][order(size_bin_B)] |>
  (\(dt) for (j in seq_len(nrow(dt))) {
    message(sprintf("    Bin %d: %s", dt$size_bin_B[j],
                    format(dt$N[j], big.mark = ",")))
  })()

# ------------------------------------------------------------------------------
# 8. Migration metrics — helper function
#
# For a given bin column, compute:
#   (a) n_distinct_bins_per_firm distribution (only ≥2 observed cycles)
#   (b) share_firms_ever_changed
#   (c) transition matrix between consecutive cycles (long format)
#   (d) direction counts (A4 only: up/down/skip)
# ------------------------------------------------------------------------------

compute_migration_metrics <- function(fc_dt, bin_col, option_label) {
  # Subset to non-NA bin assignments
  dt <- fc_dt[!is.na(get(bin_col)), .(firm_id, election_cycle, bin = get(bin_col))]

  # (a) n_distinct_bins per firm (only firms with >= 2 observed cycles)
  firm_summary <- dt[, .(
    n_cycles_obs   = .N,
    n_distinct_bins = uniqueN(bin)
  ), by = firm_id]

  firm_multi <- firm_summary[n_cycles_obs >= 2L]
  n_multi     <- nrow(firm_multi)
  n_changed   <- firm_multi[n_distinct_bins > 1L, .N]
  share_changed <- if (n_multi > 0L) n_changed / n_multi else NA_real_

  dist_dt <- firm_multi[, .N, by = n_distinct_bins][order(n_distinct_bins)]
  dist_dt[, option := option_label]
  dist_dt[, share_firms := N / n_multi]
  setcolorder(dist_dt, c("option", "n_distinct_bins", "N", "share_firms"))

  message(sprintf(
    "  [%s] Multi-cycle firms: %s | ever changed: %s (%.1f%%)",
    option_label,
    format(n_multi,   big.mark = ","),
    format(n_changed, big.mark = ","),
    100 * share_changed
  ))

  # (c) Consecutive-cycle transition matrix
  cycles_ordered <- sort(BASELINE_WINDOWS$election_cycle)
  cycle_pairs    <- data.table(
    cycle_from = cycles_ordered[-length(cycles_ordered)],
    cycle_to   = cycles_ordered[-1L]
  )

  # Pre-allocate list for consecutive-pair transitions
  trans_list <- vector("list", nrow(cycle_pairs))

  for (k in seq_len(nrow(cycle_pairs))) {
    c_from <- cycle_pairs$cycle_from[k]
    c_to   <- cycle_pairs$cycle_to[k]

    dt_from <- dt[election_cycle == c_from, .(firm_id, bin_from = bin)]
    dt_to   <- dt[election_cycle == c_to,   .(firm_id, bin_to   = bin)]

    pair <- merge(dt_from, dt_to, by = "firm_id")
    if (!nrow(pair)) next

    trans <- pair[, .N, by = .(bin_from, bin_to)]
    trans[, cycle_from := c_from]
    trans[, cycle_to   := c_to]
    trans[, option     := option_label]

    trans_list[[k]] <- trans
  }

  trans_dt <- rbindlist(trans_list, fill = TRUE)
  setcolorder(trans_dt, c("option", "cycle_from", "cycle_to",
                           "bin_from", "bin_to", "N"))

  # Direction counts (only meaningful for ordered integer bins; A4 and A3 are ordered)
  up_moves   <- NA_integer_
  down_moves <- NA_integer_
  skip_moves <- NA_integer_

  if (grepl("^A", option_label) && nrow(trans_dt) > 0L) {
    trans_dt[, bin_delta := bin_to - bin_from]
    up_moves   <- trans_dt[bin_delta >  0L, sum(N)]
    down_moves <- trans_dt[bin_delta <  0L, sum(N)]
    skip_moves <- trans_dt[abs(bin_delta) >= 2L, sum(N)]
    trans_dt[, bin_delta := NULL]
  }

  list(
    dist_dt       = dist_dt,
    trans_dt      = trans_dt,
    n_multi        = n_multi,
    n_changed      = n_changed,
    share_changed  = share_changed,
    up_moves       = up_moves,
    down_moves     = down_moves,
    skip_moves     = skip_moves
  )
}

# ------------------------------------------------------------------------------
# 9. Run migration metrics for all three options
# ------------------------------------------------------------------------------
message("\nStep 9: Computing migration metrics per option...")

res_A4 <- compute_migration_metrics(firm_cycle, "size_bin_A4", "A4")
res_A3 <- compute_migration_metrics(firm_cycle, "size_bin_A3", "A3")
res_B  <- compute_migration_metrics(firm_cycle, "size_bin_B",  "B")

# ------------------------------------------------------------------------------
# 10. Boundary-noise flag (A4 only, plan §3.5 failure modes)
#
# Share of A4 movers where the employment change that caused the migration
# crossed a bin threshold by <= BOUNDARY_NOISE_TOL employees.
# A4 thresholds: 9.5, 49.5, 499.5  (midpoints between integer bin edges)
# We check whether the firm's cycle means straddle a threshold within 2 employees.
# ------------------------------------------------------------------------------
message("\nStep 10: Computing boundary-noise flag for A4...")

A4_THRESHOLDS <- c(9.5, 49.5, 499.5)   # exclusive boundaries

# Find all consecutive-cycle pairs where A4 bin changed
cycles_ordered <- sort(BASELINE_WINDOWS$election_cycle)
cycle_pairs_dt <- data.table(
  cycle_from = cycles_ordered[-length(cycles_ordered)],
  cycle_to   = cycles_ordered[-1L]
)

boundary_list <- vector("list", nrow(cycle_pairs_dt))

for (k in seq_len(nrow(cycle_pairs_dt))) {
  c_from <- cycle_pairs_dt$cycle_from[k]
  c_to   <- cycle_pairs_dt$cycle_to[k]

  dt_from <- firm_cycle[election_cycle == c_from & !is.na(size_bin_A4),
                        .(firm_id, bin_from = size_bin_A4, emp_from = mean_emp)]
  dt_to   <- firm_cycle[election_cycle == c_to   & !is.na(size_bin_A4),
                        .(firm_id, bin_to   = size_bin_A4, emp_to   = mean_emp)]

  pair <- merge(dt_from, dt_to, by = "firm_id")
  if (!nrow(pair)) next

  # Keep only movers (bin changed)
  movers <- pair[bin_from != bin_to]
  if (!nrow(movers)) next

  # For each mover, check whether a threshold was crossed by <= tol employees
  # by finding the threshold between bin_from and bin_to and computing distance.
  movers[, is_boundary_noise := vapply(
    seq_len(.N),
    function(j) {
      b_lo  <- min(bin_from[j], bin_to[j])
      b_hi  <- max(bin_from[j], bin_to[j])
      # Threshold between b_lo and b_hi:
      #   b_lo=1,b_hi=2 -> threshold = 9.5
      #   b_lo=2,b_hi=3 -> threshold = 49.5
      #   b_lo=3,b_hi=4 -> threshold = 499.5
      thresh_idx <- b_lo   # aligns: boundary between bin k and k+1 is A4_THRESHOLDS[k]
      if (thresh_idx < 1L || thresh_idx > length(A4_THRESHOLDS)) return(FALSE)
      thresh <- A4_THRESHOLDS[thresh_idx]
      # min distance from either mean_emp to the threshold
      dist_from <- abs(emp_from[j] - thresh)
      dist_to   <- abs(emp_to[j]   - thresh)
      min(dist_from, dist_to) <= BOUNDARY_NOISE_TOL
    },
    FUN.VALUE = logical(1L)
  )]

  boundary_list[[k]] <- movers[, .(
    cycle_from  = c_from,
    cycle_to    = c_to,
    n_movers    = .N,
    n_boundary  = sum(is_boundary_noise)
  )]
}

boundary_dt <- rbindlist(boundary_list, fill = TRUE)
total_movers_A4    <- if (nrow(boundary_dt)) sum(boundary_dt$n_movers)    else 0L
total_boundary_A4  <- if (nrow(boundary_dt)) sum(boundary_dt$n_boundary)  else 0L
share_boundary_noise_A4 <- if (total_movers_A4 > 0L) {
  total_boundary_A4 / total_movers_A4
} else NA_real_

message(sprintf(
  "  [A4] Boundary-noise: %s / %s movers crossed threshold by <= %d emp (%.1f%%)",
  format(total_boundary_A4, big.mark = ","),
  format(total_movers_A4,   big.mark = ","),
  BOUNDARY_NOISE_TOL,
  100 * share_boundary_noise_A4
))

# ------------------------------------------------------------------------------
# 11. Cross-rule consistency
#
# For the same firm, compare "stable" status (n_distinct_bins == 1) across
# A4, A3, B (multi-cycle firms only).
# A firm stable under A3 but not A4: its moves were all within Micro/Pequena.
# A firm stable under A4 but not B: relative rank shifted while absolute level held.
# ------------------------------------------------------------------------------
message("\nStep 11: Cross-rule consistency...")

firm_stability <- firm_cycle[, .(
  n_obs_A4 = sum(!is.na(size_bin_A4)),
  n_obs_A3 = sum(!is.na(size_bin_A3)),
  n_obs_B  = sum(!is.na(size_bin_B)),
  n_dist_A4 = uniqueN(size_bin_A4[!is.na(size_bin_A4)]),
  n_dist_A3 = uniqueN(size_bin_A3[!is.na(size_bin_A3)]),
  n_dist_B  = uniqueN(size_bin_B[!is.na(size_bin_B)])
), by = firm_id]

# Filter to firms with >= 2 observed cycles under at least one option
firm_stability_multi <- firm_stability[
  n_obs_A4 >= 2L | n_obs_A3 >= 2L | n_obs_B >= 2L
]

n_stability_multi <- nrow(firm_stability_multi)
firm_stability_multi[, stable_A4 := (n_obs_A4 >= 2L & n_dist_A4 == 1L)]
firm_stability_multi[, stable_A3 := (n_obs_A3 >= 2L & n_dist_A3 == 1L)]
firm_stability_multi[, stable_B  := (n_obs_B  >= 2L & n_dist_B  == 1L)]

# Cross-consistency counts
n_stable_all_three  <- firm_stability_multi[(stable_A4) & (stable_A3) & (stable_B), .N]
n_stable_A4_not_B   <- firm_stability_multi[(stable_A4) & !(stable_B)  & n_obs_B  >= 2L, .N]
n_stable_B_not_A4   <- firm_stability_multi[!(stable_A4) & n_obs_A4 >= 2L & (stable_B), .N]
n_stable_A3_not_A4  <- firm_stability_multi[(stable_A3) & !(stable_A4) & n_obs_A4 >= 2L, .N]

message(sprintf(
  "  Multi-cycle firms (any option): %s",
  format(n_stability_multi, big.mark = ",")
))
message(sprintf("  Stable under all 3: %s",
                format(n_stable_all_three, big.mark = ",")))
message(sprintf("  Stable A4 but not B: %s (absolute stable, rank shifted)",
                format(n_stable_A4_not_B, big.mark = ",")))
message(sprintf("  Stable B but not A4: %s (rank stable, crossed abs threshold)",
                format(n_stable_B_not_A4, big.mark = ",")))
message(sprintf("  Stable A3 but not A4: %s (move was within Micro/Pequena)",
                format(n_stable_A3_not_A4, big.mark = ",")))

# ------------------------------------------------------------------------------
# 12. Write CSVs
# ------------------------------------------------------------------------------
message("\nStep 12: Writing output CSVs...")

# Distribution CSVs (one per option)
fwrite(res_A4$dist_dt,
       file.path(OUTPUT_DIR, "bin_stability_A4_distribution.csv"))
message("  Written: bin_stability_A4_distribution.csv")

fwrite(res_A3$dist_dt,
       file.path(OUTPUT_DIR, "bin_stability_A3_distribution.csv"))
message("  Written: bin_stability_A3_distribution.csv")

fwrite(res_B$dist_dt,
       file.path(OUTPUT_DIR, "bin_stability_B_distribution.csv"))
message("  Written: bin_stability_B_distribution.csv")

# Transition matrix CSVs (one per option)
fwrite(res_A4$trans_dt,
       file.path(OUTPUT_DIR, "bin_stability_A4_transitions.csv"))
message("  Written: bin_stability_A4_transitions.csv")

fwrite(res_A3$trans_dt,
       file.path(OUTPUT_DIR, "bin_stability_A3_transitions.csv"))
message("  Written: bin_stability_A3_transitions.csv")

fwrite(res_B$trans_dt,
       file.path(OUTPUT_DIR, "bin_stability_B_transitions.csv"))
message("  Written: bin_stability_B_transitions.csv")

# Summary CSV: one row per option
n_total_moves_A4 <- if (!is.na(res_A4$up_moves)) {
  res_A4$up_moves + res_A4$down_moves
} else NA_integer_

summary_dt <- data.table(
  option                 = c("A4", "A3", "B"),
  share_firms_ever_changed = c(
    res_A4$share_changed,
    res_A3$share_changed,
    res_B$share_changed
  ),
  n_multi_cycle_firms    = c(
    res_A4$n_multi,
    res_A3$n_multi,
    res_B$n_multi
  ),
  n_firms_ever_changed   = c(
    res_A4$n_changed,
    res_A3$n_changed,
    res_B$n_changed
  ),
  up_moves               = c(res_A4$up_moves,   NA_integer_, NA_integer_),
  down_moves             = c(res_A4$down_moves,  NA_integer_, NA_integer_),
  skip_bin_moves         = c(res_A4$skip_moves,  NA_integer_, NA_integer_),
  share_skip_bin_moves   = c(
    if (!is.na(n_total_moves_A4) && n_total_moves_A4 > 0L) {
      res_A4$skip_moves / n_total_moves_A4
    } else NA_real_,
    NA_real_,
    NA_real_
  ),
  share_boundary_noise_A4 = c(share_boundary_noise_A4, NA_real_, NA_real_),
  fall_back_rate          = fallback_rate,   # same for all options (same input grid)
  recommendation_flag     = c(
    as.integer(!is.na(res_A4$share_changed) &&
                 res_A4$share_changed < STABILITY_THRESHOLD),
    NA_integer_,
    NA_integer_
  )
)

# recommendation_flag = 1 means "lifetime-mean rule recommended" (low migration)
fwrite(summary_dt,
       file.path(OUTPUT_DIR, "bin_stability_summary.csv"))
message("  Written: bin_stability_summary.csv")

# ------------------------------------------------------------------------------
# 13. Markdown report
# ------------------------------------------------------------------------------
message("\nStep 13: Writing bin_stability_report.md...")

fmt_pct  <- function(x, d = 1) ifelse(is.na(x), "—", sprintf(paste0("%.", d, "f%%"), 100 * x))
fmt_num  <- function(x, d = 4) ifelse(is.na(x), "—", sprintf(paste0("%.", d, "f"), x))
fmt_int  <- function(x)        ifelse(is.na(x), "—", format(as.integer(x), big.mark = ","))

decision_text <- if (!is.na(res_A4$share_changed) &&
                      res_A4$share_changed < STABILITY_THRESHOLD) {
  paste0(
    "**Recommendation: LIFETIME-MEAN rule.** Under Option A4, only ",
    fmt_pct(res_A4$share_changed),
    " of multi-cycle firms ever change bin — below the 20% threshold. ",
    "The cycle-baseline construction adds complexity without measurable benefit. ",
    "Consider replacing it with a single lifetime mean employment as the ",
    "bin input. Re-run E1–E3 with the lifetime-mean variant before committing."
  )
} else {
  paste0(
    "**Recommendation: KEEP CYCLE-BASELINE RULE.** Under Option A4, ",
    fmt_pct(res_A4$share_changed),
    " of multi-cycle firms change bin at least once — at or above the 20% threshold. ",
    "Firm size genuinely shifts over the 2002–2017 panel. The cycle-baseline ",
    "construction correctly captures these changes and is justified. Proceed to E1–E3."
  )
}

# Build A4 transition matrix as a readable Markdown table (aggregate across cycles)
if (nrow(res_A4$trans_dt) > 0L) {
  agg_trans_A4 <- res_A4$trans_dt[, .(N = sum(N)), by = .(bin_from, bin_to)]
  setorder(agg_trans_A4, bin_from, bin_to)

  bins_present <- sort(unique(c(agg_trans_A4$bin_from, agg_trans_A4$bin_to)))
  bin_labels_present <- A4_LABELS[bins_present]

  # Header
  trans_header <- paste0("| From \\ To | ",
                          paste(bin_labels_present, collapse = " | "),
                          " |")
  trans_sep    <- paste0("|", paste(rep("---", length(bins_present) + 1L),
                                     collapse = "|"), "|")

  trans_rows <- vapply(bins_present, function(bf) {
    counts <- vapply(bins_present, function(bt) {
      n <- agg_trans_A4[bin_from == bf & bin_to == bt, N]
      if (!length(n) || is.na(n)) "0" else format(n, big.mark = ",")
    }, character(1L))
    paste0("| ", A4_LABELS[bf], " | ", paste(counts, collapse = " | "), " |")
  }, character(1L))

  trans_table_lines <- c(trans_header, trans_sep, trans_rows)
} else {
  trans_table_lines <- c("_No transitions computed (empty transition table)._")
}

report_lines <- c(
  "# Bin Stability Pre-Exercise (E0) — Report",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Goal",
  "",
  "Measure bin migration across Options A4 (4-bin BNDES native), A3 (3-bin collapse), ",
  "and B (within-sector tertiles) over the 7 election cycles 2005–2017. ",
  "Determines whether the cycle-baseline construction is necessary or can be ",
  "replaced with a simpler lifetime-mean rule.",
  "",
  "**F0 link:** Bin stability is a precondition for justifying the cycle-baseline ",
  "rule in `docs/PROJECT_BLUEPRINT.md` §3 F0.",
  "",
  "---",
  "",
  "## 1. Top-Line Numbers",
  "",
  sprintf("- **Fall-back rate:** %.2f%% of (firm × cycle) cells filled by the fall-back rule.",
          100 * fallback_rate),
  "",
  "| Option | Multi-cycle firms | Ever changed | Share changed | Skip-bin moves (A4) | Boundary noise (A4) |",
  "|--------|------------------|-------------|--------------|--------------------|--------------------|",
  sprintf("| **A4** | %s | %s | %s | %s | %s |",
          fmt_int(res_A4$n_multi),
          fmt_int(res_A4$n_changed),
          fmt_pct(res_A4$share_changed),
          fmt_int(res_A4$skip_moves),
          fmt_pct(share_boundary_noise_A4)),
  sprintf("| **A3** | %s | %s | %s | — | — |",
          fmt_int(res_A3$n_multi),
          fmt_int(res_A3$n_changed),
          fmt_pct(res_A3$share_changed)),
  sprintf("| **B**  | %s | %s | %s | — | — |",
          fmt_int(res_B$n_multi),
          fmt_int(res_B$n_changed),
          fmt_pct(res_B$share_changed)),
  "",
  "---",
  "",
  "## 2. A4 Transition Matrix (aggregate across all consecutive cycle pairs)",
  "",
  "Rows = bin in cycle c, columns = bin in cycle c+1.",
  "",
  trans_table_lines,
  "",
  "_Diagonal = stayers; off-diagonal = movers._",
  "",
  "---",
  "",
  "## 3. Cross-Rule Consistency",
  "",
  sprintf("Multi-cycle firms (any option): **%s**", fmt_int(n_stability_multi)),
  "",
  sprintf("- Stable under all 3 options: %s", fmt_int(n_stable_all_three)),
  sprintf("- Stable under A4 but not B: %s (absolute level stable; relative rank shifted — reflects peer-composition change, not firm-size change)", fmt_int(n_stable_A4_not_B)),
  sprintf("- Stable under B but not A4: %s (crossed an absolute threshold; rank stayed constant — firm's growth tracked its sector)", fmt_int(n_stable_B_not_A4)),
  sprintf("- Stable under A3 but not A4: %s (migration was within Micro/Pequena boundary; collapsed bin absorbs it)", fmt_int(n_stable_A3_not_A4)),
  "",
  "---",
  "",
  "## 4. Recommendation",
  "",
  decision_text,
  "",
  "---",
  "",
  "## 5. Files Written",
  "",
  "| File | Description |",
  "|------|-------------|",
  "| `bin_stability_A4_distribution.csv` | n_distinct_bins distribution (A4) |",
  "| `bin_stability_A4_transitions.csv` | Consecutive-cycle transition matrix (A4) |",
  "| `bin_stability_A3_distribution.csv` | n_distinct_bins distribution (A3) |",
  "| `bin_stability_A3_transitions.csv` | Consecutive-cycle transition matrix (A3) |",
  "| `bin_stability_B_distribution.csv` | n_distinct_bins distribution (B) |",
  "| `bin_stability_B_transitions.csv` | Consecutive-cycle transition matrix (B) |",
  "| `bin_stability_summary.csv` | Summary: one row per option, key metrics + flag |",
  ""
)

writeLines(report_lines,
           file.path(OUTPUT_DIR, "bin_stability_report.md"))
message("  Written: bin_stability_report.md")

# ------------------------------------------------------------------------------
# 14. Console summary
# ------------------------------------------------------------------------------
message("\n")
message("=================================================================")
message("  E0: Bin Stability Pre-Exercise — Summary")
message("=================================================================")
message(sprintf("  Fall-back rate:  %.2f%%", 100 * fallback_rate))
message("")
message(sprintf("  [A4] Multi-cycle firms: %s", format(res_A4$n_multi, big.mark = ",")))
message(sprintf("  [A4] Ever changed:      %s (%.1f%%)",
                format(res_A4$n_changed, big.mark = ","),
                100 * res_A4$share_changed))
message(sprintf("  [A4] Skip-bin moves:    %s", fmt_int(res_A4$skip_moves)))
message(sprintf("  [A4] Boundary noise:    %.1f%% of movers",
                100 * share_boundary_noise_A4))
message("")
message(sprintf("  [A3] Ever changed:      %s (%.1f%%)",
                format(res_A3$n_changed, big.mark = ","),
                100 * res_A3$share_changed))
message(sprintf("  [B]  Ever changed:      %s (%.1f%%)",
                format(res_B$n_changed, big.mark = ","),
                100 * res_B$share_changed))
message("")
if (!is.na(res_A4$share_changed) && res_A4$share_changed < STABILITY_THRESHOLD) {
  message("  DECISION: share_firms_ever_changed < 20% under A4.")
  message("            Recommend LIFETIME-MEAN rule. Pause for user review.")
} else {
  message("  DECISION: share_firms_ever_changed >= 20% under A4.")
  message("            Cycle-baseline rule is JUSTIFIED. Proceed to E1-E3.")
}
message("")
message("  Output files written to:")
message("    ", OUTPUT_DIR)
message("=================================================================")

# ------------------------------------------------------------------------------
# 15. Return invisible list for interactive inspection
# ------------------------------------------------------------------------------
invisible(list(
  firm_cycle        = firm_cycle,
  res_A4            = res_A4,
  res_A3            = res_A3,
  res_B             = res_B,
  fallback_rate     = fallback_rate,
  summary_dt        = summary_dt,
  boundary_dt       = boundary_dt,
  firm_stability    = firm_stability_multi
))
