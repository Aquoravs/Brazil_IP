---
title: "Sector Grouping Diagnostics: Empirical Validation and Potential Refinements"
type: explore
status: active
date: 2026-03-01
---

# Sector Grouping Diagnostics

## Motivation

The current sector grouping (script 30) collapses 21 CNAE sections into 9 active groups (+1 residual XX). The first stage with grouped sectors (mayor coalition = 0.020**, muni x year FE) is weaker than the ungrouped specification (0.0282***, F = 12.4). This loss of power suggests the grouping may be collapsing meaningful variation. Before proceeding to the second stage with grouped sectors, we need empirical evidence on:

1. Whether the current groups are internally homogeneous in BNDES treatment intensity
2. Whether specific merges (especially Agriculture + Mining) destroy identifying variation
3. Whether we should aggregate further (drop sectors with negligible BNDES presence) or disaggregate selectively

### Key concern: Agriculture & Mining (AM)

Agriculture (A) and Mining (B) are merged into a single group despite:
- Different BNDES program channels (Pronaf/Moderfrota/ABC for agriculture vs. investment-bank-style for mining)
- Very different geographic concentration (agriculture is ubiquitous; mining is concentrated in MG, PA, GO)
- Different political economy (agricultural interests organized through different parties than mining)

### Literature guidance (GPS 2020, BHJ 2022/2025, AKM 2019)

The shift-share literature recommends **theory-first grouping**: the classification should reflect the level at which the policy allocation mechanism operates. Data-driven diagnostics (Rotemberg weights, N_eff, shock balance) serve as validation, not as the primary selection criterion. Specifically:

- **GPS**: Compute Rotemberg weights per sector; split dominant sectors where sub-sector IV estimates diverge; drop sectors with near-zero Rotemberg weight
- **BHJ**: Maximize N_eff = 1/HHI of aggregate exposure; exclude sectors with zero shock variation; verify shock balance at the chosen granularity
- **AKM**: Finer sectors reduce cross-regional share similarity (lower ICC), improving inference; but coarser sectors reduce many-instrument bias

### CNAE sector definition: Firm-registered (RAIS) vs. BNDES project CNAE

We use the firm's registered CNAE section from RAIS/Receita Federal consistently for both credit shares and exposure weights. This is preferred over the BNDES project CNAE because:

1. The identification channel operates at the firm level (connected owners channel credit to their firms), not the project level
2. BNDES project CNAE is only available for loan-receiving firms, which would condition on the endogenous outcome and destroy the balanced panel with zeros
3. BNDES project CNAE is potentially strategic (firms choose CNAE codes to target subsidized credit lines), introducing endogenous measurement error
4. 99.6% of firm-years map to a unique CNAE section, making the mismatch quantitatively marginal

The paper should acknowledge that if BNDES systematically allocates credit to projects outside borrowing firms' main activity, our instrument misses that channel — but this attenuates results toward zero (conservative bias).

## Plan

### Step 1: Descriptive diagnostics by CNAE section and sector group ✓ COMPLETED

**Goal**: Understand which sectors are empirically relevant for BNDES allocation across municipality-years, and quantify within-group heterogeneity.

**Script**: `diagnostics/sector_group_diagnostics.R` (implemented)

**Outputs** (tables + plots):

1a. **BNDES presence table** — For each of the 21 CNAE sections:
   - N municipalities with any BNDES credit (ever)
   - N municipality-years with positive BNDES credit
   - Mean and median BNDES share (s_mjt) conditional on positive
   - Total BNDES volume (R$ millions, 2018)
   - % of total BNDES disbursements
   - N nonzero instrument observations (proxy for instrument relevance)

1b. **Same table aggregated by sector group** — Show which groups are dominated by a single CNAE section vs. genuinely pooling across sections.

1c. **Within-AM comparison** — Agriculture (A) vs. Mining (B):
   - Geographic spread: number of distinct municipalities with BNDES > 0, by year
   - Mean BNDES share conditional on positive
   - Correlation of BNDES shares across municipalities (are they substitutes or complements?)
   - Political exposure weight distribution: compare mean w_mjp for Agriculture vs. Mining firms

1d. **Within-MS comparison** — Same for I, J, K, L, M, N:
   - Identify which sub-sections drive the group's BNDES share
   - Flag Finance (K) as potentially problematic (banks are BNDES intermediaries, not final borrowers)

1e. **Heatmap/bar chart**: BNDES share by sector group x year, showing time trends in sectoral composition

1f. **Manufacturing split distribution (CL/CH/CA)**:
   - Total BNDES volume and % share within Manufacturing
   - Number of municipalities and municipality-years with positive BNDES
   - Nonzero instrument support by subgroup
   - Year-by-year composition within Manufacturing

**Data sources**: `output/bndes_credit_shares.qs2` (ungrouped, from script 35), `output/muni_sector_panel.qs2` (Panel A), `output/sector_group_mapping.qs2`

**Key findings (2026-03-01)**:
- **1a**: Manufacturing (C) dominates with 42.4% of all BNDES, followed by Transport (H, 18.8%), Utilities/D (14.1%). Sparse sectors: O (8 muni-years), T (13), U (19).
- **1b**: AM group is 72.9% dominated by Mining (B) in volume (R$1.2B vs R$445M for Agriculture). MS group is spread: K=30%, J=27%, N=19%, M=17%.
- **1c AM split evidence**: Mining has fewer munis (1,396 vs 2,303) but 2.7x more BNDES volume. Only 1.8% of muni-years have both A and B positive (near-zero co-occurrence). Correlation of shares when both present = 0.12 (essentially independent). Instrument variance 5x larger for Agriculture. Strong case for splitting AM.
- **1d MS heterogeneity**: Finance (K) has 30% of MS BNDES but only 2.4% of muni-years positive — highly concentrated. J (Information) is 27% with broader coverage. I (Accommodation) is negligible (1%). Group is genuinely heterogeneous.
- **1e**: Sectoral composition varies dramatically across years (e.g., UCo=50% in 2003, CL=83% in 2006, Tp=59% in 2017).
- **1f manufacturing relevance check (2026-03-02)**: CH=48.7%, CL=28.6%, CA=22.7% of manufacturing BNDES volume. All three have substantial nonzero IV support (CH=17,110; CL=23,871; CA=12,870). None is economically negligible in levels.

**All outputs saved to**: `output/diagnostics/sector_grouping/`

### Step 2: Rotemberg weight decomposition ✓ IMPLEMENTED (2026-03-02)

**Goal**: Identify which sectors drive the shift-share instrument's identifying variation (GPS 2020 diagnostics).

**Method**: Compute Rotemberg weights alpha_j for each sector j in the pooled Bartik regression. The Rotemberg weight for sector j is proportional to:

$$\alpha_j = \frac{g_j' X (X'X)^{-1} \hat{\beta}_{2SLS}}{\sum_k g_k' X (X'X)^{-1} \hat{\beta}_{2SLS}}$$

where g_j is the j-th shock and X includes the shares.

In practice, use the `bartik.weight` R package (Paul Goldsmith-Pinkham's code) or compute manually as the product of:
- Sector j's first-stage contribution (partial R-squared of s_j in the first stage)
- The sector-specific IV estimate of beta_j

**Outputs**:
- Table of Rotemberg weights by sector (21 sections and grouped)
- Fraction of absolute Rotemberg weight in top 3 sectors
- Scatter: sector-specific IV estimate vs. first-stage F, sized by Rotemberg weight
- Flag sectors with negative Rotemberg weights (these pull the estimate in the wrong direction)

**Implementation note**: The `bartik.weight` package expects a specific data structure (location x time panel with sector shares as columns). Our Panel B wide format is close but may need adaptation. Alternative: manual computation following GPS Appendix equations.

**Implementation progress (2026-03-02)**:
- Added Step 2 to `BNDES/politicsregs/diagnostics/sector_group_diagnostics.R`.
- Computes Rotemberg-style decomposition for:
  - 21-section panel (`output/muni_sector_panel.qs2`)
  - grouped panel (`output/muni_sector_panel_grouped.qs2`, when available)
- New outputs in `output/diagnostics/sector_grouping/`:
  - `2a_rotemberg_weights_by_section.csv`
  - `2a_rotemberg_weights_by_group.csv` (if grouped panel exists)
  - `2b_rotemberg_top3_summary.csv`
  - `2c_sector_iv_scatter_section.pdf`
  - `2c_sector_iv_scatter_group.pdf` (if grouped panel exists)
  - `2d_manufacturing_split_diagnostics.csv` (CL/CH/CA focused check)
- Includes an explicit manufacturing split assessment heuristic:
  - `supports_3way_split`
  - `mixed_evidence`
  - `one_subsector_dominates_consider_merge`
- Executed diagnostics script end-to-end and saved outputs.
- Key empirical findings from Step 2 run:
  - Top-3 absolute signed weight share:
    - 21 sections: **79.1%**
    - grouped sectors: **82.7%**
  - Negative signed weights:
    - 21 sections: **2/21** (B, K)
    - grouped sectors: **3/9** (CH, MS, CL)
  - Manufacturing split check (within manufacturing absolute weight):
    - **CH: 78.3%** (`first_stage_f = 2.22`, `beta_sector_iv = -0.079`)
    - **CA: 21.1%** (`first_stage_f = 3.98`, `beta_sector_iv = -0.117`)
    - **CL: 0.7%** (`first_stage_f ≈ 0.00`, `beta_sector_iv = -0.003`)
  - Interpretation: the 3-way split captures meaningful heterogeneity between heavy and advanced manufacturing, but light manufacturing contributes almost no identifying variation in this first-stage decomposition.

## Candidate alternative groupings to evaluate

Based on the diagnostics above, we may consider:

| Variant | Groups | Key change | Rationale |
|---------|--------|------------|-----------|
| Current | 9 + XX | AM = A+B merged | Status quo |
| Split AM | 10 + XX | Ag (A) separate from Mi (B) | Different BNDES programs, geography, political economy |
| Split AM + collapse MS | 10 + XX | Ag, Mi separate; I+L+N merged into "Other Services", J+K+M kept as "Info, Finance & Professional" | Separates BNDES-intensive services from minor ones |
| Aggressive aggregation | 7 + XX | Merge CA into CH; merge PSO into MS | Fewer instruments, more power per instrument |

The choice among these should be guided by: (a) first-stage F-statistics, (b) Rotemberg weight concentration, and (c) economic coherence of the groups.

## Dependencies

- **Data**: `output/bndes_credit_shares.qs2`, `output/muni_sector_panel.qs2`, `output/sector_group_mapping.qs2`, `output/shift_share_instruments_sector.qs2`
- **Packages**: `data.table`, `fixest`, `ggplot2` (for diagnostic plots), optionally `bartik.weight` (for Rotemberg decomposition)
- **Scripts**: Diagnostic script is standalone; does not modify the pipeline

## References

- Goldsmith-Pinkham, Sorkin & Swift (2020), "Bartik Instruments: What, When, Why, and How," AER
- Borusyak, Hull & Jaravel (2022), "Quasi-Experimental Shift-Share Research Designs," ReStud
- Borusyak, Hull & Jaravel (2025), "A Practical Guide to Shift-Share Instruments," JEP
- Adao, Kolesar & Morales (2019), "Shift-Share Designs: Theory and Inference," QJE
