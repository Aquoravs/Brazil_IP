resolve_this_script <- function() {
  opt_path <- getOption("politicsregs.script_file", default = NULL)
  if (is.character(opt_path) && length(opt_path) == 1L && nzchar(opt_path)) {
    return(normalizePath(opt_path, winslash = "/", mustWork = TRUE))
  }

  script_args_full <- commandArgs(trailingOnly = FALSE)
  script_file <- grep("^--file=", script_args_full, value = TRUE)
  if (length(script_file)) {
    return(normalizePath(sub("^--file=", "", script_file[[1]]), winslash = "/", mustWork = TRUE))
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
    return(normalizePath(frame_paths[[length(frame_paths)]], winslash = "/", mustWork = TRUE))
  }

  stop(
    "Cannot determine script path. Run with `Rscript path/to/script.R` ",
    "or `source('.../script.R')`."
  )
}

bootstrap_politicsregs <- function() {
  script_file <- resolve_this_script()
  project_root <- dirname(script_file)
  while (TRUE) {
    # New structure: scripts/R/ (clo-author layout)
    if (dir.exists(file.path(project_root, "scripts", "R"))) break
    # Legacy: BNDES/ (old layout)
    if (dir.exists(file.path(project_root, "BNDES"))) break
    parent <- dirname(project_root)
    if (identical(parent, project_root)) {
      stop("Could not find project root containing 'scripts/R/' or 'BNDES/' while bootstrapping from: ", script_file)
    }
    project_root <- parent
  }

  options(
    politicsregs.project_root = project_root,
    politicsregs.script_file = script_file
  )

  # Source utils from new or legacy location
  utils_new <- file.path(project_root, "scripts", "R", "_utils", "utils.R")
  utils_old <- file.path(project_root, "BNDES", "politicsregs", "_utils", "utils.R")
  source(if (file.exists(utils_new)) utils_new else utils_old)
  invisible(script_file)
}
