# Political Affiliation Data Diagnostics

**Date**: 2026-03-15
**Status**: Brainstorm
**Goal**: Internal diagnostics to understand the structure, stability, and coverage of firm-owner political affiliation data — the micro-foundation of the shift-share instrument.

## What We're Building

A single interactive R script (`diagnostics/explore_affiliation.R`) that loads the reconstructed firm panel and produces console-printed summary tables answering five diagnostic questions about political affiliation patterns. Designed for line-by-line execution in RStudio.

## Why This Matters

The shift-share instrument relies on baseline party-exposure weights derived from owner affiliations. If affiliations are noisy, unstable, or geographically disconnected from the establishments where alignment shocks hit, the instrument's relevance and exclusion restriction are both at risk. These diagnostics inform whether the current design is defensible and where robustness checks are needed.

## Diagnostic Questions

### 1. Affiliation Rates by Year
- What % of firms in the reconstructed panel have at least one owner affiliated with a party (excluding "No party") in each year?
- How does this rate evolve over 2002-2019?
- Conditional on having affiliated owners: what is the distribution of `share_aff_owners` (fraction of owners who are affiliated)?

### 2. Firm Entry and Exit
- Distribution of the first year each firm appears in the panel
- Distribution of the last year each firm appears
- How many firms are present for the full 2002-2017 sample period vs. entering/exiting?

### 3. Party Stability
- How many distinct parties does a firm's ownership connect to over its lifetime?
- Distribution: 1 party, 2 parties, 3+?
- Frequency of party switches: how often does a firm's modal/dominant party change across years?
- Is the baseline party exposure a stable characteristic or something that fluctuates?

### 4. Temporal Gaps in Firm Presence
- Are there firms present in year t and year t+lambda but absent in some/all years in between?
- Distribution of gap lengths
- How prevalent are gaps? (share of firms with at least one gap)
- Implication: if a firm has gaps, the baseline weight from a pre-treatment year might reflect a firm that isn't actually operating

### 5. Multi-Municipality Firms
- What share of firms appear in more than one municipality (via RAIS establishments)?
- Distribution of municipality counts per firm
- Characterization: are multi-muni firms larger (by employment)? Concentrated in specific sectors?
- Mechanism question: owner affiliation is firm-level, but alignment shocks are municipality-level. For a firm in 5 municipalities, the same owner affiliation interacts with 5 different alignment shocks (via cartesian expansion in script 31). Is this appropriate or does it create noise?

## Key Decisions

1. **Data source**: Reconstructed panel from script 22 (`rais_bndes_reconstructed.fst`) — already filtered to RAIS-present firms with municipality and sector info
2. **"No party" treatment**: Exclude from affiliation rate calculations (consistent with instrument construction)
3. **Output**: Console tables only (internal diagnostics); no CSV or LaTeX output needed
4. **Scope**: Descriptive statistics and tabulations, no regression analysis
5. **Owner geography**: Not available in the data — cannot compare owner residence to establishment location

## Resolved Questions

1. **Data loading**: Load both the reconstructed panel (for muni/sector/employment) and the raw affiliation file (for party-level detail). Merge on (firm_id, year).

2. **Multi-municipality definition**: Report both — simultaneous (within-year) and lifetime (across all years) multi-municipality presence.

3. **Time window**: Restrict to 2002-2017 (the RAIS/BNDES analysis period).

## Open Questions

None — all design questions resolved.

## Approach

Single interactive R script with labeled `# ---- Section N ----` headers. Load data once at the top. Each section is self-contained after loading. Print summary tables using `data.table` operations. No external dependencies beyond the standard project stack (data.table, qs2, fst).
