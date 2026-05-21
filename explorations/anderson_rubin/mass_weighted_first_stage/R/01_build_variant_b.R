#!/usr/bin/env Rscript

cat("==============================================================================\n")
cat("Mass-weighted first stage: build VAR-B employment-mass instruments\n")
cat("==============================================================================\n\n")

source("R/00_helpers.R")

required_pkgs <- c("data.table", "qs2")
invisible(lapply(required_pkgs, require, character.only = TRUE))

cat("Loading firm panel and policy-block mapping...\n")
firm <- read_qs_dt(processed_path("firm_panel_for_regs.qs2"))
keep_cols <- unique(c(
  "firm_id", "muni_id", "year", "cnae_section", "n_employees"
))
missing_cols <- setdiff(keep_cols, names(firm))
if (length(missing_cols)) stop("firm_panel_for_regs.qs2 missing: ", paste(missing_cols, collapse = ", "))
firm <- firm[, ..keep_cols]
firm <- firm[!is.na(muni_id) & muni_id > 0L]
firm[is.na(n_employees), n_employees := 0]

pb_map <- read_qs_dt(processed_path("policy_block_mapping.qs2"))
firm[pb_map[, .(cnae_section, policy_block)], policy_block := i.policy_block, on = "cnae_section"]
firm[is.na(policy_block), policy_block := "XX"]
firm[, policy_block := as.character(policy_block)]

cat("Loading firm baseline exposures and alignment shocks...\n")
firm_exp <- read_qs_dt(processed_path("firm_baseline_exposures.qs2"))
exp_cols <- c("firm_id", "party", "baseline_type", "election_year", "share_fp_0")
missing_exp <- setdiff(exp_cols, names(firm_exp))
if (length(missing_exp)) stop("firm_baseline_exposures.qs2 missing: ", paste(missing_exp, collapse = ", "))
firm_exp <- firm_exp[
  baseline_type == "cycle_specific" & election_year %in% mayor_elections,
  ..exp_cols
]
firm_exp <- firm_exp[share_fp_0 > 0]

align <- read_qs_dt(processed_path("alignment_shocks.qs2"))
align_cols <- c("muni_id", "party", "year", channel_map$level_col, channel_map$diff_col)
missing_align <- setdiff(align_cols, names(align))
if (length(missing_align)) stop("alignment_shocks.qs2 missing: ", paste(missing_align, collapse = ", "))
align <- align[year %in% 2005L:2017L, ..align_cols]

out_parts <- list()

for (e in mayor_elections) {
  pre_years <- pre_years_for_election(e)
  term_years <- term_map[treatment_year == e, year]
  cat(sprintf("Cycle %d: pre-window %s, term years %s\n",
              e, paste(pre_years, collapse = ","), paste(term_years, collapse = ",")))

  pre <- firm[year %in% pre_years]
  if (!nrow(pre)) next

  ebar_fm <- pre[, .(
    Ebar_f = mean(as.numeric(n_employees), na.rm = TRUE)
  ), by = .(firm_id, muni_id)]
  ebar_fm[!is.finite(Ebar_f) | is.na(Ebar_f), Ebar_f := 0]
  ebar_fm[, treatment_year := e]

  support_blocks <- unique(pre[, .(firm_id, muni_id, policy_block)])
  support <- merge(
    support_blocks,
    ebar_fm[, .(firm_id, muni_id, treatment_year, Ebar_f)],
    by = c("firm_id", "muni_id"),
    all.x = TRUE
  )
  support[is.na(Ebar_f), Ebar_f := 0]

  denom_full <- ebar_fm[, .(Ebar_m = sum(Ebar_f, na.rm = TRUE)), by = .(muni_id, treatment_year)]
  active_firms <- unique(support[policy_block %in% active_blocks, .(firm_id, muni_id, treatment_year, Ebar_f)])
  denom_active <- active_firms[, .(Ebar_m_active = sum(Ebar_f, na.rm = TRUE)), by = .(muni_id, treatment_year)]

  muni_keep <- denom_full[Ebar_m > 0, .(muni_id, treatment_year, Ebar_m)]
  balanced <- CJ(
    muni_id = sort(muni_keep$muni_id),
    policy_block = active_blocks,
    year = term_years,
    unique = TRUE
  )
  balanced[, treatment_year := e]
  balanced <- merge(balanced, muni_keep, by = c("muni_id", "treatment_year"), all.x = TRUE)
  balanced <- merge(balanced, denom_active, by = c("muni_id", "treatment_year"), all.x = TRUE)
  balanced[is.na(Ebar_m_active), Ebar_m_active := 0]

  ebar_jm <- support[policy_block %in% active_blocks,
                     .(Ebar_jm = sum(Ebar_f, na.rm = TRUE)),
                     by = .(muni_id, treatment_year, policy_block)]
  balanced <- merge(balanced, ebar_jm, by = c("muni_id", "treatment_year", "policy_block"), all.x = TRUE)
  balanced[is.na(Ebar_jm), Ebar_jm := 0]

  support_active <- support[
    policy_block %in% active_blocks,
    .(firm_id, muni_id, treatment_year, policy_block, Ebar_f)
  ]
  tmp <- merge(
    support_active,
    firm_exp[election_year == e, .(firm_id, party, share_fp_0)],
    by = "firm_id",
    allow.cartesian = TRUE,
    all.x = FALSE
  )
  tmp <- merge(
    tmp,
    align[year %in% term_years],
    by = c("muni_id", "party"),
    allow.cartesian = TRUE,
    all.x = FALSE
  )
  tmp <- tmp[year %in% term_years]
  rm(support_active); invisible(gc())

  long_parts <- list()
  for (i in seq_len(nrow(channel_map))) {
    ch <- channel_map$channel[i]
    lev_col <- channel_map$fa_col[i]
    dif_col <- channel_map$dfa_col[i]

    for (shift_name in c("LEV", "DIF")) {
      src <- if (identical(shift_name, "LEV")) {
        channel_map$level_col[i]
      } else {
        channel_map$diff_col[i]
      }
      agg <- tmp[, .(
        numer = sum(Ebar_f * share_fp_0 * fifelse(is.na(get(src)), 0, get(src)), na.rm = TRUE)
      ), by = .(muni_id, treatment_year, policy_block, year)]
      dt <- merge(
        balanced,
        agg,
        by = c("muni_id", "treatment_year", "policy_block", "year"),
        all.x = TRUE
      )
      dt[is.na(numer), numer := 0]
      dt[, `:=`(
        channel = ch,
        shift = shift_name,
        Z_emp = fifelse(Ebar_m > 0, numer / Ebar_m, NA_real_),
        Z_emp_active_denom = fifelse(Ebar_m_active > 0, numer / Ebar_m_active, NA_real_)
      )]
      dt[is.na(Z_emp), Z_emp := 0]
      long_parts[[length(long_parts) + 1L]] <- dt[, .(
        muni_id, policy_block, year, treatment_year, channel, shift,
        Z_emp, Z_emp_active_denom, Ebar_jm, Ebar_m, Ebar_m_active
      )]
    }
  }

  out_parts[[length(out_parts) + 1L]] <- rbindlist(long_parts, use.names = TRUE)
  rm(pre, ebar_fm, support_blocks, support, denom_full, denom_active,
     active_firms, muni_keep, balanced, ebar_jm, tmp, long_parts)
  invisible(gc())
}

variant_b <- rbindlist(out_parts, use.names = TRUE)
variant_b[, spec := "VAR-B"]
setcolorder(variant_b, c(
  "spec", "muni_id", "policy_block", "year", "treatment_year", "channel", "shift",
  "Z_emp", "Z_emp_active_denom", "Ebar_jm", "Ebar_m", "Ebar_m_active"
))
setorder(variant_b, spec, shift, channel, year, muni_id, policy_block)

variant_b[, herfindahl_Z := sum(Z_emp^2, na.rm = TRUE),
          by = .(muni_id, year, channel, shift)]
variant_b[, herfindahl_Z_active_denom := sum(Z_emp_active_denom^2, na.rm = TRUE),
          by = .(muni_id, year, channel, shift)]

write_qs_atomic(variant_b, out_path("variant_b_instruments.qs2"))

summary <- variant_b[, .(
  n_rows = .N,
  n_munis = uniqueN(muni_id),
  mean_Z = mean(Z_emp, na.rm = TRUE),
  sd_Z = sd(Z_emp, na.rm = TRUE),
  nonzero_share = mean(abs(Z_emp) > 1e-12, na.rm = TRUE),
  mean_Z_active_denom = mean(Z_emp_active_denom, na.rm = TRUE)
), by = .(channel, shift)]
write_csv_atomic(summary, out_path("variant_b_summary.csv"))

cat("\nSaved ", out_path("variant_b_instruments.qs2"), "\n", sep = "")
cat("Rows: ", format(nrow(variant_b), big.mark = ","), "\n", sep = "")
print(summary)
cat("\nVAR-B build complete.\n")
