#!/usr/bin/env Rscript
# ==============================================================================
# 05_build_slides.R — assemble Beamer body sections per taxonomy from the
# Stage C tex artifacts, then write the master slides.tex deck to
# journal/meetings/2026-05-14/.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

get_this_script <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (length(fa)) return(normalizePath(sub("^--file=", "", fa[[1L]]),
                                       winslash = "/", mustWork = TRUE))
  stop("Run via Rscript.")
}
THIS <- get_this_script()
BR   <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
ROOT <- normalizePath(file.path(BR, "..", "..", ".."), winslash = "/", mustWork = TRUE)
OUT  <- file.path(BR, "output")
DECK_DIR <- file.path(ROOT, "journal", "meetings", "2026-05-14")
if (!dir.exists(DECK_DIR))     dir.create(DECK_DIR, recursive = TRUE)
BUILD_DIR <- file.path(DECK_DIR, "build")
if (!dir.exists(BUILD_DIR))    dir.create(BUILD_DIR, recursive = TRUE)
TABLES_DIR <- file.path(DECK_DIR, "tables")
if (!dir.exists(TABLES_DIR))   dir.create(TABLES_DIR, recursive = TRUE)

source(file.path(BR, "R", "00_helpers.R"))

# --- Copy / adapt tex artifacts ----------------------------------------------

adapt_resizebox <- function(lines) {
  # Replace \resizebox{!}{!} with \resizebox{\textwidth}{!} (slide-friendly).
  gsub("\\\\resizebox\\{!\\}\\{!\\}",
       "\\\\resizebox{\\\\textwidth}{!}",
       lines, perl = FALSE)
}

copy_and_adapt <- function(src, dst) {
  ls <- readLines(src)
  ls <- adapt_resizebox(ls)
  writeLines(ls, dst)
}

for (tax in c("policy_block", "size_bin")) {
  src <- file.path(OUT, sprintf("ar_table_fstats_%s.tex", tax))
  dst <- file.path(TABLES_DIR, sprintf("ar_table_fstats_%s.tex", tax))
  copy_and_adapt(src, dst)
  for (ch in c("M", "MP", "MG", "MGP")) {
    src <- file.path(OUT, sprintf("ar_table_coefs_%s_%s.tex", tax, ch))
    dst <- file.path(TABLES_DIR, sprintf("ar_table_coefs_%s_%s.tex", tax, ch))
    copy_and_adapt(src, dst)
  }
}
message("[INFO] copied & adapted tex artifacts to ", TABLES_DIR)

# --- Slides body per taxonomy -----------------------------------------------

tax_display <- function(tax) {
  if (identical(tax, "policy_block")) return("Policy Block")
  if (identical(tax, "size_bin"))     return("Firm Size (S3)")
  tax
}

tax_K <- function(tax) {
  if (identical(tax, "policy_block")) return(4L)
  if (identical(tax, "size_bin"))     return(3L)
  NA_integer_
}

tax_holdout <- function(tax) {
  fn <- file.path(OUT, sprintf("holdout_%s.csv", tax))
  hh <- fread(fn)
  setorder(hh, -mean_share)
  hh$sector[1L]
}

tax_levels_for_display <- function(tax) {
  if (identical(tax, "policy_block"))
    return("Agriculture, Industry, Infrastructure, Services")
  if (identical(tax, "size_bin"))
    return("MPME, Media, Grande")
  ""
}

build_body_lines <- function(tax) {
  K       <- tax_K(tax)
  ho      <- tax_holdout(tax)
  display <- tax_display(tax)
  levels  <- tax_levels_for_display(tax)
  holdout_label <- if (identical(tax, "policy_block")) {
    c(Serv = "Services", Ind = "Industry", Agro = "Agriculture",
      Infra = "Infrastructure")[ho]
  } else {
    c(`1` = "MPME", `2` = "Media", `3` = "Grande")[as.character(ho)]
  }
  c(
    sprintf("\\begin{frame}{%s --- Setup}", display),
    "\\begin{itemize}\\setlength{\\itemsep}{0.4em}",
    sprintf("\\item \\textbf{Taxonomy:} %s. $K=%d$; hold-out sector: \\textbf{%s}.",
            display, K, holdout_label),
    sprintf("\\item \\textbf{Levels:} %s.", levels),
    "\\item Weights: Variant A (muni-relative aligned-owner share), pre-earliest-election window.",
    "\\item Volume control: $\\mathrm{vol}_{mt} = \\mathrm{total\\_bndes\\_real}_{mt} / \\mathrm{pib\\_real}_{m,2002}$.",
    "\\item FE: municipality + year. SE: one-way cluster on \\texttt{muni\\_id}.",
    "\\end{itemize}",
    "\\end{frame}",
    "",
    sprintf("\\begin{frame}{%s --- AR joint $F$}", display),
    "{\\footnotesize Variant A weights, pre-earliest-election window.}",
    "\\vskip 0.25em",
    "\\resizebox{\\textwidth}{!}{%",
    "\\setlength{\\tabcolsep}{4pt}%",
    "\\footnotesize%",
    sprintf("\\input{tables/ar_table_fstats_%s.tex}%%", tax),
    "}",
    "\\vskip 0.5em",
    "{\\footnotesize Cluster-robust AR Wald joint $F$. ",
    "$^{*}$ $p<0.10$, $^{**}$ $p<0.05$, $^{***}$ $p<0.01$. ",
    "[$p$] is the $p$-value; reject at 5\\% iff $p<0.05$.}",
    "\\end{frame}",
    "",
    sprintf("\\begin{frame}{%s --- Coefficients: Mayor}", display),
    sprintf("\\input{tables/ar_table_coefs_%s_M.tex}", tax),
    "\\vskip 0.25em",
    "{\\footnotesize SE in parentheses. EC (mean) row reports the mean coefficient across the $K-1$ EC controls. Stars: $^{*}$ $p<0.10$, $^{**}$ $p<0.05$, $^{***}$ $p<0.01$.}",
    "\\end{frame}",
    "",
    sprintf("\\begin{frame}{%s --- Coefficients: Mayor $\\cdot$ President}", display),
    sprintf("\\input{tables/ar_table_coefs_%s_MP.tex}", tax),
    "\\vskip 0.25em",
    "{\\footnotesize SE in parentheses. EC (mean) row reports the mean coefficient across the $K-1$ EC controls.}",
    "\\end{frame}",
    "",
    sprintf("\\begin{frame}{%s --- Coefficients: Mayor $\\cdot$ Governor}", display),
    sprintf("\\input{tables/ar_table_coefs_%s_MG.tex}", tax),
    "\\vskip 0.25em",
    "{\\footnotesize SE in parentheses. EC (mean) row reports the mean coefficient across the $K-1$ EC controls.}",
    "\\end{frame}",
    "",
    sprintf("\\begin{frame}{%s --- Coefficients: Mayor $\\cdot$ Gov. $\\cdot$ President}", display),
    sprintf("\\input{tables/ar_table_coefs_%s_MGP.tex}", tax),
    "\\vskip 0.25em",
    "{\\footnotesize SE in parentheses. EC (mean) row reports the mean coefficient across the $K-1$ EC controls.}",
    "\\end{frame}",
    ""
  )
}

for (tax in c("policy_block", "size_bin")) {
  body <- build_body_lines(tax)
  writeLines(body, file.path(DECK_DIR, sprintf("slides_body_%s.tex", tax)))
  message("[INFO] wrote slides_body_", tax, ".tex")
}

# --- Master deck ------------------------------------------------------------

deck <- c(
  "\\documentclass[aspectratio=169,11pt]{beamer}",
  "\\usetheme{default}",
  "\\setbeamertemplate{navigation symbols}{}",
  "\\setbeamertemplate{headline}{}",
  "\\setbeamertemplate{footline}{\\hfill{\\usebeamerfont{footline}\\insertframenumber}\\hspace{0.6em}\\vspace{0.4em}}",
  "\\setbeamerfont{frametitle}{size=\\large,series=\\bfseries}",
  "\\setbeamerfont{footline}{size=\\scriptsize}",
  "\\usepackage{palatino}",
  "\\usepackage[T1]{fontenc}",
  "\\usepackage{booktabs}",
  "\\usepackage{array}",
  "\\usepackage{microtype}",
  "\\usepackage{graphicx}",
  "\\usepackage{makecell}",
  "\\title{\\textbf{Updated AR Test Results}}",
  "\\date{}",
  "\\begin{document}",
  "",
  "\\begin{frame}",
  "\\titlepage",
  "\\end{frame}",
  "",
  "\\begin{frame}{Headline date}",
  "\\centering",
  "\\vfill",
  "{\\Large May 14, 2026}",
  "\\vfill",
  "\\end{frame}",
  "",
  "\\begin{frame}{Overview}",
  "\\begin{itemize}\\setlength{\\itemsep}{0.45em}",
  "\\item \\textbf{Question.} Under the updated instrument convention (Variant A muni-relative owner-share, pre-earliest-election window), does the Anderson-Rubin test reject $H_0\\!:\\!\\beta=0$ on sector employment shares?",
  "\\item \\textbf{Two taxonomies.} Policy block (Agriculture, Industry, Infrastructure, Services; $K=4$); firm-size (MPME, Media, Grande; $K=3$).",
  "\\item \\textbf{Four control specs.} (1) No controls; (2) $+$ EC (per-cell exposure control); (3) $+$ Vol (volume control); (4) $+$ Vol $+$ EC.",
  "\\item \\textbf{Four channels.} Mayor; Mayor $\\cdot$ President; Mayor $\\cdot$ Governor; Mayor $\\cdot$ Gov.\\ $\\cdot$ President.",
  "\\item All regressions use municipality and year FE; one-way cluster on \\texttt{muni\\_id}.",
  "\\end{itemize}",
  "\\end{frame}",
  "",
  "\\input{slides_body_policy_block.tex}",
  "\\input{slides_body_size_bin.tex}",
  "",
  "\\begin{frame}{Bottom Line}",
  "\\begin{itemize}\\setlength{\\itemsep}{0.45em}",
  "\\item Under Variant A weights with pre-earliest-election windows, the AR test \\textit{rejects} at 5\\% in two cells: (M $\\cdot$ G, $+$ EC) and (M $\\cdot$ G, $+$ Vol $+$ EC) for policy\\_block; (M $\\cdot$ P, no controls / $+$ Vol) and (M $\\cdot$ G, $+$ EC / $+$ Vol $+$ EC) for size\\_bin.",
  "\\item The volume control (single coefficient) shifts $F$ negligibly; the EC controls (per-cell, $K-1$ columns) move $F$ in both directions.",
  "\\item Size\\_bin power is constrained ($K-1=2$ instruments per channel).",
  "\\item Per-channel coefficients reported on the following slides for inspection.",
  "\\end{itemize}",
  "\\end{frame}",
  "",
  "\\end{document}",
  ""
)
writeLines(deck, file.path(DECK_DIR, "slides.tex"))
message("[INFO] wrote master deck: ", file.path(DECK_DIR, "slides.tex"))
message(sprintf("[INFO] %s | done.", Sys.time()))
