---
status: PROPOSED
date: 2026-05-05
author: Claude (planner)
phase: exploration
related:
  - logs/plans/2026-05-05_a7-revised-weight-comparison.md
  - logs/plans/2026-05-05_a7-weight-comparison-strategy.md
  - docs/PROJECT_BLUEPRINT.md (§4 A7)
target_artifact: explorations/anderson_rubin/diagnostics/a7_step0_coverage.R
mode: simplified (workflow.md §2 — Simplified Mode for R Scripts / Explorations)
aggregation_margin: policy_block (4 active bins: Agro, Ind, Infra, Serv; XX excluded)
context:
  - Reading scripts 31/33/34 on 2026-05-05 surfaced three silent imputation patterns the production pipeline does not separate:
    (i) all four current weights condition on the matched-only owner-data subset
    (ii) `w_mjp_emp` filters firms with `n_employees > 0`, dropping the 0-employment subpopulation entirely
    (iii) muni-sector cells with no matched firms produce `Z = 0`, identical to genuine zero exposure
  - This diagnostic is Step 0 of the revised A7 plan; it characterises the imputation/coverage structure of the existing instrument before any weight comparison runs
  - All work at `policy_block` only; size dimension deferred
---

# A7 Step 0 — Coverage and Imputation Diagnostic (policy_block)

## Status

PROPOSED for implementation as a fast-track exploration script.

## Goal

Characterise three forms of coverage and imputation that the current pipeline silently handles, at the `policy_block` aggregation level. Outputs feed the interpretation of the Step 1–5 weight comparison in the revised A7 plan: the correlation matrix and one-cycle F-stats are uninterpretable without knowing how much of the variation is driven by these imputation choices.

The diagnostic runs at policy_block marginals only (4 active bins: Agro, Ind, Infra, Serv). The size dimension is out of scope for this plan; if patterns at policy_block warrant it, a follow-up at S3 alone or `policy_block × S3` can be added.

## Why this is a prerequisite

Without this diagnostic, the weight comparison cannot distinguish:
- "Weight A correlates highly with weight B" because they are economically equivalent vs. because they share the same imputation bias
- "Weight A's first-stage F is high" because the underlying signal is real vs. because non-random missingness inflates it

Step 0 quantifies the bias structure. Step 1–5 then runs on cleaner ground.

## Three diagnostic outputs

### D-A: Affiliation-match coverage by `policy_block`

For each (`muni_id`, `policy_block`, `year`) cell, compute:
- `n_firms_rais` — count of firms in `firm_sector` (the RAIS+BNDES reconstructed panel)
- `n_firms_aff` — count of firms in `firm_sector` that also have a row in `owner_aff_firm_year_party_2002_2019.qs2` (any party, any aff_count) for the same (firm, year)
- `emp_rais` — `sum(n_employees)` across firms in `firm_sector` (`n_employees > 0` only)
- `emp_aff` — `sum(n_employees)` across firms with both RAIS and affiliation records (`n_employees > 0`)
- `match_rate_n = n_firms_aff / n_firms_rais`
- `match_rate_emp = emp_aff / emp_rais`

Aggregations:
- by `policy_block` (pooled across muni and year): mean, median, p10, p90 of both match rates
- by `policy_block × year`: median match rates (to check temporal stability)
- by `policy_block × muni size class` (small / medium / large munis based on `emp_rais` quartiles, pooled across years): median match rates (to check whether coverage is concentrated in particular muni types)

Output: `a7_coverage_by_policy_block.csv` — one row per (policy_block, year, muni_size_class) cell with both match rates plus the rais/aff counts.

Interpretation hint: if match rates differ across blocks (e.g., Agro 80% vs. Serv 50%), then any across-block instrument comparison carries sector-correlated bias.

### D-B: `Z = 0` decomposition for the production owner instrument

The current production muni-level instrument at `policy_block` is `Z_emp_owner_*` columns in `shift_share_instruments_policy_block.qs2` (or the equivalent on Panel B). For each (muni, year, baseline_type = cycle_specific) cell with `Z = 0` for the mayor coalition shock, decompose the cause into a priority hierarchy:

1. **Reason (i) — zero RAIS exposure**: no firms in `firm_sector` for this muni in any active `policy_block` (Agro, Ind, Infra, Serv) over the baseline window
2. **Reason (ii) — zero matched-firm coverage in non-empty cells**: at least one active block has firms in `firm_sector` over the baseline window, but none of them appear in `owner_aff_firm_year_party_2002_2019.qs2`
3. **Reason (iii) — zero alignment shock**: matched firms exist with positive total owners, but no party in those firms has a non-zero `align_mayor_coalition` shock (i.e., no political alignment in the data for this muni-year)

Priority order: (i) > (ii) > (iii). A cell flagged (i) is not also flagged (ii) or (iii).

Output: `a7_z_zero_decomposition.csv` with columns `muni_id`, `year`, `n_active_blocks_with_rais`, `n_active_blocks_with_aff`, `total_baseline_owners`, `total_alignment_shock`, `reason` ∈ {`zero_rais`, `zero_aff`, `zero_shock`}.

Plus an aggregated summary: `a7_z_zero_summary.csv` — one row per `reason × year`, counts and shares of all `Z = 0` cells.

Interpretation hint: if reason (ii) accounts for >20% of `Z = 0` cells, the matched-only denominator is doing meaningful imputation. If <5%, it's a sensitivity-analysis footnote.

### D-C: Zero-employment population by `policy_block`

For each firm-year in `firm_sector`, flag whether `n_employees == 0` or `is.na(n_employees)`. Then:
- by `policy_block`: count and share of zero-emp firm-years
- of those zero-emp firm-years: count and share that have an affiliation record (i.e., are observable to the IV but invisible to `w_mjp_emp`)
- of those zero-emp firm-years with affiliation: count and share with `owner_count >= 1` (i.e., would survive the proposed `pmax(n_employees, owner_count, 1)` floor)

Output: `a7_zero_emp_by_policy_block.csv` with `policy_block`, `n_firmyears_total`, `n_zero_emp`, `share_zero_emp`, `n_zero_emp_with_aff`, `share_zero_emp_with_aff`, `n_zero_emp_with_owners_ge_1`, `share_zero_emp_with_owners_ge_1`.

Interpretation hint: if zero-emp firms with affiliation are concentrated in Serv/MPME-style activities (likely, given individual entrepreneurs and Cartão BNDES borrowers), the employment weight is systematically blind to a substantively important subpopulation, and the `emp_share_floor` weight in Step 1 is justified.

## Files

| File | Status | Purpose |
|---|---|---|
| `explorations/anderson_rubin/diagnostics/a7_step0_coverage.R` | NEW | Single master diagnostic script |
| `explorations/anderson_rubin/diagnostics/output/a7_coverage_by_policy_block.csv` | NEW | D-A output |
| `explorations/anderson_rubin/diagnostics/output/a7_z_zero_decomposition.csv` | NEW | D-B per-cell output |
| `explorations/anderson_rubin/diagnostics/output/a7_z_zero_summary.csv` | NEW | D-B aggregated output |
| `explorations/anderson_rubin/diagnostics/output/a7_zero_emp_by_policy_block.csv` | NEW | D-C output |
| `explorations/anderson_rubin/diagnostics/output/a7_step0_report.md` | NEW | Narrative synthesis with the three findings and pointers to the revised A7 plan |

No production scripts touched.

## Inputs

- `output/rais_bndes_reconstructed.fst` — firm × year × muni × cnae_section × n_employees panel (script 22)
- `raw/david_ra/owner_aff_firm_year_party_2002_2019.qs2` — firm-year-party owner counts and shares
- `output/policy_block_mapping.qs2` — cnae_section → policy_block crosswalk (script 30e)
- `output/alignment_shocks.qs2` — muni-year-party alignment levels and changes (script 32)
- `output/shift_share_instruments_policy_block.qs2` — current production instruments at policy_block (script 34) — for D-B

## Implementation sketch

```r
# 1. Packages, seed, paths (INV-14, INV-15, INV-16)
# 2. Load all inputs above; merge cnae_section -> policy_block crosswalk; drop XX
# 3. D-A: build firm_sector | aff status indicator, aggregate match rates by
#    (policy_block, year, muni_size_class)
# 4. D-B: load production muni-level Z_emp_owner_mayor_coalition column;
#    for cells with Z = 0, walk the priority hierarchy (i) > (ii) > (iii)
#    using firm_sector | aff | alignment_shocks
# 5. D-C: tabulate n_employees == 0 | NA by policy_block, conditional on aff status
# 6. Write three CSVs and one markdown report
```

## Verification (simplified-mode quality checklist, target ≥80)

- [ ] Script runs without errors on a fresh R session.
- [ ] All packages loaded at top (INV-15); no `setwd()` or absolute paths (INV-16, INV-19); seed once if any random sampling is used (INV-14).
- [ ] D-A: all `match_rate_n` and `match_rate_emp` values in `[0, 1]`.
- [ ] D-B: priority hierarchy is mutually exclusive — every `Z = 0` cell gets exactly one reason; reasons sum to 100% of zero cells.
- [ ] D-C: shares sum correctly within each `policy_block`.
- [ ] All three CSVs and the markdown report exist at the expected paths.
- [ ] Quality score ≥ 80 (simplified-mode threshold).

## Risks and mitigation

| Risk | Mitigation |
|---|---|
| `n_firms_aff` join is ambiguous if `aff` is firm-year-party (one firm-year has many rows) | Deduplicate `aff` to firm-year before counting; document the choice |
| Some `Z = 0` cells may genuinely have all three reasons present (e.g., empty muni in baseline) | Priority hierarchy resolves ambiguity; document unambiguously in the script comments |
| Memory pressure: full RAIS firm-sector × baseline window | Read with `fst` column-selective; aggregate to muni-policy_block early; keep a single firm-year copy in memory |

## Out of scope

- Size-dimension diagnostics (S3 alone or `policy_block × S3`) — defer until policy_block patterns are understood.
- Diagnostics on the worker affiliation file (`worker_aff_party_standard_2002_2019.qs2`) — owner-only for now, consistent with production.
- Causal interpretation of the bias structure — this plan only quantifies; interpretation lives in the Step 0 report and feeds the revised A7 plan.
