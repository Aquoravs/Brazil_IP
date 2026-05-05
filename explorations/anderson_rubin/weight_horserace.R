#!/usr/bin/env Rscript

# ==============================================================================
# AR Weight Horserace + Tier Ascent
#
# Constructs muni-normalized policy_block AR instruments and runs the approved
# 80-row horserace grid:
#   4 weights x 5 tier specs x 4 controls-ladder specs.
#
# Plan: logs/plans/2026-04-29_weight-horserace.md
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst
#   data/raw/david_ra/owner_aff_firm_year_party_2002_2019.qs2
#   data/processed/alignment_shocks.qs2
#   data/processed/muni_panel_for_regs_policy_block.qs2
# Outputs:
#   explorations/anderson_rubin/output/ar_horserace_results.csv
#   explorations/anderson_rubin/output/ar_horserace_coefficients.csv
#   explorations/anderson_rubin/output/ar_horserace_summary.tex
#   explorations/anderson_rubin/output/ar_horserace_summary.md
#   explorations/anderson_rubin/output/ar_horserace_diagnostics.csv
#   explorations/anderson_rubin/output/ar_horserace_console_table.txt
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})

set.seed(20260429L)

# ---- Bootstrap project paths -------------------------------------------------

resolve_this_script <- function() {
  script_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", script_args, value = TRUE)
  if (length(file_arg)) {
    return(normalizePath(sub("^--file=", "", file_arg[[1]]),
                         winslash = "/", mustWork = TRUE))
  }

  frame_paths <- vapply(
    sys.frames(),
    function(env) {
      ofile <- env$ofile
      if (is.null(ofile) || !nzchar(ofile)) return(NA_character_)
      ofile
    },
    character(1)
  )
  frame_paths <- frame_paths[!is.na(frame_paths)]
  if (length(frame_paths)) {
    return(normalizePath(frame_paths[[length(frame_paths)]],
                         winslash = "/", mustWork = TRUE))
  }

  stop("Cannot determine script path. Run with Rscript path/to/weight_horserace.R.")
}

find_root_from <- function(path) {
  current <- dirname(normalizePath(path, winslash = "/", mustWork = TRUE))
  repeat {
    if (dir.exists(file.path(current, "scripts", "R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find project root containing scripts/R from: ", path)
    }
    current <- parent
  }
}

THIS_SCRIPT <- resolve_this_script()
PROJECT_ROOT_LOCAL <- find_root_from(THIS_SCRIPT)
options(
  politicsregs.project_root = PROJECT_ROOT_LOCAL,
  politicsregs.script_file = THIS_SCRIPT
)
source(file.path(PROJECT_ROOT_LOCAL, "scripts", "R", "_utils", "utils.R"))

# ---- Runtime options ---------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
REUSE_CACHE <- "--reuse-cache" %in% args
FORCE_REBUILD <- "--force-rebuild" %in% args
DRY_RUN <- "--dry-run" %in% args

n_threads <- max(1L, parallel::detectCores() - 1L)
data.table::setDTthreads(n_threads)
fixest::setFixest_nthreads(n_threads)
if ("qopt" %in% getNamespaceExports("qs2")) {
  qs2::qopt("nthreads", n_threads)
}

cat("==============================================================================\n")
cat("AR Weight Horserace + Tier Ascent\n")
cat("==============================================================================\n\n")
cat(sprintf("Threads: data.table=%d, fixest=%d\n", getDTthreads(), n_threads))
cat(sprintf("Options: reuse_cache=%s, force_rebuild=%s, dry_run=%s\n\n",
            REUSE_CACHE, FORCE_REBUILD, DRY_RUN))

# ---- Constants and paths -----------------------------------------------------

SECTORS <- c("Agro", "Ind", "Infra", "Serv")
BASELINE_TYPE <- "cycle_specific"
ALIGN <- "coalition"
OUTCOME <- "log_gdp"
CLUSTER <- "muni_id"

OUT_DIR <- project_path("explorations", "anderson_rubin", "output")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

RESULTS_CSV <- file.path(OUT_DIR, "ar_horserace_results.csv")
COEFF_CSV <- file.path(OUT_DIR, "ar_horserace_coefficients.csv")
SUMMARY_TEX <- file.path(OUT_DIR, "ar_horserace_summary.tex")
SUMMARY_MD <- file.path(OUT_DIR, "ar_horserace_summary.md")
DIAGNOSTICS_CSV <- file.path(OUT_DIR, "ar_horserace_diagnostics.csv")
CONSOLE_TXT <- file.path(OUT_DIR, "ar_horserace_console_table.txt")
NEW_Z_CACHE <- file.path(OUT_DIR, "ar_horserace_new_z_wide.qs2")

RECON_FST <- output_path("rais_bndes_reconstructed.fst")
RECON_QS2 <- output_path("rais_bndes_reconstructed.qs2")
AFF_PATH <- raw_path("david_ra", "owner_aff_firm_year_party_2002_2019.qs2")
SHOCKS_PATH <- output_path("alignment_shocks.qs2")
PANEL_PATH <- output_path("muni_panel_for_regs_policy_block.qs2")
PB_MAP_PATH <- output_path("policy_block_mapping.qs2")
ANCHOR_RESULTS <- file.path(OUT_DIR, "ar_results.csv")

baseline_window_map <- rbindlist(list(
  data.table(treatment_year = 2005L, bl_start = 2000L, bl_end = 2003L, baseline_tier = "mayor"),
  data.table(treatment_year = 2009L, bl_start = 2004L, bl_end = 2007L, baseline_tier = "mayor"),
  data.table(treatment_year = 2013L, bl_start = 2008L, bl_end = 2011L, baseline_tier = "mayor"),
  data.table(treatment_year = 2017L, bl_start = 2012L, bl_end = 2015L, baseline_tier = "mayor"),
  data.table(treatment_year = 2007L, bl_start = 2002L, bl_end = 2005L, baseline_tier = "gov_pres"),
  data.table(treatment_year = 2011L, bl_start = 2006L, bl_end = 2009L, baseline_tier = "gov_pres"),
  data.table(treatment_year = 2015L, bl_start = 2010L, bl_end = 2013L, baseline_tier = "gov_pres")
))

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

weight_specs <- data.table(
  weight_id = c("emp_muni", "bin_muni", "own_muni", "owner_legacy"),
  panel_infix = c("empmuni_", "binmuni_", "ownmuni_", ""),
  panel_label = c("emp_muni", "bin_muni", "own_muni", "owner_legacy"),
  panel_order = 1:4
)

tier_specs <- list(
  mayor = c("mayor"),
  gov = c("gov"),
  mayor_gov = c("mayor", "gov"),
  mayor_pres = c("mayor", "pres"),
  mayor_gov_pres = c("mayor", "gov", "pres")
)

controls_specs <- data.table(
  controls = c("none", "C1_FE", "C2_FE_R0a", "C3_FE_R0b"),
  has_fe = c(FALSE, TRUE, TRUE, TRUE),
  controls_order = 1:4
)

# ---- General helpers ---------------------------------------------------------

stop_if_missing <- function(paths) {
  missing <- paths[!file.exists(paths)]
  if (length(missing)) {
    stop("Missing required input(s):\n  ", paste(missing, collapse = "\n  "))
  }
  invisible(TRUE)
}

regex_escape <- function(x) {
  gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x, perl = TRUE)
}

sig_marker <- function(p) {
  fifelse(is.na(p), "",
    fifelse(p < 0.01, "***",
      fifelse(p < 0.05, "**",
        fifelse(p < 0.10, "*", "")
      )
    )
  )
}

format_p <- function(p) {
  ifelse(is.na(p), "NA", sprintf("%.3f", p))
}

format_f_cell <- function(f_stat, p_value) {
  if (is.na(f_stat) || is.na(p_value)) return("NA")
  paste0(sprintf("%.2f", f_stat), sig_marker(p_value), " [p=", format_p(p_value), "]")
}

tex_escape <- function(x) {
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("_", "\\\\_", x, fixed = TRUE)
  x
}

make_z_name <- function(weight_id, tier, sector) {
  infix <- weight_specs[["panel_infix"]][match(weight_id, weight_specs[["weight_id"]])]
  paste0("ar_Z_", infix, tier, "_", ALIGN, "_", BASELINE_TYPE, "_", sector)
}

z_cols_for_tiers <- function(weight_id, tiers) {
  infix <- weight_specs[["panel_infix"]][match(weight_id, weight_specs[["weight_id"]])]
  unlist(lapply(tiers, function(tt) {
    paste0("ar_Z_", infix, tt, "_", ALIGN, "_", BASELINE_TYPE, "_", SECTORS)
  }), use.names = FALSE)
}

z_cols_for <- function(weight_id, tier_spec) {
  z_cols_for_tiers(weight_id, tier_specs[[tier_spec]])
}

controls_for <- function(controls, tier_spec) {
  tiers <- tier_specs[[tier_spec]]
  if (controls %in% c("none", "C1_FE")) {
    return(character(0L))
  }

  needs_mayor <- "mayor" %in% tiers
  needs_gp <- any(tiers %in% c("gov", "pres"))

  if (controls == "C2_FE_R0a") {
    out <- character(0L)
    if (needs_mayor) out <- c(out, "ec_total_mayor_cycle_specific")
    if (needs_gp) out <- c(out, "ec_total_gov_pres_cycle_specific")
    return(out)
  }

  if (controls == "C3_FE_R0b") {
    out <- character(0L)
    if (needs_mayor) {
      out <- c(out, paste0("ar_exposure_control_mayor_cycle_specific_", SECTORS))
    }
    if (needs_gp) {
      out <- c(out, paste0("ar_exposure_control_gov_pres_cycle_specific_", SECTORS))
    }
    return(out)
  }

  stop("Unknown controls spec: ", controls)
}

parse_coef_tier <- function(variable) {
  sub("^ar_Z_(empmuni_|binmuni_|ownmuni_)?([a-z]+)_coalition_cycle_specific_.*$",
      "\\2", variable)
}

parse_coef_sector <- function(variable) {
  sub("^.*_", "", variable)
}

# ---- Data loading and weight construction -----------------------------------

load_reconstructed <- function() {
  stop_if_missing(c(PB_MAP_PATH))

  load_cols <- c("firm_id", "muni_id", "year", "cnae_section", "n_employees")
  if (file.exists(RECON_FST) && requireNamespace("fst", quietly = TRUE)) {
    cat("Loading reconstructed panel from fst with selected columns...\n")
    firm <- fst::read_fst(RECON_FST, columns = load_cols, as.data.table = TRUE)
  } else if (file.exists(RECON_QS2)) {
    cat("Loading reconstructed panel from qs2...\n")
    firm <- qs2::qs_read(RECON_QS2)
    setDT(firm)
    firm <- firm[, ..load_cols]
  } else {
    stop("Reconstructed panel not found:\n  ", RECON_FST, "\n  ", RECON_QS2)
  }
  setDT(firm)

  firm[, firm_id := as.integer(firm_id)]
  firm[, muni_id := as.integer(muni_id)]
  firm[, year := as.integer(year)]
  firm[, n_employees := as.numeric(n_employees)]

  firm <- firm[
    year >= 2002L & year <= 2017L &
      !is.na(muni_id) & muni_id > 0L &
      !is.na(firm_id) &
      is.finite(n_employees) & n_employees > 0
  ]

  firm <- unique(firm, by = c("firm_id", "muni_id", "year"))

  pb <- qs2::qs_read(PB_MAP_PATH)
  setDT(pb)
  pb <- unique(pb[, .(cnae_section, policy_block)])
  firm[pb, policy_block := i.policy_block, on = "cnae_section"]

  cat(sprintf(
    "  Reconstructed firm panel: %s rows, %s firms, %s munis, years %s-%s\n",
    format(nrow(firm), big.mark = ","),
    format(uniqueN(firm$firm_id), big.mark = ","),
    format(uniqueN(firm$muni_id), big.mark = ","),
    min(firm$year), max(firm$year)
  ))
  cat(sprintf(
    "  Policy-block rows: %s (%.1f%% of positive-employment rows)\n\n",
    format(nrow(firm[policy_block %in% SECTORS]), big.mark = ","),
    100 * nrow(firm[policy_block %in% SECTORS]) / nrow(firm)
  ))

  firm[]
}

load_affiliation <- function() {
  stop_if_missing(c(AFF_PATH))
  cat("Loading owner affiliation file...\n")

  aff <- qs2::qs_read(AFF_PATH)
  setDT(aff)

  required <- c("firm_id", "year", "party", "aff_owners", "share_aff_owners")
  missing <- setdiff(required, names(aff))
  if (length(missing)) {
    stop("Affiliation file missing required columns: ", paste(missing, collapse = ", "))
  }

  aff[, firm_id := as.integer(firm_id)]
  aff[, year := as.integer(year)]
  aff[, party := trimws(as.character(party))]
  aff[, aff_count := as.integer(aff_owners)]
  aff[, share_aff := as.numeric(share_aff_owners)]
  aff <- aff[
    year >= 2002L & year <= 2017L &
      !is.na(firm_id) & !is.na(party) & nzchar(party) &
      !is.na(aff_count) & aff_count >= 0
  ]
  aff[share_aff < 0, share_aff := NA_real_]
  aff[share_aff > 1, share_aff := 1]

  cat("  Computing total owners per firm-year from party shares...\n")
  aff[, total_owners_est := fifelse(
    share_aff > 0 & !is.na(share_aff),
    aff_count / share_aff,
    NA_real_
  )]

  firm_sum <- aff[, .(total_owners_from_sum = sum(aff_count, na.rm = TRUE)),
                  by = .(firm_id, year)]
  firm_share <- aff[!is.na(total_owners_est),
                    .(total_owners_from_share = as.integer(round(
                      median(total_owners_est)
                    ))),
                    by = .(firm_id, year)]
  firm_sum[firm_share,
           total_owners_from_share := i.total_owners_from_share,
           on = .(firm_id, year)]
  firm_sum[, total_owners := fifelse(
    !is.na(total_owners_from_share),
    pmax(total_owners_from_share, total_owners_from_sum),
    total_owners_from_sum
  )]
  owner_year <- firm_sum[total_owners > 0, .(firm_id, year, total_owners)]
  rm(firm_sum, firm_share)

  aff_party_year <- aff[party != "No party",
                        .(aff_count = sum(aff_count, na.rm = TRUE)),
                        by = .(firm_id, year, party)]
  aff_party_year <- aff_party_year[aff_count > 0]

  cat(sprintf(
    "  Affiliation party rows: %s; owner firm-years: %s\n\n",
    format(nrow(aff_party_year), big.mark = ","),
    format(nrow(owner_year), big.mark = ",")
  ))

  list(aff_party_year = aff_party_year, owner_year = owner_year)
}

build_window_weights <- function(firm, aff_party_year, owner_year, window_row) {
  ty <- window_row$treatment_year
  bstart <- window_row$bl_start
  bend <- window_row$bl_end
  baseline_tier <- window_row$baseline_tier
  window_years <- intersect(seq.int(bstart, bend), unique(firm$year))

  cat(sprintf(
    "  Window %s treatment=%d, baseline=%d-%d, years used={%s}\n",
    baseline_tier, ty, bstart, bend, paste(window_years, collapse = ",")
  ))

  firm_window <- firm[year %in% window_years]
  if (!nrow(firm_window)) {
    stop("No reconstructed firm rows in baseline window for treatment year ", ty)
  }

  emp_den <- firm_window[, .(
    E_mB = sum(n_employees, na.rm = TRUE),
    n_firms_emp_den = uniqueN(firm_id)
  ), by = .(muni_id)]

  owner_bl <- owner_year[year %in% window_years,
                         .(total_owners_fB = sum(total_owners, na.rm = TRUE)),
                         by = .(firm_id)]
  owner_bl <- owner_bl[total_owners_fB > 0]

  firm_muni <- unique(firm_window[, .(firm_id, muni_id)])
  owner_den <- merge(firm_muni, owner_bl, by = "firm_id", all.x = TRUE)
  owner_den[is.na(total_owners_fB), total_owners_fB := 0]
  owner_den <- owner_den[, .(
    L_mB = sum(total_owners_fB, na.rm = TRUE),
    n_firms_owner_den = uniqueN(firm_id),
    n_firms_with_owner_den = sum(total_owners_fB > 0, na.rm = TRUE)
  ), by = .(muni_id)]

  aff_bl <- aff_party_year[year %in% window_years,
                           .(aff_count_fpB = sum(aff_count, na.rm = TRUE)),
                           by = .(firm_id, party)]
  aff_bl <- aff_bl[aff_count_fpB > 0]
  aff_bl <- merge(aff_bl, owner_bl, by = "firm_id", all.x = TRUE)
  aff_bl[is.na(total_owners_fB) | total_owners_fB <= 0, total_owners_fB := NA_real_]
  aff_bl[, theta_fpB := fifelse(!is.na(total_owners_fB),
                                aff_count_fpB / total_owners_fB,
                                0)]
  aff_bl[, binary_fpB := as.integer(aff_count_fpB > 0)]

  firm_policy <- firm_window[
    policy_block %in% SECTORS,
    .(n_fB = sum(n_employees, na.rm = TRUE),
      n_years_emp = uniqueN(year)),
    by = .(firm_id, muni_id, policy_block)
  ]
  firm_policy <- firm_policy[n_fB > 0]

  numerator <- merge(
    firm_policy,
    aff_bl[, .(firm_id, party, aff_count_fpB, theta_fpB, binary_fpB)],
    by = "firm_id",
    allow.cartesian = TRUE
  )

  if (!nrow(numerator)) {
    stop("No nonzero affiliation numerator rows for treatment year ", ty)
  }

  num <- numerator[, .(
    emp_num = sum(n_fB * theta_fpB, na.rm = TRUE),
    bin_num = sum(n_fB * binary_fpB, na.rm = TRUE),
    own_num = sum(aff_count_fpB, na.rm = TRUE),
    n_firms_num = uniqueN(firm_id)
  ), by = .(muni_id, policy_block, party)]

  wt <- merge(num, emp_den, by = "muni_id", all.x = TRUE)
  wt <- merge(wt, owner_den, by = "muni_id", all.x = TRUE)
  wt[is.na(E_mB), E_mB := 0]
  wt[is.na(L_mB), L_mB := 0]
  wt[, `:=`(
    w_emp_muni = fifelse(E_mB > 0, emp_num / E_mB, 0),
    w_bin_muni = fifelse(E_mB > 0, bin_num / E_mB, 0),
    w_own_muni = fifelse(L_mB > 0, own_num / L_mB, 0),
    treatment_year = ty,
    baseline_tier = baseline_tier,
    baseline_type = BASELINE_TYPE,
    baseline_years_used = length(window_years)
  )]

  long <- melt(
    wt,
    id.vars = c("muni_id", "policy_block", "party", "treatment_year",
                "baseline_tier", "baseline_type", "baseline_years_used",
                "E_mB", "L_mB", "n_firms_num"),
    measure.vars = c(
      emp_muni = "w_emp_muni",
      bin_muni = "w_bin_muni",
      own_muni = "w_own_muni"
    ),
    variable.name = "weight_id",
    value.name = "weight_value",
    variable.factor = FALSE
  )
  long[, weight_id := fifelse(
    weight_id == "w_emp_muni", "emp_muni",
    fifelse(
      weight_id == "w_bin_muni", "bin_muni",
      fifelse(weight_id == "w_own_muni", "own_muni", weight_id)
    )
  )]
  long[is.na(weight_value), weight_value := 0]

  rm(firm_window, firm_muni, owner_bl, aff_bl, firm_policy, numerator, num, wt)
  invisible(gc())

  long[]
}

build_all_weights <- function(firm, aff_party_year, owner_year) {
  cat("Building cycle-specific muni-normalized baseline weights...\n")
  out <- vector("list", nrow(baseline_window_map))
  for (i in seq_len(nrow(baseline_window_map))) {
    out[[i]] <- build_window_weights(
      firm = firm,
      aff_party_year = aff_party_year,
      owner_year = owner_year,
      window_row = baseline_window_map[i]
    )
  }
  weights <- rbindlist(out, use.names = TRUE, fill = TRUE)
  setorderv(weights, c("weight_id", "baseline_tier", "treatment_year",
                       "muni_id", "policy_block", "party"))

  for (wid in c("emp_muni", "own_muni")) {
    sums <- weights[weight_id == wid,
                    .(sum_w = sum(weight_value, na.rm = TRUE)),
                    by = .(muni_id, policy_block, treatment_year, baseline_tier)]
    max_sum <- max(sums$sum_w, na.rm = TRUE)
    n_bad <- sum(sums$sum_w > 1 + 1e-9, na.rm = TRUE)
    cat(sprintf(
      "  Sum-to-one sanity [%s]: max sum_p=%.8f, violations=%d/%d\n",
      wid, max_sum, n_bad, nrow(sums)
    ))
    if (n_bad > 0L) {
      stop("Sum-to-one sanity failed for ", wid, ": ", n_bad, " violations.")
    }
  }
  bin_sums <- weights[weight_id == "bin_muni",
                      .(sum_w = sum(weight_value, na.rm = TRUE)),
                      by = .(muni_id, policy_block, treatment_year, baseline_tier)]
  cat(sprintf(
    "  Binary weight sanity [bin_muni]: max sum_p=%.8f (unconstrained by design)\n\n",
    max(bin_sums$sum_w, na.rm = TRUE)
  ))

  weights[]
}

build_new_z_wide <- function(weights) {
  stop_if_missing(c(SHOCKS_PATH))
  cat("Building new Z instruments from weights and alignment shocks...\n")

  shocks <- qs2::qs_read(SHOCKS_PATH)
  setDT(shocks)
  shock_cols <- c("align_mayor_coalition", "align_gov_coalition", "align_pres_coalition")
  missing <- setdiff(c("muni_id", "party", "year", shock_cols), names(shocks))
  if (length(missing)) {
    stop("Alignment shocks missing required columns: ", paste(missing, collapse = ", "))
  }
  shocks <- shocks[, c("muni_id", "party", "year", shock_cols), with = FALSE]

  merged <- merge(
    weights,
    shocks,
    by.x = c("muni_id", "party", "treatment_year"),
    by.y = c("muni_id", "party", "year"),
    all.x = TRUE
  )
  for (cc in shock_cols) merged[is.na(get(cc)), (cc) := 0]

  z_list <- list()
  idx <- 0L
  for (tt in c("mayor", "gov", "pres")) {
    needed_baseline <- if (tt == "mayor") "mayor" else "gov_pres"
    align_col <- paste0("align_", tt, "_coalition")
    idx <- idx + 1L
    tmp <- merged[baseline_tier == needed_baseline]
    tmp[, Z_value := weight_value * get(align_col)]
    z_list[[idx]] <- tmp[, .(Z_value = sum(Z_value, na.rm = TRUE)),
                         by = .(muni_id, policy_block, treatment_year, weight_id)]
    z_list[[idx]][, tier := tt]
    cat(sprintf("  Tier %s: %s inauguration rows\n",
                tt, format(nrow(z_list[[idx]]), big.mark = ",")))
  }

  z_inaug <- rbindlist(z_list, use.names = TRUE)
  setnames(z_inaug, "treatment_year", "inaug_year")
  z_spread <- merge(z_inaug, term_map, by = "inaug_year", allow.cartesian = TRUE)
  z_spread <- z_spread[year >= 2002L & year <= 2017L]
  z_spread <- z_spread[, .(Z_value = sum(Z_value, na.rm = TRUE)),
                       by = .(muni_id, year, policy_block, weight_id, tier)]
  z_spread[weight_specs, panel_infix := i.panel_infix, on = .(weight_id)]
  z_spread[, z_col := paste0("ar_Z_", panel_infix, tier, "_", ALIGN,
                             "_", BASELINE_TYPE, "_", policy_block)]

  wide <- dcast(
    z_spread,
    muni_id + year ~ z_col,
    value.var = "Z_value",
    fun.aggregate = sum,
    fill = 0
  )

  expected_cols <- unlist(lapply(c("emp_muni", "bin_muni", "own_muni"), function(wid) {
    z_cols_for_tiers(wid, c("mayor", "gov", "pres"))
  }), use.names = FALSE)
  missing_expected <- setdiff(expected_cols, names(wide))
  for (cc in missing_expected) wide[, (cc) := 0]
  setcolorder(wide, c("muni_id", "year", sort(setdiff(names(wide), c("muni_id", "year")))))

  qs2::qs_save(wide, NEW_Z_CACHE)
  cat(sprintf("  Saved new-Z cache: %s (%.2f MB)\n\n",
              NEW_Z_CACHE, file.size(NEW_Z_CACHE) / 1024^2))

  wide[]
}

# ---- Regression helpers ------------------------------------------------------

run_ar_spec <- function(data, weight_id, tier_spec, controls) {
  z_cols <- z_cols_for(weight_id, tier_spec)
  ctrl_cols <- controls_for(controls, tier_spec)
  has_fe <- controls_specs[["has_fe"]][match(controls, controls_specs[["controls"]])]
  k <- length(z_cols)

  required <- unique(c(OUTCOME, CLUSTER, "year", z_cols, ctrl_cols))
  missing <- setdiff(required, names(data))
  spec_meta <- data.table(
    spec_id = paste(weight_id, tier_spec, controls, sep = "__"),
    weight_id = weight_id,
    tier_spec = tier_spec,
    K = k,
    controls = controls
  )

  if (length(missing)) {
    return(list(
      result = cbind(spec_meta, data.table(
        f_stat = NA_real_, p_value = NA_real_, df1 = NA_real_, df2 = NA_real_,
        n_obs = NA_integer_, n_clusters = NA_integer_, r2 = NA_real_,
        sig_marker = "", reject_05 = NA, status = "missing_columns",
        note = paste(missing, collapse = ", ")
      )),
      coefficients = data.table()
    ))
  }

  rhs <- paste(c(z_cols, ctrl_cols), collapse = " + ")
  fml <- if (isTRUE(has_fe)) {
    as.formula(paste0(OUTCOME, " ~ ", rhs, " | muni_id + year"))
  } else {
    as.formula(paste0(OUTCOME, " ~ ", rhs))
  }

  model_cols <- required
  model_data <- data[, ..model_cols]
  complete <- complete.cases(model_data)
  numeric_cols <- names(model_data)[vapply(model_data, is.numeric, logical(1))]
  for (cc in numeric_cols) {
    complete <- complete & is.finite(model_data[[cc]])
  }
  est_data <- data[complete]

  if (nrow(est_data) == 0L) {
    return(list(
      result = cbind(spec_meta, data.table(
        f_stat = NA_real_, p_value = NA_real_, df1 = NA_real_, df2 = NA_real_,
        n_obs = 0L, n_clusters = 0L, r2 = NA_real_, sig_marker = "",
        reject_05 = NA, status = "empty_sample", note = "No complete observations"
      )),
      coefficients = data.table()
    ))
  }

  fit <- tryCatch(
    fixest::feols(fml, data = est_data, vcov = as.formula(paste0("~", CLUSTER))),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    return(list(
      result = cbind(spec_meta, data.table(
        f_stat = NA_real_, p_value = NA_real_, df1 = NA_real_, df2 = NA_real_,
        n_obs = nrow(est_data), n_clusters = uniqueN(est_data[[CLUSTER]]),
        r2 = NA_real_, sig_marker = "", reject_05 = NA,
        status = "fit_error", note = conditionMessage(fit)
      )),
      coefficients = data.table()
    ))
  }

  estimated_z <- intersect(z_cols, names(stats::coef(fit)))
  if (!length(estimated_z)) {
    f_stat <- p_value <- df1 <- df2 <- NA_real_
    status <- "degenerate"
    note <- "All AR instrument columns were removed or unavailable after collinearity checks"
  } else {
    keep_re <- paste0("^(", paste(regex_escape(estimated_z), collapse = "|"), ")$")
    ar <- tryCatch(
      fixest::wald(fit, keep = keep_re, print = FALSE),
      error = function(e) e
    )
    if (inherits(ar, "error")) {
      f_stat <- p_value <- df1 <- df2 <- NA_real_
      status <- "wald_error"
      note <- conditionMessage(ar)
    } else if (is.list(ar)) {
      f_stat <- unname(ar$stat)
      p_value <- unname(ar$p)
      df1 <- unname(ar$df1)
      df2 <- unname(ar$df2)
      status <- if (is.finite(f_stat)) "ok" else "degenerate"
      note <- ""
    } else {
      f_stat <- suppressWarnings(as.numeric(ar[1]))
      p_value <- suppressWarnings(as.numeric(ar["p"]))
      df1 <- NA_real_
      df2 <- NA_real_
      status <- if (is.finite(f_stat)) "ok" else "degenerate"
      note <- "fixest::wald returned an atomic object"
    }
  }

  r2_val <- tryCatch(
    if (isTRUE(has_fe)) unname(fixest::r2(fit, "wr2")) else unname(fixest::r2(fit, "r2")),
    error = function(e) NA_real_
  )

  result <- cbind(spec_meta, data.table(
    f_stat = f_stat,
    p_value = p_value,
    df1 = df1,
    df2 = df2,
    n_obs = nobs(fit),
    n_clusters = uniqueN(est_data[[CLUSTER]]),
    r2 = r2_val,
    sig_marker = sig_marker(p_value),
    reject_05 = !is.na(p_value) & p_value < 0.05,
    status = status,
    note = note
  ))

  ct <- as.data.table(as.data.frame(fixest::coeftable(fit)), keep.rownames = "variable")
  if (ncol(ct) >= 5L) {
    setnames(ct, names(ct)[2:5], c("estimate", "std_error", "t_stat", "p_value"))
  } else {
    ct <- data.table(variable = character(), estimate = numeric(),
                     std_error = numeric(), t_stat = numeric(), p_value = numeric())
  }
  coef_dt <- data.table(variable = z_cols)
  coef_dt <- merge(coef_dt, ct[, .(variable, estimate, std_error, t_stat, p_value)],
                   by = "variable", all.x = TRUE, sort = FALSE)
  coef_dt[, `:=`(
    estimated = !is.na(estimate),
    ci_low = estimate - 1.96 * std_error,
    ci_high = estimate + 1.96 * std_error,
    tier = parse_coef_tier(variable),
    sector = parse_coef_sector(variable)
  )]
  coef_dt <- cbind(spec_meta, coef_dt)
  coef_dt[, `:=`(n_obs = nobs(fit), n_clusters = uniqueN(est_data[[CLUSTER]]))]

  list(result = result, coefficients = coef_dt)
}

build_spec_grid <- function() {
  grid <- CJ(
    weight_id = weight_specs$weight_id,
    tier_spec = names(tier_specs),
    controls = controls_specs$controls,
    sorted = FALSE
  )
  grid[weight_specs, weight_order := i.panel_order, on = .(weight_id)]
  grid[, tier_order := match(tier_spec, names(tier_specs))]
  grid[controls_specs, controls_order := i.controls_order, on = .(controls)]
  setorder(grid, weight_order, tier_order, controls_order)
  grid[]
}

run_spec_grid <- function(panel) {
  grid <- build_spec_grid()
  cat(sprintf("Running AR grid: %d specs\n", nrow(grid)))

  res_list <- vector("list", nrow(grid))
  coef_list <- vector("list", nrow(grid))
  for (i in seq_len(nrow(grid))) {
    g <- grid[i]
    cat(sprintf(
      "  [%02d/%02d] weight=%s, tier=%s, controls=%s\n",
      i, nrow(grid), g$weight_id, g$tier_spec, g$controls
    ))
    out <- run_ar_spec(panel, g$weight_id, g$tier_spec, g$controls)
    res_list[[i]] <- out$result
    coef_list[[i]] <- out$coefficients
  }

  results <- rbindlist(res_list, use.names = TRUE, fill = TRUE)
  coeffs <- rbindlist(coef_list, use.names = TRUE, fill = TRUE)
  results[]
  list(results = results, coefficients = coeffs)
}

# ---- Output writers ----------------------------------------------------------

make_summary_wide <- function(results, weight_id) {
  wid <- weight_id
  sub <- copy(results[results[["weight_id"]] == wid])
  sub[, cell := mapply(format_f_cell, f_stat, p_value)]
  sub[, tier_order := match(tier_spec, names(tier_specs))]
  wide <- dcast(
    sub,
    tier_order + tier_spec ~ controls,
    value.var = "cell",
    fun.aggregate = function(x) x[1]
  )
  setorder(wide, tier_order)
  wide[, tier_order := NULL]
  wide[]
}

write_markdown_summary <- function(results, path) {
  panels <- list(
    emp_muni = "Panel A: emp_muni",
    bin_muni = "Panel B: bin_muni",
    own_muni = "Panel C: own_muni",
    owner_legacy = "Panel D: owner_legacy"
  )
  lines <- c("# AR Weight Horserace Summary", "")
  for (wid in names(panels)) {
    wide <- make_summary_wide(results, wid)
    setcolorder(wide, c("tier_spec", controls_specs$controls))
    lines <- c(lines, paste0("## ", panels[[wid]]), "")
    lines <- c(lines, paste(names(wide), collapse = " | "))
    lines <- c(lines, paste(rep("---", ncol(wide)), collapse = " | "))
    for (i in seq_len(nrow(wide))) {
      lines <- c(lines, paste(as.character(unlist(wide[i], use.names = FALSE)), collapse = " | "))
    }
    reject_count <- results[weight_id == wid & controls == "C3_FE_R0b",
                            sum(reject_05, na.rm = TRUE)]
    lines <- c(lines, "",
               sprintf("Interpretation hint: %d of 5 C3 specs reject H0 at 5%%.", reject_count),
               "")
  }
  writeLines(lines, path)
}

write_tex_summary <- function(results, path) {
  panels <- list(
    emp_muni = "Panel A: emp\\_muni",
    bin_muni = "Panel B: bin\\_muni",
    own_muni = "Panel C: own\\_muni",
    owner_legacy = "Panel D: owner\\_legacy"
  )
  lines <- c(
    "\\begin{tabular}{lcccc}",
    "\\toprule",
    "Tier spec & None & C1 FE & C2 FE+R0a & C3 FE+R0b \\\\",
    "\\midrule"
  )
  for (wid in names(panels)) {
    wide <- make_summary_wide(results, wid)
    control_cols <- controls_specs$controls
    setcolorder(wide, c("tier_spec", control_cols))
    lines <- c(lines, sprintf("\\multicolumn{5}{l}{%s} \\\\", panels[[wid]]))
    for (i in seq_len(nrow(wide))) {
      row <- wide[i]
      vals <- as.character(unlist(row[, ..control_cols], use.names = FALSE))
      lines <- c(lines, paste0(
        tex_escape(row$tier_spec), " & ",
        paste(tex_escape(vals), collapse = " & "),
        " \\\\"
      ))
    }
    if (!identical(wid, tail(names(panels), 1))) {
      lines <- c(lines, "\\addlinespace")
    }
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}")
  writeLines(lines, path)
}

build_console_table <- function(results) {
  view <- copy(results)
  view[, fp := mapply(format_f_cell, f_stat, p_value)]
  wide <- dcast(view, weight_id + tier_spec ~ controls, value.var = "fp")
  setcolorder(wide, c("weight_id", "tier_spec", controls_specs$controls))
  wide[, weight_order := match(weight_id, weight_specs$weight_id)]
  wide[, tier_order := match(tier_spec, names(tier_specs))]
  setorder(wide, weight_order, tier_order)
  wide[, c("weight_order", "tier_order") := NULL]
  capture.output(print(wide, nrows = Inf))
}

build_diagnostics <- function(panel, results) {
  rows <- list()
  idx <- 0L
  for (wid in weight_specs$weight_id) {
    for (ts in names(tier_specs)) {
      z_cols <- z_cols_for(wid, ts)
      z_cols <- intersect(z_cols, names(panel))
      idx <- idx + 1L
      if (!length(z_cols)) {
        rows[[idx]] <- data.table(
          weight_id = wid, tier_spec = ts, K = 0L,
          weight_mean = NA_real_, weight_sd = NA_real_,
          share_nonzero_obs_per_sector_mean = NA_real_,
          share_nonzero_obs_per_sector_min = NA_real_,
          n_munis_with_nonzero_Z_per_sector_mean = NA_real_,
          n_munis_with_nonzero_Z_per_sector_min = NA_real_,
          n_clusters_after_controls = NA_integer_
        )
        next
      }
      vals <- unlist(panel[, ..z_cols], use.names = FALSE)
      sec_stats <- rbindlist(lapply(z_cols, function(cc) {
        data.table(
          variable = cc,
          share_nonzero = mean(abs(panel[[cc]]) > 1e-12, na.rm = TRUE),
          n_munis_nonzero = uniqueN(panel[abs(get(cc)) > 1e-12, muni_id])
        )
      }))
      c3_ctrl <- controls_for("C3_FE_R0b", ts)
      complete_cols <- intersect(c(OUTCOME, CLUSTER, "year", z_cols, c3_ctrl), names(panel))
      tmp <- panel[, ..complete_cols]
      keep <- complete.cases(tmp)
      num_cols <- names(tmp)[vapply(tmp, is.numeric, logical(1))]
      for (cc in num_cols) keep <- keep & is.finite(tmp[[cc]])
      rows[[idx]] <- data.table(
        weight_id = wid,
        tier_spec = ts,
        K = length(z_cols),
        weight_mean = mean(vals, na.rm = TRUE),
        weight_sd = sd(vals, na.rm = TRUE),
        share_nonzero_obs_per_sector_mean = mean(sec_stats$share_nonzero, na.rm = TRUE),
        share_nonzero_obs_per_sector_min = min(sec_stats$share_nonzero, na.rm = TRUE),
        n_munis_with_nonzero_Z_per_sector_mean = mean(sec_stats$n_munis_nonzero, na.rm = TRUE),
        n_munis_with_nonzero_Z_per_sector_min = min(sec_stats$n_munis_nonzero, na.rm = TRUE),
        n_clusters_after_controls = uniqueN(panel[keep, muni_id])
      )
    }
  }
  rbindlist(rows, use.names = TRUE, fill = TRUE)
}

check_anchor <- function(results) {
  if (!file.exists(ANCHOR_RESULTS)) {
    warning("Anchor ar_results.csv not found; skipping replication anchor check.")
    return(invisible(FALSE))
  }
  anchor <- fread(ANCHOR_RESULTS)
  if (!"spec_id" %in% names(anchor) || !"f_stat" %in% names(anchor)) {
    warning("Anchor ar_results.csv has unexpected schema; skipping replication anchor check.")
    return(invisible(FALSE))
  }
  anchor_f <- anchor[spec_id == "primary", f_stat][1]
  new_f <- results[
    weight_id == "owner_legacy" &
      tier_spec == "mayor" &
      controls == "none",
    f_stat
  ][1]
  delta <- abs(new_f - anchor_f)
  cat(sprintf(
    "Replication anchor: existing primary F=%.12f, horserace owner_legacy mayor none F=%.12f, delta=%.3g\n",
    anchor_f, new_f, delta
  ))
  if (!is.finite(delta) || delta > 1e-3) {
    stop("Replication anchor failed: owner_legacy primary F-stat does not match ar_results.csv within 1e-3.")
  }
  invisible(TRUE)
}

# ---- Main --------------------------------------------------------------------

stop_if_missing(c(AFF_PATH, SHOCKS_PATH, PANEL_PATH, PB_MAP_PATH))
if (!file.exists(RECON_FST) && !file.exists(RECON_QS2)) {
  stop("Reconstructed panel not found:\n  ", RECON_FST, "\n  ", RECON_QS2)
}

if (DRY_RUN) {
  cat("Dry run requested. Inputs are present and script parsed successfully.\n")
  quit(status = 0L)
}

if (REUSE_CACHE && file.exists(NEW_Z_CACHE) && !FORCE_REBUILD) {
  cat("Loading new-Z cache: ", NEW_Z_CACHE, "\n", sep = "")
  new_z_wide <- qs2::qs_read(NEW_Z_CACHE)
  setDT(new_z_wide)
} else {
  firm <- load_reconstructed()
  aff_objs <- load_affiliation()
  weights <- build_all_weights(
    firm = firm,
    aff_party_year = aff_objs$aff_party_year,
    owner_year = aff_objs$owner_year
  )
  rm(aff_objs); invisible(gc())
  new_z_wide <- build_new_z_wide(weights)
  rm(firm, weights); invisible(gc())
}

cat("Loading Panel B and merging new instruments...\n")
panel <- qs2::qs_read(PANEL_PATH)
setDT(panel)
panel[, muni_id := as.integer(muni_id)]
panel[, year := as.integer(year)]
panel <- merge(panel, new_z_wide, by = c("muni_id", "year"), all.x = TRUE)
new_cols <- setdiff(names(new_z_wide), c("muni_id", "year"))
for (cc in new_cols) panel[is.na(get(cc)), (cc) := 0]
panel <- panel[!is.na(log_gdp) & is.finite(log_gdp)]
cat(sprintf(
  "  Estimation panel: %s rows, %s munis, %s new Z cols\n\n",
  format(nrow(panel), big.mark = ","),
  format(uniqueN(panel$muni_id), big.mark = ","),
  length(new_cols)
))

grid_out <- run_spec_grid(panel)
results <- grid_out$results
coefficients <- grid_out$coefficients

check_anchor(results)

diagnostics <- build_diagnostics(panel, results)
console_lines <- build_console_table(results)

fwrite(results, RESULTS_CSV)
fwrite(coefficients, COEFF_CSV)
fwrite(diagnostics, DIAGNOSTICS_CSV)
write_markdown_summary(results, SUMMARY_MD)
write_tex_summary(results, SUMMARY_TEX)
writeLines(console_lines, CONSOLE_TXT)

cat("\n=== AR HORSE RACE CONSOLE TABLE ===\n")
cat(paste(console_lines, collapse = "\n"), "\n")

cat("\nSaved outputs:\n")
cat("  ", RESULTS_CSV, "\n", sep = "")
cat("  ", COEFF_CSV, "\n", sep = "")
cat("  ", SUMMARY_TEX, "\n", sep = "")
cat("  ", SUMMARY_MD, "\n", sep = "")
cat("  ", DIAGNOSTICS_CSV, "\n", sep = "")
cat("  ", CONSOLE_TXT, "\n", sep = "")

if (nrow(results) != 80L) {
  stop("Expected 80 result rows, found ", nrow(results))
}
if (any(results$status != "ok")) {
  warning("Some specifications did not complete cleanly: ",
          paste(unique(results[status != "ok", status]), collapse = ", "))
}

cat("\nweight_horserace.R completed successfully.\n")
