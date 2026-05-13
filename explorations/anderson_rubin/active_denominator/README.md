---
title: Active-Denominator Employment-Share Panel
status: ACTIVE
date: 2026-05-12
purpose: Build the AR-test endogenous-variable panel s^emp_{jmt} = n_{jmt}/n_{mt} under three firm-support denominator variants (contemporaneous / frozen / balanced) per the firm-support hybrid recommendation. Decision artifact for D2 default and Phase 2 production graduation.
---

# Active-Denominator Employment-Share Panel

Purpose: Implement Phase 1 of the firm-support hybrid plan (`journal/plans/2026-05-12_firm_support_hybrid_implementation.md`). Produces a (j, m, t) employment-share panel that becomes the AR-test endogenous variable, with three denominator variants for sensitivity. The default (contemporaneous unbalanced RAIS) is the working-spec choice per D2 and the hybrid memo's pillar (i).

Parent docs: [`docs/PROJECT_BLUEPRINT.md`](../../../docs/PROJECT_BLUEPRINT.md), [`docs/strategy/firm_support_restrictions_ssiv.md`](../../../docs/strategy/firm_support_restrictions_ssiv.md), [`journal/plans/2026-05-12_firm_support_hybrid_implementation.md`](../../../journal/plans/2026-05-12_firm_support_hybrid_implementation.md).

## Status

- Branch status: ACTIVE
- Started: 2026-05-12
- Last updated: 2026-05-12
- Owner artifact: `R/01_build_emp_share_panel.R` and outputs under `output/`.
- Current research use status: research building block (Phase 1 exploration; not yet graduated to production)

## Decision Context

| Field | Value |
|---|---|
| Parent A/D/F IDs | D2 (denominator default), D5-op (private-vs-all-loans downstream), F1 (composition first stage), A-firm-support |
| Decision needed | (a) Confirm contemporaneous denominator viable as production default; (b) quantify AR sensitivity to the frozen and balanced variants; feeds Phase 2 promotion to `scripts/R/3_instruments/32c_*`. |
| Current blocker | None for B1.2. B1.3 AR test waits on this panel. |
| Production boundary | Does not modify any file under `scripts/R/`. Outputs land in `output/` here, NOT `data/processed/`. Production graduation is Phase 2 (`32c_build_emp_share_panel.R`). |

## Inputs

| Input | Source | Role | Caveat |
|---|---|---|---|
| `data/processed/rais_bndes_reconstructed.fst` | script 22 | Union firm panel (44.18M rows; 40.71M with `in_rais == TRUE`). | Phase 0 A0.1: RAIS coverage = 92.13%; Negativa unavailable locally (upper-bound recoverable mass <= 7.64% per A0.1, refined to 0.63%-1.83% of formal-employment mass per A0.5). |
| `data/processed/muni_employment_baselines.qs2` | script 32b | Frozen-baseline membership reference (mayor cycles: 2005/2009/2013/2017 windows). | Mayor-tier rows only consumed here. |
| Mayor election calendar | Hard-coded | Cycle assignment: for year t, e(t) = next mayor election in {2004, 2008, 2012, 2016}; pre-election window = [e(t)-4, e(t)-1]. | Matches script 33's `baseline_window_map` mayor rows so variants B/C are comparable. |

## Scripts

| Script | Purpose | Writes |
|---|---|---|
| `R/01_build_emp_share_panel.R` | Build (j, m, t) employment-share panel under one of three denominator variants. | `output/emp_share_panel_{contemporaneous,frozen,balanced}.qs2`, `output/emp_share_panel_{variant}_summary.csv`, `output/slack_per_cell_{variant}.csv` |

CLI:

```
Rscript R/01_build_emp_share_panel.R [--denominator=contemporaneous|frozen|balanced] [--sector-var=cnae_section|sector_group|policy_block]
```

Defaults: `--denominator=contemporaneous --sector-var=cnae_section`.

## Outputs

| Artifact | Use status | Notes |
|---|---|---|
| `output/emp_share_panel_contemporaneous.qs2` | research building block | Default working spec per D2. Columns: `muni_id, cnae_section, year, n_jmt, n_mt, s_emp_jmt, delta_s_emp_jmt, cycle, in_window`. |
| `output/emp_share_panel_frozen.qs2` | diagnostic only | Variant B per hybrid memo (denominator on firms RAIS-active in [e(t)-4, e(t)-1]). |
| `output/emp_share_panel_balanced.qs2` | diagnostic only | Variant C per hybrid memo (firms present in pre- AND post-election windows). Expect ~52% attrition per Phase 0 A0.3. |
| `output/slack_per_cell_{variant}.csv` | diagnostic only | (muni, year, cycle)-level slack = share of contemporaneous n_mt accounted for by variant's firm set. BHJ §4.4 incomplete-shares control input for B1.3. |

## Findings

### B1.2 panel construction (2026-05-12)

- Contemporaneous variant: 1.46M (j, m, t) cells, K = 20 CNAE sections (G excluded by upstream), 121 muni-years dropped where n_mt = 0 (0.14%). Slack share identically 1.0 (definitional).
- Frozen variant: comparable cell count; slack share quantifies frozen-firm mass / contemporaneous mass per muni-year (BHJ §4.4 incomplete-shares input).
- Balanced variant: substantially smaller; slack share ~ 0.45-0.65 in late years per the slack csv.
- Top-5 sectors by `n_mt`-weighted mean share (full sample): O (Public Admin, 19.4%), C (Manufacturing, 16.6%), G (Trade, 16.5%), N (Admin/Support, 8.1%), M (Professional, 8.0%). O ranks #1 unweighted (44.98%) because small munis are dominated by municipal payroll; weighting by n_mt reduces this artifact but O still leads. See `output/sector_share_summary.csv`.

### B1.3 AR test (2026-05-12)

Primary results, MGP flavor (mayor + governor + president cross-office instruments, K = 57 = 19 sections × 3 offices after holdout U):

| variant | outcome | AR F | AR p | eff_F (proxy OP) | Rejection region |
|---|---|---|---|---|---|
| contemporaneous | log_gdp | 5.29 | < 1e-16 | **19.98** | bounded, excludes 0 |
| contemporaneous | delta_log_gdp | 1.15 | 0.207 | 19.98 | unbounded (Dufour) |
| frozen | log_gdp | 5.26 | < 1e-16 | 15.67 | bounded, excludes 0 |
| frozen | delta_log_gdp | 1.15 | 0.209 | 15.67 | bounded, contains 0 |
| balanced | log_gdp | 5.31 | < 1e-16 | **42.93** | bounded, excludes 0 |
| balanced | delta_log_gdp | 1.12 | 0.247 | 42.93 | bounded, contains 0 |

- **Pass criterion (eff_F >= 10 on contemporaneous)**: PASS (19.98).
- All three variants reject H0: beta = 0 sharply on `log_gdp` levels (p < 1e-9). The Dix-Carneiro–Kovak hybrid recommendation passes empirically: the composition channel is non-zero in levels regardless of firm-support choice.
- `delta_log_gdp` does not reject across variants — short-run year-on-year changes carry less signal than the cumulative level shift; AR CI contains zero for first-differenced outcomes (consistent with low-frequency variation in the political-turnover instrument).
- Effective F ranking: balanced (42.9) > contemporaneous (20.0) > frozen (15.7). The balanced variant has the strongest first stage because its firm set is highly self-selected on survival; contemporaneous strikes the documented compromise per the hybrid memo.
- Single-office flavors confirm robustness: Pres-only AR F = 9.97 (log_gdp, contemporaneous), Gov-only = 3.51, Mayor-only = 2.40 — all reject at <0.001, with the presidential cross-section carrying the most identifying variation.
- See `output/ar_test_summary.csv` (full grid: 3 variants × 2 outcomes × 6 flavors) and `output/ar_test_full_{variant}_{outcome}.tex` (bare booktabs `tabular` for MGP coefficient tables).

## Caveats

- **D1 / D5-op:** Firm universe is RAIS only. The "private-vs-all-loans" volume-control split is a Phase 3 task and does NOT enter this panel; this branch only constructs the endogenous-variable share vector.
- **Phase 0 A0.2:** Every RAIS firm has `n_employees >= 1`. The earlier "include zero-employee firms" wording is moot; cell existence = (>= 1 firm of sector j in (m, t)) ⇔ (n_{jmt} >= 1).
- **Phase 0 A0.3:** Variant A drops only 121 muni-years (0.14%); variant B essentially the same; variant C is much more aggressive.
- **Negativa unavailable locally** (Phase 0 A0.1). Quantified upper bound on the missing-formal-employment mass per A0.5: 0.63%-1.83% per year.
- **Sector classification at exploration stage:** `cnae_section` by default. The post-D28 production margin is not yet committed; `--sector-var` toggles for sensitivity but no production-margin decision is taken here.

## Graduation / Archive Decision

- **Graduation condition:** B1.3 AR test (sister script in this branch) runs cleanly across all three variants with effective F ≥ 10 on the contemporaneous variant; coder-critic ≥ 80; user signoff. Then promote `01_build_emp_share_panel.R` to `scripts/R/3_instruments/32c_build_emp_share_panel.R`.
- **Archive condition:** If the contemporaneous default fails the AR-test pass criterion across all three variants, archive this branch under `explorations/anderson_rubin/ARCHIVE/` and re-open the hybrid recommendation.
- **Next action:** Run B1.3 (`R/02_ar_test_emp_share.R`) consuming the three panels produced here.
