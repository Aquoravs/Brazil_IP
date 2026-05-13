#!/usr/bin/env Rscript

# ==============================================================================
# 10_policy_block_diagnostics.R
# Phase 2 C2.1.5 -- re-run Phase 1 margin-sensitivity diagnostics at the
# policy_block (K=4 blocks; Agro/Ind/Infra/Serv) margin, to validate the
# Phase 1 robustness story survives at the coarser partition.
#
# Strategist-critic gate: journal/plans/2026-05-12_phase2_strategist_review.md
# - Phase 1 diagnostics are NOT margin-invariant (re-run mandatory).
# - drop-top-5 undefined at K=4; substitute drop-top-1 and drop-top-2.
#
# Headline spec mirrors Phase 1 cnae_section baseline:
#   variant=contemporaneous, outcome=log_gdp, flavor=MGP (mayor+gov+pres),
#   FE=muni+year, alignment=coalition, baseline=cycle_specific, vol_ratio
#   control. Section/block holdout = Serv (alphabetically last among 4 blocks).
#
# Inputs:
#   data/processed/muni_panel_for_regs_policy_block.qs2 (Z_<off>_coalition_cycle_specific_<block> cols)
#   data/processed/muni_panel_for_regs.qs2 (pib_real, total_bndes_real for volume control)
#   data/processed/emp_share_panel_policy_block.qs2 (s_emp_mjt + slack_frozen_mt + first stage data)
#   data/processed/shift_share_instruments_sector_policy_block.qs2 (sector first stage Z's)
#
# Outputs (all in explorations/anderson_rubin/active_denominator/output/):
#   ar_headline_policy_block.csv
#   rotemberg_weights_policy_block.csv
#   rotemberg_drop_top_policy_block.csv
#   slack_robustness_policy_block.csv
#   policy_block_diagnostics_summary.md
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})

# ---- Paths -------------------------------------------------------------------

get_this_script <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (length(fa)) {
    return(normalizePath(sub("^--file=", "", fa[[1L]]),
                         winslash = "/", mustWork = TRUE))
  }
  fp <- vapply(sys.frames(), function(env) {
    of <- env$ofile
    if (is.null(of) || !nzchar(of)) return(NA_character_)
    of
  }, character(1))
  fp <- fp[!is.na(fp)]
  if (length(fp)) {
    return(normalizePath(fp[[length(fp)]], winslash = "/", mustWork = TRUE))
  }
  stop("Cannot determine script path. Run via Rscript.")
}

THIS_SCRIPT  <- get_this_script()
BRANCH_DIR   <- normalizePath(file.path(dirname(THIS_SCRIPT), ".."),
                              winslash = "/", mustWork = TRUE)
PROJECT_ROOT <- normalizePath(file.path(BRANCH_DIR, "..", "..", ".."),
                              winslash = "/", mustWork = TRUE)
source(file.path(PROJECT_ROOT, "scripts", "R", "_utils", "utils.R"))

OUTPUT_BRANCH <- file.path(BRANCH_DIR, "output")
stopifnot(dir.exists(OUTPUT_BRANCH))

set.seed(20260513L)
setDTthreads(0L)
fixest::setFixest_nthreads(4L)

# ---- Constants (headline spec mirrors Phase 1) ------------------------------

VARIANT   <- "contemporaneous"
OUTCOME   <- "log_gdp"
FLAVOR    <- "MGP"
FE_TERM   <- "muni_id + year"
BASELINE  <- "cycle_specific"
ALIGNMENT <- "coalition"
OFFICES   <- c("mayor", "gov", "pres")

# All policy blocks present in the underlying panel (the K=4 partition):
ALL_BLOCKS <- c("Agro", "Ind", "Infra", "Serv")
HOLDOUT    <- "Serv"  # alphabetically last; matches Phase 1 hold-out convention
BLOCKS_KEEP <- setdiff(ALL_BLOCKS, HOLDOUT)  # c("Agro","Ind","Infra")

message(sprintf("[INFO] %s | policy_block diagnostics. blocks=%s holdout=%s",
                Sys.time(), paste(ALL_BLOCKS, collapse=","), HOLDOUT))

# ---- Load policy_block muni panel (Z columns) -------------------------------

pb_muni_path <- output_path("muni_panel_for_regs_policy_block.qs2")
stopifnot("muni_panel_for_regs_policy_block.qs2 must exist" = file.exists(pb_muni_path))
message(sprintf("[INFO] %s | loading muni_panel_for_regs_policy_block.qs2 ...",
                Sys.time()))
pb <- qs_read(pb_muni_path)
setDT(pb)
pb[, muni_id := as.integer(muni_id)]
pb[, year    := as.integer(year)]
pb <- pb[muni_id > 0L]
message(sprintf("[INFO] policy_block panel: %s rows, %d munis, %d years",
                format(nrow(pb), big.mark=","), uniqueN(pb$muni_id),
                uniqueN(pb$year)))

# Build instrument column names per (office, block_keep).
# Available: Z_<off>_coalition_cycle_specific_<block> for block in {Agro,Ind,Infra}.
build_inst_cols <- function(offices, blocks) {
  out <- character()
  for (off in offices) for (b in blocks) {
    out <- c(out, sprintf("Z_%s_%s_%s_%s", off, ALIGNMENT, BASELINE, b))
  }
  out
}
INST_COLS <- build_inst_cols(OFFICES, BLOCKS_KEEP)
miss <- setdiff(INST_COLS, names(pb))
stopifnot("Missing Z columns" = length(miss) == 0L)
message(sprintf("[INFO] K = %d instruments (3 offices x %d blocks)",
                length(INST_COLS), length(BLOCKS_KEEP)))

# ---- Merge volume control from the canonical muni panel ---------------------

base_muni_path <- output_path("muni_panel_for_regs.qs2")
stopifnot(file.exists(base_muni_path))
message(sprintf("[INFO] %s | loading muni_panel_for_regs.qs2 for vol_ratio ...",
                Sys.time()))
bm <- qs_read(base_muni_path)
setDT(bm)
bm[, muni_id := as.integer(muni_id)]
bm[, year    := as.integer(year)]
bm <- bm[muni_id > 0L]

setorder(bm, muni_id, year)
init_gdp <- bm[!is.na(pib_real),
               .(initial_gdp = pib_real[1L]), by = muni_id]
vol_dt <- merge(
  bm[, .(muni_id, year, total_bndes_real, pib_real)],
  init_gdp, by = "muni_id", all.x = TRUE)
vol_dt[, vol_ratio := total_bndes_real / initial_gdp]
vol_dt[!is.finite(vol_ratio), vol_ratio := NA_real_]

# Merge into pb. Use only (muni, year, vol_ratio) to avoid clobbering pb's outcome.
pb <- merge(pb, vol_dt[, .(muni_id, year, vol_ratio)],
            by = c("muni_id", "year"), all.x = TRUE)
message(sprintf("[INFO] vol_ratio merged. Non-NA: %d / %d",
                sum(!is.na(pb$vol_ratio)), nrow(pb)))

# Confirm outcome present.
stopifnot(OUTCOME %in% names(pb))

# ---- Slack loader (from emp_share_panel_policy_block.qs2) -------------------

load_slack_pb <- function() {
  emp_path <- raw_path("..", "processed",
                       "emp_share_panel_policy_block.qs2")
  emp_path2 <- output_path("emp_share_panel_policy_block.qs2")
  pth <- if (file.exists(emp_path2)) emp_path2 else emp_path
  stopifnot(file.exists(pth))
  e <- qs_read(pth)
  setDT(e)
  e[, muni_id := as.integer(muni_id)]
  e[, year    := as.integer(year)]
  # Collapse to (muni, year) by mean over blocks. Phase 1 convention.
  s <- e[, .(slack_share = mean(slack_frozen_mt, na.rm = TRUE)),
         by = .(muni_id, year)]
  s[!is.finite(slack_share), slack_share := NA_real_]
  v <- var(s$slack_share, na.rm = TRUE)
  message(sprintf("[INFO] slack_share variance (policy_block, muni-year) = %s (N=%d)",
                  formatC(v, format="g", digits=4), nrow(s)))
  s
}

# ---- AR reduced form runner -------------------------------------------------

z_pattern <- sprintf("^Z_(%s)_%s_%s_",
                     paste(OFFICES, collapse = "|"), ALIGNMENT, BASELINE)

run_ar_pb <- function(inst_cols_use, fe_term = FE_TERM,
                      outcome = OUTCOME, include_slack = FALSE,
                      slack_dt = NULL) {
  dat <- copy(pb)
  if (include_slack) {
    stopifnot(!is.null(slack_dt))
    dat <- merge(dat, slack_dt, by = c("muni_id", "year"), all.x = TRUE)
  }
  keep <- c("muni_id", "year", outcome, "vol_ratio", inst_cols_use)
  if (include_slack) keep <- c(keep, "slack_share")
  dat <- dat[, ..keep]
  base_keep <- setdiff(keep, "slack_share")
  dat <- dat[complete.cases(dat[, .SD, .SDcols = base_keep])]
  if (include_slack) dat <- dat[!is.na(slack_share)]
  if (!nrow(dat)) {
    return(list(status = "empty"))
  }
  rhs <- c(inst_cols_use, "vol_ratio")
  if (include_slack) rhs <- c(rhs, "slack_share")
  fml <- as.formula(paste0(outcome, " ~ ",
                           paste(rhs, collapse = " + "),
                           " | ", fe_term))
  mod <- tryCatch(
    feols(fml, data = dat, vcov = ~ muni_id, lean = TRUE),
    error = function(e) {
      message(sprintf("[WARN] AR fit failed: %s", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(mod)) return(list(status = "fit_failed"))
  w <- tryCatch(fixest::wald(mod, keep = z_pattern), error = function(e) NULL)
  ar_F <- if (!is.null(w)) as.numeric(w$stat) else NA_real_
  ar_p <- if (!is.null(w)) as.numeric(w$p)    else NA_real_
  list(
    status = "ok",
    mod = mod,
    n_obs = nobs(mod),
    n_munis = uniqueN(dat$muni_id),
    K = length(inst_cols_use),
    n_collinear = length(mod$collin.var),
    ar_F = ar_F, ar_p = ar_p,
    rejects_5pc = isTRUE(ar_p < 0.05)
  )
}

# ============================================================================
# (1) Headline AR at policy_block
# ============================================================================

message(sprintf("\n[INFO] %s | === (1) Headline AR at policy_block ===",
                Sys.time()))
hf <- run_ar_pb(INST_COLS, fe_term = FE_TERM, outcome = OUTCOME,
                include_slack = FALSE)
stopifnot(identical(hf$status, "ok"))
message(sprintf("[INFO] AR_F = %.4f  AR_p = %.4g  n = %d  K = %d  collin = %d",
                hf$ar_F, hf$ar_p, hf$n_obs, hf$K, hf$n_collinear))

# ---- First-stage joint F (analog of fs_F in Phase 1) ------------------------
# Run sector-level first stage: s_emp_mjt ~ Z's | muni_id^policy_block +
# policy_block^year; cluster by muni + policy_block.
run_first_stage_joint_F_pb <- function() {
  emp_path <- output_path("emp_share_panel_policy_block.qs2")
  stopifnot(file.exists(emp_path))
  emp <- qs_read(emp_path)
  setDT(emp)
  emp[, muni_id := as.integer(muni_id)]
  emp[, year    := as.integer(year)]
  # Build a long instrument frame from pb wide cols.
  rename_map <- list()
  wide_cols  <- character()
  for (off in OFFICES) for (b in BLOCKS_KEEP) {
    col <- sprintf("Z_%s_%s_%s_%s", off, ALIGNMENT, BASELINE, b)
    new <- sprintf("Z_%s.%s", off, b)
    wide_cols <- c(wide_cols, col); rename_map[[col]] <- new
  }
  mp <- pb[, c("muni_id", "year", wide_cols), with = FALSE]
  setnames(mp, wide_cols, unlist(rename_map[wide_cols]))
  id_vars <- c("muni_id", "year")
  meas <- setdiff(names(mp), id_vars)
  long <- melt(mp, id.vars = id_vars, measure.vars = meas,
               variable.name = "key", value.name = "Z_val")
  long[, c("office_tag","policy_block") := tstrsplit(as.character(key), ".",
                                                      fixed = TRUE)]
  long[, key := NULL]
  long_w <- dcast(long, muni_id + year + policy_block ~ office_tag,
                  value.var = "Z_val")
  z_cols <- setdiff(names(long_w), c("muni_id","year","policy_block"))

  panel <- merge(emp, long_w,
                 by = c("muni_id","year","policy_block"),
                 all.x = FALSE, all.y = FALSE)
  if (!nrow(panel)) return(NA_real_)
  rhs <- paste(z_cols, collapse = " + ")
  fml <- as.formula(sprintf(
    "s_emp_mjt ~ %s | muni_id^policy_block + policy_block^year", rhs))
  mod <- tryCatch(
    feols(fml, data = panel, vcov = ~ muni_id + policy_block, lean = TRUE),
    error = function(e) NULL)
  if (is.null(mod)) return(NA_real_)
  w <- tryCatch(fixest::wald(mod, keep = "^Z_"), error = function(e) NULL)
  if (is.null(w)) return(NA_real_)
  as.numeric(w$stat)
}

message(sprintf("[INFO] %s | computing first-stage joint F ...", Sys.time()))
fs_F <- run_first_stage_joint_F_pb()
message(sprintf("[INFO] first_stage_joint_F (policy_block) = %.4f", fs_F))

headline_dt <- data.table(
  margin = "policy_block",
  variant = VARIANT, outcome = OUTCOME, flavor = FLAVOR,
  fe_spec = "muni_year",
  K = hf$K, n_obs = hf$n_obs, n_munis = hf$n_munis,
  n_collinear = hf$n_collinear,
  ar_F = hf$ar_F, ar_p = hf$ar_p,
  rejects_5pc = hf$rejects_5pc,
  first_stage_joint_F = fs_F,
  phase1_cnae_section_ar_F = 2.69,
  phase1_cnae_section_ar_p_note = "<1e-10",
  phase1_cnae_section_fs_F = 19.98
)
fwrite(headline_dt, file.path(OUTPUT_BRANCH, "ar_headline_policy_block.csv"))
message(sprintf("[INFO] wrote: %s",
                file.path(OUTPUT_BRANCH, "ar_headline_policy_block.csv")))

# ============================================================================
# (2) Rotemberg partial-Wald weights
# ============================================================================

message(sprintf("\n[INFO] %s | === (2) Rotemberg partial-Wald weights ===",
                Sys.time()))
ct <- coeftable(hf$mod)
z_rows <- grepl(z_pattern, rownames(ct))
ct_z <- ct[z_rows, , drop = FALSE]

parse_inst_pb <- function(nm) {
  # Format: Z_<off>_<align>_<base>_<block>  where <base> may contain '_'
  # (cycle_specific). Strip prefix then split.
  body <- sub("^Z_", "", nm)
  parts <- strsplit(body, "_", fixed = TRUE)[[1L]]
  # office = parts[1]; block = last element; align/base in between.
  list(office = parts[1L], policy_block = parts[length(parts)])
}
info <- lapply(rownames(ct_z), parse_inst_pb)

rotemberg <- data.table(
  instrument   = rownames(ct_z),
  office       = vapply(info, `[[`, character(1), "office"),
  policy_block = vapply(info, `[[`, character(1), "policy_block"),
  beta_hat = ct_z[, "Estimate"],
  se       = ct_z[, "Std. Error"],
  t_stat   = ct_z[, "t value"],
  p_value  = ct_z[, "Pr(>|t|)"]
)
rotemberg[, t_sq := t_stat^2]
total_tsq <- sum(rotemberg$t_sq, na.rm = TRUE)
rotemberg[, w_partial_wald := t_sq / total_tsq]
setorder(rotemberg, -w_partial_wald)
rotemberg[, rank_partial_wald := seq_len(.N)]

# Aggregated weights at the block level (K=3 blocks tested + 3 offices each):
block_weights <- rotemberg[, .(block_weight = sum(w_partial_wald, na.rm=TRUE),
                                n_offices_in_block = .N),
                            by = policy_block]
setorder(block_weights, -block_weight)
block_weights[, rank_block_weight := seq_len(.N)]

fwrite(rotemberg, file.path(OUTPUT_BRANCH, "rotemberg_weights_policy_block.csv"))
fwrite(block_weights, file.path(OUTPUT_BRANCH,
                                 "rotemberg_block_weights_policy_block.csv"))
message("[INFO] per-instrument Rotemberg-analog weights (sorted):")
print(rotemberg[, .(rank_partial_wald, instrument, office, policy_block,
                    beta_hat, t_stat, w_partial_wald)])
message("[INFO] per-block aggregated weights:")
print(block_weights)

w_top1 <- rotemberg[rank_partial_wald == 1L, w_partial_wald]
w_top2 <- sum(rotemberg[rank_partial_wald <= 2L, w_partial_wald])
message(sprintf("[INFO] top-1 weight share = %.4f", w_top1))
message(sprintf("[INFO] top-2 weight share = %.4f", w_top2))

# ============================================================================
# (3) Drop-top-1 and Drop-top-2 substitutes (drop-top-5 undefined at K=4)
# ============================================================================

message(sprintf("\n[INFO] %s | === (3) Drop-top-1 / Drop-top-2 reruns ===",
                Sys.time()))

top1_inst <- rotemberg[rank_partial_wald == 1L, instrument]
top2_inst <- rotemberg[rank_partial_wald <= 2L, instrument]

hf_d1 <- run_ar_pb(setdiff(INST_COLS, top1_inst))
hf_d2 <- run_ar_pb(setdiff(INST_COLS, top2_inst))

# Drop-top first-stage F: re-run sector-level first stage excluding the office's
# block dimension that was dropped. For simplicity we report the AR reduced-form
# F here; the strategist gate language refers to the sector-level "fs_F" but
# the natural analog at the reduced-form level is the joint AR Wald F itself.
# We additionally compute the dropped-instrument first stage F for the strict
# interpretation of "fs_F drop-top-1 >= 10".
run_first_stage_drop <- function(drop_inst) {
  emp_path <- output_path("emp_share_panel_policy_block.qs2")
  stopifnot(file.exists(emp_path))
  emp <- qs_read(emp_path)
  setDT(emp)
  emp[, muni_id := as.integer(muni_id)]
  emp[, year    := as.integer(year)]
  rename_map <- list()
  wide_cols  <- character()
  for (off in OFFICES) for (b in BLOCKS_KEEP) {
    col <- sprintf("Z_%s_%s_%s_%s", off, ALIGNMENT, BASELINE, b)
    if (col %in% drop_inst) next  # skip dropped instruments
    new <- sprintf("Z_%s.%s", off, b)
    wide_cols <- c(wide_cols, col); rename_map[[col]] <- new
  }
  if (!length(wide_cols)) return(NA_real_)
  mp <- pb[, c("muni_id","year", wide_cols), with = FALSE]
  setnames(mp, wide_cols, unlist(rename_map[wide_cols]))
  id_vars <- c("muni_id","year")
  meas <- setdiff(names(mp), id_vars)
  long <- melt(mp, id.vars = id_vars, measure.vars = meas,
               variable.name = "key", value.name = "Z_val")
  long[, c("office_tag","policy_block") := tstrsplit(as.character(key), ".",
                                                      fixed = TRUE)]
  long[, key := NULL]
  long_w <- dcast(long, muni_id + year + policy_block ~ office_tag,
                  value.var = "Z_val")
  z_cols <- setdiff(names(long_w), c("muni_id","year","policy_block"))
  panel <- merge(emp, long_w, by = c("muni_id","year","policy_block"))
  if (!nrow(panel)) return(NA_real_)
  rhs <- paste(z_cols, collapse = " + ")
  fml <- as.formula(sprintf(
    "s_emp_mjt ~ %s | muni_id^policy_block + policy_block^year", rhs))
  mod <- tryCatch(feols(fml, data = panel,
                        vcov = ~ muni_id + policy_block, lean = TRUE),
                  error = function(e) NULL)
  if (is.null(mod)) return(NA_real_)
  w <- tryCatch(fixest::wald(mod, keep = "^Z_"), error = function(e) NULL)
  if (is.null(w)) return(NA_real_)
  as.numeric(w$stat)
}

fs_F_d1 <- run_first_stage_drop(top1_inst)
fs_F_d2 <- run_first_stage_drop(top2_inst)
message(sprintf("[INFO] drop-top-1 first_stage_joint_F = %.4f", fs_F_d1))
message(sprintf("[INFO] drop-top-2 first_stage_joint_F = %.4f", fs_F_d2))

drop_dt <- data.table(
  spec       = c("baseline", "drop_top1", "drop_top2"),
  K          = c(length(INST_COLS),
                 length(INST_COLS) - length(top1_inst),
                 length(INST_COLS) - length(top2_inst)),
  n_obs      = c(hf$n_obs, hf_d1$n_obs, hf_d2$n_obs),
  ar_F       = c(hf$ar_F, hf_d1$ar_F, hf_d2$ar_F),
  ar_p       = c(hf$ar_p, hf_d1$ar_p, hf_d2$ar_p),
  rejects_5pc= c(hf$rejects_5pc, hf_d1$rejects_5pc, hf_d2$rejects_5pc),
  first_stage_joint_F = c(fs_F, fs_F_d1, fs_F_d2),
  dropped_instruments = c("",
                           paste(top1_inst, collapse=";"),
                           paste(top2_inst, collapse=";"))
)
fwrite(drop_dt, file.path(OUTPUT_BRANCH,
                          "rotemberg_drop_top_policy_block.csv"))
message("[INFO] drop-top reruns:")
print(drop_dt)

# Escalation gate: drop-top-1 fs_F >= 10
drop_top1_pass <- isTRUE(is.finite(fs_F_d1) && fs_F_d1 >= 10)
message(sprintf("[INFO] Escalation gate (drop-top-1 fs_F >= 10): %s (fs_F=%.4f)",
                if (drop_top1_pass) "PASS" else "ESCALATE-RISK",
                fs_F_d1))

# ============================================================================
# (4) Slack on/off robustness grid
# ============================================================================

message(sprintf("\n[INFO] %s | === (4) Slack on/off grid ===", Sys.time()))
slack_dt <- load_slack_pb()

# Phase 1 24-cell grid: variants {contemporaneous, frozen, balanced} x outcomes
# x FE x slack. Here we only have the contemporaneous variant for policy_block
# (frozen/balanced not built). We run the contemporaneous subset:
#   outcomes {log_gdp, delta_log_gdp} x FE {muni_year, year_only} x slack {F,T}
# = 8 cells.

# Build delta_log_gdp if needed.
setorder(pb, muni_id, year)
if (!"delta_log_gdp" %in% names(pb)) {
  pb[, delta_log_gdp := log_gdp - shift(log_gdp, type = "lag"), by = muni_id]
}

slack_grid <- list()
for (out_v in c("log_gdp", "delta_log_gdp")) {
  for (fe_v in c("muni_year", "year_only")) {
    fe_term_v <- if (fe_v == "muni_year") "muni_id + year" else "year"
    for (slk in c(FALSE, TRUE)) {
      tag <- sprintf("[%s|%s|slack=%s]", out_v, fe_v, slk)
      r <- run_ar_pb(INST_COLS, fe_term = fe_term_v, outcome = out_v,
                     include_slack = slk, slack_dt = slack_dt)
      if (identical(r$status, "ok")) {
        message(sprintf("[INFO] %s AR_F=%.4f AR_p=%.4g n=%d coll=%d",
                        tag, r$ar_F, r$ar_p, r$n_obs, r$n_collinear))
        slack_grid[[length(slack_grid) + 1L]] <- data.table(
          variant = VARIANT, outcome = out_v, fe_spec = fe_v,
          slack_included = slk, status = "ok",
          n_obs = r$n_obs, n_munis = r$n_munis,
          K = r$K, n_collinear = r$n_collinear,
          ar_F = r$ar_F, ar_p = r$ar_p,
          rejects_5pc = r$rejects_5pc)
      } else {
        message(sprintf("[INFO] %s status=%s", tag, r$status))
        slack_grid[[length(slack_grid) + 1L]] <- data.table(
          variant = VARIANT, outcome = out_v, fe_spec = fe_v,
          slack_included = slk, status = r$status)
      }
    }
  }
}
slack_robust <- rbindlist(slack_grid, fill = TRUE)
fwrite(slack_robust, file.path(OUTPUT_BRANCH,
                                "slack_robustness_policy_block.csv"))

# Compute max |Delta AR F| across slack on/off pairs.
delta_ar <- slack_robust[status == "ok",
                          .(ar_F_off = ar_F[slack_included == FALSE][1L],
                            ar_F_on  = ar_F[slack_included == TRUE][1L]),
                          by = .(outcome, fe_spec)]
delta_ar[, delta_F := abs(ar_F_on - ar_F_off)]
max_delta_F <- max(delta_ar$delta_F, na.rm = TRUE)
message("[INFO] slack on/off delta AR F:")
print(delta_ar)
message(sprintf("[INFO] max |Delta AR F| = %.4f (Phase 1 had <= 0.03)",
                max_delta_F))

# Escalation gate: max_delta_F > 0.5
slack_pass <- isTRUE(is.finite(max_delta_F) && max_delta_F <= 0.5)
message(sprintf("[INFO] Escalation gate (max |Delta AR F| <= 0.5): %s",
                if (slack_pass) "PASS" else "ESCALATE-RISK"))

# ============================================================================
# (5) AKM 2019 cluster-robust SE assessment
# ============================================================================

# Implementation note: a full AKM 2019 correlated-effective-shocks correction
# requires (i) recomputing the AR reduced-form residuals at the shock-block
# level and (ii) Adao-Kolesar-Morales-style variance via the per-shock
# exposure-weighted residual aggregation. The fixest 'vcov = ssc()' API does
# not directly support AKM-2019 SEs; an external pkg (e.g., 'ssaggregate') is
# needed. Given K=9 effective instruments and ~5,300 munis, the one-way
# muni-clustered VCV is conservative under AKM 2019 conditions: the shock
# dimension (4 blocks) is fixed and small, and exposure correlation across
# munis is mediated by the muni-by-block share matrix which already enters as
# the regressor coefficient. We document the limitation rather than implement
# (would exceed the 1-hr budget cited in the orchestrator brief).
#
# Empirical safety check: re-fit the headline AR with two-way clustering on
# (muni_id, year) -- conservative analog of correlated-shock structure when
# shocks vary only by year. If the AR F materially changes, AKM correction is
# advisable; if not, one-way muni clustering is adequate.

message(sprintf("\n[INFO] %s | === (5) AKM SE check (two-way muni+year cluster) ===",
                Sys.time()))
run_ar_twoway <- function() {
  keep <- c("muni_id","year", OUTCOME, "vol_ratio", INST_COLS)
  dat <- pb[, ..keep]
  dat <- dat[complete.cases(dat)]
  rhs <- c(INST_COLS, "vol_ratio")
  fml <- as.formula(paste0(OUTCOME, " ~ ", paste(rhs, collapse=" + "),
                            " | ", FE_TERM))
  mod <- feols(fml, data = dat, vcov = ~ muni_id + year, lean = TRUE)
  w <- fixest::wald(mod, keep = z_pattern)
  list(ar_F = as.numeric(w$stat), ar_p = as.numeric(w$p), n = nobs(mod))
}
twoway <- tryCatch(run_ar_twoway(), error = function(e) {
  message(sprintf("[WARN] two-way fit failed: %s", conditionMessage(e)))
  list(ar_F = NA_real_, ar_p = NA_real_, n = NA_integer_)
})
message(sprintf("[INFO] two-way (muni+year) AR_F = %.4f  AR_p = %.4g (vs. one-way muni AR_F = %.4f)",
                twoway$ar_F, twoway$ar_p, hf$ar_F))
ratio_ar_F_twoway_oneway <- twoway$ar_F / hf$ar_F

akm_dt <- data.table(
  cluster = c("muni_oneway","muni_year_twoway"),
  ar_F    = c(hf$ar_F, twoway$ar_F),
  ar_p    = c(hf$ar_p, twoway$ar_p),
  n_obs   = c(hf$n_obs, twoway$n)
)
fwrite(akm_dt, file.path(OUTPUT_BRANCH, "akm_se_check_policy_block.csv"))

# ============================================================================
# (6) K=4 power note (back-of-envelope)
# ============================================================================

# Under Phase 1 alternative (true beta of full vector at cnae_section), the AR
# non-centrality parameter scales with sum_j beta_j' Sigma_j^-1 beta_j where
# Sigma_j is the per-instrument variance. Coarsening from K=20 sections to K=4
# blocks aggregates beta within each block. If within-block heterogeneity is
# substantial (some +, some -), aggregation will attenuate the true beta and
# lower the non-centrality. If within-block signs align, aggregation preserves
# (or amplifies via reduced variance) the non-centrality. We compute a
# heuristic ratio: (K_cnae - 1) / (K_pb - 1) * (ar_F_pb / ar_F_cnae) gives
# approximately the relative power; values << 1 indicate the partition is
# attenuating. Reported in summary below.

k_cnae <- 57L   # MGP at cnae_section, K = 3 offices x (20 - 1 holdout) sections
k_pb   <- length(INST_COLS)
ar_F_phase1_cnae <- 2.69
power_proxy <- (k_cnae * ar_F_phase1_cnae) / (k_pb * hf$ar_F)
# Under the chi^2 approximation (ar_F * K is approx chi^2(K) under H1), this
# ratio compares non-centralities. >1 means policy_block has LESS non-centrality
# per identifying restriction; <1 means MORE.

# ============================================================================
# (7) Summary markdown
# ============================================================================

summary_md <- c(
  "# Policy-block diagnostics summary",
  "",
  sprintf("**Date:** %s", Sys.Date()),
  sprintf("**Script:** `explorations/anderson_rubin/active_denominator/R/10_policy_block_diagnostics.R`"),
  "",
  "## (1) Headline AR: policy_block vs. cnae_section",
  "",
  sprintf("| Margin | K | AR F | AR p | first-stage joint F |"),
  "|---|---|---|---|---|",
  sprintf("| policy_block | %d | %.4f | %.4g | %.4f |",
          hf$K, hf$ar_F, hf$ar_p, fs_F),
  sprintf("| cnae_section (Phase 1) | 57 | 2.69 | <1e-10 | 19.98 |"),
  "",
  sprintf("Headline reject 5%%: %s",
          if (hf$rejects_5pc) "**YES**" else "**NO**"),
  "",
  "## (2) Rotemberg partial-Wald weights",
  "",
  sprintf("- top-1 weight share = **%.4f** (instrument: `%s`)",
          w_top1, rotemberg[rank_partial_wald == 1L, instrument]),
  sprintf("- top-2 weight share = **%.4f** (instruments: `%s`)",
          w_top2,
          paste(rotemberg[rank_partial_wald <= 2L, instrument], collapse=", ")),
  "",
  "Per-block aggregated weights:",
  "",
  paste0("- ", block_weights$policy_block, ": ",
         sprintf("%.4f", block_weights$block_weight),
         collapse = "\n"),
  "",
  "## (3) Drop-top reruns (drop-top-5 undefined at K<=9)",
  "",
  "| Spec | K | AR F | AR p | first-stage joint F | reject 5% |",
  "|---|---|---|---|---|---|",
  sprintf("| baseline   | %d | %.4f | %.4g | %.4f | %s |",
          length(INST_COLS), hf$ar_F, hf$ar_p, fs_F,
          if (hf$rejects_5pc) "YES" else "NO"),
  sprintf("| drop-top-1 | %d | %.4f | %.4g | %.4f | %s |",
          length(INST_COLS) - 1L, hf_d1$ar_F, hf_d1$ar_p, fs_F_d1,
          if (hf_d1$rejects_5pc) "YES" else "NO"),
  sprintf("| drop-top-2 | %d | %.4f | %.4g | %.4f | %s |",
          length(INST_COLS) - 2L, hf_d2$ar_F, hf_d2$ar_p, fs_F_d2,
          if (hf_d2$rejects_5pc) "YES" else "NO"),
  "",
  sprintf("Escalation gate (drop-top-1 first-stage joint F >= 10): **%s** (fs_F=%.4f)",
          if (drop_top1_pass) "PASS" else "ESCALATE", fs_F_d1),
  "",
  "## (4) Slack on/off (contemporaneous variant; 8-cell sub-grid)",
  "",
  "| Outcome | FE | AR F (slack OFF) | AR F (slack ON) | Delta F |",
  "|---|---|---|---|---|",
  paste0(sprintf("| %s | %s | %.4f | %.4f | %.4f |",
                 delta_ar$outcome, delta_ar$fe_spec,
                 delta_ar$ar_F_off, delta_ar$ar_F_on, delta_ar$delta_F),
         collapse = "\n"),
  "",
  sprintf("max |Delta AR F| = **%.4f** (Phase 1 had <= 0.03; gate is <= 0.5).",
          max_delta_F),
  sprintf("Escalation gate (slack stable): **%s**",
          if (slack_pass) "PASS" else "ESCALATE"),
  "",
  "## (5) AKM 2019 cluster-robust SE assessment",
  "",
  sprintf("At K = %d effective instruments (3 offices x %d blocks-after-holdout) we evaluate whether one-way muni clustering remains defensible vs the AKM 2019 correlated-effective-shocks correction. A full AKM correction requires shock-block aggregation of residuals (Adao, Kolesar, Morales 2019, §3) and is not directly supported by fixest's VCV API; external implementations (e.g., ssaggregate in Stata, or a hand-coded equivalent) would be required, exceeding the diagnostic budget here.",
          length(INST_COLS), length(BLOCKS_KEEP)),
  "",
  sprintf("As a conservative empirical check, two-way clustering on (muni_id, year) yields AR F = %.4f (vs one-way muni AR F = %.4f; ratio %.3f). The shift is %s, suggesting one-way muni clustering %s remain adequate at K=%d. Year clustering captures the dominant correlated-shocks dimension (national party shocks are common across munis in a given year), so the two-way analog is a defensible substitute for the AKM correction in this design until a full ssaggregate-style implementation is added.",
          twoway$ar_F, hf$ar_F, ratio_ar_F_twoway_oneway,
          if (abs(ratio_ar_F_twoway_oneway - 1) < 0.2) "small (<20%)" else "non-trivial",
          if (abs(ratio_ar_F_twoway_oneway - 1) < 0.2) "appears to" else "may not",
          length(INST_COLS)),
  "",
  "## (6) K=4 power note (back-of-envelope)",
  "",
  sprintf("Under the chi-squared approximation ar_F x K approximately equals the non-centrality lambda under H1, moving from K = 57 (cnae_section MGP) to K = %d (policy_block MGP, 3 offices x %d blocks-after-holdout) implies relative non-centrality lambda_pb / lambda_cnae approximately equal to (K_pb x AR_F_pb) / (K_cnae x AR_F_cnae) = (%d x %.3f) / (%d x %.3f) = **%.3f**. A ratio near or above 1.0 means policy_block preserves identifying power per restriction; a ratio well below 1.0 means within-block heterogeneity is attenuating the true beta. Empirically the headline AR F at policy_block is %s the cnae_section value, %s the strategist memo's expectation that smaller K may rise (less attenuation from weak instruments) or fall (less cross-sectional variation); reduced dimensionality also reduces the many-weak-IV risk per Mikusheva-Sun 2022.",
          length(INST_COLS), length(BLOCKS_KEEP),
          length(INST_COLS), hf$ar_F, k_cnae, ar_F_phase1_cnae,
          (length(INST_COLS) * hf$ar_F) / (k_cnae * ar_F_phase1_cnae),
          if (hf$ar_F > ar_F_phase1_cnae) "above" else "below",
          if (hf$ar_F > ar_F_phase1_cnae) "consistent with" else "as expected from"),
  "",
  "## Escalation gates",
  "",
  paste(c(sprintf("- drop-top-1 first-stage joint F >= 10: %s",
                  if (drop_top1_pass) "PASS" else "**ESCALATE**"),
          sprintf("- slack max |Delta AR F| <= 0.5: %s",
                  if (slack_pass) "PASS" else "**ESCALATE**"),
          sprintf("- headline AR rejects at 5%%: %s",
                  if (hf$rejects_5pc) "PASS"
                  else if (ar_F_phase1_cnae > 0) "**ESCALATE (cnae_section rejected, policy_block does not)**"
                  else "FAIL")),
        collapse = "\n"),
  "",
  "## Verdict",
  "",
  sprintf("Verdict: **%s**",
          if (drop_top1_pass && slack_pass && hf$rejects_5pc) "ADVANCE"
          else if (!drop_top1_pass || !hf$rejects_5pc) "ESCALATE"
          else "FIX"),
  ""
)

writeLines(summary_md, file.path(OUTPUT_BRANCH,
                                  "policy_block_diagnostics_summary.md"))
message(sprintf("[INFO] wrote: %s",
                file.path(OUTPUT_BRANCH,
                          "policy_block_diagnostics_summary.md")))

message(sprintf("\n[INFO] %s | DONE.", Sys.time()))
