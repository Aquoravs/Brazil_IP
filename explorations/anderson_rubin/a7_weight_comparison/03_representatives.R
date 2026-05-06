# 03_representatives.R
# A7 weight comparison — Step 3 (representative selection)
# Plan: logs/plans/2026-05-05_a7-revised-weight-comparison.md
#
# Reads the mayor-tier cluster assignment from Step 2 and emits a
# representative-per-cluster CSV with rationale. The selection logic is
# documented in the script and mirrored in the markdown sidecar produced
# alongside the CSV.
#
# Selection priority (from the plan):
#   (1) Step 0 bias flag override -- exclude flagged weights.
#       Step 0 surfaced one bias (Agro coverage; D22), but it is sector-level
#       not weight-level: all 6 Tier C weights load on Agro identically
#       (matched-only numerator, full-universe denominator). Therefore the
#       Step 0 flag does NOT distinguish weights at this aggregation; no
#       weight is overridden.
#   (2) Interpretability ranking (high to low):
#         owners > firm_empshare_floor > emp > firm > binary > binary_empshare_floor
#   (3) Construction simplicity -- prefer one-sentence formulas.
#
# Conditional 2x2 expansion flag:
#   Flagged for clusters whose Tier C representative's win in Step 4 could be
#   misleading without a Tier A/B counterpart to disentangle denominator-scope
#   (sector vs muni) or firm-scope (matched vs universe) effects.

# ---- packages (INV-15) ----
library(here)
library(data.table)
library(qs2)

# ---- paths (INV-16) ----
out_dir <- here("explorations", "anderson_rubin", "a7_weight_comparison", "output")
clusters_path <- file.path(out_dir, "a7_correlation_clusters.csv")
csv_out_path  <- file.path(out_dir, "a7_representative_weights.csv")
md_out_path   <- file.path(out_dir, "a7_representative_weights_rationale.md")

stopifnot(file.exists(clusters_path))

# ---- read Step 2 mayor-tier cluster assignment ----
clusters_all <- fread(clusters_path)
clusters <- clusters_all[tier == "mayor"]
stopifnot(nrow(clusters) == 6L)
stopifnot(uniqueN(clusters$cluster_id) == 5L)

# ---- interpretability rank table (higher rank == more interpretable) ----
# Plan ordering: owners > firm_empshare_floor > emp > firm > binary > binary_empshare_floor
interp_rank <- data.table(
  weight_id = c(
    "w_owners_muni_univ",
    "w_firm_empshare_floor",
    "w_emp_muni_univ",
    "w_firm_muni_univ",
    "w_binary_muni_univ",
    "w_binary_empshare_floor"
  ),
  interp_rank = c(6L, 5L, 4L, 3L, 2L, 1L)
)

# ---- Step 0 bias flag: NONE override at the weight level ----
# All 6 Tier C weights inherit the Agro coverage gap symmetrically; the
# flag is a Step 5 documentation point per D22, not a Step 3 exclusion.
step0_flagged <- character(0)

# ---- selection by cluster ----
clusters[, step0_bias_flag := weight_id %in% step0_flagged]
clusters <- merge(clusters, interp_rank, by = "weight_id", all.x = TRUE)

# pick representative: highest interp_rank among non-flagged cluster members
# (deterministic; ties broken by alphabetical weight_id, but no ties exist)
setorder(clusters, cluster_id, -interp_rank, weight_id)
clusters[, is_representative := (seq_len(.N) == 1L) & (!step0_bias_flag),
         by = cluster_id]

# Safety: if a cluster's only members are all flagged, we'd have no rep.
# That cannot happen here (zero flags), but guard anyway.
n_rep_per_cluster <- clusters[, sum(is_representative), by = cluster_id]
stopifnot(all(n_rep_per_cluster$V1 == 1L))

# ---- per-row rationale ----
# Hand-authored sentences; this is the substance of Step 3.
rationale_map <- list(
  # cluster 1: w_owners_muni_univ (singleton)
  w_owners_muni_univ = paste(
    "Singleton cluster. Owner-count numerator with full-universe muni denominator.",
    "Top of the interpretability ranking; carries the cleanest economic narrative",
    "(party owners as a share of all muni owners) and matches the legacy production",
    "weight on the firm-scope dimension that production already uses."
  ),
  # cluster 2: w_emp_muni_univ + w_firm_empshare_floor -- the only nontrivial pick
  w_emp_muni_univ = paste(
    "Cluster contains w_emp_muni_univ (interp rank 4) and w_firm_empshare_floor",
    "(interp rank 5). The empshare_floor variant outranks emp on interpretability",
    "because it folds firm size honestly without dropping zero-employment firms",
    "(D-C shows >=94% of zero-emp affiliated firms would survive the floor).",
    "Selected as cluster 2 representative."
  ),
  w_firm_empshare_floor = paste(
    "Cluster representative: w_firm_empshare_floor. Pairs continuous owner_party_share",
    "with a pmax(n_employees, owner_count, 1) firm weight, so zero-employment BNDES",
    "borrowers (MEI / Cartao BNDES, concentrated in Serv) re-enter the instrument",
    "rather than being silently dropped. Beats w_emp_muni_univ on interpretability",
    "rank (5 vs 4) and on coverage of a real subpopulation flagged by Step 0 D-C."
  ),
  # cluster 3: w_firm_muni_univ (singleton)
  w_firm_muni_univ = paste(
    "Singleton cluster. Equal-per-firm aggregation of continuous owner_party_share.",
    "Forced representative; rank 3 on interpretability (size-blind aggregation)",
    "but defensible as a one-sentence construction."
  ),
  # cluster 4: w_binary_muni_univ (singleton)
  w_binary_muni_univ = paste(
    "Singleton cluster. Equal-per-firm aggregation of the binary alignment indicator.",
    "Forced representative; lowest interpretability among the muni_univ family but",
    "uniquely captures the extensive-margin signal (any aligned owner)."
  ),
  # cluster 5: w_binary_empshare_floor (singleton)
  w_binary_empshare_floor = paste(
    "Singleton cluster. Binary alignment indicator weighted by employment-share-floor",
    "weights. Forced representative; the only weight that combines the extensive",
    "margin with size-honest aggregation."
  )
)

# ---- 2x2 expansion flag ----
# Only flag clusters where a Tier C win in Step 4 would be substantively
# ambiguous without a Tier A/B counterpart.
#
# Cluster 1 (w_owners_muni_univ): the replication-anchor sanity correlation
# of 0.75 with Tier A w_owners_sec_match (NOT collinear) means a Cluster 1
# win in Step 4 would NOT distinguish whether the win comes from
# denominator-scope (sector vs muni) or firm-scope (matched vs universe).
# Flag for Tier B build path so a Tier C vs Tier B comparison can isolate
# the firm-scope effect cleanly.
#
# Cluster 2 (w_firm_empshare_floor): the floor mechanism is what makes this
# weight novel; the firm-scope question (would a matched-only Tier B
# w_firm_empshare_floor look the same?) is exactly the kind of ambiguity
# the plan's expansion clause anticipates. Flag.
#
# Clusters 3, 4, 5 (w_firm_muni_univ, w_binary_muni_univ,
# w_binary_empshare_floor): if any of these wins Step 4, the conclusion
# would already be surprising relative to the owners-style weights, and
# the 2x2 expansion would only matter if the win turned out to be robust;
# defer the build to Step 4 conditional re-entry rather than pre-committing
# the labour now.

expansion_flagged_clusters <- c(1L, 2L)

expansion_rationale_map <- list(
  `1` = paste(
    "Cluster 1 representative w_owners_muni_univ correlates only 0.75 with the Tier A",
    "anchor w_owners_sec_match (well below the 0.90 threshold). A Cluster 1 win in",
    "Step 4 cannot distinguish denominator-scope (sector vs muni) from firm-scope",
    "(matched vs universe) effects without the Tier B w_owners_muni_match counterpart.",
    "Flag for the documented Tier B build path."
  ),
  `2` = paste(
    "Cluster 2 representative w_firm_empshare_floor is the novel floor weight: its win",
    "in Step 4 would invite the question of whether a matched-only Tier B counterpart",
    "(w_firm_empshare_floor restricted to matched firms) shows the same first-stage",
    "behaviour. The plan explicitly anticipates this firm-scope ambiguity for the",
    "floor family; flag for Tier B build path."
  )
)

# ---- assemble final CSV columns ----
clusters[, rationale := vapply(weight_id, function(w) rationale_map[[w]],
                                character(1))]

clusters[, flag_for_2x2_expansion := cluster_id %in% expansion_flagged_clusters]
clusters[, expansion_rationale := ""]
for (cid in expansion_flagged_clusters) {
  clusters[cluster_id == cid,
           expansion_rationale := expansion_rationale_map[[as.character(cid)]]]
}

out <- clusters[, .(
  cluster_id,
  weight_id,
  is_representative,
  rationale,
  step0_bias_flag,
  flag_for_2x2_expansion,
  expansion_rationale
)]
setorder(out, cluster_id, -is_representative, weight_id)

# ---- write CSV ----
fwrite(out, csv_out_path)

# ---- write markdown sidecar ----
md_lines <- c(
  "# A7 Step 3 -- Representative Weight Selection (Rationale)",
  "",
  "Plan: `logs/plans/2026-05-05_a7-revised-weight-comparison.md`, Step 3.",
  "Mayor-tier clustering from `a7_correlation_clusters.csv`.",
  "Step 0 inputs from `explorations/anderson_rubin/diagnostics/output/a7_step0_report.md`.",
  "",
  "## Selection rules (priority order)",
  "",
  "1. **Step 0 bias flag override** -- exclude any weight Step 0 flags as biased.",
  "2. **Interpretability ranking** (highest first):",
  "   `owners > firm_empshare_floor > emp > firm > binary > binary_empshare_floor`.",
  "3. **Construction simplicity** -- prefer one-sentence formulas.",
  "",
  "## Step 0 override applied?",
  "",
  "No weight is excluded by Step 0. The diagnostic surfaced one bias",
  "(Agro coverage degraded -- mean `match_rate_emp` 24.8%; D22 in the blueprint),",
  "but it is sector-level not weight-level: all 6 Tier C weights inherit the",
  "Agro coverage gap symmetrically (matched-only numerator, full-universe",
  "denominator). The Agro attenuation is documented as a Step 5 caveat per D22.",
  "",
  "## Cluster-by-cluster choices (mayor tier)",
  ""
)

for (cid in sort(unique(out$cluster_id))) {
  members <- out[cluster_id == cid]
  rep_row <- members[is_representative == TRUE]
  non_rep_rows <- members[is_representative == FALSE]

  member_ids <- paste0("`", members$weight_id, "`", collapse = ", ")
  md_lines <- c(md_lines,
    sprintf("### Cluster %d", cid),
    "",
    sprintf("**Members:** %s", member_ids),
    sprintf("**Representative:** `%s`", rep_row$weight_id),
    "",
    rep_row$rationale,
    ""
  )
  if (nrow(non_rep_rows) > 0L) {
    md_lines <- c(md_lines, "_Cluster-mate rationale (not selected):_", "")
    for (i in seq_len(nrow(non_rep_rows))) {
      md_lines <- c(md_lines,
        sprintf("- `%s`: %s", non_rep_rows$weight_id[i], non_rep_rows$rationale[i])
      )
    }
    md_lines <- c(md_lines, "")
  }
  if (rep_row$flag_for_2x2_expansion) {
    md_lines <- c(md_lines,
      sprintf("**2x2 expansion flag:** YES. %s", rep_row$expansion_rationale),
      ""
    )
  } else {
    md_lines <- c(md_lines,
      "**2x2 expansion flag:** No. Tier C alone is adequate for Step 4.",
      ""
    )
  }
}

md_lines <- c(md_lines,
  "## Summary",
  "",
  "Five representatives advance to Step 4 (one-cycle proxy F-stats):",
  ""
)
for (cid in sort(unique(out$cluster_id))) {
  rep_row <- out[cluster_id == cid & is_representative == TRUE]
  md_lines <- c(md_lines,
    sprintf("- Cluster %d -- `%s`%s", cid, rep_row$weight_id,
            ifelse(rep_row$flag_for_2x2_expansion, " (flagged for Tier B expansion)", ""))
  )
}
md_lines <- c(md_lines,
  "",
  "Clusters 1 and 2 carry conditional Tier B build flags. Step 4 runs on the",
  "five Tier C representatives first; Tier B is built only if a flagged",
  "representative wins or places second under primary controls (`C1_FE`)."
)

writeLines(md_lines, md_out_path)

# ---- console summary ----
message("Step 3 representatives written:")
message("  CSV:      ", csv_out_path)
message("  Markdown: ", md_out_path)
print(out[, .(cluster_id, weight_id, is_representative, flag_for_2x2_expansion)])
