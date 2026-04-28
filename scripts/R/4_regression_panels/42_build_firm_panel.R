#!/usr/bin/env Rscript

# ==============================================================================
# Build Firm Regression Panel
# ==============================================================================
# Merges firm-level instruments with BNDES credit and employment, constructs
# outcome variables for extensive and intensive margin regressions.
#
# Panel unit: firm x muni x year
#
# Outcomes:
#   has_bndes_fmt       — indicator for positive BNDES credit (0/1)
#   log_bndes_fmt       — log(BNDES) when positive, NA otherwise
#   delta_has_bndes_fmt — change in BNDES indicator within (firm_id, muni_id)
#   delta_log_bndes_fmt — change in log(BNDES), NA unless positive in both t and t-1
#
# Dependencies:
#   - Script 22: rais_bndes_reconstructed.fst/.qs2
#   - Script 36: firm_level_instruments.qs2
# ==============================================================================

cat("==============================================================================\n")
cat("Building Firm Regression Panel\n")
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

# Large joins here are memory-bound; a single data.table thread avoids
# extra temporary allocations from parallel sorting/join paths.
setDTthreads(1)

# --- Configuration -----------------------------------------------------------

recon_fst_path <- make_output_path("rais_bndes_reconstructed.fst")
recon_qs2_path <- make_output_path("rais_bndes_reconstructed.qs2")
instr_path     <- make_output_path("firm_level_instruments.qs2")
instr_summary_in_path <- make_output_path("firm_level_instruments_summary.csv")
summary_path   <- make_output_path("firm_panel_summary.csv")
muni_emp_baselines_path <- make_output_path("muni_employment_baselines.qs2")
muni_emp_class_path     <- make_output_path("muni_employment_classification.qs2")

count_nonzero_rows <- function(dt, cols, idx = NULL) {
  if (!length(cols)) return(0L)

  if (is.null(idx)) {
    n <- nrow(dt)
    subset_vec <- function(x) x
  } else {
    n <- if (is.logical(idx)) sum(idx) else length(idx)
    subset_vec <- function(x) x[idx]
  }

  any_nonzero <- rep(FALSE, n)
  for (col in cols) {
    vals <- subset_vec(dt[[col]])
    any_nonzero <- any_nonzero | (!is.na(vals) & vals != 0)
  }

  sum(any_nonzero)
}

write_fst_atomic <- function(dt, final_path, compress = 50) {
  if (!requireNamespace("fst", quietly = TRUE)) {
    cat("    fst package not available; skipping .fst write\n")
    return(invisible(FALSE))
  }

  tmp_path <- paste0(final_path, ".tmp")
  bak_path <- paste0(final_path, ".bak")

  unlink(tmp_path)
  unlink(bak_path)

  ok <- FALSE

  tryCatch({
    fst::write_fst(dt, tmp_path, compress = compress)

    if (file.exists(final_path)) {
      if (!file.rename(final_path, bak_path)) {
        stop("Could not move existing fst file aside before replacement.")
      }
    }

    if (!file.rename(tmp_path, final_path)) {
      if (file.exists(bak_path) && !file.exists(final_path)) {
        file.rename(bak_path, final_path)
      }
      stop("Could not promote temporary fst file to final path.")
    }

    if (file.exists(bak_path)) unlink(bak_path)
    ok <- TRUE
  }, error = function(e) {
    unlink(tmp_path)
    if (file.exists(bak_path) && !file.exists(final_path)) {
      file.rename(bak_path, final_path)
    }
    warning(sprintf("Failed to write fst companion file [%s]: %s",
                    basename(final_path), conditionMessage(e)))
  })

  invisible(ok)
}

# ==============================================================================
# STEP 1: Load reconstructed firm panel
# ==============================================================================

cat("Step 1: Loading reconstructed firm panel...\n")

load_cols <- c("firm_id", "muni_id", "year", "cnae_section",
               "n_employees", "value_dis_real_2018_total")

if (file.exists(recon_fst_path) && requireNamespace("fst", quietly = TRUE)) {
  cat("  Loading from fst:", basename(recon_fst_path), "\n")
  panel <- fst::read_fst(recon_fst_path, columns = load_cols, as.data.table = TRUE)
} else if (file.exists(recon_qs2_path)) {
  cat("  Loading from qs2:", basename(recon_qs2_path), "\n")
  raw <- qs_read(recon_qs2_path)
  setDT(raw)
  panel <- raw[, ..load_cols]
  rm(raw); invisible(gc())
} else {
  stop("Reconstructed panel not found. Run script 22 first.")
}

# Ensure integer keys
panel[, firm_id := as.integer(firm_id)]
panel[, muni_id := as.integer(muni_id)]
panel[, year    := as.integer(year)]

# Drop invalid muni_id (0 is not a valid IBGE municipality code)
n_invalid_muni <- sum(panel$muni_id == 0L | is.na(panel$muni_id))
if (n_invalid_muni > 0L) {
  cat(sprintf("  Dropping %d rows with invalid muni_id (0 or NA)\n", n_invalid_muni))
  panel <- panel[!is.na(muni_id) & muni_id > 0L]
}

# Fill NA credit values with 0 (no BNDES = zero credit)
panel[is.na(value_dis_real_2018_total), value_dis_real_2018_total := 0]

cat(sprintf("  Loaded: %s rows, %d firms, %d munis, years %d-%d\n",
            format(nrow(panel), big.mark = ","),
            uniqueN(panel$firm_id),
            uniqueN(panel$muni_id),
            min(panel$year), max(panel$year)))

# ==============================================================================
# STEP 2: Construct outcome variables
# ==============================================================================

cat("\nStep 2: Constructing outcome variables...\n")

# Extensive margin: indicator for positive BNDES credit
panel[, has_bndes_fmt := as.integer(value_dis_real_2018_total > 0)]

# Intensive margin: log BNDES (NA when zero)
panel[, log_bndes_fmt := fifelse(
  value_dis_real_2018_total > 0,
  log(value_dis_real_2018_total),
  NA_real_
)]

# Employment outcomes
panel[, log_n_employees := fifelse(
  !is.na(n_employees) & n_employees > 0,
  log(n_employees),
  NA_real_
)]

panel[, total_muni_rais_employment := sum(n_employees, na.rm = TRUE), by = .(muni_id, year)]
panel[, emp_share_muni_rais := fifelse(
  !is.na(n_employees) & total_muni_rais_employment > 0,
  n_employees / total_muni_rais_employment,
  NA_real_
)]
panel[, total_muni_rais_employment := NULL]

cat(sprintf("  Extensive margin: %d / %d firm-muni-years with BNDES > 0 (%.2f%%)\n",
            sum(panel$has_bndes_fmt), nrow(panel),
            100 * mean(panel$has_bndes_fmt)))

cat(sprintf("  Intensive margin: %d observations with defined log(BNDES)\n",
            sum(!is.na(panel$log_bndes_fmt))))

cat(sprintf("  Log employment: %d observations with defined log employment\n",
            sum(!is.na(panel$log_n_employees))))

cat(sprintf("  Employment share: %d observations with defined municipality-year RAIS share\n",
            sum(!is.na(panel$emp_share_muni_rais))))

# ==============================================================================
# STEP 3: Construct changes outcomes within (firm_id, muni_id)
# ==============================================================================

cat("\nStep 3: Constructing changes outcomes...\n")

setorder(panel, firm_id, muni_id, year)
# `setorder()` does not mark a key, but the table is now physically sorted by
# the join columns and can safely be treated as keyed for the upcoming join.
setattr(panel, "sorted", c("firm_id", "muni_id", "year"))

# Changes in extensive margin indicator
panel[, delta_has_bndes_fmt := has_bndes_fmt - shift(has_bndes_fmt, 1L, type = "lag"),
      by = .(firm_id, muni_id)]

# Changes in intensive margin: defined only when both t and t-1 have positive BNDES
panel[, lag_log_bndes := shift(log_bndes_fmt, 1L, type = "lag"),
      by = .(firm_id, muni_id)]

panel[, delta_log_bndes_fmt := fifelse(
  !is.na(log_bndes_fmt) & !is.na(lag_log_bndes),
  log_bndes_fmt - lag_log_bndes,
  NA_real_
)]

# Changes in log employment: defined only when both t and t-1 have positive employment
panel[, lag_log_n_employees := shift(log_n_employees, 1L, type = "lag"),
      by = .(firm_id, muni_id)]

panel[, delta_log_n_employees := fifelse(
  !is.na(log_n_employees) & !is.na(lag_log_n_employees),
  log_n_employees - lag_log_n_employees,
  NA_real_
)]

# Changes in municipality employment share
panel[, lag_emp_share_muni_rais := shift(emp_share_muni_rais, 1L, type = "lag"),
      by = .(firm_id, muni_id)]

panel[, delta_emp_share_muni_rais := fifelse(
  !is.na(emp_share_muni_rais) & !is.na(lag_emp_share_muni_rais),
  emp_share_muni_rais - lag_emp_share_muni_rais,
  NA_real_
)]

# Drop temporary columns
panel[, c("lag_log_bndes", "lag_log_n_employees", "lag_emp_share_muni_rais") := NULL]

# Diagnostics for changes
n_delta_ext <- sum(!is.na(panel$delta_has_bndes_fmt))
n_delta_int <- sum(!is.na(panel$delta_log_bndes_fmt))
n_delta_emp_log <- sum(!is.na(panel$delta_log_n_employees))
n_delta_emp_share <- sum(!is.na(panel$delta_emp_share_muni_rais))
cat(sprintf("  Changes extensive: %d non-NA observations\n", n_delta_ext))
cat(sprintf("  Changes intensive: %d non-NA observations (positive BNDES in both t and t-1)\n",
            n_delta_int))
cat(sprintf("  Changes log employment: %d non-NA observations\n", n_delta_emp_log))
cat(sprintf("  Changes employment share: %d non-NA observations\n", n_delta_emp_share))

# Verify first-year deltas are NA (not zero)
first_year_dt <- panel[, .SD[1L], by = .(firm_id, muni_id)]
n_first_na_ext <- sum(is.na(first_year_dt$delta_has_bndes_fmt))
n_first_na_int <- sum(is.na(first_year_dt$delta_log_bndes_fmt))
n_first_na_emp_log <- sum(is.na(first_year_dt$delta_log_n_employees))
n_first_na_emp_share <- sum(is.na(first_year_dt$delta_emp_share_muni_rais))
cat(sprintf("  First-year delta_has NA: %d / %d (expect all NA)\n",
            n_first_na_ext, nrow(first_year_dt)))
cat(sprintf("  First-year delta_log_bndes NA: %d / %d (expect all NA)\n",
            n_first_na_int, nrow(first_year_dt)))
cat(sprintf("  First-year delta_log_employment NA: %d / %d (expect all NA)\n",
            n_first_na_emp_log, nrow(first_year_dt)))
cat(sprintf("  First-year delta_emp_share NA: %d / %d (expect all NA)\n",
            n_first_na_emp_share, nrow(first_year_dt)))
rm(first_year_dt)
invisible(gc())

# ==============================================================================
# STEP 3B: Multi-municipality flag
# ==============================================================================

cat("\nStep 3B: Computing multi-municipality flag...\n")

# is_multi_muni = 1 in years where the firm has 2+ municipalities (per-year).
# The panel is guaranteed unique on (firm_id, muni_id, year), so the count of
# distinct munis per (firm_id, year) equals the row count .N. We use .N rather
# than uniqueN() because .N is GForce-accelerated (optimized C) — orders of
# magnitude faster on 44M rows with single-thread data.table.
panel[, is_multi_muni := as.integer(.N > 1L),
      by = .(firm_id, year)]

# Aggregate all multi-muni diagnostics in ONE grouped pass rather than four
# separate scans of the 44M-row panel.
mm_stats <- panel[, .(
  n_total       = .N,
  n_multi       = sum(is_multi_muni, na.rm = TRUE),
  emp_total     = sum(n_employees, na.rm = TRUE),
  emp_multi     = sum(n_employees * is_multi_muni, na.rm = TRUE),
  bndes_total   = sum(value_dis_real_2018_total, na.rm = TRUE),
  bndes_multi   = sum(value_dis_real_2018_total * is_multi_muni, na.rm = TRUE),
  dext_all      = sum(!is.na(delta_has_bndes_fmt)),
  dext_single   = sum(!is.na(delta_has_bndes_fmt) & is_multi_muni == 0L),
  dint_all      = sum(!is.na(delta_log_bndes_fmt)),
  dint_single   = sum(!is.na(delta_log_bndes_fmt) & is_multi_muni == 0L)
)]

cat(sprintf("  Multi-muni firm-muni-years: %s / %s (%.2f%%)\n",
            format(mm_stats$n_multi, big.mark = ","),
            format(mm_stats$n_total, big.mark = ","),
            100 * mm_stats$n_multi / mm_stats$n_total))
cat(sprintf("  Employment in multi-muni firms: %.1f%% of total\n",
            100 * mm_stats$emp_multi / mm_stats$emp_total))
cat(sprintf("  BNDES credit to multi-muni firms: %.1f%% of total\n",
            100 * mm_stats$bndes_multi / mm_stats$bndes_total))
cat(sprintf("  Delta_ext non-NA: all=%d, single-muni=%d (diff=%d)\n",
            mm_stats$dext_all, mm_stats$dext_single,
            mm_stats$dext_all - mm_stats$dext_single))
cat(sprintf("  Delta_int non-NA: all=%d, single-muni=%d (diff=%d)\n",
            mm_stats$dint_all, mm_stats$dint_single,
            mm_stats$dint_all - mm_stats$dint_single))
rm(mm_stats)

# Preserve BNDES-amount diagnostics, then drop the raw amount column before the
# large script-36 merge to keep memory use within the prior working envelope.
bndes_total_amt <- sum(panel$value_dis_real_2018_total, na.rm = TRUE)
bndes_pos_emp_amt <- sum(panel[n_employees > 0, value_dis_real_2018_total], na.rm = TRUE)
bndes_pos_emp_share <- if (bndes_total_amt > 0) {
  100 * bndes_pos_emp_amt / bndes_total_amt
} else {
  NA_real_
}
panel[, value_dis_real_2018_total := NULL]
invisible(gc())

# ==============================================================================
# STEP 3C: Compute pre-election baseline employment
# ==============================================================================
# For employment-weighted regressions, we use pre-election baseline employment
# (average over the same windows as the party affiliation baselines) instead of
# contemporaneous employment, which is endogenous to the BNDES lending channel.
#
# Baseline windows mirror script 36: pooled [election_year - 4, election_year - 1].
# For cycle_specific: cycle-specific windows. For 2002_fixed: year 2002 only.
# After computing per-window averages, we spread across electoral terms and
# average across tiers for years covered by multiple inaugurations.

cat("\nStep 3C: Computing pre-election baseline employment...\n")

# Static window definitions (same as script 36)
bl_window_map <- rbindlist(list(
  # Mayor inaugurations
  data.table(treatment_year = 2005L, bl_start = 2000L, bl_end = 2003L, tier = "mayor"),
  data.table(treatment_year = 2009L, bl_start = 2004L, bl_end = 2007L, tier = "mayor"),
  data.table(treatment_year = 2013L, bl_start = 2008L, bl_end = 2011L, tier = "mayor"),
  data.table(treatment_year = 2017L, bl_start = 2012L, bl_end = 2015L, tier = "mayor"),
  # Governor/President inaugurations
  data.table(treatment_year = 2007L, bl_start = 2002L, bl_end = 2005L, tier = "gov_pres"),
  data.table(treatment_year = 2011L, bl_start = 2006L, bl_end = 2009L, tier = "gov_pres"),
  data.table(treatment_year = 2015L, bl_start = 2010L, bl_end = 2013L, tier = "gov_pres")
))

# Term map: each inauguration year maps to its 4-year term
bl_term_map <- rbindlist(list(
  data.table(inaug_year = 2005L, year = 2005L:2008L),
  data.table(inaug_year = 2009L, year = 2009L:2012L),
  data.table(inaug_year = 2013L, year = 2013L:2016L),
  data.table(inaug_year = 2017L, year = 2017L:2020L),
  data.table(inaug_year = 2007L, year = 2007L:2010L),
  data.table(inaug_year = 2011L, year = 2011L:2014L),
  data.table(inaug_year = 2015L, year = 2015L:2018L)
))

available_years <- sort(unique(panel$year))

compute_bl_employment <- function(panel_dt, window_map, baseline_type, avail_years) {
  out <- vector("list", nrow(window_map))

  for (i in seq_len(nrow(window_map))) {
    ty     <- window_map$treatment_year[i]
    bstart <- window_map$bl_start[i]
    bend   <- window_map$bl_end[i]

    if (identical(baseline_type, "2002_fixed")) {
      window_years <- intersect(2002L, avail_years)
    } else {
      window_years <- intersect(seq(bstart, bend), avail_years)
    }

    if (length(window_years) == 0L) {
      cat(sprintf("  WARNING: No employment data in window %d-%d (treatment %d, %s) -- skipping\n",
                  bstart, bend, ty, baseline_type))
      next
    }

    emp_window <- panel_dt[year %in% window_years,
      .(bl_n_employees = mean(n_employees, na.rm = TRUE)),
      by = .(firm_id, muni_id)
    ]
    # NaN from all-NA → set to NA
    emp_window[is.nan(bl_n_employees), bl_n_employees := NA_real_]
    emp_window[, inaug_year := ty]

    cat(sprintf("  %s treatment=%d, window=%d-%d (%s; used %d yrs: %s): %d firm-muni rows\n",
                baseline_type, ty, bstart, bend, baseline_type,
                length(window_years), paste(window_years, collapse = ","),
                nrow(emp_window)))
    out[[i]] <- emp_window
  }

  rbindlist(out, use.names = TRUE, fill = TRUE)
}

spread_bl_employment <- function(bl_emp_dt, term_map_dt, year_range = 2002L:2017L) {
  # Spread across electoral terms
  spread <- merge(bl_emp_dt, term_map_dt, by = "inaug_year", allow.cartesian = TRUE)
  spread[, inaug_year := NULL]

  # Average across tiers for years covered by multiple inaugurations
  spread <- spread[year %in% year_range,
    .(bl_n_employees = mean(bl_n_employees, na.rm = TRUE)),
    by = .(firm_id, muni_id, year)
  ]
  spread[is.nan(bl_n_employees), bl_n_employees := NA_real_]
  spread
}

# We compute baseline employment separately for each baseline_type and persist
# each to a temporary qs2 file immediately. Combined they weigh ~2.4 GB and
# Step 4 attaches them one baseline at a time — no reason to hold both in RAM
# during the critical instrument-attach step.
bl_emp_path <- function(bt) make_output_path(paste0("_tmp_bl_emp_", bt, ".qs2"))

describe_bl <- function(bt, bl) {
  n_total <- nrow(bl)
  n_pos <- sum(bl$bl_n_employees > 0, na.rm = TRUE)
  n_na  <- sum(is.na(bl$bl_n_employees))
  cat(sprintf("  [%s] Baseline employment: %d rows, %d positive (%.1f%%), %d NA (%.1f%%)\n",
              bt, n_total, n_pos, 100 * n_pos / n_total, n_na, 100 * n_na / n_total))
  if (n_pos > 0) {
    cat(sprintf("    mean=%.1f, median=%.1f, sd=%.1f\n",
                mean(bl$bl_n_employees, na.rm = TRUE),
                median(bl$bl_n_employees, na.rm = TRUE),
                sd(bl$bl_n_employees, na.rm = TRUE)))
  }
}

cat("  Computing cycle-specific baseline employment...\n")
bl_emp_cycle <- compute_bl_employment(panel, bl_window_map, "cycle_specific", available_years)
bl_emp_cycle_spread <- spread_bl_employment(bl_emp_cycle, bl_term_map)
rm(bl_emp_cycle)
describe_bl("cycle_specific", bl_emp_cycle_spread)
qs_save(bl_emp_cycle_spread, bl_emp_path("cycle_specific"))
rm(bl_emp_cycle_spread)
invisible(gc())

cat("\n  Computing 2002-fixed baseline employment...\n")
bl_emp_fixed <- compute_bl_employment(panel, bl_window_map, "2002_fixed", available_years)
bl_emp_fixed_spread <- spread_bl_employment(bl_emp_fixed, bl_term_map)
rm(bl_emp_fixed)
describe_bl("2002_fixed", bl_emp_fixed_spread)
qs_save(bl_emp_fixed_spread, bl_emp_path("2002_fixed"))
rm(bl_emp_fixed_spread)
invisible(gc())

# ==============================================================================
# STEP 3D: Load municipality employment baselines and quartile classification
# ==============================================================================
# These objects were produced by script 32b (and/or script 41).
# muni_employment_baselines.qs2  — (muni_id, election_cycle, office_tier) → muni_emp_bl
# muni_employment_classification.qs2 — (muni_id) → top_q4_muni, muni_emp_quartile
#
# We pre-compute (muni_id, year) → muni_emp_bl_{mayor,gp} lookup tables here,
# reusing bl_term_map defined in Step 3C so the lookups are built once and
# reused for every baseline type in the Step 4 loop below.

cat("\nStep 3D: Loading municipality employment baselines and classification...\n")

if (!file.exists(muni_emp_baselines_path)) {
  stop("Municipality employment baselines not found at: ", muni_emp_baselines_path,
       "\nRun script 32b first.")
}
if (!file.exists(muni_emp_class_path)) {
  stop("Municipality employment classification not found at: ", muni_emp_class_path,
       "\nRun script 32b or 41 first.")
}

muni_emp_baselines <- qs_read(muni_emp_baselines_path)
setDT(muni_emp_baselines)
muni_emp_baselines[, muni_id       := as.integer(muni_id)]
muni_emp_baselines[, election_cycle := as.integer(election_cycle)]

muni_emp_class <- qs_read(muni_emp_class_path)
setDT(muni_emp_class)
muni_emp_class[, muni_id := as.integer(muni_id)]

cat(sprintf("  Baselines loaded: %s rows, %d municipalities\n",
            format(nrow(muni_emp_baselines), big.mark = ","),
            uniqueN(muni_emp_baselines$muni_id)))
cat(sprintf("  Classification loaded: %d municipalities\n", nrow(muni_emp_class)))
cat(sprintf("  top_q4_muni distribution:\n"))
q4_tab <- muni_emp_class[, .N, by = top_q4_muni][order(top_q4_muni)]
for (k in seq_len(nrow(q4_tab))) {
  cat(sprintf("    top_q4_muni=%d: %d munis\n", q4_tab$top_q4_muni[k], q4_tab$N[k]))
}

# Build (muni_id, year) → muni_emp_bl lookups per office tier.
# bl_term_map was defined in Step 3C: inaug_year → year range.
# mayor cycles: 2005, 2009, 2013, 2017  |  gov/pres cycles: 2007, 2011, 2015
mayor_cycles <- c(2005L, 2009L, 2013L, 2017L)
gp_cycles    <- c(2007L, 2011L, 2015L)

year_to_ec_mayor <- bl_term_map[inaug_year %in% mayor_cycles,
                                .(year, election_cycle = inaug_year)]
year_to_ec_gp    <- bl_term_map[inaug_year %in% gp_cycles,
                                .(year, election_cycle = inaug_year)]

# Many-to-many by design: each election_cycle expands to multiple years (4)
# and multiple munis (~5572). Result is bounded at ~89k rows per tier — safe.
muni_bl_mayor_yr <- merge(
  year_to_ec_mayor,
  muni_emp_baselines[office_tier == "mayor",
                     .(muni_id, election_cycle, muni_emp_bl_mayor = muni_emp_bl)],
  by = "election_cycle",
  allow.cartesian = TRUE
)[, .(muni_id, year, muni_emp_bl_mayor)]
setkey(muni_bl_mayor_yr, muni_id, year)

muni_bl_gp_yr <- merge(
  year_to_ec_gp,
  muni_emp_baselines[office_tier == "gov_pres",
                     .(muni_id, election_cycle, muni_emp_bl_gp = muni_emp_bl)],
  by = "election_cycle",
  allow.cartesian = TRUE
)[, .(muni_id, year, muni_emp_bl_gp)]
setkey(muni_bl_gp_yr, muni_id, year)

panel_years <- sort(unique(panel$year))
covered_mayor <- panel_years[panel_years %in% year_to_ec_mayor$year]
covered_gp    <- panel_years[panel_years %in% year_to_ec_gp$year]
cat(sprintf("  Panel years covered by mayor lookup: %s\n", paste(covered_mayor, collapse = ",")))
cat(sprintf("  Panel years covered by gov/pres lookup: %s\n", paste(covered_gp, collapse = ",")))

rm(muni_emp_baselines)
invisible(gc())

# ==============================================================================
# STEP 4: Merge firm-level instruments
# ==============================================================================

cat("\nStep 4: Attaching firm-level instruments...\n")

if (!file.exists(instr_path)) {
  stop("Firm-level instruments not found. Run script 36 first.")
}

instruments <- qs_read(instr_path)
setDT(instruments)

instruments[, firm_id := as.integer(firm_id)]
instruments[, muni_id := as.integer(muni_id)]
instruments[, year := as.integer(year)]

cat(sprintf("  Loaded instruments: %s rows\n",
            format(nrow(instruments), big.mark = ",")))

# Identify FA and dFA columns
fa_cols  <- grep("^FA_", names(instruments), value = TRUE)
dfa_cols <- grep("^dFA_", names(instruments), value = TRUE)
all_instrument_cols <- c(fa_cols, dfa_cols)

cat(sprintf("  FA columns: %s\n", paste(fa_cols, collapse = ", ")))
cat(sprintf("  dFA columns: %s\n", paste(dfa_cols, collapse = ", ")))

# Script 36 saves only firm-muni-years with non-zero instruments (sparse).
# We left-join instruments onto the panel for each baseline type, zero-filling
# firms without owner data. Each baseline is saved as a separate file to avoid
# holding 88M rows in memory (44M panel × 2 baselines exceeds 16GB).
baseline_types <- c("cycle_specific", setdiff(sort(unique(instruments$baseline_type)), "cycle_specific"))
cat(sprintf("  Baseline types: %s\n", paste(baseline_types, collapse = ", ")))

# Binary FA/dFA columns are 0/1 — store as integer (4 bytes) rather than double
# (8 bytes). Across 48 instrument columns × 44M rows, narrowing the binary
# subset saves ~4 GB of peak RAM during the Step 4 join.
bin_cols <- grep("^FA_binary_|^dFA_binary_", all_instrument_cols, value = TRUE)
if (length(bin_cols)) {
  instruments[, (bin_cols) := lapply(.SD, as.integer), .SDcols = bin_cols]
  cat(sprintf("  Narrowed %d binary instrument columns to integer dtype\n",
              length(bin_cols)))
}

# Zero-fill any column-level NAs in the sparse instruments table itself so the
# serialized sparse file contains {0, real value} semantics. This does NOT touch
# `panel` — it only normalizes the existing sparse rows, each of which already
# carries at least one non-zero value by construction in script 36.
setnafill(instruments, type = "const", fill = 0, cols = all_instrument_cols)

# Sparsity guard. Drop any instrument row whose 48 columns are all zero after
# the NA fill. By construction script 36 should not emit such rows, but the
# refactor relies on the sparse file being strictly smaller than the panel —
# this check defends that invariant explicitly. The running-OR loop holds at
# most one logical vector of length nrow(instruments) at a time.
any_nonzero_mask <- logical(nrow(instruments))  # all FALSE
for (ic in all_instrument_cols) {
  any_nonzero_mask <- any_nonzero_mask | (instruments[[ic]] != 0)
}
n_rows_before_filter <- nrow(instruments)
if (!all(any_nonzero_mask)) {
  instruments <- instruments[any_nonzero_mask]
  cat(sprintf("  Sparsity guard: dropped %d all-zero instrument rows (%s -> %s)\n",
              n_rows_before_filter - nrow(instruments),
              format(n_rows_before_filter, big.mark = ","),
              format(nrow(instruments), big.mark = ",")))
}
rm(any_nonzero_mask)

# Split-file producer (plan 2026-04-14-002). Per baseline type we emit:
#   firm_panel_for_regs{_bt}.fst              BASE  — panel without FA/dFA
#   firm_panel_for_regs{_bt}_instruments.fst  SPARSE — only non-zero FA/dFA rows
# The 48 FA/dFA columns are never materialized onto the 44M-row panel; the
# downstream loader (scripts/R/_utils/load_firm_panel.R) attaches the subset a
# consumer actually needs.
last_bt <- baseline_types[length(baseline_types)]
for (bt in baseline_types) {
  cat(sprintf("\n  Attaching [%s] baseline...\n", bt))
  # Force a full heap consolidation before per-baseline work. On Windows the R
  # allocator fragments quickly; a full gc here keeps peak RAM bounded.
  invisible(gc(full = TRUE))
  setkey(panel, firm_id, muni_id, year)

  # Select this baseline's sparse instrument slice. Keys + 48 FA/dFA cols only.
  # No merge onto `panel` — the 14 GB allocation the old code incurred here is
  # what the refactor removes.
  inst_bt <- instruments[baseline_type == bt,
    c("firm_id", "muni_id", "year", all_instrument_cols), with = FALSE]

  # Baseline-type marker stays on panel (single integer-width column).
  panel[, baseline_type := bt]

  n_with <- nrow(inst_bt)
  cat(sprintf("    %d / %d firm-muni-years with non-zero instruments (%.1f%%)\n",
              n_with, nrow(panel), 100 * n_with / nrow(panel)))

  # Merge pre-election baseline employment (Step 3C) — reload from disk so we
  # only hold the baseline we're currently attaching in RAM.
  panel[, bl_n_employees := NA_real_]
  bl_emp_bt_path <- bl_emp_path(bt)
  if (file.exists(bl_emp_bt_path)) {
    bl_emp_bt <- qs_read(bl_emp_bt_path)
    setDT(bl_emp_bt)
    panel[bl_emp_bt, bl_n_employees := i.bl_n_employees,
          on = .(firm_id, muni_id, year)]
    rm(bl_emp_bt)
    invisible(gc())
    n_bl_pos <- sum(panel$bl_n_employees > 0, na.rm = TRUE)
    n_bl_na  <- sum(is.na(panel$bl_n_employees))
    cat(sprintf("    Baseline employment: %d positive (%.1f%%), %d NA (%.1f%%)\n",
                n_bl_pos, 100 * n_bl_pos / nrow(panel),
                n_bl_na, 100 * n_bl_na / nrow(panel)))
  } else {
    cat("    WARNING: No baseline employment data for this baseline type\n")
  }

  # -------------------------------------------------------------------------
  # Merge muni-employment share denominators and compute pre-election shares
  # (Step 3D objects; two columns — one per office tier — matching FA_mayor /
  # FA_gov/FA_pres separation in scripts 51 and 52)
  # -------------------------------------------------------------------------
  panel[, muni_emp_bl_mayor := NA_real_]
  panel[, muni_emp_bl_gp    := NA_real_]
  panel[muni_bl_mayor_yr, muni_emp_bl_mayor := i.muni_emp_bl_mayor,
        on = .(muni_id, year)]
  panel[muni_bl_gp_yr,    muni_emp_bl_gp    := i.muni_emp_bl_gp,
        on = .(muni_id, year)]

  # emp_share_muni_pre = bl_n_employees / muni_emp_bl
  # Edge cases:
  #   bl_n_employees is NA         → share is NA (firm has no baseline)
  #   muni_emp_bl is NA or 0       → share is 0 (year outside lookup or zero-emp muni)
  #   bl_n_employees is 0          → share is 0
  panel[, emp_share_muni_pre_mayor := fifelse(
    is.na(bl_n_employees),
    NA_real_,
    fifelse(
      is.na(muni_emp_bl_mayor) | muni_emp_bl_mayor <= 0,
      0,
      bl_n_employees / muni_emp_bl_mayor
    )
  )]
  panel[, emp_share_muni_pre_gp := fifelse(
    is.na(bl_n_employees),
    NA_real_,
    fifelse(
      is.na(muni_emp_bl_gp) | muni_emp_bl_gp <= 0,
      0,
      bl_n_employees / muni_emp_bl_gp
    )
  )]
  panel[, muni_emp_bl_mayor := NULL]
  panel[, muni_emp_bl_gp    := NULL]

  # Merge time-invariant quartile flag
  panel[, top_q4_muni := NA_integer_]
  panel[muni_emp_class[, .(muni_id, top_q4_muni)],
        top_q4_muni := i.top_q4_muni, on = "muni_id"]

  n_share_mayor_na <- sum(is.na(panel$emp_share_muni_pre_mayor))
  n_share_gp_na    <- sum(is.na(panel$emp_share_muni_pre_gp))
  n_top_q4_na      <- sum(is.na(panel$top_q4_muni))
  cat(sprintf("    emp_share_muni_pre_mayor NA: %d (%.1f%%)\n",
              n_share_mayor_na, 100 * n_share_mayor_na / nrow(panel)))
  cat(sprintf("    emp_share_muni_pre_gp NA: %d (%.1f%%)\n",
              n_share_gp_na, 100 * n_share_gp_na / nrow(panel)))
  cat(sprintf("    top_q4_muni NA: %d %s\n",
              n_top_q4_na, if (n_top_q4_na == 0L) "PASS" else "WARN"))

  # Emit BASE and SPARSE files side-by-side. Downstream consumers read through
  # load_firm_panel() (scripts/R/_utils/load_firm_panel.R), which joins the two
  # on (firm_id, muni_id, year) with zero-fill for non-matched rows.
  bt_suffix   <- if (bt == "cycle_specific") "" else paste0("_", bt)
  bt_fst_path <- make_output_path(paste0("firm_panel_for_regs", bt_suffix, ".fst"))
  bt_inst_path <- make_output_path(paste0("firm_panel_for_regs", bt_suffix, "_instruments.fst"))

  if (!isTRUE(write_fst_atomic(panel, bt_fst_path, compress = 50))) {
    stop("Failed to write firm panel base fst output for baseline: ", bt)
  }
  base_size_mb <- file.size(bt_fst_path) / 1024^2

  if (!isTRUE(write_fst_atomic(inst_bt, bt_inst_path, compress = 50))) {
    stop("Failed to write firm panel sparse instruments fst output for baseline: ", bt)
  }
  inst_size_mb <- file.size(bt_inst_path) / 1024^2

  cat(sprintf("    Saved base:        %s (%.2f MB, %s rows, %d cols)\n",
              bt_fst_path, base_size_mb,
              format(nrow(panel), big.mark = ","), ncol(panel)))
  cat(sprintf("    Saved instruments: %s (%.2f MB, %s rows, %d cols)\n",
              bt_inst_path, inst_size_mb,
              format(nrow(inst_bt), big.mark = ","), ncol(inst_bt)))

  # Sparsity invariant (plan §3, §7). If this trips, the split format is
  # paying cost without the memory win — flag it loudly.
  if (nrow(inst_bt) >= nrow(panel)) {
    warning(sprintf(
      "Sparsity invariant broken for [%s]: sparse rows (%s) >= base rows (%s).",
      bt, format(nrow(inst_bt), big.mark = ","),
      format(nrow(panel), big.mark = ",")))
  }

  # Keep the last baseline's sparse slice in memory so Step 6 can run
  # instrument-column diagnostics without rejoining 14 GB onto the panel.
  if (bt == last_bt) {
    firm_panel_inst_last <- copy(inst_bt)
  }
  rm(inst_bt)

  # Strip per-baseline columns from `panel` except on the last iteration — Steps
  # 5–7 still need baseline_type, bl_n_employees, emp_share_* and top_q4_muni.
  # The 48 instrument columns are no longer attached to `panel` so they do not
  # appear in this cleanup list.
  if (bt != last_bt) {
    panel[, c("baseline_type", "bl_n_employees",
              "emp_share_muni_pre_mayor", "emp_share_muni_pre_gp",
              "top_q4_muni") := NULL]
    invisible(gc())
  }
}

firm_panel <- panel
rm(instruments, panel)
invisible(gc())

# Clean up temporary baseline employment files persisted in Step 3C.
for (bt_tmp in baseline_types) {
  p_tmp <- bl_emp_path(bt_tmp)
  if (file.exists(p_tmp)) unlink(p_tmp)
}

cat(sprintf("\n  Panel rows per baseline: %s\n",
            format(nrow(firm_panel), big.mark = ",")))

# ==============================================================================
# STEP 5: Employment coverage diagnostics
# ==============================================================================

cat("\nStep 5: Employment coverage diagnostics...\n")

n_total <- nrow(firm_panel)
n_pos_emp <- sum(firm_panel$n_employees > 0, na.rm = TRUE)
n_na_emp  <- sum(is.na(firm_panel$n_employees))
n_zero_emp <- sum(firm_panel$n_employees == 0, na.rm = TRUE)

cat(sprintf("  Total firm-muni-years: %s\n", format(n_total, big.mark = ",")))
cat(sprintf("  Positive n_employees: %s (%.1f%%)\n",
            format(n_pos_emp, big.mark = ","), 100 * n_pos_emp / n_total))
cat(sprintf("  Zero n_employees: %s (%.1f%%)\n",
            format(n_zero_emp, big.mark = ","), 100 * n_zero_emp / n_total))
cat(sprintf("  NA n_employees: %s (%.1f%%)\n",
            format(n_na_emp, big.mark = ","), 100 * n_na_emp / n_total))

# BNDES credit share going to firms with positive employment
cat(sprintf("  BNDES credit to firms with positive employment: %.1f%% of total\n",
            bndes_pos_emp_share))

# ==============================================================================
# STEP 6: Final validation
# ==============================================================================

cat("\nStep 6: Final validation...\n")

# log_bndes_fmt must be NA (not -Inf) when value == 0
n_neg_inf <- sum(is.infinite(firm_panel$log_bndes_fmt) & firm_panel$log_bndes_fmt < 0,
                 na.rm = TRUE)
cat(sprintf("  log_bndes_fmt -Inf count: %d (expect 0) %s\n",
            n_neg_inf, if (n_neg_inf == 0) "PASS" else "FAIL"))

# delta_log_bndes_fmt must be NA when either t or t-1 has zero BNDES
# (Already ensured by construction, but verify)
if (n_neg_inf > 0) {
  warning("log_bndes_fmt has -Inf values! This should not happen.")
}

# log_n_employees must be finite whenever defined
n_emp_neg_inf <- sum(is.infinite(firm_panel$log_n_employees) & firm_panel$log_n_employees < 0,
                     na.rm = TRUE)
cat(sprintf("  log_n_employees -Inf count: %d (expect 0) %s\n",
            n_emp_neg_inf, if (n_emp_neg_inf == 0) "PASS" else "FAIL"))

# emp_share_muni_rais must lie in [0, 1]
share_vals <- firm_panel$emp_share_muni_rais
share_vals <- share_vals[!is.na(share_vals)]
if (length(share_vals)) {
  share_min <- min(share_vals)
  share_max <- max(share_vals)
  share_bounds_ok <- share_min >= -1e-10 && share_max <= 1 + 1e-10
  cat(sprintf("  emp_share_muni_rais support: [%.6f, %.6f] %s\n",
              share_min, share_max, if (share_bounds_ok) "PASS" else "FAIL"))
} else {
  cat("  emp_share_muni_rais support: no non-missing observations\n")
}

# New pre-election share weights: no Inf, no negative, no new NAs in bl_n_employees
for (share_col in c("emp_share_muni_pre_mayor", "emp_share_muni_pre_gp")) {
  vals <- firm_panel[[share_col]]
  vals_finite <- vals[!is.na(vals)]
  if (length(vals_finite)) {
    n_inf  <- sum(is.infinite(vals_finite))
    n_neg  <- sum(vals_finite < -1e-10)
    n_na   <- sum(is.na(vals))
    ok <- n_inf == 0L && n_neg == 0L
    cat(sprintf("  %s: min=%.6f max=%.6f Inf=%d neg=%d NA=%d %s\n",
                share_col,
                min(vals_finite), max(vals_finite),
                n_inf, n_neg, n_na,
                if (ok) "PASS" else "FAIL"))
  } else {
    cat(sprintf("  %s: all NA\n", share_col))
  }
}

# top_q4_muni must be 0/1 with no NAs (for munis present in the panel)
top_q4_vals <- unique(firm_panel$top_q4_muni)
n_top_q4_na_final <- sum(is.na(firm_panel$top_q4_muni))
cat(sprintf("  top_q4_muni values: {%s} NA=%d %s\n",
            paste(sort(top_q4_vals[!is.na(top_q4_vals)]), collapse = ","),
            n_top_q4_na_final,
            if (n_top_q4_na_final == 0L && all(top_q4_vals[!is.na(top_q4_vals)] %in% 0:1))
              "PASS" else "WARN"))

# has_bndes_fmt must be 0 or 1
has_vals <- unique(firm_panel$has_bndes_fmt)
cat(sprintf("  has_bndes_fmt values: {%s} %s\n",
            paste(sort(has_vals), collapse = ", "),
            if (all(has_vals %in% c(0L, 1L))) "PASS" else "FAIL"))

# delta_has_bndes_fmt must be in {-1, 0, 1}
delta_has_vals <- unique(na.omit(firm_panel$delta_has_bndes_fmt))
cat(sprintf("  delta_has_bndes_fmt values: {%s} %s\n",
            paste(sort(delta_has_vals), collapse = ", "),
            if (all(delta_has_vals %in% c(-1L, 0L, 1L))) "PASS" else "FAIL"))

# Instrument support bounds
# Share-based: FA in [0,1], dFA in [-1,1]
# Binary (_binary_): wider bounds since sum_p tilde_omega can exceed 1
#
# Instruments are now stored in the sparse companion (firm_panel_inst_last).
# The full joined panel = sparse rows ∪ zero-filled non-matched rows, so
#   min_full = min(min(sparse), 0),  max_full = max(max(sparse), 0).
# That identity lets us compute bounds without rejoining 14 GB onto `panel`.
cat("\n  Instrument support bounds:\n")
bounds_from_sparse <- function(ic) {
  v <- firm_panel_inst_last[[ic]]
  list(mn = min(c(min(v, na.rm = TRUE), 0)),
       mx = max(c(max(v, na.rm = TRUE), 0)))
}
for (ic in fa_cols) {
  b <- bounds_from_sparse(ic)
  is_binary <- grepl("_binary_", ic)
  ok <- if (is_binary) b$mn >= -1e-10 else b$mn >= -1e-10 && b$mx <= 1 + 1e-10
  cat(sprintf("    %s: [%.6f, %.6f] %s\n", ic, b$mn, b$mx, if (ok) "PASS" else "FAIL"))
}
for (ic in dfa_cols) {
  b <- bounds_from_sparse(ic)
  is_binary <- grepl("_binary_", ic)
  ok <- if (is_binary) TRUE else b$mn >= -1 - 1e-10 && b$mx <= 1 + 1e-10
  cat(sprintf("    %s: [%.6f, %.6f] %s\n", ic, b$mn, b$mx, if (ok) "PASS" else "FAIL"))
}

# Coverage stats (only the last baseline in memory — other baselines already saved)
bt_in_mem <- firm_panel$baseline_type[1]
cat(sprintf("\n  Coverage stats for [%s] baseline (in memory):\n", bt_in_mem))
n_rows_bt <- nrow(firm_panel)
coverage_stats <- data.table(
  baseline_type       = bt_in_mem,
  n_rows              = n_rows_bt,
  n_firms             = uniqueN(firm_panel$firm_id),
  n_munis             = uniqueN(firm_panel$muni_id),
  n_years             = uniqueN(firm_panel$year),
  n_has_bndes         = sum(firm_panel$has_bndes_fmt),
  frac_has_bndes      = mean(firm_panel$has_bndes_fmt),
  frac_pos_employment = mean(firm_panel$n_employees > 0, na.rm = TRUE),
  n_delta_ext         = sum(!is.na(firm_panel$delta_has_bndes_fmt)),
  n_delta_int         = sum(!is.na(firm_panel$delta_log_bndes_fmt)),
  n_log_bndes         = sum(!is.na(firm_panel$log_bndes_fmt)),
  n_log_employment    = sum(!is.na(firm_panel$log_n_employees)),
  n_emp_share         = sum(!is.na(firm_panel$emp_share_muni_rais)),
  n_delta_emp_log     = sum(!is.na(firm_panel$delta_log_n_employees)),
  n_delta_emp_share   = sum(!is.na(firm_panel$delta_emp_share_muni_rais)),
  # Counted on the sparse companion: any row absent from sparse has zeros in
  # every FA/dFA column and cannot contribute to the numerator.
  frac_nonzero_FA           = count_nonzero_rows(firm_panel_inst_last, fa_cols) / n_rows_bt,
  frac_nonzero_dFA          = count_nonzero_rows(firm_panel_inst_last, dfa_cols) / n_rows_bt,
  n_emp_share_mayor         = sum(!is.na(firm_panel$emp_share_muni_pre_mayor)),
  n_emp_share_gp            = sum(!is.na(firm_panel$emp_share_muni_pre_gp)),
  n_top_q4_muni             = sum(!is.na(firm_panel$top_q4_muni)),
  frac_top_q4_muni          = mean(firm_panel$top_q4_muni, na.rm = TRUE)
)

cat(sprintf("    %s rows, %d firms, %d munis\n",
            format(coverage_stats$n_rows, big.mark = ","),
            coverage_stats$n_firms,
            coverage_stats$n_munis))
cat(sprintf("    Extensive: %d with BNDES, %d non-NA deltas\n",
            coverage_stats$n_has_bndes,
            coverage_stats$n_delta_ext))
cat(sprintf("    Intensive: %d with log(BNDES), %d non-NA deltas\n",
            coverage_stats$n_log_bndes,
            coverage_stats$n_delta_int))
cat(sprintf("    Employment: %d with log employment, %d with employment share\n",
            coverage_stats$n_log_employment,
            coverage_stats$n_emp_share))
cat(sprintf("    Employment changes: %d log employment deltas, %d employment-share deltas\n",
            coverage_stats$n_delta_emp_log,
            coverage_stats$n_delta_emp_share))
cat(sprintf("    Pre-election share weights: %d mayor, %d gp\n",
            coverage_stats$n_emp_share_mayor,
            coverage_stats$n_emp_share_gp))
cat(sprintf("    top_q4_muni: %d classified (%.1f%% in Q4)\n",
            coverage_stats$n_top_q4_muni,
            100 * coverage_stats$frac_top_q4_muni))

# ==============================================================================
# STEP 7: Save
# ==============================================================================

cat("\nStep 7: Saving summary...\n")

# Panel files already saved per-baseline in Step 4.
# Save summary CSV.
fwrite(coverage_stats, summary_path)

cat(sprintf("  Saved %s\n", summary_path))
cat("  Panel files saved per baseline in Step 4 (base + sparse instruments):\n")
for (bt in baseline_types) {
  bt_suffix   <- if (bt == "cycle_specific") "" else paste0("_", bt)
  bt_fst_path <- make_output_path(paste0("firm_panel_for_regs", bt_suffix, ".fst"))
  bt_inst_path <- make_output_path(paste0("firm_panel_for_regs", bt_suffix, "_instruments.fst"))
  if (file.exists(bt_fst_path)) {
    cat(sprintf("    base:        %s (%.2f MB)\n",
                bt_fst_path, file.size(bt_fst_path) / 1024^2))
  }
  if (file.exists(bt_inst_path)) {
    cat(sprintf("    instruments: %s (%.2f MB)\n",
                bt_inst_path, file.size(bt_inst_path) / 1024^2))
  }
}

cat("\n==============================================================================\n")
cat("Firm Regression Panel Complete\n")
cat("==============================================================================\n")
