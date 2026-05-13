#!/usr/bin/env Rscript

# ==============================================================================
# 07_ar_drop_violators.R
# Phase 1.6 diagnostic (e) -- AR test with pre-trend violators dropped.
#
# B1.6 (06_pretrend_proper.R) identified two genuine sector-share pre-trend
# violators on the variant-beta test: Pres x E (p = 0.00112) and Pres x P
# (p = 0.0177). Variant-alpha also rejected on log_gdp (p = 2e-8) and
# delta_log_gdp (p = 0.0024), motivating the strictest scenario: drop the
# entire presidential office.
#
# This script re-runs the headline B1.3 R2 AR test (contemporaneous variant,
# MGP flavor, muni+year FE, log_gdp outcome, cluster on muni_id) under three
# drop-violator scenarios:
#
#   S1: drop_PresE   -- exclude Z_pres_coalition_cycle_specific_E only
#   S2: drop_PresE_PresP -- exclude both beta-test violators
#   S3: drop_AllPres -- drop ALL Z_pres_* columns (most conservative)
#
# For each scenario, we run all 3 denominator variants x both outcomes x both
# FE specs. The headline cell is (contemporaneous + log_gdp + muni_year).
#
# Pass framing:
#   Strong pass -- S3 still rejects at 5% with fs_F >= 10
#   Weak pass   -- S2 rejects at 5% with fs_F >= 10
#   Fail        -- S1 alone collapses the rejection
#
# Inputs (same as 02_ar_test_emp_share.R):
#   data/processed/muni_panel_for_regs.qs2
#   explorations/anderson_rubin/active_denominator/output/
#     emp_share_panel_{variant}.qs2
#
# Outputs:
#   output/ar_drop_violators.csv
#   output/ar_drop_violators_summary.md
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

# ---- Reproducibility ---------------------------------------------------------

set.seed(20260512L)
setDTthreads(0L)
fixest::setFixest_nthreads(4L)

# ---- Constants ---------------------------------------------------------------

ALIGNMENT  <- "coalition"
BASELINE   <- "cycle_specific"
OFFICES    <- c("mayor", "gov", "pres")
FLAVOR     <- "MGP"
CLUSTER_VAR <- "muni_id"

VARIANTS  <- c("contemporaneous", "frozen", "balanced")
OUTCOMES  <- c("log_gdp", "delta_log_gdp")
FE_SPECS  <- c("muni_year", "year_only")

SCENARIOS <- list(
  drop_PresE       = c("Z_pres_coalition_cycle_specific_E"),
  drop_PresE_PresP = c("Z_pres_coalition_cycle_specific_E",
                       "Z_pres_coalition_cycle_specific_P"),
  drop_AllPres     = NULL  # set below: all Z_pres_* columns
)

message(sprintf("[INFO] %s | starting drop-violator AR test", Sys.time()))

# ---- Load muni panel ---------------------------------------------------------

muni_path <- output_path("muni_panel_for_regs.qs2")
stopifnot(file.exists(muni_path))
message(sprintf("[INFO] %s | loading muni panel...", Sys.time()))
muni <- qs_read(muni_path)
setDT(muni)
muni[, muni_id := as.integer(muni_id)]
muni[, year    := as.integer(year)]
muni <- muni[muni_id > 0L]

# Sections discovered from the mayor Z columns (canonical anchor).
inst_prefix <- sprintf("Z_mayor_%s_%s_", ALIGNMENT, BASELINE)
sec_cols <- grep(paste0("^", inst_prefix, "[A-Z]$"), names(muni), value = TRUE)
SECTIONS <- sort(sub(paste0("^", inst_prefix), "", sec_cols))
HOLDOUT  <- SECTIONS[length(SECTIONS)]
SECTIONS_KEEP <- setdiff(SECTIONS, HOLDOUT)
message(sprintf("[INFO] sections (K=%d, holdout=%s): %s",
                length(SECTIONS_KEEP), HOLDOUT,
                paste(SECTIONS_KEEP, collapse = ",")))

build_inst_cols <- function(offices, sections) {
  out <- character()
  for (off in offices) {
    for (s in sections) {
      out <- c(out, sprintf("Z_%s_%s_%s_%s", off, ALIGNMENT, BASELINE, s))
    }
  }
  out
}

INST_COLS_FULL <- build_inst_cols(OFFICES, SECTIONS_KEEP)
stopifnot(all(INST_COLS_FULL %in% names(muni)))

# Finalize drop_AllPres scenario: all Z_pres_* columns in the full set.
SCENARIOS$drop_AllPres <- grep("^Z_pres_", INST_COLS_FULL, value = TRUE)

# Verify violator columns exist
for (sc_name in names(SCENARIOS)) {
  drops <- SCENARIOS[[sc_name]]
  miss <- setdiff(drops, INST_COLS_FULL)
  if (length(miss)) {
    stop(sprintf("Scenario %s references missing columns: %s",
                 sc_name, paste(miss, collapse = ",")))
  }
  message(sprintf("[INFO] scenario=%s drops %d cols: %s",
                  sc_name, length(drops), paste(drops, collapse = ",")))
}

# ---- Volume control and outcomes --------------------------------------------

setorder(muni, muni_id, year)
init_gdp <- muni[!is.na(pib_real),
                 .(initial_gdp = pib_real[1L]), by = muni_id]
muni <- merge(muni, init_gdp, by = "muni_id", all.x = TRUE)
muni[, vol_ratio := total_bndes_real / initial_gdp]
muni[!is.finite(vol_ratio), vol_ratio := NA_real_]

muni[, delta_log_gdp := log_gdp - shift(log_gdp, type = "lag"), by = muni_id]

# ---- Reduced-form AR runner --------------------------------------------------

run_ar_drop <- function(inst_cols_use, outcome, fe_spec) {
  stopifnot(fe_spec %in% c("muni_year", "year_only"))
  keep <- c("muni_id", "year", outcome, "vol_ratio", inst_cols_use)
  dat <- muni[, ..keep]
  dat <- dat[complete.cases(dat)]
  if (!nrow(dat)) return(NULL)

  rhs <- c(inst_cols_use, "vol_ratio")
  fe_term <- if (identical(fe_spec, "muni_year")) "muni_id + year" else "year"
  fml <- as.formula(paste0(outcome, " ~ ", paste(rhs, collapse = " + "),
                           " | ", fe_term))
  mod <- tryCatch(
    feols(fml, data = dat,
          vcov = as.formula(paste0("~ ", CLUSTER_VAR)),
          lean = TRUE),
    error = function(e) {
      message(sprintf("[WARN] AR fit failed: %s", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(mod)) return(NULL)

  z_pattern <- paste0("^Z_(",
                      paste(OFFICES, collapse = "|"),
                      ")_", ALIGNMENT, "_", BASELINE, "_")
  w <- tryCatch(fixest::wald(mod, keep = z_pattern),
                error = function(e) NULL)
  if (is.null(w)) return(NULL)

  ct <- coeftable(mod)
  is_z <- grepl(z_pattern, rownames(ct))
  n_z_id <- sum(is_z)
  n_col  <- length(mod$collin.var)
  ar_F <- as.numeric(w$stat)
  ar_p <- as.numeric(w$p)
  rejects <- isTRUE(ar_p < 0.05)
  region <- if (rejects) "bounded_excludes_zero" else
            if (n_col > 0 || n_z_id < length(inst_cols_use) / 2)
              "unbounded_dufour" else "bounded_contains_zero"

  list(n_obs = nobs(mod), n_munis = uniqueN(dat$muni_id),
       K_req = length(inst_cols_use), K_id = n_z_id,
       n_collin = n_col, ar_F = ar_F, ar_p = ar_p,
       rejects_5pc = rejects, region = region)
}

# ---- First-stage joint F (matches 02_*.R) ------------------------------------

run_first_stage_joint_F <- function(variant, inst_cols_use, offices_present) {
  emp_path <- file.path(OUTPUT_BRANCH,
                        sprintf("emp_share_panel_%s.qs2", variant))
  if (!file.exists(emp_path)) return(NA_real_)
  emp <- qs_read(emp_path)
  setDT(emp)
  emp[, muni_id := as.integer(muni_id)]
  emp[, year    := as.integer(year)]

  # Parse offices x sections present in inst_cols_use.
  rename_map <- list()
  wide_cols  <- character()
  for (col in inst_cols_use) {
    # col format: Z_<office>_<alignment>_<baseline>_<sec>
    sec_match <- sub("^.*_([A-Z])$", "\\1", col)
    off_match <- sub("^Z_([^_]+)_.*$", "\\1", col)
    newnm <- sprintf("Z_%s.%s", off_match, sec_match)
    wide_cols <- c(wide_cols, col)
    rename_map[[col]] <- newnm
  }
  mp <- muni[, c("muni_id", "year", wide_cols), with = FALSE]
  setnames(mp, wide_cols, unlist(rename_map[wide_cols]))
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
  if (!length(z_cols)) return(NA_real_)

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
      message(sprintf("[WARN] FS fit failed: %s", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(mod)) return(NA_real_)
  w <- tryCatch(fixest::wald(mod, keep = "^Z_"), error = function(e) NULL)
  if (is.null(w)) return(NA_real_)
  as.numeric(w$stat)
}

# ---- Driver: also include S0 = baseline (no drop) for sanity check ----------

ALL_SCENARIOS <- c(list(baseline = character(0)), SCENARIOS)

results <- list()
fs_cache <- list()  # keyed by (variant, scenario)

for (sc_name in names(ALL_SCENARIOS)) {
  drops <- ALL_SCENARIOS[[sc_name]]
  inst_cols_use <- setdiff(INST_COLS_FULL, drops)
  offices_present <- unique(sub("^Z_([^_]+)_.*$", "\\1", inst_cols_use))

  for (variant in VARIANTS) {
    fs_key <- paste(variant, sc_name, sep = "__")
    if (is.null(fs_cache[[fs_key]])) {
      fs_cache[[fs_key]] <- run_first_stage_joint_F(variant, inst_cols_use,
                                                    offices_present)
    }
    fs_F <- fs_cache[[fs_key]]

    for (outcome in OUTCOMES) {
      for (fe_spec in FE_SPECS) {
        tag <- sprintf("[%s|%s|%s|fe=%s]", sc_name, variant, outcome, fe_spec)
        message(sprintf("[INFO] %s | %s K=%d", Sys.time(), tag,
                        length(inst_cols_use)))
        res <- run_ar_drop(inst_cols_use, outcome, fe_spec)
        if (is.null(res)) {
          results[[length(results) + 1L]] <- data.table(
            scenario = sc_name, variant = variant, outcome = outcome,
            fe_spec = fe_spec, n_dropped = length(drops),
            n_instruments = length(inst_cols_use),
            status = "fit_failed"
          )
          next
        }
        message(sprintf("       AR_F=%.4f AR_p=%.4g K=%d/%d coll=%d fs_F=%s region=%s",
                        res$ar_F, res$ar_p, res$K_id, res$K_req,
                        res$n_collin, formatC(fs_F, format = "f", digits = 3),
                        res$region))
        results[[length(results) + 1L]] <- data.table(
          scenario = sc_name, variant = variant, outcome = outcome,
          fe_spec = fe_spec,
          n_dropped = length(drops),
          n_instruments = res$K_req,
          K_identified = res$K_id,
          n_collinear = res$n_collin,
          n_obs = res$n_obs, n_munis = res$n_munis,
          ar_F = res$ar_F, ar_p = res$ar_p,
          rejects_5pc = res$rejects_5pc,
          region_status = res$region,
          fs_F = fs_F,
          status = "ok"
        )
      }
    }
  }
}

summary_dt <- rbindlist(results, fill = TRUE)
out_csv <- file.path(OUTPUT_BRANCH, "ar_drop_violators.csv")
fwrite(summary_dt, out_csv)
message(sprintf("[INFO] wrote: %s", out_csv))

# ---- Verdict on headline cell ------------------------------------------------

headline_cell <- function(sc_name) {
  summary_dt[scenario == sc_name & variant == "contemporaneous" &
             outcome == "log_gdp" & fe_spec == "muni_year"]
}

baseline_row <- headline_cell("baseline")
S1 <- headline_cell("drop_PresE")
S2 <- headline_cell("drop_PresE_PresP")
S3 <- headline_cell("drop_AllPres")

verdict <- function(row) {
  if (!nrow(row) || row$status != "ok") return("NA")
  if (isTRUE(row$rejects_5pc) && isTRUE(row$fs_F >= 10)) "PASS"
  else if (isTRUE(row$rejects_5pc)) "REJECT-but-fs_F<10"
  else "FAIL"
}

if (nrow(S3) && verdict(S3) == "PASS") {
  overall <- "STRONG PASS"
} else if (nrow(S2) && verdict(S2) == "PASS") {
  overall <- "WEAK PASS"
} else if (nrow(S1) && verdict(S1) == "PASS") {
  overall <- "MARGINAL (only S1 survives)"
} else {
  overall <- "FAIL"
}

message(sprintf("[INFO] overall verdict: %s", overall))

# ---- Markdown summary --------------------------------------------------------

fmt <- function(x, d = 4) if (!is.finite(x)) "NA" else formatC(x, format = "g", digits = d)

fmt_row <- function(label, row) {
  if (!nrow(row) || row$status != "ok") {
    return(sprintf("| %s | -- | -- | -- | -- | -- | -- |", label))
  }
  sprintf("| %s | %d | %s | %s | %s | %s | %s |",
          label, row$n_instruments,
          fmt(row$ar_F), fmt(row$ar_p), fmt(row$fs_F),
          isTRUE(row$rejects_5pc),
          row$region_status)
}

md <- c(
  "# Drop-Violator AR Test (B1.6 diagnostic e)",
  "",
  sprintf("**Date:** %s", format(Sys.time(), "%Y-%m-%d %H:%M")),
  "**Headline cell:** contemporaneous variant, log_gdp, muni+year FE, MGP flavor, cluster on muni_id",
  "",
  "## Scenarios",
  "",
  sprintf("- **baseline** (B1.3 R2 replication): K = %d (mayor + gov + pres x %d sections, drop holdout %s)",
          length(INST_COLS_FULL), length(SECTIONS_KEEP), HOLDOUT),
  sprintf("- **drop_PresE**: drop `%s`", SCENARIOS$drop_PresE),
  sprintf("- **drop_PresE_PresP**: drop `%s`",
          paste(SCENARIOS$drop_PresE_PresP, collapse = "`, `")),
  sprintf("- **drop_AllPres**: drop all %d `Z_pres_*` columns",
          length(SCENARIOS$drop_AllPres)),
  "",
  "## Headline results (contemporaneous + log_gdp + muni+year FE)",
  "",
  "| Scenario | K | AR F | AR p | fs_F | rejects 5% | region |",
  "|---|---|---|---|---|---|---|",
  fmt_row("baseline",         baseline_row),
  fmt_row("drop_PresE",       S1),
  fmt_row("drop_PresE_PresP", S2),
  fmt_row("drop_AllPres",     S3),
  "",
  sprintf("## Overall verdict: **%s**", overall),
  "",
  "Pass framing:",
  "- Strong pass -- drop_AllPres rejects at 5% with fs_F >= 10",
  "- Weak pass -- drop_PresE_PresP rejects at 5% with fs_F >= 10",
  "- Fail -- even drop_PresE collapses the rejection",
  "",
  "Full grid (3 scenarios + baseline x 3 variants x 2 outcomes x 2 FE specs)",
  "saved to `ar_drop_violators.csv`."
)

out_md <- file.path(OUTPUT_BRANCH, "ar_drop_violators_summary.md")
writeLines(md, out_md)
message(sprintf("[INFO] wrote: %s", out_md))

message(sprintf("[INFO] %s | done.", Sys.time()))
