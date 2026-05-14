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
channel_offices <- list(
  M       = "mayor",
  MP      = c("mayor", "pres"),
  MG      = c("mayor", "governor"),
  MGP     = c("mayor", "governor", "pres")
)

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
  stop("Unknown taxonomy: ", tax)
}

# Levels for each taxonomy (used for column naming).
taxonomy_levels <- function(tax) {
  if (identical(tax, "policy_block")) return(c("Agro", "Ind", "Infra", "Serv"))
  if (identical(tax, "size_bin"))     return(c("1", "2", "3"))
  stop("Unknown taxonomy: ", tax)
}

taxonomy_labels <- function(tax) {
  if (identical(tax, "policy_block"))
    return(c(Agro = "Agriculture", Ind = "Industry",
             Infra = "Infrastructure", Serv = "Services"))
  if (identical(tax, "size_bin"))
    return(c(`1` = "MPME", `2` = "Media", `3` = "Grande"))
  stop("Unknown taxonomy: ", tax)
}

# Channel display labels for slides.
channel_label <- function(channel) {
  switch(channel,
    M   = "Mayor",
    MP  = "Mayor x President",
    MG  = "Mayor x Governor",
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
channel_align_col <- function(channel) {
  switch(channel,
    M   = "align_mayor_coalition",
    MP  = "align_mayor_pres_coalition",
    MG  = "align_mayor_gov_coalition",
    MGP = "align_triple_coalition",
    stop("Unknown channel: ", channel))
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
