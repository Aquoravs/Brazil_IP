#!/usr/bin/env Rscript

# ==============================================================================
# Diagnose Multi-Sector Firms
# ==============================================================================
# Measures how many (firm_id, muni_id, year) cells have >1 CNAE section in the
# reconstructed panel, and how much employment they represent. Informs whether
# the deduplication in script 31 (unique by firm-muni-year) loses meaningful
# sectoral variation.
#
# Input:  output/rais_bndes_reconstructed.fst (or .qs2)
# Output: console diagnostics only
#
# Usage:  Rscript scripts/R/diagnostics/diagnose_multisector_firms.R
# ==============================================================================

cat("==============================================================================\n")
cat("Diagnosing Multi-Sector Firms in Reconstructed Panel\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})

setDTthreads(0)

bootstrap_file <- local({
  project_root_opt <- getOption("politicsregs.project_root", default = NULL)
  if (is.character(project_root_opt) && length(project_root_opt) == 1L && nzchar(project_root_opt)) {
    return(file.path(project_root_opt, "scripts", "R", "_utils", "script_bootstrap.R"))
  }

  script_args_full <- commandArgs(trailingOnly = FALSE)
  script_file <- grep("^--file=", script_args_full, value = TRUE)
  if (length(script_file)) {
    script_file <- normalizePath(sub("^--file=", "", script_file[[1L]]), winslash = "/", mustWork = TRUE)
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

# --- Step 1: Load reconstructed panel -----------------------------------------

cat("Step 1: Loading reconstructed panel...\n")

recon_path_fst <- make_output_path("rais_bndes_reconstructed.fst")
recon_path_qs2 <- make_output_path("rais_bndes_reconstructed.qs2")

load_cols <- c("firm_id", "muni_id", "year", "cnae_section", "n_employees")

if (file.exists(recon_path_fst) && requireNamespace("fst", quietly = TRUE)) {
  cat("  Loading from fst (column-selective):", basename(recon_path_fst), "\n")
  dt <- fst::read_fst(recon_path_fst, columns = load_cols, as.data.table = TRUE)
} else if (file.exists(recon_path_qs2)) {
  cat("  Loading from qs2:", basename(recon_path_qs2), "\n")
  raw <- qs_read(recon_path_qs2)
  setDT(raw)
  dt <- raw[, ..load_cols]
  rm(raw); invisible(gc())
} else {
  stop("Reconstructed panel not found. Run script 22 first.")
}

dt[, firm_id := as.integer(firm_id)]
dt[, muni_id := as.integer(muni_id)]
dt[, year := as.integer(year)]
dt[is.na(n_employees) | !is.finite(n_employees), n_employees := 0]

cat(sprintf("  Loaded: %s rows, years %d-%d\n\n",
            format(nrow(dt), big.mark = ","),
            min(dt$year), max(dt$year)))

# --- Step 2: Diagnose multi-CNAE-section prevalence ---------------------------

cat("==============================================================================\n")
cat("Multi-CNAE-section diagnosis for (firm_id, muni_id, year) cells\n")
cat("==============================================================================\n\n")

cat(sprintf("cnae_section (%d categories):\n", uniqueN(dt$cnae_section, na.rm = TRUE)))
cat("  Collapsing to firm-muni-year-section employment...\n")

total_emp <- dt[!is.na(cnae_section), sum(n_employees, na.rm = TRUE)]

section_emp <- dt[!is.na(cnae_section), .(
  emp = sum(n_employees, na.rm = TRUE)
), by = .(firm_id, muni_id, year, cnae_section)]

rm(dt); invisible(gc())

cat(sprintf("  Collapsed rows: %s\n", format(nrow(section_emp), big.mark = ",")))
cat("  Counting sections per firm-muni-year cell...\n")

cell_stats <- section_emp[, .(
  n_sections = .N,
  emp_total = sum(emp, na.rm = TRUE)
), by = .(firm_id, muni_id, year)]

n_total <- nrow(cell_stats)
multi <- cell_stats[n_sections > 1L]
n_multi <- nrow(multi)
emp_multi <- sum(multi$emp_total, na.rm = TRUE)

cat(sprintf("  Total (firm, muni, year) cells with cnae_section: %s\n",
            format(n_total, big.mark = ",")))
cat(sprintf("  Cells with >1 cnae_section: %s (%.2f%%)\n",
            format(n_multi, big.mark = ","),
            100 * n_multi / n_total))
cat(sprintf("  Employment in >1-section cells: %s (%.2f%% of total)\n",
            format(as.integer(emp_multi), big.mark = ","),
            100 * emp_multi / total_emp))

if (n_multi > 0L) {
  cat("  Among >1-section cells:\n")
  cat(sprintf("    Mean sections per cell: %.2f\n", mean(multi$n_sections)))
  cat(sprintf("    Max sections per cell: %d\n", max(multi$n_sections)))
  cat(sprintf("    Distribution: %s\n",
              paste(sprintf("%d sections: %s",
                            sort(unique(multi$n_sections)),
                            vapply(sort(unique(multi$n_sections)), function(k)
                              format(sum(multi$n_sections == k), big.mark = ","),
                              character(1))),
                    collapse = "; ")))

  multi_keys <- multi[, .(firm_id, muni_id, year)]
  emp_by_section <- section_emp[multi_keys, on = .(firm_id, muni_id, year), nomatch = 0L]
  emp_by_section[, emp_total := sum(emp), by = .(firm_id, muni_id, year)]
  emp_by_section[, emp_share := fifelse(emp_total > 0, emp / emp_total, 0)]
  max_shares <- emp_by_section[, .(max_share = max(emp_share)), by = .(firm_id, muni_id, year)]

  cat(sprintf("    Employment share of largest section (mean): %.1f%%\n",
              100 * mean(max_shares$max_share)))
  cat(sprintf("    Employment share of largest section (median): %.1f%%\n",
              100 * median(max_shares$max_share)))
  cat(sprintf("    Cells where largest section has >80%% emp: %s (%.1f%%)\n",
              format(sum(max_shares$max_share > 0.8), big.mark = ","),
              100 * mean(max_shares$max_share > 0.8)))
}

# --- Step 3: Which sections co-occur? -----------------------------------------

cat("==============================================================================\n")
cat("Which cnae_section pairs most commonly co-occur in a firm-muni-year?\n")
cat("==============================================================================\n\n")

if (nrow(multi) > 0L) {
  two_section_keys <- multi[n_sections == 2L, .(firm_id, muni_id, year)]
  two_sections <- section_emp[two_section_keys, on = .(firm_id, muni_id, year), nomatch = 0L]
  setorder(two_sections, firm_id, muni_id, year, cnae_section)

  pairs <- two_sections[, .(
    pair = paste(cnae_section, collapse = "-"),
    emp = sum(emp, na.rm = TRUE)
  ), by = .(firm_id, muni_id, year)]

  pair_counts <- pairs[, .(n = .N, total_emp = sum(emp, na.rm = TRUE)), by = pair]
  setorder(pair_counts, -n)
  cat("  Top 15 section pairs (2-sector cells):\n")
  print(head(pair_counts, 15))
  cat("\n")
}

cat("Diagnosis complete.\n")
cat("==============================================================================\n")
