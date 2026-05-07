#!/usr/bin/env Rscript

# ==============================================================================
# visualize_size_bin_battery.R
# ==============================================================================
#
# Side-by-side visualization of the size_bin_battery run from script 52:
#   4 sector taxonomies x 2 outcomes x 6 instrument combos = 48 regressions
#   extracted from 8 .tex files (one per taxonomy x outcome).
#
# Compared:
#   cnae_section, custom_sector, cnae_size_bin, sector_group_size_bin
#   x bndes_extensive, bndes_share
#   under fixed: coalition / cycle_specific / owner_count / unweighted
#                / mxj_jxt / ctrl / pooled_count
#
# Outputs:
#   quality_reports/size_bin_battery_summary.csv            (tidy long table)
#   output/tables/agg_firm_size_bin/size_bin_battery_fstat.tex
#   output/tables/agg_firm_size_bin/size_bin_battery_coef.tex
#   paper/figures/size_bin_battery_fstat.pdf                (dodged bar plot)
#   paper/figures/size_bin_battery_coef_forest.pdf          (forest plot with 95% CI)
#
# Usage:
#   Rscript scripts/R/diagnostics/visualize_size_bin_battery.R
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

# --- Bootstrap ----------------------------------------------------------------
bootstrap_file <- local({
  args_full <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", args_full, value = TRUE)
  if (length(f)) {
    script_file <- normalizePath(sub("^--file=", "", f[[1L]]), winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }
  file.path(getwd(), "scripts", "R", "_utils", "script_bootstrap.R")
})
if (file.exists(normalizePath(bootstrap_file, winslash = "/", mustWork = FALSE))) {
  source(normalizePath(bootstrap_file, winslash = "/"))
  if (exists("bootstrap_politicsregs")) bootstrap_politicsregs()
}

PROJECT_ROOT <- getOption("politicsregs.project_root", default = getwd())
TABLES_ROOT  <- file.path(PROJECT_ROOT, "paper", "tables")
FIG_DIR      <- file.path(PROJECT_ROOT, "paper", "figures")
REPORT_DIR   <- file.path(PROJECT_ROOT, "quality_reports")
OUT_TEX_DIR  <- file.path(TABLES_ROOT, "agg_firm_size_bin")
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(REPORT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_TEX_DIR, showWarnings = FALSE, recursive = TRUE)

# --- Target files -------------------------------------------------------------
# Held-fixed pattern (other dims may be regenerated, so filter by pattern).
SHARED_TOKENS <- "coalition__cycle_specific__owner_count__unweighted__mxj_jxt__ctrl__pooled_count"
COMBOS <- c("M", "G", "P", "M+G", "M+P", "M+G+P")

TAXONOMIES <- list(
  list(key = "cnae_section",          label = "CNAE Section",           dir = "agg_firm"),
  list(key = "custom_sector",         label = "Custom Sector",          dir = "agg_firm_grouped"),
  list(key = "cnae_size_bin",         label = "CNAE x Size",            dir = "agg_firm_cnae_size_bin"),
  list(key = "sector_group_size_bin", label = "Sector Group x Size",    dir = "agg_firm_sector_group_size_bin")
)
OUTCOMES <- list(
  list(key = "bndes_extensive", label = "Share Receiving BNDES"),
  list(key = "bndes_share",     label = "BNDES Share")
)

build_path <- function(tax, out) {
  slug <- sprintf("agg_firm__%s__%s__%s.tex", tax$key, out$key, SHARED_TOKENS)
  file.path(TABLES_ROOT, tax$dir, slug)
}

# --- Parsing helpers ----------------------------------------------------------
strip_tex <- function(x) {
  x <- gsub("\\\\textbf\\{([^}]+)\\}", "\\1", x)
  x <- gsub("\\\\[a-zA-Z]+\\{([^}]*)\\}", "\\1", x)
  x <- gsub("\\$|\\\\|\\{|\\}", "", x)
  trimws(x)
}

split_cells <- function(line) {
  cells <- strsplit(sub("\\\\\\\\\\s*$", "", line), "&", fixed = FALSE)[[1]]
  trimws(strip_tex(cells))
}

parse_numeric_row <- function(lines, prefix) {
  hit <- grep(prefix, lines, fixed = TRUE, value = TRUE)
  if (!length(hit)) return(rep(NA_real_, length(COMBOS)))
  cells <- split_cells(hit[1])
  vals  <- suppressWarnings(as.numeric(gsub(",", "", cells[-1])))
  length(vals) <- length(COMBOS)
  vals
}

parse_se_row <- function(lines, coef_row_idx) {
  if (is.na(coef_row_idx) || coef_row_idx + 1 > length(lines)) return(rep(NA_real_, length(COMBOS)))
  cells <- split_cells(lines[coef_row_idx + 1])
  vals  <- suppressWarnings(as.numeric(gsub("[()]", "", cells[-1])))
  length(vals) <- length(COMBOS)
  vals
}

parse_coef_with_se <- function(lines, instrument_tag) {
  idx <- grep(instrument_tag, lines, fixed = TRUE)
  if (!length(idx)) {
    return(list(coef = rep(NA_real_, length(COMBOS)), se = rep(NA_real_, length(COMBOS))))
  }
  cells <- split_cells(lines[idx[1]])
  coef  <- suppressWarnings(as.numeric(gsub("\\*", "", cells[-1])))
  length(coef) <- length(COMBOS)
  se <- parse_se_row(lines, idx[1])
  list(coef = coef, se = se)
}

parse_file <- function(path, tax, out) {
  if (!file.exists(path)) {
    warning("Missing: ", path)
    return(NULL)
  }
  lines <- readLines(path, warn = FALSE)

  # F, N, R2
  fstat <- parse_numeric_row(lines, "F")
  nobs  <- parse_numeric_row(lines, "Observations")
  r2    <- parse_numeric_row(lines, "R^2")
  if (all(is.na(r2))) r2 <- parse_numeric_row(lines, "R$^2$")

  # Coefficients for each tier
  m <- parse_coef_with_se(lines, "mayor")
  g <- parse_coef_with_se(lines, "gov")
  p <- parse_coef_with_se(lines, "pres")

  rbindlist(lapply(seq_along(COMBOS), function(i) {
    data.table(
      taxonomy       = tax$key,
      taxonomy_label = tax$label,
      outcome        = out$key,
      outcome_label  = out$label,
      combo          = COMBOS[i],
      fstat          = fstat[i],
      nobs           = nobs[i],
      r2             = r2[i],
      coef_mayor     = m$coef[i], se_mayor = m$se[i],
      coef_gov       = g$coef[i], se_gov   = g$se[i],
      coef_pres      = p$coef[i], se_pres  = p$se[i]
    )
  }))
}

# --- Ingest -------------------------------------------------------------------
all_rows <- rbindlist(lapply(TAXONOMIES, function(tax) {
  rbindlist(lapply(OUTCOMES, function(out) parse_file(build_path(tax, out), tax, out)),
            use.names = TRUE, fill = TRUE)
}), use.names = TRUE, fill = TRUE)

if (!nrow(all_rows)) {
  stop("No .tex files found. Run script 52 with --specs=size_bin_battery first.")
}

# --- CSV summary --------------------------------------------------------------
csv_path <- file.path(REPORT_DIR, "size_bin_battery_summary.csv")
fwrite(all_rows, csv_path)
cat(sprintf("Wrote %s (%d rows)\n", csv_path, nrow(all_rows)))

# --- F-stat comparison table (.tex) ------------------------------------------
fstat_wide <- dcast(all_rows, taxonomy_label + outcome_label ~ combo,
                    value.var = "fstat")
setcolorder(fstat_wide, c("taxonomy_label", "outcome_label", COMBOS))

fmt_f <- function(x) ifelse(is.na(x), "--", sprintf("%.2f", x))
tex_fstat <- c(
  "\\begin{tabular}{llcccccc}",
  "\\toprule",
  paste("Taxonomy & Outcome &", paste(COMBOS, collapse = " & "), "\\\\"),
  "\\midrule",
  apply(fstat_wide, 1, function(r) {
    paste(c(r[["taxonomy_label"]], r[["outcome_label"]],
            sapply(COMBOS, function(cc) fmt_f(as.numeric(r[[cc]])))),
          collapse = " & ")
  }) |> paste("\\\\"),
  "\\bottomrule",
  "\\end{tabular}"
)
writeLines(tex_fstat, file.path(OUT_TEX_DIR, "size_bin_battery_fstat.tex"))
cat(sprintf("Wrote %s\n", file.path(OUT_TEX_DIR, "size_bin_battery_fstat.tex")))

# --- Coefficient comparison table (M+G+P only) --------------------------------
mgp <- all_rows[combo == "M+G+P"]
fmt_coef <- function(c, s) ifelse(is.na(c), "--", sprintf("%.4f (%.4f)", c, s))

tex_coef <- c(
  "\\begin{tabular}{llccc}",
  "\\toprule",
  "Taxonomy & Outcome & $\\bar{FA}^{M}_{coal}$ & $\\bar{FA}^{G}_{coal}$ & $\\bar{FA}^{P}_{coal}$ \\\\",
  "\\midrule",
  apply(mgp, 1, function(r) {
    paste(c(r[["taxonomy_label"]], r[["outcome_label"]],
            fmt_coef(as.numeric(r[["coef_mayor"]]), as.numeric(r[["se_mayor"]])),
            fmt_coef(as.numeric(r[["coef_gov"]]),   as.numeric(r[["se_gov"]])),
            fmt_coef(as.numeric(r[["coef_pres"]]),  as.numeric(r[["se_pres"]]))),
          collapse = " & ")
  }) |> paste("\\\\"),
  "\\bottomrule",
  "\\end{tabular}"
)
writeLines(tex_coef, file.path(OUT_TEX_DIR, "size_bin_battery_coef.tex"))
cat(sprintf("Wrote %s\n", file.path(OUT_TEX_DIR, "size_bin_battery_coef.tex")))

# --- Figure 1: F-stat bar plot, dodged by taxonomy ----------------------------
fplot_data <- copy(all_rows)
fplot_data[, combo := factor(combo, levels = COMBOS)]
fplot_data[, taxonomy_label := factor(taxonomy_label,
                                      levels = sapply(TAXONOMIES, `[[`, "label"))]

p1 <- ggplot(fplot_data, aes(x = combo, y = fstat, fill = taxonomy_label)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  geom_hline(yintercept = 10, linetype = "dashed", linewidth = 0.3, colour = "grey30") +
  facet_wrap(~ outcome_label, scales = "free_y") +
  scale_fill_brewer(palette = "Set2") +
  labs(x = "Instrument combo", y = "First-stage F-statistic", fill = NULL) +
  theme_minimal(base_family = "serif", base_size = 10) +
  theme(legend.position = "bottom",
        panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold"))

ggsave(file.path(FIG_DIR, "size_bin_battery_fstat.pdf"),
       p1, width = 9, height = 4.2)
cat(sprintf("Wrote %s\n", file.path(FIG_DIR, "size_bin_battery_fstat.pdf")))

# --- Figure 2: coefficient forest plot ---------------------------------------
long_coef <- melt(all_rows,
                  id.vars = c("taxonomy_label", "outcome_label", "combo"),
                  measure.vars = patterns(coef = "^coef_", se = "^se_"),
                  variable.name = "tier")
tier_levels <- c("1" = "Mayor", "2" = "Gov", "3" = "Pres")
long_coef[, tier := factor(tier_levels[as.character(tier)], levels = tier_levels)]
long_coef[, `:=`(lo = coef - 1.96 * se, hi = coef + 1.96 * se)]
long_coef <- long_coef[combo == "M+G+P" & !is.na(coef)]
long_coef[, taxonomy_label := factor(taxonomy_label,
                                     levels = sapply(TAXONOMIES, `[[`, "label"))]

p2 <- ggplot(long_coef,
             aes(x = coef, y = taxonomy_label,
                 xmin = lo, xmax = hi, colour = tier, shape = tier)) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.3, colour = "grey30") +
  geom_pointrange(position = position_dodge(width = 0.6)) +
  facet_wrap(~ outcome_label, scales = "free_x") +
  scale_colour_brewer(palette = "Dark2") +
  labs(x = "Coefficient (95% CI)", y = NULL, colour = NULL, shape = NULL,
       subtitle = "Full M+G+P specification") +
  theme_minimal(base_family = "serif", base_size = 10) +
  theme(legend.position = "bottom",
        panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold"))

ggsave(file.path(FIG_DIR, "size_bin_battery_coef_forest.pdf"),
       p2, width = 9, height = 4)
cat(sprintf("Wrote %s\n", file.path(FIG_DIR, "size_bin_battery_coef_forest.pdf")))

# --- Console summary ----------------------------------------------------------
cat("\n== F-stats (wide) ==\n")
print(fstat_wide)
cat("\nDone.\n")
