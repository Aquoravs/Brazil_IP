cat("==============================================================================\n")
cat("Audit: Sector First-Stage Inputs (31-35 + parse checks)\n")
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

args <- commandArgs(trailingOnly = TRUE)

parse_flag <- function(prefix, default = NA_character_) {
  x <- grep(paste0("^", prefix), args, value = TRUE)
  if (!length(x)) return(default)
  trimws(sub(paste0("^", prefix), "", x[1]))
}

parse_bool <- function(x, default = FALSE) {
  if (is.na(x) || !nzchar(x)) return(default)
  x <- tolower(trimws(x))
  if (x %in% c("1", "true", "t", "yes", "y")) return(TRUE)
  if (x %in% c("0", "false", "f", "no", "n")) return(FALSE)
  stop("Invalid boolean value: ", x)
}

SECTOR_VAR <- parse_flag("--sector-var=", "sector_group")
if (!SECTOR_VAR %in% c("cnae_section", "sector_group")) {
  stop("Invalid --sector-var value: ", SECTOR_VAR)
}
STRICT <- parse_bool(parse_flag("--strict=", "true"), default = TRUE)
CHECK_DRYRUN <- parse_bool(parse_flag("--check-dryrun=", "false"), default = FALSE)

cat("Sector variable:", SECTOR_VAR, "\n")
cat("Strict mode:", STRICT, "\n")
cat("Dry-run checks:", CHECK_DRYRUN, "\n\n")

suffix <- if (SECTOR_VAR == "sector_group") "_grouped" else ""
sc_col <- SECTOR_VAR

audit_dir <- file.path(
  OUTPUT_DIR,
  "diagnostics",
  paste0("3_instruments_audit_", SECTOR_VAR)
)
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

registry <- data.table(
  dataset = c(
    "sector_exposure_weights_owner",
    "alignment_shocks",
    "baseline_sector_weights",
    "shift_share_instruments",
    "shift_share_instruments_sector",
    "exposure_control_sector",
    "bndes_credit_shares"
  ),
  path = c(
    make_output_path(paste0("sector_exposure_weights_owner", suffix, ".qs2")),
    make_output_path("alignment_shocks.qs2"),
    make_output_path(paste0("baseline_sector_weights", suffix, ".qs2")),
    make_output_path(paste0("shift_share_instruments", suffix, ".qs2")),
    make_output_path(paste0("shift_share_instruments_sector", suffix, ".qs2")),
    make_output_path(paste0("exposure_control_sector", suffix, ".qs2")),
    make_output_path(paste0("bndes_credit_shares", suffix, ".qs2"))
  )
)
registry[, exists := file.exists(path)]
registry[, size_mb := fifelse(exists, file.size(path) / 1024^2, NA_real_)]
fwrite(registry, file.path(audit_dir, "00_data_inventory.csv"))

checks <- data.table(
  group = character(),
  dataset = character(),
  check_id = character(),
  severity = character(),
  passed = logical(),
  details = character()
)

add_check <- function(group, dataset, check_id, passed, details, severity = "critical") {
  checks <<- rbind(
    checks,
    data.table(
      group = group,
      dataset = dataset,
      check_id = check_id,
      severity = severity,
      passed = as.logical(passed),
      details = details
    ),
    fill = TRUE
  )
}

load_dt <- function(path) {
  obj <- qs_read(path)
  setDT(obj)
  obj
}

required_missing <- registry[exists == FALSE, dataset]
add_check(
  "inventory",
  "all",
  "required_files_exist",
  length(required_missing) == 0,
  if (length(required_missing)) {
    paste("Missing:", paste(required_missing, collapse = ", "))
  } else {
    "All required files found."
  }
)

d <- list()
for (i in seq_len(nrow(registry))) {
  if (registry$exists[i]) {
    d[[registry$dataset[i]]] <- load_dt(registry$path[i])
  }
}

if (!is.null(d$sector_exposure_weights_owner)) {
  wt <- d$sector_exposure_weights_owner
  required_cols <- c("muni_id", sc_col, "year", "party", "L_rjp", "L_rj", "N_rj", "w_rjp")
  missing_cols <- setdiff(required_cols, names(wt))
  add_check("schema", "sector_exposure_weights_owner", "required_columns",
            length(missing_cols) == 0,
            if (length(missing_cols)) paste("Missing:", paste(missing_cols, collapse = ", ")) else "OK")
  add_check("schema", "sector_exposure_weights_owner", "no_firm_count_columns",
            !any(c("F_rj", "w_rjp_firms") %in% names(wt)),
            "Firm-count robustness columns should be absent.")
  if (all(c("muni_id", sc_col, "year", "party") %in% names(wt))) {
    n_dup <- nrow(wt) - uniqueN(wt, by = c("muni_id", sc_col, "year", "party"))
    add_check("keys", "sector_exposure_weights_owner", "unique_key", n_dup == 0,
              paste("Duplicate rows:", n_dup))
  }
  if ("w_rjp" %in% names(wt)) {
    rng <- range(wt$w_rjp, na.rm = TRUE)
    add_check("identity", "sector_exposure_weights_owner", "weight_bounds",
              is.finite(rng[1]) && is.finite(rng[2]) && rng[1] >= -1e-10 && rng[2] <= 1 + 1e-10,
              sprintf("Range [%.6f, %.6f]", rng[1], rng[2]))
    cell_sums <- wt[, .(sum_w = sum(w_rjp, na.rm = TRUE)), by = c("muni_id", sc_col, "year")]
    max_sum <- cell_sums[, max(sum_w, na.rm = TRUE)]
    add_check("identity", "sector_exposure_weights_owner", "weight_sum_per_cell",
              is.finite(max_sum) && max_sum <= 1.001,
              sprintf("Max sum_p(w_rjp)=%.6f", max_sum))
  }
}

if (!is.null(d$baseline_sector_weights)) {
  bw <- d$baseline_sector_weights
  required_cols <- c(
    "muni_id", sc_col, "party", "treatment_year", "tier", "baseline_type",
    "baseline_year", "L_rjp_0", "L_rj_0", "N_rj_0", "w_rjp_0", "N_r_0", "L_r_0"
  )
  missing_cols <- setdiff(required_cols, names(bw))
  add_check("schema", "baseline_sector_weights", "required_columns",
            length(missing_cols) == 0,
            if (length(missing_cols)) paste("Missing:", paste(missing_cols, collapse = ", ")) else "OK")
  add_check("schema", "baseline_sector_weights", "no_firm_count_columns",
            !any(c("F_rj_0", "w_rjp_firms_0", "F_r_0") %in% names(bw)),
            "Firm-count robustness columns should be absent.")
}

if (!is.null(d$shift_share_instruments_sector)) {
  zs <- d$shift_share_instruments_sector
  z_cols <- grep("^Z_", names(zs), value = TRUE)
  add_check("schema", "shift_share_instruments_sector", "has_sector_instruments",
            length(z_cols) > 0,
            paste("Z columns:", length(z_cols)))
  add_check("schema", "shift_share_instruments_sector", "no_zf1_columns",
            !any(grepl("^Zf1_", names(zs))),
            "Zf1 columns should be absent.")
}

if (!is.null(d$exposure_control_sector)) {
  ctrl <- d$exposure_control_sector
  ctrl_cols <- grep("^exposure_control_", names(ctrl), value = TRUE)
  add_check("schema", "exposure_control_sector", "has_exposure_controls",
            length(ctrl_cols) > 0,
            paste("Control columns:", paste(ctrl_cols, collapse = ", ")))
  if (length(ctrl_cols) && all(c("muni_id", sc_col, "year") %in% names(ctrl))) {
    varying <- ctrl[, .(
      varying = any(vapply(.SD, function(x) uniqueN(x[is.finite(x)]) > 1, logical(1)))
    ), by = .(muni_id, year), .SDcols = ctrl_cols]
    n_varying <- varying[, sum(varying)]
    add_check("identity", "exposure_control_sector", "varies_within_muni_year",
              n_varying > 0,
              paste("Municipality-years with cross-sector variation:", n_varying),
              severity = "warning")
  }
}

if (!is.null(d$bndes_credit_shares)) {
  cs <- d$bndes_credit_shares
  if (all(c("muni_id", sc_col, "year", "s_mjt", "delta_s_mjt", "bndes_mt") %in% names(cs))) {
    pos <- cs[bndes_mt > 0]
    if (nrow(pos)) {
      share_sum <- pos[, .(sum_s = sum(s_mjt, na.rm = TRUE)), by = .(muni_id, year)]
      max_dev_s <- share_sum[, max(abs(sum_s - 1), na.rm = TRUE)]
      add_check("identity", "bndes_credit_shares", "share_sum_to_one",
                is.finite(max_dev_s) && max_dev_s < 1e-8,
                sprintf("max|sum_j s_mjt - 1| = %.6e", max_dev_s))
    }
    totals <- unique(cs[, .(muni_id, year, bndes_mt)])
    setorder(totals, muni_id, year)
    totals[, bndes_mt_lag := shift(bndes_mt, n = 1L, type = "lag"), by = muni_id]

    deltas <- cs[!is.na(delta_s_mjt), .(sum_delta = sum(delta_s_mjt, na.rm = TRUE)), by = .(muni_id, year)]
    deltas <- merge(deltas, totals, by = c("muni_id", "year"), all.x = TRUE)
    if (nrow(deltas)) {
      deltas[, expected_sum := fifelse(
        !is.na(bndes_mt_lag) & bndes_mt_lag == 0 & bndes_mt > 0, 1,
        fifelse(!is.na(bndes_mt_lag) & bndes_mt_lag > 0 & bndes_mt == 0, -1, 0)
      )]
      max_dev_d <- deltas[, max(abs(sum_delta - expected_sum), na.rm = TRUE)]
      add_check("identity", "bndes_credit_shares", "delta_sum_to_zero",
                is.finite(max_dev_d) && max_dev_d < 1e-8,
                sprintf("max|sum_j delta_s_mjt - expected| = %.6e", max_dev_d))
    }
    first_year_check <- cs[, .(
      n_non_na = sum(!is.na(delta_s_mjt[year == min(year, na.rm = TRUE)]))
    ), by = .(muni_id, sector = get(sc_col))]
    n_bad_first_year <- first_year_check[, sum(n_non_na)]
    add_check("identity", "bndes_credit_shares", "first_year_delta_is_na",
              isTRUE(n_bad_first_year == 0L),
              paste("Non-NA first-year delta_s_mjt rows:", n_bad_first_year))
  }
}

if (CHECK_DRYRUN) {
  cmd <- c(
    politicsregs_path("run_politicsregs.R"),
    "31:35",
    "--dryrun",
    "--",
    paste0("--sector-var=", SECTOR_VAR)
  )
  status <- system2("Rscript", args = cmd)
  add_check("execution", "run_politicsregs", "31_35_dryrun", status == 0, paste("Exit status:", status))
}

fwrite(checks, file.path(audit_dir, "audit_checks.csv"))

failed <- checks[passed == FALSE]
md_lines <- c(
  "# Sector First-Stage Audit",
  "",
  paste0("- Date: ", Sys.Date()),
  paste0("- Sector variable: `", SECTOR_VAR, "`"),
  paste0("- Strict mode: `", STRICT, "`"),
  "",
  "## Results",
  ""
)

if (nrow(failed) == 0) {
  md_lines <- c(md_lines, "- All checks passed.")
} else {
  for (i in seq_len(nrow(failed))) {
    md_lines <- c(
      md_lines,
      paste0("- [", failed$severity[i], "] `", failed$dataset[i], "::", failed$check_id[i], "`: ", failed$details[i])
    )
  }
}

md_path <- file.path(audit_dir, "audit_summary.md")
writeLines(md_lines, md_path)
cat("Saved audit outputs to:\n")
cat("  ", audit_dir, "\n\n")

if (nrow(failed) && STRICT) {
  stop("Audit failed with ", nrow(failed), " failing checks.")
}

cat("Audit complete.\n")
