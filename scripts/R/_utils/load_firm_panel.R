# ==============================================================================
# Firm Regression Panel Loader
# ==============================================================================
# Unified read-path for the firm regression panel emitted by script 42.
#
# Storage layout (per baseline type `bt`):
#   firm_panel_for_regs{suffix}.fst              BASE  — panel without FA/dFA
#   firm_panel_for_regs{suffix}_instruments.fst  SPARSE — only non-zero FA/dFA
#     where suffix = ""         for bt = "cycle_specific"
#           suffix = "_<bt>"    otherwise
#
# The split format lets downstream consumers pay the 48-instrument materialization
# cost only for the subset they actually use. See plan
# `quality_reports/plans/2026-04-14-002-refactor-firm-panel-split-files-plan.md`.
#
# Requires make_output_path() from scripts/R/_utils/utils.R.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# --- Constants ----------------------------------------------------------------

# Panel keys used for the base <-> sparse join.
.firm_panel_keys <- c("firm_id", "muni_id", "year")

# Pattern matching the 48 instrument columns emitted by script 36 / 42.
.firm_panel_instrument_regex <- "^(FA_|dFA_)"

# --- Path resolution ----------------------------------------------------------

firm_panel_paths <- function(baseline_type = "cycle_specific", test_mode = FALSE) {
  suffix <- if (identical(baseline_type, "cycle_specific")) "" else paste0("_", baseline_type)
  sample_suffix <- if (isTRUE(test_mode)) "_sample" else ""
  stem <- paste0("firm_panel_for_regs", suffix, sample_suffix)
  list(
    base   = make_output_path(paste0(stem, ".fst")),
    sparse = make_output_path(paste0(stem, "_instruments.fst"))
  )
}

# --- Helpers ------------------------------------------------------------------

.fst_columns <- function(path) {
  if (!requireNamespace("fst", quietly = TRUE)) {
    stop("The 'fst' package is required by load_firm_panel().")
  }
  fst::metadata_fst(path)$columnNames
}

.detect_instrument_cols <- function(all_cols) {
  grep(.firm_panel_instrument_regex, all_cols, value = TRUE)
}

.coerce_panel_types <- function(dt) {
  int_cols <- intersect(c(
    "firm_id", "muni_id", "year",
    "has_bndes_fmt", "delta_has_bndes_fmt",
    "is_multi_muni"
  ), names(dt))
  for (col in int_cols) dt[, (col) := as.integer(get(col))]
  if ("n_employees" %in% names(dt)) dt[, n_employees := as.numeric(n_employees)]
  dt
}

# Resolve the instruments argument into an explicit character vector.
# NULL           -> all instrument columns present in `available_inst_cols`
# character(0)   -> no instruments
# character vec  -> intersect with available; error if any requested cols missing
.resolve_instruments <- function(instruments, available_inst_cols) {
  if (is.null(instruments)) return(available_inst_cols)
  if (!is.character(instruments)) {
    stop("`instruments` must be NULL, character(0), or a character vector.")
  }
  if (length(instruments) == 0L) return(character(0))
  missing_inst <- setdiff(instruments, available_inst_cols)
  if (length(missing_inst)) {
    stop(sprintf(
      "Requested instrument columns not available: %s",
      paste(missing_inst, collapse = ", ")
    ))
  }
  instruments
}

# Resolve the columns argument into an explicit character vector of base cols.
# NULL -> all base columns (everything in the file that isn't an instrument)
# character vector -> intersect with available base cols; keys are always kept
.resolve_base_columns <- function(columns, available_base_cols) {
  if (is.null(columns)) return(available_base_cols)
  if (!is.character(columns)) {
    stop("`columns` must be NULL or a character vector.")
  }
  requested <- union(.firm_panel_keys, columns)
  missing_base <- setdiff(requested, available_base_cols)
  if (length(missing_base)) {
    stop(sprintf(
      "Requested base columns not available: %s",
      paste(missing_base, collapse = ", ")
    ))
  }
  # Preserve caller order but put keys first.
  c(.firm_panel_keys, setdiff(requested, .firm_panel_keys))
}

# --- Main loader --------------------------------------------------------------

#' Load the firm regression panel (base + sparse instruments).
#'
#' @param baseline_type  "cycle_specific" or "2002_fixed". Selects which pair of
#'                       files to read.
#' @param columns        Base columns to return. NULL (default) returns every
#'                       base column in the file. Keys (firm_id, muni_id, year)
#'                       are always included.
#' @param instruments    FA/dFA columns to attach. NULL (default) returns every
#'                       instrument column. `character(0)` skips the sparse join
#'                       entirely. A character vector selects specific columns.
#' @param zero_fill      If TRUE (default), rows with no match in the sparse
#'                       file are filled with 0 for the requested instrument
#'                       columns. If FALSE, non-matched rows contain NA.
#' @param as_data_table  If TRUE (default), returns a data.table. If FALSE,
#'                       returns a data.frame.
#' @param test_mode      If TRUE, reads the `_sample` variant of each file.
#'
#' @return A data.table (or data.frame) with the requested columns.
load_firm_panel <- function(baseline_type = c("cycle_specific", "2002_fixed"),
                            columns       = NULL,
                            instruments   = NULL,
                            zero_fill     = TRUE,
                            as_data_table = TRUE,
                            test_mode     = FALSE) {
  baseline_type <- match.arg(baseline_type)
  if (!requireNamespace("fst", quietly = TRUE)) {
    stop("The 'fst' package is required by load_firm_panel().")
  }

  paths <- firm_panel_paths(baseline_type, test_mode = test_mode)

  if (!file.exists(paths$base)) {
    stop(sprintf(
      "Firm panel not found for baseline '%s'.\n  expected base:   %s\n  expected sparse: %s\nRun scripts 22, 36, 42 first.",
      baseline_type, paths$base, paths$sparse
    ))
  }

  # ---------------------------------------------------------------------------
  # Split-path read
  # ---------------------------------------------------------------------------
  base_available <- .fst_columns(paths$base)
  if (any(grepl(.firm_panel_instrument_regex, base_available))) {
    stop(sprintf(
      "Base file unexpectedly contains instrument columns: %s\nRefusing to proceed.",
      paths$base
    ))
  }
  base_cols <- .resolve_base_columns(columns, base_available)

  dt <- fst::read_fst(paths$base, columns = base_cols, as.data.table = TRUE)
  .coerce_panel_types(dt)

  # Short-circuit: if caller requests no instruments, skip sparse join entirely.
  if (is.character(instruments) && length(instruments) == 0L) {
    if (!isTRUE(as_data_table)) return(as.data.frame(dt))
    return(dt)
  }

  if (!file.exists(paths$sparse)) {
    stop(sprintf(
      "Sparse instrument file not found for baseline '%s':\n  %s\nRun script 42 first.",
      baseline_type, paths$sparse
    ))
  }

  sparse_available <- .fst_columns(paths$sparse)
  inst_available <- .detect_instrument_cols(sparse_available)
  inst_cols <- .resolve_instruments(instruments, inst_available)

  if (!length(inst_cols)) {
    if (!isTRUE(as_data_table)) return(as.data.frame(dt))
    return(dt)
  }

  missing_keys <- setdiff(.firm_panel_keys, sparse_available)
  if (length(missing_keys)) {
    stop(sprintf(
      "Sparse instrument file missing expected key columns: %s\n  %s",
      paste(missing_keys, collapse = ", "), paths$sparse
    ))
  }

  sparse_dt <- fst::read_fst(
    paths$sparse,
    columns = c(.firm_panel_keys, inst_cols),
    as.data.table = TRUE
  )
  # Keys must be integer to match base (coerce for cheap, safe merge).
  for (k in .firm_panel_keys) {
    if (!is.integer(sparse_dt[[k]])) sparse_dt[, (k) := as.integer(get(k))]
  }

  # Left-join instruments onto base by (firm_id, muni_id, year). data.table's
  # binary join + in-place assignment avoids an intermediate copy.
  setkeyv(dt, .firm_panel_keys)
  setkeyv(sparse_dt, .firm_panel_keys)
  dt[sparse_dt, (inst_cols) := mget(paste0("i.", inst_cols)),
     on = .firm_panel_keys]
  rm(sparse_dt)

  if (isTRUE(zero_fill)) {
    setnafill(dt, type = "const", fill = 0, cols = inst_cols)
  }

  if (!isTRUE(as_data_table)) return(as.data.frame(dt))
  dt
}
