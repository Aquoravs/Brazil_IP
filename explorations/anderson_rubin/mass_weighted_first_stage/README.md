# Mass-Weighted Exposure: Sector First-Stage Horserace

Purpose: diagnostic horserace for exposure mass and LEV/DIF timing at the `policy_block` margin. This branch informs the AR methodology review; it does not commit a production margin, production weight, or production instrument.

Parent docs: [../../../docs/PROJECT_BLUEPRINT.md](../../../docs/PROJECT_BLUEPRINT.md), [../../../docs/research_state.md](../../../docs/research_state.md), and [../README.md](../README.md).

Use-status labels: diagnostic only; supports next design decision; research building block; ready for production pipeline; superseded / do not use.

## Status

COMPLETED exploration, started 2026-05-11 and summarized 2026-05-12.

Research use status: supports next design decision.

Production boundary: outputs are diagnostic / research-building evidence only. They are not production-pipeline inputs and should not be consumed by `scripts/R/` unless a later decision graduates a construction, implements it in the production pipeline, and verifies it.

## Decision Context

| Field | Value |
|---|---|
| Parent IDs | F2/F4, D23, D25, D27, D28 |
| Decision informed | Whether employment-mass exposure and DIF timing should enter the next methodology review. |
| Margin tested | `policy_block` only. |
| Outcome tested | `emp_share_jmt` at the sector x municipality x year unit. |
| Main owner artifact | [findings.md](findings.md) |
| Output manifest | [output/MANIFEST.md](output/MANIFEST.md) |

## Research Question

The branch compares three exposure-mass constructions and two shift timings:

| Dimension | Variants |
|---|---|
| Mass | BASE intensity; VAR-A owner-mass relative; VAR-B employment-mass relative. |
| Shift | LEV level alignment; DIF first-difference alignment. |
| Channels | M, MP, MG, MGP. |

The motivating question is whether clean employment mass improves first-stage prediction of sector employment shares, and whether DIF timing is viable for cross-office channels.

## Findings

Top-line result from [findings.md](findings.md):

- Keep VAR-A as the conservative recommendation.
- Treat VAR-B as evidence that employment mass contains signal, not as a production candidate in current form.
- VAR-B improves several per-channel first-stage diagnostics but fails the BJS-3 concentration guardrail.
- Promote DIF as a methodology candidate for cross-office channels under VAR-A; keep LEV for the mayor-only channel.
- Joint-channel Wald values are screening diagnostics, not literal SW/KP statistics from a full IV system.

## Inputs

| Input | Role | Boundary |
|---|---|---|
| Firm panel and pre-window employment objects | Build frozen-support employment-mass exposure. | Reused for diagnostics only. |
| `firm_baseline_exposures.qs2` and `alignment_shocks.qs2` | Rebuild channel-specific FA / alignment objects locally. | Local diagnostic build, not production rewrite. |
| A7 weight panel | Reuse VAR-A owner-mass weights. | A7 is settled at `policy_block` only. |
| Production sector instrument primitives | BASE comparison where compatible. | Compatibility check only; no production code changes. |

## Scripts

| Script | Purpose |
|---|---|
| `R/01_build_variant_b.R` | Build VAR-B employment-mass instruments and denominator robustness. |
| `R/01b_build_dif_shifts_existing_specs.R` | Build BASE and VAR-A LEV/DIF channel schema. |
| `R/02_horserace.R` | Run per-channel and joint Wald diagnostics. |
| `R/03_diagnostics.R` | Produce rank-correlation, concentration, disagreement, and DIF decomposition diagnostics. |

## Outputs

The load-bearing output files are documented in [output/MANIFEST.md](output/MANIFEST.md). The branch output folder also contains intermediate panels and large scratch-style diagnostic tables retained for reproducibility.

## Caveats

- `policy_block` is the diagnostic taxonomy here; this branch does not settle the post-D28 production margin.
- VAR-B is built from frozen pre-window support, but its current concentration profile is not acceptable for graduation.
- Clustered Wald diagnostics can be unstable with four policy-block clusters; interpretation should lean on rankings, concentration diagnostics, and the theory review.
- Shock-level AKM inference is not implemented in this branch.

## Graduation / Archive Decision

Archive condition: current branch is complete and should remain a reference.

Graduation condition: a later methodology decision must specify the mass and timing construction, commit the production margin, implement the construction in `scripts/R/`, and rerun verification gates. Until then, use this branch only as evidence for the next design decision.
