# ==============================================================================
# cnae_coverage_audit.R
# CNAE section coverage audit for policy_block taxonomy
#
# Answers three questions:
#   (1) How much BNDES credit volume goes to XX sub-sections (K, O, T, U)
#       vs. the 4 active blocks?
#   (2) What share of all firm-years fall in XX, by sub-section?
#   (3) Are XX firms geographically concentrated (state, muni-size quartile)?
#
# Inputs:
#   data/processed/rais_bndes_reconstructed.fst  (preferred)
#   data/processed/rais_bndes_reconstructed.qs2  (fallback)
#   data/processed/policy_block_mapping.qs2
#
# Outputs (all in explorations/anderson_rubin/diagnostics/output/):
#   cnae_section_summary.csv
#   policy_block_summary.csv
#   xx_subsection_summary.csv
#   geographic_by_state.csv
#   geographic_by_muni_size.csv
#   cnae_coverage_report.md
#
# Paper reference: explorations/anderson_rubin/README.md
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Packages (INV-15: all at top)
# ------------------------------------------------------------------------------
library(data.table)
library(qs2)
library(here)

# Load fst only if available
HAS_FST <- requireNamespace("fst", quietly = TRUE)
if (HAS_FST) library(fst)

setDTthreads(0L)

# ------------------------------------------------------------------------------
# 2. Paths via here::here() (INV-16: no absolute paths)
# ------------------------------------------------------------------------------
PROCESSED_DIR  <- here::here("data", "processed")
OUTPUT_DIR     <- here::here(
  "explorations", "anderson_rubin", "diagnostics", "output"
)

if (!dir.exists(OUTPUT_DIR)) {
  dir.create(OUTPUT_DIR, recursive = TRUE)
  message("Created output directory: ", OUTPUT_DIR)
}

path_fst     <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.fst")
path_qs2     <- file.path(PROCESSED_DIR, "rais_bndes_reconstructed.qs2")
path_cw      <- file.path(PROCESSED_DIR, "policy_block_mapping.qs2")

# ------------------------------------------------------------------------------
# 3. Load policy_block crosswalk
# ------------------------------------------------------------------------------
message("Loading policy_block crosswalk...")

if (!file.exists(path_cw)) {
  stop(
    "policy_block_mapping.qs2 not found at: ", path_cw,
    "\nRun script 30e first."
  )
}

crosswalk <- setDT(qs_read(path_cw))
stopifnot(all(c("cnae_section", "policy_block",
                "policy_block_label", "cnae_section_label") %in% names(crosswalk)))
stopifnot(nrow(crosswalk) == 21L)
message(sprintf("  Crosswalk loaded: %d CNAE sections.", nrow(crosswalk)))

# Expected CNAE section order for output
CNAE_ORDER <- c("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K",
                 "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U")

XX_SECTIONS <- c("K", "O", "T", "U")

# ------------------------------------------------------------------------------
# 4. Load reconstructed panel (fst preferred, qs2 fallback)
#    Column-selective: only what we need.
# ------------------------------------------------------------------------------
COLS_NEEDED <- c("firm_id", "muni_id", "year", "cnae_section",
                 "in_bndes", "value_dis_real_2018_total", "n_employees")

message("Loading reconstructed RAIS-BNDES panel...")

if (HAS_FST && file.exists(path_fst)) {
  message("  Source: fst (column-selective) — ", basename(path_fst))
  panel <- fst::read_fst(path_fst, columns = COLS_NEEDED, as.data.table = TRUE)
} else if (file.exists(path_qs2)) {
  message("  Source: qs2 — ", basename(path_qs2))
  raw <- qs_read(path_qs2)
  setDT(raw)
  missing_cols <- setdiff(COLS_NEEDED, names(raw))
  if (length(missing_cols) > 0L) {
    stop("qs2 file missing columns: ", paste(missing_cols, collapse = ", "))
  }
  panel <- raw[, .SD, .SDcols = COLS_NEEDED]
  rm(raw)
  invisible(gc())
} else {
  stop(
    "Neither fst nor qs2 panel file found.\n",
    "Expected:\n  ", path_fst, "\n  or\n  ", path_qs2
  )
}

message(sprintf("  Panel loaded: %s firm-years, %d columns.",
                format(nrow(panel), big.mark = ","), ncol(panel)))

# Validate key columns
stopifnot(is.data.table(panel))
stopifnot(all(COLS_NEEDED %in% names(panel)))

# Coerce in_bndes to integer to ensure arithmetic is safe
panel[, in_bndes := as.integer(in_bndes)]

# Guard: replace NA employment and loan value with 0 for aggregation
panel[is.na(n_employees),              n_employees              := 0L]
panel[is.na(value_dis_real_2018_total), value_dis_real_2018_total := 0]

# ------------------------------------------------------------------------------
# 5. Merge crosswalk; tag XX sub-sections
# ------------------------------------------------------------------------------
message("Merging crosswalk into panel...")

panel <- merge(
  panel,
  crosswalk[, .(cnae_section, policy_block, policy_block_label,
                cnae_section_label)],
  by    = "cnae_section",
  all.x = TRUE
)

n_unmatched <- panel[is.na(policy_block), .N]
if (n_unmatched > 0L) {
  warning(sprintf(
    "%d firm-years have no policy_block match — check crosswalk coverage.",
    n_unmatched
  ))

  # --- Diagnostic: why are these unmatched? ---
  message("\n  --- Unmatched firm-year diagnostic ---")
  unmatched_breakdown <- panel[is.na(policy_block), .(
    n_firm_years   = .N,
    n_firms        = uniqueN(firm_id),
    n_munis        = uniqueN(muni_id),
    years          = paste(sort(unique(year)), collapse = ", "),
    n_bndes        = sum(in_bndes == 1L, na.rm = TRUE),
    bndes_value_M  = sum(
      fifelse(in_bndes == 1L, value_dis_real_2018_total, 0),
      na.rm = TRUE
    ) / 1e6
  ), by = .(cnae_section_raw = cnae_section)]

  # Tag the cnae_section value type so NA vs "" vs unexpected letter are obvious
  unmatched_breakdown[, value_kind := fcase(
    is.na(cnae_section_raw),                                       "NA",
    cnae_section_raw == "",                                        "empty string",
    !cnae_section_raw %in% CNAE_ORDER,                             "outside A-U",
    default                                                      = "unexpected"
  )]

  setcolorder(unmatched_breakdown,
              c("cnae_section_raw", "value_kind",
                "n_firm_years", "n_firms", "n_munis",
                "n_bndes", "bndes_value_M", "years"))

  print(unmatched_breakdown)

  fwrite(unmatched_breakdown,
         file.path(OUTPUT_DIR, "unmatched_cnae_diagnostic.csv"))
  message("  --- saved: unmatched_cnae_diagnostic.csv ---\n")
}

panel[, is_xx      := (policy_block == "XX")]
panel[, xx_section := fifelse(cnae_section %in% XX_SECTIONS,
                               cnae_section, NA_character_)]

message(sprintf(
  "  Match complete. XX firm-years: %s (%.1f%% of total).",
  format(panel[is_xx == TRUE, .N], big.mark = ","),
  100 * panel[is_xx == TRUE, .N] / nrow(panel)
))

# ------------------------------------------------------------------------------
# 6. Section-level summary (21 rows)
# ------------------------------------------------------------------------------
message("Computing section-level summary...")

# Total denominators for percentage columns
N_FY_TOTAL   <- nrow(panel)
EMP_TOTAL    <- panel[, sum(n_employees)]
BNDES_TOTAL  <- panel[in_bndes == 1L, sum(value_dis_real_2018_total)]

section_summary <- panel[, .(
  n_firm_years       = .N,
  n_firms            = uniqueN(firm_id),
  total_employment   = sum(n_employees),
  n_bndes_firm_years = sum(in_bndes == 1L, na.rm = TRUE),
  total_bndes_value  = sum(
    fifelse(in_bndes == 1L, value_dis_real_2018_total, 0),
    na.rm = TRUE
  )
), by = cnae_section]

section_summary <- merge(
  section_summary,
  crosswalk[, .(cnae_section, cnae_section_label, policy_block)],
  by = "cnae_section"
)

section_summary[, in_regression  := (policy_block != "XX")]
section_summary[, pct_firm_years := 100 * n_firm_years  / N_FY_TOTAL]
section_summary[, pct_employment := 100 * total_employment / EMP_TOTAL]
section_summary[, pct_bndes_value := if (BNDES_TOTAL > 0) {
  100 * total_bndes_value / BNDES_TOTAL
} else {
  NA_real_
}]

# Order by canonical CNAE section order
section_summary[, cnae_section := factor(cnae_section, levels = CNAE_ORDER)]
setorder(section_summary, cnae_section)
section_summary[, cnae_section := as.character(cnae_section)]

setcolorder(section_summary, c(
  "cnae_section", "cnae_section_label", "policy_block", "in_regression",
  "n_firm_years", "n_firms", "total_employment",
  "n_bndes_firm_years", "total_bndes_value",
  "pct_firm_years", "pct_employment", "pct_bndes_value"
))

stopifnot(nrow(section_summary) == 21L)
stopifnot(abs(sum(section_summary$pct_firm_years) - 100) < 1e-4)
message(sprintf("  pct_firm_years sums to %.6f (check: ~100).",
                sum(section_summary$pct_firm_years)))

# ------------------------------------------------------------------------------
# 7. Policy-block summary (5 rows)
# ------------------------------------------------------------------------------
message("Computing policy-block summary...")

block_summary <- panel[, .(
  n_firm_years       = .N,
  n_firms            = uniqueN(firm_id),
  total_employment   = sum(n_employees),
  n_bndes_firm_years = sum(in_bndes == 1L, na.rm = TRUE),
  total_bndes_value  = sum(
    fifelse(in_bndes == 1L, value_dis_real_2018_total, 0),
    na.rm = TRUE
  )
), by = policy_block]

block_summary <- block_summary[!is.na(policy_block)]

block_summary[, in_regression  := (policy_block != "XX")]
block_summary[, pct_firm_years := 100 * n_firm_years  / N_FY_TOTAL]
block_summary[, pct_employment := 100 * total_employment / EMP_TOTAL]
block_summary[, pct_bndes_value := if (BNDES_TOTAL > 0) {
  100 * total_bndes_value / BNDES_TOTAL
} else {
  NA_real_
}]

# Canonical block order
BLOCK_ORDER <- c("Agro", "Ind", "Infra", "Serv", "XX")
block_summary[, policy_block := factor(policy_block, levels = BLOCK_ORDER)]
setorder(block_summary, policy_block)
block_summary[, policy_block := as.character(policy_block)]

stopifnot(nrow(block_summary) == 5L)

# XX sub-section detail (4 rows: K, O, T, U)
xx_detail <- section_summary[cnae_section %in% XX_SECTIONS]
stopifnot(nrow(xx_detail) == 4L)

xx_sub_summary <- xx_detail[, .(
  cnae_section, cnae_section_label, policy_block,
  n_firm_years, n_firms, total_employment,
  n_bndes_firm_years, total_bndes_value,
  pct_firm_years, pct_employment, pct_bndes_value
)]

# ------------------------------------------------------------------------------
# 8. Geographic: state-level breakdown
# ------------------------------------------------------------------------------
message("Computing state-level geographic breakdown...")

# State = first 2 digits of 7-digit muni_id
panel[, state_id := substr(as.character(muni_id), 1L, 2L)]

state_summary <- panel[, .(
  n_firm_years_total = .N,
  n_firm_years_xx    = sum(is_xx, na.rm = TRUE),
  emp_total          = sum(n_employees),
  emp_xx             = sum(n_employees * as.integer(is_xx), na.rm = TRUE)
), by = state_id]

state_summary[, xx_share_firm_years := 100 * n_firm_years_xx / n_firm_years_total]
state_summary[, xx_share_employment := 100 * emp_xx / fifelse(emp_total > 0, emp_total, NA_real_)]

setorder(state_summary, -xx_share_firm_years)

# ------------------------------------------------------------------------------
# 9. Geographic: municipality employment quartile breakdown
# ------------------------------------------------------------------------------
message("Computing municipality employment-quartile breakdown...")

# Total employment per muni, pooled across all years
muni_emp <- panel[, .(total_emp_muni = sum(n_employees)), by = muni_id]

# Quartile cut: ntile implemented via data.table rank approach (no dplyr)
# ntile(x, 4): assign each observation to one of 4 equally-sized groups
setorder(muni_emp, total_emp_muni)
N_MUNIS <- nrow(muni_emp)
muni_emp[, muni_emp_quartile := as.integer(ceiling(4 * .I / N_MUNIS))]
# Clamp to [1, 4] in case of floating-point edge
muni_emp[, muni_emp_quartile := pmin(pmax(muni_emp_quartile, 1L), 4L)]
muni_emp[, quartile_label := paste0("Q", muni_emp_quartile)]

# Merge back into panel
panel <- merge(panel, muni_emp[, .(muni_id, muni_emp_quartile, quartile_label)],
               by = "muni_id", all.x = TRUE)

muni_size_summary <- panel[!is.na(quartile_label), .(
  n_firm_years_total = .N,
  n_firm_years_xx    = sum(is_xx, na.rm = TRUE),
  emp_total          = sum(n_employees),
  emp_xx             = sum(n_employees * as.integer(is_xx), na.rm = TRUE)
), by = .(muni_emp_quartile, quartile_label)]

muni_size_summary[, xx_share_firm_years :=
  100 * n_firm_years_xx / n_firm_years_total]
muni_size_summary[, xx_share_employment :=
  100 * emp_xx / fifelse(emp_total > 0, emp_total, NA_real_)]

setorder(muni_size_summary, muni_emp_quartile)

# ------------------------------------------------------------------------------
# 10. Write all CSVs
# ------------------------------------------------------------------------------
message("Writing output CSVs...")

fwrite(section_summary,
       file.path(OUTPUT_DIR, "cnae_section_summary.csv"))
message("  Written: cnae_section_summary.csv  (", nrow(section_summary), " rows)")

fwrite(block_summary,
       file.path(OUTPUT_DIR, "policy_block_summary.csv"))
message("  Written: policy_block_summary.csv  (", nrow(block_summary), " rows)")

fwrite(xx_sub_summary,
       file.path(OUTPUT_DIR, "xx_subsection_summary.csv"))
message("  Written: xx_subsection_summary.csv (", nrow(xx_sub_summary), " rows)")

fwrite(state_summary,
       file.path(OUTPUT_DIR, "geographic_by_state.csv"))
message("  Written: geographic_by_state.csv   (", nrow(state_summary), " rows)")

fwrite(muni_size_summary,
       file.path(OUTPUT_DIR, "geographic_by_muni_size.csv"))
message("  Written: geographic_by_muni_size.csv (", nrow(muni_size_summary), " rows)")

# ------------------------------------------------------------------------------
# 11. Generate cnae_coverage_report.md
# ------------------------------------------------------------------------------
message("Generating cnae_coverage_report.md...")

# --- Helper: format large numbers ---
fmt_n   <- function(x) format(round(x), big.mark = ",", scientific = FALSE)
fmt_pct <- function(x) sprintf("%.1f", x)
fmt_m   <- function(x) sprintf("%.1f", x / 1e6)   # to R$ millions

# Scalar quantities for report
n_total_fy   <- N_FY_TOTAL
n_active_fy  <- panel[is_xx == FALSE, .N]
n_xx_fy      <- panel[is_xx == TRUE,  .N]
pct_active   <- 100 * n_active_fy / n_total_fy
pct_xx       <- 100 * n_xx_fy     / n_total_fy

# BNDES totals for XX sub-sections
k_bndes_pct <- xx_sub_summary[cnae_section == "K", pct_bndes_value]
k_bndes_pct <- if (length(k_bndes_pct) == 0L || is.na(k_bndes_pct)) 0 else k_bndes_pct

otu_bndes_pct <- xx_sub_summary[
  cnae_section %in% c("O", "T", "U"),
  sum(pct_bndes_value, na.rm = TRUE)
]

# XX employment share (for Section 5)
xx_emp_pct <- 100 * panel[is_xx == TRUE, sum(n_employees)] / EMP_TOTAL

# Q4 XX firm-year share
q4_xx_fy_share <- muni_size_summary[quartile_label == "Q4", xx_share_firm_years]
q4_xx_fy_share <- if (length(q4_xx_fy_share) == 0L) NA_real_ else q4_xx_fy_share

# Top-3 states by XX share — check for SP (35) and RJ (33)
top3_states   <- head(state_summary$state_id, 3L)
has_sp_top3   <- "35" %in% top3_states
has_rj_top3   <- "33" %in% top3_states

# --- Interpretation paragraphs (auto-fill rules) ---

# Section 2 interpretation
if (!is.na(k_bndes_pct) && k_bndes_pct > 5) {
  interp_xx <- sprintf(
    paste0(
      "Section K carries substantial BNDES volume, consistent with its ",
      "on-lending role. Exclusion is appropriate but note that %.1f%% of ",
      "BNDES credit volume flows through the excluded financial intermediary ",
      "channel."
    ),
    k_bndes_pct
  )
} else if (!is.na(k_bndes_pct) && k_bndes_pct < 1) {
  interp_xx <- paste0(
    "Section K carries minimal direct BNDES value — the on-lending mechanism ",
    "appears to route value primarily to recipient sectors in the data."
  )
} else {
  interp_xx <- sprintf(
    "Section K accounts for %.1f%% of total BNDES value in this dataset.",
    k_bndes_pct
  )
}

if (!is.na(otu_bndes_pct) && otu_bndes_pct > 1) {
  interp_xx <- paste0(
    interp_xx,
    sprintf(
      " Sections O, T, and U together account for %.1f%% of BNDES value — ",
      otu_bndes_pct
    ),
    "this is higher than expected given their near-zero direct BNDES lending ",
    "rationale; verify loan categorization."
  )
}

# Section 4 interpretation
geo_flags <- character(0L)

if (!is.na(q4_xx_fy_share) && q4_xx_fy_share > 15) {
  geo_flags <- c(geo_flags, sprintf(
    paste0(
      "XX sectors are over-represented in large municipalities ",
      "(Q4 xx_share_firm_years = %.1f%%). This implies the muni-normalized ",
      "weight denominators (E_mB) include a larger share of excluded-sector ",
      "firms in urban centers, potentially diluting the weight signal in ",
      "high-employment municipalities."
    ),
    q4_xx_fy_share
  ))
}

if (has_sp_top3 || has_rj_top3) {
  sp_rj_which <- paste(
    c(if (has_sp_top3) "SP (35)", if (has_rj_top3) "RJ (33)"),
    collapse = " and "
  )
  geo_flags <- c(geo_flags, sprintf(
    paste0(
      "%s appear in the top-3 states by XX firm-year share, consistent with ",
      "the expected geographic concentration of the financial sector (K)."
    ),
    sp_rj_which
  ))
}

interp_geo <- if (length(geo_flags) > 0L) {
  paste(geo_flags, collapse = " ")
} else {
  paste0(
    "XX firms do not appear strongly concentrated in the largest municipalities ",
    "or in SP/RJ — the exclusion criterion does not create a systematic ",
    "urban-rural imbalance in the instrument denominators."
  )
}

# Section 5 interpretation
interp_iv <- sprintf(
  paste0(
    "The emp_muni and own_muni weight denominators include XX firm-years ",
    "(E_mB = all municipal employment). XX represents %.1f%% of total ",
    "municipal employment in this panel, so the effective weight on ",
    "active-block affiliation is scaled down by a factor of approximately ",
    "%.3f on average. This is intentional — the denominator measures exposure ",
    "relative to the full local economy."
  ),
  xx_emp_pct,
  1 - xx_emp_pct / 100
)

if (!is.na(xx_emp_pct) && xx_emp_pct > 20) {
  interp_iv <- paste0(
    interp_iv,
    " WARNING: XX employment share exceeds 20%. Consider a robustness check ",
    "where the weight denominators are restricted to active blocks only ",
    "(Agro + Ind + Infra + Serv) to assess sensitivity of the instrument."
  )
}

# --- Build XX sub-section table rows ---
xx_tbl_rows <- vapply(seq_len(nrow(xx_sub_summary)), function(i) {
  r <- xx_sub_summary[i]
  sprintf(
    "| %s | %s | %s | %s | %.1f | %.2f |",
    r$cnae_section,
    r$cnae_section_label,
    fmt_n(r$n_firm_years),
    fmt_n(r$total_employment),
    r$total_bndes_value / 1e6,
    fifelse(is.na(r$pct_bndes_value), 0, r$pct_bndes_value)
  )
}, character(1L))

# --- Build active-block table rows ---
active_block_rows <- vapply(
  which(block_summary$policy_block != "XX"),
  function(i) {
    r <- block_summary[i]
    sprintf(
      "| %s | %s | %s | %.1f | %.2f |",
      r$policy_block,
      fmt_n(r$n_firm_years),
      fmt_n(r$total_employment),
      r$total_bndes_value / 1e6,
      fifelse(is.na(r$pct_bndes_value), 0, r$pct_bndes_value)
    )
  }, character(1L)
)

# --- Build state table (top 10 by XX firm-year share) ---
top10_states <- head(state_summary, 10L)
state_tbl_rows <- vapply(seq_len(nrow(top10_states)), function(i) {
  r <- top10_states[i]
  sprintf(
    "| %s | %s | %.1f | %.1f |",
    r$state_id,
    fmt_n(r$n_firm_years_total),
    r$xx_share_firm_years,
    fifelse(is.na(r$xx_share_employment), 0, r$xx_share_employment)
  )
}, character(1L))

# --- Build muni-size table ---
muni_tbl_rows <- vapply(seq_len(nrow(muni_size_summary)), function(i) {
  r <- muni_size_summary[i]
  sprintf(
    "| %s (smallest → largest) | %s | %.1f | %.1f |",
    r$quartile_label,
    fmt_n(r$n_firm_years_total),
    r$xx_share_firm_years,
    fifelse(is.na(r$xx_share_employment), 0, r$xx_share_employment)
  )
}, character(1L))

# --- Assemble report ---
report_lines <- c(
  "# CNAE Coverage Audit — policy_block Taxonomy",
  paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  "",
  "## 1. Overall Coverage",
  "",
  paste0("- Total firm-years: ", fmt_n(n_total_fy)),
  paste0("- In active blocks (Agro/Ind/Infra/Serv): ",
         fmt_n(n_active_fy), " (", fmt_pct(pct_active), "%)"),
  paste0("- In XX (residual — K, O, T, U): ",
         fmt_n(n_xx_fy), " (", fmt_pct(pct_xx), "%)"),
  paste0("- Total BNDES value in dataset: R$ ", fmt_m(BNDES_TOTAL), "M"),
  "",
  "---",
  "",
  "## 2. XX Sub-section Breakdown",
  "",
  paste0(
    "| Section | Label | Firm-years | Employment | ",
    "BNDES value (R$ M) | % of all BNDES |"
  ),
  paste0(
    "|---------|-------|-----------|-----------|",
    "--------------------|----------------|"
  ),
  xx_tbl_rows,
  "",
  paste0("**Interpretation:** ", interp_xx),
  "",
  "---",
  "",
  "## 3. Active Block Summary",
  "",
  "| Block | Firm-years | Employment | BNDES value (R$ M) | % of all BNDES |",
  "|-------|-----------|-----------|--------------------|----|",
  active_block_rows,
  "",
  "---",
  "",
  "## 4. Geographic Concentration of XX",
  "",
  "### By State (top 10 by XX firm-year share)",
  "",
  "| State ID | Total firm-years | XX share of firm-years (%) | XX share of employment (%) |",
  "|----------|-----------------|---------------------------|---------------------------|",
  state_tbl_rows,
  "",
  "### By Municipality Size Quartile",
  "",
  "| Quartile | Total firm-years | XX share of firm-years (%) | XX share of employment (%) |",
  "|----------|-----------------|---------------------------|---------------------------|",
  muni_tbl_rows,
  "",
  paste0("**Interpretation:** ", interp_geo),
  "",
  "---",
  "",
  "## 5. Implications for Instrument Validity",
  "",
  interp_iv,
  "",
  "---",
  "",
  "## 6. Files Produced",
  "",
  "| File | Rows | Description |",
  "|------|------|-------------|",
  "| cnae_section_summary.csv | 21 | One row per CNAE section A-U |",
  "| policy_block_summary.csv | 5 | One row per policy block |",
  "| xx_subsection_summary.csv | 4 | K, O, T, U detail |",
  "| geographic_by_state.csv | varies | XX share by Brazilian state |",
  "| geographic_by_muni_size.csv | 4 | XX share by muni employment quartile |",
  ""
)

writeLines(report_lines,
           file.path(OUTPUT_DIR, "cnae_coverage_report.md"))
message("  Written: cnae_coverage_report.md")

# ------------------------------------------------------------------------------
# 12. Print console summary
# ------------------------------------------------------------------------------
message("\n")
message("=================================================================")
message("  CNAE Coverage Audit — Summary")
message("=================================================================")
message(sprintf("  Total firm-years            : %s",
                format(n_total_fy, big.mark = ",")))
message(sprintf("  Active blocks (Agro/Ind/Infra/Serv): %s  (%.1f%%)",
                format(n_active_fy, big.mark = ","), pct_active))
message(sprintf("  XX (residual K/O/T/U)       : %s  (%.1f%%)",
                format(n_xx_fy,     big.mark = ","), pct_xx))
message(sprintf("  Total BNDES value           : R$ %.1fM", BNDES_TOTAL / 1e6))
message("")
message("  Policy-block BNDES value breakdown:")

for (i in seq_len(nrow(block_summary))) {
  r <- block_summary[i]
  message(sprintf("    %-6s : R$ %8.1fM  (%5.2f%% of BNDES)",
                  r$policy_block,
                  r$total_bndes_value / 1e6,
                  fifelse(is.na(r$pct_bndes_value), 0, r$pct_bndes_value)))
}

message("")
message("  XX sub-section firm-year shares:")
for (i in seq_len(nrow(xx_sub_summary))) {
  r <- xx_sub_summary[i]
  message(sprintf("    %s (%s): %s firm-years  (%.2f%% of total)",
                  r$cnae_section,
                  r$cnae_section_label,
                  format(r$n_firm_years, big.mark = ","),
                  r$pct_firm_years))
}

message("")
message("  Muni employment-quartile XX share:")
for (i in seq_len(nrow(muni_size_summary))) {
  r <- muni_size_summary[i]
  message(sprintf("    %s : %.1f%% of firm-years are XX",
                  r$quartile_label, r$xx_share_firm_years))
}

message("")
message("  Output files written to:")
message("    ", OUTPUT_DIR)
message("=================================================================")
