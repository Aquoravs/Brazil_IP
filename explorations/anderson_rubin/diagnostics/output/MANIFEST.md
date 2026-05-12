---
title: Anderson-Rubin Diagnostics Output Manifest
status: active
date: 2026-05-12
purpose: Concise manifest for F1 and related diagnostic outputs.
---

# Output Manifest

Purpose: identify the load-bearing diagnostics outputs and their current research use status. Project front door: [../../../../docs/PROJECT_BLUEPRINT.md](../../../../docs/PROJECT_BLUEPRINT.md).

## Folder

- Branch: `explorations/anderson_rubin/diagnostics`
- Output folder: `explorations/anderson_rubin/diagnostics/output`
- Status: COMPLETED / active reference
- Last updated: 2026-05-12

## Decision Context

- Parent IDs: F1/F4, D12, D15, D16, D17, D19, D22, D28
- Claim or decision informed: candidate-margin support and coverage caveats.
- Current research use status: supports next design decision
- Production boundary: diagnostics support F1 and related data-quality caveats. They are not a production-margin commitment and do not implement production pipeline logic.

## Load-Bearing Outputs

| Artifact | Created by | Contents | Use status | Caveat |
|---|---|---|---|---|
| `f1_combined_report.md` | Diagnostics scripts / manual synthesis | Combined F1 evidence across candidate sector and size margins. | supports next design decision | `policy_block_active x S3` is top F1 candidate, not committed production margin. |
| `within_muni_variation_report.md` | Diagnostics scripts | Baseline within-muni variation evidence. | diagnostic only | Earlier diagnostic layer; use the combined report for current status. |
| `f1_policy_block_size_report.md` | Diagnostics scripts | F1 evidence for policy-block x size variants. | supports next design decision | Supports candidate-margin ranking only. |
| `f1_standalone_size_report.md` | Diagnostics scripts | Standalone S3/S4 size diagnostics. | diagnostic only | Standalone size is not preferred as sole margin; S4 is superseded. |
| `a7_step0_report.md` | A7 step-0 diagnostics | Agro owner-affiliation and coverage caveats. | diagnostic only | Supports F4/A7 caveat tracking; not a production commitment. |
| `alignment_report.md`, `alignment_report_yearly.md` | Diagnostics scripts | Alignment / size-bin diagnostic summaries. | diagnostic only | Historical support for F1 candidate screening. |
| `coverage_report.md`, `coverage_report_A2.md` | Diagnostics scripts | Coverage summaries for candidate margins. | diagnostic only | Use as coverage evidence, not final design evidence. |
| `cnae_coverage_report.md` | Diagnostics scripts | CNAE coverage and unmatched diagnostic summary. | diagnostic only | Data-quality caveat. |

## Intermediate / Large Reproducibility Outputs

| Artifact pattern | Contents | Retention rule |
|---|---|---|
| `coverage_cells_*.csv`, `variation_by_muni.csv`, `a7_coverage_by_policy_block.csv` | Large cell-level diagnostic tables. | Retain for reproducibility; prefer reports above for state summaries. |
| `*_summary.csv`, `*_decomposition.csv`, `*_vs_round1.csv` | Supporting tabulations for reports. | Retain as report inputs. |
| `*.pdf` | Diagnostic figures. | Retain as visual support only. |

## Reproduction

- Inputs: diagnostic candidate-margin panels and coverage objects.
- Scripts / commands: see corresponding diagnostics branch scripts and reports.
- Verification performed: current docs use `f1_combined_report.md` as the active F1 evidence pointer.

## Graduation / Archive Decision

- Graduation condition: after the theory/econometric review, rerun or extend diagnostics at the committed production margin before production implementation.
- Archive condition: current reports remain a D28-era evidence reference.
- Next action: keep as F1 support and caveat evidence; do not treat as production commitment.
