#!/usr/bin/env Rscript

cat("==============================================================================\n")
cat("Diagnostic: Joint Alignment Support and Transitions\n")
cat("==============================================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})

# Bootstrap shared path helpers from this script location.
bootstrap_file <- local({
  project_root_opt <- getOption("politicsregs.project_root", default = NULL)
  if (is.character(project_root_opt) && length(project_root_opt) == 1L && nzchar(project_root_opt)) {
    return(file.path(project_root_opt, "scripts", "R", "_utils", "script_bootstrap.R"))
  }

  script_args_full <- commandArgs(trailingOnly = FALSE)
  script_file <- grep("^--file=", script_args_full, value = TRUE)
  if (length(script_file)) {
    script_file <- normalizePath(sub("^--file=", "", script_file[[1]]), winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }

  frame_paths <- vapply(sys.frames(), function(env) {
    ofile <- env$ofile
    if (is.null(ofile) || !nzchar(ofile)) return(NA_character_)
    ofile
  }, character(1))
  frame_paths <- frame_paths[!is.na(frame_paths)]
  if (length(frame_paths)) {
    script_file <- normalizePath(frame_paths[[length(frame_paths)]], winslash = "/", mustWork = TRUE)
    return(file.path(dirname(script_file), "..", "_utils", "script_bootstrap.R"))
  }

  stop("Cannot determine bootstrap path. In an interactive session, call `init_politicsregs_session()` first.")
})
source(normalizePath(bootstrap_file, winslash = "/", mustWork = TRUE))
bootstrap_politicsregs()

setDTthreads(0)

START_YEAR <- 2002L
END_YEAR <- 2017L
TRANSITION_START_YEAR <- START_YEAR + 1L

ALIGN_TYPES <- c("party", "coalition")
LEVEL_TERMS <- c("mayor_gov", "mayor_pres", "triple")
BROAD_TERMS <- c("mayor_gov", "mayor_pres", "triple")
STATE_LEVELS <- c("other", "mayor_gov", "mayor_pres", "triple")

TERM_MEMBERSHIP <- list(
  mayor_gov = c("mayor_gov", "triple"),
  mayor_pres = c("mayor_pres", "triple"),
  triple = c("triple")
)

raw_path <- make_base_path("raw/david_ra/in_power_upd_2002_2019.qs2")
align_path <- make_output_path("alignment_shocks.qs2")
out_dir <- file.path(OUTPUT_DIR, "diagnostics", "alignment_overlap_support")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

levels_muni_csv <- file.path(out_dir, "levels_muni_year_long.csv")
levels_rows_csv <- file.path(out_dir, "levels_party_row_long.csv")
term_changes_csv <- file.path(out_dir, "transition_term_changes_long.csv")
state_matrix_csv <- file.path(out_dir, "transitions_state_matrix_long.csv")
summary_md <- file.path(out_dir, "summary.md")
plot_paths <- setNames(
  file.path(out_dir, paste0("levels_support_", ALIGN_TYPES, ".png")),
  ALIGN_TYPES
)

load_dt <- function(path) {
  obj <- qs_read(path)
  setDT(obj)
  obj
}

state_col_name <- function(align_type) {
  paste0("state_", align_type)
}

prev_state_col_name <- function(align_type) {
  paste0("prev_state_", align_type)
}

align_col_name <- function(term, align_type) {
  paste0("align_", term, "_", align_type)
}

delta_col_name <- function(term, align_type) {
  paste0("delta_align_", term, "_", align_type)
}

make_level_summaries <- function(dt, align_type) {
  rbindlist(lapply(LEVEL_TERMS, function(term) {
    col <- align_col_name(term, align_type)

    row_summary <- dt[, .(
      n_rows = .N,
      n_positive = sum(get(col), na.rm = TRUE),
      pct_positive = 100 * mean(get(col), na.rm = TRUE)
    ), by = year][order(year)]
    row_summary[, `:=`(align_type = align_type, term = term)]
    setcolorder(row_summary, c("year", "align_type", "term", "n_rows", "n_positive", "pct_positive"))

    muni_flags <- dt[, .(
      is_positive = as.integer(any(get(col) == 1L))
    ), by = .(year, muni_id)]
    muni_summary <- muni_flags[, .(
      n_munis = .N,
      n_positive = sum(is_positive, na.rm = TRUE),
      pct_positive = 100 * mean(is_positive, na.rm = TRUE)
    ), by = year][order(year)]
    muni_summary[, `:=`(align_type = align_type, term = term)]
    setcolorder(muni_summary, c("year", "align_type", "term", "n_munis", "n_positive", "pct_positive"))

    list(rows = row_summary, munis = muni_summary)
  }))
}

if (!file.exists(raw_path)) {
  stop("Raw alignment panel not found: ", raw_path)
}

cat("Loading raw political panel...\n")
dt <- load_dt(raw_path)
cat("  Source:", raw_path, "\n")
cat("  Loaded rows:", format(nrow(dt), big.mark = ","), "\n")

muni_src <- intersect(c("muni_id_ibge6", "muni_id_ibge", "muni_id"), names(dt))[1]
year_src <- intersect(c("year", "ano"), names(dt))[1]
party_src <- intersect(c("party", "sigla_partido"), names(dt))[1]
required_power_cols <- c(
  "mayor_in_power_party", "mayor_in_power_coalition",
  "gov_in_power_party", "gov_in_power_coalition",
  "pres_in_power_party", "pres_in_power_coalition"
)

if (is.na(muni_src) || is.na(year_src) || is.na(party_src)) {
  stop("Could not map municipality/year/party columns from raw panel.")
}
missing_power <- setdiff(required_power_cols, names(dt))
if (length(missing_power)) {
  stop("Missing power columns in raw panel: ", paste(missing_power, collapse = ", "))
}

keep_cols <- c(muni_src, year_src, party_src, required_power_cols)
dt <- dt[, ..keep_cols]
setnames(dt, c(muni_src, year_src, party_src), c("muni_id", "year", "party"))

dt[, muni_id := {
  x <- as.character(muni_id)
  as.integer(ifelse(nchar(x) == 7L, substr(x, 1L, 6L), x))
}]
dt[, year := as.integer(year)]
dt[, party := trimws(as.character(party))]
for (col in required_power_cols) {
  dt[, (col) := fifelse(is.na(get(col)), 0L, as.integer(get(col)))]
}

dt <- dt[year >= START_YEAR & year <= END_YEAR]
dup_count <- nrow(dt) - uniqueN(dt, by = c("muni_id", "party", "year"))
dt <- unique(dt, by = c("muni_id", "party", "year"))
setorder(dt, muni_id, party, year)

cat("  Analysis window:", START_YEAR, "-", END_YEAR, "\n")
cat("  Duplicate (muni_id, party, year) rows removed:", dup_count, "\n")
cat("  Municipalities:", uniqueN(dt$muni_id), "\n")
cat("  Parties:", uniqueN(dt$party), "\n\n")

for (align_type in ALIGN_TYPES) {
  mayor_col <- paste0("mayor_in_power_", align_type)
  gov_col <- paste0("gov_in_power_", align_type)
  pres_col <- paste0("pres_in_power_", align_type)

  dt[, (align_col_name("mayor_pres", align_type)) := as.integer(get(mayor_col) * get(pres_col))]
  dt[, (align_col_name("mayor_gov", align_type)) := as.integer(get(mayor_col) * get(gov_col))]
  dt[, (align_col_name("triple", align_type)) := as.integer(get(mayor_col) * get(gov_col) * get(pres_col))]

  dt[, (state_col_name(align_type)) := fcase(
    get(align_col_name("triple", align_type)) == 1L, "triple",
    get(mayor_col) == 1L & get(gov_col) == 1L & get(pres_col) == 0L, "mayor_gov",
    get(mayor_col) == 1L & get(gov_col) == 0L & get(pres_col) == 1L, "mayor_pres",
    default = "other"
  )]

  for (term in BROAD_TERMS) {
    delta_col <- delta_col_name(term, align_type)
    dt[, (delta_col) := get(align_col_name(term, align_type)) - shift(get(align_col_name(term, align_type)), n = 1L, type = "lag"),
       by = .(muni_id, party)]
  }
  dt[, (prev_state_col_name(align_type)) := shift(get(state_col_name(align_type)), n = 1L, type = "lag"),
     by = .(muni_id, party)]
}

year_denoms <- dt[, .(
  n_munis = uniqueN(muni_id),
  n_rows = .N
), by = year][order(year)]

cat("Running support and consistency checks...\n")

for (align_type in ALIGN_TYPES) {
  mg_col <- align_col_name("mayor_gov", align_type)
  mp_col <- align_col_name("mayor_pres", align_type)
  tri_col <- align_col_name("triple", align_type)
  algebra_check <- dt[, .(
    bad_mg = sum(abs(get(mg_col) - as.integer(get(state_col_name(align_type)) %in% c("mayor_gov", "triple"))) != 0L, na.rm = TRUE),
    bad_mp = sum(abs(get(mp_col) - as.integer(get(state_col_name(align_type)) %in% c("mayor_pres", "triple"))) != 0L, na.rm = TRUE)
  ), by = year]
  if (algebra_check[, sum(bad_mg + bad_mp)] > 0L) {
    stop("Algebraic consistency failed for align_type=", align_type)
  }

  state_values <- unique(dt[[state_col_name(align_type)]])
  if (!all(state_values %in% STATE_LEVELS)) {
    stop("Unexpected state labels for align_type=", align_type, ": ", paste(setdiff(state_values, STATE_LEVELS), collapse = ", "))
  }

  for (term in LEVEL_TERMS) {
    col <- align_col_name(term, align_type)
    overlap_by_muni_year <- dt[, .(n_matches = sum(get(col), na.rm = TRUE)), by = .(year, muni_id)]
    row_counts <- dt[, .(n_positive = sum(get(col), na.rm = TRUE)), by = year][order(year)]
    muni_counts <- overlap_by_muni_year[, .(n_positive = sum(n_matches > 0L)), by = year][order(year)]

    if (align_type == "party") {
      max_matches <- overlap_by_muni_year[, max(n_matches, na.rm = TRUE)]
      if (is.finite(max_matches) && max_matches > 1L) {
        offending <- overlap_by_muni_year[n_matches > 1L][1]
        stop(
          sprintf(
            "Party overlap %s is not unique within municipality-year. First offending cell: year=%s muni_id=%s matches=%s",
            term, offending$year, offending$muni_id, offending$n_matches
          )
        )
      }
      if (!identical(row_counts$n_positive, muni_counts$n_positive)) {
        stop("Party row counts do not match municipality counts for term ", term)
      }
    } else {
      if (any(row_counts$n_positive < muni_counts$n_positive)) {
        stop("Coalition row counts fall below municipality counts for term ", term)
      }
    }
  }
}

first_obs_mask <- dt[, .I[1L], by = .(muni_id, party)]$V1
transition_dt <- dt[-first_obs_mask]
transition_dt <- transition_dt[year >= TRANSITION_START_YEAR & year <= END_YEAR]

levels_rows_list <- list()
levels_munis_list <- list()
for (align_type in ALIGN_TYPES) {
  summaries <- lapply(LEVEL_TERMS, function(term) {
    col <- align_col_name(term, align_type)

    row_summary <- dt[, .(
      n_rows = .N,
      n_positive = sum(get(col), na.rm = TRUE),
      pct_positive = 100 * mean(get(col), na.rm = TRUE)
    ), by = year][order(year)]
    row_summary[, `:=`(align_type = align_type, term = term)]
    setcolorder(row_summary, c("year", "align_type", "term", "n_rows", "n_positive", "pct_positive"))

    muni_flags <- dt[, .(flag = as.integer(any(get(col) == 1L))), by = .(year, muni_id)]
    muni_summary <- muni_flags[, .(
      n_munis = .N,
      n_positive = sum(flag, na.rm = TRUE),
      pct_positive = 100 * mean(flag, na.rm = TRUE)
    ), by = year][order(year)]
    muni_summary[, `:=`(align_type = align_type, term = term)]
    setcolorder(muni_summary, c("year", "align_type", "term", "n_munis", "n_positive", "pct_positive"))

    list(rows = row_summary, munis = muni_summary)
  })
  levels_rows_list[[align_type]] <- rbindlist(lapply(summaries, `[[`, "rows"))
  levels_munis_list[[align_type]] <- rbindlist(lapply(summaries, `[[`, "munis"))
}

levels_rows <- rbindlist(levels_rows_list)[order(align_type, term, year)]
levels_munis <- rbindlist(levels_munis_list)[order(align_type, term, year)]

term_changes <- rbindlist(lapply(ALIGN_TYPES, function(align_type) {
  rbindlist(lapply(BROAD_TERMS, function(term) {
    dcol <- delta_col_name(term, align_type)
    transition_dt[, .(
      n_rows = .N,
      n_change = sum(get(dcol) != 0L, na.rm = TRUE),
      n_into = sum(get(dcol) == 1L, na.rm = TRUE),
      n_out = sum(get(dcol) == -1L, na.rm = TRUE),
      pct_change = 100 * mean(get(dcol) != 0L, na.rm = TRUE),
      pct_into = 100 * mean(get(dcol) == 1L, na.rm = TRUE),
      pct_out = 100 * mean(get(dcol) == -1L, na.rm = TRUE)
    ), by = year][order(year)][
      , `:=`(align_type = align_type, term = term)
    ][
      , .(year, align_type, term, n_rows, n_change, n_into, n_out, pct_change, pct_into, pct_out)
    ]
  }))
}))[order(align_type, term, year)]

state_transitions <- transition_dt[, rbindlist(lapply(ALIGN_TYPES, function(align_type) {
  from_col <- prev_state_col_name(align_type)
  to_col <- state_col_name(align_type)
  .SD[, .(
    year = year,
    align_type = align_type,
    from_state = get(from_col),
    to_state = get(to_col)
  )]
}))]

state_matrix <- state_transitions[, .(n = .N), by = .(year, align_type, from_state, to_state)][order(align_type, year, from_state, to_state)]
state_matrix[, pct_of_from_state := 100 * n / sum(n), by = .(year, align_type, from_state)]
state_matrix[, pct_of_all_rows := 100 * n / sum(n), by = .(year, align_type)]
setcolorder(state_matrix, c("year", "align_type", "from_state", "to_state", "n", "pct_of_from_state", "pct_of_all_rows"))

for (align_type in ALIGN_TYPES) {
  for (term in BROAD_TERMS) {
    align_type_value <- align_type
    term_value <- term
    members <- TERM_MEMBERSHIP[[term]]
    implied <- state_transitions[align_type == align_type_value, .(
      n_change = sum(xor(from_state %in% members, to_state %in% members)),
      n_into = sum(!(from_state %in% members) & (to_state %in% members)),
      n_out = sum((from_state %in% members) & !(to_state %in% members))
    ), by = year][order(year)]

    direct <- term_changes[align_type == align_type_value & term == term_value, .(year, n_change, n_into, n_out)][order(year)]
    if (!identical(direct, implied)) {
      stop("Direct delta counts do not match state-transition counts for align_type=", align_type, ", term=", term)
    }
    if (term_changes[align_type == align_type_value & term == term_value, any(n_change != n_into + n_out)]) {
      stop("n_change != n_into + n_out for align_type=", align_type, ", term=", term)
    }
  }
}

if (file.exists(align_path)) {
  cat("  Cross-checking against canonical alignment_shocks.qs2...\n")
  shocks <- load_dt(align_path)
  required_overlap_cols <- unlist(lapply(ALIGN_TYPES, function(align_type) {
    vapply(LEVEL_TERMS, align_col_name, align_type = align_type, FUN.VALUE = character(1))
  }), use.names = FALSE)
  missing_overlap_cols <- setdiff(required_overlap_cols, names(shocks))

  if (length(missing_overlap_cols)) {
    cat("    Skipping cross-check; cached alignment_shocks.qs2 lacks overlap columns:\n")
    cat("    ", paste(missing_overlap_cols, collapse = ", "), "\n")
  } else {
    shocks <- shocks[year >= TRANSITION_START_YEAR & year <= END_YEAR]
    shock_counts <- rbindlist(lapply(ALIGN_TYPES, function(align_type) {
      rbindlist(lapply(LEVEL_TERMS, function(term) {
        col <- align_col_name(term, align_type)
        shocks[, .(
          n_positive = sum(get(col), na.rm = TRUE)
        ), by = year][order(year)][
          , `:=`(align_type = align_type, term = term)
        ][
          , .(year, align_type, term, n_positive)
        ]
      }))
    }))[order(align_type, term, year)]

    raw_counts <- transition_dt[, rbindlist(lapply(ALIGN_TYPES, function(align_type) {
      rbindlist(lapply(LEVEL_TERMS, function(term) {
        col <- align_col_name(term, align_type)
        .SD[, .(
          year = year,
          align_type = align_type,
          term = term,
          n_positive = get(col)
        )]
      }))
    }))][, .(n_positive = sum(n_positive, na.rm = TRUE)), by = .(year, align_type, term)][order(align_type, term, year)]

    if (!identical(raw_counts, shock_counts)) {
      stop("Raw overlap counts do not match alignment_shocks.qs2 on the common post-lag sample.")
    }
  }
}

fwrite(levels_munis, levels_muni_csv)
fwrite(levels_rows, levels_rows_csv)
fwrite(term_changes, term_changes_csv)
fwrite(state_matrix, state_matrix_csv)

plot_terms <- c("mayor_gov", "mayor_pres", "triple")
plot_colors <- c(
  mayor_gov = "#1B6CA8",
  mayor_pres = "#A23B72",
  triple = "#3B7A57"
)
plot_pch <- c(
  mayor_gov = 16,
  mayor_pres = 17,
  triple = 15
)

for (align_type in ALIGN_TYPES) {
  align_type_value <- align_type
  plot_dt <- levels_munis[align_type == align_type_value & term %in% plot_terms][order(term, year)]
  y_max <- plot_dt[, max(pct_positive, na.rm = TRUE)]

  png(filename = plot_paths[[align_type]], width = 1100, height = 620)
  par(mar = c(4.2, 4.5, 3.2, 1))
  first_term <- plot_terms[1]
  base_dt <- plot_dt[term == first_term]
  plot(
    base_dt$year, base_dt$pct_positive,
    type = "o", pch = plot_pch[[first_term]], lwd = 2, col = plot_colors[[first_term]],
    ylim = c(0, y_max * 1.1),
    xlab = "Year", ylab = "Municipalities with overlap (%)",
    main = paste("Alignment support by year:", align_type)
  )
  for (term in plot_terms[-1]) {
    term_value <- term
    term_dt <- plot_dt[term == term_value]
    lines(term_dt$year, term_dt$pct_positive, type = "o", pch = plot_pch[[term]], lwd = 2, col = plot_colors[[term]])
  }
  legend(
    "topright",
    legend = plot_terms,
    col = unname(plot_colors[plot_terms]),
    pch = unname(plot_pch[plot_terms]),
    lwd = 2,
    bty = "n"
  )
  dev.off()
}

fmt_pct <- function(x) sprintf("%.2f%%", x)

level_summary_lines <- unlist(lapply(ALIGN_TYPES, function(align_type) {
  align_type_value <- align_type
  c(
    sprintf("### %s", align_type),
    unlist(lapply(LEVEL_TERMS, function(term) {
      term_value <- term
      muni_dt <- levels_munis[align_type == align_type_value & term == term_value]
      row_dt <- levels_rows[align_type == align_type_value & term == term_value]
      max_idx <- which.max(muni_dt$pct_positive)
      min_idx <- which.min(muni_dt$pct_positive)
      c(
        sprintf(
          "- `%s`: municipality-year mean %s; min %s in %d; max %s in %d.",
          term,
          fmt_pct(mean(muni_dt$pct_positive, na.rm = TRUE)),
          fmt_pct(muni_dt$pct_positive[min_idx]),
          muni_dt$year[min_idx],
          fmt_pct(muni_dt$pct_positive[max_idx]),
          muni_dt$year[max_idx]
        ),
        sprintf(
          "- `%s`: row-level mean %s.",
          term,
          fmt_pct(mean(row_dt$pct_positive, na.rm = TRUE))
        )
      )
    })),
    ""
  )
}))

term_change_summary_lines <- unlist(lapply(ALIGN_TYPES, function(align_type) {
  align_type_value <- align_type
  c(
    sprintf("### %s", align_type),
    unlist(lapply(BROAD_TERMS, function(term) {
      term_value <- term
      dt_term <- term_changes[align_type == align_type_value & term == term_value]
      max_idx <- which.max(dt_term$pct_change)
      c(
        sprintf(
          "- `%s`: average yearly change frequency %s; max %s in %d.",
          term,
          fmt_pct(mean(dt_term$pct_change, na.rm = TRUE)),
          fmt_pct(dt_term$pct_change[max_idx]),
          dt_term$year[max_idx]
        ),
        sprintf(
          "- `%s`: average yearly entries %s and exits %s.",
          term,
          fmt_pct(mean(dt_term$pct_into, na.rm = TRUE)),
          fmt_pct(mean(dt_term$pct_out, na.rm = TRUE))
        )
      )
    })),
    ""
  )
}))

transition_pattern_lines <- unlist(lapply(ALIGN_TYPES, function(align_type) {
  align_type_value <- align_type
  top_moves <- state_matrix[
    align_type == align_type_value & from_state != to_state,
    .(n = sum(n)),
    by = .(from_state, to_state)
  ][order(-n)][1:6]
  c(
    sprintf("### %s", align_type),
    if (nrow(top_moves) == 0L) {
      "- No cross-state transitions found."
    } else {
      vapply(seq_len(nrow(top_moves)), function(i) {
        sprintf(
          "- `%s -> %s`: %s row transitions pooled across years.",
          top_moves$from_state[i],
          top_moves$to_state[i],
          format(top_moves$n[i], big.mark = ",")
        )
      }, character(1))
    },
    ""
  )
}))

summary_lines <- c(
  "# Joint Alignment Support and Transitions",
  "",
  sprintf("- Sample window for levels: %d-%d.", START_YEAR, END_YEAR),
  sprintf("- Sample window for transitions: %d-%d.", TRANSITION_START_YEAR, END_YEAR),
  sprintf(
    "- Municipality denominator by year ranges from %s to %s municipalities.",
    format(min(year_denoms$n_munis), big.mark = ","),
    format(max(year_denoms$n_munis), big.mark = ",")
  ),
  sprintf(
    "- Row denominator by year ranges from %s to %s muni-party rows.",
    format(min(year_denoms$n_rows), big.mark = ","),
    format(max(year_denoms$n_rows), big.mark = ",")
  ),
  "",
  "## Levels",
  level_summary_lines,
  "## Term Changes",
  term_change_summary_lines,
  "## Transition Patterns",
  transition_pattern_lines
)
writeLines(summary_lines, con = summary_md, useBytes = TRUE)

cat("Saved outputs:\n")
cat("  ", levels_muni_csv, "\n")
cat("  ", levels_rows_csv, "\n")
cat("  ", term_changes_csv, "\n")
cat("  ", state_matrix_csv, "\n")
cat("  ", summary_md, "\n")
for (align_type in ALIGN_TYPES) {
  cat("  ", plot_paths[[align_type]], "\n")
}
cat("\nJoint alignment support diagnostic complete.\n")
