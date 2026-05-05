# Session Log: 2026-04-29 -- Anderson-Rubin Baseline Implementation

**Status:** IN PROGRESS

## Objective

Implement the pooled Anderson-Rubin test of H0: BNDES sectoral allocation has
no first-order effect on municipal GDP. Deliverable is
`explorations/anderson_rubin/ar_baseline.R` running the primary spec (K = 4
mayor, log_gdp, no controls, owner-count weights, cycle-specific baseline,
coalition alignment), the controls ladder (C1 / C2 / C3 / C4), the R0–R4
sensitivity grid, grouped AR diagnostics, and the F1 / F2 / F7 falsification
battery. Full specification in `logs/plans/2026-04-29_ar-baseline-implementation.md`.

Plan approved on 2026-04-29; entering implementation.

## Changes Made

| File | Change | Reason | Quality Score |
|------|--------|--------|---|
| `explorations/anderson_rubin/README.md` | Created; populated with goal, primary spec, hypotheses (1)-(7), success criteria | Step 3 of implementation plan | N/A |
| `explorations/anderson_rubin/SESSION_LOG.md` | Created; opening entry | Step 3 of implementation plan | N/A |
| `explorations/anderson_rubin/output/.gitkeep` | Created; marks empty output directory for git tracking | Step 3 of implementation plan | N/A |

## Design Decisions

| Decision | Alternatives Considered | Rationale |
|----------|------------------------|-----------|
| Primary outcome = `log_gdp` (not `log_gdp_pc`) | `log_gdp_pc` as primary | USER-MANDATED 2026-04-29; avoids population-denominator measurement error |
| No controls in primary spec | Muni FE + year FE as primary (strategy memo default) | USER-MANDATED 2026-04-29; FE spec demoted to C1 on the controls ladder |
| K = 4 (mayor-only) as primary | K = 8, K = 12 | Retained per strategy memo §3; tier ascent is R3 sensitivity |
| `policy_block` taxonomy (4 sectors) | `bndes_sector` | Strategy memo §7 BLOCKER resolved; `policy_block` is wired end-to-end through scripts 30e-41 |

## Incremental Work Log

**2026-04-29:** Step 3 complete — exploration scaffolding created
(`README.md`, `SESSION_LOG.md`, `output/`). `ar_baseline.R` not yet written
(Step 4). Panel B patch for `ec_total_*` columns not yet applied (Step 1).

## Learnings & Corrections

- [LEARN:pipeline] The strategy memo's Section 7 BLOCKER (`bndes_sector` not
  wired) is RESOLVED in Phase 0 — `policy_block` is the active taxonomy.
- [LEARN:spec] Primary spec has NO fixed effects; between-muni cross-sectional
  variation (interacted with within-period alignment turnover) drives
  identification in the primary. C1 (FE-only) isolates within-muni variation.
  Comparing primary vs C1 is informative about which variation source drives
  the result.
- [LEARN:ec] Only `ec_total_*` (muni-total EC, R0a) is missing from Panel B
  at plan time; sector-specific EC columns (R0b) already exist. Step 1 adds
  the row-sum block to script 41.

## Verification Results

| Check | Result | Status |
|-------|--------|--------|
| `policy_block` wired through scripts 30e/31/32/33/34/35/41 | Confirmed by Phase 0 code reads | PASS |
| Sector-specific EC columns present in Panel B | 96 columns (24 stems x 4 sectors) | PASS |
| `ec_total_*` columns present in Panel B | NOT present at plan time; Step 1 adds them | PENDING |
| `ar_baseline.R` runs without errors | Not yet run | PENDING |
| Output files produced | Not yet generated | PENDING |

## Open Questions / Blockers

- [ ] F2 lead horizon: plan defaults to +4 years; user may override to +2.
- [ ] F7 pre-period: plan uses 2002-2004 muni averages; confirm or override
  to 2002 only.
- [ ] Confirm `baseline_sector_weights_policy_block.qs2` exists on disk before
  running Step 1 (script 41); if not, rebuild from scripts 30e, 31, 33, 34, 35
  first.

## Next Steps

- [ ] Step 1: Patch `scripts/R/4_regression_panels/41_build_muni_panel.R` —
  add `ec_total_*` row-sum block after line ~742.
- [ ] Step 2: Patch `scripts/R/diagnostics/audit_41_muni_panel.R` — add
  `ec_total` presence and identity checks.
- [ ] Step 4: Write `explorations/anderson_rubin/ar_baseline.R`.
- [ ] Step 7: Rebuild Panel B, run audit, run AR script, verify outputs.

## Unit 5 Addendum: Weight Horserace

**2026-04-29:** Unit 5 weight horserace implemented. Added
`weight_horserace.R`, built three muni-normalized weights (`emp_muni`,
`bin_muni`, `own_muni`) using all municipal firms in the employment
denominator, treated missing party affiliation as zero affiliation, deferred
`2002_fixed`, and ran the 4 weights x 5 tier specs x 4 controls grid. Outputs
saved in `output/ar_horserace_*`. A reusable cache of the new wide Z columns
was saved as `output/ar_horserace_new_z_wide.qs2` to avoid rebuilding the
40.7M-row reconstructed panel for output-only reruns.

### Unit 5 Verification

| Check | Result | Status |
|-------|--------|--------|
| Script parses | `Rscript explorations/anderson_rubin/weight_horserace.R --dry-run` | PASS |
| Full build/run | `Rscript explorations/anderson_rubin/weight_horserace.R --force-rebuild`, then cache reruns | PASS |
| Result rows | 80 rows; 80 unique `(weight_id, tier_spec, controls)` specs; 0 failed statuses | PASS |
| Coefficient rows | 576 instrument-coefficient rows; all estimated | PASS |
| Diagnostics rows | 20 `(weight_id, tier_spec)` rows | PASS |
| Replication anchor | owner_legacy mayor none F = 123.184946804876 vs `ar_results.csv` F = 123.184946804925 | PASS |
