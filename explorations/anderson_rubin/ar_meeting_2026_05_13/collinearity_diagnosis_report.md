# Phase 1A — Instrument-Collinearity Diagnosis: Report

**Date:** 2026-05-21
**Script:** `R/B7_collinearity_diagnosis.R`
**Plan:** `journal/plans/2026-05-21_multi-channel-first-stages.md`, Phase 1A

> **Note (2026-05-21, post-review).** B7 has since been corrected to evaluate
> **18 candidate stacks** — the parent pairs `{M, G}` and `{M, P}` were added
> at the user's request. B7 has **not yet been re-run**; §4–§6 below reflect
> the original 16-stack run. Re-running B7 (at the start of Phase 1B) refreshes
> them with all 18 stacks. The verdict — no near-collinearity in any stack — is
> not expected to change: `{M, G}` and `{M, P}` are 2-channel parent pairs
> structurally like the already-evaluated `{G, P}` pair (κ = 1.28 / 1.51).

---

## 1. What "B7" is

B7 is a **script**, not a document: `R/B7_collinearity_diagnosis.R`. The
AR-test follow-up scripts are named in a B-series — `B2` composition first
stage, `B3` volume first stage, `B2b`/`B3b` multi-channel variants, `B4`
routing, `B5` advisor comparison, `B6` the AR test, and `B7` (new) the
collinearity diagnosis. "B7" is just the seventh script in that series.

This file is the prose report of what B7 found.

## 2. Where the results live

| File | Content |
|---|---|
| `output/collinearity_diagnosis_policy_block.csv` | Per-stack diagnostics, 4-group margin |
| `output/collinearity_diagnosis_policy_block_size_bin.csv` | Per-stack diagnostics, 12-group margin |
| `output/collinearity_diagnosis_<tax>.tex` | The same, as a slide table |
| `output/instrument_admissibility_<tax>.csv` | Proposed admissibility verdict per stack |
| `output/interaction_construction_audit.csv` | 1A.1 audit of the interaction alignment columns |
| `output/design_attribution_<tax>.csv` | 1A.4 verticalizado vs post correlation split |
| `journal/meetings/2026-05-21/slides.tex` pp. 23–24 | Two diagnosis slides |

## 3. What B7 computes

For each candidate **instrument stack** (a set of channels evaluated together),
B7 takes the wide instrument block — every column `Z_<channel>_<sector>` of
every channel in the stack — and **residualises** it on the regressors the AR
test conditions on: muni and year fixed effects, the exposure-control (EC)
block, and the volume ratio. On the residualised block it reports:

- **Condition number** κ = √(λ_max/λ_min) of the correlation matrix
  (Belsley-Kuh-Welsch). κ ≤ 30 = well-conditioned; 30–100 = moderate-to-strong
  collinearity; > 100 = severe.
- **Worst VIF** — variance inflation factor of the most-inflated column.
  VIF > 10 is the conventional collinearity flag.
- **Rank** of the block (full rank = no exact linear dependence).
- **Max |r|** and **mean |r|** — largest and average pairwise correlation
  among the residualised instrument columns.

## 4. The 16 candidate stacks

Yes — **all 16 were evaluated, at both margins.** They fall in four groups:

**Group 1 — singletons (7).** Each channel on its own:
`{M}`, `{G}`, `{P}`, `{M·G}`, `{M·P}`, `{G·P}`, `{M·G·P}`.

**Group 2 — mayor stacks (4).** The Mayor paired with each mayor-crossed
interaction, plus the full mayor-crossed stack:
`{M, M·P}`, `{M, M·G}`, `{M, M·G·P}`, and `{M, M·P, M·G, M·G·P}`.

**Group 3 — parent + interaction (3 trios + 1 quad = 4).** A stack holding an
interaction together with *all* of its single-office parents:
`{M, P, M·P}`, `{M, G, M·G}`, `{G, P, G·P}` (trios), and `{M, G, P, M·G·P}`
(the triple interaction with its three parents).

**Group 4 — diagnostic G/P/GP (1).** `{G, P}` — Governor with President.
(`{G·P}` singleton is in Group 1; `{G, P, G·P}` is the third trio in Group 3.)

7 + 4 + 4 + 1 = **16.** The "additional three" beyond a 7 + 3 + 3 count are:
the **full mayor stack** `{M, M·P, M·G, M·G·P}`, the **`{M, G, P, M·G·P}`
quad**, and the **`{G, P}` pair**.

## 5. Collinearity results — both margins

K = number of instrument columns. Rank = numerical rank of the residualised
block. All κ, VIF, and |r| are measured *after* partialling out FE + EC +
volume ratio.

### Policy block (4 sectors)

| Stack | K | Rank | κ | Worst VIF | Mean \|r\| | Max \|r\| |
|---|---|---|---|---|---|---|
| `{M}` | 4 | 4 | 1.28 | 1.06 | 0.098 | 0.193 |
| `{G}` | 4 | 4 | 1.23 | 1.04 | 0.085 | 0.158 |
| `{P}` | 4 | 4 | 1.04 | 1.00 | 0.016 | 0.028 |
| `{M·G}` | 4 | 4 | 1.31 | 1.07 | 0.118 | 0.188 |
| `{M·P}` | 4 | 4 | 1.27 | 1.05 | 0.090 | 0.171 |
| `{G·P}` | 4 | 4 | 1.18 | 1.02 | 0.064 | 0.132 |
| `{M·G·P}` | 4 | 4 | 1.35 | 1.09 | 0.114 | 0.217 |
| `{M, M·P}` | 8 | 8 | 1.91 | 1.32 | 0.101 | 0.446 |
| `{M, M·G}` | 8 | 8 | 2.03 | 1.33 | 0.128 | 0.453 |
| `{M, M·G·P}` | 8 | 8 | 1.62 | 1.16 | 0.080 | 0.246 |
| `{M, M·P, M·G, M·G·P}` | 16 | 16 | 3.80 | 2.53 | 0.116 | 0.668 |
| `{M, P, M·P}` | 12 | 12 | 2.41 | 1.74 | 0.078 | 0.527 |
| `{M, G, M·G}` | 12 | 12 | 2.70 | 1.85 | 0.103 | 0.503 |
| `{M, G, P, M·G·P}` | 16 | 16 | 1.91 | 1.32 | 0.047 | 0.305 |
| `{G, P}` | 8 | 8 | 1.28 | 1.05 | 0.035 | 0.158 |
| `{G, P, G·P}` | 12 | 12 | 2.60 | 2.04 | 0.081 | 0.564 |

### Policy block × firm size (12 sectors)

| Stack | K | Rank | κ | Worst VIF | Mean \|r\| | Max \|r\| |
|---|---|---|---|---|---|---|
| `{M}` | 12 | 12 | 1.41 | 1.06 | 0.042 | 0.154 |
| `{G}` | 12 | 12 | 1.33 | 1.05 | 0.037 | 0.160 |
| `{P}` | 12 | 12 | 1.08 | 1.00 | 0.011 | 0.044 |
| `{M·G}` | 12 | 12 | 1.47 | 1.08 | 0.053 | 0.183 |
| `{M·P}` | 12 | 12 | 1.38 | 1.07 | 0.040 | 0.149 |
| `{G·P}` | 12 | 12 | 1.30 | 1.05 | 0.030 | 0.144 |
| `{M·G·P}` | 12 | 12 | 1.50 | 1.09 | 0.053 | 0.190 |
| `{M, M·P}` | 24 | 24 | 2.20 | 1.37 | 0.042 | 0.477 |
| `{M, M·G}` | 24 | 24 | 2.38 | 1.45 | 0.052 | 0.517 |
| `{M, M·G·P}` | 24 | 24 | 1.86 | 1.19 | 0.036 | 0.303 |
| `{M, M·P, M·G, M·G·P}` | 48 | 48 | 4.53 | 3.43 | 0.047 | 0.760 |
| `{M, P, M·P}` | 36 | 36 | 2.85 | 1.97 | 0.033 | 0.565 |
| `{M, G, M·G}` | 36 | 36 | 3.18 | 2.05 | 0.043 | 0.562 |
| `{M, G, P, M·G·P}` | 48 | 48 | 2.27 | 1.42 | 0.022 | 0.358 |
| `{G, P}` | 24 | 24 | 1.51 | 1.13 | 0.016 | 0.293 |
| `{G, P, G·P}` | 36 | 36 | 3.08 | 2.32 | 0.032 | 0.631 |

## 6. Verdict: is there near-collinearity? — No.

**Not in any of the 16 stacks, at either margin.**

- The **largest condition number** anywhere is κ = 4.53 (the 48-column full
  mayor stack, 12-group margin). The threshold for even *moderate*
  collinearity is κ = 30; the proposed admissibility gate is κ ≤ 30. Every
  stack is between 6× and 30× below that gate.
- The **worst VIF** anywhere is 3.43 — the conventional flag is VIF > 10.
- **Every stack is full rank** (rank = K everywhere) — no exact linear
  dependence among the instrument columns.

The only non-trivial number is **max |r|**: same-sector cross-channel
correlations reach 0.45–0.76 in the multi-channel stacks. That is a meaningful
*pairwise* correlation, but it does not produce block ill-conditioning —
mean |r| stays at 0.02–0.13, and the condition numbers confirm the block as a
whole is well-conditioned. A pair of correlated columns inside an otherwise
orthogonal 16- or 48-column block does not inflate variances materially.

**The stacked-long collinearity seen earlier does not carry over.** The earlier
checkpoint observed rank-deficient / inflated joint F statistics in the
*stacked-long* first stage (`B2b`/`B3b`), where the seven channels enter as
seven scalar columns at the muni-sector-year level. That parameterisation is
not the first stage the AR test embeds. In the **wide-form** block — the one
the AR test uses — there is no collinearity problem.

## 7. How the interaction instruments are built (important clarification)

The interaction channels use **one** construction, built by the pipeline:

> `Z^{MG}_{jmt} = Σ_p w̃^{MG}_{jmp,t} · Align^M_{mpt} · Align^G_{mpt}`

where `w̃^{MG}` is a **single MG-channel baseline owner-share** (one number per
muni-year-sector-party, built in `01_build_variant_a_weights.R` with the
MG-channel window), and `Align^M·Align^G` is the interaction alignment column
(`align_mayor_gov_coalition`). This is `share_affiliated_baseline_AB ·
alignment_A · alignment_B`.

This is **not** the product of the two single-office instruments,
`(Σ_p w̃^M Align^M)·(Σ_p w̃^G Align^G)`, which would involve two separate
baseline shares and a product of two party-sums. That object is **not built
anywhere** in the pipeline and was **not** evaluated by B7. B7 evaluated the
channel-built interaction only.

**The 1A.1 audit** verified only that the *alignment indicator column*
`align_mayor_gov_coalition` equals `align_mayor_coalition × align_gov_coalition`
(exact, on all 1,288,211 rows). That is a fact about the 0/1 alignment dummies.
It does **not** imply the *instrument* `Z^{MG}` is collinear with `Z^M` and
`Z^G`. Numerically:

- `Z^{MG}_j` vs the product `Z^M_j·Z^G_j`: correlation 0.74–0.86, not equal —
  the absolute gap is up to half the magnitude of `Z^{MG}`.
- Regressing each `Z^{MG}_j` on the full {`Z^M`, `Z^G`} block (FE-partialled):
  R² = 0.53–0.64 — roughly 40% of `Z^{MG}` is orthogonal to its parents.

So the `{M, G, M·G}`-type stacks are genuinely full-rank and well-conditioned
(κ = 2.7 / 3.2), as the table in §5 shows.

## 8. Design attribution (1A.4) — verticalização is not the source

Residual cross-channel correlation split by sub-period (policy block; the
verticalizado cycles 2002+2006 are years < 2010, the post cycles 2010+2014 are
years ≥ 2010):

| Channel pair | Verticalizado | Post | Verticalizado − Post |
|---|---|---|---|
| G vs P | 0.023 | 0.027 | −0.004 |
| M·G vs M·P | 0.025 | 0.094 | −0.069 |
| M·G vs M·G·P | 0.063 | 0.210 | −0.147 |
| M·P vs M·G·P | 0.171 | 0.187 | −0.016 |
| M vs M·G | 0.112 | 0.170 | −0.058 |
| M vs M·P | 0.034 | 0.160 | −0.127 |

Every pair shows **lower** residual correlation in the verticalizado period,
not higher. Verticalização is not the source of the (mild) cross-channel
correlation; what correlation exists is a post-2010 phenomenon.

## 9. Proposed admissibility and the open question

The `verdict` column in `instrument_admissibility_<tax>.csv` marks the four
**parent + interaction** stacks (`{M,P,M·P}`, `{M,G,M·G}`, `{M,G,P,M·G·P}`,
`{G,P,G·P}`) as *inadmissible*. That flag comes from the plan's 1A.1 rule —
"an interaction that is the exact product of its parents makes the
parent+interaction stack inadmissible a priori" — **not** from measured
collinearity. As §5–§7 show, those four stacks are full-rank and
well-conditioned (κ ≤ 3.2). The a-priori rule was premised on alignment-level
nesting implying instrument-level collinearity; it does not.

**Read off the measured diagnostics, all 16 stacks are admissible** — there is
no collinearity-based reason to prune any of them. Whether to keep the a-priori
rule as a deliberate modelling preference is a checkpoint-#1 decision for the
user.
