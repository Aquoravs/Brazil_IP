#!/usr/bin/env Rscript

# ==============================================================================
# Build Alignment Turnover Shocks
# ==============================================================================
# Extract political alignment status at (municipality, party, year) level,
# standardize level names to align_*, build requested overlap states, and
# compute year-over-year changes:
#   dAlign_{p,t} = Align_{p,t} - Align_{p,t-1}
#
# Non-zero shocks occur only at inauguration years:
#   Mayors:          2001, 2005, 2009, 2013, 2017
#   Governors/Pres:  2003, 2007, 2011, 2015, 2019
#
# Output includes both LEVELS (align_*) and CHANGES (dalign_*), at party and
# coalition level, for all three government tiers plus requested overlap states.
# Overlap states include joint alignment and "only" variants that exclude triple
# alignment:
#   mayor_gov       = mayor * gov
#   mayor_gov_only  = mayor * gov * (1 - pres)
#   mayor_pres      = mayor * pres
#   mayor_pres_only = mayor * pres * (1 - gov)
#   triple          = mayor * gov * pres
#
# Input:  raw/david_ra/in_power_upd_2002_2019.qs2
#         Already at (year, party, muni) level with raw columns:
#         mayor_in_power_party, mayor_in_power_coalition,
#         gov_in_power_party, gov_in_power_coalition,
#         pres_in_power_party, pres_in_power_coalition
#
# Dependencies: raw political turnover data
# ==============================================================================

cat("==============================================================================\n")
cat("Building Alignment Turnover Shocks\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})

# Bootstrap shared path helpers from this script location.
bootstrap_file <- local({
  project_root_opt <- getOption("politicsregs.project_root", default = NULL)
  if (is.character(project_root_opt) && length(project_root_opt) == 1L && nzchar(project_root_opt)) {
    return(file.path(project_root_opt, "scripts", "R", "_utils", "script_bootstrap.R"))
  }

  script_args_full <- commandArgs(trailingOnly = FALSE)
  script_file <- grep("^--file=", script_args_full, value = TRUE)
  if (length(script_file)) {
    script_file <- normalizePath(sub("^--file=", "", script_file[[1]]), winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }

  frame_paths <- vapply(sys.frames(), function(env) {
    ofile <- env$ofile
    if (is.null(ofile) || !nzchar(ofile)) return(NA_character_)
    ofile
  }, character(1))
  frame_paths <- frame_paths[!is.na(frame_paths)]
  if (length(frame_paths)) {
    script_file <- normalizePath(frame_paths[[length(frame_paths)]], winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }

  stop("Cannot determine bootstrap path. In an interactive session, call `init_politicsregs_session()` first.")
})
source(normalizePath(bootstrap_file, winslash = "/", mustWork = TRUE))
bootstrap_politicsregs()

setDTthreads(0)

# --- Configuration -----------------------------------------------------------

aff_path <- make_base_path("raw/david_ra/in_power_upd_2002_2019.qs2")

out_path     <- make_output_path("alignment_shocks.qs2")
summary_path <- make_output_path("alignment_shocks_summary.csv")

raw_power_cols <- c(
  "mayor_in_power_party", "mayor_in_power_coalition",
  "gov_in_power_party",   "gov_in_power_coalition",
  "pres_in_power_party",  "pres_in_power_coalition"
)

canonical_power_map <- c(
  mayor_in_power_party = "align_mayor_party",
  mayor_in_power_coalition = "align_mayor_coalition",
  gov_in_power_party = "align_gov_party",
  gov_in_power_coalition = "align_gov_coalition",
  pres_in_power_party = "align_pres_party",
  pres_in_power_coalition = "align_pres_coalition"
)

# --- Step 1: Load alignment data ---------------------------------------------

cat("Step 1: Loading alignment data...\n")

if (!file.exists(aff_path)) {
  stop("Alignment data not found: ", aff_path)
}

cat("  Source:", basename(aff_path), "(muni-party-year level)\n")
align_dt <- qs_read(aff_path)
setDT(align_dt)
cat("  Loaded:", nrow(align_dt), "rows,", ncol(align_dt), "cols\n")
cat("  Columns:", paste(names(align_dt), collapse = ", "), "\n")

muni_src <- intersect(c("muni_id_ibge6", "muni_id_ibge", "muni_id"), names(align_dt))[1]
if (is.na(muni_src)) {
  stop("No municipality column found. Available: ", paste(names(align_dt), collapse = ", "))
}
if (muni_src != "muni_id") setnames(align_dt, muni_src, "muni_id")
align_dt[, muni_id := {
  m <- as.character(muni_id)
  as.integer(ifelse(nchar(m) == 7, substr(m, 1, 6), m))
}]

yr_col <- intersect(c("year", "ano"), names(align_dt))[1]
if (is.na(yr_col)) stop("No year column found.")
if (yr_col != "year") setnames(align_dt, yr_col, "year")
align_dt[, year := as.integer(year)]

pty_col <- intersect(c("party", "sigla_partido"), names(align_dt))[1]
if (is.na(pty_col)) stop("No party column found.")
if (pty_col != "party") setnames(align_dt, pty_col, "party")
align_dt[, party := trimws(as.character(party))]

pc_present_raw <- intersect(raw_power_cols, names(align_dt))
if (!length(pc_present_raw)) {
  stop("No power-flag columns found. Available: ", paste(names(align_dt), collapse = ", "))
}
for (pc in pc_present_raw) {
  align_dt[, (pc) := {
    v <- as.integer(get(pc))
    v[is.na(v)] <- 0L
    v
  }]
}

align_dt <- align_dt[, c("muni_id", "party", "year", pc_present_raw), with = FALSE]
setnames(align_dt, old = pc_present_raw, new = unname(canonical_power_map[pc_present_raw]))

align_dt <- align_dt[year >= 2002 & year <= 2019]
# Drop invalid muni_id (0 is not a valid IBGE municipality code)
n_invalid_muni <- sum(align_dt$muni_id == 0L | is.na(align_dt$muni_id))
if (n_invalid_muni > 0L) {
  cat(sprintf("  Dropping %d rows with invalid muni_id (0 or NA)\n", n_invalid_muni))
  align_dt <- align_dt[!is.na(muni_id) & muni_id > 0L]
}
align_dt <- unique(align_dt, by = c("muni_id", "party", "year"))

cat("  After standardization:", nrow(align_dt), "rows\n")
cat("\n  Alignment panel:", nrow(align_dt), "rows\n")
cat("  Unique municipalities:", uniqueN(align_dt$muni_id), "\n")
cat("  Unique parties:", uniqueN(align_dt$party), "\n")
cat("  Year range:", paste(range(align_dt$year), collapse = "-"), "\n")

# --- Step 2: Build overlap levels --------------------------------------------

cat("\nStep 2: Building overlap alignment levels...\n")

for (align_type in c("party", "coalition")) {
  mayor_col <- paste0("align_mayor_", align_type)
  gov_col   <- paste0("align_gov_", align_type)
  pres_col  <- paste0("align_pres_", align_type)

  required_cols <- c(mayor_col, gov_col, pres_col)
  if (!all(required_cols %in% names(align_dt))) {
    stop("Missing canonical align columns for overlap construction: ",
         paste(setdiff(required_cols, names(align_dt)), collapse = ", "))
  }

  align_dt[, (paste0("align_mayor_gov_", align_type)) :=
             as.integer(get(mayor_col) * get(gov_col))]
  align_dt[, (paste0("align_mayor_gov_only_", align_type)) :=
             as.integer(get(mayor_col) * get(gov_col) * (1L - get(pres_col)))]
  align_dt[, (paste0("align_mayor_pres_", align_type)) :=
             as.integer(get(mayor_col) * get(pres_col))]
  align_dt[, (paste0("align_mayor_pres_only_", align_type)) :=
             as.integer(get(mayor_col) * get(pres_col) * (1L - get(gov_col)))]
  align_dt[, (paste0("align_triple_", align_type)) :=
             as.integer(get(mayor_col) * get(gov_col) * get(pres_col))]
}

align_cols <- grep("^align_", names(align_dt), value = TRUE)
cat("  align_ columns:", paste(align_cols, collapse = ", "), "\n")

# --- Step 3: Compute changes -------------------------------------------------

cat("\nStep 3: Computing alignment changes (dalign)...\n")

setorder(align_dt, muni_id, party, year)

for (ac in align_cols) {
  dcol <- sub("^align_", "dalign_", ac)
  align_dt[, (dcol) := get(ac) - shift(get(ac), n = 1L, type = "lag"),
           by = .(muni_id, party)]
}

dalign_cols <- grep("^dalign_", names(align_dt), value = TRUE)
first_year_mask <- align_dt[, .I[1], by = .(muni_id, party)]$V1
align_dt <- align_dt[-first_year_mask]

for (dc in dalign_cols) {
  align_dt[is.na(get(dc)), (dc) := 0L]
}

cat("  After differencing:", nrow(align_dt), "rows\n")
cat("  dalign_ columns:", paste(dalign_cols, collapse = ", "), "\n")

# --- Step 4: Diagnostics ----------------------------------------------------

cat("\nStep 4: Diagnostics...\n")

for (ac in align_cols) {
  n_one  <- sum(align_dt[[ac]] == 1L, na.rm = TRUE)
  n_zero <- sum(align_dt[[ac]] == 0L, na.rm = TRUE)
  cat(sprintf("  %s:  1=%d  0=%d\n", ac, n_one, n_zero))
}

for (dc in dalign_cols) {
  n_pos  <- sum(align_dt[[dc]] > 0, na.rm = TRUE)
  n_neg  <- sum(align_dt[[dc]] < 0, na.rm = TRUE)
  n_zero <- sum(align_dt[[dc]] == 0, na.rm = TRUE)
  cat(sprintf("  %s:  +1=%d  -1=%d  0=%d\n", dc, n_pos, n_neg, n_zero))
}

if ("dalign_mayor_party" %in% names(align_dt)) {
  cat("\n  Mayor party shocks by year:\n")
  mayor_shocks <- align_dt[dalign_mayor_party != 0, .N, by = year]
  setorder(mayor_shocks, year)
  print(mayor_shocks)
}

if ("dalign_gov_party" %in% names(align_dt)) {
  cat("\n  Governor party shocks by year:\n")
  gov_shocks <- align_dt[dalign_gov_party != 0, .N, by = year]
  setorder(gov_shocks, year)
  print(gov_shocks)
}

# --- Step 5: Save ------------------------------------------------------------

cat("\nStep 5: Saving...\n")

setorder(align_dt, year, muni_id, party)

qs_save(align_dt, out_path)

summ <- data.table(
  variable = dalign_cols,
  n_positive = sapply(dalign_cols, function(dc) sum(align_dt[[dc]] > 0)),
  n_negative = sapply(dalign_cols, function(dc) sum(align_dt[[dc]] < 0)),
  n_zero     = sapply(dalign_cols, function(dc) sum(align_dt[[dc]] == 0)),
  mean_shock = sapply(dalign_cols, function(dc) mean(align_dt[[dc]])),
  sd_shock   = sapply(dalign_cols, function(dc) sd(align_dt[[dc]]))
)
fwrite(summ, summary_path)

cat(sprintf("  Saved %s (%.2f MB)\n", out_path, file.size(out_path) / 1024^2))
cat(sprintf("  Saved %s\n", summary_path))

cat("\nAlignment shocks complete.\n")
