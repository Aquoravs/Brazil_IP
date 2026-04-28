## Proposition 2 Tier Comparison

| Tier | Restrictions | Max |Delta beta| | Specs | Obs range |
|------|-------------|-------------------|-------|-----------|
| Gold | Synthetic DGP (C1-C6) | 1.0e-15 | 5 | 10,000 |
| Silver | Single-cell + balanced + no-rm + exact FE | 2.40e-01 | 8 | 13,000,619--14,144,058 |
| Bronze | Full sample + no-rm + exact FE | 1.36e-01 | 8 | 22,703,715--24,157,111 |

Gold tier from `verify_proposition2_synthetic.R`. Silver-Bronze gap is a joint effect (nested comparison, not decomposition). Silver residual = within-cell regressor heterogeneity (C6).
