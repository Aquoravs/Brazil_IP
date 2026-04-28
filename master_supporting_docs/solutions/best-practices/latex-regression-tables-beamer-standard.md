# LaTeX Regression Tables for Beamer: Project Standard

---
problem_type: best-practice
component: regression-tables, presentation
domain: econometrics, causal-inference
tags: [latex, beamer, regression-tables, modelsummary, fixest, kableExtra, presentation]
date_documented: 2026-03-01
status: production
key_files:
  - BNDES/politicsregs/_utils/beamer_tables.R
  - BNDES/politicsregs/5_estimation/51_first_stage.R
  - BNDES/politicsregs/5_estimation/52_second_stage.R
  - paper/first_stage.tex
---

## Problem

Standard regression table export methods (`fixest::etable` with `style.tex="aer"`) produce tables optimized for journal submissions but inadequate for Beamer slides:
- Excessive precision (4 decimal places)
- Dense formatting unsuitable for 16:9 slides
- No visual hierarchy for grouped columns
- FE checkmarks not customizable
- F-statistics buried in fit statistics
- Footnotes forced inside tabular, distorting column widths

## Solution: `save_beamer_table()` Pipeline

A reusable helper function in `_utils/beamer_tables.R` using `modelsummary` (>= 2.0) + `kableExtra` to produce presentation-quality LaTeX tables from `fixest` model lists.

### Pipeline Flow

```
fixest::feols() --> modelsummary(..., output="data.frame") -->
  kbl() + kable_styling() --> kableExtra helpers -->
  .strip_to_tabular() --> clean LaTeX --> Beamer \input{...}
```

### Function Signature

```r
save_beamer_table(
  mods,                    # named list of fixest models
  filename,                # output basename (writes .tex and .md)
  coef_map    = NULL,      # auto-detected from COEF_MAP_INSTRUMENTS if NULL
  fe_labels   = FE_LABELS, # named list: fixef_var = "Display label"
  add_f_stat  = TRUE,      # add Wald F-stat row
  dep_var     = NULL,      # e.g. "$\\Delta s_{mjt}$" -- spanning header
  notes       = NULL,      # if NULL, auto-generated from FE + clustering + stars
  font_size   = 8,         # kableExtra font_size for Beamer readability
  digits      = 3,         # coefficient decimal places
  table_dir   = TABLE_DIR,
  stars       = c("*" = 0.10, "**" = 0.05, "***" = 0.01),
  ...
)
```

### Key Formatting Choices

| Setting | Value | Rationale |
|---------|-------|-----------|
| Font size | `font_size = 8` | Readable on 16:9 Beamer slides with 6 columns |
| Decimal places | `digits = 3` | Cleaner than 4-decimal journal format |
| Stars | `* = 0.10, ** = 0.05, *** = 0.01` | Inline: `0.020**` |
| SE display | Below coefficient, parenthesized | SE row label blanked |
| GOF rows | Observations (comma-formatted) + $R^2$ (3 dec) | No AIC/BIC clutter |
| F-statistic | Bold if F >= 10 via `\textbf{}` | Visual emphasis for instrument strength |
| Table style | `booktabs = TRUE` | `\toprule`, `\midrule`, `\bottomrule` |
| Column alignment | `l` for labels, `c` for model columns | Clean centering |
| Spanning header | `\multicolumn{N}{c}{\textbf{Dep.~var: ...}}` | Via `add_header_above` |
| FE display | Checkmarks when varying; footnote when constant | Reduces clutter |
| Footnote position | Outside tabular in `\parbox{\wd0}` | Exact table-width match |
| File output | Dual: `.tex` (Beamer) + `.md` (console/git review) | |

### Preset Label Maps

**Coefficient labels** (`COEF_MAP_INSTRUMENTS`):
```r
"Z_mayor_coalition_cycle_specific"  = "$Z^{\\text{mayor}}_{\\text{coal.}}$"
"Z_gov_coalition_cycle_specific"    = "$Z^{\\text{gov}}_{\\text{coal.}}$"
"Z_pres_coalition_cycle_specific"   = "$Z^{\\text{pres}}_{\\text{coal.}}$"
# ... plus party, 2002-fixed, and levels variants
"exposure_control_cycle_specific"   = "Exposure control"
```

**FE labels** (`FE_LABELS`):
```r
"muni_id^cnae_section" = "Muni $\\times$ sector FE"
"muni_id^year"         = "Muni $\\times$ year FE"
"year"                 = "Year FE"
"cnae_section^year"    = "Sector $\\times$ year FE"
```

### The `\sbox0` Width-Measurement Trick

The `.strip_to_tabular()` post-processor strips kableExtra wrappers and repositions the footnote:

```latex
\sbox0{
\begin{tabular}[t]{lcccccc}
\toprule
...
\bottomrule
\end{tabular}
}\usebox0
\par\vspace{3pt}\parbox{\wd0}{\raggedright\scriptsize Note: Muni x sector + ...}
```

This typesets the tabular into box 0, then measures its width (`\wd0`) so the footnote `\parbox` is exactly as wide as the table -- preventing overflow on slides.

## Usage Pattern

### In Estimation Scripts

```r
source("_utils/utils.R")
source("_utils/beamer_tables.R")

TABLE_DIR <<- file.path(OUTPUT_DIR, "muni_reg_tables_grouped")

# Fit models
mods <- list(
  "Mayor"     = feols(delta_s ~ Z_mayor | muni_id^cnae_section + year, data = dt, vcov = ~muni_id + cnae_section),
  "Governor"  = feols(delta_s ~ Z_gov   | muni_id^cnae_section + year, data = dt, vcov = ~muni_id + cnae_section),
  "M+G"       = feols(delta_s ~ Z_mayor + Z_gov | muni_id^cnae_section + year, data = dt, vcov = ~muni_id + cnae_section)
)

# Save table
save_beamer_table(mods, "fs_t1_baseline",
  dep_var = "$\\Delta s_{mjt}$",
  notes = "Muni $\\times$ sector + sector $\\times$ year FE. Coalition, cycle-specific. SEs clustered by muni + sector. $^{***}p<0.01$, $^{**}p<0.05$, $^{*}p<0.10$."
)
```

### In Beamer Presentation

```latex
\documentclass[aspectratio=169,11pt]{beamer}
\usetheme{Madrid}
\usepackage{booktabs,amsmath,amssymb}
\newcommand{\tabledir}{../BNDES/output/muni_reg_tables_grouped}

\begin{frame}{First Stage: Baseline Specification}
\begin{center}
\footnotesize
\input{\tabledir/fs_t1_baseline.tex}
\end{center}
\end{frame}
```

### Second-Stage Wald Summary Tables

For compact optimality test summaries, `save_wald_summary()` builds a handwritten tabular:

```latex
\begin{tabular}{lrrrrr}
\toprule
Specification & $N$ & $R^2$ & IVs & Wald $F$ & $p$-value \\
\midrule
Mayor & 89,008 & 0.9455 & 18 & 1.47 & 0.0894 \\
M+G & 89,008 & 0.9456 & 36 & 2.18 & $< 10^{-4}$ \\
\bottomrule
\end{tabular}
```

## Checklist for New Tables

- [ ] Source `beamer_tables.R` at top of script
- [ ] Use `save_beamer_table()`, never raw `modelsummary(output="latex")`
- [ ] Pass `dep_var` in LaTeX format with escaped backslashes
- [ ] Include `notes` describing FE, clustering, and significance codes
- [ ] Set `font_size` appropriate for column count (8-9 pt typical, 7 for 20+ cols)
- [ ] Generate both `.tex` and `.md` outputs (automatic)
- [ ] Test LaTeX compilation in actual Beamer frame
- [ ] Verify F-stat bolding threshold (F >= 10)

## Common Pitfalls

| Problem | Cause | Fix |
|---------|-------|-----|
| Table overflows slide | Font too large or too many columns | Reduce `font_size` to 7-8; split across frames |
| Footnote distorts widths | kableExtra puts footnote inside tabular | `save_beamer_table()` auto-fixes via `.strip_to_tabular()` |
| LaTeX won't compile | Backslash escaping | Use `\\\\` in R strings; check `notes` parameter |
| F-stats missing | Instruments not matching `^Z_` or `^Zlev_` regex | Verify column names match pattern |
| Stars disappear | `escape=TRUE` overrides star formatting | Always use `escape = FALSE` |
| FE checkmarks wrong | FE variable name not in `FE_LABELS` map | Add new FE patterns to `beamer_tables.R` |

## Design Principles

1. **Single source of truth**: All label maps live in `beamer_tables.R`, not scattered across scripts
2. **One footnote per table**: Consolidates FE, clustering, stars -- no duplication in slide annotations
3. **Automatic metadata extraction**: FE, clustering, F-stats extracted programmatically from fixest models
4. **Dual output**: `.tex` for presentation, `.md` for console/git review
5. **No manual LaTeX editing**: Tables are fully generated from R; any change goes through the script

## Related Files

- `docs/plans/2026-03-01-refactor-presentation-regression-tables-plan.md` -- Original implementation plan
- `docs/plans/2026-02-28-refactor-first-stage-robustness-reorganization-plan.md` -- Script 51 reorganization
- `CLAUDE.md` -- Project conventions and variable naming
