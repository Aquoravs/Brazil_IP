# BNDES Allocation Logic: Institutional and Documentary Review (A1)

**Author:** Claude (desk research, no code)
**Date:** 2026-05-03
**Purpose:** Tests F0 in the project blueprint — the existence and identity of margins along which BNDES allocates credit. Defines the candidate set for A2 (within-muni × time variation diagnostic).
**Reading order in pipeline:** Read after `docs/PROJECT_BLUEPRINT.md` §3 (F-link chain) and before A2 implementation.

---

## Executive summary

BNDES allocates credit along **multiple, overlapping** dimensions: a product-line classification that every loan carries by design, sectoral departments and named programs, a firm-size dimension with dedicated instruments and quota-style commitments, and a layer of strategic / industrial-policy priorities overlaid by the federal government through PDP (2008), Plano Brasil Maior (2011), and PSI (2009–2016). Documenting these dimensions is the substantive content of §§1–5.

For the paper's purpose, however, only a strict subset of these dimensions are usable as **aggregation margins** for the muni-level shift-share IV. A margin $s$ is usable iff every firm-year in the RAIS universe — including the ~99% of firms that never borrow from BNDES — can be assigned to one $s$-bin from data observable independently of the loan decision. This makes the baseline share $s_{m,s,t_0}$ (employment share of muni $m$ in bin $s$ at the predetermined date) well-defined for every muni, including those with no BNDES exposure. **A margin must be a firm-side classifier, not a loan-side classifier.**

Under that criterion the candidate set is much narrower than the catalog of dimensions BNDES uses internally. The admissible margins, ranked:

1. **Sector (CNAE-section, BNDES-macro-sector, custom-block).** Defined for every firm; already in the reconstructed panel as three taxonomies.
2. **Firm size with absolute thresholds (standalone `size_bin`).** Defined for every firm via `n_employees`. Preferred classification: absolute thresholds (MPME 0–49 / Média 50–499 / Grande 500+) approximating BNDES's own revenue-based porte categories. BNDES classifies firms by observable revenue cutoffs, not tertiles; `n_employees`-based absolute cutoffs are the closest admissible proxy.
3. **`CNAE × size_bin` interaction** taken as the cell variable, using the same absolute thresholds. Captures the targeting logic of programs like Cartão BNDES (MSME-only) and PSI tier 1 (small-firm rates) without using any loan-side or program-side classifier.

Dimensions BNDES *does* use that are nevertheless **inadmissible** as aggregation margins:

- **Product line** (FINEM / FINAME / Cartão / Automático / Exim / PSI sub-programs / named sector programs). A loan-side classification — observed only conditional on borrowing. Use it to motivate which firm-side cells matter; do not aggregate on it.
- **PSI eligibility.** Eligibility was defined by the *purpose* of the loan (acquisition of eligible capital goods), not by firm CNAE. Cannot be assigned to non-borrowers from CNAE alone.

Dimensions that are firm-side but not promising:

- **Industrial-policy CNAE crosswalks** (PBM Block 1–5, Profarma list, Prosoft list, P&G suppliers list). These are admissible as coarsenings of CNAE × year, but each is essentially a re-bucketing of CNAE that we already test directly. Worth flagging in the catalog; not worth dedicating A2 effort to unless the primary CNAE-side margins fail.
- **Region/state.** Admissible, but BNDES does not actively allocate on this dimension (§4). Use as control, not as aggregation margin.
- **Export orientation.** Admissible only conditional on a clean RAIS-export or SECEX merge for non-borrowers — not currently in the panel.

The implication for A2 round 1: run the variance decomposition on the three sector taxonomies already in the panel plus `size_bin` (standalone, absolute thresholds) and the `cnae_section × size_bin` interaction. The firm-CNAE choice is settled (P1 validates the firm-level channel), so we do not aggregate on project-CNAE; the direct-vs-indirect delivery distinction is institutional, not relevant to margin choice. Region as control. Industrial-policy CNAE crosswalks as a fallback only if the primary set fails.

The remainder of this memo documents the evidence behind these claims.

---

## §1. BNDES governance and decision-making

BNDES (Banco Nacional de Desenvolvimento Econômico e Social) is a federal public company under the direct supervision of the federal executive. Its governance has four operative features that matter for the identification strategy.

**Presidential tutelage.** The President of BNDES, the Vice-President, and the Directors are appointed and dismissed at will by the President of the Republic. In 2007 the bank was formally elevated to a status "comparable to that of a ministry" and placed under direct presidential tutelage (Lazzarini, Musacchio, Bandeira-de-Mello & Marcon, 2015; Musacchio & Lazzarini, 2014). This is the institutional fact that motivates the political-alignment instrument: the federal incumbent has ex ante control over the bank's senior leadership and, through it, over which sectors, programs, and projects receive priority.

**Board structure.** The highest body is the Conselho de Administração (Board of Directors), which approves the bank's annual business plan and supervises the Diretoria. The Diretoria comprises the President, the Vice-President, and roughly seven to nine sectoral Directors whose portfolios shift with reorganizations. A Conselho Fiscal and a Conselho Consultivo (with representatives of government and civil society) provide oversight; their role is advisory rather than decisional. Operational committees — Strategy Management, Operations Planning, Audit — handle the day-to-day flow of cases.

**Sectoral operating areas.** Below the Diretoria, BNDES is organized into operating areas (áreas operacionais) corresponding to broad sectors of the economy. The names and exact divisions have changed across reorganizations, but throughout 2002–2017 the bank has maintained dedicated departments for, at minimum: **(a) industry / capital goods** (AOI / AI), **(b) infrastructure** (AIE), **(c) trade and services**, **(d) agro and agroindustry**, **(e) MSMEs / indirect operations** (AOI-MPME / AINT), and **(f) capital markets and equity** (BNDESPAR). Three subsidiaries — **FINAME** (capital goods financing), **BNDESPAR** (equity), and **BNDES Limited** (international, London-based) — execute specialized mandates. The sectoral department is, in practice, where the political principal's priorities are translated into rules of thumb on which projects to advance.

**Funding sources and the role of the National Treasury.** Throughout the period of interest, BNDES funded itself primarily through (i) FAT (Fundo de Amparo ao Trabalhador, the workers' fund), (ii) PIS/PASEP, and (iii) Treasury loans. The Treasury share rose dramatically from about 2008 onward, with cumulative on-lending exceeding R$ 400 billion by 2014. These Treasury loans were extended at the long-term reference rate (TJLP) and lent to firms at TJLP plus a small spread, producing an implicit interest subsidy financed by the federal budget. The subsidy mechanism is what gives the political principal extra-budgetary leverage over the allocation: for each real lent, the Treasury bears the difference between TJLP and its own marginal funding cost on public debt (Sant'Anna & Borça in BNDES discussion papers; Bonomo, Brito & Martins, 2015). This is also why the post-2015 fiscal reform — replacement of TJLP by TLP (Lei 13.483/2017, effective 2018-01-01) — is treated as an exogenous shock to the bank's allocative leverage.

**Coordination with industrial policy.** BNDES participates as a coordinator, vice-coordinator, or member in every executive committee of major industrial-policy frameworks. It contributed eight of the 35 initial measures of Plano Brasil Maior (PBM) and is a permanent member of the Conselho Nacional de Desenvolvimento Industrial (CNDI), the inter-ministerial body that sets PBM strategy under the Presidency of the Republic (BNDES Annual Report 2011). This integration with the federal industrial-policy apparatus is what makes "alignment" a meaningful instrument: the same political coalition that controls the executive sets PDP/PBM priority sectors **and** controls the BNDES leadership that operationalizes them.

**Direct vs. indirect operations.** A first-order distinction in BNDES's logic is between *direct* operations (BNDES negotiates and contracts the loan directly with the firm — typical for FINEM and large projects) and *indirect* operations (BNDES on-lends through accredited financial agents — Banco do Brasil, Caixa, regional development banks, and large private banks — which assume the credit risk and earn an intermediation spread). FINAME, Cartão BNDES, BNDES Automático, and parts of Exim are predominantly indirect. The direct vs. indirect classification is a *delivery channel*, not an allocation margin. The paper uses **firm-CNAE (RAIS)** as the aggregation classifier throughout, by prior decision — the firm-level channel is the validated mechanism (P1), and firm-CNAE is the only classifier defined for the non-borrower majority of the RAIS universe. Whether BNDES *labels* a given indirect loan with a project-CNAE that differs from the borrower's RAIS-CNAE is a descriptive observation about how the bank classifies its book; it is not a question this paper resolves through the choice of aggregation margin.

---

## §2. Allocation dimensions BNDES uses, and which of them are admissible aggregation margins

This section answers two distinct questions in sequence:

(a) **What dimensions does BNDES actively use to allocate credit?** This is a description of the bank's behaviour and is the substantive content of the section.
(b) **Which of those dimensions can serve as the aggregation margin in our muni-level shift-share IV?** This is a stricter test — a margin must be a *firm-side* classifier, observable from RAIS for every firm-year (including the firms that never borrow from BNDES), and assignable independently of the loan decision. A loan-side classification cannot serve as an aggregation margin because it is undefined for non-borrowers, who are the bulk of the RAIS universe and the bulk of the muni's denominator.

### (a) Dimensions BNDES actively uses

| # | Dimension | What it is | Institutional evidence that BNDES uses it |
|---|---|---|---|
| 1 | **Product line** (FINEM, FINAME, Cartão, Automático, Exim, PSI sub-programs, named sector programs) | The instrument through which BNDES delivers credit. Every loan carries a product code. | Loan-level metadata; BNDES's own taxonomy of "produtos" on bndes.gov.br; sector-specific named programs (Profarma, Prosoft, Procult, P&G, Progeren) operate as product lines with eligibility rules. |
| 2 | **Sector** (CNAE section, BNDES macro-sector, custom block) | The economic sector of the borrower or of the financed project. | Sectoral departments (AOI/AIE/AI/AINT/AINP) are the bank's organizational backbone; PDP 2008 nominated 25 priority sectors; PBM 2011 organized 19 competitiveness committees into 5 strategic blocks; BNDES Annual Reports decompose disbursements by industry / infrastructure / agro / trade-services. |
| 3 | **Firm size** (MSME vs. large; tertile or quartile within sector) | Number of employees or revenue band. | Cartão BNDES is exclusive to MPME; BNDES Crédito Pequenas Empresas dedicated line; FGI guarantee fund for MPME; differentiated rates/spreads for MPME within FINAME and Automático; PBM and PDP both list "SMEs" as cross-cutting strategic areas; BNDES tracks MSME share of disbursements as a headline metric (43% in 2014). |
| 4 | **Strategic-priority overlay** (PSI eligibility; Profarma; Prosoft; Procult; P&G; Progeren; Climate Fund; …) | A federal-government overlay assigning differentiated rates and conditions to projects in priority categories. | PSI 2009–2016 imposed below-TJLP fixed rates on capital-goods financing (6.75% p.a. flat for several years); sector programs (Profarma, Prosoft, Procult) have eligibility lists keyed to CNAE and project type; PBM 2011 announced reduced spreads (1.7% → 0.9%) on innovation, environment, sanitation, public security projects. |
| 5 | **Export orientation** (BNDES Exim eligibility) | Whether the firm sells to foreign markets. | BNDES Exim Pre-Shipment, Post-Shipment, Exim Automatic — distinct product family with its own eligibility rules and credit conditions; pre-shipment fixed rate (TJFPE) set quarterly. |
| 6 | **Region / state** | Geographic priority. | PDP 2008 listed "Regionalização" as one of six strategic areas; BNDES has occasionally announced reduced spreads for projects in less-developed regions; some sector programs prioritize regional development banks (BNB, BASA) as accredited intermediaries. **Empirically weak**: North/Northeast are *underweighted* in BNDES disbursements (§4). |

### (b) Admissibility as aggregation margins

Mapping the six dimensions to firm-side classifiers gives the following verdict:

| # | Dimension | Firm-side classifier? | Admissible as aggregation margin? | Why |
|---|---|---|---|---|
| 1 | Product line | **No.** A property of the loan, not the firm. | **Inadmissible.** | Undefined for non-borrowers (the bulk of the RAIS universe). Use only to motivate which sector × size cells matter. |
| 2 | Sector (CNAE-section / BNDES-macro / custom-block) | **Yes.** Every firm has a CNAE in RAIS. | **Admissible.** | Already in the panel as three taxonomies. |
| 3 | Firm size | **Yes.** Every firm has `n_employees` in RAIS. | **Admissible** as standalone margin and as part of sector × size interactions. Preferred: absolute thresholds (MPME / Média / Grande) mirroring BNDES porte categories. Within-sector tertiles are a valid robustness option but less institutionally grounded — BNDES decides on observable revenue categories, not relative tertiles. | Constructible from the existing panel. |
| 4a | Strategic-priority overlay — *PSI eligibility* | **No.** PSI eligibility was defined by the *purpose* of the loan (eligible capital-goods purchase), not by firm CNAE. | **Inadmissible.** | Cannot be assigned to non-borrowers from CNAE alone. |
| 4b | Strategic-priority overlay — *PBM-Block / Profarma / Prosoft / P&G CNAE crosswalks* | **Yes**, by CNAE-list membership × program-active years. | **Admissible** but redundant. | Each is a coarsening of CNAE the panel already carries. Mention in the catalog; do not invest A2 effort here unless the primary margins fail. |
| 5 | Export orientation | **Yes**, conditional on a RAIS-export or SECEX merge. | **Admissible conditional on data merge.** | Not currently in the reconstructed panel; deferred. |
| 6 | Region / state | **Yes.** | Admissible, but **BNDES does not allocate on it** (§4). | Use as control variable, not as aggregation margin. |

The active candidate set for A2 is therefore **CNAE (3 taxonomies), standalone `size_bin`, and `CNAE × size_bin`** — narrower than the catalog of dimensions BNDES uses, but wider than CNAE alone. Items 1 and 4a are out (loan-side or purpose-side classifiers). Item 4b is technically admissible but not promising. Items 5 and 6 are deferred or used as controls.

### Empirical sector composition of disbursements

To anchor the table, the historical sector composition of BNDES disbursements (per BNDES Annual Reports) is approximately:

| Year | Industry | Infrastructure | Trade & Services | Agro / Agro-industry | Total disbursement (R$ bn, current) |
|---|---|---|---|---|---|
| 2002 | ~57% | ~30% | ~9% | ~4% | ~38 |
| 2010 | 47% | 31% | 16% | 6% | 168 (or 144 ex-Petrobras capitalization) |
| 2013 | ~37% | 36% | ~22% | ~5% | 190 |
| 2014 | 26.7% (R$ 50 bn) | 36.7% (R$ 68.9 bn) | ~30% | ~6% | 188 |
| 2017 | ~30% | ~40% | ~25% | ~5% | ~70 (post-PSI contraction) |

(Figures are approximate; exact composition fluctuates with capital-markets operations like the 2010 Petrobras capitalization. Source: BNDES Annual Reports 2002, 2010, 2011, 2013, 2014, 2017.)

The composition shifts reveal the **political logic**: the Lula years (2002–2010) emphasize *industry*, with the national-champions strategy (JBS, Marfrig, BRF, Eike Batista's group, Oi) loading the industry line. The Dilma years (2011–2014), under PBM, sustain industry but shift the marginal real toward infrastructure as PSI saturates capital-goods financing. The Temer transition (2016–) collapses total volume and rebalances toward infrastructure, which is the lower-risk legacy mandate.

---

## §3. Timeline of major shifts in allocation logic, 2002–2017

The 16-year window of the paper spans three distinct regimes for BNDES allocation. Each has consequences for which sectoral and program margins should be considered "active" in a given year.

**2002 (end-Cardoso) — the legacy bank.** BNDES is a mid-sized infrastructure financier with disbursements around R$ 38 billion. Sector composition is industry-heavy (~57%) and infrastructure (~30%). FINAME is the workhorse for capital-goods financing; BNDES Automático handles smaller projects. No subsidized-rate programs comparable to PSI yet exist. The bank is operationally autonomous; the "alignment" margin is muted.

**2003–2007 (Lula 1) — gradual expansion.** The 2003 statute change permits BNDES to finance Brazilian firms' operations abroad for the first time, opening the door to the national-champions strategy. Cartão BNDES is consolidated as the MSME instrument. Disbursements grow steadily but without dramatic regime shift.

**2007–2010 (Lula 2 — the expansionary turn).**
- 2007: BNDES is upgraded to "ministerial status" under direct presidential tutelage (Musacchio & Lazzarini 2014, ch. 5). National champions strategy formalized: BNDES injects equity into JBS, Marfrig, BRF, Oi, Eike Batista's EBX group; aggregate equity stakes via BNDESPAR rise sharply.
- 2008-05-12: **PDP** (Política de Desenvolvimento Produtivo) announced. 25 priority sectors organized into "Strengthening Competitiveness" (12 sectors), "Consolidate and Expand Leadership" (7 strategic complexes including bioethanol, oil-and-gas, aeronautical, mining, steel, cellulose, meat), and other strategic categories. BNDES committed R$ 210.4 billion of project financing through 2011.
- 2008–2009 financial crisis: BNDES used as the principal counter-cyclical instrument. Treasury on-lending begins at scale (R$ 100+ billion in 2009 alone).
- 2009: **PSI launched.** Below-TJLP fixed rates (initially 4.5–6.75% p.a.) on capital-goods FINAME and innovation projects. PSI is the single largest discretionary subsidy of the period; it explains the 2009–2014 bulge in industrial disbursements. R$ 455 billion of public-bond injections support PSI through its life cycle.
- 2010: Disbursements peak at R$ 168 billion (R$ 144 billion excluding the Petrobras capitalization). Industry 47%, infrastructure 31%, services 16%. MPME share: R$ 45.7 billion (~27%).

**2011–2014 (Dilma 1 — Plano Brasil Maior).**
- 2011-08: **Plano Brasil Maior** announced. Five strategic production-system blocks; 19 sectoral committees. Block 1 (Mechanical, Electro-Electronic, and Health Systems) absorbs ~55% of BNDES PBM-related disbursements in 2011. PBM-aligned operations represent 86% of total BNDES disbursements that year. Knowledge-intensive sectors (high/medium-high tech) receive 62% of disbursements.
- BNDES P&G (oil-and-gas suppliers), Progeren (working capital), Profarma renewals, Climate Fund disbursements all expanded. Spreads on innovation/environment/sanitation projects cut from 1.7% to 0.9%.
- PSI continues, generating annual subsidy expenditures at the Treasury that, by some estimates, will continue through 2041.
- 2013-2014: Disbursements plateau around R$ 188-190 billion. MPME share rises to 43% of disbursements by 2014 (R$ 80+ billion).

**2015–2016 (Dilma 2 → Temer transition — the contraction).**
- 2015-01: Joaquim Levy as Finance Minister begins fiscal retrenchment. BNDES disbursements start to contract.
- 2015: BNDESPAR begins the divestiture of national-champion equity stakes (Marfrig sale begun mid-2015).
- 2016-08: Dilma impeached, Temer presidency begins. Fiscal-tightening mandate accelerated.
- 2016-12: PSI formally ends (last contracts grandfathered).
- 2016-12 to 2018-08: Temer government schedules **R$ 280 billion early repayment** of Treasury loans by BNDES; the bank's lending capacity is structurally cut.

**2017 (Temer-Goldfajn).**
- 2017-08: Congress approves the **TLP** (Taxa de Longo Prazo), replacing TJLP from 2018-01-01. New BNDES contracts are indexed to a 5-year IPCA-linked Treasury curve, eliminating the implicit Treasury subsidy on the marginal new loan (Lei 13.483/2017).
- BNDES disbursements collapse to ~R$ 70-75 billion in 2017, less than half the 2014 peak. Sector mix tilts toward infrastructure (legacy mandate).
- The post-2015 contraction is the *opposite* of the political-alignment logic for the period 2002–2014: the same bank, structurally, but with allocative leverage gutted. This matters for the paper's identification: the 2015–2017 sub-period is essentially the placebo of the alignment instrument at the federal level.

**Operational implication for the paper.** The within-muni × time variation that A2 will look for must respect this regime structure. Margins that "work" only during 2009–2014 (PSI eligibility, sector-specific programs at peak) will look mechanical if the variance decomposition is run on the full 2002–2017 panel without subsample diagnostics. We should (i) report the variance decomposition for the full panel and (ii) report a 2002–2014 / 2015–2017 split to verify that the "active" margin survives the contraction.

---

## §4. Geographic priority rules and their evolution

Despite recurring rhetorical attention to regional imbalance, BNDES does **not** operate a strong systematic geographic-priority rule that overrides sector and size logic. The evidence:

**(a) Stated rules.** PDP 2008 nominated "Regionalização" as one of six strategic areas, but the operational manifestation was modest: differentiated spreads of order 0.1–0.3 percentage points on certain projects in the North, Northeast, and Centro-Oeste, and a directive to channel more indirect lending through regional development banks (Banco do Nordeste, BNB; Banco da Amazônia, BASA). PBM 2011 mentions regional balance as a goal but does not assign quantitative regional targets.

**(b) Empirical distribution.** Annibelli & Souza (2021), using BNDES indirect-lending data 2007–2016, find that the bank's *coverage* (share of municipalities served) is "virtually nationwide" — fewer than 1% of municipalities have no indirect-lending presence — but the **intensity** in the North and Northeast is systematically lower than in the South and Southeast. Their interpretation: the geographic distribution follows productive capacity, not redistributive intent. Lazzarini-Musacchio (2015) find a similar pattern at the firm level: state and regional fixed effects absorb most of the cross-firm variation in receiving BNDES support, but conditional on firm size and sector, region adds little explanatory power.

**(c) Constitutional carve-outs.** The Constitutional Funds (FCO, FNE, FNO) are *separate* from BNDES and do operate explicit regional preferences. They are administered by BB, BNB, and BASA respectively. BNDES does not control them. For our paper, this means regional-specific funding exists in Brazil but does not flow through BNDES — so it should not appear in our BNDES-loan dataset, and any regional first-stage variation we observe in BNDES is *despite* the Constitutional Funds, not because of them.

**Verdict.** Region/state should be treated as a *conditioning variable* in the muni-level regression (state fixed effects, or region trends), not as an aggregation margin for the shift-share IV. Aggregating the alignment shock by state-level shares would project on a dimension that BNDES does not actively use, and the first stage will be weak by construction. This is the F0–F1 logic applied to the geographic case.

---

## §5. Programs and lines of credit

The table below catalogs BNDES's main product lines and named programs active during 2002–2017, with sector targets, indicative volumes (where reported in annual reports), and time period. The list is not exhaustive — BNDES launched and retired many small programs — but it covers all the lines that materially moved aggregate disbursements.

| Program / line | Type | Sector / target | Period | Indicative volume / share | Notes |
|---|---|---|---|---|---|
| **FINEM** (Financiamento a Empreendimentos) | Direct | All sectors; projects ≥ R$ 10 mn (later thresholds vary) | 1953–present | Backbone of direct operations; ~30–45% of disbursements | The classic project-finance instrument |
| **FINAME** (Agência Especial de Financiamento Industrial) | Indirect (subsidiary) | Capital goods, machinery, equipment of national manufacture | 1964–present | ~25–30% of disbursements (peak 35%+ during PSI) | Goes through accredited banks; eligible equipment must be on the CFI registry |
| **FINAME Agrícola / Moderfrota / PRONAF** (transferred to BNDES at various times) | Indirect | Agricultural machinery, family farming | Various; PRONAF 1996–present | Modest direct share but high political salience | Some agricultural lines are administered by BB / Banco do Brasil with BNDES funding |
| **BNDES Automático** | Indirect | Investment projects up to R$ 20 mn (limit varies by period) | 1965–present | ~10–15% of disbursements | Smaller projects through commercial-bank intermediaries |
| **Cartão BNDES** | Indirect | MSME; pre-approved revolving credit up to R$ 2 mn per issuing bank | 2003–present | R$ 1 bn (2005) → R$ 11.5 bn (2014, 800k operations) | Exclusively MSME; durable goods and inputs from accredited suppliers |
| **BNDES Exim Pre-Shipment** | Direct/indirect | Manufacturers exporting Brazilian goods; production phase | 1990s–present | ~5–8% of disbursements | Fixed rate TJFPE set quarterly |
| **BNDES Exim Post-Shipment** | Direct | Buyers of Brazilian exports; up to 15-year tenor | 1990s–present | Varies | Heavily used by aircraft and capital-goods exporters |
| **BNDES Exim Automatic** | Indirect | Post-shipment up to USD 10 mn | Various | Small | Through accredited foreign and domestic banks |
| **BNDES Crédito Pequenas Empresas / MPME** | Indirect | MSME working capital and investment | Various (consolidated 2010s) | Component of MPME aggregate, ~20–25% by 2014 | Bundled with FGI guarantee fund |
| **PSI (Programa de Sustentação do Investimento)** | Indirect (FINAME-PSI) and direct subprograms | Capital goods, innovation, exports; firms of all sizes with rate differentials by size and region | 2009-07 to 2016-12 | R$ 455 bn cumulative; up to ~30% of disbursements at peak | Below-TJLP fixed rates (initially 4.5–6.75% p.a.); largest discretionary subsidy of the period |
| **Profarma** (Apoio ao Complexo Industrial da Saúde) | Direct/indirect | Pharmaceuticals, biotech, health products | 2004–present (renewed 2007, 2013, …) | Single-digit % of disbursements but high strategic weight | Subprograms: biotechnology, innovation, production, M&A |
| **Prosoft** (Software e Serviços de TI) | Direct/indirect | Software and IT-services firms | 1997–present (renewed) | Small share of disbursements; targeted high-tech | Eligible CNAE list keyed to software and TI |
| **Procult** (Economia da Cultura) | Direct/indirect | Cultural-economy production chains | 2006–present | Very small share | Cultural goods, audiovisual, publishing |
| **BNDES P&G** (Petróleo e Gás) | Direct/indirect | Oil-and-gas equipment and services suppliers | 2009–present | Material in PBM years | Built around Petrobras procurement chain |
| **Progeren** (Programa de Apoio ao Fortalecimento da Capacidade de Geração de Emprego e Renda) | Indirect | Working capital, MSME-tilted | Launched 2008; expanded 2011 (R$ +7 bn) and 2015 | Counter-cyclical | Used as anti-recession instrument |
| **Climate Fund (Fundo Clima)** | Direct/indirect | Emissions reduction, renewables, sustainable industry | 2010–present | Small initially, growing | PBM-era addition; sector programs by environmental theme |
| **Inova series** (Inova Empresa, Inova Saúde, Inova Petro, Inova Energia, Inova Aerodefesa, Inova Agro, …) | Direct/indirect, joint with FINEP | Innovation projects in named sectors | 2013–2016 | R$ 30+ bn aggregate target | Sector-specific innovation calls; explicit sector × innovation cells |
| **National-champions equity** (BNDESPAR) | Equity | Listed firms, mostly large-cap | 2007–2015 (active accumulation); 2015– (divestiture) | Stock value ~R$ 100+ bn at peak | Not a credit line; relevant for the political-alignment instrument because the same federal principal selects equity targets |

**Reading of the table.** The program catalog informs the choice of aggregation margin without itself being one. Three observations:

1. **The catalog points at which sector × size cells matter.** Cartão BNDES is MSME-only → small-firm cells in industrial CNAEs are an active cell. Profarma is pharma-only → pharma CNAE × any-size is active. PSI is capital-goods buyers, 2009–2016 → manufacturing × medium-and-large during that window is active. The catalog is a *guide* to which CNAE × size_bin cells we expect to load most of the alignment-driven credit reallocation.
2. **The catalog is not itself an aggregation margin.** Product-line and PSI-eligibility are loan-side or purpose-side classifications (see §2(b)). For non-borrowers — the bulk of the RAIS universe — these classifications are undefined. The aggregation margin must be a firm-side classifier defined for everyone; the catalog tells us which firm-side cells the loan-side classifier targets.
3. **Program timing constrains the time window.** PSI exists 2009-07 to 2016-12; PBM is 2011-08 to 2014-12; Inova-series is 2013–2016. If the CNAE × size_bin diagnostic in A2 uses pooled within-muni × time variation across 2002–2017, the alignment-driven variation that loads most heavily during 2009–2014 will be diluted by the calmer 2002–2008 and 2015–2017 sub-periods. Report the variance decomposition both pooled and 2009–2014.

---

## §6. Recommended candidate margins for A2

The candidate set is the intersection of (i) the dimensions BNDES uses, per §2(a), and (ii) admissibility as a firm-side classifier defined for the entire RAIS universe, per §2(b). Combined with the data inventory in `docs/PROJECT_BLUEPRINT.md`, this yields a much narrower roster than a "everything BNDES uses internally" reading would suggest.

### Active candidate set for A2 round 1

These are the margins to actually run the variance decomposition on:

| Margin | Construction | Why |
|---|---|---|
| **`cnae_section`** (21 sections) | Already in `data/processed/rais_bndes_reconstructed.fst`. | Current default; finest sector taxonomy already wired through. |
| **`bndes_macro_sector`** (4 macros: Agro, Ind, Infra, Serv) | Already in panel. | Coarser sector taxonomy; matches BNDES departmental backbone (§1). |
| **`custom_block`** (11 blocks) | Already in panel. | Intermediate granularity; useful for comparison. |
| **`size_bin`** (standalone; absolute thresholds MPME 0–49 / Média 50–499 / Grande 500+) | New from A1. Constructed from `n_employees` using cutoffs that approximate BNDES porte categories. | Captures the size-targeting logic as a standalone margin (Cartão BNDES is MSME-only; PSI Tier 1 offered lower rates to small firms). Admissible because `n_employees` is defined for every firm in RAIS. |
| **`cnae_section × size_bin`** (interaction; same absolute thresholds) | New from A1. Constructed from `cnae_section × n_employees`. | Finer cells capturing both sector and size targeting simultaneously. |

**Note on absolute thresholds vs. tertiles.** BNDES classifies firms by observable, absolute revenue cutoffs (porte: ME/EPP/Médias/Grandes), not by relative within-sector position. Using absolute `n_employees` thresholds (MPME 0–49 / Média 50–499 / Grande 500+) as a proxy for revenue-based porte is institutionally grounded. Within-sector tertiles are a valid robustness option — they adapt to sector-specific size distributions and avoid conflating small-in-manufacturing with small-in-pharma — but they are less aligned with how BNDES actually decides. D16 uses the A3 absolute-threshold scheme as F1 diagnostic evidence; D28 defers the production-margin commitment.

### Acknowledged but not actively pursued

These margins are admissible but not on the A2 round 1 critical path. They are listed for completeness and as fallbacks if the active set fails F1.

| Margin | Status |
|---|---|
| **CNAE-list crosswalks for industrial-policy bins** (PBM Block 1–5 active 2011-08 to 2014-12; Profarma-CNAE; Prosoft-CNAE; P&G-supplier-CNAE) | Admissible as coarsenings of `cnae_section × year`. **Not promising** — each is essentially a re-bucketing of CNAE that the active set already tests directly. Mention only; do not build a dedicated A2 round for them. |
| **Export orientation** | Admissible only conditional on a RAIS-export or SECEX merge. Not in the current panel. **Defer.** |

### Inadmissible (catalogued for clarity)

- **Product line** (FINEM, FINAME, Cartão, Automático, Exim, named programs). Loan-side classifier; undefined for non-borrowers. **Cannot be an aggregation margin.** Use only to motivate which sector × size cells matter.
- **PSI eligibility**. Defined by the *purpose* of the loan (eligible capital-goods purchase), not by firm CNAE. Not a firm-side classifier. **Cannot be an aggregation margin.**
- **Direct vs. indirect operations**. Delivery channel, not an allocation dimension at all. The paper uses firm-CNAE throughout (the firm-level channel is validated by P1); whether BNDES delivers a given loan directly or through an intermediary is institutional context, not a design choice.

### Used as control, not as aggregation margin

- **Region / state.** §4 establishes that BNDES does not operationally allocate on this dimension. Absorbed via state × year fixed effects or meso-region trends in the muni-level regression.

### A2 round 1 plan

Run the variance decomposition $\sigma^2_{\text{total}} = \sigma^2_{\text{between-muni}} + \sigma^2_{\text{within-muni-between-year}} + \sigma^2_{\text{within-muni-year}}$ on the four active margins listed above. Report median and p10/p90 of within-muni σ across munis, by margin, both for the pooled 2002–2017 panel and for the 2009–2014 sub-panel (the PSI/PBM-active window). Diagnostic plot: distribution of within-muni share volatility per margin.

**A2 stop rule.** If no margin in the active set yields meaningful within-muni × time variation (operationalize: median within-muni σ > 0.05 in normalized share units, with at least 200 munis showing σ > 0.10), F1 fails on the firm-side admissible margins. Before re-thinking the design, run a small follow-up on the CNAE-list crosswalks (PBM Block 1–5 × year on 2011–2014; Profarma-CNAE × year on 2004–2017) to confirm that the industrial-policy coarsening also fails. If both sets fail, the design needs to be re-thought before any further code work — per the blueprint's "if F1 fails on every margin → stop everything else" rule.

---

## §7. Bibliography

**Academic literature.**

- Annibelli, M.B., & Souza, M.A. (2021). "Lending and regional growth in Brazil: the development bank BNDES versus private and public banks." *Estudos Econômicos* (SciELO Brazil). [Documents BNDES indirect-lending coverage and intensity by region 2007–2016.]
- Bonomo, M., Brito, R.D., & Martins, B. (2015). "The after crisis government-driven credit expansion in Brazil: A firm level analysis." *Journal of International Money and Finance* 55, 111–134. [Shows that larger, older, and less-risky firms benefited most from the post-crisis BNDES expansion. Firm-level panel ~1 mn firms 2004–2012.]
- Carvalho, D.R. (2014). "The Real Effects of Government-Owned Banks: Evidence from an Emerging Market." *The Journal of Finance* 69(2), 577–609. [Shows BNDES disbursements are higher for states governed by political allies of the federal incumbent in years near gubernatorial reelections — direct precedent for the alignment-instrument logic.]
- Cavalcanti, T., & Vaz, P. (2017). "Access to long-term credit and productivity of small and medium firms: A causal evidence." *Economics Letters* 150, 21–25. [Positive productivity effects on SMEs from a permanent expansion of BNDES access.]
- Coelho, C., De Mello, J.M.P., & Funchal, B. (2013). "The Brazilian payroll lending experiment." *Review of Economics and Statistics* 95(3), 845–856. [Used as a complementary methodological reference.]
- Lazzarini, S.G., Musacchio, A., Bandeira-de-Mello, R., & Marcon, R. (2015). "What Do State-Owned Development Banks Do? Evidence from BNDES, 2002–09." *World Development* 66, 237–253. [Core institutional reference. Documents that BNDES does not systematically lend to underperforming firms, that political connections (via campaign donations) predict access, and that subsidies — not project finance per se — drive most of the bank's effect.]
- Musacchio, A., & Lazzarini, S.G. (2014). *Reinventing State Capitalism: Leviathan in Business, Brazil and Beyond*. Harvard University Press. [Book-length treatment. Chapter 5 covers BNDES governance and its 2007 elevation to ministerial status. Chapter 7 documents the national-champions strategy.]
- Sant'Anna, A.A., & Borça Junior, G.R. (various years). BNDES Discussion Papers / *Visão do Desenvolvimento*. [Series of internal-research notes on PSI, TJLP, and the bank's funding structure. Cited across the timeline of §3.]

**Government documents and primary sources.**

- Brazil. Ministério do Desenvolvimento, Indústria e Comércio (2008). *Política de Desenvolvimento Produtivo (PDP)*. Announced 2008-05-12. [25 priority sectors organized into "Strengthening Competitiveness," "Consolidate and Expand Leadership," and other strategic categories. R$ 210.4 bn of BNDES financing committed through 2011.]
- Brazil. Casa Civil (2011). *Plano Brasil Maior 2011–2014*. Announced 2011-08. [Five strategic production-system blocks; 19 sectoral committees; CNDI as governance body. BNDES participation in every committee.]
- Brazil. Lei nº 13.483/2017 (2017-09-21). [Creates the TLP, replacing TJLP from 2018-01-01.]
- BNDES. *Annual Reports / Relatórios Anuais* 2002–2017. Available at bndes.gov.br. [Cited for sector composition, MSME share, program volumes by year. Key: 2010, 2011, 2013, 2014, 2017.]
- BNDES. *Boletim Setorial* (sector bulletins, various years).
- BNDES Investor Relations. "Governance Structure" and "Bylaws / Estatuto Social." Available at ri.bndes.gov.br. [Used for §1 governance section.]

**Operational references on the bank's products.**

- BNDES. "BNDES Finem," "BNDES Finame," "Cartão BNDES," "BNDES Automático," "BNDES Exim Pre-Shipment / Post-Shipment / Automatic" — product pages on bndes.gov.br/wps/portal/site/home/financiamento/.
- BNDES. "Profarma — Programa de Apoio ao Desenvolvimento do Complexo Industrial da Saúde."
- BNDES. "Prosoft — Programa para o Desenvolvimento da Indústria Nacional de Software."
- BNDES. "Procult — Programa para o Desenvolvimento da Economia da Cultura."
- BNDES. "BNDES PSI" institutional pages (archived; program ended 2016-12).

**Web / news on national champions and political controversy.**

- "With Sale of Marfrig Shares, BNDES Starts to Wean 'National Champions'" (2015). *Rio Times*. [Documents 2015 divestiture turn.]
- "BNDES Speaks Out: giant Brazilian bank offers rare in-depth interview" (2016). *Mongabay News*. [Used for §3 timeline detail on the Temer transition.]
- "Subsídios do Tesouro a programa do BNDES somaram R$ 22 bilhões em 2017" (2018). *Agência Brasil*. [Used for the post-PSI Treasury-subsidy figure.]

---

## Appendix. Verdict against F0 and consequences for the rest of the chain

Restating the F-link from `docs/PROJECT_BLUEPRINT.md` §3:

> **F0** — BNDES allocates credit across one or more recognizable margins (sector, firm size, export orientation, product line, …) that we can use as the aggregation dimension for the muni-level shock.

**Verdict: F0 is satisfied, but the answer is more constrained than a naive reading suggests.** BNDES actively uses six dimensions to allocate credit (§2(a)). However, only a subset of these are admissible as muni-level aggregation margins — a margin must be a *firm-side classifier* defined for the entire RAIS universe, not a *loan-side* property observed only conditional on borrowing (§2(b)). The admissible active set is **CNAE (3 taxonomies) + standalone `size_bin` + `CNAE × size_bin`**, all using absolute thresholds (MPME / Média / Grande) that approximate BNDES porte categories. Product line and PSI eligibility — both of which BNDES uses heavily — are inadmissible.

**Consequence for F1.** A2 expands the candidate set by **two genuinely new margins**: standalone `size_bin` and the `cnae_section × size_bin` interaction, both firm-side classifiers built from `n_employees` with absolute thresholds. The other "new" candidates considered in early drafts (`bndes_product`, PSI-eligibility) drop out on admissibility grounds. F1 is therefore a sharper test than initially framed: the within-muni × time variation must show up on the CNAE side or on the CNAE × size cell side, not on the loan-side classification we cannot use.

**Consequence for F3 (exclusion restriction).** §3 of this memo provides the institutional context for why the alignment shock is plausibly exogenous to *muni* economic shocks even though it is endogenous to the *federal* policy stance. The federal principal sets PDP/PBM priorities and chooses BNDES leadership; the realized turnover at the municipal-owner level (the variation that drives the shift-share) is a function of micro-level political dynamics that are not the proximate cause of muni-level economic shocks. The memo's Section 1 makes this concrete by documenting that the bank's organizational backbone (sectoral departments, named programs) is the *channel* through which alignment translates into volume — which is what the SSIV needs.

**Consequence for F2 (measurement consistency).** F2 has been retired from the identification chain (D18, 2026-05-05). It was a design choice, not an empirical foundation: the paper uses firm-CNAE (RAIS) as the aggregation classifier throughout, because the firm-level channel is the validated mechanism (P1) and firm-CNAE is the only classifier defined for the non-borrower majority of the RAIS universe. Project-CNAE (BNDES-side) is observed only for borrowers and is not used. A6 (the planned firm-CNAE / project-CNAE cross-tab) remains as an optional descriptive exercise about how BNDES labels its book — informative for the institutional narrative — rather than a measurement-error question that could shift the choice of margin.

---

*End of memo.*
