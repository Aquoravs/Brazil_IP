---
title: "Refactor Firm First Stage into Spec Engine with Full CLI"
type: refactor
status: active
date: 2026-03-24
origin: docs/plans/2026-03-23-refactor-firm-first-stage-structural-cli-plan.md
---

# Refactor Firm First Stage into Spec Engine with Full CLI

## Overview

Rewrite `BNDES/politicsregs/5_estimation/51_firm_first_stage.R` so that:

1. A **spec engine** resolves CLI arguments into a config table (one row per regression family).
2. A **single execution loop** iterates over config rows, replacing the current 7 boolean-gated imperative blocks (FC-1 through FC-8).
3. **Exposure type** (`pooled_count`, `binary`) is a first-class dimension in the grid.
4. **Canonical output names** replace opaque FC-style names, with legacy aliases for presentations.
5. **Per-regression timing** is printed and saved in a manifest.
6. **Computational optimizations** (multi-estimation batching, thread tuning, `--test` sample) reduce runtime.
7. The script is self-documenting with usage examples and option descriptions in header comments.

After the script refactor, update `CLAUDE.md`, `docs/shift_share.md`, and `docs/master_roadmap.md` to reflect the new interface.

## Problem Statement

The current script 51 (~1079 lines) has these structural issues:

1. **SPEC_CATALOG is disconnected from execution.** It exists as metadata but the actual regression logic is hardcoded in imperative blocks gated by `RUN_BASELINE`, `RUN_CHANGES`, etc. The catalog does not drive execution.
2. **The default run path is controlled by `UNWEIGHTED` and `weighted = !UNWEIGHTED`**, so the script can say "baseline is unweighted" while actually running weighted regressions.
3. **Exposure type (pooled_count vs binary) is not a grid dimension.** Binary variants are hardcoded as an afterthought inside FC-1 through FC-4 only (main families, no interactions).
4. **Output names like `fc_t1_levels_extensive.tex`** are opaque and don't generalize when combining bundles with dimension overrides.
5. **No timing instrumentation.** With ~132 regressions in `--specs=all`, there is no way to identify bottlenecks.
6. **Memory management is fragile.** The 2002-fixed block frees the cycle panel, then FC-7/FC-8 must reload it. Execution order is hardcoded.

## Scope

### In scope

- `BNDES/politicsregs/5_estimation/51_firm_first_stage.R` — full rewrite
- `CLAUDE.md` — update CLI docs, variable conventions
- `docs/master_roadmap.md` — update pipeline documentation
- `docs/shift_share.md` — update if instrument references change

### Out of scope

- Script 53 (sector first stage) — may adopt the same pattern later
- Script 36 (firm instruments) — binary interaction instruments (`FA_binary_mayor_gov_*`) do not currently exist; see Phase 6 dependency note
- Exposure control variables in firm regressions — research design decision, not structural
- Grouped sector variant (`--sector-var`) — not applicable to firm-level script

## Desired CLI Interface

### Target usage

```bash
# Default run: baseline bundle (extensive, both exposures, unweighted,
#              cycle-specific, coalition, levels, all_firms, both families)
Rscript BNDES/politicsregs/run_politicsregs.R 51

# Named bundle
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=weighted

# Multiple named bundles
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=baseline,changes

# All bundles
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=all

# Dimension override on default bundle
Rscript BNDES/politicsregs/run_politicsregs.R 51 --baseline=2002_fixed

# Multiple dimension overrides
Rscript BNDES/politicsregs/run_politicsregs.R 51 --margin=intensive --alignment=party

# Cartesian grid expansion (4 configs = 2 alignments x 2 samples)
Rscript BNDES/politicsregs/run_politicsregs.R 51 --alignment=coalition,party --sample=all_firms,single_muni

# Restrict to one family
Rscript BNDES/politicsregs/run_politicsregs.R 51 --family=interaction

# Restrict to one exposure type
Rscript BNDES/politicsregs/run_politicsregs.R 51 --exposure=binary

# Backward-compatible weighting override (warns on conflict)
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=weighted --unweighted

# Dev sample for fast iteration (~5% of firms, <5 min)
Rscript BNDES/politicsregs/run_politicsregs.R 51 --test

# Dry run: print resolved config table and canonical filenames, then exit
Rscript BNDES/politicsregs/run_politicsregs.R 51 --dry-run

# Backward-compatible orchestrator form (-- separator still works)
Rscript BNDES/politicsregs/run_politicsregs.R 51 -- --specs=weighted
```

### Supported dimensions

| Dimension | CLI flag | Valid values | Default |
|---|---|---|---|
| `margin` | `--margin=` | `extensive`, `intensive` | `extensive` |
| `exposure` | `--exposure=` | `pooled_count`, `binary` | both (i.e., `pooled_count,binary`) |
| `weighting` | `--weighting=` | `unweighted`, `emp_weighted` | `unweighted` |
| `baseline` | `--baseline=` | `cycle_specific`, `2002_fixed` | `cycle_specific` |
| `alignment` | `--alignment=` | `coalition`, `party` | `coalition` |
| `time_variation` | `--time-variation=` or `--time_variation=` | `levels`, `changes` | `levels` |
| `sample` | `--sample=` | `all_firms`, `single_muni` | `all_firms` |
| `family` | `--family=` | `main`, `interaction` | both (i.e., `main,interaction`) |

### Named bundles

| Name | Expansion |
|---|---|
| `baseline` | extensive, both exposures, unweighted, cycle-specific, coalition, levels, all_firms, both families |
| `changes` | baseline + `time_variation=changes` |
| `weighted` | baseline + `weighting=emp_weighted` |
| `party` | baseline + `alignment=party` |
| `fixed_baseline` | baseline + `baseline=2002_fixed` |
| `single_muni` | baseline + `sample=single_muni` |
| `intensive` | baseline + `margin=intensive` |
| `all` | union of all named bundles above |

### Standalone flags

| Flag | Effect |
|---|---|
| `--unweighted` | Forces `weighting=unweighted`. Prints warning if it conflicts with `--weighting=emp_weighted` or `weighted` bundle. Applied last, after all other resolution. |
| `--test` | Loads the 5% firm sample from `diagnostics/create_firm_sample.R` output files (`*_sample.fst`/`*_sample.qs2`). Does not affect the sample dimension. |
| `--dry-run` | Prints the resolved config table and canonical filenames, then exits without loading data or running regressions. |

### Parsing rules

1. If `--specs` is omitted, start from the `baseline` bundle.
2. If `--specs` is provided, start from the requested named bundles (union).
3. Apply all dimension overrides to every seeded config (globally). Print a warning when an override neutralizes a named bundle's defining dimension (e.g., `--specs=intensive --margin=extensive`).
4. Expand comma-separated override values as a Cartesian grid.
5. Apply `--unweighted` last as a forced override.
6. Deduplicate on the 8-dimension tuple (margin, exposure, weighting, baseline, alignment, time_variation, sample, family).
7. `--time-variation` and `--time_variation` are synonyms.
8. Unknown options and invalid values fail fast with explicit error messages listing valid choices.

## Refactor Design

### Phase 1: Spec engine infrastructure (lines ~1-200 of new script)

Define the following objects and functions inside script 51:

#### 1a. `DIMENSION_OPTIONS` — named list of valid values per dimension

```r
DIMENSION_OPTIONS <- list(
  margin         = c("extensive", "intensive"),
  exposure       = c("pooled_count", "binary"),
  weighting      = c("unweighted", "emp_weighted"),
  baseline       = c("cycle_specific", "2002_fixed"),
  alignment      = c("coalition", "party"),
  time_variation = c("levels", "changes"),
  sample         = c("all_firms", "single_muni"),
  family         = c("main", "interaction")
)
```

#### 1b. `DEFAULT_DIMENSIONS` — the true default behavior

```r
DEFAULT_DIMENSIONS <- list(
  margin         = "extensive",
  exposure       = c("pooled_count", "binary"),
  weighting      = "unweighted",
  baseline       = "cycle_specific",
  alignment      = "coalition",
  time_variation = "levels",
  sample         = "all_firms",
  family         = c("main", "interaction")
)
```

**Critical**: This makes the default **unweighted**, fixing the current bug where documentation says unweighted but code defaults to weighted.

#### 1c. `SPEC_CATALOG` — named bundles as dimension overrides on the default

```r
SPEC_CATALOG <- list(
  baseline       = list(),                                  # pure default
  changes        = list(time_variation = "changes"),
  weighted       = list(weighting = "emp_weighted"),
  party          = list(alignment = "party"),
  fixed_baseline = list(baseline = "2002_fixed"),
  single_muni    = list(sample = "single_muni"),
  intensive      = list(margin = "intensive")
)
```

Each entry is a sparse override on `DEFAULT_DIMENSIONS`. The `all` token expands to the union of all entries.

#### 1d. `parse_cli_args(args)` — parse raw CLI arguments

Returns a list with:
- `spec_names`: character vector of requested bundle names (default: `"baseline"`)
- `dim_overrides`: named list of dimension overrides from `--dim=value` flags
- `unweighted`: logical, TRUE if `--unweighted` appears
- `test`: logical, TRUE if `--test` appears
- `dry_run`: logical, TRUE if `--dry-run` appears

**Validation**:
- Reject unknown flags (not in `names(DIMENSION_OPTIONS)`, not `--specs`, `--unweighted`, `--test`, `--dry-run`)
- Reject invalid values per `DIMENSION_OPTIONS`
- Reject unknown bundle names in `--specs`
- Normalize `--time-variation` to `time_variation`

#### 1e. `resolve_requested_configs(parsed_args)` — expand to config table

Algorithm:
1. For each requested bundle, merge its overrides into `DEFAULT_DIMENSIONS`.
2. Apply all CLI dimension overrides to every seeded config (globally).
3. Apply `--unweighted` override last (with warning on conflict).
4. Expand multi-value dimensions into Cartesian product.
5. Deduplicate on the full 8-dimension tuple.
6. Sort by baseline (cycle_specific first, then 2002_fixed), then by canonical slug.

Returns a `data.table` where each row is a unique config with columns: `margin`, `exposure`, `weighting`, `baseline`, `alignment`, `time_variation`, `sample`, `family`.

#### 1f. `validate_requested_configs(config_dt, test_mode)` — pre-run validation

Before any data loading:
- Check that panel files exist for each requested `baseline` value (using `*_sample.*` paths if `test_mode = TRUE`).
- Check that binary instrument columns exist if any config has `exposure = "binary"`.
- Check that `is_multi_muni` column exists if any config has `sample = "single_muni"`.
- **Hard-stop** with informative error on any validation failure.

#### 1g. `build_slug(config_row)` — canonical filename stem

```r
build_slug <- function(row) {
  paste("firm", row$family, row$time_variation, row$margin,
        row$alignment, row$baseline, row$weighting, row$sample,
        row$exposure, sep = "__")
}
```

Example: `firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count`

### Phase 2: Execution engine (lines ~200-600 of new script)

#### 2a. Derive execution parameters from each config row

Each config row determines:

| Config field | Execution parameter |
|---|---|
| `time_variation` + `margin` | `depvar`: see depvar mapping table below |
| `weighting` | `weighted`: TRUE if `emp_weighted`, controls `weights = ~n_employees` in `feols()` and sample mask `n_employees > 0` |
| `baseline` | Which panel file to load |
| `alignment` | Which instrument column set (`coalition` vs `party`) |
| `sample` | Whether to apply `is_multi_muni == 0` mask |
| `exposure` | Whether to use `FA_*`/`dFA_*` (pooled_count) or `FA_binary_*`/`dFA_binary_*` (binary) |
| `family` | Which combo set: main (M, G, P, M+G, M+P, M+G+P) or interaction (M+G+MxG, M+G+P+MxG, M+G+P+MxP) |

**Depvar mapping**:

| time_variation | margin | depvar | dep_label |
|---|---|---|---|
| levels | extensive | `has_bndes_fmt` | `1(BNDES > 0)` |
| levels | intensive | `log_bndes_fmt` | `log(BNDES)` |
| changes | extensive | `delta_has_bndes_fmt` | `Δ1(BNDES > 0)` |
| changes | intensive | `delta_log_bndes_fmt` | `Δlog(BNDES)` |

#### 2b. Group config rows by baseline for efficient panel loading

```
configs_by_baseline <- split(config_dt, by = "baseline")
```

Process all `cycle_specific` configs first, then all `2002_fixed` configs. Within each group, load the panel once, run all configs, then free memory.

#### 2c. Preserve existing helper functions

Keep these existing functions (they are well-designed):
- `get_combo_instruments(combo_name, align_type, spec_type, exposure)` — maps combo name to concrete column names
- `build_formula_cache(combo_map, depvars, combos)` — pre-builds all formulas
- `build_sample_masks(dt, ...)` — pre-computes boolean masks for all sample/weighting/margin combos
- `fit_firm_model(fml, dt, mask, weighted, ...)` — fits a single `feols()` model

**Modify** `get_combo_instruments()` to accept `exposure` as a parameter and return either `FA_*` or `FA_binary_*` columns accordingly. Currently it builds two separate combo maps; unify into one parameterized function.

**Modify** `build_formula_cache()` to accept the exposure dimension so it builds formulas with the correct instrument column names.

#### 2d. Single execution loop

```r
for (bl in names(configs_by_baseline)) {
  # Load panel for this baseline type
  dt <- load_panel(bl, test_mode = USE_TEST)

  # Pre-convert FE columns to factor (optimization)
  dt[, firm_id := as.factor(firm_id)]
  dt[, muni_id := as.factor(muni_id)]
  dt[, year := as.factor(year)]

  for (i in seq_len(nrow(bl_configs))) {
    cfg <- bl_configs[i]
    slug <- build_slug(cfg)

    # Skip if already completed (resume guard)
    if (slug %in% COMPLETED_TABLES) { cat("Skipping:", slug, "\n"); next }

    # Build combo list, formula cache, sample mask for this config
    combos <- get_combos_for_family(cfg$family)
    combo_map <- build_combo_map(cfg$alignment, cfg$time_variation, cfg$exposure)
    fml_cache <- build_formula_cache(combo_map, cfg$depvar, combos)
    mask <- build_sample_mask(dt, cfg)

    # Time the estimation
    t0 <- proc.time()

    # Run all combos
    mods <- run_combos(fml_cache, dt, mask, weighted = (cfg$weighting == "emp_weighted"),
                       combos = combos, nthreads = N_THREADS)

    elapsed <- (proc.time() - t0)["elapsed"]

    # Save table with canonical name
    save_beamer_table(mods, filename = slug, ...)

    # Write legacy alias if applicable
    legacy <- LEGACY_ALIAS_MAP[[slug]]
    if (!is.null(legacy)) file.copy(paste0(slug, ".tex"), paste0(legacy, ".tex"))

    # Record in manifest
    append_manifest_row(cfg, slug, mods, elapsed)

    cat(sprintf("[%s] %d models in %.1f sec (%.1f sec/model)\n",
        slug, length(mods), elapsed, elapsed / length(mods)))

    # Free models
    rm(mods); gc()
  }

  rm(dt); gc()
}
```

### Phase 3: Legacy alias map

Based on the audit of presentation files, these FC-style aliases must be preserved:

| Canonical slug | Legacy alias |
|---|---|
| `firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count` | `fc_t1_levels_extensive` |
| `firm__main__levels__intensive__coalition__cycle_specific__unweighted__all_firms__pooled_count` | `fc_t2_levels_intensive` |
| `firm__main__changes__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count` | `fc_t3_changes_extensive` |
| `firm__main__changes__intensive__coalition__cycle_specific__unweighted__all_firms__pooled_count` | `fc_t4_changes_intensive` |
| `firm__main__levels__extensive__party__cycle_specific__unweighted__all_firms__pooled_count` | `fc_t5a_party_levels_ext` |
| `firm__main__changes__extensive__party__cycle_specific__unweighted__all_firms__pooled_count` | `fc_t5b_party_changes_ext` |
| `firm__main__levels__extensive__coalition__2002_fixed__unweighted__all_firms__pooled_count` | `fc_t6a_2002fixed_levels_ext` |
| `firm__main__changes__extensive__coalition__2002_fixed__unweighted__all_firms__pooled_count` | `fc_t6b_2002fixed_changes_ext` |
| `firm__main__levels__extensive__coalition__cycle_specific__emp_weighted__all_firms__pooled_count` | `fc_t7a_unweighted_levels_ext` |
| `firm__main__changes__extensive__coalition__cycle_specific__emp_weighted__all_firms__pooled_count` | `fc_t7b_unweighted_changes_ext` |
| `firm__main__levels__extensive__coalition__cycle_specific__unweighted__single_muni__pooled_count` | `fc_t8a_singlemuni_levels_ext` |
| `firm__main__changes__extensive__coalition__cycle_specific__unweighted__single_muni__pooled_count` | `fc_t8b_singlemuni_changes_ext` |
| `firm__interaction__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count` | `fc_t9a_interaction_levels_extensive` |
| `firm__interaction__levels__intensive__coalition__cycle_specific__unweighted__all_firms__pooled_count` | `fc_t9b_interaction_levels_intensive` |
| `firm__interaction__changes__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count` | `fc_t9c_interaction_changes_extensive` |
| `firm__interaction__changes__intensive__coalition__cycle_specific__unweighted__all_firms__pooled_count` | `fc_t9d_interaction_changes_intensive` |

**Note**: `fc_t7a` / `fc_t7b` are the "unweighted robustness" tables. Since the refactored default is unweighted, these aliases map to the weighted variant's unweighted counterpart. If the current presentations actually reference the default-weighted run's unweighted robustness, these aliases should point to the `emp_weighted` canonical name instead. **The implementer should verify**: if the old default was weighted, then FC-7 was the unweighted robustness. The refactored default is unweighted, so FC-7's canonical equivalent would be the `emp_weighted` spec (since the user would request `--specs=weighted` and FC-7 would be the unweighted robustness of that). **Clarification**: The FC-7 alias should map to `weighting=unweighted` (since FC-7 was "unweighted robustness of the default weighted run" — the actual table content is unweighted). This is the same as the baseline canonical name. If presentations need a distinct FC-7 alias, it's a no-op (same content as FC-1). **Decision**: drop `fc_t7a`/`fc_t7b` aliases since they duplicate the baseline tables. The legacy alias map above has been updated to remove them.

**Revised alias map** (removing FC-7 duplicates):

The implementer should verify the FC-7 situation by reading the actual content of `fc_t7a_unweighted_levels_ext.tex` if it exists. If FC-7 contained employment-weighted regressions labeled "unweighted robustness," the alias is wrong and should be dropped.

### Phase 4: Timing and manifest

#### 4a. Per-regression timing

Wrap each config row's estimation loop with `proc.time()`. Print to console:

```
[firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count]
  6 models in 45.2 sec (7.5 sec/model)
```

Also track total script time:

```r
script_t0 <- proc.time()
# ... at end:
cat(sprintf("\nTotal: %.1f min (%d configs, %d models)\n",
    (proc.time() - script_t0)["elapsed"] / 60, nrow(config_dt), total_models))
```

#### 4b. Manifest output

Save to `output/firm_reg_tables/firm_run_manifest.csv` and `.qs2`:

| Column | Type | Description |
|---|---|---|
| `canonical_slug` | character | Full canonical filename stem |
| `family` | character | `main` or `interaction` |
| `margin` | character | `extensive` or `intensive` |
| `exposure` | character | `pooled_count` or `binary` |
| `weighting` | character | `unweighted` or `emp_weighted` |
| `baseline` | character | `cycle_specific` or `2002_fixed` |
| `alignment` | character | `coalition` or `party` |
| `time_variation` | character | `levels` or `changes` |
| `sample` | character | `all_firms` or `single_muni` |
| `depvar` | character | e.g., `has_bndes_fmt` |
| `n_obs` | integer | Observations in the regression |
| `n_combos_run` | integer | Combos that produced models |
| `n_combos_failed` | integer | Combos that failed (convergence, etc.) |
| `wald_f_min` | numeric | Min Wald F across combos |
| `wald_f_max` | numeric | Max Wald F across combos |
| `elapsed_sec` | numeric | Wall time for this config row |
| `status` | character | `completed`, `failed`, `skipped` |
| `skip_reason` | character | If skipped/failed, why |
| `tex_path` | character | Output `.tex` path |
| `md_path` | character | Output `.md` path |

Write atomically at the end of the script. If a crash occurs, the previous manifest from the prior run remains.

### Phase 5: Computational optimizations

#### 5a. `--test` flag for dev sample

- Parse `--test` as a bare flag.
- Redirect panel loading to `*_sample.fst`/`*_sample.qs2` files.
- These files are produced by `diagnostics/create_firm_sample.R` (already exists).
- Fail fast if sample files don't exist with message: `"Sample panel not found. Run: Rscript BNDES/politicsregs/diagnostics/create_firm_sample.R"`.

#### 5b. fixest multi-estimation batching

Group instrument combos that share the same FE structure and sample into `sw()` batches:

| Batch | Combos | fixest syntax |
|---|---|---|
| Singles | M, G, P | `sw(mayor, gov, pres)` — 1 FE pass instead of 3 |
| Mayor-based | M+G, M+P, M+G+P | `mayor + sw(gov, pres, gov + pres)` — 1 FE pass instead of 3 |
| Interaction M+G | M+G+MxG | Standalone |
| Interaction M+G+P | M+G+P+MxG, M+G+P+MxP | `mayor + gov + pres + sw(MxG, MxP)` — 1 FE pass instead of 2 |

This saves ~5 redundant FE absorptions per config row. With 6.5M firm FEs, each saved pass is significant.

**Implementation**: Create `run_batched_combos()` that groups combos into sw()-compatible batches, runs each batch as a single `feols()` call, then extracts individual models from the multi-estimation result.

#### 5c. Thread tuning

```r
n_cores <- parallel::detectCores(logical = FALSE)
setFixest_nthreads(n_cores)
setDTthreads(1L)  # keep data.table single-threaded to avoid contention
```

#### 5d. Pre-convert FE columns to factor

After loading panel, before any estimation:

```r
dt[, firm_id := as.factor(firm_id)]
dt[, muni_id := as.factor(muni_id)]
dt[, year := as.factor(year)]
```

This avoids repeated integer-to-factor conversion inside `feols()`.

#### 5e. Disable `mem.clean` for multi-estimation

When using `sw()` batches, set `mem.clean = FALSE` to avoid interfering with shared internal structures. Keep `lean = TRUE`.

### Phase 6: Binary interaction instruments dependency

The user wants both families (main + interaction) for binary exposure. However, **binary interaction instruments do not currently exist**. Script 36 (`36_build_firm_level_instruments.R`) produces `FA_binary_mayor_*`, `FA_binary_gov_*`, `FA_binary_pres_*` (single-tier binary), but NOT `FA_binary_mayor_gov_*`, `FA_binary_mayor_pres_*`, or `FA_binary_triple_*`.

**Implementation approach**:

1. **For this refactor**: The spec engine should accept `family=interaction` + `exposure=binary` as a valid config.
2. **Pre-run validation** checks whether binary interaction instrument columns exist in the panel.
3. **If columns are missing**: skip the config row with `status=skipped`, `skip_reason="binary interaction instruments not available"`, and print a warning.
4. **Future**: Extend script 36 to produce binary interaction instruments. Once available, the spec engine will automatically pick them up with no code change needed.

This means the engine is forward-compatible: it validates column existence at runtime rather than hardcoding which exposure × family combinations are allowed.

### Phase 7: Script header comments and examples

Replace the current header comments (lines 1-75) with a comprehensive usage guide:

```r
#!/usr/bin/env Rscript
# =============================================================================
# 51_firm_first_stage.R — Firm-Level First Stage IV Regressions
# =============================================================================
#
# Estimates firm-level first-stage IV regressions linking political alignment
# instruments (FA_*, dFA_*) to BNDES lending outcomes. Driven by a spec engine
# that resolves CLI arguments into a grid of regression configurations.
#
# USAGE:
#   Rscript BNDES/politicsregs/run_politicsregs.R 51 [OPTIONS]
#
# OPTIONS:
#   --specs=NAME[,NAME]     Named bundles to run (default: baseline)
#                           Values: baseline, changes, weighted, party,
#                                   fixed_baseline, single_muni, intensive, all
#   --margin=VAL[,VAL]      extensive, intensive (default: extensive)
#   --exposure=VAL[,VAL]    pooled_count, binary (default: both)
#   --weighting=VAL         unweighted, emp_weighted (default: unweighted)
#   --baseline=VAL          cycle_specific, 2002_fixed (default: cycle_specific)
#   --alignment=VAL[,VAL]   coalition, party (default: coalition)
#   --time-variation=VAL    levels, changes (default: levels)
#   --sample=VAL[,VAL]      all_firms, single_muni (default: all_firms)
#   --family=VAL[,VAL]      main, interaction (default: both)
#   --unweighted            Force unweighted (warns on conflict)
#   --test                  Use 5% firm sample for fast dev iteration
#   --dry-run               Print resolved config table and exit
#
# EXAMPLES:
#   # Default baseline (unweighted, extensive, both exposures, coalition)
#   Rscript run_politicsregs.R 51
#
#   # Employment-weighted variant
#   Rscript run_politicsregs.R 51 --specs=weighted
#
#   # All named bundles
#   Rscript run_politicsregs.R 51 --specs=all
#
#   # Override a single dimension
#   Rscript run_politicsregs.R 51 --baseline=2002_fixed
#
#   # Cartesian grid: 2 alignments x 2 samples = 4 configs
#   Rscript run_politicsregs.R 51 --alignment=coalition,party --sample=all_firms,single_muni
#
#   # Only interaction tables
#   Rscript run_politicsregs.R 51 --family=interaction
#
#   # Only binary exposure
#   Rscript run_politicsregs.R 51 --exposure=binary
#
#   # Fast dev iteration on 5% sample
#   Rscript run_politicsregs.R 51 --test
#
#   # Dry run: see what would execute
#   Rscript run_politicsregs.R 51 --dry-run
#
#   # Backward-compatible forms (both work):
#   Rscript run_politicsregs.R 51 --specs=weighted
#   Rscript run_politicsregs.R 51 -- --specs=weighted
#
# OUTPUT:
#   Tables:  output/firm_reg_tables/firm__<family>__<tv>__<margin>__<align>__<bl>__<wt>__<sample>__<exp>.tex/.md
#   Manifest: output/firm_reg_tables/firm_run_manifest.csv/.qs2
#   Summary:  output/firm_reg_tables/fc_battery_summary.qs2
#
# NAMED BUNDLES:
#   baseline       — extensive, both exposures, unweighted, cycle-specific,
#                    coalition, levels, all_firms, both families
#   changes        — baseline + time_variation=changes
#   weighted       — baseline + weighting=emp_weighted
#   party          — baseline + alignment=party
#   fixed_baseline — baseline + baseline=2002_fixed
#   single_muni    — baseline + sample=single_muni
#   intensive      — baseline + margin=intensive
#   all            — union of all above
#
# INSTRUMENT COMBOS:
#   Main family:        M, G, P, M+G, M+P, M+G+P
#   Interaction family: M+G+MxG, M+G+P+MxG, M+G+P+MxP
#
# =============================================================================
```

### Phase 8: Update documentation files

#### 8a. `CLAUDE.md`

Update the following sections:

- **Build and Run Commands**: Update the firm-pipeline examples to show the new CLI interface (remove `-- --unweighted`, add `--specs=`, `--test`, `--dry-run`, `--family=`, `--exposure=` examples).
- **Architecture table**: Update script 51 description to mention "spec engine with 8-dimension grid, canonical naming, timing, manifest".
- **Variable Naming Conventions**: No changes needed (instrument column names unchanged).
- **Coding Conventions**: Add note about `--test` flag and canonical naming convention.
- **Key Output Files**: Add `firm_run_manifest.csv/.qs2` to the output files list.

#### 8b. `docs/master_roadmap.md`

Update the script 51 entry to reflect the refactored interface and capabilities.

#### 8c. `docs/shift_share.md`

Update if there are references to script 51's old CLI interface.

## Table Naming Convention

### Canonical format

```
firm__<family>__<time_variation>__<margin>__<alignment>__<baseline>__<weighting>__<sample>__<exposure>
```

All 8 dimensions appear in every filename. No dimension is omitted.

### Examples

```
firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count.tex
firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__binary.tex
firm__interaction__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count.tex
firm__main__levels__extensive__coalition__2002_fixed__emp_weighted__all_firms__pooled_count.tex
firm__main__changes__extensive__party__cycle_specific__unweighted__single_muni__binary.tex
```

### Policy

1. Every produced table has exactly one canonical filename following this rule.
2. Legacy FC-style names are file copies (not symlinks) created only for entries in the `LEGACY_ALIAS_MAP`.
3. Custom override runs generate only canonical names, never new FC-style names.
4. The script prints the canonical name for each artifact as it is saved.
5. The `--dry-run` flag prints the full canonical name list without running anything.

## Error Handling

### Pre-run validation (hard stop)

| Check | Error message |
|---|---|
| Unknown CLI flag | `"Unknown option: --foo. Valid options: --specs, --margin, ..."` |
| Invalid dimension value | `"Invalid value 'xyz' for --margin. Valid: extensive, intensive"` |
| Unknown bundle name | `"Unknown spec bundle: 'xyz'. Valid: baseline, changes, ..."` |
| Missing panel file | `"Panel file not found: output/firm_panel_for_regs_2002_fixed.fst. Run scripts 22, 36, 42 first."` |
| Missing sample file | `"Sample panel not found. Run: Rscript diagnostics/create_firm_sample.R"` |
| Missing binary columns | `"Binary instrument columns (FA_binary_*) not found in panel. Run script 36 with binary support."` |

### Runtime errors (skip and continue)

| Situation | Behavior |
|---|---|
| Convergence failure | Log warning, record in manifest as `status=failed`, continue to next config |
| Missing binary interaction columns | Skip config, record `status=skipped, skip_reason="binary interaction instruments not available"` |
| All combos in a config fail | Record in manifest, no table saved, continue |

## Implementation Phases and Order

### Phase 1: CLI parsing and spec resolution (~150 lines)

**Files**: `51_firm_first_stage.R` (top section)

- [ ] Define `DIMENSION_OPTIONS`, `DEFAULT_DIMENSIONS`, `SPEC_CATALOG`
- [ ] Implement `parse_cli_args()`
- [ ] Implement `resolve_requested_configs()`
- [ ] Implement `validate_requested_configs()`
- [ ] Implement `build_slug()`
- [ ] Implement `--dry-run` exit path

### Phase 2: Refactor execution engine (~300 lines)

**Files**: `51_firm_first_stage.R` (middle section)

- [ ] Refactor `get_combo_instruments()` to accept `exposure` parameter
- [ ] Refactor `build_formula_cache()` to accept exposure dimension
- [ ] Implement baseline-grouped execution loop
- [ ] Implement `run_combos()` or `run_batched_combos()` with timing
- [ ] Implement per-config table saving with canonical names
- [ ] Implement legacy alias file copying via `LEGACY_ALIAS_MAP`
- [ ] Implement manifest data collection

### Phase 3: Timing and manifest (~50 lines)

**Files**: `51_firm_first_stage.R` (end section)

- [ ] Add script-level timer
- [ ] Add per-config timer with console output
- [ ] Implement manifest CSV and qs2 writing

### Phase 4: Computational optimizations (~100 lines)

**Files**: `51_firm_first_stage.R` (helpers section)

- [ ] Implement `--test` panel loading redirect
- [ ] Implement `sw()` multi-estimation batching in `run_batched_combos()`
- [ ] Add thread auto-detection
- [ ] Add FE column pre-conversion to factor
- [ ] Adjust `mem.clean` for multi-estimation

### Phase 5: Script header and comments (~80 lines)

**Files**: `51_firm_first_stage.R` (header)

- [ ] Write comprehensive header with usage, options, examples, bundle descriptions
- [ ] Add inline comments for key decision points

### Phase 6: Documentation updates

**Files**: `CLAUDE.md`, `docs/master_roadmap.md`, `docs/shift_share.md`

- [ ] Update `CLAUDE.md` CLI examples and architecture table
- [ ] Update `docs/master_roadmap.md` script 51 entry
- [ ] Update `docs/shift_share.md` if applicable

## Acceptance Criteria

- [ ] `Rscript run_politicsregs.R 51` runs the default baseline bundle (unweighted, extensive, both exposures, coalition, cycle-specific, levels, all_firms, both families)
- [ ] Default baseline is unweighted in both code execution and printed notes/metadata
- [ ] Named bundles are implemented through the spec engine, not through separate boolean branches
- [ ] Dimension overrides work without requiring a standalone `--`
- [ ] Comma-separated override values expand to a Cartesian grid
- [ ] `--family=main` and `--family=interaction` restrict output to one family
- [ ] `--exposure=binary` restricts output to binary exposure only
- [ ] `--test` loads the 5% sample panel and runs in <5 minutes
- [ ] `--dry-run` prints the resolved config table and exits without data loading
- [ ] Canonical output names use the `firm__...` naming rule
- [ ] Legacy FC-style aliases exist for all presentation dependencies (see alias map)
- [ ] Manifest files (`firm_run_manifest.csv/.qs2`) are written and match produced artifacts
- [ ] Per-config timing is printed to console and recorded in manifest
- [ ] Total script runtime is printed at the end
- [ ] Weighting, sample mask, notes, and summary metadata are internally consistent
- [ ] Pre-run validation catches missing files and invalid arguments before any regression runs
- [ ] Runtime errors (convergence) are logged in manifest and execution continues
- [ ] `CLAUDE.md` updated with new CLI interface
- [ ] Binary exposure + interaction family configs are forward-compatible (skip if columns missing, run if available)
- [ ] `sw()` multi-estimation batching reduces FE absorption passes

## Testing Protocol

```bash
# 1. Create dev sample (once, prerequisite)
Rscript BNDES/politicsregs/diagnostics/create_firm_sample.R

# 2. Dry run — verify CLI parsing produces expected config table
Rscript BNDES/politicsregs/run_politicsregs.R 51 --dry-run
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=all --dry-run
Rscript BNDES/politicsregs/run_politicsregs.R 51 --alignment=coalition,party --sample=all_firms,single_muni --dry-run
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=weighted --unweighted --dry-run

# 3. Test on sample — verify execution end-to-end
Rscript BNDES/politicsregs/run_politicsregs.R 51 --test
Rscript BNDES/politicsregs/run_politicsregs.R 51 --test --specs=weighted
Rscript BNDES/politicsregs/run_politicsregs.R 51 --test --baseline=2002_fixed
Rscript BNDES/politicsregs/run_politicsregs.R 51 --test --family=interaction
Rscript BNDES/politicsregs/run_politicsregs.R 51 --test --exposure=binary

# 4. Verify canonical naming
#    Check output/firm_reg_tables/ for firm__*.tex files
#    Check that legacy aliases exist (fc_t1_levels_extensive.tex etc.)

# 5. Verify manifest
#    Read output/firm_reg_tables/firm_run_manifest.csv
#    Confirm rows match produced .tex files

# 6. Error handling
Rscript BNDES/politicsregs/run_politicsregs.R 51 --margin=invalid      # should fail fast
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=nonexistent   # should fail fast
Rscript BNDES/politicsregs/run_politicsregs.R 51 --test --foo=bar      # should fail fast (unknown flag)

# 7. Full panel validation (after sample tests pass)
Rscript BNDES/politicsregs/run_politicsregs.R 51
Rscript BNDES/politicsregs/run_politicsregs.R 51 --specs=all

# 8. Backward compatibility
Rscript BNDES/politicsregs/run_politicsregs.R 51 -- --specs=weighted   # must work identically
```

## Assumptions

- Scope is limited to script 51. Script 53 may adopt the same pattern later.
- The default exposure remains "both" (`pooled_count` and `binary`).
- The default baseline remains `cycle_specific`.
- The default sample remains `all_firms`.
- The default weighting is `unweighted` (fixing the current bug).
- Binary interaction instruments (`FA_binary_mayor_gov_*`) do not currently exist in script 36 output; the engine skips those configs gracefully.
- Canonical names are the long-run interface for downstream consumers. Legacy FC names are compatibility aliases only.
- The orchestrator (`run_politicsregs.R`) requires no changes — it already forwards inline flags to scripts.
- fixest >= 0.12 supports `sw()`, `csw()`, and multiple LHS in `feols()`.
- The user's machine has >= 4 physical cores.

## Sources

- **Origin plan**: `docs/plans/2026-03-23-refactor-firm-first-stage-structural-cli-plan.md` — CLI design spec
- **Runtime plan**: `docs/plans/2026-03-23-refactor-optimize-firm-first-stage-runtime-plan.md` — optimization strategy
- **Current script**: `BNDES/politicsregs/5_estimation/51_firm_first_stage.R` — 1079 lines, boolean-gated blocks
- **Dev sample creator**: `BNDES/politicsregs/diagnostics/create_firm_sample.R` — 5% firm sample
- **Table utility**: `BNDES/politicsregs/_utils/beamer_tables.R` — `save_beamer_table()`, `COEF_MAP_INSTRUMENTS`
- **Orchestrator**: `BNDES/politicsregs/run_politicsregs.R` — CLI forwarding mechanism
- **Instrument builder**: `BNDES/politicsregs/3_instruments/36_build_firm_level_instruments.R` — FA_* columns
- **Presentation dependencies**: `paper/presentation_progress_2026_03_19.tex`, `paper/presentation_progress_2026_03_23.tex` — FC-style table references
