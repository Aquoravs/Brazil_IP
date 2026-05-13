#!/usr/bin/env Rscript

# ==============================================================================
# 08_gov_pretrend_deep_dive.R
# Phase 1.7 -- governor-instrument pre-trend deep-dive.
#
# Context. Phase 1.6 (06_pretrend_proper.R / 07_pretrend_decomp.R) found that
# variant-alpha rejects on Delta log_gdp (F = 1.612, p = 0.002356) and that the
# rejection is driven by the GOVERNOR Z columns (office decomp: gov F = 2.47,
# p = 4e-4; mayor p = 0.79; pres p = 0.065). Variant-beta separately flagged
# Pres x E and Pres x P as sector-share pre-trend violators (07_ar_drop_violators.R
# shows dropping Pres x E + Pres x P improves AR fs_F and preserves rejection).
#
# B1.7 has three sequential tests:
#
#   B1.7.1  alpha-clearance test: re-run variant-alpha on Delta log_gdp with the
#           full Z matrix MINUS {Z_pres_coalition_cycle_specific_E,
#           Z_pres_coalition_cycle_specific_P}. If joint p > 0.05, alpha clears
#           and the story is "the beta violators were also the alpha violators";
#           halt at B1.7.1.
#
#   B1.7.2  If B1.7.1 still rejects, redo the by-office decomposition on the
#           cleaned Z (Pres-block with E+P excluded; Gov-block full; Mayor-block
#           full). Confirms whether Gov is still the driver.
#
#   B1.7.3  Conditional on B1.7.2 confirming Gov, two Gov-specific diagnostics:
#       (alpha) Gov-cycle interaction. Regress Delta log_gdp on Gov-Z columns
#               interacted with election-cycle dummies. Test whether the gov
#               pre-trend is cycle-specific (single bad election) or persistent.
#       (beta)  Descriptive contamination check at the state x cycle level.
#               For each (state, gov-cycle), compute mean Gov-Z and mean
#               state-level pre-period Delta log_gdp, then tabulate the
#               correlation across cycles.
#
# Caveats.
#   - State-fiscal data (e.g., FINBRA aggregates) are NOT on disk. The
#     budget-cycle / reverse-causation channel cannot be tested directly;
#     B1.7.3.beta provides only descriptive evidence.
#   - Brazilian gubernatorial elections: 2002, 2006, 2010, 2014, 2018.
#     The muni panel covers 2002-2017, so 2018 has no post-period Z in our
#     panel; the gov-cycle alignment in the instrument build follows the
#     mayoral cycle convention (cycle_specific baseline at the mayoral election
#     year). We use the mayoral cycle indexing here for consistency with the
#     variant-alpha pre-period mapping in 06/07; gov elections that fall mid-
#     mayoral-cycle are absorbed inside the cycle Z value.
#
# Inputs:
#   data/processed/muni_panel_for_regs.qs2 (built by script 41)
#
# Outputs:
#   output/pretrend_alpha_drop_PresEP.csv          (B1.7.1)
#   output/pretrend_office_decomp_cleaned.csv      (B1.7.2)
#   output/gov_cycle_interaction.csv               (B1.7.3.alpha)
#   output/gov_contamination_descriptive.csv       (B1.7.3.beta)
#   output/pretrend_b17_summary.md
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

# ---- Constants ---------------------------------------------------------------

ALIGNMENT   <- "coalition"
BASELINE    <- "cycle_specific"
OFFICES     <- c("mayor", "gov", "pres")
CLUSTER_VAR <- "muni_id"

# Pre-period tau -> ref_year (3y pre-mayoral-cycle window, matches B1.6).
PRE_MAP <- data.table(
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

# Excluded Pres columns (per B1.6 variant-beta + 07_ar_drop_violators).
PRES_DROP_SECTIONS <- c("E", "P")

# ---- Load muni panel ---------------------------------------------------------

muni_path <- output_path("muni_panel_for_regs.qs2")
stopifnot(file.exists(muni_path))
message(sprintf("[INFO] %s | loading muni panel...", Sys.time()))
muni <- qs_read(muni_path)
setDT(muni)
muni[, muni_id := as.integer(muni_id)]
muni[, year    := as.integer(year)]
muni <- muni[muni_id > 0L]
stopifnot("state_id" %in% names(muni))

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

# Cleaned set: drop Pres x E and Pres x P.
PRES_DROP_COLS <- sprintf("Z_pres_%s_%s_%s", ALIGNMENT, BASELINE,
                          PRES_DROP_SECTIONS)
stopifnot(all(PRES_DROP_COLS %in% INST_COLS_ALL))
INST_COLS_CLEANED <- setdiff(INST_COLS_ALL, PRES_DROP_COLS)
message(sprintf("[INFO] dropped %d Pres columns: %s",
                length(PRES_DROP_COLS),
                paste(PRES_DROP_COLS, collapse = ", ")))

# delta_log_gdp.
setorder(muni, muni_id, year)
muni[, delta_log_gdp := log_gdp - shift(log_gdp, type = "lag"),
     by = muni_id]

# ---- Build future-Z lookup ---------------------------------------------------

z_at_ref <- muni[year %in% sort(unique(PRE_MAP$ref_year)),
                 c("muni_id", "year", INST_COLS_ALL), with = FALSE]
setnames(z_at_ref, "year", "ref_year")
future_cols_all <- paste0(INST_COLS_ALL, "_future")
setnames(z_at_ref, INST_COLS_ALL, future_cols_all)

# ---- Core fit ---------------------------------------------------------------

fit_joint_F <- function(inst_cols, label) {
  fut_cols <- paste0(inst_cols, "_future")
  stopifnot(all(fut_cols %in% names(z_at_ref)))

  pre <- muni[year %in% PRE_MAP$pre_year,
              c("muni_id", "year", "delta_log_gdp"), with = FALSE]
  pre <- merge(pre, PRE_MAP[, .(pre_year, ref_year)],
               by.x = "year", by.y = "pre_year", all.x = TRUE)
  stopifnot(!any(is.na(pre$ref_year)))

  z_sub <- z_at_ref[, c("muni_id", "ref_year", fut_cols), with = FALSE]
  dat <- merge(pre, z_sub, by = c("muni_id", "ref_year"), all.x = TRUE)
  keep <- c("muni_id", "year", "ref_year", "delta_log_gdp", fut_cols)
  dat <- dat[, ..keep]
  dat <- dat[complete.cases(dat)]

  vars <- vapply(fut_cols, function(cc) var(dat[[cc]], na.rm = TRUE),
                 numeric(1))
  fut_keep <- fut_cols[is.finite(vars) & vars > 0]

  rhs <- paste(fut_keep, collapse = " + ")
  fml <- as.formula(sprintf("delta_log_gdp ~ %s | muni_id + year", rhs))
  mod <- feols(fml, data = dat,
               vcov = as.formula(paste0("~ ", CLUSTER_VAR)),
               lean = TRUE)

  z_pattern <- paste0("^Z_(",
                      paste(OFFICES, collapse = "|"),
                      ")_", ALIGNMENT, "_", BASELINE, "_.*_future$")
  w <- fixest::wald(mod, keep = z_pattern, print = FALSE)
  message(sprintf("[INFO] [%s] n=%s munis=%s k=%d F=%.4f p=%.4g",
                  label,
                  format(nobs(mod), big.mark = ","),
                  format(uniqueN(dat$muni_id), big.mark = ","),
                  length(fut_keep),
                  as.numeric(w$stat), as.numeric(w$p)))
  list(F = as.numeric(w$stat), p = as.numeric(w$p),
       n = nobs(mod), m = uniqueN(dat$muni_id),
       k = length(fut_keep), model = mod)
}

# =============================================================================
# B1.7.1 -- alpha-clearance after dropping Pres x E + Pres x P
# =============================================================================

message("[INFO] === B1.7.1: alpha-clearance after dropping Pres x E + Pres x P ===")
b171 <- fit_joint_F(INST_COLS_CLEANED, "B1.7.1_cleaned")

b171_dt <- data.table(
  test          = "B1.7.1_alpha_drop_PresEP",
  outcome       = "delta_log_gdp",
  z_set         = "all_offices_minus_PresE_PresP",
  n_obs         = b171$n,
  n_munis       = b171$m,
  k_instruments = b171$k,
  joint_F       = b171$F,
  joint_p       = b171$p,
  rejects_5pc   = isTRUE(b171$p < 0.05),
  alpha_cleared = isTRUE(b171$p > 0.05)
)
fwrite(b171_dt,
       file.path(OUTPUT_BRANCH, "pretrend_alpha_drop_PresEP.csv"))

alpha_cleared <- isTRUE(b171$p > 0.05)
message(sprintf("[INFO] B1.7.1 verdict: %s (p=%.4g)",
                if (alpha_cleared) "ALPHA CLEARS -- halt at B1.7.1"
                else "STILL REJECTS -- proceed to B1.7.2",
                b171$p))

# =============================================================================
# B1.7.2 -- by-office decomposition on cleaned Z
# =============================================================================

# Per task brief: always produce B1.7.2 output (informative even if B1.7.1
# cleared). The script's decision logic for B1.7.3 below depends on whether
# B1.7.1 cleared AND whether Gov drives the residual rejection.
message("[INFO] === B1.7.2: by-office decomposition on cleaned Z ===")

office_inst_cleaned <- list(
  pres  = setdiff(build_inst_cols("pres",  SECTIONS_KEEP), PRES_DROP_COLS),
  gov   = build_inst_cols("gov",   SECTIONS_KEEP),
  mayor = build_inst_cols("mayor", SECTIONS_KEEP)
)

office_rows <- list()
for (off in names(office_inst_cleaned)) {
  r <- fit_joint_F(office_inst_cleaned[[off]],
                   sprintf("B1.7.2_office_%s_cleaned", off))
  office_rows[[length(office_rows) + 1L]] <- data.table(
    test          = "B1.7.2_office_decomp_cleaned",
    office        = off,
    z_set         = if (off == "pres") "pres_minus_E_P" else "full",
    n_obs         = r$n,
    n_munis       = r$m,
    k_instruments = r$k,
    joint_F       = r$F,
    joint_p       = r$p,
    rejects_5pc   = isTRUE(r$p < 0.05)
  )
}
office_dt <- rbindlist(office_rows)
fwrite(office_dt, file.path(OUTPUT_BRANCH, "pretrend_office_decomp_cleaned.csv"))
print(office_dt)

gov_drives <- isTRUE(office_dt[office == "gov", rejects_5pc])
gov_only_driver <- gov_drives &&
  !isTRUE(office_dt[office == "pres",  rejects_5pc]) &&
  !isTRUE(office_dt[office == "mayor", rejects_5pc])
message(sprintf("[INFO] B1.7.2 verdict: gov_rejects=%s, gov_is_only_driver=%s",
                gov_drives, gov_only_driver))

# =============================================================================
# B1.7.3.alpha -- Gov-cycle interaction
# =============================================================================
# Goal: is the gov pre-trend cycle-specific (one bad election) or persistent?
# Implementation. For each pre-period observation, the mapped ref_election in
# {2004, 2008, 2012, 2016} indexes the mayoral cycle (the same indexing that
# governs how cycle_specific Z varies). Regress delta_log_gdp on Gov-Z columns
# fully interacted with ref_election dummies; muni + year FE; cluster muni.
# Joint F over: (i) per-cycle main effects (Gov-Z within each cycle subset),
# (ii) cycle x Gov-Z interaction terms vs a pooled-Gov-Z baseline.
#
# Operational shortcut. Run one regression per cycle, restricted to that
# cycle's pre-window, on Gov-Z columns alone. This already answers "is the
# rejection driven by one cycle?". Then run the pooled Gov-only regression
# and compare per-cycle F's to the pooled F. We avoid the explicit interaction
# specification because feols with K x C interacted columns and muni FE is
# unstable when Z is constant within muni x cycle (which it is by
# construction).

message("[INFO] === B1.7.3.alpha: gov-cycle interaction (per-cycle Gov-Z F) ===")

INST_COLS_GOV <- build_inst_cols("gov", SECTIONS_KEEP)
fut_cols_gov  <- paste0(INST_COLS_GOV, "_future")

# Pooled gov-only F (replicates 07_pretrend_decomp.R gov entry).
pooled_gov <- fit_joint_F(INST_COLS_GOV, "B1.7.3a_gov_pooled")

# Per-cycle gov-only F.
fit_gov_one_cycle <- function(e) {
  pre_e <- PRE_MAP[ref_election == e]
  pre <- muni[year %in% pre_e$pre_year,
              c("muni_id", "year", "delta_log_gdp"), with = FALSE]
  pre <- merge(pre, pre_e[, .(pre_year, ref_year)],
               by.x = "year", by.y = "pre_year", all.x = TRUE)
  z_sub <- z_at_ref[, c("muni_id", "ref_year", fut_cols_gov), with = FALSE]
  dat <- merge(pre, z_sub, by = c("muni_id", "ref_year"), all.x = TRUE)
  keep <- c("muni_id", "year", "delta_log_gdp", fut_cols_gov)
  dat <- dat[, ..keep]
  dat <- dat[complete.cases(dat)]
  if (!nrow(dat)) {
    return(list(F = NA_real_, p = NA_real_, n = 0L, m = 0L, k = 0L))
  }
  # Within one cycle, Z is constant per muni -> muni FE absorbs Z. Drop muni FE
  # within a single cycle; keep year FE only.
  vars <- vapply(fut_cols_gov, function(cc) var(dat[[cc]], na.rm = TRUE),
                 numeric(1))
  fut_keep <- fut_cols_gov[is.finite(vars) & vars > 0]
  if (!length(fut_keep)) {
    return(list(F = NA_real_, p = NA_real_, n = nrow(dat),
                m = uniqueN(dat$muni_id), k = 0L))
  }
  rhs <- paste(fut_keep, collapse = " + ")
  has_year_var <- uniqueN(dat$year) > 1L
  fml <- if (has_year_var) {
    as.formula(sprintf("delta_log_gdp ~ %s | year", rhs))
  } else {
    as.formula(sprintf("delta_log_gdp ~ %s", rhs))
  }
  mod <- feols(fml, data = dat,
               vcov = as.formula(paste0("~ ", CLUSTER_VAR)),
               lean = TRUE)
  z_pattern <- paste0("^Z_gov_", ALIGNMENT, "_", BASELINE, "_.*_future$")
  w <- fixest::wald(mod, keep = z_pattern, print = FALSE)
  list(F = as.numeric(w$stat), p = as.numeric(w$p),
       n = nobs(mod), m = uniqueN(dat$muni_id), k = length(fut_keep))
}

gov_cycle_rows <- list(
  data.table(scope = "pooled", election_cycle = NA_integer_,
             n_obs = pooled_gov$n, n_munis = pooled_gov$m,
             k_instruments = pooled_gov$k,
             joint_F = pooled_gov$F, joint_p = pooled_gov$p,
             rejects_5pc = isTRUE(pooled_gov$p < 0.05))
)
for (e in c(2004L, 2008L, 2012L, 2016L)) {
  r <- fit_gov_one_cycle(e)
  gov_cycle_rows[[length(gov_cycle_rows) + 1L]] <- data.table(
    scope = "per_cycle", election_cycle = e,
    n_obs = r$n, n_munis = r$m, k_instruments = r$k,
    joint_F = r$F, joint_p = r$p,
    rejects_5pc = isTRUE(r$p < 0.05)
  )
  message(sprintf("[INFO] gov cycle %d: F=%.4f p=%.4g n=%s",
                  e, r$F, r$p, format(r$n, big.mark = ",")))
}
gov_cycle_dt <- rbindlist(gov_cycle_rows)
fwrite(gov_cycle_dt, file.path(OUTPUT_BRANCH, "gov_cycle_interaction.csv"))

n_cycles_reject <- gov_cycle_dt[scope == "per_cycle" & rejects_5pc == TRUE,
                                 .N]
cycle_persistence <- if (n_cycles_reject >= 3L) {
  "PERSISTENT (3-4 of 4 cycles reject -> gov pre-trend is structural, not cycle-specific)"
} else if (n_cycles_reject == 0L) {
  "DIFFUSE (no single cycle rejects -> rejection comes from pooled cross-cycle signal)"
} else {
  sprintf("CYCLE-SPECIFIC (%d of 4 cycles reject)", n_cycles_reject)
}
message(sprintf("[INFO] B1.7.3.alpha verdict: %s", cycle_persistence))

# =============================================================================
# B1.7.3.beta -- descriptive contamination check
# =============================================================================
# For each (state x ref_election), compute:
#   mean of |Gov-Z_future| (loadings on the gov-coalition cycle shock, averaged
#     over all gov-Z sections, then averaged across munis within state)
#   mean state-level pre-period delta_log_gdp (UF aggregation)
# Then tabulate the (state, cycle) pairs and compute, per cycle, the
# correlation across states between the two.

message("[INFO] === B1.7.3.beta: descriptive contamination at state x cycle level ===")

# Per (muni, ref_election): one Z value per Gov-Z column (constant within cycle
# by construction). Average across all gov-Z sections to get a scalar
# "gov_shock_magnitude" per (muni, ref_election). We use the L1 mean of
# |Z| since coalition shocks can be signed; the magnitude captures total
# exposure regardless of direction.
gov_z_long <- z_at_ref[, c("muni_id", "ref_year", paste0(INST_COLS_GOV, "_future")),
                       with = FALSE]
# Map ref_year back to ref_election.
ref_year_to_election <- unique(PRE_MAP[, .(ref_year, ref_election)])
gov_z_long <- merge(gov_z_long, ref_year_to_election,
                    by = "ref_year", all.x = TRUE)

fut_cols_gov_in <- paste0(INST_COLS_GOV, "_future")
gov_z_long[, gov_shock_mag := rowMeans(abs(.SD), na.rm = TRUE),
           .SDcols = fut_cols_gov_in]
gov_z_long[, gov_shock_signed := rowMeans(.SD, na.rm = TRUE),
           .SDcols = fut_cols_gov_in]
gov_z_muni_cycle <- gov_z_long[, .(muni_id, ref_election,
                                    gov_shock_mag, gov_shock_signed)]

# Map muni_id -> state_id.
muni_state <- unique(muni[, .(muni_id, state_id)])
gov_z_muni_cycle <- merge(gov_z_muni_cycle, muni_state,
                          by = "muni_id", all.x = TRUE)
stopifnot(!any(is.na(gov_z_muni_cycle$state_id)))

# Pre-period state-level delta_log_gdp: for each ref_election, average
# delta_log_gdp over the matched pre-years within each state.
pre_gdp <- muni[year %in% PRE_MAP$pre_year,
                c("muni_id", "year", "state_id", "delta_log_gdp"),
                with = FALSE]
pre_gdp <- merge(pre_gdp, PRE_MAP[, .(pre_year, ref_election)],
                 by.x = "year", by.y = "pre_year", all.x = TRUE)
pre_gdp <- pre_gdp[!is.na(delta_log_gdp)]
state_pre <- pre_gdp[, .(state_pre_dlog_gdp = mean(delta_log_gdp,
                                                    na.rm = TRUE),
                          n_muni_yr = .N),
                     by = .(state_id, ref_election)]

# Average gov-Z by (state, ref_election).
state_z <- gov_z_muni_cycle[, .(state_gov_shock_mag = mean(gov_shock_mag,
                                                            na.rm = TRUE),
                                 state_gov_shock_signed = mean(gov_shock_signed,
                                                                na.rm = TRUE),
                                 n_munis = uniqueN(muni_id)),
                              by = .(state_id, ref_election)]

state_cell <- merge(state_z, state_pre, by = c("state_id", "ref_election"),
                    all = TRUE)
setorder(state_cell, ref_election, state_id)

# Per-cycle correlation across states.
cor_by_cycle <- state_cell[!is.na(state_gov_shock_mag) &
                            !is.na(state_pre_dlog_gdp),
                            .(n_states  = .N,
                              cor_mag   = if (.N >= 3L)
                                            cor(state_gov_shock_mag,
                                                state_pre_dlog_gdp,
                                                use = "complete.obs")
                                          else NA_real_,
                              cor_signed = if (.N >= 3L)
                                             cor(state_gov_shock_signed,
                                                 state_pre_dlog_gdp,
                                                 use = "complete.obs")
                                           else NA_real_),
                          by = ref_election]
setorder(cor_by_cycle, ref_election)

# Pooled correlation across all (state, cycle) cells.
pooled <- state_cell[!is.na(state_gov_shock_mag) &
                      !is.na(state_pre_dlog_gdp)]
pooled_cor_mag    <- if (nrow(pooled) >= 3L)
                       cor(pooled$state_gov_shock_mag,
                           pooled$state_pre_dlog_gdp) else NA_real_
pooled_cor_signed <- if (nrow(pooled) >= 3L)
                       cor(pooled$state_gov_shock_signed,
                           pooled$state_pre_dlog_gdp) else NA_real_

cor_summary <- rbind(
  cor_by_cycle,
  data.table(ref_election = NA_integer_,
             n_states = nrow(pooled),
             cor_mag = pooled_cor_mag,
             cor_signed = pooled_cor_signed),
  fill = TRUE
)

# Write the descriptive cell table plus the correlation summary as two
# logical sections in one CSV: long-form, with a "row_type" tag.
state_cell[, row_type := "state_cycle_cell"]
cor_summary[, row_type := ifelse(is.na(ref_election),
                                  "pooled_correlation",
                                  "per_cycle_correlation")]

contamination_out <- rbindlist(list(
  state_cell[, .(row_type, ref_election, state_id,
                 state_gov_shock_mag, state_gov_shock_signed,
                 n_munis, state_pre_dlog_gdp, n_muni_yr)],
  cor_summary[, .(row_type, ref_election,
                  state_id = NA_integer_,
                  state_gov_shock_mag = NA_real_,
                  state_gov_shock_signed = NA_real_,
                  n_munis = n_states,
                  state_pre_dlog_gdp = cor_mag,
                  n_muni_yr = NA_integer_,
                  cor_signed = cor_signed)]
), fill = TRUE)
fwrite(contamination_out,
       file.path(OUTPUT_BRANCH, "gov_contamination_descriptive.csv"))

message("[INFO] per-cycle correlations (cor_mag = |Z| vs state pre-Delta log_gdp):")
print(cor_by_cycle)
message(sprintf("[INFO] pooled cor_mag=%.4f cor_signed=%.4f (n=%d state-cycle cells)",
                pooled_cor_mag, pooled_cor_signed, nrow(pooled)))

# =============================================================================
# Markdown summary
# =============================================================================

fmt <- function(x, digits = 4L) {
  if (!is.finite(x)) return("NA")
  formatC(x, format = "g", digits = digits)
}

md <- c(
  "# Phase 1.7 -- Governor-Instrument Pre-Trend Deep-Dive",
  "",
  sprintf("**Date:** %s", format(Sys.time(), "%Y-%m-%d %H:%M")),
  "**Outcome:** Delta log_gdp",
  "**FE / SE:** muni + year FE; cluster on muni_id (per-cycle gov tests drop muni FE because Z is constant within muni-cycle)",
  "",
  "## B1.7.1 -- alpha-clearance after dropping Pres x E + Pres x P",
  "",
  "Re-run variant-alpha with full Z minus {Z_pres_coalition_cycle_specific_E,",
  "Z_pres_coalition_cycle_specific_P}.",
  "",
  "| n_obs | k_instruments | joint F | joint p | rejects 5% | alpha clears? |",
  "|---|---|---|---|---|---|",
  sprintf("| %s | %d | %s | %s | %s | %s |",
          format(b171$n, big.mark = ","), b171$k,
          fmt(b171$F), fmt(b171$p),
          isTRUE(b171$p < 0.05),
          if (alpha_cleared) "YES (halt at B1.7.1)" else "NO (proceed to B1.7.2)"),
  "",
  "## B1.7.2 -- by-office decomposition on cleaned Z",
  "",
  "| Office | Z-set | n_obs | k | joint F | joint p | rejects 5% |",
  "|---|---|---|---|---|---|---|"
)
for (i in seq_len(nrow(office_dt))) {
  md <- c(md, sprintf("| %s | %s | %s | %d | %s | %s | %s |",
                      office_dt$office[i], office_dt$z_set[i],
                      format(office_dt$n_obs[i], big.mark = ","),
                      office_dt$k_instruments[i],
                      fmt(office_dt$joint_F[i]),
                      fmt(office_dt$joint_p[i]),
                      office_dt$rejects_5pc[i]))
}
md <- c(md, "",
        sprintf("**Gov still the driver?** %s. **Gov only driver?** %s.",
                gov_drives, gov_only_driver))

md <- c(md, "",
        "## B1.7.3.alpha -- Gov-cycle interaction",
        "",
        "Gov-Z joint F, pooled and per ref_election cycle. Per-cycle specs use year FE only (Z constant within muni-cycle).",
        "",
        "| Scope | Cycle | n_obs | k | joint F | joint p | rejects 5% |",
        "|---|---|---|---|---|---|---|")
for (i in seq_len(nrow(gov_cycle_dt))) {
  md <- c(md, sprintf("| %s | %s | %s | %d | %s | %s | %s |",
                      gov_cycle_dt$scope[i],
                      if (is.na(gov_cycle_dt$election_cycle[i])) "--"
                      else as.character(gov_cycle_dt$election_cycle[i]),
                      format(gov_cycle_dt$n_obs[i], big.mark = ","),
                      gov_cycle_dt$k_instruments[i],
                      fmt(gov_cycle_dt$joint_F[i]),
                      fmt(gov_cycle_dt$joint_p[i]),
                      gov_cycle_dt$rejects_5pc[i]))
}
md <- c(md, "",
        sprintf("**Cycle pattern:** %s.", cycle_persistence))

md <- c(md, "",
        "## B1.7.3.beta -- descriptive contamination at state x cycle level",
        "",
        "Per (state, ref_election), mean |Gov-Z_future| across munis vs mean state pre-period Delta log_gdp. Correlations computed across states within each cycle and pooled across all state-cycle cells.",
        "",
        "| Cycle | n_states | cor(|Z|, state pre-Delta log_gdp) | cor(signed Z, state pre-Delta log_gdp) |",
        "|---|---|---|---|")
for (i in seq_len(nrow(cor_by_cycle))) {
  md <- c(md, sprintf("| %d | %d | %s | %s |",
                      cor_by_cycle$ref_election[i],
                      cor_by_cycle$n_states[i],
                      fmt(cor_by_cycle$cor_mag[i]),
                      fmt(cor_by_cycle$cor_signed[i])))
}
md <- c(md, sprintf("| pooled | %d | %s | %s |",
                    nrow(pooled), fmt(pooled_cor_mag), fmt(pooled_cor_signed)))

# Story classification (heuristic).
story <- if (alpha_cleared) {
  "A-overlap (Pres-E/P violators absorbed the alpha rejection)"
} else if (cycle_persistence ==
           "PERSISTENT (3-4 of 4 cycles reject -> gov pre-trend is structural, not cycle-specific)") {
  if (is.finite(pooled_cor_mag) && abs(pooled_cor_mag) > 0.20) {
    "B-budget (persistent across cycles + non-trivial state-level cor -> consistent with gov-budget reverse causation)"
  } else {
    "C-spec (persistent across cycles + weak state-level cor -> likely specification artifact in instrument build)"
  }
} else if (grepl("CYCLE-SPECIFIC", cycle_persistence)) {
  "A-anticipation (rejection localized to subset of cycles -> plausibly real political anticipation)"
} else {
  "C-spec (diffuse pooled signal with no single-cycle driver -> likely artifact)"
}

md <- c(md, "",
        "## Limitations",
        "",
        "- State-fiscal data (FINBRA aggregates: state-level expenditure / revenue / debt) are NOT on disk. The budget-cycle channel cannot be tested directly. Required for a follow-up: state-year fiscal panels matched to gov election cycles.",
        "- Gov elections in Brazil are 2002, 2006, 2010, 2014, 2018; the analysis indexes by the mayoral cycle (2004, 2008, 2012, 2016) used in cycle_specific Z. A clean gov-cycle re-indexing would require rebuilding Z with a gov-specific cycle window.",
        "- 'gov_shock_mag' is the row mean of |Gov-Z columns| over kept sections (K-1 sections). This is a magnitude proxy; the signed mean is also reported.",
        "",
        "## Story classification",
        "",
        sprintf("**Best-supported story:** %s.", story),
        "",
        "Stories considered:",
        "- A-anticipation: real pre-electoral political anticipation in the coalition shock.",
        "- B-budget: state-level fiscal / political-credit cycle reverse-causally drives the alignment shock.",
        "- C-spec: coding artifact in how Z is computed off lagged gov-party variables.",
        "")

writeLines(md, file.path(OUTPUT_BRANCH, "pretrend_b17_summary.md"))
message(sprintf("[INFO] wrote: %s",
                file.path(OUTPUT_BRANCH, "pretrend_b17_summary.md")))
message(sprintf("[INFO] %s | done.", Sys.time()))
