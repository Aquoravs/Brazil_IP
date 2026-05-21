#!/usr/bin/env Rscript
# ==============================================================================
# B6_three_volume_ar.R — the three-volume AR table.
#
# AR test run three ways, EC ALWAYS an included control:
#   (i)   no volume control : log_gdp ~ Z's + EC's              | muni + year
#   (ii)  Vol predetermined : log_gdp ~ Z's + EC's + vol_ratio  | muni + year
#   (iii) Vol instrumented  : feols(log_gdp ~ Z's + EC's | muni+year |
#                                   vol_ratio ~ Zbar_volchannel)
# Spec (iii) is dropped entirely if B4 finds no volume channel.
#
# Reported for TWO instrument sets (plan Decision 4):
#   (a) the data-selected composition set from B4 -- stacked, one AR regression;
#   (b) per-channel for the four mayor-crossed channels {M, M.P, M.G, M.G.P}.
# A channel never appears twice in the same table.
# AR statistic = cluster-robust joint Wald on the Z coefficients only.
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/ar_three_volume_compset_<tax>.{csv,tex}
#       output/ar_three_volume_mayor_<tax>.{csv,tex}
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})
setDTthreads(0L)
fixest::setFixest_nthreads(4L)
set.seed(20260520L)

source_helpers <- function() {
  a  <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (!length(fa)) stop("Run via Rscript.")
  this <- normalizePath(sub("^--file=", "", fa[[1L]]),
                        winslash = "/", mustWork = TRUE)
  source(file.path(dirname(this), "00_helpers.R"))
}
source_helpers()  # provides get_this_script(), parse_kv(), fmt_*, SIZE_CYCLES

THIS <- get_this_script()
BR   <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
OUT  <- file.path(BR, "output")

TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "policy_block_size_bin"))
message(sprintf("[INFO] %s | B6 three-volume AR | tax=%s", Sys.time(), TAX))

MAYOR_CHANNELS <- c("M", "MP", "MG", "MGP")

# --- Load panel + routing ----------------------------------------------------

panel <- qs_read(file.path(OUT, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(panel)
stopifnot(nrow(panel) > 0L)
SECTORS_ALL  <- attr(panel, "sectors_all")
SECTORS_KEEP <- attr(panel, "sectors_keep")
panel <- panel[is.finite(log_gdp) & is.finite(vol_ratio)]
stopifnot(nrow(panel) > 0L)
message(sprintf("[INFO] complete-case rows: %s",
                format(nrow(panel), big.mark = ",")))

route <- fread(file.path(OUT, sprintf("ar_routing_%s.csv", TAX)))
comp_set <- route[in_comp_set == TRUE, channel]
vol_set  <- route[in_vol_set  == TRUE, channel]
comp_set <- comp_set[order(match(comp_set, all_channels()))]
vol_set  <- vol_set[order(match(vol_set, all_channels()))]
message(sprintf("[INFO] composition set from B4: {%s}",
                paste(comp_set, collapse = ", ")))
message(sprintf("[INFO] volume set from B4: {%s}",
                if (length(vol_set)) paste(vol_set, collapse = ", ")
                else "(none)"))

# Build Zbar for the volume channels (muni-aggregated channel = sum_j Z).
for (ch in unique(c(vol_set, all_channels()))) {
  zc <- grep(paste0("^Z_", ch, "_"), names(panel), value = TRUE)
  if (length(zc))
    panel[, (paste0("Zbar_", ch)) := rowSums(.SD), .SDcols = zc]
}

z_cols  <- function(ch) paste0("Z_",  ch, "_", SECTORS_ALL)
ec_cols <- function(ch) paste0("EC_", ch, "_", SECTORS_KEEP)

vol_has_instrument <- length(vol_set) > 0L

# AR run for an instrument set under one volume treatment.
#   spec in {"novol", "volctrl", "volIV"}
run_ar <- function(channels, spec) {
  zc  <- unlist(lapply(channels, z_cols))
  ecc <- unlist(lapply(channels, ec_cols))
  key <- paste0("^(", paste0("Z_", channels, "_", collapse = "|"), ")")
  if (spec == "novol") {
    fml <- as.formula(sprintf("log_gdp ~ %s | muni_id + year",
                              paste(c(zc, ecc), collapse = " + ")))
  } else if (spec == "volctrl") {
    fml <- as.formula(sprintf("log_gdp ~ %s | muni_id + year",
                              paste(c(zc, ecc, "vol_ratio"), collapse = " + ")))
  } else {            # volIV: instrument vol_ratio by the volume channel Zbar
    zbar <- paste0("Zbar_", vol_set)
    fml <- as.formula(sprintf(
      "log_gdp ~ %s | muni_id + year | vol_ratio ~ %s",
      paste(c(zc, ecc), collapse = " + "),
      paste(zbar, collapse = " + ")))
  }
  mod <- tryCatch(
    feols(fml, data = panel, vcov = ~ muni_id, lean = FALSE),
    error = function(e) {
      message(sprintf("[WARN] AR fit failed [%s/%s]: %s",
                      paste(channels, collapse = ","), spec,
                      conditionMessage(e)))
      NULL
    })
  if (is.null(mod))
    return(list(ar_F = NA_real_, ar_p = NA_real_, df1 = NA_integer_,
                df2 = NA_integer_, K_Z = length(zc), n_obs = NA_integer_,
                vol_coef = NA_real_, vol_se = NA_real_, reject_5pc = FALSE))
  wd <- fixest::wald(mod, keep = key)
  ct <- coeftable(mod)
  vol_name <- if (spec == "volIV") "fit_vol_ratio" else "vol_ratio"
  vrow <- if (vol_name %in% rownames(ct)) ct[vol_name, ]
          else c(NA_real_, NA_real_, NA_real_, NA_real_)
  list(
    ar_F = as.numeric(wd$stat), ar_p = as.numeric(wd$p),
    df1  = as.integer(wd$df1),  df2  = as.integer(wd$df2),
    K_Z  = length(zc), n_obs = nobs(mod),
    vol_coef = unname(vrow[1L]), vol_se = unname(vrow[2L]),
    reject_5pc = isTRUE(as.numeric(wd$p) < 0.05))
}

SPECS <- c("novol", "volctrl")
if (vol_has_instrument) SPECS <- c(SPECS, "volIV")
spec_label <- c(novol = "No volume control",
                volctrl = "Volume control",
                volIV = "Volume instrumented")

# --- Set (a): data-selected composition set, stacked ------------------------

stopifnot(length(comp_set) > 0L)
rows_a <- list()
for (sp in SPECS) {
  r <- run_ar(comp_set, sp)
  rows_a[[sp]] <- data.table(
    instrument_set = paste0("compset {", paste(comp_set, collapse = ","), "}"),
    spec = sp, ar_F = r$ar_F, ar_p = r$ar_p, df1 = r$df1, df2 = r$df2,
    K_Z = r$K_Z, n_obs = r$n_obs, vol_coef = r$vol_coef, vol_se = r$vol_se,
    reject_5pc = r$reject_5pc)
}
res_a <- rbindlist(rows_a)
res_a[, taxonomy := TAX]
fwrite(res_a, file.path(OUT, sprintf("ar_three_volume_compset_%s.csv", TAX)))
message("\n[RESULT] B6 three-volume AR -- composition set (stacked):")
print(res_a[, .(spec, ar_F = round(ar_F, 3), ar_p = signif(ar_p, 3),
                df1, reject_5pc)])

# --- Set (b): per-channel, four mayor-crossed channels ----------------------

rows_b <- list()
for (ch in MAYOR_CHANNELS) for (sp in SPECS) {
  r <- run_ar(ch, sp)
  rows_b[[paste(ch, sp)]] <- data.table(
    channel = ch, channel_label = channel_label_plain(ch),
    spec = sp, ar_F = r$ar_F, ar_p = r$ar_p, df1 = r$df1, df2 = r$df2,
    K_Z = r$K_Z, n_obs = r$n_obs, vol_coef = r$vol_coef, vol_se = r$vol_se,
    reject_5pc = r$reject_5pc)
}
res_b <- rbindlist(rows_b)
res_b[, taxonomy := TAX]
fwrite(res_b, file.path(OUT, sprintf("ar_three_volume_mayor_%s.csv", TAX)))
message("\n[RESULT] B6 three-volume AR -- four mayor-crossed channels:")
print(dcast(res_b, channel_label ~ spec,
            value.var = "ar_F")[order(match(channel_label,
              vapply(MAYOR_CHANNELS, channel_label_plain, character(1))))])

# --- Bare-tabular .tex (INV-13) ---------------------------------------------
# fmt_F() / fmt_p() / stars() come from 00_helpers.R.

# Set (a) table: rows = {AR F, p-value, reject, df, N}, cols = three specs.
build_compset_tex <- function(rd) {
  ncol_spec <- nrow(rd)
  colspec <- paste0("@{}l", paste(rep("c", ncol_spec), collapse = ""), "@{}")
  hdr <- paste0("& ",
                paste(spec_label[rd$spec], collapse = " & "), " \\\\")
  c(
    sprintf("\\begin{tabular}{%s}", colspec),
    "\\toprule", hdr, "\\midrule",
    paste0("AR joint $F$ & ",
           paste(vapply(seq_len(nrow(rd)), function(i)
             paste0(fmt_F(rd$ar_F[i]), stars(rd$ar_p[i])),
             character(1)), collapse = " & "), " \\\\"),
    paste0("$p$-value & ",
           paste(vapply(rd$ar_p, fmt_p, character(1)),
                 collapse = " & "), " \\\\"),
    paste0("Reject (5\\%) & ",
           paste(ifelse(rd$reject_5pc, "Yes", "No"), collapse = " & "),
           " \\\\"),
    "\\midrule",
    paste0("Instruments ($K_Z$) & ",
           paste(rd$K_Z, collapse = " & "), " \\\\"),
    paste0("Numerator d.f. & ",
           paste(rd$df1, collapse = " & "), " \\\\"),
    paste0("Observations & ",
           paste(format(rd$n_obs, big.mark = ","), collapse = " & "),
           " \\\\"),
    "\\bottomrule", "\\end{tabular}")
}
writeLines(build_compset_tex(res_a),
           file.path(OUT, sprintf("ar_three_volume_compset_%s.tex", TAX)))

# Set (b) table: rows = four channels, cols = three specs (AR F [p]).
build_mayor_tex <- function(rd) {
  specs <- unique(rd$spec)
  ncol_spec <- length(specs)
  colspec <- paste0("@{}l", paste(rep("c", ncol_spec), collapse = ""), "@{}")
  hdr <- paste0("Channel & ",
                paste(spec_label[specs], collapse = " & "), " \\\\")
  lines <- c(sprintf("\\begin{tabular}{%s}", colspec),
             "\\toprule", hdr, "\\midrule")
  for (ch in MAYOR_CHANNELS) {
    cells <- character(ncol_spec)
    for (i in seq_along(specs)) {
      r <- rd[channel == ch & spec == specs[i]]
      cells[i] <- if (nrow(r) == 0L) "--" else
        sprintf("%s%s [%s]", fmt_F(r$ar_F), stars(r$ar_p), fmt_p(r$ar_p))
    }
    lines <- c(lines, paste0(channel_label(ch), " & ",
                             paste(cells, collapse = " & "), " \\\\"))
  }
  c(lines, "\\bottomrule", "\\end{tabular}")
}
writeLines(build_mayor_tex(res_b),
           file.path(OUT, sprintf("ar_three_volume_mayor_%s.tex", TAX)))

message(sprintf("[INFO] wrote ar_three_volume_{compset,mayor}_%s.{csv,tex}", TAX))
if (!vol_has_instrument)
  message("[INFO] no volume channel from B4 -- 'Volume instrumented' spec dropped")
message(sprintf("[INFO] %s | B6 done.", Sys.time()))
