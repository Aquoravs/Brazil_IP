# ==============================================================================
# Explore: Political Affiliation Data Diagnostics
# ==============================================================================
#
# Runs start-to-end. Prints summaries to console and saves CSV tables to
# output/diagnostics/explore_affiliation/.
#
# Data sources:
#   1. output/rais_bndes_reconstructed.fst  (firm x muni x year)
#   2. raw/david_ra/owner_aff_firm_year_party_2002_2019.parquet  (firm x year x party)
#
# See: docs/brainstorms/2026-03-15-affiliation-data-diagnostics-brainstorm.md
# ==============================================================================

# Bootstrap using the standard pattern (auto-discovers project root)
bootstrap_file <- file.path(dirname(sys.frame(1)$ofile %||% "."), "..", "_utils", "script_bootstrap.R")
source(normalizePath(bootstrap_file, winslash = "/", mustWork = TRUE))
bootstrap_politicsregs()

suppressPackageStartupMessages({
  library(data.table)
  library(fst)
  library(DBI)
  library(duckdb)
})

# Output directory
OUT_DIR <- make_output_path("diagnostics/explore_affiliation")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

save_csv <- function(dt, name) {
  path <- file.path(OUT_DIR, paste0(name, ".csv"))
  fwrite(dt, path)
  cat("  -> Saved:", path, "\n")
}


# ===========================================================================
# Preamble: Setup DuckDB + Load Panel
# ===========================================================================

cat("\n===== Loading Data =====\n\n")

con <- dbConnect(duckdb())

parquet_path <- normalizePath(
  make_base_path("raw/david_ra/owner_aff_firm_year_party_2002_2019.parquet"),
  winslash = "/", mustWork = TRUE
)
pq_cols <- names(dbGetQuery(con, sprintf("SELECT * FROM '%s' LIMIT 0", parquet_path)))
cat("Parquet columns:", paste(pq_cols, collapse = ", "), "\n")

fid_col <- intersect(c("firm_id", "cnpj", "cnpj_raiz"), pq_cols)[1]
yr_col  <- intersect(c("year", "ano"), pq_cols)[1]
pty_col <- intersect(c("party", "sigla_partido"), pq_cols)[1]
aff_col <- intersect(c("aff_owners", "n_aff_owners"), pq_cols)[1]
shr_col <- intersect(c("share_aff_owners", "share_aff"), pq_cols)[1]
cat(sprintf("  Mapped: firm_id=%s, year=%s, party=%s, aff_count=%s, share=%s\n",
            fid_col, yr_col, pty_col, aff_col, shr_col))

dbExecute(con, sprintf("
  CREATE VIEW aff AS
  SELECT
    CAST(%s AS INTEGER) AS firm_id,
    CAST(%s AS INTEGER) AS year,
    TRIM(%s) AS party,
    CAST(%s AS INTEGER) AS aff_count,
    CAST(%s AS DOUBLE)  AS share_aff
  FROM '%s'
  WHERE CAST(%s AS INTEGER) BETWEEN 2002 AND 2017
", fid_col, yr_col, pty_col, aff_col, shr_col, parquet_path, yr_col))

dbExecute(con, "
  CREATE VIEW aff_party AS
  SELECT * FROM aff
  WHERE party NOT IN ('No party', 'Sem partido', 'SEM PARTIDO', '')
    AND aff_count > 0
")
cat("DuckDB views created\n\n")

# Panel (column-selective fst)
panel_path <- make_output_path("rais_bndes_reconstructed.fst")
panel <- setDT(read_fst(panel_path, columns = c(
  "firm_id", "muni_id", "year", "cnae_section", "n_employees"
)))
panel[, firm_id := as.integer(firm_id)]
panel[, muni_id := as.integer(muni_id)]
panel[, year := as.integer(year)]
panel <- panel[year >= 2002L & year <= 2017L]

cat("Panel:", format(nrow(panel), big.mark = ","), "rows,",
    format(uniqueN(panel$firm_id), big.mark = ","), "firms,",
    min(panel$year), "-", max(panel$year), "\n")

panel_univ <- unique(panel[, .(firm_id, year)])
dbWriteTable(con, "panel_universe", panel_univ, overwrite = TRUE)
cat("Panel universe registered:", format(nrow(panel_univ), big.mark = ","), "firm-years\n\n")


# ===========================================================================
# Section 1: Affiliation Rates by Year
# ===========================================================================

cat("===== Section 1: Affiliation Rates by Year =====\n\n")

rates <- setDT(dbGetQuery(con, "
  SELECT
    u.year,
    COUNT(DISTINCT u.firm_id) AS n_firms,
    COUNT(DISTINCT a.firm_id) AS n_affiliated,
    ROUND(100.0 * COUNT(DISTINCT a.firm_id) / COUNT(DISTINCT u.firm_id), 1) AS pct_affiliated
  FROM panel_universe u
  LEFT JOIN (SELECT DISTINCT firm_id, year FROM aff_party) a
    USING (firm_id, year)
  GROUP BY u.year
  ORDER BY u.year
"))
print(rates)
save_csv(rates, "1_affiliation_rates_by_year")

share_quantiles <- setDT(dbGetQuery(con, "
  WITH total_est AS (
    SELECT firm_id, year, aff_count,
           CASE WHEN share_aff > 0 THEN aff_count / share_aff ELSE NULL END AS est
    FROM aff
    WHERE aff_count > 0
  ),
  firm_totals AS (
    SELECT firm_id, year,
           GREATEST(MEDIAN(est), SUM(aff_count)) AS total_owners
    FROM total_est
    WHERE est IS NOT NULL
    GROUP BY firm_id, year
  ),
  affiliated_counts AS (
    SELECT firm_id, year, SUM(aff_count) AS total_affiliated
    FROM aff_party
    GROUP BY firm_id, year
  ),
  shares AS (
    SELECT a.year,
           a.total_affiliated * 1.0 / t.total_owners AS share_affiliated
    FROM affiliated_counts a
    JOIN firm_totals t USING (firm_id, year)
    WHERE t.total_owners > 0
  )
  SELECT year,
    ROUND(QUANTILE_CONT(share_affiliated, 0.10), 3) AS p10,
    ROUND(QUANTILE_CONT(share_affiliated, 0.25), 3) AS p25,
    ROUND(QUANTILE_CONT(share_affiliated, 0.50), 3) AS p50,
    ROUND(QUANTILE_CONT(share_affiliated, 0.75), 3) AS p75,
    ROUND(QUANTILE_CONT(share_affiliated, 0.90), 3) AS p90
  FROM shares
  GROUP BY year
  ORDER BY year
"))
cat("\nConditional share of affiliated owners (quantiles):\n")
print(share_quantiles)
save_csv(share_quantiles, "1_affiliation_share_quantiles")


# ===========================================================================
# Section 2: Firm Entry and Exit
# ===========================================================================

cat("\n===== Section 2: Firm Entry and Exit =====\n\n")

firm_span <- panel[, .(
  first_year = min(year),
  last_year  = max(year),
  n_years    = uniqueN(year)
), by = firm_id]
n_total_firms <- nrow(firm_span)

entry_dist <- firm_span[, .(n_firms = .N), by = first_year]
setorder(entry_dist, first_year)
cat("Entry distribution:\n")
print(entry_dist)
save_csv(entry_dist, "2_entry_distribution")

exit_dist <- firm_span[, .(n_firms = .N), by = last_year]
setorder(exit_dist, last_year)
cat("\nExit distribution:\n")
print(exit_dist)
save_csv(exit_dist, "2_exit_distribution")

n_full <- firm_span[first_year == 2002L & last_year == 2017L, .N]
cat(sprintf("\nFull-period firms (2002 & 2017): %s (%.1f%%)\n",
            format(n_full, big.mark = ","),
            100 * n_full / n_total_firms))

firm_span[, duration_bin := fcase(
  n_years == 1L,  "1 year",
  n_years <= 5L,  "2-5 years",
  n_years <= 10L, "6-10 years",
  n_years <= 15L, "11-15 years",
  n_years == 16L, "16 (full)"
)]
firm_span[, duration_bin := factor(duration_bin,
  levels = c("1 year", "2-5 years", "6-10 years", "11-15 years", "16 (full)")
)]
duration_dist <- firm_span[, .(n_firms = .N), by = duration_bin]
duration_dist[, pct := round(100 * n_firms / n_total_firms, 1)]
setorder(duration_dist, duration_bin)
cat("\nDuration distribution:\n")
print(duration_dist)
save_csv(duration_dist, "2_duration_distribution")


# ===========================================================================
# Section 3: Party Stability
# ===========================================================================

cat("\n===== Section 3: Party Stability =====\n\n")

# 3a. Distinct parties per firm (lifetime)
party_counts <- setDT(dbGetQuery(con, "
  SELECT
    CASE
      WHEN n_parties = 1 THEN '1'
      WHEN n_parties = 2 THEN '2'
      WHEN n_parties = 3 THEN '3'
      WHEN n_parties = 4 THEN '4'
      ELSE '5+'
    END AS party_bin,
    COUNT(*) AS n_firms
  FROM (
    SELECT firm_id, COUNT(DISTINCT party) AS n_parties
    FROM aff_party GROUP BY firm_id
  )
  GROUP BY party_bin
  ORDER BY party_bin
"))
party_counts[, pct := round(100 * n_firms / sum(n_firms), 1)]
cat("Distinct parties per firm (lifetime):\n")
print(party_counts)
save_csv(party_counts, "3a_parties_per_firm")

# 3b. Parties per firm per year
fy_party_stats <- setDT(dbGetQuery(con, "
  WITH per_fy AS (
    SELECT firm_id, year, COUNT(DISTINCT party) AS n_parties
    FROM aff_party GROUP BY firm_id, year
  ),
  per_firm AS (
    SELECT firm_id,
           MEDIAN(n_parties) AS median_parties,
           MAX(n_parties) AS max_parties
    FROM per_fy GROUP BY firm_id
  )
  SELECT
    ROUND(MEDIAN(median_parties), 2) AS median_of_medians,
    ROUND(100.0 * SUM(CASE WHEN max_parties = 1 THEN 1 ELSE 0 END) / COUNT(*), 1)
      AS pct_always_one_party
  FROM per_firm
"))
cat(sprintf("\nWithin-year party count: median=%.2f, always-one-party=%.1f%%\n",
            fy_party_stats$median_of_medians, fy_party_stats$pct_always_one_party))

# 3c. Dominant party switches
switch_dist <- setDT(dbGetQuery(con, "
  WITH ranked AS (
    SELECT firm_id, year, party, aff_count,
           ROW_NUMBER() OVER (PARTITION BY firm_id, year
                              ORDER BY aff_count DESC, party ASC) AS rn
    FROM aff_party
  ),
  dominant AS (
    SELECT firm_id, year, party AS dominant_party
    FROM ranked WHERE rn = 1
  ),
  with_lag AS (
    SELECT firm_id, year, dominant_party,
           LAG(dominant_party) OVER (PARTITION BY firm_id ORDER BY year) AS prev_party
    FROM dominant
  ),
  switches AS (
    SELECT firm_id,
           SUM(CASE WHEN prev_party IS NOT NULL AND dominant_party != prev_party
                    THEN 1 ELSE 0 END) AS n_switches
    FROM with_lag GROUP BY firm_id
  )
  SELECT
    CASE
      WHEN n_switches = 0 THEN '0 switches'
      WHEN n_switches = 1 THEN '1 switch'
      WHEN n_switches = 2 THEN '2 switches'
      ELSE '3+ switches'
    END AS switch_bin,
    COUNT(*) AS n_firms
  FROM switches
  GROUP BY switch_bin
  ORDER BY switch_bin
"))
switch_dist[, pct := round(100 * n_firms / sum(n_firms), 1)]
cat("\nDominant party switches:\n")
print(switch_dist)
save_csv(switch_dist, "3c_dominant_party_switches")

# 3d. Baseline stability
baseline_stability <- dbGetQuery(con, "
  WITH ranked AS (
    SELECT firm_id, year, party,
           ROW_NUMBER() OVER (PARTITION BY firm_id, year
                              ORDER BY aff_count DESC, party ASC) AS rn
    FROM aff_party
  ),
  dominant AS (
    SELECT firm_id, year, party AS dominant_party
    FROM ranked WHERE rn = 1
  ),
  baseline AS (
    SELECT firm_id, dominant_party AS baseline_party
    FROM (
      SELECT firm_id, dominant_party,
             ROW_NUMBER() OVER (PARTITION BY firm_id ORDER BY year) AS rn
      FROM dominant
    ) WHERE rn = 1
  ),
  modal AS (
    SELECT firm_id, dominant_party AS modal_party
    FROM (
      SELECT firm_id, dominant_party, COUNT(*) AS cnt,
             ROW_NUMBER() OVER (PARTITION BY firm_id
                                ORDER BY COUNT(*) DESC, dominant_party ASC) AS rn
      FROM dominant GROUP BY firm_id, dominant_party
    ) WHERE rn = 1
  )
  SELECT
    COUNT(*) AS n_firms,
    ROUND(100.0 * SUM(CASE WHEN b.baseline_party = m.modal_party THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS pct_match
  FROM baseline b JOIN modal m USING (firm_id)
")
cat(sprintf("\nBaseline = lifetime modal: %.1f%% of %s firms\n",
            baseline_stability$pct_match,
            format(baseline_stability$n_firms, big.mark = ",")))


# ===========================================================================
# Section 4: Temporal Gaps in Firm Presence
# ===========================================================================

cat("\n===== Section 4: Temporal Gaps =====\n\n")

firm_years <- unique(panel[, .(firm_id, year)])
setorder(firm_years, firm_id, year)
firm_years[, year_diff := year - shift(year, 1L, type = "lag"), by = firm_id]

gaps <- firm_years[!is.na(year_diff) & year_diff > 1L]
gaps[, gap_length := year_diff - 1L]

n_firms_total    <- uniqueN(firm_years$firm_id)
n_firms_with_gap <- uniqueN(gaps$firm_id)
cat(sprintf("Firms with gaps: %s (%.1f%% of %s)\n",
            format(n_firms_with_gap, big.mark = ","),
            100 * n_firms_with_gap / n_firms_total,
            format(n_firms_total, big.mark = ",")))
cat("Total gaps:", format(nrow(gaps), big.mark = ","), "\n")

gaps[, gap_bin := fcase(
  gap_length == 1L,  "1 year",
  gap_length == 2L,  "2 years",
  gap_length == 3L,  "3 years",
  gap_length <= 5L,  "4-5 years",
  gap_length <= 10L, "6-10 years",
  gap_length > 10L,  "10+ years"
)]
gaps[, gap_bin := factor(gap_bin,
  levels = c("1 year", "2 years", "3 years", "4-5 years", "6-10 years", "10+ years")
)]
gap_dist <- gaps[, .(n_gaps = .N), by = gap_bin]
gap_dist[, pct := round(100 * n_gaps / sum(n_gaps), 1)]
setorder(gap_dist, gap_bin)
cat("\nGap length distribution:\n")
print(gap_dist)
save_csv(gap_dist, "4_gap_length_distribution")

# Cross-check: affiliation data during gap years
# Expand each gap row into the missing firm-year pairs
gap_years <- gaps[, .(missing_year = seq.int(year - gap_length + 1L, year - 1L)),
                  by = .(firm_id, year, gap_length)]

if (nrow(gap_years) > 0L) {
  dbExecute(con, "DROP TABLE IF EXISTS gap_firmyears")
  dbWriteTable(con, "gap_firmyears", gap_years[, .(firm_id, year = missing_year)])

  gap_cross <- dbGetQuery(con, "
    SELECT
      COUNT(*) AS n_gap_firmyears,
      SUM(CASE WHEN a.firm_id IS NOT NULL THEN 1 ELSE 0 END) AS n_with_aff,
      ROUND(100.0 * SUM(CASE WHEN a.firm_id IS NOT NULL THEN 1 ELSE 0 END)
            / COUNT(*), 1) AS pct_with_aff
    FROM gap_firmyears g
    LEFT JOIN (SELECT DISTINCT firm_id, year FROM aff_party) a
      USING (firm_id, year)
  ")
  cat(sprintf("\nGap-year firm-years: %s, with affiliation: %s (%.1f%%)\n",
              format(gap_cross$n_gap_firmyears, big.mark = ","),
              format(gap_cross$n_with_aff, big.mark = ","),
              gap_cross$pct_with_aff))
}


# ===========================================================================
# Section 4b: Affiliation Stability Across Gaps
# ===========================================================================

cat("\n===== Section 4b: Affiliation Stability Across Gaps =====\n\n")

# For firms with gaps: does the dominant party change before vs. after the gap?
# "before" = last year before gap; "after" = first year after gap
# We need: (firm_id, year_before_gap, year_after_gap) then query affiliation

gap_edges <- gaps[, .(firm_id,
                       year_before = year - gap_length,
                       year_after  = year)]

dbExecute(con, "DROP TABLE IF EXISTS gap_edges")
dbWriteTable(con, "gap_edges", gap_edges)

gap_aff_change <- setDT(dbGetQuery(con, "
  WITH ranked_before AS (
    SELECT g.firm_id, g.year_before, g.year_after,
           a.party, a.aff_count,
           ROW_NUMBER() OVER (PARTITION BY g.firm_id, g.year_before
                              ORDER BY a.aff_count DESC, a.party ASC) AS rn
    FROM gap_edges g
    JOIN aff_party a ON g.firm_id = a.firm_id AND g.year_before = a.year
  ),
  ranked_after AS (
    SELECT g.firm_id, g.year_before, g.year_after,
           a.party, a.aff_count,
           ROW_NUMBER() OVER (PARTITION BY g.firm_id, g.year_after
                              ORDER BY a.aff_count DESC, a.party ASC) AS rn
    FROM gap_edges g
    JOIN aff_party a ON g.firm_id = a.firm_id AND g.year_after = a.year
  ),
  pairs AS (
    SELECT b.firm_id, b.year_before, b.year_after,
           b.party AS party_before, a.party AS party_after,
           (b.year_after - b.year_before - 1) AS gap_length
    FROM ranked_before b
    JOIN ranked_after a ON b.firm_id = a.firm_id
                       AND b.year_before = a.year_before
                       AND b.year_after = a.year_after
                       AND b.rn = 1 AND a.rn = 1
  )
  SELECT
    CASE
      WHEN gap_length = 1 THEN '1 year'
      WHEN gap_length = 2 THEN '2 years'
      WHEN gap_length = 3 THEN '3 years'
      WHEN gap_length <= 5 THEN '4-5 years'
      WHEN gap_length <= 10 THEN '6-10 years'
      ELSE '10+ years'
    END AS gap_bin,
    COUNT(*) AS n_gaps,
    SUM(CASE WHEN party_before = party_after THEN 1 ELSE 0 END) AS n_same,
    ROUND(100.0 * SUM(CASE WHEN party_before = party_after THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS pct_same
  FROM pairs
  GROUP BY gap_bin
  ORDER BY gap_bin
"))

cat("Dominant party stability across RAIS gaps\n")
cat("(% of gaps where dominant party is the same before and after):\n\n")
print(gap_aff_change)
save_csv(gap_aff_change, "4b_affiliation_stability_across_gaps")

# Overall stability
total_gaps_with_aff <- sum(gap_aff_change$n_gaps)
total_same <- sum(gap_aff_change$n_same)
cat(sprintf("\nOverall: %s gaps with affiliation on both sides, %.1f%% same party\n",
            format(total_gaps_with_aff, big.mark = ","),
            100 * total_same / total_gaps_with_aff))

# Size characterization of gapped firms
gap_firm_ids <- unique(gaps$firm_id)
gap_firm_size <- panel[firm_id %in% gap_firm_ids,
                       .(median_emp = median(n_employees, na.rm = TRUE)),
                       by = firm_id]
nongap_firm_size <- panel[!firm_id %in% gap_firm_ids,
                          .(median_emp = median(n_employees, na.rm = TRUE)),
                          by = firm_id]
cat(sprintf("\nFirm size (median employees): gapped=%.0f, non-gapped=%.0f\n",
            median(gap_firm_size$median_emp, na.rm = TRUE),
            median(nongap_firm_size$median_emp, na.rm = TRUE)))


# ===========================================================================
# Section 6: Baseline Year Exogeneity Diagnostics
# ===========================================================================

cat("\n===== Section 6: Baseline Year Analysis =====\n\n")

# For each candidate baseline year, compute:
# (a) How many firms have affiliation data
# (b) How stable that baseline is relative to subsequent years
# (c) Whether affiliation in that year predicts future affiliation changes
#     (a truly exogenous baseline should not predict future switches)

# 6a. Coverage by year: firms with affiliation data in each year
coverage <- setDT(dbGetQuery(con, "
  SELECT year,
         COUNT(DISTINCT firm_id) AS n_firms_with_aff,
         SUM(aff_count) AS total_affiliated_owners
  FROM aff_party
  GROUP BY year
  ORDER BY year
"))
cat("6a. Affiliation coverage by year:\n")
print(coverage)
save_csv(coverage, "6a_affiliation_coverage_by_year")

# 6b. Baseline persistence: for each baseline year, what % of firms still
#     have the same dominant party 1, 2, 4, 8 years later?
persistence <- setDT(dbGetQuery(con, "
  WITH ranked AS (
    SELECT firm_id, year, party,
           ROW_NUMBER() OVER (PARTITION BY firm_id, year
                              ORDER BY aff_count DESC, party ASC) AS rn
    FROM aff_party
  ),
  dominant AS (
    SELECT firm_id, year, party AS dom_party
    FROM ranked WHERE rn = 1
  )
  SELECT
    b.year AS baseline_year,
    f.year AS future_year,
    (f.year - b.year) AS horizon,
    COUNT(*) AS n_firms,
    ROUND(100.0 * SUM(CASE WHEN b.dom_party = f.dom_party THEN 1 ELSE 0 END)
          / COUNT(*), 1) AS pct_same
  FROM dominant b
  JOIN dominant f ON b.firm_id = f.firm_id
                 AND f.year - b.year IN (1, 2, 4, 8)
  WHERE b.year BETWEEN 2002 AND 2013
  GROUP BY b.year, f.year
  ORDER BY b.year, f.year
"))

cat("\n6b. Baseline persistence (% same dominant party at horizon):\n\n")

# Pivot to wide format for readability
persistence_wide <- dcast(persistence, baseline_year ~ horizon,
                          value.var = "pct_same")
setnames(persistence_wide, c("1", "2", "4", "8"),
         c("h1_pct", "h2_pct", "h4_pct", "h8_pct"), skip_absent = TRUE)
print(persistence_wide)
save_csv(persistence_wide, "6b_baseline_persistence")

# 6c. Electoral cycle alignment
# Show which baseline years are "pre-treatment" for each tier
cat("\n6c. Electoral cycle baseline mapping:\n")
cycle_map <- data.table(
  tier = c(rep("mayor", 4), rep("gov_pres", 4)),
  treatment_year = c(2005, 2009, 2013, 2017, 2003, 2007, 2011, 2015),
  cycle_baseline = c(2003, 2007, 2011, 2015, 2002, 2005, 2009, 2013),
  fixed_baseline = rep(2002L, 8)
)
print(cycle_map)
save_csv(cycle_map, "6c_electoral_cycle_baselines")

# 6d. Affiliation changes around elections: do firms switch parties
# disproportionately in election years vs. non-election years?
switch_by_year <- setDT(dbGetQuery(con, "
  WITH ranked AS (
    SELECT firm_id, year, party,
           ROW_NUMBER() OVER (PARTITION BY firm_id, year
                              ORDER BY aff_count DESC, party ASC) AS rn
    FROM aff_party
  ),
  dominant AS (
    SELECT firm_id, year, party AS dom_party
    FROM ranked WHERE rn = 1
  ),
  with_lag AS (
    SELECT firm_id, year, dom_party,
           LAG(dom_party) OVER (PARTITION BY firm_id ORDER BY year) AS prev_party
    FROM dominant
  )
  SELECT year,
    COUNT(*) AS n_firms,
    SUM(CASE WHEN prev_party IS NOT NULL AND dom_party != prev_party
             THEN 1 ELSE 0 END) AS n_switches,
    ROUND(100.0 * SUM(CASE WHEN prev_party IS NOT NULL AND dom_party != prev_party
                            THEN 1 ELSE 0 END)
          / NULLIF(SUM(CASE WHEN prev_party IS NOT NULL THEN 1 ELSE 0 END), 0), 2)
      AS switch_rate_pct
  FROM with_lag
  WHERE year BETWEEN 2003 AND 2017
  GROUP BY year
  ORDER BY year
"))

# Flag election years
switch_by_year[, mayor_election := year %in% c(2004, 2008, 2012, 2016)]
switch_by_year[, govpres_election := year %in% c(2002, 2006, 2010, 2014)]
switch_by_year[, inauguration_mayor := year %in% c(2005, 2009, 2013, 2017)]
switch_by_year[, inauguration_govpres := year %in% c(2003, 2007, 2011, 2015)]

cat("\n6d. Party switch rates by year (election years flagged):\n\n")
print(switch_by_year)
save_csv(switch_by_year, "6d_switch_rates_by_year")

avg_election <- switch_by_year[mayor_election == TRUE | govpres_election == TRUE,
                                mean(switch_rate_pct, na.rm = TRUE)]
avg_non <- switch_by_year[mayor_election == FALSE & govpres_election == FALSE,
                           mean(switch_rate_pct, na.rm = TRUE)]
cat(sprintf("\nAvg switch rate: election years=%.2f%%, non-election=%.2f%%\n",
            avg_election, avg_non))
if (abs(avg_election - avg_non) < 0.5) {
  cat("  -> No meaningful difference: affiliation changes are NOT driven by elections.\n")
  cat("     This supports treating baseline affiliation as exogenous.\n")
} else {
  cat("  -> WARNING: switch rates differ around elections.\n")
  cat("     Strategic re-affiliation may threaten baseline exogeneity.\n")
}


# ===========================================================================
# Section 5: Multi-Municipality Firms
# ===========================================================================

cat("\n===== Section 5: Multi-Municipality Firms =====\n\n")

# 5a. Within-year
munis_by_fy <- panel[, .(n_munis = uniqueN(muni_id)), by = .(firm_id, year)]
munis_by_fy[, muni_bin := fcase(
  n_munis == 1L,  "1 muni",
  n_munis == 2L,  "2 munis",
  n_munis <= 5L,  "3-5 munis",
  n_munis <= 10L, "6-10 munis",
  n_munis > 10L,  "11+ munis"
)]
munis_by_fy[, muni_bin := factor(muni_bin,
  levels = c("1 muni", "2 munis", "3-5 munis", "6-10 munis", "11+ munis")
)]

simul_dist <- munis_by_fy[, .(n_firmyears = .N), by = muni_bin]
simul_dist[, pct := round(100 * n_firmyears / sum(n_firmyears), 1)]
setorder(simul_dist, muni_bin)
cat("5a. Within-year multi-municipality:\n")
print(simul_dist)
save_csv(simul_dist, "5a_multimuni_within_year")

# Employment by bin
emp_by_fy <- panel[, .(total_emp = sum(n_employees, na.rm = TRUE)), by = .(firm_id, year)]
emp_by_bin <- merge(munis_by_fy[, .(firm_id, year, muni_bin)], emp_by_fy,
                    by = c("firm_id", "year"))
emp_summary <- emp_by_bin[, .(
  median_emp = round(median(total_emp, na.rm = TRUE)),
  mean_emp   = round(mean(total_emp, na.rm = TRUE))
), by = muni_bin]
setorder(emp_summary, muni_bin)
cat("\nEmployment by muni count:\n")
print(emp_summary)
save_csv(emp_summary, "5a_employment_by_muni_count")

# 5b. Lifetime
munis_ever <- panel[, .(n_munis_ever = uniqueN(muni_id)), by = firm_id]
munis_ever[, muni_bin := fcase(
  n_munis_ever == 1L,  "1 muni",
  n_munis_ever == 2L,  "2 munis",
  n_munis_ever <= 5L,  "3-5 munis",
  n_munis_ever <= 10L, "6-10 munis",
  n_munis_ever > 10L,  "11+ munis"
)]
munis_ever[, muni_bin := factor(muni_bin,
  levels = c("1 muni", "2 munis", "3-5 munis", "6-10 munis", "11+ munis")
)]
lifetime_dist <- munis_ever[, .(n_firms = .N), by = muni_bin]
lifetime_dist[, pct := round(100 * n_firms / sum(n_firms), 1)]
setorder(lifetime_dist, muni_bin)
cat("\n5b. Lifetime multi-municipality:\n")
print(lifetime_dist)
save_csv(lifetime_dist, "5b_multimuni_lifetime")

# Sector cross-tab
multimuni_firms <- munis_ever[n_munis_ever >= 2L, firm_id]
sector_cross_all   <- unique(panel[, .(firm_id, cnae_section)])
sector_cross_multi <- sector_cross_all[firm_id %in% multimuni_firms]
sector_share <- merge(
  sector_cross_multi[, .(n_multi = uniqueN(firm_id)), by = cnae_section],
  sector_cross_all[, .(n_total = uniqueN(firm_id)), by = cnae_section],
  by = "cnae_section"
)
sector_share[, pct_multi := round(100 * n_multi / n_total, 1)]
setorder(sector_share, -pct_multi)
cat("\nMulti-muni by sector:\n")
print(sector_share)
save_csv(sector_share, "5b_multimuni_by_sector")

# 5c. Mechanism relevance
n_multimuni_fy  <- munis_by_fy[n_munis >= 2L, .N]
n_total_fy      <- nrow(munis_by_fy)
emp_multimuni   <- merge(munis_by_fy[n_munis >= 2L, .(firm_id, year)],
                         emp_by_fy, by = c("firm_id", "year"))
emp_total       <- sum(emp_by_fy$total_emp, na.rm = TRUE)
emp_multi_total <- sum(emp_multimuni$total_emp, na.rm = TRUE)

mechanism <- data.table(
  metric = c("multi_muni_firmyears_pct", "multi_muni_employment_pct"),
  value  = c(round(100 * n_multimuni_fy / n_total_fy, 1),
             round(100 * emp_multi_total / emp_total, 1))
)
cat(sprintf("\n5c. Multi-muni firm-years: %.1f%%, employment share: %.1f%%\n",
            mechanism$value[1], mechanism$value[2]))
save_csv(mechanism, "5c_multimuni_mechanism")


# ===========================================================================
# Cleanup
# ===========================================================================

dbDisconnect(con, shutdown = TRUE)
cat(sprintf("\n===== Done. %d CSV files saved to %s =====\n",
            length(list.files(OUT_DIR, pattern = "\\.csv$")), OUT_DIR))
