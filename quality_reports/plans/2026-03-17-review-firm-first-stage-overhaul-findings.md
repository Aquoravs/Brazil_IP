---
title: "Code Review Findings: Firm First Stage Overhaul"
type: review
status: active
date: 2026-03-17
parent_plan: docs/plans/2026-03-16-feat-firm-first-stage-overhaul-plan.md
---

# Code Review Findings: Firm First Stage Overhaul

Review of all scripts modified by the firm first-stage overhaul plan. Findings are ordered by severity.

---

## P1 CRITICAL — Must fix before running pipeline

### 1. Script 53: Wald test pattern `"^Z_"` does not match `dZ_*` coefficients

**Problem:** All reduced-form and robustness Wald tests in `53_sector_second_stage.R` silently fail. The pattern `"^Z_"` (starts with literal `Z_`) does not match the actual instrument coefficient names, which start with `dZ_` (e.g., `dZ_mayor_coalition_cycle_specific_Ag`).

The `tryCatch` around each `wald()` call swallows the error, so the script prints "Wald test failed" for every test instead of reporting the optimality F-statistic. This means **no Wald test results are produced** for the second stage.

**Affected lines in `BNDES/politicsregs/5_estimation/53_sector_second_stage.R`:**

| Line | Current code | Issue |
|------|-------------|-------|
| 335 | `save_wald_summary <- function(..., pattern = "^Z_")` | Default pattern misses `dZ_*` |
| 468 | `print_wald(mods_rf, pattern = "^Z_", ...)` | Reduced form Wald |
| 472 | `save_wald_summary(mods_rf, ...)` (uses default) | Reduced form Wald summary |
| 678 | `print_wald(mods_rob_a, "^Z_", ...)` | 2002-fixed robustness |
| 705 | `print_wald(mods_rob_b, "^Z_", ...)` | Trimmed sample robustness |
| 731 | `print_wald(mods_rob_c, "^Z_", ...)` | Alt clustering robustness |
| 791 | `print_wald(mods_placebo, "^Z_", ...)` | Transfer placebo |

**How the bug manifests:**
- `pick_z_sec()` (line 400) returns columns like `dZ_mayor_coalition_cycle_specific_Ag`
- These columns become the model coefficients
- `wald(mod, keep = "^Z_")` finds zero matching coefficients → error → caught by tryCatch → returns NULL/NA
- Console output shows "Wald test failed" for every specification

**Fix:** Change all `"^Z_"` patterns to `"^dZ_"` for reduced-form/changes specifications. The `save_wald_summary` default parameter on line 335 should also change to `"^dZ_"`. For the levels specification (Table 7 in script 52), the pattern `"^Z_"` is correct — but script 53 only uses changes instruments. A safe universal pattern would be `"^(dZ_|Z_)"`.

**Specific edits:**

```r
# Line 335: change default parameter
save_wald_summary <- function(mods, filename, header, pattern = "^(dZ_|Z_)") {

# Line 468:
print_wald(mods_rf, pattern = "^dZ_", header = "Optimality test")

# Lines 678, 705, 731, 791: change "^Z_" to "^dZ_" in each call
print_wald(mods_rob_a, "^dZ_", "Optimality test (2002-fixed)")
print_wald(mods_rob_b, "^dZ_", "Optimality test (trimmed)")
print_wald(mods_rob_c, "^dZ_", "Optimality test (alt clustering)")
print_wald(mods_placebo, "^dZ_", "Exclusion restriction test")
```

**Verification:** After the fix, re-run `Rscript run_politicsregs.R 53` and confirm that Wald F-statistics are printed (numeric values, not "Wald test failed").

---

## P2 IMPORTANT — Should fix before production runs

### 2. Script 51: `dt` held in memory through FC-5 to FC-8, wasting ~3.2 GB

**Problem:** `51_firm_first_stage.R` line 282 loads the full cycle_specific panel into `dt` (~22M rows, ~3.2 GB). This object is used for:
- Column discovery (lines 290-297): extracting `fa_cols`, `dfa_cols`, `has_multi_muni`
- Creating `dt_cs` for FC-1 to FC-4 (line 324)

After FC-4 completes, `dt_cs` is freed (line 386) but `dt` persists until line 548. Meanwhile, FC-5 through FC-8 each call `load_panel_subset()` which reads from disk into a new object. During those sections, both `dt` (3.2 GB, unused) and the new panel copy (~3.2 GB) coexist in memory, leaving only ~9.5 GB for fixest working memory on a 16 GB machine.

**Fix:** After the column discovery block and before FC-1, extract the needed metadata and free `dt`:

```r
# After line 312 (regression_keep_cols definition), add:
rm(dt); gc(verbose = FALSE)

# Then for FC-1 to FC-4, load via load_panel_subset instead of subsetting dt:
# Replace lines 324-330 with:
dt_cs <- load_panel_subset("cycle_specific", keep_cols = regression_keep_cols)
if (!UNWEIGHTED) {
  n_before <- nrow(dt_cs)
  dt_cs <- dt_cs[!is.na(n_employees) & n_employees > 0]
  cat(sprintf("  Dropped %s obs with n_employees <= 0 or NA\n",
              format(n_before - nrow(dt_cs), big.mark = ",")))
}
```

Also remove the now-unnecessary line 548 (`rm(dt); gc(verbose = FALSE)`).

**Additionally:** Line 324 `dt_cs <- dt[baseline_type == "cycle_specific"]` creates a full copy even though the file only contains cycle_specific data (script 42 saves baselines separately). After switching to `load_panel_subset`, this filter is unnecessary since the loaded file is already baseline-specific.

### 3. Script 51: `_only` variants dropped from the active analysis battery

**Resolved:** `_only` interaction variants are not part of the active analysis battery. This review note previously described a larger battery that still counted `_only` overlap specifications; that description is obsolete and should not be treated as the current analysis interface.

### 4. `beamer_tables.R`: Historical note on interaction labels

**Historical note:** this review section originally listed a larger interaction label set that included `_only` variants. The active analysis only needs labels for the interaction terms still reported in the battery: `FA_mayor_gov_*`, `FA_mayor_pres_*`, `FA_triple_*`, and their `dFA_*` counterparts.

---

## P3 NICE TO HAVE — Low priority improvements

### 5. Script 34: Levels and changes instruments in separate files

The plan (Phase 1B) suggests "a single sector-level instrument file containing both `Z_*` (levels) and `dZ_*` (changes) columns." Currently script 34 saves:
- `shift_share_instruments_sector_grouped.qs2` — changes (`dZ_*`)
- `shift_share_instruments_levels_sector_grouped.qs2` — levels (`Z_*`)

Script 41 then loads both. Merging them into a single file would simplify I/O. Low priority since the current approach works correctly.

### 6. Script 36, line 409: Integer fill for potentially double columns

`merged[is.na(get(dc)), (dc) := 0L]` fills with integer `0L`. If `dalign_*` columns are stored as doubles after qs2 deserialization, this could cause a type mismatch warning. In practice, alignment changes are integers, so this is benign. Using `0` (double) instead of `0L` would be strictly safer.

### 7. Script 52, line 79: Single-threaded fixest

`fixest::setFixest_nthreads(1)` is conservative. The sector panel (~1.37M rows) is small enough that 4 threads would help without memory risk. Matching the approach in script 51 (`setFixest_nthreads(4)`) would speed up estimation.

### 8. Script 41: `s_*` wide columns dropped from Panel B

Level share columns `s_*` are dropped from Panel B (lines 820-821). These could be useful for a future levels-specification second stage (analogous to script 52's Table 7). Currently script 53 only uses `delta_s_*`, so no immediate impact.

---

## Verified Correct (no issues found)

These aspects were reviewed and found to be correctly implemented:

1. **Script 33 baseline averaging:** Window clipping to available years, 2002-fixed variant, sector-level column deduplication — all correct.

2. **Script 34 non-spreading of dZ:** Changes instruments (`dZ_*`) stay at inauguration years; only levels (`Z_*`) and exposure controls are spread via `term_map`. The `spread_instruments()` function correctly handles this split.

3. **Script 36 interaction instrument construction:** The `is_interaction_col()` helper correctly identifies MxG/MxP/triple columns. Interaction instruments use `share_fp_0 * dalign_*` for both tiers (not filtered by `is_mayor`/`is_gp`), which is correct because combined alignment changes at both inaugurations. The `combined_term_map` (~2-year stints) correctly limits each inauguration's FA effect.

4. **Script 36 baseline windows for interactions:** The single-tier `baseline_window_map` implicitly creates correct combined baselines because each tier's treatment_year maps to different baseline windows (e.g., mayor 2005 → baseline 2002-2003, gov_pres 2007 → baseline 2002-2005). After tier collapse (Step 7), the sum correctly combines contributions.

5. **Script 42 multi-muni flag:** Per-year definition (`uniqueN(muni_id) > 1` by `firm_id, year`), employment/BNDES share diagnostics, additional NA-delta reporting in single-muni subsample — all correctly implemented.

6. **Script 42 per-baseline file saving:** Memory-safe design that processes one baseline at a time, saving immediately and freeing. The `count_nonzero_rows()` helper is efficient (loops over columns, avoids matrix conversion for row-wise OR).

7. **Script 52 Wald pattern:** Uses `"^(dZ_|Z_)"` (line 191, 224), which correctly matches both changes and levels instrument coefficients.

8. **Script 41 Panel B column management:** `delta_hhi` computed and retained; `bndes_pc` retained for robustness; `log_transfers_pc` retained for placebo; `delta_s_*` columns NOT zero-filled (NAs preserved for undefined deltas). All consistent with CLAUDE.md design decisions.

9. **Z_/dZ_ rename:** Scripts 34, 41, 52, 53, and beamer_tables.R consistently use `Z_*` for levels and `dZ_*` for changes. No residual `Zlev_*` references found.
