# E3c — F1 Decomposition for `policy_block × size` margin
Generated: 2026-05-04 20:28:26

Coarser sector dimension (policy_block, 4 active blocks: Agro/Ind/Infra/Serv) 
crossed with A2 (2 sizes) or A3 (3 sizes). Active bins:

- policy_block × A2 → 8 active bins
- policy_block × A3 → 12 active bins

Compared to E3 (`cnae_section × size`): 17×{2,3} = {34, 51} active bins.

## Per-spec summary

| Option | Denom | n_bins | n_supported | mean share_within | med share_within | max med σ | verdict |
|--------|-------|-------:|------------:|-----------------:|----------------:|----------:|---------|
| policy_block_A2 | V1 | 8 | 3 | 0.615 | 0.628 | 0.302 | SUPPORTED |
| policy_block_A2 | V2 | 8 | 3 | 0.617 | 0.629 | 0.302 | SUPPORTED |
| policy_block_A3 | V1 | 12 | 3 | 0.642 | 0.642 | 0.302 | SUPPORTED |
| policy_block_A3 | V2 | 12 | 3 | 0.643 | 0.643 | 0.301 | SUPPORTED |

## Comparison to E3 (cnae_section × size)

From `f1_combined_report.md`:
- cnae_section × A2 V1: mean share_within = 0.755, med = 0.799
- cnae_section × A3 V1: mean share_within = 0.769, med = 0.808

## Comparison to round 1 (sector-only)

From `variation_decomposition.csv`:
- policy_block × V1 (5 bins, includes XX): see round 1
- policy_block_active × V1 (4 bins): see round 1

## Implication

Coarser sector × finer size produces fatter cells but loses sector granularity. 
If `mean share_within` here is comparable to E3 (within ~0.05), the policy_block 
× size margin is preferable for production: same identification with much fewer 
instruments and less coverage risk.

