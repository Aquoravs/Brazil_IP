#!/usr/bin/env Rscript
# ==============================================================================
# 00_helpers.R — channel windows, taxonomy switches, column-name helpers.
#
# Variant F (pre-earliest-election window) per office_specific_exposure_weights
# §3.2. For a channel c with offices O(c), define
#   e_{F,c}(t) = min_{l in O(c)} e_l(t)
#   T^{F,c}_t  = [e_{F,c}(t) - 4, e_{F,c}(t) - 1] cap [2002, 2017]
# where e_l(t) is the most recent election of office l on or before t.
#
# Brazilian electoral calendar inside the sample window:
#   mayoral: 2000, 2004, 2008, 2012, 2016
#   gov/pres (coincident from 1994): 2002, 2006, 2010, 2014
# ==============================================================================

# --- Election calendar -------------------------------------------------------

election_calendar <- list(
  mayor    = c(1996, 2000, 2004, 2008, 2012, 2016),
  governor = c(1998, 2002, 2006, 2010, 2014),
  pres     = c(1998, 2002, 2006, 2010, 2014)
)

# Most recent election of office l on or before year t.
e_office <- function(t, office) {
  cal <- election_calendar[[office]]
  el <- cal[cal <= t]
  if (length(el) == 0L) return(NA_integer_)
  as.integer(max(el))
}

# Channel-specific offices (mapping from channel label to vector of offices).
# Seven channels: three mains (M, G, P), three pairs (MG, MP, GP), one triple
# (MGP). The original four (M, MP, MG, MGP) are unchanged; G, P, GP are added.
channel_offices <- list(
  M       = "mayor",
  G       = "governor",
  P       = "pres",
  MP      = c("mayor", "pres"),
  MG      = c("mayor", "governor"),
  GP      = c("governor", "pres"),
  MGP     = c("mayor", "governor", "pres")
)

# The full seven-channel set, in main -> pair -> triple order. Helper scripts
# that want all channels read this; the original four-channel scripts keep
# their own hard-coded CHANNELS vector and are unaffected.
all_channels <- function() c("M", "G", "P", "MG", "MP", "GP", "MGP")

# Pre-earliest-election window for channel c at year t.
#   Returns list(lo, hi) — both integers, inclusive — clipped to [2002, 2017].
#   If the window is fully outside [2002, 2017], returns list(NA, NA).
T_Fc_window <- function(t, channel,
                        sample_lo = 2002L, sample_hi = 2017L) {
  offices <- channel_offices[[channel]]
  if (is.null(offices)) stop("Unknown channel: ", channel)
  e_each <- vapply(offices, function(off) e_office(t, off), integer(1))
  if (any(is.na(e_each))) return(list(lo = NA_integer_, hi = NA_integer_))
  e_min <- min(e_each)
  lo <- as.integer(e_min - 4L)
  hi <- as.integer(e_min - 1L)
  lo_cl <- max(lo, sample_lo)
  hi_cl <- min(hi, sample_hi)
  if (lo_cl > hi_cl) return(list(lo = NA_integer_, hi = NA_integer_))
  list(lo = lo_cl, hi = hi_cl)
}

# Build the (year, channel, lo, hi) calendar table for 2002..2017.
build_channel_calendar <- function(years = 2002:2017,
                                   channels = names(channel_offices)) {
  rows <- vector("list", length(years) * length(channels))
  k <- 1L
  for (t in years) for (c in channels) {
    w <- T_Fc_window(t, c)
    rows[[k]] <- data.frame(
      year = t, channel = c,
      e_Fc = if (is.na(w$lo)) NA_integer_ else (w$lo + 4L),
      T_lo = w$lo, T_hi = w$hi,
      stringsAsFactors = FALSE
    )
    k <- k + 1L
  }
  do.call(rbind, rows)
}

# --- Taxonomy loaders --------------------------------------------------------

# Valid taxonomy values. policy_block_size_bin (4 blocks x 3 size bins = 12
# crossed groups) is additive — the original two remain unchanged.
TAXONOMIES <- c("policy_block", "size_bin", "policy_block_size_bin")

load_taxonomy <- function(tax,
                          data_dir = file.path(Sys.getenv("BNDES_OUTPUT",
                                                          "data/processed"))) {
  if (identical(tax, "policy_block")) {
    pb <- qs2::qs_read(file.path(data_dir, "policy_block_mapping.qs2"))
    data.table::setDT(pb)
    return(pb)
  }
  if (identical(tax, "size_bin")) {
    sb <- qs2::qs_read(file.path(data_dir, "size_bin_mapping.qs2"))
    data.table::setDT(sb)
    return(sb)
  }
  if (identical(tax, "policy_block_size_bin")) {
    # Crossed taxonomy: assigned at firm x cycle level by the build scripts.
    # Return both component mappings as a named list.
    pb <- qs2::qs_read(file.path(data_dir, "policy_block_mapping.qs2"))
    sb <- qs2::qs_read(file.path(data_dir, "size_bin_mapping.qs2"))
    data.table::setDT(pb); data.table::setDT(sb)
    return(list(policy_block = pb, size_bin = sb))
  }
  stop("Unknown taxonomy: ", tax)
}

# Levels for each taxonomy (used for column naming).
taxonomy_levels <- function(tax) {
  if (identical(tax, "policy_block")) return(c("Agro", "Ind", "Infra", "Serv"))
  if (identical(tax, "size_bin"))     return(c("1", "2", "3"))
  if (identical(tax, "policy_block_size_bin")) {
    # 4 policy blocks x 3 size bins = 12 crossed groups, label "<block>_<bin>".
    pb <- c("Agro", "Ind", "Infra", "Serv")
    sb <- c("1", "2", "3")
    return(as.vector(t(outer(pb, sb, paste, sep = "_"))))
  }
  stop("Unknown taxonomy: ", tax)
}

taxonomy_labels <- function(tax) {
  if (identical(tax, "policy_block"))
    return(c(Agro = "Agriculture", Ind = "Industry",
             Infra = "Infrastructure", Serv = "Services"))
  if (identical(tax, "size_bin"))
    return(c(`1` = "Small", `2` = "Medium", `3` = "Big"))
  if (identical(tax, "policy_block_size_bin")) {
    pb_lab <- c(Agro = "Agro", Ind = "Ind", Infra = "Infra", Serv = "Serv")
    sb_lab <- c(`1` = "Small", `2` = "Medium", `3` = "Big")
    lvls <- taxonomy_levels(tax)
    parts <- strsplit(lvls, "_", fixed = TRUE)
    out <- vapply(parts, function(p) paste0(pb_lab[[p[[1L]]]], " / ",
                                            sb_lab[[p[[2L]]]]), character(1))
    names(out) <- lvls
    return(out)
  }
  stop("Unknown taxonomy: ", tax)
}

# Channel display labels for LaTeX tables and slides. Interaction channels use
# the centered dot ($\cdot$) to match script 04's channel_labels and the slide
# prose. Single-office channels stay plain text.
channel_label <- function(channel) {
  switch(channel,
    M   = "Mayor",
    G   = "Governor",
    P   = "President",
    MP  = "Mayor $\\cdot$ President",
    MG  = "Mayor $\\cdot$ Governor",
    GP  = "Governor $\\cdot$ President",
    MGP = "Mayor $\\cdot$ Gov. $\\cdot$ President",
    channel)
}

# Plain-text channel labels for CSV columns and console output, where a raw
# LaTeX "$\cdot$" would be noise. Same channels as channel_label(), with " x "
# in place of the centered dot.
channel_label_plain <- function(channel) {
  switch(channel,
    M   = "Mayor",
    G   = "Governor",
    P   = "President",
    MP  = "Mayor x President",
    MG  = "Mayor x Governor",
    GP  = "Governor x President",
    MGP = "Mayor x Gov. x President",
    channel)
}

# --- Column-name helpers -----------------------------------------------------

z_col_name <- function(channel, sector) {
  paste0("Z_", channel, "_", sector)
}

ec_col_name <- function(channel, sector) {
  paste0("EC_", channel, "_", sector)
}

# --- Alignment-column mapping per channel ------------------------------------

# Maps channel label to alignment_shocks.qs2 column (coalition variants only,
# per L5 of the plan).
#
# The four cross-mayor channels and the three single-office mains have a
# pre-built coalition column. The GP pair (governor x president) has NO
# pre-built column: it is constructed in 02_build_instruments_ec.R as the
# product align_gov_coalition * align_pres_coalition at the (muni,party,year)
# level. channel_align_col() therefore returns NA for GP — callers detect this
# and build the product. The original four channels are unchanged.
channel_align_col <- function(channel) {
  switch(channel,
    M   = "align_mayor_coalition",
    G   = "align_gov_coalition",
    P   = "align_pres_coalition",
    MP  = "align_mayor_pres_coalition",
    MG  = "align_mayor_gov_coalition",
    GP  = NA_character_,   # built as gov_coalition * pres_coalition
    MGP = "align_triple_coalition",
    stop("Unknown channel: ", channel))
}

# Component coalition columns for channels built as a product (GP).
channel_align_components <- function(channel) {
  switch(channel,
    GP = c("align_gov_coalition", "align_pres_coalition"),
    stop("Channel has no product definition: ", channel))
}

# --- Phase B/C shared utilities ----------------------------------------------
# Lifted from B2-B6 / C3 to remove copy-paste duplication. Every Phase B/C
# script sources 00_helpers.R and uses these instead of redefining them.

# Resolve the absolute path of the running script (Rscript only).
get_this_script <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (length(fa)) return(normalizePath(sub("^--file=", "", fa[[1L]]),
                                       winslash = "/", mustWork = TRUE))
  stop("Run via Rscript.")
}

# Parse a "--flag=value" command-line argument; returns `default` if absent.
parse_kv <- function(flag, default, cli = commandArgs(trailingOnly = TRUE)) {
  hit <- grep(paste0("^", flag, "="), cli, value = TRUE)
  if (!length(hit)) return(default)
  sub(paste0("^", flag, "="), "", hit[[1L]])
}

# Firm size-bin election cycles (odd years 2005-2017). Single source of truth;
# previously hard-coded in 03_build_muni_ar_panel.R, B2, and C3.
SIZE_CYCLES <- c(2005L, 2007L, 2009L, 2011L, 2013L, 2015L, 2017L)

# --- Numeric / LaTeX formatting helpers --------------------------------------
# fmt_n: fixed-decimal; fmt_g: significant-digits; fmt_p: p-value with a
# "<0.001" floor; fmt_F: alias of fmt_n at 3 digits. Digits are arguments so a
# caller that needs a different precision passes it explicitly rather than
# redefining the function.

fmt_n <- function(x, d = 3L) {
  if (!is.finite(x)) return("--")
  formatC(x, format = "f", digits = d)
}

fmt_g <- function(x, d = 3L) {
  if (!is.finite(x)) return("--")
  formatC(x, format = "g", digits = d)
}

fmt_p <- function(p, d = 3L) {
  if (!is.finite(p)) return("--")
  if (p < 0.001) return("$<$0.001")
  formatC(p, format = "f", digits = d)
}

fmt_F <- function(x, d = 3L) fmt_n(x, d)

# Joint Wald F-statistics over highly collinear stacked channels can be
# numerically degenerate: when the cluster-robust VCV of the coefficient block
# is near-singular, inverting it in the quadratic form yields a garbage F (e.g.
# tens of millions). joint_F_rank_deficient() flags such cases so the joint cell
# can be reported as rank-deficient rather than a bogus number. A non-finite F
# or one exceeding JOINT_F_CEILING is treated as rank-deficient.
JOINT_F_CEILING <- 1e4

joint_F_rank_deficient <- function(F_stat) {
  !is.finite(F_stat) || F_stat > JOINT_F_CEILING
}

# Significance stars from a p-value.
stars <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.01) return("$^{***}$")
  if (p < 0.05) return("$^{**}$")
  if (p < 0.10) return("$^{*}$")
  ""
}

# --- Sanity test (run at sourcing) -------------------------------------------

# Verify the §3.2 worked-example table reproduces exactly.
.test_calendar <- function() {
  cal <- build_channel_calendar(years = c(2008, 2010, 2011, 2012, 2014, 2017),
                                channels = c("MP", "MG", "MGP"))
  expected <- list(
    list(t = 2008, e_Fc = 2006, T_lo = 2002, T_hi = 2005),
    list(t = 2010, e_Fc = 2008, T_lo = 2004, T_hi = 2007),
    list(t = 2011, e_Fc = 2008, T_lo = 2004, T_hi = 2007),
    list(t = 2012, e_Fc = 2010, T_lo = 2006, T_hi = 2009),
    list(t = 2014, e_Fc = 2012, T_lo = 2008, T_hi = 2011),
    list(t = 2017, e_Fc = 2014, T_lo = 2010, T_hi = 2013)
  )
  ok <- TRUE
  for (e in expected) {
    sub <- cal[cal$year == e$t & cal$channel == "MGP", ]
    if (nrow(sub) != 1L || sub$e_Fc != e$e_Fc ||
        sub$T_lo != e$T_lo || sub$T_hi != e$T_hi) {
      message(sprintf(
        "[FAIL] year=%d MGP expected e=%d window=[%d,%d] got e=%s [%s,%s]",
        e$t, e$e_Fc, e$T_lo, e$T_hi,
        as.character(sub$e_Fc), as.character(sub$T_lo),
        as.character(sub$T_hi)))
      ok <- FALSE
    }
  }
  if (ok) message("[OK] 00_helpers.R worked-example table matches Variant F §3.2")
  invisible(ok)
}

if (sys.nframe() == 0L) {
  .test_calendar()
}
