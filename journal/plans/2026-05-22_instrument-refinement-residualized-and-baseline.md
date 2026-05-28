---
title: Instrument refinement — residualized interaction first stages and baseline-period sensitivity
status: DRAFT
date: 2026-05-22
---

# Plan: Residualized interaction first stages + baseline-period sensitivity

## Why this plan exists

Two refinements to the first-stage relevance work, both deferred from the
2026-05-21 checkpoint #2. The current `B8_wide_first_stage.R` evaluates the raw
instrument stacks; checkpoint #2 presents those results as-is. This plan is the
agreed next step — it does **not** alter `B8` or the slides being shown at the
2026-05-21 meeting.

Two parts. They are independent and can run in either order, though Part 1 is
cheap (extends existing scripts) and Part 2 is heavy (rebuilds the instrument
pipeline). Default order: Part 1, then Part 2.

- **Part 1 — residualized interaction first stages.** Implement the
  interaction-as-differencing design: an interaction instrument as the *only*
  excluded instrument, with its lower-order single-office instrument and EC
  blocks moved into the *control* set.
- **Part 2 — baseline-period sensitivity.** Test whether a fresher,
  cycle-specific affiliation baseline changes first-stage relevance, and
  characterize the relevance-vs-contamination trade-off.

---

## Background — Part 1: the differencing argument

The cross-office interaction instruments (MP, MG, MGP) carry a stronger
exclusion argument than their single-office parents, but only if the design is
specified correctly. Take MP. The worst exclusion threat for a presidential
instrument is a direct fiscal path — federal transfers, procurement, BNDES
capital lifting GDP outside the employment-composition channel. That threat is
a property of the **presidential main effect**: it is present for every
president-aligned municipality regardless of mayoral turnover.

If the single-office instrument blocks (`Z_M`, `Z_P`) and their EC blocks enter
the GDP equation as **exogenous controls**, the MP coefficient is identified
off variation orthogonal to both main effects. The pure-presidential fiscal
path differences out; so does the pure-mayoral municipal-favoritism path. The
exclusion restriction shrinks from "no single-office direct path" to "no
super-additive, interaction-specific direct path" — a much narrower, more
contrived violation. This is the standard result that an interaction term
carries a weaker exclusion requirement than its components, conditional on
controlling the components (Nizalova–Murtazashvili; Bun–Harrison).

**The current `B8` does not implement this.** The `B8` MP row is
`log_gdp ~ EC_MP + vol_ratio | muni + year | s_j ~ Z_MP` — it never partials
`Z_M`, `Z_P` out of the GDP equation. The `{M,P,MP}` stack does not implement
it either: it treats all three as *excluded* instruments (the dilution case,
not the differencing case). `Z_M`-as-control and `Z_M`-as-instrument are
different specifications, and the differencing argument requires the former.

**Differencing also re-prices relevance.** The `B8` SW F = 14.25 for MP is the
*raw* number, `Z_MP` as sole excluded instrument. Once `Z_M`, `Z_P` are
controls, the relevant first stage is *residualized* MP. Phase 1A established
that `Z_M`, `Z_P`, `Z_MP` are highly correlated; residualizing removes the
shared variation. The residualized SW F will be *below* 14.25, possibly below
10. That is not a side effect — it is the test. Differencing buys a cleaner
exclusion story by spending relevance, and whether MP survives is whether
enough interaction-specific variation remains. The residualized SW F — not the
raw `B8` number — is the relevance verdict to carry forward.

## Background — Part 2: baseline period and exogenous-shifts identification

The instrument is a shift-share object: firm-owner partisan affiliation (the
exposure) interacted with political turnover (the shift). Under
exogenous-*shifts* identification (Borusyak–Hull–Jaravel), the exposure shares
may be endogenous — correlated with local economic structure or GDP levels.
What identification requires is that the shares are **predetermined relative to
the shock they are paired with**: determined before that cycle's election, and
not chosen in anticipation of it.

The current baseline measures affiliation before the **earliest** election in
the panel. That is predetermined w.r.t. every cycle — stronger than necessary.
The cost is staleness: pre-2002 affiliation instrumenting a 2014 cycle is
twelve years old, and stale exposure predicts treatment poorly. A
**cycle-specific** baseline — affiliation measured between the previous
election and the current one — is still predetermined w.r.t. the current
cycle's shock, hence BHJ-admissible, and should be more relevant.

The binding constraint is **anticipation**, not endogeneity. "Uncontaminated"
does not mean exogenous shares; it means the shares are not a function of the
realized shock or chosen in anticipation of it. If owners re-affiliate
strategically before an election to position for BNDES access, a baseline
measured close to the election is contaminated. That channel is plausible
because the paper's thesis is that political connections pay off — so a
strategic-re-affiliation check is mandatory for any fresher baseline.

**A note on collinearity.** Phase 1A found the identical pre-earliest-election
window is one driver of the MP/MG/MGP collinearity. Per-office cycle-specific
windows separate the mayoral leg's window from the gov/pres leg's window and
add freshness — but they do **not** separate MG from MP: governor and president
share the election calendar (2002/06/10/14), so their windows coincide.
MG-vs-MP differentiation must come from the alignment columns, not the window,
and verticalização keeps the two near-identical for 2002/2006 regardless of
baseline. The freshness gain is the real prize; collinearity relief is at most
partial.

---

## Part 1 — Residualized interaction first stages

New script `B9_residualized_interactions.R` (leaves `B8` frozen as the
checkpoint deliverable). Runs on the muni-year AR panel
(`muni_panel_ar_<tax>.qs2`), both margins.

### 1.1 The specification

For an interaction channel, the excluded instrument is the interaction block
only; the single-office instrument and EC blocks are exogenous controls. MP:

```
log_gdp ~ EC_M + EC_P + EC_MP + vol_ratio + Z_M + Z_P | muni + year | s_j ~ Z_MP
```

- Excluded instrument: `Z_MP` block (J columns).
- Exogenous controls: `Z_M` block, `Z_P` block, the three EC blocks, `vol_ratio`.
- FE: muni + year. Clustering: by muni.
- Relevance: Sanderson–Windmeijer first-stage F per share, computed on the
  *residualized* MP; Kleibergen–Paap rank statistic.
- AR / Wald: on the `Z_MP` coefficients only — never on the control or
  single-office coefficients.

### 1.2 Channels

- **MP** — control `M`, `P`.
- **MG** — control `M`, `G`.
- **MGP** — hierarchical lower-order controls `{M, G, P, MG, MP, GP}`. Flag as
  likely degenerate: after residualizing the three-way interaction on six
  near-collinear lower-order blocks, little usable variation is expected to
  remain. Before reporting any MGP number, check the condition number and rank
  of the residualized block; if rank-deficient, report MGP as inadmissible for
  the differencing design rather than reporting a misleading F.

The workable rigorous design is the two-way interactions. MGP is a likely
casualty — report it as such.

### 1.3 The differencing diagnostic

For MP and MG, run the instrument both ways:
- residualized (single-office blocks as controls — §1.1);
- raw (single-office blocks excluded — the `B8` spec).

Compare the AR p-value and the SW F across the two. Stability → the interaction
carries the identification. Collapse when the main effects enter → the
instrument was riding a main-effect path. Report the residualized-vs-raw SW F
gap explicitly: it quantifies the relevance the differencing spends.

### 1.4 Outputs

- `output/residualized_first_stage_<tax>.{csv,tex}` — residualized SW F per
  share, KP rank, ID count, per interaction channel; raw-vs-residualized
  comparison columns.
- The residualized AR result feeds the Phase 2 AR extension (`B6`), replacing
  the raw interaction rows for the channels carried forward.

---

## Part 2 — Baseline-period sensitivity

New script `B10_baseline_sweep.R`. Heavier than Part 1: it rebuilds the
affiliation/exposure object and the instruments for each baseline definition,
then re-runs the wide-form first stage. Requires a parameterized
baseline-window argument in the instrument-construction pipeline
(`scripts/R/3_instruments/`).

### 2.1 Baseline definitions

The window over which firm-owner partisan affiliation is measured:

- **B0 — pre-earliest-election (anchor).** Current design. Predetermined
  w.r.t. every cycle. Conservative; referee-proof.
- **B1 — cycle-specific, inter-election window.** Affiliation measured over the
  years strictly between the previous election and the current cycle's
  election, dropping the immediate pre-election year to blunt anticipation.
- **B2 — cycle-specific, fixed short lag.** Affiliation at t−2..t−1 relative to
  the cycle's election.
- **B3 — cycle-specific, just-after-previous-election.** Maximal distance from
  anticipation of the next election while still cycle-fresh.

### 2.2 Baseline windows for interaction channels

A cycle-specific baseline is defined **per office**. Each municipality-year
observation inherits its windows automatically: `W_M` is the window before that
observation's most-recent mayoral election, `W_P` (`W_G`) the window before its
most-recent presidential (gubernatorial) election. No joint "interaction cycle"
is defined.

For an interaction channel the instrument is the product of leg-specific
alignments, each computed from owner affiliation measured in that leg's window:
`Z_MP ∝ align_M(W_M) × align_P(W_P) × turnover`. Each leg is predetermined
w.r.t. its own office's election — which is all predeterminedness requires. The
windows overlap in calendar time (4-year windows two years apart share ~2
years); overlap is harmless, because each leg is clean w.r.t. its own election
regardless of where the other office's election falls.

Corollary: when the windows overlap heavily and affiliation is stable, the
two-window design collapses to the single-window design — it bites only when
owner affiliation changes between `W_M` and `W_P`, which is exactly the
strategic-re-affiliation churn the §2.4 placebo tests. The two-window
construction and the contamination placebo are the same diagnostic.

### 2.3 The relevance sweep

For each baseline definition: rebuild affiliation → rebuild instruments → run
the `B8` wide-form first stage → record SW F per share, KP rank, ID count, both
margins. Output a relevance-vs-baseline table: SW F as a function of baseline
window, per channel, per share.

### 2.4 Contamination diagnostics (for the fresher baselines B1–B3)

- **Strategic-re-affiliation placebo.** Do firm-owner affiliation *changes*
  cluster in pre-election years? Clustering indicates owners re-affiliate in
  anticipation — fresher baselines would then be contaminated.
- **Pre-trend / placebo outcome.** Does the fresher-baseline instrument predict
  GDP growth in the pre-period (before the cycle's election)? A clean
  instrument should not.
- **Lag robustness.** Compare instruments built with vs without the immediate
  pre-election year.

### 2.5 Decision rule

- Relevance flat across baselines → keep B0 (cleanest). The pre-earliest
  baseline costs nothing; retain it.
- Relevance rises materially with fresher baselines → real trade-off. Adopt the
  freshest baseline that passes all §2.4 diagnostics; keep B0 as the robustness
  endpoint. Report the sweep as a sensitivity panel regardless of the verdict.

### 2.6 Outputs

- `output/baseline_sweep_<tax>.{csv,tex}` — SW F / KP by baseline window and
  channel.
- `output/baseline_contamination_<tax>.{csv,tex}` — the three §2.4 diagnostics.

---

## Files

| File | Role | Part |
|---|---|---|
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B9_residualized_interactions.R` | new — residualized interaction first stages + differencing diagnostic | 1 |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B10_baseline_sweep.R` | new — baseline-period relevance sweep + contamination diagnostics | 2 |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/B6_three_volume_ar.R` | edit — AR extension consumes residualized interaction rows | 1 |
| `scripts/R/3_instruments/` (affiliation / alignment-shock builders) | edit — parameterized baseline-window argument | 2 |
| `explorations/anderson_rubin/ar_meeting_2026_05_13/R/run_phase_bc.R` | edit — register B9, B10 | 1,2 |
| `journal/meetings/<date>/slides.tex` | edit — frames for residualized and baseline results (date TBD, not the 2026-05-21 deck) | 1,2 |

`B8_wide_first_stage.R` and the 2026-05-21 slides are **not** modified by this
plan.

## Verification

**Part 1:**
- [ ] `B9` runs without error for both margins.
- [ ] Residualized SW F, KP rank, and ID count reported per interaction
      channel; raw-vs-residualized comparison present.
- [ ] MGP residualized-block rank/condition checked before any MGP F is
      reported; degeneracy reported honestly if present.
- [ ] Differencing diagnostic (residualized vs raw AR p-value) reported for
      MP and MG.

**Part 2:**
- [ ] Instrument pipeline accepts a baseline-window argument; `B10` rebuilds
      instruments for B0–B3 without error.
- [ ] Relevance-vs-baseline table produced, both margins.
- [ ] All three contamination diagnostics run for the fresher baselines.
- [ ] Decision rule applied; verdict and retained baseline documented.

**Process:**
- [ ] On approval, set `status: APPROVED`, write the post-plan session log.
- [ ] Add the two angles to `docs/PROJECT_BLUEPRINT.md` §4 (open angles) with
      A-numbers — residualized interaction design, baseline-period sensitivity.
- [ ] On completion, set `status: COMPLETED`, add `completed:`, rewrite the
      Status prose.

## Open questions for the user

1. **MGP under full hierarchical controls** — accept the likely degeneracy and
   drop MGP from the differencing design, or attempt a partial control set?
2. **Baseline windows** — are B0–B3 the right set, or a different sweep? The
   per-office, two-window construction for interaction channels is settled
   (§2.2).
3. **Anticipation channel** — is strategic owner re-affiliation considered
   plausible enough to gate the fresher baselines on the §2.4 placebo, or is
   owner partisanship treated as effectively fixed?
4. **Identification frame** — the exogenous-*shifts* frame raises a
   many-shocks requirement, and the answer is channel-specific. Mayoral
   turnover varies at muni × election (~tens of thousands of independent shock
   realizations), so the requirement is met for M and for the mayoral-gated
   interactions, which inherit the staggering. Gubernatorial shocks (~27 states
   × 4 cycles) are moderately many. The presidential shock is national (~4,
   serially correlated) — few shocks, and >5,000 munis do not help, since they
   all share one shock. This is independent confirmation of the mayoral gating
   and one more reason G/P stay diagnostic-only. Inference: cluster at muni or
   muni-cycle for the mayoral channels (standard, many clusters); a BHJ
   shock-level recentering is a robustness check, mainly to show the
   shared-shock channels are not relied on. Caveat: many shocks satisfies the
   count, not quasi-random assignment — that remains the identifying
   assumption, conditional on muni + year FE. Still open: whether to fold the
   BHJ recentering robustness check into this plan's scope.
5. **Order** — Part 1 first (cheap, extends existing scripts) then Part 2
   (heavy, rebuilds the instrument pipeline)?
