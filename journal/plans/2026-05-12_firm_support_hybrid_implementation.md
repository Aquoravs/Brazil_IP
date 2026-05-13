# Plan — Firm-Support Hybrid Implementation for AR Test

**Status:** APPROVED (2026-05-12) — Phase 0 ready to dispatch via orchestrator
**Date:** 2026-05-12
**Phase:** Exploration → Production graduation
**Source memo:** `docs/strategy/firm_support_restrictions_ssiv.md` (R2 96/100)

---

## Goal

Bring the AR-test endogenous-variable construction into compliance with the firm-support hybrid recommendation and reframe the structural claim to match what the data support:

- Endogenous variable = sector **employment shares** $s^{\text{emp}}_{jmt}$ (per D24, 2026-05-06).
- Skeleton = **contemporaneous unbalanced** RAIS firm universe, including zero-employee firms (RAIS-negativa-aware where data permit).
- Exposure weights $w_{jm,\tau}$ remain frozen on pre-election window $[e(t)-4, e(t)-1]$ (already correct via script 33).
- Volume control comprehensive: BNDES auto + non-auto (which already contains `forma_de_apoio == "DIRETA"` direct loans) + public-entity disbursements; with split-volume robustness.

---

## Design decisions adopted (user 2026-05-12)

- **D1.** Firm universe = RAIS only. Structural claim narrowed to *"politically-driven shifts in formal-sector composition are GDP-neutral conditional on volume."*
- **D2.** Default denominator = contemporaneous unbalanced. Skeleton includes any firm with a RAIS row in year $t$ (current panel pre-strips Negativa-equivalents, so this is equivalent to `n_employees >= 1`; Phase 0 A0.2 confirmed zero-emp rate is 0.0000%). CLI toggle `--denominator=contemporaneous|frozen|balanced` for sensitivity. The "include zero-employee firms" earlier wording is moot under current data; A0.1's Owner-only 7.64% gap is the upper bound on the Negativa-recoverable mass (not a tight equality — some Owner-only firms are non-RAIS-universe, e.g. informal/MEI).
- **D3.** Channel bound + split-volume robustness. AR test detects formal-channel composition effect only. `bndes_total_RAIS` vs. `bndes_total_nonRAIS` reported as separate volume terms in robustness.
- **D4.** Direct BNDES = control for volume (already captured in non-automatic indirect data via `forma_de_apoio == "DIRETA"`, per user 2026-05-12). For exposure weights, indirect-auto + indirect-nonauto (default), with `--bndes-channel` toggle reserved if future need.
- **D5.** Public-entity BNDES loans included in volume control. Financial-institution intermediation flows verified not double-counted (Phase 0 A0.4: overlap impact <= 0.015% of total credit, no escalation). Excluded sectors: out of exposure weights, in volume control. Other public-credit channels (CEF/BB/BNB/constitutional funds) registered as A-entry, out of scope here.
- **D5-op (user 2026-05-12).** Operational specification: exposure weights restricted to `recipient_class == "productive-firm"` (private only); volume control aggregates all classes (productive + public + financial-institution), entered jointly as `bndes_total_mt / initial_gdp_m,0` and also split-volume robustness. Phase 3 requires lifting script 11's `nature == "PRIVADA"` filter and adding a `recipient_class` tag at the loan-level (A0.4 finding: PRIVADA strips 28.3% of total disbursement).

---

## Phases

### Phase 0 — Audits (1–2 hours)

**A0.1 — RAIS coverage audit (INVENTORY ONLY per user 2026-05-12).**
- Inventory: count Owner-CNPJs missing from current RAIS panel by year. Stratify by sector and muni population.
- Stratify the gap by likely root cause (e.g., firm in Owner but never filed RAIS Negativa; firm in BNDES but never in RAIS at all; firm in RAIS but dropped by current panel filters).
- **RAIS Negativa is NOT available locally** (user confirmed 2026-05-12). Document the gap and stop here; user will review the inventory and decide future acquisition separately.
- Note coverage limit explicitly in `docs/methodology/ar_test_specification.tex` (Phase 4).
- Output: `explorations/firm_universe/rais_coverage_audit/findings.md`.

**A0.2 — Zero-employee firm prevalence.**
- Query current RAIS panel: firm-years with `n_employees = 0`. Distribution by year, muni, sector.
- Output: append to A0.1.

**A0.3 — Contemporaneous-denominator viability.**
- Compute $n_{mt}$ on the proposed contemporaneous skeleton. Count muni-years where $n_{mt} = 0$.
- Document drop count and which munis.
- Output: append to A0.1.

**A0.4 — BNDES recipient-type audit.**
- From `rais_bndes_reconstructed`: classify loan recipients into productive-firm (RAIS-CNPJ productive sector), public-entity, financial-institution, other.
- Sum disbursements by class, by year, by muni.
- Verify financial-institution loans are not double-counted (cross-check `forma_de_apoio` codes against post-bank disbursements).
- Output: `explorations/firm_universe/bndes_recipient_audit/findings.md`.

### Phase 1 — Exploration (active-denominator share artifact)

**B1.1.** Create branch `explorations/anderson_rubin/active_denominator/` with README and SESSION_LOG.md (templates from `templates/exploration-readme.md`).

**B1.2.** Script `01_build_emp_share_panel.R`:
- Load reconstructed RAIS panel (including negativa-recovered firms from Phase 0 if applicable).
- Build skeleton: $(j, m, t)$ cells where at least one RAIS firm with sector $j$ is present in muni $m$ year $t$ (regardless of `n_employees`).
- Compute $n_{jmt} = \sum_{f \in (j,m,t)} \text{n\_employees}_f$.
- Compute $n_{mt} = \sum_j n_{jmt}$.
- Compute $s^{\text{emp}}_{jmt} = n_{jmt}/n_{mt}$ where $n_{mt} > 0$; else NA (drop muni-year per Phase 0 count).
- Three variants by `--denominator` flag:
  - `contemporaneous` (default): unbalanced RAIS at year $t$.
  - `frozen`: restricted to firms active in $\tau \in [e(t)-4, e(t)-1]$.
  - `balanced`: present at $\tau$ and every post-election year.

**B1.3.** Script `02_ar_test_emp_share.R`:
- Load instruments from production stage 34 (`shift_share_instruments_sector*.qs2`).
- Run AR test with $s^{\text{emp}}_{jmt}$ endogenous, $\text{bndes\_total}_{mt}/\text{gdp}_{m,0}$ as volume control.
- Run all three denominator variants; report F-stats, rejection regions, point estimates side-by-side.
- Save to `output/ar_test_active_denominator.csv` + diagnostic plots.

**B1.4.** Robustness diagnostics (per memo):
- Rotemberg-weight ranking (top 5), drop-top-5 AR rerun, pre-trends on high-weight sectors.
- Sum-of-exposure-shares slack control on/off.
- Split-volume: separate `bndes_total_RAIS`, `bndes_total_nonRAIS`, `bndes_total_public` terms; AR with comprehensive single vs. split.

**B1.5.** Pass criterion:
- AR test runs cleanly across all three variants.
- F-stat ≥ 10 (Olea–Pflueger effective F) for the contemporaneous variant.
- Rejection regions documented and economically interpretable.
- Coder-critic score ≥ 80 on the two scripts.

### Phase 2 — Production graduation

**C2.1.** New script `scripts/R/3_instruments/32c_build_emp_share_panel.R`:
- Promotes the Phase 1 artifact to production.
- Output: `data/processed/emp_share_panel.qs2`.
- Default to `--denominator=contemporaneous`; preserve toggles for sensitivity runs.

**C2.2.** Modify `scripts/R/4_regression_panels/41_build_muni_panel.R`:
- Replace `panel_a <- copy(credit)` (line 508) with merge from `emp_share_panel.qs2`.
- Add `s_emp_mjt`, `delta_s_emp_mjt` columns.
- Preserve `s_mjt` (BNDES credit share) as a side variable for mechanism checks (per D24).
- Add CLI flag `--endogenous=emp_share|bndes_credit` defaulting to `emp_share`.

**C2.3.** Modify `scripts/R/5_estimation/53_*.R` and `54_*.R`:
- Switch endogenous to `s_emp_mjt` / `delta_s_emp_mjt`.
- Keep BNDES credit-share regressions as mechanism-check side outputs.
- Update output table labels and notes accordingly.

### Phase 3 — Volume control completeness

**D3.1.** Verify script 11 output via Phase 0 audit:
- Confirm `bndes_total_mt` already includes auto + non-auto (including `forma_de_apoio == "DIRETA"`).
- Confirm public-entity disbursements are present and tagged. For this, consider the data available in `data/raw/bndes_public_administration/` and the observations from the current BNDES datasets that are directed to public entities. Are they they same?
- Confirm financial-institution flows are not double-counted.

**D3.2.** Modify script 41 to produce split-volume columns:
- `bndes_total_RAIS_mt`, `bndes_total_nonRAIS_mt`, `bndes_total_public_mt`.
- Each as ratio to `initial_gdp_m,0` (the volume-control normalization per D24).

**D3.3.** AR test variants in stage 54:
- Baseline: single comprehensive `bndes_total_mt` / `initial_gdp`.
- Robustness: three split-volume terms entered separately.
- Robustness pass criterion: rejection region qualitatively stable.

### Phase 4 — Documentation

**E4.1.** Update `docs/methodology/ar_test_specification.tex`:
- Section "Endogenous variable": narrow to formal-sector composition; cite the firm-support memo.
- Section "Skeleton construction": formalize contemporaneous unbalanced + zero-employee handling.
- Section "Robustness": add three-variant denominator comparison; add split-volume; add Rotemberg diagnostic.
- Section "Limitations": explicit RAIS-formal-only bound; other-public-credit channels as known limitation.
- Recompile PDF, commit alongside source.

**E4.2.** Update `docs/PROJECT_BLUEPRINT.md`:
- §6 (decisions log): D25 = firm-support hybrid adopted (link to this plan + memo).
- §4 (open angles): A-entry for RAIS-negativa coverage expansion (contingent on Phase 0 audit).
- §4: A-entry for "other public-bank credit channels" (CEF/BB/BNB/constitutional funds) as future scope.
- §7 (next action): Phase 0 audits.

**E4.3.** Update `docs/strategy/firm_support_restrictions_ssiv.md`:
- Add split-volume robustness to the robustness list (R3 extension).
- Add note on RAIS-negativa coverage expansion (Phase 0 finding).
- Score impact: should regain the residual −1 deduction for Adão (2016) absence if we cite him here or in the AR-test spec.

---

## Files

**Created:**
- `explorations/firm_universe/rais_coverage_audit/{README.md, findings.md, R/}`
- `explorations/firm_universe/bndes_recipient_audit/{README.md, findings.md, R/}`
- `explorations/anderson_rubin/active_denominator/{README.md, SESSION_LOG.md, R/01_build_emp_share_panel.R, R/02_ar_test_emp_share.R, output/}`
- `scripts/R/3_instruments/32c_build_emp_share_panel.R`

**Modified:**
- `scripts/R/4_regression_panels/41_build_muni_panel.R` (skeleton swap, split-volume columns, `--endogenous` CLI flag)
- `scripts/R/5_estimation/53_sector_first_stage.R` and `54_*.R` (endogenous variable swap)
- `docs/methodology/ar_test_specification.tex` (4 sections updated)
- `docs/PROJECT_BLUEPRINT.md` (§4, §6, §7)
- `docs/strategy/firm_support_restrictions_ssiv.md` (robustness extension)

---

## Verification

- Each new/modified script gets coder-critic score ≥ 80.
- AR test results compared across three denominator variants — differences documented.
- Split-volume robustness: rejection region qualitatively stable.
- `ar_test_specification.tex` compiles via `latexmk` and produces a paginated PDF.
- Blueprint argument map self-consistent (front-door check on next session start).

---

## Resolved (2026-05-12)

- **Q1 → A1.** Inventory only. RAIS Negativa is not locally available; user will review the gap and decide acquisition separately. No ingestion in this plan.
- **Q2 → A2.** A-entry only. Other public-bank channels (CEF/BB/BNB/constitutional funds) registered in blueprint §4 as future scope. No parallel memo in this plan.
- **Q3 → A3.** Plan approved; orchestrator brief at `journal/plans/2026-05-12_firm_support_orchestrator_prompt.md` to be invoked by user when ready.

---

## Three-strikes / escalation pre-registration

This plan touches the production pipeline (stage 41, 53, 54) and the load-bearing strategy memo. If coder-critic or strategist-critic flags any phase-2 or phase-3 change as identification-breaking, escalate to user before proceeding. No autonomous overrides on production-pipeline structure.
