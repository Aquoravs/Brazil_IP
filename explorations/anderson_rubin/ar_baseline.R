# ==============================================================================
# ar_baseline.R
# Pooled Anderson-Rubin test — PRIMARY SPEC + CONTROLS LADDER (Unit 4)
# H0: BNDES sectoral allocation has no first-order effect on municipal GDP
#
# Paper: Testing Industrial Policy: Evidence from Brazil's BNDES
# Plan:  logs/plans/2026-04-29_ar-baseline-implementation.md
#
# PRIMARY SPEC (USER-MANDATED 2026-04-29):
#   Outcome:     log_gdp
#   Instruments: ar_Z_mayor_coalition_cycle_specific_{Agro,Ind,Infra,Serv}
#   FE:          none
#   Covariates:  none
#   Cluster:     muni_id (vcov = ~muni_id)
#   Estimator:   fixest::feols
#   AR stat:     fixest::wald(m, keep = "^ar_Z_")
#   K:           4  (4 sectors x 1 tier)
#
# CONTROLS LADDER (Unit 4 addition — K=4 mayor primary path only):
#   C1 (spec_id="C1_FE",      controls="FE"):      + muni_id + year FE
#   C2 (spec_id="C2_FE_R0a",  controls="FE_R0a"):  FE + ec_total_mayor_cycle_specific
#   C3 (spec_id="C3_FE_R0b",  controls="FE_R0b"):  FE + ar_exposure_control_mayor_cycle_specific_{Agro,Ind,Infra,Serv}
#   C4 (spec_id="C4_FE_emp",  controls="FE_emp"):  FE + log_total_employment
#                                                   [C4 NOTE: bad-control risk — see strategy memo §6/§10;
#                                                    employment is a downstream outcome of BNDES credit]
#
# SCOPE: This unit runs the primary spec + controls ladder only.
#   Tier ascent K=8/12              -> Unit 5
#   Weight battery / R1/R2/R4       -> Unit 5
#   Grouped AR by state/quartile    -> Unit 6
#   Falsification F1/F2/F7          -> Unit 7
#   LaTeX .tex output               -> Unit 8
#
# Inputs:  data/processed/muni_panel_for_regs_policy_block.qs2
# Outputs: explorations/anderson_rubin/output/ar_results.csv
#          (primary row preserved; C1/C2/C3/C4 appended => 5 rows total)
# ==============================================================================

# ---- 1. Packages (INV-15: all at top) ----------------------------------------
suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
  library(here)
})

# ---- 2. Seed (INV-14: exactly once at top) ------------------------------------
set.seed(20260429L)

# ---- 3. Paths via here::here() (INV-16: no absolute paths) -------------------
PANEL_PATH <- here::here(
  "data", "processed", "muni_panel_for_regs_policy_block.qs2"
)
OUT_DIR <- here::here("explorations", "anderson_rubin", "output")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

OUT_CSV <- file.path(OUT_DIR, "ar_results.csv")

# ============================================================
# Paper-to-Code Naming Map
# ============================================================
# Paper Notation      | Code Name                                     | Description
# Y_mt                | log_gdp                                       | Log municipal GDP
# Z^Agro_mt           | ar_Z_mayor_coalition_cycle_specific_Agro      | AR instrument: Agro
# Z^Ind_mt            | ar_Z_mayor_coalition_cycle_specific_Ind       | AR instrument: Industry
# Z^Infra_mt          | ar_Z_mayor_coalition_cycle_specific_Infra     | AR instrument: Infra
# Z^Serv_mt           | ar_Z_mayor_coalition_cycle_specific_Serv      | AR instrument: Services
# EC^ell_mt (R0a)     | ec_total_mayor_cycle_specific                 | Muni-total exposure control (C2)
# EC^ell_jmt (R0b) x4 | ar_exposure_control_mayor_cycle_specific_{j} | Sector EC columns (C3)
# log L_mt            | log_total_employment                          | Log employment (C4, bad-control)
# F^AR                | f_stat                                        | AR Wald F-statistic
# p^AR                | p_value                                       | AR p-value
# K                   | K                                             | Number of instruments
# N                   | n_obs                                         | Regression observations
# M                   | n_clusters                                    | Number of muni clusters
# R2_within           | r2 (wr2 for FE specs)                         | Within-R2 for FE; overall R2 for no-FE
# ============================================================

# ---- 4. Load and prepare data ------------------------------------------------
message("Loading panel: ", PANEL_PATH)
if (!file.exists(PANEL_PATH)) {
  stop(
    "Panel not found: ", PANEL_PATH,
    "\nRun: Rscript scripts/R/run_politicsregs.R 41 -- ",
    "--sector-var=policy_block"
  )
}

dt <- qs2::qs_read(PANEL_PATH)
setDT(dt)

n_raw <- nrow(dt)
dt <- dt[!is.na(log_gdp) & is.finite(log_gdp)]
n_after <- nrow(dt)
message(sprintf(
  "Sample: %d rows loaded; %d dropped (NA/Inf log_gdp); %d retained",
  n_raw, n_raw - n_after, n_after
))

# Verify required columns exist
PRIMARY_Z_COLS <- c(
  "ar_Z_mayor_coalition_cycle_specific_Agro",
  "ar_Z_mayor_coalition_cycle_specific_Ind",
  "ar_Z_mayor_coalition_cycle_specific_Infra",
  "ar_Z_mayor_coalition_cycle_specific_Serv"
)
missing_cols <- setdiff(PRIMARY_Z_COLS, names(dt))
if (length(missing_cols) > 0L) {
  stop(
    "Missing instrument columns in panel:\n  ",
    paste(missing_cols, collapse = "\n  "),
    "\nPanel may need to be rebuilt with --sector-var=policy_block"
  )
}
message("Instrument columns verified: ", paste(PRIMARY_Z_COLS, collapse = ", "))

# ---- 5. Audit C2/C3/C4 column availability in Panel B -----------------------
C2_COL   <- "ec_total_mayor_cycle_specific"
C3_COLS  <- paste0("ar_exposure_control_mayor_cycle_specific_",
                   c("Agro", "Ind", "Infra", "Serv"))
C4_COL   <- "log_total_employment"

c2_present <- C2_COL %in% names(dt)
c3_missing <- setdiff(C3_COLS, names(dt))
c4_present <- C4_COL %in% names(dt)

message("\n--- Controls ladder column audit ---")
message(sprintf("  C2 scalar (%s): %s", C2_COL,
                if (c2_present) "PRESENT" else "MISSING"))
message(sprintf("  C3 sector cols (%d): %s", length(C3_COLS),
                if (length(c3_missing) == 0L) "ALL PRESENT"
                else paste("MISSING:", paste(c3_missing, collapse = ", "))))
message(sprintf("  C4 col (%s): %s", C4_COL,
                if (c4_present) "PRESENT" else "NOT FOUND — C4 row will be NA"))

# ---- 6. Helpers: run AR test -------------------------------------------------

#' Run pooled Anderson-Rubin test for a single specification.
#'
#' @param data      data.table. Must contain log_gdp, muni_id, and all z_cols.
#' @param z_cols    character. Instrument column names.
#' @param fe_str    character or NULL. fixest FE string, e.g. "muni_id + year".
#'                  NULL means no FE (primary spec).
#' @param ctrl_cols character. Additional covariate column names (RHS). Default
#'                  character(0) — no covariates.
#' @param cluster   character. Cluster variable name (default "muni_id").
#' @return data.table with one row: f_stat, p_value, df1, df2, n_obs,
#'         n_clusters, r2.
run_ar_spec <- function(data, z_cols, fe_str = NULL, ctrl_cols = character(0L),
                        cluster = "muni_id") {
  stopifnot(is.data.table(data))
  stopifnot(is.character(z_cols), length(z_cols) >= 1L)
  required <- c("log_gdp", cluster, z_cols)
  if (length(ctrl_cols) > 0L) required <- c(required, ctrl_cols)
  stopifnot(all(required %in% names(data)))

  rhs_regressors <- c(z_cols, ctrl_cols)
  rhs_str <- paste(rhs_regressors, collapse = " + ")

  if (!is.null(fe_str) && nchar(trimws(fe_str)) > 0L) {
    fml_str <- paste0("log_gdp ~ ", rhs_str, " | ", fe_str)
  } else {
    fml_str <- paste0("log_gdp ~ ", rhs_str)
  }
  fml <- as.formula(fml_str)

  vcov_spec <- as.formula(paste0("~", cluster))
  m <- fixest::feols(fml, data = data, vcov = vcov_spec)

  ar <- fixest::wald(m, keep = "^ar_Z_")

  # Within-R2 for FE specs; overall R2 for no-FE primary
  has_fe <- !is.null(fe_str) && nchar(trimws(fe_str)) > 0L
  r2_val <- if (has_fe) {
    unname(fixest::r2(m, "wr2"))
  } else {
    unname(fixest::r2(m, "r2"))
  }

  n_obs      <- nobs(m)
  n_clusters <- uniqueN(data[[cluster]])

  data.table(
    f_stat     = ar$stat,
    p_value    = ar$p,
    df1        = ar$df1,
    df2        = ar$df2,
    n_obs      = n_obs,
    n_clusters = n_clusters,
    r2         = r2_val
  )
}

# ---- 7. Build metadata wrapper -----------------------------------------------

#' Attach spec-level metadata to a run_ar_spec result row.
#'
#' @param ar_row   data.table (1 row) from run_ar_spec().
#' @param spec_id  character.
#' @param controls character.
#' @param is_primary logical.
#' @return data.table (1 row) with full output schema.
make_result_row <- function(ar_row, spec_id, controls, is_primary = FALSE) {
  data.table(
    spec_id    = spec_id,
    tier       = "mayor",
    align      = "coalition",
    baseline   = "cycle_specific",
    weight     = "owner",
    time_var   = "Z",
    outcome    = "log_gdp",
    controls   = controls,
    K          = 4L,
    n_obs      = ar_row$n_obs,
    n_clusters = ar_row$n_clusters,
    f_stat     = ar_row$f_stat,
    p_value    = ar_row$p_value,
    df1        = ar_row$df1,
    df2        = ar_row$df2,
    r2         = ar_row$r2,
    is_primary = is_primary
  )
}

# ---- 8. Run PRIMARY spec -----------------------------------------------------
message("\nRunning PRIMARY spec: K=4, mayor, coalition, cycle_specific, log_gdp,",
        " no controls, vcov = ~muni_id")

ar_primary <- run_ar_spec(
  data    = dt,
  z_cols  = PRIMARY_Z_COLS,
  fe_str  = NULL,
  cluster = "muni_id"
)
row_primary <- make_result_row(ar_primary, spec_id = "primary",
                               controls = "none", is_primary = TRUE)

# ---- 9. Controls ladder — C1: FE only ----------------------------------------
message("\nRunning C1: K=4, FE = muni_id + year, no covariates")

ar_c1 <- run_ar_spec(
  data      = dt,
  z_cols    = PRIMARY_Z_COLS,
  fe_str    = "muni_id + year",
  ctrl_cols = character(0L),
  cluster   = "muni_id"
)
row_c1 <- make_result_row(ar_c1, spec_id = "C1_FE", controls = "FE")

# ---- 10. Controls ladder — C2: FE + muni-total EC (R0a) ----------------------
message("\nRunning C2: FE + ec_total_mayor_cycle_specific (R0a)")

if (!c2_present) {
  stop(
    "Column '", C2_COL, "' not found in Panel B.\n",
    "Rebuild Panel B: Rscript scripts/R/run_politicsregs.R 41 -- ",
    "--sector-var=policy_block"
  )
}

ar_c2 <- run_ar_spec(
  data      = dt,
  z_cols    = PRIMARY_Z_COLS,
  fe_str    = "muni_id + year",
  ctrl_cols = C2_COL,
  cluster   = "muni_id"
)
row_c2 <- make_result_row(ar_c2, spec_id = "C2_FE_R0a", controls = "FE_R0a")

# ---- 11. Controls ladder — C3: FE + sector-specific EC (R0b) -----------------
message("\nRunning C3: FE + ar_exposure_control_mayor_cycle_specific_{Agro,Ind,Infra,Serv} (R0b)")

if (length(c3_missing) > 0L) {
  stop(
    "Missing C3 columns in Panel B:\n  ",
    paste(c3_missing, collapse = "\n  "),
    "\nRebuild Panel B: Rscript scripts/R/run_politicsregs.R 41 -- ",
    "--sector-var=policy_block"
  )
}

ar_c3 <- run_ar_spec(
  data      = dt,
  z_cols    = PRIMARY_Z_COLS,
  fe_str    = "muni_id + year",
  ctrl_cols = C3_COLS,
  cluster   = "muni_id"
)
row_c3 <- make_result_row(ar_c3, spec_id = "C3_FE_R0b", controls = "FE_R0b")

# ---- 12. Controls ladder — C4: FE + log_total_employment ---------------------
# NOTE: Bad-control risk — employment is a downstream outcome of BNDES credit
# (strategy memo §6 / §10). This spec is diagnostic only; do not use as primary
# or robustness. A positive BNDES effect on GDP may operate partly through
# employment, so controlling for employment attenuates the AR test toward zero
# even when H0 is false. Include for transparency; flag in paper.
message("\nRunning C4: FE + log_total_employment (BAD-CONTROL RISK — see strategy memo §6/§10)")

if (!c4_present) {
  cat(
    "WARNING: '", C4_COL, "' not found in Panel B. ",
    "C4 row will be recorded with NA statistics.\n",
    sep = ""
  )
  row_c4 <- data.table(
    spec_id    = "C4_FE_emp",
    tier       = "mayor",
    align      = "coalition",
    baseline   = "cycle_specific",
    weight     = "owner",
    time_var   = "Z",
    outcome    = "log_gdp",
    controls   = "FE_emp",
    K          = 4L,
    n_obs      = NA_integer_,
    n_clusters = NA_integer_,
    f_stat     = NA_real_,
    p_value    = NA_real_,
    df1        = NA_real_,
    df2        = NA_real_,
    r2         = NA_real_,
    is_primary = FALSE
  )
} else {
  ar_c4 <- run_ar_spec(
    data      = dt,
    z_cols    = PRIMARY_Z_COLS,
    fe_str    = "muni_id + year",
    ctrl_cols = C4_COL,
    cluster   = "muni_id"
  )
  row_c4 <- make_result_row(ar_c4, spec_id = "C4_FE_emp", controls = "FE_emp")
}

# ---- 13. Combine and write output --------------------------------------------
# Read existing primary row if CSV already exists, then rbind controls ladder.
# This preserves the primary row and its original r2 exactly as written.
# Final file has 5 rows: primary first, then C1, C2, C3, C4.
ladder_rows <- rbindlist(list(row_c1, row_c2, row_c3, row_c4))

if (file.exists(OUT_CSV)) {
  existing <- data.table::fread(OUT_CSV)
  # Keep only the primary row from any prior write; drop stale ladder rows
  # in case the script is re-run (idempotent behaviour).
  primary_row_existing <- existing[spec_id == "primary"]
  if (nrow(primary_row_existing) == 0L) {
    message("WARNING: No 'primary' row found in existing CSV. Using freshly computed primary.")
    primary_row_existing <- row_primary
  }
  all_results <- rbindlist(list(primary_row_existing, ladder_rows),
                            use.names = TRUE, fill = TRUE)
} else {
  # CSV does not yet exist — write primary + ladder in one shot
  message("No existing CSV found — writing primary + ladder together.")
  all_results <- rbindlist(list(row_primary, ladder_rows),
                            use.names = TRUE, fill = TRUE)
}

data.table::fwrite(all_results, OUT_CSV)
message("\nResults written to: ", OUT_CSV,
        " (", nrow(all_results), " rows)")

# ---- 14. Console summary — 5-row mini-table ----------------------------------
message("\n=== CONTROLS LADDER RESULTS (K=4, mayor, coalition, cycle_specific) ===")
message(sprintf("%-16s %-12s %4s %10s %10s",
                "spec_id", "controls", "K", "F", "p"))
message(strrep("-", 58))
for (i in seq_len(nrow(all_results))) {
  r <- all_results[i]
  message(sprintf("%-16s %-12s %4d %10s %10s",
                  r$spec_id,
                  r$controls,
                  r$K,
                  if (is.na(r$f_stat)) "NA" else sprintf("%.4f", r$f_stat),
                  if (is.na(r$p_value)) "NA" else sprintf("%.2e", r$p_value)))
}
message(strrep("-", 58))
message(sprintf("Total rows: %d", nrow(all_results)))

if (!c4_present) {
  message(sprintf(
    "\nC4 NOTE: '%s' not present in Panel B. C4 statistics are NA.",
    C4_COL
  ))
}

message("\nar_baseline.R completed successfully.")
