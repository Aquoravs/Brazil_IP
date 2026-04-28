#!/usr/bin/env Rscript

# ==============================================================================
# Reconstruct Merged Panel from Raw Data
# ==============================================================================
# Builds a firm-municipality-year panel by:
#   1. Loading the RAIS universe from the merged fst/qs2/rds file
#   2. Re-joining BNDES loan data from script-11 aggregated output
#   3. Re-joining owner affiliation flags from raw data
#
# Inputs:
#   - output/rais_bndes_merged_for_regs.fst     (existing merged file, ~867 MB)
#   - output/bndes_firm_year_muni_sector.qs2    (script 11 output)
#   - raw/david_ra/owner_aff_firm_year_party_2002_2019.qs2  (owner affiliations)
#
# Outputs:
#   - output/rais_bndes_reconstructed.qs2   (primary)
#   - output/rais_bndes_reconstructed_summary.csv
#
# Usage:
#   Rscript 2_firm_panel/22_reconstruct_merged.R
# ==============================================================================

cat("==============================================================================\n")
cat("Reconstructing Merged Panel (Script 22)\n")
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

setDTthreads(parallel::detectCores() - 1)
qopt("nthreads", parallel::detectCores() - 1)

invisible(gc(full = TRUE))

save_diag_csv <- function(dt, filename, n_max = 5000L) {
  out_path <- make_output_path(file.path("diagnostics", "script22", filename))
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  fwrite(head(copy(dt), n_max), out_path)
  out_path
}

assert_unique_keys <- function(dt, keys, label, sample_file = NULL) {
  dupes <- dt[, .N, by = keys][N > 1L]
  if (!nrow(dupes)) return(invisible(TRUE))

  detail_path <- NULL
  if (!is.null(sample_file)) {
    detail_dt <- merge(dupes, dt, by = keys, allow.cartesian = TRUE)
    detail_path <- save_diag_csv(detail_dt, sample_file)
  }

  msg <- sprintf(
    "%s has %s duplicated rows by key (%s).",
    label,
    format(sum(dupes$N - 1L), big.mark = ","),
    paste(keys, collapse = ", ")
  )
  if (!is.null(detail_path)) {
    msg <- paste0(msg, "\n  Sample written to: ", detail_path)
  }
  stop(msg)
}

# Vectorized modal pick helper: sort dt by -count then value, take first per group.
# Used instead of per-group function calls for 10-50x speedup.

owner_cnae_conflicts_n <- 0L
owner_cnae_ties_n <- 0L
owner_cnae_conflicts_path <- NA_character_
rais_cnae_conflicts_n <- 0L
rais_cnae_ties_n <- 0L
rais_cnae_conflicts_path <- NA_character_
aff <- NULL
owner_flag <- NULL

# ==============================================================================
# Step 1: Load merged file, keep only RAIS columns
# ==============================================================================

cat("Step 1: Loading merged file and extracting RAIS universe...\n")

# Columns we actually need from the merged file
rais_keep_cols <- c("firm_id", "muni_id", "year", "n_employees",
                    "total_wage_nom", "n_establishments",
                    "classe", "merge_stage", "in_rais")

invisible(gc(full = TRUE))

# Prefer fst (column-selectable) > qs2 > rds
merged_path_fst <- make_output_path("rais_bndes_merged_for_regs.fst")
merged_path_qs2 <- make_output_path("rais_bndes_merged_for_regs.qs2")
merged_path_rds <- make_output_path("rais_bndes_merged_for_regs.rds")

if (file.exists(merged_path_fst) && requireNamespace("fst", quietly = TRUE)) {
  # Best path: read only the columns we need from fst (minimal memory)
  cat("  Loading from fst (column-selective):", basename(merged_path_fst), "\n")
  avail_cols <- fst::metadata_fst(merged_path_fst)$columnNames
  cols_to_read <- intersect(rais_keep_cols, avail_cols)
  rais_universe <- fst::read_fst(merged_path_fst,
                                 columns = cols_to_read,
                                 as.data.table = TRUE)
  cat("  Loaded:", format(nrow(rais_universe), big.mark = ","), "rows,",
      ncol(rais_universe), "columns (of", length(avail_cols), "available)\n")

} else if (file.exists(merged_path_qs2)) {
  cat("  Loading from qs2:", basename(merged_path_qs2), "\n")
  merged_raw <- qs_read(merged_path_qs2)
  setDT(merged_raw)
  cat("  Loaded:", format(nrow(merged_raw), big.mark = ","), "rows,",
      ncol(merged_raw), "columns\n")
  drop_cols <- setdiff(names(merged_raw), intersect(rais_keep_cols, names(merged_raw)))
  if (length(drop_cols)) merged_raw[, (drop_cols) := NULL]
  invisible(gc(full = TRUE))
  rais_universe <- merged_raw
  rm(merged_raw)
  invisible(gc(full = TRUE))

} else if (file.exists(merged_path_rds)) {
  cat("  Loading from rds:", basename(merged_path_rds), "\n")
  merged_raw <- readRDS(merged_path_rds)
  setDT(merged_raw)
  cat("  Loaded:", format(nrow(merged_raw), big.mark = ","), "rows,",
      ncol(merged_raw), "columns\n")
  drop_cols <- setdiff(names(merged_raw), intersect(rais_keep_cols, names(merged_raw)))
  if (length(drop_cols)) merged_raw[, (drop_cols) := NULL]
  invisible(gc(full = TRUE))
  rais_universe <- merged_raw
  rm(merged_raw)
  invisible(gc(full = TRUE))

} else {
  stop("Merged file not found in any format.\n",
       "  Checked: ", merged_path_fst, "\n",
       "  Checked: ", merged_path_qs2, "\n",
       "  Checked: ", merged_path_rds)
}

# Standardize key types: firm_id as integer, muni_id as integer
rais_universe[, firm_id := as.integer(firm_id)]
rais_universe[, muni_id := as.integer(muni_id)]
rais_universe[, year := as.integer(year)]

assert_cols(rais_universe, c("firm_id", "muni_id", "year", "classe"))
assert_unique_keys(
  rais_universe,
  keys = c("firm_id", "muni_id", "year"),
  label = "RAIS universe",
  sample_file = "duplicate_rais_keys.csv"
)

# Check for missing columns
rais_missing <- setdiff(rais_keep_cols, names(rais_universe))
if (length(rais_missing)) {
  cat("  WARNING: Missing expected RAIS columns:", paste(rais_missing, collapse = ", "), "\n")
}
cat("  Kept", ncol(rais_universe), "columns:", paste(names(rais_universe), collapse = ", "), "\n")

# Derive cnae_division (2-digit) and cnae_section (letter) from classe (5-digit)
# CNAE 2.0 hierarchy: classe (5d) -> class (4d) -> group (3d) -> division (2d) -> section (letter)
if ("classe" %in% names(rais_universe)) {
  rais_universe[, cnae_division := as.integer(floor(as.numeric(classe) / 1000))]

  # Official IBGE division-to-section mapping (CNAE 2.0)
  div_to_section <- data.table(
    cnae_division = c(
       1L,  2L,  3L,                                         # A
       5L,  6L,  7L,  8L,  9L,                               # B
      10L, 11L, 12L, 13L, 14L, 15L, 16L, 17L, 18L, 19L,     # C
      20L, 21L, 22L, 23L, 24L, 25L, 26L, 27L, 28L, 29L,     # C
      30L, 31L, 32L, 33L,                                     # C
      35L,                                                     # D
      36L, 37L, 38L, 39L,                                     # E
      41L, 42L, 43L,                                           # F
      45L, 46L, 47L,                                           # G
      49L, 50L, 51L, 52L, 53L,                                # H
      55L, 56L,                                                # I
      58L, 59L, 60L, 61L, 62L, 63L,                           # J
      64L, 65L, 66L,                                           # K
      68L,                                                     # L
      69L, 70L, 71L, 72L, 73L, 74L, 75L,                     # M
      77L, 78L, 79L, 80L, 81L, 82L,                           # N
      84L,                                                     # O
      85L,                                                     # P
      86L, 87L, 88L,                                           # Q
      90L, 91L, 92L, 93L,                                     # R
      94L, 95L, 96L,                                           # S
      97L,                                                     # T
      99L                                                      # U
    ),
    cnae_section = c(
      rep("A", 3),
      rep("B", 5),
      rep("C", 24),
      "D",
      rep("E", 4),
      rep("F", 3),
      rep("G", 3),
      rep("H", 5),
      rep("I", 2),
      rep("J", 6),
      rep("K", 3),
      "L",
      rep("M", 7),
      rep("N", 6),
      "O",
      "P",
      rep("Q", 3),
      rep("R", 4),
      rep("S", 3),
      "T",
      "U"
    )
  )

  rais_universe[div_to_section, cnae_section := i.cnae_section, on = "cnae_division"]
  
  cat("  Derived cnae_section from classe:",
      uniqueN(rais_universe[!is.na(cnae_section)]$cnae_section), "unique sections,",
      sum(is.na(rais_universe$cnae_section) & !is.na(rais_universe$cnae_division)),
      "rows with division but no section match\n")
  
  # Drop cnae_division
  rais_universe[, cnae_division := NULL]
}

# Ensure in_rais exists
if (!"in_rais" %in% names(rais_universe)) {
  rais_universe[, in_rais := 1L]
}

n_missing_cnae_rais <- sum(is.na(rais_universe$cnae_section))
n_total_rais <- nrow(rais_universe)
cat(sprintf("  RAIS cnae_section: %s missing / %s total (%.1f%%)\n",
            format(n_missing_cnae_rais, big.mark = ","),
            format(n_total_rais, big.mark = ","),
            100 * n_missing_cnae_rais / n_total_rais))

cat("  RAIS universe:", format(nrow(rais_universe), big.mark = ","), "rows\n")
cat("  Unique (firm_id, muni_id, year) keys:",
    format(uniqueN(rais_universe, by = c("firm_id", "muni_id", "year")), big.mark = ","), "\n")

invisible(gc(full = TRUE))
cat("  Memory cleaned\n\n")

# ==============================================================================
# Step 1b: Load owner affiliation data once and fill missing cnae_section (cnae5)
# ==============================================================================

cat("Step 1b: Loading owner affiliation data and filling missing cnae_section...\n")

aff_path_qs2 <- make_base_path("raw/david_ra/owner_aff_firm_year_party_2002_2019.qs2")
aff_path_parquet <- make_base_path("raw/david_ra/owner_aff_firm_year_party_2002_2019.parquet")
use_owner_parquet_fast_path <- file.exists(aff_path_parquet) &&
  requireNamespace("duckdb", quietly = TRUE) &&
  requireNamespace("DBI", quietly = TRUE)

if (use_owner_parquet_fast_path) {
  cat("  Fast path: reading owner data from parquet via DuckDB\n")
  parquet_sql_path <- normalizePath(aff_path_parquet, winslash = "/", mustWork = TRUE)

  con <- DBI::dbConnect(duckdb::duckdb())
  cols <- DBI::dbGetQuery(con, sprintf("SELECT * FROM '%s' LIMIT 0", parquet_sql_path))
  col_names <- names(cols)

  fid_col <- intersect(c("firm_id", "cnpj", "cnpj_raiz"), col_names)[1]
  yr_col <- intersect(c("year", "ano"), col_names)[1]
  cnae5_col <- intersect(c("cnae5", "cnae_5d", "cnae"), col_names)[1]

  required_owner_cols <- c(fid_col, yr_col)
  if (anyNA(required_owner_cols)) {
    DBI::dbDisconnect(con, shutdown = TRUE)
    stop("Owner parquet file is missing required key columns.\n",
         "  Available columns: ", paste(col_names, collapse = ", "))
  }

  DBI::dbWriteTable(con, "div_to_section_map", div_to_section,
                    temporary = TRUE, overwrite = TRUE)

  if (!is.na(cnae5_col)) {
    cat("  CNAE column in owner parquet:", cnae5_col, "\n")

    owner_cnae_sql <- sprintf("
      SELECT
        CAST(src.%s AS INTEGER) AS firm_id,
        CAST(src.%s AS INTEGER) AS year,
        map.cnae_section AS cnae_section_aff,
        COUNT(*) AS n_obs
      FROM '%s' src
      JOIN div_to_section_map map
        ON CAST(SUBSTR(TRIM(CAST(src.%s AS VARCHAR)), 1, 2) AS INTEGER) = map.cnae_division
      WHERE CAST(src.%s AS INTEGER) BETWEEN 2002 AND 2017
        AND src.%s IS NOT NULL
        AND src.%s IS NOT NULL
        AND src.%s IS NOT NULL
        AND TRIM(CAST(src.%s AS VARCHAR)) <> ''
      GROUP BY 1, 2, 3
    ",
      fid_col, yr_col, parquet_sql_path,
      cnae5_col,
      yr_col, fid_col, yr_col, cnae5_col, cnae5_col
    )

    aff_cnae_counts <- as.data.table(DBI::dbGetQuery(con, owner_cnae_sql))

    # Fast vectorized modal pick: sort by -count then alphabetical, take first
    setorder(aff_cnae_counts, firm_id, year, -n_obs, cnae_section_aff)
    aff_cnae_choice <- aff_cnae_counts[, .(cnae_section_aff = cnae_section_aff[1L]),
                                        by = .(firm_id, year)]

    # Conflict diagnostics (lightweight grouped op, no per-group allocations)
    conflict_stats <- aff_cnae_counts[, .(
      n_sections = .N,
      is_tie = .N > 1L && n_obs[1L] == n_obs[2L]
    ), by = .(firm_id, year)]
    owner_cnae_conflicts <- conflict_stats[n_sections > 1L]
    owner_cnae_conflicts_n <- nrow(owner_cnae_conflicts)
    owner_cnae_ties_n <- sum(owner_cnae_conflicts$is_tie)

    if (owner_cnae_conflicts_n > 0) {
      owner_cnae_conflicts_path <- save_diag_csv(
        owner_cnae_conflicts,
        "owner_cnae_conflicts.csv"
      )
      cat(sprintf(
        "  WARNING: %s owner (firm_id, year) keys map to multiple CNAE sections.\n",
        format(owner_cnae_conflicts_n, big.mark = ",")
      ))
      cat("  Assumption: choose the modal CNAE section; if tied, choose alphabetically first.\n")
      cat("  Conflict sample written to:", owner_cnae_conflicts_path, "\n")
    }

    cat(sprintf("  Owner CNAE mapping: %s unique (firm_id, year) entries\n",
                format(nrow(aff_cnae_choice), big.mark = ",")))

    rais_universe[aff_cnae_choice, cnae_section_aff := i.cnae_section_aff,
                  on = .(firm_id, year)]
    rais_universe[is.na(cnae_section) & !is.na(cnae_section_aff),
                  cnae_section := cnae_section_aff]
    rais_universe[, cnae_section_aff := NULL]

    n_filled_aff <- n_missing_cnae_rais - sum(is.na(rais_universe$cnae_section))
    cat(sprintf("  Filled from owner data: %s rows (%.1f%% of missing)\n",
                format(n_filled_aff, big.mark = ","),
                100 * n_filled_aff / n_missing_cnae_rais))

    rm(aff_cnae_counts, aff_cnae_choice, conflict_stats, owner_cnae_conflicts)
  } else {
    cat("  WARNING: No owner CNAE column found in parquet. Skipping owner-based CNAE fill.\n")
  }

  owner_flag_sql <- sprintf("
    SELECT DISTINCT
      CAST(%s AS INTEGER) AS firm_id,
      CAST(%s AS INTEGER) AS year
    FROM '%s'
    WHERE CAST(%s AS INTEGER) BETWEEN 2002 AND 2017
      AND %s IS NOT NULL
      AND %s IS NOT NULL
  ",
    fid_col, yr_col, parquet_sql_path,
    yr_col, fid_col, yr_col
  )

  owner_flag <- as.data.table(DBI::dbGetQuery(con, owner_flag_sql))
  owner_flag <- owner_flag[!is.na(firm_id) & !is.na(year)]
  owner_flag[, in_owner := 1L]
  cat(sprintf("  Owner flag table (parquet fast path): %s unique (firm_id, year) keys\n",
              format(nrow(owner_flag), big.mark = ",")))

  DBI::dbDisconnect(con, shutdown = TRUE)
  invisible(gc())

} else {
  if (!file.exists(aff_path_qs2)) {
    stop("Owner affiliation file not found in parquet or qs2 format.\n",
         "  Checked: ", aff_path_parquet, "\n",
         "  Checked: ", aff_path_qs2)
  }

  cat("  Fallback path: loading owner data from qs2\n")
  cat("  Loading:", basename(aff_path_qs2), "\n")
  aff_raw <- qs_read(aff_path_qs2)
  setDT(aff_raw)
  cat("  Raw rows:", format(nrow(aff_raw), big.mark = ","), "rows,",
      ncol(aff_raw), "columns\n")

  fid_col <- intersect(c("firm_id", "cnpj", "cnpj_raiz"), names(aff_raw))[1]
  yr_col <- intersect(c("year", "ano"), names(aff_raw))[1]
  muni_col <- intersect(c("muni_id", "muni_id_ibge6", "munin_id_ibge6"), names(aff_raw))[1]
  cnae5_col <- intersect(c("cnae5", "cnae_5d", "cnae"), names(aff_raw))[1]
  party_col <- intersect(c("party", "sigla_partido"), names(aff_raw))[1]
  aff_owners_col <- intersect(c("aff_owners", "n_aff_owners"), names(aff_raw))[1]
  share_aff_col <- intersect(c("share_aff_owners", "share_aff"), names(aff_raw))[1]

  required_owner_cols <- c(fid_col, yr_col)
  if (anyNA(required_owner_cols)) {
    stop("Owner affiliation file is missing required key columns.\n",
         "  Available columns: ", paste(names(aff_raw), collapse = ", "))
  }

  aff <- aff_raw[, .(
    firm_id = as.integer(get(fid_col)),
    year = as.integer(get(yr_col))
  )]
  if (!is.na(muni_col)) aff[, muni_id := as.integer(aff_raw[[muni_col]])]
  if (!is.na(cnae5_col)) aff[, cnae5 := trimws(as.character(aff_raw[[cnae5_col]]))]
  if (!is.na(party_col)) aff[, party := trimws(as.character(aff_raw[[party_col]]))]
  if (!is.na(aff_owners_col)) aff[, aff_owners := as.integer(aff_raw[[aff_owners_col]])]
  if (!is.na(share_aff_col)) aff[, share_aff_owners := as.numeric(aff_raw[[share_aff_col]])]
  rm(aff_raw); invisible(gc())

  cat("  Standardized owner columns:", paste(names(aff), collapse = ", "), "\n")

  if ("cnae5" %in% names(aff)) {
    cat("  CNAE column in owner data:", cnae5_col, "\n")

    aff_cnae <- aff[!is.na(firm_id) & !is.na(year) & !is.na(cnae5) & nzchar(cnae5),
                    .(firm_id, year, cnae5)]

    aff_cnae[, cnae_division_aff := as.integer(substr(cnae5, 1, 2))]
    aff_cnae[div_to_section, cnae_section_aff := i.cnae_section,
             on = .(cnae_division_aff = cnae_division)]
    aff_cnae_counts <- aff_cnae[!is.na(cnae_section_aff),
                                .(n_obs = .N),
                                by = .(firm_id, year, cnae_section_aff)]

    # Fast vectorized modal pick
    setorder(aff_cnae_counts, firm_id, year, -n_obs, cnae_section_aff)
    aff_cnae_choice <- aff_cnae_counts[, .(cnae_section_aff = cnae_section_aff[1L]),
                                        by = .(firm_id, year)]

    # Conflict diagnostics
    conflict_stats <- aff_cnae_counts[, .(
      n_sections = .N,
      is_tie = .N > 1L && n_obs[1L] == n_obs[2L]
    ), by = .(firm_id, year)]
    owner_cnae_conflicts <- conflict_stats[n_sections > 1L]
    owner_cnae_conflicts_n <- nrow(owner_cnae_conflicts)
    owner_cnae_ties_n <- sum(owner_cnae_conflicts$is_tie)

    if (owner_cnae_conflicts_n > 0) {
      owner_cnae_conflicts_path <- save_diag_csv(
        owner_cnae_conflicts,
        "owner_cnae_conflicts.csv"
      )
      cat(sprintf(
        "  WARNING: %s owner (firm_id, year) keys map to multiple CNAE sections.\n",
        format(owner_cnae_conflicts_n, big.mark = ",")
      ))
      cat("  Assumption: choose the modal CNAE section; if tied, choose alphabetically first.\n")
      cat("  Conflict sample written to:", owner_cnae_conflicts_path, "\n")
    }

    cat(sprintf("  Owner CNAE mapping: %s unique (firm_id, year) entries\n",
                format(nrow(aff_cnae_choice), big.mark = ",")))

    rais_universe[aff_cnae_choice, cnae_section_aff := i.cnae_section_aff,
                  on = .(firm_id, year)]
    rais_universe[is.na(cnae_section) & !is.na(cnae_section_aff),
                  cnae_section := cnae_section_aff]
    rais_universe[, cnae_section_aff := NULL]

    n_filled_aff <- n_missing_cnae_rais - sum(is.na(rais_universe$cnae_section))
    cat(sprintf("  Filled from owner data: %s rows (%.1f%% of missing)\n",
                format(n_filled_aff, big.mark = ","),
                100 * n_filled_aff / n_missing_cnae_rais))

    rm(aff_cnae, aff_cnae_counts, aff_cnae_choice, conflict_stats, owner_cnae_conflicts)
  } else {
    cat("  WARNING: No owner CNAE column found. Skipping owner-based CNAE fill.\n")
  }

  invisible(gc())
}

# ==============================================================================
# Step 1c: Fill remaining missing cnae_section from within-RAIS (modal per firm)
# ==============================================================================

cat("\nStep 1c: Filling remaining missing cnae_section from within-RAIS data...\n")

n_still_missing <- sum(is.na(rais_universe$cnae_section))
if (n_still_missing > 0) {
  # Compute modal cnae_section per firm_id from non-missing rows.
  # Assumption is explicit: choose the modal section; if tied, choose alphabetically first.
  firm_mode_counts <- rais_universe[!is.na(cnae_section),
                                    .(n_obs = .N),
                                    by = .(firm_id, cnae_section)]

  # Fast vectorized modal pick
  setorder(firm_mode_counts, firm_id, -n_obs, cnae_section)
  firm_mode <- firm_mode_counts[, .(cnae_section_mode = cnae_section[1L]),
                                 by = firm_id]

  # Conflict diagnostics
  conflict_stats <- firm_mode_counts[, .(
    n_sections = .N,
    is_tie = .N > 1L && n_obs[1L] == n_obs[2L]
  ), by = firm_id]
  rais_cnae_conflicts <- conflict_stats[n_sections > 1L]
  rais_cnae_conflicts_n <- nrow(rais_cnae_conflicts)
  rais_cnae_ties_n <- sum(rais_cnae_conflicts$is_tie)

  if (rais_cnae_conflicts_n > 0) {
    rais_cnae_conflicts_path <- save_diag_csv(
      rais_cnae_conflicts,
      "rais_modal_cnae_conflicts.csv"
    )
    cat(sprintf(
      "  WARNING: %s firms have multiple observed RAIS CNAE sections.\n",
      format(rais_cnae_conflicts_n, big.mark = ",")
    ))
    cat("  Assumption: choose the modal CNAE section; if tied, choose alphabetically first.\n")
    cat("  Conflict sample written to:", rais_cnae_conflicts_path, "\n")
  }

  rais_universe[firm_mode, cnae_section_mode := i.cnae_section_mode,
                on = "firm_id"]
  rais_universe[is.na(cnae_section) & !is.na(cnae_section_mode),
                cnae_section := cnae_section_mode]
  rais_universe[, cnae_section_mode := NULL]

  n_filled_rais <- n_still_missing - sum(is.na(rais_universe$cnae_section))
  cat(sprintf("  Filled from within-RAIS: %s rows (%.1f%% of remaining missing)\n",
              format(n_filled_rais, big.mark = ","),
              100 * n_filled_rais / n_still_missing))
  rm(firm_mode_counts, firm_mode, conflict_stats, rais_cnae_conflicts)
} else {
  cat("  No remaining missing cnae_section. Skipping.\n")
}

# ==============================================================================
# Step 1d: Fill remaining missing cnae_section from Receita Federal (PostgreSQL)
# ==============================================================================

cat("\nStep 1d: Filling remaining missing cnae_section from Receita Federal...\n")

n_still_missing_rfb <- sum(is.na(rais_universe$cnae_section))
if (n_still_missing_rfb > 0 && requireNamespace("RPostgres", quietly = TRUE)) {

  # Unique firm_ids still missing cnae_section
  firms_missing <- unique(rais_universe[is.na(cnae_section), .(firm_id)])
  firms_missing <- firms_missing[!is.na(firm_id)]
  cat(sprintf("  Firms still missing cnae_section: %s\n",
              format(nrow(firms_missing), big.mark = ",")))

  pg_con <- tryCatch(
    DBI::dbConnect(RPostgres::Postgres(),
                   dbname = "Dados_RFB",
                   host = "localhost",
                   port = 5432,
                   user = "postgres",
                   password = "postgres"),
    error = function(e) {
      cat("  WARNING: Could not connect to PostgreSQL:", conditionMessage(e), "\n")
      NULL
    }
  )

  if (!is.null(pg_con)) {
    # Upload missing firm_ids to a temp table
    DBI::dbWriteTable(pg_con, "missing_firms", firms_missing,
                      temporary = TRUE, overwrite = TRUE)

    # Query: get cnae_fiscal_principal from the main branch (cnpj_ordem = '0001')
    # Fall back to any branch if main branch not found
    rfb_query <- "
      WITH main_branch AS (
        SELECT DISTINCT ON (e.cnpj_basico)
          e.cnpj_basico AS firm_id,
          e.cnae_fiscal_principal AS cnae_rfb
        FROM estabelecimento e
        JOIN missing_firms mf ON e.cnpj_basico = LPAD(mf.firm_id::text, 8, '0')
        ORDER BY e.cnpj_basico, (e.cnpj_ordem = '0001') DESC
      )
      SELECT firm_id, cnae_rfb
      FROM main_branch
      WHERE cnae_rfb IS NOT NULL
    "

    rfb_result <- tryCatch(
      setDT(DBI::dbGetQuery(pg_con, rfb_query)),
      error = function(e) {
        cat("  WARNING: RFB query failed:", conditionMessage(e), "\n")
        data.table()
      }
    )

    DBI::dbDisconnect(pg_con)

    if (nrow(rfb_result) > 0) {
      # Convert firm_id back to integer (it comes as zero-padded string)
      rfb_result[, firm_id := as.integer(firm_id)]

      # Derive cnae_section from cnae_rfb (7-digit code, first 2 digits = division)
      rfb_result[, cnae_division_rfb := as.integer(substr(
        trimws(as.character(cnae_rfb)), 1, 2))]
      rfb_result[div_to_section, cnae_section_rfb := i.cnae_section,
                 on = .(cnae_division_rfb = cnae_division)]
      rfb_result <- rfb_result[!is.na(cnae_section_rfb)]

      # Deduplicate to one per firm_id
      rfb_result <- unique(rfb_result[, .(firm_id, cnae_section_rfb)],
                           by = "firm_id")

      cat(sprintf("  RFB lookup returned: %s firms with cnae_section\n",
                  format(nrow(rfb_result), big.mark = ",")))

      # Fill
      rais_universe[rfb_result, cnae_section_rfb := i.cnae_section_rfb,
                    on = "firm_id"]
      rais_universe[is.na(cnae_section) & !is.na(cnae_section_rfb),
                    cnae_section := cnae_section_rfb]
      rais_universe[, cnae_section_rfb := NULL]

      n_filled_rfb <- n_still_missing_rfb - sum(is.na(rais_universe$cnae_section))
      cat(sprintf("  Filled from RFB: %s rows (%.1f%% of remaining missing)\n",
                  format(n_filled_rfb, big.mark = ","),
                  100 * n_filled_rfb / n_still_missing_rfb))
      rm(rfb_result)
    } else {
      cat("  No matches from RFB query.\n")
    }

    rm(firms_missing)
  }

} else if (n_still_missing_rfb > 0) {
  cat("  RPostgres not available. Skipping RFB lookup.\n")
  cat(sprintf("  Rows still missing cnae_section: %s\n",
              format(n_still_missing_rfb, big.mark = ",")))
} else {
  cat("  No remaining missing cnae_section. Skipping.\n")
}

# --- Final CNAE imputation summary ---
n_final_missing <- sum(is.na(rais_universe$cnae_section))
cat(sprintf("\n  CNAE imputation summary:\n"))
cat(sprintf("    Total rows:            %s\n", format(n_total_rais, big.mark = ",")))
cat(sprintf("    Missing after RAIS:    %s (%.1f%%)\n",
            format(n_missing_cnae_rais, big.mark = ","),
            100 * n_missing_cnae_rais / n_total_rais))
cat(sprintf("    Still missing (final): %s (%.1f%%)\n",
            format(n_final_missing, big.mark = ","),
            100 * n_final_missing / n_total_rais))

invisible(gc(full = TRUE))

# ==============================================================================
# Step 2: Load BNDES aggregated data (script 11 output)
# ==============================================================================

cat("Step 2: Loading BNDES aggregated data...\n")

bndes_path <- make_output_path("bndes_firm_year_muni_sector.qs2")
if (!file.exists(bndes_path)) {
  stop("BNDES aggregated file not found: ", bndes_path, "\n  Run script 11 first.")
}

bndes_dt <- qs_read(bndes_path)
setDT(bndes_dt)
cat("  Loaded:", format(nrow(bndes_dt), big.mark = ","), "rows,",
    ncol(bndes_dt), "columns\n")
cat("  Columns:", paste(names(bndes_dt), collapse = ", "), "\n")
assert_cols(
  bndes_dt,
  c("firm_id", "year", "muni_id_ibge6",
    "value_dis_total", "value_dis_real_2018_total", "n_loans")
)

# Script 11 output has: firm_id (char), year, muni_id_ibge6 (int), cnae_section,
#                        value_dis_total, value_dis_real_2018_total, n_loans

# Filter to study period
bndes_dt <- bndes_dt[year >= 2002L & year <= 2017L]

# Collapse across cnae_section to get firm x muni x year totals
# (RAIS universe is at firm x muni x year level, not sector)
bndes_collapsed <- bndes_dt[, .(
  value_dis_total           = sum(value_dis_total, na.rm = TRUE),
  value_dis_real_2018_total = sum(value_dis_real_2018_total, na.rm = TRUE),
  n_loans                   = sum(n_loans, na.rm = TRUE)
), by = .(firm_id, muni_id_ibge6, year)]

# Standardize key names and types to match RAIS universe
bndes_collapsed[, firm_id := as.integer(firm_id)]
setnames(bndes_collapsed, "muni_id_ibge6", "muni_id")
bndes_collapsed[, muni_id := as.integer(muni_id)]
bndes_collapsed[, year := as.integer(year)]
bndes_collapsed[, in_bndes := 1L]
assert_unique_keys(
  bndes_collapsed,
  keys = c("firm_id", "muni_id", "year"),
  label = "Collapsed BNDES data",
  sample_file = "duplicate_bndes_keys.csv"
)

cat("  BNDES collapsed:", format(nrow(bndes_collapsed), big.mark = ","), "rows\n")
cat("  Unique firms:", format(uniqueN(bndes_collapsed$firm_id), big.mark = ","), "\n")
cat("  Year range:", paste(range(bndes_collapsed$year), collapse = "-"), "\n")

rm(bndes_dt); invisible(gc())

# ==============================================================================
# Step 3: Standardize owner affiliation data for owner-flag construction
# ==============================================================================

cat("\nStep 3: Standardizing owner affiliation data for owner flags...\n")
if (is.null(owner_flag)) {
  cat("  Reusing owner table loaded in Step 1b fallback path.\n")
  assert_cols(aff, c("firm_id", "year"))
  cat("  Columns:", paste(names(aff), collapse = ", "), "\n")

  # --- Standardize columns ---------------------------------------------------
  aff[, year := as.integer(year)]
  aff[, firm_id := as.integer(firm_id)]

  if ("muni_id" %in% names(aff)) {
    aff[, muni_id := as.integer(muni_id)]
  }

  if ("party" %in% names(aff)) {
    aff[, party := trimws(as.character(party))]
  }

  if ("aff_owners" %in% names(aff)) {
    aff[, aff_owners := as.integer(aff_owners)]
  }

  if ("share_aff_owners" %in% names(aff)) {
    aff[, share_aff_owners := as.numeric(share_aff_owners)]
    aff[share_aff_owners < 0, share_aff_owners := NA_real_]
    aff[share_aff_owners > 1, share_aff_owners := 1]
  }

  aff <- aff[year >= 2002L & year <= 2017L]
  cat("  After year filter:", format(nrow(aff), big.mark = ","), "rows\n")
} else {
  cat("  Owner flag already built in Step 1b parquet fast path.\n")
}

# ==============================================================================
# Step 4: Build in_owner flag from affiliation data
# ==============================================================================

cat("\nStep 4: Building in_owner flag...\n")

# Unique (firm_id, year) keys in affiliation data.
# Owner affiliation is a firm-level attribute valid across all municipalities
# where the firm operates, so we merge on (firm_id, year) only.
if (is.null(owner_flag)) {
  owner_flag <- unique(aff[, .(firm_id, year)])
  owner_flag <- owner_flag[!is.na(firm_id) & !is.na(year)]
  owner_flag[, in_owner := 1L]
}
assert_unique_keys(
  owner_flag,
  keys = c("firm_id", "year"),
  label = "Owner affiliation flag table",
  sample_file = "duplicate_owner_flag_keys.csv"
)

cat("  Owner flag table:", format(nrow(owner_flag), big.mark = ","),
    "unique (firm_id, year) keys\n")

# ==============================================================================
# Step 5: Left-join onto RAIS universe
# ==============================================================================

cat("\nStep 5: Left-joining BNDES and owner flags onto RAIS universe...\n")

# --- 5a: Left-join BNDES loans -----------------------------------------------
cat("  5a: Joining BNDES loans...\n")

setkey(rais_universe, firm_id, muni_id, year)
setkey(bndes_collapsed, firm_id, muni_id, year)

panel <- merge(rais_universe, bndes_collapsed,
               by = c("firm_id", "muni_id", "year"),
               all.x = TRUE)

# Fill unmatched
panel[is.na(in_bndes), in_bndes := 0L]

# Zero out loan values for non-BNDES rows
loan_value_cols <- intersect(
  c("value_dis_total", "value_dis_real_2018_total", "n_loans"),
  names(panel))
non_bndes_idx <- which(panel$in_bndes == 0L)
for (v in loan_value_cols) {
  set(panel, i = non_bndes_idx, j = v, value = 0)
}

cat("    Matched:", format(sum(panel$in_bndes == 1L), big.mark = ","),
    "rows with BNDES loans\n")
cat("    Unmatched (RAIS-only):", format(sum(panel$in_bndes == 0L), big.mark = ","),
    "rows\n")

rm(rais_universe, bndes_collapsed); invisible(gc())

# --- 5b: Left-join in_owner flag ---------------------------------------------
cat("  5b: Joining owner affiliation flag...\n")

setkey(owner_flag, firm_id, year)

panel <- merge(panel, owner_flag,
               by = c("firm_id", "year"),
               all.x = TRUE)
panel[is.na(in_owner), in_owner := 0L]

cat("    Matched:", format(sum(panel$in_owner == 1L), big.mark = ","),
    "rows with owner affiliations\n")
cat("    Unmatched:", format(sum(panel$in_owner == 0L), big.mark = ","), "rows\n")

rm(owner_flag); invisible(gc())

# --- 5c: Remove observations not in RAIS, BNDES, or owner data ---------------

panel <- panel[in_rais + in_bndes + in_owner > 0L]
cat("  Panel rows:", format(nrow(panel), big.mark = ","), "\n\n")

# ==============================================================================
# Step 6: Create regression variables
# ==============================================================================

cat("Step 6: Creating regression variables...\n")

if ("value_dis_total" %in% names(panel)) {
  panel[, logval  := log1p(pmax(0, as.numeric(value_dis_total)))]
  panel[, ihs_val := asinh(value_dis_total)]
} else {
  panel[, logval  := NA_real_]
  panel[, ihs_val := NA_real_]
}

if ("value_dis_real_2018_total" %in% names(panel)) {
  panel[, logval_real  := log1p(pmax(0, as.numeric(value_dis_real_2018_total)))]
  panel[, ihs_val_real := asinh(value_dis_real_2018_total)]
} else {
  panel[, logval_real  := NA_real_]
  panel[, ihs_val_real := NA_real_]
}

cat("  Created: logval, ihs_val, logval_real, ihs_val_real\n\n")

# ==============================================================================
# Step 7: Save outputs
# ==============================================================================

cat("Step 7: Saving outputs...\n")

# Drop invalid muni_id (0 is not a valid IBGE municipality code)
n_invalid_muni <- sum(panel$muni_id == 0L | is.na(panel$muni_id))
if (n_invalid_muni > 0L) {
  cat(sprintf("  Dropping %d rows with invalid muni_id (0 or NA)\n", n_invalid_muni))
  panel <- panel[!is.na(muni_id) & muni_id > 0L]
}

setorder(panel, year, firm_id, muni_id)

# --- Output 1: Base panel (qs2) -----------------------------------------------
out_qs2 <- make_output_path("rais_bndes_reconstructed.qs2")

cat("  Saving base panel...\n")
qs_save(panel, out_qs2)
cat(sprintf("    QS2: %s (%.2f MB)\n", out_qs2, file.size(out_qs2) / 1024^2))

if (requireNamespace("fst", quietly = TRUE)) {
  out_fst <- make_output_path("rais_bndes_reconstructed.fst")
  fst::write_fst(panel, out_fst, compress = 50)
  cat(sprintf("    FST: %s (%.2f MB)\n", out_fst, file.size(out_fst) / 1024^2))
}

rm(aff); invisible(gc())

# --- Output 2: Summary -------------------------------------------------------
cat("  Building summary...\n")

summary_dt <- data.table(
  metric = character(),
  value = numeric()
)

add_row <- function(m, v) {
  summary_dt <<- rbindlist(list(summary_dt, data.table(metric = m, value = v)))
}

add_row("total_rows", nrow(panel))
add_row("n_firms", uniqueN(panel$firm_id))
add_row("n_munis", uniqueN(panel$muni_id))
add_row("n_years", uniqueN(panel$year))
add_row("pct_in_rais", round(mean(panel$in_rais, na.rm = TRUE) * 100, 2))
add_row("pct_in_bndes", round(mean(panel$in_bndes) * 100, 4))
add_row("pct_in_owner", round(mean(panel$in_owner) * 100, 4))
add_row("n_in_bndes", sum(panel$in_bndes == 1L))
add_row("n_in_owner", sum(panel$in_owner == 1L))
add_row("mean_employees", round(mean(panel$n_employees, na.rm = TRUE), 2))
add_row("mean_loan_value", round(mean(panel$value_dis_total, na.rm = TRUE), 2))
add_row("n_cnae_missing_final", n_final_missing)
add_row("n_owner_cnae_conflicts", owner_cnae_conflicts_n)
add_row("n_owner_cnae_ties", owner_cnae_ties_n)
add_row("n_rais_cnae_conflicts", rais_cnae_conflicts_n)
add_row("n_rais_cnae_ties", rais_cnae_ties_n)

summary_path <- make_output_path("rais_bndes_reconstructed_summary.csv")
fwrite(summary_dt, summary_path)
cat(sprintf("    %s\n", summary_path))

# --- Print summary to console ------------------------------------------------
cat("\n==============================================================================\n")
cat("RECONSTRUCTION SUMMARY\n")
cat("==============================================================================\n")
cat(sprintf("  Total rows:                  %s\n", format(nrow(panel), big.mark = ",")))
cat(sprintf("  Unique firms:                %s\n", format(uniqueN(panel$firm_id), big.mark = ",")))
cat(sprintf("  Unique municipalities:       %s\n", format(uniqueN(panel$muni_id), big.mark = ",")))
cat(sprintf("  Year range:                  %s\n", paste(range(panel$year), collapse = "-")))
cat(sprintf("  in_rais == 1:                %s (%.1f%%)\n",
            format(sum(panel$in_rais == 1L, na.rm = TRUE), big.mark = ","),
            mean(panel$in_rais, na.rm = TRUE) * 100))
cat(sprintf("  in_bndes == 1:               %s (%.4f%%)\n",
            format(sum(panel$in_bndes == 1L), big.mark = ","),
            mean(panel$in_bndes) * 100))
cat(sprintf("  in_owner == 1:               %s (%.4f%%)\n",
            format(sum(panel$in_owner == 1L), big.mark = ","),
            mean(panel$in_owner) * 100))

cat("\nVariable summary (non-NA):\n")
for (v in c("n_employees", "total_wage_nom", "value_dis_total",
            "value_dis_real_2018_total", "logval", "logval_real", "firm_size")) {
  if (v %in% names(panel)) {
    vals <- panel[[v]][!is.na(panel[[v]])]
    if (length(vals)) {
      cat(sprintf("  %-35s mean=%.2f  sd=%.2f  min=%.2f  max=%.2f  n=%s\n",
                  v, mean(vals), sd(vals), min(vals), max(vals),
                  format(length(vals), big.mark = ",")))
    }
  }
}

if ("cnae_section" %in% names(panel)) {
  cat("\nCNAE section distribution (top 10):\n")
  sec_tab <- panel[!is.na(cnae_section), .N, by = cnae_section][order(-N)]
  for (i in seq_len(min(10, nrow(sec_tab)))) {
    cat(sprintf("  %s: %s (%.1f%%)\n",
                sec_tab$cnae_section[i],
                format(sec_tab$N[i], big.mark = ","),
                sec_tab$N[i] / sum(sec_tab$N) * 100))
  }
  cat(sprintf("  NA: %s\n", format(sum(is.na(panel$cnae_section)), big.mark = ",")))
}

if (owner_cnae_conflicts_n > 0L) {
  cat(sprintf("\nOwner CNAE conflicts: %s (ties: %s)\n",
              format(owner_cnae_conflicts_n, big.mark = ","),
              format(owner_cnae_ties_n, big.mark = ",")))
  cat("  Assumption used: modal section; alphabetical first if tied.\n")
  cat("  Diagnostic sample:", owner_cnae_conflicts_path, "\n")
}

if (rais_cnae_conflicts_n > 0L) {
  cat(sprintf("\nWithin-RAIS CNAE conflicts: %s (ties: %s)\n",
              format(rais_cnae_conflicts_n, big.mark = ","),
              format(rais_cnae_ties_n, big.mark = ",")))
  cat("  Assumption used: modal section; alphabetical first if tied.\n")
  cat("  Diagnostic sample:", rais_cnae_conflicts_path, "\n")
}

cat("\n==============================================================================\n")
cat("Reconstruction complete.\n")
cat("==============================================================================\n")
