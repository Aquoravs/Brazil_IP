#!/usr/bin/env Rscript
# ==============================================================================
# 02_build_instruments_ec.R — stack Variant A weights into Z and EC.
#
#   Z^c_{jmt}              = sum_p w_tilde^{c,own}_{jmp,t} * Align^c_{mpt}
#   widetilde_EC^c_{jm,t}  = sum_p w_tilde^{c,own}_{jmp,t}
#
# Channels:
#   M   -> align_mayor_coalition
#   MP  -> align_mayor_pres_coalition
#   MG  -> align_mayor_gov_coalition
#   MGP -> align_triple_coalition
#
# CLI:   --tax={policy_block, size_bin}
# Out:   output/Z_variant_a_<tax>.qs2  (muni, year, channel, sector, Z_val)
#        output/EC_variant_a_<tax>.qs2 (muni, year, channel, sector, EC_val)
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

# --- Load weights ----------------------------------------------------------

w_path <- file.path(OUT, sprintf("weights_variant_a_%s.qs2", TAX))
stopifnot(file.exists(w_path))
w <- qs_read(w_path); setDT(w)
message(sprintf("[INFO] weights rows: %s", format(nrow(w), big.mark = ",")))

# --- Load alignment shocks -------------------------------------------------

al <- qs_read(file.path(DATA, "alignment_shocks.qs2")); setDT(al)
al[, muni_id := as.integer(muni_id)]
al[, year    := as.integer(year)]
# Slim to needed columns only.
align_cols <- c("align_mayor_coalition", "align_mayor_pres_coalition",
                "align_mayor_gov_coalition", "align_triple_coalition")
stopifnot(all(align_cols %in% names(al)))
al <- al[, c("muni_id", "party", "year", align_cols), with = FALSE]
message(sprintf("[INFO] alignment rows: %s", format(nrow(al), big.mark = ",")))

# --- Per-channel: join weights × alignment, then sum over party ----------

CHANNELS <- c("M", "MP", "MG", "MGP")
Z_list  <- vector("list", length(CHANNELS))
EC_list <- vector("list", length(CHANNELS))

for (i in seq_along(CHANNELS)) {
  c_lab <- CHANNELS[[i]]
  align_col <- channel_align_col(c_lab)
  wc <- w[channel == c_lab,
          .(muni_id, year, sector, party, w_tilde)]
  if (!nrow(wc)) {
    message(sprintf("[WARN] channel %s: no weights", c_lab)); next
  }
  # Join on (muni_id, party, year)
  alc <- al[, c("muni_id", "party", "year", align_col), with = FALSE]
  setnames(alc, align_col, "Align")
  wj <- merge(wc, alc, by = c("muni_id", "party", "year"),
              all.x = TRUE, all.y = FALSE)
  wj[is.na(Align), Align := 0]
  # Z and EC aggregation over party (within muni-year-sector).
  zg <- wj[, .(Z_val  = sum(w_tilde * Align, na.rm = TRUE),
               EC_val = sum(w_tilde, na.rm = TRUE)),
           by = .(muni_id, year, sector)]
  zg[, channel := c_lab]
  Z_list[[i]]  <- zg[, .(muni_id, year, channel, sector, Z_val)]
  EC_list[[i]] <- zg[, .(muni_id, year, channel, sector, EC_val)]
  message(sprintf("[INFO] channel=%s: %s muni-year-sector cells",
                  c_lab, format(nrow(zg), big.mark = ",")))
}

Z_dt  <- rbindlist(Z_list,  use.names = TRUE)
EC_dt <- rbindlist(EC_list, use.names = TRUE)

# --- Invariant check: sum_j EC^c_{jm,t} in {0, 1} ------------------------

inv <- EC_dt[, .(sum_EC = sum(EC_val)),
             by = .(muni_id, year, channel)]
n_bad <- nrow(inv[abs(sum_EC - 1) > 1e-6 & abs(sum_EC) > 1e-6])
n_unit <- nrow(inv[abs(sum_EC - 1) <= 1e-6])
message(sprintf("[INFO] EC invariant: n_unit=%d n_bad=%d", n_unit, n_bad))
if (n_bad > 0L) {
  message("[WARN] EC invariant violated; sample bad rows:")
  print(head(inv[abs(sum_EC - 1) > 1e-6 & abs(sum_EC) > 1e-6], 5))
}

# --- Save ------------------------------------------------------------------

qs_save(Z_dt,  file.path(OUT, sprintf("Z_variant_a_%s.qs2",  TAX)))
qs_save(EC_dt, file.path(OUT, sprintf("EC_variant_a_%s.qs2", TAX)))
message(sprintf("[INFO] wrote Z_variant_a_%s.qs2 and EC_variant_a_%s.qs2",
                TAX, TAX))
message(sprintf("[INFO] %s | done.", Sys.time()))
