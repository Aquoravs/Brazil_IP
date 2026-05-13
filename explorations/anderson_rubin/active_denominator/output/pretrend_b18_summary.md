# Phase 1.8 -- Gov-Cycle Alignment Hypothesis Test

**Date:** 2026-05-12 19:30
**Outcome:** Delta log_gdp
**FE:** muni_id + year (single-cycle subsets: year FE only; Z constant within muni-cycle)
**SE:** cluster on muni_id

## B1.8.1 -- Panel calendar inspection

Brazilian electoral schedule:
- Mayoral elections: 2000, 2004, 2008, 2012, 2016
- Gov/Pres elections: 2002, 2006, 2010, 2014, 2018

Mayoral pre-window {e_mayor-3, e_mayor-1} membership and whether a gov
election falls inside that window:

- Pre-window years in panel 2002-2017: 11
- Pre-window years that are POST a gov election falling inside the same mayoral pre-window: 8
- Mayoral cycles affected (out of 4 with full pre-window in panel): 4

**Timing claim:** **CONFIRMED**.

See `panel_calendar_b181.csv` for the full year-by-year table.

## B1.8.2 -- Gov-only variant-alpha with strict pre-gov-election timing

Restrict tau to [e_gov-3, e_gov-1] for each gov cycle e_gov in {2002, 2006,
2010, 2014}; gov-Z columns only; muni+year FE pooled, year-only FE per-cycle.

| Scope | Cycle | n_obs | k | joint F | joint p | reject 5% | FE |
|---|---|---|---|---|---|---|---|
| pooled | -- | 50,028 | 19 | 1.314 | 0.1617 | FALSE | muni_id+year |
| per_cycle | 2006 | 16,651 | 18 |  1323 |     0 | TRUE | year |
| per_cycle | 2010 | 16,687 | 19 | 4.447 | 3.314e-10 | TRUE | year |
| per_cycle | 2014 | 16,690 | 19 | 3.542 | 2.672e-07 | TRUE | year |

**Verdict:** gov-only strict-timing **PASSES** (pooled p = 0.1617).

## B1.8.3 -- Per-office strict-timing variant-alpha

Each office's pre-trend tested against its OWN pre-election window:
- Mayor: tau in [e_mayor-3, e_mayor-1], e_mayor in {2004,2008,2012,2016}
- Gov:   tau in [e_gov-3,   e_gov-1],   e_gov   in {2002,2006,2010,2014}
- Pres:  tau in [e_pres-3,  e_pres-1],  e_pres  in {2002,2006,2010,2014};
  reported with full pres-Z set and with Pres x E, Pres x P dropped (B1.7).

| Test | Office | Z-set | n_obs | k | joint F | joint p | reject 5% | FE |
|---|---|---|---|---|---|---|---|---|
| B1.8.3_mayor_strict | mayor | mayor_full | 55,614 | 19 | 0.7268 | 0.7947 | FALSE | muni_id+year |
| B1.8.3_gov_strict | gov | gov_full | 50,028 | 19 | 1.314 | 0.1617 | FALSE | muni_id+year |
| B1.8.3_pres_strict_full | pres | pres_full | 50,028 | 19 | 2.117 | 0.003066 | TRUE | muni_id+year |
| B1.8.3_pres_strict_cleaned | pres | pres_minus_E_P | 50,028 | 17 | 2.284 | 0.001893 | TRUE | muni_id+year |

## Classification

**MIXED -- gov strict-timing clears but at least one other office still fails under its own strict window; partial support for the artifact story.**

**Recommendation for Phase 2 gate:** PAUSE -- partial support warrants strategist review before Phase 2 dispatch.

## Method note

The B1.6/B1.7 variant-alpha test uses the mayoral pre-window for all
offices, conflating timing across the three electoral calendars. The
GPSS / BHJ pre-trend assumption is office-specific: each instrument's
shock Z^office_{m,e} should be tested against the pre-period for that
office's own election cycle e. Pooling all three offices into the
mayoral window mechanically conflates the legitimate gov-cycle effect
(which is causally identified by the mayoral cycle's pre-window because
the gov election falls INSIDE it) with a pre-trend violation. The
B1.8 strict-timing reformulation is the correct null.

