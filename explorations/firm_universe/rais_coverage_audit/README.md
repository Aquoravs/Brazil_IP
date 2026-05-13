# RAIS Coverage Audit (A0.1)

**Status:** A0.1 complete (2026-05-12). A0.2 and A0.3 pending.
**Phase:** Phase 0 of the firm-support hybrid implementation
(`journal/plans/2026-05-12_firm_support_hybrid_implementation.md`).
**Strategy memo:** `docs/strategy/firm_support_restrictions_ssiv.md`.

## Goal

Inventory the firm union panel by RAIS coverage class to quantify the gap
between the BNDES/Owner administrative universes and the current RAIS panel
on which the AR-test endogenous variable is built.

INVENTORY ONLY — no production-pipeline mutations. RAIS Negativa is not
locally available; this audit documents the gap so the user can decide
acquisition separately.

## Inputs

- `data/processed/rais_bndes_reconstructed.fst` — 44,181,405 firm-year-muni rows
- `data/processed/population_ibge.qs2` — muni-year IBGE population

## Outputs (under `output/`)

- `class_overall.csv` — global counts by coverage class
- `class_by_year.csv` — counts and within-year shares
- `class_by_cnae_section.csv` — counts and within-section shares
- `class_by_pop_tercile.csv` — counts and within-tercile shares
- `class_by_year_pop_tercile.csv` — year x tercile x class cross-tab

## Coverage classes

| Class | Rule |
|---|---|
| `in_rais_panel` | `in_rais == 1` |
| `bndes_only_no_rais` | `in_bndes == 1 & in_rais == 0` |
| `owner_only_no_rais` | `in_owner == 1 & in_rais == 0 & in_bndes == 0` |
| `other_no_rais` | residual (none observed) |
| `in_rais_dropped` | **N/A** — no upstream flag preserved (limitation, see findings) |

## How to run

```
Rscript explorations/firm_universe/rais_coverage_audit/R/audit_rais_coverage.R
```
