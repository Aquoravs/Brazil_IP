---
title: "refactor: Extend script 52 into full sector-level spec engine"
type: refactor
status: completed
date: 2026-04-06
---

# Extend Script 52 into Full Sector-Level Spec Engine

## Overview

Refactor `scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R` from a
fixed aggregated-firm regression script into a full sector-level spec engine with
9 configurable dimensions, 4 outcomes, 4 sector classifications, and 3
aggregation weight variants. This replaces the current hardcoded
alignment×exposure×weighting loop with the same DIMENSION_OPTIONS / SPEC_CATALOG
/ parse_cli_args architecture used in script 51.

## Problem Frame

Script 52 currently collapses the firm panel to (sector, muni, year) cells and
runs a fixed set of 8 tables (2 alignments × 2 exposures × 2 weightings) with a
single outcome (`H_jmt` = BNDES extensive margin share). The design session
decided to extend it into the main sector-level estimation script supporting:

- 4 outcomes (bndes_share, bndes_extensive, log_employment, employment_share)
- 4 sector classifications (cnae_section, custom_sector, bndes_sector, size_bin)
- 3 aggregation weights (owner_count, equal_firm, employment)
- 2 regression weights (unweighted, emp_weighted)
- 2 exposures, 2 baselines, 2 alignments, 2 FE specs, 2 exposure_control options
- 6 instrument combos per config

## Requirements Trace

- R1. Nine-dimension spec engine matching the design session table
- R2. New sector classifications: bndes_sector (4 BNDES macro-sectors) and size_bin (3 terciles)
- R3. Four outcomes computed at sector-muni-year level from firm panel
- R4. Three aggregation weight variants for collapsing firms to cells
- R5. Pre-election employment weights for WLS regression (never contemporaneous)
- R6. CLI interface mirroring script 51 (--specs, --outcome, --sector-var, etc.)
- R7. F-stat grid tables in Beamer format, bare tabular .tex files
- R8. Run manifest CSV + coefficient summary .qs2
- R9. Two-way clustering by muni_id + sector_var
- R10. Proposition 2 mode preserved (separated to own script)

## Scope Boundaries

- Time variation is fixed to levels only — no changes dimension
- No changes to scripts 30, 31, 33, 41, or 42
- No changes to script 51 (firm-level)
- Script 53 (existing sector spec engine using muni panel) is NOT replaced — it
  operates on the pre-built muni×sector panel from script 41, while this script
  operates on the firm panel from script 42 and collapses it internally
- No interaction instrument family (main combos only: M, G, P, M+G, M+P, All)

## Context & Research

### Relevant Code and Patterns

- **Script 51** (`51_firm_first_stage.R`, 1335 lines): Canonical spec-engine
  architecture. Defines DIMENSION_OPTIONS, DEFAULT_DIMENSIONS, SPEC_CATALOG,
  parse_cli_args(), resolve_requested_configs(), expand_dimension_grid(). Main
  loop iterates config_dt rows, fits 6 combos, saves beamer table + manifest +
  summary. Groups configs by baseline to minimize panel reloads.
- **Script 52** (`52_aggregated_firm_sector_first_stage.R`, 1843 lines): Current
  script. Steps 1-4 do the default aggregated regressions. Steps 5+ do
  Proposition 2 equivalence tests (~800 lines). The collapse logic in
  `collapse_agg_panel()` computes simple means or employment-weighted means of
  FA_* columns and `has_bndes_fmt`.
- **Script 53** (`53_sector_first_stage.R`, 849 lines): Sector spec engine using
  the muni×sector panel (from script 41). Has its own DIMENSION_OPTIONS with
  instrument_weight dimension mapping to Z_* column prefixes. Saves manifest +
  summary. Good reference for sector-level table notes and slug building.
- **Script 30** (`30_build_sector_groups.R`): Builds custom_sector crosswalk
  from cnae_section. Saves to `output/sector_group_mapping.qs2`. Pattern for new
  crosswalk scripts.
- **Script 31** (`31_build_sector_exposure_weights.R`): Builds w_mjp weights at
  (muni, sector, party, year) level. Has owner_count, employment, equal_firm,
  binary variants. Loads sector_group crosswalk when --sector-var=sector_group.
- **Script 42** (`42_build_firm_panel.R`): Builds firm×muni×year panel with
  outcomes (has_bndes_fmt, log_bndes_fmt, log_n_employees, emp_share_muni_rais)
  and their delta_ variants. Has n_employees, cnae_section, value_dis_real_2018_total.
- **beamer_tables.R**: `save_beamer_table()` takes a named list of fixest models,
  outputs bare tabular .tex. Supports dep_var header, F-stat rows, FE checkmarks,
  exposure_control_gof, notes.

### Key Observations from Code

1. **Script 52's collapse already supports two weighting modes** (unweighted =
   simple mean, emp_weighted = employment-weighted mean). The new "aggregation"
   dimension generalizes this to three modes.
2. **The firm panel (script 42) has cnae_section** but not sector_group or
   bndes_sector. Script 52 already handles joining sector_group from the crosswalk
   when needed (lines 728-737). Same pattern extends to bndes_sector and size_bin.
3. **Script 52's Proposition 2 mode** is ~800 lines of specialized code for
   testing aggregation equivalence. It has its own sample construction, FE
   variants, and comparison logic. It should be separated.
4. **Pre-election employment weights**: Script 52 uses `n_employees` from the
   firm panel as cell weights when collapsing. For the regression_weight dimension,
   we need cell-level pre-election employment summed from firm-level n_employees
   within the baseline window — the same `emp_pre` column that
   `collapse_agg_panel()` already computes.
5. **Script 53 loads the muni×sector panel** (from script 41) which already has
   pre-built Z_* instruments. Script 52 loads the firm panel and collapses FA_*
   instruments. These are different aggregation approaches — script 52's approach
   is the "aggregated firm" approach that the design session chose to extend.

## Key Technical Decisions

- **Refactor script 52 in place, extract Proposition 2 to new script**: Script
  52 is the right home for the sector-level aggregated-firm spec engine. The
  Proposition 2 code (~800 lines) is a specialized validation tool with different
  sample construction and FE variants — it belongs in its own script
  (`52b_proposition2_equivalence.R`). This keeps script 52 focused and under
  ~1200 lines.

- **Build crosswalks in new preprocessing scripts**: bndes_sector and size_bin
  crosswalks should be built in scripts `30b_build_bndes_sector_mapping.R` and
  `30c_build_size_bin_mapping.R`, following the pattern of script 30. Reasons:
  (a) crosswalks are reusable by scripts 31, 33, 41, 53; (b) they have their own
  data dependencies; (c) script 52 should load crosswalks, not build them.

- **Collapse step computes all outcomes and weight variants in one pass**: For
  each (sector_var, exposure, aggregation) triple, collapse the firm panel to
  (sector, muni, year) cells computing all 4 outcomes simultaneously. This avoids
  redundant groupby operations. The collapse produces one data.table per
  (sector_var, aggregation) combination with FA_bar_* instruments and all outcome
  columns.

- **Aggregation-regression weight pairing is advisory, not enforced**: The
  design session noted that unweighted pairs with equal_firm and emp_weighted
  pairs with employment aggregation. The spec catalog encodes these pairings in
  named bundles, but the engine does not hard-block cross-pairings — they are
  just not in any default bundle.

- **FE formulas parameterized by sector_var**: Like script 53's
  `build_fe_formula(fe_key, sector_col)`, the FE string is built dynamically from
  the sector_var dimension value.

- **Output directory follows sector_var**: Tables go to
  `paper/tables/agg_firm_{sector_var}/` (e.g., `agg_firm_bndes_sector/`,
  `agg_firm_size_bin/`). This extends the current pattern where
  `agg_firm_grouped` = custom_sector.

## Open Questions

### Resolved During Planning

- **Should script 53 be deprecated?** No. Script 53 uses the pre-built
  muni×sector panel (script 41) with pre-constructed Z_* instruments. Script 52
  uses the firm panel and collapses FA_* instruments to sector level. These are
  complementary approaches with different instrument construction methods.

- **Where does bndes_share come from?** It must be computed during the collapse
  step. For each cell (sector, muni, year), sum firm-level BNDES credit, then
  divide by municipal total. Requires `value_dis_real_2018_total` from the firm
  panel.

- **How to handle size_bin — it's not an industry classification?** The
  size_bin crosswalk maps (firm_id, election_cycle) → size_bin based on
  pre-election average n_employees terciles across all firms nationally.
  Per-cycle pre-election windows avoid endogeneity (treatment could affect
  employment) while preventing staleness (natural firm growth updates the
  classification). The "sector" variable becomes size_bin, and cells are
  (size_bin, muni, year). FE and clustering use size_bin as the sector
  variable, just like any other classification.

- **What is the reference year for exposure control interactions?** Use
  `min(year)` from the estimation sample, same as script 53 (line 675).

### Deferred to Implementation

- Exact n_employees tercile cutpoints for size_bin — depends on data distribution (computed across all firms nationally per cycle)
- Whether `bndes_extensive` (share of pre-election firms receiving BNDES) needs
  the same F_pre support filter that script 52 currently applies — likely yes
- Performance of the full combinatorial grid — may need to profile and optimize
  the collapse step for large sector_var options (cnae_section × muni × year)

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review,
> not implementation specification. The implementing agent should treat it as
> context, not code to reproduce.*

```
CLI args → parse_cli_args() → resolve_requested_configs() → config_dt
                                                                |
                                                                v
For each unique (sector_var, baseline) in config_dt:
  1. Load firm panel (script 42 output)
  2. Join sector classification crosswalk (sector_group, bndes_sector, or size_bin)
  3. Apply F_pre support filter (same as current step 2)
  4. For each unique aggregation weight in this group's configs:
     a. Collapse firm panel → (sector, muni, year) cells
        - Compute FA_bar_* instruments (mean or weighted mean of FA_*)
        - Compute all 4 outcome variables at cell level
        - Compute emp_pre (pre-election cell employment for WLS)
     b. Cache the collapsed panel
  5. For each config row:
     a. Select the cached collapsed panel for this aggregation weight
     b. Build formula: outcome ~ instruments [+ exposure_control] | FE
     c. Run 6 combos (M, G, P, M+G, M+P, All)
     d. Save beamer table, append to manifest + summary
  6. Save manifest CSV + summary .qs2
```

## Implementation Units

- [ ] **Unit 1: Extract Proposition 2 to `52b_proposition2_equivalence.R`**

  **Goal:** Separate the ~800 lines of Proposition 2 code from script 52 into
  its own standalone script, preserving all functionality.

  **Requirements:** R10

  **Dependencies:** None

  **Files:**
  - Create: `scripts/R/5_estimation/52b_proposition2_equivalence.R`
  - Modify: `scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R`

  **Approach:**
  - Move everything from `# STEP 5: Proposition 2 equivalence test` onward
    (lines ~1088-1843) plus supporting functions (`get_prop2_terms`,
    `build_prop2_sample`, `filter_single_cell_firms`,
    `filter_balanced_within_regime`, `compare_model_coefficients`,
    `build_prop2_notes`, `build_prop2_fe_notes`, `build_prop2_fe_labels`,
    `save_prop2_tables`) to the new script
  - The new script loads the firm panel, applies F_pre filter, and runs
    Proposition 2 tests — it's self-contained
  - Remove PROPOSITION2, COMPARE_51, SINGLE_CELL, BALANCED flags and all
    prop2-related CLI parsing from script 52
  - Keep `collapse_agg_panel()` and the historical step-4 code in script 52
    for now (Unit 3 replaces them)

  **Patterns to follow:**
  - Script 52's existing bootstrap and panel loading pattern

  **Verification:**
  - 52b runs independently with `--proposition2` and produces identical tables
  - Script 52 runs without `--proposition2` flag and produces the same 8 default
    tables as before

- [ ] **Unit 2: Build bndes_sector and size_bin crosswalks**

  **Goal:** Create two new crosswalk scripts following the pattern of script 30.

  **Requirements:** R2

  **Dependencies:** None (parallel with Unit 1)

  **Files:**
  - Create: `scripts/R/3_instruments/30b_build_bndes_sector_mapping.R`
  - Create: `scripts/R/3_instruments/30c_build_size_bin_mapping.R`

  **Approach — bndes_sector:**
  - Read `data/raw/sector_mapping.csv` (columns: setor_bndes, codigo_cnae_ibge)
  - Parse CNAE codes from `codigo_cnae_ibge` (format: "C10", "A01 a A03",
    "D351", "F41 e F43", "H49 (restante)")
  - For CNAE codes with multiple rows (different `produto_bndes`), keep the row
    where `produto_bndes = "Todos"` (broadest applicability). If no "Todos" row,
    keep the row that is NOT "Somente X" (i.e., the default/exclusion row)
  - Build crosswalk: cnae_section → bndes_sector (4 values: Agropecuária,
    Indústria, Infraestrutura, Comércio e Serviços)
  - Since CNAE sections map to multiple bndes_sector depending on division, the
    crosswalk must be at cnae_division level (2-digit), then the firm panel join
    uses cnae_division (derived from the 5-digit CNAE code that produces
    cnae_section in script 22)
  - Actually, the mapping CSV uses CNAE section+division codes (e.g., "C10").
    Build crosswalk at cnae_division → bndes_sector level. For sections that map
    entirely (e.g., A, B), expand to all divisions within that section
  - Save to `output/bndes_sector_mapping.qs2` + summary CSV

  **Approach — size_bin:**
  - Load firm panel (script 42 output) — needs firm_id, n_employees, year
  - For each election cycle, compute mean n_employees per firm across the
    pre-election baseline window (same windows as script 33)
  - Classify firms into terciles (3 bins) across all firms nationally — not
    within CNAE section, since size_bin is a standalone classification
    orthogonal to industry
  - Per-cycle pre-election windows avoid endogeneity (political alignment could
    affect post-election employment) while preventing staleness (a firm's
    natural growth over 15 years should update its classification)
  - The crosswalk is: (firm_id, election_cycle) → size_bin
  - Save to `output/size_bin_mapping.qs2` + summary CSV
  - Note: size_bin is firm-level, not industry-level. The cell becomes
    (size_bin, muni, year) — size_bin replaces the industry classification

  **Patterns to follow:**
  - Script 30 structure: config, step-by-step with cat() progress, save .qs2 +
    summary CSV, atomic writes

  **Verification:**
  - bndes_sector mapping covers all 21 CNAE sections (or all relevant divisions)
  - 4 distinct bndes_sector values produced
  - size_bin has 3 bins per election cycle, roughly equal firm counts per tercile
  - No firm is left unclassified

- [ ] **Unit 3: Rewrite script 52 as spec engine**

  **Goal:** Replace the hardcoded alignment×exposure×weighting loop with the
  9-dimension spec engine architecture.

  **Requirements:** R1, R3, R4, R5, R6, R7, R8, R9

  **Dependencies:** Unit 1 (Proposition 2 extracted), Unit 2 (crosswalks built)

  **Files:**
  - Modify: `scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R`

  **Approach — Spec engine infrastructure** (mirroring script 51):
  ```
  DIMENSION_OPTIONS:
    outcome          = [bndes_share, bndes_extensive, log_employment, employment_share]
    exposure         = [pooled_count, binary]
    aggregation      = [owner_count, equal_firm, employment]
    regression_weight= [unweighted, emp_weighted]
    sector_var       = [cnae_section, custom_sector, bndes_sector, size_bin]
    baseline         = [cycle_specific, 2002_fixed]
    alignment        = [coalition, party]
    fe               = [mxj_jxt, mxj_mxt]
    exposure_control = [yes, no]

  DEFAULT_DIMENSIONS:
    outcome          = bndes_share
    exposure         = pooled_count
    aggregation      = owner_count
    regression_weight= unweighted
    sector_var       = custom_sector
    baseline         = cycle_specific
    alignment        = coalition
    fe               = mxj_jxt
    exposure_control = yes

  SPEC_CATALOG:
    baseline         = {}  (all defaults)
    emp_weighted     = {aggregation: employment, regression_weight: emp_weighted}
    equal_firm       = {aggregation: equal_firm}
    party            = {alignment: party}
    fixed_baseline   = {baseline: 2002_fixed}
    binary           = {exposure: binary}
    fe_muni_year     = {fe: mxj_mxt}
    no_controls      = {exposure_control: no}
    all_outcomes     = {outcome: [bndes_share, bndes_extensive, log_employment, employment_share]}
    all_sectors      = {sector_var: [cnae_section, custom_sector, bndes_sector, size_bin]}
    weight_battery   = {aggregation: [owner_count, equal_firm, employment]}
  ```

  **Approach — Collapse step:**
  - Generalize `collapse_agg_panel()` to accept an `aggregation` parameter:
    - `owner_count`: pool raw FA_* values (current unweighted mean behavior —
      firms with more affiliated owners naturally contribute more)
    - `equal_firm`: each firm weighted 1/N (current simple mean, same as
      owner_count for the mean — but the distinction matters for the instrument:
      owner_count sums raw affiliated owner counts, equal_firm takes the mean of
      the per-firm share)
    - `employment`: weight by pre-election n_employees (current emp_weighted)
  - Compute all 4 outcomes during collapse:
    - `bndes_share`: sum(value_dis_real_2018_total) for this cell / sum across
      all sectors in same (muni, year). Requires loading value_dis_real_2018_total
    - `bndes_extensive`: mean(has_bndes_fmt) — share of pre-election firm base
      with any BNDES (already computed as H_jmt)
    - `log_employment`: log(sum(n_employees)) at cell level
    - `employment_share`: sum(n_employees) for cell / sum across all sectors in
      same (muni, year)
  - Compute `emp_pre`: sum of pre-election n_employees in the cell (for WLS)

  **Approach — Main loop:**
  - Group configs by (sector_var, baseline) to minimize panel reloads
  - Within each group, further group by aggregation to cache collapsed panels
  - For each config: select collapsed panel, build formula, run 6 combos, save
    beamer table, append manifest + summary
  - Slug format: `agg_firm__{outcome}__{alignment}__{baseline}__{aggregation}__{regression_weight}__{fe}__{exposure_control}__{exposure}`

  **Approach — Table output:**
  - Table directory: `paper/tables/agg_firm_{sector_var}/`
    - `agg_firm/` → cnae_section (backward compatible)
    - `agg_firm_grouped/` → custom_sector (backward compatible)
    - `agg_firm_bndes_sector/` → bndes_sector
    - `agg_firm_size_bin/` → size_bin
  - Use `save_beamer_table()` from beamer_tables.R (same as current)
  - Manifest: `{table_dir}/agg_firm_run_manifest.csv` + `.qs2`
  - Summary: `{table_dir}/agg_firm_fc_battery_summary.qs2`

  **Approach — Clustering:**
  - `VCOV = ~ muni_id + {sector_var}` — two-way by municipality and whatever
    sector classification is active

  **Approach — CLI:**
  ```
  Rscript run_politicsregs.R 52 [OPTIONS]
    --specs=NAME[,NAME]           Named bundles (default: baseline)
    --outcome=VAL[,VAL]           bndes_share, bndes_extensive, log_employment, employment_share
    --exposure=VAL[,VAL]          pooled_count, binary
    --aggregation=VAL[,VAL]       owner_count, equal_firm, employment
    --regression-weight=VAL[,VAL] unweighted, emp_weighted
    --sector-var=VAL[,VAL]        cnae_section, custom_sector, bndes_sector, size_bin
    --baseline=VAL[,VAL]          cycle_specific, 2002_fixed
    --alignment=VAL[,VAL]         coalition, party
    --fe=VAL[,VAL]                mxj_jxt, mxj_mxt
    --exposure-control=VAL[,VAL]  yes, no
    --test                        10% municipality subsample
    --dry-run                     Print resolved configs and exit
  ```

  **Patterns to follow:**
  - Script 51's parse_cli_args, resolve_requested_configs, main loop, manifest/
    summary saving, merge_existing_runs pattern
  - Script 53's build_fe_formula, build_table_notes, run_six_combos
  - Script 52's current collapse_agg_panel (generalized)

  **Verification:**
  - `--specs=baseline --dry-run` shows exactly 1 config with all defaults
  - `--specs=baseline` produces the same F-stats as the current script 52 default
    (bndes_extensive outcome, owner_count aggregation, unweighted, coalition,
    mxj_jxt FE, cycle_specific baseline, exposure_control=yes)
  - `--specs=all_outcomes --sector-var=bndes_sector` runs without error
  - `--specs=weight_battery` runs 3 configs (one per aggregation weight)
  - Manifest CSV has one row per config with F-stat ranges and timing
  - Summary .qs2 has coefficient-level detail for all runs
  - Tables are bare tabular .tex with no `\begin{table}` wrapper
  - Two-way clustering confirmed in table notes

- [ ] **Unit 4: Backward compatibility and smoke tests**

  **Goal:** Verify the refactored script produces results consistent with the
  old script and runs correctly across sector classifications.

  **Requirements:** R1-R9

  **Dependencies:** Unit 3

  **Files:**
  - Modify: `scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R`
    (if fixes needed)

  **Approach:**
  - Run `--specs=baseline --sector-var=custom_sector` and compare F-stats against
    old script 52 output (tables in `paper/tables/agg_firm_grouped/`)
  - Run `--specs=baseline --sector-var=cnae_section` and compare against old
    `paper/tables/agg_firm/`
  - Run each new sector_var (bndes_sector, size_bin) with `--specs=baseline`
  - Run `--specs=all_outcomes` for each sector_var
  - Run `--specs=weight_battery` to exercise all aggregation weights
  - Verify manifest and summary files are well-formed
  - Check that table .tex files are valid bare tabular (parse for `\begin{tabular}`,
    `\toprule`, `\bottomrule`, no `\begin{table}`)

  **Patterns to follow:**
  - Script 51's `--dry-run` for quick config validation before full runs

  **Verification:**
  - F-stats for bndes_extensive + owner_count + custom_sector match old script 52
    output within floating-point tolerance
  - All 4 sector_var options produce non-empty tables
  - All 4 outcomes produce non-degenerate results (F > 0, N > 0)
  - No regressions crash or produce all-NA coefficients

## System-Wide Impact

- **Upstream scripts (30-42):** No modifications required. Script 52 loads the
  firm panel from script 42 and crosswalks from scripts 30/30b/30c. New
  crosswalk scripts (30b, 30c) are additive.
- **Script 53:** Unaffected. Continues to use the muni×sector panel from script
  41 with pre-built Z_* instruments.
- **Script 51:** Unaffected. Firm-level spec engine is independent.
- **beamer_tables.R:** No changes needed. `save_beamer_table()` already supports
  all required features (dep_var header, F-stat, FE checkmarks, notes).
- **paper/tables/ directory:** New subdirectories created (agg_firm_bndes_sector/,
  agg_firm_size_bin/). Existing directories (agg_firm/, agg_firm_grouped/)
  preserved with backward-compatible output.
- **run_politicsregs.R runner:** If it dispatches by script number, no changes
  needed — script 52 is already registered. Script 52b needs to be added if the
  runner supports it.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| bndes_sector mapping ambiguity (CNAE codes with product-line-dependent classification) | Use "Todos" rows as default; document exceptions in crosswalk summary |
| size_bin tercile instability (cycles with few firms) | Compute terciles across all firms nationally per election cycle; cycles with < 30 firms get a single bin (unlikely) |
| Collapse step memory for cnae_section (21 sectors × ~5500 munis × 16 years) | Max ~1.8M cells — manageable. Profile during implementation |
| Backward compatibility break if old table filenames change | Keep old slug format for baseline specs; new slugs only for new dimension combinations |
| emp_pre = 0 cells causing WLS issues | Filter cells with emp_pre = 0 before WLS regression (same as script 52's current behavior) |

## Sources & References

- Script 51 spec-engine architecture: `scripts/R/5_estimation/51_firm_first_stage.R`
- Script 52 current implementation: `scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R`
- Script 53 sector spec engine: `scripts/R/5_estimation/53_sector_first_stage.R`
- Script 30 crosswalk pattern: `scripts/R/3_instruments/30_build_sector_groups.R`
- BNDES sector mapping: `data/raw/sector_mapping.csv`
- Design session decisions: feature description in this plan's prompt
