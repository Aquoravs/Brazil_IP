# ============================================================================
# Audit A0.2 — Zero-employee firm prevalence in RAIS-covered firm-years
#
# Purpose : Quantify the prevalence and structure of zero-employee firm-years
#           in the reconstructed RAIS+BNDES panel (in_rais == TRUE). Provides
#           D2 evidence for the firm-support hybrid implementation plan
#           (journal/plans/2026-05-12_firm_support_hybrid_implementation.md).
#
# Inputs  : data/processed/rais_bndes_reconstructed.fst
#           data/processed/population_ibge.qs2
#
# Outputs : explorations/firm_universe/rais_coverage_audit/output/
#             zero_emp_by_year.csv
#             zero_emp_by_cnae_section.csv
#             zero_emp_by_pop_tercile.csv
#             zero_emp_by_establishment_type.csv
#             zero_emp_persistence.csv
#             zero_emp_transient.csv
#             zero_emp_overall_summary.csv
#
# Author  : data-engineer (orchestrated)
# Date    : 2026-05-12
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fst)
  library(qs2)
})

set.seed(2026)

# ---- Path bootstrap --------------------------------------------------------

script_path <- (function() {
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grep("^--file=", args)])
  if (length(f)) return(normalizePath(f[1], winslash = "/", mustWork = FALSE))
  normalizePath("audit_zero_employee.R", winslash = "/", mustWork = FALSE)
})()

# Find project root: walk up until scripts/R/ exists
find_root <- function(p) {
  p <- normalizePath(p, winslash = "/", mustWork = FALSE)
  if (!dir.exists(p)) p <- dirname(p)
  repeat {
    if (dir.exists(file.path(p, "scripts", "R"))) return(p)
    par <- dirname(p)
    if (identical(par, p)) stop("Project root not found from: ", script_path)
    p <- par
  }
}
PROJECT_ROOT <- find_root(script_path)

source(file.path(PROJECT_ROOT, "scripts", "R", "_utils", "utils.R"))

rais_path  <- output_path("rais_bndes_reconstructed.fst")
pop_path   <- output_path("population_ibge.qs2")
out_dir    <- project_path(
  "explorations", "firm_universe", "rais_coverage_audit", "output"
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ---- Preconditions ---------------------------------------------------------
stopifnot(
  "RAIS reconstructed panel not found" = file.exists(rais_path),
  "Population file not found"          = file.exists(pop_path)
)

log_info("Project root :", PROJECT_ROOT)
log_info("Output dir   :", out_dir)

# ---- Load -------------------------------------------------------------------

log_info("Reading RAIS reconstructed panel (fst)...")
cols <- c("firm_id", "muni_id", "year", "n_employees", "n_establishments",
          "cnae_section", "in_rais")
dt <- as.data.table(fst::read_fst(rais_path, columns = cols))

log_info("Read", format(nrow(dt), big.mark = ","), "firm-year rows")

# Restrict to RAIS-covered + years 2002-2017
dt <- dt[in_rais == TRUE & year >= 2002L & year <= 2017L]
log_info("After in_rais & 2002-2017 restriction:",
         format(nrow(dt), big.mark = ","), "rows")

# Coerce n_employees / n_establishments to integer for stable comparisons
dt[, n_employees := as.integer(n_employees)]
dt[, n_establishments := as.integer(n_establishments)]

# Flag zero-employee rows (treat NA as not zero, but log)
n_na_emp <- sum(is.na(dt$n_employees))
log_info("Firm-years with NA n_employees:", n_na_emp)
dt[, is_zero := !is.na(n_employees) & n_employees == 0L]

# ---- 1. By year ------------------------------------------------------------

by_year <- dt[, .(
  total_firm_years = .N,
  zero_emp_firm_years = sum(is_zero),
  zero_emp_share = sum(is_zero) / .N
), by = year][order(year)]

fwrite(by_year, file.path(out_dir, "zero_emp_by_year.csv"))
log_info("Wrote zero_emp_by_year.csv")

overall_rate <- sum(dt$is_zero) / nrow(dt)
overall_zero <- sum(dt$is_zero)
log_info(sprintf("Overall zero-emp rate: %.4f%% (%d / %d)",
                 100 * overall_rate, overall_zero, nrow(dt)))

# Empirical distribution of n_employees at the low end (sanity check on whether
# the panel might already exclude RAIS Negativa-equivalent rows).
emp_quantiles <- quantile(dt$n_employees,
                          probs = c(0, 0.0001, 0.001, 0.01, 0.05, 0.5, 0.95, 1),
                          na.rm = TRUE)
log_info("n_employees quantiles:")
print(emp_quantiles)
n_one_emp <- sum(dt$n_employees == 1L, na.rm = TRUE)
log_info(sprintf("Firm-years with n_employees == 1: %d (%.2f%%)",
                 n_one_emp, 100 * n_one_emp / nrow(dt)))

# ---- 2a. By CNAE section (within zero-emp) ---------------------------------

z <- dt[is_zero == TRUE]

by_cnae <- z[, .(
  zero_emp_firm_years = .N
), by = cnae_section][order(-zero_emp_firm_years)]
by_cnae[, share_of_zero_emp := zero_emp_firm_years / sum(zero_emp_firm_years)]

# Also compute denominator (total firm-years in each section) for rate
totals_cnae <- dt[, .(total_firm_years = .N), by = cnae_section]
by_cnae <- merge(by_cnae, totals_cnae, by = "cnae_section", all.x = TRUE)
by_cnae[, zero_emp_rate_within_section := zero_emp_firm_years / total_firm_years]
setorder(by_cnae, -zero_emp_firm_years)

fwrite(by_cnae, file.path(out_dir, "zero_emp_by_cnae_section.csv"))
log_info("Wrote zero_emp_by_cnae_section.csv")

# ---- 2b. By muni population tercile ----------------------------------------

log_info("Reading population data...")
pop <- qs2::qs_read(pop_path)
setDT(pop)
# RAIS muni_id is 6-digit (no verifier digit); pop muni_id_ibge is 7-digit char.
# Convert by truncating the trailing verifier digit.
pop[, muni_id_6dig := as.integer(substr(as.character(muni_id_ibge), 1, 6))]
dt[, muni_id_int := as.integer(muni_id)]

# Compute tercile from baseline year 2002 population (or earliest available)
pop_base <- pop[year == 2002, .(muni_id_int = muni_id_6dig, population)]
if (nrow(pop_base) == 0L) {
  pop_base <- pop[year == min(year), .(muni_id_int = muni_id, population)]
}
# In case duplicates: take first
pop_base <- unique(pop_base, by = "muni_id_int")

pop_base[, pop_tercile := cut(
  as.numeric(population),
  breaks = quantile(as.numeric(population),
                    probs = c(0, 1/3, 2/3, 1), na.rm = TRUE),
  labels = c("T1_small", "T2_mid", "T3_large"),
  include.lowest = TRUE
)]

dt <- merge(dt, pop_base[, .(muni_id_int, pop_tercile)],
            by = "muni_id_int", all.x = TRUE)

by_pop <- dt[, .(
  total_firm_years = .N,
  zero_emp_firm_years = sum(is_zero),
  zero_emp_rate = sum(is_zero) / .N
), by = pop_tercile][order(pop_tercile)]

fwrite(by_pop, file.path(out_dir, "zero_emp_by_pop_tercile.csv"))
log_info("Wrote zero_emp_by_pop_tercile.csv")

# ---- 2c. Single- vs multi-establishment CNPJ -------------------------------

dt[, estab_type := fifelse(
  is.na(n_establishments), "unknown",
  fifelse(n_establishments <= 1L, "single_estab", "multi_estab")
)]

by_estab <- dt[, .(
  total_firm_years = .N,
  zero_emp_firm_years = sum(is_zero),
  zero_emp_rate = sum(is_zero) / .N
), by = estab_type][order(estab_type)]

fwrite(by_estab, file.path(out_dir, "zero_emp_by_establishment_type.csv"))
log_info("Wrote zero_emp_by_establishment_type.csv")

# ---- 3. Persistence: >=3 consecutive zero years vs isolated zeros ----------

# Sort by firm and year; for each zero-emp row, determine length of the
# consecutive zero-run it belongs to.
setorder(dt, firm_id, year)
dt[, prev_year   := shift(year, type = "lag"),  by = firm_id]
dt[, prev_zero   := shift(is_zero, type = "lag"), by = firm_id]
dt[, gap_break   := is.na(prev_year) | (year - prev_year) != 1L |
                      is.na(prev_zero) | prev_zero != is_zero]
dt[, run_id      := cumsum(gap_break), by = firm_id]

# Compute run lengths only over zero runs
zero_runs <- dt[is_zero == TRUE,
                .(run_len = .N, run_first_year = min(year),
                  run_last_year = max(year)),
                by = .(firm_id, run_id)]

n_zero_total <- nrow(dt[is_zero == TRUE])
runs_ge3 <- zero_runs[run_len >= 3L]
runs_iso <- zero_runs[run_len == 1L]
runs_2   <- zero_runs[run_len == 2L]

zero_years_in_ge3 <- runs_ge3[, sum(run_len)]
zero_years_in_iso <- nrow(runs_iso)
zero_years_in_2   <- runs_2[, sum(run_len)]

persistence <- data.table(
  category = c("isolated_zero (run_len=1)",
               "two_consecutive (run_len=2)",
               "persistent_zero (run_len>=3)"),
  n_runs = c(nrow(runs_iso), nrow(runs_2), nrow(runs_ge3)),
  n_firm_years = c(zero_years_in_iso, zero_years_in_2, zero_years_in_ge3),
  share_of_zero_firm_years = c(
    zero_years_in_iso / n_zero_total,
    zero_years_in_2   / n_zero_total,
    zero_years_in_ge3 / n_zero_total
  )
)

fwrite(persistence, file.path(out_dir, "zero_emp_persistence.csv"))
log_info("Wrote zero_emp_persistence.csv")

# ---- 4. Transient: zero-year adjacent to positive-employment year ----------

dt[, next_emp := shift(n_employees, type = "lead"), by = firm_id]
dt[, prev_emp := shift(n_employees, type = "lag"),  by = firm_id]
dt[, next_year_adj := shift(year, type = "lead"), by = firm_id]
dt[, prev_year_adj := shift(year, type = "lag"),  by = firm_id]

dt[, adj_to_positive := is_zero == TRUE & (
  (!is.na(next_emp) & next_emp > 0L &
     !is.na(next_year_adj) & (next_year_adj - year) == 1L) |
  (!is.na(prev_emp) & prev_emp > 0L &
     !is.na(prev_year_adj) & (year - prev_year_adj) == 1L)
)]

n_transient <- sum(dt$adj_to_positive)

transient <- data.table(
  zero_firm_years_total = n_zero_total,
  transient_zero_firm_years = n_transient,
  transient_share_of_zero = n_transient / n_zero_total
)

fwrite(transient, file.path(out_dir, "zero_emp_transient.csv"))
log_info("Wrote zero_emp_transient.csv")

# ---- Overall summary -------------------------------------------------------

summary_dt <- data.table(
  metric = c(
    "total_rais_firm_years_2002_2017",
    "zero_employee_firm_years",
    "zero_employee_share_pct",
    "na_n_employees",
    "min_year", "max_year",
    "persistent_ge3_share_of_zero_pct",
    "isolated_share_of_zero_pct",
    "transient_adjacent_share_of_zero_pct",
    "escalation_threshold_lt_1pct_hit",
    "min_n_employees_observed",
    "n_employees_eq_1_count",
    "n_employees_eq_1_share_pct"
  ),
  value = c(
    nrow(dt),
    n_zero_total,
    round(100 * overall_rate, 4),
    n_na_emp,
    min(dt$year), max(dt$year),
    round(100 * zero_years_in_ge3 / n_zero_total, 2),
    round(100 * zero_years_in_iso / n_zero_total, 2),
    round(100 * n_transient / n_zero_total, 2),
    as.integer(overall_rate < 0.01),
    min(dt$n_employees, na.rm = TRUE),
    n_one_emp,
    round(100 * n_one_emp / nrow(dt), 2)
  )
)
fwrite(summary_dt, file.path(out_dir, "zero_emp_overall_summary.csv"))
log_info("Wrote zero_emp_overall_summary.csv")

message("\n==== A0.2 SUMMARY ====")
print(summary_dt)
message("\nBy year:"); print(by_year)
message("\nBy pop tercile:"); print(by_pop)
message("\nBy establishment type:"); print(by_estab)
message("\nPersistence:"); print(persistence)
message("\nTransient:"); print(transient)
message("\nTop CNAE sections by zero-emp count:"); print(head(by_cnae, 10))

log_info("A0.2 audit complete.")
