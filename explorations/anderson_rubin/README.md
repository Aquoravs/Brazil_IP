# Anderson-Rubin Baseline Exploration

## Goal

Pooled Anderson-Rubin test of H0: BNDES sectoral reallocation has no
first-order GDP effect, using mayor alignment shift-share instruments at
`policy_block` granularity (4 sectors: Agro, Ind, Infra, Serv). K = 4 in the
primary spec; tier ascent (K = 8 / K = 12) is the R3 sensitivity ladder. Full
identification strategy in `docs/strategy/ar_test_strategy.md`.

## Status

IN PROGRESS (started 2026-04-29)

## Primary Specification

USER-MANDATED 2026-04-29:

- **Outcome:** `log_gdp` (log total municipal GDP; NOT `log_gdp_pc` — that is
  demoted to R4 sensitivity)
- **Instruments (K = 4):**
  `ar_Z_mayor_coalition_cycle_specific_Agro`,
  `ar_Z_mayor_coalition_cycle_specific_Ind`,
  `ar_Z_mayor_coalition_cycle_specific_Infra`,
  `ar_Z_mayor_coalition_cycle_specific_Serv`
- **Controls:** NONE (no muni FE, no year FE, no covariates)
- **Variance estimator:** cluster-robust, clustered at `muni_id`
- **Weight infix:** owner-count (default)

Controls ladder (sensitivities, not the primary):

| Label | Contents |
|-------|----------|
| C1 | Muni FE + year FE only |
| C2 | FE + R0a muni-total EC (`ec_total_mayor_cycle_specific`) |
| C3 | FE + R0b sector-specific EC (four `ar_exposure_control_mayor_cycle_specific_<sector>` columns) |
| C4 | FE + log total employment (advisory; bad-control risk per strategy memo §6 / §10) |

## Hypotheses to Test

1. AR rejects H0 under the K = 4 no-controls primary spec (finite F-stat with
   p < 0.10).
2. The result survives the controls ladder: C1 (FE only), C2 (FE + muni-total
   EC), C3 (FE + sector-specific EC) all continue to reject (or at minimum
   fail to strongly accept H0).
3. The result survives R2: 2002-fixed baseline weights deliver a comparable
   F-stat to the cycle-specific baseline.
4. Tier ascent (R3): K = 8 (mayor + gov) and K = 12 (mayor + gov + pres)
   sharpen or sustain the result; power does not collapse under K = 12 / C3
   (if it does, interpret as collinearity, not confound — see strategy memo
   §3.1 and plan Open Question 5).
5. F1 transfers placebo: primary instruments do NOT reject H0 when the outcome
   is `log_transfers_pc`; failure would indicate instruments predict federal
   transfers directly, violating the exclusion restriction.
6. F2 lead-instruments placebo: instruments shifted +4 years do NOT reject H0;
   future alignment should not predict current GDP under the null.
7. F7 pre-period balance: primary-cycle Z values do NOT reject H0 for
   pre-2005 municipal averages of `log_gdp_pc`, `log(population)`,
   `log(total_employment)`; rejection would indicate pre-existing trends
   correlated with first-cycle alignment.

## Success Criteria

- `ar_baseline.R` runs to completion without errors on rebuilt Panel B
  (`muni_panel_for_regs_policy_block.qs2`).
- Primary K = 4 no-controls AR row in `output/ar_results.csv` has finite,
  non-missing `f_stat`, `p_value`, `df1`, `df2`, `n_obs`, `n_clusters`.
- `output/ar_results.csv` has at least 12 spec rows.
- `output/ar_results.tex` is a bare `tabular` environment (no float wrapper,
  no `\caption{}`, no notes; booktabs rules only — INV-3, INV-13).
- `output/ar_grouped_state.csv`, `output/ar_grouped_quartile.csv`, and
  `output/ar_falsification.csv` are produced.
- R0a (muni-total EC) and R0b (sector-specific EC) rows present and
  non-null in `ar_results.csv`.
- At least one F1 / F2 / F7 row present in `ar_falsification.csv`.
- Quality score >= 80 against simplified-mode checklist (workflow.md §2).

## Findings

(Updated as work progresses)

## Timeline

- 2026-04-29: Plan approved; scaffolding created; Step 3 of implementation
  plan complete. Steps 4–7 (script writing, Panel B patch, run, verify)
  pending.
