#!/usr/bin/env Rscript
# Build sector group distribution table for Beamer presentation
# Reads bndes_credit_shares_grouped.qs2 and outputs a LaTeX table

library(data.table)

# --- Paths -------------------------------------------------------------------
BNDES_BASE <- Sys.getenv("BNDES_BASE", unset = path.expand("~/BNDES"))
OUTPUT_DIR <- Sys.getenv("BNDES_OUTPUT", unset = file.path(BNDES_BASE, "output"))

# --- Load data ---------------------------------------------------------------
cs <- qs2::qs_read(file.path(OUTPUT_DIR, "bndes_credit_shares_grouped.qs2"))
setDT(cs)

sg <- qs2::qs_read(file.path(OUTPUT_DIR, "sector_group_mapping.qs2"))
setDT(sg)

# Labels lookup (one row per sector_group)
labels <- unique(sg[, .(sector_group, sector_group_label)])

# --- Compute summary statistics by sector group ------------------------------
stats <- cs[, .(
  mean_share   = mean(s_mjt, na.rm = TRUE),
  pct_positive = 100 * mean(bndes_mjt > 0, na.rm = TRUE),
  n_obs        = .N
), by = sector_group]

stats <- merge(stats, labels, by = "sector_group", all.x = TRUE)
# Escape LaTeX special characters in labels
stats[, sector_group_label := gsub("&", "\\\\&", sector_group_label)]
setorder(stats, -mean_share)

# --- Build LaTeX table --------------------------------------------------------
header <- paste0(
  "\\begin{tabular}{llrrr}\n",
  "\\toprule\n",
  "\\textbf{Group} & \\textbf{Label} & \\textbf{Mean $s_{mjt}$} & ",
  "\\textbf{\\% Positive} & \\textbf{$N$ obs} \\\\\n",
  "\\midrule\n"
)

rows <- stats[, sprintf(
  "%s & %s & %.3f & %.1f\\%% & %s \\\\",
  sector_group,
  sector_group_label,
  mean_share,
  pct_positive,
  formatC(n_obs, format = "d", big.mark = ",")
)]

footer <- paste0(
  "\\midrule\n",
  sprintf("\\multicolumn{4}{l}{Total observations} & %s \\\\\n",
          formatC(nrow(cs), format = "d", big.mark = ",")),
  "\\bottomrule\n",
  "\\end{tabular}"
)

tex <- paste(c(header, rows, footer), collapse = "\n")

# --- Write output -------------------------------------------------------------
out_dir <- file.path(OUTPUT_DIR, "muni_reg_tables_grouped")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
out_file <- file.path(out_dir, "sector_group_distribution.tex")
writeLines(tex, out_file)

cat("Sector group distribution table written to:\n")
cat("  ", out_file, "\n")
