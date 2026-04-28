# Plan: Tighten Aggregated First-Stage Appendix Inclusion Rule

**Status:** COMPLETED

## Context

`scripts/R/5_estimation/52b_agg_first_stage_summary.R` generates `paper/sections/agg_first_stage.tex` by parsing existing regression tables. The current appendix filter includes a table if it has either:
- any genuine `F > 10` with `F < 10,000`, or
- any coefficient marked `**` / `***` anywhere in the table.

That second branch is too permissive for the requested presentation rule because it does not require the significant coefficient to belong to a column whose own F-statistic is below `10,000`.

## Requested Rule

Appendix slides should appear only if at least one column satisfies either:
1. `F > 10` and `F < 10,000`, or
2. a coefficient is significant at `p < 0.05` and that same column has `F < 10,000`.

## Approach

**File:** `scripts/R/5_estimation/52b_agg_first_stage_summary.R`

- Replace the current table-level significance detector with a column-level parser that returns six logical flags aligned with the six instrument-combo columns.
- Keep `parse_fstats()` as the source of raw column F-statistics.
- Qualify a table only when at least one column passes one of the two requested conditions.
- Update the appendix summary slide title/note so the stated rule matches the implemented filter.
- Regenerate `paper/sections/agg_first_stage.tex` and compile it to verify the new appendix list.

## Verification

1. Run `Rscript scripts/R/5_estimation/52b_agg_first_stage_summary.R`
2. Confirm the appendix counts and slide list in `paper/sections/agg_first_stage.tex`
3. Compile the presentation file and check for successful output

## Outcome

- Regenerated `paper/sections/agg_first_stage.tex` with the tighter column-level appendix filter.
- Appendix counts changed from `10 / 9 / 17` to `8 / 8 / 16` across BNDES Sector / Custom Sector / Size Bin.
- Verified standalone compilation with `xelatex -interaction=nonstopmode agg_first_stage.tex` (two passes).
