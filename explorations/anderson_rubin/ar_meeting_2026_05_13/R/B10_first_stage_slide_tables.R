#!/usr/bin/env Rscript
# ==============================================================================
# B10_first_stage_slide_tables.R - sector-share first-stage tables for the
# meeting deck. Reads B8's wide_first_stage_<tax>.csv (volume-control rows) and
# re-presents ALL 18 evaluated stacks - the seven singletons plus the Mayor
# stacks, parent pairs, and parent-plus-interaction stacks - grouped by family.
# No model is re-fit.
#
#   policy_block          -> per-share table: each stack's SW F for every sector
#                            share, plus the KP rank statistic.
#   policy_block_size_bin -> per-stack verdict: KP, SW F range, identified
#                            shares (11 shares are too many for a per-share
#                            slide table).
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/first_stage_shares_<tax>.tex   (bare tabular, INV-13)
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

source_helpers <- function() {
  a  <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (!length(fa)) stop("Run via Rscript.")
  this <- normalizePath(sub("^--file=", "", fa[[1L]]),
                        winslash = "/", mustWork = TRUE)
  source(file.path(dirname(this), "00_helpers.R"))
}
source_helpers()  # provides get_this_script(), parse_kv(), fmt_*

THIS <- get_this_script()
BR   <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
OUT  <- file.path(BR, "output")

TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "policy_block_size_bin"))
message(sprintf("[INFO] %s | B10 first-stage slide tables | tax=%s",
                Sys.time(), TAX))

# Stack id order and family grouping, matching B8.
STACK_ORDER <- c("M", "G", "P", "MG", "MP", "GP", "MGP",
                 "M_MP", "M_MG", "M_MGP", "mayor_full",
                 "M_G", "M_P", "G_P",
                 "M_P_MP", "M_G_MG", "G_P_GP", "M_G_P_MGP")

wide_path <- file.path(OUT, sprintf("wide_first_stage_%s.csv", TAX))
if (!file.exists(wide_path)) stop("Missing B8 output: ", wide_path)
wide <- fread(wide_path)

fs <- wide[volume_control == TRUE]
fs[, ord := match(stack_id, STACK_ORDER)]
setorder(fs, ord)
stopifnot(nrow(fs) == length(STACK_ORDER), !anyNA(fs$ord))

# --- policy_block: per-share SW F table --------------------------------------
# Families (singletons, Mayor stacks, parent pairs, parent+interaction) are
# separated by \addlinespace; the stack notation in the row label is itself
# self-describing, so no group-header rows are needed.

build_per_share_tex <- function(d) {
  share_cols <- grep("^sw_F_", names(d), value = TRUE)
  sectors    <- sub("^sw_F_", "", share_cols)
  labs       <- taxonomy_labels("policy_block")
  headers    <- vapply(sectors, function(s)
    if (s %in% names(labs)) labs[[s]] else s, character(1))
  nshare     <- length(share_cols)
  colspec    <- paste0("@{}l", paste(rep("c", nshare + 1L), collapse = ""), "@{}")
  lines <- c(
    sprintf("\\begin{tabular}{%s}", colspec),
    "\\toprule",
    paste0("Stack & \\multicolumn{", nshare,
           "}{c}{SW $F$ per sector share} & KP \\\\"),
    sprintf("\\cmidrule(lr){2-%d}", nshare + 1L),
    paste0(" & ", paste(headers, collapse = " & "), " & \\\\"),
    "\\midrule")
  cur_group <- d$stack_group[[1L]]
  for (i in seq_len(nrow(d))) {
    r <- d[i]
    if (!identical(r$stack_group, cur_group)) {
      lines <- c(lines, "\\addlinespace")
      cur_group <- r$stack_group
    }
    cells <- vapply(share_cols, function(c) fmt_n(r[[c]], 2L), character(1))
    lines <- c(lines, paste0(
      r$tex_label, " & ", paste(cells, collapse = " & "), " & ",
      fmt_n(r$kp_rank_wald, 2L), " \\\\"))
  }
  c(lines, "\\bottomrule", "\\end{tabular}")
}

# --- policy_block_size_bin: per-stack verdict --------------------------------

build_verdict_tex <- function(d) {
  lines <- c(
    "\\begin{tabular}{@{}lcccc@{}}",
    "\\toprule",
    "Stack & KP & SW $F$ min & SW $F$ max & Identified shares \\\\",
    "\\midrule")
  cur_group <- d$stack_group[[1L]]
  for (i in seq_len(nrow(d))) {
    r <- d[i]
    if (!identical(r$stack_group, cur_group)) {
      lines <- c(lines, "\\addlinespace")
      cur_group <- r$stack_group
    }
    lines <- c(lines, sprintf(
      "%s & %s & %s & %s & %d/%d \\\\",
      r$tex_label,
      fmt_n(r$kp_rank_wald, 2L),
      fmt_n(r$sw_min, 2L),
      fmt_n(r$sw_max, 2L),
      r$identified_shares, r$n_endogenous))
  }
  c(lines, "\\bottomrule", "\\end{tabular}")
}

builder <- if (identical(TAX, "policy_block")) {
  build_per_share_tex
} else {
  build_verdict_tex
}

# Full table (record) plus a two-panel split for the slide: panel A is the
# singletons and Mayor stacks, panel B the parent pairs and parent+interaction
# stacks - two short tables sit side by side better than one 18-row table.
GROUP_A <- c("Singletons", "Mayor stacks")
GROUP_B <- c("Parent pairs", "Parent + interaction")
stopifnot(all(fs$stack_group %in% c(GROUP_A, GROUP_B)))

panels <- list(
  list(suffix = "",   d = fs),
  list(suffix = "_a", d = fs[stack_group %in% GROUP_A]),
  list(suffix = "_b", d = fs[stack_group %in% GROUP_B]))

for (p in panels) {
  tex_path <- file.path(OUT, sprintf("first_stage_shares_%s%s.tex",
                                     TAX, p$suffix))
  writeLines(builder(p$d), tex_path)
  message(sprintf("[INFO] wrote first_stage_shares_%s%s.tex (%d stacks)",
                  TAX, p$suffix, nrow(p$d)))
}
message(sprintf("[INFO] %s | B10 done.", Sys.time()))
