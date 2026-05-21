#!/usr/bin/env Rscript

cat("==============================================================================\n")
cat("Mass-weighted first stage: build BASE and VAR-A cross-office instruments\n")
cat("==============================================================================\n\n")

source("R/00_helpers.R")

build_cross_office <- function(weights, weight_col, spec_name) {
  if (!weight_col %in% names(weights)) stop(spec_name, " missing ", weight_col)
  if ("baseline_type" %in% names(weights)) {
    weights <- weights[baseline_type == "cycle_specific"]
  }
  if ("tier" %in% names(weights)) {
    weights <- weights[tier == "mayor"]
  }
  weights <- weights[
    treatment_year %in% mayor_elections & policy_block %in% active_blocks,
    .(muni_id, policy_block, party, treatment_year, weight = get(weight_col))
  ]
  weights[is.na(weight), weight := 0]
  weights <- weights[abs(weight) > 0]

  align <- read_qs_dt(processed_path("alignment_shocks.qs2"))
  needed_align <- c("muni_id", "party", "year", channel_map$level_col, channel_map$diff_col)
  missing_align <- setdiff(needed_align, names(align))
  if (length(missing_align)) stop("alignment_shocks.qs2 missing: ", paste(missing_align, collapse = ", "))
  align <- align[year %in% 2005L:2017L, ..needed_align]

  out <- list()
  for (e in mayor_elections) {
    term_years <- term_map[treatment_year == e, year]
    w_e <- weights[treatment_year == e]
    if (!nrow(w_e)) next

    grid <- merge(
      w_e[, dummy__ := 1L],
      data.table(dummy__ = 1L, year = term_years),
      by = "dummy__",
      allow.cartesian = TRUE
    )[, dummy__ := NULL]

    grid <- merge(
      grid,
      align[year %in% term_years],
      by = c("muni_id", "party", "year"),
      all.x = TRUE
    )
    for (cc in c(channel_map$level_col, channel_map$diff_col)) {
      grid[is.na(get(cc)), (cc) := 0]
    }

    balanced <- CJ(
      muni_id = sort(unique(w_e$muni_id)),
      policy_block = active_blocks,
      year = term_years,
      unique = TRUE
    )
    balanced[, treatment_year := e]

    for (i in seq_len(nrow(channel_map))) {
      ch <- channel_map$channel[i]
      for (shift_name in c("LEV", "DIF")) {
        src <- if (identical(shift_name, "LEV")) channel_map$level_col[i] else channel_map$diff_col[i]
        agg <- grid[, .(
          Z = sum(weight * get(src), na.rm = TRUE)
        ), by = .(muni_id, policy_block, year, treatment_year)]
        dt <- merge(
          balanced,
          agg,
          by = c("muni_id", "policy_block", "year", "treatment_year"),
          all.x = TRUE
        )
        dt[is.na(Z), Z := 0]
        dt[, `:=`(spec = spec_name, channel = ch, shift = shift_name)]
        out[[length(out) + 1L]] <- dt[, .(
          spec, muni_id, policy_block, year, treatment_year, channel, shift, Z
        )]
      }
    }

    rm(grid, balanced, w_e); invisible(gc())
  }

  rbindlist(out, use.names = TRUE)
}

cat("Loading BASE weights...\n")
base_weights <- read_qs_dt(processed_path("baseline_sector_weights_policy_block.qs2"))
base_long <- build_cross_office(base_weights, "w_rjp_0", "BASE")
rm(base_weights); invisible(gc())

cat("Loading VAR-A a7 weights...\n")
vara_weights <- read_qs_dt(file.path(
  PROJECT_ROOT, "explorations", "anderson_rubin", "a7_weight_comparison",
  "output", "a7_weights_panel.qs2"
))
vara_long <- build_cross_office(vara_weights, "w_owners_muni_univ", "VAR-A")
rm(vara_weights); invisible(gc())

out_dt <- rbindlist(list(base_long, vara_long), use.names = TRUE)
out_dt[, herfindahl_Z := sum(Z^2, na.rm = TRUE), by = .(spec, muni_id, year, channel, shift)]
setorder(out_dt, spec, shift, channel, year, muni_id, policy_block)

write_qs_atomic(out_dt, out_path("dif_shifts_base_vara.qs2"))

summary <- out_dt[, .(
  n_rows = .N,
  n_munis = uniqueN(muni_id),
  mean_Z = mean(Z, na.rm = TRUE),
  sd_Z = sd(Z, na.rm = TRUE),
  nonzero_share = mean(abs(Z) > 1e-12, na.rm = TRUE)
), by = .(spec, channel, shift)]
write_csv_atomic(summary, out_path("dif_shifts_base_vara_summary.csv"))

cat("\nSaved ", out_path("dif_shifts_base_vara.qs2"), "\n", sep = "")
cat("Rows: ", format(nrow(out_dt), big.mark = ","), "\n", sep = "")
print(summary)
cat("\nBASE and VAR-A build complete.\n")
