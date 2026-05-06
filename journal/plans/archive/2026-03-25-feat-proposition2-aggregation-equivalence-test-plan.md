---
title: "feat: Proposition 2 Aggregation Equivalence Test in Script 52"
type: feat
status: active
date: 2026-03-25
origin: paper/review_aggregation.tex
---

# Proposition 2 Aggregation Equivalence Test

## Overview

Modify script 52 (`52_aggregated_firm_sector_first_stage.R`) to formally evaluate Proposition 2 from `review_aggregation.tex`: firm-level and cell-averaged OLS should produce identical `lambda^ext_l` coefficients under proper weighting, sample identity, and FE conditions. The script will run firm-level regressions internally on the exact same sample used for aggregation, apply `N_c` (or `E_c`) regression weights to the aggregated version, test both the current FE structure and an exact support-regime FE, and produce side-by-side summary tables. It will also optionally compare against pre-existing script 51 output to quantify how much the sample filter matters.

## Problem Statement / Motivation

The `review_aggregation.tex` document establishes four conditions for exact coefficient equivalence between firm-level and sector-level regressions:

1. **Weighting**: unweighted firm OLS requires `N_c`-weighted cell OLS; employment-weighted firm OLS requires `E_c`-weighted cell OLS with employment-weighted averages.
2. **Same sample**: both regressions must use the identical firm set.
3. **Consistent FE**: the cell-averaged FE `bar(gamma)_c` must be nested by the sector-level FE.
4. **Linear averaging**: the population equation aggregates exactly because `lambda` is common to all firms.

Script 52 currently collapses the firm panel to cells and runs unweighted aggregated OLS. It computes `N_pre` and `emp_pre` but never uses them as regression weights. It also differs from script 51 because script 52 uses the current support-based `F_pre` while script 51 baseline specs use the all-firms estimation sample. These gaps prevent script 52 from serving as a formal Proposition 2 test.

## Proposed Solution

### Architecture: Two modes within script 52

**Mode A - Proposition 2 Equivalence Test** (`--proposition2`):
- Run `feols()` at the firm level on the same filtered sample used for aggregation (the current support-based `F_pre`).
- Collapse to cells with simple averaging (unweighted case) and employment-weighted averaging.
- Run aggregated `feols()` with `N_c` weights (unweighted target) and `E_c` weights (employment-weighted target).
- Test under two FE structures:
  - relaxed: `muni_id^sector + muni_id^year`
  - exact: `muni_id^sector^support_regime + muni_id^year`
- Produce summary tables, FE-comparison tables, and programmatic equality checks.

**Mode B - Script 51 Comparison** (`--compare-51`):
- Load pre-existing script 51 coefficient output (`firm_run_manifest.csv` / `fc_battery_summary.qs2`).
- Reconstruct the script 51 baseline sample directly from the panel.
- Report coefficient gaps, F-stat gaps, and sample-overlap diagnostics against script 52's support-based `F_pre`.

### Key implementation decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Internal firm-level regression | Yes, on identical filtered sample | Only way to satisfy Proposition 2 sample-identity and weighting conditions |
| Keep current `F_pre` | Yes, use the support-based sample already implemented in script 52 | More defensible than the older `any(FA != 0)` proxy |
| Also compare against script 51 | Yes, optional `--compare-51` | Shows practical impact of the sample mismatch |
| FE structures | Test both relaxed and exact | The relaxed FE is the current empirical spec; the exact FE is the Proposition 2 benchmark |
| Exact FE regime definition | Derive `support_regime` from the actual baseline-window support map used by script 52 | Preserves exact nesting under the sample that is actually aggregated |
| Weighting variants | `N_c` for unweighted, `E_c` for employment-weighted | Matches Proposition 2 Cases 1 and 2 |
| Also report no-weight aggregated | Yes | Shows the magnitude of the weighting correction |
| Main summary table | Six columns per alignment x exposure: firm (UW), agg `N_c`-weighted, agg simple, firm (EW), agg `E_c`-weighted, agg emp-simple | Lets the baseline spec be read in one place with coefficients, SEs, F-stats, N, and FE labels |
| Equality tolerance | `max(abs(beta_firm - beta_agg)) < 1e-8` | Floating-point tolerance for exact equivalence |

## Technical Considerations

### 1. Support-regime column

The firm panel does not contain a support-regime column. Derive it inside script 52 from the same year-to-baseline mapping already used to build the current support filter.

- Build a `year -> baseline_year` map with `build_f_pre_year_map()`.
- For each current year, collapse the sorted set of active baseline years into a regime label.
- Attach that regime label to both the firm-level and aggregated datasets.

This avoids modifying script 42 or the firm panel schema and keeps the exact FE aligned with the sample construction script 52 actually uses.

### 2. FE-related estimation loss diagnostic

The original singleton narrative is too imprecise: one-firm underlying cells do not mechanically imply `fixest` singleton absorption at the aggregated level. The diagnostic should therefore report estimation-sample retention under each FE structure rather than claiming that one-firm cells are what gets dropped.

The script should report:
- number of candidate firm-year observations before each firm regression
- number of candidate aggregated cells before each aggregated regression
- number used by each fitted model (`nobs`)
- retention rate under relaxed vs. exact FE
- a warning if the exact FE removes more than 80% of candidate observations or cells

### 3. Firm-level regression within script 52

The firm-level `feols()` call uses `firm_id + muni_id^year` FE and `~ firm_id + muni_id` clustering, matching script 51. For the employment-weighted version, add `weights = ~n_employees`. The key difference from script 51 is the sample: script 52 uses the support-based `F_pre`, not the script-51 all-firms baseline sample.

For the comparison tables, clustering affects only SEs, not point estimates. Equality checks therefore compare coefficients only.

### 4. Main Proposition 2 summary table layout

For each alignment x exposure combination (for example, coalition + pooled_count), produce a six-column baseline-spec summary table:

| | Firm UW | Agg `N_c`-wt | Agg simple | Firm EW | Agg `E_c`-wt | Agg emp-simple |
|---|---|---|---|---|---|---|
| `FA_mayor` / `FA_binary_mayor` | beta (se) | beta (se) | beta (se) | beta (se) | beta (se) | beta (se) |
| `FA_gov` / `FA_binary_gov` | beta (se) | beta (se) | beta (se) | beta (se) | beta (se) | beta (se) |
| `FA_pres` / `FA_binary_pres` | beta (se) | beta (se) | beta (se) | beta (se) | beta (se) | beta (se) |
| F-statistic | reported | reported | reported | reported | reported | reported |
| Observations | reported | reported | reported | reported | reported | reported |

Produce one such table under relaxed FE and one under exact FE. Table notes should state which columns correspond to unweighted versus employment-weighted targets.

### 5. FE comparison table

For each alignment x exposure combination, also produce an aggregated-only FE-comparison table that contrasts relaxed and exact FE under:
- unweighted cell averages with and without `N_c` weights
- employment-weighted cell averages with and without `E_c` weights

This table isolates the empirical effect of tightening the FE structure.

### 6. Sample diagnostic

Before running regressions, emit a sample reconciliation report:
- total firm-year observations in the loaded panel
- total firm-year observations after the support-based `F_pre` filter
- cell-size distribution: mean, median, p90, p99, max of `N_c`
- fraction of firm-year observations in singleton cells (`N_c = 1`)
- if `--compare-51` is active: reconstructed count of firms and firm-year rows in script 51 but not script 52, and vice versa

### 7. Output artifacts

| Artifact | Path | Description |
|----------|------|-------------|
| Relaxed-FE summary table (Beamer) | `agg_firm_reg_tables_{grouped}/prop2_equiv_relaxed_<alignment>_<exposure>.tex` | Six-column baseline-spec summary table with both weighting targets |
| Exact-FE summary table (Beamer) | `agg_firm_reg_tables_{grouped}/prop2_equiv_exact_<alignment>_<exposure>.tex` | Same summary table under exact support-regime FE |
| Summary table (markdown) | same path with `.md` | Git / console review version |
| FE comparison table | `agg_firm_reg_tables_{grouped}/prop2_fe_comparison_<alignment>_<exposure>.tex` | Aggregated relaxed-vs-exact FE comparison |
| Equality check log | `agg_firm_reg_tables_{grouped}/prop2_equality_check.csv` | Per-spec PASS/FAIL with max coefficient deviations |
| Sample diagnostic log | `agg_firm_reg_tables_{grouped}/prop2_sample_diagnostic.csv` | Cell support and FE-retention diagnostics |
| Script-51 comparison log | `agg_firm_reg_tables_{grouped}/prop2_compare51.csv` | Coefficient gaps, F-stat gaps, and reconstructed sample-overlap metrics |

## System-Wide Impact

- **No changes to other scripts**: script 52 is self-contained; it reads the firm panel and produces its own output.
- **No schema changes**: `support_regime` is derived within script 52 and not added to the firm panel.
- **Backward compatible**: running script 52 without `--proposition2` preserves the current aggregated-only behavior.
- **Optional dependency on script 51 output**: `--compare-51` requires script 51 outputs for the matching baseline specs.

## Acceptance Criteria

### Functional Requirements

- [ ] **Unweighted equivalence**: under `--proposition2`, unweighted firm OLS and `N_c`-weighted aggregated OLS match within `1e-8` under the exact support-regime FE; relaxed FE gaps are reported but not treated as failures.
- [ ] **Employment-weighted equivalence**: employment-weighted firm OLS and `E_c`-weighted aggregated OLS with employment-weighted averages match within `1e-8` under the exact support-regime FE.
- [ ] **Six-column baseline summary table**: each summary table shows both firm targets and their aggregated counterparts, including coefficients, SEs, F-stats, observations, and FE labels.
- [ ] **Two FE structures tested**: both relaxed and exact FE are reported.
- [ ] **FE-retention diagnostic**: the script reports how many firm-year observations / cells survive estimation under each FE structure.
- [ ] **Sample diagnostic**: the script reports the `N_c` distribution and singleton share.
- [ ] **Script 51 comparison** (`--compare-51`): the script loads script 51 output and reports coefficient/F-stat differences plus reconstructed overlap counts.
- [ ] **Equality check CSV**: per-spec PASS/FAIL with max absolute coefficient deviation.
- [ ] **Existing behavior preserved**: running script 52 without `--proposition2` produces the same output as before.

### Quality Gates

- [ ] All new Proposition 2 comparison tables use `save_beamer_table()` from `beamer_tables.R`.
- [ ] Console output is informative but not verbose and follows current script-52 patterns.
- [ ] `--dry-run` prints planned comparisons and output paths without running regressions.

## Dependencies & Risks

### Dependencies

- **Script 42** must have been run to produce `firm_panel_for_regs.fst/.qs2`.
- **Script 51** must have been run if using `--compare-51`.
- `beamer_tables.R` must support the needed wide tables via `save_beamer_table()`.

### Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Exact FE (`muni_id^sector^support_regime`) sharply reduces the effective sample | High | Report FE-retention diagnostics; warn if retention falls below 20% |
| Relaxed FE produces coefficients that are close but not identical | Certain | Report deviation magnitudes explicitly; that is the point of the FE comparison |
| Memory pressure from fitting multiple firm and aggregated models in one run | Medium | Use `lean = TRUE`, `mem.clean = TRUE`, and `gc()` between blocks |
| Script 51 output format changes in the future | Low | Validate expected columns before loading optional comparison inputs |

## Implementation Sketch

### Step 1: CLI argument parsing

Add `--proposition2`, `--compare-51`, and `--dry-run` flags. When `--proposition2` is active, run the current aggregated output first, then enter the Proposition 2 block.

### Step 2: Support-regime derivation

```r
regime_map <- f_pre_year_map[
  , .(support_regime = paste(sort(unique(baseline_year)), collapse = "_")),
  by = year
]
dt_pre[regime_map, support_regime := i.support_regime, on = "year"]
agg_dt[regime_map, support_regime := i.support_regime, on = "year"]
```

### Step 3: Sample diagnostics

Print and save:
- panel rows before/after support filtering
- `N_pre` distribution
- singleton fraction
- candidate-vs-used counts under relaxed and exact FE

### Step 4: Internal firm-level regressions

For each alignment x exposure combination, run the baseline `M+G+P` extensive-levels firm regressions:

```r
mod_firm_uw <- feols(
  has_bndes_fmt ~ FA_mayor_coalition + FA_gov_coalition + FA_pres_coalition |
    firm_id + muni_id^year,
  data = dt_pre,
  vcov = ~ firm_id + muni_id,
  lean = TRUE,
  mem.clean = TRUE
)

mod_firm_ew <- feols(
  has_bndes_fmt ~ FA_mayor_coalition + FA_gov_coalition + FA_pres_coalition |
    firm_id + muni_id^year,
  data = dt_pre[n_employees > 0 & is.finite(n_employees)],
  weights = ~ n_employees,
  vcov = ~ firm_id + muni_id,
  lean = TRUE,
  mem.clean = TRUE
)
```

### Step 5: Aggregated regressions with weights

For each FE structure (relaxed + exact), run:

```r
mod_agg_nc <- feols(
  H_jmt ~ FA_bar_mayor_coalition + FA_bar_gov_coalition + FA_bar_pres_coalition | FE,
  data = agg_unweighted,
  weights = ~ N_pre,
  vcov = ~ muni_id + sector,
  lean = TRUE,
  mem.clean = TRUE
)

mod_agg_ec <- feols(
  H_jmt ~ FA_bar_mayor_coalition + FA_bar_gov_coalition + FA_bar_pres_coalition | FE,
  data = agg_emp_weighted,
  weights = ~ emp_pre,
  vcov = ~ muni_id + sector,
  lean = TRUE,
  mem.clean = TRUE
)
```

Also run the no-cell-weight versions on the same aggregated datasets.

### Step 6: Equality checks and table export

For each alignment x exposure combination:
- extract firm and aggregated coefficients
- compute `max_abs_diff` for weighted and unweighted targets
- save PASS/FAIL rows to `prop2_equality_check.csv`
- export relaxed-FE and exact-FE six-column summary tables with `save_beamer_table()`
- export aggregated relaxed-vs-exact FE comparison table with `save_beamer_table()`
- write markdown mirrors for review

### Step 7: Script 51 comparison

Load `fc_battery_summary.qs2` and `firm_run_manifest.csv`, match the baseline `main`, `levels`, `extensive`, `cycle_specific`, `all_firms`, `M+G+P` rows by alignment / exposure / weighting, and compare them against the internally re-estimated script-52 firm models.

Reconstruct script 51 baseline samples from the panel using script 51's sample-mask rules so that overlap with script 52's support-based `F_pre` can be counted directly.

## Sources & References

- **Theory**: `paper/review_aggregation.tex`
- **Current script**: `BNDES/politicsregs/5_estimation/52_aggregated_firm_sector_first_stage.R`
- **Firm benchmark**: `BNDES/politicsregs/5_estimation/51_firm_first_stage.R`
- **Table utility**: `BNDES/politicsregs/_utils/beamer_tables.R`
- **Related background**: `paper/regs.tex`, `docs/brainstorms/2026-03-14-firm-sector-first-stage-disconnect-brainstorm.md`
