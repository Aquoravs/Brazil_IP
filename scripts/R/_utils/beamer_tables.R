# Beamer-quality regression table export via direct fixest extraction
# Source this from estimation scripts after utils.R:
#   source("_utils/beamer_tables.R")
#
# Requires: fixest

# --- Preset coefficient label maps -------------------------------------------

.build_sector_variant_coef_map <- function() {
  weight_prefixes <- c(emp = "emp", firm = "firm", binary = "binary")
  out <- character(0)

  for (weight_key in names(weight_prefixes)) {
    prefix <- weight_prefixes[[weight_key]]
    for (baseline in c("cycle_specific", "2002_fixed")) {
      for (align in c("coalition", "party")) {
        align_lbl <- if (identical(align, "coalition")) "coal." else "party"
        for (tier in c("mayor", "gov", "pres")) {
          out[paste0("dZ_", prefix, "_", tier, "_", align, "_", baseline)] <-
            paste0("$\\Delta Z^{\\text{", tier, "}}_{\\text{", align_lbl, "}}$")
          out[paste0("Z_", prefix, "_", tier, "_", align, "_", baseline)] <-
            paste0("$Z^{\\text{", tier, "}}_{\\text{", align_lbl, "}}$")
        }
      }
    }
  }

  out
}

COEF_MAP_INSTRUMENTS <- c(
  # Changes instruments (dZ): coalition, cycle-specific
  "dZ_mayor_coalition_cycle_specific"  = "$\\Delta Z^{\\text{mayor}}_{\\text{coal.}}$",
  "dZ_gov_coalition_cycle_specific"    = "$\\Delta Z^{\\text{gov}}_{\\text{coal.}}$",
  "dZ_pres_coalition_cycle_specific"   = "$\\Delta Z^{\\text{pres}}_{\\text{coal.}}$",
  # Changes instruments (dZ): party, cycle-specific
  "dZ_mayor_party_cycle_specific"      = "$\\Delta Z^{\\text{mayor}}_{\\text{party}}$",
  "dZ_gov_party_cycle_specific"        = "$\\Delta Z^{\\text{gov}}_{\\text{party}}$",
  "dZ_pres_party_cycle_specific"       = "$\\Delta Z^{\\text{pres}}_{\\text{party}}$",
  # Changes instruments (dZ): coalition, 2002-fixed
  "dZ_mayor_coalition_2002_fixed"      = "$\\Delta Z^{\\text{mayor}}_{\\text{coal.}}$",
  "dZ_gov_coalition_2002_fixed"        = "$\\Delta Z^{\\text{gov}}_{\\text{coal.}}$",
  "dZ_pres_coalition_2002_fixed"       = "$\\Delta Z^{\\text{pres}}_{\\text{coal.}}$",
  # Changes instruments (dZ): party, 2002-fixed
  "dZ_mayor_party_2002_fixed"          = "$\\Delta Z^{\\text{mayor}}_{\\text{party}}$",
  "dZ_gov_party_2002_fixed"            = "$\\Delta Z^{\\text{gov}}_{\\text{party}}$",
  "dZ_pres_party_2002_fixed"           = "$\\Delta Z^{\\text{pres}}_{\\text{party}}$",
  # Levels instruments (Z): coalition, cycle-specific
  "Z_mayor_coalition_cycle_specific"   = "$Z^{\\text{mayor}}_{\\text{coal.}}$",
  "Z_gov_coalition_cycle_specific"     = "$Z^{\\text{gov}}_{\\text{coal.}}$",
  "Z_pres_coalition_cycle_specific"    = "$Z^{\\text{pres}}_{\\text{coal.}}$",
  # Levels instruments (Z): party, cycle-specific
  "Z_mayor_party_cycle_specific"       = "$Z^{\\text{mayor}}_{\\text{party}}$",
  "Z_gov_party_cycle_specific"         = "$Z^{\\text{gov}}_{\\text{party}}$",
  "Z_pres_party_cycle_specific"        = "$Z^{\\text{pres}}_{\\text{party}}$",
  # Exposure controls
  "exposure_control_cycle_specific"     = "Exposure control",
  "exposure_control_2002_fixed"         = "Exposure control (2002)",
  # Firm-level instruments: levels (FA)
  "FA_mayor_coalition"  = "$FA^{\\text{mayor}}_{\\text{coal.}}$",
  "FA_gov_coalition"    = "$FA^{\\text{gov}}_{\\text{coal.}}$",
  "FA_pres_coalition"   = "$FA^{\\text{pres}}_{\\text{coal.}}$",
  "FA_mayor_party"      = "$FA^{\\text{mayor}}_{\\text{party}}$",
  "FA_gov_party"        = "$FA^{\\text{gov}}_{\\text{party}}$",
  "FA_pres_party"       = "$FA^{\\text{pres}}_{\\text{party}}$",
  # Firm-level instruments: changes (dFA)
  "dFA_mayor_coalition" = "$\\Delta FA^{\\text{mayor}}_{\\text{coal.}}$",
  "dFA_gov_coalition"   = "$\\Delta FA^{\\text{gov}}_{\\text{coal.}}$",
  "dFA_pres_coalition"  = "$\\Delta FA^{\\text{pres}}_{\\text{coal.}}$",
  "dFA_mayor_party"     = "$\\Delta FA^{\\text{mayor}}_{\\text{party}}$",
  "dFA_gov_party"       = "$\\Delta FA^{\\text{gov}}_{\\text{party}}$",
  "dFA_pres_party"      = "$\\Delta FA^{\\text{pres}}_{\\text{party}}$",
  # Firm-level instruments: interaction levels (FA)
  "FA_mayor_gov_coalition"       = "$FA^{\\text{M} \\times \\text{G}}_{\\text{coal.}}$",
  "FA_mayor_gov_party"           = "$FA^{\\text{M} \\times \\text{G}}_{\\text{party}}$",
  "FA_mayor_gov_only_coalition"  = "$FA^{\\text{M} \\times \\text{G only}}_{\\text{coal.}}$",
  "FA_mayor_gov_only_party"      = "$FA^{\\text{M} \\times \\text{G only}}_{\\text{party}}$",
  "FA_mayor_pres_coalition"      = "$FA^{\\text{M} \\times \\text{P}}_{\\text{coal.}}$",
  "FA_mayor_pres_party"          = "$FA^{\\text{M} \\times \\text{P}}_{\\text{party}}$",
  "FA_mayor_pres_only_coalition" = "$FA^{\\text{M} \\times \\text{P only}}_{\\text{coal.}}$",
  "FA_mayor_pres_only_party"     = "$FA^{\\text{M} \\times \\text{P only}}_{\\text{party}}$",
  "FA_triple_coalition"          = "$FA^{\\text{M} \\times \\text{G} \\times \\text{P}}_{\\text{coal.}}$",
  "FA_triple_party"              = "$FA^{\\text{M} \\times \\text{G} \\times \\text{P}}_{\\text{party}}$",
  # Firm-level instruments: interaction changes (dFA)
  "dFA_mayor_gov_coalition"       = "$\\Delta FA^{\\text{M} \\times \\text{G}}_{\\text{coal.}}$",
  "dFA_mayor_gov_party"           = "$\\Delta FA^{\\text{M} \\times \\text{G}}_{\\text{party}}$",
  "dFA_mayor_gov_only_coalition"  = "$\\Delta FA^{\\text{M} \\times \\text{G only}}_{\\text{coal.}}$",
  "dFA_mayor_gov_only_party"      = "$\\Delta FA^{\\text{M} \\times \\text{G only}}_{\\text{party}}$",
  "dFA_mayor_pres_coalition"      = "$\\Delta FA^{\\text{M} \\times \\text{P}}_{\\text{coal.}}$",
  "dFA_mayor_pres_party"          = "$\\Delta FA^{\\text{M} \\times \\text{P}}_{\\text{party}}$",
  "dFA_mayor_pres_only_coalition" = "$\\Delta FA^{\\text{M} \\times \\text{P only}}_{\\text{coal.}}$",
  "dFA_mayor_pres_only_party"     = "$\\Delta FA^{\\text{M} \\times \\text{P only}}_{\\text{party}}$",
  "dFA_triple_coalition"          = "$\\Delta FA^{\\text{M} \\times \\text{G} \\times \\text{P}}_{\\text{coal.}}$",
  "dFA_triple_party"              = "$\\Delta FA^{\\text{M} \\times \\text{G} \\times \\text{P}}_{\\text{party}}$",
  # Aggregated firm→sector instruments (FA_bar)
  "FA_bar_mayor_coalition" = "$\\overline{FA}^{\\text{mayor}}_{\\text{coal.}}$",
  "FA_bar_gov_coalition"   = "$\\overline{FA}^{\\text{gov}}_{\\text{coal.}}$",
  "FA_bar_pres_coalition"  = "$\\overline{FA}^{\\text{pres}}_{\\text{coal.}}$",
  "FA_bar_mayor_party"     = "$\\overline{FA}^{\\text{mayor}}_{\\text{party}}$",
  "FA_bar_gov_party"       = "$\\overline{FA}^{\\text{gov}}_{\\text{party}}$",
  "FA_bar_pres_party"      = "$\\overline{FA}^{\\text{pres}}_{\\text{party}}$",
  "FA_bar_binary_mayor_coalition" = "$\\bar{\\widetilde{FA}}^{\\text{mayor}}_{\\text{coal.}}$",
  "FA_bar_binary_gov_coalition"   = "$\\bar{\\widetilde{FA}}^{\\text{gov}}_{\\text{coal.}}$",
  "FA_bar_binary_pres_coalition"  = "$\\bar{\\widetilde{FA}}^{\\text{pres}}_{\\text{coal.}}$",
  "FA_bar_binary_mayor_party"     = "$\\bar{\\widetilde{FA}}^{\\text{mayor}}_{\\text{party}}$",
  "FA_bar_binary_gov_party"       = "$\\bar{\\widetilde{FA}}^{\\text{gov}}_{\\text{party}}$",
  "FA_bar_binary_pres_party"      = "$\\bar{\\widetilde{FA}}^{\\text{pres}}_{\\text{party}}$",
  # Binary firm-level instruments: levels (FA_binary)
  "FA_binary_mayor_coalition"  = "$\\widetilde{FA}^{\\text{mayor}}_{\\text{coal.}}$",
  "FA_binary_gov_coalition"    = "$\\widetilde{FA}^{\\text{gov}}_{\\text{coal.}}$",
  "FA_binary_pres_coalition"   = "$\\widetilde{FA}^{\\text{pres}}_{\\text{coal.}}$",
  "FA_binary_mayor_gov_coalition"  = "$\\widetilde{FA}^{\\text{M} \\times \\text{G}}_{\\text{coal.}}$",
  "FA_binary_mayor_pres_coalition" = "$\\widetilde{FA}^{\\text{M} \\times \\text{P}}_{\\text{coal.}}$",
  "FA_binary_triple_coalition"     = "$\\widetilde{FA}^{\\text{M} \\times \\text{G} \\times \\text{P}}_{\\text{coal.}}$",
  "FA_binary_mayor_party"      = "$\\widetilde{FA}^{\\text{mayor}}_{\\text{party}}$",
  "FA_binary_gov_party"        = "$\\widetilde{FA}^{\\text{gov}}_{\\text{party}}$",
  "FA_binary_pres_party"       = "$\\widetilde{FA}^{\\text{pres}}_{\\text{party}}$",
  "FA_binary_mayor_gov_party"  = "$\\widetilde{FA}^{\\text{M} \\times \\text{G}}_{\\text{party}}$",
  "FA_binary_mayor_pres_party" = "$\\widetilde{FA}^{\\text{M} \\times \\text{P}}_{\\text{party}}$",
  "FA_binary_triple_party"     = "$\\widetilde{FA}^{\\text{M} \\times \\text{G} \\times \\text{P}}_{\\text{party}}$",
  # Binary firm-level instruments: changes (dFA_binary)
  "dFA_binary_mayor_coalition" = "$\\Delta\\widetilde{FA}^{\\text{mayor}}_{\\text{coal.}}$",
  "dFA_binary_gov_coalition"   = "$\\Delta\\widetilde{FA}^{\\text{gov}}_{\\text{coal.}}$",
  "dFA_binary_pres_coalition"  = "$\\Delta\\widetilde{FA}^{\\text{pres}}_{\\text{coal.}}$",
  "dFA_binary_mayor_gov_coalition"  = "$\\Delta\\widetilde{FA}^{\\text{M} \\times \\text{G}}_{\\text{coal.}}$",
  "dFA_binary_mayor_pres_coalition" = "$\\Delta\\widetilde{FA}^{\\text{M} \\times \\text{P}}_{\\text{coal.}}$",
  "dFA_binary_triple_coalition"     = "$\\Delta\\widetilde{FA}^{\\text{M} \\times \\text{G} \\times \\text{P}}_{\\text{coal.}}$",
  "dFA_binary_mayor_party"     = "$\\Delta\\widetilde{FA}^{\\text{mayor}}_{\\text{party}}$",
  "dFA_binary_gov_party"       = "$\\Delta\\widetilde{FA}^{\\text{gov}}_{\\text{party}}$",
  "dFA_binary_pres_party"      = "$\\Delta\\widetilde{FA}^{\\text{pres}}_{\\text{party}}$",
  "dFA_binary_mayor_gov_party"  = "$\\Delta\\widetilde{FA}^{\\text{M} \\times \\text{G}}_{\\text{party}}$",
  "dFA_binary_mayor_pres_party" = "$\\Delta\\widetilde{FA}^{\\text{M} \\times \\text{P}}_{\\text{party}}$",
  "dFA_binary_triple_party"     = "$\\Delta\\widetilde{FA}^{\\text{M} \\times \\text{G} \\times \\text{P}}_{\\text{party}}$"
)

COEF_MAP_INSTRUMENTS <- c(COEF_MAP_INSTRUMENTS, .build_sector_variant_coef_map())

# --- Preset FE label maps ----------------------------------------------------

FE_LABELS <- list(
  "muni_id^cnae_section"    = "Muni $\\times$ sector FE",
  "muni_id^sector_group"    = "Muni $\\times$ sector FE",
  "muni_id^bndes_sector"    = "Muni $\\times$ sector FE",
  "muni_id^size_bin_label"  = "Muni $\\times$ size bin FE",
  "muni_id^year"            = "Muni $\\times$ year FE",
  "year"                    = "Year FE",
  "cnae_section^year"       = "Sector $\\times$ year FE",
  "sector_group^year"       = "Sector $\\times$ year FE",
  "bndes_sector^year"       = "Sector $\\times$ year FE",
  "size_bin_label^year"     = "Size bin $\\times$ year FE",
  "firm_id"                 = "Firm FE"
)

F_SUSPICIOUS_THRESHOLD <- 10000

# =============================================================================
# Internal helpers
# =============================================================================

#' Determine FE info: whether constant across models, note text, and row data
.get_fe_info <- function(mods, fe_labels) {
  # Get FE set per model
  fe_per_mod <- lapply(mods, function(m) {
    if (inherits(m, "fixest")) sort(m$fixef_vars) else character(0)
  })

  all_fe <- unique(unlist(fe_per_mod))
  if (length(all_fe) == 0) {
    return(list(constant = TRUE, note_text = "", rows = NULL))
  }

  # Check if all models have the same FE
  fe_sigs <- sapply(fe_per_mod, paste, collapse = "|")
  constant <- length(unique(fe_sigs)) == 1

  # Build display labels
  fe_to_show <- all_fe[all_fe %in% names(fe_labels)]
  if (length(fe_to_show) == 0) {
    labels <- setNames(all_fe, all_fe)
    fe_to_show <- all_fe
  } else {
    labels <- unlist(fe_labels[fe_to_show])
  }

  # Note text (for constant case)
  note_text <- paste(labels, collapse = ", ")
  note_text <- paste0(note_text, ".")

  # Row data (for varying case)
  mod_names <- names(mods)
  rows <- lapply(fe_to_show, function(fe) {
    checks <- sapply(mods, function(m) {
      if (inherits(m, "fixest") && fe %in% m$fixef_vars) "$\\checkmark$" else ""
    })
    setNames(c(labels[[fe]], checks), c("term", mod_names))
  })
  row_df <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)

  list(constant = constant, note_text = note_text, rows = row_df)
}

#' Determine clustering info: whether constant across models and note text
.get_clustering_info <- function(mods) {
  clust_per_mod <- sapply(mods, function(m) {
    if (!inherits(m, "fixest")) return("---")
    vcov_type <- attr(m$cov.scaled, "type")
    if (is.null(vcov_type)) return("---")
    if (grepl("firm_id", vcov_type) && grepl("muni_id", vcov_type)) {
      "firm + muni"
    } else if (grepl("muni_id", vcov_type) && grepl("&", vcov_type)) {
      "muni + sector"
    } else if (grepl("muni_id", vcov_type)) {
      "muni"
    } else if (grepl("Clustered", vcov_type)) {
      gsub("Clustered \\((.+)\\)", "\\1", vcov_type)
    } else {
      "---"
    }
  })

  constant <- length(unique(clust_per_mod)) == 1
  clust_val <- clust_per_mod[1]
  note_text <- if (clust_val != "---") {
    paste0("SEs clustered by ", clust_val, " in parentheses.")
  } else {
    "SEs in parentheses."
  }

  list(constant = constant, note_text = note_text, values = clust_per_mod)
}

.format_fstat_value <- function(f) {
  if (is.na(f)) {
    return("")
  }

  if (!is.finite(f) || f > F_SUSPICIOUS_THRESHOLD) {
    cat(sprintf(
      "WARNING: F-stat = %s - likely near-zero SE artefact\n",
      format(f, scientific = FALSE, trim = TRUE)
    ))
    return("$>$10k")
  }

  if (f >= 10) {
    return(sprintf("\\textbf{%.1f}", f))
  }

  sprintf("%.1f", f)
}

#' Build F-statistic row only (no clustering)
.build_fstat_row_only <- function(mods, mod_names, fstat_keep = NULL) {
  fstats <- sapply(mods, function(m) {
    tryCatch({
      # Use cached Wald stat unconditionally when present (avoids recomputation)
      cached_stat <- attr(m, "politicsregs_wald_stat", exact = TRUE)
      if (!is.null(cached_stat)) {
        f <- cached_stat
      } else {
        keep_pat <- if (!is.null(fstat_keep)) fstat_keep else "^(dZ_|Z_|FA_|dFA_|FA_bar_)"
        wald_obj <- suppressMessages(fixest::wald(m, keep = keep_pat))
        f <- wald_obj$stat
      }
      .format_fstat_value(f)
    }, error = function(e) "")
  })
  if (all(fstats == "")) return(NULL)

  df <- data.frame(term = "$F$-statistic", stringsAsFactors = FALSE)
  for (i in seq_along(mod_names)) {
    df[[mod_names[i]]] <- fstats[i]
  }
  df
}

# =============================================================================
# save_beamer_table()  —  direct fixest extraction, no modelsummary/kableExtra
# =============================================================================

#' Extract coefficient matrix from fixest models
#' Returns list with $coef_rows (formatted coefficient strings with stars)
#' and $se_rows (formatted SEs in parentheses), both n_coefs × n_models matrices.
#' Row order follows coef_map order.
.extract_coef_matrix <- function(mods, coef_map, digits, stars) {
  n_mods <- length(mods)

  # Auto-detect coef_map if NULL
  if (is.null(coef_map)) {
    all_coefs <- unique(unlist(lapply(mods, function(m) names(coef(m)))))
    coef_map <- COEF_MAP_INSTRUMENTS[names(COEF_MAP_INSTRUMENTS) %in% all_coefs]
    if (length(coef_map) == 0) coef_map <- setNames(all_coefs, all_coefs)
  }

  coef_names <- names(coef_map)   # variable names in model
  coef_labels <- unname(coef_map) # display labels
  n_coefs <- length(coef_names)

  # Pre-allocate matrices
  coef_rows <- matrix("", nrow = n_coefs, ncol = n_mods)
  se_rows   <- matrix("", nrow = n_coefs, ncol = n_mods)

  fmt_coef <- paste0("%.", digits, "f")
  fmt_se   <- paste0("(", fmt_coef, ")")

  # Evaluate thresholds from most to least stringent and stop at the first hit.
  # Without the break below, highly significant coefficients get downgraded to
  # a single star because they also satisfy the looser thresholds.
  star_levels <- sort(stars)  # 0.01, 0.05, 0.10

  for (j in seq_len(n_mods)) {
    ct <- fixest::coeftable(mods[[j]])  # matrix: rows=coefficients, cols=Estimate,SE,t/z,p
    mod_coef_names <- rownames(ct)

    for (i in seq_len(n_coefs)) {
      idx <- match(coef_names[i], mod_coef_names)
      if (!is.na(idx)) {
        est <- ct[idx, 1]
        se  <- ct[idx, 2]
        pv  <- ct[idx, ncol(ct)]  # p-value is last column

        # Determine stars
        star_str <- ""
        for (k in seq_along(star_levels)) {
          if (!is.na(pv) && pv < star_levels[k]) {
            star_str <- names(star_levels)[k]
            break
          }
        }

        coef_rows[i, j] <- paste0(sprintf(fmt_coef, est), star_str)
        se_rows[i, j]   <- sprintf(fmt_se, se)
      }
    }
  }

  list(coef_rows = coef_rows, se_rows = se_rows,
       labels = coef_labels, coef_map = coef_map)
}

#' Extract GOF rows (Observations, R²) from fixest models
#' Returns list with $n_obs and $r2, each a character vector of length n_mods.
.extract_gof_rows <- function(mods, digits = 3) {
  n_obs <- sapply(mods, function(m) {
    formatC(stats::nobs(m), format = "d", big.mark = ",")
  })
  r2 <- sapply(mods, function(m) {
    sprintf("%.3f", fixest::r2(m, "r2"))
  })
  list(n_obs = n_obs, r2 = r2)
}

save_beamer_table <- function(
    mods,
    filename,
    coef_map    = NULL,
    fe_labels   = FE_LABELS,
    exposure_control_gof = NULL,
    exposure_control_fstat = NULL,
    add_f_stat  = TRUE,
    fstat_keep  = NULL,
    dep_var     = NULL,
    notes       = NULL,
    font_size   = 8,    # accepted but ignored (v1 was also a no-op after .strip_to_tabular)
    digits      = 3,
    table_dir   = TABLE_DIR,
    stars       = c("*" = 0.10, "**" = 0.05, "***" = 0.01)
) {
  if (length(mods) == 0) return(invisible(NULL))
  stopifnot(is.numeric(digits))

  n_mods    <- length(mods)
  mod_names <- names(mods)

  # Auto-generate column names if missing
  if (is.null(mod_names)) {
    mod_names <- paste0("(", seq_len(n_mods), ")")
    warning("save_beamer_table: model list has no names; using (1), (2), ...")
  }

  # --- Extract data ---
  cm <- .extract_coef_matrix(mods, coef_map, digits, stars)
  gof <- .extract_gof_rows(mods, digits)

  # --- FE info ---
  fe_info      <- .get_fe_info(mods, fe_labels)
  fe_constant  <- fe_info$constant
  fe_note_text <- fe_info$note_text

  # --- Clustering info ---
  clust_info      <- .get_clustering_info(mods)
  clust_constant  <- clust_info$constant
  clust_note_text <- clust_info$note_text

  # --- Build LaTeX lines ---
  lines <- character(0)
  amp <- " & "

  # sbox + tabular header
  align_str <- paste0("l", paste(rep("c", n_mods), collapse = ""))
  lines <- c(lines,
    "\\sbox0{%",
    sprintf("\\begin{tabular}[t]{%s}", align_str),
    "\\toprule"
  )

  # Dep var spanning header
  if (!is.null(dep_var)) {
    lines <- c(lines,
      sprintf("\\multicolumn{1}{c}{\\textbf{ }} & \\multicolumn{%d}{c}{\\textbf{Dep.~var: %s}} \\\\",
              n_mods, dep_var),
      sprintf("\\cmidrule(l{3pt}r{3pt}){2-%d}", n_mods + 1)
    )
  }

  # Column name headers
  header_line <- paste0("  & ", paste(mod_names, collapse = " & "), "\\\\")
  lines <- c(lines, header_line, "\\midrule")

  # Coefficient + SE row pairs
  for (i in seq_len(nrow(cm$coef_rows))) {
    coef_line <- paste0(cm$labels[i], amp, paste(cm$coef_rows[i, ], collapse = amp), "\\\\")
    se_line   <- paste0(" ", amp, paste(cm$se_rows[i, ], collapse = amp), "\\\\")
    lines <- c(lines, coef_line, se_line)
  }

  # Midrule before GOF section
  lines <- c(lines, "\\midrule")

  # FE checkmark rows (only if FE vary across models)
  if (!fe_constant && !is.null(fe_info$rows)) {
    fe_df <- fe_info$rows
    for (r in seq_len(nrow(fe_df))) {
      fe_line <- paste0(fe_df[r, 1], amp, paste(fe_df[r, -1], collapse = amp), "\\\\")
      lines <- c(lines, fe_line)
    }
  }

  # Clustering row (only if clustering varies)
  if (!clust_constant) {
    clust_vals <- sapply(mods, function(m) {
      vcov_type <- attr(m$cov.scaled, "type")
      if (is.null(vcov_type)) return("---")
      if (grepl("firm_id", vcov_type) && grepl("muni_id", vcov_type)) {
        "firm + muni"
      } else if (grepl("muni_id", vcov_type) && grepl("&", vcov_type)) {
        "muni + sector"
      } else if (grepl("muni_id", vcov_type)) {
        "muni"
      } else if (grepl("Clustered", vcov_type)) {
        gsub("Clustered \\((.+)\\)", "\\1", vcov_type)
      } else "---"
    })
    clust_line <- paste0("Clustering", amp, paste(clust_vals, collapse = amp), "\\\\")
    lines <- c(lines, clust_line)
  }

  if (!is.null(exposure_control_gof)) {
    gof_vals <- exposure_control_gof
    if (length(gof_vals) == 1L) {
      gof_vals <- rep(gof_vals, n_mods)
    }
    if (is.logical(gof_vals)) {
      gof_vals <- ifelse(gof_vals, "Yes", "No")
    }
    if (length(gof_vals) != n_mods) {
      stop("`exposure_control_gof` must have length 1 or match the number of models.")
    }
    exp_line <- paste0("Exposure Control", amp, paste(gof_vals, collapse = amp), "\\\\")
    lines <- c(lines, exp_line)
  }

  # F-statistic row
  if (add_f_stat) {
    fstat_row <- .build_fstat_row_only(mods, mod_names, fstat_keep = fstat_keep)
    if (!is.null(fstat_row)) {
      fstat_vals <- as.character(fstat_row[1, -1])
      fstat_line <- paste0("$F$-statistic", amp, paste(fstat_vals, collapse = amp), "\\\\")
      lines <- c(lines, fstat_line)
    }
  }

  if (!is.null(exposure_control_fstat)) {
    ctrl_vals <- exposure_control_fstat
    if (length(ctrl_vals) == 1L) {
      ctrl_vals <- rep(ctrl_vals, n_mods)
    }
    if (length(ctrl_vals) != n_mods) {
      stop("`exposure_control_fstat` must have length 1 or match the number of models.")
    }
    ctrl_vals <- vapply(ctrl_vals, .format_fstat_value, character(1))
    if (any(nzchar(ctrl_vals))) {
      ctrl_line <- paste0("Control $F$-statistic", amp, paste(ctrl_vals, collapse = amp), "\\\\")
      lines <- c(lines, ctrl_line)
    }
  }

  # Observations + R²
  obs_line <- paste0("Observations", amp, paste(gof$n_obs, collapse = amp), "\\\\")
  r2_line  <- paste0("$R^2$", amp, paste(gof$r2, collapse = amp), "\\\\")
  lines <- c(lines, obs_line, r2_line)

  # Close tabular
  lines <- c(lines, "\\bottomrule", "\\end{tabular}", "}%")

  # --- Build footnote text ---
  if (!is.null(notes)) {
    note_text <- notes
  } else {
    note_parts <- character(0)
    if (fe_constant && nzchar(fe_note_text)) {
      note_parts <- c(note_parts, fe_note_text)
    }
    if (clust_constant && nzchar(clust_note_text)) {
      note_parts <- c(note_parts, clust_note_text)
    }
    note_parts <- c(note_parts, "$^{***}p<0.01$, $^{**}p<0.05$, $^{*}p<0.10$.")
    note_text <- paste(note_parts, collapse = " ")
  }

  # Auto-scale wrapper with footnote (no double-escaping — notes are already valid LaTeX)
  if (nzchar(note_text)) {
    lines <- c(lines,
      "\\ifdim\\wd0>\\linewidth",
      "  \\resizebox{\\linewidth}{!}{\\usebox0}%",
      sprintf("  \\par\\vspace{3pt}\\parbox{\\linewidth}{\\raggedright\\scriptsize %s}", note_text),
      "\\else",
      "  \\usebox0%",
      sprintf("  \\par\\vspace{3pt}\\parbox{\\wd0}{\\raggedright\\scriptsize %s}", note_text),
      "\\fi"
    )
  } else {
    lines <- c(lines,
      "\\ifdim\\wd0>\\linewidth",
      "  \\resizebox{\\linewidth}{!}{\\usebox0}%",
      "\\else",
      "  \\usebox0%",
      "\\fi"
    )
  }

  # --- Write .tex ---
  dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
  tex_path <- file.path(table_dir, paste0(filename, ".tex"))
  writeLines(lines, tex_path)

  cat(sprintf("  Saved: %s (.tex)\n", filename))
  invisible(tex_path)
}
