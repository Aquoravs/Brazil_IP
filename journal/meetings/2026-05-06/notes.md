Date: 2026-05-06

## Updated Instruments

Implement the updated version of the four instruments with the following options:

1. Pre-earliest election baseline exposure.
2. Variant A from subsection 2.3 (sector-level exposure weights): within-municipality normalization and owner-count weights inside a cell.
3. Frozen support for baseline exposure; contemporaneous observations for outcomes.
4. RAIS universe.

## AR Test Specifications

With these options, run the AR test across the following versions:

- `log GDP = instruments for muni-sector employment shares`
- `log GDP = instruments for muni-sector employment shares + Exposure control (EC)`
- `log GDP = instruments for muni-sector employment shares + volume control`
- `log GDP = instruments for muni-sector employment shares + volume control (loans/initial GDP) + EC`

## Output Format

Follow the format in `explorations/anderson_rubin/a10_composition_volume/output/slides.tex`:

- First column: office or cross-office instrument (M, MG, MP, MGP).
- Other columns: control combinations.
- First slide: joint F-statistic showing whether the AR test is rejected.
- Second slide: coefficients and significance for sectors, volume control, and EC — design a display that cleanly shows on/off controls across specs.

## Open Questions

- Possible correlation between baseline affiliation and future industry share of employment.
- Are alignment shifters iid to the municipal outcome?
- Is the shift-share in levels a problem for identification?
- Control for the sum of shares: pre-election sum of sector shares minus sectoral share.
