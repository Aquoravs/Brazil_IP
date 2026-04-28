# Plan: Add Sector-Classification Explainers to Aggregated First-Stage Talk

**Status:** COMPLETED

## Context

`paper/sections/agg_first_stage.tex` has plain transition slides for the three classification blocks:
- BNDES sector
- custom 11-sector grouping
- size bins

Those divider slides currently show only the title and directory name, even though there is enough space to explain what each classification means.

## Goal

Add a short, presentation-friendly explanation of each classification directly on its transition slide.

## Approach

1. Use the mapping scripts as the source of truth:
   - `scripts/R/3_instruments/30b_build_bndes_sector_mapping.R`
   - `scripts/R/3_instruments/30_build_sector_groups.R`
   - `scripts/R/3_instruments/30c_build_size_bin_mapping.R`
2. Patch `scripts/R/5_estimation/52b_agg_first_stage_summary.R` so each section-divider frame includes:
   - BNDES sector: the 4 broad BNDES groups
   - Custom sector: the 11 grouped sectors (including the residual group note)
   - Size bin: the 3 national terciles based on pre-election average employment
3. Rebuild `paper/sections/agg_first_stage.tex` and compile it to confirm the new slides fit cleanly.

## Verification

1. Run `Rscript scripts/R/5_estimation/52b_agg_first_stage_summary.R`
2. Confirm the new explainer text appears on the three divider slides in `paper/sections/agg_first_stage.tex`
3. Compile the deck successfully with XeLaTeX

## Outcome

- Added classification explainer text to the three section-divider slides in `scripts/R/5_estimation/52b_agg_first_stage_summary.R`.
- Rebuilt `paper/sections/agg_first_stage.tex`; the BNDES, custom-sector, and size-bin divider slides now describe the underlying grouping logic.
- Verified a clean two-pass XeLaTeX build of `paper/sections/agg_first_stage.pdf`.
