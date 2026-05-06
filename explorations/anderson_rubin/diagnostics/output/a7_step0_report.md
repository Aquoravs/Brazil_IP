# A7 Step 0 — Coverage and Imputation Diagnostic
Generated: 2026-05-05 17:23:03
Plan: logs/plans/2026-05-05_a7-step0-coverage-diagnostic.md

---

## Overview

This diagnostic characterises three forms of silent imputation in the
production shift-share instrument at the `policy_block` aggregation margin.
The findings feed the A7 weight comparison: the correlation matrix and
first-stage F-stats in Steps 1-5 are uninterpretable without knowing how
much of the variation is driven by coverage patterns rather than real
political alignment variation.

Aggregation margin: **policy_block only** (Agro, Ind, Infra, Serv; XX excluded).
Year range: 2002-2017.

---

## D-A: Affiliation-Match Coverage by Policy Block

Match rates are computed per (muni, policy_block, year) cell and then
pooled. Two rates are reported: `match_rate_n` (firm count) and
`match_rate_emp` (employment-weighted).

### Pooled means by policy_block

| Block | Match rate n (mean) | Match rate n (median) | Match rate emp (mean) | Match rate emp (median) | N cells |
|-------|--------------------|-----------------------|---------------------|------------------------|---------|
| Agro | 19.4% | 11.1% | 24.8% | 10.3% | 79,078 |
| Ind | 95.8% | 100.0% | 95.5% | 100.0% | 75,934 |
| Infra | 92.9% | 98.4% | 93.4% | 100.0% | 86,592 |
| Serv | 79.1% | 86.7% | 67.7% | 82.9% | 88,377 |

**ESCALATION FLAG: The following blocks have mean match_rate_emp < 50%: Agro. This is a hard escalation trigger per the A7 plan.**

### Interpretation

Match rates differ across blocks because the owner affiliation file covers firms proportional to their size and visibility in the registry. Blocks with lower coverage (typically Serv) contribute disproportionately to the `zero_aff` category in D-B. If match_rate_emp systematically differs across blocks, any across-block IV comparison in Steps 1-5 carries sector-correlated bias — the weighting choice partially proxies for coverage, not only for economic exposure.

---

## D-B: Z = 0 Decomposition

Total `Z_mayor_coalition = 0` cells (cycle_specific baseline): 7,596

Priority decomposition: (i) zero_rais > (ii) zero_aff > (iii) zero_shock.
Mutually exclusive — every Z = 0 cell gets exactly one reason.

| Reason | Count | Share |
|--------|-------|-------|
| zero_rais  | 21 | 0.3% |
| zero_aff   | 29 | 0.4% |
| zero_shock | 7,546 | 99.3% |

### Interpretation

`zero_aff` accounts for only 0.4% of Z = 0 cells (< 5% threshold). The matched-only denominator is doing minimal imputation; this concern is a sensitivity-analysis footnote rather than a central identification issue. Steps 1-5 weight comparison can proceed without resolving this bias source first.

The dominant reason for Z = 0 is `zero_shock` (99.3%), covering munis with matched affiliated firms and positive owner counts, but where no party winning the mayoralty has any affiliation with the muni's incumbent owners in that year. These cells are genuine alignment zeros and are correctly coded as Z = 0.

`zero_rais` (0.3%) flags munis with no firms in active policy blocks in the baseline window. These munis are structurally untreated and would be dropped from estimation regardless of weighting choice; they do not affect the weight comparison.

---

## D-C: Zero-Employment Firm-Years by Policy Block

| Block | Total firm-years | N zero-emp | Share zero-emp | N zero-emp with aff | Share with aff | N with owners >= 1 | Share with owners >= 1 |
|-------|-----------------|------------|----------------|--------------------|----------------|--------------------|-----------------------|
| Agro | 2,058,418 | 31,318 | 1.5% | 30,612 | 97.7% | 30,612 | 100.0% |
| Ind | 4,696,874 | 349,378 | 7.4% | 342,795 | 98.1% | 342,795 | 100.0% |
| Infra | 6,665,385 | 425,104 | 6.4% | 401,176 | 94.4% | 401,176 | 100.0% |
| Serv | 30,002,010 | 2,642,554 | 8.8% | 2,613,654 | 98.9% | 2,613,654 | 100.0% |

### Interpretation

Zero-employment firm-years are invisible to the `w_mjp_emp` weight because that weight uses `n_employees > 0` in the denominator. If zero-emp firms that have affiliation records (i.e., they are visible to the IV) are concentrated in specific blocks, the employment weight is systematically blind to a substantively important subpopulation. The `emp_share_floor` weight proposed in Step 1 addresses this by substituting `pmax(n_employees, owner_count, 1)` in the denominator.

A high `share_zero_emp_with_aff` combined with a high `share_zero_emp` in a block (especially Serv, which includes individual entrepreneurs and Cartao BNDES borrowers) justifies the floor weight for that block. The `share_zero_emp_with_owners_ge_1` column shows what fraction of zero-emp affiliated firms would survive the proposed floor (i.e., would have owner_count >= 1 and hence receive a non-zero floor weight).

---

## Files Produced

| File | Description |
|------|-------------|
| `a7_coverage_by_policy_block.csv` | D-A: 329,981 rows, per (muni, block, year, size_class) |
| `a7_z_zero_decomposition.csv` | D-B per-cell: 7,596 rows |
| `a7_z_zero_summary.csv` | D-B aggregated: 35 rows |
| `a7_zero_emp_by_policy_block.csv` | D-C: 4 rows |
| `a7_step0_report.md` | This narrative report |

---

## Implications for A7 Weight Comparison (Steps 1-5)

1. **D-A (coverage bias):** If match_rate_emp varies substantially across
   blocks, the weight comparison in Steps 1-5 should be interpreted as
   comparing weights that implicitly combine economic exposure with coverage
   selection. A block with low match_rate_emp will have its employment weight
   mechanically attenuated relative to its owner-count weight.

2. **D-B (Z = 0 composition):** The share of zero_aff cells determines how
   much of the instrument's zero-variation is structural (data gap) versus
   informative (genuine non-alignment). Steps 1-5 first-stage F-stats cannot
   distinguish between these; the `zero_aff` share is the fraction of the
   zero-mass that is non-informative structural imputation.

3. **D-C (zero-emp floor):** If zero-emp firms with affiliation represent
   a large share of the covered population in any block, the employment
   weight systematically underweights that block's alignment signal. The
   floor weight is most justified in blocks where `share_zero_emp_with_aff`
   is high relative to `share_zero_emp`.

---

## ESCALATION NOTICE

**Hard escalation triggered.** The following policy blocks have mean match_rate_emp < 50%: **Agro**. Per the A7 plan, this requires human review before the Step 1-5 weight comparison proceeds. The employment weight in these blocks covers less than half of the underlying employment mass, making cross-weight comparisons unreliable for those blocks.

