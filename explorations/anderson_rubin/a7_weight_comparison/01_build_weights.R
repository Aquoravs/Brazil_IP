# ==============================================================================
# 01_build_weights.R
#
# A7 Step 1 — Candidate weight construction (Tier C: 6 weights) plus loaded
# Tier A replication anchor at the policy_block aggregation margin.
#
# Plan: logs/plans/2026-05-05_a7-revised-weight-comparison.md
# Step 0 context: explorations/anderson_rubin/diagnostics/output/a7_step0_report.md
# Aggregation margin: policy_block only (4 active blocks: Agro, Ind, Infra, Serv)
# Baseline windows: cycle_specific only
#   mayor:   2002-03 / 04-07 / 08-11 / 12-15  -> treatment 2005/2009/2013/2017
#   gov_pres: 2002-05 / 06-09 / 10-13         -> treatment 2007/2011/2015
#
# Tier C weights (numerators carry alignment from matched firms; denominators
# sum over ALL RAIS firms in muni m, regardless of affiliation status):
#   w_owners_muni_univ         L_mjp / L_mB_univ
#   w_emp_muni_univ            L_mjp_emp / E_mB_univ                (n_emp > 0 floor)
#   w_firm_muni_univ           L_mjp_firm / n_firms_rais_muni
#   w_binary_muni_univ         L_mjp_binary / n_firms_rais_muni
#   w_firm_empshare_floor      sum_f emp_share_floor_f * owner_party_share_f
#   w_binary_empshare_floor    sum_f emp_share_floor_f * 1[owner_party_share_f > 0]
# emp_share_floor_f = n_f_floored / sum_{f' in muni} n_{f'}_floored
# n_f_floored = pmax(n_employees, owner_count, 1) where owner_count = total_owners
# for matched firms and 0 for unmatched.
#
# Tier A replication anchor: w_owners_sec_match loaded from
# data/processed/sector_exposure_weights_owner_policy_block.qs2 (column
# w_mjp_owners). HARD GATE: muni-mayor-coalition instrument computed from this
# anchor must match production Z_mayor_coalition within 1e-6.
#
# Outputs:
#   output/a7_weights_panel.qs2      — keyed by (muni_id, policy_block, party,
#                                       treatment_year, tier, baseline_type),
#                                       7 weight columns
#   output/a7_instruments_panel.qs2  — muni-year instrument vectors
#                                       Z_<weight_id>_mayor_coalition,
#                                       Z_<weight_id>_gov_coalition, and
#                                       Z_<weight_id>_pres_coalition for each
#                                       of the 6 Tier C weights + replication
#                                       anchor for verification (21 + 3 = 24
#                                       instrument columns total: 7 weights ×
#                                       3 alignment tiers).
#
# Hard constraints: INV-15 (packages at top), INV-16 (no absolute paths),
# INV-19 (no setwd, rm(list=ls), install.packages, attach/detach).
# No random sampling -> no set.seed() per INV-14.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Packages (INV-15: all at top)
# ------------------------------------------------------------------------------
library(data.table)
library(qs2)
library(here)

HAS_FST <- requireNamespace("fst", quietly = TRUE)
if (HAS_FST) library(fst)

setDTthreads(0L)

# ------------------------------------------------------------------------------
# 2. Paths via here::here() (INV-16: no absolute paths)
# ------------------------------------------------------------------------------
PROCESSED_DIR <- here::here("data", "processed")
RAW_DIR       <- here::here("data", "raw")
OUTPUT_DIR    <- here::here(
  "explorations", "anderson_rubin", "a7_weight_comparison", "output"
)

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  message("Created output directory: ", OUTPUT_DIR)
}

path_recon_fst    <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst")
path_recon_qs2    <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.qs2")
path_pb_cw        <- file.path(PROCESSED_DIR, "policy_block_mapping.qs2")
path_owner_aff    <- file.path(RAW_DIR, "david_ra", "owner_aff_firm_year_party_2002_2019.qs2")
path_align        <- file.path(PROCESSED_DIR, "alignment_shocks.qs2")
path_anchor       <- file.path(PROCESSED_DIR, "sector_exposure_weights_owner_policy_block.qs2")
path_prod_inst    <- file.path(PROCESSED_DIR, "shift_share_instruments_policy_block.qs2")

path_out_weights      <- file.path(OUTPUT_DIR, "a7_weights_panel.qs2")
path_out_instruments  <- file.path(OUTPUT_DIR, "a7_instruments_panel.qs2")

# ------------------------------------------------------------------------------
# 3. Constants
# ------------------------------------------------------------------------------
ACTIVE_BLOCKS <- c("Agro", "Ind", "Infra", "Serv")

# Cycle-specific baseline windows (from script 33).
baseline_window_map <- rbindlist(list(
  data.table(treatment_year = 2005L, bl_start = 2000L, bl_end = 2003L, tier = "mayor"),
  data.table(treatment_year = 2009L, bl_start = 2004L, bl_end = 2007L, tier = "mayor"),
  data.table(treatment_year = 2013L, bl_start = 2008L, bl_end = 2011L, tier = "mayor"),
  data.table(treatment_year = 2017L, bl_start = 2012L, bl_end = 2015L, tier = "mayor"),
  data.table(treatment_year = 2007L, bl_start = 2002L, bl_end = 2005L, tier = "gov_pres"),
  data.table(treatment_year = 2011L, bl_start = 2006L, bl_end = 2009L, tier = "gov_pres"),
  data.table(treatment_year = 2015L, bl_start = 2010L, bl_end = 2013L, tier = "gov_pres")
))

# Term spreading map (from script 34): inaug_year -> 4-year term
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

# Tier C weight identifiers (used as column infix in instrument names)
TIERC_WEIGHTS <- c(
  "owners_muni_univ",
  "emp_muni_univ",
  "firm_muni_univ",
  "binary_muni_univ",
  "firm_empshare_floor",
  "binary_empshare_floor"
)

# Replication anchor weight ID (Tier A; loaded, not built fresh)
ANCHOR_WEIGHT <- "owners_sec_match"

# Replication tolerance gate
REPL_TOL <- 1e-6

# ------------------------------------------------------------------------------
# 4. Load policy_block crosswalk
# ------------------------------------------------------------------------------
message("Loading policy_block crosswalk...")
crosswalk <- setDT(qs_read(path_pb_cw))
stopifnot(all(c("cnae_section", "policy_block") %in% names(crosswalk)))
message(sprintf("  Crosswalk loaded: %d cnae sections.", nrow(crosswalk)))

# ------------------------------------------------------------------------------
# 5. Load reconstructed RAIS panel (full RAIS firm universe)
#    Universe denominator must include ALL RAIS firms in muni m, regardless of
#    affiliation status, that are mapped to active policy blocks.
# ------------------------------------------------------------------------------
COLS_NEEDED <- c("firm_id", "muni_id", "year", "cnae_section", "n_employees")

message("Loading reconstructed RAIS-BNDES panel (column-selective)...")
if (HAS_FST && file.exists(path_recon_fst)) {
  message("  Source: fst — ", basename(path_recon_fst))
  panel <- fst::read_fst(path_recon_fst, columns = COLS_NEEDED, as.data.table = TRUE)
} else if (file.exists(path_recon_qs2)) {
  message("  Source: qs2 — ", basename(path_recon_qs2))
  raw <- qs_read(path_recon_qs2)
  setDT(raw)
  missing_cols <- setdiff(COLS_NEEDED, names(raw))
  if (length(missing_cols) > 0L) {
    stop("qs2 file missing columns: ", paste(missing_cols, collapse = ", "))
  }
  panel <- raw[, .SD, .SDcols = COLS_NEEDED]
  rm(raw); invisible(gc())
} else {
  stop("Neither fst nor qs2 reconstructed panel found.")
}

panel[, firm_id := as.integer(firm_id)]
panel[, muni_id := as.integer(muni_id)]
panel[, year := as.integer(year)]
panel[, n_employees := as.numeric(n_employees)]

message(sprintf("  Loaded: %s firm-years.", format(nrow(panel), big.mark = ",")))

# Drop invalid muni_id and missing/empty cnae_section
panel <- panel[!is.na(muni_id) & muni_id > 0L &
               !is.na(cnae_section) & nzchar(cnae_section)]

# Merge policy_block; restrict to active blocks (drop XX and unmapped)
panel <- merge(
  panel,
  crosswalk[, .(cnae_section, policy_block)],
  by = "cnae_section",
  all.x = TRUE
)
panel <- panel[!is.na(policy_block) & policy_block %in% ACTIVE_BLOCKS]

# Restrict years to baseline window range (2000-2017 covers all cycles)
panel <- panel[year >= 2000L & year <= 2017L]

# Deduplicate to one (firm_id, muni_id, year) row keeping the policy_block
# (matches script 31's deduplicate-on-firm-muni-year convention).
panel <- unique(panel, by = c("firm_id", "muni_id", "year"))

message(sprintf(
  "  After active-block filter: %s firm-muni-year rows across %s munis.",
  format(nrow(panel), big.mark = ","),
  format(uniqueN(panel$muni_id), big.mark = ",")
))

# ------------------------------------------------------------------------------
# 6. Load owner affiliation data and compute total_owners per firm-year
#    (mirroring script 31's logic).
#
# Aff data has NO muni_id; muni is recovered from RAIS via firm-year join.
# A firm operating in multiple munis spreads its owner counts across them
# (allow.cartesian = TRUE in the merge below).
# ------------------------------------------------------------------------------
message("Loading owner affiliation data...")
aff <- qs_read(path_owner_aff)
setDT(aff)
message(sprintf("  Loaded: %s rows, %d cols.",
                format(nrow(aff), big.mark = ","), ncol(aff)))

aff[, year := as.integer(year)]
aff[, firm_id := as.integer(firm_id)]
aff[, party := trimws(as.character(party))]
aff[, share_aff_owners := as.numeric(share_aff_owners)]
aff[, aff_owners := as.integer(aff_owners)]

# Year filter to baseline window range
aff <- aff[year >= 2000L & year <= 2017L]

# Sanity: clamp share to [0, 1] (mirrors script 31)
aff[share_aff_owners < 0, share_aff_owners := NA_real_]
aff[share_aff_owners > 1, share_aff_owners := 1]

# Estimate total_owners per firm-party-year via aff_count / share, then
# aggregate to firm-year using script 31's two-step formula:
#   total_owners = max( median(round(aff_count/share)) , sum(aff_count) )
aff[, total_owners_est := fifelse(
  share_aff_owners > 0 & !is.na(share_aff_owners),
  aff_owners / share_aff_owners,
  NA_real_
)]

firm_owners_sum <- aff[, .(
  total_owners_from_sum = sum(aff_owners, na.rm = TRUE)
), by = .(firm_id, year)]

firm_owners_share <- aff[!is.na(total_owners_est),
                         .(total_owners_from_share = as.integer(round(median(total_owners_est)))),
                         by = .(firm_id, year)]

firm_owners <- merge(firm_owners_sum, firm_owners_share,
                     by = c("firm_id", "year"), all.x = TRUE)
firm_owners[, total_owners := fifelse(
  !is.na(total_owners_from_share),
  pmax(total_owners_from_share, total_owners_from_sum),
  total_owners_from_sum
)]
firm_owners[, c("total_owners_from_share", "total_owners_from_sum") := NULL]
firm_owners <- firm_owners[total_owners > 0L]

message(sprintf("  Unique firm-years with positive total_owners: %s",
                format(nrow(firm_owners), big.mark = ",")))

# Drop the per-row total_owners_est now that firm_owners is built
aff[, total_owners_est := NULL]
invisible(gc())

# ------------------------------------------------------------------------------
# 7. Build the per-firm-muni-year denominator base table
#    (one row per firm-muni-year-block + n_employees + owner_count, where
#    owner_count = total_owners for matched firms, 0 for unmatched).
# ------------------------------------------------------------------------------
message("Joining total_owners onto RAIS panel...")
firm_base <- merge(
  panel,
  firm_owners[, .(firm_id, year, total_owners)],
  by = c("firm_id", "year"),
  all.x = TRUE
)
# owner_count: 0 for unmatched firms (script 31 convention for the universe)
firm_base[, owner_count := fifelse(is.na(total_owners), 0L, as.integer(total_owners))]

# n_f_floored = pmax(n_employees, owner_count, 1)
firm_base[, n_employees_clean := fifelse(
  is.finite(n_employees) & !is.na(n_employees) & n_employees > 0,
  n_employees,
  0
)]
firm_base[, n_f_floored := pmax(n_employees_clean, owner_count, 1)]

n_matched <- sum(!is.na(firm_base$total_owners))
message(sprintf("  RAIS firms matched to owner data: %s / %s (%.1f%%)",
                format(n_matched, big.mark = ","),
                format(nrow(firm_base), big.mark = ","),
                100 * n_matched / nrow(firm_base)))

# Free panel
rm(panel); invisible(gc())

# ------------------------------------------------------------------------------
# 8. Build the per-firm-muni-year-party numerator base table.
#    Aff is firm-year-party; expand to firm-muni-year-party by joining
#    onto the firm_base universe (allow.cartesian = TRUE).
# ------------------------------------------------------------------------------
message("Building firm-muni-year-party numerator base...")

# Drop "No party" from numerator (script 31 convention; these owners have no
# alignment shock and thus contribute 0 to Z).
aff_align <- aff[party != "No party"]
message(sprintf("  Dropped %s 'No party' rows; kept %s aligned-party rows.",
                format(nrow(aff) - nrow(aff_align), big.mark = ","),
                format(nrow(aff_align), big.mark = ",")))

# Compute owner_party_share for each row using the aggregated total_owners
aff_align <- merge(aff_align,
                   firm_owners[, .(firm_id, year, total_owners)],
                   by = c("firm_id", "year"),
                   all.x = TRUE)
aff_align[, owner_party_share := fifelse(
  !is.na(total_owners) & total_owners > 0,
  aff_owners / total_owners,
  NA_real_
)]
aff_align <- aff_align[!is.na(owner_party_share) & owner_party_share > 0]

# Join firm-muni-year coordinates (with policy_block + n_employees + n_f_floored)
# onto the aligned aff. allow.cartesian: a firm operating in multiple munis
# carries its owners across them (script 31 convention).
firm_party_base <- merge(
  aff_align[, .(firm_id, year, party, aff_owners, owner_party_share)],
  firm_base[, .(firm_id, muni_id, year, policy_block, n_employees_clean, n_f_floored)],
  by = c("firm_id", "year"),
  all.x = FALSE,        # only keep aligned rows that match RAIS
  allow.cartesian = TRUE
)
firm_party_base <- firm_party_base[!is.na(policy_block)]

message(sprintf("  Numerator base (firm, muni, year, party): %s rows",
                format(nrow(firm_party_base), big.mark = ",")))

rm(aff, aff_align); invisible(gc())

# ------------------------------------------------------------------------------
# 9. Build per-(muni, year) firm-base aggregates needed for Tier C denominators.
#    Pool first across baseline window; then divide once.
#
# We will materialize denominators per (muni, policy_block, treatment_year, tier)
# by pooling firm-base counts across the baseline window.
# ------------------------------------------------------------------------------

# Pre-compute per-(firm_id, muni_id, year) emp-share-floor. This is firm-level
# but the share denominator is over ALL firms in muni m at year t — so the
# share is computed AFTER we restrict to the baseline window. We therefore
# carry the floor weights and total_emp_floor_muni at the muni-year level.

# For empshare_floor: emp_share_floor_f = n_f_floored / sum_{f' in muni m, year t} n_{f'}_floored.
# Since we pool across baseline-window years FIRST then compute weights, the
# correct interpretation per the plan is to compute the firm-level signal
# year-by-year (using year-specific muni totals), then pool the resulting
# per-firm contributions across the baseline window.
#
# That is the mathematically defensible reading: the empshare_floor weight is
# a firm-share-weighted average of party signal at year t; pooling sums these
# yearly contributions into one baseline summary, mirroring the script-33
# pool-counts-then-divide convention applied to the (already-share-weighted)
# numerator.

# Step 9a: muni-year totals over ALL RAIS firms in active blocks
muni_year_totals <- firm_base[, .(
  L_mB_univ_year      = sum(owner_count, na.rm = TRUE),                                       # for owners weight
  E_mB_univ_year      = sum(n_employees_clean[n_employees_clean > 0]),                        # for emp weight (n_emp > 0 floor)
  n_firms_rais_year   = .N,                                                                   # for firm/binary weights
  total_floor_muni_year = sum(n_f_floored, na.rm = TRUE)                                      # for empshare_floor
), by = .(muni_id, year)]

setkey(muni_year_totals, muni_id, year)

# Step 9b: per-(muni, year, policy_block) numerator pieces from firm_party_base.
# Aggregate across firms within a (muni, year, policy_block, party) cell:
#   L_mjp_year       = sum(aff_owners)               (owners numerator)
#   L_mjp_emp_year   = sum(n_employees * owner_party_share | n_emp > 0)
#   L_mjp_firm_year  = sum(owner_party_share)        (continuous, equal-firm)
#   L_mjp_binary_year= sum(1[owner_party_share > 0])
# For empshare_floor variants we need the firm-level share, which depends on
# muni-year total floor. We attach total_floor_muni_year (computed in 9a) and
# compute the per-firm contribution n_f_floored / total_floor_muni_year *
# party_signal_f, then sum across firms.
firm_party_base <- merge(
  firm_party_base,
  muni_year_totals[, .(muni_id, year, total_floor_muni_year)],
  by = c("muni_id", "year"),
  all.x = TRUE
)

# emp_party_contrib: only firms with n_employees > 0 contribute (mirrors script 31)
firm_party_base[, emp_party_contrib := fifelse(
  n_employees_clean > 0,
  n_employees_clean * owner_party_share,
  0
)]

# empshare_floor per-firm contributions
firm_party_base[, emp_share_floor_f := fifelse(
  total_floor_muni_year > 0,
  n_f_floored / total_floor_muni_year,
  0
)]
firm_party_base[, contrib_floor_firm   := emp_share_floor_f * owner_party_share]
firm_party_base[, contrib_floor_binary := emp_share_floor_f * as.integer(owner_party_share > 0)]

# Aggregate to (muni, policy_block, party, year) - per-year numerator pieces
muni_block_party_year <- firm_party_base[, .(
  L_mjp_year        = sum(aff_owners, na.rm = TRUE),
  L_mjp_emp_year    = sum(emp_party_contrib, na.rm = TRUE),
  L_mjp_firm_year   = sum(owner_party_share, na.rm = TRUE),
  L_mjp_binary_year = sum(as.integer(owner_party_share > 0), na.rm = TRUE),
  N_floor_firm_year   = sum(contrib_floor_firm, na.rm = TRUE),     # already share-weighted
  N_floor_binary_year = sum(contrib_floor_binary, na.rm = TRUE)
), by = .(muni_id, policy_block, party, year)]

message(sprintf("  Numerator panel (muni, block, party, year): %s rows",
                format(nrow(muni_block_party_year), big.mark = ",")))

rm(firm_party_base); invisible(gc())

# Step 9c: per-(muni, year, policy_block) denominator pieces from firm_base
muni_block_year_denoms <- firm_base[, .(
  L_mB_univ_block_year      = sum(owner_count, na.rm = TRUE),                                # for owners (block-specific NOT used; muni-level used)
  E_mB_univ_block_year      = sum(n_employees_clean[n_employees_clean > 0]),                 # block-specific (NOT used; muni-level used)
  n_firms_rais_block_year   = .N,                                                            # block-specific (NOT used; muni-level used)
  total_floor_block_year    = sum(n_f_floored, na.rm = TRUE)                                 # block-specific (NOT used; muni-level used)
), by = .(muni_id, policy_block, year)]
# NOTE: per the plan, denominators sum over ALL RAIS firms in muni m (NOT
# restricted to the same policy_block). We use muni_year_totals (9a) for
# denominators below; the block-specific aggregates above are kept only for
# diagnostic/debug purposes and not used in the weight formula.
rm(muni_block_year_denoms); invisible(gc())

rm(firm_base); invisible(gc())

# ------------------------------------------------------------------------------
# 10. For each baseline window, pool numerator counts across the window and
#     divide by the pooled denominator.
#
# Pooling convention (script 33 pool-counts-then-divide):
#   L_mjp_pooled       = sum_{t in window} L_mjp_year(t)
#   L_mB_univ_pooled   = sum_{t in window} L_mB_univ_year(muni, t)
#   weight             = L_mjp_pooled / L_mB_univ_pooled
#
# This preserves sum-to-1 across parties within (muni, block) at the baseline.
# ------------------------------------------------------------------------------
message("\nPooling weights across baseline windows...")

build_baseline_weights <- function(treatment_year, bl_start, bl_end, tier) {
  window_years <- seq.int(bl_start, bl_end)

  # Filter numerators and denominators to window
  num_w <- muni_block_party_year[year %in% window_years]
  den_w <- muni_year_totals[year %in% window_years]

  # Pool numerators across years to (muni, block, party)
  num_pooled <- num_w[, .(
    L_mjp        = sum(L_mjp_year, na.rm = TRUE),
    L_mjp_emp    = sum(L_mjp_emp_year, na.rm = TRUE),
    L_mjp_firm   = sum(L_mjp_firm_year, na.rm = TRUE),
    L_mjp_binary = sum(L_mjp_binary_year, na.rm = TRUE),
    N_floor_firm   = sum(N_floor_firm_year, na.rm = TRUE),
    N_floor_binary = sum(N_floor_binary_year, na.rm = TRUE)
  ), by = .(muni_id, policy_block, party)]

  # Pool muni-level denominators across years to (muni)
  # The denominators sum over ALL RAIS firms in muni m, regardless of block.
  den_pooled <- den_w[, .(
    L_mB_univ        = sum(L_mB_univ_year, na.rm = TRUE),
    E_mB_univ        = sum(E_mB_univ_year, na.rm = TRUE),
    n_firms_rais_muni = sum(n_firms_rais_year, na.rm = TRUE),
    total_floor_muni  = sum(total_floor_muni_year, na.rm = TRUE)
  ), by = .(muni_id)]

  # Note for empshare_floor: N_floor_firm and N_floor_binary were already
  # share-weighted at the year level (each firm's contribution divided by the
  # YEAR-specific total_floor_muni_year). Pooling those across years gives a
  # SUM of yearly share-weighted contributions, which is the correct baseline
  # signal for the empshare_floor weights — analogous to summing yearly
  # owner-counts before dividing once.
  #
  # However, by pooling counts then dividing once, the empshare_floor weights
  # do NOT have a denominator further applied (the share-weighting was done
  # at the firm-year level using the year-specific muni total). Their pooled
  # value should be divided by the number of years in the window to obtain
  # the average share-weighted signal — but per script 33's convention
  # (pool-counts-then-divide-once), we keep the SUM across years and let it
  # stand as the baseline signal. Since the same window-length applies to all
  # munis in the same baseline cell, this is a simple rescaling that does not
  # affect the weight rankings or correlations. To preserve the within-window
  # comparability AND the sum-to-1 property, we divide by the number of years
  # in the window to bring the empshare_floor weight onto the same scale as a
  # single-year share.
  n_years_in_window <- length(window_years)

  # Cartesian merge: every (muni, block, party) gets the muni-level denoms
  out <- merge(num_pooled, den_pooled, by = "muni_id", all.x = TRUE)

  # Compute weights
  out[, w_owners_muni_univ := fifelse(L_mB_univ > 0, L_mjp / L_mB_univ, 0)]
  out[, w_emp_muni_univ    := fifelse(E_mB_univ > 0, L_mjp_emp / E_mB_univ, 0)]
  out[, w_firm_muni_univ   := fifelse(n_firms_rais_muni > 0, L_mjp_firm / n_firms_rais_muni, 0)]
  out[, w_binary_muni_univ := fifelse(n_firms_rais_muni > 0, L_mjp_binary / n_firms_rais_muni, 0)]

  # ---- empshare_floor weights: cross-cycle rescaling caveat (FIX 3) ----
  # We divide the pooled share-weighted sum by n_years_in_window to recover the
  # average-yearly-signal interpretation. This keeps sum-to-1 holding within a
  # window IF (and only if) the firm-set is constant across the window's years
  # — see Step 11 cell-by-cell verification (FIX 2) which hard-stops if any
  # cell violates this.
  #
  # Cross-cycle pooling caveat:
  #   * Within a single mayor cycle (all 4 years), the divisor is the same
  #     scalar (4) for every (muni, block, party) cell — Pearson correlations
  #     across weights are preserved EXACTLY within the cycle.
  #   * Across cycles, however, the divisor differs by tier and window:
  #       - mayor windows (2000-03, 04-07, 08-11, 12-15): divisor = 4
  #       - gov_pres window 2002-05: divisor = 4
  #       - gov_pres window 2006-09: divisor = 4
  #       - gov_pres window 2010-13: divisor = 4
  #     All current windows are length 4, so within the present plan the
  #     divisor is uniform. BUT if a window of different length (e.g. an
  #     edge-case 2-year window for 2002-03 mayor) is later added, cross-
  #     cycle pooled correlations may be slightly distorted. The within-cycle
  #     correlation matrix is therefore the canonical reference; cross-cycle
  #     pooled stats (if produced) carry an asterisk.
  #   * This is a documentation note — no code-logic change. The within-cycle
  #     sum-to-1 invariant is checked in Section 11.
  out[, w_firm_empshare_floor   := N_floor_firm   / n_years_in_window]
  out[, w_binary_empshare_floor := N_floor_binary / n_years_in_window]

  # Metadata
  out[, treatment_year := as.integer(treatment_year)]
  out[, tier := tier]
  out[, baseline_type := "cycle_specific"]
  out[, baseline_yrs := n_years_in_window]

  out[, .(
    muni_id, policy_block, party, treatment_year, tier, baseline_type, baseline_yrs,
    L_mjp, L_mjp_emp, L_mjp_firm, L_mjp_binary, N_floor_firm, N_floor_binary,
    L_mB_univ, E_mB_univ, n_firms_rais_muni, total_floor_muni,
    w_owners_muni_univ, w_emp_muni_univ, w_firm_muni_univ, w_binary_muni_univ,
    w_firm_empshare_floor, w_binary_empshare_floor
  )]
}

baseline_list <- vector("list", nrow(baseline_window_map))
for (i in seq_len(nrow(baseline_window_map))) {
  ty     <- baseline_window_map$treatment_year[i]
  bs     <- baseline_window_map$bl_start[i]
  be     <- baseline_window_map$bl_end[i]
  tier_i <- baseline_window_map$tier[i]
  message(sprintf("  %s tier, treatment=%d, window=%d-%d", tier_i, ty, bs, be))
  baseline_list[[i]] <- build_baseline_weights(ty, bs, be, tier_i)
}

weights_panel <- rbindlist(baseline_list, use.names = TRUE)
rm(baseline_list); invisible(gc())

message(sprintf("\n  Tier C weights panel: %s rows",
                format(nrow(weights_panel), big.mark = ",")))
message(sprintf("  Unique munis: %s",
                format(uniqueN(weights_panel$muni_id), big.mark = ",")))
message(sprintf("  policy_blocks: %s",
                paste(sort(unique(weights_panel$policy_block)), collapse = ", ")))
message(sprintf("  Tiers: %s",
                paste(sort(unique(weights_panel$tier)), collapse = ", ")))
message(sprintf("  Treatment years: %s",
                paste(sort(unique(weights_panel$treatment_year)), collapse = ", ")))

# ------------------------------------------------------------------------------
# 11. Sum-to-1 verification (FIX 2 — HARD STOP; revised after Round 1 finding)
#
# Per the plan (line 219), the invariant is sum_p w(m, b, p, t) <= 1 + tol
# per cell — an UPPER BOUND, not exact equality. Reason: the Tier C
# numerator carries party-owner counts from MATCHED firms only, while the
# muni-wide denominator includes ALL RAIS firms (matched + unmatched, with
# unmatched contributing 0 to the owner-count denominator). So the sum
# across parties within (m, b, t) equals
#   (matched-firm party-owner counts in block b) / (muni-wide total owner
#    counts of matched firms across ALL blocks, summed across the window)
# which is ≤ 1 because (a) matched-firm coverage is partial and (b) the
# denominator pools across ALL muni blocks, not just b.
#
# Sum-to-1 EXACTLY would only hold if the muni's owner-counts were entirely
# captured by block b in the window — true in <3% of cells (verified post-
# hoc against the loaded sector anchor: only 2.3% of cells satisfy
# |sum - 1| < 1e-6). The structural invariant the plan calls "sum to 1"
# is the upper bound: no cell can exceed 1.
#
# What FIX 2 must hard-stop on:
#   (i) sum > 1 + tol — would mean numerator exceeds denominator, which is
#       structurally impossible under the muni-universe denominator; if
#       this happens, the construction is broken.
#   (ii) For w_firm_empshare_floor: same upper-bound check. The cross-cycle
#        rescaling caveat (FIX 3) means cells where the firm-set is non-
#        constant across baseline-window years could theoretically push
#        sum > 1 if the divisor (n_years_in_window) is too small. The check
#        below catches this.
# We DO NOT hard-stop on sum < 1 — that is structurally expected from
# matched-only partial coverage of muni totals.
# ------------------------------------------------------------------------------
message("\nSum-to-1 upper-bound verification (cell-by-cell, hard stop on sum > 1 + tol):")
SUM_KEYS <- c("muni_id", "policy_block", "treatment_year", "tier", "baseline_type")
SUM_TOL  <- 1e-6

check_sum_to_1_upper <- function(dt, col, label, tol = SUM_TOL,
                                 hard_stop = TRUE) {
  s <- dt[, .(sum_w = sum(get(col), na.rm = TRUE)), by = SUM_KEYS]
  active       <- s[sum_w > tol]
  n_total      <- nrow(s)
  n_active     <- nrow(active)
  max_s        <- if (n_total > 0L) max(s$sum_w, na.rm = TRUE) else NA_real_
  n_above_1    <- sum(s$sum_w > 1 + tol, na.rm = TRUE)
  # Diagnostic-only: how often does sum equal 1 exactly?
  n_at_1       <- sum(abs(active$sum_w - 1) < tol, na.rm = TRUE)
  message(sprintf(
    "  %-30s n_active=%d, max_sum=%.10f, viol(>1+%.0e): %d, exactly_at_1: %d (%.1f%%)",
    label, n_active, max_s, tol, n_above_1, n_at_1,
    100 * n_at_1 / max(n_active, 1L)
  ))
  if (hard_stop && n_above_1 > 0L) {
    message("    >>> SAMPLE OVER-1 VIOLATIONS (top 10 by sum): <<<")
    over <- s[sum_w > 1 + tol]
    print(over[order(-sum_w)][seq_len(min(10L, .N))])
    stop(sprintf(
      "Upper-bound hard-stop FAILED for %s: %d cells have sum > 1 + %.0e. STOP per FIX 2.",
      label, n_above_1, tol
    ))
  }
  invisible(list(max = max_s, n_above_1 = n_above_1, n_at_1 = n_at_1,
                 n_active = n_active, n_violate = n_above_1))
}

# Hard stop on upper-bound violation (sum > 1 + tol)
res_owners <- check_sum_to_1_upper(weights_panel, "w_owners_muni_univ",      "w_owners_muni_univ")
res_emp    <- check_sum_to_1_upper(weights_panel, "w_emp_muni_univ",         "w_emp_muni_univ")
res_firm   <- check_sum_to_1_upper(weights_panel, "w_firm_muni_univ",        "w_firm_muni_univ")
res_floorf <- check_sum_to_1_upper(weights_panel, "w_firm_empshare_floor",   "w_firm_empshare_floor")
# Binary variants: a firm with multiple aligned parties is double-counted in
# the numerator but the denominator is unchanged, so binary variants CAN
# legitimately exceed 1. Report only.
res_bin    <- check_sum_to_1_upper(weights_panel, "w_binary_muni_univ",
                                   "w_binary_muni_univ (not enforced)",
                                   hard_stop = FALSE)
res_binf   <- check_sum_to_1_upper(weights_panel, "w_binary_empshare_floor",
                                   "w_binary_empshare_floor (not enforced)",
                                   hard_stop = FALSE)

max_sum_owners <- res_owners$max
max_sum_emp    <- res_emp$max
max_sum_firm   <- res_firm$max
max_sum_floorf <- res_floorf$max
max_sum_bin    <- res_bin$max
max_sum_binf   <- res_binf$max

# ------------------------------------------------------------------------------
# 12. Load Tier A replication anchor (w_owners_sec_match) and merge into panel
# ------------------------------------------------------------------------------
message("\nLoading Tier A replication anchor (w_owners_sec_match)...")
anchor_raw <- qs_read(path_anchor)
setDT(anchor_raw)

# Anchor has columns: muni_id, policy_block, year, party, w_mjp_owners.
# We need to pool to the same baseline windows used for Tier C.
anchor_year <- anchor_raw[, .(muni_id, policy_block, year, party,
                              L_mjp_anchor = L_mjp,
                              L_mj_anchor  = L_mj)]

build_anchor_baseline <- function(treatment_year, bl_start, bl_end, tier) {
  window_years <- seq.int(bl_start, bl_end)
  sub <- anchor_year[year %in% window_years]
  num_pooled <- sub[, .(L_mjp_pooled = sum(L_mjp_anchor, na.rm = TRUE)),
                    by = .(muni_id, policy_block, party)]
  # Sector denominator: pool L_mj across years per (muni, block).
  # L_mj is identical across parties within (muni, block, year), so we
  # deduplicate first.
  den_unique <- unique(sub[, .(muni_id, policy_block, year, L_mj_anchor)])
  den_pooled <- den_unique[, .(L_mj_pooled = sum(L_mj_anchor, na.rm = TRUE)),
                            by = .(muni_id, policy_block)]
  out <- merge(num_pooled, den_pooled, by = c("muni_id", "policy_block"), all.x = TRUE)
  out[, w_owners_sec_match := fifelse(L_mj_pooled > 0, L_mjp_pooled / L_mj_pooled, 0)]
  out[, treatment_year := as.integer(treatment_year)]
  out[, tier := tier]
  out[, baseline_type := "cycle_specific"]
  out[, .(muni_id, policy_block, party, treatment_year, tier, baseline_type,
          w_owners_sec_match)]
}

anchor_list <- vector("list", nrow(baseline_window_map))
for (i in seq_len(nrow(baseline_window_map))) {
  ty     <- baseline_window_map$treatment_year[i]
  bs     <- baseline_window_map$bl_start[i]
  be     <- baseline_window_map$bl_end[i]
  tier_i <- baseline_window_map$tier[i]
  anchor_list[[i]] <- build_anchor_baseline(ty, bs, be, tier_i)
}
anchor_pooled <- rbindlist(anchor_list, use.names = TRUE)
rm(anchor_list, anchor_raw, anchor_year); invisible(gc())

message(sprintf("  Anchor pooled panel: %s rows",
                format(nrow(anchor_pooled), big.mark = ",")))

# Merge anchor onto Tier C panel
weights_panel <- merge(
  weights_panel,
  anchor_pooled,
  by = c("muni_id", "policy_block", "party", "treatment_year", "tier", "baseline_type"),
  all = TRUE
)

# Where anchor is NA (Tier C cells with no matched-firm coverage), set 0.
# This mirrors the pipeline's NA-fill convention.
weights_panel[is.na(w_owners_sec_match), w_owners_sec_match := 0]
# And vice versa: any anchor-only rows (no Tier C) get Tier C zeros.
TIERC_COLS <- c("w_owners_muni_univ", "w_emp_muni_univ", "w_firm_muni_univ",
                "w_binary_muni_univ", "w_firm_empshare_floor", "w_binary_empshare_floor")
for (col in TIERC_COLS) {
  weights_panel[is.na(get(col)), (col) := 0]
}

# Set tier label for the panel: all rows are "C" with the anchor on top
weights_panel[, tier_panel := "C"]

# ------------------------------------------------------------------------------
# 13. Save weights panel
# ------------------------------------------------------------------------------
setorderv(weights_panel, c("baseline_type", "tier", "treatment_year",
                           "muni_id", "policy_block", "party"))
qs_save(weights_panel, path_out_weights)
message(sprintf("\nSaved weights panel: %s (%.2f MB)",
                path_out_weights, file.size(path_out_weights) / 1024^2))

# ------------------------------------------------------------------------------
# 14. Build muni-level instrument vectors
#
# For each weight w (6 Tier C + replication anchor):
#   sector-level Z_w_<tier>_coalition_inaug(m, b, treatment_year) =
#       sum over parties of w(m, b, p, treatment_year) * align_<tier>_coalition(m, p, treatment_year)
#   muni-level Z_w_<tier>_coalition_inaug(m, treatment_year) =
#       sum over (b, p) of w(m, b, p, treatment_year) * align_<tier>_coalition(m, p, treatment_year)
#
# Then spread across electoral term using term_map (script 34 convention):
#   for each muni and inaug_year, replicate the value over the 4 years
#   inaug_year .. inaug_year+3.
# ------------------------------------------------------------------------------
message("\nLoading alignment shocks...")
shocks <- qs_read(path_align)
setDT(shocks)

# Keep the level alignments (NOT the changes) since we are spreading levels
# across electoral terms (script 34 convention).
keep_align_cols <- c("muni_id", "party", "year",
                     "align_mayor_coalition", "align_gov_coalition", "align_pres_coalition")
shocks <- shocks[, ..keep_align_cols]
shocks[, year := as.integer(year)]

# FIX 1: Production script 34 builds THREE separate level instruments per
# weight variant: Z_mayor_coalition, Z_gov_coalition, Z_pres_coalition (the
# regex `align_(mayor|gov|pres)_(party|coalition)` in script 34 line 190
# captures both gov and pres). Earlier revision of THIS script summed
# align_gov_coalition + align_pres_coalition into a single combined column
# and built one Z_<weight>_gov_pres_coalition instrument. That collapsed
# distinct production semantics — gov coalition shocks are NOT identical to
# pres coalition shocks — into a single signal.
#
# Resolution: build TWO separate instruments for the gov_pres tier rows:
#   Z_<weight>_gov_coalition   = weight × align_gov_coalition  | tier=="gov_pres"
#   Z_<weight>_pres_coalition  = weight × align_pres_coalition | tier=="gov_pres"
# This matches script 34's `level_cols` enumeration exactly.
# DO NOT define a combined align_gov_pres_coalition column here.

message(sprintf("  Loaded %s alignment rows", format(nrow(shocks), big.mark = ",")))

# ------------------------------------------------------------------------------
# 15. Build instrument vectors per weight
#
# Strategy: for each weight column w_id, do the production-script-34 dance:
#   1. Merge weights_panel (key: muni, party, treatment_year) with shocks
#      (key: muni, party, year) on (muni, party) and matching treatment_year=year.
#   2. For each tier in {mayor, gov_pres}:
#        Z_w_<tier>_coalition_inaug = sum over (block, party) of
#            w_id * align_<tier>_coalition * 1[tier in panel matches]
#   3. Spread across electoral term via term_map.
# ------------------------------------------------------------------------------
message("\nBuilding muni-level instrument vectors...")

# All weight columns (Tier C + anchor)
ALL_WEIGHTS <- c(TIERC_WEIGHTS, ANCHOR_WEIGHT)
ALL_WEIGHT_COLS <- c(paste0("w_", TIERC_WEIGHTS), paste0("w_", ANCHOR_WEIGHT))

# Merge weights with shocks at (muni, party) where treatment_year matches the
# inauguration year (the level alignment in the inauguration year IS the
# level for the term, before spreading).
merge_keys <- c("muni_id", "party", "year")

# Reshape weights to long form (muni, party, treatment_year, tier, weight_id, value)
weights_long <- melt(
  weights_panel[, c("muni_id", "policy_block", "party", "treatment_year", "tier",
                    ALL_WEIGHT_COLS), with = FALSE],
  id.vars = c("muni_id", "policy_block", "party", "treatment_year", "tier"),
  measure.vars = ALL_WEIGHT_COLS,
  variable.name = "weight_id",
  value.name = "weight_value"
)
weights_long[, weight_id := as.character(weight_id)]
weights_long[, weight_id := sub("^w_", "", weight_id)]   # strip "w_" prefix
weights_long[is.na(weight_value), weight_value := 0]

# Merge with shocks on (muni, party, treatment_year=year)
merged <- merge(
  weights_long,
  shocks,
  by.x = c("muni_id", "party", "treatment_year"),
  by.y = c("muni_id", "party", "year"),
  all.x = TRUE
)
for (col in c("align_mayor_coalition", "align_gov_coalition",
              "align_pres_coalition")) {
  merged[is.na(get(col)), (col) := 0L]
}

# FIX 1: Apply tier conditional logic per script 34 (lines 251-266):
#   tier == "mayor"    => use align_mayor_coalition
#   tier == "gov_pres" => use align_gov_coalition AND align_pres_coalition
#                          (two separate instruments, not summed)
merged[, contrib_mayor := fifelse(tier == "mayor",
                                  weight_value * align_mayor_coalition,
                                  0)]
merged[, contrib_gov   := fifelse(tier == "gov_pres",
                                  weight_value * align_gov_coalition,
                                  0)]
merged[, contrib_pres  := fifelse(tier == "gov_pres",
                                  weight_value * align_pres_coalition,
                                  0)]

# Aggregate to muni-treatment_year-weight_id-baseline_type (sum over block, party)
muni_inaug <- merged[, .(
  Z_mayor_coalition_inaug = sum(contrib_mayor, na.rm = TRUE),
  Z_gov_coalition_inaug   = sum(contrib_gov,   na.rm = TRUE),
  Z_pres_coalition_inaug  = sum(contrib_pres,  na.rm = TRUE)
), by = .(muni_id, treatment_year, weight_id)]

rm(merged, weights_long); invisible(gc())

# Reshape to wide on weight_id: 3 pivots, one per alignment tier.
build_wide <- function(dt, value_col, tier_suffix) {
  out <- dcast(dt, muni_id + treatment_year ~ weight_id, value.var = value_col)
  vc  <- setdiff(names(out), c("muni_id", "treatment_year"))
  setnames(out, vc, paste0("Z_", vc, "_", tier_suffix, "_inaug"))
  out
}
muni_inaug_wide_mayor <- build_wide(muni_inaug, "Z_mayor_coalition_inaug", "mayor_coalition")
muni_inaug_wide_gov   <- build_wide(muni_inaug, "Z_gov_coalition_inaug",   "gov_coalition")
muni_inaug_wide_pres  <- build_wide(muni_inaug, "Z_pres_coalition_inaug",  "pres_coalition")

muni_inaug_wide <- Reduce(
  function(x, y) merge(x, y, by = c("muni_id", "treatment_year"), all = TRUE),
  list(muni_inaug_wide_mayor, muni_inaug_wide_gov, muni_inaug_wide_pres)
)
rm(muni_inaug_wide_mayor, muni_inaug_wide_gov, muni_inaug_wide_pres,
   muni_inaug); invisible(gc())

# Fill NAs with 0
inst_cols <- setdiff(names(muni_inaug_wide), c("muni_id", "treatment_year"))
for (col in inst_cols) {
  muni_inaug_wide[is.na(get(col)), (col) := 0]
}

# ------------------------------------------------------------------------------
# 16. Spread across electoral term
#
# FIX 6: Verify the term_map produces a disjoint mapping per (year, tier).
# Reasoning: each weight in muni_inaug_wide carries an implicit tier (mayor
# weights are non-zero only in mayor inaug years, gov_pres weights only in
# gov_pres inaug years). Within each tier, term_map covers disjoint year
# ranges (mayor: 2005-08, 09-12, 13-16, 17-20; gov_pres: 2003-06, 07-10,
# 11-14, 15-18). Across tiers, however, mayor inaug 2005 spreads into year
# 2005 AND gov_pres inaug 2003 spreads into year 2005 — but the columns are
# tier-specific (Z_*_mayor_*, Z_*_gov_*, Z_*_pres_*), so adding tier columns
# under sum(.) does NOT double-count: a mayor column has 0 for any
# treatment_year that is a gov_pres inaug year (the contrib_mayor logic
# above zeros these out). Thus per-column-per-(muni, year), at most ONE
# inaug_year feeds in. Verify this:
# ------------------------------------------------------------------------------
message("Spreading muni-level instruments across electoral terms...")

# Sanity check: within each tier (mayor or gov_pres), the term_map's
# (inaug_year, year) rows must be disjoint. We test by counting (year, tier)
# multiplicities.
mayor_inaug_years <- c(2005L, 2009L, 2013L, 2017L)
gp_inaug_years    <- c(2003L, 2007L, 2011L, 2015L)
tm_mayor <- term_map[inaug_year %in% mayor_inaug_years]
tm_gp    <- term_map[inaug_year %in% gp_inaug_years]
n_dup_mayor <- nrow(tm_mayor) - nrow(unique(tm_mayor, by = "year"))
n_dup_gp    <- nrow(tm_gp)    - nrow(unique(tm_gp,    by = "year"))
if (n_dup_mayor > 0L || n_dup_gp > 0L) {
  stop(sprintf(
    "term_map has overlapping (year, tier) pairs (mayor dup=%d, gov_pres dup=%d). STOP per FIX 6 — structural bug in term_map.",
    n_dup_mayor, n_dup_gp
  ))
}
message(sprintf("  term_map disjointness check: PASS (mayor=%d, gov_pres=%d, no duplicate years per tier)",
                nrow(tm_mayor), nrow(tm_gp)))

# Map treatment_year -> year (term spreading)
muni_spread <- merge(
  muni_inaug_wide,
  term_map,
  by.x = "treatment_year",
  by.y = "inaug_year",
  allow.cartesian = TRUE
)
# Aggregate over inaug_year (sum-by-year). Since each tier's inaug_years span
# disjoint year-ranges (verified above) AND mayor columns are zero for
# gov_pres inaug rows (and vice versa), each (muni, year, column) draws from
# AT MOST ONE inaug-year contribution. The sum is therefore a deduplication
# safeguard — not a true aggregation that would double-count.
agg_cols <- inst_cols
muni_year <- muni_spread[, lapply(.SD, sum, na.rm = TRUE),
                         by = .(muni_id, year),
                         .SDcols = agg_cols]
# Output column names: drop "_inaug" suffix to match production naming
new_names <- sub("_inaug$", "", names(muni_year))
setnames(muni_year, names(muni_year), new_names)

# Restrict to estimation years 2002-2017 (matching production)
muni_year <- muni_year[year >= 2002L & year <= 2017L]

# Mark baseline_type
muni_year[, baseline_type := "cycle_specific"]

setorder(muni_year, baseline_type, year, muni_id)

message(sprintf("  Instrument panel: %s muni-year rows",
                format(nrow(muni_year), big.mark = ",")))
message(sprintf("  Instrument columns built: %d",
                length(grep("^Z_", names(muni_year)))))

# NA verification: per script 34 convention, no NAs allowed in instrument cols.
inst_panel_cols <- grep("^Z_", names(muni_year), value = TRUE)
n_na_total <- sum(vapply(inst_panel_cols,
                         function(c) sum(is.na(muni_year[[c]])),
                         integer(1)))
if (n_na_total > 0L) {
  warning(sprintf("Found %d NA values in instrument columns; filling with 0",
                  n_na_total))
  for (col in inst_panel_cols) {
    muni_year[is.na(get(col)), (col) := 0]
  }
}
message(sprintf("  Total NAs in instrument columns: %d (after fill: 0)",
                n_na_total))

# ------------------------------------------------------------------------------
# 17. Replication anchor verification (HARD GATE for all THREE tiers — FIX 1, FIX 4)
#
# Compare freshly aggregated Z_owners_sec_match_<tier>_coalition with
# production Z_<tier>_coalition for tier in {mayor, gov, pres},
# cycle_specific baseline. Max abs diff per tier must be < 1e-6 or we STOP.
# ------------------------------------------------------------------------------
message("\n========================================================")
message("REPLICATION ANCHOR VERIFICATION (3 tiers: mayor, gov, pres)")
message("========================================================")

prod_inst <- qs_read(path_prod_inst)
setDT(prod_inst)

# Verify production has the columns we need (per script 34's level_cols regex)
required_prod_cols <- c("Z_mayor_coalition", "Z_gov_coalition", "Z_pres_coalition")
missing_prod <- setdiff(required_prod_cols, names(prod_inst))
if (length(missing_prod) > 0L) {
  stop(sprintf("Production instruments file missing columns: %s",
               paste(missing_prod, collapse = ", ")))
}

prod_cs <- prod_inst[baseline_type == "cycle_specific",
                     .(muni_id, year, baseline_type,
                       Z_mayor_coalition_prod = Z_mayor_coalition,
                       Z_gov_coalition_prod   = Z_gov_coalition,
                       Z_pres_coalition_prod  = Z_pres_coalition)]

fresh_anchor <- muni_year[, .(muni_id, year, baseline_type,
                              Z_mayor_anchor_fresh = Z_owners_sec_match_mayor_coalition,
                              Z_gov_anchor_fresh   = Z_owners_sec_match_gov_coalition,
                              Z_pres_anchor_fresh  = Z_owners_sec_match_pres_coalition)]

cmp <- merge(prod_cs, fresh_anchor,
             by = c("muni_id", "year", "baseline_type"),
             all = TRUE)
fill_zero_cols <- setdiff(names(cmp), c("muni_id", "year", "baseline_type"))
for (col in fill_zero_cols) {
  cmp[is.na(get(col)), (col) := 0]
}

# Per-tier diff
cmp[, abs_diff_mayor := abs(Z_mayor_coalition_prod - Z_mayor_anchor_fresh)]
cmp[, abs_diff_gov   := abs(Z_gov_coalition_prod   - Z_gov_anchor_fresh)]
cmp[, abs_diff_pres  := abs(Z_pres_coalition_prod  - Z_pres_anchor_fresh)]

# FIX 4: Use the merged-with-all=TRUE cmp to find rows present in production
# but missing from fresh (i.e. the fresh side was NA before fill). We track
# this BEFORE filling NAs by re-doing the merge with a sentinel column.
fresh_anchor[, fresh_sentinel_ := 1L]
cmp_check <- merge(prod_cs[, .(muni_id, year, baseline_type)],
                   fresh_anchor[, .(muni_id, year, baseline_type, fresh_sentinel_)],
                   by = c("muni_id", "year", "baseline_type"),
                   all.x = TRUE)
n_prod_only <- cmp_check[is.na(fresh_sentinel_), .N]
fresh_anchor[, fresh_sentinel_ := NULL]

# Per-tier summary stats
report_tier <- function(tier_name, diff_col) {
  max_d  <- max(cmp[[diff_col]], na.rm = TRUE)
  mean_d <- mean(cmp[[diff_col]], na.rm = TRUE)
  n_above <- sum(cmp[[diff_col]] > REPL_TOL, na.rm = TRUE)
  message(sprintf("  %-6s | max abs diff = %.10e | mean abs diff = %.10e | rows > %.0e: %s",
                  tier_name, max_d, mean_d, REPL_TOL,
                  format(n_above, big.mark = ",")))
  list(tier = tier_name, max = max_d, mean = mean_d, n_above = n_above)
}

message(sprintf("  Compared rows: %s | Production-only (no fresh row): %s",
                format(nrow(cmp), big.mark = ","),
                format(n_prod_only, big.mark = ",")))
res_mayor <- report_tier("mayor", "abs_diff_mayor")
res_gov   <- report_tier("gov",   "abs_diff_gov")
res_pres  <- report_tier("pres",  "abs_diff_pres")

# Hard-stop loop
fail_tiers <- character(0)
for (r in list(res_mayor, res_gov, res_pres)) {
  if (r$max > REPL_TOL) fail_tiers <- c(fail_tiers, r$tier)
}
if (length(fail_tiers) > 0L) {
  message("\n  >>> REPLICATION ANCHOR FAILED on tier(s): ",
          paste(fail_tiers, collapse = ", "), " <<<")
  for (tier_name in fail_tiers) {
    diff_col <- paste0("abs_diff_", tier_name)
    message(sprintf("\n  Top 10 discrepancies for tier '%s':", tier_name))
    print(cmp[order(-get(diff_col))][seq_len(min(10L, .N))])
  }
  stop(sprintf(
    "Replication anchor exceeds tolerance %.6e on tier(s): %s. STOP per plan.",
    REPL_TOL, paste(fail_tiers, collapse = ", ")
  ))
} else {
  message(sprintf("\n  >>> REPLICATION ANCHOR PASSED for all 3 tiers (max diff < %.0e) <<<",
                  REPL_TOL))
}

# Keep top-level summary scalars for the final summary block
max_abs_diff       <- max(c(res_mayor$max, res_gov$max, res_pres$max))
max_abs_diff_mayor <- res_mayor$max
max_abs_diff_gov   <- res_gov$max
max_abs_diff_pres  <- res_pres$max

# ------------------------------------------------------------------------------
# 18. Save instruments panel
# ------------------------------------------------------------------------------
qs_save(muni_year, path_out_instruments)
message(sprintf("\nSaved instruments panel: %s (%.2f MB)",
                path_out_instruments, file.size(path_out_instruments) / 1024^2))

# ------------------------------------------------------------------------------
# 19. Final summary
# ------------------------------------------------------------------------------
message("\n========================================================")
message("STEP 1 SUMMARY")
message("========================================================")
message(sprintf("Replication anchor (3 tiers, all PASS at tolerance %.0e):", REPL_TOL))
message(sprintf("  mayor: max abs diff = %.6e", max_abs_diff_mayor))
message(sprintf("  gov:   max abs diff = %.6e", max_abs_diff_gov))
message(sprintf("  pres:  max abs diff = %.6e", max_abs_diff_pres))
message(sprintf("Sum-to-1 upper-bound (4 weights, hard-stop at sum>1+%.0e):", SUM_TOL))
message(sprintf("  w_owners_muni_univ      n_active=%d, max=%.10f, over-1=%d, exactly-at-1=%d",
                res_owners$n_active, res_owners$max, res_owners$n_above_1, res_owners$n_at_1))
message(sprintf("  w_emp_muni_univ         n_active=%d, max=%.10f, over-1=%d, exactly-at-1=%d",
                res_emp$n_active, res_emp$max, res_emp$n_above_1, res_emp$n_at_1))
message(sprintf("  w_firm_muni_univ        n_active=%d, max=%.10f, over-1=%d, exactly-at-1=%d",
                res_firm$n_active, res_firm$max, res_firm$n_above_1, res_firm$n_at_1))
message(sprintf("  w_firm_empshare_floor   n_active=%d, max=%.10f, over-1=%d, exactly-at-1=%d",
                res_floorf$n_active, res_floorf$max, res_floorf$n_above_1, res_floorf$n_at_1))
message(sprintf("Binary variants (NOT enforced; can sum to >1):"))
message(sprintf("  w_binary_muni_univ      max sum = %.10f", max_sum_bin))
message(sprintf("  w_binary_empshare_floor max sum = %.10f", max_sum_binf))
message(sprintf("Weights panel:     %s rows, %s munis",
                format(nrow(weights_panel), big.mark = ","),
                format(uniqueN(weights_panel$muni_id), big.mark = ",")))
message(sprintf("Instruments panel: %s muni-year rows, %s munis",
                format(nrow(muni_year), big.mark = ","),
                format(uniqueN(muni_year$muni_id), big.mark = ",")))
n_z_cols <- length(grep("^Z_", names(muni_year)))
message(sprintf("Instrument columns built: %d (expected: 7 weights x 3 tiers = 21)",
                n_z_cols))
message(sprintf("Active blocks present: %s",
                paste(sort(unique(weights_panel$policy_block)), collapse = ", ")))

# FIX 5: Memory peak from gc(). gc() returns a 2-row matrix
# (Ncells / Vcells) x columns: "used" (cells), "(Mb)" (current MB),
# "gc trigger" (cells), "(Mb)" (trigger MB), "max used" (cells),
# "(Mb)" (max used MB). The previous code multiplied "max used" (cells)
# by 8 / 1024, which is wrong: Ncells are ~56 bytes each on R 4.x and
# Vcells are 8 bytes each, AND there is already a peak-MB column directly
# to the right of "max used" — that's what we should sum.
mem_info <- gc(reset = TRUE, full = TRUE)
cn <- colnames(mem_info)
mb_idxs <- which(cn == "(Mb)")
peak_mem_mb <- NA_real_
if (length(mb_idxs) >= 2L) {
  # Last "(Mb)" column corresponds to "max used (Mb)" peak per row.
  peak_mb_col <- mb_idxs[length(mb_idxs)]
  peak_mem_mb <- sum(mem_info[, peak_mb_col], na.rm = TRUE)
  message(sprintf(
    "Approximate memory peak: %.0f MB (sum of Ncells+Vcells max '(Mb)' column at index %d)",
    peak_mem_mb, peak_mb_col
  ))
} else if ("max used" %in% cn) {
  # Older R: estimate from cell counts and per-cell byte sizes.
  ncells_max <- mem_info["Ncells", "max used"]
  vcells_max <- mem_info["Vcells", "max used"]
  peak_mem_mb <- (ncells_max * 56 + vcells_max * 8) / 1024^2
  message(sprintf(
    "Approximate memory peak: %.0f MB (cell-based: N=%s x 56B + V=%s x 8B)",
    peak_mem_mb,
    format(ncells_max, big.mark = ","),
    format(vcells_max, big.mark = ",")
  ))
} else {
  message("Memory peak: gc() column shape unrecognized — manual check required.")
}

message("\nStep 1 complete.")
