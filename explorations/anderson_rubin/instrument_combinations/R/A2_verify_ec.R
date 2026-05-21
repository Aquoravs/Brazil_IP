#!/usr/bin/env Rscript
# ==============================================================================
# A2_verify_ec.R — EC adequacy audit, built-object verification (plan A1/A2/A4).
#
# Confirms, on the actually-built objects of the ar_meeting_2026_05_13 pipeline:
#   (A1) EC = sum_p of the SAME muni-relative weight as the instrument Z.
#   (A2) The pipeline carries the sum-of-shares EC and NO `slack` column;
#        sum_j EC^c_{jm,t} = 1 exactly (muni-relative denominator => no
#        muni-level unaffiliated residual).
#   (A4) The exposure window T_Fc is strictly pre-year-t (predetermined).
#
# Reads built artefacts from ../ar_meeting_2026_05_13/output/. Writes nothing
# to that folder. Diagnostics -> instrument_combinations/output/.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})
setDTthreads(0L)

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

log_line <- function(...) message(sprintf(...))
report   <- character(0)
add_rep  <- function(...) report <<- c(report, sprintf(...))

log_line("[INFO] %s | A2 verify EC | tax=%s", Sys.time(), TAX)

# --- Load built objects ------------------------------------------------------

w     <- qs_read(file.path(ARO, sprintf("weights_variant_a_%s.qs2", TAX)))
Z     <- qs_read(file.path(ARO, sprintf("Z_variant_a_%s.qs2",  TAX)))
EC    <- qs_read(file.path(ARO, sprintf("EC_variant_a_%s.qs2", TAX)))
panel <- qs_read(file.path(ARO, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(w); setDT(Z); setDT(EC); setDT(panel)

# ============================================================================
# A1 — EC = sum_p of the same muni-relative weight as Z.
# Recompute EC directly from the weights table and compare to the saved EC.
# ============================================================================

ec_recomputed <- w[, .(EC_recomp = sum(w_tilde, na.rm = TRUE)),
                   by = .(muni_id, year, channel, sector)]
chk <- merge(EC, ec_recomputed,
             by = c("muni_id", "year", "channel", "sector"), all = TRUE)
chk[is.na(EC_val),    EC_val    := 0]
chk[is.na(EC_recomp), EC_recomp := 0]
max_abs_dev <- chk[, max(abs(EC_val - EC_recomp))]
add_rep("A1  EC == sum_p w_tilde (recomputed vs saved): max abs dev = %.3e %s",
        max_abs_dev, if (max_abs_dev < 1e-9) "[PASS]" else "[FAIL]")

# Same weight feeds Z: the build joins one weights table; Z uses w_tilde*Align,
# EC uses w_tilde. Confirm the weights table has exactly the expected columns.
add_rep("A1  weights table columns: %s", paste(names(w), collapse = ", "))
add_rep("A1  channels in weights: %s", paste(sort(unique(w$channel)), collapse = ", "))

# ============================================================================
# A2 — sum-of-shares EC; no `slack` column; sum_j EC = 1.
# ============================================================================

# (i) No `slack`-type column anywhere in the carried artefacts.
slack_hits <- unique(c(
  grep("slack", names(w),     value = TRUE, ignore.case = TRUE),
  grep("slack", names(Z),     value = TRUE, ignore.case = TRUE),
  grep("slack", names(EC),    value = TRUE, ignore.case = TRUE),
  grep("slack", names(panel), value = TRUE, ignore.case = TRUE)
))
add_rep("A2  `slack`-type columns carried in pipeline: %s",
        if (length(slack_hits)) paste(slack_hits, collapse = ", ")
        else "NONE [PASS — correct for muni-relative weight]")

# (ii) sum_j EC^c_{jm,t} over the FULL sector set = 1 exactly (muni-relative
# denominator excludes unaffiliated owners => no muni-level slack).
sum_ec <- EC[, .(sum_EC = sum(EC_val, na.rm = TRUE)),
             by = .(muni_id, year, channel)]
n_unit <- sum_ec[abs(sum_EC - 1) <= 1e-6, .N]
n_zero <- sum_ec[abs(sum_EC)     <= 1e-6, .N]
n_bad  <- sum_ec[abs(sum_EC - 1) > 1e-6 & abs(sum_EC) > 1e-6, .N]
add_rep("A2  sum_j EC over full sector set: n(=1)=%d  n(=0)=%d  n(other)=%d %s",
        n_unit, n_zero, n_bad, if (n_bad == 0L) "[PASS]" else "[FAIL]")

# (iii) Per-sector incomplete-shares: EC_jm in [0,1] and < 1 with mass.
add_rep("A2  per-sector EC_val range: [%.4f, %.4f]; mean = %.4f",
        EC[, min(EC_val)], EC[, max(EC_val)], EC[, mean(EC_val)])
add_rep(paste0("A2  share of cells with EC_val strictly in (0,1): %.1f%% ",
               "(incomplete shares => per-sector EC is the BHJ control)"),
        100 * EC[EC_val > 1e-9 & EC_val < 1 - 1e-9, .N] / EC[, .N])

# ============================================================================
# A3 — panel regression structure: one EC per retained sector, hold-out
# consistent between Z and EC.
# ============================================================================

HOLDOUT <- attr(panel, "holdout_sector")
KEEP    <- attr(panel, "sectors_keep")
z_cols  <- grep("^Z_",  names(panel), value = TRUE)
ec_cols <- grep("^EC_", names(panel), value = TRUE)
add_rep("A3  hold-out sector: %s; retained: %s", HOLDOUT, paste(KEEP, collapse = ", "))
add_rep("A3  panel Z columns (%d): %s", length(z_cols), paste(z_cols, collapse = ", "))
add_rep("A3  panel EC columns (%d): %s", length(ec_cols), paste(ec_cols, collapse = ", "))
z_secs  <- sort(unique(sub("^Z_[A-Za-z]+_",  "", z_cols)))
ec_secs <- sort(unique(sub("^EC_[A-Za-z]+_", "", ec_cols)))
add_rep("A3  Z sector set == EC sector set == retained set: %s",
        if (identical(z_secs, ec_secs) && identical(z_secs, sort(KEEP)))
          "[PASS]" else "[FAIL]")

# ============================================================================
# A4 — predeterminedness: T_Fc window strictly before year t.
# ============================================================================

win <- unique(w[, .(year, channel, T_Fc_lo, T_Fc_hi)])
n_leak <- win[T_Fc_hi >= year, .N]
add_rep("A4  window rows with T_Fc_hi >= t (contemporaneous leakage): %d %s",
        n_leak, if (n_leak == 0L) "[PASS]" else "[FAIL]")
add_rep("A4  window span: T_Fc_hi - t ranges [%d, %d] (all negative => pre-t)",
        win[, min(T_Fc_hi - year)], win[, max(T_Fc_hi - year)])

# --- Write report ------------------------------------------------------------

writeLines(c("# A2 EC adequacy — built-object verification",
             sprintf("# generated %s | tax=%s", Sys.time(), TAX),
             "", report),
           file.path(OUT, "A2_ec_verification.txt"))
log_line("\n%s", paste(report, collapse = "\n"))
log_line("[INFO] wrote output/A2_ec_verification.txt")
log_line("[INFO] %s | done.", Sys.time())
