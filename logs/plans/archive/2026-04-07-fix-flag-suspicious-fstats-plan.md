# Plan: Flag Suspicious F-Statistics from Near-Zero SEs

**Status:** COMPLETED

## Context

Script 52's aggregated first-stage battery produces F-statistics in the billions for some specifications (e.g., size_bin + BNDES share + emp-weighted + MxJ+JxT + noctrl). The root cause is standard errors collapsing to machine-zero when `sector×year` FE absorbs nearly all instrument variation. The F-stat formula `(coef/se)^2` then explodes. These are numerical artefacts, not genuine signals, and they clutter the output tables.

## Approach: Centralized Formatting Guard in `beamer_tables.R`

**File**: `scripts/R/_utils/beamer_tables.R`

Single choke point — all .tex tables from scripts 51, 52, and 53 pass through this file.

### Change 1: `.build_fstat_row_only()` (~line 243)
Add a check before formatting:
- If `f > F_SUSPICIOUS_THRESHOLD` (10,000) or `!is.finite(f)`: format as `"$>$10k"` instead of the raw number
- Log a warning to stdout: `"WARNING: F-stat = X — likely near-zero SE artefact"`

### Change 2: `save_beamer_table()` (~lines 469-476)
Same guard for exposure-control F-stat formatting.

### Threshold

`F_SUSPICIOUS_THRESHOLD <- 10000` — Stock-Yogo critical values are 10–25; any genuine F > 10,000 would be extraordinary.

## Files to Modify

| File | Function | Change |
|------|----------|--------|
| `scripts/R/_utils/beamer_tables.R` | `.build_fstat_row_only()` (~L243) | Add finite + threshold check before `sprintf` |
| `scripts/R/_utils/beamer_tables.R` | `save_beamer_table()` (~L469-476) | Same guard for control F-stats |

## What NOT to Change

- `safe_wald()` in scripts 51, 52, 53 — raw values stay in manifests for traceability
- The underlying `fixest::wald()` call
- Bold formatting for F >= 10 — that stays, the guard only fires above 10,000

## Verification

After modifying `beamer_tables.R`, the guard will take effect the next time script 52 (or 51/53) is run. No immediate re-run needed.

To confirm later:
1. Check the .tex output: F-stats should show `$>$10k` instead of billions
2. Normal specs (F < 10,000) should be unaffected
3. Manifests retain raw values for traceability
