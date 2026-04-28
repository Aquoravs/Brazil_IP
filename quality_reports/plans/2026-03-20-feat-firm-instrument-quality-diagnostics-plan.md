---
title: "feat: Firm-Level Instrument Quality Diagnostics + Pooled-Count Baselines"
type: feat
status: completed
date: 2026-03-20
---

# Firm-Level Instrument Quality Diagnostics + Pooled-Count Baselines

## Overview

Two linked deliverables:

1. **Script 36 update**: Change baseline exposure construction from equal-year-weight averaging to **pooled-count** formula matching the paper (regs.tex §2.1). This also includes saving intermediate baselines as a side output for diagnostics.
2. **New diagnostic script** (`diagnostics/diagnose_firm_instruments.R`): Evaluate the empirical quality of firm-level political-linkage instruments (`FA_*`, `dFA_*`) for predicting BNDES firm credit allocation. Produces figures, summary tables, and a programmatic recommendation note.

## Problem Statement / Motivation

### Baseline Construction Mismatch

Script 36 currently computes baseline exposure as the **simple average of annual shares**:

```r
# Current (line 235): equal year weight
share_fp_0 = mean(L_fp / L_f)  # across years in window
```

The paper now specifies **pooled counts** (owner-year-weighted average):

```
omega_fp_t = sum_{s in T} L_{f,p,s} / sum_{s in T} L_{f,s}
```

These differ when `L_f` varies across years within the window. The pooled-count definition weights each owner-year observation equally, so years with more owners contribute more to the baseline. This is the canonical formula in regs.tex §2.1 and must be implemented before diagnostics can evaluate the production instruments.

**Note**: The extensive-margin baseline (`tilde{omega}` in the paper) is a robustness variant and is **not** part of this plan.

### Missing Instrument Diagnostics

The firm first-stage estimation (script 51) runs a 144-specification battery, but there is no upstream diagnostic that characterizes the raw instrument distributions, flags data quality issues, or validates that instruments have credible variation before feeding them into expensive regressions. Without this:

- Outlier-driven results may go undetected until post-estimation review
- Structural zeros in `dFA_*` (non-inauguration years) may be misinterpreted as weak instruments
- Baseline exposure quality (persistence, coverage, party concentration) is unexamined
- No systematic comparison between tiers, alignment types, or baseline types exists

**Goal**: Help choose the instrument specification with credible variation, not dominated by outliers or coding artifacts, and with the best empirical chance of predicting firm-level BNDES credit allocation.

## Proposed Solution

### Part A: Script 36 — Pooled-Count Baselines

Update the baseline computation in script 36 (lines 231-236) from simple averaging to pooled counts. Also save intermediate baseline exposures for diagnostic use.

### Part B: Diagnostic Script

A single modular R script organized into five diagnostic sections, each loading only the columns it needs via fst column-selective reads. Outputs go to `OUTPUT_DIR/diagnostics/firm_instruments/`.

### Prerequisites

**Script 36 modification (small)**: Save intermediate baseline exposures (`share_fp_0` = `L_fp_0 / L_f_0`) as `output/firm_baseline_exposures.qs2` with columns `(firm_id, party, baseline_type, election_year, share_fp_0, L_fp_0, L_f_0, n_baseline_years)`. Currently these are consumed and discarded during instrument construction. This is ~2 lines of code and enables Section 3 (baseline diagnostics) without re-deriving from raw affiliation data.

### Script Structure

```
diagnostics/diagnose_firm_instruments.R
├── Section 0: Bootstrap, paths, variable definitions
├── Section 1: Instrument distribution diagnostics
├── Section 2: Within/between-firm variation decomposition
├── Section 3: Baseline exposure diagnostics
├── Section 4: Election-cycle timing & predictive relevance
├── Section 5: Export recommendation note
```

## Technical Considerations

### Memory Strategy (16 GB RAM)

- **Never load full panel with all columns simultaneously.** Use fst column-selective reads throughout.
- **Process one diagnostic section at a time** with explicit `rm(); gc()` between sections.
- **Process `cycle_specific` baseline only** by default. The script accepts `--baseline=2002_fixed` to run the alternative, but never loads both simultaneously.
- **Within/between decomposition**: Use data.table GForce-optimized aggregations (`mean`, `sd` within `.SD`) grouped by `firm_id`. Avoid materializing a firm-level means table alongside the full panel — compute deviations incrementally.
- **Predictive regressions**: Use fixest with `nthreads=4` and lean specifications (firm FE only, no muni×year FE) to keep each regression under 2 minutes.

### Structural Zeros vs. Data-Quality Zeros

The `dFA_*` instruments are zero by construction in non-inauguration years:
- Mayor: non-zero only in {2005, 2009, 2013, 2017}
- Gov/Pres: non-zero only in {2007, 2011, 2015}

All diagnostic statistics for `dFA_*` must be reported **both unconditionally and conditional on inauguration years**. Unconditional zero-mass (e.g., "93% zeros") is structural and uninformative; conditional zero-mass reveals actual instrument weakness.

For `FA_*` (levels), zeros arise from either (a) no affiliated owners in the firm, or (b) no alignment between firm's parties and municipality's incumbents. Both are substantive.

### Three-Way Zero Taxonomy

| Category | Definition | Diagnostic Treatment |
|----------|-----------|---------------------|
| Structural zero | dFA in non-inauguration year | Exclude from conditional stats |
| No-exposure zero | Firm has no affiliated owners (L_f_0 = 0 or all "No party") | Report as coverage gap |
| Substantive zero | Affiliated firm, no alignment match | Include in all stats |

## Acceptance Criteria

### Section 0: Setup & Variable Definitions

- [x] Standard bootstrap pattern (inline block, matching `diagnose_alignment_overlap_support.R`)
- [x] `setDTthreads(0)` for multi-threaded data.table
- [x] Output directory: `file.path(OUTPUT_DIR, "diagnostics", "firm_instruments")`
- [x] Centralized variable definitions as named lists:

```r
# Instrument groups
FA_SINGLE <- c("FA_mayor_coalition", "FA_mayor_party",
               "FA_gov_coalition", "FA_gov_party",
               "FA_pres_coalition", "FA_pres_party")
FA_INTERACT <- c("FA_mayor_gov_coalition", "FA_mayor_gov_party",
                 "FA_mayor_pres_coalition", "FA_mayor_pres_party",
                 "FA_triple_coalition", "FA_triple_party")
DFA_SINGLE <- gsub("^FA_", "dFA_", FA_SINGLE)
DFA_INTERACT <- gsub("^FA_", "dFA_", FA_INTERACT)
ALL_INSTRUMENTS <- c(FA_SINGLE, FA_INTERACT, DFA_SINGLE, DFA_INTERACT)

# Outcomes
OUTCOMES_LEVELS <- c("has_bndes_fmt", "log_bndes_fmt")
OUTCOMES_CHANGES <- c("delta_has_bndes_fmt", "delta_log_bndes_fmt")

# Inauguration years by tier
INAUG_MAYOR <- c(2005L, 2009L, 2013L, 2017L)
INAUG_GOVPRES <- c(2007L, 2011L, 2015L)

# Theoretical support bounds
BOUNDS <- list(FA = c(0, 1), dFA = c(-1, 1))
```

- [x] Fail with informative error if any expected instrument column is missing from the fst file
- [x] Accept `--baseline=cycle_specific|2002_fixed` CLI argument (default: `cycle_specific`)
- [x] Print diagnostic header: date, baseline type, input file paths, panel dimensions

### Section 1: Instrument Distribution Diagnostics

**Input**: fst column-selective read of instrument columns + `year` + `firm_id` + `muni_id`

For each instrument group (FA single-tier, FA interaction, dFA single-tier, dFA interaction):

- [x] **Overall descriptive statistics table** (CSV): mean, sd, min, p1, p5, p25, median, p75, p95, p99, max, n_obs, n_zero, pct_zero, skewness, kurtosis
- [x] **By-year descriptive statistics table** (CSV): same columns, stratified by year
- [x] **For dFA instruments**: report conditional stats (inauguration years only) alongside unconditional
- [x] **Support bounds check**: flag any values outside theoretical bounds `[0, 1]` for FA, `[-1, 1]` for dFA
- [x] **Faceted density plots** (PNG, 4 total):
  - `fig_density_fa_single.png`: 6-panel facet (one per FA single-tier instrument), density of non-zero values
  - `fig_density_fa_interact.png`: 6-panel facet for FA interaction instruments
  - `fig_density_dfa_single.png`: 6-panel facet for dFA single-tier (inauguration years only)
  - `fig_density_dfa_interact.png`: 6-panel facet for dFA interaction
- [x] **Zero-mass heatmap** (PNG, 1 total): `fig_zero_mass_by_year.png` — heatmap of % zero by instrument × year, with inauguration years highlighted

### Section 2: Within/Between-Firm Variation Decomposition

**Input**: fst column-selective read of instrument columns + `firm_id` + `muni_id` + `year`

- [x] **Variance decomposition table** (CSV): For each instrument, report:
  - Total variance
  - Between-firm variance (variance of firm means)
  - Within-firm variance (mean of firm-level variances)
  - ICC (intra-class correlation = between / total)
  - Share of within-firm variation at inauguration years only (for dFA)
- [x] **Interpretation note**: High ICC means the instrument is mostly cross-sectional (between firms); low ICC means time-series variation dominates. For the firm FE specification, only within-firm variation identifies the coefficient.
- [x] **For dFA instruments**: compute decomposition restricted to inauguration years
- [x] **Scatter of within vs. between SD** (PNG, 1 total): `fig_within_between_scatter.png` — each instrument is a labeled point, x = between-firm SD, y = within-firm SD

### Section 3: Baseline Exposure Diagnostics

**Input**: `output/firm_baseline_exposures.qs2` (new side output from script 36)

- [x] **Coverage table** (CSV): By election cycle × tier, report:
  - N firms with any affiliated owner (L_f_0 > 0)
  - N firms with zero affiliations (L_f_0 = 0 or all "No party")
  - N baseline years available (from `n_baseline_years` column)
  - Mean, median, max `share_fp_0` across firms
- [x] **Persistence analysis** (CSV): For firms present in consecutive election cycles, compute:
  - Correlation of `share_fp_0` between cycle τ and τ+1 (same party)
  - Fraction of firms switching dominant party between cycles
  - Fraction of firms with stable exposure (|Δshare_fp_0| < 0.1)
- [x] **Pairwise correlation matrix** (PNG, 1 total): `fig_baseline_correlations.png` — correlation heatmap of `share_fp_0` across parties within a cycle (are firms exposed to multiple parties simultaneously?)
- [x] **Flag support problems**:
  - Firms with `share_fp_0 = 0` for all parties (no political exposure)
  - Election cycles where `n_baseline_years < 2` (thin baselines)
  - Municipality-cycles with fewer than 10 firms having non-zero exposure

### Section 4: Election-Cycle Timing & Predictive Relevance

#### 4A: Timing Alignment Checks

**Input**: fst read of instruments + year

- [x] **Inauguration-year verification** (console + CSV): Confirm that `dFA_*` columns are zero in all non-inauguration years. Report any violations.
- [x] **Term-constancy check**: For `FA_*` (levels), verify that values are constant within each 4-year electoral term for a given (firm, muni). Report fraction of firm-muni cells violating this (should be ~0%).
- [x] **Event-study-style plot** (PNG, 1 total): `fig_instrument_by_year.png` — mean non-zero instrument value by year, with vertical lines at inauguration years, separate series for mayor/gov/pres tiers. Shows whether instrument magnitude varies systematically with the electoral cycle.

#### 4B: Predictive Relevance (Diagnostic Regressions)

**Input**: fst read of instruments + outcomes + `firm_id` + `n_employees`

**Specification**: Stripped-down battery — fast diagnostics, not production estimation.

| # | Dependent Variable | Instruments | FE | Weights | Purpose |
|---|-------------------|-------------|-----|---------|---------|
| 1 | `has_bndes_fmt` | FA_mayor_coalition | firm_id | n_employees | Mayor extensive |
| 2 | `has_bndes_fmt` | FA_gov_coalition | firm_id | n_employees | Gov extensive |
| 3 | `has_bndes_fmt` | FA_pres_coalition | firm_id | n_employees | Pres extensive |
| 4 | `log_bndes_fmt` | FA_mayor_coalition | firm_id | n_employees | Mayor intensive |
| 5 | `log_bndes_fmt` | FA_gov_coalition | firm_id | n_employees | Gov intensive |
| 6 | `log_bndes_fmt` | FA_pres_coalition | firm_id | n_employees | Pres intensive |
| 7 | `has_bndes_fmt` | FA_mayor + FA_gov + FA_pres (coalition) | firm_id | n_employees | Joint extensive |
| 8 | `log_bndes_fmt` | FA_mayor + FA_gov + FA_pres (coalition) | firm_id | n_employees | Joint intensive |
| 9 | `delta_has_bndes_fmt` | dFA_mayor_coalition | firm_id | n_employees | Mayor chg ext |
| 10 | `delta_has_bndes_fmt` | dFA_gov_coalition | firm_id | n_employees | Gov chg ext |
| 11 | `delta_has_bndes_fmt` | dFA_pres_coalition | firm_id | n_employees | Pres chg ext |
| 12 | `delta_has_bndes_fmt` | dFA_mayor + dFA_gov + dFA_pres (coal.) | firm_id | n_employees | Joint chg ext |

- [x] **Uses firm FE only** (not firm + muni×year) — faster and sufficient for diagnostics. The full FE structure is for production estimation in script 51.
- [x] **`setFixest_nthreads(4)`** for speed
- [x] **Output** (CSV): `predictive_regressions.csv` with columns: spec_id, depvar, instruments, coef, se, t_stat, p_value, r2_within, wald_f, n_obs
- [x] **Interpretation caveat**: Print explicit note that these are predictive diagnostics, not causal estimates. Absence of muni×year FE inflates apparent predictive power.

#### 4C: Winsorization Sensitivity

- [x] **Test 1/99 and 5/95 percentile winsorization** on all instrument columns
- [x] **Report** (CSV): `winsorization_sensitivity.csv` — for each instrument × threshold: original mean, winsorized mean, original SD, winsorized SD, original skewness, winsorized skewness, n_clipped
- [x] **Flag instruments where winsorization changes mean by > 10%** or SD by > 25% (tail-driven)

### Section 5: Export Recommendation Note

- [x] **Programmatically generated** markdown file: `recommendation_note.md`
- [x] **Structure**:

```markdown
# Firm Instrument Quality Diagnostics — Summary
Date: {date}
Baseline: {baseline_type}
Panel: {n_obs} obs, {n_firms} firms, {n_years} years

## Pass/Fail Summary
| Diagnostic | Status | Detail |
|-----------|--------|--------|
| Instrument coverage | PASS/WARN | {pct} of panel has non-zero FA instruments |
| Support bounds | PASS/FAIL | {n} values outside theoretical bounds |
| Structural zeros (dFA) | PASS/FAIL | dFA non-zero only at inauguration years: {yes/no} |
| Term constancy (FA) | PASS/FAIL | {pct}% of firm-muni cells constant within term |
| Baseline coverage | PASS/WARN | {pct}% of firms with affiliated owners |
| Baseline persistence | INFO | Cross-cycle correlation: {r} |
| Winsorization sensitivity | PASS/WARN | {n} instruments flagged as tail-driven |

## Predictive Relevance (Diagnostic Regressions)
| Tier | Margin | Wald F | Assessment |
|------|--------|--------|------------|
| Mayor | Extensive | {F} | {STRONG/MODERATE/WEAK} |
| ... | ... | ... | ... |

Threshold: F >= 10 → STRONG, 5 <= F < 10 → MODERATE, F < 5 → WEAK

## Recommendation
{Programmatic text based on results: which tiers show strongest relevance,
 which alignment type (coalition vs party) is preferred if both were tested,
 whether interaction instruments add predictive power,
 and which robustness alternatives to report.}

## Caveats
- These are predictive diagnostics only, not causal estimates.
- Firm FE only (no muni×year FE); apparent relevance will differ in production specifications.
- Conditional-on-positive sample for intensive margin may differ from production conditioning.
```

## Dependencies & Risks

### Dependencies
- **Script 36 modification**: Must save `firm_baseline_exposures.qs2` before this script can run Section 3. Fallback: skip Section 3 with a warning if file not found.
- **Input files**: `firm_panel_for_regs.fst` and `firm_level_instruments.qs2` (or `.fst`) must exist (built by scripts 42 and 36)
- **Libraries**: `data.table`, `qs2`, `fst`, `fixest`, `moments` (for skewness/kurtosis; or compute manually)

### Risks
- **Memory pressure**: Mitigated by fst column-selective reads and section-by-section processing with gc()
- **Runtime**: 12 diagnostic regressions with firm FE on ~44M rows ≈ 12-24 minutes total. Acceptable for a diagnostic script.
- **`moments` package**: May not be installed. Fallback: compute skewness/kurtosis manually with data.table (3 lines each).

## Implementation Checklist

### Phase 0: Script 36 — Pooled-Count Baselines (15 min)

**Location**: `BNDES/politicsregs/3_instruments/36_build_firm_level_instruments.R`, lines 231-236

**Current code** (equal-year-weight averaging):
```r
base_i <- firm_shares[year %in% window_years,
                      .(L_fp = mean(L_fp, na.rm = TRUE),
                        L_f = mean(L_f, na.rm = TRUE),
                        share_fp = mean(share_fp, na.rm = TRUE)),
                      by = .(firm_id, party)]
```

**New code** (pooled counts):
```r
base_i <- firm_shares[year %in% window_years,
                      .(L_fp_0 = sum(L_fp, na.rm = TRUE),
                        L_f_0 = sum(L_f, na.rm = TRUE),
                        n_baseline_years = .N),
                      by = .(firm_id, party)]
base_i[, share_fp := fifelse(L_f_0 > 0, L_fp_0 / L_f_0, 0)]
```

Note: `L_f` must be summed at the firm level (not firm×party) to avoid double-counting. Since `firm_shares` has one row per (firm_id, year, party), `L_f` is duplicated across parties within a firm-year. The correct pooled denominator pools across years but not across parties:

```r
# Pool L_f at (firm_id) level first, then merge back
firm_L_pooled <- firm_shares[year %in% window_years,
                             .(L_f_0 = sum(L_f[!duplicated(year)], na.rm = TRUE),
                               n_baseline_years = uniqueN(year)),
                             by = .(firm_id)]
party_L_pooled <- firm_shares[year %in% window_years,
                              .(L_fp_0 = sum(L_fp, na.rm = TRUE)),
                              by = .(firm_id, party)]
base_i <- merge(party_L_pooled, firm_L_pooled, by = "firm_id")
base_i[, share_fp := fifelse(L_f_0 > 0, L_fp_0 / L_f_0, 0)]
```

- [x] Update baseline computation from `mean()` to pooled `sum()/sum()` with correct denominator handling
- [x] Verify that `sum_p share_fp <= 1` still holds (print diagnostic)
- [x] Update log messages to say "pooled-count baseline" instead of "averaged baseline"
- [x] Rename downstream columns consistently: `L_fp` → `L_fp_0`, `L_f` → `L_f_0` (already done at line 278-280, but verify)

**Script 33 update** (`33_select_baseline_weights.R`, lines 163-168): Same issue. Currently averages `L_rjp` and `w_rjp` (= `L_rjp / N_rj`) per year equally across the window. The pooled-count version should be:

```r
# Current (line 164-165): equal year weight
avg_expr_party <- lapply(avg_party_cols, function(col) {
    call("mean", as.name(col), na.rm = TRUE)
})

# New: pool L_rjp and compute w_rjp from pooled counts
# For party-level: sum L_rjp across window years
# For sector-level: sum N_rj across window years (deduplicate across parties first)
# Then: w_rjp_0 = sum(L_rjp) / sum(N_rj)
```

- [x] Update script 33 to pool `L_rjp` via `sum()` instead of averaging `w_rjp` via `mean()`
- [x] Recompute `w_rjp` as `L_rjp_pooled / N_rj_pooled` after pooling raw counts
- [x] Also pool `L_rj` and `N_rj` via `sum()` for the sector-level columns
- [x] Verify `sum_p w_rjp <= 1` still holds
- [x] Keep `baseline_years_used` column for diagnostic use

### Phase 0b: Script 33 — Pooled-Count Sector Baselines (10 min)
- [x] Update `avg_expr_party` from `mean()` to `sum()` for `L_rjp`
- [x] Pool `N_rj` and `L_rj` via `sum()` (deduplicate across parties within year first)
- [x] Recompute `w_rjp = L_rjp_pooled / N_rj_pooled`
- [x] Verify `sum_p w_rjp <= 1`
- [x] Update log messages

### Phase 0c: CLAUDE.md Update (2 min)
- [x] Update the "Averaged baselines" section (decision #9) to say "pooled-count baselines" and note the formula change: `omega = sum(L_fp) / sum(L_f)` across window years, not `mean(L_fp / L_f)`

### Phase 1: Script 36 Side Output (5 min)
- [x] Save intermediate baselines after pooled-count computation: `qs_save(baseline_dt, make_output_path("firm_baseline_exposures.qs2"))` with columns `(firm_id, party, baseline_type, election_year, share_fp_0, L_fp_0, L_f_0, n_baseline_years)`
- [x] Re-run scripts 33, 36 to produce updated outputs

### Phase 2: Diagnostic Script Skeleton (15 min)
- [x] Create `diagnostics/diagnose_firm_instruments.R` with bootstrap, variable definitions, CLI arg parsing
- [x] Create output directory
- [x] Implement fst column discovery and missing-variable checks

### Phase 3: Sections 1-2 (30 min)
- [x] Section 1: Distribution diagnostics + density plots + zero-mass heatmap
- [x] Section 2: Within/between decomposition + scatter plot

### Phase 4: Section 3 (20 min)
- [x] Section 3: Baseline exposure diagnostics (with graceful skip if file missing)

### Phase 5: Section 4 (30 min)
- [x] Section 4A: Timing alignment checks
- [x] Section 4B: Predictive regressions (12 specs)
- [x] Section 4C: Winsorization sensitivity

### Phase 6: Section 5 + Polish (15 min)
- [x] Section 5: Recommendation note generation
- [x] Console progress messages throughout
- [x] Final review: memory management, error messages, output count

### Expected Outputs (23 files)

| Type | Count | Files |
|------|-------|-------|
| CSV | 9 | `desc_stats_overall.csv`, `desc_stats_by_year.csv`, `variance_decomposition.csv`, `baseline_coverage.csv`, `baseline_persistence.csv`, `inauguration_verification.csv`, `predictive_regressions.csv`, `winsorization_sensitivity.csv`, `term_constancy.csv` |
| PNG | 8 | `fig_density_fa_single.png`, `fig_density_fa_interact.png`, `fig_density_dfa_single.png`, `fig_density_dfa_interact.png`, `fig_zero_mass_by_year.png`, `fig_within_between_scatter.png`, `fig_baseline_correlations.png`, `fig_instrument_by_year.png` |
| MD | 1 | `recommendation_note.md` |
| **Total** | **18** | |

## Sources & References

### Internal References
- Instrument construction: `BNDES/politicsregs/3_instruments/36_build_firm_level_instruments.R`
- Firm panel builder: `BNDES/politicsregs/4_regression_panels/42_build_firm_panel.R`
- Production estimation: `BNDES/politicsregs/5_estimation/51_firm_first_stage.R`
- Existing diagnostic pattern: `BNDES/politicsregs/diagnostics/diagnose_alignment_overlap_support.R`
- Bootstrap pattern: `BNDES/politicsregs/_utils/script_bootstrap.R`
- Beamer table utility: `BNDES/politicsregs/_utils/beamer_tables.R`

### Related Brainstorms
- `docs/brainstorms/2026-03-14-firm-sector-first-stage-disconnect-brainstorm.md` — documents firm→sector aggregation gap; diagnostics 1A/1B proposed there are complementary to this script
- `docs/brainstorms/2026-03-15-affiliation-data-diagnostics-brainstorm.md` — validates foundational affiliation data quality; this script builds on those findings

### Related Plans
- `docs/plans/2026-03-16-feat-firm-first-stage-overhaul-plan.md` — the production estimation this diagnostic supports
- `docs/plans/2026-03-17-review-firm-first-stage-overhaul-findings.md` — known bugs (P1 Wald pattern in script 53, missing COEF_MAP entries)
