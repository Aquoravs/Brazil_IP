#!/usr/bin/env Rscript

# ==============================================================================
# Second-Stage: Optimality Test (Reduced Form + 2SLS)
# ==============================================================================
# Tests whether politically-driven BNDES sectoral reallocation affects GDP.
# Uses municipality×year panel (Panel B) with wide-format sector columns.
#
# Table 4: Reduced Form (muni×year) — sector-specific instruments
#   log(GDP_pc) ~ Z_mayor_sec_j [+ Z_gov_sec_j] [+ bndes_pc] | muni_id + year
#   Joint Wald test: H0: all pi_j = 0 (optimality null)
#
# Table 5: Scalar 2SLS (muni×year)
#   log(GDP_pc) ~ 1 | muni_id + year | delta_hhi ~ Z_mayor [+ Z_gov]
#   (Tests concentration effect of political reallocation)
#
# Table 6: Vector 2SLS (muni×year)
#   log(GDP_pc) ~ 1 | muni_id + year | delta_s_A + ... ~ Z_sec_A + ...
#   J-1 endogenous sector shares instrumented by sector-specific Z
#   Joint Wald test on all beta_j = optimality null
#
# Table 7: Robustness
#   2002-fixed baselines, trimmed sample, alternative clustering, OLS, placebo
#
# Usage:
#   Rscript 53_sector_second_stage.R [--align=coalition|party|both] [--specs=all|rf|scalar|vector|robust]
#
#   --align=coalition  Use coalition-level alignment instruments (default)
#   --align=party      Use party-level alignment instruments
#   --align=both       Run tables for both party and coalition instruments
#
#   --specs=all        Run all tables (default)
#   --specs=rf         Reduced form only (Table 4)
#   --specs=scalar     Scalar 2SLS only (Table 5)
#   --specs=vector     Vector 2SLS only (Table 6)
#   --specs=robust     Robustness only (Table 7)
#   Comma-separated allowed, e.g. --specs=rf,scalar
#
#   --sector-var=sector_group  Use ~10 grouped sectors (default; from script 30)
#   --sector-var=cnae_section  Use 21 CNAE sections
#
# Dependencies: script 41 (muni_panel_for_regs.qs2)
# ==============================================================================

cat("==============================================================================\n")
cat("Second-Stage: Optimality Test (Reduced Form + 2SLS)\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(fixest)
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

fixest::setFixest_nthreads(1)

# --- Parse CLI arguments ------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)

align_flag <- grep("^--align=", args, value = TRUE)
ALIGN_TYPE <- "coalition"
if (length(align_flag)) {
  ALIGN_TYPE <- tolower(trimws(sub("^--align=", "", align_flag[1])))
  if (!ALIGN_TYPE %in% c("coalition", "party", "both")) {
    stop("Invalid --align value: '", ALIGN_TYPE,
         "'. Use 'coalition', 'party', or 'both'.")
  }
}

specs_flag <- grep("^--specs=", args, value = TRUE)
SPECS <- "all"
if (length(specs_flag)) {
  SPECS <- tolower(trimws(sub("^--specs=", "", specs_flag[1])))
}
run_specs <- if (SPECS == "all") {
  c("rf", "scalar", "vector", "robust")
} else {
  strsplit(SPECS, ",")[[1]]
}
valid_specs <- c("rf", "scalar", "vector", "robust")
bad <- setdiff(run_specs, valid_specs)
if (length(bad)) {
  stop("Invalid --specs value(s): ", paste(bad, collapse = ", "),
       ". Use: ", paste(valid_specs, collapse = ", "))
}

# --- Parse --sector-var flag --------------------------------------------------

svar_flag <- grep("^--sector-var=", args, value = TRUE)
SECTOR_VAR <- "sector_group"
if (length(svar_flag)) {
  SECTOR_VAR <- tolower(trimws(sub("^--sector-var=", "", svar_flag[1])))
  if (!SECTOR_VAR %in% c("cnae_section", "sector_group")) {
    stop("Invalid --sector-var value: '", SECTOR_VAR, "'. Use 'cnae_section' or 'sector_group'.")
  }
}
USE_GROUPS <- (SECTOR_VAR == "sector_group")

cat("Alignment type:", ALIGN_TYPE, "\n")
cat("Sector variable:", SECTOR_VAR, "\n")
cat("Specifications:", paste(run_specs, collapse = ", "), "\n\n")

# --- Configuration -----------------------------------------------------------

if (USE_GROUPS) {
  panel_b_path <- make_output_path("muni_panel_for_regs_grouped.qs2")
  table_dir    <- file.path(TABLES_DIR, "sector_grouped")
} else {
  panel_b_path <- make_output_path("muni_panel_for_regs.qs2")
  table_dir    <- file.path(TABLES_DIR, "sector")
}
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

# --- Step 1: Load Panel B (muni × year) --------------------------------------

cat("Step 1: Loading muni × year panel (Panel B)...\n")

if (!file.exists(panel_b_path)) {
  stop("Panel B not found: ", panel_b_path, "\n  Run script 41 first.")
}

dt <- qs_read(panel_b_path)
setDT(dt)
cat("  Loaded:", format(nrow(dt), big.mark = ","), "rows,", ncol(dt), "cols\n")

# Check GDP availability
if (!"log_gdp_pc" %in% names(dt) || all(is.na(dt$log_gdp_pc))) {
  stop("GDP per capita not available. Ensure GDP + population data are loaded in script 41.")
}

# Ensure types
dt[, muni_id := as.integer(muni_id)]
dt[, year := as.integer(year)]

# Drop rows without GDP
n0 <- nrow(dt)
dt <- dt[!is.na(log_gdp_pc) & is.finite(log_gdp_pc)]
cat("  Dropped", n0 - nrow(dt), "rows with missing GDP\n")

cat("  Final sample:", format(nrow(dt), big.mark = ","), "obs,",
    uniqueN(dt$muni_id), "munis,",
    uniqueN(dt$year), "years\n")
cat(sprintf("  log_gdp_pc: mean=%.4f, sd=%.4f\n",
            mean(dt$log_gdp_pc), sd(dt$log_gdp_pc)))

# --- Step 2: Identify columns ------------------------------------------------

cat("\nStep 2: Identifying instrument and endogenous columns...\n")

# Sector suffix regex: single letter [A-U] for cnae_section, multi-char for sector_group
SEC_RE <- if (USE_GROUPS) "[A-Za-z]+" else "[A-U]"

# Muni-level instruments (aggregate, changes)
z_muni_cycle <- grep("^dZ_.*_cycle_specific$", names(dt), value = TRUE)
z_muni_fixed <- grep("^dZ_.*_2002_fixed$", names(dt), value = TRUE)

# Sector-level instruments (wide format: dZ_*_cycle_specific_A, etc.)
z_sec_cycle <- grep(paste0("^dZ_.*_cycle_specific_", SEC_RE, "$"), names(dt), value = TRUE)
z_sec_fixed <- grep(paste0("^dZ_.*_2002_fixed_", SEC_RE, "$"), names(dt), value = TRUE)

# Endogenous sector share columns (wide format)
delta_s_cols <- grep(paste0("^delta_s_", SEC_RE, "$"), names(dt), value = TRUE)
s_cols       <- grep(paste0("^s_", SEC_RE, "$"), names(dt), value = TRUE)

cat("  Muni-level instruments (cycle):", paste(z_muni_cycle, collapse = ", "), "\n")
cat("  Muni-level instruments (fixed):", paste(z_muni_fixed, collapse = ", "), "\n")
cat("  Sector instruments (cycle):", length(z_sec_cycle), "cols\n")
cat("  Endogenous delta_s columns:", length(delta_s_cols), "cols\n")
cat("  Endogenous s columns:", length(s_cols), "cols\n")

# Extract sector codes from delta_s columns (single letters for cnae_section, multi-char for sector_group)
sec_letters_all <- gsub("^delta_s_", "", delta_s_cols)

# Drop sparse sectors: require at least MIN_NZ_SEC nonzero obs in the
# cycle-specific mayor instrument.  Sectors like T (5 obs) and U (4 obs) in
# 2002-fixed produce extreme leverage; a threshold of 100 removes them while
# keeping all economically meaningful sectors.
MIN_NZ_SEC <- 100
sparse_secs <- character(0)
for (sl in sec_letters_all) {
  col <- grep(paste0("^Z_mayor_.*_cycle_specific_", sl, "$"), names(dt), value = TRUE)[1]
  if (!is.null(col) && !is.na(col)) {
    nz <- sum(dt[[col]] != 0, na.rm = TRUE)
    if (nz < MIN_NZ_SEC) sparse_secs <- c(sparse_secs, sl)
  }
}
sec_letters <- setdiff(sec_letters_all, sparse_secs)
if (length(sparse_secs) > 0) {
  cat(sprintf("  Dropped %d sparse sector(s) (<%d nonzero instrument obs): %s\n",
              length(sparse_secs), MIN_NZ_SEC, paste(sparse_secs, collapse = ", ")))
}

# Update delta_s and s columns to match non-sparse sectors
delta_s_cols <- paste0("delta_s_", sec_letters)
s_cols <- paste0("s_", sec_letters)

cat("  Sectors (J-1):", paste(sec_letters, collapse = ", "), "\n\n")

# --- Helpers -----------------------------------------------------------------

etable_defaults <- list(
  digits = 4, se.below = TRUE,
  signif.code = c("***" = 0.01, "**" = 0.05, "*" = 0.10),
  fitstat = ~ n + r2
)

etable_iv_defaults <- list(
  digits = 4, se.below = TRUE,
  signif.code = c("***" = 0.01, "**" = 0.05, "*" = 0.10),
  fitstat = ~ n + r2 + ivf + sargan
)

# Build dict for sector-specific instruments and endogenous vars
.build_tex_dict <- function() {
  d <- c(
    "log_gdp_pc" = "$\\ln(\\text{GDP}_{pc})$",
    "log_transfers_pc" = "$\\ln(\\text{Transfers}_{pc})$",
    "bndes_pc"   = "$\\text{BNDES}_{pc}$",
    "delta_hhi"  = "$\\Delta\\text{HHI}$"
  )
  # Sector-specific delta_s and Z columns
  # Use actual sector codes found in the data (works for both cnae_section and sector_group)
  all_sec_codes <- if (length(sec_letters_all) > 0) sec_letters_all else LETTERS[1:21]
  for (sl in all_sec_codes) {
    d[paste0("delta_s_", sl)]  <- paste0("$\\Delta s_", sl, "$")
    d[paste0("s_", sl)]        <- paste0("$s_", sl, "$")
    for (tier in c("mayor", "gov", "pres")) {
      tlab <- switch(tier, mayor = "M", gov = "G", pres = "P")
      for (base in c("cycle_specific", "2002_fixed")) {
        bsfx <- if (base == "2002_fixed") ",fix" else ""
        orig <- paste0("dZ_", tier, "_coalition_", base, "_", sl)
        d[orig] <- paste0("$\\Delta Z^{", tlab, bsfx, "}_", sl, "$")
        orig_p <- paste0("dZ_", tier, "_party_", base, "_", sl)
        d[orig_p] <- paste0("$\\Delta Z^{", tlab, ",p", bsfx, "}_", sl, "$")
      }
    }
  }
  # Muni-level instruments (changes)
  for (tier in c("mayor", "gov", "pres")) {
    tlab <- switch(tier, mayor = "M", gov = "G", pres = "P")
    for (align in c("coalition", "party")) {
      asfx <- if (align == "party") ",p" else ""
      for (base in c("cycle_specific", "2002_fixed")) {
        bsfx <- if (base == "2002_fixed") ",fix" else ""
        orig <- paste0("dZ_", tier, "_", align, "_", base)
        d[orig] <- paste0("$\\Delta Z^{\\text{", tlab, "}", asfx, bsfx, "}$")
      }
    }
  }
  d
}

etable_tex_extras <- list(
  style.tex = style.tex("aer"),
  dict = .build_tex_dict(),
  fixef.group = list(
    "Municipality FE" = "^muni_id$",
    "Year FE"         = "^year$"
  ),
  notes = "Clustered (municipality) standard errors in parentheses. $^{***}p<0.01$, $^{**}p<0.05$, $^{*}p<0.10$."
)

print_table <- function(mods, header, iv = FALSE) {
  if (length(mods) == 0) return(invisible(NULL))
  cat("\n", header, "\n", sep = "")
  defaults <- if (iv) etable_iv_defaults else etable_defaults
  tbl <- do.call(fixest::etable, c(mods, defaults))
  lines <- capture.output(print(tbl))
  cat(paste(lines, collapse = "\n"), "\n")
}

print_wald <- function(mods, pattern = "^(dZ_|Z_)", header = "Joint Wald test") {
  cat(sprintf("\n  %s (H0: all coefficients on %s = 0):\n", header, pattern))
  for (nm in names(mods)) {
    wt <- tryCatch({
      fixest::wald(mods[[nm]], keep = pattern)
    }, error = function(e) NULL)
    if (!is.null(wt)) {
      cat(sprintf("    %s: F=%.3f, p=%.4f\n", nm, wt$stat, wt$p))
    } else {
      cat(sprintf("    %s: Wald test failed\n", nm))
    }
  }
}

save_table <- function(mods, filename, header, iv = FALSE) {
  if (length(mods) == 0) return(invisible(NULL))
  defaults <- if (iv) etable_iv_defaults else etable_defaults
  tbl <- do.call(fixest::etable, c(mods, defaults))

  md_lines <- capture.output(print(tbl, markdown = TRUE))
  md_path <- file.path(table_dir, paste0(filename, ".md"))
  writeLines(c(paste0("# ", header), "", md_lines), md_path)

  tex_lines <- do.call(fixest::etable, c(mods, defaults, etable_tex_extras,
                                          list(tex = TRUE)))
  tex_path <- file.path(table_dir, paste0(filename, ".tex"))
  writeLines(tex_lines, tex_path)

  cat(sprintf("  Saved: %s (.md + .tex)\n", filename))
}

#' Save a compact Wald-test summary table as LaTeX (for beamer slides)
save_wald_summary <- function(mods, filename, header, pattern = "^(dZ_|Z_)") {
  if (length(mods) == 0) return(invisible(NULL))
  rows <- list()
  for (nm in names(mods)) {
    wt <- tryCatch(fixest::wald(mods[[nm]], keep = pattern), error = function(e) NULL)
    n <- tryCatch(nobs(mods[[nm]]), error = function(e) NA)
    r2 <- tryCatch(fixest::r2(mods[[nm]], "r2"), error = function(e) NA)
    if (!is.null(wt)) {
      rows[[nm]] <- data.frame(
        Spec = nm, N = n, R2 = r2,
        F_stat = wt$stat, p_value = wt$p,
        df1 = wt$df1, df2 = wt$df2,
        stringsAsFactors = FALSE)
    }
  }
  if (length(rows) == 0) return(invisible(NULL))
  df <- do.call(rbind, rows)

  # Build LaTeX tabular
  ncols <- "lrrrrr"
  tex <- character()
  tex <- c(tex, "\\begingroup", "\\centering",
           sprintf("\\begin{tabular}{%s}", ncols),
           "\\toprule",
           "Specification & $N$ & $R^2$ & IVs & Wald $F$ & $p$-value \\\\",
           "\\midrule")
  for (i in seq_len(nrow(df))) {
    pstr <- if (df$p_value[i] < 0.0001) {
      sprintf("$< 10^{-4}$")
    } else {
      sprintf("%.4f", df$p_value[i])
    }
    tex <- c(tex, sprintf("%s & %s & %.4f & %d & %.2f & %s \\\\",
                          gsub("_", "\\\\_", df$Spec[i]),
                          format(df$N[i], big.mark = ","),
                          df$R2[i], df$df1[i], df$F_stat[i], pstr))
  }
  tex <- c(tex, "\\bottomrule", "\\end{tabular}", "\\par\\endgroup")

  tex_path <- file.path(table_dir, paste0(filename, ".tex"))
  writeLines(tex, tex_path)
  cat(sprintf("  Saved Wald summary: %s.tex\n", filename))
}

# --- Instrument selection helper ----------------------------------------------

#' Pick muni-level instruments for a given alignment type and tier(s)
#' @param z_cols_set Character vector of available Z column names
#' @param align "coalition" or "party"
#' @param tiers Character vector of tiers to include, e.g. c("mayor", "gov", "pres")
#' @return Named character vector of matching instrument column names (NAs dropped)
pick_z_muni <- function(z_cols_set, align, tiers = c("mayor", "gov", "pres")) {
  out <- vapply(tiers, function(tier) {
    grep(paste0("dZ_", tier, "_", align), z_cols_set, value = TRUE)[1]
  }, character(1))
  out <- out[!is.na(out) & out %in% names(dt)]
  out
}

#' Pick sector-level instruments (wide format) for a given alignment type and tier(s)
#' @param z_sec_set Character vector of available sector-level Z column names
#' @param align "coalition" or "party"
#' @param tiers Character vector of tiers to include
#' @param sec_letters Character vector of sector letters to include
#' @return Character vector of matching instrument column names
pick_z_sec <- function(z_sec_set, align, tiers = c("mayor", "gov", "pres"),
                       sec_letters_use = sec_letters) {
  out <- character(0)
  for (sl in sec_letters_use) {
    for (tier in tiers) {
      z_sl <- grep(paste0("dZ_", tier, "_", align, ".*_", sl, "$"),
                   z_sec_set, value = TRUE)
      out <- c(out, z_sl)
    }
  }
  out[out %in% names(dt)]
}

# ==============================================================================
# Main alignment loop
# ==============================================================================

align_types <- if (ALIGN_TYPE == "both") c("coalition", "party") else ALIGN_TYPE

for (atype in align_types) {
  atag <- paste0("[", atype, "]")
  asfx <- paste0("_", atype)   # file suffix

  cat(sprintf("\n========== Alignment: %s ==========\n", toupper(atype)))

  # ==========================================================================
  # TABLE 4: Reduced Form (muni × year) — sector-specific instruments
  # ==========================================================================

  if ("rf" %in% run_specs) {
    cat("\nStep 3: Running reduced-form regressions (muni × year, sector-specific Z)...\n")

    if (length(z_sec_cycle) > 0) {
      mods_rf <- list()

      z_sec_m  <- pick_z_sec(z_sec_cycle, atype, tiers = "mayor")
      z_sec_mg <- pick_z_sec(z_sec_cycle, atype, tiers = c("mayor", "gov"))

      cat(sprintf("  Mayor sector instruments: %d, M+G sector instruments: %d\n",
                  length(z_sec_m), length(z_sec_mg)))

      # (a) Mayor sector instruments only
      if (length(z_sec_m) > 0) {
        mods_rf[["Mayor"]] <- feols(
          as.formula(paste0("log_gdp_pc ~ ", paste(z_sec_m, collapse = " + "),
                            " | muni_id + year")),
          data = dt, vcov = ~muni_id)
      }

      # (b) Mayor + Governor sector instruments (overidentified)
      if (length(z_sec_mg) > length(z_sec_m)) {
        mods_rf[["M+G"]] <- feols(
          as.formula(paste0("log_gdp_pc ~ ", paste(z_sec_mg, collapse = " + "),
                            " | muni_id + year")),
          data = dt, vcov = ~muni_id)
      }

      # (c) M+G + bndes_pc control (robustness: scale control)
      if (length(z_sec_mg) > length(z_sec_m) && "bndes_pc" %in% names(dt)) {
        mods_rf[["M+G+bndes_pc"]] <- feols(
          as.formula(paste0("log_gdp_pc ~ ", paste(z_sec_mg, collapse = " + "),
                            " + bndes_pc | muni_id + year")),
          data = dt, vcov = ~muni_id)
      }

      # Print only Wald tests to console (full table too wide with ~20+ instruments)
      cat(sprintf("\n  Table 4: Reduced Form — log(GDP_pc) on sector-specific Z [muni×year, cycle-specific, %s]\n", atype))
      cat("  (Full coefficient table saved to file; showing joint Wald tests only)\n")
      print_wald(mods_rf, pattern = "^dZ_", header = "Optimality test")

      save_table(mods_rf, paste0("ss_reduced_form_t4", asfx),
        sprintf("Reduced Form: log(GDP_pc) on sector-specific Z (muni×year, %s)", atype))
      save_wald_summary(mods_rf, paste0("ss_reduced_form_t4_wald", asfx),
        sprintf("Reduced Form Wald Tests (%s)", atype))
      rm(mods_rf); gc(verbose = FALSE)
    } else {
      cat("  No cycle-specific sector instruments found — skipping Table 4\n")
    }
  }

  # ==========================================================================
  # TABLE 5: Scalar 2SLS (muni × year)
  # ==========================================================================

  if ("scalar" %in% run_specs) {
    cat("\nStep 4: Running scalar 2SLS regressions (muni × year)...\n")

    if (length(z_muni_cycle) > 0 && "delta_hhi" %in% names(dt)) {
      mods_scalar <- list()
      dt_hhi <- dt[!is.na(delta_hhi)]

      z_m <- pick_z_muni(z_muni_cycle, atype, "mayor")
      z_mg <- pick_z_muni(z_muni_cycle, atype, c("mayor", "gov"))

      if (nrow(dt_hhi) > 100) {
        # (a) Just-identified: mayor only
        if (length(z_m) > 0) {
          z_str_m <- paste(z_m, collapse = " + ")
          tryCatch({
            mods_scalar[["IV:Mayor"]] <- feols(
              as.formula(paste0("log_gdp_pc ~ 1 | muni_id + year | delta_hhi ~ ", z_str_m)),
              data = dt_hhi, vcov = ~muni_id)
          }, error = function(e) cat("  WARNING: Scalar 2SLS (mayor) failed:", conditionMessage(e), "\n"))
        }

        # (b) Overidentified: mayor + governor
        if (length(z_mg) == 2) {
          z_str_mg <- paste(z_mg, collapse = " + ")
          tryCatch({
            mods_scalar[["IV:M+G"]] <- feols(
              as.formula(paste0("log_gdp_pc ~ 1 | muni_id + year | delta_hhi ~ ", z_str_mg)),
              data = dt_hhi, vcov = ~muni_id)
          }, error = function(e) cat("  WARNING: Scalar 2SLS (M+G) failed:", conditionMessage(e), "\n"))
        }

        # (c) Overidentified + bndes_pc control (robustness)
        if (length(z_mg) == 2 && "bndes_pc" %in% names(dt)) {
          z_str_mg <- paste(z_mg, collapse = " + ")
          tryCatch({
            mods_scalar[["IV:M+G+bndes_pc"]] <- feols(
              as.formula(paste0("log_gdp_pc ~ bndes_pc | muni_id + year | delta_hhi ~ ", z_str_mg)),
              data = dt_hhi, vcov = ~muni_id)
          }, error = function(e) cat("  WARNING: Scalar 2SLS (M+G+bndes_pc) failed:", conditionMessage(e), "\n"))
        }
      }

      if (length(mods_scalar) > 0) {
        print_table(mods_scalar,
          sprintf("Table 5: Scalar 2SLS — log(GDP_pc) ~ delta_hhi [muni×year, %s]", atype), iv = TRUE)
        save_table(mods_scalar, paste0("ss_scalar_2sls_t5", asfx),
          sprintf("Scalar 2SLS (muni×year, %s)", atype), iv = TRUE)
      } else {
        cat("  No scalar 2SLS models could be estimated\n")
      }
      rm(dt_hhi, mods_scalar); gc(verbose = FALSE)
    } else {
      cat("  Missing delta_hhi or instruments — skipping Table 5\n")
    }
  }

  # ==========================================================================
  # TABLE 6: Vector 2SLS (muni × year, J-1 endogenous regressors)
  # ==========================================================================

  if ("vector" %in% run_specs) {
    cat("\nStep 5: Running vector 2SLS regressions (muni × year)...\n")

    if (length(delta_s_cols) > 0 && length(z_sec_cycle) > 0) {
      endo_str <- paste(delta_s_cols, collapse = " + ")

      # (a) Mayor-only sector instruments (just-identified)
      z_sec_m <- pick_z_sec(z_sec_cycle, atype, tiers = "mayor")
      # (b) Mayor + Governor sector instruments (overidentified)
      z_sec_mg <- pick_z_sec(z_sec_cycle, atype, tiers = c("mayor", "gov"))

      cat(sprintf("  Endogenous regressors: %d (delta_s columns)\n", length(delta_s_cols)))
      cat(sprintf("  Mayor instruments: %d, M+G instruments: %d\n",
                  length(z_sec_m), length(z_sec_mg)))

      mods_vec <- list()

      # 6a: Mayor-only (just-identified)
      if (length(z_sec_m) >= length(delta_s_cols)) {
        iv_str_m <- paste(z_sec_m, collapse = " + ")
        complete_rows <- complete.cases(dt[, c("log_gdp_pc", delta_s_cols, z_sec_m), with = FALSE])
        cat(sprintf("  6a complete obs (mayor): %d / %d\n", sum(complete_rows), nrow(dt)))

        if (sum(complete_rows) > length(z_sec_m) + 100) {
          tryCatch({
            mods_vec[["Vec:Mayor"]] <- feols(
              as.formula(paste0("log_gdp_pc ~ 1 | muni_id + year | ",
                                endo_str, " ~ ", iv_str_m)),
              data = dt, vcov = ~muni_id)
          }, error = function(e) {
            cat("  WARNING: Vector 2SLS (mayor) failed:", conditionMessage(e), "\n")
          })
        }
      }

      # 6b: Mayor + Governor (overidentified, enables Sargan test)
      if (length(z_sec_mg) >= length(delta_s_cols)) {
        iv_str_mg <- paste(z_sec_mg, collapse = " + ")
        complete_rows <- complete.cases(dt[, c("log_gdp_pc", delta_s_cols, z_sec_mg), with = FALSE])
        cat(sprintf("  6b complete obs (M+G): %d / %d\n", sum(complete_rows), nrow(dt)))

        if (sum(complete_rows) > length(z_sec_mg) + 100) {
          tryCatch({
            mods_vec[["Vec:M+G"]] <- feols(
              as.formula(paste0("log_gdp_pc ~ 1 | muni_id + year | ",
                                endo_str, " ~ ", iv_str_mg)),
              data = dt, vcov = ~muni_id)
          }, error = function(e) {
            cat("  WARNING: Vector 2SLS (M+G) failed:", conditionMessage(e), "\n")
          })
        }
      }

      # 6c: M+G + bndes_pc control (robustness)
      if (length(z_sec_mg) >= length(delta_s_cols) && "bndes_pc" %in% names(dt)) {
        iv_str_mg <- paste(z_sec_mg, collapse = " + ")
        tryCatch({
          mods_vec[["Vec:M+G+bndes_pc"]] <- feols(
            as.formula(paste0("log_gdp_pc ~ bndes_pc | muni_id + year | ",
                              endo_str, " ~ ", iv_str_mg)),
            data = dt, vcov = ~muni_id)
        }, error = function(e) {
          cat("  WARNING: Vector 2SLS (M+G+bndes_pc) failed:", conditionMessage(e), "\n")
        })
      }

      if (length(mods_vec) > 0) {
        print_table(mods_vec,
          sprintf("Table 6: Vector 2SLS — log(GDP_pc) ~ delta_s_j [muni×year, %s]", atype), iv = TRUE)

        # Joint Wald test on all delta_s coefficients (optimality null)
        cat("\n  Optimality null (H0: all beta_j = 0):\n")
        for (nm in names(mods_vec)) {
          wt <- tryCatch({
            fixest::wald(mods_vec[[nm]], keep = "^(fit_)?delta_s_")
          }, error = function(e) NULL)
          if (!is.null(wt)) {
            cat(sprintf("    %s: F=%.3f, p=%.4f\n", nm, wt$stat, wt$p))
          } else {
            cat(sprintf("    %s: Wald test failed\n", nm))
          }
        }

        # Print sector-specific coefficients
        cat("\n  Sector-specific coefficients (policy interpretation):\n")
        for (nm in names(mods_vec)) {
          cat(sprintf("    --- %s ---\n", nm))
          coefs <- coef(mods_vec[[nm]])
          ses   <- se(mods_vec[[nm]])
          ds_coefs <- grep("^(fit_)?delta_s_", names(coefs), value = TRUE)
          for (cc in ds_coefs) {
            sig <- ""
            pval <- 2 * pnorm(-abs(coefs[cc] / ses[cc]))
            if (pval < 0.01) sig <- "***"
            else if (pval < 0.05) sig <- "**"
            else if (pval < 0.10) sig <- "*"
            cat(sprintf("      %s: %.4f (%.4f) %s\n", cc, coefs[cc], ses[cc], sig))
          }
        }

        save_table(mods_vec, paste0("ss_vector_2sls_t6", asfx),
          sprintf("Vector 2SLS: log(GDP_pc) ~ delta_s_j (muni×year, %s)", atype), iv = TRUE)
      } else {
        cat("  No vector 2SLS models could be estimated\n")
      }
      rm(mods_vec); gc(verbose = FALSE)
    } else {
      cat("  No wide-format sector columns found — skipping Table 6\n")
      cat("  (Ensure script 41 built wide Panel B with sector columns)\n")
    }
  }

  # ==========================================================================
  # TABLE 7: Robustness
  # ==========================================================================

  if ("robust" %in% run_specs) {
    cat("\nStep 6: Running robustness checks...\n")
    rob_wald_mods <- list()  # collect for combined summary

    # 7a: 2002-fixed baseline (reduced form, sector-specific instruments)
    if (length(z_sec_fixed) > 0) {
      cat("  7a: 2002-fixed baseline reduced form (sector-specific Z)...\n")

      z_fixed_sec_mg <- pick_z_sec(z_sec_fixed, atype, tiers = c("mayor", "gov"))

      if (length(z_fixed_sec_mg) > 0) {
        mods_rob_a <- list()
        mods_rob_a[["RF:Fixed"]] <- feols(
          as.formula(paste0("log_gdp_pc ~ ", paste(z_fixed_sec_mg, collapse = " + "),
                            " | muni_id + year")),
          data = dt, vcov = ~muni_id)

        cat("  (Full coefficient table saved to file; showing joint Wald test only)\n")
        print_wald(mods_rob_a, "^dZ_", "Optimality test (2002-fixed)")
        save_table(mods_rob_a, paste0("ss_robustness_t7a_fixed_rf", asfx),
          sprintf("Reduced Form (2002-fixed, sector-specific Z, %s)", atype))
        rob_wald_mods[["2002-fixed baseline"]] <- mods_rob_a[[1]]
        rm(mods_rob_a); gc(verbose = FALSE)
      }
    }

    # 7b: Trimmed sample (drop top/bottom 1% GDP_pc, sector-specific instruments)
    if (length(z_sec_cycle) > 0) {
      cat("  7b: Trimmed sample (dropping top/bottom 1% GDP_pc, sector-specific Z)...\n")
      gdp_q <- quantile(dt$log_gdp_pc, c(0.01, 0.99), na.rm = TRUE)
      dt_trim <- dt[log_gdp_pc >= gdp_q[1] & log_gdp_pc <= gdp_q[2]]
      cat(sprintf("    Trimmed: %s -> %s rows\n",
                  format(nrow(dt), big.mark = ","),
                  format(nrow(dt_trim), big.mark = ",")))

      z_trim_sec <- pick_z_sec(z_sec_cycle, atype, tiers = c("mayor", "gov"))

      if (length(z_trim_sec) > 0) {
        mods_rob_b <- list()
        mods_rob_b[["RF:Trimmed"]] <- feols(
          as.formula(paste0("log_gdp_pc ~ ", paste(z_trim_sec, collapse = " + "),
                            " | muni_id + year")),
          data = dt_trim, vcov = ~muni_id)

        cat("  (Full coefficient table saved to file; showing joint Wald test only)\n")
        print_wald(mods_rob_b, "^dZ_", "Optimality test (trimmed)")
        save_table(mods_rob_b, paste0("ss_robustness_t7b_trimmed_rf", asfx),
          sprintf("Reduced Form (trimmed, sector-specific Z, %s)", atype))
        rob_wald_mods[["Trimmed 1--99\\%"]] <- mods_rob_b[[1]]
        rm(mods_rob_b)
      }
      rm(dt_trim); gc(verbose = FALSE)
    }

    # 7c: Alternative clustering (sector-specific instruments)
    if (length(z_sec_cycle) > 0) {
      cat("  7c: Alternative clustering (sector-specific Z)...\n")

      z_clust_sec <- pick_z_sec(z_sec_cycle, atype, tiers = c("mayor", "gov"))
      if (length(z_clust_sec) > 0) {
        fml <- as.formula(paste0("log_gdp_pc ~ ", paste(z_clust_sec, collapse = " + "),
                                 " | muni_id + year"))

        mods_rob_c <- list()
        mods_rob_c[["cluster:muni"]] <- feols(fml, data = dt, vcov = ~muni_id)
        mods_rob_c[["cluster:muni+year"]] <- feols(fml, data = dt, vcov = ~muni_id + year)
        if ("state_id" %in% names(dt)) {
          mods_rob_c[["cluster:state"]] <- feols(fml, data = dt, vcov = ~state_id)
        }

        cat("  (Full coefficient table saved to file; showing joint Wald tests only)\n")
        print_wald(mods_rob_c, "^dZ_", "Optimality test (alt clustering)")
        save_table(mods_rob_c, paste0("ss_robustness_t7c_clustering", asfx),
          sprintf("Reduced Form (alternative clustering, sector-specific Z, %s)", atype))
        rob_wald_mods[["Cluster: muni+year"]] <- mods_rob_c[["cluster:muni+year"]]
        rm(mods_rob_c); gc(verbose = FALSE)
      }
    }

    # 7d: OLS benchmark (uninstrumented) — for comparison
    if (length(delta_s_cols) > 0) {
      cat("  7d: OLS benchmark (uninstrumented)...\n")

      mods_ols <- list()
      tryCatch({
        mods_ols[["OLS"]] <- feols(
          as.formula(paste0("log_gdp_pc ~ ", paste(delta_s_cols, collapse = " + "),
                            " | muni_id + year")),
          data = dt, vcov = ~muni_id)
      }, error = function(e) {
        cat("  WARNING: OLS failed:", conditionMessage(e), "\n")
      })

      if ("bndes_pc" %in% names(dt)) {
        tryCatch({
          mods_ols[["OLS+bndes_pc"]] <- feols(
            as.formula(paste0("log_gdp_pc ~ ", paste(delta_s_cols, collapse = " + "),
                              " + bndes_pc | muni_id + year")),
            data = dt, vcov = ~muni_id)
        }, error = function(e) {
          cat("  WARNING: OLS+bndes_pc failed:", conditionMessage(e), "\n")
        })
      }

      if (length(mods_ols) > 0) {
        print_table(mods_ols,
          sprintf("Table 7d: OLS Benchmark (uninstrumented) [%s]", atype))
        save_table(mods_ols, paste0("ss_robustness_t7d_ols", asfx),
          sprintf("OLS Benchmark (uninstrumented, %s)", atype))
      }
      rm(mods_ols); gc(verbose = FALSE)
    }

    # 7e: Transfer placebo (sector-specific instruments — exclusion restriction)
    # If sector-specific Z isolates the BNDES composition channel, these same
    # sector Z's should NOT predict transfers (which flow through other channels).
    if ("log_transfers_pc" %in% names(dt) && length(z_sec_cycle) > 0) {
      cat("  7e: Transfer placebo (exclusion restriction, sector-specific Z)...\n")

      dt_trans <- dt[!is.na(log_transfers_pc) & is.finite(log_transfers_pc)]
      if (nrow(dt_trans) > 100) {
        z_placebo_sec <- pick_z_sec(z_sec_cycle, atype, tiers = c("mayor", "gov"))

        if (length(z_placebo_sec) > 0) {
          mods_placebo <- list()
          mods_placebo[["Transfers"]] <- feols(
            as.formula(paste0("log_transfers_pc ~ ", paste(z_placebo_sec, collapse = " + "),
                              " | muni_id + year")),
            data = dt_trans, vcov = ~muni_id)

          cat("  (Full coefficient table saved to file; showing joint Wald test only)\n")
          print_wald(mods_placebo, "^dZ_", "Exclusion restriction test")
          save_table(mods_placebo, paste0("ss_robustness_t7e_placebo", asfx),
            sprintf("Transfer Placebo (sector-specific Z, %s)", atype))
          rm(mods_placebo)
        }
      } else {
        cat("  Insufficient transfer data for placebo test\n")
      }
      rm(dt_trans); gc(verbose = FALSE)
    } else {
      cat("  7e: Transfer data not available — skipping placebo test\n")
    }

    # Save combined robustness Wald summary table
    if (length(rob_wald_mods) > 0) {
      save_wald_summary(rob_wald_mods, paste0("ss_robustness_wald_summary", asfx),
        sprintf("Robustness Wald Tests (%s)", atype))
    }
    rm(rob_wald_mods); gc(verbose = FALSE)
  }

} # end align_types loop

# === Summary =================================================================

cat("\n==============================================================================\n")
cat("Second-stage regressions complete.\n")
cat("Tables saved to:", table_dir, "\n")
cat("\nInterpretation guide:\n")
cat("  Table 4 (Reduced form): sector-specific instruments Z_rjt on GDP_pc\n")
cat("    (a) Mayor sector Z only, (b) M+G sector Z, (c) M+G+bndes_pc [robustness]\n")
cat("    Joint Wald test: H0 optimality — all pi_j = 0\n")
cat("  Table 5 (Scalar 2SLS): tests concentration effect of political reallocation\n")
cat("    (a) Mayor just-identified, (b) M+G overidentified, (c) M+G+bndes_pc [robustness]\n")
cat("  Table 6 (Vector 2SLS): sector-specific beta_j\n")
cat("    (a) Mayor just-identified, (b) M+G overidentified, (c) M+G+bndes_pc [robustness]\n")
cat("    Joint Wald: H0 all beta_j = 0 → allocation is optimal\n")
cat("    Significant beta_j → sector j is over/under-funded relative to dropped sector\n")
cat("  Table 7 (Robustness): 2002-fixed, trimmed, alt clustering, OLS, placebo\n")
cat("    (all reduced-form robustness tables use sector-specific instruments)\n")
cat("==============================================================================\n")
