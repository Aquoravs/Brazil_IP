# Testing Industrial Policy: Evidence from Brazil's BNDES

**Research question:** Does a politically driven exogenous shock to the sectoral composition of local economic activity affect municipal GDP, beyond the aggregate volume effect?

The full causal chain: political turnover → politically connected firms in some sectors receive marginally more BNDES credit → employment in those sectors expands → the sectoral composition of economic activity within the municipality shifts → municipal GDP changes. The primary endogenous variable is the vector of sector employment shares (the best available proxy for the sectoral distribution of local economic activity); BNDES credit reallocation is the mechanism that transmits the political shock to employment composition.

**Empirical strategy:** Linked IV specifications that build from micro validation to municipality-level optimality:

1. **Firm-level** (levels + changes, extensive + intensive): `FA_*` / `dFA_*` instruments predict BNDES access/amount
2. **Sector-level** (levels + changes): shift-share `Z_*` / `dZ_*` instruments predict the sector employment composition within the municipality (primary endogenous variable). The same instruments also predict BNDES sector credit shares — interpreted as a mechanism check on the upstream credit-reallocation link, not the primary estimand.
3. **Municipality-level second stage**: an Anderson-Rubin test of whether the politically driven shift in sector employment composition predicts municipal GDP, holding the volume channel (total BNDES disbursements / initial municipal GDP, a ratio) constant
4. **Null hypothesis** (optimality of the sectoral structure of the local economy): marginal compositional reallocation has zero GDP effect (beta ~ 0)

**Geographic unit:** municipality (5,570)
**Time coverage:** 2002-2017
**Key data sources:** BNDES indirect loans, RAIS employer-employee, TSE elections, IBGE municipal GDP/population

---

## Directory Structure

### `data/`

All project data. Raw inputs are never modified; processed outputs are reproducible from the pipeline.

#### `data/raw/`

| Directory / File | Contents |
|-----------------|----------|
| `bndes_indirect_auto/` | BNDES indirect loans (automatic operations), 2002-2025 |
| `bndes_indirect_nonauto/` | BNDES indirect loans (non-automatic operations), 2002-2025 |
| `david_ra/` | Political affiliation data, including `in_power_upd_2002_2019.qs2` (year-party-municipality level) |
| `mun_gdp/` | IBGE PIB Municipal .xls files (2002-2009 and 2010-2019), values in R$ 1,000 (nominal) |
| `ipca_202509SerieHist.xlsx` | BCB IPCA historical series (read with `skip=6`, annual average index, base year 2018) |

RAIS employment data (2002-2017) is accessed via encrypted mount (`ENCFS_MOUNT`), not stored in this directory.

#### `data/processed/`

Intermediate datasets produced by the pipeline. All files are `.qs2` (preferred) or `.fst` (for column-selective reads of large panels).

| File | Source Script | Description |
|------|--------------|-------------|
| `rais_bndes_reconstructed.qs2` (`.fst`) | 22 | Unified firm x municipality x year panel (RAIS + BNDES + owner affiliation) |
| `owner_aff_standardized.qs2` | 22 | Standardized owner affiliation data |
| `sector_group_mapping.qs2` | 30 | CNAE section to sector group crosswalk (21 sections to 11 groups) |
| `sector_exposure_weights_owner_grouped.qs2` | 31 | Sector-party exposure weights (owner-count, employment, equal-firm, binary variants) |
| `alignment_shocks.qs2` | 32 | Canonical alignment levels `align_*`, overlap states, and turnover shocks `dalign_*` |
| `baseline_sector_weights.qs2` (`_grouped`) | 33 | Baseline sector-party exposure weights (cycle-specific + 2002-fixed), all weight variants |
| `shift_share_instruments.qs2` (`_sector`, `_levels`, `_grouped`) | 34 | Shift-share instruments: `Z_*` / `dZ_*` plus employment, equal-firm, and binary variants |
| `shift_share_controls_sector.qs2` (`_grouped`) | 34 | Exposure controls (owner-count, employment, equal-firm, binary; generic + tier-specific) |
| `bndes_credit_shares.qs2` (`_grouped`) | 35 | Balanced BNDES credit shares `s_mjt` and `delta_s_mjt` (RAIS skeleton + zeros) |
| `firm_baseline_exposures.qs2` | 36 | Firm baseline party exposure weights |
| `firm_level_instruments.qs2` | 36 | Firm-level instruments `FA_*` (levels) and `dFA_*` (changes) |
| `muni_sector_panel.qs2` (`_grouped`) | 41 | Panel A: municipality x sector x year for regressions |
| `muni_panel_for_regs.qs2` (`_grouped`) | 41 | Panel B: municipality x year (wide format) with IPCA-deflated GDP, instruments, HHI |
| `firm_panel_for_regs.qs2` (`.fst`) | 42 | Firm regression panel with extensive/intensive margin outcomes and instruments |
| `firm_panel_for_regs_2002_fixed.qs2` (`.fst`) | 42 | Firm panel variant using fixed 2002 baseline weights |
| `population_ibge.qs2` | 41 | IBGE municipal population (via `basedosdados`, cached) |
| `transfers_ibge.qs2` | 41 | Municipal transfer data (optional, for placebo tests) |
| `bndes_firm_year_muni_sector.qs2` | 11 | Aggregated BNDES indirect loans at firm-year-municipality-sector level |
| `bndes_loan_level.qs2` | 11 | Loan-level BNDES data |
| `diagnostics/` | audits | Diagnostic outputs from audit scripts |

Files with `_grouped` suffix use `sector_group` (11 groups) instead of `cnae_section` (21 sections). Files with `_sample` suffix are 10% development subsamples.

### `scripts/`

#### `scripts/R/`

Pipeline scripts numbered for execution order. The orchestrator `run_politicsregs.R` runs them in sequence.

| Stage | Script | Purpose |
|-------|--------|---------|
| 11 | `1_loan_aggregation/11_process_bndes_indirect.R` | Aggregate BNDES indirect loans |
| 21 | `2_firm_panel/21_convert_merged_formats.R` | Convert original panel to fst format |
| 22 | `2_firm_panel/22_reconstruct_merged.R` | Reconstruct unified firm panel (RAIS + BNDES + owner), CNAE imputation |
| 30 | `3_instruments/30_build_sector_groups.R` | Build sector group crosswalk (21 CNAE sections to 10 active groups + XX residual) |
| 31 | `3_instruments/31_build_sector_exposure_weights.R` | Build sector-party exposure weights (owner-count, employment, equal-firm, binary) |
| 32 | `3_instruments/32_build_alignment_shocks.R` | Build canonical alignment levels, overlap states, and turnover shocks |
| 33 | `3_instruments/33_select_baseline_weights.R` | Select baseline weights (cycle-specific averaged over 4-year pre-election window + 2002-fixed) |
| 34 | `3_instruments/34_build_shift_share_instruments.R` | Build shift-share instruments: `Z_*` / `dZ_*` and all weight variants |
| 35 | `3_instruments/35_build_credit_shares.R` | Build balanced BNDES credit shares (RAIS skeleton + zeros) |
| 36 | `3_instruments/36_build_firm_level_instruments.R` | Build firm-level instruments: `FA_*` / `dFA_*` including interaction and binary variants |
| 41 | `4_regression_panels/41_build_muni_panel.R` | Build Panel A (municipality x sector x year) and Panel B (municipality x year, wide) |
| 42 | `4_regression_panels/42_build_firm_panel.R` | Build firm regression panel with extensive/intensive margin outcomes |
| 51 | `5_estimation/51_firm_first_stage.R` | Firm-level first stage (8-dimension spec engine) |
| 52 | `5_estimation/52_aggregated_firm_sector_first_stage.R` | Aggregated firm-to-sector first stage |
| 53 | `5_estimation/53_sector_first_stage.R` | Sector first stage (spec engine with multiple weight/baseline/FE variants) |
| 54 | `5_estimation/54_sector_second_stage.R` | Second stage: reduced form, scalar 2SLS, vector 2SLS |

Supporting directories:

| Directory | Contents |
|-----------|----------|
| `_utils/` | Shared utilities (`utils.R` defines path configuration, helper functions) |
| `_archive/` | Legacy scripts from previous researcher |
| `diagnostics/` | Audit scripts (`audit_3_instruments.R`, `audit_41_muni_panel.R`) |

#### Minimal Stage Chains

- **Firm first stage (51):** `22, 32, 36, 42, 51` (add `11` if BNDES aggregation not yet built)
- **Sector first stage (53):** `22, 30, 31, 32, 33, 34, 35, 41, 53` (skip `30` if using `cnae_section`)
- **Sector second stage (54):** full sector chain through `41`, then `54`

### `paper/`

LaTeX manuscript folder. Currently in skeleton form — no active draft. Will be populated when results are publication-ready.

| Directory / File | Contents |
|-----------------|----------|
| `latexmkrc` | Build configuration (XeLaTeX + biber) |
| `snapshots/` | Early draft versions: `main_2026_01.tex` and compiled PDF snapshot |

### `output/`

R pipeline output. Exploratory — not paper-ready. Gitignored; regenerated by running the pipeline.

| Directory | Contents |
|-----------|----------|
| `tables/` | Regression tables, summaries, and figures organized by pipeline stage: `firm/`, `sector/`, `sector_grouped/`, `agg_firm/`, `agg_firm_grouped/`, etc. |

### `docs/` — stable knowledge

Cite-able, edited-in-place documents. Anything not dated.

| File / Directory | Contents |
|-----------------|----------|
| `PROJECT_BLUEPRINT.md` | Argument map, F-links, decisions D1–D23, next action |
| `strategy/` | Load-bearing strategy memos (AR-test strategy, falsification, robustness, BNDES allocation logic) |
| `methodology/` | Compiled LaTeX technical notes (aggregation catalogue, Proposition 2, C3/C5/C6 explainer) |
| `data_memos/` | C6 (employment sources) and C7 (local deflators) memos |
| `archive/` | Superseded material (old roadmap, brainstorms, doubts, decisions) |

### `journal/` — time-stamped events

Append-only, dated filenames. The convention: if filename starts with a date, it lives here.

| Directory / File | Contents |
|-----------------|----------|
| `research_journal.md` | Cumulative agent invocation log |
| `knowledge.md` | Extracted conventions and findings |
| `plans/` | Implementation plans (`YYYY-MM-DD_*.md`, with `archive/` for completed plans) |
| `sessions/` | Session progress logs (`YYYY-MM-DD_*.md`) |
| `meetings/<date>/` | Per-meeting folder: `notes.md`, `tracker.md`, `slides[_variant].tex`, `build/` |
| `audits/` | One-off audit reports |

### `explorations/`

Research sandbox. Experimental work goes here first, not into production folders. See `.claude/rules/content-standards.md` for the exploration lifecycle and graduation protocol.

### Other Top-Level Files

| File | Purpose |
|------|---------|
| `INSTRUCTIONS.md` | Project configuration for AI agents |
| `Bibliography_base.bib` | Centralized BibTeX bibliography |
| `CHANGELOG.md` | Version history |

---

## Variable Dictionary

### Identifiers

| Variable | Description |
|----------|-------------|
| `cnae_section` | CNAE 2.0 section codes (letter A-U), used for both credit shares and exposure weights |
| `muni_id` | Municipality code (6-digit IBGE, integer) |
| `firm_id` | Firm identifier (integer, from RAIS) |
| `sector_group` | Grouped sector code: Ag, Mi, CL, CH, CA, UCo, Tr, Tp, MS, PSO, XX (from script 30) |

### Outcome Variables

| Variable | Description |
|----------|-------------|
| `has_bndes_fmt` | Indicator for positive BNDES credit at firm-municipality-year level (0/1), extensive margin |
| `log_bndes_fmt` | Log of BNDES credit (defined only when positive; `NA` otherwise), intensive margin |
| `delta_has_bndes_fmt` | Change in BNDES indicator (`has_bndes_t - has_bndes_{t-1}`), changes extensive margin |
| `delta_log_bndes_fmt` | Change in log BNDES (defined only when positive in both `t` and `t-1`; `NA` otherwise) |
| `s_mjt` | BNDES sector share: `bndes_mjt / bndes_mt` |
| `delta_s_mjt` | Yearly change in BNDES sector share within municipality; computed from shares only, never zero-filled from NA |
| `log_gdp_pc` | Log GDP per capita, IPCA-deflated to 2018 R$ |
| `delta_hhi` | Change in Herfindahl index of BNDES sector shares (scalar 2SLS endogenous variable) |
| `log_bndes_pc` | Log BNDES per capita (control for scale vs. composition effects) |

### Firm-Level Instruments

| Variable | Description |
|----------|-------------|
| `FA_mayor_*`, `FA_gov_*`, `FA_pres_*` | Firm-level levels instruments: baseline party exposure x alignment levels (spread across 4-year terms) |
| `FA_mayor_gov_*`, `FA_mayor_pres_*`, `FA_triple_*` | Interaction instruments for joint alignment states (combined term map with ~2-year stints) |
| `dFA_*` | Firm-level changes instruments: baseline party exposure x alignment turnover (non-zero only at inauguration years) |
| `FA_binary_*`, `dFA_binary_*` | Firm-level instruments using extensive-margin binary baseline exposure `tilde_omega_fp = mean(1(L_fp > 0))` |

### Sector-Level Instruments

| Variable | Description |
|----------|-------------|
| `Z_mayor_coalition`, `Z_gov_coalition`, `Z_pres_coalition` | Sector-level levels shift-share instruments (alignment levels x baseline exposure weights, spread across terms) |
| `dZ_mayor_coalition`, `dZ_gov_coalition`, `dZ_pres_coalition` | Sector-level changes shift-share instruments (alignment turnover x baseline weights, inauguration years only) |
| `Z_emp_*`, `dZ_emp_*` | Sector instruments using employment-weighted baseline exposure |
| `Z_firm_*`, `dZ_firm_*` | Sector instruments using equal-firm baseline exposure |
| `Z_binary_*`, `dZ_binary_*` | Sector instruments using binary firm-connection baseline exposure |
| `Z_*_cycle_specific`, `dZ_*_cycle_specific` | Instruments with cycle-specific baseline weights |
| `Z_*_2002_fixed`, `dZ_*_2002_fixed` | Instruments using fixed 2002 baseline weights (robustness) |

### Exposure Weights and Baselines

| Variable | Description |
|----------|-------------|
| `L_fp_0` | Baseline affiliated owners in party p for firm f (averaged over 4-year pre-election window) |
| `L_mjp_0` | Baseline affiliated count in party p, sector j, municipality m (averaged over pre-election window) |
| `w_mjp`, `w_mjp_emp`, `w_mjp_firm`, `w_mjp_binary` | Year-level sector-party exposure weights (owner-count primary, plus employment, equal-firm, binary) |
| `w_rjp_0`, `w_rjp_emp_0`, `w_rjp_firm_0`, `w_rjp_binary_0` | Baseline sector-party exposure weights from script 33 |
| `exposure_control_*` | Sum of baseline party-exposure weights (controls for overall political connectedness, excluding "No party") |
| `exposure_control_binary` | Firm-level sum of binary baselines across parties (can exceed 1 for multi-party firms) |

### Alignment Variables

| Variable | Description |
|----------|-------------|
| `align_mayor_*`, `align_gov_*`, `align_pres_*` | Alignment level columns spread across 4-year electoral terms |
| `align_mayor_pres_*`, `align_triple_*` | Overlap alignment states |
| `dalign_*` | Alignment turnover shocks (non-zero only at inauguration years) |

### Panel Indicators and Controls

| Variable | Description |
|----------|-------------|
| `in_bndes`, `in_rais`, `in_owner` | Source indicator flags (0/1) in reconstructed panel |
| `is_multi_muni` | Per-year flag (0/1) for firms operating in 2+ municipalities |
| `n_employees` | Employment count (enters as regression weights in firm first stage) |

---

## Key Design Decisions

1. **Firm-to-sector logic:** The firm-level regressions are the micro-foundation. The sector-level shift-share is the aggregation of firm-level political exposures.

2. **Balanced panel with zeros:** Script 35 builds a RAIS-based skeleton (all CNAE sections active in each municipality x all years), filling sectors with no BNDES as zero. Ensures shares sum to 1 and `delta_s_mjt` captures the extensive margin.

3. **Instrument spreading:** Levels instruments (`FA_*`, `Z_*`) spread across full 4-year electoral terms. Changes instruments (`dFA_*`, `dZ_*`) are non-zero only at inauguration years (not spread). The 2003 gov/pres cycle is dropped (no baseline data).

4. **GDP deflation:** Nominal GDP deflated to 2018 R$ using annual average IPCA index.

5. **Dropped sector (simplex constraint):** For `delta_s` specifications, one sector is dropped per municipality-year (largest mean share). Coefficients are relative to the dropped sector.

6. **Share vs. delta imputation:** `s_mjt = 0` is valid when a RAIS-active cell has no BNDES. `delta_s_mjt = 0` must come only from computed subtraction, never from zero-fill.

7. **Employment weighting:** Enters through regression weights (`n_employees`) in the firm first stage, not through instrument construction.

8. **Extensive vs. intensive margin:** Firm specifications decompose into extensive (LPM indicator) and intensive (log BNDES conditional on positive).

9. **Pooled-count baselines:** Baseline weights use pooled counts over 4-year pre-election window. Uses all available years >= 2002. For mayor 2004 election, only 2002-2003 available; for gov/pres 2002 election, cycle dropped entirely.

10. **Interaction instruments:** Joint alignment instruments (`FA_mayor_gov_*`, etc.) use combined term maps with ~2-year stints per inauguration.

---

## Path Configuration

All R scripts source `_utils/utils.R` which reads environment variables:

| Variable | Purpose | Default |
|----------|---------|---------|
| `BNDES_BASE` | Root data folder | `~/BNDES` |
| `BNDES_OUTPUT` | Processed output folder | `$BNDES_BASE/output` |
| `BNDES_TABLES` | Regression table output | `output/tables/` |
| `ENCFS_MOUNT` | Encrypted RAIS mount | (none) |

Helper functions: `raw_path()`, `output_path()`, `tables_path()`, `project_path()`

---

## Data Notes

- BNDES loan data: 2002-2025. Early years may group loans under financial intermediaries rather than actual firms.
- RAIS employment data: accessed via encrypted mount, restricted access (2002-2017).
- ~10% of firms lack CNAE codes; recovered via imputation cascade: (1) owner affiliation cnae5, (2) within-RAIS modal section per firm, (3) Receita Federal PostgreSQL lookup.
- 99.6% of firm-years have a single CNAE section; modal assignment is appropriate for rare multi-section cases.
- BigQuery downloads via `basedosdados` produce `integer64` columns; after qs2 reload, use `bit64::as.integer64()` to recover class before converting.
- Population match rate: 99.9% of municipality-years. Transfer match rate: 96.3%.
- `sum_j delta_s_mjt` may equal +1 or -1 in municipality-years entering/exiting zero-total BNDES (valid transitions); first-year or undefined deltas must never be coerced to zero.
- Git LFS used for large data files.
