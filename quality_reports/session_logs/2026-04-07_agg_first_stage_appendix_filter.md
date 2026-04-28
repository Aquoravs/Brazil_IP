## 2026-04-07 12:32 - Tighten Appendix Filter

**Operations:**
- Reviewed `paper/sections/agg_first_stage.tex` and traced its generator to `scripts/R/5_estimation/52b_agg_first_stage_summary.R`.
- Inspected representative appendix table files to verify that the current significance test is table-level rather than column-level.
- Created `quality_reports/plans/2026-04-07-tighten-agg-first-stage-appendix-filter-plan.md`.

**Decisions:**
- Implement the rule in the generator, not by manually editing the generated `.tex`, so future rebuilds preserve the requested appendix logic.
- Interpret the requested `p<0.05` condition at the column level: a significant coefficient only qualifies when its own column's F-statistic is below `10,000`.

**Results:**
- Confirmed the current generator includes appendix tables whenever any `**` appears anywhere in the table, even if that significance is attached only to suspicious `F > 10,000` columns.

**Commits:**
- None.

**Status:**
- Done: rule interpretation, generator identification, and plan setup.
- Pending: patch the parser, rebuild `agg_first_stage.tex`, compile, and record the final appendix counts.

## 2026-04-07 12:35 - Filter Tightened and Deck Rebuilt

**Operations:**
- Patched `scripts/R/5_estimation/52b_agg_first_stage_summary.R` to parse significance column-by-column and require `F < 10,000` for the `p<0.05` appendix path.
- Regenerated `paper/sections/agg_first_stage.tex` with `Rscript scripts/R/5_estimation/52b_agg_first_stage_summary.R`.
- Compiled `paper/sections/agg_first_stage.tex` with two XeLaTeX passes.

**Decisions:**
- Treat the appendix rule as combo-specific: significance only counts when the same combo has a non-suspicious F-statistic.
- Keep the main grid formatting unchanged and tighten only the appendix-selection rule plus its explanatory slide text.

**Results:**
- Appendix qualification dropped from 36 to 32 specs.
- Group counts changed from `BNDES Sector 10 / Custom Sector 9 / Size Bin 17` to `8 / 8 / 16`.
- Removed appendix tables:
  - `BNDES Share --- Coal · Ew · JxT · NoCtrl` (BNDES Sector)
  - `BNDES Share --- Party · Ew · JxT · NoCtrl` (BNDES Sector)
  - `BNDES Share --- Party · Ew · JxT · NoCtrl` (Custom Sector)
  - `BNDES Share --- Coal · Ew · JxT · NoCtrl` (Size Bin)
- Standalone Beamer build succeeded and produced `paper/sections/agg_first_stage.pdf` with 52 pages.

**Commits:**
- None.

**Status:**
- Done: generator patch, TeX regeneration, and compile verification.
- Pending: none.
