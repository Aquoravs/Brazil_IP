---
title: Mass-Weighted First-Stage Output Manifest
status: active
date: 2026-05-12
purpose: Concise manifest for diagnostic outputs from the mass-weighted first-stage horserace.
---

# Output Manifest

Purpose: identify the load-bearing outputs from the mass-weighted first-stage branch and their research use status. Parent README: [../README.md](../README.md). Project front door: [../../../../docs/PROJECT_BLUEPRINT.md](../../../../docs/PROJECT_BLUEPRINT.md).

## Folder

- Branch: `explorations/anderson_rubin/mass_weighted_first_stage`
- Output folder: `explorations/anderson_rubin/mass_weighted_first_stage/output`
- Status: COMPLETED exploration
- Last updated: 2026-05-12

## Decision Context

- Parent IDs: F2/F4, D23, D25, D27, D28
- Claim or decision informed: whether employment-mass exposure and DIF timing should enter the next methodology review.
- Current research use status: supports next design decision
- Production boundary: diagnostic / research-building evidence only. Do not use these outputs as production-pipeline inputs.

## Load-Bearing Outputs

| Artifact | Created by | Contents | Use status | Caveat |
|---|---|---|---|---|
| `horserace_fstats.csv` | `R/02_horserace.R` | Per-channel and joint clustered Wald diagnostics across mass and shift variants. | supports next design decision | Screening diagnostic; not literal SW/KP from a full IV system. |
| `horserace_coefs.csv` | `R/02_horserace.R` | Coefficient estimates by mass spec, shift, and channel. | diagnostic only | Interpret with fixed effects and cluster caveats from `findings.md`. |
| `horserace_summary.tex` | `R/02_horserace.R` | Compact table summarizing first-stage diagnostics. | supports next design decision | Exploration table only; not a production artifact. |
| `herfindahl_distribution_summary.csv` | `R/03_diagnostics.R` | Concentration summary used to reject current VAR-B for graduation. | supports next design decision | Load-bearing guardrail output; pair with `herfindahl_distribution.pdf`. |
| `herfindahl_distribution.pdf` | `R/03_diagnostics.R` | Visual concentration diagnostic across variants. | diagnostic only | Figure supports interpretation; summary CSV is the decision anchor. |
| `rank_correlation_summary.csv` | `R/03_diagnostics.R` | Summary of within-muni rank correlations across mass specs. | diagnostic only | Used to characterize reranking, not to settle production use. |
| `rank_correlation_summary.tex` | `R/03_diagnostics.R` | Compact rank-correlation table. | diagnostic only | Exploration table only. |
| `dif_event_year_decomposition.csv` | `R/03_diagnostics.R` | Decomposition of DIF variation across mayoral and gov/pres event years. | supports next design decision | Supports DIF as a cross-office methodology candidate. |
| `disagreement_munis.csv` | `R/03_diagnostics.R` | Municipalities where VAR-A and VAR-B rankings diverge most. | diagnostic only | Descriptive audit output. |
| `variant_b_summary.csv` | `R/01_build_variant_b.R` | Summary diagnostics for VAR-B construction. | diagnostic only | VAR-B is not graduated. |
| `dif_shifts_base_vara_summary.csv` | `R/01b_build_dif_shifts_existing_specs.R` | Summary diagnostics for BASE / VAR-A LEV-DIF shifts. | diagnostic only | Supports reproducibility of timing comparison. |

## Intermediate / Large Reproducibility Outputs

| Artifact pattern | Contents | Retention rule |
|---|---|---|
| `variant_b_instruments.qs2` | VAR-B instrument panel and denominator robustness. | Retain for reproducibility; do not use in production. |
| `dif_shifts_base_vara.qs2` | BASE and VAR-A LEV/DIF diagnostic instrument panel. | Retain for reproducibility; do not use in production. |
| `emp_share_policy_block_panel.qs2` | Local diagnostic employment-share panel. | Retain for reproducibility; not a production panel. |
| `horserace_panel_long.qs2` | Merged long panel for horserace regressions. | Retain for reproducibility. |
| `rank_correlations.csv`, `herfindahl_distribution.csv` | Large row-level diagnostic tables. | Use summaries above unless rerunning diagnostics. |

## Reproduction

- Inputs: firm panel, `firm_baseline_exposures.qs2`, `alignment_shocks.qs2`, A7 weight panel, and compatible production instrument primitives.
- Scripts: `R/01_build_variant_b.R`, `R/01b_build_dif_shifts_existing_specs.R`, `R/02_horserace.R`, `R/03_diagnostics.R`.
- Verification performed: findings checked against F-stat, concentration, rank-correlation, and DIF decomposition outputs.

## Graduation / Archive Decision

- Graduation condition: methodology review specifies a mass/timing construction, the production margin is committed, the construction is implemented in `scripts/R/`, and verification gates pass.
- Archive condition: current branch is complete; retain as research-building evidence for D28-era design review.
- Next action: use [../findings.md](../findings.md) in the theory/econometric review; do not point production scripts to this folder.
