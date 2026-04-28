## Project Overview

**Research question**: Is the allocation of BNDES lending across municipalities GDP-optimal?

**Empirical strategy**: linked IV specifications that build from micro validation to municipality-level optimality:
- Firm-level, levels, extensive: `FA_*` → `1(BNDES > 0)` (LPM, full panel)
- Sector-level, levels: alignment levels interacted with sector baseline exposure weights → BNDES sector share within municipality
- Sector-level, changes: alignment turnover interacted with sector baseline exposure weights → yearly change in BNDES sector share within municipality
- Municipality-level second stage: predicted sectoral reallocation or scalar summaries of it → change in municipality GDP per capita
- Null hypothesis (optimality): marginal reallocation has zero GDP effect (beta ~ 0)

**Geographic unit**: municipality
**Time coverage**: 2002-2017
**Key data sources**: BNDES indirect loans, RAIS employer-employee, TSE elections, IBGE municipal GDP, IBGE municipal population

## Current Focus

Establish a defensible first stage by following the paper's sequence:
1. Verify that the existing scripts correctly and efficiently implement the intended design.
2. Validate the political-lending link at the firm level.
3. Aggregate consistently to the sector level and estimate the municipality-sector first stage.
4. Only then proceed to reduced form / 2SLS optimality analysis at the municipality level.

- **Micro validation comes first**: the firm-level regressions are the micro-foundation for the sector-level shift-share design
- **Primary shift variable**: political alignment turnover `ΔAlign_mtp` at the municipality-party-year level
- **Primary levels shifter**: political alignment level `Align_mtp` spread across the full electoral term
- **Primary share variable, firm level**: `L_fp,0 / L_f,0` (averaged over 4-year pre-election window)
- **Primary share variable, sector level**: baseline sector-party exposure weights by municipality, cycle-specific (averaged over 4-year window) and 2002-fixed
- **Employment weighting**: enters via regression weights (`n_employees`) in the firm first stage; the sector pipeline uses owner-count exposure weights (`Z_*` for levels, `dZ_*` for changes)
- **Outcome**: `log_gdp_pc` — IBGE municipal GDP deflated by IPCA to 2018 R$ divided by IBGE municipal population
- **Main endogenous variables**: `s_mjt`, `delta_s_mjt`, and scalar summaries such as `delta_hhi`
- **Main regression panels**:
  - Firm panel: firm × municipality × year
  - Panel A: municipality × sector × year
  - Panel B: municipality × year, wide format
- **Primary FE, firm level**: firm + municipality×year
- **Primary FE, sector level**: municipality×sector + sector×year
- **Robustness FE, sector level**: municipality×sector + municipality×year
- **Standard errors**: two-way clustered by firm and municipality (firm specs), by municipality and sector (Panel A), by municipality (Panel B)
- **Key script(s) that need revision**: first audit the existing sector pipeline (`31-35`, `41`, `53`, `54`, plus `audit_3_instruments` and `audit_41_muni_panel`), then build the firm-level pipeline (`36`, `42`, `51`)

### Key Design Decisions (see also `docs/doubts.md`)

1. **Firm-to-sector logic**: validate first that political alignment predicts firm-level BNDES lending. The sector-level shift-share should be interpretable as the aggregation of these firm-level political exposures.
2. **Balanced panel with zeros**: Script 35 builds a RAIS-based skeleton (all CNAE sections active in each municipality) × all years, fills sectors with no BNDES loans as zero. This ensures shares sum to 1 over economically relevant sectors and `delta_s_mjt` captures the extensive margin.
3. **Instrument spreading**: Alignment shocks occur at inaugurations only. **Levels instruments** (`FA_*`, `Z_*`) are spread across the full 4-year electoral term (mayor: 2005-2008, 2009-2012, ...; gov/pres: 2003-2006, 2007-2010, ...). **Changes instruments** (`dFA_*`, `dZ_*`) are NOT spread — they are non-zero only at inauguration years (2005, 2009, 2013, 2017 for mayor; 2007, 2011, 2015 for gov/pres). The 2003 gov/pres cycle is dropped entirely (no baseline data available). Interaction FA instruments (`FA_mayor_gov_*`, etc.) use a `combined_term_map` with ~2-year stints per inauguration.
4. **GDP deflation**: Nominal GDP deflated to 2018 R$ using annual average IPCA index (from `raw/ipca_202509SerieHist.xlsx`). Pattern reused from script 11.
5. **Dropped sector (simplex constraint)**: For municipality-years with positive total BNDES in both `t-1` and `t`, `Δs` sums to 0 within muni-year, so one sector `j0` must be dropped in vector specifications. Currently: sector with largest mean share (determined empirically in script 41, saved as attribute). Coefficients are relative to the dropped sector.
7. **Share vs. delta imputation rule**: It is acceptable to infer `s_mjt = 0` when a RAIS-active municipality-sector-year has no BNDES credit. It is not acceptable to infer `delta_s_mjt = 0` from missingness created by merges, reshapes, or widening. `delta_s_mjt` must come only from observed subtraction of two share values. Valid zeroes in `delta_s_mjt` are computed outcomes, not fill values.
6. **Employment weighting**: enters through analytic regression weights (`n_employees`) in the firm first stage, not through separate employment-weighted instrument columns. The employment-weighted average of firm instruments within (sector, municipality) naturally recovers a sector-level instrument with employment-weighted exposure shares. The sector pipeline uses owner-count weights as a complementary specification.
8. **Extensive vs. intensive margin**: firm-level specifications decompose the effect into extensive margin (indicator `1(BNDES > 0)`, LPM) and intensive margin (`log(BNDES)`, conditional on positive). Changes specifications follow the same decomposition. This reveals whether alignment operates through access to credit or loan size.
9. **Pooled-count baselines**: Baseline party-exposure weights use pooled counts over a 4-year pre-election window `[election_year - 4, election_year - 1]`: `omega_fp = sum_s(L_fp_s) / sum_s(L_f_s)` for firms, `w_rjp = sum_s(L_rjp_s) / sum_s(N_rj_s)` for sectors, where `s` indexes years in the window. This weights each owner-year observation equally, so years with more owners contribute more. Uses all available years ≥ 2002. For mayor treatment 2005-2008 (election 2004), the window is 2000-2003, but only 2002-2003 are available. For gov/pres treatment 2003-2006 (election 2002), the full window 1998-2001 has no data, so this cycle is dropped entirely. This applies to both firm-level (script 36) and sector-level (script 33) baselines.
10. **Interaction instruments**: Script 36 produces interaction instruments for joint alignment states: `FA_mayor_gov_*`, `FA_mayor_pres_*`, and `FA_triple_*`. Interaction FA instruments use a `combined_term_map` where each inauguration's effect spans ~2 years until the next tier inaugurates, with baselines shifting at each inauguration. `_only` overlap variants are not part of the current firm first-stage analysis.

## Variable Naming Conventions

- `cnae_section` — CNAE 2.0 section codes (letter A-U), used consistently for both credit shares and exposure weights
- `muni_id` — municipality code (6-digit IBGE, integer)
- `firm_id` — firm identifier (integer, from RAIS)
- `has_bndes_fmt` — indicator for positive BNDES credit at the firm-muni-year level (0/1), extensive margin outcome
- `log_bndes_fmt` — log of BNDES credit (defined only when positive; `NA` otherwise), intensive margin outcome
- `delta_has_bndes_fmt` — change in BNDES indicator (`has_bndes_t - has_bndes_{t-1}`), changes extensive margin
- `delta_log_bndes_fmt` — change in log BNDES (defined only when positive in both `t` and `t-1`; `NA` otherwise), changes intensive margin
- `delta_s_mjt` — yearly change in BNDES sector share within municipality (endogenous variable); compute from shares only, never by NA-to-zero fill
- `s_mjt` — BNDES sector share: bndes_mjt / bndes_mt
- `FA_*` — firm-level levels instruments: firm baseline party exposure interacted with alignment levels (single-tier: `FA_mayor_*`, `FA_gov_*`, `FA_pres_*`; interactions used in analysis: `FA_mayor_gov_*`, `FA_mayor_pres_*`, `FA_triple_*`)
- `dFA_*` — firm-level changes instruments: firm baseline party exposure interacted with alignment turnover (same tiers and interactions as `FA_*`); non-zero only at inauguration years (not spread across terms)
- `FA_binary_*`, `dFA_binary_*` — firm-level instruments using extensive-margin (binary) baseline exposure `tilde_omega_fp = mean(1(L_fp > 0))` instead of pooled-count shares; same naming pattern as `FA_*`/`dFA_*` with `_binary_` infix
- `exposure_control_binary` — firm-level sum of binary baselines across parties (`sum_p binary_fp_0`, excluding "No party"); can exceed 1 for multi-party firms
- `Z_*` — sector-level **levels** shift-share instruments (alignment levels × baseline exposure weights); spread across 4-year electoral terms (`Z_mayor_coalition`, `Z_gov_coalition`, `Z_pres_coalition`)
- `dZ_*` — sector-level **changes** shift-share instruments (alignment turnover × baseline exposure weights); non-zero only at inauguration years (not spread) (`dZ_mayor_coalition`, `dZ_gov_coalition`, `dZ_pres_coalition`)
- `Z_emp_*`, `dZ_emp_*` — sector-level instruments using employment-weighted baseline exposure weights
- `Z_firm_*`, `dZ_firm_*` — sector-level instruments using equal-firm baseline exposure weights
- `Z_binary_*`, `dZ_binary_*` — sector-level instruments using binary firm-connection baseline exposure weights
- `Z_*_cycle_specific`, `dZ_*_cycle_specific` — sector-level instruments with cycle-specific baseline weights
- `Z_*_2002_fixed`, `dZ_*_2002_fixed` — instruments using fixed 2002 baseline weights (robustness)
- `L_mjp_0` — baseline affiliated count in party p, sector j, muni m (averaged over 4-year pre-election window)
- `L_fp_0` — baseline affiliated owners in party p for firm f (averaged over 4-year pre-election window)
- `w_mjp`, `w_mjp_emp`, `w_mjp_firm`, `w_mjp_binary` — year-level sector-party exposure weights from script 31 (owner-count primary, plus employment, equal-firm, and binary variants)
- `w_rjp_0`, `w_rjp_emp_0`, `w_rjp_firm_0`, `w_rjp_binary_0` — baseline sector-party exposure weights from script 33
- `dalign_*` — alignment turnover shock columns; canonical changes naming for both single-tier and overlap states
- `align_*` — alignment level columns spread across the relevant electoral term; canonical levels naming (`align_mayor_*`, `align_gov_*`, `align_pres_*`, plus overlap states such as `align_mayor_pres_*` and `align_triple_*`)
- `log_gdp_pc` — log GDP per capita, IPCA-deflated to 2018 R$ (outcome)
- `delta_hhi` — change in Herfindahl index of BNDES sector shares (scalar 2SLS endogenous var)
- `log_bndes_pc` — log BNDES per capita (control for scale vs. composition effects)
- `in_bndes`, `in_rais`, `in_owner` — source indicator flags (0/1) in reconstructed panel
- `sector_group` — grouped sector code (Ag, Mi, CL, CH, CA, UCo, Tr, Tp, MS, PSO, XX) from script 30
- `is_multi_muni` — per-year flag (0/1) for firms operating in 2+ municipalities; used for single-muni robustness subsample
- `exposure_control_*` — sum of baseline party-exposure weights within a municipality-sector cell; controls for overall political connectedness, excluding "No party". Script 34 now emits owner-count, employment, equal-firm, and binary variants, plus tier-specific `_mayor` / `_gov_pres` versions used in script 53.

## Coding Conventions

- R packages: `data.table` preferred for data manipulation, `fixest` for regressions
- qs2 files preferred for data storage; fst for column-selective reads of large panels
- Standard errors: two-way clustered by `muni_id` and `cnae_section` (Panel A); by `muni_id` (Panel B)
- Firm-level regressions: use `firm_id + muni_id^year` as primary FE and two-way clustering by `firm_id` and `muni_id`
- When writing new pipeline stages, follow the numbering convention (folder/stage_number prefix)
- Sector definition: always use RAIS CNAE section (not BNDES project CNAE)
- Firm identifiers are integers (`as.integer(firm_id)`), not zero-padded strings
- Owner affiliation data is firm-level: merge on `(firm_id, year)`, not `(firm_id, muni_id, year)`
- BigQuery/qs2 integer64 columns: after qs2 reload, use `bit64::as.integer64()` to reattach class before converting (raw bits survive but class is lost)
- FE syntax in fixest: use `muni_id^cnae_section` for interaction FE (not manual paste columns)
- F-statistics: use `fixest::wald(mod, keep = "^(dZ_|Z_)")$stat` for sector regressions, not `summary(mod)$fstatistic`
- For firm-level F-statistics, use `fixest::wald(mod, keep = "^(FA_|dFA_)")$stat`
- Employment weighting enters through regression weights (`n_employees`) in the firm first stage, not through separate instrument columns; the sector pipeline uses owner-count instruments (`Z_*` for levels, `dZ_*` for changes)
- Firm-level instrument construction is not employment-weighted; employment enters firm-level estimation as regression weights when running the main firm specifications
- Scripts 31, 33-35, 41, 53, 54 accept `--sector-var=sector_group` to run with grouped sectors (forwarded via `--` in orchestrator)
- Script 51 uses an 8-dimension spec engine with `--specs=`, dimension overrides (`--margin=`, `--exposure=`, `--weighting=`, `--baseline=`, `--alignment=`, `--time-variation=`/`--time_variation=`, `--sample=`, `--family=`), plus `--test` and `--dry-run`; firm first-stage outputs use canonical `firm__...` filenames and a run manifest.
- Script 53 now uses a sector spec engine with `--specs=` and dimension overrides (`--time-variation=`/`--time_variation=`, `--instrument-weight=`/`--instrument_weight=`, `--baseline=`, `--alignment=`, `--fe=`, `--exposure-control=`/`--exposure_control=`), plus `--test` (10% municipality subsample) and `--dry-run`; canonical outputs are `sector__<time_variation>__<instrument_weight>__<alignment>__<baseline>__<fe>__<ctrl>.tex`, with per-run manifest and coefficient-summary artifacts.
- Script 30 builds the sector group crosswalk; it runs automatically before 31 when using `30:54 --sector-var=sector_group`
- In wide panels, zero-fill is allowed for `s_*` columns and instrument columns, but not for `delta_s_*`; undefined deltas must remain `NA`

## Build and Run Commands

### R Pipeline (Main Analysis)

```bash
# Set environment variables first
export BNDES_BASE="/path/to/BNDES"
export BNDES_OUTPUT="$BNDES_BASE/output"
export ENCFS_MOUNT="/proj/patkin/juan/encfs_mount"  # for RAIS data access

# Run full pipeline
Rscript BNDES/politicsregs/run_politicsregs.R all

# Audit current sector pipeline before extending it
Rscript BNDES/politicsregs/run_politicsregs.R 31:35 --audits=auto
Rscript BNDES/politicsregs/run_politicsregs.R 41,53,54 --dryrun

# Run sector pipeline through estimation
Rscript BNDES/politicsregs/run_politicsregs.R 31:54

# Run firm validation pipeline
Rscript BNDES/politicsregs/run_politicsregs.R 22,32,36,42,51

# Run firm + sector pipeline end-to-end
Rscript BNDES/politicsregs/run_politicsregs.R 31:54

# Run specific stages
Rscript BNDES/politicsregs/run_politicsregs.R 21,41,53

# Dry run (print commands only)
Rscript BNDES/politicsregs/run_politicsregs.R 21:54 --dryrun

# Default firm first stage (baseline bundle)
Rscript BNDES/politicsregs/run_politicsregs.R 51

# Run specific spec bundles / dimensions for script 51
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=baseline,changes
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=weighted
Rscript BNDES/politicsregs/run_politicsregs.R 51 --family=interaction --exposure=pooled_count
Rscript BNDES/politicsregs/run_politicsregs.R 51 --test
Rscript BNDES/politicsregs/run_politicsregs.R 51 --dry-run

# Run specific spec bundles (script 53)
Rscript BNDES/politicsregs/run_politicsregs.R 53 -- --specs=all
Rscript BNDES/politicsregs/run_politicsregs.R 53 -- --specs=weight_battery
Rscript BNDES/politicsregs/run_politicsregs.R 53 -- --specs=baseline --instrument-weight=owner_count,employment,equal_firm,binary
Rscript BNDES/politicsregs/run_politicsregs.R 53 -- --specs=baseline --fe=mxj_mxt --alignment=party
Rscript BNDES/politicsregs/run_politicsregs.R 53 -- --specs=baseline --test
Rscript BNDES/politicsregs/run_politicsregs.R 53 -- --specs=all --dry-run

# Run grouped sector pipeline (sector_group instead of cnae_section)
Rscript BNDES/politicsregs/run_politicsregs.R 30:54 --sector-var=sector_group
```

### Minimal Stage Chains

- **Firm first stage (`51_firm_first_stage.R`)**: run `22`, `32`, `36`, `42`, `51`. If `22` has not been built yet from raw inputs, also run `11` first because script 22 depends on the aggregated BNDES file from script 11.
- **Sector first stage (`53_sector_first_stage.R`) with default `sector_group`**: run `22`, `30`, `31`, `32`, `33`, `34`, `35`, `41`, `53`. If `22` has not been built yet from raw inputs, also run `11` first. If you explicitly use `--sector-var=cnae_section`, script `30` is not required.
- **Sector second stage (`54_sector_second_stage.R`)**: run the full sector first-stage chain through `41`, then `54`. Script `54` reads Panel B from script `41`.

## Architecture

### Key Pipeline Stages (BNDES/politicsregs/)

Scripts are numbered for execution order. The orchestrator `run_politicsregs.R` runs them in sequence. Folder N contains scripts N1, N2, etc. Legacy scripts are archived in `_archive/`.

| Stage | Script | Purpose |
|-------|--------|---------|
| 11 | `1_loan_aggregation/11_process_bndes_indirect.R` | Aggregate BNDES indirect loans |
| 21 | `2_firm_panel/21_convert_merged_formats.R` | Convert original panel to fst format to reconstruct it |
| 22 | `2_firm_panel/22_reconstruct_merged.R` | Reconstruct unified firm panel (RAIS + BNDES + owner), CNAE imputation |
| 30 | `3_instruments/30_build_sector_groups.R` | Build sector group crosswalk (21 CNAE sections → 10 active groups + XX residual; Ag/Mi split, K/O dropped to XX, Manufacturing split 3 ways) |
| 31 | `3_instruments/31_build_sector_exposure_weights.R` | Build sector-party exposure weights from reconstructed panel, including owner-count, employment, equal-firm, and binary variants |
| 32 | `3_instruments/32_build_alignment_shocks.R` | Build canonical alignment levels `align_*`, overlap states, and turnover shocks `dalign_*` from `in_power_upd_2002_2019.qs2` |
| 33 | `3_instruments/33_select_baseline_weights.R` | Select baseline weights (cycle-specific averaged over the 4-year pre-election window, plus 2002-fixed) for owner-count, employment, equal-firm, and binary variants |
| 34 | `3_instruments/34_build_shift_share_instruments.R` | Build shift-share instruments: `Z_*` / `dZ_*` plus `Z_emp_*`, `Z_firm_*`, `Z_binary_*` and matching changes variants; also emits weight-variant-specific exposure controls |
| 35 | `3_instruments/35_build_credit_shares.R` | Build balanced BNDES credit shares (RAIS skeleton + zeros), s_mjt and delta_s_mjt |
| 36 | `3_instruments/36_build_firm_level_instruments.R` | Build firm-level instruments: `FA_*` (levels, spread) and `dFA_*` (changes, inauguration only); includes interaction instruments used in analysis (MxG, MxP, triple) and binary baseline variants (`FA_binary_*`, `dFA_binary_*`) |
| 41 | `4_regression_panels/41_build_muni_panel.R` | Build Panel A (muni×sector×year) and Panel B (muni×year, wide format) with IPCA-deflated GDP, population, instruments, HHI; Panel A carries all sector weight variants, Panel B keeps the legacy owner-count muni instruments |
| 42 | `4_regression_panels/42_build_firm_panel.R` | Build firm regression panel with extensive/intensive margin outcomes and firm-level instruments |
| 51 | `5_estimation/51_firm_first_stage.R` | Firm-level first stage spec engine: 8-dimension config grid, canonical `firm__...` outputs, per-config timing, run manifest, `--test` dev sample, and batched `fixest` estimation |
| 52 | `5_estimation/52_aggregated_firm_sector_first_stage.R` | Aggregated firm→sector first stage: H_jmt (pre-election firm BNDES share) on averaged FA instruments with muni×year FE |
| 53 | `5_estimation/53_sector_first_stage.R` | Sector first stage spec engine: changes/levels, four instrument-weight variants, two baselines, coalition/party alignment, three FE choices, optional exposure controls, `--test`, `--dry-run`, canonical `sector__...` outputs, and a run manifest |
| 54 | `5_estimation/54_sector_second_stage.R` | Second stage: reduced form, scalar 2SLS (HHI), vector 2SLS (J-1 sectors), robustness |

Standalone diagnostics:
- `diagnostics/audit_3_instruments.R` — audit gate for scripts 31-35 outputs (run via `run_politicsregs.R` with `--audits=auto` or explicitly as `audit_3_instruments`)
- `diagnostics/audit_41_muni_panel.R` — stage-41 audit for Panel A / Panel B preservation checks (run via `run_politicsregs.R` with `--audits=auto` or explicitly as `audit_41_muni_panel`); verifies that wide `delta_s_*` columns are not zero-filled when undefined

### Key Output Files

- `output/rais_bndes_reconstructed.qs2` (.fst) — Unified firm×muni×year panel from script 22
- `output/baseline_sector_weights.qs2` — Sector-party exposure weights (L_mjp,0 / D_m,0)
- `output/alignment_shocks.qs2` — Canonical alignment panel with `align_*` levels, overlap states, and `dalign_*` turnover shocks
- `output/shift_share_instruments.qs2` — Muni-level instruments (levels `Z_*` and changes `dZ_*`; owner-count retained for Panel B)
- `output/shift_share_instruments_sector.qs2` — Sector-level instruments (owner-count plus employment, equal-firm, and binary variants)
- `output/firm_level_instruments.qs2` — Firm-level instruments `FA_*` and `dFA_*`
- `output/bndes_credit_shares.qs2` — Balanced credit shares s_mjt and delta_s_mjt (RAIS skeleton + zeros)
- `output/sector_group_mapping.qs2` — CNAE section → sector group crosswalk (script 30)
- `output/exposure_control_sector.qs2` — Sector exposure controls (owner-count, employment, equal-firm, binary; generic plus tier-specific variants)
- `output/muni_sector_panel.qs2` — Panel A for regressions (muni × sector × year, ~1.37M rows after NA drop)
- `output/muni_panel_for_regs.qs2` — Panel B for regressions (muni × year, wide format with sector columns)
- `output/firm_panel_for_regs.qs2` — Firm panel for regressions (firm × muni × year)
- `output/firm_reg_tables/` — Firm first-stage regression tables with canonical `firm__<family>__<time_variation>__<margin>__<alignment>__<baseline>__<weighting>__<sample>__<exposure>.tex/.md` filenames
- `output/firm_reg_tables/firm_run_manifest.csv` / `.qs2` — Per-config execution manifest with status, timing, and artifact paths
- `output/firm_reg_tables/fc_battery_summary.qs2` — Firm first-stage coefficient summary across all successful configs
- `output/muni_reg_tables/sector_run_manifest.csv` / `.qs2` — Per-config sector first-stage manifest with status, timing, F-stat ranges, and degeneracy warnings
- `output/muni_reg_tables/sector_fc_battery_summary.qs2` — Sector first-stage coefficient summary across all successful configs
- `output/population_ibge.qs2` — Cached population data (downloaded via basedosdados; integer64 columns need bit64 on reload)
- `output/transfers_ibge.qs2` — Cached municipal transfer data (from basedosdados br_me_siconfi; optional, for placebo tests)
- `output/muni_reg_tables/` — Regression tables (markdown and LaTeX)
- `docs/doubts.md` — Open design decisions and assumptions
- `docs/shift_share.md` — Shift-share instrument construction notes
- `paper/presentation_progress.tex` — Beamer presentation of progress for advisors
- `paper/draft.tex` — Paper draft

### Path Configuration

All R scripts source `_utils/utils.R` which defines:
- `BNDES_BASE` - Root data folder (env: `BNDES_BASE`, default: `~/BNDES`)
- `OUTPUT_DIR` - Output folder (env: `BNDES_OUTPUT`, default: `$BNDES_BASE/output`)
- `ENCFS_MOUNT` - Encrypted RAIS mount (env: `ENCFS_MOUNT`)

No Python scripts remain in the active pipeline.

## Data Notes

- Legacy scripts from the previous researcher are archived in `BNDES/politicsregs/_archive/`
- BNDES loan data: 2002-2025, stored in `raw/bndes_indirect_auto/` and `raw/bndes_indirect_nonauto/`
- RAIS employment data: accessed via encrypted mount, 2002-2017. Access is restricted; only request if strictly necessary.
- Political affiliation data: `raw/david_ra/` folder — includes `in_power_upd_2002_2019.qs2` (year-party-muni level)
- GDP data: `raw/mun_gdp/` — IBGE PIB Municipal .xls files (2002-2009 and 2010-2019), values in R$ 1,000 (nominal). Deflated to 2018 R$ using IPCA in script 41.
- IPCA deflator: `raw/ipca_202509SerieHist.xlsx` — BCB historical series, read with skip=6, annual average index computed, base year 2018
- Population data: downloaded via `basedosdados` R package (BigQuery, billing project: `replication-paiva-2025`), cached as `output/population_ibge.qs2`
- Transfer data: downloaded via `basedosdados` (table `br_me_siconfi.municipio_receitas_orcamentarias`), cached as `output/transfers_ibge.qs2` (optional, for exclusion restriction placebo)
- Uses Git LFS for large data files
- CNAE imputation in script 22: cascade of (1) owner affiliation cnae5, (2) within-RAIS modal cnae_section per firm_id, (3) Receita Federal PostgreSQL lookup (localhost, dbname=Dados_RFB)
- Known data quality issues:
  - ~10% of firms lack CNAE codes; recovered via imputation cascade above
  - The earliest years of BNDES data don't reflect the actual firm that got a loan (grouped under financial intermediary)
  - 99.6% of firm-years have a single CNAE section; modal assignment per firm is appropriate for the rare multi-section cases
  - BigQuery downloads via basedosdados produce integer64 columns; after qs2 save/reload the class is lost but raw bits remain. Must use `bit64::as.integer64()` to recover before converting to integer/numeric.
  - Population match rate: 99.9% of muni-years after integer64 fix
  - Transfer match rate: 96.3% of muni-years
  - Audit finding from 2026-03-11: `sum_j delta_s_mjt` may equal `+1` or `-1` in municipality-years entering or exiting zero-total BNDES; those are valid transitions, but first-year or otherwise undefined deltas must never be coerced to zero in Panel B
