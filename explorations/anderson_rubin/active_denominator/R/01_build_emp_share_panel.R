#!/usr/bin/env Rscript

# ==============================================================================
# 01_build_emp_share_panel.R
# Build (j, m, t) employment-share panel for the AR-test endogenous variable.
# Three firm-support denominator variants per the hybrid recommendation:
#   contemporaneous (default): unbalanced RAIS at year t
#   frozen:                    firms RAIS-active in [e(t)-4, e(t)-1]
#   balanced:                  firms RAIS-active in [e(t)-4, e(t)-1] AND
#                              every post-election year in [e(t), e(t)+3]
#
# Paper: Testing Industrial Policy / Brazil BNDES; AR test, endogenous variable
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst   (script 22)
#   data/processed/muni_employment_baselines.qs2  (script 32b; reference only)
# Outputs (under explorations/anderson_rubin/active_denominator/output/):
#   emp_share_panel_{variant}.qs2
#   emp_share_panel_{variant}_summary.csv
#   slack_per_cell_{variant}.csv
#
# Phase 1 of journal/plans/2026-05-12_firm_support_hybrid_implementation.md (B1.2).
# Does NOT modify any production script. Production graduation = Phase 2.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
  library(fst)
})

# ---- Paths -------------------------------------------------------------------

# Resolve this script file robustly across Rscript / source() / RStudio.
get_this_script <- function() {
  script_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", script_args, value = TRUE)
  if (length(file_arg)) {
    return(normalizePath(sub("^--file=", "", file_arg[[1L]]),
                         winslash = "/", mustWork = TRUE))
  }
  frame_paths <- vapply(sys.frames(), function(env) {
    ofile <- env$ofile
    if (is.null(ofile) || !nzchar(ofile)) return(NA_character_)
    ofile
  }, character(1))
  frame_paths <- frame_paths[!is.na(frame_paths)]
  if (length(frame_paths)) {
    return(normalizePath(frame_paths[[length(frame_paths)]],
                         winslash = "/", mustWork = TRUE))
  }
  stop("Cannot determine script path. Run via Rscript or source(..., chdir=TRUE).")
}

THIS_SCRIPT <- get_this_script()
BRANCH_DIR  <- normalizePath(file.path(dirname(THIS_SCRIPT), ".."),
                             winslash = "/", mustWork = TRUE)
PROJECT_ROOT <- normalizePath(file.path(BRANCH_DIR, "..", "..", ".."),
                              winslash = "/", mustWork = TRUE)

# Source canonical path helpers (read-only consumers).
source(file.path(PROJECT_ROOT, "scripts", "R", "_utils", "utils.R"))

OUTPUT_BRANCH <- file.path(BRANCH_DIR, "output")
if (!dir.exists(OUTPUT_BRANCH)) dir.create(OUTPUT_BRANCH, recursive = TRUE)

# ---- Reproducibility ---------------------------------------------------------

set.seed(20260512L)
setDTthreads(0L)

# ---- CLI parsing -------------------------------------------------------------

cli <- commandArgs(trailingOnly = TRUE)

parse_kv <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), cli, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", flag, "="), "", hit[[1L]])
}

DENOMINATOR <- parse_kv("--denominator", "contemporaneous")
SECTOR_VAR  <- parse_kv("--sector-var",  "cnae_section")

stopifnot(DENOMINATOR %in% c("contemporaneous", "frozen", "balanced"))
stopifnot(is.character(SECTOR_VAR), length(SECTOR_VAR) == 1L, nzchar(SECTOR_VAR))

message(sprintf("[INFO] %s | denominator=%s | sector_var=%s",
                Sys.time(), DENOMINATOR, SECTOR_VAR))

# ---- Mayor election calendar -------------------------------------------------
# Matches script 33 mayor rows of `baseline_window_map`. treatment_year = e(t)+1.
# For a given year t, cycle = smallest c in {2005, 2009, 2013, 2017} with c > t.
# Year-to-cycle assignment is total over 2002..2017.

CYCLE_WINDOWS <- data.table(
  cycle      = c(2005L, 2009L, 2013L, 2017L),
  election   = c(2004L, 2008L, 2012L, 2016L),
  bl_start   = c(2000L, 2004L, 2008L, 2012L),
  bl_end     = c(2003L, 2007L, 2011L, 2015L),
  post_start = c(2004L, 2008L, 2012L, 2016L),
  post_end   = c(2007L, 2011L, 2015L, 2019L)
)

assign_cycle <- function(year) {
  fcase(
    year <= 2004L, 2005L,
    year <= 2008L, 2009L,
    year <= 2012L, 2013L,
    default       = 2017L
  )
}

# ---- Load RAIS panel ---------------------------------------------------------

recon_fst <- output_path("rais_bndes_reconstructed.fst")
recon_qs2 <- output_path("rais_bndes_reconstructed.qs2")

stopifnot(
  "rais_bndes_reconstructed.fst or .qs2 must exist (script 22)" =
    file.exists(recon_fst) || file.exists(recon_qs2)
)
stopifnot(
  "muni_employment_baselines.qs2 must exist (script 32b)" =
    file.exists(output_path("muni_employment_baselines.qs2"))
)

need_cols <- c("firm_id", "muni_id", "year", "n_employees", "in_rais", SECTOR_VAR)

message(sprintf("[INFO] %s | loading RAIS panel...", Sys.time()))
if (file.exists(recon_fst)) {
  avail <- fst::metadata_fst(recon_fst)$columnNames
  missing_cols <- setdiff(need_cols, avail)
  if (length(missing_cols)) {
    stop("Missing required columns in reconstructed panel: ",
         paste(missing_cols, collapse = ", "))
  }
  panel <- fst::read_fst(recon_fst, columns = need_cols, as.data.table = TRUE)
} else {
  raw <- qs_read(recon_qs2)
  setDT(raw)
  missing_cols <- setdiff(need_cols, names(raw))
  if (length(missing_cols)) {
    stop("Missing required columns in reconstructed panel: ",
         paste(missing_cols, collapse = ", "))
  }
  panel <- raw[, ..need_cols]
  rm(raw); invisible(gc())
}

message(sprintf("[INFO] %s | loaded %s rows", Sys.time(),
                format(nrow(panel), big.mark = ",")))

# Filter to RAIS-covered rows (D1 universe).
panel <- panel[in_rais == TRUE]
panel[, in_rais := NULL]

# Type coercion and basic hygiene.
panel[, muni_id := as.integer(muni_id)]
panel[, year    := as.integer(year)]
panel[, n_employees := as.numeric(n_employees)]
panel <- panel[!is.na(muni_id) & muni_id > 0L]
panel <- panel[!is.na(get(SECTOR_VAR))]

# Phase 0 A0.2 invariant: every RAIS firm has n_employees >= 1.
stopifnot(panel[, min(n_employees, na.rm = TRUE)] >= 1)

# Cycle assignment for every row.
panel[, cycle := assign_cycle(year)]
panel <- merge(panel, CYCLE_WINDOWS, by = "cycle", all.x = TRUE)
panel[, in_window := year >= bl_start & year <= bl_end]

# ---- Variant firm-set masks --------------------------------------------------

message(sprintf("[INFO] %s | computing variant firm sets for '%s'...",
                Sys.time(), DENOMINATOR))

if (DENOMINATOR == "contemporaneous") {

  panel[, keep := TRUE]

} else if (DENOMINATOR %in% c("frozen", "balanced")) {

  # Cycle membership is cross-join, not per-row: a firm-year is kept at cycle c
  # iff the firm is in the variant's c-specific firm set, regardless of the row's
  # own cycle assignment. Build firm sets per cycle by year-range membership.

  firm_year_set <- unique(panel[, .(firm_id, year)])
  data_min <- 2002L
  data_max <- 2017L

  build_cycle_set <- function(start_yr, end_yr) {
    yrs <- intersect(seq.int(start_yr, end_yr), data_min:data_max)
    list(years = yrs, required = length(yrs))
  }

  variant_keep_list <- vector("list", nrow(CYCLE_WINDOWS))
  for (i in seq_len(nrow(CYCLE_WINDOWS))) {
    cyc <- CYCLE_WINDOWS$cycle[i]
    pre <- build_cycle_set(CYCLE_WINDOWS$bl_start[i], CYCLE_WINDOWS$bl_end[i])
    if (DENOMINATOR == "frozen") {
      # any presence in pre window
      keep_firms <- firm_year_set[year %in% pre$years,
                                  unique(firm_id)]
    } else {
      # balanced: present in EVERY pre year AND EVERY post year
      post <- build_cycle_set(CYCLE_WINDOWS$post_start[i],
                              CYCLE_WINDOWS$post_end[i])
      pre_counts <- firm_year_set[year %in% pre$years,
                                  .(n = uniqueN(year)), by = firm_id]
      post_counts <- firm_year_set[year %in% post$years,
                                   .(n = uniqueN(year)), by = firm_id]
      pre_firms  <- pre_counts[n == pre$required, firm_id]
      post_firms <- post_counts[n == post$required, firm_id]
      keep_firms <- intersect(pre_firms, post_firms)
    }
    variant_keep_list[[i]] <- data.table(firm_id = keep_firms, cycle = cyc,
                                         keep = TRUE)
    message(sprintf("[INFO] cycle %d (%s): %s firms in keep set",
                    cyc, DENOMINATOR, format(length(keep_firms), big.mark = ",")))
  }
  variant_keep <- rbindlist(variant_keep_list, use.names = TRUE)
  panel <- merge(panel, variant_keep, by = c("firm_id", "cycle"), all.x = TRUE)
  panel[is.na(keep), keep := FALSE]
  rm(firm_year_set, variant_keep_list, variant_keep); invisible(gc())
}

# ---- Aggregate to (sector, muni, year) ---------------------------------------

message(sprintf("[INFO] %s | aggregating to (j, m, t) cells...", Sys.time()))

# Full skeleton: contemporaneous cell existence per D2.
skeleton <- unique(panel[, .(muni_id, sector_j = get(SECTOR_VAR), year)])

# n_jmt under the chosen variant's firm set.
cells_var <- panel[keep == TRUE,
                   .(n_jmt = sum(n_employees, na.rm = TRUE)),
                   by = .(muni_id, sector_j = get(SECTOR_VAR), year)]

# Contemporaneous n_mt and frozen-firm-mass-by-cell for slack control.
cells_all <- panel[,
                   .(n_jmt_contemp = sum(n_employees, na.rm = TRUE)),
                   by = .(muni_id, sector_j = get(SECTOR_VAR), year)]

cells <- merge(skeleton, cells_var, by = c("muni_id", "sector_j", "year"),
               all.x = TRUE)
cells <- merge(cells, cells_all, by = c("muni_id", "sector_j", "year"),
               all.x = TRUE)
cells[is.na(n_jmt), n_jmt := 0]
cells[is.na(n_jmt_contemp), n_jmt_contemp := 0]

# Add cycle / window flags at year level.
cells[, cycle := assign_cycle(year)]
cells <- merge(cells, CYCLE_WINDOWS[, .(cycle, bl_start, bl_end)],
               by = "cycle", all.x = TRUE)
cells[, in_window := year >= bl_start & year <= bl_end]
cells[, c("bl_start", "bl_end") := NULL]

# Muni totals under both the variant firm set and contemporaneous (slack denom).
muni_totals <- cells[, .(n_mt           = sum(n_jmt),
                         n_mt_contemp   = sum(n_jmt_contemp)),
                     by = .(muni_id, year)]

cells <- merge(cells, muni_totals, by = c("muni_id", "year"), all.x = TRUE)

# Drop muni-years where variant denominator is zero (no firms in that variant).
n_dropped_muni_years <- nrow(unique(cells[n_mt == 0, .(muni_id, year)]))
cells <- cells[n_mt > 0]

cells[, s_emp_jmt := n_jmt / n_mt]

# delta_s_emp_jmt = within-(muni, sector) first difference in year.
setorder(cells, muni_id, sector_j, year)
cells[, delta_s_emp_jmt := s_emp_jmt - shift(s_emp_jmt, type = "lag"),
      by = .(muni_id, sector_j)]

# Final column rename to the requested schema.
setnames(cells, "sector_j", SECTOR_VAR)
out_cols <- c("muni_id", SECTOR_VAR, "year",
              "n_jmt", "n_mt", "s_emp_jmt", "delta_s_emp_jmt",
              "cycle", "in_window")
cells_out <- cells[, ..out_cols]

# ---- Sanity checks -----------------------------------------------------------

stopifnot(cells_out[, all(s_emp_jmt >= 0 & s_emp_jmt <= 1)])
stopifnot(cells_out[!is.na(delta_s_emp_jmt),
                    all(delta_s_emp_jmt >= -1 & delta_s_emp_jmt <= 1)])

n_rows         <- nrow(cells_out)
n_muni_year    <- uniqueN(cells_out[, .(muni_id, year)])
n_unique_cells <- uniqueN(cells_out[, c("muni_id", SECTOR_VAR, "year"),
                                    with = FALSE])
J              <- uniqueN(cells_out[[SECTOR_VAR]])

share_stats <- cells_out[, .(
  min    = min(s_emp_jmt),
  median = median(s_emp_jmt),
  mean   = mean(s_emp_jmt),
  max    = max(s_emp_jmt)
)]

top5_sectors <- cells_out[, .(mean_share = mean(s_emp_jmt),
                              n_cells    = .N),
                          by = c(SECTOR_VAR)][order(-mean_share)][1:5]

message(sprintf("[INFO] %s | panel rows: %s | muni-years: %s | unique cells: %s | J=%d",
                Sys.time(),
                format(n_rows, big.mark = ","),
                format(n_muni_year, big.mark = ","),
                format(n_unique_cells, big.mark = ","),
                J))
message(sprintf("[INFO] dropped muni-years with n_mt==0 under %s: %d",
                DENOMINATOR, n_dropped_muni_years))
message(sprintf("[INFO] s_emp distribution -- min=%.4f median=%.4f mean=%.4f max=%.4f (expect mean ~ 1/J = %.4f)",
                share_stats$min, share_stats$median, share_stats$mean,
                share_stats$max, 1 / J))
message("[INFO] top-5 sectors by mean share:")
for (i in seq_len(nrow(top5_sectors))) {
  message(sprintf("       %s mean=%.4f n=%s",
                  as.character(top5_sectors[[SECTOR_VAR]][i]),
                  top5_sectors$mean_share[i],
                  format(top5_sectors$n_cells[i], big.mark = ",")))
}

# ---- Slack-per-cell artifact (BHJ §4.4) --------------------------------------
# slack at (muni, year, cycle) = share of contemporaneous n_mt accounted for
# by the variant's firm set. For contemporaneous: identically 1.0.

slack <- unique(cells[, .(muni_id, year, cycle, n_mt, n_mt_contemp)])
slack[, slack_share := fifelse(n_mt_contemp > 0, n_mt / n_mt_contemp, NA_real_)]
setorder(slack, muni_id, year)

# ---- Save --------------------------------------------------------------------

out_panel_path <- file.path(OUTPUT_BRANCH,
                            sprintf("emp_share_panel_%s.qs2", DENOMINATOR))
out_summary_path <- file.path(OUTPUT_BRANCH,
                              sprintf("emp_share_panel_%s_summary.csv",
                                      DENOMINATOR))
out_slack_path <- file.path(OUTPUT_BRANCH,
                            sprintf("slack_per_cell_%s.csv", DENOMINATOR))

qs_save(cells_out, out_panel_path)

summary_dt <- data.table(
  denominator             = DENOMINATOR,
  sector_var              = SECTOR_VAR,
  n_rows                  = n_rows,
  n_unique_muni_sec_year  = n_unique_cells,
  n_muni_year             = n_muni_year,
  n_sectors               = J,
  n_dropped_muni_years    = n_dropped_muni_years,
  s_min                   = share_stats$min,
  s_median                = share_stats$median,
  s_mean                  = share_stats$mean,
  s_max                   = share_stats$max,
  inv_J                   = 1 / J
)
fwrite(summary_dt, out_summary_path)
fwrite(slack, out_slack_path)

message(sprintf("[INFO] wrote: %s", out_panel_path))
message(sprintf("[INFO] wrote: %s", out_summary_path))
message(sprintf("[INFO] wrote: %s", out_slack_path))
message(sprintf("[INFO] %s | done.", Sys.time()))
