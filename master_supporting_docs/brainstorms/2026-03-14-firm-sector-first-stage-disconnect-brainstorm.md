# Brainstorm: Diagnosing the Firm-to-Sector First Stage Disconnect

**Date**: 2026-03-14
**Status**: Active

## What We're Investigating

The firm-level first stage shows that political alignment predicts BNDES lending (extensive and intensive margins), and the result is **stronger without employment weights** (small firms drive the effect). However, this signal does not translate into a strong sector-level first stage, where `delta_s_mjt` (change in BNDES sector share) is regressed on shift-share instruments `Z_mjt`.

The project's identification strategy depends on sector-level instrument relevance, so understanding and resolving this disconnect is critical.

## Root Cause Hypotheses

### H1: Scale Effect (likely)

If alignment raises **total** BNDES to a municipality roughly proportionally across sectors, the firm regression detects a level effect (more firms get credit), but `delta_s_mjt` doesn't move because shares stay flat. The sector first stage only detects **cross-sector reallocation**, not overall expansion.

### H2: Cross-Sector Cancellation (likely, related to H1)

Connected owners are spread across many sectors within a municipality. When alignment flips, BNDES grows in multiple sectors simultaneously. Since `Sum_j delta_s_mjt = 0` by construction, these gains cancel in shares. This is the micro-mechanism that produces H1.

### H3: Weighting Mismatch (ruled out)

Employment weighting *reduces* the firm-level coefficient strength, meaning small firms drive the result. Since the sector instrument uses owner-count weights (which weight small firms more equally), there is no dilution from large-firm overweighting. **This hypothesis is ruled out.**

### H4: Jensen's Inequality in Instrument Construction

The firm-level instrument is `FA_fmt = Sum_p (L_fp/L_f) * Align_pmt` — a sum of **ratios**.
The sector instrument is `Z_mjt = Sum_p (L_mjp/N_mj) * dAlign_pmt` where `L_mjp/N_mj = Sum_f L_fp / Sum_f L_f` — a **ratio of sums**.

These differ by Jensen's inequality. Firms with few total owners but high party share are overweighted in the firm aggregation relative to the sector instrument. This could attenuate the sector instrument relative to what the firm-level results would imply.

## Diagnostic Plan

### Diagnostic 1: Aggregate Firm Equation

Sum the firm-level first stage within (muni, sector, year) and compare the implied sector-level instrument to `Z_mjt`.

**Sub-approach A — Fix the sector instrument**: Reconstruct `Z_mjt` as the simple average of firm-level `FA` within (m, j):

```
Z_alt_mjt = (1/N_firms_mj) * Sum_f FA_fmt = (1/N_firms_mj) * Sum_f Sum_p (L_fp/L_f) * Align_pmt
```

This matches the firm aggregation exactly. Run the sector first stage with `Z_alt_mjt` instead of `Z_mjt`.

**Sub-approach B — Weight firm regression by L_f**: Weight the firm regression by `L_f` (total owner count) instead of `n_employees`. Then the within-(m,j) weighted sum produces:

```
Sum_f L_f * (L_fp/L_f) = Sum_f L_fp = L_mjp
```

And dividing by `Sum_f L_f = N_mj` recovers exactly `Z_mjt = L_mjp/N_mj`. This shows the existing sector instrument is the aggregation of the firm instrument **under owner-count weighting**.

**Both approaches run as robustness** to see which aggregation path preserves the most signal.

### Diagnostic 2: Cross-Sector Variation Test

Compute how much `Z_mjt` actually varies across sectors within a muni-year:

- Within-muni-year variance of `Z_mjt` across sectors (the identifying variation for the sector×year FE spec)
- Between-muni-year variance (what muni×year FE absorbs)
- Concentration of party affiliations across sectors: Herfindahl of `L_mjp` across sectors j for each (m, p)

If cross-sector variation is small, the sector×year FE absorbs most of the instrument's signal, explaining why the muni×year FE specification performs better (as already observed in the presentation).

## Key Decisions Made

1. **Multi-level alignment interactions** (e.g., FA_double for party holding 2+ offices): interesting but deferred — adds complexity without first understanding the baseline disconnect.
2. **Level vs. share LHS** (running sector regression on total BNDES volume instead of shares): deferred for future investigation.
3. **Both aggregation approaches** (fix sector instrument AND weight firm regression by L_f) will be tried as robustness.

## Open Questions

1. If the cross-sector variation diagnostic confirms that `Z_mjt` has very little within-muni-year variation, what is the preferred next step? (Options: redesign instrument, change FE structure, pivot to level regressions — to be decided after seeing diagnostic results.)
2. How should we handle the LHS mismatch? The firm LHS is `1(BNDES > 0)` or `log(BNDES)` per firm. The sector LHS is a share `s_mjt = bndes_mjt / bndes_mt`. Even after perfect instrument alignment, the LHS transformation could attenuate the result. Should we also test a "count-based" sector LHS (fraction of firms in sector j receiving BNDES)?

## Relationship to Current Pipeline

- **Script 36** (`build_firm_level_instruments.R`): constructs `FA_*` and `dFA_*`
- **Script 31** (`build_sector_exposure_weights.R`): constructs `L_mjp/N_mj`
- **Script 34** (`build_shift_share_instruments.R`): constructs `Z_mjt` from sector weights × alignment
- **Script 51** (`firm_first_stage.R`): firm-level estimation (already has aggregation verification diagnostic, lines ~593-641)
- **Script 52** (`sector_first_stage.R`): sector-level estimation

New diagnostics will likely be implemented as:
- A new diagnostic script (e.g., `diagnostics/diagnose_firm_sector_link.R`)
- Modifications to script 34 or 31 to produce `Z_alt_mjt`
- A robustness variant of script 51 with `L_f` weights
