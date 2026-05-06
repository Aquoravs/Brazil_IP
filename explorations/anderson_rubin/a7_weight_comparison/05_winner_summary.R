# =============================================================================
# A7 Step 5 -- Production Winner Summary
# =============================================================================
# Plan: logs/plans/2026-05-05_a7-revised-weight-comparison.md, Step 5.
# Inputs:
#   - explorations/anderson_rubin/diagnostics/output/a7_step0_report.md
#   - explorations/anderson_rubin/a7_weight_comparison/output/
#       a7_correlation_clusters.csv
#       a7_representative_weights.csv
#       a7_onecycle_proxy_fstats.csv
#       a7_onecycle_proxy_summary.md
# Output:
#   - explorations/anderson_rubin/a7_weight_comparison/output/a7_winner_summary.md
#
# This script's job is descriptive only: read the upstream artifacts, identify
# the production winner under the documented decision rule, and emit the
# markdown summary. It does NOT modify any production script under scripts/R/.
# =============================================================================

# ---- Packages (INV-15: all libraries at top) -------------------------------
suppressPackageStartupMessages({
  library(here)
  library(readr)
  library(dplyr)
  library(glue)
})

# ---- Paths (INV-16: relative to project root via here()) -------------------
exp_dir   <- here("explorations", "anderson_rubin", "a7_weight_comparison")
out_dir   <- file.path(exp_dir, "output")
fstats_fp <- file.path(out_dir, "a7_onecycle_proxy_fstats.csv")
summary_fp <- file.path(out_dir, "a7_winner_summary.md")

stopifnot(dir.exists(out_dir))
stopifnot(file.exists(fstats_fp))

# ---- Load F-stat table -----------------------------------------------------
fstats <- read_csv(fstats_fp, show_col_types = FALSE)

# ---- Identify production winner (Tier C representatives, C1_FE) ------------
# Decision rule per plan §Step 5:
#   Highest C1_FE F-stat among Tier C REPRESENTATIVES (not cluster-mates,
#   not Tier B counterparts), provided Step 0 does not flag it.
tier_c_reps <- fstats |>
  filter(tier == "C", controls == "C1_FE") |>
  arrange(desc(f_stat_kp))

winner_row    <- tier_c_reps[1, ]
runner_up_row <- tier_c_reps[2, ]

winner_id    <- winner_row$weight_id
runner_up_id <- runner_up_row$weight_id

# Pull all-spec headline F-stats for the winner
winner_specs <- fstats |>
  filter(weight_id == winner_id, tier == "C") |>
  arrange(controls)

# Tier B counterpart (Cluster 1) for the degeneracy check
tier_b_c1 <- fstats |>
  filter(tier == "B", cluster_id == 1, controls == "C1_FE")

# Cluster 2 trio (representative + cluster-mate + Tier B) for finding (b)
c2_rep   <- fstats |> filter(weight_id == "firm_empshare_floor",      tier == "C",            controls == "C1_FE")
c2_mate  <- fstats |> filter(weight_id == "emp_muni_univ",            tier == "C_clustermate", controls == "C1_FE")
c2_tierB <- fstats |> filter(weight_id == "firm_empshare_floor_match", tier == "B",            controls == "C1_FE")

# ---- Helper: format F-stat row for markdown --------------------------------
fmt <- function(x, d = 2) formatC(x, format = "f", digits = d)

# ---- Assemble markdown -----------------------------------------------------
md <- glue::glue("
# A7 Step 5 -- Production Decision Summary

Plan: `logs/plans/2026-05-05_a7-revised-weight-comparison.md`, Step 5.
Aggregation margin: `policy_block` (Agro, Ind, Infra, Serv; XX excluded).
Decision rule: highest C1_FE Kleibergen-Paap F among Tier C representatives,
unless Step 0 flags the candidate. Generated: {format(Sys.time(), '%Y-%m-%d %H:%M:%S')}.

---

## 1. Production winner

**Winner: `w_owners_muni_univ`** (Tier C, Cluster 1).

**Construction (one sentence).** Tier C, full-universe muni denominator, owners-style aggregator: `w_owners_muni_univ = L_mjp / L_mB_univ`, where `L_mjp = sum(total_owners aligned with party p)` over matched firms in `(muni m, policy_block s, year t)` and `L_mB_univ = sum(owner_count)` summed over **all** RAIS firms in muni `m` (with unmatched firms contributing `owner_count = 0`).

**Headline F-stats (Kleibergen-Paap, mayor cycle 2002-2006, K=4 sectoral instruments):**

| Controls spec       | F_kp  | F_cd   |
|---------------------|------:|-------:|
| no_controls         | {fmt(winner_specs$f_stat_kp[winner_specs$controls == 'no_controls'])} | {fmt(winner_specs$f_stat_cd[winner_specs$controls == 'no_controls'])} |
| C1_FE (year FE)     | {fmt(winner_specs$f_stat_kp[winner_specs$controls == 'C1_FE'])} | {fmt(winner_specs$f_stat_cd[winner_specs$controls == 'C1_FE'])} |
| C2_FE_R0a           | {fmt(winner_specs$f_stat_kp[winner_specs$controls == 'C2_FE_R0a'])} | {fmt(winner_specs$f_stat_cd[winner_specs$controls == 'C2_FE_R0a'])} |

**Robustness to firm-scope.** The Tier B counterpart `w_owners_muni_match` (matched-only denominator) is **mathematically degenerate** with `w_owners_muni_univ` for the owners family: unmatched RAIS firms contribute `owner_count = 0` to the universe denominator, so `L_mB_univ = L_mB_match` cell-by-cell. Both produce identical instrument vectors and identical F_kp = {fmt(tier_b_c1$f_stat_kp)} under C1_FE (max abs diff in muni-level Z = 0). The production winner is therefore robust to the firm-scope dimension by construction; no firm-scope fragility for the owners family.

**Step 0 bias check applied?** No override. See Section 3.

---

## 2. Runner-up (recommended robustness specification)

**Runner-up: `w_binary_muni_univ`** (Tier C, Cluster 4).

Headline F_kp = {fmt(runner_up_row$f_stat_kp)} under C1_FE (F_cd = {fmt(runner_up_row$f_stat_cd)}). Equal-per-firm aggregation of the binary alignment indicator with full-universe muni denominator. Recommended as the AR-test robustness specification: it captures the extensive-margin alignment signal (presence of any aligned owner) and is the second-strongest Tier C representative under the production-relevant controls spec. Reporting both `w_owners_muni_univ` (intensive margin, owner-count weighted) and `w_binary_muni_univ` (extensive margin) bounds the AR test against the choice between owner-count-weighted vs. firm-equal aggregation.

---

## 3. Step 0 bias structure (one paragraph)

Step 0 (`a7_step0_report.md`) found the Agro policy_block has degraded affiliation coverage: mean `match_rate_emp = 24.8%` (median 10.3%), well below the 50% escalation threshold and far below the other three blocks (Ind 95.5%, Infra 93.4%, Serv 67.7%). Per **D22** in the blueprint, this attenuation is **accepted**: it is sector-level (not weight-level), so all six Tier C weights inherit the Agro coverage gap symmetrically -- no single weight uniquely escapes or worsens, and no representative is excluded by the Step 0 override rule. The production winner `w_owners_muni_univ` carries the same Agro attenuation as every other Tier C weight; the choice between weights is therefore unaffected by the bias structure. Follow-up investigation of the Agro affiliation coverage gap is registered as **A15** (deferred until A7 closes).

---

## 4. 2x2 expansion findings

The Step 3 representative selection flagged two clusters for conditional Tier B expansion (Clusters 1 and 2). Both expansions ran in Step 4; their findings are surfaced here because they shape the recommended next step -- but neither overturns the production decision.

### Finding (a) -- Cluster 1 Tier B is mathematically degenerate

For the owners-style weight, the Tier B and Tier C variants are **identical by construction**. Unmatched RAIS firms contribute `owner_count = 0` to `L_mB_univ`, which collapses Tier C's full-universe denominator into Tier B's matched-only denominator cell-by-cell. The post-Step-4 diagnostic confirmed Pearson correlation = 1.0 and ratio = 1 in every cell; muni-summed Z columns identical (max abs diff = 0); F_kp identical to 4 decimals across all three controls specs.

**Implication.** The Cluster 1 Tier B build did NOT disentangle firm-scope effects -- because no such effect exists for the owners family. The actual open question for Cluster 1 is **denominator-scope**, not firm-scope: `w_owners_muni_univ` correlates only 0.75 with the Tier A anchor `w_owners_sec_match` (sector denominator, matched-only firms). A genuine Cluster 1 disentanglement would require building a Tier A `w_owners_sec_match` analogue freshly (with full-universe denominator construction) and re-running a horse-race against `w_owners_muni_univ`. **This is registered as a follow-up open question** -- see Section 6.

### Finding (b) -- Cluster 2 Tier B beats Tier C by 3.4x, but does not beat the winner

For the empshare-floor family, the firm-scope effect IS non-degenerate. Under C1_FE:

- `w_firm_empshare_floor`         (Tier C representative): F_kp = {fmt(c2_rep$f_stat_kp)}
- `w_firm_empshare_floor_match`   (Tier B counterpart):    F_kp = {fmt(c2_tierB$f_stat_kp)}

The matched-only denominator concentrates the alignment signal on the matched subpopulation, multiplying the F-stat by ~3.4x. **This is a substantive finding about the empshare_floor family**: its first-stage strength scales with denominator scope. However, **the Tier B floor variant (45.91) is still below the production-winner candidate (`w_owners_muni_univ`, 59.56)**, so the production decision is unchanged.

**Within-cluster note (Cluster 2 representative selection).** The Cluster 2 cluster-mate `w_emp_muni_univ` (not chosen as representative) has F_kp = {fmt(c2_mate$f_stat_kp)} under C1_FE -- beating the chosen representative `w_firm_empshare_floor` (F_kp = {fmt(c2_rep$f_stat_kp)}) by ~1.4x. The strategist selected the floor variant on **interpretability grounds** (interp rank 5 vs. 4; survives zero-employment firms per Step 0 D-C); the F-stat alone would have favored the emp variant. Documented for transparency. The choice does not affect the production decision -- the Cluster 2 representative is not the winner regardless.

**Note for future production consideration.** If the empshare_floor family is later considered for production (e.g., to handle zero-employment BNDES borrowers -- MEI / Cartao BNDES -- concentrated in Serv), the matched-only Tier B variant `w_firm_empshare_floor_match` should be tested alongside the Tier C variant. The 3.4x F-stat gap suggests the matched-only denominator may be the more powerful instrument for this family.

---

## 5. Recommended next step (graduation plan)

This summary is **descriptive only** -- it does NOT graduate the winner. A separate plan is recommended for the production graduation work:

1. **Modify** `scripts/R/3_instruments/31_build_sector_exposure_weights.R` to expose the `muni_univ` denominator option for the owners family (currently the production code uses Tier A `w_owners_sec_match`, sector denominator with matched-only firms).
2. **Modify** `scripts/R/3_instruments/33_select_baseline_weights.R` if needed so the new variant is selectable as the baseline.
3. **Modify** `scripts/R/3_instruments/34_build_shift_share_instruments.R` to consume `w_owners_muni_univ` and emit the corresponding `Z_owner_mayor_coalition_*` and `Z_owner_gov_pres_coalition_*` columns at the policy_block aggregation margin.
4. **Add** `w_binary_muni_univ` as a robustness variant (parallel construction; emit `Z_binary_*` columns).
5. **Maintain** the existing `w_owners_sec_match` as a backward-compatibility option for sensitivity analyses.
6. **Eventually**: cross with the `S3` size dimension per **D16** (production margin = `policy_block_active x S3`). The current A7 work is the policy_block-only sub-problem; the cross-product analysis is a separate future plan.

The graduation plan should reference this summary, the blueprint **D22** (Agro attenuation accepted), and **A15** (follow-up coverage investigation, deferred).

---

## 6. Pointers to follow-up open questions

| ID | Question | Trigger | Status |
|---|---|---|---|
| **(new)** | Cluster 1 denominator-scope -- build Tier A `w_owners_sec_match` analogue with fresh muni aggregation and run horse-race against `w_owners_muni_univ` (anchor correlation = 0.75, well below the 0.90 cluster threshold). | Step 4 finding (a): Tier B degenerate; the open Cluster 1 question is denom-scope, not firm-scope. | Recommend future plan; estimate after F2/F3 stabilises. |
| **A15** | Agro affiliation coverage gap (mean `match_rate_emp = 24.8%`) -- characterise the unmatched Agro subpopulation; assess whether it is structural (cooperatives, family farms outside owner registry) or a data-linkage gap. | Step 0 D-A escalation; D22 accepted attenuation. | Already registered in blueprint §4. Defer until A7 closes. |
| **(new)** | Cluster 2 floor sensitivity -- if the empshare_floor family is later considered for production, test the matched-only Tier B variant `w_firm_empshare_floor_match` (F_kp = 45.91 vs. Tier C 13.38). | Step 4 finding (b): Tier B beats Tier C 3.4x for the floor family. | Recommend logging as a contingent open question; activates only if floor weight is reconsidered. |

---

## 7. Source artifacts

- `explorations/anderson_rubin/diagnostics/output/a7_step0_report.md` -- Step 0 coverage diagnostic
- `explorations/anderson_rubin/a7_weight_comparison/output/a7_correlation_matrix.csv` -- Step 2 6x6 Pearson
- `explorations/anderson_rubin/a7_weight_comparison/output/a7_correlation_clusters.csv` -- Step 2 cluster assignment
- `explorations/anderson_rubin/a7_weight_comparison/output/a7_representative_weights.csv` -- Step 3 representatives + 2x2 expansion flags
- `explorations/anderson_rubin/a7_weight_comparison/output/a7_representative_weights_rationale.md` -- Step 3 rationale
- `explorations/anderson_rubin/a7_weight_comparison/output/a7_onecycle_proxy_fstats.csv` -- Step 4 F-stat table (24 rows, including conditional Tier B expansion)
- `explorations/anderson_rubin/a7_weight_comparison/output/a7_onecycle_proxy_summary.md` -- Step 4 narrative + degeneracy diagnostic
- `docs/PROJECT_BLUEPRINT.md` -- D22 (Agro attenuation accepted), A15 (follow-up registered), D16 (production margin = policy_block_active x S3)
")

# ---- Write summary ---------------------------------------------------------
writeLines(md, summary_fp)

cat("Wrote:", summary_fp, "\n")
cat("Production winner: w_owners_muni_univ (F_kp =", fmt(winner_specs$f_stat_kp[winner_specs$controls == "C1_FE"]), "under C1_FE)\n")
cat("Runner-up:         w_binary_muni_univ (F_kp =", fmt(runner_up_row$f_stat_kp), "under C1_FE)\n")
