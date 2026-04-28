#!/usr/bin/env Rscript

# ==============================================================================
# Build Sector × Size-Bin Crosswalks (Within-Sector Employment Terciles)
# ==============================================================================
# Creates three crosswalks from (firm_id, election_cycle) to composite sector ×
# size-bin keys, based on within-sector pre-election employment terciles:
#
#   1. cnae_section × size_bin   → sector_size_bin_cnae_mapping.qs2
#      key: cnae_size_bin = paste(cnae_section, size_bin_cnae, sep = "_")
#
#   2. sector_group × size_bin   → sector_size_bin_group_mapping.qs2
#      key: sector_group_size_bin = paste(sector_group, size_bin_group, sep = "_")
#
#   3. bndes_sector × size_bin   → sector_size_bin_bndes_mapping.qs2
#      key: bndes_sector_size_bin = paste(bndes_sector, size_bin_bndes, sep = "_")
#
# Tercile thresholds are computed within each sector nationally, per election
# cycle — not across all firms nationally (that is script 30c).
#
# Election cycles and baseline windows match script 33 / script 30c:
#   Mayor cycles:    2005, 2009, 2013, 2017
#   Gov/Pres cycles: 2007, 2011, 2015
#
# Edge cases:
#   - Sectors with < MIN_SECTOR_FIRMS firms in a cycle: all firms assigned T1
#     with a warning. No NA bins emitted.
#
# Inputs:
#   output/firm_panel_for_regs.fst (base) + firm_panel_for_regs_instruments.fst (sparse)
#   output/sector_group_mapping.qs2
#   output/bndes_sector_mapping.qs2
#
# Outputs:
#   output/sector_size_bin_cnae_mapping.qs2
#   output/sector_size_bin_cnae_mapping_summary.csv
#   output/sector_size_bin_group_mapping.qs2
#   output/sector_size_bin_group_mapping_summary.csv
#   output/sector_size_bin_bndes_mapping.qs2
#   output/sector_size_bin_bndes_mapping_summary.csv
#
# Dependencies: script 42 (firm panel), script 30 (sector_group_mapping),
#               script 30b (bndes_sector_mapping)
# ==============================================================================

cat("==============================================================================\n")
cat("Building Sector x Size-Bin Crosswalks -- Within-Sector Terciles (Script 30d)\n")
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

out_cnae_path    <- make_output_path("sector_size_bin_cnae_mapping.qs2")
out_group_path   <- make_output_path("sector_size_bin_group_mapping.qs2")
out_bndes_path   <- make_output_path("sector_size_bin_bndes_mapping.qs2")
sum_cnae_path    <- make_output_path("sector_size_bin_cnae_mapping_summary.csv")
sum_group_path   <- make_output_path("sector_size_bin_group_mapping_summary.csv")
sum_bndes_path   <- make_output_path("sector_size_bin_bndes_mapping_summary.csv")

# Baseline windows matching script 33 / script 30c.
BASELINE_WINDOWS <- rbindlist(list(
  data.table(election_cycle = 2005L, bl_start = 2002L, bl_end = 2003L),
  data.table(election_cycle = 2007L, bl_start = 2002L, bl_end = 2005L),
  data.table(election_cycle = 2009L, bl_start = 2004L, bl_end = 2007L),
  data.table(election_cycle = 2011L, bl_start = 2006L, bl_end = 2009L),
  data.table(election_cycle = 2013L, bl_start = 2008L, bl_end = 2011L),
  data.table(election_cycle = 2015L, bl_start = 2010L, bl_end = 2013L),
  data.table(election_cycle = 2017L, bl_start = 2012L, bl_end = 2015L)
))

N_BINS            <- 3L
# Sectors with fewer than this many firms get all firms assigned to T1.
MIN_SECTOR_FIRMS  <- 3L

# --- Helper: assign terciles within a vector ---------------------------------

assign_size_bins <- function(x, n_bins = 3L) {
  if (!length(x)) return(integer())
  if (all(is.na(x))) return(rep(NA_integer_, length(x)))

  probs  <- seq(0, 1, length.out = n_bins + 1L)
  breaks <- unique(as.numeric(quantile(x, probs = probs, na.rm = TRUE, names = FALSE)))

  if (length(breaks) >= n_bins + 1L) {
    return(as.integer(cut(x, breaks = breaks, include.lowest = TRUE, labels = FALSE)))
  }

  # Fallback: rank-based assignment when ties collapse the quantile breaks.
  ranks <- frank(x, ties.method = "average", na.last = "keep")
  n_obs <- sum(!is.na(x))
  pmax.int(1L, pmin.int(n_bins, as.integer(ceiling(ranks / n_obs * n_bins))))
}

# Assign within-sector bins for one (sector, cycle) slice.
# Falls back to T1-for-all when fewer than MIN_SECTOR_FIRMS firms are present.
assign_within_sector <- function(dt_slice, sector_id_for_log, cycle_for_log) {
  n <- nrow(dt_slice)
  if (n < MIN_SECTOR_FIRMS) {
    cat(sprintf(
      "    WARNING: sector '%s' cycle %d has only %d firm(s) — all assigned T1.\n",
      sector_id_for_log, cycle_for_log, n
    ))
    dt_slice[, size_bin := 1L]
    return(dt_slice)
  }
  if (uniqueN(dt_slice$mean_emp) <= 1L) {
    dt_slice[, size_bin := 1L]
    return(dt_slice)
  }
  dt_slice[, size_bin := assign_size_bins(mean_emp, n_bins = N_BINS)]
  dt_slice
}

# --- Step 1: Load firm panel -------------------------------------------------

cat("Step 1: Loading firm panel...\n")

# No instrument columns needed — load base only to minimise memory.
dt <- load_firm_panel(
  baseline_type = "cycle_specific",
  columns       = c("firm_id", "year", "cnae_section", "n_employees"),
  instruments   = character(0),
  zero_fill     = FALSE,
  as_data_table = TRUE
)
cat(sprintf("  Loaded: %s rows\n", format(nrow(dt), big.mark = ",")))

dt[, firm_id      := as.integer(firm_id)]
dt[, year         := as.integer(year)]
dt[, cnae_section := as.character(cnae_section)]
dt[, n_employees  := as.numeric(n_employees)]

# --- Step 2: Load sector-group and BNDES-sector mappings ---------------------

cat("\nStep 2: Loading sector-group and BNDES-sector mappings...\n")

sg_map_path <- make_output_path("sector_group_mapping.qs2")
if (!file.exists(sg_map_path)) {
  stop("sector_group_mapping.qs2 not found. Run script 30 first.")
}
sg_map <- qs_read(sg_map_path)
setDT(sg_map)
if (!all(c("cnae_section", "sector_group") %in% names(sg_map))) {
  stop("sector_group_mapping.qs2 is missing required columns 'cnae_section' or 'sector_group'.")
}
sg_map <- unique(sg_map[, .(cnae_section = as.character(cnae_section),
                             sector_group = as.character(sector_group))])
cat(sprintf("  %d cnae_section -> sector_group mappings loaded.\n", nrow(sg_map)))

bndes_map_path <- make_output_path("bndes_sector_mapping.qs2")
if (!file.exists(bndes_map_path)) {
  stop("bndes_sector_mapping.qs2 not found. Run script 30b first.")
}
bndes_map <- qs_read(bndes_map_path)
setDT(bndes_map)
if (!all(c("cnae_section", "bndes_sector") %in% names(bndes_map))) {
  stop("bndes_sector_mapping.qs2 is missing required columns 'cnae_section' or 'bndes_sector'.")
}
bndes_map <- unique(bndes_map[, .(cnae_section = as.character(cnae_section),
                                   bndes_sector  = as.character(bndes_sector))])
cat(sprintf("  %d cnae_section -> bndes_sector mappings loaded.\n", nrow(bndes_map)))

# --- Step 3: Attach sector_group and bndes_sector, collapse to (firm, year) --

cat("\nStep 3: Collapsing to national firm-year totals...\n")

dt[sg_map,    sector_group := i.sector_group, on = "cnae_section"]
dt[bndes_map, bndes_sector := i.bndes_sector, on = "cnae_section"]

n_no_sg <- sum(is.na(dt$sector_group))
if (n_no_sg > 0L) {
  cat(sprintf("  NOTE: %s rows have no sector_group (likely residual/XX sectors); excluded from group crosswalk.\n",
              format(n_no_sg, big.mark = ",")))
}

n_no_bndes <- sum(is.na(dt$bndes_sector))
if (n_no_bndes > 0L) {
  cat(sprintf("  NOTE: %s rows have no bndes_sector; excluded from BNDES crosswalk.\n",
              format(n_no_bndes, big.mark = ",")))
}

# Collapse across munis to national firm-year totals.
# Zero employment is valid; exclude only rows where n_employees is entirely NA
# for that (firm, year) cell.
dt_fy <- dt[, .(
  has_emp_obs     = any(!is.na(n_employees)),
  total_employees = sum(n_employees, na.rm = TRUE),
  cnae_section    = cnae_section[1L],
  sector_group    = if (all(is.na(sector_group))) NA_character_ else sector_group[!is.na(sector_group)][1L],
  bndes_sector    = if (all(is.na(bndes_sector))) NA_character_ else bndes_sector[!is.na(bndes_sector)][1L]
), by = .(firm_id, year)]

dt_fy <- dt_fy[has_emp_obs == TRUE]
dt_fy[, has_emp_obs := NULL]
setnames(dt_fy, "total_employees", "n_employees")

cat(sprintf("  Firm-year national totals retained: %s\n",  format(nrow(dt_fy), big.mark = ",")))
cat(sprintf("  Unique firms: %s\n",  format(uniqueN(dt_fy$firm_id), big.mark = ",")))
cat(sprintf("  Zero-employment firm-years: %s\n",
            format(sum(dt_fy$n_employees == 0, na.rm = TRUE), big.mark = ",")))

# Free memory — we no longer need the muni-level panel.
rm(dt)
invisible(gc())

# --- Step 4: Build within-sector terciles per cycle --------------------------

cat("\nStep 4: Computing within-sector terciles per election cycle...\n")

all_cnae_bins  <- list()
all_group_bins <- list()
all_bndes_bins <- list()

for (i in seq_len(nrow(BASELINE_WINDOWS))) {
  ec       <- BASELINE_WINDOWS$election_cycle[i]
  bl_start <- BASELINE_WINDOWS$bl_start[i]
  bl_end   <- BASELINE_WINDOWS$bl_end[i]

  cat(sprintf("  Cycle %d (baseline %d-%d):\n", ec, bl_start, bl_end))

  dt_bl <- dt_fy[year >= bl_start & year <= bl_end]
  if (!nrow(dt_bl)) {
    cat("    Skipped: no observations in baseline window.\n")
    next
  }

  # Pre-election mean employment per firm.
  firm_avg <- dt_bl[, .(
    mean_emp     = mean(n_employees, na.rm = TRUE),
    cnae_section = cnae_section[1L],
    sector_group = if (all(is.na(sector_group))) NA_character_
                   else sector_group[!is.na(sector_group)][1L],
    bndes_sector = if (all(is.na(bndes_sector))) NA_character_
                   else bndes_sector[!is.na(bndes_sector)][1L],
    n_years      = .N
  ), by = firm_id]

  cat(sprintf("    Firms: %s, mean emp: %.1f\n",
              format(nrow(firm_avg), big.mark = ","),
              mean(firm_avg$mean_emp, na.rm = TRUE)))

  # --- CNAE section bins ------------------------------------------------------
  cnae_bins_cycle <- rbindlist(lapply(
    unique(firm_avg$cnae_section),
    function(sec) {
      slice <- firm_avg[cnae_section == sec]
      slice <- assign_within_sector(slice, sec, ec)
      slice[, .(firm_id, cnae_section, size_bin)]
    }
  ), fill = FALSE)
  cnae_bins_cycle[, election_cycle := ec]

  n_na_cnae <- sum(is.na(cnae_bins_cycle$size_bin))
  if (n_na_cnae > 0L) {
    cat(sprintf("    WARNING: %d NA size_bin values in CNAE crosswalk for cycle %d.\n",
                n_na_cnae, ec))
  }

  cat(sprintf("    CNAE bin distribution: %s\n",
              paste(cnae_bins_cycle[, .N, by = size_bin][order(size_bin),
                        sprintf("T%d=%s", size_bin, format(N, big.mark = ","))],
                    collapse = ", ")))

  all_cnae_bins[[length(all_cnae_bins) + 1L]] <- cnae_bins_cycle

  # --- Sector-group bins ------------------------------------------------------
  firms_with_group <- firm_avg[!is.na(sector_group)]
  if (!nrow(firms_with_group)) {
    cat("    No firms with sector_group for this cycle — skipping group bins.\n")
  } else {
    group_bins_cycle <- rbindlist(lapply(
      unique(firms_with_group$sector_group),
      function(grp) {
        slice <- firms_with_group[sector_group == grp]
        slice <- assign_within_sector(slice, grp, ec)
        slice[, .(firm_id, sector_group, size_bin)]
      }
    ), fill = FALSE)
    group_bins_cycle[, election_cycle := ec]

    n_na_group <- sum(is.na(group_bins_cycle$size_bin))
    if (n_na_group > 0L) {
      cat(sprintf("    WARNING: %d NA size_bin values in sector-group crosswalk for cycle %d.\n",
                  n_na_group, ec))
    }

    cat(sprintf("    Group bin distribution: %s\n",
                paste(group_bins_cycle[, .N, by = size_bin][order(size_bin),
                          sprintf("T%d=%s", size_bin, format(N, big.mark = ","))],
                      collapse = ", ")))

    all_group_bins[[length(all_group_bins) + 1L]] <- group_bins_cycle
  }

  # --- BNDES-sector bins ------------------------------------------------------
  firms_with_bndes <- firm_avg[!is.na(bndes_sector)]
  if (!nrow(firms_with_bndes)) {
    cat("    No firms with bndes_sector for this cycle — skipping BNDES bins.\n")
  } else {
    bndes_bins_cycle <- rbindlist(lapply(
      unique(firms_with_bndes$bndes_sector),
      function(bsec) {
        slice <- firms_with_bndes[bndes_sector == bsec]
        slice <- assign_within_sector(slice, bsec, ec)
        slice[, .(firm_id, bndes_sector, size_bin)]
      }
    ), fill = FALSE)
    bndes_bins_cycle[, election_cycle := ec]

    n_na_bndes <- sum(is.na(bndes_bins_cycle$size_bin))
    if (n_na_bndes > 0L) {
      cat(sprintf("    WARNING: %d NA size_bin values in BNDES-sector crosswalk for cycle %d.\n",
                  n_na_bndes, ec))
    }

    cat(sprintf("    BNDES bin distribution: %s\n",
                paste(bndes_bins_cycle[, .N, by = size_bin][order(size_bin),
                          sprintf("T%d=%s", size_bin, format(N, big.mark = ","))],
                      collapse = ", ")))

    all_bndes_bins[[length(all_bndes_bins) + 1L]] <- bndes_bins_cycle
  }
}

# --- Step 5: Build composite keys and save -----------------------------------

cat("\nStep 5: Building composite keys and saving...\n")

# --- CNAE crosswalk ----------------------------------------------------------

cnae_xwalk <- rbindlist(all_cnae_bins, fill = TRUE)
cnae_xwalk[, size_bin_cnae      := paste0("T", size_bin)]
cnae_xwalk[, cnae_size_bin      := paste(cnae_section, size_bin_cnae, sep = "_")]
cnae_xwalk[, size_bin := NULL]

cat(sprintf("  CNAE crosswalk: %s rows, %s unique firms, %d cycles.\n",
            format(nrow(cnae_xwalk), big.mark = ","),
            format(uniqueN(cnae_xwalk$firm_id), big.mark = ","),
            uniqueN(cnae_xwalk$election_cycle)))

n_na_check <- sum(is.na(cnae_xwalk$size_bin_cnae))
if (n_na_check > 0L) {
  warning(sprintf("%d rows with NA size_bin_cnae in CNAE crosswalk.", n_na_check))
}

qs_save(
  cnae_xwalk[, .(firm_id, election_cycle, cnae_section, size_bin_cnae, cnae_size_bin)],
  out_cnae_path
)
cat(sprintf("  Saved: %s\n", out_cnae_path))

cnae_summary <- cnae_xwalk[, .(n_firms = .N),
                            by = .(cnae_section, size_bin_cnae, election_cycle)]
setorder(cnae_summary, cnae_section, election_cycle, size_bin_cnae)
fwrite(cnae_summary, sum_cnae_path)
cat(sprintf("  Saved: %s\n", sum_cnae_path))

# --- Sector-group crosswalk --------------------------------------------------

group_xwalk <- rbindlist(all_group_bins, fill = TRUE)
group_xwalk[, size_bin_group        := paste0("T", size_bin)]
group_xwalk[, sector_group_size_bin := paste(sector_group, size_bin_group, sep = "_")]
group_xwalk[, size_bin := NULL]

cat(sprintf("  Group crosswalk: %s rows, %s unique firms, %d cycles.\n",
            format(nrow(group_xwalk), big.mark = ","),
            format(uniqueN(group_xwalk$firm_id), big.mark = ","),
            uniqueN(group_xwalk$election_cycle)))

n_na_check_g <- sum(is.na(group_xwalk$size_bin_group))
if (n_na_check_g > 0L) {
  warning(sprintf("%d rows with NA size_bin_group in sector-group crosswalk.", n_na_check_g))
}

qs_save(
  group_xwalk[, .(firm_id, election_cycle, sector_group, size_bin_group, sector_group_size_bin)],
  out_group_path
)
cat(sprintf("  Saved: %s\n", out_group_path))

group_summary <- group_xwalk[, .(n_firms = .N),
                              by = .(sector_group, size_bin_group, election_cycle)]
setorder(group_summary, sector_group, election_cycle, size_bin_group)
fwrite(group_summary, sum_group_path)
cat(sprintf("  Saved: %s\n", sum_group_path))

# --- BNDES-sector crosswalk --------------------------------------------------

bndes_xwalk <- rbindlist(all_bndes_bins, fill = TRUE)
bndes_xwalk[, size_bin_bndes       := paste0("T", size_bin)]
bndes_xwalk[, bndes_sector_size_bin := paste(bndes_sector, size_bin_bndes, sep = "_")]
bndes_xwalk[, size_bin := NULL]

cat(sprintf("  BNDES crosswalk: %s rows, %s unique firms, %d cycles.\n",
            format(nrow(bndes_xwalk), big.mark = ","),
            format(uniqueN(bndes_xwalk$firm_id), big.mark = ","),
            uniqueN(bndes_xwalk$election_cycle)))

n_na_check_b <- sum(is.na(bndes_xwalk$size_bin_bndes))
if (n_na_check_b > 0L) {
  warning(sprintf("%d rows with NA size_bin_bndes in BNDES-sector crosswalk.", n_na_check_b))
}

qs_save(
  bndes_xwalk[, .(firm_id, election_cycle, bndes_sector, size_bin_bndes, bndes_sector_size_bin)],
  out_bndes_path
)
cat(sprintf("  Saved: %s\n", out_bndes_path))

bndes_summary <- bndes_xwalk[, .(n_firms = .N),
                               by = .(bndes_sector, size_bin_bndes, election_cycle)]
setorder(bndes_summary, bndes_sector, election_cycle, size_bin_bndes)
fwrite(bndes_summary, sum_bndes_path)
cat(sprintf("  Saved: %s\n", sum_bndes_path))

# --- Final validation --------------------------------------------------------

cat("\nValidation:\n")

# Every firm present in the CNAE crosswalk for each cycle?
# Use anyDuplicated (short-circuits on first duplicate) instead of a full
# uniqueN-by-group scan, which creates millions of groups and is very slow.
any_multi_bin <- anyDuplicated(cnae_xwalk, by = c("firm_id", "election_cycle")) > 0L
if (any_multi_bin) {
  cat("  WARNING: Some firms have more than one size_bin_cnae within a (firm, cycle) — check sector assignment.\n")
} else {
  cat("  CNAE crosswalk: each firm appears at most once per (firm, cycle) — OK.\n")
}

# No empty bin labels?
empty_cnae  <- sum(nchar(cnae_xwalk$cnae_size_bin) == 0L, na.rm = TRUE)
empty_group <- sum(nchar(group_xwalk$sector_group_size_bin) == 0L, na.rm = TRUE)
empty_bndes <- sum(nchar(bndes_xwalk$bndes_sector_size_bin) == 0L, na.rm = TRUE)
cat(sprintf("  Empty composite keys — CNAE: %d, Group: %d, BNDES: %d\n",
            empty_cnae, empty_group, empty_bndes))

# Unique composite categories (informational).
cat(sprintf("  Unique composite keys — CNAE: %d, Group: %d, BNDES: %d\n",
            uniqueN(cnae_xwalk$cnae_size_bin),
            uniqueN(group_xwalk$sector_group_size_bin),
            uniqueN(bndes_xwalk$bndes_sector_size_bin)))

# Thin-cell rate for D6 diagnostic (informational).
thin_cnae  <- cnae_summary[n_firms < 3L]
thin_group <- group_summary[n_firms < 3L]
thin_bndes <- bndes_summary[n_firms < 3L]
cat(sprintf("  Thin cells (< 3 firms): CNAE = %d / %d (%.1f%%), Group = %d / %d (%.1f%%), BNDES = %d / %d (%.1f%%)\n",
            nrow(thin_cnae),  nrow(cnae_summary),
            100 * nrow(thin_cnae)  / max(1L, nrow(cnae_summary)),
            nrow(thin_group), nrow(group_summary),
            100 * nrow(thin_group) / max(1L, nrow(group_summary)),
            nrow(thin_bndes), nrow(bndes_summary),
            100 * nrow(thin_bndes) / max(1L, nrow(bndes_summary))))

cat("\n==============================================================================\n")
cat("Sector x size-bin crosswalks complete.\n")
cat("==============================================================================\n")
