---
title: "Refactor Firm First Stage into a Structural CLI and Spec Engine"
type: refactor
status: completed
date: 2026-03-23
updated: 2026-03-23
---

# Refactor Firm First Stage into a Structural CLI and Spec Engine

## Overview

Refactor `BNDES/politicsregs/5_estimation/51_firm_first_stage.R` so that the script is driven by an explicit spec engine rather than a mix of comments, named bundles, global booleans, and hidden weighting defaults.

The target interface is:

```bash
# Default run
Rscript BNDES/politicsregs/run_politicsregs.R 51

# Named bundle, no standalone -- required
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=weighted

# Dimension override, no standalone -- required
Rscript BNDES/politicsregs/run_politicsregs.R 51 --baseline=2002_fixed

# Multiple dimension overrides
Rscript BNDES/politicsregs/run_politicsregs.R 51 --margin=intensive --alignment=party

# Multiple values expand to a grid
Rscript BNDES/politicsregs/run_politicsregs.R 51 --alignment=coalition,party --sample=all_firms,single_muni

# Backward-compatible form still works
Rscript BNDES/politicsregs/run_politicsregs.R 51 -- --specs=weighted
```

The behavioral rule is:

1. If `--specs` is omitted, start from the default bundle `baseline`.
2. If `--specs` is provided, start from the requested named bundles.
3. Apply all dimension overrides to those seeded bundles.
4. Expand comma-separated override values as a Cartesian grid.
5. Apply `--unweighted` last as a backward-compatible override of `weighting=unweighted`.

This refactor must also fix the current inconsistency where the script documentation says the baseline specification is unweighted, but the executable path defaults to employment-weighted estimation.

## Problem to Solve

The current script has three structural issues:

1. `SPEC_CATALOG` documents dimensions such as `weighting`, but execution does not actually use the spec object to decide how models are fit.
2. The default run path is controlled by `UNWEIGHTED` and `weighted = !UNWEIGHTED`, so the script can say "baseline is unweighted" while actually running weighted regressions.
3. Output names such as `fc_t1_levels_extensive.tex` and `fc_t9a_interaction_levels_extensive.tex` are hard to interpret and do not generalize once users begin combining named bundles with dimension overrides.

The refactor should turn script 51 into a deterministic engine where the requested configuration is explicit, validated, printed, run, and saved with names that fully identify the regression specification.

## Scope

This plan applies only to:

- `BNDES/politicsregs/5_estimation/51_firm_first_stage.R`

This plan does not refactor script 53 now, though the internal design should be reusable later.

## Desired CLI Semantics

### Supported dimensions

The script should support these dimensions explicitly:

| Dimension | Options | Default |
|---|---|---|
| `margin` | `extensive`, `intensive` | `extensive` |
| `exposure` | `pooled_count`, `binary` | both |
| `weighting` | `unweighted`, `emp_weighted` | `unweighted` |
| `baseline` | `cycle_specific`, `2002_fixed` | `cycle_specific` |
| `alignment` | `coalition`, `party` | `coalition` |
| `time_variation` | `levels`, `changes` | `levels` |
| `sample` | `all_firms`, `single_muni` | `all_firms` |

### Named bundles

Keep these named bundles:

| Name | Expansion |
|---|---|
| `baseline` | extensive, both exposures, unweighted, cycle-specific, coalition, levels, all firms |
| `changes` | baseline + `time_variation=changes` |
| `weighted` | baseline + `weighting=emp_weighted` |
| `party` | baseline + `alignment=party` |
| `fixed_baseline` | baseline + `baseline=2002_fixed` |
| `single_muni` | baseline + `sample=single_muni` |
| `intensive` | baseline + `margin=intensive` |
| `all` | all named bundles above |

### Parsing rules

The script should accept:

- `--specs=name1,name2`
- `--margin=...`
- `--exposure=...`
- `--weighting=...`
- `--baseline=...`
- `--alignment=...`
- `--time-variation=...`
- `--time_variation=...`
- `--sample=...`
- `--unweighted`

Rules:

- `--time-variation` and `--time_variation` are synonyms.
- Comma-separated values are allowed for every dimension and expand to a Cartesian grid.
- If `--unweighted` appears, it overrides any weighting choice and prints a warning if that conflicts with `--weighting=emp_weighted` or the `weighted` bundle.
- Unknown options and invalid values must fail fast with explicit error messages.

### Orchestrator compatibility

The user should not need a standalone `--` before script options.

These must behave identically:

```bash
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=weighted
Rscript BNDES/politicsregs/run_politicsregs.R 51 -- --specs=weighted
```

This requires no orchestrator refactor if script 51 parses forwarded arguments normally, because `run_politicsregs.R` already forwards non-orchestrator flags passed inline.

## Refactor Design

### Phase 1: Centralize spec definitions

Inside script 51, define:

- `DIMENSION_OPTIONS`
- `DEFAULT_DIMENSIONS`
- `SPEC_CATALOG`
- `parse_cli_args()`
- `resolve_requested_configs()`
- `validate_requested_configs()`

`DEFAULT_DIMENSIONS` should represent the true default behavior, not just documentation:

```r
list(
  margin = "extensive",
  exposure = c("pooled_count", "binary"),
  weighting = "unweighted",
  baseline = "cycle_specific",
  alignment = "coalition",
  time_variation = "levels",
  sample = "all_firms"
)
```

### Phase 2: Build a resolved config table

The script should transform the CLI request into a data table or list of normalized configuration rows, one row per regression family to run.

Each resolved row must contain:

- `family`: `main` or `interaction`
- `margin`
- `exposure`
- `weighting`
- `baseline`
- `alignment`
- `time_variation`
- `sample`
- `depvar`
- `dep_label`
- `slug`

Configurations should be deduplicated after bundle expansion plus dimension overrides.

### Phase 3: Route execution through config rows

Replace the current blocks keyed by:

- `RUN_BASELINE`
- `RUN_CHANGES`
- `RUN_INTENSIVE`
- `RUN_PARTY`
- `RUN_FIXED_BASELINE`
- `RUN_WEIGHTED`
- `RUN_SINGLE_MUNI`

with a single loop over resolved config rows.

Each config row determines:

- which panel to load
- which sample mask to use
- whether weights are used
- which formula cache to query
- which dependent variable is used
- which combo family is run

Execution mapping:

| Condition | Result |
|---|---|
| `levels + extensive` | `has_bndes_fmt` |
| `levels + intensive` | `log_bndes_fmt` |
| `changes + extensive` | `delta_has_bndes_fmt` |
| `changes + intensive` | `delta_log_bndes_fmt` |

Family mapping:

- `main`: `M`, `G`, `P`, `M+G`, `M+P`, `M+G+P`
- `interaction`: `M+G+MxG`, `M+G+P+MxG`, `M+G+P+MxP`

### Phase 4: Make weighting semantics explicit

The refactor must eliminate `weighted = !UNWEIGHTED` as the driver of model behavior.

Instead:

- resolved `config$weighting` determines whether `weights = ~n_employees` is passed to `feols()`
- resolved `config$weighting` determines whether the sample mask requires `n_employees > 0`
- printed headers, notes, and summary metadata must use the same resolved weighting value

This is the core fix for the current bug.

### Phase 5: Lazy loading

The script should still avoid loading unnecessary data:

- load the cycle-specific panel only if at least one config needs it
- load the 2002-fixed panel only if at least one config needs it
- require binary instrument columns only when at least one config requests `exposure=binary`

Fail fast when:

- `2002_fixed` is requested but the panel file does not exist
- binary exposure is requested but binary instrument columns are absent
- `single_muni` is requested but `is_multi_muni` is unavailable

## Table Naming Convention

This is the canonical output naming rule:

```text
firm__<family>__<time_variation>__<margin>__<alignment>__<baseline>__<weighting>__<sample>__<exposure>.tex
```

and analogously for `.md`.

Fields:

- `family`: `main` or `interaction`
- `time_variation`: `levels` or `changes`
- `margin`: `extensive` or `intensive`
- `alignment`: `coalition` or `party`
- `baseline`: `cycle_specific` or `2002_fixed`
- `weighting`: `unweighted` or `emp_weighted`
- `sample`: `all_firms` or `single_muni`
- `exposure`: `pooled_count` or `binary`

Examples:

```text
firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count.tex
firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__binary.tex
firm__interaction__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count.tex
firm__main__levels__extensive__coalition__2002_fixed__emp_weighted__all_firms__pooled_count.tex
firm__main__changes__extensive__party__cycle_specific__unweighted__single_muni__binary.tex
```

### Naming policy

1. These readable names become the source of truth.
2. Every produced table must have exactly one canonical filename following this rule.
3. Legacy names such as `fc_t1_levels_extensive.tex` may be kept only as compatibility aliases for canonical named bundles currently consumed by presentations or documents.
4. Custom override runs should not create new FC-style names.
5. The script should print the canonical name for each artifact as it is saved.

### Why this naming matters

This naming rule makes the output self-describing:

- the user can recognize the full specification without opening the file
- custom overrides no longer require inventing new opaque table IDs
- files sort predictably
- downstream scripts and presentations can target canonical names directly

## Summary and Manifest Outputs

In addition to regression tables, save a manifest in `BNDES/output/firm_reg_tables/`:

- `firm_run_manifest.csv`
- `firm_run_manifest.qs2`

Each row should contain:

- canonical filename stem
- family
- resolved dimensions
- output paths
- number of observations
- Wald F-statistic summary
- whether the family ran or was skipped
- skip reason, if any

This manifest becomes the machine-readable source of truth for presentation scripts or later audits.

## Testing

Only test through the orchestrator:

```bash
Rscript BNDES/politicsregs/run_politicsregs.R 51
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=weighted
Rscript BNDES/politicsregs/run_politicsregs.R 51 --baseline=2002_fixed
Rscript BNDES/politicsregs/run_politicsregs.R 51 --margin=intensive
Rscript BNDES/politicsregs/run_politicsregs.R 51 --alignment=coalition,party --sample=all_firms,single_muni
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=weighted --unweighted
Rscript BNDES/politicsregs/run_politicsregs.R 51 -- --specs=weighted
```

Expected checks:

1. `Rscript ... 51`
   - runs only the default baseline bundle
   - baseline is unweighted
   - both exposure variants run
   - notes and metadata say unweighted

2. `--specs=weighted`
   - works without standalone `--`
   - switches the run to employment-weighted

3. `--baseline=2002_fixed`
   - works without standalone `--`
   - loads fixed panel lazily

4. `--margin=intensive`
   - applies the override to the default bundle only

5. multiple values
   - expand to a clean Cartesian grid
   - outputs are deduplicated and named deterministically

6. conflicting weighting requests
   - `--unweighted` wins
   - warning is printed

7. naming verification
   - all saved tables use canonical `firm__...` names
   - legacy FC aliases exist only for compatibility targets

## Original Acceptance Criteria (Not Implemented Verbatim)

- [ ] `Rscript ... run_politicsregs.R 51` runs the true default baseline only
- [ ] default baseline is unweighted in both code and notes
- [ ] named bundles are implemented through the spec engine, not through separate boolean branches
- [ ] dimension overrides work without requiring a standalone `--`
- [ ] comma-separated override values expand to a Cartesian grid
- [ ] canonical output names use the agreed `firm__...` naming rule
- [ ] custom override runs generate only canonical names
- [ ] compatibility aliases exist for existing presentation dependencies
- [ ] manifest files are written and match produced artifacts
- [ ] weighting, sample mask, notes, and summary metadata are internally consistent

## Assumptions

- Scope is limited to script 51.
- Script 53 may later adopt the same pattern, but this refactor should not block on it.
- The default exposure remains "both" (`pooled_count` and `binary`).
- The default baseline remains `cycle_specific`.
- The default sample remains `all_firms`.
- Canonical names, not FC names, are the long-run interface for downstream consumers.
