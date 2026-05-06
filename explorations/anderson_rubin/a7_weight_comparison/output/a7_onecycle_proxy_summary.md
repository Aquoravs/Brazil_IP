# A7 Step 4 -- One-Cycle Proxy F-Stat Summary

Plan: `logs/plans/2026-05-05_a7-revised-weight-comparison.md`, Step 4.
Sample: 2002-2006 mayor cycle (treatment_year = 2005, term years 2005, 2006, 2007, 2008)
Outcome: `log_gdp` (matches `explorations/anderson_rubin/ar_baseline.R`).
Instruments per weight: 4 sector-decomposed Z columns (Agro, Ind, Infra, Serv).
Cluster: `muni_id` for `f_stat_kp`; HC-robust (no cluster) for `f_stat_cd`.
Sample size: 22247 muni-year obs across 5564 munis.

## F-stat metric clarification

In a reduced-form first-stage with no endogenous regressor, `f_stat_cd` and `f_stat_kp` collapse to robust / cluster-robust joint Wald F-tests on the K=4 sectoral instruments. The naming preserves the plan's vocabulary (`Cragg-Donald F` and `Kleibergen-Paap rk Wald F`) while the construction is the AR-test joint Wald F.

## Spec deviation (documented)

Plan §Step 4 lists C1_FE = `muni FE + year FE`. In the one-cycle proxy (treatment_year=2005, term spread to 2005-2008), every `Z_<weight>` is time-INVARIANT within muni; adding muni FE absorbs all variation -> perfect collinearity. C1_FE here uses YEAR FE only (the maximal identifiable FE set in a one-cycle window). The multi-cycle AR baseline (ar_baseline.R) does include muni FE, since Z varies across cycles within muni in the full panel.

## Ranking under C1_FE (production-relevant spec)

```
 1. owners_muni_univ                 [C            , c=1]  F_kp=59.56  F_cd=236.35
 2. owners_muni_match                [B            , c=1]  F_kp=59.56  F_cd=236.35
 3. binary_muni_univ                 [C            , c=4]  F_kp=47.54  F_cd=188.84
 4. firm_empshare_floor_match        [B            , c=2]  F_kp=45.91  F_cd=181.96
 5. firm_muni_univ                   [C            , c=3]  F_kp=33.35  F_cd=132.17
 6. emp_muni_univ                    [C_clustermate, c=2]  F_kp=18.76  F_cd=74.57
 7. binary_empshare_floor            [C            , c=5]  F_kp=13.81  F_cd=54.90
 8. firm_empshare_floor              [C            , c=2]  F_kp=13.38  F_cd=53.19
```

## Ranking under no_controls

```
 1. owners_muni_univ                 [C            , c=1]  F_kp=59.57  F_cd=234.07
 2. owners_muni_match                [B            , c=1]  F_kp=59.57  F_cd=234.07
 3. binary_muni_univ                 [C            , c=4]  F_kp=47.54  F_cd=187.13
 4. firm_empshare_floor_match        [B            , c=2]  F_kp=45.92  F_cd=179.81
 5. firm_muni_univ                   [C            , c=3]  F_kp=33.36  F_cd=130.76
 6. emp_muni_univ                    [C_clustermate, c=2]  F_kp=18.76  F_cd=74.15
 7. binary_empshare_floor            [C            , c=5]  F_kp=13.81  F_cd=54.68
 8. firm_empshare_floor              [C            , c=2]  F_kp=13.38  F_cd=52.88
```

## Ranking under C2_FE_R0a

```
 1. owners_muni_univ                 [C            , c=1]  F_kp=50.30  F_cd=199.36
 2. owners_muni_match                [B            , c=1]  F_kp=50.30  F_cd=199.36
 3. binary_muni_univ                 [C            , c=4]  F_kp=44.81  F_cd=177.77
 4. firm_empshare_floor_match        [B            , c=2]  F_kp=41.22  F_cd=163.02
 5. emp_muni_univ                    [C_clustermate, c=2]  F_kp=31.47  F_cd=125.14
 6. firm_empshare_floor              [C            , c=2]  F_kp=26.99  F_cd=107.19
 7. firm_muni_univ                   [C            , c=3]  F_kp=19.40  F_cd=76.89
 8. binary_empshare_floor            [C            , c=5]  F_kp=15.40  F_cd=61.36
```

## Cluster 1 -- Tier B vs Tier C comparison (under C1_FE)

- `owners_muni_univ` (C, c=1): F_kp = 59.558, F_cd = 236.355
- `owners_muni_match` (B, c=1): F_kp = 59.558, F_cd = 236.355

## Cluster 2 -- Tier B vs Tier C (with optional clustermate, under C1_FE)

- `firm_empshare_floor` (C, c=2): F_kp = 13.383, F_cd = 53.189
- `emp_muni_univ` (C_clustermate, c=2): F_kp = 18.757, F_cd = 74.575
- `firm_empshare_floor_match` (B, c=2): F_kp = 45.912, F_cd = 181.959

## Flags

- No `f_stat_kp` < 1 cases (all specs pass minimum sanity).

- No F_kp < 5 cases.

## Substantive finding: `w_owners_muni_univ` is mathematically identical to `w_owners_muni_match`

Diagnostic check post-run: Pearson correlation between `w_owners_muni_univ`
(Tier C) and `w_owners_muni_match` (Tier B) at (muni, block, party,
treatment_year=2005) is exactly 1; ratio is exactly 1 in every cell. The
muni-summed Z columns are also identical (max abs diff = 0).

Reason: For owner-count weights, Tier C's denominator
`L_mB_univ = sum(owner_count)` over ALL RAIS firms reduces to
`sum(total_owners)` over MATCHED firms only — because by Step 1's construction
(line 270 of `01_build_weights.R`), unmatched firms contribute
`owner_count = 0` to the denominator. This makes Tier C's
"universe-denominator" identical to Tier B's "matched-only-denominator" for
the owner family. The firm-scope dimension is therefore non-existent for
the owner numerator/denominator combination.

Implication: the Tier B build for Cluster 1 (`w_owners_muni_match`) does NOT
disentangle firm scope from denominator scope for the owner-count family.
The strategist-critic's flag for Cluster 1 expansion was based on the 0.75
correlation between `w_owners_muni_univ` and the Tier A anchor
`w_owners_sec_match`, where the open question is **denominator scope**
(sector vs. muni), not firm scope. Cluster 1 expansion is therefore
not informative as run; a true Cluster 1 disentanglement requires building
Tier A `w_owners_sec_match` AND/OR Tier B `w_emp_muni_match` (a different
firm-scope test using the employment-weighted variant where the firm-scope
dimension is non-degenerate).

The Cluster 2 Tier B (`w_firm_empshare_floor_match`) is non-degenerate and
DOES disentangle firm scope. See Cluster 2 comparison above: Tier B beats
Tier C and the cluster-mate by a wide margin (45.91 vs. 13.38 vs. 18.76).

## Outputs

- `output/a7_onecycle_proxy_fstats.csv` - main F-stat table (24 rows).
- `output/a7_tier_b_weights_panel.qs2` - Tier B weights for clusters 1, 2.
- `output/a7_tier_b_instruments_panel.qs2` - corresponding muni-level Z.
- `output/a7_onecycle_proxy_summary.md` - this narrative.

