# Plan — AR test specification companion note

**Status:** APPROVED

## Goal

A concise companion document for the May 14, 2026 slides
(`journal/meetings/2026-05-14/slides.tex`) that answers the two questions a
viewer of the deck would ask: (1) what regression produced the numbers, and
(2) how was each variable in it constructed. Distilled from
`docs/methodology/ar_test_specification.tex`; theory is deferred to that
document, not repeated.

## Decisions (user-approved)

- **Location:** `journal/meetings/2026-05-14/specification_note.tex`
- **Depth:** distilled pointer (~2-3 pp) — estimating equation + variable
  construction only; all identification/theory cited out to the full spec.

## What changes

- New file: `journal/meetings/2026-05-14/specification_note.tex`
- Compiled PDF in `journal/meetings/2026-05-14/build/`

## Structure

1. Estimating equation — `eq:rf-est` specialized to the meeting run; per
   channel × control spec; AR joint F = cluster-robust Wald on the channel's Z's.
2. Four control specs — 2x2 (EC, Vol) -> RHS, from script 04 header.
3. Four channels — M / M.P / M.G / M.G.P; cross-office product; align columns.
4. Variable construction — outcome, Z (Variant A, scripts 01->02), EC, Vol,
   taxonomy + hold-out sector.
5. Sample (5,544 munis / 88,694 muni-years, complete-case) + AR statistic.
6. Scope note — coarse-taxonomy per-channel run, not the stacked production AR.
   Appendix: variable-provenance table.

## Sources traced

- `docs/methodology/ar_test_specification.tex` (full technical reference)
- `explorations/anderson_rubin/ar_meeting_2026_05_13/R/00_helpers.R` (windows)
- `.../R/01_build_variant_a_weights.R` (Variant A weights)
- `.../R/02_build_instruments_ec.R` (Z, EC)
- `.../R/03_build_muni_ar_panel.R` (log_gdp, vol_ratio, hold-out)
- `.../R/04_run_ar_regressions.R` (the 4x4 regression grid, AR Wald)

## Verification

- Compiles with xelatex/latexmk, no undefined references, no overfull-box errors.
- Notation matches `ar_test_specification.tex` exactly (INV-7).
