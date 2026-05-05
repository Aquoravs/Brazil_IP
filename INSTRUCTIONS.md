# INSTRUCTIONS.md

**Project:** Testing Industrial Policy: Evidence from Brazil's BNDES
**Field:** Economics (Industrial Policy, Political Economy, Development)

---

## Core Principles

- **Plan first** -- enter plan mode before non-trivial tasks; save plans to `logs/plans/`
- **Verify after** -- compile and confirm output at the end of every task
- **Source of truth** -- Paper `paper/main.tex` is authoritative on the overall idea, but details are in current evolution
- **Quality gates** -- weighted aggregate score; nothing ships below 80/100; see `.claude/rules/quality.md`
- **Worker-critic pairs** -- every creator has a paired critic; critics never edit files
- **Auto-memory** -- corrections and preferences are saved automatically via the active agent's built-in memory system
- **Logging** -- session logs, research journal, and entry format defined in `.claude/rules/logging.md`

---

## Current Focus

**Project front door:** [`docs/PROJECT_BLUEPRINT.md`](docs/PROJECT_BLUEPRINT.md). Read at the start of every session. It is the *argument map* — load-bearing claims (F0–F4) with status markers, open angles register (A1–A9), decisions log (D12+), and the current next action.
**State catalog:** [`docs/research_state.md`](docs/research_state.md). Complement to the blueprint — pipeline state, sector taxonomies, design decisions D1–D11, validation invariants, findings. The blueprint references this rather than duplicating it.

**Phase:** exploration (Anderson-Rubin policy evaluation; see `PROJECT_BLUEPRINT.md` §1 for the question, §3 for the identification chain).
**Active comments:** C4 (pooled + muni-by-muni AR test), C8 (penalized methods for many-instruments AR) — `logs/meetings/2026-04-17_tracker.md`.
**Awaiting advisor:** C6 (alternative employment / production-factor data), C7 (local deflators) — memos in `logs/data_exploration/`.
**Use:** `/analyze`, `/strategize`, `/discover data`, `/tools` standalone. Do **not** invoke `/new-project`.
**Quality gating:** exploration-phase renormalization is in effect (see `.claude/rules/quality.md` §1).

---

## Research Design

See [`README.md`](README.md) for the full description, variable dictionary, and data documentation.

**Research question**: Is the allocation of BNDES lending across municipalities GDP-optimal?

**Identifying shock**: Political turnover (mayoral elections) interacted with baseline political affiliation of firms. Sectors whose firms were connected to the incoming party gain BNDES access; those connected to the outgoing party lose it. The variation comes from national party identity x pre-existing firm-owner partisanship, not local demand shocks.

**Empirical strategy**: The centerpiece is an Anderson-Rubin test of whether politically driven reallocation of BNDES credit across sectors affects municipal GDP, presented alongside evidence that the exclusion restriction holds (or is close to holding). The null of zero effect is the optimality benchmark. Multiple operationalizations are being explored — predicted sectoral loans, sector loan shares, aligned employment shares, log employment — to find the most transparent way to map the shock to GDP.

Firm-level (`FA_*`/`dFA_*`) and sector-level shift-share (`Z_*`/`dZ_*`) exercises are exploratory — they establish which sectors to use, whether the instruments are strong, and whether they predict the intended channels (BNDES loans, employment). These feed into the municipality-level AR test, not the other way around.

**Geographic unit**: municipality (5,570) | **Time**: 2002-2017

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

# Policy block variant (4 coarse BNDES lending blocks)
Rscript scripts/R/run_politicsregs.R 30e,31,33,34,35,41 -- --sector-var=policy_block
Rscript scripts/R/run_politicsregs.R 53 -- --sector-var=policy_block
Rscript scripts/R/run_politicsregs.R 54 -- --sector-var=policy_block

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

## Output Organization

Output organization: by-script

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
| 30e | `3_instruments/30e_build_policy_block_mapping.R` | CNAE -> 4 BNDES policy blocks (Agro/Ind/Infra/Serv) |
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

## Current Project State

| Component | File | Status | Description |
|-----------|------|--------|-------------|
| Paper | `paper/main.tex` | draft | BNDES optimality working paper; specs in `paper/sections/regs.tex` |
| Data pipeline | `scripts/R/` | complete | 55 scripts, stages 11->54, all stages operational |
| First stage (firm) | `scripts/R/5_estimation/51_*` | in-progress | Spec engine with 8-dim grid; evaluating firm-level focus |
| First stage (sector) | `scripts/R/5_estimation/53_*` | in-progress | Multiple weight/baseline/FE variants |
| Second stage | `scripts/R/5_estimation/54_*` | in-progress | Reduced form, scalar 2SLS, vector 2SLS |
| Aggregation analysis | `paper/talks/comparison_firm_agg.tex` | complete | C1-C6 conditions, >90% within-cell variation |
