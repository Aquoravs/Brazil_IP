#!/usr/bin/env Rscript

# ==============================================================================
# Build Shift-Share (Bartik) Instruments
# ==============================================================================
# Combines baseline sector exposure weights (script 33) with alignment shocks
# (script 32) to construct municipality-level and municipality-sector-level
# shift-share instruments. The owner-count design keeps the historical column
# names for backward compatibility; alternative weight variants insert an infix
# after the instrument prefix, e.g. dZ_emp_*, Z_firm_*, dZ_binary_*.
#
# Also builds variant-specific sector exposure controls. The output includes
# both the generic plan-facing control names (exposure_control_emp, etc.) and
# tier-specific variants (..._mayor, ..._gov_pres) used by script 53 to match
# the current control-interaction structure.
#
# Dependencies: scripts 32 (alignment_shocks.qs2), 33 (baseline_sector_weights.qs2)
# ==============================================================================

cat("==============================================================================\n")
cat("Building Shift-Share Instruments\n")
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

setDTthreads(0)

# --- Parse CLI arguments -----------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

svar_flag <- grep("^--sector-var=", args, value = TRUE)
SECTOR_VAR <- "sector_group"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[1])))
  if (!SECTOR_VAR %in% c("cnae_section", "sector_group")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'. Use 'cnae_section' or 'sector_group'.")
  }
}
USE_GROUPS <- (SECTOR_VAR == "sector_group")
SCOL <- SECTOR_VAR
cat("Sector variable:", SECTOR_VAR, "\n\n")

# --- Configuration -----------------------------------------------------------

if (USE_GROUPS) {
  baseline_path <- make_output_path("baseline_sector_weights_grouped.qs2")
  out_path <- make_output_path("shift_share_instruments_grouped.qs2")
  output_sector_path <- make_output_path("shift_share_instruments_sector_grouped.qs2")
  summary_path <- make_output_path("shift_share_instruments_grouped_summary.csv")
  controls_output_path <- make_output_path("exposure_control_sector_grouped.qs2")
} else {
  baseline_path <- make_output_path("baseline_sector_weights.qs2")
  out_path <- make_output_path("shift_share_instruments.qs2")
  output_sector_path <- make_output_path("shift_share_instruments_sector.qs2")
  summary_path <- make_output_path("shift_share_instruments_summary.csv")
  controls_output_path <- make_output_path("exposure_control_sector.qs2")
}
shocks_path <- make_output_path("alignment_shocks.qs2")

WEIGHT_VARIANTS <- list(
  owner_count = list(weight_col = "w_rjp_0", infix = "", control_stub = ""),
  employment = list(weight_col = "w_rjp_emp_0", infix = "emp_", control_stub = "emp_"),
  equal_firm = list(weight_col = "w_rjp_firm_0", infix = "firm_", control_stub = "firm_"),
  binary = list(weight_col = "w_rjp_binary_0", infix = "binary_", control_stub = "binary_")
)

term_map <- rbindlist(list(
  data.table(inaug_year = 2005L, year = 2005L:2008L),
  data.table(inaug_year = 2009L, year = 2009L:2012L),
  data.table(inaug_year = 2013L, year = 2013L:2016L),
  data.table(inaug_year = 2017L, year = 2017L:2020L),
  data.table(inaug_year = 2003L, year = 2003L:2006L),
  data.table(inaug_year = 2007L, year = 2007L:2010L),
  data.table(inaug_year = 2011L, year = 2011L:2014L),
  data.table(inaug_year = 2015L, year = 2015L:2018L)
))

control_name <- function(control_stub, tier = NULL) {
  base <- if (nzchar(control_stub)) {
    paste0("exposure_control_", sub("_$", "", control_stub))
  } else {
    "exposure_control"
  }
  if (is.null(tier)) {
    return(base)
  }
  paste0(base, "_", tier)
}

build_change_name <- function(infix, shock_col) {
  paste0("dZ_", infix, sub("^dalign_", "", shock_col))
}

build_level_name <- function(infix, shock_col) {
  paste0("Z_", infix, sub("^align_", "", shock_col))
}

spread_instruments <- function(dt, spread_cols, id_cols) {
  out <- copy(dt)
  setnames(out, "year", "inaug_year")
  out <- merge(out, term_map, by = "inaug_year", allow.cartesian = TRUE)
  out[, inaug_year := NULL]
  out[, lapply(.SD, sum, na.rm = TRUE), by = id_cols, .SDcols = spread_cols]
}

merge_many <- function(dt_list, by_cols) {
  dt_list <- Filter(function(x) !is.null(x) && nrow(x) > 0, dt_list)
  if (!length(dt_list)) {
    return(NULL)
  }
  Reduce(function(x, y) merge(x, y, by = by_cols, all = TRUE), dt_list)
}

# --- Step 1: Load data -------------------------------------------------------

cat("Step 1: Loading baseline weights and alignment shocks...\n")

if (!file.exists(baseline_path)) {
  stop("Baseline weights not found: ", baseline_path, "\n  Run script 33 first.")
}
if (!file.exists(shocks_path)) {
  stop("Alignment shocks not found: ", shocks_path, "\n  Run script 32 first.")
}

baseline <- qs_read(baseline_path)
setDT(baseline)
cat("  Baseline weights:", nrow(baseline), "rows\n")

shocks <- qs_read(shocks_path)
setDT(shocks)
cat("  Alignment shocks:", nrow(shocks), "rows\n")

required_baseline_cols <- c(
  "muni_id", SCOL, "party", "treatment_year", "tier", "baseline_type",
  "w_rjp_0", "w_rjp_emp_0", "w_rjp_firm_0", "w_rjp_binary_0"
)
missing_baseline_cols <- setdiff(required_baseline_cols, names(baseline))
if (length(missing_baseline_cols)) {
  stop("Baseline weights missing required columns: ", paste(missing_baseline_cols, collapse = ", "))
}

dalign_cols <- c(
  "dalign_mayor_party", "dalign_mayor_coalition",
  "dalign_gov_party", "dalign_gov_coalition",
  "dalign_pres_party", "dalign_pres_coalition"
)
dalign_present <- intersect(dalign_cols, names(shocks))

level_cols <- grep("^align_(mayor|gov|pres)_(party|coalition)$", names(shocks), value = TRUE)

cat("  Shock columns:", paste(dalign_present, collapse = ", "), "\n")
cat("  Level columns:", paste(level_cols, collapse = ", "), "\n\n")

# --- Step 2: Merge baselines with shocks -------------------------------------

cat("Step 2: Merging baseline weights with shocks...\n")

merge_cols <- c(dalign_present, level_cols)
merged <- merge(
  baseline,
  shocks[, c("muni_id", "party", "year", merge_cols), with = FALSE],
  by.x = c("muni_id", "party", "treatment_year"),
  by.y = c("muni_id", "party", "year"),
  all.x = TRUE
)

for (col in merge_cols) {
  if (grepl("^dalign_", col)) {
    merged[is.na(get(col)), (col) := 0]
  } else {
    merged[is.na(get(col)), (col) := 0L]
  }
}

cat("  After merge:", nrow(merged), "rows\n")
cat(sprintf("  Rows with missing shock data before fill: %d\n",
            sum(is.na(shocks$muni_id))))

# --- Step 3: Build variant-specific instruments ------------------------------

cat("\nStep 3: Computing instruments for all weight variants...\n")

variant_muni <- list()
variant_sector <- list()
variant_controls <- list()

for (variant_name in names(WEIGHT_VARIANTS)) {
  variant <- WEIGHT_VARIANTS[[variant_name]]
  weight_col <- variant$weight_col
  infix <- variant$infix
  control_stub <- variant$control_stub

  cat(sprintf("  [%s] weight column: %s\n", variant_name, weight_col))

  tmp_cols <- unique(c(
    "muni_id", SCOL, "treatment_year", "tier", "baseline_type",
    weight_col, dalign_present, level_cols
  ))
  tmp <- copy(merged[, ..tmp_cols])
  setnames(tmp, weight_col, "weight_value")
  tmp[is.na(weight_value), weight_value := 0]

  is_mayor <- tmp$tier == "mayor"
  is_gp <- tmp$tier == "gov_pres"

  change_internal <- character(0)
  for (col in dalign_present) {
    out_col <- build_change_name(infix, col)
    change_internal <- c(change_internal, out_col)
    if (grepl("^dalign_mayor_", col)) {
      tmp[, (out_col) := fifelse(is_mayor, weight_value * get(col), 0)]
    } else {
      tmp[, (out_col) := fifelse(is_gp, weight_value * get(col), 0)]
    }
  }

  level_internal <- character(0)
  for (col in level_cols) {
    out_col <- build_level_name(infix, col)
    level_internal <- c(level_internal, out_col)
    if (grepl("^align_mayor_", col)) {
      tmp[, (out_col) := fifelse(is_mayor, weight_value * get(col), 0)]
    } else {
      tmp[, (out_col) := fifelse(is_gp, weight_value * get(col), 0)]
    }
  }

  control_cols <- c(
    control_name(control_stub),
    control_name(control_stub, "mayor"),
    control_name(control_stub, "gov_pres")
  )
  tmp[, (control_cols[1]) := weight_value]
  tmp[, (control_cols[2]) := fifelse(is_mayor, weight_value, 0)]
  tmp[, (control_cols[3]) := fifelse(is_gp, weight_value, 0)]

  agg_cols <- c(change_internal, level_internal)

  variant_muni[[variant_name]] <- tmp[, lapply(.SD, sum, na.rm = TRUE),
                                      by = .(muni_id, treatment_year, baseline_type),
                                      .SDcols = agg_cols]
  variant_sector[[variant_name]] <- tmp[, lapply(.SD, sum, na.rm = TRUE),
                                        by = c("muni_id", SCOL, "treatment_year", "baseline_type"),
                                        .SDcols = agg_cols]
  variant_controls[[variant_name]] <- tmp[, lapply(.SD, sum, na.rm = TRUE),
                                          by = c("muni_id", SCOL, "treatment_year", "baseline_type"),
                                          .SDcols = control_cols]

  cat(sprintf(
    "    Built %d muni rows, %d muni-sector rows, %d control rows\n",
    nrow(variant_muni[[variant_name]]),
    nrow(variant_sector[[variant_name]]),
    nrow(variant_controls[[variant_name]])
  ))
}

muni_by_inaug <- merge_many(variant_muni, c("muni_id", "treatment_year", "baseline_type"))
sector_by_inaug <- merge_many(variant_sector, c("muni_id", SCOL, "treatment_year", "baseline_type"))
controls_by_inaug <- merge_many(variant_controls, c("muni_id", SCOL, "treatment_year", "baseline_type"))

setnames(muni_by_inaug, "treatment_year", "year")
setnames(sector_by_inaug, "treatment_year", "year")
setnames(controls_by_inaug, "treatment_year", "year")

change_cols <- grep("^dZ_", names(muni_by_inaug), value = TRUE)
level_out_cols <- grep("^Z_", names(muni_by_inaug), value = TRUE)
control_out_cols <- grep("^exposure_control", names(controls_by_inaug), value = TRUE)

cat("\n  Changes instrument columns:", paste(change_cols, collapse = ", "), "\n")
cat("  Levels instrument columns:", paste(level_out_cols, collapse = ", "), "\n")
cat("  Exposure control columns:", paste(control_out_cols, collapse = ", "), "\n")

# --- Step 4: Spread levels instruments and controls across terms -------------

cat("\nStep 4: Spreading levels instruments and controls across electoral terms...\n")
cat("  dZ (changes): not spread\n")
cat("  Z (levels): spread across term\n")
cat("  Exposure controls: spread across term\n")

muni_changes <- copy(muni_by_inaug[, c("muni_id", "year", "baseline_type", change_cols), with = FALSE])
sector_changes <- copy(sector_by_inaug[, c("muni_id", SCOL, "year", "baseline_type", change_cols), with = FALSE])

muni_changes <- muni_changes[year >= 2002L & year <= 2017L]
sector_changes <- sector_changes[year >= 2002L & year <= 2017L]
for (col in change_cols) {
  muni_changes[is.na(get(col)), (col) := 0]
  sector_changes[is.na(get(col)), (col) := 0]
}

muni_levels <- spread_instruments(muni_by_inaug[, c("muni_id", "year", "baseline_type", level_out_cols), with = FALSE],
                                  level_out_cols,
                                  c("muni_id", "year", "baseline_type"))
sector_levels <- spread_instruments(sector_by_inaug[, c("muni_id", SCOL, "year", "baseline_type", level_out_cols), with = FALSE],
                                    level_out_cols,
                                    c("muni_id", SCOL, "year", "baseline_type"))
controls_spread <- spread_instruments(controls_by_inaug,
                                      control_out_cols,
                                      c("muni_id", SCOL, "year", "baseline_type"))

muni_levels <- muni_levels[year >= 2002L & year <= 2017L]
sector_levels <- sector_levels[year >= 2002L & year <= 2017L]
controls_spread <- controls_spread[year >= 2002L & year <= 2017L]

for (col in level_out_cols) {
  muni_levels[is.na(get(col)), (col) := 0]
  sector_levels[is.na(get(col)), (col) := 0]
}
for (col in control_out_cols) {
  controls_spread[is.na(get(col)), (col) := 0]
}

instruments_unified <- merge(
  muni_changes,
  muni_levels,
  by = c("muni_id", "year", "baseline_type"),
  all = TRUE
)
instruments_sector_unified <- merge(
  sector_changes,
  sector_levels,
  by = c("muni_id", SCOL, "year", "baseline_type"),
  all = TRUE
)

for (col in c(change_cols, level_out_cols)) {
  instruments_unified[is.na(get(col)), (col) := 0]
  instruments_sector_unified[is.na(get(col)), (col) := 0]
}

# --- Step 5: Diagnostics ----------------------------------------------------

cat("\nStep 5: Diagnostics...\n")

for (col in change_cols) {
  vals <- instruments_unified[[col]]
  cat(sprintf("  %s: mean=%.6f, sd=%.6f, nonzero=%d/%d\n",
              col, mean(vals, na.rm = TRUE), sd(vals, na.rm = TRUE),
              sum(vals != 0, na.rm = TRUE), length(vals)))
}
for (col in level_out_cols) {
  vals <- instruments_unified[[col]]
  cat(sprintf("  %s: mean=%.6f, sd=%.6f, nonzero=%d/%d\n",
              col, mean(vals, na.rm = TRUE), sd(vals, na.rm = TRUE),
              sum(vals != 0, na.rm = TRUE), length(vals)))
}

for (col in control_out_cols) {
  vals <- controls_spread[[col]]
  cat(sprintf("  %s: mean=%.6f, sd=%.6f, positive=%d/%d\n",
              col, mean(vals, na.rm = TRUE), sd(vals, na.rm = TRUE),
              sum(vals > 0, na.rm = TRUE), length(vals)))
}

for (bt in unique(instruments_unified$baseline_type)) {
  sub <- instruments_unified[baseline_type == bt]
  cat(sprintf("  [%s] %d muni-years, %d unique munis\n",
              bt, nrow(sub), uniqueN(sub$muni_id)))
}

# --- Step 6: Save ------------------------------------------------------------

cat("\nStep 6: Saving...\n")

setorder(instruments_unified, baseline_type, year, muni_id)
qs_save(instruments_unified, out_path)

summary_cols <- c(change_cols, level_out_cols)
summ <- instruments_unified[, c(
  list(n_rows = .N, n_munis = uniqueN(muni_id)),
  lapply(.SD, function(x) c(mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE)))
), by = .(baseline_type, year), .SDcols = summary_cols]

fwrite(summ, summary_path)

cat(sprintf("  Saved %s (%.2f MB)\n", out_path, file.size(out_path) / 1024^2))
cat(sprintf("  Saved %s\n", summary_path))

setorderv(instruments_sector_unified, c("baseline_type", "year", "muni_id", SCOL))
qs_save(instruments_sector_unified, output_sector_path)
cat(sprintf("  Saved %s (%.2f MB)\n", output_sector_path, file.size(output_sector_path) / 1024^2))

setorderv(controls_spread, c("baseline_type", "year", "muni_id", SCOL))
qs_save(controls_spread, controls_output_path)
cat(sprintf("  Saved %s (%.2f MB)\n", controls_output_path, file.size(controls_output_path) / 1024^2))

cat("\nShift-share instruments complete.\n")
