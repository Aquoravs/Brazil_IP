## 2026-04-06 14:00 — Sector Aggregation Design Session

**Operations:**
- Read regs.tex (sections 2.1–2.5), scripts 51/52/53, script 30, sector_mapping.csv
- Analyzed instrument weight construction in script 31 (build_sector_exposure_weights.R)

**Decisions:**
- Extend script 52 (aggregated firm → sector) rather than script 53 for new aggregations
- Split the old `instrument_weight` dimension into three orthogonal dimensions:
  - `exposure`: firm-level baseline definition (pooled_count, binary) — parallels script 51
  - `aggregation`: how firms are weighted when collapsing to sector (owner_count, equal_firm, employment)
  - `regression_weight`: WLS regression weights (unweighted, emp_weighted with pre-election employment)
- Rename sector classifications: setor_bndes → bndes_sector, sector_group → custom_sector
- Four outcomes: bndes_share, bndes_extensive, log_employment, employment_share
- Five sector classifications: cnae_section, custom_sector, bndes_sector, size_bin
- Other dimensions: baseline (cycle_specific, 2002_fixed), alignment (coalition, party), fe (mxj_jxt, mxj_mxt), exposure_control (yes, no)
- Time variation fixed to levels only
- For aggregation link consistency: unweighted regression pairs with equal_firm aggregation; emp_weighted pairs with employment aggregation
- Pre-election employment weights mandatory (not contemporaneous) to avoid bad-controls

**Results:**
- Full 9-dimension spec engine design agreed upon
- BNDES sector mapping feasible from sector_mapping.csv using dominant product-line assignment
- Size bins: 3 terciles based on pre-election n_employees within CNAE section

**Status:**
- Done: Design decisions finalized
- Pending: Implementation plan, script refactoring
