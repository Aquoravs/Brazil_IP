# E1 Alignment — Year-Level (revised)
Generated: 2026-05-04 15:00:45

## Question

For every BNDES loan with known porte in year y, what A4 bin does the
borrower's RAIS n_employees in year y put it in? **Per-loan; no cycle;
no fall-back.** This is the cleanest test of whether RAIS-headcount and
BNDES-porte agree on firm size.

---

## 1. Headline metrics

- Loans after NA filtering: 1,653,310
- Matched to a RAIS firm-year:           742,404 (44.9%)
- Dropped (no RAIS obs that year):       910,906
- Cross-tab loans (porte + A4 known):    742,404

| Metric | Value | Threshold | Status |
|--------|------:|----------:|--------|
| **4×4 unweighted diagonal**            | **62.79%** | — | informational |
| **4×4 value-weighted diagonal**        | **70.20%** | ≥ 60% | **PASS** |
| **3×3 collapsed unweighted diagonal**  | **76.29%** | ≥ 65% | **PASS** |
| **3×3 collapsed value-weighted diag**  | **70.28%** | — | informational |

**Verdict: PASS**

---

## 2. 4×4 cross-tab (loan counts)

| Porte \ A4 | Micro (1) | Pequena (2) | Media (3) | Grande (4) | Row total |
|-------------|----------:|------------:|----------:|-----------:|----------:|
| **Micro** | 129,245 | 69,285 | 6,894 | 1,510 | 206,934 |
| **Pequena** | 30,956 | 75,931 | 46,383 | 1,445 | 154,715 |
| **Media** | 6,939 | 23,192 | 104,773 | 21,314 | 156,218 |
| **Grande** | 2,911 | 7,445 | 58,002 | 156,179 | 224,537 |

---

## 3. 3×3 collapsed cross-tab (loan counts)

| Porte \ A3 | MPME (1) | Media (2) | Grande (3) | Row total |
|-------------|---------:|----------:|-----------:|----------:|
| **MPME** | 305,417 | 53,277 | 2,955 | 361,649 |
| **Media** | 30,131 | 104,773 | 21,314 | 156,218 |
| **Grande** | 10,356 | 58,002 | 156,179 | 224,537 |

---

## 4. Top off-diagonal cells (4×4 unweighted)

  1. porte=Micro × A4=2 (n=69,285, 33.5% of porte-row)
  2. porte=Grande × A4=3 (n=58,002, 25.8% of porte-row)
  3. porte=Pequena × A4=3 (n=46,383, 30.0% of porte-row)
  4. porte=Pequena × A4=1 (n=30,956, 20.0% of porte-row)
  5. porte=Media × A4=2 (n=23,192, 14.8% of porte-row)

---

## 5. Files

- `alignment_porte_A4_4x4_unweighted_yearly.csv`
- `alignment_porte_A4_4x4_value_weighted_yearly.csv`
- `alignment_porte_A4_3x3_collapsed_yearly.csv`
- `alignment_summary_yearly.csv`

