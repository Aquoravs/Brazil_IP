---
title: "Refactor sector first stage with spec engine and alternative instrument weights"
type: refactor
status: active
date: 2026-03-24
origin: docs/brainstorms/2026-03-24-sector-instrument-weighting-alternatives-brainstorm.md
---

# Refactor Sector First Stage with Spec Engine and Alternative Instrument Weights

## Overview

Refactor script 53 (sector first stage) to use a dimension-grid spec engine similar to script 51's architecture, and extend the upstream instrument pipeline (scripts 31, 33, 34, 41) to produce three new sector-level instrument weighting variants (employment-weighted, equal-firm, binary) alongside the existing owner-count weights. Additionally, make exposure control coefficients visible in regression table output.

## Problem Statement / Motivation

Script 53 currently uses hardcoded table sections (7 manually written blocks, each running 6 instrument combos). Adding new dimensions (like instrument weighting variants) requires duplicating code blocks. The brainstorm (see brainstorm: `docs/brainstorms/2026-03-24-sector-instrument-weighting-alternatives-brainstorm.md`) motivates four weighting schemes that encode different theories of how firm-level political connections translate into sector-level BNDES credit:

1. **Owner-count** (existing): each owner is an equally important political channel
2. **Employment-weighted**: larger firms matter more (BNDES cares about job creation)
3. **Equal-firm**: each firm is an independent political access point (simple average)
4. **Binary**: political connection is binary at the firm level (extensive margin only)

A spec engine makes this extensible and enables selective execution via CLI arguments.

## Proposed Solution

### Design Decisions (carried from brainstorm)

1. **Collapse `outcome` + `instrument` into `time_variation`**: Like script 51, use a single dimension with values `levels` and `changes` (see SpecFlow Gap 4).
2. **Instrument column naming**: Keep existing names for owner-count (backward compat). New variants insert a weight infix after prefix: `dZ_emp_mayor_coalition_cycle_specific`, `Z_firm_mayor_coalition_cycle_specific`, `Z_binary_mayor_coalition_2002_fixed`, etc.
3. **Weight-variant-specific exposure controls**: Each weight variant gets its own exposure control column (e.g., `exposure_control_emp_cycle_specific`, `exposure_control_firm_cycle_specific`, `exposure_control_binary_cycle_specific`), so the control matches the instrument's exposure concept.
4. **Exposure control in tables**: Show a "Exposure Control" indicator row (Yes/No) in the goodness-of-fit section, plus report the joint Wald F-statistic for the control interactions. Individual year-specific coefficients stay hidden (there are ~14 per control variable — showing them all would overwhelm the table).
5. **Pre-election firm set as primary** for all variants; contemporaneous firm set as robustness (brainstorm decision 1).
6. **Employment timing**: pre-election window average (brainstorm decision 2).
7. **Panel B unchanged**: new weight variants are only needed in Panel A (script 53). Panel B serves the second stage (script 54), which uses predicted values.
8. **`--test` mode**: subsample to 10% of municipalities (random, reproducible seed), applied at load time.
9. **Run all dimension combos; flag known-degenerate ones**: The manifest records a `degenerate_warning` column for combos like `fe=mxj_mxt + exposure_control=yes` (near-collinear).
10. **Backward compatibility**: existing named specs (`baseline`, `changes`, `fe_muni_year`, `party`, `no_controls`, `fixed_baseline`) continue to work with `instrument_weight=owner_count` as implicit default.

### Spec Engine Dimensions (7 dimensions)

| Dimension | Values | Default |
|---|---|---|
| `time_variation` | `changes`, `levels` | `changes` |
| `instrument_weight` | `owner_count`, `employment`, `equal_firm`, `binary` | `owner_count` |
| `baseline` | `cycle_specific`, `2002_fixed` | `cycle_specific` |
| `alignment` | `coalition`, `party` | `coalition` |
| `fe` | `mxj_jxt`, `mxj_mxt`, `mxj_year` | `mxj_jxt` |
| `exposure_control` | `yes`, `no` | `yes` |
| `sector_var` | (global CLI flag, not per-spec) | `sector_group` |

### Spec Catalog (named bundles)

| Bundle | Overrides |
|---|---|
| `baseline` | (all defaults — changes, owner_count, cycle_specific, coalition, mxj_jxt, yes) |
| `changes` | same as baseline (explicit name for clarity) |
| `levels` | `time_variation=levels` |
| `fe_muni_year` | `fe=mxj_mxt` |
| `fe_year` | `fe=mxj_year` |
| `party` | `alignment=party` |
| `no_controls` | `exposure_control=no` |
| `fixed_baseline` | `baseline=2002_fixed` |
| `weight_battery` | `instrument_weight=owner_count,employment,equal_firm,binary` |
| `all` | expands all bundles |

### CLI Interface

```bash
# Backward-compatible usage (identical to current)
Rscript 53_sector_first_stage.R --specs=baseline

# Run all weight variants for baseline spec
Rscript 53_sector_first_stage.R --specs=baseline --instrument-weight=owner_count,employment,equal_firm,binary

# Run the weight battery bundle
Rscript 53_sector_first_stage.R --specs=weight_battery

# Dimension overrides
Rscript 53_sector_first_stage.R --specs=baseline --fe=mxj_mxt --alignment=party

# Dev modes
Rscript 53_sector_first_stage.R --specs=all --dry-run
Rscript 53_sector_first_stage.R --specs=baseline --test

# Full battery (warning: 192 configs x 6 combos = 1,152 models)
Rscript 53_sector_first_stage.R --specs=all --instrument-weight=owner_count,employment,equal_firm,binary
```

### Canonical Output Naming

```
sector__<time_variation>__<instrument_weight>__<alignment>__<baseline>__<fe>__<exposure_control>.tex
```

Example: `sector__changes__employment__coalition__cycle_specific__mxj_jxt__ctrl.tex`

## Technical Considerations

### Upstream pipeline changes (scripts 31, 33, 34, 41)

The three new weighting variants must be constructed upstream before script 53 can consume them. This is the primary blocker.

**Script 31** (`31_build_sector_exposure_weights.R`):
- Already computes `w_mjp_emp`. Add `w_mjp_firm` and `w_mjp_binary`.
- `w_mjp_firm = mean(omega_fp)` across firms in the (muni, sector, party, year) cell — simple average of firm-level pooled-count shares.
- `w_mjp_binary = mean(1(omega_fp > 0))` — fraction of firms with any connection.
- These require the firm-level `omega_fp` to be available during aggregation (it currently is — script 31 merges firm-level owner data).

**Script 33** (`33_select_baseline_weights.R`):
- Currently pools only `L_rjp` counts across the pre-election window and recomputes `w_rjp = L_rjp / N_rj`.
- Extend to pool all four weight columns. For employment, equal-firm, and binary, the year-level values from script 31 are already the "right" aggregation — script 33 should average them across window years (weighted by firm count or simply mean).
- Output: `w_rjp_0` (existing), `w_rjp_emp_0`, `w_rjp_firm_0`, `w_rjp_binary_0` for each baseline type.

**Script 34** (`34_build_shift_share_instruments.R`):
- Currently constructs `Z_*` and `dZ_*` using `share_owner_cell = L_rjp_0 / N_rj_0`.
- Parameterize to loop over weight variants. For each variant, multiply the variant-specific baseline weight by the alignment shock.
- Also construct weight-variant-specific exposure controls: `exposure_control_<weight>_<baseline> = sum_p w_rjp_<weight>_0` (excluding "No party").

**Script 41** (`41_build_muni_panel.R`):
- Pass through all new `Z_*`, `dZ_*`, and `exposure_control_*` columns from the instrument files to Panel A.
- Panel B does not need the new columns.

### Exposure control identification concern

With cycle-specific baselines + muni×sector FE, the exposure control has limited residual within-cell variation (see `docs/first_stage_review.md`). The spec engine should run these combos but the manifest flags them with `degenerate_warning = "exposure_control near-collinear with FE"`.

### Column count in Panel A

Currently ~14 instrument-related columns. With 4 weight variants: ~56 instrument columns + ~8 exposure control columns = ~64 total. This is manageable for the ~1.37M row Panel A.

## Acceptance Criteria

- [ ] **Upstream: Script 31** computes `w_mjp_firm` and `w_mjp_binary` alongside existing `w_mjp` and `w_mjp_emp`
- [ ] **Upstream: Script 33** pools all four weight variants to produce baseline weights for cycle-specific and 2002-fixed
- [ ] **Upstream: Script 34** constructs `Z_emp_*`, `Z_firm_*`, `Z_binary_*`, `dZ_emp_*`, `dZ_firm_*`, `dZ_binary_*` instruments and corresponding `exposure_control_emp_*`, `exposure_control_firm_*`, `exposure_control_binary_*` columns
- [ ] **Upstream: Script 41** passes all new columns through to Panel A
- [ ] **Script 53** has `parse_cli_args()`, `resolve_requested_configs()`, `build_slug()` following script 51's pattern
- [ ] **Script 53** `DIMENSION_OPTIONS` defines 7 dimensions with valid values
- [ ] **Script 53** `SPEC_CATALOG` includes all bundles from table above
- [ ] **Script 53** `--specs=baseline` produces identical regression output to the current script (backward compat)
- [ ] **Script 53** `--instrument-weight=employment,equal_firm,binary` works end-to-end
- [ ] **Script 53** `--dry-run` prints the resolved config grid and exits
- [ ] **Script 53** `--test` loads a 10% municipality subsample
- [ ] **Script 53** produces a run manifest (`sector_run_manifest.csv` / `.qs2`) with per-config status, timing, F-stat range, and `degenerate_warning` column
- [ ] **Script 53** produces a coefficient summary (`sector_fc_battery_summary.qs2`) across all configs
- [ ] **Tables**: Exposure control shows as indicator row (Yes/No) in goodness-of-fit section
- [ ] **Tables**: Joint Wald F-statistic for exposure control interactions appears in diagnostics
- [ ] **beamer_tables.R**: `COEF_MAP_INSTRUMENTS` extended with entries for `dZ_emp_*`, `Z_emp_*`, `dZ_firm_*`, `Z_firm_*`, `dZ_binary_*`, `Z_binary_*` instruments
- [ ] **CLAUDE.md** updated with new CLI args, variable naming conventions, and output files

## Implementation Phases

### Phase 1: Upstream instrument construction (scripts 31, 33, 34)

**Scripts**: `31_build_sector_exposure_weights.R`, `33_select_baseline_weights.R`, `34_build_shift_share_instruments.R`

1. Script 31: add `w_mjp_firm` and `w_mjp_binary` computation in `process_weights()`.
2. Script 33: extend baseline selection to pool all four weight columns across the pre-election window. Output columns: `w_rjp_0`, `w_rjp_emp_0`, `w_rjp_firm_0`, `w_rjp_binary_0` for each baseline type.
3. Script 34: parameterize instrument construction to loop over `c("", "emp_", "firm_", "binary_")` weight prefixes. For each, multiply the variant-specific baseline weight by alignment shocks to produce `Z_<prefix>*` and `dZ_<prefix>*` columns. Also construct `exposure_control_<prefix><baseline>` columns.
4. Verify output files contain all expected columns.

### Phase 2: Panel passthrough (script 41)

**Script**: `41_build_muni_panel.R`

1. Update the instrument merge to include all new `Z_*`, `dZ_*`, and `exposure_control_*` columns.
2. Verify Panel A has the expected number of instrument columns.
3. Panel B is not changed.

### Phase 3: Spec engine refactor (script 53)

**Script**: `53_sector_first_stage.R`

1. Define `DIMENSION_OPTIONS`, `DEFAULT_DIMENSIONS`, `SPEC_CATALOG` at script top.
2. Implement `parse_cli_args()` following script 51's pattern — handle `--specs=`, dimension overrides, `--test`, `--dry-run`.
3. Implement `resolve_requested_configs()` — expand bundles, apply overrides, deduplicate, build canonical slugs.
4. Refactor the current `dz_col()`, `z_col()`, `ctrl_col()` helpers to accept a `weight_prefix` argument.
5. Refactor `run_six_combos()` to accept a config row and construct formulas dynamically based on all dimensions.
6. Replace the 7 hardcoded table blocks with a single loop over config rows.
7. Add manifest output (per-config timing, status, F-stat range, `degenerate_warning`).
8. Add coefficient summary extraction across all configs.
9. Add `--test` mode (10% municipality subsample at load time).
10. Add `--dry-run` mode (print config grid and exit).

### Phase 4: Table export improvements (beamer_tables.R + script 53)

**Scripts**: `_utils/beamer_tables.R`, `53_sector_first_stage.R`

1. Extend `COEF_MAP_INSTRUMENTS` with labels for new weight-variant instruments.
2. Add "Exposure Control" indicator row to `save_beamer_table()` goodness-of-fit section (similar to FE checkmarks).
3. Add joint Wald F-stat for exposure control interactions to table diagnostics.
4. Update `save_beamer_table()` to accept an `exposure_control_gof` parameter that adds the indicator row.

### Phase 5: Documentation and integration testing

1. Update `CLAUDE.md` with new CLI args, variable names, and output file descriptions.
2. Run `31:53 --specs=baseline` and verify output matches current script 53 results (backward compatibility regression test).
3. Run `31:53 --specs=weight_battery` end-to-end to verify the full pipeline works.
4. Run `53 --dry-run --specs=all --instrument-weight=owner_count,employment,equal_firm,binary` to verify the full grid.

## Dependencies & Risks

- **Primary blocker**: Phases 1-2 (upstream changes) must complete before Phase 3 can be tested with new weight variants. However, the spec engine refactor (Phase 3) can be developed in parallel using only `owner_count` instruments.
- **Script 33 pooling complexity**: Equal-firm and binary weights require different aggregation logic than the current `L_rjp`-based pooling. This is the hardest upstream change.
- **Exposure control identification**: Some FE × exposure_control combos are near-degenerate. Mitigated by manifest warnings, not by filtering.
- **Grid explosion**: Full battery is 192 configs × 6 combos = 1,152 models. Runtime may be significant. Mitigated by `--specs=` for selective execution and `--test` for dev iteration.

## Sources & References

- **Origin brainstorm**: [docs/brainstorms/2026-03-24-sector-instrument-weighting-alternatives-brainstorm.md](docs/brainstorms/2026-03-24-sector-instrument-weighting-alternatives-brainstorm.md) — Key decisions: four weighting schemes, pre-election firm base, employment timing, pipeline integration approach
- **Spec engine template**: `BNDES/politicsregs/5_estimation/51_firm_first_stage.R` (lines 122-352 for spec engine architecture)
- **Current sector first stage**: `BNDES/politicsregs/5_estimation/53_sector_first_stage.R` (lines 93-137 for current spec catalog)
- **Table standard**: `BNDES/politicsregs/_utils/beamer_tables.R` and `docs/solutions/best-practices/latex-regression-tables-beamer-standard.md`
- **Exposure control identification analysis**: `docs/first_stage_review.md` (lines 9-92)
- **Upstream scripts**: `31_build_sector_exposure_weights.R`, `33_select_baseline_weights.R`, `34_build_shift_share_instruments.R`, `41_build_muni_panel.R`
