#!/usr/bin/env Rscript

# ==============================================================================
# Build BNDES Sector Mapping (CNAE Section -> BNDES Macro-Sector)
# ==============================================================================
# Creates a crosswalk from 21 CNAE sections to 4 BNDES macro-sectors
# (Agropecuária, Indústria, Infraestrutura, Comércio e Serviços) using the
# official BNDES sector classification from data/raw/sector_mapping.csv.
#
# For CNAE codes with product-line-dependent classification (e.g., "Somente
# BNDES Exim"), we use the default/broadest classification:
#   - "Todos" rows preferred
#   - "Exceto" rows (default with exclusions) over "Somente" rows (exception-only)
#
# For section J (Information/Communication), J61 (telecom) maps to
# Infraestrutura while J58-63 maps to Comércio. Since the firm panel has
# cnae_section (not division), we assign J → Comércio e Serviços (majority).
#
# Input:  data/raw/sector_mapping.csv
# Output: output/bndes_sector_mapping.qs2
#         output/bndes_sector_mapping_summary.csv
#
# Dependencies: none (standalone crosswalk)
# ==============================================================================

cat("==============================================================================\n")
cat("Building BNDES Sector Mapping (Script 30b)\n")
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

raw_path <- file.path(PROJECT_ROOT, "data", "raw", "sector_mapping.csv")
out_path <- make_output_path("bndes_sector_mapping.qs2")
summary_path <- make_output_path("bndes_sector_mapping_summary.csv")

# --- Step 1: Read and parse the BNDES sector mapping -------------------------

cat("Step 1: Reading BNDES sector mapping...\n")

if (!file.exists(raw_path)) {
  stop("Sector mapping file not found: ", raw_path)
}

raw_dt <- fread(raw_path, encoding = "UTF-8")
cat(sprintf("  Raw rows: %d\n", nrow(raw_dt)))

# --- Step 2: Filter to default classification rows ---------------------------
# Priority: "Todos" > "Exceto*" > "Somente*"
# For each unique CNAE code, keep the broadest classification.

cat("\nStep 2: Filtering to default classification rows...\n")

raw_dt[, priority := fcase(
  grepl("^Todos", produto_bndes), 1L,
  grepl("^Exceto", produto_bndes), 2L,
  grepl("^Somente", produto_bndes), 3L,
  default = 2L
)]

# For each CNAE code, keep the highest-priority row
setorder(raw_dt, codigo_cnae_ibge, priority)
default_dt <- raw_dt[, .SD[1L], by = codigo_cnae_ibge]

cat(sprintf("  Default classification rows: %d (from %d raw)\n",
            nrow(default_dt), nrow(raw_dt)))

# --- Step 3: Parse CNAE codes to extract section letters ---------------------

cat("\nStep 3: Parsing CNAE codes to section level...\n")

# Extract the section letter from codigo_cnae_ibge
# Formats: "A01 a A03", "C10", "D351", "F41 e F43", "H49 (restante)", etc.
default_dt[, cnae_section := sub("^([A-U]).*", "\\1", codigo_cnae_ibge)]

# Build cnae_section -> bndes_sector mapping
# For each section, take the bndes_sector from the majority of default rows
section_votes <- default_dt[, .N, by = .(cnae_section, setor_bndes)]
setorder(section_votes, cnae_section, -N)
section_majority <- section_votes[, .SD[1L], by = cnae_section]

cat("  Section-level mapping from majority vote:\n")
for (i in seq_len(nrow(section_majority))) {
  r <- section_majority[i]
  cat(sprintf("    %s -> %s (%d rows)\n", r$cnae_section, r$setor_bndes, r$N))
}

# --- Step 4: Build final crosswalk -------------------------------------------

cat("\nStep 4: Building final crosswalk...\n")

# Define the canonical mapping (hardcoded for clarity and auditability)
# This matches the majority-vote result but is explicit about edge cases
crosswalk <- data.table(
  cnae_section = c("A", "B", "C", "D", "E", "F", "G", "H",
                    "I", "J", "K", "L", "M", "N",
                    "O", "P", "Q", "R", "S", "T", "U"),
  bndes_sector = c(
    "Agropecuaria",                          # A
    "Industria",                             # B
    "Industria",                             # C
    "Infraestrutura",                        # D (default; Exim-only→Comércio)
    "Infraestrutura",                        # E (default; Exim-only→Comércio)
    "Infraestrutura",                        # F (default; some products→Comércio)
    "Comercio e Servicos",                   # G
    "Infraestrutura",                        # H (default; Exim-only→Comércio)
    "Comercio e Servicos",                   # I
    "Comercio e Servicos",                   # J (J61=Infra, rest=Comércio; majority)
    "Comercio e Servicos",                   # K
    "Comercio e Servicos",                   # L
    "Comercio e Servicos",                   # M
    "Comercio e Servicos",                   # N
    "Comercio e Servicos",                   # O
    "Comercio e Servicos",                   # P
    "Comercio e Servicos",                   # Q
    "Comercio e Servicos",                   # R
    "Comercio e Servicos",                   # S
    "Comercio e Servicos",                   # T
    "Comercio e Servicos"                    # U
  ),
  bndes_sector_label = c(
    "Agriculture & Fishing",                 # A
    "Extractive Industry",                   # B
    "Manufacturing",                         # C
    "Utilities",                             # D
    "Water & Waste",                         # E
    "Construction",                          # F
    "Trade",                                 # G
    "Transport & Logistics",                 # H
    "Hospitality",                           # I
    "Information & Communication",           # J
    "Finance & Insurance",                   # K
    "Real Estate",                           # L
    "Professional Services",                 # M
    "Administrative Services",               # N
    "Public Administration",                 # O
    "Education",                             # P
    "Health & Social Services",              # Q
    "Arts & Culture",                        # R
    "Other Services",                        # S
    "Domestic Services",                     # T
    "International Organizations"            # U
  )
)

cat(sprintf("  Crosswalk rows: %d\n", nrow(crosswalk)))
cat(sprintf("  Unique BNDES sectors: %d\n", uniqueN(crosswalk$bndes_sector)))
cat(sprintf("  Sectors: %s\n", paste(sort(unique(crosswalk$bndes_sector)), collapse = ", ")))

# Print the mapping
cat("\n  BNDES sector mapping:\n")
for (g in sort(unique(crosswalk$bndes_sector))) {
  secs <- sort(crosswalk[bndes_sector == g, cnae_section])
  cat(sprintf("    %s: sections %s\n", g, paste(secs, collapse = ", ")))
}

# --- Step 5: Save outputs ----------------------------------------------------

cat("\nStep 5: Saving outputs...\n")

qs_save(crosswalk, out_path)
cat(sprintf("  Saved: %s\n", out_path))

fwrite(crosswalk, summary_path)
cat(sprintf("  Saved: %s\n", summary_path))

cat("\n==============================================================================\n")
cat("BNDES sector mapping complete.\n")
cat("==============================================================================\n")
