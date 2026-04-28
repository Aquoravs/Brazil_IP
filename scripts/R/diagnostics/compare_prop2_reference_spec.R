#!/usr/bin/env Rscript

# ==============================================================================
# Compare Proposition 2 Reference Spec from the Firm Baseline Regression
# ==============================================================================
# Purpose:
#   Rebuild the reference script-51 firm baseline regression for the saved
#   default BNDES-extensive specification; recover the exact estimation
#   sample actually used after FE pruning; recover the saved FE solution from
#   the firm regression; and then construct the aggregate analogs from that same
#   used sample.
#
#   The script exports three linked objects:
#     1. A comparison table:
#          - rebuilt firm coefficient / SE / F-stat
#          - aggregated mean regression after subtracting saved FE averages
#          - exact cell-level sufficient-stat coefficient implied by the firm FE
#     2. A diagnostics CSV:
#          - candidate sample A vs used sample B overlap
#          - firm/cell pruning summaries
#          - exact-vs-mean decomposition terms
#     3. A cell-level QS2 file:
#          - H_jmt, X_bar, averaged firm FE, muni-year FE, and sufficient stats
#
# Usage:
#   Rscript compare_prop2_reference_spec.R [--sector-var=sector_group]
# ==============================================================================

cat("==============================================================================\n")
cat("Compare Proposition 2 Reference Spec from Firm Baseline\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
  library(qs2)
})

# --- Bootstrap -----------------------------------------------------------------

bootstrap_file <- local({
  project_root_opt <- getOption("politicsregs.project_root", default = NULL)
  if (is.character(project_root_opt) && length(project_root_opt) == 1L && nzchar(project_root_opt)) {
    return(file.path(project_root_opt, "scripts", "R", "_utils", "script_bootstrap.R"))
  }

  script_args_full <- commandArgs(trailingOnly = FALSE)
  script_file <- grep("^--file=", script_args_full, value = TRUE)
  if (length(script_file)) {
    script_file <- normalizePath(sub("^--file=", "", script_file[[1L]]), winslash = "/", mustWork = TRUE)
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
source(politicsregs_path("_utils", "load_firm_panel.R"))

# --- Parse CLI args ------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
svar_flag <- grep("^--sector-var=", args, value = TRUE)

SECTOR_VAR <- "sector_group"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[[1L]])))
  if (!SECTOR_VAR %in% c("cnae_section", "sector_group")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'. Use 'cnae_section' or 'sector_group'.")
  }
}

SCOL <- SECTOR_VAR
cat("Sector variable:", SECTOR_VAR, "\n\n")

setDTthreads(1L)
fixest::setFixest_nthreads(1L)

# --- Configuration -------------------------------------------------------------

FE_FIRM <- "firm_id + muni_id^year"
VCOV_FIRM <- ~ firm_id + muni_id
VCOV_AGG <- as.formula(paste0("~ muni_id + ", SCOL))
VERIFY_TOL <- 1e-8

TARGET_SPECS <- list(
  list(combo = "M", tier = "Mayor", term = "FA_mayor_coalition"),
  list(combo = "G", tier = "Governor", term = "FA_gov_coalition"),
  list(combo = "P", tier = "President", term = "FA_pres_coalition")
)

diag_dir <- file.path(OUTPUT_DIR, "diagnostics")
dir.create(diag_dir, recursive = TRUE, showWarnings = FALSE)

comparison_base <- file.path(diag_dir, "prop2_reference_spec_comparison")
diagnostics_path <- file.path(diag_dir, "prop2_reference_spec_diagnostics.csv")
cell_fe_path <- file.path(diag_dir, "prop2_reference_spec_cell_fe.qs2")

# --- Helpers -------------------------------------------------------------------

write_csv_atomic <- function(dt, path) {
  tmp <- tempfile(pattern = "prop2-ref-", tmpdir = dirname(path), fileext = ".csv")
  fwrite(dt, tmp)
  if (file.exists(path)) {
    file.remove(path)
  }
  if (!file.rename(tmp, path)) {
    stop("Failed to write file: ", path)
  }
}

write_qs_atomic <- function(obj, path) {
  tmp <- tempfile(pattern = "prop2-ref-", tmpdir = dirname(path), fileext = ".qs2")
  qs_save(obj, tmp)
  if (file.exists(path)) {
    file.remove(path)
  }
  if (!file.rename(tmp, path)) {
    stop("Failed to write file: ", path)
  }
}

format_num <- function(x, digits = 6L) {
  ifelse(is.na(x), "", formatC(x, digits = digits, format = "f"))
}

format_sci <- function(x, digits = 3L) {
  ifelse(is.na(x), "", formatC(x, digits = digits, format = "e"))
}

format_stat <- function(x, digits = 3L) {
  ifelse(is.na(x), "", formatC(x, digits = digits, format = "f"))
}

format_int <- function(x) {
  ifelse(is.na(x), "", formatC(as.integer(round(x)), format = "d", big.mark = ","))
}

escape_tex <- function(x) {
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("_", "\\\\_", x, fixed = TRUE)
  x
}

safe_wald <- function(mod, keep) {
  tryCatch(
    {
      out <- capture.output(wald_obj <- suppressMessages(fixest::wald(mod, keep = keep)))
      invisible(out)
      wald_obj$stat
    },
    error = function(e) NA_real_
  )
}

safe_coef <- function(mod, term) {
  ct <- tryCatch(fixest::coeftable(mod), error = function(e) NULL)
  if (is.null(ct) || !term %in% rownames(ct)) return(NA_real_)
  unname(ct[term, 1])
}

safe_se <- function(mod, term) {
  ct <- tryCatch(fixest::coeftable(mod), error = function(e) NULL)
  if (is.null(ct) || !term %in% rownames(ct)) return(NA_real_)
  unname(ct[term, 2])
}

get_removed_obs <- function(mod) {
  removed <- mod$obs_selection$obsRemoved
  if (is.null(removed)) {
    return(integer(0))
  }

  removed <- as.integer(removed)
  if (all(removed <= 0L)) {
    removed <- -removed
  } else if (any(removed < 0L)) {
    stop("obsRemoved contains a mix of positive and negative indices.")
  }

  sort(unique(removed))
}

recover_fe_components <- function(mod) {
  fe_vals <- fixef(mod)
  fe_ids <- mod$fixef_id

  if (is.null(fe_vals) || is.null(fe_ids) || length(fe_vals) != 2L || length(fe_ids) != 2L) {
    stop("Expected exactly two FE dimensions in the reference firm model.")
  }

  nm <- names(fe_vals)
  firm_nm <- nm[grepl("^firm_id$", nm)]
  mt_nm <- nm[grepl("^muni_id\\^year$", nm)]

  if (length(firm_nm) != 1L || length(mt_nm) != 1L) {
    stop("Could not identify firm_id and muni_id^year FE dimensions.")
  }

  firm_fe <- unname(fe_vals[[firm_nm]][fe_ids[[firm_nm]]])
  muniyear_fe <- unname(fe_vals[[mt_nm]][fe_ids[[mt_nm]]])
  sum_fe <- unname(mod$sumFE)

  data.table(
    firm_fe_hat = firm_fe,
    muniyear_fe_hat = muniyear_fe,
    sum_fe_hat = sum_fe
  )
}

load_panel <- function(sector_var, target_terms) {
  inst_cols <- grep("^(FA_|dFA_)", target_terms, value = TRUE)
  base_cols  <- unique(c("firm_id", "muni_id", "year", "cnae_section", sector_var, "has_bndes_fmt",
                          setdiff(target_terms, inst_cols)))

  dt <- load_firm_panel(
    baseline_type = "cycle_specific",
    columns       = base_cols,
    instruments   = if (length(inst_cols)) inst_cols else character(0),
    zero_fill     = TRUE,
    as_data_table = TRUE
  )
  cat(sprintf("Loaded panel: %s rows\n", format(nrow(dt), big.mark = ",")))

  dt[, firm_id := as.integer(firm_id)]
  dt[, muni_id := as.integer(muni_id)]
  dt[, year := as.integer(year)]

  if (identical(sector_var, "sector_group") && !"sector_group" %in% names(dt)) {
    mapping_path <- make_output_path("sector_group_mapping.qs2")
    if (!file.exists(mapping_path)) {
      stop("sector_group mapping not found. Run script 30 first.")
    }
    sg_map <- qs_read(mapping_path)
    setDT(sg_map)
    dt[sg_map, sector_group := i.sector_group, on = "cnae_section"]
  }

  missing_cols <- setdiff(c("firm_id", "muni_id", "year", sector_var, "has_bndes_fmt", target_terms), names(dt))
  if (length(missing_cols)) {
    stop("Panel is missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  if (!is.character(dt[[sector_var]])) {
    dt[, (sector_var) := as.character(get(sector_var))]
  }

  dt
}

build_md_table <- function(comp_dt, notes) {
  header <- c(
    "# Proposition 2 Reference-Spec Comparison",
    "",
    "| Tier | Firm beta | Firm SE | Firm F | Firm N | Agg beta (mean + saved FE) | Agg SE | Agg F | Agg cells | Exact beta (cell SS) | Gap (mean agg) | Gap (exact) | Max identity err |",
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
  )

  body <- vapply(seq_len(nrow(comp_dt)), function(i) {
    row <- comp_dt[i]
    paste0(
      "| ", row$tier,
      " | ", format_num(row$firm_coef),
      " | ", format_num(row$firm_se),
      " | ", format_stat(row$firm_f_stat),
      " | ", format_int(row$firm_n_obs),
      " | ", format_num(row$agg_mean_coef),
      " | ", format_num(row$agg_mean_se),
      " | ", format_stat(row$agg_mean_f_stat),
      " | ", format_int(row$agg_n_cells),
      " | ", format_num(row$agg_exact_coef),
      " | ", format_num(row$agg_mean_gap),
      " | ", format_sci(row$agg_exact_gap),
      " | ", format_sci(row$max_abs_identity_error),
      " |"
    )
  }, character(1))

  c(header, body, "", notes)
}

build_tex_table <- function(comp_dt, notes) {
  col_header <- paste(
    "Tier", "Firm $\\beta$", "Firm SE", "Firm $F$", "Firm $N$",
    "Agg $\\beta$ (mean+FE)", "Agg SE", "Agg $F$", "Agg cells",
    "Exact $\\beta$", "Gap (mean)", "Gap (exact)", "Max id. err.",
    sep = " & "
  )

  rows <- vapply(seq_len(nrow(comp_dt)), function(i) {
    row <- comp_dt[i]
    paste0(
      escape_tex(row$tier), " & ",
      format_num(row$firm_coef), " & ",
      format_num(row$firm_se), " & ",
      format_stat(row$firm_f_stat), " & ",
      format_int(row$firm_n_obs), " & ",
      format_num(row$agg_mean_coef), " & ",
      format_num(row$agg_mean_se), " & ",
      format_stat(row$agg_mean_f_stat), " & ",
      format_int(row$agg_n_cells), " & ",
      format_num(row$agg_exact_coef), " & ",
      format_num(row$agg_mean_gap), " & ",
      format_sci(row$agg_exact_gap), " & ",
      format_sci(row$max_abs_identity_error), " \\\\"
    )
  }, character(1))

  c(
    "\\sbox0{%",
    "\\begin{tabular}[t]{lrrrrrrrrrrrr}",
    "\\toprule",
    col_header, "\\\\",
    "\\midrule",
    rows,
    "\\bottomrule",
    "\\end{tabular}",
    "}%",
    "\\ifdim\\wd0>\\linewidth",
    "  \\resizebox{\\linewidth}{!}{\\usebox0}%",
    paste0("  \\par\\vspace{3pt}\\parbox{\\linewidth}{\\raggedright\\scriptsize ", notes, "}"),
    "\\else",
    "  \\usebox0%",
    paste0("  \\par\\vspace{3pt}\\parbox{\\wd0}{\\raggedright\\scriptsize ", notes, "}"),
    "\\fi"
  )
}

# --- Load saved firm results for verification ----------------------------------

summary_path <- file.path(OUTPUT_DIR, "firm_reg_tables", "fc_battery_summary.qs2")
manifest_path <- file.path(OUTPUT_DIR, "firm_reg_tables", "firm_run_manifest.qs2")

if (!file.exists(summary_path)) {
  stop("Missing fc_battery_summary.qs2. Run script 51 first.")
}
if (!file.exists(manifest_path)) {
  stop("Missing firm_run_manifest.qs2. Run script 51 first.")
}

firm_summary <- qs_read(summary_path)
manifest <- qs_read(manifest_path)
setDT(firm_summary)
setDT(manifest)

required_manifest_cols <- c(
  "canonical_slug", "family", "outcome", "exposure", "weighting",
  "baseline", "alignment", "time_variation", "sample", "depvar", "tex_path"
)
missing_manifest_cols <- setdiff(required_manifest_cols, names(manifest))
if (length(missing_manifest_cols)) {
  stop("Manifest is missing required columns: ", paste(missing_manifest_cols, collapse = ", "))
}

manifest_row <- manifest[
  family == "main" &
    outcome == "bndes_extensive" &
    exposure == "pooled_count" &
    weighting == "unweighted" &
    baseline == "cycle_specific" &
    alignment == "coalition" &
    time_variation == "levels" &
    sample == "all_firms" &
    depvar == "has_bndes_fmt"
]
if (nrow(manifest_row) != 1L) {
  stop("Expected exactly one manifest row for the default BNDES-extensive reference spec.")
}

REFERENCE_SLUG <- manifest_row$canonical_slug[[1L]]
firm_tex_path <- manifest_row$tex_path[[1L]]
REFERENCE_FILE <- paste0(REFERENCE_SLUG, ".tex")
if (!identical(basename(firm_tex_path), REFERENCE_FILE)) {
  stop("Manifest tex_path does not match expected reference file.")
}
if (!file.exists(firm_tex_path)) {
  stop("Saved firm tex file not found at manifest path: ", firm_tex_path)
}

cat("Reference slug:", REFERENCE_SLUG, "\n")
cat("Saved firm tex path:", firm_tex_path, "\n\n")

# --- Load panel ----------------------------------------------------------------

target_terms <- vapply(TARGET_SPECS, `[[`, character(1), "term")
dt <- load_panel(SCOL, target_terms)
cat("\n")

# --- Main loop -----------------------------------------------------------------

comparison_rows <- vector("list", length(TARGET_SPECS))
diagnostic_rows <- vector("list", length(TARGET_SPECS))
cell_fe_rows <- vector("list", length(TARGET_SPECS))

for (i in seq_along(TARGET_SPECS)) {
  spec_info <- TARGET_SPECS[[i]]
  combo_name <- spec_info$combo
  tier <- spec_info$tier
  term <- spec_info$term

  cat(sprintf("Rebuilding %s comparison (%s)...\n", tier, combo_name))

  firm_row <- firm_summary[spec == REFERENCE_SLUG & combo == combo_name & variable == term]
  if (nrow(firm_row) != 1L) {
    stop("Expected exactly one saved firm summary row for combo ", combo_name, " and term ", term)
  }

  dt_candidate <- dt[
    !is.na(has_bndes_fmt) & !is.na(get(term)),
    .(
      firm_id = as.integer(firm_id),
      muni_id = as.integer(muni_id),
      year = as.integer(year),
      sector_cell = get(SCOL),
      y = as.numeric(has_bndes_fmt),
      x = as.numeric(get(term))
    )
  ]
  setnames(dt_candidate, "sector_cell", SCOL)

  candidate_rows <- nrow(dt_candidate)
  candidate_firms <- uniqueN(dt_candidate$firm_id)
  candidate_cells <- uniqueN(dt_candidate[, c(SCOL, "muni_id", "year"), with = FALSE])

  mod_firm <- feols(
    y ~ x | firm_id + muni_id^year,
    data = dt_candidate,
    vcov = VCOV_FIRM,
    notes = FALSE,
    lean = FALSE,
    mem.clean = TRUE,
    nthreads = 1L
  )

  removed <- get_removed_obs(mod_firm)
  keep <- rep(TRUE, candidate_rows)
  if (length(removed)) {
    keep[removed] <- FALSE
  }

  dt_used <- dt_candidate[keep]
  fe_dt <- recover_fe_components(mod_firm)
  if (nrow(dt_used) != nrow(fe_dt) || nrow(dt_used) != length(mod_firm$residuals)) {
    stop("Used sample rows and FE vectors do not align for combo ", combo_name)
  }

  dt_used[, `:=`(
    firm_fe_hat = fe_dt$firm_fe_hat,
    muniyear_fe_hat = fe_dt$muniyear_fe_hat,
    sum_fe_hat = fe_dt$sum_fe_hat,
    u_hat = as.numeric(mod_firm$residuals)
  )]
  dt_used[, y_tilde := y - sum_fe_hat]

  max_abs_sumfe_check <- max(abs(dt_used$sum_fe_hat - (dt_used$firm_fe_hat + dt_used$muniyear_fe_hat)))

  firm_coef <- safe_coef(mod_firm, "x")
  firm_se <- safe_se(mod_firm, "x")
  firm_f <- safe_wald(mod_firm, "^x$")
  firm_n_obs <- as.integer(nobs(mod_firm))

  saved_coef <- as.numeric(firm_row$coef[[1L]])
  saved_se <- as.numeric(firm_row$se[[1L]])
  saved_f <- as.numeric(firm_row$wald_f[[1L]])
  saved_n_obs <- as.integer(firm_row$n_obs[[1L]])

  coef_gap_saved <- firm_coef - saved_coef
  se_gap_saved <- firm_se - saved_se
  f_gap_saved <- firm_f - saved_f
  n_gap_saved <- firm_n_obs - saved_n_obs

  if (abs(coef_gap_saved) > VERIFY_TOL) {
    cat(sprintf("  WARNING: rebuilt coefficient differs from saved summary by %.3e\n", coef_gap_saved))
  }

  candidate_firm_counts <- dt_candidate[, .(candidate_n = .N), by = firm_id]
  used_firm_counts <- dt_used[, .(used_n = .N), by = firm_id]
  firm_overlap <- merge(candidate_firm_counts, used_firm_counts, by = "firm_id", all.x = TRUE, sort = FALSE)
  firm_overlap[is.na(used_n), used_n := 0L]

  fully_kept_firms <- firm_overlap[used_n == candidate_n, .N]
  partially_dropped_firms <- firm_overlap[used_n > 0L & used_n < candidate_n, .N]
  fully_dropped_firms <- firm_overlap[used_n == 0L, .N]
  fully_dropped_singleton_firms <- firm_overlap[candidate_n == 1L & used_n == 0L, .N]

  candidate_cell_counts <- dt_candidate[, .(candidate_N_c = .N), by = c(SCOL, "muni_id", "year")]
  used_cell_counts <- dt_used[, .(used_N_c = .N), by = c(SCOL, "muni_id", "year")]
  cell_overlap <- merge(
    candidate_cell_counts,
    used_cell_counts,
    by = c(SCOL, "muni_id", "year"),
    all.x = TRUE,
    sort = FALSE
  )
  cell_overlap[is.na(used_N_c), used_N_c := 0L]

  fully_kept_cells <- cell_overlap[used_N_c == candidate_N_c, .N]
  partially_pruned_cells <- cell_overlap[used_N_c > 0L & used_N_c < candidate_N_c, .N]
  fully_dropped_cells <- cell_overlap[used_N_c == 0L, .N]

  agg_cell <- dt_used[, .(
    H_jmt = mean(y),
    X_bar = mean(x),
    N_c = .N,
    firm_fe_bar = mean(firm_fe_hat),
    muniyear_fe_hat = mean(muniyear_fe_hat),
    sum_fe_bar = mean(sum_fe_hat),
    u_bar = mean(u_hat),
    x_sum = sum(x),
    y_tilde_sum = sum(y_tilde),
    x_sq_sum = sum(x^2),
    x_ytilde_sum = sum(x * y_tilde)
  ), by = c(SCOL, "muni_id", "year")]

  agg_cell[, H_net := H_jmt - sum_fe_bar]
  agg_cell[, y_tilde_bar := y_tilde_sum / N_c]
  agg_cell[, fe_decomp_error := sum_fe_bar - (firm_fe_bar + muniyear_fe_hat)]
  agg_cell[, identity_error := H_jmt - (firm_coef * X_bar + sum_fe_bar + u_bar)]

  mod_agg_mean <- feols(
    H_net ~ 0 + X_bar,
    data = agg_cell,
    weights = ~N_c,
    vcov = VCOV_AGG,
    notes = FALSE,
    lean = TRUE,
    mem.clean = TRUE,
    nthreads = 1L
  )

  agg_mean_coef <- safe_coef(mod_agg_mean, "X_bar")
  agg_mean_se <- safe_se(mod_agg_mean, "X_bar")
  agg_mean_f <- safe_wald(mod_agg_mean, "^X_bar$")
  agg_n_cells <- as.integer(nobs(mod_agg_mean))

  exact_num <- sum(agg_cell$x_ytilde_sum)
  exact_den <- sum(agg_cell$x_sq_sum)
  mean_num <- sum(agg_cell$x_sum * agg_cell$y_tilde_sum / agg_cell$N_c)
  mean_den <- sum((agg_cell$x_sum^2) / agg_cell$N_c)
  within_num_gap <- exact_num - mean_num
  within_den_gap <- exact_den - mean_den
  within_den_share_pct <- if (isTRUE(all.equal(exact_den, 0))) NA_real_ else 100 * within_den_gap / exact_den

  agg_exact_coef <- exact_num / exact_den
  agg_exact_micro_coef <- sum(dt_used$x * dt_used$y_tilde) / sum(dt_used$x^2)

  max_abs_identity_error <- max(abs(agg_cell$identity_error))
  max_abs_fe_decomp_error <- max(abs(agg_cell$fe_decomp_error))

  comparison_rows[[i]] <- data.table(
    combo = combo_name,
    tier = tier,
    firm_coef = firm_coef,
    firm_se = firm_se,
    firm_f_stat = firm_f,
    firm_n_obs = firm_n_obs,
    agg_mean_coef = agg_mean_coef,
    agg_mean_se = agg_mean_se,
    agg_mean_f_stat = agg_mean_f,
    agg_n_cells = agg_n_cells,
    agg_exact_coef = agg_exact_coef,
    agg_mean_gap = agg_mean_coef - firm_coef,
    agg_exact_gap = agg_exact_coef - firm_coef,
    max_abs_identity_error = max_abs_identity_error,
    firm_tex_path = firm_tex_path
  )

  diagnostic_rows[[i]] <- data.table(
    combo = combo_name,
    tier = tier,
    instrument = term,
    candidate_rows_A = candidate_rows,
    used_rows_B = firm_n_obs,
    dropped_rows_A_minus_B = candidate_rows - firm_n_obs,
    dropped_rows_share_pct = 100 * (candidate_rows - firm_n_obs) / max(candidate_rows, 1L),
    candidate_firms = candidate_firms,
    used_firms = uniqueN(dt_used$firm_id),
    fully_kept_firms = fully_kept_firms,
    partially_dropped_firms = partially_dropped_firms,
    fully_dropped_firms = fully_dropped_firms,
    fully_dropped_singleton_firms = fully_dropped_singleton_firms,
    candidate_cells = candidate_cells,
    used_cells = nrow(used_cell_counts),
    fully_kept_cells = fully_kept_cells,
    partially_pruned_cells = partially_pruned_cells,
    fully_dropped_cells = fully_dropped_cells,
    saved_firm_coef = saved_coef,
    rebuilt_firm_coef = firm_coef,
    saved_rebuilt_coef_gap = coef_gap_saved,
    saved_rebuilt_se_gap = se_gap_saved,
    saved_rebuilt_f_gap = f_gap_saved,
    saved_rebuilt_n_gap = n_gap_saved,
    agg_mean_coef = agg_mean_coef,
    agg_exact_coef = agg_exact_coef,
    agg_mean_gap = agg_mean_coef - firm_coef,
    agg_exact_gap = agg_exact_coef - firm_coef,
    exact_num = exact_num,
    mean_num = mean_num,
    within_num_gap = within_num_gap,
    exact_den = exact_den,
    mean_den = mean_den,
    within_den_gap = within_den_gap,
    within_den_share_pct = within_den_share_pct,
    agg_exact_micro_gap = agg_exact_micro_coef - firm_coef,
    max_abs_identity_error = max_abs_identity_error,
    max_abs_fe_decomp_error = max_abs_fe_decomp_error,
    max_abs_sumfe_check = max_abs_sumfe_check,
    agg_mean_formula = "H_net ~ 0 + X_bar",
    agg_weight = "N_c",
    agg_fe_source = "saved firm FE averaged to cell-year + saved muni_id^year FE"
  )

  cell_fe_rows[[i]] <- agg_cell[, `:=`(
    combo = combo_name,
    tier = tier,
    instrument = term,
    firm_beta = firm_coef
  )][]

  cat(sprintf(
    "  Firm beta = %.6f, Agg beta (mean+saved FE) = %.6f, Exact beta (cell SS) = %.6f, max identity err = %.3e\n",
    firm_coef,
    agg_mean_coef,
    agg_exact_coef,
    max_abs_identity_error
  ))

  rm(dt_candidate, dt_used, fe_dt, candidate_firm_counts, used_firm_counts, firm_overlap,
     candidate_cell_counts, used_cell_counts, cell_overlap, agg_cell, mod_firm, mod_agg_mean)
  invisible(gc())
}

comparison_dt <- rbindlist(comparison_rows)
diagnostic_dt <- rbindlist(diagnostic_rows)
cell_fe_dt <- rbindlist(cell_fe_rows, fill = TRUE)

setcolorder(comparison_dt, c(
  "combo", "tier", "firm_coef", "firm_se", "firm_f_stat", "firm_n_obs",
  "agg_mean_coef", "agg_mean_se", "agg_mean_f_stat", "agg_n_cells",
  "agg_exact_coef", "agg_mean_gap", "agg_exact_gap",
  "max_abs_identity_error", "firm_tex_path"
))

setcolorder(diagnostic_dt, c(
  "combo", "tier", "instrument",
  "candidate_rows_A", "used_rows_B", "dropped_rows_A_minus_B", "dropped_rows_share_pct",
  "candidate_firms", "used_firms", "fully_kept_firms", "partially_dropped_firms",
  "fully_dropped_firms", "fully_dropped_singleton_firms",
  "candidate_cells", "used_cells", "fully_kept_cells", "partially_pruned_cells",
  "fully_dropped_cells",
  "saved_firm_coef", "rebuilt_firm_coef", "saved_rebuilt_coef_gap",
  "saved_rebuilt_se_gap", "saved_rebuilt_f_gap", "saved_rebuilt_n_gap",
  "agg_mean_coef", "agg_exact_coef", "agg_mean_gap", "agg_exact_gap",
  "exact_num", "mean_num", "within_num_gap",
  "exact_den", "mean_den", "within_den_gap", "within_den_share_pct",
  "agg_exact_micro_gap",
  "max_abs_identity_error", "max_abs_fe_decomp_error", "max_abs_sumfe_check",
  "agg_mean_formula", "agg_weight", "agg_fe_source"
))

setcolorder(cell_fe_dt, c(
  "combo", "tier", "instrument", SCOL, "muni_id", "year", "N_c",
  "H_jmt", "X_bar", "firm_fe_bar", "muniyear_fe_hat", "sum_fe_bar",
  "H_net", "y_tilde_bar", "u_bar", "identity_error", "fe_decomp_error",
  "x_sum", "y_tilde_sum", "x_sq_sum", "x_ytilde_sum", "firm_beta"
))

# --- Write outputs -------------------------------------------------------------

notes_md <- paste(
  "Reference-spec rebuild from the firm baseline regression.",
  "For each single-tier combo, the script refits the unweighted firm model on the exact `51` reference sample,",
  "drops the same FE-pruned rows, recovers the fitted FE contributions, and then collapses the used sample only.",
  "The column `Agg beta (mean + saved FE)` is the coefficient from the actual cell-mean regression",
  "`H_net ~ 0 + X_bar` with `N_c` weights after subtracting the saved averaged FE from the outcome.",
  "The column `Exact beta (cell SS)` is the exact cell-level sufficient-stat coefficient",
  "`sum_c sum_i x_i(y_i - FE_i) / sum_c sum_i x_i^2`, which should match the firm coefficient up to numerical tolerance."
)

notes_tex <- paste(
  "Reference-spec rebuild from the firm baseline regression.",
  "For each single-tier combo, the script refits the unweighted firm model on the exact script-51 reference sample,",
  "drops the same FE-pruned rows, recovers the fitted FE contributions, and then collapses the used sample only.",
  "The column Agg $\\beta$ (mean+FE) comes from the cell-mean regression",
  "\\texttt{H\\_net \\textasciitilde{} 0 + X\\_bar} with $N_c$ weights after subtracting the saved averaged FE from the outcome.",
  "The column Exact $\\beta$ is the exact cell-level sufficient-stat coefficient",
  "$\\sum_c \\sum_{i\\in c} x_i(y_i-\\widehat{FE}_i) / \\sum_c \\sum_{i\\in c} x_i^2$,",
  "which should match the firm coefficient up to numerical tolerance."
)

write_csv_atomic(comparison_dt, paste0(comparison_base, ".csv"))
writeLines(build_md_table(comparison_dt, notes_md), paste0(comparison_base, ".md"))
writeLines(build_tex_table(comparison_dt, notes_tex), paste0(comparison_base, ".tex"))
write_csv_atomic(diagnostic_dt, diagnostics_path)
write_qs_atomic(cell_fe_dt, cell_fe_path)

cat("\nSaved:\n")
cat("  ", paste0(comparison_base, ".csv"), "\n", sep = "")
cat("  ", paste0(comparison_base, ".md"), "\n", sep = "")
cat("  ", paste0(comparison_base, ".tex"), "\n", sep = "")
cat("  ", diagnostics_path, "\n", sep = "")
cat("  ", cell_fe_path, "\n", sep = "")

cat("\nDone.\n")
