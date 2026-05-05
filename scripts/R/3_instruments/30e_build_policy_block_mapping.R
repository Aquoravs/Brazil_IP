#!/usr/bin/env Rscript

# ==============================================================================
# Build Policy Block Mapping (CNAE Section -> 4 BNDES Policy Blocks)
# ==============================================================================
# Groups 21 CNAE sections into 4 coarse "policy blocks" that mirror how BNDES
# organizes its lending divisions, defined ex ante from institutional logic
# rather than derived from the raw sector_mapping.csv product-line table.
#
# Policy blocks:
#   Agro    = Agriculture (A) — dedicated BNDES agricultural programs
#   Ind     = Industry (B, C) — core developmental lending (Finame, Exim)
#   Infra   = Infrastructure (D, E, F, H) — long-term project finance
#   Serv    = Services & Trade (G, I, J, L, M, N, P, Q, R, S)
#   XX      = Residual (K, O, T, U) — dropped from regressions
#
# K (Finance) is dropped because BNDES on-lends through financial institutions
# in section K, confounding the instrument. O (Public Admin), T (Domestic),
# U (International) have near-zero BNDES lending.
#
# Input:  output/rais_bndes_reconstructed.fst (for validation)
# Output: output/policy_block_mapping.qs2
#         output/policy_block_mapping_summary.csv
#
# Dependencies: script 22
# ==============================================================================

cat("==============================================================================\n")
cat("Building Policy Block Mapping (Script 30e)\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})

setDTthreads(0)

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

# --- Configuration -----------------------------------------------------------

out_path     <- make_output_path("policy_block_mapping.qs2")
summary_path <- make_output_path("policy_block_mapping_summary.csv")

# --- Step 1: Define the policy block mapping ----------------------------------

cat("Step 1: Defining policy block mapping...\n\n")

crosswalk <- data.table(
  cnae_section = c("A", "B", "C", "D", "E", "F", "G", "H",
                    "I", "J", "K", "L", "M", "N",
                    "O", "P", "Q", "R", "S", "T", "U"),
  policy_block = c(
    "Agro",          # A — Agriculture & Fishing
    "Ind",           # B — Mining & Extraction
    "Ind",           # C — Manufacturing
    "Infra",         # D — Electricity & Gas
    "Infra",         # E — Water & Waste
    "Infra",         # F — Construction
    "Serv",          # G — Trade
    "Infra",         # H — Transport & Logistics
    "Serv",          # I — Hospitality
    "Serv",          # J — Information & Communication
    "XX",            # K — Finance (BNDES intermediary; confounds instrument)
    "Serv",          # L — Real Estate
    "Serv",          # M — Professional Services
    "Serv",          # N — Administrative Services
    "XX",            # O — Public Administration
    "Serv",          # P — Education
    "Serv",          # Q — Health & Social Services
    "Serv",          # R — Arts & Culture
    "Serv",          # S — Other Services
    "XX",            # T — Domestic Services
    "XX"             # U — International Organizations
  ),
  policy_block_label = c(
    "Agriculture",                # A
    "Industry",                   # B
    "Industry",                   # C
    "Infrastructure",             # D
    "Infrastructure",             # E
    "Infrastructure",             # F
    "Services & Trade",           # G
    "Infrastructure",             # H
    "Services & Trade",           # I
    "Services & Trade",           # J
    "Residual",                   # K
    "Services & Trade",           # L
    "Services & Trade",           # M
    "Services & Trade",           # N
    "Residual",                   # O
    "Services & Trade",           # P
    "Services & Trade",           # Q
    "Services & Trade",           # R
    "Services & Trade",           # S
    "Residual",                   # T
    "Residual"                    # U
  ),
  cnae_section_label = c(
    "Agriculture & Fishing",      # A
    "Mining & Extraction",        # B
    "Manufacturing",              # C
    "Electricity & Gas",          # D
    "Water & Waste",              # E
    "Construction",               # F
    "Trade",                      # G
    "Transport & Logistics",      # H
    "Hospitality",                # I
    "Information & Communication", # J
    "Finance & Insurance",        # K
    "Real Estate",                # L
    "Professional Services",      # M
    "Administrative Services",    # N
    "Public Administration",      # O
    "Education",                  # P
    "Health & Social Services",   # Q
    "Arts & Culture",             # R
    "Other Services",             # S
    "Domestic Services",          # T
    "International Organizations" # U
  )
)

cat("  Policy block mapping:\n")
for (g in c("Agro", "Ind", "Infra", "Serv", "XX")) {
  lab  <- crosswalk[policy_block == g, policy_block_label[1]]
  secs <- sort(crosswalk[policy_block == g, cnae_section])
  sec_labs <- crosswalk[policy_block == g][order(cnae_section), cnae_section_label]
  cat(sprintf("    %s (%s): sections %s\n", g, lab, paste(secs, collapse = ", ")))
  for (j in seq_along(secs)) {
    cat(sprintf("      %s = %s\n", secs[j], sec_labs[j]))
  }
}

cat(sprintf("\n  Total sections: %d (%d active + %d residual)\n",
            nrow(crosswalk),
            sum(crosswalk$policy_block != "XX"),
            sum(crosswalk$policy_block == "XX")))

# --- Step 2: Validate against reconstructed panel ----------------------------

cat("\nStep 2: Validating against reconstructed panel...\n")

recon_path_fst <- make_output_path("rais_bndes_reconstructed.fst")
recon_path_qs2 <- make_output_path("rais_bndes_reconstructed.qs2")

if (file.exists(recon_path_fst) && requireNamespace("fst", quietly = TRUE)) {
  cat("  Loading from fst (column-selective):", basename(recon_path_fst), "\n")
  recon <- fst::read_fst(recon_path_fst,
                          columns = c("firm_id", "muni_id", "year", "cnae_section",
                                      "in_bndes", "value_dis_real_2018_total"),
                          as.data.table = TRUE)
} else if (file.exists(recon_path_qs2)) {
  cat("  Loading from qs2:", basename(recon_path_qs2), "\n")
  raw <- qs_read(recon_path_qs2)
  setDT(raw)
  recon <- raw[, .(firm_id, muni_id, year, cnae_section,
                   in_bndes, value_dis_real_2018_total)]
  rm(raw); invisible(gc())
} else {
  cat("  WARNING: Reconstructed panel not found. Skipping validation.\n")
  recon <- NULL
}

if (!is.null(recon)) {
  recon_merged <- merge(recon, crosswalk[, .(cnae_section, policy_block, policy_block_label)],
                        by = "cnae_section", all.x = TRUE)

  n_matched <- sum(!is.na(recon_merged$policy_block))
  n_total   <- sum(!is.na(recon_merged$cnae_section))
  cat(sprintf("  Policy block match: %d / %d (%.1f%%)\n",
              n_matched, n_total, 100 * n_matched / n_total))

  cat("\n  Coverage by policy block:\n")
  coverage <- recon_merged[!is.na(policy_block), .(
    n_firm_years = .N,
    n_bndes      = sum(in_bndes == 1L, na.rm = TRUE),
    total_bndes  = sum(fifelse(in_bndes == 1L, value_dis_real_2018_total, 0), na.rm = TRUE)
  ), by = .(policy_block, policy_block_label)]
  coverage[, pct_firms := 100 * n_firm_years / sum(n_firm_years)]
  coverage[, pct_bndes := 100 * total_bndes / sum(total_bndes)]
  setorder(coverage, -total_bndes)
  for (i in seq_len(nrow(coverage))) {
    cat(sprintf("    %s (%s): %s firm-years (%.1f%%), %s BNDES firms, R$ %.1fM BNDES (%.1f%%)\n",
                coverage$policy_block[i],
                coverage$policy_block_label[i],
                format(coverage$n_firm_years[i], big.mark = ","),
                coverage$pct_firms[i],
                format(coverage$n_bndes[i], big.mark = ","),
                coverage$total_bndes[i] / 1e6,
                coverage$pct_bndes[i]))
  }

  cells <- recon_merged[!is.na(policy_block) & policy_block != "XX" & in_bndes == 1L,
                        uniqueN(paste(muni_id, year)),
                        by = policy_block]
  setnames(cells, "V1", "n_nonzero_cells")
  cat("\n  Nonzero BNDES cells by block (for instrument validity):\n")
  setorder(cells, n_nonzero_cells)
  for (i in seq_len(nrow(cells))) {
    flag <- if (cells$n_nonzero_cells[i] < 500) " *** BELOW 500 ***" else ""
    cat(sprintf("    %s: %d cells%s\n",
                cells$policy_block[i], cells$n_nonzero_cells[i], flag))
  }

  rm(recon, recon_merged); invisible(gc())
}

# --- Step 3: Save -------------------------------------------------------------

cat("\nStep 3: Saving...\n")

qs_save(crosswalk, out_path)
cat(sprintf("  Saved %s (%.2f KB)\n", out_path, file.size(out_path) / 1024))

fwrite(crosswalk, summary_path)
cat(sprintf("  Saved %s\n", summary_path))

cat("\n  Section-level crosswalk:\n")
print(crosswalk[, .(cnae_section, policy_block, policy_block_label)])

cat("\nPolicy block mapping complete.\n")
cat("  Use --sector-var=policy_block in downstream scripts to activate.\n")
cat("==============================================================================\n")
