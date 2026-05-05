# Falsification Tests: Anderson-Rubin Test

## Tests That Should NOT Reject H0

| # | Test | LHS | RHS | Expected under validity | Data source | Priority |
|---|------|-----|-----|------------------------|-------------|----------|
| F1 | Transfers placebo | log(transfers_pc_mt) | Z^mayor_jmt (4 sectors) | F not significant; instruments do not predict federal transfers | `data/processed/transfers_ibge.qs2` (96.3% match) | High -- directly tests exclusion |
| F2 | Lead instruments (pre-trends) | log(GDP_pc_mt) | Z^mayor_j,m,t+4 (shifted forward one mayor cycle) | Not significant; future alignment does not predict current GDP | Construct from existing Z by time-shifting | High -- core validity check |
| F3 | Lagged GDP as outcome | log(GDP_pc_m,t-1) or log(GDP_pc_m,t-2) | Z^mayor_jmt | Not significant; current instruments should not predict past GDP | Lag within Panel B | High |
| F4 | Permuted sector labels | log(GDP_pc_mt) | Z with sector labels randomly permuted within municipality | Not significant; permuted instruments are noise | Permutation within-m | Medium |
| F5 | Municipal procurement | log(procurement_mt) | Z^mayor_jmt | Not significant; instruments should not predict procurement | Not yet sourced; pending | Medium -- contingent on data |
| F6 | Randomization inference | log(GDP_pc_mt) | Z with alignment permuted across munis within year | Observed AR stat in tail of permutation distribution only if real effect exists | B = 1000 permutations | Medium |
| F7 | Pre-period balance test | Pre-2005 municipality averages (log GDP_pc, log pop, sectoral employment shares, BNDES/cap) | Cross-sectional instrument values (first-cycle Z) | Not significant; baseline characteristics do not differ systematically by instrument magnitude | Compute from Panel B pre-2005 averages + first-cycle Z | High -- core exogeneity check |
| F8 | Non-BNDES-intensive sectors | log(GDP_pc_mt) | Z^mayor_jmt for sectors that receive minimal BNDES | Not significant if BNDES is the channel (no credit to transmit) | Identify sectors with near-zero BNDES take-up | Low |

## Tests That SHOULD Reject H0 (Positive Controls)

| # | Test | LHS | RHS | Expected if mechanism works | Notes |
|---|------|-----|-----|---------------------------|-------|
| P1 | BNDES share as LHS | s_jmt (sector BNDES share) | Z^mayor_jmt | Significant -- this IS the first stage | Already done in script 53; confirms instrument relevance |
| P2 | Employment as LHS | log(employment_mt) | Z^mayor_jmt | Likely significant (F up to 265 at firm level) | Validates that alignment affects real economic activity |
| P3 | Firm-level extensive margin | 1(BNDES_fmt > 0) | FA^ell_fmt | Significant (F up to 103) | Already done in script 51; micro-level validation |

## Interpretation Framework

**If F1 rejects (transfers):** Alignment affects GDP through transfers, not just BNDES. The AR test is still valid as a test of gamma = 0 in the reduced form, but the interpretation shifts: instruments capture the overall GDP effect of political alignment, not the BNDES-specific channel. The paper would need to be reframed or the transfer channel would need to be controlled for (while acknowledging bad-control concerns).

**If F2 rejects (lead instruments):** Pre-trends concern. Political parties may be gaining power in municipalities that are already on different GDP trajectories. This undermines the exogeneity assumption. Possible remedies: (a) control for pre-treatment GDP trends, (b) use only sudden party changes (close elections), (c) difference-in-differences within a narrower window around elections.

**If F3 rejects (lagged GDP):** Similar to F2 -- suggests reverse causality or confounding trends. The instruments are endogenous to the GDP process.

**If F6 permutation p-value is small:** Strengthens the result by providing distribution-free evidence. The observed AR statistic is unlikely under the sharp null of no effect, without relying on asymptotic theory.

**If F7 rejects (pre-period balance):** Municipalities that receive larger instrument shocks (larger alignment changes interacted with larger baseline exposure) are systematically different in pre-treatment observables. This does not prove violation of exogeneity (conditional on FE, the relevant variation is within-municipality over time), but it raises concerns that the cross-sectional variation driving identification is confounded. Possible remedies: (a) include the pre-treatment characteristics as controls in the AR regression, (b) reweight municipalities to achieve balance, (c) restrict to a subsample where balance holds.

## Implementation Notes

- F1 requires merging `transfers_ibge.qs2` into Panel B. Check match rate and coverage.
- F2 requires care with the time shift: Z^mayor at t+4 is the instrument from the NEXT electoral cycle. This means using future alignment status, which is observed in the data but would not have been knowable at time t. The pre-election baseline for the future cycle must also be shifted.
- F4 (permuted sectors): Fix the seed. Permute sector labels within each municipality (not across municipalities). Run B = 500 permutations. Report the fraction of permutations where the AR F-statistic exceeds the observed one.
- F6 (randomization inference): Permute the alignment vector Align^ell_mpt across municipalities within each year t, keeping the baseline exposure w^ell_jmp,t fixed. Recompute Z^ell_jmt and re-run the AR regression. Repeat B = 1000 times.
- F7 (pre-period balance): Compute pre-2005 municipality averages of log GDP per capita, log population, employment share in each BNDES sector, and total BNDES per capita. Merge with first-cycle instrument values (2005 mayor cycle). Run cross-sectional OLS of each pre-treatment variable on the 4 sector instruments and report the joint F-test. Heteroskedasticity-robust SEs (HC2). No municipality FE (this is a cross-sectional test).
