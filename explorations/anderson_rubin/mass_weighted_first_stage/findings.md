# Findings: Mass-Weighted First-Stage Horserace

Date: 2026-05-12

Research use status: supports next design decision. These outputs are diagnostic / research-building evidence only and are not production-pipeline inputs.

## Recommendation

**Mass dimension: keep VAR-A as the conservative recommendation.** On the main
outcome `emp_share_jmt = emp_jmt / emp_mt_full`, the exact frozen-support VAR-B
build improves the per-channel average clustered Wald diagnostic in all four
channels:

| Channel | BASE avg F | VAR-A avg F | VAR-B avg F | Winner |
|---|---:|---:|---:|---|
| M | 0.24 | 0.22 | 3.03 | VAR-B |
| MP | 0.71 | 0.92 | 1.78 | VAR-B |
| MG | 0.11 | 1.22 | 5.28 | VAR-B |
| MGP | 0.32 | 2.76 | 3.17 | VAR-B |

That first-stage gain is not enough to promote the current VAR-B because it
fails the BJS-3 concentration guardrail. Its 95th-percentile Herfindahl is 2.7x
to 10.2x VAR-A depending on channel-shift cell, far above the 15% tolerance.
The problem is not that VAR-B is weak; it is that the employment-mass version
lets a small number of high-employment sector-municipality cells carry too much
of the identifying variation. Adding a concentration control can be useful as
a diagnostic, but it does not by itself solve BJS-3 because the instrument's
variation remains concentrated. Winsorization would define a new instrument,
not repair the existing one.

VAR-B should therefore be treated as evidence that employment mass contains
signal, not as the next-step candidate in its current form. A winsorized VAR-B
is worth testing, but it should only be considered admissible if it is rebuilt
from frozen pre-window support and clears a pre-specified robustness battery:

1. Define the cap ex ante, preferably as a small grid such as p95, p97.5, and
   p99 caps on firm pre-window employment or on sector-municipality employment
   shares.
2. Recompute the VAR-B instruments and the full Herfindahl distribution under
   each cap; do not winsorize the finished `Z` after construction.
3. Require the 95th-percentile Herfindahl to fall close to VAR-A under the same
   channel-shift cells, using the original 15% rule or a revised rule stated
   before looking at outcomes.
4. Re-run the per-channel and joint first-stage diagnostics, plus both
   active-denominator outcome and active-denominator VAR-B instrument
   robustness.
5. Check stability of coefficient signs, within-municipality rank correlations,
   and leave-one-policy-block / leave-one-high-Herfindahl-municipality results.
6. If the winsorized version passes these checks, carry it into the AR
   robustness table alongside unmodified VAR-A and unmodified VAR-B; if it only
   works under aggressive caps, report that as evidence that the employment
   signal is driven by dominant-employer cells.

## LEV vs DIF

**Promote DIF as a methodology candidate for the cross-office channels under
VAR-A; keep LEV for the mayor-only channel.** Under the recommended mass spec,
VAR-A, the cross-office DIF/LEV F ratio is 11.17 when averaged over MP, MG, and
MGP, clearing the 0.8 promotion rule. The mayor-only channel behaves as
expected: VAR-A M-DIF has F = 0.06 versus M-LEV F = 0.38, so M should remain
LEV in any mixed timing stack.

The DIF event-year decomposition behaves as expected. For VAR-B, cross-office
DIF has both pulses: gov/pres-transition shares of DIF sum-of-squares are 0.42
for MG, 0.45 for MP, and 0.61 for MGP.

## Denominator Sensitivity

The main VAR-B instrument uses the full municipal RAIS denominator, including
outside/XX employment. The active-block denominator robustness was emitted in
`output/variant_b_instruments.qs2`.

For the outcome denominator, the active-block share robustness does not overturn
the conservative VAR-A recommendation. It changes the timing ranking: VAR-B-DIF
is much stronger under the active-block outcome than under the full-denominator
outcome, but VAR-A-LEV remains the largest active-denominator joint diagnostic.

| Outcome | BASE LEV | BASE DIF | VAR-A LEV | VAR-A DIF | VAR-B LEV | VAR-B DIF |
|---|---:|---:|---:|---:|---:|---:|
| Full denom | 9,804,654 | 2,654,439 | 5,020,373 | 29,074,499 | 1,026,781 | 9,830,656 |
| Active denom | 3,378,330 | 14,674,849 | 1,020,475,259 | 16,044,654 | 78,067 | 120,015,187 |

These joint-channel Wald values are useful as the required KP-style diagnostic
but should not be read as literal KP/SW statistics from a full IV system.

## Caveats

- `fixest` repaired several non-positive-semidefinite clustered VCOV matrices;
  this is unsurprising with only four policy-block clusters and can inflate
  Wald magnitudes. The recommendation therefore leans on the per-channel
  ranking plus the concentration diagnostics, not only the huge joint Wald
  numbers.
- Shock-level AKM inference has not been implemented in this branch. The
  current scripts are panel-level `fixest` diagnostics at the
  `(municipality, policy block, year)` unit. AKM requires a separate
  shock-level aggregation that maps each channel-party-municipality-year shock
  to exposure-weighted outcomes/residuals and defines the relevant shock
  clusters. That machinery is not yet in the production pipeline, and the
  current branch was scoped as a quick first-stage horserace. Until the
  shock-level object exists, the joint Wald values should be read as screening
  diagnostics rather than inference-ready evidence.
- VAR-B is built from frozen mayoral pre-window support and computes current
  FA locally from `firm_baseline_exposures.qs2` and `alignment_shocks.qs2`,
  so current-year sector or municipality movement does not define support.
- BASE and VAR-A have 280,420 main-outcome observations; VAR-B has 289,220
  because its local frozen-support build drops only full-denominator-zero
  muni-cycles and keeps balanced sector rows.

## Outputs

- `output/variant_b_instruments.qs2`
- `output/dif_shifts_base_vara.qs2`
- `output/emp_share_policy_block_panel.qs2`
- `output/horserace_fstats.csv`
- `output/horserace_coefs.csv`
- `output/horserace_summary.tex`
- `output/rank_correlation_summary.tex`
- `output/herfindahl_distribution.pdf`
- `output/disagreement_munis.csv`
- `output/dif_event_year_decomposition.csv`
