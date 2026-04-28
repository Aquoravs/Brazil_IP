# Anderson-Rubin Test Strategy

**Goal:** Test H₀: β = 0 (loan allocations do not affect municipality GDP) using political alignment as the instrument.

---

## Phase 1 — Baseline Setup (Start Simple)

**Model:** Regress log real GDP (per capita) on political alignment instruments (local, regional, national), controlling for municipality fixed effects, year fixed effects, and possibly total municipality employment.

**Sector granularity:** Begin with the coarse 4-sector division. This keeps the instrument count low and preserves statistical power of standard tests.

**Inference tool:** Standard Anderson-Rubin (AR) test, clustered at the municipality level.

- Valid even under weak instruments — avoids the false-positive risk of standard 2SLS t-tests
- If AR fails to reject H₀ → robust baseline evidence supporting optimal loan policies

---

## Phase 2 — Validating the Mechanisms (Transparency)

Before expanding sector definitions, establish credibility with the audience.

**Defend the exclusion restriction:**
- Run placebo regressions of alternative channels (e.g., municipal infrastructure spending, government contracts) on the political alignment instruments
- If instruments do not predict these channels, the design becomes credible
- Apply the residual prediction test (ML-based): tests whether instruments predict model residuals — a sign of misspecification

**Compute Rotemberg weights:**
- Identify which political alignments (local vs. national) and which of the 4 sectors drive the overall estimate
- Opens the "black box" of the IV strategy and provides a transparent identifying narrative

---

## Phase 3 — Scaling Up Complexity (Ideal Extensions)

Once the baseline is established, expand to finer sector divisions (20+) or size-mean classifications.

**Many-instruments problem:** Moving to 20+ sectors multiplies instrument count, entering a high-dimensional regime where standard AR tests suffer from size distortions and power loss.

**Solution — Ridge-Regularized Jackknifed AR (RJAR) test:**
- Applies regularization to filter out noise from irrelevant sectors (sectors with few or zero firms in certain municipalities)
- Maintains correct test size

**Subvector testing:** If testing one specific sector's loan allocation while treating the other 19 sectors as endogenous controls, standard AR is too conservative.

**Solution — Conditional Subvector AR test:**
- Adapts to nuisance parameters (the other sectors)
- Provides a more powerful and precise test for the sector of interest

---

## Phase 4 — Advanced Robustness (Stress-Testing)

Address the specific challenges of the 15-year panel and political instruments.

**Near-exogeneity — Fractionally Resampled AR (FAR) test:**
- Allows for a slight, local-to-zero violation of the exclusion restriction
- Provides valid, conservative inference even if political alignment mildly affects GDP through non-loan channels
- Bulletproofs findings without requiring perfect exogeneity

**Panel data persistence — Cluster Jackknife AR test:**
- 15-year panel likely exhibits serial correlation and intra-cluster dependence, which artificially shrinks standard errors
- Removes entire clusters (municipalities) rather than single observations during estimation
- Highly robust to panel data structures where effective sample size is reduced by clustering
- Many-instrument variant available for Phase 3 settings
