#!/usr/bin/env Rscript

# ==============================================================================
# 09_cycle_alignment_fix_test.R
# Phase 1.8 -- gov-cycle alignment hypothesis test.
#
# Hypothesis. The variant-alpha pre-trend rejection on Delta log_gdp is driven
# entirely by gov-Z columns (B1.7.2: gov F=2.47 p=4e-4; mayor p=0.79; pres
# cleaned p~0.06). B1.8 hypothesizes that this rejection is a TIMING-ALIGNMENT
# SPECIFICATION ARTIFACT: the variant-alpha pre-window is built on the MAYORAL
# election calendar (tau in [e_mayor-3, e_mayor-1]), but gov elections occur
# MID-mayoral-cycle (Oct 2002, 2006, 2010, 2014; inauguration Jan 2003, 2007,
# 2011, 2015 -- confirmed in scripts/R/3_instruments/32_build_alignment_shocks.R
# lines 12-13). The Z_gov values at the post-mayoral-election ref_year (e.g.,
# 2005 for the 2004-cycle) reference the gov inaugurated in 2003 (elected Oct
# 2002) -- the same gov in office during the "pre" mayoral window 2002-2003.
# So Z_gov_future trivially predicts pre-mayoral-window Delta log_gdp via the
# legitimate gov-cycle effect, not a violation of the GPSS pre-trend assumption.
#
# Three tests.
#   B1.8.1 -- print panel calendar (year, e_mayor(t), e_gov(t), gov term inaug)
#             to confirm or refute the timing claim structurally.
#   B1.8.2 -- gov-only variant-alpha with STRICT PRE-GOV-ELECTION TIMING.
#             For each gov cycle c with election year e_c, restrict the test
#             sample to tau in [e_c-3, e_c-1]; Z_gov_future references the
#             gov-Z values during the c-th cycle (constant within muni-cycle).
#   B1.8.3 -- per-office strict-timing variant-alpha.
#             Mayor: tau in [e_mayor-3, e_mayor-1] (was the B1.6 baseline).
#             Gov:   tau in [e_gov-3, e_gov-1] (strict).
#             Pres:  tau in [e_pres-3, e_pres-1] (strict; pres E+P dropped).
#
# Inputs:
#   data/processed/muni_panel_for_regs.qs2 (script 41)
#
# Outputs:
#   output/gov_strict_timing_pretrend.csv
#   output/by_office_strict_timing.csv
#   output/pretrend_b18_summary.md
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

ALIGNMENT   <- "coalition"
BASELINE    <- "cycle_specific"
CLUSTER_VAR <- "muni_id"

# Election years (Brazilian schedule; confirmed from script 32 lines 12-13 and
# script 34 term_map lines 108-117).
MAYOR_ELECTIONS <- c(2000L, 2004L, 2008L, 2012L, 2016L)    # inaug +1
GOV_ELECTIONS   <- c(2002L, 2006L, 2010L, 2014L, 2018L)    # inaug +1 (pres same)
PRES_ELECTIONS  <- GOV_ELECTIONS

# Mayor term map: inauguration year -> covered panel years (script 34 lines
# 109-117). We invert to get e_mayor(t) and e_gov(t) for each panel year.
MAYOR_TERM_MAP <- rbindlist(list(
  data.table(election_year = 2000L, inaug_year = 2001L, term_years = 2001L:2004L),
  data.table(election_year = 2004L, inaug_year = 2005L, term_years = 2005L:2008L),
  data.table(election_year = 2008L, inaug_year = 2009L, term_years = 2009L:2012L),
  data.table(election_year = 2012L, inaug_year = 2013L, term_years = 2013L:2016L),
  data.table(election_year = 2016L, inaug_year = 2017L, term_years = 2017L:2020L)
))
MAYOR_TERM_MAP <- MAYOR_TERM_MAP[, .(year = term_years), by = .(election_year, inaug_year)]

GOV_TERM_MAP <- rbindlist(list(
  data.table(election_year = 2002L, inaug_year = 2003L, term_years = 2003L:2006L),
  data.table(election_year = 2006L, inaug_year = 2007L, term_years = 2007L:2010L),
  data.table(election_year = 2010L, inaug_year = 2011L, term_years = 2011L:2014L),
  data.table(election_year = 2014L, inaug_year = 2015L, term_years = 2015L:2018L)
))
GOV_TERM_MAP <- GOV_TERM_MAP[, .(year = term_years), by = .(election_year, inaug_year)]

# ---- Load muni panel ---------------------------------------------------------

muni_path <- output_path("muni_panel_for_regs.qs2")
stopifnot(file.exists(muni_path))
message(sprintf("[INFO] %s | loading muni panel...", Sys.time()))
muni <- qs_read(muni_path)
setDT(muni)
muni[, muni_id := as.integer(muni_id)]
muni[, year    := as.integer(year)]
muni <- muni[muni_id > 0L]

# Discover sections.
inst_prefix <- sprintf("Z_mayor_%s_%s_", ALIGNMENT, BASELINE)
sec_cols <- grep(paste0("^", inst_prefix, "[A-Z]$"), names(muni), value = TRUE)
SECTIONS <- sort(sub(paste0("^", inst_prefix), "", sec_cols))
HOLDOUT  <- SECTIONS[length(SECTIONS)]
SECTIONS_KEEP <- setdiff(SECTIONS, HOLDOUT)
message(sprintf("[INFO] K_sections_kept=%d (holdout=%s)",
                length(SECTIONS_KEEP), HOLDOUT))

# Per B1.7 robustness, drop Pres x E + Pres x P from the pres set in B1.8.3.
PRES_DROP_SECTIONS <- c("E", "P")
PRES_SECTIONS_KEEP <- setdiff(SECTIONS_KEEP, PRES_DROP_SECTIONS)

build_inst_cols <- function(office, sections) {
  sprintf("Z_%s_%s_%s_%s", office, ALIGNMENT, BASELINE, sections)
}

# delta_log_gdp.
setorder(muni, muni_id, year)
muni[, delta_log_gdp := log_gdp - shift(log_gdp, type = "lag"),
     by = muni_id]

# =============================================================================
# B1.8.1 -- panel calendar inspection
# =============================================================================

message("[INFO] === B1.8.1: panel calendar inspection ===")

panel_years <- 2002L:2017L
cal <- data.table(year = panel_years)

# e_mayor(t): next mayoral election year >= t (the e such that t is in
# pre-window or in term). For pre-trend semantics: "next" election strictly
# after t when t is pre-period, OR the election that the current term traces
# back to. We compute BOTH:
#   next_mayor_election: min e in MAYOR_ELECTIONS with e >= t (so 2002 -> 2004)
#   current_mayor_inaug: the inauguration year of the term covering t
cal[, next_mayor_election := vapply(year, function(t) {
  cand <- MAYOR_ELECTIONS[MAYOR_ELECTIONS >= t]
  if (!length(cand)) NA_integer_ else min(cand)
}, integer(1))]
cal[, next_gov_election := vapply(year, function(t) {
  cand <- GOV_ELECTIONS[GOV_ELECTIONS >= t]
  if (!length(cand)) NA_integer_ else min(cand)
}, integer(1))]

# Term-covering election (the election whose inauguration year <= t and term
# covers t).
cal <- merge(cal, MAYOR_TERM_MAP[, .(year,
                                     mayor_term_election = election_year,
                                     mayor_term_inaug = inaug_year)],
             by = "year", all.x = TRUE)
cal <- merge(cal, GOV_TERM_MAP[, .(year,
                                   gov_term_election = election_year,
                                   gov_term_inaug = inaug_year)],
             by = "year", all.x = TRUE)

# Mayoral pre-window membership: is t in [e_mayor - 3, e_mayor - 1] for some
# e_mayor in {2004, 2008, 2012, 2016}?
PRE_MAP_MAYOR_B16 <- rbindlist(lapply(c(2004L, 2008L, 2012L, 2016L), function(e) {
  data.table(pre_year = (e - 3L):(e - 1L), ref_election = e)
}))
cal[, in_mayoral_pre_window := year %in% PRE_MAP_MAYOR_B16$pre_year]
cal <- merge(cal,
             PRE_MAP_MAYOR_B16[, .(pre_year, mayoral_pre_for = ref_election)],
             by.x = "year", by.y = "pre_year", all.x = TRUE)

# Diagnostic flag: pre-mayoral-window year that is POST a gov election.
cal[, gov_election_inside_pre_window := vapply(seq_len(.N), function(i) {
  if (!cal$in_mayoral_pre_window[i]) return(FALSE)
  e_m <- cal$mayoral_pre_for[i]
  any(GOV_ELECTIONS >= (e_m - 3L) & GOV_ELECTIONS <= (e_m - 1L))
}, logical(1))]
cal[, year_post_gov_election_within_pre_window := vapply(seq_len(.N), function(i) {
  if (!cal$in_mayoral_pre_window[i]) return(FALSE)
  e_m <- cal$mayoral_pre_for[i]
  contained_govs <- GOV_ELECTIONS[GOV_ELECTIONS >= (e_m - 3L) &
                                  GOV_ELECTIONS <= (e_m - 1L)]
  if (!length(contained_govs)) return(FALSE)
  any(cal$year[i] >= contained_govs)
}, logical(1))]

fwrite(cal, file.path(OUTPUT_BRANCH, "panel_calendar_b181.csv"))
message("[INFO] panel calendar:")
print(cal)

n_pre_yrs <- sum(cal$in_mayoral_pre_window)
n_post_gov_in_pre <- sum(cal$year_post_gov_election_within_pre_window)
n_mayoral_cycles_with_gov_inside <- length(unique(cal[
  gov_election_inside_pre_window == TRUE]$mayoral_pre_for))
message(sprintf("[INFO] B1.8.1: %d of %d mayoral-pre-window years are POST a gov election that fell INSIDE the same mayoral pre-window; %d of 4 mayoral cycles affected.",
                n_post_gov_in_pre, n_pre_yrs, n_mayoral_cycles_with_gov_inside))

timing_claim_holds <- (n_mayoral_cycles_with_gov_inside >= 3L)
message(sprintf("[INFO] B1.8.1 verdict: timing claim %s",
                if (timing_claim_holds) "CONFIRMED" else "REFUTED"))

# =============================================================================
# Helper: run variant-alpha-style test with arbitrary (office, sections,
# pre-window map). pre_map columns: pre_year, ref_election, ref_year.
# =============================================================================

INST_COLS_ALL <- c(
  build_inst_cols("mayor", SECTIONS_KEEP),
  build_inst_cols("gov",   SECTIONS_KEEP),
  build_inst_cols("pres",  SECTIONS_KEEP)
)
stopifnot(all(INST_COLS_ALL %in% names(muni)))

run_alpha_strict <- function(inst_cols, pre_map, label) {
  stopifnot(all(c("pre_year", "ref_election", "ref_year") %in% names(pre_map)))
  fut_cols <- paste0(inst_cols, "_future")

  # Build per-call future-Z lookup keyed on (muni_id, ref_year).
  ref_years <- sort(unique(pre_map$ref_year))
  z_at_ref <- muni[year %in% ref_years,
                   c("muni_id", "year", inst_cols), with = FALSE]
  setnames(z_at_ref, "year", "ref_year")
  setnames(z_at_ref, inst_cols, fut_cols)

  pre <- muni[year %in% pre_map$pre_year,
              c("muni_id", "year", "delta_log_gdp"), with = FALSE]
  pre <- merge(pre, pre_map[, .(pre_year, ref_year)],
               by.x = "year", by.y = "pre_year",
               all.x = TRUE, allow.cartesian = TRUE)
  stopifnot(!any(is.na(pre$ref_year)))

  dat <- merge(pre, z_at_ref, by = c("muni_id", "ref_year"), all.x = TRUE)
  keep <- c("muni_id", "year", "ref_year", "delta_log_gdp", fut_cols)
  dat <- dat[, ..keep]
  dat <- dat[complete.cases(dat)]

  if (!nrow(dat)) {
    message(sprintf("[WARN] [%s] empty sample", label))
    return(list(F = NA_real_, p = NA_real_, n = 0L, m = 0L, k = 0L))
  }

  vars <- vapply(fut_cols, function(cc) var(dat[[cc]], na.rm = TRUE),
                 numeric(1))
  fut_keep <- fut_cols[is.finite(vars) & vars > 0]
  if (!length(fut_keep)) {
    message(sprintf("[WARN] [%s] all future-Z columns have zero variance",
                    label))
    return(list(F = NA_real_, p = NA_real_, n = nrow(dat),
                m = uniqueN(dat$muni_id), k = 0L))
  }

  # FE selection: muni FE only meaningful if at least some munis appear in >1
  # ref_election cycle in the sample (otherwise Z constant within muni in the
  # restricted window).
  n_ref_per_muni <- dat[, uniqueN(ref_year), by = muni_id]
  use_muni_fe <- max(n_ref_per_muni$V1) > 1L
  has_year_var <- uniqueN(dat$year) > 1L

  rhs <- paste(fut_keep, collapse = " + ")
  fe_parts <- character()
  if (use_muni_fe)  fe_parts <- c(fe_parts, "muni_id")
  if (has_year_var) fe_parts <- c(fe_parts, "year")
  fml <- if (length(fe_parts)) {
    as.formula(sprintf("delta_log_gdp ~ %s | %s", rhs,
                       paste(fe_parts, collapse = " + ")))
  } else {
    as.formula(sprintf("delta_log_gdp ~ %s", rhs))
  }
  mod <- feols(fml, data = dat,
               vcov = as.formula(paste0("~ ", CLUSTER_VAR)),
               lean = TRUE)

  z_pattern <- "^Z_(mayor|gov|pres)_.*_future$"
  w <- fixest::wald(mod, keep = z_pattern, print = FALSE)
  message(sprintf("[INFO] [%s] n=%s munis=%s k=%d F=%.4f p=%.4g (FE: %s)",
                  label,
                  format(nobs(mod), big.mark = ","),
                  format(uniqueN(dat$muni_id), big.mark = ","),
                  length(fut_keep),
                  as.numeric(w$stat), as.numeric(w$p),
                  if (length(fe_parts)) paste(fe_parts, collapse = "+") else "none"))
  list(F = as.numeric(w$stat), p = as.numeric(w$p),
       n = nobs(mod), m = uniqueN(dat$muni_id), k = length(fut_keep),
       fe = paste(fe_parts, collapse = "+"))
}

# Build pre-maps per office. ref_year is chosen as e+1 (first post-inauguration
# panel year), which lies inside the cycle-specific term and therefore returns
# the Z value tied to election year e.
make_pre_map <- function(elections_in_panel, panel_min = 2002L,
                         panel_max = 2017L) {
  rows <- lapply(elections_in_panel, function(e) {
    pre <- (e - 3L):(e - 1L)
    pre <- pre[pre >= panel_min & pre <= panel_max]
    if (!length(pre)) return(NULL)
    rf <- e + 1L
    if (rf < panel_min || rf > panel_max) return(NULL)
    data.table(pre_year = pre, ref_election = e, ref_year = rf)
  })
  rbindlist(rows[!vapply(rows, is.null, logical(1))])
}

PRE_MAP_GOV   <- make_pre_map(GOV_ELECTIONS)
PRE_MAP_MAYOR <- make_pre_map(MAYOR_ELECTIONS)
PRE_MAP_PRES  <- make_pre_map(PRES_ELECTIONS)

message("[INFO] PRE_MAP_GOV:");   print(PRE_MAP_GOV)
message("[INFO] PRE_MAP_MAYOR:"); print(PRE_MAP_MAYOR)
message("[INFO] PRE_MAP_PRES:");  print(PRE_MAP_PRES)

# =============================================================================
# B1.8.2 -- gov-only variant-alpha with strict pre-gov-election timing
# =============================================================================

message("[INFO] === B1.8.2: gov-only strict-timing variant-alpha ===")

gov_cols <- build_inst_cols("gov", SECTIONS_KEEP)

# Pooled gov-only strict.
b182_pooled <- run_alpha_strict(gov_cols, PRE_MAP_GOV, "B1.8.2_gov_pooled_strict")

# Per-cycle gov-only strict.
b182_rows <- list(
  data.table(scope = "pooled", election_cycle = NA_integer_,
             n_obs = b182_pooled$n, n_munis = b182_pooled$m,
             k_instruments = b182_pooled$k,
             joint_F = b182_pooled$F, joint_p = b182_pooled$p,
             rejects_5pc = isTRUE(b182_pooled$p < 0.05),
             fe = b182_pooled$fe)
)
for (e in unique(PRE_MAP_GOV$ref_election)) {
  pm_e <- PRE_MAP_GOV[ref_election == e]
  r <- run_alpha_strict(gov_cols, pm_e,
                        sprintf("B1.8.2_gov_cycle_%d_strict", e))
  b182_rows[[length(b182_rows) + 1L]] <- data.table(
    scope = "per_cycle", election_cycle = e,
    n_obs = r$n, n_munis = r$m, k_instruments = r$k,
    joint_F = r$F, joint_p = r$p,
    rejects_5pc = isTRUE(r$p < 0.05),
    fe = r$fe
  )
}
b182_dt <- rbindlist(b182_rows)
fwrite(b182_dt, file.path(OUTPUT_BRANCH, "gov_strict_timing_pretrend.csv"))
print(b182_dt)

b182_pooled_pass <- isTRUE(b182_pooled$p > 0.05)
message(sprintf("[INFO] B1.8.2 verdict: gov-only strict-timing %s (pooled p=%.4g)",
                if (b182_pooled_pass) "PASSES" else "STILL REJECTS",
                b182_pooled$p))

# =============================================================================
# B1.8.3 -- per-office variant-alpha with each office's strict pre-window
# =============================================================================

message("[INFO] === B1.8.3: per-office strict-timing variant-alpha ===")

mayor_cols <- build_inst_cols("mayor", SECTIONS_KEEP)
pres_cols_full    <- build_inst_cols("pres",  SECTIONS_KEEP)
pres_cols_cleaned <- build_inst_cols("pres",  PRES_SECTIONS_KEEP)

b183_specs <- list(
  list(label = "B1.8.3_mayor_strict",  office = "mayor",
       inst = mayor_cols, pmap = PRE_MAP_MAYOR,
       z_set = "mayor_full"),
  list(label = "B1.8.3_gov_strict",    office = "gov",
       inst = gov_cols,   pmap = PRE_MAP_GOV,
       z_set = "gov_full"),
  list(label = "B1.8.3_pres_strict_full", office = "pres",
       inst = pres_cols_full,    pmap = PRE_MAP_PRES,
       z_set = "pres_full"),
  list(label = "B1.8.3_pres_strict_cleaned", office = "pres",
       inst = pres_cols_cleaned, pmap = PRE_MAP_PRES,
       z_set = "pres_minus_E_P")
)

b183_rows <- list()
for (spec in b183_specs) {
  r <- run_alpha_strict(spec$inst, spec$pmap, spec$label)
  b183_rows[[length(b183_rows) + 1L]] <- data.table(
    test = spec$label, office = spec$office, z_set = spec$z_set,
    n_obs = r$n, n_munis = r$m, k_instruments = r$k,
    joint_F = r$F, joint_p = r$p,
    rejects_5pc = isTRUE(r$p < 0.05),
    fe = r$fe
  )
}
b183_dt <- rbindlist(b183_rows)
fwrite(b183_dt, file.path(OUTPUT_BRANCH, "by_office_strict_timing.csv"))
print(b183_dt)

mayor_pass <- isTRUE(b183_dt[office == "mayor", joint_p] > 0.05)
gov_pass   <- isTRUE(b183_dt[office == "gov",   joint_p] > 0.05)
pres_pass_cleaned <- isTRUE(b183_dt[z_set == "pres_minus_E_P", joint_p] > 0.05)

# =============================================================================
# Classification
# =============================================================================

artifact_confirmed <- b182_pooled_pass && mayor_pass && gov_pass &&
                       pres_pass_cleaned
artifact_refuted   <- !b182_pooled_pass

classification <- if (artifact_confirmed) {
  "ARTIFACT CONFIRMED -- gov pre-trend rejection in B1.6/B1.7 is a mayoral-cycle timing-alignment specification artifact. Each office's pre-trend, tested against its OWN strict pre-election window, clears at 5%."
} else if (artifact_refuted) {
  "REFUTED -- gov-only strict-timing pre-trend still rejects. The hypothesis fails; the gov pre-trend is not a mayoral-cycle alignment artifact and requires a different fix (instrument re-construction or AR re-design)."
} else {
  "MIXED -- gov strict-timing clears but at least one other office still fails under its own strict window; partial support for the artifact story."
}

recommendation <- if (artifact_confirmed) {
  "PROCEED with Phase 2 dispatch using the corrected variant-alpha formulation (per-office strict pre-election windows) as the methodology-note pre-trend test."
} else if (artifact_refuted) {
  "ESCALATE to user -- the gov pre-trend is genuine and requires Z_gov reconstruction or an alternative identification design."
} else {
  "PAUSE -- partial support warrants strategist review before Phase 2 dispatch."
}

message(sprintf("[INFO] === %s ===", classification))
message(sprintf("[INFO] Recommendation: %s", recommendation))

# =============================================================================
# Markdown summary
# =============================================================================

fmt <- function(x, digits = 4L) {
  if (!is.finite(x)) return("NA")
  formatC(x, format = "g", digits = digits)
}

md <- c(
  "# Phase 1.8 -- Gov-Cycle Alignment Hypothesis Test",
  "",
  sprintf("**Date:** %s", format(Sys.time(), "%Y-%m-%d %H:%M")),
  "**Outcome:** Delta log_gdp",
  "**FE:** muni_id + year (single-cycle subsets: year FE only; Z constant within muni-cycle)",
  "**SE:** cluster on muni_id",
  "",
  "## B1.8.1 -- Panel calendar inspection",
  "",
  "Brazilian electoral schedule:",
  sprintf("- Mayoral elections: %s",
          paste(MAYOR_ELECTIONS, collapse = ", ")),
  sprintf("- Gov/Pres elections: %s",
          paste(GOV_ELECTIONS, collapse = ", ")),
  "",
  "Mayoral pre-window {e_mayor-3, e_mayor-1} membership and whether a gov",
  "election falls inside that window:",
  "",
  sprintf("- Pre-window years in panel 2002-2017: %d", n_pre_yrs),
  sprintf("- Pre-window years that are POST a gov election falling inside the same mayoral pre-window: %d",
          n_post_gov_in_pre),
  sprintf("- Mayoral cycles affected (out of 4 with full pre-window in panel): %d",
          n_mayoral_cycles_with_gov_inside),
  "",
  sprintf("**Timing claim:** %s.",
          if (timing_claim_holds) "**CONFIRMED**" else "**REFUTED**"),
  "",
  "See `panel_calendar_b181.csv` for the full year-by-year table.",
  "",
  "## B1.8.2 -- Gov-only variant-alpha with strict pre-gov-election timing",
  "",
  "Restrict tau to [e_gov-3, e_gov-1] for each gov cycle e_gov in {2002, 2006,",
  "2010, 2014}; gov-Z columns only; muni+year FE pooled, year-only FE per-cycle.",
  "",
  "| Scope | Cycle | n_obs | k | joint F | joint p | reject 5% | FE |",
  "|---|---|---|---|---|---|---|---|"
)
for (i in seq_len(nrow(b182_dt))) {
  md <- c(md, sprintf("| %s | %s | %s | %d | %s | %s | %s | %s |",
                      b182_dt$scope[i],
                      if (is.na(b182_dt$election_cycle[i])) "--"
                      else as.character(b182_dt$election_cycle[i]),
                      format(b182_dt$n_obs[i], big.mark = ","),
                      b182_dt$k_instruments[i],
                      fmt(b182_dt$joint_F[i]),
                      fmt(b182_dt$joint_p[i]),
                      b182_dt$rejects_5pc[i],
                      b182_dt$fe[i]))
}
md <- c(md, "",
        sprintf("**Verdict:** gov-only strict-timing %s (pooled p = %s).",
                if (b182_pooled_pass) "**PASSES**" else "**STILL REJECTS**",
                fmt(b182_pooled$p)))

md <- c(md, "",
        "## B1.8.3 -- Per-office strict-timing variant-alpha",
        "",
        "Each office's pre-trend tested against its OWN pre-election window:",
        "- Mayor: tau in [e_mayor-3, e_mayor-1], e_mayor in {2004,2008,2012,2016}",
        "- Gov:   tau in [e_gov-3,   e_gov-1],   e_gov   in {2002,2006,2010,2014}",
        "- Pres:  tau in [e_pres-3,  e_pres-1],  e_pres  in {2002,2006,2010,2014};",
        "  reported with full pres-Z set and with Pres x E, Pres x P dropped (B1.7).",
        "",
        "| Test | Office | Z-set | n_obs | k | joint F | joint p | reject 5% | FE |",
        "|---|---|---|---|---|---|---|---|---|")
for (i in seq_len(nrow(b183_dt))) {
  md <- c(md, sprintf("| %s | %s | %s | %s | %d | %s | %s | %s | %s |",
                      b183_dt$test[i], b183_dt$office[i], b183_dt$z_set[i],
                      format(b183_dt$n_obs[i], big.mark = ","),
                      b183_dt$k_instruments[i],
                      fmt(b183_dt$joint_F[i]),
                      fmt(b183_dt$joint_p[i]),
                      b183_dt$rejects_5pc[i],
                      b183_dt$fe[i]))
}

md <- c(md, "",
        "## Classification",
        "",
        sprintf("**%s**", classification),
        "",
        sprintf("**Recommendation for Phase 2 gate:** %s", recommendation),
        "",
        "## Method note",
        "",
        "The B1.6/B1.7 variant-alpha test uses the mayoral pre-window for all",
        "offices, conflating timing across the three electoral calendars. The",
        "GPSS / BHJ pre-trend assumption is office-specific: each instrument's",
        "shock Z^office_{m,e} should be tested against the pre-period for that",
        "office's own election cycle e. Pooling all three offices into the",
        "mayoral window mechanically conflates the legitimate gov-cycle effect",
        "(which is causally identified by the mayoral cycle's pre-window because",
        "the gov election falls INSIDE it) with a pre-trend violation. The",
        "B1.8 strict-timing reformulation is the correct null.",
        "")

writeLines(md, file.path(OUTPUT_BRANCH, "pretrend_b18_summary.md"))
message(sprintf("[INFO] wrote: %s",
                file.path(OUTPUT_BRANCH, "pretrend_b18_summary.md")))
message(sprintf("[INFO] %s | done.", Sys.time()))
