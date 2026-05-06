## 2026-04-06 13:50 - Script 52 Spec Engine Review

**Operations:**
- Reviewed `quality_reports/plans/2026-04-06-refactor-script52-sector-spec-engine-plan.md`
- Inspected `scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R`, `scripts/R/5_estimation/52b_proposition2_equivalence.R`, `scripts/R/3_instruments/30b_build_bndes_sector_mapping.R`, `scripts/R/3_instruments/30c_build_size_bin_mapping.R`, and `scripts/R/_utils/beamer_tables.R`
- Cross-checked against `scripts/R/5_estimation/51_firm_first_stage.R`, `scripts/R/5_estimation/53_sector_first_stage.R`, `scripts/R/3_instruments/30_build_sector_groups.R`, `scripts/R/3_instruments/33_select_baseline_weights.R`, `scripts/R/3_instruments/36_build_firm_level_instruments.R`, and `scripts/R/4_regression_panels/42_build_firm_panel.R`
- Ran static parse checks and targeted validation snippets for size-bin year mapping and raw BNDES sector mapping majority vote

**Decisions:**
- Focused findings on correctness, silent data-flow errors, and config combinations that mis-specify or ignore dimensions
- Treated baseline handling, exposure controls, aggregation weights, sector joins, and size-bin construction as the highest-risk areas

**Results:**
- Identified critical issues in script 52: baseline-specific panels ignored, exposure-control configs omit controls, employment-based aggregation/WLS use contemporaneous employment, owner-count and equal-firm aggregation collapse identically, bndes-share is miscomputed under employment aggregation, F_pre filtering is applied before sector-specific joins, and the size-bin year-to-cycle map is malformed
- Identified an additional size-bin construction issue in script 30c: terciles are computed from firm-muni-year rows instead of firm-year totals, which misclassifies multi-municipality firms
- Identified one optional-path issue in script 52b: `--compare-51` still points to the pre-refactor script 51 output directory

**Commits:**
- None

**Status:**
- Done: code review completed with severity-ranked findings and concrete fixes
- Pending: implementation of fixes and rerun/smoke verification
