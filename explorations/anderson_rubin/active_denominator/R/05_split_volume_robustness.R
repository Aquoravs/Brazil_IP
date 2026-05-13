#!/usr/bin/env Rscript

# ==============================================================================
# 05_split_volume_robustness.R
# B1.4.3 - Split-volume robustness for the AR test (headline spec only).
#
# Goal. Phase 3 will properly build bndes_total_RAIS / bndes_total_nonRAIS /
# bndes_total_public columns in production script 41. Phase 1 sanity-checks the
# AR rejection under a split-volume specification using the recipient-class
# logic from the A0.4 audit. The pass criterion (per plan §B1.4 / D3.3) is that
# the rejection region is qualitatively stable when the joint volume term is
# decomposed into three separate volume terms entered jointly:
#   - productive_volume = sum(value_dis | recipient_class == "productive_firm")
#   - public_volume     = sum(value_dis | recipient_class == "public_entity")
#   - fi_volume         = sum(value_dis | recipient_class == "financial_institution")
# all normalized by initial_gdp_m,0 (the baseline volume-control denominator).
#
# Reclassification.
#   Mirror of explorations/firm_universe/bndes_recipient_audit/R/
#   audit_bndes_recipients.R classification rules (lines 175-191):
#     priority: public-entity > financial-institution > productive-firm > other
#     financial_institution: CNAE division 2 in {64, 65, 66}
#     productive_firm: nature == "PRIVADA" AND has CNAE section
#     public_entity: nature starts with "PUBLICA" OR "ADMINISTRACAO PUBLICA"
#                    OR CNAE section == "O"
#   The cached `data/processed/bndes_loan_level.qs2` is post-PRIVADA-filter and
#   therefore drops public-entity loans (28.3% of total disbursement per A0.4).
#   We re-read raw to recover the full universe.
#
#   Aggregates cached to output/muni_year_class_aggregate.csv so the AR loop
#   does not re-read raw on rerun.
#
# AR runs.
#   1) Joint: bndes_total_mt / initial_gdp (baseline, matches 02_*.R headline).
#   2) Split: three separate productive_vol / public_vol / fi_vol terms, each
#      normalized by initial_gdp, entered jointly.
# Headline cell: contemporaneous + MGP + muni_year FE + log_gdp outcome.
#
# Output: output/split_volume_ar.csv
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
  library(readxl)
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
stopifnot(dir.exists(OUTPUT_BRANCH))

set.seed(20260512L)
setDTthreads(0L)
fixest::setFixest_nthreads(4L)

# ---- Build muni-year-class aggregate from raw (cached) ----------------------

CACHE_PATH <- file.path(OUTPUT_BRANCH, "muni_year_class_aggregate.csv")

clean_cnpj <- function(x) {
  d <- gsub("\\D", "", as.character(x))
  d[nchar(d) == 0] <- NA_character_
  d
}
clean_currency <- function(x) {
  if (is.numeric(x)) return(x)
  x <- trimws(as.character(x))
  x[x %chin% c("", "ND", "NA")] <- NA_character_
  x <- gsub(".", "", x, fixed = TRUE)
  x <- gsub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}
ascii_upper <- function(x) toupper(iconv(trimws(as.character(x)),
                                          to = "ASCII//TRANSLIT"))
parse_date_col <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  if (is.numeric(x)) return(as.Date(round(x), origin = "1899-12-30"))
  s <- trimws(as.character(x)); s[s == ""] <- NA_character_
  out <- suppressWarnings(as.Date(s, format = "%Y-%m-%d"))
  m <- is.na(out) & !is.na(s)
  if (any(m)) out[m] <- suppressWarnings(as.Date(s[m], format = "%d/%m/%Y"))
  out
}

build_muni_year_class <- function() {
  raw_auto_dir <- file.path(PROJECT_ROOT, "data", "raw", "bndes_indirect_auto")
  raw_nonauto  <- file.path(PROJECT_ROOT, "data", "raw",
                            "bndes_direct_and_indirect_nonauto",
                            "naoautomaticas.xlsx")
  stopifnot(dir.exists(raw_auto_dir), file.exists(raw_nonauto))

  auto_cols <- c("client","cnpj_raw","uf","muni_name","muni_id_ibge","date",
                 "value_op","value_dis","source","fin_cost","rate",
                 "length1","length2","modality","form_support","product",
                 "instrument","innovation","area","sector_cnae",
                 "subsector_cnae_group","subsector_cnae_cod",
                 "subsector_cnae_name","sector_bndes","subsector_bndes",
                 "size","nature","fin_inst","fin_inst_cnpj","status")
  nonauto_cols <- c("client","cnpj_raw","proj_desc","uf","muni_name",
                    "muni_id_ibge","contract","date","value_op","value_dis",
                    "source","fin_cost","rate","length1","length2",
                    "modality","form_support","product","instrument",
                    "innovation","area","sector_cnae","subsector_cnae_group",
                    "subsector_cnae_cod","subsector_cnae_name","sector_bndes",
                    "subsector_bndes","size","nature","fin_inst",
                    "fin_inst_cnpj","type_guarantee","type_excep","status")

  read_one <- function(path, names_vec, skip = 4L) {
    message(sprintf("[INFO]   reading %s", basename(path)))
    ext <- tolower(tools::file_ext(path))
    dt <- switch(ext,
      "csv"  = fread(path, skip = skip, header = TRUE, encoding = "Latin-1"),
      "xlsx" = setDT(read_xlsx(path, skip = skip, col_names = TRUE)),
      stop("Unsupported: ", ext)
    )
    setnames(dt, names_vec[seq_len(ncol(dt))])
    if ("date" %in% names(dt) && !is.character(dt[["date"]])) {
      dt[, date := as.character(date)]
    }
    dt
  }

  message(sprintf("[INFO] %s | loading raw BNDES files (auto+nonauto)",
                  Sys.time()))
  auto_files <- sort(list.files(
    raw_auto_dir,
    pattern = "operacoes_indiretas_automaticas_.*\\.(xlsx|csv)$",
    full.names = TRUE, ignore.case = TRUE))
  auto_list <- lapply(auto_files, read_one, names_vec = auto_cols, skip = 4L)
  automatic <- rbindlist(auto_list, use.names = TRUE, fill = TRUE)
  rm(auto_list); gc()
  nonautomatic <- read_one(raw_nonauto, nonauto_cols, skip = 4L)
  loans <- rbind(automatic, nonautomatic, fill = TRUE)
  rm(automatic, nonautomatic); gc()
  message(sprintf("[INFO] raw combined: %d rows", nrow(loans)))

  loans[, value_dis := clean_currency(value_dis)]
  loans[, date_parsed := parse_date_col(date)]
  loans[, year := as.integer(format(date_parsed, "%Y"))]
  loans[, muni_id := as.integer(floor(suppressWarnings(
         as.numeric(gsub("\\D", "", as.character(muni_id_ibge)))) / 10))]
  loans[, nature_u := ascii_upper(nature)]
  loans[, cnae_section := substr(trimws(as.character(subsector_cnae_cod)), 1, 1)]
  loans[cnae_section == "", cnae_section := NA_character_]
  loans[, cnae_code_clean := trimws(as.character(subsector_cnae_cod))]
  loans[, cnae_div2 := {
    sl <- grepl("^[A-Za-z]", cnae_code_clean)
    d <- ifelse(sl, substr(cnae_code_clean, 2, 3),
                    substr(cnae_code_clean, 1, 2))
    suppressWarnings(as.integer(d))
  }]
  loans <- loans[!is.na(year) & year >= 2002L & year <= 2017L]

  # Classification (mirror audit script).
  loans[, recipient_class := "other"]
  loans[!is.na(cnae_div2) & cnae_div2 %in% 64:66,
        recipient_class := "financial_institution"]
  loans[!is.na(nature_u) & nature_u == "PRIVADA" &
        !is.na(cnae_section) & recipient_class == "other",
        recipient_class := "productive_firm"]
  loans[, is_public_nature := !is.na(nature_u) & (
          startsWith(nature_u, "PUBLICA") |
          startsWith(nature_u, "ADMINISTRACAO PUBLICA"))]
  loans[is_public_nature | (!is.na(cnae_section) & cnae_section == "O"),
        recipient_class := "public_entity"]

  agg <- loans[!is.na(muni_id) & !is.na(value_dis),
               .(value_dis = sum(value_dis, na.rm = TRUE), n_loans = .N),
               by = .(muni_id, year, recipient_class)]
  message(sprintf("[INFO] muni-year-class agg: %d rows", nrow(agg)))
  fwrite(agg, CACHE_PATH)
  message(sprintf("[INFO] wrote: %s", CACHE_PATH))
  agg
}

if (file.exists(CACHE_PATH)) {
  message(sprintf("[INFO] using cached %s", CACHE_PATH))
  class_agg <- fread(CACHE_PATH)
} else {
  class_agg <- build_muni_year_class()
}
class_agg[, muni_id := as.integer(muni_id)]
class_agg[, year    := as.integer(year)]

# Wide form: one column per recipient_class.
class_wide <- dcast(
  class_agg[recipient_class %in% c("productive_firm", "public_entity",
                                    "financial_institution")],
  muni_id + year ~ recipient_class,
  value.var = "value_dis", fill = 0
)
setnames(class_wide,
         c("productive_firm", "public_entity", "financial_institution"),
         c("productive_vol_nom", "public_vol_nom", "fi_vol_nom"),
         skip_absent = TRUE)
for (c in c("productive_vol_nom", "public_vol_nom", "fi_vol_nom")) {
  if (!c %in% names(class_wide)) class_wide[, (c) := 0]
}

# ---- Load muni panel + apply same volume-normalization logic ----------------

muni_path <- output_path("muni_panel_for_regs.qs2")
stopifnot(file.exists(muni_path))
message(sprintf("[INFO] %s | loading muni panel...", Sys.time()))
muni <- qs_read(muni_path)
setDT(muni)
muni[, muni_id := as.integer(muni_id)]
muni[, year    := as.integer(year)]
muni <- muni[muni_id > 0L]

inst_prefix <- sprintf("Z_mayor_coalition_cycle_specific_")
sec_cols <- grep(paste0("^", inst_prefix, "[A-Z]$"), names(muni), value = TRUE)
SECTIONS <- sort(sub(paste0("^", inst_prefix), "", sec_cols))
HOLDOUT  <- SECTIONS[length(SECTIONS)]
SECTIONS_KEEP <- setdiff(SECTIONS, HOLDOUT)

OFFICES <- c("mayor", "gov", "pres")
ALIGNMENT <- "coalition"; BASELINE <- "cycle_specific"
build_inst_cols <- function(offices, sections) {
  out <- character()
  for (off in offices) for (s in sections) {
    out <- c(out, sprintf("Z_%s_%s_%s_%s", off, ALIGNMENT, BASELINE, s))
  }
  out
}
INST_COLS <- build_inst_cols(OFFICES, SECTIONS_KEEP)
stopifnot(all(INST_COLS %in% names(muni)))

# Initial GDP (same as 02_*.R).
setorder(muni, muni_id, year)
init_gdp <- muni[!is.na(pib_real),
                 .(initial_gdp = pib_real[1L]), by = muni_id]
muni <- merge(muni, init_gdp, by = "muni_id", all.x = TRUE)
muni[, vol_ratio := total_bndes_real / initial_gdp]
muni[!is.finite(vol_ratio), vol_ratio := NA_real_]

# Merge in class aggregates. The class data is *nominal* (not deflated). The
# baseline `vol_ratio` uses `total_bndes_real` (deflated 2018 BRL). For the
# split, we apply the same nominal-to-real deflator by leveraging an aggregate
# ratio: real_total / nominal_total per year (a year-only deflator). This is an
# approximation but preserves cross-muni comparability per year, which is what
# enters the regression.
muni_nom_real <- muni[!is.na(total_bndes_real) & year >= 2002L & year <= 2017L,
                      .(real_total = sum(total_bndes_real, na.rm = TRUE)),
                      by = year]
class_yr_tot <- class_agg[, .(nom_total = sum(value_dis, na.rm = TRUE)),
                          by = year]
deflators <- merge(muni_nom_real, class_yr_tot, by = "year")
deflators[, defl := fifelse(nom_total > 0, real_total / nom_total, NA_real_)]
class_wide <- merge(class_wide, deflators[, .(year, defl)],
                    by = "year", all.x = TRUE)
class_wide[, productive_vol_real := productive_vol_nom * defl]
class_wide[, public_vol_real     := public_vol_nom     * defl]
class_wide[, fi_vol_real         := fi_vol_nom         * defl]

dat <- merge(muni, class_wide[, .(muni_id, year,
                                   productive_vol_real, public_vol_real,
                                   fi_vol_real)],
             by = c("muni_id", "year"), all.x = TRUE)
for (c in c("productive_vol_real", "public_vol_real", "fi_vol_real")) {
  dat[is.na(get(c)), (c) := 0]
}
dat[, prod_ratio   := productive_vol_real / initial_gdp]
dat[, public_ratio := public_vol_real     / initial_gdp]
dat[, fi_ratio     := fi_vol_real         / initial_gdp]
for (c in c("prod_ratio", "public_ratio", "fi_ratio")) {
  dat[!is.finite(get(c)), (c) := NA_real_]
}

# ---- Run AR (headline cell) -------------------------------------------------

OUTCOME <- "log_gdp"
FE_TERM <- "muni_id + year"
z_pattern <- sprintf("^Z_(%s)_%s_%s_",
                     paste(OFFICES, collapse = "|"), ALIGNMENT, BASELINE)

run_ar_spec <- function(spec_name, vol_terms) {
  keep <- c("muni_id", "year", OUTCOME, vol_terms, INST_COLS)
  d <- dat[, ..keep]
  d <- d[complete.cases(d)]
  if (!nrow(d)) {
    return(data.table(spec = spec_name, status = "empty"))
  }
  rhs <- c(INST_COLS, vol_terms)
  fml <- as.formula(paste0(OUTCOME, " ~ ",
                           paste(rhs, collapse = " + "),
                           " | ", FE_TERM))
  mod <- tryCatch(
    feols(fml, data = d, vcov = ~ muni_id, lean = TRUE),
    error = function(e) NULL
  )
  if (is.null(mod)) {
    return(data.table(spec = spec_name, status = "fit_failed"))
  }
  w <- tryCatch(fixest::wald(mod, keep = z_pattern), error = function(e) NULL)
  ar_F <- if (!is.null(w)) as.numeric(w$stat) else NA_real_
  ar_p <- if (!is.null(w)) as.numeric(w$p)    else NA_real_
  # Volume-term coefficients.
  ct <- coeftable(mod)
  vol_summary <- paste(vapply(vol_terms, function(vt) {
    if (vt %in% rownames(ct)) {
      sprintf("%s=%.3e(SE=%.3e)", vt,
              ct[vt, "Estimate"], ct[vt, "Std. Error"])
    } else sprintf("%s=NA", vt)
  }, character(1)), collapse = "; ")
  data.table(
    spec = spec_name,
    status = "ok",
    n_obs = nobs(mod),
    n_munis = uniqueN(d$muni_id),
    K = length(INST_COLS),
    n_collinear = length(mod$collin.var),
    ar_F = ar_F, ar_p = ar_p,
    rejects_5pc = isTRUE(ar_p < 0.05),
    rejection_status = if (isTRUE(ar_p < 0.05)) "bounded_excludes_zero"
                       else "bounded_contains_zero",
    vol_terms = paste(vol_terms, collapse = "+"),
    vol_coefs = vol_summary
  )
}

message(sprintf("[INFO] %s | running joint AR (baseline)", Sys.time()))
res_joint <- run_ar_spec("joint", "vol_ratio")
print(res_joint)

message(sprintf("[INFO] %s | running split AR", Sys.time()))
res_split <- run_ar_spec("split",
                         c("prod_ratio", "public_ratio", "fi_ratio"))
print(res_split)

out <- rbind(res_joint, res_split, fill = TRUE)
out_path <- file.path(OUTPUT_BRANCH, "split_volume_ar.csv")
fwrite(out, out_path)
message(sprintf("[INFO] wrote: %s", out_path))

# Pass-criterion check.
if (all(out$status == "ok")) {
  stable <- identical(out$rejects_5pc[1L], out$rejects_5pc[2L])
  message(sprintf(
    "[INFO] split-volume rejection stability: %s (joint reject=%s, split reject=%s)",
    if (stable) "PASS" else "FAIL",
    out$rejects_5pc[1L], out$rejects_5pc[2L]))
}

message(sprintf("[INFO] %s | done.", Sys.time()))
