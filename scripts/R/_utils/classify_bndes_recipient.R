# classify_bndes_recipient.R
#
# Helper: classify BNDES loan recipients into one of
#   {"productive-firm", "financial-institution", "public-entity", "other"}.
#
# Mirrors the A0.4 audit logic
# (explorations/firm_universe/bndes_recipient_audit/R/audit_bndes_recipients.R),
# which is the canonical Phase 0 classification per D5-op.
#
# Priority order (deterministic):
#   1. public-entity        (highest)
#   2. financial-institution
#   3. productive-firm
#   4. other                (residual; lowest)
#
# Required input columns on `dt` (a data.table):
#   - nature              (Natureza do cliente — string)
#   - subsector_cnae_cod  (CNAE code, may begin with a letter)
#   - cnae_section        (single-letter CNAE section, may be NA)
#
# Notes on rule fidelity to A0.4:
#   - FI by CNAE division 64-66 (financial activities). This is the
#     classifier used by A0.4 — it matches the indirect-onlending banks
#     and any other CNAE-64/65/66-classified recipient. No fixed bank list
#     is maintained; the audit established this rule yields 0.1% of total
#     disbursement with ≤0.015% double-counting risk.
#   - Public-entity by `nature` prefix or CNAE section O.
#   - Productive-firm is the residual private + sector-tagged class.
#
# The helper returns the input `dt` with a new `recipient_class` column.
# Hyphenated class labels match D5-op naming.

classify_bndes_recipient <- function(dt) {
  stopifnot(
    "Input must be a data.table" = inherits(dt, "data.table"),
    "Missing column: nature"             = "nature"             %in% names(dt),
    "Missing column: subsector_cnae_cod" = "subsector_cnae_cod" %in% names(dt),
    "Missing column: cnae_section"       = "cnae_section"       %in% names(dt)
  )

  ascii_upper_local <- function(x) {
    toupper(iconv(trimws(as.character(x)), to = "ASCII//TRANSLIT"))
  }

  nature_u <- ascii_upper_local(dt[["nature"]])
  code     <- trimws(as.character(dt[["subsector_cnae_cod"]]))
  section  <- dt[["cnae_section"]]

  # CNAE division 2-digit: positions 2-3 if first char is a letter, else first 2.
  starts_letter <- grepl("^[A-Za-z]", code)
  div2_char <- ifelse(starts_letter, substr(code, 2L, 3L), substr(code, 1L, 2L))
  div2 <- suppressWarnings(as.integer(div2_char))

  # Initialise residual.
  cls <- rep("other", nrow(dt))

  # Financial institutions (CNAE 64-66).
  is_fi <- !is.na(div2) & div2 %in% 64:66
  cls[is_fi] <- "financial-institution"

  # Productive firms: PRIVADA + non-NA CNAE section + not FI + not yet assigned.
  is_priv_prod <- !is.na(nature_u) & nature_u == "PRIVADA" &
                  !is.na(section) & cls == "other"
  cls[is_priv_prod] <- "productive-firm"

  # Public entity (highest priority — overrides any prior assignment).
  is_public_nature <- !is.na(nature_u) & (
    startsWith(nature_u, "PUBLICA") |
    startsWith(nature_u, "ADMINISTRACAO PUBLICA")
  )
  is_public_section <- !is.na(section) & section == "O"
  is_public <- is_public_nature | is_public_section
  cls[is_public] <- "public-entity"

  dt[, recipient_class := cls]
  dt
}
