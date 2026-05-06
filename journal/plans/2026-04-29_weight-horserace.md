---
status: APPROVED
date: 2026-04-29
author: Claude (planner)
phase: exploration
related:
  - logs/plans/2026-04-29_ar-baseline-implementation.md
  - logs/strategy/strategy_memo_ar_test.md
  - explorations/anderson_rubin/ar_baseline.R
  - scripts/R/3_instruments/31_build_sector_exposure_weights.R
  - scripts/R/3_instruments/33_select_baseline_weights.R
  - scripts/R/3_instruments/34_build_shift_share_instruments.R
target_artifact: explorations/anderson_rubin/weight_horserace.R
mode: simplified (workflow.md §2 — Simplified Mode for R Scripts / Explorations)
context:
  - Units 1-4 of the AR-baseline plan are complete (primary + C1/C2/C3/C4 ladder for K=4 mayor / coalition / cycle / owner / log_gdp)
  - This plan finalizes Unit 5 by adding three muni-normalized weights and tier ascent under the same controls ladder
  - Units 6 and 7 deferred per user 2026-04-29
user_decisions_locked:
  - 5 tier specs: mayor, gov, mayor_gov, mayor_pres, mayor_gov_pres (pres-only dropped 2026-04-29)
  - 3 new weights + 1 legacy: emp_muni, bin_muni, own_muni, owner (sector-normalized continuity row)
  - Baseline pooling = script-33-consistent (pool counts and denominators across baseline window, divide once)
  - E_mB denominator = all municipal firms, including firms outside policy_block
  - Missing affiliation = no affiliation; keep firms in denominators with zero affiliation contribution
  - Baseline type for this pass = cycle_specific only; 2002_fixed deferred
  - AR reporting = F-stat with visible p-value; save instrument coefficients from every spec
  - No pipeline rebuild; one exploration script reproduces script-31/33/34 math in-file
  - Gov/pres elections share timing — single gov_pres EC bucket is correct, not asymmetric
---

# Plan: AR Weight Horserace + Tier Ascent (Unit 5 Finalization)

## Status

APPROVED for implementation after user decisions on 2026-04-29.

## Goal

Build `explorations/anderson_rubin/weight_horserace.R` that:

1. Constructs three new shift-share weights from RAIS+affiliation raw inputs.
2. Combines with the existing `alignment_shocks.qs2` to build sector-level instruments at policy_block × {mayor, gov, pres} × coalition × cycle_specific.
3. Joins the new instruments onto the existing Panel B (which already has `log_gdp`, EC controls, and the legacy `owner`-weight Z columns).
4. Runs primary + controls ladder × 5 tier specs × 4 weights = **80 spec rows**.
5. Emits presentation-ready outputs plus a coefficient dump (CSV, coefficient CSV, bare TeX, Markdown).

## Why no full pipeline rebuild

Pushing three weights through scripts 31 → 33 → 34 → 41 would inflate Panel B by ~150 columns and trigger a multi-hour rebuild. Exploration mode justifies replicating the math in one file. If results warrant, graduate to the pipeline post-meeting.

## New weight formulas (script-33-consistent pooling)

For firm `f`, treatment_year `T`, baseline window `B(T)`:

```
n_fB        = Σ_{t ∈ B(T)} n_ft                 (firm employment summed across baseline)
E_mB        = Σ_{t ∈ B(T)} E_mt                 (muni employment summed across baseline)
aff_count_fpB     = Σ_{t ∈ B(T)} aff_count_fpt  (party-p owner count, pooled)
total_owners_fB   = Σ_{t ∈ B(T)} total_owners_ft (firm total owners, pooled)
1_fpB       = 𝟙{aff_count_fpB > 0}              (firm-baseline binary affiliation)
```

`E_mB` includes all municipal firm employment in the baseline window, including firms outside the policy_block mapping. Firms with no observed affiliation are treated as unaffiliated: they remain in denominators and contribute zero to affiliated numerators.

Then for each `(m, j, p, T, baseline_type = cycle_specific)`:

| Weight | Formula |
|---|---|
| `emp_muni` | `w_mjp = (Σ_{f ∈ (m,j)} n_fB · θ_fpB) / E_mB` where `θ_fpB = aff_count_fpB / total_owners_fB` |
| `bin_muni` | `w_mjp = (Σ_{f ∈ (m,j)} n_fB · 1_fpB) / E_mB` |
| `own_muni` | `w_mjp = L_mjpB / L_mB` where `L_mjpB = Σ_f aff_count_fpB`, `L_mB = Σ_{f ∈ m} total_owners_fB` |
| `owner` (legacy) | from existing `ar_Z_mayor_coalition_cycle_specific_<sec>` on Panel B; one continuity row per tier spec |

**Pooling identity proof (sum-to-1).** For `emp_muni` and `own_muni`, summing `w_mjp` over affiliated parties `p` within `(m, j)` yields `(Σ_f n_fB) / E_mB · 1` and `(Σ_f total_owners_fB · 1) / L_mB · 1` respectively, which collapse to bounded fractions ≤ 1. Pooling-then-dividing once is the unique convention that preserves this property; year-mean-of-ratios breaks it.

`bin_muni` is not constrained to sum to 1 by design — same logic as the existing legacy `binary` weight.

Only one baseline_type is built in this pass: `cycle_specific`. The `2002_fixed` sensitivity is explicitly deferred.

## Instrument construction (script-34-consistent)

For each tier ∈ {mayor, gov, pres} and align ∈ {coalition} (party deferred):

1. Merge weights with `alignment_shocks.qs2` on (muni_id, party, treatment_year=year).
2. Compute `Z_mjp = w_mjp × align_<tier>_<align>` and `dZ_mjp = w_mjp × dalign_<tier>_<align>`.
3. **Tier restriction:** apply weights only on the tier's matching baseline rows (mayor weights × mayor shocks; gov/pres weights × gov_pres-tier shocks — script 33's tier partition).
4. Aggregate over parties: sum `Z_mjp` over `p` within `(m, j, T, baseline_type = cycle_specific)`.
5. Spread `Z` across the 4-year electoral term using the same `term_map` as script 34. `dZ` stays at inauguration year.
6. Filter to 2002–2017.
7. Pivot wide: `Z_mjt → ar_Z_<infix>_<tier>_<align>_<baseline>_<sector>` with infixes `empmuni_`, `binmuni_`, `ownmuni_`.

## Spec grid (80 rows)

| Axis | Levels | K |
|---|---|---|
| Tier | mayor / gov / mayor_gov / mayor_pres / mayor_gov_pres | 4 / 4 / 8 / 8 / 12 |
| Controls | none / C1 (FE) / C2 (FE+R0a) / C3 (FE+R0b) | — |
| Weight | emp_muni / bin_muni / own_muni / owner_legacy | — |
| Fixed | align=coalition, baseline=cycle_specific, time_var=Z, outcome=log_gdp, cluster=muni_id | — |

5 × 4 × 4 = **80 spec rows.**

**Tier-specific column lookups.** For each tier spec, the EC controls already on Panel B are:

| Tier spec | C2 column(s) | C3 columns |
|---|---|---|
| mayor | `ec_total_mayor_cycle_specific` | 4× `ar_exposure_control_mayor_cycle_specific_<sec>` |
| gov | `ec_total_gov_pres_cycle_specific` | 4× `ar_exposure_control_gov_pres_cycle_specific_<sec>` |
| mayor_gov | both above | 8 columns |
| mayor_pres | both above | 8 columns |
| mayor_gov_pres | both above | 8 columns |

EC controls do NOT need to match the AR weight — they enter as confounders regardless of which Z weight design is being tested.

## Output schema

### `output/ar_horserace_results.csv` — machine-readable, 80 rows

| Column | Type | Note |
|---|---|---|
| `weight_id` | character | `emp_muni` / `bin_muni` / `own_muni` / `owner_legacy` |
| `tier_spec` | character | `mayor` / `gov` / `mayor_gov` / `mayor_pres` / `mayor_gov_pres` |
| `K` | integer | 4 / 4 / 8 / 8 / 12 |
| `controls` | character | `none` / `C1_FE` / `C2_FE_R0a` / `C3_FE_R0b` |
| `f_stat`, `p_value`, `df1`, `df2` | numeric | from `fixest::wald` |
| `n_obs`, `n_clusters` | integer | |
| `r2` | numeric | within-R² for FE specs, overall R² for `none` |
| `sig_marker` | character | `***`/`**`/`*`/empty |
| `reject_05` | logical | p < 0.05 indicator |

### `output/ar_horserace_coefficients.csv` — coefficient dump

One row per AR instrument coefficient per spec:

| Column | Type | Note |
|---|---|---|
| `weight_id` | character | `emp_muni` / `bin_muni` / `own_muni` / `owner_legacy` |
| `tier_spec` | character | `mayor` / `gov` / `mayor_gov` / `mayor_pres` / `mayor_gov_pres` |
| `K` | integer | 4 / 4 / 8 / 8 / 12 |
| `controls` | character | `none` / `C1_FE` / `C2_FE_R0a` / `C3_FE_R0b` |
| `variable` | character | AR instrument column name |
| `tier` | character | mayor / gov / pres, parsed from the coefficient name |
| `sector` | character | policy_block sector suffix, parsed from the coefficient name |
| `estimate`, `std_error`, `t_stat`, `p_value` | numeric | from `fixest::coeftable` |
| `ci_low`, `ci_high` | numeric | 95% confidence interval |

### `output/ar_horserace_summary.tex` — bare tabular for paper / appendix

Four sub-panels (Panel A: emp_muni, B: bin_muni, C: own_muni, D: owner_legacy):
- Rows: 5 tier specs
- Columns: F_none, F_C1_FE, F_C2_FE_R0a, F_C3_FE_R0b, each as F-stat with stars and visible p-value (`F*** [p=...]`)
- Bare `tabular`, booktabs rules only (INV-3, INV-13)

### `output/ar_horserace_summary.md` — Markdown for slide deck

Same structure as TeX but pipe-tables, with visible AR p-values in each cell. Designed to copy-paste directly into a Beamer/Quarto slide. Includes a one-line "interpretation hint" footer per panel (e.g., "all 5 specs reject H0 at 5%").

### `output/ar_horserace_diagnostics.csv` — one row per (weight, tier spec)

Per-weight sanity diagnostics: `weight_mean`, `weight_sd`, `share_nonzero_obs_per_sector`, `n_munis_with_nonzero_Z_per_sector`, `cluster_count_after_demean`. Helps explain F-stat ordering across weights.

### `output/ar_horserace_console_table.txt`

Printed during script run for instant scan; also saved for the session log.

## Implementation sketch

```r
# 1. Packages, seed, paths (INV-14, INV-15, INV-16)
# 2. Load inputs:
#    - rais_bndes_reconstructed.fst (firm × year × muni × policy_block × n_employees)
#    - owner_aff_firm_year_party_2002_2019.qs2 (firm × year × party owner counts)
#    - alignment_shocks.qs2 (muni × party × year alignment levels + changes)
#    - muni_panel_for_regs_policy_block.qs2 (Panel B with log_gdp, EC, legacy owner Z)
# 3. Build firm-baseline aggregates per (firm, treatment_year, baseline_type = cycle_specific):
#    n_fB, E_mB, aff_count_fpB, total_owners_fB, 1_fpB
#    Apply baseline windows from script 33 (mayor: 2002-03/04-07/08-11/12-15;
#    gov_pres: 2002-05/06-09/10-13).
# 4. Compute w_mjp for each new weight under the cycle_specific baseline
# 5. Merge alignment shocks; build Z, dZ at (m, j, p, T, baseline_type = cycle_specific)
# 6. Apply tier restriction (mayor weights only on mayor baseline rows; gov_pres
#    weights only on gov_pres baseline rows). Aggregate over p.
# 7. Spread Z across cycle term (term_map from script 34); filter 2002-2017
# 8. Pivot wide; merge with Panel B by (muni_id, year)
# 9. Helper: run_ar_spec(z_cols, fe_str, ctrl_cols, cluster) -> 1-row data.table
# 10. Build spec grid (CJ); iterate; rbindlist results
# 11. Compute significance markers; write results CSV / coefficient CSV / TeX / MD / diagnostics
# 12. Console summary table
```

## Verification (simplified-mode quality checklist, target ≥80)

- [ ] All 80 specs return finite F-stat (or explicitly logged degenerate-cell reason).
- [ ] Sum-to-1 sanity: `Σ_p w_mjp ≤ 1 + 1e-9` per (m, j) for `emp_muni` and `own_muni`.
- [ ] Pivot sanity: each new wide column has at least 1 nonzero observation per sector.
- [ ] **Replication anchor:** owner_legacy primary spec F-stat must match the existing `ar_results.csv` `primary` row F=123.18 (within 1e-3).
- [ ] Output files exist; results CSV row count = 80.
- [ ] Coefficient CSV exists and contains every AR instrument coefficient from every non-degenerate spec.
- [ ] No prohibited functions (INV-19), no absolute paths (INV-16), seed once (INV-14), packages at top (INV-15).
- [ ] Bare `tabular` output (no `\begin{table}` wrapper, no caption — INV-13).
- [ ] Console table prints in <5 sec at end of run.

## Resolved decisions (2026-04-29)

1. **`E_mB` denominator scope.** Use all municipal firms, including CNAE sections outside policy_block. This preserves the "share of municipal economy" interpretation.

2. **Firms with missing affiliation data.** Missing affiliation is no affiliation. Keep firms in denominators and assign zero affiliation contribution.

3. **`2002_fixed` baseline.** Do not build it now. Build and run `cycle_specific` only.

4. **Slide-table format detail.** Follow AR-test reporting practice: show the F-stat and visible p-value. Stars may remain as a visual cue, but p-values cannot live only in the CSV.

5. **Coefficient retention.** Save instrument coefficients from all non-degenerate specs in `ar_horserace_coefficients.csv` so selected estimates can be reported later.

## Files

| File | Status | Purpose |
|---|---|---|
| `explorations/anderson_rubin/weight_horserace.R` | NEW | The horserace script |
| `explorations/anderson_rubin/output/ar_horserace_results.csv` | NEW | Machine-readable spec grid |
| `explorations/anderson_rubin/output/ar_horserace_coefficients.csv` | NEW | Instrument coefficient dump for all specs |
| `explorations/anderson_rubin/output/ar_horserace_summary.tex` | NEW | Bare tabular for paper |
| `explorations/anderson_rubin/output/ar_horserace_summary.md` | NEW | Markdown for slides |
| `explorations/anderson_rubin/output/ar_horserace_diagnostics.csv` | NEW | Per-weight sanity stats |
| `explorations/anderson_rubin/output/ar_horserace_console_table.txt` | NEW | Saved console output |
| `explorations/anderson_rubin/SESSION_LOG.md` | UPDATE | Append Unit 5 entry |

No changes to existing scripts (31, 33, 34, 41) or to Panel B.

## Risks / Mitigation

| Risk | Mitigation |
|---|---|
| Replication anchor fails (owner_legacy primary F ≠ 123.18) | Indicates merge or filter discrepancy with `ar_baseline.R`. Rerun `ar_baseline.R` and diff; halt before claiming Unit 5 done. |
| Memory pressure: RAIS reconstructed at firm-year-party explodes per baseline window | Use baseline-pooled aggregates (one row per firm × T × baseline_type) before joining affiliation; expected peak memory ~3-4 GB. |
| Tier restriction logic mistake silently zeroing instruments | Add per-(weight, tier) diagnostic that asserts at least 70% of (m, j, t) cells have nonzero Z within each policy_block sector. |
