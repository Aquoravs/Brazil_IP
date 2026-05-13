#!/usr/bin/env Rscript

# ==============================================================================
# A0.3 — Contemporaneous-denominator viability audit
# ==============================================================================
# Purpose:
#   Quantify the cost of using the contemporaneous unbalanced RAIS firm universe
#   as the share denominator for the AR-test endogenous variable (per D2).
#
# Outputs (all under explorations/firm_universe/rais_coverage_audit/output/):
#   - contemp_denominator_by_year.csv      muni-year drop counts per variant
#   - contemp_denominator_thresholds.csv   share of muni-years <= {0,10,50,100}
#   - contemp_denominator_muni_dist.csv    distribution of drops across munis
#   - slack_series_by_year.csv             slack = frozen / contemporaneous
#   - slack_trend.pdf                      slack plot, serif, no in-figure title
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst (in_rais == TRUE rows)
#   data/processed/muni_employment_baselines.qs2 (frozen baseline, mayor cycles)
#
# Invariants: INV-14 (no RNG → no set.seed needed), INV-15, INV-16, INV-19.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fst)
  library(qs2)
  library(ggplot2)
})

setDTthreads(0)

# --- Paths --------------------------------------------------------------------

# Script lives at explorations/firm_universe/rais_coverage_audit/R/audit_*.R
# → repo root is four levels up.
script_args <- commandArgs(trailingOnly = FALSE)
file_arg    <- grep("^--file=", script_args, value = TRUE)
if (length(file_arg)) {
  script_path <- normalizePath(sub("^--file=", "", file_arg[1]),
                               winslash = "/", mustWork = TRUE)
  repo_root <- normalizePath(file.path(dirname(script_path),
                                       "..", "..", "..", ".."),
                             winslash = "/", mustWork = TRUE)
} else {
  repo_root <- normalizePath(getwd(), winslash = "/")
}

rais_path <- file.path(repo_root, "data", "processed", "rais_bndes_reconstructed.fst")
bl_path   <- file.path(repo_root, "data", "processed", "muni_employment_baselines.qs2")

out_dir   <- file.path(repo_root, "explorations", "firm_universe",
                       "rais_coverage_audit", "output")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# --- Preconditions ------------------------------------------------------------
stopifnot(
  "RAIS reconstructed panel not found"        = file.exists(rais_path),
  "Muni employment baselines file not found"  = file.exists(bl_path)
)

message("Audit A0.3 — Contemporaneous-denominator viability")
message("Repo root: ", repo_root)
message("Output dir: ", out_dir)

# --- Load RAIS-covered firm-years ---------------------------------------------

message("Loading RAIS reconstructed panel (in_rais == TRUE)...")
need_cols <- c("firm_id", "year", "muni_id", "n_employees", "in_rais")
rais <- as.data.table(read_fst(rais_path, columns = need_cols))
rais <- rais[in_rais == TRUE]
rais[, muni_id := as.integer(muni_id)]
rais[, year := as.integer(year)]
rais[is.na(n_employees), n_employees := 0]
rais <- rais[!is.na(muni_id) & muni_id > 0L & year >= 2002L & year <= 2017L]
message(sprintf("  Rows: %s", format(nrow(rais), big.mark = ",")))
message(sprintf("  Firms: %s | Munis: %d | Years: %d",
                format(uniqueN(rais$firm_id), big.mark = ","),
                uniqueN(rais$muni_id), uniqueN(rais$year)))

all_munis <- sort(unique(rais$muni_id))
all_years <- 2002L:2017L

# --- Variant A: contemporaneous unbalanced ------------------------------------

message("\nVariant A — contemporaneous unbalanced...")
muni_yr_A <- rais[, .(n_mt = sum(n_employees, na.rm = TRUE)),
                  by = .(muni_id, year)]

# Complete to full 5,570 munis × 16 years skeleton (zero-fill missing cells)
skel <- CJ(muni_id = all_munis, year = all_years)
muni_yr_A <- muni_yr_A[skel, on = .(muni_id, year)]
muni_yr_A[is.na(n_mt), n_mt := 0]

# --- Variant B: frozen pre-election baseline (mayor cycles) -------------------

message("Variant B — frozen pre-election baseline (mayor)...")
bl <- as.data.table(qs_read(bl_path))
bl <- bl[office_tier == "mayor"]

# Map each calendar year t to its mayor election_cycle's baseline window
# Mayor cycles: 2005 (yrs 2002-2004), 2009 (yrs 2005-2008), 2013 (yrs 2009-2012),
# 2017 (yrs 2013-2016). Year 2017 → next cycle 2021 (out); reuse 2017 cycle.
# We need: for each year t in 2002-2017, identify the firms "frozen" in window.
# Frozen-baseline firm SET = firms active in [e(t)-4, e(t)-1].

cycle_for_year <- function(t) {
  fcase(
    t >= 2002L & t <= 2004L, 2005L,
    t >= 2005L & t <= 2008L, 2009L,
    t >= 2009L & t <= 2012L, 2013L,
    t >= 2013L & t <= 2017L, 2017L
  )
}
window_for_cycle <- function(ec) {
  fcase(
    ec == 2005L, list(c(2000L, 2003L)),
    ec == 2009L, list(c(2004L, 2007L)),
    ec == 2013L, list(c(2008L, 2011L)),
    ec == 2017L, list(c(2012L, 2015L))
  )
}

# Build firm sets per cycle: firms with any RAIS presence in window
cycles <- c(2005L, 2009L, 2013L, 2017L)
frozen_firms <- list()
for (ec in cycles) {
  w <- window_for_cycle(ec)[[1]]
  w_start <- max(w[1], 2002L); w_end <- w[2]
  frozen_firms[[as.character(ec)]] <- unique(
    rais[year >= w_start & year <= w_end, firm_id]
  )
  message(sprintf("  Cycle %d window [%d,%d]: %s frozen firms",
                  ec, w_start, w_end,
                  format(length(frozen_firms[[as.character(ec)]]), big.mark = ",")))
}

# For variant B, restrict contemp-year rows to firms in their cycle's frozen set
rais[, cycle := cycle_for_year(year)]
build_B <- function(yr) {
  ec <- cycle_for_year(yr)
  fs <- frozen_firms[[as.character(ec)]]
  rais[year == yr & firm_id %in% fs,
       .(n_mt_B = sum(n_employees, na.rm = TRUE)),
       by = muni_id]
}
muni_yr_B <- rbindlist(lapply(all_years, function(yr) {
  d <- build_B(yr); d[, year := yr]; d
}), use.names = TRUE, fill = TRUE)
muni_yr_B <- muni_yr_B[skel, on = .(muni_id, year)]
muni_yr_B[is.na(n_mt_B), n_mt_B := 0]

# --- Variant C: balanced (in window AND every post-election year) -------------

message("Variant C — balanced (frozen + present every post-election year)...")
# Post-election years for each mayor cycle: e(t), e(t)+1, e(t)+2, e(t)+3
post_years_for_cycle <- function(ec) {
  fcase(
    ec == 2005L, list(2005L:2008L),
    ec == 2009L, list(2009L:2012L),
    ec == 2013L, list(2013L:2016L),
    ec == 2017L, list(2017L:2017L)  # only 2017 observed
  )
}
balanced_firms <- list()
for (ec in cycles) {
  fs <- frozen_firms[[as.character(ec)]]
  py <- post_years_for_cycle(ec)[[1]]
  # firms present every post-year
  presence <- rais[firm_id %in% fs & year %in% py,
                   .(n_yrs = uniqueN(year)), by = firm_id]
  bal <- presence[n_yrs == length(py), firm_id]
  balanced_firms[[as.character(ec)]] <- bal
  message(sprintf("  Cycle %d post-yrs (%s): %s balanced firms (of %s frozen)",
                  ec, paste(range(py), collapse = "-"),
                  format(length(bal), big.mark = ","),
                  format(length(fs), big.mark = ",")))
}
build_C <- function(yr) {
  ec <- cycle_for_year(yr)
  fs <- balanced_firms[[as.character(ec)]]
  rais[year == yr & firm_id %in% fs,
       .(n_mt_C = sum(n_employees, na.rm = TRUE)),
       by = muni_id]
}
muni_yr_C <- rbindlist(lapply(all_years, function(yr) {
  d <- build_C(yr); d[, year := yr]; d
}), use.names = TRUE, fill = TRUE)
muni_yr_C <- muni_yr_C[skel, on = .(muni_id, year)]
muni_yr_C[is.na(n_mt_C), n_mt_C := 0]

# --- Merge all variants -------------------------------------------------------

panel <- muni_yr_A[muni_yr_B, on = .(muni_id, year)]
panel <- panel[muni_yr_C, on = .(muni_id, year)]
panel[is.na(n_mt), n_mt := 0]
panel[is.na(n_mt_B), n_mt_B := 0]
panel[is.na(n_mt_C), n_mt_C := 0]

# --- 1) Drop counts by year and variant ---------------------------------------

message("\nDrop counts by year (n_mt == 0)...")
by_year <- panel[, .(
  n_munis        = .N,
  zero_A         = sum(n_mt == 0),
  zero_B         = sum(n_mt_B == 0),
  zero_C         = sum(n_mt_C == 0),
  le10_A         = sum(n_mt <= 10),
  le50_A         = sum(n_mt <= 50),
  le100_A        = sum(n_mt <= 100),
  mean_A         = mean(n_mt),
  median_A       = as.numeric(median(n_mt))
), by = year][order(year)]

fwrite(by_year, file.path(out_dir, "contemp_denominator_by_year.csv"))

# --- 2) Threshold table (overall) ---------------------------------------------

total_my <- nrow(panel)
thresholds <- data.table(
  variant   = c(rep("A_contemporaneous", 4), "B_frozen", "C_balanced"),
  threshold = c("zero", "le10", "le50", "le100", "zero", "zero"),
  count     = c(sum(panel$n_mt == 0),
                sum(panel$n_mt <= 10),
                sum(panel$n_mt <= 50),
                sum(panel$n_mt <= 100),
                sum(panel$n_mt_B == 0),
                sum(panel$n_mt_C == 0)),
  total_muni_years = total_my
)
thresholds[, pct := 100 * count / total_muni_years]
fwrite(thresholds, file.path(out_dir, "contemp_denominator_thresholds.csv"))

message(sprintf("  Total muni-years: %s", format(total_my, big.mark = ",")))
print(thresholds)

# --- 3) Distribution across munis (variant A) ---------------------------------

message("\nMuni-level: how many years each muni hits n_mt == 0 (variant A)...")
muni_dist <- panel[, .(n_zero_years = sum(n_mt == 0)), by = muni_id]
muni_dist_tab <- muni_dist[, .(n_munis = .N), by = n_zero_years][order(n_zero_years)]
fwrite(muni_dist_tab, file.path(out_dir, "contemp_denominator_muni_dist.csv"))
message(sprintf("  Munis with >=1 zero year: %d", sum(muni_dist$n_zero_years > 0)))
message(sprintf("  Munis with all 16 zero: %d",  sum(muni_dist$n_zero_years == 16)))

# --- 4) Slack series ----------------------------------------------------------

message("\nSlack = frozen / contemporaneous, by year...")
slack <- panel[n_mt > 0, .(
  n_obs        = .N,
  total_A      = sum(n_mt),
  total_B      = sum(n_mt_B),
  slack_agg    = sum(n_mt_B) / sum(n_mt),
  slack_mean   = mean(pmin(n_mt_B / n_mt, 1.0)),
  slack_median = as.numeric(median(pmin(n_mt_B / n_mt, 1.0)))
), by = year][order(year)]
fwrite(slack, file.path(out_dir, "slack_series_by_year.csv"))
print(slack[, .(year, slack_agg, slack_median)])

# --- 5) Plot: slack trend -----------------------------------------------------

p <- ggplot(slack, aes(x = year)) +
  geom_line(aes(y = slack_agg, linetype = "Aggregate"), linewidth = 0.7) +
  geom_point(aes(y = slack_agg, shape = "Aggregate"), size = 2) +
  geom_line(aes(y = slack_median, linetype = "Median across munis"),
            linewidth = 0.7) +
  geom_point(aes(y = slack_median, shape = "Median across munis"), size = 2) +
  scale_x_continuous(breaks = 2002:2017) +
  scale_y_continuous(limits = c(0, 1.0),
                     breaks = seq(0, 1, by = 0.2),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_linetype_manual(values = c("Aggregate" = "solid",
                                   "Median across munis" = "dashed")) +
  scale_shape_manual(values = c("Aggregate" = 16,
                                "Median across munis" = 17)) +
  labs(x = "Year",
       y = "Frozen-baseline share of contemporaneous employment",
       linetype = NULL, shape = NULL,
       title = NULL, subtitle = NULL) +
  theme_minimal(base_family = "serif", base_size = 12) +
  theme(legend.position = "bottom",
        legend.direction = "horizontal",
        panel.grid.minor = element_blank())

ggsave(file.path(out_dir, "slack_trend.pdf"), p,
       width = 7, height = 4.2, device = cairo_pdf)

message(sprintf("\nDone. Outputs in: %s", out_dir))
