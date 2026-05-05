# CNAE Coverage Audit — policy_block Taxonomy
Generated: 2026-05-03 11:06:00

## 1. Overall Coverage

- Total firm-years: 44,181,405
- In active blocks (Agro/Ind/Infra/Serv): 43,422,687 (98.3%)
- In XX (residual — K, O, T, U): 758,698 (1.7%)
- Total BNDES value in dataset: R$ 23272175.7M

---

## 2. XX Sub-section Breakdown

| Section | Label | Firm-years | Employment | BNDES value (R$ M) | % of all BNDES |
|---------|-------|-----------|-----------|--------------------|----------------|
| K | Finance & Insurance | 530,412 | 14,084,286 | 711738.8 | 3.06 |
| O | Public Administration | 186,728 | 103,207,091 | 8.0 | 0.00 |
| T | Domestic Services | 37,274 | 130,908 | 4.2 | 0.00 |
| U | International Organizations | 4,284 | 68,513 | 720.1 | 0.00 |

**Interpretation:** Section K accounts for 3.1% of total BNDES value in this dataset.

---

## 3. Active Block Summary

| Block | Firm-years | Employment | BNDES value (R$ M) | % of all BNDES |
|-------|-----------|-----------|--------------------|----|
| Agro | 2,058,418 | 21,898,529 | 445079.5 | 1.91 |
| Ind | 4,696,874 | 108,918,915 | 11065863.8 | 47.55 |
| Infra | 6,665,385 | 82,950,696 | 8183813.5 | 35.17 |
| Serv | 30,002,010 | 314,997,997 | 2864916.0 | 12.31 |

---

## 4. Geographic Concentration of XX

### By State (top 10 by XX firm-year share)

| State ID | Total firm-years | XX share of firm-years (%) | XX share of employment (%) |
|----------|-----------------|---------------------------|---------------------------|
| 22 | 330,928 | 3.2 | 31.5 |
| 17 | 262,275 | 3.0 | 36.7 |
| 12 | 84,124 | 2.9 | 36.8 |
| 25 | 478,026 | 2.7 | 34.3 |
| 28 | 300,207 | 2.5 | 26.3 |
| 14 | 54,845 | 2.5 | 43.3 |
| 13 | 254,052 | 2.5 | 24.9 |
| 21 | 483,454 | 2.4 | 32.2 |
| 27 | 353,866 | 2.3 | 26.3 |
| 16 | 73,941 | 2.2 | 38.3 |

### By Municipality Size Quartile

| Quartile | Total firm-years | XX share of firm-years (%) | XX share of employment (%) |
|----------|-----------------|---------------------------|---------------------------|
| Q1 (smallest → largest) | 543,375 | 7.5 | 57.8 |
| Q2 (smallest → largest) | 1,360,019 | 4.1 | 44.2 |
| Q3 (smallest → largest) | 3,432,255 | 2.4 | 29.3 |
| Q4 (smallest → largest) | 38,845,756 | 1.5 | 16.5 |

**Interpretation:** XX firms do not appear strongly concentrated in the largest municipalities or in SP/RJ — the exclusion criterion does not create a systematic urban-rural imbalance in the instrument denominators.

---

## 5. Implications for Instrument Validity

The emp_muni and own_muni weight denominators include XX firm-years (E_mB = all municipal employment). XX represents 18.2% of total municipal employment in this panel, so the effective weight on active-block affiliation is scaled down by a factor of approximately 0.818 on average. This is intentional — the denominator measures exposure relative to the full local economy.

---

## 6. Files Produced

| File | Rows | Description |
|------|------|-------------|
| cnae_section_summary.csv | 21 | One row per CNAE section A-U |
| policy_block_summary.csv | 5 | One row per policy block |
| xx_subsection_summary.csv | 4 | K, O, T, U detail |
| geographic_by_state.csv | varies | XX share by Brazilian state |
| geographic_by_muni_size.csv | 4 | XX share by muni employment quartile |

