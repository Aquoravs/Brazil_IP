#!/usr/bin/env Rscript
# =============================================================================
# ar_instrument_combination_sim.R
#
# Monte Carlo "dummy example" for the 2026-05-14 advisor question on instrument
# combinations. It shows how the choice of instrument SET changes the
# Anderson-Rubin test, which is the joint cluster-robust Wald F on the reduced
# form  log GDP ~ (instrument set) | FE.
#
# AR test of H0: beta = 0 (sectoral composition has no first-order GDP effect).
# Under H0 the reduced-form coefficient on every VALID instrument is zero, so
# the AR test = joint F on the instrument set. The set we feed it matters.
#
# Instrument sets compared:
#   S0  Mayor only             {Z_M}                      (clean anchor)
#   S1  Additive M, G, P       {Z_M, Z_G, Z_P}            old design, pre-D25
#   S2  Interaction only       {Z_MG}                     2026-05-14 candidate
#   S3  Main effects + inter.  {Z_M, Z_G, Z_MG}           2026-05-14 notes ask
#   S4  Cross-office           {Z_M, Z_MG, Z_MP, Z_MGP}   current design (D25)
#   S5  Cross-office + noise    S4 + 5 irrelevant instruments
#
# Three regimes the example isolates:
#   (a) add a VALID + RELEVANT instrument   -> power rises   (S4 vs S2)
#   (b) add a VALID but IRRELEVANT one      -> power falls   (S5 vs S4)
#   (c) add an INVALID instrument           -> size distortion / false
#       rejection of the optimality null    (S1, S3 once the governor wave
#                                            has a direct GDP effect)
#
# The DGP encodes the project's maintained mechanism: credit reaches local
# firms only when the mayor (the local intermediary) coincides with a higher
# tier. The example illustrates the CONSEQUENCES of that mechanism for the
# instrument set; it does not prove the mechanism.
# =============================================================================

suppressPackageStartupMessages(library(data.table))
set.seed(20260520L)

# ---- paths ------------------------------------------------------------------
this_file <- sub("^--file=", "",
                 grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
BR <- getwd()
if (length(this_file) && !is.na(this_file) && nzchar(this_file)) {
  BR <- normalizePath(file.path(dirname(this_file), ".."), winslash = "/")
}
OUT <- file.path(BR, "output")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ---- DGP parameters ---------------------------------------------------------
N       <- 4000L      # municipalities (one cross-section)
REPS    <- 2000L      # Monte Carlo replications
P_ALIGN <- 0.40       # P(an office is held by the firm-side party)
PI_M    <- 0.30       # mayor-only ("local capital") first-stage loading
PI_MG   <- 1.00       # mayor x governor first-stage loading
PI_MP   <- 0.80       # mayor x president first-stage loading
SD_U    <- 0.50       # composition noise
SD_NU   <- 0.50       # municipal-fundamental noise
SD_EPS  <- 1.50       # GDP noise
ALPHA   <- 0.05

SET_NAMES <- c("S0_mayor", "S1_additive", "S2_interaction",
               "S3_main_inter", "S4_crossoffice", "S5_kitchensink")
CH_NAMES  <- c("ch_M", "ch_MG", "ch_MP", "ch_MGP", "ch_G", "ch_P")
COLS      <- c(SET_NAMES, CH_NAMES)

# ---- one Monte Carlo replication --------------------------------------------
# beta : structural composition effect (0 = optimality null true)
# d_G  : direct GDP effect of the governor wave (0 = governor exclusion holds)
one_draw <- function(beta, d_G) {
  x  <- runif(N, 0.1, 1.0)        # predetermined sector exposure weight
  aM <- rbinom(N, 1L, P_ALIGN)    # mayor aligned    -- local, idiosyncratic
  aG <- rbinom(N, 1L, P_ALIGN)    # governor aligned -- regional wave
  aP <- rbinom(N, 1L, P_ALIGN)    # president aligned -- national wave

  Z_M   <- x * aM
  Z_G   <- x * aG
  Z_P   <- x * aP
  Z_MG  <- x * aM * aG
  Z_MP  <- x * aM * aP
  Z_MGP <- x * aM * aG * aP

  # endogenous composition: moves only through mayor-crossed channels
  s <- PI_M * Z_M + PI_MG * Z_MG + PI_MP * Z_MP + rnorm(N, 0, SD_U)

  # municipal fundamental: d_G > 0 makes the governor wave aG correlate with
  # theta, i.e. an exclusion violation for any instrument that contains aG.
  theta <- d_G * aG + rnorm(N, 0, SD_NU)

  Y <- beta * s + theta + rnorm(N, 0, SD_EPS)

  noise <- matrix(runif(N * 5L, 0, 1), N, 5L)   # valid but irrelevant

  # AR test = joint F that every column of Zmat has zero reduced-form coef
  ar_reject <- function(Zmat) {
    fs <- summary(lm(Y ~ Zmat))$fstatistic
    unname(pf(fs[1L], fs[2L], fs[3L], lower.tail = FALSE) < ALPHA)
  }

  c(
    ar_reject(cbind(Z_M)),
    ar_reject(cbind(Z_M, Z_G, Z_P)),
    ar_reject(cbind(Z_MG)),
    ar_reject(cbind(Z_M, Z_G, Z_MG)),
    ar_reject(cbind(Z_M, Z_MG, Z_MP, Z_MGP)),
    ar_reject(cbind(Z_M, Z_MG, Z_MP, Z_MGP, noise)),
    ar_reject(cbind(Z_M)),
    ar_reject(cbind(Z_MG)),
    ar_reject(cbind(Z_MP)),
    ar_reject(cbind(Z_MGP)),
    ar_reject(cbind(Z_G)),
    ar_reject(cbind(Z_P))
  )
}

run_cell <- function(beta, d_G) {
  acc <- numeric(length(COLS))
  for (r in seq_len(REPS)) acc <- acc + one_draw(beta, d_G)
  setNames(acc / REPS, COLS)
}

# ---- scenario grid ----------------------------------------------------------
# Power curve: vary beta with the governor exclusion restriction intact.
beta_grid <- c(0.00, 0.10, 0.20)
# Size distortion: hold beta = 0 (optimality null TRUE) and turn on d_G.
dG_grid   <- c(0.00, 0.50, 1.00)

message(sprintf("[INFO] %s | N=%d, REPS=%d", Sys.time(), N, REPS))

power_rows <- vector("list", length(beta_grid))
for (i in seq_along(beta_grid)) {
  b <- beta_grid[i]
  message(sprintf("[INFO] power cell: beta=%.2f, d_G=0", b))
  res <- run_cell(beta = b, d_G = 0)
  power_rows[[i]] <- data.table(beta = b, d_G = 0, t(res))
}

dist_rows <- vector("list", length(dG_grid))
for (i in seq_along(dG_grid)) {
  g <- dG_grid[i]
  message(sprintf("[INFO] distortion cell: beta=0, d_G=%.2f", g))
  res <- run_cell(beta = 0, d_G = g)
  dist_rows[[i]] <- data.table(beta = 0, d_G = g, t(res))
}

power_dt <- rbindlist(power_rows)
dist_dt  <- rbindlist(dist_rows)

fwrite(power_dt, file.path(OUT, "ar_combination_power.csv"))
fwrite(dist_dt,  file.path(OUT, "ar_combination_size_distortion.csv"))

# ---- console report ---------------------------------------------------------
pct <- function(x) formatC(100 * x, format = "f", digits = 1, width = 6)

cat("\n=== Rejection rate by instrument SET (d_G = 0) ==========================\n")
cat("beta=0 row is SIZE (target 5.0); beta>0 rows are POWER.\n\n")
cat(sprintf("%-7s %-9s %-12s %-14s %-15s %-16s %-14s\n",
            "beta", "S0 mayor", "S1 add MGP", "S2 inter MG",
            "S3 M+G+MG", "S4 crossoffice", "S5 +noise"))
for (i in seq_len(nrow(power_dt))) {
  r <- power_dt[i]
  cat(sprintf("%-7.2f %s   %s     %s       %s       %s        %s\n",
              r$beta, pct(r$S0_mayor), pct(r$S1_additive),
              pct(r$S2_interaction), pct(r$S3_main_inter),
              pct(r$S4_crossoffice), pct(r$S5_kitchensink)))
}

cat("\n=== Size of the AR test under a GOVERNOR exclusion violation ============\n")
cat("beta = 0 throughout: every rejection here is a FALSE rejection of the\n")
cat("optimality null. Target is 5.0.\n\n")
cat(sprintf("%-7s %-9s %-12s %-14s %-15s %-16s\n",
            "d_G", "S0 mayor", "S1 add MGP", "S2 inter MG",
            "S3 M+G+MG", "S4 crossoffice"))
for (i in seq_len(nrow(dist_dt))) {
  r <- dist_dt[i]
  cat(sprintf("%-7.2f %s   %s     %s       %s       %s\n",
              r$d_G, pct(r$S0_mayor), pct(r$S1_additive),
              pct(r$S2_interaction), pct(r$S3_main_inter),
              pct(r$S4_crossoffice)))
}

cat("\n=== Per-channel size under the GOVERNOR exclusion violation =============\n")
cat("Single-instrument AR test, one channel at a time, beta = 0.\n")
cat("Shows WHICH channels inherit the contamination.\n\n")
cat(sprintf("%-7s %-9s %-9s %-9s %-9s %-9s %-9s\n",
            "d_G", "M", "MxG", "MxP", "MxGxP", "G only", "P only"))
for (i in seq_len(nrow(dist_dt))) {
  r <- dist_dt[i]
  cat(sprintf("%-7.2f %s %s %s %s %s %s\n",
              r$d_G, pct(r$ch_M), pct(r$ch_MG), pct(r$ch_MP),
              pct(r$ch_MGP), pct(r$ch_G), pct(r$ch_P)))
}
cat("\n[INFO] wrote ar_combination_power.csv, ar_combination_size_distortion.csv\n")
