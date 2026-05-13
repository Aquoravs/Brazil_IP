# Session Log — active_denominator

## 2026-05-12 — Branch creation and B1.2 implementation

**Goal:** Stand up Phase 1 of the firm-support hybrid plan. Produce a (j, m, t) employment-share panel with three denominator variants (contemporaneous default; frozen and balanced as sensitivities) that will serve as the AR-test endogenous variable.

**Context references:**
- Plan: `journal/plans/2026-05-12_firm_support_hybrid_implementation.md` (Phase 1, design decisions D1, D2 — D2 tightened 2026-05-12).
- Memo: `docs/strategy/firm_support_restrictions_ssiv.md` (operational notes (i) and (ii); BHJ §4.4 incomplete-shares).
- Phase 0 findings: `explorations/firm_universe/rais_coverage_audit/findings.md` (A0.2 zero-emp = 0; A0.3 contemporaneous viable; A0.5 OO upper bound 0.63%-1.83%).

**Cycle / window definition (matches script 33 mayor rows):**
- Mayor elections: 2004, 2008, 2012, 2016. Treatment years (cycles): 2005, 2009, 2013, 2017.
- For year t in 2002..2017, assign to cycle = next election cycle (smallest c in {2005, 2009, 2013, 2017} with c > t). Years 2017+ map to cycle 2017 with the same [2012, 2015] window.
- Pre-election window per cycle: [e-4, e-1] = [2000, 2003], [2004, 2007], [2008, 2011], [2012, 2015] (using bl_start/bl_end from script 32b).
- `in_window` flag = (year in [bl_start, bl_end]) for the assigned cycle.

**Operations:**
- Created `R/` and `output/` subdirs; wrote `README.md` from template and this `SESSION_LOG.md`.
- Wrote `R/01_build_emp_share_panel.R` (default `--denominator=contemporaneous`).
- Ran the contemporaneous variant end-to-end via `Rscript`.

**Decisions:**
- Use `here::here()` via the script-file resolution path inside the exploration subtree rather than `bootstrap_politicsregs()`, to keep the exploration self-contained (judgment call per task spec). Input paths still resolved via `output_path()` helper from `_utils/utils.R` to read the canonical processed-data location.
- Default sector classification = `cnae_section`. Allow `--sector-var` toggle but do not commit a production margin (D28 unsettled).
- Drop muni-years with `n_mt == 0` rather than emitting NA rows, to match the BHJ-§4.4 convention used downstream (slack control accounts for incomplete-shares variation, not zero rows).

## 2026-05-12 17:44 — B1.4 robustness diagnostics

**03_rotemberg_diagnostics.R** — Headline spec (contemporaneous + MGP + muni+year FE + log_gdp). Partial-Wald analog of Rotemberg weight `w_k = t_k^2 / sum_j(t_j^2)`. Top-5 instruments carry 0.507 of joint AR F. Drop-top-5: AR F drops 2.692 -> 1.623, p 9.1e-11 -> 0.003 — rejection survives at 1% but tail thins. Pre-trend test: 2/5 sectors flag (Pres x T, Pres x E) at 5%; mayor/gov x P stable.

**04_slack_robustness.R** — 24 cells: {contemp, frozen, balanced} x {log_gdp, delta_log_gdp} x {muni_year, year_only} x slack{TRUE,FALSE}. In frozen + balanced (where slack varies), AR F shifts by <0.03 and rejection status is unchanged. Slack control mechanically drops in contemporaneous as expected. Inclusion is non-binding for the headline.

**05_split_volume_robustness.R** — Cached muni-year-class aggregate built from raw BNDES (2.1M rows -> 56,252 muni-year-class cells). Joint AR F = 2.692 (p=9.1e-11); split AR F = 2.684 (p=1.05e-10). Rejection status PASS. Volume coefs: prod 2.9e-4 (SE 1.9e-4), public 6.4e-4 (SE 5.8e-4), fi -1.05e-1 (SE 3.5e-2; FI loans negatively associated with log GDP — consistent with FI loans flowing through banks not into local production).

## 2026-05-12 19:00 — B1.6 proper tau-baseline pre-trend test

**06_pretrend_proper.R** — Implements the strategist-gate (`journal/plans/2026-05-12_phase2_strategist_review.md` §C item 2 / §E pre-condition 1) requirement that B1.4's contemporaneous-on-contemporaneous flag is not a proper pre-trend.

Mapping: for pre-period year tau in {2002-3, 2005-7, 2009-11, 2013-15}, future-cycle reference year is {2005, 2009, 2013, 2017} respectively (the post-election window of the next mayoral election e in {2004, 2008, 2012, 2016}). Z is constant within each post-election cycle, so r = e+1 fully identifies Z_{m,e(t)}.

**Variant alpha (outcome):** muni + year FE; cluster on muni_id; joint Wald F on all 57 future-Z columns (3 offices x 19 sections).
- log_gdp: F = 2.39, p = 2.02e-8 — REJECTS pre-trend at 5%.
- delta_log_gdp: F = 1.61, p = 0.0024 — REJECTS pre-trend at 5%.

**Variant beta (top-5 sector shares):** 2 of 5 reject — Pres x E (p = 0.0011), Pres x P (p = 0.018). Three remain insignificant (Pres x T, Mayor x P, Gov x P). Variant beta PASSES (>=3 of 5 do not reject).

**Verdict: FAIL.** The variant-alpha rejection on delta_log_gdp is the operative concern — it means munis with larger future-cycle shocks already had different GDP growth in pre-election years, conditional on muni + year FE. This is the parallel-trends / no-anticipation violation Phase 2 dispatch was gated on.

**Comparison to B1.4 flags:**
- B1.4 flagged Pres x T and Pres x E on the within-period s_{j,m,tau} ~ Z_{m,tau} test.
- B1.6 confirms Pres x E (p = 0.0011) is also a proper pre-trend violator at the sector-share margin.
- B1.6 does NOT confirm Pres x T as a proper pre-trend violator at the share margin (p = 0.087). The B1.4 flag was within-period mechanical correlation, not anticipation.
- B1.6 NEWLY flags Pres x P at the share margin (p = 0.018).

**Outputs:** `output/pretrend_alpha_log_gdp.csv`, `output/pretrend_alpha_delta_log_gdp.csv`, `output/pretrend_beta_sector_shares.csv`, `output/pretrend_summary.md`.

**Status:** Escalate to user before Phase 2 dispatch. The strategist memo (§E) explicitly states this gate must be cleared before production-pipeline edits.

## 2026-05-13 — Policy-block diagnostics (Phase 2 C2.1.5)

Re-ran Phase 1 margin-sensitivity diagnostics at policy_block (K=4) per strategist gate.

- Script: `R/10_policy_block_diagnostics.R`
- Headline AR F = 4.19 (p = 1.96e-05) [vs Phase 1 cnae_section 2.69, <1e-10]
- Rotemberg per-block: Infra 0.49, Ind 0.43, Agro 0.08; top-1 weight share 0.32
- Drop-top-1 AR F = 3.37 (p = 7.3e-4); drop-top-2 AR F = 2.72 (p = 8.0e-3) — both reject 5%
- Slack on/off stable at `muni_year` FE (Delta=0.023); breach at `year_only` only
- AKM SE proxy: two-way clustering widens p to 0.027 (still rejects)
- K=4 power: per-restriction non-centrality ratio ~0.25 — less power per instrument but fewer many-weak concerns

Verdict: ADVANCE with two methodology caveats logged for Phase 4 documentation.
