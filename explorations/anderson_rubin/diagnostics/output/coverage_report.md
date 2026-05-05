# E2: Coverage Check — Size-Bin Aggregation Margin Candidates (A4, A3, B)
Generated: 2026-05-04 17:10:24

## Goal

Evaluate whether the proposed firm-size aggregation margins produce
`(size_bin x cnae_section x muni_id x year)` cells with adequate BNDES
borrower coverage for the shift-share IV first stage.

**Cell unit:** `(size_bin, cnae_section, muni_id, year)` — year-level,
matching the IV and the A2 round-1 decomposition (plan §0.1).

**F0/F1 link:** `docs/PROJECT_BLUEPRINT.md` §3 F0 (admissibility) and F1
(within-muni variation in credit shares requires non-degenerate cells).

**Thresholds:** structurally thin if `share_munis_with_bin_borrower_med < 0.1`; overall thin-cell PASS requires share < 0.3.

---

## 1. Headline Numbers

| Option | n_cells_total | n_cells_with_borrower | share_cells | thin_cell_share | verdict |
|--------|--------------|----------------------|-------------|----------------|---------|
| **A4** | 1,991,722 | 213,184 | 10.7% | 87.4% | **THIN_BIN** |
| **A3** | 1,619,825 | 177,746 | 11.0% | 84.7% | **THIN_BIN** |
| **B**  | 2,025,621 | 204,883 | 10.1% | 86.9% | **THIN_BIN** |

---

## 2. Per-Bin Tables

### Option A4 (4-bin BNDES native: Micro / Pequena / Media / Grande)

| Bin | n_cells_total | n_cells_with_borrower | share_cells | share_munis_med | p50_n_borrow | share_thin | struct_thin |
|-----|--------------|----------------------|-------------|-----------------|-------------|------------|------------|
| Micro | 768,790 | 90,306 | 11.7% | 9.4% | 1 | 84.7% | YES |
| Pequena | 429,404 | 64,980 | 15.1% | 12.3% | 1 | 87.5% | no |
| Media | 372,770 | 39,863 | 10.7% | 9.8% | 1 | 89.5% | YES |
| Grande | 420,758 | 18,035 | 4.3% | 4.4% | 1 | 96.0% | YES |

Structurally thin A4 bins: **Grande, Micro, Media**

### Option A3 (3-bin collapse: MPME / Media / Grande)

| Bin | n_cells_total | n_cells_with_borrower | share_cells | share_munis_med | p50_n_borrow | share_thin | struct_thin |
|-----|--------------|----------------------|-------------|-----------------|-------------|------------|------------|
| MPME | 826,297 | 119,848 | 14.5% | 11.8% | 1 | 81.4% | no |
| Media | 372,770 | 39,863 | 10.7% | 9.8% | 1 | 89.5% | YES |
| Grande | 420,758 | 18,035 | 4.3% | 4.4% | 1 | 96.0% | YES |

Structurally thin A3 bins: **Grande, Media**

### Option B (within-(cnae_section x year) terciles)

| Bin | n_cells_total | n_cells_with_borrower | share_cells | share_munis_med | p50_n_borrow | share_thin | struct_thin |
|-----|--------------|----------------------|-------------|-----------------|-------------|------------|------------|
| Tercile_1 | 708,971 | 53,010 | 7.5% | 5.5% | 1 | 92.7% | YES |
| Tercile_2 | 632,077 | 62,069 | 9.8% | 7.8% | 1 | 89.9% | YES |
| Tercile_3 | 684,573 | 89,804 | 13.1% | 11.4% | 1 | 81.5% | no |

Structurally thin B bins: **Tercile_2, Tercile_1**

---

## 3. Decision Read (plan §5 / §8)

**A-option logic:** A4 fails on Grande (structurally rare large firms in small munis). A3 also fails — no rescue. Escalate to user.

- A4 Micro thin: YES
- A4 Pequena thin: no
- A4 Media thin: YES
- A4 Grande thin: YES
- A4 overall thin-cell share >= 0.30: YES

**Option B logic:** B PASSES (bin 3 not structurally thin) — advances to E3.

---

## 4. Which Options Survive into E3

**E3 survivors: B**

- **B** advances to E3 alongside the surviving A-option.

---

## 5. Files Written

| File | Description |
|------|-------------|
| `coverage_optionA4.csv` | Per-bin metrics for A4 |
| `coverage_optionA3.csv` | Per-bin metrics for A3 |
| `coverage_optionB.csv` | Per-bin metrics for B |
| `coverage_cells_optionA4.csv` | Full cell long table (downstream E3 input), A4 |
| `coverage_cells_optionA3.csv` | Full cell long table, A3 |
| `coverage_cells_optionB.csv` | Full cell long table, B |
| `coverage_summary.csv` | One row per option with overall verdict |

