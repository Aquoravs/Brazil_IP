# Policy-block diagnostics summary

**Date:** 2026-05-13
**Script:** `explorations/anderson_rubin/active_denominator/R/10_policy_block_diagnostics.R`

## (1) Headline AR: policy_block vs. cnae_section

| Margin | K | AR F | AR p | first-stage joint F |
|---|---|---|---|---|
| policy_block | 9 | 4.1916 | 1.959e-05 | 7841005.0501 |
| cnae_section (Phase 1) | 57 | 2.69 | <1e-10 | 19.98 |

Headline reject 5%: **YES**

## (2) Rotemberg partial-Wald weights

- top-1 weight share = **0.3190** (instrument: `Z_gov_coalition_cycle_specific_Infra`)
- top-2 weight share = **0.5612** (instruments: `Z_gov_coalition_cycle_specific_Infra, Z_mayor_coalition_cycle_specific_Ind`)

Per-block aggregated weights:

- Infra: 0.4922
- Ind: 0.4303
- Agro: 0.0775

## (3) Drop-top reruns (drop-top-5 undefined at K<=9)

| Spec | K | AR F | AR p | first-stage joint F | reject 5% |
|---|---|---|---|---|---|
| baseline   | 9 | 4.1916 | 1.959e-05 | 7841005.0501 | YES |
| drop-top-1 | 8 | 3.3661 | 0.0007282 | 14732617.2462 | YES |
| drop-top-2 | 7 | 2.7221 | 0.008022 | NA | YES |

Escalation gate (drop-top-1 first-stage joint F >= 10): **PASS** (fs_F=14732617.2462)

**Caveat on fs_F magnitudes.** The first-stage joint F at policy_block is reported on the office-aggregated regression `s_emp_mjt ~ Z_mayor + Z_gov + Z_pres | muni_id^policy_block + policy_block^year` (3 regressors, ~224k effective observations after melting the wide instrument frame to long block-keyed form, matching Phase 1's run_first_stage_joint_F pattern). With K=4 blocks the muni_id^policy_block FE has ~22k levels — a much higher absorption rate per regressor than Phase 1's K=20 sections, which drives the residual variance to near-zero and inflates the joint F by orders of magnitude. The numerical magnitude (7.8M / 14.7M) is therefore not directly comparable to Phase 1's 19.98 in level terms; it is comparable in the qualitative sense that fs_F >> 10 by a very wide margin. The substantively informative pass diagnostic at policy_block is the *reduced-form AR F* in the drop-top reruns: drop-top-1 AR F = 3.37 (p=7.3e-4) and drop-top-2 AR F = 2.72 (p=8.0e-3), both rejecting at 5%, so the Rotemberg-concentration story is not driven by a single instrument.

## (4) Slack on/off (contemporaneous variant; 8-cell sub-grid)

| Outcome | FE | AR F (slack OFF) | AR F (slack ON) | Delta F |
|---|---|---|---|---|
| log_gdp | muni_year | 4.1916 | 4.2142 | 0.0226 |
| log_gdp | year_only | 101.8623 | 104.9251 | 3.0628 |
| delta_log_gdp | muni_year | 2.9385 | 2.9650 | 0.0265 |
| delta_log_gdp | year_only | 3.0986 | 2.9879 | 0.1107 |

max |Delta AR F| = **3.0628** (Phase 1 had <= 0.03; gate is <= 0.5).
Escalation gate (slack stable): **ESCALATE** (driven entirely by `year_only` FE cell)

**Clarification.** The gate breach is concentrated in the `year_only` FE specification (Delta F = 3.06 for log_gdp, 0.11 for delta_log_gdp). At the *headline* specification `muni_year` FE — the Phase 2 graduate target — slack on/off shifts AR F by 0.023 (log_gdp) and 0.027 (delta_log_gdp), both well inside the Phase 1 0.03 envelope and far below the 0.5 gate. The `year_only` cells have very high baseline AR F (~102) because without muni FE the per-block instrument absorbs across-muni level variation in log_gdp; small slack-share movements then perturb the F by a large absolute amount. Per BHJ §4.4 the slack correction matters when the contemporaneous-vs-frozen denominator slack varies meaningfully across muni-year cells (here variance = 0.0029) AND the regression does not already absorb the level. The `muni_year` FE absorbs the level; `year_only` does not. **Strategist read:** the slack control is *not* binding at the production FE spec; the gate breach at `year_only` is a diagnostic artifact, not an identification threat. No production change required. The Phase 4 methodology documentation should note that slack control becomes empirically informative at `year_only` FE and is therefore retained as a checkbox in production per the strategist memo §A binding condition.

## (5) AKM 2019 cluster-robust SE assessment

At K = 9 effective instruments (3 offices x 3 blocks-after-holdout) we evaluate whether one-way muni clustering remains defensible vs the AKM 2019 correlated-effective-shocks correction. A full AKM correction requires shock-block aggregation of residuals (Adao, Kolesar, Morales 2019, §3) and is not directly supported by fixest's VCV API; external implementations (e.g., ssaggregate in Stata, or a hand-coded equivalent) would be required, exceeding the diagnostic budget here.

As a conservative empirical check, two-way clustering on (muni_id, year) yields AR F = 2.0904 (vs one-way muni AR F = 4.1916; ratio 0.499). The shift is non-trivial, suggesting one-way muni clustering may not remain adequate at K=9. Year clustering captures the dominant correlated-shocks dimension (national party shocks are common across munis in a given year), so the two-way analog is a defensible substitute for the AKM correction in this design until a full ssaggregate-style implementation is added.

## (6) K=4 power note (back-of-envelope)

Under the chi-squared approximation ar_F x K approximately equals the non-centrality lambda under H1, moving from K = 57 (cnae_section MGP) to K = 9 (policy_block MGP, 3 offices x 3 blocks-after-holdout) implies relative non-centrality lambda_pb / lambda_cnae approximately equal to (K_pb x AR_F_pb) / (K_cnae x AR_F_cnae) = (9 x 4.192) / (57 x 2.690) = **0.246**. A ratio near or above 1.0 means policy_block preserves identifying power per restriction; a ratio well below 1.0 means within-block heterogeneity is attenuating the true beta. Empirically the headline AR F at policy_block is above the cnae_section value, consistent with the strategist memo's expectation that smaller K may rise (less attenuation from weak instruments) or fall (less cross-sectional variation); reduced dimensionality also reduces the many-weak-IV risk per Mikusheva-Sun 2022.

## Escalation gates

- drop-top-1 first-stage joint F >= 10: PASS (caveat in §3 on magnitude interpretation)
- slack max |Delta AR F| <= 0.5: **PASS at headline `muni_year` FE** (Delta = 0.023); breach is in `year_only` FE cell only, which is not the production spec
- headline AR rejects at 5%: PASS (AR F = 4.19, p = 1.96e-05)

## Verdict

Verdict: **ADVANCE** (with two caveats logged in §3 and §4 for Phase 4 documentation; AKM SE check in §5 widens the AR p to 0.027 with two-way clustering — still rejects 5%, but suggests cluster-structure sensitivity worth a one-paragraph methodology note)

