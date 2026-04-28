---
status: active
date: 2026-04-21
source: master_supporting_docs/meetings/2026-04-17_meeting.md
tracker: quality_reports/referee_response_tracker.md
scope: C1 (emp weights + split samples) + C2 (employment outcomes) + C3 (size bins within BNDES sectors)
---

# Plan: Complete Remaining First-Stage Regressions

## Context

Meeting of 2026-04-17 asked to complete the first-stage regression battery. Two gaps exist:

1. **Full-sample NA cells:** The emp-share-weighted (`emp_share_weighted`) rows in `agg_first_stage_2026_04_17.tex` show NA for some sector classifications — these are regressions that never ran (not numerical artifacts).
2. **Split-sample full grids:** The existing split-sample presentations (`split_sample_first_stage.tex`, `split_sample_agg_first_stage.tex`) only cover a subset of the spec grid (BNDES sector, unweighted, one alignment). The advisor wants **complete F-stat grids** matching the full-sample format, to test whether the first-stage effect is concentrated in big cities.

The tracker (`quality_reports/referee_response_tracker.md`) classifies all 8 meeting comments. This plan operationalizes **C1** (highest priority, run immediately) and **C2** (employment outcomes, can bundle with C1). Comments C3-C8 are deferred to later sessions.

## Design Decision: Q4/3Q Split

**Keep the current top-Q4 vs bottom-3Q split.** It's adequate because:
- Maximizes contrast between big and small cities (results already show G=23.5 vs 0.4)
- Standard in shift-share literature
- `interaction_mqemp` provides the continuous complement within the same regression

## Aggregation Note

The full-sample grid's "Unwtd" row uses `equal_firm` aggregation (confirmed in appendix filenames). The existing split-sample tables used `owner_count`. This plan uses `equal_firm` for split grids to match the full-sample format.

---

## Unit A: Fill NA Cells in Full-Sample Grids

**Goal:** Complete the emp-share-weighted rows that show NA in `agg_first_stage_2026_04_17.tex`.

**What's missing:**
- BNDES Sector: emp-shr-wtd + No ctrl → all NA (both FEs, both alignments, both outcomes)
- Custom Sector: ALL emp-shr-wtd → all NA (both ctrl, both FEs, both alignments, both outcomes)

**Commands (2):**

```bash
# A1: BNDES Sector — emp-shr-wtd, no exposure control only [RUN]
Rscript scripts/R/run_politicsregs.R 52 --specs=emp_share_weighted --sector-var=bndes_sector --exposure-control=no --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt

# A2: Custom Sector — emp-shr-wtd, both ctrl settings
Rscript scripts/R/run_politicsregs.R 52 --specs=emp_share_weighted --sector-var=custom_sector --exposure-control=yes,no --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt
```

**Regression count:**
- A1: 1 × 2 outcomes × 2 align × 2 FE × 1 ctrl = 8 configs × 6 combos = 48 regressions
- A2: 1 × 2 × 2 × 2 × 2 = 16 configs × 6 = 96 regressions
- **Unit A total: ~144 regressions**

---

## Unit B: Complete Split-Sample F-Stat Grids (Aggregated, Script 52)

**Goal:** Produce full F-stat grids for top_q4 and bottom_3q, matching the format of `agg_first_stage_2026_04_17.tex` — i.e., FE (2) × Weighting (3) × Ctrl (2) = 12 rows per grid.

**Commands (4):**

```bash
# B1: BNDES Sector — top Q4
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --sector-var=bndes_sector --muni-sample=top_q4 --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no

# B2: BNDES Sector — bottom 3Q
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --sector-var=bndes_sector --muni-sample=bottom_3q --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no

# B3: Custom Sector — top Q4
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --sector-var=custom_sector --muni-sample=top_q4 --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no

# B4: Custom Sector — bottom 3Q
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --sector-var=custom_sector --muni-sample=bottom_3q --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no
```

**Regression count per command:** 3 bundles × 2 outcomes × 2 align × 2 FE × 2 ctrl = 48 configs × 6 combos = 288 regressions
**Unit B total: 4 × 288 = ~1,152 regressions**

**Note:** Some BNDES-sector + unweighted + owner_count split runs already exist from the prior session, but those used `owner_count` aggregation. The new runs use `equal_firm` to match the full-sample grid. Both will coexist in the manifest without conflict (different slugs).

---

## Unit C: Firm-Level Split Samples (Script 51)

**Goal:** Complete the firm-level split-sample battery. The existing `split_sample_first_stage.tex` only covers: coalition, unweighted, main family, bndes_extensive + employment_share, both baselines. We need the full grid: both alignments, both weightings, interaction family.

**Commands (3):**

```bash
# C1: Firm-level — emp-share-weighted + both samples
Rscript scripts/R/run_politicsregs.R 51 --weighting=emp_share_weighted --sample=top_q4,bottom_3q --outcome=bndes_extensive,employment_share --alignment=coalition,party

# C3: Firm-level — party alignment + unweighted (existing only had coalition)
Rscript scripts/R/run_politicsregs.R 51 --weighting=unweighted --sample=top_q4,bottom_3q --outcome=bndes_extensive,employment_share --alignment=party

# C4: Firm-level — interaction_mqemp family + both samples
Rscript scripts/R/run_politicsregs.R 51 --weighting=unweighted,emp_share_weighted --family=interaction_mqemp --sample=top_q4,bottom_3q --outcome=bndes_extensive --alignment=coalition,party
```

**Unit C total: ~400 regressions** (script 51 defaults include both exposures and both main+interaction families)

---

## Unit D: Employment Outcomes (C2 from tracker)

**Goal:** Run aggregated regressions with employment on the LHS, full sample + split samples.

**Commands (3):**

```bash
# D1: Employment outcomes — full sample, all sector vars
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --outcome=log_employment,employment_share --sector-var=bndes_sector,custom_sector --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no

# D2: Employment outcomes — top Q4
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --outcome=log_employment,employment_share --sector-var=bndes_sector,custom_sector --muni-sample=top_q4 --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no

# D3: Employment outcomes — bottom 3Q
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --outcome=log_employment,employment_share --sector-var=bndes_sector,custom_sector --muni-sample=bottom_3q --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no
```

**Unit D total: 3 × (3 bundles × 2 outcomes × 2 sectors × 2 align × 2 FE × 2 ctrl × 6 combos) = 3 × 576 = ~1,728 regressions**

---

## Unit E: Interaction Family as Complement

**Goal:** Run `interaction_mqemp` for aggregated regressions (tests differential instrument strength by city size within one regression).

**Commands (1):**

```bash
# E1: Interaction family — all sector vars, BNDES outcomes
Rscript scripts/R/run_politicsregs.R 52 --specs=interaction_muni_emp --sector-var=bndes_sector,custom_sector --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no
```

**Unit E total: ~192 regressions**

---

## Unit F: Size Bins Within BNDES Sectors (C3 from tracker)

**Goal:** Run the first-stage battery for the new sector classification that embeds size bins inside BNDES sectors — both firm-level (script 51) and aggregated (script 52).

**What's different from the main grid:**
- New `--sector-var` / classification uses size bins nested within BNDES sectors (not standalone `size_bin`)
- Aggregated run uses `n_firms_weighted` in addition to the usual weighting options
- Baseline options: `cycle_specific` and `2002_fixed` for firm-level; `cycle_specific` only for aggregated
- Exposure fixed to `pooled_count` throughout

**Commands (2):**

```bash
# F1: Firm-level — size bins within BNDES sectors
Rscript scripts/R/run_politicsregs.R 51 -- \
  --weighting=unweighted,emp_share_weighted \
  --outcome=bndes_extensive,employment_log,employment_share \
  --sector-var=sector_group_size_bin \
  --alignment=coalition,party \
  --baseline=cycle_specific,2002_fixed \
  --exposure=pooled_count \
  --sample=all_firms \
  --family=main

# F2: Aggregated — size bins within BNDES sectors
Rscript scripts/R/run_politicsregs.R 52 -- \
  --regression-weight=unweighted,n_firms_weighted,emp_share_weighted \
  --outcome=bndes_extensive,bndes_share \
  --sector-var=sector_group_size_bin \
  --alignment=coalition,party \
  --fe=mxj_jxt,mxj_mxt \
  --exposure-control=yes \
  --baseline=cycle_specific \
  --exposure=pooled_count \
  --muni-sample=all
```

**Regression count:**
- F1: 2 weights × 3 outcomes × 2 align × 2 baselines = 24 configs (× combos within script)
- F2: 3 weights × 2 outcomes × 2 align × 2 FE = 24 configs (× combos within script)
- **Unit F total: ~300–500 regressions** (exact count depends on script defaults)


---

## Unit G: Compile Summaries and Presentations

**Goal:** After all regressions complete, regenerate the F-stat summary grids and compile updated Beamer presentations.

**Commands (4):**

```bash
# G1: Regenerate aggregated summary (reads manifests, produces F-stat grids)
Rscript scripts/R/run_politicsregs.R 52b

# G2: Regenerate firm-level summary
Rscript scripts/R/run_politicsregs.R 51b

# G3: Compile updated agg presentation
cd paper/meetings && xelatex agg_first_stage.tex && cd ../..

# G4: Compile updated firm presentation
cd paper/meetings && xelatex first_stage.tex && cd ../..
```

---

## Pre-Flight: Dry-Run Verification

Before launching any real run, verify the command resolves to the expected configs:

```bash
# Append --dry-run to any command to print the config table without running regressions
Rscript scripts/R/run_politicsregs.R 52 --specs=emp_share_weighted --sector-var=bndes_sector --exposure-control=no --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --dry-run
```

This prints the full grid of configs and slugs, letting you confirm the exact regressions before committing compute time.

---

## Execution Summary

| Unit | What | Commands | Est. Regressions | Priority |
|------|------|----------|-----------------|----------|
| A | Fill full-sample NA cells | 2 | ~144 | Run first |
| B | Split-sample full grids (agg) | 4 | ~1,152 | Run second |
| C | Firm-level split samples | 3 | ~400 | Run third |
| D | Employment outcomes (C2) | 3 | ~1,728 | Run fourth |
| E | Interaction family | 1 | ~192 | Run with B or D |
| F | Size bins within BNDES sectors (C3) | 2 | ~300–500 | Run after data ready |
| G | Compile summaries | 4 | 0 | Run last |
| **Total** | | **19 commands** | **~3,916–4,116** | |

**Estimated total runtime:** 2-10 hours depending on hardware (each regression ~3-10s).

**Suggested batching for overnight runs:**
- Night 1: Units A + B + E (7 commands, ~1,488 regressions, ~1-4 hours)
- Night 2: Units C + D (6 commands, ~2,128 regressions, ~2-6 hours)
- Night 3: Unit F (2 commands, ~300–500 regressions, ~0.5-1.5 hours) — only after size-bin variable is confirmed in data
- After all: Unit G (compilation, <5 minutes)

---

## Compact Batch Scripts

Copy-paste these blocks to run each night's batch unattended. Each command runs sequentially; if one fails, the next still starts (using `;` separator).

**Night 1 batch (Units A + B + E):**

```bash
# Unit A: Fill full-sample NAs
Rscript scripts/R/run_politicsregs.R 52 --specs=emp_share_weighted --sector-var=bndes_sector --exposure-control=no --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt ; \
Rscript scripts/R/run_politicsregs.R 52 --specs=emp_share_weighted --sector-var=custom_sector --exposure-control=yes,no --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt ; \
# Unit B: Split-sample full grids
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --sector-var=bndes_sector --muni-sample=top_q4 --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no ; \
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --sector-var=bndes_sector --muni-sample=bottom_3q --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no ; \
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --sector-var=custom_sector --muni-sample=top_q4 --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no ; \
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --sector-var=custom_sector --muni-sample=bottom_3q --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no ; \
# Unit E: Interaction family
Rscript scripts/R/run_politicsregs.R 52 --specs=interaction_muni_emp --sector-var=bndes_sector,custom_sector --outcome=bndes_extensive,bndes_share --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no ; \
echo "Night 1 batch complete"
```

**Night 2 batch (Units C + D):**

```bash
# Unit C: Firm-level split samples
Rscript scripts/R/run_politicsregs.R 51 --weighting=emp_share_weighted --sample=top_q4,bottom_3q --outcome=bndes_extensive,employment_share --alignment=coalition,party ; \
Rscript scripts/R/run_politicsregs.R 51 --weighting=unweighted --sample=top_q4,bottom_3q --outcome=bndes_extensive,employment_share --alignment=party ; \
Rscript scripts/R/run_politicsregs.R 51 --weighting=unweighted,emp_share_weighted --family=interaction_mqemp --sample=top_q4,bottom_3q --outcome=bndes_extensive --alignment=coalition,party ; \
# Unit D: Employment outcomes (aggregated)
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --outcome=log_employment,employment_share --sector-var=bndes_sector,custom_sector --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no ; \
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --outcome=log_employment,employment_share --sector-var=bndes_sector,custom_sector --muni-sample=top_q4 --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no ; \
Rscript scripts/R/run_politicsregs.R 52 --specs=equal_firm,emp_share_weighted,n_firms_weighted --outcome=log_employment,employment_share --sector-var=bndes_sector,custom_sector --muni-sample=bottom_3q --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes,no ; \
echo "Night 2 batch complete"
```

**Night 3 batch (Unit F — size bins within BNDES sectors):**

Run only after confirming the size-bin-within-BNDES-sector variable exists in the data (check script 30e output).

```bash
# Unit F: Size bins within BNDES sectors
Rscript scripts/R/run_politicsregs.R 51 -- --weighting=unweighted,emp_share_weighted --outcome=bndes_extensive,employment_log,employment_share --sector-var=sector_group_size_bin --alignment=coalition,party --baseline=cycle_specific,2002_fixed --exposure=pooled_count --sample=all_firms --family=main ; \
Rscript scripts/R/run_politicsregs.R 52 -- --regression-weight=unweighted,n_firms_weighted,emp_share_weighted --outcome=bndes_extensive,bndes_share --sector-var=sector_group_size_bin --alignment=coalition,party --fe=mxj_jxt,mxj_mxt --exposure-control=yes --baseline=cycle_specific --exposure=pooled_count --muni-sample=all ; \
echo "Night 3 batch complete"
```

**After all nights (Unit G):**

```bash
Rscript scripts/R/run_politicsregs.R 52b ; \
Rscript scripts/R/run_politicsregs.R 51b
```

---

## Remaining Comments (C3-C8)

These are classified in `quality_reports/referee_response_tracker.md`:
- **C3** (size bins within BNDES sectors): Regression specs are included in **Unit F** above. The data prerequisite (script 30e or equivalent producing the size-bin-within-BNDES variable) must be completed before launching G1/G2.
- **C4** (Anderson-Rubin): New exploration. Separate plan needed.
- **C5** (GDP deflation): RESOLVED — uses national IPCA, no spatial deflation.
- **C6-C7** (Data exploration): Web research tasks, no code.
- **C8** (Penalized regression): Depends on C4 results.

---

## Verification

After each unit completes:
1. Check that new `.tex` table files appear in `paper/tables/agg_firm_{sector_var}/`
2. Check the manifest CSV for new rows: `paper/tables/agg_firm_{sector_var}/agg_firm_run_manifest.csv`
3. Verify no NA cells remain in the F-stat summary grids (Unit F output)
4. Compile the Beamer presentations without errors
