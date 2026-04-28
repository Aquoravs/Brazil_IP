# 2026-04-14 — Script 42 memory efficiency overhaul

## Goal
Fix two failures in `scripts/R/4_regression_panels/42_build_firm_panel.R`:
1. Step 3D merge error: `vecseq` cartesian blocker
2. Step 4 OOM: `cannot allocate vector of size 62.2 Mb` during `[cycle_specific]` baseline attach

## Operations
- Edited `scripts/R/4_regression_panels/42_build_firm_panel.R`:
  - Step 3B: swapped `uniqueN(muni_id) by (firm_id, year)` for GForce-accelerated `.N` (panel is unique on firm×muni×year)
  - Step 3B: consolidated four separate `panel[is_multi_muni == ...]` scans into one aggregated pass
  - Step 3D: added `allow.cartesian = TRUE` to both `muni_bl_mayor_yr` / `muni_bl_gp_yr` merges (legitimate many-to-many)
  - Step 3C: persisted `bl_emp_cycle_spread` and `bl_emp_fixed_spread` to temporary qs2 files, removed from RAM
  - Step 4: removed `panel[, (all_instrument_cols) := 0]` pre-allocation (was ~17 GB upfront)
  - Step 4: pre-filled NAs in `instruments` once with `setnafill`, join lets columns allocate on first write
  - Step 4: replaced 48-iteration column NA-fill loop with single `setnafill` post-join
  - Step 4: coerced `FA_binary_*` / `dFA_binary_*` to integer (saves ~4 GB)
  - Step 4: added `gc(full = TRUE)` before each bt iteration to counter Windows heap fragmentation
  - Step 4: reload baseline spread from disk inside each bt iteration, rm after use
  - Step 4: dropped qs2 dual-write — all downstream scripts try fst first
  - End of Step 4: `unlink` temp baseline qs2 files

## Decisions
- Chose `.N` over `uniqueN` in Step 3B — panel's (firm, muni, year) uniqueness guarantees equivalence and `.N` is GForce-accelerated
- Dropped qs2 dual-write — 14 downstream scripts verified to prefer `.fst` with qs2 as fallback only
- Kept `compute_bl_employment` / `spread_bl_employment` untouched — they're memory-bounded already
- Did not migrate to Parquet/Arrow or year-chunking (Tier 3 proposals) — bigger refactor touching downstream consumers

## Results
- Step 3B runtime: expected to drop from minutes to seconds (GForce `.N`)
- Step 4 peak RAM: expected ~12 GB reduction (pre-alloc elimination + binary narrowing + baseline off-RAM)
- Output footprint: halved (fst only)

## Status
- Done: patches applied; script not yet re-run
- Pending: user to re-run `42_build_firm_panel.R` and confirm completion through Step 4
