---
status: COMPLETED (commit hash appended in §10 below)
date: 2026-05-13
meeting: 2026-05-14
author: assistant + user
purpose: Execute the updated AR-test results for the upcoming meeting.
spec anchors:
  - docs/methodology/ar_test_specification.tex §2.3 (sector-level exposure weights, Variant A primary)
  - docs/strategy/office_specific_exposure_weights.md §3.2 (Variant F pre-earliest window)
  - docs/PROJECT_BLUEPRINT.md §Current Method State + §Production Margin Status
slide target format:
  - explorations/anderson_rubin/a10_composition_volume/output/slides.tex (existing reference)
---

# Plan — Updated AR-test results for the meeting

## 1. Goal

Produce two parallel Beamer slide pairs (one per taxonomy) that report the
Anderson-Rubin test of `H_0: beta = 0` on sector employment shares,
constructed under the **updated instrument convention** the user requested:

1. Channel-specific **pre-earliest-election** baseline window
   (Variant F of `office_specific_exposure_weights.md`).
2. **Variant A** sector-level exposure weights from
   `ar_test_specification.tex` §2.3 — muni-relative aligned-owner share
   (within-municipality normalization, owner-count weights inside the cell).
3. **Frozen support** for the baseline-exposure firm set; **contemporaneous**
   firms for the outcome panel (sector employment shares and log GDP).
4. **RAIS universe** as the firm support.

For each of two endogenous taxonomies — **policy_block** (K=4) and the
**3-size firm-size variable S3** (MPME, Média, Grande, K=3) — we run the
AR test in four control variants:

| Spec | Outcome reg. | Controls beyond muni + year FE |
|---|---|---|
| (1) No controls | `log GDP ~ Z's` | none |
| (2) + EC | `log GDP ~ Z's + EC_j` | per-cell exposure control (J-1 controls) |
| (3) + Vol | `log GDP ~ Z's + Vol` | volume control `bndes_total / initial_gdp_2002` |
| (4) + Vol + EC | `log GDP ~ Z's + Vol + EC_j` | both |

Four channels enter as separate row tests, each row using only that
channel's stacked sector instruments:

- **M** — pure mayoral channel
- **M·P** — mayor × president cross-office
- **M·G** — mayor × governor cross-office
- **M·G·P** — mayor × governor × president cross-office

Total regressions: 4 channels × 4 control specs × 2 taxonomies = **32**.

## 2. Decisions locked in (this session)

| # | Decision | Source |
|---|---|---|
| L1 | Two **parallel slide pairs**: policy_block and S3 (3-size). Not crossed. | User Q1, 2026-05-13 |
| L2 | Outcome panel = **contemporaneous** sector employment shares (existing `emp_share_panel_<sector>.qs2` contemporaneous variant). "Frozen support" refers to baseline-exposure firm set only, not the outcome panel. | User Q2 |
| L3 | EC = per-cell `sum_p w^{c,A}_{jmp,t}` from Variant A, entered as **J-1 sector controls** at the muni regression (hold-out matches the Z hold-out). No additional muni-level scalar political-mass control in primary; that is a robustness only. | User Q3 + spec §2.3 line 817-829 |
| L4 | Slide 2 layout per taxonomy: **2 sub-tables per slide**, 2 slides → 4 channels across two coefficient slides. | User Q4 |
| L5 | Channels = {M, M·P, M·G, M·G·P}. No standalone Governor or President channels (those are absorbed into year FE or state FE in the muni regression — see spec §Inference). | Spec §1.1 cross-office, §Inference para "Concern" |
| L6 | FE = muni + year. SE = one-way cluster on muni_id. | Spec §Controls and §Inference primary clustering |
| L7 | Volume control = `total_bndes_real / initial_gdp_{m,2002}`. | Spec eq:vol-explicit |
| L8 | Hold-out sector for each taxonomy: drop the largest-mean-share sector to keep the unit-norm reference (matches existing `02_ar_test_emp_share.R`). | Existing convention |
| L9 | Meeting subfolder: `journal/meetings/2026-05-14/`. | User, 2026-05-13 |
| L10 | Size-bin taxonomy variable in code: `size_bin` (3 levels: MPME / Média / Grande) from `30c_build_size_bin_mapping.R`. | User, 2026-05-13 |
| L11 | Stars on the F-stat slide: working-paper default `*` p<0.10, `**` p<0.05, `***` p<0.01. | User, 2026-05-13 |
| L12 | Deck title: "Updated AR Test Results". Date in body of first slide. No subtitle. | User, 2026-05-13 |

## 3. Deferred / robustness for later (not in meeting slides)

- Mayoral-window exposure (Variant A timing in the memo) — robustness ask.
- Variant B (employment-mass) and intensity-only weights — robustness ask.
- Muni-level `log bar L^{c,affil}_{m,t}` political-mass scalar — robustness.
- `policy_block × S3` crossed taxonomy (D28 deferred).
- AKM shock-level SEs.

## 4. Existing assets to reuse

```
data/processed/
  policy_block_mapping.qs2                         (script 30e)
  size_bin_mapping.qs2                             (script 30c — 3-size firm-size)
  firm_panel_for_regs.qs2                          (firm-year panel with employment)
  alignment_shocks.qs2                             (Align^{M}, Align^{P}, Align^{G}, and channel composites)
  owner_aff_standardized.qs2                       (owner-party affiliation primitives)
  emp_share_panel_policy_block.qs2                 (contemporaneous outcome panel, K=4)
  emp_share_panel_cnae_section.qs2                 (contemporaneous outcome panel, cnae)
  muni_panel_for_regs.qs2, muni_panel_for_regs_policy_block.qs2  (muni-year GDP panel)

scripts/R/3_instruments/
  30c (size-bin), 30e (policy_block), 31 (current within-cell intensity weights — REPLACED for this run),
  32 (alignment), 32c (emp_share_panel builder), 34 (shift-share assembly)

explorations/anderson_rubin/active_denominator/R/
  02_ar_test_emp_share.R                           (existing AR runner — template for the new runner)
```

## 5. Implementation phases

### Phase A — Variant A weight + instrument build (new exploration scripts)

Branch: `explorations/anderson_rubin/ar_meeting_2026_05_13/`

Structure:
```
explorations/anderson_rubin/ar_meeting_2026_05_13/
  README.md
  SESSION_LOG.md
  R/
    00_helpers.R                  helper functions (channel windows, taxonomy switches)
    01_build_variant_a_weights.R  build w_tilde^{c,own}_{jmp,t} for all 4 channels x both taxonomies
    02_build_instruments_ec.R     stack into Z^{c}_{jmt} and per-cell EC_jmt
    03_build_muni_ar_panel.R      merge Z's + EC + log GDP + volume control into muni-year panel
    04_run_ar_regressions.R       loop over 4 channels x 4 specs x 2 taxonomies, save CSV + tex
    05_build_slides.R             emit Beamer .tex per taxonomy
  output/
    weights_variant_a_<tax>.qs2
    Z_variant_a_<tax>.qs2
    EC_variant_a_<tax>.qs2
    muni_panel_ar_<tax>.qs2
    ar_summary_<tax>.csv
    ar_table_fstats_<tax>.tex
    ar_table_coefs_<tax>_pair1.tex   (channels M, M.P)
    ar_table_coefs_<tax>_pair2.tex   (channels M.G, M.G.P)
```

#### A.1 Pre-earliest election windows (Variant F)

For each year t in 2002..2017, define for each channel c:
```
e_{F,M}(t)   = e_M(t)              (most recent mayoral election <= t)
e_{F,MP}(t)  = min(e_M(t), e_P(t))
e_{F,MG}(t)  = min(e_M(t), e_G(t))
e_{F,MGP}(t) = min(e_M(t), e_G(t), e_P(t))
T^{F,c}_t    = [e_{F,c}(t) - 4, e_{F,c}(t) - 1] cap [2002, 2017]
```
Reference table in `office_specific_exposure_weights.md` §3.2.

In Brazil: mayoral elections 2000, 2004, 2008, 2012, 2016;
gubernatorial/presidential elections 2002, 2006, 2010, 2014.
`e_M(2002) = 2000` (out of sample → window 1996..1999 intersected with
[2002,2017] is empty; flag and use 2002 itself as the earliest available
year; document as a corner case for early-sample munis).

#### A.2 Variant A weights (eq:w-own-rel)

For each (channel c, taxonomy `tax in {policy_block, S3}`, cycle t):

```
bar L^c_{jmp,t}        = sum_{s in T^{F,c}_t} sum_{f in F(j,m)} L_{f,p,s}
bar L^{c,affil}_{m,t}  = sum_{j'} sum_{p'} bar L^c_{j'mp',t}

w_tilde^{c,own}_{jmp,t} = bar L^c_{jmp,t} / bar L^{c,affil}_{m,t}
```
Firm support `F(j,m)`: all firms appearing in RAIS during `T^{F,c}_t`
with non-missing owner-party affiliations and a valid `tax` assignment.
This is the frozen support.

`L_{f,p,s}` = number of owners of firm f affiliated with party p in year s
(`owner_aff_standardized.qs2`).

#### A.3 Sector-level instrument and per-cell EC

```
Z^{c}_{jmt}              = sum_p w_tilde^{c,own}_{jmp,t} * Align^{c}_{mpt}
widetilde_EC^{c}_{jm,t}  = sum_p w_tilde^{c,own}_{jmp,t}      (sum_j over j = 1; drop hold-out)
```
For c in {M, MP, MG, MGP}. Align is loaded from `alignment_shocks.qs2`.

### Phase B — Muni AR panel

Outcome: `log_gdp_mt`, plus `log(pib_real)`.
Volume: `vol_ratio_mt = total_bndes_real_mt / pib_real_{m, 2002}`.
Sector employment shares for s_jmt enter only as the structural endogenous
in interpretation — the AR test does **not** include s_jmt on the RHS; it is
the reduced form on log GDP. The shares are used downstream to verify
hold-out choice.

Per-sector EC: J columns, drop hold-out sector. Same hold-out used for Z's.

Joining keys: `(muni_id, year)`. Drop muni-years missing any of:
log_gdp, pib_real (for 2002 anchor), Z's for the chosen channel.

### Phase C — Run the 32 regressions

For each `(tax, channel, spec) in {policy_block, S3} x {M, MP, MG, MGP} x {(1), (2), (3), (4)}`:

```r
# Build formula
rhs <- c(z_cols[channel])
if (spec %in% c("ec","vol_ec")) rhs <- c(rhs, ec_cols[channel])
if (spec %in% c("vol","vol_ec")) rhs <- c(rhs, "vol_ratio")
fml <- as.formula(paste0("log_gdp ~ ", paste(rhs, collapse = " + "), " | muni_id + year"))
mod <- fixest::feols(fml, data = muni_panel, vcov = ~ muni_id, lean = TRUE)

# AR statistic: cluster-robust joint Wald F on the Z's only
w <- fixest::wald(mod, keep = paste0("^Z_", channel, "_"))
ar_F <- w$stat ; ar_p <- w$p
```

Save:
- `output/ar_summary_<tax>.csv` — one row per (channel, spec, tax) with
  `channel, spec, tax, n_obs, n_munis, K_Z, K_collin, ar_F, ar_p,
   vol_coef, vol_se, ec_drop_sec, ar_reject_5pc`.
- Per-cell coefficient tables for all 16 cells, for use in slide 2.

### Phase D — Slides

Per taxonomy, 3 slides:

**Slide 1 — Joint F (rows = channels, columns = specs).**

```
\begin{tabular}{@{}lcccc@{}}
\toprule
Channel & No controls & + EC & + Vol & + Vol + EC \\
\midrule
M       & F [p] & F [p] & F [p] & F [p] \\
M.P     & F [p] & F [p] & F [p] & F [p] \\
M.G     & F [p] & F [p] & F [p] & F [p] \\
M.G.P   & F [p] & F [p] & F [p] & F [p] \\
\bottomrule
\end{tabular}
```
Stars on F via the AR p-value. Footer note: cluster-robust AR Wald
joint F; "[p]" is the p-value; 5% rejection ≡ p < 0.05.

**Slides 2a / 2b — Coefficients.**

Two sub-tables per slide, 2 channels per slide:

- 2a: panel for channel M, panel for channel M·P
- 2b: panel for channel M·G, panel for channel M·G·P

Each panel:
```
              No controls   + EC   + Vol   + Vol + EC
Sector 1       coef[stars]   ...    ...      ...
...
Sector K-1     coef[stars]   ...    ...      ...
Volume                        --   coef     coef
EC summary*    --            coef   --       coef
```
For the "EC summary" row we report the **average across J-1 EC controls**
of the coefficient (or the median absolute coef) — full per-sector EC
coefs are too dense for a slide. Footer note explains. Per-sector EC
coefficients are in the CSV for the appendix.

Two parallel taxonomies → **6 substantive slides**. Title, setup, and
bottom-line slides = 3 more. **Total ~9 slides.**

Beamer source mirrors `a10_composition_volume/output/slides.tex`:
- aspectratio=169, 11pt
- palatino font, T1 fontenc
- booktabs, microtype, makecell
- footer page number only, no nav symbols
- `\resizebox{\textwidth}{!}{...}` for the wide tables

### Phase E — Verification

1. Compile slides: `xelatex -interaction=nonstopmode slides.tex` from the
   meeting subfolder (`journal/meetings/2026-05-??/` — date TBD by user).
2. Cross-check: AR F shown in the tex F-stat table matches the value in
   `ar_summary_<tax>.csv` for every cell.
3. Sanity diagnostic: first-stage joint F under M·G·P channel for each
   taxonomy (reuse `run_first_stage_joint_F()` from `02_ar_test_emp_share.R`).
4. Append session log entry to `journal/sessions/2026-05-13_ar_meeting_update.md`.
5. Append journal entry to `journal/research_journal.md` with the F results.

## 6. Commands

```bash
# Phase A
Rscript explorations/anderson_rubin/ar_meeting_2026_05_13/R/01_build_variant_a_weights.R --tax=policy_block
Rscript explorations/anderson_rubin/ar_meeting_2026_05_13/R/01_build_variant_a_weights.R --tax=size_bin
Rscript explorations/anderson_rubin/ar_meeting_2026_05_13/R/02_build_instruments_ec.R   --tax=policy_block
Rscript explorations/anderson_rubin/ar_meeting_2026_05_13/R/02_build_instruments_ec.R   --tax=size_bin

# Phase B
Rscript explorations/anderson_rubin/ar_meeting_2026_05_13/R/03_build_muni_ar_panel.R   --tax=policy_block
Rscript explorations/anderson_rubin/ar_meeting_2026_05_13/R/03_build_muni_ar_panel.R   --tax=size_bin

# Phase C
Rscript explorations/anderson_rubin/ar_meeting_2026_05_13/R/04_run_ar_regressions.R    --tax=policy_block
Rscript explorations/anderson_rubin/ar_meeting_2026_05_13/R/04_run_ar_regressions.R    --tax=size_bin

# Phase D
Rscript explorations/anderson_rubin/ar_meeting_2026_05_13/R/05_build_slides.R

# Phase E
cd journal/meetings/<meeting-date> && xelatex -interaction=nonstopmode slides.tex
```

## 7. Open items (resolved 2026-05-13)

All five open items closed by user responses on 2026-05-13. See L9–L12 in §2.

## 8. Risk register

- **Variant A weight construction is new code.** The existing production
  weight builder (`31_build_sector_exposure_weights.R`) uses within-cell
  intensity weights. The new exploration branch implements
  eq:w-own-rel from scratch. Critical: the muni-denominator
  `bar L^{c,affil}_{m,t}` is the sum over **all** affiliated owner-years
  across **all** sectors and **all** parties in the muni; not a per-sector
  or per-party normalizer.
- **Pre-earliest window for the M channel collapses to mayoral window**
  (since `O(M) = {M}`). For the 2002–2004 cycle, the mayoral window is
  before 2000 → empty intersection with [2002, 2017]. We will document
  these muni-years as "no baseline available" and decide whether to drop
  or impute with the earliest available year.
- **Cluster-robust AR F under MGP with 12 instruments** in the policy_block
  case (4 channels × 3 sectors after hold-out) is K=3 per channel here, so
  per-channel AR uses 3 instruments — well within standard AR power.
- **S3 taxonomy K=2 after hold-out** — only 2 instruments per channel.
  Power will be lower; flag explicitly in the bottom-line slide.

## 9. Definition of done

- All 32 AR cells populated in both `ar_summary_<tax>.csv` files.
- Six substantive slides + bookends compile to PDF without errors.
- Numbers in tex tables match CSV.
- Journal entry + session log appended.
- Plan status updated from DRAFT to COMPLETED with commit hash.

## 10. Completion record

| Item | Value |
|---|---|
| Status | COMPLETED |
| Completion date | 2026-05-13 |
| PDF | `journal/meetings/2026-05-14/build/slides.pdf` (37,845 bytes, 16 pages) |
| Worker-critic scores | Stage 0 = 92; A1 = 90; A2 = 92; B = 90; C = 88; D = 86 (all >= 80 per exploration-phase quality.md §1) |
| Stage E verifier | PASS (32/32 F-stats in tex match CSV to 3 decimals) |
| Session log | `journal/sessions/2026-05-13_ar_meeting_update.md` |
| Research journal | `journal/research_journal.md` (entry 2026-05-13 22:23 — orchestrator) |
| Commit hash | (recorded by Stage F commit on `main`; see `git log` for hash of "feat(ar-test): updated AR results for 2026-05-14 meeting") |

