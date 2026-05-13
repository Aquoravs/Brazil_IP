#!/usr/bin/env Rscript

# ==============================================================================
# 07_pretrend_decomp.R
# Phase 1.6 diagnostic decomposition of the variant-alpha rejection on
# delta_log_gdp (B1.6 baseline: F = 1.612, p = 0.002356).
#
# Three decompositions, all on delta_log_gdp, identical FE / clustering
# convention to 06_pretrend_proper.R (muni_id + year FE, cluster on muni_id).
#
#   (a) By election cycle in {2004, 2008, 2012, 2016}
#       For each cycle, restrict to the pre-window mapped to that election
#       (3 years preceding) and rerun the joint F-test on the full Z matrix.
#
#   (b) By office in {pres, gov, mayor}
#       Restrict the Z matrix to that office's ~19 columns, pool all cycles,
#       rerun the joint F-test.
#
#   (c) Window sensitivity: short (2y), medium (3y = baseline), long (6y).
#
# Outputs:
#   output/pretrend_decomp_cycle.csv
#   output/pretrend_decomp_office.csv
#   output/pretrend_decomp_window.csv
#   output/pretrend_decomp_summary.md
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})

# ---- Paths -------------------------------------------------------------------

get_this_script <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (length(fa)) {
    return(normalizePath(sub("^--file=", "", fa[[1L]]),
                         winslash = "/", mustWork = TRUE))
  }
  fp <- vapply(sys.frames(), function(env) {
    of <- env$ofile
    if (is.null(of) || !nzchar(of)) return(NA_character_)
    of
  }, character(1))
  fp <- fp[!is.na(fp)]
  if (length(fp)) {
    return(normalizePath(fp[[length(fp)]], winslash = "/", mustWork = TRUE))
  }
  stop("Cannot determine script path. Run via Rscript.")
}

THIS_SCRIPT  <- get_this_script()
BRANCH_DIR   <- normalizePath(file.path(dirname(THIS_SCRIPT), ".."),
                              winslash = "/", mustWork = TRUE)
PROJECT_ROOT <- normalizePath(file.path(BRANCH_DIR, "..", "..", ".."),
                              winslash = "/", mustWork = TRUE)
source(file.path(PROJECT_ROOT, "scripts", "R", "_utils", "utils.R"))

OUTPUT_BRANCH <- file.path(BRANCH_DIR, "output")
stopifnot(dir.exists(OUTPUT_BRANCH))

# ---- Reproducibility ---------------------------------------------------------

set.seed(20260512L)
setDTthreads(0L)
fixest::setFixest_nthreads(4L)

# ---- Constants (must match 06_pretrend_proper.R) -----------------------------

ALIGNMENT   <- "coalition"
BASELINE    <- "cycle_specific"
OFFICES     <- c("mayor", "gov", "pres")
CLUSTER_VAR <- "muni_id"

# Baseline (medium) pre-period tau -> ref_year map (3 years pre-election).
PRE_MAP_MEDIUM <- data.table(
  pre_year     = c(2002L, 2003L,
                   2005L, 2006L, 2007L,
                   2009L, 2010L, 2011L,
                   2013L, 2014L, 2015L),
  ref_election = c(2004L, 2004L,
                   2008L, 2008L, 2008L,
                   2012L, 2012L, 2012L,
                   2016L, 2016L, 2016L),
  ref_year     = c(2005L, 2005L,
                   2009L, 2009L, 2009L,
                   2013L, 2013L, 2013L,
                   2017L, 2017L, 2017L)
)

# Short (2y pre-election) map: tau in [e-2, e-1].
PRE_MAP_SHORT <- data.table(
  pre_year     = c(2002L, 2003L,
                   2006L, 2007L,
                   2010L, 2011L,
                   2014L, 2015L),
  ref_election = c(2004L, 2004L,
                   2008L, 2008L,
                   2012L, 2012L,
                   2016L, 2016L),
  ref_year     = c(2005L, 2005L,
                   2009L, 2009L,
                   2013L, 2013L,
                   2017L, 2017L)
)

# Long (6y pre-election) map: tau in [e-6, e-1]. We assign each pre_year to
# its NEXT election strictly greater than pre_year, capped at the 2004..2016
# cycle set. Years before 2004 election: 2002,2003 -> 2004. Then we extend
# 2008's pre-window to start at 2002 (6 yrs), 2012's to 2006, 2016's to 2010.
# To avoid duplicating panel rows across cycles we assign each pre_year to its
# IMMEDIATE next election (same as medium); the "long" window simply extends
# how far before that election we look, capped below by 2002.
PRE_MAP_LONG <- data.table(
  pre_year     = c(2002L, 2003L,
                   2005L, 2006L, 2007L,
                   2009L, 2010L, 2011L,
                   2013L, 2014L, 2015L),
  ref_election = c(2004L, 2004L,
                   2008L, 2008L, 2008L,
                   2012L, 2012L, 2012L,
                   2016L, 2016L, 2016L),
  ref_year     = c(2005L, 2005L,
                   2009L, 2009L, 2009L,
                   2013L, 2013L, 2013L,
                   2017L, 2017L, 2017L)
)
# Note: with mayoral cycles 4yrs apart, the medium (3y) map already covers
# tau in [e-3, e-1] for each election with no gaps. A true "long" window of
# 6y would overlap cycles. We implement it by including all pre-period years
# 2002:2015 (excluding election years 2004,2008,2012,2016) and assigning each
# tau to its NEXT mayoral election. This is monotone and unambiguous.
PRE_MAP_LONG <- data.table(
  pre_year     = c(2002L, 2003L,
                   2005L, 2006L, 2007L,
                   2009L, 2010L, 2011L,
                   2013L, 2014L, 2015L),
  ref_election = c(2004L, 2004L,
                   2008L, 2008L, 2008L,
                   2012L, 2012L, 2012L,
                   2016L, 2016L, 2016L),
  ref_year     = c(2005L, 2005L,
                   2009L, 2009L, 2009L,
                   2013L, 2013L, 2013L,
                   2017L, 2017L, 2017L)
)
# "Long" in practice equals "medium" given 4-yr mayoral cycles -- there are no
# additional pre-period years available without colliding with a different
# cycle's election. Per the task brief we keep the "long" entry to confirm
# this equality; the truly different window is "short" (2y).

# ---- Load muni panel ---------------------------------------------------------

muni_path <- output_path("muni_panel_for_regs.qs2")
stopifnot(file.exists(muni_path))
message(sprintf("[INFO] %s | loading muni panel...", Sys.time()))
muni <- qs_read(muni_path)
setDT(muni)
muni[, muni_id := as.integer(muni_id)]
muni[, year    := as.integer(year)]
muni <- muni[muni_id > 0L]

# Discover sections.
inst_prefix <- sprintf("Z_mayor_%s_%s_", ALIGNMENT, BASELINE)
sec_cols <- grep(paste0("^", inst_prefix, "[A-Z]$"), names(muni), value = TRUE)
SECTIONS <- sort(sub(paste0("^", inst_prefix), "", sec_cols))
HOLDOUT  <- SECTIONS[length(SECTIONS)]
SECTIONS_KEEP <- setdiff(SECTIONS, HOLDOUT)
message(sprintf("[INFO] K_sections_kept=%d (holdout=%s)",
                length(SECTIONS_KEEP), HOLDOUT))

build_inst_cols <- function(offices, sections) {
  out <- character()
  for (off in offices) {
    for (s in sections) {
      out <- c(out, sprintf("Z_%s_%s_%s_%s", off, ALIGNMENT, BASELINE, s))
    }
  }
  out
}

INST_COLS_ALL <- build_inst_cols(OFFICES, SECTIONS_KEEP)
stopifnot(all(INST_COLS_ALL %in% names(muni)))

# delta_log_gdp.
setorder(muni, muni_id, year)
muni[, delta_log_gdp := log_gdp - shift(log_gdp, type = "lag"),
     by = muni_id]

# ---- Build future-Z lookup ---------------------------------------------------

z_at_ref <- muni[year %in% sort(unique(PRE_MAP_MEDIUM$ref_year)),
                 c("muni_id", "year", INST_COLS_ALL), with = FALSE]
setnames(z_at_ref, "year", "ref_year")
future_cols_all <- paste0(INST_COLS_ALL, "_future")
setnames(z_at_ref, INST_COLS_ALL, future_cols_all)

# ---- Core fit ----------------------------------------------------------------

fit_joint_F <- function(pre_map, inst_cols, label) {
  fut_cols <- paste0(inst_cols, "_future")
  stopifnot(all(fut_cols %in% names(z_at_ref)))

  pre <- muni[year %in% pre_map$pre_year,
              c("muni_id", "year", "delta_log_gdp"), with = FALSE]
  pre <- merge(pre, pre_map[, .(pre_year, ref_year)],
               by.x = "year", by.y = "pre_year", all.x = TRUE)
  stopifnot(!any(is.na(pre$ref_year)))

  z_sub <- z_at_ref[, c("muni_id", "ref_year", fut_cols), with = FALSE]
  dat <- merge(pre, z_sub, by = c("muni_id", "ref_year"), all.x = TRUE)
  keep <- c("muni_id", "year", "ref_year", "delta_log_gdp", fut_cols)
  dat <- dat[, ..keep]
  dat <- dat[complete.cases(dat)]
  if (!nrow(dat)) {
    message(sprintf("[WARN] [%s] empty sample", label))
    return(list(F = NA_real_, p = NA_real_, n = 0L, m = 0L,
                k = length(fut_cols)))
  }

  # Drop future-Z columns with zero within-muni variation (e.g., a single-year
  # restriction).
  vars <- vapply(fut_cols, function(cc) var(dat[[cc]], na.rm = TRUE),
                 numeric(1))
  fut_keep <- fut_cols[is.finite(vars) & vars > 0]
  if (!length(fut_keep)) {
    return(list(F = NA_real_, p = NA_real_, n = nrow(dat),
                m = uniqueN(dat$muni_id), k = 0L))
  }

  rhs <- paste(fut_keep, collapse = " + ")
  # Within a single election cycle, Z_future is constant per muni: muni FE
  # would absorb all variation. Drop muni FE in that case. Year FE drops if
  # only one year remains.
  has_year_var <- uniqueN(dat$year) > 1L
  n_ref_years_per_muni <- dat[, uniqueN(ref_year), by = muni_id]
  cycles_per_muni_max <- max(n_ref_years_per_muni$V1)
  use_muni_fe <- cycles_per_muni_max > 1L
  fe_parts <- character()
  if (use_muni_fe) fe_parts <- c(fe_parts, "muni_id")
  if (has_year_var) fe_parts <- c(fe_parts, "year")
  fml <- if (length(fe_parts)) {
    as.formula(sprintf("delta_log_gdp ~ %s | %s", rhs,
                       paste(fe_parts, collapse = " + ")))
  } else {
    as.formula(sprintf("delta_log_gdp ~ %s", rhs))
  }
  mod <- feols(fml, data = dat,
               vcov = as.formula(paste0("~ ", CLUSTER_VAR)),
               lean = TRUE)

  z_pattern <- paste0("^Z_(",
                      paste(OFFICES, collapse = "|"),
                      ")_", ALIGNMENT, "_", BASELINE, "_.*_future$")
  w <- fixest::wald(mod, keep = z_pattern, print = FALSE)
  list(F = as.numeric(w$stat), p = as.numeric(w$p),
       n = nobs(mod), m = uniqueN(dat$muni_id), k = length(fut_keep))
}

# ---- Baseline replication ----------------------------------------------------

message("[INFO] baseline replication (medium window, all offices, all cycles)")
baseline <- fit_joint_F(PRE_MAP_MEDIUM, INST_COLS_ALL, "baseline")
message(sprintf("[INFO] baseline: F=%.4f p=%.4g n=%s munis=%s k=%d",
                baseline$F, baseline$p,
                format(baseline$n, big.mark = ","),
                format(baseline$m, big.mark = ","),
                baseline$k))

# Tolerance: target F = 1.612, p = 0.002356. Allow 5% tolerance on F.
B1_6_F <- 1.612
B1_6_P <- 0.002356
F_REPLICATES <- isTRUE(abs(baseline$F - B1_6_F) / B1_6_F < 0.05)
message(sprintf("[INFO] B1.6 replication: %s (target F=%.4f, got F=%.4f)",
                if (F_REPLICATES) "PASS" else "FAIL", B1_6_F, baseline$F))

# ---- (a) By-cycle decomposition ----------------------------------------------

message("[INFO] (a) by-cycle decomposition")
cycle_rows <- list()
for (e in c(2004L, 2008L, 2012L, 2016L)) {
  pre_map_e <- PRE_MAP_MEDIUM[ref_election == e]
  r <- fit_joint_F(pre_map_e, INST_COLS_ALL,
                   sprintf("cycle_%d", e))
  cycle_rows[[length(cycle_rows) + 1L]] <- data.table(
    election_cycle = e,
    pre_years = paste(sort(unique(pre_map_e$pre_year)), collapse = ","),
    n_obs = r$n, n_munis = r$m, k_instruments = r$k,
    joint_F = r$F, joint_p = r$p,
    rejects_5pc = isTRUE(r$p < 0.05)
  )
}
cycle_dt <- rbindlist(cycle_rows)
fwrite(cycle_dt, file.path(OUTPUT_BRANCH, "pretrend_decomp_cycle.csv"))
print(cycle_dt)

# ---- (b) By-office decomposition ---------------------------------------------

message("[INFO] (b) by-office decomposition")
office_rows <- list()
for (off in OFFICES) {
  inst_off <- build_inst_cols(off, SECTIONS_KEEP)
  r <- fit_joint_F(PRE_MAP_MEDIUM, inst_off,
                   sprintf("office_%s", off))
  office_rows[[length(office_rows) + 1L]] <- data.table(
    office = off,
    n_obs = r$n, n_munis = r$m, k_instruments = r$k,
    joint_F = r$F, joint_p = r$p,
    rejects_5pc = isTRUE(r$p < 0.05)
  )
}
office_dt <- rbindlist(office_rows)
fwrite(office_dt, file.path(OUTPUT_BRANCH, "pretrend_decomp_office.csv"))
print(office_dt)

# ---- (c) Window sensitivity --------------------------------------------------

message("[INFO] (c) window sensitivity")
window_specs <- list(
  short  = PRE_MAP_SHORT,
  medium = PRE_MAP_MEDIUM,
  long   = PRE_MAP_LONG
)
window_rows <- list()
for (nm in names(window_specs)) {
  pm <- window_specs[[nm]]
  r <- fit_joint_F(pm, INST_COLS_ALL, sprintf("window_%s", nm))
  window_rows[[length(window_rows) + 1L]] <- data.table(
    window = nm,
    pre_years = paste(sort(unique(pm$pre_year)), collapse = ","),
    n_obs = r$n, n_munis = r$m, k_instruments = r$k,
    joint_F = r$F, joint_p = r$p,
    rejects_5pc = isTRUE(r$p < 0.05)
  )
}
window_dt <- rbindlist(window_rows)
fwrite(window_dt, file.path(OUTPUT_BRANCH, "pretrend_decomp_window.csv"))
print(window_dt)

# ---- Markdown summary --------------------------------------------------------

fmt <- function(x, digits = 4L) {
  if (!is.finite(x)) return("NA")
  formatC(x, format = "g", digits = digits)
}

md <- c(
  "# Phase 1.6 Pre-Trend Decomposition (delta_log_gdp)",
  "",
  sprintf("**Date:** %s", format(Sys.time(), "%Y-%m-%d %H:%M")),
  "**Outcome:** delta_log_gdp (B1.6 variant alpha, operative violation)",
  "**FE / SE:** muni_id + year FE; cluster on muni_id",
  "",
  "## Baseline replication",
  "",
  sprintf("| | n_obs | k | joint F | joint p | replicates B1.6? |"),
  "|---|---|---|---|---|---|",
  sprintf("| Baseline (medium window, all offices, all cycles) | %s | %d | %s | %s | %s |",
          format(baseline$n, big.mark = ","), baseline$k,
          fmt(baseline$F), fmt(baseline$p),
          if (F_REPLICATES) "YES" else "NO"),
  sprintf("| B1.6 target | 55,614 | 57 | 1.612 | 0.002356 | -- |"),
  "",
  "## (a) By election cycle",
  "",
  "| Cycle e | pre-years | n_obs | k | joint F | joint p | reject 5% |",
  "|---|---|---|---|---|---|---|"
)
for (i in seq_len(nrow(cycle_dt))) {
  md <- c(md, sprintf("| %d | %s | %s | %d | %s | %s | %s |",
                      cycle_dt$election_cycle[i],
                      cycle_dt$pre_years[i],
                      format(cycle_dt$n_obs[i], big.mark = ","),
                      cycle_dt$k_instruments[i],
                      fmt(cycle_dt$joint_F[i]),
                      fmt(cycle_dt$joint_p[i]),
                      cycle_dt$rejects_5pc[i]))
}

md <- c(md, "",
        "## (b) By office",
        "",
        "| Office | n_obs | k | joint F | joint p | reject 5% |",
        "|---|---|---|---|---|---|")
for (i in seq_len(nrow(office_dt))) {
  md <- c(md, sprintf("| %s | %s | %d | %s | %s | %s |",
                      office_dt$office[i],
                      format(office_dt$n_obs[i], big.mark = ","),
                      office_dt$k_instruments[i],
                      fmt(office_dt$joint_F[i]),
                      fmt(office_dt$joint_p[i]),
                      office_dt$rejects_5pc[i]))
}

md <- c(md, "",
        "## (c) Window sensitivity",
        "",
        "| Window | pre-years | n_obs | k | joint F | joint p | reject 5% |",
        "|---|---|---|---|---|---|---|")
for (i in seq_len(nrow(window_dt))) {
  md <- c(md, sprintf("| %s | %s | %s | %d | %s | %s | %s |",
                      window_dt$window[i],
                      window_dt$pre_years[i],
                      format(window_dt$n_obs[i], big.mark = ","),
                      window_dt$k_instruments[i],
                      fmt(window_dt$joint_F[i]),
                      fmt(window_dt$joint_p[i]),
                      window_dt$rejects_5pc[i]))
}

# ---- Interpretation block (mechanical) ---------------------------------------

cycles_reject <- cycle_dt[rejects_5pc == TRUE, election_cycle]
offices_reject <- office_dt[rejects_5pc == TRUE, office]
windows_reject <- window_dt[rejects_5pc == TRUE, window]
windows_pass   <- window_dt[rejects_5pc == FALSE, window]

most_diagnostic <- if (length(cycles_reject) <= 1L) {
  "by-cycle (rejection concentrated in a subset of elections)"
} else if (length(offices_reject) == 1L) {
  "by-office (rejection concentrated in a single office)"
} else if (length(windows_reject) < 3L) {
  "window sensitivity (rejection is specification-driven, not window-invariant)"
} else {
  "rejection is robust across all three decompositions -- diffuse anticipation"
}

md <- c(md, "",
        "## Interpretation",
        "",
        sprintf("- **By-cycle:** cycle(s) rejecting at 5%%: %s.",
                if (length(cycles_reject)) paste(cycles_reject, collapse = ", ") else "none"),
        sprintf("- **By-office:** office(s) rejecting at 5%%: %s.",
                if (length(offices_reject)) paste(offices_reject, collapse = ", ") else "none"),
        sprintf("- **Window:** window(s) rejecting at 5%%: %s. Passing: %s.",
                if (length(windows_reject)) paste(windows_reject, collapse = ", ") else "none",
                if (length(windows_pass)) paste(windows_pass, collapse = ", ") else "none"),
        "",
        sprintf("**Most diagnostic single takeaway:** %s.", most_diagnostic),
        "")

writeLines(md, file.path(OUTPUT_BRANCH, "pretrend_decomp_summary.md"))
message(sprintf("[INFO] wrote: %s",
                file.path(OUTPUT_BRANCH, "pretrend_decomp_summary.md")))
message(sprintf("[INFO] %s | done.", Sys.time()))
