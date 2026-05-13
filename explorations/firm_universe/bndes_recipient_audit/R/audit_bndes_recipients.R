#!/usr/bin/env Rscript
# audit_bndes_recipients.R
#
# A0.4 — BNDES recipient-type audit (informs D5).
# Re-reads raw BNDES files (raw bypasses the script-11 PRIVADA filter), classifies
# each disbursement record into productive-firm / public-entity / financial-
# institution / other, and produces double-counting and public-admin overlap
# diagnostics for the firm-support hybrid implementation plan.
#
# Inputs (read directly; processed cache is post-PRIVADA-filter and unusable):
#   data/raw/bndes_indirect_auto/*.xlsx, *.csv
#   data/raw/bndes_direct_and_indirect_nonauto/naoautomaticas.xlsx
#   data/raw/bndes_public_administration/administracao_publica_1994-06-30_ate_2025-07-31.xlsx
#
# Outputs (under explorations/firm_universe/bndes_recipient_audit/output/):
#   class_shares_overall.csv
#   class_by_year.csv
#   class_by_muni_aggregate.csv
#   fi_double_counting_2010.csv
#   public_admin_vs_main_overlap.csv
#   audit_summary.csv

suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
})

options(scipen = 999)
setDTthreads(threads = max(1L, parallel::detectCores() - 1L))

# ---- paths (relative to project root; resolved from --file= or cwd) --------
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || !nzchar(a)) b else a

get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", args, value = TRUE)
  if (length(m)) {
    return(normalizePath(dirname(sub("^--file=", "", m[[1]])),
                         winslash = "/", mustWork = FALSE))
  }
  getwd()
}
script_dir <- get_script_dir()
project_root <- Sys.getenv("BNDES_PROJECT_ROOT",
  unset = normalizePath(file.path(script_dir, "..", "..", "..", ".."),
                        winslash = "/", mustWork = FALSE))
if (!dir.exists(project_root)) project_root <- getwd()

raw_auto_dir <- file.path(project_root, "data", "raw", "bndes_indirect_auto")
raw_nonauto  <- file.path(project_root, "data", "raw",
                          "bndes_direct_and_indirect_nonauto", "naoautomaticas.xlsx")
raw_pubadmin <- file.path(project_root, "data", "raw", "bndes_public_administration",
                          "administracao_publica_1994-06-30_ate_2025-07-31.xlsx")
out_dir      <- file.path(project_root, "explorations", "firm_universe",
                          "bndes_recipient_audit", "output")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# ---- preconditions ---------------------------------------------------------
stopifnot(
  "Raw BNDES indirect_auto directory not found" = dir.exists(raw_auto_dir),
  "Raw BNDES nonautomaticas file not found"     = file.exists(raw_nonauto),
  "Raw BNDES public-admin file not found"       = file.exists(raw_pubadmin)
)

log_msg <- function(...) message(sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"),
                                          paste0(..., collapse = "")))

# ---- helpers ---------------------------------------------------------------
clean_cnpj <- function(x) {
  digits <- gsub("\\D", "", as.character(x))
  digits[nchar(digits) == 0] <- NA_character_
  pad_idx <- !is.na(digits) & nchar(digits) %in% 12:13
  if (any(pad_idx)) digits[pad_idx] <- gsub(" ", "0", sprintf("%014s", digits[pad_idx]),
                                              fixed = TRUE)
  digits[!is.na(digits) & nchar(digits) != 14] <- NA_character_
  digits
}

clean_currency <- function(x) {
  if (is.numeric(x)) return(x)
  x <- trimws(as.character(x))
  x[x %chin% c("", "ND", "NA")] <- NA_character_
  x <- gsub(".", "", x, fixed = TRUE)
  x <- gsub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

ascii_upper <- function(x) toupper(iconv(trimws(as.character(x)), to = "ASCII//TRANSLIT"))

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
  log_msg("  reading ", basename(path))
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

# ---- 1. Load raw automatic + non-automatic ---------------------------------
log_msg("Loading raw BNDES files (pre-filter)")

auto_files <- sort(list.files(raw_auto_dir,
                              pattern = "operacoes_indiretas_automaticas_.*\\.(xlsx|csv)$",
                              full.names = TRUE, ignore.case = TRUE))
auto_list <- lapply(auto_files, read_one, names_vec = auto_cols, skip = 4L)
automatic <- rbindlist(auto_list, use.names = TRUE, fill = TRUE)
automatic[, automatic := 1L]
rm(auto_list); gc()

nonautomatic <- read_one(raw_nonauto, nonauto_cols, skip = 4L)
nonautomatic[, automatic := 0L]

loans <- rbind(automatic, nonautomatic, fill = TRUE)
rm(automatic, nonautomatic); gc()
log_msg(sprintf("Raw combined: %d rows", nrow(loans)))

# ---- 2. Clean minimal fields -----------------------------------------------
loans[, cnpj := clean_cnpj(cnpj_raw)]
loans[, firm_id := substr(cnpj, 1, 8)]
loans[, date_parsed := parse_date_col(date)]
loans[, year := as.integer(format(date_parsed, "%Y"))]
loans[, value_dis := clean_currency(value_dis)]
loans[, muni_id_ibge6 := as.integer(floor(suppressWarnings(
  as.numeric(gsub("\\D", "", as.character(muni_id_ibge)))) / 10))]
loans[, nature_u := ascii_upper(nature)]
loans[, cnae_section := substr(trimws(as.character(subsector_cnae_cod)), 1, 1)]
loans[cnae_section == "", cnae_section := NA_character_]
# CNAE codes have form "<letter><7 digits>" (e.g. "K6411900"); division 2-digit
# is positions 2-3. Fall back to first-two digits if the code begins numerically.
loans[, cnae_code_clean := trimws(as.character(subsector_cnae_cod))]
loans[, cnae_div2 := {
  starts_letter <- grepl("^[A-Za-z]", cnae_code_clean)
  d <- ifelse(starts_letter, substr(cnae_code_clean, 2, 3),
                              substr(cnae_code_clean, 1, 2))
  suppressWarnings(as.integer(d))
}]

# Restrict to AR-test window 2002–2017 for like-for-like comparison.
loans <- loans[!is.na(year) & year >= 2002L & year <= 2017L]
log_msg(sprintf("After year filter [2002-2017]: %d rows", nrow(loans)))

# ---- 3. Classification -----------------------------------------------------
# Priority: public-entity > financial-institution > productive-firm > other.
loans[, recipient_class := "other"]
loans[!is.na(cnae_div2) & cnae_div2 %in% 64:66, recipient_class := "financial_institution"]
loans[!is.na(nature_u) & nature_u == "PRIVADA" &
      !is.na(cnae_section) & recipient_class == "other",
      recipient_class := "productive_firm"]
# Public-entity override (highest priority). The raw `Natureza do cliente`
# field reports several public variants — PUBLICA, PUBLICA INDIRETA,
# ADMINISTRACAO PUBLICA DIRETA - GOVERNO {FEDERAL,ESTADUAL,MUNICIPAL} — so we
# match by prefix rather than exact equality. Also flag any record whose CNAE
# section is O (public administration, defense, social security).
loans[, is_public_nature := !is.na(nature_u) & (
        startsWith(nature_u, "PUBLICA") |
        startsWith(nature_u, "ADMINISTRACAO PUBLICA"))]
loans[is_public_nature | (!is.na(cnae_section) & cnae_section == "O"),
      recipient_class := "public_entity"]

# ---- 4. Aggregate ----------------------------------------------------------
# Diagnostic on the "other" residual: which fields are missing / unusual.
other_diag <- loans[recipient_class == "other",
                    .(n = .N, value_dis = sum(value_dis, na.rm = TRUE)),
                    by = .(nature_u, cnae_section_missing = is.na(cnae_section),
                           cnae_section)]
setorder(other_diag, -value_dis)
fwrite(other_diag, file.path(out_dir, "other_class_diagnostics.csv"))

class_overall <- loans[, .(value_dis = sum(value_dis, na.rm = TRUE),
                            n_loans = .N), by = recipient_class]
total_v <- sum(class_overall$value_dis, na.rm = TRUE)
class_overall[, share_value := value_dis / total_v]
setorder(class_overall, -value_dis)
fwrite(class_overall, file.path(out_dir, "class_shares_overall.csv"))

class_year <- loans[, .(value_dis = sum(value_dis, na.rm = TRUE), n_loans = .N),
                    by = .(recipient_class, year)]
setorder(class_year, year, recipient_class)
fwrite(class_year, file.path(out_dir, "class_by_year.csv"))

class_muni <- loans[!is.na(muni_id_ibge6),
                    .(value_dis = sum(value_dis, na.rm = TRUE), n_loans = .N,
                      n_munis = uniqueN(muni_id_ibge6)),
                    by = recipient_class]
fwrite(class_muni, file.path(out_dir, "class_by_muni_aggregate.csv"))

log_msg("Recipient-class shares of total disbursement (2002-2017):")
print(class_overall)

# ---- 5. Double-counting check: FI loans vs. fin_inst_cnpj (multi-year) -----
# Extended to 2008/2010/2014 to bracket the PSI era (per coder-critic A0.4
# follow-up). Threshold for escalation is overlap-volume share of TOTAL credit
# disbursed that year (not the FI subset) — the relevant denominator for
# whether double-counting moves the AR-test estimand. Trigger: > 0.05% of
# total credit in any year.
log_msg("Double-counting check (multi-year: 2008, 2010, 2014)")

fi_cnpjs <- unique(loans[recipient_class == "financial_institution" & !is.na(cnpj), cnpj])
log_msg(sprintf("  %d unique FI-classified CNPJs (across 2002-2017)", length(fi_cnpjs)))

dc_years <- c(2008L, 2010L, 2014L)
dc_rows  <- list()

for (yr in dc_years) {
  loans_yr <- loans[year == yr]
  loans_yr[, fin_inst_cnpj_clean := clean_cnpj(fin_inst_cnpj)]

  indirect_yr <- loans_yr[!is.na(fin_inst_cnpj_clean) &
                            recipient_class %in% c("productive_firm",
                                                   "financial_institution",
                                                   "public_entity", "other")]

  fi_volume_yr <- loans_yr[recipient_class == "financial_institution",
                            .(value_dis_fi = sum(value_dis, na.rm = TRUE),
                              n_loans_fi = .N), by = cnpj]
  agent_volume_yr <- indirect_yr[, .(value_dis_routed = sum(value_dis, na.rm = TRUE),
                                      n_loans_routed = .N),
                                  by = fin_inst_cnpj_clean]
  setnames(agent_volume_yr, "fin_inst_cnpj_clean", "cnpj")

  overlap_yr <- merge(fi_volume_yr, agent_volume_yr, by = "cnpj", all = TRUE)
  overlap_yr[, both := !is.na(value_dis_fi) & !is.na(value_dis_routed)]

  if (yr == 2010L) {
    # preserve back-compatible filename for 2010 detail dump
    fwrite(overlap_yr, file.path(out_dir, "fi_double_counting_2010.csv"))
  }

  n_fi_yr        <- nrow(fi_volume_yr)
  n_overlap_yr   <- sum(overlap_yr$both, na.rm = TRUE)
  v_fi_yr        <- sum(fi_volume_yr$value_dis_fi, na.rm = TRUE)
  v_fi_alsoag_yr <- sum(overlap_yr[both == TRUE, value_dis_fi], na.rm = TRUE)
  v_total_yr     <- sum(loans_yr$value_dis, na.rm = TRUE)

  overlap_share_count  <- if (n_fi_yr > 0) n_overlap_yr / n_fi_yr else 0
  overlap_share_volume <- if (v_fi_yr  > 0) v_fi_alsoag_yr / v_fi_yr else 0
  dc_share_of_total    <- if (v_total_yr > 0) v_fi_alsoag_yr / v_total_yr else 0

  dc_rows[[as.character(yr)]] <- data.table(
    year                  = yr,
    n_fi_borrowers        = n_fi_yr,
    n_overlap             = n_overlap_yr,
    overlap_share_count   = overlap_share_count,
    fi_volume_total       = v_fi_yr,
    fi_volume_overlap     = v_fi_alsoag_yr,
    overlap_share_volume  = overlap_share_volume,
    dc_share_of_total_credit = dc_share_of_total
  )

  log_msg(sprintf("  %d: FI=%d, overlap=%d (%.1f%%); FI-vol=R$ %.2e; overlap-vol=R$ %.2e (%.3f%% of total credit)",
                  yr, n_fi_yr, n_overlap_yr, 100 * overlap_share_count,
                  v_fi_yr, v_fi_alsoag_yr, 100 * dc_share_of_total))
}

fi_multi <- rbindlist(dc_rows, use.names = TRUE)
fwrite(fi_multi, file.path(out_dir, "fi_double_counting_multi_year.csv"))

# Escalation flag: overlap volume > 0.05% of total credit in any year.
dc_escalate_threshold <- 0.0005
fi_multi[, escalate := dc_share_of_total_credit > dc_escalate_threshold]
escalate_dc_any <- any(fi_multi$escalate)
if (escalate_dc_any) {
  log_msg(sprintf("  ESCALATION: at least one year exceeds %.2f%% of total credit",
                  100 * dc_escalate_threshold))
} else {
  log_msg(sprintf("  No year exceeds %.2f%% of total credit threshold",
                  100 * dc_escalate_threshold))
}

# Back-compat summary scalars (2010 figures, used by summary table below).
double_count_share <- fi_multi[year == 2010L, overlap_share_volume]
if (length(double_count_share) == 0L) double_count_share <- 0
escalate_dc <- escalate_dc_any

# ---- 6. Public-admin file vs main-file public-entity overlap ---------------
log_msg("Public-admin file overlap analysis")

pa <- setDT(read_xlsx(raw_pubadmin, skip = 2L, col_names = TRUE))
setnames(pa, c("ente_publico", "uf", "muni_name", "programa", "modalidade",
               "date_nivel", "nivel", "value_op", "value_dis_pa",
               "saldo", "objetivo", "situacao"))
pa[, value_dis_pa := clean_currency(value_dis_pa)]
pa[, date_pa := parse_date_col(date_nivel)]
pa[, year_pa := as.integer(format(date_pa, "%Y"))]
# Restrict to AR-test window where possible (data covers 1994-2025).
pa_window <- pa[!is.na(year_pa) & year_pa >= 2002L & year_pa <= 2017L]

# The public-admin file has NO CNPJ. We match on (uf, muni_name, year)
# against public-entity rows from the main BNDES file as a proxy overlap.
main_pe <- loans[recipient_class == "public_entity" & !is.na(muni_name),
                 .(value_dis_main = sum(value_dis, na.rm = TRUE), n_loans_main = .N),
                 by = .(uf = toupper(trimws(uf)),
                        muni_key = toupper(iconv(trimws(as.character(muni_name)),
                                                  to = "ASCII//TRANSLIT")),
                        year)]
pa_key <- pa_window[, .(value_dis_pa = sum(value_dis_pa, na.rm = TRUE),
                        n_loans_pa = .N),
                    by = .(uf = toupper(trimws(uf)),
                           muni_key = toupper(iconv(trimws(as.character(muni_name)),
                                                      to = "ASCII//TRANSLIT")),
                           year = year_pa)]
overlap_pa <- merge(main_pe, pa_key, by = c("uf", "muni_key", "year"), all = TRUE)
overlap_pa[, in_main := !is.na(value_dis_main)]
overlap_pa[, in_pa   := !is.na(value_dis_pa)]
fwrite(overlap_pa, file.path(out_dir, "public_admin_vs_main_overlap.csv"))

v_main <- sum(main_pe$value_dis_main, na.rm = TRUE)
v_pa   <- sum(pa_key$value_dis_pa, na.rm = TRUE)
n_main_keys <- nrow(main_pe)
n_pa_keys   <- nrow(pa_key)
n_both_keys <- nrow(overlap_pa[in_main & in_pa])
v_both_main <- sum(overlap_pa[in_main & in_pa, value_dis_main], na.rm = TRUE)
v_both_pa   <- sum(overlap_pa[in_main & in_pa, value_dis_pa], na.rm = TRUE)

log_msg(sprintf("  Main-file public-entity (UF, muni, year) cells: %d  vol=R$ %.2e",
                n_main_keys, v_main))
log_msg(sprintf("  Public-admin (UF, muni, year) cells: %d  vol=R$ %.2e",
                n_pa_keys, v_pa))
log_msg(sprintf("  Overlap cells: %d  main-vol(overlap)=R$ %.2e  pa-vol(overlap)=R$ %.2e",
                n_both_keys, v_both_main, v_both_pa))

# ---- 7. Summary table ------------------------------------------------------
summary_dt <- data.table(
  metric = c("total_disbursement_2002_2017",
             "share_public_entity", "share_financial_institution",
             "share_productive_firm", "share_other",
             "fi_double_count_share_2010_pct",
             "fi_double_count_escalate",
             "pa_file_cells_2002_2017", "pa_file_volume_2002_2017",
             "main_pe_cells_2002_2017", "main_pe_volume_2002_2017",
             "pa_main_overlap_cells", "pa_main_overlap_volume_main",
             "pa_main_overlap_volume_pa"),
  value  = c(format(total_v, scientific = TRUE, digits = 4),
             sprintf("%.4f", class_overall[recipient_class == "public_entity",
                                            share_value] %||% 0),
             sprintf("%.4f", class_overall[recipient_class == "financial_institution",
                                            share_value] %||% 0),
             sprintf("%.4f", class_overall[recipient_class == "productive_firm",
                                            share_value] %||% 0),
             sprintf("%.4f", class_overall[recipient_class == "other",
                                            share_value] %||% 0),
             sprintf("%.2f", 100 * double_count_share),
             as.character(escalate_dc),
             as.character(n_pa_keys),
             format(v_pa, scientific = TRUE, digits = 4),
             as.character(n_main_keys),
             format(v_main, scientific = TRUE, digits = 4),
             as.character(n_both_keys),
             format(v_both_main, scientific = TRUE, digits = 4),
             format(v_both_pa, scientific = TRUE, digits = 4))
)
fwrite(summary_dt, file.path(out_dir, "audit_summary.csv"))
log_msg("Wrote: ", file.path(out_dir, "audit_summary.csv"))

log_msg("audit_bndes_recipients.R completed.")
