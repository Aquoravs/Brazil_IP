cat("==============================================================================\n")
cat("Audit: Municipality Panels (Stage 41)\n")
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
    script_dir <- dirname(normalizePath(frame_paths[[length(frame_paths)]], winslash = "/", mustWork = TRUE))
    return(file.path(script_dir, "..", "_utils", "script_bootstrap.R"))
  }

  file.path(getwd(), "_utils", "script_bootstrap.R")
})
source(bootstrap_file)
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

cat("Sector variable:", SECTOR_VAR, "\n")
cat("Strict mode:", STRICT, "\n\n")

suffix <- if (SECTOR_VAR == "sector_group") "_grouped" else ""
sc_col <- SECTOR_VAR

audit_dir <- file.path(OUTPUT_DIR, "diagnostics", paste0("41_muni_panel_audit_", SECTOR_VAR))
dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)

load_dt <- function(path) {
  obj <- qs_read(path)
  setDT(obj)
  obj
}

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

registry <- data.table(
  dataset = c("bndes_credit_shares", "muni_sector_panel", "muni_panel_for_regs"),
  path = c(
    make_output_path(paste0("bndes_credit_shares", suffix, ".qs2")),
    make_output_path(paste0("muni_sector_panel", suffix, ".qs2")),
    make_output_path(paste0("muni_panel_for_regs", suffix, ".qs2"))
  )
)
registry[, exists := file.exists(path)]
registry[, size_mb := fifelse(exists, file.size(path) / 1024^2, NA_real_)]
fwrite(registry, file.path(audit_dir, "00_data_inventory.csv"))

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

if (!is.null(d$bndes_credit_shares) && !is.null(d$muni_sector_panel)) {
  credit <- d$bndes_credit_shares
  panel_a <- d$muni_sector_panel

  needed <- c("muni_id", sc_col, "year", "s_mjt", "delta_s_mjt")
  if (all(needed %in% names(credit)) && all(needed %in% names(panel_a))) {
    cmp <- merge(
      credit[, .(muni_id, year, sector = get(sc_col), s_mjt, delta_s_mjt)],
      panel_a[, .(muni_id, year, sector = get(sc_col), s_panel = s_mjt, delta_panel = delta_s_mjt)],
      by = c("muni_id", "year", "sector"),
      all = FALSE
    )

    max_s_diff <- cmp[, max(abs(s_mjt - s_panel), na.rm = TRUE)]
    add_check("identity", "muni_sector_panel", "preserves_s_mjt",
              is.finite(max_s_diff) && max_s_diff < 1e-8,
              sprintf("max|PanelA s_mjt - script35 s_mjt| = %.6e", max_s_diff))

    max_delta_diff <- cmp[, max(abs(delta_s_mjt - delta_panel), na.rm = TRUE)]
    add_check("identity", "muni_sector_panel", "preserves_delta_s_mjt",
              is.finite(max_delta_diff) && max_delta_diff < 1e-8,
              sprintf("max|PanelA delta_s_mjt - script35 delta_s_mjt| = %.6e", max_delta_diff))
  }
}

if (!is.null(d$muni_panel_for_regs)) {
  panel_b <- d$muni_panel_for_regs
  delta_cols <- grep("^delta_s_", names(panel_b), value = TRUE)
  if (!is.null(d$muni_sector_panel) && length(delta_cols) && all(c("muni_id", "year") %in% names(panel_b))) {
    panel_a <- d$muni_sector_panel
    first_year_a <- panel_a[, .(first_year_panel_a = min(year, na.rm = TRUE)), by = muni_id]
            first_rows_b <- panel_b[, .SD[which.min(year)], by = muni_id, .SDcols = c("year", delta_cols)]
    first_rows_b <- merge(first_rows_b, first_year_a, by = "muni_id", all.x = TRUE)
    first_rows_b <- first_rows_b[year == first_year_panel_a]
    n_defined_first_year <- first_rows_b[, sum(vapply(.SD, function(x) sum(!is.na(x)), integer(1))), .SDcols = delta_cols]
    n_zero_first_year <- first_rows_b[, sum(vapply(.SD, function(x) sum(!is.na(x) & x == 0), integer(1))), .SDcols = delta_cols]
    add_check("identity", "muni_panel_for_regs", "first_year_delta_not_zero_filled",
              isTRUE(n_defined_first_year == 0L),
              paste("Defined wide delta_s entries in municipality true first year:", n_defined_first_year,
                    "| zeros among them:", n_zero_first_year))
  }
}

fwrite(checks, file.path(audit_dir, "audit_checks.csv"))

failed <- checks[passed == FALSE]
md_lines <- c(
  "# Municipality Panel Audit",
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
