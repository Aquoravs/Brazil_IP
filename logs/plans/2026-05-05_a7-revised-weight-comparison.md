---
status: PROPOSED
date: 2026-05-05
author: Claude (planner)
phase: exploration
supersedes:
  - logs/plans/2026-04-29_weight-horserace.md
builds_on:
  - logs/plans/2026-05-05_a7-weight-comparison-strategy.md
depends_on:
  - logs/plans/2026-05-05_a7-step0-coverage-diagnostic.md
related:
  - docs/PROJECT_BLUEPRINT.md (§4 A7, §6 D-entries on weighting)
  - scripts/R/3_instruments/31_build_sector_exposure_weights.R
  - scripts/R/3_instruments/33_select_baseline_weights.R
  - scripts/R/3_instruments/34_build_shift_share_instruments.R
target_artifact: explorations/anderson_rubin/a7_weight_comparison/
mode: simplified (workflow.md §2 — Simplified Mode for R Scripts / Explorations)
aggregation_margin: policy_block (4 active bins: Agro, Ind, Infra, Serv; XX excluded)
context:
  - Aggregation margin in scope for THIS plan: policy_block only. Size dimension deferred.
  - The production margin per D16 is policy_block_active × S3; this plan handles the policy_block-only sub-problem first; an analogous plan can be written for the cross product after this stabilises.
  - Scripts 31/33/34 read on 2026-05-05 confirmed three silent imputations (matched-only denominators, n_employees > 0 filter on emp weight, undifferentiated Z = 0 cells). Step 0 diagnostic quantifies these before this plan runs.
user_decisions_locked:
  - Aggregation margin: policy_block only
  - emp_share_floor numerator: pmax(n_employees, owner_count, 1)
  - Correlation threshold for cluster collapse: |ρ| > 0.90
  - One-cycle proxy regression: 2002–2006 (mayor cycle, cycle-specific baseline)
  - Replication anchor: w_owners_sec_match (loaded from existing pipeline, verification-only — not in correlation matrix)
  - Correlation exercise restricted to ONE cell of the 2×2 grid — Tier C (muni denominator × full RAIS universe). Tier A and Tier B built only if Step 3 surfaces ambiguity that requires disentangling denominator-scope or firm-scope effects.
  - Two empshare_floor variants in Tier C — w_firm_empshare_floor (continuous owner_party_share aggregated by emp_share_floor weights; renamed from w_emp_share_floor_muni_univ for symmetry with binary variant) and w_binary_empshare_floor (binary alignment indicator aggregated by emp_share_floor weights; new).
---

# A7 — Revised Weight Comparison (Correlation-First Protocol, policy_block)

## Status

PROPOSED. Replaces `logs/plans/2026-04-29_weight-horserace.md`.

## Goal

Select the production SSIV weight at the `policy_block` aggregation margin. Use the correlation-first protocol from `2026-05-05_a7-weight-comparison-strategy.md`: collapse redundant weights via correlation **within one cell of the 2×2 grid** before running any regression, then run a single one-cycle F-stat comparison on the surviving representatives.

The aggregation margin for this plan is `policy_block` (4 active bins: Agro, Ind, Infra, Serv; XX excluded). Size is out of scope here. The output is a single recommended weight construction for the `policy_block` shift-share instrument, with a documented runner-up for robustness.

## Why this supersedes the 2026-04-29 plan

The original plan ran an 80-row spec grid (5 tier specs × 4 controls × 4 weights) before establishing whether the four weights are even distinguishable. Reading scripts 31/33/34 surfaced two confounds the original grid could not resolve:

1. **Confounded denominator-and-firm-scope.** The original A7 plan's new weights (`emp_muni`, `bin_muni`, `own_muni`) differ from the legacy `owner` weight on **two dimensions at once** — denominator scope (sector vs. muni) **and** firm scope (matched-only vs. full RAIS universe). If a new weight wins, the original plan cannot tell which dimension drove the win.
2. **Hidden 0-employment drop.** `w_mjp_emp` filters firms with `n_employees > 0`, silently removing the BNDES borrowers that have zero RAIS employment (MEI, individual entrepreneurs, Cartão BNDES, informal-borderline). These are real loan recipients who are invisible to the employment-weighted instrument.

The revised plan resolves both: (a) sets up the explicit 2×2 grid (denominator × firm scope) so each comparison can vary one dimension at a time; (b) adds an `empshare_floor` weight family using `pmax(n_employees, owner_count, 1)` so 0-employment firms re-enter the instrument with their owner-count footprint or a unit floor; (c) uses correlation **within one cell of the 2×2** to collapse the candidate set before any regression runs, with the cross-cell comparisons held in reserve as a documented escalation path.

## Steps overview

| Step | Goal | Output |
|---|---|---|
| 0 | Coverage and imputation diagnostic | (separate plan; produces 3 CSVs + report) |
| 1 | Build 6 Tier C candidate weights + Tier A replication anchor at policy_block | `a7_weights_panel.qs2` |
| 2 | Pairwise correlation matrix on Tier C weights → cluster (6×6) | `a7_correlation_matrix.csv`, `a7_correlation_clusters.csv`, `a7_correlation_heatmap.pdf` |
| 3 | Pick representatives (one per cluster) | `a7_representative_weights.csv` |
| 4 | One-cycle proxy F-stats on Tier C representatives; expand to Tier A/B only if Step 3 flags ambiguity | `a7_onecycle_proxy_fstats.csv` |
| 5 | Production decision + runner-up | `a7_winner_summary.md` |

Step 0 runs first and is a hard prerequisite — its findings condition how Steps 2 and 4 are interpreted.

## Step 1 — Candidate weight construction (Tier C: 6 weights + Tier A replication anchor)

Tier C is the **one cell of the 2×2 grid** that gets built initially. The four cells of the 2×2 are (denominator scope: sector vs. muni) × (firm scope: matched-only vs. full RAIS universe). Tier C is muni denominator × full RAIS universe — the most defensible production candidate because (a) the muni denominator gives a Bartik-style sector-share interpretation, (b) the full universe avoids the matched-only imputation bias from concern (2) of the 2026-05-05 reading of scripts 31/33/34, and (c) it accommodates the new `empshare_floor` variants that handle 0-employment firms via `pmax(n_employees, owner_count, 1)`.

Tier A and Tier B are **not built initially**. They are built only if Step 3 surfaces ambiguity that requires disentangling the denominator-scope effect (Tier A → Tier B) or the firm-scope effect (Tier B → Tier C). The Tier A replication anchor `w_owners_sec_match` *is* loaded from the existing pipeline output to verify that the construction matches the production code; it does not enter the correlation matrix.

All weights built at `policy_block` aggregation, under the cycle-specific baseline windows from script 33 (mayor: 2002-03 / 04-07 / 08-11 / 12-15; gov_pres: 2002-05 / 06-09 / 10-13).

### Tier A — Sector denominator, matched-only firms (replication anchor only)

The existing pipeline weight is `w_owners_sec_match = L_mjp / L_mj` where `L_mj = sum(total_owners)` over matched firms in (m, s, t). This weight is **loaded** from `sector_exposure_weights_owner_policy_block.qs2` (built by script 31) and aggregated to muni level to verify that the muni-mayor-coalition instrument vector matches the production output (`shift_share_instruments_policy_block.qs2`, `Z_owner_mayor_coalition_*` columns) within `1e-6`. No new construction; no entry in the correlation matrix.

The other Tier A weights (`w_emp_sec_match`, `w_firm_sec_match`, `w_binary_sec_match`) are **not loaded** — they would only be informative if Step 3 surfaced a denominator-scope effect that required disentangling, in which case they would be built alongside the relevant Tier B weights.

### Tier B — Muni denominator, matched-only firms (deferred, definitions held in reserve)

Tier B is **not built initially**. If Step 3 surfaces a cluster where the firm-scope effect (matched-only vs. full RAIS universe) is the open question — for example, two Tier C representatives separated only by their treatment of unmatched firms — then the Tier B counterparts of those representatives are built and added to a follow-up correlation pass. Definitions held in reserve:

| Weight ID | Formula |
|---|---|
| `w_owners_muni_match` | `L_mjp / L_mB_match` where `L_mB_match = sum(total_owners)` over matched firms in muni m |
| `w_emp_muni_match`    | `L_mjp_emp / E_mB_match` where `E_mB_match = sum(n_employees)` over matched firms in muni m with `n_employees > 0` |
| `w_firm_muni_match`   | `L_mjp_firm / n_firms_with_owners_muni` |
| `w_binary_muni_match` | `L_mjp_binary / n_firms_with_owners_muni` |

### Tier C — Muni denominator, full RAIS universe (6 weights, the cell that runs)

Numerators carry alignment from matched firms only (alignment is observed only there); denominators sum across **all RAIS firms in muni m**, regardless of affiliation status. The two `empshare_floor` variants share the same firm-level weight `emp_share_floor_f = n_f_floored / Σ_{f' ∈ muni} n_f'_floored` with `n_f_floored = pmax(n_employees, owner_count, 1)` (`owner_count` = `total_owners` for matched firms, `0` for unmatched, so the floor reduces to `pmax(n_employees, 1)` for unmatched RAIS firms). They differ only in the firm-level alignment signal.

| Weight ID | Formula |
|---|---|
| `w_owners_muni_univ`         | `L_mjp / L_mB_univ` where `L_mB_univ = sum(total_owners)` for matched + `0` for unmatched, summed over all RAIS firms in muni m |
| `w_emp_muni_univ`            | `L_mjp_emp / E_mB_univ` where `E_mB_univ = sum(n_employees)` over **all** RAIS firms in muni m with `n_employees > 0`. Note: `w_emp_*` retains the historical 0-employment filter; the floor variants below replace it. |
| `w_firm_muni_univ`           | `L_mjp_firm / n_firms_rais_muni` — equal-per-firm aggregation of `owner_party_share` |
| `w_binary_muni_univ`         | `L_mjp_binary / n_firms_rais_muni` — equal-per-firm aggregation of `1[owner_party_share > 0]` |
| `w_firm_empshare_floor`      | `Σ_{f ∈ (m,s,t)} emp_share_floor_f × owner_party_share_f`. Continuous alignment signal aggregated by employment-share-floor weights. **Mathematically equivalent** to the originally-proposed `w_emp_share_floor_muni_univ`; renamed for symmetry with the binary variant below. |
| `w_binary_empshare_floor`    | `Σ_{f ∈ (m,s,t)} emp_share_floor_f × 1[owner_party_share_f > 0]`. Binary alignment indicator aggregated by employment-share-floor weights. **New.** |

### Universe-vs-matched bookkeeping

- All Tier-C denominators sum over **all RAIS firms** in muni m, regardless of whether the firm has an affiliation record. This includes firms in any cnae_section (active blocks Agro/Ind/Infra/Serv plus XX); the choice mirrors the original A7 plan's `E_mB` rule.
- Numerators carry alignment information from matched firms only (alignment is observed only there).
- The 2×2 grid logic is **held in reserve**: a Tier B → Tier C comparison would isolate the **firm-scope** effect (matched-only vs. universe denominator) holding muni denominator fixed; a Tier A → Tier B comparison would isolate the **denominator-scope** effect (sector vs. muni) holding firm scope fixed. Step 3 decides whether either comparison is needed.

### Pooling convention

For all Tier C weights, baseline pooling follows script 33's convention: pool counts across the baseline window first, then divide once. This preserves the sum-to-1 invariant for owner-style and continuous emp-share-style weights. `w_binary_*` does not satisfy sum-to-1 by design (a firm with multiple aligned parties is double-counted across parties).

### Output

A single panel keyed by (`muni_id`, `policy_block`, `party`, `treatment_year`, `tier`, `baseline_type = cycle_specific`) with the 6 Tier C weight columns plus the loaded Tier A replication anchor (`w_owners_sec_match`). Save to `explorations/anderson_rubin/a7_weight_comparison/output/a7_weights_panel.qs2`.

In a parallel pass, combine each weight with `alignment_shocks.qs2` to build muni-level instrument vectors `Z_<weight_id>_mayor_coalition` (and the gov_pres analogue), spread across the electoral term using the same `term_map` as script 34. Save to `a7_instruments_panel.qs2`.

## Step 2 — Correlation matrix and clustering (Tier C only)

For each of the 6 Tier C weights, extract the muni-level mayor-coalition instrument vector (`Z_<weight_id>_mayor_coalition`), pooled across all (muni, year) cells in 2002–2017 under the cycle-specific baseline. The Tier A replication anchor is **not** in the correlation matrix.

Compute the 6×6 pairwise Pearson correlation matrix. Apply the protocol from `2026-05-05_a7-weight-comparison-strategy.md`:

- **|ρ| > 0.90** → cluster the two weights together
- Hierarchical clustering on `(1 − |ρ|)` as the distance metric, single linkage, cut at 0.10

Output:
- `a7_correlation_matrix.csv` — 6×6 with weight_ids on rows/cols
- `a7_correlation_clusters.csv` — `weight_id`, `cluster_id` for each weight
- `a7_correlation_heatmap.pdf` — visual (ggplot, no in-figure title per INV-12; serif font)

Repeat the same exercise for `Z_<weight_id>_gov_pres_coalition` and report side by side. If the cluster structure differs between mayor and gov_pres, document; the production decision uses the mayor-cycle clustering.

The Tier A → Tier C and Tier B → Tier C cross-tier comparisons are **not** run in Step 2. The expectation is that within Tier C, the 6 weights cluster into 2–3 groups; reducing the candidate set before any cross-tier work is more efficient than building Tier A/B for weights that turn out to cluster with their Tier C analogues anyway.

## Step 3 — Representative selection

For each cluster from Step 2, pick one representative weight. Selection criterion (in priority order):

1. **Step 0 bias flag override** — if Step 0 flags a weight in a cluster as biased (e.g., `w_emp_muni_univ` blind to a substantively important 0-employment subpopulation that lives mostly in Serv), exclude it from representative candidacy and pick from its cluster-mates.
2. **Interpretability** — owners > firm_empshare_floor > emp > firm > binary > binary_empshare_floor, by economic transparency. The empshare-floor variants outrank the equal-per-firm averages because they fold in firm size honestly.
3. **Construction simplicity** — prefer weights whose formulas the paper can defend in a single sentence.

Document the choice for each cluster in `a7_representative_weights.csv` with columns `weight_id`, `cluster_id`, `is_representative`, `rationale`. The rationale records any Step 0 override and the priority criterion that decided the pick.

If any single cluster contains weights that disagree on the firm-scope dimension (e.g., a cluster where Tier C `w_owners_muni_univ` correlates above 0.90 with what *would* be `w_owners_muni_match` if it were built — a hypothesis tested in Step 4 expansion), flag the cluster for the Tier B build path.

## Step 4 — One-cycle proxy regression (Tier C representatives, optional 2×2 expansion)

For each Tier C representative, run a sector first-stage regression on the 2002–2006 mayor cycle only:

- Outcome: muni-level BNDES sector share or sector treatment as currently defined in the project (use the same outcome as the existing `ar_baseline.R` for comparability)
- Instruments: `Z_<weight_id>_mayor_coalition` and its sectoral components for the four active blocks
- Specifications: (a) no controls; (b) C1_FE = muni FE + year FE; (c) C2_FE_R0a = C1_FE + tier-specific exposure controls

Compute Cragg–Donald F (or Kleibergen–Paap F where available via `fixest::feols` or `ivreg`). Cluster standard errors at `muni_id`.

**Conditional 2×2 expansion.** If Step 3 flagged ambiguity that requires disentangling denominator-scope or firm-scope effects, build the corresponding Tier A and/or Tier B counterparts of the surviving Tier C representatives and re-run the same regression on them. This is conditional, not default — the expectation is that Tier C alone produces a clean F-stat ordering.

Output: `a7_onecycle_proxy_fstats.csv` with one row per (representative weight, controls spec): columns `weight_id`, `tier`, `controls`, `f_stat_cd`, `f_stat_kp`, `n_obs`, `n_clusters`, `df1`, `df2`.

The one-cycle restriction keeps the test small and fast. The relative F-stat ordering across weights is generally stable across cycles (per the A7 strategy doc); if a representative produces F < 5 even on the proxy, flag for closer inspection rather than dismissing immediately.

## Step 5 — Production decision

The Tier C representative with the highest F-stat under primary controls (`C1_FE`) is the production candidate, **provided** Step 0 does not flag it for bias. The runner-up (next-highest F-stat representative) is reported as a robustness specification in the AR test. If the highest-F representative is the one Step 0 flags, the second-highest representative becomes the production candidate and the flagged one becomes the robustness check.

If the conditional 2×2 expansion in Step 4 produced cross-tier F-stats, document any reversal: Tier C's winner being beaten by its Tier A or Tier B counterpart would be a substantive finding about the SSIV's sensitivity to denominator scope or firm scope, and warrants escalation rather than a quiet promotion.

Output: `a7_winner_summary.md` with:
- Selected weight ID and its construction formula (Tier C, denominator scope, firm scope, floor handling)
- Headline F-stat under each controls spec
- Runner-up weight ID and its rationale as a robustness check
- Whether the 2×2 expansion was triggered, and if so its findings
- Pointer to where production scripts (31/33/34) need to be updated if this is graduated

This plan does not graduate the winner into production — that is a separate plan, conditional on the orchestrator approving the recommendation.

## Files

| File | Status | Purpose |
|---|---|---|
| `explorations/anderson_rubin/a7_weight_comparison/01_build_weights.R` | NEW | Step 1 — builds 6 Tier C weights and loads Tier A replication anchor |
| `explorations/anderson_rubin/a7_weight_comparison/02_correlations.R` | NEW | Step 2 — 6×6 Tier C correlation matrix and clustering |
| `explorations/anderson_rubin/a7_weight_comparison/03_representatives.R` | NEW | Step 3 — pick one representative per cluster; document rationale and any Step 0 overrides |
| `explorations/anderson_rubin/a7_weight_comparison/04_onecycle_proxy.R` | NEW | Step 4 — F-stat regressions on representatives; conditional 2×2 expansion |
| `explorations/anderson_rubin/a7_weight_comparison/05_winner_summary.R` | NEW | Step 5 — assemble final summary |
| `explorations/anderson_rubin/a7_weight_comparison/output/a7_weights_panel.qs2` | NEW | 6 Tier C weights + replication anchor at (m, s, p, t, tier, baseline_type) |
| `explorations/anderson_rubin/a7_weight_comparison/output/a7_instruments_panel.qs2` | NEW | Muni-level instrument vectors for the 6 Tier C weights |
| `explorations/anderson_rubin/a7_weight_comparison/output/a7_correlation_matrix.csv` | NEW | 6×6 Pearson |
| `explorations/anderson_rubin/a7_weight_comparison/output/a7_correlation_clusters.csv` | NEW | Cluster assignment |
| `explorations/anderson_rubin/a7_weight_comparison/output/a7_correlation_heatmap.pdf` | NEW | Visual |
| `explorations/anderson_rubin/a7_weight_comparison/output/a7_representative_weights.csv` | NEW | Representative per cluster + rationale |
| `explorations/anderson_rubin/a7_weight_comparison/output/a7_onecycle_proxy_fstats.csv` | NEW | F-stats for representatives (and any Tier A/B expansion rows) |
| `explorations/anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md` | NEW | Production decision + runner-up + 2×2 expansion findings (if any) |
| `explorations/anderson_rubin/a7_weight_comparison/SESSION_LOG.md` | NEW | Per-session progress log |

No production scripts touched.

## Inputs

- `output/rais_bndes_reconstructed.fst` — firm-year-muni-cnae_section-n_employees panel (script 22)
- `raw/david_ra/owner_aff_firm_year_party_2002_2019.qs2` — firm-year-party owner counts and shares
- `output/policy_block_mapping.qs2` — cnae_section → policy_block crosswalk (script 30e)
- `output/alignment_shocks.qs2` — muni-year-party alignment levels and changes (script 32)
- `output/sector_exposure_weights_owner_policy_block.qs2` — Tier A replication anchor (built by script 31)
- `output/shift_share_instruments_policy_block.qs2` — current production instruments at policy_block (script 34)
- Step 0 outputs — feed Step 3 rationale and Step 5 override logic

## Verification (simplified-mode quality checklist, target ≥80)

For Step 1:
- [ ] All 6 Tier C weights produce a non-empty (m, s, p, t) panel.
- [ ] **Replication anchor**: `w_owners_sec_match` muni-mayor-coalition instrument vector loaded from the existing pipeline matches a freshly aggregated version produced by this exploration within `1e-6`.
- [ ] Sum-to-1 invariant: for `w_owners_muni_univ`, `w_emp_muni_univ`, `w_firm_muni_univ`, `w_firm_empshare_floor`, summing across parties within (m, s, t) yields ≤ `1 + 1e-9` per cell.
- [ ] No sum-to-1 enforcement on `w_binary_muni_univ` or `w_binary_empshare_floor` (binary signal can sum to >1 by design — a firm with multiple aligned parties is double-counted).
- [ ] No NA values in instrument vectors (NAs filled with 0 per script 34 convention; Step 0 documents the imputation).

For Step 2:
- [ ] Correlation matrix is 6×6, symmetric, diagonal = 1, off-diagonals in `[-1, 1]`.
- [ ] Cluster assignment is deterministic (same input → same clusters).

For Step 4:
- [ ] All representative F-stats > 1 (else the spec is broken).
- [ ] `n_obs` matches expected muni-year count for the 2002–2006 cycle.
- [ ] Conditional 2×2 expansion rows (if produced) carry an explicit `tier` column distinguishing them from primary Tier C rows.
- [ ] No prohibited functions (INV-19); seed once if any random sampling (INV-14); packages at top (INV-15); no absolute paths (INV-16).

For Step 5:
- [ ] `a7_winner_summary.md` references all five Step outputs and Step 0 findings.
- [ ] Selected weight has both rationale and Step 0 bias-check documented.

## Risks and mitigation

| Risk | Mitigation |
|---|---|
| Replication anchor fails (`w_owners_sec_match` ≠ existing pipeline) | Halt before claiming Step 1 done; diff against `sector_exposure_weights_owner_policy_block.qs2` row by row; fix construction or re-load the existing object |
| Tier C universe denominator inflates memory (full RAIS firm-year join) | Aggregate to muni level early; keep firm-year copy in memory only for the `pmax(n_employees, owner_count, 1)` floor computation; expected peak ~5 GB |
| All 6 Tier C weights cluster into one cluster (correlations all > 0.90) | Document; pick on interpretability + replication continuity; one-cycle proxy still runs on the single representative as a sanity check |
| All 6 Tier C weights are mutually distinct (no clusters of size ≥ 2) | Run one-cycle proxy on all 6; consider building Tier B for the lowest-correlated pair to test whether firm-scope is driving the spread |
| Step 0 flags multiple representatives for bias | Document; pick the cleanest representative; if no clean candidate exists, escalate to user — this would be a substantive finding about the SSIV's construction limits |
| Step 3 surfaces ambiguity that the Tier C correlation cannot resolve (e.g., two representatives correlate at exactly 0.85, neither dominant) | Build the corresponding Tier B counterparts to disentangle the firm-scope effect; re-run a 4-row correlation pass; this is the documented escalation path from the cell-only protocol back to the full 2×2 |
| `policy_block` patterns differ from what `policy_block × S3` would show | Acknowledged; this plan is the policy_block-only sub-problem. Cross-product version of the analysis is a separate future plan |

## Out of scope

- Size-dimension weights (S3 alone or `policy_block × S3`) — deferred.
- Tier-spec ladder (mayor / gov / mayor_gov / mayor_pres / mayor_gov_pres) — the original A7 plan's 5 tier specs are not run here. The mayor cycle alone serves as the proxy. A full tier ladder can be re-introduced in a graduation plan if the production winner warrants it.
- Worker affiliation file — owners only, consistent with production.
- Graduating the winner to scripts 31/33/34 — separate plan, conditional on this plan's recommendation.

## Deferred from the 2026-04-29 plan

The original 80-row spec grid (5 tier specs × 4 controls × 4 weights) is **not** run. Justification: correlation-first protocol collapses redundant weights before any regression, and the one-cycle proxy on representatives is sufficient for the production decision. If post-hoc the chosen weight needs a full tier-spec ladder for the AR test itself, that is a downstream task in the AR baseline plan, not this comparison plan.

## Deferred — full 2×2 grid build

An earlier revision of this plan (in this same session) proposed building all 13 weights across the full 2×2 grid (Tier A 4 + Tier B 4 + Tier C 5) before correlation. That proposal is **deferred** in favor of cell-only correlation in Tier C with 6 weights. Justification: within a cell, the 6 weights are expected to cluster into 2–3 groups; reducing the candidate set before any cross-tier work avoids building 8 additional weights (Tier A 4 + Tier B 4) for inputs that may turn out to be redundant with their Tier C analogues. The full 2×2 build is the documented escalation path if Step 3 surfaces ambiguity (see Step 4's "Conditional 2×2 expansion").
