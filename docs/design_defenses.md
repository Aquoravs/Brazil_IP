---
title: Design Defenses
status: active
date: 2026-05-20
purpose: A bank of anticipated questions on the project's assumptions and design choices, each with a rigorous answer and pointers to the evidence. Use it to prepare for advisor meetings and referee reports.
---

# Design Defenses

This file records *why a design choice survives a hard question*. It is the
defense layer of the project's knowledge:

- [`decision_log.md`](decision_log.md) records **what** was decided and its status.
- [`PROJECT_BLUEPRINT.md`](PROJECT_BLUEPRINT.md) is the **argument map** (load-bearing claims).
- **This file** records the **reasoning that makes a choice defensible** when an
  advisor or referee pushes on it.

Add an entry whenever a question is raised — by an advisor, a referee, or a
self-audit — and answered with reasoning worth keeping. Each entry is an index
key (`Q1`, `Q2`, …) plus a plain-English question; the question is the primary
label.

## Entry format

```
## Q<n> — <plain-English question>
**Raised by:** advisor / referee / self-audit — <date>
**Short answer:** one or two sentences.
**Defense:** the reasoning.
**Evidence:** files, outputs, checks.
**Related decisions:** D-numbers.
```

---

## Q1 — The AR-test instruments and exposure control are piecewise-constant in 2-year blocks while the outcome varies yearly. Is that a problem?

**Raised by:** self-audit / advisor-style question — 2026-05-20

**Short answer:** No. It is not a bias or identification problem — it is the
ordinary structure of a difference-in-differences-style design where the
treatment switches on a coarse schedule. The only consequence is that the
effective identifying variation lives at the municipality-by-block level, and
inference must cluster by municipality — which the pipeline already does.

**Defense.**

*The timing, precisely.* The instrument is `Z^c_{jmt} = Σ_p w̃^c_{jmp,t} ·
Align^c_{mpt}` and the exposure control is `EC^c_{jm,t} = Σ_p w̃^c_{jmp,t}`.
Both inherit their time variation from the exposure window `T^{F,c}` (which
rolls forward when the channel's earliest relevant election rolls) and, for
`Z`, from the alignment shock. Brazilian mayoral and governor/president
elections are offset by two years, so:

- **Cross-office channels (M·G, M·P, M·G·P):** the earliest election entering
  the channel state rolls every 2 years, so the window — and therefore `EC`,
  and the share part of `Z` — is piecewise-constant in 2-year blocks
  (`{2006,07}`, `{2008,09}`, …, `{2016,17}`). Confirmed on the built weights:
  6 distinct `EC` values per cell, `EC(t) = EC(t+1)` within each block.
- **Pure mayoral channel (M):** only mayoral elections matter, so the window
  rolls every 4 years — 4 distinct `EC` values.
- M·G, M·P, M·G·P share an identical window (governor and president elections
  coincide), so their `w̃` and `EC` are identical; only `Align` differs.

The alignment shock changes on the same election boundaries, so `Z` is
block-constant on the same blocks. Instrument and control move on the same
coarse schedule.

*Why it is not a bias problem.* A regressor that is constant within blocks,
regressed on a yearly outcome with year fixed effects, is standard — it is the
structure of any DiD whose treatment switches coarsely. The coefficient `γ` is
identified from how block-level `Z` covaries with log GDP, net of municipality
and year fixed effects and the `EC`. The `EC` is predetermined for its own
block (window strictly pre-`t`; verified, `T_Fc_hi − t ∈ [−4,−1]`).
Block-constancy changes nothing about validity.

*The `EC` still does its job.* The `EC` exists to absorb share-component
confounding. The share `w̃` is block-constant by construction, so the
confounding the `EC` must absorb is also block-constant — the `EC` matches it
exactly at the block level. There is no within-block share variation for it to
miss.

*The real consequence — effective sample size.* Within a 2-year block, both
years carry mechanically identical `Z` and `EC`. The ~88,700 muni-years are not
88,700 independent observations: the instrument has only ~6 distinct values per
municipality (4 for M). The identifying variation lives at the
**municipality-by-block** level (~5,500 munis × 6 blocks). The row count
overstates the independent information; this matters for reading precision, not
validity.

*Why inference is still correct.* This is the Bertrand-Duflo-Mullainathan
serial-correlation situation: a treatment constant within blocks plus a highly
persistent outcome (log GDP). The remedy is to cluster standard errors at the
unit level, and `04_run_ar_regressions.R` uses `vcov = ~ muni_id`. Municipality
clustering is robust to arbitrary within-municipality correlation, which
absorbs both the perfect within-block duplication of `Z`/`EC` and the serial
correlation in log GDP. The AR Wald `F` is therefore correctly sized. (With iid
or muni-year standard errors, block-constancy would badly understate standard
errors — but the pipeline does not use those.)

*No collinearity between `Z` and `EC`.* Changing on the same calendar is not
collinearity: `Z` is alignment-signed, `EC` is a positive share-sum, and they
have different within-municipality paths. Confirmed — joint `Z + EC` runs
produced no collinearity drop (only the binned-`EC` robustness drops one
redundant bin level, which is expected).

*Optional, not required.* One could collapse the panel to municipality-by-block
(block-averaged log GDP) to make the effective sample explicit — the BDM
"collapse" remedy. It should give the same conclusion. Clustering already
delivers valid inference, so this is a presentational or robustness option, not
a needed fix.

**Evidence:** `explorations/anderson_rubin/instrument_combinations/findings.md`
§10 (EC adequacy audit, A1–A6); `R/A2_verify_ec.R` (predeterminedness check,
`T_Fc_hi − t ∈ [−4,−1]`); `R/A5_ec_functional_form.R` (joint `Z + EC` runs, no
collinearity drop); `ar_meeting_2026_05_13/R/00_helpers.R` (window calendar);
`ar_meeting_2026_05_13/R/04_run_ar_regressions.R` (`vcov = ~ muni_id`).

**Related decisions:** D31 (channel-specific pre-earliest-election window),
D32 (muni-relative weight + per-channel `EC`).
