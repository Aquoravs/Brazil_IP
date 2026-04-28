---
title: "Implement Extensive-Margin Baseline Exposure, Aggregated First Stage, and Spec Selection"
type: feat
status: completed
date: 2026-03-22
origin: docs/prompts/2026_03_22_refactor_prompt.md
---

# Implement Extensive-Margin Baseline Exposure, Aggregated First Stage, and Spec Selection

## Overview

Four coordinated changes to the firm/sector first-stage pipeline:

1. **Task 1**: Add extensive-margin baseline exposure (`binary`) as a robustness variant for firm and sector instruments, plus corresponding exposure controls.
2. **Task 2**: New script 52 — aggregated firm→sector first stage (H_jmt on FA_bar with muni×year FE), with new Section 2.3.1 in regs.tex.
3. **Task 3**: Add `--specs` CLI argument to scripts 51 and 53 for selective specification execution.
4. **Task 4**: Add robustness framing language to regs.tex Sections 2.2 and 2.4.

## Task 1: Extensive-Margin Baseline Exposure

### What the paper specifies (regs.tex Section 2.1)

The **pooled-count** (current default) baseline is:

```
omega_fp = sum_s(L_fp_s) / sum_s(L_f_s)    over s in T_ell_t
```

The **extensive-margin** (binary) alternative is:

```
tilde_omega_fp = (1/|T_ell_t|) * sum_s 1(L_fp_s > 0)    over s in T_ell_t
```

This is the fraction of years in the pre-election window where firm f has *any* owner in party p. Key difference: `sum_p tilde_omega_fp` can exceed 1 (multi-party firms), unlike the share-based measure where `sum_p omega_fp <= 1`.

### Scope (includes exposure control updates, per user decision)

- Build `tilde_omega` in script 36 alongside existing `omega`
- Propagate to script 42 (firm panel) as a new instrument variant
- Build corresponding **extensive-margin exposure control**: `EC_binary = sum_p tilde_omega_fp` at the firm level, and `sum_p tilde_w_jmp` at the sector level
- Update regs.tex to document the exposure control definition properly (pooled-count and binary variants)
- Propagate to sector-level scripts (31, 33, 34) if sector-level extensive-margin instruments are needed

### Implementation

#### Phase 1A: Script 36 — Firm-level binary baselines

**File**: `BNDES/politicsregs/3_instruments/36_build_firm_level_instruments.R`

Current Step 1 computes `share_fp = L_fp / L_f` (pooled-count). Add a parallel computation:

```r
# Binary: 1(L_fp_s > 0) averaged over pre-election years
binary_baseline[, binary_fp_0 := mean(aff_count > 0), by = .(firm_id, party)]
```

Then in Steps 4-7, compute `FA_*_binary` and `dFA_*_binary` instruments using `binary_fp_0` instead of `share_fp_0`, following identical spreading and interaction logic.

**Output**: Save as additional columns in `firm_level_instruments.qs2` (or a separate `firm_level_instruments_binary.qs2` to avoid breaking existing consumers). Preferred approach: add `_binary` suffix columns to the existing file to keep a single merge path in script 42.

**Exposure control**: Compute `exposure_control_binary_f = sum_p binary_fp_0` per firm. This measures the total number of party-windows with any affiliated owner (can exceed 1). Save alongside instruments.

#### Phase 1B: Script 42 — Firm panel with binary instruments

**File**: `BNDES/politicsregs/4_regression_panels/42_build_firm_panel.R`

Merge the new `FA_*_binary` and `dFA_*_binary` columns from the updated instrument file. No new outcome variables needed — the binary exposure only changes the instrument, not the LHS.

#### Phase 1C: Sector-level binary baselines (scripts 31, 33, 34)

**Decision needed at implementation time**: If the sector-level extensive-margin instrument is required (for script 53 robustness), modify:
- Script 31: compute `binary_w_jmp = (1/|T|) * sum_s 1(any firm in (j,m) has owner in p at s)`
- Script 33: select binary baselines alongside pooled-count
- Script 34: build `Z_*_binary` and `dZ_*_binary` instruments

This can be deferred if the spec catalog for script 53 does not include a `binary` exposure dimension. The prompt's spec catalog for script 53 does not list an `exposure` dimension, so **sector-level binary baselines are deferred** unless explicitly requested.

#### Phase 1D: regs.tex updates

- Verify the exposure control definition in Section 2.3 accurately reflects the pooled-count formula: `EC_ell = sum_p w_jmp`
- Add a remark noting the extensive-margin exposure control variant: `EC_binary = sum_p tilde_omega_fp` (or `sum_p tilde_w_jmp` at sector level), noting it can exceed 1
- Cross-reference the extensive-margin baseline paragraph in Section 2.1

### Acceptance Criteria — Task 1

- [x] Script 36 computes both `share_fp_0` (pooled-count) and `binary_fp_0` (extensive-margin) baselines
- [x] `FA_*_binary` and `dFA_*_binary` instruments constructed with correct spreading/interaction logic
- [x] `exposure_control_binary_f` computed as `sum_p binary_fp_0`
- [x] Script 42 merges binary instrument columns into firm panel
- [x] Binary instruments satisfy support bounds: `FA_binary in [0, |parties|]` (wider than [0,1] since tilde_omega sums can exceed 1) — **verify this**: actually, `FA_binary = sum_p tilde_omega_fp * Align_mpt`, and `Align_mpt in {0,1}` while `tilde_omega_fp in [0,1]`, so `FA_binary in [0, sum_p 1] = [0, |parties|]` theoretically but practically bounded by the number of parties with any affiliation
- [x] regs.tex exposure control definition updated

---

## Task 2: Aggregated Firm→Sector First Stage (Script 52)

### What the paper specifies (regs.tex Section 2.5, eq:agg-ext)

Collapse the firm-level extensive-margin equation to (sector, muni, year):

**Outcome**:
```
H_jmt = (1 / N_jme_pre) * sum_f 1(BNDES_fmt > 0)    for f in F_pre(j,m,e)
```
The share of pre-election firm base receiving any BNDES credit in year t.

**Instrument**:
```
FA_bar_jmt = (1 / N_jme_pre) * sum_f FA_fmt    for f in F_pre(j,m,e)
```
The simple (unweighted) average of firm-level instruments within the pre-election firm base.

**Fixed effects**: muni×year (since averaged firm FE becomes a cell constant absorbed by muni×sector FE, and the firm equation already has muni×year FE).

**Regression**:
```
H_jmt = sum_ell lambda_ell * FA_bar_ell_jmt + gamma_jm + alpha_mt + u_jmt
```

### Pre-election firm base definition

`F_pre(j,m,e)` = set of firms in sector j, municipality m that appear in the baseline exposure window for election e. This is the set of firms with non-zero `omega_fp_0` (or equivalently, firms present in the RAIS data during the pre-election window `T_ell_t`). Since the baseline window is office-specific, the pre-election firm base may differ across tiers — but for the aggregated regression, use the union of firms in any tier's baseline window as the firm base.

**Practical implementation**: firms with any non-zero FA instrument in the firm panel are in the pre-election base. Filter `firm_panel_for_regs` to rows where at least one `FA_*` column is non-zero, then collapse.

### Implementation

#### Phase 2A: New script `5_estimation/52_aggregated_firm_sector_first_stage.R`

1. **Load** `firm_panel_for_regs.qs2` (or .fst for column-selective read)
2. **Filter** to pre-election firm base: rows where any `FA_*` is non-zero
3. **Collapse** to (cnae_section, muni_id, year):
   - `H_jmt = mean(has_bndes_fmt)` — share of pre-election firms with BNDES
   - `FA_bar_*_jmt = mean(FA_*)` — simple average of each FA instrument
   - `N_pre_jmt = .N` — count of pre-election firms (for diagnostics)
4. **Estimate** with fixest:
   ```r
   H_jmt ~ FA_bar_mayor + FA_bar_gov + FA_bar_pres | muni_id^cnae_section + muni_id^year
   ```
   Clustering: two-way by muni_id and cnae_section
5. **Output**: Save tables via `save_beamer_table()` to `output/muni_reg_tables/`

**Command-line args**: Accept `--sector-var` (forwarded from orchestrator) for grouped sectors.

#### Phase 2B: Register script 52 in orchestrator

**File**: `BNDES/politicsregs/run_politicsregs.R`

Already registered: `"52" = "5_estimation/52_aggregated_firm_sector_first_stage.R"` (done during renumbering). Verify the entry exists.

#### Phase 2C: Add Section 2.3.1 to regs.tex

**File**: `paper/regs.tex`

After the current Section 2.3 content, add a new subsection:

```latex
\subsection{Aggregated firm extensive margin}\label{sec:agg-ext-sector}

As a complementary exercise, we aggregate the firm-level extensive-margin
equation within each municipality-sector cell...
```

Present equation (eq:agg-ext) from Section 2.5, the three enumerated differences (outcome, weighting, FE structure), and note that this regression bridges the firm and sector pipelines.

**Do not move or delete existing Section 2.3 content.**

### Acceptance Criteria — Task 2

- [x] Script 52 exists and is registered in the orchestrator pipeline map
- [x] Correctly identifies the pre-election firm base from non-zero FA instruments
- [x] Collapses to (sector, muni, year) with simple averages (not owner-count-weighted)
- [x] Uses muni×sector + muni×year FE (not sector×year)
- [x] Two-way clustering by muni_id and sector
- [x] F-statistics via `fixest::wald(mod, keep = "^FA_bar_")$stat`
- [x] Output tables saved via `save_beamer_table()`
- [x] Section 2.3.1 added to regs.tex without deleting existing content
- [x] `Rscript run_politicsregs.R 52` works standalone

---

## Task 3: Spec Selection (`--specs`) for Scripts 51 and 52

### Interface

```bash
# Default: run baseline only
Rscript run_politicsregs.R 51

# Specific specs
Rscript run_politicsregs.R 51 -- --specs=baseline,changes,weighted

# All specs
Rscript run_politicsregs.R 51 -- --specs=all
```

The orchestrator (`run_politicsregs.R`) already forwards arguments after `--` to individual scripts. No orchestrator changes needed for argument forwarding.

### Script 51: Spec Catalog

#### Dimensions

| Dimension       | Options                         | Default          |
|-----------------|---------------------------------|------------------|
| margin          | `extensive`, `intensive`        | `extensive`      |
| exposure        | `pooled_count`, `binary`        | both             |
| weighting       | `unweighted`, `emp_weighted`    | `unweighted`     |
| baseline        | `cycle_specific`, `2002_fixed`  | `cycle_specific` |
| alignment       | `coalition`, `party`            | `coalition`      |
| time_variation  | `levels`, `changes`             | `levels`         |
| sample          | `all_firms`, `single_muni`      | `all_firms`      |

**Note**: Default margin is `extensive` (per user clarification). Default exposure is `both` (pooled_count + binary).

#### Named Bundles

| Name             | Description                                                                              |
|------------------|------------------------------------------------------------------------------------------|
| `baseline`       | extensive margin, both exposures (pooled_count + binary), unweighted, cycle_specific, coalition, levels, all_firms |
| `changes`        | same as baseline but time_variation = changes (dFA instruments)                          |
| `weighted`       | same as baseline but weighting = emp_weighted                                            |
| `party`          | same as baseline but alignment = party                                                   |
| `fixed_baseline` | same as baseline but baseline = 2002_fixed                                               |
| `single_muni`    | same as baseline but sample = single_muni                                                |
| `intensive`      | same as baseline but margin = intensive                                                  |
| `all`            | run all of the above                                                                     |

Each named bundle expands to 2 regressions (one per exposure type) × 9 instrument combos = 18 regressions. The `all` bundle expands to 7 × 18 = 126 regressions.

#### Implementation (script 51)

1. **Parse** `--specs` from `commandArgs(trailingOnly = TRUE)`:
   ```r
   specs_arg <- grep("^--specs=", args, value = TRUE)
   if (length(specs_arg) == 0) {
     requested_specs <- "baseline"
   } else {
     requested_specs <- strsplit(sub("^--specs=", "", specs_arg), ",")[[1]]
   }
   if ("all" %in% requested_specs) requested_specs <- names(SPEC_CATALOG)
   ```

2. **Define** `SPEC_CATALOG` as a named list. Each entry is a list of dimension values:
   ```r
   SPEC_CATALOG <- list(
     baseline = list(margin = "extensive", exposure = c("pooled_count", "binary"),
                     weighting = "unweighted", baseline = "cycle_specific",
                     alignment = "coalition", time_variation = "levels",
                     sample = "all_firms"),
     changes = list(..., time_variation = "changes"),
     ...
   )
   ```

3. **Expand** each requested spec into a grid of regression configurations. Each configuration maps to a formula, sample mask, and weighting flag.

4. **Run** regressions using the existing formula-caching and sample-batching infrastructure in script 51. The current code already has the machinery for all these dimensions — the refactor wraps the existing logic under the spec catalog.

5. **Output**: Each spec bundle produces its own table file(s). Print a summary table at the end with coefficient, SE, F-stat for each spec.

**Key refactoring note**: Script 51 currently runs *everything* (all tables FC-1 through FC-9). The refactor reorganizes the existing code so that each table maps to one or more named specs. The `baseline` spec corresponds to FC-1 (levels, extensive, coalition, cycle-specific). Running `--specs=all` reproduces the current full output.

### Script 53: Spec Catalog

#### Dimensions

| Dimension        | Options                                      | Default              |
|------------------|----------------------------------------------|----------------------|
| outcome          | `levels` (s_mjt), `changes` (delta_s_mjt)    | `levels`             |
| instrument       | `levels` (Z), `changes` (dZ)                 | `levels`             |
| baseline         | `cycle_specific`, `2002_fixed`               | `cycle_specific`     |
| alignment        | `coalition`, `party`                         | `coalition`          |
| fe               | `mxj_jxt`, `mxj_mxt`                        | `mxj_jxt`            |
| exposure_control | `yes`, `no`                                  | `yes`                |

**Note**: The `--sector-var` flag (already implemented) continues to work alongside `--specs`.

#### Named Bundles

| Name             | Description                                                    |
|------------------|----------------------------------------------------------------|
| `baseline`       | levels outcome + levels instrument, cycle_specific, coalition, mxj_jxt FE, with exposure control |
| `changes`        | changes outcome + changes instrument (current Table 1 behavior) |
| `fe_muni_year`   | same as baseline but fe = mxj_mxt (current Table 2)           |
| `party`          | same as baseline but alignment = party (current Table 4)       |
| `no_controls`    | same as baseline but exposure_control = no (current Table 5)   |
| `fixed_baseline` | same as baseline but baseline = 2002_fixed (current Table 6)   |
| `all`            | run all of the above                                           |

#### Implementation (script 53)

Same parsing pattern as script 51. Map named specs to the existing table-generation functions (`run_six_combos()` with appropriate FE, control, and instrument arguments).

### Acceptance Criteria — Task 3

- [x] `Rscript run_politicsregs.R 51` (no `--specs`) runs baseline only (2 exposure × 9 combos = 18 regressions)
- [x] `--specs=all` runs all named specs without error
- [x] `--specs=changes` runs only the changes specification
- [x] `--specs=baseline,changes` runs both baseline and changes
- [x] Output tables saved to `output/firm_reg_tables/` with spec-specific filenames
- [x] F-statistics use `fixest::wald()`, not `summary()$fstatistic`
- [x] Clustering: firm_id + muni_id (script 51), muni_id + sector (script 53)
- [x] `--sector-var` still works in script 53 alongside `--specs`
- [x] Summary table printed to console at end of each script run

---

## Task 4: regs.tex Robustness Framing

### Changes

#### Section 2.2 (Firm-level, Changes)

Add at the beginning of the subsection, before the first `\paragraph`:

```latex
As a robustness exercise, we also estimate specifications that exploit only the
variation induced by political turnover at inauguration years, rather than the
cross-sectional differences in alignment status used in the primary levels
specification.
```

#### Section 2.4 (Sector-level, Changes)

Add at the beginning of the subsection, before the first `\paragraph`:

```latex
The sector-level analogue of the firm-level changes specification
(Section~\ref{sec:firm-changes}) serves as the corresponding robustness check:
it tests whether political turnover also reallocates BNDES credit across
sectors, exploiting only inauguration-year variation rather than the
cross-sectional alignment differences used in the levels specification above.
```

### Acceptance Criteria — Task 4

- [x] Section 2.2 opens with robustness framing sentence
- [x] Section 2.4 opens with parallel framing sentence referencing Section 2.2
- [x] No equations or existing content deleted
- [x] LaTeX compiles without errors
- [x] Section numbering unchanged

---

## Implementation Sequence

The tasks have dependencies:

```
Task 1 (binary baselines)
  └→ Phase 1A: script 36 (build binary instruments)
  └→ Phase 1B: script 42 (merge into firm panel)
  └→ Phase 1D: regs.tex exposure control docs

Task 2 (aggregated regression) — depends on Task 1B (needs firm panel with instruments)
  └→ Phase 2A: script 54 (new script)
  └→ Phase 2B: orchestrator registration
  └→ Phase 2C: regs.tex Section 2.3.1

Task 3 (spec selection) — depends on Task 1B (binary exposure needs to be in panel)
  └→ Phase 3A: script 51 refactor (spec catalog + --specs parsing)
  └→ Phase 3B: script 53 refactor (spec catalog + --specs parsing)

Task 4 (regs.tex framing) — independent
  └→ Phase 4A: edit Sections 2.2 and 2.4
```

**Recommended order**: Task 4 → Task 1 → Task 2 → Task 3

Task 4 is a simple text edit with no code dependencies. Task 1 must precede Tasks 2 and 3 because binary instruments must exist before spec selection can reference them and before the aggregated regression can use them. Task 2 can run in parallel with Task 3 after Task 1 completes.

---

## Technical Considerations

### Performance
- Script 52's collapse is a simple `data.table` aggregation — fast even on the full firm panel (~2M rows)
- The spec catalog in script 51 must avoid loading `2002_fixed` panel data unless specs requiring it are requested (lazy loading)
- Binary instrument columns add ~12 columns to the firm panel (6 FA_binary + 6 dFA_binary for single-tier; more with interactions). Memory impact is modest.

### Naming conventions for binary instruments
- Firm-level: `FA_mayor_coalition_binary`, `FA_gov_coalition_binary`, etc.
- Changes: `dFA_mayor_coalition_binary`, etc.
- Exposure control: `exposure_control_binary_mayor`, etc. (one per tier, since pre-election windows differ)
- Aggregated: `FA_bar_mayor_coalition`, `FA_bar_gov_coalition`, etc. (no `_binary` suffix; the aggregation is always over the default pooled-count instruments unless spec says otherwise)

### Support bounds for binary instruments
- `tilde_omega_fp in [0, 1]` per party (fraction of years with any affiliation)
- `sum_p tilde_omega_fp` can exceed 1 (multi-party firms)
- `FA_binary = sum_p tilde_omega_fp * Align_mpt` is in `[0, K]` where K = number of aligned parties (vs. `[0, 1]` for pooled-count)
- Validation checks in scripts 36 and 42 must use wider bounds for binary instruments

### Backwards compatibility
- Without `--specs`, scripts 51 and 53 run `baseline` only — this is a **behavior change** from the current default of running everything
- The `--unweighted` flag in script 51 should still work and is equivalent to `--specs=baseline` with `weighting=unweighted` override. For backwards compatibility, keep `--unweighted` as a standalone flag that modifies the weighting dimension of whatever specs are requested.

---

## Sources

- **Prompt**: `docs/prompts/2026_03_22_refactor_prompt.md`
- **Paper specification**: `paper/regs.tex` Sections 2.1 (extensive-margin baseline, lines 112-119), 2.2 (firm changes), 2.3 (sector levels), 2.4 (sector changes), 2.5 (aggregation, eq:agg-ext)
- **Instrument construction notes**: `docs/shift_share.md`
- **Current scripts**: `36_build_firm_level_instruments.R`, `42_build_firm_panel.R`, `51_firm_first_stage.R`, `52_sector_first_stage.R`, `run_politicsregs.R`
- **Table helper**: `_utils/beamer_tables.R` (`save_beamer_table()`)
