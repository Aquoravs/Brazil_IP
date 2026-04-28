---
title: "C6 — Alternative Employment and Production Factor Sources"
type: data-exploration-memo
status: final
date: 2026-04-21
plan: quality_reports/plans/2026-04-21-001-feat-data-exploration-c6-c7-plan.md
panel: 2002–2017, ~5,570 municipalities, join key: muni_id × year
---

# C6 — Alternative Employment and Production Factor Data Sources

## Executive Summary

The panel's current employment measure is RAIS formal employment stock only. Seven alternative or complementary sources are evaluated below. **Three are immediately actionable** with near-zero integration cost (all on `basedosdados` with `muni_id × year` keys matching the existing pipeline):

1. **RAIS unexploited variables** (Grade A) — education, age, and wage distribution of workers are already in the encrypted RAIS mount and on `basedosdados`; extracting them from the existing source adds no data access burden.
2. **CAGED** (Grade B) — monthly formal job flows since 1996, available on `basedosdados`, municipality × sector × month. Complements RAIS with turnover and net flow information; annual aggregation straightforward.
3. **INEP Censo Escolar** (Grade A) — annual school census, all municipalities, on `basedosdados`. Best proxy for local human capital supply. Directly mergeable.
4. **Pesquisa Pecuária Municipal + PAM** (Grade A) — annual agricultural production, all municipalities, on `basedosdados`. Best annual proxy for agricultural capital and productive land.

Two sources are strong for **baseline controls** but not annual variation:
5. **Censo Agropecuário** (Grade B) — two in-window observations (2006, 2017) with rich capital and land variables; useful as cross-sectional controls.
6. **Censo Demográfico** (Grade B) — two in-window observations (2000, 2010) with comprehensive employment, education, and age; useful as baseline controls.

One source is **not feasible** for municipality-level panel analysis:
7. **PNAD/PNAD Contínua** (Grade D) — geographic identifiers in public microdata are restricted to states and metropolitan capitals; municipality-level aggregation not possible for the full 5,570-municipality panel.

### Ranked Table

| Rank | Source | Type | Annual? | Muni Coverage | Feasibility | basedosdados |
|------|--------|------|---------|---------------|-------------|--------------|
| 1 | RAIS (unexploited vars) | Admin | Yes | Formal sector, all munis | **A** | Yes (`br_me_rais`) |
| 2 | INEP Censo Escolar | Admin | Yes | All munis | **A** | Yes (`br_inep_censo_escolar`) |
| 3 | PPM + PAM | Admin | Yes | All munis | **A** | Yes (`br_ibge_ppm`, `br_ibge_pam`) |
| 4 | CAGED | Admin | Monthly→annual | All munis (formal) | **B** | Yes (`br_me_caged`) |
| 5 | Censo Agropecuário | Census | Decennial | All munis w/ agriculture | **B** | Yes (`br_ibge_censo_agropecuario`) |
| 6 | Censo Demográfico | Census | Decennial | All munis | **B** | Yes (microdata) |
| 7 | PNAD / PNAD Contínua | Household survey | Annual / Quarterly | States + metros only | **D** | Yes (but geographic limitation fatal) |

---

## Evaluation Criteria

Sources are scored on:
1. **Geographic coverage** — fraction of 5,570 municipalities covered
2. **Temporal coverage** — overlap with 2002–2017 panel window
3. **Variable relevance** — employment, education, age, sector, capital, land
4. **Access difficulty** — public download / BigQuery / restricted access
5. **Merge complexity** — join key compatibility with existing `muni_id × year` panel

**Feasibility grades:**
- **A** — Directly mergeable with existing panel, minimal effort
- **B** — Mergeable with moderate effort (crosswalk, cleaning, or temporal interpolation)
- **C** — Partial coverage, requires imputation or subsample analysis
- **D** — Infeasible for current panel design

---

## Part I — Employment Data Sources

### Source Card: RAIS (Unexploited Variables)

**Type:** Annual employer administrative survey (already in pipeline)
**Coverage years:** 2002–2017 ✓ (full panel window)
**Municipality coverage:** All municipalities with at least one formal establishment (~5,200+ munis)
**Key variables currently extracted:** Employment stock (count of formal workers)
**Unexploited variables in RAIS:**
- Education level of workers (grau de instrução: 8 categories from illiterate to graduate)
- Age bracket of workers (faixa etária)
- Average wage (salário médio / mediana)
- Wage distribution (percentiles)
- Tenure length distribution
- Share of workers by sector (CNAE 2-digit)
- Share of workers by occupation (CBO)

**Access method:** Encrypted RAIS mount (already used by script 22) OR `basedosdados` BigQuery table `br_me_rais.microdados_vinculos`
**basedosdados:** Yes — `basedosdados.br_me_rais.microdados_vinculos` covers 2002–2020+
**Integration cost:** Very low — existing script 22 already reads RAIS; adding education/age variables is a column expansion only
**Feasibility grade:** **A**

**Recommendation:** Extract at minimum: mean education level and age distribution by municipality×year. These directly address the advisor's request for labor quality proxies and are the lowest-cost variables to add.

---

### Source Card: CAGED (Cadastro Geral de Empregados e Desempregados)

**Type:** Monthly administrative record of formal-sector job creation/destruction
**Coverage years:** January 1996–December 2019 (old CAGED); January 2020+ (new eSocial-based CAGED)
→ Full coverage of 2002–2017 panel window ✓
**Municipality coverage:** All municipalities with any formal employment activity
**Key variables:**
- Monthly admissions (admissões) and separations (desligamentos) by muni × sector × occupation
- Net employment change (saldo = admissões − desligamentos)
- Employment stock (estoque acumulado)
- Sector (CNAE 2-digit), occupation (CBO), wage, age bracket, education level, gender
- Reason for separation (dismissal type)

**Access method:**
- `basedosdados.br_me_caged.microdados_antigos` (1996–2019, old methodology)
- `basedosdados.br_me_caged.microdados_movimentacao` (2020+, new eSocial)
- Ministry of Labor portal: `pdet.mte.gov.br/microdados-rais-e-caged`
**basedosdados:** Yes — both old and new CAGED tables available
**Integration cost:** Low — BigQuery query to aggregate to annual muni×year, then left_join. Monthly frequency collapses to annual stock or net flow easily.
**Feasibility grade:** **B** (slightly lower than A because annual aggregation decision has nuance: stock vs. flow vs. net change)

**Value added over RAIS:** CAGED records monthly flows whereas RAIS is an annual snapshot. CAGED captures within-year employment dynamics (seasonality, cyclical adjustment). It also provides slightly different sectoral coding (CNAE classification) which may catch firms that changed status between RAIS reference dates.

**Caveat:** CAGED and RAIS can show divergent totals for the same municipality×year because they measure different things (flows vs. stock) and have different compliance incentives. Do not directly sum them.

---

### Source Card: PNAD / PNAD Contínua (IBGE)

**Type:** Household survey
**Old PNAD:** Annual, 1992–2015. **PNAD Contínua:** Quarterly since 2012, annual since 2013.
**Coverage years for PNAD Contínua:** 2012–present (only 2012–2017 overlaps our panel window)
**Coverage years for old PNAD:** 1992–2015 (full panel window, but see geographic limit)

**Municipality coverage — Critical limitation:**
Public microdata files identify only: (1) states (UF), (2) metropolitan regions and their capital municipalities, (3) "resto da UF" (rest of state) as a residual group. Specific non-capital municipality identifiers are **not released** in public microdata due to IBGE confidentiality rules. This applies to both old PNAD and PNAD Contínua.

→ For PNAD Contínua: data is published for Brazil, 5 major regions, 27 states, 27 capital municipalities, and 20 metropolitan regions. The ~5,500 non-capital municipalities are **not identifiable**.
→ For old PNAD: similar restriction; municipality identifiers suppressed.

**Key variables:** Employment rate, informality, education level (all categories), age, sector, income, hours worked
**Access method:** IBGE microdata portal; `PNADcIBGE` R package; DataZoom (PUC-Rio)
**basedosdados:** Yes, but geographic limitation applies regardless of access channel
**Feasibility grade:** **D** — geographic restriction is fatal for the municipality panel

**Possible use:** PNAD can inform state-level robustness checks or provide national-level informality rates as controls. Cannot be used to construct municipality×year employment variables for the full panel.

---

### Source Card: Censo Demográfico (IBGE)

**Type:** Decennial census
**Coverage years in panel window:** 2000 and 2010 (only 2 points)
**Municipality coverage:** All 5,570 municipalities, full enumeration
**Key variables:**
- Employment status (employed/unemployed/inactive) by age, gender, education, sector
- Informality (workers without formal contracts)
- Average wage and income by municipality
- Education levels (from illiterate to graduate)
- Age distribution of working-age population
- Migration (birthplace, 5-year migration)

**Access method:** IBGE microdata portal; `basedosdados` (aggregated tables); DataZoom/PUC-Rio
**basedosdados:** Yes — both 2000 and 2010 censuses in BigQuery
**Integration cost:** Moderate — decennial data needs to be joined as cross-sectional controls (year = 2000 or 2010), not as annual panel variation
**Feasibility grade:** **B** — not useful for annual identification but excellent for baseline controls and 2000→2010 first-differences analysis

**Recommended use:** (a) Validate RAIS coverage against total employment; (b) Provide informality rates as controls; (c) Construct pre-period employment composition variables for heterogeneous effects analysis.

---

## Part II — Production Factor Data Sources

### Source Card: Censo Agropecuário (IBGE)

**Type:** Agricultural census
**Coverage years in panel window:** 2006 and 2017 (2 points)
→ 1995 also available but outside main window
**Municipality coverage:** All municipalities with agricultural establishments (virtually all)
**Key variables:**
- Total agricultural area (ha) by land use type (lavouras, pastagens, matas, etc.)
- Productive land area (area plantada, área colhida)
- Agricultural capital: machinery count (tractors, harvesters), irrigation, silos
- Livestock numbers by type
- Number of agricultural establishments and workers
- Financing access (PRONAF, etc.)

**Access method:**
- IBGE SIDRA (aggregated tables by municipality)
- `basedosdados.br_ibge_censo_agropecuario` — available ✓
- IBGE microdata (establishment-level)
**basedosdados:** Yes — `basedosdados.br_ibge_censo_agropecuario`
**Integration cost:** Moderate — decennial; must use as level controls (2006) or change controls (2017−2006)
**Feasibility grade:** **B**

**Important methodological note:** The 2006 and 2017 censuses use different reference periods (calendar year vs. crop year) and include different land-use categories. IBGE recommends specific adjustments when comparing across years. This limits clean panel variation but does not preclude use as controls.

**Recommended use:** Agricultural land area and machinery as productive land / capital proxies in 2006 and/or as pre-period heterogeneity. Particularly valuable for municipalities where agriculture is the primary economic activity.

---

### Source Card: FINBRA/SICONFI (Tesouro Nacional)

**Type:** Annual municipal budget administrative data
**Coverage years:** FINBRA: 1989–2012; SICONFI: 2013–present → full panel window ✓
**Municipality coverage:** ~5,000–5,500 municipalities (coverage improves over time; pre-2013 may have ~10% missing)
**Key variables:**
- Capital expenditure (despesas de capital / investimentos) — public capital formation proxy
- Current expenditure (despesas correntes)
- Personnel expenditure (folha de pagamento)
- Transfers received (FPM, ICMS-cota, SUS, FUNDEB)
- Revenue by source (IPTU, ISS, FPM)
- Debt and fiscal balance

**Access method:**
- `basedosdados.br_me_siconfi.*` — SICONFI tables available ✓
- Tesouro Nacional open data portal (direct download)
- FINBRA portal (`tesourotransparente.gov.br`)
**basedosdados:** Yes — SICONFI on `basedosdados`; FINBRA partially available (1989–2012)
**Integration cost:** Low — pipeline already uses SICONFI/FINBRA for transfers (script 41); capital expenditure variables not yet extracted
**Feasibility grade:** **A/B** — Annual and mostly complete; slight degradation before 2013 due to FINBRA→SICONFI transition

**Recommended use:** Capital expenditure as proxy for public capital accumulation. This is likely the most feasible capital stock proxy available at annual municipal frequency. Note: captures public investment only, not private capital.

---

### Source Card: INEP Censo Escolar (Educação Básica)

**Type:** Annual administrative census of schools
**Coverage years:** 2000–present → full panel window ✓
**Municipality coverage:** All municipalities with at least one school (~5,570, essentially complete)
**Key variables:**
- Total school enrollment by educational level (fundamental, médio, EJA)
- Teacher count by qualification level
- School infrastructure: computer labs, libraries, sanitation, internet access
- School type (public federal/state/municipal vs. private)
- Class size (students per class)
- Dropout and flow rates (available in separate flow tables)

**Access method:**
- `basedosdados.br_inep_censo_escolar.*` — available ✓
- INEP microdata portal (`gov.br/inep`)
**basedosdados:** Yes — `basedosdados.br_inep_censo_escolar`; note the matricula (enrollment) table is partitioned by year and state (>90GB) — filter by state when querying
**Integration cost:** Low — municipality×year join, same as existing pipeline
**Feasibility grade:** **A**

**Recommended use:** School enrollment rate (enrollment / population 6–17) and teacher qualification share as human capital supply proxies. These are direct measures of local human capital investment and may partially instrument for future labor quality.

---

### Source Card: Pesquisa Pecuária Municipal (PPM) + Produção Agrícola Municipal (PAM)

**Type:** Annual surveys of agricultural/livestock production
**Coverage years:** Annual, 1970s–present → full panel window ✓
**Municipality coverage:** All municipalities (PPM covers those with any livestock; PAM covers those with crop production — together near-universal)
**Key variables — PPM (livestock):**
- Cattle, pigs, poultry, sheep, goat, horse, buffalo head counts
- Milk, egg, honey production quantities and values

**Key variables — PAM (crops):**
- Area planted and harvested by crop type (ha)
- Production quantity (tonnes) and value (R$) by crop
- Covers temporary crops (soy, corn, sugarcane, etc.) and permanent crops (coffee, orange, etc.)

**Access method:**
- `basedosdados.br_ibge_ppm` — PPM ✓
- `basedosdados.br_ibge_pam` (also listed as `fc403b40` dataset) — PAM ✓
- IBGE SIDRA directly
**basedosdados:** Yes — both PPM and PAM on `basedosdados`
**Integration cost:** Very low — annual muni×year keys, BigQuery join
**Feasibility grade:** **A**

**Recommended use:** Planted area (PAM) as proxy for productive land; livestock total value as agricultural capital proxy. The annual frequency and full municipality coverage make these the best available proxies for productive land without waiting for a decennial census.

---

## Merge Assessment

| Source | Join Key | Annual? | Muni Coverage | basedosdados | Integration Cost | Grade |
|--------|----------|---------|---------------|--------------|-----------------|-------|
| RAIS (unexploited vars) | `muni_id × year` | Yes | Formal sector (~98% munis) | Yes | Very low | **A** |
| INEP Censo Escolar | `muni_id × year` | Yes | All munis | Yes | Low | **A** |
| PPM + PAM | `muni_id × year` | Yes | All munis | Yes | Low | **A** |
| FINBRA/SICONFI | `muni_id × year` | Yes | ~95% munis | Yes (SICONFI) | Low | **A/B** |
| CAGED | `muni_id × month → agg to year` | Monthly | All munis (formal) | Yes | Low | **B** |
| Censo Agropecuário | `muni_id × census year` | Decennial | ~All munis w/ agro | Yes | Moderate | **B** |
| Censo Demográfico | `muni_id × census year` | Decennial | All munis | Yes | Moderate | **B** |
| PNAD / PNAD Contínua | State × metro only | Annual / Quarterly | States + metros | Yes | N/A (infeasible) | **D** |

---

## Recommendations for Advisor

**Immediately actionable (no new data access required):**

1. **Extract RAIS education and age variables** — Script 22 already reads RAIS; adding `grau_instrucao` and `faixa_etaria` aggregations is a low-cost script extension. These directly address labor quality heterogeneity.

2. **Add INEP Censo Escolar** — Annual, full coverage, on `basedosdados`. School enrollment rate and teacher qualification are clean human capital supply proxies. One BigQuery query extension to script 41.

3. **Add PPM+PAM** — Annual, full coverage, on `basedosdados`. Planted area and livestock value address the productive land/agricultural capital gap. One BigQuery query extension.

**Moderate effort, high value:**

4. **Add CAGED net employment flows** — Complements RAIS stock with flow information. Annual aggregation (sum admissions/separations by muni×year) is straightforward. Useful if any robustness check varies formal employment treatment.

5. **Censo Demográfico informality rates** — Two cross-sectional observations (2000, 2010) provide informality and total employment (formal+informal). Valuable for heterogeneous effects and as pre-period controls.

**Low priority for the current panel:**

6. **Censo Agropecuário** — Rich agricultural variables but only 2006 and 2017. Best reserved for agricultural subsample analysis or as a single cross-sectional control.

7. **PNAD** — Not feasible for municipality-level panel without restricted-access microdata request to IBGE.
