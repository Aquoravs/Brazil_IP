#!/usr/bin/env Rscript
# ==============================================================================
# B2b_composition_multichannel.R — multi-channel composition first stage.
#
# Extends B2 from a single saturated 7-channel fit to regressions that enter
# channels two at a time, and two channels plus their interaction, for the
# three natural pairs:
#   (M, G): {M, G}  and  {M, G, M.G}
#   (M, P): {M, P}  and  {M, P, M.P}
#   (G, P): {G, P}  and  {G, P, G.P}
# Each of the six channel combinations is run TWICE — without a volume control
# (matching B2) and with vol_ratio added as a predetermined control (matching
# the AR test's partial-IV treatment). 12 fits per margin.
#
# Spec is otherwise B2's: endogenous = sector employment share s_emp[j,m,t],
# stacked long at (muni, sector, year);
#   FE   = muni^sector + sector^year
#   ctrl = own-sector EC of the channels IN that regression (per-channel EC,
#          matched to the included instruments, as in B6's run_ar)
#   vcov = cluster by muni + sector.
# Reports the cluster-robust partial Wald F and p for every channel in the fit.
# Both specs run on the common sample (rows with finite vol_ratio) so the
# volume on/off comparison holds N fixed.
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/ar_first_stage_comp_multi_<tax>.{tex,csv}
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
ROOT <- normalizePath(file.path(BR, "..", "..", ".."), winslash = "/", mustWork = TRUE)
DATA <- file.path(ROOT, "data", "processed")
OUT  <- file.path(BR, "output")

TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "policy_block_size_bin"))
message(sprintf("[INFO] %s | B2b composition multi-channel first stage | tax=%s",
                Sys.time(), TAX))

CHANNELS <- all_channels()   # M G P MG MP GP MGP

# The three pairs, each with a pair-only and a pair+interaction combination.
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

# Channel triple shown as the third column of each pair panel.
PANEL_CHANS <- list(MG = c("M", "G", "MG"),
                    MP = c("M", "P", "MP"),
                    GP = c("G", "P", "GP"))

# --- Load Z and EC (long), wide-by-channel -----------------------------------

Z  <- qs_read(file.path(OUT, sprintf("Z_variant_a_%s.qs2",  TAX))); setDT(Z)
EC <- qs_read(file.path(OUT, sprintf("EC_variant_a_%s.qs2", TAX))); setDT(EC)

Zw <- dcast(Z,  muni_id + year + sector ~ channel, value.var = "Z_val")
setnames(Zw, CHANNELS, paste0("Z_", CHANNELS))
ECw <- dcast(EC, muni_id + year + sector ~ channel, value.var = "EC_val")
ec_chan <- intersect(CHANNELS, names(ECw))
setnames(ECw, ec_chan, paste0("EC_", ec_chan))
stopifnot(all(paste0("EC_", CHANNELS) %in% names(ECw)))

# --- Endogenous: employment share s_emp[j,m,t] -------------------------------

if (identical(TAX, "policy_block")) {
  emp <- qs_read(file.path(DATA, "emp_share_panel_policy_block.qs2")); setDT(emp)
  emp <- emp[policy_block != "XX",
             .(muni_id = as.integer(muni_id), year = as.integer(year),
               sector = as.character(policy_block), s_emp = s_emp_mjt)]
} else {
  # policy_block_size_bin: build crossed-margin shares from the firm panel,
  # mirroring B2_composition_first_stage.R.
  message("[INFO] computing policy_block_size_bin employment shares ...")
  fp <- qs_read(file.path(DATA, "firm_panel_for_regs.qs2")); setDT(fp)
  fp <- fp[, .(firm_id = as.integer(firm_id), muni_id = as.integer(muni_id),
               year = as.integer(year),
               cnae_section = as.character(cnae_section), n_employees)]
  fp <- fp[!is.na(cnae_section) & nzchar(cnae_section)]
  pbm <- qs_read(file.path(DATA, "policy_block_mapping.qs2")); setDT(pbm)
  pbm <- pbm[policy_block != "XX"]
  fp <- merge(fp, pbm[, .(cnae_section, policy_block)],
              by = "cnae_section", all.x = FALSE)
  fp[, cnae_section := NULL]
  sb <- qs_read(file.path(DATA, "size_bin_mapping.qs2")); setDT(sb)
  fp[, election_cycle := vapply(year, function(y) {
    cs <- SIZE_CYCLES[SIZE_CYCLES <= y]
    if (length(cs) == 0L) SIZE_CYCLES[1L] else max(cs)
  }, integer(1))]
  sb[, `:=`(election_cycle = as.integer(election_cycle),
            firm_id = as.integer(firm_id), size_bin = as.integer(size_bin))]
  fp <- merge(fp, sb[, .(firm_id, election_cycle, size_bin)],
              by = c("firm_id", "election_cycle"), all.x = FALSE)
  fp[, sector := paste0(policy_block, "_", size_bin)]
  njmt <- fp[!is.na(n_employees), .(n_jmt = sum(n_employees, na.rm = TRUE)),
             by = .(muni_id, year, sector)]
  nmt  <- njmt[, .(n_mt = sum(n_jmt, na.rm = TRUE)), by = .(muni_id, year)]
  njmt <- merge(njmt, nmt, by = c("muni_id", "year"))
  njmt[, s_emp := n_jmt / n_mt]
  emp <- njmt[, .(muni_id, year, sector, s_emp)]
  rm(fp, sb, pbm, njmt, nmt); gc(verbose = FALSE)
}

# --- vol_ratio (muni-year scalar) from the AR panel --------------------------

panel <- qs_read(file.path(OUT, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(panel)
vol <- unique(panel[, .(muni_id = as.integer(muni_id),
                        year = as.integer(year), vol_ratio)])

# --- Assemble stacked (muni, sector, year) analysis table --------------------

dt <- merge(emp, Zw,  by = c("muni_id", "year", "sector"), all.x = TRUE)
dt <- merge(dt, ECw, by = c("muni_id", "year", "sector"), all.x = TRUE)
zc <- grep("^Z_",  names(dt), value = TRUE)
ec <- grep("^EC_", names(dt), value = TRUE)
for (cc in c(zc, ec))
  set(dt, i = which(is.na(dt[[cc]])), j = cc, value = 0)
dt <- merge(dt, vol, by = c("muni_id", "year"), all.x = TRUE)
dt <- dt[is.finite(s_emp) & is.finite(vol_ratio)]   # common sample, both specs
dt[, muni_sector := paste0(muni_id, "_", sector)]
stopifnot(nrow(dt) > 0L)
message(sprintf("[INFO] analysis rows (finite s_emp & vol_ratio): %s",
                format(nrow(dt), big.mark = ",")))

# --- One fit: channel combination x volume treatment -------------------------
# EC entered only for the channels IN the regression (per-channel EC matched to
# the included instruments, consistent with B6's run_ar). Reports per-channel
# partial Wald F/p AND the joint Wald F/p over all channels in the set --- the
# joint statistic is the relevance object that gates the AR-test set choice;
# per-channel F is the collinearity diagnostic.

run_combo <- function(channels, vol_ctrl) {
  z_terms  <- paste0("Z_",  channels)
  ec_terms <- paste0("EC_", channels)
  rhs <- c(z_terms, ec_terms)
  if (vol_ctrl) rhs <- c(rhs, "vol_ratio")
  fml <- as.formula(sprintf("s_emp ~ %s | muni_sector + sector^year",
                            paste(rhs, collapse = " + ")))
  mod <- tryCatch(
    feols(fml, data = dt, vcov = ~ muni_id + sector, lean = FALSE),
    error = function(e) {
      message(sprintf("[WARN] fit failed [%s | vol=%s]: %s",
                      paste(channels, collapse = ","), vol_ctrl,
                      conditionMessage(e)))
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
    zt <- z_terms[[i]]
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
  zkeep <- paste0("^(", paste(z_terms, collapse = "|"), ")$")
  wj <- tryCatch(fixest::wald(mod, keep = zkeep), error = function(e) NULL)
  jF <- if (!is.null(wj)) as.numeric(wj$stat) else NA_real_
  jp <- if (!is.null(wj)) as.numeric(wj$p)    else NA_real_
  if (joint_F_rank_deficient(jF)) { jF <- NA_real_; jp <- NA_real_ }
  maxF <- suppressWarnings(max(per$F_partial, na.rm = TRUE))
  reliable <- is.finite(jF) && is.finite(maxF) && jF <= maxF
  per[, `:=`(joint_F = jF, joint_p = jp, joint_reliable = reliable)]
  per
}

# --- Run all 12 fits ---------------------------------------------------------

rows <- list()
for (k in seq_along(COMBOS)) {
  cb <- COMBOS[[k]]
  for (vc in c(FALSE, TRUE)) {
    r <- run_combo(cb$channels, vc)
    r[, `:=`(combo_id = k, pair = cb$pair, set_lab = cb$set_lab,
             panel = cb$panel, vol_control = vc)]
    rows[[length(rows) + 1L]] <- r
  }
}
res <- rbindlist(rows)
res[, channel_label := vapply(channel, channel_label_plain, character(1))]
res[, relevant_5pc  := is.finite(p_partial) & p_partial < 0.05]
res[, taxonomy := TAX]
setcolorder(res, c("taxonomy", "combo_id", "pair", "set_lab", "vol_control",
                   "channel", "channel_label", "F_partial", "p_partial",
                   "joint_F", "joint_p", "joint_reliable", "relevant_5pc",
                   "n_obs"))

message("\n[RESULT] B2b multi-channel composition first stage:")
print(res[, .(pair, set_lab = gsub("\\\\|\\$|cdot|\\{|\\}", "", set_lab),
              vol_control, channel_label,
              F = round(F_partial, 2), p = round(p_partial, 4),
              joint_F = round(joint_F, 2), joint_p = round(joint_p, 4),
              relevant_5pc)])

fwrite(res, file.path(OUT, sprintf("ar_first_stage_comp_multi_%s.csv", TAX)))

# --- Bare-tabular .tex (INV-13): 3 pair panels, 4 rows each ------------------
# 10 cols: set label | vol ctrl | F,p x 3 channels | joint F,p. Pair-only rows
# leave the interaction channel's F/p blank.

cell_F <- function(F, p) {
  if (!is.finite(F)) return("")
  paste0(fmt_n(F, 2L), stars(p))
}
cell_p <- function(p) if (!is.finite(p)) "" else fmt_p(p, 3L)

build_tex <- function(rd) {
  lines <- c("\\begin{tabular}{@{}llcccccccc@{}}", "\\toprule")
  pairs <- c("MG", "MP", "GP")
  panel_letter <- c(MG = "A", MP = "B", GP = "C")
  for (pr in pairs) {
    chans <- PANEL_CHANS[[pr]]
    pname <- rd[pair == pr, panel][1L]
    # Panel label row.
    lines <- c(lines, sprintf(
      "\\multicolumn{10}{l}{\\textit{Panel %s: %s}} \\\\",
      panel_letter[[pr]], pname))
    lines <- c(lines, "\\cmidrule(lr){1-10}")
    # Channel-name header (this panel's three channels) + joint.
    lines <- c(lines, sprintf(
      "Instrument set & Vol.\\ ctrl & \\multicolumn{2}{c}{%s} & \\multicolumn{2}{c}{%s} & \\multicolumn{2}{c}{%s} & \\multicolumn{2}{c}{Joint} \\\\",
      channel_label(chans[1L]), channel_label(chans[2L]),
      channel_label(chans[3L])))
    lines <- c(lines,
      "\\cmidrule(lr){3-4}\\cmidrule(lr){5-6}\\cmidrule(lr){7-8}\\cmidrule(lr){9-10}")
    lines <- c(lines, " & & $F$ & $p$ & $F$ & $p$ & $F$ & $p$ & $F$ & $p$ \\\\")
    lines <- c(lines, "\\midrule")
    combo_ids <- sort(unique(rd[pair == pr, combo_id]))
    for (ci in combo_ids) {
      set_lab <- rd[combo_id == ci, set_lab][1L]
      for (vc in c(FALSE, TRUE)) {
        sub <- rd[combo_id == ci & vol_control == vc]
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
          "%s & %s & %s & %s & %s & %s & %s & %s & %s \\\\",
          set_lab, if (vc) "Yes" else "No",
          cells[1], cells[2], cells[3], cells[4], cells[5], cells[6],
          jcell))
      }
    }
    if (pr != "GP") lines <- c(lines, "\\midrule")
  }
  c(lines, "\\bottomrule", "\\end{tabular}")
}
writeLines(build_tex(res),
           file.path(OUT, sprintf("ar_first_stage_comp_multi_%s.tex", TAX)))
message(sprintf("[INFO] wrote ar_first_stage_comp_multi_%s.{tex,csv}", TAX))
message(sprintf("[INFO] %s | B2b done.", Sys.time()))
