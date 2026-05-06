# ==============================================================================
# 04_onecycle_proxy.R
#
# A7 Step 4 - One-cycle proxy regression (F-stat ranking driving the production
# decision). Runs first-stage F-stats for the 5 Tier C representative weights
# plus 2 Tier B counterparts (Clusters 1 and 2 expansion-flagged) plus the
# optional Cluster 2 cluster-mate (w_emp_muni_univ) on the 2002-2006 mayor
# cycle.
#
# Plan: logs/plans/2026-05-05_a7-revised-weight-comparison.md (Step 4)
# Step 1 inputs:
#   explorations/anderson_rubin/a7_weight_comparison/output/a7_weights_panel.qs2
# Step 3 inputs:
#   explorations/anderson_rubin/a7_weight_comparison/output/a7_representative_weights.csv
# Outcome / panel reference:
#   explorations/anderson_rubin/ar_baseline.R uses log_gdp as outcome with
#   instruments ar_Z_mayor_coalition_cycle_specific_{Agro,Ind,Infra,Serv}
#   (sector-decomposed K=4) and clusters at muni_id.
#
# Specifications (per plan Step 4):
#   (a) no_controls : log_gdp ~ Z_<w>_<block> (4 instruments, no FE/ctrl)
#   (b) C1_FE       : + muni_id + year FE
#   (c) C2_FE_R0a   : C1_FE + ec_total_mayor_cycle_specific scalar
#                     (matching ar_baseline.R C2 spec)
#
# Sample: rows in muni_panel_for_regs_policy_block.qs2 with
#   year %in% 2005..2008 (the 2002-2006 mayor cycle's electoral term).
#   The plan says "2002-2006 mayor cycle" -- the baseline window is 2002-03,
#   election is 2004, inauguration is 2005, term covers 2005-2008. Step 1
#   built treatment_year = 2005 with bl = 2000-2003 (script-33 cycle-spec
#   convention), spread via term_map to years 2005-2008. So filtering on
#   year %in% 2005..2008 isolates the one-cycle proxy.
#
# F-stats reported:
#   f_stat_cd : heteroskedasticity-robust joint Wald F (no clustering)
#               -- the AR analogue of Cragg-Donald in the reduced-form setup
#   f_stat_kp : cluster-robust (~muni_id) joint Wald F
#               -- the AR analogue of Kleibergen-Paap rk Wald F
#   In a reduced-form first-stage (no endogenous regressor), CD/KP collapse
#   to robust / cluster-robust F-tests on the K=4 instruments. The naming
#   preserves the plan's vocabulary while clarifying the actual quantity.
#
# Outputs:
#   output/a7_onecycle_proxy_fstats.csv   F-stat ranking table (24 rows)
#   output/a7_tier_b_weights_panel.qs2    Tier B weights (clusters 1 & 2)
#   output/a7_tier_b_instruments_panel.qs2 Tier B sector-decomposed Z
#   output/a7_onecycle_proxy_summary.md   Narrative summary
#
# Hard constraints: INV-14 (one set.seed; no randomness here, omitted),
# INV-15 (packages at top), INV-16 (no absolute paths), INV-19 (no setwd,
# rm(list=ls), install.packages, attach/detach).
# ==============================================================================

# ---- 1. Packages (INV-15) ----------------------------------------------------
suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
  library(fixest)
  library(here)
})

HAS_FST <- requireNamespace("fst", quietly = TRUE)
if (HAS_FST) library(fst)

setDTthreads(0L)

# ---- 2. Paths via here::here() (INV-16) --------------------------------------
PROCESSED_DIR <- here::here("data", "processed")
RAW_DIR       <- here::here("data", "raw")
A7_DIR        <- here::here(
  "explorations", "anderson_rubin", "a7_weight_comparison"
)
OUTPUT_DIR    <- file.path(A7_DIR, "output")

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
}

path_weights_panel    <- file.path(OUTPUT_DIR, "a7_weights_panel.qs2")
path_repr             <- file.path(OUTPUT_DIR, "a7_representative_weights.csv")
path_muni_panel       <- file.path(PROCESSED_DIR, "muni_panel_for_regs_policy_block.qs2")
path_pb_cw            <- file.path(PROCESSED_DIR, "policy_block_mapping.qs2")
path_owner_aff        <- file.path(RAW_DIR, "david_ra", "owner_aff_firm_year_party_2002_2019.qs2")
path_recon_fst        <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst")
path_recon_qs2        <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.qs2")
path_align            <- file.path(PROCESSED_DIR, "alignment_shocks.qs2")

path_out_fstats       <- file.path(OUTPUT_DIR, "a7_onecycle_proxy_fstats.csv")
path_out_tb_weights   <- file.path(OUTPUT_DIR, "a7_tier_b_weights_panel.qs2")
path_out_tb_inst      <- file.path(OUTPUT_DIR, "a7_tier_b_instruments_panel.qs2")
path_out_summary      <- file.path(OUTPUT_DIR, "a7_onecycle_proxy_summary.md")

# ============================================================
# Paper-to-Code Naming Map
# ============================================================
# Paper Notation             | Code Name                              | Description
# Y_mt                       | log_gdp                                | Log municipal GDP
# Z^j_{mt}(w)                | Z_<weight_id>_mayor_coalition_<block>  | Sector-decomp shift-share Z
# EC_mt                      | ec_total_mayor_cycle_specific          | Muni-total exposure ctrl
# F_first-stage robust       | f_stat_cd                              | CD-analogue (HC-robust F)
# F_first-stage cluster      | f_stat_kp                              | KP-analogue (cluster-rob F)
# K = 4                      | length(z_cols)                         | Number of instruments
# N                          | n_obs                                  | Regression observations
# M                          | n_clusters                             | Unique muni clusters
# ============================================================

# ---- 3. Constants ------------------------------------------------------------
ACTIVE_BLOCKS <- c("Agro", "Ind", "Infra", "Serv")

# 2002-2006 mayor cycle: baseline 2000-2003 (Step 1), inaug 2005, term 2005-08
ONECYCLE_TREATMENT_YEAR <- 2005L
ONECYCLE_TERM_YEARS     <- 2005L:2008L

# Tier C representative weight IDs (Step 3 output)
TIERC_REPS <- c(
  "owners_muni_univ",        # Cluster 1 representative (expansion flag)
  "firm_empshare_floor",     # Cluster 2 representative (expansion flag)
  "firm_muni_univ",          # Cluster 3
  "binary_muni_univ",        # Cluster 4
  "binary_empshare_floor"    # Cluster 5
)

# Cluster 2 clustermate (optional, recommended)
CLUSTERMATE <- "emp_muni_univ"

# Tier B weight IDs to build (one per flagged Tier C representative)
TIERB_WEIGHTS <- c(
  "owners_muni_match",            # Tier B counterpart of w_owners_muni_univ
  "firm_empshare_floor_match"     # Tier B counterpart of w_firm_empshare_floor
)

# Mapping cluster_id of each weight (for output table)
WEIGHT_CLUSTER_MAP <- data.table(
  weight_id = c(TIERC_REPS, CLUSTERMATE, TIERB_WEIGHTS),
  tier      = c(rep("C", length(TIERC_REPS)),
                "C_clustermate",
                rep("B", length(TIERB_WEIGHTS))),
  cluster_id = c(1L, 2L, 3L, 4L, 5L,    # Tier C reps
                 2L,                     # clustermate (cluster 2)
                 1L, 2L)                 # Tier B (clusters 1 and 2)
)

# Spec definitions
#
# DEVIATION FROM PLAN (documented):
#   The plan lists C1_FE = "muni FE + year FE" and C2_FE_R0a as that plus the
#   exposure control. In the one-cycle proxy, however, every Z is time-INVARIANT
#   within muni (Step 1 spreads the treatment_year=2005 instrument across years
#   2005-2008). Adding muni FE absorbs all Z variation -> perfect collinearity.
#   Therefore C1_FE here uses YEAR FE only (the maximal identifiable FE set in
#   a one-cycle window). This is the canonical adjustment for one-cycle proxies
#   and matches what the spec is structurally asking for: "control for time
#   shocks while testing first-stage strength of muni-level Z variation".
#   In the multi-cycle AR test (ar_baseline.R), Z does vary across cycles within
#   muni, so muni FE is identifiable there; the production decision spec stays
#   as the multi-cycle AR. The one-cycle proxy is a fast ranking tool whose
#   F-stat ordering is documented to be stable across cycles.
SPECS <- list(
  no_controls = list(fe_str = NULL,        ctrl_cols = character(0L)),
  C1_FE       = list(fe_str = "year",      ctrl_cols = character(0L)),
  C2_FE_R0a   = list(fe_str = "year",
                     ctrl_cols = "ec_total_mayor_cycle_specific")
)

# Cycle-specific baseline windows for the 2005 treatment year (Step 1 conv.)
TIERB_BASELINE_BL_START <- 2000L
TIERB_BASELINE_BL_END   <- 2003L
TIERB_TIER              <- "mayor"

# ---- 4. Load Step 1 weights panel and Step 3 representatives ----------------
message("Loading Step 1 weights panel...")
weights_panel <- qs_read(path_weights_panel)
setDT(weights_panel)
message(sprintf("  %s rows, %d cols", format(nrow(weights_panel), big.mark = ","), ncol(weights_panel)))

message("Loading Step 3 representative selection...")
repr <- fread(path_repr)
message(sprintf("  %d cluster-rep entries", nrow(repr)))

# Sanity: confirm the representatives in the CSV match TIERC_REPS
csv_reps <- repr[is_representative == TRUE, weight_id]
csv_reps_clean <- sub("^w_", "", csv_reps)
stopifnot(setequal(csv_reps_clean, TIERC_REPS))

# ==============================================================================
# 5. BUILD TIER B WEIGHTS for clusters 1 and 2
# ==============================================================================
# Definitions per plan lines 86-91:
#   w_owners_muni_match: L_mjp / L_mB_match where L_mB_match = sum(total_owners)
#                        over MATCHED firms in muni m
#   w_firm_empshare_floor_match: same firm-level signal as w_firm_empshare_floor
#                                but emp_share_floor_f denominator computed
#                                over MATCHED firms only (denominator =
#                                Sigma n_f_floored over MATCHED RAIS firms in
#                                muni m, not all RAIS firms)
#
# We re-implement using the same pool-counts-then-divide convention as Step 1.
# Only ONE baseline window is needed for Step 4 (treatment_year = 2005, bl
# 2000-2003) but we build all 4 mayor windows for symmetry with Step 1.
# ==============================================================================

message("\n========================================================")
message("BUILDING TIER B WEIGHTS (clusters 1 and 2)")
message("========================================================")

# --- 5.1 Load ingredients (mirrors 01_build_weights.R sections 4-8) ----------

message("Loading policy_block crosswalk...")
crosswalk <- setDT(qs_read(path_pb_cw))

COLS_NEEDED <- c("firm_id", "muni_id", "year", "cnae_section", "n_employees")

message("Loading reconstructed RAIS-BNDES panel...")
if (HAS_FST && file.exists(path_recon_fst)) {
  panel <- fst::read_fst(path_recon_fst, columns = COLS_NEEDED, as.data.table = TRUE)
} else if (file.exists(path_recon_qs2)) {
  raw <- qs_read(path_recon_qs2)
  setDT(raw)
  panel <- raw[, .SD, .SDcols = COLS_NEEDED]
  rm(raw); invisible(gc())
} else {
  stop("Neither fst nor qs2 reconstructed panel found.")
}

panel[, firm_id := as.integer(firm_id)]
panel[, muni_id := as.integer(muni_id)]
panel[, year := as.integer(year)]
panel[, n_employees := as.numeric(n_employees)]

panel <- panel[!is.na(muni_id) & muni_id > 0L &
               !is.na(cnae_section) & nzchar(cnae_section)]
panel <- merge(
  panel,
  crosswalk[, .(cnae_section, policy_block)],
  by = "cnae_section",
  all.x = TRUE
)
panel <- panel[!is.na(policy_block) & policy_block %in% ACTIVE_BLOCKS]
panel <- panel[year >= 2000L & year <= 2017L]
panel <- unique(panel, by = c("firm_id", "muni_id", "year"))

message(sprintf(
  "  RAIS panel: %s firm-muni-year rows, %s munis",
  format(nrow(panel), big.mark = ","),
  format(uniqueN(panel$muni_id), big.mark = ",")
))

message("Loading owner affiliation data...")
aff <- qs_read(path_owner_aff)
setDT(aff)
aff[, year := as.integer(year)]
aff[, firm_id := as.integer(firm_id)]
aff[, party := trimws(as.character(party))]
aff[, share_aff_owners := as.numeric(share_aff_owners)]
aff[, aff_owners := as.integer(aff_owners)]
aff <- aff[year >= 2000L & year <= 2017L]
aff[share_aff_owners < 0, share_aff_owners := NA_real_]
aff[share_aff_owners > 1, share_aff_owners := 1]

# Compute total_owners per firm-year (mirrors Step 1)
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
aff[, total_owners_est := NULL]

# Build firm_base: one row per firm-muni-year with policy_block, n_employees,
# and owner_count (= total_owners for matched, NA for unmatched).
message("Joining total_owners onto RAIS panel (Tier B match-only path)...")
firm_base <- merge(
  panel,
  firm_owners[, .(firm_id, year, total_owners)],
  by = c("firm_id", "year"),
  all.x = TRUE
)
# Tier B: restrict to MATCHED firms only.
firm_base[, n_employees_clean := fifelse(
  is.finite(n_employees) & !is.na(n_employees) & n_employees > 0,
  n_employees,
  0
)]
# n_f_floored uses the MATCHED-firm convention: pmax(n_employees, total_owners, 1)
# for matched firms; unmatched firms are excluded from the denominator entirely.
firm_base_match <- firm_base[!is.na(total_owners)]
firm_base_match[, owner_count := as.integer(total_owners)]
firm_base_match[, n_f_floored := pmax(n_employees_clean, owner_count, 1)]

n_match <- nrow(firm_base_match)
n_total <- nrow(firm_base)
message(sprintf("  Tier B firm-muni-year rows (matched only): %s / %s (%.1f%%)",
                format(n_match, big.mark = ","),
                format(n_total, big.mark = ","),
                100 * n_match / n_total))

rm(panel, firm_base); invisible(gc())

# Build firm_party_base: aligned aff joined onto firm_base_match
aff_align <- aff[party != "No party"]
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

firm_party_base <- merge(
  aff_align[, .(firm_id, year, party, aff_owners, owner_party_share)],
  firm_base_match[, .(firm_id, muni_id, year, policy_block,
                      n_employees_clean, n_f_floored)],
  by = c("firm_id", "year"),
  all.x = FALSE,
  allow.cartesian = TRUE
)
firm_party_base <- firm_party_base[!is.na(policy_block)]

message(sprintf("  Tier B numerator base (firm, muni, year, party): %s rows",
                format(nrow(firm_party_base), big.mark = ",")))
rm(aff, aff_align); invisible(gc())

# --- 5.2 Build (muni, year) totals over MATCHED firms ------------------------
muni_year_totals_match <- firm_base_match[, .(
  L_mB_match_year         = sum(owner_count, na.rm = TRUE),
  total_floor_match_year  = sum(n_f_floored, na.rm = TRUE)
), by = .(muni_id, year)]
setkey(muni_year_totals_match, muni_id, year)

# Attach total_floor_match_year to firm_party_base for empshare_floor variant
firm_party_base <- merge(
  firm_party_base,
  muni_year_totals_match[, .(muni_id, year, total_floor_match_year)],
  by = c("muni_id", "year"),
  all.x = TRUE
)
firm_party_base[, emp_share_floor_match_f := fifelse(
  total_floor_match_year > 0,
  n_f_floored / total_floor_match_year,
  0
)]
firm_party_base[, contrib_floor_firm_match := emp_share_floor_match_f * owner_party_share]

# Per-(muni, block, party, year) numerator pieces
muni_block_party_year_b <- firm_party_base[, .(
  L_mjp_year                = sum(aff_owners, na.rm = TRUE),
  N_floor_firm_match_year   = sum(contrib_floor_firm_match, na.rm = TRUE)
), by = .(muni_id, policy_block, party, year)]

rm(firm_party_base, firm_base_match); invisible(gc())

# --- 5.3 Pool baseline windows and compute Tier B weights --------------------
build_tierb_baseline <- function(treatment_year, bl_start, bl_end, tier) {
  window_years <- seq.int(bl_start, bl_end)
  num_w <- muni_block_party_year_b[year %in% window_years]
  den_w <- muni_year_totals_match[year %in% window_years]

  num_pooled <- num_w[, .(
    L_mjp                = sum(L_mjp_year, na.rm = TRUE),
    N_floor_firm_match   = sum(N_floor_firm_match_year, na.rm = TRUE)
  ), by = .(muni_id, policy_block, party)]

  den_pooled <- den_w[, .(
    L_mB_match           = sum(L_mB_match_year, na.rm = TRUE),
    total_floor_match    = sum(total_floor_match_year, na.rm = TRUE)
  ), by = .(muni_id)]

  n_years_in_window <- length(window_years)

  out <- merge(num_pooled, den_pooled, by = "muni_id", all.x = TRUE)

  # w_owners_muni_match: L_mjp / L_mB_match
  out[, w_owners_muni_match := fifelse(L_mB_match > 0, L_mjp / L_mB_match, 0)]
  # w_firm_empshare_floor_match: pooled per-year share-weighted contributions,
  # rescaled by n_years_in_window (mirrors Step 1's empshare_floor convention).
  out[, w_firm_empshare_floor_match := N_floor_firm_match / n_years_in_window]

  out[, treatment_year := as.integer(treatment_year)]
  out[, tier := tier]
  out[, baseline_type := "cycle_specific"]
  out[, baseline_yrs := n_years_in_window]

  out[, .(
    muni_id, policy_block, party, treatment_year, tier, baseline_type, baseline_yrs,
    L_mjp, N_floor_firm_match, L_mB_match, total_floor_match,
    w_owners_muni_match, w_firm_empshare_floor_match
  )]
}

# Build all 4 mayor baseline windows (matching Step 1) so the panel is keyed
# the same way; only the 2005 row is used for Step 4 regressions.
mayor_window_map <- data.table(
  treatment_year = c(2005L, 2009L, 2013L, 2017L),
  bl_start       = c(2000L, 2004L, 2008L, 2012L),
  bl_end         = c(2003L, 2007L, 2011L, 2015L)
)

tierb_list <- vector("list", nrow(mayor_window_map))
for (i in seq_len(nrow(mayor_window_map))) {
  ty <- mayor_window_map$treatment_year[i]
  bs <- mayor_window_map$bl_start[i]
  be <- mayor_window_map$bl_end[i]
  message(sprintf("  Building Tier B for treatment=%d, window=%d-%d",
                  ty, bs, be))
  tierb_list[[i]] <- build_tierb_baseline(ty, bs, be, TIERB_TIER)
}
tierb_panel <- rbindlist(tierb_list, use.names = TRUE)
rm(tierb_list); invisible(gc())

message(sprintf("  Tier B weights panel: %s rows, %s munis",
                format(nrow(tierb_panel), big.mark = ","),
                format(uniqueN(tierb_panel$muni_id), big.mark = ",")))

# Save Tier B weights panel
qs_save(tierb_panel, path_out_tb_weights)
message(sprintf("  Saved: %s (%.2f MB)",
                path_out_tb_weights,
                file.size(path_out_tb_weights) / 1024^2))

# ==============================================================================
# 6. BUILD TIER B SECTOR-DECOMPOSED INSTRUMENTS
# ==============================================================================
# For each Tier B weight w and each policy_block b (Agro, Ind, Infra, Serv),
# build muni-level sector-decomposed Z(m, b, t) = sum_p w(m, b, p, t_treat) *
# align_mayor_coalition(m, p, t_treat), then spread across the term.
# ==============================================================================

message("\n========================================================")
message("BUILDING TIER B SECTOR-DECOMPOSED INSTRUMENTS")
message("========================================================")

shocks <- qs_read(path_align)
setDT(shocks)
shocks <- shocks[, .(muni_id, party, year, align_mayor_coalition)]
shocks[, year := as.integer(year)]

# Mayor-tier rows only
tierb_mayor <- tierb_panel[tier == "mayor"]

# Merge with shocks at (muni, party, treatment_year=year)
merged_b <- merge(
  tierb_mayor,
  shocks,
  by.x = c("muni_id", "party", "treatment_year"),
  by.y = c("muni_id", "party", "year"),
  all.x = TRUE
)
merged_b[is.na(align_mayor_coalition), align_mayor_coalition := 0]

# For each Tier B weight, compute per-(muni, block, treatment_year) Z component
build_tierb_sector_z <- function(weight_col, weight_id) {
  # Z_{m,b,t_treat} = sum_p w(m,b,p,t_treat) * align_mayor_coalition(m,p,t_treat)
  z_inaug <- merged_b[, .(
    Z_block = sum(get(weight_col) * align_mayor_coalition, na.rm = TRUE)
  ), by = .(muni_id, treatment_year, policy_block)]
  setnames(z_inaug, "Z_block", paste0("Z_", weight_id, "_mayor_coalition"))
  z_inaug
}

z_b1 <- build_tierb_sector_z("w_owners_muni_match",          "owners_muni_match")
z_b2 <- build_tierb_sector_z("w_firm_empshare_floor_match",  "firm_empshare_floor_match")

# Combine wide on (muni, treatment_year, policy_block)
tierb_z_inaug <- merge(
  z_b1, z_b2,
  by = c("muni_id", "treatment_year", "policy_block"),
  all = TRUE
)
for (col in setdiff(names(tierb_z_inaug), c("muni_id", "treatment_year", "policy_block"))) {
  tierb_z_inaug[is.na(get(col)), (col) := 0]
}

# Spread across electoral term (mayor: inaug -> 4-year term)
mayor_term_map <- rbindlist(list(
  data.table(inaug_year = 2005L, year = 2005L:2008L),
  data.table(inaug_year = 2009L, year = 2009L:2012L),
  data.table(inaug_year = 2013L, year = 2013L:2016L),
  data.table(inaug_year = 2017L, year = 2017L:2020L)
))
tierb_spread <- merge(
  tierb_z_inaug,
  mayor_term_map,
  by.x = "treatment_year",
  by.y = "inaug_year",
  allow.cartesian = TRUE
)
tierb_spread[, treatment_year := NULL]

# Pivot wide on policy_block: one column per (weight, block) pair
tierb_z_long <- melt(
  tierb_spread,
  id.vars = c("muni_id", "year", "policy_block"),
  measure.vars = c("Z_owners_muni_match_mayor_coalition",
                   "Z_firm_empshare_floor_match_mayor_coalition"),
  variable.name = "z_var",
  value.name = "z_val"
)
tierb_z_long[, z_var := as.character(z_var)]
tierb_z_long[, full_col := paste0(z_var, "_", policy_block)]
tierb_z_wide <- dcast(
  tierb_z_long,
  muni_id + year ~ full_col,
  value.var = "z_val",
  fill = 0
)

# Restrict to estimation years 2002-2017 and add baseline_type label
tierb_z_wide <- tierb_z_wide[year >= 2002L & year <= 2017L]
tierb_z_wide[, baseline_type := "cycle_specific"]

setorder(tierb_z_wide, year, muni_id)

# Save
qs_save(tierb_z_wide, path_out_tb_inst)
message(sprintf("  Tier B instruments panel: %s muni-year rows, %d cols",
                format(nrow(tierb_z_wide), big.mark = ","),
                ncol(tierb_z_wide)))
message(sprintf("  Saved: %s (%.2f MB)",
                path_out_tb_inst,
                file.size(path_out_tb_inst) / 1024^2))

rm(merged_b, tierb_mayor, tierb_spread, tierb_z_inaug, tierb_z_long,
   z_b1, z_b2); invisible(gc())

# ==============================================================================
# 7. BUILD TIER C SECTOR-DECOMPOSED INSTRUMENTS
# ==============================================================================
# Step 1's a7_instruments_panel.qs2 has muni-summed Z (one column per
# (weight, alignment-tier)). For F-stat first-stage we need sector-decomposed Z
# (4 columns per weight). Re-derive from weights_panel + alignment_shocks.
# ==============================================================================

message("\n========================================================")
message("BUILDING TIER C SECTOR-DECOMPOSED INSTRUMENTS")
message("========================================================")

# All Tier C weights to expand: 5 reps + clustermate
TIERC_WEIGHTS_ALL <- c(TIERC_REPS, CLUSTERMATE)

# Filter weights_panel to mayor tier only
wp_mayor <- weights_panel[tier == "mayor"]

# Merge with shocks at (muni, party, treatment_year=year)
merged_c <- merge(
  wp_mayor,
  shocks,
  by.x = c("muni_id", "party", "treatment_year"),
  by.y = c("muni_id", "party", "year"),
  all.x = TRUE
)
merged_c[is.na(align_mayor_coalition), align_mayor_coalition := 0]

# For each Tier C weight, compute per-(muni, block, treatment_year) Z
build_tierc_sector_z <- function(weight_id) {
  weight_col <- paste0("w_", weight_id)
  z_inaug <- merged_c[, .(
    Z_block = sum(get(weight_col) * align_mayor_coalition, na.rm = TRUE)
  ), by = .(muni_id, treatment_year, policy_block)]
  setnames(z_inaug, "Z_block", paste0("Z_", weight_id, "_mayor_coalition"))
  z_inaug
}

tierc_z_list <- lapply(TIERC_WEIGHTS_ALL, build_tierc_sector_z)
tierc_z_inaug <- Reduce(
  function(x, y) merge(x, y,
                       by = c("muni_id", "treatment_year", "policy_block"),
                       all = TRUE),
  tierc_z_list
)
z_cols_inaug <- setdiff(names(tierc_z_inaug),
                        c("muni_id", "treatment_year", "policy_block"))
for (col in z_cols_inaug) {
  tierc_z_inaug[is.na(get(col)), (col) := 0]
}

# Spread across mayor term
tierc_spread <- merge(
  tierc_z_inaug,
  mayor_term_map,
  by.x = "treatment_year",
  by.y = "inaug_year",
  allow.cartesian = TRUE
)
tierc_spread[, treatment_year := NULL]

# Pivot wide on policy_block
tierc_z_long <- melt(
  tierc_spread,
  id.vars = c("muni_id", "year", "policy_block"),
  measure.vars = z_cols_inaug,
  variable.name = "z_var",
  value.name = "z_val"
)
tierc_z_long[, z_var := as.character(z_var)]
tierc_z_long[, full_col := paste0(z_var, "_", policy_block)]
tierc_z_wide <- dcast(
  tierc_z_long,
  muni_id + year ~ full_col,
  value.var = "z_val",
  fill = 0
)

tierc_z_wide <- tierc_z_wide[year >= 2002L & year <= 2017L]

message(sprintf("  Tier C sector-decomposed instruments: %s rows, %d cols",
                format(nrow(tierc_z_wide), big.mark = ","),
                ncol(tierc_z_wide)))

rm(merged_c, wp_mayor, tierc_z_list, tierc_z_inaug, tierc_spread,
   tierc_z_long); invisible(gc())

# ==============================================================================
# 8. LOAD MUNI PANEL AND MERGE INSTRUMENTS
# ==============================================================================

message("\n========================================================")
message("LOADING MUNI PANEL AND MERGING INSTRUMENTS")
message("========================================================")

mp <- qs_read(path_muni_panel)
setDT(mp)

# Keep only the columns we need
keep_cols <- c("muni_id", "year", "log_gdp",
               "ec_total_mayor_cycle_specific")
keep_cols <- intersect(keep_cols, names(mp))
mp_lean <- mp[, ..keep_cols]
mp_lean[, muni_id := as.integer(muni_id)]
mp_lean[, year := as.integer(year)]

message(sprintf("  Muni panel: %s rows, %s munis (full panel)",
                format(nrow(mp_lean), big.mark = ","),
                format(uniqueN(mp_lean$muni_id), big.mark = ",")))

# Filter to one-cycle window
mp_cycle <- mp_lean[year %in% ONECYCLE_TERM_YEARS]
n_before_log <- nrow(mp_cycle)
mp_cycle <- mp_cycle[!is.na(log_gdp) & is.finite(log_gdp)]
message(sprintf("  One-cycle sample (year %d-%d): %s rows; dropped %d for NA/Inf log_gdp",
                ONECYCLE_TERM_YEARS[1], ONECYCLE_TERM_YEARS[length(ONECYCLE_TERM_YEARS)],
                format(nrow(mp_cycle), big.mark = ","), n_before_log - nrow(mp_cycle)))

# Merge Tier C instruments
mp_cycle <- merge(mp_cycle, tierc_z_wide,
                  by = c("muni_id", "year"), all.x = TRUE)
# Merge Tier B instruments
tierb_z_for_merge <- copy(tierb_z_wide)
tierb_z_for_merge[, baseline_type := NULL]
mp_cycle <- merge(mp_cycle, tierb_z_for_merge,
                  by = c("muni_id", "year"), all.x = TRUE)

# Fill NAs in Z columns with 0
z_all_cols <- grep("^Z_", names(mp_cycle), value = TRUE)
for (col in z_all_cols) {
  mp_cycle[is.na(get(col)), (col) := 0]
}

# C2 control: fill missing with 0 (matches ar_baseline.R behavior; the panel
# already has it for all rows, but we guard against NA)
if ("ec_total_mayor_cycle_specific" %in% names(mp_cycle)) {
  n_na_ec <- sum(is.na(mp_cycle$ec_total_mayor_cycle_specific))
  if (n_na_ec > 0L) {
    message(sprintf("  WARNING: %d NA values in ec_total_mayor_cycle_specific; setting to 0",
                    n_na_ec))
    mp_cycle[is.na(ec_total_mayor_cycle_specific),
             ec_total_mayor_cycle_specific := 0]
  }
} else {
  stop("ec_total_mayor_cycle_specific missing from muni panel; required for C2_FE_R0a spec.")
}

n_obs_cycle    <- nrow(mp_cycle)
n_clust_cycle  <- uniqueN(mp_cycle$muni_id)
message(sprintf("  Final estimation sample: %s muni-year obs, %s munis, %d years (%s)",
                format(n_obs_cycle, big.mark = ","),
                format(n_clust_cycle, big.mark = ","),
                length(ONECYCLE_TERM_YEARS),
                paste(ONECYCLE_TERM_YEARS, collapse = ", ")))

# ==============================================================================
# 9. F-STAT REGRESSION HELPER
# ==============================================================================
# For each (weight, spec):
#   1. Run reduced-form first stage:
#        log_gdp ~ Z_<w>_mayor_coalition_{Agro,Ind,Infra,Serv} + ctrl | FE
#   2. f_stat_kp: cluster-robust Wald F (vcov = ~muni_id)
#                 -- the AR-test analogue of Kleibergen-Paap rk Wald F
#   3. f_stat_cd: HC-robust (no cluster) Wald F via vcov = "hetero"
#                 -- the AR-test analogue of Cragg-Donald F
#   4. coef_estimate / se_estimate: aggregated as the unweighted sum of the 4
#      sector coefficients with cluster-robust SE (a single representative
#      summary)
#
# Notes:
#   - In the absence of an endogenous regressor, CD/KP collapse to the
#     reduced-form joint Wald F under different vcov choices. The naming
#     preserves the plan's vocabulary while the column documentation makes
#     the actual quantity transparent.
# ==============================================================================

run_first_stage <- function(data, weight_id, fe_str, ctrl_cols, blocks = ACTIVE_BLOCKS) {
  z_cols <- paste0("Z_", weight_id, "_mayor_coalition_", blocks)
  missing_z <- setdiff(z_cols, names(data))
  if (length(missing_z) > 0L) {
    stop(sprintf("Missing Z cols for %s: %s",
                 weight_id, paste(missing_z, collapse = ", ")))
  }

  rhs_regressors <- c(z_cols, ctrl_cols)
  rhs_str <- paste(rhs_regressors, collapse = " + ")

  if (!is.null(fe_str) && nchar(trimws(fe_str)) > 0L) {
    fml_str <- paste0("log_gdp ~ ", rhs_str, " | ", fe_str)
  } else {
    fml_str <- paste0("log_gdp ~ ", rhs_str)
  }
  fml <- as.formula(fml_str)

  # Cluster-robust fit
  m_kp <- fixest::feols(fml, data = data, vcov = ~muni_id)
  # HC-robust fit (no cluster)
  m_cd <- fixest::feols(fml, data = data, vcov = "hetero")

  # Wald F on the K=4 instruments
  pat <- paste0("^Z_", weight_id, "_mayor_coalition_")
  ar_kp <- fixest::wald(m_kp, keep = pat, print = FALSE)
  ar_cd <- fixest::wald(m_cd, keep = pat, print = FALSE)

  # Sample sizes
  n_obs       <- nobs(m_kp)
  n_clusters  <- uniqueN(data$muni_id)

  # Representative coefficient summary: sum of the 4 sectoral coefs
  # (an aggregate sanity quantity; not a substantive estimate)
  coefs <- coef(m_kp)[z_cols]
  coef_estimate <- sum(coefs)
  vc <- vcov(m_kp)[z_cols, z_cols, drop = FALSE]
  se_estimate <- sqrt(sum(vc))

  data.table(
    f_stat_cd     = ar_cd$stat,
    f_stat_kp     = ar_kp$stat,
    df1           = ar_kp$df1,
    df2           = ar_kp$df2,
    n_obs         = n_obs,
    n_clusters    = n_clusters,
    coef_estimate = coef_estimate,
    se_estimate   = se_estimate
  )
}

# ==============================================================================
# 10. RUN ALL (weight x spec) COMBINATIONS
# ==============================================================================

message("\n========================================================")
message("RUNNING F-STAT FIRST STAGES (weight x spec)")
message("========================================================")

results_list <- list()
row_idx <- 1L

for (i in seq_len(nrow(WEIGHT_CLUSTER_MAP))) {
  wid    <- WEIGHT_CLUSTER_MAP$weight_id[i]
  wtier  <- WEIGHT_CLUSTER_MAP$tier[i]
  wclust <- WEIGHT_CLUSTER_MAP$cluster_id[i]

  for (spec_id in names(SPECS)) {
    spec <- SPECS[[spec_id]]
    message(sprintf("  [%2d] %-32s  cluster=%d  tier=%-13s  spec=%s",
                    row_idx, wid, wclust, wtier, spec_id))
    fr <- run_first_stage(
      data      = mp_cycle,
      weight_id = wid,
      fe_str    = spec$fe_str,
      ctrl_cols = spec$ctrl_cols
    )
    fr[, weight_id := wid]
    fr[, tier := wtier]
    fr[, cluster_id := wclust]
    fr[, controls := spec_id]
    results_list[[row_idx]] <- fr
    row_idx <- row_idx + 1L
  }
}

results <- rbindlist(results_list, use.names = TRUE)

# Reorder columns to spec
setcolorder(results, c("weight_id", "tier", "cluster_id", "controls",
                       "f_stat_cd", "f_stat_kp",
                       "n_obs", "n_clusters", "df1", "df2",
                       "coef_estimate", "se_estimate"))

# Sanity: F > 1 hard check
n_below_1 <- sum(results$f_stat_kp < 1, na.rm = TRUE)
if (n_below_1 > 0L) {
  message(sprintf("\n  >>> WARNING: %d rows with f_stat_kp < 1 (broken spec) <<<",
                  n_below_1))
  print(results[f_stat_kp < 1])
}

# Save F-stat table
fwrite(results, path_out_fstats)
message(sprintf("\nSaved F-stat table: %s (%d rows)",
                path_out_fstats, nrow(results)))

# ==============================================================================
# 11. SUMMARY: RANK ORDER UNDER C1_FE
# ==============================================================================

message("\n========================================================")
message("F-STAT RANKING UNDER C1_FE (production-relevant spec)")
message("========================================================")

c1_results <- results[controls == "C1_FE"][order(-f_stat_kp)]

message(sprintf("%-32s %-14s %-3s %12s %12s",
                "weight_id", "tier", "cl", "F_kp", "F_cd"))
message(strrep("-", 80))
for (i in seq_len(nrow(c1_results))) {
  r <- c1_results[i]
  message(sprintf("%-32s %-14s %3d %12.3f %12.3f",
                  r$weight_id, r$tier, r$cluster_id,
                  r$f_stat_kp, r$f_stat_cd))
}
message(strrep("-", 80))
message(sprintf("Total rows in F-stat table: %d", nrow(results)))
message(sprintf("Sample: %d obs, %d munis, years %s",
                results$n_obs[1L], results$n_clusters[1L],
                paste(ONECYCLE_TERM_YEARS, collapse = ", ")))

# ==============================================================================
# 12. WRITE NARRATIVE SUMMARY
# ==============================================================================

# Headline rankings under each spec
mk_rank <- function(spec) {
  rr <- results[controls == spec][order(-f_stat_kp)]
  paste(sprintf("%2d. %-32s [%-13s, c=%d]  F_kp=%.2f  F_cd=%.2f",
                seq_len(nrow(rr)), rr$weight_id, rr$tier, rr$cluster_id,
                rr$f_stat_kp, rr$f_stat_cd),
        collapse = "\n")
}

# Tier B vs Tier C comparison rows for clusters 1 and 2
cmp_c1 <- results[cluster_id == 1L & controls == "C1_FE"]
cmp_c2 <- results[cluster_id == 2L & controls == "C1_FE"]

flagged_low_kp  <- results[f_stat_kp < 5, .(weight_id, tier, cluster_id,
                                            controls, f_stat_kp, f_stat_cd)]
flagged_under_1 <- results[f_stat_kp < 1, .(weight_id, tier, cluster_id,
                                            controls, f_stat_kp, f_stat_cd)]

summary_md <- paste0(
  "# A7 Step 4 -- One-Cycle Proxy F-Stat Summary\n\n",
  "Plan: `logs/plans/2026-05-05_a7-revised-weight-comparison.md`, Step 4.\n",
  "Sample: 2002-2006 mayor cycle (treatment_year = 2005, term years ",
  paste(ONECYCLE_TERM_YEARS, collapse = ", "), ")\n",
  "Outcome: `log_gdp` (matches `explorations/anderson_rubin/ar_baseline.R`).\n",
  "Instruments per weight: 4 sector-decomposed Z columns (Agro, Ind, Infra, Serv).\n",
  "Cluster: `muni_id` for `f_stat_kp`; HC-robust (no cluster) for `f_stat_cd`.\n",
  "Sample size: ", n_obs_cycle, " muni-year obs across ", n_clust_cycle, " munis.\n\n",

  "## F-stat metric clarification\n\n",
  "In a reduced-form first-stage with no endogenous regressor, `f_stat_cd` ",
  "and `f_stat_kp` collapse to robust / cluster-robust joint Wald F-tests on ",
  "the K=4 sectoral instruments. The naming preserves the plan's vocabulary ",
  "(`Cragg-Donald F` and `Kleibergen-Paap rk Wald F`) while the construction ",
  "is the AR-test joint Wald F.\n\n",
  "## Spec deviation (documented)\n\n",
  "Plan §Step 4 lists C1_FE = `muni FE + year FE`. In the one-cycle proxy ",
  "(treatment_year=2005, term spread to 2005-2008), every `Z_<weight>` is ",
  "time-INVARIANT within muni; adding muni FE absorbs all variation -> ",
  "perfect collinearity. C1_FE here uses YEAR FE only (the maximal ",
  "identifiable FE set in a one-cycle window). The multi-cycle AR baseline ",
  "(ar_baseline.R) does include muni FE, since Z varies across cycles within ",
  "muni in the full panel.\n\n",

  "## Ranking under C1_FE (production-relevant spec)\n\n```\n",
  mk_rank("C1_FE"),
  "\n```\n\n",

  "## Ranking under no_controls\n\n```\n",
  mk_rank("no_controls"),
  "\n```\n\n",

  "## Ranking under C2_FE_R0a\n\n```\n",
  mk_rank("C2_FE_R0a"),
  "\n```\n\n",

  "## Cluster 1 -- Tier B vs Tier C comparison (under C1_FE)\n\n",
  paste(sprintf("- `%s` (%s, c=%d): F_kp = %.3f, F_cd = %.3f",
                cmp_c1$weight_id, cmp_c1$tier, cmp_c1$cluster_id,
                cmp_c1$f_stat_kp, cmp_c1$f_stat_cd),
        collapse = "\n"),
  "\n\n",

  "## Cluster 2 -- Tier B vs Tier C (with optional clustermate, under C1_FE)\n\n",
  paste(sprintf("- `%s` (%s, c=%d): F_kp = %.3f, F_cd = %.3f",
                cmp_c2$weight_id, cmp_c2$tier, cmp_c2$cluster_id,
                cmp_c2$f_stat_kp, cmp_c2$f_stat_cd),
        collapse = "\n"),
  "\n\n",

  "## Flags\n\n",
  if (nrow(flagged_under_1) > 0L) {
    paste0("- **CRITICAL**: ", nrow(flagged_under_1),
           " row(s) with `f_stat_kp` < 1 (broken spec):\n",
           paste(sprintf("    - `%s` [%s] spec=%s: F_kp = %.4f",
                         flagged_under_1$weight_id, flagged_under_1$tier,
                         flagged_under_1$controls, flagged_under_1$f_stat_kp),
                 collapse = "\n"),
           "\n\n")
  } else {
    "- No `f_stat_kp` < 1 cases (all specs pass minimum sanity).\n\n"
  },
  if (nrow(flagged_low_kp) > 0L) {
    paste0("- **Weak-instrument flags** (F_kp < 5):\n",
           paste(sprintf("    - `%s` [%s] spec=%s: F_kp = %.3f",
                         flagged_low_kp$weight_id, flagged_low_kp$tier,
                         flagged_low_kp$controls, flagged_low_kp$f_stat_kp),
                 collapse = "\n"),
           "\n")
  } else {
    "- No F_kp < 5 cases.\n"
  },
  "\n",

  "## Outputs\n\n",
  "- `output/a7_onecycle_proxy_fstats.csv` - main F-stat table (",
  nrow(results), " rows).\n",
  "- `output/a7_tier_b_weights_panel.qs2` - Tier B weights for clusters 1, 2.\n",
  "- `output/a7_tier_b_instruments_panel.qs2` - corresponding muni-level Z.\n",
  "- `output/a7_onecycle_proxy_summary.md` - this narrative.\n"
)

writeLines(summary_md, path_out_summary)
message(sprintf("Saved summary: %s", path_out_summary))

# ==============================================================================
# 13. FINAL CONSOLE SUMMARY
# ==============================================================================

message("\n========================================================")
message("STEP 4 COMPLETE")
message("========================================================")
message(sprintf("F-stat rows: %d", nrow(results)))
message(sprintf("  Tier C (5 reps x 3 specs):       %d", 5L * 3L))
message(sprintf("  Tier C clustermate (1 x 3):      %d", 1L * 3L))
message(sprintf("  Tier B (2 weights x 3 specs):    %d", 2L * 3L))
message(sprintf("  Total expected (5+1+2 x 3):      %d", (5L + 1L + 2L) * 3L))
message(sprintf("Outputs:"))
message(sprintf("  %s", path_out_fstats))
message(sprintf("  %s", path_out_tb_weights))
message(sprintf("  %s", path_out_tb_inst))
message(sprintf("  %s", path_out_summary))

invisible(gc())
