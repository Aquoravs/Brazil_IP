# A0.4 — BNDES recipient-type audit (findings)

Phase 0 audit feeding D5 (recipient-class treatment) of the firm-support hybrid
implementation plan (`journal/plans/2026-05-12_firm_support_hybrid_implementation.md`).

## Headline (2002-2017, pre-PRIVADA-filter raw BNDES files)

| recipient_class       | share of total disbursement |
|-----------------------|----------------------------:|
| productive_firm       |                       71.6% |
| public_entity         |                       28.3% |
| financial_institution |                       0.10% |
| other                 |                     < 0.01% |

Source: `output/class_shares_overall.csv`. The 28.3% public-entity share
confirms D5: dropping public-administration recipients is material and must
happen before any firm-side aggregation.

## Multi-year FI double-counting check (2008/2010/2014)

Extended from the 2010-only baseline to bracket the PSI era. Overlap = CNPJs
that appear both as FI-borrower and as `fin_inst_cnpj` routing agent in the
same year. Escalation threshold: overlap volume > 0.05% of total credit.

| year | n_fi_borrowers | n_overlap | overlap_share_count | fi_volume_total (R$) | fi_volume_overlap (R$) | overlap_share_volume | dc_share_of_total_credit |
|-----:|---------------:|----------:|--------------------:|---------------------:|-----------------------:|---------------------:|-------------------------:|
| 2008 | 31  | 2 | 6.5% | 2.21e+09 | 5.46e+08 | 24.7% | 0.016% |
| 2010 | 41  | 3 | 7.3% | 5.62e+09 | 8.19e+08 | 14.6% | 0.018% |
| 2014 | 42  | 0 | 0.0% | 1.98e+09 |     0    |  0.0% | 0.000% |

Source: `output/fi_double_counting_multi_year.csv`.

**Conclusion:** no year exceeds the 0.05%-of-total-credit threshold; the
maximum (2010) is 0.018%. Double-counting from FI-as-borrower + FI-as-agent
overlap is not a material concern for the AR-test estimand, and no
escalation is required.

## Public-admin overlap

`output/public_admin_vs_main_overlap.csv` shows 2,544 (UF, muni, year) cells
present in both the main file's public-entity rows and the public-admin file,
suggesting the main file already captures most public-administration credit.
Use the public-admin file only as a residual check, not a replacement.
