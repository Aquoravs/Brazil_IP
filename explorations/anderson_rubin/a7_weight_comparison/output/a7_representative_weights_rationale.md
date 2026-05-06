# A7 Step 3 -- Representative Weight Selection (Rationale)

Plan: `logs/plans/2026-05-05_a7-revised-weight-comparison.md`, Step 3.
Mayor-tier clustering from `a7_correlation_clusters.csv`.
Step 0 inputs from `explorations/anderson_rubin/diagnostics/output/a7_step0_report.md`.

## Selection rules (priority order)

1. **Step 0 bias flag override** -- exclude any weight Step 0 flags as biased.
2. **Interpretability ranking** (highest first):
   `owners > firm_empshare_floor > emp > firm > binary > binary_empshare_floor`.
3. **Construction simplicity** -- prefer one-sentence formulas.

## Step 0 override applied?

No weight is excluded by Step 0. The diagnostic surfaced one bias
(Agro coverage degraded -- mean `match_rate_emp` 24.8%; D22 in the blueprint),
but it is sector-level not weight-level: all 6 Tier C weights inherit the
Agro coverage gap symmetrically (matched-only numerator, full-universe
denominator). The Agro attenuation is documented as a Step 5 caveat per D22.

## Cluster-by-cluster choices (mayor tier)

### Cluster 1

**Members:** `w_owners_muni_univ`
**Representative:** `w_owners_muni_univ`

Singleton cluster. Owner-count numerator with full-universe muni denominator.
Top of the interpretability ranking; carries the cleanest economic narrative
(party owners as a share of all muni owners) and matches the legacy production
weight on the firm-scope dimension that production already uses.

**2x2 expansion flag:** YES. The Cluster 1 representative correlates only 0.75
with the Tier A anchor `w_owners_sec_match` (well below the 0.90 threshold),
so a Cluster 1 win in Step 4 cannot distinguish denominator-scope (sector vs
muni) from firm-scope (matched vs universe) effects without the Tier B
`w_owners_muni_match` counterpart. Flag for the documented Tier B build path.

### Cluster 2

**Members:** `w_emp_muni_univ`, `w_firm_empshare_floor`
**Representative:** `w_firm_empshare_floor`

Cluster representative: `w_firm_empshare_floor`. Pairs continuous
`owner_party_share` with a `pmax(n_employees, owner_count, 1)` firm weight,
so zero-employment BNDES borrowers (MEI / Cartao BNDES, concentrated in Serv)
re-enter the instrument rather than being silently dropped. Beats
`w_emp_muni_univ` on interpretability rank (5 vs 4) and on coverage of a real
subpopulation flagged by Step 0 D-C (>=94% of zero-emp affiliated firms would
survive the floor in every block).

_Cluster-mate rationale (not selected):_

- `w_emp_muni_univ`: cluster contains `w_emp_muni_univ` (interp rank 4) and
  `w_firm_empshare_floor` (interp rank 5). The empshare_floor variant outranks
  emp on interpretability because it folds firm size honestly without dropping
  zero-employment firms.

**2x2 expansion flag:** YES. The novel floor mechanism invites the question
of whether a matched-only Tier B counterpart (`w_firm_empshare_floor`
restricted to matched firms) shows the same first-stage behaviour. The plan
explicitly anticipates this firm-scope ambiguity for the floor family; flag
for Tier B build path.

### Cluster 3

**Members:** `w_firm_muni_univ`
**Representative:** `w_firm_muni_univ`

Singleton cluster. Equal-per-firm aggregation of continuous
`owner_party_share`. Forced representative; rank 3 on interpretability
(size-blind aggregation) but defensible as a one-sentence construction.

**2x2 expansion flag:** No. Tier C alone is adequate for Step 4.

### Cluster 4

**Members:** `w_binary_muni_univ`
**Representative:** `w_binary_muni_univ`

Singleton cluster. Equal-per-firm aggregation of the binary alignment
indicator. Forced representative; lowest interpretability among the
muni_univ family but uniquely captures the extensive-margin signal (any
aligned owner).

**2x2 expansion flag:** No. Tier C alone is adequate for Step 4.

### Cluster 5

**Members:** `w_binary_empshare_floor`
**Representative:** `w_binary_empshare_floor`

Singleton cluster. Binary alignment indicator weighted by employment-share-
floor weights. Forced representative; the only weight that combines the
extensive margin with size-honest aggregation.

**2x2 expansion flag:** No. Tier C alone is adequate for Step 4.

## Summary

Five representatives advance to Step 4 (one-cycle proxy F-stats):

- Cluster 1 -- `w_owners_muni_univ` (flagged for Tier B expansion)
- Cluster 2 -- `w_firm_empshare_floor` (flagged for Tier B expansion)
- Cluster 3 -- `w_firm_muni_univ`
- Cluster 4 -- `w_binary_muni_univ`
- Cluster 5 -- `w_binary_empshare_floor`

Clusters 1 and 2 carry conditional Tier B build flags. Step 4 runs on the
five Tier C representatives first; Tier B is built only if a flagged
representative wins or places second under primary controls (`C1_FE`).
