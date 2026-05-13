# Drop-Violator AR Test (B1.6 diagnostic e)

**Date:** 2026-05-12 19:13
**Headline cell:** contemporaneous variant, log_gdp, muni+year FE, MGP flavor, cluster on muni_id

## Scenarios

- **baseline** (B1.3 R2 replication): K = 57 (mayor + gov + pres x 19 sections, drop holdout U)
- **drop_PresE**: drop `Z_pres_coalition_cycle_specific_E`
- **drop_PresE_PresP**: drop `Z_pres_coalition_cycle_specific_E`, `Z_pres_coalition_cycle_specific_P`
- **drop_AllPres**: drop all 19 `Z_pres_*` columns

## Headline results (contemporaneous + log_gdp + muni+year FE)

| Scenario | K | AR F | AR p | fs_F | rejects 5% | region |
|---|---|---|---|---|---|---|
| baseline | 57 | 2.692 | 9.13e-11 | 19.98 | TRUE | bounded_excludes_zero |
| drop_PresE | 56 | 2.574 | 1.076e-09 | 45.89 | TRUE | bounded_excludes_zero |
| drop_PresE_PresP | 55 | 2.416 | 2.22e-08 | 53.84 | TRUE | bounded_excludes_zero |
| drop_AllPres | 38 | 2.153 | 4.818e-05 | 1.091 | TRUE | bounded_excludes_zero |

## Overall verdict: **WEAK PASS**

Pass framing:
- Strong pass -- drop_AllPres rejects at 5% with fs_F >= 10
- Weak pass -- drop_PresE_PresP rejects at 5% with fs_F >= 10
- Fail -- even drop_PresE collapses the rejection

Full grid (3 scenarios + baseline x 3 variants x 2 outcomes x 2 FE specs)
saved to `ar_drop_violators.csv`.
