#!/usr/bin/env Rscript

# ==============================================================================
# Convert merged RDS to memory-efficient formats (fst + qs2) and save a sample
# ==============================================================================
#
# Problem: The merged file (~867 MB RDS) causes "cannot allocate vector"
#          errors on Windows machines with limited RAM, because RDS and qs2
#          require loading the entire object into memory at once.
#
# Solution: Convert to fst format, which supports:
#   - Column-selective reading (only load the columns you need)
#   - Row-range reading (only load a slice of rows)
#   This lets downstream scripts (22, 31+) load subsets without
#   exceeding available RAM.
#
# Outputs:
#   - output/rais_bndes_merged_for_regs.fst   (fst, column-selectable)
#   - output/rais_bndes_merged_for_regs.qs2   (qs2, compact archive)
#   - output/rais_bndes_merged_sample.qs2     (5% random sample for inspection)
#
# Usage:
#   Rscript 2_firm_panel/21_convert_merged_formats.R
#
# After running this script, downstream code can read efficiently:
#   library(fst)
#   # Read only the columns you need:
#   dt <- read_fst("output/rais_bndes_merged_for_regs.fst",
#                  columns = c("firm_id", "muni_id", "year", "n_employees"),
#                  as.data.table = TRUE)
# ==============================================================================

cat("==============================================================================\n")
cat("Convert Merged File to Memory-Efficient Formats (Script 21)\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
})

setDTthreads(parallel::detectCores() - 1)

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

# --- Check required packages --------------------------------------------------

if (!requireNamespace("fst", quietly = TRUE)) {
  stop("Package 'fst' is required. Install with: install.packages('fst')")
  }

has_qs2 <- requireNamespace("qs2", quietly = TRUE)
if (has_qs2) {
  library(qs2)
  qopt("nthreads", parallel::detectCores() - 1)
}

# --- Locate the RDS source file -----------------------------------------------

rds_path <- make_output_path("rais_bndes_merged_for_regs.rds")
if (!file.exists(rds_path)) {
  stop("RDS file not found: ", rds_path,
       "\n  This script converts the .rds file to .fst and .qs2 formats.")
}

cat("Source file:", rds_path, "\n")
cat("  Size:", round(file.size(rds_path) / 1024^2, 1), "MB\n\n")

# ==============================================================================
# Step 1: Load the RDS file
# ==============================================================================

cat("Step 1: Loading RDS file...\n")
invisible(gc(full = TRUE))

dt <- readRDS(rds_path)
setDT(dt)

cat("  Loaded:", format(nrow(dt), big.mark = ","), "rows,",
    ncol(dt), "columns\n")
cat("  Columns:", paste(names(dt), collapse = ", "), "\n")
cat("  Object size in memory:", round(object.size(dt) / 1024^2, 1), "MB\n\n")

# ==============================================================================
# Step 2: Save as fst (column-selectable format)
# ==============================================================================

cat("Step 2: Saving as fst...\n")

fst_path <- make_output_path("rais_bndes_merged_for_regs.fst")

# compress = 50 is a good balance of speed vs size (range: 0-100)
fst::write_fst(dt, fst_path, compress = 50)

cat(sprintf("  Saved: %s (%.1f MB)\n", basename(fst_path),
            file.size(fst_path) / 1024^2))

# Verify: read back column names and row count
fst_meta <- fst::metadata_fst(fst_path)
cat(sprintf("  Verified: %s rows, %d columns\n\n",
            format(fst_meta$nrOfRows, big.mark = ","), length(fst_meta$columnNames)))

# ==============================================================================
# Step 3: Save as qs2 (compact archive)
# ==============================================================================

if (has_qs2) {
  cat("Step 3: Saving as qs2...\n")

  qs2_path <- make_output_path("rais_bndes_merged_for_regs.qs2")
  qs_save(dt, qs2_path)

  cat(sprintf("  Saved: %s (%.1f MB)\n\n", basename(qs2_path),
              file.size(qs2_path) / 1024^2))
} else {
  cat("Step 3: Skipped (qs2 not installed)\n\n")
}

# ==============================================================================
# Step 4: Save a random sample for quick inspection
# ==============================================================================

cat("Step 4: Creating random sample (5%)...\n")

set.seed(42)
n_sample <- ceiling(nrow(dt) * 0.05)
sample_idx <- sample.int(nrow(dt), n_sample)
dt_sample <- dt[sample_idx]

cat("  Sample size:", format(nrow(dt_sample), big.mark = ","), "rows\n")

# Save sample as qs2
if (has_qs2) {
  sample_qs2_path <- make_output_path("rais_bndes_merged_sample.qs2")
  qs_save(dt_sample, sample_qs2_path)
  cat(sprintf("  Saved: %s (%.1f MB)\n", basename(sample_qs2_path),
              file.size(sample_qs2_path) / 1024^2))
}

# ==============================================================================
# Step 5: Print summary of the sample
# ==============================================================================

cat("\n==============================================================================\n")
cat("SAMPLE SUMMARY\n")
cat("==============================================================================\n")
cat(sprintf("  Rows:              %s (5%% of %s)\n",
            format(nrow(dt_sample), big.mark = ","),
            format(nrow(dt), big.mark = ",")))
cat(sprintf("  Columns:           %d\n", ncol(dt_sample)))
cat(sprintf("  Unique firms:      %s\n", format(uniqueN(dt_sample$firm_id), big.mark = ",")))
cat(sprintf("  Unique munis:      %s\n", format(uniqueN(dt_sample$muni_id), big.mark = ",")))
cat(sprintf("  Year range:        %s\n", paste(range(dt_sample$year, na.rm = TRUE), collapse = "-")))

# Key variable distributions
cat("\nVariable summaries (sample):\n")
summary_vars <- c("n_employees", "total_wage_nom", "n_establishments",
                   "valor_desembolsado_total", "valor_indireto",
                   "valor_desembolsado_total_real_2018",
                   "in_bndes", "in_rais", "in_owner",
                   "logval", "firm_size", "classe", "sector_2d")
for (v in intersect(summary_vars, names(dt_sample))) {
  vals <- dt_sample[[v]]
  if (is.numeric(vals)) {
    non_na <- vals[!is.na(vals)]
    if (length(non_na) > 0) {
      cat(sprintf("  %-40s n=%s  mean=%.2f  sd=%.2f  min=%.2f  p50=%.2f  max=%.2f  NA%%=%.1f\n",
                  v,
                  format(length(non_na), big.mark = ","),
                  mean(non_na), sd(non_na),
                  min(non_na), median(non_na), max(non_na),
                  100 * mean(is.na(vals))))
    }
  } else {
    cat(sprintf("  %-40s n_unique=%s  NA%%=%.1f\n",
                v, format(uniqueN(vals, na.rm = TRUE), big.mark = ","),
                100 * mean(is.na(vals))))
  }
}

# Flag columns: show counts
cat("\nFlag distributions (sample):\n")
for (v in intersect(c("in_bndes", "in_rais", "in_owner"), names(dt_sample))) {
  tbl <- dt_sample[, .N, by = v][order(get(v))]
  cat(sprintf("  %s: %s\n", v,
              paste(sprintf("%s=%s", tbl[[1]], format(tbl[[2]], big.mark = ",")),
                    collapse = "  ")))
}

# ==============================================================================
# Summary of output files
# ==============================================================================

cat("\n==============================================================================\n")
cat("OUTPUT FILES\n")
cat("==============================================================================\n")
cat(sprintf("  %-50s %7.1f MB  (column-selectable, for downstream scripts)\n",
            basename(fst_path), file.size(fst_path) / 1024^2))
if (has_qs2) {
  qs2_path <- make_output_path("rais_bndes_merged_for_regs.qs2")
  if (file.exists(qs2_path)) {
    cat(sprintf("  %-50s %7.1f MB  (compact archive)\n",
                basename(qs2_path), file.size(qs2_path) / 1024^2))
  }
  sample_qs2_path <- make_output_path("rais_bndes_merged_sample.qs2")
  if (file.exists(sample_qs2_path)) {
    cat(sprintf("  %-50s %7.1f MB  (5%% sample)\n",
                basename(sample_qs2_path), file.size(sample_qs2_path) / 1024^2))
  }
}
cat(sprintf("  %-50s %7.1f MB  (original, keep as backup)\n",
            basename(rds_path), file.size(rds_path) / 1024^2))

cat("\n==============================================================================\n")
cat("Done. Downstream scripts can now use fst::read_fst() with column selection.\n")
cat("==============================================================================\n")

rm(dt, dt_sample); invisible(gc(full = TRUE))
