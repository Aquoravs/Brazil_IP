---
title: "Align regs.tex Notation with Four-IV Implementation Plan"
type: refactor
status: completed
date: 2026-03-11
origin: docs/plans/2026-03-10-feat-four-iv-specifications-unified-pipeline-plan.md
---

# Align `regs.tex` Notation with Four-IV Implementation Plan

## Overview

The paper `paper/regs.tex` defines four IV specifications (firm levels, firm changes, sector levels, sector changes) using mathematical notation that has diverged from the design decisions in the implementation plan. This plan proposes targeted edits to `regs.tex` so that (a) the notation cleanly differentiates all four specifications, (b) the aggregation link between firm and sector instruments is stated precisely, and (c) the paper matches the code's naming conventions and construction logic.

## Problem Statement

Seven concrete notation problems have been identified through cross-referencing `regs.tex`, the implementation plan, CLAUDE.md, and the actual code in scripts 31/34/51:

| # | Problem | Location in `regs.tex` | Severity |
|---|---------|------------------------|----------|
| 1 | Same base symbol `Z` for firm and sector instruments — differentiated only by subscript `f` vs `j` | lines 93, 131 | High — easy to confuse |
| 2 | Firm exposure `w_{fmpt}` carries a spurious municipality subscript — `L_{fp}/L_f` doesn't vary by `m` | line 83 | Medium — misleading |
| 3 | Aggregation link claims sector instrument is "employment-weighted average" of firm instruments, but sector weights use owner counts | line 147 | **Critical** — factually incorrect |
| 4 | Paper uses identical denominator formula for firm and sector, but code treats "No party" differently in numerator | lines 83, 125 | Medium — obscures the distinction |
| 5 | Coefficient letters overloaded: `κ_ℓ` used for both instrument and exposure control in sector specs; `λ_ℓ` in text references `κ_ℓ` | lines 100, 102, 138 | Medium — confusing |
| 6 | No formalization of cycle-specific vs. 2002-fixed baselines; `τ(t)` mentioned but never defined | line 85 | Medium — incomplete |
| 7 | Baseline exposure paragraph duplicated verbatim between firm-level (lines 80–85) and sector-level (lines 122–126) sections | lines 80, 122 | Low — redundant |

Additionally, three design decisions from the implementation plan are absent from the paper:

- Employment weighting enters firm regressions as analytic regression weights, not through separate instruments.
- The two pipelines (firm with employment weights, sector with owner counts) are complementary, not nested.
- Sector-level exposure control must vary at the municipality × sector level (not replicated from municipality level).

## Proposed Notation System

### Design Principles

1. **Distinct base symbols** for firm vs. sector instruments — a reader scanning equations should immediately know which specification is being discussed.
2. **Subscripts reflect actual variation** — no spurious indices.
3. **Aggregation link made explicit** — state the identity under owner-count weighting; note the employment-weighted variant as a separate diagnostic.
4. **Levels vs. changes distinguished by operator** — `Δ` prefix for changes instruments (constructed from `ΔAlign`), with a footnote clarifying this is not the first difference of the levels instrument.
5. **One coefficient letter per role** — `λ` for instrument coefficients, `φ` for exposure control, `β` reserved for second stage.

### Symbol Table

| Object | Current notation | Proposed notation | Rationale |
|--------|-----------------|-------------------|-----------|
| Firm-level exposure share | `w_{fmpt}` | `ω_{fp,τ}` | Remove spurious `m`; use `τ` for baseline period; lowercase omega distinguishes from sector `w` |
| Sector-level exposure share | `w_{jmpt}` | `w_{jmp,τ}` | Retain `w` for sector; add explicit `τ` baseline subscript |
| Firm-level levels instrument | `Z^{ℓ}_{fmt}` | `FA^{ℓ}_{fmt}` | Mnemonic: "Firm Alignment"; matches code prefix `FA_*` |
| Firm-level changes instrument | `ΔZ^{ℓ}_{fmt}` | `ΔFA^{ℓ}_{fmt}` | Matches code prefix `dFA_*` |
| Sector-level levels instrument | `Z^{ℓ}_{jmt}` | `Z^{ℓ}_{jmt}` | Retain existing sector notation |
| Sector-level changes instrument | `ΔZ^{ℓ}_{jmt}` | `ΔZ^{ℓ}_{jmt}` | Retain; add footnote: not the first difference of `Z^{ℓ}_{jmt}` |
| Alignment level (spread) | `Align^{ℓ}_{mpt}` | `Align^{ℓ}_{mpt}` | No change needed |
| Alignment turnover | `ΔAlign^{ℓ}_{mpt}` | `ΔAlign^{ℓ}_{mpt}` | No change needed |
| Instrument coefficient | `λ_ℓ` / `κ_ℓ` (mixed) | `λ_ℓ` everywhere | One letter for all first-stage instrument coefficients |
| Exposure control coefficient | `κ` (overloaded) | `φ` | Disambiguate from instrument coefficient |
| Exposure control (sector) | `Exposure_{jmt}` | `EC_{jm,τ} = Σ_p w_{jmp,τ}` | Clarify it varies at muni × sector × baseline, not muni-level |
| Baseline period map | `τ(t)` (mentioned, undefined) | `τ(t)` with explicit cycle map | Define `τ(t)` → pre-election year for the electoral cycle containing `t` |

### Why `FA` and Not a Calligraphic `Z`

Three arguments favor `FA`:

1. **Code alignment**: the pipeline uses `FA_*` and `dFA_*` for firm instruments, `Z_*` and `Zlev_*` for sector instruments. Matching code names reduces cognitive overhead when moving between paper and code.
2. **Visual distinctness**: `FA^{ℓ}_{fmt}` is instantly recognizable as firm-level; `Z^{ℓ}_{jmt}` as sector-level. Using the same base letter `Z` with different subscripts is error-prone in dense algebra.
3. **Aggregation narrative**: distinct symbols make it natural to write the aggregation identity as `Z^{ℓ}_{jmt} = Σ_f (L_{f,τ}/N_{jm,τ}) · FA^{ℓ}_{fmt}`, showing explicitly how the macro object is a weighted sum of micro objects.

### Why Keep `ΔZ` (with Footnote) Rather Than Introducing `Z^{Δ}` or `\tilde{Z}`

The `Δ` operator is standard in economics for "constructed from changes in the underlying shifter." Since the paper already defines `ΔAlign`, writing `ΔZ_{jmt} = Σ_p w_{jmp,τ} · ΔAlign^{ℓ}_{mpt}` is parallel to `Z_{jmt} = Σ_p w_{jmp,τ} · Align^{ℓ}_{mpt}`. The risk of confusion with first differences is handled by one clarifying footnote. Alternative notations (`\tilde{Z}`, `Z^{Δ}`) add complexity without improving clarity.

## Detailed Changes to `regs.tex`

### Change 1: Introduce `\newcommand` Definitions (Preamble)

Add after line 42 (`\newcommand{\Align}{\mathrm{Align}}`):

```latex
\newcommand{\FA}{\mathrm{FA}}
\newcommand{\EC}{\mathrm{EC}}
```

This ensures consistent typesetting of the firm-alignment symbol.

### Change 2: Rewrite Firm-Level Exposure (§ Firm-level, Levels → Baseline party exposure)

**Current** (lines 80–85): Defines `w_{fmpt}` with municipality subscript.

**Proposed**: Replace with:

```latex
\paragraph{Baseline party exposure.}
Given $L_{f,p,t}$ the number of owners of firm $f$ affiliated with party $p$ at time $t$,
and $L_{f,t}$ the total number of owners of firm $f$ at time $t$
(including owners not affiliated with any party),
we define the baseline exposure of firm $f$ to party $p$ as
\[
  \omega_{fp,\tau} \equiv \frac{L_{f,p,\tau}}{L_{f,\tau}},
  \qquad
  \sum_{p} \omega_{fp,\tau} \leq 1,
\]
where $\tau = \tau(t)$ denotes the pre-election baseline year for the electoral cycle
containing $t$.%
\footnote{Cycle-specific baselines: for mayors elected in year $e$,
$\tau = e - 1$ (pre-election year);
for governors/presidents, analogously.
As a robustness exercise we fix $\tau = 2002$ for all cycles.}
The residual $1 - \sum_p \omega_{fp,\tau}$ represents the share of owners
not affiliated with any political party;
these owners contribute zero to the instrument because they have no alignment shock.
```

Key changes:
- `ω` replaces `w` for firm exposure; municipality subscript dropped.
- `τ` defined with footnote giving the cycle map.
- "No party" treatment stated explicitly.
- Inequality `≤ 1` replaces the `= 1` with the unaffiliated residual spelled out.

### Change 3: Rewrite Firm-Level Instrument Definition

**Current** (lines 91–95): Uses `Z^{ℓ}_{fmt}`.

**Proposed**:

```latex
\paragraph{Firm-level shift-share instrument.}
Define the firm-level levels instrument as
\[
  \FA^{\ell}_{fmt} \equiv \sum_{p} \omega_{fp,\tau} \cdot \Align^{\ell}_{mpt}.
\]
This is the share of firm $f$'s owners who are affiliated with the party currently
holding office $\ell$ in the jurisdiction to which municipality $m$ belongs.
Because $\omega_{fp,\tau}$ does not vary across municipalities,
variation in $\FA^{\ell}_{fmt}$ across firms in the same $(m,t)$ cell
is driven purely by differences in owner-party composition.
```

### Change 4: Rewrite Firm-Level First Stage (Levels)

**Current** (lines 97–102): Uses `Z^{ℓ}_{fmt}` and mixed `λ_ℓ`/`κ_ℓ`.

**Proposed**:

```latex
\paragraph{Firm-level first stage (levels).}
We estimate
\[
  \text{IHS}(\text{BNDES}_{fmt}) = \sum_{\ell} \lambda_{\ell}\, \FA^{\ell}_{fmt}
  + \gamma_{f} + \alpha_{mt} + u_{fmt},
\]
where $\text{IHS}(\cdot) = \sinh^{-1}(\cdot)$ is the inverse hyperbolic sine,
$\gamma_f$ are firm fixed effects,
and $\alpha_{mt}$ are municipality$\times$year fixed effects.
Standard errors are two-way clustered by firm and municipality.
The primary specification uses analytic regression weights equal to firm employment
($n_{\text{employees},ft}$), so that $\lambda_\ell$ estimates the
employment-weighted average effect of alignment through office $\ell$
on firm-level BNDES credit.
An unweighted specification serves as robustness.
```

Key additions: IHS defined; employment weights as analytic regression weights; consistent `λ_ℓ`.

### Change 5: Rewrite Firm-Level Changes Instrument and First Stage

**Current** (lines 104–118).

**Proposed**:

```latex
\subsection{Firm-level, Changes}

\paragraph{Firm-level alignment turnover instrument.}
To exploit only the variation induced by political turnover, define
\[
  \Delta\FA^{\ell}_{fmt} \equiv \sum_{p} \omega_{fp,\tau} \cdot \Delta\Align^{\ell}_{mpt},
\]
where $\Delta\Align^{\ell}_{mpt} = \Align^{\ell}_{mpt} - \Align^{\ell}_{mp,t-1}$
is the alignment turnover shock.%
\footnote{$\Delta\FA^{\ell}_{fmt}$ is constructed from alignment turnover,
not as the first difference of $\FA^{\ell}_{fmt}$.
The two coincide only when baseline weights $\omega_{fp,\tau}$ are constant across
adjacent years---which holds within an electoral cycle but not at cycle boundaries.}

\paragraph{Firm-level first stage (changes).}
We estimate
\[
  \text{IHS}(\Delta\text{BNDES}_{fmt}) = \sum_{\ell} \lambda_{\ell}\,\Delta\FA^{\ell}_{fmt}
  + \gamma_{f} + \alpha_{mt} + u_{fmt},
\]
where $\Delta\text{BNDES}_{fmt} = \text{BNDES}_{fmt} - \text{BNDES}_{fm,t-1}$.
Fixed effects, clustering, and employment weighting follow the levels specification.
```

### Change 6: Rewrite Sector-Level Exposure (§ Sector-level, Levels → Baseline party exposure)

**Current** (lines 122–126): Duplicates firm-level paragraph verbatim.

**Proposed**: Replace with a definition that references the firm-level `ω` and shows aggregation:

```latex
\subsection{Sector-level, Levels}

\paragraph{Sector-level baseline exposure.}
For sector $j$ in municipality $m$, define the sector-party exposure weight as
\[
  w_{jmp,\tau} \equiv
  \frac{\sum_{f\in\mathcal{F}(j,m)} L_{f,p,\tau}}
       {\sum_{f\in\mathcal{F}(j,m)} L_{f,\tau}},
\]
where $\mathcal{F}(j,m)$ is the set of firms in sector $j$ of municipality $m$.
This is the owner-count-weighted average of firm-level exposures:
$w_{jmp,\tau} = \sum_{f\in\mathcal{F}(j,m)} (L_{f,\tau}/N_{jm,\tau})\,\omega_{fp,\tau}$,
where $N_{jm,\tau} = \sum_{f\in\mathcal{F}(j,m)} L_{f,\tau}$.
As at the firm level, unaffiliated owners enter the denominator but contribute zero
to the instrument; $\sum_p w_{jmp,\tau} \leq 1$.
```

Key changes:
- No duplication; references firm `ω` and shows how `w` aggregates it.
- Owner-count aggregation identity stated explicitly.
- "No party" treatment consistent with firm-level definition.

### Change 7: Sector-Level Levels Instrument and First Stage

**Current** (lines 128–140).

**Proposed**:

```latex
\paragraph{Levels instrument.}
The sector-level levels instrument is
\[
  Z^{\ell}_{jmt} \equiv \sum_{p} w_{jmp,\tau}\,\Align^{\ell}_{mpt}.
\]
Because $\Align^{\ell}_{mpt}$ is constant across sectors $j$ within $(m,t)$,
variation in $Z^{\ell}_{jmt}$ across sectors is driven by baseline exposure $w_{jmp,\tau}$.

\paragraph{First stage and exclusion.}
We estimate
\[
  s_{jmt} = \sum_{\ell} \lambda_{\ell}\, Z^{\ell}_{jmt}
  + \phi\,\EC_{jm,\tau} + \gamma_{jm} + \alpha_{jt} + u_{jmt},
\]
where $s_{jmt}$ is sector $j$'s share of BNDES credit in municipality $m$ at time $t$,
$\EC_{jm,\tau} \equiv \sum_p w_{jmp,\tau}$ is the sector-level exposure control
(measuring overall political connectedness of the sector-municipality cell),
$\gamma_{jm}$ are municipality$\times$sector fixed effects,
and $\alpha_{jt}$ are sector$\times$year fixed effects.
Standard errors are two-way clustered by municipality and sector.
```

Key changes:
- `s_{jmt}` used instead of verbose "BNDES Share".
- `φ` for exposure control coefficient (not `κ`, which was overloaded).
- `EC_{jm,τ}` explicitly defined as sector-level (not municipality-level).
- `λ_ℓ` consistent with firm specifications.
- FE written with `γ_{jm}` and `α_{jt}` (municipality×sector and sector×year).

### Change 8: Rewrite Aggregation Link

**Current** (lines 142–147): Incorrectly claims employment-weighted aggregation.

**Proposed**: Replace with:

```latex
\paragraph{Aggregation link.}
The sector-level instrument is the owner-count-weighted aggregation of firm-level instruments:
\[
  Z^{\ell}_{jmt}
  = \sum_{f\in\mathcal{F}(j,m)} \frac{L_{f,\tau}}{N_{jm,\tau}}\,\FA^{\ell}_{fmt}.
\]
The aggregation weight $L_{f,\tau}/N_{jm,\tau}$ is each firm's share of total owners
in the sector-municipality cell.
The employment-weighted counterpart---aggregating $\FA^{\ell}_{fmt}$ with weights
proportional to $n_{\text{employees},ft}$---produces a distinct object that corresponds
to the estimand of the employment-weighted firm first stage.
We verify this aggregation identity diagnostically by collapsing firm instruments
within each $(j,m,t)$ cell and confirming that the collapsed quantity satisfies
the instrument's support bounds.
```

Key changes:
- Owner-count aggregation stated correctly.
- Employment-weighted aggregation described as a related but distinct object.
- No false claim of equivalence; the diagnostic verification is mentioned.

### Change 9: Sector-Level Changes Instrument and First Stage

**Current** (lines 149–162).

**Proposed**:

```latex
\subsection{Sector-level, Changes}

\paragraph{Shift-share changes instrument.}
The sector-level changes instrument is
\[
  \Delta Z^{\ell}_{jmt} \equiv \sum_{p} w_{jmp,\tau}\,\Delta\Align^{\ell}_{mpt}.
\]
As with the firm-level analog $\Delta\FA$,
this is constructed from alignment turnover, not as the first difference of $Z^{\ell}_{jmt}$.%
\footnote{See footnote~\ref{fn:not-first-diff} above.
Within an electoral cycle, $w_{jmp,\tau}$ is constant and the two coincide.}

\paragraph{First stage.}
We estimate
\[
  \Delta s_{jmt} = \sum_{\ell} \lambda_{\ell}\,\Delta Z^{\ell}_{jmt}
  + \phi\,\EC_{jm,\tau} + \gamma_{jm} + \alpha_{jt} + u_{jmt}.
\]
Because shares sum to unity within each municipality-year
($\sum_j s_{jmt} = 1$), changes satisfy the simplex constraint
$\sum_j \Delta s_{jmt} = 0$ in municipality-years with positive total BNDES
in both $t$ and $t-1$.
We therefore drop the sector with the largest mean share ($j_0$)
and interpret coefficients relative to it.
```

Key changes:
- `Δs_{jmt}` used (matching code's `delta_s_mjt`).
- Footnote cross-reference for the "not first difference" clarification.
- Simplex constraint and dropped-sector rule stated.
- Consistent `λ_ℓ`, `φ`, `EC`, FE notation.

### Change 10: Add Remark on Two-Pipeline Design (After All Four Specifications)

Insert a new subsection after the four specifications:

```latex
\subsection{Two Complementary Pipelines}

The firm-level and sector-level specifications estimate related but distinct objects.
The sector pipeline uses owner-count exposure weights $w_{jmp,\tau}$
and does not employ analytic regression weights.
The firm pipeline uses firm-specific exposure $\omega_{fp,\tau}$
with employment-weighted regression estimation ($n_{\text{employees},ft}$ as weights),
so that the firm-level estimand is the employment-weighted average treatment effect.

The employment-weighted aggregation of firm instruments within a sector-municipality cell
recovers an employment-weighted sector-level instrument:
\[
  \sum_{f\in\mathcal{F}(j,m)}
    \frac{n_{\text{employees},ft}}{\sum_{f'} n_{\text{employees},f't}}\,
    \FA^{\ell}_{fmt}
  = \sum_p w^{\text{emp}}_{jmp,\tau}\,\Align^{\ell}_{mpt},
\]
where $w^{\text{emp}}_{jmp,\tau}
= \sum_f n_{\text{employees},ft} \cdot (\omega_{fp,\tau})
  / \sum_f n_{\text{employees},ft}$
is the employment-weighted exposure share.
This quantity differs from the owner-count instrument $Z^{\ell}_{jmt}$
whenever the employment distribution across firms differs from the owner-count distribution.
Both are valid shift-share instruments exploiting the same underlying political variation;
we present them as complementary views of the sector-level first stage.
```

## Acceptance Criteria

### Notation Consistency
- [x] `FA^{ℓ}_{fmt}` and `ΔFA^{ℓ}_{fmt}` used consistently for firm instruments; `Z^{ℓ}_{jmt}` and `ΔZ^{ℓ}_{jmt}` for sector instruments
- [x] `ω_{fp,τ}` used for firm exposure (no municipality subscript); `w_{jmp,τ}` for sector exposure
- [x] `λ_ℓ` used for all first-stage instrument coefficients; `φ` for exposure control
- [x] `EC_{jm,τ}` defined as sector-level exposure control with explicit formula
- [x] `τ(t)` defined once with cycle map in footnote; 2002-fixed variant mentioned as robustness

### Factual Correctness
- [x] Aggregation link states owner-count identity (not employment-weighted)
- [x] Employment-weighted aggregation presented as a separate diagnostic/complementary object
- [x] "No party" treatment described: denominator includes, numerator excludes, zero contribution to instrument
- [x] Simplex constraint and dropped-sector rule stated in sector changes specification
- [x] Footnote clarifies `ΔZ` / `ΔFA` are not first differences of the levels instruments

### Structural Improvements
- [x] Baseline exposure paragraph appears once (firm section); sector section references and aggregates
- [x] Employment weighting as regression weights stated in firm first-stage paragraph
- [x] New subsection on two-pipeline design connects firm and sector specifications
- [x] `\newcommand{\FA}` and `\newcommand{\EC}` added to preamble

### Code–Paper Alignment
- [x] Paper notation maps to code names: `FA_*` ↔ `FA^{ℓ}`, `dFA_*` ↔ `ΔFA^{ℓ}`, `Z_*` ↔ `Z^{ℓ}`, `Zlev_*` ↔ `Z^{ℓ}` (levels context), `exposure_control_*` ↔ `EC`
- [x] Design decisions in the implementation plan (employment weighting, complementary pipelines, sector-level exposure control) are reflected in the paper

## Decision Points Requiring Author Input

Before implementing these changes, three decisions need to be made:

1. **Coalition vs. party alignment**: The code constructs both `_coalition` and `_party` variants. The paper currently presents only one generic `ℓ`. Should the paper formalize coalition as primary and party as robustness? Or keep `ℓ` generic?

2. **IHS interpretation**: Should the paper include a brief remark on interpreting IHS coefficients at small values (where `asinh(x) ≈ x` rather than `log(x)`)? This affects the quantitative interpretation of `λ_ℓ`.

3. **Second-stage preview**: The current paper stops at first stages. Should this revision add a forward reference to the second stage (scalar 2SLS via HHI, vector 2SLS)? Or keep the paper focused on the first-stage notation for now?

## Sources

- **Origin plan**: [docs/plans/2026-03-10-feat-four-iv-specifications-unified-pipeline-plan.md](docs/plans/2026-03-10-feat-four-iv-specifications-unified-pipeline-plan.md) — design decisions on employment weighting (lines 32–50), two-pipeline architecture (lines 52–59), aggregation identity (lines 38–42)
- **Current paper**: [paper/regs.tex](paper/regs.tex) — all four specifications and aggregation link
- **Audit findings**: [docs/plans/2026-03-10-phase-minus-1-audit-findings.md](docs/plans/2026-03-10-phase-minus-1-audit-findings.md) — exposure control mismatch (municipality vs. sector level)
- **Code references**: script 31 (denominator logic, lines 347–408, 516–523), script 34 (instrument construction), script 51 (regression specifications)
