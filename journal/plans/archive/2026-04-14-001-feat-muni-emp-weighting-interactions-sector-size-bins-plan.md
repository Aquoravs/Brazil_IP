---
title: Muni-employment share weights, top-quartile interactions/splits, and sector × firm-size classifications
type: feat
status: completed
date: 2026-04-14
origin: (no matching requirements doc; bootstrapped from user prompt)
scope: scripts/R/3_instruments/{30c,31,33,34}, scripts/R/4_regression_panels/{41,42}, scripts/R/5_estimation/{51,52,53}, scripts/R/run_politicsregs.R
governing_sources:
  - CLAUDE.md / INSTRUCTIONS.md
  - paper/sections/regs.tex
---

# Muni-employment share weights, top-quartile interactions/splits, and sector × firm-size classifications

## Overview

Four coordinated extensions to the BNDES politics-regs first-stage pipeline:

1. **Re-weight firm (51) and sector (52) first-stages** so that firm/sector contributes proportionally to its **share of pre-election municipality employment**, not raw pre-election headcount.
2. **Pooled regressions with an interaction** between the instruments and a dummy for top-quartile municipality employment.
3. **Split-sample regressions** using the same top-quartile classification.
4. **Sector × firm-size-tercile taxonomies**, built for both grouped BNDES sectors and CNAE sections, as new candidate sector definitions for (52) and optionally (53).

The plan is conservative: it adds new objects and new specs rather than re-defining existing ones, and it preserves the firm + sector dual-pipeline structure described in `regs.tex`.

This document is organised in the seven sections the user requested (**A–G**), then closes with the standard plan artifacts (implementation units, risks, validation, references).

---

## A. Audit of current logic

Verified against current source (2026-04-14).

### A.1 How employment enters scripts 51 and 52 today

**Script 51 — firm first stage.**
- Regression weight (when `weighting = emp_weighted`) is **`bl_n_employees`** — the firm × muni × year **pre-election mean headcount**, spread across the electoral term (built in `42_build_firm_panel.R`, lines 355–480).
  - Usage: `fit_args$weights <- ~bl_n_employees` (`51_firm_first_stage.R:695–696`).
  - Sample mask: `weight_ok <- is.finite(bl_n_employees) & bl_n_employees > 0` (`51:524–526`).
- **Not a share.** It is raw headcount. Mechanically, this means larger firms in larger municipalities count disproportionately against *all other firms in the same muni-year cell and in other muni-year cells*. Because the FE structure is `firm_id + muni_id^year`, the weight still affects how firm-level variation aggregates into the coefficient, but the scale is the raw firm headcount, not a share.

**Script 52 — aggregated firm → sector first stage.**
- Two distinct uses of employment:
  1. **Instrument aggregation** from firm-level `FA_*` to sector-level `FA_bar_*` when `aggregation = employment`: `weighted_mean_safe(FA_*, bl_n_employees)` (`52:550`). Other aggregation modes use owner-counts or equal-firm weights (`52:549–562`).
  2. **Regression weight** when `regression_weight = emp_weighted`: `wt_formula <- ~emp_pre`, where `emp_pre = sum(bl_n_employees)` within (`sector, muni, year`) (`52:540, 604, 646`).
- Again, `emp_pre` is a **sum of headcounts**, not a share of muni employment.

**Script 53 — sector first stage.** Does not use employment weights at all; it works off the pre-collapsed `muni_sector_panel` with `s_mjt` / `Δs_mjt` outcomes and shift-share instruments from `34`.

### A.2 Upstream: does pre-election *municipality* employment exist?

**No.** No script in the current pipeline computes a pre-election-window muni-total employment. Searched: `31, 32, 33, 34, 35, 36, 41, 42`.

- `41_build_muni_panel.R:144` computes `total_employment = sum(n_employees, na.rm = TRUE)` per `(muni_id, year)` — **contemporaneous only**.
- `42_build_firm_panel.R` computes `bl_n_employees` (firm × muni × year, pre-election averaged) and `emp_share_muni_rais = n_employees / total_muni_rais_employment` (contemporaneous). Neither provides a pre-election muni total.

**Implication for goal (1).** A new pre-election muni-employment object is **required** upstream before the new share weights can be constructed. It is not sufficient to divide firm-level weights by the contemporaneous `total_employment` — that re-introduces post-treatment variation.

### A.3 Does goal (1) change only estimation weights, or also collapsed objects upstream?

The proposed change modifies (a) regression weights in 51 and 52, and (b) the firm-weight used in the `aggregation = employment` variant in 52 (since that aggregation mixes into the instrument itself, not just the standard errors).

- **Pure regression-weight change** (51 `weighting=emp_weighted`; 52 `regression_weight=emp_weighted`): changing the weight column is local to 51/52. No new collapsed object required beyond a per (muni, year) pre-election denominator.
- **Instrument-aggregation change** (52 `aggregation=employment`): if the user wants the aggregated `FA_bar_*` instrument to use muni-employment shares as weights rather than raw `bl_n_employees`, this modifies the **instrument object** used in 52's first stage. Strictly this is still at the per-firm weight level (shares sum to ≤ 1 within (m,t) cell), and mathematically the within-cell collapse is unchanged up to a constant — `w_f = bl_n_employees_f / M_{m,t}` with `M_{m,t}` constant within the cell yields `Σ w_f · FA_f = (1/M_{m,t}) Σ bl_n_employees_f · FA_f`. So the *point estimates* of the collapsed instrument are identical up to a per-cell rescale. **This should be made explicit** in the plan — see Ambiguity B.3.

### A.4 Goals (2)–(3): top-quartile classification

- No `muni_emp_q4`, `top_quartile`, or similar flag exists anywhere.
- `41_build_muni_panel.R` is the natural place to compute a muni-level average employment over the sample window (2002–2017) and classify into quartiles; this is a single time-invariant classification per `muni_id`.
- Scripts 51/52 need a minimal addition: a flag column on the panel, plus a new family `interaction_mqemp` that adds `FA_bar_* : top_q4_muni` and `Z^ℓ_jmt : top_q4_muni` to the formula; and a new `sample` option (or a split at the driver level) for split-sample regressions.

### A.5 Goal (4): sector × firm-size bins

- `30c_build_size_bin_mapping.R` already exists and produces **national terciles** of pre-election firm employment (not within sector), per election cycle (`30c:7–8, 77–79`). This is currently consumed **only by 52** (`sector_var = size_bin`).
- The new extension needs:
  - **Within-sector** terciles (not national), separately for `cnae_section` and for `sector_group`.
  - An output crosswalk `(firm_id, election_cycle, sector, size_bin) → sector_size_bin`.
  - A `sector_var` value in 52 (and optionally 53) that reads this crosswalk.

No changes are needed in 31–36 for goal (4) *unless* the user wants the sector-level shift-share instrument (`Z^ℓ`) itself to be built at the `(sector × size_bin, muni, year)` grain — see Ambiguity B.6.

### A.6 Downstream exposure / controls

- Script 34's exposure controls `EC^ℓ_jm,t` and script 31's weights use **owner-count** aggregation inside the cell (`31:128`, `34` via `baseline_sector_weights`). These are **not** affected by goal (1). The re-weighting applies only to regression-level weights and — optionally — to the instrument-aggregation weight inside 52.

---

## B. Design decisions (resolved 2026-04-14)

All decisions confirmed by user.

| # | Decision | Resolution |
|---|---|---|
| B.1 | Muni-employment denominator window | **(a) Office-specific.** Mayor-cycle muni employment for `FA_mayor` weights; G/P-cycle muni employment for `FA_gov`/`FA_pres` weights. Matches the `bl_n_employees` cycle windows in script 42/33. |
| B.2 | Multi-muni firms | **(a) RAIS muni-m headcount.** Firm's contribution to `muni_emp_bl` equals its employment allocated to that municipality by RAIS. No double-counting. |
| B.3 | 52 `aggregation=employment` | **(a) Regression weight only.** `aggregation=employment` is left unchanged (within-cell weighted mean; dividing by muni total is a cell-constant that cancels). New `regression_weight=emp_share_weighted` divides `emp_pre` by `muni_emp_bl` at the collapsed level. No new aggregation label. |
| B.4 | Muni quartile classification | **Confirmed.** Mean RAIS employment 2002–2017, national (unconditional), time-invariant per `muni_id`. |
| B.5 | FE for sector interaction specs | **(a) `mxj_jxt`** (`muni^sector + sector^year`). The main effect of the time-invariant `top_q4_muni` is absorbed by `muni^sector`; the interaction with `Z^ℓ_jmt` is identified because the instrument varies within `(muni, year)`. Hard-stop in 53 if `mxj_mxt` is combined with muni interaction. |
| B.6 | Sector × firm-size bins | **(a) Within-sector terciles.** Each sector (`cnae_section` and `sector_group`) gets its own T1/T2/T3 thresholds computed on national sector population, per election cycle. |
| B.7 | Scope of goal (4) | **Script 52 only** for this plan. Goal (4) adds new `sector_var` options in 52 using firm→sector collapse (no need to touch 31/33/34). Script 53 rebuild deferred to a follow-up plan triggered by 52 diagnostics. |
| B.8 | Size variable | **Confirmed.** Pre-election mean `n_employees` per election cycle, matching `30c`. |
| B.9 | Split-sample implementation | **(a) Spec-grid dimensions.** Add `sample ∈ {top_q4, bottom_3q}` to script 51; add `muni_sample ∈ {all, top_q4, bottom_3q}` to scripts 52 and 53. |

---

## C. Proposed implementation plan

Split along the five dimensions the user requested (plus validation).

### C.1 Municipality-employment measures and top-quartile flag

**New intermediate object.** `output/muni_employment_baselines.qs2`, keys `(muni_id, election_cycle, baseline_type)`, columns:
- `muni_emp_bl` — sum of `n_employees` across the baseline window for that cycle;
- `muni_emp_whole` — 2002–2017 mean (replicated across cycles for convenience);
- `top_q4_muni` — 0/1 flag based on `muni_emp_whole` quartiles, time-invariant;
- `muni_emp_quartile` — 1–4 (reporting).

**New/modified scripts.**
- **Modify `41_build_muni_panel.R`** to compute `muni_emp_whole` and write `muni_employment_classification.qs2` at `(muni_id)` level (time-invariant).
- **New `32b_build_muni_employment_baselines.R`** (or, minimally, added as a helper inside `42_build_firm_panel.R`): compute per-cycle pre-election muni-employment totals from RAIS, with office-specific windows mirroring script 33. Produces `muni_employment_baselines.qs2`.
- **Modify `42_build_firm_panel.R`** to merge `muni_emp_bl` onto the firm panel and compute:
  - `emp_share_muni_pre = bl_n_employees / muni_emp_bl` (firm × muni × year, pre-election share).
  - `top_q4_muni` flag.

### C.2 New weight construction

**Script 51.**
- Add a new `weighting` value: `emp_share_weighted` (in addition to existing `unweighted, emp_weighted`).
- Resolves to `fit_args$weights <- ~emp_share_muni_pre`.
- Keep `emp_weighted` (raw headcount) as a *robustness* spec so historical results remain reproducible.

**Script 52.**
- Add a new `regression_weight` value: `emp_share_weighted`. Resolves to `wt_formula <- ~emp_share_sector_pre`, where `emp_share_sector_pre = emp_pre / muni_emp_bl` at the collapsed (sector, muni, year) level.
- Leave `aggregation=employment` unchanged (see B.3). Optionally add `aggregation=employment_share` label as no-op (up to cell-constant rescaling) for reporting.

**Expected outputs.** New `.tex` table cells under `paper/tables/firm/` and `paper/tables/agg_firm*/` with filenames ending in `__emp_share_weighted__*` (following the existing filename convention in 51/52).

### C.3 Pooled regressions with interaction terms

**Script 51.** Add a new `family` value: `interaction_mqemp`.
- Combos become, e.g., `FA_mayor + FA_mayor:top_q4_muni` and similar for other tiers.
- FE unchanged: `firm_id + muni_id^year` (the main effect is absorbed).
- Expose via `--family=interaction_mqemp` CLI flag.

**Script 52.** Add analogous `interaction_mqemp` family at the sector level: `FA_bar_* + FA_bar_* : top_q4_muni`.
- Expose via `--family` CLI flag.

**Script 53.** Add a new CLI flag `--muni-interaction=top_q4_muni` (default off). When set, the model adds `Z^ℓ : top_q4_muni` for every shock. Requires FE `mxj_jxt` (see B.5); 53 will `stop()` with a clear message if `mxj_mxt` is combined with a time-invariant muni interaction.

### C.4 Split-sample regressions

**Script 51.** Add `sample ∈ {top_q4, bottom_3q}` alongside existing `{all_firms, single_muni}`.
- Specs: `top_q4_sample`, `bottom_3q_sample`.
- Filter is `dt[top_q4_muni == 1]` or `dt[top_q4_muni == 0]`.

**Script 52.** Introduce new dimension `muni_sample ∈ {all, top_q4, bottom_3q}` with the same filter semantics.

**Script 53.** Same `muni_sample` dimension.

### C.5 Sector × size-bin classifications (goal 4)

**New scripts.**
- `30d_build_sector_size_bin_mapping.R`:
  - Input: `firm_panel_for_regs.fst/.qs2`, `sector_group_mapping.qs2`, `bndes_sector_mapping.qs2`.
  - Output **two** crosswalks:
    - `sector_size_bin_cnae_mapping.qs2` — `(firm_id, election_cycle, cnae_section, size_bin_cnae)` with terciles computed **within `cnae_section`** nationally per cycle.
    - `sector_size_bin_group_mapping.qs2` — same for `sector_group`.
  - Build the composite key `sector_size_bin = paste(cnae_section, size_bin_cnae, sep = "_")` (and analog for sector_group).

**Script 52.** Add `sector_var ∈ {cnae_size_bin, sector_group_size_bin}`.
- Spec: `size_bin_battery` (loops over `cnae_section`, `sector_group`, `cnae_size_bin`, `sector_group_size_bin`).
- Use the new crosswalks to merge the composite key onto the firm panel prior to the collapse step.

**Script 53.** No changes in this plan (see B.7). A future plan can rebuild 31/33/34 at the new grain.

### C.6 Validation and diagnostics

Delivered via a new diagnostics script (see Section E below). Consumed by `52b_agg_first_stage_summary.R` to produce new appendix tables in `paper/tables/agg_firm_size_bin/` (already present as a folder from prior work) and new entries in `paper/sections/agg_first_stage.tex`.

---

## D. Script-level modification map

Symbols: **M** = mandatory; **O** = optional; **N** = new file.

| Script | Currently reads | New columns / arguments / files | Must remain unchanged | Change |
|---|---|---|---|---|
| `30c_build_size_bin_mapping.R` | `firm_panel_for_regs` | — | national-tercile taxonomy kept as default | **none** (preserve existing) |
| `30d_build_sector_size_bin_mapping.R` (new) | `firm_panel_for_regs`, `sector_group_mapping`, `bndes_sector_mapping` | outputs `sector_size_bin_{cnae,group}_mapping.qs2` | — | **N** |
| `31_build_sector_exposure_weights.R` | RAIS reconstructed panel, owner affiliation | — | owner-count weight logic | **none** (no change for goals 1–4 under default B.7) |
| `32_build_alignment_shocks.R` | `in_power_upd_*` | — | alignment construction | **none** |
| `32b_build_muni_employment_baselines.R` (new) | RAIS panel | outputs `muni_employment_baselines.qs2` (per-cycle), `muni_employment_classification.qs2` (whole-period) | — | **N** |
| `33_select_baseline_weights.R` | `sector_exposure_weights_*` | — | window logic | **none** |
| `34_build_shift_share_instruments.R` | `baseline_sector_weights`, `alignment_shocks` | — | instrument construction | **none** |
| `35_build_credit_shares.R` | RAIS reconstructed panel | — | credit share logic | **none** |
| `41_build_muni_panel.R` | RAIS, instruments, GDP | adds `muni_emp_whole`, `muni_emp_quartile`, `top_q4_muni` columns; emits `muni_employment_classification.qs2` | existing `total_employment` column, muni instruments | **M** |
| `42_build_firm_panel.R` | firm-level instruments, RAIS | merges `muni_employment_baselines`; computes `emp_share_muni_pre` (firm × muni × year, pre-election share); merges `top_q4_muni` | `bl_n_employees` (must be preserved as legacy weight), `is_multi_muni`, all existing outcomes | **M** |
| `51_firm_first_stage.R` | firm panel | new `weighting=emp_share_weighted`; new `family=interaction_mqemp`; extend `sample` dimension | existing specs must remain runnable unchanged | **M** |
| `52_aggregated_firm_sector_first_stage.R` | firm panel (+ new sector-size-bin crosswalks) | new `regression_weight=emp_share_weighted`; new `family=interaction_mqemp`; new `sector_var ∈ {cnae_size_bin, sector_group_size_bin}`; new `muni_sample` dimension | existing specs | **M** |
| `53_sector_first_stage.R` | sector panel | new `--muni-interaction=top_q4_muni`; new `muni_sample` dimension | existing sector-level 31–34 instrument taxonomy | **M** |
| `54_sector_second_stage.R` | sector first-stage outputs | — (may later consume new muni-split results) | — | **O** (follow-up plan) |
| `run_politicsregs.R` | CLI | add `32b` and `30d` to stage map; pass-through `--muni-sample`, `--muni-interaction` | existing routing | **M** |

---

## E. Validation strategy for the new sector classifications

The objective is evaluating whether changes in the allocation of loans across sectors matter for municipality-level outcomes (`regs.tex` §§1, 2.5, 2.6). A new sector taxonomy that simply improves the first stage is **not** a better taxonomy for this paper if it loses the interpretability of "sectoral reallocation" or creates thin cells that do not aggregate coherently back to the muni level.

Below, we distinguish **mechanical fit** from **economically meaningful reallocation signal**.

### E.1 What would count as a *substantively* better classification

Relative to existing `cnae_section` and `sector_group`, a candidate is substantively better if **all** of:
1. **Preserved muni coverage.** For ≥ 95% of (muni, year) cells with positive BNDES, the new taxonomy's `Σ_j s_{jmt} = 1` identity still holds (no BNDES credit is lost to thin cells that are dropped in later steps).
2. **Nonpathological cell counts.** Median sector × (firm-size tercile) cell has ≥ 5 firms; < 10% of cells have fewer than 3 firms. (The existing sector_group has ~25–40 firms per cell on average; we should not collapse by an order of magnitude.)
3. **Within-cell dispersion grows or is preserved.** Variance of `s_{jmt}` within (muni, year) across the new sector definition is not *lower* than under the baseline — otherwise we are re-introducing the aggregation collapse that motivated the firm pipeline.
4. **First stage remains interpretable.** The new `Z^ℓ` object remains a convex combination of firm-level shift-share instruments with well-defined weights, and the exposure control `EC^ℓ_jm,t` remains bounded by 1 for the pooled-count baseline (`regs.tex` §2.3 footnote).
5. **Muni aggregation still maps to GDP.** The new second-stage object `Σ_j (ŝ_{jmt} - s_{jm,t-1}) · β_j` has the same muni-level interpretation — i.e., "expected reallocation across sectors" is still well-defined when the sector unit now embeds firm size.

First-stage F-statistic growth alone is **not** sufficient. If F grows because thin high-variance cells survive on a small subset of munis, the gain is mechanical.

### E.2 Diagnostic battery (delivered by new script 52c or extension of 52b)

For each candidate `sector_var ∈ {cnae_section, sector_group, cnae_size_bin, sector_group_size_bin}`:

| Diagnostic | Computation | Pass criterion |
|---|---|---|
| **D1. Observation / cell counts** | Obs count; distinct (muni, sector) cells; median/min firms per cell per cycle | Median ≥ 5; p10 ≥ 2 |
| **D2. Within-muni-year dispersion** | `var(s_{jmt} | m, t)` and `var(Z^ℓ_{jmt} | m, t)` | ≥ baseline `sector_group` |
| **D3. First-stage relevance under alternative FE** | F-stat on `Z^ℓ` (or `FA_bar_*`) with FE `mxj_jxt`, `mxj_mxt`, `mxj_year` | Report all three; no single FE used to declare a winner |
| **D4. Stability across sector taxonomies** | Compare λ̂ across `cnae_section`, `sector_group`, and size-bin variants; compute cosine similarity of coefficient vectors | λ̂ sign and order of magnitude preserved |
| **D5. Tercile vs quartile size-bin robustness** | Re-run the size-bin variant with quartiles; compare (a) thin-cell rate; (b) F-stat | Choose the coarsest that still passes D1 |
| **D6. Thin-cell audit** | Share of (muni, sector) cells with < 3 firms; share of (muni, year) cells where the new `Σ_j s_{jmt}` differs from total BNDES | Thin-cell rate < 10%; aggregation loss < 1% of credit |
| **D7. Muni-level aggregation fidelity** | Build `Δ̂s_{jmt} · β̂_j` at the muni level under each taxonomy; correlate with baseline | ρ > 0.8 across taxonomies |
| **D8. Economic interpretability** | Narrative: for a worked muni example, does "sector 'Heavy mfg, firm-size T3' got more BNDES credit" map to a readable statement about sectoral reallocation? | Yes/No judgment, flagged for user |
| **D9. Placebo on D4** | Estimate with *lead* alignment; expect null | Not significantly different from zero |

Outputs:
- `paper/tables/sector_taxonomy_diagnostics.tex` — compact one-page table summarising D1–D7 across taxonomies.
- `quality_reports/sector_taxonomy_diagnostic_report.md` — full write-up including D8 narrative.

**Explicit decision rule.** Declare a taxonomy "preferred" only if it passes D1–D3, does not degrade D4 or D6, and has D7 correlation ≥ 0.8. Larger F-stats with degraded D4/D6/D7 do **not** win.

---

## F. Run plan

After implementation (and assuming ambiguities resolved with the conservative defaults in B):

### F.1 Build upstream objects (once per data refresh)

```bash
Rscript scripts/R/run_politicsregs.R 30c,30d,32b
Rscript scripts/R/run_politicsregs.R 41 -- --sector-var=sector_group
Rscript scripts/R/run_politicsregs.R 42
```

### F.2 Firm regressions with new employment-share weights

```bash
Rscript scripts/R/run_politicsregs.R 51 -- --specs=emp_share_weighted --family=main
```

### F.3 Sector regressions (aggregated firm → sector) with new employment-share weights

```bash
Rscript scripts/R/run_politicsregs.R 52 -- --specs=emp_share_weighted --aggregation=employment,employment_share --sector-var=sector_group
```

### F.4 Sector first-stage, new sector classifications (goal 4)

```bash
Rscript scripts/R/run_politicsregs.R 52 -- --specs=size_bin_battery --sector-var=cnae_section,sector_group,cnae_size_bin,sector_group_size_bin
```

### F.5 Muni-employment distribution specs (goals 2 and 3)

```bash
# Pooled with interaction (goal 2)
Rscript scripts/R/run_politicsregs.R 51 -- --specs=baseline,weighted --family=interaction_mqemp
Rscript scripts/R/run_politicsregs.R 52 -- --specs=baseline,emp_share_weighted --family=interaction_mqemp --sector-var=sector_group

# Split-sample (goal 3)
Rscript scripts/R/run_politicsregs.R 51 -- --specs=baseline,weighted --sample=top_q4
Rscript scripts/R/run_politicsregs.R 51 -- --specs=baseline,weighted --sample=bottom_3q
Rscript scripts/R/run_politicsregs.R 52 -- --specs=baseline,emp_share_weighted --muni-sample=top_q4,bottom_3q --sector-var=sector_group
```

### F.6 Diagnostics (post-hoc)

```bash
Rscript scripts/R/run_politicsregs.R 52b
# + new diagnostics aggregator (52c if added) or direct R script:
Rscript scripts/R/diagnostics/sector_taxonomy_diagnostics.R
```

---

## G. Final recommendation

### G.1 Minimum viable implementation (MVI)

**Scope.** Goals (1) + (2) + (3), restricted to scripts 51, 52, 41, 42 plus the new `32b` and `41` changes. **Skip 53 changes** for now (stick with existing `cnae_section` / `sector_group` there).

**Why.** It delivers the econometric objects the user asked for (proper employment shares + muni-employment interaction/split) with the smallest surface-area change and no upstream rebuild of 31/33/34. All new specs are additive — existing commands continue to work.

**Units.** C.1 (muni-emp measures), C.2 (share weights in 51/52), C.3 (interactions in 51/52), C.4 (splits in 51/52).

### G.2 Higher-value extension if time permits

Goal (4): add `30d` (two within-sector tercile crosswalks) and the new `sector_var ∈ {cnae_size_bin, sector_group_size_bin}` options in 52, plus the diagnostic battery (Section E). This is the single most informative extension because it evaluates whether within-sector firm-size heterogeneity is the missing dimension that caused the >90% within-cell variance observed in the sector pipeline (per `comparison_firm_agg.tex`, project memory).

### G.3 Highest-risk change that should not be coded until clarified

Rebuilding `31/33/34` at the `(sector × size_bin, muni, year)` grain so that script **53** can consume the new taxonomies (Ambiguity B.7). This multiplies the instrument-panel row count by up to 3× per sector, changes the owner-count denominators, and affects `EC^ℓ_jm,t` interpretability. This **must not be coded** until the user confirms both (a) that script 52 diagnostics indicate a meaningful gain, and (b) the exact weighting redesign for 31/33/34 under the new grain.

Additional coupled risk: Ambiguity B.1 (office-specific vs. single pre-election muni-employment denominator). Choosing the wrong window re-introduces post-treatment variation into the regression weights and invalidates the "weighted-average effect" interpretation stated in `regs.tex` §2.1. **Do not code goal (1) weights until B.1 is resolved.**

---

## Implementation Units

- [x] **Unit 1: Muni-employment upstream objects**
  - **Goal:** Produce two new intermediate objects: (a) office-specific per-cycle muni-employment totals for use as share denominators; (b) whole-period quartile classification for interaction/split specs.
  - **Files:**
    - Create: `scripts/R/3_instruments/32b_build_muni_employment_baselines.R`
    - Modify: `scripts/R/4_regression_panels/41_build_muni_panel.R`
  - **Approach:**
    - `32b`: For each (muni_id, election_cycle, office_tier), sum `n_employees` across the same baseline windows used by script 33 (mayor: [e_M−4, e_M−1]; G/P: [e_G−4, e_G−1]). Produce `muni_employment_baselines.qs2` keyed by `(muni_id, election_cycle, office_tier)` with column `muni_emp_bl`.
    - `41`: Compute `muni_emp_whole = mean(total_employment)` across 2002–2017 per `muni_id`; assign `muni_emp_quartile ∈ {1,2,3,4}` and `top_q4_muni ∈ {0,1}` nationally. Emit `muni_employment_classification.qs2` at (muni_id) level.
  - **Patterns to follow:** Script 33's baseline window definitions (`BASELINE_WINDOWS`); script 30c's summary CSV output pattern.
  - **Test scenarios:**
    - Happy path: every `muni_id` in RAIS appears in classification output; quartile 4 contains exactly 25% of munis (within rounding).
    - Edge case: munis with zero RAIS employment — verify they receive `muni_emp_whole = 0` and land in Q1.
    - Office-specific: mayor-cycle window for 2009 (`2004–2007`) differs from G/P-cycle window (`2002–2005`); verify two distinct `muni_emp_bl` values per (muni_id, election cycle year).
  - **Verification:** `muni_employment_baselines.qs2` exists; no `muni_id` missing from `muni_employment_classification.qs2`; quartile counts sum to total munis.

- [x] **Unit 2: Firm-panel integration**
  - **Goal:** Add `emp_share_muni_pre` (office-specific, pre-election share) and `top_q4_muni` to the firm panel so scripts 51/52 can consume them.
  - **Files:** Modify `scripts/R/4_regression_panels/42_build_firm_panel.R`
  - **Approach:**
    - Merge `muni_employment_baselines.qs2` on `(muni_id, election_cycle, office_tier)`.
    - Compute `emp_share_muni_pre_mayor = bl_n_employees / muni_emp_bl_mayor` and `emp_share_muni_pre_gp = bl_n_employees / muni_emp_bl_gp` — two columns, one per office tier (matching how `FA_mayor` and `FA_gov/pres` are separated).
    - Merge `top_q4_muni` from `muni_employment_classification.qs2` on `muni_id`.
    - Preserve `bl_n_employees` and `emp_share_muni_rais` (contemporaneous) unchanged.
  - **Patterns to follow:** Existing `bl_n_employees` spread logic (lines 432–444 of 42); `is_multi_muni` merge pattern (lines 301–328 of 42). Multi-muni: use RAIS muni-m `n_employees` (already in the panel per row), not total firm headcount.
  - **Test scenarios:**
    - Happy path: `emp_share_muni_pre_mayor` sums to ≤ 1.0 within any (muni_id, mayor_treatment_year) cell across all firms.
    - Multi-muni firm: the share is computed from the muni-m row's `bl_n_employees`, not the firm's total across munis.
    - Edge case: firm with `bl_n_employees = 0` → `emp_share_muni_pre = 0` (not NA, not Inf).
    - `top_q4_muni` is a 0/1 column with no NAs for munis in the panel.
  - **Verification:** `firm_panel_for_regs` has columns `emp_share_muni_pre_mayor`, `emp_share_muni_pre_gp`, `top_q4_muni`; no new NAs introduced in `bl_n_employees`.
  - **Depends on:** Unit 1.

- [x] **Unit 3: Script 51 — share weights, interaction family, split-sample**
  - **Goal:** Expose three new capabilities in the firm first-stage spec engine without breaking any existing spec.
  - **Files:** Modify `scripts/R/5_estimation/51_firm_first_stage.R`
  - **Approach:**
    - Add `weighting = "emp_share_weighted"` to the dimension grid. Resolves to `fit_args$weights <- ~emp_share_muni_pre_mayor` for mayor instruments and `~emp_share_muni_pre_gp` for G/P instruments. (If a combo uses both, weight by the column matching the dominant office tier — or use a single averaged share; flag as a deferred implementation detail.)
    - Add `family = "interaction_mqemp"`. For each standard instrument combo, add an interaction term `FA_* : top_q4_muni`. FE unchanged (`firm_id + muni_id^year`); main effect of `top_q4_muni` is absorbed by `muni_id^year`.
    - Add `sample ∈ {top_q4, bottom_3q}` alongside existing `{all_firms, single_muni}`. Filter: `dt[top_q4_muni == 1]` or `dt[top_q4_muni == 0]`.
    - New named specs: `emp_share_weighted`, `top_q4_sample`, `bottom_3q_sample`, `interaction_muni_emp`.
    - `all` spec bundle absorbs new specs.
  - **Patterns to follow:** Existing `emp_weighted` → `~bl_n_employees` pattern (lines 524–526, 695–696 of 51); `single_muni` sample mask (lines 541–554 of 51); `interaction` family combos (line 26 of 51).
  - **Test scenarios:**
    - Happy path: `--specs=emp_share_weighted` runs without error; produces table files following existing naming convention.
    - `--sample=top_q4` retains only rows where `top_q4_muni == 1`; N in table header reflects the reduced sample.
    - `--family=interaction_mqemp`: formula contains `FA_mayor:top_q4_muni`; coefficient table has one extra row per instrument.
    - Existing `--specs=baseline` produces identical output as before (non-regression).
  - **Verification:** All three new capabilities produce `.tex` table output; existing spec runs reproduce prior results.
  - **Depends on:** Unit 2.

- [x] **Unit 4: Script 52 — share weights, interaction family, muni-sample, sector-size-bin wiring**
  - **Goal:** Four parallel extensions to script 52's spec engine.
  - **Files:** Modify `scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R`
  - **Approach:**
    - **Share weight:** Add `regression_weight = "emp_share_weighted"`. After collapse, compute `emp_share_sector_pre = emp_pre / muni_emp_bl` (use the appropriate office-tier denominator column, mirroring Unit 3). `wt_formula <- ~emp_share_sector_pre`. Do NOT change `aggregation=employment` (B.3 resolved).
    - **Interaction family:** Add `family = "interaction_mqemp"`. Formula adds `FA_bar_* : top_q4_muni`. FE stays `muni^sector + sector^year` (mxj_jxt default per B.5).
    - **muni_sample:** Add `muni_sample ∈ {all, top_q4, bottom_3q}` dimension. Filter at the collapsed panel level on `top_q4_muni`.
    - **New sector_var:** Wire `sector_var ∈ {cnae_size_bin, sector_group_size_bin}`. Before collapse, merge the crosswalk from Unit 6 on `(firm_id, election_cycle)`, replace `sector_col` with the composite key. No changes to instrument construction.
    - New named specs: `emp_share_weighted`, `interaction_muni_emp`, `top_q4_sample`, `bottom_3q_sample`, `size_bin_battery`.
  - **Patterns to follow:** Existing `emp_weighted` → `~emp_pre` pattern (52:604, 646); `muni_sample` analogous to 51's `sample`; `sector_var` dispatch (52:107, 256).
  - **Test scenarios:**
    - `regression_weight=emp_share_weighted`: weights sum to ~1 within (sector, muni) cell after collapse; no Inf or NA weights.
    - `muni_sample=top_q4`: collapsed panel restricted to `top_q4_muni == 1` munis.
    - `sector_var=cnae_size_bin`: collapsed panel has composite sector key (e.g., `"A_T1"`); cell counts reported in diagnostics.
    - Existing `--specs=baseline` unchanged.
  - **Verification:** New specs produce `.tex` output; `sector_var=cnae_size_bin` cell-count table agrees with diagnostic output from Unit 8.
  - **Depends on:** Unit 2 (for share weights, interaction, muni-sample); Unit 6 (for sector_var).

- [x] **Unit 5: Script 53 — muni-interaction + muni-sample**
  - **Goal:** Add interaction and split-sample capabilities to the sector first-stage using the existing `Z^ℓ_jmt` instruments (no 31/33/34 rebuild).
  - **Files:** Modify `scripts/R/5_estimation/53_sector_first_stage.R`
  - **Approach:**
    - Merge `top_q4_muni` from `muni_employment_classification.qs2` onto the sector panel via `muni_id`.
    - Add `--muni-interaction=top_q4_muni` flag. When set: add `Z^ℓ_jmt : top_q4_muni` to the formula; enforce `fe=mxj_jxt` (emit a clear `stop()` message if `mxj_mxt` is combined with this flag).
    - Add `muni_sample ∈ {all, top_q4, bottom_3q}` to spec grid.
  - **Test scenarios:**
    - `--muni-interaction=top_q4_muni` with `fe=mxj_jxt`: interaction terms appear in formula; main effect absorbed.
    - `--muni-interaction=top_q4_muni` with `fe=mxj_mxt`: script stops with message "interaction with time-invariant muni flag is not identified under mxj_mxt; use mxj_jxt."
    - `muni_sample=bottom_3q`: panel restricted to munis with `top_q4_muni == 0`; all muni-sector cells in those munis retained.
  - **Verification:** Both new flags produce expected formula strings and table output; FE guardrail fires correctly.
  - **Depends on:** Unit 1 (classification file).

- [x] **Unit 6: Sector × firm-size-tercile crosswalks**
  - **Goal:** Produce two new crosswalks: firm → (cnae_section × size_tercile) and firm → (sector_group × size_tercile), per election cycle.
  - **Files:** Create `scripts/R/3_instruments/30d_build_sector_size_bin_mapping.R`
  - **Approach:**
    - Input: `firm_panel_for_regs` (firm_id, election_cycle, cnae_section, sector_group, bl_n_employees=pre-election mean).
    - For each (`cnae_section`, `election_cycle`): compute tercile thresholds of `mean_emp` across all firms in that section nationally. Assign `size_bin_cnae ∈ {T1, T2, T3}`. Composite key: `cnae_size_bin = paste(cnae_section, size_bin_cnae, sep="_")`.
    - Repeat for `sector_group` → `size_bin_group` → `sector_group_size_bin`.
    - Output: `sector_size_bin_cnae_mapping.qs2` and `sector_size_bin_group_mapping.qs2`, keyed by `(firm_id, election_cycle)`.
    - Emit summary CSVs with cell counts per (sector, size_bin, cycle) for diagnostic D1.
  - **Patterns to follow:** `30c_build_size_bin_mapping.R` (BASELINE_WINDOWS, tercile logic, summary CSV output); `30_build_sector_groups.R` (sector crosswalk structure).
  - **Test scenarios:**
    - Happy path: every firm in `firm_panel_for_regs` appears in both crosswalks for each cycle.
    - Within-sector balance: across all (sector, cycle) pairs, T1/T2/T3 contain roughly equal firm counts (within rounding); no empty bins.
    - Small sector edge case: sector with < 3 firms in a cycle — all assigned T1 (or emit a warning and flag); verify no `NA` bins.
    - Composite key: `cnae_size_bin = "A_T1"` format; no spaces or special characters.
  - **Verification:** Both `.qs2` files created; summary CSVs show no cycles with empty bins; cell counts match expectations for sector sizes.
  - **Depends on:** Script 42 (firm panel); nothing else.

- [x] **Unit 7: Diagnostic battery**
  - **Goal:** Implement the 9-diagnostic D1–D9 framework (Section E) as a standalone script and extend `52b_agg_first_stage_summary.R`.
  - **Files:**
    - Create: `scripts/R/diagnostics/sector_taxonomy_diagnostics.R`
    - Modify: `scripts/R/5_estimation/52b_agg_first_stage_summary.R`
    - Output table: `paper/tables/agg_firm_size_bin/sector_taxonomy_diagnostics.tex`
    - Output report: `quality_reports/sector_taxonomy_diagnostic_report.md`
  - **Approach:** Loop over `sector_var ∈ {cnae_section, sector_group, cnae_size_bin, sector_group_size_bin}`; compute diagnostics D1–D7 from collapsed panels; emit one row per taxonomy in the summary table; emit D8 narrative in the `.md` report.
  - **Test scenarios:**
    - D1 cell-count table is non-empty for all four taxonomies.
    - D6 thin-cell rate < 10% for baseline taxonomies; flagged (not failed) if exceeded for size-bin variants.
    - D7 correlation ≥ 0.8 for existing taxonomies vs. each other (sanity check).
  - **Verification:** `sector_taxonomy_diagnostics.tex` compiles without LaTeX errors; diagnostic report exists at expected path.
  - **Depends on:** Units 4 and 6.

- [x] **Unit 8: Driver + documentation updates**
  - **Goal:** Wire new scripts into `run_politicsregs.R` and update `INSTRUCTIONS.md` command table.
  - **Files:** `scripts/R/run_politicsregs.R`; `INSTRUCTIONS.md`
  - **Approach:** Add `30d` and `32b` to stage map; ensure `--muni-sample`, `--muni-interaction`, `emp_share_weighted` are passed through to child scripts.
  - **Depends on:** Units 1–7.

---

## Risks & Dependencies

| Risk | Mitigation |
|---|---|
| Wrong pre-election muni-employment window (B.1) makes share weights mix post-treatment variation | Block Unit 1 until user confirms B.1; default (i) office-specific is safest |
| Multi-muni firms double-count in shares (B.2) | Use RAIS muni-allocated headcount; report `single_muni` parallel spec |
| Instrument-aggregation weight change silently redefines the `FA_bar_*` object (B.3) | Keep `aggregation=employment` unchanged; introduce `employment_share` as a new label only |
| Interaction specs not identified under `mxj_mxt` FE (B.5) | Enforce `mxj_jxt` for sector interaction specs; hard-stop in 53 if combined with `mxj_mxt` |
| Thin cells from within-sector terciles in small sectors (B.6) | Diagnostic D1/D6 gates; drop or merge T1/T2 if cell count < 3 |
| Script 53 silently reading old `cnae_section` for size-bin specs (B.7) | Explicit `stop()` in 53 if a size-bin `sector_var` is passed |
| Plan expansion into a 31/33/34 rebuild | Out of scope; follow-up plan required |

---

## Open Questions

### Resolved during planning (all B-items confirmed 2026-04-14)
- B.1: Office-specific muni-employment windows (mayor and G/P separate).
- B.2: RAIS muni-m headcount for multi-muni firms.
- B.3: Regression weight only; `aggregation=employment` unchanged.
- B.4: Mean 2002–2017 RAIS employment, national, time-invariant per muni.
- B.5: `mxj_jxt` FE for sector interaction specs.
- B.6: Within-sector terciles (each sector's own thresholds), per election cycle.
- B.7: Goal (4) in script 52 only; 53 grain rebuild deferred.
- B.8: Pre-election mean `n_employees`, matching `30c`.
- B.9: `sample`/`muni_sample` dimensions in spec grids of 51/52/53.

### Deferred to implementation
- Exact `fixest` formula strings for interaction terms.
- Whether `emp_share_muni_pre` is stored as one or two columns (mayor vs. G/P) — resolve when reading weight dispatch in 51/52.
- Table filename tokens for new specs: follow `__<baseline>__<weighting>__<sample>__<exposure>.tex` convention.
- Small-sector edge case in `30d`: if a (sector, cycle) cell has < 3 firms, decide assign-all-to-T1 vs. warn-and-flag.

---

## Sources & References

- `CLAUDE.md`, `INSTRUCTIONS.md` — governing conventions (weighting, FE syntax, clustering).
- `paper/sections/regs.tex` — full specification.
  - §2.1 firm-level levels, firm-level pre-election window.
  - §2.3 sector-level levels, `w^ℓ_{jmp,t}` = owner-count-weighted average; `EC^ℓ_jm,t` bounded by 1 for pooled-count baseline.
  - §2.4 sector-level changes (inauguration-year variation).
  - §2.6 multi-muni firm caveat.
- Scripts verified:
  - `5_estimation/51_firm_first_stage.R:524–526, 686–696, 548–554` (weight logic).
  - `5_estimation/52_aggregated_firm_sector_first_stage.R:105–137, 538–562, 604–646` (weight + aggregation logic).
  - `5_estimation/53_sector_first_stage.R` (sector first stage, owner-count instrument taxonomy).
  - `3_instruments/30c_build_size_bin_mapping.R:7–8, 73–79` (national terciles per cycle).
  - `3_instruments/31_build_sector_exposure_weights.R:10, 128, 414` (owner-count weights; no muni-employment).
  - `3_instruments/33_select_baseline_weights.R:155–159, 220–240` (baseline windows).
  - `3_instruments/34_build_shift_share_instruments.R:102–110` (spread across terms).
  - `4_regression_panels/41_build_muni_panel.R:139–151` (contemporaneous `total_employment`).
  - `4_regression_panels/42_build_firm_panel.R:203–209, 301–328, 355–480` (`bl_n_employees`, `emp_share_muni_rais`, `is_multi_muni`).
  - `scripts/R/run_politicsregs.R:28–97` (driver, flag forwarding).
- Prior plans (`quality_reports/plans/`) — spec engine refactors for 51, 52, 53 (2026-03-23 to 2026-04-06).
- Memory: project pivot toward firm-level allocation due to >90% within-cell variance loss in sector pipeline (2026-04-02 note).
