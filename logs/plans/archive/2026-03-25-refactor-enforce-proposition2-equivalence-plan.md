---
title: "refactor: Enforce Proposition 2 Aggregation Equivalence in Script 52"
type: refactor
status: completed
date: 2026-03-25
origin: paper/review_aggregation.tex
---

# Enforce Proposition 2 Aggregation Equivalence in Script 52

## Overview

Script 52 (`52_aggregated_firm_sector_first_stage.R`) tests whether the firm-level
OLS and cell-averaged OLS produce the same coefficient estimates --- the claim
formalized as Proposition 2 in `paper/review_aggregation.tex`. Currently all 16
empirical tests **FAIL**, with coefficient deviations of 0.005--0.20 (tolerance:
1e-8). This plan redesigns the Proposition 2 mode so that every enforceable condition
is applied on real data (C1--C5), while documenting the inherent limits of
real-data equivalence (C6: within-cell regressor heterogeneity). The synthetic
benchmark validates the math at machine precision; the real-data tiers show
how much of the gap is reducible by sample and FE restrictions versus how much
is intrinsic to the data structure.

## Problem Statement / Motivation

Proposition 2 is the theoretical foundation linking the firm-level first stage to
the sector-level first stage. If we cannot demonstrate the equivalence holds under
controlled conditions, the aggregation step is not validated. The current script 52
attempts the test but does not enforce all four conditions simultaneously, so it is
unclear whether the gap is a math/code bug or a genuine data violation.

The user needs to:
1. **Understand the math**: see which conditions matter and why.
2. **Verify the code**: confirm that under ideal conditions the equivalence is exact.
3. **Diagnose the data**: quantify how much each real-data violation costs.

## Mathematical Framework

### The Population Identity

Firm-level equation (script 51):

```
Y_fmt = Sum_l lambda_l * FA^l_fmt + gamma_f + alpha_mt + u_fmt        (1)
```

Average both sides over firms f in cell c = (j, m, e) with |F^pre_c| = N_c:

```
Y_bar_ct = Sum_l lambda_l * FA_bar^l_ct + gamma_bar_c + alpha_mt + eps_ct   (2)
```

where `gamma_bar_c = (1/N_c) Sum_f gamma_f` and `eps_ct = (1/N_c) Sum_f u_fmt`.

The **same** lambda_l appears because averaging is linear and lambda is common
to all firms. This is the population identity --- it holds exactly.

### When Are the *Estimated* Coefficients Identical?

The OLS estimator from (1) and the N_c-weighted OLS from (2) coincide if and
only if the between-cell normal equations are identical:

```
Firm-level between-cell:   Sum_c N_c * X_tilde_bar_c' (Y_tilde_bar_c - X_tilde_bar_c * lambda) = 0
Cell-level N_c-weighted:   Sum_c N_c * X_tilde_bar_c' (Y_tilde_bar_c - X_tilde_bar_c * lambda) = 0
```

These are the same equation. But they produce the same solution **only if**:

1. **(C1) Correct weighting.** The cell regression uses analytic weight N_c.
   Without it, large cells are under-represented relative to the firm regression.

2. **(C2) Same sample.** Both regressions use the identical set of firm-year
   observations. Differential singleton absorption (`fixef.rm` default in fixest)
   or different NA filters break this.

3. **(C3) FE nesting / firm immobility.** Each firm maps to exactly one cell
   (j, m) across all years. If firm f appears in cells c1 and c2, the firm FE
   gamma_f links them, but the cell FEs gamma_bar_c1 and gamma_bar_c2 are
   independent --- the between-cell decomposition breaks.

4. **(C4) Correct aggregated FE structure.** The aggregated FE must absorb
   gamma_bar_c = (1/N_c) Sum_f gamma_f. Since the firm set F^pre_c changes
   across election cycles, gamma_bar_c is a (muni x sector x election_cycle)
   constant. The aggregated FE must be at least this granular. The muni x year
   FE alpha_mt is the same on both sides.

5. **(C5) Fixed cell composition within regime.** Within each support regime
   (election cycle), the set of firms in each cell must be constant across years.
   If firms enter/exit the panel within a regime, gamma_bar_ct varies by year
   even though the cell FE absorbs only one constant per regime.

6. **(C6) No within-cell regressor heterogeneity after FE projection.** Even
   when C1--C5 hold, the between-within decomposition requires that within-cell
   variation in the FE-projected regressors does not contribute to the normal
   equations. In the firm-level regression, firm FE absorbs the firm-specific
   mean of FA^l_fmt across time. If FA^l_fmt varies across firms within the
   same cell-year (i.e., different firms in the same (j, m, t) have different
   party exposure), the firm-level projection removes different amounts of
   variation than the cell-level projection. Machine-precision equivalence on
   real data requires that the regressor path is losslessly aggregated --- i.e.,
   FA^l_fmt is constant within cell-year after FE projection, or equivalently,
   within-cell between-firm variation in the projected regressors is zero.

   In the existing synthetic benchmark (`verify_proposition2_synthetic.R`), exact
   equality (1e-15) was achieved only after making FA constant within cell-year.
   On real data, firms within the same (sector, muni, year) cell have different
   owner-party exposure shares, so C6 is inherently violated. This means
   **machine-precision equivalence is achievable only on synthetic data** where
   C6 can be imposed by construction. On real data, even with C1--C5 fully
   enforced, a residual gap from within-cell regressor heterogeneity will remain.

### Condition Summary Table

| # | Condition | Firm side | Aggregated side | Currently enforced? |
|---|-----------|-----------|-----------------|---------------------|
| C1 | Weighting | (implicit: each firm gets weight 1) | `weights = ~N_pre` | Yes (in Prop2 mode) |
| C2 | Same sample | F_pre filter + `fixef.rm = "none"` | Same F_pre + `fixef.rm = "none"` | **Partial** --- `fixef.rm = "none"` not used |
| C3 | Firm immobility | Restrict to single-cell firms | Same restriction | **No** --- 20% of firms are multi-cell |
| C4 | Correct FE | `firm_id + muni_id^year` | `muni_id^sector^support_regime + muni_id^year` | **Approximate** --- `FE_AGG_EXACT` exists |
| C5 | Fixed composition | Balanced panel within regime | Same balanced panel | **No** --- firms enter/exit within regimes |
| C6 | Regressor homogeneity | (inherently violated: firms differ in FA) | (cell mean != individual values) | **No** --- cannot be enforced on real data |

### Employment-Weighted Variant

For employment-weighted firm-level OLS, the equivalence requires:

- Cell averages are employment-weighted: `H^emp = Sum(n_emp * Y) / Sum(n_emp)`
- Cell regression uses total cell employment E_c = Sum(n_emp) as weight
- All other conditions (C2--C6) still apply
- **Additional condition (C7-emp)**: within-cell employment shares must be stable
  over time. The employment-weighted firm-level OLS weights each firm-year by
  `n_emp_ft`. When aggregated, the cell weight is `E_ct = Sum_f n_emp_ft`. If
  employment shares shift within a cell across years (e.g., one firm grows while
  another shrinks), the effective weighting of the cell changes by year, but the
  aggregated regression uses a single E_c per cell. Balanced firm presence alone
  does not guarantee stable employment shares. This makes the employment-weighted
  equivalence strictly harder to achieve than the unweighted case, even on
  synthetic data.

## Proposed Solution

### Design Principle

Create three nested test tiers within script 52's `--proposition2` mode:

| Tier | Name | Restrictions | Expected gap |
|------|------|-------------|--------------|
| **Gold** | Synthetic benchmark | Synthetic DGP with C1--C6 all enforced (FA constant within cell-year) | < 1e-8 |
| **Silver** | Maximal real-data restrictions | Single-cell + balanced-within-regime + fixef.rm="none" + exact FE + N_c weights | Small but nonzero (C6 violated) |
| **Bronze** | Full-sample real-data | All firms + fixef.rm="none" + exact FE + N_c weights | ~0.03 |

The **Gold** tier (synthetic only) validates the mathematical proposition. The
**Silver** tier enforces every condition that CAN be enforced on real data
(C1--C5); its residual gap reflects within-cell regressor heterogeneity (C6),
which is inherent to the data and not a code or design flaw. The **Bronze**
tier shows the full real-data gap.

**Important**: Silver→Bronze is a nested restriction comparison, not an additive
decomposition. Relaxing single-cell + balanced simultaneously changes sample
support, FE support, and instrument variation. The gap difference between tiers
is informative about the joint effect of all relaxed conditions, not attributable
to any single violation.

### What "Single-Cell" Means

A firm is "single-cell" if it appears in exactly one (muni_id, sector) pair across
**all years in the F_pre-filtered sample**. Operationally:

```r
cell_count <- dt_pre[, .(n_cells = uniqueN(paste(muni_id, sector))), by = firm_id]
single_cell_firms <- cell_count[n_cells == 1L, firm_id]
dt_single <- dt_pre[firm_id %in% single_cell_firms]
```

### What "Balanced Within Regime" Means

Within each support regime, every firm must be present in ALL years of that regime.
This ensures the cell composition is truly fixed:

```r
regime_years <- dt_single[, .(all_years = list(sort(unique(year)))), by = support_regime]
dt_balanced <- dt_single[, {
  expected_years <- regime_years[support_regime == .BY$support_regime, all_years][[1]]
  firm_years <- .SD[, .(present_years = list(sort(unique(year)))), by = firm_id]
  balanced_firms <- firm_years[sapply(present_years, function(py) identical(py, expected_years)), firm_id]
  .SD[firm_id %in% balanced_firms]
}, by = support_regime]
```

## Technical Considerations

### FE Structure Verification

The current `FE_AGG_EXACT` is `muni_id^sector^support_regime + muni_id^year`.
This should correctly absorb gamma_bar_c under conditions C3+C5 because:

- `muni_id^sector^support_regime` is one dummy per (muni, sector, regime) triple
- Within a regime, with fixed cell composition, gamma_bar_c is constant
- `muni_id^year` absorbs alpha_mt, same as the firm side

The `support_regime` is built from `build_support_regime_map()`, which maps each
year to a unique label based on the union of all applicable baseline years. This
correctly captures the election-cycle dimension because the F_pre firm set is
determined by baseline years.

### `fixef.rm = "none"` Implications

- Prevents fixest from dropping singleton groups (firms/cells that appear only once
  in a FE dimension)
- Without it, the firm-level regression may drop ~900K observations that the
  aggregated regression keeps (or vice versa), violating C2
- Performance impact: minimal --- singleton removal is a speed optimization, not
  a correctness requirement
- Numerical impact: may increase condition number of the FE projection matrix, but
  fixest handles this well

### Degrees of Freedom Check

For a (muni, regime) block with K sectors and T years:
- Cell FE: K parameters (one per sector within the muni-regime block)
- Muni x year FE: T parameters
- Overlap: 1 (the muni-regime intercept is absorbed by both)
- Net FE: K + T - 1
- Observations: K x T (balanced)
- Residual df: (K-1)(T-1)

Need K >= 2 and T >= 2 for identification. Cells with K=1 or T=1 are singletons
under the FE structure and will be dropped (or kept with `fixef.rm = "none"` but
won't contribute to identification).

### Sample Size Impact (Estimated)

Based on current diagnostics:
- Full F_pre sample: ~24M firm-year obs, ~482K cells
- Single-cell restriction: ~15M obs (~64% retained), ~309K cells
- Balanced-within-regime: ~10-12M obs (~50% of single-cell), ~200-250K cells

These are rough estimates; exact numbers will be reported by the diagnostic output.

## Acceptance Criteria

### Synthetic Benchmark (Gold)

- [x] Gold tier (synthetic, already in `verify_proposition2_synthetic.R`): `max |diff| < 1e-8` for all specs
- [x] Confirms that the mathematical proposition is correctly implemented when C1--C6 hold

### Real-Data Tier Comparison

- [x] Silver tier: gap is strictly smaller than Bronze, confirming that enforcing C1--C5 reduces the deviation
- [x] Silver tier residual is documented as the irreducible effect of within-cell regressor heterogeneity (C6)
- [x] Report a table with columns: tier, alignment, exposure, weighting, max_abs_diff, N_firm_obs, N_cells
- [x] Employment-weighted variant included (E_c weights + emp-weighted averages), with caveat that stable employment shares (C7-emp) are also violated

### Output Artifacts

- [x] Gold tier validated by existing `verify_proposition2_synthetic.R` (no new artifact needed)
- [x] `prop2_tier_comparison.csv` --- gap by tier, alignment, exposure (nested restriction comparison, not decomposition)
- [x] `prop2_sample_restriction_summary.csv` --- how many firms/obs survive each restriction
- [x] LaTeX/md comparison tables for each tier (same format as current `prop2_equiv_*` tables)

### Code Quality

- [x] No changes to default (non-Prop2) mode behavior
- [x] New flags: `--single-cell`, `--balanced` (only active in `--proposition2` mode)
- [x] `fixef.rm = "none"` applied to ALL feols calls in Prop2 mode (both firm and agg)
- [x] Mathematical conditions documented in code comments

## Implementation Phases

### Phase 1: Add `fixef.rm = "none"` to Prop2 Mode

**File**: `52_aggregated_firm_sector_first_stage.R`

In `run_feols_model()`, add a `fixef_rm` parameter (default `NULL`, which
preserves fixest's default behavior of `"singletons"`). In Prop2 mode, pass
`fixef_rm = "none"` which adds `fixef.rm = "none"` to the feols call. Valid
fixest values for `fixef.rm` are `"none"`, `"singletons"`, and `"perfect_fit"`.

```r
# In run_feols_model():
if (!is.null(fixef_rm)) {
  fit_args$fixef.rm <- fixef_rm
}
```

Update all Prop2-mode calls to pass `fixef_rm = "none"`.

**Test**: Re-run current Prop2 test. Gap should barely change (confirming the
diagnostic finding that singleton absorption is not the main driver).

### Phase 2: Add Single-Cell Filter

Add a function `filter_single_cell_firms()`:

```r
filter_single_cell_firms <- function(dt, sector_col) {
  cell_ids <- dt[, paste(muni_id, get(sector_col), sep = "_")]
  firm_cells <- dt[, .(n_cells = uniqueN(paste(muni_id, get(sector_col), sep = "_"))), by = firm_id]
  single <- firm_cells[n_cells == 1L, firm_id]
  cat(sprintf("  Single-cell filter: %d / %d firms (%.1f%%), %d / %d obs (%.1f%%)\n",
              length(single), uniqueN(dt$firm_id),
              100 * length(single) / uniqueN(dt$firm_id),
              sum(dt$firm_id %in% single), nrow(dt),
              100 * sum(dt$firm_id %in% single) / nrow(dt)))
  dt[firm_id %in% single]
}
```

Add `--single-cell` CLI flag. When active, apply the filter before BOTH the
firm-level and aggregated regressions.

**Test**: Silver tier gap should drop from ~0.033 to ~0.011 (matching the existing
diagnostic finding for single-cell firms).

### Phase 3: Add Balanced-Within-Regime Filter

Add a function `filter_balanced_within_regime()`:

```r
filter_balanced_within_regime <- function(dt) {
  # For each support_regime, find years that should be present
  regime_year_list <- dt[, .(years = list(sort(unique(year)))), by = support_regime]

  # For each firm x regime, check if firm has all years
  firm_regime_years <- dt[, .(
    present = list(sort(unique(year)))
  ), by = .(firm_id, support_regime)]

  firm_regime_years[regime_year_list, expected := i.years, on = "support_regime"]
  balanced <- firm_regime_years[mapply(identical, present, expected)]

  keep_keys <- balanced[, .(firm_id, support_regime)]
  dt_out <- dt[keep_keys, on = .(firm_id, support_regime), nomatch = 0L]

  cat(sprintf("  Balanced filter: %d / %d obs (%.1f%%)\n",
              nrow(dt_out), nrow(dt), 100 * nrow(dt_out) / nrow(dt)))
  dt_out
}
```

Add `--balanced` CLI flag. Only meaningful with `--single-cell`.

**Test**: Silver tier gap should be smaller than Bronze. The residual reflects
within-cell regressor heterogeneity (C6), which cannot be eliminated on real data.

### Phase 4: Three-Tier Comparison Loop

Restructure the Prop2 estimation to loop over tiers. Note: these are **nested
restriction comparisons**, not an additive decomposition. Each step changes
sample support, FE support, and instrument variation jointly.

```r
tiers <- list(
  list(name = "bronze", label = "Full sample",
       filter_fn = identity),
  list(name = "silver", label = "Single-cell + balanced",
       filter_fn = function(d) filter_balanced_within_regime(filter_single_cell_firms(d, SCOL)))
)

comparison_rows <- list()
for (tier in tiers) {
  dt_tier <- tier$filter_fn(dt_pre_copy)
  # Run firm-level and aggregated regressions with fixef.rm = "none"
  # Record gap for each alignment x exposure combo
  # Append to comparison_rows
}
```

The Gold tier (synthetic benchmark) is already implemented in
`verify_proposition2_synthetic.R` and should be referenced, not re-implemented
within script 52.

Output: `prop2_tier_comparison.csv` with columns:
`tier, alignment, exposure, weighting, max_abs_diff, firm_obs, agg_cells,
 firm_retained_pct`

### Phase 5: Presentation Table

Generate a single summary Beamer table showing the tiers:

```
| Tier   | Restrictions Applied               | Max |Delta hat_beta| | Notes |
|--------|-------------------------------------|---------------------|-------|
| Gold   | Synthetic DGP (C1-C6 enforced)      | 1.0e-15             | Validates math |
| Silver | Single-cell + balanced + no-rm + FE | TBD (small)         | Best achievable on real data |
| Bronze | Full sample + no-rm + FE            | ~0.033              | Baseline real-data gap |
```

The Gold row references the existing synthetic verification. The Silver-to-Bronze
gap is a **joint effect** of relaxing the single-cell, balanced-panel, and
composition constraints simultaneously --- it should NOT be decomposed into
additive "sources."

## System-Wide Impact

- **Script 51**: No changes. Script 52 runs its own firm-level regression internally.
- **Script 53/54**: No changes. These use the sector-level shift-share design,
  not the aggregated firm design.
- **Default mode of script 52**: No changes. New flags only affect `--proposition2`.
- **Diagnostics**: Existing `diagnose_proposition2_gap.R` and
  `verify_proposition2_synthetic.R` remain valid but become redundant once the
  decomposition is built into script 52.

## Dependencies & Risks

1. **Data loss risk**: The gold-tier balanced filter may retain only ~50% of the
   single-cell sample. If too few observations survive, the regression may fail
   or produce unreliable estimates. Mitigation: report sample sizes and skip
   tiers with insufficient data.

2. **Collinearity risk**: Restricting the sample may cause some FA_* instruments
   to become collinear (especially with `fixef.rm = "none"`). Mitigation: fixest
   reports collinear variables; log them in the decomposition output.

3. **support_regime correctness**: If the support_regime mapping doesn't perfectly
   capture election cycles, the gold-tier test may fail despite correct
   implementation. Mitigation: verify the mapping manually against known election
   years before running.

4. **Employment-weighted equivalence**: The E_c-weighted test requires
   employment-weighted cell averages AND E_c regression weights AND all conditions
   C2--C6 AND stable within-cell employment shares (C7-emp). On real data,
   employment shares shift within cells over time, so even with all other
   conditions enforced, the employment-weighted gap will be larger than the
   unweighted gap. The employment-weighted Silver tier should be interpreted as
   an upper bound on achievable precision, not expected to reach machine
   precision. Only on synthetic data with fixed employment can it pass.

## Sources & References

### Internal

- `paper/review_aggregation.tex` — Proposition 2 proof (Sections 2--3)
- `paper/comparison_firm_agg.tex` — Current empirical results (6-slide Beamer)
- `BNDES/politicsregs/5_estimation/52_aggregated_firm_sector_first_stage.R` — Script to modify
- `BNDES/politicsregs/diagnostics/verify_proposition2_synthetic.R` — Synthetic validation (confirms Prop 2 works at 1e-15 under ideal conditions)
- `BNDES/politicsregs/diagnostics/diagnose_proposition2_gap.R` — Real-data gap diagnostics

### Key Diagnostic Findings (from existing outputs)

| Diagnostic | Value |
|-----------|-------|
| Multi-cell firms | 819,259 (20.0%) |
| Multi-cell obs share | 36.1% |
| Gap (full sample, relaxed FE) | 0.033 |
| Gap (full sample, exact FE) | 0.012 |
| Gap (single-cell, fixef.rm=none) | 0.011 |
| Gap (synthetic, all conditions) | 1.0e-15 |

### Related Plans

- `docs/plans/2026-03-25-feat-proposition2-aggregation-equivalence-test-plan.md`
- `docs/plans/2026-03-25-feat-simplify-proposition2-test-plan.md`
- `docs/brainstorms/2026-03-14-firm-sector-first-stage-disconnect-brainstorm.md`
