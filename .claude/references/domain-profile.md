# Domain Profile

<!--
HOW TO USE: Fill this in manually OR let /discover (interactive interview) generate it.
All agents read this file to calibrate their field-specific behavior.
Delete sections that don't apply. Add sections specific to your field.
If no field is specified, agents default to applied economics.
-->

## Field

**Primary:** Industrial Policy, Political Economy, Development Economics
**Secondary:** Industrial Organization, Public Finance (in the sense of government allocation of credit)

---

## Target Journals (ranked by tier)

<!-- The Orchestrator uses this for journal selection. The Librarian prioritizes these in searches. -->

| Tier | Journals |
|------|----------|
| Top-5 | AER, Econometrica, JPE, QJE, REStud |
| Top field | AEJ:Applied, AEJ:Policy, Journal of Development Economics (JDE), Journal of Public Economics (JPubE) |
| Other field | Review of Economics and Statistics (RESTAT), Journal of the European Economic Association (JEEA), Economic Journal |

---

## Common Data Sources

<!-- The Explorer prioritizes these. The explorer-critic knows their quirks. -->

| Dataset | Type | Access | Notes |
|---------|------|--------|-------|
| BNDES indirect loans | admin (loan-level) | public | 2002–2025 in `data/raw/bndes_indirect_{auto,nonauto}/`. Loan-level granularity, mapped to firms via CNPJ. CNAE coding sometimes inconsistent with RAIS — use RAIS CNAE as authoritative (see D1). |
| RAIS (Relação Anual de Informações Sociais) | admin (employer-employee) | restricted (encrypted mount) | 2002–2017. Universe of Brazilian formal-sector employment. Full firm × worker × year panel. Used to construct firm size, sector, multi-municipality presence, employment baselines. Unexploited columns: education, age bracket, wage distribution, tenure, CBO occupation (see C6). |
| TSE elections | admin (electoral) | public | Mayor (4-year), governor (4-year), president (4-year). Used for political-affiliation instruments. `data/raw/david_ra/in_power_upd_2002_2019.qs2`. |
| IBGE PIB Municipal | admin (national accounts) | public | Annual nominal municipal GDP, deflated to 2018 R$ via national IPCA (see C5/C7 — no muni-level deflator exists for 2002–2017). |
| basedosdados | aggregator | public | R/Python wrapper around BigQuery. Use for population, IPCA, INEP Censo Escolar, PPM, PAM, CAGED, transfers, metro IPCA crosswalk. |
| Transfers (IBGE) | admin (fiscal) | public | `data/processed/transfers_ibge.qs2`, 96.3% match rate. Mechanism placebo for AR Phase 2. |
| INPE / INEP / PPM / PAM | admin | public via basedosdados | Production-factor proxies (education, agriculture). Pending advisor decision (C6). |

---

## Common Identification Strategies

<!-- The Strategist considers these first. The strategist-critic knows field-specific threats. -->

| Strategy | Typical Application | Key Assumption to Defend |
|----------|-------------------|------------------------|
| Bartik / shift-share IV | Regional exposure to a national shock weighted by local industry composition | Either (a) exogenous shocks given exposures (Borusyak-Hull-Jaravel 2022), or (b) exogenous exposure shares (Goldsmith-Pinkham, Sorkin & Swift 2020). State which. |
| Alignment-based political-economy IV | Mayor / governor / president alignment with the national-government coalition as a source of variation in BNDES allocation | Exclusion restriction: alignment affects GDP only through BNDES-mediated channels. Document direct effects on transfers, procurement (Phase 2 placebo). |
| Anderson-Rubin (AR) test of $H_0: \beta = 0$ | Inference under weak/many instruments — the active research agenda for this project | Test inverts confidence sets without estimating $\hat\beta$. Robust to weak first stage. |
| Ridge-Regularized Jackknifed AR (RJAR) | Many-instruments AR (sector × tier × interaction grows past ~20–30) | Mikusheva-Sun (2022); valid under many-weak-instruments, sparse alternatives. |
| Conditional subvector AR | Test one sector while treating others as nuisance | Useful when only a few sectors are policy-relevant; controls size when nuisance instruments are weak. |
| Fractionally Resampled AR (FAR), Cluster Jackknife AR | Stress tests for near-exogeneity and serial correlation in the 15-year muni panel | FAR for near-but-not-exact exogeneity; Cluster Jackknife AR for muni-level serial correlation. |
| Two-way FE (firm × year, muni × sector × year) | Firm-level first stage (script 51), sector-level first stage (script 53) | Assumes within-cell variation drives identification — note that >90% of $\sum X^2$ is within-cell at sector × muni × year (Prop 2 failure note, §6). |

---

## Field Conventions

<!-- The Coder and Writer follow these. The writer-critic checks for them. -->

- **Two-way clustering** is standard: `firm_id + muni_id` for firm-level; `muni_id + cnae_section` for sector-level.
- **`fixest` is the canonical estimator** in R; `feols(... | FE | iv ~ ..., cluster = ...)` syntax. F-statistics extracted via `fixest::wald(mod, keep = "^(FA_|dFA_|Z_|dZ_)")$stat`.
- **Share variables** (`s_*`): zero-fill OK on RAIS skeleton. **Change variables** (`delta_s_*`): never zero-fill from NA — only from observed subtraction (D5).
- **Baselines pooled over the 4-year pre-election window** `[e-4, e-1] ∩ [2002, 2017]` (D3); cycle-specific is primary, 2002-fixed is robustness.
- **Multi-municipality firms** (2% of firm-years, 30% of employment) handled as robustness via `is_multi_muni == 0` subsample (D11), not dropped from main sample.
- **2003 mayor / governor / president cycle dropped** (no pre-election data — D4).
- **No causal language** until AR test rejects $H_0$. Until then, frame results as "first-stage strength," "predicted reallocation," "reduced-form association."
- **Total BNDES not used as second-stage scale control** (bad-control concern — D10).
- **Real GDP** deflated by national IPCA; metro IPCA optional robustness on metro subsample (~55% of GDP, ~13 metros) — see C5/C7.
- **Significance stars off** when targeting AEA journals (AER, AEJ:Applied, AEJ:Policy); use confidence intervals or exact p-values. Stars on for working papers.

---

## Notation Conventions

<!-- The Writer and writer-critic enforce these. -->

| Symbol | Meaning | Anti-pattern |
|--------|---------|-------------|
| $m, j, t$ | municipality, sector, year | Don't use $i$ for muni in this project — $i$ is reserved for firm-worker observations in some RAIS contexts. |
| $f, p$ | firm, party | Don't use $i, k$. |
| $s_{mjt}$ | BNDES sector share within muni-year | Code: `s_mjt`. Constructed from observed BNDES totals; zero-fill OK on RAIS skeleton. |
| $\Delta s_{mjt}$ | yearly change in $s_{mjt}$ | Code: `delta_s_mjt`. Never zero-filled from NA — only from observed subtraction. |
| $Z_{mjt}, \Delta Z_{mjt}$ | sector-level shift-share instruments (levels, changes) | Code: `Z_*` / `dZ_*`. |
| $\mathrm{FA}_{fmjt}, \Delta \mathrm{FA}_{fmjt}$ | firm-level instruments (levels, changes) | Code: `FA_*` / `dFA_*`. Built from firm-party exposures × alignment shocks. |
| $\omega^\ell_{fp,t}$ | firm $f$'s baseline exposure to party $p$ at level $\ell \in \{m,g,p\}$ (mayor/governor/president) | Pre-election baseline pooled over the 4-year window. Cycle-specific = primary; 2002-fixed = robustness. |
| $\mathrm{Align}^\ell_{mpt}$ | binary indicator that party $p$ is aligned with the national-coalition leader at level $\ell$ in muni $m$ at time $t$ | Mayor / governor / president. Not the same as raw party identity. |
| $\beta$ | sectoral-reallocation coefficient on log GDP per capita (the AR-test target) | The null is $H_0: \beta = 0$ ("BNDES sectoral reallocation has no GDP effect"). |
| $\mathrm{cnae\_section}$ | 21 CNAE 2.0 sections (A–U) | Standard granularity. |
| $\mathrm{custom\_sector}$ | 11-group RAIS-departmental sector taxonomy | Renamed from `sector_group` 2026-04-06. |
| $\mathrm{bndes\_sector}$ | 4 BNDES macro-sectors (Agropecuária, Indústria, Infraestrutura, Comércio e Serviços) | Renamed from `setor_bndes` 2026-04-06. AR Phase 1 candidate. |
| $\mathrm{bndes\_sector\_size\_bin}$ | 4 macros × 3 employment terciles = 12 categories | Within-macro tercile (advisor C3). |

---

## Seminal References

<!-- The Librarian ensures these are cited when relevant. The strategist-critic knows their methods. -->

| Paper | Why It Matters |
|-------|---------------|
| Bartik (1991, *Who Benefits from State and Local Economic Development Policies?*) | Origin of the shift-share / Bartik instrument. Foundational for any local exposure × national shock design. |
| Goldsmith-Pinkham, Sorkin & Swift (2020, *AER*) | "Bartik instruments: what, when, why, and how" — Rotemberg-weight diagnostics, exposure-based identification. Direct precedent for our sector exposure share decomposition. |
| Borusyak, Hull & Jaravel (2022, *REStud*) | Shock-based identification: shift-share validity follows from exogenous shocks given exposures, not the reverse. Distinguishes from Goldsmith-Pinkham route. |
| Andrews, Stock & Sun (2019, *Annual Review of Economics*) | Weak-instruments survey. Anderson-Rubin and tF procedures. Use AR to make inference robust to weak first stage. |
| Mikusheva & Sun (2022, *REStud*) | Jackknifed AR for many-weak instruments — direct method for AR Phase 3 (RJAR). |
| Imbens & Angrist (1994); Angrist, Imbens & Rubin (1996) | LATE / monotonicity framework — needed to characterize compliers in any IV interpretation. |
| Cunningham (2021, *Causal Inference: The Mixedtape*) | Modern reference for econometric implementation; secondary citation only — Goldsmith-Pinkham is the primary methodological anchor. |
| Lim, Sergi & Yurukoglu (2024, *AEJ:Applied*) and related | Industrial-policy quantification, Brazil-style settings. Useful for positioning. |

---

## Theoretical Foundational References

<!-- The Theorist and theorist-critic default to these anchors when building or reviewing a theory section.
     Only needed if the paper has a formal theory section (econometric methods, theory+empirics,
     structural identification, or methodological reduced-form).
     Leave empty to fall back to the generic econometric theory defaults baked into the theorist agent. -->

| Topic | Anchor references |
|-------|------------------|
| Shift-share IV identification (exposure-based vs shock-based) | Goldsmith-Pinkham, Sorkin & Swift (2020); Borusyak, Hull & Jaravel (2022); Adão, Kolesár & Morales (2019, *QJE*) |
| Anderson-Rubin and weak-IV inference | Anderson & Rubin (1949); Andrews, Stock & Sun (2019); Mikusheva & Sun (2022); Moreira (2003) |
| Many-weak-instruments / regularization | Mikusheva & Sun (2022, *REStud*); Belloni, Chernozhukov & Hansen (2014, *JEP*); Hansen, Hausman & Newey (2008, *JBES*) |
| LATE / heterogeneous effects | Imbens & Angrist (1994); Angrist, Imbens & Rubin (1996); Heckman, Urzua & Vytlacil (2006) |
| Aggregation conditions for two-step regression equivalence | Frisch-Waugh-Lovell; see `docs/methodology_notes/conditions_C3_C5_C6_explained.tex` for the project-specific C1–C6 |

---

## Theoretical Foundational References

<!-- The Theorist and theorist-critic default to these anchors when building or reviewing a theory section.
     Only needed if the paper has a formal theory section (econometric methods, theory+empirics,
     structural identification, or methodological reduced-form).
     Leave empty to fall back to the generic econometric theory defaults baked into the theorist agent. -->

| Topic | Anchor references |
|-------|------------------|
| [e.g., DiD with staggered adoption] | [e.g., Callaway & Sant'Anna (2021); Sant'Anna & Zhao (2020)] |
| [e.g., Semiparametric efficiency] | [e.g., Newey (1990, 1994); Bickel-Klaassen-Ritov-Wellner (1993)] |

---

## Paper Author Team

<!-- Used by the theorist-critic to calibrate respect. If the authors are themselves among the reference
     literature on a topic, the critic avoids lecturing them on their own contributions.
     List author surnames + the topics they are foundational on. -->

| Author | Foundational on |
|--------|----------------|
| [e.g., Callaway] | [DiD with staggered adoption, $ATT(g,t)$] |

---

## Field-Specific Referee Concerns

<!-- The domain-referee and methods-referee watch for these. -->

- **"Are sector-level shift-share instruments truly Bartik-valid given firm heterogeneity within cells?"** — within-cell variation dominates between-cell at $(j, m, t)$ (91–94% of $\sum X^2$); see `docs/methodology_notes/proposition2_failure_note.tex`. Cell-level second stage cannot recover firm-level $\lambda$ exactly because C6 fails on real data.
- **"Why not use total BNDES as a scale control in the second stage?"** — bad-control concern (D10): total BNDES is endogenous to the political-economy mechanism we are estimating.
- **"What does the simplex constraint do to your estimates?"** — $\sum_j s_{mjt} = 1$ implies $\sum_j \Delta s_{mjt} = 0$, which mechanically attenuates the firm-level signal at the sector level via cross-sector cancellation (D6 — drop the largest sector for vector $\Delta s$ regressions).
- **"How is the political-economy first-stage exclusion restriction defended?"** — alignment must affect GDP only through BNDES-mediated channels. Phase-2 mechanism placebo on transfers (`data/processed/transfers_ibge.qs2`) and procurement (pending) directly tests this.
- **"Employment outcomes (`employment_log`, `employment_share`) generate F up to 265 — isn't this evidence of a direct alignment-employment channel that violates exclusion?"** — yes; treat as reduced-form direct effects, not as IV first stage.
- **"Why pool the baseline over a 4-year pre-election window rather than fix it at 2002?"** — both used (D3): cycle-specific is primary, 2002-fixed is robustness. Cycle-specific is not weaker on real data (max F = 103 governor vs 24 president for 2002-fixed).
- **"Are you using a national IPCA on muni-level GDP?"** — yes, no muni-level deflator exists for 2002–2017 (C5/C7). Metro IPCA is robustness on metro subsample only.
- **"Multi-municipality firms are 30% of employment — how robust is the firm-level result?"** — robustness via `is_multi_muni == 0` subsample (D11).
- **"Why an AR test rather than 2SLS confidence intervals?"** — first-stage strength varies materially across specs (max F = 103 firm-level extensive; ≈ 6 intensive). AR is robust to weak first stage; with sector × tier × interaction the instrument count grows past 20–30 (C8 — RJAR).

---

## Quality Tolerance Thresholds

<!-- Customize for your domain's standards. Used by quality.md. -->

| Quantity | Tolerance | Rationale |
|----------|-----------|-----------|
| Point estimates | [e.g., 1e-6] | [Numerical precision] |
| Standard errors | [e.g., 1e-4] | [MC variability] |
| Coverage rates | [e.g., ± 0.01] | [Simulation with B reps] |
