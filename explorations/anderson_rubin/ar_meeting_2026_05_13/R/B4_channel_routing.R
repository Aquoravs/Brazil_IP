#!/usr/bin/env Rscript
# ==============================================================================
# B4_channel_routing.R - route channels using the B8 wide-form relevance verdict.
#
# B2/B3 stacked-form first stages are descriptive companions only. The routing
# rule now reads `wide_first_stage_<tax>.csv`, takes the volume-control fit as
# the verdict, and assigns singleton channels with wide-form relevance to the
# composition set. B8 does not evaluate a separate volume-channel first stage,
# so the volume set is empty in this Phase 1B routing table.
#
# CLI:  --tax={policy_block, policy_block_size_bin}
# Out:  output/ar_routing_<tax>.{csv,tex}
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

source_helpers <- function() {
  a  <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", a, value = TRUE)
  if (!length(fa)) stop("Run via Rscript.")
  this <- normalizePath(sub("^--file=", "", fa[[1L]]),
                        winslash = "/", mustWork = TRUE)
  source(file.path(dirname(this), "00_helpers.R"))
}
source_helpers()

THIS <- get_this_script()
BR   <- normalizePath(file.path(dirname(THIS), ".."), winslash = "/", mustWork = TRUE)
OUT  <- file.path(BR, "output")

TAX <- parse_kv("--tax", "policy_block")
stopifnot(TAX %in% c("policy_block", "policy_block_size_bin"))
message(sprintf("[INFO] %s | B4 channel routing from B8 | tax=%s",
                Sys.time(), TAX))

CHANNELS <- all_channels()
MAYOR_FALLBACK <- c("M", "MP", "MG", "MGP")

wide_path <- file.path(OUT, sprintf("wide_first_stage_%s.csv", TAX))
if (!file.exists(wide_path)) {
  stop("Missing B8 output: ", wide_path)
}
wide <- fread(wide_path)

needed <- c("stack_id", "volume_control", "kp_rank_wald", "kp_p",
            "sw_min", "sw_median", "sw_max", "identified_shares",
            "n_endogenous", "relevant_verdict")
missing <- setdiff(needed, names(wide))
if (length(missing)) {
  stop("B8 output is missing required columns: ", paste(missing, collapse = ", "))
}

route <- wide[volume_control == TRUE & stack_id %in% CHANNELS,
              .(channel = stack_id,
                channel_label = vapply(stack_id, channel_label_plain, character(1)),
                kp_rank_wald,
                kp_p,
                sw_min,
                sw_median,
                sw_max,
                identified_shares,
                n_endogenous,
                rel_comp = relevant_verdict)]

missing_channels <- setdiff(CHANNELS, route$channel)
if (length(missing_channels)) {
  stop("B8 singleton verdicts missing for: ",
       paste(missing_channels, collapse = ", "))
}

route <- route[order(match(channel, CHANNELS))]
route[, rel_vol := FALSE]

route[, assignment := fifelse(rel_comp, "composition", "dropped")]

comp_relevant <- route[rel_comp == TRUE, channel]
fallback_used <- length(comp_relevant) == 0L
if (fallback_used) {
  stopifnot(!any(route$rel_comp))
  message("[INFO] no channel clears the wide-form composition gate -> fallback set ",
          "{M, M.P, M.G, M.G.P}")
  route[channel %in% MAYOR_FALLBACK, assignment := "composition"]
  comp_set <- MAYOR_FALLBACK
} else {
  comp_set <- route[assignment == "composition", channel]
}

vol_set <- character(0L)

route[, `:=`(
  fallback_used = fallback_used,
  in_comp_set = channel %in% comp_set,
  in_vol_set = FALSE,
  routing_source = "B8 wide-form first stage",
  taxonomy = TAX)]

# Compatibility columns for downstream readers that used the old B4 schema.
route[, `:=`(
  F_comp = sw_max,
  p_comp = kp_p,
  F_vol = NA_real_,
  p_vol = NA_real_)]

message("\n[RESULT] B4 routing table (B8 wide-form verdict):")
print(route[, .(channel_label,
                 kp = round(kp_rank_wald, 3),
                 sw_min = round(sw_min, 2),
                 sw_max = round(sw_max, 2),
                 identified = paste0(identified_shares, "/", n_endogenous),
                 rel_comp,
                 assignment)])
message(sprintf("[RESULT] composition set: {%s}%s",
                paste(comp_set, collapse = ", "),
                if (fallback_used) "  (FALLBACK)" else ""))
message("[RESULT] volume set: {(none)} -- B8 has no separate volume-channel verdict")

fwrite(route, file.path(OUT, sprintf("ar_routing_%s.csv", TAX)))

# --- Bare-tabular .tex (INV-13) ---------------------------------------------

assign_label <- c(composition = "Composition", dropped = "Dropped")

lines <- c(
  "\\begin{tabular}{@{}lccccc@{}}",
  "\\toprule",
  "Channel & KP & SW $F$ min & SW $F$ max & ID shares & Assignment \\\\",
  "\\midrule")
for (i in seq_len(nrow(route))) {
  r <- route[i]
  lines <- c(lines, sprintf(
    "%s & %s & %s & %s & %d/%d & %s \\\\",
    channel_label(r$channel),
    fmt_n(r$kp_rank_wald, 2L),
    fmt_n(r$sw_min, 2L),
    fmt_n(r$sw_max, 2L),
    r$identified_shares,
    r$n_endogenous,
    assign_label[[r$assignment]]))
}
lines <- c(lines, "\\bottomrule", "\\end{tabular}")
writeLines(lines, file.path(OUT, sprintf("ar_routing_%s.tex", TAX)))

message(sprintf("[INFO] wrote ar_routing_%s.{csv,tex}", TAX))
message(sprintf("[INFO] %s | B4 done.", Sys.time()))
