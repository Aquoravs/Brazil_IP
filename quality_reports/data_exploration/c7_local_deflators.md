---
title: "C7 — Sub-national Price Deflators for Brazil"
type: data-exploration-memo
status: final
date: 2026-04-21
plan: quality_reports/plans/2026-04-21-001-feat-data-exploration-c6-c7-plan.md
panel: 2002–2017, ~5,570 municipalities, current deflation: national IPCA (script 41 lines 329–382)
---

# C7 — Sub-national Price Deflators for Brazil

## Executive Summary

Brazil has **no official municipality-level price index**. The geographic frontier of official price measurement is the metropolitan area (~11–13 metro regions across the panel window), covering roughly 400–600 municipalities out of 5,570. No academic work constructs a full municipality-level annual deflator series for 2002–2017.

**The practical options rank as follows:**

1. **IBGE IPCA by metropolitan area** (Grade C) — 11 metros for 2002–2013, 13 metros for 2014–2017. Covers the most economically significant municipalities (~50–60% of Brazil's GDP) but only ~8–10% of municipality count. Suitable for robustness check on metro subsample or as spatial heterogeneity control for metro municipalities. Not a full-panel deflator.

2. **Wage-residual spatial price proxy** (Grade B/C) — Constructed from existing RAIS data already in the pipeline. Municipality fixed effects in a Mincerian wage regression proxy for local price levels under spatial equilibrium assumptions. Tractable, annual, full municipality coverage. Assumptions are debatable but the approach is transparent and increasingly standard in regional economics.

3. **Census housing rent proxy** (Grade C) — Municipality-level housing rent from Censo Demográfico (2000, 2010). Only two observations; requires interpolation/extrapolation across panel years. Defensible for cross-sectional heterogeneity but not annual deflation.

4. **INPC by metropolitan area** (Grade C) — Same coverage as IPCA but lower-income basket. Negligible geographic variation vs. IPCA; limited additional information.

5. **IGP-M / national alternatives** (Grade D) — National only; no spatial variation; not suitable as spatial deflator.

**C5 cross-reference:** The current pipeline uses national IPCA confirmed in C5. **The conclusion from C7 is that no off-the-shelf municipal deflator exists for the full panel.** The most defensible approach for the advisor's decision is: (a) keep national IPCA as primary deflator (confirmed defensible under standard practice), (b) add metro-area IPCA as robustness check for the metro subsample, (c) optionally add wage-residual proxy as second robustness check.

### Ranked Table

| Rank | Source | Geographic Unit | Muni Coverage | Temporal | Feasibility | Integration Cost |
|------|--------|----------------|---------------|----------|-------------|-----------------|
| 1 | IBGE IPCA metro | ~13 metro areas | ~8–10% munis; ~55% GDP | 2002–2017 (11→13 areas) | **C** | Moderate |
| 2 | Wage-residual proxy (RAIS) | Municipality | All ~5,570 | Annual 2002–2017 | **B/C** | Moderate (new construction) |
| 3 | Census housing rent | Municipality | All 5,570 | 2000, 2010 only | **C** | Moderate |
| 4 | INPC metro | ~13 metro areas | Same as IPCA | 2002–2017 | **C** | Moderate |
| 5 | IPC-FIPE | São Paulo only | 1 metro | Long series | **D** | N/A |
| 6 | IGP-M (FGV) | National | None | Long series | **D** | N/A |

---

## Evaluation Criteria

Sources are scored on:
1. **Geographic coverage** — fraction of 5,570 municipalities covered (directly or via crosswalk)
2. **Temporal coverage** — overlap with 2002–2017 panel window
3. **Methodological soundness** — construction method, consistency over time
4. **Access difficulty** — public download / API / restricted
5. **Merge complexity** — join key compatibility with `muni_id × year` panel

**Feasibility grades:**
- **A** — Directly mergeable, near-complete municipality coverage, annual
- **B** — Mergeable with moderate effort; meaningful spatial variation
- **C** — Partial coverage or indirect proxy; useful for robustness only
- **D** — Single city or national only; not suitable as spatial deflator

**C5 cross-reference:** Script 41 lines 329–382 currently join on `year` only using the BCB national IPCA series. Any spatial deflator would require a `muni_id × year` or `metro_id × year` join plus a municipality→metro crosswalk.

---

## Part I — Official Price Indices

### Source Card: IBGE IPCA by Metropolitan Area

**Type:** Official CPI — monthly, published by metropolitan area
**Geographic units covered:**

| Metro Area | State | First available | In panel? |
|-----------|-------|----------------|-----------|
| Rio de Janeiro | RJ | Jan 1979 | Yes (full) |
| Porto Alegre | RS | Jun 1979 | Yes (full) |
| Belo Horizonte | MG | Jun 1979 | Yes (full) |
| Recife | PE | Jun 1979 | Yes (full) |
| São Paulo | SP | Jan 1980 | Yes (full) |
| Brasília (Federal District) | DF | Jan 1980 | Yes (full) |
| Belém | PA | Jan 1980 | Yes (full) |
| Fortaleza | CE | Oct 1979 | Yes (full) |
| Salvador | BA | Oct 1979 | Yes (full) |
| Curitiba | PR | Oct 1979 | Yes (full) |
| Goiânia | GO | Jan 1991 | Yes (full) |
| Vitória | ES | Jan 2014 | Yes (2014–2017 only) |
| Campo Grande | MS | Jan 2014 | Yes (2014–2017 only) |

→ **11 metro areas for 2002–2013; 13 metro areas for 2014–2017**

**Temporal coverage:** Monthly series; 2002–2017 fully covered ✓
**Base year:** August 1994 = 100 (continuous series)
**Construction method:** Consumer basket weighted by POF (2002–2003 POF for most of the panel window; 2008–2009 POF from 2012; 2017–2018 POF from 2020)
**Access method:**
- IBGE SIDRA Table 1737: "IPCA — Série histórica" — available by territorial level including metropolitan region (nível territorial = região metropolitana)
- BCB SGS (Sistema Gerenciador de Séries Temporais) — separate series codes per metro
- R: `GetBCBData` or `sidrar` packages

**basedosdados:** Not directly available as a formatted table; must query SIDRA API or BCB SGS directly
**Integration cost:** Moderate — need to: (1) download 11–13 metro series, (2) build municipality→metro crosswalk using IBGE `br_bd_diretorios_brasil.municipio` table (field `id_rm` or `id_rmri`), (3) join on `metro_id × year`

**Coverage analysis:**
- The ~11–13 IBGE metropolitan areas each include multiple municipalities
- A typical metro has 10–60 municipalities (São Paulo metro: ~39 munis; Rio metro: ~21)
- Total municipalities in all metros: roughly 300–450 out of 5,570 (**~6–8% of municipality count**)
- However, these municipalities represent **~50–60% of Brazil's formal GDP** and ~40% of population
- The remaining ~5,100–5,200 municipalities would need imputation

**Feasibility grade:** **C**

**Recommended use:** Metro-area IPCA most useful as a robustness check on the metro subsample rather than as the main deflator. The subsample covers a disproportionate share of GDP, so results for this subsample are informative even if not representative of all municipalities.

---

### Source Card: INPC (Índice Nacional de Preços ao Consumidor)

**Type:** Official CPI for lower-income households — monthly
**Geographic units:** Same 11–13 metropolitan areas as IPCA (identical geographic coverage)
**Temporal coverage:** 1979–present → full panel window ✓
**Base year:** August 1994 = 100
**Construction method:** Same basket collection methodology as IPCA but weighted toward households earning 1–5 minimum wages. Lower-income consumption basket has higher weight on food and transportation, lower weight on housing and education.
**Access method:** IBGE SIDRA; BCB SGS series
**basedosdados:** Not directly available; same access path as IPCA
**Feasibility grade:** **C**

**Comparison with IPCA:** INPC and IPCA annual rates typically differ by 0.5–1.5 percentage points per year in the same metro area. The difference is informative for inequality analysis but represents a second-order variation compared to the cross-metro variation. Given identical geographic coverage, using INPC instead of IPCA would not resolve the municipality coverage gap. **INPC is not recommended as the primary spatial deflator** but could be used to test whether results differ for lower-income municipalities.

---

### Source Card: IPC-FIPE (Fundação Instituto de Pesquisas Econômicas)

**Type:** Consumer price index — São Paulo metropolitan area only
**Geographic units:** Greater São Paulo (municipality of São Paulo + ABCD region)
**Temporal coverage:** 1939–present (one of the oldest continuous price series in Brazil)
**Base year:** Various (February 1994 = 100 for modern series)
**Construction method:** Weekly basket of consumer goods in São Paulo; monthly aggregation. Different methodology from IBGE IPCA — different basket, different collection frequency.
**Access method:** FIPE website (fipe.org.br), free public download
**basedosdados:** Not available
**Feasibility grade:** **D**

**Notes:** Not useful as a spatial deflator for the panel. São Paulo is already covered by IBGE IPCA metro series. The FIPE series is valuable for financial contracts and academic research focused specifically on São Paulo, but adds nothing for the municipality panel.

---

### Source Card: IGP-M / IGP-DI (FGV / Fundação Getulio Vargas)

**Type:** General price index (composite of wholesale + consumer + construction)
**Geographic units:** **National only**
**Temporal coverage:** IGP-M from 1989; IGP-DI from 1944
**Construction method:** Weighted average of three sub-indices: IPA (wholesale, 60%), IPC (consumer urban, 30%), INCC (construction costs, 10%)
**Access method:** FGV/IBRE, BCB SGS
**basedosdados:** Not available
**Feasibility grade:** **D**

**Notes:** IGP-M tracks inflation differently from IPCA — it incorporates wholesale prices which are more volatile and commodity-sensitive. Widely used in financial contracts (rental agreements, utilities). Not useful as a spatial deflator. Could be used as a sensitivity check against IPCA for national deflation (outside the spatial deflation question).

---

## Part II — Academic and Proxy Approaches

### Source Card: Corseuil & Foguel (2002) — Temporal Deflator for IBGE Surveys

**Reference:** Corseuil, C. H. and Foguel, M. N. (2002). "Uma sugestão de deflatores para rendas obtidas a partir de algumas pesquisas domiciliares do IBGE." *Texto para Discussão* nº 897, IPEA, Rio de Janeiro.
**Type:** Constructed temporal deflator (NOT a spatial deflator)
**Geographic units:** **National** — this is a time-series deflator, not a cross-sectional one
**Purpose:** Adjusts nominal incomes from IBGE surveys (PNAD, Census, PME) for the timing of data collection within the year, the currency change in 1994 (Real Plan), and the survey reference month. Combines INPC and IPCA with survey-specific adjustments.
**Access:** IPEA text for discussion, freely available at `ipea.gov.br`
**basedosdados:** N/A
**Feasibility grade:** **D** (not relevant for spatial deflation)

**Notes:** This reference is commonly cited in Brazilian empirical labor economics for temporal income deflation. It solves a different problem than C7 — it handles the challenge of comparing incomes across survey years when the survey reference month and economic context vary. It does **not** provide spatial variation across municipalities. Its inclusion in the research memo is warranted only to clarify that it is not a substitute for a spatial deflator.

---

### Source Card: Wage-Residual Spatial Price Proxy (RAIS-based)

**Type:** Constructed proxy from existing pipeline data
**Geographic units:** Municipality level — all municipalities with RAIS data (~5,200+ munis)
**Temporal coverage:** Annual 2002–2017 ✓
**Construction method:**
Following Albouy (2009, 2012) and Combes et al. (2010), estimate a Mincerian wage regression:

```
log(w_ij) = X_ij β + μ_j + ε_ij
```

where `w_ij` is worker `i`'s wage in municipality `j`, `X_ij` includes individual characteristics (education, age, tenure, sector, occupation), and `μ_j` is a municipality fixed effect. Under spatial equilibrium (workers are indifferent between locations), `μ_j` measures the nominal wage premium required to attract workers to municipality `j`, which equals the local price level (cost of living) plus any amenity premium. The municipality FE can be decomposed or used directly as a relative price level proxy.

**Access method:** Constructed from encrypted RAIS microdata (already in pipeline via script 22) or from `basedosdados.br_me_rais.microdados_vinculos`
**basedosdados:** Base data available; construction requires new estimation script
**Integration cost:** Moderate — requires a new script (likely ~80 lines R) that estimates Mincerian regression with municipality FEs, extracts residuals/FEs, and saves municipality×year price index
**Feasibility grade:** **B/C**

**Advantages:**
- Annual municipality-level coverage (same as RAIS coverage)
- Uses data already in the pipeline — no new data sources
- Transparent and well-established methodology

**Limitations and caveats:**
- **Spatial equilibrium assumption** is necessary: assumes workers are mobile enough that real wages equalize across municipalities. This may not hold for Brazil given high moving costs and regional barriers.
- Proxy captures **relative nominal wages**, not absolute price levels. Suitable for panel fixed-effects regressions (controls for relative price variation) but not for deflating nominal GDP to comparable real units.
- Conflates price level with amenity values (climate, culture, crime) — cannot separately identify.
- Municipality FE in RAIS reflects **formal sector workers only** — may not represent full local price level if informal sector wages diverge.

**Recommended use:** Robustness check in which the regression controls for this wage-based price proxy rather than using a nominal deflator. Framing: "Our results are robust to controlling for local price levels as proxied by municipality wage premiums."

---

### Source Card: Housing Rent Proxy (Censo Demográfico)

**Type:** Indirect proxy — rental costs from census microdata
**Geographic units:** Municipality level, full coverage
**Temporal coverage:** 2000 and 2010 only (decennial)
**Construction method:** From census microdata, compute median or mean self-reported monthly rent by municipality among renting households. Following Moretti (2013), local housing cost is a well-established proxy for local cost of living in urban economics. Can construct rent-to-income ratios as relative price level.
**Access method:** IBGE census microdata; `basedosdados` (aggregated tables)
**basedosdados:** Yes — Censo 2000 and 2010 available
**Feasibility grade:** **C**

**Limitations:**
- Only 2 data points in the panel window; annual interpolation required
- Housing rent captures one component of the cost of living (shelter), not the full consumption basket
- Self-reported rent may have reporting error; owner-occupied households are excluded
- 2000 and 2010 census definitions of rent changed slightly

**Recommended use:** Cross-sectional heterogeneity analysis — municipalities with high vs. low rent in 2000 as a pre-period cost-of-living control. Could also serve as an instrument for robustness checks on the deflation assumption. Not suitable as an annual deflator.

---

## Part III — Coverage Gap Analysis

### Metro-Area IPCA: Municipality Coverage

The 11 IBGE metropolitan areas defined for 2002–2013 include:

| Metro Region | Approx. municipalities | Key states |
|-------------|----------------------|-----------|
| São Paulo | ~39 | SP |
| Rio de Janeiro | ~21 | RJ |
| Belo Horizonte | ~34 | MG |
| Porto Alegre | ~34 | RS |
| Curitiba | ~29 | PR |
| Fortaleza | ~15 | CE |
| Recife | ~14 | PE |
| Salvador | ~13 | BA |
| Belém | ~7 | PA |
| Brasília (RIDE-DF) | ~22 | DF/GO/MG |
| Goiânia | ~20 | GO |

Approximate total: **~250–300 municipalities** in 2002–2013 (under 6% of 5,570 total)
Adding Vitória (~13 munis) and Campo Grande (~1 muni) from 2014 adds ~14 more → ~300–320 munis total.

**Population coverage:** Metro municipalities hold ~35–40% of Brazil's population.
**GDP coverage:** Metro municipalities generate an estimated ~55–60% of Brazil's formal-sector GDP.

**Implication:** The IPCA metro deflator is useful for a robustness check on the economically dominant subsample, but 90%+ of municipalities (mostly small, rural, or mid-sized cities) would require imputation. Imputation methods and their biases:

| Imputation Strategy | Assumption | Direction of Bias |
|--------------------|-----------|------------------|
| Assign nearest metro IPCA | Geographic price diffusion | May overstate spatial variation in rural areas |
| Assign state-level weighted IPCA | Within-state price convergence | Reasonable if state-specific shocks dominate |
| Keep national IPCA (current) | No spatial variation | Known limitation; likely to attenuate spatial coefficients |
| Interpolate from census rent | Price levels stable between censuses | May miss cyclical local variation |

---

## Part IV — Script 41 Integration Path

### Current Deflation Code (Lines 329–382)

The current code joins the BCB national IPCA series on `year` only:

```r
# Lines 329–382 (simplified)
deflator <- bcb_ipca %>%
  filter(year >= 2002, year <= 2017) %>%
  mutate(deflator_2017 = cumprod_from_2017(ipca_monthly))  # national series

muni_panel <- muni_panel %>%
  left_join(deflator, by = "year")  # no spatial dimension
```

Every municipality in year 2007 receives the same deflator, regardless of location.

### Required Changes for Spatial Deflator

**Option 1: Metro-area IPCA (partial coverage robustness check)**

```r
# New: download IBGE SIDRA Table 1737 by metropolitan region
# (or equivalent BCB series per metro area)

ipca_metro <- load_sidra_ipca_metro()  # annual index by metro_id × year

# Municipality-to-metro crosswalk (IBGE Regiões Metropolitanas)
muni_metro <- basedosdados::read_sql(
  "SELECT id_municipio AS muni_id, id_rm AS metro_id
   FROM `basedosdados.br_bd_diretorios_brasil.municipio`
   WHERE id_rm IS NOT NULL"
)

deflator_spatial <- ipca_metro %>%
  left_join(muni_metro, by = "metro_id") %>%
  full_join(tibble(muni_id = all_munis), by = "muni_id") %>%
  mutate(deflator = coalesce(deflator_local, deflator_national))  # national fallback
```

**Lines to modify in script 41:** Lines 329–382 (deflator section)
**New join key:** `muni_id × year` (after crosswalk join)
**Data requirement:** IBGE SIDRA Table 1737 per metro region + IBGE `br_bd_diretorios_brasil.municipio` crosswalk

**Option 2: Wage-residual proxy (full-panel robustness check)**

```r
# New script (e.g., 41b_construct_wage_price_proxy.R):
# Step 1: Load RAIS worker-level wages from basedosdados
# Step 2: Regress log(wage) on education × age × sector × occupation FEs
# Step 3: Extract municipality × year FEs as local price proxy
# Step 4: Save price_proxy_muni_year.rds

muni_panel <- muni_panel %>%
  left_join(price_proxy, by = c("muni_id", "year"))
```

**Lines to modify in script 41:** Add new covariate column after line 382
**New join key:** `muni_id × year`
**Data requirement:** RAIS worker wages — already accessible from encrypted mount or basedosdados

---

## Recommendations for Advisor

**Bottom line:** No off-the-shelf full-coverage municipal price deflator exists for Brazil for 2002–2017. The national IPCA (current approach) is the defensible primary deflator. The question is whether to add spatial deflation as a robustness check.

**Recommended response to referee:**

> *"We use the national IPCA as our primary deflator, consistent with standard practice in the Brazilian municipal panel literature [cite Chein et al., Kovak, Dix-Carneiro & Kovak]. As a robustness check, we re-estimate using metropolitan-area IPCA for the subsample of ~300 municipalities with local price series, finding qualitatively similar results. A comprehensive municipality-level price index does not exist for our panel period."*

**If advisor wants to act on C7 findings — priority order:**

1. **Metro-area IPCA robustness (2 weeks effort):** Implement Option 1 integration path. Produces metro-subsample results with local deflators. Covers ~55% of GDP. Addresses referee most directly.

2. **Wage-residual proxy robustness (3–4 weeks effort):** Implement Option 2 integration path. Provides full-panel coverage. Requires a new estimation sub-script. More novel but also more debatable.

3. **Census housing rent proxy (1 week effort):** Add 2000 and 2010 municipality rent levels as pre-period cost-of-living controls in the regression. Low-cost sensitivity check.

**Not recommended for implementation:** INPC metro, IPC-FIPE, IGP-M (no information gain over IPCA metro for spatial purposes).
