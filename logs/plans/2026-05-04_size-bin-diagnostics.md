---
title: Size-Bin Aggregation Margin — Four-Exercise Diagnostic Plan
date: 2026-05-04
status: DRAFT — revised 2026-05-04 (rev 2): added E0 stability pre-exercise; primary Option A is now the 4-bin BNDES-native rule (A4); 3-bin collapse (A3) becomes a fallback; V1+V2 in E3; all 7 cycles for loan→cycle mapping; fall-back baseline rule for missing-cycle firms
related:
  - docs/PROJECT_BLUEPRINT.md §7 Track 1 (Next action: variance decomposition on cnae_section × size_tertile)
  - logs/strategy/bndes_allocation_logic.md (A1 memo, D14 admissibility criterion)
  - explorations/anderson_rubin/diagnostics/within_muni_variation.R (round-1 F1 reference)
  - data/processed/size_bin_mapping.qs2 (Option C national tercile fallback, already built)
---

# Plan: choosing the firm-size aggregation margin for the AR test

## 0. Goal in one sentence

Decide which firm-size classifier (crossed with `cnae_section`) becomes the **production aggregation margin for the AR-test SSIV** — choosing among **Option A4** (4-bin BNDES native: Micro 0–9 / Pequena 10–49 / Média 50–499 / Grande 500+), **Option A3** (3-bin collapse of A4: 0–49 / 50–499 / 500+), and **Option B** (within-(cnae_section × year) terciles, input = per-cycle baseline mean) — using a stability pre-exercise (E0) plus three diagnostics (E1 alignment of A4 with BNDES porte → E2 coverage of A3, A4, B → E3 F1 within-muni variation), and add a conditional F1 check on the existing `policy_block × Agro` spec (E3b).

**The chosen rule propagates into the production pipeline** (`30c` successor → `31` exposure weights → `34` shift-share instruments → `41` muni panel → AR test). This is not a descriptive exercise; it commits the project to a margin.

## 0.1 Cycle vs. year (load-bearing distinction)

Two units appear in this plan and they should not be conflated:

- **Bin-construction unit = election cycle.** A firm's `size_bin` is computed from its mean `n_employees` over the cycle's pre-election baseline window. This is the level at which the bin is *defined*. Per-year bin assignment was rejected (see `30c` header) because post-election alignment shocks could feed back into the firm's employment within a year and so into the bin — the bin must be pre-treatment relative to the cycle's outcome.
- **Panel temporal unit = year.** The IV credit shares, the SSIV residualization, and the F1 within-muni variance decomposition all operate on the `(muni × year × bin)` panel. `within_muni_variation.R` aggregates and decomposes at year level. Round 1 of A2 was at year level. A2 round 2 (this plan) must match.

Inside a cycle `c`, every year `t ∈ {bl_end_c+1, …, bl_end_{c+1}}` inherits the same firm-cycle bin. So the bin is constant within a cycle for a given firm, but the cells indexed for coverage and F1 are still annual.

## 0.2 V2 denominator (clarification)

`V2` = full-economy denominator. For the size × sector margin under V2:
- **Denominator** is the muni's total BNDES disbursement summed over **all 63 bins** (21 CNAE sections × 3 size bins), including the four "irrelevant" XX sections K, O, T, U. The denominator does **not** drop them — it is the muni's actual total BNDES book. This mirrors round 1's V2 spec for `policy_block` and `policy_block_active`.
- **Output bins** (the bins for which we report a share and run the variance decomposition) are only the **51 active-section bins** (excluding K_*, O_*, T_*, U_*). This mirrors round 1's M3 (`policy_block_active × V2`): full-economy denominator, active-only output. Shares for active bins under V2 do not sum to 1 within a (muni, year), and that is intentional — the residual mass goes to KOTU credit, which we exclude on theoretical grounds (D12).

## 1. Context

- F0 is CONFIRMED (D14). The admissibility criterion: a margin must be a **firm-side classifier defined for every RAIS firm**, including non-borrowers, so the muni baseline share `s_{m,b,t0}` is well-defined. Both A and B are admissible (employment is defined for every RAIS firm).
- F1 round 1 is CONFIRMED (D15) on `cnae_section`, `policy_block`, `policy_block_active` × {V1, V2}, with med σ_within ≈ 0.26–0.33 and share_within ≈ 0.58–0.83 on active blocks.
- Round 2 candidate per D14: `cnae_section × size_tertile`. This plan refines the size-tertile definition by horse-racing A vs. B before re-running the F1 diagnostic.
- Standing convention (memory `feedback_sector_classification_convention`): **size bins only within sectors** — no standalone size_bin margin.
- Option C (national terciles per cycle) is already in `data/processed/size_bin_mapping.qs2` from script `30c`. It is a fallback only — no new diagnostic on C; we cite its existing output if A and B both fail.

## 2. Inputs (verified to exist)

| Path | Role |
|---|---|
| `data/processed/rais_bndes_reconstructed.fst` | Full RAIS-BNDES panel: `firm_id, muni_id, year, cnae_section, in_bndes, value_dis_real_2018_total, n_employees`. Used by E2 and E3. |
| `data/processed/bndes_loan_level.qs2` | Loan-level with BNDES `size` (porte) column: `Micro/Pequena/Média/Grande` (or NA). Used by E1. Also: `firm_id, year, cnae_section, value_dis_real_2018, value_dis`. |
| `data/processed/policy_block_mapping.qs2` | CNAE-section → policy_block crosswalk (5-bin: Agro/Ind/Infra/Serv/XX). Used by E3b. |
| `data/processed/size_bin_mapping.qs2` | Option C national-tercile crosswalk per cycle (built by `30c`). Cited only if A and B both fail. |

Election-cycle baseline windows (mirror script `30c` and script `33`):

```r
BASELINE_WINDOWS <- rbindlist(list(
  data.table(election_cycle = 2005L, bl_start = 2002L, bl_end = 2003L),
  data.table(election_cycle = 2007L, bl_start = 2002L, bl_end = 2005L),
  data.table(election_cycle = 2009L, bl_start = 2004L, bl_end = 2007L),
  data.table(election_cycle = 2011L, bl_start = 2006L, bl_end = 2009L),
  data.table(election_cycle = 2013L, bl_start = 2008L, bl_end = 2011L),
  data.table(election_cycle = 2015L, bl_start = 2010L, bl_end = 2013L),
  data.table(election_cycle = 2017L, bl_start = 2012L, bl_end = 2015L)
))
```

## 3. The three candidate definitions, formalized

For all options, the firm's input is `mean_emp_{f, c}` = mean `n_employees` of firm `f` over the pre-election baseline window for cycle `c` (zero-employment years included; firm-years with all-NA employment dropped, mirroring `30c` lines 127–135). **All 7 cycles** in `BASELINE_WINDOWS` are used (mayor + gov/pres), not mayor-only.

**Option A4 — Fixed employment thresholds, 4-bin BNDES native (PRIMARY Option-A spec).**

Maps directly to the BNDES porte categorization with employment proxies:

```
size_bin_A4 = 1 (Micro)    if  0 <= mean_emp <=  9
              2 (Pequena)  if 10 <= mean_emp <= 49
              3 (Média)    if 50 <= mean_emp <= 499
              4 (Grande)   if      mean_emp >= 500
```

This matches the BNDES table:

| BNDES category | Revenue threshold | Employment proxy |
|---|---|---|
| Microempresa | ≤ R$360K | ≤ 9 |
| Pequena | ≤ R$4.8M | 10–49 |
| Média | ≤ R$60M | 50–499 |
| Grande | > R$300M | 500+ |

Constant across cycles and sectors. The cleanest possible match for E1's alignment check (yields a 4×4 cross-tab against BNDES porte directly, no collapsing needed).

**Option A3 — Fixed employment thresholds, 3-bin collapse (FALLBACK).**

```
size_bin_A3 = 1 (MPME)   if  0 <= mean_emp <=  49     (Micro+Pequena collapsed)
              2 (Média)  if 50 <= mean_emp <=  499
              3 (Grande) if      mean_emp >= 500
```

Mathematically: `size_bin_A3 = pmin(size_bin_A4, 1)` collapsed to 3 levels. Used only if E2 shows that the Micro bin (A4 bin 1) is structurally thin in most muni-years — collapsing Micro into Pequena salvages coverage at the cost of granularity. Decision is data-driven, not a priori.

**Option B — Within-(cnae_section × year) equal-frequency terciles, input = per-cycle baseline mean.**

The input variable is each firm's `mean_emp_{f, c(t)}` — the firm's baseline mean employment for the cycle that year `t` belongs to (per §0.1). The tertile cut is taken **within each (cnae_section, year) cell**, not per cycle:

```r
panel_with_baseline_mean[
  , size_bin_B := assign_size_bins(mean_emp_cycle, n_bins = 3L),
  by = .(cnae_section, year)
]
```

Reuse the `assign_size_bins()` helper from `30c` (lines 91–105). Falls back to ranks when ≤3 unique values.

Implication: a firm with a constant baseline mean within a cycle can land in different B-bins in different years inside the same cycle, because the universe of firms in `(cnae_section, year)` shifts year-to-year (entry/exit, cnae reclassification). This is what the user's brief specified and is preserved here.

**Fall-back rule for missing baseline windows (applies to all options).** If `mean_emp_{f, c}` is NA because firm `f` has no observations in cycle `c`'s baseline window, fall back to the firm's mean over the *closest preceding cycle* in which it does have observations. If no preceding cycle exists, fall back forward (closest succeeding cycle) — this last case is rare (firm enters RAIS late) and we accept the contemporaneity. Document the count of fall-backs per cycle in the script log.

## 3.5. Exercise 0 — Bin-stability pre-exercise

**Why it exists.** The cycle-baseline rule is conservative: it forbids using year-`t` employment to define a firm's bin in year `t`, which is the right call only if firm size actually changes over the panel. If most firms stay in the same bin throughout 2002–2017, the cycle-baseline machinery is overhead with no payoff and a simpler "lifetime mean" rule would be defensible. E0 measures bin migration empirically before E1–E3 commit to the cycle-baseline construction.

**Script:** `explorations/anderson_rubin/diagnostics/00_size_bin_stability.R`

**Steps.**

1. Load `rais_bndes_reconstructed.fst` (firm_id, year, cnae_section, n_employees only).
2. Compute `mean_emp_{f, c}` for every (firm, cycle) using `BASELINE_WINDOWS` (all 7 cycles).
3. Apply the fall-back rule from §3 for any NA cells. Report fall-back rate.
4. Assign `size_bin_A4`, `size_bin_A3`, `size_bin_B` to every (firm, cycle) — for B, run the within-(cnae, year) tertile assignment using the firm's per-cycle baseline mean as input (same as in §3, but here we measure migration at the cycle level for a like-for-like comparison with A4 and A3).
5. **Migration metrics** per option:
   - `n_distinct_bins_per_firm` — count of distinct bins a firm occupies across cycles. Distribution: share of firms with 1 bin (stable), 2 bins, 3 bins, etc.
   - `share_firms_ever_changed` — share of multi-cycle firms with `n_distinct_bins > 1`.
   - **Transition matrix** between consecutive cycles: rows = bin in cycle `c`, cols = bin in cycle `c+1`. Diagonal = stayers; off-diagonal = movers.
   - **Direction of migration** under A4: count up-moves (Micro→Pequena, Pequena→Média, Média→Grande) and down-moves separately. Count "skip-bin" moves (e.g., Micro→Média, plausibly RAIS measurement noise rather than real growth).
6. **BNDES-rule-specific output** per the user's question: under Option A4, what share of firms migrate between Micro/Pequena/Média/Grande over the 16-year panel? Reported as:
   - Micro stayers / Micro→Pequena / Micro→Média / Micro→Grande
   - same rows for Pequena, Média, Grande starting bins.
7. **Cross-rule consistency:** for the same firm, do A4, A3, and B agree on which firms are "stable"? This catches cases where one rule shows stability that the others don't (e.g., a firm whose absolute employment is stable but whose B-rank moves because peers move).
8. **Decision implication.** Two thresholds:
   - If `share_firms_ever_changed` < 20% under A4 → recommend "lifetime mean" rule (one bin per firm) for the production margin and skip the cycle-baseline overhead.
   - If `share_firms_ever_changed` ≥ 20% under A4 → keep the cycle-baseline rule. Document the migration patterns and proceed to E1–E3.

**Outputs (in `explorations/anderson_rubin/diagnostics/output/`):**
- `bin_stability_A4_distribution.csv` — `n_distinct_bins` distribution under A4.
- `bin_stability_A4_transitions.csv` — transition matrix Micro/Pequena/Média/Grande.
- Same for A3 and B.
- `bin_stability_summary.csv` — one row per option with `share_firms_ever_changed`, `share_skip_bin_moves`, `fall_back_rate`, recommendation flag.
- `bin_stability_report.md` — interpretation, comparison across rules, recommendation on cycle-baseline vs. lifetime-mean.

**Failure modes:**
- Firms with only 1 observed cycle have `n_distinct_bins = 1` mechanically. Filter to ≥2 observed cycles before reporting `share_firms_ever_changed`.
- A4 Bin 1 (Micro, 0–9) under measurement noise: a firm at 9 employees in cycle `c` with one extra hire becomes 10 in cycle `c+1` and migrates Micro→Pequena even though the change is economically trivial. Flag the share of moves that cross thresholds by ≤2 employees (boundary noise).
- B's tertile assignment is sensitive to the firm universe in each (cnae, year). Bin migration under B can reflect compositional changes rather than firm-size changes.

## 4. Exercise 1 — Alignment of Option A4 with BNDES `size` (porte)

**Scope.** E1 cross-tabulates **Option A4 only** (4-bin BNDES native) against BNDES porte. Option B is excluded by design — B's bins are relative-to-sector-peers, not absolute thresholds, and would be a category error to compare against porte. Option A3 is a downstream collapse of A4, so it inherits A4's alignment by construction; no separate A3 alignment table is needed. The natural output is a **4×4 cross-tab** (porte vs. A4) — cleanest possible alignment test.

**Script:** `explorations/anderson_rubin/diagnostics/01_size_bin_alignment.R`

**Inputs:** `bndes_loan_level.qs2`, `rais_bndes_reconstructed.fst`.

**Steps.**

1. Load `bndes_loan_level.qs2`. Drop loans with missing `firm_id`, `value_dis_real_2018`, or `size`. Normalize porte:
   ```r
   bndes_porte_norm <- function(s) {
     s <- toupper(iconv(trimws(s), to = "ASCII//TRANSLIT"))
     fcase(
       grepl("MICRO", s),    "Micro",
       grepl("PEQUEN", s),   "Pequena",
       grepl("MEDIA|MEDIO|MEDIANO", s), "Media",
       grepl("GRANDE", s),   "Grande",
       default = NA_character_
     )
   }
   ```
2. Map each loan year `y` to a cycle using the **post-baseline outcome window rule, all 7 cycles**: cycle `c` such that `bl_end_c < y ≤ bl_end_{c+1}` over the full set {2005, 2007, 2009, 2011, 2013, 2015, 2017}. Concretely:
   - `y = 2004` → cycle 2005 (bl 2002–2003)
   - `y = 2005, 2006` → cycle 2007 (bl 2002–2005)
   - `y = 2007, 2008` → cycle 2009 (bl 2004–2007)
   - `y = 2009, 2010` → cycle 2011 (bl 2006–2009)
   - `y = 2011, 2012` → cycle 2013 (bl 2008–2011)
   - `y = 2013, 2014` → cycle 2015 (bl 2010–2013)
   - `y = 2015, 2016, 2017` → cycle 2017 (bl 2012–2015)
   - `y ∈ {2002, 2003}`: no preceding cycle in the set. Drop with logged count.
   - `y ≥ 2018`: drop (out of panel).
3. Aggregate to (firm × cycle): take the modal porte across loans within (firm, cycle), tie-broken by total `value_dis_real_2018`. Produces `firm_cycle_porte ∈ {Micro, Pequena, Media, Grande}`.
4. Compute baseline `mean_emp_{f,c}` from the RAIS panel using `BASELINE_WINDOWS` (re-use the loop pattern from `30c` lines 143–191), with the §3 fall-back rule applied.
5. Build `size_bin_A4 ∈ {1=Micro, 2=Pequena, 3=Média, 4=Grande}` per (firm, cycle).
6. Cross-tab on the borrower set:
   - **Table 1 (primary): 4×4** — rows = `firm_cycle_porte`, cols = `size_bin_A4`. Counts and row-percentages.
   - **Table 1w: 4×4 weighted** — same shape, cells weighted by sum of `value_dis_real_2018` over loans in that (firm, cycle).
   - **Table 1c (informational): 3×3 collapsed** — A4's Micro+Pequena → 1, plus the corresponding collapse on the porte axis. Lets us see what A3 alignment would look like as a side benefit.
7. Report three metrics:
   - **Unweighted diagonal mass (4×4):** share of (firm × cycle) on the diagonal of Table 1.
   - **Loan-value-weighted diagonal mass (4×4):** from Table 1w.
   - **Collapsed diagonal mass (3×3):** from Table 1c — for cross-comparison with the A3 fallback later.
   - **Confusion patterns:** flag the largest off-diagonal cells (e.g., are mismatches concentrated at Micro/Pequena boundary, or scattered?).

**Outputs (in `explorations/anderson_rubin/diagnostics/output/`):**
- `alignment_porte_A4_4x4_unweighted.csv`
- `alignment_porte_A4_4x4_value_weighted.csv`
- `alignment_porte_A4_3x3_collapsed.csv`
- `alignment_summary.csv` — one row per metric (unweighted-4x4, weighted-4x4, collapsed-3x3) with diagonal mass and mismatch rate.
- `alignment_report.md` — plain-language verdict on whether A4's fixed thresholds track BNDES's own porte categories, plus a note on the implied A3 alignment.

**Failure modes (flagged, not stopped):**
- High NA share in `bndes_porte`. Report `n_porte_known / n_total_loans` and proceed on the porte-known subsample only.
- Multi-firm borrowers: assignment by modal porte, value-weighted tie-break (as above).
- Cycle-window edge cases: documented in step 2.

## 5. Exercise 2 — Coverage check (A4, A3, B)

**Script:** `explorations/anderson_rubin/diagnostics/02_size_bin_coverage.R`

**Cell unit.** `(size_bin × cnae_section × muni_id × year)`. Year, not cycle — see §0.1. The IV operates at year level; A2 round 1 decomposes at year level; coverage must be evaluated at the same unit. The bin assignment is cycle-level (constant within each cycle for a given firm-cycle under A4 and A3; potentially year-varying within a cycle under B), but cell rows are annual.

**Steps.**

1. Load reconstructed panel via `fst::read_fst(..., columns = c("firm_id","muni_id","year","cnae_section","in_bndes","value_dis_real_2018_total","n_employees"), as.data.table = TRUE)`.
2. Compute `mean_emp_{f,c}` per cycle (helper to be factored from the existing `30c` loop, but local to this script — do not edit `30c`). Apply §3 fall-back rule.
3. Assign `election_cycle` to every panel year using the post-baseline outcome rule from §4 step 2 (all 7 cycles).
4. Assign `size_bin_A4` and `size_bin_A3` to every RAIS firm-cycle.
5. Assign `size_bin_B` per (firm, year) using each firm's per-cycle baseline mean as the input but cutting tertiles within (cnae_section, year).
6. Admissibility check per option: print `share(is.na(size_bin))` separately for active sections and XX sections — must be near zero for active.
7. Build `cell_dt` long, per option:
   ```r
   cell_dt <- panel_with_bin[
     !is.na(size_bin) & !is.na(cnae_section) & cnae_section != "",
     .(n_borrowers = sum(in_bndes == 1L, na.rm = TRUE),
       L_total    = sum(fifelse(in_bndes == 1L, value_dis_real_2018_total, 0), na.rm = TRUE),
       n_firms    = uniqueN(firm_id),
       emp_total  = sum(n_employees, na.rm = TRUE)),
     by = .(size_bin, cnae_section, muni_id, year)
   ]
   ```
8. Reporting (per option):
   - `n_cells_total` and `n_cells_with_borrower` (n_borrowers ≥ 1).
   - `share_munis_with_bin_borrower` per `size_bin`: among `(muni_id × year)` cells where the muni has any RAIS firms in that bin, what share have ≥1 BNDES borrower of any sector in that bin.
   - Distribution of `n_borrowers` across populated cells: p10, p50, p90.
   - **Thin-cell flag:** `share_thin = mean(n_borrowers < 5 | populated)`. Report by `size_bin` and overall.
   - **Structurally thin bin** rule: `share_munis_with_bin_borrower < 0.10` for a bin in the median year.

**Outputs:**
- `coverage_optionA4.csv`, `coverage_optionA3.csv`, `coverage_optionB.csv` — one row per (option, size_bin) with the four reporting numbers.
- `coverage_cells_optionA4.csv`, `coverage_cells_optionA3.csv`, `coverage_cells_optionB.csv` — full cell long table for downstream use in E3.
- `coverage_summary.csv` — one row per option with overall thin-cell share, max/min `share_munis_with_bin_borrower` across bins, and a verdict column (`PASS` / `THIN_BIN` / `FAIL`).
- `coverage_report.md` — explicit comparison A4 vs. A3 vs. B; flags whether to escalate from A4 to A3 (Micro-bin coverage failure) before E3.

**Decision logic between A4 and A3 at the end of E2.**
- If A4 passes coverage on **all four bins** (no structurally thin bin in median year, overall thin-cell share < 0.30) → A4 is the production candidate; A3 is dropped.
- If A4 fails only on the **Micro bin** (bin 1) → escalate to A3 (collapses Micro into Pequena). A3 inherits A4's alignment by construction (E1) and may pass coverage where A4 didn't.
- If A4 fails on **Grande** (bin 4) → no rescue; even A3 will have the same thin Grande bin. Flag the structural rarity of large firms in small munis as a known caveat; pass A3 forward only if its remaining bins look healthy.
- If A4 fails on Pequena or Média (bins 2 or 3) → unusual; flag and inspect manually.

**Failure modes:**
- Bin 4 (Grande, 500+) under A4 is plausibly rare in small munis. Flag, don't drop.
- Bin 1 (Micro, 0–9) under A4 is the most numerous bin by firm count but may be sparsely populated *for BNDES borrowers* in small munis (Cartão BNDES exists, but Micro firms borrow less than Média firms in absolute terms). This is the most plausible reason to fall back from A4 to A3.
- Option B has equal-frequency terciles by construction within (cnae × year), so no bin is universally thin nationally — but a small-muni Bin-3 cell is still possible.

## 6. Exercise 3 — F1 within-muni variance decomposition (E2 winner among A4/A3, plus B)

**Script:** `explorations/anderson_rubin/diagnostics/03_size_bin_f1.R`

**What this extends.** `within_muni_variation.R` already implements the variance decomposition for a generic margin variable. The plan is to **abstract its `process_margin()` and decomposition pipeline into a reusable function** at the top of `03_size_bin_f1.R` (call it `f1_decompose(panel, margin_var, all_bins, active_bins, output_bins, denom)`), then call it on the new size×sector margins. **Do not modify `within_muni_variation.R`** — that script is the canonical round-1 reference and its outputs are cited in D15.

**Options run.** Whichever of A4 or A3 survives E2 (default A4; A3 only if E2 escalates), plus Option B. So either {A4, B} or {A3, B} — usually two options total, four if both pass E2.

**Margin construction (per option).**

```r
panel_with_bin[, size_x_sec := paste(cnae_section, size_bin, sep = "_")]
# A4: 21 sections * 4 size bins = 84 bins (51 active under A4 if KOTU excluded)
# A3: 21 sections * 3 size bins = 63 bins (51 active under A3)
# B:  21 sections * 3 size bins = 63 bins
all_bins_sxs    <- sort(unique(panel_with_bin$size_x_sec))
active_bins_sxs <- all_bins_sxs[!grepl("^[KOTU]_", all_bins_sxs)]   # XX sections excluded
```

Active-bin counts: A4 → 17 sections × 4 sizes = **68 active bins**; A3 / B → 17 × 3 = **51 active bins**.

**Denominators — both V1 and V2, V1 primary.**

- **V1 (active-only, PRIMARY):** `s_v1 = L_b / sum_{b in active} L_{b}`. Denominator excludes KOTU. Active shares sum to 1 within (muni, year). Cleaner identification — KOTU credit fluctuations don't contaminate active-share variance.
- **V2 (full-economy, SECONDARY):** `s_v2 = L_b / sum_{b in all bins} L_{b}`. Denominator includes KOTU (mirrors round 1's M3 spec). More natural muni-credit-share interpretation; reported as a robustness check.

The round-1 verdict was identical under V1 and V2 on the verdict, but the variance components and σ levels differ. We report both. V1 wins the tiebreaker if their verdicts disagree at any bin.

**Decomposition.** Same formulas as `within_muni_variation.R` lines 268–328:
- `total_var` = `var(s)` over `(m, t)`
- `between_muni_var` = `var(mean_t s_{m, sxs, t})` over `m`
- `within_muni_var` = `var(s − mean_t s)` over `(m, t)`
- `share_within = within_muni_var / total_var`
- Cross-muni quantiles of σ_within.

**Comparison to round 1.** Add a `vs_round1.csv` table with one row per (margin name, bin) showing:
- size×sector bin (e.g., `C_3` = Manufacturing / Grande)
- size×sector med σ_within and share_within
- The corresponding `cnae_section` row from round 1 (e.g., `C` alone) — pulled from `variation_decomposition.csv`.
- Delta columns.

**SUPPORTED rule** (mirrors round 1, see `within_muni_variation.R` lines 84–86):
- `med σ_within > 0.05` AND `share_within > 0.20` for ≥1 bin → SUPPORTED.

**Outputs (per surviving option `X ∈ {A4, A3, B}` from E2, per denominator `D ∈ {V1, V2}`):**
- `f1_optionX_D_decomposition.csv`
- `f1_optionX_D_summary.csv` — verdict per option × denominator.
- `f1_optionX_D_vs_round1.csv`
- `f1_combined_report.md` — head-to-head table A4/A3 vs. B vs. round 1, V1 primary with V2 robustness, plus implications.

**Failure modes:**
- A `size_x_sec` bin that is empty in most munis will collapse `share_within` (zero denominator). The decomposition function already handles this (NA where `total_var <= 0`); flag bins with `n_munis_with_sigma < 100`.
- 68 bins (A4 active) × per-muni decomposition is heavier than round 1's 21–5–4. Verify memory by running on a single cycle slice first; if needed, partition the decomposition by `cnae_section` and `rbind`.
- V1 is undefined for bins not in the active set; V2 has shares for all bins. Skip V1 outputs for KOTU bins (they are NA by construction).

## 7. Exercise 3b — Conditional F1 for Agro under policy_block × V2

**Script:** `explorations/anderson_rubin/diagnostics/03b_agro_conditional_f1.R`

**Why this exists.** Round 1 (D15) reports `policy_block × Agro × V2` as SUPPORTED in aggregate, but the per-bin numbers show a peculiar pattern: `mean_share = 0.058`, `share_within = 0.60`, `med σ_within ≈ 0.000`, `p90 σ_within = 0.345`. The median σ is zero because most munis (urban, service-heavy) have zero Agro credit in most years; the variation is concentrated in agricultural munis where it is substantial. The right reading is "Agro moves where Agro is a thing," not "Agro doesn't move." This is the correct regime for an SSIV — bites where it should, mechanically zero where it shouldn't — but it is worth a positive check.

**Steps.**

1. Reuse the `policy_block` loader and crosswalk from `within_muni_variation.R`.
2. Compute, per muni, **baseline Agro share** = mean of `s_{m, Agro, t}` over `t in baseline_window` (use cycle 2009 baseline window 2004–2007 as the reference, since that is the muni-level baseline used by `33`). Output: `muni_baseline_agro_share`.
3. Define `agro_munis` = munis with `muni_baseline_agro_share > p50` of the baseline Agro share **conditional on > 0** (i.e., median among munis with any baseline Agro credit). Also produce a stricter cut at `> p25` of the strictly-positive distribution.
4. Re-run the F1 variance decomposition for `policy_block × Agro × V2` on three samples:
   - **All munis** (reproduces round 1 for sanity).
   - **Agro-having munis** (baseline Agro > 0).
   - **Above-median Agro munis** (the main conditional sample).
5. Verdict:
   - If conditional `med σ_within > 0.05` → Agro is fine; flat tail is "where's the action," not structural flatness.
   - If even on the conditional sample `med σ_within < 0.05` → Agro is structurally flat under V2; flag as a caveat (not a chain-breaker, given share_within is already strong).

**Outputs:**
- `agro_conditional_f1_decomposition.csv` — three rows (all / agro-having / above-median), with med σ_within, p10/p90 σ, share_within, n_munis.
- `agro_conditional_summary.csv` — one row with verdict.
- Append a section to `f1_combined_report.md` (no separate report file; keep it local to the F1 narrative).

**Failure modes:**
- Misalignment between A2 round 1 panel filters and this re-run. Cross-check `n_obs` against `variation_decomposition.csv` for the all-munis row.
- Cycle-2009 baseline window is one defensible choice; an alternative is the per-(muni, cycle) baseline. Document the choice in the script header.

## 8. Decision rules

After all five scripts run, decide on the production margin among {A4, A3, B} (with C as last-resort fallback).

**Per-exercise verdicts** (binary, computed in each `*_summary.csv`):

| Exercise | Option passes if |
|---|---|
| **E0 stability** | `share_firms_ever_changed ≥ 20%` under A4 → keep cycle-baseline rule (proceed). If `< 20%` → recommend simpler "lifetime mean" rule and re-run E1–E3 with that variant before finalizing. (Reported, not gating.) |
| **E1 alignment** (A4 only) | 4×4 diagonal mass ≥ 0.60 (loan-value-weighted). 3×3 collapsed diagonal mass ≥ 0.65 (looser threshold since collapsing absorbs near-boundary mismatches). |
| **E2 coverage** | No bin has `share_munis_with_bin_borrower < 0.10` in median year; overall thin-cell share < 0.30. A4 → A3 escalation if Micro fails. |
| **E3 F1 (V1 primary)** | At least one size×sector bin has `med σ_within > 0.05` AND `share_within > 0.20`. Mean `share_within` across bins comparable to round-1 cnae_section baseline (Δ ≥ −0.05 acceptable, since 51-bin shares are smaller than 21-bin shares). V2 reported for robustness; verdicts must agree at the SUPPORTED/REJECTED level. |

**Selection flow.**

```
1. E0 → reports stability. If lifetime-mean rule is recommended, surface to user before continuing.

2. E1 → does A4 align with porte?
     A4 passes  → A4 is the Option-A candidate.
     A4 fails   → A3 inherits A4's coverage but A's interpretability claim weakens.

3. E2 → which of {A4, A3, B} have viable coverage?
     A4 covers          → A4 advances to E3.
     A4 fails on Micro  → A3 advances instead of A4.
     A4 fails on Grande → A3 advances; flag Grande caveat.
     B always advances unless its bin 3 fails coverage in median year.

4. E3 → among the surviving candidates, which has the strongest F1?
     Pick the candidate with highest mean share_within across bins (V1 primary).
     Tiebreaker (Δ < 0.05): prefer A4 > A3 > B (interpretability ranking).
     Override: if A failed E1 alignment, drop A's tiebreaker bonus → ties go to B.

5. Escalate to user if:
     - All three of {A4, A3, B} fail E2 or E3.
     - A4 and A3 both fail but B passes (decision is automatic — Option B wins — but flag for awareness since it loses the BNDES interpretability link).
     - V1 and V2 verdicts disagree at the SUPPORTED/REJECTED level for the leading candidate.
```

**Production margin commitment.** Once a winner is selected:
- Update `docs/PROJECT_BLUEPRINT.md` §3 F1 row with the chosen rule and a D-entry in §6.
- The chosen rule's bin definition becomes the spec for a successor to `30c` (e.g., `30f_build_size_sector_mapping.R`) that produces the production crosswalk consumed by `31`, `34`, `41`.
- Round 1's cnae_section-only margin remains in the panel for robustness comparisons; it is not displaced.

**Agro decision (3b is independent of A/B choice):**
- If the conditional (above-median) sample shows `med σ_within > 0.05` → no change to D15; document in `f1_combined_report.md` that the round-1 verdict on Agro × V2 holds under conditioning.
- Else → add Agro caveat to `docs/PROJECT_BLUEPRINT.md` §3 F1 row (struck-through update, not a re-verdict).

## 9. File layout

```
explorations/anderson_rubin/diagnostics/
├── 00_size_bin_stability.R       (E0: bin migration under A4, A3, B; all 7 cycles)
├── 01_size_bin_alignment.R       (E1: A4 vs. BNDES porte; 4x4 cross-tab)
├── 02_size_bin_coverage.R        (E2: A4, A3, B; cell unit = year)
├── 03_size_bin_f1.R              (E3: surviving option(s) + B; V1 primary, V2 robustness)
├── 03b_agro_conditional_f1.R     (E3b: policy_block x Agro x V2 conditional sample)
└── output/
    ├── bin_stability_A4_distribution.csv
    ├── bin_stability_A4_transitions.csv
    ├── bin_stability_A3_distribution.csv
    ├── bin_stability_A3_transitions.csv
    ├── bin_stability_B_distribution.csv
    ├── bin_stability_B_transitions.csv
    ├── bin_stability_summary.csv
    ├── bin_stability_report.md
    ├── alignment_porte_A4_4x4_unweighted.csv
    ├── alignment_porte_A4_4x4_value_weighted.csv
    ├── alignment_porte_A4_3x3_collapsed.csv
    ├── alignment_summary.csv
    ├── alignment_report.md
    ├── coverage_optionA4.csv
    ├── coverage_optionA3.csv
    ├── coverage_optionB.csv
    ├── coverage_cells_optionA4.csv
    ├── coverage_cells_optionA3.csv
    ├── coverage_cells_optionB.csv
    ├── coverage_summary.csv
    ├── coverage_report.md
    ├── f1_optionA4_V1_decomposition.csv         (only if A4 advances)
    ├── f1_optionA4_V1_summary.csv
    ├── f1_optionA4_V1_vs_round1.csv
    ├── f1_optionA4_V2_decomposition.csv
    ├── f1_optionA4_V2_summary.csv
    ├── f1_optionA4_V2_vs_round1.csv
    ├── f1_optionA3_V1_decomposition.csv         (only if A3 advances)
    ├── f1_optionA3_V1_summary.csv
    ├── f1_optionA3_V1_vs_round1.csv
    ├── f1_optionA3_V2_decomposition.csv
    ├── f1_optionA3_V2_summary.csv
    ├── f1_optionA3_V2_vs_round1.csv
    ├── f1_optionB_V1_decomposition.csv
    ├── f1_optionB_V1_summary.csv
    ├── f1_optionB_V1_vs_round1.csv
    ├── f1_optionB_V2_decomposition.csv
    ├── f1_optionB_V2_summary.csv
    ├── f1_optionB_V2_vs_round1.csv
    ├── f1_combined_report.md
    ├── agro_conditional_f1_decomposition.csv
    └── agro_conditional_summary.csv
```

## 10. Code conventions (per `.claude/rules/content-invariants.md` + project state)

Each script:
- `library(data.table); library(qs2); library(here); library(fst)` (and `library(ggplot2)` only if a figure is added — none planned for now) at the top.
- `setDTthreads(0L)`.
- No `setwd()`, no `rm(list = ls())`, no `install.packages()`.
- Paths via `here::here()` only.
- One `set.seed()` at the top if any randomness — none planned.
- Header docstring naming inputs, outputs, the F-link being tested (F0 admissibility for E1; F1 for E3).
- Pre-allocated container for cycle loops (mirroring `30c` lines 141–191).

## 11. Open questions — RESOLVED

User answers (2026-05-04, rev 2):

1. **Q1 — Option B temporal unit.** RESOLVED → within **(cnae_section, year)** using each firm's per-cycle baseline mean as input. Implementation per §3.
2. **Q2 — Cycle assignment for loans in E1.** RESOLVED with clarification + scope expansion → use the cycle whose **post-baseline outcome window contains `y`** over **all 7 cycles** (mayor + gov/pres), not mayor-only as I had originally specified. Concrete year-cycle mapping in §4 step 2.
3. **Q3 — Borrower porte aggregation in E1.** RESOLVED → modal porte within (firm × cycle), value-weighted tie-break.
4. **Q4 — Empty-cycle loans.** RESOLVED → drop with logged count (loans in 2002–2003 and 2018+).
5. **Q5 — Agro-conditional cutoff.** RESOLVED → above median of munis with strictly-positive baseline Agro share.
6. **Q6 (new) — V1 vs. V2 in E3.** RESOLVED → run both, V1 primary, V2 robustness.
7. **Q7 (new) — Option A granularity.** RESOLVED → 4-bin (A4) primary, 3-bin (A3) collapsed fallback. E0/E2 will tell us whether to use A4 directly or fall back to A3.

No further open questions. Ready to implement on user approval.

## 12. Verification checklist (per `.claude/rules/workflow.md` §2 Simplified Mode)

For each of the five scripts:
- [ ] Runs without errors on existing data
- [ ] All packages loaded at top
- [ ] No absolute paths — `here::here()` only
- [ ] No `setwd()`, no `rm(list = ls())`, no `install.packages()`
- [ ] Output files created at the expected paths
- [ ] Header documents inputs / outputs / F-link
- [ ] Quality score ≥ 80

After all four:
- [ ] `f1_combined_report.md` includes the comparison vs. round-1.
- [ ] `docs/PROJECT_BLUEPRINT.md` §4 (A3 row) updated with status `PARTIAL → CONFIRMED` once a winner emerges, plus a D-entry in §6.
- [ ] `logs/research_journal.md` appended per `.claude/rules/logging.md`.

## 13. Implementation order

1. Approve plan (Q1–Q7 all resolved).
2. Implement **E0** (`00_size_bin_stability.R`) → run → review migration distributions and BNDES-rule transition matrix. Decide whether to keep cycle-baseline rule or switch to lifetime-mean rule. Pause for user check before continuing if `share_firms_ever_changed < 20%` under A4.
3. Implement **E1** (`01_size_bin_alignment.R`) → run → check 4×4 diagonal mass.
4. Implement **E2** (`02_size_bin_coverage.R`) → run → determine surviving options among {A4, A3, B}.
5. Implement **E3** (`03_size_bin_f1.R`) for surviving options × {V1, V2} → run → check F1 verdicts.
6. **In parallel with E3** (independent): implement **E3b** (`03b_agro_conditional_f1.R`).
7. Synthesize decision into `f1_combined_report.md`; update Blueprint §3 (F1), §4 (A3 row), §6 (new D-entry recording the production margin choice), §7 (Next action moves to F2 / F3).
8. Once the production margin is fixed, draft a successor to `30c` (e.g., `30f_build_size_sector_mapping.R`) that produces the chosen crosswalk for downstream consumption by `31`, `34`, `41`. This is a separate, follow-on plan — not part of this diagnostic.
