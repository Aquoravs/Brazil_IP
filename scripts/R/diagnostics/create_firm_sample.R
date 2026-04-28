#!/usr/bin/env Rscript

# ==============================================================================
# Create Firm Sample Panel
# ==============================================================================
# Creates a reproducible firm-level sample panel for faster development and
# runtime benchmarking of script 51. Sampling is done at the firm level so all
# years and municipalities for a sampled firm are preserved.
#
# Usage:
#   Rscript BNDES/politicsregs/diagnostics/create_firm_sample.R [--frac=0.05]
# ==============================================================================

cat("==============================================================================\n")
cat("Creating Firm Sample Panel\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})

# Bootstrap shared path helpers from this script location.
bootstrap_file <- local({
  project_root_opt <- getOption("politicsregs.project_root", default = NULL)
  if (is.character(project_root_opt) && length(project_root_opt) == 1L && nzchar(project_root_opt)) {
    return(file.path(project_root_opt, "scripts", "R", "_utils", "script_bootstrap.R"))
  }

  script_args_full <- commandArgs(trailingOnly = FALSE)
  script_file <- grep("^--file=", script_args_full, value = TRUE)
  if (length(script_file)) {
    script_file <- normalizePath(sub("^--file=", "", script_file[[1]]), winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }

  frame_paths <- vapply(sys.frames(), function(env) {
    ofile <- env$ofile
    if (is.null(ofile) || !nzchar(ofile)) return(NA_character_)
    ofile
  }, character(1))
  frame_paths <- frame_paths[!is.na(frame_paths)]
  if (length(frame_paths)) {
    script_file <- normalizePath(frame_paths[[length(frame_paths)]], winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }

  stop("Cannot determine bootstrap path. In an interactive session, call `init_politicsregs_session()` first.")
})
source(normalizePath(bootstrap_file, winslash = "/", mustWork = TRUE))
bootstrap_politicsregs()
source(politicsregs_path("_utils", "load_firm_panel.R"))

setDTthreads(1)

args <- commandArgs(trailingOnly = TRUE)
frac_arg <- grep("^--frac=", args, value = TRUE)
SAMPLE_FRAC <- if (length(frac_arg)) as.numeric(sub("^--frac=", "", frac_arg[[1L]])) else 0.05

if (!is.finite(SAMPLE_FRAC) || SAMPLE_FRAC <= 0 || SAMPLE_FRAC > 1) {
  stop("`--frac` must be in (0, 1].")
}

cat(sprintf("Requested sample fraction: %.2f%%\n\n", 100 * SAMPLE_FRAC))

for (bt in c("cycle_specific", "2002_fixed")) {
  bt_suffix <- if (bt == "cycle_specific") "" else paste0("_", bt)
  paths_bt  <- firm_panel_paths(bt)   # base + sparse paths via loader

  cat(sprintf("[%s]\n", bt))

  if (!file.exists(paths_bt$base)) {
    cat("  Source base panel not found; skipping\n\n")
    next
  }

  # Step 1: sample firm IDs from the base file (firm_id is always in base).
  firm_ids <- fst::read_fst(paths_bt$base, columns = "firm_id", as.data.table = TRUE)
  firm_ids[, firm_id := as.integer(firm_id)]
  unique_firms <- sort(unique(firm_ids$firm_id))
  n_firms  <- length(unique_firms)
  n_sample <- max(1L, as.integer(n_firms * SAMPLE_FRAC))
  set.seed(42L)
  sampled_firms <- sample(unique_firms, n_sample)
  rm(firm_ids, unique_firms)
  invisible(gc())

  cat(sprintf("  Sampled %s of %s firms (%.2f%%)\n",
              format(n_sample, big.mark = ","),
              format(n_firms, big.mark = ","),
              100 * n_sample / n_firms))

  # Step 2: subset the base file and write the sample base .fst.
  dt_base <- fst::read_fst(paths_bt$base, as.data.table = TRUE)
  dt_base[, firm_id := as.integer(firm_id)]
  dt_base <- dt_base[firm_id %in% sampled_firms]

  sample_fst <- make_output_path(paste0("firm_panel_for_regs", bt_suffix, "_sample.fst"))
  fst::write_fst(dt_base, sample_fst, compress = 50)
  cat(sprintf("  Saved: %s (%s rows, %.2f MB)\n",
              sample_fst, format(nrow(dt_base), big.mark = ","),
              file.size(sample_fst) / 1024^2))
  rm(dt_base)
  invisible(gc())

  # Step 3: subset the sparse instruments file and write the sample sparse .fst.
  sample_inst_fst <- make_output_path(paste0("firm_panel_for_regs", bt_suffix, "_sample_instruments.fst"))
  if (file.exists(paths_bt$sparse)) {
    dt_inst <- fst::read_fst(paths_bt$sparse, as.data.table = TRUE)
    dt_inst[, firm_id := as.integer(firm_id)]
    dt_inst <- dt_inst[firm_id %in% sampled_firms]
    fst::write_fst(dt_inst, sample_inst_fst, compress = 50)
    cat(sprintf("  Saved: %s (%s rows, %.2f MB)\n",
                sample_inst_fst, format(nrow(dt_inst), big.mark = ","),
                file.size(sample_inst_fst) / 1024^2))
    rm(dt_inst)
    invisible(gc())
  } else {
    cat("  Sparse instruments file not found; skipping instrument sample\n")
  }

  rm(sampled_firms)
  invisible(gc())
  cat("\n")
}

cat("Done. Use `--test` in script 51 to load these artifacts.\n")
