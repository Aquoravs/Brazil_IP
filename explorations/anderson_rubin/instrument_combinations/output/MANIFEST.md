# Output Manifest — AR Test Instrument Combinations

| Artifact | Produced by | Use status | Description |
|---|---|---|---|
| `ar_combination_power.csv` | `R/ar_instrument_combination_sim.R` | diagnostic only | AR-test rejection rate by instrument set across a β grid (β=0 row is size), governor exclusion holding. |
| `ar_combination_size_distortion.csv` | `R/ar_instrument_combination_sim.R` | diagnostic only | AR-test rejection rate (β=0, false rejections) by instrument set and per channel, across a governor exclusion-violation grid. |
| `saturated_first_stage.csv` | `R/agnostic_office_relevance_sim.R` | diagnostic only | Coefficients and t-stats from the saturated first stage (composition on all 7 channels) in three "worlds"; shows the agnostic recovery of the true channel. |
| `agnostic_ar_power.csv` | `R/agnostic_office_relevance_sim.R` | diagnostic only | AR-test rejection rate by instrument set (mayor-restricted, saturated, per channel) across three worlds; shows the cost of imposing the wrong restriction. |
| `A2_ec_verification.txt` | `R/A2_verify_ec.R` | audit evidence (real data) | Phase A A1/A2/A4: EC = Σ_p w̃ recheck, no-slack-column check, Σ_j EC = 1 check, predeterminedness check. |
| `A5_ec_functional_form.csv` | `R/A5_ec_functional_form.R` | audit evidence (real data) | Phase A A5: AR F and p for 4 channels × 4 EC forms (none/linear/quad/bins) × 2 volume specs at `policy_block`. |
| `A5_ec_functional_form_summary.txt` | `R/A5_ec_functional_form.R` | audit evidence (real data) | Phase A A5: per-channel stability verdict — AR conclusion stable across EC functional forms. |
| `A6_effective_shocks.csv` | `R/A6_coverage_concentration.R` | audit evidence (real data) | Phase A A6: effective number of shocks (inverse-HHI of muni-relative weights) per channel. |
| `A6_cell_owner_counts.csv` | `R/A6_coverage_concentration.R` | audit evidence (real data) | Phase A A6: distribution of cell affiliated-owner counts L_{jm,t} per channel; thin-cell share. |
| `A6_gdp_mass_thin.csv` | `R/A6_coverage_concentration.R` | audit evidence (real data) | Phase A A6: share of municipal GDP in thin-identified muni-years per channel. |
| `A6_coverage_concentration.txt` | `R/A6_coverage_concentration.R` | audit evidence (real data) | Phase A A6: consolidated coverage / concentration report. |

The `ar_combination_*` and `*agnostic*`/`saturated_*` outputs are illustrative
Monte Carlo results. The `A2_`/`A5_`/`A6_` outputs are real-data Phase A EC
adequacy audit evidence. See `../findings.md` (§10) for interpretation.
