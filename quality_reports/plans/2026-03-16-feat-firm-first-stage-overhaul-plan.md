---
title: "Firm First Stage Overhaul: Averaged Baselines, Interactions, Multi-Muni Robustness"
type: feat
status: active
date: 2026-03-16
deepened: 2026-03-16
origin: docs/brainstorms/2026-03-14-firm-sector-first-stage-disconnect-brainstorm.md
---

# Firm First Stage Overhaul

## Enhancement Summary

**Deepened on:** 2026-03-16
**Research agents used:** spec-flow-analyzer, best-practices-researcher (fixest/data.table), repo-research-analyst, performance-oracle, learnings-researcher (regression tables)

### Key Improvements
1. **Performance**: Without optimizations, 144 models would take ~8 hours. With `setFixest_nthreads(4)` + sample batching → **~25-40 minutes**.
2. **Missing script**: Script 33 (sector baselines) also uses single-year cycle_map — needs same averaging change for sector-level consistency.
3. **Spec flow gaps**: 20 gaps identified — most critical: complete combined baseline window map needed; interaction instruments were only partially integrated into the battery; `G+P` combo missing; migration strategy for rename needed.
4. **Table presentation**: 12 columns need `font_size=7` and frame splitting; 144-spec summary saved as `.qs2` with optional coefficient plot.
5. **Collinearity**: Use `mod$collin.var` for detection; in municipalities where mayor's party == governor's party, MxG == M == G (perfect collinearity — fixest drops silently).

### Decisions Resolved
1. **2003 gov/pres cycle**: **Drop entirely** — no baseline window available (data starts 2002)
2. **Changes specs sample**: **Full panel** — non-inauguration years contribute to FE estimation; dFA=0 is valid
3. **Interaction variants and triple**: include the active overlap specifications in the battery; `_only` variants are no longer part of the target analysis
4. **Multi-muni filter**: **Per-year** — `is_multi_muni = 1` only in years where the firm has 2+ municipalities

---

## Overview

Overhaul the firm-level first-stage instrument construction and estimation to: (1) redefine baselines as term-averaged affiliation shares, (2) stop spreading changes instruments across electoral terms, (3) add interaction instruments (MxG, MxP, triple), (4) add multi-municipality firm robustness, and (5) run a battery of 144 regression specifications (48 main + 96 robustness). Propagate changes to documentation (`CLAUDE.md`, `regs.tex`, `shift_share.md`).

## Problem Statement / Motivation

The current firm-level first stage uses a **single pre-election year** as the baseline for party-exposure weights. This creates two problems:
1. Firms entering the data late or having gaps miss the baseline year entirely, causing unnecessary sample attrition.
2. A single year of affiliation data is noisy — averaging across the previous term (up to 4 years) smooths measurement error and increases instrument precision.

Additionally:
- **Changes instruments are spread** across 4-year terms even though alignment turnover is a discrete event at inauguration. Spreading conflates the timing of the shock.
- **Interaction effects** (MxG, MxP, triple alignment) are constructed in script 32 but never used in the firm pipeline, leaving important variation on the table.
- **Multi-municipality firms** (2.2% of firm-years, 29.6% of employment) may behave differently because the same owner affiliation interacts with alignment shocks in multiple municipalities.

## Proposed Solution

### Phase 1: Instrument Construction Changes (scripts 36, 34, 33)

#### 1A. Averaged baselines in scripts 36 and 33

Replace the single-year `cycle_map` with a `baseline_window_map` specifying a 4-year window of candidate baseline years. For each firm, average `share_fp_0 = L_fp / L_f` across all **available** years within the window.

**New baseline windows (firm-level, single-tier instruments):**

| Treatment term | Tier | Election year | Baseline window (4 yrs before election) | Notes |
|---|---|---|---|---|
| 2005-2008 | mayor | 2004 | 2000-2003 | Data starts 2002, so use 2002-2003 |
| 2009-2012 | mayor | 2008 | 2004-2007 | Full 4-year window |
| 2013-2016 | mayor | 2012 | 2008-2011 | Full 4-year window |
| 2017-2020 | mayor | 2016 | 2012-2015 | Full 4-year window |
| 2003-2006 | gov/pres | 2002 | 1998-2001 | **Dropped**: no pre-election data available (data starts 2002) |
| 2007-2010 | gov/pres | 2006 | 2002-2005 | Full 4-year window |
| 2011-2014 | gov/pres | 2010 | 2006-2009 | Full 4-year window |
| 2015-2018 | gov/pres | 2014 | 2010-2013 | Full 4-year window |

**For combined shocks (MxG, MxP, triple):**

The baseline window is the previous term **before the last election that created the combined state**. Within a combined-alignment term, the "last election" shifts when a new tier inaugurates:

- **MxG, years 2005-2006** (mayor just inaugurated): baseline = 2000-2003 → use available from 2002-2003
- **MxG, years 2007-2008** (governor just inaugurated): baseline = 2002-2005
- **MxP, years 2005-2006**: baseline = 2000-2003 → 2002-2003
- **MxP, years 2007-2008**: baseline = 2002-2005 (pres inaugurated 2007)
- **Triple, years 2005-2006**: baseline = 2000-2003 → 2002-2003
- **Triple, years 2007-2008**: baseline = 2002-2005

Implementation: build a `combined_baseline_window_map` keyed by `(treatment_year, tier_combination, year_within_term)` mapping to baseline window `[bl_start, bl_end]`. For each firm, compute `share_fp_0` as the mean of `L_fp/L_f` across available years in the window. If only one year is available, use that year.

### Research Insights: Averaged Baselines

**Sector-level consistency (script 33):**
Script 33 (`33_select_baseline_weights.R`) uses an **identical** single-year `cycle_map` (lines 66-78). For consistency, it must also adopt the averaged-baseline approach. Otherwise the firm-level and sector-level instruments use different baseline definitions, breaking the aggregation identity documented in `regs.tex`.

**data.table implementation pattern:**
The most efficient approach for variable-length window averaging is an explicit merge + group-by:
```r
# Expand windows to individual years
windows_long <- baseline_window_map[, .(year = seq(bl_start, bl_end)), by = .(treatment_year, tier)]
# Merge with firm-party shares and average
firm_baseline <- merge(firm_shares, windows_long, by = "year", allow.cartesian = TRUE)
firm_baseline <- firm_baseline[,
  .(share_fp_0 = mean(share_fp, na.rm = TRUE), n_years = .N),
  by = .(firm_id, party, treatment_year, tier)
]
```
For production with 22M+ rows, a non-equi join avoids materializing the full Cartesian product but is less readable.

**Edge case — firms with zero baseline-window years:**
`mean(numeric(0))` returns `NaN` in R. Firms with no affiliation data in any baseline-window year should get `share_fp_0 = 0` (same as current behavior for firms without owner data — they contribute zero to instruments via Step 9 of script 36).

**Edge case — heteroskedasticity from unequal window sizes:**
The mayor 2005-2008 cycle uses only 2 baseline years (2002-2003) vs. 4 years for later cycles. The variance of `share_fp_0` will be systematically higher for this cycle. This does not bias the instrument but may reduce precision. No correction needed, but worth noting in the paper.

**Complete combined baseline window map (to be built before implementation):**
The plan provides examples for 2005-2008 only. A complete table for all years 2002-2017 covering MxG, MxP, and triple is needed. The rule is: for year `t` in a combined-tier treatment period, the baseline window is `[e-4, e-1]` where `e` is the most recent election year of any tier in the combination, with `e <= t`.

#### 1B. Rename sector instruments: `Zlev_*` → `Z_*`, `Z_*` → `dZ_*`

For consistency with the firm-level naming convention (`FA_*` for levels, `dFA_*` for changes), rename sector-level instruments:
- Current `Zlev_mayor_coalition` → `Z_mayor_coalition` (levels instrument)
- Current `Z_mayor_coalition` → `dZ_mayor_coalition` (changes instrument)

This is a naming-only change but touches multiple scripts:
- **Script 34**: rename output columns (both muni-level and sector-level outputs)
- **Script 41**: update column references when building Panel A and Panel B
- **Script 52**: update regression formulas and coefficient maps
- **Script 53**: update instrument column references
- **`_utils/beamer_tables.R`**: update `COEF_MAP_INSTRUMENTS` and `FE_LABELS`
- **Documentation**: `CLAUDE.md`, `shift_share.md`, `regs.tex`

Output file names also change:
- `shift_share_instruments_levels_sector.qs2` → drop (levels instruments become the primary `shift_share_instruments_sector.qs2`)
- Current `shift_share_instruments_sector.qs2` (changes) → `shift_share_instruments_changes_sector.qs2` (or keep both in one file with `Z_*` and `dZ_*` columns)

**Preferred approach**: produce a single sector-level instrument file containing both `Z_*` (levels) and `dZ_*` (changes) columns, eliminating the need for separate files.

### Research Insights: Z/dZ Rename

**Exact line references from repo analysis (for atomic rename):**

| Script | Lines | Current pattern | New pattern |
|--------|-------|----------------|-------------|
| 34 | 225, 237-238 | `Z_` output, `Zlev_` output | `dZ_`, `Z_` |
| 41 | 442, 473, 545, 602, 617, 642 | `grep("^Z_"...)`, `grep("^Zlev_"...)` | `grep("^dZ_"...)`, `grep("^Z_"...)` |
| 52 | 151-152, 187, 191, 224-225, 236-244 | `z_col()` prefix `"Z_"`, `zlev_col()` prefix `"Zlev_"` | `dz_col()` prefix `"dZ_"`, `z_col()` prefix `"Z_"` |
| 53 | 185-190, 258-280, 303-304, 386-411 | All `"^Z_"` patterns (changes only) | All `"^dZ_"` |
| beamer_tables.R | 14-37, 328 | `Z_` entries in COEF_MAP, `Zlev_` entries, F-stat keep `"^(Z_\|Zlev_)"` | `dZ_` entries, `Z_` entries, `"^(dZ_\|Z_)"` |

**Migration risk:**
If scripts 34 and 41/52/53 are not updated atomically, an intermediate state where 34 produces `Z_*` (levels) but 41 reads `Z_*` expecting changes instruments will silently produce wrong regressions. **Must update all scripts in a single commit and re-run the full pipeline `34:53`.**

**LaTeX label update in beamer_tables.R:**
- Current `$Z^{\text{mayor}}_{\text{coal.}}$` (for changes) → `$\Delta Z^{\text{mayor}}_{\text{coal.}}$`
- Current `$Z^{\text{mayor,lev}}_{\text{coal.}}$` (for levels) → `$Z^{\text{mayor}}_{\text{coal.}}$`

#### 1C. Stop spreading changes instruments

In both scripts 34 and 36, the "spreading" step (Step 4b in 34, Step 8 in 36) currently applies to both levels and changes instruments. **Remove spreading for changes instruments** (`dFA_*`, `dZ_*`). Only levels instruments (`FA_*`, `Z_*`) should be spread across the 4-year term.

This means:
- `dFA_*` instruments are non-zero only at inauguration years: 2005, 2009, 2013, 2017 (mayor) and 2003, 2007, 2011, 2015 (gov/pres)
- `dZ_*` instruments similarly non-zero only at inauguration years
- Changes specifications will identify off fewer effective observations, but this is **conceptually correct**: turnover is a discrete event
- The changes first stage will acknowledge in notes that identification comes from inauguration-year variation only

**Script 34 changes:**
- Rename instrument columns: `Zlev_*` → `Z_*`, `Z_*` → `dZ_*` (per Phase 1B)
- Split `spread_instruments()` into two calls: one for `dz_cols` (changes) without spreading, one for `z_cols` (levels) with spreading
- For changes instruments: rename `year` from `inaug_year` to `year` directly, no cartesian join with `term_map`
- For controls: continue spreading (they are predetermined baselines, constant within term)

**Script 36 changes:**
- In Step 8, only spread `fa_cols` (levels instruments)
- Keep `dfa_cols` at their original inauguration-year values
- After tier collapse (Step 7), `dFA` instruments will remain at treatment years only

### Research Insights: Non-Spreading

**Effective sample implications:**
With `firm_id + muni_id^year` FE, the changes spec identifies off cross-firm variation within municipality-year. In non-inauguration years, `dFA = 0` for all firms, so FE absorbs everything. The regression runs on the full panel (non-inauguration years contribute to FE estimation), but F-statistics reflect only inauguration-year variation. This is ~7 inauguration years out of 16 total years — roughly 44% of identifying variation.

**Resolved: full panel.**
Running on the full panel is standard in shift-share designs. The muni×year FE ensures identification comes from cross-firm variation within inauguration-year cells. Non-inauguration years contribute only to FE estimation, which is appropriate.

**Lagged response concern:**
If lending responds with a lag (alignment shock in 2009 affects lending in 2010-2012), the non-spread changes design misses this. Consider documenting that the levels specification captures cumulative effects while changes captures impact effects.

#### 1D. Add interaction instruments to script 36

Currently script 36 uses only 6 `dalign` columns and 6 `align` columns (mayor/gov/pres × party/coalition). Script 32 already produces 10 additional overlap columns:
- `align_mayor_gov_*`, `align_mayor_gov_only_*`
- `align_mayor_pres_*`, `align_mayor_pres_only_*`
- `align_triple_*`
And their `dalign_*` counterparts.

**Changes to script 36:**
- Expand `dalign_cols` and `level_cols` to include the overlap columns
- Compute weighted products `share_fp_0 * dalign_mayor_gov_*`, etc.
- For interaction instruments, use the **combined baseline window** (Phase 1A); interaction instruments also follow the `Z`/`dZ` naming at the sector level
- The combined instruments need special tier logic: `mayor_gov` interactions require alignment data from both mayor and gov_pres tiers

**New instrument columns produced:**
- `FA_mayor_gov_coalition`, `FA_mayor_gov_party`
- `FA_mayor_gov_only_coalition`, `FA_mayor_gov_only_party`
- `FA_mayor_pres_coalition`, `FA_mayor_pres_party`
- `FA_mayor_pres_only_coalition`, `FA_mayor_pres_only_party`
- `FA_triple_coalition`, `FA_triple_party`
- Same set for `dFA_*`

### Research Insights: Interaction Instruments

**Instrument construction verification:**
Script 32 (lines 184-188) computes `dalign_mayor_gov_*` as `d(M*G) = M_t*G_t - M_{t-1}*G_{t-1}` — the change in the product, NOT the product of changes. This is correct and consistent with `dFA_mayor_gov = share_fp_0 * d(M*G)`.

**Interaction variants and triple:**
These instruments are constructed in the alignment pipeline, but the active analysis battery keeps the MxG, MxP, and triple interactions rather than `_only` overlap variants. If the triple interaction is too rare to identify (check prevalence in script 32 diagnostics), those specs will produce NA in the summary — the battery is designed to handle this gracefully via `tryCatch()`.

**Missing instrument combo `G+P`:**
The 11 combos include M+G and M+P but not G+P. If the rationale is that mayor alignment is always included in multi-tier specs, this should be stated. Otherwise add G+P for completeness.

**Collinearity detection:**
fixest silently drops collinear variables and reports them in `mod$collin.var`. Add a diagnostic after each `feols()` call:
```r
if (length(mod$collin.var) > 0) {
  cat(sprintf("  WARNING: %d variable(s) dropped for collinearity: %s\n",
              length(mod$collin.var), paste(mod$collin.var, collapse = ", ")))
}
```
In municipalities where mayor's party == governor's party (common), `MxG == M == G` perfectly — fixest drops 2 of 3.

### Phase 2: Panel and Estimation Changes (scripts 42, 51)

#### 2A. Multi-muni flag in script 42

Add a column `is_multi_muni` to the firm panel:
```r
# Count municipalities per firm per year
muni_counts <- panel[, .(n_munis = uniqueN(muni_id)), by = .(firm_id, year)]
panel[muni_counts, is_multi_muni := as.integer(i.n_munis > 1L), on = .(firm_id, year)]
```

Report summary statistics:
- Share of firm-years that are multi-muni
- Share of employment in multi-muni firms
- Share of BNDES credit going to multi-muni firms

### Research Insights: Multi-Muni

**Resolved: per-year definition.**
`is_multi_muni = 1` only in years where the firm actually has 2+ municipalities. A firm multi-muni in 2010 but single-muni in 2011 creates a gap: `delta_has_bndes_fmt` becomes `NA` in 2011 for the "single_muni" subsample (no prior-year observation after filtering). **Add a diagnostic showing additional NA deltas in the single-muni subsample vs. all-firms.**

**Existing multi-muni diagnostics:**
`diagnostics/explore_affiliation.R` (Section 5, lines 625-713) already computes within-year and lifetime multi-municipality distributions, mechanism relevance (% of firm-years and employment). No new diagnostic script needed — just use existing numbers.

**Script 42 structural compatibility:**
Script 42 auto-discovers `FA_*`/`dFA_*` columns via `grep` (lines 216-217). The new interaction columns will be auto-discovered. The `count_nonzero_rows` diagnostic will check more columns but requires no code changes. Only `is_multi_muni` flag addition is needed.

#### 2B. Full regression battery in script 51

Restructure script 51 to loop over a specification grid:

```r
spec_grid <- CJ(
  align_type = c("coalition", "party"),
  instrument_combo = c("M", "G", "P", "M+G", "M+P", "M+G+P",
                        "M+G+MxG", "M+P+MxP",
                        "M+G+P+MxG", "M+G+P+MxP",
                        "M+G+P+MxG+MxP",
                        "M+G+P+MxG+MxP+Triple"),
  spec_type = c("levels", "changes"),
  sample = c("all", "single_muni"),
  weighting = c("employment", "unweighted")
)
```

For each row in the grid, run both extensive and intensive margin regressions. Store all results in a single summary data.table.

**Key implementation choices:**
- Run coalition first (main), party second (robustness)
- For the "single_muni" sample, filter to `is_multi_muni == 0`
- For changes specifications, acknowledge that `dFA` is non-zero only at inauguration years
- Use `save_beamer_table()` for the main tables; store the full battery in a summary `.qs2` file

**Table numbering (proposed):**
- FC-1 through FC-4: Main tables (coalition, cycle-specific, employment-weighted, all firms) — levels ext/int, changes ext/int. 12 combos × 4 = 48 specs
- FC-5: Party alignment variant (levels ext + changes ext) — 12 combos × 2 = 24 specs
- FC-6: 2002-fixed baseline (levels ext + changes ext) — 12 combos × 2 = 24 specs
- FC-7: Unweighted robustness (levels ext + changes ext) — 12 combos × 2 = 24 specs
- FC-8: Single-muni firms only (levels ext + changes ext) — 12 combos × 2 = 24 specs
- FC-9: Full battery summary table (coefficient + F-stat for all 144 specs)

### Research Insights: Estimation Performance (CRITICAL)

**Runtime without optimizations: 7-10 hours (infeasible).**
Each `feols()` on 11M rows with firm + muni×year FE + two-way clustering takes 3-4 minutes single-threaded. 144 models × 3.5 min = ~8.4 hours for full-panel samples alone. Intensive-margin samples (200K-500K rows) are fast (~5-10 seconds each).

**Optimization 1 (highest impact): Enable multi-threaded fixest.**
```r
setDTthreads(1)                    # data.table stays single-threaded for safety
fixest::setFixest_nthreads(4)      # estimation uses 4 threads for demeaning
```
Cuts per-model time by ~40-50% on large samples. Safe because `lean=TRUE` means fixest does not modify the input data.table.

**Optimization 2 (highest impact): Batch by sample, not by table.**
Load data once per baseline, subset once per sample filter, run all instrument combos for that combination:
```r
for (bt in c("cycle_specific", "2002_fixed")) {
  dt_base <- load_panel_subset(bt)
  for (sample_type in c("all", "single_muni")) {
    dt_sample <- if (sample_type == "single_muni") dt_base[is_multi_muni == 0L] else dt_base
    for (margin in c("extensive", "intensive")) {
      # subset once, run all combos, save, free
    }
  }
  rm(dt_base); gc()
}
```

**Optimization 3: Use `sw()` for shared FE demeaning where possible.**
fixest's `sw()` shares the FE projection of Y across specifications. This avoids recomputing the O(N × K_FE × iterations) demeaning for each instrument combo. However, `sw()` cannot express arbitrary subsets like M+G vs M+P — the current `run_firm_combos()` pattern is still needed for the 11-combo grid. `sw()` works best for the single-tier sweep (M, G, P).

**Optimization 4: Extract-and-discard models immediately.**
Don't store 144 model objects. Extract coefficients, F-stats, and R² immediately, then `rm(mod)`:
```r
safe_wald <- function(mod, pattern) {
  inst_names <- grep(pattern, names(coef(mod)), value = TRUE)
  if (length(inst_names) == 0) return(NA_real_)
  wald(mod, keep = pattern)$stat
}
```

**Projected runtime with all optimizations: ~25-40 minutes on 16 GB RAM.**

| Optimization | Time reduction |
|---|---|
| `setFixest_nthreads(4)` | -40-50% |
| Sample batching (no redundant I/O) | -15% |
| Aggressive gc() between blocks | memory safety |
| **Combined** | **~70-75% reduction** |

**Memory budget (16 GB):**
- Panel data (one baseline, one subset): ~1.7 GB
- fixest working memory during estimation: ~1-1.5 GB
- R session + GC headroom: ~2.5 GB
- **Total: ~5.5-6 GB** — safe on 16 GB if only one full-panel copy is in memory at a time
- **NEVER** hold `dt_lev_ext`, `dt_lev_int`, `dt_chg_ext`, `dt_chg_int` simultaneously (current code does this — fix during restructure)

### Research Insights: Table Presentation

**11 columns per table:**
The Beamer table standard specifies `font_size=8` for 6 columns. With 11 columns, use `font_size=7` and **split across two frames** (6+5 columns). The standard explicitly warns about table overflow and recommends frame splitting.

**144-spec battery summary:**
`save_wald_summary()` exists but was designed for a handful of rows. For 144 specifications, consider:
- A compact summary data.table saved as `.qs2` with one row per spec (coefficient, SE, F-stat, N)
- A coefficient plot (ggplot2 dot-and-whisker) for visual presentation
- A heatmap of F-statistics across the spec grid dimensions

**Failure handling:**
If a model fails to converge or produces NA coefficients (e.g., collinearity drops all instruments), log a warning, store NA in the summary table, continue. Add `tryCatch()` around each `feols()` call.

### Phase 3: Documentation Updates

#### 3A. `paper/regs.tex`

1. **Update baseline definition paragraph** (currently lines 82-96):
   - Replace single-year $\tau(t)$ with average over baseline window
   - New definition: $\omega_{fp,\tau} = \frac{1}{|T_\tau|} \sum_{s \in T_\tau} \frac{L_{f,p,s}}{L_{f,s}}$ where $T_\tau$ is the set of available years in the previous term
   - Add footnote explaining the window for each treatment term

2. **Add interaction instrument definitions** (new paragraph after firm-level instrument):
   - Define $\FA^{\ell_1 \times \ell_2}_{fmt}$ as the exposure-weighted product of alignment across two tiers
   - Explain that "only" variants (e.g., MxG only) exclude triple alignment

3. **Update changes specification** (lines 147-176):
   - Note that $\Delta\FA$ is defined only at inauguration years (not spread)
   - Add footnote: "Changes instruments are non-zero only at political transitions"
   - Update notation: $\Delta Z$ instead of $Z$ for changes instruments

4. **Add multi-muni robustness paragraph** (after two pipelines section):
   - Describe the filter and its motivation

#### 3B. `CLAUDE.md`

1. **Variable naming**: Add interaction instrument names (`FA_mayor_gov_*`, etc.), `dZ_*` naming, `is_multi_muni` flag
2. **Key design decisions**: Update baseline definition, note changes instruments are NOT spread
3. **Coding conventions**: Note `Z_*` = levels, `dZ_*` = changes (consistent with FA/dFA)
4. **Script 33**: Add to list of scripts needing averaged baselines

#### 3C. `docs/shift_share.md`

1. **Section 4**: Update firm-level instrument formula with averaged baseline
2. **Section 3**: Note that changes instruments are not spread across terms
3. **Section 5**: Update notation: `Z_*` (levels), `dZ_*` (changes)
4. Add new section on interaction instruments

## Technical Considerations

### Econometric concerns

1. **Collinearity in interaction specifications**: Including M, G, and MxG together may cause multicollinearity in municipalities where alignment is perfectly correlated. Monitor `mod$collin.var` after each regression. fixest silently drops collinear variables — report which were dropped.

2. **Effective sample size for changes specs**: Without spreading, changes instruments are non-zero only at inauguration years (~7 years out of 16 in 2002-2017). This is still adequate for identification with municipality×year FE since variation is cross-sectional (across firms within muni-year), but F-statistics may be lower. Run on full panel — non-inauguration years contribute to FE estimation.

3. **Averaged baselines and predetermination**: Averaging over the previous term (e-4 to e-1, where e is election year) preserves predetermination since all baseline years precede the treatment. However, years closer to the election may reflect anticipation effects. The 2002-fixed baseline remains the cleanest robustness check. Note: shorter windows (2 years) at data boundaries introduce heteroskedasticity but no bias.

4. **Multi-muni firms**: Excluding them changes the estimand from the average firm to the average single-establishment firm. If coefficients differ, this reveals heterogeneity, not bias. Both estimates are valid for different populations. Per-year filter creates additional NA deltas in changes specs — diagnose and report.

5. **Interaction instrument interpretation**: `dFA_mayor_gov = share_fp_0 * d(M*G)` is the change in the product of alignment levels, NOT the product of changes. This captures transitions into/out of joint alignment, which has a natural political economy interpretation.

### Memory and performance

- **Without optimizations**: 144 models on 11M-row full-panel samples would take ~8 hours (infeasible)
- **With optimizations** (`setFixest_nthreads(4)` + sample batching + immediate model disposal): **~25-40 minutes**
- Never hold multiple full-panel copies simultaneously (each copy ~1.7 GB)
- `lean=TRUE` is non-negotiable — without it, 144 models would require ~19 GB
- Current `run_firm_combos()` pattern is correct for arbitrary instrument combos — `sw()`/`csw()` cannot express the 11-combo grid

## Acceptance Criteria

### Functional Requirements

- [x] Script 33 computes averaged baselines for sector-level weights (same windows as 36)
- [x] Script 36 computes averaged baselines over the previous-term window
- [x] Script 36 produces interaction instruments (FA/dFA for MxG, MxP, triple, and "only" variants)
- [x] Script 36 does NOT spread dFA instruments; only FA instruments are spread
- [x] Script 34 renames `Zlev_*` → `Z_*` and `Z_*` → `dZ_*` throughout
- [x] Script 34 does NOT spread dZ (changes) instruments; only Z (levels) are spread
- [x] Scripts 41, 52, 53 updated to use new `Z_*`/`dZ_*` naming
- [x] Script 42 adds `is_multi_muni` flag with correct definition
- [x] Script 51 runs 144 specifications: 48 main (12 combos × 4 margins) + 96 robustness (4 tables × 12 combos × 2 margins)
- [x] Script 51 uses `setFixest_nthreads(4)` and batches by sample for performance
- [x] Script 51 saves a comprehensive summary table with all coefficients and F-stats
- [x] Script 51 reports collinearity via `mod$collin.var` for interaction specs
- [x] `regs.tex` reflects the updated baseline definition, interaction instruments, and non-spreading of changes
- [x] `CLAUDE.md` updated with new variable names, design decisions, and conventions
- [x] `shift_share.md` updated for consistency

### Validation Requirements

- [ ] Averaged baselines: verify that firms with affiliation in only 1 of 4 baseline years still get instruments (not dropped)
- [ ] Averaged baselines: firms with zero baseline-window years get `share_fp_0 = 0` (not NaN)
- [ ] Averaged baselines: diagnostic prints number of firms with 1, 2, 3, 4 baseline years per cycle
- [ ] Support bounds: FA in [0,1], dFA in [-1,1], interaction instruments in [0,1] for levels and [-1,1] for changes
- [ ] Non-spreading check: dFA columns are all zero in non-inauguration years
- [ ] Multi-muni flag: verify ~2.2% prevalence of multi-muni firm-years and ~29.6% employment share
- [ ] Multi-muni: report additional NA deltas in single-muni subsample vs. all-firms
- [ ] Instrument variation: interaction instruments have non-trivial within-muni-year variance
- [ ] Collinearity report: fraction of models where interaction instruments were dropped
- [ ] No regression crashes: all 144 models converge or fail gracefully with NA in summary
- [ ] Code consistency: script 34 and 36 use parallel logic for spreading/non-spreading
- [ ] Rename atomicity: all scripts (34, 41, 52, 53, beamer_tables.R) updated in single commit
- [ ] Full pipeline `34:53` runs clean after rename

## Dependencies & Risks

**Dependencies:**
- Script 32 already produces overlap alignment columns — no changes needed there
- Script 33 needs same baseline-averaging change as script 36 (previously missed)
- Raw affiliation data (`owner_aff_firm_year_party_2002_2019.qs2`) must have multi-year coverage per firm for averaging to help
- Multi-muni flag requires RAIS panel from script 22

**Risks:**
- **Averaged baselines may not help much** if most firms are observed in all 4 baseline years already (the single-year and average would be similar). The affiliation diagnostics script (`diagnostics/explore_affiliation.R`) should be run first to quantify gaps.
- **Interaction specifications may have weak first stages** if triple alignment is rare. Check prevalence of each alignment state in script 32 diagnostics.
- **Non-spreading may reduce changes first-stage F-stats** due to fewer effective observations. This is acceptable if the conceptual argument is sound.
- **Rename collision window**: partial pipeline runs between renaming script 34 and updating scripts 41/52/53 will silently produce wrong regressions. Mitigate by atomic commit + full pipeline re-run.
- **Script 41 file read logic**: currently reads separate files for levels vs. changes instruments. Must update to read the unified file.

## Implementation Order

1. **Rename (atomic commit)**: Update scripts 34, 41, 52, 53, beamer_tables.R for `Z_*`/`dZ_*` naming. Re-run `34:53` to validate.
2. **Script 33**: Averaged baselines for sector weights (parallel with 36, same logic)
3. **Script 36** (most complex): baseline averaging + interaction instruments + no dFA spreading
4. **Script 34**: no dZ-changes spreading + unified output file
5. **Script 42**: add `is_multi_muni` flag
6. **Script 51**: full regression battery with performance optimizations
7. **Documentation**: `regs.tex`, `CLAUDE.md`, `shift_share.md`
8. **Validation**: run full pipeline `33,34,36,42,51` and verify all acceptance criteria

## Script-by-Script Change Summary

| Script | File | Changes |
|--------|------|---------|
| 32 | `32_build_alignment_shocks.R` | **No changes** — already produces all needed overlap columns |
| 33 | `33_select_baseline_weights.R` | **(NEW)** Replace single-year cycle_map with averaged 4-year baseline windows (same logic as 36) |
| 34 | `34_build_shift_share_instruments.R` | (a) Rename `Zlev_*` → `Z_*`, `Z_*` → `dZ_*`; (b) stop spreading changes instruments; only spread levels and controls; (c) merge levels + changes into single output file |
| 36 | `36_build_firm_level_instruments.R` | (a) Replace `cycle_map` single-year baselines with averaged 4-year windows; (b) add interaction instruments using overlap `dalign_`/`align_` columns with combined baseline windows; (c) stop spreading `dFA` instruments |
| 41 | `41_build_muni_panel.R` | Update instrument column references from `Zlev_*`/`Z_*` to `Z_*`/`dZ_*`; update file read logic for unified instrument file |
| 42 | `42_build_firm_panel.R` | Add `is_multi_muni` flag; report multi-muni summary stats |
| 51 | `51_firm_first_stage.R` | Restructure as spec-grid loop with performance optimizations (`nthreads=4`, sample batching, extract-and-discard); add collinearity reporting; produce comprehensive summary output |
| 52 | `52_sector_first_stage.R` | Update regression formulas and coefficient maps to `Z_*`/`dZ_*` naming; add `mem.clean=TRUE` |
| 53 | `53_sector_second_stage.R` | Update instrument column references to `Z_*`/`dZ_*` naming |
| — | `_utils/beamer_tables.R` | Update `COEF_MAP_INSTRUMENTS` for `Z_*`/`dZ_*` naming; update LaTeX labels (`$\Delta Z$` for changes) |
| — | `paper/regs.tex` | Update baseline definition, add interaction instruments, note non-spreading, update `Z`/`\Delta Z` notation |
| — | `CLAUDE.md` | Update variable names, design decisions, conventions |
| — | `docs/shift_share.md` | Update sections 3, 4, 5; add interaction section |

## Sources & References

- **Origin brainstorm:** [docs/brainstorms/2026-03-14-firm-sector-first-stage-disconnect-brainstorm.md](docs/brainstorms/2026-03-14-firm-sector-first-stage-disconnect-brainstorm.md) — Key findings: (1) small firms drive the firm-level result, (2) Jensen's inequality may attenuate sector aggregation, (3) interaction effects were deferred pending baseline diagnostics
- **Affiliation diagnostics brainstorm:** [docs/brainstorms/2026-03-15-affiliation-data-diagnostics-brainstorm.md](docs/brainstorms/2026-03-15-affiliation-data-diagnostics-brainstorm.md) — Temporal gaps (Diagnostic 4) and multi-muni prevalence (Diagnostic 5) directly motivate the averaged-baseline and multi-muni changes
- **Regression table standard:** [docs/solutions/best-practices/latex-regression-tables-beamer-standard.md](docs/solutions/best-practices/latex-regression-tables-beamer-standard.md) — font_size=7 for 11+ columns, split across frames, save_wald_summary() for compact summaries
- Related plan: [docs/plans/2026-02-27-feat-robust-first-stage-specification-plan.md](docs/plans/2026-02-27-feat-robust-first-stage-specification-plan.md)
