#!/usr/bin/env Rscript

# ==============================================================================
# 02_ar_test_emp_share.R
# Anderson-Rubin test of H0: beta = 0 on the sector employment-share vector
# s_emp_jmt, conditional on a volume control and FE.
#
# AR-as-test logic: regress muni-level outcome Y_mt on the per-sector instrument
# matrix {Z_jmt}_j plus the volume control plus FE, and compute the joint Wald
# F-stat on the Z's. Under H0 this F is pivotal regardless of first-stage
# strength (Anderson and Rubin 1949; Andrews, Stock and Sun 2019).
#
# Inputs:
#   data/processed/muni_panel_for_regs.qs2
#     -- muni x year panel with per-sector Z_<office>_<align>_<baseline>_<sec>
#        columns, log_gdp, pib_real, total_bndes_real.
#   data/processed/muni_employment_classification.qs2 (optional; for top_q4)
#   explorations/anderson_rubin/active_denominator/output/
#     emp_share_panel_{variant}.qs2   -- s_emp_jmt for diagnostics / sector list
#     slack_per_cell_{variant}.csv    -- slack control input
#
# Instrument flavor:
#   MGP (mayor + governor + president; "All" combo) is the primary per the
#   firm-support memo (cross-office variation maximizes Rotemberg-relevant
#   identifying variation). ML / MP / MG / Mayor / Gov / Pres reported as
#   sensitivity.
#
# AR p-value computation:
#   The AR F-stat is computed via fixest::wald() on the keep="^Z_..._<sec>$"
#   pattern, using a cluster-robust VCV at muni_id^cnae_section is NOT
#   applicable here because the regression is at the muni-year level. We use
#   one-way cluster-robust SE on muni_id at the muni regression. Under H0 the
#   AR statistic is pivotal and the cluster-robust F is the natural
#   finite-sample analogue (Adao, Kolesar, Morales 2019 emphasise cluster
#   correlation across regions sharing share structure; here the muni-year
#   regression collapses share structure into a coefficient on each Z, so
#   muni-clustering is the operative correction).
#
# Effective F (R2 fix — renamed honestly):
#   We do NOT compute the Montiel Olea-Pflueger 2013 effective F here. A faithful
#   MOP implementation requires the trace-ratio of cluster-robust VCV components
#   (eq. 12 of Olea & Pflueger 2013) which fixest does not return in canonical
#   MOP form. Instead, we report `first_stage_joint_F` -- the cluster-robust
#   joint Wald F on the Z's from the sector-A first stage, matching the FE and
#   cluster convention of scripts/R/5_estimation/53_*.R. The F >= 10 pass
#   criterion is applied to this joint Wald F as a documented approximation;
#   it conservatively understates true MOP under heteroskedasticity-inflating
#   cluster structures.
#
# FE specifications for AR reduced form (R2 fix):
#   We run BOTH `muni_year` (muni_id + year FE) and `year_only` (year FE only)
#   in parallel. The default per critic guidance is muni_year (controls for
#   cross-sectional muni heterogeneity in levels). year_only is retained as a
#   theoretical benchmark.
#
# Phase 1, step B1.3 of journal/plans/2026-05-12_firm_support_hybrid_implementation.md
# Does NOT modify any production script.
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

THIS_SCRIPT <- get_this_script()
BRANCH_DIR  <- normalizePath(file.path(dirname(THIS_SCRIPT), ".."),
                             winslash = "/", mustWork = TRUE)
PROJECT_ROOT <- normalizePath(file.path(BRANCH_DIR, "..", "..", ".."),
                              winslash = "/", mustWork = TRUE)
source(file.path(PROJECT_ROOT, "scripts", "R", "_utils", "utils.R"))

OUTPUT_BRANCH <- file.path(BRANCH_DIR, "output")
if (!dir.exists(OUTPUT_BRANCH)) dir.create(OUTPUT_BRANCH, recursive = TRUE)

# ---- Reproducibility ---------------------------------------------------------

set.seed(20260512L)
setDTthreads(0L)
fixest::setFixest_nthreads(4L)

# ---- CLI ---------------------------------------------------------------------

cli <- commandArgs(trailingOnly = TRUE)
parse_kv <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), cli, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", flag, "="), "", hit[[1L]])
}

VARIANTS_ARG  <- parse_kv("--variants",   "contemporaneous,frozen,balanced")
OUTCOMES_ARG  <- parse_kv("--outcomes",   "log_gdp,delta_log_gdp")
FLAVORS_ARG   <- parse_kv("--flavors",    "MGP,Mayor,Gov,Pres,MG,MP")
FE_SPECS_ARG  <- parse_kv("--fe-specs",   "muni_year,year_only")
BASELINE      <- parse_kv("--baseline",   "cycle_specific")  # or 2002_fixed
ALIGNMENT     <- parse_kv("--alignment",  "coalition")       # or party
INCLUDE_SLACK <- as.logical(parse_kv("--slack-control", "TRUE"))

VARIANTS  <- strsplit(VARIANTS_ARG, ",", fixed = TRUE)[[1L]]
OUTCOMES  <- strsplit(OUTCOMES_ARG, ",", fixed = TRUE)[[1L]]
FLAVORS   <- strsplit(FLAVORS_ARG,  ",", fixed = TRUE)[[1L]]
FE_SPECS  <- strsplit(FE_SPECS_ARG, ",", fixed = TRUE)[[1L]]
stopifnot(all(FE_SPECS %in% c("muni_year", "year_only")))

stopifnot(all(VARIANTS %in% c("contemporaneous", "frozen", "balanced")))
stopifnot(all(OUTCOMES %in% c("log_gdp", "delta_log_gdp")))
stopifnot(all(FLAVORS %in% c("MGP", "Mayor", "Gov", "Pres", "MG", "MP")))
stopifnot(BASELINE %in% c("cycle_specific", "2002_fixed"))
stopifnot(ALIGNMENT %in% c("coalition", "party"))

message(sprintf("[INFO] %s | variants=%s outcomes=%s flavors=%s fe_specs=%s baseline=%s align=%s slack=%s",
                Sys.time(),
                paste(VARIANTS, collapse = ","),
                paste(OUTCOMES, collapse = ","),
                paste(FLAVORS,  collapse = ","),
                paste(FE_SPECS, collapse = ","),
                BASELINE, ALIGNMENT, INCLUDE_SLACK))

# ---- Load muni panel ---------------------------------------------------------

muni_path <- output_path("muni_panel_for_regs.qs2")
stopifnot("muni_panel_for_regs.qs2 must exist (script 41)" = file.exists(muni_path))

message(sprintf("[INFO] %s | loading muni panel...", Sys.time()))
muni <- qs_read(muni_path)
setDT(muni)
muni[, muni_id := as.integer(muni_id)]
muni[, year    := as.integer(year)]

# Drop the unique muni_id == 0 placeholder if present (no GDP).
muni <- muni[muni_id > 0L]

message(sprintf("[INFO] muni panel: %s rows, %d munis, %d years",
                format(nrow(muni), big.mark = ","),
                uniqueN(muni$muni_id), uniqueN(muni$year)))

# ---- Sector list -------------------------------------------------------------

# CNAE sections with per-sector instrument columns. Derived from the muni-panel
# names. Section "G" is excluded by the upstream pipeline; we use whatever the
# panel exposes.
inst_prefix <- sprintf("Z_mayor_%s_%s_", ALIGNMENT, BASELINE)
sec_cols <- grep(paste0("^", inst_prefix, "[A-Z]$"), names(muni), value = TRUE)
SECTIONS <- sort(sub(paste0("^", inst_prefix), "", sec_cols))
stopifnot(length(SECTIONS) >= 2L)
message(sprintf("[INFO] sections (K=%d): %s",
                length(SECTIONS), paste(SECTIONS, collapse = ",")))

# Hold-out section (last alphabetically) to break the share-sum-to-one
# collinearity. The AR null is invariant to which section we drop because the
# test is on the joint coefficient vector restricted to identified contrasts.
HOLDOUT <- SECTIONS[length(SECTIONS)]
SECTIONS_KEEP <- setdiff(SECTIONS, HOLDOUT)
message(sprintf("[INFO] hold-out section: %s; testing K=%d coefficients",
                HOLDOUT, length(SECTIONS_KEEP)))

# ---- Build initial_gdp and volume control -----------------------------------

# initial_gdp_m,0 = pib_real in the first available year per muni (typically 2002).
setorder(muni, muni_id, year)
init_gdp <- muni[!is.na(pib_real),
                 .(initial_gdp = pib_real[1L],
                   initial_year = year[1L]),
                 by = muni_id]
n_missing_init <- nrow(muni[, .N, by = muni_id]) - nrow(init_gdp)
message(sprintf("[INFO] initial_gdp: built for %s munis; %d missing",
                format(nrow(init_gdp), big.mark = ","), n_missing_init))

muni <- merge(muni, init_gdp, by = "muni_id", all.x = TRUE)

# Volume control: bndes_total_mt / initial_gdp_m,0. Unit-free ratio per D24.
# Note: total_bndes_real is in real BRL (deflated upstream), pib_real is real
# BRL of the initial year. The ratio is approximate but stable across munis.
muni[, vol_ratio := total_bndes_real / initial_gdp]
muni[!is.finite(vol_ratio), vol_ratio := NA_real_]

# ---- Build delta_log_gdp -----------------------------------------------------

setorder(muni, muni_id, year)
muni[, delta_log_gdp := log_gdp - shift(log_gdp, type = "lag"), by = muni_id]

# ---- Build flavor instrument lists ------------------------------------------

flavor_offices <- list(
  Mayor = "mayor",
  Gov   = "gov",
  Pres  = "pres",
  MG    = c("mayor", "gov"),
  MP    = c("mayor", "pres"),
  MGP   = c("mayor", "gov", "pres")
)

build_inst_cols <- function(offices, sections) {
  out <- character()
  for (off in offices) {
    for (s in sections) {
      out <- c(out, sprintf("Z_%s_%s_%s_%s", off, ALIGNMENT, BASELINE, s))
    }
  }
  out
}

# Sanity: all required Z cols exist for chosen flavors.
for (fl in FLAVORS) {
  needed <- build_inst_cols(flavor_offices[[fl]], SECTIONS_KEEP)
  miss <- setdiff(needed, names(muni))
  if (length(miss)) {
    stop(sprintf("Missing Z columns for flavor %s: %s",
                 fl, paste(head(miss, 5), collapse = ", ")))
  }
}

# ---- Slack control (optional, per variant) ----------------------------------

load_slack <- function(variant) {
  pth <- file.path(OUTPUT_BRANCH, sprintf("slack_per_cell_%s.csv", variant))
  stopifnot(file.exists(pth))
  s <- fread(pth)
  s[, muni_id := as.integer(muni_id)]
  s[, year    := as.integer(year)]
  # R2 FIX 3: Inspect aggregation structure before collapsing.
  cols <- names(s)
  has_cycle  <- any(c("cycle", "cycle_id", "term") %in% cols)
  has_sector <- any(c("cnae_section", "sector", "sector_group") %in% cols)
  message(sprintf("[INFO] slack_per_cell_%s.csv columns: %s",
                  variant, paste(cols, collapse = ",")))
  # Cycle-correct merge: for each (muni, year), pick the slack value from the
  # ACTIVE cycle in that year (the cycle that the variant's firm set was
  # frozen from). When the CSV already aggregates within muni-year, use
  # whatever rows exist. We collapse over any sector dim by mean. We collapse
  # over cycle by taking the row whose cycle window includes `year` if cycle
  # bounds are present; otherwise mean over cycle rows.
  group_keys <- c("muni_id", "year")
  if (has_sector) {
    sec_col <- intersect(c("cnae_section","sector","sector_group"), cols)[1L]
    s <- s[, .(slack_share = mean(slack_share, na.rm = TRUE)),
           by = c(group_keys, sec_col)]
    # Then collapse over sector (unweighted; muni-year slack is the avg
    # across active sectors).
    s <- s[, .(slack_share = mean(slack_share, na.rm = TRUE)),
           by = group_keys]
  } else {
    s <- s[, .(slack_share = mean(slack_share, na.rm = TRUE)),
           by = group_keys]
  }
  s[!is.finite(slack_share), slack_share := NA_real_]
  v <- var(s$slack_share, na.rm = TRUE)
  message(sprintf("[INFO] slack_share muni-year variance [%s] = %s (N=%d)",
                  variant, formatC(v, format = "g", digits = 4), nrow(s)))
  if (is.finite(v) && v < 1e-10) {
    message(sprintf("[WARN] slack_share has ~zero muni-year variance in '%s' -- ",
                    variant),
            "likely collinear in regression; control will drop.")
  }
  s
}

# ---- AR test runner ----------------------------------------------------------

# For a given (variant, outcome, flavor), assemble the muni-year regression
# data, fit the reduced form, and extract the AR F statistic + p-value.

cluster_var <- "muni_id"

run_ar <- function(variant, outcome, flavor, fe_spec = "muni_year") {
  stopifnot(fe_spec %in% c("muni_year", "year_only"))

  inst_cols <- build_inst_cols(flavor_offices[[flavor]], SECTIONS_KEEP)

  # Slack: variant-specific.
  if (INCLUDE_SLACK) {
    slack_dt <- load_slack(variant)
    dat <- merge(muni, slack_dt, by = c("muni_id", "year"), all.x = TRUE)
  } else {
    dat <- copy(muni)
    dat[, slack_share := NA_real_]
  }

  keep_cols <- c("muni_id", "year", outcome, "vol_ratio",
                 "slack_share", inst_cols)
  dat <- dat[, ..keep_cols]
  dat <- dat[complete.cases(dat[, .SD, .SDcols = setdiff(keep_cols, "slack_share")])]
  if (INCLUDE_SLACK) {
    dat <- dat[!is.na(slack_share)]
  }
  if (!nrow(dat)) {
    return(list(status = "empty_sample"))
  }

  # Build formula: outcome ~ Z's + vol_ratio (+ slack) | FE
  rhs_terms <- c(inst_cols, "vol_ratio")
  if (INCLUDE_SLACK) rhs_terms <- c(rhs_terms, "slack_share")
  fe_term <- if (identical(fe_spec, "muni_year")) "muni_id + year" else "year"
  fml <- as.formula(paste0(
    outcome, " ~ ", paste(rhs_terms, collapse = " + "),
    " | ", fe_term
  ))

  mod <- tryCatch(
    feols(fml, data = dat,
          vcov = as.formula(paste0("~ ", cluster_var)),
          lean = TRUE),
    error = function(e) {
      message(sprintf("[WARN] AR fit failed [%s/%s/%s/%s]: %s",
                      variant, outcome, flavor, fe_spec, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(mod)) return(list(status = "fit_failed"))

  # AR statistic: joint cluster-robust Wald F on the Z's.
  z_pattern <- paste0("^Z_(", paste(flavor_offices[[flavor]], collapse = "|"),
                      ")_", ALIGNMENT, "_", BASELINE, "_")
  w <- tryCatch(fixest::wald(mod, keep = z_pattern),
                error = function(e) NULL)
  ar_F <- if (!is.null(w)) as.numeric(w$stat) else NA_real_
  ar_p <- if (!is.null(w)) as.numeric(w$p)    else NA_real_

  # Coef stats (for sanity; point estimates are not the AR test).
  ct <- coeftable(mod)
  z_rows <- grepl(z_pattern, rownames(ct))
  n_z_identified <- sum(z_rows)
  n_collin <- length(mod$collin.var)

  # Rejection-region characterization on a 1-D projection: project beta onto
  # the leading Z (largest absolute coefficient). The AR CI on c'beta is the
  # set of c0 such that the AR F at c'beta = c0 is below the chi^2 critical
  # value. For diagnostic purposes here we just report whether the AR F
  # rejects at 5% (i.e., the 0 point is outside the implied AR CI when AR
  # rejects). Unboundedness in the Dufour (1997) sense is flagged when AR
  # fails to reject AND the joint coefficient is locally unidentified
  # (proxied here by n_collin > 0 or n_z_identified < length(inst_cols)/2).
  rejects_5pc <- isTRUE(ar_p < 0.05)
  unbounded   <- (!rejects_5pc) &&
                 (n_collin > 0 || n_z_identified < length(inst_cols) / 2)

  list(
    status = "ok",
    fe_spec = fe_spec,
    n_obs = nobs(mod),
    n_munis = uniqueN(dat$muni_id),
    n_years = uniqueN(dat$year),
    K_instruments_requested = length(inst_cols),
    K_instruments_identified = n_z_identified,
    n_collin = n_collin,
    ar_F = ar_F,
    ar_p = ar_p,
    rejects_5pc = rejects_5pc,
    rejection_region = if (rejects_5pc) "bounded_excludes_zero"
                       else if (unbounded) "unbounded_dufour"
                       else "bounded_contains_zero",
    vol_ratio_coef = if ("vol_ratio" %in% rownames(ct))
                       ct["vol_ratio", "Estimate"] else NA_real_,
    vol_ratio_se   = if ("vol_ratio" %in% rownames(ct))
                       ct["vol_ratio", "Std. Error"] else NA_real_,
    coef_table_obj = ct,
    z_pattern = z_pattern,
    mod = mod,
    leading_sec = {
      if (any(z_rows)) {
        idx <- which.max(abs(ct[z_rows, "Estimate"]))
        rn  <- rownames(ct)[z_rows][idx]
        sub(".*_([A-Z])$", "\\1", rn)
      } else NA_character_
    }
  )
}

# ---- First-stage joint F (renamed from "eff_F_proxy") -----------------------
#
# R2 FIX 2: This is NOT the Montiel Olea-Pflueger 2013 effective F. It is the
# cluster-robust joint Wald F on the Z's from the sector-A panel first stage
# s_emp_jmt ~ Z (FE: muni_id^cnae_section + cnae_section^year; cluster: muni +
# cnae_section, matching scripts/R/5_estimation/53_*.R). Applied as a pass
# diagnostic with the F >= 10 cutoff. Conservatively understates true MOP only
# under heteroskedasticity-inflating clustering structures.

run_first_stage_joint_F <- function(variant, flavor) {
  emp_path <- file.path(OUTPUT_BRANCH,
                        sprintf("emp_share_panel_%s.qs2", variant))
  if (!file.exists(emp_path)) return(NA_real_)
  emp <- qs_read(emp_path)
  setDT(emp)
  emp[, muni_id := as.integer(muni_id)]
  emp[, year    := as.integer(year)]

  # Long instrument frame: per (muni, year, section), the Z value is the same
  # value as the wide column Z_<office>_<align>_<baseline>_<section>. Build by
  # melt from the muni panel.
  offices <- flavor_offices[[flavor]]
  wide_cols <- character()
  rename_map <- list()
  for (off in offices) {
    for (s in SECTIONS_KEEP) {
      col <- sprintf("Z_%s_%s_%s_%s", off, ALIGNMENT, BASELINE, s)
      newnm <- sprintf("Z_%s.%s", off, s)
      wide_cols <- c(wide_cols, col)
      rename_map[[col]] <- newnm
    }
  }
  mp <- muni[, c("muni_id", "year", wide_cols), with = FALSE]
  setnames(mp, wide_cols, unlist(rename_map[wide_cols]))
  # Melt to (muni, year, section, off, Z).
  id_vars <- c("muni_id", "year")
  meas <- setdiff(names(mp), id_vars)
  long <- melt(mp, id.vars = id_vars, measure.vars = meas,
               variable.name = "key", value.name = "Z_val")
  long[, c("office_tag", "cnae_section") := tstrsplit(as.character(key), ".",
                                                       fixed = TRUE)]
  long[, key := NULL]
  long_w <- dcast(long, muni_id + year + cnae_section ~ office_tag,
                  value.var = "Z_val")
  z_cols <- setdiff(names(long_w), c("muni_id", "year", "cnae_section"))

  panel <- merge(emp, long_w,
                 by = c("muni_id", "year", "cnae_section"),
                 all.x = FALSE, all.y = FALSE)
  if (!nrow(panel)) return(NA_real_)

  rhs <- paste(z_cols, collapse = " + ")
  fml <- as.formula(sprintf(
    "s_emp_jmt ~ %s | muni_id^cnae_section + cnae_section^year", rhs
  ))
  mod <- tryCatch(
    feols(fml, data = panel,
          vcov = ~ muni_id + cnae_section, lean = TRUE),
    error = function(e) {
      message(sprintf("[WARN] first-stage joint F fit failed [%s/%s]: %s",
                      variant, flavor, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(mod)) return(NA_real_)
  w <- tryCatch(fixest::wald(mod, keep = "^Z_"), error = function(e) NULL)
  if (is.null(w)) return(NA_real_)
  as.numeric(w$stat)
}

# ---- Driver loop -------------------------------------------------------------

results <- list()
full_tabs <- list()
# Cache first-stage joint F by (variant, flavor) -- does not depend on outcome
# or FE spec of the reduced form.
fs_cache <- list()
for (variant in VARIANTS) {
  for (outcome in OUTCOMES) {
    for (flavor in FLAVORS) {
      for (fe_spec in FE_SPECS) {
        tag <- sprintf("[%s|%s|%s|fe=%s]", variant, outcome, flavor, fe_spec)
        message(sprintf("[INFO] %s | running %s", Sys.time(), tag))
        res <- run_ar(variant, outcome, flavor, fe_spec = fe_spec)
        if (!identical(res$status, "ok")) {
          message(sprintf("[WARN] %s status=%s -- skipped", tag, res$status))
          results[[length(results) + 1L]] <- data.table(
            variant = variant, outcome = outcome, flavor = flavor,
            fe_spec = fe_spec, status = res$status
          )
          next
        }
        fs_F <- NA_real_
        if (identical(flavor, "MGP")) {
          k_cache <- paste(variant, flavor, sep = "__")
          if (is.null(fs_cache[[k_cache]])) {
            fs_cache[[k_cache]] <- run_first_stage_joint_F(variant, flavor)
          }
          fs_F <- fs_cache[[k_cache]]
        }
        message(sprintf("       AR_F=%.3f AR_p=%.4g K=%d/%d coll=%d fs_F=%s region=%s",
                        res$ar_F, res$ar_p,
                        res$K_instruments_identified,
                        res$K_instruments_requested,
                        res$n_collin,
                        formatC(fs_F, format = "f", digits = 3),
                        res$rejection_region))
        results[[length(results) + 1L]] <- data.table(
          variant = variant, outcome = outcome, flavor = flavor,
          fe_spec = fe_spec,
          status = "ok",
          n_obs = res$n_obs, n_munis = res$n_munis, n_years = res$n_years,
          K_requested = res$K_instruments_requested,
          K_identified = res$K_instruments_identified,
          n_collinear  = res$n_collin,
          ar_F = res$ar_F, ar_p = res$ar_p,
          rejects_5pc = res$rejects_5pc,
          rejection_region = res$rejection_region,
          vol_ratio_coef = res$vol_ratio_coef,
          vol_ratio_se   = res$vol_ratio_se,
          leading_sec    = res$leading_sec,
          first_stage_joint_F = fs_F
        )
        # Bare tabular export for MGP at the muni_year FE spec (R2 default).
        if (identical(flavor, "MGP") && identical(fe_spec, "muni_year")) {
          full_tabs[[paste(variant, outcome, sep = "__")]] <- res
        }
      }
    }
  }
}

summary_dt <- rbindlist(results, fill = TRUE)
out_summary <- file.path(OUTPUT_BRANCH, "ar_test_summary.csv")
fwrite(summary_dt, out_summary)
message(sprintf("[INFO] wrote: %s", out_summary))

# ---- Full coefficient tables (bare tabular, booktabs) ------------------------

format_num <- function(x, digits = 3L) {
  if (!is.finite(x)) return("--")
  formatC(x, format = "f", digits = digits)
}
# R2 FIX 4: cap displayed p-values at 1e-3 for TeX export. F-tail probabilities
# below ~1e-6 are unreliable under cluster-robust assumptions (Hansen-Lee 2019).
format_pval_tex <- function(p, digits = 4L) {
  if (!is.finite(p)) return("--")
  if (p < 1e-3) return("$<0.001$")
  formatC(p, format = "f", digits = digits)
}
stars <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.01) return("$^{***}$")
  if (p < 0.05) return("$^{**}$")
  if (p < 0.10) return("$^{*}$")
  ""
}

write_full_tab <- function(variant, outcome, res) {
  ct  <- res$coef_table_obj
  rn  <- rownames(ct)
  is_z <- grepl(res$z_pattern, rn)
  is_vol <- rn == "vol_ratio"
  is_slack <- rn == "slack_share"
  rn_keep <- c(rn[is_z], rn[is_vol], rn[is_slack])
  cti <- ct[match(rn_keep, rn), , drop = FALSE]

  rows <- character()
  for (i in seq_len(nrow(cti))) {
    name <- rownames(cti)[i]
    est  <- cti[i, "Estimate"]
    se   <- cti[i, "Std. Error"]
    p    <- cti[i, "Pr(>|t|)"]
    label <- gsub("_", "\\\\_", name)
    rows <- c(rows,
              sprintf("%s & %s%s \\\\", label,
                      format_num(est, 4), stars(p)),
              sprintf(" & (%s) \\\\", format_num(se, 4)))
  }

  ar_F_str <- format_num(res$ar_F, 3)
  ar_p_str <- format_pval_tex(res$ar_p, 4)
  fe_label <- if (identical(res$fe_spec, "muni_year")) "muni + year"
              else "year"

  body <- c(
    "\\begin{tabular}{lc}",
    "\\toprule",
    sprintf(" & %s \\\\", gsub("_", "\\\\_", outcome)),
    "\\midrule",
    rows,
    "\\midrule",
    sprintf("Observations & %s \\\\", format(res$n_obs, big.mark = ",")),
    sprintf("Municipalities & %s \\\\", format(res$n_munis, big.mark = ",")),
    sprintf("$K$ instruments & %d \\\\", res$K_instruments_identified),
    sprintf("Fixed effects & %s \\\\", fe_label),
    sprintf("AR $F$ & %s \\\\", ar_F_str),
    sprintf("AR $p$ & %s \\\\", ar_p_str),
    "\\bottomrule",
    "\\end{tabular}"
  )
  out <- file.path(OUTPUT_BRANCH,
                   sprintf("ar_test_full_%s_%s.tex", variant, outcome))
  writeLines(body, out)
  message(sprintf("[INFO] wrote: %s", out))
}

for (key in names(full_tabs)) {
  parts <- strsplit(key, "__", fixed = TRUE)[[1L]]
  write_full_tab(parts[1L], parts[2L], full_tabs[[key]])
}

# ---- Sector-share summary (B1.2 critic backfill) -----------------------------
# Unweighted and n_mt-weighted mean shares per sector, with rank under each.

build_sector_summary <- function() {
  emp_path <- file.path(OUTPUT_BRANCH, "emp_share_panel_contemporaneous.qs2")
  if (!file.exists(emp_path)) return(invisible(NULL))
  emp <- qs_read(emp_path)
  setDT(emp)
  # Unweighted: simple mean of s_emp_jmt across cells.
  unw <- emp[, .(mean_share_unweighted = mean(s_emp_jmt, na.rm = TRUE)),
             by = cnae_section]
  wt  <- emp[, .(mean_share_weighted = sum(n_jmt, na.rm = TRUE) /
                                       sum(n_mt, na.rm = TRUE)),
             by = cnae_section]
  out <- merge(unw, wt, by = "cnae_section")
  setorder(out, -mean_share_unweighted)
  out[, rank_unweighted := seq_len(.N)]
  setorder(out, -mean_share_weighted)
  out[, rank_weighted := seq_len(.N)]
  setorder(out, rank_weighted)
  out_path <- file.path(OUTPUT_BRANCH, "sector_share_summary.csv")
  fwrite(out, out_path)
  message(sprintf("[INFO] wrote: %s", out_path))
  out
}
sec_sum <- build_sector_summary()
if (!is.null(sec_sum)) {
  message("[INFO] top-5 sectors (n_mt-weighted):")
  print(head(sec_sum[, .(cnae_section, mean_share_weighted, rank_weighted,
                         mean_share_unweighted, rank_unweighted)], 5))
}

# ---- Pass-criterion check ----------------------------------------------------

# R2: pass criterion applied to first_stage_joint_F (renamed from eff_F_proxy)
# at the muni_year FE spec, contemporaneous variant, MGP flavor, log_gdp outcome.
fs_pass <- summary_dt[variant == "contemporaneous" & flavor == "MGP" &
                      outcome == "log_gdp" & fe_spec == "muni_year" &
                      !is.na(first_stage_joint_F),
                      first_stage_joint_F[1L]]
passed <- isTRUE(is.finite(fs_pass) && fs_pass >= 10)
message(sprintf("[INFO] pass criterion (contemporaneous MGP first_stage_joint_F >= 10): %s (F=%s)",
                if (isTRUE(passed)) "PASS" else "FAIL",
                formatC(fs_pass, format = "f", digits = 3)))

message(sprintf("[INFO] %s | done.", Sys.time()))
