---
title: Research State
status: active
date: 2026-05-05
purpose: Single working reference to current design decisions, findings, and open questions
---

# Research State

This file is the **current working understanding** of the Brazil IP project. It is not a paper section. Authoritative sources for fixed material live elsewhere; this file references them rather than duplicating them.

| For... | Read... |
|---|---|
| Project overview, file layout, variable dictionary | [`README.md`](../README.md) |
| AI-agent-facing config, commands, conventions | [`INSTRUCTIONS.md`](../INSTRUCTIONS.md) |
| Current argument map, load-bearing claims, and next action | [`docs/PROJECT_BLUEPRINT.md`](PROJECT_BLUEPRINT.md) |
| Formal specification of firm + sector first stages | [`paper/regs.tex`](../paper/regs.tex) (current draft of Section 5; **not yet `\input{}`-ed by `main.tex`**) |
| Aggregation equivalence formal review | [`docs/methodology_notes/proposition2_aggregation_review.tex`](methodology_notes/proposition2_aggregation_review.tex) |
| Proposition 2 condition explainer | [`docs/methodology_notes/conditions_C3_C5_C6_explained.tex`](methodology_notes/conditions_C3_C5_C6_explained.tex) |
| Numeric Prop 2 verification (B vs A samples, exact identity) | [`docs/methodology_notes/proposition2_failure_note.tex`](methodology_notes/proposition2_failure_note.tex) |
| Comments and resolution status | [`logs/referee_response_tracker.md`](../logs/referee_response_tracker.md) |
| Implementation conventions and findings extracted from session logs | [`logs/knowledge.md`](../logs/knowledge.md) |
| Historical brainstorms, superseded roadmaps | [`docs/archive/`](archive/) |

---

## 1. Current focus

**Policy evaluation via Anderson-Rubin (AR) test.** The previous firm-level and sector-level first-stage exploration was preparatory; it produced the spec engines, the taxonomies, and the F-stat patterns documented below. The current exploration has moved past the aggregation-margin existence question: F0 is confirmed, F1 is confirmed, and the production aggregation margin for the AR-test SSIV is `policy_block_active x S3`.

BNDES private loans can influence municipal GDP through two distinct channels: (1) a **composition channel**, the allocation of credit across sectors within a municipality (the channel of interest), and (2) a **volume channel**, the overall amount of credit flowing to firms in a municipality. The objective is to isolate the composition effect by sweeping out the total volume effect. Both sets of variables are endogenous, which raises the question of how to cleanly identify the composition channel when both sector-share variables and aggregate municipality-level disbursements are endogenous. Four approaches are under consideration: pure AR (OLS on both), partial IV (instrument sector shares only), full IV (instrument both), and mixed (OLS for shares, IV for total). See blueprint A10.

The relevant inferential object is the AR-style test of $H_0: \beta = 0$ ("BNDES sectoral reallocation has no GDP effect within a municipality"). The four-phase AR strategy is the active research agenda:

1. **Baseline**: regress $\log(\text{GDP}_{mt})$ on instruments with muni FE + year FE (+/- total muni employment), clustered AR test.
2. **Mechanism validation**: placebo on alternative channels (transfers, procurement); Rotemberg-weight diagnostics.
3. **Many-instruments scaling**: Ridge-Regularized Jackknifed AR (RJAR) once the instrument set grows past 20 sectors; conditional subvector AR for testing one sector while treating others as nuisance.
4. **Stress tests**: Fractionally Resampled AR (FAR) for near-exogeneity; Cluster Jackknife AR for the 15-year panel's serial correlation.

Current bottleneck: **F2**, the first-stage relevance of the municipality-level shock at the chosen production margin. F3 exclusion/placebo work is partial. F4 denominator and weight robustness remains paused until F2 is tested at the new margin.

Source: [`docs/archive/brainstorms/2026-04-21-ar-test-ideas.md`](archive/brainstorms/2026-04-21-ar-test-ideas.md). Current argument-map status is in [`docs/PROJECT_BLUEPRINT.md`](PROJECT_BLUEPRINT.md). Tracked as advisor comments **C4** (pooled AR) and **C8** (penalized methods) in [`logs/referee_response_tracker.md`](../logs/referee_response_tracker.md).

---

## 2. Pipeline state

55 R scripts in `scripts/R/`, stages 11-54, all operational. Spec engines in 51 (firm, 8-dim), 52 (aggregated firm-to-sector, 9-dim), 53 (sector, 6-dim). Second stage 54 has reduced form, scalar 2SLS, vector 2SLS, and extends naturally to AR-style inference. Stage map: see [`README.md`](../README.md) -> "Directory Structure -> scripts/R/" and [`INSTRUCTIONS.md`](../INSTRUCTIONS.md) -> "Pipeline Architecture".

Pipeline caveat as of 2026-05-05: the existing pipeline does **not yet fully implement the chosen production margin** `policy_block_active x S3`. Existing scripts support `policy_block`, older `size_bin` variants, and older sector-size crosswalks, but the production crosswalk is still a follow-on task. Expected implementation path:

1. Create a successor to `30c` / `30d`, likely `scripts/R/3_instruments/30f_build_policy_block_size_mapping.R`, producing `policy_block_active x S3`.
2. Wire the new crosswalk through scripts `31`, `34`, and `41`.
3. Re-run script `53` at the new margin to test F2.

---

## 3. Active design decisions

Numbered for cross-reference. Source for each is the location where the decision is operationalized in code, notes, or `regs.tex`.

| # | Decision | Source |
|---|---|---|
| D1 | Sector defined consistently from RAIS CNAE section, not BNDES project CNAE | script 22 -> 35; `regs.tex` section "Sector-level baseline exposure" |
| D2 | Levels instruments (`FA`, `Z`) spread across full 4-year electoral term. Changes instruments (`dFA`, `dZ`) constructed as $\omega^\ell_{fp,t} \cdot \Delta\text{Align}^\ell_{mpt}$ (current-cycle baseline x alignment turnover), non-zero only at inauguration years. Coincides with the literal first difference of levels within a term, but differs at cycle boundaries where naive first-differencing would mechanically pick up the baseline-window update | script 32, 34, 36; `regs.tex` footnote labelled `not-first-diff` |
| D3 | Baseline weights pooled over 4-year pre-election window `[e-4, e-1]` intersected with `[2002, 2017]`; cycle-specific = primary, 2002-fixed = robustness | script 33; `regs.tex` cycle-specific footnote |
| D4 | 2003 gov/pres cycle dropped (no pre-election data) | script 32 |
| D5 | `s_mjt` zero-fill OK on RAIS skeleton; `delta_s_mjt` **never** from NA-to-zero, only from observed subtraction | script 35; `audit_41_muni_panel.R`; `INSTRUCTIONS.md` data notes |
| D6 | Drop sector with largest mean share for vector `delta_s` regressions (simplex constraint) | script 41 / 54 |
| D7 | Employment weighting enters firm regression via `bl_n_employees` (pre-election baseline mean), **not** contemporaneous; redefined 2026-04-04 | script 42, 51; session log `2026-04-04_max-binary-baseline-employment` |
| D8 | `binary_fp` baseline = `max(1(L_fp,s > 0))` over pre-election window (any-year indicator), not fraction-of-years | script 36; same session log |
| D9 | `exposure_control` ($\sum_p w^\ell_{jmp,t}$) included in primary sector spec; tier-specific variants emitted; bounded above by 1 (pooled-count) but exposure-control-binary may exceed 1 | scripts 31/34, `regs.tex` exposure-control footnote |
| D10 | **How to handle total BNDES in the second stage is open (blueprint A10).** The composition channel (sector allocation) and volume channel (aggregate muni disbursements) are both endogenous. Four approaches are under consideration: (1) Pure AR, OLS on both; (2) Partial IV, instrument sector shares only; (3) Full IV, instrument both using sum of sector instruments; (4) Mixed, OLS for shares, IV for total. The earlier "do not include total BNDES" framing was too restrictive; the volume control is needed to isolate the composition channel. | `docs/archive/doubts.md` Issue 9; blueprint A10; 2026-04-30 meeting notes |
| D11 | Multi-municipality firms (2% of firm-years, 30% of employment) handled as robustness via `is_multi_muni == 0` subsample | script 42; `regs.tex` "Multi-Municipality Firm Robustness" |
| D12 | XX sectors (K, O, T, U) excluded from the active policy-block treatment set. K is the key case: BNDES is a financial intermediary, so finance-sector firms re-lend rather than absorb credit as final users. | `docs/PROJECT_BLUEPRINT.md` D12; CNAE coverage audit outputs |
| D14 | Aggregation margins must be **firm-side classifiers defined for every firm in RAIS**, including non-borrowers. Loan-side (`bndes_product`) and purpose-side (PSI eligibility) classifiers are inadmissible for muni-level SSIV shares. | `docs/PROJECT_BLUEPRINT.md` D14; `logs/strategy/bndes_allocation_logic.md` |
| D16 | Production aggregation margin for the AR-test SSIV is `policy_block_active x S3`: active policy blocks Agro / Ind / Infra / Serv crossed with S3 size bins MPME / Media / Grande. Secondary robustness: `cnae_section x S3`. | `docs/PROJECT_BLUEPRINT.md` D16; `explorations/anderson_rubin/diagnostics/output/f1_combined_report.md` |
| D17 | Standalone `size_bin` is admissible as an aggregation margin. Absolute employee-count thresholds are preferred over tertiles: S3 = MPME 0-49 / Media 50-499 / Grande 500+. | `docs/PROJECT_BLUEPRINT.md` D17; `logs/strategy/bndes_allocation_logic.md` |
| D18 | The old firm-CNAE vs. project-CNAE consistency issue is retired from the identification chain. Firm-CNAE is the operative classifier because it is defined for all firms; project-CNAE is descriptive only. | `docs/PROJECT_BLUEPRINT.md` D18 |
| D19 | Size-classifier labels are S2/S3/S4, not A2/A3/A4, to avoid collision with open-angle IDs. | `docs/PROJECT_BLUEPRINT.md` D19 |

---

## 4. Sector taxonomies in play

The AR-test taxonomy choice is now settled for production, while older classifications remain useful for comparison, robustness, or legacy spec-engine output.

| Variable | Granularity | Built by | Use case |
|---|---|---|---|
| `cnae_section` | 21 CNAE sections (A-U) | upstream | Standard granularity; balanced panel skeleton |
| `custom_sector` (was `sector_group`) | 11 groups (Ag, Mi, CL, CH, CA, UCo, Tr, Tp, MS, PSO, XX) | script 30 | Manufacturing 3-way split; matches BNDES departmental structure |
| `policy_block_active` | 4 active BNDES blocks: Agro, Ind, Infra, Serv; XX excluded | script 30e | Production sector dimension for the AR-test SSIV |
| `S3` | 3 absolute size bins: MPME 0-49, Media 50-499, Grande 500+ employees | follow-on production crosswalk pending | Production size dimension; approximates BNDES porte categories using RAIS employment |
| `policy_block_active x S3` | 12 active bins | follow-on production crosswalk pending | **Primary AR production margin** |
| `cnae_section x S3` | 51 active bins | follow-on / robustness wiring pending | Secondary robustness margin; higher within variation but thinner cells |
| standalone `size_bin` | S3 or S4 size bins without sector crossing | diagnostics completed; older script 30c uses terciles | Admissible and supported, but not the preferred production margin |
| older `bndes_sector_size_bin` | 4 macros x 3 terciles | script 30d | Legacy / exploratory variant; not the preferred institutional definition |

Renames adopted 2026-04-06: `setor_bndes -> bndes_sector`, `sector_group -> custom_sector`. Size labels adopted 2026-05-05: S2/S3/S4 replace the temporary A2/A3/A4 labels in diagnostics. Older notes still use the original names.

---

## 5. Spec engine dimensions

### Script 51: Firm first stage (8-dim)

`margin x exposure x weighting x baseline x alignment x time_variation x sample x family`

Reference panel sample size: 44,181,405 firm-muni-year rows (cycle-specific baseline).

### Script 52: Aggregated firm to sector (9-dim)

`outcome x baseline x alignment x FE x exposure_control x sector_var x aggregation x regression_weight x exposure`

**Pairing rule** (aggregation to regression weight): `unweighted regression` pairs with `equal_firm aggregation`; `emp_weighted` pairs with `employment aggregation`. This makes the sector-level coefficient a faithful aggregation of the firm-level one under the matching weighting scheme.

Outcomes: `bndes_share`, `bndes_extensive` (= "Share Receiving BNDES Loan", relabeled 2026-04-07), `log_employment`, `employment_share`.

### Script 53: Sector first stage (6-dim)

`time_variation x instrument_weight x baseline x alignment x FE x exposure_control`

Instrument-weight variants (per 2026-03-24 brainstorm):
- `owner_count`: $w_{jmp} = \sum_f L_{fp,0} / \sum_f L_{f,0}$ (each owner an equal political channel)
- `employment`: employment-weighted firm exposure (BNDES responds to economic size)
- `equal_firm`: simple firm average (each firm an independent access point)
- `binary`: fraction of sector's firms with any affiliated owner (extensive margin)

### Common: Standard errors and FE

| Level | Default FE | Default clustering | Robustness FE |
|---|---|---|---|
| Firm | `firm_id + muni_id^year` | firm + muni | - |
| Sector A (Panel A) | `muni_id^cnae_section + cnae_section^year` | muni + sector | `muni_id^cnae_section + muni_id^year` |
| Muni B (Panel B) | `muni_id + year` | muni | - |

---

## 6. Findings from preparatory work

These are working findings; numerical references are in `logs/knowledge.md`, `docs/PROJECT_BLUEPRINT.md`, and the AR diagnostic reports.

- **Firm-level extensive margin** has a real first stage. Coalition, unweighted, pooled-count is strongest (cycle-specific F up to 103). 2002-fixed and cycle-specific both viable. Source: 2026-04-05 first-stage talk audit.
- **Firm-level intensive margin** has no viable first stage (max F around 6 across all 32 specs).
- **Employment outcomes** as LHS produce very high F-stats (up to 265 for `employment_log`). These are **reduced-form direct effects**, not BNDES-mediated, and raise an exclusion-restriction concern if used as IV.
- **Employment-weighted always weaker** than unweighted across outcomes and baselines.
- **Sector-share LHS** (`delta_s_mjt`) attenuates the firm-level signal because cross-sector cancellation in the simplex constraint absorbs much of the within-municipality reallocation. Confirmed by aggregated-firm spec engine in script 52.
- **Within-cell variation dominates between-cell variation** in the firm regression (91-94% of the identifying $X^2$ sum is within-cell). Cell-mean regressions therefore differ materially from the firm regression unless the exact firm sufficient statistics are aggregated. Source: `proposition2_failure_note.tex`. Implication: cell-level second stage cannot recover firm-level $\lambda$ exactly without conditions C1-C6, and **C6 fails on real data** because firms in the same `(j,m,t)` cell have heterogeneous owner-party exposures.
- **F1 is confirmed on sector-only margins.** Round 1 supported `cnae_section`, `policy_block`, and `policy_block_active` under both V1 active-only and V2 full-economy denominators. Denominator choice does not change the F1 verdict. Source: `within_muni_variation_report.md`; blueprint D15.
- **F1 is confirmed on size and sector-size margins.** Round 2 selected `policy_block_active x S3` as the production margin: 12 active bins, mean `share_within = 0.642` under V1, and 3/12 supported bins. `cnae_section x S3` has higher mean `share_within = 0.769` but much thinner cells (3/51 supported bins), so it is secondary robustness. Source: `f1_combined_report.md`; blueprint D16.
- **Standalone size is admissible and supported but not primary.** Standalone S3 and S4 pass the F1 diagnostic, but they collapse sector entirely. They are useful robustness candidates, while `policy_block_active x S3` better matches the institutional mechanism. Source: `f1_standalone_size_report.md`; blueprint D17.
- **Known caveat for size margins:** 51% of BNDES loans in the size-alignment diagnostic match no RAIS firm-year row; unmatched stated Micro/Pequena loans are imputed to the small-size bin under the T3 rule, while unmatched stated Media/Grande loans are dropped. This should be surfaced in the data appendix.

---

## 7. Validation invariants

Active checks in `audit_3_instruments.R` and `audit_41_muni_panel.R`:

1. $\sum_j s_{mjt} = 1$ in muni-years with positive total BNDES.
2. $\sum_j \Delta s_{mjt} = 0$ in interior positive-total transitions; +/-1 valid only at entry/exit transitions.
3. Levels instruments in `[0, 1]`; turnover instruments in `[-1, 1]`.
4. Exposure control varies across sectors within muni-year (not muni-only duplicated).
5. No zero-imputation of undefined `delta_s_*`.

Source: extracted from `docs/archive/shift_share.md` section 10.

---

## 8. Open questions and decision points

Active items only. Closed items live in their archive sources.

### 8.1 AR-test design questions (current focus)

- **C4** Pooled AR: start from `policy_block_active x S3` once the production crosswalk is wired and script 53 confirms F2 relevance. Keep `policy_block_active` alone and `cnae_section x S3` as comparison / robustness margins.
- **C4** Muni-by-muni AR: low priority / likely infeasible with roughly 16 years per municipality and 5,570 municipalities; pooled AR remains the active path.
- **C8** Penalized methods: relevant when the instrument count grows past roughly 20-30. `policy_block_active x S3` has 12 bins, so many-instrument methods are not first-order for the primary production margin; they matter more for `cnae_section x S3` robustness.
- AR Phase 2 mechanism placebo: transfers data is already cached at `data/processed/transfers_ibge.qs2` (96.3% match rate), per audit. Procurement data not yet sourced.

### 8.2 Data integration decisions awaiting advisor input

- **C6** Alternative employment / production-factor data: RAIS unexploited variables (education, age, wages), INEP Censo Escolar, PPM + PAM all immediately actionable. PNAD infeasible (no muni-level public microdata). Awaiting advisor decision on what to ingest. Memo: [`logs/data_exploration/c6_employment_sources.md`](../logs/data_exploration/c6_employment_sources.md).
- **C7** Local deflators: no full-coverage muni deflator exists for 2002-2017. Metro IPCA (roughly 13 metros, roughly 55% of GDP) is the only off-the-shelf option; wage-residual proxy from RAIS is the tractable full-coverage alternative. Awaiting advisor decision. Memo: [`logs/data_exploration/c7_local_deflators.md`](../logs/data_exploration/c7_local_deflators.md).

These are not blockers for the immediate F2 production-margin test.

### 8.3 Paper integration

- `paper/regs.tex` is the current authoritative draft of the Specifications section but is **not** included from `main.tex`. The section 5 of `main.tex` is older and contains a placeholder section ("Connection to three steps thing (deprecated)"). Decide when to merge.
- `docs/methodology_notes/proposition2_aggregation_review.tex`: eventual appendix material or kept as internal note. Currently classified as internal note.
- The paper/specification draft needs to absorb the 2026-05-03 to 2026-05-05 design updates: the admissibility criterion, the `policy_block_active x S3` production margin, F1 diagnostic results, the unmatched-loan / T3-imputation caveat, and the retirement of project-CNAE as a load-bearing measurement concern.

### 8.4 Current next action

1. Build the `policy_block_active x S3` production crosswalk.
2. Wire it into scripts `31`, `34`, and `41`.
3. Run script `53` on the new margin to test F2.
4. After F2, resume AR baseline, F3 placebos, and F4 weight / denominator robustness.

---

## 9. What is **not** in this file

- Detailed pipeline script behaviors: `scripts/R/<stage>/<script>.R` and `INSTRUCTIONS.md` -> "Pipeline Architecture".
- Variable definitions: `README.md` -> "Variable Dictionary".
- Full LaTeX preamble standards: `.claude/rules/working-paper-format.md`.
- Plans for individual implementation tasks: `logs/plans/archive/`.
- Specific session implementation notes: `logs/session_logs/archive/`.
