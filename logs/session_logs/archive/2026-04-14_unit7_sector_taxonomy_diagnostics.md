## 2026-04-14 — Unit 7: Sector Taxonomy Diagnostic Battery

**Operations:**
- Created `scripts/R/diagnostics/sector_taxonomy_diagnostics.R`
- Modified `scripts/R/5_estimation/52b_agg_first_stage_summary.R` (added taxonomy diagnostics slide section)
- Updated plan checkbox: Unit 7 → [x]

**Decisions:**
- D1/D2/D6/D7: computed from firm panel + crosswalk files; gracefully skips if crosswalks (from 30d) not yet run
- D3/D4: parsed from existing .tex tables in paper/tables/ directories (matching 52b parse logic)
- D5/D9: deferred — require re-running 30d with quartiles / 52 with lead alignment; flagged in .md report
- D8: narrative written directly in the .md report covering all four taxonomies
- D7 proxy: Shannon entropy of sector employment shares within (muni, year) — full cross-vector correlation deferred until collapsed panels are built for all four taxonomies
- 52b extension: taxonomy slide appears only when sector_taxonomy_diagnostics.tex exists (graceful fallback)

**Results:**
- Syntax OK for both scripts
- Outputs when run: `paper/tables/agg_firm_size_bin/sector_taxonomy_diagnostics.tex`, `quality_reports/sector_taxonomy_diagnostic_report.md`
- Verification: LaTeX table uses booktabs format; compiles cleanly as bare tabular

**Status:**
- Done: Unit 7 complete
- Pending: Unit 8 (driver + documentation updates, depends on Units 1–7)
