#!/usr/bin/env Rscript

# ==============================================================================
# Manual tests for scripts/R/_utils/load_firm_panel.R
# ==============================================================================
# Runs the six scenarios specified in Unit 1 of plan
# 2026-04-14-002-refactor-firm-panel-split-files-plan.md. Each test prints
# PASS / FAIL / SKIP. SKIP means the on-disk prerequisite is missing (e.g. the
# split files haven't been produced yet by Unit 2). Run with:
#
#   Rscript scripts/R/_utils/test_load_firm_panel.R
#
# or source interactively after sourcing load_firm_panel.R.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# --- Bootstrap ----------------------------------------------------------------

bootstrap_file <- local({
  project_root_opt <- getOption("politicsregs.project_root", default = NULL)
  if (is.character(project_root_opt) && length(project_root_opt) == 1L && nzchar(project_root_opt)) {
    return(file.path(project_root_opt, "scripts", "R", "_utils", "script_bootstrap.R"))
  }
  script_args_full <- commandArgs(trailingOnly = FALSE)
  script_file <- grep("^--file=", script_args_full, value = TRUE)
  if (length(script_file)) {
    script_file <- normalizePath(sub("^--file=", "", script_file[[1]]), winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "script_bootstrap.R"))
  }
  frame_paths <- vapply(sys.frames(), function(env) {
    ofile <- env$ofile
    if (is.null(ofile) || !nzchar(ofile)) return(NA_character_)
    ofile
  }, character(1))
  frame_paths <- frame_paths[!is.na(frame_paths)]
  if (length(frame_paths)) {
    script_file <- normalizePath(frame_paths[[length(frame_paths)]], winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "script_bootstrap.R"))
  }
  stop("Cannot determine bootstrap path. In an interactive session, call `init_politicsregs_session()` first.")
})
source(normalizePath(bootstrap_file, winslash = "/", mustWork = TRUE))
bootstrap_politicsregs()

loader_file <- file.path(dirname(normalizePath(bootstrap_file)), "load_firm_panel.R")
source(loader_file)

# --- Test harness -------------------------------------------------------------

.results <- list()

run_test <- function(name, body) {
  cat(sprintf("\n[TEST] %s\n", name))
  res <- tryCatch(body(), error = function(e) structure(list(status = "FAIL", msg = conditionMessage(e)), class = "test_res"))
  if (is.null(res)) res <- list(status = "PASS", msg = "")
  if (!inherits(res, "test_res")) res <- structure(res, class = "test_res")
  .results[[name]] <<- res
  cat(sprintf("  %s  %s\n", res$status, res$msg %||% ""))
  invisible(res)
}

`%||%` <- function(a, b) if (is.null(a) || !nzchar(a)) b else a

skip <- function(msg) structure(list(status = "SKIP", msg = msg), class = "test_res")
pass <- function(msg = "") structure(list(status = "PASS", msg = msg), class = "test_res")
fail <- function(msg) structure(list(status = "FAIL", msg = msg), class = "test_res")

# --- Test 1: Happy path -- load base-only -------------------------------------

run_test("1. Happy path: load base-only returns panel with no FA/dFA", function() {
  paths <- firm_panel_paths("cycle_specific")
  if (!file.exists(paths$sparse)) return(skip("sparse file not yet produced (Unit 2 pending)"))
  dt <- load_firm_panel("cycle_specific", instruments = character(0))
  bad <- grep("^(FA_|dFA_)", names(dt), value = TRUE)
  if (length(bad)) return(fail(sprintf("base-only load contained instrument columns: %s",
                                        paste(bad, collapse = ", "))))
  if (!all(c("firm_id", "muni_id", "year") %in% names(dt))) return(fail("missing key columns"))
  pass(sprintf("%d rows, %d cols", nrow(dt), ncol(dt)))
})

# --- Test 2: Full load -- matches legacy fat file column-for-column -----------

run_test("2. Full load: all 48 instruments match legacy fat file", function() {
  paths <- firm_panel_paths("cycle_specific")
  if (!file.exists(paths$sparse)) return(skip("sparse file not yet produced (Unit 2 pending)"))
  # Need a reference fat file to compare against. The migration path is:
  # (a) keep a pre-refactor copy at firm_panel_for_regs_fat_reference.fst, or
  # (b) compare within a small subset of columns against a known specification.
  ref_path <- make_output_path("firm_panel_for_regs_fat_reference.fst")
  if (!file.exists(ref_path)) return(skip(sprintf("reference fat file missing at %s", ref_path)))

  dt_new <- load_firm_panel("cycle_specific", instruments = NULL)
  dt_ref <- fst::read_fst(ref_path, as.data.table = TRUE)

  if (!setequal(names(dt_new), names(dt_ref))) {
    only_new <- setdiff(names(dt_new), names(dt_ref))
    only_ref <- setdiff(names(dt_ref), names(dt_new))
    return(fail(sprintf("column-set mismatch; only_new=[%s] only_ref=[%s]",
                        paste(only_new, collapse = ","),
                        paste(only_ref, collapse = ","))))
  }

  setkeyv(dt_new, c("firm_id", "muni_id", "year"))
  setkeyv(dt_ref, c("firm_id", "muni_id", "year"))
  if (nrow(dt_new) != nrow(dt_ref)) {
    return(fail(sprintf("row count mismatch: new=%d ref=%d", nrow(dt_new), nrow(dt_ref))))
  }

  # Compare every column; instruments should match to machine precision.
  inst_cols <- grep("^(FA_|dFA_)", names(dt_new), value = TRUE)
  max_abs_diff <- 0
  for (col in inst_cols) {
    d <- max(abs(dt_new[[col]] - dt_ref[[col]]), na.rm = TRUE)
    if (is.finite(d)) max_abs_diff <- max(max_abs_diff, d)
  }
  if (max_abs_diff > 1e-10) return(fail(sprintf("max abs instrument diff = %.3e", max_abs_diff)))
  pass(sprintf("%d instrument cols, max |diff| = %.3e", length(inst_cols), max_abs_diff))
})

# --- Test 3: Column subset ----------------------------------------------------

run_test("3. Column subset: request 3 continuous instruments", function() {
  paths <- firm_panel_paths("cycle_specific")
  if (!file.exists(paths$sparse)) return(skip("sparse file not yet produced (Unit 2 pending)"))
  sparse_cols <- fst::metadata_fst(paths$sparse)$columnNames
  inst_avail <- grep("^FA_(?!binary_)", sparse_cols, value = TRUE, perl = TRUE)
  if (length(inst_avail) < 3L) return(skip("fewer than 3 continuous FA_ columns available"))
  req <- inst_avail[1:3]
  dt <- load_firm_panel("cycle_specific",
                        columns = c("firm_id", "muni_id", "year"),
                        instruments = req)
  got_inst <- grep("^(FA_|dFA_)", names(dt), value = TRUE)
  if (!setequal(got_inst, req)) return(fail(sprintf("requested=[%s] got=[%s]",
                                                     paste(req, collapse = ","),
                                                     paste(got_inst, collapse = ","))))
  pass(sprintf("returned %d cols: %s", ncol(dt), paste(names(dt), collapse = ",")))
})

# --- Test 4: Zero-fill correctness --------------------------------------------

run_test("4. Zero-fill: non-matched rows are 0, not NA", function() {
  paths <- firm_panel_paths("cycle_specific")
  if (!file.exists(paths$sparse)) return(skip("sparse file not yet produced (Unit 2 pending)"))
  dt <- load_firm_panel("cycle_specific",
                        columns = c("firm_id", "muni_id", "year"),
                        instruments = NULL,
                        zero_fill = TRUE)
  inst_cols <- grep("^(FA_|dFA_)", names(dt), value = TRUE)
  na_counts <- vapply(inst_cols, function(c) sum(is.na(dt[[c]])), integer(1))
  if (any(na_counts > 0L)) {
    offenders <- names(na_counts)[na_counts > 0L]
    return(fail(sprintf("instrument cols with NAs after zero-fill: %s",
                        paste(offenders, collapse = ", "))))
  }

  # And with zero_fill = FALSE, at least one NA should appear (there are firms
  # with no owner link, so the sparse file omits them).
  dt2 <- load_firm_panel("cycle_specific",
                         columns = c("firm_id", "muni_id", "year"),
                         instruments = inst_cols[1],
                         zero_fill = FALSE)
  if (sum(is.na(dt2[[inst_cols[1]]])) == 0L) {
    return(fail(sprintf("zero_fill=FALSE produced no NAs in %s (unexpected given sparse design)",
                        inst_cols[1])))
  }
  pass(sprintf("%d instrument cols verified; NA semantics honored when zero_fill=FALSE",
               length(inst_cols)))
})

# --- Test 5: Baseline switch --------------------------------------------------

run_test("5. Baseline switch: cycle_specific and 2002_fixed both load", function() {
  p_cs <- firm_panel_paths("cycle_specific")
  p_02 <- firm_panel_paths("2002_fixed")
  if (!file.exists(p_cs$sparse) || !file.exists(p_02$sparse)) {
    return(skip("split files missing for one or both baselines (Unit 2 pending)"))
  }
  dt_cs <- load_firm_panel("cycle_specific", instruments = character(0))
  dt_02 <- load_firm_panel("2002_fixed",     instruments = character(0))
  if (!setequal(names(dt_cs), names(dt_02))) {
    return(fail("base column sets differ across baselines"))
  }
  # The two baselines should produce different FA values on at least some rows.
  inst_avail <- grep("^(FA_|dFA_)",
                     fst::metadata_fst(p_cs$sparse)$columnNames, value = TRUE)
  if (!length(inst_avail)) return(skip("no instrument cols available"))
  probe <- inst_avail[1]
  v_cs <- load_firm_panel("cycle_specific",
                          columns = c("firm_id", "muni_id", "year"),
                          instruments = probe)
  v_02 <- load_firm_panel("2002_fixed",
                          columns = c("firm_id", "muni_id", "year"),
                          instruments = probe)
  setkeyv(v_cs, c("firm_id", "muni_id", "year"))
  setkeyv(v_02, c("firm_id", "muni_id", "year"))
  m <- merge(v_cs, v_02, by = c("firm_id", "muni_id", "year"),
             suffixes = c(".cs", ".02"))
  diff_rows <- sum(m[[paste0(probe, ".cs")]] != m[[paste0(probe, ".02")]])
  if (diff_rows == 0L) {
    return(fail(sprintf("%s identical across baselines on all %d common rows", probe, nrow(m))))
  }
  pass(sprintf("cs rows=%d, 2002 rows=%d, %s differs on %d common rows",
               nrow(dt_cs), nrow(dt_02), probe, diff_rows))
})

# --- Test 6: Legacy fat-file fallback -----------------------------------------

run_test("6. Fallback: no sparse file -> reads legacy, warns once", function() {
  paths <- firm_panel_paths("cycle_specific")
  if (file.exists(paths$sparse)) {
    return(skip("sparse file exists; cannot exercise fallback without moving it aside"))
  }
  if (!file.exists(paths$legacy)) {
    return(skip(sprintf("no legacy fat file at %s", paths$legacy)))
  }

  # Reset the one-time latch on our copy of the loader environment.
  .firm_panel_fallback_warned$done <- FALSE

  warn_count <- 0L
  withCallingHandlers({
    dt <- load_firm_panel("cycle_specific",
                          columns = c("firm_id", "muni_id", "year"),
                          instruments = character(0))
    # Second call in same session should NOT re-warn.
    dt2 <- load_firm_panel("cycle_specific",
                           columns = c("firm_id", "muni_id", "year"),
                           instruments = character(0))
  }, message = function(m) {
    if (grepl("load_firm_panel", conditionMessage(m), fixed = TRUE)) {
      warn_count <<- warn_count + 1L
    }
    invokeRestart("muffleMessage")
  })

  if (warn_count != 1L) {
    return(fail(sprintf("expected exactly 1 fallback warning, got %d", warn_count)))
  }
  if (!all(c("firm_id", "muni_id", "year") %in% names(dt))) {
    return(fail("fallback did not return key columns"))
  }
  pass(sprintf("%d rows via fallback, warning fired once", nrow(dt)))
})

# --- Summary ------------------------------------------------------------------

cat("\n==============================================================================\n")
cat("Summary\n")
cat("==============================================================================\n")
for (nm in names(.results)) {
  cat(sprintf("  %-5s  %s\n", .results[[nm]]$status, nm))
}
n_fail <- sum(vapply(.results, function(r) identical(r$status, "FAIL"), logical(1)))
n_pass <- sum(vapply(.results, function(r) identical(r$status, "PASS"), logical(1)))
n_skip <- sum(vapply(.results, function(r) identical(r$status, "SKIP"), logical(1)))
cat(sprintf("\n%d PASS, %d FAIL, %d SKIP\n", n_pass, n_fail, n_skip))
if (n_fail > 0L) quit(status = 1L)
