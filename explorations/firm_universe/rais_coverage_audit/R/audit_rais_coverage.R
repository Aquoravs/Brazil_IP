#!/usr/bin/env Rscript

# ==============================================================================
# A0.1 - RAIS Coverage Audit (INVENTORY ONLY)
# ==============================================================================
# Author:  data-engineer (orchestrator dispatch)
# Date:    2026-05-12
# Phase:   Phase 0 of firm-support hybrid implementation
# Purpose: Stratify the firm union panel into coverage classes and tabulate
#          counts by year, CNAE section, and municipality population tercile.
#          INVENTORY ONLY - no production-pipeline mutations.
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst   (44,181,410 firm-year rows)
#   data/processed/population_ibge.qs2            (muni-year IBGE population)
#
# Outputs (under explorations/firm_universe/rais_coverage_audit/output/):
#   class_overall.csv
#   class_by_year.csv
#   class_by_cnae_section.csv
#   class_by_pop_tercile.csv
#   class_by_year_pop_tercile.csv
#
# Coverage classes (mutually exclusive among rows present in the union panel):
#   1. in_rais_panel       : in_rais == 1
#   2. in_rais_dropped     : N/A flagged - no upstream "dropped-by-filter" flag
#                            is preserved in the reconstructed panel. Limitation
#                            documented in findings.md.
#   3. bndes_only_no_rais  : in_bndes == 1 & in_rais == 0
#   4. owner_only_no_rais  : in_owner == 1 & in_rais == 0 & in_bndes == 0
#   5. other_no_rais       : residual (in_rais == 0 & in_bndes == 0 & in_owner == 0)
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fst)
  library(qs2)
  library(bit64)   # population_ibge stores `year` as integer64; required for
                   # `as.integer()` coercion to dispatch correctly.
})

# Reproducibility: no stochastic step here, but keep the convention.
set.seed(20260512L)

# ---- Paths (relative to project root) ----------------------------------------
script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
if (length(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = TRUE)
  project_root <- normalizePath(file.path(dirname(script_path), "..", "..", "..", ".."),
                                winslash = "/", mustWork = TRUE)
} else {
  project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

panel_path  <- file.path(project_root, "data", "processed", "rais_bndes_reconstructed.fst")
pop_path    <- file.path(project_root, "data", "processed", "population_ibge.qs2")
out_dir     <- file.path(project_root, "explorations", "firm_universe",
                         "rais_coverage_audit", "output")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ---- Preconditions -----------------------------------------------------------
stopifnot(
  "Input panel not found"      = file.exists(panel_path),
  "Population file not found"  = file.exists(pop_path)
)

message("[INFO] project_root: ", project_root)
message("[INFO] panel_path  : ", panel_path)
message("[INFO] out_dir     : ", out_dir)

# ---- Load union panel (selected columns only) --------------------------------
needed_cols <- c("firm_id", "year", "muni_id", "n_employees",
                 "cnae_section", "in_rais", "in_bndes", "in_owner")

message("[INFO] Reading union panel ...")
dt <- as.data.table(read_fst(panel_path, columns = needed_cols))
message("[INFO] Rows: ", format(nrow(dt), big.mark = ","))
message("[INFO] Cols: ", paste(names(dt), collapse = ", "))

# Sanity: in_rais/in_bndes/in_owner are integer 0/1 flags.
dt[, `:=`(
  in_rais  = as.integer(in_rais),
  in_bndes = as.integer(in_bndes),
  in_owner = as.integer(in_owner)
)]

# ---- Assign coverage class ---------------------------------------------------
# Mutually exclusive; order matters - in_rais_panel takes priority over all else.
dt[, coverage_class := fifelse(
  in_rais == 1L, "in_rais_panel",
  fifelse(in_bndes == 1L, "bndes_only_no_rais",
    fifelse(in_owner == 1L, "owner_only_no_rais", "other_no_rais")))]

# ---- Class 2 ("in_rais_dropped"): N/A ----------------------------------------
# The reconstructed panel does not preserve a flag identifying firms that were
# in RAIS-raw but dropped by upstream filters. Documented as a limitation in
# findings.md. Class is omitted from tabulations.

# ---- Overall counts ----------------------------------------------------------
overall <- dt[, .(n_rows = .N), by = coverage_class]
total_n <- sum(overall$n_rows)
overall[, share := n_rows / total_n]
setorder(overall, -n_rows)
fwrite(overall, file.path(out_dir, "class_overall.csv"))
message("[INFO] Overall class counts:"); print(overall)

# ---- By year -----------------------------------------------------------------
by_year <- dt[, .(n_rows = .N), by = .(year, coverage_class)]
by_year[, year_total := sum(n_rows), by = year]
by_year[, share_in_year := n_rows / year_total]
setorder(by_year, year, coverage_class)
fwrite(by_year, file.path(out_dir, "class_by_year.csv"))

# ---- By CNAE section ---------------------------------------------------------
by_cnae <- dt[, .(n_rows = .N), by = .(cnae_section, coverage_class)]
by_cnae[, cnae_total := sum(n_rows), by = cnae_section]
by_cnae[, share_in_cnae := n_rows / cnae_total]
setorder(by_cnae, cnae_section, coverage_class)
fwrite(by_cnae, file.path(out_dir, "class_by_cnae_section.csv"))

# ---- Muni population terciles -----------------------------------------------
message("[INFO] Building muni population terciles ...")
pop <- qs_read(pop_path)
setDT(pop)
# population_ibge uses 7-digit muni_id_ibge; panel uses 6-digit muni_id (no
# check digit). Take the first 6 chars of muni_id_ibge to merge.
pop[, muni_id := as.integer(substr(as.character(muni_id_ibge), 1L, 6L))]
# `year` is stored as integer64; coerce to base integer for comparison.
pop[, year := as.integer(year)]

# Use mean population over 2002-2017 to assign a single tercile per muni.
pop_panel <- pop[year >= 2002L & year <= 2017L,
                 .(pop_mean = mean(population, na.rm = TRUE)),
                 by = muni_id]
pop_panel <- pop_panel[is.finite(pop_mean) & pop_mean > 0]
# Rank-based terciles so duplicated population values do not collapse breaks.
pop_panel[, pop_rank := frank(pop_mean, ties.method = "first")]
n_munis <- nrow(pop_panel)
pop_panel[, pop_tercile := fifelse(
  pop_rank <= n_munis / 3, "T1_small",
  fifelse(pop_rank <= 2 * n_munis / 3, "T2_mid", "T3_large")
)]
pop_panel[, pop_rank := NULL]
message("[INFO] Muni tercile counts:"); print(pop_panel[, .N, by = pop_tercile])

dt <- merge(dt, pop_panel[, .(muni_id, pop_tercile)], by = "muni_id",
            all.x = TRUE, sort = FALSE)
n_unmatched <- dt[is.na(pop_tercile), .N]
message(sprintf("[INFO] Panel rows without pop tercile match: %s (%.2f%%)",
                format(n_unmatched, big.mark = ","),
                100 * n_unmatched / nrow(dt)))

by_pop <- dt[!is.na(pop_tercile), .(n_rows = .N),
             by = .(pop_tercile, coverage_class)]
by_pop[, tercile_total := sum(n_rows), by = pop_tercile]
by_pop[, share_in_tercile := n_rows / tercile_total]
setorder(by_pop, pop_tercile, coverage_class)
fwrite(by_pop, file.path(out_dir, "class_by_pop_tercile.csv"))

# Year x tercile cross-tab (richer view).
by_year_pop <- dt[!is.na(pop_tercile),
                  .(n_rows = .N),
                  by = .(year, pop_tercile, coverage_class)]
by_year_pop[, cell_total := sum(n_rows), by = .(year, pop_tercile)]
by_year_pop[, share := n_rows / cell_total]
setorder(by_year_pop, year, pop_tercile, coverage_class)
fwrite(by_year_pop, file.path(out_dir, "class_by_year_pop_tercile.csv"))

# ---- Headline summary printed to stdout --------------------------------------
message("\n==============================================================================")
message("HEADLINE SUMMARY")
message("==============================================================================")
message(sprintf("Total firm-year-muni rows in union panel: %s",
                format(total_n, big.mark = ",")))
message("\nClass shares (overall):")
print(overall)

# Year-level non-RAIS share trajectory.
yr_summary <- dcast(by_year, year ~ coverage_class,
                    value.var = "share_in_year", fill = 0)
message("\nNon-RAIS share by year (head/tail):")
print(head(yr_summary, 5)); print(tail(yr_summary, 5))

# CNAE sections with highest non-RAIS share.
cnae_nonrais <- by_cnae[coverage_class != "in_rais_panel",
                        .(non_rais_share = sum(share_in_cnae),
                          n_nonrais = sum(n_rows),
                          cnae_total = first(cnae_total)),
                        by = cnae_section]
setorder(cnae_nonrais, -non_rais_share)
message("\nTop CNAE sections by non-RAIS share:")
print(head(cnae_nonrais, 10))

message("\n[INFO] All outputs written to: ", out_dir)
message("[DONE]")
