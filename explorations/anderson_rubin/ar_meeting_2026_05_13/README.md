---
title: Updated AR Test Results for the 2026-05-14 Meeting
status: ACTIVE
date: 2026-05-13
purpose: Updated AR test under Variant A muni-relative owner-share weights with pre-earliest-election windows, for the meeting on 2026-05-14.
---

# AR Meeting 2026-05-13 — Variant A weights, pre-earliest windows

Purpose: Produce two parallel Beamer slide pairs (one per taxonomy: `policy_block` and `size_bin`) reporting the Anderson-Rubin test of `H_0: beta = 0` on sector employment shares, constructed under Variant A muni-relative owner-share weights with channel-specific pre-earliest-election windows (Variant F timing).

Parent docs: [PROJECT_BLUEPRINT.md](../../../docs/PROJECT_BLUEPRINT.md), [office_specific_exposure_weights.md](../../../docs/strategy/office_specific_exposure_weights.md), [ar_test_specification.tex §2.3](../../../docs/methodology/ar_test_specification.tex).

Use-status labels: diagnostic only; supports next design decision; research building block; ready for production pipeline; superseded / do not use.

## Status

- Branch status: ACTIVE
- Started: 2026-05-13
- Last updated: 2026-05-13
- Owner artifact: `journal/meetings/2026-05-14/slides.tex`
- Current research use status: supports next design decision (AR test design discussion at 2026-05-14 meeting)

## Decision Context

| Field | Value |
|---|---|
| Parent A/D/F IDs | D24 (volume control), Variant F (office memo), Variant A (spec §2.3) |
| Decision needed | Whether AR rejects the null under the new primary weight convention |
| Current blocker | None — all upstream primitives in `data/processed/` |
| Production boundary | Does not modify `scripts/R/`. New artifacts live in `explorations/anderson_rubin/ar_meeting_2026_05_13/output/` and `journal/meetings/2026-05-14/`. |

## Inputs

| Input | Source | Role | Caveat |
|---|---|---|---|
| `owner_aff_standardized.qs2` | `data/processed/` | L_{f,p,s} — owner-year counts by firm × party × year | Sparse for small munis |
| `firm_panel_for_regs.qs2` | `data/processed/` | F(j,m) — firm-muni-year-sector membership in RAIS | RAIS universe; cycle baselines |
| `alignment_shocks.qs2` | `data/processed/` | Align^c_{mpt} for c in {M, M·P, M·G, M·G·P} | Coalition-based per L5 |
| `policy_block_mapping.qs2` | `data/processed/` | cnae_section → policy_block (K=4) | 4 levels: Agro / Ind / Infra / Serv |
| `size_bin_mapping.qs2` | `data/processed/` | firm_id × election_cycle → size_bin (K=3) | Cycle-specific; size_bin in {1,2,3} = MPME / Média / Grande |
| `muni_panel_for_regs_policy_block.qs2` | `data/processed/` | log_gdp, pib_real, total_bndes_real | Source of vol_ratio |
| `emp_share_panel_policy_block.qs2` | `data/processed/` | s_emp_jmt for hold-out determination | Contemporaneous variant |

## Scripts

| Script | Purpose | Writes |
|---|---|---|
| `R/00_helpers.R` | Channel windows, taxonomy switches, column-name helpers | sourced only |
| `R/01_build_variant_a_weights.R` | Build w_tilde^{c,own}_{jmp,t} for both taxonomies | `weights_variant_a_<tax>.qs2` |
| `R/02_build_instruments_ec.R` | Stack Z^c_{jmt} and per-cell EC^c_{jm,t} | `Z_variant_a_<tax>.qs2`, `EC_variant_a_<tax>.qs2` |
| `R/03_build_muni_ar_panel.R` | Merge Z's + EC + log_gdp + vol_ratio | `muni_panel_ar_<tax>.qs2` |
| `R/04_run_ar_regressions.R` | Loop 4 channels × 4 specs per taxonomy | `ar_summary_<tax>.csv`, `ar_table_fstats_<tax>.tex`, coef pair tex |
| `R/05_build_slides.R` | Emit Beamer body per taxonomy | `slides_body_<tax>.tex` |

## Outputs

| Artifact | Use status | Notes |
|---|---|---|
| `output/weights_variant_a_<tax>.qs2` | research building block | (muni × year × channel × sector × party) → w_tilde |
| `output/Z_variant_a_<tax>.qs2` | research building block | Z^c_{jmt} long format |
| `output/EC_variant_a_<tax>.qs2` | research building block | EC^c_{jm,t} long format |
| `output/muni_panel_ar_<tax>.qs2` | research building block | Regression-ready wide panel |
| `output/ar_summary_<tax>.csv` | supports next design decision | 16 rows per taxonomy |
| `output/ar_table_fstats_<tax>.tex` | supports next design decision | F-stat grid |
| `output/ar_table_coefs_<tax>_pair1.tex` | supports next design decision | Coefficients M, M·P |
| `output/ar_table_coefs_<tax>_pair2.tex` | supports next design decision | Coefficients M·G, M·G·P |

## Findings

To be populated after Stage E verification.

## Caveats

- New code path (not the production weight builder). The muni-denominator `bar L^{c,affil}_{m,t}` must sum over all sectors and all parties — verified in `01_build_variant_a_weights.R`.
- Pre-earliest window for the M channel collapses to mayoral window. For year t = 2002 the mayoral window is [1996, 1999] which intersects [2002, 2017] as empty; such cells are dropped from the affected channel's panel.
- S3 taxonomy (size_bin, K=3) leaves only K-1=2 instruments per channel after the hold-out — flag explicitly in the bottom-line slide.

## Graduation / Archive Decision

- Graduation condition: User approves the Variant F + Variant A convention for the production pipeline.
- Archive condition: Convention superseded by a later decision in the AR-test design discussion.
- Next action: Compile slides for the 2026-05-14 meeting and present.
