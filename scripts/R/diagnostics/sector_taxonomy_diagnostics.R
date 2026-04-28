#!/usr/bin/env Rscript

# ==============================================================================
# Sector Taxonomy Diagnostics (Unit 7)
# ==============================================================================
#
# Implements the D1–D9 diagnostic battery from the plan
# (2026-04-14-001-feat-muni-emp-weighting-interactions-sector-size-bins-plan.md,
# Section E) for four sector taxonomies:
#
#   1. cnae_section          — 21 CNAE letters
#   2. custom_sector         — 11 sector groups (script 30)
#   3. cnae_size_bin         — CNAE × firm-size tercile (script 30d)
#   4. sector_group_size_bin — sector group × firm-size tercile (script 30d)
#
# Diagnostics implemented:
#   D1  — Observation and cell counts; median/min firms per cell
#   D2  — Within-muni-year variance of sector share proxy (simplified)
#   D3  — First-stage relevance: max F-stat across existing .tex tables
#   D4  — Stability: cosine similarity of F-stat vectors across taxonomies
#   D5  — Tercile vs quartile robustness [DEFERRED — flags only]
#   D6  — Thin-cell audit: share of (sector, muni, year) cells with < 3 firms
#   D7  — Muni-level aggregation fidelity: correlation of sector-share vectors
#   D8  — Economic interpretability narrative [written to .md report]
#   D9  — Lead-alignment placebo [DEFERRED — requires re-running 52]
#
# Outputs:
#   paper/tables/agg_firm_size_bin/sector_taxonomy_diagnostics.tex
#   quality_reports/sector_taxonomy_diagnostic_report.md
#
# Usage:
#   Rscript scripts/R/diagnostics/sector_taxonomy_diagnostics.R
#
# Dependencies: scripts 30, 30c, 30d (optional), 42, existing 52 .tex tables
# ==============================================================================

cat("==============================================================================\n")
cat("Sector Taxonomy Diagnostics (D1-D9 Battery)\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})

setDTthreads(0)

# --- Bootstrap ----------------------------------------------------------------

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

  stop("Cannot determine bootstrap path.")
})
source(normalizePath(bootstrap_file, winslash = "/", mustWork = TRUE))
bootstrap_politicsregs()
source(politicsregs_path("_utils", "load_firm_panel.R"))

# --- Configuration ------------------------------------------------------------

TABLES_ROOT <- file.path("paper", "tables")
TEX_OUT     <- file.path(TABLES_ROOT, "agg_firm_size_bin", "sector_taxonomy_diagnostics.tex")
MD_OUT      <- file.path("quality_reports", "sector_taxonomy_diagnostic_report.md")

# Mayor-election cycles (primary grouping for cell counts, matching 30c)
MAYOR_CYCLES <- c(2005L, 2009L, 2013L, 2017L)
YEAR_TO_CYCLE <- data.table(
  year = 2002L:2017L,
  election_cycle = c(rep(2005L, 4L), rep(2005L, 1L),
                     rep(2009L, 4L), rep(2013L, 4L), rep(2017L, 4L))
)

# Table directories per sector_var (matching 52's get_table_dir_suffix())
TABLE_DIR <- list(
  cnae_section          = file.path(TABLES_ROOT, "agg_firm"),
  custom_sector         = file.path(TABLES_ROOT, "agg_firm_grouped"),
  cnae_size_bin         = file.path(TABLES_ROOT, "agg_firm_cnae_size_bin"),
  sector_group_size_bin = file.path(TABLES_ROOT, "agg_firm_sector_group_size_bin")
)

TAXONOMY_LABELS <- c(
  cnae_section          = "CNAE section",
  custom_sector         = "Sector group",
  cnae_size_bin         = "CNAE $\\times$ size-T",
  sector_group_size_bin = "Group $\\times$ size-T"
)

THIN_CELL_THRESHOLD <- 3L   # < 3 firms = thin cell
THIN_CELL_RATE_WARN <- 0.10 # warn if thin-cell rate exceeds 10%
D7_CORR_PASS        <- 0.80

# F-stat parsing thresholds (matching 52b)
F_SUSPICIOUS <- 10000
F_PASS       <- 10

# --- Helpers ------------------------------------------------------------------

safe_try <- function(expr, default = NA_real_) {
  tryCatch(expr, error = function(e) default)
}

pct_fmt <- function(x) {
  if (is.na(x)) return("---")
  sprintf("%.1f\\%%", x * 100)
}

num_fmt <- function(x, big.mark = TRUE) {
  if (is.na(x)) return("---")
  if (big.mark) format(round(x), big.mark = ",", scientific = FALSE)
  else sprintf("%.2f", x)
}

f_fmt <- function(x) {
  if (is.na(x)) return("---")
  sprintf("%.1f", x)
}

# --- D3: Parse F-stats from existing .tex files (same logic as 52b) -----------

parse_fstats_from_dir <- function(table_dir) {
  if (!dir.exists(table_dir)) return(NULL)
  tex_files <- list.files(table_dir, pattern = "\\.tex$", full.names = TRUE)
  tex_files <- tex_files[!grepl("diagnostics", tex_files)]
  if (!length(tex_files)) return(NULL)

  all_fstats <- numeric(0)
  for (f in tex_files) {
    lines <- tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
    fline <- grep("F\\$-statistic", lines, value = TRUE)
    if (!length(fline)) next
    fline <- fline[1]
    fline <- gsub("\\\\textbf\\{([^}]+)\\}", "\\1", fline)
    fline <- gsub("\\$[^$]*\\$", "", fline)
    fline <- gsub("\\\\\\\\", "", fline)
    parts <- strsplit(fline, "&")[[1]]
    vals <- parts[-1]
    vals <- gsub("[^0-9.eE+-]", "", vals)
    vals <- suppressWarnings(as.numeric(vals))
    vals <- vals[!is.na(vals) & is.finite(vals) & vals < F_SUSPICIOUS]
    all_fstats <- c(all_fstats, vals)
  }
  all_fstats
}

# --- Load firm panel (minimal columns) ----------------------------------------

cat("Loading firm panel...\n")

# No instrument columns needed — load base only.
dt_firm <- tryCatch(
  load_firm_panel(
    baseline_type = "cycle_specific",
    columns       = c("firm_id", "muni_id", "year", "cnae_section", "bl_n_employees", "has_bndes_fmt"),
    instruments   = character(0),
    zero_fill     = FALSE,
    as_data_table = TRUE
  ),
  error = function(e) {
    cat("  WARNING: firm panel not found. D1/D2/D6/D7 will be NA.\n")
    NULL
  }
)
if (!is.null(dt_firm)) {
  cat(sprintf("  Loaded: %s rows\n", format(nrow(dt_firm), big.mark = ",")))
}

if (!is.null(dt_firm)) {
  dt_firm[, `:=`(
    firm_id      = as.integer(firm_id),
    muni_id      = as.integer(muni_id),
    year         = as.integer(year),
    cnae_section = as.character(cnae_section)
  )]
  if ("bl_n_employees" %in% names(dt_firm)) {
    dt_firm[, bl_n_employees := as.numeric(bl_n_employees)]
  }
  # Attach mayor election cycle
  dt_firm[YEAR_TO_CYCLE, election_cycle := i.election_cycle, on = "year"]
}

# --- Load sector group mapping ------------------------------------------------

cat("Loading sector group mapping...\n")

sg_map <- NULL
sg_path <- make_output_path("sector_group_mapping.qs2")
if (file.exists(sg_path)) {
  sg_map <- qs_read(sg_path)
  setDT(sg_map)
  sg_map[, `:=`(cnae_section = as.character(cnae_section), sector_group = as.character(sector_group))]
  cat(sprintf("  Loaded sector_group_mapping: %d rows\n", nrow(sg_map)))
} else {
  cat("  WARNING: sector_group_mapping.qs2 not found. custom_sector D1/D2/D6 will be NA.\n")
}

# --- Load sector × size-bin crosswalks (Unit 6) --------------------------------

cat("Loading sector × size-bin crosswalks (Unit 6)...\n")

cnae_sb_map  <- NULL
group_sb_map <- NULL

cnae_sb_path  <- make_output_path("sector_size_bin_cnae_mapping.qs2")
group_sb_path <- make_output_path("sector_size_bin_group_mapping.qs2")

if (file.exists(cnae_sb_path)) {
  cnae_sb_map <- qs_read(cnae_sb_path)
  setDT(cnae_sb_map)
  cnae_sb_map[, `:=`(firm_id = as.integer(firm_id), election_cycle = as.integer(election_cycle))]
  cat(sprintf("  Loaded cnae_size_bin mapping: %d rows\n", nrow(cnae_sb_map)))
} else {
  cat("  NOTE: sector_size_bin_cnae_mapping.qs2 not found (run 30d). cnae_size_bin diagnostics will be NA.\n")
}

if (file.exists(group_sb_path)) {
  group_sb_map <- qs_read(group_sb_path)
  setDT(group_sb_map)
  group_sb_map[, `:=`(firm_id = as.integer(firm_id), election_cycle = as.integer(election_cycle))]
  cat(sprintf("  Loaded sector_group_size_bin mapping: %d rows\n", nrow(group_sb_map)))
} else {
  cat("  NOTE: sector_size_bin_group_mapping.qs2 not found (run 30d). sector_group_size_bin diagnostics will be NA.\n")
}

# --- Build per-taxonomy firm-level crosswalk -----------------------------------
# Returns a data.table with (firm_id, election_cycle, muni_id, year, sector_col, bl_n_employees)
# or NULL if the required inputs are unavailable.

build_taxonomy_dt <- function(sector_var) {
  if (is.null(dt_firm)) return(NULL)

  if (sector_var == "cnae_section") {
    dt <- copy(dt_firm)
    dt[, sector_col := cnae_section]
    return(dt)
  }

  if (sector_var == "custom_sector") {
    if (is.null(sg_map)) return(NULL)
    dt <- copy(dt_firm)
    dt[sg_map, sector_col := i.sector_group, on = "cnae_section"]
    return(dt)
  }

  if (sector_var == "cnae_size_bin") {
    if (is.null(cnae_sb_map)) return(NULL)
    dt <- copy(dt_firm)
    dt[cnae_sb_map, sector_col := i.cnae_size_bin, on = c("firm_id", "election_cycle")]
    return(dt)
  }

  if (sector_var == "sector_group_size_bin") {
    if (is.null(group_sb_map)) return(NULL)
    dt <- copy(dt_firm)
    dt[group_sb_map, sector_col := i.sector_group_size_bin, on = c("firm_id", "election_cycle")]
    return(dt)
  }

  NULL
}

# ==============================================================================
# Compute diagnostics per taxonomy
# ==============================================================================

cat("\nComputing diagnostics...\n")

results <- list()

for (sv in names(TAXONOMY_LABELS)) {
  cat(sprintf("\n  [%s]\n", sv))

  dt_sv <- build_taxonomy_dt(sv)

  # ---------- D1: cell counts --------------------------------------------------

  d1_n_obs      <- NA_integer_
  d1_n_cells    <- NA_integer_
  d1_med_firms  <- NA_real_
  d1_p10_firms  <- NA_real_
  d1_n_munis    <- NA_integer_
  d1_coverage   <- NA_real_   # share of (muni, year) cells with ≥1 sector

  if (!is.null(dt_sv)) {
    d1_n_obs <- nrow(dt_sv)

    # (sector, muni, year) cells
    cells <- dt_sv[!is.na(sector_col), .(
      n_firms = uniqueN(firm_id)
    ), by = .(sector_col, muni_id, year)]

    d1_n_cells   <- nrow(cells)
    d1_med_firms <- safe_try(median(cells$n_firms, na.rm = TRUE))
    d1_p10_firms <- safe_try(as.numeric(quantile(cells$n_firms, 0.10, na.rm = TRUE)))

    d1_n_munis <- uniqueN(dt_sv$muni_id)

    # Muni-year coverage: fraction of (muni, year) cells with at least one firm in some sector
    muni_year_total <- uniqueN(dt_sv[, .(muni_id, year)])
    muni_year_covered <- uniqueN(cells[, .(muni_id, year)])
    d1_coverage <- if (muni_year_total > 0) muni_year_covered / muni_year_total else NA_real_

    cat(sprintf("    D1: %s obs | %s cells | median %g firms/cell | p10 %g\n",
                format(d1_n_obs, big.mark = ","),
                format(d1_n_cells, big.mark = ","),
                d1_med_firms, d1_p10_firms))
  } else {
    cat("    D1: skipped (missing inputs)\n")
  }

  # ---------- D2: within-muni-year variance of sector share proxy --------------

  d2_var_smjt <- NA_real_

  if (!is.null(dt_sv) && "bl_n_employees" %in% names(dt_sv)) {
    # Compute sector employment share within (muni_id, year):
    #   s_{jmt} proxy = bl_n_employees of sector j / total bl_n_employees in muni-year
    emp_by_sector <- dt_sv[!is.na(sector_col) & !is.na(bl_n_employees) & bl_n_employees > 0,
                            .(sector_emp = sum(bl_n_employees, na.rm = TRUE)),
                            by = .(sector_col, muni_id, year)]
    muni_year_total_emp <- emp_by_sector[, .(muni_total = sum(sector_emp, na.rm = TRUE)),
                                          by = .(muni_id, year)]
    emp_by_sector[muni_year_total_emp, muni_total := i.muni_total, on = .(muni_id, year)]
    emp_by_sector[, s_jmt := sector_emp / muni_total]

    d2_var_smjt <- safe_try(emp_by_sector[muni_total > 0, var(s_jmt, na.rm = TRUE)])
    cat(sprintf("    D2: var(s_jmt proxy) = %.5f\n", d2_var_smjt))
  } else {
    cat("    D2: skipped (missing bl_n_employees)\n")
  }

  # ---------- D3: first-stage F-stat from existing .tex tables -----------------

  d3_max_f    <- NA_real_
  d3_n_tables <- 0L

  fstats_vec <- parse_fstats_from_dir(TABLE_DIR[[sv]])
  if (!is.null(fstats_vec) && length(fstats_vec) > 0) {
    d3_n_tables <- as.integer(length(fstats_vec))
    d3_max_f    <- max(fstats_vec, na.rm = TRUE)
    cat(sprintf("    D3: max F = %.1f (%d F-stats parsed)\n", d3_max_f, d3_n_tables))
  } else {
    cat("    D3: no tables found (run script 52 first)\n")
  }

  # ---------- D6: thin-cell audit ----------------------------------------------

  d6_thin_rate  <- NA_real_  # share of (sector, muni, year) cells with < 3 firms
  d6_agg_loss   <- NA_real_  # deferred (needs credit data at cell level)

  if (!is.null(dt_sv)) {
    cells_d6 <- dt_sv[!is.na(sector_col), .(n_firms = uniqueN(firm_id)),
                      by = .(sector_col, muni_id, year)]
    n_total <- nrow(cells_d6)
    n_thin  <- sum(cells_d6$n_firms < THIN_CELL_THRESHOLD, na.rm = TRUE)
    d6_thin_rate <- if (n_total > 0) n_thin / n_total else NA_real_
    flag <- if (!is.na(d6_thin_rate) && d6_thin_rate > THIN_CELL_RATE_WARN) " [FLAGGED]" else ""
    cat(sprintf("    D6: thin-cell rate = %.1f%%%s\n", d6_thin_rate * 100, flag))
  } else {
    cat("    D6: skipped (missing inputs)\n")
  }

  # ---------- D7: muni-level aggregation fidelity (simplified) -----------------
  # Simplified: correlation between (muni, year) total sector-employment share
  # vectors across taxonomies. We store the per-muni-year entropy of sector shares
  # as a scalar summary and compare later.

  d7_entropy <- NA_real_   # mean Shannon entropy of sector shares within (muni, year)

  if (!is.null(dt_sv) && "bl_n_employees" %in% names(dt_sv)) {
    emp_by_s <- dt_sv[!is.na(sector_col) & !is.na(bl_n_employees) & bl_n_employees > 0,
                      .(sector_emp = sum(bl_n_employees, na.rm = TRUE)),
                      by = .(sector_col, muni_id, year)]
    muni_yr_tot <- emp_by_s[, .(muni_total = sum(sector_emp)), by = .(muni_id, year)]
    emp_by_s[muni_yr_tot, muni_total := i.muni_total, on = .(muni_id, year)]
    emp_by_s[, p := sector_emp / muni_total]
    # Shannon entropy per (muni, year): H = -sum(p * log(p))
    entropy_dt <- emp_by_s[p > 0, .(H = -sum(p * log(p), na.rm = TRUE)), by = .(muni_id, year)]
    d7_entropy <- mean(entropy_dt$H, na.rm = TRUE)
    cat(sprintf("    D7: mean entropy = %.3f (higher = more dispersed across sectors)\n", d7_entropy))
  } else {
    cat("    D7: skipped\n")
  }

  # ---------- Store results ----------------------------------------------------

  results[[sv]] <- data.table(
    sector_var    = sv,
    label         = TAXONOMY_LABELS[[sv]],
    d1_n_obs      = d1_n_obs,
    d1_n_cells    = d1_n_cells,
    d1_med_firms  = d1_med_firms,
    d1_p10_firms  = d1_p10_firms,
    d1_n_munis    = d1_n_munis,
    d2_var_smjt   = d2_var_smjt,
    d3_max_f      = d3_max_f,
    d3_n_tables   = d3_n_tables,
    d6_thin_rate  = d6_thin_rate,
    d7_entropy    = d7_entropy
  )
}

res_dt <- rbindlist(results, fill = TRUE)

# ---------- D4: cross-taxonomy cosine similarity of F-stat vectors -----------

cat("\nD4: Cross-taxonomy F-stat cosine similarity...\n")

fstat_vecs <- lapply(names(TAXONOMY_LABELS), function(sv) {
  fstats_vec <- parse_fstats_from_dir(TABLE_DIR[[sv]])
  if (!is.null(fstats_vec) && length(fstats_vec) >= 2) fstats_vec else NULL
})
names(fstat_vecs) <- names(TAXONOMY_LABELS)

cosine_sim <- function(x, y) {
  common_len <- min(length(x), length(y))
  if (common_len < 2) return(NA_real_)
  x <- head(x, common_len)
  y <- head(y, common_len)
  if (sd(x, na.rm = TRUE) == 0 || sd(y, na.rm = TRUE) == 0) return(NA_real_)
  sum(x * y, na.rm = TRUE) / (sqrt(sum(x^2, na.rm = TRUE)) * sqrt(sum(y^2, na.rm = TRUE)))
}

# Compare each pair against cnae_section (baseline)
baseline_vec <- fstat_vecs[["cnae_section"]]
d4_sims <- vapply(names(TAXONOMY_LABELS), function(sv) {
  if (sv == "cnae_section") return(1.0)
  cosine_sim(baseline_vec, fstat_vecs[[sv]])
}, numeric(1))

res_dt[, d4_cosine_vs_baseline := d4_sims[sector_var]]
cat(sprintf("  cnae_section vs custom_sector:         %.3f\n",
            d4_sims[["custom_sector"]]))
cat(sprintf("  cnae_section vs cnae_size_bin:          %.3f\n",
            d4_sims[["cnae_size_bin"]]))
cat(sprintf("  cnae_section vs sector_group_size_bin:  %.3f\n",
            d4_sims[["sector_group_size_bin"]]))

# ---------- D7 cross-taxonomy correlation of entropy -------------------------

cat("\nD7 (muni-level fidelity): cross-taxonomy entropy correlation...\n")

entropy_vals <- res_dt$d7_entropy
names(entropy_vals) <- res_dt$sector_var

if (!all(is.na(entropy_vals))) {
  base_e <- entropy_vals[["cnae_section"]]
  for (sv in names(TAXONOMY_LABELS)) {
    e <- entropy_vals[[sv]]
    if (!is.na(base_e) && !is.na(e)) {
      cat(sprintf("  %s: entropy = %.3f (baseline = %.3f)\n", sv, e, base_e))
    }
  }
}

# ==============================================================================
# Emit LaTeX table
# ==============================================================================

cat("\nWriting LaTeX table...\n")

dir.create(dirname(TEX_OUT), showWarnings = FALSE, recursive = TRUE)

tex_lines <- character(0)
add_tex <- function(...) tex_lines <<- c(tex_lines, paste0(...))

add_tex("% Sector Taxonomy Diagnostics Table")
add_tex("% Generated by scripts/R/diagnostics/sector_taxonomy_diagnostics.R")
add_tex("% Date: ", format(Sys.Date(), "%Y-%m-%d"))
add_tex("% Do NOT edit manually — re-run the diagnostics script.")
add_tex("")
add_tex("\\begin{tabular}{lrrrrrrr}")
add_tex("\\toprule")
add_tex("  & \\multicolumn{4}{c}{D1: Cell structure} & D3 & D6 & D7 \\\\")
add_tex("\\cmidrule(lr){2-5}")
add_tex(paste0(
  "  Taxonomy",
  " & Obs",
  " & Cells",
  " & Med.~$n_f$",
  " & P10~$n_f$",
  " & Max~$F$",
  " & Thin\\%",
  " & Entropy",
  " \\\\"
))
add_tex("\\midrule")

for (i in seq_len(nrow(res_dt))) {
  r <- res_dt[i]

  label      <- r$label
  obs_str    <- num_fmt(r$d1_n_obs)
  cells_str  <- num_fmt(r$d1_n_cells)
  med_str    <- if (is.na(r$d1_med_firms)) "---" else sprintf("%.0f", r$d1_med_firms)
  p10_str    <- if (is.na(r$d1_p10_firms)) "---" else sprintf("%.0f", r$d1_p10_firms)
  f_str      <- f_fmt(r$d3_max_f)
  thin_str   <- pct_fmt(r$d6_thin_rate)
  ent_str    <- if (is.na(r$d7_entropy)) "---" else sprintf("%.3f", r$d7_entropy)

  # Flag thin-cell violations
  thin_flag <- if (!is.na(r$d6_thin_rate) && r$d6_thin_rate > THIN_CELL_RATE_WARN) {
    paste0(thin_str, "$^{\\dagger}$")
  } else {
    thin_str
  }

  # Flag F-pass
  f_display <- if (!is.na(r$d3_max_f) && r$d3_max_f >= F_PASS) {
    sprintf("\\textbf{%s}", f_str)
  } else {
    f_str
  }

  add_tex(sprintf("  %s & %s & %s & %s & %s & %s & %s & %s \\\\",
                  label, obs_str, cells_str, med_str, p10_str,
                  f_display, thin_flag, ent_str))
}

add_tex("\\bottomrule")
add_tex("\\end{tabular}")

writeLines(tex_lines, TEX_OUT)
cat(sprintf("  Wrote %d lines to %s\n", length(tex_lines), TEX_OUT))

# ==============================================================================
# Emit Markdown report
# ==============================================================================

cat("Writing Markdown report...\n")

run_date <- format(Sys.Date(), "%Y-%m-%d")

# D7: compute cross-taxonomy sector-share correlations at muni level
# (simplified: correlate the entropy scalars — full correlation requires storing
#  the full (muni, year, sector) expanded table for all four taxonomies)
entropy_avail <- res_dt[!is.na(d7_entropy), .(sector_var, d7_entropy)]

report_lines <- c(
  sprintf("# Sector Taxonomy Diagnostic Report"),
  sprintf("Generated: %s", run_date),
  sprintf("Script: `scripts/R/diagnostics/sector_taxonomy_diagnostics.R`"),
  "",
  "---",
  "",
  "## Summary",
  "",
  "This report evaluates four sector taxonomies against the criteria in Section E of",
  "the plan `2026-04-14-001-feat-muni-emp-weighting-interactions-sector-size-bins-plan.md`.",
  "",
  "### Taxonomies evaluated",
  "",
  "| Code | Label | Key |",
  "|------|-------|-----|",
  "| `cnae_section` | 21 CNAE letters | In firm panel |",
  "| `custom_sector` | 11 sector groups | `sector_group_mapping.qs2` |",
  "| `cnae_size_bin` | CNAE × size-tercile | `sector_size_bin_cnae_mapping.qs2` |",
  "| `sector_group_size_bin` | Group × size-tercile | `sector_size_bin_group_mapping.qs2` |",
  "",
  "---",
  "",
  "## Diagnostic Results",
  "",
  "### D1 — Cell Structure",
  "",
  "| Taxonomy | Obs | Cells (muni×sector×year) | Median firms/cell | P10 firms/cell | N munis |",
  "|----------|-----|--------------------------|-------------------|----------------|---------|"
)

for (i in seq_len(nrow(res_dt))) {
  r <- res_dt[i]
  report_lines <- c(report_lines,
    sprintf("| %s | %s | %s | %s | %s | %s |",
            r$label,
            if (is.na(r$d1_n_obs)) "---" else format(r$d1_n_obs, big.mark = ","),
            if (is.na(r$d1_n_cells)) "---" else format(r$d1_n_cells, big.mark = ","),
            if (is.na(r$d1_med_firms)) "---" else round(r$d1_med_firms),
            if (is.na(r$d1_p10_firms)) "---" else round(r$d1_p10_firms),
            if (is.na(r$d1_n_munis)) "---" else format(r$d1_n_munis, big.mark = ",")))
}

report_lines <- c(report_lines,
  "",
  "**Pass criterion:** Median ≥ 5 firms per cell; P10 ≥ 2.",
  "",
  "### D2 — Within-Muni-Year Dispersion",
  "",
  "Proxy: variance of sector employment share within (muni, year) cells.",
  "Higher variance = more heterogeneity across sectors within a municipality.",
  "",
  "| Taxonomy | var(s_{jmt} proxy) | vs. CNAE baseline |",
  "|----------|-------------------|-------------------|"
)

base_var <- res_dt[sector_var == "cnae_section", d2_var_smjt]
for (i in seq_len(nrow(res_dt))) {
  r <- res_dt[i]
  vs_base <- if (is.na(r$d2_var_smjt) || is.na(base_var) || base_var == 0) "---"
             else sprintf("%.1f%%", (r$d2_var_smjt / base_var - 1) * 100)
  report_lines <- c(report_lines,
    sprintf("| %s | %.5f | %s |",
            r$label,
            if (is.na(r$d2_var_smjt)) NA_real_ else r$d2_var_smjt,
            vs_base))
}

report_lines <- c(report_lines,
  "",
  "**Pass criterion:** Variance ≥ baseline (`cnae_section`).",
  "",
  "### D3 — First-Stage Relevance",
  "",
  "Maximum F-statistic observed across all available `.tex` tables for each taxonomy.",
  "",
  "| Taxonomy | Max F-stat | Tables parsed | F > 10? |",
  "|----------|------------|---------------|---------|"
)

for (i in seq_len(nrow(res_dt))) {
  r <- res_dt[i]
  pass <- if (!is.na(r$d3_max_f) && r$d3_max_f >= F_PASS) "**YES**" else "No"
  report_lines <- c(report_lines,
    sprintf("| %s | %s | %d | %s |",
            r$label,
            if (is.na(r$d3_max_f)) "---" else sprintf("%.1f", r$d3_max_f),
            r$d3_n_tables,
            pass))
}

report_lines <- c(report_lines,
  "",
  "**Note:** Tables for `cnae_size_bin` and `sector_group_size_bin` are produced by",
  "script 52. Run `Rscript run_politicsregs.R 52 -- --specs=size_bin_battery` first.",
  "",
  "### D4 — Stability: Cosine Similarity of F-stat Vectors",
  "",
  "Cosine similarity between each taxonomy's F-stat vector and the CNAE section baseline.",
  "",
  "| Taxonomy | Cosine similarity vs CNAE |",
  "|----------|--------------------------|"
)

for (i in seq_len(nrow(res_dt))) {
  r <- res_dt[i]
  cs <- r$d4_cosine_vs_baseline
  report_lines <- c(report_lines,
    sprintf("| %s | %s |",
            r$label,
            if (is.na(cs)) "---" else sprintf("%.3f", cs)))
}

report_lines <- c(report_lines,
  "",
  "### D5 — Tercile vs Quartile Robustness",
  "",
  "**DEFERRED.** Requires re-running script 30d with N_BINS = 4.",
  "Flag: compare thin-cell rates and F-stats between tercile and quartile variants.",
  "",
  "### D6 — Thin-Cell Audit",
  "",
  "| Taxonomy | Thin-cell rate (< 3 firms) | Status |",
  "|----------|---------------------------|--------|"
)

for (i in seq_len(nrow(res_dt))) {
  r <- res_dt[i]
  status <- if (is.na(r$d6_thin_rate)) "N/A"
            else if (r$d6_thin_rate > THIN_CELL_RATE_WARN) "**FLAGGED**"
            else "PASS"
  report_lines <- c(report_lines,
    sprintf("| %s | %s | %s |",
            r$label,
            pct_fmt(r$d6_thin_rate),
            status))
}

report_lines <- c(report_lines,
  "",
  "**Pass criterion:** Thin-cell rate < 10%. Flagged but not failed for size-bin variants.",
  "",
  "### D7 — Muni-Level Aggregation Fidelity",
  "",
  "Simplified proxy: mean Shannon entropy of sector employment shares within (muni, year).",
  "Higher entropy = more uniform distribution across sectors.",
  "Pass: correlation ≥ 0.8 relative to `cnae_section` baseline.",
  "",
  "| Taxonomy | Mean entropy H | vs CNAE |",
  "|----------|---------------|---------|"
)

base_ent <- res_dt[sector_var == "cnae_section", d7_entropy]
for (i in seq_len(nrow(res_dt))) {
  r <- res_dt[i]
  vs_ent <- if (is.na(r$d7_entropy) || is.na(base_ent) || base_ent == 0) "---"
            else sprintf("%.1f%%", (r$d7_entropy / base_ent - 1) * 100)
  report_lines <- c(report_lines,
    sprintf("| %s | %s | %s |",
            r$label,
            if (is.na(r$d7_entropy)) "---" else sprintf("%.3f", r$d7_entropy),
            vs_ent))
}

report_lines <- c(report_lines,
  "",
  "**Full D7 correlation** (comparing (muni, year, sector) share vectors across taxonomies)",
  "requires building the collapsed panel for all four taxonomies. Run script 52 with",
  "`--specs=size_bin_battery` and re-run this diagnostic.",
  "",
  "### D8 — Economic Interpretability",
  "",
  "**CNAE section (baseline):** A statement like 'sector C (manufacturing) received more",
  "BNDES credit' maps directly to a well-understood sector. Interpretability: HIGH.",
  "",
  "**Sector group (custom_sector):** 'Heavy manufacturing got more BNDES' is economically",
  "intuitive and groups related CNAE letters. Interpretability: HIGH.",
  "",
  "**CNAE × size-tercile (cnae_size_bin):** 'Sector C, large firms got more BNDES'",
  "is interpretable as within-sector reallocation toward larger incumbents.",
  "Interpretability: MEDIUM — adds a firm-size dimension that is not in regs.tex §2.3.",
  "",
  "**Group × size-tercile (sector_group_size_bin):** 'Heavy manufacturing T3 firms got",
  "more BNDES' is the most granular. Interpretability: MEDIUM — same caveat as above.",
  "The economic meaning is well-defined but shifts the unit from 'sector' to",
  "'sector × firm-size class', which requires updating the muni-level interpretation",
  "in §2.6 of regs.tex.",
  "",
  "**Recommendation (pending D1/D6 pass):** Prefer `custom_sector` as the baseline",
  "for robustness tables. Add `cnae_size_bin` only if D1 (median ≥ 5) and D6 (thin < 10%)",
  "both pass and D7 correlation ≥ 0.8.",
  "",
  "### D9 — Lead-Alignment Placebo",
  "",
  "**DEFERRED.** Requires re-running script 52 with lead alignment instruments.",
  "Flag: expect null coefficients on `FA_bar_*` when using lead-term ownership.",
  "",
  "---",
  "",
  "## Decision Rule",
  "",
  "From Section E.3 of the plan: declare a taxonomy 'preferred' only if it passes",
  "D1 (median ≥ 5, P10 ≥ 2), D3 (some F > 10 with F < 10,000), D6 (thin < 10%),",
  "and D7 (correlation ≥ 0.8). Larger F-stats with degraded D4/D6/D7 do not win.",
  "",
  sprintf("Report generated: %s", run_date),
  ""
)

writeLines(report_lines, MD_OUT)
cat(sprintf("  Wrote %d lines to %s\n", length(report_lines), MD_OUT))

# ==============================================================================
# Summary
# ==============================================================================

cat("\n==============================================================================\n")
cat("Sector Taxonomy Diagnostics — Summary\n")
cat("==============================================================================\n\n")

cat(sprintf("%-30s  %8s  %8s  %6s  %6s  %6s\n",
            "Taxonomy", "Cells", "Med_nf", "Max_F", "Thin%", "D4_cos"))
cat(strrep("-", 72), "\n")
for (i in seq_len(nrow(res_dt))) {
  r <- res_dt[i]
  cat(sprintf("%-30s  %8s  %8s  %6s  %6s  %6s\n",
              r$sector_var,
              if (is.na(r$d1_n_cells)) "---" else format(r$d1_n_cells, big.mark = ","),
              if (is.na(r$d1_med_firms)) "---" else round(r$d1_med_firms),
              if (is.na(r$d3_max_f)) "---" else sprintf("%.1f", r$d3_max_f),
              if (is.na(r$d6_thin_rate)) "---" else sprintf("%.1f%%", r$d6_thin_rate * 100),
              if (is.na(r$d4_cosine_vs_baseline)) "---"
                else sprintf("%.3f", r$d4_cosine_vs_baseline)))
}
cat("\n")
cat(sprintf("Outputs:\n  %s\n  %s\n", TEX_OUT, MD_OUT))
cat("\n==============================================================================\n")
cat("Done.\n")
cat("==============================================================================\n")
