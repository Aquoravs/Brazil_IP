---
title: A7 Weight Comparison Output Manifest
status: active
date: 2026-05-12
purpose: Concise manifest for A7 policy-block weight comparison outputs.
---

# Output Manifest

Purpose: identify the load-bearing A7 outputs and their current research use status. Project front door: [../../../../docs/PROJECT_BLUEPRINT.md](../../../../docs/PROJECT_BLUEPRINT.md).

## Folder

- Branch: `explorations/anderson_rubin/a7_weight_comparison`
- Output folder: `explorations/anderson_rubin/a7_weight_comparison/output`
- Status: COMPLETED for `policy_block`; BLOCKED for final AR graduation
- Last updated: 2026-05-12

## Decision Context

- Parent IDs: F4, D21, D22, D23, D28
- Claim or decision informed: exposure-weight choice at the `policy_block` diagnostic margin.
- Current research use status: research building block
- Production boundary: A7 supports `w_owners_muni_univ` at `policy_block` only. It does not graduate weights for `policy_block_active x S3`, `cnae_section x S3`, or any final post-D28 production margin.

## Load-Bearing Outputs

| Artifact | Created by | Contents | Use status | Caveat |
|---|---|---|---|---|
| `a7_winner_summary.md` | A7 branch scripts / manual synthesis | Winner summary: `w_owners_muni_univ` wins, `w_binary_muni_univ` runner-up. | research building block | Settled for `policy_block`; blocked for final AR graduation. |
| `a7_representative_weights_rationale.md` | A7 branch scripts / manual synthesis | Rationale for representative weights and the candidate set. | research building block | Applies to A7's policy-block protocol. |
| `a7_onecycle_proxy_summary.md` | A7 branch scripts | One-cycle proxy diagnostics used in the final comparison. | diagnostic only | Diagnostic support, not a production criterion by itself. |
| `a7_correlation_matrix.csv` | A7 branch scripts | Correlations among representative candidate weights. | diagnostic only | Use with summaries; not a standalone decision artifact. |
| `a7_representative_weights.csv` | A7 branch scripts | Compact representative weight values / diagnostics. | diagnostic only | Descriptive support for A7. |

## Intermediate / Large Reproducibility Outputs

| Artifact pattern | Contents | Retention rule |
|---|---|---|
| `a7_weights_panel.qs2`, `a7_instruments_panel.qs2` | A7 diagnostic panels. | Retain for reproducibility; do not treat as production inputs. |
| `a7_tier_b_*.qs2` | Tier-B robustness panels. | Retain for audit trail. |
| `run_log.txt`, `04_run_log.txt` | Execution logs. | Retain with branch. |

## Reproduction

- Inputs: policy-block diagnostic panels and A7 script outputs.
- Scripts / commands: see branch scripts and logs.
- Verification performed: A7 winner summary reconciles correlation and one-cycle proxy diagnostics.

## Graduation / Archive Decision

- Graduation condition: production margin and instrument form are committed, then weight comparison is rerun or explicitly mapped to that final design and verified.
- Archive condition: A7 remains complete for `policy_block`.
- Next action: use as research-building evidence only; do not graduate directly to the production pipeline.
