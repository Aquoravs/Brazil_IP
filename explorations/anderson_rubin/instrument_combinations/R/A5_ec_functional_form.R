#!/usr/bin/env Rscript
# ==============================================================================
# A5_ec_functional_form.R — EC adequacy audit, functional-form sensitivity.
#
# The AR test enters the exposure control (EC) linearly in production
# (`04_run_ar_regressions.R`, specs `ec` / `vol_ec`). A5 re-runs the AR test
# with the EC entered four ways and checks the AR conclusion is stable:
#
#   none    : no EC                                  (uncontrolled benchmark)
#   linear  : + EC_<ch>_<sec>                         (production form)
#   quad    : + EC + EC^2 per retained sector         (low-order polynomial)
#   bins    : + EC tercile dummies per retained sector (flexible / non-param)
#
# Each EC form is run with and without the volume control. AR statistic =
# cluster-robust (muni) joint Wald F on the channel's Z's only. If the AR
# rejection verdict and F are stable across forms, "EC dependence" is not a
# concern (plan A5). If the verdict flips, escalate.
#
# Reads the built panel from ../ar_meeting_2026_05_13/output/. Writes to
# instrument_combinations/output/.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})
setDTthreads(0L)
fixest::setFixest_nthreads(4L)
set.seed(20260520L)  # deterministic run; seed set once for convention.

get_this_script <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (length(fa)) return(normalizePath(sub("^--file=", "", fa[[1L]]),
                                       winslash = "/", mustWork = TRUE))
  stop("Run via Rscript.")
}
THIS <- get_this_script()
BR   <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
ARO  <- normalizePath(file.path(BR, "..", "ar_meeting_2026_05_13", "output"),
                      winslash = "/", mustWork = TRUE)
OUT  <- file.path(BR, "output")
TAX  <- "policy_block"

message(sprintf("[INFO] %s | A5 EC functional form | tax=%s", Sys.time(), TAX))

panel <- qs_read(file.path(ARO, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(panel)
KEEP <- attr(panel, "sectors_keep")
# Same complete-case sample as 04_run_ar_regressions.R.
panel <- panel[is.finite(log_gdp) & is.finite(vol_ratio)]
message(sprintf("[INFO] complete-case rows: %s; retained sectors: %s",
                format(nrow(panel), big.mark = ","), paste(KEEP, collapse = ", ")))

CHANNELS  <- c("M", "MP", "MG", "MGP")
EC_FORMS  <- c("none", "linear", "quad", "bins")

z_cols  <- function(ch) paste0("Z_",  ch, "_", KEEP)
ec_cols <- function(ch) paste0("EC_", ch, "_", KEEP)

# --- Build quadratic and binned EC transforms (per channel × sector) --------
# EC^2 columns and tercile-dummy columns are precomputed into the panel so the
# regression formula can name them directly.

for (ch in CHANNELS) {
  for (sec in KEEP) {
    ec <- paste0("EC_", ch, "_", sec)
    panel[, paste0(ec, "_sq") := get(ec)^2]
    # Terciles on the nonzero support; degenerate cuts collapse to one bin.
    brks <- quantile(panel[[ec]], probs = c(0, 1/3, 2/3, 1),
                     na.rm = TRUE, type = 7)
    brks <- unique(brks)
    if (length(brks) >= 3L) {
      panel[, paste0(ec, "_bin") :=
              cut(get(ec), breaks = brks, include.lowest = TRUE,
                  labels = FALSE)]
    } else {
      panel[, paste0(ec, "_bin") := 1L]  # degenerate: single bin
    }
    panel[, paste0(ec, "_bin") := factor(get(paste0(ec, "_bin")))]
  }
}

ec_rhs <- function(ch, form) {
  ecs <- ec_cols(ch)
  switch(form,
    none   = character(0),
    linear = ecs,
    quad   = c(ecs, paste0(ecs, "_sq")),
    bins   = paste0("i(", paste0(ecs, "_bin"), ")"),
    stop("bad form"))
}

# --- Run one AR regression ---------------------------------------------------

run_one <- function(ch, form, with_vol) {
  zcs <- z_cols(ch)
  rhs <- c(zcs, ec_rhs(ch, form))
  if (with_vol) rhs <- c(rhs, "vol_ratio")
  fml <- as.formula(paste0("log_gdp ~ ", paste(rhs, collapse = " + "),
                           " | muni_id + year"))
  mod <- tryCatch(feols(fml, data = panel, vcov = ~ muni_id),
                  error = function(e) {
                    message(sprintf("[WARN] fit failed [%s/%s/vol=%s]: %s",
                                    ch, form, with_vol, conditionMessage(e)))
                    NULL
                  })
  if (is.null(mod)) return(NULL)
  w <- tryCatch(fixest::wald(mod, keep = paste0("^Z_", ch, "_")),
                error = function(e) NULL)
  data.table(
    channel  = ch,
    ec_form  = form,
    with_vol = with_vol,
    K_Z      = length(zcs),
    n_params = length(rhs),
    n_obs    = nobs(mod),
    ar_F     = if (!is.null(w)) as.numeric(w$stat) else NA_real_,
    ar_p     = if (!is.null(w)) as.numeric(w$p)    else NA_real_
  )
}

results <- list()
for (ch in CHANNELS) for (form in EC_FORMS) for (wv in c(FALSE, TRUE)) {
  r <- run_one(ch, form, wv)
  if (is.null(r)) next
  results[[length(results) + 1L]] <- r
  message(sprintf("  %-4s %-7s vol=%-5s  AR_F=%8.3f  AR_p=%.4g",
                  ch, form, wv, r$ar_F, r$ar_p))
}
res <- rbindlist(results)
res[, reject_5pc := ar_p < 0.05]

fwrite(res, file.path(OUT, "A5_ec_functional_form.csv"))
message(sprintf("[INFO] wrote output/A5_ec_functional_form.csv (%d rows)",
                nrow(res)))

# --- Stability summary -------------------------------------------------------
# The A5 question is whether the AR verdict moves with the EC FUNCTIONAL FORM.
# The comparison set is {linear, quad, bins} — three ways to enter the same
# predetermined EC. `none` is the uncontrolled benchmark (no EC at all): it is
# reported separately, not part of the stability test, since EC presence vs
# absence is a different question from EC functional form.

EC_FORM_SET <- c("linear", "quad", "bins")
flip_flag <- FALSE

summarise_channel <- function(ch) {
  sub <- res[channel == ch]
  msgs <- character(0)
  for (wv in c(FALSE, TRUE)) {
    s_ec   <- sub[with_vol == wv & ec_form %in% EC_FORM_SET]
    s_none <- sub[with_vol == wv & ec_form == "none"]
    fr     <- range(s_ec$ar_F)
    stable <- uniqueN(s_ec$reject_5pc) == 1L
    if (!stable) flip_flag <<- TRUE
    msgs <- c(msgs, sprintf(
      paste0("  %-4s vol=%-5s | EC-forms AR_F in [%.3f, %.3f] (spread %.3f), ",
             "reject@5%%: %s %s | benchmark none: F=%.3f p=%.4g"),
      ch, wv, fr[1], fr[2], diff(fr),
      paste(s_ec$reject_5pc, collapse = "/"),
      if (stable) "[STABLE]" else "[FLIP — escalate]",
      s_none$ar_F, s_none$ar_p))
  }
  msgs
}

stab <- unlist(lapply(CHANNELS, summarise_channel))
verdict_global <- if (flip_flag) {
  "CONCLUSION FLIPS across EC functional forms — escalate (Phase C primary)."
} else {
  paste("CONCLUSION STABLE across EC functional forms (linear/quad/bins) for",
        "every channel x volume combination — EC functional-form dependence is",
        "not a concern.")
}

rep_lines <- c(
  "# A5 — EC functional-form sensitivity",
  sprintf("# generated %s | tax=%s", Sys.time(), TAX),
  "",
  "EC functional forms compared: linear (production) / quad (EC + EC^2) /",
  "bins (EC terciles). `none` = no EC (uncontrolled benchmark, reported but",
  "outside the stability test).",
  "AR statistic = muni-clustered joint Wald F on the channel's Z's.",
  "",
  stab,
  "",
  verdict_global)
writeLines(rep_lines, file.path(OUT, "A5_ec_functional_form_summary.txt"))
message(sprintf("\n%s", paste(rep_lines, collapse = "\n")))
message(sprintf("[INFO] %s | done.", Sys.time()))
