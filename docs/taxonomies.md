---
title: Taxonomies
status: active
date: 2026-05-12
purpose: Catalog of sector and size taxonomies used in AR exploration and production planning. The project front door remains docs/PROJECT_BLUEPRINT.md.
---

# Taxonomies

Purpose: separate taxonomy definitions, production status, evidence, and intended use. Start from [PROJECT_BLUEPRINT.md](PROJECT_BLUEPRINT.md).

Use-status labels: diagnostic only; supports next design decision; research building block; ready for production pipeline; superseded / do not use.

| Taxonomy | Definition | Production status | Research role | Build script / source | Evidence | Use status |
|---|---|---|---|---|---|---|
| `cnae_section` | 21 CNAE sections A-U from RAIS firm CNAE. | Implemented / production-compatible. | ACTIVE baseline and ROBUSTNESS basis. | Upstream RAIS/CNAE fields; consumed by scripts 41-54. | D1, D14, D15; diagnostics output. | ready for production pipeline |
| `custom_sector` / `sector_group` | 11 custom groups, including manufacturing splits and `XX`. | Implemented; naming transition still appears in docs. | ROBUSTNESS / LEGACY bridge to earlier outputs. | `scripts/R/3_instruments/30_build_sector_groups.R` | Pipeline outputs; older sector first-stage runs. | research building block |
| `policy_block_active` | Four active BNDES blocks: Agro, Ind, Infra, Serv; excludes `XX`. | Implemented for diagnostics and policy-block runs. | ACTIVE candidate component; possible final separate margin. | `scripts/R/3_instruments/30e_build_policy_block_mapping.R` | D12, D15, D23; A7 at `policy_block`. | supports next design decision |
| S2 | Two absolute firm-size bins. | Diagnostic only; not current production candidate. | EXPLORATORY size-family check. | Size-bin logic from diagnostic / 30c-style objects. | F1 size diagnostics. | diagnostic only |
| S3 | Three absolute firm-size bins: MPME, Media, Grande. | PRODUCTION-PENDING; no committed post-D28 crosswalk. | ACTIVE candidate component; initially separate from policy blocks under D28. | 30f-style production crosswalk pending; 30c uses existing size-bin machinery. | D16, D17, D19, D28; F1 size diagnostics. | supports next design decision |
| S4 | Four size bins. | Rejected for current production planning. | LEGACY / audit trail. | Diagnostic size-bin objects. | D16 F1 size diagnostics. | superseded / do not use |
| `policy_block_active x S3` | 12 active policy-block-by-size cells. | PRODUCTION-PENDING; not committed under D28. | ACTIVE top F1 diagnostic candidate, not production margin. | 30f-style production crosswalk pending. | D16 and D28; [f1_combined_report.md](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md). | supports next design decision |
| `cnae_section x S3` | 51 active CNAE-section-by-size cells. | PRODUCTION-PENDING robustness; not wired for production. | ROBUSTNESS candidate; higher instrument count. | Production/robustness crosswalk pending. | D16 and D28; [f1_combined_report.md](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md). | supports next design decision |
| standalone `size_bin` | Firm-size bins without sector crossing. | Implemented as diagnostic machinery; not preferred as sole margin. | EXPLORATORY / fallback admissible margin. | `scripts/R/3_instruments/30c_build_size_bin_mapping.R` | D17; F1 size diagnostics. | diagnostic only |
| `bndes_sector_size_bin` | BNDES macro sector x size terciles. | Legacy exploratory implementation. | LEGACY comparison only. | `scripts/R/3_instruments/30d_build_sector_size_bin_mapping.R` | Earlier exploration outputs. | superseded / do not use |
| BNDES product classifiers | Loan-side BNDES product or line classifications. | Inadmissible as production margins. | DESCRIPTIVE only if used to narrate loans. | Raw BNDES loan fields; no production margin script. | D14; [bndes_allocation_logic.md](strategy/bndes_allocation_logic.md). | superseded / do not use |
| Project-CNAE classifiers | BNDES project CNAE rather than firm RAIS CNAE. | Inadmissible as production margins. | DESCRIPTIVE only; optional A6 cross-tab. | Raw BNDES project fields; A6 optional. | D1, D14, D18. | superseded / do not use |

## Current Production Boundary

No taxonomy that requires a new production crosswalk should be treated as production-ready until D28 is resolved: Track 1 settles the instrument form, Track 2 commits the margin, and the resulting pipeline changes pass project verification. In particular, no new taxonomy requiring 30f-style work is production-ready at the current gate.
