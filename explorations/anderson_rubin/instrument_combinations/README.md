---
title: AR Test Instrument Combinations
status: active
date: 2026-05-20
purpose: Answers the 2026-05-14 advisor questions on instrument combinations. The project front door remains docs/PROJECT_BLUEPRINT.md.
---

# AR Test Instrument Combinations

Purpose: answer why the AR-test instrument set uses mayor-crossed channels
(M, M·P, M·G, M·G·P) rather than standalone or additive M/G/P instruments, and
whether channels should be combined in one regression or run separately.

Parent docs: [../../../docs/PROJECT_BLUEPRINT.md](../../../docs/PROJECT_BLUEPRINT.md),
[../../../docs/research_state.md](../../../docs/research_state.md),
[../../ACTIVE_PROJECTS.md](../../ACTIVE_PROJECTS.md).

## Status

- Branch status: ACTIVE
- Started: 2026-05-20
- Last updated: 2026-05-20
- Owner artifact: `findings.md`
- Current research use status: supports next design decision

## Decision Context

| Field | Value |
|---|---|
| Parent A/D/F IDs | D25 (cross-office instrument set), D31 (exposure timing), F2 |
| Decision needed | Confirm or revise the cross-office per-channel instrument design for the AR test. |
| Current blocker | None. |
| Production boundary | Does not change `scripts/R/`. Illustrative Monte Carlo only; no production panel touched. |

## Inputs

| Input | Source | Role | Caveat |
|---|---|---|---|
| (none) | simulated DGP | Self-contained Monte Carlo | DGP assumes the project's maintained mechanism. |

## Scripts

| Script | Purpose | Writes |
|---|---|---|
| `R/ar_instrument_combination_sim.R` | Monte Carlo: size/power of the AR test under six instrument sets (assumes the mayor-crossed mechanism) | `output/ar_combination_power.csv`, `output/ar_combination_size_distortion.csv` |
| `R/agnostic_office_relevance_sim.R` | Monte Carlo: the saturated first stage recovers the true channel without assuming which office matters; cost of imposing the wrong restriction | `output/saturated_first_stage.csv`, `output/agnostic_ar_power.csv` |

## Findings

- The AR test is a joint Wald test on the reduced form; the instrument set is
  the test. Adding an instrument either raises power (valid + relevant), lowers
  it (valid + irrelevant), or breaks the test (invalid — false rejection).
- The old additive {M,G,P} stack is the weakest and most exposed set; D25's
  switch to cross-office channels is correct. `{M·G}` alone is a sharper test
  than `{M, G, M·G}` — main effects dilute the interaction.
- Relevance and validity are separate questions. The mayor-anchor is a
  *validity* argument, not a relevance claim. Which office is relevant is open
  and must be settled by data, not assumption.
- The saturated first stage (composition on all 7 channels) recovers the true
  channel regardless of which office matters. Imposing the mayor-restriction
  costs most of the power if the truth is president-only (23% vs 76%).
- Recommended: build all 7 channels; saturated first stage for relevance;
  per-channel placebo for validity; per-channel AR test on the
  relevant∩valid set. Do not pre-exclude G/P before the first stage runs.

## Caveats

- Simulation assumes the project's mechanism (mayor as local intermediary). It
  illustrates consequences; it does not prove the mechanism.
- Cross-section with homoskedastic errors; the real AR test has muni + year FE
  and muni-clustered SEs. FE and clustering do not change the three regimes.

## Graduation / Archive Decision

- Graduation condition: real-data checks in `findings.md` §7 run on the
  `policy_block` panel (relevance F of Z_G/Z_P; `{M·G}` vs `{M,G,M·G}` AR
  comparison; standalone G/P placebo reduced form).
- Archive condition: mark COMPLETED once those checks are run and the
  cross-office per-channel design is confirmed in the methodology PDF.
- Next action: present `findings.md` to advisors; decide whether to run the §7
  real-data checks.
