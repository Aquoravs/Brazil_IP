#!/usr/bin/env Rscript

# ==============================================================================
# Build Size Bin Mapping (Firm Employment Terciles per Election Cycle)
# ==============================================================================
# Creates a crosswalk from (firm_id, election_cycle) to size_bin based on
# pre-election average employment. Firms are classified into 3 terciles
# across all firms nationally (not within CNAE section).
#
# The per-cycle pre-election approach avoids endogeneity: political alignment
# could affect firm employment post-election, so we use only pre-treatment
# employment. Recomputing per cycle avoids staleness — a firm's natural
# growth over 15 years should update its classification.
#
# Election cycles (matching script 33 baseline windows):
#   Mayor cycles:   2005, 2009, 2013, 2017
#   Gov/Pres cycles: 2007, 2011, 2015
#
# For each cycle, the baseline window is the pre-election period.
# Mean n_employees is computed per firm across the baseline window, then
# terciles are computed across all firms nationally.
#
# Input:  output/firm_panel_for_regs.fst (base) + firm_panel_for_regs_instruments.fst (sparse)
# Output: output/size_bin_mapping.qs2
#         output/size_bin_mapping_summary.csv
#
# Dependencies: script 42
# ==============================================================================

cat("==============================================================================\n")
cat("Building Size Bin Mapping — National Terciles (Script 30c)\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})

setDTthreads(0)

# Bootstrap shared path helpers from this script location.
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

# --- Configuration -----------------------------------------------------------

out_path <- make_output_path("size_bin_mapping.qs2")
summary_path <- make_output_path("size_bin_mapping_summary.csv")

# Baseline windows matching script 33
BASELINE_WINDOWS <- rbindlist(list(
  data.table(election_cycle = 2005L, bl_start = 2002L, bl_end = 2003L),
  data.table(election_cycle = 2007L, bl_start = 2002L, bl_end = 2005L),
  data.table(election_cycle = 2009L, bl_start = 2004L, bl_end = 2007L),
  data.table(election_cycle = 2011L, bl_start = 2006L, bl_end = 2009L),
  data.table(election_cycle = 2013L, bl_start = 2008L, bl_end = 2011L),
  data.table(election_cycle = 2015L, bl_start = 2010L, bl_end = 2013L),
  data.table(election_cycle = 2017L, bl_start = 2012L, bl_end = 2015L)
))

MIN_FIRMS_FOR_TERCILES <- 30L
N_BINS <- 3L

assign_size_bins <- function(x, n_bins = 3L) {
  if (!length(x)) return(integer())
  if (all(is.na(x))) return(rep(NA_integer_, length(x)))

  probs <- seq(0, 1, length.out = n_bins + 1L)
  breaks <- unique(as.numeric(quantile(x, probs = probs, na.rm = TRUE, names = FALSE)))

  if (length(breaks) >= n_bins + 1L) {
    return(as.integer(cut(x, breaks = breaks, include.lowest = TRUE, labels = FALSE)))
  }

  ranks <- frank(x, ties.method = "average", na.last = "keep")
  n_obs <- sum(!is.na(x))
  pmax.int(1L, pmin.int(n_bins, as.integer(ceiling(ranks / n_obs * n_bins))))
}

# --- Step 1: Load firm panel --------------------------------------------------

cat("Step 1: Loading firm panel...\n")

# No instrument columns needed — load base only to minimise memory.
dt <- load_firm_panel(
  baseline_type = "cycle_specific",
  columns       = c("firm_id", "year", "n_employees"),
  instruments   = character(0),
  zero_fill     = FALSE,
  as_data_table = TRUE
)
cat(sprintf("  Loaded: %s rows\n", format(nrow(dt), big.mark = ",")))

dt[, firm_id := as.integer(firm_id)]
dt[, year := as.integer(year)]
dt[, n_employees := as.numeric(n_employees)]

# Collapse to national firm-year totals before building cycle averages.
# Zero is a valid observed size; exclude only firm-years with all-NA employment.
dt_fy <- dt[, .(
  has_emp_obs = any(!is.na(n_employees)),
  total_employees = sum(n_employees, na.rm = TRUE)
), by = .(firm_id, year)]
dt_fy <- dt_fy[has_emp_obs == TRUE, .(firm_id, year, n_employees = total_employees)]

cat(sprintf("  Firm-year totals retained: %s\n", format(nrow(dt_fy), big.mark = ",")))
cat(sprintf("  Zero-employment firm-years retained: %s\n",
            format(sum(dt_fy$n_employees == 0, na.rm = TRUE), big.mark = ",")))

# --- Step 2: Compute mean employment per firm per election cycle --------------

cat("\nStep 2: Computing pre-election mean employment per firm...\n")

all_bins <- list()

for (i in seq_len(nrow(BASELINE_WINDOWS))) {
  ec <- BASELINE_WINDOWS$election_cycle[i]
  bl_start <- BASELINE_WINDOWS$bl_start[i]
  bl_end <- BASELINE_WINDOWS$bl_end[i]

  cat(sprintf("  Cycle %d (baseline %d-%d):\n", ec, bl_start, bl_end))

  # Subset to baseline window using retained firm-year totals.
  dt_bl <- dt_fy[year >= bl_start & year <= bl_end]

  if (!nrow(dt_bl)) {
    cat("    Skipped: no observations in baseline window\n")
    next
  }

  # Compute mean employment per firm across retained baseline years.
  firm_avg <- dt_bl[, .(
    mean_emp = mean(n_employees, na.rm = TRUE),
    n_years = .N
  ), by = firm_id]

  cat(sprintf("    Firms: %s, mean employment: %.1f\n",
              format(nrow(firm_avg), big.mark = ","),
              mean(firm_avg$mean_emp, na.rm = TRUE)))

  # --- Step 3: Compute terciles across all firms nationally ------------------

  n_firms <- nrow(firm_avg)
  if (n_firms < MIN_FIRMS_FOR_TERCILES) {
    firm_avg[, size_bin := 1L]
  } else {
    if (uniqueN(firm_avg$mean_emp) <= 1L) {
      firm_avg[, size_bin := 1L]
    } else {
      firm_avg[, size_bin := assign_size_bins(mean_emp, n_bins = N_BINS)]
    }
  }

  # Create output
  bin_dt <- firm_avg[, .(firm_id, size_bin, mean_emp)]
  bin_dt[, election_cycle := ec]

  cat(sprintf("    Bin distribution: %s\n",
              paste(bin_dt[, .N, by = size_bin][order(size_bin),
                           sprintf("bin%d=%s", size_bin, format(N, big.mark = ","))],
                    collapse = ", ")))

  all_bins[[length(all_bins) + 1L]] <- bin_dt
}

# --- Step 4: Combine and save ------------------------------------------------

cat("\nStep 4: Combining and saving...\n")

crosswalk <- rbindlist(all_bins, fill = TRUE)
crosswalk[, size_bin_label := paste0("T", size_bin)]

cat(sprintf("  Total rows: %s\n", format(nrow(crosswalk), big.mark = ",")))
cat(sprintf("  Unique firms: %s\n", format(uniqueN(crosswalk$firm_id), big.mark = ",")))
cat(sprintf("  Election cycles: %s\n", paste(sort(unique(crosswalk$election_cycle)), collapse = ", ")))
cat(sprintf("  Size bins: %d\n", uniqueN(crosswalk$size_bin)))

# Verify no firm is left unclassified
n_na <- sum(is.na(crosswalk$size_bin))
if (n_na > 0) {
  cat(sprintf("  WARNING: %d rows with NA size_bin\n", n_na))
}

# Save
qs_save(crosswalk[, .(firm_id, election_cycle, size_bin, size_bin_label, mean_emp)],
        out_path)
cat(sprintf("  Saved: %s\n", out_path))

# Summary by cycle and bin
summary_dt <- crosswalk[, .(
  n_firms = .N,
  mean_emp_p25 = quantile(mean_emp, 0.25, na.rm = TRUE),
  mean_emp_p50 = quantile(mean_emp, 0.50, na.rm = TRUE),
  mean_emp_p75 = quantile(mean_emp, 0.75, na.rm = TRUE)
), by = .(election_cycle, size_bin)]
setorder(summary_dt, election_cycle, size_bin)

fwrite(summary_dt, summary_path)
cat(sprintf("  Saved: %s\n", summary_path))

cat("\n==============================================================================\n")
cat("Size bin mapping complete.\n")
cat("==============================================================================\n")
