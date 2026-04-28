# Shift-share design: updated specification and pipeline map

## 1) Linked specifications (micro to macro)

The empirical design has six linked first-stage specifications:

1. Firm levels, extensive: `has_bndes_fmt` on `FA_*` (LPM, full panel).
2. Firm levels, intensive: `log_bndes_fmt` on `FA_*` (conditional on `BNDES > 0`).
3. Firm changes, extensive: `delta_has_bndes_fmt` on `dFA_*`.
4. Firm changes, intensive: `delta_log_bndes_fmt` on `dFA_*` (conditional on positive in `t` and `t-1`).
5. Sector levels: `s_mjt` on levels shift-share instrument `Z_*`.
6. Sector changes: `delta_s_mjt` on turnover shift-share instrument `dZ_*`.

The firm specifications provide the micro-foundation for the sector reallocation design.

## 2) Common sector definition

The sector definition is always derived from the RAIS CNAE section (`cnae_section`, letters A-U), not BNDES project CNAE.

Data flow:

1. Script 22 (`22_reconstruct_merged.R`) reconstructs the firm panel and assigns each firm-year a RAIS sector.
2. Script 35 (`35_build_credit_shares.R`) aggregates BNDES credit to municipality-sector-year using that RAIS sector assignment.
3. Script 31 (`31_build_sector_exposure_weights.R`) builds sector-party baseline exposure weights with the same sector classification.

Using one sector definition for both the endogenous shares and the instruments preserves the shift-share interpretation.

## 3) Political shocks and baseline timing

For office tier `ell in {mayor, governor, president}` and party `p`:

- Levels alignment: `Align_{mpt}^ell`
- Turnover alignment: `dAlign_{mpt}^ell = Align_{mpt}^ell - Align_{mp,t-1}^ell`

**Levels** alignment shocks are spread across full terms (4 years), so inauguration shocks persist for the full electoral cycle. **Changes** (turnover) shocks are NOT spread — they are non-zero only at inauguration years (2005, 2009, 2013, 2017 for mayor; 2007, 2011, 2015 for gov/pres). The 2003 gov/pres cycle is dropped entirely (no pre-election data available).

Baselines are predetermined and **pooled over a 4-year pre-election window** `[election_year - 4, election_year - 1]`:

- Primary: cycle-specific averaged baseline using all available years ≥ 2002 in the window. For mayor treatment 2005-2008 (election 2004), the window is 2000-2003 but only 2002-2003 are used.
- Robustness: fixed 2002 baseline.

## 4) Firm-level instrument construction (script 36)

Define firm-party exposure at baseline using pooled counts over a 4-year window:

`omega_{fp,tau} = [sum_{s in T_tau} L_{f,p,s}] / [sum_{s in T_tau} L_{f,s}]`

where `T_tau` is the set of available years in `[election_year - 4, election_year - 1]` (clipped to ≥ 2002), and `L_{f,s}` includes all owners (including "No party"). Unaffiliated owners contribute zero to instruments because they have no alignment shock.

Single-tier firm instruments:

- Levels: `FA_{fmt}^ell = sum_p omega_{fp,tau} * Align_{mpt}^ell` (spread across 4-year term)
- Changes: `dFA_{fmt}^ell = sum_p omega_{fp,tau} * dAlign_{mpt}^ell` (inauguration years only, NOT spread)

Interaction firm instruments used in the analysis (MxG, MxP, triple):

- `FA_{fmt}^{MxG} = sum_p omega_{fp,tau} * Align_{mpt}^{mayor} * Align_{mpt}^{gov}`
- `dFA_{fmt}^{MxG} = sum_p omega_{fp,tau} * d(Align^{mayor} * Align^{gov})_{mpt}`

Interaction FA instruments use a `combined_term_map` with ~2-year stints per inauguration (baselines shift when a new tier inaugurates). Interaction dFA instruments are NOT spread. `_only` overlap states may still exist upstream in intermediate construction, but they are not part of the current firm first-stage battery.

Important: `dFA` is built from turnover shocks, not by mechanically differencing `FA`.

## 5) Sector-level instrument construction (scripts 31, 33, 34)

Sector-party baseline exposure:

`w_{jmp,tau} = [sum_{f in F(j,m)} L_{f,p,tau}] / [sum_{f in F(j,m)} L_{f,tau}]`

Primary implementation uses owner-count exposure (`w_rjp` / `w_{jmp,tau}`).

Sector instruments:

- Levels: `Z_{jmt}^ell = sum_p w_{jmp,tau} * Align_{mpt}^ell` (spread across 4-year term)
- Changes: `dZ_{jmt}^ell = sum_p w_{jmp,tau} * dAlign_{mpt}^ell` (inauguration years only, NOT spread)

Exposure control (sector-level):

`ExposureControl_{jm,tau} = sum_p w_{jmp,tau}`

This control must vary across sectors within municipality-year (it is not a municipality-only control duplicated by sector).

## 6) Endogenous variables and construction rules

Sector outcomes (script 35):

- `s_mjt = bndes_mjt / bndes_mt`
- `delta_s_mjt = s_mjt - s_mj,t-1`

Firm outcomes (script 42):

- `has_bndes_fmt = 1(value_dis_real_2018_total > 0)`
- `log_bndes_fmt = log(value_dis_real_2018_total)` only when positive
- `delta_has_bndes_fmt = has_t - has_t-1`
- `delta_log_bndes_fmt = log_t - log_t-1` only when both periods are positive

Imputation rule:

- Zero-fill is acceptable for level shares `s_*` and instrument columns in wide outputs.
- `delta_s_*` must never be created by NA-to-zero fill; valid zeros are computed differences only.
- First-year or undefined deltas remain `NA` (same rule in firm panel and Panel B).

## 7) Estimation specs and fixed effects

Firm first stage (script 51, main):

- FE: `firm_id + muni_id^year`
- Clustering: two-way by `firm_id` and `muni_id`
- Default bundle: unweighted
- Weighted variants: `n_employees` via `--specs=weighted` or `--weighting=emp_weighted`
- Interface: spec engine over margin, exposure, weighting, baseline, alignment, time variation, sample, and family, with `--test` and `--dry-run`
- Outputs: canonical `firm__...` tables plus `firm_run_manifest.csv/.qs2`

Sector first stage (script 53, Panel A main):

- FE: `muni_id^cnae_section + cnae_section^year`
- Clustering: two-way by `muni_id` and `cnae_section`
- Robustness FE includes `muni_id^cnae_section + muni_id^year`

Simplex handling for vector `delta_s` regressions:

- In municipality-years with positive total BNDES in both `t-1` and `t`, `sum_j delta_s_mjt = 0`.
- One sector (`j0`, largest mean share) is dropped; coefficients are relative to `j0`.

## 8) Two complementary pipelines

The design now explicitly keeps two valid, complementary pipelines:

1. Sector pipeline: owner-count shift-share instruments (`Z_*` levels, `dZ_*` changes) in municipality-sector regressions.
2. Firm pipeline: firm-level instruments (`FA_*` levels, `dFA_*` changes, plus interaction instruments) used in a spec-engine battery over the firm panel. Script 51 writes canonical `firm__...` tables, records per-config timing in `firm_run_manifest`, and can skip binary interaction configs when those columns are unavailable.

The employment-weighted collapse of firm instruments within `(muni_id, cnae_section, year)` is used as a diagnostic aggregation check, not as a separate production instrument family.

## 9) Script and output mapping

Core scripts:

- `31` builds sector-party weights.
- `32` builds alignment shocks (`align_*`, `dalign_*`).
- `33` selects cycle-specific and 2002-fixed baselines.
- `34` builds sector-level instruments and exposure control.
- `35` builds balanced credit shares (`s_mjt`, `delta_s_mjt`).
- `36` builds firm-level instruments (`FA_*`, `dFA_*`).
- `41` builds Panel A and Panel B.
- `42` builds firm panel for regressions.
- `51` firm first stage.
- `52` aggregated firm→sector first stage.
- `53` sector first stage.
- `54` sector second stage.

Key outputs:

- `output/shift_share_instruments_sector.qs2`
- `output/exposure_control_sector.qs2`
- `output/bndes_credit_shares.qs2`
- `output/firm_level_instruments.qs2`
- `output/firm_panel_for_regs.qs2`
- `output/muni_sector_panel.qs2`
- `output/muni_panel_for_regs.qs2`

## 10) Validation checks to keep active

1. Share identities: `sum_j s_mjt = 1` when municipal total BNDES is positive.
2. Delta identities: `sum_j delta_s_mjt = 0` in interior positive-total transitions; `+/-1` can appear in entry/exit transitions.
3. Instrument support: levels instruments in `[0,1]`, turnover instruments in `[-1,1]`.
4. Exposure control support and within-municipality sector variation.
5. No zero-imputation of undefined deltas in wide panels.
