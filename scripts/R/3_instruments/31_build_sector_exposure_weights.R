#!/usr/bin/env Rscript

# ==============================================================================
# Build Sector-Level Exposure Weights for Shift-Share Instrument
# ==============================================================================
# Constructs exposure weights w_{mjp,t} at (municipality, sector, party,
# year) level using owner-based denominators and employment-weighted
# aggregation of firm-level owner shares:
#
#   Method "owners":  w_{mjp,t} = L_{mjp,t} / L_{mj,t}
#     L_{mjp,t} = count of affiliated owners with party p in sector j
#                 and municipality r at time t. Raw owner affiliation data are
#                 firm-year-party, so municipality and sector are assigned from
#                 the reconstructed panel in script 22.
#     L_{mj,t}  = total owners across firms in sector j, municipality r,
#                 derived as aff_count / share_aff for firms with share data.
#                 Only firms with computable owner counts contribute to L_mj.
#
#   Method "employment":  w^{emp}_{mjp,t} = Sum_f n_{f,m,t} * (L_{fp,t} / L_{f,t}) / E_{mj,t}
#     n_{f,m,t} = employment of firm f in municipality m at time t
#     E_{mj,t}  = total employment across firms in sector j, municipality m,
#                 restricted to firms with computable affiliation shares
#
# Usage:
#   Rscript 31_build_sector_exposure_weights.R [owner|worker|all]
#   [--sector-var=cnae_section|sector_group]
#
#   Default: owner --sector-var=sector_group
#
# Examples:
#   Rscript 31_build_sector_exposure_weights.R owner       # owner (default)
#   Rscript 31_build_sector_exposure_weights.R all         # both groups
#
# Dependencies: reconstructed panel (rais_bndes_reconstructed.fst, script 22),
#               raw affiliation data (raw/david_ra/)
# ==============================================================================

cat("==============================================================================\n")
cat("Building Sector-Level Exposure Weights\n")
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
# --- Configuration -----------------------------------------------------------

configs <- list(
  list(
    stub = "owner",
    aff_path = make_base_path("raw/david_ra/owner_aff_firm_year_party_2002_2019.qs2"),
    aff_col_candidates  = "aff_owners",
    share_col_candidates = "share_aff_owners",
    output_path  = make_output_path("sector_exposure_weights_owner.qs2"),
    summary_path = make_output_path("sector_exposure_weights_owner_summary.csv")
  ),
  list(
    stub = "worker",
    aff_path = make_base_path("raw/david_ra/worker_aff_party_standard_2002_2019.qs2"),
    aff_col_candidates  = "aff_workers",
    share_col_candidates = "share_aff_workers",
    output_path  = make_output_path("sector_exposure_weights_worker.qs2"),
    summary_path = make_output_path("sector_exposure_weights_worker_summary.csv")
  )
)

# --- Parse CLI arguments -----------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

# Group selection (owner / worker / all)
selection <- c("owner")
group_args <- args[!grepl("^--", args)]
if (length(group_args)) {
  selection <- unique(unlist(strsplit(tolower(paste(group_args, collapse = " ")), "[,\\s]+")))
  selection <- selection[nzchar(selection)]
  if (any(selection %in% c("all", "both"))) selection <- c("owner", "worker")
  selection <- intersect(selection, c("owner", "worker"))
  if (!length(selection)) stop("No valid group specified; expected owner/worker/all.")
}

# Sector variable (--sector-var=cnae_section | --sector-var=sector_group)
svar_flag <- grep("^--sector-var=", args, value = TRUE)
SECTOR_VAR <- "sector_group"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[1])))
  if (!SECTOR_VAR %in% c("cnae_section", "sector_group")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'. Use 'cnae_section' or 'sector_group'.")
  }
}
USE_GROUPS <- (SECTOR_VAR == "sector_group")

configs <- Filter(function(cfg) cfg$stub %in% selection, configs)
cat("Running for group(s):", paste(selection, collapse = ", "), "\n")
cat("Primary denominator:  owners (w_mjp = L_mjp / L_mj)\n")
cat("Sector variable:      --sector-var=", SECTOR_VAR, "\n")
if (USE_GROUPS) {
  cat("  Using sector_group aggregation (from script 30 crosswalk)\n")
}
cat("\n")

# Load sector group crosswalk if using grouped sectors
group_crosswalk <- NULL
if (USE_GROUPS) {
  cw_path <- make_output_path("sector_group_mapping.qs2")
  if (!file.exists(cw_path)) {
    stop("Sector group mapping not found: ", cw_path, "\n  Run script 30 first.")
  }
  group_crosswalk <- qs_read(cw_path)
  setDT(group_crosswalk)
  cat("  Loaded sector group crosswalk:", nrow(group_crosswalk), "rows\n\n")

  # Update output paths for grouped variants
  for (i in seq_along(configs)) {
    configs[[i]]$output_path <- sub("\\.qs2$", "_grouped.qs2", configs[[i]]$output_path)
    configs[[i]]$summary_path <- sub("\\.csv$", "_grouped.csv", configs[[i]]$summary_path)
  }
}

# --- Step 1: Build municipality-sector mapping from reconstructed panel ------
# The reconstructed file contains firm_id (integer), muni_id, year, cnae_section
# produced from RAIS classe via the division-to-section mapping in script 22.

cat("Step 1: Building reconstructed firm-year municipality-sector mapping...\n")

recon_path_fst <- make_output_path("rais_bndes_reconstructed.fst")
recon_path_qs2 <- make_output_path("rais_bndes_reconstructed.qs2")

# When using groups, also need classe to derive cnae_division
load_cols <- c("firm_id", "muni_id", "year", "cnae_section", "n_employees")
if (USE_GROUPS) load_cols <- c(load_cols, "classe")

if (file.exists(recon_path_fst) && requireNamespace("fst", quietly = TRUE)) {
  cat("  Loading from fst (column-selective):", basename(recon_path_fst), "\n")
  firm_sector <- fst::read_fst(recon_path_fst,
                                columns = load_cols,
                                as.data.table = TRUE)
} else if (file.exists(recon_path_qs2)) {
  cat("  Loading from qs2:", basename(recon_path_qs2), "\n")
  recon <- qs_read(recon_path_qs2)
  setDT(recon)
  firm_sector <- recon[, ..load_cols]
  rm(recon); invisible(gc())
} else {
  stop("Reconstructed panel not found.\n",
       "  Checked: ", recon_path_fst, "\n",
       "  Checked: ", recon_path_qs2, "\n",
       "  Run script 22 first.")
}

# If using groups, derive cnae_division and merge sector_group
if (USE_GROUPS) {
  firm_sector[, cnae_division := as.integer(floor(as.numeric(classe) / 1000))]
  firm_sector[group_crosswalk, sector_group := i.sector_group, on = "cnae_division"]
  # For rows that didn't match via division (missing classe), try via section
  section_cw <- unique(group_crosswalk[, .(cnae_section, sector_group)])
  # Deduplicate: for C, multiple groups exist per section — these need division
  section_cw_nonc <- section_cw[cnae_section != "C"]
  firm_sector[is.na(sector_group) & !is.na(cnae_section),
              sector_group := section_cw_nonc$sector_group[
                match(cnae_section, section_cw_nonc$cnae_section)]]
  n_grouped <- sum(!is.na(firm_sector$sector_group))
  cat(sprintf("  Sector group assignment: %d / %d (%.1f%%)\n",
              n_grouped, nrow(firm_sector), 100 * n_grouped / nrow(firm_sector)))
  # Drop XX (residual)
  n_xx <- sum(firm_sector$sector_group == "XX", na.rm = TRUE)
  if (n_xx > 0) {
    cat(sprintf("  Dropping %d rows in residual group XX (sections O, T, U)\n", n_xx))
    firm_sector <- firm_sector[!is.na(sector_group) & sector_group != "XX"]
  }
  firm_sector[, c("classe", "cnae_division") := NULL]
}

# Standardize key types
firm_sector[, firm_id := as.integer(firm_id)]
firm_sector[, muni_id := as.integer(muni_id)]
firm_sector[, year := as.integer(year)]

# Drop invalid muni_id (0 is not a valid IBGE municipality code)
n_invalid_muni <- sum(firm_sector$muni_id == 0L | is.na(firm_sector$muni_id))
if (n_invalid_muni > 0L) {
  cat(sprintf("  Dropping %d rows with invalid muni_id (0 or NA)\n", n_invalid_muni))
  firm_sector <- firm_sector[!is.na(muni_id) & muni_id > 0L]
}

# Drop rows with missing sector in the requested sector variable
SCOL <- SECTOR_VAR  # "cnae_section" or "sector_group"
firm_sector <- firm_sector[!is.na(get(SCOL)) & nzchar(get(SCOL))]

# Deduplicate to one sector per (firm_id, muni_id, year)
firm_sector <- unique(firm_sector, by = c("firm_id", "muni_id", "year"))

cat("  Sector mapping:", nrow(firm_sector), "firm-muni-year entries\n")
cat(sprintf("  Unique %s: %d\n", SCOL, uniqueN(firm_sector[[SCOL]])))
cat("  Year range:", paste(range(firm_sector$year), collapse = "-"), "\n\n")

emp_vals_total <- firm_sector$n_employees[is.finite(firm_sector$n_employees) &
                                            !is.na(firm_sector$n_employees) &
                                            firm_sector$n_employees > 0]
if (length(emp_vals_total)) {
  cat(sprintf("  Reconstructed employment coverage: %d / %d rows (%.1f%%) with positive n_employees\n",
              length(emp_vals_total), nrow(firm_sector), 100 * length(emp_vals_total) / nrow(firm_sector)))
  cat(sprintf("  n_employees: mean=%.1f, median=%.0f, max=%.0f\n\n",
              mean(emp_vals_total), median(emp_vals_total), max(emp_vals_total)))
} else {
  cat("  WARNING: no positive n_employees values found in reconstructed panel\n\n")
}

# --- Step 2: Process each affiliation group ----------------------------------

process_weights <- function(cfg) {
  stub         <- cfg$stub
  output_path  <- cfg$output_path
  summary_path <- cfg$summary_path

  cat(sprintf("--- %s ---\n", toupper(stub)))

  # --- Load affiliation data --------------------------------------------------
  if (!file.exists(cfg$aff_path)) {
    warning("Affiliation file not found for ", stub, " -- skipping.\n",
            "  Looked for: ", cfg$aff_path)
    return(invisible(NULL))
  }
  cat("  Loading:", basename(cfg$aff_path), "\n")
  aff <- qs_read(cfg$aff_path)
  cat("  Loaded:", nrow(aff), "rows,", ncol(aff), "cols\n")
  cat("  Columns:", paste(names(aff), collapse = ", "), "\n")

  check_weight_invariants <- function(dt, weight_col, label, enforce_sum_constraint = TRUE) {
    vals <- dt[[weight_col]]
    vals <- vals[!is.na(vals)]
    if (!length(vals)) {
      cat(sprintf("  Assertions (%s): no non-missing values\n", label))
      return(invisible(NULL))
    }

    max_w <- max(vals)
    if (max_w > 1.001) {
      n_violations <- sum(dt[[weight_col]] > 1.001, na.rm = TRUE)
      warning(sprintf("INVARIANT VIOLATION: max(%s) = %.4f (> 1) in %d cells",
                      weight_col, max_w, n_violations))
    }

    max_sum <- NA_real_
    if (isTRUE(enforce_sum_constraint)) {
      cell_sums <- dt[!is.na(get(weight_col)),
                      .(sum_w = sum(get(weight_col))),
                      by = c("muni_id", SCOL, "year")]
      max_sum <- max(cell_sums$sum_w)
      if (max_sum > 1.001) {
        n_violations <- sum(cell_sums$sum_w > 1.001)
        warning(sprintf("INVARIANT VIOLATION: max(sum_p %s) = %.4f (> 1) in %d cells",
                        weight_col, max_sum, n_violations))
      }
      rm(cell_sums)
    }

    if (isTRUE(enforce_sum_constraint)) {
      cat(sprintf("  Assertions (%s): max(%s) = %.6f, max(sum_p) = %.6f\n",
                  label, weight_col, max_w, max_sum))
    } else {
      cat(sprintf("  Assertions (%s): max(%s) = %.6f (sum_p unconstrained)\n",
                  label, weight_col, max_w))
    }
    invisible(NULL)
  }

  # --- Standardise columns --------------------------------------------------

  # year
  aff[, year := as.integer(year)]

  # firm_id — character in source, convert to integer to match RAIS/BNDES
  aff[, firm_id := as.integer(firm_id)]

  aff_has_muni <- "muni_id" %in% names(aff)
  if (aff_has_muni) {
    aff[, muni_id := as.integer(muni_id)]
    cat("  Municipality found in affiliation data; merging on (firm_id, muni_id, year)\n")
  } else {
    cat("  Municipality absent in affiliation data; recovering muni_id from reconstructed panel via (firm_id, year)\n")
  }
  merge_keys <- if (aff_has_muni) c("firm_id", "muni_id", "year") else c("firm_id", "year")

  # party
  aff[, party := trimws(as.character(party))]

  # affiliation count
  aff_col <- cfg$aff_col_candidates
  aff[, aff_count := as.integer(get(aff_col))]

  # share column
  share_col <- cfg$share_col_candidates
  has_share <- !is.na(share_col)
  if (has_share) {
    aff[, share_aff := as.numeric(get(share_col))]
    cat("  Share column:", share_col, "\n")
    # Sanity checks
    n_below_zero <- sum(aff$share_aff < 0, na.rm = TRUE)
    n_above_one  <- sum(aff$share_aff > 1, na.rm = TRUE)
    if (n_below_zero > 0) {
      cat(sprintf("  WARNING: %d rows with share < 0 -- setting to NA\n", n_below_zero))
      aff[share_aff < 0, share_aff := NA_real_]
    }
    if (n_above_one > 0) {
      cat(sprintf("  WARNING: %d rows with share > 1 -- clamping to 1\n", n_above_one))
      aff[share_aff > 1, share_aff := 1]
    }
  } else {
    cat("  ERROR: No share column found. Owners denominator unavailable.\n")
    cat("  Looked for:", paste(cfg$share_col_candidates, collapse = ", "), "\n")
    stop("Aborting: owner-based denominator requires share data.")
  }

  # --- Filter to 2002-2017 (years with complete data in RAIS) --------------
  aff <- aff[year >= 2002 & year <= 2017]
  cat("  After year filter:", nrow(aff), "rows\n")

  # --- Compute L_mj (total owners per muni-sector-year) --------------------
  # For each row (firm, party, year), total_owners = aff_count / share_aff.
  # share_aff is the fraction of the firm's owners affiliated with THIS party,
  # so dividing gives the total owner count for the firm (consistent across
  # parties within the same firm).
  owner_counts <- NULL
  emp_counts <- NULL
  if (has_share) {
    cat("  Computing total owners per firm from share data...\n")

    aff[, total_owners_est := fifelse(
      share_aff > 0 & !is.na(share_aff),
      aff_count / share_aff,
      NA_real_
    )]

    n_with_est <- sum(!is.na(aff$total_owners_est))
    n_total <- nrow(aff)
    cat(sprintf("    Rows with computable total_owners: %d / %d (%.1f%%)\n",
                n_with_est, n_total, 100 * n_with_est / n_total))

    # Deduplicate to one total_owners per firm-year (or firm-muni-year if
    # municipality is already present in the affiliation source).
    # Round each estimate to nearest integer first: share_aff is stored as a
    # rounded float, so aff_count/share_aff recovers total_owners with ~1e-8
    # floating-point noise. Rounding eliminates 100% of cross-party mismatches
    # (verified in 3x_diagnose_total_owners.R). Use median across parties
    # (robust to any single outlier share), then floor at sum(aff_count).
    owner_id_keys <- if (aff_has_muni) c("firm_id", "muni_id", "year") else c("firm_id", "year")

    # --- Fast path: separate GForce-optimized sum() from R-level median() ---
    # Step 1: sum(aff_count) per firm-year — GForce-optimized in C
    firm_owners <- aff[, .(total_owners_from_sum = sum(aff_count, na.rm = TRUE)),
                       by = owner_id_keys]

    # Step 2: median(total_owners_est) only on rows with valid estimates,
    #         avoiding suppressWarnings() and reducing the number of groups
    est_valid <- aff[!is.na(total_owners_est),
                     .(total_owners_from_share = as.integer(round(
                       median(total_owners_est)
                     ))),
                     by = owner_id_keys]

    # Step 3: merge the two pieces
    firm_owners[est_valid, total_owners_from_share := i.total_owners_from_share,
                on = owner_id_keys]
    rm(est_valid)

    # total_owners = max of the two methods (floor at sum of aff_count)
    firm_owners[, total_owners := fifelse(
      !is.na(total_owners_from_share),
      pmax(total_owners_from_share, total_owners_from_sum),
      total_owners_from_sum
    )]
    firm_owners[, c("total_owners_from_share", "total_owners_from_sum") := NULL]
    firm_owners <- firm_owners[total_owners > 0]

    cat(sprintf("    Unique firms with owner estimates: %d\n", nrow(firm_owners)))

    # Merge municipality-sector cells from the reconstructed panel. When the raw
    # affiliation source is firm-year-party, this expands one firm-year owner
    # record across the municipalities where the firm operates in that year.
    merge_cols <- unique(c(merge_keys, "muni_id", "year", SCOL, "n_employees"))
    firm_owners <- merge(firm_owners,
      firm_sector[, ..merge_cols],
      by = merge_keys,
      all.x = TRUE,
      allow.cartesian = !aff_has_muni)
    firm_owners <- firm_owners[!is.na(get(SCOL))]

    # Aggregate to L_mj = sum of total owners per (muni, sector, year)
    owner_counts <- firm_owners[, .(
      L_mj = sum(total_owners, na.rm = TRUE),
      n_firms_with_owners = .N
    ), by = c("muni_id", SCOL, "year")]
    setkeyv(owner_counts, c("muni_id", SCOL, "year"))

    cat(sprintf("    L_mj computed for %d (muni, sector, year) cells\n",
                nrow(owner_counts)))
    cat(sprintf("    L_mj: mean=%.1f, median=%.0f, max=%.0f\n",
                mean(owner_counts$L_mj), median(owner_counts$L_mj),
                max(owner_counts$L_mj)))

    # Employment denominator for the weighted aggregation of firm-level owner shares.
    firm_employment <- unique(
      firm_owners[is.finite(n_employees) & !is.na(n_employees) & n_employees > 0,
                  c("firm_id", "muni_id", SCOL, "year", "n_employees"),
                  with = FALSE]
    )
    emp_counts <- firm_employment[, .(
      E_mj = sum(n_employees, na.rm = TRUE),
      n_firms_with_emp = .N
    ), by = c("muni_id", SCOL, "year")]
    setkeyv(emp_counts, c("muni_id", SCOL, "year"))

    cat(sprintf("    E_mj computed for %d (muni, sector, year) cells\n",
                nrow(emp_counts)))
    if (nrow(emp_counts)) {
      cat(sprintf("    E_mj: mean=%.1f, median=%.0f, max=%.0f\n",
                  mean(emp_counts$E_mj), median(emp_counts$E_mj), max(emp_counts$E_mj)))
    }

    if (nrow(firm_employment)) {
      total_emp_matched <- sum(firm_employment$n_employees, na.rm = TRUE)
      total_emp_recon <- sum(firm_sector$n_employees[
        is.finite(firm_sector$n_employees) &
          !is.na(firm_sector$n_employees) &
          firm_sector$n_employees > 0
      ], na.rm = TRUE)
      emp_share <- if (total_emp_recon > 0) total_emp_matched / total_emp_recon else NA_real_
      cat(sprintf("    Employment coverage in matched affiliated firms: %.1f%% of reconstructed employment mass\n",
                  100 * emp_share))
    }

    owner_totals <- unique(firm_owners[, c(merge_keys, "total_owners"), with = FALSE])

    rm(firm_owners); invisible(gc())
  }

  # --- Merge sector and aggregate L_mjp ------------------------------------
  cat("  Merging sector codes from RAIS...\n")
  n_before <- nrow(aff)
  aff[, aff_row_id := .I]
  merge_cols <- unique(c(merge_keys, "muni_id", SCOL, "n_employees"))
  aff <- merge(
    aff,
    firm_sector[, ..merge_cols],
    by = merge_keys,
    all.x = TRUE,
    allow.cartesian = !aff_has_muni
  )
  n_matched <- aff[!is.na(get(SCOL)), uniqueN(aff_row_id)]
  cat(sprintf("  Sector match: %d / %d source affiliation rows (%.1f%%)\n",
              n_matched, n_before, 100 * n_matched / n_before))
  if (!aff_has_muni) {
    cat(sprintf("  Expanded to %d firm-muni-sector rows after municipality assignment\n",
                nrow(aff)))
  }

  aff <- aff[!is.na(get(SCOL))]
  invisible(gc())

  if (has_share) {
    aff <- merge(aff, owner_totals, by = merge_keys, all.x = TRUE)
    aff[, owner_party_share := fifelse(
      !is.na(total_owners) & total_owners > 0,
      aff_count / total_owners,
      NA_real_
    )]
    aff[, emp_party_contrib := fifelse(
      !is.na(owner_party_share) &
        !is.na(n_employees) &
        is.finite(n_employees) &
        n_employees > 0,
      n_employees * owner_party_share,
      NA_real_
    )]
    rm(owner_totals)
  } else {
    aff[, `:=`(total_owners = NA_integer_, owner_party_share = NA_real_, emp_party_contrib = NA_real_)]
  }

  # Aggregate to (muni, sector, party, year)
  # Exclude "No party" from the numerator: these owners have no alignment shock
  # (not in alignment_shocks.qs2) so they contribute zero to Z_mjt. They already
  # contribute to the denominator L_mj via total_owners above.
  cat(sprintf("  Aggregating to (muni, %s, party, year)...\n", SCOL))
  n_no_party <- sum(aff$party == "No party", na.rm = TRUE)
  cat(sprintf("  Excluding %d 'No party' rows from L_mjp (%.1f%% of matched rows)\n",
              n_no_party, 100 * n_no_party / nrow(aff)))
  wt <- aff[party != "No party",
            .(L_mjp = sum(aff_count, na.rm = TRUE),
              n_firms_mjp = uniqueN(firm_id)),
            by = c("muni_id", SCOL, "party", "year")]

  # --- Merge denominators and compute weights --------------------------------

  # L_mj (owners method) — available if share data was present
  if (!is.null(owner_counts)) {
    wt <- merge(wt, owner_counts,
                by = c("muni_id", SCOL, "year"), all.x = TRUE)
    wt[is.na(L_mj), L_mj := 0]
    wt[is.na(n_firms_with_owners), n_firms_with_owners := 0L]
    wt[, w_mjp_owners := fifelse(L_mj > 0, L_mjp / L_mj, 0)]
  } else {
    wt[, L_mj := NA_real_]
    wt[, n_firms_with_owners := NA_integer_]
    wt[, w_mjp_owners := NA_real_]
  }

  if (!is.null(emp_counts)) {
    emp_numerators <- aff[party != "No party" & !is.na(emp_party_contrib),
                          .(L_mjp_emp = sum(emp_party_contrib, na.rm = TRUE)),
                          by = c("muni_id", SCOL, "party", "year")]
    wt <- merge(wt, emp_numerators,
                by = c("muni_id", SCOL, "party", "year"), all.x = TRUE)
    wt <- merge(wt, emp_counts,
                by = c("muni_id", SCOL, "year"), all.x = TRUE)
    wt[is.na(L_mjp_emp), L_mjp_emp := 0]
    wt[is.na(E_mj), E_mj := 0]
    wt[is.na(n_firms_with_emp), n_firms_with_emp := 0L]
    wt[, w_mjp_emp := fifelse(E_mj > 0, L_mjp_emp / E_mj, 0)]
    rm(emp_numerators)
  } else {
    wt[, `:=`(
      L_mjp_emp = NA_real_,
      E_mj = NA_real_,
      n_firms_with_emp = NA_integer_,
      w_mjp_emp = NA_real_
    )]
  }

  if (!is.null(owner_counts)) {
    firm_numerators <- aff[party != "No party" & !is.na(owner_party_share),
                           .(
                             L_mjp_firm = sum(owner_party_share, na.rm = TRUE),
                             L_mjp_binary = sum(as.integer(owner_party_share > 0), na.rm = TRUE)
                           ),
                           by = c("muni_id", SCOL, "party", "year")]
    wt <- merge(wt, firm_numerators,
                by = c("muni_id", SCOL, "party", "year"), all.x = TRUE)
    wt[is.na(L_mjp_firm), L_mjp_firm := 0]
    wt[is.na(L_mjp_binary), L_mjp_binary := 0]
    wt[, w_mjp_firm := fifelse(n_firms_with_owners > 0, L_mjp_firm / n_firms_with_owners, 0)]
    wt[, w_mjp_binary := fifelse(n_firms_with_owners > 0, L_mjp_binary / n_firms_with_owners, 0)]
    rm(firm_numerators)
  } else {
    wt[, `:=`(
      L_mjp_firm = NA_real_,
      L_mjp_binary = NA_real_,
      w_mjp_firm = NA_real_,
      w_mjp_binary = NA_real_
    )]
  }

  # Total affiliated across all parties (for reference, excluding "No party")
  wt[, L_mj_affiliated := sum(L_mjp), by = c("muni_id", SCOL, "year")]
  if ("L_mjp_emp" %in% names(wt)) {
    wt[, L_mj_emp := sum(L_mjp_emp, na.rm = TRUE), by = c("muni_id", SCOL, "year")]
  }

  # --- Permanent invariant assertions -----------------------------------------
  if (!is.null(owner_counts)) check_weight_invariants(wt, "w_mjp_owners", "owners")
  if (!is.null(emp_counts)) check_weight_invariants(wt, "w_mjp_emp", "employment")
  if ("w_mjp_firm" %in% names(wt) && !all(is.na(wt$w_mjp_firm))) {
    check_weight_invariants(wt, "w_mjp_firm", "equal-firm")
  }
  if ("w_mjp_binary" %in% names(wt) && !all(is.na(wt$w_mjp_binary))) {
    check_weight_invariants(wt, "w_mjp_binary", "binary", enforce_sum_constraint = FALSE)
  }

  # --- Set primary w_mjp -------------------------------------------------------
  wt[, w_mjp := w_mjp_owners]
  cat("  Primary weight: w_mjp = w_mjp_owners (L_mjp / L_mj)\n")

  setorderv(wt, c("year", "muni_id", SCOL, "party"))

  # --- Diagnostics -----------------------------------------------------------
  cat("\n  Weight panel:", nrow(wt), "rows\n")
  cat(sprintf("  Unique (muni, %s, year) cells: %d\n",
      SCOL, uniqueN(wt, by = c("muni_id", SCOL, "year"))))

  for (wcol in c("w_mjp_owners", "w_mjp")) {
    if (wcol %in% names(wt) && !all(is.na(wt[[wcol]]))) {
      vals <- wt[[wcol]][!is.na(wt[[wcol]])]
      cat(sprintf("  %s: mean=%.6f, sd=%.6f, min=%.6f, max=%.6f\n",
                  wcol, mean(vals), sd(vals), min(vals), max(vals)))
    }
  }
  if ("w_mjp_emp" %in% names(wt) && !all(is.na(wt$w_mjp_emp))) {
    vals <- wt$w_mjp_emp[!is.na(wt$w_mjp_emp)]
    cat(sprintf("  w_mjp_emp: mean=%.6f, sd=%.6f, min=%.6f, max=%.6f\n",
                mean(vals), sd(vals), min(vals), max(vals)))
  }
  if ("w_mjp_firm" %in% names(wt) && !all(is.na(wt$w_mjp_firm))) {
    vals <- wt$w_mjp_firm[!is.na(wt$w_mjp_firm)]
    cat(sprintf("  w_mjp_firm: mean=%.6f, sd=%.6f, min=%.6f, max=%.6f\n",
                mean(vals), sd(vals), min(vals), max(vals)))
  }
  if ("w_mjp_binary" %in% names(wt) && !all(is.na(wt$w_mjp_binary))) {
    vals <- wt$w_mjp_binary[!is.na(wt$w_mjp_binary)]
    cat(sprintf("  w_mjp_binary: mean=%.6f, sd=%.6f, min=%.6f, max=%.6f\n",
                mean(vals), sd(vals), min(vals), max(vals)))
  }
  if (!all(is.na(wt$L_mj))) {
    vals <- wt$L_mj[!is.na(wt$L_mj) & wt$L_mj > 0]
    if (length(vals)) {
      cat(sprintf("  L_mj:  mean=%.1f, median=%.0f, max=%d (non-zero only)\n",
                  mean(vals), median(vals), max(vals)))
    }
  }
  if ("E_mj" %in% names(wt) && !all(is.na(wt$E_mj))) {
    vals <- wt$E_mj[!is.na(wt$E_mj) & wt$E_mj > 0]
    if (length(vals)) {
      cat(sprintf("  E_mj:  mean=%.1f, median=%.0f, max=%.0f (non-zero only)\n",
                  mean(vals), median(vals), max(vals)))
    }
  }

  cell_coverage <- wt[, .(
    has_owner_denom = any(!is.na(L_mj) & L_mj > 0),
    has_emp_denom = any(!is.na(E_mj) & E_mj > 0)
  ), by = c("muni_id", SCOL, "year")]
  cat(sprintf("  Coverage: owner denominator in %d / %d cells (%.1f%%)\n",
              sum(cell_coverage$has_owner_denom), nrow(cell_coverage),
              100 * mean(cell_coverage$has_owner_denom)))
  cat(sprintf("  Coverage: employment denominator in %d / %d cells (%.1f%%)\n",
              sum(cell_coverage$has_emp_denom), nrow(cell_coverage),
              100 * mean(cell_coverage$has_emp_denom)))

  # --- Save -------------------------------------------------------------------
  summ <- wt[, .(
    n_obs          = .N,
    n_munis        = uniqueN(muni_id),
    n_sectors      = uniqueN(get(SCOL)),
    n_parties      = uniqueN(party),
    n_years        = uniqueN(year),
    mean_L_mjp     = mean(L_mjp),
    mean_L_mj      = mean(L_mj, na.rm = TRUE),
    mean_E_mj      = mean(E_mj, na.rm = TRUE),
    mean_L_mj_aff  = mean(L_mj_affiliated, na.rm = TRUE),
    mean_w_owners  = mean(w_mjp_owners, na.rm = TRUE),
    sd_w_owners    = sd(w_mjp_owners, na.rm = TRUE),
    mean_w_emp     = mean(w_mjp_emp, na.rm = TRUE),
    sd_w_emp       = sd(w_mjp_emp, na.rm = TRUE),
    mean_w_firm    = mean(w_mjp_firm, na.rm = TRUE),
    sd_w_firm      = sd(w_mjp_firm, na.rm = TRUE),
    mean_w_binary  = mean(w_mjp_binary, na.rm = TRUE),
    sd_w_binary    = sd(w_mjp_binary, na.rm = TRUE),
    sector_var     = SECTOR_VAR
  )]

  drop_cols <- intersect(c("n_firms_mjp", "n_firms_with_owners", "n_firms_with_emp"), names(wt))
  if (length(drop_cols)) wt[, (drop_cols) := NULL]

  qs_save(wt, output_path)
  fwrite(summ, summary_path)
  cat(sprintf("  Saved %s (%.2f MB)\n",
              output_path, file.size(output_path) / 1024^2))
  cat(sprintf("  Saved %s\n\n", summary_path))

  rm(aff, wt); invisible(gc())
}

invisible(lapply(configs, process_weights))

cat("Sector exposure weights complete.\n")
