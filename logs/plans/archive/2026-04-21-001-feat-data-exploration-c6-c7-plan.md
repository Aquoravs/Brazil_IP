---
title: "feat: Data exploration — alternative employment sources (C6) and local deflators (C7)"
type: feat
status: completed
date: 2026-04-21
origin: quality_reports/referee_response_tracker.md (C6, C7)
scope: Research, evaluate, and document alternative data sources; no pipeline changes in this plan
---

# Data Exploration: Alternative Employment Sources (C6) & Local Deflators (C7)

## Overview

Two data discovery tasks from the 2026-04-17 meeting. C6 explores municipality-level employment data beyond RAIS (the sole current source) — including employment by age, sector, education, capital stock, and productive land. C7 explores whether sub-national price deflators exist to replace or supplement the national IPCA used uniformly across all municipalities. Both tasks produce ranked data-source memos for advisor review; neither modifies the pipeline.

## Problem Frame

The current muni panel (`scripts/R/4_regression_panels/41_build_muni_panel.R`) relies on two critical data inputs:

1. **Employment:** Exclusively from RAIS (formal employer survey), aggregated from firm-level records via script 22. No employment-by-age, education, informality, or capital stock data exists in the pipeline.
2. **GDP deflation:** National IPCA applied uniformly to all 5,570 municipalities (lines 329–382 of script 41). Every municipality in a given year gets an identical deflator. If local price levels differ substantially, this biases real GDP comparisons across municipalities.

The advisor wants to know what alternative data exists, how it covers the panel (2002–2017, ~5,570 municipalities), and whether it can be merged. This is pure research — deliverables are evaluation memos, not code.

## Requirements Trace

- R1. (C6) Identify and evaluate all plausible municipality-level employment data sources beyond RAIS
- R2. (C6) For each source, document: geographic coverage, temporal coverage, variable definitions, access method, and merge feasibility with existing muni×year panel
- R3. (C6) Extend search to production factor proxies: employment by age/sector/education, capital stock, productive land
- R4. (C7) Identify all sub-national price indices or deflators available for Brazil
- R5. (C7) For each deflator, document: geographic granularity, temporal coverage, update frequency, construction methodology
- R6. (C7) Assess whether any deflator can be matched to the municipality panel and what the practical coverage gap would be
- R7. Produce ranked data-source memos (one for C6, one for C7) with feasibility grades for advisor review
- R8. Cross-reference C5 finding (national IPCA confirmed) with C7 results to inform whether script 41 should be updated

## Scope Boundaries

- **In scope:** Data source research, coverage evaluation, merge feasibility assessment, ranked memos
- **Out of scope:** Downloading data, writing ingestion scripts, modifying script 41 or any pipeline code, running regressions with new data
- **If a high-quality deflator is found:** Document the integration path (which script 41 lines change, what the join key would be) but do not implement it

## Context & Research

### Current Data Architecture

| Data Type | Source | Script | Coverage | Join Key |
|---|---|---|---|---|
| Employment (firm-level) | RAIS (encrypted mount) | 22 → 41 | 2002–2017, all formal firms | `muni_id × year` |
| GDP (nominal) | IBGE PIB Municipal (.xls) | 41 (lines 202–314) | 2002–2019, all municipalities | `muni_id × year` |
| GDP deflator | BCB IPCA (national) | 41 (lines 329–382) | 1994–present, single series | `year` only |
| Population | IBGE via `basedosdados` BigQuery | 41 (lines 395–421) | Annual, all municipalities | `muni_id × year` |
| Transfers | SICONFI/FINBRA | 41 (optional) | 2002–2017 | `muni_id × year` |

### Existing Data Access Patterns

The project already uses `basedosdados` (BigQuery) for population data. This is a strong access channel for C6/C7 — Base dos Dados aggregates many IBGE datasets at municipality level and provides standardized BigQuery tables. Any new data source that exists on `basedosdados` has near-zero integration cost.

### Known Candidate Sources (from referee tracker)

**C6 — Employment alternatives:**
- PNAD Contínua (IBGE) — quarterly employment/education/age, but limited municipality coverage
- CAGED (MTE) — monthly formal employment flows (entry/exit)
- Censo Demográfico (IBGE) — comprehensive but decennial (2000, 2010)
- Censo Agropecuário (IBGE) — agricultural land and capital
- FINBRA/SICONFI — municipal fiscal data (capital proxy)
- Base dos Dados — pre-aggregated municipality panels

**C7 — Local deflators:**
- IBGE IPCA by metropolitan area (~16 metros)
- INPC by metropolitan area
- Academic constructed indices (Corseuil & Foguel, others)
- Regional cost-of-living indices from academic papers

## Key Technical Decisions

- **Deliverable format:** Markdown memos in `quality_reports/data_exploration/`, one per task (C6, C7), following a standardized evaluation template with source cards
- **Evaluation criteria:** Ranked by (1) geographic coverage relative to our 5,570 municipalities, (2) temporal coverage relative to 2002–2017, (3) variable relevance, (4) access difficulty, (5) merge complexity
- **Feasibility grading:** A/B/C/D scale where A = directly mergeable with existing panel, B = mergeable with moderate effort, C = partial coverage requiring imputation, D = infeasible for current design
- **Research method:** Web search for official IBGE/BCB/MTE documentation, `basedosdados` catalog exploration, academic paper search for constructed indices
- **No data downloads:** This plan is research-only. Any promising source gets a "how to access" section but no actual data acquisition

## Open Questions

### Resolved During Planning

- **Where do memos go?** → `quality_reports/data_exploration/c6_employment_sources.md` and `quality_reports/data_exploration/c7_local_deflators.md`
- **What's the panel time window?** → 2002–2017 (core analysis), though 2002–2019 is available for GDP
- **Does basedosdados already have employment alternatives?** → Must check; it aggregates many IBGE datasets and is already integrated in our pipeline

### Deferred to Implementation

- **Which source to prioritize for ingestion?** → Depends on advisor review of the memos
- **How to handle partial geographic coverage?** → Imputation strategies deferred until a specific source is chosen
- **Whether to use metro-area deflators as municipality proxy?** → Depends on what C7 finds about coverage

## Implementation Units

- [ ] **Unit 1: Set up exploration structure and evaluation template**

  **Goal:** Create the output directory and a reusable source-card template so both C6 and C7 memos are structured consistently.

  **Requirements:** R7

  **Dependencies:** None

  **Files:**
  - Create: `quality_reports/data_exploration/c6_employment_sources.md`
  - Create: `quality_reports/data_exploration/c7_local_deflators.md`

  **Approach:**
  Each memo uses a standardized structure: (1) Executive summary with ranked table, (2) Per-source cards with coverage matrix, access instructions, variable inventory, and feasibility grade, (3) Merge assessment against existing `muni_id × year` panel, (4) Recommendation for advisor.

  **Verification:**
  - Both files exist with skeleton structure
  - Template includes all evaluation dimensions from the Key Technical Decisions section

- [ ] **Unit 2: C6 — Research official Brazilian employment data sources**

  **Goal:** Systematically evaluate PNAD Contínua, CAGED, Censo Demográfico, and RAIS-derived alternatives for municipality-level employment coverage.

  **Requirements:** R1, R2

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `quality_reports/data_exploration/c6_employment_sources.md`

  **Approach:**
  For each source, research via web search and `basedosdados` catalog:
  - **PNAD Contínua (IBGE):** Quarterly household survey. Key question: does it publish municipality-level data, or only UF/metro? Check if microdata can be aggregated to municipality level (sample size concerns for small munis). Covers employment by age, education, sector, formality.
  - **CAGED (MTE):** Monthly administrative record of formal hirings/separations. Complements RAIS (which is annual stock). Available on `basedosdados`. Municipality × sector × month granularity. Key question: does it add information beyond RAIS, or is it redundant for annual analysis?
  - **Censo Demográfico (IBGE):** 2000 and 2010 (2022 results being released). Comprehensive employment, education, age, sector at municipality level. Key question: can decennial data be useful as baseline controls or cross-validation for RAIS?
  - **RAIS itself:** Already used, but check if there are RAIS-derived variables not currently extracted (education level of workers, age distribution, wage distribution).

  **Patterns to follow:**
  - Use `basedosdados` BigQuery catalog (`basedosdados.br_*` tables) as first lookup for each source — if it's there, the merge is nearly free since script 41 already queries BigQuery

  **Verification:**
  - Each source has a completed card with: coverage years, municipality count, key variables, access method, feasibility grade
  - At least 4 sources evaluated

- [ ] **Unit 3: C6 — Research production factor data (capital, land, education)**

  **Goal:** Evaluate data sources for non-employment production factors the advisor requested: capital stock, productive land, education levels.

  **Requirements:** R3

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `quality_reports/data_exploration/c6_employment_sources.md`

  **Approach:**
  - **Censo Agropecuário (IBGE):** 2006 and 2017. Municipality-level data on: productive land area, crop types, agricultural capital (machinery, livestock). Key question: temporal sparsity (only 2 observations in our panel window).
  - **FINBRA/SICONFI (Tesouro Nacional):** Annual municipal budget data. Capital expenditure as proxy for public capital. Available on `basedosdados` (`basedosdados.br_me_siconfi.*`). Good temporal coverage.
  - **Censo da Educação Superior / Básica (INEP):** School enrollment, teacher counts, education infrastructure by municipality. Annual. Proxy for human capital supply.
  - **Estoque de Empregos (MTE):** If available — formal employment stock by education level and age bracket at municipality level.
  - **IBGE Pesquisa Pecuária Municipal:** Annual livestock/agricultural production by municipality.

  **Verification:**
  - Each source has a completed card
  - At least 4 production-factor sources evaluated
  - Clear distinction between annual sources (directly usable) and decennial sources (baseline controls only)

- [ ] **Unit 4: C7 — Research sub-national price indices for Brazil**

  **Goal:** Identify all available sub-national price deflators and evaluate their geographic and temporal coverage relative to the municipality panel.

  **Requirements:** R4, R5

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `quality_reports/data_exploration/c7_local_deflators.md`

  **Approach:**
  - **IBGE IPCA by metropolitan area:** The national IPCA is published for ~16 metropolitan regions (São Paulo, Rio, Belo Horizonte, Porto Alegre, Curitiba, Salvador, Recife, Fortaleza, Belém, Goiânia, Brasília, Campo Grande, Aracaju, Vitória, Rio Branco, São Luís). Research exact list, temporal coverage, and whether micro-area codes can be mapped to municipalities within metros.
  - **INPC (Índice Nacional de Preços ao Consumidor):** Same metro coverage as IPCA but for lower-income basket. Check if geographic breakdown differs.
  - **IPC-FIPE:** São Paulo metropolitan area only. Limited but very long time series.
  - **Academic constructed indices:** Search for papers that construct municipality-level cost-of-living indices. Key authors: Corseuil & Foguel, Menezes-Filho, Naercio Menezes. Check NBER/SSRN/SciELO for Brazilian spatial price indices.
  - **Indirect/proxy approaches:** (a) Housing rental prices from Censo Demográfico, (b) IBGE consumer basket surveys, (c) wage-regression residuals as local price proxy. Document these as alternatives even if not direct deflators.

  **Verification:**
  - Each price index has a completed card with: geographic units, temporal coverage, base year, construction method, access
  - Coverage gap analysis: what fraction of our 5,570 municipalities would be covered directly vs. requiring imputation
  - At least 3 official indices and 2 academic/proxy approaches evaluated

- [ ] **Unit 5: C7 — Assess municipality-level matchability and integration path**

  **Goal:** For the most promising deflator(s), document exactly how they would merge with the existing panel and what the practical coverage gap would be.

  **Requirements:** R6, R8

  **Dependencies:** Unit 4

  **Files:**
  - Modify: `quality_reports/data_exploration/c7_local_deflators.md`

  **Approach:**
  - For each promising deflator, document the join key (`metro_area_id → muni_id` mapping, or `UF → muni_id`)
  - Estimate coverage: how many of the 5,570 municipalities fall within the ~16 IPCA metro areas? What fraction of the population/GDP do they represent?
  - Document the script 41 integration path: lines 329–382 currently join deflators on `year` only; a spatial deflator would need `muni_id × year` join (or `metro_id × year` with a muni→metro crosswalk)
  - Assess imputation strategy for non-metro municipalities: use state-level deflator? Use nearest metro? Use national IPCA as fallback? Document tradeoffs.
  - Cross-reference C5 finding: confirm that the current pipeline uses only national IPCA (verified) and that any change requires script 41 modification.

  **Verification:**
  - Integration path documented with specific script 41 line references
  - Coverage fraction estimated (municipalities covered / total)
  - Imputation tradeoffs documented for advisor decision

- [ ] **Unit 6: Compile ranked recommendations and finalize memos**

  **Goal:** Synthesize findings into ranked executive summaries with clear feasibility grades and advisor-ready recommendations.

  **Requirements:** R7

  **Dependencies:** Units 2, 3, 4, 5

  **Files:**
  - Modify: `quality_reports/data_exploration/c6_employment_sources.md`
  - Modify: `quality_reports/data_exploration/c7_local_deflators.md`

  **Approach:**
  - Rank C6 sources by composite score: (coverage × relevance × access ease)
  - Rank C7 deflators by: (geographic coverage × temporal coverage × methodological soundness)
  - For each memo, write executive summary with top-3 recommendations and a decision matrix
  - Flag any source that exists on `basedosdados` as "low integration cost" — this is a significant advantage given existing pipeline infrastructure
  - Note cross-connections: e.g., if PNAD Contínua provides both employment alternatives (C6) and consumption data useful for spatial price indices (C7)

  **Verification:**
  - Both memos have completed executive summaries with ranked tables
  - Each recommended source has a feasibility grade (A/B/C/D)
  - Memos are self-contained and readable without this plan

## System-Wide Impact

- **No code changes:** This plan produces documentation only. No scripts, panels, or pipeline outputs are modified.
- **Downstream implications:** If C7 finds a usable spatial deflator, script 41 (lines 329–382) would need modification in a follow-up plan. The integration path will be documented but not executed.
- **If C6 finds a strong employment alternative:** A follow-up plan would add new data ingestion to script 41 (after the RAIS aggregation in lines 113–161) and potentially new outcome variables in the estimation scripts.
- **basedosdados dependency:** The project already uses `basedosdados` with billing ID `replication-paiva-2025`. Any new BigQuery table is near-zero marginal cost to integrate.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| PNAD Contínua may not have municipality-level identifiers in public microdata | Document this limitation clearly; check if IBGE restricted-access microdata is an option |
| Metro-area IPCA covers only ~30% of municipalities | Document imputation strategies; may still be useful for robustness check on metro subsample |
| Academic spatial deflators may be for specific time periods only (e.g., Census years) | Note temporal gaps; assess whether interpolation is defensible |
| basedosdados catalog may not include all sources | Supplement with direct IBGE/BCB/MTE portal searches |
| Source documentation may be in Portuguese only | Not a risk for this team (Portuguese-speaking researchers) |

## Sources & References

- **Origin document:** [quality_reports/referee_response_tracker.md](quality_reports/referee_response_tracker.md) — C6 and C7
- **Current deflation code:** `scripts/R/4_regression_panels/41_build_muni_panel.R` (lines 329–382)
- **Current employment aggregation:** `scripts/R/4_regression_panels/41_build_muni_panel.R` (lines 113–161)
- **basedosdados integration:** `scripts/R/4_regression_panels/41_build_muni_panel.R` (lines 395–421)
- **C5 verification:** GDP deflation confirmed as national IPCA only (referee_response_tracker.md, C5 RESOLVED)
- **basedosdados catalog:** `basedosdados.org` — BigQuery tables for IBGE, MTE, INEP, Tesouro Nacional
- **IBGE IPCA methodology:** BCB historical series, IBGE SIDRA portal
