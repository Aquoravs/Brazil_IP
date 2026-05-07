# Utility helpers for politicsregs scripts.
# Keep minimal and dependency-light. Scripts should source this via an absolute
# path derived from their own `--file=` location, never via the working
# directory.

# -----------------------------------------------------------------------------
# Path bootstrap
# -----------------------------------------------------------------------------

is_absolute_path <- function(path) {
  is.character(path) &&
    length(path) == 1L &&
    !is.na(path) &&
    grepl("^([A-Za-z]:|/|\\\\\\\\)", path)
}

normalize_path_safe <- function(path, mustWork = FALSE) {
  path <- path.expand(path)
  normalizePath(path, winslash = "/", mustWork = mustWork)
}

get_script_path <- function() {
  opt_path <- getOption("politicsregs.script_file", default = NULL)
  if (is.character(opt_path) && length(opt_path) == 1L && nzchar(opt_path)) {
    return(normalize_path_safe(opt_path, mustWork = TRUE))
  }

  script_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", script_args, value = TRUE)
  if (length(file_arg)) {
    return(normalize_path_safe(sub("^--file=", "", file_arg[[1]]), mustWork = TRUE))
  }

  frame_paths <- vapply(
    sys.frames(),
    function(env) {
      ofile <- env$ofile
      if (is.null(ofile) || !nzchar(ofile)) return(NA_character_)
      ofile
    },
    character(1)
  )
  frame_paths <- frame_paths[!is.na(frame_paths)]
  if (length(frame_paths)) {
    return(normalize_path_safe(frame_paths[[length(frame_paths)]], mustWork = TRUE))
  }

  NA_character_
}

find_project_root <- function(start_path = NULL) {
  if (is.null(start_path) || !nzchar(start_path)) {
    start_path <- get_script_path()
  }
  if (is.na(start_path) || !nzchar(start_path)) {
    start_path <- getwd()
  }

  current <- normalize_path_safe(start_path, mustWork = FALSE)
  if (!dir.exists(current)) {
    current <- dirname(current)
  }

  repeat {
    # New structure: look for scripts/R/ (clo-author layout)
    if (dir.exists(file.path(current, "scripts", "R"))) {
      return(current)
    }
    # Legacy: look for BNDES/ (old layout)
    if (dir.exists(file.path(current, "BNDES"))) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop(
        "Could not find project root containing 'scripts/R/' or 'BNDES/' while bootstrapping from: ",
        start_path,
        "\nRun the script with `Rscript path/to/script.R` or source utils via an absolute path."
      )
    }
    current <- parent
  }
}

PROJECT_ROOT <- normalize_path_safe(
  getOption("politicsregs.project_root", default = find_project_root()),
  mustWork = TRUE
)
POLITICSREGS_DIR <- normalize_path_safe(
  file.path(PROJECT_ROOT, "scripts", "R"),
  mustWork = TRUE
)

init_politicsregs_session <- function(project_root = NULL, script_file = NULL) {
  if (is.null(project_root) || !nzchar(project_root)) {
    project_root <- find_project_root(getwd())
  }
  project_root <- normalize_path_safe(project_root, mustWork = TRUE)

  if (is.null(script_file) || !nzchar(script_file)) {
    script_file <- file.path(project_root, "scripts", "R", "run_politicsregs.R")
  }
  script_file <- normalize_path_safe(script_file, mustWork = TRUE)

  if (!dir.exists(file.path(project_root, "scripts", "R"))) {
    stop("`project_root` must contain a `scripts/R/` directory: ", project_root)
  }

  options(
    politicsregs.project_root = project_root,
    politicsregs.script_file = script_file
  )

  invisible(list(
    project_root = project_root,
    script_file = script_file,
    politicsregs_dir = file.path(project_root, "scripts", "R")
  ))
}

# -----------------------------------------------------------------------------
# Canonical directory configuration (all can be overridden by env vars)
# -----------------------------------------------------------------------------

# Base directory for project data
BNDES_BASE <- normalize_path_safe(
  Sys.getenv("BNDES_BASE", unset = file.path(PROJECT_ROOT, "data")),
  mustWork = FALSE
)

# Processed/intermediate data directory
OUTPUT_DIR <- normalize_path_safe(
  Sys.getenv("BNDES_OUTPUT", unset = file.path(BNDES_BASE, "processed")),
  mustWork = FALSE
)

# Regression tables output directory
TABLES_DIR <- normalize_path_safe(
  Sys.getenv("BNDES_TABLES", unset = file.path(PROJECT_ROOT, "output", "tables")),
  mustWork = FALSE
)

# Encrypted RAIS mount point (contains identifier crosswalks)
ENCFS_MOUNT <- normalize_path_safe(
  Sys.getenv("ENCFS_MOUNT", unset = "/proj/patkin/juan/encfs_mount"),
  mustWork = FALSE
)

# Base directory for de-identified RAIS data on the server
RAIS_DEIDENTIFIED_BASE <- "/proj/patkin/raisdeidentified/dta"

project_path <- function(...) {
  normalize_path_safe(file.path(PROJECT_ROOT, ...), mustWork = FALSE)
}

politicsregs_path <- function(...) {
  normalize_path_safe(file.path(POLITICSREGS_DIR, ...), mustWork = FALSE)
}

bndes_data_path <- function(...) {
  normalize_path_safe(file.path(BNDES_BASE, ...), mustWork = FALSE)
}

raw_path <- function(...) {
  normalize_path_safe(file.path(BNDES_BASE, "raw", ...), mustWork = FALSE)
}

output_path <- function(...) {
  normalize_path_safe(file.path(OUTPUT_DIR, ...), mustWork = FALSE)
}

encfs_path <- function(...) {
  normalize_path_safe(file.path(ENCFS_MOUNT, ...), mustWork = FALSE)
}

tables_path <- function(...) {
  normalize_path_safe(file.path(TABLES_DIR, ...), mustWork = FALSE)
}

# Backward-compatible aliases used across the pipeline
make_output_path <- function(filename) {
  if (is_absolute_path(filename)) return(normalize_path_safe(filename, mustWork = FALSE))
  normalize_path_safe(file.path(OUTPUT_DIR, filename), mustWork = FALSE)
}

make_base_path <- function(relpath) {
  if (is_absolute_path(relpath)) return(normalize_path_safe(relpath, mustWork = FALSE))
  bndes_data_path(relpath)
}

make_encfs_path <- function(relpath) {
  if (is_absolute_path(relpath)) return(normalize_path_safe(relpath, mustWork = FALSE))
  encfs_path(relpath)
}

# Safe readRDS with informative error
read_rds_safe <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path)
  readRDS(path)
}

# Atomic writeRDS (write temp then move)
write_rds_atomic <- function(obj, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  saveRDS(obj, tmp)
  if (!file.rename(tmp, path)) stop("Atomic write failed for: ", path)
  invisible(path)
}

# Simple logging helpers
log_info <- function(...) message(sprintf("[INFO] %s: %s", Sys.time(), paste(..., collapse = " ")))
log_warn <- function(...) message(sprintf("[WARN] %s: %s", Sys.time(), paste(..., collapse = " ")))
log_error <- function(...) stop(sprintf("[ERROR] %s: %s", Sys.time(), paste(..., collapse = " ")))

# Lightweight CLI flag parser for common patterns
parse_flags <- function() {
  args <- tolower(commandArgs(trailingOnly = TRUE))
  list(
    lagsonly = "-lagsonly" %in% args,
    currentonly = "-currentonly" %in% args,
    unweighted = "-unweighted" %in% args
  )
}

# Small data helpers
winsorize_vec <- function(x, probs = c(0.01, 0.99)) {
  if (!is.numeric(x)) return(x)
  qs <- quantile(x, probs, na.rm = TRUE, names = FALSE)
  if (anyNA(qs)) return(x)
  pmin(pmax(x, qs[1]), qs[2])
}

mode_with_ties <- function(v) {
  v <- v[!is.na(v)]
  if (!length(v)) return(NA_character_)
  tab <- table(v)
  max_count <- max(tab)
  modes <- names(tab)[tab == max_count]
  sample(modes, 1L)
}

# Convert to numeric, suppressing warnings for non-numeric strings
numify <- function(x) {
  suppressWarnings(as.numeric(as.character(x)))
}

# Assert columns present
assert_cols <- function(dt, cols) {
  missing <- setdiff(cols, names(dt))
  if (length(missing)) stop("Missing columns: ", paste(missing, collapse = ", "))
  invisible(TRUE)
}
