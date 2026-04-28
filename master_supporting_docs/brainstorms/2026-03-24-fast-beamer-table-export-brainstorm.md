# Brainstorm: Fast Beamer Table Export

**Date:** 2026-03-24
**Status:** Ready for planning

## What We're Building

A drop-in-compatible replacement for `save_beamer_table()` in `_utils/beamer_tables.R` that eliminates the `modelsummary` and `kableExtra` dependencies, replacing them with direct `fixest` coefficient extraction and `sprintf`/`paste`-based LaTeX generation.

### Problem

The current `save_beamer_table()` is the post-estimation bottleneck:
- **50+ calls per pipeline run** (script 51 spec engine battery)
- **15+ minutes total** for table formatting alone — often exceeding estimation time
- Root cause: `modelsummary()` does expensive generic tidy dispatch on every call, and `kableExtra` builds a full LaTeX document that `.strip_to_tabular()` immediately strips back down

### Goal

Reduce post-estimation table export from 15+ minutes to under 1 minute for a full spec engine run, while producing structurally equivalent booktabs LaTeX output.

## Why This Approach

**Chosen approach: Direct fixest extraction + sprintf LaTeX (Approach 1)**

All models in this pipeline are `fixest` objects. We can extract everything we need directly:
- `coef(m)`, `se(m)`, `pvalue(m)` — coefficient table
- `fitstat(m, ~n + r2)` — GOF stats (N, R²)
- `m$fixef_vars` — FE info
- `fixest::wald(m, keep=...)$stat` — F-statistics (already cached via `politicsregs_wald_stat` attribute)

The LaTeX output format is highly structured and predictable:
- `\begin{tabular}` with booktabs (`\toprule`, `\midrule`, `\bottomrule`)
- Dep var spanning header via `\multicolumn`
- Coefficient rows with stars, SE rows in parentheses
- FE checkmarks, F-stat row, N/R² rows
- `\sbox0` auto-scaling wrapper with footnote

This is ~30 lines of LaTeX template that `sprintf` handles trivially.

### Rejected alternatives

- **Approach 2 (keep kableExtra):** Partial speedup only (3-5x vs 10-50x). kableExtra's overhead is wasted since `.strip_to_tabular()` discards most of its output anyway.
- **Approach 3 (fixest::etable):** Less control over custom features (bold F≥10, dep var header, FE label map, `\sbox0` wrapper). Would need significant post-processing to match current output.

## Key Decisions

1. **New function name for parallel period:** `save_beamer_table_v2()` alongside existing `save_beamer_table()`. Validate by comparing `.tex` output via git diff, then swap once confirmed equivalent.
2. **Output format:** `.tex` only. Drop `.md` generation entirely (confirmed unnecessary).
3. **Same function signature:** `save_beamer_table_v2()` accepts the same arguments (`mods`, `filename`, `coef_map`, `fe_labels`, `add_f_stat`, `dep_var`, `notes`, `font_size`, `digits`, `table_dir`, `stars`). Remove `write_md` parameter.
4. **LaTeX fidelity:** Same booktabs structure, midrule placement, `\sbox0` wrapper, bold F≥10, dep var header. Minor whitespace differences are acceptable.
5. **Dependencies removed:** `modelsummary` and `kableExtra` no longer needed by the new function. Keep them importable for the old function during transition.
6. **Existing helpers reused:** `.get_fe_info()`, `.get_clustering_info()`, `.build_fstat_row_only()` — these are fast (no modelsummary calls). Adapt their output for the sprintf path.

## Implementation Sketch (for planning phase)

The new function would:
1. Extract coefficients/SEs/p-values directly from fixest models
2. Apply `coef_map` filtering and label substitution
3. Add significance stars based on p-values
4. Format SE rows as `(0.123)`
5. Build FE/clustering/F-stat mid-section rows (reuse existing helpers)
6. Build GOF rows (N, R²)
7. Emit LaTeX via sprintf template:
   - `\sbox0{%` wrapper
   - `\begin{tabular}{lcc...}` with `\toprule`
   - Optional `\multicolumn` dep var header
   - Coefficient + SE rows
   - `\midrule` + mid-section + GOF rows
   - `\bottomrule` + `\end{tabular}`
   - `}%` close sbox
   - Auto-scale `\ifdim` block with footnote

## Open Questions

None — all key decisions resolved during brainstorming.
