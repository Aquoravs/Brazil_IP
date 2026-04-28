---
title: "Diagnose total_owners Mismatches & Select Correction Rule"
type: fix
status: active
date: 2026-03-03
---

# Diagnose total_owners Mismatches & Select Correction Rule

## Overview

Script 31 (`31_build_sector_exposure_weights.R:332-345`) reports 484,607 firm-year observations (1.4%) where `total_owners_est = aff_count / share_aff` differs across party rows for the same `(firm_id, muni_id, year)`. The current code uses `max(total_owners_est)` as the firm-level estimate. This plan diagnoses the root cause, evaluates candidate correction rules by their downstream impact on `w_rjp`, and selects a single deterministic rule for script 31.

## Problem Statement

The identity `total_owners = aff_count / share_aff` should be constant across parties for a given firm-year. When it isn't, the denominator `N_rj` (total owners per muni-sector-year) inherits imprecision that can cause `w_rjp > 1`.

**Hypotheses**:

1. **Rounding in `share_aff_owners`** — upstream file stores shares as rounded floats (e.g., 0.33 instead of 1/3)
2. **Small-firm amplification** — firms with 2-5 owners have discrete shares where rounding errors are proportionally large

## Proposed Diagnostic Script

Single R script: `3_instruments/3x_diagnose_total_owners.R` (~100 lines). Runs on a **10% stratified muni sample** first; scale to full data only if the rule choice is unclear.

### Step 0: Sanity checks on raw data
- Load `owner_aff_upd_2002_2019.qs2`
- Sample 10% of municipalities (stratified random, set.seed for reproducibility)
- Filter to 2002-2017 (matching script 31)
- Assert `aff_count` is integer-valued
- Check whether `aff_count` is constant across party rows within each firm-year — if not, flag upstream data issue before proceeding
- Count firm-years where ALL party rows have `share_aff <= 0` or `NA` (no denominator recoverable from any row) — these must be excluded from both `L_rjp` and `N_rj`

### Step 1: Characterize mismatches
- Compute `total_owners_est = aff_count / share_aff` per row (where `share_aff > 0`)
- Per firm-year: compute `min_est`, `max_est`, `median_est`
- Flag mismatched firm-years (`min_est != max_est`)
- Report: count, share, distribution of `abs(max_est - min_est)` (p50, p90, p99, max)

### Step 2: Test rounding hypothesis
- For each mismatched firm-year: compute `round(total_owners_est)` per party row
- Count mismatches that **vanish** after rounding to nearest integer (all parties agree on `round()`)
- Count mismatches that **persist** after rounding
- Report: `% vanished` — this is the key decision input

### Step 3: Mismatch rate by firm size
- Bucket firms by `max(total_owners_est)`: 1-2, 3-5, 6-10, 11-50, 50+
- Tabulate mismatch rate per bucket (table to console)

### Step 4: Downstream impact — compare candidate rules
For ALL mismatched firm-years in the sample, compute `total_owners` under three candidate rules:

| Rule | Formula |
|------|---------|
| **Current** (status quo) | `max(total_owners_est)` floored at `sum(aff_count)` |
| **Rounded median** | `round(median(total_owners_est))` floored at `sum(aff_count)` |
| **Rounded max** | `round(max(total_owners_est))` floored at `sum(aff_count)` |

For each rule:
- Load sector mapping from reconstructed panel (`rais_bndes_reconstructed.fst`)
- Merge sector, aggregate to `N_rj`, recompute `w_rjp = L_rjp / N_rj`
- Check: `max(w_rjp) ≤ 1`? `Σ_p w_rjp ≤ 1` per cell?
- Report: distribution of `|w_rjp_candidate - w_rjp_current|` (p50, p95, p99, max)

### Step 5: Decision tree (printed to console)

```
IF ≥95% of mismatches vanish after integer rounding:
  → Adopt round(median(total_owners_est)), floored at sum(aff_count)
  → Rationale: all estimates point to the same integer; median is robust to outlier shares
ELSE IF persistent mismatches concentrated in firms with ≤5 owners:
  → Adopt round(max(total_owners_est)), floored at sum(aff_count)
  → Rationale: max is conservative (avoids w > 1); rounding recovers integer counts
ELSE:
  → Flag for manual review; print sample of persistent mismatches
```

### Step 6: Two diagnostic plots (ggplot2)
1. **Histogram**: `abs(max_est - min_est)` among mismatched firms (linear scale)
2. **Bar chart**: mismatch rate by firm-size bucket

Save to `output/diagnostics/total_owners_mismatch_{histogram,by_size}.png`.

## Acceptance Criteria

- [ ] `aff_count` confirmed integer and constant within firm-year (or upstream issue flagged)
- [ ] Coverage gap quantified: firm-years with no recoverable `total_owners` from any party row
- [ ] Rounding hypothesis tested: % of mismatches that vanish after `round()`
- [ ] Downstream impact quantified: distribution of `|Δw_rjp|` under 3 candidate rules
- [ ] **Single deterministic rule selected** that (i) yields integer counts, (ii) keeps `Σ_p L_rjp ≤ N_rj` in every cell, (iii) changes `w_rjp` by < ε for 99% of cells
- [ ] 2 diagnostic plots saved to `output/diagnostics/`

## Files to create/modify

- **Create**: `BNDES/politicsregs/3_instruments/3x_diagnose_total_owners.R`
- **Update later** (after diagnostic): `31_build_sector_exposure_weights.R:311-325` — replace `max()` with chosen rule
- **Update**: this plan file — mark completed

## Verification

1. Run: `Rscript BNDES/politicsregs/3_instruments/3x_diagnose_total_owners.R`
2. Check console output for decision tree recommendation
3. Check `output/diagnostics/` for 2 plots
4. If decision is clear, apply rule to script 31 and re-run `31:35` pipeline

## Sources

- `BNDES/politicsregs/3_instruments/31_build_sector_exposure_weights.R:311-345` — total_owners computation and consistency check
- `BNDES/politicsregs/3_instruments/3x_audit_shift_share.R` — existing audit script (Section A)
- `docs/shift_share.md` — instrument specification
- `BNDES/politicsregs/_utils/utils.R` — path helpers (`make_base_path`, `make_output_path`)
