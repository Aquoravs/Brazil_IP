#!/usr/bin/env Rscript
# ==============================================================================
# 06_verify.R — cross-check that F-statistics in ar_table_fstats_<tax>.tex
# match ar_summary_<tax>.csv to 3 decimals, for every cell.
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
OUT  <- file.path(BR, "output")

SPECS    <- c("none", "ec", "vol", "vol_ec")
CHANNELS <- c("M", "MP", "MG", "MGP")

verify_one <- function(tax) {
  csv  <- fread(file.path(OUT, sprintf("ar_summary_%s.csv", tax)))
  tex  <- readLines(file.path(OUT, sprintf("ar_table_fstats_%s.tex", tax)))
  # Parse data rows (skip \begin, \toprule, header, \midrule).
  data_lines <- tex[grepl("&", tex) & !grepl("^Channel", tex)]
  # Each line: "ChannelLabel & cell1 & cell2 & cell3 & cell4 \\"
  parse_cell <- function(cell) {
    # cell like "3.986$^{***}$ [0.008]"
    F_part <- sub("\\$.*$", "", cell)
    F_part <- sub("\\[.*$", "", F_part)
    F_part <- trimws(F_part)
    if (grepl("--", F_part)) return(NA_real_)
    as.numeric(F_part)
  }
  rows <- list()
  for (i in seq_along(data_lines)) {
    li <- data_lines[i]
    li <- sub("\\\\\\\\\\s*$", "", li)
    parts <- strsplit(li, "&", fixed = TRUE)[[1L]]
    parts <- trimws(parts)
    if (length(parts) < 5L) next
    ch_label <- parts[1L]
    ch <- CHANNELS[i]
    for (j in seq_along(SPECS)) {
      cell <- parts[1L + j]
      Ftex <- parse_cell(cell)
      sp <- SPECS[j]
      Fcsv <- csv[channel == ch & spec == sp, ar_F[1L]]
      rows[[length(rows) + 1L]] <- data.table(
        tax = tax, channel = ch, spec = sp,
        F_tex = Ftex, F_csv = Fcsv,
        diff = abs(round(Ftex, 3) - round(Fcsv, 3))
      )
    }
  }
  rbindlist(rows)
}

ok <- TRUE
all_checks <- rbindlist(lapply(c("policy_block", "size_bin"), verify_one))
n_match  <- sum(all_checks$diff < 1e-6)
n_mismatch <- sum(all_checks$diff >= 1e-6 & !is.na(all_checks$diff))
cat(sprintf("[VERIFY] %d cells checked: %d match, %d mismatch\n",
            nrow(all_checks), n_match, n_mismatch))
if (n_mismatch > 0L) {
  cat("[VERIFY] mismatches:\n")
  print(all_checks[diff >= 1e-6])
  ok <- FALSE
}
if (n_match == nrow(all_checks)) {
  cat("[VERIFY] PASS — every F in the tex matches the CSV to 3 decimals.\n")
}
print(all_checks)
if (!ok) quit(status = 1L)
