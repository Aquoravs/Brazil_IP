---
title: "feat: Diagnose Aggregated First Stage Collapse"
type: feat
status: completed
date: 2026-03-23
origin: docs/brainstorms/2026-03-14-firm-sector-first-stage-disconnect-brainstorm.md
---

# Diagnose Aggregated First Stage Collapse

## Overview

The firm-level first stage (script 51) shows strong results, but when aggregated to `(sector, muni, year)` cells in script 52, **all F-statistics drop below 2.3** and no coefficient reaches significance. This diagnostic script will systematically test competing hypotheses for why the firm-level political alignment signal weakens so sharply in the specific collapsed extensive-margin regression implemented by script 52.

## Problem Statement / Motivation

Script 52 is a diagnostic bridge between the firm-level first stage and the sector pipeline: it collapses the firm extensive-margin equation to `(sector, muni, year)` cells and asks whether the firm-level alignment signal is still visible once averaged within sector-municipality cells and estimated with `muni_id^sector + muni_id^year` fixed effects. If the signal disappears at this step, we need to know whether the problem is diffuse exposure, thin cell support, FE absorption, or the aggregation form itself (see brainstorm: `docs/brainstorms/2026-03-14-firm-sector-first-stage-disconnect-brainstorm.md`).

The March 23 presentation documents the collapse quantitatively:

| Tier (coalition) | Firm Coef | Firm F | Agg Coef | Agg F |
|---|---|---|---|---|
| Mayor | 0.009* | 3.7 | 0.003 | 0.6 |
| Governor | 0.011*** | 6.7 | 0.004 | 0.8 |
| President | -0.013** | 6.1 | 0.010 | 2.3 |
| M+G+P | - | 5.1 | - | 1.0 |

Coefficients attenuate 60-70%; F-stats drop 80-90%; president sign flips.

## Proposed Solution

Implemented `BNDES/politicsregs/diagnostics/diagnose_agg_first_stage_collapse.R` - a multi-section diagnostic script that loads the firm panel (from script 42) and tests each hypothesis with specific, quantifiable diagnostics. Output: CSV tables and a recommendation note in `BNDES/output/diagnostics/agg_sector_collapse/`.

## Hypotheses and Diagnostic Tests

### H1: Cross-Sector Cancellation / Diffuse Exposure (Primary)

Connected owners spread across many sectors within a municipality. Alignment may raise the extensive-margin probability of BNDES across many sectors simultaneously, so the collapsed sector-municipality averages in script 52 may show little contrast across sectors after fixed effects.

**Tests:**

1. **HHI of party affiliations across sectors** - For each `(muni, party, election cycle)`, compute `HHI_mp = sum_j (L_mjp / L_mp)^2` where `L_mjp` = affiliated owner count in sector `j`. High HHI means sector-concentrated exposure; low HHI means diffuse exposure.
   - Report distribution of HHI across `(muni, party)` pairs
   - Cross-tabulate by party tier (mayor vs. gov vs. pres)
   - Weighted vs. unweighted by municipality size

2. **Cross-sector comovement in `H_jmt`** - For muni-years with non-zero instrument support, measure how similar sector-level `H_jmt` values are within the same municipality-year. High within-muni-year comovement means broad extensive-margin response rather than sharply differentiated sector response.

3. **Direct cancellation test** - Regress `H_jmt ~ FA_bar | muni_id^sector_group` (sector FE only, no `muni_id^year` FE) to see whether the municipality-level aggregate BNDES response is visible before muni-year FE absorb it. Compare F to the full-FE specification.

### H2: Thin Sector Coverage / Cell Sparsity

Median cell has only 2 pre-election firms. `H_jmt` takes values in `{0, 0.5, 1}` for much of the sample. Cell-level averages of `FA_bar` may be noisy with so few observations.

**Tests:**

4. **Cell size distribution** - Distribution of `N_pre` (pre-election firms per cell) by sector group and year. Report fraction of cells with `N_pre = 1, 2, 3-5, 6-10, 11-50, 50+`.

5. **BNDES coverage by sector** - What share of the 10 sector groups has positive BNDES credit in a given muni-year? Report the distribution across municipalities and evolution over time (2002-2017).

6. **Conditional F-statistics by cell size** - Re-run the aggregated regression restricted to cells where `N_pre >= k` for thresholds `k = 5, 10, 20, 50`. If F recovers as cell size increases, sparsity is likely an important bottleneck.

7. **Precision-weighted regression** - Weight the aggregated regression by `N_pre` (or `sqrt(N_pre)`) to give more precise cells more influence. Compare F to the unweighted specification.

### H3: FE Absorption

`muni_id^year` FE removes all municipality-level time variation, which may be where much of the script-52 signal lives. The firm-level spec uses `firm_id` FE, preserving within-cell firm-level variation that the collapsed regression no longer has.

**Tests:**

8. **Instrument FE absorption rate** - For each `FA_bar_*` column, regress `FA_bar ~ 1 | muni_id^sector_group + muni_id^year` and report within-FE R-squared. If R2 is very high, the FEs absorb nearly all instrument variation.

9. **Within-muni-year variance of instruments across sectors** - Compute `Var_j(FA_bar_jmt)` within each `(muni, year)`, then summarize the distribution across muni-years. This is the identifying variation for the muni-year FE specification. If this variance is near zero, there is little cross-sector variation left to identify the effect.

10. **Alternative FE specifications** - Re-run the aggregated regression with:
    - `muni_id^sector_group + sector_group^year`
    - `sector_group + year`
    - `muni_id^sector_group` only

    Compare F-statistics across specifications.

11. **Governor/president limited-variance note** - Document that `FA_bar_gov_jmt` and `FA_bar_pres_jmt` may have limited within-muni-year cross-sector variance because the alignment shock is common within muni-year and only sector exposure heterogeneity generates cross-sector spread. Treat this as an empirical variance question, not a mechanical identity.

### H4: Aggregation-Form Mismatch

Script 52 uses simple averages of firm-level instruments within `(sector, muni, year)` cells. This may differ materially from owner-count-based aggregation, which is closer to the sector exposure logic in the brainstorm.

**Tests:**

12. **Owner-count-weighted aggregation** - Weight by `L_f_0` (total baseline owner count per firm) to construct an alternative collapsed regressor aligned with the owner-count aggregation logic in the brainstorm Diagnostic 1, Sub-approach B.

13. **FA_bar vs. owner-count aggregate / Z correlation** - Merge the simple-average `FA_bar_jmt` with the owner-count aggregate and, if available, `Z_mjt` from `shift_share_instruments_sector.qs2`. Compute:
    - Raw correlation at the cell level
    - Within-FE partial correlation (after projecting out `muni_id^sector + muni_id^year`)
    - Coverage comparison: fraction of cells where both are defined

### H5: Sector Heterogeneity (Supplementary)

The aggregate F may mask sector-specific signal that is cancelled by other sectors.

**Tests:**

14. **Leave-one-sector-out F-statistics** - For each sector group, drop it and re-run the regression. If dropping a specific sector raises F, that sector may be actively cancelling signal.

15. **Sector-specific regressions** - Run the aggregated regression separately by sector group. Report which sectors, if any, yield `F > 5`.

## Technical Considerations

### Data Dependencies

- **Required**: `firm_panel_for_regs.fst` or `.qs2` (script 42)
- **Required**: `sector_group_mapping.qs2` (script 30, if using `sector_group`)
- **Required**: `firm_baseline_exposures.qs2` (script 36 side-output, for `L_fp_0` / `L_f_0` data and owner-count aggregation)
- **Optional**: `shift_share_instruments_sector.qs2` (script 34, for `FA_bar` vs. `Z` comparison)
- **Optional**: `firm_level_instruments.qs2` (script 36, for baseline exposure HHI)

### Column-Selective Loading

Use fst for memory efficiency. Required columns from firm panel:
```
firm_id, muni_id, year, cnae_section, sector_group,
has_bndes_fmt,
FA_mayor_coalition, FA_gov_coalition, FA_pres_coalition,
FA_mayor_party, FA_gov_party, FA_pres_party
```

Required columns from baseline exposures:
```
firm_id, year, party, L_fp_0, L_f_0
```

### Script Structure

Follow the pattern in `diagnose_firm_instruments.R`:
- Numbered sections with skip-if-done guards (check for output CSV existence)
- Bootstrap from `_utils/script_bootstrap.R`
- Accept `--sector-var=` CLI argument (default: `sector_group`)
- Output directory: `output/diagnostics/agg_sector_collapse/`
- Terminal recommendation note summarizing ranked evidence with caveats

### Key Design Decisions

1. **Pre-election filter**: Replicate script 52's filter (rows where any `FA != 0`) as the baseline, but also compute diagnostics on the full panel for comparison. The filter itself is a potential source of support loss.

2. **Election cycle handling**: The 2003 gov/pres cycle is dropped (no baseline data). Years 2003-2006 have `FA_gov = 0` and `FA_pres = 0` for all firms. Within-muni-year variance diagnostics for gov/pres should exclude or flag these years.

3. **Sector variable**: Default to `sector_group` (10 groups) to match script 52. Report cell-size distribution for both `sector_group` and `cnae_section` in the coverage diagnostic, since sector granularity directly affects sparsity.

4. **Output format**: CSV tables plus printed console summaries. No Beamer tables; this is a diagnostic, not a presentation output. Use `cat()` for structured console output.

## Acceptance Criteria

- [x] Script runs end-to-end from firm panel without manual intervention
- [x] HHI of party affiliations computed and distribution reported (H1, test 1)
- [x] Within-muni-year instrument variance computed (H3, test 9)
- [x] Cell size distribution tabulated by sector and year (H2, test 4)
- [x] Conditional F-statistics by cell size threshold reported (H2, test 6)
- [x] FE absorption R-squared for each `FA_bar` column (H3, test 8)
- [x] Alternative FE specifications compared with F-stats (H3, test 10)
- [x] Owner-count aggregation diagnostic reported (H4, test 12)
- [x] `FA_bar` vs. owner-count aggregate / `Z` correlation reported (H4, test 13)
- [x] Sector-specific F-statistics reported (H5, test 15)
- [x] Recommendation note saved summarizing ranked evidence with caveats

## Implementation Status

Completed on 2026-03-23.

Implemented files:
- `BNDES/politicsregs/diagnostics/diagnose_agg_first_stage_collapse.R`

Key realized outputs:
- `BNDES/output/diagnostics/agg_sector_collapse/baseline_regression.csv`
- `BNDES/output/diagnostics/agg_sector_collapse/hhi_summary.csv`
- `BNDES/output/diagnostics/agg_sector_collapse/conditional_f_by_npre.csv`
- `BNDES/output/diagnostics/agg_sector_collapse/instrument_fe_absorption.csv`
- `BNDES/output/diagnostics/agg_sector_collapse/alternative_fe_regressions.csv`
- `BNDES/output/diagnostics/agg_sector_collapse/owner_weighted_regressions.csv`
- `BNDES/output/diagnostics/agg_sector_collapse/aggregation_form_correlations.csv`
- `BNDES/output/diagnostics/agg_sector_collapse/sector_specific_regressions.csv`
- `BNDES/output/diagnostics/agg_sector_collapse/ranked_evidence_summary.csv`
- `BNDES/output/diagnostics/agg_sector_collapse/recommendation_note.md`

## Implementation Structure

### `diagnostics/diagnose_agg_first_stage_collapse.R`

```
Section 0: Bootstrap, CLI args, output directory setup
Section 1: Load firm panel (fst column-selective)
Section 2: Replicate script 52 aggregation (baseline)
Section 3: H1 - Cross-sector cancellation / diffuse exposure diagnostics
  3a: HHI of party affiliations across sectors
  3b: BNDES response correlation across sectors
  3c: Direct cancellation test (no muni-year FE)
Section 4: H2 - Cell sparsity diagnostics
  4a: Cell size distribution
  4b: BNDES coverage by sector
  4c: Conditional F-statistics by N_pre threshold
  4d: Precision-weighted regression
Section 5: H3 - FE absorption diagnostics
  5a: Instrument FE absorption R-squared
  5b: Within-muni-year variance of instruments
  5c: Alternative FE specifications
Section 6: H4 - Aggregation-form mismatch
  6a: Owner-count-weighted aggregation
  6b: FA_bar vs. owner-count aggregate / Z correlation (if Z file exists)
Section 7: H5 - Sector heterogeneity
  7a: Leave-one-sector-out F-stats
  7b: Sector-specific regressions
Section 8: Summary and recommendation note
```

## Success Metrics

The script should produce a ranked evidence summary, with caveats, for the most plausible explanations of script 52's weakness:
- Conditional F rising materially with higher `N_pre` thresholds supports **cell sparsity / support** as an important contributor
- High FE absorption R2 and very low within-muni-year variance support **FE absorption / limited identifying variation**
- Low HHI and broad within-muni-year cross-sector comovement in `H_jmt` support **diffuse exposure / cancellation**
- Large differences between simple-average `FA_bar` and owner-count aggregation support **aggregation-form mismatch**
- Substantially higher F under weaker FE should be interpreted as evidence on where the identifying variation lives, not by itself as proof that the baseline FE are "too strong"

## Sources & References

- **Origin brainstorm:** [docs/brainstorms/2026-03-14-firm-sector-first-stage-disconnect-brainstorm.md](docs/brainstorms/2026-03-14-firm-sector-first-stage-disconnect-brainstorm.md) - Key decision: employment-weight mismatch is not the main issue; the more relevant gap is simple firm averaging versus owner-count aggregation / Jensen-style differences
- **Results exhibited:** `paper/presentation_progress_2026_03_23.pdf` slides 6-11
- **Script 52:** `BNDES/politicsregs/5_estimation/52_aggregated_firm_sector_first_stage.R` - current aggregation logic
- **Script 51:** `BNDES/politicsregs/5_estimation/51_firm_first_stage.R` - firm-level reference
- **Diagnostic pattern:** `BNDES/politicsregs/diagnostics/diagnose_firm_instruments.R` - section-by-section structure to follow
- **First stage review:** `docs/first_stage_review.md` - documents FE-dependent F-stats; ungrouped (21 sections) yields F=12.4 vs. grouped F=6.1
