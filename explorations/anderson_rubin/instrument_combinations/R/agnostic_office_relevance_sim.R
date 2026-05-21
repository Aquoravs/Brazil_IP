#!/usr/bin/env Rscript
# =============================================================================
# agnostic_office_relevance_sim.R
#
# Companion to ar_instrument_combination_sim.R. That first script ASSUMED the
# mechanism (only mayor-crossed channels move composition) and showed the
# consequences. This script drops that assumption and asks the open question:
#
#   If we do NOT know which office drives credit / composition, how do we let
#   the data tell us, and what does it cost to impose the mayor-restriction if
#   it turns out to be wrong?
#
# The agnostic tool is the SATURATED first stage. With three binary alignment
# indicators (mayor aM, governor aG, president aP) there are seven non-constant
# channels:
#       M, G, P, M.G, M.P, G.P, M.G.P
# These are the fully saturated basis for ANY function of (aM, aG, aP). A
# regression of the endogenous object on all seven imposes nothing about which
# office matters: the channel that carries the signal is read off the
# coefficients. This is a RELEVANCE diagnostic (a first-stage projection); it
# needs no exclusion restriction.
#
# The script runs three "worlds" -- the truth is M.G-only, P-only, or both --
# and shows (1) the saturated first stage recovers the true channel in every
# world; (2) the mayor-restricted instrument set {M, M.G, M.P, M.G.P} has
# almost no AR power when the truth is P-only.
# =============================================================================

suppressPackageStartupMessages(library(data.table))
set.seed(20260520L)

this_file <- sub("^--file=", "",
                 grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
BR <- getwd()
if (length(this_file) && !is.na(this_file) && nzchar(this_file)) {
  BR <- normalizePath(file.path(dirname(this_file), ".."), winslash = "/")
}
OUT <- file.path(BR, "output")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ---- parameters -------------------------------------------------------------
N       <- 4000L
REPS    <- 1500L
P_ALIGN <- 0.40
SD_U    <- 0.50      # composition noise
SD_EPS  <- 1.50      # GDP noise
ALPHA   <- 0.05

# ---- build the seven shift-share channels -----------------------------------
make_Z <- function(n) {
  x  <- runif(n, 0.1, 1.0)
  aM <- rbinom(n, 1L, P_ALIGN)
  aG <- rbinom(n, 1L, P_ALIGN)
  aP <- rbinom(n, 1L, P_ALIGN)
  data.table(
    Z_M   = x * aM,
    Z_G   = x * aG,
    Z_P   = x * aP,
    Z_MG  = x * aM * aG,
    Z_MP  = x * aM * aP,
    Z_GP  = x * aG * aP,
    Z_MGP = x * aM * aG * aP
  )
}

# composition under a "world": named vector of true channel loadings
build_s <- function(Z, loadings) {
  s <- rnorm(nrow(Z), 0, SD_U)
  for (ch in names(loadings)) s <- s + loadings[[ch]] * Z[[paste0("Z_", ch)]]
  s
}

worlds <- list(
  "MxG only"  = c(MG = 1.0),
  "P only"    = c(P  = 1.0),
  "MxG and P" = c(MG = 1.0, P = 0.8)
)

# =============================================================================
# Part 1 -- the saturated first stage recovers the true channel
# =============================================================================
cat("\n=== Part 1: saturated first stage (one draw, N=20000) ==================\n")
cat("Regress composition s on ALL SEVEN channels. The true channel(s) show a\n")
cat("large coefficient; the rest are ~0. No restriction imposed.\n")

fs_rows <- list()
for (wn in names(worlds)) {
  Zb <- make_Z(20000L)
  sb <- build_s(Zb, worlds[[wn]])
  fit <- lm(sb ~ ., data = cbind(data.table(sb = sb), Zb))
  ct  <- summary(fit)$coefficients
  ct  <- ct[grep("^Z_", rownames(ct)), c("Estimate", "t value"), drop = FALSE]
  cat(sprintf("\n  World: %s   (true loadings: %s)\n", wn,
              paste(sprintf("%s=%.2f", names(worlds[[wn]]), worlds[[wn]]),
                    collapse = ", ")))
  cat(sprintf("    %-8s %10s %10s\n", "channel", "coef", "t"))
  for (rn in rownames(ct)) {
    cat(sprintf("    %-8s %10.3f %10.1f\n",
                sub("^Z_", "", rn), ct[rn, 1L], ct[rn, 2L]))
    fs_rows[[length(fs_rows) + 1L]] <- data.table(
      world = wn, channel = sub("^Z_", "", rn),
      coef = ct[rn, 1L], t = ct[rn, 2L])
  }
}
fwrite(rbindlist(fs_rows), file.path(OUT, "saturated_first_stage.csv"))

# =============================================================================
# Part 2 -- AR power: mayor-restricted set vs saturated set vs per channel
# =============================================================================
COLS <- c("M_restricted", "saturated",
          "ch_M", "ch_G", "ch_P", "ch_MG", "ch_MP", "ch_GP", "ch_MGP")

ar_reject <- function(Y, Zmat) {
  fs <- summary(lm(Y ~ Zmat))$fstatistic
  unname(pf(fs[1L], fs[2L], fs[3L], lower.tail = FALSE) < ALPHA)
}

one_draw <- function(loadings, beta) {
  Z  <- make_Z(N)
  s  <- build_s(Z, loadings)
  Y  <- beta * s + rnorm(N, 0, SD_EPS)
  Zm <- as.matrix(Z)
  c(
    ar_reject(Y, Zm[, c("Z_M", "Z_MG", "Z_MP", "Z_MGP")]),
    ar_reject(Y, Zm),
    ar_reject(Y, Zm[, "Z_M",   drop = FALSE]),
    ar_reject(Y, Zm[, "Z_G",   drop = FALSE]),
    ar_reject(Y, Zm[, "Z_P",   drop = FALSE]),
    ar_reject(Y, Zm[, "Z_MG",  drop = FALSE]),
    ar_reject(Y, Zm[, "Z_MP",  drop = FALSE]),
    ar_reject(Y, Zm[, "Z_GP",  drop = FALSE]),
    ar_reject(Y, Zm[, "Z_MGP", drop = FALSE])
  )
}

run_cell <- function(loadings, beta) {
  acc <- numeric(length(COLS))
  for (r in seq_len(REPS)) acc <- acc + one_draw(loadings, beta)
  setNames(acc / REPS, COLS)
}

beta_grid <- c(0.00, 0.20)
pow_rows  <- list()
for (wn in names(worlds)) {
  for (b in beta_grid) {
    message(sprintf("[INFO] AR power: world=%s, beta=%.2f", wn, b))
    res <- run_cell(worlds[[wn]], b)
    pow_rows[[length(pow_rows) + 1L]] <-
      data.table(world = wn, beta = b, t(res))
  }
}
pow_dt <- rbindlist(pow_rows)
fwrite(pow_dt, file.path(OUT, "agnostic_ar_power.csv"))

pct <- function(x) formatC(100 * x, format = "f", digits = 1, width = 6)

cat("\n=== Part 2: AR rejection rate, % (beta=0 is size, beta=0.20 is power) ===\n")
cat("M_restricted = {M, MxG, MxP, MxGxP}; saturated = all seven channels.\n\n")
cat(sprintf("%-12s %-6s %-13s %-12s %-9s %-9s %-9s\n",
            "world", "beta", "M_restricted", "saturated",
            "ch_M", "ch_P", "ch_MG"))
for (i in seq_len(nrow(pow_dt))) {
  r <- pow_dt[i]
  cat(sprintf("%-12s %-6.2f %s        %s     %s %s %s\n",
              r$world, r$beta, pct(r$M_restricted), pct(r$saturated),
              pct(r$ch_M), pct(r$ch_P), pct(r$ch_MG)))
}

cat("\n[INFO] wrote saturated_first_stage.csv, agnostic_ar_power.csv\n")
