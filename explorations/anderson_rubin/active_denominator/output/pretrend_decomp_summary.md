# Phase 1.6 Pre-Trend Decomposition (delta_log_gdp)

**Date:** 2026-05-12 19:12
**Outcome:** delta_log_gdp (B1.6 variant alpha, operative violation)
**FE / SE:** muni_id + year FE; cluster on muni_id

## Baseline replication

| | n_obs | k | joint F | joint p | replicates B1.6? |
|---|---|---|---|---|---|
| Baseline (medium window, all offices, all cycles) | 55,614 | 57 | 1.612 | 0.002356 | YES |
| B1.6 target | 55,614 | 57 | 1.612 | 0.002356 | -- |

## (a) By election cycle

| Cycle e | pre-years | n_obs | k | joint F | joint p | reject 5% |
|---|---|---|---|---|---|---|
| 2004 | 2002,2003 | 5,540 | 56 | 17.31 | 1.965e-149 | TRUE |
| 2008 | 2005,2006,2007 | 16,678 | 55 | 20.42 | 7.495e-192 | TRUE |
| 2012 | 2009,2010,2011 | 16,693 | 57 |   2.7 | 8.865e-11 | TRUE |
| 2016 | 2013,2014,2015 | 16,703 | 57 |   4.3 | 6.202e-25 | TRUE |

## (b) By office

| Office | n_obs | k | joint F | joint p | reject 5% |
|---|---|---|---|---|---|
| mayor | 55,614 | 19 | 0.7268 | 0.7947 | FALSE |
| gov | 55,614 | 19 |  2.47 | 0.0003665 | TRUE |
| pres | 55,614 | 19 |  1.53 | 0.06488 | FALSE |

## (c) Window sensitivity

| Window | pre-years | n_obs | k | joint F | joint p | reject 5% |
|---|---|---|---|---|---|---|
| short | 2002,2003,2006,2007,2010,2011,2014,2015 | 38,934 | 57 | 1.851 | 0.0001009 | TRUE |
| medium | 2002,2003,2005,2006,2007,2009,2010,2011,2013,2014,2015 | 55,614 | 57 | 1.612 | 0.002356 | TRUE |
| long | 2002,2003,2005,2006,2007,2009,2010,2011,2013,2014,2015 | 55,614 | 57 | 1.612 | 0.002356 | TRUE |

## Interpretation

- **By-cycle:** cycle(s) rejecting at 5%: 2004, 2008, 2012, 2016.
- **By-office:** office(s) rejecting at 5%: gov.
- **Window:** window(s) rejecting at 5%: short, medium, long. Passing: none.

**Most diagnostic single takeaway:** by-office (rejection concentrated in a single office).

