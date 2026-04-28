---
title: "Optimize Firm First Stage Runtime with fst Dual-Write"
type: refactor
status: active
date: 2026-03-18
origin: docs/plans/2026-03-16-feat-firm-first-stage-overhaul-plan.md
---

# Optimize Firm First Stage Runtime with `fst` Dual-Write

## Summary

Speed up the firm first-stage pipeline while preserving:
- regression samples,
- variable definitions,
- fixed effects,
- clustering and standard errors,
- weights,
- missing-value handling,
- output tables and saved objects,
- numerical results up to normal floating-point tolerance.

The implementation has two parts:
1. Add dual-write `qs2` + `fst` outputs in [42_build_firm_panel.R](/C:/Users/LENOVO/Desktop/David/Proyectos/Brazil_IP_Code/BNDES/politicsregs/4_regression_panels/42_build_firm_panel.R).
2. Refactor [51_firm_first_stage.R](/C:/Users/LENOVO/Desktop/David/Proyectos/Brazil_IP_Code/BNDES/politicsregs/5_estimation/51_firm_first_stage.R) to reduce repeated I/O, repeated data copies, and repeated estimation.

## Current Script Flow

In [51_firm_first_stage.R](/C:/Users/LENOVO/Desktop/David/Proyectos/Brazil_IP_Code/BNDES/politicsregs/5_estimation/51_firm_first_stage.R), the current execution order is:

1. Load libraries, bootstrap paths, set `data.table` and `fixest` threads, parse `--unweighted`, define FE and VCOV.
2. Define helpers for model fitting, Wald extraction, panel loading, combo-to-instrument mapping, summary extraction, and console printing.
3. Load `cycle_specific` once for metadata discovery only, then free it.
4. Reload `cycle_specific` and estimate FC-1 to FC-4.
5. Reload `cycle_specific` and estimate FC-5.
6. Load `2002_fixed` and estimate FC-6.
7. Reload `cycle_specific` and estimate FC-7.
8. Reload `cycle_specific` and estimate FC-8.
9. Reload `cycle_specific` and estimate FC-9 interaction tables.
10. Reload `cycle_specific` again and estimate the full battery a second time.
11. Bind and save the battery summary.

The main performance losses come from repeated full-panel loads, repeated materialized subsets, and duplicate estimation of coalition weighted models already run for FC-1 to FC-4 and FC-9.

**Quantified waste:**
- `cycle_specific` panel loaded **7 times** (1 metadata + 6 estimation sections)
- `2002_fixed` loaded **1 time** (already efficient)
- Full Battery (step 10) re-estimates all **36 models** (9 combos × 4 margins) already covered by FC-1 to FC-4 (6 main combos × 4 margins = 24) and FC-9 (3 interaction combos × 4 margins = 12)
- **15 `gc()` calls** throughout the script, including inside inner loops on small temporaries

## Implementation Dependency Graph

```
Item 7 (fst dual-write in 42) ──→ Item 8 (fst read in 51)

Item 1 (load once) ──→ Item 2 (masks on loaded panel) ──→ Item 3 (estimate once, reuse)

Item 5 (combo maps) ──→ Item 4 (formula cache from resolved maps)

Item 6 (reduce gc) ── independent, apply at any point
```

**Recommended implementation order:** 7 → 8 → 1 → 5 → 4 → 2 → 3 → 6

Validate after each numbered item. If validation fails at any step, revert that step and investigate before continuing.

## Safe Improvements

Priority order is runtime gain first, then implementation difficulty, then risk.

### 1. Load each baseline once and process it fully before freeing it

In script 51:
- Keep one in-memory object for `cycle_specific`.
- If present, load `2002_fixed` once later, process FC-6, then free it.
- Do not reload `cycle_specific` separately for FC-5, FC-7, FC-8, FC-9, and the battery.

Implementation:
- Replace repeated `load_panel_subset("cycle_specific", ...)` calls with one `dt_cycle`.
- Run all `cycle_specific` sections from `dt_cycle`.
- **Critical: `dt_cycle` must remain unfiltered.** Do not apply `weight_ok` or any other row filter directly to `dt_cycle`. All filtering must happen through masks (Item 2) or `subset=` in `feols`. This is essential for FC-7 (unweighted robustness) which needs the full panel including rows with `NA` or zero `n_employees`.
- Only after all `cycle_specific` work is done: `rm(dt_cycle); gc(verbose = FALSE)`.
- Then load `dt_fixed` only if `firm_panel_for_regs_2002_fixed.*` exists.

Why faster:
- Removes 6 redundant full-panel reads from disk.
- Avoids repeated deserialization and repeated memory churn.

Why results should be unchanged:
- Same rows, same columns, same filters, same models.
- Only execution order changes.

### 2. Replace repeated materialized subsets with precomputed sample masks

In script 51:
- Build logical masks once on the loaded panel.
- Pass those masks via `subset=` to `feols` in `fixest 0.13.2`.
- Do not repeatedly create `dt_sub <- dt[...]` large copies for each spec.

Required masks on each loaded baseline:
- `weight_ok = !is.na(n_employees) & n_employees > 0`
- `levels_ext = rep(TRUE, nrow(dt))`
- `levels_int = has_bndes_fmt == 1L`
- `changes_ext = !is.na(delta_has_bndes_fmt)`
- `changes_int = !is.na(delta_log_bndes_fmt)`
- `single_muni = is_multi_muni == 0L` if available, otherwise `NULL`

Required intersections:
- weighted main:
  - `weight_ok & levels_ext`
  - `weight_ok & levels_int`
  - `weight_ok & changes_ext`
  - `weight_ok & changes_int`
- single-muni weighted:
  - `weight_ok & single_muni & levels_ext`
  - `weight_ok & single_muni & changes_ext`
- unweighted robustness:
  - `levels_ext`
  - `changes_ext`
- party and 2002-fixed:
  - same pattern as main weighted or current script logic

Implementation:
- Add helper `build_sample_masks(dt, apply_weights, has_multi_muni)`.
- Change `fit_firm_model()` to accept `subset_idx = NULL`.
- Call `feols(..., subset = subset_idx, ...)`.

**Singleton equivalence check (must verify before full rollout):**
Before implementing this across all models, run a single model (e.g., FC-1 levels extensive, combo "M") both ways:
1. `feols(..., data = dt[mask])` (current approach)
2. `feols(..., data = dt, subset = mask)` (proposed approach)

Compare: `nobs(mod)`, `mod$nobs_origin`, coefficients, SEs, `wald_f`, and `mod$collin.var`. If any differ, investigate fixest's singleton detection behavior with `subset=` before proceeding. Document the result.

Why faster:
- Avoids repeated large `data.table` copies.
- Lowers memory pressure substantially.
- Keeps one base table in memory.

Why results should be unchanged:
- `subset=` in `fixest` uses the same observations that `dt[mask]` would use.
- The model specification and missing-value logic remain identical.
- Singleton detection within the subset should match pre-filtered behavior in fixest 0.13.2, but the empirical check above confirms this.

### 3. Estimate the coalition / cycle-specific / all / weighted grid once per margin and reuse it

In script 51:
- For each of the 4 main margins:
  - `levels` + `extensive`
  - `levels` + `intensive`
  - `changes` + `extensive`
  - `changes` + `intensive`
- Fit the full 9-combo coalition model set once.
- Use subsets of that model list to produce:
  - FC-1 to FC-4 main tables from `main_combos`
  - FC-9a to FC-9d interaction tables from `interaction_combos`
  - the battery summary from all 9 combos
- Do not re-run those same coalition models in a separate "Full Battery" section.

Implementation:
- For each main margin, build `mods_full` once from `INSTRUMENT_COMBOS`.
- Derive:
  - `mods_main <- mods_full[names(mods_full) %in% main_combos]`
  - `mods_int <- mods_full[names(mods_full) %in% interaction_combos]`
- Save FC tables from those subsets.
- Append battery summary from `mods_full`.
- Remove the current separate "Full Battery" estimation block that duplicates those models.

**Battery summary label preservation:** When extracting battery summary rows from the reused models, the `extract_firm_summary()` call must pass `spec_label = "Battery-..."` (not the FC table label like `"FC-1"`). The current `fc_battery_summary.qs2` uses labels such as `"Battery-levels-extensive"`. Changing these labels would break any downstream code or presentation that filters on `spec`. Preserve them exactly.

**Scope of reuse:** This applies only to coalition/cycle-specific/weighted models. The following remain separate estimation passes and are NOT part of the reuse:
- **FC-5** (party alignment, `align_type = "party"`) — different instruments
- **FC-6** (2002-fixed baseline, `dt_fixed`) — different data
- **FC-7** (unweighted robustness) — different weights/sample
- **FC-8** (single-muni subsample) — different sample

**`lean = TRUE` compatibility:** The current `feols(..., lean = TRUE, mem.clean = TRUE)` discards fitted values and residuals. Before implementing full reuse, verify that `save_beamer_table()` works correctly on lean model objects — specifically that `modelsummary()` does not attempt to access `mod$fitted.values` or `mod$residuals`. Run a quick test with one model: call `save_beamer_table()` on a lean model object, then call it again on the same object. If both succeed, reuse is safe.

Why faster:
- Eliminates duplicate estimation of the same coalition weighted models.
- This is one of the largest expected runtime gains (~36 models saved).

Why results should be unchanged:
- Same formulas and same samples.
- Same model objects are simply reused across outputs.

### 4. Precompute formula objects once

In script 51:
- Build a formula cache keyed by `(align_type, spec_type, depvar, combo)`.
- `fit_firm_model()` should accept a formula object, not a string.
- Do not call `paste()` + `as.formula()` inside every estimation loop.

Implementation:
- Add `build_formula_cache(combo_map)` helper.
- Precompute formulas for:
  - `align_type`: `coalition`, `party`
  - `spec_type`: `levels`, `changes`
  - `depvar`: `has_bndes_fmt`, `log_bndes_fmt`, `delta_has_bndes_fmt`, `delta_log_bndes_fmt`
  - `combo`: all 9 combos that have available columns
- Store as nested named lists.

Why faster:
- Reduces repeated string building and formula parsing.
- The gain is modest, but it is a clean zero-risk optimization.

Why results should be unchanged:
- Formula text is unchanged.
- Only the timing of parsing changes.

### 5. Precompute combo-to-column maps once

In script 51:
- Resolve valid instrument columns for each `(combo, align_type, spec_type)` once after column discovery.
- Skip empty combos before entering estimation loops.

Implementation:
- Add helper `build_combo_map(all_instrument_cols)`.
- For each combination:
  - call current `get_combo_instruments()`,
  - intersect with `all_instrument_cols`,
  - drop combinations with zero available columns.
- Build formulas from this resolved map rather than recomputing intersections repeatedly.

Why faster:
- Avoids repeated `switch()` plus repeated column-existence checks inside all loops.
- This is modest but safe.

Why results should be unchanged:
- Same combos are included or excluded as under current logic.
- The decision is just made once rather than repeatedly.

### 6. Reduce `gc()` frequency

In script 51:
- Keep `gc()` only after freeing:
  - full baseline panels,
  - large model bundles after export.
- Remove per-loop `gc()` calls on small temporaries like `dt_sub` and short model subsets.

Implementation:
- Remove `gc(verbose = FALSE)` inside small inner loops.
- Keep it after:
  - `rm(dt_cycle)`
  - `rm(dt_fixed)`
  - `rm(mods_full)` when a full 9-model bundle is done
- Keep `lean = TRUE` and `mem.clean = TRUE` in `feols`.

Why faster:
- Frequent forced GC can add noticeable overhead.
- The benefit is modest but real when loops are large.

Why results should be unchanged:
- Garbage collection affects memory management, not estimation.

## `fst` Plan

### 7. Script 42: dual-write `qs2` + `fst`

Update [42_build_firm_panel.R](/C:/Users/LENOVO/Desktop/David/Proyectos/Brazil_IP_Code/BNDES/politicsregs/4_regression_panels/42_build_firm_panel.R) so each baseline-specific panel is saved as:
- `firm_panel_for_regs.qs2` and `firm_panel_for_regs.fst`
- `firm_panel_for_regs_2002_fixed.qs2` and `firm_panel_for_regs_2002_fixed.fst`

Implementation:
- Keep current `qs_save()` behavior unchanged.
- After `setorder(firm_panel, year, muni_id, firm_id)`, write `fst` if `requireNamespace("fst", quietly = TRUE)`.
- **Atomic write:** Write to a temporary file (e.g., `firm_panel_for_regs.fst.tmp`) then `file.rename()` to the final path. This prevents a partial `.fst` from being preferred by script 51 over a valid `.qs2` if the write is interrupted. Wrap in `tryCatch`; on failure, `unlink` the temp file, warn, and continue with `qs2` only.
- Use `compress = 50` (fst default). Include this in profiling to determine if `compress = 0` would be faster for column-selective reads.
- If `fst` is unavailable, print a message and continue with `qs2` only.
- Do not change the panel construction logic, joins, zero-filling, or diagnostics.

Why faster:
- `fst` enables fast column-selective reads.
- Script 51 only needs `regression_keep_cols`, so `fst` can avoid full-file reads.

Why results should be unchanged:
- The stored data are identical; only an additional file format is created.

### 8. Script 51: prefer `fst` read, fallback to `qs2`

Update `load_panel_subset()` in [51_firm_first_stage.R](/C:/Users/LENOVO/Desktop/David/Proyectos/Brazil_IP_Code/BNDES/politicsregs/5_estimation/51_firm_first_stage.R) to:
- look first for `firm_panel_for_regs*.fst`,
- if present and `fst` is installed, read only `keep_cols` with `fst::read_fst(..., columns = keep_cols, as.data.table = TRUE)`,
- otherwise fallback to `qs_read()` and then subset columns as currently done.

Implementation:
- Preserve current integer coercions for `firm_id`, `muni_id`, `year`.
- Keep current behavior when `keep_cols = NULL`.
- **Column type verification:** After the first fst read, verify that column types match what qs2 would produce (especially integer vs. double for `firm_id`, `muni_id`, `year`, `is_multi_muni`). If `fst` promotes integers to doubles, add explicit coercions after read. This follows the existing pattern in scripts 21, 22, 30, 31, 35, 36, 41, 42 which already use fst with `as.data.table = TRUE`.

Why faster:
- Reduces I/O and deserialization cost.
- Reduces peak memory on load.

Why results should be unchanged:
- Same rows and columns are read into estimation.

## Higher-Risk Changes Not Included in This Pass

The first implementation pass must not include:
- manual FE singleton removal,
- changing the FE structure,
- changing clustering,
- changing weights,
- replacing `fixest`,
- multi-process model parallelization,
- upstream econometric-specification changes,
- non-atomic output-format changes that remove `qs2`.

## Post-Run Sanity Checks

No formal before/after comparison protocol is needed. The refactoring preserves all logic; only execution order and memory layout change. After the first run of the refactored scripts, do a quick sanity check:

### Script 42 (fst dual-write)

- Confirm `.fst` files exist alongside `.qs2` for each baseline
- Spot-check row count: `nrow(fst::read_fst(..., as.data.table = TRUE))` matches `nrow(qs::qs_read(...))`
- Spot-check column types on key columns (`firm_id`, `muni_id`, `year`, `is_multi_muni`): should be integer, not double

### Script 51 (estimation refactor)

- **One-model singleton check (do once before full rollout of Item 2):** Run FC-1 levels extensive, combo "M" both ways — `feols(data = dt[mask])` vs `feols(data = dt, subset = mask)`. Compare `nobs()`. If identical, proceed with masks everywhere.
- After full run: eyeball `nobs` per table in the console output — unchanged from the last run
- Confirm `fc_battery_summary.qs2` has the same row count and same `spec` labels as before
- Spot-check 1-2 F-stats from FC-1 against the current `.md` output

## Assumptions

- `fixest` version remains `0.13.2`, so logical `subset=` masks are supported.
- `fst` is optional; the pipeline must still run with `qs2` only.
- `qs2` remains the compatibility artifact for the broader pipeline.
- All optimizations in this plan are intended to be specification-preserving.
- Tiny floating-point differences may arise from multithreaded `fixest`, but anything beyond the defined tolerances is treated as a regression.
- Console output order may change due to reordered estimation; only structured artifacts (tables, summary `.qs2`) must match exactly.
