# Phase 1.7 -- Governor-Instrument Pre-Trend Deep-Dive

**Date:** 2026-05-12 19:27
**Outcome:** Delta log_gdp
**FE / SE:** muni + year FE; cluster on muni_id (per-cycle gov tests drop muni FE because Z is constant within muni-cycle)

## B1.7.1 -- alpha-clearance after dropping Pres x E + Pres x P

Re-run variant-alpha with full Z minus {Z_pres_coalition_cycle_specific_E,
Z_pres_coalition_cycle_specific_P}.

| n_obs | k_instruments | joint F | joint p | rejects 5% | alpha clears? |
|---|---|---|---|---|---|
| 55,614 | 55 | 1.628 | 0.002257 | TRUE | NO (proceed to B1.7.2) |

## B1.7.2 -- by-office decomposition on cleaned Z

| Office | Z-set | n_obs | k | joint F | joint p | rejects 5% |
|---|---|---|---|---|---|---|
| pres | pres_minus_E_P | 55,614 | 17 | 1.463 | 0.0977 | FALSE |
| gov | full | 55,614 | 19 |  2.47 | 0.0003665 | TRUE |
| mayor | full | 55,614 | 19 | 0.7268 | 0.7947 | FALSE |

**Gov still the driver?** TRUE. **Gov only driver?** TRUE.

## B1.7.3.alpha -- Gov-cycle interaction

Gov-Z joint F, pooled and per ref_election cycle. Per-cycle specs use year FE only (Z constant within muni-cycle).

| Scope | Cycle | n_obs | k | joint F | joint p | rejects 5% |
|---|---|---|---|---|---|---|
| pooled | -- | 55,614 | 19 |  2.47 | 0.0003665 | TRUE |
| per_cycle | 2004 | 5,540 | 19 | 1.731 | 0.02787 | TRUE |
| per_cycle | 2008 | 16,678 | 18 |  7.16 | 1.047e-18 | TRUE |
| per_cycle | 2012 | 16,693 | 19 | 1.066 | 0.3793 | FALSE |
| per_cycle | 2016 | 16,703 | 19 |  4.46 | 3.002e-10 | TRUE |

**Cycle pattern:** PERSISTENT (3-4 of 4 cycles reject -> gov pre-trend is structural, not cycle-specific).

## B1.7.3.beta -- descriptive contamination at state x cycle level

Per (state, ref_election), mean |Gov-Z_future| across munis vs mean state pre-period Delta log_gdp. Correlations computed across states within each cycle and pooled across all state-cycle cells.

| Cycle | n_states | cor(|Z|, state pre-Delta log_gdp) | cor(signed Z, state pre-Delta log_gdp) |
|---|---|---|---|
| 2004 | 27 | 0.1533 | -0.08204 |
| 2008 | 27 | -0.06357 | -0.1933 |
| 2012 | 27 | -0.1134 | -0.01589 |
| 2016 | 27 | -0.02403 | 0.2872 |
| pooled | 108 | 0.06366 | -0.01075 |

## Limitations

- State-fiscal data (FINBRA aggregates: state-level expenditure / revenue / debt) are NOT on disk. The budget-cycle channel cannot be tested directly. Required for a follow-up: state-year fiscal panels matched to gov election cycles.
- Gov elections in Brazil are 2002, 2006, 2010, 2014, 2018; the analysis indexes by the mayoral cycle (2004, 2008, 2012, 2016) used in cycle_specific Z. A clean gov-cycle re-indexing would require rebuilding Z with a gov-specific cycle window.
- 'gov_shock_mag' is the row mean of |Gov-Z columns| over kept sections (K-1 sections). This is a magnitude proxy; the signed mean is also reported.

## Story classification

**Best-supported story:** C-spec (persistent across cycles + weak state-level cor -> likely specification artifact in instrument build).

Stories considered:
- A-anticipation: real pre-electoral political anticipation in the coalition shock.
- B-budget: state-level fiscal / political-credit cycle reverse-causally drives the alignment shock.
- C-spec: coding artifact in how Z is computed off lagged gov-party variables.

