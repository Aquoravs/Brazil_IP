# Phase -1 Audit Findings

Date: 2026-03-10
Scope: `31-35`, `41`, `51`, `52`, named audits (`audit_3_instruments`, `audit_41_muni_panel`), `run_politicsregs.R`
Sources checked: `AGENTS.md`, `docs/shift_share.md`, `paper/regs.tex`, `docs/plans/2026-03-10-feat-four-iv-specifications-unified-pipeline-plan.md`

## Audit Verdict

The current sector pipeline is not clean enough to extend without first fixing a small set of specification and wiring problems. The core `35 -> 41 -> 51 -> 52` skeleton is recognizable and several pieces already match the paper, but three issues are currently first-order blockers:

1. `31_build_sector_exposure_weights.R` contains a stray eager read and no longer produces the `F_rj` / `w_rjp_firms` objects that downstream scripts still require.
2. `34_build_shift_share_instruments.R` and `51_first_stage.R` implement municipality-level exposure controls replicated across sectors, not the sector-level exposure control required by the plan and the paper.
3. `diagnostics/audit_3_instruments.R` is stale relative to current outputs and cannot serve as the phase `-1` audit gate in its present form.

## Reproducibility Checks Run

- `Rscript BNDES/politicsregs/run_politicsregs.R 31:35 --audits=auto --dryrun`
- `Rscript BNDES/politicsregs/run_politicsregs.R 41,51,52 --dryrun`
- `Rscript -e "parse(file='BNDES/politicsregs/3_instruments/31_build_sector_exposure_weights.R'); cat('OK\n')"`
- `Rscript -e "parse(file='BNDES/politicsregs/3_instruments/34_build_shift_share_instruments.R'); cat('OK\n')"`
- `Rscript -e "parse(file='BNDES/politicsregs/3_instruments/35_build_credit_shares.R'); cat('OK\n')"`
- `Rscript -e "parse(file='BNDES/politicsregs/4_regression_panels/41_build_muni_panel.R'); cat('OK\n')"`
- `Rscript -e "parse(file='BNDES/politicsregs/5_estimation/51_first_stage.R'); cat('OK\n')"`
- `Rscript -e "parse(file='BNDES/politicsregs/5_estimation/52_second_stage.R'); cat('OK\n')"`
- `Rscript -e "parse(file='BNDES/politicsregs/diagnostics/audit_3_instruments.R'); cat('OK\n')"`

Result: all audited scripts parse, and the orchestrator dry-runs stage wiring successfully.

## Script-by-Script Findings

### `31_build_sector_exposure_weights.R`

Status: fail before extension

- Blocker: line 47 eagerly loads `sector_exposure_weights_owner_grouped.qs2` into `t` before any argument parsing or file checks. This is dead code and can make script 31 fail for reasons unrelated to the requested run.
- Blocker: the script currently saves `L_rjp`, `N_rj`, `w_rjp_owners`, `w_rjp`, and `L_rj`, but it does not build `F_rj` or `w_rjp_firms`. Downstream code still expects those objects:
  - `33_select_baseline_weights.R` tries to carry `F_rj` and `w_rjp_firms` forward.
  - `34_build_shift_share_instruments.R` stops if `F_rj_0` is absent.
  - `audit_3_instruments.R` still requires them in its schema checks.
- Design mismatch: the default sector variable is `sector_group`, while most of the current sector pipeline defaults to `cnae_section`. That makes unflagged runs non-reproducible across stages.

### `33_select_baseline_weights.R`

Status: mostly consistent, but downstream-dependent

- Pass: cycle mapping is consistent with the stated baseline years and the 2002 fallback.
- Risk: because `setnames(..., skip_absent = TRUE)` is used, script 33 will quietly tolerate missing `F_rj` / `w_rjp_firms` columns instead of failing early. The hard failure is deferred to script 34.

### `34_build_shift_share_instruments.R`

Status: fail before extension

- Pass: the inauguration-to-term spread is conceptually correct for the current 2003-2017 sample.
- Pass: levels and turnover instruments are both constructed and then spread across the electoral term.
- Blocker: the control object built in lines 287-300 is municipality-level, then replicated across sectors in lines 537-545. The plan and `regs.tex` require a sector-level exposure control `Σ_p w_{jmpt}` that varies across sectors within municipality-year. The current control cannot separate differential alignment from overall sector connectedness.
- Blocker: the script stops if `F_rj_0` is missing, which is incompatible with the current version of script 31.
- Minor: header comments still refer to the wrong upstream stage numbers.

### `35_build_credit_shares.R`

Status: pass with small caveats

- Pass: the RAIS skeleton is genuinely balanced within municipality-sector cells and fills zero-credit years explicitly.
- Pass: shares sum to one within municipality-year when total BNDES is positive, and `delta_s_mjt` is computed using consecutive yearly lags.
- Pass: this script is aligned with `docs/shift_share.md` on the “balanced panel with zeros” design.
- Minor: the filter `... & muni_id` in line 132 is opaque and should be written explicitly as a non-missing / positive municipality condition.

### `diagnostics/audit_3_instruments.R`

Status: stale and not reliable as the phase `-1` gate

- Blocker: the registry expects `shift_share_controls_sector.qs2`, but script 34 currently writes `controls_sector.qs2`.
- Blocker: the schema checks still require `F_rj` and `w_rjp_firms`, which script 31 no longer produces.
- Scope mismatch: this audit is hard-coded to `cnae_section` only and does not cover `41`, `51`, `52`, or orchestrator reproducibility, all of which are explicitly in phase `-1`.
- Identification mismatch: the audit currently treats controls as correctly constant within municipality-year, but the new plan explicitly says the relevant exposure control should vary at the municipality-sector level.

### `41_build_muni_panel.R`

Status: mixed; panel construction is mostly sound, control wiring is not

- Pass: GDP loading, IPCA deflation to 2018 reais, population recovery, and `log_gdp_pc` construction are all consistent with `AGENTS.md`.
- Pass: Panel B chooses the dropped sector `j0` using the largest mean share, consistent with the current design note.
- Pass: HHI and `delta_hhi` are built in a way that matches the scalar second-stage design.
- Blocker inherited from script 34: Panel A merges the municipality-level replicated exposure controls, not a sector-level exposure control.
- Risk: wide Panel B carries only `^Z_` sector instruments; if future levels or alternative sector-instrument variants are meant to feed Panel B, the current widening logic will need to be generalized.

### `51_first_stage.R`

Status: specification mismatch

- Pass: the FE menu matches the intended hierarchy:
  - baseline `muni_id^sector + sector^year`
  - robustness `muni_id^sector + muni_id^year`
  - robustness `muni_id^sector + year`
- Pass: clustered SEs are implemented at municipality and sector, and F-statistics use `fixest::wald()`.
- Blocker: the controls used by the regressions are `affiliated_share_muni_owner_*` or `affiliated_total_muni_*`, i.e. municipality-level controls replicated across sectors. This is not the sector-level exposure control required by the phase `-1` plan.
- Reproducibility risk: default `SECTOR_VAR` is `sector_group`, while `41_build_muni_panel.R` defaults to `cnae_section`.
- Minor: `write.excel()` is dead utility code in production estimation.

### `52_second_stage.R`

Status: mostly coherent with current Panel B, but not yet aligned with the planned unified pipeline

- Pass: reduced form, scalar 2SLS, and vector 2SLS all consume the wide Panel B objects consistently.
- Pass: the optimality null is implemented as a joint Wald test on the vector second-stage coefficients.
- Risk: sparse-sector dropping is hard-coded using a mayor-instrument support rule and is not currently documented in the project conventions.
- Convention mismatch: table writing is custom here rather than using `save_beamer_table()`, unlike the rest of the estimation pipeline.

### `run_politicsregs.R`

Status: pass for current scope

- Pass: dry-run wiring works for `31:35 --audits=auto` and `41,51,52`.
- Pass: forwarding after standalone `--` is implemented.
- Historical note (as of 2026-03-10): the firm-pipeline stages (firm instruments, firm panel, firm first stage) were not yet registered at audit time.
- Reproducibility caveat: because stage defaults differ across scripts, orchestrator runs without explicit forwarded `--sector-var=...` are currently fragile.

## Cross-Document Conformity

### Already aligned

- `35_build_credit_shares.R` matches the “balanced panel with zeros” logic in `AGENTS.md` and `docs/shift_share.md`.
- `41_build_muni_panel.R` implements GDP deflation and the dropped-sector rule in a way that is consistent with current project notes.
- `51_first_stage.R` uses the intended FE hierarchy and `fixest::wald()` for first-stage strength.

### Not aligned

- The current first stage does not use a sector-level exposure control, despite the plan and paper requiring one.
- The current audit gate is not aligned with current filenames or with the broader phase `-1` scope.
- Stage defaults are inconsistent across scripts, so the pipeline is not reproducible by default.

## Remediation Order Before Phase 0

1. Remove the stray eager read from script 31 and restore a coherent output schema.
2. Decide whether `F_rj` / `w_rjp_firms` remain part of the active robustness design; then either restore them in script 31 or remove all downstream dependencies.
3. Replace the municipality-level replicated control with a true municipality-sector exposure control in scripts 34, 41, and 51.
4. Rewrite or replace `audit_3_instruments.R` so it audits the current outputs and the actual phase `-1` scope.
5. Harmonize default `--sector-var` behavior across 31, 33, 34, 35, 41, 51, and 52.

## Phase -1 Status Against Plan Criteria

- `[x]` Audit memo added in a linked note
- `[x]` All current sector scripts pass or have been remediated before new features
- `[x]` Mismatches between `paper/regs.tex`, `docs/shift_share.md`, and code are documented
- `[x]` Performance and reproducibility risks that would slow iterative work are identified
