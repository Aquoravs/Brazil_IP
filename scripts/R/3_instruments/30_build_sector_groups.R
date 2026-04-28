#!/usr/bin/env Rscript

# ==============================================================================
# Build Sector Group Mapping (CNAE Section -> Sector Groups)
# ==============================================================================
# Creates a crosswalk from 21 CNAE sections to ~10 sector groups for
# robustness analysis. Manufacturing (section C) is split into 3 sub-groups
# based on CNAE division (2-digit code). Problematic sections (K=finance/
# BNDES intermediaries, O=public admin with near-zero BNDES, T, U) are
# collapsed into a residual group (dropped from regressions).
#
# Grouping logic:
#   Ag  = Agriculture (A)
#   Mi  = Mining (B)
#   CL  = Light Manufacturing (C div 10-18)
#   CH  = Heavy Manufacturing (C div 19-25)
#   CA  = Advanced Manufacturing (C div 26-33)
#   UCo = Utilities & Construction (D, E, F)
#   Tr  = Trade (G)
#   Tp  = Transport (H)
#   MS  = Market Services (I, J, L, M, N)
#   PSO = Public, Social & Other (P, Q, R, S)
#   XX  = Residual (K, O, T, U) — dropped from regressions
#
# Input:  output/rais_bndes_reconstructed.fst (for cnae_division derivation)
# Output: output/sector_group_mapping.qs2
#         output/sector_group_mapping_summary.csv
#
# Dependencies: script 22
# ==============================================================================

cat("==============================================================================\n")
cat("Building Sector Group Mapping (Script 30)\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})

setDTthreads(0)


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

# --- Configuration -----------------------------------------------------------

out_path     <- make_output_path("sector_group_mapping.qs2")
summary_path <- make_output_path("sector_group_mapping_summary.csv")

# --- Step 1: Define the sector group mapping ---------------------------------

cat("Step 1: Defining sector group mapping...\n")

# Official CNAE 2.0 division-to-section mapping (same as script 22)
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

# For non-Manufacturing sections, sector_group is determined solely by section
section_to_group <- data.table(
  cnae_section = c("A", "B", "D", "E", "F", "G", "H",
                   "I", "J", "K", "L", "M", "N",
                   "O", "P", "Q", "R", "S",
                   "T", "U"),
  sector_group = c("Ag", "Mi", "UCo", "UCo", "UCo", "Tr", "Tp",
                   "MS", "MS", "XX", "MS", "MS", "MS",
                   "XX", "PSO", "PSO", "PSO", "PSO",
                   "XX", "XX"),
  sector_group_label = c(
    "Agriculture", "Mining",
    "Utilities & Construction", "Utilities & Construction", "Utilities & Construction",
    "Trade", "Transport",
    "Market Services", "Market Services", "Residual",
    "Market Services", "Market Services", "Market Services",
    "Residual", "Public, Social & Other",
    "Public, Social & Other", "Public, Social & Other", "Public, Social & Other",
    "Residual", "Residual"
  )
)

# Manufacturing (C) splits by division
# CL = Light Manufacturing (div 10-18)
# CH = Heavy Manufacturing (div 19-25)
# CA = Advanced Manufacturing (div 26-33)
mfg_divisions <- div_to_section[cnae_section == "C"]
mfg_divisions[, sector_group := fcase(
  cnae_division >= 10L & cnae_division <= 18L, "CL",
  cnae_division >= 19L & cnae_division <= 25L, "CH",
  cnae_division >= 26L & cnae_division <= 33L, "CA"
)]
mfg_divisions[, sector_group_label := fcase(
  sector_group == "CL", "Light Manufacturing",
  sector_group == "CH", "Heavy Manufacturing",
  sector_group == "CA", "Advanced Manufacturing"
)]

# Build full crosswalk: each (cnae_section, cnae_division) -> sector_group
# Non-C sections: merge section_to_group
non_c <- div_to_section[cnae_section != "C"]
non_c <- merge(non_c, section_to_group, by = "cnae_section", all.x = TRUE)

# C sections: use mfg_divisions
crosswalk <- rbind(
  non_c[, .(cnae_section, cnae_division, sector_group, sector_group_label)],
  mfg_divisions[, .(cnae_section, cnae_division, sector_group, sector_group_label)]
)

setorder(crosswalk, cnae_division)

cat("  Crosswalk rows:", nrow(crosswalk), "\n")
cat("  Unique sector groups:", uniqueN(crosswalk$sector_group), "\n")
cat("  Groups:", paste(sort(unique(crosswalk$sector_group)), collapse = ", "), "\n\n")

# Print the mapping
cat("  Sector group mapping:\n")
for (g in sort(unique(crosswalk$sector_group))) {
  lab <- crosswalk[sector_group == g, sector_group_label[1]]
  secs <- unique(crosswalk[sector_group == g, cnae_section])
  divs <- sort(crosswalk[sector_group == g, cnae_division])
  cat(sprintf("    %s (%s): sections %s, divisions %s\n",
              g, lab, paste(secs, collapse = ","),
              paste(divs, collapse = ",")))
}

# Also create a section-level crosswalk (without division detail)
# for sections that don't need division-level splitting (all non-C)
# For C, we need the division to determine the group
section_crosswalk <- unique(crosswalk[cnae_section != "C",
                                       .(cnae_section, sector_group, sector_group_label)])

# --- Step 2: Validate against reconstructed panel ----------------------------

cat("\nStep 2: Validating against reconstructed panel...\n")

recon_path_fst <- make_output_path("rais_bndes_reconstructed.fst")
recon_path_qs2 <- make_output_path("rais_bndes_reconstructed.qs2")

if (file.exists(recon_path_fst) && requireNamespace("fst", quietly = TRUE)) {
  cat("  Loading from fst (column-selective):", basename(recon_path_fst), "\n")
  recon <- fst::read_fst(recon_path_fst,
                          columns = c("firm_id", "muni_id", "year", "cnae_section",
                                      "classe", "in_bndes", "value_dis_real_2018_total"),
                          as.data.table = TRUE)
} else if (file.exists(recon_path_qs2)) {
  cat("  Loading from qs2:", basename(recon_path_qs2), "\n")
  raw <- qs_read(recon_path_qs2)
  setDT(raw)
  recon <- raw[, .(firm_id, muni_id, year, cnae_section, classe,
                   in_bndes, value_dis_real_2018_total)]
  rm(raw); invisible(gc())
} else {
  cat("  WARNING: Reconstructed panel not found. Skipping validation.\n")
  recon <- NULL
}

if (!is.null(recon)) {
  # Derive cnae_division from classe
  recon[, cnae_division := as.integer(floor(as.numeric(classe) / 1000))]

  # Merge crosswalk
  recon_merged <- merge(recon, crosswalk[, .(cnae_division, sector_group)],
                        by = "cnae_division", all.x = TRUE)

  # For non-C sections without division, merge via section_crosswalk
  recon_merged[is.na(sector_group) & !is.na(cnae_section),
               sector_group := section_crosswalk$sector_group[
                 match(cnae_section, section_crosswalk$cnae_section)]]

  n_matched <- sum(!is.na(recon_merged$sector_group))
  n_total <- sum(!is.na(recon_merged$cnae_section))
  cat(sprintf("  Sector group match: %d / %d (%.1f%%)\n",
              n_matched, n_total, 100 * n_matched / n_total))

  # Coverage by group: RAIS firms and BNDES credit
  cat("\n  Coverage by sector group:\n")
  coverage <- recon_merged[!is.na(sector_group), .(
    n_firm_years = .N,
    n_bndes = sum(in_bndes == 1L, na.rm = TRUE),
    total_bndes = sum(fifelse(in_bndes == 1L, value_dis_real_2018_total, 0), na.rm = TRUE)
  ), by = sector_group]
  coverage[, pct_firms := 100 * n_firm_years / sum(n_firm_years)]
  coverage[, pct_bndes := 100 * total_bndes / sum(total_bndes)]
  setorder(coverage, -total_bndes)
  for (i in seq_len(nrow(coverage))) {
    cat(sprintf("    %s: %s firm-years (%.1f%%), %s BNDES firms, R$ %.1fM BNDES (%.1f%%)\n",
                coverage$sector_group[i],
                format(coverage$n_firm_years[i], big.mark = ","),
                coverage$pct_firms[i],
                format(coverage$n_bndes[i], big.mark = ","),
                coverage$total_bndes[i] / 1e6,
                coverage$pct_bndes[i]))
  }

  # Check minimum nonzero instrument observations per group
  # (proxy: number of muni-group-year cells with BNDES > 0)
  cells <- recon_merged[!is.na(sector_group) & in_bndes == 1L,
                        uniqueN(paste(muni_id, year)),
                        by = sector_group]
  setnames(cells, "V1", "n_nonzero_cells")
  cat("\n  Nonzero BNDES cells by group (for instrument validity):\n")
  setorder(cells, n_nonzero_cells)
  for (i in seq_len(nrow(cells))) {
    flag <- if (cells$n_nonzero_cells[i] < 500) " *** BELOW 500 ***" else ""
    cat(sprintf("    %s: %d cells%s\n",
                cells$sector_group[i], cells$n_nonzero_cells[i], flag))
  }

  rm(recon, recon_merged); invisible(gc())
}

# --- Step 3: Save -----------------------------------------------------------

cat("\nStep 3: Saving...\n")

qs_save(crosswalk, out_path)
cat(sprintf("  Saved %s (%.2f KB)\n", out_path, file.size(out_path) / 1024))

# Summary CSV
fwrite(crosswalk, summary_path)
cat(sprintf("  Saved %s\n", summary_path))

# Also save the section-level crosswalk as an attribute-accessible reference
section_level <- unique(crosswalk[, .(cnae_section, sector_group, sector_group_label)])
setorder(section_level, cnae_section)
cat("\n  Section-level crosswalk (for non-C sections and C aggregate):\n")
print(section_level)

cat("\nSector group mapping complete.\n")
cat("  Use --sector-var=sector_group in downstream scripts to activate grouping.\n")
