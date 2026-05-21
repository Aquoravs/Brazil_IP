# Session — 2026-05-21 — Multi-channel first stages (Phase 1)

## 2026-05-21 11:30 — Phase 1: multi-channel first stages

**Goal:** Extend the saturated first-stage exercise (B2/B3) with regressions
that enter channels two at a time, and two channels plus their interaction, for
the three pairs (M,G), (M,P), (G,P). Plan:
`journal/plans/2026-05-21_multi-channel-first-stages.md`.

**Decisions:**
- B2b composition first stage runs each combination twice — volume control off
  and on (user choice at clarification step) — for 12 fits per margin. B3b
  volume first stage has no on/off split (vol_ratio is its dependent variable).
- EC entered only for the channels in each regression (per-channel EC matched
  to the included instruments, consistent with B6's run_ar) — not all 7.
- Both B2b specs run on the common sample (finite vol_ratio) so the on/off
  comparison holds N fixed.

**Operations:**
- New scripts `B2b_composition_multichannel.R`, `B3b_volume_multichannel.R` in
  `explorations/anderson_rubin/ar_meeting_2026_05_13/R/`; both wired into
  `run_phase_bc.R` after B3.
- Ran both for `policy_block` and `policy_block_size_bin`. 4 tables written and
  copied to `journal/meetings/2026-05-21/tables/`.
- Added 4 slides to `journal/meetings/2026-05-21/slides.tex` (deck now 22 pages,
  was 18). XeLaTeX compile clean — no overfull boxes, no missing references.
  `\resizebox{!}{height}` form did not constrain; switched to `{width}{!}`.

**Results (composition relevance, 5% partial F):**
- policy_block: Mayor relevant in {M,G} and {M,P} pairs; M·P relevant in
  {M,P,M·P}. Stacking the M·G interaction kills all relevance in {M,G,M·G}.
  Volume control on/off changes the statistics negligibly.
- 12 groups: only President clears 5%, and only in the stacked {M,P,M·P} set
  (p=0.0485). Volume control on/off again inert.

## 2026-05-21 14:00 — Joint-F columns added (checkpoint follow-up)

**Decision:** User asked, at the checkpoint, to evaluate multi-channel sets by
joint significance rather than per-channel F. Added a joint Wald $F$/$p$ over
each set's channels to B2b/B3b. A joint $F$ is flagged unreliable when it
exceeds the largest per-channel $F$ (orthogonality bound) — collinear channels
inflate or rank-deficient the joint Wald; such cells render as `collinear`.

**Results — joint first-stage F:**
- Composition, policy_block: only `{M,P}` has a reliable joint $F$ (3.87,
  p=0.021, significant). `{M,G}`, `{M,G,M·G}`, `{G,P}` collinearity-inflated;
  `{M,P,M·P}` inflated (raw F=284); `{G,P,G·P}` rank-deficient.
- Composition, 12 groups: joint $F$ mostly reliable but **none significant**
  (best reliable p=0.096, `{G,P}`); `{G,P,G·P}` collinear.
- Volume (both margins): all joint $F$ reliable, none significant at 5%.
- Takeaway: `{M,P}` at policy_block is the only multi-channel set with a
  trustworthy and significant joint first stage.

**Operations:**
- B2b/B3b: added joint Wald + `joint_reliable` flag; 10-col composition / 9-col
  volume tables. Re-ran all 4; copied tables; updated 4 slide notes.
- Slides recompiled (22 pages, XeLaTeX). Aesthetic review: log clean (no
  undefined refs; one 0.58pt vbox overflow — negligible). All 4 new slides
  visually checked at 190 DPI — tables centered (wrapped in `\centerline`),
  complete, booktabs format consistent with the deck.

**Status:**
- Done: Phase 1 — scripts (with joint F), tables, slides, compile, aesthetic
  review.
- Pending: mandatory user checkpoint — user must specify which composition
  instrument set(s) to carry into the Phase 2 AR test extension (B6).

## 2026-05-21 — Plan revised: wrong first stage caught; collinearity diagnosis added

**Goal:** Relevance was being judged with the stacked-long first stage
(B2b/B3b), which is not the first stage the AR test embeds. Revise the plan so
relevance is measured by the wide-form first stage that matches the AR test,
and add a prior instrument-collinearity diagnosis.

**Decisions:**
- The wide-form first stage (muni-year, $J$-column-per-channel, FE muni+year,
  EC control, muni clustering) is the relevance object — not the stacked-long
  own-sector form. Rationale: $\gamma=\Pi'\beta$; the exclusion diagnostic
  (irrelevant channel yet AR rejects) is valid only when irrelevance is read
  off the wide-form $\Pi$. Stacked form zeroes the off-diagonal of $\Pi$
  (false — shares sum to one) and imposes a common $\beta$.
- Relevance diagnostics are rank-based: Sanderson-Windmeijer $F$ per share +
  Kleibergen-Paap rank statistic, not a pooled $F$.
- B2/B2b/B3/B3b demoted to a descriptive companion — not the routing/exclusion
  verdict.
- Phase 1A (collinearity diagnosis) gets its own mandatory checkpoint before
  Phase 1B runs, per user request: the user reviews the diagnosis and prunes
  inadmissible instrument combinations before any first stage is run.

**Operations:**
- Rewrote `journal/plans/2026-05-21_multi-channel-first-stages.md`: two gated
  checkpoints (1A diagnosis, 1B wide-form relevance), Phase 2 AR extension
  with an exclusion-diagnostic flag. Status DRAFT → APPROVED (user, 2026-05-21).

**Status:**
- Done: plan revision approved.
- Pending: Phase 1A — `B7_collinearity_diagnosis.R`, 2 tables, 2 slides, then
  checkpoint #1. Blueprint §6 + decision log to be updated in the same commit
  as Phase 1A work.

## 2026-05-21 — Phase 1A implemented: collinearity diagnosis (B7)

**Goal:** Implement Phase 1A of the wide-form first-stage plan — the
instrument-collinearity diagnosis — and stop at checkpoint #1.

**Decisions:**
- 1A.3 "KP rank statistic": Phase 1A does not build the endogenous share
  vector (that is Phase 1B), so the genuine cluster-robust Kleibergen-Paap
  rank Wald statistic — which needs the endogenous regressors — cannot be
  computed here. Implemented the operational Phase-1A content instead: the
  numerical rank of the partialled instrument block (rank deficiency =
  `K − rank`). The genuine KP rank Wald is deferred to Phase 1B (`B8`).
  Documented in the `B7` header.
- Candidate stacks: 7 singletons, 3 mayor-paired pairs, the full mayor stack,
  3 parent-plus-interaction stacks, and 2 diagnostic G/P/GP stacks (16 total).
- Partialling matches the AR reduced form (B6 `run_ar`): per stack, the Z
  block is residualised on that stack's EC block + `vol_ratio` + muni/year FE
  via `fixest::demean` then a QR partial.
- Reported `max |r|` alongside `mean |r|`: the channel-level mean understates
  same-sector cross-channel correlation (which reaches ~0.7); the block
  condition number is the verdict, the max pairwise `|r|` is the honest
  context.

**Operations:**
- New script `B7_collinearity_diagnosis.R`; ran for both margins. Outputs:
  `collinearity_diagnosis_<tax>.{csv,tex}`, `instrument_admissibility_<tax>.csv`,
  `interaction_construction_audit.csv`, `design_attribution_<tax>.csv`.
- 2 tables copied to `journal/meetings/2026-05-21/tables/`; 2 frames added to
  `slides.tex` (deck 24 pages, was 22). XeLaTeX clean — no undefined refs, no
  overfull boxes; both new frames visually checked at 115 DPI.
- `run_phase_bc.R` rewritten with a `--phase={1a,1b,2}` selector and three
  gated passes; `B7` runs in the Phase 1A pass alongside the demoted
  descriptive companions B2/B2b/B3/B3b/B5.

**Results — the headline is a null collinearity finding:**
- 1A.1: all four interaction alignment columns (M·G, M·P, M·G·P, G·P) are
  the *exact* product of their single-office parents — equality holds on all
  1,288,211 alignment rows. M·G/M·P/M·G·P from `32_build_alignment_shocks.R`;
  G·P built as a product in `02_build_instruments_ec.R`.
- 1A.2/1A.3: the wide-form instrument block is well-conditioned at BOTH
  margins. Every candidate stack has condition number κ ≤ 3.8 (policy block) /
  ≤ 4.5 (12 groups), worst VIF ≤ 2.5 / ≤ 3.4, full rank. The stacked-long
  collinearity logged at the earlier checkpoint does NOT carry over to the
  wide-form parameterization the AR test embeds — consistent with the plan's
  thesis that the stacked-long form is the wrong first stage. Pairwise
  correlations are moderate (max |r| up to 0.67/0.76) but the blocks are not
  rank-deficient.
- Only the 4 parent-plus-interaction stacks are proposed inadmissible, and
  *a priori* (exact-product rule), not from measured collinearity — those same
  stacks have κ = 1.9–3.2.
- 1A.4: verticalização is NOT the collinearity source. The verticalizado
  cycles (2002, 2006; years < 2010) show LOWER residual cross-channel
  correlation than the post cycles for every key pair — contradicting the
  plan's 1A.4 hypothesis. Reported as-is.

**Status:**
- Done: Phase 1A — `B7`, 4 output files × 2 margins, 2 tables, 2 slides,
  compile + visual check, runner wiring, decision log D38, blueprint update.
- Pending: mandatory checkpoint #1 — user prunes the instrument set, then
  Phase 1B (`B8` wide-form first stage). Phase 1B NOT started.

## 2026-05-21 — Checkpoint #1 review: B7 corrected, slides removed

**User feedback at checkpoint #1:**
- `{M, G}` (and, by symmetry, `{M, P}`) parent pairs were missing from the
  candidate-stack set. Both added — `B7` now evaluates **18 stacks**
  (Singletons 7, Mayor stacks 4, Parent pairs 3 = {M,G}/{M,P}/{G,P},
  Parent + interaction 4). `B7` corrected but **not re-run** per user
  instruction.
- Phase 1B is to evaluate **all** stacks — no pruning by the a-priori
  exact-product rule.
- The 2 collinearity slides were not requested: removed from
  `journal/meetings/2026-05-21/slides.tex` (deck back to 22 pages, XeLaTeX
  clean), and the 2 copied tables removed from the meeting `tables/` folder.
  The collinearity `.tex`/`.csv` outputs in the exploration `output/` folder
  are kept.
- Clarified the interaction-instrument construction: the pipeline builds
  `Z^c = sum_p w_tilde^c * Align^c` with a single per-channel baseline share
  `w_tilde^c` — not the product of single-office instruments. The 1A.1 audit
  tested the alignment indicator columns, not the instruments; `Z^MG` is not a
  linear combination of `Z^M`, `Z^G` (R^2 = 0.53-0.64 regressing one on the
  others). Written up in
  `explorations/anderson_rubin/ar_meeting_2026_05_13/collinearity_diagnosis_report.md`.

**Status:**
- Done: B7 corrected to 18 stacks (not re-run); slides + meeting-table copies
  removed; collinearity report written; Phase 1B prompt handed to the user.
- Pending: Phase 1B in a separate session — re-run corrected B7, then build
  and run `B8_wide_first_stage.R`. Phase 1B NOT started here.

## 2026-05-21 17:19 — Phase 1B start: corrected B7 refreshed

**Operations:**
- Re-ran `R/B7_collinearity_diagnosis.R --tax=policy_block` and
  `--tax=policy_block_size_bin` before coding B8, as required by checkpoint #1.
- Refreshed `explorations/anderson_rubin/ar_meeting_2026_05_13/collinearity_diagnosis_report.md`
  sections 4-6 to cover the 18-stack run.

**Results:**
- Both margins still have full rank and low collinearity in every stack:
  max kappa = 3.80 / 4.53 and worst VIF = 2.53 / 3.43 for
  `policy_block` / `policy_block_size_bin`.
- `{M, G}` and `{M, P}` are well-conditioned parent pairs at both margins.

**Status:**
- Done: checkpoint #1 refresh step.
- Pending: implement and run `B8_wide_first_stage.R`, then update `B4` to read
  the B8 wide-form relevance verdict.

## 2026-05-21 17:46 — Phase 1B implemented and verified

**Operations:**
- Added `R/B8_wide_first_stage.R`.
- Rewrote `R/B4_channel_routing.R` so routing reads
  `output/wide_first_stage_<tax>.csv` rather than B2/B3 stacked-form CSVs.
- Ran `R/run_phase_bc.R --phase=1b`, which ran B8 then B4 for
  `policy_block` and `policy_block_size_bin`.

**Results:**
- B8 wrote `wide_first_stage_policy_block.{csv,tex}` and
  `wide_first_stage_policy_block_size_bin.{csv,tex}` with 18 stacks x
  2 volume treatments. The volume-control rows are the verdict.
- B4 wrote `ar_routing_policy_block.{csv,tex}` and
  `ar_routing_policy_block_size_bin.{csv,tex}`. All seven singleton channels
  route to composition at both margins; the volume set is empty because B8 has
  no separate volume-channel first stage.
- Runner wiring is confirmed: `phase1b_steps` is `B8_wide_first_stage.R`,
  then `B4_channel_routing.R`, and the pass ends at checkpoint #2.

**Status:**
- Done: Phase 1B write-run-verify loop; INV-13 checked for B8/B4 `.tex`
  outputs.
- Pending: user checkpoint #2 decision on which composition instrument set(s)
  to carry into Phase 2. Phase 2 not started.
