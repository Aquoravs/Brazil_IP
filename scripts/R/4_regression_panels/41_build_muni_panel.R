#!/usr/bin/env Rscript

# ==============================================================================
# Build Municipality Panels for Shift-Share Regressions
# ==============================================================================
# Produces two panels:
#
# (A) muni × sector × year panel (for first stage)
#     delta_s_mjt, sector-specific instruments Z_jrt, controls
#
# (B) muni × year panel (for second stage)
#     GDP per capita, total BNDES, employment, muni-level instruments
#
# Dependencies:
#   - Script 22: rais_bndes_reconstructed.fst
#   - Script 34: shift_share_instruments.qs2 (muni-level)
#                shift_share_instruments_sector.qs2 (sector-level)
#   - Script 35: bndes_credit_shares.qs2
#   - User-provided: raw/mun_gdp/ (IBGE PIB Municipal .xls files)
#   - Population: downloaded via basedosdados and cached locally
# ==============================================================================

cat("==============================================================================\n")
cat("Building Municipality Panels for Regressions\n")
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

# --- Parse CLI arguments -----------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

svar_flag <- grep("^--sector-var=", args, value = TRUE)
SECTOR_VAR <- "sector_group"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[1])))
  if (!SECTOR_VAR %in% c("cnae_section", "sector_group", "policy_block")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'. Use 'cnae_section', 'sector_group', or 'policy_block'.")
  }
}
USE_GROUPS <- (SECTOR_VAR == "sector_group")
USE_POLICY_BLOCKS <- (SECTOR_VAR == "policy_block")
SCOL <- SECTOR_VAR
cat("Sector variable:", SECTOR_VAR, "\n")

# --- Endogenous variable source (Phase 2 C2.2-partial; 2026-05-13) -----------
# emp_share   : panel_a skeleton from emp_share_panel_<margin>.qs2 (script 32c).
#               s_emp_mjt / delta_s_emp_mjt drive j0 selection, wide pivots,
#               and HHI. Credit shares are merged as mechanism-check side
#               variables (s_credit_mjt / delta_s_credit_mjt). The BHJ §4.4
#               slack column (slack_frozen_mt) propagates to Panel B.
# bndes_credit: legacy path. panel_a = credit, j0 by mean(s_mjt), wide pivots
#               on s_mjt / delta_s_mjt. No slack column required.
endo_flag <- grep("^--endogenous=", args, value = TRUE)
ENDOGENOUS <- "emp_share"
if (length(endo_flag)) {
  ENDOGENOUS <- tolower(trimws(sub("^--endogenous=", "", endo_flag[1])))
  if (!ENDOGENOUS %in% c("emp_share", "bndes_credit")) {
    stop("Invalid --endogenous value: '", ENDOGENOUS,
         "'. Use 'emp_share' or 'bndes_credit'.")
  }
}
cat("Endogenous source:", ENDOGENOUS, "\n\n")

# --- Configuration -----------------------------------------------------------

recon_fst_path  <- make_output_path("rais_bndes_reconstructed.fst")
recon_qs2_path  <- make_output_path("rais_bndes_reconstructed.qs2")

if (USE_GROUPS) {
  credit_path     <- make_output_path("bndes_credit_shares_grouped.qs2")
  instr_path      <- make_output_path("shift_share_instruments_grouped.qs2")
  instr_sec_path  <- make_output_path("shift_share_instruments_sector_grouped.qs2")
  controls_sec_path <- make_output_path("exposure_control_sector_grouped.qs2")
  output_sector_path <- make_output_path("muni_sector_panel_grouped.qs2")
  output_muni_path   <- make_output_path("muni_panel_for_regs_grouped.qs2")
  summary_path       <- make_output_path("muni_panel_grouped_summary.csv")
} else if (USE_POLICY_BLOCKS) {
  credit_path     <- make_output_path("bndes_credit_shares_policy_block.qs2")
  instr_path      <- make_output_path("shift_share_instruments_policy_block.qs2")
  instr_sec_path  <- make_output_path("shift_share_instruments_sector_policy_block.qs2")
  controls_sec_path <- make_output_path("exposure_control_sector_policy_block.qs2")
  output_sector_path <- make_output_path("muni_sector_panel_policy_block.qs2")
  output_muni_path   <- make_output_path("muni_panel_for_regs_policy_block.qs2")
  summary_path       <- make_output_path("muni_panel_policy_block_summary.csv")
} else {
  credit_path     <- make_output_path("bndes_credit_shares.qs2")
  instr_path      <- make_output_path("shift_share_instruments.qs2")
  instr_sec_path  <- make_output_path("shift_share_instruments_sector.qs2")
  controls_sec_path <- make_output_path("exposure_control_sector.qs2")
  output_sector_path <- make_output_path("muni_sector_panel.qs2")
  output_muni_path   <- make_output_path("muni_panel_for_regs.qs2")
  summary_path       <- make_output_path("muni_panel_summary.csv")
}

gdp_dir  <- make_base_path("raw/mun_gdp")
pop_cache <- make_output_path("population_ibge.qs2")

# Classification output (also produced independently by script 32b)
output_classification_path  <- make_output_path("muni_employment_classification.qs2")
summary_classification_path <- make_output_path("muni_employment_classification_summary.csv")

# ==============================================================================
# STEP 1: Aggregate firm-level data to municipality × year
# ==============================================================================

cat("Step 1: Aggregating firm-level data to municipality-year...\n")

# Load from fst (column-selective) or qs2
agg_cols <- c("firm_id", "muni_id", "year", "cnae_section",
              "value_dis_real_2018_total", "n_employees", "in_bndes")

if (file.exists(recon_fst_path) && requireNamespace("fst", quietly = TRUE)) {
  cat("  Loading from fst:", basename(recon_fst_path), "\n")
  recon <- fst::read_fst(recon_fst_path, columns = agg_cols, as.data.table = TRUE)
} else if (file.exists(recon_qs2_path)) {
  cat("  Loading from qs2:", basename(recon_qs2_path), "\n")
  raw <- qs_read(recon_qs2_path)
  setDT(raw)
  recon <- raw[, ..agg_cols]
  rm(raw); invisible(gc())
} else {
  stop("Reconstructed panel not found. Run script 22 first.")
}
cat("  Loaded:", format(nrow(recon), big.mark = ","), "rows\n")

# Drop invalid muni_id (0 is not a valid IBGE municipality code)
n_invalid_muni <- sum(recon$muni_id == 0L | is.na(recon$muni_id))
if (n_invalid_muni > 0L) {
  cat(sprintf("  Dropping %d rows with invalid muni_id (0 or NA)\n", n_invalid_muni))
  recon <- recon[!is.na(muni_id) & muni_id > 0L]
}

# Fill NAs for aggregation
recon[is.na(value_dis_real_2018_total), value_dis_real_2018_total := 0]
recon[is.na(n_employees), n_employees := 0L]

# Municipality × year aggregation
muni_yr <- recon[, .(
  total_bndes_real = sum(value_dis_real_2018_total, na.rm = TRUE),
  total_employment = sum(n_employees, na.rm = TRUE),
  n_firms          = uniqueN(firm_id),
  n_bndes_firms    = sum(in_bndes > 0, na.rm = TRUE)
), by = .(muni_id, year)]

muni_yr[, log_bndes := log1p(pmax(0, total_bndes_real))]
muni_yr[, bndes_per_worker := fifelse(
  total_employment > 0, total_bndes_real / total_employment, NA_real_)]
muni_yr[, state_id := as.integer(floor(muni_id / 10000))]

cat("  Municipality-year panel:", nrow(muni_yr), "rows,",
    uniqueN(muni_yr$muni_id), "municipalities\n")

rm(recon); invisible(gc())

# ==============================================================================
# STEP 1b: Muni employment quartile classification (time-invariant)
# ==============================================================================
# Whole-period mean (2002–2017), national unconditional quartiles.
# Emits muni_employment_classification.qs2 — also produced by script 32b.
# Saved here so it is always regenerated alongside the muni panels.
# ==============================================================================

cat("\nStep 1b: Building muni employment quartile classification (2002–2017)...\n")

WHOLE_PERIOD_YEARS_41 <- 2002L:2017L

muni_emp_class <- muni_yr[year %in% WHOLE_PERIOD_YEARS_41, .(
  muni_emp_whole = mean(total_employment, na.rm = TRUE)
), by = muni_id]

# Munis with zero or missing employment → 0, land in Q1
muni_emp_class[is.na(muni_emp_whole) | !is.finite(muni_emp_whole), muni_emp_whole := 0]

muni_emp_class[, muni_emp_quartile := as.integer(
  cut(muni_emp_whole,
      breaks = quantile(muni_emp_whole, probs = c(0, 0.25, 0.50, 0.75, 1.0),
                        na.rm = TRUE, names = FALSE),
      include.lowest = TRUE,
      labels = FALSE)
)]
muni_emp_class[is.na(muni_emp_quartile), muni_emp_quartile := 1L]
muni_emp_class[, top_q4_muni := as.integer(muni_emp_quartile == 4L)]

cat(sprintf("  Classified: %d municipalities\n", nrow(muni_emp_class)))
q_dist_41 <- muni_emp_class[, .N, by = muni_emp_quartile][order(muni_emp_quartile)]
for (k in seq_len(nrow(q_dist_41))) {
  cat(sprintf("  Q%d: %d munis (%.1f%%)\n",
              q_dist_41$muni_emp_quartile[k],
              q_dist_41$N[k],
              100 * q_dist_41$N[k] / nrow(muni_emp_class)))
}

# ==============================================================================
# STEP 2: Load GDP data
# ==============================================================================

cat("\nStep 2: Loading GDP data...\n")

load_gdp <- function(gdp_dir) {
  if (!dir.exists(gdp_dir)) {
    cat("  WARNING: GDP directory not found:", gdp_dir, "\n")
    return(NULL)
  }

  # Look for .xls/.xlsx files
  gdp_files <- list.files(gdp_dir, pattern = "\\.(xls|xlsx|csv|rds|qs2)$",
                           full.names = TRUE, ignore.case = TRUE)
  if (length(gdp_files) == 0) {
    cat("  WARNING: No data files found in", gdp_dir, "\n")
    return(NULL)
  }

  gdp_list <- list()
  for (gf in gdp_files) {
    ext <- tolower(tools::file_ext(gf))
    cat("  Loading:", basename(gf), "\n")

    if (ext %in% c("xls", "xlsx")) {
      if (!requireNamespace("readxl", quietly = TRUE)) {
        cat("    WARNING: readxl package not installed, skipping\n")
        next
      }
      sheets <- readxl::excel_sheets(gf)
      # Use the first sheet (or one with data-like name)
      sheet_use <- sheets[1]
      cat("    Using sheet:", sheet_use, "\n")
      tmp <- as.data.table(readxl::read_excel(gf, sheet = sheet_use))
    } else if (ext == "csv") {
      tmp <- fread(gf, showProgress = FALSE)
    } else if (ext == "rds") {
      tmp <- as.data.table(readRDS(gf))
    } else if (ext == "qs2") {
      tmp <- as.data.table(qs_read(gf))
    } else {
      next
    }

    cat("    Loaded:", nrow(tmp), "rows,", ncol(tmp), "cols\n")
    cat("    Columns:", paste(names(tmp), collapse = ", "), "\n")
    gdp_list[[length(gdp_list) + 1]] <- tmp
  }

  if (length(gdp_list) == 0) return(NULL)

  # Combine all files
  gdp <- rbindlist(gdp_list, use.names = TRUE, fill = TRUE)

  # Standardise columns
  muni_col <- intersect(c("cod_muni", "cod_municipio", "codigo_municipio",
                           "id_municipio", "muni_id", "muni_id_ibge",
                           "codmun", "municipio",
                           "Código do Município"), names(gdp))[1]
  if (is.na(muni_col)) {
    # Try partial match for Portuguese column names
    muni_col <- grep("(cod|codigo|id).*(muni|munic)", names(gdp),
                     value = TRUE, ignore.case = TRUE)[1]
  }
  if (is.na(muni_col)) {
    cat("  WARNING: Cannot identify municipality column. Available:\n    ",
        paste(names(gdp), collapse = ", "), "\n")
    return(NULL)
  }

  year_col <- intersect(c("ano", "year", "ANO", "Ano"), names(gdp))[1]
  if (is.na(year_col)) {
    year_col <- grep("^ano$", names(gdp), value = TRUE, ignore.case = TRUE)[1]
  }
  if (is.na(year_col)) {
    cat("  WARNING: Cannot identify year column.\n")
    return(NULL)
  }

  # GDP column — try several options
  pib_col <- intersect(c("pib", "PIB", "pib_total", "valor", "gdp",
                          "va_total", "Produto Interno Bruto, \na preços correntes\n(R$ 1.000)"),
                       names(gdp))[1]
  if (is.na(pib_col)) {
    pib_col <- grep("(pib|produto.*bruto|gdp)", names(gdp),
                    value = TRUE, ignore.case = TRUE)[1]
  }
  if (is.na(pib_col)) {
    cat("  WARNING: Cannot identify GDP column. Available:\n    ",
        paste(names(gdp), collapse = ", "), "\n")
    return(NULL)
  }

  cat(sprintf("  Using: muni=%s, year=%s, pib=%s\n", muni_col, year_col, pib_col))

  gdp[, muni_id := {
    m <- as.character(get(muni_col))
    as.integer(ifelse(nchar(m) == 7, substr(m, 1, 6), m))
  }]
  gdp[, year := as.integer(numify(get(year_col)))]
  gdp[, pib := numify(get(pib_col))]

  # PIB in source is R$ 1,000 — convert to R$
  # (IBGE PIB Municipal files report in thousands)
  gdp[, pib := pib * 1000]

  gdp_clean <- gdp[!is.na(muni_id) & !is.na(year) & !is.na(pib) & pib > 0,
                    .(pib = sum(pib, na.rm = TRUE)), by = .(muni_id, year)]

  cat("  GDP panel:", nrow(gdp_clean), "muni-years,",
      uniqueN(gdp_clean$muni_id), "municipalities\n")
  gdp_clean
}

gdp_dt <- load_gdp(gdp_dir)

if (!is.null(gdp_dt)) {
  n_before <- nrow(muni_yr)
  muni_yr <- merge(muni_yr, gdp_dt, by = c("muni_id", "year"), all.x = TRUE)
  n_matched <- sum(!is.na(muni_yr$pib))
  cat(sprintf("  GDP match: %d / %d (%.1f%%)\n",
              n_matched, n_before, 100 * n_matched / n_before))
  rm(gdp_dt)
} else {
  muni_yr[, pib := NA_real_]
}

# --- STEP 2b: Deflate GDP using IPCA (base 2018) ----------------------------

cat("\nStep 2b: Deflating GDP with IPCA...\n")

ipca_path <- make_base_path("raw/ipca_202509SerieHist.xlsx")

if (file.exists(ipca_path) && requireNamespace("readxl", quietly = TRUE)) {
  ipca_raw <- as.data.table(readxl::read_excel(ipca_path, skip = 6, col_names = FALSE))
  ipca_raw <- ipca_raw[, 1:4]
  base_names <- c("year", "month", "index", "variation")
  if (ncol(ipca_raw) >= length(base_names)) {
    setnames(ipca_raw, seq_along(base_names), base_names)
  } else {
    setnames(ipca_raw, base_names[seq_len(ncol(ipca_raw))])
  }
  suppressWarnings(ipca_raw <- ipca_raw[!is.na(index)])
  ipca_raw[, year   := as.integer(year)]
  ipca_raw[, month  := toupper(trimws(as.character(month)))]
  ipca_raw[, year   := nafill(year, type = "locf")]
  ipca_raw[, index  := suppressWarnings(as.numeric(index))]

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
    ipca_yearly[, deflator_2018 := base_val / ipca_avg]

    muni_yr[ipca_yearly, deflator_2018 := i.deflator_2018, on = .(year)]
    muni_yr[is.na(deflator_2018), deflator_2018 := 1]
    muni_yr[, pib_real := pib * deflator_2018]
    muni_yr[, deflator_2018 := NULL]

    cat(sprintf("  IPCA deflation applied (base %d). Deflator range: %.3f - %.3f\n",
                base_year,
                min(ipca_yearly$deflator_2018, na.rm = TRUE),
                max(ipca_yearly$deflator_2018, na.rm = TRUE)))
  } else {
    cat("  WARNING: Base year 2018 not in IPCA series; using nominal GDP\n")
    muni_yr[, pib_real := pib]
  }
  rm(ipca_raw, ipca_yearly)
} else {
  cat("  WARNING: IPCA file not found or readxl not available; using nominal GDP\n")
  muni_yr[, pib_real := pib]
}

# ==============================================================================
# STEP 3: Load population data
# ==============================================================================

cat("\nStep 3: Loading population data...\n")

if (file.exists(pop_cache)) {
  cat("  Loading cached population data\n")
  pop <- qs_read(pop_cache)
  setDT(pop)
} else {
  cat("  Downloading population via basedosdados...\n")
  if (!requireNamespace("basedosdados", quietly = TRUE)) {
    cat("  WARNING: basedosdados package not installed.\n")
    cat("  Install with: install.packages('basedosdados')\n")
    cat("  Proceeding without population data.\n")
    pop <- NULL
  } else {
    tryCatch({
      basedosdados::set_billing_id("replication-paiva-2025")
      query <- "
        SELECT
          dados.ano as year,
          dados.id_municipio AS muni_id_ibge,
          dados.populacao as population
        FROM `basedosdados.br_ibge_populacao.municipio` AS dados
      "
      pop <- basedosdados::read_sql(query)
      setDT(pop)
      # Cache for future runs
      qs_save(pop, pop_cache)
      cat("  Downloaded and cached:", nrow(pop), "rows\n")
    }, error = function(e) {
      cat("  WARNING: Population download failed:", conditionMessage(e), "\n")
      cat("  Proceeding without population data.\n")
      pop <<- NULL
    })
  }
}

if (!is.null(pop)) {
  # Standardise
  if ("muni_id_ibge" %in% names(pop)) {
    pop[, muni_id := {
      m <- as.character(muni_id_ibge)
      as.integer(ifelse(nchar(m) == 7, substr(m, 1, 6), m))
    }]
  }
  # Convert from integer64 (BigQuery/qs2) — class may be lost on reload,
  # so reattach it via bit64::as.integer64() before converting to base R types
  if (requireNamespace("bit64", quietly = TRUE)) {
    pop[, year := as.integer(bit64::as.integer64(year))]
    pop[, population := as.numeric(bit64::as.integer64(population))]
  } else {
    pop[, year := as.integer(year)]
    pop[, population := as.numeric(population)]
  }
  pop <- pop[!is.na(muni_id) & !is.na(year) & !is.na(population) & population > 0,
             .(population = sum(population)), by = .(muni_id, year)]

  cat("  Population panel:", nrow(pop), "muni-years\n")

  muni_yr <- merge(muni_yr, pop[, .(muni_id, year, population)],
                   by = c("muni_id", "year"), all.x = TRUE)
  n_pop <- sum(!is.na(muni_yr$population))
  cat(sprintf("  Population match: %d / %d (%.1f%%)\n",
              n_pop, nrow(muni_yr), 100 * n_pop / nrow(muni_yr)))
  rm(pop)
} else {
  muni_yr[, population := NA_real_]
}

# Compute GDP per capita (using deflated pib_real)
muni_yr[, gdp_pc := fifelse(!is.na(pib_real) & !is.na(population) & population > 0,
                            pib_real / population, NA_real_)]
muni_yr[, log_gdp_pc := fifelse(!is.na(gdp_pc) & gdp_pc > 0,
                                log(gdp_pc), NA_real_)]
muni_yr[, log_gdp := fifelse(!is.na(pib_real) & pib_real > 0, log(pib_real), NA_real_)]

cat(sprintf("  GDP per capita available: %d / %d (%.1f%%)\n",
            sum(!is.na(muni_yr$gdp_pc)), nrow(muni_yr),
            100 * mean(!is.na(muni_yr$gdp_pc))))

invisible(gc())

# ==============================================================================
# STEP 4: Build muni × sector × year panel (Panel A — first stage)
# ==============================================================================

cat("\nStep 4: Building muni × sector × year panel (Panel A)...\n")

# Load credit shares (delta_s_mjt)
if (!file.exists(credit_path)) {
  stop("Credit shares not found: ", credit_path, "\n  Run script 35 first.")
}
credit <- qs_read(credit_path)
setDT(credit)
cat("  Credit shares:", nrow(credit), "rows\n")

# Load sector-level instruments
if (!file.exists(instr_sec_path)) {
  stop("Sector instruments not found: ", instr_sec_path, "\n  Run script 34 first.")
}
instr_sec <- qs_read(instr_sec_path)
setDT(instr_sec)
cat("  Sector instruments:", nrow(instr_sec), "rows\n")

dz_cols <- grep("^dZ_", names(instr_sec), value = TRUE)
z_cols <- grep("^Z_", names(instr_sec), value = TRUE)
cat("  Changes instrument columns:", paste(dz_cols, collapse = ", "), "\n")
if (length(z_cols) > 0) {
  cat("  Levels instrument columns:", paste(z_cols, collapse = ", "), "\n")
}

# --- Skeleton selection (C2.2-partial, 2026-05-13) --------------------------
# When ENDOGENOUS == "emp_share": panel_a's skeleton comes from
# emp_share_panel_<SECTOR_VAR>.qs2 (script 32c). Credit shares are merged in
# afterwards as mechanism-check side variables. The BHJ §4.4 slack control
# travels with the skeleton.
# When ENDOGENOUS == "bndes_credit": existing behavior unchanged.

if (ENDOGENOUS == "emp_share") {
  emp_share_path <- make_output_path(
    sprintf("emp_share_panel_%s.qs2", SECTOR_VAR)
  )
  if (!file.exists(emp_share_path)) {
    stop("emp_share_panel not found: ", emp_share_path,
         "\n  Run script 32c with --sector-var=", SECTOR_VAR, " first.")
  }
  emp_share <- qs_read(emp_share_path)
  setDT(emp_share)
  cat(sprintf("  Loaded emp_share_panel [%s]: %d rows\n",
              SECTOR_VAR, nrow(emp_share)))

  # Schema check.
  emp_share_req <- c("muni_id", SCOL, "year", "n_jmt", "n_mt",
                     "s_emp_mjt", "delta_s_emp_mjt", "slack_frozen_mt")
  missing_es <- setdiff(emp_share_req, names(emp_share))
  if (length(missing_es)) {
    stop("emp_share_panel missing columns: ",
         paste(missing_es, collapse = ", "))
  }

  # Skeleton: (muni_id, sector_var, year, s_emp_mjt, delta_s_emp_mjt,
  #           slack_frozen_mt, n_jmt, n_mt).
  panel_a <- emp_share[, c("muni_id", SCOL, "year",
                           "n_jmt", "n_mt",
                           "s_emp_mjt", "delta_s_emp_mjt",
                           "slack_frozen_mt"), with = FALSE]
  rm(emp_share); invisible(gc())

  # Merge credit shares as mechanism-check side variables.
  credit_side <- credit[, c("muni_id", SCOL, "year",
                            intersect(c("s_mjt", "delta_s_mjt"), names(credit))),
                        with = FALSE]
  setnames(credit_side,
           old = intersect(c("s_mjt", "delta_s_mjt"), names(credit_side)),
           new = paste0(intersect(c("s_mjt", "delta_s_mjt"), names(credit_side)),
                        "_credit"))
  # Final names: s_mjt -> s_mjt_credit, delta_s_mjt -> delta_s_mjt_credit
  # Rename for clarity per spec: s_credit_mjt / delta_s_credit_mjt
  if ("s_mjt_credit" %in% names(credit_side)) {
    setnames(credit_side, "s_mjt_credit", "s_credit_mjt")
  }
  if ("delta_s_mjt_credit" %in% names(credit_side)) {
    setnames(credit_side, "delta_s_mjt_credit", "delta_s_credit_mjt")
  }

  panel_a <- merge(panel_a, credit_side,
                   by = c("muni_id", SCOL, "year"), all.x = TRUE)
  rm(credit_side, credit); invisible(gc())

  # Slack column binding condition (strategist review §A, BHJ §4.4):
  # slack_frozen_mt MUST be non-NA for every (muni_id, year) in panel_a.
  stopifnot(
    "slack_frozen_mt has NAs after emp_share skeleton load" =
      !any(is.na(panel_a$slack_frozen_mt))
  )

  # Naming aliases for downstream code: when ENDOGENOUS == "emp_share",
  # use s_emp_mjt / delta_s_emp_mjt in j0 selection, wide pivots, HHI.
  SHARE_COL  <- "s_emp_mjt"
  DSHARE_COL <- "delta_s_emp_mjt"
  cat(sprintf("  Panel A skeleton: emp_share (rows=%d). Share col: %s\n",
              nrow(panel_a), SHARE_COL))
} else {
  # Legacy bndes_credit path: skeleton from credit shares.
  panel_a <- copy(credit)
  SHARE_COL  <- "s_mjt"
  DSHARE_COL <- "delta_s_mjt"
  rm(credit); invisible(gc())
  cat(sprintf("  Panel A skeleton: bndes_credit (rows=%d). Share col: %s\n",
              nrow(panel_a), SHARE_COL))
}

# Merge sector-level instruments — split by baseline_type and suffix
for (bt in unique(instr_sec$baseline_type)) {
  sub <- instr_sec[baseline_type == bt,
                   c("muni_id", SCOL, "year", dz_cols), with = FALSE]
  suffix <- paste0("_", bt)
  dz_bt <- paste0(dz_cols, suffix)
  setnames(sub, dz_cols, dz_bt)

  panel_a <- merge(panel_a, sub, by = c("muni_id", SCOL, "year"), all.x = TRUE)

  for (zc in dz_bt) {
    panel_a[is.na(get(zc)), (zc) := 0]
  }
  cat(sprintf("  Merged sector changes instruments [%s]: %d matched\n",
              bt, sum(!is.na(sub[[dz_bt[1]]]))))
}

if (length(z_cols) > 0) {
  for (bt in unique(instr_sec$baseline_type)) {
    sub <- instr_sec[baseline_type == bt,
                     c("muni_id", SCOL, "year", z_cols), with = FALSE]
    suffix <- paste0("_", bt)
    z_bt <- paste0(z_cols, suffix)
    setnames(sub, z_cols, z_bt)

    panel_a <- merge(panel_a, sub, by = c("muni_id", SCOL, "year"), all.x = TRUE)

    for (zc in z_bt) {
      panel_a[is.na(get(zc)), (zc) := 0]
    }
    cat(sprintf("  Merged unified levels instruments [%s]\n", bt))
  }
}

rm(instr_sec); invisible(gc())

# Merge levels instruments (if available)
levels_sec_path <- sub("instruments_sector", "instruments_levels_sector", instr_sec_path)
if (length(z_cols) == 0L && file.exists(levels_sec_path)) {
  cat("  Loading levels instruments...\n")
  instr_lev <- qs_read(levels_sec_path)
  setDT(instr_lev)
  z_cols <- grep("^Z_", names(instr_lev), value = TRUE)
  cat("  Levels instrument columns:", paste(z_cols, collapse = ", "), "\n")

  for (bt in unique(instr_lev$baseline_type)) {
    sub <- instr_lev[baseline_type == bt,
                     c("muni_id", SCOL, "year", z_cols), with = FALSE]
    suffix <- paste0("_", bt)
    z_bt <- paste0(z_cols, suffix)
    setnames(sub, z_cols, z_bt)

    panel_a <- merge(panel_a, sub, by = c("muni_id", SCOL, "year"), all.x = TRUE)

    for (zc in z_bt) {
      panel_a[is.na(get(zc)), (zc) := 0]
    }
    cat(sprintf("  Merged levels instruments [%s]\n", bt))
  }
  rm(instr_lev); invisible(gc())
} else if (length(z_cols) == 0L) {
  cat("  Levels instruments not found (optional) — skipping\n")
}

# Merge municipality-sector exposure controls (if available)
if (file.exists(controls_sec_path)) {
  cat("  Loading sector exposure controls...\n")
  ctrl <- qs_read(controls_sec_path)
  setDT(ctrl)
  ctrl_vars <- grep("^exposure_control", names(ctrl), value = TRUE)
  if (!length(ctrl_vars)) {
    cat("  No sector exposure control columns found — skipping\n")
  } else {
    for (bt in unique(ctrl$baseline_type)) {
      sub <- ctrl[baseline_type == bt,
                  c("muni_id", SCOL, "year", ctrl_vars), with = FALSE]
      suffix <- paste0("_", bt)
      ctrl_bt <- paste0(ctrl_vars, suffix)
      setnames(sub, ctrl_vars, ctrl_bt)

      panel_a <- merge(panel_a, sub, by = c("muni_id", SCOL, "year"), all.x = TRUE)
      for (cc in ctrl_bt) panel_a[is.na(get(cc)), (cc) := 0]
      cat(sprintf("  Merged sector exposure controls [%s]\n", bt))
    }
  }
  rm(ctrl); invisible(gc())
} else {
  cat("  Sector exposure controls not found (optional) — skipping\n")
}

# Merge muni-year controls from muni_yr
panel_a <- merge(panel_a, muni_yr[, .(muni_id, year, total_employment, n_firms,
                                       log_gdp_pc, log_gdp, gdp_pc, pib,
                                       population, state_id)],
                 by = c("muni_id", "year"), all.x = TRUE)

cat("  Panel A:", nrow(panel_a), "rows,",
    uniqueN(panel_a$muni_id), "munis,",
    uniqueN(panel_a[[SCOL]]), "sectors,",
    uniqueN(panel_a$year), "years\n")

# ==============================================================================
# STEP 5: Build muni × year panel (Panel B — second stage)
# ==============================================================================

cat("\nStep 5: Building muni × year panel (Panel B)...\n")

# Merge muni-level instruments
if (!file.exists(instr_path)) {
  stop("Muni instruments not found: ", instr_path, "\n  Run script 34 first.")
}
instr_muni <- qs_read(instr_path)
setDT(instr_muni)

dz_cols_muni <- grep("^dZ_(mayor|gov|pres)_", names(instr_muni), value = TRUE)
z_cols_muni <- grep("^Z_(mayor|gov|pres)_", names(instr_muni), value = TRUE)

panel_b <- copy(muni_yr)

for (bt in unique(instr_muni$baseline_type)) {
  sub <- instr_muni[baseline_type == bt,
                    c("muni_id", "year", dz_cols_muni), with = FALSE]
  suffix <- paste0("_", bt)
  dz_bt <- paste0(dz_cols_muni, suffix)
  setnames(sub, dz_cols_muni, dz_bt)

  panel_b <- merge(panel_b, sub, by = c("muni_id", "year"), all.x = TRUE)

  for (zc in dz_bt) {
    panel_b[is.na(get(zc)), (zc) := 0]
  }

  if (length(z_cols_muni) > 0) {
    z_sub <- instr_muni[baseline_type == bt,
                        c("muni_id", "year", z_cols_muni), with = FALSE]
    z_bt <- paste0(z_cols_muni, suffix)
    setnames(z_sub, z_cols_muni, z_bt)

    panel_b <- merge(panel_b, z_sub, by = c("muni_id", "year"), all.x = TRUE)

    for (zc in z_bt) {
      panel_b[is.na(get(zc)), (zc) := 0]
    }
  }
}

rm(instr_muni); invisible(gc())

cat("  Panel B (base):", nrow(panel_b), "rows,",
    uniqueN(panel_b$muni_id), "municipalities\n")

# --- Step 5b: Determine dropped sector and build wide-format columns ---------

cat("\nStep 5b: Building wide-format sector columns for vector 2SLS and AR...\n")

# Determine j0 (dropped sector): largest average share.
# Under --endogenous=emp_share, share column is s_emp_mjt; under bndes_credit
# it is s_mjt. Deterministic alphabetical tiebreak on SECTOR_VAR.
sec_shares <- panel_a[!is.na(get(SHARE_COL)),
                      .(mean_share = mean(get(SHARE_COL))),
                      by = SCOL]
setorderv(sec_shares, c("mean_share", SCOL), order = c(-1L, 1L))
j0 <- sec_shares[[SCOL]][1]
cat(sprintf("  Dropped sector (j0): %s (mean share = %.4f)\n",
            j0, sec_shares$mean_share[1]))
cat("  Sector shares:\n")
print(sec_shares)

sec_all <- sec_shares[[SCOL]]
sec_iv <- setdiff(sec_all, j0)
sec_ar <- sec_all

make_sector_wide <- function(dt, value_col, sectors, out_prefix, fill = NULL) {
  if (!length(sectors)) {
    return(data.table(muni_id = integer(), year = integer()))
  }

  source <- dt[
    get(SCOL) %in% sectors,
    c("muni_id", "year", SCOL, value_col),
    with = FALSE
  ]

  if (is.null(fill)) {
    wide <- dcast(
      source,
      as.formula(paste("muni_id + year ~", SCOL)),
      value.var = value_col
    )
  } else {
    wide <- dcast(
      source,
      as.formula(paste("muni_id + year ~", SCOL)),
      value.var = value_col,
      fill = fill
    )
  }

  sector_cols <- setdiff(names(wide), c("muni_id", "year"))
  setnames(wide, sector_cols, paste0(out_prefix, "_", sector_cols))
  wide
}

# Pivot delta share to wide (excluding j0)
# Do not zero-fill: undefined deltas (e.g. first year) must stay NA.
# Column-name prefix kept as "delta_s" / "s" regardless of endogenous source,
# so downstream regex patterns in scripts 53/54 remain stable.
delta_s_wide <- make_sector_wide(panel_a, DSHARE_COL, sec_iv, "delta_s")

# Pivot share level to wide (for levels specification)
s_wide <- make_sector_wide(panel_a, SHARE_COL, sec_iv, "s", fill = 0)

# AR namespace (all-J) wide pivots — additionally emit ar_delta_s_*, ar_s_*
# only when ENDOGENOUS == "emp_share", since the AR pivot on the realised
# share vector is the load-bearing endogenous side. Under bndes_credit the
# AR namespace for shares is not used downstream.
if (ENDOGENOUS == "emp_share") {
  ar_delta_s_wide <- make_sector_wide(panel_a, DSHARE_COL, sec_ar, "ar_delta_s")
  ar_s_wide       <- make_sector_wide(panel_a, SHARE_COL,  sec_ar, "ar_s", fill = 0)
} else {
  ar_delta_s_wide <- NULL
  ar_s_wide       <- NULL
}

# Pivot sector-level instruments to wide.
# Existing names remain J-1 for structural share/2SLS specs.
# The ar_* namespace keeps all J sectors for reduced-form AR tests, where the
# BNDES share simplex does not require dropping a sector.
dz_sec_cols <- grep("^dZ_.*_cycle_specific$", names(panel_a), value = TRUE)
dz_sec_cols_fixed <- grep("^dZ_.*_2002_fixed$", names(panel_a), value = TRUE)
z_sec_cols <- grep("^Z_.*_cycle_specific$", names(panel_a), value = TRUE)
z_sec_cols_fixed <- grep("^Z_.*_2002_fixed$", names(panel_a), value = TRUE)
sector_inst_cols <- c(dz_sec_cols, dz_sec_cols_fixed, z_sec_cols, z_sec_cols_fixed)
z_sec_wide_list <- list()
for (zc in sector_inst_cols) {
  z_sec_wide_list[[paste0("iv__", zc)]] <- make_sector_wide(
    panel_a, zc, sec_iv, zc, fill = 0
  )
  z_sec_wide_list[[paste0("ar__", zc)]] <- make_sector_wide(
    panel_a, zc, sec_ar, paste0("ar_", zc), fill = 0
  )
}

# Pivot all-sector exposure controls for AR robustness checks only.
ctrl_sec_cols <- grep("^exposure_control.*_(cycle_specific|2002_fixed)$",
                      names(panel_a), value = TRUE)
for (cc in ctrl_sec_cols) {
  z_sec_wide_list[[paste0("ar__", cc)]] <- make_sector_wide(
    panel_a, cc, sec_ar, paste0("ar_", cc), fill = 0
  )
}

# Merge all wide columns into Panel B
panel_b <- merge(panel_b, delta_s_wide, by = c("muni_id", "year"), all.x = TRUE)
panel_b <- merge(panel_b, s_wide, by = c("muni_id", "year"), all.x = TRUE)
if (!is.null(ar_delta_s_wide)) {
  panel_b <- merge(panel_b, ar_delta_s_wide,
                   by = c("muni_id", "year"), all.x = TRUE)
}
if (!is.null(ar_s_wide)) {
  panel_b <- merge(panel_b, ar_s_wide,
                   by = c("muni_id", "year"), all.x = TRUE)
}
for (zw in z_sec_wide_list) {
  panel_b <- merge(panel_b, zw, by = c("muni_id", "year"), all.x = TRUE)
}

# Slack propagation (BHJ §4.4): carry slack_frozen_mt onto panel_b as a
# muni-year quantity. Only present when ENDOGENOUS == "emp_share".
if (ENDOGENOUS == "emp_share") {
  slack_my <- unique(panel_a[, .(muni_id, year, slack_frozen_mt)])
  stopifnot(
    "slack_frozen_mt not unique at (muni_id, year)" =
      uniqueN(slack_my[, .(muni_id, year)]) == nrow(slack_my)
  )
  panel_b <- merge(panel_b, slack_my, by = c("muni_id", "year"), all.x = TRUE)
  stopifnot(
    "panel_b not unique at (muni_id, year) after slack merge" =
      uniqueN(panel_b[, .(muni_id, year)]) == nrow(panel_b)
  )
  # Slack must be defined for every muni-year in Panel B (downstream
  # specification gate). Drop muni-years not in emp_share_panel skeleton, or
  # NA-fill = 1 if it's a pure muni_yr row absent from emp_share_panel.
  # Hybrid memo binding condition: prefer dropping NAs to keep BHJ §4.4 valid.
  na_slack <- sum(is.na(panel_b$slack_frozen_mt))
  if (na_slack > 0L) {
    cat(sprintf("  Dropping %d muni-year rows with NA slack_frozen_mt (not in emp_share skeleton)\n",
                na_slack))
    panel_b <- panel_b[!is.na(slack_frozen_mt)]
  }
  stopifnot(
    "slack_frozen_mt still has NAs in panel_b" =
      !any(is.na(panel_b$slack_frozen_mt))
  )
  cat(sprintf("  Slack propagated: range [%.4f, %.4f], mean=%.4f\n",
              min(panel_b$slack_frozen_mt),
              max(panel_b$slack_frozen_mt),
              mean(panel_b$slack_frozen_mt)))
}

# --- Step 5b': Build muni-total exposure controls (row-sum across sectors) ----
# R0a sensitivity: EC^ell_mt = sum_j sum_p w^ell_jmp,t. Row-sum the existing
# ar_exposure_control_*_<sector> columns; one ec_total_* column per (infix,
# tier, baseline) stem. See logs/strategy/strategy_memo_ar_test.md §3.1.

cat("\n  Building muni-total exposure controls (sum across sectors)...\n")
ec_total_added <- character(0)
for (cc in ctrl_sec_cols) {
  ar_cols <- paste0("ar_", cc, "_", sec_ar)
  ar_cols <- intersect(ar_cols, names(panel_b))
  if (!length(ar_cols)) next
  total_col <- sub("^exposure_control", "ec_total", cc)
  panel_b[, (total_col) := rowSums(.SD, na.rm = TRUE), .SDcols = ar_cols]
  ec_total_added <- c(ec_total_added, total_col)
}
cat(sprintf("  Added %d muni-total EC columns (sample: %s)\n",
            length(ec_total_added),
            paste(head(ec_total_added, 4), collapse = ", ")))

# Fill NAs with 0 only for share and instrument columns.
# delta_s_* must keep NA when the underlying change is undefined.
fill_cols <- grep("^(s_|d?Z_|ar_d?Z_|ar_exposure_control)",
                  names(panel_b), value = TRUE)
for (fc in fill_cols) {
  panel_b[is.na(get(fc)), (fc) := 0]
}

# Compute HHI for scalar 2SLS
# HHI_mt = sum_j s_mjt^2 (or sum_j s_emp_mjt^2 under --endogenous=emp_share)
hhi <- panel_a[!is.na(get(SHARE_COL)),
               .(hhi = sum(get(SHARE_COL)^2, na.rm = TRUE)),
               by = .(muni_id, year)]
panel_b <- merge(panel_b, hhi, by = c("muni_id", "year"), all.x = TRUE)
# delta_hhi
setorder(panel_b, muni_id, year)
panel_b[, delta_hhi := hhi - shift(hhi, 1), by = muni_id]

# Log BNDES per capita
panel_b[, bndes_pc := fifelse(!is.na(total_bndes_real) & !is.na(population) & population > 0,
                              total_bndes_real / population, NA_real_)]
panel_b[, log_bndes_pc := fifelse(!is.na(bndes_pc) & bndes_pc > 0,
                                  log(bndes_pc), NA_real_)]

cat(sprintf("  Panel B with wide columns: %d rows, %d cols\n",
            nrow(panel_b), ncol(panel_b)))
cat(sprintf("  Structural wide sectors (J-1=%d): %s%s\n",
            length(sec_iv),
            paste(head(paste0("delta_s_", sec_iv), 5), collapse = ", "),
            if (length(sec_iv) > 5) ", ..." else ""))
cat(sprintf("  AR wide sectors (J=%d): %s\n",
            length(sec_ar), paste(sec_ar, collapse = ", ")))
cat(sprintf("  AR instrument columns: %d; AR exposure-control columns: %d\n",
            length(grep("^ar_d?Z_", names(panel_b), value = TRUE)),
            length(grep("^ar_exposure_control", names(panel_b), value = TRUE))))

# --- Step 5c: Download transfer data (optional) -----------------------------

cat("\nStep 5c: Downloading transfer data (optional)...\n")

transfers_cache <- make_output_path("transfers_ibge.qs2")

if (file.exists(transfers_cache)) {
  cat("  Loading cached transfer data\n")
  transfers <- qs_read(transfers_cache)
  setDT(transfers)
} else if (requireNamespace("basedosdados", quietly = TRUE)) {
  tryCatch({
    basedosdados::set_billing_id("replication-paiva-2025")
    query_transfers <- "
      SELECT
        ano AS year,
        id_municipio AS muni_id_ibge,
        -- Federal transfers (receitas de transferencias)
        SUM(CASE WHEN conta LIKE '1.7.2%' THEN valor ELSE 0 END) AS transfers_federal,
        SUM(CASE WHEN conta LIKE '1.7.1%' THEN valor ELSE 0 END) AS transfers_state,
        SUM(CASE WHEN conta LIKE '1.7%' THEN valor ELSE 0 END) AS transfers_total
      FROM `basedosdados.br_me_siconfi.municipio_receitas_orcamentarias`
      WHERE ano BETWEEN 2002 AND 2017
      GROUP BY ano, id_municipio
    "
    transfers <- basedosdados::read_sql(query_transfers)
    setDT(transfers)
    qs_save(transfers, transfers_cache)
    cat("  Downloaded and cached:", nrow(transfers), "rows\n")
  }, error = function(e) {
    cat("  WARNING: Transfer download failed:", conditionMessage(e), "\n")
    cat("  Proceeding without transfer data.\n")
    transfers <<- NULL
  })
} else {
  cat("  basedosdados not available; skipping transfer download\n")
  transfers <- NULL
}

if (!is.null(transfers) && nrow(transfers) > 0) {
  if ("muni_id_ibge" %in% names(transfers)) {
    transfers[, muni_id := {
      m <- as.character(muni_id_ibge)
      as.integer(ifelse(nchar(m) == 7, substr(m, 1, 6), m))
    }]
  }
  # Convert from integer64 (BigQuery/qs2) — reattach class before converting
  if (requireNamespace("bit64", quietly = TRUE)) {
    transfers[, year := as.integer(bit64::as.integer64(year))]
    for (tc in c("transfers_federal", "transfers_state", "transfers_total")) {
      if (tc %in% names(transfers)) transfers[, (tc) := as.numeric(bit64::as.integer64(get(tc)))]
    }
  } else {
    transfers[, year := as.integer(year)]
    for (tc in c("transfers_federal", "transfers_state", "transfers_total")) {
      if (tc %in% names(transfers)) transfers[, (tc) := as.numeric(get(tc))]
    }
  }
  transfers_clean <- transfers[!is.na(muni_id) & !is.na(year),
                               .(muni_id, year, transfers_federal, transfers_state, transfers_total)]

  panel_b <- merge(panel_b, transfers_clean, by = c("muni_id", "year"), all.x = TRUE)
  # Log transfers per capita
  panel_b[, log_transfers_pc := fifelse(
    !is.na(transfers_total) & !is.na(population) & population > 0 & transfers_total > 0,
    log(transfers_total / population), NA_real_)]
  n_trans <- sum(!is.na(panel_b$transfers_total))
  cat(sprintf("  Transfer match: %d / %d (%.1f%%)\n",
              n_trans, nrow(panel_b), 100 * n_trans / nrow(panel_b)))
  rm(transfers, transfers_clean)
} else {
  cat("  No transfer data available\n")
}

cat("  Panel B final:", nrow(panel_b), "rows,",
    uniqueN(panel_b$muni_id), "municipalities\n")

# --- Step 5d: Split-volume BNDES columns by recipient class -----------------
# C2.2-supplement (2026-05-13): add level columns to panel_b giving the
# muni-year sum of `value_dis_real_2018_total` broken out by recipient class
# (productive-firm / financial-institution / public-entity / other), plus a
# residual column for productive-firm loans NOT in the RAIS-merged panel.
#
# ============================================================================
# USER ADJUDICATION 2026-05-13 — four-way volume split (locked):
#   Primary volume control (default):
#     total_bndes_real                    RAIS-merged productive (D1 universe)
#   Robustness split-volume components:
#     bndes_total_productive_nonRAIS_mt   productive-firm loans NOT in RAIS
#                                         = bndes_total_productive_all_mt
#                                           - total_bndes_real
#     bndes_total_fi_mt                   financial-intermediary loans
#     bndes_total_public_mt               public-entity loans
#     bndes_total_other_mt                residual (= 0 per D3.1)
#   Identity:
#     bndes_total_productive_all_mt =
#         total_bndes_real + bndes_total_productive_nonRAIS_mt
#
# Note: bndes_total_productive_all_mt is the BROADER productive aggregate from
# D3.1 (all private/CNAE firms), NOT the RAIS-merged subset. The RAIS-merged
# subset is total_bndes_real (script-22 reconstruction). The residual
# bndes_total_productive_nonRAIS_mt captures the productive-firm loans that
# fall outside the RAIS-merged analyzed universe.
# ============================================================================
#
# Source: data/processed/bndes_loans_by_recipient_class_my.qs2 (D3.1 output,
# 56,103 rows, keyed on muni_id_ibge6 × year × recipient_class). The
# muni_id_ibge6 column is the 6-digit IBGE code, which is the SAME variable
# panel_b uses as `muni_id` (script 41 truncates 7-digit IBGE to 6 digits at
# every load point — see lines 327, 457, 1005). The bridge is therefore an
# identity rename; we still assert uniqueness of the mapping.
#
# Backward compatibility: if the recipient-class aggregate does not exist
# (e.g., user pulled a snapshot from before D3.1), emit a warning and skip.

recipient_class_path <- make_output_path("bndes_loans_by_recipient_class_my.qs2")
RECIPIENT_CLASSES <- c("productive-firm", "financial-institution",
                       "public-entity", "other")
RECIPIENT_CLASS_SUFFIX <- c(
  "productive-firm"        = "productive_all",
  "financial-institution"  = "fi",
  "public-entity"          = "public",
  "other"                  = "other"
)

if (file.exists(recipient_class_path)) {
  cat("\nStep 5d: Merging split-volume BNDES columns by recipient class...\n")
  cat("  Loading:", basename(recipient_class_path), "\n")

  rc <- qs_read(recipient_class_path)
  setDT(rc)
  cat(sprintf("  Recipient-class aggregate: %d rows\n", nrow(rc)))

  # Muni-id bridge: muni_id_ibge6 (6-digit IBGE) → muni_id (panel_b also 6-digit).
  # Build an explicit crosswalk just for the assertion: it must be one-to-one.
  rc[, muni_id := as.integer(muni_id_ibge6)]
  crosswalk <- unique(rc[, .(muni_id_ibge6, muni_id)])
  stopifnot(
    "muni_id_ibge6 not unique in crosswalk" =
      uniqueN(crosswalk[, muni_id_ibge6]) == nrow(crosswalk),
    "muni_id not unique in crosswalk" =
      uniqueN(crosswalk[, muni_id]) == nrow(crosswalk)
  )

  # Report unmatched munis (recipient-class munis not in panel_b universe).
  rc_munis <- unique(rc$muni_id)
  pb_munis <- unique(panel_b$muni_id)
  n_unmatched <- length(setdiff(rc_munis, pb_munis))
  cat(sprintf("  Crosswalk: %d unique muni_id_ibge6, %d unmatched in panel_b\n",
              length(rc_munis), n_unmatched))
  if (n_unmatched > 0L) {
    cat(sprintf("    First unmatched: %s\n",
                paste(head(setdiff(rc_munis, pb_munis), 5),
                      collapse = ", ")))
  }

  # Coerce recipient_class to known set and produce the wide column names.
  unknown_classes <- setdiff(unique(rc$recipient_class), RECIPIENT_CLASSES)
  if (length(unknown_classes)) {
    warning("Unknown recipient_class values in aggregate: ",
            paste(unknown_classes, collapse = ", "),
            " (will be ignored)")
    rc <- rc[recipient_class %in% RECIPIENT_CLASSES]
  }

  # Wide pivot: (muni_id × year) → one column per recipient_class.
  rc_wide <- dcast(
    rc,
    muni_id + year ~ recipient_class,
    value.var = "value_dis_real_2018_total",
    fun.aggregate = sum,
    fill = 0
  )

  # Ensure all four classes are present as columns (zero-fill if a class never
  # appeared in the aggregate — e.g., D3.1 reported "other" share is 0%).
  for (rcls in RECIPIENT_CLASSES) {
    if (!rcls %in% names(rc_wide)) {
      rc_wide[, (rcls) := 0]
    }
  }

  # Rename to bndes_total_<suffix>_mt.
  new_col_names <- paste0("bndes_total_", RECIPIENT_CLASS_SUFFIX, "_mt")
  setnames(rc_wide,
           old = RECIPIENT_CLASSES,
           new = new_col_names)
  rc_wide <- rc_wide[, c("muni_id", "year", new_col_names), with = FALSE]

  # Left-join into panel_b on (muni_id, year). Muni-years with no BNDES
  # activity (or absent from the recipient-class file) get NA, then zero-fill.
  panel_b <- merge(panel_b, rc_wide,
                   by = c("muni_id", "year"), all.x = TRUE)
  for (nc in new_col_names) {
    panel_b[is.na(get(nc)), (nc) := 0]
  }

  stopifnot(
    "panel_b not unique at (muni_id, year) after recipient-class merge" =
      uniqueN(panel_b[, .(muni_id, year)]) == nrow(panel_b)
  )

  # ----------------------------------------------------------------------
  # Build residual productive-nonRAIS column (user adjudication 2026-05-13).
  # ----------------------------------------------------------------------
  # bndes_total_productive_nonRAIS_mt = bndes_total_productive_all_mt
  #                                     - total_bndes_real
  # This is the productive-firm loan volume sitting OUTSIDE the RAIS-merged
  # analyzed universe (script-22 reconstruction).
  if (!"total_bndes_real" %in% names(panel_b)) {
    stop("total_bndes_real missing — cannot build bndes_total_productive_nonRAIS_mt.")
  }
  panel_b[, bndes_total_productive_nonRAIS_mt :=
            bndes_total_productive_all_mt - total_bndes_real]

  # Sign sanity: residual must be non-negative within floating-point
  # tolerance. A substantially negative value would imply total_bndes_real
  # contains loans absent from the D3.1 broader productive aggregate, which
  # would indicate a deeper definitional inconsistency upstream.
  min_residual <- min(panel_b$bndes_total_productive_nonRAIS_mt, na.rm = TRUE)
  n_negative   <- sum(panel_b$bndes_total_productive_nonRAIS_mt < -1e-3,
                      na.rm = TRUE)
  cat(sprintf("  Sign sanity (productive_nonRAIS): min = %.6f R$, n(<-1e-3) = %d\n",
              min_residual, n_negative))
  stopifnot(
    "bndes_total_productive_nonRAIS_mt has substantial negative values (>-1e-3)" =
      all(panel_b$bndes_total_productive_nonRAIS_mt >= -1e-3)
  )

  # Identity check: productive_all == total_bndes_real + productive_nonRAIS
  # (by construction; residual should be near machine epsilon).
  identity_resid <- max(abs(
    panel_b$bndes_total_productive_all_mt -
      panel_b$total_bndes_real -
      panel_b$bndes_total_productive_nonRAIS_mt
  ), na.rm = TRUE)
  cat(sprintf("  Identity check: max |productive_all - total_bndes_real - productive_nonRAIS| = %.3e\n",
              identity_resid))
  stopifnot(
    "Productive-volume identity violated (>1e-6 R$)" =
      identity_resid < 1e-6
  )

  # Aggregate / per-muni-year diagnostics for the new residual column.
  agg_nonRAIS <- sum(panel_b$bndes_total_productive_nonRAIS_mt)
  med_nonRAIS <- median(panel_b$bndes_total_productive_nonRAIS_mt)
  max_nonRAIS <- max(panel_b$bndes_total_productive_nonRAIS_mt)
  cat(sprintf("  productive_nonRAIS aggregate = %.3e R$ (expect ~1.66e13 = 16.6 T R$)\n",
              agg_nonRAIS))
  cat(sprintf("  productive_nonRAIS per muni-year: median = %.2f R$, max = %.2e R$\n",
              med_nonRAIS, max_nonRAIS))
  if (abs(agg_nonRAIS - 1.66e13) > 1e12) {
    warning(sprintf(
      "productive_nonRAIS aggregate (%.3e R$) deviates from expected 16.6 T R$ by more than 1 T R$ — flag for review.",
      agg_nonRAIS))
  }

  # Legacy diagnostic: with productive_all renamed, this check no longer
  # expects equality with total_bndes_real. Just report the GAP between
  # productive_all and total_bndes_real (which equals productive_nonRAIS
  # by identity above).
  delta_prod <- panel_b$bndes_total_productive_all_mt - panel_b$total_bndes_real
  cat(sprintf("  Gap (productive_all - total_bndes_real): max = %.3e R$, mean = %.3e R$\n",
              max(delta_prod, na.rm = TRUE),
              mean(delta_prod, na.rm = TRUE)))

  # "Other" class should be zero per D3.1.
  other_sum <- sum(panel_b$bndes_total_other_mt)
  cat(sprintf("  Other-class total: %.2f R$ (D3.1 expects 0)\n", other_sum))
  if (other_sum > 1e-3) {
    warning(sprintf(
      "bndes_total_other_mt is non-zero (%.2f R$) — contradicts D3.1 reported 0%% share",
      other_sum))
  }

  # Per-year mean of each new column (diagnostic), including the residual.
  yearly_cols <- c(new_col_names, "bndes_total_productive_nonRAIS_mt")
  yearly_means <- panel_b[, lapply(.SD, mean, na.rm = TRUE),
                          .SDcols = yearly_cols, by = year]
  setorder(yearly_means, year)
  cat("  Per-year mean (R$ per muni) of split-volume columns ",
      "(incl. productive_nonRAIS):\n", sep = "")
  print(yearly_means)

  # Final column set present after Step 5d:
  #   total_bndes_real                    (primary; from script 22 reconstruction)
  #   bndes_total_productive_all_mt       (D3.1 broader productive aggregate)
  #   bndes_total_productive_nonRAIS_mt   (residual = productive_all - total_bndes_real)
  #   bndes_total_fi_mt                   (financial intermediary)
  #   bndes_total_public_mt               (public entity)
  #   bndes_total_other_mt                (residual; = 0 per D3.1)
  cat("  Five-way volume column set installed in panel_b: ",
      "total_bndes_real, bndes_total_productive_all_mt, ",
      "bndes_total_productive_nonRAIS_mt, bndes_total_fi_mt, ",
      "bndes_total_public_mt, bndes_total_other_mt\n", sep = "")

  rm(rc, rc_wide, crosswalk); invisible(gc())
} else {
  cat("\nStep 5d: Recipient-class aggregate not found at\n    ",
      recipient_class_path, "\n",
      "  Skipping split-volume column supplement (backward-compat path).\n",
      sep = "")
}

# ==============================================================================
# STEP 6: Diagnostics and save
# ==============================================================================

cat("\nStep 6: Summary and save...\n")

cat("\n  === Panel A (muni × sector × year) ===\n")
cat("  Rows:", format(nrow(panel_a), big.mark = ","), "\n")
cat("  Unique municipalities:", uniqueN(panel_a$muni_id), "\n")
cat(sprintf("  Unique %s: %d\n", SCOL, uniqueN(panel_a[[SCOL]])))
cat("  Years:", paste(range(panel_a$year), collapse = "-"), "\n")
for (v in unique(c(DSHARE_COL, SHARE_COL, "delta_s_mjt", "s_mjt", "log_gdp_pc"))) {
  if (v %in% names(panel_a)) {
    vals <- panel_a[[v]][is.finite(panel_a[[v]])]
    if (length(vals)) cat(sprintf("  %s: mean=%.4f, sd=%.4f, n=%d\n",
                                  v, mean(vals), sd(vals), length(vals)))
  }
}

cat("\n  === Panel B (muni × year) ===\n")
cat("  Rows:", nrow(panel_b), "\n")
cat("  Unique municipalities:", uniqueN(panel_b$muni_id), "\n")
cat("  Years:", paste(range(panel_b$year), collapse = "-"), "\n")
for (v in c("log_bndes", "total_employment", "log_gdp_pc", "log_gdp")) {
  if (v %in% names(panel_b)) {
    vals <- panel_b[[v]][is.finite(panel_b[[v]])]
    if (length(vals)) cat(sprintf("  %s: mean=%.4f, sd=%.4f, n=%d\n",
                                  v, mean(vals), sd(vals), length(vals)))
  }
}

# --- Drop unused columns to keep regression panels lean ----------------------

cat("\n  Dropping unused columns from Panel A...\n")
panel_a_drop <- intersect(
  c("bndes_mjt", "bndes_mt",
    "total_employment", "n_firms",
    "log_gdp_pc", "log_gdp", "gdp_pc", "pib", "population", "state_id"),
  names(panel_a)
)
if (length(panel_a_drop)) {
  cat("    Dropping:", paste(panel_a_drop, collapse = ", "), "\n")
  panel_a[, (panel_a_drop) := NULL]
}

cat("  Dropping unused columns from Panel B...\n")
# Note: s_* wide columns are retained for potential levels-specification second
# stage; log_gdp and population are retained for AR robustness/balance checks.
# total_bndes_real is RETAINED as the PRIMARY volume control (user adjudication
# 2026-05-13, four-way split). Other split-volume columns are also retained.
panel_b_drop <- intersect(
  c("total_employment", "n_firms", "n_bndes_firms",
    "log_bndes", "bndes_per_worker",
    "pib", "pib_real", "gdp_pc",
    "hhi", "log_bndes_pc",
    "transfers_federal", "transfers_state", "transfers_total"),
  names(panel_b)
)
if (length(panel_b_drop)) {
  cat("    Dropping:", paste(panel_b_drop, collapse = ", "), "\n")
  panel_b[, (panel_b_drop) := NULL]
}

cat(sprintf("  Panel A: %d cols remaining\n", ncol(panel_a)))
cat(sprintf("  Panel B: %d cols remaining\n", ncol(panel_b)))

cat("\nSaving...\n")

# Save muni employment classification (time-invariant)
setorder(muni_emp_class, muni_id)
qs_save(muni_emp_class[, .(muni_id, muni_emp_whole, muni_emp_quartile, top_q4_muni)],
        output_classification_path)
cat(sprintf("  Saved classification: %s (%.2f MB)\n",
            output_classification_path, file.size(output_classification_path) / 1024^2))

summ_class_41 <- muni_emp_class[, .(
  n_munis    = .N,
  mean_emp   = mean(muni_emp_whole, na.rm = TRUE),
  pct_top_q4 = mean(top_q4_muni) * 100
), by = muni_emp_quartile]
setorder(summ_class_41, muni_emp_quartile)
fwrite(summ_class_41, summary_classification_path)
cat(sprintf("  Saved classification summary: %s\n", summary_classification_path))

setorderv(panel_a, c("year", "muni_id", SCOL))
attr(panel_a, "endogenous") <- ENDOGENOUS
attr(panel_a, "share_col") <- SHARE_COL
attr(panel_a, "dshare_col") <- DSHARE_COL
attr(panel_a, "sector_var") <- SECTOR_VAR
qs_save(panel_a, output_sector_path)
cat(sprintf("  Saved Panel A: %s (%.2f MB)\n",
            output_sector_path, file.size(output_sector_path) / 1024^2))

attr(panel_b, "dropped_sector_j0") <- j0
attr(panel_b, "sector_var") <- SECTOR_VAR
attr(panel_b, "sectors_all") <- sec_all
attr(panel_b, "sectors_iv") <- sec_iv
attr(panel_b, "sectors_ar") <- sec_ar
attr(panel_b, "endogenous") <- ENDOGENOUS
attr(panel_b, "share_col") <- SHARE_COL
attr(panel_b, "dshare_col") <- DSHARE_COL
setorder(panel_b, year, muni_id)
qs_save(panel_b, output_muni_path)
cat(sprintf("  Saved Panel B: %s (%.2f MB)\n",
            output_muni_path, file.size(output_muni_path) / 1024^2))

# Summary CSV
summ <- panel_b[, .(
  n_obs = .N,
  n_munis = uniqueN(muni_id),
  mean_log_gdp_pc = mean(log_gdp_pc, na.rm = TRUE),
  mean_bndes_pc = mean(bndes_pc, na.rm = TRUE),
  mean_delta_hhi = mean(delta_hhi, na.rm = TRUE)
), by = year]
fwrite(summ, summary_path)
cat(sprintf("  Saved %s\n", summary_path))

cat("\nMunicipality panels complete.\n")
