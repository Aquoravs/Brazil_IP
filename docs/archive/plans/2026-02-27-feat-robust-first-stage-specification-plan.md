---
title: "Robust First-Stage Specification: Sector Regrouping, FE Variants, Controls, Levels, and Firm-Level Replication"
type: feat
status: active
date: 2026-02-27
---

# Robust First-Stage Specification

## Overview

Referees/advisors have raised four concrete concerns about the first-stage credibility. This plan addresses them systematically:

1. **Sector regrouping**: Break up Manufacturing (C, 24 CNAE divisions) into meaningful subsectors while collapsing sparse sectors, targeting <=10 total groups.
2. **Sector-by-year FE**: Add `cnae_section^year` (or the regrouped equivalent) as an additional FE specification.
3. **Baseline exposure control**: Include the sum across parties of baseline exposure weights as a muni-year level control.
4. **Levels specification**: Run the first stage in levels (s_mjt on Sum_p{w_mjp}*Align in levels) in addition to the current changes specification (delta_s_mjt on Z_mjt).
5. **Firm-level first stage**: Replicate the first-stage regression at the firm level to verify micro-level patterns are consistent.

## Problem Statement / Motivation

The current first stage operates with 21 CNAE sections (A-U). Manufacturing (section C) alone spans 24 2-digit divisions (10-33), which represent very heterogeneous industries (food processing, chemicals, autos, electronics). Lumping them together masks important heterogeneity in political exposure. Conversely, several sections (T, U, D, L, O) have very sparse BNDES coverage (< 1% of cells positive) and create leverage/noise problems (T and U already had to be dropped from the second stage).

Referees also want to see that results are robust to: (a) sector-by-year FE (absorbing sector-level trends), (b) controlling for the "total exposure" of each muni-sector cell (addressing concerns that high-exposure cells differ systematically), (c) a levels specification (complements the changes specification), and (d) firm-level evidence (verifying the muni-sector-level patterns reflect actual firm-level credit allocation, not just compositional artifacts).

## Proposed Solution

### Phase 1: Sector Regrouping (new script `36_build_sector_groups.R`)

Create a mapping from the 21 CNAE sections to ~8-10 groups. The regrouping follows economic logic and data density:

**Final grouping (9 effective groups + 1 dropped residual):**

| Group | Code | Label | CNAE sections | Approx. share |
|-------|------|-------|---------------|---------------|
| 1 | AM | Agriculture & Mining | A, B | ~5.9% |
| 2 | CL | Light Manufacturing | C div 10-18 | part of 16% |
| 3 | CH | Heavy Manufacturing | C div 19-25 | part of 16% |
| 4 | CA | Advanced Manufacturing | C div 26-33 | part of 16% |
| 5 | UCo | Utilities & Construction | D, E, F | ~3.3% |
| 6 | Tr | Trade | G | ~18.2% (j0) |
| 7 | Tp | Transport | H | ~12.3% |
| 8 | MS | Market Services | I, J, K, L, M, N | ~5.3% |
| 9 | PSO | Public, Social & Other | O, P, Q, R, S | ~1.2% |
| (drop) | XX | Residual | T, U | <0.1% |

**Key design decision**: Manufacturing (C) splits into 3 sub-groups based on CNAE division (2-digit code), which is already computed in script 22 as an intermediate step but then dropped. We need to preserve `cnae_division` in the reconstructed panel or re-derive it.

**Implementation**:
- The script reads the reconstructed panel (fst) to extract `classe` and derive `cnae_division`, then maps each `(cnae_section, cnae_division)` pair to a `sector_group` code.
- Outputs a crosswalk table `output/sector_group_mapping.qs2` with columns: `cnae_section`, `cnae_division`, `sector_group`, `sector_group_label`.
- Also outputs a summary of BNDES coverage and RAIS firm counts by group.

**Alternative groupings to explore (robustness)**:
- 8 groups (merge Public & Social into Other Services)
- Manufacturing split at division 20 (two-way instead of three-way)
- Data-driven: group sectors by similar mean BNDES share (quantile-based)

### Phase 2: Propagate Sector Groups Through Pipeline

**Script 35 (`build_credit_shares.R`) modifications:**
- Accept a `--sector-var` flag (default: `cnae_section`, alternative: `sector_group`)
- When `sector_group` is selected, aggregate BNDES credit and compute shares at the `(muni_id, sector_group, year)` level instead of `cnae_section`
- Output: `output/bndes_credit_shares_grouped.qs2`

**Script 31 (`build_sector_exposure_weights.R`) modifications:**
- Same `--sector-var` flag
- Aggregate `L_rjp` and denominators at `sector_group` level
- Output: `output/sector_exposure_weights_owner_grouped.qs2`

**Scripts 33-34 (`select_baseline_weights`, `build_shift_share_instruments`):**
- Propagate `sector_group` through baseline weight selection and instrument construction
- Output grouped versions of instruments

**Script 41 (`build_muni_panel.R`):**
- Build Panel A at `(muni_id, sector_group, year)` level
- Panel B wide-format columns use `sector_group` codes instead of letters
- Save as separate output files (do not overwrite originals)

### Phase 3: First-Stage Enhancements (modify script `51_first_stage.R`)

#### 3a. Sector-by-Year FE

Add a third FE specification:

```r
FE_SECTOR_YEAR <- "muni_id^cnae_section + cnae_section^year"
```

This absorbs sector-specific trends (e.g., manufacturing's secular decline relative to services). Identification then comes from cross-municipality variation in political exposure within each sector-year cell.

**Note**: Cannot combine `muni_id^year` and `cnae_section^year` simultaneously with `muni_id^cnae_section` — that would absorb nearly all variation. The `cnae_section^year` FE replaces `muni_id^year`, relaxing the demand on cross-sector within-muni variation but controlling for sector trends.

**New FE grid for first stage:**

| Spec | FE | Identification source |
|------|----|-----------------------|
| Primary | muni x sector + muni x year | Cross-sector within muni-year |
| Robustness 1 | muni x sector + year | Cross-sector + cross-muni within year |
| Robustness 2 | muni x sector + sector x year | Cross-muni within sector-year |

#### 3b. Baseline Exposure Control

The sum of baseline exposure weights across parties measures "total political connectedness" of a muni-sector cell:

```r
# In script 41 or 51, compute:
# exposure_control_mjt = sum_p (L_rjp_0 / D_r_0) for muni r, sector j
```

This is the sum of the "share" variables across all parties for each muni-sector. Include as a control:

```r
delta_s_mjt ~ Z_mjt + exposure_control_mj + alpha_mj + alpha_mt + epsilon
```

This absorbs the mechanical correlation between instrument magnitude and cell connectedness. The instrument should predict *changes* in credit shares conditional on the level of total political connection.

**Implementation**: Compute `exposure_control_mj` in script 34 or 41 by summing `L_rjp_0 / D_r_0` across parties (p) for each `(muni_id, cnae_section, baseline_type)`. Since the baseline weights are pre-determined, this is not a "bad control."

For time-varying versions (cycle-specific baselines), the control varies by electoral cycle:
- `exposure_control_mj_cycle` = sum_p w_{mjp,cycle} (varies by treatment_year)
- `exposure_control_mj_2002` = sum_p w_{mjp,2002} (constant across cycles)

#### 3c. Levels Specification

Currently the first stage is in changes: `delta_s_mjt ~ Z_mjt + FE`.

The levels version regresses the share *level* on the instrument in levels:

```r
s_mjt ~ Z_levels_mjt + alpha_mj + alpha_t + epsilon_mjt
```

Where `Z_levels_mjt = sum_p w_{mjp,0} * Align_{mtp}` (alignment in **levels**, not changes).

**Implementation**:
- In script 34, compute a levels version of the instrument using alignment levels (already available in `in_power_upd_2002_2019.qs2` — the raw alignment indicator, not the delta).
- The levels instrument is: `Z_levels_mjt = sum_p (L_rjp_0 / D_r_0) * Align_mtp` where `Align_mtp = 1` if party p is aligned with tier l in muni m at time t.
- Save alongside the existing delta instruments.
- In script 51, add a levels specification block that regresses `s_mjt` on `Z_levels_mjt`.

**FE for levels**: Use `muni_id^cnae_section + year` (not muni x year, since alignment levels are absorbed by muni x year FE — unlike changes, the level of alignment doesn't vary within muni-year across sectors, so the sector-specific instrument *would* still vary through the exposure weights, but the level of the aggregate alignment is absorbed).

Actually, **the levels instrument does vary across sectors** (through w_{mjp}), so `muni_id^year` FE is still valid and preferred — it absorbs the aggregate alignment level. This parallels the changes specification.

### Phase 4: Firm-Level First Stage (new script `53_first_stage_firm.R`)

Replicate the first stage at the firm level:

```
bndes_fit ~ Z_firm_mjt + alpha_firm + alpha_mt + epsilon_fit
```

Where:
- `bndes_fit` = BNDES credit received by firm f in muni m, sector j, year t (or indicator for receiving any credit, or log(1+credit))
- `Z_firm_mjt` = the same sector-level shift-share instrument (does not vary across firms within a muni-sector-year cell)
- `alpha_firm` = firm FE
- `alpha_mt` = muni x year FE

**Data**: Use the reconstructed firm-level panel (`rais_bndes_reconstructed.fst`), which has `(firm_id, muni_id, year, cnae_section, value_dis_real_2018_total, in_bndes)`.

**Outcomes to test**:
1. `in_bndes_fit` (extensive margin: 0/1 indicator)
2. `log(1 + bndes_fit)` (intensive + extensive margin)
3. `bndes_fit / total_bndes_mt` (firm's share of muni-year BNDES — maps to the sector share)

**Clustering**: Two-way by `muni_id` and `cnae_section` (same as Panel A).

**Purpose**: Show that the sector-level reallocation reflects actual firm-level credit decisions, not just compositional changes in which firms exist. The firm FE absorbs permanent firm characteristics; the muni x year FE absorbs aggregate shocks. If the coefficient on Z_mjt is positive and significant, it confirms that firms in politically-connected sectors receive more credit when their sector's party gains alignment.

## Technical Considerations

### Architecture impacts
- New script 36 (sector groups) slots between scripts 35 and 41 in the pipeline
- Script 51 grows with additional FE specifications and levels regressions
- New script 53 for firm-level regressions
- All changes are additive (original outputs preserved); grouped versions saved with `_grouped` suffix

### Performance implications
- Firm-level regressions (script 53) will be large: the reconstructed panel has ~15-20M rows. `fixest` with firm FE + muni x year FE should handle this but may require `lean = TRUE` and single-threaded execution.
- Sector regrouping reduces panel dimensions (from ~21 to ~10 sectors per muni), which will speed up estimation.

### Simplex constraint with regrouping
- With 10 groups, we drop one reference group (largest share, likely group 6: Trade & Transport if it subsumes G).
- Shares still sum to 1 within muni-year by construction (since regrouping just aggregates).

### Interaction with second stage
- The sector regrouping will also affect the second stage (vector 2SLS with fewer endogenous regressors = more degrees of freedom, possibly better identified).
- The levels specification provides a complementary estimating equation that could serve as an additional overidentification test.

## Acceptance Criteria

### Functional Requirements
- [x] New `36_build_sector_groups.R` script creates a crosswalk and validates coverage
- [x] Scripts 31, 33-35, 41 accept `--sector-var=sector_group` flag and produce grouped outputs
- [x] Script 51 runs 3 FE specifications (primary, year-only, sector x year) for both changes and levels
- [x] Script 51 includes baseline exposure control as an additional specification
- [ ] New `53_first_stage_firm.R` replicates the first stage at firm level with 3 outcomes
- [x] All specifications run for both coalition and party alignment types
- [x] Tables are saved in both `.md` and `.tex` formats
- [x] Regression tables include F-statistics computed via `fixest::wald()`

### Robustness matrix (target table)

The plan targets a robustness matrix for the first-stage table:

| Row | Sector def | LHS | RHS instrument | FE | Controls | Cluster |
|-----|-----------|-----|----------------|-----|----------|---------|
| 1 | 21 CNAE sections | delta_s | Z (changes) | muni x sec + muni x yr | — | muni + sec |
| 2 | 21 CNAE sections | delta_s | Z (changes) | muni x sec + sec x yr | — | muni + sec |
| 3 | 21 CNAE sections | delta_s | Z (changes) | muni x sec + muni x yr | exposure_control | muni + sec |
| 4 | 21 CNAE sections | s (levels) | Z_levels | muni x sec + muni x yr | — | muni + sec |
| 5 | ~10 groups | delta_s | Z (changes) | muni x grp + muni x yr | — | muni + grp |
| 6 | ~10 groups | delta_s | Z (changes) | muni x grp + grp x yr | — | muni + grp |
| 7 | ~10 groups | s (levels) | Z_levels | muni x grp + muni x yr | — | muni + grp |
| 8 | Firm-level | in_bndes | Z_mjt | firm + muni x yr | — | muni + sec |
| 9 | Firm-level | log(1+bndes) | Z_mjt | firm + muni x yr | — | muni + sec |

### Quality Gates
- [ ] F-statistics reported for all specifications; flag any below Stock-Yogo threshold (F < 10 for single instrument)
- [ ] Coefficient stability: mayor instrument coefficient should be broadly similar across rows 1-7
- [ ] Firm-level (rows 8-9) coefficient sign should match muni-sector level (row 1)
- [ ] Sector groups validated: no group with < 500 nonzero instrument observations

## Implementation Phases

### Phase 1: Sector Regrouping (script 36)
**Files**: `3_instruments/36_build_sector_groups.R` (new)
**Effort**: Small. Pure data mapping + validation.
**Dependencies**: Script 22 output (for cnae_division derivation from classe).

### Phase 2: Pipeline Propagation (scripts 31, 33-35, 41)
**Files**: Modify 5 existing scripts to accept `--sector-var` flag.
**Effort**: Medium. Each script needs conditional aggregation logic.
**Dependencies**: Phase 1 output (crosswalk).

### Phase 3: First-Stage Enhancements (script 51)
**Files**: `5_estimation/51_first_stage.R` (modify)
**Effort**: Medium. Add FE specifications, exposure control, and levels specification.
**Dependencies**: Phase 2 outputs (panels with grouped sectors and levels instruments).

Substeps:
1. Add `sector x year` FE specification to the existing FE grid.
2. Compute and include `exposure_control_mj` as a control variable.
3. Build levels instruments in script 34 and add levels regression to script 51.

### Phase 4: Firm-Level First Stage (script 53)
**Files**: `5_estimation/53_first_stage_firm.R` (new)
**Effort**: Medium. Loads large firm panel, merges sector instruments, runs fixest with firm FE.
**Dependencies**: Script 34 output (sector instruments), script 22 output (firm panel).

### Phase 5: Summary Table and Presentation Update
**Files**: `paper/presentation_progress.tex` (modify), table generation in scripts 51/53.
**Effort**: Small. Collect F-stats and coefficients from all specifications into a single comparison table.

## Dependencies & Risks

- **Data dependency**: Manufacturing subsector split requires `classe` (5-digit CNAE) from the reconstructed panel. Currently `cnae_division` is derived but dropped in script 22. Fix: either re-derive from `classe` in script 36, or modify script 22 to retain `cnae_division`.
- **Memory**: Firm-level regressions with firm FE on ~15M rows may be memory-intensive. Mitigation: use `fixest::feols(..., lean = TRUE)`, single-threaded, and consider subsetting to firms in municipalities with BNDES activity.
- **Levels instrument**: Need alignment *levels* (not deltas) from the political data. These are available in `in_power_upd_2002_2019.qs2` but haven't been used in the instrument pipeline yet. Need to verify column names and structure.
- **Sector x year FE interpretation**: With `muni_id^cnae_section + cnae_section^year`, identification comes from cross-municipality variation in political exposure within sector-year cells. This is less demanding than muni x year FE (which requires cross-sector variation within muni-year). F-stats may be higher but the identifying variation is different — document this.

## Sources & References

### Internal References
- Division-to-section mapping: `22_reconstruct_merged.R:120-170`
- Instrument construction: `34_build_shift_share_instruments.R`
- Current first stage: `51_first_stage.R`
- Sector share distribution: presentation appendix (slide: Sector Share Distribution)
- Design decisions: `docs/doubts.md` (Issues 3, 6, 7)

### External References
- Goldsmith-Pinkham, Sorkin & Swift (2020): shift-share instrument diagnostics
- Borusyak, Hull & Jaravel (2022): exposure design for shift-share
- Stock & Yogo (2005): weak instrument thresholds
