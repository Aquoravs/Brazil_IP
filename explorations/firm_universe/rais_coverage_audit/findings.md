# Findings - RAIS Coverage Audit

**Date:** 2026-05-12
**Phase:** Phase 0 (A0.1 complete; A0.2, A0.3 pending and will be appended).
**Source plan:** `journal/plans/2026-05-12_firm_support_hybrid_implementation.md`.

## A0.1 - RAIS coverage inventory

### Data and method

- Union panel: `data/processed/rais_bndes_reconstructed.fst`, 44,181,405 firm-year-muni rows, 6,460,955 firms, 5,573 munis, 2002-2017.
- Population terciles: built from the muni-level mean of `population_ibge.qs2` over 2002-2017, assigned by rank thirds (T1 small / T2 mid / T3 large, approx 1,857 munis each).
- Classes are mutually exclusive over the union panel; priority is `in_rais_panel` > `bndes_only_no_rais` > `owner_only_no_rais` > residual.

### Headline class counts (overall)

| Class | Rows | Share |
|---|---:|---:|
| `in_rais_panel` | 40,706,050 | 92.13% |
| `owner_only_no_rais` | 3,373,874 | 7.64% |
| `bndes_only_no_rais` | 101,481 | 0.23% |
| `other_no_rais` | 0 | 0.00% |

The headline numbers reconcile exactly with the union panel summary (`rais_bndes_reconstructed_summary.csv`: `pct_in_rais = 92.13`).

### Stratification findings (top 3)

1. Coverage is essentially flat over time. Yearly RAIS share never drops below 91.77% (2016) or rises above 92.47% (2005). The `bndes_only_no_rais` class is small in every year (0.07%-0.44%) and peaks in 2010-2014 - the PAC/BNDES expansion years - consistent with that period drawing in informal-leaning recipients via PSI-era policies. No secular trend, so the contemporaneous denominator does not become more or less selected over the AR-test window.
2. Non-RAIS rows concentrate in services and construction, not industry. CNAE sections with the highest non-RAIS share are F (Construction, 12.86%), G (Wholesale/Retail, 11.16%), L (Real Estate, 9.97%), I (Accommodation/Food, 9.76%), B (Mining, 8.18%). Manufacturing (C) is 7.42%. Section G alone accounts for 1,777,637 of the 3,475,355 non-RAIS rows. The formal-sector composition vector is most trustworthy in industry and least trustworthy in retail/services, which is also where employment shares are largest in many munis.
3. Small munis have a slightly higher BNDES-only-no-RAIS share, but coverage is otherwise tercile-invariant. RAIS shares are 92.53% (T1), 91.84% (T2), 92.15% (T3). The `bndes_only_no_rais` share is highest in T1 (0.50%) vs T3 (0.21%) - a 2.4x ratio. Interpretation: BNDES disbursements that fail to merge into RAIS are disproportionately small-muni events, plausibly PRONAF/MEI-style recipients below the RAIS threshold. T1 munis hold only 3.2% of rows, so this leans on volume not share construction.

### Class 2 (`in_rais_dropped`) - N/A

The reconstructed panel does not preserve a flag identifying firms that were in RAIS-raw but dropped by upstream filters in `scripts/R/2_firm_panel/`. We cannot separate "panel filter drop" from "never in RAIS universe" within `in_rais == 0` rows. Recovering it would require re-running script 22 with the pre-filter row count retained.

### Quantifiable bound from missing RAIS Negativa

Yes, to first order, and the bound is small. RAIS Negativa records zero-employee formal firms.
- Direct (employment) contribution: zero. Negativa firms contribute zero employees to $n_{jmt}$ by definition, so their absence does not bias $n_{mt}$ as an employment count.
- Indirect (cell existence) contribution: small. A $(j,m,t)$ cell exists if any RAIS firm with sector $j$ is in muni $m$ year $t$. Negativa-only cells are dropped. Upper bound on the gap is the union-panel non-RAIS share: at most 7.87% of rows (combined owner+bndes only). Of these, the Negativa-recoverable share is bounded above by the Owner-only share (7.64%); BNDES recipients are generally not Negativa filers.

The contemporaneous denominator is bounded above by RAIS-with-employees <= RAIS-total <= RAIS-with-employees + 7.64% of admin-observed firms. This is the quantifiable bound for the AR-test spec limitations section.

## A0.2 - Zero-employee firm prevalence

### Sample and headline

40,706,050 RAIS-covered firm-years (`in_rais == TRUE`), 2002-2017. No NA in `n_employees`. The empirical minimum is **1**. **Zero-employee firm-years = 0 in every year** (rate = 0.0000%).

The upstream RAIS reconstruction (scripts 11-22) already omits all RAIS-Negativa-equivalent rows; the absence is total, not residual.

### Year totals

Monotonic growth 1.75M (2002) -> 3.13M (2017); zero-emp count = 0 every year.

### Stratification

All strata are degenerate (zero zero-emp rows). Descriptive companion: **28.36% of firm-years (11,545,513) sit at exactly `n_employees == 1`** -- the closest analogue to a "micro / quasi-Negativa" mass.

- By pop tercile: T1=1.32M, T2=3.23M, T3=36.16M (NA=5,577 due to muni_id non-matches)
- By establishment type: single-estab 96.3%, multi-estab 3.7%
- All zero-emp cells empty.

### Persistence vs transient

Both undefined (NaN) -- no zero-emp firm-years exist to classify.

### Escalation flag -- TRIGGERED

The < 1% threshold is hit with massive margin (rate = 0.0000%). **D2 implication:** the "contemporaneous skeleton includes zero-employee firms" provision is moot in current data -- every firm in the skeleton has `n_employees >= 1`. The "contemporaneous includes zero-emp firms" framing in the firm-support memo must be tightened to "any firm with a RAIS row in year t (currently equivalent to `n_employees >= 1`)." A0.1 (Negativa-absent-firm inventory) becomes load-bearing for the hybrid plan; the Negativa-recoverable mass is bounded above by the Owner-only 7.64% gap reported in A0.1 -- not equated to it (some Owner-only firms are non-RAIS-universe, e.g. informal/MEI, and would not be recovered by Negativa ingestion).

## A0.3 - Contemporaneous denominator viability

### Inputs

`rais_bndes_reconstructed.fst` (`in_rais == TRUE`): 40.7M firm-years, 6.07M firms, 5,571 munis, 2002-2017. Frozen mayor-cycle baselines from `muni_employment_baselines.qs2`. Total muni-years = 89,136.

### Drop counts (variant A, contemporaneous)

| Threshold | Muni-years | Share |
|---|---:|---:|
| $n_{mt} = 0$ | 121 | 0.14% |
| $n_{mt} \le 10$ | 363 | 0.41% |
| $n_{mt} \le 50$ | 913 | 1.02% |
| $n_{mt} \le 100$ | 1,798 | 2.02% |

### Cross-variant ($n_{mt} = 0$)

- A (contemporaneous): 121 (0.14%)
- B (frozen pre-election window): 124 (0.14%)
- C (balanced post-election panel): 211 (0.24%)

Variants A and B are statistically indistinguishable on the zero margin. Variant C halves the frozen firm support (cycle 2013: 1.55M balanced vs 3.24M frozen -- ~52% attrition), confirming memo's pillar (iii) on the first-stage-relevance cost of option (C).

### Muni distribution

Only 36 munis ever hit $n_{mt} = 0$; none zero across all 16 years. Drops concentrate in a small intermittent-reporting set, not a panel-wide leak.

### Slack series

$\sum n^{frozen}_{mt} / \sum n_{mt}$ -- within-window years mechanically = 1. Out-of-window: 2004 = 0.964, 2008 = 0.968, 2012 = 0.970, 2016 = 0.976, **2017 = 0.949** (lowest, 2-year horizon past 2015 baseline window). **No post-2013 collapse** -- memo's final-bullet concern not realised on mayor-cycle baselines.

### Escalation status -- NOT TRIGGERED

5% drop threshold cleared by two orders of magnitude. Contemporaneous unbalanced denominator (D2 default) is viable. Variant B preferred for instrument side per hybrid; variant C documented as attritionful sensitivity.

## A0.5 - Owner-only firm employment proxy

### Question

Of the 3,373,874 Owner-only firm-year rows (7.64% of the union panel), how many have a non-trivial number of employees? The user's prior: most are zero-employee and therefore irrelevant to the local economy.

### Data limitation

Owner-only firms have no RAIS record by construction; direct employment is unobservable. The Owner table (`owner_aff_firm_year_party_2002_2019.parquet`) is keyed by `(firm_id, year, party)` and preserves only the COUNT of affiliated owners (`aff_owners`), not owner identifiers. We therefore cannot perform true owner cross-membership (diagnostic #2 in the spec). Substituted with year-level cross-membership: does the same CNPJ appear in RAIS in some other year?

### Diagnostics

1. **CNAE composition (`owner_only_cnae_distribution.csv`).** Owner-only firms cluster in sectors where RAIS-covered firms are predominantly tiny. **Owner-only-weighted mean of "share of RAIS firms in same sector with 1-4 employees" = 62.2%**. Owner-only-weighted median employment of RAIS peers = 3.34. Sectoral mix (top: G/Wholesale-Retail, F/Construction, L/Real Estate, I/Accommodation-Food) is the same mix that dominates the non-RAIS rows in A0.1.

2. **Cross-membership substitute (`owner_only_owner_crossmembership.csv`).** 86.7% (2,403,502 firms) of the Owner-only firms appear in RAIS in some OTHER year -- consistent with intermittent formal-employment status (one-employee firms drop in/out of RAIS year-to-year). Only **13.3% (367,988 firms) never appear in RAIS in any year** -- the strongest candidate set for "non-operational / individual entrepreneurs". This is a lower bound on the never-operational share (the data cannot rule out a firm that operated but was always informal).

3. **Persistence (`owner_only_persistence.csv`).** **83.2% of Owner-only firms appear in only 1 year as Owner-only**; these contribute 68.4% of Owner-only rows. The single-year mass is consistent with short-lived registrations or CNPJs that crossed the RAIS reporting margin once.

4. **Owner count (`owner_only_aff_owners.csv`).** **64.7% of Owner-only firm-year rows have a single affiliated owner**; 35.3% have two or more. The single-owner share is high but not overwhelming -- a meaningful fraction (~35%) are multi-owner entities, consistent with real (but small) partnerships rather than individual non-operational CNPJs.

5. **Counterfactual employment-mass bound (`owner_only_employment_bound.csv`).** Imputing each Owner-only row's employment as the median (resp. P25) RAIS employment in its CNAE-section x population-tercile x year cell, then summing:

   | Imputation | Subset | Avg yearly mass added (% of RAIS total emp) |
   |---|---|---:|
   | Median | All Owner-only rows | **1.83%** |
   | P25    | All Owner-only rows | 0.73% |
   | Median | Ever-in-RAIS subset (likely operational) | 1.58% |
   | P25    | Ever-in-RAIS subset | 0.63% |

   The "ever-in-RAIS" subset is the more relevant counterfactual: those firms are demonstrably real businesses; their Owner-only year(s) likely reflect formal-payroll gaps. The never-in-RAIS subset (13.3%) plausibly includes the user's "0-employee, non-operational" CNPJs.

### Headline conclusion

**The user's prior is supported, with one important caveat.** Owner-only firms are concentrated in sectors where RAIS firms are 62% tiny; 83% appear in only a single Owner-only year; and the most generous upper bound on their contribution to contemporaneous formal employment -- median imputation across all Owner-only rows -- is **1.83% of total RAIS employment per year**. Under the P25-imputation, ever-in-RAIS-subset variant (the bound most aligned with the prior that the never-RAIS 13% have ~zero employment), the bound falls to **0.63% per year**. Both are below the 5% threshold flagged in the audit spec.

**Caveat:** "Non-trivial number of employees" is not the same as "non-trivial GDP contribution". The bound applies to the contemporaneous formal-employment denominator $n_{mt}$, which is what the AR-test endogenous variable (sector employment shares) depends on. It says nothing about output / value-added that small Owner-only firms may generate. For the AR-test specification, the Owner-only gap is a tolerable upper bound (< 2% of formal employment) and the user's prior is the working assumption.

### Quantified upper bound

For the AR-test limitations section: **the contemporaneous formal-sector denominator $n_{mt}$ excludes at most 1.83% of latent formal employment (average across 2002-2017)** under the most permissive imputation (cell-median across ALL Owner-only rows). A defensible central bound is 0.6-1.6%.
