#!/usr/bin/env Rscript
# ==============================================================================
# B9_stack_ar_screen.R - Phase 2 baseline AR screen over an explicit stack list.
#
# B6 runs the AR test on the single B4-routed composition set and the four
# mayor-crossed channels. B9 runs it on an arbitrary list of instrument stacks -
# the "current excluded-stack design": every channel in a stack contributes its
# full J-column Z block as an excluded instrument, e.g. the stack {M, P, MP}
# excludes Z_M, Z_P, and Z_MP jointly.
#
# AR structure matches B6 exactly:
#   unit                = municipality-year
#   outcome             = log_gdp
#   FE                  = muni_id + year
#   cluster             = muni_id
#   controls            = the stack's EC block (+ vol_ratio under volctrl)
#   excluded instruments= the stack's Z blocks
#   AR statistic        = cluster-robust joint Wald on the Z coefficients only.
#
# THREE volume treatments, matching B6:
#   novol   - no volume control;
#   volctrl - vol_ratio as a predetermined control (the verdict);
#   volIV   - vol_ratio instrumented (Full IV).
# The Full-IV spec needs an instrument for vol_ratio. B9 builds it from a
# self-contained VOLUME FIRST STAGE: for each channel c, vol_ratio is regressed
# on the muni-aggregated channel instrument Zbar_c = sum_j Z^c_jmt (with EC_c,
# FE, muni clustering). Channels whose partial F clears the 5% gate are the
# volume instruments. For a given excluded stack, vol_ratio is instrumented by
# the Zbar of the volume-relevant channels NOT already in that stack - using
# Zbar_c when channel c is in the stack would be collinear with the stack's own
# excluded Z block.
#
# Each AR result is paired with the Phase 1B wide-form relevance verdict (B8,
# volume-control rows) for the same stack.
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/stack_ar_screen_<tax>.{csv,tex}
#       output/volume_first_stage_<tax>.{csv,tex}
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})
setDTthreads(0L)
fixest::setFixest_nthreads(4L)
set.seed(20260522L)

source_helpers <- function() {
  a  <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (!length(fa)) stop("Run via Rscript.")
  this <- normalizePath(sub("^--file=", "", fa[[1L]]),
                        winslash = "/", mustWork = TRUE)
  source(file.path(dirname(this), "00_helpers.R"))
}
source_helpers()  # provides get_this_script(), parse_kv(), fmt_*, stars()

THIS <- get_this_script()
BR   <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
OUT  <- file.path(BR, "output")

TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "policy_block_size_bin"))
message(sprintf("[INFO] %s | B9 stack AR screen | tax=%s", Sys.time(), TAX))

CHANNELS <- all_channels()

# --- Stack list (the current excluded-stack design) --------------------------
# stack_id values match B8 so the Phase 1B relevance verdict can be joined.

STACKS_BY_TAX <- list(
  policy_block = list(
    list(id = "MP",        chans = "MP"),
    list(id = "MG",        chans = "MG"),
    list(id = "MGP",       chans = "MGP"),
    list(id = "G",         chans = "G"),
    list(id = "P",         chans = "P"),
    list(id = "GP",        chans = "GP"),
    list(id = "M_G",       chans = c("M", "G")),
    list(id = "M_P",       chans = c("M", "P")),
    list(id = "G_P",       chans = c("G", "P")),
    list(id = "M_P_MP",    chans = c("M", "P", "MP")),
    list(id = "G_P_GP",    chans = c("G", "P", "GP")),
    list(id = "M_G_P_MGP", chans = c("M", "G", "P", "MGP"))
  ),
  policy_block_size_bin = list(
    list(id = "G",  chans = "G"),
    list(id = "P",  chans = "P"),
    list(id = "GP", chans = "GP")
  )
)
STACKS <- STACKS_BY_TAX[[TAX]]

# --- Label helpers ------------------------------------------------------------

chan_code <- function(ch) {
  switch(ch, M = "M", G = "G", P = "P",
    MP = "M$\\cdot$P", MG = "M$\\cdot$G", GP = "G$\\cdot$P",
    MGP = "M$\\cdot$G$\\cdot$P", ch)
}

tex_set_label <- function(chans) {
  paste0("\\{", paste(vapply(chans, chan_code, character(1)),
                      collapse = ", "), "\\}")
}

plain_set_label <- function(chans) {
  paste0("{", paste(vapply(chans, channel_label_plain, character(1)),
                    collapse = ", "), "}")
}

# --- Load panel ---------------------------------------------------------------

panel <- qs_read(file.path(OUT, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(panel)
stopifnot(nrow(panel) > 0L)
SECTORS_ALL  <- attr(panel, "sectors_all")
SECTORS_KEEP <- attr(panel, "sectors_keep")
panel <- panel[is.finite(log_gdp) & is.finite(vol_ratio)]
stopifnot(nrow(panel) > 0L)
message(sprintf("[INFO] complete-case rows: %s",
                format(nrow(panel), big.mark = ",")))

z_cols  <- function(ch) paste0("Z_",  ch, "_", SECTORS_ALL)
ec_cols <- function(ch) paste0("EC_", ch, "_", SECTORS_KEEP)

# Muni-aggregated channel instrument Zbar_c = sum_j Z^c_jmt (the volume
# instrument, as in B6's Full-IV spec).
for (ch in CHANNELS) {
  zc <- z_cols(ch)
  panel[, (paste0("Zbar_", ch)) := rowSums(.SD), .SDcols = zc]
}

# --- Volume first stage: which channels predict vol_ratio? -------------------
# Per channel c: vol_ratio ~ Zbar_c + EC_c | muni + year, clustered by muni.
# The partial F on Zbar_c is the cluster-robust Wald; p < 0.05 makes channel c
# a usable volume instrument for the Full-IV spec.

volume_first_stage <- function() {
  rows <- vector("list", length(CHANNELS))
  for (i in seq_along(CHANNELS)) {
    ch  <- CHANNELS[[i]]
    zb  <- paste0("Zbar_", ch)
    ecc <- ec_cols(ch)
    fml <- as.formula(sprintf("vol_ratio ~ %s | muni_id + year",
                              paste(c(zb, ecc), collapse = " + ")))
    mod <- tryCatch(feols(fml, data = panel, vcov = ~ muni_id, lean = FALSE),
                    error = function(e) NULL)
    if (is.null(mod)) {
      rows[[i]] <- data.table(channel = ch,
                              channel_label = channel_label_plain(ch),
                              coef = NA_real_, se = NA_real_,
                              F_partial = NA_real_, p_partial = NA_real_,
                              volume_relevant = FALSE)
      next
    }
    ct <- coeftable(mod)
    wd <- tryCatch(fixest::wald(mod, keep = paste0("^", zb, "$")),
                   error = function(e) NULL)
    rows[[i]] <- data.table(
      channel = ch,
      channel_label = channel_label_plain(ch),
      coef = if (zb %in% rownames(ct)) ct[zb, "Estimate"]   else NA_real_,
      se   = if (zb %in% rownames(ct)) ct[zb, "Std. Error"] else NA_real_,
      F_partial = if (!is.null(wd)) as.numeric(wd$stat) else NA_real_,
      p_partial = if (!is.null(wd)) as.numeric(wd$p)    else NA_real_)
    rows[[i]][, volume_relevant := is.finite(p_partial) & p_partial < 0.05]
  }
  rbindlist(rows)
}

vfs <- volume_first_stage()
vfs[, taxonomy := TAX]
VOL_CHANNELS <- vfs[volume_relevant == TRUE, channel]
fwrite(vfs, file.path(OUT, sprintf("volume_first_stage_%s.csv", TAX)))

message("\n[RESULT] B9 volume first stage (vol_ratio ~ Zbar_c + EC_c):")
print(vfs[, .(channel_label, coef = signif(coef, 3),
              F = round(F_partial, 2), p = signif(p_partial, 3),
              volume_relevant)])
message(sprintf("[INFO] volume instruments (p<0.05): {%s}",
                if (length(VOL_CHANNELS)) paste(VOL_CHANNELS, collapse = ", ")
                else "(none)"))

# --- Phase 1B relevance verdict (B8 wide-form, volume-control rows) ----------

b8_path <- file.path(OUT, sprintf("wide_first_stage_%s.csv", TAX))
b8 <- if (file.exists(b8_path)) {
  d <- fread(b8_path)
  d[volume_control == TRUE,
    .(stack_id, n_endogenous, identified_shares, sw_max,
      kp_rank_wald, kp_p, relevant_verdict)]
} else {
  message("[WARN] B8 wide_first_stage CSV not found - relevance columns blank")
  NULL
}

# --- AR run for one stack under one volume treatment -------------------------
#   spec in {"novol", "volctrl", "volIV"}.
#   AR stat = cluster-robust joint Wald on the stack's Z coefficients only.
#   volIV instruments vol_ratio with Zbar of `vol_inst` (channels not in stack).

run_ar <- function(chans, spec, vol_inst = character(0L)) {
  zc  <- unlist(lapply(chans, z_cols))
  ecc <- unlist(lapply(chans, ec_cols))
  key <- paste0("^(", paste0("Z_", chans, "_", collapse = "|"), ")")
  na_out <- list(ar_F = NA_real_, ar_p = NA_real_, df1 = NA_integer_,
                 df2 = NA_integer_, K_Z = length(zc), n_obs = NA_integer_,
                 reject_5pc = NA, vol_fs_F = NA_real_)

  if (spec == "volIV" && length(vol_inst) == 0L) return(na_out)

  if (spec == "novol") {
    fml <- as.formula(sprintf("log_gdp ~ %s | muni_id + year",
                              paste(c(zc, ecc), collapse = " + ")))
  } else if (spec == "volctrl") {
    fml <- as.formula(sprintf("log_gdp ~ %s | muni_id + year",
                              paste(c(zc, ecc, "vol_ratio"), collapse = " + ")))
  } else {  # volIV
    zbar <- paste0("Zbar_", vol_inst)
    fml <- as.formula(sprintf(
      "log_gdp ~ %s | muni_id + year | vol_ratio ~ %s",
      paste(c(zc, ecc), collapse = " + "),
      paste(zbar, collapse = " + ")))
  }
  mod <- tryCatch(
    feols(fml, data = panel, vcov = ~ muni_id, lean = FALSE),
    error = function(e) {
      message(sprintf("[WARN] AR fit failed [%s/%s]: %s",
                      paste(chans, collapse = ","), spec,
                      conditionMessage(e)))
      NULL
    })
  if (is.null(mod)) return(na_out)
  wd <- fixest::wald(mod, keep = key)
  vol_fs_F <- NA_real_
  if (spec == "volIV") {
    vol_fs_F <- tryCatch({
      ff <- fitstat(mod, ~ ivf1, verbose = FALSE)
      as.numeric(ff[[1L]]$stat)
    }, error = function(e) NA_real_)
  }
  list(ar_F = as.numeric(wd$stat), ar_p = as.numeric(wd$p),
       df1 = as.integer(wd$df1), df2 = as.integer(wd$df2),
       K_Z = length(zc), n_obs = nobs(mod),
       reject_5pc = isTRUE(as.numeric(wd$p) < 0.05),
       vol_fs_F = vol_fs_F)
}

# --- Screen -------------------------------------------------------------------

rows <- list()
for (st in STACKS) {
  vi <- setdiff(VOL_CHANNELS, st$chans)  # volume instruments usable for this stack
  message(sprintf("[INFO] stack %-10s {%s} | volIV instruments {%s}",
                  st$id, paste(st$chans, collapse = ","),
                  if (length(vi)) paste(vi, collapse = ",") else "none"))
  nv <- run_ar(st$chans, "novol")
  vc <- run_ar(st$chans, "volctrl")
  iv <- run_ar(st$chans, "volIV", vol_inst = vi)
  rows[[st$id]] <- data.table(
    taxonomy        = TAX,
    stack_id        = st$id,
    stack_label     = plain_set_label(st$chans),
    tex_label       = tex_set_label(st$chans),
    channels        = paste(st$chans, collapse = ","),
    n_channels      = length(st$chans),
    K_Z             = vc$K_Z,
    ar_F_novol      = nv$ar_F,
    ar_p_novol      = nv$ar_p,
    reject_novol    = nv$reject_5pc,
    ar_F_volctrl    = vc$ar_F,
    ar_p_volctrl    = vc$ar_p,
    reject_volctrl  = vc$reject_5pc,
    ar_F_volIV      = iv$ar_F,
    ar_p_volIV      = iv$ar_p,
    reject_volIV    = iv$reject_5pc,
    volIV_instrument = if (length(vi)) paste(vi, collapse = ",") else NA_character_,
    volIV_fs_F      = iv$vol_fs_F,
    df1             = vc$df1,
    n_obs           = vc$n_obs)
}
res <- rbindlist(rows)

# Pair with the Phase 1B wide-form relevance verdict.
if (!is.null(b8)) {
  res <- merge(res, b8, by = "stack_id", all.x = TRUE, sort = FALSE)
} else {
  res[, `:=`(n_endogenous = NA_integer_, identified_shares = NA_integer_,
             sw_max = NA_real_, kp_rank_wald = NA_real_, kp_p = NA_real_,
             relevant_verdict = NA)]
}
stack_order <- vapply(STACKS, `[[`, character(1), "id")
res[, stack_order := match(stack_id, stack_order)]
setorder(res, stack_order)
res[, stack_order := NULL]

csv_path <- file.path(OUT, sprintf("stack_ar_screen_%s.csv", TAX))
fwrite(res, csv_path)

message("\n[RESULT] B9 stack AR screen (AR F by volume treatment):")
print(res[, .(stack_label, K_Z,
              novol   = round(ar_F_novol, 3),
              volctrl = round(ar_F_volctrl, 3),
              volIV   = round(ar_F_volIV, 3),
              reject_vc = reject_volctrl,
              id_shares = sprintf("%s/%s", identified_shares, n_endogenous))])

# --- Bare-tabular .tex (INV-13) ----------------------------------------------
# fmt_F() / fmt_p() / stars() come from 00_helpers.R. No \begin{table},
# no \caption, no notes - the slide wraps it.

ar_cell <- function(F, p) {
  if (!is.finite(F)) return("--")
  sprintf("%s%s [%s]", fmt_F(F), stars(p), fmt_p(p))
}

build_screen_tex <- function(rd) {
  lines <- c(
    "\\begin{tabular}{@{}lccccccc@{}}",
    "\\toprule",
    paste0("Excluded stack & $K_Z$ & AR $F$ (no vol.) & ",
           "AR $F$ (vol. control) & AR $F$ (vol. instr.) & ",
           "Reject 5\\% & Relevant shares \\\\"),
    "\\midrule")
  for (i in seq_len(nrow(rd))) {
    r <- rd[i]
    reject <- if (isTRUE(r$reject_volctrl)) "Yes" else "No"
    idsh   <- if (is.finite(r$identified_shares) &&
                  is.finite(r$n_endogenous))
                sprintf("%d/%d", r$identified_shares, r$n_endogenous)
              else "--"
    lines <- c(lines, paste0(
      r$tex_label, " & ", r$K_Z, " & ",
      ar_cell(r$ar_F_novol,   r$ar_p_novol),   " & ",
      ar_cell(r$ar_F_volctrl, r$ar_p_volctrl), " & ",
      ar_cell(r$ar_F_volIV,   r$ar_p_volIV),   " & ",
      reject, " & ", idsh, " \\\\"))
  }
  c(lines, "\\bottomrule", "\\end{tabular}")
}

tex_path <- file.path(OUT, sprintf("stack_ar_screen_%s.tex", TAX))
writeLines(build_screen_tex(res), tex_path)

build_vfs_tex <- function(vd) {
  lines <- c(
    "\\begin{tabular}{@{}lcccc@{}}",
    "\\toprule",
    "Channel & Coefficient & Partial $F$ & $p$-value & Volume instrument \\\\",
    "\\midrule")
  for (i in seq_len(nrow(vd))) {
    r <- vd[i]
    lines <- c(lines, sprintf(
      "%s & %s & %s%s & %s & %s \\\\",
      channel_label(r$channel), fmt_g(r$coef, 3L),
      fmt_F(r$F_partial, 2L), stars(r$p_partial),
      fmt_p(r$p_partial, 3L),
      if (isTRUE(r$volume_relevant)) "Yes" else "No"))
  }
  c(lines, "\\bottomrule", "\\end{tabular}")
}
writeLines(build_vfs_tex(vfs),
           file.path(OUT, sprintf("volume_first_stage_%s.tex", TAX)))

message(sprintf("[INFO] wrote stack_ar_screen_%s.{csv,tex} and volume_first_stage_%s.{csv,tex}",
                TAX, TAX))
message(sprintf("[INFO] %s | B9 done.", Sys.time()))
