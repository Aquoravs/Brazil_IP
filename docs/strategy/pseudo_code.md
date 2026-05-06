# Pseudo-Code: Anderson-Rubin Test -- Baseline Implementation

## Script: `explorations/anderson_rubin/ar_baseline.R`

```
# ==============================================================================
# Anderson-Rubin Test: Baseline (Phase 1)
# ==============================================================================
# Tests H0: gamma = 0 in the reduced-form regression
#   log(GDP_pc_mt) = alpha_m + delta_t + gamma' * Z_mt + epsilon_mt
# where Z_mt are sector-level shift-share instruments (BNDES macro-sectors).
#
# The AR statistic is the cluster-robust Wald F-statistic on the Z coefficients.
# Under H0: beta = 0, this equals the Anderson-Rubin test (Finlay & Magnusson 2009).
# ==============================================================================

LOAD packages: data.table, fixest, qs2

SET seed (not needed for deterministic regression, but set for any bootstrap/permutation)

# --- Step 1: Load Panel B ---------------------------------------------------

LOAD muni_panel_for_regs.qs2 (or grouped variant with bndes_sector)
  -> dt[muni_id, year, log_gdp_pc, log_gdp, Z_*_bndes_sector_*, dZ_*_bndes_sector_*,
        EC_*_bndes_sector_*]

# BLOCKER: bndes_sector may not be wired through the pipeline.
# If Z columns for bndes_sector are not present, STOP and resolve:
#   Option A: Add --sector-var=bndes_sector to scripts 31, 34, 41
#   Option B: Collapse Panel A from sector_group to bndes_sector in this script

DROP rows with missing log_gdp_pc
REPORT sample size: N_obs, N_munis, N_years

# --- Step 2: Identify instrument columns ------------------------------------

# BNDES macro-sectors: Agropecuaria, Industria, Infraestrutura, Comercio_Servicos
# (Exact column names depend on how bndes_sector is encoded in wide format)

IDENTIFY z_cols_levels_mayor   <- grep("^Z_mayor_coalition_cycle_specific_.*$")
IDENTIFY z_cols_levels_gov     <- grep("^Z_gov_coalition_cycle_specific_.*$")
IDENTIFY z_cols_changes_mayor  <- grep("^dZ_mayor_coalition_cycle_specific_.*$")
IDENTIFY ec_cols_mayor         <- grep("^EC_mayor_.*$")  # exposure controls

REPORT: "Instruments found: {K_mayor} mayor, {K_gov} governor"
REPORT: "Exposure controls found: {length(ec_cols_mayor)}"

# Check for zero-variation columns within municipality
FOR each z_col:
  COMPUTE n_nonzero_within <- number of munis with any non-zero within-muni variation
  IF n_nonzero_within < 100:
    FLAG as sparse; consider dropping
  REPORT: "{z_col}: {n_nonzero_within} munis with variation"

# --- Step 3: Primary AR Test ------------------------------------------------

# Spec 1: Mayor only, levels, cycle-specific baseline, NO exposure control
formula_1 <- log_gdp_pc ~ Z_mayor_1 + Z_mayor_2 + Z_mayor_3 + Z_mayor_4
             | muni_id + year

mod_1 <- feols(formula_1, data = dt, vcov = ~muni_id)
ar_1  <- fixest::wald(mod_1, keep = "^Z_")
STORE: F_stat, p_value, df1, df2

# Spec 1b: Mayor only, levels, WITH sector-specific exposure controls (R0)
formula_1b <- log_gdp_pc ~ Z_mayor_1 + Z_mayor_2 + Z_mayor_3 + Z_mayor_4
              + EC_mayor_1 + EC_mayor_2 + EC_mayor_3 + EC_mayor_4
              | muni_id + year

mod_1b <- feols(formula_1b, data = dt, vcov = ~muni_id)
ar_1b  <- fixest::wald(mod_1b, keep = "^Z_")
STORE: F_stat, p_value, df1, df2
REPORT: "AR without exposure control: F={ar_1$stat}, p={ar_1$p}"
REPORT: "AR with exposure control:    F={ar_1b$stat}, p={ar_1b$p}"

# Spec 2: Mayor + Governor, levels, cycle-specific
formula_2 <- log_gdp_pc ~ Z_mayor_1 + ... + Z_mayor_4
             + Z_gov_1 + ... + Z_gov_4
             | muni_id + year

mod_2 <- feols(formula_2, data = dt, vcov = ~muni_id)
ar_2  <- fixest::wald(mod_2, keep = "^Z_")

# Spec 3: Mayor only, changes instruments
formula_3 <- log_gdp_pc ~ dZ_mayor_1 + ... + dZ_mayor_4
             | muni_id + year

mod_3 <- feols(formula_3, data = dt, vcov = ~muni_id)
ar_3  <- fixest::wald(mod_3, keep = "^dZ_")

# Spec 4: 2002-fixed baseline (robustness)
# Same as Spec 1 but with Z_mayor_*_2002_fixed_* columns
mod_4 <- feols(formula_4, data = dt, vcov = ~muni_id)
ar_4  <- fixest::wald(mod_4, keep = "^Z_")

# Spec 5: log(GDP) instead of log(GDP_pc)
mod_5 <- feols(log_gdp ~ Z_mayor_1 + ... | muni_id + year,
               data = dt, vcov = ~muni_id)
ar_5  <- fixest::wald(mod_5, keep = "^Z_")

# --- Step 4: Individual Sector Tests ----------------------------------------

FOR j in 1:4 (each BNDES sector):
  mod_j <- feols(log_gdp_pc ~ Z_mayor_j | muni_id + year,
                 data = dt, vcov = ~muni_id)
  t_j <- coeftable(mod_j)["Z_mayor_j", "t value"]
  STORE: coef_j, se_j, t_j, p_j

REPORT table of individual sector coefficients and p-values

# --- Step 5: Grouped AR Tests -----------------------------------------------

# By state (UF)
states <- unique(dt$uf)  # need to ensure UF is in Panel B
grouped_results_state <- list()
FOR each state s:
  dt_s <- dt[uf == s]
  IF nrow(dt_s) > 200:  # minimum viable sample
    mod_s <- feols(formula_1, data = dt_s, vcov = ~muni_id)
    ar_s  <- fixest::wald(mod_s, keep = "^Z_")
    STORE: state = s, F = ar_s$stat, p = ar_s$p, N = nobs(mod_s)

# Apply Benjamini-Hochberg to 27 state p-values
p_vals_state <- sapply(grouped_results_state, \(x) x$p)
p_adj_state  <- p.adjust(p_vals_state, method = "BH")
REPORT: distribution of F-statistics (median, IQR, fraction above critical value)
REPORT: raw and BH-adjusted p-values

# By BNDES intensity quartile
dt[, bndes_quartile := ntile(mean_bndes_pc, 4), by = .(year)]
# (Or: quartile based on total BNDES per capita over the full period)
FOR each q in 1:4:
  dt_q <- dt[bndes_quartile == q]
  mod_q <- feols(formula_1, data = dt_q, vcov = ~muni_id)
  ar_q  <- fixest::wald(mod_q, keep = "^Z_")
  STORE: quartile = q, F, p, N

REPORT grouped results as table

# --- Step 6: Falsification Tests ---------------------------------------------

# F1: Transfers as LHS
IF "log_transfers_pc" in names(dt):
  mod_f1 <- feols(log_transfers_pc ~ Z_mayor_1 + ... | muni_id + year,
                  data = dt, vcov = ~muni_id)
  ar_f1 <- fixest::wald(mod_f1, keep = "^Z_")
  REPORT: "Transfers falsification: F = {F}, p = {p}"

# F2: Lead instruments (pre-trends)
# Shift Z columns forward by 4 years (one mayor cycle)
dt[, Z_mayor_1_lead4 := shift(Z_mayor_1, n = -4, type = "lag"), by = muni_id]
# ... for all sectors
mod_f2 <- feols(log_gdp_pc ~ Z_mayor_1_lead4 + ... | muni_id + year,
                data = dt, vcov = ~muni_id)
ar_f2 <- fixest::wald(mod_f2, keep = "^Z_.*lead")
REPORT: "Lead instruments: F = {F}, p = {p}"

# F3: Lagged GDP
dt[, log_gdp_pc_lag1 := shift(log_gdp_pc, n = 1), by = muni_id]
mod_f3 <- feols(log_gdp_pc_lag1 ~ Z_mayor_1 + ... | muni_id + year,
                data = dt, vcov = ~muni_id)
ar_f3 <- fixest::wald(mod_f3, keep = "^Z_")
REPORT: "Lagged GDP: F = {F}, p = {p}"

# F7: Pre-period balance test
# Construct pre-2005 municipality averages
dt_pre <- dt[year < 2005, .(
  mean_log_gdp_pc = mean(log_gdp_pc, na.rm = TRUE),
  mean_log_pop    = mean(log(population), na.rm = TRUE),
  mean_emp_share_agro  = mean(emp_share_agro, na.rm = TRUE),
  mean_emp_share_ind   = mean(emp_share_ind, na.rm = TRUE),
  mean_emp_share_infra = mean(emp_share_infra, na.rm = TRUE),
  mean_emp_share_cs    = mean(emp_share_cs, na.rm = TRUE)
), by = muni_id]

# Merge first-cycle instrument values (2005 or first non-zero year)
dt_z_first <- dt[year == 2005, .(muni_id, Z_mayor_1, Z_mayor_2, Z_mayor_3, Z_mayor_4)]
dt_balance <- merge(dt_pre, dt_z_first, by = "muni_id")

# Test: do instruments predict pre-treatment characteristics?
FOR each pre_var in {mean_log_gdp_pc, mean_log_pop, mean_emp_share_*}:
  mod_bal <- lm(pre_var ~ Z_mayor_1 + Z_mayor_2 + Z_mayor_3 + Z_mayor_4,
                data = dt_balance)
  f_bal <- linearHypothesis(mod_bal, names(coef(mod_bal))[-1])  # joint F
  STORE: variable, F, p
REPORT: "Pre-period balance: joint F and p for each baseline characteristic"

# --- Step 7: Summary Table --------------------------------------------------

COMPILE all results into a summary table:
  Columns: Specification, K (instruments), N (obs), Clusters, F_stat, p_value, Reject_5pct
  Rows: Primary specs (1-5), exposure control variant (1b), individual sectors,
        grouped tests, falsification, pre-period balance

SAVE summary to explorations/anderson_rubin/output/ar_summary.csv
SAVE LaTeX table to explorations/anderson_rubin/output/ar_summary.tex

# --- Step 8: Diagnostics ----------------------------------------------------

# Report within-R-squared (how much GDP variation remains after muni+year FE)
mod_fe_only <- feols(log_gdp_pc ~ 1 | muni_id + year, data = dt)
within_r2 <- 1 - sum(resid(mod_fe_only)^2) / sum((dt$log_gdp_pc - mean(dt$log_gdp_pc))^2)

# Report partial R-squared of instruments (correct computation)
# Partial R^2 = 1 - RSS_unrestricted / RSS_restricted
# where restricted = FE only, unrestricted = FE + instruments
partial_r2 <- 1 - sum(resid(mod_1)^2) / sum(resid(mod_fe_only)^2)

# Report number of municipalities with non-zero within-variation per instrument
FOR each z_col in z_cols_levels_mayor:
  dt_var <- dt[, .(has_var = var(get(z_col)) > 0), by = muni_id]
  n_contributing <- sum(dt_var$has_var, na.rm = TRUE)
  REPORT: "{z_col}: {n_contributing} / {N_munis} municipalities with variation"

REPORT: "Within R2 (FE only): {within_r2}"
REPORT: "Partial R2 (instruments | FE): {partial_r2}"
REPORT: "This partial R2 is the share of within-muni GDP variation explained by instruments"
REPORT: "Note: partial R2 will be mechanically limited because instruments are step functions"
REPORT: "      that change only at electoral cycle boundaries (~3-4 transitions per municipality)"
```

## Data Flow

```
Panel B (muni_panel_for_regs.qs2)
  |
  +-- [Already has]: log_gdp_pc, log_gdp, Z_* (wide), dZ_* (wide)
  |
  +-- [BLOCKER]:     Z and EC columns for bndes_sector (4 macros)
  |                  Currently has: sector_group (11) or cnae_section (21)
  |                  Must resolve before AR test can run:
  |                    -> Build from Panel A by collapsing Z within bndes_sector
  |                    -> Or add --sector-var=bndes_sector to script 41
  |
  +-- [May need]:    UF (state) for grouped analysis
  |                  -> Derive from muni_id (first 2 digits of IBGE code)
  |
  +-- [May need]:    transfers_pc for falsification
  |                  -> Merge from data/processed/transfers_ibge.qs2
  |
  +-- [May need]:    pre-period municipality characteristics for balance test
                     -> Compute from Panel B (pre-2005 averages)
```

## Output Files

```
explorations/anderson_rubin/
  output/
    ar_summary.csv           # All AR test results in machine-readable format
    ar_summary.tex           # LaTeX table of primary results
    ar_grouped_state.csv     # State-by-state AR results (raw + BH-adjusted p)
    ar_grouped_bndes_q.csv   # By BNDES quartile
    ar_falsification.csv     # Falsification test results
    ar_balance.csv           # Pre-period balance test results
    ar_diagnostics.txt       # R-squared, partial R-squared, sample diagnostics,
                             #   per-instrument contributing cluster counts
```
