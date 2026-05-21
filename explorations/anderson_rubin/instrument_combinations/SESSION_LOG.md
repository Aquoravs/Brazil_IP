# Session Log — AR Test Instrument Combinations

## 2026-05-20 — branch created

- Triggered by the 2026-05-14 meeting note "Instrument Combinations": advisors
  asked why the AR test uses mayor-crossed channels and why the design moved
  away from individual M/G/P instruments in one regression.
- Reviewed prior documents: `ar_test_specification.tex` (cross-office channel
  structure), `office_specific_exposure_weights.md`, decision log D25/D26/D31,
  `ar_test_strategy.md` (the original additive tier stack), 2026-05-14
  `specification_note.tex` (current per-channel implementation),
  `04_run_ar_regressions.R`.
- Wrote `R/ar_instrument_combination_sim.R`: Monte Carlo (N=4000, 2000 reps)
  comparing six instrument sets on AR-test size and power, plus a governor
  exclusion-violation knob.
- Result: all valid sets correctly sized; `{M·G}` alone is the most powerful;
  `{M,G,M·G}` is weaker than `{M·G}`; the additive `{M,G,P}` stack is the
  weakest genuine set; a governor exclusion violation drives every G-containing
  set to ~100% false rejection while M and M·P stay at 5%.
- Wrote `findings.md` with the summary of prior decisions, the three-regime
  framework, the result tables, answers to the two advisor questions, and a
  recommendation (keep cross-office per-channel; do not pad interactions with
  main effects; M is the clean anchor).
- Proposed three real-data checks on the `policy_block` panel (findings.md §7).

## 2026-05-20 — follow-up: the agnostic case

- User pushed back: the first simulation assumed the mechanism (only
  mayor-crossed channels relevant). Ex ante we do not know which office grants
  federal support; higher-tier alignment could matter independently of the
  mayor.
- Wrote `R/agnostic_office_relevance_sim.R`: builds all 7 alignment channels,
  three "worlds" (M·G-only, P-only, both), and shows (1) the saturated first
  stage recovers the true channel in every world; (2) the mayor-restricted AR
  set has only 23% power when the truth is P-only vs 76% for the P channel.
- Added findings.md §8: relevance vs validity distinction; the mayor-anchor is
  a *validity* argument, not a relevance claim; the saturated first stage is
  the agnostic relevance tool; recommended 3-stage procedure (saturated first
  stage -> per-channel placebo -> per-channel AR test); do not pre-exclude G/P
  before stage 1.

## 2026-05-20 — resolution: keep muni-relative weight + EC

- User raised reverting to a within-cell affiliated-normalized weight (sums to
  one across parties at the sector level -> EC unnecessary). Specified the
  stage-1 saturated first-stage regression and explained the BHJ "shares sum to
  one" exemption applies at the level of the regressor used (sector-level
  instruments are still incomplete-shares -> EC needed, or recenter shocks).
- External second opinion obtained; agreed. Within-cell revert rejected
  (discards mass; thin-cell instability; cosmetic gain only).
- Recorded as decision D32: keep muni-relative weight + per-channel EC;
  recentering = planned EC-free robustness.
- Added findings.md §9 (resolution). Wrote
  `journal/plans/2026-05-20_ec-adequacy-and-instrument-combinations.md`:
  Phase A EC adequacy audit, Phase B instrument-combinations agenda
  (build G/P/GP, saturated first stage, {M,G,MG} vs {MG}), Phase C recentering.

## 2026-05-20 — Phase A: EC adequacy audit (A1–A6)

- Audited the EC entering the AR test against the plan's six checks. Audited
  `ar_meeting_2026_05_13/R/` scripts 01–04; built objects re-verified with new
  scripts `R/A2_verify_ec.R`, `R/A5_ec_functional_form.R`,
  `R/A6_coverage_concentration.R`.
- A1 (definitional consistency): CONFIRMED. EC = Σ_p of the same muni-relative
  weight as Z; recomputed EC matches saved EC to 7e-16.
- A2 (EC vs slack): RESOLVED. Exploration pipeline carries the sum-of-shares EC
  and no `slack` column; Σ_j EC = 1 for all 264,168 muni-year-channel cells.
  The `slack ≡ 1−EC` object belongs to the within-cell intensity weight, not
  Variant A. The per-sector sum-of-shares EC is the BHJ §4.4-correct
  incomplete-shares control for the muni-relative weight. DOC FLAG:
  `ar_test_specification.tex` §2.3 and production scripts 32c/41 still describe
  / carry the intensity-weight `slack_frozen_mt`; routed to E4.1.
- A3 (regression structure): CONFIRMED. One EC per retained sector; hold-out
  `Serv` consistent for Z and EC; simplex constant absorbed by hold-out + FE.
- A4 (predeterminedness): CONFIRMED. Window strictly pre-t (T_Fc_hi − t ∈
  [−4,−1]); no contemporaneous leakage.
- A5 (functional-form sensitivity): STABLE. 32 AR regressions (4 channels × 4
  EC forms × 2 volume specs). AR verdict stable across linear/quad/bins for
  every channel; MG rejects under all three (F ∈ [3.63,3.99]); M/MP/MGP never
  reject. No Phase C escalation.
- A6 (coverage/concentration): median effective shocks ≈ 8; 27–28% of cells
  thin (≤5 owners) but thin muni-years carry only ~1.8% of GDP. Muni-relative
  denominator is thick — collapse is not a threat. Confirms D32 rationale.
- Verdict: EC is the BHJ-correct, predetermined incomplete-shares control,
  correctly built and entered; AR conclusion robust to EC functional form.
  D32 stands and is reinforced. findings.md §10 written.
- Quality self-assessment: 88/100 (exploration threshold 80). Code runs, no
  absolute paths, env/relative paths, set.seed once; deductions for the heavy
  owner-join memory footprint in A6 and reliance on the existing built panel
  rather than a fresh 01–03 rerun (justified: only a cosmetic label changed in
  00_helpers.R since the build).

## 2026-05-20 — Phases B and C implemented and run

- Edited 03_build_muni_ar_panel.R: Z retains all J sectors, EC retains J-1
  (plan Decision 1). Rebuilt weights/Z/EC/panel for policy_block (7 channels,
  J=4) and policy_block_size_bin (J=12).
- New scripts: B2 (composition first stage), B3 (volume first stage),
  B4 (channel routing), B5 (advisor comparison), B6 (three-volume AR table),
  C3 (12-group coverage audit), run_phase_bc.R (master).
- Headline results: policy_block routing comp={P} vol={G,MG};
  12-group routing fallback comp={M,MP,MG,MGP} vol={G}. Mayor-Governor is the
  only mayor-crossed channel that rejects (F=3.19, p=0.012 at policy_block),
  stable across no-Vol / Vol-control / Vol-instrumented. {M,G,MG} stacked
  sharper than {MG} alone. 12-group thin cells 64.8% but only 9.3% of GDP.
- All .tex outputs are bare tabular (INV-13). Quality self-assessment 86/100.
