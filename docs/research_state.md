---
title: Research State
status: skeleton
date: 2026-05-13
purpose: Compact current-state catalog for the AR research program. The project front door remains docs/PROJECT_BLUEPRINT.md.
---

# Research State

Purpose: track the current research state, blocking dependencies, and use status of active evidence. Start from the front door: [PROJECT_BLUEPRINT.md](PROJECT_BLUEPRINT.md).

This repository is an exploration and research-building system. Current outputs are not final research artifacts by default; they become inputs to later synthesis only after the relevant design choice is settled, implemented in the production pipeline, and verified.

## Current Gate

Phase 4 documentation is in flight. The firm-support hybrid (D29) graduated `policy_block` as primary and `cnae_section` as side-by-side robustness on 2026-05-13. Volume-control specification settled per D30.

`policy_block_active x S3` remains a top F1 candidate from diagnostics but is **not** graduated; its production margin work is deferred per D28 (user 2026-05-12).

## Identification Chain

| ID | Claim | Current status | Evidence pointer | Use status | Caveat |
|---|---|---|---|---|---|
| F0 | BNDES allocation margins must be recognizable and firm-side. | SETTLED | [bndes_allocation_logic.md](strategy/bndes_allocation_logic.md) | research building block | Loan-side or purpose-side classifiers remain inadmissible unless converted to firm-side classifiers. |
| F1 | Candidate margins have meaningful within-muni x time variation. | CONFIRMED for graduated margins | [f1_combined_report.md](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) | research building block | `policy_block` graduated primary; `cnae_section` graduated robustness (D29). `policy_block_active x S3` remains top F1 candidate only. |
| F2 | Alignment effects aggregate to an informative muni-level shock. | CONFIRMED at `policy_block` primary; CONFIRMED at `cnae_section` robustness | Phase 2/3 critic memos; [ar_test_specification.tex](methodology/ar_test_specification.tex) | research building block | Production AR F = 4.37 (p=2e-4) at `policy_block` (K=12 effective); F = 2.05 (p=2.1e-4) at `cnae_section`. Drop-top-1 / drop-top-2 substitutes pass at `policy_block`. Stage 53 first-stage F on `emp_share` is weak (see A-Stage53-emp_share-weak), disclosed under AR-robust inference. |
| F3 | Alignment shifts satisfy the SSIV exclusion restriction. | PARTIAL | [ar_test_specification.tex](methodology/ar_test_specification.tex), A8 pending | supports next design decision | Pre-trend characterization complete; presidential residual flagged; mayor pre-trend clean; governor resolved as specification artifact. |
| F4 | Denominator and weight construction do not load on excluded margins. | PARTIAL | [a7_winner_summary.md](../explorations/anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md), [findings.md](../explorations/anderson_rubin/mass_weighted_first_stage/findings.md) | research building block | A7 was at `policy_block`; size-crossed (`policy_block x S3`) graduation still BLOCKED per D28 user deferral (2026-05-12). |

## Current Design Status

| Component | Status | Current fact | Next dependency |
|---|---|---|---|
| Production margin | GRADUATED for `policy_block` primary + `cnae_section` robustness (D29); BLOCKED for `policy_block_active x S3` (D28) | Hybrid skeleton implemented in stage 32c -> 41/53/54. | Phase 4 documentation; then optionally revisit `policy_block_active x S3` graduation. |
| Instrument form | PROVISIONAL | Methodology draft uses cross-office channels `M`, `MP`, `MG`, `MGP`; office-specific electoral coalitions for higher-tier alignment. | Theory/econometric review continues in E4.1. |
| Exposure timing / weights | SETTLED for cross-office timing (D31) | Primary cross-office weights use the channel-specific pre-earliest-election window with no coalition gating. Mayoral-window exposure is the main mechanism-aligned robustness; higher-tier window is a second timing robustness. A7 supports `w_owners_muni_univ` at `policy_block`. | Align production weight builder / stage 31c with D31; size-crossed weight graduation deferred. |
| Endogenous variable | SETTLED | Sector employment shares on RAIS contemporaneous-unbalanced skeleton; per-cell BHJ §4.4 slack control. | Implemented in stages 41/53/54. |
| Volume control | SETTLED (D30) | Primary: `total_bndes_real / initial_gdp_m,0` (RAIS-merged productive-firm disbursements). Split-volume robustness includes non-RAIS productive, FI, and public flows. | Documented in methodology PDF (E4.1). |

## Active Tracks

| Track | Status | Next action | Blocker | Use status |
|---|---|---|---|---|
| Track 1: AR theory/econometrics | ACTIVE | Phase 4 E4.1 methodology PDF in flight. | None. | supports next design decision |
| Track 2: production margin | PARTIAL | `policy_block` primary + `cnae_section` robustness graduated (D29). `policy_block_active x S3` graduation deferred (D28). | None for graduated margins; user decision for the deferred margin. | production-ready at the two graduated margins |
| Track 3: production crosswalk | COMPLETED for hybrid (stage 32c -> 41/53/54) | Done. | None. | ready for production pipeline |
| Track 4: F2 rerun | COMPLETED at graduated margins | F=4.37 (`policy_block`); F=2.05 (`cnae_section`). | None. | research building block |
| Track 5: weight graduation | PARTIAL | `w_owners_muni_univ` graduated at `policy_block` (A7); size-crossed graduation still BLOCKED per D28. | User decision. | research building block |

## Completed / Recently Closed

| Item | Status | Result | Use status |
|---|---|---|---|
| A1 allocation logic | SETTLED | Firm-side admissibility criterion; active admissible set is CNAE-derived taxonomies and size. | research building block |
| A7 weight comparison | SETTLED for `policy_block`; PARTIAL for full AR design | `w_owners_muni_univ` wins the `policy_block` horserace; `w_binary_muni_univ` is runner-up. | research building block |
| Mass-weighted first-stage horserace | COMPLETED as exploration | VAR-B has signal but fails concentration guardrail; keep VAR-A conservative, consider DIF for cross-office channels. | supports next design decision |

## Deferred / Superseded

| Item | Status | Note |
|---|---|---|
| Muni-by-muni AR | DEFERRED | Likely low power with roughly 16 years per municipality; pooled AR remains active path. |
| Standalone `bndes_sector_size_bin` | SUPERSEDED | Legacy exploratory variant; keep for audit and comparison only. |
| Current exploration outputs as final artifacts | SUPERSEDED / do not use | Outputs may later support synthesis after design settlement and verification; do not treat them as final outputs now. |

## Pointers

- Decision skeleton: [decision_log.md](decision_log.md)
- Evidence traceability: [evidence_index.md](evidence_index.md)
- Taxonomy catalog: [taxonomies.md](taxonomies.md)
- Active explorations: [../explorations/ACTIVE_PROJECTS.md](../explorations/ACTIVE_PROJECTS.md)
