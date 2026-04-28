#!/usr/bin/env Rscript

# ==============================================================================
# Diagnostic: Aggregated First-Stage Collapse
# ==============================================================================
# Diagnoses why the aggregated extensive-margin regression in script 52 loses
# relevance relative to the firm-level first stage. The focus is script 52
# specifically:
#
#   H_jmt ~ FA_bar_mayor + FA_bar_gov + FA_bar_pres | muni_id^sector + muni_id^year
#
# Outputs:
#   - CSV tables in output/diagnostics/agg_sector_collapse/
#   - recommendation_note.md with ranked evidence and caveats
#
# Usage:
#   Rscript diagnose_agg_first_stage_collapse.R [--sector-var=sector_group|cnae_section]
# ==============================================================================

cat("==============================================================================\n")
cat("Diagnostic: Aggregated First-Stage Collapse\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})

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

setDTthreads(1)
fixest::setFixest_nthreads(4)

args <- commandArgs(trailingOnly = TRUE)
svar_flag <- grep("^--sector-var=", args, value = TRUE)
SECTOR_VAR <- "sector_group"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[1])))
  if (!SECTOR_VAR %in% c("sector_group", "cnae_section")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'. Use 'sector_group' or 'cnae_section'.")
  }
}
SCOL <- SECTOR_VAR

baseline_path <- make_output_path("firm_baseline_exposures.qs2")
sector_map_path <- make_output_path("sector_group_mapping.qs2")
z_levels_path <- if (SCOL == "sector_group") {
  make_output_path("shift_share_instruments_levels_sector_grouped.qs2")
} else {
  make_output_path("shift_share_instruments_levels_sector.qs2")
}

out_dir <- file.path(OUTPUT_DIR, "diagnostics", "agg_sector_collapse")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(firm_panel_paths("cycle_specific")$base)) {
  stop("Firm panel not found. Run script 42 first.")
}
if (!file.exists(baseline_path)) {
  stop("Baseline exposures not found: ", baseline_path, "\nRun script 36 first.")
}

cat("Sector variable:", SCOL, "\n")
cat("Output directory:", out_dir, "\n\n")

FA_BASE <- c(
  "FA_mayor_coalition", "FA_gov_coalition", "FA_pres_coalition",
  "FA_mayor_party", "FA_gov_party", "FA_pres_party"
)

FE_BASELINE <- paste0("muni_id^", SCOL, " + muni_id^year")
VCOV_BASELINE <- as.formula(paste0("~ muni_id + ", SCOL))

safe_unique <- function(dt, cols) unique(dt[, ..cols])

weighted_mean_safe <- function(x, w) {
  x_nonmiss <- x[!is.na(x)]
  if (length(x_nonmiss) == 0L) return(NA_real_)
  if (all(abs(x_nonmiss) < 1e-12)) return(0)
  ok <- !is.na(x) & !is.na(w) & w > 0
  if (!any(ok)) return(NA_real_)
  sum(x[ok] * w[ok]) / sum(w[ok])
}

safe_var <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) <= 1L) return(NA_real_)
  var(x)
}

safe_sd <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) <= 1L) return(NA_real_)
  sd(x)
}

safe_cv <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) <= 1L) return(NA_real_)
  mu <- mean(x)
  if (abs(mu) < 1e-12) return(NA_real_)
  sd(x) / abs(mu)
}

qstr <- function(x) {
  if (all(is.na(x))) return("NA")
  sprintf("%.4f", x)
}

mayor_treatment_year <- function(year) {
  out <- rep(NA_integer_, length(year))
  out[year %in% 2005:2008] <- 2005L
  out[year %in% 2009:2012] <- 2009L
  out[year %in% 2013:2016] <- 2013L
  out[year %in% 2017] <- 2017L
  out
}

gp_treatment_year <- function(year) {
  out <- rep(NA_integer_, length(year))
  out[year %in% 2007:2010] <- 2007L
  out[year %in% 2011:2014] <- 2011L
  out[year %in% 2015:2017] <- 2015L
  out
}

fit_fstat <- function(data, depvar, inst_cols, fe, vcov, weights = NULL, subset_label = NA_character_,
                      family = "coalition", spec = "baseline") {
  inst_cols <- inst_cols[inst_cols %in% names(data)]
  if (length(inst_cols) == 0L) {
    return(data.table(
      family = family, spec = spec, subset = subset_label, depvar = depvar,
      instruments = NA_character_, n_obs = NA_integer_, wald_f = NA_real_,
      r2 = NA_real_, n_collin = NA_integer_, fe = fe, weights = ifelse(is.null(weights), "none", deparse(weights[[2L]]))
    ))
  }

  rhs <- paste(inst_cols, collapse = " + ")
  fml <- as.formula(paste0(depvar, " ~ ", rhs, " | ", fe))

  mod <- tryCatch(
    {
      if (is.null(weights)) {
        feols(fml, data = data, vcov = vcov, lean = TRUE, mem.clean = TRUE)
      } else {
        feols(fml, data = data, vcov = vcov, weights = weights, lean = TRUE, mem.clean = TRUE)
      }
    },
    error = function(e) NULL
  )

  if (is.null(mod)) {
    return(data.table(
      family = family, spec = spec, subset = subset_label, depvar = depvar,
      instruments = rhs, n_obs = NA_integer_, wald_f = NA_real_, r2 = NA_real_,
      n_collin = NA_integer_, fe = fe, weights = ifelse(is.null(weights), "none", deparse(weights[[2L]]))
    ))
  }

  keep_pat <- paste0("^(", paste(inst_cols, collapse = "|"), ")$")
  data.table(
    family = family,
    spec = spec,
    subset = subset_label,
    depvar = depvar,
    instruments = rhs,
    n_obs = nobs(mod),
    wald_f = tryCatch(fixest::wald(mod, keep = keep_pat)$stat, error = function(e) NA_real_),
    r2 = tryCatch(fixest::r2(mod, "r2"), error = function(e) NA_real_),
    n_collin = length(mod$collin.var),
    fe = fe,
    weights = ifelse(is.null(weights), "none", deparse(weights[[2L]]))
  )
}

partial_corr_fe <- function(dt, x, y, fe) {
  keep <- dt[!is.na(get(x)) & !is.na(get(y))]
  if (nrow(keep) <= 2L) return(NA_real_)
  mod_x <- tryCatch(feols(as.formula(paste0(x, " ~ 1 | ", fe)), data = keep, lean = TRUE), error = function(e) NULL)
  mod_y <- tryCatch(feols(as.formula(paste0(y, " ~ 1 | ", fe)), data = keep, lean = TRUE), error = function(e) NULL)
  if (is.null(mod_x) || is.null(mod_y)) return(NA_real_)
  cor(resid(mod_x), resid(mod_y), use = "complete.obs")
}

cat("Section 1: Loading and replicating script 52 baseline collapse...\n")

# Determine available FA columns from the sparse instruments file.
paths_agg <- firm_panel_paths("cycle_specific")
panel_nrows <- fst::metadata_fst(paths_agg$base)$nrOfRows

avail_inst_cols_agg <- if (file.exists(paths_agg$sparse) && requireNamespace("fst", quietly = TRUE)) {
  fst::metadata_fst(paths_agg$sparse)$columnNames
} else character(0)
fa_cols <- intersect(FA_BASE, avail_inst_cols_agg)

if (length(fa_cols) == 0L) {
  stop("No FA columns found in sparse instruments file. Run script 42 first.")
}

if (SCOL == "sector_group" && !file.exists(sector_map_path)) {
  stop("sector_group mapping not found: ", sector_map_path)
}

# Load panel (base cols + requested FA cols) via the shared loader.
# Filters to pre-election rows after load (rows where any FA != 0).
base_cols_agg <- c("firm_id", "muni_id", "year", "cnae_section", "has_bndes_fmt")
if (SCOL != "cnae_section") base_cols_agg <- c(base_cols_agg, SCOL)
base_cols_agg <- intersect(base_cols_agg, fst::metadata_fst(paths_agg$base)$columnNames)

dt_pre <- load_firm_panel(
  baseline_type = "cycle_specific",
  columns       = base_cols_agg,
  instruments   = fa_cols,
  zero_fill     = TRUE,
  as_data_table = TRUE
)
dt_pre[, `:=`(firm_id = as.integer(firm_id), muni_id = as.integer(muni_id), year = as.integer(year))]

# Attach sector_group if needed and not yet in panel.
if (SCOL == "sector_group" && !"sector_group" %in% names(dt_pre)) {
  sg_map <- qs_read(sector_map_path)
  setDT(sg_map)
  dt_pre[sg_map, sector_group := i.sector_group, on = "cnae_section"]
  rm(sg_map)
  invisible(gc())
}

# Keep only pre-election rows (any non-zero FA = owner link exists).
fa_mat <- as.matrix(dt_pre[, ..fa_cols])
has_any_fa <- rowSums(fa_mat != 0, na.rm = TRUE) > 0
rm(fa_mat)
dt_pre <- dt_pre[has_any_fa]
rm(has_any_fa)
invisible(gc())

cat(sprintf("  Loaded pre-selected columns from firm panel.\n"))
cat(sprintf("  Pre-election base: %s rows (%.1f%%)\n",
            format(nrow(dt_pre), big.mark = ","), 100 * nrow(dt_pre) / panel_nrows))

agg <- dt_pre[, c(
  list(
    H_jmt = mean(has_bndes_fmt, na.rm = TRUE),
    N_pre = .N,
    n_positive = sum(has_bndes_fmt > 0, na.rm = TRUE)
  ),
  lapply(.SD, mean, na.rm = TRUE)
), by = c("muni_id", "year", SCOL), .SDcols = fa_cols]

fa_bar_cols <- sub("^FA_", "FA_bar_", fa_cols)
setnames(agg, fa_cols, fa_bar_cols)

fwrite(data.table(
  metric = c("n_rows_panel", "n_rows_pre", "n_cells_agg", "mean_H", "median_N_pre", "mean_N_pre"),
  value = c(panel_nrows, nrow(dt_pre), nrow(agg), mean(agg$H_jmt), median(agg$N_pre), mean(agg$N_pre))
), file.path(out_dir, "baseline_aggregation_summary.csv"))

coal_cols <- grep("^FA_bar_(mayor|gov|pres)_coalition$", names(agg), value = TRUE)
party_cols <- grep("^FA_bar_(mayor|gov|pres)_party$", names(agg), value = TRUE)

baseline_reg <- rbindlist(list(
  fit_fstat(agg, "H_jmt", coal_cols, FE_BASELINE, VCOV_BASELINE, family = "coalition", spec = "baseline"),
  fit_fstat(agg, "H_jmt", party_cols, FE_BASELINE, VCOV_BASELINE, family = "party", spec = "baseline")
), use.names = TRUE, fill = TRUE)
fwrite(baseline_reg, file.path(out_dir, "baseline_regression.csv"))

cat("Section 2: H1 diffuse exposure diagnostics...\n")

baseline <- qs_read(baseline_path)
setDT(baseline)
baseline <- baseline[baseline_type == "cycle_specific"]

firm_cycle_weights <- unique(baseline[, .(firm_id, election_year, baseline_type, L_f_0)])
firm_sector_cycle <- safe_unique(dt_pre[, .(
  firm_id, muni_id, year,
  cnae_section = as.character(cnae_section),
  sector_id = as.character(get(SCOL)),
  treat_mayor = mayor_treatment_year(year),
  treat_gp = gp_treatment_year(year)
)], c("firm_id", "muni_id", "year", "cnae_section", "sector_id", "treat_mayor", "treat_gp"))

if (SCOL == "sector_group") {
  firm_sector_cycle <- firm_sector_cycle[!is.na(sector_id)]
}

hhi_input_mayor <- safe_unique(
  firm_sector_cycle[!is.na(treat_mayor), .(firm_id, muni_id, sector_id, election_year = treat_mayor)],
  c("firm_id", "muni_id", "sector_id", "election_year")
)
hhi_input_gp <- safe_unique(
  firm_sector_cycle[!is.na(treat_gp), .(firm_id, muni_id, sector_id, election_year = treat_gp)],
  c("firm_id", "muni_id", "sector_id", "election_year")
)

build_hhi_dt <- function(cell_dt, tier_label) {
  merged <- merge(
    cell_dt,
    baseline[, .(firm_id, party, election_year, L_fp_0)],
    by = c("firm_id", "election_year"),
    all.x = FALSE,
    all.y = FALSE
  )
  if (nrow(merged) == 0L) return(NULL)
  merged[, tier := tier_label]
  sector_party <- merged[, .(L_mjp = sum(L_fp_0, na.rm = TRUE)),
                         by = .(tier, muni_id, election_year, party, sector_id)]
  totals <- sector_party[, .(L_mp = sum(L_mjp, na.rm = TRUE)), by = .(tier, muni_id, election_year, party)]
  sector_party[totals, L_mp := i.L_mp, on = .(tier, muni_id, election_year, party)]
  sector_party <- sector_party[L_mp > 0]
  sector_party[, share_mjp := L_mjp / L_mp]
  sector_party[, .(
    HHI_mp = sum(share_mjp^2, na.rm = TRUE),
    L_mp = unique(L_mp)
  ), by = .(tier, muni_id, election_year, party)]
}

hhi_dt <- rbindlist(list(
  build_hhi_dt(hhi_input_mayor, "mayor"),
  build_hhi_dt(hhi_input_gp, "gov_pres")
), use.names = TRUE, fill = TRUE)

if (!is.null(hhi_dt) && nrow(hhi_dt) > 0) {
  hhi_summary <- hhi_dt[, .(
    n_cells = .N,
    mean_hhi = mean(HHI_mp, na.rm = TRUE),
    median_hhi = median(HHI_mp, na.rm = TRUE),
    p10_hhi = quantile(HHI_mp, 0.10, na.rm = TRUE),
    p90_hhi = quantile(HHI_mp, 0.90, na.rm = TRUE),
    weighted_mean_hhi = weighted.mean(HHI_mp, L_mp, na.rm = TRUE)
  ), by = tier]
  fwrite(hhi_dt, file.path(out_dir, "hhi_party_sector_cycle.csv"))
  fwrite(hhi_summary, file.path(out_dir, "hhi_summary.csv"))
}

comovement_dt <- agg[, .(
  n_sectors = .N,
  mean_H = mean(H_jmt, na.rm = TRUE),
  sd_H = safe_sd(H_jmt),
  cv_H = safe_cv(H_jmt),
  range_H = diff(range(H_jmt, na.rm = TRUE)),
  mean_N_pre = mean(N_pre, na.rm = TRUE)
), by = .(muni_id, year)]
comovement_dt <- comovement_dt[n_sectors >= 2]

comovement_summary <- comovement_dt[, .(
  n_muni_year = .N,
  median_sd_H = median(sd_H, na.rm = TRUE),
  p25_sd_H = quantile(sd_H, 0.25, na.rm = TRUE),
  p75_sd_H = quantile(sd_H, 0.75, na.rm = TRUE),
  median_cv_H = median(cv_H, na.rm = TRUE),
  median_range_H = median(range_H, na.rm = TRUE)
)]
fwrite(comovement_dt, file.path(out_dir, "within_muni_year_h_comovement.csv"))
fwrite(comovement_summary, file.path(out_dir, "within_muni_year_h_comovement_summary.csv"))

direct_cancel <- rbindlist(list(
  fit_fstat(agg, "H_jmt", coal_cols, paste0("muni_id^", SCOL), VCOV_BASELINE, family = "coalition", spec = "no_muni_year_fe"),
  fit_fstat(agg, "H_jmt", party_cols, paste0("muni_id^", SCOL), VCOV_BASELINE, family = "party", spec = "no_muni_year_fe")
), use.names = TRUE, fill = TRUE)
fwrite(direct_cancel, file.path(out_dir, "direct_cancellation_regressions.csv"))

cat("Section 3: H2 sparsity diagnostics...\n")

cell_bins <- copy(agg)
cell_bins[, npre_bin := fifelse(
  N_pre == 1, "1",
  fifelse(N_pre == 2, "2",
          fifelse(N_pre >= 3 & N_pre <= 5, "3-5",
                  fifelse(N_pre >= 6 & N_pre <= 10, "6-10",
                          fifelse(N_pre >= 11 & N_pre <= 50, "11-50", "50+")))))
]

cell_dist_sector <- cell_bins[, .N, by = .(get(SCOL), npre_bin)]
setnames(cell_dist_sector, "get", SCOL)
cell_dist_sector[, share := N / sum(N), by = SCOL]
cell_dist_year <- cell_bins[, .N, by = .(year, npre_bin)]
cell_dist_year[, share := N / sum(N), by = year]
cell_dist_overall <- cell_bins[, .N, by = npre_bin][, share := N / sum(N)]
fwrite(cell_dist_sector, file.path(out_dir, "cell_size_distribution_by_sector.csv"))
fwrite(cell_dist_year, file.path(out_dir, "cell_size_distribution_by_year.csv"))
fwrite(cell_dist_overall, file.path(out_dir, "cell_size_distribution_overall.csv"))

coverage_dt <- agg[, .(
  n_sectors = .N,
  n_positive_h = sum(H_jmt > 0, na.rm = TRUE),
  share_positive_h = mean(H_jmt > 0, na.rm = TRUE),
  avg_H = mean(H_jmt, na.rm = TRUE)
), by = .(muni_id, year)]
coverage_summary <- coverage_dt[, .(
  n_muni_year = .N,
  mean_share_positive_h = mean(share_positive_h, na.rm = TRUE),
  median_share_positive_h = median(share_positive_h, na.rm = TRUE),
  p10_share_positive_h = quantile(share_positive_h, 0.10, na.rm = TRUE),
  p90_share_positive_h = quantile(share_positive_h, 0.90, na.rm = TRUE)
)]
fwrite(coverage_dt, file.path(out_dir, "sector_bndes_coverage_by_muni_year.csv"))
fwrite(coverage_summary, file.path(out_dir, "sector_bndes_coverage_summary.csv"))

threshold_regs <- rbindlist(lapply(c(5L, 10L, 20L, 50L), function(k) {
  sub <- agg[N_pre >= k]
  rbindlist(list(
    fit_fstat(sub, "H_jmt", coal_cols, FE_BASELINE, VCOV_BASELINE, family = "coalition", spec = "npre_threshold", subset_label = paste0("N_pre>=", k)),
    fit_fstat(sub, "H_jmt", party_cols, FE_BASELINE, VCOV_BASELINE, family = "party", spec = "npre_threshold", subset_label = paste0("N_pre>=", k))
  ), use.names = TRUE, fill = TRUE)
}), use.names = TRUE, fill = TRUE)
fwrite(threshold_regs, file.path(out_dir, "conditional_f_by_npre.csv"))

precision_regs <- rbindlist(list(
  fit_fstat(agg, "H_jmt", coal_cols, FE_BASELINE, VCOV_BASELINE, weights = ~N_pre, family = "coalition", spec = "weighted_N_pre"),
  fit_fstat(agg, "H_jmt", coal_cols, FE_BASELINE, VCOV_BASELINE, weights = ~sqrt(N_pre), family = "coalition", spec = "weighted_sqrt_N_pre"),
  fit_fstat(agg, "H_jmt", party_cols, FE_BASELINE, VCOV_BASELINE, weights = ~N_pre, family = "party", spec = "weighted_N_pre"),
  fit_fstat(agg, "H_jmt", party_cols, FE_BASELINE, VCOV_BASELINE, weights = ~sqrt(N_pre), family = "party", spec = "weighted_sqrt_N_pre")
), use.names = TRUE, fill = TRUE)
fwrite(precision_regs, file.path(out_dir, "precision_weighted_regressions.csv"))

cat("Section 4: H3 FE diagnostics...\n")

absorption_dt <- rbindlist(lapply(c(coal_cols, party_cols), function(col) {
  mod <- tryCatch(feols(as.formula(paste0(col, " ~ 1 | ", FE_BASELINE)), data = agg, lean = TRUE), error = function(e) NULL)
  if (is.null(mod)) {
    return(data.table(instrument = col, total_var = var(agg[[col]], na.rm = TRUE), residual_var = NA_real_, absorption_r2 = NA_real_))
  }
  total_var <- var(agg[[col]], na.rm = TRUE)
  resid_var <- var(resid(mod), na.rm = TRUE)
  data.table(
    instrument = col,
    total_var = total_var,
    residual_var = resid_var,
    absorption_r2 = ifelse(is.na(total_var) || total_var <= 0, NA_real_, 1 - resid_var / total_var)
  )
}))
fwrite(absorption_dt, file.path(out_dir, "instrument_fe_absorption.csv"))

within_var_dt <- rbindlist(lapply(c(coal_cols, party_cols), function(col) {
  tmp <- agg[, .(
    n_sectors = .N,
    within_var = safe_var(get(col)),
    within_sd = safe_sd(get(col))
  ), by = .(muni_id, year)]
  tmp <- tmp[n_sectors >= 2]
  tmp[, instrument := col]
  tmp
}), use.names = TRUE, fill = TRUE)
within_var_summary <- within_var_dt[, .(
  n_muni_year = .N,
  median_within_var = median(within_var, na.rm = TRUE),
  p10_within_var = quantile(within_var, 0.10, na.rm = TRUE),
  p90_within_var = quantile(within_var, 0.90, na.rm = TRUE),
  median_within_sd = median(within_sd, na.rm = TRUE)
), by = instrument]
fwrite(within_var_dt, file.path(out_dir, "within_muni_year_instrument_variance.csv"))
fwrite(within_var_summary, file.path(out_dir, "within_muni_year_instrument_variance_summary.csv"))

alt_fe_specs <- list(
  canonical_sector = paste0("muni_id^", SCOL, " + ", SCOL, "^year"),
  minimal = paste0(SCOL, " + year"),
  no_time = paste0("muni_id^", SCOL)
)

alt_fe_dt <- rbindlist(lapply(names(alt_fe_specs), function(spec_name) {
  fe_here <- alt_fe_specs[[spec_name]]
  rbindlist(list(
    fit_fstat(agg, "H_jmt", coal_cols, fe_here, VCOV_BASELINE, family = "coalition", spec = spec_name),
    fit_fstat(agg, "H_jmt", party_cols, fe_here, VCOV_BASELINE, family = "party", spec = spec_name)
  ), use.names = TRUE, fill = TRUE)
}), use.names = TRUE, fill = TRUE)
fwrite(alt_fe_dt, file.path(out_dir, "alternative_fe_regressions.csv"))

limited_variance_note <- within_var_summary[instrument %in% c("FA_bar_mayor_coalition", "FA_bar_gov_coalition", "FA_bar_pres_coalition"),
                                            .(instrument, median_within_var, p10_within_var, p90_within_var)]
fwrite(limited_variance_note, file.path(out_dir, "gov_pres_limited_variance_note.csv"))

cat("Section 5: H4 aggregation-form mismatch...\n")

weights_long <- unique(baseline[, .(firm_id, election_year, L_f_0)])

dt_pre_weights <- copy(dt_pre[, c("firm_id", "muni_id", "year", SCOL, "has_bndes_fmt", fa_cols), with = FALSE])
dt_pre_weights[, treat_mayor := mayor_treatment_year(year)]
dt_pre_weights[, treat_gp := gp_treatment_year(year)]

mayor_w <- copy(weights_long)
setnames(mayor_w, c("election_year", "L_f_0"), c("treat_mayor", "L_f0_mayor"))
gp_w <- copy(weights_long)
setnames(gp_w, c("election_year", "L_f_0"), c("treat_gp", "L_f0_gp"))

dt_pre_weights[mayor_w, L_f0_mayor := i.L_f0_mayor, on = .(firm_id, treat_mayor)]
dt_pre_weights[gp_w, L_f0_gp := i.L_f0_gp, on = .(firm_id, treat_gp)]

owner_agg <- dt_pre_weights[, {
  out <- list(
    H_jmt = mean(has_bndes_fmt, na.rm = TRUE),
    N_pre = .N
  )
  for (col in fa_cols) {
    wcol <- if (grepl("^FA_mayor_", col)) "L_f0_mayor" else "L_f0_gp"
    out[[sub("^FA_", "FA_owner_", col)]] <- weighted_mean_safe(get(col), get(wcol))
  }
  out
}, by = c("muni_id", "year", SCOL)]
owner_cols <- grep("^FA_owner_", names(owner_agg), value = TRUE)

owner_reg <- rbindlist(list(
  fit_fstat(owner_agg, "H_jmt", grep("_coalition$", owner_cols, value = TRUE), FE_BASELINE, VCOV_BASELINE, family = "coalition", spec = "owner_weighted"),
  fit_fstat(owner_agg, "H_jmt", grep("_party$", owner_cols, value = TRUE), FE_BASELINE, VCOV_BASELINE, family = "party", spec = "owner_weighted")
), use.names = TRUE, fill = TRUE)
fwrite(owner_reg, file.path(out_dir, "owner_weighted_regressions.csv"))

owner_compare <- merge(
  agg[, c("muni_id", "year", SCOL, fa_bar_cols), with = FALSE],
  owner_agg[, c("muni_id", "year", SCOL, owner_cols), with = FALSE],
  by = c("muni_id", "year", SCOL),
  all = FALSE
)

cor_pairs <- list(
  c("FA_bar_mayor_coalition", "FA_owner_mayor_coalition"),
  c("FA_bar_gov_coalition", "FA_owner_gov_coalition"),
  c("FA_bar_pres_coalition", "FA_owner_pres_coalition"),
  c("FA_bar_mayor_party", "FA_owner_mayor_party"),
  c("FA_bar_gov_party", "FA_owner_gov_party"),
  c("FA_bar_pres_party", "FA_owner_pres_party")
)

cor_dt <- rbindlist(lapply(cor_pairs, function(pair) {
  x <- pair[[1]]
  y <- pair[[2]]
  if (!all(c(x, y) %in% names(owner_compare))) return(NULL)
  data.table(
    lhs = x,
    rhs = y,
    corr_raw = cor(owner_compare[[x]], owner_compare[[y]], use = "complete.obs"),
    corr_partial = partial_corr_fe(owner_compare, x, y, FE_BASELINE),
    n_complete = sum(complete.cases(owner_compare[, .SD, .SDcols = c(x, y)]))
  )
}), use.names = TRUE, fill = TRUE)

if (file.exists(z_levels_path)) {
  zdt <- qs_read(z_levels_path)
  setDT(zdt)
  if ("baseline_type" %in% names(zdt)) {
    zdt <- zdt[baseline_type == "cycle_specific"]
  }
  z_cols <- grep("^(Z_|Zlev_)(mayor|gov|pres)_(coalition|party)$", names(zdt), value = TRUE)
  zkeep <- c("muni_id", "year", SCOL, z_cols)
  zkeep <- intersect(zkeep, names(zdt))
  zdt <- zdt[, ..zkeep]
  z_merge <- merge(agg[, c("muni_id", "year", SCOL, fa_bar_cols), with = FALSE], zdt,
                   by = c("muni_id", "year", SCOL), all = FALSE)

  z_name_for <- function(fa_col) {
    suffix <- sub("^FA_bar_", "", fa_col)
    z_try <- c(paste0("Z_", suffix), paste0("Zlev_", suffix))
    z_try[z_try %in% names(z_merge)][1]
  }

  z_cor_dt <- rbindlist(lapply(fa_bar_cols, function(col) {
    zcol <- z_name_for(col)
    if (is.na(zcol) || !nzchar(zcol)) return(NULL)
    data.table(
      lhs = col,
      rhs = zcol,
      corr_raw = cor(z_merge[[col]], z_merge[[zcol]], use = "complete.obs"),
      corr_partial = partial_corr_fe(z_merge, col, zcol, FE_BASELINE),
      n_complete = sum(complete.cases(z_merge[, .SD, .SDcols = c(col, zcol)]))
    )
  }), use.names = TRUE, fill = TRUE)
  cor_dt <- rbind(cor_dt, z_cor_dt, use.names = TRUE, fill = TRUE)
}
fwrite(cor_dt, file.path(out_dir, "aggregation_form_correlations.csv"))

cat("Section 6: H5 sector heterogeneity...\n")

joint_coal <- coal_cols
loo_dt <- rbindlist(lapply(sort(unique(agg[[SCOL]])), function(sec) {
  sub <- agg[get(SCOL) != sec]
  fit_fstat(sub, "H_jmt", joint_coal, FE_BASELINE, VCOV_BASELINE,
            family = "coalition", spec = "leave_one_sector_out", subset_label = as.character(sec))
}), use.names = TRUE, fill = TRUE)
fwrite(loo_dt, file.path(out_dir, "leave_one_sector_out_regressions.csv"))

sector_specific_dt <- rbindlist(lapply(sort(unique(agg[[SCOL]])), function(sec) {
  sub <- agg[get(SCOL) == sec]
  fit_fstat(sub, "H_jmt", joint_coal, "muni_id + year", ~muni_id,
            family = "coalition", spec = "sector_specific", subset_label = as.character(sec))
}), use.names = TRUE, fill = TRUE)
fwrite(sector_specific_dt, file.path(out_dir, "sector_specific_regressions.csv"))

cat("Section 7: Recommendation note...\n")

baseline_coal_f <- baseline_reg[family == "coalition", wald_f][1]
no_my_coal_f <- direct_cancel[family == "coalition", wald_f][1]
owner_coal_f <- owner_reg[family == "coalition", wald_f][1]
threshold_peak <- threshold_regs[family == "coalition", max(wald_f, na.rm = TRUE)]
if (!is.finite(threshold_peak)) threshold_peak <- NA_real_
precision_peak <- precision_regs[family == "coalition", max(wald_f, na.rm = TRUE)]
if (!is.finite(precision_peak)) precision_peak <- NA_real_
median_absorb <- absorption_dt[instrument %in% coal_cols, median(absorption_r2, na.rm = TRUE)]
median_within_var <- within_var_summary[instrument %in% coal_cols, median(median_within_var, na.rm = TRUE)]
median_hhi <- if (!is.null(hhi_dt) && nrow(hhi_dt) > 0) median(hhi_dt$HHI_mp, na.rm = TRUE) else NA_real_
median_sd_h <- comovement_summary$median_sd_H[1]

evidence_dt <- rbindlist(list(
  data.table(
    hypothesis = "Cell sparsity / support",
    evidence = ifelse(!is.na(threshold_peak) && !is.na(baseline_coal_f), threshold_peak - baseline_coal_f, NA_real_),
    summary = sprintf("Baseline coalition F=%.2f; best threshold F=%.2f; best precision-weighted F=%.2f",
                      baseline_coal_f, threshold_peak, precision_peak)
  ),
  data.table(
    hypothesis = "FE absorption / limited within-muni-year variation",
    evidence = ifelse(!is.na(median_absorb), median_absorb, NA_real_),
    summary = sprintf("Median FE absorption R2=%.3f; median within-muni-year instrument variance=%s",
                      median_absorb, qstr(median_within_var))
  ),
  data.table(
    hypothesis = "Diffuse exposure / cancellation",
    evidence = ifelse(!is.na(median_hhi), 1 - median_hhi, NA_real_),
    summary = sprintf("Median party-sector HHI=%.3f; median within-muni-year H dispersion=%s",
                      median_hhi, qstr(median_sd_h))
  ),
  data.table(
    hypothesis = "Aggregation-form mismatch",
    evidence = ifelse(!is.na(owner_coal_f) && !is.na(baseline_coal_f), owner_coal_f - baseline_coal_f, NA_real_),
    summary = sprintf("Baseline coalition F=%.2f; owner-weighted coalition F=%.2f",
                      baseline_coal_f, owner_coal_f)
  )
), use.names = TRUE, fill = TRUE)
setorder(evidence_dt, -evidence)
fwrite(evidence_dt, file.path(out_dir, "ranked_evidence_summary.csv"))

note_lines <- c(
  "# Aggregated First-Stage Collapse Diagnostics",
  sprintf("Date: %s", Sys.Date()),
  sprintf("Sector variable: %s", SCOL),
  "",
  "## Baseline Script 52 Replication",
  sprintf("- Coalition baseline F-stat: %.2f", baseline_coal_f),
  sprintf("- Party baseline F-stat: %.2f", baseline_reg[family == "party", wald_f][1]),
  "",
  "## Ranked Evidence With Caveats",
  "| Rank | Hypothesis | Evidence | Summary |",
  "|------|------------|----------|---------|",
  vapply(seq_len(nrow(evidence_dt)), function(i) {
    sprintf("| %d | %s | %.3f | %s |",
            i, evidence_dt$hypothesis[i], evidence_dt$evidence[i], evidence_dt$summary[i])
  }, character(1)),
  "",
  "## Caveats",
  "- This diagnostic is specific to script 52's collapsed extensive-margin regression.",
  "- Higher F under weaker FE is evidence about where the variation lives, not by itself a recommendation to change the production FE.",
  "- The owner-count aggregation check diagnoses aggregation form; it does not by itself validate a replacement estimand.",
  "- Governor and president instruments may show limited within-muni-year cross-sector variation because the alignment shock is common within muni-year; this was treated as an empirical variance question, not a mechanical identity.",
  "",
  "## Key Output Files",
  "- baseline_regression.csv",
  "- hhi_summary.csv",
  "- conditional_f_by_npre.csv",
  "- instrument_fe_absorption.csv",
  "- alternative_fe_regressions.csv",
  "- owner_weighted_regressions.csv",
  "- aggregation_form_correlations.csv",
  "- sector_specific_regressions.csv",
  "- ranked_evidence_summary.csv",
  ""
)
writeLines(note_lines, file.path(out_dir, "recommendation_note.md"))

cat("Diagnostic complete.\n")
cat("Outputs written to:\n  ", out_dir, "\n", sep = "")
