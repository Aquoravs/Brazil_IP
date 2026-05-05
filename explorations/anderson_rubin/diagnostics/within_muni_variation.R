# ==============================================================================
# within_muni_variation.R
#
# F1 diagnostic: within-muni x time variance decomposition of BNDES credit
# shares for three candidate aggregation margins, under two denominator
# definitions.
#
# Foundation under test (docs/PROJECT_BLUEPRINT.md, F1):
#   "For at least one F0-margin, BNDES credit shares have meaningful
#    within-muni x time variation."
#   If shares are flat within muni over time, muni FE absorb everything
#   -> no first-stage variation -> IV degenerates.
#
# Margins:
#   M1. cnae_section          (21 bins, A-U)
#   M2. policy_block          (5 bins: Agro/Ind/Infra/Serv/XX)
#   M3. policy_block_active   (4 bins: Agro/Ind/Infra/Serv only)
#
# Denominators (per margin):
#   V1 (active-only):  s_{m,b,t} = L / sum_{b' in active} L
#                      Shares of XX bins are NA under V1.
#   V2 (full economy): s_{m,b,t} = L / sum_{b'} L
#                      All bins in denominator (incl. XX).
#
# L_{m,b,t} = sum of value_dis_real_2018_total over firms with in_bndes==1
#             in (muni m, bin b, year t).
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst (preferred)
#   data/processed/rais_bndes_reconstructed.qs2 (fallback)
#   data/processed/policy_block_mapping.qs2
#
# Outputs (in explorations/anderson_rubin/diagnostics/output/):
#   variation_decomposition.csv         one row per margin x denom x bin
#   variation_by_muni.csv               one row per margin x denom x muni x bin
#   variation_summary.csv               one row per margin x denom (verdict)
#   variation_within_muni_density.pdf   density of sigma_within faceted by margin
#   variation_top_munis.csv             5 most + 5 least variable munis x annual series
#   within_muni_variation_report.md     interpretation + F1 verdict
#
# Paper reference: explorations/anderson_rubin/README.md
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Packages (INV-15: all at top)
# ------------------------------------------------------------------------------
library(data.table)
library(qs2)
library(here)
library(ggplot2)

HAS_FST <- requireNamespace("fst", quietly = TRUE)
if (HAS_FST) library(fst)

setDTthreads(0L)

# ------------------------------------------------------------------------------
# 2. Paths via here::here() (INV-16: no absolute paths)
# ------------------------------------------------------------------------------
PROCESSED_DIR <- here::here("data", "processed")
OUTPUT_DIR    <- here::here(
  "explorations", "anderson_rubin", "diagnostics", "output"
)

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  message("Created output directory: ", OUTPUT_DIR)
}

path_fst <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst")
path_qs2 <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.qs2")
path_cw  <- file.path(PROCESSED_DIR, "policy_block_mapping.qs2")

# ------------------------------------------------------------------------------
# 3. Constants
# ------------------------------------------------------------------------------
CNAE_ORDER  <- c("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K",
                 "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U")
XX_SECTIONS <- c("K", "O", "T", "U")
BLOCK_ORDER   <- c("Agro", "Ind", "Infra", "Serv", "XX")
ACTIVE_BLOCKS <- c("Agro", "Ind", "Infra", "Serv")

# F1 verdict thresholds (heuristic — see report)
F1_SIGMA_MEDIAN_MIN          <- 0.05  # cross-muni median sigma_within
F1_SHARE_WITHIN_MIN          <- 0.20  # within / total variance ratio
F1_SHARE_WITHIN_REJECT_BELOW <- 0.10  # below this: clearly REJECTED

# ------------------------------------------------------------------------------
# 4. Load policy_block crosswalk
# ------------------------------------------------------------------------------
message("Loading policy_block crosswalk...")

if (!file.exists(path_cw)) {
  stop("Missing crosswalk: ", path_cw,
       "\nRun script 30e first.")
}

crosswalk <- setDT(qs_read(path_cw))
stopifnot(all(c("cnae_section", "policy_block") %in% names(crosswalk)))
stopifnot(nrow(crosswalk) == 21L)
message(sprintf("  Crosswalk loaded: %d CNAE sections.", nrow(crosswalk)))

# ------------------------------------------------------------------------------
# 5. Load reconstructed RAIS-BNDES panel (column-selective)
# ------------------------------------------------------------------------------
COLS_NEEDED <- c("firm_id", "muni_id", "year", "cnae_section",
                 "in_bndes", "value_dis_real_2018_total", "n_employees")

message("Loading reconstructed RAIS-BNDES panel...")

if (HAS_FST && file.exists(path_fst)) {
  message("  Source: fst (column-selective) — ", basename(path_fst))
  panel <- fst::read_fst(path_fst, columns = COLS_NEEDED, as.data.table = TRUE)
} else if (file.exists(path_qs2)) {
  message("  Source: qs2 — ", basename(path_qs2))
  raw <- qs_read(path_qs2)
  setDT(raw)
  missing_cols <- setdiff(COLS_NEEDED, names(raw))
  if (length(missing_cols) > 0L) {
    stop("qs2 file missing columns: ", paste(missing_cols, collapse = ", "))
  }
  panel <- raw[, .SD, .SDcols = COLS_NEEDED]
  rm(raw); invisible(gc())
} else {
  stop("Neither fst nor qs2 panel file found.\n",
       "Expected:\n  ", path_fst, "\n  or\n  ", path_qs2)
}

stopifnot(is.data.table(panel))
stopifnot(all(COLS_NEEDED %in% names(panel)))
panel[, in_bndes := as.integer(in_bndes)]
panel[is.na(value_dis_real_2018_total), value_dis_real_2018_total := 0]

message(sprintf("  Panel loaded: %s firm-years.",
                format(nrow(panel), big.mark = ",")))

# ------------------------------------------------------------------------------
# 6. Build BNDES-only working dataset
#    Filter to in_bndes == 1, drop missing/empty cnae, merge policy_block.
# ------------------------------------------------------------------------------
message("Building BNDES-only working dataset...")

bndes_panel <- panel[in_bndes == 1L &
                       !is.na(cnae_section) &
                       cnae_section != ""]

bndes_panel <- merge(
  bndes_panel,
  crosswalk[, .(cnae_section, policy_block)],
  by    = "cnae_section",
  all.x = TRUE
)

n_unmatched <- bndes_panel[is.na(policy_block), .N]
if (n_unmatched > 0L) {
  warning(sprintf(
    "%d BNDES firm-years unmatched in crosswalk; dropped from analysis.",
    n_unmatched
  ))
  bndes_panel <- bndes_panel[!is.na(policy_block)]
}

message(sprintf(
  "  BNDES-only working dataset: %s firm-years across %s munis, %d years.",
  format(nrow(bndes_panel),                   big.mark = ","),
  format(uniqueN(bndes_panel$muni_id),        big.mark = ","),
  uniqueN(bndes_panel$year)
))

# Free the full panel after this point — analysis only uses BNDES rows.
rm(panel); invisible(gc())

# ------------------------------------------------------------------------------
# 7. Margin-processing function
#
# For a given margin, returns a long DT with one row per
# (margin x denom x muni x year x bin), where:
#   margin = margin_label
#   denom  = "V1" or "V2"
#   share  = s_v1 or s_v2 (NA where undefined under V1)
#
# Universe: (m, t) with total muni BNDES > 0. Bins not observed in (m, t)
# have L = 0 (and therefore share = 0 under V2; s_v1 = 0 if bin is active).
# ------------------------------------------------------------------------------
process_margin <- function(margin_label, margin_var,
                           all_bins, active_bins, output_bins) {

  message(sprintf("\n  Margin: %s (var=%s, %d bins all, %d active, %d output)",
                  margin_label, margin_var,
                  length(all_bins), length(active_bins), length(output_bins)))

  # Aggregate L over firms within (muni, year, bin)
  agg <- bndes_panel[get(margin_var) %in% all_bins,
                     .(L = sum(value_dis_real_2018_total, na.rm = TRUE)),
                     by = c("muni_id", "year", margin_var)]
  setnames(agg, margin_var, "bin")

  # Per-(m, t) totals
  totals <- agg[, .(
    total_full   = sum(L, na.rm = TRUE),
    total_active = sum(L[bin %in% active_bins], na.rm = TRUE)
  ), by = .(muni_id, year)]

  # Restrict universe to (m, t) with total muni BNDES > 0
  totals <- totals[total_full > 0]
  message(sprintf(
    "    Universe: %s muni-years with total BNDES > 0.",
    format(nrow(totals), big.mark = ",")
  ))

  # Expand to dense (m, t, bin) over all_bins; merge in observed L
  dense_keys <- totals[, .(bin = all_bins), by = .(muni_id, year)]
  dense      <- merge(dense_keys, totals, by = c("muni_id", "year"))
  dense      <- merge(dense, agg, by = c("muni_id", "year", "bin"), all.x = TRUE)
  dense[is.na(L), L := 0]

  # Compute shares
  is_active <- dense$bin %in% active_bins
  dense[, s_v1 := fifelse(is_active & total_active > 0,
                          L / total_active,
                          NA_real_)]
  dense[, s_v2 := L / total_full]   # total_full > 0 by construction

  # Restrict to output bins (M3 drops XX from output)
  dense <- dense[bin %in% output_bins]

  # Stack V1 and V2 long
  long_v1 <- dense[, .(margin = margin_label, denom = "V1",
                        muni_id, year, bin, share = s_v1)]
  long_v2 <- dense[, .(margin = margin_label, denom = "V2",
                        muni_id, year, bin, share = s_v2)]

  rbind(long_v1, long_v2)
}

# ------------------------------------------------------------------------------
# 8. Process all three margins -> shares_long
# ------------------------------------------------------------------------------
message("Processing margins...")

shares_long <- rbindlist(list(
  process_margin(
    margin_label = "cnae_section",
    margin_var   = "cnae_section",
    all_bins     = CNAE_ORDER,
    active_bins  = setdiff(CNAE_ORDER, XX_SECTIONS),
    output_bins  = CNAE_ORDER
  ),
  process_margin(
    margin_label = "policy_block",
    margin_var   = "policy_block",
    all_bins     = BLOCK_ORDER,
    active_bins  = ACTIVE_BLOCKS,
    output_bins  = BLOCK_ORDER
  ),
  process_margin(
    margin_label = "policy_block_active",
    margin_var   = "policy_block",
    all_bins     = BLOCK_ORDER,
    active_bins  = ACTIVE_BLOCKS,
    output_bins  = ACTIVE_BLOCKS
  )
))

message(sprintf("\n  shares_long: %s rows across margins x denoms.",
                format(nrow(shares_long), big.mark = ",")))

# ------------------------------------------------------------------------------
# 9. Per-muni summaries: mean, n_years, sigma_within
# ------------------------------------------------------------------------------
message("Computing per-muni summaries...")

by_muni <- shares_long[!is.na(share),
                       .(n_years      = .N,
                         mean_share   = mean(share),
                         sigma_within = if (.N >= 2L) stats::sd(share) else NA_real_),
                       by = .(margin, denom, muni_id, bin)]

# ------------------------------------------------------------------------------
# 10. Variance decomposition per (margin, denom, bin)
#     Per spec:
#       total_var       = Var(s_{m,b,t}) across all (m,t)
#       between_muni_var = Var(mean_t s_{m,b,t}) across m
#       within_muni_var  = Var(s_{m,b,t} - mean_t s_{m,b,t}) across all (m,t)
#       share_within     = within_muni_var / total_var
# ------------------------------------------------------------------------------
message("Computing variance decompositions...")

shares_with_means <- merge(
  shares_long[!is.na(share)],
  by_muni[, .(margin, denom, muni_id, bin, mean_share)],
  by = c("margin", "denom", "muni_id", "bin")
)
shares_with_means[, residual := share - mean_share]

decomp_core <- shares_with_means[, .(
  n_obs            = .N,
  n_munis          = uniqueN(muni_id),
  mean_share_overall = mean(share),
  total_var        = if (.N >= 2L) stats::var(share)    else NA_real_,
  within_muni_var  = if (.N >= 2L) stats::var(residual) else NA_real_
), by = .(margin, denom, bin)]

# Between-muni variance: Var of muni-level mean across munis (need >= 2 munis)
between_var <- by_muni[, .(
  between_muni_var = if (.N >= 2L) stats::var(mean_share) else NA_real_
), by = .(margin, denom, bin)]

decomposition <- merge(decomp_core, between_var,
                       by = c("margin", "denom", "bin"), all.x = TRUE)

decomposition[, share_within := fifelse(
  !is.na(total_var) & total_var > 0,
  within_muni_var / total_var,
  NA_real_
)]

# Cross-muni quantiles of sigma_within per (margin, denom, bin)
sigma_quantiles <- by_muni[!is.na(sigma_within), {
  q <- stats::quantile(sigma_within, probs = c(0.10, 0.50, 0.90), names = FALSE)
  .(p10_sigma_within   = q[1],
    med_sigma_within   = q[2],
    p90_sigma_within   = q[3],
    n_munis_with_sigma = .N)
}, by = .(margin, denom, bin)]

decomposition <- merge(decomposition, sigma_quantiles,
                       by = c("margin", "denom", "bin"), all.x = TRUE)

# ------------------------------------------------------------------------------
# 11. Reindex to full (margin, denom, bin) grid; order canonically
#     Ensures V1 + XX rows appear with NA values, per spec.
# ------------------------------------------------------------------------------
all_combos <- rbindlist(list(
  CJ(margin = "cnae_section",
     denom  = c("V1", "V2"),
     bin    = CNAE_ORDER),
  CJ(margin = "policy_block",
     denom  = c("V1", "V2"),
     bin    = BLOCK_ORDER),
  CJ(margin = "policy_block_active",
     denom  = c("V1", "V2"),
     bin    = ACTIVE_BLOCKS)
))

decomposition <- merge(all_combos, decomposition,
                       by = c("margin", "denom", "bin"), all.x = TRUE)

# Bin ordering for output
bin_order_dt <- rbindlist(list(
  data.table(margin = "cnae_section",
             bin    = CNAE_ORDER,
             bin_order = seq_along(CNAE_ORDER)),
  data.table(margin = "policy_block",
             bin    = BLOCK_ORDER,
             bin_order = seq_along(BLOCK_ORDER)),
  data.table(margin = "policy_block_active",
             bin    = ACTIVE_BLOCKS,
             bin_order = seq_along(ACTIVE_BLOCKS))
))
decomposition <- merge(decomposition, bin_order_dt,
                       by = c("margin", "bin"), all.x = TRUE)

setorder(decomposition, margin, denom, bin_order)
decomposition[, bin_order := NULL]

setcolorder(decomposition, c(
  "margin", "denom", "bin",
  "n_obs", "n_munis", "n_munis_with_sigma",
  "mean_share_overall",
  "total_var", "between_muni_var", "within_muni_var", "share_within",
  "p10_sigma_within", "med_sigma_within", "p90_sigma_within"
))

# ------------------------------------------------------------------------------
# 12. Per (margin x denom) summary + F1 verdict
# ------------------------------------------------------------------------------
message("Computing margin x denom summary and F1 verdict...")

variation_summary <- decomposition[, .(
  n_bins_total                  = .N,
  n_bins_with_share_within      = sum(!is.na(share_within)),
  max_share_within              = if (any(!is.na(share_within))) {
    max(share_within, na.rm = TRUE)
  } else NA_real_,
  med_share_within_across_bins  = if (any(!is.na(share_within))) {
    stats::median(share_within, na.rm = TRUE)
  } else NA_real_,
  max_med_sigma_within          = if (any(!is.na(med_sigma_within))) {
    max(med_sigma_within, na.rm = TRUE)
  } else NA_real_,
  med_med_sigma_within          = if (any(!is.na(med_sigma_within))) {
    stats::median(med_sigma_within, na.rm = TRUE)
  } else NA_real_,
  any_bin_supports_f1           = any(
    !is.na(med_sigma_within) & !is.na(share_within) &
      med_sigma_within > F1_SIGMA_MEDIAN_MIN &
      share_within     > F1_SHARE_WITHIN_MIN,
    na.rm = TRUE
  )
), by = .(margin, denom)]

variation_summary[, verdict := fcase(
  any_bin_supports_f1,                                    "SUPPORTED",
  is.na(max_share_within),                                "INCONCLUSIVE",
  max_share_within < F1_SHARE_WITHIN_REJECT_BELOW,        "REJECTED",
  default                                                = "INCONCLUSIVE"
)]

# Order: margin then denom
margin_order_dt <- data.table(
  margin = c("cnae_section", "policy_block", "policy_block_active"),
  margin_order = 1:3
)
variation_summary <- merge(variation_summary, margin_order_dt,
                           by = "margin", all.x = TRUE)
setorder(variation_summary, margin_order, denom)
variation_summary[, margin_order := NULL]

# Overall F1 verdict (across margins x denoms)
n_supported    <- variation_summary[verdict == "SUPPORTED",   .N]
n_rejected     <- variation_summary[verdict == "REJECTED",    .N]
n_inconclusive <- variation_summary[verdict == "INCONCLUSIVE", .N]
n_total_specs  <- nrow(variation_summary)

f1_overall <- fcase(
  n_supported >= 1L,                                 "CONFIRMED",
  n_rejected == n_total_specs,                       "BLOCKED",
  default                                            = "PARTIAL"
)

# ------------------------------------------------------------------------------
# 13. Top / bottom munis selection
#
# "Most variable" muni for a (margin, denom): mean of sigma_within across
# the bins that are defined (i.e., for V1, excludes XX bins which are NA).
# ------------------------------------------------------------------------------
message("Selecting top / bottom munis per margin x denom...")

muni_overall <- by_muni[!is.na(sigma_within),
                        .(mean_sigma_across_bins = mean(sigma_within),
                          max_sigma_across_bins  = max(sigma_within),
                          n_bins_used            = .N),
                        by = .(margin, denom, muni_id)]

# Need at least 5 munis per (margin x denom) to pick top/bottom 5
muni_counts <- muni_overall[, .N, by = .(margin, denom)]
sparse_groups <- muni_counts[N < 10L]
if (nrow(sparse_groups) > 0L) {
  warning("Some (margin, denom) groups have fewer than 10 munis with sigma:\n",
          paste(capture.output(print(sparse_groups)), collapse = "\n"))
}

# Top 5 (most variable)
top_munis <- muni_overall[order(-mean_sigma_across_bins),
                          head(.SD, 5L),
                          by = .(margin, denom)]
top_munis[, rank_type := "top"]

# Bottom 5 (least variable)
bot_munis <- muni_overall[order(mean_sigma_across_bins),
                          head(.SD, 5L),
                          by = .(margin, denom)]
bot_munis[, rank_type := "bottom"]

picked_munis <- rbind(top_munis, bot_munis)

# Annual share series for picked munis
top_munis_series <- merge(
  shares_long,
  picked_munis[, .(margin, denom, muni_id, rank_type,
                   mean_sigma_across_bins, max_sigma_across_bins)],
  by    = c("margin", "denom", "muni_id"),
  allow.cartesian = TRUE
)

# Order
top_munis_series <- merge(top_munis_series, bin_order_dt,
                          by = c("margin", "bin"), all.x = TRUE)
setorder(top_munis_series, margin, denom, rank_type, muni_id, bin_order, year)
top_munis_series[, bin_order := NULL]

setcolorder(top_munis_series, c(
  "margin", "denom", "rank_type", "muni_id",
  "mean_sigma_across_bins", "max_sigma_across_bins",
  "bin", "year", "share"
))

# ------------------------------------------------------------------------------
# 14. Order by_muni canonically for output
# ------------------------------------------------------------------------------
by_muni_out <- merge(by_muni, bin_order_dt,
                     by = c("margin", "bin"), all.x = TRUE)
by_muni_out <- merge(by_muni_out, margin_order_dt,
                     by = "margin", all.x = TRUE)
setorder(by_muni_out, margin_order, denom, muni_id, bin_order)
by_muni_out[, c("bin_order", "margin_order") := NULL]

setcolorder(by_muni_out, c(
  "margin", "denom", "muni_id", "bin",
  "n_years", "mean_share", "sigma_within"
))

# ------------------------------------------------------------------------------
# 15. Write CSVs
# ------------------------------------------------------------------------------
message("Writing output CSVs...")

fwrite(decomposition,
       file.path(OUTPUT_DIR, "variation_decomposition.csv"))
message("  Written: variation_decomposition.csv (", nrow(decomposition), " rows)")

fwrite(by_muni_out,
       file.path(OUTPUT_DIR, "variation_by_muni.csv"))
message("  Written: variation_by_muni.csv      (", nrow(by_muni_out), " rows)")

fwrite(variation_summary,
       file.path(OUTPUT_DIR, "variation_summary.csv"))
message("  Written: variation_summary.csv     (", nrow(variation_summary), " rows)")

fwrite(top_munis_series,
       file.path(OUTPUT_DIR, "variation_top_munis.csv"))
message("  Written: variation_top_munis.csv   (", nrow(top_munis_series), " rows)")

# ------------------------------------------------------------------------------
# 16. Density plot: sigma_within faceted by margin, color = denom
# ------------------------------------------------------------------------------
message("Building density plot...")

plot_data <- by_muni[!is.na(sigma_within)]
plot_data[, margin_lab := factor(
  margin,
  levels = c("cnae_section", "policy_block", "policy_block_active"),
  labels = c("M1: cnae_section (21 bins)",
             "M2: policy_block (5 bins)",
             "M3: policy_block_active (4 bins)")
)]
plot_data[, denom_lab := factor(
  denom,
  levels = c("V1", "V2"),
  labels = c("V1 (active-only)", "V2 (full economy)")
)]

# Cap x-axis at p99 to keep tails from dominating
x_cap <- stats::quantile(plot_data$sigma_within, 0.99, na.rm = TRUE)
x_cap <- max(x_cap, F1_SIGMA_MEDIAN_MIN * 4)

p <- ggplot(plot_data, aes(x = sigma_within, color = denom_lab,
                           fill = denom_lab, linetype = denom_lab)) +
  geom_density(alpha = 0.25, na.rm = TRUE) +
  geom_vline(xintercept = F1_SIGMA_MEDIAN_MIN,
             linetype = "dashed", color = "grey40") +
  facet_wrap(~ margin_lab, ncol = 1, scales = "free_y") +
  coord_cartesian(xlim = c(0, x_cap)) +
  scale_color_brewer(palette = "Set2") +
  scale_fill_brewer(palette  = "Set2") +
  scale_linetype_manual(values = c("solid", "longdash")) +
  labs(
    x        = expression("Per-muni " * sigma[within] *
                          " of bin share across years"),
    y        = "Density",
    color    = "Denominator",
    fill     = "Denominator",
    linetype = "Denominator"
  ) +
  theme_minimal(base_family = "serif") +
  theme(
    legend.position = "bottom",
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold")
  )

ggsave(file.path(OUTPUT_DIR, "variation_within_muni_density.pdf"),
       plot = p, width = 7.5, height = 9, device = "pdf")
message("  Written: variation_within_muni_density.pdf")

# ------------------------------------------------------------------------------
# 17. Markdown report
# ------------------------------------------------------------------------------
message("Generating within_muni_variation_report.md...")

fmt_num <- function(x, digits = 4) {
  ifelse(is.na(x), "—", sprintf(paste0("%.", digits, "f"), x))
}
fmt_int <- function(x) {
  ifelse(is.na(x), "—", format(as.integer(x), big.mark = ","))
}

verdict_emoji <- function(v) {
  fcase(v == "SUPPORTED",     "[YES]",
        v == "REJECTED",      "[NO]",
        v == "INCONCLUSIVE",  "[?]",
        default               = "")
}

# Header
report_lines <- c(
  "# Within-Muni x Time Variation Diagnostic — F1 Test",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## Goal",
  "",
  "Test foundation **F1** (`docs/PROJECT_BLUEPRINT.md` §3):",
  "",
  "> *For at least one F0-margin, BNDES credit shares have meaningful within-muni x time variation.*",
  "",
  "If shares are flat within muni over time, muni FE absorb everything → no first-stage variation → IV degenerates. F1 is the most cheaply falsified link in the identification chain.",
  "",
  "## Setup",
  "",
  paste0("- Universe: muni-years with total muni BNDES > 0."),
  paste0("- L_{m,b,t} = sum of `value_dis_real_2018_total` over firms with ",
         "`in_bndes == 1` in (muni m, bin b, year t)."),
  paste0("- Margins: M1 (`cnae_section`, 21 bins), M2 (`policy_block`, 5 bins), ",
         "M3 (`policy_block_active`, 4 bins)."),
  paste0("- Denominators: V1 (active-only, sum over non-XX bins) vs ",
         "V2 (full economy, includes XX)."),
  "",
  paste0("**SUPPORTED heuristic:** at least one bin has cross-muni median ",
         "sigma_within > ", F1_SIGMA_MEDIAN_MIN,
         " AND share_within > ", F1_SHARE_WITHIN_MIN, "."),
  paste0("**REJECTED heuristic:** max share_within across bins < ",
         F1_SHARE_WITHIN_REJECT_BELOW, "."),
  "",
  "---",
  "",
  "## 1. F1 Verdict",
  "",
  paste0("**Overall F1 verdict: ", f1_overall, "**"),
  "",
  sprintf("- Supported (margin × denom): %d / %d",
          n_supported, n_total_specs),
  sprintf("- Rejected:                   %d / %d",
          n_rejected, n_total_specs),
  sprintf("- Inconclusive:               %d / %d",
          n_inconclusive, n_total_specs),
  ""
)

# Per (margin, denom) verdict table
report_lines <- c(report_lines,
  "### Per-spec verdict",
  "",
  paste0("| Margin | Denom | Verdict | Max share_within | Max med σ_within | ",
         "Med share_within | Med med σ_within | n bins |"),
  paste0("|--------|-------|---------|------------------|------------------|",
         "------------------|------------------|--------|"))

for (i in seq_len(nrow(variation_summary))) {
  r <- variation_summary[i]
  report_lines <- c(report_lines, sprintf(
    "| %s | %s | %s %s | %s | %s | %s | %s | %d |",
    r$margin, r$denom,
    r$verdict, verdict_emoji(r$verdict),
    fmt_num(r$max_share_within, 3),
    fmt_num(r$max_med_sigma_within, 3),
    fmt_num(r$med_share_within_across_bins, 3),
    fmt_num(r$med_med_sigma_within, 3),
    r$n_bins_total
  ))
}
report_lines <- c(report_lines, "")

# Per-margin sections
margin_meta <- list(
  cnae_section        = "M1. cnae_section (21-bin: A–U)",
  policy_block        = "M2. policy_block (5-bin: Agro/Ind/Infra/Serv/XX)",
  policy_block_active = "M3. policy_block_active (4-bin: Agro/Ind/Infra/Serv)"
)

for (this_margin in names(margin_meta)) {
  report_lines <- c(report_lines,
    "---",
    "",
    paste0("## 2. ", margin_meta[[this_margin]]),
    ""
  )

  for (this_denom in c("V1", "V2")) {
    denom_lab <- if (this_denom == "V1") {
      "V1 (active-only denominator)"
    } else {
      "V2 (full-economy denominator)"
    }

    sub <- decomposition[margin == this_margin & denom == this_denom]
    v   <- variation_summary[margin == this_margin & denom == this_denom]
    v_str <- if (nrow(v) == 0L) "—" else paste0(v$verdict, " ", verdict_emoji(v$verdict))

    report_lines <- c(report_lines,
      sprintf("### %s — %s", this_denom, denom_lab),
      "",
      paste0("**Verdict:** ", v_str),
      "",
      paste0("| Bin | n_munis | Mean s | Total Var | Btw Var | Within Var | ",
             "share_within | p10 σ | Med σ | p90 σ |"),
      paste0("|-----|---------|--------|-----------|---------|------------|",
             "--------------|-------|-------|-------|"))

    for (i in seq_len(nrow(sub))) {
      r <- sub[i]
      report_lines <- c(report_lines, sprintf(
        "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |",
        r$bin,
        fmt_int(r$n_munis_with_sigma),
        fmt_num(r$mean_share_overall, 4),
        fmt_num(r$total_var, 5),
        fmt_num(r$between_muni_var, 5),
        fmt_num(r$within_muni_var, 5),
        fmt_num(r$share_within, 3),
        fmt_num(r$p10_sigma_within, 3),
        fmt_num(r$med_sigma_within, 3),
        fmt_num(r$p90_sigma_within, 3)
      ))
    }
    report_lines <- c(report_lines, "")
  }

  # V1 vs V2 comparison
  v1 <- variation_summary[margin == this_margin & denom == "V1", verdict]
  v2 <- variation_summary[margin == this_margin & denom == "V2", verdict]
  v1 <- if (length(v1) == 0L) "—" else v1
  v2 <- if (length(v2) == 0L) "—" else v2

  cmp <- if (v1 == v2) {
    sprintf("Denominator choice does **not** change the verdict (V1=%s, V2=%s).",
            v1, v2)
  } else {
    sprintf("Denominator choice **CHANGES** the verdict: V1=%s, V2=%s. ",
            v1, v2)
  }
  report_lines <- c(report_lines,
    paste0("**V1 vs V2:** ", cmp),
    ""
  )
}

# Top/bottom munis section
report_lines <- c(report_lines,
  "---",
  "",
  "## 3. Top / Bottom Muni Sanity Check",
  "",
  paste0("Per (margin x denom), the 5 most variable + 5 least variable munis ",
         "(by mean sigma_within across bins) and their annual share series ",
         "are written to `variation_top_munis.csv`. Inspect these to verify ",
         "the numbers correspond to plausible patterns."),
  ""
)

# Files produced
report_lines <- c(report_lines,
  "---",
  "",
  "## 4. Files Produced",
  "",
  "| File | Rows | Description |",
  "|------|------|-------------|",
  sprintf("| variation_decomposition.csv | %d | One row per margin x denom x bin: variance decomp + sigma quantiles |",
          nrow(decomposition)),
  sprintf("| variation_by_muni.csv | %d | One row per margin x denom x muni x bin: n_years, mean, sigma_within |",
          nrow(by_muni_out)),
  sprintf("| variation_summary.csv | %d | One row per margin x denom: F1 verdict |",
          nrow(variation_summary)),
  sprintf("| variation_top_munis.csv | %d | Annual share series for top/bottom 5 munis |",
          nrow(top_munis_series)),
  "| variation_within_muni_density.pdf | — | Density of sigma_within faceted by margin, colored by denom |",
  ""
)

# Implications
report_lines <- c(report_lines,
  "---",
  "",
  "## 5. Implications for Identification",
  ""
)

if (f1_overall == "CONFIRMED") {
  report_lines <- c(report_lines,
    paste0("F1 is **CONFIRMED** on at least one (margin x denom) specification. ",
           "Within-muni x time variation in BNDES credit shares exists for at ",
           "least one candidate margin under at least one denominator choice. ",
           "The shift-share IV identification strategy is not degenerate at ",
           "the F1 link. **Next:** A6 (firm vs. project CNAE reconciliation, F2)."),
    ""
  )
} else if (f1_overall == "BLOCKED") {
  report_lines <- c(report_lines,
    paste0("F1 is **BLOCKED**: every (margin x denom) specification rejects ",
           "F1 (max share_within < ", F1_SHARE_WITHIN_REJECT_BELOW, "). The ",
           "identification chain breaks at F1 — muni FE absorb essentially ",
           "all variation in BNDES credit shares, leaving the IV degenerate. ",
           "**STOP** further code work; the research design needs a different ",
           "aggregation margin or a different identifying assumption."),
    ""
  )
} else {
  report_lines <- c(report_lines,
    paste0("F1 is **PARTIAL**: no (margin x denom) clearly supports F1, but ",
           "not all are decisively rejected. The identification chain is ",
           "weakly viable. **Next:** investigate whether any margin from A1 ",
           "(BNDES institutional review) is more promising than the current ",
           "candidates, then re-run this diagnostic."),
    ""
  )
}

writeLines(report_lines,
           file.path(OUTPUT_DIR, "within_muni_variation_report.md"))
message("  Written: within_muni_variation_report.md")

# ------------------------------------------------------------------------------
# 18. Console summary
# ------------------------------------------------------------------------------
message("\n")
message("=================================================================")
message("  Within-Muni x Time Variation Diagnostic — Summary")
message("=================================================================")
message(sprintf("  Overall F1 verdict: %s", f1_overall))
message(sprintf("  Supported / Rejected / Inconclusive: %d / %d / %d (of %d specs)",
                n_supported, n_rejected, n_inconclusive, n_total_specs))
message("")
message("  Per (margin x denom):")
for (i in seq_len(nrow(variation_summary))) {
  r <- variation_summary[i]
  message(sprintf("    %-22s %s : %s  (max share_within=%s, max med σ=%s)",
                  r$margin, r$denom, r$verdict,
                  fmt_num(r$max_share_within, 3),
                  fmt_num(r$max_med_sigma_within, 3)))
}
message("")
message("  Output files written to:")
message("    ", OUTPUT_DIR)
message("=================================================================")

# ------------------------------------------------------------------------------
# 19. Return invisible list for interactive inspection
# ------------------------------------------------------------------------------
invisible(list(
  decomposition     = decomposition,
  by_muni           = by_muni_out,
  variation_summary = variation_summary,
  top_munis_series  = top_munis_series,
  f1_overall        = f1_overall
))
