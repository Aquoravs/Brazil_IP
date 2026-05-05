---
title: Research State
status: active
date: 2026-04-28
purpose: Single working reference to current design decisions, findings, and open questions
---

# Research State

This file is the **current working understanding** of the Brazil IP project. It is not a paper section. Authoritative sources for fixed material live elsewhere; this file references them rather than duplicating them.

| For… | Read… |
|---|---|
| Project overview, file layout, variable dictionary | [`README.md`](../README.md) |
| AI-agent-facing config, commands, conventions | [`INSTRUCTIONS.md`](../INSTRUCTIONS.md) |
| Formal specification of firm + sector first stages | [`paper/regs.tex`](../paper/regs.tex) (current draft of Section 5; **not yet `\input{}`-ed by `main.tex`**) |
| Aggregation equivalence formal review | [`docs/methodology_notes/proposition2_aggregation_review.tex`](methodology_notes/proposition2_aggregation_review.tex) |
| Proposition 2 condition explainer | [`docs/methodology_notes/conditions_C3_C5_C6_explained.tex`](methodology_notes/conditions_C3_C5_C6_explained.tex) |
| Numeric Prop 2 verification (B vs A samples, exact identity) | [`docs/methodology_notes/proposition2_failure_note.tex`](methodology_notes/proposition2_failure_note.tex) |
| Comments and resolution status | [`logs/referee_response_tracker.md`](../logs/referee_response_tracker.md) |
| Implementation conventions and findings extracted from session logs | [`logs/knowledge.md`](../logs/knowledge.md) |
| Historical brainstorms, superseded roadmaps | [`docs/archive/`](archive/) |

---

## 1. Current focus

**Policy evaluation via Anderson-Rubin (AR) test.** The previous firm-level and sector-level first-stage exploration was preparatory; it produced the spec engines, the taxonomies, and the F-stat patterns documented below, and clarified that some sector classifications might be more appropriate for the test.

BNDES private loans can influence municipal GDP through two distinct channels: (1) a **composition channel** — the allocation of credit across sectors within a municipality (the channel of interest), and (2) a **volume channel** — the overall amount of credit flowing to firms in a municipality. The objective is to isolate the composition (allocation) effect by sweeping out the total volume effect. Both sets of variables are endogenous, which raises the question of how to cleanly identify the composition channel when both sector-share variables and aggregate municipality-level disbursements are endogenous. Four approaches are under consideration: pure AR (OLS on both), partial IV (instrument sector shares only), full IV (instrument both), and mixed (OLS for shares, IV for total). See blueprint A10.

The relevant inferential object is the AR-style test of $H_0: \beta = 0$ ("BNDES sectoral reallocation has no GDP effect within a municipality"). The four-phase AR strategy is the active research agenda:

1. **Baseline**: regress $\log(\text{GDP}_{mt})$ on instruments with muni FE + year FE (± total muni employment), clustered AR test.
2. **Mechanism validation**: placebo on alternative channels (transfers, procurement); Rotemberg-weight diagnostics.
3. **Many-instruments scaling**: Ridge-Regularized Jackknifed AR (RJAR) once the instrument set grows past 20 sectors; conditional subvector AR for testing one sector while treating others as nuisance.
4. **Stress tests**: Fractionally Resampled AR (FAR) for near-exogeneity; Cluster Jackknife AR for the 15-year panel's serial correlation.

Source: [`docs/archive/brainstorms/2026-04-21-ar-test-ideas.md`](archive/brainstorms/2026-04-21-ar-test-ideas.md). Tracked as advisor comments **C4** (muni-by-muni AR) and **C8** (penalized methods) in [`logs/referee_response_tracker.md`](../logs/referee_response_tracker.md).

---

## 2. Pipeline state

55 R scripts in `scripts/R/`, stages 11–54, all operational. Spec engines in 51 (firm, 8-dim), 52 (aggregated firm→sector, 9-dim), 53 (sector, 6-dim). Second stage 54 has reduced form, scalar 2SLS, vector 2SLS — extends naturally to AR-style inference. Stage map: see [`README.md`](../README.md) → "Directory Structure → scripts/R/" and [`INSTRUCTIONS.md`](../INSTRUCTIONS.md) → "Pipeline Architecture".

---

## 3. Active design decisions

Numbered for cross-reference. Source for each is the location where the decision is operationalized in code or in `regs.tex`.

| # | Decision | Source |
|---|---|---|
| D1 | Sector defined consistently from RAIS CNAE section, not BNDES project CNAE | script 22 → 35; `regs.tex` §"Sector-level baseline exposure" |
| D2 | Levels instruments (`FA`, `Z`) spread across full 4-year electoral term. Changes instruments (`dFA`, `dZ`) constructed as $\omega^\ell_{fp,t} \cdot \Delta\text{Align}^\ell_{mpt}$ (current-cycle baseline × alignment turnover) — non-zero only at inauguration years. Coincides with the literal first difference of levels within a term, but differs at cycle boundaries where naive first-differencing would mechanically pick up the baseline-window update | script 32, 34, 36; `regs.tex` footnote labelled `not-first-diff` |
| D3 | Baseline weights pooled over 4-year pre-election window `[e-4, e-1] ∩ [2002, 2017]`; cycle-specific = primary, 2002-fixed = robustness | script 33; `regs.tex` cycle-specific footnote |
| D4 | 2003 gov/pres cycle dropped (no pre-election data) | script 32 |
| D5 | `s_mjt` zero-fill OK on RAIS skeleton; `delta_s_mjt` **never** from NA-to-zero, only from observed subtraction | script 35; `audit_41_muni_panel.R`; `INSTRUCTIONS.md` data notes |
| D6 | Drop sector with largest mean share for vector $\Delta s$ regressions (simplex constraint) | script 41 / 54 |
| D7 | Employment weighting enters firm regression via `bl_n_employees` (pre-election baseline mean), **not** contemporaneous; redefined 2026-04-04 | script 42, 51; session log `2026-04-04_max-binary-baseline-employment` |
| D8 | `binary_fp` baseline = `max(1(L_fp,s > 0))` over pre-election window (any-year indicator), not fraction-of-years | script 36; same session log |
| D9 | `exposure_control` ($\sum_p w^\ell_{jmp,t}$) included in primary sector spec; tier-specific variants emitted; bounded above by 1 (pooled-count) but exposure-control-binary may exceed 1 | scripts 31/34, `regs.tex` exposure-control footnote |
| D10 | **How to handle total BNDES in the second stage is open (blueprint A10).** The composition channel (sector allocation) and volume channel (aggregate muni disbursements) are both endogenous. Four approaches are under consideration: (1) Pure AR — OLS on both; (2) Partial IV — instrument sector shares only; (3) Full IV — instrument both using sum of sector instruments; (4) Mixed — OLS for shares, IV for total. The earlier "do not include total BNDES" framing was too restrictive — the volume control is needed to isolate the composition channel. | `docs/archive/doubts.md` Issue 9; blueprint A10; 2026-04-30 meeting notes |
| D11 | Multi-municipality firms (2% of firm-years, 30% of employment) handled as robustness via `is_multi_muni == 0` subsample | script 42; `regs.tex` "Multi-Municipality Firm Robustness" |

---

## 4. Sector taxonomies in play

Five classifications run in parallel through the spec engines. None has been declared "primary" for the AR test yet — choice depends on AR phase.

| Variable | Granularity | Built by | Use case |
|---|---|---|---|
| `cnae_section` | 21 CNAE sections (A–U) | upstream | Standard granularity; balanced panel skeleton |
| `custom_sector` (was `sector_group`) | 11 groups (Ag, Mi, CL, CH, CA, UCo, Tr, Tp, MS, PSO, XX) | script 30 | Manufacturing 3-way split; matches BNDES departmental structure |
| `bndes_sector` (was `setor_bndes`) | 4 macros (Agropecuária, Indústria, Infraestrutura, Comércio e Serviços) | script 30b | Coarsest grouping; AR-test Phase 1 candidate |
| `size_bin` | 3 national employment terciles (recomputed each election cycle) | script 30c | Within-sector size heterogeneity; not a sector classification per se |
| `bndes_sector_size_bin` | 4 macros × 3 terciles = 12 categories | script 30d | Tercile-within-macro; addresses advisor comment C3 |

Renames adopted 2026-04-06: `setor_bndes → bndes_sector`, `sector_group → custom_sector`. Older notes still use the original names.

---

## 5. Spec engine dimensions

### Script 51 — Firm first stage (8-dim)

`margin × exposure × weighting × baseline × alignment × time_variation × sample × family`

Reference panel sample size: 44,181,405 firm-muni-year rows (cycle-specific baseline).

### Script 52 — Aggregated firm → sector (9-dim)

`outcome × baseline × alignment × FE × exposure_control × sector_var × aggregation × regression_weight × exposure`

**Pairing rule** (aggregation ↔ regression weight): `unweighted regression ↔ equal_firm aggregation`; `emp_weighted ↔ employment aggregation`. This makes the sector-level coefficient a faithful aggregation of the firm-level one under the matching weighting scheme.

Outcomes: `bndes_share`, `bndes_extensive` (= "Share Receiving BNDES Loan", relabeled 2026-04-07), `log_employment`, `employment_share`.

### Script 53 — Sector first stage (6-dim)

`time_variation × instrument_weight × baseline × alignment × FE × exposure_control`

Instrument-weight variants (per 2026-03-24 brainstorm):
- `owner_count` — $w_{jmp} = \sum_f L_{fp,0} / \sum_f L_{f,0}$ (each owner an equal political channel)
- `employment` — employment-weighted firm exposure (BNDES responds to economic size)
- `equal_firm` — simple firm average (each firm an independent access point)
- `binary` — fraction of sector's firms with any affiliated owner (extensive margin)

### Common — Standard errors and FE

| Level | Default FE | Default clustering | Robustness FE |
|---|---|---|---|
| Firm | `firm_id + muni_id^year` | firm + muni | — |
| Sector A (Panel A) | `muni_id^cnae_section + cnae_section^year` | muni + sector | `muni_id^cnae_section + muni_id^year` |
| Muni B (Panel B) | `muni_id + year` | muni | — |

---

## 6. Findings from preparatory work

These are working findings; numerical references are in `logs/knowledge.md`.

- **Firm-level extensive margin** has a real first stage. Coalition · unweighted · pooled-count is strongest (cycle-specific F up to 103). 2002-fixed and cycle-specific both viable. Source: 2026-04-05 first-stage talk audit.
- **Firm-level intensive margin** has no viable first stage (max F ≈ 6 across all 32 specs).
- **Employment outcomes** as LHS produce very high F-stats (up to 265 for `employment_log`). These are **reduced-form direct effects**, not BNDES-mediated, and raise an exclusion-restriction concern if used as IV.
- **Employment-weighted always weaker** than unweighted across outcomes and baselines.
- **Sector-share LHS** (`delta_s_mjt`) attenuates the firm-level signal because cross-sector cancellation in the simplex constraint absorbs much of the within-municipality reallocation. Confirmed by aggregated-firm spec engine in script 52.
- **Within-cell variation dominates between-cell variation** in the firm regression (91–94% of the identifying $X^2$ sum is within-cell). Cell-mean regressions therefore differ materially from the firm regression unless the exact firm sufficient statistics are aggregated. Source: `proposition2_failure_note.tex`. Implication: cell-level second stage cannot recover firm-level $\lambda$ exactly without conditions C1–C6, and **C6 fails on real data** because firms in the same $(j,m,t)$ cell have heterogeneous owner-party exposures.

---

## 7. Validation invariants

Active checks in `audit_3_instruments.R` and `audit_41_muni_panel.R`:

1. $\sum_j s_{mjt} = 1$ in muni-years with positive total BNDES.
2. $\sum_j \Delta s_{mjt} = 0$ in interior positive-total transitions; ±1 valid only at entry/exit transitions.
3. Levels instruments in $[0, 1]$; turnover instruments in $[-1, 1]$.
4. Exposure control varies across sectors within muni-year (not muni-only duplicated).
5. No zero-imputation of undefined `delta_s_*`.

Source: extracted from `docs/archive/shift_share.md` §10.

---

## 8. Open questions and decision points

Active items only. Closed items live in their archive sources.

### 8.1 AR-test design questions (current focus)

- **C4** Pooled AR — `log(GDP_real) ~ instruments | muni_FE + year_FE` with/without total employment. Choice of instrument set: which sector taxonomy? My read: start with `bndes_sector` (4 macros) for Phase 1.
- **C4** Muni-by-muni AR — feasibility unclear (~16 years per muni; 5,570 munis); compute % rejecting $H_0$ at standard levels. Needs a script in `explorations/anderson_rubin/`.
- **C8** Penalized methods — when sector × tier × interaction grows the instrument count past ~20–30, ridge / LASSO / post-LASSO become relevant. Methodological memo deferred until C4 results are in.
- AR Phase 2 mechanism placebo — transfers data is already cached at `data/processed/transfers_ibge.qs2` (96.3% match rate), per audit. Procurement data not yet sourced.

### 8.2 Data integration decisions awaiting advisor input

- **C6** Alternative employment / production-factor data — RAIS unexploited variables (education, age, wages), INEP Censo Escolar, PPM + PAM all immediately actionable. PNAD infeasible (no muni-level public microdata). Awaiting advisor decision on what to ingest. Memo: [`logs/data_exploration/c6_employment_sources.md`](../logs/data_exploration/c6_employment_sources.md).
- **C7** Local deflators — no full-coverage muni deflator exists for 2002–2017. Metro IPCA (~13 metros, ~55% of GDP) is the only off-the-shelf option; wage-residual proxy from RAIS is the tractable full-coverage alternative. Awaiting advisor decision. Memo: [`logs/data_exploration/c7_local_deflators.md`](../logs/data_exploration/c7_local_deflators.md).

### 8.3 Paper integration

- `paper/regs.tex` is the current authoritative draft of the Specifications section but is **not** included from `main.tex`. The §5 of `main.tex` is older and contains a placeholder section ("Connection to three steps thing (deprecated)"). Decide when to merge.
- `docs/methodology_notes/proposition2_aggregation_review.tex` — eventual appendix material or kept as internal note. Currently classified as internal note.

---

## 9. What is **not** in this file

- Detailed pipeline script behaviors → `scripts/R/<stage>/<script>.R` and `INSTRUCTIONS.md` → "Pipeline Architecture".
- Variable definitions → `README.md` → "Variable Dictionary".
- Full LaTeX preamble standards → `.claude/rules/working-paper-format.md`.
- Plans for individual implementation tasks → `logs/plans/archive/`.
- Specific session implementation notes → `logs/session_logs/archive/`.
