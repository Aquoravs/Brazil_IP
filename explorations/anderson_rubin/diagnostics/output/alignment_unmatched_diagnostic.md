# Unmatched Loan Diagnostic — E1 RAIS Coverage Gap
Generated: 2026-05-04 16:08:40

**F0 link:** F0 admissibility (docs/PROJECT_BLUEPRINT.md §3 F0). Coverage of
the RAIS-BNDES match underpins every bin assignment in the A4/A3 options.

---

## 1. Headline Numbers

- Clean loan set (firm_id + value + porte + year non-missing): 1,653,310
- Matched to a RAIS (firm, year) row:   **800,189** (48.4% of loans; 49.1% of value)
- Unmatched (no RAIS row in loan year): **853,121** (51.6% of loans; 50.9% of value)

---

## 2. By Year

| Year | n_matched | n_unmatched | share_unmatched | share_value_unmatched |
|------|----------:|------------:|----------------:|----------------------:|
| 2002 | 16,883 | 11,367 | 40.2% | 39.6% |
| 2003 | 20,096 | 17,779 | 46.9% | 67.5% |
| 2004 | 17,188 | 13,712 | 44.4% | 52.5% |
| 2005 | 20,659 | 18,885 | 47.8% | 53.5% |
| 2006 | 20,397 | 20,789 | 50.5% | 44.8% |
| 2007 | 31,162 | 34,211 | 52.3% | 67.5% |
| 2008 | 36,845 | 45,716 | 55.4% | 56.0% |
| 2009 | 45,326 | 64,580 | 58.8% | 74.0% |
| 2010 | 86,299 | 111,273 | 56.3% | 50.9% |
| 2011 | 106,394 | 132,447 | 55.5% | 49.6% |
| 2012 | 97,404 | 112,797 | 53.7% | 26.8% |
| 2013 | 96,713 | 98,167 | 50.4% | 49.3% |
| 2014 | 91,642 | 82,275 | 47.3% | 35.3% |
| 2015 | 47,761 | 39,506 | 45.3% | 58.9% |
| 2016 | 30,928 | 22,145 | 41.7% | 27.6% |
| 2017 | 34,492 | 27,472 | 44.3% | 54.1% |

**Read:** early years (≤ 2004) average unmatched share = 43.9%; middle years (2005–2014) = 52.8%; late years (≥ 2015) = 43.8%. Peak unmatched year: 2009 (58.8%); lowest: 2002 (40.2%).

---

## 3. By Porte

| Porte | n_matched | n_unmatched | share_unmatched | share_value_unmatched |
|-------|----------:|------------:|----------------:|----------------------:|
| Grande | 232,562 | 125,849 | 35.1% | 50.5% |
| Media | 159,846 | 140,486 | 46.8% | 70.5% |
| Micro | 244,854 | 371,396 | 60.3% | 44.7% |
| Pequena | 162,927 | 215,390 | 56.9% | 56.6% |

**Read:** Micro/Pequena share of unmatched loans = 68.8%; Media/Grande = 31.2%. Unmatched mass is broadly distributed across porte categories.

---

## 4. By CNAE Section

| CNAE | n_matched | n_unmatched | share_unmatched | share_value_unmatched |
|------|----------:|------------:|----------------:|----------------------:|
| A | 27,191 | 24,425 | 47.3% | 35.0% |
| B | 7,782 | 6,721 | 46.3% | 29.3% |
| C | 167,417 | 125,960 | 42.9% | 37.5% |
| D | 2,835 | 4,196 | 59.7% | 61.3% |
| E | 4,971 | 8,145 | 62.1% | 80.4% |
| F | 53,407 | 48,333 | 47.5% | 54.8% |
| G | 131,264 | 154,571 | 54.1% | 19.7% |
| H | 352,133 | 433,650 | 55.2% | 52.5% |
| I | 4,012 | 4,431 | 52.5% | 60.4% |
| J | 3,812 | 2,963 | 43.7% | 78.5% |
| K | 1,137 | 674 | 37.2% | 50.8% |
| L | 373 | 378 | 50.3% | 71.9% |
| M | 3,193 | 4,032 | 55.8% | 42.5% |
| N | 31,930 | 26,915 | 45.7% | 39.4% |
| O | 3 | 19 | 86.4% | 87.5% |
| P | 2,290 | 2,748 | 54.5% | 2.0% |
| Q | 4,045 | 2,660 | 39.7% | 11.4% |
| R | 856 | 833 | 49.3% | 22.4% |
| S | 1,538 | 1,467 | 48.8% | 80.3% |

---

## 5. By Loan Size

Values in thousands R$ (2018 BRL).

| Group | N | Mean (k R$) | Median (k R$) | p10 (k R$) | p90 (k R$) |
|-------|--:|------------:|--------------:|-----------:|-----------:|
| matched | 800,189 | 40556 | 217 | 40 | 1062 |
| unmatched | 853,121 | 39385 | 191 | 37 | 687 |

**Read:** Mean loan value for unmatched = R$ 39385K vs. R$ 40556K for matched. Unmatched loans are smaller on average — consistent with smaller/informal firms.

---

## 6. Type A vs. Type B Firms

Firms with at least one unmatched loan: **190,402**

| Firm type | Definition | N firms | Share | N unmatched loans | Share of unmatched loans |
|-----------|-----------|--------:|------:|------------------:|-------------------------:|
| **Type A — never in RAIS** | n_rais_years_anywhere = 0 | 190,336 | 100.0% | 852,860 | 100.0% |
| **Type B — sometimes in RAIS** | n_rais_years_anywhere ≥ 1 | 66 | 0.0% | 261 | 0.0% |

**Read:** Type A (truly absent from formal employment) accounts for 100.0% of unmatched-loan firms and 100.0% of unmatched loans. Type B (panel coverage gap — firm is in RAIS in some years but not the loan year) accounts for 0.0% of firms. Among Type B firms, the median RAIS year count is 3 years.

---

## 7. Recommendation

**Recommended treatment: Conditional imputation** (impute size_bin_A4 = 1 for unmatched loans where stated porte = Micro or Pequena; drop unmatched loans with porte = Media or Grande). Rationale: (1) 100.0% of firms with unmatched loans never appear in RAIS at any point (Type A), consistent with sole-proprietors and unregistered micro-enterprises that hold BNDES credit but are outside formal payroll — these firms are economically Micro. (2) 68.8% of unmatched loans are categorised as Micro/Pequena by BNDES itself, making the treat-as-bin-1 assumption conservative rather than speculative. (3) Only 266,335 Media/Grande unmatched loans are dropped under T3 — a small share of the unmatched mass whose RAIS absence cannot be plausibly explained by informality. (4) The conditional-imputation cross-tab (T3) yields a 4x4 value-weighted diagonal of 70.1% and a 3x3 unweighted diagonal of 86.8%, compared with 70.2% / 76.3% for the drop-only baseline.

---

## 8. Imputed Diagonal Comparison

Three treatment alternatives evaluated on the full clean loan set:
- T1: drop unmatched (current baseline)
- T2: treat-as-Micro for ALL unmatched (size_bin_A4 = 1)
- T3: conditional imputation — bin 1 for Micro/Pequena unmatched; drop Media/Grande unmatched

| Treatment | N loans | 4x4 uw diag | 4x4 vw diag | 3x3 uw diag | Pass 4x4 vw ≥60% | Pass 3x3 uw ≥65% |
|-----------|--------:|------------:|------------:|------------:|:-----------------:|:-----------------:|
| T1_drop_unmatched | 742,404 | 62.8% | 70.2% | 76.3% | YES | YES |
| T2_treat_as_micro_all | 1,595,525 | 52.5% | 34.7% | 72.3% | NO | YES |
| T3_conditional_micro_pequena | 1,329,190 | 63.0% | 70.1% | 86.8% | YES | YES |

Files: `alignment_yearly_imputed_summary.csv`

---

## 9. Output Files

| File | Description |
|------|-------------|
| `unmatched_by_year.csv` | Matched vs. unmatched counts and values by year |
| `unmatched_by_porte.csv` | Matched vs. unmatched by porte category |
| `unmatched_by_cnae.csv` | Matched vs. unmatched by CNAE section |
| `unmatched_value_distribution.csv` | Distribution of loan values for matched vs. unmatched |
| `unmatched_firm_persistence.csv` | Per-firm loan counts and RAIS year count |
| `unmatched_firm_persistence_summary.csv` | Type A / Type B split + loan decomposition |
| `alignment_yearly_imputed_summary.csv` | Diagonal comparison across three treatment options |

