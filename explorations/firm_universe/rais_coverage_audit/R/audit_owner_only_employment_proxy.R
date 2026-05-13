#!/usr/bin/env Rscript

# ==============================================================================
# A0.5 - Owner-only firm employment proxy
# ==============================================================================
# Author:  data-engineer (orchestrator dispatch)
# Date:    2026-05-12
# Purpose: Of the 3,373,874 Owner-only firm-year rows (7.64% of the union panel,
#          present in the Owner CNPJ table but absent from RAIS), how many
#          likely have a non-trivial number of employees? Direct employment is
#          unobservable for Owner-only firms by construction; this script
#          builds a 5-diagnostic proxy battery.
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst
#   data/raw/david_ra/owner_aff_firm_year_party_2002_2019.parquet
#   data/processed/population_ibge.qs2
#
# Outputs (under explorations/firm_universe/rais_coverage_audit/output/):
#   owner_only_cnae_distribution.csv
#   owner_only_owner_crossmembership.csv   (substitute: persistent vs single-yr)
#   owner_only_persistence.csv
#   owner_only_aff_owners.csv              (#4: number of co-owners per CNPJ)
#   owner_only_employment_bound.csv
#
# Note on diagnostic #2 (owner cross-membership):
#   The Owner table (owner_aff_firm_year_party_2002_2019.parquet) is keyed by
#   (firm_id, year) and does NOT include owner identifiers; only the COUNT of
#   affiliated owners (`aff_owners`) is preserved. We therefore CANNOT tabulate
#   whether the same owner controls multiple CNPJs. As a substitute, we
#   tabulate whether each Owner-only CNPJ ever appears in RAIS in some other
#   year (the same firm temporarily absent vs never-RAIS). This is the closest
#   feasible cross-membership signal given local data.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fst)
  library(qs2)
  library(arrow)
  library(bit64)
})

set.seed(20260512L)

# ---- Paths -------------------------------------------------------------------
script_args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", script_args, value = TRUE)
if (length(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg[[1]]),
                               winslash = "/", mustWork = TRUE)
  project_root <- normalizePath(file.path(dirname(script_path),
                                          "..", "..", "..", ".."),
                                winslash = "/", mustWork = TRUE)
} else {
  project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

panel_path <- file.path(project_root, "data", "processed",
                        "rais_bndes_reconstructed.fst")
owner_parquet <- file.path(project_root, "data", "raw", "david_ra",
                           "owner_aff_firm_year_party_2002_2019.parquet")
pop_path <- file.path(project_root, "data", "processed",
                      "population_ibge.qs2")
out_dir <- file.path(project_root, "explorations", "firm_universe",
                     "rais_coverage_audit", "output")

stopifnot(file.exists(panel_path))
stopifnot(file.exists(owner_parquet))
stopifnot(file.exists(pop_path))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

message("[INFO] project_root: ", project_root)
message("[INFO] out_dir     : ", out_dir)

# ---- Load union panel --------------------------------------------------------
message("[INFO] Reading union panel ...")
needed_cols <- c("firm_id", "year", "muni_id", "n_employees",
                 "cnae_section", "in_rais", "in_bndes", "in_owner")
dt <- as.data.table(read_fst(panel_path, columns = needed_cols))
dt[, `:=`(
  in_rais  = as.integer(in_rais),
  in_bndes = as.integer(in_bndes),
  in_owner = as.integer(in_owner)
)]
message("[INFO] Union-panel rows: ", format(nrow(dt), big.mark = ","))

# Owner-only class (matches A0.1 priority rule).
dt[, owner_only := as.integer(in_rais == 0L & in_bndes == 0L & in_owner == 1L)]
n_owner_only <- dt[owner_only == 1L, .N]
message("[INFO] Owner-only rows: ", format(n_owner_only, big.mark = ","))
stopifnot(n_owner_only > 0L)

# ---- Population terciles (same construction as A0.1) ------------------------
message("[INFO] Building muni population terciles ...")
pop <- qs_read(pop_path)
setDT(pop)
pop[, muni_id := as.integer(substr(as.character(muni_id_ibge), 1L, 6L))]
pop[, year := as.integer(year)]
pop_panel <- pop[year >= 2002L & year <= 2017L,
                 .(pop_mean = mean(population, na.rm = TRUE)),
                 by = muni_id]
pop_panel <- pop_panel[is.finite(pop_mean) & pop_mean > 0]
pop_panel[, pop_rank := frank(pop_mean, ties.method = "first")]
n_munis <- nrow(pop_panel)
pop_panel[, pop_tercile := fifelse(
  pop_rank <= n_munis / 3, "T1_small",
  fifelse(pop_rank <= 2 * n_munis / 3, "T2_mid", "T3_large")
)]
pop_panel[, pop_rank := NULL]
dt <- merge(dt, pop_panel[, .(muni_id, pop_tercile)], by = "muni_id",
            all.x = TRUE, sort = FALSE)

# ==============================================================================
# Diagnostic 1: CNAE composition + comparison to RAIS-covered tiny-firm pattern
# ==============================================================================
message("[INFO] Diagnostic 1: CNAE composition ...")

# Owner-only by CNAE section
oo_cnae <- dt[owner_only == 1L, .(n_owner_only = .N), by = cnae_section]
oo_cnae[, share_owner_only := n_owner_only / sum(n_owner_only)]

# RAIS-covered: distribution and share of tiny (n_employees in 1..4) by CNAE
rais_cnae <- dt[in_rais == 1L,
                .(n_rais = .N,
                  n_rais_1to4   = sum(n_employees >= 1L & n_employees <= 4L,
                                      na.rm = TRUE),
                  n_rais_5to19  = sum(n_employees >= 5L & n_employees <= 19L,
                                      na.rm = TRUE),
                  n_rais_20plus = sum(n_employees >= 20L, na.rm = TRUE),
                  median_emp    = as.numeric(median(n_employees, na.rm = TRUE)),
                  mean_emp      = mean(n_employees, na.rm = TRUE)),
                by = cnae_section]
rais_cnae[, share_rais_1to4 := n_rais_1to4 / n_rais]

cnae_dist <- merge(oo_cnae, rais_cnae, by = "cnae_section", all = TRUE)
setorder(cnae_dist, -n_owner_only)
fwrite(cnae_dist, file.path(out_dir, "owner_only_cnae_distribution.csv"))

# Owner-only-weighted average of (RAIS tiny share) across sectors:
# proxy for "if Owner-only firms behave like RAIS firms in their sector,
# what fraction would be 1-4 employees".
oo_total <- sum(cnae_dist$n_owner_only, na.rm = TRUE)
weighted_tiny_share <- sum(cnae_dist$n_owner_only *
                             cnae_dist$share_rais_1to4,
                           na.rm = TRUE) / oo_total
weighted_median_emp <- sum(cnae_dist$n_owner_only *
                             cnae_dist$median_emp,
                           na.rm = TRUE) / oo_total
message(sprintf("  Owner-only-weighted RAIS-tiny (1-4 emp) share: %.1f%%",
                100 * weighted_tiny_share))
message(sprintf("  Owner-only-weighted RAIS median employment    : %.2f",
                weighted_median_emp))

# ==============================================================================
# Diagnostic 2 (substitute): does the Owner-only CNPJ appear in RAIS in some
# OTHER year? (true firm cross-membership not feasible -- see header note)
# ==============================================================================
message("[INFO] Diagnostic 2 (substitute): firm-year-level cross-membership ...")

# Firms that ever appear in RAIS within 2002-2017
ever_rais_firms <- unique(dt[in_rais == 1L, .(firm_id)])
ever_rais_firms[, ever_rais := 1L]

oo_firms <- unique(dt[owner_only == 1L, .(firm_id)])
oo_firms <- merge(oo_firms, ever_rais_firms, by = "firm_id", all.x = TRUE)
oo_firms[is.na(ever_rais), ever_rais := 0L]

cross_tab <- oo_firms[, .(n_firms = .N), by = ever_rais]
cross_tab[, share := n_firms / sum(n_firms)]
cross_tab[, label := fifelse(ever_rais == 1L,
                             "owner_only_year_but_in_RAIS_other_year",
                             "never_in_RAIS_any_year")]
fwrite(cross_tab[, .(label, ever_rais, n_firms, share)],
       file.path(out_dir, "owner_only_owner_crossmembership.csv"))
message(sprintf(
  "  Owner-only firms ever observed in RAIS in some year: %s (%.1f%%)",
  format(cross_tab[ever_rais == 1L, n_firms], big.mark = ","),
  100 * cross_tab[ever_rais == 1L, share]
))
message(sprintf(
  "  Owner-only firms NEVER in RAIS in any year        : %s (%.1f%%)",
  format(cross_tab[ever_rais == 0L, n_firms], big.mark = ","),
  100 * cross_tab[ever_rais == 0L, share]
))

# Per-row attribution: tag each owner_only ROW with whether the firm appears
# in RAIS in any year (used as a "likely operational" indicator downstream).
dt[oo_firms, ever_rais_any_year := i.ever_rais, on = "firm_id"]

# ==============================================================================
# Diagnostic 3: persistence -- years the CNPJ appears in the Owner table
# ==============================================================================
message("[INFO] Diagnostic 3: persistence ...")

# Persistence within Owner-only rows: distinct years per firm.
persistence <- dt[owner_only == 1L,
                  .(n_years_owner_only = uniqueN(year)),
                  by = firm_id]
persist_tab <- persistence[, .(n_firms = .N), by = n_years_owner_only]
setorder(persist_tab, n_years_owner_only)
persist_tab[, share_firms := n_firms / sum(n_firms)]
persist_tab[, n_rows := n_firms * n_years_owner_only]
persist_tab[, share_rows := n_rows / sum(n_rows)]
fwrite(persist_tab, file.path(out_dir, "owner_only_persistence.csv"))

single_year_share_firms <- persist_tab[n_years_owner_only == 1L, share_firms]
single_year_share_rows  <- persist_tab[n_years_owner_only == 1L, share_rows]
message(sprintf("  Single-year owner-only firms: %.1f%% of firms / %.1f%% of rows",
                100 * single_year_share_firms,
                100 * single_year_share_rows))

# ==============================================================================
# Diagnostic 4: aff_owners distribution (number of affiliated owners per CNPJ)
# ==============================================================================
message("[INFO] Diagnostic 4: aff_owners distribution from owner parquet ...")

owner_ds <- arrow::open_dataset(owner_parquet)
owner_min <- owner_ds |>
  dplyr::select(firm_id, year, aff_owners) |>
  dplyr::filter(year >= 2002L, year <= 2017L) |>
  dplyr::collect() |>
  as.data.table()
owner_min[, firm_id := as.integer(firm_id)]
owner_min[, year := as.integer(year)]
owner_min[, aff_owners := as.integer(aff_owners)]
owner_min <- owner_min[!is.na(firm_id) & !is.na(year)]

# The parquet is keyed by (firm_id, year, party); a CNPJ with owners affiliated
# to multiple parties has multiple rows. For owner-count diagnostics we want
# one row per (firm_id, year): take the max aff_owners across party rows
# (the COUNT of distinct owners; safe upper bound when party rows reflect
# party breakdowns of the same owner set).
owner_min <- owner_min[, .(aff_owners = max(aff_owners, na.rm = TRUE)),
                      by = .(firm_id, year)]

# Restrict to Owner-only rows (firm_id, year)
oo_key <- dt[owner_only == 1L, .(firm_id, year)]
oo_owners <- merge(oo_key, owner_min, by = c("firm_id", "year"))
message(sprintf("  Owner-only rows joined to owner-count table: %s / %s (%.1f%%)",
                format(nrow(oo_owners), big.mark = ","),
                format(n_owner_only, big.mark = ","),
                100 * nrow(oo_owners) / n_owner_only))

aff_tab <- oo_owners[, .(n_rows = .N), by = aff_owners]
setorder(aff_tab, aff_owners)
aff_tab[, share := n_rows / sum(n_rows)]
# Coarse buckets
aff_tab[, bucket := fcase(
  aff_owners == 1L, "1_owner",
  aff_owners == 2L, "2_owners",
  aff_owners >= 3L & aff_owners <= 5L, "3to5_owners",
  aff_owners >= 6L, "6plus_owners",
  default = "unknown"
)]
aff_bucket <- aff_tab[, .(n_rows = sum(n_rows),
                         share  = sum(share)), by = bucket]
setorder(aff_bucket, -n_rows)
fwrite(list_to_dt <- rbindlist(list(
  cbind(aff_tab[, .(level = as.character(aff_owners), n_rows, share)],
        kind = "exact"),
  cbind(aff_bucket[, .(level = bucket, n_rows, share)], kind = "bucket")
)), file.path(out_dir, "owner_only_aff_owners.csv"))

share_single_owner <- aff_bucket[bucket == "1_owner", share]
share_multi_owner  <- 1 - share_single_owner
message(sprintf("  Single-owner Owner-only rows: %.1f%% | Multi-owner: %.1f%%",
                100 * share_single_owner, 100 * share_multi_owner))

# ==============================================================================
# Diagnostic 5: counterfactual employment-mass bound
# Impute each Owner-only firm-row's employment as the median of RAIS firms
# in the same CNAE section x population tercile cell. Compute total formal-
# sector employment with vs without imputation; report the delta as an
# upper-bound contribution to n_{mt}.
# ==============================================================================
message("[INFO] Diagnostic 5: counterfactual employment-mass bound ...")

# Cell-level medians and percentiles among RAIS firms.
rais_cells <- dt[in_rais == 1L & !is.na(cnae_section) & !is.na(pop_tercile),
                 .(median_emp_cell = as.numeric(median(n_employees, na.rm = TRUE)),
                   p25_emp_cell    = as.numeric(quantile(n_employees, 0.25,
                                                         na.rm = TRUE)),
                   mean_emp_cell   = mean(n_employees, na.rm = TRUE),
                   n_rais_cell     = .N),
                 by = .(cnae_section, pop_tercile, year)]

# Yearly RAIS total employment.
year_totals <- dt[in_rais == 1L,
                  .(rais_total_emp = sum(n_employees, na.rm = TRUE),
                    rais_rows      = .N),
                  by = year]

# Owner-only rows tagged with cell median/p25.
oo_rows <- dt[owner_only == 1L & !is.na(cnae_section) & !is.na(pop_tercile),
              .(firm_id, year, muni_id, cnae_section, pop_tercile,
                ever_rais_any_year)]
oo_rows <- merge(oo_rows, rais_cells,
                 by = c("cnae_section", "pop_tercile", "year"),
                 all.x = TRUE)

# Fallback: rows in cells with no RAIS data (rare). Use year-wide median.
year_median <- dt[in_rais == 1L,
                  .(year_median = as.numeric(median(n_employees, na.rm = TRUE)),
                    year_p25    = as.numeric(quantile(n_employees, 0.25,
                                                      na.rm = TRUE))),
                  by = year]
oo_rows <- merge(oo_rows, year_median, by = "year", all.x = TRUE)
oo_rows[is.na(median_emp_cell), median_emp_cell := year_median]
oo_rows[is.na(p25_emp_cell), p25_emp_cell := year_p25]

# Two imputations: conservative (P25) and central (median).
oo_rows[, imp_median := median_emp_cell]
oo_rows[, imp_p25    := p25_emp_cell]

# Yearly imputed mass (full Owner-only set and "ever_rais" subset only).
oo_year <- oo_rows[, .(
  oo_rows_n            = .N,
  oo_rows_ever_rais    = sum(ever_rais_any_year == 1L, na.rm = TRUE),
  imp_total_median     = sum(imp_median, na.rm = TRUE),
  imp_total_p25        = sum(imp_p25, na.rm = TRUE),
  imp_total_median_ER  = sum(imp_median * (ever_rais_any_year == 1L),
                             na.rm = TRUE),
  imp_total_p25_ER     = sum(imp_p25 * (ever_rais_any_year == 1L),
                             na.rm = TRUE)
), by = year]

bound <- merge(year_totals, oo_year, by = "year")
bound[, share_added_median        := imp_total_median / rais_total_emp]
bound[, share_added_p25           := imp_total_p25 / rais_total_emp]
bound[, share_added_median_ER     := imp_total_median_ER / rais_total_emp]
bound[, share_added_p25_ER        := imp_total_p25_ER / rais_total_emp]
setorder(bound, year)
fwrite(bound, file.path(out_dir, "owner_only_employment_bound.csv"))

avg_share_median    <- mean(bound$share_added_median, na.rm = TRUE)
avg_share_p25       <- mean(bound$share_added_p25, na.rm = TRUE)
avg_share_median_ER <- mean(bound$share_added_median_ER, na.rm = TRUE)
avg_share_p25_ER    <- mean(bound$share_added_p25_ER, na.rm = TRUE)
message(sprintf("  Avg yearly share added (median imputation, ALL OO)        : %.2f%%",
                100 * avg_share_median))
message(sprintf("  Avg yearly share added (P25 imputation, ALL OO)           : %.2f%%",
                100 * avg_share_p25))
message(sprintf("  Avg yearly share added (median imputation, ever-RAIS only): %.2f%%",
                100 * avg_share_median_ER))
message(sprintf("  Avg yearly share added (P25 imputation, ever-RAIS only)   : %.2f%%",
                100 * avg_share_p25_ER))

# ---- Headline summary --------------------------------------------------------
message("")
message("==============================================================================")
message("A0.5 HEADLINE SUMMARY")
message("==============================================================================")
message(sprintf("Owner-only firm-year rows               : %s",
                format(n_owner_only, big.mark = ",")))
message(sprintf("Owner-only-weighted RAIS-tiny (1-4) share: %.1f%%",
                100 * weighted_tiny_share))
message(sprintf("Owner-only-weighted RAIS median emp     : %.2f",
                weighted_median_emp))
message(sprintf("Owner-only firms ever in RAIS some year : %.1f%%",
                100 * cross_tab[ever_rais == 1L, share]))
message(sprintf("Single-year owner-only firms (of firms) : %.1f%%",
                100 * single_year_share_firms))
message(sprintf("Single-owner Owner-only rows            : %.1f%%",
                100 * share_single_owner))
message(sprintf("Upper-bound mass added (median, all OO) : %.2f%% of RAIS emp",
                100 * avg_share_median))
message(sprintf("Lower-bound mass added (P25, ever-RAIS) : %.2f%% of RAIS emp",
                100 * avg_share_p25_ER))
message("")
message("[INFO] All outputs written to: ", out_dir)
message("[DONE]")
