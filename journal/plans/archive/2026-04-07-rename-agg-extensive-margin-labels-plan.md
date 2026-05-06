# Plan: Rename Aggregated Extensive-Margin Slide Labels

**Status:** COMPLETED

## Context

The aggregated first-stage presentation in `paper/sections/agg_first_stage.tex` uses the label `H^{\text{pre}}_{jmt}` in the appendix table headers for the `bndes_extensive` outcome. That notation is not transparent in slides.

The user requested a clearer label such as "share of firms receiving a loan".

## Goal

Replace the opaque extensive-margin notation in the aggregated first-stage slides with plain language while preserving the underlying estimates and appendix-selection logic.

## Approach

1. Update the source label in `scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R` so future table exports use a clearer dependent-variable label.
2. Update `scripts/R/5_estimation/52b_agg_first_stage_summary.R` so summary and appendix slide titles use a clearer extensive-margin outcome name.
3. Patch the already-exported aggregated extensive-margin table files under `paper/tables/agg_firm_*` so the current presentation changes immediately without rerunning the full estimation battery.
4. Rebuild `paper/sections/agg_first_stage.tex` and compile it to verify the new wording.

## Target Wording

- Slide titles: `Share Receiving BNDES Loan`
- Table header: `$\text{Share of firms receiving a BNDES loan}_{jmt}$`

## Verification

1. Regenerate `paper/sections/agg_first_stage.tex`
2. Confirm the new wording appears in the summary and appendix slides
3. Compile `paper/sections/agg_first_stage.tex` successfully

## Outcome

- Updated the upstream `bndes_extensive` dependent-variable label in script `52` to `$\text{Share of firms receiving a BNDES loan}_{jmt}$`.
- Updated script `52b` so extensive-margin summary and appendix slide titles now read `Share Receiving BNDES Loan`.
- Replaced the old `H^{\text{pre}}_{jmt}` header in the already-exported aggregated extensive-margin tables.
- Regenerated `paper/sections/agg_first_stage.tex` and verified a clean two-pass XeLaTeX build of `paper/sections/agg_first_stage.pdf`.
