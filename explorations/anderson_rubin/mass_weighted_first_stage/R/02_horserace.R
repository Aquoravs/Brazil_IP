#!/usr/bin/env Rscript

cat("==============================================================================\n")
cat("Mass-weighted first stage: policy_block horserace\n")
cat("==============================================================================\n\n")

source("R/00_helpers.R")

suppressPackageStartupMessages({
  library(fixest)
})
fixest::setFixest_nthreads(4)

build_emp_share_panel <- function() {
  out_file <- out_path("emp_share_policy_block_panel.qs2")
  if (file.exists(out_file)) {
    cat("Loading cached employment-share panel...\n")
    return(read_qs_dt(out_file))
  }

  cat("Building employment-share panel from RAIS employment...\n")
  firm <- read_qs_dt(processed_path("firm_panel_for_regs.qs2"))
  firm <- firm[, .(firm_id, muni_id, year, cnae_section, n_employees)]
  firm <- firm[!is.na(muni_id) & muni_id > 0L & year %in% 2005L:2017L]
  firm[is.na(n_employees), n_employees := 0]

  pb_map <- read_qs_dt(processed_path("policy_block_mapping.qs2"))
  firm[pb_map[, .(cnae_section, policy_block)], policy_block := i.policy_block, on = "cnae_section"]
  firm[is.na(policy_block), policy_block := "XX"]

  denom <- firm[, .(
    emp_mt_full = sum(as.numeric(n_employees), na.rm = TRUE),
    emp_mt_active = sum(as.numeric(n_employees) * (policy_block %in% active_blocks), na.rm = TRUE)
  ), by = .(muni_id, year)]
  denom <- denom[emp_mt_full > 0]

  emp_j <- firm[policy_block %in% active_blocks,
                .(emp_jmt = sum(as.numeric(n_employees), na.rm = TRUE)),
                by = .(muni_id, year, policy_block)]

  panel <- CJ(
    muni_id = sort(unique(denom$muni_id)),
    policy_block = active_blocks,
    year = sort(unique(denom$year)),
    unique = TRUE
  )
  panel <- merge(panel, denom, by = c("muni_id", "year"), all.x = TRUE)
  panel <- merge(panel, emp_j, by = c("muni_id", "year", "policy_block"), all.x = TRUE)
  panel[is.na(emp_jmt), emp_jmt := 0]
  panel[, emp_share_jmt := fifelse(emp_mt_full > 0, emp_jmt / emp_mt_full, NA_real_)]
  panel[, emp_share_active_jmt := fifelse(emp_mt_active > 0, emp_jmt / emp_mt_active, NA_real_)]
  panel[, policy_block := factor(policy_block, levels = active_blocks)]
  setorder(panel, year, muni_id, policy_block)
  write_qs_atomic(panel, out_file)
  panel
}

load_instruments <- function() {
  base_vara <- read_qs_dt(out_path("dif_shifts_base_vara.qs2"))
  base_vara <- base_vara[, .(spec, muni_id, policy_block, year, treatment_year, channel, shift, Z)]

  varb <- read_qs_dt(out_path("variant_b_instruments.qs2"))
  varb <- varb[, .(
    spec = "VAR-B",
    muni_id, policy_block, year, treatment_year, channel, shift,
    Z = Z_emp,
    Z_active_denom = Z_emp_active_denom
  )]
  base_vara[, Z_active_denom := NA_real_]

  inst <- rbindlist(list(base_vara, varb), use.names = TRUE, fill = TRUE)
  inst[, policy_block := factor(as.character(policy_block), levels = active_blocks)]
  inst[, shift := factor(shift, levels = c("LEV", "DIF"))]
  inst[, channel := factor(channel, levels = channel_map$channel)]
  inst[, spec := factor(spec, levels = c("BASE", "VAR-A", "VAR-B"))]
  inst
}

fit_one <- function(dt, outcome, rhs_terms) {
  form <- as.formula(paste0(
    outcome, " ~ ", paste(rhs_terms, collapse = " + "),
    " | muni_id^policy_block + policy_block^year"
  ))
  feols(form, data = dt, vcov = ~ muni_id + policy_block, lean = TRUE)
}

coef_rows <- function(mod, meta) {
  ct <- as.data.table(coeftable(mod), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("estimate", "std_error", "t_value", "p_value"), skip_absent = TRUE)
  ct <- ct[grepl("^Z_", term)]
  cbind(as.data.table(meta), ct)
}

emp <- build_emp_share_panel()
inst <- load_instruments()

cat("Merging instruments and outcomes...\n")
panel <- merge(inst, emp, by = c("muni_id", "policy_block", "year"), all.x = TRUE)
panel <- panel[!is.na(emp_share_jmt)]
write_qs_atomic(panel, out_path("horserace_panel_long.qs2"))

outcomes <- c(
  emp_share_jmt = "full denominator outcome",
  emp_share_active_jmt = "active-block denominator outcome"
)

f_rows <- list()
c_rows <- list()

cat("Running per-channel regressions...\n")
for (outcome in names(outcomes)) {
  for (sp in levels(inst$spec)) {
    for (sh in levels(inst$shift)) {
      for (ch in levels(inst$channel)) {
        dt <- panel[spec == sp & shift == sh & channel == ch]
        dt <- dt[!is.na(get(outcome))]
        if (!nrow(dt) || sd(dt$Z, na.rm = TRUE) == 0) next
        dt[, Z_single := Z]
        mod <- tryCatch(fit_one(dt, outcome, "Z_single"), error = function(e) e)
        if (inherits(mod, "error")) {
          f_rows[[length(f_rows) + 1L]] <- data.table(
            outcome = outcome, model_type = "per_channel", spec = sp, shift = sh,
            channel = ch, f_wald_twcl = NA_real_, n_obs = nrow(dt),
            error = conditionMessage(mod)
          )
          next
        }
        meta <- list(outcome = outcome, model_type = "per_channel", spec = sp,
                     shift = sh, channel = ch)
        f_rows[[length(f_rows) + 1L]] <- data.table(
          outcome = outcome, model_type = "per_channel", spec = sp, shift = sh,
          channel = ch, f_wald_twcl = safe_wald_stat(mod, "^Z_"),
          n_obs = nobs(mod), r2 = tryCatch(r2(mod, "r2"), error = function(e) NA_real_),
          error = NA_character_
        )
        c_rows[[length(c_rows) + 1L]] <- coef_rows(mod, meta)
      }
    }
  }
}

cat("Running joint-channel regressions...\n")
wide <- dcast(
  panel,
  spec + shift + muni_id + policy_block + year + emp_share_jmt + emp_share_active_jmt ~ channel,
  value.var = "Z",
  fill = 0
)
for (ch in channel_map$channel) {
  setnames(wide, ch, paste0("Z_", ch))
}

for (outcome in names(outcomes)) {
  for (sp in levels(inst$spec)) {
    for (sh in levels(inst$shift)) {
      dt <- wide[spec == sp & shift == sh]
      dt <- dt[!is.na(get(outcome))]
      rhs <- paste0("Z_", channel_map$channel)
      if (!nrow(dt)) next
      mod <- tryCatch(fit_one(dt, outcome, rhs), error = function(e) e)
      if (inherits(mod, "error")) {
        f_rows[[length(f_rows) + 1L]] <- data.table(
          outcome = outcome, model_type = "joint_channel", spec = sp, shift = sh,
          channel = "ALL", f_wald_twcl = NA_real_, n_obs = nrow(dt),
          error = conditionMessage(mod)
        )
        next
      }
      meta <- list(outcome = outcome, model_type = "joint_channel", spec = sp,
                   shift = sh, channel = "ALL")
      f_rows[[length(f_rows) + 1L]] <- data.table(
        outcome = outcome, model_type = "joint_channel", spec = sp, shift = sh,
        channel = "ALL", f_wald_twcl = safe_wald_stat(mod, "^Z_"),
        n_obs = nobs(mod), r2 = tryCatch(r2(mod, "r2"), error = function(e) NA_real_),
        error = NA_character_
      )
      c_rows[[length(c_rows) + 1L]] <- coef_rows(mod, meta)
    }
  }
}

fstats <- rbindlist(f_rows, fill = TRUE)
coefs <- rbindlist(c_rows, fill = TRUE)
setorder(fstats, outcome, model_type, spec, shift, channel)
setorder(coefs, outcome, model_type, spec, shift, channel, term)

write_csv_atomic(fstats, out_path("horserace_fstats.csv"))
write_csv_atomic(coefs, out_path("horserace_coefs.csv"))

main_joint <- fstats[outcome == "emp_share_jmt" & model_type == "joint_channel"]
main_per <- fstats[outcome == "emp_share_jmt" & model_type == "per_channel"]

tex_lines <- c(
  "% Auto-generated by R/02_horserace.R",
  "\\begin{table}[!htbp]",
  "\\centering",
  "\\caption{Mass-weighted first-stage clustered Wald diagnostics}",
  "\\begin{tabular}{llrrrr}",
  "\\toprule",
  "Spec & Shift & M & MP & MG & MGP \\\\",
  "\\midrule"
)
per_wide <- dcast(main_per, spec + shift ~ channel, value.var = "f_wald_twcl")
setorder(per_wide, spec, shift)
for (i in seq_len(nrow(per_wide))) {
  tex_lines <- c(tex_lines, sprintf(
    "%s & %s & %s & %s & %s & %s \\\\",
    per_wide$spec[i], per_wide$shift[i],
    fmt_num(per_wide$M[i], 2), fmt_num(per_wide$MP[i], 2),
    fmt_num(per_wide$MG[i], 2), fmt_num(per_wide$MGP[i], 2)
  ))
}
tex_lines <- c(
  tex_lines,
  "\\midrule",
  "\\multicolumn{6}{l}{Joint-channel Wald F} \\\\"
)
for (i in seq_len(nrow(main_joint))) {
  tex_lines <- c(tex_lines, sprintf(
    "%s & %s & \\multicolumn{4}{r}{%s} \\\\",
    main_joint$spec[i], main_joint$shift[i], fmt_num(main_joint$f_wald_twcl[i], 2)
  ))
}
tex_lines <- c(
  tex_lines,
  "\\bottomrule",
  "\\end{tabular}",
  "\\begin{minipage}{0.95\\linewidth}\\footnotesize",
  "Notes: Dependent variable is $emp\\_share_{jmt}=emp_{jmt}/emp_{mt}^{full}$.",
  "Models include municipality-by-policy-block and policy-block-by-year fixed effects.",
  "Standard errors are two-way clustered by municipality and policy block.",
  "Reported statistics are clustered Wald / KP-style diagnostics from fixest::wald with keep = \\texttt{\\string^Z\\_}; they are not literal Sanderson-Windmeijer or Kleibergen-Paap statistics from a full IV system.",
  "\\end{minipage}",
  "\\end{table}"
)
writeLines(tex_lines, out_path("horserace_summary.tex"))

cat("\nSaved outputs:\n")
cat("  ", out_path("emp_share_policy_block_panel.qs2"), "\n", sep = "")
cat("  ", out_path("horserace_fstats.csv"), "\n", sep = "")
cat("  ", out_path("horserace_coefs.csv"), "\n", sep = "")
cat("  ", out_path("horserace_summary.tex"), "\n", sep = "")
print(main_joint)
cat("\nHorserace complete.\n")
