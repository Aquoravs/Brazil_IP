#!/usr/bin/env Rscript
# Orchestrator to run `scripts/politicsregs` pipeline stages.
# Usage examples:
#   Rscript run_politicsregs.R all                             # run all main stages (+ auto audits)
#   Rscript run_politicsregs.R 31:54                           # run main stages 31 through 54
#   Rscript run_politicsregs.R 41,51,53                        # run specific main stages
#   Rscript run_politicsregs.R audit_3_instruments             # run one audit directly
#   Rscript run_politicsregs.R diagnose_alignment_overlap_support
#   Rscript run_politicsregs.R diagnose_sector_group_cell_support
#   Rscript run_politicsregs.R 31:35 --audits=auto             # run main + triggered audits
#   Rscript run_politicsregs.R 31:54 --audits=off              # run main stages only
#   Rscript run_politicsregs.R 31:54 --audits=only             # run only audits triggered by selected main stages
#   Rscript run_politicsregs.R all --dryrun                    # dry run
#   Rscript run_politicsregs.R 31 --sector-var=cnae_section    # forward inline script args
#   Rscript run_politicsregs.R 51 -- --unweighted              # forward args to main script

# Bootstrap shared path helpers from this script location.
script_args_full <- commandArgs(trailingOnly = FALSE)
script_file <- grep("^--file=", script_args_full, value = TRUE)
if (length(script_file)) {
  script_dir <- dirname(normalizePath(sub("^--file=", "", script_file[[1]]), winslash = "/", mustWork = TRUE))
  source(file.path(script_dir, "_utils", "script_bootstrap.R"))
} else {
  stop("Cannot determine orchestrator path. Run with `Rscript path/to/run_politicsregs.R`.")
}
bootstrap_politicsregs()

args <- commandArgs(trailingOnly = TRUE)
dash_idx <- match("--", args, nomatch = 0L)
if (dash_idx > 0L) {
  control_args <- args[seq_len(dash_idx - 1L)]
  explicit_forward_args <- if (dash_idx < length(args)) {
    args[(dash_idx + 1L):length(args)]
  } else {
    character(0)
  }
} else {
  control_args <- args
  explicit_forward_args <- character(0)
}

is_orchestrator_flag <- function(x) {
  grepl("^--(stages|audits)=", x) | tolower(x) == "--dryrun"
}

parse_opt <- function(opt, default = NULL) {
  m <- grep(paste0("^--", opt, "="), control_args, value = TRUE)
  if (length(m)) sub(paste0("^--", opt, "="), "", m[[1]]) else default
}

# First try --stages= format, then positional argument
stages_arg <- parse_opt("stages", NULL)
stage_token_idx <- integer(0)
if (is.null(stages_arg)) {
  # Look for first positional argument (not starting with --)
  positional_idx <- which(!grepl("^--", control_args))
  if (length(positional_idx)) {
    stage_token_idx <- positional_idx[1]
    stages_arg <- control_args[stage_token_idx]
  } else {
    stages_arg <- "all"
  }
}
dryrun <- any(tolower(control_args) == "--dryrun")
audits_mode <- tolower(parse_opt("audits", "auto"))
if (!audits_mode %in% c("off", "auto", "only")) {
  stop("Invalid --audits value: ", audits_mode, ". Use off, auto, or only.")
}
# Forward any non-orchestrator args, whether passed inline or after a standalone --.
control_forward_idx <- setdiff(
  seq_along(control_args),
  c(stage_token_idx, which(is_orchestrator_flag(control_args)))
)
forward_args <- c(control_args[control_forward_idx], explicit_forward_args)

script_root <- POLITICSREGS_DIR

# Ordered main pipeline map (key -> relative path from this script's directory)
# Main pipeline stages only. Audits are configured separately below.
pipeline_main <- list(
  "11" = "1_loan_aggregation/11_process_bndes_indirect.R",
  "21" = "2_firm_panel/21_convert_merged_formats.R",
  "22" = "2_firm_panel/22_reconstruct_merged.R",
  "30" = "3_instruments/30_build_sector_groups.R",
  "30b" = "3_instruments/30b_build_bndes_sector_mapping.R",
  "30c" = "3_instruments/30c_build_size_bin_mapping.R",
  "30d" = "3_instruments/30d_build_sector_size_bin_mapping.R",
  "30e" = "3_instruments/30e_build_policy_block_mapping.R",
  "31" = "3_instruments/31_build_sector_exposure_weights.R",
  "32" = "3_instruments/32_build_alignment_shocks.R",
  "32b" = "3_instruments/32b_build_muni_employment_baselines.R",
  "32c" = "3_instruments/32c_build_emp_share_panel.R",
  "33" = "3_instruments/33_select_baseline_weights.R",
  "34" = "3_instruments/34_build_shift_share_instruments.R",
  "35" = "3_instruments/35_build_credit_shares.R",
  "36" = "3_instruments/36_build_firm_level_instruments.R",
  "41" = "4_regression_panels/41_build_muni_panel.R",
  "42" = "4_regression_panels/42_build_firm_panel.R",
  "51" = "5_estimation/51_firm_first_stage.R",
  "51b" = "5_estimation/51b_firm_first_stage_summary.R",
  "52" = "5_estimation/52_aggregated_firm_sector_first_stage.R",
  "52b" = "5_estimation/52b_agg_first_stage_summary.R",
  "53" = "5_estimation/53_sector_first_stage.R",
  "54" = "5_estimation/54_sector_second_stage.R"
)

# Audit registry (name -> script + trigger stages)
# Trigger stages define when audits run automatically in --audits=auto mode.
audit_registry <- list(
  "audit_3_instruments" = list(
    script = "diagnostics/audit_3_instruments.R",
    triggers = c("35")
  ),
  "audit_41_muni_panel" = list(
    script = "diagnostics/audit_41_muni_panel.R",
    triggers = c("41")
  ),
  "diagnose_alignment_overlap_support" = list(
    script = "diagnostics/diagnose_alignment_overlap_support.R",
    triggers = character(0)
  ),
  "diagnose_sector_group_cell_support" = list(
    script = "diagnostics/diagnose_sector_group_cell_support.R",
    triggers = character(0)
  )
)

main_keys <- names(pipeline_main)
main_nums <- as.integer(main_keys)
audit_names <- names(audit_registry)

# Function to expand a range like "31:53" into matching main pipeline keys
expand_range <- function(range_str, keys, nums) {
  if (!grepl(":", range_str)) return(range_str)
  parts <- strsplit(range_str, ":")[[1]]
  if (length(parts) != 2) return(range_str)
  start <- as.integer(parts[1])
  end <- as.integer(parts[2])
  if (is.na(start) || is.na(end)) return(range_str)
  # Return all keys whose numeric value is between start and end
  keys[nums >= start & nums <= end]
}

is_range_token <- function(x) grepl(":", x)

if (identical(tolower(stages_arg), "all")) {
  requested_main <- main_keys
  requested_audits_explicit <- character(0)
} else {
  # Split by comma first, then classify tokens
  parts <- unlist(strsplit(stages_arg, ","))
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]

  requested_main <- character(0)
  requested_audits_explicit <- character(0)
  unknown_tokens <- character(0)

  for (p in parts) {
    if (is_range_token(p)) {
      expanded <- expand_range(p, main_keys, main_nums)
      if (identical(expanded, p)) {
        unknown_tokens <- c(unknown_tokens, p)
      } else {
        requested_main <- c(requested_main, expanded)
      }
      next
    }

    if (p %in% main_keys) {
      requested_main <- c(requested_main, p)
      next
    }

    if (p %in% audit_names) {
      requested_audits_explicit <- c(requested_audits_explicit, p)
      next
    }

    unknown_tokens <- c(unknown_tokens, p)
  }

  if (length(unknown_tokens)) {
    stop("Unknown stage(s): ", paste(unique(unknown_tokens), collapse = ", "))
  }

  requested_main <- unique(requested_main)
  requested_audits_explicit <- unique(requested_audits_explicit)
  requested_main <- requested_main[order(as.integer(requested_main))]
}

cat("Orchestrator:", if (dryrun) "DRYRUN mode" else "EXECUTE mode", "\n")
cat("Script root:", script_root, "\n")
cat("Audits mode:", audits_mode, "\n")
cat("Forward args to scripts:", if (length(forward_args)) paste(forward_args, collapse = " ") else "(none)", "\n")

# Build execution queue with typed entries.
queue <- list()
queued_audits <- character(0)

enqueue_main <- function(key) {
  queue[[length(queue) + 1L]] <<- list(
    id = key,
    type = "main",
    script_rel = pipeline_main[[key]],
    forward = TRUE
  )
}

enqueue_audit <- function(name, forward = FALSE) {
  if (name %in% queued_audits) return(invisible(NULL))
  queue[[length(queue) + 1L]] <<- list(
    id = name,
    type = "audit",
    script_rel = audit_registry[[name]]$script,
    forward = isTRUE(forward)
  )
  queued_audits <<- c(queued_audits, name)
  invisible(NULL)
}

if (audits_mode != "only") {
  for (key in requested_main) {
    enqueue_main(key)
    if (audits_mode == "auto") {
      triggered <- audit_names[vapply(
        audit_names,
        function(a) key %in% audit_registry[[a]]$triggers,
        logical(1)
      )]
      for (a in triggered) enqueue_audit(a, forward = FALSE)
    }
  }
}

if (audits_mode == "only") {
  # In "only" mode, run explicitly requested audits plus those triggered by selected main stages.
  triggered <- audit_names[vapply(
    audit_names,
    function(a) any(audit_registry[[a]]$triggers %in% requested_main),
    logical(1)
  )]
  for (a in c(triggered, requested_audits_explicit)) enqueue_audit(a, forward = TRUE)
} else {
  # Outside "only" mode, explicit audits are appended and receive forward args.
  for (a in requested_audits_explicit) enqueue_audit(a, forward = TRUE)
}

if (!length(queue)) {
  stop("No scripts selected. Check --stages and --audits arguments.")
}

for (entry in queue) {
  key <- entry$id
  script_rel <- entry$script_rel
  script_path <- politicsregs_path(script_rel)
  if (!file.exists(script_path)) {
    stop("Script not found: ", script_path)
  }
  cat(sprintf("\n=== Running [%s] %s -> %s ===\n", toupper(entry$type), key, script_rel))

  cmd <- c(script_path, if (isTRUE(entry$forward)) forward_args else character(0))
  cat("Command: Rscript ", script_path,
      if (isTRUE(entry$forward) && length(forward_args)) paste0(" ", paste(forward_args, collapse = " ")) else "",
      "\n", sep = "")
  if (dryrun) next
  status <- system2("Rscript", cmd, stdout = "", stderr = "")
  if (status != 0) stop(sprintf("Script failed (%s) with exit %s", script_rel, status))
}

cat("\nOrchestration complete.\n")
