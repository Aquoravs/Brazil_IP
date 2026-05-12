---
title: Knowledge — Conventions and Findings from Implementation
status: current
date: 2026-04-28
purpose: Concise reference of decisions, conventions, and numerical findings extracted from session logs and brainstorms
---

# Knowledge

Extracted from historical session logs now represented under `journal/sessions/` and from `docs/archive/brainstorms/`. Each item is dated by the session that established it; full context lives in the source file when available.

For active design decisions and the current research focus, see [`docs/research_state.md`](../docs/research_state.md).

---

## 1. Conventions adopted

| Convention | Date | Source |
|---|---|---|
| Project migrated `Brazil_IP_Code/` → `Brazil_IP/` (clo-author template). All paths via `_utils/utils.R`: `BNDES_BASE`, `BNDES_OUTPUT`, `BNDES_TABLES`, `ENCFS_MOUNT` | 2026-04-02 | `2026-04-02_migration-to-clo-author.md` |
| `binary_fp` baseline = `max(1(L_fp,s > 0))` over pre-election window (any-year indicator), not fraction-of-years | 2026-04-04 | `2026-04-04_max-binary-baseline-employment.md` |
| `emp_weighted` redefined to use `bl_n_employees` (mean pre-election baseline employment, spread across electoral terms), not contemporaneous; computed in script 42, not 36 | 2026-04-04 | same |
| Spec engine 51 weighting parameter: string (`unweighted` / `emp_weighted`), not boolean | 2026-04-04 | same |
| Renames: `setor_bndes → bndes_sector`; `sector_group → custom_sector` | 2026-04-06 | `2026-04-06_sector_aggregation_design.md` |
| Aggregated firm extensive margin label: `H^pre_jmt` → "Share Receiving BNDES Loan" / "Share of firms receiving a BNDES loan" | 2026-04-07 | `2026-04-07_agg_extensive_margin_label_cleanup.md` |
| F-stat formatter caps at `$>$10k` for non-finite or > 10000 (presentation layer only; raw Wald statistic preserved upstream) | 2026-04-07 | `2026-04-07_fix-flag-suspicious-fstats.md` |
| Aggregated appendix filter: `p<0.05` significance qualifies only when same column has `F < 10000` | 2026-04-07 | `2026-04-07_agg_first_stage_appendix_filter.md` |
| Firm panel split into base + sparse instrument files (`firm_panel_for_regs{_bt}.fst` + `firm_panel_for_regs{_bt}_instruments.fst`) | 2026-04-14 | `2026-04-14_script42_split_refactor.md` |
| Unified firm-panel loader at `_utils/load_firm_panel.R`; legacy fat-file fallback removed | 2026-04-14 | same |

---

## 2. Spec engine architecture (consolidated)

### Script 51 — firm first stage

8 dimensions: `margin × exposure × weighting × baseline × alignment × time_variation × sample × family`. Outputs canonical `firm__...` tables + `firm_run_manifest.csv/.qs2` + `fc_battery_summary.qs2`. Two-pass loader: keep_cols split on `^(FA_|dFA_)` to separate base columns from sparse instruments. Reference panel size: 44,181,405 rows (cycle-specific baseline).

### Script 52 — aggregated firm → sector

9 dimensions: `outcome × baseline × alignment × FE × exposure_control × sector_var × aggregation × regression_weight × exposure`. Outcomes: `bndes_share`, `bndes_extensive`, `log_employment`, `employment_share`. Pairing rule: `unweighted ↔ equal_firm aggregation`, `emp_weighted ↔ employment aggregation`. Source: `2026-04-06_sector_aggregation_design.md` and `2026-04-06_script52_spec_engine_fix.md`.

### Script 53 — sector first stage

6 dimensions: `time_variation × instrument_weight × baseline × alignment × FE × exposure_control`. Instrument-weight variants: `owner_count` (primary), `employment`, `equal_firm`, `binary` — built per `2026-03-24-sector-instrument-weighting-alternatives` brainstorm.

---

## 3. Sector taxonomy artifacts

| Script | Output | Content |
|---|---|---|
| 30 | `sector_group_mapping.qs2` | CNAE section → 11 custom_sector groups |
| 30b | `bndes_sector_mapping.qs2` | CNAE section → 4 BNDES macro-sectors (majority-vote from `sector_mapping.csv`) |
| 30c | `size_bin_mapping.qs2` | National employment terciles per cycle (computed from firm-year totals, not firm-muni-year, to avoid multi-muni misclassification) |
| 30d | `sector_size_bin_bndes_mapping.qs2` | Within-BNDES-macro tercile (4×3 = 12 categories); also produces `sector_size_bin_cnae_mapping.qs2` and `sector_size_bin_custom_mapping.qs2` |

---

## 4. Findings (preparatory first-stage work)

Source: `2026-04-05_first-stage-beamer-presentation.md` and `quality_reports/2026-04-05_first_stage_talk_audit.md`.

### 4.1 BNDES extensive margin (firm panel)

Strongest spec: **Coalition · Unweighted · Pooled count**.

- Cycle-specific baseline: max F = 103.2 (governor)
- 2002-fixed baseline: max F = 24.4 (president)

Both baselines viable; cycle-specific is **not** weaker than 2002-fixed. Coalition · Unweighted · Binary works in M+P and M+G+P columns only. Party · Unwt · Pooled works only with cycle-specific baseline.

### 4.2 BNDES intensive margin

**No viable spec** — max F ≈ 6 across all 32 specs.

### 4.3 Employment outcomes as LHS

Reduced-form direct effects, **not BNDES-mediated**:

- `employment_log`: F up to 265 (Coal · Unwt · Pooled, both baselines)
- `employment_share`: F up to 223

These large F-stats raise an exclusion-restriction concern if used in IV. Treat as evidence of direct alignment → employment channel.

### 4.4 Weighting comparison

Emp-weighted **consistently weaker** than unweighted across all outcomes and baselines.

### 4.5 Aggregation gap (Proposition 2)

Source: [`docs/methodology/proposition2_failure_note.tex`](../docs/methodology/proposition2_failure_note.tex).

- Used sample for reference firm spec: 43,184,682 obs (vs 44,181,405 with `y` and `x` observed; 996,723 dropped, almost all singleton firms).
- Exact aggregation from cell sums of firm sufficient statistics matches firm-level $\hat\beta$ to within $1.1 \times 10^{-16}$.
- Cell-mean regression differs (mayor: 0.00218 vs 0.00129; gov: 0.00340 vs 0.00440; pres: 0.00038 vs −0.00660). Within-cell share of $\sum x^2$: 91.9% (mayor, gov), 93.7% (pres) — most identifying variation is **inside** cells, not between cell means.
- Conditions C1–C5 enforceable; **C6 (no within-cell regressor heterogeneity) is irreducible** because firm baseline party exposures $\omega_{fp,0}$ vary within $(j,m)$ cells.

---

## 5. Performance / engineering wins

| Item | Before | After | Source |
|---|---|---|---|
| Script 42 Step 4 peak RAM | ~17 GB pre-allocation + 14 GB peak | base + sparse split files; 14 GB join eliminated | `2026-04-14_script42_split_refactor.md` |
| Script 42 Step 3B `uniqueN(muni_id) by (firm_id, year)` | minutes | seconds (GForce `.N`; panel is unique on firm×muni×year) | `2026-04-14_script42_memory_efficiency.md` |
| `save_beamer_table()` total runtime per pipeline run | 15+ min (`modelsummary` + `kableExtra` overhead) | < 1 min (direct fixest extraction + `sprintf`) | `docs/archive/brainstorms/2026-03-24-fast-beamer-table-export-brainstorm.md` |
| Output file format | qs2 + fst dual-write | fst only (qs2 fallback retired in downstream) | `2026-04-14_script42_memory_efficiency.md` |

---

## 6. Data exploration outcomes (advisor C6/C7)

Source: [`docs/data_memos/c6_employment_sources.md`](../docs/data_memos/c6_employment_sources.md), [`docs/data_memos/c7_local_deflators.md`](../docs/data_memos/c7_local_deflators.md). Status as of 2026-04-21: memos delivered, awaiting advisor review.

### C6 — alternative employment / production-factor data

**Actionable (Grade A or B, on `basedosdados` with muni × year keys):**

- **RAIS unexploited variables** — education (8 grau de instrução categories), age bracket, wage distribution, tenure, share by CBO occupation. Already in encrypted mount; column-expansion only. **Zero new data access cost.**
- **INEP Censo Escolar** — annual school census, all munis, on `basedosdados`. Best human capital proxy.
- **PPM + PAM** — annual agricultural production / livestock, all munis. Best agricultural capital + land proxy.
- **CAGED** — monthly job flows since 1996, all munis, formal sector. Aggregates to annual.

**Cross-sectional only (Grade B):**

- Censo Agropecuário — 2006 and 2017 in window; rich capital and land variables.
- Censo Demográfico — 2000 and 2010; comprehensive employment / education / age.

**Infeasible (Grade D):**

- PNAD / PNAD Contínua — public microdata geographic identifiers restricted to states + metro capitals; no muni-level aggregation possible for the 5,570-muni panel.

### C7 — local / spatial deflators

**No full-coverage muni deflator exists for 2002–2017.** Off-the-shelf options:

- **Metro IPCA** (Grade C) — 11 metros 2002–2013, 13 metros 2014–2017. Covers ~8–10% of munis but ~55% of GDP. Crosswalk: `basedosdados.br_bd_diretorios_brasil.municipio` → `id_rm`. Suitable for robustness check on metro subsample only.
- **Wage-residual proxy** (Grade B/C) — muni FE in Mincerian regression on RAIS data. Tractable, annual, full muni coverage. Albouy (2009) methodology.

**Misconception clarified:** Corseuil & Foguel (2002) is a temporal deflator only — does NOT provide spatial variation.

**Advisor recommendation in memo:** keep national IPCA as primary; metro IPCA as robustness on metro subsample.

---

## 7. Open analysis directions (preparatory phase that fed AR test)

These were investigated but are now superseded by the AR-test agenda; kept for traceability.

- **Firm → sector first-stage disconnect** (2026-03-14 brainstorm): H1 (scale effect), H2 (cross-sector cancellation) confirmed by within-muni-year cancellation pattern; H3 (weighting mismatch) ruled out (small firms drive the firm-level result, owner-count weights also weight small firms heavily); H4 (Jensen's inequality) is real and explicitly handled by the equal_firm vs owner_count aggregation choice in script 52.
- **Affiliation data diagnostics** (2026-03-15 brainstorm): implemented as `diagnostics/explore_affiliation.R`. Covers affiliation rates by year, firm entry/exit, party stability, temporal gaps, multi-municipality presence.
- **Sector instrument weighting alternatives** (2026-03-24 brainstorm): all four variants (owner_count, employment, equal_firm, binary) implemented in script 53; binary baseline mirror in script 51 and 52.

---

## 8. Cross-references

| For… | See… |
|---|---|
| Current decisions and AR-test focus | [`docs/research_state.md`](../docs/research_state.md) |
| Advisor comment statuses (C1-C8) | [`journal/meetings/2026-04-17/tracker.md`](meetings/2026-04-17/tracker.md) |
| Plan history (per-task) | [`journal/plans/`](plans/) |
| Session logs (full detail per task) | [`journal/sessions/`](sessions/) |
| Audit reports | [`journal/audits/`](audits/) |
| Data-source feasibility memos | [`docs/data_memos/`](../docs/data_memos/) |
