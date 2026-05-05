---
title: Project Blueprint
status: living document
date: 2026-05-03
purpose: Front door of the project. The argument map — load-bearing claims, their test status, open angles, and the next concrete action.
---

# Project Blueprint

**Read this at the start of every session.** It tells you (a) what argument the paper makes, (b) which load-bearing claims are confirmed and which are still under test, (c) what work is in flight, and (d) what to do next.

This document is the *argument map*. It does **not** duplicate the state catalog.

| For… | Read… |
|---|---|
| Pipeline state, design decisions D1–D11, sector taxonomies, findings | [`docs/research_state.md`](research_state.md) |
| Active strategy memo for the AR test | [`logs/strategy/strategy_memo_ar_test.md`](../logs/strategy/strategy_memo_ar_test.md) |
| Current implementation plans | [`logs/plans/`](../logs/plans/) |
| Active exploration branch | [`explorations/anderson_rubin/`](../explorations/anderson_rubin/) |

---

## §1 Research question

Does political alignment between firm owners and the municipal/state/federal incumbent shift the **sectoral allocation** of BNDES credit at the municipality level, and does that politically driven reallocation affect municipal GDP? The inferential object is an Anderson–Rubin test of $H_0: \beta = 0$ on the GDP coefficient, with shift-share instruments built from firm-level alignment shocks projected onto a sector taxonomy.

---

## §2 Premise — what is already established

These are the *prior results* the rest of the argument builds on. Do not retest unless contradicted by new evidence.

| ID | Claim | Status | Evidence |
|---|---|---|---|
| **P1** | Firm-level political alignment → future BNDES credit access. The micro-mechanism is real and quantitatively meaningful. | **CONFIRMED** | `docs/research_state.md` §6 first bullet: cycle-specific F up to 103 on extensive margin. |
| **P2** | The Anderson–Rubin test is the chosen inferential framework for the muni-level second stage (handles weak/many instruments, weak-IV-robust). | **DECIDED** | `docs/research_state.md` §1; `logs/strategy/strategy_memo_ar_test.md`. |

---

## §3 Identification chain — the foundations under test

The paper rests on the chain **F0 → F1 → F2 → F3 → F4 → F5**. If any link breaks, the chain breaks. Status markers are: **CONFIRMED / UNDER TEST / OPEN / PARTIAL / PAUSED**.

| ID | Claim | Why load-bearing | Test | Status |
|---|---|---|---|---|
| **F0** | BNDES allocates credit across one or more **recognizable margins** (sector, firm size (based on revenue/income), export orientation, product line, …) that we can use as the aggregation dimension for the muni-level shock. | Without a margin BNDES actually uses, the muni-level shift-share IV is projecting on a dimension that is irrelevant to allocation, weakening the first stage by construction. | **A1**: institutional / documentary review of BNDES priority sectors, programs, and historical sector-targeting policy. | **CONFIRMED** (2026-05-03, revised same day). A1 memo establishes a key distinction: BNDES uses ≥6 dimensions internally (product line, sector, firm size, strategic-priority overlay, export orientation, region), but for muni-level aggregation a margin must be a **firm-side classifier** defined for every firm in RAIS or other available dataset — including non-borrowers. Loan-side (`bndes_product`) and purpose-side (`PSI eligibility`) classifiers are inadmissible. Active admissible set: **CNAE (and any derived taxonomies) + standalone `size_bin` + `CNAE × size_bin`** (new from A1; corrected D17 — absolute thresholds MPME/Média/Grande preferred over tertiles). Region used as control, not aggregation margin. See [`logs/strategy/bndes_allocation_logic.md`](../logs/strategy/bndes_allocation_logic.md). |
| **F1** | For at least one F0-margin, there is **meaningful within-muni × time variation** in the share of BNDES credit going to one bin vs. another. | If shares are flat within muni over time, muni FE absorb everything → no identifying variation → IV degenerates. *This is the most cheaply falsified link in the chain.* | **A2**: variance-decomposition diagnostic on every candidate margin: total variance vs. between-muni vs. within-muni-over-time. | **CONFIRMED** (2026-05-03 round 1; 2026-05-04 round 2 — D16). Round 1 supported F1 on the 3-margin × 2-denominator initial set (`cnae_section`, `policy_block`, `policy_block_active` × V1/V2). Round 2 added the size dimension: at year-level, A4 cycle-stability (19.9%) justifies the cycle-baseline rule (E0); A4 thresholds align with BNDES porte at year-level under T3 imputation (uw 3×3 = 87%, vw 4×4 = 70%; E1/E1b/E1c); A4 fails E2 coverage but A3 (MPME / Media / Grande) under V1 renormalization survives. **Production margin: `policy_block_active × A3` (12 active bins; mean share_within = 0.642 V1)**; secondary `cnae_section × A3` (51 active bins; mean share_within = 0.769) as robustness. Agro-conditional verdict (E3b): AGRO_OK; D15 holds. See [`f1_combined_report.md`](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) §8 for synthesis. |
| **F2** | The chosen margin can be measured **consistently** across (a) firm RAIS classification, (b) BNDES project label, (c) shock construction. | Mismatch (e.g., firm whose RAIS CNAE is "industry" but whose BNDES project is labeled "infrastructure") creates measurement error in the *direction of the treatment*, not just noise. | **A6**: cross-tabulate firm primary CNAE vs. BNDES project CNAE for borrowers. | **OPEN**. |
| **F3** | The firm-level alignment effect (P1) **aggregates** to a non-trivial muni-level shock when projected on the chosen margin. | The shift-share IV requires a non-degenerate aggregate shock; firm-level relevance is necessary but not sufficient. | Sector first-stage spec engine (script 53); already running for current taxonomies. | **PARTIAL** — sector first stage exists in current spec engine; aggregation validity depends on F1–F2. |
| **F4** | Alignment shifts are **conditionally exogenous** to muni economic shocks (the SSIV exclusion restriction). | Without it, the AR test rejects $H_0: \beta=0$ for the wrong reason. | **A1** also informs this (institutional review tells us *why* BNDES picks sectors — political vs. technocratic margins); **A8** (placebo on transfers / procurement, AR Phase 2). | **PARTIAL**. |
| **F5** | The denominator and weight construction in the SSIV do not load on excluded margins (XX share, public-sector intensity in small munis). | The CNAE coverage audit (2026-05-03) showed XX = **18.2% of muni employment** and **57.8% in Q1 munis** — the denominator choice is empirically nontrivial. | **A7**: weight horse race (full-economy vs. active-block-only denominator). | **PAUSED** — conditional on F1 returning at least one viable margin. |

### Read-down implication

- **F1 is logically prior to F3, F4, F5.** Any work on F5 (or refinements of F3, F4) is hostage to F1. If F1 fails on every candidate margin, the paper does not exist.
- **F0 expands the candidate set for F1.** Without F0, A2 only tests the four taxonomies we currently have; with F0, it can test margins BNDES actually uses (which may include some we haven't built yet).
- **F0 and F1 can run in parallel.** A1 (desk research) does not block A2 (data work on existing margins). Re-run A2 after A1 if new margins surface.

---

## §4 Open angles register

Each row is a candidate piece of work, tagged with which F-link it tests. Add new ideas here *immediately* in any session — the only way to prevent ideas from evaporating.

| ID | Idea | Tests | Priority | Status | Pointer |
|---|---|---|---|---|---|
| **A1** | BNDES institutional / documentary review: priority sectors, program structure, historical changes in sector targeting, geography of allocation. Web, BNDES annual reports, academic literature on BNDES governance. | F0, F4 | **HIGH (blocking)** | COMPLETED 2026-05-03 | [`logs/strategy/bndes_allocation_logic.md`](../logs/strategy/bndes_allocation_logic.md) |
| **A2** | Within-muni × time variation diagnostic on every candidate margin. Variance decomposition: $\sigma^2_{\text{total}} = \sigma^2_{\text{between-muni}} + \sigma^2_{\text{within-muni-between-year}} + \sigma^2_{\text{within-muni-year}}$. Output: median + p10/p90 of within-muni σ across munis, by margin. | F1 | **HIGH** | PARTIAL — round 1 (cnae_section, policy_block, policy_block_active × V1 / V2) COMPLETED 2026-05-03, F1 CONFIRMED on all 6 specs. Round 2 (`bndes_product`, `cnae_section × size_tertile` from A1; PSI/PBM/Profarma program-window indicators) PENDING. | [`explorations/anderson_rubin/diagnostics/within_muni_variation.R`](../explorations/anderson_rubin/diagnostics/within_muni_variation.R) → [`within_muni_variation_report.md`](../explorations/anderson_rubin/diagnostics/output/within_muni_variation_report.md) |
| **A3** | Add **firm size** as candidate margin (tercile or quartile). Advisor suggestion. | F0, F1 | MEDIUM | ~~COMPLETED 2026-05-04~~ — staged size-bin diagnostic (E0–E3c) selected `policy_block_active × A3` (3 size bins MPME / Media / Grande × 4 active blocks = 12 active bins) as the production margin. Secondary: `cnae_section × A3` (51 bins) as robustness. See D16. | [`logs/plans/2026-05-04_size-bin-diagnostics.md`](../logs/plans/2026-05-04_size-bin-diagnostics.md), [`f1_combined_report.md`](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) §8 |
| **A4** | Add **export orientation** (export-oriented vs. domestic) as candidate margin. Advisor suggestion. Requires SECEX or RAIS-export linkage. | F0, F1 | MEDIUM | PROPOSED — data source TBD | — |
| **A5** | Add **BNDES product / line** (lines of credit, programs) as candidate margin. The BNDES project itself carries metadata that may classify allocation more accurately than the borrower's RAIS CNAE. | F0, F1, F2 | MEDIUM | PROPOSED | — |
| **A6** | Reconcile firm primary CNAE (RAIS) vs. BNDES project CNAE. Cross-tab; report mismatch share weighted by loan value. Then decide: should the *project* CNAE drive the sector taxonomy? | F2 | MEDIUM | PROPOSED | — |
| **A7** | Weight horse race: full-economy denominator vs. active-block-only denominator (sums to 1 over Agro+Ind+Infra+Serv). Plus optional decomposition into within-active share and active-intensity scaler. | F5 | LOW (paused) | PLANNED — paused | [`logs/plans/2026-04-29_weight-horserace.md`](../logs/plans/2026-04-29_weight-horserace.md) |
| **A8** | Robustness regression including K (Finance) in the treatment set. Tests whether the alignment instrument *should* load on direct financial-sector credit. Either result is publishable. | F3, F4 | LOW | PROPOSED | — |
| **A9** | Trace the 20 NA-CNAE firm-years (R$31.9M, 18 BNDES borrowers, 2002–2014) upstream in the panel reconstruction pipeline. Likely a join failure. | data quality (cross-cutting) | LOW | PROPOSED | [`explorations/anderson_rubin/diagnostics/output/unmatched_cnae_diagnostic.csv`](../explorations/anderson_rubin/diagnostics/output/unmatched_cnae_diagnostic.csv) |
| **A10** | **AR identification alternatives for the composition/volume decomposition.** Four approaches to isolating the composition channel when both sector shares and aggregate muni-level disbursements are endogenous: (1) Pure AR — OLS on both; (2) Partial IV — instrument sector shares only, leave total as endogenous control; (3) Full IV — instrument both (total instrumented by sum of sector-specific instruments); (4) Mixed — OLS for shares, IV for total. Determines whether we can sweep out the volume channel or must instrument for it. Source: 2026-04-30 meeting. | F4, F5 | **HIGH** | PROPOSED | — |
| **A11** | **Mechanism puzzle: hiring vs. credit channel.** First stage shows instruments predict employment (F up to 265) but not loan amounts (F ~ 6). This may suggest the mechanism runs through hiring/labor allocation rather than credit allocation — firms connected to the incoming party hire more, rather than borrow more. Investigate once the baseline AR test is in place. Source: 2026-04-23 meeting. | F3, F4 | MEDIUM | PROPOSED — deferred until AR baseline complete | — |
| **A12** | **Instrument construction document.** Step-by-step document explaining instrument definition, construction, and aggregation at the sector level considering different weights. Covers: alignment shock definition, baseline weight variants (owner_count, employment, equal_firm, binary), sector-level projection, and muni-level aggregation. Source: 2026-04-30 meeting action item. | documentation (cross-cutting) | MEDIUM | PROPOSED | — |
| **A13** | **Verify real GDP deflator construction.** Check whether the current `gdp_real` variable was constructed using spatial deflators or a single national deflator. Affects interpretation of cross-muni comparisons. Source: 2026-04-17 meeting. | data quality (cross-cutting) | LOW | PROPOSED — do later | — |
| **A14** | **Test sensitivity to political affiliation timing window.** Compare (a) cycle-specific pooled `[e-4, e-1]` baseline (current), (b) last year's affiliation (t−1), (c) contemporaneous affiliation. Hypothesis: political affiliation is highly persistent ("stubborn") — firms rarely switch party ties. Using a longer or more stable affiliation window could increase the number of usable observations and sharpen signal detection without introducing new bias. Low priority until the AR baseline is established. | F3, F4 | LOW | PROPOSED | — |

---

## §5 Active branches

What is currently in flight in `explorations/`. Update the status when a branch closes (graduate to production, archive, or pause).

| Branch | Plan | Status |
|---|---|---|
| AR baseline implementation (`explorations/anderson_rubin/ar_baseline.R`) | [`logs/plans/2026-04-29_ar-baseline-implementation.md`](../logs/plans/2026-04-29_ar-baseline-implementation.md) | ACTIVE |
| Weight horse race (`explorations/anderson_rubin/weight_horserace.R`) | [`logs/plans/2026-04-29_weight-horserace.md`](../logs/plans/2026-04-29_weight-horserace.md) | PAUSED — pending F1 result (A2) |
| CNAE coverage audit (`explorations/anderson_rubin/diagnostics/cnae_coverage_audit.R`) | — | COMPLETED 2026-05-03 — outputs in `diagnostics/output/`; report in `cnae_coverage_report.md` |
| Within-muni × time variation diagnostic (`explorations/anderson_rubin/diagnostics/within_muni_variation.R`) | — | COMPLETED 2026-05-03 (round 1) — F1 CONFIRMED on all 3 initial margins × 2 denominators; report in `within_muni_variation_report.md`. Round 2 (A1 margins) pending. |

---

## §6 Decisions log

Append-only. New decisions get an ID and a one-line entry. Existing operational decisions D1–D11 are catalogued in [`docs/research_state.md`](research_state.md) §3 and are not duplicated here.

| ID | Date | Decision | Rationale | Source |
|---|---|---|---|---|
| **D12** | 2026-05-03 | XX sectors (K, O, T, U) excluded from the policy-block treatment set. The K (Finance) case is the load-bearing one — BNDES is itself a financial intermediary; K firms re-lend rather than absorb credit as final users. O (Public Admin), T (Domestic Services), U (Intl. Orgs) excluded as not commercial borrowers. | CNAE coverage audit shows K = 3.06% of BNDES value (R$712B); O is huge in employment (103M) but ~0% credit. Direct case for exclusion is theoretical (K is intermediary, not user); robustness check including K planned (A8). | This conversation; `cnae_coverage_audit.R` outputs |
| **D13** | 2026-05-03 | The **operative aggregation margin is to be determined empirically**, not committed a priori. CNAE-section is *one* candidate among (sector, firm size, export orientation, BNDES product line, …). The choice will be driven by F0 (which margins BNDES actually uses) and F1 (which margins have within-muni × time variation). | Without this, we are committing the paper to the CNAE margin before checking whether it is the right one. The firm-level result (P1) is margin-agnostic; the muni-level aggregation is not. | This conversation |
| **D14** | 2026-05-03 | **A1 memo produced; admissibility-based reframing of F0.** A margin is admissible iff it is a firm-side classifier defined for every firm in RAIS (including non-borrowers, the bulk of the universe), so that the baseline share $s_{m,s,t_0}$ is well-defined for every muni. Under this criterion, BNDES uses ≥6 internal dimensions, but only **two** are admissible *and* genuinely new for our panel: standalone `size_bin` and `cnae_section × size_bin`, both using absolute thresholds (MPME 0–49 / Média 50–499 / Grande 500+) approximating BNDES porte categories (corrected D17 — see note on standalone-size_bin ban). The originally proposed `bndes_product` is **inadmissible** (loan-side classifier; undefined for non-borrowers). PSI eligibility is **inadmissible** (purpose-defined, not CNAE-defined). Industrial-policy CNAE crosswalks (PBM Block 1–5, Profarma-CNAE, Prosoft-CNAE, P&G-supplier-CNAE) are admissible but redundant with raw CNAE; mention only, do not pursue. Region as control. The A2 candidate set is therefore: 3 sector taxonomies (already in panel) + 2 new (`size_bin` standalone, `cnae_section × size_bin`). The decision also formally settles the firm-CNAE vs. project-CNAE choice in favor of firm-CNAE — the firm-level channel is validated (P1), and firm-CNAE is the only classifier defined everywhere; A6 is therefore reframed as descriptive (informational about how BNDES labels its book), not as a design choice. | Without the admissibility criterion we would have aggregated on a loan-side classifier for which the muni-level baseline shares are undefined for the non-borrower majority of the RAIS universe. | [`logs/strategy/bndes_allocation_logic.md`](../logs/strategy/bndes_allocation_logic.md) |
| **D15** | 2026-05-03 | **F1 CONFIRMED on the initial 3-margin candidate set.** Within-muni × time variance decomposition supports F1 on every (margin × denom) cell tested: `cnae_section`, `policy_block`, `policy_block_active`, each under V1 (active-only denominator) and V2 (full-economy denominator). The active blocks Ind / Infra / Serv exhibit cross-muni median σ_within ≈ 0.26–0.33 and share_within ≈ 0.58–0.83 — comfortably above the SUPPORTED heuristic (med σ_within > 0.05 AND share_within > 0.20). Denominator choice (V1 vs V2) is **not material at the F1 link** — verdict is identical across both. F5 (denominator robustness) remains a separate question for the second-stage AR test, but is not load-bearing for first-stage existence. The IV is not degenerate at F1 on the existing taxonomies; A2 round 2 (new A1 margins) can refine, but the chain is no longer hostage to F1 on the current set. | [`within_muni_variation_report.md`](../explorations/anderson_rubin/diagnostics/output/within_muni_variation_report.md) |
| **D17** | 2026-05-05 | **Standalone `size_bin` is admissible as an aggregation margin; absolute thresholds (MPME/Média/Grande) preferred over tertiles.** The 2026-04-21 convention banning standalone `size_bin` conflated two separate questions: (1) regression weighting — drop `emp_weighted`, keep `emp_share_weighted` (still stands); (2) size as an SSIV aggregation margin — admissible, since `n_employees` is defined for every firm in RAIS. Preferred classification: absolute thresholds (MPME 0–49 / Média 50–499 / Grande 500+) mirroring BNDES's own revenue-based porte categories. Within-sector tertiles remain valid as robustness but are less institutionally grounded. D14's A2 candidate set corrected: `size_bin` (standalone) and `cnae_section × size_bin` replace `cnae_section × size_tertile`. D16's production margin `policy_block_active × A3` is unaffected (A3 already uses absolute thresholds). | This session 2026-05-05; `feedback_sector_classification_convention.md` |
| **D16** | 2026-05-04 | **Production aggregation margin: `policy_block_active × A3`.** Five-stage diagnostic (E0 stability → E1/E1b/E1c alignment → E2 coverage → E3 F1 within-muni → E3b Agro conditional) on three size-classifier candidates {A4 4-bin / A3 3-bin MPME-Media-Grande / A2 2-bin MPME-Big / B within-sector terciles} crossed with two sector dimensions {`cnae_section`, `policy_block_active`} under both V1 and V2 denominators. **Primary**: `policy_block_active × A3` — 12 active bins, mean share_within = 0.642 (V1); chosen for institutional alignment with BNDES policy targeting and substantially higher density of supported bins (3/12 = 25%) than `cnae_section × A3` (3/51 = 6%). **Secondary / robustness**: `cnae_section × A3` (51 active bins, mean share_within = 0.769). A4 4-bin scheme dropped at E2 (Micro 0.094, Media 0.098, Grande 0.044 below 0.10 share_munis_med threshold). Option B (within-sector terciles) excluded on interpretability grounds. Note: the earlier "size only within sectors" convention has been corrected (D17) — standalone size_bin with absolute thresholds is admissible. T3 conditional imputation accepted for E1: 51% of BNDES loans match no RAIS firm-year, but 100% are Type-A (never in RAIS at any year — informality / Cartão BNDES / non-firm), so unmatched stated-MPME loans are imputed to A3 bin 1; stated Media/Grande unmatched dropped. Caveats: (i) E2 nominal FAIL on Media + Grande survives only because V1 active-only renormalization preserves IV mechanic validity for thin bins; (ii) the 266k unmatched stated-Media/Grande loans (potential BNDES revenue-vs-headcount classification divergence) are a documented but accepted measurement caveat. | [`logs/plans/2026-05-04_size-bin-diagnostics.md`](../logs/plans/2026-05-04_size-bin-diagnostics.md), [`f1_combined_report.md`](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) §8, scripts `00b_size_bin_stability_yearly.R`, `01b_size_bin_alignment_yearly.R`, `01c_alignment_unmatched_diagnostic.R`, `02_size_bin_coverage.R`, `02b_size_bin_coverage_2bin.R`, `03_size_bin_f1.R`, `03b_agro_conditional_f1.R`, `03c_policy_block_size_f1.R`. |

---

## §7 Next action

**A2 round 2 is COMPLETED (2026-05-04, D16). F1 is fully CONFIRMED with the production margin chosen: `policy_block_active × A3` (12 active bins).** F1 is no longer blocking; the chain advances to F2 / F3.

**Track 1 (build production crosswalk).** Draft a successor to `scripts/R/3_instruments/30c_build_size_bin_mapping.R` (e.g., `30f_build_policy_block_size_mapping.R`) that produces the production crosswalk implementing the chosen margin: A3 thresholds (MPME 0–49 / Media 50–499 / Grande 500+) crossed with `policy_block` (Agro / Ind / Infra / Serv / XX excluded). Apply T3 imputation rule for unmatched-but-stated-Micro/Pequena BNDES loans. Downstream consumers: scripts `31` (exposure weights), `34` (shift-share instruments), `41` (muni panel). This is a separate plan, not part of this diagnostic.

**Track 2 (A6, parallel, descriptive only — unchanged from D14).** Cross-tabulate firm primary CNAE (RAIS) against BNDES project CNAE for borrowers; report mismatch share weighted by loan value. Output: a short descriptive note. Does not feed back into margin choice (settled at D14/D16).

**Track 3 (F3 sector first stage at the new margin).** Re-run sector first-stage spec engine (script `53`) at the chosen `policy_block_active × A3` aggregation to get muni-level instrument F-stats. Tests F3.

The next critical links in the chain are **F3** (does the muni-level shock have a non-trivial first stage at the chosen margin?) and **F4** (exclusion-restriction placebos). F2 is descriptive per D14 (firm-CNAE settled). F5 is paused per A7.

---

## §8 How to maintain this document

Three rules. They are the only thing that keeps this document useful.

1. **Any new idea, in any session, gets a row in §4 immediately.** No exceptions. Even half-formed ideas get an A-number — that is what stops them from evaporating.
2. **When an F-link's status changes (e.g., A2 runs and F1 becomes CONFIRMED or BLOCKED) → update §3 in the same commit, and add a one-line entry in §6.**
3. **The Next action (§7) is updated whenever the previous Next action is started or completed.** §7 is always actionable, never aspirational.

Promotion rules:
- An A-entry that becomes load-bearing (i.e., its result will reshape the chain) → promote to a new F-link in §3.
- An A-entry that is closed (done, abandoned, or superseded) → strike through with a date and reason. Do not delete (auditability).

The blueprint should be re-read at session start and edited at session end.
