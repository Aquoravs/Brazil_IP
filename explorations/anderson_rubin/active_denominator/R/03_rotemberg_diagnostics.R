#!/usr/bin/env Rscript

# ==============================================================================
# 03_rotemberg_diagnostics.R
# B1.4.1 - Rotemberg-weight diagnostics on the AR-test headline spec
# (contemporaneous variant, MGP flavor, muni+year FE, log_gdp outcome).
#
# Approach.
#   Goldsmith-Pinkham, Sorkin & Swift (2020) §4.2 develops Rotemberg weights for a
#   scalar Bartik IV: alpha_k proportional to (z_k' M_W y)(z_k' M_W x). In the
#   AR-test setting here, the test is on the joint coefficient vector beta on
#   K = (n_offices x n_sectors) - 1 share-instruments, not on a scalar reduced
#   form. We therefore report a partial-Wald analog of the Rotemberg weight:
#
#     w_k = (t_k)^2 / sum_j (t_j)^2
#
#   where t_k is the cluster-robust t-stat on instrument k in the AR reduced
#   form. Sum-of-squared-t equals the AR Wald F up to a normalization, so w_k is
#   the share of the joint AR statistic attributable to instrument k. This is
#   the right "concentration" diagnostic for the AR test: if one or two z_k
#   carry the rejection, drop-top-5 should overturn it.
#
#   For interpretation we also report a GPSS-style "Bartik-like" weight on the
#   leading-section projection: project the per-sector beta onto the largest-
#   absolute-value coefficient and rank z_k by their contribution to that
#   scalar.
#
# Steps.
#   1) Rebuild the headline reduced-form regression (mirror of run_ar() in
#      02_ar_test_emp_share.R, headline cell).
#   2) Extract per-instrument t-stats, compute w_k, rank.
#   3) Tabulate top 5 / bottom 5; share of total weight on top 5.
#   4) Re-run AR with top-5 dropped.
#   5) Pre-trend test on top-5 sectors: regress sector j's pre-election
#      (year in [e(t)-4, e(t)-1]) emp share on the year-e(t) instrument value.
#
# Inputs:
#   data/processed/muni_panel_for_regs.qs2 (same as 02_ar_test_emp_share.R)
#   explorations/.../output/emp_share_panel_contemporaneous.qs2
#   explorations/.../output/slack_per_cell_contemporaneous.csv
#
# Outputs:
#   output/rotemberg_weights.csv
#   output/rotemberg_top5_drop_ar.csv
#   output/pretrend_high_weight.csv
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

THIS_SCRIPT <- get_this_script()
BRANCH_DIR  <- normalizePath(file.path(dirname(THIS_SCRIPT), ".."),
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

# ---- Constants (headline spec) ----------------------------------------------

VARIANT   <- "contemporaneous"
OUTCOME   <- "log_gdp"
FLAVOR    <- "MGP"
FE_TERM   <- "muni_id + year"
BASELINE  <- "cycle_specific"
ALIGNMENT <- "coalition"
OFFICES   <- c("mayor", "gov", "pres")
INCLUDE_SLACK <- FALSE  # contemporaneous slack is mechanically 1 => collinear

message(sprintf("[INFO] %s | headline spec: variant=%s outcome=%s flavor=%s",
                Sys.time(), VARIANT, OUTCOME, FLAVOR))

# ---- Load muni panel ---------------------------------------------------------

muni_path <- output_path("muni_panel_for_regs.qs2")
stopifnot(file.exists(muni_path))
message(sprintf("[INFO] %s | loading muni panel...", Sys.time()))
muni <- qs_read(muni_path)
setDT(muni)
muni[, muni_id := as.integer(muni_id)]
muni[, year    := as.integer(year)]
muni <- muni[muni_id > 0L]

# Sections from column names.
inst_prefix <- sprintf("Z_mayor_%s_%s_", ALIGNMENT, BASELINE)
sec_cols <- grep(paste0("^", inst_prefix, "[A-Z]$"), names(muni), value = TRUE)
SECTIONS <- sort(sub(paste0("^", inst_prefix), "", sec_cols))
HOLDOUT  <- SECTIONS[length(SECTIONS)]
SECTIONS_KEEP <- setdiff(SECTIONS, HOLDOUT)
message(sprintf("[INFO] sections (K=%d, holdout=%s)",
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

# Volume control: same as 02_*.R.
setorder(muni, muni_id, year)
init_gdp <- muni[!is.na(pib_real),
                 .(initial_gdp = pib_real[1L]), by = muni_id]
muni <- merge(muni, init_gdp, by = "muni_id", all.x = TRUE)
muni[, vol_ratio := total_bndes_real / initial_gdp]
muni[!is.finite(vol_ratio), vol_ratio := NA_real_]

# ---- Headline reduced form ---------------------------------------------------

run_reduced_form <- function(inst_cols_use) {
  keep <- c("muni_id", "year", OUTCOME, "vol_ratio", inst_cols_use)
  dat <- muni[, ..keep]
  dat <- dat[complete.cases(dat)]
  rhs <- c(inst_cols_use, "vol_ratio")
  fml <- as.formula(paste0(
    OUTCOME, " ~ ", paste(rhs, collapse = " + "),
    " | ", FE_TERM
  ))
  mod <- feols(fml, data = dat, vcov = ~ muni_id, lean = TRUE)
  list(mod = mod, n = nrow(dat))
}

message(sprintf("[INFO] %s | fitting headline reduced form (K=%d)...",
                Sys.time(), length(INST_COLS)))
hf <- run_reduced_form(INST_COLS)
mod <- hf$mod

z_pattern <- sprintf("^Z_(%s)_%s_%s_",
                     paste(OFFICES, collapse = "|"), ALIGNMENT, BASELINE)
w_all <- fixest::wald(mod, keep = z_pattern)
ar_F_baseline <- as.numeric(w_all$stat)
ar_p_baseline <- as.numeric(w_all$p)
message(sprintf("[INFO] baseline AR_F=%.3f AR_p=%.4g n=%d",
                ar_F_baseline, ar_p_baseline, hf$n))

# ---- Per-instrument Rotemberg-analog weights --------------------------------

ct <- coeftable(mod)
z_rows <- grepl(z_pattern, rownames(ct))
ct_z <- ct[z_rows, , drop = FALSE]

# Parse office + section out of the column name.
parse_inst <- function(nm) {
  parts <- strsplit(nm, "_", fixed = TRUE)[[1L]]
  list(office = parts[2L], section = parts[length(parts)])
}

inst_info <- lapply(rownames(ct_z), parse_inst)
rotemberg <- data.table(
  instrument = rownames(ct_z),
  office     = vapply(inst_info, `[[`, character(1), "office"),
  cnae_section = vapply(inst_info, `[[`, character(1), "section"),
  beta_hat = ct_z[, "Estimate"],
  se       = ct_z[, "Std. Error"],
  t_stat   = ct_z[, "t value"],
  p_value  = ct_z[, "Pr(>|t|)"]
)
rotemberg[, t_sq := t_stat^2]
total_t_sq <- sum(rotemberg$t_sq, na.rm = TRUE)
rotemberg[, w_partial_wald := t_sq / total_t_sq]

# Leading-section projection (GPSS scalar-Bartik analog): project onto sector
# with largest abs beta; weight z_k by |beta_k * beta_lead| / sum(...).
lead_idx <- which.max(abs(rotemberg$beta_hat))
beta_lead <- rotemberg$beta_hat[lead_idx]
rotemberg[, w_gpss_proj := abs(beta_hat * beta_lead) /
                           sum(abs(beta_hat * beta_lead), na.rm = TRUE)]

setorder(rotemberg, -w_partial_wald)
rotemberg[, rank_partial_wald := seq_len(.N)]

out_rw <- file.path(OUTPUT_BRANCH, "rotemberg_weights.csv")
fwrite(rotemberg, out_rw)
message(sprintf("[INFO] wrote: %s", out_rw))

# Console digest.
top5 <- head(rotemberg, 5L)
bot5 <- tail(rotemberg, 5L)
message("[INFO] top 5 instruments by partial-Wald weight:")
print(top5[, .(instrument, office, cnae_section, beta_hat, t_stat, w_partial_wald)])
message("[INFO] bottom 5 instruments by partial-Wald weight:")
print(bot5[, .(instrument, office, cnae_section, beta_hat, t_stat, w_partial_wald)])
share_top5 <- sum(top5$w_partial_wald, na.rm = TRUE)
message(sprintf("[INFO] share of joint AR F carried by top 5: %.3f",
                share_top5))

# ---- Drop-top-5 AR rerun -----------------------------------------------------

top5_inst <- top5$instrument
inst_cols_drop <- setdiff(INST_COLS, top5_inst)
message(sprintf("[INFO] %s | re-fitting AR with top-5 dropped (K'=%d)...",
                Sys.time(), length(inst_cols_drop)))
hf_drop <- run_reduced_form(inst_cols_drop)
w_drop <- fixest::wald(hf_drop$mod, keep = z_pattern)
ar_F_drop <- as.numeric(w_drop$stat)
ar_p_drop <- as.numeric(w_drop$p)
message(sprintf("[INFO] drop-top-5 AR_F=%.3f AR_p=%.4g n=%d",
                ar_F_drop, ar_p_drop, hf_drop$n))

drop_dt <- data.table(
  spec = c("baseline", "drop_top5"),
  K = c(length(INST_COLS), length(inst_cols_drop)),
  n_obs = c(hf$n, hf_drop$n),
  ar_F = c(ar_F_baseline, ar_F_drop),
  ar_p = c(ar_p_baseline, ar_p_drop),
  rejects_5pc = c(ar_p_baseline < 0.05, ar_p_drop < 0.05),
  share_top5_weight = c(share_top5, NA_real_),
  top5_instruments = c(paste(top5_inst, collapse = ";"), "")
)
out_drop <- file.path(OUTPUT_BRANCH, "rotemberg_top5_drop_ar.csv")
fwrite(drop_dt, out_drop)
message(sprintf("[INFO] wrote: %s", out_drop))

# ---- Pre-trend test on top-5 sectors -----------------------------------------
#
# For each top-5 sector, regress sector-share at year t in the pre-election
# window [e(t)-4, e(t)-1] on the year-t instrument value. Identification of
# valid AR requires that pre-election shares (the basis for w_jm,tau) are
# orthogonal to the shock. We do the lighter analog here: pool over pre-period
# years and regress emp share on the instrument column itself, controlling for
# muni and year FE. A non-zero coefficient flags a pre-trend.

emp_path <- file.path(OUTPUT_BRANCH, "emp_share_panel_contemporaneous.qs2")
stopifnot(file.exists(emp_path))
message(sprintf("[INFO] %s | loading emp share panel...", Sys.time()))
emp <- qs_read(emp_path)
setDT(emp)
emp[, muni_id := as.integer(muni_id)]
emp[, year    := as.integer(year)]

# Pre-election window definition. Mayoral elections in 2000, 2004, 2008, 2012,
# 2016. Pre-election cycle window for cycle starting at e is [e-4, e-1].
# We approximate: for each year t, classify t as "pre-election" if t mod 4 is
# in {0, 1, 2, 3} relative to the most recent election, i.e., t-1 to t-4 of
# each cycle. Here we adopt: pre-election years are 2002,2003 (cycle 2004),
# 2005-2007 (cycle 2008), 2009-2011 (cycle 2012), 2013-2015 (cycle 2016). For
# simplicity, treat any year strictly less than the next election (year %% 4)
# as pre-election for that cycle.
emp[, election_year := 4L * ceiling(year / 4L)]
emp[election_year %% 4L != 0L, election_year := election_year + (4L - election_year %% 4L)]
# Actual Brazilian mayoral elections: 2000, 2004, 2008, 2012, 2016 (year %% 4 == 0).
emp[, is_pre := (election_year - year) >= 1L & (election_year - year) <= 4L]

# Merge in instrument values per (muni_id, year) for each top-5 instrument.
# An instrument column Z_<off>_<align>_<base>_<sec> varies by (muni, year);
# attach via merge.
key_cols <- c("muni_id", "year")
muni_z <- muni[, c(key_cols, top5_inst), with = FALSE]
pre <- merge(emp[is_pre == TRUE], muni_z, by = key_cols, all.x = TRUE)

pretrend_rows <- list()
for (inst_nm in top5_inst) {
  info <- parse_inst(inst_nm)
  sec  <- info$section
  dat_s <- pre[cnae_section == sec & !is.na(s_emp_jmt)]
  dat_s <- dat_s[!is.na(get(inst_nm))]
  if (!nrow(dat_s)) {
    pretrend_rows[[length(pretrend_rows) + 1L]] <- data.table(
      instrument = inst_nm, cnae_section = sec, office = info$office,
      n_obs = 0L, beta = NA_real_, se = NA_real_,
      t_stat = NA_real_, p_value = NA_real_, status = "no_obs"
    )
    next
  }
  fml <- as.formula(sprintf("s_emp_jmt ~ %s | muni_id + year", inst_nm))
  m <- tryCatch(
    feols(fml, data = dat_s, vcov = ~ muni_id, lean = TRUE),
    error = function(e) NULL
  )
  if (is.null(m)) {
    pretrend_rows[[length(pretrend_rows) + 1L]] <- data.table(
      instrument = inst_nm, cnae_section = sec, office = info$office,
      n_obs = nrow(dat_s), beta = NA_real_, se = NA_real_,
      t_stat = NA_real_, p_value = NA_real_, status = "fit_failed"
    )
    next
  }
  ct_m <- coeftable(m)
  pretrend_rows[[length(pretrend_rows) + 1L]] <- data.table(
    instrument = inst_nm, cnae_section = sec, office = info$office,
    n_obs = nobs(m),
    beta   = ct_m[inst_nm, "Estimate"],
    se     = ct_m[inst_nm, "Std. Error"],
    t_stat = ct_m[inst_nm, "t value"],
    p_value = ct_m[inst_nm, "Pr(>|t|)"],
    status = "ok"
  )
}
pretrend <- rbindlist(pretrend_rows, fill = TRUE)
pretrend[, rejects_5pc := isTRUE(p_value < 0.05), by = seq_len(nrow(pretrend))]
out_pre <- file.path(OUTPUT_BRANCH, "pretrend_high_weight.csv")
fwrite(pretrend, out_pre)
message(sprintf("[INFO] wrote: %s", out_pre))
message("[INFO] pre-trend test results (top-5 sectors):")
print(pretrend)

message(sprintf("[INFO] %s | done.", Sys.time()))
