---
title: "Map Script 51 Battery Commands"
type: plan
status: completed
date: 2026-04-02
---

# Script 51 Battery Command Map

## Goal

Write the concrete `Rscript` commands needed to finish the script-51 firm first-stage battery without rerunning the production tables already present in `paper/tables/firm/`.

## Current observed state

- Production tables currently present:
  - `firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__pooled_count.tex`
  - `firm__main__levels__extensive__coalition__cycle_specific__unweighted__all_firms__binary.tex`
  - `firm__main__levels__extensive__coalition__cycle_specific__emp_weighted__all_firms__binary.tex`
- Production manifest currently has only 2 completed rows, so file presence is more reliable than the existing manifest snapshot.
- `--specs=all --dry-run` resolves to 28 configs in the current script.

## Key implementation findings

1. Script 51 has no resume guard. It does not automatically skip configs whose `.tex` files already exist.
2. The clean way to avoid reruns is to issue targeted commands rather than `--specs=all`.
3. Current dry runs show no pre-skips for binary interaction specs, so the older "binary interaction instruments not available" assumption is stale in the present data state.
4. `--specs=all` is the current script-defined full battery, but it does not cover some older presentation tables such as:
   - `changes + intensive`
   - `party + changes`
   - `fixed_baseline + changes`
   - `single_muni + changes`

## Validated command set

### A. Remaining current script battery (25 missing configs from the 28-config `--specs=all` universe)

```bash
Rscript scripts/R/run_politicsregs.R 51 --family=interaction
Rscript scripts/R/run_politicsregs.R 51 --specs=changes,party,fixed_baseline,single_muni,intensive
Rscript scripts/R/run_politicsregs.R 51 --specs=weighted --family=interaction
Rscript scripts/R/run_politicsregs.R 51 --specs=weighted --family=main --exposure=pooled_count
```

### B. Extra pooled-count appendix tables not included in `--specs=all`

```bash
Rscript scripts/R/run_politicsregs.R 51 --specs=intensive --time-variation=changes --family=main,interaction --exposure=pooled_count
Rscript scripts/R/run_politicsregs.R 51 --specs=party,fixed_baseline,single_muni --time-variation=changes --family=main --exposure=pooled_count
```

## Open decisions surfaced while mapping commands

1. Decide which battery is canonical:
   - the current script-defined `--specs=all` battery (28 configs), or
   - the broader presentation-oriented pooled-count battery that adds the extra combined specs above.
2. Decide whether `party`, `2002_fixed`, and `single_muni` changes tables should remain appendix-only or be folded into the canonical battery.
3. Decide whether the script should be patched with a real resume guard based on existing `.tex` outputs or manifest rows before large reruns.
