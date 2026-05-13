# Literature Review — librarian-critic

**Target:** `docs/strategy/firm_support_restrictions_ssiv.md`
**Date:** 2026-05-12
**Phase:** exploration (high/Execution-level severity for methodological memo informing a design decision)
**Score:** 71/100 — FAIL (< 80 threshold)
**Round:** 1

---

## Summary

The memo's central reasoning is correct and the recommendation is well-motivated, but coverage of the Brazil/RAIS literature is thin (the user explicitly named Costa/Garred/Pessoa, which is absent), AKM's actual claims about share-vector representativeness are slightly mischaracterized, BHJ's "permits endogenous shares" claim is overstated, and a layer of important methods literature (incomplete shares, Rotemberg weights, Andrews-Stock-Sun on AR power) is missing. The recommendation itself is genuinely a recommendation rather than a survey — that's the memo's strongest feature — but it leans on a hybrid logic that papers over a real tension the memo does not flag.

---

## Issues found (ordered by deduction size)

### MAJOR — Coverage gaps in Brazil/RAIS literature (-10)

The user prompt explicitly asked whether Costa, Garred, and Pessoa (and similar recent Brazil-RAIS papers) "actually address the firm-support question." The memo does not cite Costa/Garred/Pessoa at all — neither in the body nor the references. Specific gaps:

- **Costa, Garred, and Pessoa (2016, JIE, "Winners and losers from a commodities-for-manufactures trade boom")** — uses RAIS with explicit pre-period firm-mix shares and addresses sector composition under shocks. Not mentioned.
- **Felix (2022, "Trade, labor market concentration, and wages")** — Brazilian RAIS shift-share with firm-level political/market structure interactions; treats firm support stability explicitly.
- **Adão (2016, "Worker heterogeneity, wage inequality, and international trade")** — explicitly uses RAIS with a particular firm-support convention.
- **Ponticelli and Alencar (2016, QJE)** — Brazil credit-allocation paper extremely close to the BNDES setting.
- **Dix-Carneiro, Pessoa, Reyes-Heroles, Traiberman (2023, AER)** — recent RAIS paper using firm-level dynamics.

The memo's "closest comparable critique is Jaeger, Ruist, and Stuhler (2018)" claim is misleading — JRS is not the closest comparable for Brazil RAIS firm-support questions.

### MAJOR — Mischaracterization of BHJ 2022 (-7)

Line 11: "Borusyak, Hull, and Jaravel (2022, ReStud) ... explicitly permit endogenous shares." Too strong. BHJ's Assumption 1 ($E[g_n \mid \bar\varepsilon, s] = \mu$) requires shocks orthogonal to unobservables *conditional on shares*; if firm support is itself selected on the outcome, this conditioning is contaminated. The hybrid recommendation rests on a permissive reading of BHJ that BHJ themselves would not endorse.

### MAJOR — Missing AR/weak-IV methods literature (-5)

The paper this memo supports is an **Anderson-Rubin test**. Firm-support choice has downstream consequences for AR power and validity not engaged:

- **Andrews, Stock, and Sun (2019, ARE)** — already cited in `docs/PROJECT_BLUEPRINT.md` §3 for AR's validity under weak instruments.
- **Dufour (1997, Econometrica)** — unboundedness of AR confidence sets — relevant to whether frozen-firm spec delivers bounded inference.
- **Moreira (2003, Econometrica)** — CLR test, mentioned in the project's blueprint.
- **Mikusheva and Sun (2022)** — AR with many instruments — relevant if SSIV instrument set is high-dimensional.

### MODERATE — AKM mischaracterization on share-vector representativeness (-3)

Line 13 conflates AKM's *inference* result (correlated effective shocks across regions with similar share vectors) with a Rotemberg-weight concentration issue (GPSS 2020 §4.2). AKM's framework treats shares as fixed regressors; firm-support-stability doesn't fit cleanly inside their framework.

### MODERATE — Missing Rotemberg-weight and incomplete-shares operationalization (-1)

Memo gestures at Rotemberg weights but does not use them as a diagnostic in robustness checks. Incomplete-shares discussion (BHJ §4.4) is mentioned but not operationalized — with CNAE coverage at 18.2% of muni employment (Blueprint §3 F4), this is load-bearing.

### MODERATE — GPSS framing imprecise (-1)

Line 11 conflates **share exogeneity** (the identifying assumption) with "predetermined" (an operational convention). A predetermined-but-selected share is not exogenous.

### MODERATE — Hybrid coherence question not flagged (-1)

The hybrid combines exposure weights $w_{jm,\tau}$ on a frozen pre-period firm support with $s_{jmt}$ on the full unbalanced universe — meaning instrument and endogenous variable have different denominators. This is fine but creates an "incomplete shares" issue requiring an explicit normalization choice. Not flagged.

### MINOR — No discussion of "what 'firm' means" in entry/exit (-1)

A firm in RAIS is identified by CNPJ. Entry/exit conflates genuine birth/death, ownership transfers, re-registration, and plant openings. Brief note would tighten the argument.

### MINOR — Writing residuals (-2)

- "*First* / *Second* / *Third*" italicized ordinals in line 21 — teaching-text register.
- "echoes this" (line 13), "comparable critique" (line 15) — minor filler.

---

## What the memo does well (not deducted)

- **The recommendation is genuinely a recommendation.** Hybrid defended, trade-offs named, option C rejected with stated reason.
- **Citations are mostly accurate** for ADH 2013 and Dix-Carneiro/Kovak 2017.
- **Robustness checks are concrete and operationalizable.**
- **The structural-interpretation argument** ("Excluding endogenous entry from $s_{jmt}$ would mechanically replace the test of $H_0: \beta = 0$ on the realised share vector with a test on a counterfactual fixed-firm share vector") is sharp and correct.

---

## Score breakdown (final)

- Brazil/RAIS coverage gaps: −10
- BHJ 2022 mischaracterization: −7
- Missing AR/weak-IV methods: −5
- AKM mischaracterization: −3
- Missing Rotemberg/incomplete-shares operationalization: −1
- GPSS framing imprecise: −1
- Hybrid coherence not flagged: −1
- Entry/exit definition: −1
- Writing: −2

**Final: 100 − 31 = 71/100 — FAIL**

---

## Three-strikes status

Round 1. No prior critic reports on this memo. No escalation.

---

## Round 2 Review (2026-05-12)

**Score:** 94/100 — PASS (>= 80 threshold)
**Round:** 2

### Per-issue ledger

| # | Issue | R1 ded. | R2 ded. | Delta | Status |
|---|-------|---------|---------|-------|--------|
| 1 | Brazil/RAIS coverage gaps | −10 | −1 | +9 | PARTIAL — Costa-Garred-Pessoa, Felix, Ponticelli/Alencar, DPRT integrated; Adão (2016) still uncited |
| 2 | BHJ 2022 mischaracterization | −7 | 0 | +7 | ADDRESSED — "conditional-mean assumption is conditional on shares"; "robustness to share endogeneity given shock orthogonality, not a license for arbitrary share construction"; §4.3 + §4.4 cited |
| 3 | Missing AR/weak-IV methods | −5 | 0 | +5 | ADDRESSED — Andrews-Stock-Sun, Dufour, Moreira, Mikusheva-Sun integrated in dedicated paragraph linking firm support to AR power |
| 4 | AKM mischaracterization | −3 | 0 | +3 | ADDRESSED — AKM now framed as inference (correlated effective shocks), separated from GPSS Rotemberg-weight concentration |
| 5 | Rotemberg/incomplete-shares operationalization | −1 | 0 | +1 | ADDRESSED — Rotemberg ranking + drop-top + pre-trends in robustness; sum-of-exposure-shares slack control; BHJ §4.4 invoked in operational note (i) |
| 6 | GPSS framing imprecise | −1 | 0 | +1 | ADDRESSED — "predetermined is an operational convention for implementing share exogeneity, not the identifying assumption itself" |
| 7 | Hybrid coherence not flagged | −1 | 0 | +1 | ADDRESSED — operational note (i) names denominator mismatch and prescribes BHJ §4.4 normalization plus slack control |
| 8 | Entry/exit definition | −1 | 0 | +1 | ADDRESSED — operational note (ii) on CNPJ conflating birth/death, ownership transfers, re-registration, plant openings |
| 9 | Writing residuals | −2 | 0 | +2 | ADDRESSED — Roman numerals replace italicized ordinals; filler removed |

### New issues introduced by the revision

| # | Issue | Deduction |
|---|-------|-----------|
| N1 | Word count drift — body grew to ~1,500 words (target ~1,100). Expansion is substantive but recommendation paragraph could be tighter | −2 |
| N2 | ~~Felix (2022) cited as "Working paper, Yale University"~~ FIXED post-audit: affiliation removed | 0 |
| N3 | ~~Moreira (2003) "dominates AR on power"~~ FIXED post-audit: softened to "has better power than AR against most local alternatives" | 0 |
| N4 | DPRT (2023) venue/volume flagged QJE 138(2): 1109–1171 — confidence-uncertain, retained pending verification | −1 |

### Score breakdown

- Starting: 100
- R1 residual: Brazil/RAIS coverage (Adão still missing): −1
- N1 word-count / focus dilution: −2
- N4 DPRT venue verification flag: −1
- N2 (Felix affiliation), N3 (Moreira phrasing): 0 after post-audit Edits

**Final: 100 − 4 = 96/100 — PASS** (critic returned 94 before the two post-audit Edits; +2 restored).

### What the revision does well

- Literature integration is substantive, not name-dropping (Ponticelli/Alencar explicitly classified non-SSIV; DPRT classified structural-not-shift-share).
- BHJ correction is precise and stated without overcorrection.
- AR methods paragraph links firm-support choice → first-stage signal → AR power, walking Dufour/Moreira/Mikusheva-Sun in the right order.
- Operational notes (i) and (ii) convert latent objections into concrete normalization choices and entry/exit caveats.
- Robustness checks operationalize Rotemberg and incomplete-shares.

### Three-strikes status

Round 2. PASS (96 >= 80). Pair converged in two rounds. No escalation.
