#!/usr/bin/env Rscript

# ==============================================================================
# 04_slack_robustness.R
# B1.4.2 - Slack-control on/off sensitivity for the AR test.
#
# Per BHJ 2022 §4.4 (incomplete shares), when the sum of exposure weights does
# not equal one (because s_jmt uses contemporaneous denom but w_jm,tau uses
# frozen denom), variation in the slack between the two denominators can
# contaminate the instrument. The standard correction is to include the
# sum-of-exposure-shares as a control. In the *contemporaneous* variant this
# slack is mechanically 1 (the s_jmt denominator is the same universe as itself);
# in *frozen* and *balanced* it has muni-year variance and is the operative
# control to verify.
#
# This script runs the full AR for all {variant} x {outcome} x {FE} cells with
# and without the slack control, side-by-side. The on/off comparison is most
# informative for frozen / balanced.
#
# Inputs / Outputs follow 02_ar_test_emp_share.R conventions.
# Output:
#   output/slack_robustness.csv with one row per
#   (variant, outcome, fe_spec, slack_included) cell.
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

set.seed(20260512L)
setDTthreads(0L)
fixest::setFixest_nthreads(4L)

# ---- Spec grid ---------------------------------------------------------------

VARIANTS  <- c("contemporaneous", "frozen", "balanced")
OUTCOMES  <- c("log_gdp", "delta_log_gdp")
FE_SPECS  <- c("muni_year", "year_only")
BASELINE  <- "cycle_specific"
ALIGNMENT <- "coalition"
FLAVOR    <- "MGP"
OFFICES   <- c("mayor", "gov", "pres")

# ---- Load muni panel ---------------------------------------------------------

muni_path <- output_path("muni_panel_for_regs.qs2")
stopifnot(file.exists(muni_path))
message(sprintf("[INFO] %s | loading muni panel...", Sys.time()))
muni <- qs_read(muni_path)
setDT(muni)
muni[, muni_id := as.integer(muni_id)]
muni[, year    := as.integer(year)]
muni <- muni[muni_id > 0L]

inst_prefix <- sprintf("Z_mayor_%s_%s_", ALIGNMENT, BASELINE)
sec_cols <- grep(paste0("^", inst_prefix, "[A-Z]$"), names(muni), value = TRUE)
SECTIONS <- sort(sub(paste0("^", inst_prefix), "", sec_cols))
HOLDOUT  <- SECTIONS[length(SECTIONS)]
SECTIONS_KEEP <- setdiff(SECTIONS, HOLDOUT)

build_inst_cols <- function(offices, sections) {
  out <- character()
  for (off in offices) for (s in sections) {
    out <- c(out, sprintf("Z_%s_%s_%s_%s", off, ALIGNMENT, BASELINE, s))
  }
  out
}
INST_COLS <- build_inst_cols(OFFICES, SECTIONS_KEEP)
stopifnot(all(INST_COLS %in% names(muni)))

# Volume control + delta.
setorder(muni, muni_id, year)
init_gdp <- muni[!is.na(pib_real),
                 .(initial_gdp = pib_real[1L]), by = muni_id]
muni <- merge(muni, init_gdp, by = "muni_id", all.x = TRUE)
muni[, vol_ratio := total_bndes_real / initial_gdp]
muni[!is.finite(vol_ratio), vol_ratio := NA_real_]
muni[, delta_log_gdp := log_gdp - shift(log_gdp, type = "lag"), by = muni_id]

# ---- Slack loader (mirrors 02_*.R) ------------------------------------------

load_slack <- function(variant) {
  pth <- file.path(OUTPUT_BRANCH, sprintf("slack_per_cell_%s.csv", variant))
  stopifnot(file.exists(pth))
  s <- fread(pth)
  s[, muni_id := as.integer(muni_id)]
  s[, year    := as.integer(year)]
  cols <- names(s)
  has_sector <- any(c("cnae_section", "sector", "sector_group") %in% cols)
  group_keys <- c("muni_id", "year")
  if (has_sector) {
    sec_col <- intersect(c("cnae_section","sector","sector_group"), cols)[1L]
    s <- s[, .(slack_share = mean(slack_share, na.rm = TRUE)),
           by = c(group_keys, sec_col)]
    s <- s[, .(slack_share = mean(slack_share, na.rm = TRUE)),
           by = group_keys]
  } else {
    s <- s[, .(slack_share = mean(slack_share, na.rm = TRUE)),
           by = group_keys]
  }
  s[!is.finite(slack_share), slack_share := NA_real_]
  s
}

z_pattern <- sprintf("^Z_(%s)_%s_%s_",
                     paste(OFFICES, collapse = "|"), ALIGNMENT, BASELINE)

run_one <- function(variant, outcome, fe_spec, slack_included) {
  fe_term <- if (identical(fe_spec, "muni_year")) "muni_id + year" else "year"
  dat <- copy(muni)
  if (slack_included) {
    s <- load_slack(variant)
    dat <- merge(dat, s, by = c("muni_id", "year"), all.x = TRUE)
  }
  keep <- c("muni_id", "year", outcome, "vol_ratio", INST_COLS)
  if (slack_included) keep <- c(keep, "slack_share")
  dat <- dat[, ..keep]
  base_complete <- setdiff(keep, "slack_share")
  dat <- dat[complete.cases(dat[, .SD, .SDcols = base_complete])]
  if (slack_included) dat <- dat[!is.na(slack_share)]
  if (!nrow(dat)) {
    return(data.table(variant = variant, outcome = outcome, fe_spec = fe_spec,
                      slack_included = slack_included, status = "empty"))
  }
  rhs <- c(INST_COLS, "vol_ratio")
  if (slack_included) rhs <- c(rhs, "slack_share")
  fml <- as.formula(paste0(outcome, " ~ ",
                           paste(rhs, collapse = " + "),
                           " | ", fe_term))
  mod <- tryCatch(
    feols(fml, data = dat, vcov = ~ muni_id, lean = TRUE),
    error = function(e) NULL
  )
  if (is.null(mod)) {
    return(data.table(variant = variant, outcome = outcome, fe_spec = fe_spec,
                      slack_included = slack_included, status = "fit_failed"))
  }
  w <- tryCatch(fixest::wald(mod, keep = z_pattern), error = function(e) NULL)
  ar_F <- if (!is.null(w)) as.numeric(w$stat) else NA_real_
  ar_p <- if (!is.null(w)) as.numeric(w$p)    else NA_real_
  n_collin <- length(mod$collin.var)
  data.table(
    variant = variant, outcome = outcome, fe_spec = fe_spec,
    slack_included = slack_included, status = "ok",
    n_obs = nobs(mod),
    n_munis = uniqueN(dat$muni_id),
    K = length(INST_COLS),
    n_collinear = n_collin,
    ar_F = ar_F, ar_p = ar_p,
    rejects_5pc = isTRUE(ar_p < 0.05)
  )
}

results <- list()
for (variant in VARIANTS) {
  for (outcome in OUTCOMES) {
    for (fe_spec in FE_SPECS) {
      for (slack_in in c(FALSE, TRUE)) {
        tag <- sprintf("[%s|%s|%s|slack=%s]",
                       variant, outcome, fe_spec, slack_in)
        message(sprintf("[INFO] %s | %s", Sys.time(), tag))
        res <- run_one(variant, outcome, fe_spec, slack_in)
        if (identical(res$status, "ok")) {
          message(sprintf("       AR_F=%.3f AR_p=%.4g coll=%d n=%d",
                          res$ar_F, res$ar_p, res$n_collinear, res$n_obs))
        } else {
          message(sprintf("       status=%s", res$status))
        }
        results[[length(results) + 1L]] <- res
      }
    }
  }
}
out <- rbindlist(results, fill = TRUE)
out_path <- file.path(OUTPUT_BRANCH, "slack_robustness.csv")
fwrite(out, out_path)
message(sprintf("[INFO] wrote: %s", out_path))

# Quick on/off comparison (frozen + balanced are the informative cells).
message("[INFO] frozen / balanced on-vs-off comparison (log_gdp, muni_year):")
comp <- dcast(
  out[variant %in% c("frozen", "balanced") & outcome == "log_gdp" &
      fe_spec == "muni_year" & status == "ok"],
  variant ~ slack_included,
  value.var = c("ar_F", "ar_p", "rejects_5pc")
)
print(comp)

message(sprintf("[INFO] %s | done.", Sys.time()))
