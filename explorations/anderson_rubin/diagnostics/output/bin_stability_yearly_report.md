# Bin Stability — Year-Level (E0 revised)
Generated: 2026-05-04 14:23:12

## Question

How often does a firm's size-bin classification change year-over-year
across the 2002–2017 RAIS panel, under each candidate rule (A4, A3, B)?

**No fall-back.** Each (firm, year) is binned from that year's observed
`n_employees` directly. A firm contributes to migration metrics only
for years in which it appears in RAIS.

---

## 1. Top-line numbers

| Option | Multi-year firms | Ever changed | Share changed | YoY change rate |
|--------|-----------------:|-------------:|--------------:|----------------:|
| **A4** | 4,899,745 | 975,094 | **19.90%** | 6.54% |
| **A3** | 4,899,745 | 161,473 | **3.30%** | 1.01% |
| **B**  | 4,899,744 | 2,596,087 | **52.98%** | 19.99% |

A4 movers: **1,012,598 up**, **891,834 down**, **31,594 skip-bin** (|Δbin|≥2; 1.66% of all A4 yoy moves).

- **`share_firms_ever_changed`** = share of firms with ≥ 2 RAIS-observed years
  whose bin is not constant across all observed years.
- **`yoy change rate`** = share of consecutive (year, year+1) firm pairs where
  the bin changed. Picks up high-frequency churn that the lifetime metric hides.

---

## 2. A4 year-on-year transition matrix (aggregate, all year pairs)

Rows = bin in year t, columns = bin in year t+1.

| From \ To | Micro | Pequena | Media | Grande |
|------------|------:|--------:|------:|-------:|
| **Micro** | 22,055,416 | 853,687 | 11,029 | 413 |
| **Pequena** | 756,877 | 4,163,924 | 133,504 | 420 |
| **Media** | 18,761 | 105,435 | 878,903 | 13,545 |
| **Grande** | 388 | 583 | 9,790 | 127,018 |

_Diagonal = firms that stay in the same bin from year t to year t+1._

---

## 3. Distribution of distinct bins per firm

How many distinct bins does each multi-year firm pass through?

**A4:**

| n_distinct_bins | N firms | Share |
|----------------:|--------:|------:|
| 1 | 3,924,651 | 80.10% |
| 2 | 901,516 | 18.40% |
| 3 | 72,091 | 1.47% |
| 4 | 1,487 | 0.03% |

**A3:**

| n_distinct_bins | N firms | Share |
|----------------:|--------:|------:|
| 1 | 4,738,272 | 96.70% |
| 2 | 156,793 | 3.20% |
| 3 | 4,680 | 0.10% |

**B:**

| n_distinct_bins | N firms | Share |
|----------------:|--------:|------:|
| 1 | 2,303,657 | 47.02% |
| 2 | 1,865,961 | 38.08% |
| 3 | 730,126 | 14.90% |

---

## 4. Verdict

Under A4, 19.90% of multi-year firms ever change bin — below the 20% threshold. **Lifetime-mean rule is defensible.**

Note that A3 and B should be read alongside A4. If A4 is unstable but A3 is
(near-)constant per firm, the cycle/year structure is mostly absorbing
Micro/Pequena boundary noise, not real growth. If B is much more migratory
than A4, within-sector rank shifts dominate absolute-level movement.

---

## 5. Files written

- `bin_stability_yearly_summary.csv`
- `bin_stability_yearly_{A4,A3,B}_distribution.csv`
- `bin_stability_yearly_{A4,A3,B}_transitions.csv`  (long format, year-on-year)
- `bin_stability_yearly_report.md` (this file)

