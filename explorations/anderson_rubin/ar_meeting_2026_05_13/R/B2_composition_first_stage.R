#!/usr/bin/env Rscript
# ==============================================================================
# B2_composition_first_stage.R — saturated first stage of sectoral COMPOSITION.
#
# Endogenous = sector employment share s_emp[j,m,t]. Stacked long form, data at
# (muni, sector, year): regress s_emp on the seven own-sector channel
# instruments (each channel = its own-sector Z value, matched j-to-j),
#   FE   = muni^sector + sector^year
#   ctrl = own-sector EC of every channel (EC always included)
#   vcov = cluster by muni + sector.
# Reports per-channel coefficient, SE, per-channel first-stage F (cluster-robust
# Wald on that channel). Nested blocks: mains {M,G,P} -> +pairs -> +triple.
# Alternative LHS: BNDES credit share (upstream-mechanism check).
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/ar_first_stage_comp_<tax>.{tex,csv}
#       output/ar_first_stage_comp_nested_<tax>.csv
#       output/ar_first_stage_comp_credit_<tax>.csv
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
ROOT <- normalizePath(file.path(BR, "..", "..", ".."), winslash = "/", mustWork = TRUE)
DATA <- file.path(ROOT, "data", "processed")
OUT  <- file.path(BR, "output")

TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "policy_block_size_bin"))
message(sprintf("[INFO] %s | B2 composition first stage | tax=%s",
                Sys.time(), TAX))

CHANNELS <- all_channels()   # M G P MG MP GP MGP

# --- Load Z and EC (long), build own-sector channel instrument ---------------

Z  <- qs_read(file.path(OUT, sprintf("Z_variant_a_%s.qs2",  TAX))); setDT(Z)
EC <- qs_read(file.path(OUT, sprintf("EC_variant_a_%s.qs2", TAX))); setDT(EC)

# Wide-by-channel: one column Z_<channel> and EC_<channel> per (muni,year,sector)
Zw <- dcast(Z,  muni_id + year + sector ~ channel, value.var = "Z_val")
setnames(Zw, CHANNELS, paste0("Z_", CHANNELS))
ECw <- dcast(EC, muni_id + year + sector ~ channel, value.var = "EC_val")
# EC only on J-1 sectors; channels present same set.
ec_chan <- intersect(CHANNELS, names(ECw))
setnames(ECw, ec_chan, paste0("EC_", ec_chan))

# --- Endogenous: employment share s_emp[j,m,t] -------------------------------

if (identical(TAX, "policy_block")) {
  emp <- qs_read(file.path(DATA, "emp_share_panel_policy_block.qs2")); setDT(emp)
  emp <- emp[policy_block != "XX",
             .(muni_id = as.integer(muni_id), year = as.integer(year),
               sector = as.character(policy_block), s_emp = s_emp_mjt)]
} else {
  # policy_block_size_bin: build crossed-margin shares from the firm panel,
  # mirroring 03_build_muni_ar_panel.R lines ~67-103.
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

# --- Alternative LHS: BNDES credit share -------------------------------------

if (identical(TAX, "policy_block")) {
  cr <- qs_read(file.path(DATA, "bndes_credit_shares_policy_block.qs2"))
  setDT(cr)
  cr <- cr[policy_block != "XX",
           .(muni_id = as.integer(muni_id), year = as.integer(year),
             sector = as.character(policy_block), s_credit = s_mjt)]
} else {
  cr <- NULL   # no crossed-margin credit share panel; skip alt LHS at 12-group
}

# --- Assemble stacked (muni, sector, year) analysis table --------------------

assemble <- function(lhs_dt, lhs_name) {
  dt <- merge(lhs_dt, Zw,  by = c("muni_id", "year", "sector"), all.x = TRUE)
  dt <- merge(dt, ECw, by = c("muni_id", "year", "sector"), all.x = TRUE)
  # Zero-fill Z/EC (a muni-sector-year with no aligned owners has no shock).
  zc <- grep("^Z_",  names(dt), value = TRUE)
  ec <- grep("^EC_", names(dt), value = TRUE)
  for (cc in c(zc, ec))
    set(dt, i = which(is.na(dt[[cc]])), j = cc, value = 0)
  dt <- dt[is.finite(get(lhs_name))]
  dt[, muni_sector := paste0(muni_id, "_", sector)]
  dt[]
}

ec_present <- grep("^EC_", names(ECw), value = TRUE)
ec_rhs <- paste(ec_present, collapse = " + ")

# Per-channel first-stage F = cluster-robust Wald on that channel's coef.
run_saturated <- function(dt, lhs_name, z_terms) {
  stopifnot(nrow(dt) > 0L)
  fml <- as.formula(sprintf(
    "%s ~ %s + %s | muni_sector + sector^year",
    lhs_name, paste(z_terms, collapse = " + "), ec_rhs))
  mod <- tryCatch(
    feols(fml, data = dt, vcov = ~ muni_id + sector, lean = FALSE),
    error = function(e) {
      message(sprintf("[WARN] composition fit failed [%s]: %s",
                      lhs_name, conditionMessage(e)))
      NULL
    })
  if (is.null(mod)) return(NULL)
  ct  <- coeftable(mod)
  per <- vector("list", length(z_terms))
  for (i in seq_along(z_terms)) {
    zt <- z_terms[[i]]
    wd <- tryCatch(fixest::wald(mod, keep = paste0("^", zt, "$")),
                   error = function(e) NULL)
    per[[i]] <- data.table(
      term  = zt,
      coef  = if (zt %in% rownames(ct)) ct[zt, "Estimate"]   else NA_real_,
      se    = if (zt %in% rownames(ct)) ct[zt, "Std. Error"] else NA_real_,
      tstat = if (zt %in% rownames(ct)) ct[zt, 3L]           else NA_real_,
      pval  = if (zt %in% rownames(ct)) ct[zt, 4L]           else NA_real_,
      F_partial = if (!is.null(wd)) as.numeric(wd$stat) else NA_real_,
      p_partial = if (!is.null(wd)) as.numeric(wd$p)    else NA_real_)
  }
  list(mod = mod, per = rbindlist(per), n_obs = nobs(mod))
}

# --- Main: all seven channels, employment share LHS --------------------------

dt_emp <- assemble(emp, "s_emp")
stopifnot(nrow(dt_emp) > 0L)
message(sprintf("[INFO] employment-share analysis rows: %s",
                format(nrow(dt_emp), big.mark = ",")))

z_all <- paste0("Z_", CHANNELS)
sat   <- run_saturated(dt_emp, "s_emp", z_all)
if (is.null(sat)) stop("B2: saturated employment-share fit failed.")

# Joint F on ALL seven channels in the saturated fit.
# Guard: the 7 saturated channels are nested ("on" sets), so at coarse margins
# their cluster-robust VCV can be near-singular and the joint Wald F degenerate.
# When flagged rank-deficient, store NA for joint F/p (per-channel F's are fine).
w_all <- fixest::wald(sat$mod, keep = "^Z_")
joint_F_emp <- as.numeric(w_all$stat)
joint_p_emp <- as.numeric(w_all$p)
joint_rd_emp <- joint_F_rank_deficient(joint_F_emp)
if (joint_rd_emp) {
  message(sprintf(
    "[WARN] joint F over 7 channels is rank-deficient (F=%.3g); reporting NA.",
    joint_F_emp))
  joint_F_emp <- NA_real_
  joint_p_emp <- NA_real_
}
per <- sat$per
per[, channel := sub("^Z_", "", term)]
per[, channel_label := vapply(channel, channel_label_plain, character(1))]
per[, relevant_5pc  := is.finite(p_partial) & p_partial < 0.05]
per[, lhs := "s_emp"]
per[, n_obs := sat$n_obs]
per[, joint_F_7chan := joint_F_emp]
per[, joint_p_7chan := joint_p_emp]
per[, joint_rank_deficient := joint_rd_emp]
setcolorder(per, c("channel", "channel_label", "term", "coef", "se",
                   "tstat", "pval", "F_partial", "p_partial", "relevant_5pc"))

message("\n[RESULT] B2 saturated composition first stage (employment share):")
print(per[, .(channel_label, coef = round(coef, 4), se = round(se, 4),
              F_partial = round(F_partial, 2),
              p_partial = round(p_partial, 4), relevant_5pc)])
if (joint_rd_emp) {
  message("[RESULT] joint F on all 7 channels: rank-deficient (collinear channels)")
} else {
  message(sprintf("[RESULT] joint F on all 7 channels: %.3f (p=%.4g)",
                  joint_F_emp, joint_p_emp))
}

fwrite(per, file.path(OUT, sprintf("ar_first_stage_comp_%s.csv", TAX)))

# --- Nested blocks: mains -> +pairs -> +triple -------------------------------

blocks <- list(
  mains      = c("M", "G", "P"),
  plus_pairs = c("M", "G", "P", "MG", "MP", "GP"),
  plus_triple = CHANNELS)
nested <- vector("list", length(blocks))
for (i in seq_along(blocks)) {
  zb <- paste0("Z_", blocks[[i]])
  rs <- run_saturated(dt_emp, "s_emp", zb)
  if (is.null(rs)) stop(sprintf("B2: nested-block fit failed (%s).",
                                names(blocks)[i]))
  wj <- fixest::wald(rs$mod, keep = "^Z_")
  nested[[i]] <- data.table(
    block   = names(blocks)[i],
    n_chan  = length(blocks[[i]]),
    joint_F = as.numeric(wj$stat),
    joint_p = as.numeric(wj$p),
    n_obs   = rs$n_obs)
}
nested_dt <- rbindlist(nested)
message("\n[RESULT] B2 nested-block joint F (employment share):")
print(nested_dt)
fwrite(nested_dt, file.path(OUT, sprintf("ar_first_stage_comp_nested_%s.csv", TAX)))

# --- Alternative LHS: BNDES credit share -------------------------------------

if (!is.null(cr)) {
  dt_cr <- assemble(cr, "s_credit")
  stopifnot(nrow(dt_cr) > 0L)
  message(sprintf("[INFO] credit-share analysis rows: %s",
                  format(nrow(dt_cr), big.mark = ",")))
  sat_cr <- run_saturated(dt_cr, "s_credit", z_all)
  if (is.null(sat_cr)) stop("B2: saturated credit-share fit failed.")
  w_cr <- fixest::wald(sat_cr$mod, keep = "^Z_")
  joint_F_cr <- as.numeric(w_cr$stat)
  joint_p_cr <- as.numeric(w_cr$p)
  joint_rd_cr <- joint_F_rank_deficient(joint_F_cr)
  if (joint_rd_cr) {
    message(sprintf(
      "[WARN] credit-share joint F is rank-deficient (F=%.3g); reporting NA.",
      joint_F_cr))
    joint_F_cr <- NA_real_
    joint_p_cr <- NA_real_
  }
  per_cr <- sat_cr$per
  per_cr[, channel := sub("^Z_", "", term)]
  per_cr[, channel_label := vapply(channel, channel_label_plain, character(1))]
  per_cr[, relevant_5pc := is.finite(p_partial) & p_partial < 0.05]
  per_cr[, lhs := "s_credit"]
  per_cr[, n_obs := sat_cr$n_obs]
  per_cr[, joint_F_7chan := joint_F_cr]
  per_cr[, joint_p_7chan := joint_p_cr]
  per_cr[, joint_rank_deficient := joint_rd_cr]
  message("\n[RESULT] B2 saturated first stage (BNDES credit share):")
  print(per_cr[, .(channel_label, coef = round(coef, 4),
                   F_partial = round(F_partial, 2),
                   p_partial = round(p_partial, 4), relevant_5pc)])
  fwrite(per_cr, file.path(OUT, sprintf("ar_first_stage_comp_credit_%s.csv", TAX)))
}

# --- Bare-tabular .tex (INV-13): channel x {coef, SE, F, p, relevant} --------
# fmt_n() comes from 00_helpers.R; coef/SE shown at 4 digits, F at 2, p at 3.

build_tex <- function(pd) {
  lines <- c(
    "\\begin{tabular}{@{}lccccc@{}}",
    "\\toprule",
    "Channel & Coefficient & Std. error & Partial $F$ & $p$-value & Relevant \\\\",
    "\\midrule")
  for (i in seq_len(nrow(pd))) {
    r <- pd[i]
    lines <- c(lines, sprintf(
      "%s & %s & %s & %s & %s & %s \\\\",
      channel_label(r$channel), fmt_n(r$coef, 4L), fmt_n(r$se, 4L),
      fmt_n(r$F_partial, 2L), fmt_n(r$p_partial, 3L),
      if (isTRUE(r$relevant_5pc)) "Yes" else "No"))
  }
  joint_cell <- if (isTRUE(pd$joint_rank_deficient[1L])) {
    "Rank-deficient (collinear channels)"
  } else {
    sprintf("$F=%s$, $p=%s$",
            fmt_n(pd$joint_F_7chan[1L], 2L),
            fmt_n(pd$joint_p_7chan[1L], 4L))
  }
  lines <- c(lines, "\\midrule",
    sprintf("Joint ($7$ channels) & \\multicolumn{5}{c}{%s} \\\\", joint_cell),
    "\\bottomrule", "\\end{tabular}")
  lines
}
writeLines(build_tex(per),
           file.path(OUT, sprintf("ar_first_stage_comp_%s.tex", TAX)))
message(sprintf("[INFO] wrote ar_first_stage_comp_%s.{tex,csv}", TAX))
message(sprintf("[INFO] %s | B2 done.", Sys.time()))
