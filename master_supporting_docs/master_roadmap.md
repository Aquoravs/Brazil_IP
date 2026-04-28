---
title: "Master Roadmap: Next Steps"
type: roadmap
status: in_progress
date: 2026-03-12
canonical_presentation: "paper/presentation_progress_2026_03_12.tex"
---

# Master Roadmap: Next Steps

This is the canonical living checklist for the current pipeline, results validation, paper writing, and presentation work.

The active execution horizon is scripts `31:54`. Older dated files in `docs/plans/` remain historical records, but this file is the main tracker going forward.

## Checklist Legend

Use one checklist system throughout this file.

- Status: `[ ]` not started, `[~]` running/waiting, `[x]` done, `[!]` blocked.
- Priority: `[P0]` critical, `[P1]` main analysis, `[P2]` robustness/paper, `[P3]` extensions.

## Current State

- [x][P0] Canonical roadmap file lives at `docs/master_roadmap.md`.
- [x][P0] Canonical presentation draft lives at `paper/presentation_progress_2026_03_12.tex`.
- [~][P0] Active run target is scripts `31:54`, not `31:42`.
- [x][P0] Estimation sample for the active analysis pipeline is `2002-2017`.
- [x][P0] Firm micro validation comes before sector and municipality claims.
- [x][P0] The firm pipeline has four main outcomes: `has_bndes_fmt`, `log_bndes_fmt`, `delta_has_bndes_fmt`, and `delta_log_bndes_fmt`.
- [x][P0] The sector pipeline uses owner-count instruments `Z_*` and `Zlev_*`; the firm pipeline uses regression weights `n_employees` rather than separate employment-weighted production instruments.
- [x][P0] `delta_s_*`, `delta_has_bndes_fmt`, and `delta_log_bndes_fmt` are never created by NA-to-zero fill; undefined deltas must remain `NA`.
- [x][P0] Firm default FE and clustering are `firm_id + muni_id^year` with two-way clustering by `firm_id` and `muni_id`.
- [x][P0] Sector first-stage default FE and clustering are `muni_id^sector + sector^year` with two-way clustering by municipality and sector; `muni_id^sector + muni_id^year` is a robustness FE.
- [x][P0] The current sources of truth are `AGENTS.md`, `paper/regs.tex`, `paper/draft.tex`, `docs/shift_share.md`, and `docs/first_stage_review.md`.

## Core Pipeline Tasks

- [ ][P0] Validate outputs from `31:42` immediately after the current run finishes.  
  Done when: the roadmap has row counts, runtime notes, schema checks, and any warnings for stages `31-36`, `41`, and `42`.

- [ ][P0] Validate script `51` as soon as firm tables are written.  
  Done when: the four main firm result tables and the coefficient summary are reviewed for sign, precision, sample size, and weighting coverage.

- [ ][P1] Run and assess script `54` under the current preferred default plus robustness FE.  
  Done when: the roadmap records the headline coefficient pattern, first-stage strength, and whether exposure controls materially change the results.

- [ ][P1] Run and assess script `54` end-to-end.  
  Done when: reduced form, scalar 2SLS, vector 2SLS, and robustness outputs are either summarized or explicitly marked as blocked/skipped.

- [ ][P1] Compare `cnae_section` versus `sector_group`.  
  Done when: the roadmap states which granularity is stronger empirically, which is cleaner substantively, and which one is suitable for headline results.

- [ ][P1] Compare coalition versus party alignment.  
  Done when: the roadmap states whether party is treated as robustness or a co-equal design, with a note on any implausibly large F-statistics or sign reversals.

- [ ][P1] Compare `cycle_specific` versus `2002_fixed` baselines.  
  Done when: the roadmap states whether the fixed baseline is a meaningful robustness check or changes the story materially.

- [ ][P1] Compare weighted versus unweighted firm results.  
  Done when: the roadmap states whether weighting by `n_employees` changes sign, magnitude, precision, or inference.

- [ ][P1] Record the aggregation diagnostic linking firm `FA_*` and `dFA_*` to sector-level variation.  
  Done when: the roadmap states support bounds, overall variation, within-municipality variation, and any discrepancies between micro and macro patterns.

## Paper Writing Tasks


- [ ][P2] Rewrite the empirical roadmap subsection in `paper/draft.tex` so it reflects completed versus pending work accurately.  
  Done when: future-work bullets correspond to the current roadmap rather than the older pre-implementation plan.

## Open Decisions

- [ ][P1] Decide the primary sector granularity for headline results: `cnae_section` or `sector_group`.  
  Done when: the roadmap states one main choice and one robustness choice, with evidence from first-stage strength and interpretability.

- [ ][P1] Decide the primary alignment definition for headline results: coalition or party.  
  Done when: the roadmap states which definition leads the paper and why.

- [ ][P1] Decide whether total BNDES scale enters the second stage as a control.  
  Done when: the roadmap states the preferred treatment of total BNDES and documents the rationale.

- [ ][P1] Decide whether grouped sectors belong in the main text or only in robustness/appendix material.  
  Done when: the deck and paper follow one stable placement rule.

- [ ][P2] Decide how to treat the exposure control in the narrative.  
  Done when: the paper and deck explain whether the current control is sufficient or whether an alternative control design is needed.

## Backlog / Extensions

- [ ][P3] Add alternative outcome work beyond municipal GDP: employment, wage bill, and firm entry/exit.  
  Done when: these outcomes move from backlog into an active implementation section.

- [ ][P3] Add night-lights data and associated outcome exercises.  
  Done when: the data are acquired and a concrete estimation plan is added outside the backlog.

- [ ][P3] Add spatial spillover controls or neighboring-alignment exercises.  
  Done when: the design is specific enough to create a new implementation section.

- [ ][P3] Add input-output adjusted shares and related theory-weighted specifications.  
  Done when: the required data source and implementation path are specified.

- [ ][P3] Add municipality-by-sector policy maps and external-elasticity interactions.  
  Done when: the second-stage baseline is stable enough to justify policy interpretation layers.

- [ ][P3] Add Rotemberg-weight, effective-shock-count, or BHJ-style diagnostics if they become central to the referee strategy.  
  Done when: there is a concrete script/output plan rather than a conceptual note.
