---
title: "Implement Four IV Specifications: Unified Pipeline Design"
type: feat
status: completed
date: 2026-03-12
---

# Implement Four IV Specifications: Unified Pipeline Design

## Overview

The paper in `paper/regs.tex` defines linked IV specifications at both the firm and sector levels:

**Sector-level specifications:**
1. Sector levels: `s_mjt` instrumented by shift-share alignment levels `Z_mjt`.
2. Sector changes: `delta_s_mjt` instrumented by shift-share turnover shocks `ΔZ_mjt`.

**Firm-level specifications (extensive and intensive margins):**
3. Firm levels, extensive: `1(BNDES_fmt > 0)` instrumented by `FA_*` (LPM, full panel).
4. Firm levels, intensive: `log(BNDES_fmt)` instrumented by `FA_*` (conditional on `BNDES_fmt > 0`).
5. Firm changes, extensive: `Δ1(BNDES_fmt > 0)` instrumented by `dFA_*`.
6. Firm changes, intensive: `Δlog(BNDES_fmt)` instrumented by `dFA_*` (conditional on positive in both `t` and `t-1`).

The pipeline should be unified so these specifications share intermediate objects, follow the same naming conventions, and preserve a clear micro-to-macro aggregation link.

## Current Status

| Spec | Unit | Endogenous | Instrument | Status |
|------|------|-----------|------------|--------|
| Sector Changes | muni x sector x year | `delta_s_mjt` | `ΔZ = w x dAlign` | Implemented with owner-count weights |
| Sector Levels | muni x sector x year | `s_mjt` | `Zlev = w x Align` | Partially implemented |
| Firm Levels, Ext. | firm x muni x year | `has_bndes_fmt` | `FA = (L_fp/L_f) x Align` | Not implemented |
| Firm Levels, Int. | firm x muni x year | `log_bndes_fmt` | `FA = (L_fp/L_f) x Align` | Not implemented |
| Firm Changes, Ext. | firm x muni x year | `delta_has_bndes_fmt` | `dFA = (L_fp/L_f) x dAlign` | Not implemented |
| Firm Changes, Int. | firm x muni x year | `delta_log_bndes_fmt` | `dFA = (L_fp/L_f) x dAlign` | Not implemented |

## Design Decisions

### Employment weighting enters through regression weights, not separate instruments

Instead of constructing separate employment-weighted sector instruments (`Zemp_*`), employment weighting enters the design through **analytic regression weights** (`n_employees`) in the firm-level first stage.

**Rationale**: The employment-weighted average of firm-level instruments within a (sector, municipality) cell naturally recovers the sector-level instrument with employment-weighted exposure shares:

```text
Σ_f E_f · Z^ℓ_fmt / Σ_f E_f
  = Σ_p [Σ_f E_f · (L_{f,p}/L_f) / Σ_f E_f] · Align^ℓ_mpt
  = Σ_p w^emp_jmp · Align^ℓ_mpt
```

This means:
1. Firm-level instruments `FA_*` and `dFA_*` are constructed **without** employment weighting — they are `(L_fp/L_f) * Align_mpt` and `(L_fp/L_f) * dAlign_mpt`.
2. The firm first stage runs with `weights = n_employees`, making the estimand the employment-weighted average causal effect.
3. The sector-level pipeline continues using owner-count instruments (`Z_*`, `Zlev_*`) as a **complementary** specification at a different aggregation level.
4. The aggregation identity linking firm and sector specifications is verified as a diagnostic quality gate by collapsing firm instruments within `(muni_id, cnae_section, year)` weighted by `n_employees`.

**Consequence**: No `Zemp_*`, `Zemp_lev_*`, or `w_rjp_emp` columns need to be built, carried through baseline selection, or merged into regression panels. Scripts 31, 33, 34, 41, and 51 require no modifications for employment weighting.

### Two complementary pipelines, not one nested pipeline

The sector pipeline (owner-count `Z_*`) and the firm pipeline (employment-weighted via regression weights) estimate related but distinct objects:

- **Sector `Z_*`**: uses owner-count shares `L_mjp / N_mj` as exposure weights.
- **Firm with `n_employees` weights**: implicitly uses employment-weighted shares `Σ_f E_f · (L_fp/L_f) / Σ_f E_f` as exposure weights.

Both are valid shift-share instruments for the same underlying variation. The firm-level specification provides micro-foundation and the employment-weighted aggregation; the sector-level specification provides a complementary view with owner-count exposure. The aggregation identity linking them is verified diagnostically.

### Sector fixed effects hierarchy

Primary sector first stage:

```text
delta_s_mjt ~ Z_mjt + controls | muni x sector + sector x year
```

Robustness sector first stage:

```text
delta_s_mjt ~ Z_mjt + controls | muni x sector + muni x year
delta_s_mjt ~ Z_mjt + controls | muni x sector + year
```

### Firm fixed effects hierarchy and margin decomposition

Each firm specification (levels and changes) is estimated on two samples:

**Extensive margin** (full panel, LPM):
```text
has_bndes_fmt ~ FA_*  | firm_id + muni_id^year     [weights = n_employees]
delta_has_bndes_fmt ~ dFA_* | firm_id + muni_id^year  [weights = n_employees]
```

**Intensive margin** (conditional on positive BNDES):
```text
log_bndes_fmt ~ FA_*  | firm_id + muni_id^year     [weights = n_employees]  (sample: BNDES > 0)
delta_log_bndes_fmt ~ dFA_* | firm_id + muni_id^year  [weights = n_employees]  (sample: BNDES > 0 in t and t-1)
```

Employment analytic weights (`n_employees`) are the main specification. Unweighted is robustness.

Comparing extensive and intensive margin coefficients reveals whether alignment operates primarily through access to credit or through loan size.

### Firm-level baseline: cycle-specific, frozen at pre-election year

Firm-level party shares `L_fp/L_f` must be computed at the **pre-election baseline year** for each electoral cycle, matching the sector pipeline's cycle-specific baseline logic from script 33. A 2002-fixed variant is produced for robustness.

Rationale: Time-varying `L_fp_t/L_f_t` would create a non-predetermined instrument if firms adjust affiliations in response to anticipated political changes.

Cycle map (matching sector pipeline):
- Mayor: 2003, 2007, 2011, 2015 baseline years
- Governor/President: 2002, 2005, 2009, 2013, 2017 baseline years

### "No party" owners in firm instruments

Firm denominator `L_f` includes all owners (including "No party") to maintain the interpretation that `L_fp/L_f` is the share of firm f's owners affiliated with party p. Parties without alignment shock entries contribute zero to `FA_*` via the zero shock value. This differs from the sector pipeline where "No party" is excluded from both numerator and denominator.

### Exposure control

The relevant sector-level control is the municipality-sector baseline connectedness measure:

```text
ExposureControl_jm,tau = sum_p w_jmp,tau
```

This must vary across sectors within municipality-year. Municipality-level controls replicated by sector are not sufficient for the intended design.

No separate firm-level exposure control is needed: firm FE absorbs time-invariant firm connectedness, and muni x year FE absorbs municipality-level alignment effects.

## Pipeline Architecture

### Dependency graph

```text
                    Script 22 (firm panel)
                   /        |          \
                  /         |           \
         Script 31      Script 35     Script 36
      (sector weights) (credit shares) (firm instruments)
             |              |              |
         Script 33          |          Script 42
      (baseline select)     |       (firm reg panel)
             |              |              |
         Script 34          |          Script 53
      (sector Z, Zlev)      |      (firm first stage)
              \            /
               \          /
                 Script 41
              (sector + muni panels)
                 /       \
          Script 51    Script 52
```

### Shared intermediate files

| File | Producer | Consumers | Content |
|------|----------|-----------|---------|
| `alignment_shocks.qs2` | 32 | sector + firm specs | level and turnover alignment shocks |
| `rais_bndes_reconstructed.fst` | 22 | 31, 35, 36, 41, 42 | firm x muni x year panel |
| `owner_aff_firm_year_party_2002_2019.qs2` | raw | 31, 36 | firm-party affiliations |

### Existing scripts that require modification

| Script | Planned change |
|--------|----------------|
| `34_build_shift_share_instruments.R` | add sector-level exposure control (owner-count) |
| `41_build_muni_panel.R` | merge sector-level exposure control columns |
| `51_first_stage.R` | add exposure control to specifications |
| `run_politicsregs.R` | register stages 36, 42, 53 and migrate audits from numeric stages to named hooks (`audit_3_instruments`, `audit_41_muni_panel`) |
| project docs | update architecture, naming, and outputs |

Scripts 31, 33, 52 require **no modifications** for the employment-weighting design.

### New scripts required

| Stage | Script | Purpose |
|-------|--------|---------|
| 36 | `3_instruments/36_build_firm_level_instruments.R` | build `FA_*` and `dFA_*` |
| 42 | `4_regression_panels/42_build_firm_panel.R` | build firm regression panel |
| 53 | `5_estimation/53_firm_first_stage.R` | estimate firm first stages |

## Phase -1: Audit Existing Sector Pipeline Before Extending It

Purpose: verify that the current sector pipeline already matches the intended econometric design before adding new functionality.

### Audit scope

1. Specification conformity:
   - script 31 denominator and share definition
   - script 34 inauguration spreading and levels vs turnover handling
   - script 35 balanced panel and simplex identities
   - script 41 dropped-sector rule, GDP construction, HHI, and merges
   - script 51 FE hierarchy, clustering, F-statistics, and dropped-sector handling
   - script 52 consistency with Panel B and first-stage objects
2. Invariants and identities:
   - shares sum to 1 within municipality-year
   - `delta_s_mjt` sums to 0 within municipality-year
   - instrument support and constancy properties hold
   - exposure controls are numerically consistent with baseline weights
   - wide and long outputs agree
3. Efficiency:
   - identify unnecessary full loads, repeated sorts, and non-keyed joins
   - record runtime and output size for `31:35 --audits=auto`, `41`, `51`, `52`
4. Reproducibility:
   - run `31:35 --audits=auto --dryrun`
   - run `41,51,52 --dryrun`
   - parse audited scripts with `Rscript -e "parse(...)"`
   - verify downstream output names against upstream writes

### Phase -1 acceptance criteria

- `[x]` Audit memo added in a linked note
- `[x]` All current sector scripts either pass or have been remediated before feature work starts
- `[x]` Any mismatch between `paper/regs.tex`, `docs/shift_share.md`, and implemented code is documented explicitly
- `[x]` Any performance bottleneck that would materially slow iterative work is identified before implementation starts

Audit note: `docs/plans/2026-03-10-phase-minus-1-audit-findings.md`

## Phase 0: Sector Exposure Control

Target script: `34_build_shift_share_instruments.R`

Purpose: fix the exposure control wiring identified in the Phase -1 audit.

Changes:

1. Build sector-level exposure control `ExposureControl_jm,tau = sum_p w_jmp,tau` using owner-count baseline weights.
2. Ensure the control varies across sectors within municipality-year (not municipality-level replicated across sectors).
3. Output `exposure_control_sector.qs2` at the `(muni_id, cnae_section, baseline_type)` level.

Acceptance criteria:

- exposure control varies across sectors within the same municipality-year
- support is non-negative
- coverage statistics printed

Note: Script 31's `w_rjp_emp` and `E_rj` columns can be removed — the aggregation identity is verified directly from firm-level data in script 53.

## Phase 1: Firm-Level Instruments

Target script: `36_build_firm_level_instruments.R` (new)

Purpose: construct `FA_*` and `dFA_*` at the firm x muni x year level.

Construction logic:

1. Load owner affiliations `(firm_id, year, party, aff_count)` from `owner_aff_firm_year_party_2002_2019.qs2`.
2. Compute firm-party shares: `L_fp / L_f` where `L_f` includes all owners (including "No party").
3. Select baseline shares at cycle-specific pre-election years (matching script 33's `cycle_map`) and 2002-fixed baseline.
4. Load spread alignment shocks from script 34's intermediate objects or reimplement the term-map spreading logic from script 34 (lines 361-386).
5. Merge on `(muni_id, party, year)` and compute:
   - `FA_tier_coalition = (L_fp_0 / L_f_0) * align_mpt`
   - `dFA_tier_coalition = (L_fp_0 / L_f_0) * dalign_mpt`
6. Aggregate across parties within `(firm_id, muni_id, year, baseline_type)`.
7. Assign each firm to its municipality(s) via the reconstructed panel — the output is at `(firm_id, muni_id, year)` because alignment shocks vary by municipality.

Output: `firm_level_instruments.qs2`

Acceptance criteria:

- both cycle-specific and 2002-fixed baseline variants
- support:
  - `FA_*` in `[0, 1]`
  - `dFA_*` in `[-1, 1]`
- firms without owner data get `FA_* = 0`, `dFA_* = 0` (zero political exposure)
- coverage: fraction of firms with non-zero instruments reported

## Phase 2: Firm Regression Panel

Target script: `42_build_firm_panel.R` (new)

Purpose: merge firm-level instruments with BNDES credit and employment, construct outcome variables for extensive and intensive margin regressions.

Construction:

1. Load reconstructed panel `(firm_id, muni_id, year, n_employees, value_dis_real_2018_total, cnae_section)`.
2. Left-join firm instruments from `firm_level_instruments.qs2` on `(firm_id, muni_id, year)`.
3. Construct outcome variables:
   - `has_bndes_fmt = as.integer(value_dis_real_2018_total > 0)` — extensive margin indicator (0/1)
   - `log_bndes_fmt = log(value_dis_real_2018_total)` — intensive margin (defined only when `value_dis_real_2018_total > 0`; `NA` otherwise)
4. Construct changes outcomes within `(firm_id, muni_id)` groups, ordered by year:
   - `delta_has_bndes_fmt = has_bndes_fmt - shift(has_bndes_fmt)` — change in extensive margin indicator
   - `delta_log_bndes_fmt = log_bndes_fmt - shift(log_bndes_fmt)` — change in log BNDES (defined only when both `t` and `t-1` have positive BNDES; `NA` otherwise)
5. First-year deltas are `NA` (never zero-filled), consistent with sector pipeline's `delta_s_mjt` rule.

Required outputs:

- `has_bndes_fmt` — extensive margin indicator
- `log_bndes_fmt` — log BNDES (NA when zero)
- `delta_has_bndes_fmt` — change in indicator
- `delta_log_bndes_fmt` — change in log (NA unless positive in both periods)
- `n_employees`
- baseline type
- all `FA_*` and `dFA_*` columns

Output: `firm_panel_for_regs.qs2`

Acceptance criteria:

- full firm x muni x year coverage from the reconstructed panel
- `log_bndes_fmt` is `NA` (not `-Inf`) when `value_dis_real_2018_total == 0`
- `delta_log_bndes_fmt` is `NA` when either `t` or `t-1` has zero BNDES
- first-year delta columns are `NA`, not zero
- `n_employees` coverage reported: fraction of firm-years with positive employment

## Phase 3: Firm First Stage

Target script: `53_firm_first_stage.R` (new)

Primary specifications (all with `weights = n_employees`):

**Levels — extensive margin** (full panel, LPM):
```text
has_bndes_fmt ~ FA_*  | firm_id + muni_id^year
```

**Levels — intensive margin** (sample: `BNDES > 0`):
```text
log_bndes_fmt ~ FA_*  | firm_id + muni_id^year
```

**Changes — extensive margin** (full panel, LPM):
```text
delta_has_bndes_fmt ~ dFA_*  | firm_id + muni_id^year
```

**Changes — intensive margin** (sample: `BNDES > 0` in both `t` and `t-1`):
```text
delta_log_bndes_fmt ~ dFA_*  | firm_id + muni_id^year
```

Robustness specifications:

- Unweighted (no `n_employees` weights) — via `--unweighted` flag
- 2002-fixed baseline

First-stage table structure:

- FC-1: levels extensive, coalition, cycle-specific, employment-weighted
- FC-2: levels intensive, coalition, cycle-specific, employment-weighted
- FC-3: changes extensive, coalition, cycle-specific, employment-weighted
- FC-4: changes intensive, coalition, cycle-specific, employment-weighted
- FC-5: party alignment (instead of coalition)
- FC-6: 2002-fixed baseline
- FC-7: unweighted robustness

Acceptance criteria:

- firm tables for all four margin × direction combinations are produced
- two-way clustering by `firm_id` and `muni_id`
- first-stage strength uses `fixest::wald(mod, keep = "^(FA_|dFA_)")$stat`
- regression uses `(firm_id, muni_id, year)` as the observation unit with establishment-level `n_employees` as weights
- intensive margin sample sizes are reported alongside extensive margin for comparison

### Aggregation verification diagnostic

Script 53 (or a companion diagnostic) should verify the aggregation identity:

1. Collapse firm-level `FA_*` within `(muni_id, cnae_section, year)` cells, weighted by `n_employees`.
2. Verify support bounds of the collapsed quantity: `[0, 1]` for levels, `[-1, 1]` for changes.
3. Report variation statistics (mean, sd, within-muni sd) of the implied sector-level instrument.

This verifies that the employment-weighted aggregation of firm instruments produces a well-behaved sector-level quantity, confirming the micro-to-macro link.

## Phase 4: Integration and Documentation

Target files:

- `run_politicsregs.R`
- architecture docs
- naming-convention docs

Changes:

1. Register stages 36, 42, 53 in the orchestrator and move audits to named hooks (not numeric stage IDs).
2. Update `CLAUDE.md` to remove references to `Zemp_*` as pipeline outputs (retain as a conceptual quantity verified diagnostically).
3. Document the two-pipeline design: sector (owner-count `Z_*`) and firm (employment-weighted via regression weights).
4. Refresh pipeline run examples.

## Functional Acceptance Criteria

- `[x]` Phase -1 audit implemented as a linked note
- `[x]` Script 31 outputs owner-count exposure weights
- `[x]` Script 34 produces sector-level exposure control at municipality-sector level
- `[x]` Script 36 produces firm-level instruments `FA_*` and `dFA_*`
- `[x]` Script 42 produces the firm regression panel
- `[x]` Script 53 produces firm-level first-stage tables (extensive + intensive margins) with `n_employees` weights
- `[x]` `run_politicsregs.R` supports `36:53`
- `[x]` All six specifications from `paper/regs.tex` are implemented (2 sector + 4 firm margin×direction)

## Quality Gates

- `[x]` Firm instruments satisfy support bounds (`FA_*` in [0,1], `dFA_*` in [-1,1])
- `[x]` Aggregation diagnostic: employment-weighted collapse of firm instruments within (muni, sector) satisfies support bounds and has meaningful variation
- `[x]` Sector-level exposure controls are municipality-sector specific
- `[x]` Firm regressions use `n_employees` as the default main weighting scheme
- `[x]` Firms with `n_employees <= 0` or `NA` are excluded from weighted specification; coverage loss documented
- `[x]` Unweighted firm specification is available as robustness
- `[x]` New scripts print coverage diagnostics

## Implementation Order

1. Phase -1: audit and document the current sector pipeline.
2. Phase 0: fix sector-level exposure control wiring.
3. Phase 1: build firm-level instruments.
4. Phase 2: build firm regression panel.
5. Phase 3: estimate firm first stages with employment weights.
6. Phase 4: integrate new stages and refresh documentation.

## Edge Cases and Data Quality Notes

### Firms with zero employment
Firms with `n_employees = 0` or `NA` are excluded from the employment-weighted specification but included in the unweighted robustness. Coverage statistics should report what fraction of BNDES credit goes to firms with positive employment.

### Multi-establishment firms
The regression unit is `(firm_id, muni_id, year)`. A firm in multiple municipalities has separate rows with establishment-level `n_employees`. The firm-party share `L_fp/L_f` is constant across municipalities (affiliation is firm-level), but `FA_*` differs across municipalities because alignment shocks vary by municipality. This is correct and necessary for the aggregation identity.

### Firms without owner affiliation data
Firms with no owner data get `FA_* = 0` and `dFA_* = 0` (zero political exposure). They contribute to the regression but provide no instrument variation. Including them is correct: they represent the non-politically-exposed firm population.

### Extensive vs. intensive margin sample sizes
Most firm-muni-years have zero BNDES credit. The extensive margin (LPM) uses the full panel; the intensive margin uses only observations with positive BNDES. For the changes intensive margin, both `t` and `t-1` must have positive BNDES, making this the most restrictive sample. Report sample sizes for each margin.

### Log of zero BNDES credit
`log_bndes_fmt` is `NA` (not `-Inf`) when `value_dis_real_2018_total == 0`. The intensive margin regression only runs on the positive-BNDES subsample, so this is never an issue in estimation.

### First-year deltas
`delta_has_bndes_fmt` and `delta_log_bndes_fmt` are `NA` for the first year of each firm-muni pair. Never zero-filled, consistent with the sector pipeline's `delta_s_mjt` rule.

## Internal References

- `paper/regs.tex`
- `docs/shift_share.md`
- `CLAUDE.md`
- `BNDES/politicsregs/3_instruments/`
- `BNDES/politicsregs/4_regression_panels/`
- `BNDES/politicsregs/5_estimation/`
