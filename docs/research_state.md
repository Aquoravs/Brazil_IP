---
title: Research State
status: skeleton
date: 2026-05-12
purpose: Compact current-state catalog for the AR research program. The project front door remains docs/PROJECT_BLUEPRINT.md.
---

# Research State

Purpose: track the current research state, blocking dependencies, and use status of active evidence. Start from the front door: [PROJECT_BLUEPRINT.md](PROJECT_BLUEPRINT.md).

This repository is an exploration and research-building system. Current outputs are not final research artifacts by default; they become inputs to later synthesis only after the relevant design choice is settled, implemented in the production pipeline, and verified.

## Current Gate

The immediate gate is theoretical and econometric review of [docs/methodology/ar_test_specification.tex](methodology/ar_test_specification.tex). Only after that review should the project decide the production margin, build the production crosswalk, rerun F2, or graduate weights into production.

`policy_block_active x S3` is a top F1 candidate from diagnostics. It is not the committed production margin under D28.

## Identification Chain

| ID | Claim | Current status | Evidence pointer | Use status | Caveat |
|---|---|---|---|---|---|
| F0 | BNDES allocation margins must be recognizable and firm-side. | SETTLED | [bndes_allocation_logic.md](strategy/bndes_allocation_logic.md) | research building block | Loan-side or purpose-side classifiers remain inadmissible unless converted to firm-side classifiers. |
| F1 | Candidate margins have meaningful within-muni x time variation. | PROVISIONAL / supports design | [f1_combined_report.md](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) | supports next design decision | `policy_block_active x S3` is a top candidate, not a committed production margin. |
| F2 | Alignment effects aggregate to an informative muni-level shock. | BLOCKED | [ar_test_specification.tex](methodology/ar_test_specification.tex) | diagnostic only | Must be rerun after instrument form and production margin are settled. |
| F3 | Alignment shifts satisfy the SSIV exclusion restriction. | PARTIAL | [ar_test_specification.tex](methodology/ar_test_specification.tex), A8 pending | supports next design decision | Placebo and shock-level inference work remain incomplete. |
| F4 | Denominator and weight construction do not load on excluded margins. | PARTIAL | [a7_winner_summary.md](../explorations/anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md), [findings.md](../explorations/anderson_rubin/mass_weighted_first_stage/findings.md) | research building block | A7 was at `policy_block`; size-crossed margins are not graduated. |

## Current Design Status

| Component | Status | Current fact | Next dependency |
|---|---|---|---|
| Production margin | BLOCKED by D28 | Working dimensions are `policy_block_active` and S3; `policy_block_active x S3` is a top F1 candidate only. | Complete theory/econometric review, then decide margin. |
| Instrument form | PROVISIONAL | Current methodology draft uses cross-office channels `M`, `MP`, `MG`, `MGP`; higher-tier alignment uses office-specific electoral coalitions. | Complete review of [ar_test_specification.tex](methodology/ar_test_specification.tex). |
| Exposure timing / weights | PROVISIONAL | Variant A is primary in D27; E/F are window robustness candidates; A7 supports `w_owners_muni_univ` at `policy_block`. | Reconcile with instrument review and committed margin. |
| Endogenous variable | SETTLED | Sector employment shares are the primary object; BNDES credit shares are mechanism variables. | Production implementation after margin decision. |
| Volume control | PROVISIONAL | Current draft controls total BNDES disbursements divided by initial municipal GDP. | Theory/econometric review. |

## Active Tracks

| Track | Status | Next action | Blocker | Use status |
|---|---|---|---|---|
| Track 1: AR theory/econometrics | ACTIVE | Review and settle [ar_test_specification.tex](methodology/ar_test_specification.tex). | None. | supports next design decision |
| Track 2: production margin | BLOCKED | Decide whether to use separate `policy_block_active` and S3 margins, a crossed margin, or another taxonomy. | Track 1. | supports next design decision |
| Track 3: production crosswalk | BLOCKED | Build the selected production crosswalk, likely in the 30f/31/34/41 script path. | Track 2. | ready for production pipeline only after implemented and verified |
| Track 4: F2 rerun | BLOCKED | Rerun sector first-stage / AR informativeness diagnostics at the committed margin. | Track 3. | diagnostic only until rerun |
| Track 5: weight graduation | BLOCKED | Decide whether `w_owners_muni_univ` or a successor graduates at the committed margin. | Track 3. | research building block |

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
