#!/usr/bin/env Rscript

# ==============================================================================
# Synthetic Verification: Proposition 2 Aggregation Equivalence
# ==============================================================================
# Generates synthetic firm-level data with a known DGP, then verifies that
# firm-level OLS and N_c-weighted cell OLS produce identical coefficients
# under the four conditions of Proposition 2 (review_aggregation.tex).
#
# Then systematically breaks each condition one at a time to demonstrate
# that each is necessary.
#
# Outputs:
#   - Console summary
#   - CSV at output/diagnostics/prop2_synthetic_results.csv
#
# Usage:
#   Rscript verify_proposition2_synthetic.R
# ==============================================================================

cat("==============================================================================\n")
cat("Synthetic Verification: Proposition 2 Aggregation Equivalence\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
})

# --- Bootstrap (optional: works standalone or within pipeline) ----------------

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

# --- Check fixest version -----------------------------------------------------

if (packageVersion("fixest") < "0.11") {
  stop("fixest >= 0.11 required for fixef.rm = 'none'. Current: ", packageVersion("fixest"))
}

# --- Output directory ---------------------------------------------------------

diag_dir <- file.path(OUTPUT_DIR, "diagnostics")
dir.create(diag_dir, recursive = TRUE, showWarnings = FALSE)

# ==============================================================================
# STEP 1: Generate synthetic data
# ==============================================================================

cat("Step 1: Generating synthetic data...\n")

set.seed(42)

N_FIRMS  <- 1000L
N_MUNIS  <- 50L
N_SECTORS <- 5L
N_YEARS  <- 10L
MIN_CELL_SIZE <- 3L

# True coefficients
LAMBDA <- c(mayor = 0.05, gov = 0.03, pres = -0.02)

# --- Assign each firm to exactly one (muni, sector) cell ---------------------
# Ensure each cell has >= MIN_CELL_SIZE firms

n_cells <- N_MUNIS * N_SECTORS
firms_per_cell <- rep(MIN_CELL_SIZE, n_cells)
remaining <- N_FIRMS - sum(firms_per_cell)
if (remaining < 0) stop("Not enough firms for minimum cell sizes")

# Distribute remaining firms randomly across cells
extra <- sample.int(n_cells, remaining, replace = TRUE)
for (i in extra) firms_per_cell[i] <- firms_per_cell[i] + 1L

cell_grid <- CJ(muni_id = seq_len(N_MUNIS), sector_id = seq_len(N_SECTORS))
cell_grid[, cell_idx := .I]
cell_grid[, n_firms := firms_per_cell]

# Create firm -> cell assignment
firm_cell <- cell_grid[rep(cell_idx, n_firms), .(muni_id, sector_id, cell_idx)]
firm_cell[, firm_id := .I]

cat(sprintf("  %d firms, %d cells, min cell size = %d\n",
            nrow(firm_cell), n_cells, min(cell_grid$n_firms)))

# --- Expand to firm x year panel ---------------------------------------------

dt <- CJ(firm_id = seq_len(N_FIRMS), year = seq_len(N_YEARS))
dt[firm_cell, `:=`(muni_id = i.muni_id, sector_id = i.sector_id, cell_idx = i.cell_idx),
   on = "firm_id"]

# --- Generate instruments: FA_* = omega_cp * align_* -------------------------
# Keep party exposure constant within each cell so the baseline test satisfies
# the lossless aggregation benchmark implied by the grouped regression.
cell_omega <- data.table(
  cell_idx = seq_len(n_cells),
  omega_mayor = runif(n_cells),
  omega_gov   = runif(n_cells),
  omega_pres  = runif(n_cells)
)

dt[cell_omega, `:=`(
  omega_mayor = i.omega_mayor,
  omega_gov   = i.omega_gov,
  omega_pres  = i.omega_pres
), on = "cell_idx"]

# Alignment indicators (muni x year level)
align_dt <- CJ(muni_id = seq_len(N_MUNIS), year = seq_len(N_YEARS))
align_dt[, align_mayor := rbinom(.N, 1, 0.5)]
align_dt[, align_gov   := rbinom(.N, 1, 0.5)]
align_dt[, align_pres  := rbinom(.N, 1, 0.5)]

dt[align_dt, `:=`(align_mayor = i.align_mayor,
                   align_gov = i.align_gov,
                   align_pres = i.align_pres),
   on = c("muni_id", "year")]

# Construct FA instruments
dt[, FA_mayor := omega_mayor * align_mayor]
dt[, FA_gov   := omega_gov * align_gov]
dt[, FA_pres  := omega_pres * align_pres]

# --- Generate fixed effects and outcome --------------------------------------

gamma_f <- rnorm(N_FIRMS, 0, 0.2)
alpha_mt <- rnorm(N_MUNIS * N_YEARS, 0, 0.1)
alpha_mt_dt <- CJ(muni_id = seq_len(N_MUNIS), year = seq_len(N_YEARS))
alpha_mt_dt[, alpha_mt := alpha_mt]

dt[, gamma_f := gamma_f[firm_id]]
dt[alpha_mt_dt, alpha_mt := i.alpha_mt, on = c("muni_id", "year")]

# LPM outcome (may exceed [0,1] -- fine for equivalence testing)
dt[, u := rnorm(.N, 0, 0.3)]
dt[, Y := LAMBDA["mayor"] * FA_mayor +
          LAMBDA["gov"] * FA_gov +
          LAMBDA["pres"] * FA_pres +
          gamma_f + alpha_mt + u]

# Create cell_id for aggregated FE
dt[, cell_id := paste0(muni_id, "_", sector_id)]

cat(sprintf("  Panel: %s rows, %d firms x %d years\n",
            format(nrow(dt), big.mark = ","), N_FIRMS, N_YEARS))

# ==============================================================================
# STEP 2: Helper functions
# ==============================================================================

collapse_to_cells <- function(dt_in) {
  agg <- dt_in[, .(
    Y_bar      = mean(Y),
    FA_bar_mayor = mean(FA_mayor),
    FA_bar_gov   = mean(FA_gov),
    FA_bar_pres  = mean(FA_pres),
    N_c        = .N
  ), by = .(cell_id, muni_id, sector_id, year)]
  agg
}

run_test <- function(test_name, dt_test, use_nc_weights = TRUE,
                     firm_fe = "firm_id + muni_id^year",
                     agg_fe = "cell_id + muni_id^year",
                     fixef_rm = "none",
                     keep_models = FALSE) {
  # Firm-level regression (lean = FALSE when we need models for tables)
  firm_fml <- as.formula(paste0("Y ~ FA_mayor + FA_gov + FA_pres | ", firm_fe))
  mod_firm <- feols(firm_fml, data = dt_test, fixef.rm = fixef_rm,
                    nthreads = 1L, lean = !keep_models)

  # Collapse to cells
  agg <- collapse_to_cells(dt_test)

  # Cell-level regression
  agg_fml <- as.formula(paste0("Y_bar ~ FA_bar_mayor + FA_bar_gov + FA_bar_pres | ", agg_fe))
  wt <- if (use_nc_weights) agg$N_c else NULL
  mod_agg <- feols(agg_fml, data = agg, weights = wt, fixef.rm = fixef_rm,
                   nthreads = 1L, lean = !keep_models)

  # Compare coefficients
  firm_coef <- coef(mod_firm)[c("FA_mayor", "FA_gov", "FA_pres")]
  agg_coef  <- coef(mod_agg)[c("FA_bar_mayor", "FA_bar_gov", "FA_bar_pres")]

  diffs <- abs(unname(firm_coef) - unname(agg_coef))
  max_dev <- max(diffs)
  worst_coef <- c("mayor", "gov", "pres")[which.max(diffs)]

  pass <- max_dev < 1e-8

  cat(sprintf("  [%s] max|coef_diff| = %.2e (%s) -> %s\n",
              test_name, max_dev, worst_coef, if (pass) "PASS" else "FAIL"))

  summary_row <- data.table(
    test = test_name,
    max_abs_deviation = max_dev,
    worst_coefficient = worst_coef,
    firm_N = nobs(mod_firm),
    agg_N = nobs(mod_agg),
    pass = pass
  )

  if (keep_models) {
    list(summary = summary_row, mod_firm = mod_firm, mod_agg = mod_agg)
  } else {
    summary_row
  }
}

# ==============================================================================
# STEP 3: Run test battery
# ==============================================================================

cat("\nStep 2: Running Proposition 2 test battery...\n\n")

results <- list()
test_models <- list()  # store models for beamer table

# --- Test 1: Baseline (all conditions hold) ---
baseline_out <- run_test(
  "Baseline (correct)",
  dt,
  use_nc_weights = TRUE,
  firm_fe = "firm_id + muni_id^year",
  agg_fe = "cell_id + muni_id^year",
  fixef_rm = "none",
  keep_models = TRUE
)
results[[1]] <- baseline_out$summary
test_models[["baseline"]] <- baseline_out

# --- Test 2: Break Condition 1 (weighting) ---
cond1_out <- run_test(
  "Break Cond 1 (no N_c weights)",
  dt,
  use_nc_weights = FALSE,
  firm_fe = "firm_id + muni_id^year",
  agg_fe = "cell_id + muni_id^year",
  fixef_rm = "none",
  keep_models = TRUE
)
results[[2]] <- cond1_out$summary
test_models[["break_weights"]] <- cond1_out

# --- Test 3: Break Condition 2 (sample mismatch via singleton absorption) ---
# Inject singleton FE groups so that removing fixef.rm="none" drops them
# differently across firm vs. aggregated regressions
dt_cond2 <- copy(dt)

# Add a few firms that appear in only 1 year (singleton in firm FE)
n_singleton <- 50L
singleton_firms <- (N_FIRMS + 1L):(N_FIRMS + n_singleton)
singleton_dt <- data.table(
  firm_id = singleton_firms,
  year = sample.int(N_YEARS, n_singleton, replace = TRUE),
  muni_id = sample.int(N_MUNIS, n_singleton, replace = TRUE),
  sector_id = sample.int(N_SECTORS, n_singleton, replace = TRUE)
)
singleton_dt[, cell_id := paste0(muni_id, "_", sector_id)]
singleton_dt[, cell_idx := NA_integer_]

# Generate their data using the destination cell's exposure so this test
# perturbs the sample only and does not introduce extra within-cell variation.
singleton_dt[cell_grid, cell_idx := i.cell_idx, on = c("muni_id", "sector_id")]
singleton_dt[cell_omega, `:=`(
  omega_mayor = i.omega_mayor,
  omega_gov   = i.omega_gov,
  omega_pres  = i.omega_pres
), on = "cell_idx"]
singleton_dt[align_dt, `:=`(align_mayor = i.align_mayor,
                             align_gov = i.align_gov,
                             align_pres = i.align_pres),
             on = c("muni_id", "year")]
singleton_dt[, FA_mayor := omega_mayor * align_mayor]
singleton_dt[, FA_gov   := omega_gov * align_gov]
singleton_dt[, FA_pres  := omega_pres * align_pres]
singleton_dt[, gamma_f := rnorm(.N, 0, 0.2)]
singleton_dt[alpha_mt_dt, alpha_mt := i.alpha_mt, on = c("muni_id", "year")]
singleton_dt[, u := rnorm(.N, 0, 0.3)]
singleton_dt[, Y := LAMBDA["mayor"] * FA_mayor +
                    LAMBDA["gov"] * FA_gov +
                    LAMBDA["pres"] * FA_pres +
                    gamma_f + alpha_mt + u]

dt_cond2 <- rbind(dt_cond2, singleton_dt, fill = TRUE)

# With fixef.rm = "none", baseline should still pass
cond2_out <- run_test(
  "Break Cond 2 (singleton absorption on)",
  dt_cond2,
  use_nc_weights = TRUE,
  firm_fe = "firm_id + muni_id^year",
  agg_fe = "cell_id + muni_id^year",
  fixef_rm = "perfect_fit",  # default behavior: absorb singletons/perfect-fit FE
  keep_models = TRUE
)
results[[3]] <- cond2_out$summary
test_models[["break_sample"]] <- cond2_out

# --- Test 4: Break Condition 3a (wrong FE structure) ---
# Use muni^sector + sector^year instead of cell_id + muni^year
cond3a_out <- run_test(
  "Break Cond 3a (wrong agg FE)",
  dt,
  use_nc_weights = TRUE,
  firm_fe = "firm_id + muni_id^year",
  agg_fe = "muni_id^sector_id + sector_id^year",
  fixef_rm = "none",
  keep_models = TRUE
)
results[[4]] <- cond3a_out$summary
test_models[["break_fe"]] <- cond3a_out

# --- Test 5: Break Condition 3b (firm mobility across cells) ---
# Reassign ~20% of firms to 2+ cells over time. Refresh cell-level exposure
# after mobility so the only violation comes from broken FE nesting.
dt_cond3b <- copy(dt)
n_mobile <- as.integer(N_FIRMS * 0.2)
mobile_firms <- sample.int(N_FIRMS, n_mobile)

# For mobile firms, reassign their cell in the second half of years
for (f in mobile_firms) {
  new_muni <- sample(setdiff(seq_len(N_MUNIS), firm_cell$muni_id[f]), 1)
  new_sector <- sample(setdiff(seq_len(N_SECTORS), firm_cell$sector_id[f]), 1)
  dt_cond3b[firm_id == f & year > (N_YEARS / 2),
            `:=`(muni_id = new_muni, sector_id = new_sector)]
}
dt_cond3b[cell_grid, cell_idx := i.cell_idx, on = c("muni_id", "sector_id")]
dt_cond3b[cell_omega, `:=`(
  omega_mayor = i.omega_mayor,
  omega_gov   = i.omega_gov,
  omega_pres  = i.omega_pres
), on = "cell_idx"]
dt_cond3b[, cell_id := paste0(muni_id, "_", sector_id)]

# Re-generate muni-level alignment for any new muni-years
dt_cond3b[align_dt, `:=`(align_mayor = i.align_mayor,
                          align_gov = i.align_gov,
                          align_pres = i.align_pres),
          on = c("muni_id", "year")]
dt_cond3b[, FA_mayor := omega_mayor * align_mayor]
dt_cond3b[, FA_gov   := omega_gov * align_gov]
dt_cond3b[, FA_pres  := omega_pres * align_pres]

# Recompute muni_id^year FE component for consistency
dt_cond3b[alpha_mt_dt, alpha_mt := i.alpha_mt, on = c("muni_id", "year")]
dt_cond3b[, Y := LAMBDA["mayor"] * FA_mayor +
                 LAMBDA["gov"] * FA_gov +
                 LAMBDA["pres"] * FA_pres +
                 gamma_f + alpha_mt + u]

cond3b_out <- run_test(
  "Break Cond 3b (firm mobility)",
  dt_cond3b,
  use_nc_weights = TRUE,
  firm_fe = "firm_id + muni_id^year",
  agg_fe = "cell_id + muni_id^year",
  fixef_rm = "none",
  keep_models = TRUE
)
results[[5]] <- cond3b_out$summary
test_models[["break_mobility"]] <- cond3b_out

# ==============================================================================
# STEP 4: Summarize and save
# ==============================================================================

cat("\n--- Summary ---\n\n")

results_dt <- rbindlist(results)

for (i in seq_len(nrow(results_dt))) {
  r <- results_dt[i]
  cat(sprintf("  %-40s  max_dev = %10.2e  worst = %-8s  %s\n",
              r$test, r$max_abs_deviation, r$worst_coefficient,
              if (r$pass) "PASS" else "FAIL"))
}

# Save CSV
out_path <- file.path(diag_dir, "prop2_synthetic_results.csv")
fwrite(results_dt, out_path)
cat(sprintf("\nSaved: %s\n", out_path))

# ==============================================================================
# STEP 5: Generate Beamer regression table
# ==============================================================================

cat("\nStep 5: Generating Beamer table...\n")

source(politicsregs_path("_utils", "beamer_tables.R"))
TABLE_DIR <- diag_dir

# Harmonize aggregated coefficient names to firm names so they appear in the
# same rows of the table produced by save_beamer_table().
harmonize_agg_names <- function(mod) {
  rename_map <- c(FA_bar_mayor = "FA_mayor", FA_bar_gov = "FA_gov", FA_bar_pres = "FA_pres")
  nm <- names(mod$coefficients)
  for (old in names(rename_map)) {
    nm[nm == old] <- rename_map[[old]]
  }
  names(mod$coefficients) <- nm
  # Also fix coeftable row names
  ct <- mod$coeftable
  rn <- rownames(ct)
  for (old in names(rename_map)) {
    rn[rn == old] <- rename_map[[old]]
  }
  rownames(ct) <- rn
  mod$coeftable <- ct
  mod
}

# Build a 10-column table: for each of the 5 tests, firm (odd cols) and agg (even cols)
mod_list <- list()
test_labels <- c(
  "Baseline" = "baseline",
  "No $N_c$ wt" = "break_weights",
  "Singl. abs." = "break_sample",
  "Wrong FE" = "break_fe",
  "Mobility" = "break_mobility"
)

for (lbl in names(test_labels)) {
  key <- test_labels[[lbl]]
  tm <- test_models[[key]]
  mod_list[[paste0(lbl, " (F)")]] <- tm$mod_firm
  mod_list[[paste0(lbl, " (A)")]] <- harmonize_agg_names(tm$mod_agg)
}

coef_map_synth <- c(
  "FA_mayor" = "$FA^{\\text{mayor}}$",
  "FA_gov"   = "$FA^{\\text{gov}}$",
  "FA_pres"  = "$FA^{\\text{pres}}$"
)

# Build max-deviation footer for each test pair
dev_notes <- vapply(names(test_labels), function(lbl) {
  key <- test_labels[[lbl]]
  r <- results_dt[test == {
    switch(key,
      baseline = "Baseline (correct)",
      break_weights = "Break Cond 1 (no N_c weights)",
      break_sample = "Break Cond 2 (singleton absorption on)",
      break_fe = "Break Cond 3a (wrong agg FE)",
      break_mobility = "Break Cond 3b (firm mobility)"
    )
  }]
  if (r$pass) {
    sprintf("%s: $< 10^{-8}$ \\textcolor{notegreen}{PASS}", lbl)
  } else {
    sprintf("%s: $%.3f$ \\textcolor{alertred}{FAIL}", lbl, r$max_abs_deviation)
  }
}, character(1))

table_notes <- paste0(
  "Synthetic DGP ($N = 10{,}000$). (F) = firm-level, (A) = $N_c$-weighted cell-level. ",
  "Max $|\\Delta\\hat\\beta|$: ",
  paste(dev_notes, collapse = "; "),
  ". True $\\lambda$: mayor $= 0.05$, gov $= 0.03$, pres $= -0.02$. ",
  "$^{***}p<0.01$, $^{**}p<0.05$, $^{*}p<0.10$."
)

save_beamer_table(
  mod_list,
  "prop2_synthetic_comparison",
  coef_map = coef_map_synth,
  dep_var = "$Y$ / $\\bar{Y}_c$",
  notes = table_notes,
  add_f_stat = FALSE,
  table_dir = diag_dir
)

cat(sprintf("  Table saved: %s\n", file.path(diag_dir, "prop2_synthetic_comparison.tex")))

# Validate expectations
baseline_pass <- results_dt[test == "Baseline (correct)", pass]
breaks_fail <- all(!results_dt[!grepl("Baseline", test), pass])

if (baseline_pass && breaks_fail) {
  cat("\nAll expectations met: baseline PASSES, all condition breaks FAIL.\n")
} else {
  if (!baseline_pass) cat("\nWARNING: Baseline test did not PASS!\n")
  if (!breaks_fail) cat("\nWARNING: Some condition-break tests unexpectedly PASSED!\n")
}

cat("\nDone.\n")
