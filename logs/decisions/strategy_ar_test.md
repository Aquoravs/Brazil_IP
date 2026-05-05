# Decision Record: Anderson-Rubin Test Strategy

**Date:** 2026-04-28
**Decision:** Use a pooled reduced-form Anderson-Rubin test as the primary test of whether politically driven BNDES sectoral reallocation affects municipal GDP.
**Score:** 97/100 (strategist-critic, round 2)

---

## Decision

Test H₀: β = 0 via a cluster-robust Wald F-test on the reduced-form regression:

```
log(GDP_pc_mt) = α_m + δ_t + Σ_j γ_j · Z^mayor_j,mt + ε_mt
```

with 4 BNDES macro-sector instruments (Agropecuária, Indústria, Infraestrutura, Comércio e Serviços), municipality FE + year FE, clustered at municipality level. The AR test is the joint Wald test on all γ_j.

## Alternatives Considered

| Alternative | Why Rejected |
|---|---|
| Municipality-by-municipality AR | T=16 with K=4 gives F(4,12) with ~15-20% power; year FE not estimable; effective df near zero due to electoral-cycle timing |
| 2SLS confidence intervals | First-stage F~6 for loan amounts (below Stock-Yogo); 2SLS Wald relies on strong-instrument asymptotics |
| First-differenced (ΔlogGDP on ΔZ) | Introduces MA(1) errors; municipality FE already absorb permanent component; unnecessary power loss |
| Grouped AR as primary | Heterogeneity diagnostic only; no group has a priori theoretical priority |

## Key Assumptions

1. **Exclusion restriction:** Political alignment instruments affect GDP only through BNDES-mediated channels (tested via transfers placebo F1, procurement F5)
2. **Exogeneity given FE:** Interaction of national party identity × pre-existing firm-party exposure is orthogonal to municipality GDP determinants conditional on muni FE + year FE (tested via lead instruments F2, lagged GDP F3, pre-period balance F7)
3. **No bad controls:** Primary spec includes only FE. Exposure control as R0 robustness.

## What Would Invalidate

- Transfers placebo (F1) rejecting — instruments predict GDP through transfers, not BNDES
- Lead instruments (F2) or lagged GDP (F3) significant — pre-trends or reverse causality
- AR result sensitive to exposure control (R0) — suggests level-of-connectedness confound rather than sectoral composition
- Employment channel (F up to 265) cannot be separated from BNDES channel — limits causal interpretation

## Implementation Blocker

`bndes_sector` (4 macros) is not yet wired through the pipeline to Panel B wide format. Must either add `--sector-var=bndes_sector` support to script 41 or build the wide columns in the exploration script.

## Deliverables

| File | Content |
|---|---|
| `logs/strategy/strategy_memo_ar_test.md` | Full strategy memo (revised round 2) |
| `logs/strategy/pseudo_code.md` | Implementation pseudo-code for `explorations/anderson_rubin/ar_baseline.R` |
| `logs/strategy/robustness_plan.md` | 19 robustness checks across 3 tiers |
| `logs/strategy/falsification_tests.md` | 7 falsification tests + 3 positive controls |
| `logs/strategy/strategy_memo_ar_test_review.md` | Strategist-critic review (rounds 1 and 2) |
