# Issues and Design Decisions

## Issue 1: Instrument Timing — Spreading Shocks Across Electoral Terms

**Problem**: Alignment shocks (`dalign_*`) are only non-zero at inauguration years (mayors: 2005, 2009, 2013, 2017; gov/pres: 2003, 2007, 2011, 2015). This means instruments Z are zero for ~70% of the panel, wasting statistical power and misaligning with the annual outcome (GDP).

**Decision**: Spread each inauguration-year shock across the entire 4-year term of the elected official. The political alignment persists until the next election, so the alignment "treatment" is constant within a term.

- Mayor terms: 2005-2008, 2009-2012, 2013-2016, 2017-2020
- Gov/pres terms: 2003-2006, 2007-2007:2010, 2011-2014, 2015-2018

## Issue 2: Exclusion Restriction — Political Alignment and Non-BNDES Channels

**Problem**: Political alignment affects municipal GDP through channels beyond BNDES credit (federal/state transfers, procurement contracts, regulatory ease). If Z predicts GDP through these channels, the exclusion restriction fails.

**Required test**: Placebo regression showing Z predicts BNDES lending but NOT other transfers.

- Download municipal transfer/revenue data from basedosdados (`br_me_siconfi.municipio_receitas_orcamentarias`) or FINBRA.
- Regress `log(transfers_pc)` on Z instruments. Null of zero effect supports exclusion restriction.
- If Z does predict transfers, need a control function approach or argue the BNDES channel dominates.

**Status**: Transfer data download added to script 41 (optional, with graceful fallback).

## Issue 3: Shares Adding-Up Constraint (Simplex)

**Problem**: Within each muni-year, sector shares sum to 1: `sum_j s_mjt = 1`. Therefore `sum_j delta_s_mjt = 0`. Including all J sector-level endogenous regressors in a vector 2SLS causes perfect multicollinearity.

**Decision**: Drop one reference sector j0 (the sector with the largest average share). The coefficient beta_j is then interpreted as: "reallocating 1pp of BNDES from sector j0 toward sector j raises GDP by beta_j."

**Implementation**: Determine j0 empirically in script 41 from `mean(s_mjt)` by sector. Drop j0 from the wide-format pivot. The choice of j0 is arbitrary for the joint test (null: all beta_j = 0), but affects individual coefficient interpretation.

**Robustness**: Try alternative j0 choices; verify joint test is invariant.

## Issue 4: Baseline Year Selection

**Problem**: The first electoral cycle (2003 gov/pres) uses 2002 baseline weights — the very first year of RAIS data. These weights may be noisy or unrepresentative.

**Options**:
1. **Cycle-specific baselines** (current primary): Use the last year before each inauguration as the baseline. Pro: most relevant. Con: potential endogeneity if firms anticipate elections.
2. **2002-fixed baselines** (current robustness): Use 2002 for all cycles. Pro: clearly predetermined. Con: may not reflect evolving industrial structure.
3. **t-2 baselines**: Use two years before each inauguration to mitigate anticipation effects.

**Decision**: Use cycle-specific as primary, 2002-fixed as robustness (already implemented in scripts 33-34). Consider dropping the first cycle (2003-2006) as a robustness check since 2002 weights are shared between specifications.

## Issue 5: Baseline Exposure Weights

**Situation**: The draft suggests using the pre-election employment share of party p’s affiliated firms in sector j of municipality m as baseline exposure weights. However, it remains to determine how to assign the employment of firms with owners affiliated to different parties.

```
w_mjp = (employment in firms owned by party-p affiliates in sector j, muni m weighted by the share of owners affiliated to party-p out of all owners affiliated to any party) / (total employment in sector j, muni m)
```

The current scripts use affiliated **owner counts** divided by **municipality-level total** (N_m_0 or F_m_0).

**TODO**: Modify script 31 to offer employment-weighted within-sector party shares as an alternative. This requires RAIS employment data at the firm×year level merged with owner affiliation and party data.

## Issue 6: Fixed Effects in First Stage

**Situation**: The draft requires `muni_sector + muni_year` (alpha_mj + alpha_mt) to absorb the aggregate alignment shock at the municipality-year level. With only year FE, the aggregate political alignment at the municipality level effect contaminates identification. With muni×year FE, all identification comes from cross-sector variation in exposure weights (w_mjp).

**Concern**: muni×year FE absorbs a large number of degrees of freedom. With ~5,500 munis × 16 years = ~88,000 FE on top of ~5,500 × 20 sectors = ~110,000 muni×sector FE. This is feasible with fixest but may reduce precision.

## Issue 7: Balanced Panel Construction

### Problem with naïve construction
Only muni-sector-years with positive BNDES loans appeared in the panel.

**Before (BNDES-only)**:
- 152K observations, 8.6% fill rate
- Median muni-sector: 3 obs / 16 years
- Lags computed over consecutive loan years, not calendar years
- Missing the extensive margin entirely

**After (RAIS-expanded)**:
- 1,464K observations (10×)
- Perfectly balanced (16/16 years)
- s_mjt = 0 for sectors without loans
- Lags over consecutive calendar years
- Captures entry/exit from BNDES

**Sector universe**: all CNAE sections with ≥1 RAIS firm in municipality r (mean: 16.4 sectors/muni).

**Result**: Shares properly sum to 1, Δs sums to 0 within muni-year.

### Why it mattered for first-stage results

| | Old panel (BNDES-only) | Expanded (RAIS skeleton) |
|---|---|---|
| Observations | 100,248 | 1,372,575 |
| Muni-sector pairs | 10,859 | 91,505 |
| Mayor coalition, muni×year FE: Coeff | 0.158* | 0.028*** |
| Mayor coalition, muni×year FE: F-stat | 3.0 | **12.4** |
| Combined (M+G+P), muni×year FE: Joint F | 1.04 | **9.4** |
| Combined (M+G+P), muni×year FE: p-value | 0.374 | 3.3×10⁻⁶ |

- Old panel had weak instruments (F ≈ 1–3) with muni×year FE
- The fix: including sectors with s_mjt = 0 (no loans)
- These zeros carry information: the instrument predicts *which sectors don't get loans*
- Also fixed: lags were computed over non-consecutive years

## Issue 8: Sector Mismatch between BNDES and RAIS data

**Concern**: BNDES loan records classify each disbursement by the sector (CNAE) of the financed project, which may differ from the sector under which the borrowing firm is officially registered in RAIS. Moreover, the same firm can borrow across multiple project sectors, creating a one-to-many mapping from firms to loan sectors. This raises a question for constructing both the exposure weights (w_rjp) and the lending shares (s_mjt): should a firm's sector be defined by its RAIS registration, by its BNDES loan classification, or by both sources?

**Decision**: Each firm is assigned to its modal CNAE section as recorded in RAIS (government administrative data), and this single sector assignment is used consistently for both the exposure weights and the credit shares across time. The rationale is twofold. First, the identification strategy operates through political connections at the firm level — a party-affiliated owner channels BNDES credit toward their firm, not toward a specific project sector. Assigning the firm to its RAIS sector ensures that the exposure weights (which measure how much of a sector's employment is linked to each party) align with the channel through which political influence operates. Second, using a single consistent sector definition avoids double-counting loans across sectors when a firm borrows for projects in multiple CNAE categories, preserving the adding-up constraint that ∑_j s_mjt = 1.

**Imputation for firms with missing sector**: The CNAE imputation cascade (owner affiliation CNAE → within-RAIS modal section → Receita Federal lookup) resolves the ~10% of firms lacking codes, and 99.6% of firm-years map to a unique CNAE section, making modal assignment largely redundant for the vast majority of observations.

## Issue 9: Is ln(BNDES_mt) a "Bad Control" in the Second-Stage?

**Problem**: The instrument shifts sector composition through political alignment. But political alignment also plausibly shifts total BNDES volume to the municipality (aligned municipalities get more lending overall, not just differently allocated lending across sectors). If the instrument affects both composition (Δs) and scale (BNDES_mt), then conditioning on total BNDES in the second stage conditions on a post-treatment variable—a mediator through which alignment affects GDP.

Suppose alignment causes municipality m to get both (a) more total BNDES and (b) a tilt toward politically connected sectors. By controlling for total BNDES, you block channel (a) and attribute everything to (b). But if alignment → total BNDES → GDP is a real causal pathway, conditioning on total BNDES introduces selection bias in the β_j estimates.

**Decision**: Prefer especification without scale control or with instrumented control.

**Rationale**: Municipality FE (δ_m) absorbs permanent differences in BNDES scale, and year FE (δ_t) absorbs aggregate trends. The remaining variation in total BNDES that isn't captured by these FEs is likely small—and to the extent it correlates with your instruments, controlling for it introduces bias.
