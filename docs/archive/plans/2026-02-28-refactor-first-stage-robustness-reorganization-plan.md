---
title: "Refactor First-Stage: Clean Baseline + Robustness Variations"
type: refactor
status: active
date: 2026-02-28
updated: 2026-03-01
---

# Refactor First-Stage: Clean Baseline + Robustness Variations

## Goal

Reorganize `51_first_stage.R` so results are easy to read and compare. Not a final paper table — an exploration tool to see how the first stage behaves across specifications.

**Key design principle**: Every table has the same 6-column structure (M, G, P, M+G, M+P, All), and only one dimension changes per table. The frame title tells you what changed; the footnote tells you what's held constant. No duplicate notes.

## Baseline Specification

| Dimension | Choice |
|-----------|--------|
| Sector variable | `sector_group` |
| Baseline weights | Cycle-specific |
| Alignment | Coalition |
| Fixed effects | `muni_id^sector_group + sector_group^year` |
| Controls | `exposure_control_cycle_specific` |
| Clustering | Two-way: `muni_id + sector_group` |

## Script 51 Structure

All tables below have **6 columns**: M, G, P, M+G, M+P, M+G+P (all instrument combinations). Each column header is just the instrument combo label. The frame title and single footnote together convey the full specification.

### Table 1: Baseline Specification

**Frame title**: "First Stage: Baseline Specification"
**6 columns**: Mayor, Governor, President, M+G, M+P, All
**Footnote**: "Muni × sector + sector × year FE. Coalition alignment, cycle-specific weights, with exposure control. SEs clustered by muni + sector. ***p<0.01, **p<0.05, *p<0.10."

This merges the old Tables 1 and 2. Shows which tiers have individual power and whether combining helps.

### Table 2: FE Robustness — Muni × Year

**Frame title**: "First Stage: Muni × Year FE"
**6 columns**: same 6 instrument combos
**Footnote**: "Muni × sector + muni × year FE. Coalition, cycle-specific, with control. SEs clustered by muni + sector. ..."

### Table 3: FE Robustness — Year Only

**Frame title**: "First Stage: Year FE Only"
**6 columns**: same 6 instrument combos
**Footnote**: "Muni × sector + year FE. Coalition, cycle-specific, with control. ..."

### Table 4: Party Alignment (instead of Coalition)

**Frame title**: "First Stage: Party-Level Alignment"
**6 columns**: same 6 instrument combos
**Footnote**: "Muni × sector + sector × year FE. Party alignment, cycle-specific, with control. ..."

### Table 5: No Exposure Control

**Frame title**: "First Stage: Without Exposure Control"
**6 columns**: same 6 instrument combos
**Footnote**: "Muni × sector + sector × year FE. Coalition, cycle-specific, no exposure control. ..."

### Table 6: 2002-Fixed Baseline Weights

**Frame title**: "First Stage: 2002-Fixed Weights"
**6 columns**: same 6 instrument combos
**Footnote**: "Muni × sector + sector × year FE. Coalition, 2002-fixed weights, with control. ..."

### Table 7: Levels Specification

**Frame title**: "First Stage: Levels ($s_{mjt}$ on $Z^{\\text{levels}}$)"
**6 columns**: same 6 instrument combos
**Footnote**: "Muni × sector + sector × year FE. Coalition, cycle-specific, with control. ..."

### Figures (end of script 51, after all tables)

**Figure 1: Coefficient Forest Plot.** Point estimates + 95% CIs for the Mayor instrument across all specifications (Tables 1-7). One horizontal line per spec, grouped by table.

**Figure 2: F-Statistic Summary.** Dot chart of Wald F across all specifications. Stock-Yogo line at F=10. Color by strong/weak.

## Changes from Previous Plan

1. **Merged Tables 1+2** into a single 6-column baseline table.
2. **Robustness tables now show all 6 instrument combos** instead of just M and M+G. Each robustness table fixes one non-baseline dimension and shows how all 6 combos behave.
3. **Single footnote per table.** Removed the separate `\scriptsize` annotation in `first_stage.tex` — the table's own footnote is sufficient. Frame titles are descriptive.
4. **Consistent 6-column layout** across all tables makes comparison trivial.

## Implementation Notes

### Helper function for 6-combo tables

Create a helper `run_six_combos()` that fits 6 models given tier Z-column names and optional control/FE:

```r
run_six_combos <- function(z_m, z_g, z_p, ec, fe, data) {
  # Returns named list: Mayor, Governor, President, M+G, M+P, All
  # Each entry is a feols() fit, or NULL if column is NA
}
```

Each table block calls `run_six_combos()` with the appropriate column names, then passes the result to `save_beamer_table()`.

### Notes handling

- Pass explicit `notes` argument to `save_beamer_table()` for each table, describing what's held constant.
- Remove all `\scriptsize` annotations from `first_stage.tex`. The frame title + footnote provide all context.
- Do NOT include "Baseline spec: ..." lines in the `.tex` — that info is in the footnote.

### first_stage.tex changes

- Remove `\scriptsize` annotation lines below each `\input{}`
- Update frame titles to be descriptive (as specified above)
- Table numbers shift: old T3 → T2, old T4 → T3, etc.

## Acceptance Criteria

- [x] Tables 1-7 each have exactly 6 columns (M, G, P, M+G, M+P, All)
- [x] Each table has a single footnote (no duplicate notes in `.tex` wrapper)
- [x] Frame titles in `first_stage.tex` clearly identify the specification
- [ ] Tables run correctly for both `--sector-var=sector_group` and `cnae_section`
- [x] Figures 1-2 generated at the end of script 51
- [x] Each table prints F-stats and diagnostics to console
- [x] Clean LaTeX output via `save_beamer_table()`

## Sources

- Current script: `BNDES/politicsregs/5_estimation/51_first_stage.R`
- Helper: `BNDES/politicsregs/_utils/beamer_tables.R`
- Presentation: `paper/first_stage.tex`
- Design decisions: `docs/doubts.md`
