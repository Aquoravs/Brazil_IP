#!/usr/bin/env Rscript
# ==============================================================================
# 03_build_muni_ar_panel.R — assemble the muni-year wide panel for the AR
# regression: log_gdp, vol_ratio, Z and EC columns per channel × sector.
#
# vol_ratio_mt = total_bndes_real_mt / pib_real_{m, 2002}
#   pib_real_{m, 2002} is recovered as exp(log_gdp) at year 2002 per muni.
#
# Hold-out sector: drop the highest-mean-share sector to keep unit-norm.
# Hold-out source: emp_share_panel_<emp_tax>.qs2 (contemporaneous variant).
#
# CLI:  --tax={policy_block, size_bin}
# Out:  output/muni_panel_ar_<tax>.qs2
#       output/holdout_<tax>.csv (lists the dropped sector and its mean share)
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})
setDTthreads(0L)

get_this_script <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (length(fa)) return(normalizePath(sub("^--file=", "", fa[[1L]]),
                                       winslash = "/", mustWork = TRUE))
  stop("Run via Rscript.")
}
THIS <- get_this_script()
BR   <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
ROOT <- normalizePath(file.path(BR, "..", "..", ".."), winslash = "/", mustWork = TRUE)
DATA <- file.path(ROOT, "data", "processed")
OUT  <- file.path(BR, "output")
source(file.path(BR, "R", "00_helpers.R"))

cli <- commandArgs(trailingOnly = TRUE)
parse_kv <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), cli, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", flag, "="), "", hit[[1L]])
}
TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "size_bin"))
message(sprintf("[INFO] %s | tax=%s", Sys.time(), TAX))

# --- Load Z and EC --------------------------------------------------------

Z  <- qs_read(file.path(OUT, sprintf("Z_variant_a_%s.qs2",  TAX))); setDT(Z)
EC <- qs_read(file.path(OUT, sprintf("EC_variant_a_%s.qs2", TAX))); setDT(EC)
message(sprintf("[INFO] Z rows: %s; EC rows: %s",
                format(nrow(Z), big.mark = ","), format(nrow(EC), big.mark = ",")))

# --- Determine hold-out sector --------------------------------------------

# For policy_block, the existing panel emp_share_panel_policy_block has
# s_emp_mjt computed via 32c. We use mean share to pick the largest.
# For size_bin, no precomputed share panel exists; we derive the largest
# share within size_bin from the firm panel.

if (identical(TAX, "policy_block")) {
  emp <- qs_read(file.path(DATA, "emp_share_panel_policy_block.qs2")); setDT(emp)
  emp[, sector := as.character(policy_block)]
  share_summary <- emp[!is.na(s_emp_mjt) & sector != "XX",
                       .(mean_share = mean(s_emp_mjt, na.rm = TRUE)),
                       by = sector]
} else {
  # Compute size_bin mean shares from firm panel + size_bin mapping.
  message("[INFO] computing size_bin mean shares from firm_panel ...")
  fp <- qs_read(file.path(DATA, "firm_panel_for_regs.qs2")); setDT(fp)
  fp <- fp[, .(firm_id = as.integer(firm_id),
               muni_id = as.integer(muni_id),
               year    = as.integer(year),
               n_employees)]
  sb <- qs_read(file.path(DATA, "size_bin_mapping.qs2")); setDT(sb)
  # Match year -> cycle (max cycle <= year, fallback to 2005)
  SIZE_CYCLES <- c(2005L, 2007L, 2009L, 2011L, 2013L, 2015L, 2017L)
  fp[, election_cycle := pmax(SIZE_CYCLES[1L],
                              vapply(year, function(y) {
                                cs <- SIZE_CYCLES[SIZE_CYCLES <= y]
                                if (length(cs) == 0L) SIZE_CYCLES[1L]
                                else max(cs)
                              }, integer(1)))]
  sb[, election_cycle := as.integer(election_cycle)]
  sb[, firm_id := as.integer(firm_id)]
  sb[, size_bin := as.integer(size_bin)]
  fp <- merge(fp, sb[, .(firm_id, election_cycle, size_bin)],
              by = c("firm_id", "election_cycle"),
              all.x = FALSE)
  # Muni-year-sector employment.
  njmt <- fp[!is.na(n_employees), .(n_jmt = sum(n_employees, na.rm = TRUE)),
             by = .(muni_id, year, size_bin)]
  njmt[, sector := as.character(size_bin)]
  nmt  <- njmt[, .(n_mt = sum(n_jmt, na.rm = TRUE)), by = .(muni_id, year)]
  njmt <- merge(njmt, nmt, by = c("muni_id", "year"))
  njmt[, s := n_jmt / n_mt]
  share_summary <- njmt[!is.na(s), .(mean_share = mean(s, na.rm = TRUE)),
                        by = sector]
  rm(fp, sb, njmt, nmt); gc(verbose = FALSE)
}
setorder(share_summary, -mean_share)
holdout <- share_summary$sector[1L]
fwrite(share_summary, file.path(OUT, sprintf("holdout_%s.csv", TAX)))
message(sprintf("[INFO] hold-out sector for %s: %s (mean share = %.4f)",
                TAX, holdout, share_summary$mean_share[1L]))

sectors_keep <- sort(setdiff(unique(Z$sector), holdout))
message(sprintf("[INFO] keep sectors (K-1=%d): %s",
                length(sectors_keep), paste(sectors_keep, collapse = ", ")))

Z  <- Z [sector %in% sectors_keep]
EC <- EC[sector %in% sectors_keep]

# --- Reshape to wide ------------------------------------------------------

Z[,  col := paste0("Z_",  channel, "_", sector)]
EC[, col := paste0("EC_", channel, "_", sector)]

Z_wide  <- dcast(Z,  muni_id + year ~ col, value.var = "Z_val")
EC_wide <- dcast(EC, muni_id + year ~ col, value.var = "EC_val")
message(sprintf("[INFO] Z_wide: %d rows × %d cols; EC_wide: %d rows × %d cols",
                nrow(Z_wide), ncol(Z_wide), nrow(EC_wide), ncol(EC_wide)))

# Zero-fill missing Z/EC: a muni-year may have no entries for a (channel,
# sector) cell if the window was empty or had no aligned owners.
zero_fill_cols <- function(dt, prefix) {
  cols <- grep(paste0("^", prefix), names(dt), value = TRUE)
  for (cc in cols) {
    set(dt, i = which(is.na(dt[[cc]])), j = cc, value = 0)
  }
}
zero_fill_cols(Z_wide,  "Z_")
zero_fill_cols(EC_wide, "EC_")

# --- Load muni panel (log_gdp, total_bndes_real, year) -------------------

mp <- qs_read(file.path(DATA, "muni_panel_for_regs.qs2")); setDT(mp)
mp <- mp[, .(muni_id = as.integer(muni_id),
             year    = as.integer(year),
             log_gdp, total_bndes_real)]
mp <- mp[muni_id > 0L]

# pib_real_{m,2002}: derived from exp(log_gdp) at year 2002.
mp_2002 <- mp[year == 2002L & is.finite(log_gdp),
              .(pib_real_2002 = exp(log_gdp)), by = muni_id]
mp_2002 <- mp_2002[is.finite(pib_real_2002)]
message(sprintf("[INFO] munis with pib_real_2002: %s",
                format(nrow(mp_2002), big.mark = ",")))

mp <- merge(mp, mp_2002, by = "muni_id", all.x = TRUE)
mp[, vol_ratio := total_bndes_real / pib_real_2002]
mp[!is.finite(vol_ratio), vol_ratio := NA_real_]

# --- Merge ---------------------------------------------------------------

panel <- merge(mp, Z_wide,  by = c("muni_id", "year"), all.x = TRUE)
panel <- merge(panel, EC_wide, by = c("muni_id", "year"), all.x = TRUE)

# Zero-fill Z/EC for muni-years with no entries.
zero_fill_cols(panel, "Z_")
zero_fill_cols(panel, "EC_")

message(sprintf("[INFO] panel: %s rows; %d cols",
                format(nrow(panel), big.mark = ","), ncol(panel)))
message("[INFO] first cols: ",
        paste(head(names(panel), 8), collapse = ", "))

# --- Save -----------------------------------------------------------------

attr(panel, "holdout_sector") <- holdout
attr(panel, "sectors_keep")   <- sectors_keep
attr(panel, "taxonomy")       <- TAX

qs_save(panel, file.path(OUT, sprintf("muni_panel_ar_%s.qs2", TAX)))
message(sprintf("[INFO] wrote: muni_panel_ar_%s.qs2", TAX))
message(sprintf("[INFO] %s | done.", Sys.time()))
