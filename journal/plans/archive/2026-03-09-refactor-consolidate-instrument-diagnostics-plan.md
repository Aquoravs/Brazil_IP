---
title: "refactor: Consolidate instrument diagnostic scripts into single pipeline gate"
type: refactor
status: completed
date: 2026-03-09
origin: docs/brainstorms/2026-03-09-diagnostic-scripts-consolidation-brainstorm.md
---

# Consolidate Instrument Diagnostic Scripts into Single Pipeline Gate

## Overview

Replace six overlapping diagnostic scripts with a single audit gate (`audit_3_instruments.R`) that validates instrument construction outputs (scripts 31-35). The gate hard-stops on critical failures, preventing the pipeline from reaching regression stages with invalid instruments.

## Problem Statement / Motivation

Six diagnostic scripts accumulated during development of the shift-share instrument pipeline. They overlap substantially, and the key data quality issue they investigated (owner-estimation mismatches across parties) has been resolved upstream. The current state creates confusion about which script to run, what checks matter, and whether failures are critical or informational.

**From a referee perspective**: A clean, single audit that verifies the algebraic correctness of Z_mjt = sum_p (L_rjp,0 / N_rj,0) * dAlign_mtp is essential. Scattered diagnostics make it unclear whether the instruments satisfy their own construction identities.

## Proposed Solution

**Approach A from brainstorm**: Keep `diagnostics/audit_3_instruments.R` as the sole diagnostic, add ~5 missing checks from `3x_audit_shift_share.R`, register as pipeline stage 36, archive 5 obsolete scripts.

(See brainstorm: `docs/brainstorms/2026-03-09-diagnostic-scripts-consolidation-brainstorm.md` — Approach A chosen over two-tier system and full consolidation)

## Acceptance Criteria

### Must Have

- [x] `audit_3_instruments.R` includes 5 new checks (see "Checks to Add" below)
- [x] `--strict=true` is the default (line 62 already has this; verified)
- [x] Stage 36 registered in `run_politicsregs.R` orchestrator
- [ ] Pipeline `30:51` halts at stage 36 if critical checks fail
- [x] 5 scripts archived to `_archive/` with retirement headers
- [x] `README_script31_walkthrough.md` archived alongside its script

### Nice to Have

- [ ] `--sector-var=sector_group` support (currently blocked at line 54; defer)
- [ ] `--verbose` flag for detailed console output vs. quiet pass/fail

## Checks to Add to `audit_3_instruments.R`

All checks use the existing `add_check()` framework. **No raw data loading** — all checks operate on output files already loaded by the audit.

### From `3x_audit_shift_share.R` Section B (output-level)

| # | check_id | severity | what it checks | dataset |
|---|----------|----------|----------------|---------|
| 1 | `weight_sum_per_cell` | critical | `sum_p(w_rjp_owners) <= 1` per (muni, sector, year) cell | `sector_exposure_weights_owner` |
| 2 | `denominator_gap_L_positive_N_zero` | warning | Rows where `L_rjp > 0` but `N_rj == 0` or NA | `sector_exposure_weights_owner` |

### From `3x_audit_shift_share.R` Section C

| # | check_id | severity | what it checks | dataset |
|---|----------|----------|----------------|---------|
| 3 | `no_party_absent_from_shocks` | warning | "No party" / "Sem partido" variants not present as party values in alignment_shocks | `alignment_shocks` |

### From general best practice (brainstorm recommendations)

| # | check_id | severity | what it checks | dataset |
|---|----------|----------|----------------|---------|
| 4 | `N_rj_approximately_integer` | warning | `max(abs(N_rj - round(N_rj))) < 0.01` — confirms upstream collapsing produced clean estimates | `sector_exposure_weights_owner` |
| 5 | `weight_sum_per_cell_firms` | warning | `sum_p(w_rjp_firms) <= 1` per cell (robustness variant) | `sector_exposure_weights_owner` |

**Checks NOT added** (resolved upstream or require raw data):
- Per firm-year `share_aff` sum distribution → requires raw affiliation file; owner mismatch resolved upstream
- Party enumeration → informational; not a gate check
- `aff_count > 0` with `share_aff = 0/NA` → requires raw file; addressed by upstream collapsing rule

## Implementation Steps

### Step 1: Add checks to `audit_3_instruments.R`

**File**: `BNDES/politicsregs/diagnostics/audit_3_instruments.R`

Insert the 5 new checks into the Script 31 checks section (after line 323, before Script 32 section). Code pattern:

```r
# --- Additional Script 31 checks (from consolidation) ---

# Check: sum_p(w_rjp_owners) per (muni, sector, year) cell
if ("w_rjp_owners" %in% names(wt)) {
  cell_sums_own <- wt[!is.na(w_rjp_owners),
                       .(sum_w = sum(w_rjp_owners)),
                       by = .(muni_id, cnae_section, year)]
  max_sum_own <- cell_sums_own[, max(sum_w, na.rm = TRUE)]
  n_above_1_own <- cell_sums_own[sum_w > 1.001, .N]
  add_check("identity", "sector_exposure_weights_owner", "weight_sum_per_cell_owners",
            "critical", max_sum_own <= 1.001, "max_cell_sum", max_sum_own, "<= 1.001",
            sprintf("Cells with sum > 1: %d / %d", n_above_1_own, nrow(cell_sums_own)))
  rm(cell_sums_own)
}

# (similar pattern for checks 2-5)
```

### Step 2: Register stage 36 in orchestrator

**File**: `BNDES/politicsregs/run_politicsregs.R`

Add one line to the `pipeline` list (between `"35"` and `"41"` entries, approximately line 60):

```r
"36" = "diagnostics/audit_3_instruments.R",
```

The orchestrator's numeric sorting (`order(as.integer(requested))`) ensures correct execution order. Forward args (`--sector-var`, etc.) pass through automatically.

**Note**: Cross-directory path is fine — the orchestrator uses `system2("Rscript", args = script_path)` with working directory set to `politicsregs/`.

### Step 3: Archive 5 obsolete scripts

Move to `_archive/` with a retirement header prepended to each:

```r
# ARCHIVED 2026-03-09: Consolidated into diagnostics/audit_3_instruments.R (stage 36).
# Owner-estimation mismatch resolved upstream. See docs/brainstorms/2026-03-09-*.md.
```

**Files to archive**:
1. `3_instruments/3x_large_gap_cases.R`
2. `3_instruments/3x_audit_shift_share.R`
3. `3_instruments/3x_diagnose_total_owners.R`
4. `diagnostics/inspect_script31_walkthrough.R`
5. `diagnostics/README_script31_walkthrough.md`

**Files NOT archived** (different purpose):
- `diagnostics/sector_group_diagnostics.R` — Rotemberg decomposition, descriptive plots
- `diagnostics/shift_share_construction_tests.R` — synthetic + real invariant tests (complementary to gate)

### Step 4: Verify

```bash
# Dry run to confirm registration
Rscript BNDES/politicsregs/run_politicsregs.R 36 --dryrun

# Run gate standalone
Rscript BNDES/politicsregs/diagnostics/audit_3_instruments.R --strict=true

# Run instruments through gate
Rscript BNDES/politicsregs/run_politicsregs.R 35:36

# Full pipeline through estimation
Rscript BNDES/politicsregs/run_politicsregs.R 30:51
```

## Econometric Criticality Ranking

(Carried forward from brainstorm)

| Check | Severity | Why it matters for 2SLS |
|-------|----------|------------------------|
| Key uniqueness (all datasets) | Critical | Duplicate keys inflate instrument variation, bias F-stats |
| Z reconstruction = baseline x shocks | Critical | If Z != formula, exclusion restriction argument is wrong |
| w_rjp in [0, 1] | Critical | Weights > 1 → denominator < numerator; instrument nonsensical |
| **sum_p(w_rjp) <= 1 per cell** (NEW) | Critical | Ensures weights are proper shares within each muni-sector-year |
| delta_s sums to ~0 per muni-year | Critical | Simplex constraint for dropped-sector interpretation |
| Credit shares sum to 1 | Critical | Same as above |
| Balanced panel (script 35) | Critical | Gaps in delta_s break first-differencing |
| dalign in {-1, 0, 1} | Critical | Alignment shock must be proper indicator change |
| Shocks only at inaugurations | Warning | Non-inauguration shocks suggest data error |
| **Denominator gap L>0, N=0** (NEW) | Warning | Edge case; contributes w_rjp = 0, so benign |
| **N_rj approximately integer** (NEW) | Warning | Confirms upstream collapsing; non-integer = data issue |
| **"No party" absent from shocks** (NEW) | Warning | Design assumption; benign if present (gets dalign=0) |

## Dependencies & Risks

**Risk**: `--sector-var=sector_group` forwarded by orchestrator hits the hard stop at line 54. **Mitigation**: For now, the audit only supports `cnae_section`. Document as known limitation. Add grouped-sector support in a follow-up when the grouped pipeline matures.

**Risk**: Cross-directory path in orchestrator. **Mitigation**: Orchestrator already uses `system2` with working directory = `politicsregs/`, so `diagnostics/audit_3_instruments.R` resolves correctly.

## Sources & References

- **Origin brainstorm**: [docs/brainstorms/2026-03-09-diagnostic-scripts-consolidation-brainstorm.md](docs/brainstorms/2026-03-09-diagnostic-scripts-consolidation-brainstorm.md) — Approach A chosen, owner mismatch resolved upstream, hard stop on critical
- **Existing audit framework**: `BNDES/politicsregs/diagnostics/audit_3_instruments.R` (lines 100-158 for `add_check()` pattern)
- **Orchestrator registration**: `BNDES/politicsregs/run_politicsregs.R` (line 60, `pipeline` list)
- **Archive convention**: `BNDES/politicsregs/_archive/` (18 existing archived scripts)
- **Prior plan**: `docs/plans/2026-03-03-fix-audit-shift-share-instrument-construction-plan.md` — established two-level assertion strategy (invariants vs. downstream checks)
