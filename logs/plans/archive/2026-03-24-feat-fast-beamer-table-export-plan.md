---
title: "feat: Fast Beamer Table Export via Direct fixest Extraction"
type: feat
status: completed
date: 2026-03-24
origin: docs/brainstorms/2026-03-24-fast-beamer-table-export-brainstorm.md
---

# Fast Beamer Table Export via Direct fixest Extraction

## Overview

Replace the `save_beamer_table()` internals in `_utils/beamer_tables.R` with a new `save_beamer_table_v2()` that eliminates the `modelsummary` + `kableExtra` bottleneck, using direct `fixest` coefficient extraction and `sprintf`-based LaTeX generation. Target: reduce post-estimation table export from **15+ minutes to under 1 minute** for a full spec engine run (50+ tables).

## Problem Statement / Motivation

The current `save_beamer_table()` pipeline calls `modelsummary()` (expensive generic `tidy()` dispatch on every fixest model) and `kableExtra` (builds a full LaTeX document), then `.strip_to_tabular()` immediately discards most of the kableExtra output. This is the post-estimation bottleneck — table formatting often exceeds estimation time in script 51's spec engine battery.

All models in this pipeline are `fixest` objects. Everything needed is directly extractable via `fixest::coeftable()`, `fitstat()`, `$fixef_vars`, and cached Wald stats. The LaTeX output is a highly structured ~30-line booktabs template that `sprintf` handles trivially.

(See brainstorm: `docs/brainstorms/2026-03-24-fast-beamer-table-export-brainstorm.md`)

## Proposed Solution

### Approach: Direct fixest extraction + sprintf LaTeX (Approach 1 from brainstorm)

New function `save_beamer_table_v2()` with the same signature as `save_beamer_table()` minus the `write_md` parameter. Runs in parallel during validation, then replaces the original.

**Rejected alternatives** (from brainstorm):
- **Keep kableExtra:** Partial speedup only (3–5× vs 10–50×); kableExtra overhead is wasted since `.strip_to_tabular()` discards most output.
- **`fixest::etable`:** Less control over custom features (bold F≥10, dep var header, FE label map, `\sbox0` wrapper); significant post-processing needed.

### Key Design Decisions (carried from brainstorm)

1. **Parallel v2 period**: `save_beamer_table_v2()` alongside `save_beamer_table()`. Validate by comparing `.tex` output, then swap.
2. **Output**: `.tex` only — drop `.md` generation entirely (confirmed unnecessary).
3. **Same signature**: `mods`, `filename`, `coef_map`, `fe_labels`, `add_f_stat`, `dep_var`, `notes`, `font_size`, `digits`, `table_dir`, `stars`. Remove `write_md` and `...`.
4. **LaTeX fidelity**: Same booktabs structure, `\sbox0` wrapper, bold F≥10, dep var header. Minor whitespace differences acceptable.
5. **Reuse helpers**: `.get_fe_info()`, `.get_clustering_info()`, `.build_fstat_row_only()` — these are fast.
6. **Dependencies**: `modelsummary` and `kableExtra` remain importable for v1 during transition, removed after.

## Technical Considerations

### Gaps and Edge Cases Identified (from SpecFlow analysis)

**Critical — must address:**

| # | Gap | Resolution |
|---|-----|------------|
| 1 | Collinear variables: `coef(mod)` returns fewer coefficients than the formula; absent coefficients must render as empty cells | Build an `n_coefs × n_models` matrix; fill NA for absent coefficients |
| 2 | `coef_map` ordering determines row order | Iterate `coef_map` names in order, not fixest return order |
| 3 | Auto-detect path (`coef_map=NULL`): all 3 callers use this | Match union of `names(coef(m))` against `COEF_MAP_INSTRUMENTS`; preserve existing two-stage fallback |
| 6 | P-value extraction: avoid `summary(mod)` which triggers full recompute | Use `fixest::coeftable(mod)` — single call returning Estimate, SE, p-value |
| 11 | **Wald cache mismatch**: script 51 caches with pattern `"^(FA_\|dFA_)"` but table function defaults to `"^(dZ_\|Z_\|FA_\|dFA_)"` — cache is never used | Use cached stat unconditionally when `politicsregs_wald_stat` attribute is present; fall back to `fixest::wald()` only when absent |
| 15 | `.strip_to_tabular()` reuse vs replace | v2 generates complete output directly (sbox + tabular + footnote); `.strip_to_tabular()` is not needed for v2 |
| 17–18 | LaTeX escaping: v1 double-escapes for kableExtra; v2 must NOT | Write `notes` and `dep_var` verbatim — they already contain valid LaTeX |

**Important — should address:**

| # | Gap | Resolution |
|---|-----|------------|
| 5 | `lean=TRUE` models: verify `coeftable()` works | It does — vcov is stored even in lean mode. Add a unit check. |
| 7 | Star threshold boundaries: `p < 0.10` = `*`, `p < 0.05` = `**`, `p < 0.01` = `***` (strict less-than, matching modelsummary) | Implement with strict `<` comparisons |
| 10 | Script 52 F-stat blank: `FA_bar_*` doesn't match default keep pattern | Broaden default to `"^(dZ_\|Z_\|FA_\|dFA_\|FA_bar_)"` |
| 19 | `font_size` is a no-op in v1 (kableExtra sets it, `.strip_to_tabular()` strips it) | Accept parameter, continue ignoring it, add explanatory comment |
| 21 | R² extraction: use `fixest::r2(mod, "r2")` to match v1 | Confirmed — standard R², not within |
| 26 | Unnamed model list: `names(mods)` returns NULL | Auto-generate `(1)`, `(2)`, ... with a warning |

**Defensive — nice to have:**

| # | Gap | Resolution |
|---|-----|------------|
| 20 | `capture.output()` overhead in Wald computation | Replace with `suppressMessages()` |
| 22 | Large N formatting | Use `formatC(nobs(mod), format="d", big.mark=",")` |
| 23 | Remove `...` from signature (no callers use it) | Remove for cleaner argument validation |
| 24 | Return `invisible(tex_path)` | Preserve existing contract |
| 25 | Input validation: must be named list of fixest objects | `stopifnot()` at top of function |
| 31 | `digits` must be numeric | Validate with `is.numeric(digits)` |

### Performance

- **Primary bottleneck**: `modelsummary()` tidy dispatch (~80% of time per call)
- **Secondary bottleneck**: kableExtra LaTeX document generation + stripping (~15%)
- **Wald cache fix** (Gap 11): currently recomputes on every call despite caching — fixing this alone may provide 2–3× speedup on top of the modelsummary elimination
- **Expected speedup**: 10–50× per call, from ~18s/table to <1s/table

## Acceptance Criteria

- [x] `save_beamer_table()` produces structurally equivalent LaTeX (validated: 0 mismatches across 4 configs)
- [x] Table export completes in <0.1s per table (validated: 48–943× speedup vs old v1)
- [ ] Full script 51 `--specs=all` run completes table export in under 2 minutes (vs. current 15+ minutes)
- [x] Coefficient values, stars, SEs, FE rows, F-stats, N, and R² match v1 output for a reference run
- [x] `\sbox0` auto-scaling wrapper and footnote positioning match v1 structure
- [x] No `modelsummary` or `kableExtra` calls in code path
- [x] Wald stat cache is actually used when present (Gap 11 fix)
- [x] All existing callers (scripts 51, 52, 53) work after cleanup (write_md removed from script 51)
- [x] Old v1 removed, modelsummary/kableExtra imports removed, .strip_to_tabular deleted

## Implementation Phases

### Phase 1: Core `save_beamer_table_v2()` function

**File**: `BNDES/politicsregs/_utils/beamer_tables.R`

**Tasks:**

1. **Coefficient extraction engine** (`_utils/beamer_tables.R`)
   - New internal helper `.extract_coef_matrix(mods, coef_map, digits, stars)`:
     - For each model, call `fixest::coeftable(mod)` once → matrix with Estimate, SE, p-value
     - Build `n_coefs × n_models` matrices for formatted coefficients (with stars) and SEs (in parentheses)
     - Handle absent coefficients (collinearity, different formulas) as empty strings
     - Apply `coef_map` filtering and label substitution, preserving `coef_map` order
     - Auto-detect path: union of `names(coef(m))` matched against `COEF_MAP_INSTRUMENTS` when `coef_map=NULL`
   - Star thresholds: `p < 0.01` → `***`, `p < 0.05` → `**`, `p < 0.10` → `*` (strict `<`)
   - Format: `sprintf("%.Nf%s", coef, stars)` for coefficients, `sprintf("(%.Nf)", se)` for SEs

2. **GOF extraction** (`_utils/beamer_tables.R`)
   - New internal helper `.extract_gof_rows(mods, digits)`:
     - N via `formatC(nobs(mod), format="d", big.mark=",")`
     - R² via `sprintf("%.3f", fixest::r2(mod, "r2"))`

3. **LaTeX template assembly** (`_utils/beamer_tables.R`)
   - `save_beamer_table_v2()` main function:
     - Input validation: named list of fixest objects, numeric digits
     - Auto-generate names `(1)`, `(2)`, ... if `names(mods)` is NULL
     - Call `.extract_coef_matrix()`, `.get_fe_info()`, `.get_clustering_info()`, `.build_fstat_row_only()`
     - Assemble LaTeX via `sprintf`/`paste`:
       ```
       \sbox0{%
       \begin{tabular}[t]{lcc...}
       \toprule
       [optional dep_var multicolumn header + cmidrule]
       [column name headers]
       \midrule
       [coefficient + SE row pairs]
       \midrule
       [FE checkmark rows if varying]
       [F-stat row if add_f_stat=TRUE]
       Observations & N1 & N2 & ...\\
       $R^2$ & r1 & r2 & ...\\
       \bottomrule
       \end{tabular}
       }%
       [ifdim auto-scale block with footnote]
       ```
     - Build footnote from `notes` (verbatim, no double-escaping) or auto-generate from FE+clustering+stars
     - Write to `file.path(table_dir, paste0(filename, ".tex"))` via `writeLines()`
     - Return `invisible(tex_path)`

4. **Fix Wald cache mismatch** (`_utils/beamer_tables.R`)
   - In `.build_fstat_row_only()`: when `politicsregs_wald_stat` attribute is present, use it directly without pattern matching. Only fall back to `fixest::wald()` when the attribute is absent.
   - Broaden default `keep_pat` to `"^(dZ_|Z_|FA_|dFA_|FA_bar_)"` for the fallback path (fixes script 52 blank F-stats).
   - Replace `capture.output()` with `suppressMessages()`.

5. **`font_size` parameter**: accept but ignore, with comment explaining the v1 no-op behavior.

### Phase 2: Validation harness

**File**: `BNDES/politicsregs/_utils/beamer_tables.R`

**Tasks:**

1. **Dual-output validation mode**:
   - Environment variable `BEAMER_TABLE_VALIDATE=TRUE` triggers both v1 and v2
   - v2 output written to `filename_v2.tex` alongside v1's `filename.tex`
   - Console log: structured comparison of coefficient values, stars, GOF stats, and FE rows between v1 and v2
   - Report mismatches with model name, row, and column for easy debugging

2. **Timing comparison**:
   - Wrap both v1 and v2 in `system.time()` during validation mode
   - Log `v1_elapsed` and `v2_elapsed` per call to console
   - Script 51's existing `elapsed_table` measurement will capture v2 timing in the manifest

### Phase 3: Caller migration and cleanup

**Files**: `51_firm_first_stage.R`, `52_aggregated_firm_sector_first_stage.R`, `53_sector_first_stage.R`, `_utils/beamer_tables.R`

**Tasks:**

1. **Switch callers to v2**:
   - Script 51 (`5_estimation/51_firm_first_stage.R`): change `save_beamer_table(` → `save_beamer_table_v2(`, remove `write_md = FALSE` argument
   - Script 52 (`5_estimation/52_aggregated_firm_sector_first_stage.R`): change 4 calls
   - Script 53 (`5_estimation/53_sector_first_stage.R`): change 7 calls

2. **Run validation**: Execute `BEAMER_TABLE_VALIDATE=TRUE Rscript run_politicsregs.R 51 --specs=baseline` and verify zero mismatches

3. **Performance verification**: Run `51 --specs=all` and compare aggregate table timing from manifest

4. **Final cleanup** (`_utils/beamer_tables.R`):
   - Rename `save_beamer_table_v2` → `save_beamer_table`
   - Delete old `save_beamer_table` implementation
   - Delete `.strip_to_tabular()` (no longer needed)
   - Remove `modelsummary` and `kableExtra` from library calls (if not used elsewhere)
   - Remove validation harness code
   - Update callers back to `save_beamer_table(`

## Success Metrics

- **Primary**: Full `--specs=all` table export time < 2 minutes (measured via script 51 manifest)
- **Correctness**: Zero coefficient/star/GOF mismatches in validation run
- **LaTeX**: Tables compile identically in Beamer presentation (visual inspection of 3–5 representative tables)

## Dependencies & Risks

- **Risk**: `fixest::coeftable()` behavior on edge-case models (zero coefficients, all collinear). **Mitigation**: input validation + NA handling.
- **Risk**: Subtle LaTeX formatting differences cause validation noise. **Mitigation**: accept whitespace differences; compare structured values not raw strings.
- **Risk**: `lean=TRUE` models may not support all extraction functions in future fixest versions. **Mitigation**: version-pin fixest or add a quick smoke test.
- **Dependency**: Existing helpers (`.get_fe_info()`, `.get_clustering_info()`, `.build_fstat_row_only()`) must remain unchanged during Phase 1–2.

## Sources & References

### Origin

- **Brainstorm document**: [docs/brainstorms/2026-03-24-fast-beamer-table-export-brainstorm.md](docs/brainstorms/2026-03-24-fast-beamer-table-export-brainstorm.md) — Key decisions: direct fixest extraction approach, v2 parallel validation, .tex-only output, same signature minus write_md.

### Internal References

- Current implementation: `BNDES/politicsregs/_utils/beamer_tables.R` (478 lines)
- Best-practice standard: `docs/solutions/best-practices/latex-regression-tables-beamer-standard.md`
- Primary caller (spec engine): `BNDES/politicsregs/5_estimation/51_firm_first_stage.R:1090`
- F-stat caching: `BNDES/politicsregs/5_estimation/51_firm_first_stage.R:578-593`
- Caller script 52: `BNDES/politicsregs/5_estimation/52_aggregated_firm_sector_first_stage.R:284,316,350,383`
- Caller script 53: `BNDES/politicsregs/5_estimation/53_sector_first_stage.R:375-532`
