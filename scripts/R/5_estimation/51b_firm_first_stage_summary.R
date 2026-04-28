#!/usr/bin/env Rscript

# =============================================================================
# 51b_firm_first_stage_summary.R — Build F-stat grid Beamer from firm tables
# =============================================================================
#
# Parses the .tex tables produced by script 51 and generates:
#   1. F-stat summary grids across outcome × baseline × alignment
#   2. Appendix slides for specs with genuine F>10 or p<0.05 coefficients
#      in columns whose F-statistics stay below 10,000
#
# No re-estimation — purely text parsing of existing .tex files.
#
# Filename convention (firm tables):
#   firm__{family}__{spec}__{outcome}__{alignment}__{baseline}__{weighting}__
#   {sample}__{exposure}.tex
#
# Fixed tokens: family=main, spec=levels, sample=all_firms
#
# OUTPUT:  paper/meetings/first_stage.tex
# =============================================================================

cat("==============================================================================\n")
cat("51b: Firm-Level First-Stage Summary (grid + appendix)\n")
cat("==============================================================================\n\n")

# --- Configuration -----------------------------------------------------------

TABLE_DIR   <- file.path("paper", "tables", "firm")
OUTPUT_FILE <- file.path("paper", "meetings", "first_stage.tex")

F_SUSPICIOUS <- 10000   # F-stats above this are numerical artifacts → NA
F_PASS       <- 10      # threshold for green shading

OUTCOMES <- list(
  list(key    = "bndes_extensive",
       label  = "$F$-Statistics: BNDES Extensive --- $\\mathbf{1}(\\text{BNDES}>0)$",
       is_rf  = FALSE),
  list(key    = "bndes_intensive",
       label  = "$F$-Statistics: BNDES Intensive --- $\\log(\\text{BNDES})$",
       is_rf  = FALSE),
  list(key    = "employment_log",
       label  = "$F$-Statistics: Employment Log",
       is_rf  = TRUE),
  list(key    = "employment_share",
       label  = "$F$-Statistics: Employment Share",
       is_rf  = TRUE)
)

ALIGNMENTS <- c("coalition", "party")

BASELINES <- list(
  list(key = "2002_fixed",     label = "Panel A: 2002-fixed baseline"),
  list(key = "cycle_specific", label = "Panel B: Cycle-specific baseline")
)

WEIGHTS <- list(
  list(key = "emp_weighted",       label = "Emp.-weighted"),
  list(key = "emp_share_weighted", label = "Emp.-share-wt'd"),
  list(key = "unweighted",         label = "Unweighted")
)

EXPOSURES <- list(
  list(key = "binary",       label = "Binary"),
  list(key = "pooled_count", label = "Pooled")
)

COMBOS <- c("M", "G", "P", "M+G", "M+P", "M+G+P")

# Fixed tokens
FAMILY <- "main"
SPEC   <- "levels"
SAMPLE <- "all_firms"

# --- Slug builder -------------------------------------------------------------

build_slug <- function(outcome, alignment, baseline, weighting, exposure) {
  paste("firm", FAMILY, SPEC, outcome, alignment, baseline, weighting, SAMPLE,
        exposure, sep = "__")
}

# --- Parsing helpers ----------------------------------------------------------

parse_fstats <- function(tex_path) {
  # Returns numeric vector of 6 F-stats (M, G, P, M+G, M+P, M+G+P)
  if (!file.exists(tex_path)) return(rep(NA_real_, 6))
  lines <- readLines(tex_path, warn = FALSE)
  fline <- grep("F\\$-statistic", lines, value = TRUE)
  if (!length(fline)) return(rep(NA_real_, 6))
  fline <- fline[1]
  # Strip \textbf{...}
  fline <- gsub("\\\\textbf\\{([^}]+)\\}", "\\1", fline)
  # Strip $...$  tokens (removes the "F$-statistic" label remnant)
  fline <- gsub("\\$[^$]*\\$", "", fline)
  # Strip trailing \\
  fline <- gsub("\\\\\\\\", "", fline)
  # Split on &
  parts <- strsplit(fline, "&")[[1]]
  parts <- trimws(parts)
  # First element is the (now empty) label cell; rest are values
  vals <- parts[-1]
  vals <- gsub("[^0-9.eE+-]", "", vals)
  vals <- suppressWarnings(as.numeric(vals))
  if (length(vals) < 6) vals <- c(vals, rep(NA_real_, 6 - length(vals)))
  vals <- vals[1:6]
  # Mask numerical artifacts
  vals[!is.na(vals) & vals >= F_SUSPICIOUS] <- NA_real_
  vals
}

parse_sig_columns <- function(tex_path) {
  # Returns logical vector of 6: TRUE where p<0.05 (** or ***) in FA^{ rows
  if (!file.exists(tex_path)) return(rep(FALSE, 6))
  lines <- readLines(tex_path, warn = FALSE)
  coef_lines <- grep("FA\\^\\{", lines, value = TRUE)
  if (!length(coef_lines)) return(rep(FALSE, 6))
  sig_cols <- rep(FALSE, 6)
  for (line in coef_lines) {
    parts <- strsplit(line, "&", fixed = TRUE)[[1]]
    vals  <- trimws(parts[-1])
    if (length(vals) < 6) vals <- c(vals, rep("", 6 - length(vals)))
    sig_cols <- sig_cols | grepl("\\*\\*", vals[1:6])
  }
  sig_cols
}

# --- Parse all tables ---------------------------------------------------------

cat("Parsing existing .tex tables...\n")

all_data       <- list()
appendix_specs <- character(0)

for (out in OUTCOMES) {
  for (align in ALIGNMENTS) {
    for (bl in BASELINES) {
      for (wt in WEIGHTS) {
        for (ex in EXPOSURES) {
          slug     <- build_slug(out$key, align, bl$key, wt$key, ex$key)
          tex_path <- file.path(TABLE_DIR, paste0(slug, ".tex"))

          fstats   <- parse_fstats(tex_path)
          sig_cols <- parse_sig_columns(tex_path)
          clean_f  <- !is.na(fstats) & is.finite(fstats) & fstats < F_SUSPICIOUS

          genuine_f10      <- any(clean_f & fstats > F_PASS)
          sig_with_clean_f <- any(sig_cols & clean_f)
          if (genuine_f10 || sig_with_clean_f) {
            appendix_specs <- c(appendix_specs, slug)
          }

          key <- paste(out$key, align, bl$key, wt$key, ex$key, sep = "|")
          all_data[[key]] <- list(
            outcome   = out,
            alignment = align,
            baseline  = bl,
            weight    = wt,
            exposure  = ex,
            fstats    = fstats,
            slug      = slug,
            sig_cols  = sig_cols
          )
        }
      }
    }
  }
}

cat(sprintf("  Parsed %d table combinations\n", length(all_data)))
cat(sprintf("  %d specs qualify for appendix\n", length(appendix_specs)))

# --- Build Beamer output ------------------------------------------------------

cat("Building Beamer file...\n")

L   <- character(0)
add <- function(...) L <<- c(L, paste0(...))

# ---- Preamble ----------------------------------------------------------------

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
add("% Table directory")
add("\\newcommand{\\tabledir}{../tables/firm}")
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
add("\\title{Firm-Level First-Stage Results}")
add(sprintf("\\subtitle{Script 51b --- %s}", format(Sys.Date(), "%B %d, %Y")))
add("\\author{}")
add("\\date{}")
add("")
add("\\begin{document}")
add("")
add("\\begin{frame}")
add("\\titlepage")
add("\\end{frame}")

# ---- Format helpers ----------------------------------------------------------

fmt_f <- function(f) {
  if (is.na(f)) return("NA")
  if (f >= F_PASS) return(sprintf("\\fpass{%.1f}", f))
  sprintf("%.1f", f)
}

align_label <- function(a) switch(a, coalition = "Coalition", party = "Party")

wt_abbr <- function(wkey) {
  switch(wkey,
    emp_weighted       = "Ew",
    emp_share_weighted = "Esw",
    unweighted         = "Uw",
    wkey
  )
}

bl_abbr <- function(bkey) {
  switch(bkey,
    `2002_fixed`    = "2002fx",
    cycle_specific  = "Cyc",
    bkey
  )
}

ex_abbr <- function(ekey) {
  switch(ekey,
    binary       = "Bin",
    pooled_count = "Pool",
    ekey
  )
}

# ---- SECTION 1: F-STAT SUMMARY GRIDS (8 slides: 4 outcomes × 2 baselines) ---

add("")
add("% ===========================================================================")
add("% F-STAT SUMMARY GRIDS")
add("% ===========================================================================")

for (out in OUTCOMES) {
  for (bl in BASELINES) {

    # Determine footer rf note
    rf_note <- if (out$is_rf) {
      " \\textcolor{alertred}{Reduced form, not first stage.}"
    } else {
      ""
    }

    # Check if any cell has F >= F_PASS across this outcome × baseline slice
    any_pass <- FALSE
    for (align in ALIGNMENTS) {
      for (wt in WEIGHTS) {
        for (ex in EXPOSURES) {
          key  <- paste(out$key, align, bl$key, wt$key, ex$key, sep = "|")
          dat  <- all_data[[key]]
          fv   <- if (!is.null(dat)) dat$fstats else rep(NA_real_, 6)
          if (any(!is.na(fv) & fv >= F_PASS)) any_pass <- TRUE
        }
      }
    }

    add("")
    add(sprintf("\\begin{frame}[t]{%s}", out$label))
    add(sprintf("\\framesubtitle{%s}", bl$label))
    add("\\begin{center}")
    add("\\footnotesize")
    add("\\setlength{\\tabcolsep}{3.5pt}")
    add("\\renewcommand{\\arraystretch}{1.05}")
    add("\\begin{tabular}{@{}llrccccccc@{}}")
    add("\\toprule")
    add(" & & & \\multicolumn{6}{c}{Instrument combo} \\\\")
    add("\\cmidrule(l{2pt}r{2pt}){4-9}")
    add("Alignment & Weighting & Exposure & M & G & P & M+G & M+P & M+G+P \\\\")
    add("\\midrule")

    N_ROWS_PER_ALIGN <- length(WEIGHTS) * length(EXPOSURES)   # 6

    first_align <- TRUE
    for (align in ALIGNMENTS) {
      if (!first_align) add("\\addlinespace[5pt]")
      first_align <- FALSE

      align_cell_done <- FALSE

      for (wi in seq_along(WEIGHTS)) {
        wt <- WEIGHTS[[wi]]
        wt_cell_done <- FALSE

        for (ei in seq_along(EXPOSURES)) {
          ex  <- EXPOSURES[[ei]]
          key <- paste(out$key, align, bl$key, wt$key, ex$key, sep = "|")
          dat <- all_data[[key]]
          fv  <- if (!is.null(dat)) dat$fstats else rep(NA_real_, 6)
          fstr <- paste(sapply(fv, fmt_f), collapse = " & ")

          # Alignment multirow cell (spans all weight × exposure rows)
          if (!align_cell_done) {
            align_cell <- sprintf("\\multirow{%d}{*}{%s}",
                                  N_ROWS_PER_ALIGN, align_label(align))
            align_cell_done <- TRUE
          } else {
            align_cell <- ""
          }

          # Weight multirow cell (spans all exposure rows for this weight)
          if (!wt_cell_done) {
            wt_cell <- sprintf("\\multirow{%d}{*}{%s}",
                               length(EXPOSURES), wt$label)
            wt_cell_done <- TRUE
          } else {
            wt_cell <- ""
          }

          add(sprintf("  %s & %s & %s & %s \\\\",
                      align_cell, wt_cell, ex$label, fstr))
        }
      }
    }

    add("\\bottomrule")
    add("\\end{tabular}")
    add("\\end{center}")

    # Footer note
    if (any_pass) {
      add(sprintf(
        "{\\scriptsize \\colorbox{pass}{\\textbf{Shaded}} = $F>10$.%s Firm + muni$\\times$year FE. SEs clustered by firm + municipality.}",
        rf_note
      ))
    } else {
      add(sprintf(
        "{\\scriptsize No spec reaches $F=10$.%s Firm + muni$\\times$year FE. SEs clustered by firm + municipality.}",
        rf_note
      ))
    }

    add("\\end{frame}")
  }
}

# ---- SECTION 2: APPENDIX QUALIFYING SPECS SUMMARY ---------------------------

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
  add(sprintf("\\textbf{Total qualifying specs:} %d\\\\[0.5em]", length(appendix_specs)))
  add("{\\scriptsize Criteria: include a table if at least one combo has genuine $F>10$ with $F<10{,}000$, or at least one coefficient with $p<0.05$ in a combo whose $F<10{,}000$.}")
  add("\\end{center}")
  add("\\end{frame}")
}

# ---- SECTION 3: APPENDIX — FULL TABLES --------------------------------------

add("")
add("% ===========================================================================")
add("% APPENDIX: FULL REGRESSION TABLES")
add("% ===========================================================================")

if (length(appendix_specs)) {
  add("")
  add("\\begin{frame}[plain]")
  add("\\begin{center}")
  add("{\\Large\\textbf{Appendix --- Full Firm-Level Tables}}")
  add("\\end{center}")
  add("\\end{frame}")

  for (slug in appendix_specs) {
    # Parse slug: firm__family__spec__outcome__alignment__baseline__wt__sample__exposure
    parts <- strsplit(slug, "__")[[1]]
    # parts[1]=firm parts[2]=family parts[3]=spec parts[4]=outcome
    # parts[5]=alignment parts[6]=baseline parts[7]=wt parts[8]=sample parts[9]=exposure
    outcome_lbl <- gsub("_", " ", parts[4])
    # Map raw outcome key to display label
    outcome_lbl <- switch(parts[4],
      bndes_extensive = "BNDES Extensive",
      bndes_intensive = "BNDES Intensive",
      employment_log  = "Employment Log",
      employment_share = "Employment Share",
      outcome_lbl
    )
    align_abbr <- if (parts[5] == "coalition") "Coal" else "Party"
    bl_abbr_v  <- bl_abbr(parts[6])
    wt_abbr_v  <- wt_abbr(parts[7])
    ex_abbr_v  <- ex_abbr(parts[9])

    title <- sprintf("[App] %s --- %s $\\cdot$ %s $\\cdot$ %s $\\cdot$ %s",
                     outcome_lbl, align_abbr, bl_abbr_v, wt_abbr_v, ex_abbr_v)

    add("")
    add(sprintf("\\begin{frame}[t,shrink=5]{%s}", title))
    add("\\begin{center}\\footnotesize")
    add(sprintf("\\input{\\tabledir/%s}", slug))
    add("\\end{center}")
    add("\\end{frame}")
  }
}

add("")
add("\\end{document}")

# --- Write output -------------------------------------------------------------

dir.create(dirname(OUTPUT_FILE), showWarnings = FALSE, recursive = TRUE)
writeLines(L, OUTPUT_FILE)
cat(sprintf("\nDone. Wrote %d lines to %s\n", length(L), OUTPUT_FILE))
cat(sprintf("  Grid slides:     %d\n", length(OUTCOMES) * length(BASELINES)))
cat(sprintf("  Appendix slides: %d\n", length(appendix_specs)))
