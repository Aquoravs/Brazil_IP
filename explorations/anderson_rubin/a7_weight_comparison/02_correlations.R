# ==============================================================================
# 02_correlations.R
#
# Step 2 — Pairwise Pearson correlation matrix and hierarchical clustering
# for the 6 Tier C candidate weights, across all 3 alignment tiers
# (mayor_coalition, gov_coalition, pres_coalition).
#
# Plan:  logs/plans/2026-05-05_a7-revised-weight-comparison.md §"Step 2"
# Input: explorations/anderson_rubin/a7_weight_comparison/output/
#          a7_instruments_panel.qs2
#          (70,587 muni-year rows × 24 columns; years 2005–2017)
#
# Outputs:
#   output/a7_correlation_matrix.csv   — 6×6 Pearson, all 3 tiers (stacked)
#   output/a7_correlation_clusters.csv — weight_id × cluster_id, all 3 tiers
#   output/a7_correlation_heatmap.pdf  — 3-panel heatmap (one panel per tier)
#
# Paper reference: explorations/anderson_rubin/README.md
#
# ============================================================
# Paper-to-Code Naming Map
# ============================================================
# Paper Notation            | Code Name                       | Description
# w_owners_muni_univ        | TIER_C_WEIGHTS[1]               | Owner-count / muni total
# w_emp_muni_univ           | TIER_C_WEIGHTS[2]               | Employment / muni total
# w_firm_muni_univ          | TIER_C_WEIGHTS[3]               | Equal-per-firm, owner_party_share
# w_binary_muni_univ        | TIER_C_WEIGHTS[4]               | Equal-per-firm, binary alignment
# w_firm_empshare_floor     | TIER_C_WEIGHTS[5]               | Emp-share-floor, owner_party_share
# w_binary_empshare_floor   | TIER_C_WEIGHTS[6]               | Emp-share-floor, binary alignment
# Replication anchor        | ANCHOR_ID                       | w_owners_sec_match (excluded from 6×6)
# Z_<weight>_<tier>         | col_<tier>                      | Muni-level instrument vector
# |ρ| > 0.90                | CLUSTER_CUT_HEIGHT = 0.10       | Collapse threshold
# ============================================================
#
# NOTE on year range: the instrument panel (Step 1) covers 2005–2017
# (cycle-specific baseline; first treatment year is 2005 for the 2002-06
# mayor cycle). The plan mentions "2002–2017" as the pooling window, but
# 2002–2004 rows do not exist in a7_instruments_panel.qs2 because those
# are baseline years, not instrument years. All available rows (2005–2017)
# are used. This deviation is documented here and in the console output.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Packages (INV-15: all at top)
# ------------------------------------------------------------------------------
library(data.table)
library(qs2)
library(here)
library(ggplot2)
library(patchwork)

setDTthreads(0L)

# ------------------------------------------------------------------------------
# 2. Paths (INV-16: no absolute paths — all via here())
# ------------------------------------------------------------------------------
OUTPUT_DIR <- here::here(
  "explorations", "anderson_rubin", "a7_weight_comparison", "output"
)
if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  message("Created output directory: ", OUTPUT_DIR)
}

path_panel <- file.path(OUTPUT_DIR, "a7_instruments_panel.qs2")

# ------------------------------------------------------------------------------
# 3. Constants
# ------------------------------------------------------------------------------

# The 6 Tier C weight IDs (short labels — the column suffix after Z_ and before _<tier>_coalition)
TIER_C_WEIGHT_IDS <- c(
  "w_owners_muni_univ",
  "w_emp_muni_univ",
  "w_firm_muni_univ",
  "w_binary_muni_univ",
  "w_firm_empshare_floor",
  "w_binary_empshare_floor"
)

# The 3 alignment tiers
TIERS <- c("mayor", "gov", "pres")
TIER_LABELS <- c(
  mayor = "Mayor coalition",
  gov   = "Governor coalition",
  pres  = "President coalition"
)

# Replication anchor — excluded from correlation matrix, used for sanity check
ANCHOR_ID <- "w_owners_sec_match"

# Hierarchical clustering distance threshold:
# height = 1 - |rho|, so cut at 0.10 <=> |rho| > 0.90
CLUSTER_CUT_HEIGHT <- 0.10

# ------------------------------------------------------------------------------
# 4. Load instrument panel
# ------------------------------------------------------------------------------
message("Loading a7_instruments_panel.qs2 ...")
if (!file.exists(path_panel)) {
  stop("Input file not found: ", path_panel,
       "\nRun 01_build_weights.R first.")
}
panel <- setDT(qs_read(path_panel))

message(sprintf(
  "  Panel loaded: %s rows x %d cols. Years: %d-%d.",
  format(nrow(panel), big.mark = ","),
  ncol(panel),
  min(panel$year),
  max(panel$year)
))

# Confirm zero NAs in all instrument columns
z_cols_all <- names(panel)[grepl("^Z_", names(panel))]
na_counts  <- vapply(z_cols_all, function(x) sum(is.na(panel[[x]])), integer(1L))
if (any(na_counts > 0L)) {
  warning("NAs found in instrument columns: ",
          paste(names(na_counts)[na_counts > 0L], collapse = ", "))
} else {
  message("  NA check passed: 0 NAs in all ", length(z_cols_all), " instrument columns.")
}

# ------------------------------------------------------------------------------
# 5. Helper: build column name from weight_id + tier
#    E.g.: weight_id="w_owners_muni_univ", tier="mayor"
#          => "Z_owners_muni_univ_mayor_coalition"
# ------------------------------------------------------------------------------
z_col_name <- function(weight_id, tier) {
  # Strip leading "w_" from weight_id to form the column stub
  stub <- sub("^w_", "", weight_id)
  paste0("Z_", stub, "_", tier, "_coalition")
}

# Verify all expected columns exist
expected_cols <- unlist(lapply(TIERS, function(t) {
  vapply(TIER_C_WEIGHT_IDS, z_col_name, character(1L), tier = t)
}))
anchor_cols <- vapply(TIERS, function(t) z_col_name(ANCHOR_ID, t), character(1L))

missing <- setdiff(c(expected_cols, anchor_cols), names(panel))
if (length(missing) > 0L) {
  stop("Missing expected columns in panel:\n  ",
       paste(missing, collapse = "\n  "))
}
message("  Column presence check passed for all Tier C + anchor columns.")

# ------------------------------------------------------------------------------
# 6. Correlation matrix computation
#    For each tier: extract the 6 Tier C instrument columns,
#    compute 6×6 Pearson correlation matrix.
#    Also compute anchor vs. first Tier C weight as sanity check.
# ------------------------------------------------------------------------------
message("\nComputing correlation matrices ...")

# Pre-allocate result list: one element per tier
cor_results <- vector("list", length(TIERS))
names(cor_results) <- TIERS

cluster_results <- vector("list", length(TIERS))
names(cluster_results) <- TIERS

anchor_sanity <- vector("list", length(TIERS))
names(anchor_sanity) <- TIERS

for (tier in TIERS) {

  message(sprintf("\n  Tier: %s", tier))

  # Extract the 6 Tier C columns for this tier
  tier_cols <- vapply(TIER_C_WEIGHT_IDS, z_col_name, character(1L), tier = tier)
  mat       <- as.matrix(panel[, ..tier_cols])

  # Name columns with weight_ids (short names for readability)
  colnames(mat) <- TIER_C_WEIGHT_IDS

  # 6x6 Pearson correlation
  cor_mat <- cor(mat, method = "pearson", use = "pairwise.complete.obs")

  # Symmetry check (within 1e-9)
  sym_check <- max(abs(cor_mat - t(cor_mat)))
  if (sym_check > 1e-9) {
    warning(sprintf("Tier %s: correlation matrix asymmetry = %.2e (> 1e-9)", tier, sym_check))
  }

  # Range check: diagonal == 1, off-diagonals in [-1, 1]
  diag_check     <- all(abs(diag(cor_mat) - 1) < 1e-9)
  offdiag_check  <- all(abs(cor_mat[row(cor_mat) != col(cor_mat)]) <= 1 + 1e-9)
  if (!diag_check)    warning(sprintf("Tier %s: diagonal not exactly 1", tier))
  if (!offdiag_check) warning(sprintf("Tier %s: off-diagonal out of [-1, 1]", tier))

  message(sprintf(
    "    Symmetry max |diff| = %.2e | Diagonal == 1: %s | Range ok: %s",
    sym_check, diag_check, offdiag_check
  ))

  cor_results[[tier]] <- cor_mat

  # ---- Hierarchical clustering on (1 - |rho|) ----
  dist_mat <- as.dist(1 - abs(cor_mat))
  hc       <- hclust(dist_mat, method = "single")
  clusters <- cutree(hc, h = CLUSTER_CUT_HEIGHT)

  cluster_dt <- data.table(
    tier      = tier,
    weight_id = names(clusters),
    cluster_id = as.integer(clusters)
  )
  cluster_results[[tier]] <- cluster_dt

  n_clusters <- uniqueN(clusters)
  message(sprintf("    Clusters at h = %.2f: %d", CLUSTER_CUT_HEIGHT, n_clusters))
  for (k in sort(unique(clusters))) {
    members <- names(clusters)[clusters == k]
    message(sprintf("      Cluster %d: %s", k, paste(members, collapse = " | ")))
  }

  # ---- Sanity check: anchor vs. first Tier C weight ----
  # anchor = w_owners_sec_match; first Tier C = w_owners_muni_univ
  anchor_col <- z_col_name(ANCHOR_ID, tier)
  first_col  <- z_col_name(TIER_C_WEIGHT_IDS[1L], tier)

  rho_anchor <- cor(
    panel[[anchor_col]],
    panel[[first_col]],
    method = "pearson",
    use    = "pairwise.complete.obs"
  )
  anchor_sanity[[tier]] <- list(
    anchor = ANCHOR_ID,
    first  = TIER_C_WEIGHT_IDS[1L],
    rho    = rho_anchor
  )
  message(sprintf(
    "    Anchor sanity (|rho| between %s and %s): %.6f",
    ANCHOR_ID, TIER_C_WEIGHT_IDS[1L], abs(rho_anchor)
  ))
}

# ------------------------------------------------------------------------------
# 7. Export correlation matrices: one CSV with all 3 tiers stacked
#    Columns: tier, row_weight, col_weight, rho
# ------------------------------------------------------------------------------
message("\nExporting correlation matrix CSV ...")

cor_long_list <- vector("list", length(TIERS))
for (tier in TIERS) {
  mat <- cor_results[[tier]]
  # Melt to long form
  cor_long <- as.data.table(as.table(mat))
  setnames(cor_long, c("row_weight", "col_weight", "rho"))
  cor_long[, tier := tier]
  cor_long_list[[which(TIERS == tier)]] <- cor_long
}
cor_long_all <- rbindlist(cor_long_list)
setcolorder(cor_long_all, c("tier", "row_weight", "col_weight", "rho"))
setorder(cor_long_all, tier, row_weight, col_weight)

# Also write the wide (matrix) form for the mayor tier as the primary deliverable
cor_wide_mayor <- as.data.table(cor_results[["mayor"]], keep.rownames = TRUE)
setnames(cor_wide_mayor, "rn", "weight_id")

path_cor_matrix <- file.path(OUTPUT_DIR, "a7_correlation_matrix.csv")
fwrite(cor_wide_mayor, path_cor_matrix)
message(sprintf("  Written: a7_correlation_matrix.csv (%d rows — mayor tier 6×6 wide)",
                nrow(cor_wide_mayor)))

# Supplementary: full long-form CSV with all 3 tiers
path_cor_long <- file.path(OUTPUT_DIR, "a7_correlation_matrix_all_tiers.csv")
fwrite(cor_long_all, path_cor_long)
message(sprintf("  Written: a7_correlation_matrix_all_tiers.csv (%d rows — all tiers long)",
                nrow(cor_long_all)))

# ------------------------------------------------------------------------------
# 8. Export cluster assignments: one CSV with all 3 tiers stacked
# ------------------------------------------------------------------------------
message("Exporting cluster assignment CSV ...")

clusters_all <- rbindlist(cluster_results)
setcolorder(clusters_all, c("tier", "weight_id", "cluster_id"))
setorder(clusters_all, tier, cluster_id, weight_id)

path_clusters <- file.path(OUTPUT_DIR, "a7_correlation_clusters.csv")
fwrite(clusters_all, path_clusters)
message(sprintf("  Written: a7_correlation_clusters.csv (%d rows)", nrow(clusters_all)))

# ------------------------------------------------------------------------------
# 9. Heatmap — 3-panel PDF
#    One panel per tier. No in-figure title (INV-12). Serif font.
#    Color scale diverges around 0: scale_fill_distiller(palette = "RdBu").
#    Panel labels (INV-12 exception): "Mayor coalition", etc. inside each panel.
# ------------------------------------------------------------------------------
message("Building 3-panel heatmap ...")

# Weight ID display labels (short, readable)
WEIGHT_LABELS <- c(
  "w_owners_muni_univ"       = "owners",
  "w_emp_muni_univ"          = "emp",
  "w_firm_muni_univ"         = "firm",
  "w_binary_muni_univ"       = "binary",
  "w_firm_empshare_floor"    = "firm\n(emp-floor)",
  "w_binary_empshare_floor"  = "binary\n(emp-floor)"
)

# Factor order for axes (fixed across all panels)
WEIGHT_FACTOR_LEVELS <- TIER_C_WEIGHT_IDS

# Build one ggplot per tier
make_heatmap_panel <- function(tier) {

  cor_mat <- cor_results[[tier]]

  # Convert to long form for ggplot
  dt <- as.data.table(as.table(cor_mat))
  setnames(dt, c("row_weight", "col_weight", "rho"))

  dt[, row_weight := factor(row_weight, levels = rev(WEIGHT_FACTOR_LEVELS))]
  dt[, col_weight := factor(col_weight, levels = WEIGHT_FACTOR_LEVELS)]

  # Display labels on axes
  dt[, row_lab := WEIGHT_LABELS[as.character(row_weight)]]
  dt[, col_lab := WEIGHT_LABELS[as.character(col_weight)]]

  # Factor with short labels, same order
  short_levels_rev <- rev(WEIGHT_LABELS[WEIGHT_FACTOR_LEVELS])
  short_levels     <- WEIGHT_LABELS[WEIGHT_FACTOR_LEVELS]

  dt[, row_lab := factor(WEIGHT_LABELS[as.character(row_weight)],
                         levels = short_levels_rev)]
  dt[, col_lab := factor(WEIGHT_LABELS[as.character(col_weight)],
                         levels = short_levels)]

  # Text label: round to 2 decimal places; omit diagonal (rho==1)
  dt[, rho_txt := ifelse(
    abs(rho - 1) < 1e-9,
    "1.00",
    sprintf("%.2f", rho)
  )]

  ggplot(dt, aes(x = col_lab, y = row_lab, fill = rho)) +
    geom_tile(color = "white", linewidth = 0.4) +
    geom_text(aes(label = rho_txt), size = 2.8,
              family = "serif", color = "grey10") +
    scale_fill_distiller(
      palette  = "RdBu",
      limits   = c(-1, 1),
      direction = 1,
      name     = expression(rho)
    ) +
    labs(
      x       = NULL,
      y       = NULL,
      # No ggtitle — INV-12.  Panel label via subtitle (treated as panel label)
      subtitle = TIER_LABELS[[tier]]
    ) +
    theme_minimal(base_family = "serif") +
    theme(
      axis.text.x      = element_text(size = 7, angle = 30, hjust = 1),
      axis.text.y      = element_text(size = 7),
      plot.subtitle    = element_text(size = 9, face = "bold", hjust = 0.5),
      legend.title     = element_text(size = 8),
      legend.text      = element_text(size = 7),
      legend.key.width = unit(0.4, "cm"),
      panel.grid       = element_blank()
    )
}

p_mayor <- make_heatmap_panel("mayor")
p_gov   <- make_heatmap_panel("gov")
p_pres  <- make_heatmap_panel("pres")

# Combine with patchwork; collect shared legend
combined <- (p_mayor | p_gov | p_pres) +
  plot_layout(guides = "collect") +
  plot_annotation(
    caption = paste0(
      "Pearson correlations among 6 Tier C candidate SSIV weights at the policy_block margin.",
      "\nRows/columns: weight IDs. Color and text: correlation coefficient.",
      "\nHierarchical clustering (single linkage, distance = 1 - |rho|) cut at h = 0.10 (|rho| > 0.90).",
      "\nInstrument panel: a7_instruments_panel.qs2, years 2005-2017, cycle-specific baseline."
    ),
    theme = theme(
      plot.caption = element_text(family = "serif", size = 6.5,
                                  hjust = 0, color = "grey30")
    )
  ) &
  theme(legend.position = "right")

path_heatmap <- file.path(OUTPUT_DIR, "a7_correlation_heatmap.pdf")
ggsave(path_heatmap,
       plot   = combined,
       width  = 12,
       height = 5,
       device = "pdf")
message(sprintf("  Written: a7_correlation_heatmap.pdf  (12 x 5 in)"))

# ------------------------------------------------------------------------------
# 10. Console summary
# ------------------------------------------------------------------------------
message("\n")
message("=================================================================")
message("  A7 Correlation Matrix & Clustering — Summary")
message("=================================================================")
message(sprintf(
  "  Input: %s muni-year rows, years %d-%d.",
  format(nrow(panel), big.mark = ","), min(panel$year), max(panel$year)
))
message("  NOTE: Plan specified 2002-2017; instrument panel starts 2005")
message("        (baseline years 2002-2004 are not observation rows).")
message("")

for (tier in TIERS) {
  cor_mat   <- cor_results[[tier]]
  clusters  <- cluster_results[[tier]]
  n_clusters <- uniqueN(clusters$cluster_id)

  message(sprintf("  --- Tier: %s ---", TIER_LABELS[[tier]]))

  # Print 6x6 matrix (rounded)
  message("  Correlation matrix (6x6, Pearson):")
  cor_rounded <- round(cor_mat, 4)
  # Print row by row
  row_prefix <- format(rownames(cor_rounded), width = 26)
  header_str <- paste0("  ", formatC("", width = 27), " ",
                       paste(formatC(colnames(cor_rounded), width = 9, flag = "-"),
                             collapse = " "))
  message(header_str)
  for (i in seq_len(nrow(cor_rounded))) {
    vals <- formatC(cor_rounded[i, ], format = "f", digits = 4, width = 9)
    message(sprintf("  %-27s %s", rownames(cor_rounded)[i],
                    paste(vals, collapse = " ")))
  }

  # Flag high pairs (|rho| > 0.90, off-diagonal)
  high_pairs <- NULL
  low_pairs  <- NULL
  for (r in seq_len(nrow(cor_mat))) {
    for (c in seq_len(ncol(cor_mat))) {
      if (r >= c) next
      rho_val <- cor_mat[r, c]
      if (abs(rho_val) > 0.90) {
        high_pairs <- c(high_pairs,
                        sprintf("%s <-> %s: %.4f",
                                rownames(cor_mat)[r],
                                colnames(cor_mat)[c],
                                rho_val))
      }
      if (abs(rho_val) < 0.30) {
        low_pairs <- c(low_pairs,
                       sprintf("%s <-> %s: %.4f",
                               rownames(cor_mat)[r],
                               colnames(cor_mat)[c],
                               rho_val))
      }
    }
  }

  if (length(high_pairs) > 0L) {
    message(sprintf("  Pairs with |rho| > 0.90 (%d):", length(high_pairs)))
    for (p_str in high_pairs) message("    ", p_str)
  } else {
    message("  No pairs with |rho| > 0.90.")
  }

  if (length(low_pairs) > 0L) {
    message(sprintf("  Pairs with |rho| < 0.30 (%d):", length(low_pairs)))
    for (p_str in low_pairs) message("    ", p_str)
  } else {
    message("  No pairs with |rho| < 0.30.")
  }

  message(sprintf("  Clusters at h = %.2f: %d cluster(s)",
                  CLUSTER_CUT_HEIGHT, n_clusters))
  for (k in sort(unique(clusters$cluster_id))) {
    members <- clusters[cluster_id == k, weight_id]
    message(sprintf("    Cluster %d: %s", k, paste(members, collapse = " | ")))
  }

  san <- anchor_sanity[[tier]]
  message(sprintf(
    "  Anchor sanity |rho| (%s vs %s): %.6f",
    san$anchor, san$first, abs(san$rho)
  ))
  message("")
}

message("  Output files:")
message("    ", path_cor_matrix)
message("    ", path_cor_long)
message("    ", path_clusters)
message("    ", path_heatmap)
message("=================================================================")

# ------------------------------------------------------------------------------
# 11. Verification assertions (INV-14: deterministic — no seed needed)
# ------------------------------------------------------------------------------
message("\nRunning verification assertions ...")

for (tier in TIERS) {
  mat <- cor_results[[tier]]

  # 6x6 check
  stopifnot("Correlation matrix must be 6x6" = all(dim(mat) == 6L))

  # Symmetry check
  stopifnot("Correlation matrix must be symmetric within 1e-9" =
              max(abs(mat - t(mat))) < 1e-9)

  # Diagonal == 1 check
  stopifnot("Diagonal must equal 1 within 1e-9" =
              all(abs(diag(mat) - 1) < 1e-9))

  # Off-diagonal range check
  off <- mat[row(mat) != col(mat)]
  stopifnot("Off-diagonals must be in [-1, 1]" =
              all(abs(off) <= 1 + 1e-9))
}

# All 3 tiers in cluster output
stopifnot("All 3 tiers must appear in cluster CSV" =
            all(TIERS %in% clusters_all$tier))

# All 6 weights per tier in cluster output
for (tier in TIERS) {
  t <- tier  # local copy to avoid data.table name clash
  tier_weights <- clusters_all[clusters_all$tier == t, weight_id]
  if (!all(TIER_C_WEIGHT_IDS %in% tier_weights)) {
    stop(sprintf("Tier %s: missing weights in cluster CSV", t))
  }
}

# All output files exist
for (f in c(path_cor_matrix, path_cor_long, path_clusters, path_heatmap)) {
  if (!file.exists(f)) {
    stop("Output file not found: ", f)
  }
}

message("  All assertions passed.")
message("")
message("Done. 02_correlations.R complete.")

# Return invisibly for interactive inspection
invisible(list(
  cor_results     = cor_results,
  cluster_results = clusters_all,
  anchor_sanity   = anchor_sanity
))
