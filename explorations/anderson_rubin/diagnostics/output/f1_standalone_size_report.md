# F1 Within-Muni Variance Decomposition — Standalone Size (S3, S4)
Generated: 2026-05-05 10:52:56

## Goal

Test F1 (within-muni × time variation) on **standalone size margins** — the
third F0-admissible margin family, after CNAE-based (round 1, D15) and
CNAE × size (round 2, D16). Here the aggregation bins are size bins alone,
with no sector cross.

**Size classifiers (S-prefix per D19):**
- S3: MPME (0–49) / Media (50–499) / Grande (500+) — 3 bins
- S4: Micro (0–9) / Pequena (10–49) / Media (50–499) / Grande (500+) — 4 bins

**Denominator:** single (all bins sum to 1; no XX exclusion applies to size).

**SUPPORTED rule:** at least one bin with med σ_within > 0.05 AND share_within > 0.2.

---

## 1. Per-bin decomposition

### S3 (3 bins: MPME / Media / Grande)

| Bin | Label | n_munis | mean_share | total_var | share_within | med σ_within | p10 σ | p90 σ |
|-----|-------|--------:|----------:|---------:|------------:|------------:|------:|------:|
| 1 | MPME | 5,200 | 0.7126 | 0.135087 | 0.4836 | 0.1940 | 0.0000 | 0.4323 |
| 2 | Media | 5,200 | 0.1862 | 0.090297 | 0.6109 | 0.1426 | 0.0000 | 0.4079 |
| 3 | Grande | 5,200 | 0.1013 | 0.061769 | 0.5382 | 0.0000 | 0.0000 | 0.3443 |

### S4 (4 bins: Micro / Pequena / Media / Grande)

| Bin | Label | n_munis | mean_share | total_var | share_within | med σ_within | p10 σ | p90 σ |
|-----|-------|--------:|----------:|---------:|------------:|------------:|------:|------:|
| 1 | Micro | 5,200 | 0.4583 | 0.159280 | 0.5193 | 0.2985 | 0.0000 | 0.4831 |
| 2 | Pequena | 5,200 | 0.2513 | 0.103523 | 0.6938 | 0.2510 | 0.0000 | 0.4563 |
| 3 | Media | 5,200 | 0.1881 | 0.091258 | 0.6100 | 0.1445 | 0.0000 | 0.4082 |
| 4 | Grande | 5,200 | 0.1023 | 0.062482 | 0.5385 | 0.0000 | 0.0000 | 0.3449 |

---

## 2. Summary verdicts

| Margin | n_bins | n_supported | mean share_within | med share_within | max med σ | verdict |
|--------|-------:|------------:|-----------------:|----------------:|----------:|---------|
| standalone_S3 | 3 | 2 | 0.5442 | 0.5382 | 0.1940 | SUPPORTED |
| standalone_S4 | 4 | 3 | 0.5904 | 0.5743 | 0.2985 | SUPPORTED |

---

## 3. Comparison to existing margins

| Margin | Denom | n_bins | mean share_within | Source |
|--------|-------|-------:|-----------------:|--------|
| cnae_section | V1 | 21 | 0.7639 | round 1 sector-only (D15) |
| cnae_section | V2 | 21 | 0.7876 | round 1 sector-only (D15) |
| policy_block | V1 | 5 | 0.6233 | round 1 sector-only (D15) |
| policy_block | V2 | 5 | 0.6669 | round 1 sector-only (D15) |
| policy_block_active | V1 | 4 | 0.6233 | round 1 sector-only (D15) |
| policy_block_active | V2 | 4 | 0.6251 | round 1 sector-only (D15) |
| policy_block_A2 | V1 | 8 | 0.6153 | round 2 sector x size (D16) |
| policy_block_A2 | V2 | 8 | 0.6168 | round 2 sector x size (D16) |
| policy_block_A3 | V1 | 12 | 0.6420 | round 2 sector x size (D16) |
| policy_block_A3 | V2 | 12 | 0.6432 | round 2 sector x size (D16) |
| standalone_S3 | all | 3 | 0.5442 | standalone size (this run) |
| standalone_S4 | all | 4 | 0.5904 | standalone size (this run) |

---

## 4. Interpretation

### What this tests

Standalone size margins collapse the sector dimension entirely — the IV
projects alignment shocks onto size bins only. Compared to the production
margin `policy_block_active × S3` (12 bins, mean share_within = 0.642),
standalone S3 has 3 bins and S4 has 4 bins — a strictly coarser partition.

### Key questions for downstream

1. **K = 3–4 instruments.** BHJ (2022) many-sector asymptotics require a
   growing number of sectors. With K = 3–4, standard SSIV inference may not
   apply; however, the Anderson–Rubin test is valid with any number of
   instruments.
2. **Coverage improvement.** E2 flagged Media and Grande as thin when crossed
   with sector. Standalone size aggregates across sectors, so cells should be
   fatter. Whether this translates into broader muni coverage is reported above.
3. **Institutional channel.** BNDES targets by porte (firm size), but the
   political alignment mechanism (P1) may operate more through sectors than
   size. This is an F4 question, not F1.

### Caveats

- T3 imputation: cells from `02_size_bin_coverage.R` — stated Micro/Pequena
  unmatched loans imputed to MPME (S3 bin 1, S4 bins 1–2); stated
  Media/Grande unmatched dropped.
- S4 was dropped at E2 for the sector × size cross due to thin coverage.
  Standalone aggregation across sectors may rescue it by fattening cells,
  but the same structural thinness on Media and Grande persists.

---

## 5. Files written

| File | Description |
|------|-------------|
| `f1_standalone_S3_decomposition.csv` | Per-bin variance decomposition, S3 |
| `f1_standalone_S4_decomposition.csv` | Per-bin variance decomposition, S4 |
| `f1_standalone_size_summary.csv` | Summary + verdict for S3 and S4 |
| `f1_standalone_size_report.md` | This file |

