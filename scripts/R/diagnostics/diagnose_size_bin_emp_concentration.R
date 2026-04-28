#!/usr/bin/env Rscript

# ==============================================================================
# Diagnostic: Size Bin × Employment Weighting Concentration
# ==============================================================================
# Investigates why size_bin + emp_weighted specs produce anomalously large
# F-statistics in script 52. Three hypotheses:
#
#   H1. Weight concentration: a few cells account for most of emp_pre weight,
#       so the regression is effectively fitting to a handful of observations.
#
#   H2. Sparse coverage: most municipalities lack firms in all 3 size bins,
#       so the effective cross-section is thin.
#
#   H3. Mechanical instrument homogeneity: within a size bin (firms of similar
#       size), the employment-weighted instrument has very low variance because
#       similar-sized firms have similar owner structures.
#
# Outputs:
#   output/diagnostics/size_bin_emp_concentration/
#     01_weight_concentration.csv       — Lorenz curve data for emp_pre by cell
#     02_muni_bin_coverage.csv          — % munis with all 3 bins populated
#     03_instrument_variance_by_group.csv — within-cell instrument SD by sector def
#     04_effective_n.csv                — effective N under emp_pre weighting
#     05_top_cells_profile.csv          — profile of top-weighted cells
#     summary_note.md                   — narrative summary
#
# Usage:
#   Rscript diagnose_size_bin_emp_concentration.R
# ==============================================================================

cat("==============================================================================\n")
cat("Diagnostic: Size Bin x Employment Weighting Concentration\n")
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
source(politicsregs_path("_utils", "load_firm_panel.R"))

setDTthreads(1L)

OUT_DIR <- make_output_path("diagnostics/size_bin_emp_concentration")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ==============================================================================
# Load Firm Panel + Size Bin Mapping
# ==============================================================================

cat("Step 1: Loading firm panel...\n")

# FA instrument columns requested by this diagnostic (cycle-specific coalition).
fa_inst_want <- c("FA_mayor_coal_pooled_count", "FA_gov_coal_pooled_count", "FA_pres_coal_pooled_count")
# Filter to what's actually available in the sparse file.
paths_sbc <- firm_panel_paths("cycle_specific")
avail_inst_sbc <- if (file.exists(paths_sbc$sparse) && requireNamespace("fst", quietly = TRUE)) {
  fst::metadata_fst(paths_sbc$sparse)$columnNames
} else character(0)
fa_inst_cols <- intersect(fa_inst_want, avail_inst_sbc)

dt <- load_firm_panel(
  baseline_type = "cycle_specific",
  columns       = c("firm_id", "muni_id", "year", "n_employees", "bl_n_employees", "has_bndes_fmt"),
  instruments   = if (length(fa_inst_cols)) fa_inst_cols else character(0),
  zero_fill     = TRUE,
  as_data_table = TRUE
)
cat(sprintf("  Loaded: %s rows\n", format(nrow(dt), big.mark = ",")))

# Join size_bin mapping
cat("Step 2: Joining size_bin mapping...\n")
sb_path <- make_output_path("size_bin_mapping.qs2")
if (!file.exists(sb_path)) stop("Size bin mapping not found. Run script 30c first.")
sb_map <- qs_read(sb_path)
setDT(sb_map)

# Map year -> election_cycle for joining
mayor_years <- c(2005L, 2009L, 2013L, 2017L)
gp_years <- c(2007L, 2011L, 2015L)
all_cycles <- sort(unique(c(mayor_years, gp_years)))

assign_cycle <- function(y) {
  # Each year maps to the most recent election cycle that treated it
  cycles_before <- all_cycles[all_cycles <= y]
  if (length(cycles_before)) max(cycles_before) else NA_integer_
}
dt[, election_cycle := vapply(year, assign_cycle, integer(1))]

dt <- merge(dt, sb_map[, .(firm_id, election_cycle, size_bin)],
            by = c("firm_id", "election_cycle"), all.x = TRUE)
dt <- dt[!is.na(size_bin)]
dt[, size_bin := as.character(size_bin)]
cat(sprintf("  After size_bin join: %s rows\n", format(nrow(dt), big.mark = ",")))

# Identify FA columns that are present
fa_cols <- intersect(
  c("FA_mayor_coal_pooled_count", "FA_gov_coal_pooled_count", "FA_pres_coal_pooled_count"),
  names(dt)
)
cat(sprintf("  FA columns found: %s\n", paste(fa_cols, collapse = ", ")))

# ==============================================================================
# Also load BNDES sector and custom sector for comparison
# ==============================================================================

cat("Step 3: Joining comparison sector classifications...\n")

# BNDES sector
bndes_sec_path <- make_output_path("bndes_sector_mapping.qs2")
if (file.exists(bndes_sec_path)) {
  bndes_map <- qs_read(bndes_sec_path)
  setDT(bndes_map)
  if ("bndes_sector" %in% names(bndes_map)) {
    dt <- merge(dt, bndes_map[, .(firm_id, bndes_sector)],
                by = "firm_id", all.x = TRUE, allow.cartesian = TRUE)
    dt[, bndes_sector := as.character(bndes_sector)]
    cat(sprintf("  BNDES sector joined: %s non-NA\n",
                format(sum(!is.na(dt$bndes_sector)), big.mark = ",")))
  }
}

# Custom sector (cnae_section-based grouping)
if ("cnae_section" %in% names(dt)) {
  dt[, custom_sector := cnae_section]
  cat("  Custom sector: using cnae_section\n")
} else {
  # Try to get from sector group mapping
  sg_path <- make_output_path("sector_group_mapping.qs2")
  if (file.exists(sg_path)) {
    sg_map <- qs_read(sg_path)
    setDT(sg_map)
    if (all(c("firm_id", "custom_sector") %in% names(sg_map))) {
      dt <- merge(dt, sg_map[, .(firm_id, custom_sector)],
                  by = "firm_id", all.x = TRUE)
      dt[, custom_sector := as.character(custom_sector)]
      cat(sprintf("  Custom sector joined: %s non-NA\n",
                  format(sum(!is.na(dt$custom_sector)), big.mark = ",")))
    }
  }
}

# ==============================================================================
# Collapse to cells: (muni_id, sector, year) for each sector definition
# ==============================================================================

cat("\nStep 4: Collapsing to cells...\n")

collapse_cells <- function(dt_in, sector_col, agg_type = c("equal_firm", "employment")) {
  agg_type <- match.arg(agg_type)
  by_cols <- c("muni_id", sector_col, "year")
  sub_dt <- dt_in[!is.na(get(sector_col))]

  sub_dt[, {
    out <- list(
      N_firms = .N,
      emp_pre = sum(bl_n_employees, na.rm = TRUE),
      Y_bndes_extensive = mean(has_bndes_fmt, na.rm = TRUE)
    )

    for (fa in fa_cols) {
      fa_bar <- sub("^FA_", "FA_bar_", fa)
      if (agg_type == "equal_firm") {
        out[[fa_bar]] <- mean(get(fa), na.rm = TRUE)
      } else {
        w <- bl_n_employees
        ok <- !is.na(get(fa)) & !is.na(w) & w > 0
        if (any(ok)) {
          out[[fa_bar]] <- sum(get(fa)[ok] * w[ok]) / sum(w[ok])
        } else {
          out[[fa_bar]] <- NA_real_
        }
      }
    }

    out
  }, by = by_cols]
}

sector_defs <- "size_bin"
if ("bndes_sector" %in% names(dt)) sector_defs <- c(sector_defs, "bndes_sector")
if ("custom_sector" %in% names(dt)) sector_defs <- c(sector_defs, "custom_sector")

cells <- list()
for (sv in sector_defs) {
  for (agg in c("equal_firm", "employment")) {
    key <- paste0(sv, "__", agg)
    cat(sprintf("  Collapsing: %s, agg=%s\n", sv, agg))
    cells[[key]] <- collapse_cells(dt, sv, agg)
    cells[[key]][, sector_var := sv]
    cells[[key]][, aggregation := agg]
    cat(sprintf("    -> %s cells\n", format(nrow(cells[[key]]), big.mark = ",")))
  }
}

# ==============================================================================
# Diagnostic 1: Weight Concentration (Lorenz Curve)
# ==============================================================================

cat("\nDiagnostic 1: Weight concentration (emp_pre)...\n")

lorenz_rows <- list()
for (key in names(cells)) {
  agg_dt <- cells[[key]]
  agg_dt <- agg_dt[emp_pre > 0 & !is.na(emp_pre)]
  if (!nrow(agg_dt)) next

  # Sort by emp_pre descending
  setorder(agg_dt, -emp_pre)
  total_emp <- sum(agg_dt$emp_pre)
  n_cells <- nrow(agg_dt)
  cum_share <- cumsum(agg_dt$emp_pre) / total_emp
  cell_rank_pct <- seq_len(n_cells) / n_cells * 100

  # Key percentiles
  for (pct in c(1, 5, 10, 25, 50)) {
    idx <- min(which(cell_rank_pct >= pct))
    lorenz_rows[[length(lorenz_rows) + 1L]] <- data.table(
      sector_var = agg_dt$sector_var[1],
      aggregation = agg_dt$aggregation[1],
      top_pct_cells = pct,
      emp_share_pct = round(cum_share[idx] * 100, 1),
      n_cells_in_top = idx,
      n_cells_total = n_cells,
      total_employment = total_emp
    )
  }
}
lorenz_dt <- rbindlist(lorenz_rows)
fwrite(lorenz_dt, file.path(OUT_DIR, "01_weight_concentration.csv"))
cat("  Saved: 01_weight_concentration.csv\n")
print(lorenz_dt[aggregation == "employment"])

# ==============================================================================
# Diagnostic 2: Municipality × Size Bin Coverage
# ==============================================================================

cat("\nDiagnostic 2: Municipality coverage by sector classification...\n")

coverage_rows <- list()
for (sv in sector_defs) {
  sub_dt <- dt[!is.na(get(sv))]
  muni_year_bins <- unique(sub_dt[, .(muni_id, year, sector = get(sv))])

  # How many unique sector values exist?
  n_sectors <- uniqueN(muni_year_bins$sector)

  # For each (muni, year), how many sectors are populated?
  bins_per_muni_year <- muni_year_bins[, .(n_bins = uniqueN(sector)), by = .(muni_id, year)]

  coverage_rows[[length(coverage_rows) + 1L]] <- data.table(
    sector_var = sv,
    n_sector_categories = n_sectors,
    n_muni_years = nrow(bins_per_muni_year),
    mean_bins_per_muni_year = round(mean(bins_per_muni_year$n_bins), 2),
    median_bins_per_muni_year = median(bins_per_muni_year$n_bins),
    pct_muni_year_all_bins = round(
      100 * mean(bins_per_muni_year$n_bins == n_sectors), 1
    ),
    pct_muni_year_1_bin = round(
      100 * mean(bins_per_muni_year$n_bins == 1L), 1
    ),
    # Specifically for size_bin: how many have all 3?
    pct_muni_year_ge2_bins = round(
      100 * mean(bins_per_muni_year$n_bins >= 2L), 1
    )
  )
}
coverage_dt <- rbindlist(coverage_rows)
fwrite(coverage_dt, file.path(OUT_DIR, "02_muni_bin_coverage.csv"))
cat("  Saved: 02_muni_bin_coverage.csv\n")
print(coverage_dt)

# ==============================================================================
# Diagnostic 3: Within-Cell Instrument Variance
# ==============================================================================

cat("\nDiagnostic 3: Within-cell instrument variance...\n")

# For each (sector_var, aggregation), compute the SD of FA_bar across cells
# within each (muni, year) — this is the variation the regression exploits
variance_rows <- list()
for (key in names(cells)) {
  agg_dt <- cells[[key]]
  sv <- agg_dt$sector_var[1]
  agg <- agg_dt$aggregation[1]

  for (fa in fa_cols) {
    fa_bar <- sub("^FA_", "FA_bar_", fa)
    if (!fa_bar %in% names(agg_dt)) next

    # Within muni-year SD of the instrument across sectors
    within_sd <- agg_dt[!is.na(get(fa_bar)), .(
      sd_fa = sd(get(fa_bar), na.rm = TRUE),
      n_sectors = .N
    ), by = .(muni_id, year)]
    within_sd <- within_sd[n_sectors >= 2]

    # Also compute overall SD for reference
    overall_sd <- sd(agg_dt[[fa_bar]], na.rm = TRUE)

    variance_rows[[length(variance_rows) + 1L]] <- data.table(
      sector_var = sv,
      aggregation = agg,
      instrument = fa_bar,
      overall_sd = round(overall_sd, 6),
      mean_within_muni_year_sd = round(mean(within_sd$sd_fa, na.rm = TRUE), 6),
      median_within_muni_year_sd = round(median(within_sd$sd_fa, na.rm = TRUE), 6),
      pct_zero_within_sd = round(100 * mean(within_sd$sd_fa < 1e-10, na.rm = TRUE), 1),
      n_muni_years_with_variation = nrow(within_sd)
    )
  }
}
variance_dt <- rbindlist(variance_rows)
fwrite(variance_dt, file.path(OUT_DIR, "03_instrument_variance_by_group.csv"))
cat("  Saved: 03_instrument_variance_by_group.csv\n")
print(variance_dt)

# ==============================================================================
# Diagnostic 4: Effective N under Employment Weighting
# ==============================================================================

cat("\nDiagnostic 4: Effective N...\n")

# Kish's effective sample size: N_eff = (sum(w))^2 / sum(w^2)
eff_n_rows <- list()
for (key in names(cells)) {
  agg_dt <- cells[[key]]
  sv <- agg_dt$sector_var[1]
  agg <- agg_dt$aggregation[1]

  w <- agg_dt[emp_pre > 0 & !is.na(emp_pre), emp_pre]
  n_raw <- length(w)
  if (n_raw == 0) next

  n_eff <- (sum(w))^2 / sum(w^2)
  # Also compute within year
  eff_by_year <- agg_dt[emp_pre > 0 & !is.na(emp_pre), {
    ww <- emp_pre
    list(
      n_raw = .N,
      n_eff = (sum(ww))^2 / sum(ww^2),
      max_w = max(ww),
      total_w = sum(ww)
    )
  }, by = year]

  eff_n_rows[[length(eff_n_rows) + 1L]] <- data.table(
    sector_var = sv,
    aggregation = agg,
    n_raw = n_raw,
    n_eff = round(n_eff, 0),
    eff_ratio = round(n_eff / n_raw, 3),
    mean_yearly_eff_ratio = round(mean(eff_by_year$n_eff / eff_by_year$n_raw), 3),
    min_yearly_eff_ratio = round(min(eff_by_year$n_eff / eff_by_year$n_raw), 3)
  )
}
eff_n_dt <- rbindlist(eff_n_rows)
fwrite(eff_n_dt, file.path(OUT_DIR, "04_effective_n.csv"))
cat("  Saved: 04_effective_n.csv\n")
print(eff_n_dt)

# ==============================================================================
# Diagnostic 5: Profile of Top-Weighted Cells
# ==============================================================================

cat("\nDiagnostic 5: Top-weighted cells profile...\n")

# Focus on size_bin + employment aggregation
sb_emp_key <- "size_bin__employment"
if (sb_emp_key %in% names(cells)) {
  agg_dt <- copy(cells[[sb_emp_key]])
  agg_dt <- agg_dt[emp_pre > 0 & !is.na(emp_pre)]
  total_emp <- sum(agg_dt$emp_pre)
  setorder(agg_dt, -emp_pre)
  agg_dt[, cum_emp_share := cumsum(emp_pre) / total_emp]
  agg_dt[, rank := .I]

  # Top 50 cells
  top50 <- agg_dt[rank <= 50, .(
    rank, muni_id, size_bin, year, N_firms, emp_pre,
    emp_share_pct = round(emp_pre / total_emp * 100, 2),
    cum_emp_share_pct = round(cum_emp_share * 100, 1),
    Y_bndes_extensive = round(Y_bndes_extensive, 4)
  )]

  # Add FA_bar values if available
  for (fa in fa_cols) {
    fa_bar <- sub("^FA_", "FA_bar_", fa)
    if (fa_bar %in% names(agg_dt)) {
      top50[, (fa_bar) := round(agg_dt[rank <= 50][[fa_bar]], 4)]
    }
  }

  fwrite(top50, file.path(OUT_DIR, "05_top_cells_profile.csv"))
  cat("  Saved: 05_top_cells_profile.csv\n")
  cat(sprintf("  Top 10 cells account for %.1f%% of total employment weight\n",
              agg_dt[rank <= 10, max(cum_emp_share)] * 100))
  cat(sprintf("  Top 50 cells account for %.1f%% of total employment weight\n",
              agg_dt[rank <= 50, max(cum_emp_share)] * 100))
}

# ==============================================================================
# Diagnostic 6: Compare F-stats from manifests (if available)
# ==============================================================================

cat("\nDiagnostic 6: Comparing manifest F-stats across sector defs...\n")

fstat_comparison <- list()
for (sv in c("size_bin", "bndes_sector", "custom_sector")) {
  table_dir_name <- switch(sv,
    size_bin = "agg_firm_size_bin",
    bndes_sector = "agg_firm_bndes_sector",
    custom_sector = "agg_firm_grouped"
  )
  manifest_path <- file.path(
    tables_path(table_dir_name),
    "agg_firm_run_manifest.qs2"
  )
  if (!file.exists(manifest_path)) {
    manifest_csv <- file.path(tables_path(table_dir_name), "agg_firm_run_manifest.csv")
    if (file.exists(manifest_csv)) {
      mf <- fread(manifest_csv)
    } else {
      cat(sprintf("  Manifest not found for %s — skipping\n", sv))
      next
    }
  } else {
    mf <- qs_read(manifest_path)
    setDT(mf)
  }

  if ("max_f_stat" %in% names(mf)) {
    fstat_comparison[[sv]] <- mf[, .(
      sector_var = sv,
      canonical_slug,
      outcome,
      aggregation,
      regression_weight,
      fe,
      exposure_control,
      max_f_stat,
      status
    )]
  }
}

if (length(fstat_comparison)) {
  fstat_all <- rbindlist(fstat_comparison, fill = TRUE)
  fwrite(fstat_all, file.path(OUT_DIR, "06_fstat_manifest_comparison.csv"))
  cat("  Saved: 06_fstat_manifest_comparison.csv\n")

  # Flag suspicious F-stats
  suspicious <- fstat_all[max_f_stat > 1000 & !is.na(max_f_stat)]
  if (nrow(suspicious)) {
    cat(sprintf("\n  WARNING: %d specs with F > 1000 (likely numerical artefacts):\n", nrow(suspicious)))
    print(suspicious[, .(sector_var, canonical_slug, max_f_stat)])
  }
}

# ==============================================================================
# Summary Note
# ==============================================================================

cat("\nWriting summary note...\n")

note_lines <- c(
  "# Diagnostic: Size Bin x Employment Weighting Concentration",
  sprintf("Date: %s", Sys.Date()),
  "",
  "## Key Question",
  "Why does `size_bin + emp_weighted` produce anomalously large F-stats",
  "compared to other sector classifications?",
  "",
  "## Files Produced",
  "- `01_weight_concentration.csv` — Lorenz curve: what % of emp_pre is in top X% of cells?",
  "- `02_muni_bin_coverage.csv` — What % of muni-years have all 3 size bins populated?",
  "- `03_instrument_variance_by_group.csv` — Within-cell instrument SD comparison",
  "- `04_effective_n.csv` — Kish's effective N under employment weighting",
  "- `05_top_cells_profile.csv` — Profile of the 50 most heavily weighted cells",
  "- `06_fstat_manifest_comparison.csv` — F-stats from run manifests (if available)",
  "",
  "## What to Look For",
  "",
  "### H1: Weight concentration",
  "If `01_weight_concentration.csv` shows that the top 5% of cells hold >50% of weight,",
  "the regression is driven by a handful of observations. Compare `eff_ratio` in",
  "`04_effective_n.csv`: if N_eff / N_raw << 1 for size_bin but not for other",

  "classifications, weight concentration is the culprit.",
  "",
  "### H2: Sparse coverage",
  "If `02_muni_bin_coverage.csv` shows a large share of muni-years with only 1 size bin,",
  "those cells contribute zero within-muni-year variation. The instrument variation",
  "comes from a small subset of municipalities that happen to have all 3 bins.",
  "",
  "### H3: Instrument homogeneity",
  "If `03_instrument_variance_by_group.csv` shows lower within-muni-year SD for",
  "size_bin + employment than for other classifications, the employment-weighted",
  "instrument is mechanically smooth within size bins — firms of similar size",
  "receiving similar alignment values when weighted by employment."
)

writeLines(note_lines, file.path(OUT_DIR, "summary_note.md"))
cat("  Saved: summary_note.md\n")

cat("\n==============================================================================\n")
cat("Diagnostic complete. Results in:\n")
cat(sprintf("  %s\n", OUT_DIR))
cat("==============================================================================\n")
