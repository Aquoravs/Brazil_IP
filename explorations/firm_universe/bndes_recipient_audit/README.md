# BNDES Recipient-Type Audit (A0.4)

**Status:** COMPLETE (2026-05-12)
**Plan:** `journal/plans/2026-05-12_firm_support_hybrid_implementation.md` (Phase 0, A0.4)
**Informs:** D5 (public-entity inclusion in volume control; FI double-counting check)

## Goal

Classify every raw BNDES disbursement into productive-firm / public-entity /
financial-institution / other, sized by year and muni, to verify:

1. Coverage of public-entity flows (currently dropped by the script-11 PRIVADA filter).
2. Whether financial-institution intermediation flows are double-counted as
   both BNDES-to-bank and bank-to-borrower observations.
3. Whether the standalone `bndes_public_administration` raw file adds material
   coverage beyond what is already in the main automatic + non-automatic files.

## Method

`R/audit_bndes_recipients.R` re-reads the raw xlsx/csv files directly (the
`data/processed/bndes_loan_level.qs2` cache is post-PRIVADA-filter and unusable
for this audit). Classification is priority-ordered:

1. **public_entity** — `nature` starts with `PUBLICA` or `ADMINISTRACAO PUBLICA`,
   OR CNAE section is `O` (public administration).
2. **financial_institution** — CNAE division ∈ {64, 65, 66} (financial services).
3. **productive_firm** — `nature == "PRIVADA"` AND non-financial CNAE present.
4. **other** — residual (empty after the prefix-aware public-entity rule).

Window: 2002–2017 (matches AR-test sample).

## Outputs

- `output/class_shares_overall.csv` — total disbursement by class.
- `output/class_by_year.csv` — class × year volumes.
- `output/class_by_muni_aggregate.csv` — class-level coverage of municipalities.
- `output/other_class_diagnostics.csv` — diagnostic for the residual (now empty).
- `output/fi_double_counting_2010.csv` — FI-as-borrower vs FI-as-agent overlap (2010).
- `output/public_admin_vs_main_overlap.csv` — public-admin file vs main-file public-entity rows.
- `output/audit_summary.csv` — one-page summary metrics.
- `findings.md` — narrative findings + D5 escalation status.

## Reproduce

```sh
Rscript explorations/firm_universe/bndes_recipient_audit/R/audit_bndes_recipients.R
```

Runtime: ~5 minutes (raw xlsx parsing dominates).
