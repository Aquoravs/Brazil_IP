# Strategist-Critic Review: Anderson-Rubin Test Strategy Memo

**Reviewer:** strategist-critic
**Phase:** Exploration (CONSTRUCTIVE severity)
**Date:** 2026-04-28
**Documents reviewed:**
- `docs/strategy/ar_test_strategy.md`
- `docs/strategy/pseudo_code.md`
- `docs/strategy/robustness_plan.md`
- `docs/strategy/falsification_tests.md`

---

## Phase 1: Claim Identification

### Design
Clearly stated: reduced-form regression of log GDP on sector-level shift-share instruments, with the AR test operationalized as the cluster-robust Wald F-test on the instrument coefficients. The memo correctly identifies this as a reduced-form test that bypasses the weak first stage (F~6 for BNDES loan amounts).

### Estimand
The memo states H0: beta = 0 in the structural equation, then correctly maps this to H0: gamma = 0 in the reduced form (since gamma = Pi * beta, and beta = 0 implies gamma = 0 regardless of Pi). This is clearly stated.

**Issue 1 (minor).** The memo says "beta is the J-vector of sector-specific GDP elasticities with respect to BNDES share reallocation" but the structural equation is `Y = s' * beta + epsilon`. This makes beta a semi-elasticity (since Y is in logs but s is in share units), not an elasticity. Notation is not wrong per se, but the verbal description is imprecise.

### Treatment and Control
Treatment is the political-alignment shift-share instruments Z; control is implicit (within-municipality variation over time). The memo does not frame this as treatment/control in the classical sense, which is appropriate for an AR test -- it is testing reduced-form relevance, not estimating a treatment effect. Acceptable.

**Phase 1 verdict:** Design, estimand, and test are clearly stated. One minor labeling issue.

---

## Phase 2: Core Design Validity

### 2.1 Is the reduced-form Wald test equivalent to the AR test?

The memo claims (Section 2) that regressing Y on Z and computing the Wald test on all Z coefficients is "the AR statistic under the reduced-form interpretation." This needs scrutiny.

**Assessment: Correct, with an important caveat.** The classical AR test statistic for H0: beta = beta_0 in `Y = X*beta + e` with instruments Z is computed by regressing `Y - X*beta_0` on Z and testing joint significance. Under H0: beta = 0, this simplifies to regressing Y on Z and testing joint significance -- which is exactly a Wald test on the reduced-form regression. The memo gets this right.

**Caveat on cluster-robust version:** The textbook AR statistic uses a homoskedastic F-distribution. With cluster-robust standard errors, `fixest::wald()` computes a cluster-robust Wald statistic that follows an approximate F distribution. This is the heteroskedasticity-robust AR test discussed in Andrews, Stock & Sun (2019). The memo mentions cluster-robustness but does not cite the specific justification for using the cluster-robust Wald as an AR test. The key reference is Finlay and Magnusson (2009) or the `ivmodel` package documentation, which explicitly connect the cluster-robust Wald on the reduced form to the AR test. This is a minor citation gap, not a conceptual error.

### 2.2 Effective time-varying observations with levels instruments

**Issue 2 (substantive).** The memo recommends levels instruments as primary. These instruments Z^ell_jmt are constant within an electoral cycle (they depend on alignment status and pre-cycle baseline, both fixed for the 4-year term). With municipality FE and year FE, identification comes from within-municipality variation over time. But if the instrument changes only at electoral cycle boundaries (every 4 years for mayors, every 4 years for governors), each municipality effectively contributes only 3-4 independent instrument changes over the 2002-2017 period (e.g., cycles starting 2005, 2009, 2013 for mayors, plus potentially a partial 2001-2004 cycle).

The memo does not discuss this effective degrees-of-freedom issue. With year FE absorbing common time shocks, the within-municipality variation in Z is driven by changes in alignment status across electoral cycles. If year FE are at the annual level, they absorb the common level of Z within each cycle year. What remains is the cross-municipality heterogeneity in alignment changes interacted with heterogeneous baseline exposures. This is fine for the pooled test (N~5,570 clusters provides ample cross-sectional variation), but the memo should acknowledge that the time-series variation per municipality is limited to ~3-4 cycle transitions, not 16 independent observations.

This matters for: (a) the denominator df in the muni-by-muni case (the memo says T-K-1=11, but the effective df is closer to 3-4 cycle changes minus K=4, which could be zero or negative), and (b) the interpretation of "within R-squared" diagnostics.

### 2.3 Simplex constraint and instruments

The memo states (Section 6): "The simplex constraint sum_j s_jmt = 1 applies to the endogenous variable (credit shares), not to the instruments. The instruments Z^ell_jmt do not sum to any fixed constant across sectors within a municipality-year because the baseline exposures w^ell_jmp,t are heterogeneous across sectors."

**Assessment: Correct.** The instruments are Z^ell_jmt = sum_p w^ell_jmp,t * Align^ell_mpt. Even though Align is common across sectors within a tier-municipality-year, the weights w differ across sectors, so sum_j Z^ell_jmt = Align^ell_mpt * sum_j sum_p w^ell_jmp,t, which is not constant across municipality-years (the sum of baseline weights varies). Therefore, including all J=4 instruments simultaneously does not create perfect collinearity. The memo is correct here.

However, the memo should note that if a single alignment variable (Align) is common to all sectors within a municipality-tier-year, the J instruments are linear functions of a single binary shock scaled by J different weights. This means the J instruments have rank at most equal to the number of distinct alignment-tier combinations, not J. With one tier (mayor only), the 4 instruments are perfectly collinear in municipalities where all 4 sectors have proportional baseline weights. In practice, weight heterogeneity across sectors prevents exact collinearity, but near-collinearity is possible in municipalities where most baseline exposure is concentrated in one sector. The memo does not discuss this near-collinearity risk.

### 2.4 Power calculation for muni-by-muni case

**Issue 3 (moderate).** The memo states F(4, 11) with denominator df = T - K - 1 = 16 - 4 - 1 = 11. This assumes no year FE in the muni-specific regression (since with one municipality, year FE would absorb 15 df, leaving T - 15 - K = 16 - 15 - 4 < 0). The memo is implicitly running the muni-specific regression without year FE, which is reasonable but should be stated explicitly. If year FE are included in the muni-by-muni case, the test is not computable (negative df). This is another reason to reject the muni-by-muni approach, but the memo should be explicit about which specification it is computing power for.

Additionally, the denominator df should account for the intercept (already absorbed by demeaning) and any controls. With no controls and no year FE, df = T - K = 16 - 4 = 12 (not 11), since the municipality mean is absorbed by demeaning. The memo's formula T - K - 1 = 11 appears to double-count the intercept. This is a minor error in the df calculation.

### 2.5 Zero instrument columns and cluster-robust inference

The memo claims (Section 5) that zeros "do no harm" in the pooled regression. 

**Assessment: Mostly correct, with a nuance.** Municipalities with identically-zero instrument columns contribute zero to the numerator of the normal equations for that instrument's coefficient. They do not bias the coefficient estimate. However, they do contribute to the cluster count used in computing cluster-robust standard errors. If many clusters have zero instrument variation, the effective number of clusters identifying each coefficient is smaller than the total cluster count. The cluster-robust Wald test implicitly uses the total number of clusters for df adjustment, which could make the test slightly liberal (the effective cluster count for the sparsely identified instruments is smaller than N=5,570).

This is unlikely to be a serious problem with J=4 coarse BNDES sectors (most municipalities probably have at least 2-3 active sectors), but could matter with finer classifications (21 CNAE sections). The memo should acknowledge this and recommend reporting the number of municipalities with non-zero variation for each instrument column.

### 2.6 Exposure control omission

**Issue 4 (substantive).** The project's design decision D9 states that `exposure_control` (sum_p w^ell_jmp,t) is "included in primary sector spec." The Goldsmith-Pinkham, Sorkin & Swift (2020) and Borusyak, Hull & Jaravel (2022) frameworks emphasize that controlling for the exposure shares (or functions of them) is important for the validity of shift-share instruments.

The strategy memo explicitly states (Section 6): "No controls beyond FE in the primary specification." It does not mention the exposure control at all, even as a robustness check. This is a significant omission. The exposure control is the sum of baseline weights across parties for each sector-municipality-year. It captures the overall "connectedness" of a municipality's sector to the political system. If exposure_control correlates with both the instrument (mechanically, since it appears in the instrument construction) and with GDP (e.g., more connected municipalities grow differently), omitting it could bias the reduced-form coefficient.

The memo should:
1. Discuss whether the exposure control belongs in the AR regression.
2. At minimum, include it as a Tier 1 robustness check.
3. Clarify whether the Borusyak-Hull-Jaravel framework requires conditioning on exposure shares for the AR test to be valid, or whether the municipality FE already absorb the relevant variation.

Since exposure_control varies across sectors but is brought to the municipality level (presumably summed or averaged), and since municipality FE already absorb time-invariant exposure levels, the question is whether time-varying exposure_control (which changes with the baseline window across electoral cycles) needs to be controlled for. This is a non-trivial identification question that the memo should address.

---

## Phase 3: Inference Soundness

### 3.1 Municipality-level clustering

The memo recommends municipality-level clustering as primary, with state-level clustering as robustness (R11). This is reasonable for most shift-share designs, but the memo should discuss whether two-way clustering (municipality + year) is warranted. With year FE already absorbed, the residual cross-sectional correlation within a year should be small, so municipality-only clustering is likely sufficient. The memo should state this reasoning explicitly.

Additionally, with shift-share instruments where shocks (alignment changes) are common within states, there may be spatial correlation that municipality clustering does not capture. State-level clustering (27 clusters) would be very conservative and may have poor finite-sample properties. The memo mentions this as R11 but does not discuss the Carter-Schnepel-Steigerwald (2017) or Adao-Kolesar-Morales (2019) corrections for shift-share designs. The Adao-Kolesar-Morales correction is specifically designed for settings where residuals are correlated due to common exposure structure. This is a relevant citation gap.

### 3.2 AR test with K instruments and K endogenous variables

The memo addresses Objection 2: "With 4 instruments and 4 endogenous variables, you are just-identified -- the AR test has no power against alternatives." The memo's response is that "the AR test and 2SLS Wald test are asymptotically equivalent under strong instruments, but they diverge under weak instruments."

**Assessment: Partially correct but somewhat misleading.** In the just-identified case (K = J), the AR test and the Wald test are numerically identical -- not just asymptotically equivalent -- because the 2SLS estimator is the unique IV estimator and the AR confidence set inverts to the same test. The key advantage of the AR test in the just-identified case is not that it gives a different answer, but that its distribution under H0 is known (F(K, N-K)) regardless of instrument strength, whereas the 2SLS Wald test uses an asymptotic approximation that relies on strong instruments for correct size. So the memo's core point is right (AR has correct size), but the claim that they "diverge" is imprecise -- they give the same test statistic, but the critical values differ.

**Issue 5 (moderate).** More importantly, the memo conflates two different objects: (a) the AR test of H0: beta = 0 in the structural equation (which requires computing Y - X*beta_0 and regressing on Z), and (b) the Wald test on the reduced form (which regresses Y on Z and tests gamma = 0). These are the same test ONLY when beta_0 = 0 (so Y - X*beta_0 = Y). For testing H0: beta = beta_0 with beta_0 != 0, they would differ. The memo is testing beta = 0, so this distinction does not matter operationally, but the memo should be clearer about why the reduced-form Wald and the AR test coincide specifically at the null beta = 0.

### 3.3 Multiple testing for grouped AR

The memo proposes 27 state-level AR tests (R12) and 4 BNDES-quartile tests (R13) but does not discuss multiple testing adjustments in the main strategy section. The falsification tests mention "Bonferroni or Holm correction for J = 4 comparisons" for sector-by-sector tests (R8), but no adjustment is mentioned for the 27 state-level tests.

**Issue 6 (minor).** The 27 grouped tests are described as "heterogeneity diagnostics, not the primary test," which partially mitigates the multiple testing concern. However, if the results are presented as "X out of 27 states reject," this implicitly invites a multiple testing interpretation. The memo should recommend either: (a) a Benjamini-Hochberg adjustment, or (b) framing the grouped tests explicitly as descriptive (reporting the distribution of F-statistics, not counting rejections).

---

## Phase 4: Polish and Completeness

### 4.1 Robustness check ordering

The three-tier ordering (Must-run / Should-run / Stress tests) is well-organized and maps to the AR phases. No issues.

### 4.2 Missing robustness checks

**Issue 7.** The exposure control (D9) is absent from all three tiers of the robustness plan. As discussed in Issue 4, this should be at least Tier 1.

**Issue 8.** The robustness plan does not include a Conley spatial HAC standard error check. With municipalities as units and potential spatial correlation in GDP shocks, this is a natural robustness check for a Tier 2 slot.

### 4.3 Missing falsification tests

The falsification test list is comprehensive. One addition:

**Issue 9.** A "pre-period balance" test is missing: do baseline (pre-treatment) municipality characteristics differ systematically across municipalities that experience alignment changes vs. those that do not? This is not a balance test in the RCT sense (alignment is not randomly assigned), but showing that pre-treatment GDP levels, population, and sectoral composition are not predicted by the instruments would strengthen the exogeneity argument. This could be framed as "regress baseline X on instruments and test joint significance."

### 4.4 Pseudo-code implementability

The pseudo-code is implementable given the pipeline. Two gaps:

**Issue 10.** The pseudo-code references `z_cols_levels_mayor <- grep("^Z_mayor_coalition_cycle_specific_.*$")` but notes that `bndes_sector` may not be wired through the pipeline (the data flow section says "May need: Z columns for bndes_sector"). This is a known gap but should be flagged as a blocker for implementation -- the exploration script cannot run without resolving this.

**Issue 11.** The within-R-squared diagnostic (Step 8) computes partial R-squared as `fixest::r2(mod_1, "ar2") - fixest::r2(mod_fe_only, "ar2")`. This is not the correct way to compute partial R-squared in fixest. The adjusted R-squared difference is not the partial R-squared of the instruments. The correct approach is to use the incremental F-statistic or compute `(RSS_restricted - RSS_unrestricted) / RSS_restricted`. This implementation error should be fixed.

### 4.5 Citations

**Issue 12.** Missing citations:
- Finlay and Magnusson (2009) or Stock and Wright (2000) for the cluster-robust AR test
- Adao, Kolesar, and Morales (2019) for shift-share inference corrections
- Carter, Schnepel, and Steigerwald (2017) for few-cluster concerns (relevant if state-level clustering is used)

The Anderson & Rubin (1949) original, Andrews-Stock-Sun (2019), Mikusheva-Sun (2022), GSS (2020), and BHJ (2022) are all correctly cited.

---

## Issues Summary

| # | Issue | Severity | Deduction | Phase |
|---|-------|----------|-----------|-------|
| 1 | "Elasticity" label for semi-elasticity | Minor (notation) | -1 | 1 |
| 2 | Effective time-varying df not discussed for levels instruments | Moderate (missing assumption discussion) | -3 | 2 |
| 3 | Muni-by-muni df calculation: T-K-1=11 may double-count intercept; year-FE absence not stated | Minor (sanity check gap) | -2 | 2 |
| 4 | Exposure control omitted from primary spec discussion and all robustness tiers | Substantive (missing critical control) | -8 | 2 |
| 5 | Imprecise claim about AR vs 2SLS divergence in just-identified case | Moderate (conceptual imprecision) | -3 | 3 |
| 6 | No multiple testing adjustment recommended for 27 state-level grouped tests | Minor (missing robustness detail) | -2 | 3 |
| 7 | Exposure control absent from robustness plan | Substantive (covered in #4, no double-count) | 0 | 4 |
| 8 | No Conley spatial HAC robustness check | Minor (missing robustness) | -2 | 4 |
| 9 | No pre-period balance falsification test | Minor (missing falsification) | -2 | 4 |
| 10 | bndes_sector pipeline gap flagged but not marked as blocker | Minor (implementation) | -1 | 4 |
| 11 | Partial R-squared computation in pseudo-code is incorrect | Moderate (implementation error) | -3 | 4 |
| 12 | Missing methodological citations (Finlay-Magnusson, AKM, CSW) | Minor (citations) | -3 | 4 |

**Total deductions: -30**

---

## Final Score: 70/100

This is below the 80 threshold required for advancement.

---

## Verdict

The memo correctly identifies the AR test as a reduced-form Wald test and provides a well-structured implementation plan, but it has one substantive gap (omission of exposure control from both the primary spec discussion and all robustness tiers) and several moderate issues (imprecise claims about AR vs 2SLS equivalence, missing effective-df discussion for levels instruments, incorrect partial R-squared computation). The exposure control omission is the most consequential: the Borusyak-Hull-Jaravel and Goldsmith-Pinkham-Sorkin-Swift frameworks both emphasize conditioning on exposure shares, and the project's own design decision D9 includes exposure_control in the primary sector spec. The memo must address why the AR test specification drops it, or add it.

---

## Recommendations for Revision

1. **Exposure control (highest priority).** Add a subsection discussing whether the AR regression should include the municipality-level exposure control (sum of baseline weights across parties, summed over sectors). At minimum, add it as R0 in Tier 1 robustness. Ideally, discuss the theoretical argument: does Borusyak-Hull-Jaravel require conditioning on exposure shares for the reduced-form test, or do municipality FE suffice?

2. **Effective time-varying df.** Add a paragraph in Section 3 or 4 noting that levels instruments change only at electoral cycle boundaries, so each municipality contributes ~3-4 independent instrument changes over 16 years. Discuss implications for the muni-by-muni case (makes it even more infeasible) and for the pooled case (cross-sectional variation is what drives identification, not time-series variation).

3. **AR vs 2SLS in just-identified case.** Revise Objection 2 response: in the just-identified case, the AR and 2SLS Wald statistics are numerically identical; the advantage is that the AR test's null distribution is exact (or valid with weak instruments), while the 2SLS Wald relies on strong-instrument asymptotics for its critical values.

4. **Fix partial R-squared computation.** Replace the adjusted-R-squared difference with the correct formula using residual sums of squares.

5. **Add missing citations.** Finlay-Magnusson (2009) for robust AR; Adao-Kolesar-Morales (2019) for shift-share inference.

6. **Add pre-period balance test** to falsification tests.

7. **Add Conley spatial HAC** to Tier 2 robustness.

---
---

## Round 2 Review

**Reviewer:** strategist-critic
**Date:** 2026-04-28
**Severity:** Exploration (CONSTRUCTIVE)
**Round:** 2 of 3

### Issue-by-Issue Resolution Status

| # | Issue | Round 1 Deduction | Status | Evidence | Residual Deduction |
|---|-------|-------------------|--------|----------|-------------------|
| 1 | Semi-elasticity label | -1 | **RESOLVED** | Section 1 now correctly uses "semi-elasticities" with explicit justification ("log outcome, share-unit regressors") | 0 |
| 2 | Effective time-varying df | -3 | **RESOLVED** | Section 3 adds a detailed paragraph on electoral-cycle timing, explaining ~3-4 independent transitions per municipality, implications for pooled vs. muni-by-muni, and within-R-squared interpretation | 0 |
| 3 | Muni-by-muni df calculation | -2 | **RESOLVED** | Section 4 now explicitly states year FE cannot be included (negative df), uses correct df = T - K = 12 (not 11), and notes the intercept is absorbed by demeaning. Also integrates the effective-df argument from Issue 2 as additional evidence against the muni-by-muni approach | 0 |
| 4 | Exposure control omission | -8 | **RESOLVED** | New Section 3.1 provides a thorough treatment: theoretical argument from BHJ/GSS, what municipality FE absorb vs. what they do not, collinearity risk with cycle-specific baselines, clear recommendation (no EC in primary, sector-specific EC as R0 robustness), and interpretive guidance for the case where results differ with/without EC. This is exactly what was requested | 0 |
| 5 | AR vs 2SLS imprecision | -3 | **RESOLVED** | Objection 2 response now correctly states the AR and 2SLS Wald statistics are "numerically identical" in the just-identified case, with the advantage being the AR's exact null distribution. Section 2 also explains why the reduced-form Wald and AR coincide specifically at beta_0 = 0 | 0 |
| 6 | Multiple testing for grouped AR | -2 | **RESOLVED** | Section 4 now recommends both Benjamini-Hochberg adjustment and descriptive framing (distribution of F-statistics), with the latter recommended as preferred. Pseudo-code implements BH adjustment | 0 |
| 7 | Exposure control absent from robustness plan | 0 | **RESOLVED** | R0 is now the first entry in Tier 1, with detailed description referencing BHJ and GSS | 0 |
| 8 | Conley spatial HAC | -2 | **RESOLVED** | R14 added to Tier 2 with description of distance-based kernel approach and rationale (complements state-level clustering without few-cluster problem). Also mentioned in Section 2 of the strategy memo | 0 |
| 9 | Pre-period balance falsification | -2 | **RESOLVED** | F7 added to falsification tests with full specification: pre-2005 municipality averages, cross-sectional regression on first-cycle instruments, joint F-test with HC2 SEs. Pseudo-code includes complete implementation (Step 6). Interpretation framework discusses remedies if the test rejects | 0 |
| 10 | bndes_sector pipeline blocker | -1 | **RESOLVED** | Now explicitly labeled as "**BLOCKER**" in both Section 7 and Section 11 summary table, with two resolution options specified | 0 |
| 11 | Partial R-squared computation | -3 | **RESOLVED** | Pseudo-code Step 8 now uses the correct RSS-based formula: `partial_r2 <- 1 - sum(resid(mod_1)^2) / sum(resid(mod_fe_only)^2)` | 0 |
| 12 | Missing citations | -3 | **RESOLVED** | All three citations added: Finlay & Magnusson (2009) in Pre-Strategy Report and Section 2; Adao, Kolesar & Morales (2019, QJE) in Pre-Strategy Report and Section 2; Carter, Schnepel & Steigerwald (2017) in Pre-Strategy Report and robustness R11 | 0 |

**All 12 issues from Round 1 are RESOLVED.**

### New Issues Introduced by Revision

**Advisory (no deduction):** The within-R-squared diagnostic in pseudo-code Step 8 (line 202) computes `1 - sum(resid(mod_fe_only)^2) / sum((dt$log_gdp_pc - mean(dt$log_gdp_pc))^2)`. This is the total R-squared (comparing FE-only residuals to the grand-mean residuals), not the within-R-squared. The within-R-squared should compare FE-only residuals to the within-demeaned total sum of squares. In practice, `fixest::r2(mod_fe_only, "wr2")` gives the correct quantity. Since this is a diagnostic report (not a test or an estimand), this is advisory only -- no deduction.

No other new issues identified. The revision is clean: no conceptual errors introduced, no scope creep, and the new Section 3.1 on exposure controls is well-reasoned and well-integrated with the rest of the memo.

### Quality Assessment by Phase

| Phase | Assessment |
|-------|-----------|
| **Phase 1: Claim Identification** | Excellent. Estimand, null, and test are precisely stated. Semi-elasticity terminology now correct. |
| **Phase 2: Core Design Validity** | Strong. The exposure control discussion (Section 3.1) is thorough and well-argued. The effective-df discussion for levels instruments is clear and correctly integrated into both the pooled and muni-by-muni analyses. The near-collinearity risk for municipalities with concentrated baseline exposure remains unaddressed (noted in Round 1 body text but not as a numbered issue), which is acceptable for the exploration phase. |
| **Phase 3: Inference Soundness** | Strong. The AR vs. 2SLS distinction is now precise. Multiple testing is addressed with appropriate recommendations. The AKM citation and discussion of shift-share-specific inference concerns strengthens the clustering section. |
| **Phase 4: Polish and Completeness** | Complete. All robustness checks and falsification tests requested in Round 1 are present. The pseudo-code is implementable (modulo the acknowledged BLOCKER). Citations are comprehensive. |

### Updated Score

Starting at 100:
- Round 1 issues: all resolved, 0 deductions restored
- New issues: 0 (advisory only, no deduction)

**Final Score: 97/100**

The 3-point gap from a perfect score reflects two minor items that are acceptable at the exploration phase but would need attention before the execution phase:

1. (-1) The near-collinearity risk when baseline exposure is concentrated in one sector (discussed in Round 1 body text, Section 2.3) is acknowledged but not formally addressed in the strategy memo. At the exploration phase this is fine; by execution phase, the diagnostic of per-instrument VIFs or condition numbers should be specified.

2. (-1) The within-R-squared computation in pseudo-code Step 8 uses total R-squared instead of within-R-squared (advisory item above). Minor but should be fixed before implementation.

3. (-1) The Adao-Kolesar-Morales correction is mentioned as a future possibility ("if implemented in future phases") but no concrete recommendation is given for when or whether to implement it. At the exploration phase, flagging it is sufficient; by execution phase, a decision should be made.

### Verdict

**PASS.** Score 97/100 exceeds the 80 threshold. All 12 issues from Round 1 are fully resolved. The revision is thorough and well-executed. The strategy memo is ready for implementation (pending resolution of the bndes_sector pipeline BLOCKER).

The memo now provides a complete, technically sound specification for the Anderson-Rubin test: correct estimand, correct test statistic, correct inference framework, appropriate exposure-control discussion grounded in BHJ/GSS, comprehensive robustness plan with 20 checks across three tiers, 8 falsification tests with interpretation guidance, and implementable pseudo-code. The three residual items (-3 total) are phase-appropriate and do not impede the exploration-phase AR test.
