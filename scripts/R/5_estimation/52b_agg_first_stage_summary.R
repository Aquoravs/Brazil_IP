#!/usr/bin/env Rscript

# =============================================================================
# 52b_agg_first_stage_summary.R — Build F-stat grid Beamer from existing tables
# =============================================================================
#
# Parses the .tex tables produced by script 52 and generates:
#   1. F-stat summary grids (like first_stage.tex)
#   2. Appendix slides for specs with genuine F>10 or p<0.05 coefficients
#      in columns whose F-statistics stay below 10,000
#
# No re-estimation — purely text parsing of existing .tex files.
#
# OUTPUT:  paper/sections/agg_first_stage.tex
# =============================================================================

cat("==============================================================================\n")
cat("52b: Aggregated First-Stage Summary (grid + appendix)\n")
cat("==============================================================================\n\n")

# --- Configuration -----------------------------------------------------------

TABLES_ROOT <- file.path("paper", "tables")
OUTPUT_FILE <- file.path("paper", "meetings", "agg_first_stage.tex")

F_SUSPICIOUS <- 10000   # F-stats above this are numerical artifacts → NA
F_PASS       <- 10      # threshold for green shading

GROUPINGS <- list(
  list(
    dir     = "agg_firm_bndes_sector",
    prefix  = "bndes_sector",
    label   = "BNDES Sector",
    texcmd  = "tbndes",
    slug_sv = "bndes_sector"
  ),
  list(
    dir     = "agg_firm_grouped",
    prefix  = "custom_sector",
    label   = "Custom Sector",
    texcmd  = "tgroup",
    slug_sv = "custom_sector"
  ),
  list(
    dir     = "agg_firm_size_bin",
    prefix  = "size_bin",
    label   = "Size Bin",
    texcmd  = "tsize",
    slug_sv = "size_bin"
  ),
  list(
    dir     = "agg_firm_bndes_sector_size_bin",
    prefix  = "bndes_sector_size_bin",
    label   = "BNDES Sector × Size Bin",
    texcmd  = "tbndessize",
    slug_sv = "bndes_sector_size_bin"
  )
)

OUTCOMES <- list(
  list(key = "bndes_extensive", label = "Share Receiving BNDES Loan",
       dep_label = "$\\text{Share of firms receiving a BNDES loan}_{jmt}$"),
  list(key = "bndes_share",     label = "BNDES Share",
       dep_label = "$\\text{BNDES share}_{jmt}$")
)

ALIGNMENTS  <- c("coalition", "party")
FE_KEYS     <- c("mxj_jxt", "mxj_mxt")
WEIGHTS     <- list(
  list(agg = "equal_firm",  rw = "unweighted",        label = "Unwtd"),
  list(agg = "employment",  rw = "emp_weighted",       label = "Emp-wtd"),
  list(agg = "owner_count", rw = "emp_share_weighted", label = "Emp-shr-wtd")
)
CTRL_KEYS   <- c("ctrl", "noctrl")
COMBOS      <- c("M", "G", "P", "M+G", "M+P", "M+G+P")

# --- Parsing helpers ----------------------------------------------------------

parse_fstats <- function(tex_path) {
  # Returns named vector of 6 F-stats (M, G, P, M+G, M+P, M+G+P)
  if (!file.exists(tex_path)) return(rep(NA_real_, 6))
  lines <- readLines(tex_path, warn = FALSE)
  fline <- grep("F\\$-statistic", lines, value = TRUE)
  if (!length(fline)) return(rep(NA_real_, 6))
  fline <- fline[1]
  # Remove LaTeX formatting
  fline <- gsub("\\\\textbf\\{([^}]+)\\}", "\\1", fline)
  fline <- gsub("\\$[^$]*\\$", "", fline)  # remove $F$-statistic label
  fline <- gsub("\\\\\\\\", "", fline)
  # Split on &

  parts <- strsplit(fline, "&")[[1]]
  parts <- trimws(parts)
  # First element is the label, rest are values
  vals <- parts[-1]
  vals <- gsub("[^0-9.eE+-]", "", vals)  # keep only numeric chars
  vals <- suppressWarnings(as.numeric(vals))
  if (length(vals) < 6) vals <- c(vals, rep(NA_real_, 6 - length(vals)))
  vals[1:6]
}

parse_sig_columns <- function(tex_path) {
  # Returns logical vector of 6 columns marking p < 0.05 coefficients (** or ***).
  if (!file.exists(tex_path)) return(rep(FALSE, 6))
  lines <- readLines(tex_path, warn = FALSE)
  coef_lines <- grep("\\\\overline\\{FA\\}", trimws(lines), value = TRUE)
  if (!length(coef_lines)) return(rep(FALSE, 6))

  sig_cols <- rep(FALSE, 6)
  for (line in coef_lines) {
    parts <- strsplit(line, "&", fixed = TRUE)[[1]]
    vals <- trimws(parts[-1])
    if (length(vals) < 6) vals <- c(vals, rep("", 6 - length(vals)))
    sig_cols <- sig_cols | grepl("\\*\\*", vals[1:6])
  }
  sig_cols
}

build_slug <- function(sv, outcome, alignment, agg, rw, fe, ctrl) {
  paste0("agg_firm__", sv, "__", outcome, "__", alignment,
         "__cycle_specific__", agg, "__", rw, "__", fe, "__", ctrl,
         "__pooled_count")
}

# --- Parse all tables ---------------------------------------------------------

cat("Parsing existing .tex tables...\n")

all_data <- list()
appendix_specs <- character(0)

for (grp in GROUPINGS) {
  table_dir <- file.path(TABLES_ROOT, grp$dir)
  for (out in OUTCOMES) {
    for (align in ALIGNMENTS) {
      for (wt in WEIGHTS) {
        for (fe in FE_KEYS) {
          for (ctrl in CTRL_KEYS) {
            slug <- build_slug(grp$slug_sv, out$key, align,
                               wt$agg, wt$rw, fe, ctrl)
            tex_path <- file.path(table_dir, paste0(slug, ".tex"))

            fstats <- parse_fstats(tex_path)
            sig_cols <- parse_sig_columns(tex_path)
            clean_f <- !is.na(fstats) & is.finite(fstats) & fstats < F_SUSPICIOUS

            # Check if this spec qualifies for appendix
            genuine_f10 <- any(clean_f & fstats > F_PASS)
            sig_with_clean_f <- any(sig_cols & clean_f)
            if (genuine_f10 || sig_with_clean_f) {
              appendix_specs <- c(appendix_specs, slug)
            }

            # Replace suspicious F-stats with NA
            fstats[!is.na(fstats) & fstats >= F_SUSPICIOUS] <- NA_real_

            key <- paste(grp$slug_sv, out$key, align, wt$agg, wt$rw, fe, ctrl, sep = "|")
            all_data[[key]] <- list(
              grouping  = grp,
              outcome   = out,
              alignment = align,
              weight    = wt,
              fe        = fe,
              ctrl      = ctrl,
              fstats    = fstats,
              slug      = slug,
              sig_cols  = sig_cols
            )
          }
        }
      }
    }
  }
}

cat(sprintf("  Parsed %d table files\n", length(all_data)))
cat(sprintf("  %d specs qualify for appendix\n", length(appendix_specs)))

# --- Build Beamer output ------------------------------------------------------

cat("Building Beamer file...\n")

L <- character(0)
add <- function(...) L <<- c(L, paste0(...))

# Preamble
add("\\documentclass[aspectratio=169,10pt]{beamer}")
add("")
add("\\usetheme{Madrid}")
add("\\usecolortheme{default}")
add("\\setbeamertemplate{navigation symbols}{}")
add("\\setbeamertemplate{footline}[frame number]")
add("\\setbeamertemplate{itemize items}[circle]")
add("")
add("\\usepackage{amsmath,amssymb,mathtools}")
add("\\usepackage{booktabs}")
add("\\usepackage{multirow}")
add("\\usepackage{makecell}")
add("\\usepackage{graphicx}")
add("\\usepackage{xcolor}")
add("\\usepackage{colortbl}")
add("\\usepackage[T1]{fontenc}")
add("\\usepackage{array}")
add("")
add("% Table directories")
add("\\newcommand{\\tbndes}{../tables/agg_firm_bndes_sector}")
add("\\newcommand{\\tgroup}{../tables/agg_firm_grouped}")
add("\\newcommand{\\tsize}{../tables/agg_firm_size_bin}")
add("\\newcommand{\\tbndessize}{../tables/agg_firm_bndes_sector_size_bin}")
add("")
add("% Colors")
add("\\definecolor{darkblue}{RGB}{0,51,102}")
add("\\definecolor{alertred}{RGB}{180,30,30}")
add("\\definecolor{pass}{RGB}{198,232,198}")
add("")
add("\\setbeamercolor{frametitle}{fg=white}")
add("\\setbeamercolor{title}{fg=white}")
add("\\setbeamercolor{structure}{fg=darkblue}")
add("")
add("\\newcommand{\\fpass}[1]{\\cellcolor{pass}\\textbf{#1}}")
add("")
add("\\title{Aggregated First-Stage Battery}")
add(sprintf("\\subtitle{Script 52b --- %s}", format(Sys.Date(), "%B %d, %Y")))
add("\\author{}")
add("\\date{}")
add("")
add("\\begin{document}")
add("")
add("\\begin{frame}")
add("\\titlepage")
add("\\end{frame}")

# --- Format helpers ---

fmt_f <- function(f) {
  if (is.na(f)) return("NA")
  if (f >= F_PASS) return(sprintf("\\fpass{%.1f}", f))
  sprintf("%.1f", f)
}

fe_label <- function(fe) {
  switch(fe,
    mxj_jxt = "MxJ+JxT",
    mxj_mxt = "MxJ+MxT"
  )
}

align_label <- function(a) {
  switch(a, coalition = "Coalition", party = "Party")
}

ctrl_label <- function(c) {
  switch(c, ctrl = "Yes", noctrl = "No")
}

section_intro_tex <- function(grp) {
  dir_label <- sprintf("{\\scriptsize \\texttt{%s}}", gsub("_", "\\\\_", grp$dir))

  switch(
    grp$slug_sv,
    bndes_sector = c(
      "\\small",
      "\\begin{itemize}",
      "\\item \\textbf{4 broad BNDES groups:} Agriculture \\& Fishing; Industry (extractive + manufacturing); Infrastructure; Trade \\& Services.",
      "\\item CNAE sections are collapsed using the BNDES sector crosswalk in script 30b.",
      "\\end{itemize}",
      "\\vfill",
      "\\begin{center}",
      dir_label,
      "\\end{center}"
    ),
    custom_sector = c(
      "\\small",
      "\\textbf{11 grouped sectors:}\\\\[0.4em]",
      "{\\scriptsize",
      "\\renewcommand{\\arraystretch}{1.08}",
      "\\begin{tabular}{@{}ll@{\\hspace{1.3em}}ll@{}}",
      "Ag & Agriculture & UCo & Utilities \\& Construction \\\\",
      "Mi & Mining & Tr & Trade \\\\",
      "CL & Light Mfg. & Tp & Transport \\\\",
      "CH & Heavy Mfg. & MS & Market Services \\\\",
      "CA & Advanced Mfg. & PSO & Public, Social \\& Other \\\\",
      "XX & Residual (dropped) & & \\\\",
      "\\end{tabular}",
      "\\par}",
      "\\vspace{0.4em}",
      "{\\scriptsize Manufacturing is split into light, heavy, and advanced blocks.}",
      "\\vfill",
      "\\begin{center}",
      dir_label,
      "\\end{center}"
    ),
    size_bin = c(
      "\\small",
      "\\begin{itemize}",
      "\\item \\textbf{3 size bins:} T1, T2, T3 = small / medium / large firms.",
      "\\item Bins are national terciles of firms' pre-election average employment.",
      "\\item Recomputed each election cycle using only pre-treatment years.",
      "\\end{itemize}",
      "\\vfill",
      "\\begin{center}",
      dir_label,
      "\\end{center}"
    ),
    bndes_sector_size_bin = c(
      "\\small",
      "\\begin{itemize}",
      "\\item \\textbf{12 composite categories:} 4 BNDES macro-sectors (Agropec\\'{u}aria, Ind\\'{u}stria, Infraestrutura, Com\\'{e}rcio e Servi\\c{c}os) $\\times$ 3 employment terciles (T1 / T2 / T3).",
      "\\item Sector crosswalk from script 30b; size terciles are national pre-election averages.",
      "\\end{itemize}",
      "\\vfill",
      "\\begin{center}",
      dir_label,
      "\\end{center}"
    ),
    c(
      "\\vfill",
      "\\begin{center}",
      dir_label,
      "\\end{center}"
    )
  )
}

# === SECTION 1: F-STAT SUMMARY GRIDS =========================================

for (grp in GROUPINGS) {
  # Section divider
  add("")
  add("% ===========================================================================")
  add(sprintf("%% %s — F-STAT GRIDS", toupper(grp$label)))
  add("% ===========================================================================")
  add("")
  add("\\begin{frame}[plain]")
  add("\\begin{center}")
  add(sprintf("{\\Large\\textbf{%s --- F-Statistic Grids}}\\\\[0.5em]", grp$label))
  add("\\end{center}")
  add(section_intro_tex(grp))
  add("\\end{frame}")

  for (out in OUTCOMES) {
    for (align in ALIGNMENTS) {
      # Build the grid: rows = FE × Weight × Ctrl, cols = 6 combos
      add("")
      add(sprintf("\\begin{frame}[t]{$F$-Statistics: %s --- %s}",
                   out$label, align_label(align)))
      add(sprintf("\\framesubtitle{%s}", grp$label))
      add("\\begin{center}")
      add("\\footnotesize")
      add("\\setlength{\\tabcolsep}{3.5pt}")
      add("\\renewcommand{\\arraystretch}{1.05}")
      add("\\begin{tabular}{@{}llrccccccc@{}}")
      add("\\toprule")
      add(" & & & \\multicolumn{6}{c}{Instrument combo} \\\\")
      add("\\cmidrule(l{2pt}r{2pt}){4-9}")
      add("FE & Weighting & Ctrl & M & G & P & M+G & M+P & M+G+P \\\\")
      add("\\midrule")

      first_fe <- TRUE
      for (fe in FE_KEYS) {
        if (!first_fe) add("\\addlinespace[5pt]")
        first_fe <- FALSE
        n_wt_rows <- length(WEIGHTS) * length(CTRL_KEYS)  # 4 rows per FE

        for (wi in seq_along(WEIGHTS)) {
          wt <- WEIGHTS[[wi]]
          for (ci in seq_along(CTRL_KEYS)) {
            ctrl <- CTRL_KEYS[ci]
            key <- paste(grp$slug_sv, out$key, align, wt$agg, wt$rw, fe, ctrl, sep = "|")
            dat <- all_data[[key]]

            fvals <- if (!is.null(dat)) dat$fstats else rep(NA_real_, 6)
            fstr <- paste(sapply(fvals, fmt_f), collapse = " & ")

            # Row label construction with multirow
            fe_cell <- ""
            wt_cell <- ""
            if (wi == 1 && ci == 1) {
              fe_cell <- sprintf("\\multirow{%d}{*}{%s}", n_wt_rows, fe_label(fe))
            }
            if (ci == 1) {
              wt_cell <- sprintf("\\multirow{%d}{*}{%s}", length(CTRL_KEYS), wt$label)
            }

            add(sprintf("  %s & %s & %s & %s \\\\",
                        fe_cell, wt_cell, ctrl_label(ctrl), fstr))
          }
        }
      }

      add("\\bottomrule")
      add("\\end{tabular}")
      add("\\end{center}")
      add("{\\scriptsize \\colorbox{pass}{\\textbf{Shaded}} = $F>10$. NA = numerical artifact ($F>10{,}000$). Cycle-specific baseline. Pooled-count exposure.}")
      add("\\end{frame}")
    }
  }
}

# === SECTION 2: APPENDIX QUALIFYING SPECS SUMMARY ============================

if (length(appendix_specs)) {
  add("")
  add("% ===========================================================================")
  add("% APPENDIX-QUALIFYING SPECS")
  add("% ===========================================================================")
  add("")
  add("\\begin{frame}[t]{Appendix Specs: $F>10$ or $p<0.05$ with $F<10{,}000$}")
  add("\\framesubtitle{Full regression tables follow}")
  add("\\begin{center}")
  add("\\footnotesize")

  # Count per grouping
  for (grp in GROUPINGS) {
    n <- sum(grepl(paste0("^agg_firm__", grp$slug_sv, "__"), appendix_specs))
    add(sprintf("\\textbf{%s:} %d specs \\quad", grp$label, n))
  }
  add("\\\\[1em]")
  add("{\\scriptsize Criteria: include a table if at least one combo has genuine $F>10$ with $F<10{,}000$, or at least one coefficient with $p<0.05$ in a combo whose $F<10{,}000$.}")
  add("\\end{center}")
  add("\\end{frame}")
}

# === SECTION 3: APPENDIX FULL TABLES =========================================

add("")
add("% ===========================================================================")
add("% APPENDIX: FULL REGRESSION TABLES")
add("% ===========================================================================")

for (grp in GROUPINGS) {
  grp_specs <- appendix_specs[grepl(paste0("^agg_firm__", grp$slug_sv, "__"), appendix_specs)]
  if (!length(grp_specs)) next

  add("")
  add("\\begin{frame}[plain]")
  add("\\begin{center}")
  add(sprintf("{\\Large\\textbf{[App] %s --- Full Tables}}", grp$label))
  add("\\end{center}")
  add("\\end{frame}")

  for (slug in grp_specs) {
    # Build a short human-readable title from slug
    parts <- strsplit(slug, "__")[[1]]
    # parts: agg_firm, sector_var, outcome, alignment, baseline, agg, rw, fe, ctrl, exposure
    outcome_lbl <- gsub("_", " ", parts[3])
    outcome_lbl <- sub("bndes extensive", "Share Receiving BNDES Loan", outcome_lbl)
    outcome_lbl <- sub("bndes share", "BNDES Share", outcome_lbl)
    align_lbl <- if (parts[4] == "coalition") "Coal" else "Party"
    wt_lbl <- switch(parts[7],
      unweighted         = "Uw",
      emp_weighted       = "Ew",
      emp_share_weighted = "Esw",
      parts[7]
    )
    fe_lbl <- if (parts[8] == "mxj_jxt") "JxT" else "MxT"
    ctrl_lbl <- if (parts[9] == "ctrl") "Ctrl" else "NoCtrl"

    title <- sprintf("[App] %s --- %s $\\cdot$ %s $\\cdot$ %s $\\cdot$ %s",
                     outcome_lbl, align_lbl, wt_lbl, fe_lbl, ctrl_lbl)

    add("")
    add(sprintf("\\begin{frame}[t,shrink=5]{%s}", title))
    add(sprintf("\\framesubtitle{%s}", grp$label))
    add("\\begin{center}\\footnotesize")
    add(sprintf("\\input{\\%s/%s}", grp$texcmd, slug))
    add("\\end{center}")
    add("\\end{frame}")
  }
}

# === SECTION 4: TAXONOMY DIAGNOSTICS SLIDE (if available) ====================

DIAG_TEX <- file.path(TABLES_ROOT, "agg_firm_size_bin", "sector_taxonomy_diagnostics.tex")

if (file.exists(DIAG_TEX)) {
  add("")
  add("% ===========================================================================")
  add("% SECTOR TAXONOMY DIAGNOSTICS")
  add("% ===========================================================================")
  add("")
  add("\\begin{frame}[plain]")
  add("\\begin{center}")
  add("{\\Large\\textbf{Sector Taxonomy Diagnostics (D1--D7)}}")
  add("\\end{center}")
  add("\\small")
  add("\\begin{itemize}")
  add("\\item D1: Cell counts (obs, cells, median/P10 firms per cell)")
  add("\\item D3: First-stage relevance --- max $F$-statistic from existing tables")
  add("\\item D6: Thin-cell audit (share of cells with $<3$ firms)")
  add("\\item D7: Muni-level aggregation fidelity (Shannon entropy of sector shares)")
  add("\\end{itemize}")
  add("\\end{frame}")
  add("")
  add("\\begin{frame}[t,shrink=5]{Sector Taxonomy Diagnostics}")
  add("\\framesubtitle{D1, D3, D6, D7 summary --- run \\texttt{sector\\_taxonomy\\_diagnostics.R} to refresh}")
  add("\\begin{center}\\footnotesize")
  add("\\input{../tables/agg_firm_size_bin/sector_taxonomy_diagnostics}")
  add("\\end{center}")
  add("{\\scriptsize $\\dagger$ thin-cell rate $>10\\%$; \\textbf{bold} = $F>10$.}")
  add("\\end{frame}")

  cat(sprintf("  Taxonomy diagnostics slide included (found %s)\n", DIAG_TEX))
} else {
  cat(sprintf("  Taxonomy diagnostics slide skipped (not found: %s)\n", DIAG_TEX))
  cat("  Run scripts/R/diagnostics/sector_taxonomy_diagnostics.R to generate.\n")
}

add("")
add("\\end{document}")

# --- Write output -------------------------------------------------------------

writeLines(L, OUTPUT_FILE)
cat(sprintf("\nDone. Wrote %d lines to %s\n", length(L), OUTPUT_FILE))
cat(sprintf("  Grid slides: %d\n",
    length(GROUPINGS) * length(OUTCOMES) * length(ALIGNMENTS)))
cat(sprintf("  Appendix slides: %d\n", length(appendix_specs)))
