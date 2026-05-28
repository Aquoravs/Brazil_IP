---
title: Project Blueprint
status: front door
date: 2026-05-13
purpose: Short entry point for the current research state, active gate, and next workflow step.
---

# Project Blueprint

Read this at the start of every session. This repository is in an exploration and research-building phase: current outputs are evidence for decisions, diagnostics, and later synthesis, not final paper artifacts by default.

## Start Here

| Need | Read |
|---|---|
| Current state catalog | [research_state.md](research_state.md) |
| Decisions and supersession status | [decision_log.md](decision_log.md) |
| Defenses of design choices (advisor / referee Q&A) | [design_defenses.md](design_defenses.md) |
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

**Phase:** exploration, transitioning into documentation. The Anderson-Rubin municipal policy evaluation is now production-ready at the `policy_block` primary margin with `cnae_section` as side-by-side robustness (D29, 2026-05-13).

**Active focus:** Phase 4 documentation. E4.1 (methodology PDF update) and E4.3 (memo) bring the front-door artifacts in line with the firm-support hybrid implementation completed in Phases 2 and 3.

**Production AR results (graduated 2026-05-13):**
- `policy_block`: AR F = 4.37, p = 2e-4, K = 12 effective instruments. Drop-top-1 and drop-top-2 substitutes pass.
- `cnae_section`: AR F = 2.05, p = 2.1e-4 (side-by-side robustness).

**Remaining deferred:** D28 still defers the `policy_block_active x S3` production margin and the matching size-crossed weight graduation. F3 exclusion/placebo work is PARTIAL (presidential residual flagged; mayor clean; governor resolved as specification artifact).

**Next implementation step:** complete Phase 4 documentation. Then choose one of: (a) further pre-trend documentation, (b) AKM SE implementation for `ssaggregate` (flagged in C2.1.5 critic; advisory), or (c) revisit the deferred `policy_block_active x S3` graduation.

## Current Method State

The inferential framework is an Anderson-Rubin test of the local-optimality null, where the null sets the GDP gradient with respect to sector employment shares to zero.

Current working method facts:

- Endogenous object: sector employment shares on the RAIS contemporaneous-unbalanced skeleton, with per-cell BHJ §4.4 slack control carried through to the muni panel (D29).
- Volume channel: primary control = `total_bndes_real / initial_gdp_m,0` on RAIS-merged productive-firm disbursements; split-volume robustness adds non-RAIS productive, FI, and public components separately (D30).
- Exposure weights: cross-office primary uses channel-specific pre-earliest-election windows with no coalition gating; mayoral-window exposure is the main robustness (D31). Existing production weight code must be aligned to this timing decision before the cross-office stack is treated as final implementation.
- Instrument draft: cross-office channels `M`, `MP`, `MG`, and `MGP` are in the methodology draft.
- F-link status: F1 CONFIRMED at graduated margins; F2 CONFIRMED at `policy_block` primary (F=4.37) and `cnae_section` robustness (F=2.05); F3 PARTIAL (pre-trend characterization complete; presidential residual flagged; mayor clean; governor resolved as specification artifact); F4 PARTIAL — `policy_block x S3` weight graduation still BLOCKED per D28.
- Implementation: stage 32c (new) feeds modified stages 41/53/54.

## Production Margin Status

D29 graduates `policy_block` as primary and `cnae_section` as side-by-side robustness on 2026-05-13. The `policy_block_active x S3` size-crossed margin remains deferred under D28.

| Dimension | Status | Notes |
|---|---|---|
| `policy_block` | **production primary (graduated 2026-05-13, D29)** | Four BNDES policy blocks: Agro, Ind, Infra, Serv. Production AR F=4.37, p=2e-4, K=12 effective. |
| `cnae_section` | **production robustness (graduated 2026-05-13, D29)** | Side-by-side with `policy_block`. AR F=2.05, p=2.1e-4. |
| `policy_block_active` | active candidate component | Four active BNDES blocks; not graduated as a standalone margin. |
| S3 | active candidate component | Three firm-size bins: MPME, Media, Grande. |
| `policy_block_active x S3` | top F1 candidate only; deferred per user (D28, 2026-05-12) | Size-crossed graduation paused. |
| `cnae_section x S3` | secondary robustness candidate | Higher instrument count; may need many-instrument attention. |

See [taxonomies.md](taxonomies.md) for the detailed taxonomy catalog.

## Active And Deferred Tracks

| Track | Status | Next action |
|---|---|---|
| Track 1: theoretical/econometric review | ACTIVE | Phase 4 E4.1 methodology PDF update in flight. |
| Track 2: production margin | PARTIAL (D29 graduates `policy_block` + `cnae_section`; `policy_block_active x S3` deferred per D28) | Document graduated margins in E4.1; revisit deferred margin later if needed. |
| Track 3: production crosswalk | COMPLETED for hybrid | Stage 32c (new) -> 41/53/54 implemented and verified in Phase 2/3. |
| Track 4: F2 rerun | COMPLETED at graduated margins | F=4.37 (`policy_block`); F=2.05 (`cnae_section`). |
| Track 5: weight graduation | PARTIAL | `w_owners_muni_univ` graduated at `policy_block` (A7); size-crossed graduation still BLOCKED per D28. |
| Muni-by-muni AR | DEFERRED | Pooled AR remains the active path. |
| A6 project-CNAE cross-tab | OPTIONAL / DEFERRED | Descriptive only; not a production-margin input. |
| C6/C7 data extensions | AWAITING ADVISOR | See data memos linked from [CLAUDE.md](../CLAUDE.md). |
| A-RAIS-Negativa-access | OPEN (user 2026-05-12) | User to check whether RAIS Negativa is included in the project's restricted-access RAIS extract. If available, would tighten the Owner-only 7.64% Negativa-recoverable upper bound documented in Phase 0 A0.1. Out of scope until access status is confirmed. |
| A-AKM-ssaggregate-SE-correction | OPEN (advisory, 2026-05-13) | Flagged in C2.1.5 critic. Full AKM standard-error correction for `ssaggregate` not implemented in current production pipeline; current SEs are AR-robust but do not propagate the shock-level uncertainty. Advisory, not blocking. |
| A-Stage53-emp_share-weak | OPEN (disclosure, 2026-05-13) | Flagged in C2.3 critic. Stage 53 first-stage F on `emp_share` is weak; disclosed in the methodology PDF and relied on AR-robust inference. Not blocking under AR. |
| A-interaction-only-excluded-IV | OPEN (2026-05-22) | Interaction as the sole excluded instrument with single-office instruments as controls, differencing out the single-office direct paths so the exclusion restriction narrows to an interaction-specific direct path. Equals the current Next Action; specified in `journal/plans/2026-05-22_instrument-refinement-residualized-and-baseline.md` (DRAFT). |
| A-flexible-baseline-windows | OPEN (2026-05-22) | Test fresher cycle-specific affiliation baselines (per office, two-window construction for interactions) against the current pre-earliest-election baseline; sweep first-stage relevance and run anticipation/contamination placebos. Specified in `journal/plans/2026-05-22_instrument-refinement-residualized-and-baseline.md` (DRAFT). |
| Owner-only employment | CLOSED (2026-05-12) | Phase 0 A0.5 complete. **User's prior supported.** Owner-only observations employment-mass upper bound on contemporaneous $n_{mt}$ = 1.83% (median impute, all OO) / 0.63% (P25 impute, ever-RAIS subset). 62.2% of OO firms in cells where RAIS median is 1-4 employees; 83.2% appear in a single year; 13.3% never in RAIS. Feeds limitations section of `ar_test_specification.tex`. Caveat: bound is on formal employment, not value-added. |
| Private vs. all loans (D5-op) | IMPLEMENTED (2026-05-13, refined by D30) | Confirmed 2026-05-12; implemented in Phase 3 (D3.1 + C2.2-supplement + D3.3). Exposure weights use private productive firms only; volume control uses RAIS-merged productive-firm disbursements primary, with non-RAIS productive / FI / public splits as robustness. Script 11 drops the PRIVADA filter and tags `recipient_class`. |

## Production Pipeline Caveat

Existing `scripts/R/` production scripts remain the operational pipeline, but they do not yet implement a committed post-D28 production margin. Do not modify production code until the method review and margin decision are settled.

Any taxonomy requiring a new production crosswalk is production-ready only after:

1. the instrument form is settled;
2. the margin is committed;
3. the crosswalk and downstream consumers are implemented in `scripts/R/`;
4. verification gates pass.

## Research Logic To Preserve

- F0: candidate margins must be recognizable firm-side allocation margins.
- F1: CONFIRMED for graduated margins (`policy_block` primary, `cnae_section` robustness per D29). `policy_block_active x S3` remains a diagnostic top candidate.
- F2: CONFIRMED at the graduated margins — F=4.37 at `policy_block` (K=12 effective, p=2e-4); F=2.05 at `cnae_section` (p=2.1e-4). Stage 53 first-stage F on `emp_share` is weak (A-Stage53-emp_share-weak); inference is AR-robust.
- F3: PARTIAL — pre-trend characterization complete; presidential residual flagged; mayor clean; governor resolved as specification artifact.
- F4: PARTIAL — A7 supports `w_owners_muni_univ` at `policy_block`. `policy_block x S3` size-crossed weight graduation still BLOCKED per D28.

## Active Explorations

| Branch | Status |
|---|---|
| `explorations/anderson_rubin/active_denominator/` | COMPLETED for Phase 1 + 1.5-1.8 + C2.1.5 sub-task; production pipeline now consumes this work. Ready for archive or promotion. |
| `explorations/firm_universe/rais_coverage_audit/` | COMPLETED. |
| `explorations/firm_universe/bndes_recipient_audit/` | COMPLETED. |
| `explorations/anderson_rubin/mass_weighted_first_stage/` | Open (diagnostic). |
| `explorations/anderson_rubin/instrument_combinations/` | Open. Phase A (EC adequacy audit) complete 2026-05-20 — D32 reinforced. Phases B (seven-channel saturated first stages + routing) and C (`policy_block × S3` 12-group margin) complete 2026-05-20 — D33–D37 logged; results carried by the 2026-05-21 meeting deck. Deferred: per-channel F3 placebo/falsification on the routing-relevant channels (run after the meeting). |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/` | Open. Wide-form first-stage plan (2026-05-21): relevance is judged by the wide-form first stage, not the stacked-long form — D38 logged. Phase 1A (`B7`) found the wide-form instrument block well-conditioned at both margins. Phase 1B (`B8` + `B4`) evaluated all 18 stacks; all seven singleton channels route to composition at both margins. Checkpoint #2 resolved (user, 2026-05-22): proceed with the explicit excluded-stack design. Phase 2 baseline AR screen (`B9`) is complete with all three volume treatments — `B9` runs its own volume first stage (Mayor and Mayor·Governor are the volume instruments) to populate the Full-IV column. At `policy_block` rejection tracks the Governor channel and survives Full IV; Mayor·Governor's rejection does not survive Full IV. At the 12-group margin all three screened stacks reject on weak first stages. `B4`/`B6` still carry an empty Phase 1B `vol_set`. Next diagnostic: residualized interaction-only excluded IV (deferred). |

## Next Action

Run the **interaction-only excluded-IV diagnostic** flagged at the end of the Phase 2 baseline AR screen: for each interaction channel, exclude only the interaction instrument and include the lower-order main effects as controls (for M·P: exclude `Z_MP`, control on `Z_M` and `Z_P`). This isolates the interaction-specific variation and gives the cleaner exclusion story than the current excluded-stack design, where the main effects are themselves excluded instruments. The Phase 2 baseline screen (`B9`) is complete: at `policy_block` rejection tracks the Governor channel, and at the 12-group margin all three screened stacks reject on weak first stages — read as an exclusion/direct-effect warning, not a composition-channel finding. Still deferred: the per-channel F3 placebo/falsification on the routing-relevant channels, Phase 4 documentation (E4.1 methodology PDF, E4.3 memo), and the `policy_block × S3` production-margin work.

Do not relitigate the econometrics in this front door. Update the detailed state files when decisions change, then keep this file short.
