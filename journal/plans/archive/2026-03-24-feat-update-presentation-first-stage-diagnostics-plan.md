---
title: "Update Presentation: First-Stage Pipeline + Diagnostics + Forward Path"
type: feat
status: completed
date: 2026-03-24
---

# Update Presentation: First-Stage Pipeline + Diagnostics + Forward Path

## Overview

Rewrite `paper/presentation_progress_2026_03_23.tex` into a new `presentation_progress_2026_03_24.tex` that tells the full story:

1. **Specification overview** (self-contained, accessible to an outside reader)
2. **Firm-level first stage** (script 51 results)
3. **Aggregated firm → sector first stage** (script 52 results)
4. **Diagnostic evidence on why aggregation collapses** (from `agg_sector_collapse/` and `sector_group_cell_support/`)
5. **Sector-level shift-share first stage** (script 53 results, updated)
6. **Forward path**: coarser sector groupings, firm-level reallocation summary, alternative identification

The overarching narrative is: *political alignment robustly predicts firm-level BNDES access, but the signal does not survive aggregation to (sector, muni, year) cells because cells are too sparse and outcomes too homogeneous across sectors within most muni-years. This motivates either coarser sector definitions aligned with BNDES lending patterns, or a firm-level reallocation summary that bypasses sector aggregation entirely.*

## Proposed Slide Deck Structure

### Part I: Setup & Specification (3-4 slides)

#### Slide 1: Title Page
- Title: "Testing Industrial Policymakers: Evidence from Brazil's BNDES"
- Subtitle: "First-Stage Pipeline & Aggregation Diagnostics"
- Date: March 24, 2026

#### Slide 2: Research Design Overview
- One-paragraph summary of the research question (is sector-level BNDES allocation GDP-optimal?)
- Three-step identification strategy depicted visually or in a numbered list:
  1. **Firm first stage**: political alignment → firm BNDES access (micro validation)
  2. **Sector aggregation**: firm instruments → sector-level reallocation
  3. **Municipality second stage**: predicted reallocation → GDP per capita
- Clarify that this presentation focuses on steps 1 and 2

#### Slide 3: Firm-Level Specification (Detailed)
Self-contained description for someone unfamiliar with the project:

- **Unit of observation**: firm $f$ × municipality $m$ × year $t$
- **Dependent variable**: $\mathbf{1}(\text{BNDES}_{fmt} > 0)$ — extensive margin indicator (LPM)
- **Instruments** $FA^{\ell}_{fmt}$: firm baseline party-exposure share $\omega_{fp,0}$ interacted with alignment level $\text{Align}^{\ell}_{mpt}$, summed over parties $p$. Explain:
  - $\omega_{fp,0}$: share of firm $f$'s owners affiliated with party $p$, averaged over the 4-year pre-election window
  - $\text{Align}^{\ell}_{mpt}$: indicator for party $p$ being in the governing coalition at tier $\ell$ (mayor/governor/president) in municipality $m$ at year $t$
  - $FA^{\ell}_{fmt} = \sum_p \omega_{fp,0} \cdot \text{Align}^{\ell}_{mpt}$: fraction of firm's owners aligned with the incumbent at tier $\ell$
- **Fixed effects**: firm + municipality × year
- **Clustering**: two-way by firm and municipality
- **Sample**: 39.5M firm-muni-year observations (full RAIS-BNDES merged panel, 2002-2017)
- **Weights**: employment-weighted (number of employees as analytic regression weights)

#### Slide 4: Aggregated Specification (Detailed)
- **Collapse to** (sector group $j$, municipality $m$, year $t$) cells
- **Dependent variable**: $H^{\text{pre}}_{jmt}$ = share of pre-election firms with any BNDES
- **Instruments**: $\overline{FA}^{\ell}_{jmt}$ = simple average of firm-level $FA^{\ell}$ within the cell
- **Fixed effects**: muni × sector + muni × year
- **Clustering**: two-way by municipality and sector group
- **Pre-election base**: firms with any non-zero $FA$ instrument
- Emphasize: this is the *same* political signal, averaged within cells

### Part II: Firm-Level Results (2-3 slides)

#### Slide 5: Firm First-Stage — Main Baseline
- Include table: `\firmdir/firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count.tex`
- Bullet summary: Mayor = 0.010* (F = 3.4), Governor = 0.013*** (F = 6.9), President = −0.013** (F = 5.6); joint M+G+P F = 4.8
- Note: employment-weighted, pooled-count baselines, cycle-specific

#### Slide 6: Firm First-Stage — Variant Summary
- Handcrafted summary table (as in current presentation):
  - Pooled-count baseline (main)
  - Binary exposure variant
  - Interaction bundle variant
- Takeaway: firm-level signal is present; governor coalition is the strongest single-tier instrument

#### Slide 7 (optional): Party Alignment Variant
- Include table: `firm__main__levels__extensive__party__cycle_specific__unweighted__all_firms__pooled_count.tex`
- Or summarize in the variant table above

### Part III: Aggregated First Stage (2-3 slides)

#### Slide 8: Aggregated Results — Coalition
- Include table: `\aggdir/agg_t1_coalition_levels.tex` (fix path macro — currently `\firmdirg` points to nonexistent `firm_reg_tables_grouped/`; should be `agg_firm_reg_tables_grouped/`)
- Key finding: no coefficient reaches significance; best F = 2.3 (president single tier)

#### Slide 9: Aggregated Results — Party
- Include table: `\aggdir/agg_t2_party_levels.tex`
- Key finding: all F < 2.3

#### Slide 10: Firm vs. Aggregated Comparison
- Side-by-side table (already in current presentation, lines 253-283)
- Emphasize: 70% coefficient attenuation, 80-90% F-stat drop, president sign flip
- Transition question: **Why does the signal disappear?**

### Part IV: Diagnostic Evidence (4-5 slides — the core new content)

#### Slide 11: Diagnostic #1 — Cell Sparsity (Dominant Driver)

Evidence from `agg_sector_collapse/conditional_f_by_npre.csv` and `sector_group_cell_support/1_cell_size_distribution_overall.csv`:

**Key facts to present:**
- 37% of cells have 1 firm, 16% have 2 (from `cell_size_distribution_overall.csv` — note: these are the *agg_collapse* diagnostic numbers using pre-election firms, which differ from the 29.1% 1-2 firm share in the `sector_group_cell_support` analysis that uses *all* RAIS firms)
- F-statistic monotonically increases with minimum cell size:

| Min firms per cell | N cells | Coalition F |
|---|---|---|
| All | 293K | 1.02 |
| ≥ 5 | 74K | 0.97 |
| ≥ 10 | 35K | 1.38 |
| ≥ 20 | 15.5K | 2.96 |
| ≥ 50 | 4.6K | **6.89** |

- At N ≥ 50, the instrument approaches strength — but only 1.6% of cells survive
- Precision-weighting by N_pre does NOT help (F drops to 0.15) — large cells have different instrument distributions

**Conclusion**: The firm-level signal *is there* in dense cells; the problem is that most cells are too thin for aggregation to preserve it.

#### Slide 12: Diagnostic #2 — Outcome Homogeneity Within Muni-Years

Evidence from `within_muni_year_h_comovement_summary.csv`:

- Median within-muni-year SD of $H^{\text{pre}}_{jmt}$ across sectors = **0** (median range also 0)
- In most muni-years, *all sectors have the same BNDES extensive-margin outcome*
- This means there is **no cross-sector variation to explain** for the majority of observations

From `sector_group_cell_support_note.md`:
- 42.3% of muni-years have zero positive sector-group cells
- 20.4% have exactly one positive sector-group cell
- Together: **62.7% of muni-years have ≤ 1 sector with positive BNDES** — cross-sector reallocation cannot be identified here

#### Slide 13: Diagnostic #3 — Limited Instrument Variation Across Sectors

Evidence from `within_muni_year_instrument_variance_summary.csv`:

- Median within-muni-year SD of $\overline{FA}^{\text{mayor}}_{\text{coalition}}$ across sectors = 0.22
- For party instruments: median SD = 0.06 — near zero cross-sector spread
- FE absorption R² = 0.71–0.76: muni×sector + muni×year FE soak up ~73% of instrument variation
- But alternative FE don't help: sector+year gives F = 1.56; muni×sector only gives F = 0.98
- **Problem is structural, not just FE-driven**

#### Slide 14: Diagnostic #4 — Sector Heterogeneity

Evidence from `sector_specific_regressions.csv` and `leave_one_sector_out_regressions.csv`:

| Sector | Sector-Specific F | Leave-One-Out F |
|---|---|---|
| Tp (Transport) | **20.4** | 0.37 (dropping it kills signal) |
| XX (Residual) | **47.6** | 0.97 (dropping it kills signal) |
| CA (Adv. Manuf.) | 3.2 | **5.2** (dropping it *raises* pooled F) |
| UCo (Utilities) | 2.7 | 1.2 |
| All others | < 2.2 | ~1.0 |

- Only Transport and Residual carry signal; everything else contributes noise
- CA actively dilutes the pooled signal (its inclusion drops F from 5.2 to 1.02)

#### Slide 15: Diagnostic Summary
- Ranked hypotheses table with evidence scores (from `ranked_evidence_summary.csv`):
  1. **Cell sparsity**: score 5.87 — dominant driver
  2. **FE absorption / limited within-muni-year variation**: score 0.74 — substantial but secondary
  3. **Diffuse exposure / cancellation**: score 0.41 — moderate
  4. **Aggregation form mismatch**: score −0.18 — ruled out
- Visual or table summarizing the three binding constraints: thin cells, homogeneous outcomes, concentrated signal in 2 sectors

### Part V: Sector Shift-Share First Stage (1-2 slides)

#### Slide 16: Sector First-Stage Results (Script 53)
- Include 1-2 canonical tables from `\sectordirmain/sector__levels__owner_count__coalition__cycle_specific__mxj_jxt__ctrl.tex` (or the best-performing spec)
- Show that the sector-level shift-share instruments also fail: all F < 2.5 across weight variants, alignment types, and FE choices
- This is *consistent* with the aggregation diagnostics — the same structural problems (thin cells, outcome homogeneity) affect the sector pipeline

#### Slide 17 (optional): Sector Spec Battery Summary
- Summary table across key dimensions (alignment × FE × weight variant)
- Highlight that no specification reaches F = 10

### Part VI: Forward Path (2-3 slides)

#### Slide 18: Why Current Sector Grouping Fails
- Current 10 sector groups still produce cells that are too thin (median 6 firms per cell in overall RAIS; median 2 pre-election firms)
- BNDES lending is *highly concentrated*: median HHI of sector BNDES shares = 0.67; top group gets 79.9% of value
- 32.1% of cells have zero affiliated firms — no instrument variation possible
- Affiliation support is concentrated in Tp (38.4%) and sparse in Ag (4.8%)

#### Slide 19: Alternative Paths Forward
Three possibilities, not mutually exclusive:

**Option A: Coarser sector groupings aligned with BNDES lending**
- Current grouping (10 groups from 21 CNAE sections) was designed for broad economic categories, not BNDES lending patterns
- Could define 3-5 "BNDES-relevant" sectors based on where lending actually occurs and where affiliation support exists
- Pros: fewer, denser cells; outcome variation more likely
- Cons: loses sector-level heterogeneity; may conflate different economic channels
- Evidence: Transport and Residual sectors carry all the signal — perhaps a Manufacturing / Services / Transport+Other trichotomy

**Option B: Firm-level reallocation summary variable**
- Instead of sector shares, construct a firm-level reallocation measure within municipality:
  - e.g., turnover in BNDES access across firms between $t-1$ and $t$, aggregated to municipality level
  - Or a Herfindahl-style concentration index of firm-level BNDES within municipality
- Instrument directly with municipality-level alignment (no sector dimension needed)
- Pros: bypasses the entire sector-aggregation problem; uses the strong firm-level signal directly
- Cons: new outcome variable requires theoretical motivation; less directly interpretable for sector-level misallocation story

**Option C: Return to ungrouped sectors (21 CNAE sections)**
- The `first_stage_review.md` notes that ungrouped sectors with muni × year FE achieve F = 12.4 for mayor — above Stock-Yogo 10
- More sections → more variation in shares and instruments
- But also more singleton cells and thinner support
- Worth running the full diagnostic on ungrouped to compare

#### Slide 20: Conclusion & Next Steps
- Firm-level validation is solid: alignment → BNDES access is real
- The challenge is aggregation, not the underlying political mechanism
- Recommended next steps:
  1. Test coarser BNDES-aligned sector groupings
  2. Prototype a firm-level reallocation summary variable
  3. Run ungrouped sector first stage with muni × year FE and compare
  4. Consider the evidence when choosing the path to the second stage

### Appendix (keep existing + add)

- **Appendix A**: Aggregation mechanics (existing)
- **Appendix B**: Sector group definitions (existing)
- **Appendix C**: Full diagnostic tables (cell size distributions, FE absorption, sector-specific F)
- **Appendix D**: Additional firm first-stage variants (party, binary, interaction, intensive margin)
- **Appendix E**: Sector first-stage spec battery (full grid)

## Technical Implementation Notes

### Fix the `\firmdirg` Macro

The current presentation defines `\firmdirg` as `../BNDES/output/firm_reg_tables_grouped` which does not exist. The aggregated firm tables are in `agg_firm_reg_tables_grouped/`. Define a new macro:

```latex
\newcommand{\aggdir}{../BNDES/output/agg_firm_reg_tables_grouped}
```

And update all references to aggregated tables to use `\aggdir`.

### New Macros Needed

```latex
\newcommand{\aggdir}{../BNDES/output/agg_firm_reg_tables_grouped}
\newcommand{\diagdir}{../BNDES/output/diagnostics}
```

### Tables to Include via `\OptionalInputTable`

| Slide | File | Source |
|---|---|---|
| Firm baseline | `\firmdir/firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count.tex` | Script 51 |
| AGG coalition | `\aggdir/agg_t1_coalition_levels.tex` | Script 52 |
| AGG party | `\aggdir/agg_t2_party_levels.tex` | Script 52 |
| Sector baseline | `\sectordirmain/sector__levels__owner_count__coalition__cycle_specific__mxj_jxt__ctrl.tex` | Script 53 |

### Handcrafted Tables

The following tables should be handcrafted in LaTeX (not from `\input`):
- Slide 6: Firm variant summary (keep existing)
- Slide 10: Firm vs. aggregated comparison (keep existing)
- Slide 11: F-stat by minimum cell size (from `conditional_f_by_npre.csv`)
- Slide 14: Sector-specific F-stats (from `sector_specific_regressions.csv`)
- Slide 15: Ranked hypotheses (from `ranked_evidence_summary.csv`)
- Slide 18: Cell support summary (from `sector_group_cell_support_note.md`)

### Diagnostic Plots to Include

From `sector_group_cell_support/`:
- `plot_cell_size_by_sector_group.pdf` — shows sparsity varies by sector
- `plot_positive_bndes_share_heatmap.pdf` — shows BNDES concentration across sectors × years
- `plot_affiliation_share_heatmap.pdf` — shows where political-affiliation support exists

These can be included in the appendix or inline if they fit.

## Acceptance Criteria

- [x] New file `paper/presentation_progress_2026_03_24.tex` created (do not overwrite 03_23 version)
- [x] Slides 2-4 contain self-contained specification descriptions (someone unfamiliar can follow)
- [x] Firm first-stage results included via `\OptionalInputTable` pointing to correct script 51 outputs
- [x] Aggregated results included with corrected `\aggdir` macro
- [x] At least 3 diagnostic slides with quantitative evidence from the CSV files
- [x] Sector first-stage (script 53) results included with at least one canonical table
- [x] Forward-path slide discusses coarser sectors, firm-level reallocation, and ungrouped alternative
- [x] `\firmdirg` bug fixed (or replaced with `\aggdir`)
- [x] Compiles without errors (modulo missing table files, which use `\OptionalInputTable` placeholders)
- [x] Existing appendix content preserved and augmented

## Sources

- Diagnostic data: `BNDES/output/diagnostics/agg_sector_collapse/` (26 files, 2026-03-23)
- Diagnostic data: `BNDES/output/diagnostics/sector_group_cell_support/` (24 files, 2026-03-24)
- Current presentation: `paper/presentation_progress_2026_03_23.tex`
- First-stage review: `docs/first_stage_review.md`
- Table standard: `docs/solutions/best-practices/latex-regression-tables-beamer-standard.md`
- Helper function: `BNDES/politicsregs/_utils/beamer_tables.R`
