#!/usr/bin/env Rscript
# ==============================================================================
# B3_volume_first_stage.R — saturated first stage of VOLUME.
#
# Endogenous = Vol_mt (vol_ratio). Scalar form: regress Vol_mt on the seven
# muni-aggregated channels Zbar_c = sum_j Z^c_{jmt} (one regressor per channel),
#   FE   = muni + year
#   vcov = cluster by muni.
# Reports per-channel coefficient, SE, partial F (cluster-robust Wald).
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/ar_first_stage_vol_<tax>.{tex,csv}
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})
setDTthreads(0L)
fixest::setFixest_nthreads(4L)
set.seed(20260520L)

source_helpers <- function() {
  a  <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (!length(fa)) stop("Run via Rscript.")
  this <- normalizePath(sub("^--file=", "", fa[[1L]]),
                        winslash = "/", mustWork = TRUE)
  source(file.path(dirname(this), "00_helpers.R"))
}
source_helpers()  # provides get_this_script(), parse_kv(), fmt_*, SIZE_CYCLES

THIS <- get_this_script()
BR   <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
OUT  <- file.path(BR, "output")

TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "policy_block_size_bin"))
message(sprintf("[INFO] %s | B3 volume first stage | tax=%s", Sys.time(), TAX))

CHANNELS <- all_channels()

# --- Load panel, build Zbar_c = sum_j Z^c_jmt --------------------------------

panel <- qs_read(file.path(OUT, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(panel)
stopifnot(nrow(panel) > 0L)
panel <- panel[is.finite(log_gdp) & is.finite(vol_ratio)]
stopifnot(nrow(panel) > 0L)
message(sprintf("[INFO] complete-case rows: %s",
                format(nrow(panel), big.mark = ",")))

for (ch in CHANNELS) {
  zc <- grep(paste0("^Z_", ch, "_"), names(panel), value = TRUE)
  panel[, (paste0("Zbar_", ch)) := rowSums(.SD), .SDcols = zc]
}
zbar_cols <- paste0("Zbar_", CHANNELS)

# --- Scalar saturated volume first stage -------------------------------------

fml <- as.formula(sprintf("vol_ratio ~ %s | muni_id + year",
                          paste(zbar_cols, collapse = " + ")))
mod <- tryCatch(
  feols(fml, data = panel, vcov = ~ muni_id, lean = FALSE),
  error = function(e) {
    message(sprintf("[WARN] volume first-stage fit failed: %s",
                    conditionMessage(e)))
    NULL
  })
if (is.null(mod)) stop("B3: volume first-stage fit failed.")
ct  <- coeftable(mod)

per <- vector("list", length(CHANNELS))
for (i in seq_along(CHANNELS)) {
  zt <- zbar_cols[[i]]
  wd <- tryCatch(fixest::wald(mod, keep = paste0("^", zt, "$")),
                 error = function(e) NULL)
  per[[i]] <- data.table(
    channel = CHANNELS[[i]],
    channel_label = channel_label_plain(CHANNELS[[i]]),
    term = zt,
    coef = if (zt %in% rownames(ct)) ct[zt, "Estimate"]   else NA_real_,
    se   = if (zt %in% rownames(ct)) ct[zt, "Std. Error"] else NA_real_,
    tstat = if (zt %in% rownames(ct)) ct[zt, 3L]          else NA_real_,
    pval = if (zt %in% rownames(ct)) ct[zt, 4L]           else NA_real_,
    F_partial = if (!is.null(wd)) as.numeric(wd$stat) else NA_real_,
    p_partial = if (!is.null(wd)) as.numeric(wd$p)    else NA_real_)
}
per <- rbindlist(per)
per[, relevant_5pc := is.finite(p_partial) & p_partial < 0.05]
per[, n_obs := nobs(mod)]
# Guard the joint Wald F against rank-deficiency (near-singular VCV over the
# collinear stacked channels). When flagged, store NA for joint F/p.
w_all <- fixest::wald(mod, keep = "^Zbar_")
joint_F_vol <- as.numeric(w_all$stat)
joint_p_vol <- as.numeric(w_all$p)
joint_rd_vol <- joint_F_rank_deficient(joint_F_vol)
if (joint_rd_vol) {
  message(sprintf(
    "[WARN] volume joint F over 7 Zbar is rank-deficient (F=%.3g); reporting NA.",
    joint_F_vol))
  joint_F_vol <- NA_real_
  joint_p_vol <- NA_real_
}
per[, joint_F_7chan := joint_F_vol]
per[, joint_p_7chan := joint_p_vol]
per[, joint_rank_deficient := joint_rd_vol]

message("\n[RESULT] B3 saturated volume first stage:")
print(per[, .(channel_label, coef = signif(coef, 3), se = signif(se, 3),
              F_partial = round(F_partial, 2),
              p_partial = round(p_partial, 4), relevant_5pc)])
if (joint_rd_vol) {
  message("[RESULT] joint F on all 7 Zbar: rank-deficient (collinear channels)")
} else {
  message(sprintf("[RESULT] joint F on all 7 Zbar: %.3f (p=%.4g)",
                  joint_F_vol, joint_p_vol))
}

fwrite(per, file.path(OUT, sprintf("ar_first_stage_vol_%s.csv", TAX)))

# --- Bare-tabular .tex (INV-13) ---------------------------------------------
# fmt_n() / fmt_g() come from 00_helpers.R.

lines <- c(
  "\\begin{tabular}{@{}lccccc@{}}",
  "\\toprule",
  "Channel & Coefficient & Std. error & Partial $F$ & $p$-value & Relevant \\\\",
  "\\midrule")
for (i in seq_len(nrow(per))) {
  r <- per[i]
  lines <- c(lines, sprintf(
    "%s & %s & %s & %s & %s & %s \\\\",
    channel_label(r$channel), fmt_g(r$coef), fmt_g(r$se),
    fmt_n(r$F_partial, 2), fmt_n(r$p_partial, 3),
    if (isTRUE(r$relevant_5pc)) "Yes" else "No"))
}
joint_cell <- if (isTRUE(per$joint_rank_deficient[1L])) {
  "Rank-deficient (collinear channels)"
} else {
  sprintf("$F=%s$, $p=%s$",
          fmt_n(per$joint_F_7chan[1L], 2), fmt_n(per$joint_p_7chan[1L], 4))
}
lines <- c(lines, "\\midrule",
  sprintf("Joint ($7$ channels) & \\multicolumn{5}{c}{%s} \\\\", joint_cell),
  "\\bottomrule", "\\end{tabular}")
writeLines(lines, file.path(OUT, sprintf("ar_first_stage_vol_%s.tex", TAX)))
message(sprintf("[INFO] wrote ar_first_stage_vol_%s.{tex,csv}", TAX))
message(sprintf("[INFO] %s | B3 done.", Sys.time()))
