#!/usr/bin/env Rscript
# ==============================================================================
# 01_build_variant_a_weights.R — Variant A (muni-relative owner share) weights
# under the pre-earliest-election window (Variant F timing).
#
# Math (eq:w-own-rel from ar_test_specification.tex §2.3):
#   bar L^c_{jmp,t}       = sum_{s in T^{F,c}_t} sum_{f in F(j,m)} L_{f,p,s}
#   bar L^{c,affil}_{m,t} = sum_{j'} sum_{p'} bar L^c_{j'mp',t}
#   w_tilde^{c,own}_{jmp,t} = bar L^c_{jmp,t} / bar L^{c,affil}_{m,t}
#
# CLI:   --tax={policy_block, size_bin}
# Out:   output/weights_variant_a_<tax>.qs2 with cols
#          muni_id, year, channel, sector, party, w_tilde, T_Fc_lo, T_Fc_hi
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
  fp <- vapply(sys.frames(), function(env) {
    of <- env$ofile
    if (is.null(of) || !nzchar(of)) return(NA_character_)
    of
  }, character(1))
  fp <- fp[!is.na(fp)]
  if (length(fp)) return(normalizePath(fp[[length(fp)]],
                                       winslash = "/", mustWork = TRUE))
  stop("Cannot determine script path. Run via Rscript.")
}
THIS  <- get_this_script()
BR    <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
ROOT  <- normalizePath(file.path(BR, "..", "..", ".."), winslash = "/", mustWork = TRUE)
DATA  <- file.path(ROOT, "data", "processed")
OUT   <- file.path(BR, "output")
if (!dir.exists(OUT)) dir.create(OUT, recursive = TRUE)

source(file.path(BR, "R", "00_helpers.R"))

# --- CLI ---
cli <- commandArgs(trailingOnly = TRUE)
parse_kv <- function(flag, default) {
  hit <- grep(paste0("^", flag, "="), cli, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", flag, "="), "", hit[[1L]])
}
TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% TAXONOMIES)
message(sprintf("[INFO] %s | tax=%s", Sys.time(), TAX))

# Taxonomy families: policy_block is cnae_section-level (sector attached once);
# size_bin and policy_block_size_bin are firm x cycle-level (sector attached
# inside the cycle/year loop). The crossed taxonomy reuses the size_bin path.
TAX_CYCLE_LEVEL <- TAX %in% c("size_bin", "policy_block_size_bin")

# --- Load primitives -------------------------------------------------------

message("[INFO] loading owner_aff_standardized.qs2 ...")
oa <- qs_read(file.path(DATA, "owner_aff_standardized.qs2"))
setDT(oa)
oa[, muni_id := as.integer(muni_id)]
oa[, year    := as.integer(year)]
oa[, firm_id := as.integer(firm_id)]
# Drop "No party" (only counts politically-affiliated owners — spec definition
# of bar L^{c,affil}_{m,t}: "owner-years affiliated with any party").
oa <- oa[party != "No party"]
message(sprintf("[INFO] owner_aff filtered (party!='No party'): %s rows",
                format(nrow(oa), big.mark = ",")))

message("[INFO] loading firm_panel_for_regs.qs2 (firm-muni-year-sector)...")
fp <- qs_read(file.path(DATA, "firm_panel_for_regs.qs2"))
setDT(fp)
fp <- fp[, .(firm_id = as.integer(firm_id),
             muni_id = as.integer(muni_id),
             year    = as.integer(year),
             cnae_section = as.character(cnae_section))]
fp <- fp[!is.na(cnae_section) & nzchar(cnae_section)]
message(sprintf("[INFO] firm_panel slim: %s rows",
                format(nrow(fp), big.mark = ",")))

# --- Taxonomy attachment ---------------------------------------------------

if (identical(TAX, "policy_block")) {
  pb <- qs_read(file.path(DATA, "policy_block_mapping.qs2"))
  setDT(pb)
  # Drop XX (Residual) sectors per the plan (K=4 = Agro/Ind/Infra/Serv).
  pb <- pb[policy_block != "XX"]
  fp <- merge(fp, pb[, .(cnae_section, sector = policy_block)],
              by = "cnae_section", all.x = FALSE, all.y = FALSE)
  fp[, cnae_section := NULL]
  setkeyv(fp, c("firm_id", "muni_id", "year"))
  message(sprintf("[INFO] firm_panel after policy_block attach: %s rows",
                  format(nrow(fp), big.mark = ",")))
} else {
  # size_bin / policy_block_size_bin: firm-cycle-level. size_bin is attached
  # AT THE CYCLE LEVEL inside the loop below to keep cell membership
  # cycle-correct. For the crossed taxonomy we additionally hold the firm's
  # cnae_section -> policy_block on fp (cnae_section is time-invariant) and
  # cross it with the cycle-specific size_bin inside the loop.
  sb_full <- qs_read(file.path(DATA, "size_bin_mapping.qs2"))
  setDT(sb_full)
  sb_full[, firm_id := as.integer(firm_id)]
  sb_full[, election_cycle := as.integer(election_cycle)]
  sb_full[, size_bin := as.integer(size_bin)]
  sb_full <- sb_full[, .(firm_id, election_cycle, size_bin)]
  message(sprintf("[INFO] size_bin_mapping: %s firm-cycle rows",
                  format(nrow(sb_full), big.mark = ",")))
  if (identical(TAX, "policy_block_size_bin")) {
    # C1: crossed group = policy_block x size_bin. Attach policy_block to fp
    # via cnae_section now; size_bin is attached per cycle in the loop.
    pb <- qs_read(file.path(DATA, "policy_block_mapping.qs2"))
    setDT(pb)
    pb <- pb[policy_block != "XX"]
    fp <- merge(fp, pb[, .(cnae_section, policy_block)],
                by = "cnae_section", all.x = FALSE, all.y = FALSE)
    fp[, cnae_section := NULL]
    setkeyv(fp, c("firm_id", "muni_id", "year"))
    message(sprintf("[INFO] firm_panel after policy_block attach (crossed): %s rows",
                    format(nrow(fp), big.mark = ",")))
  }
}

# --- Cycle assignment rule for size_bin -----------------------------------

# size_bin cycles: 2005, 2007, 2009, 2011, 2013, 2015, 2017.
# For a year y, use max(cycle <= y). Fallback to 2005 if y < 2005.
SIZE_CYCLES <- c(2005L, 2007L, 2009L, 2011L, 2013L, 2015L, 2017L)
cycle_for_year <- function(y) {
  cyc <- SIZE_CYCLES[SIZE_CYCLES <= y]
  if (length(cyc) == 0L) return(SIZE_CYCLES[1L])
  max(cyc)
}

# --- Precompute the join firm×muni×year × sector × party ------------------
# For policy_block: precompute the muni-year-sector-party aggregate ONCE.
# For size_bin: the size_bin assignment is year-dependent (via cycle), so
# we precompute the (firm, year, muni, party, aff_owners) and attach
# size_bin inside the cycle/year loop.

if (identical(TAX, "policy_block")) {
  message("[INFO] joining owner_aff to firm_panel (policy_block) ...")
  setkeyv(oa, c("firm_id", "muni_id", "year"))
  setkeyv(fp, c("firm_id", "muni_id", "year"))
  joined <- oa[fp, nomatch = 0L,
               on = c("firm_id", "muni_id", "year"),
               allow.cartesian = TRUE]
  # joined now has cols: firm_id, muni_id, year, party, share_aff_owners,
  # aff_owners, sector
  message(sprintf("[INFO] joined rows: %s", format(nrow(joined), big.mark = ",")))
  # Aggregate to (muni_id, year, sector, party) → sum_aff_owners
  agg_year <- joined[, .(L = sum(aff_owners, na.rm = TRUE)),
                     by = .(muni_id, year, sector, party)]
  agg_year <- agg_year[L > 0]
  rm(joined); gc(verbose = FALSE)
  message(sprintf("[INFO] muni-year-sector-party aggregate: %s rows",
                  format(nrow(agg_year), big.mark = ",")))
  setkeyv(agg_year, c("year", "muni_id"))
} else {
  message(sprintf("[INFO] joining owner_aff to firm_panel (%s)...", TAX))
  # Slim joined first by year and add sector PER CYCLE.
  # Strategy: pre-join owner_aff and firm_panel on (firm, muni, year);
  # then within each cycle window we attach size_bin via cycle.
  # For policy_block_size_bin we carry policy_block (time-invariant) on the
  # join and cross it with the cycle-specific size_bin inside the loop.
  setkeyv(oa, c("firm_id", "muni_id", "year"))
  if (identical(TAX, "policy_block_size_bin")) {
    fp_slim <- fp[, .(firm_id, muni_id, year, policy_block)]
  } else {
    fp_slim <- fp[, .(firm_id, muni_id, year)]
  }
  setkeyv(fp_slim, c("firm_id", "muni_id", "year"))
  joined <- oa[fp_slim, nomatch = 0L,
               on = c("firm_id", "muni_id", "year"),
               allow.cartesian = TRUE]
  if (identical(TAX, "policy_block_size_bin")) {
    joined <- joined[, .(firm_id, muni_id, year, party, policy_block,
                         aff_owners = as.numeric(aff_owners))]
    joined <- joined[, .(aff_owners = sum(aff_owners, na.rm = TRUE)),
                     by = .(firm_id, muni_id, year, party, policy_block)]
  } else {
    joined <- joined[, .(firm_id, muni_id, year, party,
                         aff_owners = as.numeric(aff_owners))]
    # Sum aff_owners by (firm_id, year, muni_id, party) — safe collapse if
    # there are duplicate firm-year-muni rows from multi-section firms.
    joined <- joined[, .(aff_owners = sum(aff_owners, na.rm = TRUE)),
                     by = .(firm_id, muni_id, year, party)]
  }
  message(sprintf("[INFO] firm-year-party aggregate: %s rows",
                  format(nrow(joined), big.mark = ",")))
  setkeyv(joined, c("firm_id", "year"))
}

# --- Build the (channel, year_t) calendar --------------------------------

YEARS <- 2002:2017
# Seven channels (B1): three mains, three pairs, one triple. The original
# four (M, MP, MG, MGP) are a subset, so downstream four-channel consumers
# still find their columns.
CHANNELS <- all_channels()
cal <- build_channel_calendar(years = YEARS, channels = CHANNELS)
setDT(cal)
message("\n[INFO] channel × year calendar (Variant F windows):")
print(cal[year %in% c(2002, 2008, 2010, 2011, 2012, 2014, 2017)])

# --- Core loop: per (channel, t) → bar L → w_tilde -----------------------

build_weights_for_cell <- function(channel, t, T_lo, T_hi) {
  if (is.na(T_lo) || is.na(T_hi)) {
    return(data.table(muni_id = integer(), sector = character(),
                      party = character(), w_tilde = numeric()))
  }
  yrs <- T_lo:T_hi
  if (identical(TAX, "policy_block")) {
    sub <- agg_year[year %in% yrs]
    if (!nrow(sub)) return(data.table(muni_id = integer(),
                                       sector = character(),
                                       party = character(),
                                       w_tilde = numeric()))
    num <- sub[, .(L = sum(L, na.rm = TRUE)),
               by = .(muni_id, sector, party)]
  } else {
    # size_bin / policy_block_size_bin path: attach size_bin via cycle(t),
    # then aggregate. For the crossed taxonomy the sector is the
    # "<policy_block>_<size_bin>" pair carried on joined plus the cycle bin.
    cyc <- cycle_for_year(t)
    sb_t <- sb_full[election_cycle == cyc, .(firm_id, size_bin)]
    setkeyv(sb_t, "firm_id")
    sub <- joined[year %in% yrs]
    sub <- merge(sub, sb_t, by = "firm_id",
                 all.x = FALSE, all.y = FALSE)
    if (!nrow(sub)) return(data.table(muni_id = integer(),
                                       sector = character(),
                                       party = character(),
                                       w_tilde = numeric()))
    if (identical(TAX, "policy_block_size_bin")) {
      sub[, sector := paste0(policy_block, "_", size_bin)]
    } else {
      sub[, sector := as.character(size_bin)]
    }
    num <- sub[, .(L = sum(aff_owners, na.rm = TRUE)),
               by = .(muni_id, sector, party)]
  }
  num <- num[L > 0]
  # Muni-level denom — sum over all sectors and all parties in the muni.
  denom <- num[, .(L_affil = sum(L, na.rm = TRUE)), by = muni_id]
  out <- merge(num, denom, by = "muni_id", all.x = TRUE)
  out[, w_tilde := L / L_affil]
  out[, c("L", "L_affil") := NULL]
  out[]
}

all_w <- vector("list", nrow(cal))
for (i in seq_len(nrow(cal))) {
  row <- cal[i]
  channel <- row$channel
  t       <- row$year
  T_lo    <- row$T_lo
  T_hi    <- row$T_hi
  if (is.na(T_lo) || is.na(T_hi)) {
    all_w[[i]] <- data.table()
    next
  }
  w <- build_weights_for_cell(channel, t, T_lo, T_hi)
  if (!nrow(w)) {
    all_w[[i]] <- data.table()
    next
  }
  w[, `:=`(year = t, channel = channel,
           T_Fc_lo = T_lo, T_Fc_hi = T_hi)]
  setcolorder(w, c("muni_id", "year", "channel", "sector",
                   "party", "w_tilde", "T_Fc_lo", "T_Fc_hi"))
  all_w[[i]] <- w
  message(sprintf("[INFO] channel=%s t=%d window=[%d,%d] cells=%s",
                  channel, t, T_lo, T_hi,
                  format(nrow(w), big.mark = ",")))
}

weights_dt <- rbindlist(all_w, use.names = TRUE)
message(sprintf("\n[INFO] total weights rows: %s",
                format(nrow(weights_dt), big.mark = ",")))

# --- Invariant check: sum_{j,p} w_tilde in {0, 1} -------------------------

inv_check <- weights_dt[, .(sum_w = sum(w_tilde)),
                        by = .(muni_id, year, channel)]
n_bad <- nrow(inv_check[abs(sum_w - 1) > 1e-6 & abs(sum_w) > 1e-6])
n_unit <- nrow(inv_check[abs(sum_w - 1) <= 1e-6])
n_zero <- nrow(inv_check[abs(sum_w) <= 1e-6])
message(sprintf("[INFO] invariant sum_w in {0,1}: n_unit=%d  n_zero=%d  n_bad=%d",
                n_unit, n_zero, n_bad))
if (n_bad > 0L) {
  message("[WARN] some muni-year-channel cells violate the invariant; ",
          "sample of bad rows:")
  print(head(inv_check[abs(sum_w - 1) > 1e-6 & abs(sum_w) > 1e-6], 10))
}

# --- Save ------------------------------------------------------------------

out_path <- file.path(OUT, sprintf("weights_variant_a_%s.qs2", TAX))
qs_save(weights_dt, out_path)
message(sprintf("[INFO] wrote: %s", out_path))

message(sprintf("[INFO] %s | done.", Sys.time()))
