---
title: "refactor: Split firm panel output into base + sparse instruments"
date: 2026-04-14
sequence: 002
type: refactor
status: completed
depth: standard
origin: conversation (2026-04-14 script42 OOM debugging)
touches:
  - scripts/R/4_regression_panels/42_build_firm_panel.R
  - scripts/R/_utils/load_firm_panel.R (new)
  - scripts/R/5_estimation/51_firm_first_stage.R
  - scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R
  - scripts/R/5_estimation/52b_proposition2_equivalence.R
  - scripts/R/3_instruments/30c_build_size_bin_mapping.R
  - scripts/R/3_instruments/30d_build_sector_size_bin_mapping.R
  - scripts/R/diagnostics/compare_prop2_reference_spec.R
  - scripts/R/diagnostics/create_firm_sample.R
  - scripts/R/diagnostics/diagnose_agg_first_stage_collapse.R
  - scripts/R/diagnostics/diagnose_firm_instruments.R
  - scripts/R/diagnostics/diagnose_proposition2_gap.R
  - scripts/R/diagnostics/diagnose_sector_group_cell_support.R
  - scripts/R/diagnostics/diagnose_size_bin_emp_concentration.R
  - scripts/R/diagnostics/sector_taxonomy_diagnostics.R
---

# Refactor: Split firm panel output into base + sparse instruments

## 1. Problem Frame

`scripts/R/4_regression_panels/42_build_firm_panel.R` Step 4 OOMs on Windows with
`cannot allocate vector of size 62.2 Mb` while attaching the `[cycle_specific]` baseline to the
assembled firm panel. The preceding Tier 1 memory patches (see session log
`quality_reports/session_logs/2026-04-14_script42_memory_efficiency.md`) removed ~17 GB of
preventable allocation (zero pre-allocation, 48-iter NA-fill loop, double→int binary narrowing,
off-RAM baseline spreads, GForce `.N`, qs2 dual-write elimination). Script 3B is fast again;
Step 3D cartesian is fixed. **The remaining OOM is structural, not incidental.**

### Why the OOM is structural

Panel shape at Step 4: **44,181,405 rows × (existing + 48 new instrument columns)**.

Materializing 48 FA/dFA columns onto the panel allocates, in the join:

| Column group | Count | Dtype | Bytes/row | Total GB |
|---|---|---|---|---|
| `FA_*` / `dFA_*` continuous | 36 | double | 8 | ~12.0 |
| `FA_binary_*` / `dFA_binary_*` | 12 | int32 | 4 | ~2.0 |
| **Subtotal new allocation** | **48** | | | **~14.0** |
| Pre-existing panel in RAM | — | — | — | ~10.0 |
| **Peak working set** | | | | **~24.0** |

On a 32 GB Windows box with heap fragmentation, the join reliably fails at
the first baseline attach. `gc(full = TRUE)` defers but does not prevent the failure because
the 14 GB is genuine new state, not fragmentation.

### Root cause

**Sparsity mismatch.** The 48 instrument columns are non-zero only for firms with BNDES owner
links in a given (muni, year, cycle). For most firm×muni×year rows the instrument value is the
zero fill. We are paying dense-matrix cost to store sparse data.

### Goal

Eliminate the ~14 GB Step 4 peak allocation without changing the regression-level semantics
or forcing downstream consumers to handle two files by hand.

## 2. Scope

### In scope

- Step 4 output format of `42_build_firm_panel.R` (two files per baseline instead of one fat file)
- A new shared loader `scripts/R/_utils/load_firm_panel.R` that joins base + sparse on demand
- Migration of the 14 downstream consumers to the loader
- Backward-compat transition: leave fat-file reads as a fallback path in the loader for one
  cycle, then remove

### Out of scope

- Parquet/Arrow migration
- Year-chunking of the panel
- Redesigning the instrument construction itself (still 48 columns)
- Redesigning Step 3 baseline computation
- Changing the set of regressions run downstream

### Non-goals

- No change to numeric output of any first-stage / reduced-form spec
- No change to the muni-level baseline merges (those stay in base)
- No new dependencies (still `data.table`, `fst`, `qs2`)

## 3. Success Criteria

1. **Script 42 completes Step 4 within ≤ 14 GB peak RAM on a Windows 32 GB machine** for both
   `cycle_specific` and `2002_fixed` baseline_types.
2. **Every downstream consumer produces bit-identical first-stage / reduced-form estimates**
   against the pre-refactor fat file (tolerance `1e-10` on coefficients, identical N).
3. **Loader API is the single entry point** — no downstream script reads `firm_panel_for_regs*.fst`
   directly after migration.
4. **Output disk footprint does not grow** vs the current fst-only output (sparse file must
   genuinely be smaller than the dense equivalent).

## 4. Approach (High-Level Technical Design)

> *This section illustrates the intended shape of the refactor. It is directional guidance for
> review, not implementation specification.*

### File layout (per baseline `bt ∈ {cycle_specific, 2002_fixed}`)

```
output/firm_panel_for_regs{_bt}.fst                 # BASE: panel without FA/dFA
output/firm_panel_for_regs{_bt}_instruments.fst     # SPARSE: non-zero FA/dFA rows only
```

- **Base** = every column currently in `firm_panel_for_regs*.fst` **except** the 48 instrument
  columns. Includes `firm_id`, `muni_id`, `year`, `baseline_type`, outcomes, controls, muni
  baseline merges, `bl_n_employees`, sector/size-bin columns.
- **Sparse instruments** = only rows where at least one of the 48 FA/dFA columns is non-zero;
  keys `(firm_id, muni_id, year)` + the 48 columns. Expected row count:
  **~(non-zero instrument mass) / 44.2M** — empirically small for this design.

### Write path (Step 4 of script 42)

```
for bt in baseline_types:
  gc(full=TRUE)
  inst_bt  <- instruments[baseline_type == bt]      # already narrow; sparse by construction
  base_bt  <- panel  (without FA/dFA columns)        # no wide materialization
  attach muni + firm baselines to base_bt (as today)
  write_fst(base_bt,  "..._bt.fst")
  write_fst(inst_bt,  "..._bt_instruments.fst")     # no zero-fill; only real non-zero rows
  rm(base_bt, inst_bt); gc(full=TRUE)
```

**No 48-column materialization on the 44M panel is ever performed.** The peak allocation
becomes `nrow(panel) * ncol(base)` — the quantity that already fits in RAM today.

### Read path (shared loader)

```r
# scripts/R/_utils/load_firm_panel.R
load_firm_panel <- function(baseline_type = c("cycle_specific", "2002_fixed"),
                            columns = NULL,             # NULL = all
                            instruments = NULL,         # NULL = all 48, character() = none
                            zero_fill = TRUE,           # fill non-matched sparse rows with 0
                            as_data_table = TRUE) { ... }
```

Behavior:
1. Read base fst with column-selective `fst::read_fst(..., columns = base_cols)`
2. If `instruments` is empty, return base
3. Else read sparse fst with `columns = c(keys, instruments)`
4. Left-join sparse onto base on `(firm_id, muni_id, year)`
5. If `zero_fill`, `setnafill(dt, type="const", fill=0, cols=instruments)`
6. Return `data.table` or `data.frame`

**Key insight:** the materialization cost is now paid *by each downstream script, for only the
instruments it actually uses*. Script 51 typically uses a ~8-column subset of the 48; its peak
goes from 14 GB to ~2 GB.

### Fallback behavior

Loader falls back to reading the legacy fat file if the sparse file is missing:

```
if !exists sparse file AND exists legacy fat file:
  warn once, read legacy path, project the requested columns
```

This lets downstream migration land in parallel with the producer migration.

## 5. Implementation Units

### Unit 1 — Build the shared loader

**File:** `scripts/R/_utils/load_firm_panel.R` (new)

**Test file:** `scripts/R/_utils/test_load_firm_panel.R` (new, runs manually — project has no
automated test harness)

**Scope:**
- Single function `load_firm_panel(baseline_type, columns, instruments, zero_fill, as_data_table)`
- Accepts character vector of instrument columns or sentinel `NULL` (all) / `character(0)` (none)
- Uses `fst::metadata_fst()` to intersect requested columns with what's available — matches the
  pattern already used at `scripts/R/5_estimation/51_firm_first_stage.R:load_panel_subset`
- Reads base file with `columns = ...`; reads sparse file with `columns = c(keys, instruments)`
- Joins on `(firm_id, muni_id, year)` using `data.table` key
- Zero-fills non-matched sparse rows
- Legacy fat-file fallback with a one-time `message()` warning
- Resolves output paths via the same `make_output_path()` helper used in script 42
- No side effects beyond reading files

**Tests (manual, in companion script):**
1. Happy path: load base-only — returns panel with no FA/dFA
2. Full load: load all 48 instruments — result matches legacy fat file column-for-column
3. Column subset: request 3 continuous instruments — returned df has exactly those + base cols
4. Zero-fill correctness: a known firm with no owner data has FA/dFA rows filled with 0 (not NA)
5. Baseline switch: `cycle_specific` and `2002_fixed` both load, differ where expected
6. Fallback: when sparse file absent, loader reads legacy fat file and emits a warning once per
   session

**Dependencies:** none (pure utility).

**Execution target:** internal (reviewer checks loader contract before producer rewrite).

---

### Unit 2 — Rewrite Step 4 of script 42 to emit split files

**File:** `scripts/R/4_regression_panels/42_build_firm_panel.R`

**Scope (Step 4 only — Steps 0–3 untouched):**
- Remove the 48-column materialization onto `panel`
- Inside the `for (bt in baseline_types)` loop:
  - Build `base_bt` = `panel` copy *without* FA/dFA columns, with muni + firm baselines attached
    (logic currently in the loop, minus the instrument join)
  - Build `inst_bt` = `instruments[baseline_type == bt, c(keys, all_instrument_cols)]` filtered
    to rows where `rowSums(abs(instruments)) > 0` (sparse projection)
  - Write both files via `write_fst_atomic(...)`
  - Log row counts and file sizes side-by-side for sanity
- Remove `qs2` dual-writes (already done in prior pass; retain removal)
- Keep `unlink` of temp baseline qs2 files at end
- Keep `gc(full = TRUE)` before each bt iteration

**Critical invariant:** `inst_bt` sparse projection must be done on the *untouched* 48-column
instruments table, not after any zero-fill. Otherwise every row is "non-zero" and sparsity is
lost.

**Tests (manual):**
1. Dry-run with `test_mode = TRUE` (small sample) produces both files
2. Full run completes Step 4 without OOM, peak RAM measured < 20 GB via `pryr::mem_used()`
   bracketing each bt iteration
3. Row count check: `nrow(inst_bt) < nrow(base_bt)` (sparsity confirmed)
4. Disk check: base + sparse file sizes sum to ≤ 1.1× current fat file size

**Dependencies:** Unit 1 (loader must exist first so base/sparse split is defined against a
concrete contract).

**Execution target:** internal.

---

### Unit 3 — Migrate first-stage estimators (51, 52, 52b)

**Files:**
- `scripts/R/5_estimation/51_firm_first_stage.R`
- `scripts/R/5_estimation/52_aggregated_firm_sector_first_stage.R`
- `scripts/R/5_estimation/52b_proposition2_equivalence.R`

**Scope:**
- Replace direct `fst::read_fst(firm_panel_for_regs*.fst, columns = ...)` calls with
  `load_firm_panel(baseline_type = ..., columns = ..., instruments = ...)`
- `51` already has a `load_panel_subset(baseline_value, test_mode, keep_cols)` wrapper — rewrite
  its internals to delegate to the new loader; keep its signature so callers don't churn
- `52` has two read sites (~lines 967, 1620) — migrate both
- `52b` uses the panel for proposition-2 equivalence tests — migrate with same column selection
- Split `keep_cols` into `base_cols` and `instrument_cols` at each call site (simple grep on
  `^FA_|^dFA_` vs everything else)

**Tests (manual):**
1. Re-run `51` pre- and post-migration; coefficient tables match to `1e-10`
2. Same for `52` aggregated first stage
3. Same for `52b` proposition-2 equivalence (this one is the strictest — it asserts identity,
   any deviation breaks the paper claim)
4. `log` output shows loader's one-time warning is *not* emitted (i.e. we're hitting the split
   path, not the fallback)

**Dependencies:** Units 1 and 2.

**Execution target:** external-delegate (pure mechanical find-replace once the loader contract
is stable — well-suited to a code-writing agent).

---

### Unit 4 — Migrate size-bin builders (30c, 30d)

**Files:**
- `scripts/R/3_instruments/30c_build_size_bin_mapping.R`
- `scripts/R/3_instruments/30d_build_sector_size_bin_mapping.R`

**Scope:**
- Replace direct reads with `load_firm_panel(..., instruments = character(0))` — these scripts
  don't use the instrument columns; they classify firms into size bins from `n_employees` and
  sector columns. Loading base-only yields the largest memory win here.

**Tests (manual):**
1. Size-bin mapping files output identical to pre-migration
2. Row counts match
3. Memory peak of 30c/30d drops (log `pryr::mem_used()` at start and peak)

**Dependencies:** Units 1 and 2.

**Execution target:** external-delegate.

---

### Unit 5 — Migrate diagnostics (9 scripts)

**Files:**
- `scripts/R/diagnostics/compare_prop2_reference_spec.R`
- `scripts/R/diagnostics/create_firm_sample.R`
- `scripts/R/diagnostics/diagnose_agg_first_stage_collapse.R`
- `scripts/R/diagnostics/diagnose_firm_instruments.R`
- `scripts/R/diagnostics/diagnose_proposition2_gap.R`
- `scripts/R/diagnostics/diagnose_sector_group_cell_support.R`
- `scripts/R/diagnostics/diagnose_size_bin_emp_concentration.R`
- `scripts/R/diagnostics/sector_taxonomy_diagnostics.R`
- `scripts/R/diagnostics/create_firm_sample.R` (already listed, dedup)

**Scope:**
- Identical migration pattern to Unit 3 / Unit 4
- Diagnostics that inspect FA/dFA distributions must pass the relevant instrument columns
  explicitly; those that don't touch instruments should pass `instruments = character(0)`

**Tests (manual):**
1. Each diagnostic's primary output (tex table, csv, or png) is byte-identical or
   numerically-identical to pre-migration run
2. Spot-check: `diagnose_firm_instruments.R` moments of FA_continuous match

**Dependencies:** Units 1 and 2. Can land after Units 3/4 (diagnostics are non-blocking for the
first-stage pipeline).

**Execution target:** external-delegate.

---

### Unit 6 — Retire legacy fat-file fallback

**Files:**
- `scripts/R/_utils/load_firm_panel.R`
- `scripts/R/4_regression_panels/42_build_firm_panel.R` (remove any lingering fat-file write)

**Scope:**
- After Units 3–5 ship and we have one clean run of the full pipeline against split files,
  remove the fallback branch in the loader and delete any vestigial fat-file outputs
- Update session log and `INSTRUCTIONS.md` reference section if firm panel output format is
  documented there

**Tests:**
1. Full pipeline reruns without warning
2. No code outside `load_firm_panel.R` references `firm_panel_for_regs*.fst` paths directly
   (grep check)

**Dependencies:** Units 1–5 all complete and verified.

**Execution target:** internal (deletion + verification, cheap).

## 6. Dependencies & Sequencing

```
Unit 1 (loader)  ──┐
                   ├──> Unit 2 (producer rewrite) ──> Units 3,4,5 (parallel) ──> Unit 6 (retire fallback)
                   ┘
```

- Unit 1 and Unit 2 must land before any consumer migrates — otherwise we have a window where
  consumers call a function that reads a file that doesn't exist
- Units 3, 4, 5 can run in parallel once Units 1–2 are merged (independent consumers)
- Unit 6 is a separate, later PR — gives us one full pipeline cycle to catch a missed consumer

## 7. Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Sparse projection drops a row that *should* be zero-fill but a consumer expects NA | High | Loader default is `zero_fill = TRUE`; consumers that want NA semantics pass `zero_fill = FALSE` and handle explicitly. Reviewed per-consumer in Units 3–5. |
| Downstream script missed in migration, still reads fat file directly | Medium | Unit 6 grep check; loader fallback during transition prevents silent failure |
| Sparse file is not actually sparse (most rows non-zero) | Medium | Unit 2 test #3 asserts `nrow(sparse) < nrow(base)`. If sparsity fails, abort refactor and explore Parquet/Arrow path instead. |
| Numerical drift in prop-2 equivalence test (`52b`) from join ordering | Medium | Set `setkey(base, firm_id, muni_id, year)` and `setkey(sparse, firm_id, muni_id, year)` before join. Left-join semantics guarantee row order. |
| `fst` column-selective read has unexpected cost on wide base file | Low | `fst` is columnar; documented behavior. Benchmark in Unit 1 test. |
| Downstream memory *increases* for consumers that load all 48 instruments | Low | Only `52` loads all 48; its pre-refactor memory is already the problem. Post-refactor its peak is bounded by its actual instrument subset. |

## 8. Requirements Traceability

- **From session log `2026-04-14_script42_memory_efficiency.md`**: "Step 4 peak RAM: expected
  ~12 GB reduction" was the Tier 1 target and was achieved *on paper*; residual 14 GB from
  48-column materialization is what this plan addresses.
- **From user**: *"The script should be very efficient and avoid operations that can be replaced
  by others more efficient ones that save memory or processing time and produce the same result"*
  — the split-file design reduces Step 4 peak allocation to base-size (~10 GB) from
  fat-file-size (~24 GB) with no change in numeric output.
- **From user**: *"The script run much faster, but the error is the same"* — confirms that
  runtime optimizations alone are insufficient; the structural change is required.

## 9. Verification Plan

Per-unit tests are listed above. Overall gate:

1. `42_build_firm_panel.R` completes full run (both baselines) on Windows 32 GB box
2. `51_firm_first_stage.R` produces first-stage table bit-identical to pre-refactor
3. `52_aggregated_firm_sector_first_stage.R` produces aggregated first-stage table identical
4. `52b_proposition2_equivalence.R` identity test passes to `1e-10`
5. All 9 diagnostics produce identical outputs
6. `grep -rn "firm_panel_for_regs.*\.fst" scripts/R/ | grep -v "_utils/load_firm_panel.R"`
   returns no matches after Unit 6

Score gate: coder-critic ≥ 80 per `quality.md` execution-phase threshold.

## 10. Open Questions (Deferred to Implementation)

- Exact sparsity ratio is unknown without running Unit 2 once. If sparse file is ≥ 50% of
  panel rows, the disk-footprint success criterion (§3.4) may require revisiting — fallback is
  to keep the fat file and pursue year-chunking instead.
- Whether `fst` base-file read with `columns = ...` on 44M rows × ~30 columns incurs
  non-trivial overhead per call. If it does, Unit 1 adds a session-level cache keyed by
  `(baseline_type, hash(columns))`. Default is no cache.

## 11. Status

- **Completed** — Units 1–6 implemented.
  - Unit 1: `load_firm_panel.R` (loader + `firm_panel_paths()`)
  - Unit 2: `42_build_firm_panel.R` Step 4 rewritten to emit split files
  - Unit 3: `51`, `52`, `52b` migrated to `load_firm_panel()`
  - Unit 4: `30c`, `30d` migrated to `load_firm_panel(..., instruments = character(0))`
  - Unit 5: 8 diagnostic scripts migrated
  - Unit 6: fallback removed from loader; `firm_panel_paths()` returns base + sparse only
