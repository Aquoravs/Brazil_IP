#!/usr/bin/env Rscript

# ==============================================================================
# Diagnostic: Sector-Group Cell Support
# ==============================================================================
# Descriptive diagnostic for the sector_group x muni_id x year cell panel used
# in grouped sector specifications.
#
# Focus:
#   - cell support: number of firms per active grouped cell
#   - loan support: how often grouped cells have positive BNDES credit
#   - concentration: how BNDES value shares distribute across grouped cells
#   - affiliation support: how many firms in a grouped cell have any observed
#     party affiliation other than "No party"
#
# This script is descriptive only. It does not run regressions.
# ==============================================================================

cat("==============================================================================\n")
cat("Diagnostic: Sector-Group Cell Support\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})

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

have_fst <- requireNamespace("fst", quietly = TRUE)
have_ggplot2 <- requireNamespace("ggplot2", quietly = TRUE)

OUT_DIR <- make_output_path(file.path("diagnostics", "sector_group_cell_support"))
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

SECTOR_LEVELS <- c("Ag", "Mi", "CL", "CH", "CA", "UCo", "Tr", "Tp", "MS", "PSO", "XX")
CELL_SIZE_LEVELS <- c("1", "2", "3-5", "6-10", "11-20", "21-50", "50+")
AFF_BIN_LEVELS <- c("0%", "(0,10%]", "(10,25%]", "(25,50%]", "50%+")
NO_PARTY_VALUES <- c("NO PARTY", "SEM PARTIDO", "")

save_csv <- function(dt, filename) {
  path <- file.path(OUT_DIR, filename)
  fwrite(dt, path)
  cat("  Saved:", path, "\n")
  invisible(path)
}

save_qs <- function(obj, filename) {
  path <- file.path(OUT_DIR, filename)
  qs_save(obj, path)
  cat("  Saved:", path, "\n")
  invisible(path)
}

save_text <- function(lines, filename) {
  path <- file.path(OUT_DIR, filename)
  writeLines(lines, path, useBytes = TRUE)
  cat("  Saved:", path, "\n")
  invisible(path)
}

fmt_n <- function(x) format(round(x), big.mark = ",", scientific = FALSE, trim = TRUE)
fmt_num <- function(x, digits = 2) format(round(x, digits), big.mark = ",", scientific = FALSE, nsmall = digits, trim = TRUE)
fmt_pct <- function(x, digits = 1) sprintf(paste0("%.", digits, "f%%"), 100 * x)

share_or_na <- function(num, den) {
  ifelse(den > 0, num / den, NA_real_)
}

cell_size_bin <- function(n) {
  out <- fifelse(
    n == 1L, "1",
    fifelse(
      n == 2L, "2",
      fifelse(
        n >= 3L & n <= 5L, "3-5",
        fifelse(
          n >= 6L & n <= 10L, "6-10",
          fifelse(
            n >= 11L & n <= 20L, "11-20",
            fifelse(n >= 21L & n <= 50L, "21-50", "50+")
          )
        )
      )
    )
  )
  factor(out, levels = CELL_SIZE_LEVELS)
}

affiliation_bin <- function(x) {
  out <- fifelse(
    x <= 0, "0%",
    fifelse(
      x <= 0.10, "(0,10%]",
      fifelse(
        x <= 0.25, "(10,25%]",
        fifelse(x <= 0.50, "(25,50%]", "50%+")
      )
    )
  )
  factor(out, levels = AFF_BIN_LEVELS)
}

quantile_safe <- function(x, prob) {
  x <- x[!is.na(x)]
  if (!length(x)) return(NA_real_)
  as.numeric(stats::quantile(x, probs = prob, na.rm = TRUE, names = FALSE))
}

mean_or_na <- function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)
median_or_na <- function(x) if (all(is.na(x))) NA_real_ else stats::median(x, na.rm = TRUE)
max_or_na <- function(x) if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE)
sd_or_na <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) <= 1L) return(NA_real_)
  stats::sd(x)
}

plot_save <- function(plot_obj, filename, width = 10, height = 6) {
  if (!have_ggplot2) return(invisible(FALSE))
  path <- file.path(OUT_DIR, filename)
  ggplot2::ggsave(filename = path, plot = plot_obj, width = width, height = height, units = "in")
  cat("  Saved:", path, "\n")
  invisible(TRUE)
}

load_panel_base <- function() {
  panel_cols <- c("firm_id", "muni_id", "year", "cnae_section", "value_dis_real_2018_total", "classe")
  recon_fst  <- make_output_path("rais_bndes_reconstructed.fst")
  recon_qs2  <- make_output_path("rais_bndes_reconstructed.qs2")

  # Attempt to load from the split base panel (no instruments needed here).
  paths_sg <- firm_panel_paths("cycle_specific")
  if (file.exists(paths_sg$base) && have_fst) {
    base_meta_cols <- fst::metadata_fst(paths_sg$base)$columnNames
    if (all(panel_cols %in% base_meta_cols)) {
      dt <- load_firm_panel(
        baseline_type = "cycle_specific",
        columns       = panel_cols,
        instruments   = character(0),
        as_data_table = TRUE
      )
      return(list(dt = dt, source = basename(paths_sg$base)))
    }
  }

  # Fallback to reconstructed panel (has `classe` column).
  fallback_cols <- panel_cols
  if (file.exists(recon_fst) && have_fst) {
    dt <- fst::read_fst(recon_fst, columns = fallback_cols, as.data.table = TRUE)
    return(list(
      dt = dt,
      source = paste0(basename(recon_fst), " (fallback: firm_panel_for_regs lacks `classe` needed for exact sector_group mapping)")
    ))
  }

  if (file.exists(recon_qs2)) {
    raw <- qs_read(recon_qs2)
    setDT(raw)
    dt <- raw[, ..fallback_cols]
    rm(raw)
    invisible(gc())
    return(list(
      dt = dt,
      source = paste0(basename(recon_qs2), " (fallback: firm_panel_for_regs lacks `classe` needed for exact sector_group mapping)")
    ))
  }

  stop(
    "Could not load a panel with `classe` and `value_dis_real_2018_total`.\n",
    "Checked: ", paths_sg$base, ", ", recon_fst, ", ", recon_qs2
  )
}

cat("Step 1: Loading firm-level panel base...\n")
panel_info <- load_panel_base()
panel <- panel_info$dt
panel_source <- panel_info$source
setDT(panel)
panel[, firm_id := as.integer(firm_id)]
panel[, muni_id := as.integer(muni_id)]
panel[, year := as.integer(year)]
panel[, value_dis_real_2018_total := fifelse(is.na(value_dis_real_2018_total), 0, value_dis_real_2018_total)]
panel <- panel[!is.na(firm_id) & !is.na(muni_id) & muni_id > 0L & !is.na(year)]
cat("  Panel source:", panel_source, "\n")
cat("  Rows:", fmt_n(nrow(panel)), "\n")
cat("  Firm-muni-years:", fmt_n(uniqueN(panel, by = c("firm_id", "muni_id", "year"))), "\n")
cat("  Firms:", fmt_n(uniqueN(panel$firm_id)), "\n")
cat("  Munis:", fmt_n(uniqueN(panel$muni_id)), "\n")
cat("  Years:", min(panel$year), "-", max(panel$year), "\n\n")

cat("Step 2: Mapping rows into sector_group...\n")
mapping_path <- make_output_path("sector_group_mapping.qs2")
if (!file.exists(mapping_path)) {
  stop("Sector-group mapping not found: ", mapping_path, "\nRun script 30 first.")
}
mapping <- qs_read(mapping_path)
setDT(mapping)
mapping <- unique(mapping[, .(cnae_division, cnae_section, sector_group, sector_group_label)])

panel[, cnae_division := as.integer(floor(as.numeric(classe) / 1000))]
panel[mapping, `:=`(
  sector_group = i.sector_group,
  sector_group_label = i.sector_group_label
), on = "cnae_division"]

section_map <- unique(mapping[cnae_section != "C", .(cnae_section, sector_group, sector_group_label)])
panel[is.na(sector_group), `:=`(
  sector_group = section_map$sector_group[match(cnae_section, section_map$cnae_section)],
  sector_group_label = section_map$sector_group_label[match(cnae_section, section_map$cnae_section)]
)]

n_unmapped <- panel[is.na(sector_group), .N]
if (n_unmapped > 0L) {
  cat("  WARNING: Unmapped rows:", fmt_n(n_unmapped), "\n")
  panel <- panel[!is.na(sector_group)]
}

panel[, sector_group := factor(as.character(sector_group), levels = SECTOR_LEVELS)]
panel[, sector_group := as.character(sector_group)]
cat("  Rows after sector-group mapping:", fmt_n(nrow(panel)), "\n")
cat("  Sector groups present:", paste(unique(panel$sector_group[order(match(panel$sector_group, SECTOR_LEVELS))]), collapse = ", "), "\n\n")

cat("Step 3: Loading observed firm-year affiliation support...\n")
aff_path <- make_base_path(file.path("raw", "david_ra", "owner_aff_firm_year_party_2002_2019.qs2"))
if (!file.exists(aff_path)) {
  stop("Affiliation data not found: ", aff_path)
}
aff <- qs_read(aff_path)
setDT(aff)
keep_aff_cols <- intersect(c("firm_id", "year", "party", "aff_owners"), names(aff))
aff <- aff[, ..keep_aff_cols]
aff[, firm_id := suppressWarnings(as.integer(firm_id))]
aff[, year := as.integer(year)]
if (!"aff_owners" %in% names(aff)) {
  aff[, aff_owners := 1]
}
aff[, party_clean := toupper(trimws(as.character(party)))]
aff[, has_named_party_row := !is.na(party_clean) & !party_clean %in% NO_PARTY_VALUES & aff_owners > 0]
aff_firm_year <- aff[, .(
  firm_has_affiliation = as.integer(any(has_named_party_row, na.rm = TRUE)),
  has_no_party_row = any(!is.na(party_clean) & party_clean %in% NO_PARTY_VALUES, na.rm = TRUE),
  has_named_party_row = any(has_named_party_row, na.rm = TRUE),
  n_party_rows = .N
), by = .(firm_id, year)]
cat("  Affiliation firm-years:", fmt_n(nrow(aff_firm_year)), "\n")
cat("  Observed affiliated firm-years:", fmt_n(sum(aff_firm_year$firm_has_affiliation, na.rm = TRUE)), "\n\n")

cat("Step 4: Attaching affiliation support to the panel...\n")
panel[aff_firm_year, firm_has_affiliation := i.firm_has_affiliation, on = .(firm_id, year)]
panel[is.na(firm_has_affiliation), firm_has_affiliation := 0L]
panel[, firm_has_affiliation := as.integer(firm_has_affiliation > 0)]
cat("  Panel rows with affiliated firms:", fmt_n(sum(panel$firm_has_affiliation, na.rm = TRUE)), "\n\n")

cat("Step 5: Building sector_group x muni_id x year cell panel...\n")
cell_panel <- panel[, .(
  n_firms = .N,
  n_affiliated_firms = sum(firm_has_affiliation, na.rm = TRUE),
  bndes_amt = sum(value_dis_real_2018_total, na.rm = TRUE)
) , by = .(sector_group, sector_group_label, muni_id, year)]

cell_panel[, share_affiliated_firms := share_or_na(n_affiliated_firms, n_firms)]
cell_panel[, has_bndes_cell := as.integer(bndes_amt > 0)]
cell_panel[, cell_size_bin := cell_size_bin(n_firms)]
cell_panel[, affiliation_bin := affiliation_bin(share_affiliated_firms)]

muni_totals <- cell_panel[, .(total_bndes_muni_year = sum(bndes_amt, na.rm = TRUE)), by = .(muni_id, year)]
cell_panel[muni_totals, total_bndes_muni_year := i.total_bndes_muni_year, on = .(muni_id, year)]
cell_panel[, s_cell := fifelse(total_bndes_muni_year > 0, bndes_amt / total_bndes_muni_year, NA_real_)]

cell_panel[, sector_group_order := match(sector_group, SECTOR_LEVELS)]
setorder(cell_panel, year, muni_id, sector_group_order)
cell_panel[, sector_group_order := NULL]

cat("  Active grouped cells:", fmt_n(nrow(cell_panel)), "\n")
cat("  Mean firms per cell:", fmt_num(mean(cell_panel$n_firms), 2), "\n")
cat("  Median firms per cell:", fmt_num(median(cell_panel$n_firms), 0), "\n")
cat("  Cells with positive BNDES:", fmt_n(sum(cell_panel$has_bndes_cell)), "\n\n")

cat("Step 6: Running validation checks...\n")
validation <- list()

add_check <- function(check_name, pass, value, details = "", status_if_fail = "FAIL") {
  validation[[length(validation) + 1L]] <<- data.table(
    check = check_name,
    status = ifelse(isTRUE(pass), "PASS", status_if_fail),
    value = as.character(value),
    details = as.character(details)
  )
}

add_check(
  "sector_group_mapping_coverage",
  n_unmapped == 0L,
  paste0("unmapped_rows=", n_unmapped, "; share=", fmt_pct(n_unmapped / (nrow(panel) + n_unmapped), 2)),
  "Rows without a valid sector_group after exact division mapping and non-C section fallback.",
  status_if_fail = "WARN"
)

firm_year_group_counts <- unique(panel[, .(firm_id, year, sector_group)])
firm_year_group_counts <- firm_year_group_counts[, .(n_sector_groups = .N), by = .(firm_id, year)]
n_multi_group_fy <- firm_year_group_counts[n_sector_groups > 1L, .N]
add_check(
  "firm_year_maps_to_at_most_one_sector_group",
  n_multi_group_fy == 0L,
  paste0("violations=", n_multi_group_fy, "; share=", fmt_pct(n_multi_group_fy / nrow(firm_year_group_counts), 3)),
  "Computed on distinct (firm_id, year, sector_group) rows.",
  status_if_fail = "WARN"
)

n_aff_over <- cell_panel[n_affiliated_firms > n_firms, .N]
share_out_of_bounds <- cell_panel[share_affiliated_firms < -1e-12 | share_affiliated_firms > 1 + 1e-12, .N]
add_check(
  "affiliation_counts_and_shares_valid",
  n_aff_over == 0L && share_out_of_bounds == 0L,
  paste0("n_aff_gt_n=", n_aff_over, "; share_out_of_bounds=", share_out_of_bounds),
  "Requires n_affiliated_firms <= n_firms and share_affiliated_firms in [0,1]."
)

panel_total_bndes <- panel[, sum(value_dis_real_2018_total, na.rm = TRUE)]
cell_total_bndes <- cell_panel[, sum(bndes_amt, na.rm = TRUE)]
total_gap <- abs(panel_total_bndes - cell_total_bndes)
add_check(
  "bndes_totals_preserved_after_grouping",
  isTRUE(all.equal(panel_total_bndes, cell_total_bndes, tolerance = 1e-8)),
  fmt_num(total_gap, 8),
  "Absolute difference between firm-level and cell-level total BNDES."
)

sums_s <- cell_panel[total_bndes_muni_year > 0, .(sum_s = sum(s_cell, na.rm = TRUE)), by = .(muni_id, year)]
max_s_deviation <- sums_s[, max(abs(sum_s - 1), na.rm = TRUE)]
if (!is.finite(max_s_deviation)) max_s_deviation <- NA_real_
add_check(
  "share_sums_equal_one_when_total_positive",
  is.na(max_s_deviation) || max_s_deviation <= 1e-8,
  fmt_num(max_s_deviation, 10),
  "Maximum absolute deviation of sum_j s_cell from 1 in muni-years with positive total BNDES."
)

mixed_affiliation <- aff_firm_year[has_no_party_row == TRUE & has_named_party_row == TRUE]
n_mixed_affiliation <- nrow(mixed_affiliation)
n_mixed_fail <- mixed_affiliation[firm_has_affiliation != 1L, .N]
add_check(
  "mixed_no_party_and_named_party_counts_as_affiliated",
  n_mixed_fail == 0L,
  paste0("mixed_cases=", n_mixed_affiliation, "; failures=", n_mixed_fail),
  "Firm-years with both `No party` and named-party rows must count as affiliated."
)

validation_dt <- rbindlist(validation, use.names = TRUE, fill = TRUE)
save_csv(validation_dt, "validation_checks.csv")

spotcheck_dt <- aff[mixed_affiliation, on = .(firm_id, year)][
  order(firm_id, year, party)
]
if (nrow(spotcheck_dt) > 0L) {
  spotcheck_dt <- merge(
    spotcheck_dt[, .(firm_id, year, party, aff_owners)],
    mixed_affiliation[, .(firm_id, year, firm_has_affiliation)],
    by = c("firm_id", "year"),
    all.x = TRUE,
    all.y = FALSE
  )
}
if (nrow(spotcheck_dt) > 0L) {
  save_csv(head(spotcheck_dt, 50L), "validation_mixed_affiliation_spotcheck.csv")
}

cat("  Validation summary:\n")
print(validation_dt)
cat("\n")

cat("Step 7: Saving main cell panel...\n")
save_qs(cell_panel, "sector_group_cell_panel.qs2")
save_csv(cell_panel, "sector_group_cell_panel.csv")
cat("\n")

cat("Step 8: Building cell-size support tables...\n")
cell_size_overall <- cell_panel[, .N, by = cell_size_bin][
  , share := N / sum(N)
][order(cell_size_bin)]
cell_size_by_year <- cell_panel[, .N, by = .(year, cell_size_bin)][
  , share := N / sum(N), by = year
][order(year, cell_size_bin)]
cell_size_by_sector <- cell_panel[, .N, by = .(sector_group, cell_size_bin)][
  , share := N / sum(N), by = sector_group
][order(match(sector_group, SECTOR_LEVELS), cell_size_bin)]

save_csv(cell_size_overall, "1_cell_size_distribution_overall.csv")
save_csv(cell_size_by_year, "1_cell_size_distribution_by_year.csv")
save_csv(cell_size_by_sector, "1_cell_size_distribution_by_sector_group.csv")
cat("\n")

cat("Step 9: Building loan-support coverage tables...\n")
loan_support_muni_year <- cell_panel[, .(
  n_active_groups = .N,
  n_positive_groups = sum(has_bndes_cell, na.rm = TRUE),
  share_positive_groups = mean(has_bndes_cell, na.rm = TRUE),
  total_bndes_muni_year = unique(total_bndes_muni_year)[1]
), by = .(muni_id, year)]

loan_support_year_sector <- cell_panel[, .(
  n_active_cells = .N,
  n_positive_cells = sum(has_bndes_cell, na.rm = TRUE),
  share_positive_cells = mean(has_bndes_cell, na.rm = TRUE),
  mean_bndes_amt_positive = mean_or_na(bndes_amt[has_bndes_cell == 1L]),
  median_bndes_amt_positive = median_or_na(bndes_amt[has_bndes_cell == 1L]),
  mean_s_cell_positive = mean_or_na(s_cell[has_bndes_cell == 1L & !is.na(s_cell)]),
  median_s_cell_positive = median_or_na(s_cell[has_bndes_cell == 1L & !is.na(s_cell)])
), by = .(year, sector_group, sector_group_label)][order(year, match(sector_group, SECTOR_LEVELS))]

save_csv(loan_support_muni_year, "2_loan_support_by_muni_year.csv")
save_csv(loan_support_year_sector, "2_loan_support_by_year_sector_group.csv")
cat("\n")

cat("Step 10: Building concentration tables...\n")
concentration_muni_year <- cell_panel[, .(
  n_active_groups = .N,
  n_positive_groups = sum(has_bndes_cell, na.rm = TRUE),
  share_positive_groups = mean(has_bndes_cell, na.rm = TRUE),
  total_bndes_muni_year = unique(total_bndes_muni_year)[1],
  hhi_s_cell = if (unique(total_bndes_muni_year)[1] > 0) sum(s_cell^2, na.rm = TRUE) else NA_real_,
  top_sector_share = if (unique(total_bndes_muni_year)[1] > 0) max(s_cell, na.rm = TRUE) else NA_real_
), by = .(muni_id, year)]

concentration_summary_by_year <- concentration_muni_year[, .(
  n_muni_year = .N,
  mean_n_active_groups = as.numeric(mean(n_active_groups, na.rm = TRUE)),
  median_n_active_groups = as.numeric(median(n_active_groups, na.rm = TRUE)),
  mean_n_positive_groups = as.numeric(mean(n_positive_groups, na.rm = TRUE)),
  median_n_positive_groups = as.numeric(median(n_positive_groups, na.rm = TRUE)),
  mean_hhi_s_cell = mean_or_na(hhi_s_cell),
  median_hhi_s_cell = median_or_na(hhi_s_cell),
  p10_hhi_s_cell = quantile_safe(hhi_s_cell, 0.10),
  p90_hhi_s_cell = quantile_safe(hhi_s_cell, 0.90),
  mean_top_sector_share = mean_or_na(top_sector_share),
  median_top_sector_share = median_or_na(top_sector_share)
), by = year][order(year)]

positive_group_count_dt <- concentration_muni_year[, .(
  positive_group_bucket = fifelse(
    n_positive_groups == 0L, "0",
    fifelse(n_positive_groups == 1L, "1", "2+")
  )
), by = .(muni_id, year)]
positive_group_count_share_by_year <- positive_group_count_dt[, .N, by = .(year, positive_group_bucket)][
  , share := N / sum(N), by = year
][order(year, positive_group_bucket)]
positive_group_count_share_overall <- positive_group_count_dt[, .N, by = positive_group_bucket][
  , share := N / sum(N)
][order(positive_group_bucket)]

save_csv(concentration_muni_year, "3_concentration_by_muni_year.csv")
save_csv(concentration_summary_by_year, "3_concentration_summary_by_year.csv")
save_csv(positive_group_count_share_by_year, "3_positive_group_count_share_by_year.csv")
save_csv(positive_group_count_share_overall, "3_positive_group_count_share_overall.csv")
cat("\n")

cat("Step 11: Building affiliation-support tables...\n")
affiliation_support_sector_year <- cell_panel[, .(
  n_cells = .N,
  mean_share_affiliated_firms = mean(share_affiliated_firms, na.rm = TRUE),
  median_share_affiliated_firms = median(share_affiliated_firms, na.rm = TRUE),
  share_cells_with_any_affiliation = mean(n_affiliated_firms > 0L, na.rm = TRUE)
), by = .(year, sector_group, sector_group_label)][order(year, match(sector_group, SECTOR_LEVELS))]

affiliation_support_muni_year <- cell_panel[, .(
  n_active_groups = .N,
  n_groups_with_any_affiliation = sum(n_affiliated_firms > 0L, na.rm = TRUE),
  share_groups_with_any_affiliation = mean(n_affiliated_firms > 0L, na.rm = TRUE),
  mean_share_affiliated_firms = mean(share_affiliated_firms, na.rm = TRUE),
  median_share_affiliated_firms = median(share_affiliated_firms, na.rm = TRUE),
  sd_share_affiliated_firms = sd_or_na(share_affiliated_firms)
), by = .(muni_id, year)]

affiliation_support_by_sector <- cell_panel[, .(
  n_cells = .N,
  mean_share_affiliated_firms = mean(share_affiliated_firms, na.rm = TRUE),
  median_share_affiliated_firms = median(share_affiliated_firms, na.rm = TRUE),
  p10_share_affiliated_firms = quantile_safe(share_affiliated_firms, 0.10),
  p90_share_affiliated_firms = quantile_safe(share_affiliated_firms, 0.90),
  share_cells_with_zero_affiliation = mean(share_affiliated_firms == 0, na.rm = TRUE)
), by = .(sector_group, sector_group_label)][order(match(sector_group, SECTOR_LEVELS))]

affiliation_bins_by_sector <- cell_panel[, .N, by = .(sector_group, affiliation_bin)][
  , share := N / sum(N), by = sector_group
][order(match(sector_group, SECTOR_LEVELS), affiliation_bin)]
affiliation_bins_overall <- cell_panel[, .N, by = affiliation_bin][
  , share := N / sum(N)
][order(affiliation_bin)]

save_csv(affiliation_support_sector_year, "4_affiliation_support_by_sector_group_year.csv")
save_csv(affiliation_support_muni_year, "4_affiliation_support_by_muni_year.csv")
save_csv(affiliation_support_by_sector, "4_affiliation_support_distribution_by_sector_group.csv")
save_csv(affiliation_bins_by_sector, "4_affiliation_support_bins_by_sector_group.csv")
save_csv(affiliation_bins_overall, "4_affiliation_support_bins_overall.csv")
cat("\n")

if (have_ggplot2) {
  cat("Step 12: Saving diagnostic plots...\n")
  ggplot2 <- asNamespace("ggplot2")

  plot_cell_size_year <- ggplot2$ggplot(
    cell_size_by_year,
    ggplot2$aes(x = factor(year), y = share, fill = cell_size_bin)
  ) +
    ggplot2$geom_col(position = "stack") +
    ggplot2$labs(
      title = "Grouped Cell Size Distribution by Year",
      x = "Year",
      y = "Share of active grouped cells",
      fill = "Firms in cell"
    ) +
    ggplot2$theme_minimal(base_size = 11)

  plot_cell_size_sector <- ggplot2$ggplot(
    cell_size_by_sector,
    ggplot2$aes(x = factor(sector_group, levels = SECTOR_LEVELS), y = share, fill = cell_size_bin)
  ) +
    ggplot2$geom_col(position = "stack") +
    ggplot2$labs(
      title = "Grouped Cell Size Distribution by Sector Group",
      x = "Sector group",
      y = "Share of active grouped cells",
      fill = "Firms in cell"
    ) +
    ggplot2$theme_minimal(base_size = 11)

  plot_positive_heatmap <- ggplot2$ggplot(
    loan_support_year_sector,
    ggplot2$aes(
      x = factor(year),
      y = factor(sector_group, levels = rev(SECTOR_LEVELS)),
      fill = share_positive_cells
    )
  ) +
    ggplot2$geom_tile(color = "white", linewidth = 0.2) +
    ggplot2$scale_fill_gradient(low = "#f7fbff", high = "#08519c", na.value = "grey85") +
    ggplot2$labs(
      title = "Share of Active Grouped Cells with Positive BNDES",
      x = "Year",
      y = "Sector group",
      fill = "Share positive"
    ) +
    ggplot2$theme_minimal(base_size = 11)

  plot_affiliation_heatmap <- ggplot2$ggplot(
    affiliation_support_sector_year,
    ggplot2$aes(
      x = factor(year),
      y = factor(sector_group, levels = rev(SECTOR_LEVELS)),
      fill = mean_share_affiliated_firms
    )
  ) +
    ggplot2$geom_tile(color = "white", linewidth = 0.2) +
    ggplot2$scale_fill_gradient(low = "#fff5eb", high = "#a63603", na.value = "grey85") +
    ggplot2$labs(
      title = "Mean Share of Affiliated Firms in Active Grouped Cells",
      x = "Year",
      y = "Sector group",
      fill = "Mean affiliation share"
    ) +
    ggplot2$theme_minimal(base_size = 11)

  boxplot_long <- melt(
    concentration_muni_year[, .(year, n_active_groups, n_positive_groups, hhi_s_cell)],
    id.vars = "year",
    variable.name = "metric",
    value.name = "value"
  )
  boxplot_long[, metric := factor(
    metric,
    levels = c("n_active_groups", "n_positive_groups", "hhi_s_cell"),
    labels = c("Active groups", "Positive groups", "HHI of s_cell")
  )]

  plot_boxplots <- ggplot2$ggplot(
    boxplot_long,
    ggplot2$aes(x = factor(year), y = value)
  ) +
    ggplot2$geom_boxplot(outlier.size = 0.3, na.rm = TRUE) +
    ggplot2$facet_wrap(~ metric, scales = "free_y", ncol = 1) +
    ggplot2$labs(
      title = "Muni-Year Support and Concentration Across Grouped Cells",
      x = "Year",
      y = NULL
    ) +
    ggplot2$theme_minimal(base_size = 11)

  plot_save(plot_cell_size_year, "plot_cell_size_by_year.pdf", width = 11, height = 6)
  plot_save(plot_cell_size_sector, "plot_cell_size_by_sector_group.pdf", width = 10, height = 6)
  plot_save(plot_positive_heatmap, "plot_positive_bndes_share_heatmap.pdf", width = 11, height = 6)
  plot_save(plot_affiliation_heatmap, "plot_affiliation_share_heatmap.pdf", width = 11, height = 6)
  plot_save(plot_boxplots, "plot_muni_year_support_boxplots.pdf", width = 11, height = 9)
  cat("\n")
} else {
  cat("Step 12: Skipping plots because ggplot2 is not installed.\n\n")
}

cat("Step 13: Writing markdown note...\n")
overall_small_share <- cell_size_overall[cell_size_bin %in% c("1", "2"), sum(share)]
overall_positive_cell_share <- mean(cell_panel$has_bndes_cell, na.rm = TRUE)
overall_zero_affiliation_share <- mean(cell_panel$share_affiliated_firms == 0, na.rm = TRUE)
median_n_firms <- median(cell_panel$n_firms, na.rm = TRUE)
median_active_groups <- median(loan_support_muni_year$n_active_groups, na.rm = TRUE)
median_positive_groups <- median(concentration_muni_year$n_positive_groups, na.rm = TRUE)
mean_positive_group_share <- mean(concentration_muni_year$share_positive_groups, na.rm = TRUE)
share_muni_year_zero_positive <- positive_group_count_share_overall[positive_group_bucket == "0", share]
if (!length(share_muni_year_zero_positive)) share_muni_year_zero_positive <- 0
share_muni_year_one_positive <- positive_group_count_share_overall[positive_group_bucket == "1", share]
if (!length(share_muni_year_one_positive)) share_muni_year_one_positive <- 0
median_hhi <- median(concentration_muni_year$hhi_s_cell, na.rm = TRUE)
median_top_share <- median(concentration_muni_year$top_sector_share, na.rm = TRUE)
mean_affiliation_share <- mean(cell_panel$share_affiliated_firms, na.rm = TRUE)
median_affiliation_share <- median(cell_panel$share_affiliated_firms, na.rm = TRUE)

strongest_positive_sector <- loan_support_year_sector[order(-share_positive_cells)][1]
strongest_affiliation_sector <- affiliation_support_by_sector[order(-mean_share_affiliated_firms)][1]
weakest_affiliation_sector <- affiliation_support_by_sector[order(mean_share_affiliated_firms)][1]

note_lines <- c(
  "# Sector-Group Cell Support Diagnostic",
  sprintf("Date: %s", Sys.Date()),
  sprintf("Panel source used: %s", panel_source),
  "",
  "## Main Findings",
  "",
  "### 1. How sparse are the sector_group x muni x year cells?",
  paste0(
    "- The diagnostic builds ", fmt_n(nrow(cell_panel)),
    " active grouped cells. The median cell contains ",
    fmt_num(median_n_firms, 0), " firms."
  ),
  paste0(
    "- Cells with only 1 or 2 firms account for ",
    fmt_pct(overall_small_share),
    " of all active grouped cells."
  ),
  paste0(
    "- The median muni-year has ", fmt_num(median_active_groups, 0),
    " active sector groups."
  ),
  "",
  "### 2. How often is there actual cross-group BNDES support within a muni-year?",
  paste0(
    "- Across active grouped cells, ", fmt_pct(overall_positive_cell_share),
    " have positive BNDES credit."
  ),
  paste0(
    "- The median muni-year has ", fmt_num(median_positive_groups, 0),
    " positive sector groups, and the mean share of active groups with positive BNDES is ",
    fmt_pct(mean_positive_group_share), "."
  ),
  paste0(
    "- ", fmt_pct(share_muni_year_zero_positive),
    " of muni-years have zero positive grouped cells, and ",
    fmt_pct(share_muni_year_one_positive),
    " have exactly one positive grouped cell."
  ),
  paste0(
    "- Among muni-years with positive total BNDES, the median HHI of grouped BNDES shares is ",
    fmt_num(median_hhi, 3),
    " and the median top-group share is ",
    fmt_pct(median_top_share), "."
  ),
  paste0(
    "- The highest year-sector positive-cell rate appears in ",
    strongest_positive_sector$sector_group[1], " (",
    strongest_positive_sector$sector_group_label[1], ") in ",
    strongest_positive_sector$year[1], ", at ",
    fmt_pct(strongest_positive_sector$share_positive_cells[1]), "."
  ),
  "",
  "### 3. How much political-affiliation support exists inside grouped cells once `No party` is treated as no affiliation?",
  paste0(
    "- The mean grouped-cell affiliation share is ",
    fmt_pct(mean_affiliation_share),
    " and the median is ", fmt_pct(median_affiliation_share), "."
  ),
  paste0(
    "- ", fmt_pct(overall_zero_affiliation_share),
    " of active grouped cells have zero affiliated firms after treating `No party` as no affiliation."
  ),
  paste0(
    "- The highest mean affiliation support is in ",
    strongest_affiliation_sector$sector_group[1], " (",
    strongest_affiliation_sector$sector_group_label[1], ") at ",
    fmt_pct(strongest_affiliation_sector$mean_share_affiliated_firms[1]),
    "; the lowest is in ",
    weakest_affiliation_sector$sector_group[1], " (",
    weakest_affiliation_sector$sector_group_label[1], ") at ",
    fmt_pct(weakest_affiliation_sector$mean_share_affiliated_firms[1]), "."
  ),
  "",
  "## Files",
  "",
  "- `sector_group_cell_panel.qs2` / `.csv`: main grouped cell panel",
  "- `1_*`: cell-size support tables",
  "- `2_*`: loan-support coverage tables",
  "- `3_*`: concentration tables",
  "- `4_*`: affiliation-support tables",
  "- `validation_checks.csv`: validation results",
  "",
  "## Interpretation",
  "",
  "These outputs isolate the support of the grouped sector panel itself. They show how much cell sparsity, limited positive-loan support, concentration of BNDES value, and low political-affiliation support remain after collapsing firms into the current `sector_group` cells."
)

save_text(note_lines, "sector_group_cell_support_note.md")
cat("\n")

rm(aff, aff_firm_year, mapping, section_map, muni_totals, firm_year_group_counts, mixed_affiliation)
invisible(gc())

failed_checks <- validation_dt[status == "FAIL", .N]
if (failed_checks > 0L) {
  stop("Completed with failed validation checks. See ", file.path(OUT_DIR, "validation_checks.csv"))
}

cat("Completed successfully.\n")
