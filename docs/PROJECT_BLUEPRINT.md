---
title: Project Blueprint
status: living document
date: 2026-05-06
purpose: Front door of the project. The argument map — load-bearing claims, design decisions, key findings, and the next concrete action.
---

# Project Blueprint

**Read this at the start of every session.** It tells you (a) what argument the paper makes, (b) which load-bearing claims are confirmed and which are still under test, (c) all design decisions D1–D23, (d) key findings, and (e) what to do next.

| For… | Read… |
|---|---|
| Commands, pipeline architecture, spec engine dims | [`CLAUDE.md`](../CLAUDE.md) |
| Active strategy memo for the AR test | [`docs/strategy/ar_test_strategy.md`](../docs/strategy/ar_test_strategy.md) |
| Current implementation plans | [`journal/plans/`](../journal/plans/) |
| Active exploration branch | [`explorations/anderson_rubin/`](../explorations/anderson_rubin/) |
| Variable dictionary, data documentation | [`README.md`](../README.md) |

---

## §1 Research question

Does a politically driven exogenous shock to the **sectoral composition of local economic activity** affect municipal GDP, beyond the aggregate volume effect? The full causal chain is:

> Political turnover shock → politically connected firms in some sectors receive marginally more BNDES credit → employment in those sectors expands → the sectoral composition of economic activity within the municipality shifts → municipal GDP changes.

The inferential object is an Anderson–Rubin test of $H_0: \beta = 0$ on the GDP coefficient in a structural equation that places **sector employment shares** (as the best available proxy for the sectoral distribution of local economic activity) on the right-hand side, with shift-share instruments built from firm-level alignment shocks projected onto a sector taxonomy. BNDES credit allocation is the mechanism that transmits the political shock to employment composition — one link in the chain — not the estimand.

**Current focus:** Policy evaluation via AR test. F0 is confirmed, F1 is confirmed, and the production aggregation margin is `policy_block_active × S3`. The current bottleneck is **F2** (first-stage relevance at the chosen production margin). F3 exclusion/placebo work is partial. F4 denominator and weight robustness is partially addressed at the `policy_block` margin (A7 closed) but not yet at the size-crossed margin.

**Channels in the local economy:** (1) **composition channel** — the sectoral distribution of employment (and, by extension, economic activity) within a municipality. This is the channel of interest. The politically driven exogenous shock to BNDES credit reallocation is what generates the variation in this distribution. (2) **volume channel** — total BNDES disbursements per municipality normalised by initial municipal GDP (a unit-free ratio; specification subject to revision after theory/math review of the econometrics). This is the aggregate level effect, held constant in the second stage so the test isolates the composition effect from the volume effect. See D10 and A10 for the four candidate identification approaches that operationalise the composition/volume decomposition.

---

## §2 Premises — what is already established

Do not retest unless contradicted by new evidence.

| ID | Claim | Status | Evidence |
|---|---|---|---|
| **P1** | Firm-level political alignment → future BNDES credit access. The micro-mechanism is real and quantitatively meaningful. | **CONFIRMED** | Cycle-specific F up to 103 on extensive margin (see §8 Findings). |
| **P2** | The Anderson–Rubin test is the chosen inferential framework for the muni-level second stage (handles weak/many instruments, weak-IV-robust). | **DECIDED** | `docs/strategy/ar_test_strategy.md`. |

---

## §3 Identification chain — the foundations under test

The paper rests on the chain **F0 → F1 → F2 → F3 → F4**. F0, F1, F3, F4 are validity foundations — if any breaks, the chain breaks. F2 is an informativeness/power check (D20): it does not threaten validity under the AR framework, but its failure would leave the test uninformative. Status markers: **CONFIRMED / UNDER TEST / OPEN / PARTIAL / PAUSED / RETIRED**.

| ID | Claim | Why load-bearing | Test | Status |
|---|---|---|---|---|
| **F0** | BNDES allocates credit across one or more **recognizable margins** (sector, firm size, …) that we can use as the aggregation dimension for the muni-level shock. | Without a margin BNDES actually uses, the muni-level shift-share IV projects on a dimension irrelevant to allocation, weakening the first stage by construction. | **A1**: institutional/documentary review of BNDES priority sectors, programs, and historical sector-targeting policy. | **CONFIRMED** (2026-05-03). A1 memo establishes the admissibility criterion: a margin must be a firm-side classifier defined for every firm in RAIS (including non-borrowers). Loan-side (`bndes_product`) and purpose-side (PSI eligibility) classifiers are inadmissible. Active admissible set: **CNAE (and derived taxonomies) + `size_bin` + `CNAE × size_bin`** (absolute thresholds MPME/Média/Grande preferred over tertiles — D17). Size labels: S2 (2-bin), S3 (3-bin), S4 (4-bin). See [`docs/strategy/bndes_allocation_logic.md`](../docs/strategy/bndes_allocation_logic.md). |
| **F1** | For at least one F0-margin, there is **meaningful within-muni × time variation** in the share of BNDES credit going to one bin vs. another. | If shares are flat within muni over time, muni FE absorb everything → no identifying variation → IV degenerates. *This is the most cheaply falsified link in the chain.* | **A2**: variance-decomposition diagnostic on every candidate margin. | **CONFIRMED** (2026-05-03 round 1; 2026-05-04 round 2 — D16). Round 1 supported `cnae_section`, `policy_block`, `policy_block_active` under V1/V2 denominators. Round 2 added size: S4 fails E2 coverage; S3 (MPME/Media/Grande) under V1 renormalization survives. **Production margin: `policy_block_active × S3`** (12 active bins; mean share_within = 0.642 V1); secondary `cnae_section × S3` (51 active bins; mean share_within = 0.769). See [`f1_combined_report.md`](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) §8. |
| **F2** | The firm-level alignment effect (P1) **aggregates** to a non-trivial muni-level shock when projected on the chosen margin. | **Informativeness, not validity.** Under AR (P2), a weak first stage does not invalidate inference — AR has correct size regardless of instrument strength (Andrews, Stock & Sun 2019). But it renders the test uninformative: the AR confidence set becomes unbounded (Dufour 1997). F2 is therefore a **power check**, not a validity gate. With $K = 12$ instruments (primary margin), AR power depends on $\mu^2/K$; CLR (Moreira 2003) may complement AR in power for $K > 1$. | AR confidence set boundedness at the chosen margin; sector first-stage F-stats remain a useful diagnostic for *why* the AR CI may be wide. | **PARTIAL** — reframed from validity gate to informativeness check per D20. Not yet tested at `policy_block_active × S3`. |
| **F3** | Alignment shifts are **conditionally exogenous** to muni economic shocks (the SSIV exclusion restriction). | Without it, the AR test rejects $H_0: \beta=0$ for the wrong reason. | **A1** (institutional review of why BNDES picks sectors); **A8** (placebo on transfers/procurement, AR Phase 2). | **PARTIAL**. |
| **F4** | The denominator and weight construction in the SSIV do not load on excluded margins. | The CNAE coverage audit (2026-05-03) showed XX = 18.2% of muni employment and 57.8% in Q1 munis — the denominator choice is empirically nontrivial. | **A7**: weight horse race (full-economy vs. active-block-only denominator). | **PARTIAL** at the `policy_block` margin (2026-05-05, A7 closed). Production winner = `w_owners_muni_univ` (Tier C, F_kp = 59.56 under C1_FE). Size-crossed `policy_block_active × S3` margin not yet addressed — Track 4 graduation. |

### Read-down implication

- **F1 is logically prior to F2, F3, F4.** Any work on F4 (or refinements of F2, F3) is hostage to F1.
- **F0 expands the candidate set for F1.** Without F0, A2 only tests taxonomies we already have; with F0, it can test margins BNDES actually uses.
- **F2 is an informativeness check, not a validity gate (D20).** F2 failure under AR means the test is valid but uninformative — the AR confidence set will be correct but unbounded. F2 is tested *as a byproduct* of running the AR test itself.

---

## §4 Open angles register

Each row is a candidate piece of work. Add new ideas here *immediately* in any session — the only way to prevent ideas from evaporating.

| ID | Idea | Tests | Priority | Status | Pointer |
|---|---|---|---|---|---|
| **A1** | BNDES institutional/documentary review: priority sectors, program structure, historical changes in sector targeting. | F0, F3 | HIGH | COMPLETED 2026-05-03 | [`docs/strategy/bndes_allocation_logic.md`](../docs/strategy/bndes_allocation_logic.md) |
| **A2** | Within-muni × time variation diagnostic on every candidate margin. Variance decomposition. | F1 | HIGH | PARTIAL — round 1 COMPLETED 2026-05-03 (F1 CONFIRMED on cnae_section, policy_block, policy_block_active). Round 2 (size-bin margins) COMPLETED 2026-05-04 — see D16. A1 new margins round still pending. | [`within_muni_variation_report.md`](../explorations/anderson_rubin/diagnostics/output/within_muni_variation_report.md) |
| **A3** | Add **firm size** as candidate margin (tercile or quartile). | F0, F1 | MEDIUM | ~~COMPLETED 2026-05-04~~ — staged diagnostic (E0–E3c) selected `policy_block_active × S3` as production margin; `cnae_section × S3` as robustness. See D16. | [`f1_combined_report.md`](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) §8 |
| **A4** | Add **export orientation** (export-oriented vs. domestic) as candidate margin. Requires SECEX or RAIS-export linkage. | F0, F1 | MEDIUM | PROPOSED — data source TBD | — |
| **A5** | Add **BNDES product / line** as candidate margin. Note: `bndes_product` is inadmissible per D14 (loan-side classifier); only admissible if a firm-side proxy can be constructed. | F0, F1 | MEDIUM | PROPOSED | — |
| **A6** | Descriptive cross-tab of firm primary CNAE (RAIS) vs. project CNAE (BNDES) for borrowers. Informs institutional narrative only; does not feed back into margin choice (settled at D14). | descriptive | LOW | PROPOSED — optional | — |
| **A7** | Weight horse race at the `policy_block` aggregation. Correlation-first protocol on Tier C (6 candidate weights). | F4 | MEDIUM | ~~COMPLETED 2026-05-05~~ — production winner: `w_owners_muni_univ` (Tier C, F_kp = 59.56); runner-up: `w_binary_muni_univ` (F_kp = 47.54). Follow-ups: A15, A16, A17. | [`a7_winner_summary.md`](../explorations/anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md) |
| **A8** | Robustness regression including K (Finance) in the treatment set. | F2, F3 | LOW | PROPOSED | — |
| **A9** | Trace 20 NA-CNAE firm-years (R$31.9M, 18 BNDES borrowers, 2002–2014) upstream — likely a join failure. | data quality | LOW | PROPOSED | [`unmatched_cnae_diagnostic.csv`](../explorations/anderson_rubin/diagnostics/output/unmatched_cnae_diagnostic.csv) |
| **A10** | **Composition/volume decomposition — central design problem (was: "AR identification alternatives").** With the endogenous variable now defined as sector employment shares (proxy for sectoral composition of economic activity, per D24) and the volume channel defined as total BNDES disbursements / initial municipal GDP (a unit-free ratio; specification subject to revision after theory/math review), the question is how to operationalise the decomposition in the second stage. Four candidate approaches: (1) Pure AR — OLS on both composition and volume; **(2) Partial IV — instrument sector employment shares only, control for the volume ratio directly (BASELINE per D24);** (3) Full IV — instrument both; (4) Mixed — OLS for shares, IV for total. Approach (2) is the baseline; (1), (3), (4) are robustness variants. Source: 2026-04-30 meeting; promoted 2026-05-06 from one alternative among many to the central design problem. | F3, F4 | HIGH | UNDER TEST — baseline = approach (2) | — |
| **A11** | **Mechanism puzzle: hiring vs. credit channel.** First stage shows instruments predict employment (F up to 265) but not loan amounts (F ~ 6). Investigate once baseline AR is in place. Source: 2026-04-23 meeting. | F2, F3 | MEDIUM | PROPOSED — deferred until AR baseline complete | — |
| **A12** | **Instrument construction document.** Step-by-step document explaining instrument definition, construction, and aggregation at the sector level. Source: 2026-04-30 meeting. | documentation | MEDIUM | PROPOSED | — |
| **A13** | **Verify real GDP deflator construction.** Check whether `gdp_real` uses spatial or national deflator. Source: 2026-04-17 meeting. | data quality | LOW | PROPOSED — do later | — |
| **A14** | **Test sensitivity to political affiliation timing window.** Compare (a) cycle-specific pooled `[e-4, e-1]` baseline; (b) last year's affiliation (t−1); (c) contemporaneous affiliation. Low priority until AR baseline established. | F2, F3 | LOW | PROPOSED | — |
| **A15** | **Investigate Agro affiliation coverage gap.** A7 Step 0: only ~19% of Agro RAIS firms have an owner-affiliation record; those covered account for ~25% of Agro employment. Two questions: (i) TSE design issue or join failure? (ii) Is the matched subset systematically non-representative in alignment? | data quality + F2 power | MEDIUM | PROPOSED 2026-05-05 — activate when capacity allows | [`a7_step0_report.md`](../explorations/anderson_rubin/diagnostics/output/a7_step0_report.md) |
| **A16** | **Cluster 1 denominator-scope investigation (Tier A build).** A7 discovered `w_owners_muni_match` is mathematically degenerate with `w_owners_muni_univ` — the actual open question is denominator-scope (sector vs. muni); anchor correlation = 0.75. Requires building Tier A `w_owners_sec_match` analogue. | F4 (denom robustness) | MEDIUM | PROPOSED 2026-05-05 — surface when production graduation begins | [`a7_winner_summary.md`](../explorations/anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md) §4(a) |
| **A17** | **Cluster 2 empshare_floor matched-only sensitivity.** Cluster 2 Tier B (`w_firm_empshare_floor_match`, F_kp=45.91) beats Tier C 3.4× but does not beat the production winner. Contingent: activates only if floor weight is reconsidered. | F4 (floor sensitivity) | LOW | PROPOSED 2026-05-05 — contingent | [`a7_winner_summary.md`](../explorations/anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md) §4(b) |

---

## §5 Active branches

| Branch | Plan | Status |
|---|---|---|
| AR baseline implementation (`explorations/anderson_rubin/ar_baseline/ar_baseline.R`) | [`journal/plans/2026-04-29_ar-baseline-implementation.md`](../journal/plans/2026-04-29_ar-baseline-implementation.md) | ACTIVE |
| Weight horse race (`explorations/anderson_rubin/a7_weight_comparison/`) | [`journal/plans/2026-05-05_a7-revised-weight-comparison.md`](../journal/plans/2026-05-05_a7-revised-weight-comparison.md) | COMPLETED 2026-05-05 — winner = `w_owners_muni_univ`; see [`a7_winner_summary.md`](../explorations/anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md) |
| CNAE coverage audit (`diagnostics/cnae_coverage_audit.R`) | — | COMPLETED 2026-05-03 |
| Within-muni variation diagnostic (`diagnostics/within_muni_variation.R`) | — | COMPLETED 2026-05-03 (round 1) — F1 CONFIRMED on all 3 initial margins × 2 denominators. Round 2 (A1 margins) pending. |

---

## §6 Decisions log

Append-only. All design decisions D1–D23 in one place.

| ID | Date | Decision | Rationale | Source |
|---|---|---|---|---|
| **D1** | — | Sector defined consistently from RAIS CNAE section, not BNDES project CNAE. | Firm-CNAE is the only classifier defined for all firms (borrowers and non-borrowers). | script 22→35 |
| **D2** | — | Levels instruments (`FA`, `Z`) spread across full 4-year electoral term. Changes instruments (`dFA`, `dZ`) constructed as $\omega^\ell_{fp,t} \cdot \Delta\text{Align}^\ell_{mpt}$ — non-zero only at inauguration years. Not the same as a naive first difference at cycle boundaries. | Preserves within-cycle variation without boundary contamination. | scripts 32, 34, 36 |
| **D3** | — | Baseline weights pooled over 4-year pre-election window `[e-4, e-1]` intersected with `[2002, 2017]`; cycle-specific = primary, 2002-fixed = robustness. | Maximizes pre-election baseline coverage. | script 33 |
| **D4** | — | 2003 gov/pres cycle dropped (no pre-election data). | Data constraint. | script 32 |
| **D5** | — | `s_mjt` zero-fill OK on RAIS skeleton; `delta_s_mjt` **never** from NA-to-zero, only from observed subtraction. | Prevents spurious variation from imputation at share-change boundaries. | script 35; `audit_41_muni_panel.R` |
| **D6** | — | Drop sector with largest mean share for vector `delta_s` regressions (simplex constraint). | Avoids perfect multicollinearity from the simplex adding-up constraint. | scripts 41/54 |
| **D7** | 2026-04-04 | Employment weighting enters firm regression via `bl_n_employees` (pre-election baseline mean), **not** contemporaneous. | Contemporaneous employment is endogenous to BNDES lending. | scripts 42, 51 |
| **D8** | 2026-04-04 | `binary_fp` baseline = `max(1(L_fp,s > 0))` over pre-election window (any-year indicator), not fraction-of-years. | More stable signal; less sensitive to year-specific data gaps. | script 36 |
| **D9** | — | `exposure_control` ($\sum_p w^\ell_{jmp,t}$) included in primary sector spec; tier-specific variants emitted. | Controls for total political exposure at the sector level. | scripts 31/34 |
| **D10** | — | **How to handle total BNDES in the second stage is open (A10).** Four approaches under consideration: (1) Pure AR, OLS on both; (2) Partial IV, instrument sector shares only; (3) Full IV, instrument both; (4) Mixed, OLS for shares, IV for total. | Both the composition and volume channels are endogenous; the earlier "do not include total BNDES" framing was too restrictive. | `docs/archive/doubts.md` Issue 9; A10; 2026-04-30 meeting |
| **D11** | — | Multi-municipality firms (2% of firm-years, 30% of employment) handled as robustness via `is_multi_muni == 0` subsample. | Primary attribution of multi-muni firms is ambiguous; robustness subsample confirms results do not hinge on this choice. | script 42 |
| **D12** | 2026-05-03 | XX sectors (K, O, T, U) excluded from the policy-block treatment set. K (Finance) is the key case — BNDES is a financial intermediary; K firms re-lend rather than absorb credit as final users. | Direct case for K exclusion is theoretical; robustness check including K planned (A8). | CNAE coverage audit outputs |
| **D13** | 2026-05-03 | The operative aggregation margin is determined empirically, not committed a priori. | Without this, we commit to a margin before checking whether BNDES actually uses it. | This conversation |
| **D14** | 2026-05-03 | **Admissibility criterion for aggregation margins:** a margin must be a firm-side classifier defined for every firm in RAIS (including non-borrowers). `bndes_product` is inadmissible (loan-side). PSI eligibility is inadmissible (purpose-defined). Industrial-policy CNAE crosswalks (PBM, Profarma, Prosoft) are admissible but redundant with raw CNAE. Firm-CNAE is the operative classifier everywhere. | Loan-side classifiers leave the muni-level baseline shares undefined for the non-borrower majority of the RAIS universe. | [`docs/strategy/bndes_allocation_logic.md`](../docs/strategy/bndes_allocation_logic.md) |
| **D15** | 2026-05-03 | **F1 CONFIRMED on the initial 3-margin candidate set.** Within-muni × time variance decomposition supports F1 on all (margin × denom) cells tested. Denominator choice (V1 vs V2) is not material at the F1 link. | F1 confirmation establishes the IV is non-degenerate at the existing taxonomies. | [`within_muni_variation_report.md`](../explorations/anderson_rubin/diagnostics/output/within_muni_variation_report.md) |
| **D16** | 2026-05-04 | **Production aggregation margin: `policy_block_active × S3`.** Five-stage diagnostic (E0–E3c). Primary: 12 active bins, mean share_within = 0.642 (V1). Secondary/robustness: `cnae_section × S3` (51 active bins, mean share_within = 0.769). S4 dropped at E2. T3 conditional imputation accepted for unmatched stated-Micro/Pequena BNDES loans. | `policy_block_active × S3` chosen for institutional alignment with BNDES targeting and higher density of supported bins (3/12 = 25%) vs. `cnae_section × S3` (3/51 = 6%). | [`f1_combined_report.md`](../explorations/anderson_rubin/diagnostics/output/f1_combined_report.md) §8 |
| **D17** | 2026-05-05 | **Standalone `size_bin` is admissible as an aggregation margin.** Absolute thresholds (MPME 0–49 / Média 50–499 / Grande 500+) preferred over tertiles — mirrors BNDES porte categories. Corrects the 2026-04-21 convention that banned standalone `size_bin` (that ban conflated regression weighting with SSIV margin choice). | `n_employees` is defined for every firm in RAIS; absolute thresholds are institutionally grounded. | This session 2026-05-05 |
| **D18** | 2026-05-05 | **Firm-CNAE vs. project-CNAE consistency question retired from the identification chain.** Firm-CNAE is operative because it is defined for all firms; project-CNAE is descriptive only. A6 remains as optional descriptive. | D14 already resolved this via the admissibility criterion; keeping it as an open empirical test misrepresented a settled design choice. | This session 2026-05-05 |
| **D19** | 2026-05-05 | **Size-classifier labels renamed S2/S3/S4** (was A2/A3/A4 in diagnostic scripts) to avoid collision with open-angle A-numbers in §4. | Naming ambiguity — two referent systems sharing the same labels. | This session 2026-05-05 |
| **D20** | 2026-05-05 | **F2 reframed as informativeness/power check, not validity gate.** Under AR (P2), a weak first stage does not invalidate inference. F2 failure means the AR confidence set is unbounded (test is honest but uninformative), not that inference is wrong. F-stats remain a diagnostic for power, not a gate. | AR test validity is unconditional on instrument strength; conditioning the chain on a first-stage threshold imports a restriction the AR framework was chosen to avoid. | This session 2026-05-05 |
| **D21** | 2026-05-05 | **A7 weight comparison protocol revised: correlation-first on Tier C only.** The 2026-04-29 80-row spec grid superseded. New protocol: (i) Step 0 coverage diagnostic; (ii) build 6 candidate weights in Tier C; (iii) 6×6 Pearson correlation on Tier C; (iv) F-stat ranking on representatives, with conditional 2×2 expansion path. New `empshare_floor` variants use `pmax(n_employees, owner_count, 1)` to keep 0-employment BNDES borrowers visible. | Original A7 plan conflated denominator-scope with firm-scope effects and ran 80 spec rows before checking whether weights are distinguishable. | [`journal/plans/2026-05-05_a7-revised-weight-comparison.md`](../journal/plans/2026-05-05_a7-revised-weight-comparison.md) |
| **D22** | 2026-05-05 | **A7 Step 0 escalation resolved: proceed with Tier C, document Agro attenuation as known limitation.** Only ~19% of Agro RAIS firms have owner-affiliation records; Tier C instrument is honest about what's observable but downweights Agro ~4–5× relative to its true economic share. Matched-only denominator does not fix the issue (shifts bias from muni-level under-representation to within-Agro selection bias). Follow-up registered as A15. | No weight construction can synthesize alignment data we don't have; pausing A7 for A15 would block downstream F2/F3 work. | [`a7_step0_report.md`](../explorations/anderson_rubin/diagnostics/output/a7_step0_report.md) |
| **D23** | 2026-05-05 | **A7 weight comparison closed at `policy_block` margin; F4 PARTIAL.** All 6 units passed (89/93/97/96/89/92). Production winner: `w_owners_muni_univ` (Tier C, F_kp = 59.56 under C1_FE). Runner-up: `w_binary_muni_univ` (F_kp = 47.54) as AR robustness. Key findings: (a) Cluster 1 Tier B mathematically degenerate with Tier C for owners family — winner robust to firm-scope by construction; actual open question is denominator-scope (A16); (b) Cluster 2 Tier B beats Tier C 3.4× for empshare_floor but does not beat winner (A17, contingent). Size-crossed `policy_block_active × S3` margin not yet addressed — Track 4 graduation. | A7 plan executed end-to-end; correlation-first protocol identified 5 clusters from 6 candidates; F-stat ranking produced a clear winner. | [`a7_winner_summary.md`](../explorations/anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md) |
| **D24** | 2026-05-06 | **Primary endogenous variable shifted from BNDES credit sector shares ($s^{BNDES}_{mt}$) to sector employment shares ($\text{emp\_share}_{mt}$).** The structural equation becomes $\log(\text{GDP}_{mt}) = \alpha_m + \delta_t + \beta' \cdot \text{emp\_share}_{mt} + \lambda \cdot (\text{bndes\_total}_{mt} / \text{gdp}_{m,0}) + \varepsilon_{mt}$. The full causal chain is: political turnover → BNDES credit reallocation across politically aligned sectors → employment shifts across sectors → change in sectoral composition of economic activity → GDP effect. Employment shares are the most comprehensive observable proxy for the sectoral distribution of local economic activity; sector-by-muni value added or gross output would be preferred but are unavailable for 2002–2017. The volume control enters as the unit-free ratio $\text{bndes\_total}_{mt} / \text{gdp}_{m,0}$ (current-year total BNDES disbursements divided by initial-period municipal GDP); the specification of this control is the working choice and is subject to revision after theory/math review of the econometrics. **What does NOT change:** instruments (shift-share from firm-level political alignment × pre-election sector exposure weights), AR test framework (P2), identification chain F0→F1→F2→F3→F4, all pipeline scripts 11–54, geographic unit (5,570 municipalities), and time coverage (2002–2017). **Implication for §8 findings:** the high F-stats for employment outcomes (up to 265 for `employment_log`) are not reduced-form curiosities — they are the **first-stage relevance evidence for the new endogenous variable**. The weak F for loan amounts (F ~ 6) is the first stage for the BNDES-credit-share specification, which is now a **mechanism check** rather than the primary estimand. **Implication for A10:** the composition/volume decomposition is now central, not auxiliary; baseline = partial IV (instrument employment shares only, control for the volume ratio directly). | Employment is more representative of overall local-economy composition than credit shares, which capture only one link in the transmission chain. Confirmed in advisor meetings April–May 2026. | This session 2026-05-06; advisor discussions April–May 2026 |

---

## §7 Sector taxonomies in play

The AR-test taxonomy choice is settled for production; older classifications remain useful for comparison, robustness, or legacy spec-engine output.

| Variable | Granularity | Built by | Use case |
|---|---|---|---|
| `cnae_section` | 21 CNAE sections (A–U) | upstream | Standard granularity; balanced panel skeleton |
| `custom_sector` (was `sector_group`) | 11 groups (Ag, Mi, CL, CH, CA, UCo, Tr, Tp, MS, PSO, XX) | script 30 | Manufacturing 3-way split; matches BNDES departmental structure |
| `policy_block_active` | 4 active BNDES blocks: Agro, Ind, Infra, Serv; XX excluded | script 30e | Production sector dimension for the AR-test SSIV |
| `S3` | 3 absolute size bins: MPME 0–49, Media 50–499, Grande 500+ employees | production crosswalk pending | Production size dimension; approximates BNDES porte categories |
| **`policy_block_active × S3`** | **12 active bins** | **production crosswalk pending** | **Primary AR production margin** |
| `cnae_section × S3` | 51 active bins | robustness wiring pending | Secondary robustness margin |
| standalone `size_bin` | S3 or S4 bins | diagnostics complete; script 30c uses terciles | Admissible and supported; not preferred production margin |
| `bndes_sector_size_bin` (legacy) | 4 macros × 3 terciles | script 30d | Legacy exploratory variant; not the preferred institutional definition |

Renames: `setor_bndes → bndes_sector`, `sector_group → custom_sector` (2026-04-06). Size labels: S2/S3/S4 replace A2/A3/A4 (2026-05-05).

---

## §8 Key findings from preparatory work

- **Firm-level extensive margin** has a real first stage. Coalition, unweighted, pooled-count is strongest (cycle-specific F up to 103). 2002-fixed and cycle-specific both viable.
- **Firm-level intensive margin** has no viable first stage (max F ≈ 6 across all 32 specs).
- **Employment outcomes** as LHS produce very high F-stats (up to 265 for `employment_log`). These are **reduced-form direct effects**, not BNDES-mediated, and raise an exclusion-restriction concern if used as IV. (See A11 for mechanism investigation.)
- **Employment-weighted always weaker** than unweighted across outcomes and baselines.
- **Sector-share LHS** (`delta_s_mjt`) attenuates the firm-level signal — cross-sector cancellation in the simplex absorbs much of the within-muni reallocation. Confirmed by aggregated-firm spec engine in script 52.
- **Within-cell variation dominates** in the firm regression (91–94% of identifying $X^2$ sum is within-cell). Cell-mean regressions differ materially from the firm regression unless exact firm sufficient statistics are aggregated. **C6 fails on real data** because firms in the same `(j,m,t)` cell have heterogeneous owner-party exposures. Source: `proposition2_failure_note.tex`.
- **F1 confirmed on sector-only margins.** `cnae_section`, `policy_block`, `policy_block_active` — all supported under V1 and V2 denominators. Denominator choice does not change the F1 verdict.
- **F1 confirmed on size and sector-size margins.** `policy_block_active × S3` (12 bins, mean share_within = 0.642, 3/12 supported) is the production margin. `cnae_section × S3` (51 bins, mean share_within = 0.769, 3/51 supported) is secondary robustness.
- **Known caveat for size margins:** 51% of BNDES loans in the size-alignment diagnostic match no RAIS firm-year row. Unmatched stated Micro/Pequena loans are imputed to the small-size bin under T3; unmatched stated Media/Grande loans are dropped. Surface in data appendix.
- **A7 production weight winner: `w_owners_muni_univ`** (Tier C, F_kp = 59.56 under C1_FE). Runner-up: `w_binary_muni_univ` (F_kp = 47.54). Agro affiliation coverage is only ~19% of RAIS firms; instrument silently downweights Agro ~4–5× (A15 open).

---

## §9 Validation invariants

Active checks in `audit_3_instruments.R` and `audit_41_muni_panel.R`:

1. $\sum_j s_{mjt} = 1$ in muni-years with positive total BNDES.
2. $\sum_j \Delta s_{mjt} = 0$ in interior positive-total transitions; ±1 valid only at entry/exit transitions.
3. Levels instruments in $[0, 1]$; turnover instruments in $[-1, 1]$.
4. Exposure control varies across sectors within muni-year (not muni-only duplicated).
5. No zero-imputation of undefined `delta_s_*`.

---

## §10 Open questions

### AR-test design (current focus)
- **C4** Pooled AR: start from `policy_block_active × S3` once the production crosswalk is wired and script 53 confirms F2 relevance. Keep `policy_block_active` alone and `cnae_section × S3` as comparison/robustness margins.
- **C4** Muni-by-muni AR: low priority / likely infeasible with ~16 years per municipality; pooled AR remains the active path.
- **C8** Penalized methods: relevant when instrument count grows past ~20–30. `policy_block_active × S3` has 12 bins; many-instrument methods matter more for `cnae_section × S3` robustness.
- AR Phase 2 mechanism placebo: transfers data cached at `data/processed/transfers_ibge.qs2` (96.3% match rate). Procurement data not yet sourced.

### Data integration (awaiting advisor)
- **C6** Alternative employment / production-factor data: RAIS unexploited variables (education, age, wages), INEP Censo Escolar, PPM + PAM immediately actionable. PNAD infeasible. Memo: [`docs/data_memos/c6_employment_sources.md`](../docs/data_memos/c6_employment_sources.md).
- **C7** Local deflators: no full-coverage muni deflator exists for 2002–2017. Metro IPCA (~13 metros, ~55% of GDP) is the only off-the-shelf option; wage-residual proxy from RAIS is the tractable full-coverage alternative. Memo: [`docs/data_memos/c7_local_deflators.md`](../docs/data_memos/c7_local_deflators.md).

### Paper integration
- `paper/sections/regs.tex` is the current authoritative draft of the Specifications section but is **not** `\input{}`-ed by `main.tex`. `main.tex` §5 contains a placeholder ("Connection to three steps thing (deprecated)"). Decide when to merge.
- The paper draft needs to absorb the 2026-05-03 to 2026-05-05 updates: admissibility criterion, `policy_block_active × S3` production margin, F1 diagnostic results, T3-imputation caveat, and retirement of project-CNAE as a load-bearing concern.

---

## §11 Next action

**Track 1 (build production crosswalk) — highest priority.** Draft `scripts/R/3_instruments/30f_build_policy_block_size_mapping.R` implementing S3 thresholds (MPME 0–49 / Media 50–499 / Grande 500+) × `policy_block` (Agro/Ind/Infra/Serv; XX excluded). Apply T3 imputation for unmatched-but-stated-Micro/Pequena BNDES loans. Wire into scripts 31, 34, 41.

**Track 2 (F2 informativeness check at new margin).** Re-run sector first-stage spec engine (script 53) at `policy_block_active × S3`. F-stats are a diagnostic for AR test power, not a validity gate (D20). F2 is ultimately assessed by whether the AR confidence set for $\beta$ is bounded and reasonably precise.

**Track 3 (A7 graduation — separate plan, contingent).** A7 closed at `policy_block`. Production winner: `w_owners_muni_univ`. A graduation plan would update scripts 31/33/34 to expose the `muni_univ` denominator option. Conditional on Track 1 being available — graduate at `policy_block_active × S3` margin.

**Track 4 (A6 descriptive, optional).** Cross-tabulate firm primary CNAE (RAIS) vs. BNDES project CNAE for borrowers. Informs institutional narrative only.

The next chain links are **F2** (power check) and **F3** (exclusion-restriction placebos). F4 is PARTIALLY ADDRESSED at `policy_block` via A7; size-crossed margin still requires Track 3 graduation, and A16 (Cluster 1 denom-scope) is a contingent open question.

---

## §12 How to maintain this document

**Three rules — the only thing that keeps this document useful.**

1. **Any new idea, in any session, gets a row in §4 immediately.** No exceptions. Even half-formed ideas get an A-number.
2. **When an F-link's status changes → update §3 in the same commit, and add a one-line entry in §6.**
3. **The Next action (§11) is updated whenever the previous Next action is started or completed.** §11 is always actionable, never aspirational.

**Promotion rules:**
- An A-entry whose result reshapes the identification chain → promote to a new F-link in §3, with a D-entry in §6 recording the promotion.
- An A-entry that is closed (done, abandoned, or superseded) → strike through with a date and reason. Do not delete (auditability).

The blueprint should be re-read at session start and edited at session end.
