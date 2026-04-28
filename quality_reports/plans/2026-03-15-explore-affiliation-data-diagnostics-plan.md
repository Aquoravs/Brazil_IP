---
title: "Explore: Political Affiliation Data Diagnostics"
type: explore
status: completed
date: 2026-03-15
origin: docs/brainstorms/2026-03-15-affiliation-data-diagnostics-brainstorm.md
---

# Explore: Political Affiliation Data Diagnostics

## Overview

Create an interactive R script (`BNDES/politicsregs/diagnostics/explore_affiliation.R`) that loads the reconstructed firm panel and raw owner affiliation data, then produces console-printed summary tables answering five diagnostic questions about political affiliation patterns. The goal is internal understanding of the micro-foundation of the shift-share instrument — not paper-ready output.

## Motivation

The shift-share instrument weights `w_mjp = L_mjp / L_mj` depend critically on owner affiliations being (a) prevalent enough for meaningful variation, (b) stable enough that baseline weights are informative, and (c) geographically coherent with the municipality-level alignment shocks. If any of these fail, the instrument's relevance or exclusion restriction is at risk. These diagnostics surface potential threats before they become referee objections.

## Data Sources

Two files, loaded once at script top:

1. **Reconstructed panel** (`output/rais_bndes_reconstructed.fst`):
   - Unit: firm × muni × year
   - Columns needed: `firm_id`, `muni_id`, `year`, `cnae_section`, `n_employees`, `in_owner`
   - Use `fst::read_fst(columns = ...)` for column-selective read

2. **Raw affiliation file** (`raw/david_ra/owner_aff_firm_year_party_2002_2019.qs2`):
   - Unit: firm × year × party
   - Columns: `firm_id`/`cnpj`, `year`/`ano`, `party`/`sigla_partido`, `aff_owners`/`n_aff_owners`, `share_aff_owners`/`share_aff`
   - Use `qs2::qs_read()`, then standardize column names following script 31's pattern

**Time window**: Filter both sources to `year %in% 2002:2017` after loading.

**Merge**: Join on `(firm_id, year)` — owner affiliation is firm-level, not firm-muni-level (see brainstorm: resolved question 1).

## Implementation Plan

### Preamble: Bootstrap and Load

```
# ---- Preamble ----
# Source bootstrap to get PROJECT_ROOT, OUTPUT_DIR, and utility functions
# Load packages: data.table, fst, qs2
# Load reconstructed panel (fst, column-selective)
# Load raw affiliation (qs2)
# Standardize column names (dynamic detection, following script 31 pattern)
# Filter to 2002-2017
# Exclude "No party" rows from affiliation data for all analyses
# Compute total_owners per (firm_id, year) using median(aff_count / share_aff) floored at sum(aff_count)
```

Key conventions from existing scripts:
- `firm_id := as.integer(firm_id)`
- `party := trimws(as.character(party))`
- `aff_count := as.integer(aff_owners)`
- `share_aff := as.numeric(share_aff_owners)`
- Detect column names dynamically (check for `cnpj`/`cnpj_raiz`/`firm_id`, etc.)

### Section 1: Affiliation Rates by Year

**Questions answered:**
- What % of firms have at least one affiliated owner (excl. "No party") per year?
- How does this rate evolve over 2002-2017?
- Conditional on affiliation: distribution of `share_aff_owners`

**Approach:**
1. From the reconstructed panel, get the universe of unique `(firm_id, year)` pairs
2. From the raw affiliation (already filtered to exclude "No party"), get unique `(firm_id, year)` pairs with `aff_count > 0`
3. Merge: `affiliated_rate = n_affiliated_firms / n_total_firms` by year
4. Print a year × rate table
5. For affiliated firms, compute `total_affiliated / total_owners` per (firm_id, year) and show quantiles (p10, p25, p50, p75, p90) by year

**Expected output:** A `data.table` with columns `year`, `n_firms`, `n_affiliated`, `pct_affiliated`, plus conditional share quantiles.

### Section 2: Firm Entry and Exit

**Questions answered:**
- Distribution of first year each firm appears in the reconstructed panel
- Distribution of last year
- How many firms span the full 2002-2017 period?

**Approach:**
1. From reconstructed panel: `first_year := min(year)` and `last_year := max(year)` by `firm_id`
2. Tabulate `first_year` distribution (histogram-style: count per year)
3. Tabulate `last_year` distribution
4. Count firms where `first_year == 2002 & last_year == 2017` (full-period firms)
5. Compute `n_years_present` per firm; show distribution (1 year, 2-5, 6-10, 11-15, 16 = full)

**Expected output:** Two frequency tables (entry/exit years) + a duration distribution table.

### Section 3: Party Stability

**Questions answered:**
- How many distinct parties per firm over its lifetime?
- How often does the dominant party change?
- Is baseline party exposure stable?

**Approach:**
1. From raw affiliation (excl. "No party"), compute per `firm_id`:
   - `n_parties_ever := uniqueN(party)`
   - `n_parties_per_year := uniqueN(party)` by `(firm_id, year)`, then `median` and `max` across years
2. Tabulate `n_parties_ever`: 1, 2, 3, 4, 5+
3. Identify the **dominant party** per (firm_id, year) = party with highest `aff_count`; ties broken alphabetically
4. Compute `n_dominant_changes` per firm = number of years where dominant party differs from previous year's dominant party
5. Tabulate: 0 changes, 1, 2, 3+ changes
6. For firms with a baseline year (2002 or first available), check if baseline dominant party = modal dominant party over lifetime → share of firms where baseline is "representative"

**Expected output:** Party count distribution + party switch frequency table + baseline stability share.

### Section 4: Temporal Gaps in Firm Presence

**Questions answered:**
- Do firms have gaps (present in t and t+λ, absent in between)?
- Distribution of gap lengths
- Prevalence (share of firms with at least one gap)

**Approach:**
1. From reconstructed panel, get sorted `(firm_id, year)` pairs
2. Per firm, compute `year_diff := diff(year)` between consecutive appearances
3. A gap exists when `year_diff > 1`; gap length = `year_diff - 1`
4. Summary:
   - `n_firms_with_gap` / `n_firms_total` = prevalence
   - Distribution of gap lengths (1-year gap, 2-year, 3-year, ..., 10+)
   - Total number of gaps
5. Cross-check: do gapped firms have affiliation data in their gap years? (i.e., `in_owner = 1` in raw affiliation but no RAIS record)

**Expected output:** Gap prevalence rate + gap length distribution table.

### Section 5: Multi-Municipality Firms

**Questions answered:**
- Share of firms in >1 municipality (simultaneously and over lifetime)
- Distribution of municipality counts
- Size and sector characterization

**Approach:**

**5a. Simultaneous (within-year):**
1. From reconstructed panel: `n_munis_year := uniqueN(muni_id)` by `(firm_id, year)`
2. Classify: 1 muni, 2, 3-5, 6-10, 11+
3. Tabulate distribution (share of firm-years in each bin)
4. Median `n_employees` by bin (are multi-muni firms larger?)

**5b. Lifetime:**
1. `n_munis_ever := uniqueN(muni_id)` by `firm_id`
2. Same binning and tabulation
3. Cross with `cnae_section`: which sectors have the most multi-muni firms?

**5c. Mechanism relevance:**
1. For multi-muni firms (≥2 munis in same year): what fraction of total firm-years do they represent?
2. What fraction of total employment do they account for?
3. Implication note: these firms' owner affiliations are cartesian-expanded across municipalities in script 31, creating identical `share_fp` values interacting with different alignment shocks

**Expected output:** Two distribution tables (within-year, lifetime) + size/sector cross-tabs + employment share of multi-muni firms.

## Acceptance Criteria

- [x] Script runs interactively in RStudio, section by section
- [x] Uses project bootstrap (`script_bootstrap.R`) for path configuration
- [x] Loads data once at top; sections are self-contained after loading
- [x] All five diagnostic sections produce printed summary tables
- [x] "No party" excluded consistently from all affiliation calculations
- [x] Time window restricted to 2002-2017
- [x] No CSV/LaTeX output; console-only
- [x] Column name standardization follows script 36's pattern (hardcoded for known file)
- [x] Integer types handled correctly (`as.integer(firm_id)`, etc.)

## Dependencies

- Script 22 must have been run (reconstructed panel exists as `.fst`)
- Raw affiliation file must exist at `raw/david_ra/owner_aff_firm_year_party_2002_2019.qs2`
- Packages: `data.table`, `fst`, `qs2`

## Sources

- **Origin brainstorm:** [docs/brainstorms/2026-03-15-affiliation-data-diagnostics-brainstorm.md](docs/brainstorms/2026-03-15-affiliation-data-diagnostics-brainstorm.md) — key decisions: single interactive script, load both data sources merged on (firm_id, year), both within-year and lifetime multi-muni definitions, 2002-2017 window, console output only
- **Script 31** (`3_instruments/31_build_sector_exposure_weights.R`): column standardization pattern and total_owners computation
- **Script 36** (`3_instruments/36_build_firm_level_instruments.R`): firm-level affiliation loading pattern
- **Script 22** (`2_firm_panel/22_reconstruct_merged.R`): reconstructed panel structure and `in_owner` flag
- **Archived diagnostic** (`_archive/3x_diagnose_total_owners.R`): total_owners mismatch resolution (rounding + median)
