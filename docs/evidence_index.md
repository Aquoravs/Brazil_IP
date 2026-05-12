---
title: Evidence Index
status: active
date: 2026-05-12
purpose: Traceability map from claims and decisions to artifacts, use status, and caveats. The project front door remains docs/PROJECT_BLUEPRINT.md.
---

# Evidence Index

Purpose: answer where evidence for a claim lives and what it can currently be used for. Start from [PROJECT_BLUEPRINT.md](PROJECT_BLUEPRINT.md).

Use-status labels: diagnostic only; supports next design decision; research building block; ready for production pipeline; superseded / do not use.

| Claim / Decision | Status | Evidence artifact | Use status | Caveat |
|---|---|---|---|---|
| Firm-level political alignment predicts future BNDES access. | SETTLED as mechanism evidence | Blueprint key findings; script 51 outputs | research building block | Intensive loan amount first stage is weak; employment effects raise exclusion questions if interpreted naively. |
| AR is the selected weak-IV-robust test. | SETTLED | [ar_test_specification.tex](methodology/ar_test_specification.tex) | research building block | Current spec is still under theory/econometric review. |
| Employment shares are the primary endogenous object. | SETTLED | [ar_test_specification.tex](methodology/ar_test_specification.tex) | research building block | Sector-muni value added would be preferable but is unavailable for 2002-2017. |
| Volume channel is controlled by total BNDES disbursements over initial municipal GDP. | PROVISIONAL | [ar_test_specification.tex](methodology/ar_test_specification.tex) | supports next design decision | Specification of the volume control is subject to review. |
| `policy_block_active x S3` is the leading F1 candidate. | PROVISIONAL | [f1_combined_report.md](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) | supports next design decision | Not the committed production margin under D28. |
| `cnae_section x S3` is a secondary robustness candidate. | PROVISIONAL | [f1_combined_report.md](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) | supports next design decision | Higher instrument count may require many-instrument attention. |
| D16 production-margin interpretation is superseded by D28. | SUPERSEDED / PROVISIONAL | [decision_log.md](decision_log.md), [research_state.md](research_state.md), [f1_combined_report.md](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) | supports next design decision | D16 remains valid as F1 diagnostic evidence; it no longer commits `policy_block_active x S3` as production margin. |
| No new 30f-style taxonomy is production-ready before the D28 gate resolves. | BLOCKED | [taxonomies.md](taxonomies.md), [research_state.md](research_state.md) | supports next design decision | Requires settled instrument form, committed margin, production implementation, and verification. |
| `w_owners_muni_univ` wins A7 at the `policy_block` margin. | SETTLED for A7; PARTIAL for AR production | [a7_winner_summary.md](../explorations/anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md) | research building block | Must be re-evaluated or graduated after the production margin is committed. |
| Agro owner-affiliation coverage is thin. | OPEN / follow-up | [a7_step0_report.md](../explorations/anderson_rubin/diagnostics/output/a7_step0_report.md) | diagnostic only | Affects interpretation of Agro-heavy exposure weights. |
| VAR-B employment-mass exposure contains signal. | COMPLETED exploration | [findings.md](../explorations/anderson_rubin/mass_weighted_first_stage/findings.md) | supports next design decision | Current VAR-B fails the BJS-3 concentration guardrail; not a production input. |
| DIF timing is promising for cross-office channels under VAR-A. | PROVISIONAL | [findings.md](../explorations/anderson_rubin/mass_weighted_first_stage/findings.md) | supports next design decision | Requires methodology review before changing production instruments. |
| Standalone project-CNAE / BNDES product classifiers are not production margins. | SETTLED | [bndes_allocation_logic.md](strategy/bndes_allocation_logic.md) | superseded / do not use | May remain useful for descriptive checks only. |
| Current exploration tables and figures are not final outputs. | SETTLED workflow rule | [research_state.md](research_state.md), [../explorations/ACTIVE_PROJECTS.md](../explorations/ACTIVE_PROJECTS.md) | diagnostic only | May support later synthesis after design settlement, production implementation, and verification. |
