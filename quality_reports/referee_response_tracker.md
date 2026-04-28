# Meeting Comment Tracker — 2026-04-17

**Source:** `master_supporting_docs/meetings/2026-04-17_meeting.md`
**Classified:** 2026-04-21
**Status:** IN PROGRESS — C1/C2/C3 completed, C5 resolved, C6/C7 explored, C4/C8 pending

---

## Summary Counts

| Classification | Count | Priority |
|---------------|-------|----------|
| NEW ANALYSIS  | 6     | HIGH: 3, MEDIUM: 3 |
| CLARIFICATION | 1     | MEDIUM: 1 |
| DATA EXPLORATION | 2  | MEDIUM: 2 |
| **Total**     | **8** (from 8 comments) | |

---

## Comment-by-Comment Classification

### C1 — Full battery with employment weights + sample splits

> Finish running the full battery of firm-level and aggregated regressions using the new employment weights (share of employment within a municipality) and splitting the sample, considering quartiles of municipality employment

**Class:** NEW ANALYSIS
**Priority:** HIGH
**Routing:** Coder → scripts 51, 52
**Status:** COMPLETED (2026-04-21)

**Plan:** `quality_reports/plans/2026-04-21-feat-complete-first-stage-battery-plan.md`

**Work completed:**
- Unit A: Filled full-sample NA cells (emp-share-weighted rows for BNDES sector + custom sector) — ~144 regressions
- Unit B: Complete split-sample F-stat grids (top_q4 + bottom_3q) for BNDES sector and custom sector, all 3 weightings — ~1,152 regressions
- Unit C: Firm-level split samples (script 51) with emp-share-weighted, party alignment, interaction_mqemp — ~400 regressions
- Unit E: Interaction family (`interaction_muni_emp`) for aggregated regressions — ~192 regressions

**Analysis:** All emp-share-weighted NA cells filled. Full split-sample grids produced matching the full-sample format (equal_firm aggregation). Both alignments (coalition, party), both FE structures, both exposure controls covered.

---

### C2 — Employment outcomes on LHS with instruments on RHS

> Run aggregated regressions that consider on the left hand side employment outcomes and the different instruments as explanatory variables. Explore this using the full sample and splitting it, considering quartiles of municipality employment

**Class:** NEW ANALYSIS
**Priority:** HIGH
**Routing:** Coder → script 52
**Status:** COMPLETED (2026-04-21)

**Plan:** `quality_reports/plans/2026-04-21-feat-complete-first-stage-battery-plan.md` (Unit D)

**Work completed:**
- Unit D: Employment outcomes (log_employment, employment_share) run for full sample, top_q4, and bottom_3q — all sector vars (bndes_sector, custom_sector), all 3 weightings, both alignments, both FE structures, both exposure controls — ~1,728 regressions

**Analysis:** Full employment-outcome battery completed across all sample splits and sector classifications.

---

### C3 — Battery with BNDES-sector tercile classification

> Run full battery of regressions presented in paper\meetings\first_stage.tex and paper\meetings\agg_first_stage.tex using the new sector classification of terciles within the four aggregated BNDES sectors

**Class:** NEW ANALYSIS
**Priority:** HIGH
**Routing:** Coder → modify 30d + scripts 52, 52b
**Status:** COMPLETED (2026-04-21)

**Plans:**
- Mapping & wiring: `quality_reports/plans/2026-04-21-feat-bndes-sector-size-bin-mapping-plan.md` (COMPLETED)
- Regressions: `quality_reports/plans/2026-04-21-feat-complete-first-stage-battery-plan.md` (Unit F)

**Work completed:**
1. Extended script 30d to build `bndes_sector_size_bin` mapping — computes employment terciles within each of the 4 BNDES macro-sectors (Agropecuária, Indústria, Infraestrutura, Comércio e Serviços). Produces 12 composite categories (4 sectors × 3 terciles). Output: `sector_size_bin_bndes_mapping.qs2`.
2. Wired `bndes_sector_size_bin` into script 52 (7 touch points: DIMENSION_OPTIONS, SPEC_CATALOG, get_sector_label, load_sector_size_bin_mappings, join_sector_classification, build_supported_keys, lazy-load guard).
3. Wired into script 52b (GROUPINGS list, LaTeX command, description slide).
4. Ran script 30d successfully — mapping produced with expected structure.
5. Dry-run verified — `--sector-var=bndes_sector_size_bin` resolves correctly in script 52.
6. Regressions run for bndes_sector_size_bin (firm-level via script 51 and aggregated via script 52).

**Key decision:** Extended existing script 30d rather than creating a new 30e. Scripts 31/33/34/35 did not need changes — script 52 handles size_bin variant joins internally.

---

### C4 — Anderson-Rubin test: GDP on instruments, municipality-by-municipality

> Regarding the Anderson-Rubin test, start exploring the regression of log real GDP on the instruments, using as controls municipality FEs, year FEs, and trying with/without total municipality employment. Can this be done municipality by municipality and evaluate in what % of them do we reject the null effect?

**Class:** NEW ANALYSIS
**Priority:** HIGH
**Routing:** Coder → new script (exploration or extension of script 54)
**Status:** PENDING

**Analysis:** Script 54 already has reduced-form regressions (`log(GDP_pc) ~ Z_sector_j | muni_id + year`), but this comment asks for two specific things:

1. **Pooled AR-style regression:** `log(GDP_real) ~ instruments | muni_id + year`, with and without total municipality employment as a control. This is close to the existing reduced form in script 54 but focused specifically on the AR interpretation.

2. **Municipality-by-municipality regressions:** Run the reduced-form regression *separately* for each municipality (time series per muni), then compute what share of municipalities reject the null of zero effect at standard significance levels. This is a novel analysis — no existing script does this.

**Action items:**
1. Create exploration `explorations/anderson_rubin/` for this analysis
2. Script the pooled reduced form: `log(GDP_real) ~ Z_instruments | muni_FE + year_FE` ± total employment
3. Script the municipality-by-municipality version: loop over municipalities, run `log(GDP_real) ~ Z_instruments | year_FE` per muni, collect p-values
4. Compute and visualize rejection rates (% of munis rejecting H0 at 1%, 5%, 10%)
5. Evaluate feasibility: many municipalities may have too few time periods for reliable inference

---

### C5 — Verify GDP deflation method (spatial vs national)

> Verify if our current variable of real GDP was constructed using spatial deflators

**Class:** CLARIFICATION
**Priority:** MEDIUM
**Routing:** Documentation
**Status:** RESOLVED (verified in code)

**Finding:** Script `41_build_muni_panel.R` (lines 329–381) deflates GDP using the **national IPCA** (consumer price index, base year 2018), loaded from `raw/ipca_202509SerieHist.xlsx`. There is **no spatial deflation** — every municipality in the same year gets the same deflator. The deflator is computed as `IPCA_2018 / IPCA_year`, applied uniformly: `pib_real = pib * deflator_2018`.

**Implication:** If local price levels differ substantially across municipalities, the national deflator may bias real GDP comparisons. This connects to C7 (data exploration for local deflators). If local deflators are found, script 41 should be updated.

---

### C6 — Explore alternative employment data sources

> Explore if there is available employment data from other sources (other than RAIS) by municipality and year. In general, explore data on the production factors supply by municipality (employment by ages, employment by sector, education, total amount of capital, productive land)

**Class:** DATA EXPLORATION
**Priority:** MEDIUM
**Routing:** Explorer agent (data discovery) → user review
**Status:** EXPLORED (2026-04-21) — memo produced, awaiting advisor review

**Plan:** `quality_reports/plans/2026-04-21-001-feat-data-exploration-c6-c7-plan.md`

**Work completed:**
- Systematic research of municipality-level employment data sources beyond RAIS
- Evaluated: PNAD Contínua, CAGED, Censo Demográfico, RAIS-derived alternatives
- Evaluated production factor proxies: Censo Agropecuário (land/capital), FINBRA/SICONFI (fiscal/capital), Censo da Educação (human capital), Pesquisa Pecuária Municipal
- Ranked data source memo produced with feasibility grades (A/B/C/D)
- Output: `quality_reports/data_exploration/c6_employment_sources.md`

**Next step:** Advisor reviews memo and decides which sources to prioritize for ingestion.

---

### C7 — Explore local/spatial deflator data

> Explore if there is data on local deflators (yearly, municipality, frequency of update, size of geographic units)

**Class:** DATA EXPLORATION
**Priority:** MEDIUM
**Routing:** Explorer agent (data discovery) → user review
**Status:** EXPLORED (2026-04-21) — memo produced, awaiting advisor review

**Plan:** `quality_reports/plans/2026-04-21-001-feat-data-exploration-c6-c7-plan.md`

**Work completed:**
- Researched sub-national price indices: IBGE IPCA by metropolitan area (~16 metros), INPC, IPC-FIPE
- Investigated academic constructed indices (Corseuil & Foguel, spatial price indices literature)
- Evaluated indirect/proxy approaches: housing rental prices, consumption data, wage-regression residuals
- Assessed municipality-level matchability: coverage fraction, join keys, imputation strategies for non-metro municipalities
- Documented script 41 integration path (lines 329–382) for potential spatial deflator replacement
- Output: `quality_reports/data_exploration/c7_local_deflators.md`

**Key finding:** Metro-area IPCA covers ~16 metros (~30% of municipalities by population). Full municipality-level spatial deflators do not exist as an official series — would require academic construction or metro-area imputation.

**Next step:** Advisor reviews memo and decides whether metro-area deflators are worth integrating (robustness check on metro subsample) or if national IPCA is sufficient.

---

### C8 — Penalized regression methods for many-instruments AR test

> When we use many sectors on the right-hand side to evaluate the Anderson-Rubin test, the number of regressors can increase rapidly due to the different instruments available. It may be beneficial to include a cost penalty when including more regressors, so it's important to explore these ridge regressions, like LASSO or other methods, and evaluate if they are suitable in our case.

**Class:** NEW ANALYSIS (methodological exploration)
**Priority:** MEDIUM
**Routing:** Strategist (methodological design) + Coder (implementation)
**Status:** PENDING

**Analysis:** When running the AR test with sector-specific instruments across multiple tiers (mayor, governor, president) and interaction terms, the instrument count can grow to 30-60+ regressors. Penalized methods could help:

- **LASSO (L1):** Variable selection — identifies which sector-instrument combos are most predictive of GDP. Useful for sparsity.
- **Ridge (L2):** Shrinkage without selection — handles multicollinearity among correlated instruments.
- **Elastic net:** Combines L1 + L2.
- **Post-LASSO OLS:** Select instruments via LASSO, then run standard IV/OLS with selected set.

**Methodological considerations:**
- Standard LASSO/ridge p-values are not straightforward — may need debiased LASSO or post-selection inference
- The many-instruments literature (Belloni, Chernozhukov, Hansen 2012) has specific recommendations for IV settings
- `glmnet` (R) is the standard implementation; `hdm` package for high-dimensional IV
- Need to decide: is this for instrument selection (pick best Z's) or for the AR test itself?

**Action items:**
1. Review econometric literature on penalized IV methods (Belloni, Chernozhukov, Hansen)
2. Create exploration `explorations/penalized_ar/`
3. Implement ridge and LASSO versions of the reduced form
4. Compare selected instruments across methods
5. Evaluate statistical validity of inference under penalization
6. Produce a methodological memo for advisor review

---

## Progress Summary

| Comment | Status | Date | Plan |
|---------|--------|------|------|
| C1 | COMPLETED | 2026-04-21 | first-stage-battery (Units A-C, E) |
| C2 | COMPLETED | 2026-04-21 | first-stage-battery (Unit D) |
| C3 | COMPLETED | 2026-04-21 | bndes-sector-size-bin-mapping + first-stage-battery (Unit F) |
| C4 | PENDING | — | Needs new plan |
| C5 | RESOLVED | 2026-04-21 | Verified in code (national IPCA) |
| C6 | EXPLORED | 2026-04-21 | data-exploration-c6-c7 → advisor review |
| C7 | EXPLORED | 2026-04-21 | data-exploration-c6-c7 → advisor review |
| C8 | PENDING | — | Depends on C4 |

## Remaining Work

```
C4 (AR test) ──needs plan──> new exploration
C8 (penalized methods) ──depends on──> C4 results
C6 (employment data) ──awaiting──> advisor review of memo
C7 (local deflators) ──awaiting──> advisor review of memo
  C7 ──if approved──> update script 41 (lines 329–382)
```

**Next priorities:**
1. C4: Anderson-Rubin exploration (pooled + muni-by-muni) — needs new plan
2. C6/C7: Await advisor feedback on data exploration memos
3. C8: After C4 results, explore penalized regression methods
