# E1: Alignment of Option A4 with BNDES Porte
Generated: 2026-05-04 14:35:12

## Goal

Cross-tabulate Option A4 (4-bin fixed employment thresholds) against BNDES porte
(the size category recorded by BNDES at loan origination). Determines whether the
interpretability claim 'A4 bin k corresponds to BNDES porte category k' holds in data.

**F0 link:** `docs/PROJECT_BLUEPRINT.md` §3 F0 admissibility + interpretability.

---

## 1. Data Summary

- Total raw loans: 1,653,775
- Loans with known (normalized) porte: 1,653,310 (100% of post-filter loans)
- Loans dropped (year outside cycle windows 2002-2003 or >=2018): 66,125
- Unique (firm x cycle) pairs used in cross-tab: 541,856
- Pairs with both porte and A4 bin: 504,119
- Baseline fall-back rate: 25.15%

---

## 2. E1 Verdict

**WEAK PASS** — A4 fails the 4x4 value-weighted threshold (54% < 60%) but passes the 3x3 collapsed threshold (86.6% >= 65%). This suggests misalignment is concentrated at the Micro/Pequena or Media/Grande boundaries. A3 (3-bin collapse) may be a more appropriate production option. Flag for user review before E3.

| Metric | Value | Threshold | Pass |
|--------|-------|-----------|------|
| 4x4 unweighted diagonal | 65.4% | — | — |
| 4x4 value-weighted diagonal | 54% | >=60% | NO |
| 3x3 collapsed unweighted diagonal | 86.6% | >=65% | YES |
| 3x3 collapsed value-weighted diagonal | 54.2% | — | — |

---

## 3. 4x4 Cross-Tab: porte (rows) vs. A4 bin (cols)

### Unweighted (firm x cycle counts; row % in parentheses)

| porte \ A4 | Micro (1) | Pequena (2) | Media (3) | Grande (4) | Total |
|---|---|---|---|---|---|
| **Micro** | 222,228 (76.7%) | 63,900 (22.1%) | 3,400 (1.2%) | 48 (0%) | 289,576 |
| **Pequena** | 43,232 (33.8%) | 65,959 (51.6%) | 18,556 (14.5%) | 83 (0.1%) | 127,830 |
| **Media** | 7,309 (12.3%) | 17,888 (30.1%) | 31,784 (53.5%) | 2,421 (4.1%) | 59,402 |
| **Grande** | 1,543 (5.6%) | 3,665 (13.4%) | 12,600 (46.1%) | 9,503 (34.8%) | 27,311 |

### Value-weighted (total real disbursement in millions R$; row % in parentheses)

| porte \ A4 | Micro (1) | Pequena (2) | Media (3) | Grande (4) |
|---|---|---|---|---|
| **Micro** | 86902.6M (44.9%) | 40712.3M (21%) | 4107.3M (2.1%) | 62038.3M (32%) |
| **Pequena** | 47087.5M (24.8%) | 96037.0M (50.6%) | 45640.1M (24%) | 1081.4M (0.6%) |
| **Media** | 222971.2M (29.3%) | 131487.8M (17.3%) | 359400.8M (47.2%) | 48341.8M (6.3%) |
| **Grande** | 4944782.5M (8.9%) | 6393553.2M (11.5%) | 14102538.2M (25.4%) | 30027148.6M (54.1%) |

---

## 4. 3x3 Collapsed Cross-Tab

Collapse: A4 bins 1+2 -> MPME, bin 3 -> Media, bin 4 -> Grande.
porte: Micro+Pequena -> MPME, Media -> 2, Grande -> 3.
Cells show: n (row_pct_unweighted / vw=row_pct_value_weighted).

| porte \ A4 | MPME (1) | Media (2) | Grande (3) |
|---|---|---|---|
| **MPME (1+2)** | NULL (94.7% / vw=70.6%) | NULL (5.3% / vw=13%) | NULL (0% / vw=16.5%) |
| **Media (3)** | NULL (42.4% / vw=46.5%) | NULL (53.5% / vw=47.2%) | NULL (4.1% / vw=6.3%) |
| **Grande (4)** | NULL (19.1% / vw=20.4%) | NULL (46.1% / vw=25.4%) | NULL (34.8% / vw=54.1%) |

---

## 5. Confusion Pattern

Largest off-diagonal cells (4x4 unweighted):
  - porte=Micro x A4=Pequena (n=63,900, 12.7% of crosstab)
  - porte=Pequena x A4=Micro (n=43,232, 8.6% of crosstab)
  - porte=Pequena x A4=Media (n=18,556, 3.7% of crosstab)

---

## 6. Implied A3 Alignment

Option A3 (3-bin collapse) inherits A4's alignment by construction. The 3x3 collapsed diagonal (86.6% unweighted, 54.2% value-weighted) is the alignment metric for A3. No separate E1 run is needed for A3.

---

## 7. Files Written

| File | Description |
|------|-------------|
| `alignment_porte_A4_4x4_unweighted.csv` | 4x4 long format: porte_row, a4_col, n, row_pct |
| `alignment_porte_A4_4x4_value_weighted.csv` | 4x4 long format: porte_row, a4_col, sum_value, row_pct_value |
| `alignment_porte_A4_3x3_collapsed.csv` | 3x3 long format: both unweighted and value-weighted |
| `alignment_summary.csv` | Top-line metrics with threshold and pass/fail |
| `alignment_summary_counts.csv` | n_loans, n_porte_known, n_dropped, n_firm_cycle_pairs, fall-back rate |

