# INSTRUCTIONS.md

**Project:** Testing Industrial Policy: Evidence from Brazil's BNDES
**Field:** Economics (Industrial Policy, Political Economy, Development)

---

## Core Principles

- **Plan first** -- enter plan mode before non-trivial tasks; save plans to `logs/plans/`
- **Verify after** -- compile and confirm output at the end of every task
- **Source of truth** -- Paper `paper/main.tex` is authoritative on the overall idea, but details are in current evolution
- **Quality gates** -- weighted aggregate score; nothing ships below 80/100; see `quality.md`
- **Worker-critic pairs** -- every creator has a paired critic; critics never edit files
- **Auto-memory** -- corrections and preferences are saved automatically via the active agent's built-in memory system

---

## Current Focus

**Phase:** exploration (Anderson-Rubin policy evaluation; see [`docs/research_state.md`](docs/research_state.md) §1).
**Active comments:** C4 (pooled + muni-by-muni AR test), C8 (penalized methods for many-instruments AR) — `logs/referee_response_tracker.md`.
**Awaiting advisor:** C6 (alternative employment / production-factor data), C7 (local deflators) — memos in `logs/data_exploration/`.
**Use:** `/analyze`, `/strategize`, `/discover data`, `/tools` standalone. Do **not** invoke `/new-project`.
**Quality gating:** exploration-phase renormalization is in effect (see `.claude/rules/quality.md` §1).

---

## Research Design

**Research question**: Is the allocation of BNDES lending across municipalities GDP-optimal?

**Empirical strategy**: linked IV specifications that build from micro validation to municipality-level optimality:
- Firm-level (levels + changes, extensive + intensive): `FA_*` / `dFA_*` -> BNDES access/amount
- Sector-level (levels + changes): shift-share `Z_*` / `dZ_*` -> BNDES sector share within municipality
- Municipality-level second stage: predicted sectoral reallocation -> change in GDP per capita
- Null hypothesis (optimality): marginal reallocation has zero GDP effect (beta ~ 0)

**Key design pivot (2026-03)**: Sector-level aggregation loses >90% of identifying variation (within-cell firm heterogeneity). Analysis is evolving toward firm-level allocation. Both pipelines are maintained as complementary.

**Geographic unit**: municipality (5,570)
**Time coverage**: 2002-2017
**Key data sources**: BNDES indirect loans, RAIS employer-employee, TSE elections, IBGE municipal GDP/population

---

## Folder Structure

For detailed directory contents, and output file descriptions, see [`README.md`](README.md).

```
Brazil_IP/
|-- INSTRUCTIONS.md              # Canonical shared instructions
|-- AGENTS.md                    # Codex-specific wrapper
|-- CLAUDE.md                    # Claude-specific wrapper
|-- .agents/                     # Codex rules, skills, agents, hooks
|-- .claude/                     # Claude rules, skills, agents, hooks
|-- Bibliography_base.bib        # Centralized bibliography
|-- paper/                       # Main LaTeX manuscript (source of truth)
|   |-- main.tex                 # Primary paper file
|   |-- regs.tex                 # Authoritative draft of Section 5 (Specifications)
|   |-- output/                  # Generated tables organized by-script -- firm/, sector/, sector_grouped/, agg_firm/, agg_firm_bndes_sector/, agg_firm_grouped/, agg_firm_size_bin/, ...
|   |-- build/                   # latexmk build artifacts (gitignored)
|   `-- latexmkrc                # XeLaTeX + biber configuration
|-- presentations/               # Beamer talks (comparison_firm_agg, progress updates, first_stage, agg_first_stage, summary_first_stage)
|-- data/                        # Project data
|   |-- raw/                     # Original untouched data (BNDES, RAIS, politics, GDP)
|   `-- processed/               # Intermediate datasets (.qs2, .fst) + diagnostics/
|-- scripts/                     # Analysis code
|   `-- R/                       # 55 pipeline scripts (numbered 11->54) + _utils/ + _archive/
|-- logs/                        # Session logs, plans, research journal
|-- explorations/                # Research sandbox
|-- templates/                   # Session log, quality report templates
`-- docs/                        # Design notes, brainstorms, meeting records, reference papers
```

---

## Variable Naming Conventions

- `cnae_section` - CNAE 2.0 section codes (letter A-U)
- `muni_id` - municipality code (6-digit IBGE, integer)
- `firm_id` - firm identifier (integer, from RAIS)
- `FA_*` / `dFA_*` - firm-level levels / changes instruments
- `Z_*` / `dZ_*` - sector-level levels / changes shift-share instruments
- `s_mjt` - BNDES sector share; `delta_s_mjt` - yearly change (never zero-filled from NA)
- `has_bndes_fmt` / `log_bndes_fmt` - extensive / intensive margin outcomes
- `align_*` / `dalign_*` - alignment levels / turnover shocks
- `sector_group` - grouped sector code (Ag, Mi, CL, CH, CA, UCo, Tr, Tp, MS, PSO, XX)
- `log_gdp_pc` - log GDP per capita, IPCA-deflated to 2018 R$

For a full variable dictionary, see [`README.md`](README.md).

---

## Commands

```bash
# R Pipeline (Main Analysis)
Rscript scripts/R/run_politicsregs.R all                    # Full pipeline
Rscript scripts/R/run_politicsregs.R 22,32,36,42,51         # Firm validation pipeline
Rscript scripts/R/run_politicsregs.R 31:54                  # Sector pipeline through estimation
Rscript scripts/R/run_politicsregs.R 51 --specs=baseline     # Firm first stage (specific bundle)
Rscript scripts/R/run_politicsregs.R 53 -- --specs=all       # Sector first stage (all specs)
Rscript scripts/R/run_politicsregs.R 21:54 --dryrun          # Dry run (print commands only)

# Grouped sector variant
Rscript scripts/R/run_politicsregs.R 30:54 --sector-var=sector_group

# Muni-employment upstream objects (run once after data refresh)
Rscript scripts/R/run_politicsregs.R 30c,30d,32b
Rscript scripts/R/run_politicsregs.R 41 -- --sector-var=sector_group
Rscript scripts/R/run_politicsregs.R 42 -- --sector-var=sector_group

# Employment-share weighted specs
Rscript scripts/R/run_politicsregs.R 51 -- --specs=weighted,emp_share_weighted --family=main
Rscript scripts/R/run_politicsregs.R 52 -- --specs=emp_weighted,emp_share_weighted --sector-var=sector_group

# Pooled with top-quartile interaction (goals 2 and 3)
Rscript scripts/R/run_politicsregs.R 51 -- --specs=baseline,weighted --family=interaction_mqemp
Rscript scripts/R/run_politicsregs.R 52 -- --specs=baseline,emp_share_weighted --family=interaction_mqemp --sector-var=sector_group
Rscript scripts/R/run_politicsregs.R 53 -- --specs=baseline --muni-interaction=top_q4_muni

# Split-sample by muni employment quartile (goal 3)
Rscript scripts/R/run_politicsregs.R 51 -- --specs=baseline,weighted --sample=top_q4
Rscript scripts/R/run_politicsregs.R 51 -- --specs=baseline,weighted --sample=bottom_3q
Rscript scripts/R/run_politicsregs.R 52 -- --specs=baseline,emp_share_weighted --muni-sample=top_q4 --sector-var=sector_group
Rscript scripts/R/run_politicsregs.R 52 -- --specs=baseline,emp_share_weighted --muni-sample=bottom_3q --sector-var=sector_group
Rscript scripts/R/run_politicsregs.R 53 -- --specs=baseline --muni-sample=top_q4,bottom_3q

# Sector × size-bin taxonomy specs (goal 4)
Rscript scripts/R/run_politicsregs.R 52 -- --specs=size_bin_battery --sector-var=cnae_section,sector_group,cnae_size_bin,sector_group_size_bin

# Paper compilation (XeLaTeX + biber)
cd paper && xelatex -interaction=nonstopmode main.tex
biber main
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex

# Talk compilation
cd presentations && xelatex -interaction=nonstopmode comparison_firm_agg.tex
```

---

## Coding Conventions

- R packages: `data.table` for data manipulation, `fixest` for regressions, `qs2` or `fst` for storage (the latter if column selection is optimal)
- Standard errors: two-way clustered by `firm_id` + `muni_id` (firm), `muni_id` + `cnae_section` (sector)
- FE syntax: `muni_id^cnae_section` for interaction FE (fixest notation)
- F-statistics: `fixest::wald(mod, keep = "^(FA_|dFA_|Z_|dZ_)")$stat`
- Share imputation: zero-fill OK for `s_*`; `delta_s_*` must come only from computed subtraction
- Scripts numbered for execution order; orchestrated by `run_politicsregs.R`

---

## Pipeline Architecture

| Stage | Script | Purpose |
|-------|--------|---------|
| 11 | `1_loan_aggregation/11_process_bndes_indirect.R` | Aggregate BNDES indirect loans |
| 21-22 | `2_firm_panel/` | Convert panel formats, reconstruct unified firm panel |
| 30 | `3_instruments/30_build_sector_groups.R` | CNAE -> 11 sector groups crosswalk |
| 30b | `3_instruments/30b_build_bndes_sector_mapping.R` | BNDES sector mapping crosswalk |
| 30c | `3_instruments/30c_build_size_bin_mapping.R` | National firm size terciles (size-bin crosswalk) |
| 30d | `3_instruments/30d_build_sector_size_bin_mapping.R` | Within-sector firm size tercile crosswalks (cnae + sector_group) |
| 31-36 | `3_instruments/` | Build exposure weights, alignment shocks, baselines, instruments |
| 32b | `3_instruments/32b_build_muni_employment_baselines.R` | Municipality pre-election employment baselines + quartile classification |
| 41-42 | `4_regression_panels/` | Build muni x sector (Panel A/B) and firm panels |
| 51-54 | `5_estimation/` | Firm first stage, agg. firm->sector, sector first stage, second stage |

### Path Configuration

All R scripts use env-var-based paths via `_utils/utils.R`:
- `BNDES_BASE` -> `data/` (raw data under `data/raw/`)
- `BNDES_OUTPUT` -> `data/processed/` (intermediate .qs2/.fst files)
- `BNDES_TABLES` -> `paper/output/` (regression table outputs, organized by script: firm/, sector/, agg_firm*/, ...)
- `ENCFS_MOUNT` -> encrypted RAIS mount (server-specific)

Helpers: `raw_path()`, `output_path()`, `tables_path()`, `project_path()`

---

## Quality Thresholds

| Score | Gate | Applies To |
|-------|------|------------|
| 80 | Commit | Weighted aggregate (blocking) |
| 90 | PR | Weighted aggregate (blocking) |
| 95 | Submission | Aggregate + all components >= 80 |
| -- | Advisory | Talks (reported, non-blocking) |

---

## Logging

For every non-trivial task, agents must maintain a session log in `logs/session_logs/`.

### Session Log Requirements

- Create or append a file named `logs/session_logs/YYYY-MM-DD_<slug>.md`
- Log proactively, not only at the end
- Append-only within a session; never overwrite earlier entries

### Required Logging Triggers

1. Post-plan entry
After the plan is clear, record the goal, approach, rationale, and key context.

2. Incremental entries
Append 1-3 lines whenever:
- a design decision is made
- a bug or blocker is resolved
- the user corrects an assumption
- the implementation approach changes

3. End-of-session entry
Before final handoff, record:
- summary of work completed
- files changed
- verification performed
- open questions or blockers
- commit hash, if applicable

### Entry Format

```markdown
## YYYY-MM-DD HH:MM - [Brief Title]

**Operations:**
- [Scripts run, files created/modified/deleted]

**Decisions:**
- [Choice made] - [rationale]

**Results:**
- [Key findings, outputs produced]

**Commits:**
- `[hash]` [commit message]

**Status:**
- Done: [what is complete]
- Pending: [what remains]
```

### Research Journal

Agents should also append one short entry per substantial invocation to `logs/research_journal.md`.

```markdown
### YYYY-MM-DD HH:MM - [Agent Name]
**Phase:** [Discovery/Strategy/Execution/Peer Review/Presentation]
**Target:** [file or topic]
**Score:** [XX/100 or PASS/FAIL or N/A]
**Verdict:** [one-line summary]
**Report:** [path to full report or session log]
```

---

## Skills Quick Reference

| Command | What It Does |
|---------|-------------|
| `/new-project [topic]` | Full pipeline: idea -> paper (orchestrated) |
| `/discover [mode] [topic]` | Discovery: interview, literature, data, ideation |
| `/strategize [question]` | Identification strategy or pre-analysis plan |
| `/analyze [dataset]` | End-to-end data analysis |
| `/write [section]` | Draft paper sections + humanizer pass |
| `/review [file/--flag]` | Quality reviews (routes by target: paper, code, peer) |
| `/revise [report]` | R&R cycle: classify + route referee comments |
| `/talk [mode] [format]` | Create, audit, or compile Beamer presentations |
| `/submit [mode]` | Journal targeting -> package -> audit -> final gate |
| `/tools [subcommand]` | Utilities: commit, compile, validate-bib, journal, etc. |

---

## Output Organization

Output organization: by-script

---

## Current Project State

| Component | File | Status | Description |
|-----------|------|--------|-------------|
| Paper | `paper/main.tex` | draft | BNDES optimality working paper; specs in `paper/sections/regs.tex` |
| Data pipeline | `scripts/R/` | complete | 55 scripts, stages 11->54, all stages operational |
| First stage (firm) | `scripts/R/5_estimation/51_*` | in-progress | Spec engine with 8-dim grid; evaluating firm-level focus |
| First stage (sector) | `scripts/R/5_estimation/53_*` | in-progress | Multiple weight/baseline/FE variants |
| Second stage | `scripts/R/5_estimation/54_*` | in-progress | Reduced form, scalar 2SLS, vector 2SLS |
| Aggregation analysis | `paper/talks/comparison_firm_agg.tex` | complete | C1-C6 conditions, >90% within-cell variation |

## Data Notes

- BNDES loan data: 2002-2025, stored in `data/raw/bndes_indirect_auto/` and `data/raw/bndes_indirect_nonauto/`
- RAIS employment data: accessed via encrypted mount, 2002-2017 (restricted access)
- Political affiliation: `data/raw/david_ra/` - includes `in_power_upd_2002_2019.qs2`
- GDP data: `data/raw/mun_gdp/` - IBGE PIB Municipal (nominal -> 2018 R$ via IPCA)
- Population: downloaded via `basedosdados` R package, cached as `data/processed/population_ibge.qs2`
