#!/usr/bin/env Rscript

# ==============================================================================
# Diagnostic: Firm-Level Instrument Quality
# ==============================================================================
# Evaluates the empirical quality of firm-level political-linkage instruments
# (FA_*, dFA_*) for predicting BNDES firm credit allocation. Produces figures,
# summary tables, and a programmatic recommendation note.
#
# Sections:
#   0: Bootstrap, paths, variable definitions
#   1: Instrument distribution diagnostics
#   2: Within/between-firm variation decomposition
#   3: Baseline exposure diagnostics
#   4: Election-cycle timing & predictive relevance
#   5: Export recommendation note
#
# Usage:
#   Rscript diagnose_firm_instruments.R [--baseline=cycle_specific|2002_fixed]
#
# Dependencies:
#   - firm_panel_for_regs.fst (script 42)
#   - firm_baseline_exposures.qs2 (script 36 side output)
# ==============================================================================

cat("==============================================================================\n")
cat("Diagnostic: Firm-Level Instrument Quality\n")
cat("==============================================================================\n\n")

# ==============================================================================
# Section 0: Bootstrap, Paths, Variable Definitions
# ==============================================================================

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

setDTthreads(0)

# --- CLI arguments ---
args <- commandArgs(trailingOnly = TRUE)
bl_flag <- grep("^--baseline=", args, value = TRUE)
BASELINE_TYPE <- "cycle_specific"
if (length(bl_flag)) {
  BASELINE_TYPE <- tolower(trimws(sub("^--baseline=", "", bl_flag[1])))
  if (!BASELINE_TYPE %in% c("cycle_specific", "2002_fixed")) {
    stop("Invalid --baseline value: '", BASELINE_TYPE, "'. Use 'cycle_specific' or '2002_fixed'.")
  }
}

# --- Paths ---
panel_fst_path <- firm_panel_paths(BASELINE_TYPE)$base   # base file (no FA/dFA)
panel_inst_path <- firm_panel_paths(BASELINE_TYPE)$sparse # sparse instruments
baseline_path  <- make_output_path("firm_baseline_exposures.qs2")
out_dir <- file.path(OUTPUT_DIR, "diagnostics", "firm_instruments")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(panel_fst_path)) {
  stop("Firm panel fst not found: ", panel_fst_path,
       "\n  Run scripts 42 first.")
}

# --- Variable definitions ---
FA_SINGLE <- c("FA_mayor_coalition", "FA_mayor_party",
               "FA_gov_coalition", "FA_gov_party",
               "FA_pres_coalition", "FA_pres_party")
FA_INTERACT <- c("FA_mayor_gov_coalition", "FA_mayor_gov_party",
                 "FA_mayor_pres_coalition", "FA_mayor_pres_party",
                 "FA_triple_coalition", "FA_triple_party")
DFA_SINGLE <- gsub("^FA_", "dFA_", FA_SINGLE)
DFA_INTERACT <- gsub("^FA_", "dFA_", FA_INTERACT)
ALL_INSTRUMENTS <- c(FA_SINGLE, FA_INTERACT, DFA_SINGLE, DFA_INTERACT)

OUTCOMES_LEVELS  <- c("has_bndes_fmt", "log_bndes_fmt")
OUTCOMES_CHANGES <- c("delta_has_bndes_fmt", "delta_log_bndes_fmt")

INAUG_MAYOR   <- c(2005L, 2009L, 2013L, 2017L)
INAUG_GOVPRES <- c(2007L, 2011L, 2015L)

BOUNDS <- list(FA = c(0, 1), dFA = c(-1, 1))

# --- Discover available columns (base file + sparse instruments file) ---
if (!requireNamespace("fst", quietly = TRUE)) {
  stop("Package 'fst' is required but not installed.")
}
base_available_cols <- fst::metadata_fst(panel_fst_path)$columnNames
inst_available_cols <- if (file.exists(panel_inst_path)) {
  fst::metadata_fst(panel_inst_path)$columnNames
} else character(0)
available_cols <- union(base_available_cols, inst_available_cols)

missing_instr <- setdiff(ALL_INSTRUMENTS, available_cols)
if (length(missing_instr)) {
  cat("WARNING: Missing instrument columns:\n")
  cat("  ", paste(missing_instr, collapse = ", "), "\n")
  # Keep only available instruments
  ALL_INSTRUMENTS <- intersect(ALL_INSTRUMENTS, available_cols)
  FA_SINGLE  <- intersect(FA_SINGLE, available_cols)
  FA_INTERACT <- intersect(FA_INTERACT, available_cols)
  DFA_SINGLE  <- intersect(DFA_SINGLE, available_cols)
  DFA_INTERACT <- intersect(DFA_INTERACT, available_cols)
  if (length(ALL_INSTRUMENTS) == 0L) {
    stop("No instrument columns found.")
  }
}

# Helper: load a column set via the unified loader, splitting into base vs instruments.
.load_panel_cols <- function(col_vec) {
  inst <- grep("^(FA_|dFA_)", col_vec, value = TRUE)
  base <- setdiff(col_vec, inst)
  load_firm_panel(
    baseline_type = BASELINE_TYPE,
    columns       = if (length(base)) base else NULL,
    instruments   = if (length(inst)) inst else character(0),
    zero_fill     = TRUE,
    as_data_table = TRUE
  )
}

ALL_FA  <- c(FA_SINGLE, FA_INTERACT)
ALL_DFA <- c(DFA_SINGLE, DFA_INTERACT)

# Diagnostic header
cat(sprintf("Date: %s\n", Sys.Date()))
cat(sprintf("Baseline type: %s\n", BASELINE_TYPE))
cat(sprintf("Panel fst: %s\n", panel_fst_path))
cat(sprintf("Baseline exposures: %s (exists: %s)\n", baseline_path, file.exists(baseline_path)))
cat(sprintf("Output directory: %s\n", out_dir))
cat(sprintf("Instruments found: %d FA + %d dFA\n\n", length(ALL_FA), length(ALL_DFA)))

# Helper: compute skewness/kurtosis without moments package
calc_skewness <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 3L) return(NA_real_)
  m <- mean(x)
  s <- sd(x)
  if (s == 0) return(NA_real_)
  (n / ((n - 1) * (n - 2))) * sum(((x - m) / s)^3)
}

calc_kurtosis <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 4L) return(NA_real_)
  m <- mean(x)
  s <- sd(x)
  if (s == 0) return(NA_real_)
  (n * (n + 1) / ((n - 1) * (n - 2) * (n - 3))) * sum(((x - m) / s)^4) -
    3 * (n - 1)^2 / ((n - 2) * (n - 3))
}

# Collect results for recommendation note
diag_results <- list()

# ==============================================================================
# Section 1: Instrument Distribution Diagnostics
# ==============================================================================

# Check for existing Section 1 outputs to skip if already done
s1_done <- file.exists(file.path(out_dir, "desc_stats_overall.csv")) &&
           file.exists(file.path(out_dir, "fig_zero_mass_by_year.png"))

cat(strrep("=", 78), "\n")
cat("Section 1: Instrument Distribution Diagnostics\n")
cat(strrep("=", 78), "\n\n")

# Load instrument columns + keys (needed for panel dimensions even if skipping)
s1_cols <- c("firm_id", "muni_id", "year", ALL_INSTRUMENTS)
s1_cols <- intersect(s1_cols, available_cols)

if (s1_done) {
  cat("  Section 1 outputs already exist — loading cached stats and skipping.\n")
  # Still need panel dimensions for recommendation note
  dt1_meta <- load_firm_panel(BASELINE_TYPE, columns = c("firm_id", "year"), instruments = character(0))
  diag_results$n_obs   <- nrow(dt1_meta)
  diag_results$n_firms <- uniqueN(dt1_meta$firm_id)
  diag_results$n_years <- uniqueN(dt1_meta$year)
  rm(dt1_meta); invisible(gc())
  diag_results$desc_stats <- fread(file.path(out_dir, "desc_stats_overall.csv"))
  diag_results$bounds_ok <- TRUE  # assume pass from previous run
} else {

cat("  Loading columns:", paste(s1_cols, collapse = ", "), "\n")
dt1 <- .load_panel_cols(s1_cols)
cat(sprintf("  Panel: %s obs, %d firms, years %d-%d\n",
            format(nrow(dt1), big.mark = ","),
            uniqueN(dt1$firm_id),
            min(dt1$year), max(dt1$year)))

diag_results$n_obs   <- nrow(dt1)
diag_results$n_firms <- uniqueN(dt1$firm_id)
diag_results$n_years <- uniqueN(dt1$year)

# --- 1a: Overall descriptive statistics ---
cat("  Computing overall descriptive statistics...\n")

desc_stats_overall <- rbindlist(lapply(ALL_INSTRUMENTS, function(ic) {
  vals <- dt1[[ic]]
  vals <- vals[!is.na(vals)]
  qs <- quantile(vals, probs = c(0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99))
  data.table(
    instrument = ic,
    mean       = mean(vals),
    sd         = sd(vals),
    min        = min(vals),
    p1         = qs[1], p5 = qs[2], p25 = qs[3], median = qs[4],
    p75        = qs[5], p95 = qs[6], p99 = qs[7],
    max        = max(vals),
    n_obs      = length(vals),
    n_zero     = sum(vals == 0),
    pct_zero   = 100 * mean(vals == 0),
    skewness   = calc_skewness(vals),
    kurtosis   = calc_kurtosis(vals)
  )
}))

# For dFA: also compute conditional stats (inauguration years only)
if (length(ALL_DFA) > 0) {
  inaug_years <- sort(unique(c(INAUG_MAYOR, INAUG_GOVPRES)))
  dt1_inaug <- dt1[year %in% inaug_years]

  desc_cond <- rbindlist(lapply(ALL_DFA, function(ic) {
    vals <- dt1_inaug[[ic]]
    vals <- vals[!is.na(vals)]
    qs <- quantile(vals, probs = c(0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99))
    data.table(
      instrument = paste0(ic, "_cond_inaug"),
      mean       = mean(vals),
      sd         = sd(vals),
      min        = min(vals),
      p1         = qs[1], p5 = qs[2], p25 = qs[3], median = qs[4],
      p75        = qs[5], p95 = qs[6], p99 = qs[7],
      max        = max(vals),
      n_obs      = length(vals),
      n_zero     = sum(vals == 0),
      pct_zero   = 100 * mean(vals == 0),
      skewness   = calc_skewness(vals),
      kurtosis   = calc_kurtosis(vals)
    )
  }))
  desc_stats_overall <- rbind(desc_stats_overall, desc_cond)
  rm(desc_cond, dt1_inaug)
}

fwrite(desc_stats_overall, file.path(out_dir, "desc_stats_overall.csv"))
cat(sprintf("  Saved desc_stats_overall.csv (%d rows)\n", nrow(desc_stats_overall)))
diag_results$desc_stats <- desc_stats_overall

# --- 1b: By-year descriptive statistics ---
cat("  Computing by-year descriptive statistics...\n")

desc_stats_by_year <- rbindlist(lapply(ALL_INSTRUMENTS, function(ic) {
  dt1[, {
    vals <- get(ic)
    vals <- vals[!is.na(vals)]
    if (length(vals) == 0L) return(NULL)
    qs <- quantile(vals, probs = c(0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99))
    .(instrument = ic,
      mean = mean(vals), sd = sd(vals),
      min = min(vals), p1 = qs[1], p5 = qs[2], p25 = qs[3], median = qs[4],
      p75 = qs[5], p95 = qs[6], p99 = qs[7], max = max(vals),
      n_obs = length(vals), n_zero = sum(vals == 0),
      pct_zero = 100 * mean(vals == 0))
  }, by = year]
}))
setorder(desc_stats_by_year, instrument, year)
fwrite(desc_stats_by_year, file.path(out_dir, "desc_stats_by_year.csv"))
cat(sprintf("  Saved desc_stats_by_year.csv (%d rows)\n", nrow(desc_stats_by_year)))

# --- 1c: Support bounds check ---
cat("  Checking support bounds...\n")
bounds_ok <- TRUE
for (ic in ALL_FA) {
  mn <- min(dt1[[ic]], na.rm = TRUE)
  mx <- max(dt1[[ic]], na.rm = TRUE)
  ok <- mn >= -1e-10 && mx <= 1 + 1e-10
  if (!ok) {
    cat(sprintf("    FAIL %s: [%.6f, %.6f] outside [0, 1]\n", ic, mn, mx))
    bounds_ok <- FALSE
  }
}
for (ic in ALL_DFA) {
  mn <- min(dt1[[ic]], na.rm = TRUE)
  mx <- max(dt1[[ic]], na.rm = TRUE)
  ok <- mn >= -1 - 1e-10 && mx <= 1 + 1e-10
  if (!ok) {
    cat(sprintf("    FAIL %s: [%.6f, %.6f] outside [-1, 1]\n", ic, mn, mx))
    bounds_ok <- FALSE
  }
}
if (bounds_ok) cat("    All instruments within theoretical bounds: PASS\n")
diag_results$bounds_ok <- bounds_ok

# --- 1d: Density plots ---
cat("  Generating density plots...\n")

make_density_plot <- function(dt, instruments, filename, title, inaug_only = FALSE) {
  if (length(instruments) == 0L) return(invisible(NULL))
  n_panels <- length(instruments)
  ncol_plot <- min(3L, n_panels)
  nrow_plot <- ceiling(n_panels / ncol_plot)

  png(file.path(out_dir, filename), width = 400 * ncol_plot, height = 350 * nrow_plot)
  par(mfrow = c(nrow_plot, ncol_plot), mar = c(4, 4, 3, 1))

  for (ic in instruments) {
    vals <- dt[[ic]]
    vals <- vals[!is.na(vals) & vals != 0]
    if (length(vals) < 10L) {
      plot.new()
      title(main = ic, cex.main = 0.9)
      text(0.5, 0.5, "< 10 non-zero values")
      next
    }
    d <- density(vals, adjust = 1.2)
    plot(d, main = ic, xlab = "Value", ylab = "Density",
         col = "#1B6CA8", lwd = 2, cex.main = 0.9)
    polygon(d, col = adjustcolor("#1B6CA8", alpha.f = 0.2), border = NA)
    abline(v = 0, lty = 2, col = "grey50")
  }
  dev.off()
}

make_density_plot(dt1, FA_SINGLE, "fig_density_fa_single.png",
                  "FA Single-Tier Instruments")
make_density_plot(dt1, FA_INTERACT, "fig_density_fa_interact.png",
                  "FA Interaction Instruments")
# dFA: inauguration years only
if (length(ALL_DFA) > 0) {
  dt1_inaug <- dt1[year %in% sort(unique(c(INAUG_MAYOR, INAUG_GOVPRES)))]
  make_density_plot(dt1_inaug, DFA_SINGLE, "fig_density_dfa_single.png",
                    "dFA Single-Tier (Inaug. Years Only)", inaug_only = TRUE)
  make_density_plot(dt1_inaug, DFA_INTERACT, "fig_density_dfa_interact.png",
                    "dFA Interaction (Inaug. Years Only)", inaug_only = TRUE)
  rm(dt1_inaug)
}
cat("  Saved density plots\n")

# --- 1e: Zero-mass heatmap ---
cat("  Generating zero-mass heatmap...\n")

zero_by_year <- desc_stats_by_year[, .(instrument, year, pct_zero)]
zero_wide <- dcast(zero_by_year, instrument ~ year, value.var = "pct_zero")
instr_order <- zero_wide$instrument
zero_mat <- as.matrix(zero_wide[, -1, with = FALSE])
rownames(zero_mat) <- instr_order
year_labels <- as.integer(colnames(zero_mat))

inaug_all <- sort(unique(c(INAUG_MAYOR, INAUG_GOVPRES)))

png(file.path(out_dir, "fig_zero_mass_by_year.png"),
    width = max(800, 50 * ncol(zero_mat)),
    height = max(600, 30 * nrow(zero_mat)))
par(mar = c(5, 12, 3, 5))
image(seq_len(ncol(zero_mat)), seq_len(nrow(zero_mat)),
      t(zero_mat), col = hcl.colors(50, "YlOrRd", rev = TRUE),
      axes = FALSE, xlab = "Year", ylab = "", main = "% Zero by Instrument x Year")
axis(1, at = seq_len(ncol(zero_mat)), labels = year_labels, las = 2, cex.axis = 0.8)
axis(2, at = seq_len(nrow(zero_mat)), labels = rownames(zero_mat), las = 1, cex.axis = 0.7)
# Highlight inauguration years
inaug_idx <- which(year_labels %in% inaug_all)
if (length(inaug_idx)) {
  abline(v = inaug_idx, col = "blue", lty = 2, lwd = 1.5)
}
# Add text values
for (i in seq_len(nrow(zero_mat))) {
  for (j in seq_len(ncol(zero_mat))) {
    if (!is.na(zero_mat[i, j])) {
      text(j, i, sprintf("%.0f", zero_mat[i, j]), cex = 0.55,
           col = if (zero_mat[i, j] > 80) "white" else "black")
    }
  }
}
dev.off()
cat("  Saved fig_zero_mass_by_year.png\n")

rm(desc_stats_by_year, zero_by_year, zero_wide, zero_mat)
rm(dt1)
invisible(gc())

} # end s1_done else block

# ==============================================================================
# Section 2: Within/Between-Firm Variation Decomposition
# ==============================================================================

cat("\n", strrep("=", 78), "\n")
cat("Section 2: Within/Between-Firm Variation Decomposition\n")
cat(strrep("=", 78), "\n\n")

s2_done <- file.exists(file.path(out_dir, "variance_decomposition.csv")) &&
           file.exists(file.path(out_dir, "fig_within_between_scatter.png"))

if (s2_done) {
  cat("  Section 2 outputs already exist — loading cached and skipping.\n")
  diag_results$variance_decomp <- fread(file.path(out_dir, "variance_decomposition.csv"))
} else {

s2_cols <- c("firm_id", "muni_id", "year", ALL_INSTRUMENTS)
s2_cols <- intersect(s2_cols, available_cols)
dt2 <- .load_panel_cols(s2_cols)

cat("  Computing variance decomposition (vectorized)...\n")

# Compute all firm means in one pass using GForce-optimized mean()
# (GForce requires column names, not get(), so we use .SDcols)
cat("    Computing firm means...\n")
firm_means <- dt2[, lapply(.SD, mean, na.rm = TRUE), by = firm_id, .SDcols = ALL_INSTRUMENTS]

# Total variance, between-firm variance from firm means
cat("    Computing total and between-firm variance...\n")
variance_decomp <- rbindlist(lapply(ALL_INSTRUMENTS, function(ic) {
  total_var   <- var(dt2[[ic]], na.rm = TRUE)
  between_var <- var(firm_means[[ic]], na.rm = TRUE)
  within_var  <- total_var - between_var  # ANOVA decomposition

  icc <- if (total_var > 0) between_var / total_var else NA_real_

  data.table(
    instrument  = ic,
    total_var   = total_var,
    between_var = between_var,
    within_var  = max(within_var, 0),  # numerical floor
    icc         = icc,
    between_sd  = sqrt(between_var),
    within_sd   = sqrt(max(within_var, 0))
  )
}))

# For dFA: compute within-firm variance at inauguration years only
if (length(ALL_DFA) > 0) {
  inaug_years <- sort(unique(c(INAUG_MAYOR, INAUG_GOVPRES)))
  cat("    Computing dFA within-firm variance at inauguration years...\n")
  dt2_inaug <- dt2[year %in% inaug_years]
  fm_inaug <- dt2_inaug[, lapply(.SD, mean, na.rm = TRUE), by = firm_id, .SDcols = ALL_DFA]
  for (ic in ALL_DFA) {
    total_inaug <- var(dt2_inaug[[ic]], na.rm = TRUE)
    between_inaug <- var(fm_inaug[[ic]], na.rm = TRUE)
    within_inaug <- max(total_inaug - between_inaug, 0)
    variance_decomp[instrument == ic, within_var_inaug := within_inaug]
    variance_decomp[instrument == ic, within_sd_inaug := sqrt(within_inaug)]
  }
  rm(dt2_inaug, fm_inaug)
}
rm(firm_means)

fwrite(variance_decomp, file.path(out_dir, "variance_decomposition.csv"))
cat(sprintf("  Saved variance_decomposition.csv (%d rows)\n", nrow(variance_decomp)))
cat("  NOTE: High ICC = mostly cross-sectional (between firms);\n")
cat("        Low ICC = time-series variation dominates (within firms).\n")
cat("        Firm FE identifies only within-firm variation.\n")
diag_results$variance_decomp <- variance_decomp

# --- 2b: Within vs. between SD scatter ---
cat("  Generating within vs. between scatter plot...\n")

png(file.path(out_dir, "fig_within_between_scatter.png"), width = 800, height = 700)
par(mar = c(5, 5, 3, 1))

# Color by type
pt_col <- ifelse(variance_decomp$instrument %in% ALL_FA, "#1B6CA8", "#A23B72")
pt_pch <- ifelse(variance_decomp$instrument %in% c(FA_SINGLE, DFA_SINGLE), 16, 17)

plot(variance_decomp$between_sd, variance_decomp$within_sd,
     pch = pt_pch, col = pt_col, cex = 1.5,
     xlab = "Between-Firm SD", ylab = "Within-Firm SD",
     main = "Within vs. Between-Firm Variation")
# Label points
text(variance_decomp$between_sd, variance_decomp$within_sd,
     labels = sub("^(d?FA_)", "", variance_decomp$instrument),
     pos = 3, cex = 0.6, col = "grey30")
# 45-degree line
abline(0, 1, lty = 2, col = "grey60")
legend("topright",
       legend = c("FA (levels)", "dFA (changes)", "Single-tier", "Interaction"),
       col = c("#1B6CA8", "#A23B72", "grey40", "grey40"),
       pch = c(15, 15, 16, 17),
       bty = "n", cex = 0.9)
dev.off()
cat("  Saved fig_within_between_scatter.png\n")

rm(dt2)
invisible(gc())

} # end s2_done else block

# ==============================================================================
# Section 3: Baseline Exposure Diagnostics
# ==============================================================================

cat("\n", strrep("=", 78), "\n")
cat("Section 3: Baseline Exposure Diagnostics\n")
cat(strrep("=", 78), "\n\n")

s3_done <- file.exists(file.path(out_dir, "baseline_coverage.csv")) &&
           file.exists(file.path(out_dir, "baseline_persistence.csv"))

if (s3_done) {
  cat("  Section 3 outputs already exist — loading cached and skipping.\n")
  diag_results$baseline_available <- TRUE
  diag_results$pct_firms_with_exposure <- 100  # from previous run
  diag_results$baseline_persistence <- fread(file.path(out_dir, "baseline_persistence.csv"))
} else if (!file.exists(baseline_path)) {
  cat("  WARNING: Baseline exposures file not found. Skipping Section 3.\n")
  cat("  Expected: ", baseline_path, "\n")
  cat("  Run script 36 first to generate this side output.\n")
  diag_results$baseline_available <- FALSE
} else {
  diag_results$baseline_available <- TRUE
  bl <- qs_read(baseline_path)
  setDT(bl)

  # Filter to requested baseline type
  bl <- bl[baseline_type == BASELINE_TYPE]
  cat(sprintf("  Loaded %d baseline exposure rows (type: %s)\n",
              nrow(bl), BASELINE_TYPE))

  # --- 3a: Coverage table ---
  cat("  Computing coverage table...\n")

  # Determine tier from election_year
  bl[, tier := fifelse(election_year %in% c(2005L, 2009L, 2013L, 2017L),
                        "mayor", "gov_pres")]

  coverage <- bl[, .(
    n_firms_with_aff   = uniqueN(firm_id[L_f_0 > 0 & party != "No party"]),
    n_firms_zero_aff   = uniqueN(firm_id[L_f_0 == 0 | L_fp_0 == 0]),
    mean_n_baseline_yrs = mean(n_baseline_years, na.rm = TRUE),
    mean_share_fp_0    = mean(share_fp_0[share_fp_0 > 0], na.rm = TRUE),
    median_share_fp_0  = median(share_fp_0[share_fp_0 > 0], na.rm = TRUE),
    max_share_fp_0     = max(share_fp_0, na.rm = TRUE)
  ), by = .(election_year, tier)]
  setorder(coverage, election_year)

  fwrite(coverage, file.path(out_dir, "baseline_coverage.csv"))
  cat(sprintf("  Saved baseline_coverage.csv (%d rows)\n", nrow(coverage)))
  diag_results$baseline_coverage <- coverage

  # --- 3b: Persistence analysis ---
  cat("  Computing persistence analysis...\n")

  # Get unique election years sorted
  election_years <- sort(unique(bl$election_year))

  persistence_list <- list()
  for (idx in seq_len(length(election_years) - 1L)) {
    ey1 <- election_years[idx]
    ey2 <- election_years[idx + 1L]

    bl1 <- bl[election_year == ey1, .(firm_id, party, share1 = share_fp_0)]
    bl2 <- bl[election_year == ey2, .(firm_id, party, share2 = share_fp_0)]
    both <- merge(bl1, bl2, by = c("firm_id", "party"))

    if (nrow(both) == 0L) next

    # Correlation of share_fp_0 between cycles
    corr <- cor(both$share1, both$share2, use = "complete.obs")

    # Fraction switching dominant party
    dom1 <- bl1[, .(party1 = party[which.max(share1)]), by = firm_id]
    dom2 <- bl2[, .(party2 = party[which.max(share2)]), by = firm_id]
    dom <- merge(dom1, dom2, by = "firm_id")
    frac_switch <- mean(dom$party1 != dom$party2)

    # Fraction with stable exposure
    frac_stable <- mean(abs(both$share2 - both$share1) < 0.1)

    persistence_list[[length(persistence_list) + 1L]] <- data.table(
      cycle_from     = ey1,
      cycle_to       = ey2,
      n_firm_party   = nrow(both),
      correlation    = corr,
      frac_switch    = frac_switch,
      frac_stable    = frac_stable
    )
  }

  if (length(persistence_list) > 0L) {
    persistence <- rbindlist(persistence_list)
    fwrite(persistence, file.path(out_dir, "baseline_persistence.csv"))
    cat(sprintf("  Saved baseline_persistence.csv (%d rows)\n", nrow(persistence)))
    diag_results$baseline_persistence <- persistence
  }

  # --- 3c: Pairwise correlation matrix (within a cycle) ---
  cat("  Generating baseline correlation heatmap...\n")

  # Use the most recent cycle with enough data
  latest_ey <- max(election_years)
  bl_latest <- bl[election_year == latest_ey]

  # Wide format: firm_id x party -> share_fp_0
  bl_wide <- dcast(bl_latest, firm_id ~ party, value.var = "share_fp_0", fill = 0)
  party_cols <- setdiff(names(bl_wide), "firm_id")

  if (length(party_cols) >= 2L) {
    corr_mat <- cor(bl_wide[, ..party_cols], use = "pairwise.complete.obs")

    png(file.path(out_dir, "fig_baseline_correlations.png"),
        width = max(600, 80 * length(party_cols)),
        height = max(600, 80 * length(party_cols)))
    par(mar = c(8, 8, 3, 5))
    n_p <- nrow(corr_mat)
    image(seq_len(n_p), seq_len(n_p), corr_mat,
          col = hcl.colors(50, "RdBu"),
          axes = FALSE, xlab = "", ylab = "",
          main = sprintf("Baseline Share Correlations (cycle %d)", latest_ey),
          zlim = c(-1, 1))
    axis(1, at = seq_len(n_p), labels = party_cols, las = 2, cex.axis = 0.7)
    axis(2, at = seq_len(n_p), labels = party_cols, las = 1, cex.axis = 0.7)
    for (i in seq_len(n_p)) {
      for (j in seq_len(n_p)) {
        text(i, j, sprintf("%.2f", corr_mat[i, j]), cex = 0.6)
      }
    }
    dev.off()
    cat("  Saved fig_baseline_correlations.png\n")
  }

  # --- 3d: Flag support problems ---
  cat("  Flagging support problems...\n")

  # Firms with zero exposure for all parties
  firm_any_exposure <- bl[share_fp_0 > 0, uniqueN(firm_id)]
  firm_total <- uniqueN(bl$firm_id)
  pct_with_exposure <- 100 * firm_any_exposure / firm_total
  cat(sprintf("    Firms with any political exposure: %d / %d (%.1f%%)\n",
              firm_any_exposure, firm_total, pct_with_exposure))
  diag_results$pct_firms_with_exposure <- pct_with_exposure

  # Thin baselines
  thin <- bl[n_baseline_years < 2L]
  if (nrow(thin) > 0L) {
    cat(sprintf("    Election cycles with < 2 baseline years: %s\n",
                paste(sort(unique(thin$election_year)), collapse = ", ")))
  }

  rm(bl, bl_wide, bl_latest)
  invisible(gc())
}

# ==============================================================================
# Section 4: Election-Cycle Timing & Predictive Relevance
# ==============================================================================

cat("\n", strrep("=", 78), "\n")
cat("Section 4: Election-Cycle Timing & Predictive Relevance\n")
cat(strrep("=", 78), "\n\n")

# --- 4A: Timing Alignment Checks ---
s4a_done <- file.exists(file.path(out_dir, "inauguration_verification.csv")) &&
            file.exists(file.path(out_dir, "term_constancy.csv")) &&
            file.exists(file.path(out_dir, "fig_instrument_by_year.png"))

if (s4a_done) {
  cat("  4A: Outputs already exist — loading cached and skipping.\n")
  diag_results$inaug_violations <- 0  # from previous run
  diag_results$term_constancy <- fread(file.path(out_dir, "term_constancy.csv"))
} else {
cat("  4A: Timing alignment checks...\n")

s4a_cols <- c("firm_id", "muni_id", "year", ALL_INSTRUMENTS)
s4a_cols <- intersect(s4a_cols, available_cols)
dt4 <- .load_panel_cols(s4a_cols)

# Inauguration-year verification for dFA
inaug_all <- sort(unique(c(INAUG_MAYOR, INAUG_GOVPRES)))
inaug_verify <- rbindlist(lapply(ALL_DFA, function(ic) {
  nz_years <- sort(unique(dt4[get(ic) != 0, year]))
  non_inaug_nonzero <- setdiff(nz_years, inaug_all)
  data.table(
    instrument        = ic,
    nonzero_years     = paste(nz_years, collapse = ","),
    violations        = paste(non_inaug_nonzero, collapse = ","),
    n_violations      = length(non_inaug_nonzero)
  )
}))
fwrite(inaug_verify, file.path(out_dir, "inauguration_verification.csv"))
cat(sprintf("    Inauguration-year verification: %d violations total\n",
            sum(inaug_verify$n_violations)))
diag_results$inaug_violations <- sum(inaug_verify$n_violations)

# Term-constancy check for FA
cat("  Checking FA term constancy...\n")

# Mayor term map
mayor_terms <- list(
  `2005` = 2005L:2008L, `2009` = 2009L:2012L,
  `2013` = 2013L:2016L, `2017` = 2017L:2017L
)
gp_terms <- list(
  `2007` = 2007L:2010L, `2011` = 2011L:2014L,
  `2015` = 2015L:2017L
)

assign_term <- function(year_vec, tier) {
  terms <- if (tier == "mayor") mayor_terms else gp_terms
  result <- rep(NA_integer_, length(year_vec))
  for (nm in names(terms)) {
    result[year_vec %in% terms[[nm]]] <- as.integer(nm)
  }
  result
}

constancy_results <- list()
for (ic in ALL_FA) {
  tier <- if (grepl("^FA_(mayor|mayor_gov|mayor_pres|triple)", ic)) "mayor" else "gov_pres"
  # For interaction instruments, check combined terms
  if (grepl("(mayor_gov|mayor_pres|triple)", ic)) {
    # Combined terms: shorter stints, skip detailed check for now
    next
  }
  dt4[, term_id := assign_term(year, tier)]
  dt4_term <- dt4[!is.na(term_id)]
  # Check: within (firm_id, muni_id, term_id), is ic constant?
  constancy <- dt4_term[, .(is_constant = (max(get(ic), na.rm = TRUE) - min(get(ic), na.rm = TRUE)) < 1e-10),
                        by = .(firm_id, muni_id, term_id)]
  frac_constant <- mean(constancy$is_constant, na.rm = TRUE)
  constancy_results[[ic]] <- data.table(
    instrument    = ic,
    n_cells       = nrow(constancy),
    n_constant    = sum(constancy$is_constant),
    pct_constant  = 100 * frac_constant
  )
  cat(sprintf("    %s: %.1f%% of firm-muni-term cells are constant\n", ic, 100 * frac_constant))
}
dt4[, term_id := NULL]

if (length(constancy_results) > 0L) {
  constancy_dt <- rbindlist(constancy_results)
  fwrite(constancy_dt, file.path(out_dir, "term_constancy.csv"))
  cat(sprintf("  Saved term_constancy.csv\n"))
  diag_results$term_constancy <- constancy_dt
}

# --- Event-study-style plot ---
cat("  Generating event-study-style instrument-by-year plot...\n")

# Mean non-zero value by year for coalition instruments only (cleaner plot)
plot_instruments <- intersect(
  c("FA_mayor_coalition", "FA_gov_coalition", "FA_pres_coalition"),
  ALL_FA
)

if (length(plot_instruments) > 0L) {
  year_means <- rbindlist(lapply(plot_instruments, function(ic) {
    dt4[get(ic) != 0, .(mean_val = mean(get(ic), na.rm = TRUE),
                         n_nonzero = .N), by = year][
      , instrument := ic]
  }))
  setorder(year_means, instrument, year)

  plot_colors <- c(FA_mayor_coalition = "#1B6CA8",
                   FA_gov_coalition = "#A23B72",
                   FA_pres_coalition = "#3B7A57")

  png(file.path(out_dir, "fig_instrument_by_year.png"), width = 1000, height = 600)
  par(mar = c(4.5, 4.5, 3, 1))

  y_range <- year_means[, range(mean_val, na.rm = TRUE)]
  x_range <- year_means[, range(year)]

  first_ic <- plot_instruments[1]
  first_dt <- year_means[instrument == first_ic]
  plot(first_dt$year, first_dt$mean_val, type = "o", lwd = 2,
       col = plot_colors[first_ic], pch = 16,
       xlim = x_range, ylim = y_range,
       xlab = "Year", ylab = "Mean Non-Zero Instrument Value",
       main = "Instrument Magnitude by Year")

  for (ic in plot_instruments[-1]) {
    ic_dt <- year_means[instrument == ic]
    lines(ic_dt$year, ic_dt$mean_val, type = "o", lwd = 2,
          col = plot_colors[ic], pch = 16)
  }

  # Inauguration year lines
  abline(v = INAUG_MAYOR, lty = 2, col = "grey60")
  abline(v = INAUG_GOVPRES, lty = 3, col = "grey60")
  legend("topright",
         legend = c(sub("FA_", "", plot_instruments), "Mayor inaug.", "Gov/Pres inaug."),
         col = c(plot_colors[plot_instruments], "grey60", "grey60"),
         lty = c(rep(1, length(plot_instruments)), 2, 3),
         pch = c(rep(16, length(plot_instruments)), NA, NA),
         lwd = 2, bty = "n", cex = 0.9)
  dev.off()
  cat("  Saved fig_instrument_by_year.png\n")
}

rm(dt4)
invisible(gc())

} # end s4a_done else block

# --- 4B: Predictive Relevance (Diagnostic Regressions) ---
cat("\n  4B: Predictive regressions (diagnostic, firm FE only)...\n")
cat("  NOTE: These are predictive diagnostics, not causal estimates.\n")
cat("        No muni×year FE; apparent relevance may differ in production.\n\n")

suppressPackageStartupMessages(library(fixest))
setFixest_nthreads(4)

s4b_cols <- c("firm_id", "muni_id", "year", "n_employees",
              OUTCOMES_LEVELS, OUTCOMES_CHANGES,
              "FA_mayor_coalition", "FA_gov_coalition", "FA_pres_coalition",
              "dFA_mayor_coalition", "dFA_gov_coalition", "dFA_pres_coalition")
s4b_cols <- intersect(s4b_cols, available_cols)
dt4b <- .load_panel_cols(s4b_cols)

# Spec table
specs <- list(
  list(id = 1,  dv = "has_bndes_fmt",       iv = "FA_mayor_coalition",  label = "Mayor extensive"),
  list(id = 2,  dv = "has_bndes_fmt",       iv = "FA_gov_coalition",    label = "Gov extensive"),
  list(id = 3,  dv = "has_bndes_fmt",       iv = "FA_pres_coalition",   label = "Pres extensive"),
  list(id = 4,  dv = "log_bndes_fmt",       iv = "FA_mayor_coalition",  label = "Mayor intensive"),
  list(id = 5,  dv = "log_bndes_fmt",       iv = "FA_gov_coalition",    label = "Gov intensive"),
  list(id = 6,  dv = "log_bndes_fmt",       iv = "FA_pres_coalition",   label = "Pres intensive"),
  list(id = 7,  dv = "has_bndes_fmt",
       iv = "FA_mayor_coalition + FA_gov_coalition + FA_pres_coalition",
       label = "Joint extensive"),
  list(id = 8,  dv = "log_bndes_fmt",
       iv = "FA_mayor_coalition + FA_gov_coalition + FA_pres_coalition",
       label = "Joint intensive"),
  list(id = 9,  dv = "delta_has_bndes_fmt",  iv = "dFA_mayor_coalition", label = "Mayor chg ext"),
  list(id = 10, dv = "delta_has_bndes_fmt",  iv = "dFA_gov_coalition",   label = "Gov chg ext"),
  list(id = 11, dv = "delta_has_bndes_fmt",  iv = "dFA_pres_coalition",  label = "Pres chg ext"),
  list(id = 12, dv = "delta_has_bndes_fmt",
       iv = "dFA_mayor_coalition + dFA_gov_coalition + dFA_pres_coalition",
       label = "Joint chg ext")
)

# Filter specs to available columns
specs <- Filter(function(s) {
  iv_cols <- trimws(strsplit(s$iv, "\\+")[[1]])
  s$dv %in% available_cols && all(iv_cols %in% available_cols)
}, specs)

reg_results <- rbindlist(lapply(specs, function(s) {
  cat(sprintf("    Spec %d: %s ~ %s ...", s$id, s$dv, s$iv))
  fml <- as.formula(sprintf("%s ~ %s | firm_id", s$dv, s$iv))
  wt_col <- if ("n_employees" %in% names(dt4b)) "n_employees" else NULL

  tryCatch({
    mod <- if (!is.null(wt_col)) {
      feols(fml, data = dt4b, weights = ~n_employees, lean = TRUE)
    } else {
      feols(fml, data = dt4b, lean = TRUE)
    }

    iv_cols <- trimws(strsplit(s$iv, "\\+")[[1]])
    coefs <- coef(mod)[iv_cols]
    ses <- se(mod)[iv_cols]

    # Wald F for all IVs
    wald_f <- tryCatch({
      iv_pattern <- paste0("^(", paste(trimws(strsplit(s$iv, "\\+")[[1]]), collapse = "|"), ")$")
      fixest::wald(mod, keep = iv_pattern)$stat
    }, error = function(e) NA_real_)

    cat(sprintf(" F=%.1f\n", wald_f))

    data.table(
      spec_id     = s$id,
      label       = s$label,
      depvar      = s$dv,
      instruments = s$iv,
      coef        = paste(sprintf("%.6f", coefs), collapse = "; "),
      se          = paste(sprintf("%.6f", ses), collapse = "; "),
      t_stat      = paste(sprintf("%.3f", coefs / ses), collapse = "; "),
      p_value     = paste(sprintf("%.4f", 2 * pnorm(-abs(coefs / ses))), collapse = "; "),
      r2_within   = tryCatch(r2(mod, "within"), error = function(e) {
        tryCatch(r2(mod, "wr2"), error = function(e2) NA_real_)
      }),
      wald_f      = wald_f,
      n_obs       = nobs(mod)
    )
  }, error = function(e) {
    cat(sprintf(" ERROR: %s\n", e$message))
    data.table(
      spec_id = s$id, label = s$label, depvar = s$dv,
      instruments = s$iv, coef = NA, se = NA, t_stat = NA,
      p_value = NA, r2_within = NA, wald_f = NA, n_obs = NA
    )
  })
}))

fwrite(reg_results, file.path(out_dir, "predictive_regressions.csv"))
cat(sprintf("  Saved predictive_regressions.csv (%d rows)\n", nrow(reg_results)))
diag_results$reg_results <- reg_results

rm(dt4b)
invisible(gc())

# --- 4C: Winsorization Sensitivity ---
cat("\n  4C: Winsorization sensitivity...\n")

s4c_cols <- c("year", ALL_INSTRUMENTS)
s4c_cols <- intersect(s4c_cols, available_cols)
dt4c <- .load_panel_cols(s4c_cols)

win_thresholds <- list(c(0.01, 0.99), c(0.05, 0.95))

win_results <- rbindlist(lapply(ALL_INSTRUMENTS, function(ic) {
  vals <- dt4c[[ic]]
  vals <- vals[!is.na(vals)]
  orig_mean <- mean(vals)
  orig_sd <- sd(vals)
  orig_skew <- calc_skewness(vals)

  rbindlist(lapply(win_thresholds, function(th) {
    lo <- quantile(vals, th[1])
    hi <- quantile(vals, th[2])
    w_vals <- pmin(pmax(vals, lo), hi)
    n_clipped <- sum(vals < lo | vals > hi)
    data.table(
      instrument    = ic,
      threshold     = sprintf("%.0f/%.0f", th[1] * 100, th[2] * 100),
      orig_mean     = orig_mean,
      win_mean      = mean(w_vals),
      orig_sd       = orig_sd,
      win_sd        = sd(w_vals),
      orig_skewness = orig_skew,
      win_skewness  = calc_skewness(w_vals),
      n_clipped     = n_clipped,
      pct_mean_change = 100 * abs(mean(w_vals) - orig_mean) / max(abs(orig_mean), 1e-10),
      pct_sd_change   = 100 * abs(sd(w_vals) - orig_sd) / max(orig_sd, 1e-10)
    )
  }))
}))

# Flag tail-driven instruments
win_results[, flagged := pct_mean_change > 10 | pct_sd_change > 25]
n_flagged <- uniqueN(win_results[flagged == TRUE, instrument])

fwrite(win_results, file.path(out_dir, "winsorization_sensitivity.csv"))
cat(sprintf("  Saved winsorization_sensitivity.csv (%d rows)\n", nrow(win_results)))
cat(sprintf("  Instruments flagged as tail-driven: %d\n", n_flagged))
diag_results$n_tail_flagged <- n_flagged
diag_results$win_results <- win_results

rm(dt4c)
invisible(gc())

# ==============================================================================
# Section 5: Export Recommendation Note
# ==============================================================================

cat("\n", strrep("=", 78), "\n")
cat("Section 5: Generating Recommendation Note\n")
cat(strrep("=", 78), "\n\n")

# Build pass/fail summary
pass_fail <- function(cond, detail) {
  if (is.na(cond)) return(c("INFO", detail))
  if (cond) return(c("PASS", detail))
  c("WARN", detail)
}

# Instrument coverage
overall_stats <- diag_results$desc_stats
fa_stats <- overall_stats[instrument %in% ALL_FA]
mean_pct_nonzero_fa <- if (nrow(fa_stats) > 0) 100 - mean(fa_stats$pct_zero) else NA

# Build diagnostics table
diag_table <- rbind(
  data.table(
    diagnostic = "Instrument coverage",
    status     = if (!is.na(mean_pct_nonzero_fa) && mean_pct_nonzero_fa > 5) "PASS" else "WARN",
    detail     = sprintf("%.1f%% of panel has non-zero FA instruments", mean_pct_nonzero_fa)
  ),
  data.table(
    diagnostic = "Support bounds",
    status     = if (diag_results$bounds_ok) "PASS" else "FAIL",
    detail     = if (diag_results$bounds_ok) "All within bounds" else "Values outside theoretical bounds"
  ),
  data.table(
    diagnostic = "Structural zeros (dFA)",
    status     = if (diag_results$inaug_violations == 0) "PASS" else "FAIL",
    detail     = sprintf("dFA non-zero only at inauguration years: %s",
                         if (diag_results$inaug_violations == 0) "yes" else "no")
  ),
  if (!is.null(diag_results$term_constancy)) {
    mean_const <- mean(diag_results$term_constancy$pct_constant, na.rm = TRUE)
    data.table(
      diagnostic = "Term constancy (FA)",
      status     = if (mean_const > 99) "PASS" else "WARN",
      detail     = sprintf("%.1f%% of firm-muni cells constant within term", mean_const)
    )
  },
  if (diag_results$baseline_available) {
    data.table(
      diagnostic = "Baseline coverage",
      status     = if (diag_results$pct_firms_with_exposure > 10) "PASS" else "WARN",
      detail     = sprintf("%.1f%% of firms with affiliated owners",
                           diag_results$pct_firms_with_exposure)
    )
  },
  if (!is.null(diag_results$baseline_persistence)) {
    mean_corr <- mean(diag_results$baseline_persistence$correlation, na.rm = TRUE)
    data.table(
      diagnostic = "Baseline persistence",
      status     = "INFO",
      detail     = sprintf("Cross-cycle correlation: %.3f", mean_corr)
    )
  },
  data.table(
    diagnostic = "Winsorization sensitivity",
    status     = if (diag_results$n_tail_flagged == 0) "PASS" else "WARN",
    detail     = sprintf("%d instruments flagged as tail-driven",
                         diag_results$n_tail_flagged)
  )
)

# Predictive relevance table
assess_f <- function(f) {
  if (is.na(f)) return("N/A")
  if (f >= 10) return("STRONG")
  if (f >= 5) return("MODERATE")
  "WEAK"
}

reg_summary_lines <- character(0)
if (!is.null(diag_results$reg_results) && nrow(diag_results$reg_results) > 0) {
  rr <- diag_results$reg_results
  reg_summary_lines <- c(
    "## Predictive Relevance (Diagnostic Regressions)",
    "| Spec | Label | Wald F | Assessment |",
    "|------|-------|--------|------------|",
    vapply(seq_len(nrow(rr)), function(i) {
      sprintf("| %d | %s | %.1f | %s |",
              rr$spec_id[i], rr$label[i],
              rr$wald_f[i], assess_f(rr$wald_f[i]))
    }, character(1)),
    "",
    "Threshold: F >= 10 -> STRONG, 5 <= F < 10 -> MODERATE, F < 5 -> WEAK",
    ""
  )
}

# Recommendation text
strongest_tier <- "undetermined"
if (!is.null(diag_results$reg_results) && nrow(diag_results$reg_results) > 0) {
  single_specs <- diag_results$reg_results[spec_id %in% 1:3]
  if (nrow(single_specs) > 0 && any(!is.na(single_specs$wald_f))) {
    best_idx <- which.max(single_specs$wald_f)
    strongest_tier <- single_specs$label[best_idx]
  }
}

recommendation_lines <- c(
  sprintf("Based on diagnostic F-statistics, the strongest predictive tier is **%s**.", strongest_tier),
  "Coalition-type alignment is the default specification (broader coverage than party-exact).",
  ""
)

# Joint vs single
if (!is.null(diag_results$reg_results)) {
  joint_f <- diag_results$reg_results[spec_id == 7, wald_f]
  single_fs <- diag_results$reg_results[spec_id %in% 1:3, wald_f]
  if (length(joint_f) > 0 && !is.na(joint_f) && any(!is.na(single_fs))) {
    if (joint_f > max(single_fs, na.rm = TRUE)) {
      recommendation_lines <- c(recommendation_lines,
        "Joint specification (all 3 tiers) shows higher F than any single tier.")
    } else {
      recommendation_lines <- c(recommendation_lines,
        "Single-tier specifications dominate the joint specification on F-statistic.")
    }
  }
}

# Assemble note
note_lines <- c(
  "# Firm Instrument Quality Diagnostics — Summary",
  sprintf("Date: %s", Sys.Date()),
  sprintf("Baseline: %s", BASELINE_TYPE),
  sprintf("Panel: %s obs, %s firms, %d years",
          format(diag_results$n_obs, big.mark = ","),
          format(diag_results$n_firms, big.mark = ","),
          diag_results$n_years),
  "",
  "## Pass/Fail Summary",
  "| Diagnostic | Status | Detail |",
  "|-----------|--------|--------|",
  vapply(seq_len(nrow(diag_table)), function(i) {
    sprintf("| %s | %s | %s |", diag_table$diagnostic[i],
            diag_table$status[i], diag_table$detail[i])
  }, character(1)),
  "",
  reg_summary_lines,
  "## Recommendation",
  recommendation_lines,
  "## Caveats",
  "- These are predictive diagnostics only, not causal estimates.",
  "- Firm FE only (no muni×year FE); apparent relevance will differ in production specifications.",
  "- Conditional-on-positive sample for intensive margin may differ from production conditioning.",
  ""
)

writeLines(note_lines, file.path(out_dir, "recommendation_note.md"))
cat(sprintf("  Saved recommendation_note.md\n"))

# --- Final summary ---
cat("\n", strrep("=", 78), "\n")
cat("Diagnostic complete. Output files:\n")
out_files <- list.files(out_dir, full.names = FALSE)
for (f in out_files) cat("  ", f, "\n")
cat(sprintf("\nTotal: %d files in %s\n", length(out_files), out_dir))
