# Office-specific exposure weights for office-specific (and cross-office) alignment shocks

**Type:** strategy memo (open methodological question + diagnostic plan + data and pipeline requirements).

**Status:** DECIDED (2026-05-13) — no coalition gating in the primary specification; use the pre-earliest-election window for cross-office channels. The mayoral-window exposure is retained as a mechanism-aligned robustness.

**Question.** When the alignment shift $\Align^{c}_{mpt}$ is office-specific (channel $c\in\{M\}$) or cross-office-specific ($c\in\{M\!\cdot\!P, M\!\cdot\!G, M\!\cdot\!G\!\cdot\!P\}$), which pre-period should define the exposure weight $w$, and should the share be gated by coalition membership?

**Cross-references:**
- `docs/methodology/ar_test_specification.tex` — eqs. `eq:Z-M`–`eq:Z-MGP` (the four sector-channel instruments) and Remark `rem:weights` (the convention this memo evaluates).
- `docs/PROJECT_BLUEPRINT.md` §4 (open-angles register — A18).
- `docs/strategy/ar_test_strategy.md` — overarching strategy memo for the AR test.

---

## 0. Settled choice: coalition definition (electoral, not governing)

**Decision (2026-05-10):** Use the office-specific *electoral* coalition (the registered *coligação* on the candidate slate of office $\ell$ at election $e_\ell$) for both $\mathrm{Align}^{P}$ and $\mathrm{Align}^{G}$. Do not use governing/legislative coalitions ("base aliada", post-election cabinet membership) in the primary specification.

**Why electoral:**
- Pinned to the election date — no within-term mutation as parties enter or leave the cabinet.
- Plausibly less endogenous to subsequent municipal economic outcomes than governing coalitions (which can respond to economic conditions through cabinet reshuffles).
- Fully observable from TSE candidate-coalition records.
- Office-specific by constitutional protection (EC 52/2006), so $\mathrm{Align}^{P}$, $\mathrm{Align}^{G}$, $\mathrm{Align}^{M}$ are separately measured per office and per election (subject to the 2002/2006 verticalização caveat below).

**Why not governing (for now):**
- Governing coalition is harder to detect — requires reading legislative records and cabinet appointments year by year, with judgment calls about which parties are "in" or "out" at any moment.
- More mechanism-relevant in principle (the cabinet is who actually allocates BNDES funds), but the trade-off in identification cleanliness is not worth the added endogeneity risk for the primary specification.
- **Recorded as future robustness (R-G):** re-run the primary AR test using governing-coalition definitions of $\mathrm{Align}^{P}$ (e.g., parties holding cabinet seats year-by-year) and $\mathrm{Align}^{G}$ (parties in the gubernatorial cabinet). Sources for governing coalitions: CEPESP coalition database, DataSenado, Power & Zucco's coalition-portfolio data, scholarly compilations of Brazilian *presidencialismo de coalizão*.

**Caveat on the 2002 and 2006 cycles (verticalização).** TSE Resolution 20.993/2002 required state-level coalitions to mirror the national presidential coalition for the 2002 and 2006 elections. Within our sample window, this binds the 2002 and 2006 electoral cycles (gubernatorial inaugurations 2003 and 2007; post-election years 2003–2010). For those cycles, $\mathrm{Align}^{G}_{s(m),pt}$ and $\mathrm{Align}^{P}_{pt}$ are not independently determined — the gubernatorial coalition is partially fixed by the presidential coalition by legal construction. Mechanically inflates the correlation between $Z^{M\cdot G}$ and $Z^{M\cdot P}$ for those cycles. Documented in `ar_test_specification.tex` (verticalização caveat in the levels-vs-changes subsection of the identification strategy section); the recommended robustness restricts the AR test to cycles 2010 and 2014 (post-verticalização sample).

**Implication for interpretation.** When a referee or reader asks why we did not use governing coalitions, the answer is: cleanliness of identification, not unawareness of the mechanism. This is an interpretive nuance, not a flaw — record it, plan the robustness, defer the implementation.

---

## 1. The decision

The four cross-office shift-share instruments (Eqs. `eq:Z-M`–`eq:Z-MGP` of `ar_test_specification.tex`) now use the channel-specific pre-earliest-election exposure $w^{F,c}_{jmp,t}$ as the primary share weight:

$$Z^{c}_{jmt} \equiv \sum_{p} w^{F,c}_{jmp,t}\,\mathrm{Align}^{c}_{mpt},\qquad c\in\{M,\,M\!\cdot\!P,\,M\!\cdot\!G,\,M\!\cdot\!G\!\cdot\!P\}.$$

The decided answer: **use no coalition gating, and anchor cross-office exposure before the earliest election among the offices in the channel.** The mayoral-window exposure $w^M$ remains a robustness specification because it is mechanism-aligned with the local intermediary, but it is no longer primary.

A coalition-specific exposure, not used in the primary specification, would count in each $(j,m)$ cell only owners affiliated with parties that were *politically active in the relevant coalition during the pre-period window*. For the mayor-president channel, a gated robustness weight such as $w^{B,M\cdot P}_{jmp,t}$ would weight owners of party $p$ by the average over $T^{M}_{t}$ of their relevance to the federal coalition at the time.

**Two orthogonal axes.** The decision problem has two independent dimensions:

1. **Coalition-gating axis** — whether the exposure share is computed across all owners (Variant A) or restricted to coalition-active owners (Variants B–D). Affects *who counts* in the share.
2. **Pre-window timing axis** — which office's electoral cycle anchors the pre-period $T^{\cdot}_t$ (Variants A vs E vs F). Affects *when the baseline is measured*.

**Decision (2026-05-13).** Variant F on the timing axis and no gating on the coalition axis is the **primary** specification: pre-earliest-election window $T^{F,c}_t$, no coalition gating. Variant A (mayoral pre-window for all channels) is the main mechanism-aligned robustness. Variant E (higher-tier pre-window) is a second timing robustness. The gating axis is deferred to robustness only; it is not part of the primary specification. Variant B′ (coalition-restricted denominator) is rejected because the share collapses in cells with few or no coalition-affiliated owners. The previously written "pre-last/pre-latest election" wording was wrong: a latest-election window can be post-treatment with respect to the office chosen earlier in a cross-office channel.

## 2. Why this matters

**Substantive reading.** The exposure share is the cross-sectional weight that converts a national/regional political shock into a sector-municipality intensity. In the primary specification it measures baseline owner-party affinity, not whether those owners belong to a governing or electoral coalition. The cross-office content enters through $\mathrm{Align}^{c}_{mpt}$: whether party $p$, or its electoral coalition, holds the mayoral and higher-tier offices defining channel $c$.

**Statistical reading.** The timing decision trades predetermination against measurement freshness. Variant F is most defensible because the share is measured before every election that defines the current cross-office state. Variant A can have more power if mayoral-cycle political affinity is persistent and more current, but it is less clean for cross-office channels because part of the baseline may be after the higher-tier election.

**Cost.** The primary pre-earliest window is mechanically older for about half the panel because Brazilian mayoral and gubernatorial/presidential elections alternate every two years. Coalition-gated shares remain a robustness question only: they could concentrate signal on politically active parties, but they also make the share depend on coalition membership and raise new BJS-1 conditioning concerns.

## 3. Candidate weight constructions

**Two orthogonal axes of variation.** The exposure weight can vary along (i) the **coalition-gating axis** — whether owners affiliated with non-coalition parties contribute to the share — and (ii) the **pre-window timing axis** — which office's election defines $T^{\cdot}_t$. Variants A, E, and F vary the window with no gating; B and C vary gating and are deferred robustness only.

### 3.1 Coalition-gating axis (window fixed at $T^{M}_t$)

Define the firm support of cell $(j,m)$ as $\mathcal{F}(j,m)$ and pre-period window $T^{M}_{t} = [e_{M}(t)-4,\ e_{M}(t)-1]\cap[2002,2017]$ (mayoral window from `eq:window`).

### Variant A — Mayoral exposure (main robustness)
$$
w^{M}_{jmp,t} = \frac{1}{|T^{M}_{t}|}\sum_{s\in T^{M}_{t}}
  \frac{\sum_{f\in\mathcal{F}(j,m)} L_{f,p,s}}{\sum_{f\in\mathcal{F}(j,m)} L_{f,s}}
$$
The "exposure to party $p$" is the average over $T^{M}_{t}$ of the share of owner-counts in cell $(j,m)$ affiliated with $p$. **Cycle-dependence:** updates only at mayoral inaugurations; structural cross-section stable within mandate.

**Pros:** simple; one exposure object for all channels; same BJS-1 conditions as in the original tier instruments; no party-side selection.

**Cons:** treats all parties symmetrically in the exposure, even if only coalition-affiliated owners can plausibly transmit the channel-$c$ shock.

### Variant B — Coalition-active exposure
$$
w^{c}_{jmp,t} = \frac{1}{|T^{M}_{t}|}\sum_{s\in T^{M}_{t}}
  \frac{\sum_{f\in\mathcal{F}(j,m)} L_{f,p,s}\cdot\mathbf{1}[p\in\mathcal{K}^{c}(s)]}{\sum_{f\in\mathcal{F}(j,m)} L_{f,s}}
$$
where $\mathcal{K}^{c}(s)$ is the set of parties active in the relevant coalition at time $s$ (federal coalition for $c\in\{M\!\cdot\!P,M\!\cdot\!G\!\cdot\!P\}$, gubernatorial coalition of state $s(m)$ for $c\in\{M\!\cdot\!G\}$). Owners affiliated with parties outside $\mathcal{K}^{c}(s)$ are zeroed out of the exposure.

**Pros:** exposure aligns with the channel-relevant political capital; first-stage power likely higher.

**Cons:** $w^{c}$ now varies with the federal/state political cycle through $\mathcal{K}^{c}(s)$; BJS-1 must condition on the coalition-membership process; Adão–Kolesár–Morales correction must use coalition-cycle-relative shock clusters.

**Note on numerator-only gating.** Variant B keeps the denominator at *total* cell employment $\sum_{f}L_{f,s}$; only the numerator is restricted to coalition-active owners. So for party $p$ always in coalition $\mathcal{K}^{c}$ during $T^{M}_t$, $w^{B}_{jmp,t} = w^{A}_{jmp,t}$ — the two variants coincide. They differ only for parties whose coalition status *changes within the pre-window*. This makes Variant B a comparatively mild refinement of A.

### Variant B′ — Coalition-restricted denominator (rejected)
$$
w^{B'}_{jmp,t} = \frac{1}{|T^{M}_{t}|}\sum_{s\in T^{M}_{t}}
  \frac{\sum_{f\in\mathcal{F}(j,m)} L_{f,p,s}\cdot\mathbf{1}[p\in\mathcal{K}^{c}(s)]}{\sum_{f\in\mathcal{F}(j,m)}\sum_{p'} L_{f,p',s}\cdot\mathbf{1}[p'\in\mathcal{K}^{c}(s)]}
$$
A near-cousin of Variant B that *also* restricts the denominator to coalition-active owners — so the share measures party-$p$'s weight *among* the politically-active subset of the cell.

**Rejected (2026-05-10).** For sector-muni cells with few or no owners affiliated with parties in $\mathcal{K}^{c}$ — which is common in small munis where most owners are unaffiliated or affiliated with fringe parties — the denominator collapses to zero (undefined share) or near-zero (extreme volatility). Brazil's owner-affiliation distribution is heavy-tailed; many production cells have political coverage in the single digits. Recorded here so future readers (and authors) do not confuse it with Variant B, which keeps the total-employment denominator.

### Variant C — Coalition-frequency-weighted exposure
$$
w^{c\,\text{freq}}_{jmp,t} = \frac{1}{|T^{M}_{t}|}\sum_{s\in T^{M}_{t}}
  \frac{\sum_{f\in\mathcal{F}(j,m)} L_{f,p,s}\cdot\pi^{c}_{p}(s)}{\sum_{f\in\mathcal{F}(j,m)} L_{f,s}}
$$
where $\pi^{c}_{p}(s) \in [0,1]$ is the fraction of pre-period years $s\in T^{M}_{t}$ in which $p\in\mathcal{K}^{c}(s)$. This is a smooth version of Variant B that down-weights, rather than zeroes, owners affiliated with parties that were only sometimes coalition-active.

**Pros:** retains more identifying variation than Variant B; smoother dependence on coalition membership; less sensitive to the binary $\mathcal{K}^{c}$ definition at the boundary.

**Cons:** the same BJS-1 complication as Variant B; harder to interpret; introduces a free dimension (definition of $\pi$).

### Variant D — Two-step exposure with coalition gating
Use $w^{M}_{jmp,t}$ as the structural exposure and gate the *shift*, not the share, on coalition membership: the current Variant A construction with the existing $\mathrm{Align}^{M\cdot P}_{mpt} = \mathrm{Align}^{M}_{mpt}\cdot\mathrm{Align}^{P}_{pt}$ already does this. The question is whether Variant B/C add anything to D.

**Pros:** identical to current implementation; no new identification machinery.

**Cons:** if owners affiliated with parties never in the coalition contribute to the exposure, they dilute the signal in cells where they are present.

### 3.2 Pre-window timing axis (gating fixed at "none")

The variants below hold the gating at "none" (as in Variant A) and vary the pre-window. The timing of $T^{\cdot}_t$ pins down *when* the political-capital baseline is measured. Define the office-specific window
$$T^{\ell}_{t} \;=\; [\,e_{\ell}(t)-4,\ e_{\ell}(t)-1\,] \;\cap\; [2002,2017],\quad \ell\in\{M,\ G,\ P,\ L\},$$
where $e_{\ell}(t)$ is the most recent election of office $\ell$ on or before year $t$ — including year $t$ itself if $t$ is an election year for $\ell$ (so the pre-window is *strictly before* the most recent electoral event, never overlapping it). Brazilian gubernatorial and presidential elections coincide from 1994 onward, so $T^{G}_t = T^{P}_t$ throughout the sample, and we write $T^{G/P}_t$.

### Variant E — Higher-tier pre-window
$$
w^{E}_{jmp,t} = \frac{1}{|T^{G/P}_{t}|}\sum_{s\in T^{G/P}_{t}}
  \frac{\sum_{f\in\mathcal{F}(j,m)} L_{f,p,s}}{\sum_{f\in\mathcal{F}(j,m)} L_{f,s}}
$$
Identical to Variant A in construction, but the pre-period is anchored to the most recent gubernatorial/presidential election rather than the mayoral one. Used uniformly across all four channels (including the pure-mayor channel $Z^{M}$, where the window is now mismatched with the local shift dimension — that mismatch is the whole point of the robustness).

**Pros:** the political-capital baseline is measured at the higher-tier electoral moment. If owners adjust party affiliation in anticipation of federal/state outcomes rather than municipal ones, $T^{G/P}_t$ is the structurally cleaner pre-period for the cross-office channels.

**Cons:** temporally misaligned with the local political moment. $T^{G/P}_t$ falls in the middle of the previous mayor's term, so the baseline is already partially endogenous to local politics from the prior cycle. For the pure-mayor channel, the window mismatch is mechanical — it should drag the AR statistic toward zero if the local cycle is the operative one.

### Variant F — Pre-earliest-election window (channel-specific primary)
$$
w^{F,c}_{jmp,t} = \frac{1}{|T^{F,c}_{t}|}\sum_{s\in T^{F,c}_{t}}
  \frac{\sum_{f\in\mathcal{F}(j,m)} L_{f,p,s}}{\sum_{f\in\mathcal{F}(j,m)} L_{f,s}}
$$
For a channel $c$, let $\mathcal{O}(c)$ be the set of offices entering the
channel: $\mathcal{O}(M)=\{M\}$, $\mathcal{O}(M\!\cdot\!P)=\{M,P\}$,
$\mathcal{O}(M\!\cdot\!G)=\{M,G\}$, and
$\mathcal{O}(M\!\cdot\!G\!\cdot\!P)=\{M,G,P\}$. Define
$e_{F,c}(t)\equiv \min_{\ell\in\mathcal{O}(c)} e_\ell(t)$ and
$T^{F,c}_{t}=[\,e_{F,c}(t)-4,\ e_{F,c}(t)-1\,]\cap[2002,2017]$.
The window is therefore before the earliest election that enters the current
cross-office state. For the pure-mayor channel this collapses to Variant A;
for cross-office channels it is stricter than both the mayoral and higher-tier
windows because it precedes every office in the channel.

**Worked examples** (Brazilian electoral calendar — mayoral: 2000/04/08/12/16; gov/pres: 2002/06/10/14):

| $t$ | $e_M(t)$ | $e_{G/P}(t)$ | $e_{F,c}(t)$ for cross-office channels | $T^{F,c}_t$ |
|---|---|---|---|---|
| 2008 (mayoral) | 2008 | 2006 | 2006 | $[2002, 2005]$ |
| 2010 (gov/pres) | 2008 | 2010 | 2008 | $[2004, 2007]$ |
| 2011 | 2008 | 2010 | 2008 | $[2004, 2007]$ |
| 2012 (mayoral) | 2012 | 2010 | 2010 | $[2006, 2009]$ |
| 2014 (gov/pres) | 2012 | 2014 | 2012 | $[2008, 2011]$ |
| 2017 | 2016 | 2014 | 2014 | $[2010, 2013]$ |

**Pros:** the baseline precedes every officeholder entering the cross-office
shift, so it is the cleanest option against contamination from either the
mayoral or higher-tier election.

**Cons:** the baseline is mechanically older for half of the panel because
Brazilian mayoral and gubernatorial/presidential elections alternate every two
years. That buys stricter predetermination at the cost of a staler, noisier
measure of the party-affiliation stock. It also makes the exposure
channel-specific, whereas Variant A keeps one mayoral-window exposure object
for all channels.

## 4. What the literature says (initial reading, to be refined)

### BHJ (2022, REStud) — shift-exogeneity path
- The exposure shares $w^{\ell}_{jmp,t}$ can be endogenous; identification comes from quasi-random *shifts* $\mathrm{Align}^{\ell}_{mpt}$ conditional on shock-level controls $q_k$.
- Shocks are at the shock-level — $(c,p,m,t)$ in our coalition notation.
- BJS-3 (non-concentration of average exposure) is what disciplines the choice of $w$: a weight that concentrates exposure on a small subset of owner-party-cells weakens the asymptotic-normality argument.
- *Implication for our case:* if Variant B zeroes out a large fraction of owners (because they are affiliated with non-coalition parties most of the time), the Herfindahl of the average exposure rises. Need to compute this empirically.

### BHJ (2025, JEP) — practical guide
- Multiple shock sets combined via overidentified shock-level IV.
- For shifts that are correlated across periods of the same shock dimension (e.g., national waves in $\mathrm{Align}^{P}$), the recommended fix is shock-level inference with clusters defined on the shock dimension.
- The guide recommends *checking whether the SSIV estimate is robust to alternative share constructions*. This directly motivates reporting the mayoral-window and higher-tier-window timing variants, and later any coalition-gated variants, against the Variant F primary.
- The `ssaggregate` package transforms the panel to the shock level; the exposure choice is an input.

### GPSS (2020, AER) — share-exogeneity path
- Each share is a Rotemberg-weighted instrument; the SSIV coefficient is a weighted average of share-specific LATEs.
- Under share exogeneity, the exposure construction matters more directly because each cell's weight enters the LATE decomposition. Variant B effectively focuses the LATE on coalition-affiliated cells.
- *Caveat:* GPSS assumes share exogeneity, which is not the path we are using. Their Rotemberg-weight diagnostics, however, are useful regardless: they tell us which cells dominate the SSIV estimate.

### AKM (2019, QJE) — inference correction
- Inference at the shock level when residuals are correlated within exposure-similar units.
- *Implication:* under any weight choice, the AKM correction is the right inference; the question is what defines "exposure-similar" — it depends on which $w$ is used.

## 5. Empirical analysis required

**Goal:** implement the decided primary exposure (Variant F, no gating) and report robustness diagnostics for the mayoral-window, higher-tier-window, and later gating variants.

### Tasks

1. **Build the active exposure variants** for the leading candidate margin. Window-axis variants (F, A, E) have no new data dependencies and are built first; gating-axis variants (B, C) require coalition rosters and are deferred:
   - Variant F *(primary)*: same primitives as A, with $T^{F,c}_t = [e_{F,c}(t)-4,\ e_{F,c}(t)-1]$ where $e_{F,c}(t)=\min_{\ell\in\mathcal{O}(c)} e_\ell(t)$. Tabulate $e_{F,c}(t)$ for $t\in[2002,2017]$ and each channel (one-time), then re-window the pre-period join. **No new data input.**
   - Variant A *(main robustness)*: existing mayoral-window $w^{M}_{jmp,t}$ from script `3_instruments/31_*` outputs, used for all channels.
   - Variant E *(second timing robustness)*: same as A, with $T^{G/P}_t$ replacing $T^{M}_t$. New script — joins the existing owner-party-firm panel against gov/pres-election years. **No new data input.**
   - Variant B *(gating robustness, deferred)*: define $\mathcal{K}^{c}(s)$ from federal/state coalition membership records. New data input — coalition rosters by year. For the federal coalition, the source is the *Câmara dos Deputados* coalition records; for state coalitions, *Tribunal Superior Eleitoral* candidate-coalition data. Both are public.
   - Variant C *(gating robustness, deferred)*: compute $\pi^{c}_{p}(s)$ as the fraction of $s\in T^{M}_{t}$ with $p\in\mathcal{K}^{c}(s)$. Same coalition data as B.
   - Variant D: identical to A in implementation (gate is on $\mathrm{Align}$, not $w$); no separate build required.
   - Variant B′: rejected (see §3.1).

2. **Diagnostic comparisons:**
   - **Cross-variant correlation matrix** of $Z^{c}_{jmt}$ across F, A, E (and later B, C). If $\mathrm{corr}(Z^{c,F}, Z^{c,X}) > 0.95$ for $X\in\{A,E\}$, the timing choice is empirically immaterial; keep F as primary and report A/E as confirmation. Likely outcome if pre-window owner-affiliation distributions are persistent across cycles.
   - **First-stage F-statistic** at the cross-office channel level, separately under each variant. For the window axis, expect $F_A$ to be at least as large as $F_F$ if the newer mayoral baseline is less noisy, but $F_F$ remains the cleaner predetermined baseline. For the gating axis, expect $F_B > F_F$ only if the coalition-active subset carries the signal.
   - **Herfindahl of average exposure** across shocks (BJS-3 diagnostic). Variant B is expected to have higher Herfindahl; Variants E and F should be close to A. Quantify.
   - **AR statistic stability:** run the AR test under each variant for the pure-mayoral and the three cross-office channels; report all. BHJ (2025) recommends this kind of robustness as standard practice.

3. **Decision rule:**
   - **Primary is fixed (Variant F, no gating).** Robustness either confirms or qualifies; it does not replace.
   - For each robustness variant $X \in \{A,\ E,\ B,\ C\}$:
     - If AR statistics under F and X are within $\pm 5\%$ and AR confidence sets overlap substantially, report X in an appendix robustness table.
     - If they diverge meaningfully and the AR test rejects under one but not the other, the divergence itself is a finding — flag it and discuss in the paper which window/gating is closer to the structural interpretation of the channel.
   - **Window-axis robustness (E, F) is the binding test of the timing assumption** — these are the variants the referee will ask for.

### Data inputs needed

**Window-axis variants (F, A, E):** no new data inputs. The existing owner-party-firm panel (`2_firm_panel/22_*`) plus the existing election-year calendar are sufficient.

**Gating-axis variants (B, C), deferred:**
- **Federal presidential coalitions, 2002–2017.** Annual list of parties in the federal coalition. Source: *Câmara dos Deputados* legislative records, *DataSenado*, or compilations from CEPESP/FGV.
- **Gubernatorial coalitions by state, 2002–2017.** Annual list of parties in each gubernatorial coalition. Source: TSE candidate-coalition records (the parties that ran together as a coalition for governor in each cycle).

### Pipeline extension

**Phase 1 (window axis, F + A + E):**
- New script: `3_instruments/31c_build_window_variants.R` — accepts a `--window` argument (`pre_earliest`, `mayor`, `higher_tier`) and re-windows the existing owner-party-firm panel before averaging to $w_{jmp,t}$. Outputs `w_window_jmpt.fst` with columns `(j, m, p, t, channel, w_F, w_A, w_E)`.

**Phase 2 (gating axis, B + C), deferred:**
- New script: `3_instruments/30g_build_coalition_rosters.R` — ingests TSE/Câmara data and outputs `coalition_rosters_yearly.fst` with columns `(year, tier, state, party, in_coalition)`.
- New script: `3_instruments/31b_build_coalition_exposure.R` — joins the coalition roster to the existing owner-party-firm panel and computes Variants B and C. Outputs `w_coalition_jmpt.fst` with columns `(j, m, p, t, channel, w_A, w_B, w_C)`.

**Both phases:**
- Modified script: `3_instruments/35_*` (instrument assembly) — accept an `--exposure-variant` argument and produce $Z^{c}$ under each variant.

## 6. Proposed timing

1. **Now (decided 2026-05-13):** Variant F (channel-specific pre-earliest-election exposure, no gating) is the **primary** specification of the AR test, recorded in `ar_test_specification.tex` Remark `rem:weights`. Variant A (mayoral-window exposure for all channels) is the main mechanism-aligned robustness. Variant E (higher-tier pre-window) is a second timing robustness. Variants B and C (gating-axis robustness) are deferred. Variant B′ is rejected.
2. **Next sprint (1–2 weeks):** build the window-axis stack F/A/E (no new data inputs) via `3_instruments/31c_build_window_variants.R`. Run the §5.2 diagnostic comparisons across F, A, E.
3. **Following sprint (2–3 weeks):** read BHJ (2022, 2025) closely — §4 of BHJ (2022) on shock-level inference and §3 of BHJ (2025) on share-construction sensitivity. If they argue for coalition-gated exposure, proceed to ingest TSE/Câmara coalition data and build Variants B and C; otherwise document the gating axis as a known-but-untested robustness in the paper's appendix.
4. **Decision:** lock the full robustness suite (which variants enter the paper's robustness table) by the time the AR test moves out of exploration.

## 7. References

- Adão, R., M. Kolesár, and E. Morales (2019). "Shift-share designs: Theory and inference," *QJE* 134(4): 1949–2010.
- Borusyak, K., P. Hull, and X. Jaravel (2022). "Quasi-experimental shift-share research designs," *RES* 89(1): 181–213.
- Borusyak, K., P. Hull, and X. Jaravel (2025). "A practical guide to shift-share instruments," *JEP* 39(1): 181–204.
- Goldsmith-Pinkham, P., I. Sorkin, and H. Swift (2020). "Bartik instruments: What, when, why, and how," *AER* 110(8): 2586–2624.
