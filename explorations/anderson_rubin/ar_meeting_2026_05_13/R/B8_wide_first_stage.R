#!/usr/bin/env Rscript
# ==============================================================================
# B8_wide_first_stage.R - Phase 1B: wide-form first-stage relevance.
#
# Estimates the first stage embedded in the AR test:
#   log_gdp ~ EC + vol_ratio | muni + year | s_j ~ Z-block
# on the muni-year AR panel. The endogenous share vector omits the simplex
# hold-out sector used by 03_build_muni_ar_panel.R. Every candidate stack from
# B7 is evaluated; checkpoint #1 requires no pruning.
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/wide_first_stage_<tax>.{csv,tex}
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
source_helpers()

THIS <- get_this_script()
BR   <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
ROOT <- normalizePath(file.path(BR, "..", "..", ".."), winslash = "/", mustWork = TRUE)
DATA <- file.path(ROOT, "data", "processed")
OUT  <- file.path(BR, "output")

TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "policy_block_size_bin"))
message(sprintf("[INFO] %s | B8 wide-form first stage | tax=%s",
                Sys.time(), TAX))

CHANNELS <- all_channels()

# The same 18 candidate stacks as B7. Checkpoint #1 says evaluate all of them.
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

stack_label <- function(chans) {
  paste(vapply(chans, channel_label_plain, character(1)), collapse = " + ")
}

chan_code <- function(ch) {
  switch(ch, M = "M", G = "G", P = "P",
    MP = "M$\\cdot$P", MG = "M$\\cdot$G", GP = "G$\\cdot$P",
    MGP = "M$\\cdot$G$\\cdot$P", ch)
}

tex_set_label <- function(chans) {
  paste0("\\{", paste(vapply(chans, chan_code, character(1)),
                      collapse = ", "), "\\}")
}

tex_escape <- function(x) {
  gsub("_", "\\_", x, fixed = TRUE)
}

# --- Endogenous shares --------------------------------------------------------

build_share_wide <- function(tax, sectors_keep) {
  if (identical(tax, "policy_block")) {
    emp <- qs_read(file.path(DATA, "emp_share_panel_policy_block.qs2"))
    setDT(emp)
    emp <- emp[policy_block != "XX",
               .(muni_id = as.integer(muni_id),
                 year    = as.integer(year),
                 sector  = as.character(policy_block),
                 s_emp   = s_emp_mjt)]
  } else {
    message("[INFO] computing policy_block_size_bin employment shares ...")
    fp <- qs_read(file.path(DATA, "firm_panel_for_regs.qs2"))
    setDT(fp)
    fp <- fp[, .(firm_id = as.integer(firm_id),
                 muni_id = as.integer(muni_id),
                 year    = as.integer(year),
                 cnae_section = as.character(cnae_section),
                 n_employees)]
    fp <- fp[!is.na(cnae_section) & nzchar(cnae_section)]

    pbm <- qs_read(file.path(DATA, "policy_block_mapping.qs2"))
    setDT(pbm)
    pbm <- pbm[policy_block != "XX"]
    fp <- merge(fp, pbm[, .(cnae_section, policy_block)],
                by = "cnae_section", all.x = FALSE)
    fp[, cnae_section := NULL]

    sb <- qs_read(file.path(DATA, "size_bin_mapping.qs2"))
    setDT(sb)
    fp[, election_cycle := vapply(year, function(y) {
      cs <- SIZE_CYCLES[SIZE_CYCLES <= y]
      if (length(cs) == 0L) SIZE_CYCLES[1L] else max(cs)
    }, integer(1))]
    sb[, `:=`(election_cycle = as.integer(election_cycle),
              firm_id = as.integer(firm_id),
              size_bin = as.integer(size_bin))]
    fp <- merge(fp, sb[, .(firm_id, election_cycle, size_bin)],
                by = c("firm_id", "election_cycle"), all.x = FALSE)
    fp[, sector := paste0(policy_block, "_", size_bin)]

    njmt <- fp[!is.na(n_employees),
               .(n_jmt = sum(n_employees, na.rm = TRUE)),
               by = .(muni_id, year, sector)]
    nmt  <- njmt[, .(n_mt = sum(n_jmt, na.rm = TRUE)), by = .(muni_id, year)]
    njmt <- merge(njmt, nmt, by = c("muni_id", "year"))
    njmt[, s_emp := n_jmt / n_mt]
    emp <- njmt[, .(muni_id, year, sector, s_emp)]
    rm(fp, sb, pbm, njmt, nmt)
    gc(verbose = FALSE)
  }

  emp <- emp[sector %in% sectors_keep]
  sw <- dcast(emp, muni_id + year ~ sector, value.var = "s_emp", fill = 0)
  for (sec in sectors_keep) {
    if (!sec %in% names(sw)) sw[, (sec) := 0]
  }
  setnames(sw, sectors_keep, paste0("s_", sectors_keep), skip_absent = TRUE)
  s_cols <- paste0("s_", sectors_keep)
  for (cc in s_cols) {
    set(sw, i = which(is.na(sw[[cc]]) | !is.finite(sw[[cc]])), j = cc, value = 0)
  }
  sw[, c("muni_id", "year", s_cols), with = FALSE]
}

# --- KP rank Wald -------------------------------------------------------------
# Adapted from fixest's KP implementation, with the multi-endogenous first-stage
# coefficient table coerced to a numeric matrix. This keeps the same residual
# projection, score, and small-sample correction logic as fixest.

cluster_score_meat <- function(scores, cluster) {
  stopifnot(nrow(scores) == length(cluster))
  cl <- as.factor(cluster)
  Sg <- rowsum(scores, cl, reorder = FALSE)
  meat <- crossprod(Sg) / nrow(scores)
  G <- nrow(Sg)
  if (G > 1L) {
    meat <- meat * (G / (G - 1L)) * ((nrow(scores) - 1L) / nrow(scores))
  }
  meat
}

kp_rank_wald <- function(x, cluster) {
  out <- list(stat = NA_real_, p = NA_real_, df = NA_integer_,
              nondegenerate = FALSE, error = NA_character_)
  tryCatch({
    if (!isTRUE(x$iv) || x$iv_stage != 2L) {
      out$error <- "not a second-stage IV model"
      return(out)
    }
    X_proj <- as.matrix(resid(summary(x, stage = 1)))
    Z <- model.matrix(x, type = "iv.inst")
    Z_proj <- fixest:::proj_on_U(x, Z)

    k <- n_endo <- ncol(X_proj)
    l <- n_inst <- ncol(Z)
    if (!is.finite(k) || !is.finite(l) || l < k) {
      out$error <- "fewer instruments than endogenous regressors"
      return(out)
    }

    pi_raw <- coef(summary(x, stage = 1))
    if (is.data.frame(pi_raw)) {
      PI <- as.matrix(pi_raw[, x$iv_inst_names_xpd, drop = FALSE])
    } else {
      PI <- if (n_endo == 1L) t(pi_raw) else as.matrix(pi_raw)
      PI <- PI[, colnames(PI) %in% x$iv_inst_names_xpd, drop = FALSE]
    }
    storage.mode(PI) <- "double"
    if (nrow(PI) != n_endo || ncol(PI) != n_inst) {
      out$error <- "unexpected first-stage coefficient dimensions"
      return(out)
    }

    Fmat <- chol(crossprod(Z_proj))
    Gmat <- chol(crossprod(X_proj))
    theta <- Fmat %*% t(solve(t(Gmat), PI))

    if (n_inst == n_endo) {
      svd_decomp <- svd(theta)
      u <- svd_decomp$u
      vt <- t(svd_decomp$v)
    } else {
      svd_decomp <- fixest:::mat_svd(theta)
      u <- svd_decomp$u
      vt <- svd_decomp$vt
    }

    u_sub <- u[k:l, k:l, drop = FALSE]
    vt_sub <- vt[k, k, drop = FALSE]
    vt_k <- vt[1:k, k, drop = FALSE]
    ssign <- function(z) if (z == 0) 1 else sign(z)

    if (k == l) {
      a_qq <- ssign(u_sub[1]) * u[1:l, k:l, drop = FALSE]
      b_qq <- ssign(vt_sub[1]) * t(vt_k)
    } else {
      a_qq <- u[1:l, k:l, drop = FALSE] %*%
        (solve(u_sub) %*% fixest:::mat_sqrt(u_sub %*% t(u_sub)))
      b_qq <- fixest:::mat_sqrt(vt_sub %*% t(vt_sub)) %*%
        (solve(t(vt_sub)) %*% t(vt_k))
    }

    kronv <- kronecker(b_qq, t(a_qq))
    lambda <- kronv %*% c(theta)
    vcov_type <- attr(x$cov.scaled, "type")

    if (identical(vcov_type, "IID")) {
      vlab <- chol(tcrossprod(kronv) / nrow(X_proj))
    } else {
      Kmat <- t(kronecker(Gmat, Fmat))
      scores <- do.call(cbind, lapply(seq_len(ncol(X_proj)), function(i) {
        Z_proj * X_proj[, i]
      }))
      meat <- cluster_score_meat(scores, cluster)
      vhat <- solve(Kmat, t(solve(Kmat, meat)))
      n_adj <- nobs(x) - identical(vcov_type, "cluster")
      df_resid <- fixest:::degrees_freedom(x, "resid", stage = 1)
      vhat <- vhat * n_adj / df_resid
      vlab <- kronv %*% vhat %*% t(kronv)
    }

    r_kp <- as.numeric(t(lambda) %*% solve(vlab, lambda))
    kp_df <- n_inst - n_endo + 1L
    kp_stat <- r_kp / n_inst
    kp_p <- pchisq(kp_stat, kp_df, lower.tail = FALSE)
    list(stat = kp_stat, p = kp_p, df = kp_df,
         nondegenerate = is.finite(kp_stat), error = NA_character_)
  }, error = function(e) {
    list(stat = NA_real_, p = NA_real_, df = NA_integer_,
         nondegenerate = FALSE, error = conditionMessage(e))
  })
}

extract_sw <- function(mod, s_cols) {
  out <- data.table(share_col = s_cols, sw_F = NA_real_, sw_p = NA_real_,
                    sw_df1 = NA_integer_, sw_df2 = NA_integer_)
  fs <- tryCatch(fitstat(mod, ~ ivwald1, verbose = FALSE),
                 error = function(e) NULL)
  if (is.null(fs)) return(out)
  for (nm in names(fs)) {
    share <- sub("^ivwald1::", "", nm)
    if (!share %in% out$share_col) next
    val <- fs[[nm]]
    out[share_col == share,
        `:=`(sw_F = as.numeric(val$stat),
             sw_p = as.numeric(val$p),
             sw_df1 = as.integer(val$df1),
             sw_df2 = as.integer(val$df2))]
  }
  out
}

# --- Load panel and shares ----------------------------------------------------

panel <- qs_read(file.path(OUT, sprintf("muni_panel_ar_%s.qs2", TAX)))
setDT(panel)
SECTORS_ALL  <- attr(panel, "sectors_all")
SECTORS_KEEP <- attr(panel, "sectors_keep")
HOLDOUT      <- attr(panel, "holdout_sector")
stopifnot(length(SECTORS_ALL) > 0L, length(SECTORS_KEEP) > 0L)

share_wide <- build_share_wide(TAX, SECTORS_KEEP)
s_cols <- paste0("s_", SECTORS_KEEP)
panel <- merge(panel, share_wide, by = c("muni_id", "year"), all.x = TRUE)
for (cc in s_cols) {
  set(panel, i = which(is.na(panel[[cc]]) | !is.finite(panel[[cc]])),
      j = cc, value = 0)
}
panel <- panel[is.finite(log_gdp) & is.finite(vol_ratio)]
stopifnot(nrow(panel) > 0L)

message(sprintf("[INFO] complete-case base rows: %s; J=%d; endogenous shares=%d; holdout=%s",
                format(nrow(panel), big.mark = ","), length(SECTORS_ALL),
                length(s_cols), HOLDOUT))

z_cols  <- function(ch) paste0("Z_",  ch, "_", SECTORS_ALL)
ec_cols <- function(ch) paste0("EC_", ch, "_", SECTORS_KEEP)

ALL_NEEDED <- unique(c(unlist(lapply(CHANNELS, z_cols)),
                       unlist(lapply(CHANNELS, ec_cols)), s_cols))
missing_cols <- setdiff(ALL_NEEDED, names(panel))
if (length(missing_cols)) {
  stop("Missing expected panel columns: ", paste(missing_cols, collapse = ", "))
}

run_stack <- function(st, volume_control) {
  chans <- st$chans
  z_set <- unlist(lapply(chans, z_cols))
  ec_set <- unlist(lapply(chans, ec_cols))
  rhs <- ec_set
  if (volume_control) rhs <- c(rhs, "vol_ratio")

  sample_cols <- unique(c("log_gdp", "muni_id", "year", s_cols, z_set, rhs))
  dt <- panel[complete.cases(panel[, ..sample_cols])]
  if (!nrow(dt)) stop("No complete observations for stack ", st$id)

  fml <- as.formula(sprintf(
    "log_gdp ~ %s | muni_id + year | %s ~ %s",
    paste(rhs, collapse = " + "),
    paste(s_cols, collapse = " + "),
    paste(z_set, collapse = " + ")))

  mod <- tryCatch(
    feols(fml, data = dt, vcov = ~ muni_id, lean = FALSE),
    error = function(e) {
      message(sprintf("[WARN] fit failed [%s | vol=%s]: %s",
                      st$id, volume_control, conditionMessage(e)))
      NULL
    })

  if (is.null(mod)) {
    row <- data.table(
      taxonomy = TAX,
      stack_id = st$id,
      stack_group = st$group,
      stack_label = stack_label(chans),
      tex_label = tex_set_label(chans),
      channels = paste(chans, collapse = ","),
      spec = if (volume_control) "volctrl" else "novol",
      volume_control = volume_control,
      n_obs = NA_integer_,
      n_muni = NA_integer_,
      n_endogenous = length(s_cols),
      n_instruments = length(z_set),
      kp_rank_wald = NA_real_,
      kp_p = NA_real_,
      kp_df = NA_integer_,
      kp_nondegenerate = FALSE,
      kp_error = "fit failed",
      sw_min = NA_real_,
      sw_median = NA_real_,
      sw_max = NA_real_,
      n_sw_ge_5 = NA_integer_,
      n_sw_ge_10 = NA_integer_,
      n_sw_ge_20 = NA_integer_,
      identified_shares = NA_integer_,
      relevant_verdict = FALSE)
    for (s in s_cols) row[, (paste0("sw_F_", sub("^s_", "", s))) := NA_real_]
    return(row)
  }

  sw <- extract_sw(mod, s_cols)
  kp <- kp_rank_wald(mod, dt$muni_id)

  n_ge_5  <- sum(sw$sw_F >= 5,  na.rm = TRUE)
  n_ge_10 <- sum(sw$sw_F >= 10, na.rm = TRUE)
  n_ge_20 <- sum(sw$sw_F >= 20, na.rm = TRUE)
  kp_sig <- isTRUE(is.finite(kp$p) && kp$p < 0.05)
  relevant <- (isTRUE(kp$nondegenerate) && kp_sig) || n_ge_10 > 0L

  row <- data.table(
    taxonomy = TAX,
    stack_id = st$id,
    stack_group = st$group,
    stack_label = stack_label(chans),
    tex_label = tex_set_label(chans),
    channels = paste(chans, collapse = ","),
    spec = if (volume_control) "volctrl" else "novol",
    volume_control = volume_control,
    n_obs = nobs(mod),
    n_muni = uniqueN(dt$muni_id),
    n_endogenous = length(s_cols),
    n_instruments = length(z_set),
    kp_rank_wald = kp$stat,
    kp_p = kp$p,
    kp_df = kp$df,
    kp_nondegenerate = kp$nondegenerate,
    kp_error = kp$error,
    sw_min = suppressWarnings(min(sw$sw_F, na.rm = TRUE)),
    sw_median = suppressWarnings(median(sw$sw_F, na.rm = TRUE)),
    sw_max = suppressWarnings(max(sw$sw_F, na.rm = TRUE)),
    n_sw_ge_5 = n_ge_5,
    n_sw_ge_10 = n_ge_10,
    n_sw_ge_20 = n_ge_20,
    identified_shares = n_ge_10,
    relevant_verdict = relevant)
  if (!is.finite(row$sw_min)) row[, sw_min := NA_real_]
  if (!is.finite(row$sw_median)) row[, sw_median := NA_real_]
  if (!is.finite(row$sw_max)) row[, sw_max := NA_real_]

  for (s in s_cols) {
    sec <- sub("^s_", "", s)
    row[, (paste0("sw_F_", sec)) := sw[share_col == s, sw_F]]
    row[, (paste0("sw_p_", sec)) := sw[share_col == s, sw_p]]
  }
  row
}

# --- Run all stacks -----------------------------------------------------------

rows <- list()
idx <- 1L
for (st in STACKS) {
  for (vc in c(FALSE, TRUE)) {
    message(sprintf("[INFO] fitting %-12s | volume_control=%s",
                    st$id, vc))
    rows[[idx]] <- run_stack(st, vc)
    idx <- idx + 1L
    gc(verbose = FALSE)
  }
}

res <- rbindlist(rows, fill = TRUE)
stack_order <- vapply(STACKS, `[[`, character(1), "id")
res[, stack_order := match(stack_id, stack_order)]
setorder(res, stack_order, volume_control)
res[, stack_order := NULL]

csv_path <- file.path(OUT, sprintf("wide_first_stage_%s.csv", TAX))
fwrite(res, csv_path)

message("\n[RESULT] B8 wide-form first stage (volume-control verdict rows):")
print(res[volume_control == TRUE,
          .(stack_label, n_instruments, kp = round(kp_rank_wald, 3),
            kp_p = signif(kp_p, 3), sw_min = round(sw_min, 2),
            sw_max = round(sw_max, 2), identified_shares,
            relevant_verdict)])

# --- Bare-tabular .tex (INV-13) ---------------------------------------------

build_tex <- function(rd) {
  share_headers <- tex_escape(sub("^s_", "", s_cols))
  colspec <- paste0("@{}ll", paste(rep("c", length(s_cols)), collapse = ""),
                    "cccc@{}")
  header <- paste0("Stack & Spec & ",
                   paste(share_headers, collapse = " & "),
                   " & KP & ID & Verdict \\\\")
  lines <- c(sprintf("\\begin{tabular}{%s}", colspec),
             "\\toprule", header, "\\midrule")
  for (vc in c(TRUE, FALSE)) {
    subset_dt <- rd[volume_control == vc]
    panel_lab <- if (vc) "Panel A: Volume control" else "Panel B: No volume control"
    lines <- c(lines, sprintf("\\multicolumn{%d}{@{}l}{\\textit{%s}} \\\\",
                              4L + length(s_cols), panel_lab))
    lines <- c(lines, "\\midrule")
    for (i in seq_len(nrow(subset_dt))) {
      r <- subset_dt[i]
      f_cells <- vapply(s_cols, function(s) {
        sec <- sub("^s_", "", s)
        fmt_n(r[[paste0("sw_F_", sec)]], 2L)
      }, character(1))
      lines <- c(lines, paste0(
        r$tex_label, " & ",
        if (r$volume_control) "Vol." else "No vol.", " & ",
        paste(f_cells, collapse = " & "), " & ",
        fmt_n(r$kp_rank_wald, 2L), " & ",
        r$identified_shares, "/", r$n_endogenous, " & ",
        if (isTRUE(r$relevant_verdict)) "Yes" else "No",
        " \\\\"))
    }
    if (vc) lines <- c(lines, "\\midrule")
  }
  c(lines, "\\bottomrule", "\\end{tabular}")
}

tex_path <- file.path(OUT, sprintf("wide_first_stage_%s.tex", TAX))
writeLines(build_tex(res), tex_path)

message(sprintf("[INFO] wrote wide_first_stage_%s.{csv,tex}", TAX))
message(sprintf("[INFO] %s | B8 done.", Sys.time()))
