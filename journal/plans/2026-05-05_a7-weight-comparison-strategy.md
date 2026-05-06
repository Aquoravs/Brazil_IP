---
title: A7 Weight Comparison — Implementation Strategy
date: 2026-05-05
status: APPROVED
related:
  - docs/PROJECT_BLUEPRINT.md §4 A7
  - logs/plans/2026-04-29_weight-horserace.md
  - logs/plans/2026-05-04_size-bin-diagnostics.md (Track 1 upstream dependency)
---

# A7 Weight Comparison — Implementation Strategy

**Goal:** Select the baseline weight variant and denominator for the production SSIV without running a full grid search.

## Step 1: Instrument correlation check

After Track 1 (crosswalk) and script 31 (exposure weights) produce instrument vectors under both variants, compute the pairwise Pearson correlation between the two muni-level instrument vectors (pooled across years). Decision rule:

- **Correlation > 0.90** → weights are near-collinear; pick any of them (economically interpretable, easier to defend) and move on.
- **Correlation ≤ 0.90** → weights differ materially; proceed to Step 3.

## Step 3: One-cycle proxy (only if Step 2 triggers it)

Restrict to a single electoral cycle (e.g., 2002–2006) and run the sector first-stage spec for each weight variant. Compare Cragg–Donald or Kleibergen–Paap F-stats. The relative ordering across weights is typically stable across cycles, so this proxy generalizes.

## Denominator (V1 vs V2): same protocol

After selecting the baseline weight, apply the same two steps to the denominator dimension — correlation between V1 and V2 instrument vectors, then one-cycle proxy if correlation is low. Given that F1 showed the verdict was identical across V1 and V2, expect high correlation here; document and move to robustness.

## Output

A short table: weight pair × denominator → correlation coefficient, and (if triggered) F-stat from one-cycle proxy. The selected combination becomes the production default; the runner-up is reported as a robustness specification in the AR test.

## Upstream dependency

This plan cannot start until Track 1 (`30f_build_policy_block_size_mapping.R`) is complete and scripts 31 and 34 have been updated to consume the new crosswalk at the `policy_block_active × S3` margin.
