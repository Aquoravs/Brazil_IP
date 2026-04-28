#!/usr/bin/env Rscript

# ==============================================================================
# Build Firm-Level Instruments (FA_*, dFA_*)
# ==============================================================================
# Constructs firm-level shift-share instruments at the (firm_id, muni_id, year)
# level for first-stage validation of the political-lending channel:
#
#   FA_{f,m,t}  = Sum_p (L_{fp,0} / L_{f,0}) * align_{m,p,t}
#   dFA_{f,m,t} = Sum_p (L_{fp,0} / L_{f,0}) * dAlign_{m,p,t}
#
# Where:
#   L_{fp,0} = affiliated owner count for firm f with party p at baseline
#   L_{f,0}  = total owners of firm f at baseline (including "No party")
#   align_{m,p,t}  = alignment level for party p in muni m at time t
#   dAlign_{m,p,t} = alignment turnover shock for party p in muni m at time t
#
# Baselines use pooled counts across a 4-year window [election - 4, election - 1].
# FA instruments are spread across the 4-year electoral term (constant within).
# dFA instruments are NOT spread — they are non-zero only at inauguration years.
#
# Interaction instruments (MxG, MxP, triple) use combined baseline windows
# that shift when either involved tier inaugurates.
#
# Dependencies:
#   - owner_aff_firm_year_party_2002_2019.qs2 (raw affiliation data)
#   - alignment_shocks.qs2 (script 32)
#   - rais_bndes_reconstructed.fst/.qs2 (script 22)
# ==============================================================================

cat("==============================================================================\n")
cat("Building Firm-Level Instruments (FA, dFA)\n")
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

# --- Configuration -----------------------------------------------------------

aff_path <- make_base_path("raw/david_ra/owner_aff_firm_year_party_2002_2019.qs2")
shocks_path <- make_output_path("alignment_shocks.qs2")
out_path <- make_output_path("firm_level_instruments.qs2")
baseline_out_path <- make_output_path("firm_baseline_exposures.qs2")
summary_path <- make_output_path("firm_level_instruments_summary.csv")

# Baseline windows: pooled counts over [election_year - 4, election_year - 1]
# Data starts 2002, so windows before 2002 are clipped.
# The 2003 gov/pres cycle is dropped (baseline 1998-2001 has no data).
baseline_window_map <- rbindlist(list(
  # Mayor inaugurations (election years: 2004, 2008, 2012, 2016)
  data.table(treatment_year = 2005L, bl_start = 2000L, bl_end = 2003L, tier = "mayor"),
  data.table(treatment_year = 2009L, bl_start = 2004L, bl_end = 2007L, tier = "mayor"),
  data.table(treatment_year = 2013L, bl_start = 2008L, bl_end = 2011L, tier = "mayor"),
  data.table(treatment_year = 2017L, bl_start = 2012L, bl_end = 2015L, tier = "mayor"),
  # Governor/President inaugurations (election years: 2006, 2010, 2014)
  data.table(treatment_year = 2007L, bl_start = 2002L, bl_end = 2005L, tier = "gov_pres"),
  data.table(treatment_year = 2011L, bl_start = 2006L, bl_end = 2009L, tier = "gov_pres"),
  data.table(treatment_year = 2015L, bl_start = 2010L, bl_end = 2013L, tier = "gov_pres")
))

combined_tiers <- c(
  "mayor_gov", "mayor_gov_only",
  "mayor_pres", "mayor_pres_only",
  "triple"
)

# Combined-tier baselines shift whenever any participating tier inaugurates.
# The baseline window is always the previous 4-year electoral window before the
# most recent inauguration that generated the combined state.
combined_baseline_window_map <- CJ(
  treatment_year = c(2005L, 2007L, 2009L, 2011L, 2013L, 2015L, 2017L),
  tier = combined_tiers,
  unique = TRUE
)
combined_baseline_window_map[, `:=`(
  bl_start = treatment_year - 5L,
  bl_end   = treatment_year - 2L
)]

# Term map: single-tier spreading for FA instruments.
# Each inauguration year maps to all years in its 4-year term.
term_map <- rbindlist(list(
  data.table(inaug_year = 2005L, year = 2005L:2008L),
  data.table(inaug_year = 2009L, year = 2009L:2012L),
  data.table(inaug_year = 2013L, year = 2013L:2016L),
  data.table(inaug_year = 2017L, year = 2017L:2020L),
  data.table(inaug_year = 2007L, year = 2007L:2010L),
  data.table(inaug_year = 2011L, year = 2011L:2014L),
  data.table(inaug_year = 2015L, year = 2015L:2018L)
))

# Combined term map: for interaction FA instruments (MxG, MxP, triple).
# The baseline shifts at each inauguration of any involved tier, so interaction
# FA is valid only until the next inauguration. Alternates between mayor and
# gov/pres inaugurations (~2-year stints).
combined_term_map <- rbindlist(list(
  data.table(inaug_year = 2005L, year = 2005L:2006L),
  data.table(inaug_year = 2007L, year = 2007L:2008L),
  data.table(inaug_year = 2009L, year = 2009L:2010L),
  data.table(inaug_year = 2011L, year = 2011L:2012L),
  data.table(inaug_year = 2013L, year = 2013L:2014L),
  data.table(inaug_year = 2015L, year = 2015L:2016L),
  data.table(inaug_year = 2017L, year = 2017L:2017L)
))

build_pooled_baselines <- function(firm_shares_dt, window_map, baseline_type, available_years) {
  out <- vector("list", nrow(window_map))

  for (i in seq_len(nrow(window_map))) {
    ty     <- window_map$treatment_year[i]
    bstart <- window_map$bl_start[i]
    bend   <- window_map$bl_end[i]
    tier_i <- window_map$tier[i]
    if (baseline_type == "2002_fixed") {
      window_years <- intersect(2002L, available_years)
    } else {
      window_years <- intersect(seq(bstart, bend), available_years)
    }

    if (length(window_years) == 0L) {
      cat(sprintf("  WARNING: No data in window %d-%d (treatment %d, %s, %s) -- skipping\n",
                  bstart, bend, ty, tier_i, baseline_type))
      next
    }

    firm_window <- firm_shares_dt[year %in% window_years]

    firm_year_totals <- unique(firm_window[, .(firm_id, year, L_f)])
    firm_L_pooled <- firm_year_totals[,
      .(L_f = sum(L_f, na.rm = TRUE),
        n_baseline_years = uniqueN(year)),
      by = .(firm_id)
    ]
    party_L_pooled <- firm_window[, .(L_fp = sum(L_fp, na.rm = TRUE)),
                                  by = .(firm_id, party)]
    base_i <- merge(party_L_pooled, firm_L_pooled, by = "firm_id")
    base_i[, share_fp := fifelse(L_f > 0, L_fp / L_f, 0)]

    n_window <- length(window_years)
    # Max-binary: 1 if firm had any affiliated owner in any window year, 0 otherwise.
    # Replaces the old fraction-of-years measure (uniqueN(year) / n_window).
    binary_counts_i <- firm_window[,
      .(binary_fp = as.integer(uniqueN(year) > 0L)),
      by = .(firm_id, party)
    ]
    base_i[binary_counts_i, binary_fp := i.binary_fp, on = .(firm_id, party)]
    base_i[is.na(binary_fp), binary_fp := 0]

    base_i[, `:=`(
      treatment_year = ty,
      tier = tier_i,
      baseline_type = baseline_type,
      baseline_years_used = n_window
    )]

    cat(sprintf("  %s treatment=%d, window=%d-%d (%s; used %d yrs: %s): %d firm-party rows\n",
                tier_i, ty, bstart, bend, baseline_type,
                n_window, paste(window_years, collapse = ","),
                nrow(base_i)))
    out[[i]] <- base_i
    rm(firm_year_totals, firm_L_pooled, party_L_pooled, binary_counts_i)
  }

  rbindlist(out, use.names = TRUE, fill = TRUE)
}

# --- Step 1: Load owner affiliations and compute firm-level party shares -----

cat("Step 1: Loading owner affiliations and computing firm-level party shares...\n")

if (!file.exists(aff_path)) {
  stop("Owner affiliation file not found: ", aff_path)
}

aff <- qs_read(aff_path)
setDT(aff)
cat("  Loaded:", nrow(aff), "rows\n")
cat("  Columns:", paste(names(aff), collapse = ", "), "\n")

# Standardise columns
aff[, firm_id := as.integer(firm_id)]
aff[, year := as.integer(year)]
aff[, party := trimws(as.character(party))]
aff[, aff_count := as.integer(aff_owners)]
aff[, share_aff := as.numeric(share_aff_owners)]

# Filter to RAIS range
aff <- aff[year >= 2002L & year <= 2017L]
cat("  After year filter (2002-2017):", nrow(aff), "rows\n")

# Sanity checks on share column
aff[share_aff < 0, share_aff := NA_real_]
aff[share_aff > 1, share_aff := 1]

# Compute total owners per firm-year (L_f) from share data.
# total_owners = aff_count / share_aff gives the firm's total owner count.
# Median across parties is robust to outliers; floor at sum(aff_count).
# This includes "No party" owners in the denominator (by design).
cat("  Computing total owners per firm-year (L_f)...\n")

aff[, total_owners_est := fifelse(
  share_aff > 0 & !is.na(share_aff),
  aff_count / share_aff,
  NA_real_
)]

# Step A: sum(aff_count) per firm-year (GForce-optimized)
firm_totals <- aff[, .(L_f_from_sum = sum(aff_count, na.rm = TRUE)),
                   by = .(firm_id, year)]

# Step B: median(total_owners_est) on valid rows
est_valid <- aff[!is.na(total_owners_est),
                 .(L_f_from_share = as.integer(round(median(total_owners_est)))),
                 by = .(firm_id, year)]

firm_totals[est_valid, L_f_from_share := i.L_f_from_share,
            on = .(firm_id, year)]
rm(est_valid)

# L_f = max of the two methods (floor at sum of aff_count)
firm_totals[, L_f := fifelse(
  !is.na(L_f_from_share),
  pmax(L_f_from_share, L_f_from_sum),
  L_f_from_sum
)]
firm_totals[, c("L_f_from_share", "L_f_from_sum") := NULL]
firm_totals <- firm_totals[L_f > 0L]

cat(sprintf("  Unique firm-years with L_f > 0: %d\n", nrow(firm_totals)))

# Compute firm-party shares: L_fp / L_f
# Exclude "No party" from the numerator: these owners have no alignment shock
# and contribute zero to instruments. They are already included in L_f.
n_no_party <- sum(aff$party == "No party", na.rm = TRUE)
cat(sprintf("  Excluding %d 'No party' rows (%.1f%%) from firm-party shares\n",
            n_no_party, 100 * n_no_party / nrow(aff)))

firm_shares <- aff[party != "No party",
                   .(firm_id, year, party, L_fp = aff_count)]

firm_shares <- merge(firm_shares, firm_totals,
                     by = c("firm_id", "year"), all.x = TRUE)
firm_shares <- firm_shares[!is.na(L_f) & L_f > 0]
firm_shares[, share_fp := L_fp / L_f]

cat(sprintf("  Firm-party shares computed: %d rows\n", nrow(firm_shares)))
cat(sprintf("  share_fp: mean=%.6f, sd=%.6f, min=%.6f, max=%.6f\n",
            mean(firm_shares$share_fp), sd(firm_shares$share_fp),
            min(firm_shares$share_fp), max(firm_shares$share_fp)))

rm(aff, firm_totals)
invisible(gc())

# --- Step 2: Select baseline shares (window-averaged, cycle-specific + 2002-fixed) ---

cat("\nStep 2: Selecting baseline firm-party shares (pooled-count)...\n")

available_years <- sort(unique(firm_shares$year))
cat("  Available years in data:", paste(available_years, collapse = ", "), "\n\n")
cat("  Building single-tier cycle-specific baselines...\n")
baseline_single_cycle <- build_pooled_baselines(
  firm_shares, baseline_window_map, "cycle_specific", available_years
)
cat("\n  Building interaction cycle-specific baselines...\n")
baseline_interact_cycle <- build_pooled_baselines(
  firm_shares, combined_baseline_window_map, "cycle_specific", available_years
)

cat("\n  Building single-tier 2002-fixed baselines...\n")
baseline_single_fixed <- build_pooled_baselines(
  firm_shares, baseline_window_map, "2002_fixed", available_years
)
cat("\n  Building interaction 2002-fixed baselines...\n")
baseline_interact_fixed <- build_pooled_baselines(
  firm_shares, combined_baseline_window_map, "2002_fixed", available_years
)

firm_baseline <- rbindlist(
  list(
    baseline_single_cycle,
    baseline_interact_cycle,
    baseline_single_fixed,
    baseline_interact_fixed
  ),
  use.names = TRUE,
  fill = TRUE
)

# Rename to baseline notation
setnames(firm_baseline,
         c("L_fp", "L_f", "share_fp", "binary_fp"),
         c("L_fp_0", "L_f_0", "share_fp_0", "binary_fp_0"))
if ("year" %in% names(firm_baseline)) firm_baseline[, year := NULL]

cat(sprintf("\n  Combined firm baseline shares: %d rows\n", nrow(firm_baseline)))
cat(sprintf("  Unique firms: %d\n", uniqueN(firm_baseline$firm_id)))
cat(sprintf("  Unique treatment-year x tier x baseline cells: %d\n",
            uniqueN(firm_baseline, by = c("treatment_year", "tier", "baseline_type"))))

baseline_support <- firm_baseline[
  baseline_type == "cycle_specific",
  .(n_firms = uniqueN(firm_id)),
  by = .(tier, treatment_year, n_baseline_years)
][order(tier, treatment_year, n_baseline_years)]
if (nrow(baseline_support) > 0) {
  cat("\n  Baseline-year support by cycle (cycle-specific):\n")
  print(baseline_support)
}

# Verify share constraint: sum_p share_fp_0 <= 1 per (firm_id, treatment_year, baseline_type)
share_sums <- firm_baseline[, .(sum_share = sum(share_fp_0, na.rm = TRUE)),
                            by = .(firm_id, treatment_year, baseline_type)]
n_violate <- sum(share_sums$sum_share > 1 + 1e-10)
cat(sprintf("  sum_p share_fp_0 <= 1 check: %d violations out of %d cells\n",
            n_violate, nrow(share_sums)))
if (n_violate > 0L) {
  cat("  WARNING: Some firms have party shares summing to > 1\n")
  print(head(share_sums[sum_share > 1 + 1e-10], 5))
}
rm(share_sums)

# Compute exposure control: sum_p binary_fp_0 per (firm_id, baseline_type), excl. "No party".
# With max-binary, this is the count of parties with any affiliated owner in the window.
ec_binary <- firm_baseline[party != "No party",
                           .(exposure_control_binary = sum(binary_fp_0, na.rm = TRUE)),
                           by = .(firm_id, baseline_type)]
cat(sprintf("  Exposure control (binary): %d firm×baseline_type cells, mean=%.3f, max=%.3f\n",
            nrow(ec_binary), mean(ec_binary$exposure_control_binary),
            max(ec_binary$exposure_control_binary)))

# Save intermediate baselines for diagnostics
baseline_export <- firm_baseline[, .(firm_id, party, baseline_type,
                                     election_year = treatment_year,
                                     share_fp_0, binary_fp_0, L_fp_0, L_f_0,
                                     n_baseline_years)]
qs_save(baseline_export, baseline_out_path)
cat(sprintf("  Saved baseline exposures: %s (%.2f MB)\n",
            baseline_out_path, file.size(baseline_out_path) / 1024^2))
rm(baseline_export)

rm(firm_shares,
   baseline_single_cycle, baseline_interact_cycle,
   baseline_single_fixed, baseline_interact_fixed)
invisible(gc())

# --- Step 3: Load firm-municipality assignments from reconstructed panel -----
# Load (firm_id, muni_id, year) once; reused in Step 9 for full-panel coverage.

cat("\nStep 3: Loading firm-municipality assignments...\n")

recon_path_fst <- make_output_path("rais_bndes_reconstructed.fst")
recon_path_qs2 <- make_output_path("rais_bndes_reconstructed.qs2")

load_cols <- c("firm_id", "muni_id", "year")

if (file.exists(recon_path_fst) && requireNamespace("fst", quietly = TRUE)) {
  cat("  Loading from fst (column-selective):", basename(recon_path_fst), "\n")
  all_fmy <- fst::read_fst(recon_path_fst, columns = load_cols, as.data.table = TRUE)
} else if (file.exists(recon_path_qs2)) {
  cat("  Loading from qs2:", basename(recon_path_qs2), "\n")
  recon <- qs_read(recon_path_qs2)
  setDT(recon)
  all_fmy <- recon[, ..load_cols]
  rm(recon); invisible(gc())
} else {
  stop("Reconstructed panel not found.\n",
       "  Checked: ", recon_path_fst, "\n",
       "  Checked: ", recon_path_qs2, "\n",
       "  Run script 22 first.")
}

all_fmy[, firm_id := as.integer(firm_id)]
all_fmy[, muni_id := as.integer(muni_id)]
all_fmy[, year := as.integer(year)]
all_fmy <- unique(all_fmy)
all_fmy <- all_fmy[year >= 2002L & year <= 2017L]
# Drop invalid muni_id (0 is not a valid IBGE municipality code)
n_invalid_muni <- sum(all_fmy$muni_id == 0L | is.na(all_fmy$muni_id))
if (n_invalid_muni > 0L) {
  cat(sprintf("  Dropping %d rows with invalid muni_id (0 or NA)\n", n_invalid_muni))
  all_fmy <- all_fmy[!is.na(muni_id) & muni_id > 0L]
}

cat(sprintf("  Full panel: %d unique (firm_id, muni_id, year) triples\n", nrow(all_fmy)))

# For Step 4 expansion: unique (firm_id, muni_id) pairs across all years.
# Using all-time pairs is correct: L_fp/L_f is a firm-level constant, and
# the municipality dimension only enters through alignment shocks. Step 9
# restricts the final output to actual panel observations.
firm_muni <- unique(all_fmy[, .(firm_id, muni_id)])

cat(sprintf("  Unique (firm_id, muni_id) pairs: %d\n", nrow(firm_muni)))
cat(sprintf("  Unique firms: %d, Unique munis: %d\n",
            uniqueN(firm_muni$firm_id), uniqueN(firm_muni$muni_id)))

# --- Step 4: Expand firm baselines with municipality assignments -------------

cat("\nStep 4: Expanding firm baselines across municipalities...\n")

# Merge firm baselines with firm-muni assignments on firm_id.
# A firm in multiple municipalities gets separate rows (alignment shocks
# vary by municipality, but party shares L_fp/L_f are firm-level constants).
merged <- merge(firm_baseline, firm_muni,
                by = "firm_id",
                allow.cartesian = TRUE)

cat(sprintf("  After expansion: %d rows\n", nrow(merged)))
cat(sprintf("  Unique (firm_id, muni_id) pairs with instruments: %d\n",
            uniqueN(merged, by = c("firm_id", "muni_id"))))

rm(firm_baseline, firm_muni)
invisible(gc())

# --- Step 5: Merge alignment shocks -----------------------------------------

cat("\nStep 5: Merging alignment shocks...\n")

if (!file.exists(shocks_path)) {
  stop("Alignment shocks not found: ", shocks_path, "\n  Run script 32 first.")
}

shocks <- qs_read(shocks_path)
setDT(shocks)
cat("  Alignment shocks:", nrow(shocks), "rows\n")

# Single-tier turnover columns
dalign_single_cols <- c("dalign_mayor_party", "dalign_mayor_coalition",
                        "dalign_gov_party", "dalign_gov_coalition",
                        "dalign_pres_party", "dalign_pres_coalition")

# Interaction turnover columns (from script 32)
dalign_interaction_cols <- grep(
  "^dalign_(mayor_gov|mayor_gov_only|mayor_pres|mayor_pres_only|triple)_(party|coalition)$",
  names(shocks), value = TRUE
)

# Single-tier level columns
level_single_cols <- grep(
  "^align_(mayor|gov|pres)_(party|coalition)$",
  names(shocks), value = TRUE
)

# Interaction level columns
level_interaction_cols <- grep(
  "^align_(mayor_gov|mayor_gov_only|mayor_pres|mayor_pres_only|triple)_(party|coalition)$",
  names(shocks), value = TRUE
)

dalign_cols_all <- intersect(c(dalign_single_cols, dalign_interaction_cols), names(shocks))
level_cols_all  <- intersect(c(level_single_cols, level_interaction_cols), names(shocks))

cat("  Single-tier turnover columns:", paste(intersect(dalign_single_cols, names(shocks)), collapse = ", "), "\n")
cat("  Interaction turnover columns:", paste(dalign_interaction_cols, collapse = ", "), "\n")
cat("  Single-tier level columns:", paste(intersect(level_single_cols, names(shocks)), collapse = ", "), "\n")
cat("  Interaction level columns:", paste(level_interaction_cols, collapse = ", "), "\n")

merge_shock_cols <- c(dalign_cols_all, level_cols_all)

merged <- merge(
  merged,
  shocks[, c("muni_id", "party", "year", merge_shock_cols), with = FALSE],
  by.x = c("muni_id", "party", "treatment_year"),
  by.y = c("muni_id", "party", "year"),
  all.x = TRUE
)

n_na <- if (length(dalign_cols_all) > 0) sum(is.na(merged[[dalign_cols_all[1]]])) else 0L
cat(sprintf("  Rows with missing shock data: %d (%.1f%%)\n",
            n_na, 100 * n_na / nrow(merged)))

# Fill missing shocks with 0 (municipality-party combos not in shocks data)
for (dc in dalign_cols_all) merged[is.na(get(dc)), (dc) := 0]
for (lc in level_cols_all)  merged[is.na(get(lc)), (lc) := 0]

rm(shocks)
invisible(gc())

# --- Step 6: Compute firm-level instrument contributions --------------------

cat("\nStep 6: Computing firm-level instrument contributions...\n")

# Tier logic:
#   - Single-tier mayor instruments: only for mayor tier rows
#   - Single-tier gov/pres instruments: only for gov_pres tier rows
#   - Interaction instruments (MxG, MxP, triple): for ALL tier rows
#     because the combined alignment changes at both mayor and gov inaugurations
is_mayor <- merged$tier == "mayor"
is_gp    <- merged$tier == "gov_pres"

# Helper: classify an alignment column as single-tier or interaction
is_interaction_col <- function(col) {
  grepl("(mayor_gov|mayor_pres|triple)", col)
}

# --- 6a: Turnover instruments (dFA) ---
for (dc in dalign_cols_all) {
  wtd_col <- sub("^dalign_", "wtd_dFA_", dc)
  if (is_interaction_col(dc)) {
    # Interaction: valid for both tiers
    merged[, (wtd_col) := share_fp_0 * get(dc)]
  } else if (grepl("^dalign_mayor_", dc)) {
    merged[, (wtd_col) := fifelse(is_mayor, share_fp_0 * get(dc), 0)]
  } else if (grepl("^dalign_(gov|pres)_", dc)) {
    merged[, (wtd_col) := fifelse(is_gp, share_fp_0 * get(dc), 0)]
  } else {
    merged[, (wtd_col) := 0]
  }
}
wtd_dfa_cols <- sub("^dalign_", "wtd_dFA_", dalign_cols_all)

# --- 6b: Levels instruments (FA) ---
for (lc in level_cols_all) {
  wtd_col <- paste0("wtd_FA_", lc)
  if (is_interaction_col(lc)) {
    # Interaction: valid for both tiers
    merged[, (wtd_col) := share_fp_0 * get(lc)]
  } else if (grepl("^align_mayor_", lc)) {
    merged[, (wtd_col) := fifelse(is_mayor, share_fp_0 * get(lc), 0)]
  } else if (grepl("^align_(gov|pres)_", lc)) {
    merged[, (wtd_col) := fifelse(is_gp, share_fp_0 * get(lc), 0)]
  } else {
    merged[, (wtd_col) := 0]
  }
}
wtd_fa_cols <- paste0("wtd_FA_", level_cols_all)

# --- 6c: Binary turnover instruments (dFA_binary) ---
for (dc in dalign_cols_all) {
  wtd_col <- sub("^dalign_", "wtd_dFA_binary_", dc)
  if (is_interaction_col(dc)) {
    merged[, (wtd_col) := binary_fp_0 * get(dc)]
  } else if (grepl("^dalign_mayor_", dc)) {
    merged[, (wtd_col) := fifelse(is_mayor, binary_fp_0 * get(dc), 0)]
  } else if (grepl("^dalign_(gov|pres)_", dc)) {
    merged[, (wtd_col) := fifelse(is_gp, binary_fp_0 * get(dc), 0)]
  } else {
    merged[, (wtd_col) := 0]
  }
}
wtd_dfa_binary_cols <- sub("^dalign_", "wtd_dFA_binary_", dalign_cols_all)

# --- 6d: Binary levels instruments (FA_binary) ---
for (lc in level_cols_all) {
  wtd_col <- paste0("wtd_FA_binary_", lc)
  if (is_interaction_col(lc)) {
    merged[, (wtd_col) := binary_fp_0 * get(lc)]
  } else if (grepl("^align_mayor_", lc)) {
    merged[, (wtd_col) := fifelse(is_mayor, binary_fp_0 * get(lc), 0)]
  } else if (grepl("^align_(gov|pres)_", lc)) {
    merged[, (wtd_col) := fifelse(is_gp, binary_fp_0 * get(lc), 0)]
  } else {
    merged[, (wtd_col) := 0]
  }
}
wtd_fa_binary_cols <- paste0("wtd_FA_binary_", level_cols_all)

# --- Step 7: Aggregate across parties and collapse tiers --------------------

cat("\nStep 7: Aggregating across parties...\n")

all_wtd_cols <- c(wtd_dfa_cols, wtd_fa_cols, wtd_dfa_binary_cols, wtd_fa_binary_cols)

instruments <- merged[, lapply(.SD, sum, na.rm = TRUE),
                      by = .(firm_id, muni_id, treatment_year, tier, baseline_type),
                      .SDcols = all_wtd_cols]

cat(sprintf("  After party aggregation: %d rows\n", nrow(instruments)))

rm(merged)
invisible(gc())

# Rename: wtd_dFA_mayor_party -> dFA_mayor_party, etc.
dfa_cols <- sub("^wtd_dFA_", "dFA_", wtd_dfa_cols)
# Rename: wtd_FA_align_mayor_party -> FA_mayor_party, etc.
# Handle both single-tier (align_mayor_party) and interaction (align_mayor_gov_party)
fa_cols <- sub("^wtd_FA_align_", "FA_", wtd_fa_cols)

# Binary instrument renames
dfa_binary_cols <- sub("^wtd_dFA_binary_", "dFA_binary_", wtd_dfa_binary_cols)
fa_binary_cols  <- sub("^wtd_FA_binary_align_", "FA_binary_", wtd_fa_binary_cols)

setnames(instruments, all_wtd_cols,
         c(dfa_cols, fa_cols, dfa_binary_cols, fa_binary_cols))
all_instrument_cols <- c(dfa_cols, fa_cols)
all_binary_cols     <- c(dfa_binary_cols, fa_binary_cols)

# Classify into single-tier and interaction
fa_single_cols      <- grep("^FA_(mayor|gov|pres)_(party|coalition)$", fa_cols, value = TRUE)
fa_interaction_cols <- setdiff(fa_cols, fa_single_cols)
dfa_single_cols      <- grep("^dFA_(mayor|gov|pres)_(party|coalition)$", dfa_cols, value = TRUE)
dfa_interaction_cols <- setdiff(dfa_cols, dfa_single_cols)

# Binary classification (same patterns with _binary_ prefix)
fa_binary_single_cols      <- grep("^FA_binary_(mayor|gov|pres)_(party|coalition)$", fa_binary_cols, value = TRUE)
fa_binary_interaction_cols <- setdiff(fa_binary_cols, fa_binary_single_cols)
dfa_binary_single_cols      <- grep("^dFA_binary_(mayor|gov|pres)_(party|coalition)$", dfa_binary_cols, value = TRUE)
dfa_binary_interaction_cols <- setdiff(dfa_binary_cols, dfa_binary_single_cols)

cat("  Instrument columns:\n")
cat("    FA single-tier:", paste(fa_single_cols, collapse = ", "), "\n")
cat("    FA interaction:", paste(fa_interaction_cols, collapse = ", "), "\n")
cat("    dFA single-tier:", paste(dfa_single_cols, collapse = ", "), "\n")
cat("    dFA interaction:", paste(dfa_interaction_cols, collapse = ", "), "\n")
cat("    FA_binary single-tier:", paste(fa_binary_single_cols, collapse = ", "), "\n")
cat("    FA_binary interaction:", paste(fa_binary_interaction_cols, collapse = ", "), "\n")
cat("    dFA_binary single-tier:", paste(dfa_binary_single_cols, collapse = ", "), "\n")
cat("    dFA_binary interaction:", paste(dfa_binary_interaction_cols, collapse = ", "), "\n")

# Collapse across tiers by summing (non-overlapping treatment years within each tier)
setnames(instruments, "treatment_year", "year")

instruments <- instruments[, lapply(.SD, sum, na.rm = TRUE),
                           by = .(firm_id, muni_id, year, baseline_type),
                           .SDcols = c(all_instrument_cols, all_binary_cols)]

cat(sprintf("  After tier collapse: %d rows\n", nrow(instruments)))

# --- Step 8: Spread FA instruments across electoral terms -------------------
# dFA instruments stay at inauguration years only (turnover is a discrete event).
# Single-tier FA uses the regular term_map (4-year terms per tier).
# Interaction FA uses the combined_term_map (~2-year stints per inauguration).

cat("\nStep 8: Spreading FA instruments across electoral terms...\n")
cat("  dFA instruments: NOT spread (inauguration-year variation only)\n")
cat("  FA single-tier: spread with regular term_map\n")
cat("  FA interaction: spread with combined_term_map\n\n")

# Split data into components (share-based and binary share the same spreading logic)
key_cols <- c("firm_id", "muni_id", "year", "baseline_type")

dfa_all_cols <- c(dfa_cols, dfa_binary_cols)
dfa_data <- instruments[, c(key_cols, dfa_all_cols), with = FALSE]

fa_single_all <- c(fa_single_cols, fa_binary_single_cols)
fa_single_data <- if (length(fa_single_all) > 0) {
  instruments[, c(key_cols, fa_single_all), with = FALSE]
} else NULL

fa_interact_all <- c(fa_interaction_cols, fa_binary_interaction_cols)
fa_interact_data <- if (length(fa_interact_all) > 0) {
  instruments[, c(key_cols, fa_interact_all), with = FALSE]
} else NULL

rm(instruments)

# --- 8a: Spread single-tier FA with term_map ---
if (!is.null(fa_single_data)) {
  setnames(fa_single_data, "year", "inaug_year")
  fa_single_data <- merge(fa_single_data, term_map, by = "inaug_year",
                          allow.cartesian = TRUE)
  fa_single_data[, inaug_year := NULL]
  fa_single_data <- fa_single_data[, lapply(.SD, sum, na.rm = TRUE),
                                   by = .(firm_id, muni_id, year, baseline_type),
                                   .SDcols = fa_single_all]
  fa_single_data <- fa_single_data[year >= 2002L & year <= 2017L]
  cat(sprintf("  FA single-tier after spreading: %d rows, years: %s\n",
              nrow(fa_single_data),
              paste(sort(unique(fa_single_data$year)), collapse = ", ")))
}

# --- 8b: Spread interaction FA with combined_term_map ---
if (!is.null(fa_interact_data)) {
  setnames(fa_interact_data, "year", "inaug_year")
  fa_interact_data <- merge(fa_interact_data, combined_term_map, by = "inaug_year",
                            allow.cartesian = TRUE)
  fa_interact_data[, inaug_year := NULL]
  fa_interact_data <- fa_interact_data[, lapply(.SD, sum, na.rm = TRUE),
                                       by = .(firm_id, muni_id, year, baseline_type),
                                       .SDcols = fa_interact_all]
  fa_interact_data <- fa_interact_data[year >= 2002L & year <= 2017L]
  cat(sprintf("  FA interaction after spreading: %d rows, years: %s\n",
              nrow(fa_interact_data),
              paste(sort(unique(fa_interact_data$year)), collapse = ", ")))
}

# --- 8c: dFA stays at inauguration years (no spreading) ---
dfa_data <- dfa_data[year >= 2002L & year <= 2017L]
cat(sprintf("  dFA (no spread): %d rows, years: %s\n",
            nrow(dfa_data),
            paste(sort(unique(dfa_data$year)), collapse = ", ")))

# --- 8d: Merge all components ---
# Start with dFA, left-join FA components
instruments <- copy(dfa_data)

if (!is.null(fa_single_data)) {
  instruments <- merge(instruments, fa_single_data,
                       by = key_cols, all = TRUE)
}
if (!is.null(fa_interact_data)) {
  instruments <- merge(instruments, fa_interact_data,
                       by = key_cols, all = TRUE)
}

# Fill NAs with 0 (years without instruments from a given component)
all_final_cols <- c(all_instrument_cols, all_binary_cols)
for (ic in all_final_cols) instruments[is.na(get(ic)), (ic) := 0]

cat(sprintf("  Combined: %d rows, years: %s\n",
            nrow(instruments),
            paste(sort(unique(instruments$year)), collapse = ", ")))

rm(dfa_data, fa_single_data, fa_interact_data)
invisible(gc())

# Merge exposure control (binary) into instruments
instruments <- merge(instruments, ec_binary, by = c("firm_id", "baseline_type"), all.x = TRUE)
instruments[is.na(exposure_control_binary), exposure_control_binary := 0]
rm(ec_binary)

# --- Step 9: Report coverage (do NOT expand to full panel — too large) ------

cat("\nStep 9: Coverage diagnostics (full-panel expansion deferred to script 42)...\n")

# all_fmy was loaded in Step 3 for coverage diagnostics.
cat(sprintf("  Total (firm_id, muni_id, year) in panel: %d\n", nrow(all_fmy)))

baseline_types <- unique(instruments$baseline_type)
for (bt in baseline_types) {
  inst_bt <- instruments[baseline_type == bt]
  # Count how many panel rows have instruments via keyed semi-join
  covered <- all_fmy[inst_bt, nomatch = 0L, on = .(firm_id, muni_id, year)]
  cat(sprintf("  [%s] %d / %d firm-muni-years with instruments (%.1f%%)\n",
              bt, nrow(covered), nrow(all_fmy),
              100 * nrow(covered) / nrow(all_fmy)))
}
rm(all_fmy)
invisible(gc())

cat("  NOTE: Zero-fill for firms without owner data is handled in script 42.\n")

cat(sprintf("  Instrument panel (non-zero rows only): %d rows\n", nrow(instruments)))

# --- Step 10: Diagnostics ---------------------------------------------------

cat("\nStep 10: Diagnostics...\n")

# Support bounds (share-based: FA in [0,1], dFA in [-1,1])
cat("\n  Support bounds (share-based):\n")
for (ic in fa_cols) {
  vals <- instruments[[ic]]
  mn <- min(vals, na.rm = TRUE)
  mx <- max(vals, na.rm = TRUE)
  ok <- mn >= -1e-10 && mx <= 1 + 1e-10
  cat(sprintf("    %s: [%.6f, %.6f] %s\n", ic, mn, mx, if (ok) "PASS" else "FAIL"))
}
for (ic in dfa_cols) {
  vals <- instruments[[ic]]
  mn <- min(vals, na.rm = TRUE)
  mx <- max(vals, na.rm = TRUE)
  ok <- mn >= -1 - 1e-10 && mx <= 1 + 1e-10
  cat(sprintf("    %s: [%.6f, %.6f] %s\n", ic, mn, mx, if (ok) "PASS" else "FAIL"))
}

# Support bounds (max-binary: wider range since sum_p can exceed 1 with multi-party firms)
cat("\n  Support bounds (binary):\n")
n_parties <- length(unique(instruments$baseline_type))  # rough upper bound
for (ic in fa_binary_cols) {
  vals <- instruments[[ic]]
  mn <- min(vals, na.rm = TRUE)
  mx <- max(vals, na.rm = TRUE)
  cat(sprintf("    %s: [%.6f, %.6f]\n", ic, mn, mx))
}
for (ic in dfa_binary_cols) {
  vals <- instruments[[ic]]
  mn <- min(vals, na.rm = TRUE)
  mx <- max(vals, na.rm = TRUE)
  cat(sprintf("    %s: [%.6f, %.6f]\n", ic, mn, mx))
}

# Variation statistics
cat("\n  Variation statistics:\n")
for (ic in all_final_cols) {
  vals <- instruments[[ic]]
  n_nz <- sum(vals != 0, na.rm = TRUE)
  cat(sprintf("    %s: mean=%.6f, sd=%.6f, nonzero=%d/%d (%.1f%%)\n",
              ic, mean(vals, na.rm = TRUE), sd(vals, na.rm = TRUE),
              n_nz, length(vals), 100 * n_nz / length(vals)))
}

# Coverage by baseline type
cat("\n  Coverage by baseline type:\n")
for (bt in baseline_types) {
  sub <- instruments[baseline_type == bt]
  n_total <- nrow(sub)
  # Check if at least one FA or dFA column is non-zero
  has_any <- rowSums(abs(as.matrix(sub[, ..all_instrument_cols]))) > 0
  n_with <- sum(has_any)
  cat(sprintf("    [%s] %d firm-muni-years, %d with non-zero instruments (%.1f%%)\n",
              bt, n_total, n_with, 100 * n_with / n_total))
  cat(sprintf("      Unique firms: %d, Unique munis: %d\n",
              uniqueN(sub$firm_id), uniqueN(sub$muni_id)))
}

# dFA non-zero years check (should only be inauguration years)
cat("\n  dFA non-zero years (should be inauguration years only):\n")
for (dc in dfa_cols) {
  nz_years <- sort(unique(instruments[get(dc) != 0, year]))
  cat(sprintf("    %s: %s\n", dc, paste(nz_years, collapse = ", ")))
}

# --- Step 11: Save -----------------------------------------------------------

cat("\nStep 11: Saving...\n")

setorder(instruments, baseline_type, year, muni_id, firm_id)

qs_save(instruments, out_path)

summ <- rbindlist(lapply(unique(instruments$baseline_type), function(bt) {
  sub <- instruments[baseline_type == bt]
  data.table(
    baseline_type    = bt,
    n_rows           = nrow(sub),
    n_firms          = uniqueN(sub$firm_id),
    n_munis          = uniqueN(sub$muni_id),
    n_years          = uniqueN(sub$year),
    frac_nonzero_FA  = mean(rowSums(abs(as.matrix(sub[, ..fa_cols]))) > 0),
    frac_nonzero_dFA = mean(rowSums(abs(as.matrix(sub[, ..dfa_cols]))) > 0),
    frac_nonzero_FA_binary  = mean(rowSums(abs(as.matrix(sub[, ..fa_binary_cols]))) > 0),
    frac_nonzero_dFA_binary = mean(rowSums(abs(as.matrix(sub[, ..dfa_binary_cols]))) > 0)
  )
}))

fwrite(summ, summary_path)

cat(sprintf("  Saved %s (%.2f MB)\n", out_path, file.size(out_path) / 1024^2))
cat(sprintf("  Saved %s\n", summary_path))

cat("\nFirm-level instruments complete.\n")
