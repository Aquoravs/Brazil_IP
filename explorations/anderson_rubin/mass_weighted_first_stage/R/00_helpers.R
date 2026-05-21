suppressPackageStartupMessages({
  library(data.table)
  library(qs2)
})

setDTthreads(0)

find_project_root_local <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, "CLAUDE.md")) &&
        dir.exists(file.path(current, "scripts", "R"))) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop("Could not find project root from ", start)
    }
    current <- parent
  }
}

PROJECT_ROOT <- find_project_root_local()
EXP_DIR <- normalizePath(
  file.path(PROJECT_ROOT, "explorations", "anderson_rubin", "mass_weighted_first_stage"),
  winslash = "/",
  mustWork = TRUE
)
OUT_DIR <- file.path(EXP_DIR, "output")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

processed_path <- function(...) file.path(PROJECT_ROOT, "data", "processed", ...)
explore_path <- function(...) file.path(EXP_DIR, ...)
out_path <- function(...) file.path(OUT_DIR, ...)

read_qs_dt <- function(path) {
  if (!file.exists(path)) stop("Missing input: ", path)
  x <- qs_read(path)
  setDT(x)
  x
}

write_qs_atomic <- function(obj, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = "tmp-", tmpdir = dirname(path), fileext = ".qs2")
  qs_save(obj, tmp)
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Failed to write ", path)
  invisible(path)
}

write_csv_atomic <- function(dt, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = "tmp-", tmpdir = dirname(path), fileext = ".csv")
  fwrite(dt, tmp)
  if (file.exists(path)) file.remove(path)
  if (!file.rename(tmp, path)) stop("Failed to write ", path)
  invisible(path)
}

active_blocks <- c("Agro", "Ind", "Infra", "Serv")
mayor_elections <- c(2005L, 2009L, 2013L, 2017L)

term_map <- rbindlist(lapply(mayor_elections, function(e) {
  data.table(treatment_year = e, year = e:min(e + 3L, 2017L))
}))

pre_years_for_election <- function(e) {
  yrs <- (e - 4L):(e - 1L)
  yrs[yrs >= 2002L & yrs <= 2017L]
}

channel_map <- data.table(
  channel = c("M", "MP", "MG", "MGP"),
  level_col = c(
    "align_mayor_coalition",
    "align_mayor_pres_coalition",
    "align_mayor_gov_coalition",
    "align_triple_coalition"
  ),
  diff_col = c(
    "dalign_mayor_coalition",
    "dalign_mayor_pres_coalition",
    "dalign_mayor_gov_coalition",
    "dalign_triple_coalition"
  ),
  fa_col = c(
    "FA_mayor_coalition",
    "FA_mayor_pres_coalition",
    "FA_mayor_gov_coalition",
    "FA_triple_coalition"
  ),
  dfa_col = c(
    "dFA_mayor_coalition",
    "dFA_mayor_pres_coalition",
    "dFA_mayor_gov_coalition",
    "dFA_triple_coalition"
  )
)

event_type_for_year <- function(year) {
  fifelse(year %in% c(2005L, 2009L, 2013L, 2017L), "mayoral_transition",
    fifelse(year %in% c(2007L, 2011L, 2015L), "gov_pres_transition", "non_event"))
}

safe_wald_stat <- function(mod, keep = "^Z_") {
  tryCatch({
    as.numeric(fixest::wald(mod, keep = keep)$stat)
  }, error = function(e) NA_real_)
}

fmt_num <- function(x, digits = 3) {
  ifelse(is.na(x), "", formatC(x, format = "f", digits = digits))
}
