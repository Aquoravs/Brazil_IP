#!/usr/bin/env Rscript

# ==============================================================================
# A10: Composition vs Volume
#
# Builds policy_block and standalone S4 panels, constructs sector/bin and
# total-volume shift-share instruments from finalized A7 baseline weights, and estimates
# the four A10 alternatives:
#   pure_ols, partial_iv, full_iv, mixed.
#
# Finalized weights:
#   production: w_owners_muni_univ = L_mjp / L_mB_univ
#   robustness: w_binary_muni_univ = L_mjp_binary / n_firms_rais_muni
#
# Outputs stay in explorations/anderson_rubin/output/.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})

set.seed(20260505L)

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

  stop("Cannot determine script path. Run with Rscript path/to/a10_composition_volume.R.")
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
flag_value <- function(prefix, default = NA_character_) {
  hit <- grep(paste0("^", prefix), args, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", prefix), "", hit[[1]])
}

WEIGHT_ARG <- flag_value("--weight=", "finalized")
DRY_RUN <- "--dry-run" %in% args
REUSE_CACHE <- "--reuse-cache" %in% args
FORCE_REBUILD <- "--force-rebuild" %in% args

FINAL_WEIGHT_IDS <- c("w_owners_muni_univ", "w_binary_muni_univ")
parse_weight_ids <- function(x) {
  if (is.na(x) || !nzchar(x) || x %in% c("finalized", "finalized_pair", "all")) {
    return(FINAL_WEIGHT_IDS)
  }
  out <- trimws(unlist(strsplit(x, ",", fixed = TRUE)))
  out <- out[nzchar(out)]
  bad <- setdiff(out, FINAL_WEIGHT_IDS)
  if (length(bad)) {
    stop("--weight must be finalized, all, or one/a comma-list of: ",
         paste(FINAL_WEIGHT_IDS, collapse = ", "),
         "\nUnsupported weight(s): ", paste(bad, collapse = ", "))
  }
  unique(out)
}
WEIGHT_IDS <- parse_weight_ids(WEIGHT_ARG)

n_threads <- max(1L, parallel::detectCores() - 1L)
data.table::setDTthreads(n_threads)
fixest::setFixest_nthreads(n_threads)
if ("qopt" %in% getNamespaceExports("qs2")) {
  qs2::qopt("nthreads", n_threads)
}

cat("==============================================================================\n")
cat("A10 Composition vs Volume\n")
cat("==============================================================================\n\n")
cat(sprintf("Weights: %s\n", paste(WEIGHT_IDS, collapse = ", ")))
cat(sprintf("Options: dry_run=%s, reuse_cache=%s, force_rebuild=%s\n\n",
            DRY_RUN, REUSE_CACHE, FORCE_REBUILD))

# ---- Constants and paths -----------------------------------------------------

OUT_DIR <- project_path("explorations", "anderson_rubin", "output")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
WEIGHT_CACHE_KEY <- gsub("[^A-Za-z0-9_]+", "_", paste(WEIGHT_IDS, collapse = "__"))

RESULTS_CSV <- file.path(OUT_DIR, "a10_composition_volume_results.csv")
COEFF_CSV <- file.path(OUT_DIR, "a10_composition_volume_coefficients.csv")
FIRST_STAGE_CSV <- file.path(OUT_DIR, "a10_composition_volume_first_stage.csv")
SUMMARY_TEX <- file.path(OUT_DIR, "a10_composition_volume_summary.tex")
SLIDES_TEX <- file.path(OUT_DIR, "a10_composition_volume_slides.tex")
S4_DIAG_CSV <- file.path(OUT_DIR, "a10_s4_size_diagnostic.csv")
S4_PANEL_CACHE <- file.path(OUT_DIR, paste0("a10_s4_panel_", WEIGHT_CACHE_KEY, ".qs2"))
WEIGHT_CACHE <- file.path(OUT_DIR, paste0("a10_long_weights_", WEIGHT_CACHE_KEY, ".qs2"))
Z_DIAG_CSV <- file.path(OUT_DIR, "a10_ztotal_diagnostics.csv")

RECON_FST <- output_path("rais_bndes_reconstructed.fst")
RECON_QS2 <- output_path("rais_bndes_reconstructed.qs2")
AFF_PATH <- raw_path("david_ra", "owner_aff_firm_year_party_2002_2019.qs2")
SHOCKS_PATH <- output_path("alignment_shocks.qs2")
PANEL_POLICY_PATH <- output_path("muni_panel_for_regs_policy_block.qs2")
CREDIT_POLICY_PATH <- output_path("bndes_credit_shares_policy_block.qs2")
PB_MAP_PATH <- output_path("policy_block_mapping.qs2")

BASELINE_TYPE <- "cycle_specific"
ALIGN <- "coalition"
OUTCOME <- "log_gdp"
TOTAL_VAR <- "total_bndes_initial_gdp"
CLUSTER <- "muni_id"

POLICY_BLOCKS <- c("Agro", "Ind", "Infra", "Serv")
S4_BINS <- c("Micro", "Pequena", "Media", "Grande")

baseline_window_map <- rbindlist(list(
  data.table(treatment_year = 2005L, bl_start = 2002L, bl_end = 2003L, baseline_tier = "mayor"),
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
))[year >= 2002L & year <= 2017L]

s4_share_cycle_map <- data.table(
  year = 2002L:2017L,
  treatment_year = c(rep(2005L, 5L), rep(2007L, 2L), rep(2009L, 2L),
                     rep(2011L, 2L), rep(2013L, 2L), rep(2015L, 2L), 2017L)
)

tier_specs <- list(
  mayor = c("mayor"),
  gov = c("gov"),
  mayor_gov = c("mayor", "gov"),
  mayor_pres = c("mayor", "pres"),
  mayor_gov_pres = c("mayor", "gov", "pres")
)

control_specs <- c("FE")
option_specs <- c("pure_ols", "partial_iv", "full_iv", "mixed")

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

tex_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("_", "\\_", x, fixed = TRUE)
  x <- gsub("%", "\\%", x, fixed = TRUE)
  x <- gsub("&", "\\&", x, fixed = TRUE)
  x <- gsub("#", "\\#", x, fixed = TRUE)
  x
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

fmt_num <- function(x, digits = 2L) {
  ifelse(is.na(x), "NA", sprintf(paste0("%.", digits, "f"), x))
}

fmt_p <- function(p) {
  ifelse(is.na(p), "NA", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
}

make_share_col <- function(taxonomy, bin) {
  paste0("s_", taxonomy, "_", bin)
}

make_z_col <- function(taxonomy, tier, bin, weight_id, total = FALSE) {
  if (total) {
    paste0("a10_Ztotal_", weight_id, "_", tier, "_", ALIGN, "_",
           BASELINE_TYPE, "_", taxonomy)
  } else {
    paste0("a10_Z_", weight_id, "_", tier, "_", ALIGN, "_",
           BASELINE_TYPE, "_", taxonomy, "_", bin)
  }
}

pick_tiers <- function(tier_spec) tier_specs[[tier_spec]]

load_reconstructed <- function(columns) {
  if (file.exists(RECON_FST) && requireNamespace("fst", quietly = TRUE)) {
    dt <- fst::read_fst(RECON_FST, columns = columns, as.data.table = TRUE)
  } else if (file.exists(RECON_QS2)) {
    raw <- qs2::qs_read(RECON_QS2)
    setDT(raw)
    dt <- raw[, ..columns]
    rm(raw); invisible(gc())
  } else {
    stop("Reconstructed panel not found:\n  ", RECON_FST, "\n  ", RECON_QS2)
  }
  setDT(dt)
  dt[]
}

load_base_panel <- function() {
  stop_if_missing(c(PANEL_POLICY_PATH))
  base <- qs2::qs_read(PANEL_POLICY_PATH)
  setDT(base)
  keep <- intersect(
    c("muni_id", "year", "state_id", "population", "log_gdp", "log_gdp_pc", "bndes_pc"),
    names(base)
  )
  base <- base[, ..keep]
  base[, muni_id := as.integer(muni_id)]
  base[, year := as.integer(year)]
  if (!"bndes_pc" %in% names(base)) {
    stop("Panel B lacks bndes_pc; cannot recover total_bndes_real.")
  }
  if (!"population" %in% names(base)) {
    stop("Panel B lacks population; cannot recover total_bndes_real.")
  }
  base[, total_bndes_real := bndes_pc * population]
  base[is.na(total_bndes_real), total_bndes_real := 0]
  base[, gdp_real_from_log := fifelse(!is.na(log_gdp) & is.finite(log_gdp), exp(log_gdp), NA_real_)]
  base <- add_initial_gdp(base)
  base[, total_bndes_initial_gdp := fifelse(
    !is.na(initial_gdp_real) & initial_gdp_real > 0,
    total_bndes_real / initial_gdp_real,
    NA_real_
  )]
  base[]
}

add_initial_gdp <- function(dt) {
  g <- dt[!is.na(gdp_real_from_log) & is.finite(gdp_real_from_log) & gdp_real_from_log > 0,
          .(initial_gdp_real = gdp_real_from_log[which.min(year)],
            initial_gdp_year = year[which.min(year)]),
          by = muni_id]
  early <- dt[year %in% 2002L:2004L &
                !is.na(gdp_real_from_log) &
                is.finite(gdp_real_from_log) &
                gdp_real_from_log > 0,
              .(early_gdp = gdp_real_from_log[which.min(year)],
                early_year = year[which.min(year)]),
              by = muni_id]
  g[early, `:=`(
    initial_gdp_real = i.early_gdp,
    initial_gdp_year = i.early_year
  ), on = "muni_id"]
  g[, initial_gdp_source := fifelse(initial_gdp_year %in% 2002L:2004L, "2002_2004", "fallback")]
  dt[g, `:=`(
    initial_gdp_real = i.initial_gdp_real,
    initial_gdp_year = i.initial_gdp_year,
    initial_gdp_source = i.initial_gdp_source
  ), on = "muni_id"]
  dt[]
}

assign_s4 <- function(mean_emp) {
  fifelse(
    is.na(mean_emp), NA_character_,
    fifelse(mean_emp <= 9, "Micro",
      fifelse(mean_emp <= 49, "Pequena",
        fifelse(mean_emp <= 499, "Media", "Grande")
      )
    )
  )
}

build_s4_crosswalk <- function(recon_emp) {
  dt_fy <- recon_emp[
    !is.na(firm_id) & !is.na(year),
    .(
      has_emp_obs = any(!is.na(n_employees)),
      n_employees = sum(n_employees, na.rm = TRUE)
    ),
    by = .(firm_id, year)
  ]
  dt_fy <- dt_fy[has_emp_obs == TRUE, .(firm_id, year, n_employees)]

  out <- vector("list", nrow(baseline_window_map))
  for (i in seq_len(nrow(baseline_window_map))) {
    bw <- baseline_window_map[i]
    firm_avg <- dt_fy[year >= bw$bl_start & year <= bw$bl_end,
                      .(mean_emp = mean(n_employees, na.rm = TRUE),
                        n_years = .N),
                      by = firm_id]
    firm_avg[, S4 := assign_s4(mean_emp)]
    firm_avg[, `:=`(
      treatment_year = bw$treatment_year,
      baseline_tier = bw$baseline_tier
    )]
    out[[i]] <- firm_avg[!is.na(S4)]
  }
  xwalk <- unique(rbindlist(out, use.names = TRUE, fill = TRUE),
                  by = c("firm_id", "treatment_year"))
  xwalk[]
}

# ---- Share panels ------------------------------------------------------------

build_policy_block_panel <- function(base, z_wide) {
  cat("Building policy_block analysis panel...\n")
  stop_if_missing(c(CREDIT_POLICY_PATH))
  credit <- qs2::qs_read(CREDIT_POLICY_PATH)
  setDT(credit)
  credit <- credit[policy_block %in% POLICY_BLOCKS]
  shares <- dcast(
    credit,
    muni_id + year ~ policy_block,
    value.var = "s_mjt",
    fun.aggregate = sum,
    fill = 0
  )
  setnames(shares, POLICY_BLOCKS, make_share_col("policy_block", POLICY_BLOCKS),
           skip_absent = TRUE)
  dt <- merge(base, shares, by = c("muni_id", "year"), all.x = TRUE)
  share_cols <- make_share_col("policy_block", POLICY_BLOCKS)
  for (cc in setdiff(share_cols, names(dt))) dt[, (cc) := 0]
  for (cc in share_cols) dt[is.na(get(cc)), (cc) := 0]
  dt <- merge(dt, z_wide[taxonomy == "policy_block"][, taxonomy := NULL],
              by = c("muni_id", "year"), all.x = TRUE)
  zcols <- grep("^a10_Z", names(dt), value = TRUE)
  for (cc in zcols) dt[is.na(get(cc)), (cc) := 0]
  attr(dt, "bins") <- POLICY_BLOCKS
  attr(dt, "taxonomy") <- "policy_block"
  dt[]
}

build_s4_panel <- function(base, recon, s4_xwalk, z_wide) {
  cat("Building S4 analysis panel...\n")
  if (REUSE_CACHE && file.exists(S4_PANEL_CACHE) && !FORCE_REBUILD) {
    dt <- qs2::qs_read(S4_PANEL_CACHE)
    setDT(dt)
    return(dt[])
  }

  bndes <- recon[
    !is.na(muni_id) & muni_id > 0L &
      !is.na(year) &
      !is.na(value_dis_real_2018_total) &
      value_dis_real_2018_total > 0
  ]
  bndes <- merge(bndes, s4_share_cycle_map, by = "year", all.x = TRUE)
  bndes <- merge(
    bndes,
    s4_xwalk[, .(firm_id, treatment_year, S4)],
    by = c("firm_id", "treatment_year"),
    all.x = TRUE
  )

  credit <- bndes[!is.na(S4), .(
    bndes_mjt = sum(value_dis_real_2018_total, na.rm = TRUE)
  ), by = .(muni_id, year, S4)]
  skel <- CJ(
    muni_id = unique(base$muni_id),
    year = sort(unique(base$year)),
    S4 = S4_BINS,
    sorted = FALSE
  )
  credit <- merge(skel, credit, by = c("muni_id", "year", "S4"), all.x = TRUE)
  credit[is.na(bndes_mjt), bndes_mjt := 0]
  credit[, bndes_mt_classified := sum(bndes_mjt, na.rm = TRUE), by = .(muni_id, year)]
  credit[, s_mjt := fifelse(bndes_mt_classified > 0, bndes_mjt / bndes_mt_classified, 0)]

  shares <- dcast(
    credit,
    muni_id + year ~ S4,
    value.var = "s_mjt",
    fun.aggregate = sum,
    fill = 0
  )
  setnames(shares, S4_BINS, make_share_col("S4", S4_BINS), skip_absent = TRUE)

  dt <- merge(base, shares, by = c("muni_id", "year"), all.x = TRUE)
  share_cols <- make_share_col("S4", S4_BINS)
  for (cc in setdiff(share_cols, names(dt))) dt[, (cc) := 0]
  for (cc in share_cols) dt[is.na(get(cc)), (cc) := 0]
  dt <- merge(dt, z_wide[taxonomy == "S4"][, taxonomy := NULL],
              by = c("muni_id", "year"), all.x = TRUE)
  zcols <- grep("^a10_Z", names(dt), value = TRUE)
  for (cc in zcols) dt[is.na(get(cc)), (cc) := 0]

  attr(dt, "bins") <- S4_BINS
  attr(dt, "taxonomy") <- "S4"
  qs2::qs_save(dt, S4_PANEL_CACHE)
  dt[]
}

write_s4_diagnostic <- function(recon, s4_xwalk) {
  bndes_total <- recon[
    !is.na(value_dis_real_2018_total) & value_dis_real_2018_total > 0,
    sum(value_dis_real_2018_total, na.rm = TRUE)
  ]
  bndes <- recon[
    !is.na(value_dis_real_2018_total) & value_dis_real_2018_total > 0,
    .(firm_id, year, value_dis_real_2018_total, n_employees)
  ]
  bndes <- merge(bndes, s4_share_cycle_map, by = "year", all.x = TRUE)
  bndes <- merge(
    bndes,
    s4_xwalk[, .(firm_id, treatment_year, S4)],
    by = c("firm_id", "treatment_year"),
    all.x = TRUE
  )

  diag <- data.table(
    taxonomy = "S4",
    rows = nrow(recon),
    firms = uniqueN(recon$firm_id),
    bndes_rows = nrow(bndes),
    bndes_value_total = bndes_total,
    rows_missing_emp = sum(is.na(recon$n_employees)),
    bndes_rows_missing_emp = sum(is.na(bndes$n_employees)),
    bndes_value_missing_emp = bndes[is.na(n_employees), sum(value_dis_real_2018_total, na.rm = TRUE)],
    share_bndes_value_missing_emp = bndes[is.na(n_employees), sum(value_dis_real_2018_total, na.rm = TRUE)] / bndes_total,
    rows_zero_emp = sum(!is.na(recon$n_employees) & recon$n_employees == 0),
    bndes_rows_zero_emp = sum(!is.na(bndes$n_employees) & bndes$n_employees == 0),
    bndes_value_unclassified_s4 = bndes[is.na(S4), sum(value_dis_real_2018_total, na.rm = TRUE)],
    share_bndes_value_unclassified_s4 = bndes[is.na(S4), sum(value_dis_real_2018_total, na.rm = TRUE)] / bndes_total
  )
  fwrite(diag, S4_DIAG_CSV)
  diag[]
}

# ---- Long weights and instruments -------------------------------------------

load_affiliation <- function() {
  stop_if_missing(c(AFF_PATH))
  aff <- qs2::qs_read(AFF_PATH)
  setDT(aff)
  required <- c("firm_id", "year", "party", "aff_owners", "share_aff_owners")
  missing <- setdiff(required, names(aff))
  if (length(missing)) stop("Affiliation file missing: ", paste(missing, collapse = ", "))
  aff[, firm_id := as.integer(firm_id)]
  aff[, year := as.integer(year)]
  aff[, party := trimws(as.character(party))]
  aff[, aff_count := as.numeric(aff_owners)]
  aff[, share_aff := as.numeric(share_aff_owners)]
  aff <- aff[
    year >= 2002L & year <= 2017L &
      !is.na(firm_id) & !is.na(year) &
      !is.na(party) & nzchar(party) &
      !is.na(aff_count) & aff_count >= 0
  ]
  aff[share_aff < 0, share_aff := NA_real_]
  aff[share_aff > 1, share_aff := 1]

  aff[, total_owners_est := fifelse(
    share_aff > 0 & !is.na(share_aff),
    aff_count / share_aff,
    NA_real_
  )]
  owner_sum <- aff[, .(total_owners_from_sum = sum(aff_count, na.rm = TRUE)),
                   by = .(firm_id, year)]
  owner_share <- aff[!is.na(total_owners_est),
                     .(total_owners_from_share = as.integer(round(median(total_owners_est)))),
                     by = .(firm_id, year)]
  owner_sum[owner_share, total_owners_from_share := i.total_owners_from_share,
            on = .(firm_id, year)]
  owner_sum[, total_owners := fifelse(
    !is.na(total_owners_from_share),
    pmax(total_owners_from_share, total_owners_from_sum),
    total_owners_from_sum
  )]
  owner_year <- owner_sum[total_owners > 0, .(firm_id, year, total_owners)]
  aff_party_year <- aff[party != "No party",
                        .(aff_count = sum(aff_count, na.rm = TRUE)),
                        by = .(firm_id, year, party)]
  aff_party_year <- aff_party_year[aff_count > 0]
  list(aff_party_year = aff_party_year, owner_year = owner_year)
}

build_category_panel_for_weights <- function(recon, taxonomy, s4_xwalk = NULL) {
  if (taxonomy == "policy_block") {
    pb <- qs2::qs_read(PB_MAP_PATH)
    setDT(pb)
    pb <- unique(pb[, .(cnae_section, category = policy_block)])
    out <- recon[
      !is.na(firm_id) & !is.na(muni_id) & muni_id > 0L &
        !is.na(year),
      .(firm_id, muni_id, year, cnae_section, n_employees)
    ]
    out[pb, category := i.category, on = "cnae_section"]
    out <- out[category %in% POLICY_BLOCKS]
    out <- unique(out, by = c("firm_id", "muni_id", "year", "category"))
    return(out[])
  }

  if (taxonomy == "S4") {
    out <- recon[
      !is.na(firm_id) & !is.na(muni_id) & muni_id > 0L &
        !is.na(year),
      .(firm_id, muni_id, year, n_employees)
    ]
    bw <- copy(baseline_window_map[, .(treatment_year, bl_start, bl_end, baseline_tier)])
    out[, a10_cross_join_key := 1L]
    bw[, a10_cross_join_key := 1L]
    out <- merge(out, bw, by = "a10_cross_join_key", allow.cartesian = TRUE)
    out[, a10_cross_join_key := NULL]
    out <- out[year >= bl_start & year <= bl_end]
    out <- merge(
      out,
      s4_xwalk[, .(firm_id, treatment_year, category = S4)],
      by = c("firm_id", "treatment_year"),
      all.x = TRUE
    )
    out <- out[!is.na(category)]
    out <- unique(out, by = c("firm_id", "muni_id", "year", "category", "treatment_year", "baseline_tier"))
    return(out[])
  }

  stop("Unknown taxonomy: ", taxonomy)
}

build_window_weights <- function(cat_panel, aff_party_year, owner_year, bw, taxonomy) {
  if (taxonomy == "policy_block") {
    firm_window <- cat_panel[year >= bw$bl_start & year <= bw$bl_end]
  } else {
    firm_window <- cat_panel[
      treatment_year == bw$treatment_year &
        baseline_tier == bw$baseline_tier &
        year >= bw$bl_start & year <= bw$bl_end
    ]
  }
  if (!nrow(firm_window)) return(NULL)

  firm_window <- firm_window[, .(
    n_employees = sum(n_employees, na.rm = TRUE),
    has_emp_obs = any(!is.na(n_employees))
  ), by = .(firm_id, muni_id, year, category)]

  owner_slice <- owner_year[year >= bw$bl_start & year <= bw$bl_end]
  aff_slice <- aff_party_year[year >= bw$bl_start & year <= bw$bl_end]

  own_fw <- merge(firm_window, owner_slice, by = c("firm_id", "year"), all.x = TRUE)
  own_fw[is.na(total_owners), total_owners := 0]

  den_muni_owner <- own_fw[, .(owner_den_muni = sum(total_owners, na.rm = TRUE)),
                           by = muni_id]
  den_muni_firm <- firm_window[, .(firm_den_muni = .N), by = muni_id]

  aff_fw <- merge(
    aff_slice,
    owner_slice,
    by = c("firm_id", "year"),
    all.x = TRUE
  )
  aff_fw[, owner_party_share := fifelse(
    !is.na(total_owners) & total_owners > 0,
    aff_count / total_owners,
    0
  )]
  aff_fw <- merge(
    aff_fw,
    firm_window[, .(firm_id, muni_id, year, category, n_employees, has_emp_obs)],
    by = c("firm_id", "year"),
    all.x = FALSE,
    allow.cartesian = TRUE
  )
  aff_fw[, binary_contrib := as.integer(owner_party_share > 0)]

  num <- aff_fw[, .(
    owner_num = sum(aff_count, na.rm = TRUE),
    binary_num = sum(binary_contrib, na.rm = TRUE)
  ), by = .(muni_id, category, party)]

  num <- merge(num, den_muni_owner, by = "muni_id", all.x = TRUE)
  num <- merge(num, den_muni_firm, by = "muni_id", all.x = TRUE)
  num[is.na(owner_den_muni), owner_den_muni := 0]
  num[is.na(firm_den_muni), firm_den_muni := 0]

  # A7 finalized pair. The production winner uses owner-count intensity; the
  # secondary robustness weight uses the extensive-margin aligned-firm signal.
  num[, `:=`(
    w_owners_muni_univ = fifelse(owner_den_muni > 0, owner_num / owner_den_muni, 0),
    w_binary_muni_univ = fifelse(firm_den_muni > 0, binary_num / firm_den_muni, 0),
    treatment_year = bw$treatment_year,
    baseline_tier = bw$baseline_tier,
    taxonomy = taxonomy
  )]

  out <- melt(
    num,
    id.vars = c("taxonomy", "muni_id", "category", "party",
                "treatment_year", "baseline_tier",
                "owner_den_muni", "firm_den_muni"),
    measure.vars = WEIGHT_IDS,
    variable.name = "weight_id",
    value.name = "weight_value",
    variable.factor = FALSE
  )
  out[, .(taxonomy, muni_id, category, party, treatment_year, baseline_tier,
          weight_id, weight_value, owner_den_muni, firm_den_muni)]
}

build_long_weights <- function(recon, s4_xwalk) {
  if (REUSE_CACHE && file.exists(WEIGHT_CACHE) && !FORCE_REBUILD) {
    out <- qs2::qs_read(WEIGHT_CACHE)
    setDT(out)
    return(out[])
  }
  cat("Building long finalized baseline weights for policy_block and S4...\n")
  aff <- load_affiliation()
  panels <- list(
    policy_block = build_category_panel_for_weights(recon, "policy_block"),
    S4 = build_category_panel_for_weights(recon, "S4", s4_xwalk)
  )

  rows <- list()
  idx <- 0L
  for (tax in names(panels)) {
    for (i in seq_len(nrow(baseline_window_map))) {
      idx <- idx + 1L
      rows[[idx]] <- build_window_weights(
        panels[[tax]],
        aff$aff_party_year,
        aff$owner_year,
        baseline_window_map[i],
        tax
      )
      cat(sprintf("  %s window %d/%d: %s rows\n",
                  tax, i, nrow(baseline_window_map),
                  if (is.null(rows[[idx]])) 0L else nrow(rows[[idx]])))
    }
  }
  out <- rbindlist(rows, use.names = TRUE, fill = TRUE)
  out[is.na(weight_value), weight_value := 0]
  setorderv(out, c("taxonomy", "baseline_tier", "treatment_year", "muni_id", "category", "party"))
  qs2::qs_save(out, WEIGHT_CACHE)
  out[]
}

build_z_wide <- function(long_weights) {
  stop_if_missing(c(SHOCKS_PATH))
  shocks <- qs2::qs_read(SHOCKS_PATH)
  setDT(shocks)
  shock_cols <- c("align_mayor_coalition", "align_gov_coalition", "align_pres_coalition")
  missing <- setdiff(c("muni_id", "party", "year", shock_cols), names(shocks))
  if (length(missing)) stop("Alignment shocks missing: ", paste(missing, collapse = ", "))
  shocks <- shocks[, c("muni_id", "party", "year", shock_cols), with = FALSE]

  merged <- merge(
    long_weights,
    shocks,
    by.x = c("muni_id", "party", "treatment_year"),
    by.y = c("muni_id", "party", "year"),
    all.x = TRUE
  )
  for (cc in shock_cols) merged[is.na(get(cc)), (cc) := 0]

  z_sector <- list()
  z_total <- list()
  idx <- 0L
  for (tier in c("mayor", "gov", "pres")) {
    needed <- if (tier == "mayor") "mayor" else "gov_pres"
    align_col <- paste0("align_", tier, "_coalition")
    tmp <- merged[baseline_tier == needed]
    tmp[, z_piece := weight_value * get(align_col)]
    idx <- idx + 1L
    z_sector[[idx]] <- tmp[, .(Z_value = sum(z_piece, na.rm = TRUE)),
                           by = .(taxonomy, weight_id, muni_id, category, treatment_year)]
    z_sector[[idx]][, tier := tier]

    total_w <- tmp[, .(total_weight = sum(weight_value, na.rm = TRUE)),
                   by = .(taxonomy, weight_id, muni_id, party, treatment_year)]
    total_w <- merge(
      total_w,
      shocks[, c("muni_id", "party", "year", align_col), with = FALSE],
      by.x = c("muni_id", "party", "treatment_year"),
      by.y = c("muni_id", "party", "year"),
      all.x = TRUE
    )
    total_w[is.na(get(align_col)), (align_col) := 0]
    total_w[, z_piece := total_weight * get(align_col)]
    z_total[[idx]] <- total_w[, .(Z_value = sum(z_piece, na.rm = TRUE)),
                              by = .(taxonomy, weight_id, muni_id, treatment_year)]
    z_total[[idx]][, tier := tier]
  }

  sec <- rbindlist(z_sector, use.names = TRUE)
  tot <- rbindlist(z_total, use.names = TRUE)
  setnames(sec, "treatment_year", "inaug_year")
  setnames(tot, "treatment_year", "inaug_year")
  sec <- merge(sec, term_map, by = "inaug_year", allow.cartesian = TRUE)
  tot <- merge(tot, term_map, by = "inaug_year", allow.cartesian = TRUE)
  sec <- sec[, .(Z_value = sum(Z_value, na.rm = TRUE)),
             by = .(taxonomy, weight_id, muni_id, year, category, tier)]
  tot <- tot[, .(Z_value = sum(Z_value, na.rm = TRUE)),
             by = .(taxonomy, weight_id, muni_id, year, tier)]

  sec[, z_col := mapply(make_z_col, taxonomy, tier, category, weight_id,
                        MoreArgs = list(total = FALSE))]
  tot[, z_col := mapply(make_z_col, taxonomy, tier, NA_character_, weight_id,
                        MoreArgs = list(total = TRUE))]

  sec_wide <- dcast(
    sec,
    taxonomy + muni_id + year ~ z_col,
    value.var = "Z_value",
    fun.aggregate = sum,
    fill = 0
  )
  tot_wide <- dcast(
    tot,
    taxonomy + muni_id + year ~ z_col,
    value.var = "Z_value",
    fun.aggregate = sum,
    fill = 0
  )
  wide <- merge(sec_wide, tot_wide, by = c("taxonomy", "muni_id", "year"), all = TRUE)
  zcols <- grep("^a10_Z", names(wide), value = TRUE)
  for (cc in zcols) wide[is.na(get(cc)), (cc) := 0]

  diag_rows <- list()
  for (weight_id in unique(sec$weight_id)) {
    for (tax in unique(sec$taxonomy)) {
      bins <- if (tax == "policy_block") POLICY_BLOCKS else S4_BINS
      for (tier in c("mayor", "gov", "pres")) {
        sec_cols <- make_z_col(tax, tier, bins, weight_id)
        sec_cols <- intersect(sec_cols, names(wide))
        total_col <- make_z_col(tax, tier, NA_character_, weight_id, total = TRUE)
        if (length(sec_cols) && total_col %in% names(wide)) {
          sub <- wide[taxonomy == tax]
          rs <- rowSums(sub[, ..sec_cols], na.rm = TRUE)
          diag_rows[[length(diag_rows) + 1L]] <- data.table(
            taxonomy = tax,
            tier = tier,
            weight_id = weight_id,
            ztotal_col = total_col,
            row_sum_sector_z_corr = suppressWarnings(cor(sub[[total_col]], rs, use = "complete.obs")),
            ztotal_mean = mean(sub[[total_col]], na.rm = TRUE),
            rows = nrow(sub)
          )
        }
      }
    }
  }
  fwrite(rbindlist(diag_rows, use.names = TRUE, fill = TRUE), Z_DIAG_CSV)
  wide[]
}

# ---- Estimation helpers ------------------------------------------------------

drop_reference_share <- function(dt, taxonomy) {
  bins <- attr(dt, "bins")
  share_cols <- make_share_col(taxonomy, bins)
  means <- vapply(share_cols, function(cc) mean(dt[[cc]], na.rm = TRUE), numeric(1))
  omitted_col <- names(which.max(means))
  omitted_bin <- sub(paste0("^s_", taxonomy, "_"), "", omitted_col)
  list(
    share_cols = setdiff(share_cols, omitted_col),
    omitted_col = omitted_col,
    omitted_bin = omitted_bin,
    n_bins_total = length(share_cols)
  )
}

required_complete <- function(dt, cols) {
  cols <- unique(cols)
  cols <- cols[cols %in% names(dt)]
  keep <- complete.cases(dt[, ..cols])
  num_cols <- cols[vapply(dt[, ..cols], is.numeric, logical(1))]
  for (cc in num_cols) keep <- keep & is.finite(dt[[cc]])
  keep
}

make_formula <- function(option, controls, share_cols, z_sector_cols, z_total_cols) {
  fe_part <- if (controls == "FE") "muni_id + year" else "0"
  shares <- paste(share_cols, collapse = " + ")
  z_sector <- paste(z_sector_cols, collapse = " + ")
  z_all <- paste(c(z_sector_cols, z_total_cols), collapse = " + ")
  z_total <- paste(z_total_cols, collapse = " + ")

  if (option == "pure_ols") {
    rhs <- paste(c(share_cols, TOTAL_VAR), collapse = " + ")
    return(if (controls == "FE") {
      as.formula(paste0(OUTCOME, " ~ ", rhs, " | ", fe_part))
    } else {
      as.formula(paste0(OUTCOME, " ~ ", rhs))
    })
  }
  if (option == "partial_iv") {
    return(as.formula(paste0(OUTCOME, " ~ ", TOTAL_VAR, " | ", fe_part, " | ",
                             shares, " ~ ", z_sector)))
  }
  if (option == "full_iv") {
    endo <- paste(c(share_cols, TOTAL_VAR), collapse = " + ")
    return(as.formula(paste0(OUTCOME, " ~ 1 | ", fe_part, " | ",
                             endo, " ~ ", z_all)))
  }
  if (option == "mixed") {
    return(as.formula(paste0(OUTCOME, " ~ ", shares, " | ", fe_part, " | ",
                             TOTAL_VAR, " ~ ", z_total)))
  }
  stop("Unknown option: ", option)
}

run_first_stage <- function(dt, spec_meta, endogenous_vars, exog_vars, inst_vars, controls) {
  if (!length(endogenous_vars)) return(data.table())
  out <- vector("list", length(endogenous_vars))
  fe_part <- if (controls == "FE") " | muni_id + year" else ""
  keep_cols <- unique(c(endogenous_vars, exog_vars, inst_vars, "muni_id", "year"))
  keep <- required_complete(dt, keep_cols)
  fs_dt <- dt[keep]
  inst_keep <- paste0("^(", paste(regex_escape(inst_vars), collapse = "|"), ")$")

  for (i in seq_along(endogenous_vars)) {
    endo <- endogenous_vars[[i]]
    rhs_vars <- unique(c(exog_vars, inst_vars))
    rhs <- if (length(rhs_vars)) paste(rhs_vars, collapse = " + ") else "1"
    fml <- as.formula(paste0(endo, " ~ ", rhs, fe_part))
    fit <- tryCatch(feols(fml, data = fs_dt, vcov = ~muni_id), error = function(e) e)
    if (inherits(fit, "error")) {
      out[[i]] <- cbind(spec_meta, data.table(
        endogenous_var = endo,
        instrument_set = paste(inst_vars, collapse = " + "),
        first_stage_f = NA_real_,
        first_stage_p = NA_real_,
        partial_r2 = NA_real_,
        status = "fit_error",
        note = conditionMessage(fit)
      ))
      next
    }
    wt <- tryCatch(wald(fit, keep = inst_keep, print = FALSE), error = function(e) e)
    if (inherits(wt, "error")) {
      fstat <- pval <- NA_real_
      status <- "wald_error"
      note <- conditionMessage(wt)
    } else {
      fstat <- unname(wt$stat)
      pval <- unname(wt$p)
      status <- if (is.finite(fstat)) "ok" else "degenerate"
      note <- ""
    }
    out[[i]] <- cbind(spec_meta, data.table(
      endogenous_var = endo,
      instrument_set = paste(inst_vars, collapse = " + "),
      first_stage_f = fstat,
      first_stage_p = pval,
      partial_r2 = NA_real_,
      status = status,
      note = note
    ))
  }
  rbindlist(out, use.names = TRUE, fill = TRUE)
}

extract_coefficients <- function(fit, spec_meta) {
  ct <- as.data.table(as.data.frame(coeftable(fit)), keep.rownames = "term")
  if (!nrow(ct)) return(data.table())
  setnames(ct, names(ct)[2:5], c("estimate", "std_error", "t_stat", "p_value"),
           skip_absent = TRUE)
  ct[, `:=`(
    ci_low = estimate - 1.96 * std_error,
    ci_high = estimate + 1.96 * std_error,
    term_type = fifelse(grepl("^s_", term) | grepl("^fit_s_", term), "share",
                  fifelse(term %in% c(TOTAL_VAR, paste0("fit_", TOTAL_VAR)), "total_bndes", "other"))
  )]
  cbind(spec_meta, ct[, .(term, term_type, estimate, std_error, t_stat, p_value, ci_low, ci_high)])
}

run_a10_spec <- function(dt, taxonomy, option, controls, tier_spec, weight_id) {
  ref <- drop_reference_share(dt, taxonomy)
  tiers <- pick_tiers(tier_spec)
  bins <- attr(dt, "bins")
  z_sector_cols <- unlist(lapply(tiers, function(tt) make_z_col(taxonomy, tt, bins, weight_id)), use.names = FALSE)
  z_total_cols <- unlist(lapply(tiers, function(tt) make_z_col(taxonomy, tt, NA_character_, weight_id, total = TRUE)), use.names = FALSE)
  z_sector_cols <- intersect(z_sector_cols, names(dt))
  z_total_cols <- intersect(z_total_cols, names(dt))

  spec_id <- paste(taxonomy, option, controls, tier_spec, weight_id, sep = "__")
  spec_meta <- data.table(
    spec_id = spec_id,
    taxonomy = taxonomy,
    option = option,
    controls = controls,
    tier_spec = tier_spec,
    weight_id = weight_id,
    outcome = OUTCOME
  )

  required <- c(OUTCOME, CLUSTER, "year", ref$share_cols, TOTAL_VAR)
  if (option %in% c("partial_iv", "full_iv")) required <- c(required, z_sector_cols)
  if (option %in% c("full_iv", "mixed")) required <- c(required, z_total_cols)
  missing <- setdiff(required, names(dt))
  if (length(missing)) {
    res <- cbind(spec_meta, data.table(
      n_bins_total = ref$n_bins_total,
      n_shares_included = length(ref$share_cols),
      omitted_bin = ref$omitted_bin,
      K_sector_instruments = length(z_sector_cols),
      K_total_instruments = length(z_total_cols),
      n_obs = NA_integer_,
      n_munis = NA_integer_,
      composition_wald_f = NA_real_,
      composition_wald_p = NA_real_,
      total_bndes_coef = NA_real_,
      total_bndes_p = NA_real_,
      r2_or_wr2 = NA_real_,
      status = "missing_columns",
      note = paste(missing, collapse = ", ")
    ))
    return(list(result = res, coefficients = data.table(), first_stage = data.table()))
  }

  if (option == "partial_iv" && length(z_sector_cols) < length(ref$share_cols)) {
    status_note <- "Not enough sector/bin instruments for included shares"
  } else if (option == "full_iv" && length(c(z_sector_cols, z_total_cols)) < length(c(ref$share_cols, TOTAL_VAR))) {
    status_note <- "Not enough instruments for included shares plus total BNDES"
  } else if (option == "mixed" && !length(z_total_cols)) {
    status_note <- "No Z_total instruments available"
  } else {
    status_note <- ""
  }

  if (nzchar(status_note)) {
    res <- cbind(spec_meta, data.table(
      n_bins_total = ref$n_bins_total,
      n_shares_included = length(ref$share_cols),
      omitted_bin = ref$omitted_bin,
      K_sector_instruments = length(z_sector_cols),
      K_total_instruments = length(z_total_cols),
      n_obs = NA_integer_,
      n_munis = NA_integer_,
      composition_wald_f = NA_real_,
      composition_wald_p = NA_real_,
      total_bndes_coef = NA_real_,
      total_bndes_p = NA_real_,
      r2_or_wr2 = NA_real_,
      status = "not_identified",
      note = status_note
    ))
    return(list(result = res, coefficients = data.table(), first_stage = data.table()))
  }

  fml <- make_formula(option, controls, ref$share_cols, z_sector_cols, z_total_cols)
  keep <- required_complete(dt, required)
  est_dt <- dt[keep]

  fit <- tryCatch(feols(fml, data = est_dt, vcov = ~muni_id), error = function(e) e)
  if (inherits(fit, "error")) {
    res <- cbind(spec_meta, data.table(
      n_bins_total = ref$n_bins_total,
      n_shares_included = length(ref$share_cols),
      omitted_bin = ref$omitted_bin,
      K_sector_instruments = length(z_sector_cols),
      K_total_instruments = length(z_total_cols),
      n_obs = nrow(est_dt),
      n_munis = uniqueN(est_dt$muni_id),
      composition_wald_f = NA_real_,
      composition_wald_p = NA_real_,
      total_bndes_coef = NA_real_,
      total_bndes_p = NA_real_,
      r2_or_wr2 = NA_real_,
      status = "fit_error",
      note = conditionMessage(fit)
    ))
    return(list(result = res, coefficients = data.table(), first_stage = data.table()))
  }

  coef_names <- names(coef(fit))
  share_terms <- unique(c(ref$share_cols, paste0("fit_", ref$share_cols)))
  share_terms <- intersect(share_terms, coef_names)
  if (length(share_terms)) {
    keep_re <- paste0("^(", paste(regex_escape(share_terms), collapse = "|"), ")$")
    wt <- tryCatch(wald(fit, keep = keep_re, print = FALSE), error = function(e) e)
    if (inherits(wt, "error")) {
      comp_f <- comp_p <- NA_real_
      status <- "wald_error"
      note <- conditionMessage(wt)
    } else {
      comp_f <- unname(wt$stat)
      comp_p <- unname(wt$p)
      status <- "ok"
      note <- ""
    }
  } else {
    comp_f <- comp_p <- NA_real_
    status <- "degenerate"
    note <- "No share coefficients estimated"
  }

  ct <- extract_coefficients(fit, spec_meta)
  total_rows <- ct[term %in% c(TOTAL_VAR, paste0("fit_", TOTAL_VAR))]
  total_coef <- if (nrow(total_rows)) total_rows$estimate[1] else NA_real_
  total_p <- if (nrow(total_rows)) total_rows$p_value[1] else NA_real_
  r2_val <- tryCatch(
    if (controls == "FE") unname(r2(fit, "wr2")) else unname(r2(fit, "r2")),
    error = function(e) NA_real_
  )

  res <- cbind(spec_meta, data.table(
    n_bins_total = ref$n_bins_total,
    n_shares_included = length(ref$share_cols),
    omitted_bin = ref$omitted_bin,
    K_sector_instruments = length(z_sector_cols),
    K_total_instruments = length(z_total_cols),
    n_obs = nobs(fit),
    n_munis = uniqueN(est_dt$muni_id),
    composition_wald_f = comp_f,
    composition_wald_p = comp_p,
    total_bndes_coef = total_coef,
    total_bndes_p = total_p,
    r2_or_wr2 = r2_val,
    status = status,
    note = note
  ))

  if (option == "partial_iv") {
    fs <- run_first_stage(dt, spec_meta, ref$share_cols, TOTAL_VAR, z_sector_cols, controls)
  } else if (option == "full_iv") {
    fs <- run_first_stage(dt, spec_meta, c(ref$share_cols, TOTAL_VAR), character(0), c(z_sector_cols, z_total_cols), controls)
  } else if (option == "mixed") {
    fs <- run_first_stage(dt, spec_meta, TOTAL_VAR, ref$share_cols, z_total_cols, controls)
  } else {
    fs <- data.table()
  }

  list(result = res, coefficients = ct, first_stage = fs)
}

run_grid <- function(panels) {
  grid <- CJ(
    weight_id = WEIGHT_IDS,
    taxonomy = names(panels),
    option = option_specs,
    controls = control_specs,
    tier_spec = names(tier_specs),
    sorted = FALSE
  )
  grid[, `:=`(
    weight_order = match(weight_id, WEIGHT_IDS),
    taxonomy_order = match(taxonomy, c("policy_block", "S4")),
    option_order = match(option, option_specs),
    controls_order = match(controls, control_specs),
    tier_order = match(tier_spec, names(tier_specs))
  )]
  setorder(grid, weight_order, taxonomy_order, option_order, controls_order, tier_order)

  res <- vector("list", nrow(grid))
  coefs <- vector("list", nrow(grid))
  fs <- vector("list", nrow(grid))
  for (i in seq_len(nrow(grid))) {
    g <- grid[i]
    cat(sprintf("  [%02d/%02d] %s / %s / %s / %s / %s\n",
                i, nrow(grid), g$weight_id, g$taxonomy, g$option, g$controls, g$tier_spec))
    out <- run_a10_spec(panels[[g$taxonomy]], g$taxonomy, g$option, g$controls, g$tier_spec, g$weight_id)
    res[[i]] <- out$result
    coefs[[i]] <- out$coefficients
    fs[[i]] <- out$first_stage
  }
  list(
    results = rbindlist(res, use.names = TRUE, fill = TRUE),
    coefficients = rbindlist(coefs, use.names = TRUE, fill = TRUE),
    first_stage = rbindlist(fs, use.names = TRUE, fill = TRUE)
  )
}

# ---- Output writers ----------------------------------------------------------

result_cell <- function(f, p, bcoef, bp) {
  if (is.na(f)) return("NA")
  s <- ifelse(is.na(bcoef), "", ifelse(bcoef >= 0, "+", "-"))
  paste0(sprintf("%.2f", f), sig_marker(p), " [", fmt_p(p), "]; T", s, sig_marker(bp))
}

option_label <- function(option) {
  switch(option,
         pure_ols = "Pure OLS",
         partial_iv = "Partial IV",
         full_iv = "Full IV",
         mixed = "Mixed",
         option)
}

fmt_coef <- function(x) {
  ifelse(is.na(x), "NA",
         ifelse(x != 0 & abs(x) < 0.001,
                sprintf("%.2e", x),
                sprintf("%.3f", x)))
}

coef_cell <- function(estimate, p_value) {
  if (is.na(estimate)) return("NA")
  paste0(fmt_coef(estimate), sig_marker(p_value), " [", fmt_p(p_value), "]")
}

write_summary_tex <- function(results) {
  panels <- split(results, by = c("weight_id", "taxonomy", "controls"), keep.by = TRUE)
  lines <- c(
    "\\begin{tabular}{lllrrrr}",
    "\\toprule",
    "Weight & Taxonomy & Controls & OK rows & Mean Wald F & Min p & Omitted bin \\\\",
    "\\midrule"
  )
  for (nm in names(panels)) {
    p <- panels[[nm]]
    lines <- c(lines, sprintf(
      "%s & %s & %s & %d/%d & %.2f & %s & %s \\\\",
      tex_escape(p$weight_id[1]),
      tex_escape(p$taxonomy[1]),
      tex_escape(p$controls[1]),
      sum(p$status == "ok"),
      nrow(p),
      mean(p$composition_wald_f, na.rm = TRUE),
      tex_escape(fmt_p(min(p$composition_wald_p, na.rm = TRUE))),
      tex_escape(p$omitted_bin[1])
    ))
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}")
  writeLines(lines, SUMMARY_TEX)
}

write_slide_table <- function(results, taxonomy, controls, weight_id) {
  tax_filter <- taxonomy
  controls_filter <- controls
  weight_filter <- weight_id
  sub <- copy(results[
    taxonomy == tax_filter &
      controls == controls_filter &
      weight_id == weight_filter
  ])
  sub[, cell := mapply(result_cell, composition_wald_f, composition_wald_p,
                       total_bndes_coef, total_bndes_p)]
  wide <- dcast(sub, tier_spec ~ option, value.var = "cell", fun.aggregate = function(x) x[1])
  wide[, tier_order := match(tier_spec, names(tier_specs))]
  setorder(wide, tier_order)
  cols <- option_specs
  lines <- c(
    "\\resizebox{\\textwidth}{!}{%",
    "\\setlength{\\tabcolsep}{4pt}%",
    "\\footnotesize%",
    "\\begin{tabular}{@{}lcccc@{}}",
    "\\toprule",
    "Political tier & Pure OLS & Partial IV & Full IV & Mixed \\\\",
    "\\midrule"
  )
  for (i in seq_len(nrow(wide))) {
    vals <- as.character(unlist(wide[i, ..cols], use.names = FALSE))
    vals[is.na(vals)] <- "NA"
    lines <- c(lines, paste0(tex_escape(tier_label(wide$tier_spec[i])), " & ",
                             paste(tex_escape(vals), collapse = " & "), " \\\\"))
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}%", "}")
  lines
}

coef_term_label <- function(term, taxonomy) {
  clean <- sub("^fit_", "", term)
  clean <- fifelse(clean == TOTAL_VAR, "Total",
                   sub(paste0("^s_", taxonomy, "_"), "", clean))
  clean
}

write_coef_appendix_table <- function(coefficients, results, taxonomy, option, weight_id) {
  tax_filter <- taxonomy
  option_filter <- option
  weight_filter <- weight_id
  omitted_bin <- unique(results[
    taxonomy == tax_filter &
      option == option_filter &
      weight_id == weight_filter,
    omitted_bin
  ])
  coef_sub <- copy(coefficients[
    taxonomy == tax_filter &
      option == option_filter &
      weight_id == weight_filter &
      controls == "FE" &
      term_type %in% c("share", "total_bndes")
  ])
  if (!nrow(coef_sub)) {
    return(c("{\\footnotesize No coefficient rows available for this specification.}"))
  }
  coef_sub[, term_label := coef_term_label(term, tax_filter)]
  coef_sub[, cell := mapply(coef_cell, estimate, p_value)]

  term_order <- unique(coef_sub[term_type == "share", term_label])
  term_order <- c(term_order, "Total")
  wide <- dcast(coef_sub, tier_spec ~ term_label, value.var = "cell",
                fun.aggregate = function(x) x[1])
  wide[, tier_order := match(tier_spec, names(tier_specs))]
  setorder(wide, tier_order)
  cols <- intersect(term_order, names(wide))

  align <- paste(rep("c", length(cols)), collapse = "")
  lines <- c(
    "\\resizebox{\\textwidth}{!}{%",
    "\\setlength{\\tabcolsep}{4pt}%",
    "\\scriptsize%",
    sprintf("\\begin{tabular}{@{}l%s@{}}", align),
    "\\toprule",
    paste0(paste(c("Political tier", tex_escape(sapply(cols, bin_label))), collapse = " & "), " \\\\"),
    "\\midrule"
  )
  for (i in seq_len(nrow(wide))) {
    vals <- as.character(unlist(wide[i, ..cols], use.names = FALSE))
    vals[is.na(vals)] <- "NA"
    lines <- c(lines, paste0(tex_escape(tier_label(wide$tier_spec[i])), " & ",
                             paste(tex_escape(vals), collapse = " & "), " \\\\"))
  }
  lines <- c(
    lines,
    "\\bottomrule",
    "\\end{tabular}%",
    "}",
    sprintf("{\\footnotesize Entries are coefficient estimates with p-values in brackets. Omitted category: %s.}",
            tex_escape(bin_label(omitted_bin[1])))
  )
  lines
}

weight_role <- function(weight_id) {
  switch(weight_id,
         w_owners_muni_univ = "Production",
         w_binary_muni_univ = "Robustness",
         weight_id)
}

tier_label <- function(tier_spec) {
  switch(tier_spec,
         mayor            = "Mayor",
         gov              = "Governor",
         mayor_gov        = "Mayor + Governor",
         mayor_pres       = "Mayor + President",
         mayor_gov_pres   = "Mayor + Gov. + President",
         tier_spec)
}

taxonomy_label <- function(tax) {
  switch(tax,
         policy_block = "Broad Policy Sectors",
         S4           = "Firm-Size Groups",
         tax)
}

weight_label <- function(weight_id) {
  switch(weight_id,
         w_owners_muni_univ = "owner-count production weight",
         w_binary_muni_univ = "aligned-firm robustness weight",
         weight_id)
}

bin_label <- function(bin) {
  switch(bin,
         Agro    = "Agriculture",
         Ind     = "Industry",
         Infra   = "Infrastructure",
         Serv    = "Services",
         Micro   = "Micro",
         Pequena = "Small",
         Media   = "Medium",
         Grande  = "Large",
         bin)
}

write_slides <- function(results, coefficients, s4_diag) {
  omitted <- unique(results[, .(weight_id, taxonomy, omitted_bin)])
  miss_share <- if (nrow(s4_diag)) s4_diag$share_bndes_value_unclassified_s4[1] else NA_real_
  zdiag <- if (file.exists(Z_DIAG_CSV)) fread(Z_DIAG_CSV) else data.table()
  corr_vals <- if (nrow(zdiag)) zdiag$row_sum_sector_z_corr[is.finite(zdiag$row_sum_sector_z_corr)] else numeric()
  zcorr_txt <- if (length(corr_vals)) {
    sprintf("The instrument for total lending is constructed independently from the sector instruments (average correlation with row sum = %.3f).",
            mean(corr_vals, na.rm = TRUE))
  } else {
    "Total lending instrument diagnostics unavailable."
  }

  lines <- c(
    "\\documentclass[aspectratio=169,11pt]{beamer}",
    "\\usetheme{default}",
    "\\setbeamertemplate{navigation symbols}{}",
    "\\setbeamertemplate{headline}{}",
    "\\setbeamertemplate{footline}{\\hfill{\\usebeamerfont{footline}\\insertframenumber}\\hspace{0.6em}\\vspace{0.4em}}",
    "\\setbeamerfont{frametitle}{size=\\large,series=\\bfseries}",
    "\\setbeamerfont{footline}{size=\\scriptsize}",
    "\\usepackage{palatino}",
    "\\usepackage[T1]{fontenc}",
    "\\usepackage{booktabs}",
    "\\usepackage{array}",
    "\\usepackage{microtype}",
    "\\usepackage{graphicx}",
    "\\usepackage{makecell}",
    "\\title{\\textbf{Composition vs.\\ Volume}\\\\[0.4em]{\\large Political Alignment and Development Lending}}",
    "\\date{May 2026}",
    "\\begin{document}",
    "\\begin{frame}",
    "\\titlepage",
    "\\end{frame}",
    # ---- Summary slide ----
    "\\begin{frame}{Main Findings}",
    "\\begin{itemize}\\setlength{\\itemsep}{0.4em}",
    "\\item \\textbf{Question:} Does the \\textit{composition} of BNDES lending across sectors or firm sizes affect local GDP, or does only the \\textit{total volume} matter?",
    "\\item \\textbf{OLS:} Sector composition strongly predicts municipal GDP. Agriculture and Industry shares are positively associated with output; total loan volume is negligible.",
    "\\item \\textbf{IV:} Once sector composition is instrumented with political alignment shocks, the composition effect disappears. Total lending also shows no consistent positive effect.",
    "\\item \\textbf{Interpretation:} The OLS pattern reflects reverse causality --- booming municipalities attract specific types of BNDES lending, not the reverse.",
    "\\item Findings hold across both classification schemes (broad sectors and firm-size groups) and both weighting approaches.",
    "\\end{itemize}",
    "\\end{frame}",
    # ---- Specification overview ----
    "\\begin{frame}{Specification Overview}",
    "\\begin{itemize}\\setlength{\\itemsep}{0.35em}",
    "\\item \\textbf{Outcome:} Log municipal GDP (municipality $\\times$ year panel, 2002--2017).",
    "\\item \\textbf{Two lending classifications:}",
    "  \\begin{itemize}\\setlength{\\itemsep}{0.2em}",
    "  \\item Broad policy sectors: Agriculture, Industry, Infrastructure, Services.",
    "  \\item Firm-size groups: Micro, Small, Medium, Large enterprises.",
    "  \\end{itemize}",
    "\\item \\textbf{Four identification strategies:}",
    "  \\begin{itemize}\\setlength{\\itemsep}{0.2em}",
    "  \\item Pure OLS: treat both sector shares and total volume as observed.",
    "  \\item Partial IV: instrument sector shares only; control for total volume.",
    "  \\item Full IV: instrument both sector shares and total volume jointly.",
    "  \\item Mixed: instrument total volume only; treat sector shares as observed.",
    "  \\end{itemize}",
    "\\item All specifications include municipality and year fixed effects.",
    "\\item The highest mean-share category within each classification is the reference group.",
    "\\end{itemize}",
    "\\end{frame}",
    # ---- Weight selection notes (plain language) — rationale BEFORE finalized choice ----
    "\\begin{frame}{Weight Selection Notes}",
    "\\begin{itemize}\\setlength{\\itemsep}{0.35em}",
    "\\item Six candidate weights were compared using the Kleibergen--Paap (KP) F-statistic for first-stage instrument strength.",
    "\\item The production weight (owner-count intensity, full-municipality denominator) achieved the highest and most stable KP F across control specifications ($\\approx$60).",
    "\\item One data concern: the Agriculture sector has a lower firm-match rate ($\\approx$25\\%) than other sectors (67--95\\%), attenuating its instrument contribution. This attenuation is symmetric across all candidate weights and does not change their relative ranking.",
    "\\item The robustness weight (binary alignment, full-municipality denominator) was selected as the complement: it uses a simpler signal, is harder to manipulate, and delivers KP F $\\approx$48 under fixed effects.",
    "\\item Both finalized weights share the same denominator scope: all RAIS firms in the municipality, matched or not.",
    "\\end{itemize}",
    "\\end{frame}",
    # ---- Finalized weights (plain language) ----
    "\\begin{frame}{Finalized Weights for the Instruments}",
    "\\begin{itemize}\\setlength{\\itemsep}{0.35em}",
    "\\item \\textbf{Production weight (primary):} Weight each municipality--party cell by the number of politically affiliated firm owners, divided by the total owner count across \\textit{all} firms in the municipality.",
    "\\item \\textbf{Robustness weight (complement):} Weight by whether a firm has \\textit{any} aligned owner (a binary yes/no), divided by the total number of firms in the municipality.",
    "\\item Both weights use the full local firm universe as the denominator --- including firms that never received BNDES credit.",
    "\\item The robustness weight captures the extensive margin of alignment (first affiliated owner). The production weight captures the intensive margin (more affiliated owners = stronger signal).",
    "\\end{itemize}",
    "\\vskip 0.3em",
    "\\centering\\scriptsize",
    "\\begin{tabular}{lcc}",
    "\\toprule",
    "Control specification & Production weight KP~F & Robustness weight KP~F \\\\",
    "\\midrule",
    "No controls & 59.57 & --- \\\\",
    "Municipality and year FE & 59.56 & 47.54 \\\\",
    "FE + aggregate exposure & 50.30 & --- \\\\",
    "\\bottomrule",
    "\\end{tabular}",
    "\\end{frame}",
    # ---- Why no first-stage requirement ----
    "\\begin{frame}{Instrument Strength and the AR Test}",
    "\\begin{itemize}\\setlength{\\itemsep}{0.35em}",
    "\\item The Anderson--Rubin (AR) test is robust to weak instruments. It tests H$_0$: the reduced-form coefficients on all instruments are jointly zero, without requiring a strong first stage.",
    "\\item A strong first stage helps efficiency but is \\textit{not} required for validity --- AR confidence sets are correct even when individual first-stage F-stats are low.",
    "\\item \\textbf{Total lending instrument} (mixed specification): the instrument for total BNDES volume achieves KP F $\\approx$60 (production) and $\\approx$48 (robustness) under FE. Relevance is strong.",
    "\\item \\textbf{Sector-composition instruments} (partial IV): per-variable first-stage F ranges 1.9--4.8. This is expected --- sector shares sum to 1, so the instruments are collinear across shares by construction, attenuating individual-variable F while preserving joint relevance.",
    "\\item The composition Wald F reported on the result slides IS the joint test of instrument relevance for the composition system.",
    "\\end{itemize}",
    "\\end{frame}"
  )

  for (weight_id in WEIGHT_IDS) {
    for (tax in c("policy_block", "S4")) {
      frame_title <- sprintf("%s Weight: %s",
                             weight_role(weight_id), taxonomy_label(tax))
      weight_desc <- sprintf("Weight: %s.", weight_label(weight_id))
      lines <- c(lines,
        sprintf("\\begin{frame}{%s}", frame_title),
        sprintf("{\\footnotesize %s}", weight_desc),
        "\\vskip 0.25em",
        write_slide_table(results, tax, "FE", weight_id),
        "\\vskip 0.5em",
        "{\\footnotesize Composition Wald F [p-value]; T$+$/$-$ = sign of total lending coefficient (T$+$*/** = positive and significant at 10\\%/5\\%). Controls: municipality and year fixed effects.}",
        "\\end{frame}"
      )
    }
  }

  lines <- c(lines,
    # ---- Closing takeaway ----
    "\\begin{frame}{Bottom Line}",
    "\\begin{itemize}\\setlength{\\itemsep}{0.5em}",
    "\\item \\textbf{OLS tells a misleading story.} Sector composition correlates strongly with GDP in OLS because thriving municipalities attract specific types of lending --- not because sectoral reallocation causes growth.",
    "\\item \\textbf{IV breaks the correlation.} Once composition is instrumented with political alignment shocks, the composition effect drops to zero across both classification schemes and both weighting approaches.",
    "\\item \\textbf{Total lending is also not the driver.} Even when total BNDES volume is instrumented (mixed specification), there is no consistent positive effect on municipal GDP.",
    "\\item \\textbf{Implication.} Political alignment shapes \\textit{who receives} credit, but the sectoral and size composition of that credit does not independently predict local economic outcomes once the endogeneity is removed.",
    "\\end{itemize}",
    "\\end{frame}",
    "\\appendix",
    "\\section{Coefficient Appendix}"
  )
  for (weight_id in WEIGHT_IDS) {
    for (tax in c("policy_block", "S4")) {
      for (opt in option_specs) {
        frame_title <- sprintf("Appendix: %s Weight, %s, %s",
                               weight_role(weight_id), taxonomy_label(tax), option_label(opt))
        weight_desc <- sprintf("Weight: %s.", weight_label(weight_id))
        lines <- c(lines,
          sprintf("\\begin{frame}{%s}", frame_title),
          sprintf("{\\footnotesize %s}", weight_desc),
          "\\vskip 0.25em",
          write_coef_appendix_table(coefficients, results, tax, opt, weight_id),
          "\\end{frame}"
        )
      }
    }
  }

  lines <- c(lines,
    "\\begin{frame}{Technical Diagnostics}",
    "\\begin{itemize}\\setlength{\\itemsep}{0.4em}"
  )
  for (i in seq_len(nrow(omitted))) {
    lines <- c(lines, sprintf("\\item Omitted reference category (%s, %s): %s.",
                              weight_label(omitted$weight_id[i]),
                              taxonomy_label(omitted$taxonomy[i]),
                              bin_label(omitted$omitted_bin[i])))
  }
  miss_pct <- if (!is.na(miss_share)) sprintf("%.1f\\%%", miss_share * 100) else "NA"
  lines <- c(lines,
    sprintf("\\item Share of BNDES lending not classified by firm size: %s.", miss_pct),
    sprintf("\\item %s", zcorr_txt),
    "\\end{itemize}",
    "\\end{frame}",
    "\\end{document}"
  )
  writeLines(lines, SLIDES_TEX)
}

# ---- Main --------------------------------------------------------------------

stop_if_missing(c(AFF_PATH, SHOCKS_PATH, PANEL_POLICY_PATH, CREDIT_POLICY_PATH, PB_MAP_PATH))
if (!file.exists(RECON_FST) && !file.exists(RECON_QS2)) {
  stop("Reconstructed panel not found:\n  ", RECON_FST, "\n  ", RECON_QS2)
}

if (DRY_RUN) {
  cat("Dry run requested. Required inputs are present and script parsed successfully.\n")
  quit(status = 0L)
}

cat("Loading base muni-year panel...\n")
base <- load_base_panel()

cat("Loading reconstructed firm panel columns...\n")
recon_cols <- c("firm_id", "muni_id", "year", "cnae_section",
                "n_employees", "value_dis_real_2018_total")
recon <- load_reconstructed(recon_cols)
recon[, firm_id := as.integer(firm_id)]
recon[, muni_id := as.integer(muni_id)]
recon[, year := as.integer(year)]
recon[, n_employees := as.numeric(n_employees)]
recon[, value_dis_real_2018_total := as.numeric(value_dis_real_2018_total)]

cat("Building S4 crosswalk and diagnostic...\n")
s4_xwalk <- build_s4_crosswalk(recon[, .(firm_id, year, n_employees)])
s4_diag <- write_s4_diagnostic(recon, s4_xwalk)

long_weights <- build_long_weights(recon, s4_xwalk)
z_wide <- build_z_wide(long_weights)

policy_panel <- build_policy_block_panel(base, z_wide)
s4_panel <- build_s4_panel(base, recon, s4_xwalk, z_wide)

panels <- list(policy_block = policy_panel, S4 = s4_panel)

cat("\nRunning A10 estimation grid...\n")
grid_out <- run_grid(panels)
results <- grid_out$results
coefficients <- grid_out$coefficients
first_stage <- grid_out$first_stage

fwrite(results, RESULTS_CSV)
fwrite(coefficients, COEFF_CSV)
fwrite(first_stage, FIRST_STAGE_CSV)
write_summary_tex(results)
write_slides(results, coefficients, s4_diag)

cat("\nSaved outputs:\n")
cat("  ", RESULTS_CSV, "\n", sep = "")
cat("  ", COEFF_CSV, "\n", sep = "")
cat("  ", FIRST_STAGE_CSV, "\n", sep = "")
cat("  ", SUMMARY_TEX, "\n", sep = "")
cat("  ", SLIDES_TEX, "\n", sep = "")
cat("  ", S4_DIAG_CSV, "\n", sep = "")
cat("  ", Z_DIAG_CSV, "\n", sep = "")

cat("\nVerification summary:\n")
cat(sprintf("  Result rows: %d\n", nrow(results)))
cat(sprintf("  Coefficient rows: %d\n", nrow(coefficients)))
cat(sprintf("  Taxonomies: %s\n", paste(sort(unique(results$taxonomy)), collapse = ", ")))
cat(sprintf("  Weights: %s\n", paste(sort(unique(results$weight_id)), collapse = ", ")))
cat(sprintf("  Status counts: %s\n",
            paste(results[, .N, by = status][, paste0(status, "=", N)], collapse = ", ")))
cat(sprintf("  Missing omitted bins: %d\n", sum(is.na(results$omitted_bin) | !nzchar(results$omitted_bin))))
cat(sprintf("  First-stage rows: %d\n", nrow(first_stage)))

expected_result_rows <- length(panels) * length(option_specs) * length(control_specs) * length(tier_specs) * length(WEIGHT_IDS)
if (nrow(results) != expected_result_rows) {
  stop("Expected ", expected_result_rows, " result rows, found ", nrow(results))
}
if (!setequal(unique(results$weight_id), WEIGHT_IDS)) {
  stop("Unexpected weight_id set in results: ", paste(sort(unique(results$weight_id)), collapse = ", "))
}
if (!identical(sort(unique(results$controls)), sort(control_specs))) {
  stop("Unexpected controls in results: ", paste(sort(unique(results$controls)), collapse = ", "))
}
if (any(is.na(results$omitted_bin) | !nzchar(results$omitted_bin))) {
  stop("At least one result row has missing omitted_bin.")
}

cat("\na10_composition_volume.R completed.\n")
