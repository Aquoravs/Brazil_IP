---
title: "Audit & Fix Shift-Share Instrument Construction (Scripts 31–35)"
type: fix
status: completed
date: 2026-03-03
---

# Audit & Fix Shift-Share Instrument Construction (Scripts 31–35)

## Overview

A code review flagged exposure weight shares (`w_rjp`) with values outside [0, 1], pointing to a denominator construction error in script 31. This plan takes a **fix-first, invariant-driven** approach: patch the likely root cause, validate with two key invariants on a small sample, then do a full re-run. Exhaustive downstream checks (scripts 32–35) are deferred unless post-fix invariants still fail.

**Intended specification**:

$$Z_{mjt} = \sum_p \frac{L_{mjp,0}}{L_{mj,0}} \times \Delta\text{Align}_{mpt}$$

- $L_{mjp,0}$ = affiliated owners with party $p$ in sector $j$, muni $m$ at baseline
- $L_{mj,0}$ = **total** owners (affiliated + unaffiliated) in that cell
- $\Delta\text{Align}_{mpt}$ = alignment turnover shock for party $p$ in muni $m$ at time $t$

## Acceptance Criteria

- [x] `max(w_rjp) ≤ 1` across all (muni, sector, party, year) cells
- [x] `Σ_p w_rjp ≤ 1` per (muni, sector, year) cell — i.e., affiliated owners across all real parties do not exceed total owners
- [x] `N_rj` is non-missing wherever any `L_rjp > 0` — no firm contributes to the numerator without its total owners entering the denominator
- [x] "No party" owners contribute to the denominator but do NOT feed through as a non-zero instrument component (either filtered out or zeroed via missing shock match)
- [x] `dalign ∈ {−1, 0, 1}` and non-zero only in inauguration years (their impact lasts the full 4-year cycle via spreading in script 34)
- [x] Baseline weight selection uses the correct pre-election year for each cycle
- [x] Final instrument sums `share × shock` across parties correctly at (muni, sector, year) level
- [x] Invariants also hold under `--sector-var=sector_group` (spot check)

---

## Phase 1: Fast Guardrail — Diagnose Current State

**Goal**: Quantify the problem on current outputs before touching any code.

**Actions** (~60–80 line diagnostic script: `3_instruments/3x_audit_shift_share.R`):

### Section A: Raw Affiliation Structure
1. Load `owner_aff_upd_2002_2019.qs2` and report:
   - Unique values of `party` — is "No party" (or equivalent like `"Sem partido"`) present?
   - For a sample of firm-years: does `Σ share_aff` across parties (incl. "No party") ≈ 1?
   - For firms with all unaffiliated owners: is there a "No party" row with `share_aff > 0`?
   - Are there rows with `aff_count > 0` but `share_aff = 0` or `share_aff = NA`?

### Section B: Numerator vs. Denominator Coverage
2. Load `sector_exposure_weights_owner.qs2` (script 31 output) and compute:
   - **Invariant 1**: `max(w_rjp)` — how far above 1 do shares go?
   - **Invariant 2**: `max(Σ_p L_rjp / N_rj)` per (muni, sector, year) cell
   - Count of cells where `N_rj = 0` or `NA` but `L_rjp > 0` (denominator gap)
   - Count of cells where `w_rjp > 1`

### Section C: Decide on "No Party"
3. Check whether "No party" appears in `alignment_shocks.qs2` (script 32 output). If absent → "No party" rows get `dalign = 0` after merge in script 34, contributing nothing to the instrument. Document this explicitly.
4. **Decision**: filter `party != "No party"` in script 31 after computing `N_rj` (so "No party" owners count in the denominator but are excluded from the numerator). If "No party" is critical for the denominator recovery, keep it there and filter only in script 33 or 34.

**Output**: PASS/FAIL report with counts. If Invariant 1 fails → proceed to Phase 2.

---

## Phase 2: Fix Script 31 Denominator

**Root cause hypothesis**: `L_rjp` is summed from ALL affiliation rows that merge with a sector (line 370). But `N_rj` is summed only from firms where `total_owners_est` is computable — i.e., where `share_aff > 0 & !is.na(share_aff)` (line 297). Firms with `share_aff = 0` or NA contribute affiliated owners to `L_rjp` but zero to `N_rj`.

**Fix** (in `31_build_sector_exposure_weights.R`):

1. **Ensure all firms with `L_rjp > 0` also contribute to `N_rj`**. Options:
   - (a) Recover `total_owners` from the "No party" row of the same firm (if it has `share_aff > 0`), even when other party rows have `share_aff = 0`
   - (b) For firms with no computable `total_owners_est` from any row, exclude their `aff_count` from `L_rjp` as well (symmetric exclusion)
   - (c) Use the max `total_owners_est` across ALL parties for a firm (including "No party"), already done — but ensure the "No party" row is actually included in the computation before dedup

   **Preferred**: Option (a) — recover from any row with `share_aff > 0` (the current code does this via `max` dedup, but may miss firms where only "No party" has `share_aff > 0` if "No party" is later filtered). If no row has `share_aff > 0`, use option (b).

2. After computing `N_rj`, assert: for every (muni, sector, year) cell with `L_rjp > 0`, `N_rj > 0`.

3. After computing `w_rjp`, assert: `max(w_rjp) ≤ 1` and `Σ_p w_rjp ≤ 1` per cell.

**Key code locations** in `31_build_sector_exposure_weights.R`:
- Lines 296–300: `total_owners_est` computation
- Lines 309–312: `firm_owners` deduplication (takes max across parties)
- Lines 340–343: `N_rj` aggregation
- Lines 370–371: `L_rjp` aggregation
- Lines 386–396: `w_rjp_owners = L_rjp / N_rj`

---

## Phase 3: Small-Sample Validation

**Goal**: Confirm the fix works before a full re-run.

**Actions**:
1. Re-run scripts 31→34 on a **5% random muni sample** (or a fixed set of ~500 munis).
2. Re-check both invariants:
   - `max(w_rjp) ≤ 1` ✓
   - `Σ_p w_rjp ≤ 1` per cell ✓
   - `N_rj > 0` wherever `L_rjp > 0` ✓
3. Spot-check: for 3–5 (muni, sector, year) cells, manually compute `L_rjp / N_rj` from raw affiliation data and compare to script output.
4. If invariants pass → proceed to Phase 4. If not → revisit the fix.

---

## Phase 4: Full Re-Run and Downstream Assertions

**Actions**:
1. Full re-run: `Rscript run_politicsregs.R 31:35`
2. Re-run the diagnostic script (Section B) on the new outputs to confirm invariants at scale.
3. **Lightweight downstream checks** (single assertions, not full audits):
   - Script 32: `dalign ∈ {−1, 0, 1}` and non-zero only in inauguration years {2005, 2009, 2013, 2017} for mayor, {2003, 2007, 2011, 2015, 2019} for gov/pres
   - Script 33: baseline_year matches cycle_map; `w_rjp_0` equals script 31 output at the baseline year within tolerance 1e-10
   - Script 34: `share_owner_cell ≈ w_rjp_0` within tolerance; year 2002 has Z = 0 (no inauguration maps there)
   - Script 35: already has built-in share-sum and delta-sum assertions — defer unless flagged
4. **Grouped-sector spot check**: re-run with `--sector-var=sector_group` and verify the same two invariants hold.

---

## Phase 5 (Deferred): Full Audit of Scripts 32–35

Only if post-fix invariants still fail or downstream outputs look anomalous, expand to:
- Exhaustive inauguration-year timing checks (script 32)
- Merge rate analysis between baseline weights and shocks (script 34)
- Manual Z computation for sample cells (script 34)
- Credit share balance checks (script 35)

These are already partially covered by the diagnostic code embedded in each script.

---

## Implementation Details

### Diagnostic Script: `3_instruments/3x_audit_shift_share.R`

~60–80 lines, three sections:
- **Section A**: Raw affiliation structure (party values, share sums, "No party" presence)
- **Section B**: Numerator vs denominator coverage on current script 31 output
- **Section C**: Post-fix invariant checks (re-run after Phase 2)

Read-only. Does not modify data.

### Fix Scope

- Script 31: ~10–20 lines changed in the denominator computation
- Possibly add `party != "No party"` filter for the numerator (after denominator is computed)
- Add inline assertions (`stopifnot(max(w_rjp) <= 1)`) as permanent guardrails

### Execution Sequence

```
Phase 1 → Phase 2 → Phase 3 → Phase 4
  (diagnose)  (fix 31)  (5% sample)  (full re-run + assertions)
```

Total: ~60–80 line diagnostic script + ~10–20 line fix in script 31. Full re-run via `Rscript run_politicsregs.R 31:35`.

## Sources

- `BNDES/politicsregs/3_instruments/31_build_sector_exposure_weights.R` — exposure weight construction (primary fix target)
- `BNDES/politicsregs/3_instruments/32_build_alignment_shocks.R` — alignment shock computation
- `BNDES/politicsregs/3_instruments/33_select_baseline_weights.R` — baseline year selection
- `BNDES/politicsregs/3_instruments/34_build_shift_share_instruments.R` — Bartik instrument assembly
- `BNDES/politicsregs/3_instruments/35_build_credit_shares.R` — endogenous variable construction
- `docs/shift_share.md` — instrument specification notes
- `CLAUDE.md` — project conventions and variable naming
