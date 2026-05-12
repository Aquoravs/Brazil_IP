---
title: Project Blueprint
status: front door
date: 2026-05-12
purpose: Short entry point for the current research state, active gate, and next workflow step.
---

# Project Blueprint

Read this at the start of every session. This repository is in an exploration and research-building phase: current outputs are evidence for decisions, diagnostics, and later synthesis, not final paper artifacts by default.

## Start Here

| Need | Read |
|---|---|
| Current state catalog | [research_state.md](research_state.md) |
| Decisions and supersession status | [decision_log.md](decision_log.md) |
| Evidence and use-status map | [evidence_index.md](evidence_index.md) |
| Taxonomy and margin catalog | [taxonomies.md](taxonomies.md) |
| AR method draft | [methodology/ar_test_specification.tex](methodology/ar_test_specification.tex) |
| Active exploration branches | [../explorations/ACTIVE_PROJECTS.md](../explorations/ACTIVE_PROJECTS.md) |
| Commands, pipeline, conventions | [../CLAUDE.md](../CLAUDE.md) |

## Research Question

Does a politically driven exogenous shock to the sectoral composition of local economic activity affect municipal GDP, beyond the aggregate volume effect?

The causal chain is:

> political turnover -> politically connected firms in some sectors receive marginally more BNDES credit -> employment in those sectors expands -> municipal sectoral employment composition shifts -> municipal GDP changes.

The estimand is the GDP effect of sectoral employment-share composition. BNDES credit is the mechanism that transmits the political shock, not the final outcome. Sector employment shares are the best available full-coverage proxy for local economic composition over 2002-2017; sector-municipality value added or gross output would be preferable but is unavailable.

## Current Phase

**Phase:** exploration, focused on the Anderson-Rubin municipal policy evaluation.

**Active focus:** finish the theoretical and econometric review in [ar_test_specification.tex](methodology/ar_test_specification.tex). The draft currently develops cross-office instruments and maps the shift-share conditions to this setting, but the review is not yet the basis for production changes.

**Immediate blocker:** D28 defers the production margin decision until the theoretical/econometric review is complete. Until then, F2 informativeness, weight graduation, and production crosswalk work are blocked.

**Next implementation step:** finish the theoretical/econometric review, then decide the production margin, then build the production crosswalk / rerun F2 / graduate weights.

## Current Method State

The inferential framework is an Anderson-Rubin test of the local-optimality null, where the null sets the GDP gradient with respect to sector employment shares to zero.

Current working method facts:

- Endogenous object: sector employment shares.
- Volume channel: total BNDES disbursements divided by initial municipal GDP, still provisional pending review.
- Instrument draft: cross-office channels `M`, `MP`, `MG`, and `MGP` are in the methodology draft.
- F2 status: power/informativeness check, not a validity gate under AR.
- Exclusion and denominator/weight issues remain partial and tracked in F3/F4.

## Production Margin Status

The production margin is **not committed** under D28.

`policy_block_active x S3` is the top F1 candidate from diagnostics. It is **not** the committed production margin. Do not describe it as production-ready or as the settled AR margin.

Working dimensions for the next decision are:

| Dimension | Status | Notes |
|---|---|---|
| `policy_block_active` | active candidate component | Four active BNDES blocks: Agro, Ind, Infra, Serv. |
| S3 | active candidate component | Three firm-size bins: MPME, Media, Grande. |
| `policy_block_active x S3` | top F1 candidate only | Requires production crosswalk and post-review decision. |
| `cnae_section x S3` | secondary robustness candidate | Higher instrument count; may need many-instrument attention. |

See [taxonomies.md](taxonomies.md) for the detailed taxonomy catalog.

## Active And Deferred Tracks

| Track | Status | Next action |
|---|---|---|
| Track 1: theoretical/econometric review | ACTIVE | Complete review of [ar_test_specification.tex](methodology/ar_test_specification.tex). |
| Track 2: production margin | BLOCKED | Decide the margin only after Track 1. |
| Track 3: production crosswalk | BLOCKED | Build the selected crosswalk after the margin is committed. |
| Track 4: F2 rerun | BLOCKED | Rerun sector first-stage / AR informativeness diagnostics at the committed margin. |
| Track 5: weight graduation | BLOCKED | Decide whether `w_owners_muni_univ` or a successor graduates at the committed margin. |
| Muni-by-muni AR | DEFERRED | Pooled AR remains the active path. |
| A6 project-CNAE cross-tab | OPTIONAL / DEFERRED | Descriptive only; not a production-margin input. |
| C6/C7 data extensions | AWAITING ADVISOR | See data memos linked from [CLAUDE.md](../CLAUDE.md). |

## Production Pipeline Caveat

Existing `scripts/R/` production scripts remain the operational pipeline, but they do not yet implement a committed post-D28 production margin. Do not modify production code until the method review and margin decision are settled.

Any taxonomy requiring a new production crosswalk is production-ready only after:

1. the instrument form is settled;
2. the margin is committed;
3. the crosswalk and downstream consumers are implemented in `scripts/R/`;
4. verification gates pass.

## Research Logic To Preserve

- F0: candidate margins must be recognizable firm-side allocation margins.
- F1: diagnostics support candidate margins, especially `policy_block_active x S3`, but only as decision evidence.
- F2: informativeness is blocked until the committed margin and instrument form exist.
- F3: exclusion/placebo work is partial.
- F4: A7 supports `w_owners_muni_univ` at `policy_block`, but weight graduation at the final margin is still blocked.

Do not relitigate the econometrics in this front door. Update the detailed state files when decisions change, then keep this file short.
