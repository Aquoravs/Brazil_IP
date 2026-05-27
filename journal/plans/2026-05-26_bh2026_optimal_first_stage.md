---
title: BH-2026 optimal formula instruments — firm-coefficient aggregated predictor + permutation recentering
status: DRAFT
date: 2026-05-26
supersedes: journal/plans/bh2026_implementation_prompt.md
---

# Plan: BH-2026 optimal formula instruments for the sector first stage

## Why this plan exists

Three converging reasons.

1. **D32 commitment, 2026-05-20.** "Recentering the alignment shocks
   (Borusyak–Hull) is adopted as the planned robustness route to an
   EC-free specification that preserves mass." This plan is what D32
   promised: a recentered shift-share instrument that does not need the
   per-channel exposure control as a regression covariate.
2. **First-stage relevance is a project goal in its own right.** The
   Anderson-Rubin pipeline is weak-IV-robust, but standard 2SLS reporting
   remains part of the manuscript and benefits from a strong first stage.
   Borusyak and Brown (2026, "Optimal Formula Instruments") give the
   sharpest available method for raising first-stage R² without compromising
   validity. Their Lemma 1 establishes that the recentered best predictor
   maximizes first-stage R² among recentered IVs. This is exactly the
   target we want.
3. **The current sector first stage is informative but weak.** Production
   AR rejects at `policy_block` with F = 4.37; at `cnae_section` with
   F = 2.05 (D29). The deferred `policy_block × S3` margin (D28) is
   diagnostically strongest at F1 but blocked at F2 because no graduated
   first stage exists. A more powerful instrument helps all three margins
   and unblocks the size-crossed graduation conversation.

This plan replaces `journal/plans/bh2026_implementation_prompt.md`, which
was written under superseded assumptions (legacy paths, legacy endogenous
variable, legacy instrument architecture). The engineering content is
preserved where compatible; the framing, paths, endogenous variable,
channel architecture, predictor functional form, and success criterion are
all updated.

## Background — what BH-2026 buys, briefly

Borusyak and Hull construct optimal formula instruments in three steps
(Algorithm 1, page 14):

1. Form a treatment predictor `p(g, w)` using the treatment formula —
   replacing unobserved or endogenous inputs `u` with a base value.
2. Recenter the predictor by subtracting its expectation over permutations
   of the exogenous shocks: `z̃ = p(g, w) − E[p(g, w) | w]`.
3. (Optional) Residualize on predetermined covariates and reweight by an
   estimate of `Var[ε|w]⁻¹`.

**Lemma 1** (page 14): among all recentered IVs, the recentered best
predictor `z̃` maximizes first-stage R². So Steps 1–2 alone deliver the
relevance gain we want.

**Algorithm 1 does not require cross-fitting** (page 15, explicit).
Cross-fitting belongs to a different alternative (the nonparametric
plug-in of Online Appendix D.3) with stronger asymptotic claims but a
nonparametric-consistency requirement. We adopt Algorithm 1 — parametric
predictor plus permutation recentering — as the production design, with
cross-fit predictions reported as a finite-sample sanity check
(user-confirmed 2026-05-26).

**Mapping to our setting.** The sector-level endogenous is sector
employment share `s^emp_{j,m,t}` (per D24). The "treatment formula" we
exploit is the additive decomposition

```
s^emp_{j,m,t} = Σ_{f ∈ S_j ∩ M_m} s^emp_{f,m,t}
```

where `s^emp_{f,m,t} = n_{f,m,t} / Σ_{f' ∈ M_m} n_{f',m,t}` is firm `f`'s
share of muni `m` employment in year `t`. Predicting `s^emp_{f,m,t}`
at firm level and summing over firms in sector `j` gives a sector-level
predictor whose aggregation is *additive* — sidestepping the ratio
nonlinearity (Boustan-style mechanism 3) that the original BH plan
flagged as irreducible.

## Scope and out-of-scope

**Margin run order.** The firm panel is 44M rows; the Phase 2 grid is
21 firm-level fits × 4 leave-one-out folds = 84 fits. Running both
margins in lockstep doubles every downstream object (predictors,
permutation maps, recentered instruments, AR tables). Operational
default is therefore: **run `policy_block` end-to-end first** (Phases
1 → 5), confirm sanity checks pass, then re-enter at the earliest
phase affected by adding `policy_block × S3`. The orchestrator's
`--margin` flag exposes this — `--margin=policy_block` is the default,
`--margin=policy_block_size_bin` runs the size-crossed margin in
isolation, and `--margin=both` does the comparison sweep. The plan's
side-by-side output tables (e.g., §4.1's four-column wide-form table)
are still expressed across margins; they are simply assembled in the
final pass after both margins have been run.

In scope:

- Phase 1 — diagnostic audit at `policy_block` (primary) and
  `policy_block × S3` (deferred top candidate). Measure the three
  mechanisms; quantify the gain ceiling. Default run order:
  `policy_block` first, `policy_block × S3` second.
- Phase 2 — firm-level first stage with OLS on `s^emp_{f,m,t}` (primary
  functional form per user confirmation 2026-05-26); grid search across
  channel sets and baseline windows; held-out sector first stage selects
  the champion.
- Phase 3 — permutation recentering of the champion predictor and close
  runners-up. Channel-aware permutation design.
- Phase 4 — wide-form sector first stage and AR test with the recentered
  instrument; comparison against the production `Z` and the
  non-recentered `ŝ`.
- Phase 5 — documentation: `methodology/ar_test_specification.tex`,
  `docs/decision_log.md`, `docs/research_state.md`,
  `docs/PROJECT_BLUEPRINT.md` §3 and §7.

Out of scope:

- PPML on `n_{f,m,t}` as the firm-level functional form. Confirmed as
  *robustness only*, deferred. May be added later if the OLS predictor
  underperforms or if mechanism 3 is large.
- Cross-fitting as the production discipline. Cross-fit predictions are
  reported as a sanity check, not as the production object.
- The GLS-style Step 3 adjustment (`Var[ε|w]⁻¹` reweighting). Skipped
  per Lemma 2 minimax justification.
- Modifications to numbered production scripts (`scripts/R/`). All work
  lands in `explorations/anderson_rubin/bh2026_recentering/` per the
  production-pipeline caveat in `CLAUDE.md`. Graduation to production
  follows separately if and when the method review settles.

## Phase 1 — Diagnostic audit

**Goal:** measure how much room there is to gain on each of the three
mechanisms identified in the original plan, at both production margins,
so that the Phase 2 grid is dimensioned to the actual problem.

**Margins:** `policy_block` (4 blocks) and `policy_block × S3` (12 cells).
Drop `cnae_section` from this phase — it is robustness-only per D29.

**Mechanisms (one diagnostic each):**

- **D1 — aggregation weight sensitivity.** Read the existing script 53
  spec-engine output, filter to the four instrument-weight variants
  (`owner_count`, `employment`, `equal_firm`, `binary`), tabulate
  wide-form first-stage F per channel at both margins, side-by-side. Add
  a placeholder row for `firm_coef` that Phase 2 fills in. This is a
  *re-read* of existing output, not a new estimation.
- **D2 — within-cell heterogeneity.** For each `(j, m, t)` cell at both
  margins, compute `Var_f(FA^c_{f,m,t})` and the count of firms with
  positive vs negative firm-level alignment. Summarize: distribution of
  `Var_f` across cells (deciles), fraction of cells with mixed signs,
  correlation between `Var_f` and `|mean FA_f|` within cell. Run
  separately for the four candidate single-office channels (M, G, P) and
  for one cross-office channel (MG, as the strongest D34 candidate).
- **D3 — ratio diagnostic.** Re-run the existing sector first stage with
  three alternative LHS variables at both margins, keeping the production
  instrument unchanged:
  1. `log(n^emp_{j,m,t})` — pure level, no ratio.
  2. `s^emp_{j,m,t}` — the production endogenous.
  3. The additive predictor `Σ_f s^emp_{f,m,t}` constructed directly
     (no firm-level model) as an algebraic identity. Should match (2)
     exactly up to firm-support definition.

Report wide-form F at the production instrument across the three. A
large gap between (1) and (2) flags mechanism 3 as dominant; the (2)–(3)
gap quantifies firm-support construction effects only.

**Output:**

- `output/audit_aggregation/results.qs2` — F-stats, partial R², coefs,
  SEs, all diagnostics.
- `output/audit_aggregation/summary.md` — three tables (D1, D2, D3),
  one-paragraph interpretation: which mechanism(s) dominate at each
  margin, expected gain ceiling from Phases 2–3.

**Stop point:** present `summary.md` to user before launching Phase 2.

## Phase 2 — Firm-level predictor with grid search

**Goal:** estimate a firm-level model that predicts each firm's share of
muni employment, and select the variant that maximizes *held-out*
sector-level first-stage F.

### 2.1 The firm-level regression — primary specification

Dependent variable: `s^emp_{f,m,t}` (firm `f`'s share of muni `m`'s
total formal employment in year `t`, from the RAIS skeleton).

Excluded instrument: firm-level alignment `FA^c_{f,m,t}` for channel
set `c`. `FA^c` is the channel-`c` alignment shock interacted with
firm-owner partisan exposure, constructed identically to the production
firm-level instrument (script 36) but parameterized by channel set and
baseline window.

Specification:

```
s^emp_{f,m,t} = α_f + δ_{m,t} + λ^c · FA^c_{f,m,t} + u_{f,m,t}
```

- FE: `firm_id + muni_id × year` (fixed).
- Weights: pre-election baseline employment `bl_n_employees`
  (per D7); equal-weighted as robustness.
- Clustering: two-way, `firm_id + muni_id`.
- Estimator: `fixest::feols` (linear OLS, primary). PPML is *deferred
  robustness only*, not run in this iteration.

**Why OLS on `s^emp_{f,m,t}` and not on `n_{f,m,t}` or a two-part model.**
Three reasons. (a) The additive decomposition above means the sector-level
predictor `Σ_f ŝ^emp_{f,m,t}` is mechanically a predictor of
`s^emp_{j,m,t}` — no ratio is formed at aggregation, so mechanism 3 is
avoided at construction. (b) Lemma 1 of BH-2026 applies to the additive
predictor without modification. (c) The two-part Duan-smearing alternative
introduces an assumption (lognormality of residuals) that is hard to
defend with the extreme zero-inflation of BNDES disbursements; we side-step
this by predicting shares directly. PPML survives as a deferred robustness
option.

### 2.2 The grid

We search over two firm-level dimensions:

| Dimension       | Variants                                                                                                                                                                                                        |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Channel set `c` | `{M}`, `{G}`, `{P}`, `{M·G}`, `{M·P}`, `{G·P}`, `{M·G·P}` — seven single-channel candidates. Stacks added if the D34 routing rule selects a stack with multiple channels relevant at the saturated first stage. |
| Baseline window | channel-specific pre-earliest-election (D31 primary, Variant F); pre-mayoral (Variant A, mechanism-aligned robustness); higher-tier pre-window (Variant E, second timing robustness). Three variants. Pending discussion before Phase 2 launches. |

Fixed across all specifications: FE = `firm + muni×year`; sample = private
productive firms only (D5-op). Full grid is `7 × 3 = 21` firm-level
specifications. Recentering (Phase 3) preserves validity for any selected
variant.

### 2.3 Held-out evaluation discipline

Selection is by **held-out sector first stage F**, not in-sample F. The
four mayoral electoral cycles in 2002–2017 are:

| Fold | Years | Underlying election |
|---|---|---|
| 1 | 2002–2004 | post-2000 (truncated by data start) |
| 2 | 2005–2008 | post-2004 |
| 3 | 2009–2012 | post-2008 |
| 4 | 2013–2017 | post-2012 (2017 folded in: the 2016 election's term lies mostly outside the panel) |

Folds are defined on the mayoral calendar because M is the most
data-rich channel and the FE structure pivots on muni × year. For
cross-office channels involving G or P, the same fold partition is
used — the gubernatorial 2002/2006/2010/2014 calendar and the
presidential 2002/2006/2010/2014 calendar align with these fold
boundaries to within ±1 year, which is sufficient for honest holdout.

For each variant:

- Fit the firm-level model on three cycles.
- Predict `ŝ^emp_{f,m,t}` on the held-out cycle (out-of-sample for the
  firm coefficients).
- Aggregate to `ŝ^emp_{j,m,t}` within the held-out cycle.
- Compute the wide-form sector first stage F on the held-out cycle,
  pooled across the four leave-one-out folds.

Rank variants by the pooled held-out F. The champion is the variant with
the highest held-out F; close runners-up (within 2 F units) are carried
into Phase 3 for the robustness sweep.

This discipline is honest because Lemma 1 guarantees first-stage R²
optimization for the *population* recentered best predictor; selecting by
held-out F prevents finite-sample overfit from masquerading as relevance.
Type-I rate on the downstream AR test is preserved by recentering (Phase
3), independently of how the firm-level model was selected.

### 2.4 Production object

In addition to the cross-fit predictions used for evaluation, fit the
champion variant on the **full sample** (no holdout) for production. The
full-sample fit is the predictor we recenter and ship. The cross-fit
predictions are reported as a sanity check ("the production predictor's
held-out F equals X; the in-sample F equals Y; the gap quantifies
finite-sample overfit"). Confirmed by user 2026-05-26: full-sample
fit is the production object.

### 2.5 Aggregate firm → sector

```
ŝ^emp_{j,m,t} = Σ_{f ∈ F^pre_{j,m}}  ŝ^emp_{f,m,t}
```

`F^pre_{j,m}` is the pre-election firm support — same convention as the
existing exposure-weight builder (stage 32c hybrid skeleton, D29). This is
load-bearing: using the contemporaneous post-election firm set would inject
post-treatment composition into the instrument.

### 2.6 Outputs

- `output/firm_first_stage/grid_results.qs2` — for each of the 126
  variants: held-out F per margin, in-sample F per margin, partial R²,
  coefficient on `FA^c`, SE, N. Long format.
- `output/firm_first_stage/champion_predictor.qs2` — the **production**
  predictor at firm level, full-sample fit, with columns
  `firm_id, muni_id, policy_block, year, channel, ŝ^emp_{f,m,t}`. No
  `fold_id` column — the full-sample fit has no fold structure and is
  what gets recentered and shipped to Phase 3.
- `output/firm_first_stage/champion_predictor_crossfit.qs2` — the
  **sanity-check** companion, four leave-one-out cycle folds, with
  columns `firm_id, muni_id, policy_block, year, channel,
  ŝ^emp_{f,m,t}, fold_id` where `fold_id ∈ {1, 2, 3, 4}` indexes the
  held-out cycle from §2.3. Used only to report the held-out vs
  in-sample F gap as a finite-sample-overfit diagnostic; not
  recentered, not consumed by Phase 3.
- `output/firm_first_stage/champion_aggregated.qs2` — aggregated to
  `(muni_id, policy_block, year, channel, ŝ^emp_{j,m,t})` and
  `(muni_id, policy_block, S3, year, channel, ŝ^emp_{j,m,t})`, built
  from the production predictor (full-sample fit) only.
- `output/firm_first_stage/grid_summary.md` — table of top-10 variants
  by held-out F at each margin; champion identified; one paragraph on
  what the champion's firm-level structure looks like.

## Phase 3 — Permutation recentering

**Goal:** subtract from the champion (and runners-up) the expected
predictor over a permutation distribution of alignment shocks, holding
firm-level coefficients fixed.

### 3.1 Permutation classes

Channel-by-channel design:

- **Mayoral (M, and any cross-office channel involving M).** Within each
  `(state × inauguration_year)`, permute which municipalities saw which
  coalition win. Conditioning on state preserves the partisan
  geography; conditioning on inauguration year preserves the staggered
  timing.
- **Gubernatorial (G, and any cross-office channel involving G but not
  M).** Within each region (Norte, Nordeste, Centro-Oeste, Sudeste, Sul),
  permute which states saw which coalition win, per inauguration year.
  Region conditioning is appropriate because regional party support
  patterns are persistent.
- **Presidential (P, alone or with G but not M).** Only four
  cycle-level shocks. Recentering reduces to an empirical mean across
  cycles, which is absorbed by year FE. **Skip recentering for purely
  presidential channels**; document in the script header. Cross-office
  channels involving P are recentered via the M or G leg's permutation.
- **Cross-office channels (e.g., M·G).** Permute the joint draw
  `(M, G)` to preserve the interaction structure: the permuted M·G
  column must equal the product of the permuted M leg and the permuted
  G leg, not an independent permutation of M·G values. This honors the
  algebraic constraint flagged in D38. The single-office legs do not
  share a conditioning set — M's leg permutes within `(state × year)`,
  G's leg within `(region × year)` — so a rule is needed for which class
  governs the joint draw. The rule is given in §3.1.1.

#### 3.1.1 Joint conditioning rule for cross-office channels

When a cross-office channel combines two single-office legs with
**different** conditioning sets, the joint permutation runs **within the
finer of the two conditioning sets** — i.e., the governing class is the
intersection of the leg-level classes.

Concretely, for the three cross-office channels:

| Channel | M-leg class | G-leg class | P-leg class | **Joint governing class** |
|---|---|---|---|---|
| M·G | state × year | region × year | — | **state × year** (state ⊂ region) |
| M·P | state × year | — | year only | **state × year** |
| G·P | — | region × year | year only | **region × year** |
| M·G·P | state × year | region × year | year only | **state × year** |

The governing class is always the finest non-trivial one available. P
contributes no spatial conditioning, so it never tightens the class; it
only ever enters through M or G. When M is present, the joint runs
within state × year — this preserves both the state-level partisan
geography (which M alone requires) and the region-level pattern (which
state ⊂ region automatically enforces). When M is absent, the joint
runs within region × year, which is the strictest class that G alone
can support.

**Why "finer" rather than "coarser".** A finer conditioning class is
the weaker exogeneity assumption: it only requires quasi-random
assignment of the joint draw within smaller cells. The coarser class
(region × year for M·G, country × year for everything) would assume
cross-state or cross-region exchangeability of the joint mayoral-and-
gubernatorial coalition draw, which contradicts the documented spatial
persistence of Brazilian partisan structure (the same reasoning that
fixes G-leg permutation at region rather than country level). The
finer rule is also algebraically consistent with the leg-level
permutations: any permutation valid within state × year is *a fortiori*
valid within region × year, so the joint draw respects both leg
constraints simultaneously.

**Implementation.** When generating the J permutation maps for a
cross-office channel, draw the joint `(M, G)` outcome within the
state × year (or region × year, per the table) cell, then materialize
the cross-office shock as the product of the two permuted legs. Cache
the joint maps in `output/recentering/permutation_maps_<channel>.qs2`,
where `<channel>` includes the cross-office tag (e.g., `MG`, `MP`,
`MGP`).

The permutation design is exposed as a CLI flag:
`--permutation-design ∈ {state, state-margin, region, custom}`. Default
is `state` for M and `region` for G; `state-margin` (state × vote-margin
tercile) is reported as a conservative robustness column. For cross-
office channels the flag selects the M-leg or G-leg design; the joint
governing class follows the rule above. `custom` allows a
user-supplied conditioning column for the M or G leg (e.g., a finer
sub-state grid for a specific robustness sweep).

### 3.2 Generate `J` counterfactual alignment vectors

- Default `J = 200`. Override via `--J`.
- Pre-generate and cache `J` permutation maps once per channel.
- Reuse the same maps across `(j, m, t)` cells within a channel — this
  is the compute-saving trick. Maps live in
  `output/recentering/permutation_maps_<channel>.qs2`.

### 3.3 Recompute the predictor under each counterfactual

For each `j = 1..J` and each channel `c`:

- The firm-level coefficient `λ̂^c` from Phase 2 is held fixed —
  Phase 3 only varies the alignment input.
- Recompute `FA^{c,(j)}_{f,m,t}` using the permuted alignment.
- Recompute the firm-level prediction
  `ŝ^{emp,(j)}_{f,m,t} = α̂_f + δ̂_{m,t} + λ̂^c · FA^{c,(j)}_{f,m,t}`.
  The `α̂_f + δ̂_{m,t}` term does not depend on `j` and is cached once.
- Aggregate to `ŝ^{emp,(j)}_{j,m,t}` and `ŝ^{emp,(j)}_{j,m,S3,t}`.

### 3.4 Compute the recentered instrument

```
μ_{j,m,t}      = (1/J) · Σ_j  ŝ^{emp,(j)}_{j,m,t}
z̃_{j,m,t}     = ŝ^emp_{j,m,t} - μ_{j,m,t}
```

Same at the `policy_block × S3` margin. Repeat for each channel
separately and for the D34-routed stack (if any).

### 3.5 Sanity checks (must pass before Phase 4)

The predetermined covariate set `w` for the sanity check is fixed as

```
w = { muni FE,  year FE,  EC block for the channel under test }
```

This is the covariate set the AR-test regression conditions on under the
EC-included benchmark, so showing `mean(z̃ | w) ≈ 0` is the operational
meaning of D32's EC-free claim: if the recentered instrument has zero
conditional mean given (muni FE, year FE, EC), dropping the EC block from
the AR regression does not bias the coefficient on `z̃`. `w` does **not**
include `vol_ratio` — the volume control is treatment-stage, not a
predetermined recentering condition.

- `mean(z̃_{j,m,t} | w) ≈ 0`. Operationally: regress `z̃` on `w` (muni
  FE, year FE, EC of the channel under test) and report (i) the
  coefficient F-stat on the EC block, (ii) the intercept and its t-stat,
  (iii) a histogram of the residual `z̃`. All three are stdout-logged and
  saved to `sanity_log.md`, broken out by channel and margin.
- Drop-top-1 and drop-top-2 simplex-aware sanity (per D29): the recentered
  instrument respects the same drop-top-k structure as the production
  instrument; report `z̃` at the production drop-k specification.

### 3.6 Outputs

- `output/recentering/permutation_maps_<channel>.qs2` — cached
  permutation maps.
- `output/recentering/recentered_instrument_<margin>.qs2` — columns
  `muni_id, policy_block, [S3], year, channel, ŝ^emp, μ, z̃, J`.
- `output/recentering/sanity_log.md` — t-stats and histograms for the
  three sanity checks.

## Phase 4 — Wide-form first stage and AR test

**Goal:** quantify the relevance gain and demonstrate the EC-free
specification.

### 4.1 Wide-form first stage

Per D38, relevance is judged by the wide-form first stage:
muni-year observations, J-column-per-channel instrument block, FE = muni
+ year, EC control included as a benchmark and dropped as the target,
muni clustering.

Report a side-by-side table for each margin:

| | Production `Z` | Non-recentered `ŝ^emp` | Recentered `z̃` (no EC) | Recentered `z̃` (with EC) |
|---|---|---|---|---|
| Coefficient on instrument | | | | |
| Wide-form F | | | | |
| Partial R² | | | | |
| Condition number | | | | |
| KP rank statistic | | | | |
| N | | | | |

Two columns per cell — `policy_block` and `policy_block × S3`. The
"EC-free" column is the load-bearing one: if `z̃` clears relevance
without the EC, D32 is operationalized.

### 4.2 AR test

Run the full AR test at both margins with `z̃` (no EC), against the
production AR (F = 4.37, p = 2e-4 at `policy_block`; F = 2.05,
p = 2.1e-4 at `cnae_section` for reference). Three volume treatments:
no volume control, volume as predetermined control, volume instrumented
(D34/D35/D36 protocol).

### 4.3 Channel-set comparison

Report the top three channel sets (champion + two runners-up from Phase
2) side by side at the wide-form first stage and the AR test. The
production candidate is the recentered champion; the runners-up are the
robustness range. If the routing rule (D34) selects a different stack
than the champion at the saturated first stage, report both.

### 4.4 Outputs

- `output/sector_first_stage/widefirst_stage.{csv,tex}` — the §4.1
  side-by-side table.
- `output/sector_first_stage/ar_results.{csv,tex}` — AR p-values
  across the three volume treatments × four instruments × two margins
  × three channel sets.
- `output/sector_first_stage/findings.md` — short interpretation:
  did the recentered predictor raise relevance? Did the EC drop? Did
  the AR rejection survive? Which channel set is the production
  candidate?

## Phase 5 — Documentation

Update, on completion:

- **`docs/methodology/ar_test_specification.tex`** — new section
  "Optimal formula instruments (Borusyak–Brown 2026)" covering the
  predictor construction, the permutation class per channel, the
  sanity-check protocol, and the relevance / AR results. This section
  is what D32 (2026-05-20) committed to producing.
- **`docs/decision_log.md`** — append a D-numbered entry (D39 or later)
  recording the predictor-form choice (OLS on `s^emp_{f,m,t}`),
  permutation-class defaults, and the channel-set selection rule.
- **`docs/research_state.md`** — update F4 status row if the recentered
  predictor clears the EC-free relevance check at the production margin.
- **`docs/PROJECT_BLUEPRINT.md`** — update §3 (F-link status row for
  F2 and F4 if applicable), §6 (decisions log), and §7 (next action).
- **`docs/evidence_index.md`** — add a row for the recentered
  predictor's first-stage evidence.
- **`CLAUDE.md`** — only after graduation to production scripts.
  No edits in this plan.

## Files

| File | Role | Phase |
|---|---|---|
| `explorations/anderson_rubin/bh2026_recentering/README.md` | new — folder front door | 0 |
| `explorations/anderson_rubin/bh2026_recentering/R/B1_diagnostic_audit.R` | new — Phase 1 D1/D2/D3 | 1 |
| `explorations/anderson_rubin/bh2026_recentering/R/B2_firm_first_stage.R` | new — firm-level grid + held-out evaluation | 2 |
| `explorations/anderson_rubin/bh2026_recentering/R/B3_aggregate_predictor.R` | new — firm → sector aggregation, champion + runners-up | 2 |
| `explorations/anderson_rubin/bh2026_recentering/R/B4_recenter_predictor.R` | new — permutation recentering | 3 |
| `explorations/anderson_rubin/bh2026_recentering/R/B5_widefirst_stage.R` | new — wide-form first stage, side-by-side. Sources `00_ar_helpers.R` for the wide-form / KP-rank routines | 4 |
| `explorations/anderson_rubin/bh2026_recentering/R/B6_ar_test_recentered.R` | new — AR with `z̃`, three volume treatments. Sources `00_ar_helpers.R` rather than reimplementing the runner | 4 |
| `explorations/anderson_rubin/bh2026_recentering/R/00_ar_helpers.R` | new — shared AR helpers: `run_ar(channels, spec, instrument_block, vol_inst)`, `volume_first_stage()`, table builders (`build_screen_tex`, `build_vfs_tex`, `chan_code`, `tex_set_label`, `plain_set_label`, `ar_cell`). Logic is **ported** from `ar_meeting_2026_05_13/R/B9_stack_ar_screen.R`; B9 itself stays frozen. `run_ar()` is parameterized over the excluded-instrument column block (production `Z_*` vs. recentered `z̃_*`) so the same runner serves both Phase-4 deliverables and the legacy meeting screen | 4 |
| `explorations/anderson_rubin/bh2026_recentering/R/run_phase_bh.R` | new — orchestrator with `--dryrun`, `--phase`, `--margin`, `--channels` flags. `--margin ∈ {policy_block, policy_block_size_bin, both}`; default is `policy_block` (run the 4-block margin alone first, given the firm-panel compute cost), with `both` reserved for the comparison sweep once `policy_block` has cleared sanity checks. | all |
| `explorations/anderson_rubin/bh2026_recentering/SESSION_LOG.md` | new — incremental progress log | all |
| `docs/methodology/ar_test_specification.tex` | edit — new "Optimal formula instruments" section | 5 |
| `docs/decision_log.md` | edit — append D-entry on predictor form + permutation class | 5 |
| `docs/research_state.md` | edit — F4 status row, if applicable | 5 |
| `docs/PROJECT_BLUEPRINT.md` | edit — §3, §6, §7 | 5 |
| `docs/evidence_index.md` | edit — row for recentered predictor first-stage evidence | 5 |

No edits to `scripts/R/` production scripts in this plan. No edits to
`B7`–`B10` in `explorations/anderson_rubin/ar_meeting_2026_05_13/` (those
remain frozen as the 2026-05-21 meeting deliverable and the 2026-05-22
follow-up plan, respectively). The new `00_ar_helpers.R` in the BH-2026
folder **ports** — does not refactor — the AR runner and volume
first-stage logic that currently lives inline in `B9_stack_ar_screen.R`.
The meeting deliverable stays bit-identical; the helper is the forward
home for the runner. The new B5 and B6 source it instead of duplicating
B9 inline.

## Verification

**Phase 1:**
- [ ] `B1` runs without error at both margins.
- [ ] D1 table reports four weight variants × five channels × two margins.
- [ ] D2 deciles, mixed-sign fractions, and `Var_f`–`|mean FA_f|`
      correlations reported for the five channels × two margins.
- [ ] D3 wide-form F reported for the three LHS variables at both
      margins; mechanism-3 verdict stated in `summary.md`.
- [ ] **Stop point:** `summary.md` presented to user; Phase 2 awaits
      go-ahead.

**Phase 2:**
- [ ] `B2` runs the full `7 × 3 = 21` firm-level grid without error.
- [ ] Held-out F (four-fold cycle leave-one-out) reported per variant
      per margin.
- [ ] In-sample F reported alongside; the held-out vs in-sample gap is
      explicit.
- [ ] Champion identified (highest held-out F at `policy_block`);
      runners-up within 2 F units flagged.
- [ ] `B3` produces `ŝ^emp_{j,m,t}` and `ŝ^emp_{j,m,S3,t}` for champion
      and runners-up.
- [ ] Full-sample fit on champion is the production object; cross-fit
      predictions retained as sanity check.
- [ ] Firm support is `F^pre_{j,m}` (pre-election), not contemporaneous.

**Phase 3:**
- [ ] `B4` produces permutation maps for each channel, cached.
- [ ] Cross-office interactions permute the joint draw of single-office
      legs (D38 algebraic constraint preserved) **within the §3.1.1
      governing class** — state × year when M is present, region × year
      when only G is present.
- [ ] Recentered `z̃` produced for champion and runners-up at both
      margins.
- [ ] Sanity checks pass: regression of `z̃` on `w` = {muni FE, year
      FE, EC of channel under test} returns EC-block F-stat,
      intercept t-stat, and residual histogram — all logged to
      `sanity_log.md`, broken out by channel and margin.
- [ ] Drop-top-k simplex behavior matches production.
- [ ] Long-running steps log progress every 10 permutations.

**Phase 4:**
- [ ] `00_ar_helpers.R` exposes `run_ar()`, `volume_first_stage()`, and
      the table builders; the runner is parameterized over the
      excluded-instrument column block so both `Z_*` (production) and
      `z̃_*` (recentered) work without code duplication.
- [ ] `B5` produces the four-column wide-form first-stage table at both
      margins, with condition number and KP rank, sourcing the helper.
- [ ] `B6` produces the AR table with three volume treatments × four
      instruments × two margins × three channel sets, sourcing the helper.
- [ ] `B9_stack_ar_screen.R` in `ar_meeting_2026_05_13/` is byte-identical
      to its 2026-05-21 state (no edits to the frozen meeting deliverable).
- [ ] EC-free column reported as a primary specification — D32
      operationalization is explicit.
- [ ] Channel-set comparison reported.
- [ ] Findings memo states verdict on (a) relevance gain, (b) EC drop,
      (c) AR survival.

**Phase 5:**
- [ ] Methodology PDF section drafted and compiled.
- [ ] D-entry appended to `docs/decision_log.md`.
- [ ] Blueprint and research state updated.
- [ ] Evidence index updated.

**Process:**
- [ ] On approval, set `status: APPROVED`; write the post-plan session
      log to `journal/sessions/2026-05-26_bh2026-recentering-plan.md`.
- [ ] Add three A-numbered angles to `docs/PROJECT_BLUEPRINT.md` §4:
      (i) firm-coef-aggregated predictor, (ii) permutation recentering,
      (iii) EC-free sector first stage.
- [ ] On completion of each Phase, append the result row to the
      blueprint §6 decision log (one-line D-entry per phase).
- [ ] On full completion, set `status: COMPLETED`, add `completed:`,
      rewrite the Status prose.

## Decisions to flag — current state

User-confirmed 2026-05-26:

- **Functional form** — OLS on `s^emp_{f,m,t}` primary; PPML deferred
  robustness.
- **Cross-fitting discipline** — full-sample production fit; cross-fit
  predictions reported as sanity check.

Open after Phase 1, to confirm before Phase 2 launches:

1. **Permutation conditioning for M** — state-only (default) vs
   state × vote-margin tercile. If Phase 1 D2 reveals heavy
   margin-clustering in heterogeneity, escalate to state-margin.
2. **Skip presidential permutation** — confirmed in this plan as default;
   user can override if a within-cycle permutation design is preferred.
3. **Grid pruning** — if Phase 1 D1 shows two weighting families collapse
   onto the same F, prune to one and reduce the grid from 126 to a
   smaller cardinality. Decision after Phase 1.

Deferred for after Phase 4 results:

4. **Switch endogenous variable to `log(n^emp_{j,m,t})`** — only if
   Phase 1 D3 plus Phase 4 wide-form F together indicate mechanism 3 is
   the binding constraint, and recentering cannot close the gap. Default:
   keep the share endogenous (D24 holds).
5. **Graduation to production scripts** — only after the
   theoretical / econometric review settles the margin and instrument
   form. This plan does not graduate; it produces evidence.

## Expected outcome

Three concrete predictions, ordered by confidence.

- **High confidence.** The recentered instrument clears `mean(z̃ | w) ≈ 0`
  by construction, and the EC-free specification produces a wide-form F
  no worse than the production specification at `policy_block`.
- **Medium-high confidence.** The wide-form sector F at
  `policy_block × S3` rises materially relative to the production
  instrument. This is where mechanisms 1 and 2 are largest because the
  within-cell sample is richer.
- **Medium confidence.** The AR rejection at `policy_block × S3`
  becomes informative for the first time, unblocking the D28 graduation
  conversation.

A null result — recentered F essentially equal to production F at both
margins — implies one of: (a) mechanism 3 dominates and the share
endogenous is the binding constraint; (b) the firm-level model is too
weak to extract structural responsiveness in this panel; (c) the
production owner-count weights are already near-optimal at these
margins. The Phase 1 diagnostic is the dispositive read on which.

## References

1. Borusyak, K. and Brown, P. (2026). "Optimal Formula Instruments,"
   NBER WP w33594. Especially Section 2 (motivating example),
   Section 3 (theory and Algorithm 1), Lemma 1 (page 14), and
   Appendix A.2 (Proposition A3, optimal shift-share specialization).
   PDF at `docs/literature/`.
2. Borusyak, K., Hull, P. and Jaravel, X. (2025). "A Practical Guide to
   Shift-Share Instruments," *JEP* 39(1):181–204.
3. Borusyak, K., Hull, P. and Jaravel, X. (2022).
   "Quasi-Experimental Shift-Share Research Designs," *RES* 89(1):181–213.
4. `docs/methodology/ar_test_specification.tex` — current AR
   methodology draft.
5. `docs/decision_log.md` — D24 (endogenous = sector employment shares,
   2026-05-06), D28 (production margin deferred, 2026-05-12), D29
   (`policy_block` graduated, 2026-05-13), D31 (cross-office exposure
   timing, 2026-05-13), D32 (recentering committed, 2026-05-20), D34
   (channel routing rule, 2026-05-20), D38 (wide-form first-stage as
   relevance benchmark, 2026-05-21).
