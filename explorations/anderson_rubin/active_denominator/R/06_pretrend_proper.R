#!/usr/bin/env Rscript

# ==============================================================================
# 06_pretrend_proper.R
# Phase 1.5 extension B1.6 -- proper tau-baseline pre-trend test.
#
# Purpose. The B1.4 pre-trend test (03_rotemberg_diagnostics.R) regressed
# CONTEMPORANEOUS s_emp_jmt at year tau on the CONTEMPORANEOUS Z value at year
# tau, which is a within-period correlation, not a pre-trend. The strategist
# gate (journal/plans/2026-05-12_phase2_strategist_review.md) requires a
# proper tau-baseline test: do munis that will receive a large FUTURE shock
# Z_{m,e(t)} at the next mayoral election already show diverging outcomes
# BEFORE e(t)?
#
# Mapping pre-period tau to future-cycle Z.
# Mayoral elections: 2004, 2008, 2012, 2016.
# Z_{m, year} in muni_panel_for_regs.qs2 is constant over each post-election
# cycle window. The "future cycle" Z for pre-period year tau is the Z value
# realised in the cycle starting just AFTER the next election e:
#   tau in {2002, 2003}        -> e = 2004 -> Z evaluated at 2005
#   tau in {2005, 2006, 2007}  -> e = 2008 -> Z evaluated at 2009
#   tau in {2009, 2010, 2011}  -> e = 2012 -> Z evaluated at 2013
#   tau in {2013, 2014, 2015}  -> e = 2016 -> Z evaluated at 2017
# Election years themselves (2004, 2008, 2012, 2016) are excluded from the
# pre-period regression (they are the "treatment" point in event time).
#
# Variants implemented.
#   Variant alpha: outcome pre-trend (PREFERRED / headline)
#     Regress pre-period y_{m,tau} on Z^future_{m,e(t)} for each office-sector
#     instrument simultaneously; year + muni FE; cluster on muni_id; joint Wald
#     on the Z's gives the pre-trend test statistic. Run twice: y = log_gdp,
#     y = delta_log_gdp.
#
#   Variant beta: share pre-trend (per memo robustness item 6)
#     For each top-5 Rotemberg sector j (Pres x T, Mayor x P, Gov x P, Pres x E,
#     Pres x P), regress s^emp_{jm,tau} at pre-period tau on the FUTURE Z value
#     for that specific (office, sector); muni + year FE; cluster on muni_id.
#     Per-sector coefficient and p-value reported; pass = no rejection on
#     >=3 of 5 sectors at 5%.
#
# Margins. cnae_section only at this Phase 1.5 stage; policy_block deferred
# to Phase 2 C2.1.5 (no policy_block emp_share panel built yet).
#
# Inputs:
#   data/processed/muni_panel_for_regs.qs2 (script 41)
#   explorations/anderson_rubin/active_denominator/output/
#       emp_share_panel_contemporaneous.qs2 (B1.2)
#       rotemberg_weights.csv (B1.4; consulted only to confirm top-5 list)
#
# Outputs:
#   output/pretrend_alpha_log_gdp.csv
#   output/pretrend_alpha_delta_log_gdp.csv
#   output/pretrend_beta_sector_shares.csv
#   output/pretrend_summary.md
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

ALIGNMENT <- "coalition"
BASELINE  <- "cycle_specific"
OFFICES   <- c("mayor", "gov", "pres")
CLUSTER_VAR <- "muni_id"

# Pre-period year -> reference election e and reference future-cycle year r:
# tau -> e -> r where Z_future = Z_{m, r} (Z is constant within post-election
# cycle, so any year in [e+1, e+4] gives the same Z; we use r = e + 1).
PRE_TAU_TO_REF_YEAR <- data.table(
  pre_year = c(2002L, 2003L,
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

message(sprintf("[INFO] %s | pre-period tau -> ref_year map:", Sys.time()))
print(PRE_TAU_TO_REF_YEAR)

# Top-5 Rotemberg sectors per B1.4 (rotemberg_weights.csv rank 1-5).
TOP5 <- data.table(
  office       = c("pres",  "mayor", "gov",   "pres",  "pres"),
  cnae_section = c("T",     "P",     "P",     "E",     "P")
)
TOP5[, instrument := sprintf("Z_%s_%s_%s_%s", office, ALIGNMENT, BASELINE,
                              cnae_section)]

# ---- Load muni panel ---------------------------------------------------------

muni_path <- output_path("muni_panel_for_regs.qs2")
stopifnot(file.exists(muni_path))
message(sprintf("[INFO] %s | loading muni panel...", Sys.time()))
muni <- qs_read(muni_path)
setDT(muni)
muni[, muni_id := as.integer(muni_id)]
muni[, year    := as.integer(year)]
muni <- muni[muni_id > 0L]

# Discover sections from column names.
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

INST_COLS <- build_inst_cols(OFFICES, SECTIONS_KEEP)
stopifnot(all(INST_COLS %in% names(muni)))

# ---- Build delta_log_gdp -----------------------------------------------------

setorder(muni, muni_id, year)
muni[, delta_log_gdp := log_gdp - shift(log_gdp, type = "lag"), by = muni_id]

# ---- Build future-Z lookup ---------------------------------------------------
# For each (muni_id, ref_year) pull the full vector of Z values; rename to
# "<col>_future"; then merge onto (muni_id, pre_year) via the tau->ref_year map.

z_at_ref <- muni[year %in% unique(PRE_TAU_TO_REF_YEAR$ref_year),
                 c("muni_id", "year", INST_COLS), with = FALSE]
setnames(z_at_ref, "year", "ref_year")
future_cols <- paste0(INST_COLS, "_future")
setnames(z_at_ref, INST_COLS, future_cols)

message(sprintf("[INFO] z_at_ref rows=%s munis=%s",
                format(nrow(z_at_ref), big.mark = ","),
                format(uniqueN(z_at_ref$muni_id), big.mark = ",")))

# ---- VARIANT ALPHA: outcome pre-trend ----------------------------------------

run_alpha <- function(outcome) {
  stopifnot(outcome %in% c("log_gdp", "delta_log_gdp"))

  # Pre-period subset of muni panel.
  pre <- muni[year %in% PRE_TAU_TO_REF_YEAR$pre_year,
              c("muni_id", "year", outcome), with = FALSE]
  pre <- merge(pre, PRE_TAU_TO_REF_YEAR[, .(pre_year, ref_year)],
               by.x = "year", by.y = "pre_year", all.x = TRUE)
  stopifnot(!any(is.na(pre$ref_year)))

  # Merge future Z by (muni_id, ref_year).
  dat <- merge(pre, z_at_ref, by = c("muni_id", "ref_year"), all.x = TRUE)

  # Complete-case on outcome + all future Z columns.
  keep_cols <- c("muni_id", "year", outcome, future_cols)
  dat <- dat[, ..keep_cols]
  dat <- dat[complete.cases(dat)]
  stopifnot(nrow(dat) > 0L)

  message(sprintf("[INFO] variant alpha [%s]: n=%s munis=%s years=%s",
                  outcome,
                  format(nrow(dat), big.mark = ","),
                  format(uniqueN(dat$muni_id), big.mark = ","),
                  paste(sort(unique(dat$year)), collapse = ",")))

  rhs <- paste(future_cols, collapse = " + ")
  fml <- as.formula(sprintf("%s ~ %s | muni_id + year", outcome, rhs))
  mod <- feols(fml, data = dat,
               vcov = as.formula(paste0("~ ", CLUSTER_VAR)),
               lean = FALSE)

  z_pattern <- paste0("^Z_(",
                      paste(OFFICES, collapse = "|"),
                      ")_", ALIGNMENT, "_", BASELINE, "_.*_future$")
  w <- fixest::wald(mod, keep = z_pattern)
  joint_F <- as.numeric(w$stat)
  joint_p <- as.numeric(w$p)

  ct <- coeftable(mod)
  is_z <- grepl(z_pattern, rownames(ct))

  per_inst <- data.table(
    instrument = rownames(ct)[is_z],
    beta_hat   = ct[is_z, "Estimate"],
    se         = ct[is_z, "Std. Error"],
    t_stat     = ct[is_z, "t value"],
    p_value    = ct[is_z, "Pr(>|t|)"]
  )
  per_inst[, office := sub("^Z_([^_]+)_.*$", "\\1", instrument)]
  per_inst[, cnae_section := sub("^.*_([A-Z])_future$", "\\1", instrument)]
  per_inst[, outcome := outcome]
  per_inst[, n_obs := nobs(mod)]
  per_inst[, joint_F := joint_F]
  per_inst[, joint_p := joint_p]
  per_inst[, rejects_5pc_joint := isTRUE(joint_p < 0.05)]

  setcolorder(per_inst, c("outcome", "instrument", "office", "cnae_section",
                          "beta_hat", "se", "t_stat", "p_value",
                          "n_obs", "joint_F", "joint_p",
                          "rejects_5pc_joint"))
  setorder(per_inst, p_value)

  list(per_inst = per_inst,
       joint_F = joint_F, joint_p = joint_p,
       n_obs = nobs(mod), n_munis = uniqueN(dat$muni_id))
}

message(sprintf("[INFO] %s | running variant alpha (log_gdp)...", Sys.time()))
alpha_lg <- run_alpha("log_gdp")
fwrite(alpha_lg$per_inst,
       file.path(OUTPUT_BRANCH, "pretrend_alpha_log_gdp.csv"))
message(sprintf("[INFO] alpha log_gdp: joint_F=%.4f joint_p=%.4g n=%s",
                alpha_lg$joint_F, alpha_lg$joint_p,
                format(alpha_lg$n_obs, big.mark = ",")))

message(sprintf("[INFO] %s | running variant alpha (delta_log_gdp)...",
                Sys.time()))
alpha_dlg <- run_alpha("delta_log_gdp")
fwrite(alpha_dlg$per_inst,
       file.path(OUTPUT_BRANCH, "pretrend_alpha_delta_log_gdp.csv"))
message(sprintf("[INFO] alpha delta_log_gdp: joint_F=%.4f joint_p=%.4g n=%s",
                alpha_dlg$joint_F, alpha_dlg$joint_p,
                format(alpha_dlg$n_obs, big.mark = ",")))

# ---- VARIANT BETA: share pre-trend on top-5 sectors --------------------------

emp_path <- file.path(OUTPUT_BRANCH, "emp_share_panel_contemporaneous.qs2")
stopifnot(file.exists(emp_path))
message(sprintf("[INFO] %s | loading emp share panel...", Sys.time()))
emp <- qs_read(emp_path)
setDT(emp)
emp[, muni_id := as.integer(muni_id)]
emp[, year    := as.integer(year)]

run_beta_one_sector <- function(office, sec) {
  inst_col <- sprintf("Z_%s_%s_%s_%s", office, ALIGNMENT, BASELINE, sec)
  inst_fut <- paste0(inst_col, "_future")
  if (!(inst_fut %in% names(z_at_ref))) {
    return(data.table(office = office, cnae_section = sec,
                      instrument = inst_col, n_obs = 0L,
                      beta_hat = NA_real_, se = NA_real_,
                      t_stat = NA_real_, p_value = NA_real_,
                      status = "no_inst"))
  }

  # Restrict emp panel to this sector AND pre-period years.
  dat <- emp[cnae_section == sec & year %in% PRE_TAU_TO_REF_YEAR$pre_year,
             .(muni_id, year, s_emp_jmt)]
  dat <- merge(dat, PRE_TAU_TO_REF_YEAR[, .(pre_year, ref_year)],
               by.x = "year", by.y = "pre_year", all.x = TRUE)
  z_one <- z_at_ref[, c("muni_id", "ref_year", inst_fut), with = FALSE]
  dat <- merge(dat, z_one, by = c("muni_id", "ref_year"), all.x = TRUE)
  dat <- dat[!is.na(s_emp_jmt) & !is.na(get(inst_fut))]
  if (!nrow(dat)) {
    return(data.table(office = office, cnae_section = sec,
                      instrument = inst_col, n_obs = 0L,
                      beta_hat = NA_real_, se = NA_real_,
                      t_stat = NA_real_, p_value = NA_real_,
                      status = "empty_sample"))
  }

  fml <- as.formula(sprintf("s_emp_jmt ~ %s | muni_id + year", inst_fut))
  mod <- tryCatch(
    feols(fml, data = dat,
          vcov = as.formula(paste0("~ ", CLUSTER_VAR)),
          lean = TRUE),
    error = function(e) {
      message(sprintf("[WARN] beta fit failed [%s/%s]: %s",
                      office, sec, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(mod)) {
    return(data.table(office = office, cnae_section = sec,
                      instrument = inst_col, n_obs = nrow(dat),
                      beta_hat = NA_real_, se = NA_real_,
                      t_stat = NA_real_, p_value = NA_real_,
                      status = "fit_failed"))
  }
  ct <- coeftable(mod)
  data.table(
    office = office, cnae_section = sec,
    instrument = inst_col, n_obs = nobs(mod),
    beta_hat = ct[inst_fut, "Estimate"],
    se       = ct[inst_fut, "Std. Error"],
    t_stat   = ct[inst_fut, "t value"],
    p_value  = ct[inst_fut, "Pr(>|t|)"],
    status   = "ok"
  )
}

message(sprintf("[INFO] %s | running variant beta on top-5 sectors...",
                Sys.time()))
beta_rows <- vector("list", nrow(TOP5))
for (i in seq_len(nrow(TOP5))) {
  beta_rows[[i]] <- run_beta_one_sector(TOP5$office[i], TOP5$cnae_section[i])
}
beta_dt <- rbindlist(beta_rows, fill = TRUE)
beta_dt[, rejects_5pc := isTRUE(p_value < 0.05), by = seq_len(nrow(beta_dt))]
beta_dt[, margin := "cnae_section"]
setcolorder(beta_dt, c("margin", "office", "cnae_section", "instrument",
                       "n_obs", "beta_hat", "se", "t_stat", "p_value",
                       "rejects_5pc", "status"))
fwrite(beta_dt,
       file.path(OUTPUT_BRANCH, "pretrend_beta_sector_shares.csv"))
message("[INFO] variant beta results:")
print(beta_dt)

# ---- Verdict and markdown summary --------------------------------------------

alpha_log_pass <- !isTRUE(alpha_lg$joint_p < 0.05)
alpha_dlg_pass <- !isTRUE(alpha_dlg$joint_p < 0.05)
beta_n_reject  <- sum(beta_dt$status == "ok" &
                      !is.na(beta_dt$p_value) &
                      beta_dt$p_value < 0.05, na.rm = TRUE)
beta_n_ok      <- sum(beta_dt$status == "ok", na.rm = TRUE)
# Pass criterion: at most 2 marginal failures of 5 (i.e., >=3 of 5 do not
# reject).
beta_pass <- (beta_n_ok - beta_n_reject) >= 3L

overall_pass <- alpha_dlg_pass && beta_pass
message(sprintf("[INFO] alpha log_gdp pass=%s (p=%.4g)",
                alpha_log_pass, alpha_lg$joint_p))
message(sprintf("[INFO] alpha delta_log_gdp pass=%s (p=%.4g)",
                alpha_dlg_pass, alpha_dlg$joint_p))
message(sprintf("[INFO] beta n_reject=%d of %d ok (pass=%s)",
                beta_n_reject, beta_n_ok, beta_pass))
message(sprintf("[INFO] overall verdict: %s",
                if (overall_pass) "PASS" else "FAIL"))

fmt <- function(x, digits = 4L) {
  if (!is.finite(x)) return("NA")
  formatC(x, format = "g", digits = digits)
}

md_lines <- c(
  "# Proper tau-Baseline Pre-Trend Test (B1.6)",
  "",
  sprintf("**Date:** %s", format(Sys.time(), "%Y-%m-%d %H:%M")),
  "**Margin:** cnae_section (policy_block deferred to Phase 2 C2.1.5)",
  sprintf("**Pre-period years:** %s",
          paste(sort(unique(PRE_TAU_TO_REF_YEAR$pre_year)),
                collapse = ", ")),
  "",
  "## Variant alpha -- outcome pre-trend (headline)",
  "",
  "Regress pre-period outcome on FUTURE-cycle Z (the Z value realised in the",
  "post-election cycle following the next mayoral election). Joint Wald F over",
  "all office x sector future-Z columns; muni + year FE; cluster on muni_id.",
  "",
  "| Outcome | n_obs | joint F | joint p | rejects 5% | verdict |",
  "|---|---|---|---|---|---|",
  sprintf("| log_gdp | %s | %s | %s | %s | %s |",
          format(alpha_lg$n_obs, big.mark = ","),
          fmt(alpha_lg$joint_F), fmt(alpha_lg$joint_p),
          isTRUE(alpha_lg$joint_p < 0.05),
          if (alpha_log_pass) "PASS" else "FAIL"),
  sprintf("| delta_log_gdp | %s | %s | %s | %s | %s |",
          format(alpha_dlg$n_obs, big.mark = ","),
          fmt(alpha_dlg$joint_F), fmt(alpha_dlg$joint_p),
          isTRUE(alpha_dlg$joint_p < 0.05),
          if (alpha_dlg_pass) "PASS" else "FAIL"),
  "",
  "## Variant beta -- per-sector share pre-trend (top-5 Rotemberg)",
  "",
  "For each top-5 Rotemberg sector j, regress s^emp_{jm,tau} on the future-cycle",
  "Z for that specific (office, sector); muni + year FE; cluster on muni_id.",
  "",
  "| Office | Sector | beta | SE | t | p-value | reject 5% |",
  "|---|---|---|---|---|---|---|"
)
for (i in seq_len(nrow(beta_dt))) {
  md_lines <- c(md_lines, sprintf(
    "| %s | %s | %s | %s | %s | %s | %s |",
    beta_dt$office[i], beta_dt$cnae_section[i],
    fmt(beta_dt$beta_hat[i]), fmt(beta_dt$se[i]),
    fmt(beta_dt$t_stat[i]), fmt(beta_dt$p_value[i]),
    isTRUE(beta_dt$p_value[i] < 0.05)
  ))
}
md_lines <- c(md_lines,
  "",
  sprintf("**Variant beta:** %d of %d sectors reject at 5%%. Pass criterion (>=3 of 5 do NOT reject): %s.",
          beta_n_reject, beta_n_ok, if (beta_pass) "PASS" else "FAIL"),
  "",
  "## Overall verdict",
  "",
  sprintf("**%s** -- alpha (delta_log_gdp) %s and beta %s.",
          if (overall_pass) "PASS" else "FAIL",
          if (alpha_dlg_pass) "passes" else "FAILS",
          if (beta_pass) "passes" else "FAILS"),
  "",
  "## Note on the B1.4 contemporaneous-on-contemporaneous flags",
  "",
  "B1.4 flagged Pres x T (p = 0.04) and Pres x E (p = 4e-4) on a within-period",
  "regression of s_emp_jmt at year tau on Z at year tau. That tests whether the",
  "contemporaneous instrument is correlated with the contemporaneous share,",
  "i.e., it is mechanically a first-stage check on the share-vector itself, not",
  "a pre-trend. The proper tau-baseline test above asks whether the FUTURE",
  "instrument predicts the PRE-period outcome / share -- the actual GPSS / BHJ",
  "pre-trend object. Comparing the two: any B1.4 flag that survives here is an",
  "anticipation violation; any B1.4 flag that disappears here was the result of",
  "the (legitimate) contemporaneous variation that the AR test relies on.",
  ""
)
writeLines(md_lines, file.path(OUTPUT_BRANCH, "pretrend_summary.md"))
message(sprintf("[INFO] wrote: %s",
                file.path(OUTPUT_BRANCH, "pretrend_summary.md")))

message(sprintf("[INFO] %s | done.", Sys.time()))
