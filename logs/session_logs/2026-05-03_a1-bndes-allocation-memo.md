# Session log — 2026-05-03 — A1 BNDES allocation memo (desk research)

## 2026-05-03 — A1 BNDES Allocation Memo

**Operations:**
- Created `logs/strategy/bndes_allocation_logic.md` (~10 pages, 7 sections + appendix). No code, no data work.
- Edited `docs/PROJECT_BLUEPRINT.md`: F0 status OPEN → CONFIRMED in §3; A1 status PROPOSED → COMPLETED in §4 with link; new D14 entry in §6 decisions log; §7 next action rewritten to point at A2 with expanded candidate set.
- Appended A1 entry to `logs/research_journal.md`.

**Decisions:**
- F0 verdict: BNDES uses ≥4 operationally meaningful margins — product line, sector, firm size, strategic-priority bin. Plus narrow export-orientation margin. Region is *not* an active allocation margin (rhetoric in PDP 2008 not matched by volume; Constitutional Funds operate outside BNDES; Annibelli & Souza 2021 + Lazzarini-Musacchio 2015 confirm).
- A2 candidate set expanded by **two new margins**: `bndes_product` (built from BNDES loan-level metadata) and `cnae_section × size_tertile` interaction (honoring the standalone-size_bin convention).
- Strategic-priority bin (PSI/PBM/Profarma eligibility) deferred to A2 round 2 on the 2009–2014 sub-panel only — would mechanically pick up program-period dummies on the full panel.

**Results:**
- Memo identifies: 7 candidate margins ranked by centrality and data availability; sector composition by year; PSI/PBM timeline with operational implications for the 2002–2017 panel; geographic-priority verdict (region as control, not aggregation dimension); 16-program table (FINEM, FINAME, Cartão, Automático, Exim, PSI, Profarma, Prosoft, Procult, P&G, Progeren, Climate Fund, Inova-series, BNDESPAR equity).
- Bibliography anchored to Lazzarini-Musacchio (2015), Musacchio-Lazzarini (2014), Bonomo-Brito-Martins (2015), Carvalho (2014), Cavalcanti-Vaz (2017); plus PDP 2008, PBM 2011, Lei 13.483/2017 (TLP), and BNDES Annual Reports 2002–2017.

**Status:**
- Done: A1 memo produced; PROJECT_BLUEPRINT.md updated; research journal updated.
- Pending: A2 (within-muni × time variation diagnostic) — now the active next action with the expanded candidate set per D14. A2 round 2 (program-period bins on 2009–2014 sub-panel) deferred until after round 1.

**Open questions:**
- Does the BNDES loan-level data have a clean product code that can be binned into 6–8 super-programs without manual cross-walks? Needed for the new `bndes_product` margin in A2.
- For the `cnae_section × size_tertile` interaction, do we tertile within sector × year (preferred — preserves cross-sector size structure) or pool across years (simpler — risks mixing pre/post-PSI cohorts)?
