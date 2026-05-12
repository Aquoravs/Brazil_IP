# Strategy Memo: Anderson-Rubin Test of BNDES Sectoral Reallocation on Municipal GDP

**Paper type:** Reduced-form (primary) with IV motivation (secondary).
**Phase:** Exploration.
**Date:** 2026-04-28 (revised 2026-04-28, round 2).

---

## Pre-Strategy Report

**Research spec:** `INSTRUCTIONS.md` (section "Research Design") + `docs/research_state.md` section 1
**Literature review:** Not a standalone file; seminal references embedded in `.claude/references/domain-profile.md`
**Data assessment:** Embedded in `docs/research_state.md` sections 2--6 and `scripts/R/4_regression_panels/41_build_muni_panel.R`
**Domain profile:** Loaded (`.claude/references/domain-profile.md`)

**Research question:** Is the allocation of BNDES lending across municipalities GDP-optimal? H0: beta = 0 (sectoral reallocation driven by political turnover has no first-order GDP effect).

**Key findings from literature:**
- Anderson & Rubin (1949), Andrews, Stock & Sun (2019): AR test is valid under weak instruments; inverts confidence sets without requiring a consistent first-stage estimate.
- Mikusheva & Sun (2022): Ridge-Regularized Jackknifed AR (RJAR) extends to many-weak-instruments settings.
- Goldsmith-Pinkham, Sorkin & Swift (2020): Rotemberg weights decompose the Bartik instrument into exposure-share contributions, enabling transparency about what drives the estimate.
- Borusyak, Hull & Jaravel (2022): Shock-based inference is the relevant identification framework when shocks (alignment turnover) are arguably exogenous given predetermined exposures.
- Finlay & Magnusson (2009): Cluster-robust AR test retains correct size under heteroskedasticity and within-cluster correlation; justifies using the cluster-robust Wald statistic on the reduced form as the AR test.
- Adao, Kolesar & Morales (2019, QJE): Shift-share instruments induce residual correlation through common exposure structure; standard cluster-robust SEs may understate uncertainty.
- Carter, Schnepel & Steigerwald (2017): Few-cluster inference concerns when clustering at a coarse level (e.g., 27 states).

**Available data:**
- Municipality x year panel (Panel B): ~5,570 munis x 16 years (2002--2017). Key variables: `log_gdp_pc`, `log_gdp`, sector-level instruments (`Z_*`, `dZ_*` in wide format), `delta_s_*`, `s_*`, `bndes_pc`, employment totals, population. Built by script 41.
- Municipality x sector x year panel (Panel A): long-format with BNDES credit shares, sector instruments, exposure controls. Built by scripts 35, 41.
- Instruments: political-alignment shift-share at 3 tiers (mayor, governor, president) x 2 baseline types (cycle-specific, 2002-fixed) x multiple sector classifications (4 BNDES macros, 11 custom, 21 CNAE sections).
- GDP: IBGE PIB Municipal, deflated to 2018 R$ via national IPCA. Per capita computed using IBGE population.
- Variation available: within-municipality over-time variation in sector-level political alignment instruments, driven by electoral turnover interacted with pre-determined firm-party exposure.

**Candidate designs from domain profile:** Anderson-Rubin test (primary), RJAR for many-instruments (Phase 3), conditional subvector AR, FAR, Cluster Jackknife AR (stress tests).

Proceeding to strategy design.

---

## 1. Estimand

### What are we testing?

The parameter of interest is $\beta$ in the structural equation:

```
log(GDP_mt) = alpha_m + delta_t + beta' * emp_share_mt + epsilon_mt
```

where `emp_share_mt = (emp_share_1mt, ..., emp_share_Jmt)` is the vector of **sector employment shares** in municipality m at time t (employment in sector j divided by total municipal employment), and $\beta$ is the J-vector of sector-specific GDP **semi-elasticities** with respect to compositional reallocation of employment (log outcome, share-unit regressors: a one-percentage-point increase in sector j's employment share is associated with a $100 \cdot \beta_j$ percent change in GDP).

**Why employment shares?** Employment is the most comprehensive observable proxy for the sectoral distribution of economic activity at the municipality level for 2002–2017. If sector-by-municipality value added or gross output were available, they would be preferable — employment understates the activity of capital-intensive sectors and overstates labour-intensive ones — but they are not. Employment is therefore the primary measure used here, and value-added-by-sector data, when reachable, would enter as robustness (see C6, A11).

**The full causal chain.** The research question concerns the last link of:

> Political turnover shock → politically connected firms in some sectors receive marginally more BNDES credit → employment in those sectors expands → the sectoral composition of economic activity within the municipality shifts → municipal GDP changes.

BNDES credit shares are not the estimand; they are the mechanism that transmits the political shock to employment composition. The AR test in this memo asks whether the *last* link — composition → GDP — is non-zero, when the variation in composition is driven (instrumented) by the upstream political-credit mechanism.

**The null hypothesis is $H_0: \beta = 0$.** Under this null, exogenous compositional reallocation of economic activity across sectors has no first-order effect on municipal GDP. This is the optimality benchmark for the *sectoral structure of the local economy*: if the local economy is at an interior optimum with respect to sectoral composition, small politically driven reallocations are on the tangent hyperplane to the production frontier and have zero marginal GDP effect. The optimality interpretation has shifted from "BNDES credit allocation across sectors is GDP-optimal" to "the sectoral composition of economic activity is GDP-optimal at the margin."

**The estimand is not a single scalar.** It is a joint test of J coefficients. At the leading D16 candidate margin `policy_block_active × S3` (12 active bins, not committed under D28), the AR test would have up to 12 degrees of freedom (or 11 if a simplex constraint forces dropping one bin in robustness). At coarser margins (4 BNDES macrosectors), it has 3–4 df; at finer margins (`cnae_section × S3`, 51 active bins), it has up to ~50 df, requiring many-instruments methods (R18, R19).

### Why the AR test?

The AR test is the correct inference tool here for three reasons:

1. **Multiple instruments, joint inference.** With $K = 12$ instruments at the primary margin (and up to ~50 at the secondary `cnae_section × S3` margin), the inferential object is a joint test of $\beta = 0$ across multiple sectors. The AR test handles this naturally as a Wald test on the reduced form.

2. **Valid inference regardless of instrument strength (D20).** Under $H_0: \beta = 0$, the AR statistic follows an exact $F(K, N-K)$ distribution irrespective of first-stage relevance. The 2SLS Wald test relies on strong-instrument asymptotics for its critical values; AR does not. F2 is therefore an *informativeness* check, not a validity gate (D20) — a weak first stage means the AR confidence set is wide, not that inference is biased (Andrews, Stock & Sun 2019; Dufour 1997). CLR (Moreira 2003) may complement AR in power for $K > 1$.

3. **No $\hat\beta$ estimate needed.** The policy question asks whether $\beta = 0$, not what $\beta$ equals. The AR test answers this directly without producing an unstable point estimate when the first stage is weak.

**Note on first-stage diagnostics under the new framing (D24).** The earlier motivation in this memo — "first-stage F ~ 6 for loan amounts, so AR is needed for weak-IV-robust inference" — no longer applies as the *primary* motivation. Under the new framing, sector employment shares are the endogenous variable, and the first stage of instruments → sector employment composition is in fact strong (F up to 265 for `employment_log`; F1 confirmed across candidate margins per D15, D16). A 2SLS approach treating employment composition as endogenous would be feasible. AR is preferred because (i) we want joint inference on a multi-dimensional $\beta$ at the committed margin; (ii) we want a procedure that remains valid even if the first stage turns out to be weak at finer aggregation margins where $K$ grows (`cnae_section × S3`, $K \approx 50$); and (iii) we want to avoid the size distortion that affects 2SLS with non-trivial $K$ relative to cluster count. The historical F ~ 6 result for BNDES loan amounts now belongs to a *mechanism check* on the credit-share channel (the upstream link of the chain), not to the primary first-stage evidence.

### Volume/composition decomposition

The structural equation above isolates the **composition channel** (which sectors employ workers in what proportions) but says nothing about the **volume channel** (how much total BNDES credit, normalised by initial GDP, the municipality receives). These are conceptually distinct effects, and both could move with the political turnover shock. The decomposition is operationalised in the second stage by including a volume control:

```
log(GDP_mt) = alpha_m + delta_t + beta' * emp_share_mt
             + lambda * (bndes_total_mt / gdp_{m,0}) + epsilon_mt
```

where the volume control is current-year total BNDES disbursements normalised by initial-period municipal GDP — a unit-free ratio. The specification of this control is the working choice and is subject to revision after theory/math review of the econometrics (e.g., whether to use initial-period GDP, lagged GDP, a time-invariant scaling like average pre-period employment, or to keep BNDES in levels with population as a separate scaling). Conditioning on the volume term partials out the aggregate level effect, so $\beta$ identifies the marginal GDP effect of compositional reallocation *holding the level of BNDES activity fixed*. Whether the volume term should be entered exogenously (OLS) or instrumented — total BNDES is itself politically endogenous — is the open question A10. The four candidate approaches are: (1) Pure AR with OLS on both; (2) Partial IV instrumenting employment shares only (the **baseline per D24**); (3) Full IV instrumenting both; (4) Mixed — OLS for shares, IV for total. Approaches (1), (3), and (4) enter as robustness.

The composition/volume decomposition is what makes the AR test in this memo a *test of the optimality of the sectoral structure of the local economy*, not a test of the optimality of total spending. It is the substantive payoff of the framing introduced in D24.

---

## 2. The Anderson-Rubin Test: Formal Definition

### Setup

**Structural equation (suppressing FE):**
```
Y_mt = s_mt' * beta + epsilon_mt     (1)
```

**First stage:**
```
s_mt = Z_mt * Pi + V_mt              (2)
```

where Z_mt is the K-vector of instruments (sector-level shift-share instruments across tiers).

**Reduced form (substituting (2) into (1)):**
```
Y_mt = Z_mt * (Pi * beta) + (epsilon_mt + V_mt' * beta)
     = Z_mt * gamma + eta_mt          (3)
```

where gamma = Pi * beta is the reduced-form coefficient vector.

### The AR test statistic

Under H0: beta = 0, equation (3) becomes:

```
Y_mt = Z_mt * 0 + epsilon_mt
```

So the AR test is simply: **regress Y on Z (with FE) and test the joint significance of all Z coefficients.**

Formally, the AR statistic is:

```
AR = (RSS_restricted - RSS_unrestricted) / (K * sigma_hat^2)
```

where:
- RSS_restricted: residual sum of squares from `Y_mt ~ | alpha_m + delta_t` (FE only)
- RSS_unrestricted: residual sum of squares from `Y_mt ~ Z_mt | alpha_m + delta_t`
- K: number of instruments
- sigma_hat^2: unrestricted residual variance

Under H0 and correct specification, AR ~ F(K, N - K - n_FE) asymptotically (or chi-squared(K)/K in large samples).

**Why this coincides with the reduced-form Wald test at beta_0 = 0:** The general AR test for H0: beta = beta_0 regresses (Y - X*beta_0) on Z and tests joint significance. At beta_0 = 0, the dependent variable simplifies to Y itself, so the AR test becomes a standard Wald test on the reduced-form regression. For beta_0 != 0 the two would differ, but since our null is precisely beta = 0, they are equivalent.

### Implementation in fixest

The AR test is operationally a Wald test of the reduced-form regression:

```r
mod_rf <- feols(log_gdp_pc ~ Z_1 + Z_2 + ... + Z_K | muni_id + year,
                data = dt, vcov = ~muni_id)
ar_test <- fixest::wald(mod_rf, keep = "^Z_")
```

The `wald()` function in fixest computes the heteroskedasticity/cluster-robust Wald statistic, which is the AR statistic under the reduced-form interpretation. The validity of the cluster-robust Wald as an AR test is established by Finlay & Magnusson (2009): the cluster-robust AR test retains correct size under within-cluster correlation.

**Critical distinction:** This is a cluster-robust AR test, not the textbook homoskedastic version. With clustering at muni_id, the effective sample size for inference is ~5,570 municipalities, not ~89,000 muni-years. The test accounts for within-municipality serial correlation.

**Shift-share inference caveat:** Adao, Kolesar & Morales (2019) show that in shift-share designs, standard cluster-robust SEs can understate uncertainty because residuals are correlated across units that share similar exposure structures. Their correction is relevant here: municipalities in the same state or with similar sectoral compositions may have correlated residuals through the common alignment shocks. The primary specification clusters at the municipality level (conservative given ~5,570 clusters), with state-level clustering and Conley spatial HAC as robustness checks (R11, R14 in the robustness plan). If Adao-Kolesar-Morales standard errors are implemented in future phases, they would provide a tighter correction for the specific exposure-driven correlation structure.

---

## 3. Primary Specification

### Equation

```
log(GDP_mt) = alpha_m + delta_t + sum_j gamma_j * Z^ell_jmt + epsilon_mt     (4)
```

where:
- `log(GDP_mt)` = log real GDP (deflated by national IPCA to 2018 R$) for municipality m in year t
- `alpha_m` = municipality fixed effect
- `delta_t` = year fixed effect
- `Z^ell_jmt` = sector-level shift-share instrument for office tier ell in sector j, aggregated to municipality level (see below)
- `gamma_j` = reduced-form coefficient on the j-th sector's instrument
- Clustering: municipality level

### How sector instruments enter the municipality-level regression

The sector instruments Z^ell_jmt live at the (m, j, t) level. To run a municipality-level regression, they must be brought to the (m, t) level. There are two approaches:

**Approach A: Wide format (recommended for Phase 1).** Include each sector's instrument as a separate regressor. With J = 4 BNDES sectors and L = 3 tiers, this gives up to 4 x 3 = 12 instruments. The AR test is a joint Wald on all 12 coefficients. This is what script 54 already does.

**Approach B: Stack and summarize.** Aggregate Z^ell_jmt to municipality level using some weighting scheme (e.g., employment shares). This reduces the instrument count but imposes a specific aggregation structure. Less transparent; defer to robustness.

**Phase 1 recommendation:** Use Approach A with J = 4 BNDES sectors and L in {mayor} or {mayor, governor}. This gives K = 4 or K = 8 instruments. Start with mayor-only (K = 4) for maximum power.

### Levels vs. changes instruments

The project has both levels instruments (Z^ell_jmt) and changes instruments (dZ^ell_jmt). The changes instruments are non-zero only at inauguration years (2005, 2009, 2013, 2017 for mayors; 2007, 2011, 2015 for governors/presidents).

**Recommendation: Use levels instruments for the primary AR test.** Reason: levels instruments spread variation across the full electoral term (4 years per cycle), giving more non-zero observations. With the changes instruments, most of the panel (non-inauguration years) contributes only to FE estimation, not to the AR test, resulting in severe power loss.

**Important caveat on effective time-series variation:** Although the levels instruments produce non-zero values in every year, they are **constant within each electoral cycle** (approximately 4 years). With municipality FE and year FE, identification comes from within-municipality changes in Z across electoral cycle boundaries. Each municipality therefore contributes only ~3-4 independent instrument transitions over the 2002-2017 period (mayor cycles starting approximately 2005, 2009, 2013; governor/president cycles starting 2007, 2011, 2015). Year FE absorb the common level within each cycle-year, so what identifies the coefficients is the cross-municipality heterogeneity in instrument changes at cycle transitions, interacted with heterogeneous baseline exposures. This means:

- **For the pooled test:** Identification is primarily driven by cross-sectional variation across ~5,570 municipalities in how their instruments change at cycle boundaries, not by 16 independent time-series observations per municipality. With ~5,570 clusters, this cross-sectional variation is ample.
- **For the muni-by-muni case:** The effective degrees of freedom are far worse than T - K = 12 would suggest. Each municipality has at most ~3-4 independent instrument transitions, which is insufficient for a K = 4 test (see Section 4).
- **For interpreting within-R-squared:** The within R-squared of the instruments will be mechanically limited by the step-function nature of the instruments within cycles. Low within R-squared does not necessarily indicate weak instruments; it reflects the electoral-cycle timing structure.

**Robustness:** Run the AR test with changes instruments as well. If both reject (or both fail to reject), the result is robust to the timing assumption.

### Variant: log GDP vs. log GDP per capita

Both `log_gdp` and `log_gdp_pc` are available in Panel B. With municipality FE, the two differ only by `log(population_mt)`, which is absorbed if population grows at a municipality-specific rate (approximately true). Recommend:

- **Primary:** `log_gdp_pc` (standard in the growth/development literature)
- **Robustness:** `log_gdp` (avoids potential measurement error in population denominators)

---

## 3.1. Exposure Control in the Municipality-Level AR Regression

### The issue

The project's design decision D9 specifies that `exposure_control` (EC^ell_jmt = sum_p w^ell_jmp,t) is included in the primary sector-level specification (scripts 52, 53). The control captures the share of sector-j baseline owners in municipality m affiliated with any political party at tier ell. The question is whether -- and in what form -- this control belongs in the municipality-level AR regression.

### How the literature actually motivates exposure controls

The framing "shift-share instruments require sector-specific exposure controls" overstates the literature's prescriptions:

- **Goldsmith-Pinkham, Sorkin & Swift (2020).** Identification rests on the exogeneity of *initial shares* conditional on a control set. The paper does not mandate sector-specific controls. Its main recommendation is the *Rotemberg decomposition* -- a transparency tool that lets the reader see which sectors drive the result and judge each share's exogeneity individually.

- **Borusyak, Hull & Jaravel (2022).** Identification runs through **shock exogeneity** conditional on a control set. The required set is whatever functions of shares are needed to make shocks orthogonal to errors. The framework accommodates muni-level scalars (e.g., the *sum of shares*, used as the "incomplete shares" diagnostic) and does not require disaggregated sector-by-sector controls.

The relevant question is therefore which conditioning set makes the alignment-turnover shocks plausibly exogenous -- not whether to mechanically replicate D9's sector-level granularity at the muni level.

### Decomposing the instrument variation

To see what each candidate control absorbs, decompose the within-muni instrument change (suppressing tier ell):

```
Delta Z_jmt  = sum_p Delta w_jmp,t * Align_mp,t-1   (baseline-update component)
             + sum_p w_jmp,t-1 * Delta Align_mpt    (alignment-turnover component)

Delta EC_jmt = sum_p Delta w_jmp,t                  (baseline-update component only)
```

Conditioning on EC_jmt removes the **baseline-update component** of Z and leaves the **alignment-turnover component** intact -- the BHJ-clean piece, the variation driven by electoral turnover at predetermined exposures.

Two implications:

1. **Cycle-specific baselines (D3 primary).** Sector-specific EC removes a non-trivial slice of Z's variation but not all of it. It tightens identification *if* the baseline-update component is suspect (e.g., firms re-sorting across parties in anticipation of cycles), and dilutes power *if* it is not.

2. **2002-fixed baselines (R2 robustness).** Delta w = 0, so EC_jmt is muni-time-invariant and absorbed entirely by muni FE. Sector-specific EC adds nothing beyond fixed effects under R2; the over-control concern vanishes.

### What threat does each control address?

The design is shock-based: alignment turnover comes from electoral cycles at three independent tiers (mayor, governor, president), driven by political factors (incumbent performance, campaign dynamics, national tides) that are most plausibly unrelated to sector-specific BNDES outcomes. If shock exogeneity holds at the muni level, no exposure control is strictly required. The case for adding controls depends on the threat:

| Threat | Appropriate control |
|--------|---------------------|
| Permanent political connectedness drives muni GDP trajectories | Muni FE (already in spec) |
| Aggregate political connectedness varies over time and is correlated with both shock magnitude and GDP | Muni-total EC^ell_mt = sum_j sum_p w_jmp,t |
| Within-muni sectoral mix of political connectedness drives sector-specific GDP shocks | Sector-specific EC^ell_jmt (4 controls) |
| Baseline window updates are endogenous | 2002-fixed baseline (R2) |

The third threat -- within-muni sectoral connectedness mix correlated with sector-specific GDP shocks, surviving muni FE and year FE -- is sharper and harder to motivate than the second. It requires a story about why, say, agro-aligned munis happen to have agro-specific GDP shocks in a way not absorbed by aggregate connectedness or by tier-by-cycle electoral variation. Since the outcome (log GDP) is defined at the muni level, the muni-level threat is the more natural confound to test.

### Recommendation

**Primary specification: No exposure control.** The AR test relies on shock exogeneity (BHJ shock-based inference). Muni FE absorb permanent connectedness, year FE absorb common time shocks, and the alignment-turnover variation across three tiers is the identifying source. Adding controls beyond FE is not required by the literature for this design.

**R0a robustness (Tier 1, primary sensitivity): Muni-total exposure control.** Add EC^ell_mt = sum_j sum_p w_jmp,t as a single scalar (one per tier). This tests whether the AR result survives conditioning on aggregate political connectedness -- the muni-level threat that matches the muni-level outcome. Power loss is minimal because the control is one scalar mostly absorbed by muni FE.

**R0b robustness (Tier 1, secondary sensitivity): Sector-specific exposure controls.** Add EC^ell_Agro,mt, EC^ell_Ind,mt, EC^ell_Infra,mt, EC^ell_CS,mt as four separate regressors. This addresses the within-muni sectoral-mix threat. Expect substantial power loss given cycle-step collinearity with the instruments under cycle-specific baselines.

**Cross-link to R2 (2002-fixed baseline).** Under 2002-fixed baselines, sector-specific EC is mechanically redundant with muni FE, so R2 implicitly addresses the R0b concern. If the AR result is robust to R2, the case for R0b weakens further.

### Interpretation

- AR rejects without controls and continues to reject under R0a: aggregate connectedness is not the channel; the result is consistent with sector-specific reallocation as the active mechanism.
- AR rejects without controls but fails to reject under R0a: instrument predictive power is mediated by aggregate political connectedness, not sector-specific BNDES composition. This is a *level* (how connected) rather than a *composition* (which sectors) finding.
- AR rejects under R0a but fails under R0b: combined with the cycle-step collinearity caveat, this should be interpreted as a power loss rather than a confound, especially under cycle-specific baselines.
- AR robust to R2 (2002-fixed baseline): the baseline-update channel is not driving the result; sector-specific EC is mechanically redundant; the R0b concern is largely addressed.

---

## 4. Answer to Q1: Municipality-Level vs. Pooled AR Test

### Municipality-by-municipality AR: not feasible as primary

With T = 16 years and K = 4 instruments (one per BNDES sector, mayor tier only), the municipality-specific AR test faces the following constraints:

**Degrees of freedom without year FE:** Without year FE (which would consume T - 1 = 15 df, leaving negative residual df with K = 4), the municipality-specific regression has df = T - K = 16 - 4 = 12 (the intercept is absorbed by demeaning within the municipality). This gives an F(4, 12) test. **Year FE cannot be included** in a single-municipality regression with T = 16 and K = 4: they would leave 16 - 15 - 4 < 0 denominator df. The muni-by-muni test therefore omits year FE, meaning common time shocks (national GDP trends, commodity prices, BNDES policy changes) are not absorbed and can confound the test.

Even with F(4, 12) as the best case, there are fatal problems:

1. **Power.** An F(4, 12) test at the 5% level has critical value 3.26. To detect a moderate effect (say, partial R-squared of 0.10 from the instruments), the non-centrality parameter is approximately ncp = T * (R^2 / (1 - R^2)) = 16 * 0.111 = 1.78. The power of the F(4, 12, ncp=1.78) test at alpha = 0.05 is approximately 15--20%. This is extremely low.

2. **Effective time-series variation is even worse than T = 16 suggests.** As discussed in Section 3, the levels instruments change only at electoral cycle boundaries. Each municipality has at most ~3-4 independent instrument transitions, not 16 independent observations. The F(4, 12) calculation above overstates the true degrees of freedom; the effective denominator df is closer to 3-4 cycle transitions minus K = 4, which is zero or negative. The test is not reliably estimable.

3. **Instrument zeros.** Many municipalities have fewer than 4 active BNDES sectors. If a municipality never has Industria activity, its Z^mayor_Industria column is identically zero (no within-municipality variation). The instrument matrix is rank-deficient, and the test cannot be computed with K = 4.

4. **Serial correlation.** Without year FE and with T = 16, the F-test assumes iid errors within the municipality. GDP is highly persistent (AR(1) coefficient typically 0.95+), so the effective number of independent observations is much smaller than 16. The test will be severely oversized.

5. **Interpretation.** Even if we could run 5,570 individual tests, interpreting the fraction rejecting H0 requires a multiple-testing framework (e.g., Benjamini-Hochberg). With power of ~15%, we would expect ~5% rejection under H0 and ~15% under H1 -- indistinguishable.

**Verdict: Municipality-by-municipality AR is not feasible or informative. Do not pursue.**

### Grouped AR: feasible as a heterogeneity diagnostic

Grouping municipalities into G groups and running one AR test per group is feasible when the within-group sample is large enough. Specifically, pooling N_g municipalities within group g gives T * N_g observations with N_g municipality FEs, so the denominator df is approximately T * N_g - N_g - T - K. For groups of N_g = 100 municipalities, this is 16 * 100 - 100 - 16 - 4 = 1,480 -- plenty.

**Recommended grouping strategy:**

| Grouping | # Groups | Rationale |
|----------|----------|-----------|
| By state (UF) | 27 | Geographic heterogeneity; states have different economic structures and BNDES exposure |
| By BNDES intensity quartile | 4 | Tests whether the AR result differs between heavy and light BNDES recipients |
| By population quartile | 4 | Tests whether the result differs for large vs. small municipalities |
| By economic structure (dominant sector) | 4 | Groups munis by their dominant BNDES sector |

**Implementation:** Run the full reduced-form regression within each subgroup and compute the Wald test. Report the K = 4 (or 8) df F-statistic and p-value for each group. Present as a table or figure.

**Multiple testing adjustment for state-level grouped tests:** With 27 state-level tests, the probability of at least one spurious rejection at alpha = 0.05 is 1 - (0.95)^27 = 0.75. Two approaches:

1. **Benjamini-Hochberg adjustment:** Apply the BH procedure to the 27 p-values to control the false discovery rate at 5%. Report both raw and adjusted p-values.
2. **Descriptive framing (recommended):** Present the distribution of F-statistics across states (histogram or quantile table) rather than counting rejections. This avoids the multiple-testing problem entirely and provides a richer picture of geographic heterogeneity. Report the median, interquartile range, and fraction above the F(4, df) critical value, without interpreting individual rejections.

**This is a heterogeneity diagnostic, not the primary test.** The primary test is the pooled AR.

### Pooled AR: the primary specification

The pooled AR test uses all ~5,570 municipalities and ~89,000 muni-years. With municipality FE and year FE absorbed, identification comes from within-municipality over-time variation in the instruments -- specifically, from cross-municipality heterogeneity in how instruments change at electoral cycle boundaries. Clustering at the municipality level accounts for serial correlation.

Effective sample size for inference: ~5,570 clusters (municipalities), K = 4 to 8 instruments. This gives an F(4, 5566) or F(8, 5562) test with excellent power for any economically meaningful effect.

---

## 5. Answer to Q2: Municipalities with Incomplete Sector Coverage

### The problem

The 4 BNDES macro-sectors are Agropecuaria, Industria, Infraestrutura, and Comercio e Servicos. Many municipalities have zero BNDES activity in some sectors across the entire 2002--2017 period. For these municipalities, the corresponding sector instrument Z^ell_jmt is identically zero within the municipality (zero baseline exposure means zero instrument, regardless of alignment).

### What happens mechanically

In the pooled regression with municipality FE:

```
log(GDP_mt) = alpha_m + delta_t + gamma_1 * Z_Agro_mt + gamma_2 * Z_Ind_mt
              + gamma_3 * Z_Infra_mt + gamma_4 * Z_CS_mt + epsilon_mt
```

If municipality m has zero Industria across all years, then Z_Ind_mt = 0 for all t within m. After demeaning (absorbing alpha_m), the demeaned Z_Ind_mt is still zero. This municipality contributes nothing to the identification of gamma_2 -- it adds a row of zeros to the demeaned instrument matrix for the Industria column.

**This is not a problem for estimation.** OLS handles zero-variation columns gracefully: the coefficient gamma_2 is identified entirely from municipalities that have non-zero Industria instrument variation. The zeros add no information but also do no harm.

**It is a potential problem for the AR test interpretation.** The joint test H0: gamma_1 = gamma_2 = gamma_3 = gamma_4 = 0 tests all four coefficients simultaneously. But gamma_2 is identified only from the subset of municipalities with active Industria. If this subset is small, gamma_2 is imprecisely estimated, and the joint test may fail to reject simply because one poorly identified coefficient drags down the F-statistic.

**Cluster-count nuance:** Municipalities with identically-zero instrument columns for a given sector contribute zero to the numerator of the coefficient estimate but still count as clusters in the cluster-robust variance calculation. If many clusters have zero instrument variation for a particular sector, the effective number of clusters identifying that sector's coefficient is smaller than the reported cluster count of ~5,570. This makes the cluster-robust Wald test slightly liberal for the sparsely identified instruments. With J = 4 coarse BNDES sectors, most municipalities likely have at least 2-3 active sectors, so this is unlikely to be severe. With finer classifications (J = 21 CNAE sections), it could matter. Recommend reporting the number of municipalities with non-zero within-municipality variation for each instrument column.

### Recommendations

**Primary approach: Include all municipalities, include all 4 instrument columns.** This is the most transparent and does not introduce selection. Municipalities with zero instrument variation for a given sector simply do not contribute to that sector's coefficient. The joint test pools information across sectors.

**Diagnostic: Report the individual t-statistics for each gamma_j alongside the joint test.** If the joint F-test fails to reject but one or two individual sectors have large t-statistics, this suggests the non-rejection is driven by weak identification of the remaining sectors, not by the absence of an economic effect.

**Robustness: Restrict to municipalities with all 4 sectors active.** Define "active" as having at least one non-zero observation in Z^mayor_jmt across all 4 BNDES sectors. This subsample is smaller but each municipality contributes variation to all 4 instruments. Compare the AR test result on this subsample to the full sample.

**Robustness: Sequential (sector-by-sector) tests.** Run J separate regressions, each including only one sector's instrument:

```
log(GDP_mt) = alpha_m + delta_t + gamma_j * Z_j_mt + epsilon_mt
```

and test H0: gamma_j = 0 for each j separately. This avoids the joint-test power dilution. Report with Bonferroni or Holm correction for J = 4 comparisons.

**Do NOT:** Drop municipalities with missing sectors from the sample -- this introduces selection on BNDES sectoral diversification, which correlates with municipality size and economic complexity.

---

## 6. Answer to Q3: Functional Form

### The AR test is a reduced-form regression

The AR test regresses Y directly on Z and tests joint significance. There is no first stage, no endogenous variable on the RHS. So the functional form question is: what is Y, and what is Z?

### Left-hand side: log(GDP_mt) or log(GDP_pc_mt)

**Recommendation: log(GDP_pc_mt) as primary, log(GDP_mt) as robustness.**

Rationale:
- With municipality FE, log(GDP_mt) and log(GDP_pc_mt) differ by log(pop_mt). If population is approximately fixed within a municipality over 16 years (or grows at a stable rate), the two are equivalent up to a trend absorbed by the FE.
- log(GDP_pc_mt) is the standard dependent variable in the growth/development literature. It directly measures per-capita welfare.
- GDP per capita is more interpretable: a one-unit increase in a sector instrument (approximately a full shift from unaligned to aligned) is associated with a 100*gamma_j percent change in GDP per capita.
- Risk: population denominators can be noisy (intercensal interpolation). log(GDP) avoids this noise.

**Do NOT use:** GDP levels (non-log). GDP varies enormously across municipalities (~1,000x range). A levels specification would be dominated by Sao Paulo and other megacities. Log is essential for normalizing the scale.

**Do NOT use:** GDP growth rates (Delta log GDP). First-differencing removes municipality FE but introduces MA(1) errors if the level error is serially correlated. With the within-FE estimator already removing the permanent component, first-differencing is unnecessary and reduces efficiency.

### Right-hand side: the instruments

The instruments Z^ell_jmt are sector-level shift-share objects:

```
Z^ell_jmt = sum_p w^ell_jmp,t * Align^ell_mpt
```

These are bounded in [0, 1] by construction (since w^ell_jmp,t <= 1 and Align is binary). No log transformation is needed or appropriate for the instruments.

In the municipality-level regression (wide format), each sector's instrument enters as a separate regressor. With K = 4 BNDES sectors and mayor tier only:

```
log(GDP_pc_mt) = alpha_m + delta_t + gamma_Agro * Z^M_Agro,mt
                 + gamma_Ind * Z^M_Ind,mt + gamma_Infra * Z^M_Infra,mt
                 + gamma_CS * Z^M_CS,mt + epsilon_mt
```

### Additional controls?

**No controls beyond FE in the primary specification** (see Section 3.1 for the exposure-control discussion). The AR test is a reduced-form test: the instruments should be exogenous given the FE. Adding controls risks conditioning on post-treatment variables or bad controls.

**R0 robustness: Include sector-specific exposure controls.** See Section 3.1.

**Robustness: Include total municipality employment (log).** This absorbs scale effects and focuses the test on the compositional channel. However, total employment may itself respond to political alignment (employment F-stats up to 265!), making it a bad control. Include as sensitivity only.

**Volume control: total BNDES disbursements normalised by initial municipal GDP (per D24).** The volume channel is operationalised as the unit-free ratio $\text{bndes\_total}_{mt} / \text{gdp}_{m,0}$ — current-year total BNDES disbursement to municipality m divided by initial-period municipal GDP. Including this ratio in the second stage partials out the aggregate level effect so $\beta$ identifies the marginal GDP effect of compositional reallocation holding the level of BNDES activity fixed. The earlier guidance "do not control for total BNDES disbursements" (D10 original phrasing) has been superseded by D24/A10: under the new framing, the volume term is *required* in the second stage to isolate the composition channel from the volume channel. Whether the volume term enters exogenously (OLS) or is itself instrumented — total BNDES remains politically endogenous — is the open question A10. The specification of the volume control (ratio vs. levels with separate scaling, choice of denominator, etc.) is subject to revision after theory/math review of the econometrics.

### Simplex constraint considerations

When using all J sectors as instruments, the instruments are NOT mechanically collinear at the municipality level. The simplex constraint sum_j s_jmt = 1 applies to the endogenous variable (credit shares), not to the instruments. The instruments Z^ell_jmt do not sum to any fixed constant across sectors within a municipality-year because the baseline exposures w^ell_jmp,t are heterogeneous across sectors and do not sum to any fixed quantity.

Therefore, all J = 4 instrument columns can be included simultaneously without dropping one for identification. This is a key difference from the first-stage specification where one must drop the largest sector when the LHS is delta_s_jmt.

---

## 7. Implementation Sketch

### Data objects needed

All are already built by the existing pipeline:

| Object | Script | Path | Status |
|--------|--------|------|--------|
| Panel B (muni x year) | 41 | `data/processed/muni_panel_for_regs.qs2` | Exists |
| Panel B grouped | 41 | `data/processed/muni_panel_for_regs_grouped.qs2` | Exists |
| Panel A (muni x sector x year) | 41 | Built within script 41 | Exists |
| Sector instruments | 34 | `data/processed/instruments_sector.qs2` | Exists |
| GDP (deflated) | 41 | Column `log_gdp_pc` in Panel B | Exists |
| BNDES sector instruments (wide) | 41 | Columns `Z_*_A`, `Z_*_B`, etc. in Panel B | Exists |

### New code needed

A new script should be created at `explorations/anderson_rubin/ar_baseline.R` (following the exploration protocol). This script:

1. Loads Panel B (muni x year) with `bndes_sector` instruments in wide format.
2. Runs the primary reduced-form regression:
   ```r
   mod_ar <- feols(log_gdp_pc ~ Z_mayor_coalition_cycle_specific_Agro
                   + Z_mayor_coalition_cycle_specific_Ind
                   + Z_mayor_coalition_cycle_specific_Infra
                   + Z_mayor_coalition_cycle_specific_CS
                   | muni_id + year,
                   data = dt, vcov = ~muni_id)
   ar_stat <- fixest::wald(mod_ar, keep = "^Z_")
   ```
3. Runs variants: (a) mayor only, (b) mayor + governor, (c) levels vs. changes instruments, (d) log_gdp vs. log_gdp_pc, (e) with and without exposure controls.
4. Runs the grouped AR tests (by state, by BNDES intensity quartile).
5. Saves results to `explorations/anderson_rubin/output/`.

**Adaptation from script 54:** Script 54 already implements the reduced-form table (Table 4) with sector-specific instruments. The AR test is simply the Wald test that script 54 already computes. The new exploration script can reuse most of the logic but reorganize output for the AR-focused narrative.

**Key code gap (BLOCKER):** Script 54 uses `sector_group` (11 groups) or `cnae_section` (21 sections) but NOT `bndes_sector` (4 macros). The exploration script **cannot run** without resolving this. Options:
- Add `--sector-var=bndes_sector` support to the pipeline (scripts 31, 34, 41), OR
- Build the wide-format BNDES-sector instrument columns in the exploration script by collapsing Panel A from `sector_group` to `bndes_sector` level.

The latter is simpler for exploration phase but must be done before any AR test can be computed. Script 41 already handles sector-var configuration; check whether `bndes_sector` is wired through.

---

## 8. Robustness Plan

Ordered by priority. Each robustness check addresses a specific threat.

### Tier 1: Must-run (report in main text or primary appendix)

| # | Check | Threat addressed | Spec change |
|---|-------|-----------------|-------------|
| R0a | Muni-total exposure control | Aggregate political connectedness as muni-level confounder of GDP (matches the muni-level outcome) | Add EC^ell_mt = sum_j sum_p w_jmp,t as a single scalar (one per tier); compare AR F-statistic |
| R0b | Sector-specific exposure controls | Within-muni sectoral mix of political connectedness driving sector-specific GDP shocks (Borusyak-Hull-Jaravel 2022, Goldsmith-Pinkham-Sorkin-Swift 2020 with sector-specific shares) | Add EC^ell_Agro,mt, EC^ell_Ind,mt, EC^ell_Infra,mt, EC^ell_CS,mt; expect power loss under cycle-specific baselines (collinearity); mechanically redundant under R2 |
| R1 | Changes instruments (dZ) instead of levels (Z) | Timing of treatment: levels spread across term vs. inauguration-only changes | Replace Z with dZ; expect fewer non-zero obs |
| R2 | 2002-fixed baseline instead of cycle-specific | Endogeneity of cycle-specific baselines (firms sorting into parties in response to anticipated elections) | Swap baseline; compare F and p-values |
| R3 | Add governor tier (mayor + governor) | Tests whether state-level alignment contributes independent information | Expand K from 4 to 8 |
| R4 | log(GDP) instead of log(GDP_pc) | Population denominator measurement error | Swap LHS |
| R5 | Restrict to munis with all 4 sectors active | Incomplete instrument matrix diluting power | Subsample; compare AR statistic |
| R6 | Drop 2003 cycle entirely | No pre-election baseline for 2003 election cycle | Already implemented (D4) but verify |

### Tier 2: Should-run (report in appendix)

| # | Check | Threat addressed |
|---|-------|-----------------|
| R7 | Party-level alignment instead of coalition | Coalition definition may be too broad |
| R8 | Sector-by-sector individual tests (4 separate regressions) | Joint test power dilution from weakly identified sectors |
| R9 | Control for total employment | Scale effects vs. composition effects |
| R10 | Single-municipality firms only | Multi-muni firms (30% of employment) may blur municipality assignment |
| R11 | State-level clustered SE (instead of municipality) | Spatial correlation across municipalities within states (caveat: only 27 clusters; see Carter-Schnepel-Steigerwald 2017 for few-cluster concerns) |
| R12 | Grouped AR by state (27 tests) | Geographic heterogeneity: do some states drive the result? |
| R13 | Grouped AR by BNDES intensity quartile | Test whether effect concentrates among heavy BNDES recipients |
| R14 | Conley spatial HAC standard errors | Spatial correlation in GDP shocks across nearby municipalities; complement to state-level clustering without the few-cluster problem |
| R15 | Binary baseline exposure | Use extensive-margin baseline (tilde{omega}) | Tests sensitivity to baseline definition |

### Tier 3: Stress tests (Phase 4)

| # | Check | Threat addressed | Method |
|---|-------|-----------------|--------|
| R16 | FAR (Fractionally Resampled AR) | Near-but-not-exact exogeneity of instruments | Fractional resampling of instruments; conservative p-value |
| R17 | Cluster Jackknife AR | Serial correlation undermining cluster-robust inference | Leave-one-cluster-out AR statistic |
| R18 | RJAR with 21 CNAE sections | Many-instrument distortion when K > 20 | Mikusheva-Sun (2022) implementation |
| R19 | RJAR with 12 sector x size-bin categories | Intermediate K between 4 and 21 | Same as R18 |
| R20 | Conditional subvector AR | Test one sector at a time while treating others as nuisance endogenous | Requires conditioning on nuisance parameters |

---

## 9. Falsification Tests

### What should NOT show effects

| # | Test | Null if instruments are valid | Data source |
|---|------|------------------------------|-------------|
| F1 | Federal transfers as LHS | Instruments should not predict transfers; transfers are an alternative channel of political favoritism that would violate exclusion | `data/processed/transfers_ibge.qs2` (96.3% match rate) |
| F2 | Lead instruments (Z at t+4 or t+2) | Future political alignment should not predict current GDP (pre-trends) | Construct from existing Z by shifting time index |
| F3 | Lagged GDP as LHS with current Z | If instruments predict past GDP, this suggests reverse causality or pre-existing trends | Lag log_gdp_pc by 1--2 years |
| F4 | Placebo sector assignment | Randomly permute sector labels within municipality and re-estimate | Permutation within-m |
| F5 | Municipal procurement as LHS | If available, instruments should not predict procurement spending (alternative political channel) | Not yet sourced; pending |
| F6 | Randomization inference | Permute alignment shocks across municipalities within year, preserving the cross-sectional structure | Construct permuted Z; repeat AR test B = 1000 times; compare observed AR to permutation distribution |
| F7 | Pre-period balance test | Baseline municipality characteristics (pre-treatment GDP levels, population, sectoral employment composition) should not be predicted by instruments | Regress pre-2005 averages of municipality characteristics on instruments; test joint significance |
| F8 | Non-BNDES-intensive sectors as LHS | Instruments should not predict GDP in sectors with minimal BNDES exposure | Identify sectors with near-zero BNDES take-up |

### Interpretation guidance

- F1 (transfers): If instruments predict transfers, the exclusion restriction is violated -- alignment affects GDP through transfers, not just BNDES. This would undermine the AR test interpretation but not necessarily the AR test validity (the test would still tell us whether the instruments predict GDP, just not through which channel).
- F2 (leads): If lead instruments predict current GDP, there is a pre-trend concern. The political alignment shock is anticipating economic conditions, violating exogeneity.
- F6 (randomization inference): This provides a non-parametric p-value for the AR test that does not rely on asymptotic distribution theory. Useful because the asymptotic F(K, N-K) distribution may be a poor approximation with heterogeneous clusters.
- F7 (pre-period balance): This tests whether municipalities that experience larger instrument changes (i.e., larger alignment shifts interacted with larger baseline exposure) are systematically different in pre-treatment observables. It is not a balance test in the RCT sense (alignment is not randomly assigned), but finding no predictive power strengthens the exogeneity argument. Implementation: regress pre-2005 municipality averages of log GDP per capita, log population, employment share in each BNDES sector, and total BNDES per capita on the cross-sectional average of instruments (or the first-cycle instrument values). Report the joint F-test.

---

## 10. Referee Objection Anticipation

### Objection 1: "The instruments affect GDP through employment, not through BNDES credit"

**The threat:** Employment responds strongly to political alignment (F up to 265), while BNDES loan amounts do not (F ~ 6). This suggests alignment affects GDP through hiring/firing of politically connected workers, not through credit reallocation.

**Response:** This is a serious concern. The AR test as designed does not distinguish between channels. If gamma != 0, it could be because alignment affects GDP through employment, through transfers, through procurement, or through BNDES credit. The AR test is a joint test of all channels.

**Mitigation:** (a) Falsification test F1 on transfers to close that channel. (b) Control for total employment in a robustness check (R9) to see if the AR result survives. (c) Acknowledge that the AR test is a test of the instruments' reduced-form relevance for GDP, which is necessary but not sufficient for the BNDES-specific story. The BNDES-specific interpretation requires the exclusion restriction (instruments affect GDP only through BNDES), which is not directly testable.

### Objection 2: "With 4 instruments and 4 endogenous variables, you are just-identified -- the AR test has no power against alternatives"

**The threat:** When K = J (instruments = endogenous variables), the AR test and the 2SLS test coincide.

**Response:** In the just-identified case (K = J), the AR test statistic and the 2SLS Wald statistic are **numerically identical** -- they produce the same F-value. The advantage of the AR test is not that it gives a different answer, but that its **null distribution is exact**: the AR statistic follows F(K, N-K-n_FE) under H0 regardless of instrument strength (Finlay & Magnusson 2009). The 2SLS Wald test uses the same statistic but relies on strong-instrument asymptotics for its critical values to be valid. With our first-stage F ~ 6 (below the Stock-Yogo threshold), the 2SLS critical values are unreliable while the AR critical values remain exact. The AR framework thus provides valid inference where 2SLS does not.

Moreover, with multiple tiers (mayor + governor + president), K > J (overidentified). With K = 8 (mayor + governor, 4 sectors each) and J = 4 endogenous variables, there are 4 overidentifying restrictions. The AR test in the overidentified case is a test of both beta = 0 and the overidentifying restrictions jointly.

### Objection 3: "Municipality FE absorb most of the GDP variation -- what is left for the instruments?"

**The threat:** Municipal GDP is highly persistent (within-R-squared after absorbing muni FE is small). If the residual GDP variation after absorbing FE is mostly noise, the AR test has little power.

**Response:** This is an empirical question. Report the within R-squared of the reduced-form regression and the partial R-squared of the instruments (conditional on FE). If the instruments explain a non-trivial share of within-municipality GDP variation (say, partial R-squared > 0.001), the test has adequate power given N ~ 5,570 clusters.

Power calculation: With 5,570 clusters and K = 4 instruments, the AR test at alpha = 0.05 can detect a partial R-squared of approximately 4 / (5570 * 0.05 / qf(0.95, 4, 5570)) = 4 / (5570 * 0.05 / 2.37) ~ 4/117 ~ 0.034. This means the instruments need to explain only ~3.4% of within-municipality GDP variation for the test to reject at 5%.

### Objection 4: "The simplex constraint on BNDES shares means your test is about relative allocation, not absolute allocation"

**The threat:** Because sum_j s_jmt = 1, any increase in one sector's share must come at the expense of another. The AR test captures the effect of reallocation across sectors, not the effect of total BNDES lending.

**Response:** This is by design, not a limitation. The research question is about optimal sectoral allocation, not about the level of BNDES lending. The AR test asks: conditional on the total amount of BNDES credit flowing to a municipality, does the sectoral composition matter for GDP? This is exactly the optimality question.

Note that the instruments Z^ell_jmt do not satisfy the simplex constraint (they do not sum to a constant across sectors), so all J instrument columns can enter the regression simultaneously.

### Objection 5: "National IPCA is a poor deflator for municipality-level GDP"

**The threat:** Using a single national price index to deflate GDP across municipalities with very different price levels introduces measurement error in the dependent variable.

**Response:** (a) Classical measurement error in the LHS does not bias coefficients, only inflates standard errors. This makes the AR test conservative (less likely to reject). (b) No municipality-level deflator exists for 2002--2017. Metro IPCA covers only ~13 metropolitan areas (~55% of GDP). (c) Robustness R4 uses log(nominal GDP) to check whether deflation drives the result. (d) Municipality FE absorb permanent price-level differences; the concern is about differential inflation, which metro IPCA addresses for the metro subsample.

---

## 11. Summary of Recommendations

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Test type | Pooled AR (Wald test on reduced-form regression) | Correct size under weak instruments; pooling maximizes power |
| Endogenous variable | Sector **employment shares** `emp_share_jmt = emp_jmt / sum_j emp_jmt` (D24) | Best available proxy for the sectoral composition of local economic activity for 2002–2017; BNDES credit shares are now a mechanism check on the upstream credit-reallocation link, not the primary estimand |
| LHS | log(GDP_pc_mt) | Standard; interpretable; semi-elasticity interpretation |
| RHS (instruments) | Z^mayor_jmt for J sectors at the chosen aggregation margin (wide format); `policy_block_active × S3` is the leading D16 candidate with K = 12 if committed after D28 | Levels instruments maximize non-zero variation; AR is a Wald test on the reduced form |
| FE | muni_id + year | Standard two-way FE |
| Clustering | Municipality | Accounts for serial correlation within municipality |
| Controls | **Volume control** (total BNDES disbursements / initial muni GDP, a unit-free ratio) is required in the primary spec to isolate the composition channel from the volume channel (D24, A10 baseline approach (2)); R0a (muni-total exposure control) and R0b (sector-specific exposure controls) as Tier 1 sensitivities | Volume term partials out the aggregate level effect, leaving β as the GDP effect of compositional reallocation holding the level of BNDES activity fixed; exposure controls are separate sensitivities for shock-exogeneity threats (Section 3.1); volume specification subject to revision after theory/math review |
| Muni-by-muni | Do not pursue | T=16, K=4 gives F(4,12) with ~15% power; effective df even worse due to cycle timing |
| Grouped AR | By state (27), by BNDES quartile (4) | Heterogeneity diagnostic only; BH-adjusted or descriptive framing for 27 tests |
| Incomplete sectors | Include all munis; report individual t-stats alongside joint F; report per-instrument cluster counts | Zeros add no information but introduce no bias |
| Sector count | Start with 4 (BNDES macro); scale to 11 and 21 in Phases 3-4 | Low K maximizes power; high K requires RJAR |
| bndes_sector pipeline | **BLOCKER** -- must wire through before AR tests can run | Script 54 currently supports sector_group (11) and cnae_section (21) only |
