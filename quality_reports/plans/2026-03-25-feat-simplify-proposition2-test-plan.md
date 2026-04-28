---
title: "feat: Simplify Proposition 2 Aggregation Equivalence Test"
type: feat
status: completed
date: 2026-03-25
origin: docs/prompts/2026-03-25-simplify-proposition2-test.md
---

# Simplify Proposition 2 Aggregation Equivalence Test

## Overview

The current Proposition 2 test (`script 52 --proposition2`) runs 16 spec combinations, all of which fail with deviations of 0.005–0.203. The presentation (`comparison_firm_agg.tex`) has 12 slides showing every combination. The goal is to simplify everything: build a synthetic verification proving the proposition works under correct conditions, diagnose exactly why real data violates those conditions, and tell the story in 4–5 slides.

## Problem Statement / Motivation

Proposition 2 (from `paper/review_aggregation.tex`) states that firm-level OLS and N_c-weighted cell OLS produce identical coefficients under four conditions: correct weighting, same sample, FE nesting, and linear model. All 16 empirical tests fail because two conditions are violated:

1. **Sample mismatch** (Condition 2): fixest singleton absorption drops ~900K observations (24.16M → 23.24M) differently across firm vs. aggregated FE structures.
2. **FE nesting violation** (Condition 3): firm FE (`firm_id`) links the same firm across years; cell FE (`muni_id^sector`) links the same cell. Firms appearing in multiple (muni, sector) cells over time break nesting.

The current 12-slide presentation is too complex to communicate this cleanly. We need: one case that works (synthetic), one that doesn't (real data), and a precise diagnosis.

## Proposed Solution

Four sequential tasks, each building on the previous.

### Phase 1: Synthetic Data Verification

**New file**: `BNDES/politicsregs/diagnostics/verify_proposition2_synthetic.R`

A standalone R script that:

1. **Generates synthetic data** with explicit DGP:
   - `set.seed(42)` for reproducibility
   - ~1,000 firms, ~50 municipalities, ~5 sectors, ~10 years
   - Each firm has exactly one fixed (muni, sector) assignment across all years (satisfies FE nesting)
   - Each cell has ≥ 3 firms (no degenerate cells — avoid collinearity with FE)
   - Known true coefficients: `lambda = c(mayor = 0.05, gov = 0.03, pres = -0.02)`
   - `FA_*` instruments: draw baseline party exposure `omega_fp ~ Uniform(0, 1)` per firm-party pair, draw binary alignment indicators `align_*` per muni-year, construct `FA_* = omega_fp * align_*`
   - Firm FE: `gamma_f ~ N(0, 0.2)`, muni×year FE: `alpha_mt ~ N(0, 0.1)`
   - LPM outcome: `Y_fmt = lambda' FA_fmt + gamma_f + alpha_mt + u_fmt`, `u ~ N(0, 0.3)`
   - (Outcome may exceed [0,1] — this is fine for LPM equivalence testing)
   - Single election cycle (regime dimension degenerate) — simplifies FE structure

2. **Tests Proposition 2 under correct conditions**:
   - Firm-level: `Y ~ FA_mayor + FA_gov + FA_pres | firm_id + muni_id^year` with `fixef.rm = "none"`
   - Collapse to (sector, muni, year) cells with simple averages; compute `N_c` (cell size)
   - Cell-level: `Y_bar ~ FA_bar_* | cell_id + muni_id^year` with N_c weights and `fixef.rm = "none"`
     - **Critical**: use `cell_id` (unique muni×sector identifier) as the aggregated FE, not `muni_id^sector_id + sector_id^year`. Since each firm maps to one cell, `cell_id` nests the averaged firm FE exactly.
   - Verify max |coef_firm - coef_agg| < 1e-8 → **PASS**

3. **Breaks each condition one at a time** (test matrix):

   | Test | What changes | Expected |
   |------|-------------|----------|
   | Baseline (correct) | All 4 conditions hold | max_dev < 1e-8 |
   | Break Cond 1 (weighting) | Drop N_c weights from cell regression | max_dev > 0 |
   | Break Cond 2 (sample) | In a dedicated perturbation, create singleton FE groups (for example, one-firm cells or one-observation firms in a small random subset), then remove `fixef.rm = "none"` so fixest drops them differently across firm vs. aggregated regressions | max_dev > 0 |
   | Break Cond 3a (FE structure) | Replace `cell_id + muni^year` with `muni^sector + sector^year` | max_dev > 0 |
   | Break Cond 3b (firm mobility) | Reassign ~20% of firms to 2+ cells, re-collapse | max_dev > 0 |

   Report: max absolute coefficient deviation, which coefficient deviates most, and pass/fail against 1e-8 tolerance.

4. **Output**: Console summary + CSV at `BNDES/output/diagnostics/prop2_synthetic_results.csv`

**Edge cases to handle**:
- Ensure no degenerate cells (each cell must have ≥ 3 firms)
- The Cond 3b violation test must re-collapse data after reassigning firms and recompute N_c
- The Cond 2 violation test must explicitly inject singleton FE groups; otherwise removing `fixef.rm = "none"` may leave the sample unchanged and fail to demonstrate the condition cleanly
- Verify fixest version supports `fixef.rm = "none"` (require fixest ≥ 0.11)
- Single random draw is sufficient (this is verification, not a simulation study)

### Phase 2: Real-Data Diagnostics

**New file**: `BNDES/politicsregs/diagnostics/diagnose_proposition2_gap.R`

A standalone diagnostic script that:

1. **Quantifies sample mismatch**:
   - Load `output/firm_panel_for_regs.qs2`
   - Reconstruct the **exact same Proposition 2 sample logic used in script 52** for the chosen reference specification: coalition alignment, pooled-count exposure, unweighted, relaxed FE
   - This means: apply the same `F_pre` support filter and the same non-missing-variable filter used before estimation in script 52, then collapse from that exact firm sample
   - Run firm regression with `fixef.rm = "none"` vs. default (singleton-absorbing)
   - Report both sides of the mismatch: firm-level N_obs with vs. without singleton absorption, aggregated-cell N_obs with vs. without singleton absorption, and the implied rows/cells dropped on each side

2. **Quantifies FE nesting violation**:
   - "Multi-cell firm" = a firm appearing in more than one (muni_id, sector_group) pair across any years in the panel
   - Count: N single-cell firms, N multi-cell firms, % of firm-year observations from multi-cell firms
   - Also report: how many firms cross cells within a single election cycle (the tighter violation)

3. **Tests whether fixing the sample alone closes the gap**:
   - Force `fixef.rm = "none"` in both firm and aggregated regressions
   - Compare coefficients — does the gap shrink?

4. **Tests single-cell firm restriction**:
   - Filter to firms with exactly one (muni_id, sector_group) across all years
   - Re-run both regressions on this restricted sample
   - Report coefficient gap — should be much smaller

5. **Output**: Console summary + CSV at `BNDES/output/diagnostics/prop2_real_data_diagnostics.csv`

**Technical considerations**:
- The firm panel is large (~24M rows). Use `lean = TRUE, mem.clean = TRUE` for memory efficiency.
- Use one spec only: coalition alignment, pooled-count exposure, unweighted, relaxed FE.
- Clustering affects only SEs, not point estimates — compare coefficients only.
- The `fixef.rm = "none"` run may be slower (more observations). Use `nthreads = data.table::getDTthreads()`.
- The diagnostic script should call or replicate script 52 helper logic exactly for sample construction (`F_pre` support, term selection, non-missing filters) so its counts match the baseline Proposition 2 table one-to-one.
- This is a **new standalone script**, separate from both `diagnose_agg_first_stage_collapse.R` (which diagnoses why aggregated F-stats collapse) and script 52's `--proposition2` mode (which runs the full 16-spec battery). This script focuses narrowly on diagnosing the two specific condition violations.

### Phase 3: Simplify Presentation

**Rewrite**: `paper/comparison_firm_agg.tex`

Reduce from 12 frames to 5 frames:

| Frame | Title | Content |
|-------|-------|---------|
| 1 | Title | "Proposition 2: Aggregation Equivalence Test" |
| 2 | What Proposition 2 Says | State four conditions cleanly, one itemize list |
| 3 | Baseline Equivalence Table | Use a **new minimal table** for the reference spec only: firm unweighted vs. aggregated `N_c`-weighted, plus optionally aggregated simple-average if space helps the story. Do **not** reuse the existing 6-column `prop2_equiv_relaxed_coalition_pooled_count.tex` table directly. |
| 4 | Why Equivalence Fails | Two bullet points: (a) sample mismatch from singleton absorption with concrete N numbers, (b) FE nesting violation with count of multi-cell firms. Include real-data diagnostic numbers. |
| 5 | Verification & Takeaway | "Under correct conditions (synthetic data), max deviation = X." "With real data, the gap is driven by [quantified sources]." Proposition is mathematically correct; our data violates its conditions. |

**Template**: Match `presentation_progress_2026_03_25.tex` exactly:
- `\documentclass[aspectratio=169,11pt]{beamer}`, Madrid theme, darkblue colors
- `\OptionalInputTable` for table includes
- `\aggdir` pointing to `../BNDES/output/agg_firm_reg_tables_grouped`
- Add `\diagdir` pointing to `../BNDES/output/diagnostics`
- Generate the slide-3 table as a dedicated small LaTeX artifact (for example via `save_beamer_table()` from a 2- or 3-column model list) so the frame stays visually simple

### Phase 4: Update Presentation with Findings

After Phases 1–2 produce outputs, update Phase 3 slides with actual numbers:

- Slide 4: Fill in concrete singleton absorption count, multi-cell firm count
- Slide 5: Fill in synthetic max deviation (should be < 1e-8), real-data gap magnitude
- Optionally add a small synthetic results summary table if it fits on slide 5

## Acceptance Criteria

- [x] Synthetic test shows PASS (< 1e-8 deviation) when all four conditions hold
- [x] Synthetic test shows FAIL when each condition is individually violated, with reported deviations
- [x] Real-data diagnostic quantifies: (a) singleton absorption sample difference on both firm and aggregated sides using the exact script 52 sample logic, (b) multi-cell firm count/share, (c) gap with `fixef.rm = "none"`, (d) gap with single-cell restriction
- [x] `comparison_firm_agg.tex` has 6 frames (including title; added synthetic table frame)
- [x] Presentation compiles and tells a clear story: "Proposition 2 is correct; here's exactly why our data violates its conditions"
- [x] All tables use `save_beamer_table()` or `\input` dedicated minimal artifacts; slide 3 does not reuse the existing 6-column Proposition 2 table unchanged

## Technical Considerations

- **fixest `fixef.rm = "none"`**: Prevents singleton absorption. Critical for sample identity. Available since fixest ≥ 0.11.
- **Memory**: Real-data diagnostics on the 24M-row firm panel need `lean = TRUE, mem.clean = TRUE`. Synthetic script doesn't need this.
- **FE nesting math**: For Prop 2 to hold, each firm must map to exactly one cell. In synthetic data, enforce this by construction. In real data, measure the violation.
- **Synthetic sample-break design**: the baseline DGP intentionally avoids degenerate cells, so the Condition 2 failure case must add singleton FE groups explicitly before turning singleton removal back on.
- **Coefficient comparison only**: Clustering/SEs differ between firm and aggregated levels — only compare point estimates.
- **Presentation table scope**: The existing `prop2_equiv_relaxed_coalition_pooled_count.tex` table is too wide for the simplified story. Create a smaller dedicated table for the slide instead of reusing the full 6-column artifact.

## Dependencies & Risks

- **Dependency**: Phase 2 requires `output/firm_panel_for_regs.qs2` (built by script 42). Must be pre-built.
- **Dependency**: Phase 3 reuses existing `prop2_equiv_relaxed_*.tex` tables from script 52 `--proposition2` mode. Must be pre-built.
- **Risk**: `fixef.rm = "none"` may produce slightly different results than expected if fixest version differs. Pin version expectation.
- **Risk**: Multi-cell firm restriction may leave too few observations for stable estimation. Report N_obs alongside gap.

## Implementation Order

1. **Phase 1** (synthetic verification) — standalone, no dependencies on real data
2. **Phase 2** (real-data diagnostics) — requires firm panel
3. **Phase 3** (simplify presentation) — can start in parallel with Phases 1–2 using placeholder numbers
4. **Phase 4** (update with findings) — requires Phases 1–2 outputs

Phases 1 and 2 can run in parallel. Phase 3 can start concurrently with placeholder values, then Phase 4 fills them in.

## Key Files

| File | Role |
|------|------|
| `paper/review_aggregation.tex` | Proposition 2 theory |
| `BNDES/politicsregs/5_estimation/52_aggregated_firm_sector_first_stage.R` | Current `--proposition2` implementation |
| `BNDES/output/agg_firm_reg_tables_grouped/prop2_equality_check.csv` | Current results (all 16 fail) |
| `BNDES/output/agg_firm_reg_tables_grouped/prop2_equiv_relaxed_coalition_pooled_count.tex` | Baseline table to include |
| `paper/comparison_firm_agg.tex` | Presentation to simplify (12 → 5 slides) |
| `paper/presentation_progress_2026_03_25.tex` | Beamer template reference |
| `BNDES/politicsregs/_utils/beamer_tables.R` | `save_beamer_table()` utility |
| `BNDES/output/firm_panel_for_regs.qs2` | Real firm panel for diagnostics |
| **NEW**: `BNDES/politicsregs/diagnostics/verify_proposition2_synthetic.R` | Synthetic verification |
| **NEW**: `BNDES/politicsregs/diagnostics/diagnose_proposition2_gap.R` | Real-data diagnostics |

## Sources

- **Prompt**: `docs/prompts/2026-03-25-simplify-proposition2-test.md`
- **Prior plan**: `docs/plans/2026-03-25-feat-proposition2-aggregation-equivalence-test-plan.md` (original script 52 implementation)
- **Theory**: `paper/review_aggregation.tex` (Proposition 2 and proof)
- **Table standard**: `docs/solutions/best-practices/latex-regression-tables-beamer-standard.md`
