#!/usr/bin/env Rscript
# ==============================================================================
# B7_collinearity_diagnosis.R — Phase 1A: instrument-collinearity diagnosis.
#
# Diagnoses WHY the channel-instrument block is collinear and proposes WHICH
# channel stacks are inadmissible as joint instruments, BEFORE any wide-form
# first stage is run (Phase 1B). Runs on the muni-year AR panel
# (muni_panel_ar_<tax>.qs2) — the same object the AR test (B6) uses.
#
# Four diagnostic blocks (plan 2026-05-21, Phase 1A):
#   1A.1  Interaction-instrument construction audit. Tests, row by row on
#         alignment_shocks.qs2, whether the interaction coalition columns equal
#         the exact product of their single-office parents.
#   1A.2  Pairwise correlations, condition numbers, VIFs of each candidate
#         instrument block AFTER partialling out muni + year FE, the EC
#         controls, and vol_ratio — every non-instrument regressor in the AR
#         reduced form.
#   1A.3  Instrument-block rank diagnosis across candidate stacks. (The genuine
#         cluster-robust Kleibergen-Paap rank Wald statistic needs the
#         endogenous share vector and is a Phase 1B object; Phase 1A does not
#         build the shares. The operational Phase-1A content of "the KP rank
#         statistic cannot be computed / is degenerate" is the numerical rank
#         deficiency of the partialled instrument block, reported here.)
#   1A.4  Design attribution: split each key pairwise correlation into a
#         verticalizado component (2002 + 2006 cycles, years <= 2009) and a
#         post-verticalizacao component (2010 + 2014 cycles, years >= 2010).
#
# Partialling matches the AR reduced form (B6_three_volume_ar.R): muni + year
# FE, the EC block, and vol_ratio are removed; the diagnosis is on the
# residualised instruments only.
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/collinearity_diagnosis_<tax>.{csv,tex}
#       output/instrument_admissibility_<tax>.csv
#       output/interaction_construction_audit.csv      (taxonomy-independent)
#       output/design_attribution_<tax>.csv
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
source_helpers()  # provides get_this_script(), parse_kv(), fmt_*, channels

THIS <- get_this_script()
BR   <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
ROOT <- normalizePath(file.path(BR, "..", "..", ".."), winslash = "/", mustWork = TRUE)
DATA <- file.path(ROOT, "data", "processed")
OUT  <- file.path(BR, "output")

TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "policy_block_size_bin"))
message(sprintf("[INFO] %s | B7 collinearity diagnosis | tax=%s",
                Sys.time(), TAX))

CHANNELS <- all_channels()   # M G P MG MP GP MGP

# --- Numeric / LaTeX formatters (local to B7) --------------------------------
# Condition numbers and VIFs can be Inf or astronomically large under exact
# collinearity. fmt_big keeps the table legible.

CEIL_BIG <- 1e4

fmt_big <- function(x, d = 1L) {
  if (!is.finite(x))      return("$\\infty$")
  if (x >= CEIL_BIG)      return("$>$10{,}000")
  formatC(x, format = "f", digits = d, big.mark = ",")
}

# ==============================================================================
# Block 1A.1 — interaction-instrument construction audit
# ==============================================================================
# The single-office coalition indicators and their interaction columns live in
# alignment_shocks.qs2 at the (muni, party, year) level. 32_build_alignment_
# shocks.R builds the interaction columns as exact products; this block verifies
# that numerically. The GP channel has no pre-built column — 02_build_
# instruments_ec.R constructs it as align_gov_coalition * align_pres_coalition,
# so it is an exact product by construction.

audit_interactions <- function() {
  al <- qs_read(file.path(DATA, "alignment_shocks.qs2")); setDT(al)
  # Parent / interaction coalition columns.
  defs <- list(
    list(channel = "MG",  interaction = "align_mayor_gov_coalition",
         parents = c("align_mayor_coalition", "align_gov_coalition")),
    list(channel = "MP",  interaction = "align_mayor_pres_coalition",
         parents = c("align_mayor_coalition", "align_pres_coalition")),
    list(channel = "MGP", interaction = "align_triple_coalition",
         parents = c("align_mayor_coalition", "align_gov_coalition",
                     "align_pres_coalition")))
  rows <- vector("list", length(defs) + 1L)
  for (i in seq_along(defs)) {
    d <- defs[[i]]
    cols <- c(d$interaction, d$parents)
    stopifnot(all(cols %in% names(al)))
    prod_parents <- Reduce(`*`, lapply(d$parents, function(p) as.numeric(al[[p]])))
    obs <- as.numeric(al[[d$interaction]])
    eq  <- (obs == prod_parents)
    rows[[i]] <- data.table(
      channel        = d$channel,
      interaction_col = d$interaction,
      parents        = paste(d$parents, collapse = " * "),
      n_rows         = length(eq),
      n_equal        = sum(eq),
      share_equal    = mean(eq),
      exact_product  = all(eq),
      source         = "32_build_alignment_shocks.R")
  }
  # GP: no pre-built column; built downstream as a product.
  rows[[length(defs) + 1L]] <- data.table(
    channel        = "GP",
    interaction_col = "align_gov_pres_coalition",
    parents        = "align_gov_coalition * align_pres_coalition",
    n_rows         = nrow(al),
    n_equal        = nrow(al),
    share_equal    = 1.0,
    exact_product  = TRUE,
    source         = "02_build_instruments_ec.R (product by construction)")
  rbindlist(rows)
}

audit_dt <- audit_interactions()
message("\n[RESULT] 1A.1 interaction-construction audit:")
print(audit_dt[, .(channel, share_equal = round(share_equal, 6), exact_product)])
fwrite(audit_dt, file.path(OUT, "interaction_construction_audit.csv"))

# Channels whose interaction alignment is an exact product of its parents.
EXACT_PRODUCT_CHANNELS <- audit_dt[exact_product == TRUE, channel]

# ==============================================================================
# Load the muni-year AR panel
# ==============================================================================

panel <- qs_read(file.path(OUT, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(panel)
SECTORS_ALL  <- attr(panel, "sectors_all")
SECTORS_KEEP <- attr(panel, "sectors_keep")
panel <- panel[is.finite(log_gdp) & is.finite(vol_ratio)]
stopifnot(nrow(panel) > 0L)
message(sprintf("[INFO] complete-case panel rows: %s; sectors J=%d",
                format(nrow(panel), big.mark = ","), length(SECTORS_ALL)))

z_cols  <- function(ch) paste0("Z_",  ch, "_", SECTORS_ALL)
ec_cols <- function(ch) paste0("EC_", ch, "_", SECTORS_KEEP)

ALL_Z  <- unlist(lapply(CHANNELS, z_cols))
ALL_EC <- unlist(lapply(CHANNELS, ec_cols))
stopifnot(all(c(ALL_Z, ALL_EC) %in% names(panel)))

# ==============================================================================
# Residualisation utilities
# ==============================================================================
# partial out muni + year FE plus continuous controls (EC block + vol_ratio) —
# the non-instrument regressors of the AR reduced form (B6 run_ar).

# FE-demean a matrix on muni + year.
fe_demean <- function(M, dt) {
  fixest::demean(M, dt[, .(muni_id, year)])
}

# Partial continuous controls X out of Y (both already FE-demeaned).
# qr handles a rank-deficient X (EC blocks can be internally collinear); the
# residual is still the projection onto the orthogonal complement.
partial_controls <- function(Y, X) {
  if (is.null(X) || ncol(X) == 0L) return(Y)
  Y - qr.fitted(qr(X), Y)
}

# Residualise a set of Z columns on (EC block + vol_ratio + FE).
residualise <- function(dt, z_set, ec_set) {
  Zd  <- fe_demean(as.matrix(dt[, ..z_set]), dt)
  Xc  <- as.matrix(dt[, c(ec_set, "vol_ratio"), with = FALSE])
  Xcd <- fe_demean(Xc, dt)
  res <- partial_controls(Zd, Xcd)
  colnames(res) <- z_set
  res
}

# Collinearity diagnostics of a residualised instrument block.
diagnose_block <- function(Zres) {
  K   <- ncol(Zres)
  sds <- apply(Zres, 2L, sd)
  keep <- which(sds > 1e-10)
  n_degenerate <- K - length(keep)
  if (length(keep) == 0L) {
    return(list(K = K, rank = 0L, rank_deficiency = K,
                n_degenerate = n_degenerate, kappa = Inf,
                lambda_min = 0, lambda_max = NA_real_,
                worst_vif = Inf, mean_abs_corr = NA_real_,
                max_abs_corr = NA_real_))
  }
  R  <- cor(Zres[, keep, drop = FALSE])
  ev <- eigen(R, symmetric = TRUE, only.values = TRUE)$values
  ev <- pmax(ev, 0)
  lam_max <- max(ev); lam_min <- min(ev)
  tol  <- max(length(keep) * .Machine$double.eps * lam_max, 1e-8 * lam_max)
  rank <- sum(ev > tol)
  kappa <- if (lam_min > 1e-12) sqrt(lam_max / lam_min) else Inf
  vif <- tryCatch(diag(solve(R)), error = function(e) rep(Inf, length(keep)))
  worst_vif <- if (n_degenerate > 0L || rank < length(keep)) Inf else max(vif)
  off <- if (length(keep) > 1L) abs(R[upper.tri(R)]) else numeric(0)
  list(K = K, rank = as.integer(rank),
       rank_deficiency = as.integer(K - rank),
       n_degenerate = n_degenerate, kappa = kappa,
       lambda_min = lam_min, lambda_max = lam_max,
       worst_vif = worst_vif,
       mean_abs_corr = if (length(off)) mean(off) else NA_real_,
       max_abs_corr  = if (length(off)) max(off)  else NA_real_)
}

# Map a Z column to its channel (underscore-delimited prefix is unambiguous:
# Z_M_ does not match Z_MG_).
chan_of_col <- function(col) {
  for (ch in CHANNELS) if (grepl(paste0("^Z_", ch, "_"), col)) return(ch)
  NA_character_
}

# ==============================================================================
# Block 1A.2 + 1A.3 — per-stack diagnostics across candidate channel stacks
# ==============================================================================
# 18 candidate stacks, in four groups:
#   Singletons (7)         — each channel on its own.
#   Mayor stacks (4)       — Mayor paired with each mayor-crossed interaction,
#                            plus the full mayor-crossed stack.
#   Parent pairs (3)       — the two single-office parents of each interaction,
#                            without the interaction: {M,G}, {M,P}, {G,P}.
#   Parent + interaction (4) — an interaction together with all its parents.
# Every candidate stack is evaluated (no pruning at Phase 1A); the proposed
# admissibility verdict is advisory.

STACKS <- list(
  list(id = "M",          chans = "M",                       group = "Singletons"),
  list(id = "G",          chans = "G",                       group = "Singletons"),
  list(id = "P",          chans = "P",                       group = "Singletons"),
  list(id = "MG",         chans = "MG",                      group = "Singletons"),
  list(id = "MP",         chans = "MP",                      group = "Singletons"),
  list(id = "GP",         chans = "GP",                      group = "Singletons"),
  list(id = "MGP",        chans = "MGP",                     group = "Singletons"),
  list(id = "M_MP",       chans = c("M", "MP"),              group = "Mayor stacks"),
  list(id = "M_MG",       chans = c("M", "MG"),              group = "Mayor stacks"),
  list(id = "M_MGP",      chans = c("M", "MGP"),             group = "Mayor stacks"),
  list(id = "mayor_full", chans = c("M", "MP", "MG", "MGP"), group = "Mayor stacks"),
  list(id = "M_G",        chans = c("M", "G"),               group = "Parent pairs"),
  list(id = "M_P",        chans = c("M", "P"),               group = "Parent pairs"),
  list(id = "G_P",        chans = c("G", "P"),               group = "Parent pairs"),
  list(id = "M_P_MP",     chans = c("M", "P", "MP"),         group = "Parent + interaction"),
  list(id = "M_G_MG",     chans = c("M", "G", "MG"),         group = "Parent + interaction"),
  list(id = "G_P_GP",     chans = c("G", "P", "GP"),         group = "Parent + interaction"),
  list(id = "M_G_P_MGP",  chans = c("M", "G", "P", "MGP"),   group = "Parent + interaction")
)

# Plain-English stack label (for the CSV).
stack_label <- function(chans) {
  paste(vapply(chans, channel_label_plain, character(1)), collapse = " + ")
}

# Compact set-notation label (for the .tex table) — matches the deck's
# {M, G, M.G} shorthand. Interaction channels use the centered dot.
chan_code <- function(ch) {
  switch(ch, M = "M", G = "G", P = "P",
    MP = "M$\\cdot$P", MG = "M$\\cdot$G", GP = "G$\\cdot$P",
    MGP = "M$\\cdot$G$\\cdot$P", ch)
}
tex_set_label <- function(chans) {
  paste0("\\{", paste(vapply(chans, chan_code, character(1)),
                      collapse = ", "), "\\}")
}

# A stack is exact-product a-priori inadmissible if it contains an interaction
# channel together with ALL of that interaction's parents (parent set defined
# by the channel letters), and the interaction is an exact product (1A.1).
parent_set <- function(ch) {
  switch(ch,
    MG  = c("M", "G"),
    MP  = c("M", "P"),
    GP  = c("G", "P"),
    MGP = c("M", "G", "P"),
    character(0))
}

stack_exact_product <- function(chans) {
  for (ch in intersect(chans, EXACT_PRODUCT_CHANNELS)) {
    ps <- parent_set(ch)
    if (length(ps) > 0L && all(ps %in% chans)) return(TRUE)
  }
  FALSE
}

# Diagnostic-only: every channel sits outside the mayoral identifying
# restriction (G, P, GP only). Such stacks are not candidate AR instruments.
stack_diagnostic_only <- function(chans) all(chans %in% c("G", "P", "GP"))

# Three-valued verdict from the proposed admissibility rule.
classify_stack <- function(d, exact_apriori) {
  if (exact_apriori)
    return(list(verdict = "inadmissible", proposed_admissible = FALSE,
      reason = "Exact product: interaction alignment equals the product of its parents"))
  if (d$rank_deficiency > 0L)
    return(list(verdict = "inadmissible", proposed_admissible = FALSE,
      reason = sprintf("Rank-deficient: %d of %d instrument columns redundant",
                       d$rank_deficiency, d$K)))
  if (!is.finite(d$kappa) || d$kappa > 100)
    return(list(verdict = "inadmissible", proposed_admissible = FALSE,
      reason = sprintf("Severe collinearity: condition number %s exceeds 100",
                       fmt_big(d$kappa, 0L))))
  if (!is.finite(d$worst_vif) || d$worst_vif > 10)
    return(list(verdict = "inadmissible", proposed_admissible = FALSE,
      reason = sprintf("Inflated VIF: worst VIF %s exceeds 10",
                       fmt_big(d$worst_vif))))
  if (d$kappa > 30)
    return(list(verdict = "marginal", proposed_admissible = FALSE,
      reason = sprintf("Marginal: condition number %.1f in (30, 100]",
                       d$kappa)))
  list(verdict = "admissible", proposed_admissible = TRUE,
       reason = "Condition number, VIF, and rank all within thresholds")
}

message("\n[INFO] running per-stack collinearity diagnostics ...")
diag_rows  <- vector("list", length(STACKS))
admis_rows <- vector("list", length(STACKS))

for (i in seq_along(STACKS)) {
  st    <- STACKS[[i]]
  chans <- st$chans
  z_set  <- unlist(lapply(chans, z_cols))
  ec_set <- unlist(lapply(chans, ec_cols))
  Zres   <- residualise(panel, z_set, ec_set)
  d      <- diagnose_block(Zres)
  exact_apriori   <- stack_exact_product(chans)
  diagnostic_only <- stack_diagnostic_only(chans)
  cl     <- classify_stack(d, exact_apriori)

  diag_rows[[i]] <- data.table(
    stack_id      = st$id,
    stack_group   = st$group,
    stack_label   = stack_label(chans),
    tex_label     = tex_set_label(chans),
    channels      = paste(chans, collapse = ","),
    n_instruments = d$K,
    block_rank    = d$rank,
    rank_deficiency = d$rank_deficiency,
    condition_number = d$kappa,
    lambda_min    = d$lambda_min,
    lambda_max    = d$lambda_max,
    worst_vif     = d$worst_vif,
    mean_abs_corr = d$mean_abs_corr,
    max_abs_corr  = d$max_abs_corr,
    verdict       = cl$verdict,
    taxonomy      = TAX)

  admis_rows[[i]] <- data.table(
    stack_id      = st$id,
    stack_label   = stack_label(chans),
    channels      = paste(chans, collapse = ","),
    n_instruments = d$K,
    condition_number = d$kappa,
    worst_vif     = d$worst_vif,
    rank_deficient = d$rank_deficiency > 0L,
    exact_product_apriori = exact_apriori,
    diagnostic_only = diagnostic_only,
    candidate_ar_instrument = !diagnostic_only,
    verdict       = cl$verdict,
    proposed_admissible = cl$proposed_admissible,
    reason        = cl$reason,
    taxonomy      = TAX)
}

diag_dt  <- rbindlist(diag_rows)
admis_dt <- rbindlist(admis_rows)

message("\n[RESULT] 1A.2 / 1A.3 per-stack collinearity diagnosis:")
print(diag_dt[, .(stack_label,
                  K = n_instruments, rank = block_rank,
                  kappa = round(condition_number, 1),
                  worst_vif = round(worst_vif, 1),
                  max_corr = round(max_abs_corr, 2),
                  verdict)])

fwrite(diag_dt,  file.path(OUT, sprintf("collinearity_diagnosis_%s.csv", TAX)))
fwrite(admis_dt, file.path(OUT, sprintf("instrument_admissibility_%s.csv", TAX)))

# --- Global channel-level mean |corr| (1A.2 channel summary) -----------------
# All Z residualised on all EC + vol_ratio + FE; the 7x7 channel summary
# averages |corr| over every cross pair of residualised columns.

Zres_all <- residualise(panel, ALL_Z, ALL_EC)
col_chan <- vapply(colnames(Zres_all), chan_of_col, character(1))
Rall <- cor(Zres_all)
chan_corr <- matrix(NA_real_, length(CHANNELS), length(CHANNELS),
                    dimnames = list(CHANNELS, CHANNELS))
for (a in CHANNELS) for (b in CHANNELS) {
  ia <- which(col_chan == a); ib <- which(col_chan == b)
  if (!length(ia) || !length(ib)) next
  sub <- abs(Rall[ia, ib, drop = FALSE])
  if (identical(a, b)) {
    chan_corr[a, b] <- if (length(ia) > 1L)
      mean(sub[upper.tri(sub)]) else NA_real_
  } else {
    chan_corr[a, b] <- mean(sub)
  }
}
message("\n[RESULT] 1A.2 channel-level mean |correlation| (residualised Z):")
print(round(chan_corr, 3))

# ==============================================================================
# Block 1A.4 — design attribution: verticalizado vs post-verticalizacao split
# ==============================================================================
# TSE Resolution 20.993/2002 forced state coalitions to mirror the presidential
# coalition for the 2002 and 2006 cycles. Years <= 2009 draw their identifying
# gov/pres election from the 2002 or 2006 cycle (verticalizado); years >= 2010
# draw from the 2010 or 2014 cycle (post-verticalizacao). If verticalizacao
# drives the collinearity, the G-P and mayor-interaction correlations are
# higher in the verticalizado sub-period.

VERT_CUTOFF <- 2010L   # verticalizado: year < cutoff; post: year >= cutoff

# Channel-level mean |corr| for a sub-panel.
channel_corr_pair <- function(dt, ch_a, ch_b) {
  z_set  <- unlist(lapply(unique(c(ch_a, ch_b)), z_cols))
  ec_set <- unlist(lapply(unique(c(ch_a, ch_b)), ec_cols))
  if (nrow(dt) < 50L) return(NA_real_)
  R <- residualise(dt, z_set, ec_set)
  ca <- vapply(colnames(R), chan_of_col, character(1))
  ia <- which(ca == ch_a); ib <- which(ca == ch_b)
  cm <- cor(R)
  sub <- abs(cm[ia, ib, drop = FALSE])
  if (identical(ch_a, ch_b)) {
    if (length(ia) < 2L) return(NA_real_)
    mean(sub[upper.tri(sub)])
  } else {
    mean(sub)
  }
}

KEY_PAIRS <- list(
  c("G",  "P"),    # shared gov/pres election calendar
  c("MG", "MP"),   # verticalizacao: Align^G ~ Align^P
  c("MP", "MGP"),  # triple collapses toward M.P
  c("MG", "MGP"),  # triple collapses toward M.G
  c("M",  "MG"),   # alignment-product nesting
  c("M",  "MP"))   # alignment-product nesting

panel_vert <- panel[year <  VERT_CUTOFF]
panel_post <- panel[year >= VERT_CUTOFF]
message(sprintf("[INFO] verticalizado rows (year<%d): %s; post rows: %s",
                VERT_CUTOFF, format(nrow(panel_vert), big.mark = ","),
                format(nrow(panel_post), big.mark = ",")))

attr_rows <- vector("list", length(KEY_PAIRS))
for (i in seq_along(KEY_PAIRS)) {
  pr <- KEY_PAIRS[[i]]
  attr_rows[[i]] <- data.table(
    pair        = paste0(pr[1L], "-", pr[2L]),
    pair_label  = paste(channel_label_plain(pr[1L]), "vs",
                        channel_label_plain(pr[2L])),
    corr_full   = channel_corr_pair(panel,      pr[1L], pr[2L]),
    corr_verticalizado = channel_corr_pair(panel_vert, pr[1L], pr[2L]),
    corr_post   = channel_corr_pair(panel_post, pr[1L], pr[2L]),
    taxonomy    = TAX)
}
attr_dt <- rbindlist(attr_rows)
attr_dt[, vert_minus_post := corr_verticalizado - corr_post]
message("\n[RESULT] 1A.4 design attribution (verticalizado vs post-verticalizacao):")
print(attr_dt[, .(pair_label, corr_verticalizado = round(corr_verticalizado, 3),
                  corr_post = round(corr_post, 3),
                  vert_minus_post = round(vert_minus_post, 3))])
fwrite(attr_dt, file.path(OUT, sprintf("design_attribution_%s.csv", TAX)))

# ==============================================================================
# Bare-tabular .tex collinearity-diagnosis table (INV-13)
# ==============================================================================
# Rows = candidate stacks (grouped); columns = K, condition number, worst VIF,
# rank deficiency, proposed verdict. No \begin{table}, no caption, no notes.

verdict_label <- c(admissible = "Admissible", marginal = "Marginal",
                   inadmissible = "Inadmissible")

build_diag_tex <- function(dd) {
  lines <- c(
    "\\begin{tabular}{@{}lcccccc@{}}",
    "\\toprule",
    paste0("Instrument stack & $K$ & Condition no.\\ $\\kappa$ & ",
           "Worst VIF & Max $|r|$ & Rank def. & Verdict \\\\"),
    "\\midrule")
  groups <- unique(dd$stack_group)
  for (g in groups) {
    sub <- dd[stack_group == g]
    lines <- c(lines,
      sprintf("\\multicolumn{7}{@{}l}{\\textit{%s}} \\\\", g))
    for (i in seq_len(nrow(sub))) {
      r <- sub[i]
      lines <- c(lines, sprintf(
        "\\quad %s & %d & %s & %s & %s & %d & %s \\\\",
        r$tex_label, r$n_instruments,
        fmt_big(r$condition_number, 1L), fmt_big(r$worst_vif, 1L),
        if (is.finite(r$max_abs_corr))
          formatC(r$max_abs_corr, format = "f", digits = 2L) else "--",
        r$rank_deficiency, verdict_label[[r$verdict]]))
    }
    if (!identical(g, groups[length(groups)])) lines <- c(lines, "\\midrule")
  }
  c(lines, "\\bottomrule", "\\end{tabular}")
}

tex_path <- file.path(OUT, sprintf("collinearity_diagnosis_%s.tex", TAX))
writeLines(build_diag_tex(diag_dt), tex_path)
message(sprintf("[INFO] wrote %s", basename(tex_path)))

# --- Summary for the checkpoint report ---------------------------------------

n_adm  <- sum(admis_dt$proposed_admissible)
n_marg <- sum(admis_dt$verdict == "marginal")
n_inad <- sum(admis_dt$verdict == "inadmissible")
message(sprintf(
  "\n[SUMMARY] %s | stacks: %d proposed admissible, %d marginal, %d inadmissible",
  TAX, n_adm, n_marg, n_inad))
message(sprintf("[SUMMARY] interaction channels that are exact products: %s",
                paste(EXACT_PRODUCT_CHANNELS, collapse = ", ")))
message(sprintf("[INFO] wrote collinearity_diagnosis_%s.{csv,tex}, ",
                TAX),
        sprintf("instrument_admissibility_%s.csv, design_attribution_%s.csv",
                TAX, TAX))
message(sprintf("[INFO] %s | B7 done.", Sys.time()))
