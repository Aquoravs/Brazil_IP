# CLAUDE.md

**Project:** Testing Industrial Policy: Evidence from Brazil's BNDES
**Field:** Economics (Industrial Policy, Political Economy, Development)

**Front door:** [`docs/PROJECT_BLUEPRINT.md`](docs/PROJECT_BLUEPRINT.md) — read at the start of every session.

---

## Core Principles

- **Plan first** — enter plan mode before non-trivial tasks; save plans to `journal/plans/`
- **Verify after** — compile and confirm output at the end of every task
- **Quality gates** — weighted aggregate score; nothing ships below 80/100; see `.claude/rules/quality.md`
- **Worker-critic pairs** — every creator has a paired critic; critics never edit files
- **Logging** — session logs, research journal, and entry format defined in `.claude/rules/logging.md`

---

## Current Focus

**Phase:** exploration — Anderson-Rubin policy evaluation (see Blueprint §1 for research question, §3 for identification chain).
**Active advisor comments:** C4 (pooled + muni-by-muni AR test), C8 (penalized methods) — `journal/meetings/2026-04-17/tracker.md`.
**Awaiting advisor:** C6 (alternative employment / production-factor data), C7 (local deflators) — memos in `docs/data_memos/`.
**Use:** `/analyze`, `/strategize`, `/discover data`, `/tools` standalone. Do **not** invoke `/new-project`.
**Quality gating:** exploration-phase renormalization is in effect (see `.claude/rules/quality.md` §1).

---

## Research Design

See [`README.md`](README.md) for full variable dictionary and data documentation.

**Research question:** Does a politically driven exogenous shock to the sectoral composition of local economic activity affect municipal GDP, beyond the aggregate volume effect?

**Identifying shock:** Political turnover (mayoral elections) interacted with baseline political affiliation of firms. Sectors whose firms were connected to the incoming party gain BNDES access; those connected to the outgoing party lose it. The variation comes from national party identity × pre-existing firm-owner partisanship, not local demand shocks.

**Empirical strategy:** An Anderson-Rubin test of whether politically driven shifts in sectoral employment composition affect municipal GDP. The endogenous variable is the vector of sector employment shares — the most comprehensive observable proxy for the sectoral distribution of local economic activity (sector-by-municipality value added or gross output for 2002–2017 would be preferred but are unavailable). BNDES credit is the mechanism that transmits the political shock to employment composition; it is not the estimand. The volume channel — operationalised as total BNDES disbursements normalised by initial municipal GDP (a unit-free ratio; specification subject to revision after theory/math review) — is conditioned out so the test isolates the composition channel. The null of zero effect is the optimality benchmark for the sectoral structure of the local economy. Firm-level and sector-level first-stage work was preparatory — it produced the spec engines, taxonomies, and F-stat patterns that feed the muni-level AR test.

**Geographic unit:** municipality (5,570) | **Time:** 2002–2017

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

# Pooled with top-quartile interaction
Rscript scripts/R/run_politicsregs.R 51 -- --specs=baseline,weighted --family=interaction_mqemp
Rscript scripts/R/run_politicsregs.R 52 -- --specs=baseline,emp_share_weighted --family=interaction_mqemp --sector-var=sector_group
Rscript scripts/R/run_politicsregs.R 53 -- --specs=baseline --muni-interaction=top_q4_muni

# Split-sample by muni employment quartile
Rscript scripts/R/run_politicsregs.R 51 -- --specs=baseline,weighted --sample=top_q4
Rscript scripts/R/run_politicsregs.R 51 -- --specs=baseline,weighted --sample=bottom_3q
Rscript scripts/R/run_politicsregs.R 52 -- --specs=baseline,emp_share_weighted --muni-sample=top_q4 --sector-var=sector_group
Rscript scripts/R/run_politicsregs.R 52 -- --specs=baseline,emp_share_weighted --muni-sample=bottom_3q --sector-var=sector_group
Rscript scripts/R/run_politicsregs.R 53 -- --specs=baseline --muni-sample=top_q4,bottom_3q

# Sector × size-bin taxonomy specs
Rscript scripts/R/run_politicsregs.R 52 -- --specs=size_bin_battery --sector-var=cnae_section,sector_group,cnae_size_bin,sector_group_size_bin

# Paper compilation (XeLaTeX + biber)
cd paper && xelatex -interaction=nonstopmode main.tex
biber main
xelatex -interaction=nonstopmode main.tex
xelatex -interaction=nonstopmode main.tex

# Meeting slides compilation (per-meeting subfolder)
cd journal/meetings/2026-04-22 && xelatex -interaction=nonstopmode slides_first_stage.tex
```

---

## Folder Layout

```
docs/                      ← stable knowledge (cite-able, edited in place)
  ├── PROJECT_BLUEPRINT.md
  ├── strategy/            ← load-bearing strategy memos
  ├── methodology/         ← compiled LaTeX technical notes (.tex + .pdf)
  ├── data_memos/          ← C6/C7-style data exploration conclusions
  └── archive/             ← superseded knowledge

journal/                   ← time-stamped events (append-only, dated filenames)
  ├── research_journal.md  ← global append-only log
  ├── knowledge.md         ← extracted conventions/findings
  ├── plans/               ← YYYY-MM-DD_*.md
  ├── sessions/            ← session logs (was logs/session_logs/)
  ├── audits/
  └── meetings/<date>/     ← notes.md + tracker.md + slides[_variant].tex + build/

paper/                     ← manuscript (exploration phase: skeleton only)
  ├── latexmkrc
  └── snapshots/           ← early drafts and compiled PDFs

output/                    ← R pipeline output (exploratory, not paper-ready)
  └── tables/              ← R-generated regression tables and figures (BNDES_TABLES)

explorations/<branch>/<sub-branch>/    ← one subfolder per branch, with output/
  ├── README.md
  └── <sub-branch>/
      ├── *.R
      └── output/

scripts/R/                 ← production pipeline (unchanged)
templates/                 ← user-facing forms
.claude/                   ← AI assistant infrastructure (incl. .claude/templates/)
```

**Filename test:** if filename starts with a date (`YYYY-MM-DD_…`), it's an event → `journal/`. If not, it's knowledge → `docs/` or `paper/` or `scripts/`.

---

## Coding Conventions

- R packages: `data.table` for data manipulation, `fixest` for regressions, `qs2` or `fst` for storage
- Standard errors: two-way clustered by `firm_id` + `muni_id` (firm), `muni_id` + `cnae_section` (sector)
- FE syntax: `muni_id^cnae_section` for interaction FE (fixest notation)
- F-statistics: `fixest::wald(mod, keep = "^(FA_|dFA_|Z_|dZ_)")$stat`
- Share imputation: zero-fill OK for `s_*`; `delta_s_*` must come only from computed subtraction
- Scripts numbered for execution order; orchestrated by `run_politicsregs.R`
- Output organization: by-script

---

## Pipeline Architecture

| Stage | Script | Purpose |
|-------|--------|---------|
| 11 | `1_loan_aggregation/11_process_bndes_indirect.R` | Aggregate BNDES indirect loans |
| 21-22 | `2_firm_panel/` | Convert panel formats, reconstruct unified firm panel |
| 30 | `3_instruments/30_build_sector_groups.R` | CNAE → 11 sector groups crosswalk |
| 30b | `3_instruments/30b_build_bndes_sector_mapping.R` | BNDES sector mapping crosswalk |
| 30c | `3_instruments/30c_build_size_bin_mapping.R` | National firm size terciles (size-bin crosswalk) |
| 30d | `3_instruments/30d_build_sector_size_bin_mapping.R` | Within-sector firm size tercile crosswalks |
| 30e | `3_instruments/30e_build_policy_block_mapping.R` | CNAE → 4 BNDES policy blocks (Agro/Ind/Infra/Serv) |
| 31-36 | `3_instruments/` | Build exposure weights, alignment shocks, baselines, instruments |
| 32b | `3_instruments/32b_build_muni_employment_baselines.R` | Municipality pre-election employment baselines + quartile classification |
| 41-42 | `4_regression_panels/` | Build muni × sector (Panel A/B) and firm panels |
| 51-54 | `5_estimation/` | Firm first stage, agg. firm→sector, sector first stage, second stage |

**Path configuration** — all scripts use env-var-based paths via `_utils/utils.R`:
- `BNDES_BASE` → `data/` | `BNDES_OUTPUT` → `data/processed/` | `BNDES_TABLES` → `output/tables/` | `ENCFS_MOUNT` → encrypted RAIS mount

Helpers: `raw_path()`, `output_path()`, `tables_path()`, `project_path()`

**Pipeline caveat (2026-05-05):** existing scripts do not yet implement the production margin `policy_block_active × S3`. Script `30f_build_policy_block_size_mapping.R` is pending; downstream consumers are scripts 31, 34, and 41.

---

## Spec Engine Dimensions

### Script 51 — Firm first stage (8-dim)
`margin × exposure × weighting × baseline × alignment × time_variation × sample × family`
Reference panel: 44,181,405 firm-muni-year rows (cycle-specific baseline).

### Script 52 — Aggregated firm → sector (9-dim)
`outcome × baseline × alignment × FE × exposure_control × sector_var × aggregation × regression_weight × exposure`
**Pairing rule:** `unweighted` pairs with `equal_firm`; `emp_weighted` pairs with `employment`.
Outcomes: `bndes_share`, `bndes_extensive`, `log_employment`, `employment_share`.

### Script 53 — Sector first stage (6-dim)
`time_variation × instrument_weight × baseline × alignment × FE × exposure_control`
Instrument-weight variants: `owner_count`, `employment`, `equal_firm`, `binary`.

### Standard errors and FE

| Level | Default FE | Default clustering |
|---|---|---|
| Firm | `firm_id + muni_id^year` | firm + muni |
| Sector A (Panel A) | `muni_id^cnae_section + cnae_section^year` | muni + sector |
| Muni B (Panel B) | `muni_id + year` | muni |

---

## Current Project State

| Component | File | Status |
|-----------|------|--------|
| Paper | `paper/main.tex` | draft — specs in `paper/sections/regs.tex` (not yet `\input{}`-ed) |
| Data pipeline | `scripts/R/` | complete — 55 scripts, stages 11→54, all operational |
| First stage (firm) | `5_estimation/51_*` | in-progress — 8-dim spec engine |
| First stage (sector) | `5_estimation/53_*` | in-progress — 6-dim spec engine |
| Second stage | `5_estimation/54_*` | in-progress — reduced form, scalar/vector 2SLS |
| Aggregation analysis | `journal/meetings/2026-03-26/slides.tex` | complete |
| Production crosswalk | `3_instruments/30f_*` | **pending** — `policy_block_active × S3` not yet built |
