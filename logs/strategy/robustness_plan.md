# Robustness Plan: Anderson-Rubin Test

## Tier 1: Must-Run (Main Text / Primary Appendix)

| # | Check | What changes | Why | Expected outcome |
|---|-------|-------------|-----|-----------------|
| R0 | Exposure controls (sector-specific) | Add EC^ell_Agro,mt, EC^ell_Ind,mt, EC^ell_Infra,mt, EC^ell_CS,mt to the regression | Borusyak-Hull-Jaravel (2022) and Goldsmith-Pinkham-Sorkin-Swift (2020) emphasize conditioning on exposure shares; captures overall political connectedness that may confound | AR F-statistic should remain qualitatively unchanged if the result is not driven by connectedness levels; if it changes substantially, flags an important confound |
| R1 | Changes instruments (dZ) | Replace Z^ell_jmt with dZ^ell_jmt | Tests whether the result depends on timing (term-spread vs. inauguration-only) | Lower power due to fewer non-zero obs; result should go in same direction |
| R2 | 2002-fixed baseline | Swap cycle-specific w^ell_jmp,t with 2002-fixed baseline | Rules out endogenous party sorting within electoral cycles | Weaker first stage (F up to 24 vs. 103) but cleaner exogeneity |
| R3 | Add governor tier | Expand K from 4 to 8 (mayor + governor) | Tests overidentification; adds state-level variation | More power if both tiers contribute; AR statistic may change |
| R4 | log(GDP) instead of log(GDP_pc) | Swap LHS | Avoids population denominator noise | Should be nearly identical with muni FE |
| R5 | Active-sector subsample | Restrict to munis with all 4 BNDES sectors having nonzero Z | Eliminates zero-instrument-column dilution | Smaller N; cleaner identification; compare AR p-value |
| R6 | Verify 2003 cycle exclusion | Confirm 2003 governor/president cycle is excluded | No pre-election baseline data before 2002 | Mechanical; verify no contamination |

## Tier 2: Should-Run (Appendix)

| # | Check | What changes | Why |
|---|-------|-------------|-----|
| R7 | Party-level alignment | Use party instead of coalition alignment | Coalition may be too broad; party is a sharper treatment |
| R8 | Sector-by-sector tests | 4 separate univariate regressions (one Z per regression) | Diagnoses which sectors drive the joint result; avoids joint-test power dilution |
| R9 | Control for total employment | Add log(total_employment_mt) | Absorbs scale effects; risk: bad control if employment responds to alignment |
| R10 | Single-municipality firms only | Restrict to is_multi_muni == 0 | Multi-muni firms (30% of employment) may blur municipality assignment |
| R11 | State-level clustering | Cluster SE at UF (27 states) instead of municipality | Accounts for spatial correlation across municipalities within states; caveat: only 27 clusters raises few-cluster concerns (Carter, Schnepel & Steigerwald 2017) |
| R12 | Grouped AR by state | 27 separate AR tests | Geographic heterogeneity: do some states drive the result? Report with BH adjustment or as distribution of F-statistics |
| R13 | Grouped AR by BNDES intensity | 4 AR tests by quartile of mean BNDES/cap | Tests whether effect concentrates among heavy BNDES recipients |
| R14 | Conley spatial HAC standard errors | Replace muni clustering with spatial HAC using distance-based kernel | Accounts for spatial correlation in GDP shocks across nearby municipalities without the few-cluster problem of state-level clustering; requires choosing a distance cutoff (e.g., 100km, 200km) |
| R15 | Binary baseline exposure | Use extensive-margin baseline (tilde{omega}) | Tests sensitivity to baseline definition |

## Tier 3: Stress Tests (Phase 4)

| # | Check | What changes | Why | Method |
|---|-------|-------------|-----|--------|
| R16 | FAR (Fractionally Resampled AR) | Allows local-to-zero violation of exclusion restriction | Stress-tests exact exogeneity assumption | Fractional resampling of instruments; conservative p-value |
| R17 | Cluster Jackknife AR | Jackknife entire municipalities | Serial correlation in 15-year panel may undermine cluster-robust SE | Leave-one-cluster-out AR statistic |
| R18 | RJAR with 21 CNAE sections | Ridge-regularized jackknife AR with K = 21 | Many-instrument distortion at high K | Mikusheva-Sun (2022) implementation |
| R19 | RJAR with 12 sector x size-bin categories | K = 12 instruments | Intermediate K between 4 and 21 | Same as R18 |
| R20 | Conditional subvector AR | Test one sector at a time while treating others as nuisance endogenous | Policy relevance of individual sectors | Requires conditioning on nuisance parameters |

## Implementation Priority

**Phase 1 (immediate):** R0--R6 alongside the primary specification. These are computationally trivial (same regression with different inputs). R0 (exposure control) is highest priority among robustness checks.

**Phase 2 (after baseline results):** R7--R15. Mostly subsample or re-specification exercises. R14 (Conley HAC) requires the `conleyreg` or `spdep` package in R.

**Phase 3--4 (after Phase 1--2 results stabilize):** R16--R20. These require custom implementations or specialized packages. RJAR requires coding or finding an existing implementation of Mikusheva-Sun (2022).
