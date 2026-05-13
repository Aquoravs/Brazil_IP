#!/usr/bin/env Rscript

# ==============================================================================
# 32c_build_emp_share_panel.R
# Build (muni, sector, year) employment-share panel for the AR-test
# endogenous variable, plus BHJ §4.4 per-cell slack column.
#
# Phase 2 production graduation of:
#   explorations/anderson_rubin/active_denominator/R/01_build_emp_share_panel.R
# Plan: journal/plans/2026-05-12_firm_support_hybrid_implementation.md (C2.1).
# Source memo: docs/strategy/firm_support_restrictions_ssiv.md (R2 96/100).
#
# Design decisions adopted (per the plan):
#   D1   — Firm universe = RAIS only (in_rais == TRUE). Structural claim is
#          formal-sector composition.
#   D2   — Skeleton (tightened 2026-05-12): any firm with a RAIS row in
#          year t. Current panel pre-strips RAIS-Negativa equivalents
#          (Phase 0 A0.2: zero-employee rate = 0.0000%), so this is
#          equivalent to n_employees >= 1 under the current data. Three
#          denominator variants are offered via `--denominator`:
#            contemporaneous (default): unbalanced RAIS at year t
#            frozen:                    firms active in [e(t)-4, e(t)-1]
#            balanced:                  firms active in pre AND post window
#   D5-op — exposure margin handled elsewhere; this script is volume-agnostic.
#
# CLI:
#   --denominator={contemporaneous,frozen,balanced}   default contemporaneous
#   --sector-var={policy_block,cnae_section}          default policy_block
#                                                     (PRIMARY per user 2026-05-12)
#
# Inputs:
#   output/rais_bndes_reconstructed.fst   (script 22)
#   output/policy_block_mapping.qs2       (script 30e) -- required for policy_block
#
# Outputs:
#   output/emp_share_panel_<sector_var>.qs2
#   output/emp_share_panel_<sector_var>_summary.csv
#   output/emp_share_panel_<sector_var>_slack.csv  (per-cell BHJ §4.4)
#
# Schema (one row per muni x sector x year):
#   muni_id, <sector_var>, year, n_jmt, n_mt, s_emp_mjt, delta_s_emp_mjt,
#   slack_frozen_mt, cycle, in_window
#
# Notes:
#   - Drop muni-years with n_mt == 0; abort if drop count > 5% of muni-years.
#   - `slack_frozen_mt` is the share of contemporaneous n_mt accounted for by
#     the frozen-baseline firm set at the year's cycle. Computed for EVERY
#     muni-year regardless of the chosen --denominator; with a stopifnot()
#     gate against NA / missing.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
  library(fst)
})

# ---- Bootstrap (canonical path helpers) --------------------------------------

bootstrap_file <- local({
  project_root_opt <- getOption("politicsregs.project_root", default = NULL)
  if (is.character(project_root_opt) && length(project_root_opt) == 1L && nzchar(project_root_opt)) {
    return(file.path(project_root_opt, "scripts", "R", "_utils", "script_bootstrap.R"))
  }
  script_args_full <- commandArgs(trailingOnly = FALSE)
  script_file <- grep("^--file=", script_args_full, value = TRUE)
  if (length(script_file)) {
    script_file <- normalizePath(sub("^--file=", "", script_file[[1L]]), winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }
  frame_paths <- vapply(sys.frames(), function(env) {
    ofile <- env$ofile
    if (is.null(ofile) || !nzchar(ofile)) return(NA_character_)
    ofile
  }, character(1))
  frame_paths <- frame_paths[!is.na(frame_paths)]
  if (length(frame_paths)) {
    script_file <- normalizePath(frame_paths[[length(frame_paths)]], winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }
  stop("Cannot determine bootstrap path. Call init_politicsregs_session() first.")
})
source(normalizePath(bootstrap_file, winslash = "/", mustWork = TRUE))
bootstrap_politicsregs()

# ---- Reproducibility ---------------------------------------------------------

set.seed(20260513L)
setDTthreads(0L)

# ---- CLI parsing -------------------------------------------------------------

cli <- commandArgs(trailingOnly = TRUE)

parse_kv <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), cli, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", flag, "="), "", hit[[1L]])
}

DENOMINATOR <- parse_kv("--denominator", "contemporaneous")
SECTOR_VAR  <- parse_kv("--sector-var",  "policy_block")

stopifnot(
  "Invalid --denominator" = DENOMINATOR %in% c("contemporaneous", "frozen", "balanced"),
  "Invalid --sector-var"  = SECTOR_VAR  %in% c("policy_block", "cnae_section")
)

log_info(sprintf("32c | denominator=%s | sector_var=%s", DENOMINATOR, SECTOR_VAR))

# ---- Mayor election calendar (matches script 33 mayor rows) ------------------
# For year t in 2002..2017, cycle = smallest c in {2005, 2009, 2013, 2017}
# with c > t (years >2016 map to 2017). bl_start/bl_end = [e(t)-4, e(t)-1].

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

# ---- Input preconditions -----------------------------------------------------

recon_fst <- output_path("rais_bndes_reconstructed.fst")
recon_qs2 <- output_path("rais_bndes_reconstructed.qs2")
pb_map_path <- output_path("policy_block_mapping.qs2")

stopifnot(
  "rais_bndes_reconstructed.{fst,qs2} must exist (script 22)" =
    file.exists(recon_fst) || file.exists(recon_qs2)
)
if (SECTOR_VAR == "policy_block") {
  stopifnot(
    "policy_block_mapping.qs2 must exist (script 30e)" = file.exists(pb_map_path)
  )
}

# ---- Load RAIS panel ---------------------------------------------------------

# We always need cnae_section to merge to policy_block; load that even when
# SECTOR_VAR == "policy_block".
need_cols <- c("firm_id", "muni_id", "year", "n_employees", "in_rais", "cnae_section")

log_info("loading RAIS panel...")
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

log_info(sprintf("loaded %s rows", format(nrow(panel), big.mark = ",")))

# Restrict to RAIS-covered firms (D1 universe).
panel <- panel[in_rais == TRUE]
panel[, in_rais := NULL]

# Hygiene.
panel[, muni_id := as.integer(muni_id)]
panel[, year    := as.integer(year)]
panel[, n_employees := as.numeric(n_employees)]
panel <- panel[!is.na(muni_id) & muni_id > 0L]
panel <- panel[!is.na(cnae_section)]

# Phase 0 A0.2 invariant: every RAIS row has n_employees >= 1.
stopifnot("RAIS panel contains n_employees < 1 -- Negativa pre-strip invariant violated" =
            panel[, min(n_employees, na.rm = TRUE)] >= 1)

# Merge policy_block crosswalk if needed.
if (SECTOR_VAR == "policy_block") {
  pb_map <- qs_read(pb_map_path)
  setDT(pb_map)
  stopifnot(all(c("cnae_section", "policy_block") %in% names(pb_map)))
  panel <- merge(panel, pb_map[, .(cnae_section, policy_block)],
                 by = "cnae_section", all.x = TRUE)
  panel <- panel[!is.na(policy_block)]
  # Drop residual block "XX" from the panel (K, O, T, U per script 30e).
  panel <- panel[policy_block != "XX"]
}

# Cycle assignment / windows.
panel[, cycle := assign_cycle(year)]
panel <- merge(panel, CYCLE_WINDOWS, by = "cycle", all.x = TRUE)
panel[, in_window := year >= bl_start & year <= bl_end]

# ---- Variant firm-set masks --------------------------------------------------

log_info(sprintf("computing variant firm sets for denominator='%s'...", DENOMINATOR))

if (DENOMINATOR == "contemporaneous") {
  panel[, keep := TRUE]
} else {
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
      keep_firms <- firm_year_set[year %in% pre$years, unique(firm_id)]
    } else {
      post <- build_cycle_set(CYCLE_WINDOWS$post_start[i], CYCLE_WINDOWS$post_end[i])
      pre_counts  <- firm_year_set[year %in% pre$years,
                                   .(n = uniqueN(year)), by = firm_id]
      post_counts <- firm_year_set[year %in% post$years,
                                   .(n = uniqueN(year)), by = firm_id]
      pre_firms   <- pre_counts[n == pre$required, firm_id]
      post_firms  <- post_counts[n == post$required, firm_id]
      keep_firms  <- intersect(pre_firms, post_firms)
    }
    variant_keep_list[[i]] <- data.table(firm_id = keep_firms, cycle = cyc, keep = TRUE)
    log_info(sprintf("  cycle %d (%s): %s firms in keep set",
                     cyc, DENOMINATOR, format(length(keep_firms), big.mark = ",")))
  }
  variant_keep <- rbindlist(variant_keep_list, use.names = TRUE)
  panel <- merge(panel, variant_keep, by = c("firm_id", "cycle"), all.x = TRUE)
  panel[is.na(keep), keep := FALSE]
  rm(firm_year_set, variant_keep_list, variant_keep); invisible(gc())
}

# ---- Frozen firm-set for slack control (independent of DENOMINATOR) ----------
# Per BHJ §4.4: per-cell incomplete-shares slack = share of contemporaneous
# n_mt accounted for by the cycle's frozen baseline firm set.

log_info("computing frozen firm sets for slack control...")
fy_set <- unique(panel[, .(firm_id, year)])
frozen_keep_list <- vector("list", nrow(CYCLE_WINDOWS))
for (i in seq_len(nrow(CYCLE_WINDOWS))) {
  cyc <- CYCLE_WINDOWS$cycle[i]
  pre_years <- intersect(seq.int(CYCLE_WINDOWS$bl_start[i],
                                 CYCLE_WINDOWS$bl_end[i]),
                         2002L:2017L)
  keep_firms <- fy_set[year %in% pre_years, unique(firm_id)]
  frozen_keep_list[[i]] <- data.table(firm_id = keep_firms, cycle = cyc, frozen = TRUE)
}
frozen_keep <- rbindlist(frozen_keep_list, use.names = TRUE)
panel <- merge(panel, frozen_keep, by = c("firm_id", "cycle"), all.x = TRUE)
panel[is.na(frozen), frozen := FALSE]
rm(fy_set, frozen_keep_list, frozen_keep); invisible(gc())

# ---- Aggregate to (muni, sector, year) ---------------------------------------

log_info("aggregating to (m, j, t) cells...")

# Skeleton: contemporaneous cell existence per D2.
skeleton <- unique(panel[, .(muni_id, sector_j = get(SECTOR_VAR), year)])

# n_jmt under the chosen variant's firm set.
cells_var <- panel[keep == TRUE,
                   .(n_jmt = sum(n_employees, na.rm = TRUE)),
                   by = .(muni_id, sector_j = get(SECTOR_VAR), year)]

# Contemporaneous n_jmt at the cell (for slack denominator).
cells_all <- panel[,
                   .(n_jmt_contemp = sum(n_employees, na.rm = TRUE)),
                   by = .(muni_id, sector_j = get(SECTOR_VAR), year)]

# Frozen-firm n_jmt at the cell (for slack numerator).
cells_frozen <- panel[frozen == TRUE,
                      .(n_jmt_frozen = sum(n_employees, na.rm = TRUE)),
                      by = .(muni_id, sector_j = get(SECTOR_VAR), year)]

cells <- merge(skeleton, cells_var,    by = c("muni_id", "sector_j", "year"), all.x = TRUE)
cells <- merge(cells,   cells_all,     by = c("muni_id", "sector_j", "year"), all.x = TRUE)
cells <- merge(cells,   cells_frozen,  by = c("muni_id", "sector_j", "year"), all.x = TRUE)
cells[is.na(n_jmt),         n_jmt         := 0]
cells[is.na(n_jmt_contemp), n_jmt_contemp := 0]
cells[is.na(n_jmt_frozen),  n_jmt_frozen  := 0]

# Cycle / window flags at year level.
cells[, cycle := assign_cycle(year)]
cells <- merge(cells, CYCLE_WINDOWS[, .(cycle, bl_start, bl_end)],
               by = "cycle", all.x = TRUE)
cells[, in_window := year >= bl_start & year <= bl_end]
cells[, c("bl_start", "bl_end") := NULL]

# Muni totals.
muni_totals <- cells[, .(
  n_mt          = sum(n_jmt),
  n_mt_contemp  = sum(n_jmt_contemp),
  n_mt_frozen   = sum(n_jmt_frozen)
), by = .(muni_id, year)]

cells <- merge(cells, muni_totals, by = c("muni_id", "year"), all.x = TRUE)

# ---- Drop muni-years with n_mt == 0 + 5% sanity gate -------------------------

all_muni_years <- nrow(unique(cells[, .(muni_id, year)]))
drop_muni_years <- nrow(unique(cells[n_mt == 0, .(muni_id, year)]))
drop_share <- if (all_muni_years > 0L) drop_muni_years / all_muni_years else 0
log_info(sprintf("muni-years dropped (n_mt == 0): %d / %d (%.4f%%)",
                 drop_muni_years, all_muni_years, 100 * drop_share))

if (drop_share > 0.05) {
  stop(sprintf(
    "Sanity gate failed: dropped muni-year share %.4f%% exceeds 5%% threshold at sector_var=%s, denominator=%s. Aborts to preserve D2 validity.",
    100 * drop_share, SECTOR_VAR, DENOMINATOR
  ))
}

cells <- cells[n_mt > 0]

# ---- Shares + deltas ---------------------------------------------------------

cells[, s_emp_mjt := n_jmt / n_mt]

# slack_frozen_mt: share of contemporaneous n_mt accounted for by the cycle's
# frozen baseline firm set. Defined at (muni, year). For the contemporaneous
# variant this is the BHJ §4.4 incomplete-shares control.
cells[, slack_frozen_mt := fifelse(n_mt_contemp > 0, n_mt_frozen / n_mt_contemp, NA_real_)]

# delta s within (muni, sector).
setorder(cells, muni_id, sector_j, year)
cells[, delta_s_emp_mjt := s_emp_mjt - shift(s_emp_mjt, type = "lag"),
      by = .(muni_id, sector_j)]

# Rename sector_j -> SECTOR_VAR (final schema).
setnames(cells, "sector_j", SECTOR_VAR)

# ---- Sanity gates ------------------------------------------------------------

stopifnot(
  "s_emp_mjt must lie in [0, 1]"     = cells[, all(s_emp_mjt >= 0 & s_emp_mjt <= 1)],
  "delta_s_emp_mjt out of [-1, 1]"   = cells[!is.na(delta_s_emp_mjt),
                                             all(delta_s_emp_mjt >= -1 & delta_s_emp_mjt <= 1)],
  "slack_frozen_mt has NA values"    = cells[, !anyNA(slack_frozen_mt)],
  "slack_frozen_mt out of [0, 1]"    = cells[, all(slack_frozen_mt >= 0 & slack_frozen_mt <= 1.0 + 1e-12)]
)

# ---- Diagnostics -------------------------------------------------------------

n_rows         <- nrow(cells)
n_muni_year    <- uniqueN(cells[, .(muni_id, year)])
n_muni         <- uniqueN(cells$muni_id)
J              <- uniqueN(cells[[SECTOR_VAR]])

share_stats <- cells[, .(min = min(s_emp_mjt), median = median(s_emp_mjt),
                         mean = mean(s_emp_mjt), max = max(s_emp_mjt))]

slack_per_muni_year <- unique(cells[, .(muni_id, year, slack_frozen_mt)])
slack_stats <- slack_per_muni_year[, .(
  min          = min(slack_frozen_mt),
  mean         = mean(slack_frozen_mt),
  median       = as.numeric(median(slack_frozen_mt)),
  max          = max(slack_frozen_mt),
  share_lt_099 = mean(slack_frozen_mt < 0.99),
  share_lt_095 = mean(slack_frozen_mt < 0.95),
  n_muni_year  = .N
)]

log_info(sprintf("panel rows: %s | muni-years: %s | munis: %d | sectors (J): %d",
                 format(n_rows, big.mark = ","),
                 format(n_muni_year, big.mark = ","),
                 n_muni, J))
log_info(sprintf("s_emp_mjt: min=%.4f median=%.4f mean=%.4f max=%.4f (expect mean ~ 1/J = %.4f)",
                 share_stats$min, share_stats$median, share_stats$mean,
                 share_stats$max, 1 / J))
log_info(sprintf("slack_frozen_mt: min=%.4f mean=%.4f median=%.4f max=%.4f | share<0.99=%.4f share<0.95=%.4f",
                 slack_stats$min, slack_stats$mean, slack_stats$median, slack_stats$max,
                 slack_stats$share_lt_099, slack_stats$share_lt_095))

# ---- Save --------------------------------------------------------------------

out_cols <- c("muni_id", SECTOR_VAR, "year",
              "n_jmt", "n_mt", "s_emp_mjt", "delta_s_emp_mjt",
              "slack_frozen_mt", "cycle", "in_window")
cells_out <- cells[, ..out_cols]

out_panel_path   <- output_path(sprintf("emp_share_panel_%s.qs2", SECTOR_VAR))
out_summary_path <- output_path(sprintf("emp_share_panel_%s_summary.csv", SECTOR_VAR))
out_slack_path   <- output_path(sprintf("emp_share_panel_%s_slack.csv", SECTOR_VAR))

qs_save(cells_out, out_panel_path)

summary_dt <- data.table(
  denominator             = DENOMINATOR,
  sector_var              = SECTOR_VAR,
  n_rows                  = n_rows,
  n_muni_year             = n_muni_year,
  n_muni                  = n_muni,
  n_sectors               = J,
  n_dropped_muni_years    = drop_muni_years,
  drop_share              = drop_share,
  s_min                   = share_stats$min,
  s_median                = share_stats$median,
  s_mean                  = share_stats$mean,
  s_max                   = share_stats$max,
  inv_J                   = 1 / J,
  slack_min               = slack_stats$min,
  slack_mean              = slack_stats$mean,
  slack_median            = slack_stats$median,
  slack_max               = slack_stats$max,
  slack_share_lt_0p99     = slack_stats$share_lt_099,
  slack_share_lt_0p95     = slack_stats$share_lt_095
)
fwrite(summary_dt, out_summary_path)
fwrite(slack_per_muni_year, out_slack_path)

log_info(sprintf("wrote: %s", out_panel_path))
log_info(sprintf("wrote: %s", out_summary_path))
log_info(sprintf("wrote: %s", out_slack_path))
log_info("32c done.")
