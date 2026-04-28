# Critical Review: First-Stage Results

## Executive Summary

The first stage shows a meaningful mayor alignment effect on sector-level BNDES reallocation, but the current set of results has several issues that need to be addressed before publication. This review is organized around four questions, followed by an overall assessment.

---

## 1. Exposure Control: What Does It Represent and Is It Correct?

**The flagged issue is real and significant.**

Tracing the construction:

```
exposure_control_mjt = Sigma_p (L_rjp,0 / D_r,0)
```

This is the **total share of muni m's owners/firms in sector j that are affiliated with any party**, computed from baseline-year data. It measures how "politically connected" sector j is in municipality m.

**Variation structure with cycle-specific baselines:**

| Dimension | Varies? | Why? |
|-----------|---------|------|
| Across sectors (j) | Yes | Different sectors have different party penetration |
| Across municipalities (m) | Yes | Different political landscapes |
| Across years (t) | **Very limited** | Only changes at electoral cycle boundaries |

Within a 4-year electoral term, the cycle-specific baseline weights are constant. The only time variation comes from:
- The transition between overlapping mayor and gov/pres terms (staggered by 2 years)
- The summing across tiers in `spread_instruments()` (script 34, line 300-301)

**Problem with muni x sector FE:** With `muni_id^sector_group` FE absorbing the permanent (muni, sector) component, the remaining variation in `exposure_control` is only the cycle-to-cycle change in baseline weights. With ~4 cycles across 15 years, this is at most 3-4 distinct values per cell -- extremely limited residual variation after FE absorption.

**Problem with 2002-fixed baselines:** Here, `exposure_control` is nearly constant at (muni, sector) and would be almost entirely absorbed by muni x sector FE. The only residual variation is the mechanical overlap pattern of mayor/gov/pres terms across years.

**What the control is meant to absorb:** The concern motivating it (Goldsmith-Pinkham, Sorkin, and Swift 2020, following Borusyak, Hull, and Jaravel 2022) is that connected sectors may have different BNDES share trends regardless of alignment shocks. The control should capture "political connectedness intensity" of each sector-muni cell.

**Recommendation:**
- The subscript in the presentation equation should be corrected: `ExposureControl_mj(tau)` where tau indexes the electoral cycle, not `ExposureControl_mj`
- More importantly: verify that the coefficient on exposure_control is actually identified (not absorbed) under each FE specification. With muni x sector FE, this control may be doing very little. This could explain why Table 5 (no control) looks so different from Table 1 (with control) -- the control is absorbing cross-sectoral variation that otherwise loads onto the instruments.
- Consider replacing the continuous exposure control with a more structured approach: interact cycle dummies with baseline-year exposure to create time-varying controls that are clearly not absorbed by FE.

---

## 2. Understanding the FE Specifications

Here is the key conceptual diagram for understanding what each FE absorbs and what remains for identification:

```
                         FIRST-STAGE INSTRUMENT:
               Z_mjt = Sigma_p (L_rjp,0 / D_r,0) x dAlign_rpt
                         |                           |
                   SHARES (vary by j)        SHOCKS (vary by m,t)
                   "Exposure weights"        "Alignment turnover"

+----------------------------------------------------------------------+
|                      VARIATION IN Z_mjt                              |
|                                                                      |
|  Cross-municipality:  Different dAlign + different L_rjp,0/D_r,0     |
|  Cross-sector:        Different L_rjp,0/D_r,0 (same dAlign within m) |
|  Cross-year:          Different dAlign (cycle transitions)            |
+----------------------------------------------------------------------+
```

### FE Specification Comparison

| FE Specification | What It Absorbs | Identification Source | F-stat (Mayor) | Assessment |
|-----------------|-----------------|---------------------|----------------|------------|
| **year only** (Table 3): `alpha_mj + alpha_t` | Common time trends + permanent muni x sector differences | Cross-muni + cross-sector variation in Z_mjt. **Includes aggregate alignment effect** (Align -> total BNDES) | **F = 25.1** | Inflated -- exploits confounded variation |
| **muni x year** (Table 2): `alpha_mj + alpha_mt` | Muni-level aggregate alignment effect + all muni-year shocks | **Only cross-SECTOR variation** within each muni-year = Pure Bartik identification | **F = 6.1** | Cleanest specification |
| **sector x year** (Table 1): `alpha_mj + alpha_jt` | Sector-level national trends in BNDES shares | Only cross-MUNI variation within each sector-year | **F < 2** | Weakest -- see below |

### Why is sector x year FE so weak for coalition instruments?

With sector x year FE, the sector-year mean of delta_s is absorbed. Identification requires: *municipalities with higher Z_mjt (relative to the sector-year average) should have higher delta_s_mjt (relative to the sector-year average)*. This is cross-municipality variation within sector-year cells.

The problem: coalition alignment changes are **broad and smooth**. When a mayor changes party, the entire coalition shifts. This creates alignment shocks that are correlated across many parties simultaneously, which means the exposure-weighted instrument Z_mjt is fairly homogeneous across sectors within a municipality. The cross-muni variation in Z_mjt within sector-year cells is then dominated by the aggregate alignment shock (which is absorbed by nothing in this specification -- there's no muni x year FE).

But wait -- that should make the instrument *stronger*, not weaker, because the aggregate effect is unabsorbed. The weakness suggests something else: **with sector x year FE, the exposure control is absorbing most of the cross-muni instrument variation** (since both Z and the exposure control load on the same exposure weights L_rjp,0/D_r,0). Indeed, Table 5 (no exposure control, same FE) shows slightly different results.

### Why does party alignment work with sector x year FE (Table 4)?

Party alignment creates sharper cross-sector contrasts within a municipality. A specific party's affiliated owners are concentrated in specific sectors, while coalition alignment diffuses across all sectors with any coalition-party presence. This creates more genuine cross-muni variation in Z_mjt within sector-year cells, because the exposure weights are more heterogeneous.

### Recommendation for the paper

- Lead with **muni x year FE** (Table 2) as the primary specification -- it is the cleanest Bartik identification
- Show **year FE** (Table 3) as a "less demanding" specification that produces stronger results
- Acknowledge that sector x year FE is too demanding for coalition instruments but show it works with party alignment
- Do NOT lead with the F=1051 result -- it will raise immediate suspicion from referees

---

## 3. Sector Groups: Distribution and Implications

  ---
  What the literature says you should do

  Drawing from GPS (2020), BHJ (2022/2025), and AKM (2019):

  1. Theory-first grouping: The classification should reflect the level at which BNDES allocation decisions are made and at which political influence
  operates. BNDES has distinct operational departments for agriculture, industry (split by technology intensity), infrastructure, and services. This
  supports your manufacturing 3-way split and argues for keeping Agriculture separate from Mining.
  2. Rotemberg weight diagnostics (GPS): Before finalizing groups, compute the Rotemberg weights for each sector under both the 21-section and grouped
  specifications. If Agriculture alone carries >25% of the absolute Rotemberg weight in the AM group, it should be its own instrument.
  3. Effective number of shocks (BHJ): Compute N_eff = 1/HHI of aggregate exposure for both the 21-section and the grouped specification. If grouping
  reduces N_eff materially (say from ~8 to ~5), the grouping is too aggressive.
  4. Shock balance tests: At the sector-group level, verify that average alignment shocks are uncorrelated with pre-period sector characteristics
  (employment levels, BNDES intensity, growth trends).
  5. Don't use data-driven grouping as primary specification: Quantile-based or clustering-based groupings are atheoretic and raise pre-testing bias
  concerns. Use them only as robustness checks.
  
The 10 sector groups (9 active, dropping XX) are:

| Group | Description | CNAE Sections | Expected BNDES Share |
|-------|-------------|---------------|---------------------|
| AM | Agriculture & Mining | A, B | High (agribusiness lending) |
| CL | Light Manufacturing | C (div 10-18) | Moderate |
| CH | Heavy Manufacturing | C (div 19-25) | High |
| CA | Advanced Manufacturing | C (div 26-33) | Moderate |
| UCo | Utilities & Construction | D, E, F | High (infrastructure) |
| Tr | Trade | G | Low-Moderate |
| Tp | Transport | H | Moderate |
| MS | Market Services | I-N | Moderate |
| PSO | Public, Social & Other | O-S | Low |

### Key concern: heterogeneity within groups

The grouping collapses 21 sections into 9, which:

1. **Reduces the number of observations from 1.37M to 700K** -- this is the most visible effect
2. **Reduces the cross-sector variation that identifies the Bartik instrument with muni x year FE** -- with only 9 sectors, there are only 9 exposure weights per muni-year. The instrument variation is thin.
3. **May aggregate away meaningful heterogeneity** -- MS (Market Services) lumps together hotels (I), information (J), finance (K), real estate (L), professional services (M), and admin services (N). Political connections likely operate very differently across these.

### Why do some specifications produce very large F-statistics?

The F=1051 for party alignment (Table 4, All tiers) is almost certainly an artifact. Possible explanations:
- **Governor party alignment is extremely predictive with sector x year FE** (F=80.6 alone). Governor-party changes may be correlated with BNDES sectoral shifts at the national level (BNDES is a federal/state bank, governors influence state-level project selection), and without muni x year FE, this aggregate correlation is unabsorbed.
- **Party alignment x sector exposure creates near-mechanical correlations** -- if certain parties are nationally associated with certain sectors (e.g., PT with PSO, PMDB with AM), then party alignment changes predict sector shares nationally. Sector x year FE should absorb this, but if the grouping is coarse enough, within-group heterogeneity could generate spurious correlations.

### Recommendation

- Run the primary specifications with the **original 21 CNAE sections** (the ungrouped tables in `muni_reg_tables/` show F=12.4 for Mayor with muni x year FE -- actually *stronger* than the grouped F=6.1)
- Use sector groups only as a robustness check, not the primary specification
- If you want fewer sectors, present results for both and explain why the F-stat changes

---

## 4. Endogenous Variables

**Yes, there is exactly one endogenous variable per observation.** Each observation in Panel A is a (municipality x sector x year) cell, and the endogenous variable is:

```
delta_s_mjt = s_mjt - s_mj,t-1
```

where `s_mjt = BNDES_mjt / BNDES_mt` is sector j's share of municipality m's total BNDES lending in year t.

The first stage is a **single-equation regression** with one endogenous variable and one (or multiple) instruments, evaluated at the muni x sector x year level. In the scalar 2SLS (second stage), the endogenous variable becomes either delta_s or delta_HHI at the muni x year level. In the vector 2SLS, there are J-1 endogenous variables (one per sector, dropping the reference sector).

The total number of endogenous variable observations is equal to the panel size: **700,650** (grouped) or **1,372,575** (ungrouped), minus first-year NAs.

---

## Overall Assessment: Is This Publication-Ready?

**Not yet, but close.** Here are the critical issues ranked by priority:

### Must Fix

1. **Switch to ungrouped sectors as primary.** The ungrouped panel (21 CNAE sections, 1.37M obs) produces F=12.4 for Mayor with muni x year FE -- comfortably above the Stock-Yogo threshold of 10. The grouped panel (9 sectors, 700K obs) gives F=6.1 -- below 10 and only marginal for weak instrument concerns. Leading with the weaker specification will draw immediate referee criticism.

2. **Clarify and fix the exposure control.** The current implementation creates a time-varying control whose variation is almost entirely mechanical (driven by cycle transitions). Either:
   - Document explicitly that the control absorbs cycle-specific baseline connectedness (not a time-invariant muni x sector characteristic)
   - Consider the Goldsmith-Pinkham et al. (2020) approach of interacting exposure weights with time trends as the proper control

3. **Lead with muni x year FE.** The presentation currently starts with sector x year FE (Table 1) where instruments are weak. Reorganize: Table 1 should be the muni x year specification where the story is strong.

### Should Fix

4. **Explain or drop the party alignment specification.** F=1051 will provoke "what's wrong here?" from any referee. Either:
   - Provide a convincing economic explanation for why party (not coalition) alignment is so much more predictive
   - Investigate whether this reflects mechanical correlation or a genuine causal channel
   - If legitimate, use it but with much more careful framing

5. **Add the Olea-Pflueger effective F-statistic.** The Wald F from `fixest` is the heteroskedasticity-robust F. For 2SLS with clustered SEs, the effective F-statistic (Olea and Pflueger, 2013) is the appropriate weak instrument diagnostic. `fixest` may not compute this directly -- consider the `ivDiag` package.

### Nice to Have

6. **Show the Anderson-Rubin confidence set** for the structural parameter to address weak instrument concerns, especially for the muni x year FE specification where F=6.1.

7. **Rotemberg weights decomposition** (Goldsmith-Pinkham et al., 2020): which municipalities/sectors drive the instrument most? This would strengthen the identification story.
