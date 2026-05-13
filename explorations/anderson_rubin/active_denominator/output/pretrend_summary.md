# Proper tau-Baseline Pre-Trend Test (B1.6)

**Date:** 2026-05-12 18:59
**Margin:** cnae_section (policy_block deferred to Phase 2 C2.1.5)
**Pre-period years:** 2002, 2003, 2005, 2006, 2007, 2009, 2010, 2011, 2013, 2014, 2015

## Variant alpha -- outcome pre-trend (headline)

Regress pre-period outcome on FUTURE-cycle Z (the Z value realised in the
post-election cycle following the next mayoral election). Joint Wald F over
all office x sector future-Z columns; muni + year FE; cluster on muni_id.

| Outcome | n_obs | joint F | joint p | rejects 5% | verdict |
|---|---|---|---|---|---|
| log_gdp | 61,180 |  2.39 | 2.024e-08 | TRUE | FAIL |
| delta_log_gdp | 55,614 | 1.612 | 0.002356 | TRUE | FAIL |

## Variant beta -- per-sector share pre-trend (top-5 Rotemberg)

For each top-5 Rotemberg sector j, regress s^emp_{jm,tau} on the future-cycle
Z for that specific (office, sector); muni + year FE; cluster on muni_id.

| Office | Sector | beta | SE | t | p-value | reject 5% |
|---|---|---|---|---|---|---|
| pres | T | 0.1903 | 0.1113 | 1.711 | 0.08729 | FALSE |
| mayor | P | 0.002587 | 0.06011 | 0.04303 | 0.9657 | FALSE |
| gov | P | 0.03834 | 0.02593 | 1.479 | 0.1394 | FALSE |
| pres | E | -0.5388 | 0.1652 | -3.261 | 0.00112 | TRUE |
| pres | P | -0.1036 | 0.04368 | -2.373 | 0.0177 | TRUE |

**Variant beta:** 2 of 5 sectors reject at 5%. Pass criterion (>=3 of 5 do NOT reject): PASS.

## Overall verdict

**FAIL** -- alpha (delta_log_gdp) FAILS and beta passes.

## Note on the B1.4 contemporaneous-on-contemporaneous flags

B1.4 flagged Pres x T (p = 0.04) and Pres x E (p = 4e-4) on a within-period
regression of s_emp_jmt at year tau on Z at year tau. That tests whether the
contemporaneous instrument is correlated with the contemporaneous share,
i.e., it is mechanically a first-stage check on the share-vector itself, not
a pre-trend. The proper tau-baseline test above asks whether the FUTURE
instrument predicts the PRE-period outcome / share -- the actual GPSS / BHJ
pre-trend object. Comparing the two: any B1.4 flag that survives here is an
anticipation violation; any B1.4 flag that disappears here was the result of
the (legitimate) contemporaneous variation that the AR test relies on.

