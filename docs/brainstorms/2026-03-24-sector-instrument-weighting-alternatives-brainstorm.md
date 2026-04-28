# Brainstorm: Alternative Sector-Level Instrument Weighting Schemes

**Date:** 2026-03-24
**Status:** Complete

## What We're Building

A battery of sector-level shift-share instruments that differ in how firm-level political exposure is aggregated to the sector level. Currently, the only production instrument uses **owner-count weights** (`w_jmp = L_mjp_0 / N_rj_0`). We add three alternatives, each encoding a different substantive theory of how firm-level political connections translate into sector-level BNDES credit allocation.

## Why This Matters

The owner-count instrument treats each owner as an equally important political channel, regardless of the economic size of the firm. But if BNDES allocates credit in proportion to firm economic importance (e.g., employment), then the owner-count instrument misweights the exposure. Conversely, if political access is binary (any connection suffices), the intensive margin of owner shares is noise. Presenting all four weightings lets the data reveal which channel dominates.

## The Four Weighting Schemes

### 1. Owner-count (current baseline)

```
w_jmp = sum_f(L_fp_0) / sum_f(L_f_0)
```

**Substantive meaning:** Each owner is an equally important political connection. A firm with 5 affiliated owners out of 10 total contributes 5 affiliated owners to the sector numerator and 10 to the denominator, regardless of whether the firm has 5 or 5,000 employees.

**When it's the right object:** When BNDES responds to the density of political connections in a sector's ownership structure, irrespective of firm size.

### 2. Employment-weighted

```
w_jmp_emp = sum_f(n_emp_f_0 * omega_fp_0) / sum_f(n_emp_f_0)
```

where `omega_fp_0 = L_fp_0 / L_f_0` is the firm-level pooled-count baseline and `n_emp_f_0` is average firm employment over the pre-election window.

**Substantive meaning:** Larger firms (by employment) matter more because BNDES cares about job creation/preservation. A connected 10,000-employee firm moves more credit to the sector than a connected 5-employee firm with identical owner-affiliation shares.

**When it's the right object:** When the economic mechanism runs through employment — BNDES allocates credit proportional to the economic importance of connected firms, not just the number of connected owners.

**Implementation note:** Script 31 already computes `w_mjp_emp` but it is not consumed downstream. The employment should be baseline (pre-election window average), consistent with the pre-determination logic.

### 3. Equal-firm-weight (simple average)

```
w_jmp_firm = (1/|F_jm|) * sum_f(omega_fp_0)
```

**Substantive meaning:** Each firm is an independent political access point. What matters is how many firms in the sector are connected, not their size. This is the natural sector-level counterpart of the **unweighted** firm first stage, and matches the aggregation in Section 2.4 of the paper (eq. 4: the averaged firm instrument `FA_bar`).

**When it's the right object:** When the political-lending channel operates at the firm level — each firm is a separate node of political access — and the sector instrument should reflect the average firm's exposure.

### 4. Extensive-margin (binary)

```
w_jmp_binary = (1/|F_jm|) * sum_f 1(omega_fp_0 > 0)
```

**Substantive meaning:** Political connection is binary at the firm level. Having one affiliated owner is enough to activate the channel; additional affiliated owners add nothing. The sector's exposure is the fraction of its firms that have at least one connected owner.

**When it's the right object:** When the extensive margin dominates — the key question is whether a firm is "in the network" at all, not how deeply embedded it is.

## Key Decisions

1. **Firm base for aggregation:** Pre-election firm set (`F_jme_pre`) as primary for all variants. Contemporaneous firm set as robustness for equal-firm and binary variants. This ensures comparability across weighting schemes and avoids post-treatment composition bias.

2. **Employment timing:** Baseline (pre-election window average) employment for the employment-weighted variant. This maintains pre-determination and avoids endogeneity from post-election employment changes.

3. **Pipeline integration:** All four variants enter as a new dimension in script 53's spec engine (e.g., `--instrument-weight=owner_count|employment|equal_firm|binary`), producing comparable first-stage output.

4. **Instrument construction:** Build the three new instrument sets in the instrument pipeline (scripts 31/33/34 or a dedicated step), following the same cycle-specific and 2002-fixed baseline logic as the owner-count instruments.

5. **Aggregation verification:** Trust the algebra from Section 2.4 rather than adding computational assertions. The equal-firm instrument is the natural aggregation of the unweighted firm first stage; the employment-weighted instrument is the natural aggregation of the employment-weighted firm first stage.

6. **No separate diagnostic script:** Keep everything in the existing pipeline flow (instrument construction → panel building → estimation in script 53).

## Resolved Questions

- **Motivation:** Substantive channel exploration, not just robustness. The goal is to let the data reveal which aggregation theory best describes how political connections translate into sector credit allocation.
- **Scope:** All three alternatives (employment, equal-firm, binary) plus the existing owner-count baseline, presented as a battery.
- **Firm base:** Pre-election as primary, contemporaneous as robustness.
- **Employment timing:** Pre-election baseline.
- **Pipeline location:** Integrated into script 53 as a spec dimension.

## Implementation Sketch (for planning phase)

1. **Script 31:** Already computes `w_mjp_emp`. Add `w_mjp_firm` (equal-firm average) and `w_mjp_binary` (extensive-margin) columns.
2. **Script 33:** Extend baseline selection to pool all four weight variants across the pre-election window.
3. **Script 34:** Build `Z_*` and `dZ_*` instruments for each weighting variant (column naming: `Z_emp_*`, `Z_firm_*`, `Z_binary_*` alongside existing `Z_*`).
4. **Script 41:** Pass the new instrument columns through to Panel A.
5. **Script 53:** Add `--instrument-weight` dimension to spec engine; produce comparison table.
