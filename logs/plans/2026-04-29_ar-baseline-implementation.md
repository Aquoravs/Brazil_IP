---
status: APPROVED
date: 2026-04-29
author: Claude (planner)
phase: exploration
related:
  - logs/strategy/strategy_memo_ar_test.md
  - docs/research_state.md
  - scripts/R/4_regression_panels/41_build_muni_panel.R
  - scripts/R/5_estimation/54_sector_second_stage.R
  - scripts/R/diagnostics/audit_41_muni_panel.R
target_artifact: explorations/anderson_rubin/ar_baseline.R
mode: simplified (workflow.md §2 — Simplified Mode for R Scripts / Explorations)
user_overrides_to_strategy_memo:
  - Primary outcome is log_gdp (not log_gdp_pc). log_gdp_pc demoted to R4 sensitivity. (USER-MANDATED 2026-04-29.)
  - Primary spec uses NO controls — no muni FE, no year FE, no covariates. (USER-MANDATED 2026-04-29.) The strategy memo's standard two-way FE spec is C1 (first rung of the controls ladder), not the primary.
  - K = 4 mayor-only is retained as primary per the strategy memo §3 (NOT overridden). Tier extension to K = 8 / K = 12 is the R3 sensitivity ladder.
---

# Plan: Anderson-Rubin Baseline Implementation

## Status

**DRAFT** — awaiting user approval.

## Goal

Implement the **pooled Anderson-Rubin (AR) test of H0: BNDES sectoral allocation
has no first-order effect on municipal GDP**, per the approved strategy memo
(`logs/strategy/strategy_memo_ar_test.md`). The deliverable is a standalone R
script in `explorations/anderson_rubin/ar_baseline.R` that runs the primary
spec, the R0a / R0b / R1 / R2 / R3 / R4 sensitivities, the grouped AR
heterogeneity diagnostics, and an F1 / F2 / F7 falsification battery, then
emits a one-row-per-spec results CSV plus a bare-tabular LaTeX fragment.

The AR test is operationally a cluster-robust Wald test on the reduced-form
regression `log(GDP_mt) ~ Z_jmt | muni_id + year` clustered at `muni_id`
(strategy memo §2). No first stage. No 2SLS. The test reuses the
`fixest::feols + fixest::wald` machinery already wired in script 54.

## Approach

The pipeline produces a `policy_block` taxonomy (4 macros: Agro / Ind / Infra /
Serv) that supersedes the `bndes_sector` taxonomy referenced by the strategy
memo's Section 7 BLOCKER. **Verification reads (Phase 0 below) confirm this is
already wired through scripts 30e → 31 → 32 → 33 → 34 → 35 → 41 end-to-end.**
Panel B emits the AR-relevant instruments and sector-specific exposure
controls in wide format, prefixed `ar_`.

The single missing piece is the **muni-total** exposure control
EC^ell_mt = sum_j sum_p w^ell_jmp,t (the R0a Tier 1 sensitivity in the
strategy memo §3.1). Panel B currently has only the sector-specific wide form
(R0b). Adding muni-total EC is a row-sum operation across the existing
`ar_exposure_control_*_<sector>` columns within (muni, year) — purely additive,
no upstream rebuild required.

After the script-41 patch, the new exploration script consumes Panel B
directly, runs the spec grid via a `feols` + `wald` helper, and writes
results. Simplified-mode loop (workflow.md §2): write → run → check
outputs → score >= 80 → done.

## Files to Modify

| File | Change | Why |
|---|---|---|
| `scripts/R/4_regression_panels/41_build_muni_panel.R` | Add muni-total EC row-sum block in Step 5b after the existing wide-pivot of `ar_exposure_control_*_<sector>` (lines 736–742). Adds `ec_total_<infix>_<tier>_<baseline>` columns (24 new columns for the policy_block taxonomy). | Strategy memo §3.1 R0a Tier 1 sensitivity requires a single muni-level scalar EC per (tier, weight, baseline). The sector-specific R0b form already exists. |
| `scripts/R/diagnostics/audit_41_muni_panel.R` | Add two checks: (a) `ec_total_*` columns exist when `--sector-var=policy_block`; (b) `ec_total_<tier>_<baseline>` numerically equals row-sum of the four `ar_exposure_control_<tier>_<baseline>_<sector>` columns within muni-year (tolerance 1e-9). | INV check 4 in `docs/research_state.md` §7 demands EC variation; numerical identity check guards against silent row-mismatch on rebuild. |

## Files to Create

| File | Purpose |
|---|---|
| `explorations/anderson_rubin/README.md` | Goal, hypotheses, success criteria, status. From `templates/exploration-readme.md`. |
| `explorations/anderson_rubin/SESSION_LOG.md` | Incremental progress log. From `templates/session-log.md`. |
| `explorations/anderson_rubin/ar_baseline.R` | The AR test script (see §3 below for the spec grid). |
| `explorations/anderson_rubin/output/` | Empty directory at creation time; populated by `ar_baseline.R`. |

## Files NOT to Modify

Per the prompt's constraint, scripts **31, 32, 34, 35** are NOT modified —
verification (Phase 0) confirms `policy_block` is already wired through them.
Script 33 was not read directly but is upstream of script 34 and the
`baseline_sector_weights_policy_block.qs2` file is consumed at script 34 line
87 — so the wiring is empirically intact. Script 54 is NOT touched; the AR test
is a separate exploration, not a re-parameterization of 54.

---

## Verification Reads (Phase 0 — Pre-Implementation Findings)

These were performed during planning; the implementer can take them as given.

### `policy_block` is wired end-to-end

| Script | `--sector-var=policy_block` flag | Output file (policy_block) |
|---|---|---|
| 30e (`30e_build_policy_block_mapping.R`) | n/a (defines the crosswalk) | `policy_block_mapping.qs2` |
| 31 (`31_build_sector_exposure_weights.R`) | line 120: validated; line 154–166: branch | `sector_exposure_weights_owner_policy_block.qs2`, `..._worker_policy_block.qs2` |
| 32 (`32_build_alignment_shocks.R`) | sector-agnostic (muni × party × year only) — no flag needed | `alignment_shocks.qs2` |
| 33 (`33_select_baseline_weights.R`) | (not read; downstream of 31, consumed at script 34 line 87) | `baseline_sector_weights_policy_block.qs2` (verified by 34's `file.exists` guard) |
| 34 (`34_build_shift_share_instruments.R`) | line 69: validated; line 86–91: branch | `shift_share_instruments_policy_block.qs2`, `shift_share_instruments_sector_policy_block.qs2`, `exposure_control_sector_policy_block.qs2` |
| 35 (`35_build_credit_shares.R`) | line 82: validated; line 102–110: branch; line 161–169: filter | `bndes_credit_shares_policy_block.qs2` |
| 41 (`41_build_muni_panel.R`) | line 72: validated; line 94–101: branch | `muni_sector_panel_policy_block.qs2`, `muni_panel_for_regs_policy_block.qs2` |

**Conclusion:** the strategy memo's Section 7 BLOCKER (`bndes_sector` not
wired) is RESOLVED — `policy_block` (4 sectors: Agro, Ind, Infra, Serv;
section K dropped because BNDES on-lends through it; sections O, T, U near-zero
BNDES) supersedes `bndes_sector` and is the primary AR-test taxonomy. **No
code changes needed in scripts 30e / 31 / 32 / 33 / 34 / 35.**

### Current EC granularity in Panel B (from script 41 Step 5b reading)

Panel B (`muni_panel_for_regs_policy_block.qs2`) already exposes
**sector-specific** exposure-control wide columns in the `ar_` namespace:

```
ar_exposure_control_<infix>_<tier>_<baseline>_<sector>
```

with `infix ∈ {"" (owner_count), "emp_", "firm_", "binary_"}`,
`tier ∈ {"" (all-tier), "mayor_", "gov_pres_"}`,
`baseline ∈ {"cycle_specific", "2002_fixed"}`,
`sector ∈ {"Agro", "Ind", "Infra", "Serv"}`.

For the 4-sector policy_block taxonomy this is 24 EC stems × 4 sectors =
**96 sector-specific wide EC columns** — the R0b raw material.

The corresponding **muni-total** EC stems (sum across sectors)
`ec_total_<infix>_<tier>_<baseline>` are **NOT present**. This is the only
gap.

### Panel B AR-instrument naming pattern (verified from script 41 lines 720–733)

```
ar_<Z|dZ>_<weight_infix>_<tier>_<align>_<baseline>_<sector>
```

with `weight_infix ∈ {"" (owner), "emp_", "firm_", "binary_"}`,
`tier ∈ {"mayor", "gov", "pres"}`,
`align ∈ {"party", "coalition"}`,
`baseline ∈ {"cycle_specific", "2002_fixed"}`,
`sector ∈ {"Agro", "Ind", "Infra", "Serv"}`.

**Example primary spec column names (mayor / coalition / cycle / levels /
owner-count, K = 4 = 4 sectors × 1 tier):**

```
ar_Z_mayor_coalition_cycle_specific_Agro
ar_Z_mayor_coalition_cycle_specific_Ind
ar_Z_mayor_coalition_cycle_specific_Infra
ar_Z_mayor_coalition_cycle_specific_Serv
```

These are **ready for use today** once Panel B is rebuilt with `--sector-var=policy_block`.

**Tier-asymmetry note (relevant for R3 K = 8 / K = 12 sensitivities).**
Upstream scripts 33 / 34 partition tiers into **`mayor`** and **`gov_pres`**
(governor and president collapsed into one tier for the baseline weights and
the `exposure_control_*` columns). The instruments themselves are **NOT**
collapsed — `Z` and `dZ` columns split out `mayor`, `gov`, `pres` separately.
So R3 K = 12 (mayor + gov + pres) uses 12 distinct instrument columns but
matches against only **2 muni-total EC scalars** under R0a
(`ec_total_mayor_<baseline>` and `ec_total_gov_pres_<baseline>`), not 3. Same
asymmetry for R0b. The K = 4 mayor-only primary spec sidesteps this
asymmetry entirely.

---

## Ordered Implementation Steps

### Step 1. Patch `scripts/R/4_regression_panels/41_build_muni_panel.R`

**Where.** Step 5b, immediately after the existing `for (cc in ctrl_sec_cols)`
loop that builds `ar_exposure_control_*_<sector>` (line 738–742 in the current
file).

**What.** Insert a new block that row-sums the wide EC columns within
muni-year to produce muni-total EC scalars. This is purely a derived computation
on Panel B itself — no upstream rebuild is triggered.

**Pseudocode (to be written verbatim, plus a `cat()` diagnostic):**

```r
# --- Step 5b': Build muni-total exposure controls (row-sum across sectors) ----
# R0a sensitivity: EC^ell_mt = sum_j sum_p w^ell_jmp,t. Row-sum the existing
# ar_exposure_control_*_<sector> columns; one ec_total_* column per (infix,
# tier, baseline) stem. See logs/strategy/strategy_memo_ar_test.md §3.1.

cat("\n  Building muni-total exposure controls (sum across sectors)...\n")
ec_total_added <- character(0)
for (cc in ctrl_sec_cols) {
  ar_cols <- paste0("ar_", cc, "_", sec_ar)
  ar_cols <- intersect(ar_cols, names(panel_b))
  if (!length(ar_cols)) next
  total_col <- sub("^exposure_control", "ec_total", cc)
  panel_b[, (total_col) := rowSums(.SD, na.rm = TRUE), .SDcols = ar_cols]
  ec_total_added <- c(ec_total_added, total_col)
}
cat(sprintf("  Added %d muni-total EC columns (sample: %s)\n",
            length(ec_total_added),
            paste(head(ec_total_added, 4), collapse = ", ")))
```

**Naming convention.** `ec_total_<infix>_<tier>_<baseline>` where the infix /
tier / baseline triplet is identical to that of the source
`exposure_control_*` column in script 34. For policy_block the resulting
column names are 24 in total, including (selected examples for the AR-test
primary battery):

- `ec_total_mayor_cycle_specific` (R0a primary — mayor tier, owner-count weight, cycle baseline)
- `ec_total_gov_pres_cycle_specific` (R0a for mayor+gov / mayor+gov+pres tiers)
- `ec_total_mayor_2002_fixed` (R0a + R2 combined — mostly redundant after FE absorption; see strategy memo §3.1)
- `ec_total_emp_mayor_cycle_specific` (R0a under emp-weighted variant)
- `ec_total_firm_mayor_cycle_specific`, `ec_total_binary_mayor_cycle_specific`

**Drop list.** None — `ec_total_*` columns must be retained in the saved
panel. Verify the existing `panel_b_drop` list (line 910) does not match
`ec_total_*` (it does not — patterns are disjoint).

**Verification (do all of these in one Rscript run after the patch):**
- Rebuild: `Rscript scripts/R/run_politicsregs.R 41 -- --sector-var=policy_block`
- Quick sanity: load `muni_panel_for_regs_policy_block.qs2` and confirm
  `length(grep("^ec_total_", names(panel_b))) == 24`.
- Numerical identity:
  `panel_b[, abs(ec_total_mayor_cycle_specific - (ar_exposure_control_mayor_cycle_specific_Agro + ar_exposure_control_mayor_cycle_specific_Ind + ar_exposure_control_mayor_cycle_specific_Infra + ar_exposure_control_mayor_cycle_specific_Serv))]`
  should be < 1e-9 for every row.

### Step 2. Patch `scripts/R/diagnostics/audit_41_muni_panel.R`

**Where.** After the existing `if (!is.null(d$muni_panel_for_regs))` block
(line 160).

**What.** Two new checks, gated on `SECTOR_VAR == "policy_block"` (the new
columns only ship for this taxonomy in the current AR-test implementation):

```r
# Audit: muni-total EC presence and identity (policy_block only)
if (SECTOR_VAR == "policy_block" && !is.null(d$muni_panel_for_regs)) {
  panel_b <- d$muni_panel_for_regs
  ec_total_cols <- grep("^ec_total_", names(panel_b), value = TRUE)
  add_check("structure", "muni_panel_for_regs", "ec_total_columns_present",
            length(ec_total_cols) >= 24,
            sprintf("Found %d ec_total_* columns (expected 24 for policy_block)",
                    length(ec_total_cols)))

  # Numerical identity: ec_total = sum of ar_exposure_control_*_<sector>
  max_diff <- 0
  bad_stem <- character(0)
  sec_ar <- c("Agro", "Ind", "Infra", "Serv")
  for (tot in ec_total_cols) {
    cc <- sub("^ec_total", "exposure_control", tot)
    parts <- paste0("ar_", cc, "_", sec_ar)
    parts <- intersect(parts, names(panel_b))
    if (!length(parts)) next
    diffs <- panel_b[[tot]] - rowSums(panel_b[, ..parts], na.rm = TRUE)
    md <- max(abs(diffs), na.rm = TRUE)
    if (is.finite(md) && md > max_diff) max_diff <- md
    if (is.finite(md) && md > 1e-9) bad_stem <- c(bad_stem, tot)
  }
  add_check("identity", "muni_panel_for_regs", "ec_total_equals_sector_sum",
            length(bad_stem) == 0,
            sprintf("max|ec_total - sum(ar_exposure_control_*_<sector>)| = %.2e; failing stems: %s",
                    max_diff, paste(head(bad_stem, 3), collapse = ", ")))
}
```

**Verification:** `Rscript scripts/R/diagnostics/audit_41_muni_panel.R --sector-var=policy_block`
should report all checks PASS.

### Step 3. Create exploration scaffolding

```
explorations/anderson_rubin/
├── README.md          # from templates/exploration-readme.md, customized
├── SESSION_LOG.md     # from templates/session-log.md, initial entry
├── ar_baseline.R      # the AR script (Step 4)
└── output/            # populated by ar_baseline.R
```

`README.md` content (filled-in template):
- **Goal:** Pooled Anderson-Rubin test of H0: BNDES sectoral reallocation has no first-order GDP effect, using mayor alignment shift-share instruments at policy_block (4 sectors) granularity. K = 4 in the primary; tier ascent (K = 8 / K = 12) is the R3 sensitivity ladder. See `logs/strategy/strategy_memo_ar_test.md`.
- **Status:** IN PROGRESS (started 2026-04-29).
- **Primary spec (user-set 2026-04-29):** `log_gdp ~ ar_Z_mayor_coalition_cycle_specific_<Agro|Ind|Infra|Serv>` with **no controls** (no FE, no covariates), vcov = ~muni_id, owner-count weights. K = 4. Controls ladder C1 / C2 / C3 / C4 add FE then EC then employment as sensitivities.
- **Hypotheses to test:** (1) AR rejects under K = 4 no-controls primary; (2) result survives the controls ladder (C1 FE only; C2 FE + R0a muni-total EC; C3 FE + R0b sector-specific EC); (3) result survives R2 (2002-fixed baseline); (4) tier ascent R3 (K = 8 mayor+gov, K = 12 mayor+gov+pres) sharpens or sustains the result; (5) F1 transfers placebo does not reject; (6) F2 lead-instruments placebo does not reject; (7) F7 pre-period balance does not reject.
- **Success criteria:** primary K = 4 no-controls AR returns finite F-stat, p-value, df1, df2; output CSV / TeX produced; quality score >= 80; no script errors.

`SESSION_LOG.md`: opening entry with Objective, Status: IN PROGRESS, and a
"Plan approved on 2026-04-29; entering implementation" line.

### Step 4. Write `explorations/anderson_rubin/ar_baseline.R`

**Skeleton (in order):**

```r
# ar_baseline.R — Pooled Anderson-Rubin test of BNDES sectoral allocation H0: beta = 0
# See logs/strategy/strategy_memo_ar_test.md and explorations/anderson_rubin/README.md.

# 1. Packages (top of file, per INV-15)
suppressPackageStartupMessages({
  library(data.table); library(fixest); library(qs2); library(here)
})

# 2. Seed (only if any stochastic step is added; F2/F4 placebos may use it)
set.seed(20260429)  # INV-14

# 3. Paths via here::here (no absolute paths, INV-16)
panel_path <- here::here("data", "processed", "muni_panel_for_regs_policy_block.qs2")
out_dir    <- here::here("explorations", "anderson_rubin", "output")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# 4. Load Panel B; verify policy_block sectors
dt <- qs_read(panel_path); setDT(dt)
dt <- dt[!is.na(log_gdp) & is.finite(log_gdp)]   # USER: log_gdp primary
SECTORS <- c("Agro", "Ind", "Infra", "Serv")     # policy_block
TIERS_PRIMARY <- c("mayor")                      # K=4 primary (memo §3 + USER)

# 5. Helpers
#   - pick_ar_iv(tier, align, baseline, weight, time_var) -> character(K) column names
#   - ar_test(formula, data, vcov_var) -> list(F, p, df1, df2, n, rsq_within)
#   - run_spec(spec_row) -> data.table row aggregating identifiers + AR result

# 6. Spec grid (one row per spec; primary + variants + sensitivities)
spec_grid <- CJ(
  tier      = c("mayor", "mayor_gov", "mayor_gov_pres"),     # primary first (K=4)
  align     = c("coalition"),                                # party as future extension
  baseline  = c("cycle_specific", "2002_fixed"),
  weight    = c("owner", "emp", "firm", "binary"),
  time_var  = c("Z", "dZ"),
  outcome   = c("log_gdp", "log_gdp_pc"),                    # primary first; log_gdp_pc = R4
  controls  = c("none", "FE", "FE_R0a", "FE_R0b", "FE_emp")  # USER ladder; "none" = primary
)
# Mark primary (USER: K=4 mayor, log_gdp, owner, coalition, cycle, levels, NO controls)
spec_grid[, is_primary := tier == "mayor" & align == "coalition" &
                          baseline == "cycle_specific" & weight == "owner" &
                          time_var == "Z" & outcome == "log_gdp" &
                          controls == "none"]
# Mark Tier 1 sensitivities (R0a, R0b, R1, R2, R3, R4)
# (kept in same grid; downstream filtering not strictly necessary)

# 7. Run primary + variants; collect results
results <- spec_grid[, run_spec(.SD), by = seq_len(nrow(spec_grid))]
fwrite(results, file.path(out_dir, "ar_results.csv"))

# 8. Bare-tabular LaTeX fragment (per content-standards.md INV-13)
#    Columns: Spec | Tier | Weight | Baseline | LHS | EC | K | F | p | N
write_results_tex(results[is_primary | tier == "mayor"],   # focus rows
                  file.path(out_dir, "ar_results.tex"))

# 9. Grouped AR (heterogeneity diagnostic)
state_results    <- run_grouped_ar(dt, by_var = "state_id")        # 27 groups
quartile_results <- run_grouped_ar(dt, by_var = "bndes_quartile")  #  4 groups
fwrite(state_results,    file.path(out_dir, "ar_grouped_state.csv"))
fwrite(quartile_results, file.path(out_dir, "ar_grouped_quartile.csv"))

# 10. Falsification F1 / F2 / F7
falsif_results <- rbindlist(list(
  run_F1_transfers(dt),
  run_F2_lead_instruments(dt, lead = 4L),
  run_F7_pre_period_balance(dt)
))
fwrite(falsif_results, file.path(out_dir, "ar_falsification.csv"))
```

**Spec grid — primary specification (USER-MANDATED):**

```
Outcome:    log_gdp                      # USER: was log_gdp_pc; demoted to R4
Instruments (K = 4, 4 sectors × 1 tier):
  ar_Z_mayor_coalition_cycle_specific_{Agro, Ind, Infra, Serv}
FE:         NONE                         # USER: no controls in primary
Covariates: NONE
Cluster:    muni_id                      # cluster-robust SE on the panel
```

`feols`/`wald` invocation for the **no-controls primary**:

```r
fml <- as.formula(
  paste0("log_gdp ~ ", paste(z_cols, collapse = " + "))
)
m   <- fixest::feols(fml, data = dt, vcov = ~muni_id)
ar  <- fixest::wald(m, keep = "^ar_Z_")  # cluster-robust Wald = AR statistic
```

For the C1 sensitivity (FE-only, matching the strategy memo's standard form),
the formula appends `| muni_id + year`. For C2 / C3 (FE + EC), the EC columns
join the RHS as additional regressors.

**Variants to enumerate in `spec_grid`:**

| Axis | Levels | Notes |
|---|---|---|
| **Controls** (USER) | **none (primary)**; FE only (C1); FE + R0a muni-total EC (C2); FE + R0b sector-specific EC (C3); FE + log total employment (C4, advisory — bad-control risk per memo §6) | New axis. Primary has no FE, no covariates. C1 is the strategy memo's standard form. |
| Tier | mayor (K=4, primary); mayor+gov (K=8, R3a); mayor+gov+pres (K=12, R3b) | Tier ascent is the R3 sensitivity ladder (does power rise with more tiers?) |
| Align | coalition (primary); party (deferred — easy add) | |
| Baseline | cycle_specific (primary); 2002_fixed (R2 sensitivity) | 2002_fixed under muni FE makes sector-specific EC redundant — see strategy memo §3.1 |
| Weight | owner_count (primary); emp; firm; binary | weight battery |
| Time-variation | Z (levels, primary); dZ (changes, R1 sensitivity) | dZ has fewer non-zero obs, expected lower power |
| Outcome | log_gdp (primary, USER); log_gdp_pc (R4 sensitivity) | log_gdp avoids population-denominator measurement error; under muni FE the two differ only by log(pop_mt), which is largely absorbed if population grows at a stable muni-specific rate |

**Controls-ladder column choices for the K = 4 mayor primary spec (must match
Step 1 column names):**

```r
# Primary: no controls
ctrl_primary <- character(0)

# C1: FE only (muni FE + year FE attached via fixest's "| muni_id + year" syntax,
#     not as covariates)
fe_C1 <- "muni_id + year"

# C2: FE + R0a (muni-total EC) — one scalar matching the mayor tier
ctrl_C2 <- "ec_total_mayor_cycle_specific"

# C3: FE + R0b (sector-specific EC) — four sector EC columns
ctrl_C3 <- paste0("ar_exposure_control_mayor_cycle_specific_", SECTORS)

# C4 (advisory): FE + log total employment — bad-control concern per memo §6 / §10
ctrl_C4 <- "log_total_employment"
```

For R3 K = 8 (mayor + gov) and K = 12 (mayor + gov + pres), C2 expands to
include `ec_total_gov_pres_cycle_specific` and C3 expands to include the four
`ar_exposure_control_gov_pres_cycle_specific_<sector>` columns. The K = 12
extension still uses only **2 muni-total EC scalars** (mayor + gov_pres), not
3 — see Tier-asymmetry note above.

**To avoid combinatorial explosion**, the implementer should run the full
controls ladder (none / C1 / C2 / C3) only on the **owner-count, K = 4 mayor
primary path** (coalition / cycle / Z / log_gdp). Each tier-ascent sensitivity
(K = 8, K = 12) gets the controls ladder rerun. Other weight variants (emp /
firm / binary) get the primary no-controls row + the C1 FE-only row for
comparison. This yields a tractable results table (roughly 25–50 rows).

**Output table schema (`ar_results.csv`):**

| Column | Type | Note |
|---|---|---|
| `spec_id` | character | e.g. `primary`, `C1_FE`, `C2_FE_R0a`, `C3_FE_R0b`, `R1_dZ`, `R3a_mg`, `R3b_mgp`, `weight_emp`, ... |
| `tier` | character | `mayor` / `mayor_gov` / `mayor_gov_pres` |
| `align` | character | |
| `baseline` | character | |
| `weight` | character | |
| `time_var` | character | `Z` or `dZ` |
| `outcome` | character | |
| `controls` | character | `none` (primary) / `FE` / `FE_R0a` / `FE_R0b` / `FE_emp` |
| `K` | integer | number of instruments |
| `n_obs` | integer | regression N |
| `n_clusters` | integer | unique muni_id |
| `f_stat` | numeric | AR F statistic |
| `p_value` | numeric | |
| `df1` | integer | from `wald()$df1` |
| `df2` | integer | from `wald()$df2` |
| `r2` | numeric | `fixest::r2(m, "r2")` (or `wr2` when FE present) — partial-R^2 diagnostic |
| `is_primary` | logical | flag |

**LaTeX fragment (`ar_results.tex`):** bare `tabular` (no float wrapper),
booktabs rules only (INV-3), no notes embedded (INV-1). Wrapping with
`\begin{table}` and notes happens later in the paper. Columns: `Spec`,
`Tier`, `Weight`, `Baseline`, `LHS`, `EC`, `K`, `F`, `p`, `N`. About 8–10
rows for the primary panel; full grid stays in the CSV.

### Step 5. Grouped AR (heterogeneity diagnostic, NOT primary)

Two groupings per the strategy memo §4 and the prompt:

1. **By state (UF) — 27 groups.** Compute `state_id = floor(muni_id / 10000)`
   on Panel B (already present from script 41 line 165). For each state, run
   the primary spec restricted to that state's munis. Report F, p, n_munis,
   K. Multiple-testing handling per memo §4: present descriptive statistics
   (median F, IQR, fraction above F-critical) and Benjamini-Hochberg-adjusted
   p-values side-by-side. Save to `ar_grouped_state.csv`.

2. **By BNDES intensity quartile — 4 groups.** Compute on the fly:
   `whole_period_bndes_pc = mean(bndes_pc, na.rm = TRUE)` per muni over
   2002–2017, then quartile-cut. Run primary spec within each quartile.
   Save to `ar_grouped_quartile.csv`.

Both grouped runs are diagnostic — they do not contribute to the
primary-spec results CSV.

### Step 6. Falsification battery (minimum first pass)

Per the prompt and strategy memo §9, implement F1, F2, F7 only in this pass.
F3–F6 and F8 are deferred.

| # | Test | LHS | RHS | Expected |
|---|---|---|---|---|
| F1 | Transfers placebo | `log_transfers_pc` (already on Panel B from script 41 Step 5c) | Same K=4 mayor instruments as primary | Should NOT reject — instruments do not affect transfers if exclusion clean |
| F2 | Lead instruments | `log_gdp_pc` | Z values shifted +4 years (`shift(Z, 4, type = "lead")` per muni) | Should NOT reject — future alignment shouldn't predict current GDP |
| F7 | Pre-period balance | Pre-2005 muni average of `log_gdp_pc`, `log(population)`, `log(total_employment)` | Cross-muni first-cycle (2005) Z values | Should NOT reject for any pre-treatment outcome |

Output: `ar_falsification.csv` with one row per (test_id, outcome, F, p, df1, df2, n).

### Step 7. Run + verify (simplified-mode loop)

```bash
# 7.1 Rebuild Panel B with the new ec_total_* columns
Rscript scripts/R/run_politicsregs.R 41 -- --sector-var=policy_block

# 7.2 Re-run audit (must PASS all checks)
Rscript scripts/R/diagnostics/audit_41_muni_panel.R --sector-var=policy_block

# 7.3 Run the AR exploration
Rscript explorations/anderson_rubin/ar_baseline.R

# 7.4 Confirm output files present
ls -lh explorations/anderson_rubin/output/
#   expected:
#     ar_results.csv         (~30-60 rows, primary + variants + sensitivities)
#     ar_results.tex         (bare tabular, ~10 rows for the primary panel)
#     ar_grouped_state.csv   (~27 rows)
#     ar_grouped_quartile.csv (~4 rows)
#     ar_falsification.csv   (~5-10 rows: F1, F2 over outcomes, F7 over pre-vars)
```

---

## Expected Outputs

| Path | Contents |
|---|---|
| `data/processed/muni_panel_for_regs_policy_block.qs2` | Panel B with 24 added `ec_total_*` columns (rebuilt). |
| `output/diagnostics/41_muni_panel_audit_policy_block/audit_summary.md` | All checks PASS, including the two new EC-identity checks. |
| `explorations/anderson_rubin/README.md` | Goal / hypotheses / status / success criteria. |
| `explorations/anderson_rubin/SESSION_LOG.md` | Living incremental log. |
| `explorations/anderson_rubin/ar_baseline.R` | The AR test script. |
| `explorations/anderson_rubin/output/ar_results.csv` | One row per spec. |
| `explorations/anderson_rubin/output/ar_results.tex` | Bare tabular (INV-13). |
| `explorations/anderson_rubin/output/ar_grouped_state.csv` | 27 rows, by-UF AR. |
| `explorations/anderson_rubin/output/ar_grouped_quartile.csv` | 4 rows, by-BNDES-quartile AR. |
| `explorations/anderson_rubin/output/ar_falsification.csv` | F1 / F2 / F7 placebos. |

---

## Simplified-Mode Quality Checklist (workflow.md §2)

Implementer to verify each item before declaring DONE. Target score >= 80.

- [ ] `ar_baseline.R` runs to completion without errors on the rebuilt Panel B.
- [ ] All packages (`data.table`, `fixest`, `qs2`, `here`) are loaded at the top of the script (INV-15).
- [ ] No hardcoded absolute paths anywhere — every path uses `here::here()` (INV-16).
- [ ] `set.seed(20260429)` called once at the top, before any stochastic step (INV-14). If F2/F7 do not introduce randomness, the seed is harmless but kept for forward-compatibility with F4/F6.
- [ ] No prohibited functions: no `setwd()`, `rm(list = ls())`, `install.packages()`, `attach()` (INV-19).
- [ ] No growing vectors in loops; pre-allocate or `rbindlist` (INV-17).
- [ ] Output files at the expected paths (Step 7.4 ls).
- [ ] `ar_results.csv` has at least 12 spec rows and the primary row has a finite, well-defined `f_stat`, `p_value`, `df1`, `df2`, `n_obs`, `n_clusters`.
- [ ] `ar_results.tex` is a bare `tabular` environment (no `\begin{table}`, no `\caption{}`, no notes — INV-13). Uses booktabs rules only (INV-3).
- [ ] Audit script PASSES with `--sector-var=policy_block`.
- [ ] R0a (muni-total EC) and R0b (sector-specific EC) rows are present in `ar_results.csv` with non-null F-statistics.
- [ ] At least one F1 / F2 / F7 falsification row is present in `ar_falsification.csv`.

---

## Open Questions

1. **F2 lead horizon.** The strategy memo §9 mentions "Z at t+4 or t+2". Plan defaults to **+4 years** (one full electoral cycle ahead). User can override.

2. **F7 pre-period definition.** "Pre-2005" works for mayor cycles (mayors inaugurated 2005, 2009, 2013, 2017). Plan uses 2002–2004 muni averages for the pre-period regression; flag if user wants 2002 only.

3. **`policy_block` baseline weights file existence.** Phase 0 verified the `--sector-var=policy_block` flag is wired through scripts 31 / 33 / 34 / 35 / 41 by code reading. Before Step 1, the implementer should `ls data/processed/baseline_sector_weights_policy_block.qs2` and confirm the file exists. If not, run `Rscript scripts/R/run_politicsregs.R 30e,31,33,34,35 -- --sector-var=policy_block` once before script 41.

4. **No-controls primary — diagnostic expectations.** Without muni FE, between-muni variation in baseline exposure dominates the regressor. Z is bounded in [0, 1] but `log_gdp` ranges roughly 10–25, so the no-controls R² will be small but the F-stat is still well-defined. Flag for the user: the primary AR identifies on **between-muni cross-sectional variation interacted with within-period alignment turnover**, not the within-muni variation that the memo's standard FE spec isolates. C1 (FE-only) is the within-muni AR; comparing primary vs C1 is informative about whether the result is driven by the cross-section or the within.

5. **K = 12 / R0b collinearity (raised in earlier round, retained for record).** Under R3 K = 12 with C3 (FE + R0b sector-specific EC), the eight EC columns absorb the baseline-update component of Z and can severely shrink power. If C3 fails to reject while primary and C2 both reject, interpret as collinearity, not confound (memo §3.1).

6. **Resolved (record).** Only one strategy-memo override is in play: `log_gdp` (not `log_gdp_pc`) as primary outcome (USER 2026-04-29). The K = 4 mayor-only primary is *retained* per the memo §3 — it was a question on the user side, not an override. The no-controls primary (with FE-only as the C1 sensitivity) is a USER addition to the controls axis; it does not replace the memo's FE spec but precedes it on a controls ladder.
