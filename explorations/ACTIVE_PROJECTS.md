---
title: Active Exploration Projects
status: active
date: 2026-05-12
purpose: Central index of active, recently completed, deferred, and superseded exploration branches. The project front door remains docs/PROJECT_BLUEPRINT.md.
---

# Active Exploration Projects

Purpose: make exploration branch state explicit so stale branch READMEs are not mistaken for current production guidance. Start from [../docs/PROJECT_BLUEPRINT.md](../docs/PROJECT_BLUEPRINT.md).

Use-status labels: diagnostic only; supports next design decision; research building block; ready for production pipeline; superseded / do not use.

## Branch Status

| Branch | Status | Decision it informs | Main result | Next action | Owner artifact | Research use status |
|---|---|---|---|---|---|---|
| `anderson_rubin/ar_baseline` | SUPERSEDED as implementation plan; retained as design context | Early pooled AR implementation at `policy_block`. | Predates D24-D28 and the current cross-office instrument review. | Do not use as production guidance; revisit only after theory review settles the AR design. | `explorations/anderson_rubin/ar_baseline/` | superseded / do not use |
| `anderson_rubin/ar_horserace` | SUPERSEDED / historical | Early AR specification comparison. | Superseded by the D24 employment-share estimand and D28 process gate. | Archive as historical reference; do not extend without a new plan. | `explorations/anderson_rubin/ar_horserace/` | superseded / do not use |
| `anderson_rubin/a10_composition_volume` | DEFERRED design context | Composition / volume decomposition and partial-IV framing. | Current working approach instruments employment shares and controls total BNDES volume directly, but the volume control remains under review. | Resume after [ar_test_specification.tex](../docs/methodology/ar_test_specification.tex) review. | `explorations/anderson_rubin/a10_composition_volume/` | supports next design decision |
| `anderson_rubin/diagnostics` | COMPLETED / active reference | F1 candidate-margin support. | `policy_block_active x S3` is the top F1 candidate; `cnae_section x S3` is secondary robustness; S4 is not active. | Keep as evidence pointer; rerun only if the theory review changes the candidate set. | [anderson_rubin/diagnostics/output/f1_combined_report.md](anderson_rubin/diagnostics/output/f1_combined_report.md) | supports next design decision |
| `anderson_rubin/a7_weight_comparison` | COMPLETED for `policy_block`; BLOCKED for final AR graduation | F4 exposure-weight choice at `policy_block`. | `w_owners_muni_univ` wins; `w_binary_muni_univ` is runner-up. | Re-evaluate or graduate only after production margin and instrument form are committed. | [anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md](anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md) | research building block |
| `anderson_rubin/mass_weighted_first_stage` | COMPLETED exploration | Employment-mass exposure and LEV/DIF timing choice. | VAR-B has signal but fails concentration guardrail; VAR-A remains conservative; DIF is a methodology candidate for cross-office channels. | Feed into theory/econometric review; do not graduate directly into `scripts/R/`. | [anderson_rubin/mass_weighted_first_stage/findings.md](anderson_rubin/mass_weighted_first_stage/findings.md) | supports next design decision |
| CNAE coverage / unmatched diagnostics | DEFERRED follow-up | Data-quality caveats around `XX`, unmatched CNAE, and Agro owner-affiliation coverage. | Caveats are known and documented; they do not settle the production margin. | Revisit only when production margin is settled or advisor asks for the diagnostic. | [anderson_rubin/diagnostics/output/a7_step0_report.md](anderson_rubin/diagnostics/output/a7_step0_report.md) | diagnostic only |

## Current Active Gate

No exploration branch is currently a production implementation workstream. The active gate is the theory/econometric review in [../docs/methodology/ar_test_specification.tex](../docs/methodology/ar_test_specification.tex). After that review, the project can decide the production margin, production crosswalk, F2 rerun, and weight graduation path.

## Production Boundary

Exploration outputs may support design decisions and later synthesis, but they are not production-pipeline inputs unless the relevant decision is SETTLED, the implementation lives in `scripts/R/`, and verification gates pass. In particular, mass-weighted first-stage outputs are diagnostic / research-building evidence only; they should not be consumed by production scripts.
