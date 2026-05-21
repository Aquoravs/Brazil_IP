---
title: EC adequacy audit and instrument-combinations follow-up
status: COMPLETED
date: 2026-05-20
completed: 2026-05-20
---

# Plan: EC adequacy audit + instrument-combinations follow-up

## Status

COMPLETED (2026-05-20). All four phases done. Storyteller-critic 90/100; deck
compiled (`journal/meetings/2026-05-21/build/slides.pdf`, 18 pages); D33–D37
logged. Remaining deferred items: per-channel F3 placebo/falsification and
documentation follow-ups E4.1/E4.3 — tracked in session log, not in this plan.

_Original status note (Phase A):_ Phase A complete (2026-05-20). Phases B–D
executed in sequence: B (build seven channels, two saturated first stages,
channel routing, AR tests) → C (policy_block × S3 12-group margin) → D
(meeting slides for 2026-05-21). Dispatched coder / coder-critic for B–C and
storyteller / storyteller-critic for D.

**Phase A outcome:** EC adequacy audit done (A1–A6). The EC is the BHJ-correct,
predetermined incomplete-shares control for the muni-relative weight, correctly
built and entered; the AR conclusion is robust to its functional form. D32
stands and is reinforced. One documentation follow-up flagged (methodology PDF
§2.3 and production scripts 32c/41 still describe/carry the intensity-weight
`slack_frozen_mt`) — routed to E4.1. See `findings.md` §10.

## Background

The 2026-05-14 advisors asked why the AR test uses mayor-crossed channels and
why it abandoned the additive {M, G, P} stack. The exploration
`explorations/anderson_rubin/instrument_combinations/` (memo: `findings.md`)
answered this and was then extended in two directions:

1. An *agnostic* procedure for learning which office matters (findings.md §8).
2. A weight-construction question: whether to revert to a within-cell,
   affiliated-normalized weight that sums to one across parties at the sector
   level and thereby eliminates the exposure control (EC).

That second question was evaluated with an external second opinion and
**resolved — see D32**: keep the muni-relative weight + per-channel EC as
primary; reject the within-cell revert (it discards sector mass and
reintroduces thin-cell instability); adopt shock recentering as the planned
EC-free robustness. The standing action item is to verify the EC is
*adequately constructed*. The original advisor agenda (which office matters,
{M,G,M·G} vs {M·G}) is still open.

## Decision in force

**D32 (2026-05-20):** muni-relative owner-share weight + per-channel EC =
primary AR-test instrument. Within-cell complete-shares weight rejected.
Recentering = planned robustness.

**2026-05-20, to be logged as D33+ in `docs/decision_log.md`:**
- AR instruments retain **all `J` sector columns** per channel — no hold-out.
  The EC retains `J−1` (one sector held out, absorbed by FE).
- Saturated first stages route channels to composition vs volume (B4 rule).
- The Full-IV ("volume instrumented") column is shown only if a channel clears
  the B4 volume relevance gate; otherwise dropped.
- Slides present two margins only: `policy_block` and `policy_block × S3`.

## Phase A — EC adequacy audit (priority)

Goal: confirm the EC currently used in the AR test is the correct BHJ
incomplete-shares control for the muni-relative weight, and that the AR
conclusion does not hinge on its functional form.

- **A1. Definitional consistency.** Confirm `EC^c[j,m,t] = Σ_p w̃^c[j,m,p,t]`
  uses the *same* muni-relative weight as the instrument `Z^c`: affiliated
  owner-years in the numerator, muni-level affiliated total in the
  denominator, channel-specific frozen pre-earliest-election window. Check the
  build code, not just the spec.
- **A2. EC vs. slack.** The muni-relative weight drops unaffiliated owners
  entirely, so there is no unaffiliated residual at the muni level. Confirm
  which control the pipeline actually carries (the sum-of-shares EC vs. a
  `slack_frozen_mt` column inherited from the within-cell-intensity weight)
  and that it is the BHJ-correct object for the muni-relative weight. Resolve
  any leftover slack column.
- **A3. Regression structure.** One `EC_<channel>_<sector>` per retained
  sector; held-out sector consistent with the instrument hold-out; the
  simplex collinearity `Σ_j EC = 1` is absorbed by the hold-out + FE. Verify
  in `04_run_ar_regressions.R`.
- **A4. Predeterminedness.** Confirm the EC uses only pre-window owner counts
  — no contemporaneous leakage.
- **A5. Functional-form sensitivity.** Re-run the AR test with the EC entered
  linearly vs. flexibly (bins / low-order polynomial). If the AR conclusion is
  stable, "EC dependence" is not a concern. If it flips, escalate — recentering
  (Phase C) becomes primary, not robustness.
- **A6. Coverage / concentration audit.** Distribution of cell affiliated-owner
  counts; effective number of shocks (inverse-HHI of the share weights); share
  of employment / GDP mass in thin cells. The muni-relative denominator is
  thick so collapse is not a threat, but this documents how concentrated the
  identifying variation is.

## Phase B — instrument combinations + volume treatment

Goal: let the saturated first stages route each channel to the margin it
identifies — composition or volume — then run the AR test with the data-chosen
sets. R work goes in `explorations/anderson_rubin/ar_meeting_2026_05_13/`.

- **B1. Build the three missing channels.** Construct `G`, `P`, `G·P` channel
  instruments and their EC with the same machinery as `M/MP/MG/MGP`
  (channel-specific pre-earliest-election window). All seven channels then
  exist: M, G, P, M·G, M·P, G·P, M·G·P.
- **B2. Saturated first stage of composition.** `s_emp[j,m,t]` on the seven
  channel instruments (sector-vector form); `muni×sector` + `sector×year` FE;
  EC always included; cluster muni + sector. Report per-channel coefficients
  and per-channel first-stage F, nested blocks (mains → +pairs → +triple), and
  BNDES credit share as an alternative LHS (upstream mechanism check). Spec in
  `findings.md` §8.5.
- **B3. Saturated first stage of volume.** `Vol_mt` on the seven
  muni-aggregated channels `Zbar_c = Σ_j Z_c` (scalar form); `muni` + `year`
  FE. Report per-channel coefficient, SE, and partial F.
- **B4. Channel routing rule.** From B2 and B3, route each channel:
  - record, per channel, the partial first-stage F and 5% joint significance
    in (a) the composition first stage and (b) the volume first stage;
  - *composition instrument* = relevant (5%) in B2; *volume instrument* =
    relevant in B3 **and not** relevant in B2;
  - a channel relevant in **both** is assigned to composition — used as a
    volume instrument it would reintroduce composition variation into the
    control;
  - a channel relevant in **neither** is dropped;
  - if **no** channel clears the composition gate, fall back to the four
    mayor-crossed channels `{M, M·P, M·G, M·G·P}` as the composition set;
  - if no channel clears the volume gate, the Full-IV column is dropped.
  Output a routing table: channel × {F_comp, F_vol, assignment}.
- **B5. The advisor comparison.** AR test at `policy_block` with `{M·G}` only
  vs. `{M, G, M·G}` together — characterise the difference.
- **B6. Three-volume AR table.** Run the AR test three ways, EC always
  present: (i) no volume control; (ii) volume as a predetermined control
  (Partial IV, baseline D24); (iii) volume instrumented (Full IV) by the
  volume channel(s) from B4 — column dropped if B4 finds none. Report for
  **two** instrument sets: the data-selected composition set from B4, and
  per-channel for the four mayor-crossed channels `{M, M·P, M·G, M·G·P}`. A
  channel appearing in both sets is presented once.

**Deferred:** per-channel placebo/validity (F3 falsification on relevant
higher-tier channels) is out of scope for the 2026-05-21 deliverable; run after
the meeting.

**Simplex / category omission.** The endogenous shares `s` and the EC each sum
to 1, so the EC drops one sector (hold-out absorbed by FE). The instruments
`Z_c` do **not** sum to 1 (`Σ_j Z̃_c ∈ [0,1)`): **all `J` instrument columns
are retained** — no hold-out for `Z`. The AR Wald is the joint test on all
retained `Z` columns of the channel.

## Phase C — policy_block × S3 size margin (12 groups)

Goal: run the AR test at the crossed taxonomy policy_block × size (S3).

- **C1. Crosswalk.** Build the `policy_block_size_bin` sector variable —
  4 policy blocks × 3 size bins (S3) = 12 groups — reusing the policy-block
  mapping (30e) and the size-bin mapping (30c/30d). Rebuild channel
  instruments + EC at this margin.
- **C2. AR test at the 12-group margin.** Same channel routing (B4) and
  three-volume structure (B6). `Z` retains all 12 groups; the EC drops one.
- **C3. Coverage check.** A6-style thin-cell audit at 12 groups — the finer
  margin risks thin cells; report effective shocks and GDP mass in thin cells.

## Phase D — meeting slides (2026-05-21)

Goal: a new `slides.tex` for the 2026-05-21 meeting, modeled on the structure,
conventions, and visual style of `journal/meetings/2026-05-14/slides.tex`.

- **D1. New folder** `journal/meetings/2026-05-21/` with `slides.tex`,
  `tables/`, and `build/`; inherit the 2026-05-14 preamble, theme, and section
  layout.
- **D2. Content.** Present **two margins only**: `policy_block` (4 groups) and
  `policy_block × S3` (12 groups). Drop the standalone `size_bin` and
  `cnae_section` margins. Slides carry: the B4 routing table; the three-volume
  AR table (no Vol / Vol control / Vol instrumented) for the data-selected set
  and the four mayor-crossed channels; the `{M·G}` vs `{M, G, M·G}` comparison.
- **D3. Table notes (MUST).** Every regression-table note states that the joint
  Wald statistic is computed on the **instrument coefficients only**, not on
  all regressor coefficients. EC is always an included control and is noted as
  such. Notes must not be truncated.
- **D4. Compile + review.** XeLaTeX compile; run the `latex-aesthetic-review`
  skill; storyteller-critic pass for narrative and INV-20/INV-21 fidelity.

## Files

| File | Role |
|---|---|
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/02_build_instruments_ec.R` | builds `Z` + `EC` — audit in A1/A2 |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/04_run_ar_regressions.R` | runs the AR test — A3, A5, B3 |
| `scripts/R/3_instruments/31–36` | production instrument scripts — B1 build pattern |
| `docs/methodology/ar_test_specification.tex` | EC / weight / BJS §4.4 definitions |
| `docs/strategy/office_specific_exposure_weights.md` | weight memo; Variant B-prime rejection |
| `explorations/anderson_rubin/instrument_combinations/findings.md` | this exploration's memo (§7 checks, §8 procedure) |
| `journal/meetings/2026-05-14/slides.tex` | template for the 2026-05-21 slides — structure, preamble, conventions |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/05_build_slides.R` | slide/table-build pattern to reuse for D |

## Verification

- Phase A: each of A1–A6 produces a written finding; A5 re-runs the AR test;
  exploration quality ≥ 80.
- Phase B: both saturated first stages run; per-channel F and nested-block
  table produced; B4 routing table produced; B5 comparison produced; B6
  three-volume AR table produced for both instrument sets.
- Phase C: 12-group crosswalk built; AR test runs at the crossed margin with
  the three-volume structure; thin-cell audit produced.
- Phase D: `slides.tex` compiles under XeLaTeX with no missing references;
  table notes carry the instruments-only Wald statement; `latex-aesthetic-review`
  punch-list addressed; storyteller-critic ≥ 80.
- Log per `.claude/rules/logging.md`; update `findings.md` and the decision
  log if any phase changes a decision.
