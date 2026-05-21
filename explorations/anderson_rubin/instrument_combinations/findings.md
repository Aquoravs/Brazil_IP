# Instrument combinations for the AR test: which channels, and together or separate?

**Type:** exploration memo — answers the 2026-05-14 advisor questions on instrument combinations.
**Date:** 2026-05-20.
**Status:** analysis complete; recommendation below; real-data checks proposed in §7.
**Note:** §1–§7 take the project's "mayor as local intermediary" mechanism as
given. §8 (added 2026-05-20) drops that assumption and treats *which office
matters* as an open empirical question — read §8 alongside §5–§6.

---

## 0. Bottom line

1. **The AR test is a joint Wald test on the reduced form.** It regresses log GDP
   on whatever instrument set you give it and tests that every coefficient is
   zero. The set you feed it *is* the test. Adding an instrument is never
   neutral — it either raises power, dilutes power, or breaks the test.

2. **Three regimes govern every "should this instrument go in" decision.**
   Adding a *valid and relevant* instrument raises power. Adding a *valid but
   irrelevant* instrument lowers power (it spends a degree of freedom for no
   signal). Adding an *invalid* instrument — one with a direct GDP effect —
   makes the test reject when the optimality null is true. The simulation in §4
   shows all three.

3. **Standalone governor and president instruments are the worst case.** They do
   not move *local* sectoral composition (no local intermediary), so for the
   composition test they are at best irrelevant — and if a national or regional
   wave has any direct GDP effect, they are invalid. The old additive stack
   {M, G, P} put them in the same regression. That is what D25 removed.

4. **The mayoral factor is what makes an instrument relevant for local
   composition.** This is why every retained channel contains M. It is a
   relevance argument, not an immunity claim — see point 5.

5. **Cross-office channels are not immune to exclusion violations; they localise
   them.** A channel that crosses the mayor with the governor still inherits a
   governor-side violation. What the design buys is that the *pure mayoral
   channel M is always clean*, and each crossed channel is clean of the tiers it
   does not contain. This is the reason to run channels **separately** (per
   channel), not stacked into one regression: a violation in one tier then
   spoils only its own channel, and each channel's validity can be argued on its
   own tier.

6. **Recommendation.** Keep the per-channel cross-office design (M, M·P, M·G,
   M·G·P, one AR regression each). Do **not** revive the additive {M, G, P}
   stack. For any single channel, report the cross-office instrument alone
   (e.g. Z_MG), **not** {Z_M, Z_G, Z_MG} together — the main effects dilute it.
   The mayoral channel M is the clean anchor and should always be reported
   beside the crossed channels.

---

## 1. What the advisors asked (2026-05-14 meeting notes)

> *Instrument Combinations.* Explore regressions where instruments M, G, and
> M×G are all present versus specifications where only the interaction is
> included. Characterize the difference and determine which combination to use
> in the AR test.

In the meeting the question was put more pointedly: **why use only the
coincidence of mayor with another office as the instrument, and why did we
change away from putting the individual instruments M, G, P in the same
regression?** Two distinct questions:

- **Q1.** Why restrict the instrument set to channels that contain the mayor
  (M, M·P, M·G, M·G·P), rather than also using governor-only or
  president-only instruments?
- **Q2.** Why did the design move away from the additive specification that put
  individual M, G, P instruments together in one regression?

This memo answers both, after summarising what the project already decided.

---

## 2. What the project already decided (summary of prior documents)

The instrument set has a documented history. The relevant artefacts:

**The original design — additive tier stack.**
`docs/strategy/ar_test_strategy.md` (2026-04-28) specified the first AR design.
Its §3 "Approach A: wide format" put each sector's instrument in the regression
for each office tier — "with J = 4 BNDES sectors and L = 3 tiers, this gives up
to 4 × 3 = 12 instruments. The AR test is a joint Wald on all 12 coefficients."
Robustness check R3 was "Add governor tier (mayor + governor) … expand K from 4
to 8." This is exactly the specification the advisors are asking about: the
individual mayor, governor, and president instruments, additively, in one
regression.

**The switch to cross-office channels — Decision D25.**
`docs/decision_log.md` D25 (2026-05-10): *"Restructure the AR-test instrument
set from an additive tier stack to cross-office channels M, MP, MG, MGP."*
Status PROVISIONAL, pending theory/econometric review. This is the change the
advisors are asking about. It replaced {Z^M, Z^G, Z^P} with the four cross-office
channels, each a product of tier-specific alignment indicators.

**The mechanism rationale.**
`docs/methodology/ar_test_specification.tex`, subsection "Cross-office channel
structure", states the reason. The mechanism is cross-office: BNDES credit
reaches a municipality's firms when the same party holds the mayoralty *and* a
higher tier. "A national-only or governor-only alignment that does not pass
through a sympathetic mayor lacks the local intermediary required for
sector-specific credit to land in m and is not expected to drive s_mt. We
therefore restrict the instrument set to channels that contain mayoral
alignment as a factor." The pure M channel is kept because it "captures
local-only political capital" (municipal procurement, BNDES Card take-up, local
signalling).

**The exposure-weight decisions — D26, D31.**
`docs/strategy/office_specific_exposure_weights.md` and D31 (2026-05-13) settled
*how* each channel's shift-share weight is built (channel-specific
pre-earliest-election window, no coalition gating). That is orthogonal to the
combination question this memo addresses — it concerns the share component, not
which channels enter the test.

**The current implementation — per channel.**
`journal/meetings/2026-05-14/specification_note.tex` and
`explorations/anderson_rubin/ar_meeting_2026_05_13/R/04_run_ar_regressions.R`
show the current runs: 4 channels × 4 control specs = 16 regressions, and the AR
joint F is computed on one channel's instruments at a time. The specification
note is explicit: *"This is a per-channel run: each regression carries one
channel's instruments, not a stacked four-channel set."*

**Summary of the state.** The project moved from (i) an additive {M, G, P}
stack in one regression, to (ii) four cross-office channels, run (iii) one
channel per regression. The advisors' questions ask why (i)→(ii) and why the
channels contain the mayor. The rest of this memo gives the econometric answer
and a simulation that makes it concrete.

---

## 3. The econometric framework

### 3.1 The AR test is a joint Wald test on the reduced form

The structural equation is `log GDP_mt = α_m + δ_t + β' s_mt + λ Vol_mt + ε_mt`,
where `s_mt` is the vector of sector employment shares and the null of interest
is `H0: β = 0` (sectoral composition has no first-order GDP effect — the
local-optimality benchmark).

Substituting the first stage `s_mt = Π' Z_mt + v_mt` gives the reduced form
`log GDP_mt = α_m + δ_t + γ' Z_mt + λ Vol_mt + η_mt`, with `γ = Π β`. Under
`H0: β = 0` the reduced-form coefficient `γ` is zero for **every valid
instrument**. So the AR test is exactly: regress log GDP on the instrument set
(plus FE and controls) and jointly test that all instrument coefficients are
zero. `ar_test_strategy.md` §2 and the 2026-05-14 specification note both state
this; the pipeline computes it as `fixest::wald(mod, keep = "^Z_<channel>_")`.

The consequence: **the instrument set is not a modelling detail, it is the
test.** "Which instruments, together or separate" is the same question as "what
exactly are we testing."

### 3.2 What adding an instrument does — three regimes

An AR test on K instruments is an F test with K numerator degrees of freedom.
Its size is governed by whether every instrument is valid; its power is governed
by the non-centrality the relevant instruments contribute, traded against K.
Adding one instrument falls into exactly one of three regimes.

**Regime (a) — add a valid and relevant instrument.** The instrument is
orthogonal to the structural error (valid) and moves `s_mt` (relevant). It adds
non-centrality and one degree of freedom. Net effect: **power rises**, provided
the signal it carries outweighs the one-df cost. This is the case for combining.

**Regime (b) — add a valid but irrelevant instrument.** The instrument is
exogenous but barely moves `s_mt`. It adds a degree of freedom and no
non-centrality. The test stays correctly sized but **power falls**. A regression
padded with weak instruments is a weaker test, not a richer one.

**Regime (c) — add an invalid instrument.** The instrument has a direct effect
on GDP that does not pass through `s_mt` — it is correlated with the structural
error. Then its reduced-form coefficient `γ` is non-zero **even though
`β = 0`**. The joint test rejects. This is not power: it is a **false rejection
of the optimality null**. The AR test no longer tests `β = 0`; it tests a
contaminated composite, and a rejection can no longer be read as "composition
matters." Worse, in a joint test you cannot see which instrument caused it.

The whole instrument-combination decision is: stay in (a), avoid (b), never
enter (c).

### 3.3 Why this maps onto M, G, P

- **Standalone governor / president instruments.** Governor and president
  alignment are *regional* and *national* waves. Without a sympathetic mayor
  they do not move *local* sectoral composition — the mechanism has no local
  intermediary — so for the composition test they sit in regime (b): irrelevant,
  pure dilution. And national or regional political waves are plausibly
  correlated with sector fundamentals directly — national industrial policy,
  federal transfers, commodity cycles, regional shocks — which puts them at risk
  of regime (c). An instrument that is at best dilution and at worst invalid has
  no role in the test.

- **Cross-office channels (M·P, M·G, M·G·P).** The product is "on" only where
  the mayor *and* the higher tier align. The mayoral factor supplies locally
  idiosyncratic, plausibly exogenous switching variation, and — being the local
  intermediary — it is what makes the instrument actually move local
  composition. These channels are relevant: regime (a).

- **The pure mayoral channel M.** Relevant (local political capital) and the
  cleanest on validity, because it contains no higher tier. It is the anchor.

The simulation below quantifies all of this.

---

## 4. The dummy example

### 4.1 Design

`R/ar_instrument_combination_sim.R` is a Monte Carlo (4,000 municipalities,
2,000 replications). The data-generating process encodes the project's
maintained mechanism so the consequences can be read off cleanly:

- Each municipality has a predetermined sector exposure `x` and three alignment
  indicators — mayor `aM` (local, idiosyncratic), governor `aG` (regional wave),
  president `aP` (national wave).
- Shift-share instruments are `Z_M = x·aM`, `Z_G = x·aG`, `Z_P = x·aP`,
  `Z_MG = x·aM·aG`, `Z_MP = x·aM·aP`, `Z_MGP = x·aM·aG·aP`.
- **Composition moves only through mayor-crossed channels:**
  `s = 0.30·Z_M + 1.00·Z_MG + 0.80·Z_MP + noise`. Governor-only and
  president-only alignment do **not** move local composition — the
  no-local-intermediary assumption, made literal.
- `log GDP = β·s + θ + noise`, with `θ` a municipal fundamental. The knob
  `d_G` makes the governor wave `aG` correlate with `θ` — i.e. a governor-side
  **exclusion violation**. `d_G = 0` means the governor exclusion restriction
  holds.

Six instrument sets are fed to the AR test (each = joint F that all the set's
coefficients are zero):

| Set | Instruments | What it represents |
|---|---|---|
| S0 | {Z_M} | pure mayoral channel — clean anchor |
| S1 | {Z_M, Z_G, Z_P} | **old additive design** (pre-D25) |
| S2 | {Z_MG} | interaction only — the 2026-05-14 candidate |
| S3 | {Z_M, Z_G, Z_MG} | **the exact 2026-05-14 "main effects + interaction" ask** |
| S4 | {Z_M, Z_MG, Z_MP, Z_MGP} | all four cross-office channels stacked in one regression |
| S5 | S4 + 5 irrelevant instruments | kitchen sink |

This DGP assumes the project's mechanism; it illustrates the *consequences* of
that mechanism for the instrument set. It does not prove the mechanism — that is
what the real-data exclusion/placebo work (F3) is for.

### 4.2 Result 1 — size and power, governor exclusion holding (`d_G = 0`)

Rejection rate, %. The `β = 0` row is **size** (target 5.0); the `β > 0` rows
are **power**.

| β | S0 mayor | S1 add {M,G,P} | S2 {M·G} | S3 {M,G,M·G} | S4 cross-office ×4 | S5 + noise |
|---|---|---|---|---|---|---|
| 0.00 | 4.5 | 4.3 | 4.8 | 4.8 | 4.8 | 5.1 |
| 0.10 | 24.6 | 18.4 | **26.9** | 21.2 | 21.7 | 15.3 |
| 0.20 | 70.6 | 64.2 | **75.0** | 68.7 | 72.4 | 57.7 |

Reading:

- **All six sets are correctly sized** (≈ 5% at β = 0). With valid instruments,
  combining many of them does not break the test's size — it only affects power.
- **S2 {M·G} alone is the most powerful.** One relevant instrument, one degree
  of freedom, all the signal concentrated.
- **S3 {M, G, M·G} is weaker than S2 {M·G}** (68.7 vs 75.0 at β = 0.20). Adding
  the M and G *main effects* to the interaction is regime (b): they carry little
  independent composition signal here, so they spend two degrees of freedom for
  almost nothing. **This is the direct answer to the 2026-05-14 question** —
  "M, G, and M×G all present" is a weaker test than "M×G only."
- **S1, the old additive {M, G, P} stack, is the weakest of the genuine sets**
  (64.2 vs 70.6 for the mayoral channel alone). Standalone G and P act as near-
  noise for the composition channel — dilution, regime (b).
- **S5, the kitchen sink, is worst of all** (57.7). Five irrelevant instruments,
  five wasted degrees of freedom. More instruments is not a richer test.

### 4.3 Result 2 — size under a governor exclusion violation (`β = 0` throughout)

Here `β = 0`: the optimality null is **true**. Every rejection is a **false
rejection**. Target is 5.0.

| `d_G` | S0 mayor | S1 add {M,G,P} | S2 {M·G} | S3 {M,G,M·G} | S4 cross-office ×4 |
|---|---|---|---|---|---|
| 0.00 | 4.8 | 4.5 | 5.3 | 4.2 | 4.3 |
| 0.50 | **5.5** | 100.0 | 99.8 | 100.0 | 99.8 |
| 1.00 | **4.3** | 100.0 | 100.0 | 100.0 | 100.0 |

Per-channel, one instrument at a time (`β = 0`, governor violation on):

| `d_G` | M | M·G | M·P | M·G·P | G only | P only |
|---|---|---|---|---|---|---|
| 0.00 | 4.8 | 5.3 | 4.4 | 4.8 | 4.7 | 5.1 |
| 0.50 | **5.5** | 99.8 | **5.6** | 79.8 | 100.0 | **5.1** |
| 1.00 | **4.3** | 100.0 | **4.0** | 100.0 | 100.0 | **4.8** |

Reading — this is the most important table:

- **Once the governor wave has a direct GDP effect, every set that contains a
  governor term falsely rejects** — S1, S2, S3, S4 all go to ≈ 100%. The AR test
  reports "composition matters" when it does not.
- **A channel is contaminated if and only if it contains the violating tier.**
  Under a *governor* violation, M, M·P and P-only stay at ≈ 5% (clean); M·G,
  M·G·P and G-only blow up. M·G·P is partially attenuated at `d_G = 0.5` (79.8%)
  because the triple coincidence is rarer, but it still fails.
- **The pure mayoral channel M is the universal clean anchor.** It contains no
  higher tier, so no higher-tier violation can reach it.
- **Cross-office crossing attenuates but does not remove higher-tier
  contamination.** Crossing the governor wave with the idiosyncratic mayor
  halves how often the channel is "on", but the residual correlation with the
  fundamental is still enough to reject at this sample size. Cross-office is not
  an immunity device.

---

## 5. Answers to the advisor questions

### Q1 — Why only mayor-crossed channels?

Two reasons, both visible in §4.

**Relevance.** The mechanism is that BNDES credit reaches local firms through
the mayor as local intermediary. Governor-only and president-only alignment do
not move *local* sectoral composition. In the simulation they are literally
absent from the first stage for `s`, and the result is that the additive set S1
— which includes them — is the weakest genuine test (64.2% power vs 70.6% for
the mayoral channel alone). A standalone G or P instrument cannot add power to
the composition test; it can only dilute.

**Validity.** Governor and president alignment are regional and national waves,
plausibly correlated with sector fundamentals through channels other than local
composition (national industrial policy, transfers, commodity cycles). If any
such direct effect exists, a standalone G or P instrument is invalid — regime
(c) — and Result 2 shows what that does: a false rejection of the optimality
null. An instrument that is dilution at best and invalidating at worst has no
role. The mayoral factor is what restores relevance: the cross-office product is
"on" only where the locally idiosyncratic mayoral switch is on.

### Q2 — Why move away from individual M, G, P in one regression?

The additive {M, G, P} stack is S1. It is dominated on both axes:

- **On power**, it is the weakest of the genuine sets (§4.2). The mechanism is
  interactive — credit needs the mayor *and* a higher tier — so the additive
  main effects do not capture the channel through which composition actually
  moves. They spend degrees of freedom without carrying the signal.
- **On validity**, it is the most exposed. It puts the two riskiest instruments
  — standalone G and standalone P — directly into the test, and Result 2 shows a
  single governor-side violation drives the additive set to a 100% false-
  rejection rate.

D25 replaced it with cross-office channels for exactly these reasons. The change
was not cosmetic: the additive stack and the cross-office channels test
different nulls, because {Z^M, Z^G, Z^P} and {Z^M, Z^{MG}, Z^{MP}, Z^{MGP}}
span different column spaces. The interaction `Z^{MG}` is not a linear
combination of `Z^M` and `Z^G`; it is a genuinely different instrument that
matches the interactive mechanism.

### The specific "{M, G, M×G} vs {M×G} only" comparison

This is S3 vs S2. The simulation is unambiguous: **{M×G} alone is the stronger
test** (75.0% vs 68.7% power at β = 0.20). Adding the M and G main effects
alongside the interaction dilutes it, because in the cross-office mechanism the
main effects carry little independent composition signal. Report the
cross-office instrument on its own; do not pad it with the standalone main
effects.

---

## 6. Recommendation

**Instrument set.** Keep the cross-office channels: M, M·P, M·G, M·G·P. Do not
revive the additive {M, G, P} stack. Do not add standalone governor or president
instruments to any AR regression.

**Within a channel.** Report the channel's own cross-office instrument alone
(Z_MG for the M·G channel, etc.). Do not include the standalone main effects
{Z_M, Z_G} alongside Z_MG — that is S3, and it is a weaker test than Z_MG alone.

**Together or separate — run them separately, one channel per AR regression.**
This is what the pipeline already does, and §4 supports it:

- A single big regression stacking all four channels (S4) is not more powerful
  than the best single channel (72.4% vs 75.0% at β = 0.20) — the four channels
  are highly collinear (their "on" sets are nested: M·G·P ⊂ M·G ⊂ M) and the
  extra degrees of freedom dilute.
- More importantly, validity must be argued tier by tier. Result 2 shows a
  governor violation contaminates M·G and M·G·P but leaves M and M·P clean. If
  all four channels share one regression, that violation silently contaminates
  the joint test and you cannot see it. Run per channel and each channel's
  rejection can be read against that channel's own exclusion argument.
- The mayoral channel M is the clean anchor — it cannot be contaminated by any
  higher-tier violation — and should always be reported beside the crossed
  channels. If M·P and M·G·P diverge from M·G, that divergence is itself
  evidence about which tier's exclusion restriction is in trouble.

**The combine-vs-separate rule, stated generally.** It is not "many together" or
"always separate." Combine instruments that are each individually valid and each
relevant — that is regime (a), and it raises power. Never combine an instrument
whose validity you doubt: in a joint test it contaminates everything and you
cannot tell which one did it. When validity is uncertain, run separately, so a
bad instrument spoils only its own test. The project's per-channel design is the
correct default precisely because higher-tier exclusion is still under review
(F3 is PARTIAL: presidential residual flagged, mayor clean).

---

## 7. Caveats and the proposed real-data check

- The simulation assumes the project's mechanism (mayor as local intermediary).
  It shows the *consequences* of that mechanism for the instrument set; it does
  not prove the mechanism. The standalone-G/P validity concern is an argument,
  not a measured fact.
- It is a cross-section with homoskedastic errors. The real AR test has muni and
  year fixed effects and muni-clustered SEs. Fixed effects change *which*
  variation identifies the test and clustering changes the variance bookkeeping;
  neither changes the three regimes of §3.2.
- The DGP makes governor/president-only alignment have *exactly zero* effect on
  local composition. In reality it may be small but non-zero. That would make
  standalone G/P weak rather than perfectly irrelevant — still regime (b), still
  no reason to include them.

**Proposed next step on real data.** The simulation's claims are testable
directly on the built panel, without new data:

1. **Relevance check.** First-stage F of `s_mt` (or `Δs_mt`) on Z_G alone and on
   Z_P alone, with muni + year FE. The prediction is that these are weak — much
   weaker than Z_MG, Z_MP. This is the empirical content of "no local
   intermediary."
2. **The {M,G,M×G} vs {M×G} comparison the advisors asked for.** Run the AR test
   at the `policy_block` margin with (a) Z_MG only and (b) {Z_M, Z_G, Z_MG}
   together. Compare the joint F, the p-value, and the AR confidence set width.
   The prediction: (a) is the sharper test.
3. **Validity / placebo.** Regress log GDP on Z_G alone and Z_P alone with the
   full FE. Under the exclusion restriction these should be jointly
   insignificant. This is the F3 falsification work; a non-zero standalone-G or
   standalone-P reduced form is the real-data analogue of `d_G > 0` and would
   confirm the validity concern that motivates excluding them.

Files: `R/ar_instrument_combination_sim.R` (simulation),
`output/ar_combination_power.csv`, `output/ar_combination_size_distortion.csv`.

---

## 8. Follow-up: the agnostic case — which office actually matters?

### 8.1 The limitation §1–§7 left open

The simulation in §4 hard-coded the project's mechanism: composition moves
*only* through mayor-crossed channels. Under that assumption the conclusions
follow. But the assumption is exactly what is in question. BNDES is the
*federal* development bank; its leadership is appointed by the presidency. It
is entirely plausible that a firm whose owners are aligned with the president's
party obtains federal support regardless of the mayor — and the project's own
earlier work suggested several offices carry significant, distinct effects. So
"only mayor-crossed channels are relevant" is a hypothesis to test, not a fact
to assume. This section drops it.

### 8.2 Relevance and validity are two different questions

The case for any instrument rests on two separate conditions, and the offices
behave differently on each.

- **Relevance** — does this channel actually move the endogenous object
  (BNDES credit / employment composition)? This is a *first-stage* question. It
  is fully testable, needs no exclusion restriction, and is **agnostic by
  construction** if done right (§8.3). We should *not* impose it a priori.

- **Validity (exclusion)** — does this channel move GDP *only* through
  composition? This is the AR test's identifying assumption. It is partly
  testable (placebo / pre-trend / falsification — the project's F3 work) and
  partly an economic argument.

The mayor-anchor argument survives only as a *validity* argument, not a
relevance claim. Mayoral turnover is locally idiosyncratic and the mayor has
few non-composition levers over municipal GDP, so mayor-crossed variation is
the part most defensible as exclusion-satisfying. Presidential alignment is the
riskiest on validity *precisely because* the federal government has many other
levers — transfers, national industrial policy, regulation, public banks —
that reach a presidentially-aligned sector directly, outside the composition
channel. That asymmetry is real and does not depend on the relevance question.

The mistake to avoid: "if presidential alignment moves credit, then Z_P is a
good instrument." Relevance is necessary, not sufficient. Z_P can be strongly
relevant and still invalid.

### 8.3 The agnostic tool — the saturated first stage

Three binary alignment indicators (mayor, governor, president) generate seven
non-constant channels: the three main effects M, G, P; the three pairs M·G,
M·P, G·P; and the triple M·G·P. These seven are the **saturated basis**: any
function of the three indicators is a linear combination of them. Regressing
the endogenous object on all seven imposes *nothing* about which office
matters — the data choose.

`R/agnostic_office_relevance_sim.R` runs this. It builds three "worlds" — the
truth is M·G-only, P-only, or both — and regresses composition on all seven
channels. The saturated first stage recovers the truth every time (coefficient,
*t*-statistic; one draw, N = 20,000):

| True world | M | G | P | M·G | M·P | G·P | M·G·P |
|---|---|---|---|---|---|---|---|
| M·G only | 0.0 | 0.0 | 0.0 | **0.97** (33) | 0.0 | 0.0 | 0.1 (2) |
| P only | 0.0 | 0.0 | **1.01** (57) | 0.0 | 0.0 | 0.0 | 0.0 |
| M·G and P | 0.0 | 0.0 | **0.80** (46) | **1.03** (35) | 0.0 | 0.0 | 0.0 |

In every world the channels that genuinely move composition light up and the
rest sit at zero. This is how to answer "which office is relevant" without
assuming the answer: **estimate the saturated first stage and read it off.**
On real data, run it with muni + year fixed effects; per sector or margin if
the mechanism may differ across sectors; and interacted with municipal
characteristics if you suspect *"in which circumstances"* heterogeneity (e.g.
office relevance differing by BNDES intensity or firm size).

### 8.4 What it costs to impose the wrong restriction

The same script runs the AR test under the mayor-restricted set
{M, M·G, M·P, M·G·P} versus the saturated set versus each channel alone.
Rejection rate, %, at β = 0.20 (β = 0 rows confirmed correct size, ≈ 5%):

| True world | Mayor-restricted | Saturated (7) | M alone | P alone | M·G alone |
|---|---|---|---|---|---|
| M·G only | 29.2 | 21.3 | 18.2 | 5.1 | **46.0** |
| P only | **23.3** | 45.8 | 5.3 | **76.3** | 5.0 |
| M·G and P | 45.1 | 53.8 | 26.3 | 58.8 | 54.9 |

Reading:

- **When the truth is P-only, the mayor-restricted set nearly misses it** —
  23.3% power, against 76.3% for the P channel alone. Imposing "instruments
  must contain the mayor" throws away most of the signal if the mayor is not
  the operative office. (It is not literally zero because M·P shares the
  presidential indicator with P.)
- **The saturated set is robust but never sharp.** It catches the effect in
  every world (21–54%) but, carrying four to six irrelevant channels, it is
  always weaker than the single true channel. Stacking all seven into one AR
  regression is a poor *headline* test.
- **The per-channel column is the most informative.** M·G alone is strongest
  in the M·G world, P alone in the P world, and both fire in the mixed world.
  The per-channel pattern *is* the diagnosis of which office matters.

### 8.5 Recommended procedure when the mechanism is unknown

Construct **all seven channels**. Constructing them costs only build effort;
which ones to *use* in the AR test is then a data decision, in three stages.

1. **Relevance (agnostic).** Estimate the saturated first stage of the
   endogenous object on all seven channels, with muni + year FE — overall, by
   sector, and interacted with municipal characteristics. This identifies which
   channels move composition and in which circumstances. Imposes nothing.

2. **Validity (per channel).** For each *relevant* channel, run the
   falsification suite — reduced form of GDP on the channel with leads,
   pre-trends, federal transfers as a placebo outcome (the F3 programme). This
   identifies which relevant channels are also clean.

3. **AR test.** Report the AR test **per channel**, for every channel that is
   relevant — including governor- and president-containing ones. Designate as
   the *headline* the channel(s) that are relevant *and* pass validity; the
   cleanest of these will typically be mayor-anchored, for the validity reasons
   in §8.2, not because the mayor was assumed to be the only relevant office.
   Channels that are relevant but validity-caveated are reported as informative
   robustness, with the caveat stated. Do not collapse to a single stacked
   regression (§8.4) and do not pre-exclude G or P before stage 1 has run.

This procedure is fully agnostic about which office matters, lets the data
speak, and still respects that a rejection driven by an exclusion-violating
channel is not evidence on composition. It supersedes the §6 recommendation in
one respect: §6 said "do not add standalone G or P instruments." The accurate
statement is **do not add them before the saturated first stage and the
placebo tests have run** — if a higher-tier channel is shown to be both
relevant and clean, it belongs in the reported set.

### 8.6 On the specific "M and M·G together" question

To be unambiguous: "report M beside the crossed channels" (§6) means **separate
AR regressions presented in one table** — one regression per channel, which is
what `04_run_ar_regressions.R` already does. It does **not** mean stacking
{Z_M, Z_MG} into a single regression.

Is {Z_M, Z_MG} in one regression better than {Z_MG} alone? It depends on
whether the mayor-only channel carries *independent, valid* signal. If it does,
combining them is a power gain (§3.2 regime a); if M is irrelevant, it is a
df-cost loss (regime b). That is an empirical question the stage-1 first stage
answers. The transparent default — and the right choice while the mechanism is
still being established — is to run each channel separately and let the table
show the full per-channel pattern.

Files: `R/agnostic_office_relevance_sim.R`, `output/saturated_first_stage.csv`,
`output/agnostic_ar_power.csv`.

---

## 9. Resolution: weight construction and the EC (2026-05-20)

A further question was raised: revert the instrument to a within-cell,
affiliated-normalized weight (numerator = party-*p* affiliated owners in cell
*(j,m)*; denominator = total affiliated owners in the *same cell*). That weight
sums to one across parties at the sector level, so the EC control becomes
constant and unnecessary.

Evaluated with an external second opinion and **rejected** — recorded as **D32**.
The within-cell weight discards sector mass (worsening the AR estimand and
power) and reintroduces the thin-cell denominator instability that rejected
Variant B-prime. The EC is the BHJ-prescribed, predetermined incomplete-shares
control; being a valid control it does not bias the size-correct AR test, so
"not depending on the EC" is a presentational preference, not an identification
gain.

**Decision:** keep the muni-relative weight + per-channel EC as primary; ensure
the EC is adequately constructed (audit); adopt shock recentering as the planned
EC-free robustness, which preserves mass. Next steps are in
`journal/plans/2026-05-20_ec-adequacy-and-instrument-combinations.md`.

---

## 10. Phase A: EC adequacy audit (2026-05-20)

**Verdict.** The exposure control entering the AR test is the BHJ-correct,
predetermined incomplete-shares control for the muni-relative weight, correctly
constructed and entered, and the AR rejection verdict is robust to its
functional form. D32 stands and is reinforced. One documentation follow-up is
flagged (§10.3). Audited pipeline: `ar_meeting_2026_05_13/R/` scripts 01–04;
built objects re-verified in `R/A2_verify_ec.R`, `R/A5_ec_functional_form.R`,
`R/A6_coverage_concentration.R`.

### 10.1 A1 — definitional consistency: CONFIRMED

`02_build_instruments_ec.R` builds both objects from one join of one weights
table: `Z_val = Σ_p w̃·Align` and `EC_val = Σ_p w̃`, same `w̃`, same grouping.
The weight `w̃` (`01_build_variant_a_weights.R`) is affiliated owner-years in
cell *(j,m)* over the channel-specific frozen pre-earliest-election window,
divided by the muni-level affiliated total. Built-object check: EC recomputed
from the weights table matches the saved EC to 7e-16. The EC is exactly `Σ_p`
of the same muni-relative weight as the instrument.

### 10.2 A2 — EC vs. slack: RESOLVED

The exploration AR pipeline carries the **sum-of-shares EC and no `slack`
column** — confirmed: no slack-type column in the weights, Z, EC, or muni
panel. This is correct for the muni-relative (Variant A) weight: its
denominator is the muni affiliated total, so `Σ_{j,p} w̃ = 1` exactly —
verified, `Σ_j EC = 1` for all 264,168 muni-year-channel cells, zero
violations. There is no muni-level unaffiliated residual, hence no muni-level
slack.

The `slack ≡ 1 − EC` object belongs to a *different* weight — the within-cell
intensity weight (`eq:wjmp` in the methodology spec), whose denominator is the
cell's *total* owners, so `Σ_p w ≤ 1` and the residual is the cell's
unaffiliated share. That weight is now a robustness variant, not the primary.

The incomplete-shares problem does not vanish under Variant A — it moves to the
party index: for sector *j* the shares `{w̃_{jmp}}_p` sum to `Σ_p w̃_{jmp} =
EC_{jm} ≠ 1` (96.5% of cells strictly interior to (0,1)). The BHJ §4.4-correct
control for that incompleteness is exactly that per-sector sum — one EC per
sector — which is what the pipeline carries. So there is no leftover slack
column to resolve, and the sum-of-shares EC **is** the BHJ-correct
incomplete-shares control for the muni-relative weight.

**Documentation follow-up (flag, not a code bug).** `ar_test_specification.tex`
§2.3 "Frozen pre-election window" (≈ lines 633–650) still describes the EC and
slack via the intensity weight and states the per-cell `slack_frozen_mt` column
"must be carried as a control." Under D32 the primary is Variant A, which needs
the per-sector sum-of-shares EC and has no muni-level slack. The methodology PDF
should be reworded so the primary-spec narrative matches Variant A. The
*production* hybrid scripts (`32c_build_emp_share_panel.R`,
`41_build_muni_panel.R`) likewise carry `slack_frozen_mt`; aligning them with
the D32 Variant-A primary is part of the already-flagged production-weight
alignment task and is out of Phase A scope (production code is frozen pending
review). Routed to E4.1.

### 10.3 A3 — regression structure: CONFIRMED

`04_run_ar_regressions.R` adds one `EC_<channel>_<sector>` per retained sector.
Built panel: 12 Z + 12 EC columns (4 channels × 3 retained sectors); the Z
sector set, the EC sector set, and the retained set `{Agro, Ind, Infra}` all
coincide; hold-out sector `Serv` is consistent for Z and EC. FE are
`muni_id + year`; the AR Wald keys on `^Z_<channel>_`, so the EC is a nuisance
control. Because `Σ_j EC_{jm} = 1`, the EC vector is itself simplicial; the
simplex constant is absorbed by the hold-out + FE, and the K−1 retained EC
columns are free simplex coordinates (no residual collinearity). Controlling
for them is controlling for the municipality's full affiliated-owner sectoral
composition — a strong, valid, predetermined control.

### 10.4 A4 — predeterminedness: CONFIRMED

The window is `T^{F,c}_t = [e_min−4, e_min−1]`, where `e_min` is the earliest
most-recent election entering the channel's cross-office state. All built
weight rows have `T_Fc_hi − t ∈ [−4, −1]`; zero rows with `T_Fc_hi ≥ t`. The EC
uses only pre-window owner counts — no contemporaneous leakage.

### 10.5 A5 — functional-form sensitivity: STABLE

The AR test was re-run at `policy_block` with the EC entered four ways — `none`
(uncontrolled benchmark), `linear` (production), `quad` (EC + EC²), `bins`
(EC terciles) — each with and without the volume control (32 regressions).

| Channel | AR_F across {linear, quad, bins} | Reject @5% | Benchmark `none` |
|---|---|---|---|
| M   | 0.477–0.506 | no / no / no    | F=0.617, p=0.604 |
| MP  | 1.026–1.394 | no / no / no    | F=1.861, p=0.134 |
| MG  | 3.632–3.993 | **yes / yes / yes** | F=2.147, p=0.092 |
| MGP | 0.786–1.127 | no / no / no    | F=1.022, p=0.382 |

The AR rejection verdict is **stable across all three EC functional forms** for
every channel × volume combination. MG (the channel that rejects) rejects under
linear, quadratic, and binned EC alike, with F ∈ [3.63, 3.99], p ∈ [0.0075,
0.0123]. The `none` benchmark shows the EC's *presence* sharpens MG from p=0.092
to p<0.013 — evidence the EC is a substantive, valid predetermined control — but
the verdict does not hinge on its functional form. EC functional-form dependence
is not a concern; Phase C recentering remains a planned robustness, not a
forced-primary escalation.

### 10.6 A6 — coverage / concentration

- **Effective number of shocks** (inverse-HHI of the muni-relative weights,
  `n_eff = 1/Σ w̃²`): median ≈ 8.2–8.5 sector×party cells per muni-year-channel,
  mean ≈ 9.1–9.4, p10 ≈ 2.4, min 1.
- **Cell affiliated-owner counts** `L_{jm,t}`: median ≈ 15–16, mean ≈ 80
  (right-skewed, max ~50k); 27–28% of cells are thin (≤5 affiliated owners).
- **GDP mass**: thin-identified muni-years are ~21% of muni-years but carry only
  **~1.8% of municipal GDP**. Thin cells are small municipalities; the
  GDP-relevant AR estimand is not driven by them.

The muni-relative denominator keeps the per-channel weight thick — denominator
collapse is not a threat. This is the concrete confirmation of the D32 rationale
that the rejected within-cell weight would have reintroduced the thin-cell
instability that killed Variant B-prime.

Output: `output/A2_ec_verification.txt`, `output/A5_ec_functional_form.csv`,
`output/A5_ec_functional_form_summary.txt`, `output/A6_effective_shocks.csv`,
`output/A6_cell_owner_counts.csv`, `output/A6_gdp_mass_thin.csv`,
`output/A6_coverage_concentration.txt`.

---

## 11. Phase B: seven channels, two first stages, routing, AR tests (2026-05-20)

All Phase B work runs in `explorations/anderson_rubin/ar_meeting_2026_05_13/R/`
(scripts `B2`–`B6`, master `run_phase_bc.R`). Output suffixes the taxonomy.
Decision 1 is in force: the instruments `Z` retain all `J` sector columns per
channel; the exposure control `EC` retains `J−1` (one sector held out, absorbed
by FE). The AR Wald is the joint test on the channel's `Z` columns only.

### 11.1 B2 — saturated composition first stage

Endogenous = sector employment share `s_emp[j,m,t]`, stacked long form at
(muni, sector, year), regressed on the seven own-sector channel instruments;
FE `muni×sector + sector×year`; EC always included; cluster muni + sector.
Per-channel first-stage F (cluster-robust Wald), `policy_block`:

| Channel | Coef | Partial F | p | Relevant (5%) |
|---|---|---|---|---|
| Mayor | −0.0007 | 0.01 | 0.920 | No |
| Governor | 0.0022 | 0.20 | 0.655 | No |
| President | 0.0391 | **7.75** | **0.005** | **Yes** |
| Mayor × Governor | 0.0007 | 0.01 | 0.931 | No |
| Mayor × President | −0.0191 | 2.18 | 0.140 | No |
| Governor × President | −0.0072 | 0.15 | 0.700 | No |
| Mayor × Gov. × President | −0.0026 | 0.05 | 0.824 | No |

At `policy_block` only the President channel moves employment composition.
The BNDES-credit-share alternative LHS agrees: President (F=56.1) and
Governor × President (F=8.6) are relevant; nothing else. At the 12-group
`policy_block × S3` margin **no channel clears the 5% gate** (max F=2.15).

### 11.2 B3 — saturated volume first stage

Endogenous = `Vol_mt` (`vol_ratio`), scalar form, regressed on the seven
muni-aggregated channels `Zbar_c = Σ_j Z^c_{jmt}`; FE `muni + year`; cluster
muni. Governor (F=4.56, p=0.033) and Mayor × Governor (F=4.41, p=0.036) are
volume-relevant at `policy_block`; the same two at the 12-group margin
(Governor F=5.61, Mayor × Governor F=5.11). No other channel is volume-relevant.

### 11.3 B4 — channel routing

Routing rule (plan Decision 2): composition if relevant in B2; volume if
relevant in B3 and not in B2; composition if relevant in both; dropped if in
neither; fallback to `{M, M·P, M·G, M·G·P}` if no channel clears the
composition gate.

- **`policy_block`:** composition set = `{P}`; volume set = `{G, M·G}`.
- **`policy_block × S3`:** no channel clears the composition gate → fallback
  composition set = `{M, M·P, M·G, M·G·P}`; volume set = `{G}` (Mayor × Governor
  is volume-relevant but sits in the composition fallback, so by the
  "relevant in both → composition" rule it is assigned to composition).

A volume channel exists at both margins, so the Full-IV column is shown.

### 11.4 B5 — the advisor comparison

AR test at `policy_block` (EC always included, `vol_ratio` as predetermined
control): `{M·G}` alone gives AR F=3.20, p=0.012, df=(4, 83127); `{M, G, M·G}`
stacked gives AR F=4.82, p=5.7×10⁻⁸, df=(12, 83113). The stacked set has the
lower p-value at both margins. The stacked test rejects more strongly because
the Governor and Mayor main effects carry independent reduced-form signal here
— consistent with B3 showing Governor is volume-relevant. The scalar-index AR
confidence-set width is not feasible from the muni wide panel (it carries no
scalar composition index); the F/p/df comparison is the deliverable.

### 11.5 B6 — three-volume AR table

AR test three ways, EC always an included control: (i) no volume control,
(ii) volume as a predetermined control, (iii) volume instrumented (Full IV) by
the B4 volume channel's `Zbar`. Reported for two instrument sets per Decision 4.

**Composition set (stacked, `policy_block` = `{P}`):** AR F = 0.92 / 0.92 / 1.17
across the three volume treatments; never rejects.

**Four mayor-crossed channels, `policy_block` (AR F [p]):**

| Channel | No Vol | Vol control | Vol instrumented |
|---|---|---|---|
| Mayor | 1.09 [0.360] | 1.09 [0.360] | 1.43 [0.223] |
| Mayor × President | 1.31 [0.263] | 1.31 [0.263] | 1.27 [0.278] |
| Mayor × Governor | **3.19 [0.012]** | **3.20 [0.012]** | **3.15 [0.013]** |
| Mayor × Gov. × President | 1.38 [0.239] | 1.38 [0.239] | 1.49 [0.201] |

Mayor × Governor is the only channel that rejects, and it rejects under all
three volume treatments — the rejection is a composition result, not a volume
artifact. This reproduces the Phase A A5 finding (MG rejects, others do not).

---

## 12. Phase C: policy_block × S3 crossed margin, 12 groups (2026-05-20)

The crossed taxonomy `policy_block_size_bin` (4 blocks × 3 size bins = 12
groups) was built (`01`→`02`→`03` with `--tax=policy_block_size_bin`) and the
full B2–B6 analysis re-run. `Z` retains all 12 groups; `EC` retains 11.

- **B2 (12-group):** no channel clears the 5% composition gate (max partial
  F=2.15, President). Nested-block joint F is significant (mains F=3.80,
  p=0.010) but no single channel is individually relevant.
- **B4 (12-group):** fallback composition set `{M, M·P, M·G, M·G·P}`;
  volume set `{G}`.
- **B6 (12-group):** the composition-set AR test rejects without and with a
  volume control (F=1.47, p=0.020, df=48) but **not** under Full IV (F=1.20,
  p=0.162). Per-channel, no mayor-crossed channel rejects at this finer margin.
- **B5 (12-group):** `{M, G, M·G}` stacked (p=4.4×10⁻⁷) sharper than `{M·G}`
  alone (p=0.029).

### 12.1 C3 — thin-cell coverage audit at 12 groups

Mirroring A6 at the finer margin:

- **Effective number of shocks** (inverse-HHI of muni-relative weights):
  median 12.5, mean 16.3, p10 2.6, min 1. The crossed margin actually raises
  `n_eff` relative to the 4-group margin because each muni-year now spreads
  weight over more sector × party cells.
- **Cell affiliated-owner counts** `L_{jm,t}` (annual): median 3, mean 11;
  **64.8%** of cells are thin (≤5 affiliated owners) — up from 27–28% at the
  4-group margin, as expected when each block is split three ways.
- **GDP mass:** thin-identified muni-years are 66.8% of muni-years but carry
  only **9.3%** of municipal GDP. Thin cells concentrate in small
  municipalities; the GDP-relevant AR estimand is not driven by them.

The muni-relative denominator keeps per-channel weights thick — denominator
collapse is not a threat even at 12 groups — but the per-cell owner counts are
materially thinner, so the 12-group results carry more sampling noise than the
4-group results and should be read as a robustness margin, not the headline.

Output (all under `ar_meeting_2026_05_13/output/`, suffixed by taxonomy):
`ar_first_stage_comp_*.{tex,csv}`, `ar_first_stage_comp_nested_*.csv`,
`ar_first_stage_comp_credit_policy_block.csv`, `ar_first_stage_vol_*.{tex,csv}`,
`ar_routing_*.{tex,csv}`, `ar_b5_comparison_*.{tex,csv}`,
`ar_three_volume_compset_*.{tex,csv}`, `ar_three_volume_mayor_*.{tex,csv}`,
`C3_coverage_policy_block_size_bin.{csv,txt}`.
