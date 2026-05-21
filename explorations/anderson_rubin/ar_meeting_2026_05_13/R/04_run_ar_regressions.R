#!/usr/bin/env Rscript
# ==============================================================================
# 04_run_ar_regressions.R — 4 channels × 4 control specs = 16 regressions per
# taxonomy. AR statistic = cluster-robust joint Wald F on the Z's.
#
# Specs:
#   (1) none     : log_gdp ~ Z's                     | muni_id + year
#   (2) ec       : log_gdp ~ Z's + EC's              | muni_id + year
#   (3) vol      : log_gdp ~ Z's + vol_ratio         | muni_id + year
#   (4) vol_ec   : log_gdp ~ Z's + EC's + vol_ratio  | muni_id + year
#
# CLI:  --tax={policy_block, size_bin}
# Out:  output/ar_summary_<tax>.csv     (16 rows × {channel, spec, ...})
#       output/ar_table_fstats_<tax>.tex (bare tabular, channels × specs)
#       output/ar_table_coefs_<tax>_pair1.tex  (M, M·P)
#       output/ar_table_coefs_<tax>_pair2.tex  (M·G, M·G·P)
#       output/ar_full_results_<tax>.qs2 (raw coef tables for slide 2)
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})
setDTthreads(0L)
fixest::setFixest_nthreads(4L)
set.seed(20260513L)

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
DATA <- file.path(ROOT, "data", "processed")
OUT  <- file.path(BR, "output")
source(file.path(BR, "R", "00_helpers.R"))

cli <- commandArgs(trailingOnly = TRUE)
parse_kv <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), cli, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", flag, "="), "", hit[[1L]])
}
TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "size_bin"))
message(sprintf("[INFO] %s | tax=%s", Sys.time(), TAX))

panel <- qs_read(file.path(OUT, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(panel)
HOLDOUT      <- attr(panel, "holdout_sector")
SECTORS_KEEP <- attr(panel, "sectors_keep")
message(sprintf("[INFO] panel rows: %s; hold-out: %s; sectors: %s",
                format(nrow(panel), big.mark = ","), HOLDOUT,
                paste(SECTORS_KEEP, collapse = ", ")))

# Drop muni-years with missing log_gdp or vol_ratio (so the same sample
# applies across the 4 specs within a channel — vol_ratio missing ≡ muni
# with no 2002 GDP).
panel <- panel[is.finite(log_gdp) & is.finite(vol_ratio)]
message(sprintf("[INFO] complete-case rows: %s",
                format(nrow(panel), big.mark = ",")))

CHANNELS <- c("M", "MP", "MG", "MGP")
SPECS    <- c("none", "ec", "vol", "vol_ec")

z_cols  <- function(channel) paste0("Z_",  channel, "_", SECTORS_KEEP)
ec_cols <- function(channel) paste0("EC_", channel, "_", SECTORS_KEEP)

run_one <- function(channel, spec) {
  zcs <- z_cols(channel)
  rhs <- zcs
  if (spec %in% c("ec",  "vol_ec")) rhs <- c(rhs, ec_cols(channel))
  if (spec %in% c("vol", "vol_ec")) rhs <- c(rhs, "vol_ratio")
  fml <- as.formula(paste0("log_gdp ~ ",
                           paste(rhs, collapse = " + "),
                           " | muni_id + year"))
  mod <- tryCatch(
    feols(fml, data = panel, vcov = ~ muni_id, lean = FALSE),
    error = function(e) {
      message(sprintf("[WARN] fit failed [%s/%s]: %s",
                      channel, spec, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(mod)) return(NULL)
  # AR joint Wald F on the Z's only.
  w <- tryCatch(fixest::wald(mod, keep = paste0("^Z_", channel, "_")),
                error = function(e) NULL)
  ar_F <- if (!is.null(w)) as.numeric(w$stat) else NA_real_
  ar_p <- if (!is.null(w)) as.numeric(w$p)    else NA_real_
  ct <- coeftable(mod)
  vol_row <- if ("vol_ratio" %in% rownames(ct)) ct["vol_ratio", ]
             else c(NA_real_, NA_real_, NA_real_, NA_real_)
  list(
    channel = channel, spec = spec,
    n_obs   = nobs(mod),
    n_munis = NA_integer_,  # set below from panel
    K_Z     = length(zcs),
    ar_F    = ar_F, ar_p = ar_p,
    vol_coef = unname(vol_row[1L]),
    vol_se   = unname(vol_row[2L]),
    ar_reject_5pc = isTRUE(ar_p < 0.05),
    coef_table = ct
  )
}

results <- list()
raw_models <- list()
for (channel in CHANNELS) for (spec in SPECS) {
  tag <- paste(channel, spec, sep = "/")
  message(sprintf("[INFO] running %s ...", tag))
  r <- run_one(channel, spec)
  if (is.null(r)) next
  raw_models[[tag]] <- r$coef_table
  r$coef_table <- NULL
  results[[length(results) + 1L]] <- as.data.table(r)
  message(sprintf("       AR_F=%.3f AR_p=%.4g vol=%s",
                  r$ar_F, r$ar_p,
                  if (is.finite(r$vol_coef))
                    formatC(r$vol_coef, format = "g", digits = 3)
                  else "--"))
}
summary_dt <- rbindlist(results, fill = TRUE)
# n_munis: recompute from panel directly (per channel/spec the sample is
# identical because we drop on log_gdp + vol_ratio up front).
n_munis_all <- uniqueN(panel$muni_id)
summary_dt[, n_munis := n_munis_all]

fwrite(summary_dt,
       file.path(OUT, sprintf("ar_summary_%s.csv", TAX)))
qs_save(raw_models,
        file.path(OUT, sprintf("ar_full_results_%s.qs2", TAX)))
message(sprintf("[INFO] wrote ar_summary_%s.csv (%d rows)", TAX, nrow(summary_dt)))
print(summary_dt[, .(channel, spec, n_obs, n_munis, K_Z,
                     ar_F = round(ar_F, 3),
                     ar_p = round(ar_p, 4),
                     reject_5 = ar_reject_5pc)])

# ---- F-stat tex table: rows = channels, cols = specs ---------------------

stars <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.01) return("$^{***}$")
  if (p < 0.05) return("$^{**}$")
  if (p < 0.10) return("$^{*}$")
  ""
}
fmt_p <- function(p) {
  if (!is.finite(p)) return("--")
  if (p < 0.001) return("$<$0.001")
  formatC(p, format = "f", digits = 3)
}
fmt_F <- function(F) {
  if (!is.finite(F)) return("--")
  formatC(F, format = "f", digits = 3)
}

spec_labels <- c(none = "No controls", ec = "+ EC",
                 vol = "+ Vol", vol_ec = "+ Vol + EC")
channel_labels <- c(M = "Mayor", MP = "M $\\cdot$ P",
                    MG = "M $\\cdot$ G", MGP = "M $\\cdot$ G $\\cdot$ P")

# Human-readable sector row labels — no raw sector codes in the deck.
pb_labels   <- c(Agro = "Agriculture", Ind = "Industry",
                 Infra = "Infrastructure", Serv = "Services")
size_labels <- c(`1` = "Small", `2` = "Medium", `3` = "Big")

build_fstat_tex <- function() {
  lines <- c(
    "\\begin{tabular}{@{}lcccc@{}}",
    "\\toprule",
    paste0("Channel & ",
           paste(spec_labels[SPECS], collapse = " & "),
           " \\\\"),
    "\\midrule"
  )
  for (ch in CHANNELS) {
    cells <- character(length(SPECS))
    for (i in seq_along(SPECS)) {
      sp <- SPECS[[i]]
      r <- summary_dt[channel == ch & spec == sp]
      if (nrow(r) == 0L) { cells[i] <- "--"; next }
      cells[i] <- sprintf("%s%s [%s]",
                           fmt_F(r$ar_F),
                           stars(r$ar_p),
                           fmt_p(r$ar_p))
    }
    lines <- c(lines,
               paste0(channel_labels[ch], " & ",
                      paste(cells, collapse = " & "),
                      " \\\\"))
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}")
  lines
}

writeLines(build_fstat_tex(),
           file.path(OUT, sprintf("ar_table_fstats_%s.tex", TAX)))
message(sprintf("[INFO] wrote ar_table_fstats_%s.tex", TAX))

# ---- Coefficient tables (per channel pair) -------------------------------
# Layout: rows = (Sector 1 ... Sector K-1, Volume, EC summary).
# EC summary = mean coef across J-1 EC controls (slide-density compromise).

build_coef_panel <- function(channel) {
  rows_sec <- SECTORS_KEEP
  lines <- c(
    "\\begin{tabular}{@{}lcccc@{}}",
    "\\toprule",
    paste0("& ", paste(spec_labels[SPECS], collapse = " & "), " \\\\"),
    "\\midrule"
  )
  fmt_co <- function(x, p) {
    if (!is.finite(x)) return("--")
    sprintf("%s%s", formatC(x, format = "f", digits = 3), stars(p))
  }
  fmt_se <- function(x) {
    if (!is.finite(x)) return("--")
    sprintf("(%s)", formatC(x, format = "f", digits = 3))
  }
  # Sector Z rows
  for (sec in rows_sec) {
    row_est <- character(length(SPECS))
    row_se  <- character(length(SPECS))
    for (i in seq_along(SPECS)) {
      sp <- SPECS[[i]]
      tag <- paste(channel, sp, sep = "/")
      ct  <- raw_models[[tag]]
      key <- paste0("Z_", channel, "_", sec)
      if (!is.null(ct) && key %in% rownames(ct)) {
        est <- ct[key, "Estimate"]
        se  <- ct[key, "Std. Error"]
        pv  <- ct[key, ncol(ct)]
        row_est[i] <- fmt_co(est, pv)
        row_se[i]  <- fmt_se(se)
      } else {
        row_est[i] <- "--"; row_se[i] <- ""
      }
    }
    label <- if (identical(TAX, "policy_block")) pb_labels[[as.character(sec)]]
             else size_labels[[as.character(sec)]]
    lines <- c(lines,
               paste0(label, " & ", paste(row_est, collapse = " & "), " \\\\"),
               paste0("       & ", paste(row_se,  collapse = " & "), " \\\\"))
  }
  # Volume row
  row_est <- character(length(SPECS))
  row_se  <- character(length(SPECS))
  for (i in seq_along(SPECS)) {
    sp <- SPECS[[i]]
    tag <- paste(channel, sp, sep = "/")
    ct  <- raw_models[[tag]]
    if (!is.null(ct) && "vol_ratio" %in% rownames(ct)) {
      est <- ct["vol_ratio", "Estimate"]
      se  <- ct["vol_ratio", "Std. Error"]
      pv  <- ct["vol_ratio", ncol(ct)]
      row_est[i] <- fmt_co(est, pv)
      row_se[i]  <- fmt_se(se)
    } else {
      row_est[i] <- "--"; row_se[i] <- ""
    }
  }
  lines <- c(lines,
             "\\midrule",
             paste0("Volume & ", paste(row_est, collapse = " & "), " \\\\"),
             paste0("       & ", paste(row_se,  collapse = " & "), " \\\\"))
  # EC summary row (mean coef across J-1 EC's for specs that include them)
  row_est <- character(length(SPECS))
  for (i in seq_along(SPECS)) {
    sp <- SPECS[[i]]
    tag <- paste(channel, sp, sep = "/")
    ct  <- raw_models[[tag]]
    if (is.null(ct)) { row_est[i] <- "--"; next }
    keys <- paste0("EC_", channel, "_", SECTORS_KEEP)
    found <- intersect(keys, rownames(ct))
    if (length(found) == 0L) { row_est[i] <- "--"; next }
    est_vec <- ct[found, "Estimate"]
    row_est[i] <- formatC(mean(est_vec), format = "f", digits = 3)
  }
  lines <- c(lines,
             paste0("EC (mean) & ", paste(row_est, collapse = " & "), " \\\\"))
  # Close the table. Sample size (observations, municipalities) is identical
  # across every channel/spec/taxonomy, so it is reported once on the
  # Overview slide rather than repeated in each coefficient table.
  lines <- c(lines, "\\bottomrule", "\\end{tabular}")
  lines
}

build_coef_single <- function(ch) {
  c(
    "\\centering",
    "\\resizebox{0.78\\textwidth}{!}{%",
    "\\setlength{\\tabcolsep}{4pt}%",
    "\\scriptsize",
    build_coef_panel(ch),
    "}"
  )
}

for (ch in CHANNELS) {
  writeLines(build_coef_single(ch),
             file.path(OUT, sprintf("ar_table_coefs_%s_%s.tex", TAX, ch)))
}
message(sprintf("[INFO] wrote ar_table_coefs_%s_{M,MP,MG,MGP}.tex", TAX))

# Keep pair files for backward compatibility (now thin wrappers).
writeLines(c(build_coef_single("M"), "\\vskip 0.6em",
             build_coef_single("MP")),
           file.path(OUT, sprintf("ar_table_coefs_%s_pair1.tex", TAX)))
writeLines(c(build_coef_single("MG"), "\\vskip 0.6em",
             build_coef_single("MGP")),
           file.path(OUT, sprintf("ar_table_coefs_%s_pair2.tex", TAX)))

message(sprintf("[INFO] %s | done.", Sys.time()))
