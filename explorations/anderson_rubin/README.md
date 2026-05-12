# Anderson-Rubin Exploration Index

Purpose: index the Anderson-Rubin exploration branches and make their current research use status explicit. The project front door is [../../docs/PROJECT_BLUEPRINT.md](../../docs/PROJECT_BLUEPRINT.md); the central exploration status table is [../ACTIVE_PROJECTS.md](../ACTIVE_PROJECTS.md).

Use-status labels: diagnostic only; supports next design decision; research building block; ready for production pipeline; superseded / do not use.

## Current Gate

The active gate is the theory/econometric review of [../../docs/methodology/ar_test_specification.tex](../../docs/methodology/ar_test_specification.tex). D28 defers the production-margin decision until that review is complete. No branch in this folder currently supplies production-pipeline inputs by default.

## Branches

| Branch | Status | Research use status | Notes |
|---|---|---|---|
| `diagnostics/` | COMPLETED / active reference | supports next design decision | F1 support for candidate margins. `policy_block_active x S3` is the top diagnostic candidate, not the committed production margin. |
| `a7_weight_comparison/` | COMPLETED for `policy_block`; BLOCKED for final AR graduation | research building block | Supports `w_owners_muni_univ` at `policy_block` only. Weight graduation at the final AR margin is blocked. |
| `mass_weighted_first_stage/` | COMPLETED exploration | supports next design decision | VAR-B has signal but fails concentration guardrail; VAR-A remains conservative; DIF is a cross-office methodology candidate. |
| `a10_composition_volume/` | DEFERRED design context | supports next design decision | Composition / volume framing remains tied to the methodology review. |
| `ar_baseline/` | SUPERSEDED as implementation plan | superseded / do not use | Predates D24-D28 and the cross-office instrument review. Retained only for audit trail. |
| `ar_horserace/` | SUPERSEDED / historical | superseded / do not use | Early spec comparison; do not treat as current AR guidance. |

## Production Boundary

Outputs under this folder are diagnostics and research-building evidence unless a later decision explicitly graduates them, implements the relevant logic in `scripts/R/`, and verifies the result. Do not point production scripts to exploration output files.

## Load-Bearing References

- Current state: [../../docs/research_state.md](../../docs/research_state.md)
- Decisions: [../../docs/decision_log.md](../../docs/decision_log.md)
- Evidence map: [../../docs/evidence_index.md](../../docs/evidence_index.md)
- Taxonomies: [../../docs/taxonomies.md](../../docs/taxonomies.md)
- Output manifest template: [../../templates/output-manifest.md](../../templates/output-manifest.md)
