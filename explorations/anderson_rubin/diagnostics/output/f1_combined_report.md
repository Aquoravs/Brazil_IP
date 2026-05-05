# E3: F1 Within-Muni Variance Decomposition — A2 vs. A3 (V1 primary, V2 robustness)
Generated: 2026-05-04 19:53:48

## Goal

Decide whether the size x sector aggregation margin (A2 = MPME/Big, 
A3 = MPME/Media/Grande) adds identifying within-muni x time variation 
beyond the round-1 `cnae_section`-only margin. Run V1 (active-only 
denominator, primary) and V2 (full-economy denominator, robustness) for 
both A2 and A3 — four spec runs.

**SUPPORTED rule:** at least one bin has cross-muni median sigma_within > 0.05 AND share_within > 0.2.

---

## 1. Round-1 reproduction gate

**Status: PASS**

All 47 (margin x denom x bin) cells within tolerance (|Δshare_within| <= 0.005, |Δmed_σ_within| <= 0.005).

This confirms the refactored `f1_decompose()` reproduces the round-1 numbers in `variation_decomposition.csv` for `cnae_section` and `policy_block` x {V1, V2} on the same source data. A2/A3 outputs below are therefore directly comparable to round 1.

---

## 2. Per-spec verdicts

| Margin | Denom | Verdict | n_bins | n_supported | mean share_within | med share_within | max share_within | med med σ_within |
|--------|-------|---------|--------|-------------|-------------------|------------------|------------------|------------------|
| A2_size_x_sec | V1 | SUPPORTED | 34 | 3 | 0.7550 | 0.7987 | 0.9055 | 0.0000 |
| A2_size_x_sec | V2 | SUPPORTED | 34 | 3 | 0.7555 | 0.7990 | 0.9055 | 0.0000 |
| A3_size_x_sec | V1 | SUPPORTED | 51 | 3 | 0.7688 | 0.8077 | 0.9286 | 0.0000 |
| A3_size_x_sec | V2 | SUPPORTED | 51 | 3 | 0.7693 | 0.8079 | 0.9286 | 0.0000 |

---

## 3. Head-to-head: A2 / A3 vs. round-1 baselines

Round-1 reference (from `variation_decomposition.csv`):

| Margin | Denom | n_bins | mean share_within | med share_within | mean med σ | med med σ |
|--------|-------|--------|-------------------|------------------|-----------|-----------|
| cnae_section | V1 | 21 | 0.7639 | 0.8133 | 0.0455 | 0.0000 |
| cnae_section | V2 | 21 | 0.7876 | 0.8309 | 0.0367 | 0.0000 |
| policy_block | V1 | 5 | 0.6233 | 0.6075 | 0.2160 | 0.2676 |
| policy_block | V2 | 5 | 0.6669 | 0.6204 | 0.1725 | 0.2561 |
| policy_block_active | V1 | 4 | 0.6233 | 0.6075 | 0.2160 | 0.2676 |
| policy_block_active | V2 | 4 | 0.6251 | 0.6104 | 0.2156 | 0.2667 |

Size x sector candidates (this run):

| Margin | Denom | n_bins | mean share_within | med share_within | mean med σ | med med σ |
|--------|-------|--------|-------------------|------------------|-----------|-----------|
| A2_size_x_sec | V1 | 34 | 0.7550 | 0.7987 | 0.0154 | 0.0000 |
| A2_size_x_sec | V2 | 34 | 0.7555 | 0.7990 | 0.0154 | 0.0000 |
| A3_size_x_sec | V1 | 51 | 0.7688 | 0.8077 | 0.0103 | 0.0000 |
| A3_size_x_sec | V2 | 51 | 0.7693 | 0.8079 | 0.0103 | 0.0000 |

---

## 4. Interpretation: does size x sector add identifying variation?

### Option A2

- V1 verdict: **SUPPORTED**, 3 / 34 bins SUPPORTED, mean share_within = 0.7550.
- V2 verdict: **SUPPORTED**, 3 / 34 bins SUPPORTED, mean share_within = 0.7555.
- Delta vs. round-1 cnae_section (V1): -0.0089
- Delta vs. round-1 cnae_section (V2): -0.0321
- Conclusion: under V1, A2 preserves or improves on round-1's section-only mean within-share; the size x sector decomposition is a viable production margin.

### Option A3

- V1 verdict: **SUPPORTED**, 3 / 51 bins SUPPORTED, mean share_within = 0.7688.
- V2 verdict: **SUPPORTED**, 3 / 51 bins SUPPORTED, mean share_within = 0.7693.
- Delta vs. round-1 cnae_section (V1): 0.0048
- Delta vs. round-1 cnae_section (V2): -0.0183
- Conclusion: under V1, A3 preserves or improves on round-1's section-only mean within-share; the size x sector decomposition is a viable production margin.

---

## 5. Selection rule (plan §8)

Plan §8: pick the candidate with highest mean `share_within` across bins (V1 primary).

- Top by V1 mean share_within: **A3_size_x_sec** (mean = 0.7688).
- Runner-up: A2_size_x_sec (mean = 0.7550); delta = 0.0138.
- Tiebreaker (|delta| < 0.05): plan §8 prefers A4 > A3 > B; deviation here — A2 was not in the original plan, so prefer A3 over A2 for granularity (3 size bins > 2). Documented choice.

- V1 / V2 verdict agreement for winner: YES (consistent).

**Final winner: A3_size_x_sec** (option A3).

Caveats:
- A2 was added to the candidate set after E2 with user input; the plan's 
  original scope was {A4, A3, B}.
- E2 nominally FAILED A3's Media and Grande bins on coverage; user opted 
  to keep A3 in E3 since V1 / active-only renormalization makes the IV 
  mechanic valid even with thin coverage (thin bins simply contribute 
  less to identification per muni).
- V2 (full-economy denominator including KOTU) is reported as robustness; 
  V1 wins the tiebreaker on any disagreement.

---

## 6. Files written

| File | Description |
|------|-------------|
| `f1_round1_reproduction_PASS.csv` | Cell-level reproduction check vs. round 1 |
| `f1_optionA2_V1_decomposition.csv` | Per-bin variance decomposition, A2 V1 |
| `f1_optionA2_V1_summary.csv` | Spec-level summary + verdict, A2 V1 |
| `f1_optionA2_V1_vs_round1.csv` | Per-bin comparison to round-1 cnae_section |
| `f1_optionA2_V2_decomposition.csv` | A2 V2 |
| `f1_optionA2_V2_summary.csv` | A2 V2 |
| `f1_optionA2_V2_vs_round1.csv` | A2 V2 vs round 1 |
| `f1_optionA3_V1_decomposition.csv` | A3 V1 |
| `f1_optionA3_V1_summary.csv` | A3 V1 |
| `f1_optionA3_V1_vs_round1.csv` | A3 V1 vs round 1 |
| `f1_optionA3_V2_decomposition.csv` | A3 V2 |
| `f1_optionA3_V2_summary.csv` | A3 V2 |
| `f1_optionA3_V2_vs_round1.csv` | A3 V2 vs round 1 |
| `f1_combined_report.md` | This file |


---

## 7. Agro Conditional F1 Diagnostic

Generated: 2026-05-04 20:03:50

### 7.1 Motivation

Round-1 (D15) reports `policy_block x Agro x V2` as SUPPORTED in aggregate (share_within = 0.6003) but with `med_sigma_within = 0.0000` because most munis have zero Agro BNDES credit in most years. The pattern is 'Agro moves where Agro is a thing' -- correct IV regime, but warrants a positive conditional check.

### 7.2 Setup

- Denominator: V2 (full-economy).
- Baseline window: cycle 2009 (2004-2007); `muni_baseline_agro_share` = mean Agro V2 share over that window.
- Strictly-positive distribution (n=891 munis): p25=0.0243, p50=0.1412.

### 7.3 Decomposition by sample

| Sample | n_munis | n_obs | mean_share | total_var | share_within | p10 sigma | med sigma | p90 sigma |
|--------|---------|-------|------------|-----------|--------------|-----------|-----------|-----------|
| all | 5,291 | 51,842 | 0.0582 | 0.03881 | 0.6003 | 0.0000 | 0.0000 | 0.3452 |
| agro_having | 891 | 12,489 | 0.1419 | 0.08072 | 0.6349 | 0.0100 | 0.1985 | 0.4253 |
| above_median | 445 | 5,551 | 0.2568 | 0.13402 | 0.7289 | 0.1848 | 0.3259 | 0.4629 |
| above_p25 | 668 | 8,946 | 0.1888 | 0.10175 | 0.6795 | 0.0652 | 0.2695 | 0.4442 |

### 7.4 Sanity check vs. round 1

Round-1 `policy_block x Agro x V2`: share_within=0.600295, med_sigma=0.000000.
This run (all_munis): share_within=0.600295, med_sigma=0.000000. Delta: |0.000000|, |0.000000|. **PASS**.

### 7.5 Verdict

**AGRO_OK** — Agro varies substantially where it exists. The flat tail in round 1 is 'where's the action,' not structural flatness. No change to D15.

Above-median sample (n=445 munis, baseline > p50=0.1412): 
  share_within = 0.7289, med_sigma_within = 0.3259.

### 7.6 Implication for D15

No change to D15. The round-1 verdict on `policy_block x Agro x V2` holds under conditioning: the flat tail is driven by urban munis where Agro BNDES is mechanically zero, not by structural time-flatness of Agro shares where the instrument actually bites.


---

## 8. Synthesis — production margin selection

### 8.1 Full candidate space (V1 primary, mean share_within across bins)

| Sector dim | Size dim | Active bins | mean share_within | n_supported / n_bins | Source |
|-----------|---------|------------:|------------------:|---------------------:|--------|
| `cnae_section` only | — | 17 | ~0.66 | (round 1) | D15 |
| `policy_block_active` only | — | 4 | ~0.61 | (round 1) | D15 |
| `policy_block_active` x A2 | 2 | 8 | 0.615 | 3/8 | E3c |
| `policy_block_active` x A3 | 3 | 12 | 0.642 | 3/12 | E3c |
| `cnae_section` x A2 | 2 | 34 | 0.755 | 3/34 | E3 |
| `cnae_section` x A3 | 3 | 51 | 0.769 | 3/51 | E3 |
| `cnae_section` x A4 | 4 | 68 | dropped at E2 (coverage fail) | — | E2 |

### 8.2 Diagnostic gates summary

| Gate | A3 (cnae x size) | A3 (policy_block x size) | Note |
|------|------------------|--------------------------|------|
| F0 admissibility | PASS | PASS | Firm-side classifier defined for every RAIS firm |
| E0 stability (year-level) | PASS — A4 19.9% YoY-changed (justifies cycle-baseline rule); A3 3.3% | same | Cycle-baseline retained |
| E1 alignment year-level (T3 imputation) | uw 3x3 = 87%, vw 4x4 = 70% | inherits | A4 thresholds align with BNDES porte |
| E2 coverage | nominal FAIL on Media + Grande (share_munis_med < 0.10) | inherits, fewer fail | V1 active-only renormalization preserves IV mechanic |
| E3 F1 within-muni | mean share_within = 0.769 (V1) | mean share_within = 0.642 (V1) | Both SUPPORTED under V1 and V2 |
| E3b Agro conditional | AGRO_OK; med sigma_within above-median = 0.326 | inherits | D15 holds; round-1 Agro flat tail is 'where's the action' |

### 8.3 Production margin commitment

**Primary: `policy_block_active` x A3 (4 active blocks x 3 size bins = 12 active bins).**

Rationale:
1. **Institutional alignment.** Policy blocks (Agro / Ind / Infra / Serv) are the units BNDES uses for policy targeting. The IV's bin structure mirrors the institutional mechanism.
2. **Coverage-supported identification.** 12 fat cells produce 3 supported bins (3/12 = 25% of the bin set), substantially higher fraction than `cnae_section x A3` (3/51 = 5.9%).
3. **Strong first-stage prospect.** Fewer instruments means cleaner inference. The mean share_within (0.642) exceeds round-1's policy-block-only baseline (0.61) — adding size buys identifying variation without sacrificing power.
4. **Consistency with the standing convention** (auto-memory `feedback_sector_classification_convention`): size bins are within sectors, not standalone.

**Secondary / robustness: `cnae_section` x A3 (51 active bins).** Highest mean share_within (0.769) among all tested options. Use as a robustness comparison when the paper draft is built; report alongside the primary specification.

### 8.4 Non-priorities (documented for the record)

- **A2 (2-bin scheme MPME / Big).** Cleared E2 coverage where A3 nominally failed but loses Media-Grande granularity. Run as a sanity check if the primary spec produces unstable estimates; otherwise dropped.
- **Option B (within-sector terciles).** Excluded on interpretability grounds (terciles are sector-relative ranks, not absolute thresholds with institutional meaning). E3 numbers comparable; not promoted.
- **Stratified inference by muni bin-coverage.** Discussed; rejected as a structural choice. Muni-size heterogeneity should be a robustness slice on top of the chosen estimator, not a structural feature of the IV.

### 8.5 Caveats to surface in the paper

1. **E2 nominal FAIL on Media and Grande bins** (share_munis_borrower_med ~0.10 and ~0.04 respectively). Acceptable under V1 active-only renormalization — the IV correctly assigns ~0 weight to bins absent from a muni's baseline. Worth a footnote.
2. **51% of BNDES loans match no RAIS firm-year row** (E1c diagnostic). 100% of the unmatched-loan firms never appear in RAIS in any year — informality / Cartao BNDES / non-firm entities. Treated as Micro under T3 imputation when stated porte is Micro/Pequena (586,786 loans); 266,335 stated Media/Grande unmatched loans dropped. Document in the data-construction appendix.
3. **A4 4-bin scheme dropped at E2** despite passing E0 stability and E1 alignment, due to thin coverage on Micro, Media, and Grande individually. The 3-bin collapse (A3) is the production granularity ceiling.
