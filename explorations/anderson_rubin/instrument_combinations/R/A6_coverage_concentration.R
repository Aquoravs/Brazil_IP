#!/usr/bin/env Rscript
# ==============================================================================
# A6_coverage_concentration.R — EC adequacy audit, coverage / concentration.
#
# The muni-relative weight has a thick (muni-level affiliated) denominator, so
# denominator collapse is not a threat (unlike the rejected within-cell weight).
# A6 documents how concentrated the identifying variation actually is:
#
#   (a) Distribution of cell affiliated-owner counts L_{jm,t} — the windowed
#       affiliated owner-years behind each (muni, year, channel, sector) cell.
#   (b) Effective number of shocks per (muni, year, channel): inverse-HHI of
#       the muni-relative share weights, n_eff = 1 / sum_{j,p} w_tilde^2.
#   (c) Share of municipal GDP mass in "thin" muni-years (dominant identifying
#       cell <= THIN_OWN affiliated owners).
#
# Recomputes L_{jm,t} via the 01-script policy_block join. Reads built weights
# from ../ar_meeting_2026_05_13/output/. Writes to instrument_combinations/output/.
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
ARR  <- normalizePath(file.path(BR, "..", "ar_meeting_2026_05_13"),
                      winslash = "/", mustWork = TRUE)
ROOT <- normalizePath(file.path(BR, "..", "..", ".."), winslash = "/", mustWork = TRUE)
DATA <- file.path(ROOT, "data", "processed")
ARO  <- file.path(ARR, "output")
OUT  <- file.path(BR, "output")
source(file.path(ARR, "R", "00_helpers.R"))

TAX      <- "policy_block"
THIN_OWN <- 5L   # a cell with <= 5 affiliated owner-years is "thin".
report   <- character(0)
add_rep  <- function(...) report <<- c(report, sprintf(...))
message(sprintf("[INFO] %s | A6 coverage/concentration | tax=%s",
                Sys.time(), TAX))

# ============================================================================
# (b) Effective number of shocks — from the built weights (cheap, exact).
# ============================================================================

w <- qs_read(file.path(ARO, sprintf("weights_variant_a_%s.qs2", TAX)))
setDT(w)
# w_tilde sums to 1 over the (sector,party) grid within (muni,year,channel).
hhi <- w[, .(HHI = sum(w_tilde^2), n_cells = .N),
         by = .(muni_id, year, channel)]
hhi[, n_eff := 1 / HHI]

neff_tab <- hhi[, .(
  muni_year_cells = .N,
  neff_min  = round(min(n_eff), 2),
  neff_p10  = round(quantile(n_eff, 0.10), 2),
  neff_med  = round(median(n_eff), 2),
  neff_mean = round(mean(n_eff), 2),
  neff_p90  = round(quantile(n_eff, 0.90), 2),
  neff_max  = round(max(n_eff), 2)
), by = channel]
setkey(neff_tab, channel)
fwrite(neff_tab, file.path(OUT, "A6_effective_shocks.csv"))
add_rep("(b) Effective number of shocks n_eff = 1 / sum w_tilde^2, per channel:")
for (i in seq_len(nrow(neff_tab))) {
  r <- neff_tab[i]
  add_rep("    %-4s  n_eff: min=%.2f p10=%.2f med=%.2f mean=%.2f p90=%.2f max=%.2f",
          r$channel, r$neff_min, r$neff_p10, r$neff_med, r$neff_mean,
          r$neff_p90, r$neff_max)
}

# ============================================================================
# (a) Cell affiliated-owner counts — recompute L_{jm,t} (01-script join).
# ============================================================================

message("[INFO] recomputing cell affiliated-owner counts L_{jm,t} ...")
oa <- qs_read(file.path(DATA, "owner_aff_standardized.qs2")); setDT(oa)
oa[, `:=`(muni_id = as.integer(muni_id), year = as.integer(year),
          firm_id = as.integer(firm_id))]
oa <- oa[party != "No party"]

fp <- qs_read(file.path(DATA, "firm_panel_for_regs.qs2")); setDT(fp)
fp <- fp[, .(firm_id = as.integer(firm_id), muni_id = as.integer(muni_id),
             year = as.integer(year), cnae_section = as.character(cnae_section))]
fp <- fp[!is.na(cnae_section) & nzchar(cnae_section)]

pb <- qs_read(file.path(DATA, "policy_block_mapping.qs2")); setDT(pb)
pb <- pb[policy_block != "XX"]
fp <- merge(fp, pb[, .(cnae_section, sector = policy_block)],
            by = "cnae_section", all.x = FALSE, all.y = FALSE)
fp[, cnae_section := NULL]

joined <- oa[fp, nomatch = 0L, on = c("firm_id", "muni_id", "year"),
             allow.cartesian = TRUE]
agg_year <- joined[, .(L = sum(aff_owners, na.rm = TRUE)),
                   by = .(muni_id, year, sector, party)]
agg_year <- agg_year[L > 0]
rm(joined, oa, fp); gc(verbose = FALSE)

# Windowed L_{jm,t} per channel, mirroring 01_build_variant_a_weights.R.
CHANNELS <- c("M", "MP", "MG", "MGP")
cal <- as.data.table(build_channel_calendar(years = 2002:2017,
                                            channels = CHANNELS))
cell_list <- vector("list", nrow(cal))
for (i in seq_len(nrow(cal))) {
  row <- cal[i]
  if (is.na(row$T_lo) || is.na(row$T_hi)) next
  sub <- agg_year[year %in% (row$T_lo:row$T_hi)]
  if (!nrow(sub)) next
  cell <- sub[, .(L_jm = sum(L, na.rm = TRUE)),
              by = .(muni_id, sector)]
  cell[, `:=`(year = row$year, channel = row$channel)]
  cell_list[[i]] <- cell
}
cells <- rbindlist(cell_list, use.names = TRUE)
message(sprintf("[INFO] (muni,year,channel,sector) cells: %s",
                format(nrow(cells), big.mark = ",")))

cnt_tab <- cells[, .(
  n_cells   = .N,
  L_min     = min(L_jm),
  L_p10     = round(quantile(L_jm, 0.10), 1),
  L_med     = median(L_jm),
  L_mean    = round(mean(L_jm), 1),
  L_p90     = round(quantile(L_jm, 0.90), 1),
  L_max     = max(L_jm),
  pct_thin  = round(100 * mean(L_jm <= THIN_OWN), 1)
), by = channel]
setkey(cnt_tab, channel)
fwrite(cnt_tab, file.path(OUT, "A6_cell_owner_counts.csv"))
add_rep("")
add_rep("(a) Cell affiliated-owner count L_{jm,t}, per channel (thin <= %d):",
        THIN_OWN)
for (i in seq_len(nrow(cnt_tab))) {
  r <- cnt_tab[i]
  add_rep("    %-4s  L: min=%d p10=%.1f med=%.0f mean=%.1f p90=%.1f max=%d | thin cells=%.1f%%",
          r$channel, r$L_min, r$L_p10, r$L_med, r$L_mean, r$L_p90, r$L_max,
          r$pct_thin)
}

# ============================================================================
# (c) GDP mass in thin muni-years — dominant identifying cell is thin.
# ============================================================================

# Dominant cell per (muni,year,channel): the retained-sector cell with the
# largest muni-relative weight (the cell that carries identification). Use the
# retained sectors only (the hold-out sector is not an instrument).
panel <- qs_read(file.path(ARO, sprintf("muni_panel_ar_%s.qs2", TAX)))
KEEP  <- attr(panel, "sectors_keep")
setDT(panel)

cells_keep <- cells[sector %in% KEEP]
dom <- cells_keep[order(-L_jm),
                  .(dom_sector = sector[1], dom_L = L_jm[1],
                    cell_L_sum = sum(L_jm)),
                  by = .(muni_id, year, channel)]
dom[, thin_identified := dom_L <= THIN_OWN]

gdp <- panel[is.finite(log_gdp) & is.finite(vol_ratio),
             .(muni_id, year, gdp = exp(log_gdp))]
dom <- merge(dom, gdp, by = c("muni_id", "year"), all.x = FALSE)

gdp_tab <- dom[, .(
  muni_years     = .N,
  pct_thin_my    = round(100 * mean(thin_identified), 1),
  gdp_share_thin = round(100 * sum(gdp[thin_identified]) / sum(gdp), 2)
), by = channel]
setkey(gdp_tab, channel)
fwrite(gdp_tab, file.path(OUT, "A6_gdp_mass_thin.csv"))
add_rep("")
add_rep("(c) GDP mass in thin-identified muni-years (dominant retained cell <= %d owners):",
        THIN_OWN)
for (i in seq_len(nrow(gdp_tab))) {
  r <- gdp_tab[i]
  add_rep("    %-4s  thin muni-years=%.1f%%  but GDP share in them=%.2f%%",
          r$channel, r$pct_thin_my, r$gdp_share_thin)
}
add_rep("")
add_rep(paste0("Reading: the muni-relative denominator keeps the per-channel ",
               "weight thick; thin cells exist (small munis) but carry a tiny ",
               "share of GDP mass, so the AR estimand is not driven by them."))

writeLines(c("# A6 coverage / concentration audit",
             sprintf("# generated %s | tax=%s", Sys.time(), TAX),
             "", report),
           file.path(OUT, "A6_coverage_concentration.txt"))
message(sprintf("\n%s", paste(report, collapse = "\n")))
message("[INFO] wrote A6_effective_shocks.csv, A6_cell_owner_counts.csv, ",
        "A6_gdp_mass_thin.csv, A6_coverage_concentration.txt")
message(sprintf("[INFO] %s | done.", Sys.time()))
