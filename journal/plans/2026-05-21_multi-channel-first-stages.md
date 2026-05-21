---
title: Wide-form first-stage relevance and instrument-collinearity diagnosis
status: APPROVED
date: 2026-05-21
approved: 2026-05-21
supersedes: the approved 2026-05-21 version of this plan (multi-channel stacked first stages)
---

# Plan: Wide-form first-stage relevance + instrument-collinearity diagnosis

## Revision note — why this supersedes the approved plan

The approved version of this plan judged instrument relevance with the **wrong
first stage**. It built multi-channel *stacked-long* first stages (B2b, B3b) and
let their per-channel and joint $F$ feed the routing rule. The stacked-long
first stage is not the first stage the AR test embeds. Relevance must be
measured by the first stage that **matches the test**; the approved plan did
not, so its routing verdict and any exclusion diagnostic built on it are
unreliable. The collinearity finding logged at the 2026-05-21 checkpoint
(rank-deficient and inflated joint $F$ across channel stacks) is real and
gates everything downstream. This revision (i) replaces the relevance
evaluation with the **wide-form** first stage, (ii) adds a prior
**collinearity diagnosis** as Phase 1A with its own mandatory checkpoint, and
(iii) demotes the stacked-form scripts to a descriptive companion. Status is
**DRAFT** until the collinearity problem is diagnosed and the user approves
these modifications.

## Background — two first-stage parameterizations

The endogenous object is the sector employment-share vector $s_{mt}$, a
$J$-vector, $J-1$ free after the simplex. The AR test (`B6_three_volume_ar.R`)
is the cluster-robust joint Wald on the instruments in the reduced-form GDP
equation. Two distinct first-stage parameterizations exist.

**Wide-form first stage — what the AR test embeds.** Data at the
**municipality-year** level. Each channel $c$ enters as $J$ separate columns
$Z^c_{j}$, one per sector. The share vector is projected on the full wide
block. FE $=$ muni $+$ year. EC is always an included control. Clustered by
muni. This is equation (`fs-stacked`) of `docs/methodology/ar_test_specification.tex`:
$s_{mt} = \alpha^{(s)}_m + \delta^{(s)}_t + \Pi Z_{mt} + \Phi\,\mathrm{EC}_{mt}
+ \mu\,\mathrm{Vol}_{mt} + \nu_{mt}$, with $\Pi$ the $(J-1)\times K$ first-stage
matrix. The reduced-form GDP coefficient is $\gamma = \Pi'\beta$.

**Stacked-long first stage — what has been run so far.** Data at the
municipality-**sector**-year level. The share $s_{jmt}$ is regressed on the
channel's **own-sector** shock as a single column; one scalar $\beta$ per
channel. FE $=$ muni$\times$sector $+$ sector$\times$year. This is
`B2_composition_first_stage.R`, `B2b_composition_multichannel.R`, and the
volume analogues `B3`, `B3b`.

**Why the stacked-long form is wrong for judging relevance.** It is a
restricted and partly misspecified version of the wide-form stage. It imposes
(i) **only a sector's own shock moves its own share** — every off-diagonal
entry of $\Pi$ is set to zero, which is mechanically false because shares sum
to one (any shock that raises one share lowers others, so cross-sector
first-stage coefficients are nonzero by construction); and (ii) a **single
common $\beta$** across all $J$ sectors, washing out sector-heterogeneous
identifying variation. It also uses a different FE structure. The relevance
verdict it produces is therefore not the relevance the AR test sees.

**Why this is decisive.** Write the reduced form as $\gamma = \Pi'\beta$. Under
$H_0:\beta=\mathbf{0}$, $\gamma=\mathbf{0}$, so AR does not reject. If a channel
is **irrelevant** ($\Pi_c=\mathbf{0}$) yet AR rejects, then $\gamma=\Pi'\beta$
cannot hold — the channel reaches GDP through a direct path, an
exclusion-restriction violation. That diagnostic is valid **only if
"irrelevant" is measured by the wide-form $\Pi$**. Judging relevance with the
restricted stacked form can flag a channel that is wide-form-relevant but
stacked-form-null as an exclusion violation when it is not. The specific
worry is an M$\cdot$G-type channel that looks irrelevant in the stacked form
yet rejects the AR test: with the wrong first stage, the wrong choice
*manufactures* the alarm. The first stage must match the test.

AR's **size** is robust to weak instruments, so irrelevance does not
invalidate the test. This revision is about correctly **attributing** a
rejection and feeding the exclusion diagnostic — not about test validity.

**Relevance diagnostics for a vector-valued endogenous object.** A single
pooled $F$ is the wrong summary. The correct diagnostics are rank-based:
the **Sanderson-Windmeijer (SW) first-stage $F$** per endogenous share
(conditional on the other shares), and the **Kleibergen-Paap (KP) rank
statistic** for the instrument block — both in their cluster-robust forms,
valid for many, possibly non-iid instruments.

## Decisions in force (inherited)

- D32: muni-relative owner-share weight (Variant A) $+$ per-channel EC $=$
  primary AR-test instrument. EC is an included control in every
  specification.
- Two margins only: `policy_block` (4 groups) and `policy_block`$\times$`S3`
  (`policy_block_size_bin`, 12 crossed groups).
- AR / Wald statistics are computed on the **instrument coefficients only**,
  never on all regressor coefficients.

## Phase structure

Phase 1 has two parts, **each ending in its own mandatory user checkpoint**.
Phase 1A diagnoses the instrument collinearity and proposes which channel
stacks are admissible — then **stops** so the user can review the results and
decide which instrument combinations to discard. Phase 1B runs the wide-form
first stage **only on the user-pruned set** and reports the rank-based
relevance diagnostics — then **stops** again for the user to choose the sets
carried into Phase 2. Phase 2 extends the AR test. Neither checkpoint is
skippable; the Phase 1A checkpoint is what the user asked for — the
collinearity diagnosis is reviewed before any first stage is run.

---

## Phase 1A — instrument-collinearity diagnosis

**Goal.** Explain *why* the instrument block is collinear, propose *which*
channel stacks are inadmissible as joint instruments, and audit *how* the
interaction channels are built. The 2026-05-21 checkpoint already observed
the symptom — at the `policy_block` margin the stacked joint $F$ is
rank-deficient for $\{G,P,G\cdot P\}$, inflated for $\{M,G\}$, $\{G,P\}$, and
$\{M,P,M\cdot P\}$ (raw $F=284$), and trustworthy only for $\{M,P\}$. Phase 1A
turns that symptom into a diagnosis and a *proposed* admissibility rule that
the user reviews at the checkpoint.

New script `B7_collinearity_diagnosis.R`. It runs on the muni-year AR panel
(`muni_panel_ar_<tax>.qs2`) — the same object the AR test uses — for both
margins. Four diagnostic blocks.

**1A.1 — Interaction-instrument construction audit.** The open question: is an
interaction instrument an independently-defined alignment object (a firm owner
aligned with *both* offices), or the mechanical product of the two
single-office objects? If it is a mechanical product, it carries no variation
independent of its parents at the alignment level, so any
$\{$parent$_1$, parent$_2$, interaction$\}$ stack is collinear by construction.

What to compute:
- *GP*: confirmed in `02_build_instruments_ec.R` — `align_gov_pres_coalition`
  is built as the exact product `align_gov_coalition * align_pres_coalition`
  at the (muni, party, year) level. Record this as a known mechanical product.
- *MP, MG, MGP*: locate and read the upstream script in `scripts/R/3_instruments/`
  that produces `alignment_shocks.qs2`, and determine whether
  `align_mayor_pres_coalition`, `align_mayor_gov_coalition`, and
  `align_triple_coalition` are (i) exact products of the single-office
  coalition indicators or (ii) independently-defined coalition-membership
  objects. Then **verify numerically** on the data: for each interaction
  column, test the row-by-row equality `align_X == align_parent1 * align_parent2`
  at the (muni, party, year) level and report the share of rows where it holds.
- State the nuance explicitly: an exact *alignment-level* product does **not**
  make the *instrument* $Z^c$ an exact linear combination of $Z^{\text{parent}}$,
  because (a) the channel uses a different exposure window and (b) the
  sum-over-parties of a product is not the product of sums. Alignment-level
  mechanical nesting induces strong correlation; instrument-level exact
  collinearity would show as rank-deficiency. Block 1A.2 measures the residual.

Decision this feeds: an interaction column that equals the product of its
parents exactly makes the $\{$parent$_1$, parent$_2$, interaction$\}$ stack
inadmissible as a joint stack *a priori* — independent of the numerical
thresholds below. An independently-defined interaction is judged empirically.

**1A.2 — Pairwise correlations and condition numbers after partialling.** For
each candidate channel set, take the wide instrument block (all
$K=|\mathcal{C}|\cdot J$ columns $Z^c_j$) and residualize every column on the
muni and year FE, the EC controls, and `vol_ratio` — every non-instrument
regressor in the AR reduced form. On the partialled block compute:
- the pairwise correlation matrix of the columns, plus a channel-level
  summary (mean $|\text{corr}|$ between the block of channel $c$ and the
  block of channel $c'$);
- the condition number $\kappa=\sqrt{\lambda_{\max}/\lambda_{\min}}$ of the
  partialled $Z'Z$ (Belsley-Kuh-Welsch), and the full eigenvalue spectrum;
- the variance inflation factor (VIF) for each column.

**1A.3 — Kleibergen-Paap rank statistic across candidate stacks.** For each
candidate stack $\mathcal{C}$ — the seven per-channel singletons, the three
mayor-crossed pairs, the full mayor-crossed stack
$\{M, M\cdot P, M\cdot G, M\cdot G\cdot P\}$, and the diagnostic G/P/GP
stacks — compute the cluster-robust KP rank statistic for the wide-form first
stage. A stack whose KP rank statistic cannot be computed or is degenerate is
rank-deficient.

**1A.4 — Why the block is collinear: attribution to design.** Tie the numbers
to instrument design rather than chance:
- *Shared election calendar.* Governor and president share election years
  (2002, 2006, 2010, 2014), so $T^G_t=T^P_t$ and $w^G_{jmp,t}=w^P_{jmp,t}$ on
  the common window — $Z^G$ and $Z^P$ are near-identical by construction.
- *Verticalização.* TSE Resolution 20.993/2002 forced state coalitions to
  mirror the presidential coalition for the 2002 and 2006 cycles, so
  $\mathrm{Align}^G\approx\mathrm{Align}^P$ there — $Z^{M\cdot G}\approx
  Z^{M\cdot P}$ for those cycles, and $Z^{M\cdot G\cdot P}$ collapses toward
  $Z^{M\cdot P}$.
- *Shared pre-earliest-election window.* From `00_helpers.R` and the
  calendar, $e_G=e_P$ always, so the pre-earliest-election window
  $T^c_t$ is **identical** for the MP, MG, and MGP channels. The window
  contributes zero differentiation among the three mayor-crossed
  interactions; they differ only through the channel-specific support set
  and the alignment column.
- *Alignment-product nesting.* A product interaction indicator is one only
  when both parents are one, so it is mechanically a subset of each parent's
  variation.

To quantify the verticalização contribution, split each pairwise correlation
into a verticalizado component (2002 and 2006 cycles) and a
post-verticalização component (2010 and 2014 cycles).

**Proposed admissibility rule (the user reviews and overrides at checkpoint #1).**
A channel stack is **proposed admissible for joint wide-form evaluation and
joint AR testing** iff: (i) the partialled instrument block has condition
number $\kappa\le 30$ (propose: $\le 30$ admissible, $30$–$100$ marginal,
$>100$ severe and inadmissible); (ii) no column VIF exceeds $10$; and (iii)
the KP rank statistic is computable and non-degenerate. A stack failing any
criterion is proposed for exclusion from joint evaluation — only the
per-channel wide-form first stages of its channels would be reported. An
interaction channel whose alignment column is an exact product of its parents
makes the $\{$parent$_1$, parent$_2$, interaction$\}$ stack inadmissible
*a priori*. G, P, and GP are flagged as **diagnostic-only** channels — they sit
outside the mayoral-gated identifying restriction of the strategy
(`ar_test_specification.tex` §2.1: the instrument set is restricted to channels
that contain mayoral alignment as a factor) and are not candidate AR
instruments.

Output: `output/collinearity_diagnosis_<tax>.{csv,tex}` and a *proposed*
admissibility verdict `output/instrument_admissibility_<tax>.csv`.

### Phase 1A tables and slides

- One bare-`tabular` `.tex` collinearity-diagnosis table per margin —
  **2 tables**. Booktabs rules only; no `\caption`, no `\begin{table}`, no
  in-table notes (INV-13). Use `00_helpers.R` formatters.
- One collinearity-diagnosis slide per margin added to
  `journal/meetings/2026-05-21/slides.tex` — **2 frames**, inheriting the
  existing preamble and conventions, frame titles stating the answer.
- Copy the 2 tables into `journal/meetings/2026-05-21/tables/`; compile
  `slides.tex` under XeLaTeX; confirm no missing references and no new
  overfull boxes.

## Mandatory user checkpoint #1 (end of Phase 1A)

**Phase 1B does not begin until the user responds.**

Report to the user, for **each margin** separately:
- which channel stacks are *proposed* admissible and which inadmissible, with
  the condition number, worst VIF, and KP rank statistic for each;
- the interaction-construction audit verdict — whether
  `align_mayor_pres_coalition`, `align_mayor_gov_coalition`, and
  `align_triple_coalition` are exact products of their parents;
- the design attribution (1A.4): the verticalizado vs post-verticalização
  split of the key pairwise correlations.

Then ask the user explicitly: **which instrument combinations should be
discarded, and which channel sets should Phase 1B evaluate?** The user may
override the proposed admissibility rule in either direction. Phase 1B's input
is the user-pruned set. Do not proceed until the user answers.

---

## Phase 1B — wide-form first-stage relevance

**Goal.** Measure instrument relevance with the first stage the AR test
embeds, on the user-pruned set from checkpoint #1, and report rank-based
diagnostics — not a stacked-form per-channel or pooled $F$.

New script `B8_wide_first_stage.R`. On the muni-year AR panel, build the wide
share vector $s_j$ (the $J$ sector shares; the simplex hold-out sector is the
omitted base, leaving $J-1$ endogenous shares) by reshaping
`emp_share_panel_policy_block.qs2` for `policy_block`, or building crossed
shares from the firm panel for the 12-group margin — the same construction
already in `B2`/`03`. The share vector is merged into the muni-year panel.

For each instrument set the user retained at checkpoint #1 — every per-channel
singleton kept, plus each stack the user confirmed admissible — estimate the
wide-form first stage that matches the AR test exactly:
- unit of observation: municipality-year;
- instruments: the $J$-column-per-channel block $Z^c_j$;
- controls: the EC block ($J-1$ columns per channel) and `vol_ratio` as a
  predetermined control, matching the D24 partial-IV baseline;
- FE: muni $+$ year;
- clustering: by muni.

Estimate it as the IV specification of the AR test's structural equation
(`log_gdp ~ EC + vol_ratio | muni + year | s_j ~ Z-block`) and read the
first-stage diagnostics off it. Report, per instrument set:
- the **Sanderson-Windmeijer first-stage $F$** for each of the $J-1$
  endogenous shares, cluster-robust by muni;
- the **Kleibergen-Paap rank Wald statistic** for the set;
- the count of shares whose SW $F$ clears conventional thresholds.

Implementation note for the coder (selects the route): `fixest::fitstat()`
reports the per-endogenous-variable first-stage $F$, which is the SW statistic
when there are multiple endogenous regressors; the cluster-robust KP rank Wald
statistic is computed in closed form or via an `ivreg2`-equivalent routine.

A no-volume-control companion fit may be reported alongside, since the AR test
also runs a no-volume spec; the volume-control fit is the verdict.

**The per-channel wide-form verdict** — relevant if channel $c$'s $J$-column
block jointly predicts the share vector (KP rank statistic non-degenerate and
significant, or at least one share with a clearing SW $F$) — is what feeds the
routing rule (`B4`) and the Phase 2 exclusion diagnostic.

Output: `output/wide_first_stage_<tax>.{csv,tex}`.

`B4_channel_routing.R` is edited so the routing rule consumes the **wide-form**
relevance verdict (`B8`) and the user-confirmed admissibility set — not the
stacked-form `B2`/`B3` CSVs. The routing table becomes a descriptive input to
checkpoint #2; the user's checkpoint answer is authoritative for Phase 2.

### Phase 1B tables and slides

- One bare-`tabular` `.tex` wide-form relevance table per margin —
  **2 tables**, booktabs only, INV-13.
- One wide-form relevance slide per margin — **2 frames**. Every
  regression-table slide note states, verbatim: "The AR statistic is a
  cluster-robust joint Wald test on the instrument coefficients only --- not on
  all regressor coefficients. The exposure control is included in every
  specification." The note additionally states that relevance is measured by
  the first stage matching the AR test — same unit, FE, EC, and clustering.
- Relabel the demoted slides: the 4 stacked-form multi-channel slides added
  earlier this session get a one-line note marking them as a stacked-form
  descriptive companion that does **not** feed the routing rule or the
  exclusion diagnostic.
- Copy the 2 tables into `journal/meetings/2026-05-21/tables/`; recompile
  `slides.tex`; confirm no missing references and no new overfull boxes.

## Mandatory user checkpoint #2 (end of Phase 1B)

**Phase 2 does not begin until the user responds.**

Report to the user, for **each margin** separately:
- per channel and per admissible stack — the SW $F$ per share, the KP rank
  statistic, and the count of identified shares — the wide-form relevance
  verdict;
- a contrast of the wide-form verdict with the stacked-form `B2b` verdict, so
  the user sees where they diverge — in particular for the M$\cdot$G channel.

Then ask explicitly: **which composition instrument set(s) should be carried
into the AR test in Phase 2?** Do not proceed until the user answers.

---

## Phase 2 — AR test extension (STUB — inputs depend on the Phase 1B decision)

Phase 2 cannot be fully specified now: its instrument sets are whatever the
user selects at checkpoint #2, restricted to the checkpoint-#1-admissible sets.
What Phase 2 *will* do:

- Extend `B6_three_volume_ar.R` to run the AR test on the user-chosen
  composition set(s), keeping the three-volume structure: (i) no volume
  control; (ii) volume as a predetermined control; (iii) Full IV. EC always
  included; AR statistic $=$ cluster-robust joint Wald on the instrument
  coefficients only.
- Pair every AR result with its **Phase 1B wide-form relevance verdict**, and
  report an **exclusion-diagnostic flag**: a channel that is wide-form
  irrelevant yet rejects the AR test signals a direct path to GDP — an
  exclusion-restriction violation. This is the diagnostic the wide-form first
  stage was put in place to support.
- Run for both margins; generate bare-`tabular` tables, copy to
  `journal/meetings/2026-05-21/tables/`, add frames to `slides.tex`,
  recompile and re-verify.

**Open until checkpoint #2:** the number of instrument sets, whether the
chosen sets are stacked or per-channel, and whether a volume channel supplies
the Full-IV column.

## Stacked-form scripts — demoted to descriptive companion

`B2`, `B2b`, `B3`, `B3b` remain in the pipeline and keep their outputs, but as
an **informal descriptive companion only**. They are explicitly **not** the
verdict that feeds the routing rule or the exclusion diagnostic. Their slides
carry the relabel from the Phase 1B step. `B4` no longer reads their CSVs.

## Wire into the runner

`run_phase_bc.R` runs the phases in three gated passes, not straight through:
- **Phase 1A pass:** run `B7_collinearity_diagnosis.R` for both margins, then
  stop for checkpoint #1.
- **Phase 1B pass:** after checkpoint #1, run `B8_wide_first_stage.R` then
  `B4_channel_routing.R` for both margins, then stop for checkpoint #2.
- **Phase 2 pass:** after checkpoint #2, run the `B6` extension.

Add `B7` and `B8` to the runner with a `--phase={1a,1b,2}` selector so each
pass is invoked separately and the runner cannot skip a checkpoint. `B2`,
`B2b`, `B3`, `B3b`, `B5` stay in the runner as descriptive companions, run in
the Phase 1A pass alongside `B7`.

## Files

| File | Role | Phase |
|---|---|---|
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B7_collinearity_diagnosis.R` | new — collinearity diagnosis, proposed admissibility verdict | 1A |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B8_wide_first_stage.R` | new — wide-form first stage, SW $F$ + KP rank | 1B |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B4_channel_routing.R` | edit — consume B8 wide-form verdict + user-confirmed admissibility | 1B |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/run_phase_bc.R` | edit — add B7, B8; `--phase` selector; three gated passes | 1 |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/00_helpers.R` | reused — channels, formatters, labels (no change expected) | 1 |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B6_three_volume_ar.R` | edit — AR on user-chosen sets + exclusion-diagnostic flag | 2 |
| `journal/meetings/2026-05-21/tables/collinearity_diagnosis_policy_block.tex` | new — generated table | 1A |
| `journal/meetings/2026-05-21/tables/collinearity_diagnosis_policy_block_size_bin.tex` | new — generated table | 1A |
| `journal/meetings/2026-05-21/tables/wide_first_stage_policy_block.tex` | new — generated table | 1B |
| `journal/meetings/2026-05-21/tables/wide_first_stage_policy_block_size_bin.tex` | new — generated table | 1B |
| `journal/meetings/2026-05-21/slides.tex` | edit — 2 frames at 1A, 2 frames at 1B, relabel 4 demoted frames | 1 |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B2_composition_first_stage.R` | demoted — stacked-form descriptive companion (no change) | — |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B2b_composition_multichannel.R` | demoted — stacked-form descriptive companion (no change) | — |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B3_volume_first_stage.R` | demoted — stacked-form descriptive companion (no change) | — |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B3b_volume_multichannel.R` | demoted — stacked-form descriptive companion (no change) | — |

## Verification

**Phase 1A (before checkpoint #1):**
- [ ] `B7_collinearity_diagnosis.R` runs without error for both `--tax` values.
- [ ] `B7` produces `instrument_admissibility_<tax>.csv` with a condition
      number, worst VIF, and KP rank statistic per candidate stack, and the
      interaction-construction audit result.
- [ ] Both collinearity-diagnosis `.tex` tables present in
      `journal/meetings/2026-05-21/tables/`; `slides.tex` compiles under
      XeLaTeX with no missing references and no new overfull boxes on the
      2 added frames.
- [ ] Checkpoint #1 report (proposed admissibility + interaction audit +
      design attribution) is presented; Phase 1B does not start before the
      user prunes the instrument set.

**Phase 1B (before checkpoint #2):**
- [ ] `B8_wide_first_stage.R` runs without error for both margins, on the
      user-pruned set only; the wide-form first stage uses muni-year
      observations, FE $=$ muni $+$ year, the EC control, and muni
      clustering — matching the AR test.
- [ ] `B8` produces `wide_first_stage_<tax>.csv` with the SW $F$ per share and
      the KP rank statistic per instrument set.
- [ ] `B4_channel_routing.R` consumes the B8 wide-form verdict and the
      user-confirmed admissibility set, not the B2/B3 stacked CSVs.
- [ ] Both wide-form relevance `.tex` tables present; `slides.tex` recompiles
      cleanly; the 4 demoted stacked-form frames carry the
      descriptive-companion relabel.
- [ ] Every new regression-table slide note carries the instruments-only Wald
      statement verbatim.
- [ ] Checkpoint #2 report (wide-form relevance, contrasted with the
      stacked-form verdict) is presented; Phase 2 does not start before the
      user specifies the composition instrument set(s).

**Phase 2 (after the checkpoint-#2 decision):**
- [ ] `B6_three_volume_ar.R` extension runs without error for both margins,
      restricted to checkpoint-#1-admissible sets.
- [ ] Each AR result is paired with its wide-form relevance verdict and the
      exclusion-diagnostic flag.
- [ ] AR tables generated, copied to the meeting `tables/` folder, slides
      updated, deck recompiles under XeLaTeX with no missing references.

**Process:**
- [ ] On user approval of this revised plan, set `status: APPROVED`, write the
      post-plan session log, and add the framing decision (wide-form first
      stage for relevance) to `docs/PROJECT_BLUEPRINT.md` §6 and the decision
      log in the same commit as Phase 1A work.
- [ ] On completion, set `status: COMPLETED`, add `completed: YYYY-MM-DD`, and
      rewrite the Status prose — in the same commit as the final work
      (workflow.md §1 step 10).
