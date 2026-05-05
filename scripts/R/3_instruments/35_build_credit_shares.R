#!/usr/bin/env Rscript

# ==============================================================================
# Build BNDES Credit Shares and Reallocation Measure
# ==============================================================================
# Computes sector shares of BNDES lending within each municipality-year,
# and the yearly change in those shares (the endogenous reallocation variable).
#
#   s_{mjt} = bndes_{mjt} / bndes_{mt}
#   delta_s_{mjt} = s_{mjt} - s_{mj,t-1}
#
# IMPORTANT: The panel is expanded to include all RAIS-active sectors per
# municipality, not just sectors receiving BNDES loans. Sectors with no
# loans in a given year have bndes_mjt = 0 and s_mjt = 0. This ensures:
#   (a) shares sum to 1 over economically relevant sectors
#   (b) delta_s is computed over consecutive years, not consecutive loan years
#   (c) the extensive margin (gaining/losing BNDES) is captured
#   (d) the panel is balanced within each muni's sector set
#
# The sector universe for each municipality is defined as: all CNAE sections
# with at least one firm in RAIS in that municipality (across all years).
#
# Input:  output/rais_bndes_reconstructed.fst (columns: muni_id, year,
#         cnae_section, value_dis_real_2018_total, in_bndes)
#
# Output: output/bndes_credit_shares.qs2
#         (muni_id, cnae_section, year, bndes_mjt, bndes_mt, s_mjt, delta_s_mjt)
#
# Dependencies: script 22
# ==============================================================================

cat("==============================================================================\n")
cat("Building BNDES Credit Shares and Reallocation Measure (Script 35)\n")
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

setDTthreads(parallel::detectCores() - 1)
qopt("nthreads", parallel::detectCores() - 1)

# --- Parse CLI arguments -----------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

svar_flag <- grep("^--sector-var=", args, value = TRUE)
SECTOR_VAR <- "sector_group"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[1])))
  if (!SECTOR_VAR %in% c("cnae_section", "sector_group", "policy_block")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'. Use 'cnae_section', 'sector_group', or 'policy_block'.")
  }
}
USE_GROUPS <- (SECTOR_VAR == "sector_group")
USE_POLICY_BLOCKS <- (SECTOR_VAR == "policy_block")
SCOL <- SECTOR_VAR
cat("Sector variable:", SECTOR_VAR, "\n\n")

# Load sector crosswalk if using grouped or policy-block sectors
group_crosswalk <- NULL
pb_crosswalk <- NULL
if (USE_GROUPS) {
  cw_path <- make_output_path("sector_group_mapping.qs2")
  if (!file.exists(cw_path)) {
    stop("Sector group mapping not found: ", cw_path, "\n  Run script 30 first.")
  }
  group_crosswalk <- qs_read(cw_path)
  setDT(group_crosswalk)
  cat("  Loaded sector group crosswalk:", nrow(group_crosswalk), "rows\n\n")
} else if (USE_POLICY_BLOCKS) {
  cw_path <- make_output_path("policy_block_mapping.qs2")
  if (!file.exists(cw_path)) {
    stop("Policy block mapping not found: ", cw_path, "\n  Run script 30e first.")
  }
  pb_crosswalk <- qs_read(cw_path)
  setDT(pb_crosswalk)
  cat("  Loaded policy block crosswalk:", nrow(pb_crosswalk), "rows\n\n")
}

# --- Step 1: Load reconstructed panel ----------------------------------------

cat("Step 1: Loading reconstructed panel...\n")

recon_path_fst <- make_output_path("rais_bndes_reconstructed.fst")
recon_path_qs2 <- make_output_path("rais_bndes_reconstructed.qs2")

needed_cols <- c("muni_id", "year", "cnae_section",
                 "value_dis_real_2018_total", "in_bndes")
if (USE_GROUPS) needed_cols <- c(needed_cols, "classe")

if (file.exists(recon_path_fst) && requireNamespace("fst", quietly = TRUE)) {
  cat("  Loading from fst (column-selective):", basename(recon_path_fst), "\n")
  dt <- fst::read_fst(recon_path_fst,
                       columns = needed_cols,
                       as.data.table = TRUE)
} else if (file.exists(recon_path_qs2)) {
  cat("  Loading from qs2:", basename(recon_path_qs2), "\n")
  recon <- qs_read(recon_path_qs2)
  setDT(recon)
  dt <- recon[, ..needed_cols]
  rm(recon); invisible(gc())
} else {
  stop("Reconstructed panel not found.\n",
       "  Checked: ", recon_path_fst, "\n",
       "  Checked: ", recon_path_qs2, "\n",
       "  Run script 22 first.")
}

cat("  Loaded:", format(nrow(dt), big.mark = ","), "rows\n")

# If using groups, derive sector_group from classe
if (USE_GROUPS) {
  dt[, cnae_division := as.integer(floor(as.numeric(classe) / 1000))]
  dt[group_crosswalk, sector_group := i.sector_group, on = "cnae_division"]
  # For non-C sections, merge via section
  section_cw_nonc <- unique(group_crosswalk[cnae_section != "C", .(cnae_section, sector_group)])
  dt[is.na(sector_group) & !is.na(cnae_section),
     sector_group := section_cw_nonc$sector_group[match(cnae_section, section_cw_nonc$cnae_section)]]
  # Drop residual (O, T, U)
  n_xx <- sum(dt$sector_group == "XX", na.rm = TRUE)
  if (n_xx > 0) {
    cat(sprintf("  Dropping %d rows in residual group XX (sections O, T, U)\n", n_xx))
    dt <- dt[!is.na(sector_group) & sector_group != "XX"]
  }
  dt[, c("classe", "cnae_division") := NULL]
  cat(sprintf("  Assigned sector_group: %d unique groups\n", uniqueN(dt$sector_group)))
}

if (USE_POLICY_BLOCKS) {
  dt[pb_crosswalk, policy_block := i.policy_block, on = "cnae_section"]
  n_xx <- sum(dt$policy_block == "XX", na.rm = TRUE)
  if (n_xx > 0) {
    cat(sprintf("  Dropping %d rows in residual block XX (sections K, O, T, U)\n", n_xx))
    dt <- dt[!is.na(policy_block) & policy_block != "XX"]
  }
  cat(sprintf("  Assigned policy_block: %d unique blocks\n", uniqueN(dt$policy_block)))
}

# --- Step 2: Build RAIS skeleton (muni × sector × year) ---------------------

cat("\nStep 2: Building RAIS-based skeleton (all active sectors per muni)...\n")

# Define sector universe per municipality: all CNAE sections with at least one
# firm in RAIS in that municipality (across any year). This is the set of
# economically relevant sectors.
muni_sectors <- unique(dt[!is.na(get(SCOL)) & nzchar(get(SCOL)) &
                           !is.na(muni_id) & muni_id > 0,
                           .SD, .SDcols = c("muni_id", SCOL)])

cat("  Unique muni-sector pairs:", format(nrow(muni_sectors), big.mark = ","), "\n")
cat("  Mean sectors per muni:", round(muni_sectors[, .N, by = muni_id][, mean(N)], 1), "\n")

# All years in the data
all_years <- sort(unique(dt$year))
cat("  Years:", paste(range(all_years), collapse = "-"), "(", length(all_years), "years)\n")

# Cross-join: every muni-sector pair × every year → balanced within each muni
skeleton <- muni_sectors[, .(year = all_years), by = c("muni_id", SCOL)]

cat("  Skeleton rows:", format(nrow(skeleton), big.mark = ","), "\n")
cat("  (vs old BNDES-only panel: would have been ~152K)\n")

# --- Step 3: Aggregate BNDES credit to (muni, sector, year) -----------------

cat("\nStep 3: Aggregating BNDES credit to (muni, sector, year)...\n")

# Filter to BNDES firms with valid sector and positive credit
bndes <- dt[in_bndes == 1L &
            !is.na(get(SCOL)) & nzchar(get(SCOL)) &
            !is.na(value_dis_real_2018_total) & value_dis_real_2018_total > 0]

cat("  BNDES firm-years with positive credit:", format(nrow(bndes), big.mark = ","), "\n")

credit_pos <- bndes[, .(bndes_mjt = sum(value_dis_real_2018_total, na.rm = TRUE)),
                    by = c("muni_id", SCOL, "year")]

cat("  Positive credit cells:", format(nrow(credit_pos), big.mark = ","), "\n")

rm(dt, bndes); invisible(gc())

# --- Step 4: Merge onto skeleton (fill zeros) --------------------------------

cat("\nStep 4: Merging credit onto skeleton (filling zeros)...\n")

credit <- merge(skeleton, credit_pos,
                by = c("muni_id", SCOL, "year"),
                all.x = TRUE)

# Fill NAs with 0 (sectors with no BNDES loans in that year)
credit[is.na(bndes_mjt), bndes_mjt := 0]

n_zero <- sum(credit$bndes_mjt == 0)
n_pos  <- sum(credit$bndes_mjt > 0)
cat(sprintf("  Zero-credit cells: %s (%.1f%%)\n",
            format(n_zero, big.mark = ","), 100 * n_zero / nrow(credit)))
cat(sprintf("  Positive-credit cells: %s (%.1f%%)\n",
            format(n_pos, big.mark = ","), 100 * n_pos / nrow(credit)))

rm(skeleton, credit_pos); invisible(gc())

# --- Step 5: Compute municipality totals and shares --------------------------

cat("\nStep 5: Computing municipality totals and sector shares...\n")

credit[, bndes_mt := sum(bndes_mjt), by = .(muni_id, year)]

# s_mjt = bndes_mjt / bndes_mt; 0/0 → 0 (no BNDES in muni-year at all)
credit[, s_mjt := fifelse(bndes_mt > 0, bndes_mjt / bndes_mt, 0)]

# Flag muni-years with no BNDES at all (shares are all 0, not informative)
n_no_bndes_my <- credit[, .(has_bndes = any(bndes_mt > 0)), by = .(muni_id, year)]
cat(sprintf("  Muni-years with any BNDES: %d / %d (%.1f%%)\n",
            sum(n_no_bndes_my$has_bndes), nrow(n_no_bndes_my),
            100 * mean(n_no_bndes_my$has_bndes)))

# Sanity: shares sum to 1 (or 0 for no-BNDES muni-years) within each muni-year
share_check <- credit[, .(share_sum = sum(s_mjt)), by = .(muni_id, year)]
cat(sprintf("  Share sums (muni-years with BNDES): mean=%.6f, min=%.6f, max=%.6f\n",
            mean(share_check[share_sum > 0]$share_sum),
            min(share_check[share_sum > 0]$share_sum),
            max(share_check[share_sum > 0]$share_sum)))
cat(sprintf("  Share sums = 0 (no BNDES): %d muni-years\n",
            sum(share_check$share_sum == 0)))
rm(share_check)

# --- Step 6: Compute yearly change in shares ---------------------------------

cat("\nStep 6: Computing delta_s_mjt (yearly change in sector shares)...\n")

# Now the lag is over consecutive years (panel is balanced within each muni-sector)
setorderv(credit, c("muni_id", SCOL, "year"))
credit[, delta_s_mjt := s_mjt - shift(s_mjt, n = 1, type = "lag"),
       by = c("muni_id", SCOL)]

# Only set delta_s to NA for the first year (no lag available), not for gaps
# Since the panel is balanced, shift(, 1) always gives the previous year
credit[, yr_lag := shift(year, n = 1, type = "lag"), by = c("muni_id", SCOL)]
n_gap <- sum(!is.na(credit$yr_lag) & (credit$year - credit$yr_lag) != 1)
if (n_gap > 0) {
  cat(sprintf("  WARNING: %d non-consecutive year gaps found (should be 0)\n", n_gap))
} else {
  cat("  Confirmed: all lags are consecutive years (balanced panel)\n")
}
credit[, yr_lag := NULL]

n_delta <- sum(!is.na(credit$delta_s_mjt))
cat(sprintf("  Non-NA delta_s_mjt: %s / %s (%.1f%%)\n",
            format(n_delta, big.mark = ","),
            format(nrow(credit), big.mark = ","),
            100 * n_delta / nrow(credit)))
cat(sprintf("  delta_s_mjt: mean=%.6f, sd=%.6f, min=%.6f, max=%.6f\n",
            mean(credit$delta_s_mjt, na.rm = TRUE),
            sd(credit$delta_s_mjt, na.rm = TRUE),
            min(credit$delta_s_mjt, na.rm = TRUE),
            max(credit$delta_s_mjt, na.rm = TRUE)))

# Verify sum-to-zero within muni-year for delta_s
delta_check <- credit[!is.na(delta_s_mjt),
                      .(delta_sum = sum(delta_s_mjt)), by = .(muni_id, year)]
cat(sprintf("  delta_s sums within muni-year: mean=%.2e, max|sum|=%.2e\n",
            mean(delta_check$delta_sum), max(abs(delta_check$delta_sum))))
rm(delta_check)

# --- Step 7: Diagnostics ----------------------------------------------------

cat("\nStep 7: Diagnostics...\n")
cat(sprintf("  Total rows: %s\n", format(nrow(credit), big.mark = ",")))
cat(sprintf("  Unique municipalities: %s\n", format(uniqueN(credit$muni_id), big.mark = ",")))
cat(sprintf("  Unique %s: %d\n", SCOL, uniqueN(credit[[SCOL]])))
cat(sprintf("  Year range: %s\n", paste(range(credit$year), collapse = "-")))
cat(sprintf("  s_mjt: mean=%.4f, sd=%.4f (including zeros)\n",
            mean(credit$s_mjt), sd(credit$s_mjt)))
cat(sprintf("  s_mjt (positive only): mean=%.4f, sd=%.4f\n",
            mean(credit[s_mjt > 0]$s_mjt), sd(credit[s_mjt > 0]$s_mjt)))
cat(sprintf("  bndes_mjt: mean=%.2f, median=%.2f (including zeros)\n",
            mean(credit$bndes_mjt), median(credit$bndes_mjt)))

# Distribution by sector
cat(sprintf("\n  Credit share by %s (mean s_mjt, including zeros):\n", SCOL))
sec_means <- credit[, .(mean_share = mean(s_mjt),
                         pct_positive = 100 * mean(bndes_mjt > 0),
                         n_obs = .N),
                    by = SCOL]
setorder(sec_means, -mean_share)
for (i in seq_len(nrow(sec_means))) {
  cat(sprintf("    %s: share=%.4f, %%pos=%.1f%%, n=%s\n",
              sec_means[[SCOL]][i],
              sec_means$mean_share[i],
              sec_means$pct_positive[i],
              format(sec_means$n_obs[i], big.mark = ",")))
}

# Panel balance check
obs_per_ms <- credit[, .N, by = c("muni_id", SCOL)]
cat(sprintf("\n  Obs per muni-sector: min=%d, mean=%.1f, max=%d\n",
            min(obs_per_ms$N), mean(obs_per_ms$N), max(obs_per_ms$N)))
if (min(obs_per_ms$N) == max(obs_per_ms$N)) {
  cat("  Panel is perfectly balanced within each muni-sector\n")
}

# --- Step 8: Save ------------------------------------------------------------

cat("\nStep 8: Saving...\n")

setorderv(credit, c("year", "muni_id", SCOL))

if (USE_GROUPS) {
  out_path <- make_output_path("bndes_credit_shares_grouped.qs2")
} else if (USE_POLICY_BLOCKS) {
  out_path <- make_output_path("bndes_credit_shares_policy_block.qs2")
} else {
  out_path <- make_output_path("bndes_credit_shares.qs2")
}
qs_save(credit, out_path)
cat(sprintf("  Saved %s (%.2f MB)\n", out_path, file.size(out_path) / 1024^2))

cat("\nCredit shares complete.\n")
