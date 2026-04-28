# Migration Plan: Brazil_IP_Code → Brazil_IP (clo-author)

**Status:** DRAFT
**Date:** 2026-04-02

## Context

David has an active economics research project (Brazil IP / BNDES optimality) in `Brazil_IP_Code/` with 55 R scripts, 8GB of processed data, LaTeX papers, and extensive documentation. He wants to migrate it into `Brazil_IP/`, a fresh fork of the clo-author academic workflow template, to gain structured agents, quality gates, and publication-ready tooling. The old "output" folder name is misleading — it contains processed/intermediate data, not final outputs.

## Migration Map

### 1. Data (copy)

| Source | Destination | Notes |
|--------|-------------|-------|
| `Brazil_IP_Code/BNDES/raw/` | `Brazil_IP/data/raw/` | ~1.3GB raw inputs |
| `Brazil_IP_Code/BNDES/output/*.qs2, *.fst, *.csv, *.rds` (top-level files) | `Brazil_IP/data/processed/` | ~7.7GB intermediate data |
| `Brazil_IP_Code/BNDES/output/diagnostics/` | `Brazil_IP/data/processed/diagnostics/` | 230MB diagnostic CSVs |
| `Brazil_IP_Code/BNDES/output/firm_reg_tables/` | `Brazil_IP/paper/tables/firm/` | Regression table outputs |
| `Brazil_IP_Code/BNDES/output/muni_reg_tables/` | `Brazil_IP/paper/tables/sector/` | Regression table outputs |
| `Brazil_IP_Code/BNDES/output/muni_reg_tables_grouped/` | `Brazil_IP/paper/tables/sector_grouped/` | Grouped regression tables |
| `Brazil_IP_Code/BNDES/output/agg_firm_reg_tables_grouped/` | `Brazil_IP/paper/tables/agg_firm/` | Aggregation test tables |

### 2. R Scripts (copy, preserve subfolder structure)

| Source | Destination |
|--------|-------------|
| `Brazil_IP_Code/BNDES/politicsregs/run_politicsregs.R` | `scripts/R/run_politicsregs.R` |
| `Brazil_IP_Code/BNDES/politicsregs/1_loan_aggregation/` | `scripts/R/1_loan_aggregation/` |
| `Brazil_IP_Code/BNDES/politicsregs/2_firm_panel/` | `scripts/R/2_firm_panel/` |
| `Brazil_IP_Code/BNDES/politicsregs/3_instruments/` | `scripts/R/3_instruments/` |
| `Brazil_IP_Code/BNDES/politicsregs/4_regression_panels/` | `scripts/R/4_regression_panels/` |
| `Brazil_IP_Code/BNDES/politicsregs/5_estimation/` | `scripts/R/5_estimation/` |
| `Brazil_IP_Code/BNDES/politicsregs/diagnostics/` | `scripts/R/diagnostics/` |
| `Brazil_IP_Code/BNDES/politicsregs/_utils/` | `scripts/R/_utils/` |
| `Brazil_IP_Code/BNDES/politicsregs/_archive/` | `scripts/R/_archive/` |

### 3. Paper & LaTeX (copy .tex and .pdf only, skip build artifacts)

| Source | Destination | Role |
|--------|-------------|------|
| `paper/draft.tex` | `paper/main.tex` | Main paper (renamed) |
| `paper/regs.tex` | `paper/sections/regs.tex` | Specification write-up |
| `paper/first_stage.tex` | `paper/sections/first_stage.tex` | Appendix/beamer |
| `paper/review_aggregation.tex` | `paper/sections/review_aggregation.tex` | Aggregation review |
| `paper/comparison_firm_agg.tex` | `paper/talks/comparison_firm_agg.tex` | Beamer presentation |
| `paper/presentation_progress_*.tex` | `paper/talks/` | Progress presentations |
| `paper/Brazil_IP_Paper_2026_01_15.pdf` | `paper/Brazil_IP_Paper_2026_01_15.pdf` | Reference PDF |

### 4. Documentation (copy)

| Source | Destination |
|--------|-------------|
| `docs/shift_share.md` | `master_supporting_docs/shift_share.md` |
| `docs/doubts.md` | `master_supporting_docs/doubts.md` |
| `docs/master_roadmap.md` | `master_supporting_docs/master_roadmap.md` |
| `docs/first_stage_review.md` | `master_supporting_docs/first_stage_review.md` |
| `docs/proposition2_failure_note.tex` + `.pdf` | `master_supporting_docs/proposition2_failure_note.tex` + `.pdf` |
| `docs/conditions_C3_C5_C6_explained.tex` + `.pdf` | `master_supporting_docs/conditions_C3_C5_C6_explained.tex` + `.pdf` |
| `docs/plans/` | `quality_reports/plans/` |
| `docs/brainstorms/` | `master_supporting_docs/brainstorms/` |
| `docs/solutions/` | `master_supporting_docs/solutions/` |

### 5. Config (copy)

| Source | Destination |
|--------|-------------|
| `Brazil_IP_Code/.claude/settings.local.json` | `Brazil_IP/.claude/settings.local.json` |

## Path Configuration Updates

The R scripts use a well-designed env-var system. Only 2 files need changes:

### `scripts/R/_utils/utils.R`
- **Line ~84-87**: Change `POLITICSREGS_DIR` from `file.path(PROJECT_ROOT, "BNDES", "politicsregs")` → `file.path(PROJECT_ROOT, "scripts", "R")`
- **Line ~128**: Change `OUTPUT_DIR` default from `file.path(BNDES_BASE, "output")` → `file.path(PROJECT_ROOT, "data", "processed")`
- **Line ~113-120**: Change `BNDES_BASE` default from `file.path(PROJECT_ROOT, "BNDES")` → `file.path(PROJECT_ROOT, "data")`
- **`raw_path()`** helper: verify it still resolves to `data/raw/` (currently `BNDES_BASE/raw`)
- Add `TABLES_DIR` constant → `file.path(PROJECT_ROOT, "paper", "tables")` for regression table output

### `scripts/R/run_politicsregs.R`
- Update the `bootstrap_path` to find `_utils/script_bootstrap.R` relative to new location
- Pipeline map paths stay the same (relative to POLITICSREGS_DIR)

### `scripts/R/diagnostics/explore_affiliation.R`
- Replace hardcoded Windows paths with standard `bootstrap_politicsregs()` pattern

### Regression table output paths
- Scripts 51, 52, 53, 54 write to subdirs of OUTPUT_DIR (e.g., `output_path("firm_reg_tables/...")`). After migration these would go to `data/processed/firm_reg_tables/`. We need to redirect them to `paper/tables/` instead. Options:
  - **Option A**: Add a `TABLES_DIR` env var / constant and update scripts 51-54 to use it
  - **Option B**: Keep tables in `data/processed/` for now and move to `paper/tables/` as a later cleanup
  - **Recommended**: Option A — clean separation from the start

## .gitignore Updates

Add to `.gitignore`:
```
# Large data files (not tracked in git)
data/raw/
data/processed/
*.qs2
*.fst
*.rds

# Keep tables tracked
!paper/tables/**/*.tex
!paper/tables/**/*.md
```

## CLAUDE.md Updates

Fill in the bracketed placeholders with project-specific content from the old CLAUDE.md:
- Project name: "Testing Industrial Policymakers: Evidence from Brazil's BNDES"
- Research question, empirical strategy, variable naming conventions
- Build commands (updated for new paths)
- Pipeline architecture table
- Data notes
- Current project state

## Execution Order

1. Create directory structure
2. Copy data (`data/raw/`, `data/processed/`)
3. Copy R scripts to `scripts/R/`
4. Copy paper files (`.tex` and reference `.pdf` only)
5. Copy documentation
6. Copy `.claude/settings.local.json`
7. Update `.gitignore`
8. Update `scripts/R/_utils/utils.R` (path constants)
9. Fix `scripts/R/diagnostics/explore_affiliation.R` (hardcoded paths)
10. Update `CLAUDE.md` with project content
11. Update `MEMORY.md` (already done)

## Verification

- [ ] `ls scripts/R/` shows all numbered stage folders + `_utils/` + `run_politicsregs.R`
- [ ] `ls data/raw/` shows BNDES raw subdirs
- [ ] `ls data/processed/` shows .qs2/.fst files
- [ ] `ls paper/tables/` shows regression table subdirs
- [ ] `paper/main.tex` exists and is the old `draft.tex`
- [ ] R path bootstrap resolves correctly: `Rscript scripts/R/run_politicsregs.R --dryrun` (if R available)
- [ ] `.gitignore` excludes large data, includes .tex tables
- [ ] `CLAUDE.md` has no remaining `[BRACKETED]` placeholders
