#!/usr/bin/env Rscript
# ==============================================================================
# run_phase_bc.R — master runner for Phases 1A / 1B / 2 of the AR-test
# follow-up. The phases are run in three gated passes, not straight through:
# each pass ends at a mandatory user checkpoint, so the runner cannot skip a
# checkpoint.
#
#   --phase=1a  (default)
#     build 01 -> 02 -> 03 (unless --skip-build), then, for each margin:
#       B2, B3        : stacked-long first stages   (descriptive companion)
#       B2b, B3b      : multi-channel first stages   (descriptive companion)
#       B5            : advisor comparison           (descriptive companion)
#       B7            : instrument-collinearity diagnosis
#     C3 coverage audit at the 12-group margin.
#     >>> STOP for checkpoint #1: review the collinearity diagnosis and prune
#         the instrument set before Phase 1B.
#
#   --phase=1b
#     after checkpoint #1, for each margin:
#       B8            : wide-form first stage (SW F + KP rank), user-pruned set
#       B4            : channel routing on the wide-form verdict
#     >>> STOP for checkpoint #2: choose the composition instrument set(s).
#
#   --phase=2
#     after checkpoint #2, for each margin:
#       B6            : three-volume AR test on the user-chosen set(s)
#
# B2, B2b, B3, B3b, B5 remain in the Phase 1A pass as descriptive companions —
# they no longer feed the routing rule or the exclusion diagnostic.
#
# Usage:  Rscript R/run_phase_bc.R [--phase={1a,1b,2}] [--skip-build]
#   --phase      : which gated pass to run (default 1a)
#   --skip-build : skip 01/02/03 (reuse existing built panels); Phase 1A only
# ==============================================================================

get_this_script <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (length(fa)) return(normalizePath(sub("^--file=", "", fa[[1L]]),
                                       winslash = "/", mustWork = TRUE))
  stop("Run via Rscript.")
}
THIS <- get_this_script()
RDIR <- dirname(THIS)
cli  <- commandArgs(trailingOnly = TRUE)
SKIP_BUILD <- "--skip-build" %in% cli

phase_hit <- grep("^--phase=", cli, value = TRUE)
PHASE <- if (length(phase_hit)) sub("^--phase=", "", phase_hit[[1L]]) else "1a"
stopifnot(PHASE %in% c("1a", "1b", "2"))

MARGINS <- c("policy_block", "policy_block_size_bin")

run_step <- function(script, tax) {
  cmd <- sprintf('"%s" "%s" --tax=%s',
                 file.path(R.home("bin"), "Rscript"),
                 file.path(RDIR, script), tax)
  message(sprintf("\n>>> %s  [tax=%s]", script, tax))
  status <- system(cmd)
  if (status != 0L)
    stop(sprintf("step failed: %s (tax=%s, exit %d)", script, tax, status))
}

build_steps   <- c("01_build_variant_a_weights.R",
                   "02_build_instruments_ec.R",
                   "03_build_muni_ar_panel.R")
phase1a_steps <- c("B2_composition_first_stage.R",
                   "B3_volume_first_stage.R",
                   "B2b_composition_multichannel.R",
                   "B3b_volume_multichannel.R",
                   "B5_advisor_comparison.R",
                   "B7_collinearity_diagnosis.R")
phase1b_steps <- c("B8_wide_first_stage.R",
                   "B4_channel_routing.R")
phase2_steps  <- c("B6_three_volume_ar.R")

if (identical(PHASE, "1a")) {
  message("=========== PHASE 1A: collinearity diagnosis ===========")
  for (tax in MARGINS) {
    message(sprintf("\n----------- MARGIN: %s -----------", tax))
    if (!SKIP_BUILD) for (s in build_steps) run_step(s, tax)
    for (s in phase1a_steps) run_step(s, tax)
  }
  run_step("C3_coverage_audit.R", "policy_block_size_bin")
  message("\n[CHECKPOINT #1] Phase 1A complete. Review the collinearity ",
          "diagnosis (collinearity_diagnosis_*.{csv,tex}, ",
          "instrument_admissibility_*.csv) and prune the instrument set ",
          "before running Phase 1B (--phase=1b).")

} else if (identical(PHASE, "1b")) {
  message("=========== PHASE 1B: wide-form first stage ===========")
  for (tax in MARGINS) {
    message(sprintf("\n----------- MARGIN: %s -----------", tax))
    for (s in phase1b_steps) run_step(s, tax)
  }
  message("\n[CHECKPOINT #2] Phase 1B complete. Choose the composition ",
          "instrument set(s) before running Phase 2 (--phase=2).")

} else {
  message("=========== PHASE 2: AR test extension ===========")
  for (tax in MARGINS) {
    message(sprintf("\n----------- MARGIN: %s -----------", tax))
    for (s in phase2_steps) run_step(s, tax)
  }
}

message(sprintf("\n[INFO] run_phase_bc.R complete (phase %s).", PHASE))
