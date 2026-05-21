#!/usr/bin/env Rscript
# ==============================================================================
# B5_advisor_comparison.R — the 2026-05-14 advisor comparison.
#
# AR test (log_gdp ~ Z's + EC's + vol_ratio | muni + year, cluster muni) with:
#   (a) {M.G} only            -- Wald on Z_MG_* columns
#   (b) {M, G, M.G} stacked   -- one regression, Wald jointly on
#                                Z_M_*, Z_G_*, Z_MG_* columns
# EC is always an included control (every channel in the set contributes its
# EC's). Reports F, p, df, and the AR confidence-set width on a scalar
# composition index where feasible.
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/ar_b5_comparison_<tax>.{csv,tex}
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
message(sprintf("[INFO] %s | B5 advisor comparison | tax=%s", Sys.time(), TAX))

panel <- qs_read(file.path(OUT, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(panel)
stopifnot(nrow(panel) > 0L)
SECTORS_ALL  <- attr(panel, "sectors_all")
SECTORS_KEEP <- attr(panel, "sectors_keep")
panel <- panel[is.finite(log_gdp) & is.finite(vol_ratio)]
stopifnot(nrow(panel) > 0L)
message(sprintf("[INFO] complete-case rows: %s",
                format(nrow(panel), big.mark = ",")))

z_cols  <- function(ch) paste0("Z_",  ch, "_", SECTORS_ALL)
ec_cols <- function(ch) paste0("EC_", ch, "_", SECTORS_KEEP)

# AR regression for an instrument set. EC always present (every channel's EC's),
# vol_ratio always a predetermined control. Wald keyed on all Z_<ch>_ prefixes.
run_ar_set <- function(channels, label) {
  zc  <- unlist(lapply(channels, z_cols))
  ecc <- unlist(lapply(channels, ec_cols))
  rhs <- c(zc, ecc, "vol_ratio")
  fml <- as.formula(sprintf("log_gdp ~ %s | muni_id + year",
                            paste(rhs, collapse = " + ")))
  mod <- tryCatch(
    feols(fml, data = panel, vcov = ~ muni_id, lean = FALSE),
    error = function(e) {
      message(sprintf("[WARN] AR fit failed [%s]: %s",
                      label, conditionMessage(e)))
      NULL
    })
  if (is.null(mod)) stop(sprintf("B5: AR fit failed for set '%s'.", label))
  key <- paste0("^(", paste0("Z_", channels, "_", collapse = "|"), ")")
  wd  <- fixest::wald(mod, keep = key)
  data.table(
    set      = label,
    channels = paste(channels, collapse = ","),
    ar_F     = as.numeric(wd$stat),
    ar_p     = as.numeric(wd$p),
    df1      = as.integer(wd$df1),
    df2      = as.integer(wd$df2),
    K_Z      = length(zc),
    n_obs    = nobs(mod),
    reject_5pc = isTRUE(as.numeric(wd$p) < 0.05))
}

res_a <- run_ar_set("MG",                "MG only")
res_b <- run_ar_set(c("M", "G", "MG"),   "M, G, MG stacked")
out <- rbindlist(list(res_a, res_b))

message("\n[RESULT] B5 advisor comparison:")
print(out)

# --- AR confidence-set width on a scalar composition index -------------------
# The AR confidence-set width on a scalar composition index is not computed in
# this exploration: the muni AR panel carries no scalar share index, so a 1-D
# AR grid is not feasible without re-deriving shares. The F/p/df comparison is
# the deliverable; width columns are written as NA for schema stability.
out[, ar_ci_lo := NA_real_]
out[, ar_ci_hi := NA_real_]
out[, ar_ci_width := NA_real_]
out[, ci_note := "scalar-index AR CI not feasible from muni wide panel"]

fwrite(out, file.path(OUT, sprintf("ar_b5_comparison_%s.csv", TAX)))

# --- Bare-tabular .tex (INV-13) ---------------------------------------------
# fmt_n() comes from 00_helpers.R.

lines <- c(
  "\\begin{tabular}{@{}lccccc@{}}",
  "\\toprule",
  paste0("Instrument set & AR $F$ & $p$-value & d.f. & ",
         "$K_Z$ & Reject (5\\%) \\\\"),
  "\\midrule")
set_label <- c(`MG only` = "$M\\cdot G$ only",
               `M, G, MG stacked` = "$M$, $G$, $M\\cdot G$ stacked")
for (i in seq_len(nrow(out))) {
  r <- out[i]
  lines <- c(lines, sprintf(
    "%s & %s & %s & %d, %s & %d & %s \\\\",
    set_label[[r$set]], fmt_n(r$ar_F, 3), fmt_n(r$ar_p, 4),
    r$df1, format(r$df2, big.mark = ","), r$K_Z,
    if (isTRUE(r$reject_5pc)) "Yes" else "No"))
}
lines <- c(lines, "\\bottomrule", "\\end{tabular}")
writeLines(lines, file.path(OUT, sprintf("ar_b5_comparison_%s.tex", TAX)))
message(sprintf("[INFO] wrote ar_b5_comparison_%s.{csv,tex}", TAX))

# Characterisation.
sharper <- if (out$ar_p[1L] < out$ar_p[2L]) "MG only" else "M,G,MG stacked"
message(sprintf("[RESULT] sharper test (lower p): %s  (MG-only p=%.4g vs stacked p=%.4g)",
                sharper, out$ar_p[1L], out$ar_p[2L]))
message(sprintf("[INFO] %s | B5 done.", Sys.time()))
