# E2 Variant — 2-bin scheme A2 = {MPME (0-49), Big (50+)}
Generated: 2026-05-04 19:40:41

## Question

Does collapsing Media+Grande into a single Big bin (50+) salvage coverage?
Built by aggregating `coverage_cells_optionA4.csv` from 02_size_bin_coverage.R;
no re-run of the 15-min cell build.

---

## Per-bin coverage

| Bin | n_cells_total | n_cells_with_borrower | share_cells | share_munis_borrower_med | p50 n_borr | share_thin | struct_thin? |
|-----|--------------:|----------------------:|------------:|-------------------------:|-----------:|-----------:|:-------------|
| MPME (1) | 823,289 | 118,607 | 14.4% | 0.548 | 1 | 81.6% | no |
| Big (2) | 582,345 | 47,902 | 8.2% | 0.273 | 1 | 88.4% | no |

---

## Headline

- Overall thin-cell share (populated cells with n_borrowers<5): **83.6%**
- Structurally thin bins (share_munis_borrower_med < 0.10): **none**
- **Verdict: THIN_BIN_OK**

---

## Reading vs. A4 / A3

Compared to the per-bin numbers in `coverage_report.md` (E2 main):

- A4 Grande: share_munis_borrower_med = 0.044 (FAILED)
- A4 Media:  0.098 (FAILED, just under)
- A4 Pequena: 0.123 (passed)
- A4 Micro:   0.094 (FAILED, just under)
- A3 MPME:   0.118 (passed)
- A3 Media:  0.098 (FAILED)
- A3 Grande: 0.044 (FAILED)

If A2's MPME and Big both clear 0.10, this is the cleanest BNDES-interpretable
scheme that survives E2.

