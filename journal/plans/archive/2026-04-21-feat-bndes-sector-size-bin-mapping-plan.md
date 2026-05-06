---
title: "feat: Build BNDES-sector × size-bin classification and wire through pipeline"
type: feat
status: completed
date: 2026-04-21
origin: quality_reports/referee_response_tracker.md (C3)
scope: Build bndes_sector_size_bin mapping, wire into script 52, dry-run only — full battery deferred to run alongside C1/C2
---

# Build BNDES-Sector × Size-Bin Classification (C3 Prep)

## Overview

Create a new sector classification — `bndes_sector_size_bin` — that computes employment terciles *within* the 4 BNDES macro-sectors (Agropecuária, Indústria, Infraestrutura, Comércio e Serviços). Wire it through the estimation pipeline so regressions can be launched alongside the C1/C2 battery. This plan covers everything except the full regression run.

## Problem Frame

The advisor (C3, meeting 2026-04-17) asked to run the full first-stage battery using a new classification: terciles of firm employment computed within each of the 4 BNDES sectors. Two analogous classifications already exist — `cnae_size_bin` (terciles within CNAE sections) and `sector_group_size_bin` (terciles within custom sector groups). The new one follows the identical pattern but uses BNDES sectors as the parent grouping.

## Requirements Trace

- R1. Build firm-level crosswalk: `(firm_id, election_cycle) → bndes_sector_size_bin` with within-BNDES-sector employment terciles
- R2. Wire `bndes_sector_size_bin` as a valid `sector_var` in script 52 (aggregated estimation)
- R3. Wire into script 52b (summary compiler) so F-stat grids can be produced
- R4. Dry-run verification: confirm the new sector_var resolves to expected configs without running regressions
- R5. Full regression battery deferred — will run alongside C1/C2 commands

## Scope Boundaries

- Scripts 31, 33, 34, 35 do NOT need changes. They operate at the base sector level (cnae_section or sector_group). Script 52 handles size_bin variant joins internally via `join_sector_classification()`.
- Script 51 (firm-level) does NOT use `sector_var` — no changes needed.
- `run_politicsregs.R` just forwards args — no changes needed.
- No regressions will be run in this plan. Only dry-run to verify wiring.

## Context & Research

### Relevant Code and Patterns

The pipeline already has two sector × size-bin classifications that serve as exact templates:

| Classification | Parent grouping | Script | Output file |
|---|---|---|---|
| `cnae_size_bin` | CNAE section (21 sections) | 30d | `sector_size_bin_cnae_mapping.qs2` |
| `sector_group_size_bin` | Custom sector group (~8 groups) | 30d | `sector_size_bin_group_mapping.qs2` |
| **`bndes_sector_size_bin`** | **BNDES sector (4 sectors)** | **30d (extend)** | **`sector_size_bin_bndes_mapping.qs2`** |

### Key Existing Patterns

- **30d tercile logic** (lines 247-297): For each `(sector, election_cycle)`, computes `mean_emp` per firm in baseline window, then calls `assign_within_sector()` → `assign_size_bins()` to assign T1/T2/T3 via quantile breaks with rank-based fallback for ties.
- **30d composite key** (lines 307-308): `cnae_size_bin := paste(cnae_section, size_bin_cnae, sep = "_")` — produces keys like `"C_T2"`.
- **52 join pattern** (lines 1207-1231): `join_sector_classification()` has a block per size_bin variant that loads the crosswalk, merges on `(firm_id, sz_cycle)`, and assigns the composite column.
- **52 load guard** (line 1336): Lazy-loads sector_size_bin_maps only when config grid includes a size_bin variant.
- **52b GROUPINGS** (lines 29-51): Each sector classification gets a list entry with `dir`, `prefix`, `label`, `texcmd`, `slug_sv`.

### BNDES Sector Values

From script 30b (lines 134-156), the 4 macro-sectors and their CNAE section mappings:
- **Agropecuaria**: A
- **Industria**: B, C
- **Infraestrutura**: D, E, F, H
- **Comercio e Servicos**: G, I, J, K, L, M, N, O, P, Q, R, S, T, U

With only 4 parent sectors (vs 21 for CNAE, ~8 for sector_group), each tercile bin will contain many more firms — yielding 4 × 3 = 12 composite categories.

## Key Technical Decisions

- **Extend script 30d** rather than creating a new 30e. The script already builds two variants (CNAE and sector_group) in the same loop. Adding a third variant (bndes_sector) follows the same structure and avoids code duplication. The BNDES sector mapping loads from `bndes_sector_mapping.qs2` (output of script 30b), analogous to how sector_group loads from `sector_group_mapping.qs2` (script 30).

- **Composite key format**: `bndes_sector_size_bin := paste(bndes_sector, size_bin_bndes, sep = "_")`. This produces keys like `"Industria_T2"`, `"Agropecuaria_T1"`. Follows the established `{sector}_{Tn}` pattern.

- **Output column naming**: `size_bin_bndes` (tercile label T1/T2/T3) and `bndes_sector_size_bin` (composite key). Follows the existing naming convention: `size_bin_cnae` / `cnae_size_bin` and `size_bin_group` / `sector_group_size_bin`.

## Open Questions

### Resolved During Planning

- **Do scripts 31/34/35 need changes?** No. Script 52 handles size_bin variant joins internally. Those scripts only work with base sector classifications (cnae_section, sector_group).
- **Where does the BNDES sector mapping come from?** `bndes_sector_mapping.qs2` from script 30b. Maps cnae_section → bndes_sector.

### Deferred to Implementation

- **Thin-cell handling**: With only 4 parent BNDES sectors, Agropecuária (only section A) may have thin tercile bins in some cycles. The `assign_within_sector()` fallback (assign all to T1 if < 3 firms) handles this, but worth logging the cell counts.

---

## Implementation Units

- [x] **Unit 1: Extend script 30d to build bndes_sector_size_bin mapping**

  **Goal:** Add a third crosswalk variant to script 30d that computes within-BNDES-sector employment terciles.

  **Requirements:** R1

  **Dependencies:** None (bndes_sector_mapping.qs2 from script 30b already exists)

  **Files:**
  - Modify: `scripts/R/3_instruments/30d_build_sector_size_bin_mapping.R`

  **Approach:**
  1. In Step 2 (line ~162): load `bndes_sector_mapping.qs2` alongside `sector_group_mapping.qs2`. This maps `cnae_section → bndes_sector`.
  2. In Step 3 (line ~182): attach `bndes_sector` to the firm panel via cnae_section join (same pattern as sector_group).
  3. In Step 3 collapse (line ~193): carry `bndes_sector` through the firm-year aggregation.
  4. In Step 4 loop (line ~220): add a third block (after the sector-group block at line ~270) that iterates over unique `bndes_sector` values, calls `assign_within_sector()` per (bndes_sector, cycle), and collects results into `all_bndes_bins`.
  5. In Step 5 (line ~300): build composite key `bndes_sector_size_bin := paste(bndes_sector, size_bin_bndes, sep = "_")` and save to `sector_size_bin_bndes_mapping.qs2`.
  6. Add summary CSV output matching existing pattern.

  **Patterns to follow:**
  - Exact parallel with the sector_group block (lines 270-297 for loop, lines 323-350 for save)
  - Column naming: `size_bin_bndes` + `bndes_sector_size_bin`

  **Verification:**
  - Script runs without errors
  - `sector_size_bin_bndes_mapping.qs2` produced with columns: `firm_id`, `election_cycle`, `bndes_sector`, `size_bin_bndes`, `bndes_sector_size_bin`
  - 12 unique composite categories expected (4 sectors × 3 terciles), though some may collapse to fewer if Agropecuária has thin cells
  - Summary CSV shows row counts per cell

---

- [x] **Unit 2: Wire bndes_sector_size_bin into script 52**

  **Goal:** Make `bndes_sector_size_bin` a valid `sector_var` in the aggregated estimation engine.

  **Requirements:** R2

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R`

  **Approach — 6 touch points, all following existing patterns:**

  1. **DIMENSION_OPTIONS** (line 116-117): Add `"bndes_sector_size_bin"` to the `sector_var` vector.

  2. **SPEC_CATALOG** (line 156-157): Add `"bndes_sector_size_bin"` to the `size_bin_battery` bundle.

  3. **get_sector_label()** (line 500-509): Add case: `bndes_sector_size_bin = "BNDES sector $\\times$ firm-size tercile"`.

  4. **load_sector_size_bin_mappings()** (line 875+): Add a third element loading `sector_size_bin_bndes_mapping.qs2` with required column `bndes_sector_size_bin`. Return it as `$bndes` in the maps list.

  5. **join_sector_classification()** (line 1165+): Add a new `if (sector_var == "bndes_sector_size_bin")` block between the existing `cnae_size_bin` and `sector_group_size_bin` blocks. Pattern: check `sector_size_bin_maps$bndes`, merge on `(firm_id, sz_cycle)`, assign `bndes_sector_size_bin`.

  6. **build_supported_keys()** (line 1236+): Add matching block for `bndes_sector_size_bin`, following the `cnae_size_bin` pattern.

  7. **Lazy-load guard** (line 1336): Add `"bndes_sector_size_bin"` to the vector that triggers `load_sector_size_bin_mappings()`.

  **Patterns to follow:**
  - The `cnae_size_bin` blocks in each function — replicate with `bndes` substituted for `cnae`

  **Verification:**
  - Script sources without errors
  - `--dry-run` with `--sector-var=bndes_sector_size_bin` shows expected config grid

---

- [x] **Unit 3: Wire bndes_sector_size_bin into script 52b**

  **Goal:** Enable the summary compiler to produce F-stat grids for the new classification.

  **Requirements:** R3

  **Dependencies:** Unit 2

  **Files:**
  - Modify: `scripts/R/5_estimation/52b_agg_first_stage_summary.R`

  **Approach:**

  1. **GROUPINGS list** (lines 29-51): Add a new entry:
     - `dir = "agg_firm_bndes_sector_size_bin"` (or check existing naming convention)
     - `prefix = "bndes_sector_size_bin"`
     - `label = "BNDES Sector × Size Bin"`
     - `texcmd = "tbndessize"`
     - `slug_sv = "bndes_sector_size_bin"`

  2. **LaTeX command** (line ~199): Add `\newcommand{\tbndessize}{../tables/agg_firm_bndes_sector_size_bin}`.

  3. **Description slide switch** (line ~251): Add a `bndes_sector_size_bin` case describing the 4 BNDES macro-sectors × 3 terciles taxonomy.

  **Patterns to follow:**
  - The existing `bndes_sector` entry (lines 30-36) for structure
  - The `size_bin` entry (lines 44-50) for description content

  **Verification:**
  - Script sources without errors
  - After regressions run, 52b will pick up manifests from the new directory

---

- [x] **Unit 4: Run script 30d and dry-run script 52**

  **Goal:** Verify the full wiring end-to-end without running actual regressions.

  **Requirements:** R4

  **Dependencies:** Units 1-3

  **Approach:**

  1. Run the extended script 30d:
     ```bash
     Rscript scripts/R/3_instruments/30d_build_sector_size_bin_mapping.R
     ```
     Verify the new `.qs2` file is produced and has expected structure.

  2. Dry-run script 52 with the new sector_var:
     ```bash
     Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted --sector-var=bndes_sector_size_bin --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no --dry-run
     ```
     Verify the config grid shows expected combinations.

  3. Optionally run a single minimal regression (1 config) to confirm the full data pipeline works:
     ```bash
     Rscript scripts/R/run_politicsregs.R 52 --sector-var=bndes_sector_size_bin --outcome=bndes_extensive --alignment=coalition --fe=mxj_jxt --exposure-control=yes --dry-run
     ```

  **Verification:**
  - `sector_size_bin_bndes_mapping.qs2` exists with correct columns and ~12 unique composite keys
  - Dry-run prints config grid without errors
  - No unknown sector_var errors

---

## System-Wide Impact

- **No changes to upstream instrument scripts (31/33/34/35):** Script 52 handles size_bin variant classification joins internally. The instruments are built at base sector level; script 52 maps firms to the composite sector×size-bin key before aggregation.
- **Output directory:** New tables will land in `paper/tables/agg_firm_bndes_sector_size_bin/` — created automatically by script 52 on first run.
- **Manifest:** New rows in `agg_firm_bndes_sector_size_bin/agg_firm_run_manifest.csv` — no conflict with existing manifests.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Agropecuária has only CNAE section A — may have very few firms in some cycles, producing degenerate terciles | `assign_within_sector()` already handles this: falls back to T1-for-all when < 3 firms. Log cell counts to verify. |
| Script 30d needs bndes_sector_mapping.qs2 from script 30b | 30b is already run and output exists. Add existence check with clear error message. |

## Deferred: Full Regression Battery

After this plan is complete, add the following commands to the C1/C2 batch (Night 1 or Night 2):

```bash
# BNDES sector × size bin — full sample
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted --sector-var=bndes_sector_size_bin --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no

# BNDES sector × size bin — split samples
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted --sector-var=bndes_sector_size_bin --muni-sample=top_q4 --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no

Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted --sector-var=bndes_sector_size_bin --muni-sample=bottom_3q --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no
```

Estimated: ~576 additional regressions (3 samples × 2 specs × 2 outcomes × 2 align × 2 FE × 2 ctrl × 6 combos).
