---
title: "Optimize Firm First Stage Runtime with Sample Testing and Timing"
type: refactor
status: active
date: 2026-03-23
origin: docs/plans/2026-03-18-optimize-firm-first-stage-runtime-with-fst-plan.md
---

# Optimize Firm First Stage Runtime with Sample Testing and Timing

## Overview

Script `51_firm_first_stage.R` runs 48+ `feols()` calls on a 44M-row panel with ~6.5M firm FEs and ~89K muni×year FEs. Even the baseline bundle (12 combos × 4 margins) exceeds 60 minutes. The prior optimization plan (2026-03-18) addressed I/O waste (repeated panel loads, materialized subsets); those fixes are now implemented. The remaining bottleneck is **purely computational**: FE absorption on a massive panel.

This plan adds:
1. A random-sample creator for fast dev/test iterations
2. Per-table timing instrumentation
3. Computational optimizations targeting FE absorption cost

## Current Performance Profile

| Metric | Value |
|--------|-------|
| Panel rows (cycle_specific) | 44,181,405 |
| Unique firms (firm FE levels) | 6,460,955 |
| Unique munis | 5,572 |
| Years | 16 (2002-2017) |
| Muni×year FE levels | ~89K |
| Obs per weighted model | ~39.5M |
| Models in baseline bundle | 48 (12 combos × 4 margins) |
| Current fixest threads | 4 |
| Current `lean` / `mem.clean` | TRUE / TRUE |

**Why it's slow**: Each `feols()` call independently absorbs ~6.5M firm FEs via iterative demeaning (MAP algorithm). With 48 models sharing the same FE structure and same sample (for a given margin), this demeaning is repeated 12 times per margin instead of once.

## Phase 1: Random Sample Creator

### Purpose

Create a 5% random sample of the firm panel that preserves panel structure (all years for sampled firms). This gives ~10-20x speedup for testing code changes, timing comparisons, and debugging.

### Implementation: `BNDES/politicsregs/diagnostics/create_firm_sample.R`

```r
#!/usr/bin/env Rscript
# Create a random 5% firm sample for development/testing of script 51.
# Samples firms (not rows) to preserve within-firm panel structure.
# Usage:
#   Rscript BNDES/politicsregs/diagnostics/create_firm_sample.R [--frac=0.05]

# ... bootstrap ...

library(data.table)
library(qs2)

args <- commandArgs(trailingOnly = TRUE)
frac_arg <- grep("^--frac=", args, value = TRUE)
SAMPLE_FRAC <- if (length(frac_arg)) as.numeric(sub("^--frac=", "", frac_arg[1])) else 0.05

cat(sprintf("Creating %.0f%% firm sample for testing...\n", 100 * SAMPLE_FRAC))

# For each baseline type, sample firms and save
for (bt in c("cycle_specific", "2002_fixed")) {
  bt_suffix <- if (bt == "cycle_specific") "" else paste0("_", bt)
  fst_path <- make_output_path(paste0("firm_panel_for_regs", bt_suffix, ".fst"))
  qs2_path <- make_output_path(paste0("firm_panel_for_regs", bt_suffix, ".qs2"))

  if (!file.exists(fst_path) && !file.exists(qs2_path)) {
    cat(sprintf("  Skipping [%s]: panel not found\n", bt))
    next
  }

  # Read only firm_id column to sample
  if (file.exists(fst_path) && requireNamespace("fst", quietly = TRUE)) {
    firm_ids <- fst::read_fst(fst_path, columns = "firm_id", as.data.table = TRUE)
  } else {
    full <- qs_read(qs2_path)
    firm_ids <- data.table(firm_id = full$firm_id)
    rm(full); gc()
  }

  unique_firms <- unique(firm_ids$firm_id)
  n_sample <- max(1L, as.integer(length(unique_firms) * SAMPLE_FRAC))
  set.seed(42L)  # Reproducible
  sampled_firms <- sort(sample(unique_firms, n_sample))
  rm(firm_ids, unique_firms); gc()

  cat(sprintf("  [%s] Sampled %d firms (%.1f%%)\n", bt, n_sample, 100 * SAMPLE_FRAC))

  # Now load full panel and filter
  if (file.exists(fst_path) && requireNamespace("fst", quietly = TRUE)) {
    dt <- fst::read_fst(fst_path, as.data.table = TRUE)
  } else {
    dt <- qs_read(qs2_path)
    setDT(dt)
  }

  dt[, firm_id := as.integer(firm_id)]
  dt <- dt[firm_id %in% sampled_firms]

  # Save sample
  sample_qs2 <- make_output_path(paste0("firm_panel_for_regs", bt_suffix, "_sample.qs2"))
  sample_fst <- make_output_path(paste0("firm_panel_for_regs", bt_suffix, "_sample.fst"))

  qs_save(dt, sample_qs2)
  cat(sprintf("  Saved: %s (%s rows, %.1f MB)\n",
              sample_qs2, format(nrow(dt), big.mark = ","),
              file.size(sample_qs2) / 1024^2))

  if (requireNamespace("fst", quietly = TRUE)) {
    fst::write_fst(dt, sample_fst, compress = 50)
    cat(sprintf("  Saved: %s (%.1f MB)\n",
                sample_fst, file.size(sample_fst) / 1024^2))
  }

  rm(dt); gc()
}

cat("\nDone. Use --sample flag in script 51 to load these.\n")
```

### Script 51 integration

Add a `--sample` CLI flag to script 51 that redirects `get_panel_paths()` to load `*_sample.*` files instead of the full panel:

```r
USE_SAMPLE <- "--sample" %in% args

get_panel_paths <- function(baseline_value) {
  suffix <- if (baseline_value == "cycle_specific") "" else paste0("_", baseline_value)
  sample_tag <- if (USE_SAMPLE) "_sample" else ""
  list(
    fst = make_output_path(paste0("firm_panel_for_regs", suffix, sample_tag, ".fst")),
    qs2 = make_output_path(paste0("firm_panel_for_regs", suffix, sample_tag, ".qs2"))
  )
}
```

**Usage**:
```bash
# Create sample (once)
Rscript BNDES/politicsregs/diagnostics/create_firm_sample.R

# Run script 51 on sample for fast iteration
Rscript BNDES/politicsregs/run_politicsregs.R 51 -- --sample
```

**Design notes**:
- Firm-level sampling (not row-level) preserves within-firm panel structure for changes outcomes and firm FE estimation
- Fixed seed (`42L`) ensures reproducibility across runs
- 5% default balances speed (~2M rows, should run in <5 min) with statistical validity (enough FE variation)
- Sample files are separate artifacts, never overwrite production panels

## Phase 2: Per-Table Timing Instrumentation

Add `proc.time()` instrumentation around each table's estimation loop. Minimal code changes.

### Implementation

Wrap the inner estimation loop (lines 506-577 of current script 51) with timing:

```r
# Before the combo loop for each spec_row:
table_t0 <- proc.time()

# ... existing combo loop ...

# After the combo loop, before table saving:
table_elapsed <- (proc.time() - table_t0)["elapsed"]
cat(sprintf("  [%s] %d models estimated in %.1f seconds (%.1f sec/model)\n",
            spec_row$table_id, length(table_mods),
            table_elapsed, table_elapsed / max(1L, length(table_mods))))
```

Also add timing to the full baseline block:

```r
# Before each baseline block:
block_t0 <- proc.time()

# After each baseline block:
block_elapsed <- (proc.time() - block_t0)["elapsed"]
cat(sprintf("\n  Baseline [%s] complete: %.1f seconds total\n", baseline_value, block_elapsed))
```

And a total script timer:

```r
# At script start (after library loading):
script_t0 <- proc.time()

# At script end:
script_elapsed <- (proc.time() - script_t0)["elapsed"]
cat(sprintf("\nTotal script runtime: %.1f seconds (%.1f minutes)\n",
            script_elapsed, script_elapsed / 60))
```

Store per-table timing in the summary output:

```r
# Add to make_model_row():
elapsed_sec = NA_real_  # filled after combo loop

# After combo loop:
model_summary_list[[...]]$elapsed_sec <- table_elapsed
```

**Why**: This identifies which tables/margins are slowest, guides further optimization, and provides before/after comparison data.

## Phase 3: Computational Optimizations

### 3A. fixest Multi-Estimation for Shared-Sample Models (HIGH IMPACT)

**The key insight**: For a given margin + weighting + sample combination, all 12 instrument combos share the exact same sample and FE structure. fixest's multi-estimation can exploit this by sharing the FE demeaning computation.

Instead of 12 separate `feols()` calls per margin:

```r
# CURRENT: 12 separate calls, each re-absorbs 6.5M firm FEs
for (combo_name in COMBO_ORDER) {
  mod <- feols(depvar ~ FA_mayor_coalition | firm_id + muni_id^year, ...)
  mod <- feols(depvar ~ FA_gov_coalition | firm_id + muni_id^year, ...)
  mod <- feols(depvar ~ FA_mayor_coalition + FA_gov_coalition | firm_id + muni_id^year, ...)
  # ... 12 total
}
```

Use `sw0()` (stepwise, starting from empty) to batch combos that add instruments incrementally:

```r
# PROPOSED: batch models with shared FE absorption where possible
# Group 1: single-tier (M, G, P) — can use multiple LHS too
feols(depvar ~ sw(FA_mayor_coalition, FA_gov_coalition, FA_pres_coalition)
      | firm_id + muni_id^year,
      data = dt, subset = mask, vcov = VCOV_FIRM, ...)

# Group 2: multi-tier combos — harder to batch, but pairs share structure
feols(depvar ~ FA_mayor_coalition + FA_gov_coalition + sw0(FA_pres_coalition)
      | firm_id + muni_id^year, ...)  # gives M+G and M+G+P
```

**However**, `sw()` produces incremental additions, not arbitrary combos. The 12 combos include non-nested sets (M+G, M+P, G+P) that can't all be expressed as a single `sw()` chain.

**Practical approach**: Group into batches that share the same RHS variables up to a `sw0()` extension:

| Batch | Models | fixest syntax |
|-------|--------|---------------|
| Singles | M, G, P | `sw(mayor, gov, pres)` |
| Mayor-based | M+G, M+P, M+G+P | `mayor + sw(gov, pres, gov + pres)` |
| Gov+Pres | G+P | Standalone or with `gov + pres` |
| Interactions | M+G+MxG, M+P+MxP, etc. | Standalone (different instruments) |

Even partial batching (singles as one call) saves 2 redundant FE absorptions per margin × 4 margins = 8 saved FE passes.

**Alternative: Multiple LHS for cross-margin batching**

For the same instrument combo, extensive and intensive margins differ only in sample and depvar. But if we restrict to levels-extensive and changes-extensive (same sample structure minus NAs), we could use:

```r
feols(c(has_bndes_fmt, delta_has_bndes_fmt) ~ FA_mayor_coalition
      | firm_id + muni_id^year, ...)
```

This shares FE computation across 2 depvars. But samples differ (changes requires non-NA deltas), so this only works if fixest handles `NA` depvars correctly within multi-LHS (it does — `fixest` drops NA rows per-depvar in multi-LHS).

**Expected impact**: ~2-4x speedup on FE absorption for same-sample models. This is the single biggest optimization available.

### 3B. Increase `fixest_nthreads` (MEDIUM IMPACT)

Currently set to 4. Modern machines benefit from more threads for FE absorption:

```r
# Detect available cores and use all physical cores
n_cores <- parallel::detectCores(logical = FALSE)
fixest::setFixest_nthreads(n_cores)
```

On a typical 8-core machine, this doubles throughput vs. 4 threads. On the user's machine, check `parallel::detectCores()`.

**Caution**: Beyond physical core count, hyperthreading adds marginal benefit for FE absorption (memory-bound). Test with `--sample` first.

### 3C. Pre-Convert FE Columns to Factor (LOW-MEDIUM IMPACT)

fixest internally converts FE variables to factors. Pre-converting avoids repeated conversion:

```r
# After loading panel, before estimation:
dt[, firm_id := as.factor(firm_id)]
dt[, muni_id := as.factor(muni_id)]
dt[, year := as.factor(year)]
```

**Note**: fixest handles interaction FEs (`muni_id^year`) by building the interaction internally. Pre-converting the components to factor may or may not help — test with `--sample`.

### 3D. Remove `lean = TRUE` for Multi-Estimation Reuse (LOW IMPACT)

When using multi-estimation (`sw()`, `c()`), fixest internally manages memory. `lean = TRUE` discards fitted values/residuals per model, which is fine. But `mem.clean = TRUE` triggers aggressive cleanup that may interfere with shared internal structures in multi-estimation.

**Recommendation**: Keep `lean = TRUE`, remove `mem.clean = TRUE` when using multi-estimation batches. Re-enable `mem.clean` for standalone model calls.

### 3E. Pre-Filter Panel to Estimation-Relevant Rows (LOW IMPACT)

Currently, 44M rows are loaded but only ~39.5M have positive employment (weighted sample). For unweighted specs, the full panel is needed. But for the common case (employment-weighted), pre-filtering saves ~10% of rows:

```r
# After loading, if all requested specs are employment-weighted:
if (all(TABLE_SPECS$weighting == "employment")) {
  dt <- dt[!is.na(n_employees) & n_employees > 0L]
}
```

This is a minor optimization since `subset=` already handles this, but it reduces memory pressure.

## Implementation Order

```
Phase 1 (sample creator)  ──→  Phase 2 (timing)  ──→  Phase 3A (multi-estimation)
                                                   ──→  Phase 3B (nthreads)
                                                   ──→  Phase 3C (factor FE)
```

1. **Phase 1**: Create sample script + add `--sample` flag to script 51
2. **Phase 2**: Add timing instrumentation (independent of Phase 1)
3. **Phase 3B**: Increase `nthreads` (quick win, test on sample first)
4. **Phase 3A**: Refactor combo loop to use `sw()` multi-estimation (biggest impact, most code change)
5. **Phase 3C-3E**: Minor optimizations, test incrementally on sample

## Acceptance Criteria

- [ ] `create_firm_sample.R` produces `*_sample.fst` and `*_sample.qs2` files
- [ ] `51_firm_first_stage.R --sample` runs end-to-end on sample data in under 5 minutes
- [ ] Per-table timing is printed to console and saved in `fc_battery_summary.qs2`
- [ ] Full-panel baseline bundle completes in under 30 minutes (target: 50% reduction)
- [ ] Regression coefficients on full panel are numerically identical to pre-optimization values (verify via `fc_battery_coefficients.qs2`)
- [ ] `--sample` flag is ignored by the orchestrator (no interference with production runs)

## Testing Protocol

1. Create sample: `Rscript diagnostics/create_firm_sample.R`
2. Baseline timing on sample: `Rscript run_politicsregs.R 51 -- --sample` → record per-table times
3. Apply each optimization incrementally, re-run on sample, compare:
   - Times (expect improvement)
   - Coefficients (expect identical to pre-optimization sample run)
4. Final validation on full panel: `Rscript run_politicsregs.R 51` → compare coefficients against existing `fc_battery_coefficients.qs2`

## Assumptions

- fixest >= 0.12 supports `sw()`, `csw()`, and multiple LHS in `feols()`
- The user's machine has >= 4 physical cores (check with `parallel::detectCores(logical = FALSE)`)
- fst package is available (already used in the pipeline)
- Panel structure is preserved by firm-level sampling (all years for sampled firms)

## Sources

- **Prior optimization plan**: `docs/plans/2026-03-18-optimize-firm-first-stage-runtime-with-fst-plan.md` — I/O optimizations (now implemented)
- **Structural CLI plan**: `docs/plans/2026-03-23-refactor-firm-first-stage-structural-cli-plan.md` — confirmed >60 min runtime bottleneck
- **Panel summary**: `output/firm_panel_summary.csv` — 44.2M rows, 6.5M firms
- **Existing tables**: `output/firm_reg_tables/fc_t1_levels_extensive.md` — 39.5M obs per model
