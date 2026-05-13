#!/usr/bin/env Rscript
# 11_process_bndes_indirect.R
#
# Processes BNDES automatic + non-automatic loan data.
# Filters to private, reimbursable loans. Applies IPCA deflation (base 2018).
#
# Outputs (saved to OUTPUT_DIR):
#   1. bndes_loan_level.qs2              -- Cleaned loan-level data (2002-2017)
#   2. bndes_firm_year_muni_sector.qs2   -- Aggregated: cnpj x year x muni x cnae_section

suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
  library(qs2)
})

options(scipen = 999)

setDTthreads(threads = parallel::detectCores() - 1)
qopt("nthreads", parallel::detectCores() - 1)

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

# Recipient-class classifier (D5-op, Phase 3 D3.1) — depends on bootstrap above.
classifier_path <- normalizePath(
  file.path(dirname(bootstrap_file), "classify_bndes_recipient.R"),
  winslash = "/", mustWork = TRUE
)
source(classifier_path)

# CLI flag: keep the legacy PRIVADA-only filter when explicitly requested.
# Default is FALSE per D5-op: lift the filter, tag with recipient_class, and
# downstream-restrict to recipient_class == "productive-firm" for the firm-level
# aggregate (preserving the existing pipeline schema and inputs to scripts 22,
# 31, 33). The full-class loan-level dataset and a new muni x year x class
# aggregate are emitted alongside for D5-op volume control.
cli_args <- commandArgs(trailingOnly = TRUE)
restrict_to_private <- "--restrict-to-private" %in% cli_args
log_info(sprintf("restrict_to_private flag: %s", restrict_to_private))

# =====================================================================
# Directories
# =====================================================================
raw_auto_dir <- make_base_path("raw/bndes_indirect_auto")
raw_nonauto_dir <- make_base_path("raw/bndes_direct_and_indirect_nonauto")
output_dir <- OUTPUT_DIR

log_info("BNDES base:", BNDES_BASE)
log_info("Raw automatic directory:", raw_auto_dir)
log_info("Raw non-automatic directory:", raw_nonauto_dir)
log_info("Output directory:", output_dir)

if (!dir.exists(raw_auto_dir)) stop("Raw auto directory not found: ", raw_auto_dir)
if (!dir.exists(raw_nonauto_dir)) stop("Raw non-auto directory not found: ", raw_nonauto_dir)
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# =====================================================================
# Helper functions
# =====================================================================
clean_cnpj <- function(x) {
  digits <- gsub("\\D", "", as.character(x))
  digits[nchar(digits) == 0] <- NA_character_
  pad_idx <- !is.na(digits) & nchar(digits) %in% 12:13
  if (any(pad_idx)) {
    digits[pad_idx] <- gsub(" ", "0", sprintf("%014s", digits[pad_idx]), fixed = TRUE)
  }
  digits[!is.na(digits) & nchar(digits) != 14] <- NA_character_
  digits
}

clean_currency <- function(x) {
  if (is.numeric(x)) return(x)
  x <- trimws(as.character(x))
  x[x %chin% c("", "ND", "NA")] <- NA_character_
  x <- gsub(".", "", x, fixed = TRUE)   # thousand separator
  x <- gsub(",", ".", x, fixed = TRUE)  # decimal separator
  suppressWarnings(as.numeric(x))
}

clean_integer <- function(x) {
  if (is.numeric(x)) return(as.integer(x))
  x <- trimws(as.character(x))
  x[x %chin% c("", "ND", "NA")] <- NA_character_
  x <- gsub("[^0-9\\-]", "", x)
  suppressWarnings(as.integer(x))
}

clean_rate <- function(x) {
  if (is.numeric(x)) return(x)
  x <- trimws(as.character(x))
  x[x %chin% c("", "ND", "NA")] <- NA_character_
  needs_pad <- !is.na(x) & nchar(x) == 3L & grepl("^\\d,\\d$", x)
  if (any(needs_pad)) x[needs_pad] <- paste0("0", x[needs_pad])
  x <- gsub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

parse_date_col <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }
  if (inherits(x, "POSIXt")) {
    return(as.Date(x))
  }
  if (is.numeric(x)) {
    # Excel origin
    return(as.Date(round(x), origin = "1899-12-30"))
  }
  x_chr <- trimws(as.character(x))
  x_chr[x_chr == ""] <- NA_character_
  # Try ISO format first (from as.character(POSIXct)), then DD/MM/YYYY (from CSV)
  result <- suppressWarnings(as.Date(x_chr, format = "%Y-%m-%d"))
  missing <- is.na(result) & !is.na(x_chr)
  if (any(missing)) {
    result[missing] <- suppressWarnings(as.Date(x_chr[missing], format = "%d/%m/%Y"))
  }
  result
}

ascii_upper <- function(x) {
  toupper(iconv(trimws(as.character(x)), to = "ASCII//TRANSLIT"))
}

# =====================================================================
# Read raw data
# =====================================================================

# Column name vectors (positional, matching BNDES portal structure)
auto_col_names <- c(
  "client", "cnpj_raw", "uf", "muni_name", "muni_id_ibge", "date",
  "value_op", "value_dis", "source", "fin_cost", "rate",
  "length1", "length2", "modality", "form_support", "product",
  "instrument", "innovation", "area", "sector_cnae",
  "subsector_cnae_group", "subsector_cnae_cod",
  "subsector_cnae_name", "sector_bndes", "subsector_bndes",
  "size", "nature", "fin_inst", "fin_inst_cnpj", "status"
)

nonauto_col_names <- c(
  "client", "cnpj_raw", "proj_desc", "uf", "muni_name",
  "muni_id_ibge", "contract", "date", "value_op", "value_dis",
  "source", "fin_cost", "rate", "length1", "length2",
  "modality", "form_support", "product", "instrument",
  "innovation", "area", "sector_cnae", "subsector_cnae_group",
  "subsector_cnae_cod", "subsector_cnae_name", "sector_bndes",
  "subsector_bndes", "size", "nature", "fin_inst",
  "fin_inst_cnpj", "type_guarantee", "type_excep", "status"
)

read_loan_file <- function(path, skip_rows = 4) {
  log_info("Reading", basename(path))
  ext <- tolower(tools::file_ext(path))
  dt <- switch(
    ext,
    "csv"  = fread(path, skip = skip_rows, header = TRUE, encoding = "Latin-1"),
    "xlsx" = setDT(read_xlsx(path, skip = skip_rows, col_names = TRUE)),
    stop("Unsupported file extension: ", ext)
  )
  log_info(sprintf("  -> %d rows x %d cols", nrow(dt), ncol(dt)))
  dt
}

# --- Automatic loans ---
auto_files <- sort(list.files(
  raw_auto_dir,
  pattern     = "operacoes_indiretas_automaticas_.*\\.(xlsx|csv)$",
  full.names  = TRUE,
  ignore.case = TRUE
))

if (length(auto_files)) {
  log_info(sprintf("Found %d automatic loan file(s)", length(auto_files)))
  auto_list <- lapply(auto_files, function(f) {
    dt <- read_loan_file(f)
    setnames(dt, auto_col_names[seq_len(ncol(dt))])
    # Coerce date to character before binding (xlsx returns POSIXct, csv returns character)
    if ("date" %in% names(dt) && !is.character(dt[["date"]])) {
      dt[, date := as.character(date)]
    }
    dt[, automatic := 1L]
    dt
  })
  automatic <- rbindlist(auto_list, use.names = TRUE, fill = TRUE)
  rm(auto_list)
} else {
  log_warn("No automatic loan files found in: ", raw_auto_dir)
  automatic <- data.table()
}

# --- Non-automatic loans ---
nonauto_path <- file.path(raw_nonauto_dir, "naoautomaticas.xlsx")
if (file.exists(nonauto_path)) {
  nonautomatic <- read_loan_file(nonauto_path)
  setnames(nonautomatic, nonauto_col_names[seq_len(ncol(nonautomatic))])
  # Coerce date to character before binding (xlsx returns POSIXct)
  if ("date" %in% names(nonautomatic) && !is.character(nonautomatic[["date"]])) {
    nonautomatic[, date := as.character(date)]
  }
  nonautomatic[, automatic := 0L]
} else {
  log_warn("Non-automatic file not found: ", nonauto_path)
  nonautomatic <- data.table()
}

# --- Combine ---
loans <- rbind(automatic, nonautomatic, fill = TRUE)
rm(automatic, nonautomatic)
log_info(sprintf("Combined: %d rows x %d cols", nrow(loans), ncol(loans)))

if (nrow(loans) == 0) stop("No loan data loaded.")

# =====================================================================
# Clean fields
# =====================================================================

# CNPJ (pad and validate to 14 digits)
loans[, cnpj := clean_cnpj(cnpj_raw)]
na_cnpj <- sum(is.na(loans$cnpj))
if (na_cnpj > 0) log_info(sprintf("CNPJ: %d rows with invalid/missing CNPJ", na_cnpj))

# Firm identifier
loans[, firm_id := substr(cnpj, 1, 8)]

# Date -> year, month
loans[, date_parsed := parse_date_col(date)]
loans[, year  := as.integer(format(date_parsed, "%Y"))]
loans[, month := as.integer(format(date_parsed, "%m"))]

# Numeric fields
loans[, value_dis     := clean_currency(value_dis)]
loans[, value_op      := clean_currency(value_op)]
loans[, rate          := clean_rate(rate)]
loans[, length1       := clean_integer(length1)]
loans[, length2       := clean_integer(length2)]
loans[, muni_id_ibge6 := as.integer(floor(clean_integer(muni_id_ibge) / 10))]

# Trim character fields
char_cols <- intersect(
  c("client", "uf", "muni_name", "source", "fin_cost", "modality",
    "form_support", "product", "instrument", "sector_cnae",
    "subsector_cnae_group", "subsector_cnae_cod", "subsector_cnae_name",
    "sector_bndes", "subsector_bndes", "size", "nature", "area",
    "fin_inst", "status"),
  names(loans)
)
for (col in char_cols) set(loans, j = col, value = trimws(as.character(loans[[col]])))

# Innovation flag (SIM -> 1, else 0)
loans[, innovation := as.integer(ascii_upper(innovation) == "SIM")]
loans[is.na(innovation), innovation := 0L]

# Direct flag (non-automatic loans with forma_de_apoio == "DIRETA")
loans[, direct := 0L]
loans[automatic == 0L & ascii_upper(form_support) == "DIRETA", direct := 1L]

# =====================================================================
# CNAE section (needed for recipient classification below)
# =====================================================================

loans[, cnae_section := substr(trimws(subsector_cnae_cod), 1, 1)]
loans[cnae_section == "", cnae_section := NA_character_]

# =====================================================================
# Tag recipient_class (D5-op, Phase 3 D3.1)
# =====================================================================
# Priority: public-entity > financial-institution > productive-firm > other.
# Done BEFORE any filter so the auxiliary all-class aggregate captures the
# full universe. The legacy `nature == "PRIVADA"` filter is replaced by a
# recipient-class restriction below (default: productive-firm).

n_pre_tag <- nrow(loans)
classify_bndes_recipient(loans)
log_info("Recipient-class tag distribution (pre-restriction):")
print(loans[, .(n_rows = .N, value_dis = sum(value_dis, na.rm = TRUE)),
            by = recipient_class][order(-value_dis)])

# Sanity: no NA values in recipient_class (all rows land in one of 4 classes).
stopifnot("recipient_class has NA values" = !any(is.na(loans$recipient_class)))

# Snapshot pre-restriction totals (loan-level) for downstream sanity checks.
totals_pre <- loans[, .(value_dis = sum(value_dis, na.rm = TRUE), n_loans = .N),
                    by = recipient_class]

# Filter: reimbursable (applies to all classes; mirrors legacy behaviour).
n0 <- nrow(loans)
loans <- loans[!(automatic == 0L & ascii_upper(modality) == "NAO REEMBOLSAVEL")]
log_info(sprintf("Reimbursable filter: %d -> %d (dropped %d)", n0, nrow(loans), n0 - nrow(loans)))

# =====================================================================
# IPCA deflation (base year 2018) — applied before recipient-class
# restriction so the all-class auxiliary aggregate carries real values too.
# =====================================================================

ipca_path <- make_base_path("raw/ipca_202509SerieHist.xlsx")

if (file.exists(ipca_path)) {
  log_info("Loading IPCA series from: ", ipca_path)

  ipca_raw <- as.data.table(read_excel(ipca_path, skip = 6, col_names = FALSE))
  ipca_raw <- ipca_raw[, 1:4]
  base_names <- c("year", "month", "index", "variation")
  if (ncol(ipca_raw) >= length(base_names))   {
    setnames(ipca_raw, seq_along(base_names), base_names)
  } else {
    setnames(ipca_raw, base_names[seq_len(ncol(ipca_raw))])
  }
  suppressWarnings(ipca_raw <- ipca_raw[!is.na(index)])
  ipca_raw[, year   := as.integer(year)]
  ipca_raw[, month  := toupper(trimws(as.character(month)))]
  ipca_raw[, year   := nafill(year, type = "locf")]
  ipca_raw[, index := suppressWarnings(as.numeric(index))]

  month_map <- setNames(1:12, c("JAN", "FEV", "MAR", "ABR", "MAI", "JUN",
                                "JUL", "AGO", "SET", "OUT", "NOV", "DEZ"))
  ipca_raw[, month_num := month_map[month]]

  ipca_yearly <- ipca_raw[
    !is.na(month_num) & !is.na(year),
    .(ipca_avg = mean(index, na.rm = TRUE)),
    by = year
  ]

  base_year <- 2018L
  if (base_year %in% ipca_yearly$year) {
    base_val <- ipca_yearly[year == base_year, ipca_avg]
    ipca_yearly[, deflator := base_val / ipca_avg]

    loans[ipca_yearly, deflator := i.deflator, on = .(year = year)]
    loans[!is.na(deflator), value_dis_real_2018 := value_dis * deflator]
    loans[, deflator := NULL]
    log_info("IPCA deflation applied (base 2018)")
  } else {
    log_warn("Base year 2018 not in IPCA series; skipping deflation")
  }
  rm(ipca_raw, ipca_yearly)
} else {
  log_warn("IPCA file not found: ", ipca_path, " -- skipping deflation")
}

# =====================================================================
# Snapshot full-class dataset, then restrict primary pipeline to
# recipient_class == "productive-firm" (D5-op default).
# =====================================================================
loans_all_classes <- copy(loans)

n0 <- nrow(loans)
if (restrict_to_private) {
  loans <- loans[ascii_upper(nature) == "PRIVADA"]
  log_info(sprintf("Legacy PRIVADA filter: %d -> %d (dropped %d)",
                   n0, nrow(loans), n0 - nrow(loans)))
} else {
  loans <- loans[recipient_class == "productive-firm"]
  log_info(sprintf("Recipient-class filter (productive-firm): %d -> %d (dropped %d)",
                   n0, nrow(loans), n0 - nrow(loans)))
}

# =====================================================================
# Drop working columns, restrict to 2002-2017, reorder
# =====================================================================

drop_cols <- intersect(
  c("cnpj_raw", "muni_id_ibge", "date", "date_parsed", "form_support",
    "value_op", "nature", "area", "proj_desc", "contract", "type_guarantee",
    "type_excep", "status"),
  names(loans)
)
if (length(drop_cols)) loans[, (drop_cols) := NULL]

n0 <- nrow(loans)
loans <- loans[year >= 2002L & year <= 2017L]
log_info(sprintf("Year filter [2002-2017]: %d -> %d", n0, nrow(loans)))

desired_order <- intersect(
  c("client", "cnpj", "firm_id", "uf", "muni_name", "muni_id_ibge6",
    "value_dis", "value_dis_real_2018",
    "source", "fin_cost", "rate", "length1", "length2",
    "modality", "product", "instrument", "innovation",
    "sector_cnae", "subsector_cnae_group", "subsector_cnae_cod",
    "subsector_cnae_name", "cnae_section",
    "sector_bndes", "subsector_bndes", "size",
    "fin_inst", "fin_inst_cnpj", "automatic", "direct",
    "recipient_class",
    "year", "month"),
  names(loans)
)
setcolorder(loans, desired_order)

# =====================================================================
# Save: cleaned loan-level
# =====================================================================

clean_path <- make_output_path("bndes_loan_level.qs2")
qs_save(loans, clean_path)
log_info(sprintf("Saved loan-level: %d rows -> %s", nrow(loans), clean_path))

# =====================================================================
# Aggregate: firm x year x municipality x cnae_section
# =====================================================================

agg <- loans[
  !is.na(firm_id) & firm_id != "77700001" & cnpj != "00000000000000" & 
  !is.na(year) & !is.na(muni_id_ibge6) & !muni_id_ibge6 %in% c(0, 999999) & 
  !is.na(cnae_section),
  .(
    value_dis_total           = sum(value_dis, na.rm = TRUE),
    value_dis_real_2018_total = if (all(is.na(value_dis_real_2018))) NA_real_
                                  else sum(value_dis_real_2018, na.rm = TRUE),
    n_loans                   = .N
  ),
  by = .(firm_id, year, muni_id_ibge6, cnae_section)
]

setorderv(agg, c("firm_id", "year", "muni_id_ibge6", "cnae_section"))

log_info(sprintf(
  "Aggregated: %d rows (%d unique firms, %d unique munis, %d unique sectors)",
  nrow(agg), uniqueN(agg$firm_id), uniqueN(agg$muni_id_ibge6), uniqueN(agg$cnae_section)
))

# =====================================================================
# Save: aggregated
# =====================================================================

# =====================================================================
# Auxiliary aggregate: muni x year x recipient_class (D5-op, Phase 3 D3.1)
# =====================================================================
# Built from the FULL-CLASS dataset (pre-recipient-class restriction) so
# downstream consumers can construct split-volume columns
# bndes_total_{productive,fi,public,other}_mt without re-reading the raw
# files. Applies the same 2002-2017 window and muni-id sanitation as the
# primary firm-level aggregate.
loans_all_classes <- loans_all_classes[year >= 2002L & year <= 2017L]
class_my <- loans_all_classes[
  !is.na(year) & !is.na(muni_id_ibge6) & !muni_id_ibge6 %in% c(0L, 999999L),
  .(
    value_dis_total           = sum(value_dis, na.rm = TRUE),
    value_dis_real_2018_total = if (all(is.na(value_dis_real_2018))) NA_real_
                                  else sum(value_dis_real_2018, na.rm = TRUE),
    n_loans                   = .N
  ),
  by = .(muni_id_ibge6, year, recipient_class)
]
setorderv(class_my, c("muni_id_ibge6", "year", "recipient_class"))

class_my_path <- make_output_path("bndes_loans_by_recipient_class_my.qs2")
qs_save(class_my, class_my_path)
log_info(sprintf("Saved muni x year x recipient_class aggregate: %d rows -> %s",
                 nrow(class_my), class_my_path))

# Sanity report: class-level totals (nominal R$, full window).
class_totals <- loans_all_classes[, .(
  value_dis = sum(value_dis, na.rm = TRUE), n_loans = .N
), by = recipient_class][order(-value_dis)]
class_totals[, share := value_dis / sum(value_dis)]
log_info("Recipient-class shares (post reimbursable filter, 2002-2017):")
print(class_totals)

# Cross-check: productive-firm volume in restricted aggregate ≈ all-class
# productive-firm volume from class_my.
prod_v_main <- if (nrow(loans) > 0) sum(loans$value_dis, na.rm = TRUE) else 0
prod_v_aux  <- sum(class_my[recipient_class == "productive-firm", value_dis_total],
                   na.rm = TRUE)
log_info(sprintf("Cross-check productive-firm volume: main=%.4e  aux=%.4e  diff=%.4e",
                 prod_v_main, prod_v_aux, prod_v_main - prod_v_aux))

agg_path <- make_output_path("bndes_firm_year_muni_sector.qs2")
qs_save(agg, agg_path)
log_info(sprintf("Saved aggregated: %d rows -> %s", nrow(agg), agg_path))

log_info("Script 11 completed successfully.")
