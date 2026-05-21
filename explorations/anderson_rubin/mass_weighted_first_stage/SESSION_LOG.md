# Session Log — Mass-Weighted First-Stage Horserace

## 2026-05-11

- Created exploration folder and README
- Plan v1: 3 scripts (build VAR-B, horserace, diagnostics) + findings memo
- Reusing a7 winner output for VAR-A; reusing production sector instruments for BASE
- Plan v2: extended to a 3 × 2 grid (3 mass specs × {LEV, DIF} shifts). Added
  Step 1b to build differences shifts for BASE and VAR-A using their existing
  share weights against `dAlign^c_mpt`. Hypotheses 4 and 5 cover the DIF
  stratum; decision rule has two independent verdicts (mass dimension and
  shift dimension)
- Brazilian electoral cadence: cross-office channels have TWO pulses per
  4-year mayoral cycle (year 1 = mayor, year 3 = gov/pres) under DIF, not
  one — Remark 1 of the methodology spec underestimated this
- Next: implement `R/01_build_variant_b.R`

## 2026-05-12

- Plan v3: clarified this branch is an exploration-only `policy_block`
  diagnostic, not a production-margin commitment.
- Tightened the first-stage statistic: report per-channel and joint-channel
  two-way-clustered Wald F statistics from `fixest::wald`; label these as
  KP-style diagnostics only, not literal SW/KP statistics from a full IV system.
- Corrected the outcome source: build a local `emp_share_policy_block_panel.qs2`
  from RAIS employment; do not use script 41 `s_mjt`, which is currently BNDES
  credit share.
- Resolved denominator default for VAR-B: use full municipal RAIS employment
  including outside/XX blocks as primary, emit active-block denominator as
  robustness. Zero pre-window sector-muni cells stay in the balanced panel with
  zero predetermined exposure.
- Implemented local scripts under `R/`: `00_helpers.R`, `01_build_variant_b.R`,
  `01b_build_dif_shifts_existing_specs.R`, `02_horserace.R`, and
  `03_diagnostics.R`. No production pipeline scripts were modified.
- Executed the full exploration from this subfolder. Outputs written under
  `output/`: `variant_b_instruments.qs2`, `dif_shifts_base_vara.qs2`,
  `emp_share_policy_block_panel.qs2`, `horserace_fstats.csv`,
  `horserace_coefs.csv`, `horserace_summary.tex`,
  `rank_correlation_summary.tex`, `herfindahl_distribution.pdf`,
  `disagreement_munis.csv`, and `dif_event_year_decomposition.csv`.
- Corrected VAR-B implementation after the first run: current FA is now computed
  locally from frozen pre-window firm support, `firm_baseline_exposures.qs2`,
  and `alignment_shocks.qs2`, so exited firms and current sector movement do
  not define support. Re-ran scripts 01, 02, and 03 after this correction.
- Findings: VAR-A remains the conservative mass-dimension recommendation.
  VAR-B wins the per-channel average F diagnostic in 4/4 channels, but fails
  the Herfindahl guardrail: VAR-B p95 concentration is 2.7x--10.2x VAR-A
  across channel-shift cells.
- Shift timing: promote DIF as a methodology candidate for cross-office
  channels under VAR-A (cross-office DIF/LEV ratio = 11.17), but keep LEV for
  the mayor-only channel.
- Caveat: several clustered Wald calculations required fixest VCOV repair
  because clustering includes only four policy blocks. The joint-channel F
  values are reported as required but interpreted as clustered Wald/KP-style
  diagnostics, not literal KP/SW statistics from a full IV system.
- Clarified `findings.md`: winsorizing VAR-B is not a post-hoc fix for BJS-3
  but a new candidate instrument that must be rebuilt from frozen support and
  validated through pre-specified HHI, first-stage, coefficient-stability,
  active-denominator, and leave-one-out checks. Also documented why
  shock-level AKM inference is still pending: this branch only builds
  panel-level `fixest` diagnostics and does not yet construct the required
  shock-level aggregation object. Registered the follow-up as A20 in
  `docs/PROJECT_BLUEPRINT.md`.
