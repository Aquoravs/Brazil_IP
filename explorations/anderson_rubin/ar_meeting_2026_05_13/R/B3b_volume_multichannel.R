#!/usr/bin/env Rscript
# ==============================================================================
# B3b_volume_multichannel.R — multi-channel volume first stage.
#
# Extends B3 from a single saturated 7-channel fit to regressions that enter
# channels two at a time, and two channels plus their interaction, for the
# three natural pairs:
#   (M, G): {M, G}  and  {M, G, M.G}
#   (M, P): {M, P}  and  {M, P, M.P}
#   (G, P): {G, P}  and  {G, P, G.P}
# Six channel combinations per margin. There is NO volume on/off split here:
# vol_ratio is the dependent variable, so it cannot also be a control.
#
# Spec is B3's: endogenous = Vol_mt (vol_ratio); scalar form, one regressor per
# channel, Zbar_c = sum_j Z^c_jmt;
#   FE   = muni + year
#   vcov = cluster by muni.
# As in B3 there is no EC term — the muni-aggregated EC sums to one over sectors
# and is absorbed by the fixed effects.
# Reports the cluster-robust partial Wald F and p for every channel in the fit.
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/ar_first_stage_vol_multi_<tax>.{tex,csv}
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})
setDTthreads(0L)
fixest::setFixest_nthreads(4L)
set.seed(20260521L)

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
message(sprintf("[INFO] %s | B3b volume multi-channel first stage | tax=%s",
                Sys.time(), TAX))

CHANNELS <- all_channels()

COMBOS <- list(
  list(panel = "Mayor and Governor",   pair = "MG",
       set_lab = "\\{M, G\\}",                    channels = c("M", "G")),
  list(panel = "Mayor and Governor",   pair = "MG",
       set_lab = "\\{M, G, M$\\cdot$G\\}",        channels = c("M", "G", "MG")),
  list(panel = "Mayor and President",  pair = "MP",
       set_lab = "\\{M, P\\}",                    channels = c("M", "P")),
  list(panel = "Mayor and President",  pair = "MP",
       set_lab = "\\{M, P, M$\\cdot$P\\}",        channels = c("M", "P", "MP")),
  list(panel = "Governor and President", pair = "GP",
       set_lab = "\\{G, P\\}",                    channels = c("G", "P")),
  list(panel = "Governor and President", pair = "GP",
       set_lab = "\\{G, P, G$\\cdot$P\\}",        channels = c("G", "P", "GP")))

PANEL_CHANS <- list(MG = c("M", "G", "MG"),
                    MP = c("M", "P", "MP"),
                    GP = c("G", "P", "GP"))

# --- Load panel, build Zbar_c = sum_j Z^c_jmt --------------------------------

panel <- qs_read(file.path(OUT, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(panel)
panel <- panel[is.finite(log_gdp) & is.finite(vol_ratio)]
stopifnot(nrow(panel) > 0L)
message(sprintf("[INFO] complete-case rows: %s",
                format(nrow(panel), big.mark = ",")))

for (ch in CHANNELS) {
  zc <- grep(paste0("^Z_", ch, "_"), names(panel), value = TRUE)
  panel[, (paste0("Zbar_", ch)) := rowSums(.SD), .SDcols = zc]
}

# --- One fit: channel combination --------------------------------------------
# Reports per-channel partial Wald F/p AND the joint Wald F/p over all channels
# in the set --- the joint statistic is the relevance object that gates the
# AR-test set choice; per-channel F is the collinearity diagnostic.

run_combo <- function(channels) {
  zbar <- paste0("Zbar_", channels)
  fml <- as.formula(sprintf("vol_ratio ~ %s | muni_id + year",
                            paste(zbar, collapse = " + ")))
  mod <- tryCatch(
    feols(fml, data = panel, vcov = ~ muni_id, lean = FALSE),
    error = function(e) {
      message(sprintf("[WARN] fit failed [%s]: %s",
                      paste(channels, collapse = ","), conditionMessage(e)))
      NULL
    })
  if (is.null(mod)) {
    return(data.table(channel = channels, F_partial = NA_real_,
                      p_partial = NA_real_, n_obs = NA_integer_,
                      joint_F = NA_real_, joint_p = NA_real_,
                      joint_reliable = FALSE))
  }
  out <- vector("list", length(channels))
  for (i in seq_along(channels)) {
    zt <- zbar[[i]]
    wd <- tryCatch(fixest::wald(mod, keep = paste0("^", zt, "$")),
                   error = function(e) NULL)
    out[[i]] <- data.table(
      channel   = channels[[i]],
      F_partial = if (!is.null(wd)) as.numeric(wd$stat) else NA_real_,
      p_partial = if (!is.null(wd)) as.numeric(wd$p)    else NA_real_,
      n_obs     = nobs(mod))
  }
  per <- rbindlist(out)
  # Joint Wald over all channels in the set. Under orthogonal instruments the
  # joint F equals the mean of the per-channel F's and cannot exceed the
  # largest; a joint F above that bound signals collinear channels and an
  # inflated (at the extreme, rank-deficient) joint Wald. joint_reliable flags
  # whether the joint statistic respects the bound.
  zkeep <- paste0("^(", paste(zbar, collapse = "|"), ")$")
  wj <- tryCatch(fixest::wald(mod, keep = zkeep), error = function(e) NULL)
  jF <- if (!is.null(wj)) as.numeric(wj$stat) else NA_real_
  jp <- if (!is.null(wj)) as.numeric(wj$p)    else NA_real_
  if (joint_F_rank_deficient(jF)) { jF <- NA_real_; jp <- NA_real_ }
  maxF <- suppressWarnings(max(per$F_partial, na.rm = TRUE))
  reliable <- is.finite(jF) && is.finite(maxF) && jF <= maxF
  per[, `:=`(joint_F = jF, joint_p = jp, joint_reliable = reliable)]
  per
}

# --- Run all six fits --------------------------------------------------------

rows <- list()
for (k in seq_along(COMBOS)) {
  cb <- COMBOS[[k]]
  r  <- run_combo(cb$channels)
  r[, `:=`(combo_id = k, pair = cb$pair, set_lab = cb$set_lab,
           panel = cb$panel)]
  rows[[k]] <- r
}
res <- rbindlist(rows)
res[, channel_label := vapply(channel, channel_label_plain, character(1))]
res[, relevant_5pc  := is.finite(p_partial) & p_partial < 0.05]
res[, taxonomy := TAX]
setcolorder(res, c("taxonomy", "combo_id", "pair", "set_lab", "channel",
                   "channel_label", "F_partial", "p_partial",
                   "joint_F", "joint_p", "joint_reliable", "relevant_5pc",
                   "n_obs"))

message("\n[RESULT] B3b multi-channel volume first stage:")
print(res[, .(pair, set_lab = gsub("\\\\|\\$|cdot|\\{|\\}", "", set_lab),
              channel_label, F = round(F_partial, 2),
              p = round(p_partial, 4), joint_F = round(joint_F, 2),
              joint_p = round(joint_p, 4), relevant_5pc)])

fwrite(res, file.path(OUT, sprintf("ar_first_stage_vol_multi_%s.csv", TAX)))

# --- Bare-tabular .tex (INV-13): 3 pair panels, 2 rows each ------------------
# 9 cols: set label | F,p x 3 channels | joint F,p. Pair-only rows leave the
# interaction channel's F/p blank.

cell_F <- function(F, p) {
  if (!is.finite(F)) return("")
  paste0(fmt_n(F, 2L), stars(p))
}
cell_p <- function(p) if (!is.finite(p)) "" else fmt_p(p, 3L)

build_tex <- function(rd) {
  lines <- c("\\begin{tabular}{@{}lcccccccc@{}}", "\\toprule")
  pairs <- c("MG", "MP", "GP")
  panel_letter <- c(MG = "A", MP = "B", GP = "C")
  for (pr in pairs) {
    chans <- PANEL_CHANS[[pr]]
    pname <- rd[pair == pr, panel][1L]
    lines <- c(lines, sprintf(
      "\\multicolumn{9}{l}{\\textit{Panel %s: %s}} \\\\",
      panel_letter[[pr]], pname))
    lines <- c(lines, "\\cmidrule(lr){1-9}")
    lines <- c(lines, sprintf(
      "Instrument set & \\multicolumn{2}{c}{%s} & \\multicolumn{2}{c}{%s} & \\multicolumn{2}{c}{%s} & \\multicolumn{2}{c}{Joint} \\\\",
      channel_label(chans[1L]), channel_label(chans[2L]),
      channel_label(chans[3L])))
    lines <- c(lines,
      "\\cmidrule(lr){2-3}\\cmidrule(lr){4-5}\\cmidrule(lr){6-7}\\cmidrule(lr){8-9}")
    lines <- c(lines, " & $F$ & $p$ & $F$ & $p$ & $F$ & $p$ & $F$ & $p$ \\\\")
    lines <- c(lines, "\\midrule")
    combo_ids <- sort(unique(rd[pair == pr, combo_id]))
    for (ci in combo_ids) {
      set_lab <- rd[combo_id == ci, set_lab][1L]
      sub <- rd[combo_id == ci]
      cells <- character(6)
      for (j in seq_along(chans)) {
        r <- sub[channel == chans[j]]
        if (nrow(r) == 0L) { cells[2*j-1] <- ""; cells[2*j] <- "" }
        else { cells[2*j-1] <- cell_F(r$F_partial, r$p_partial)
               cells[2*j]   <- cell_p(r$p_partial) }
      }
      jF <- sub$joint_F[1L]; jp <- sub$joint_p[1L]
      jcell <- if (isTRUE(sub$joint_reliable[1L]))
        paste0(cell_F(jF, jp), " & ", cell_p(jp))
      else "\\multicolumn{2}{c}{\\textit{collinear}}"
      lines <- c(lines, sprintf(
        "%s & %s & %s & %s & %s & %s & %s & %s \\\\",
        set_lab, cells[1], cells[2], cells[3], cells[4], cells[5], cells[6],
        jcell))
    }
    if (pr != "GP") lines <- c(lines, "\\midrule")
  }
  c(lines, "\\bottomrule", "\\end{tabular}")
}
writeLines(build_tex(res),
           file.path(OUT, sprintf("ar_first_stage_vol_multi_%s.tex", TAX)))
message(sprintf("[INFO] wrote ar_first_stage_vol_multi_%s.{tex,csv}", TAX))
message(sprintf("[INFO] %s | B3b done.", Sys.time()))
