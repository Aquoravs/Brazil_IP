# Within-Muni x Time Variation Diagnostic — F1 Test
Generated: 2026-05-03 15:02:41

## Goal

Test foundation **F1** (`docs/PROJECT_BLUEPRINT.md` §3):

> *For at least one F0-margin, BNDES credit shares have meaningful within-muni x time variation.*

If shares are flat within muni over time, muni FE absorb everything → no first-stage variation → IV degenerates. F1 is the most cheaply falsified link in the identification chain.

## Setup

- Universe: muni-years with total muni BNDES > 0.
- L_{m,b,t} = sum of `value_dis_real_2018_total` over firms with `in_bndes == 1` in (muni m, bin b, year t).
- Margins: M1 (`cnae_section`, 21 bins), M2 (`policy_block`, 5 bins), M3 (`policy_block_active`, 4 bins).
- Denominators: V1 (active-only, sum over non-XX bins) vs V2 (full economy, includes XX).

**SUPPORTED heuristic:** at least one bin has cross-muni median sigma_within > 0.05 AND share_within > 0.2.
**REJECTED heuristic:** max share_within across bins < 0.1.

---

## 1. F1 Verdict

**Overall F1 verdict: CONFIRMED**

- Supported (margin × denom): 6 / 6
- Rejected:                   0 / 6
- Inconclusive:               0 / 6

### Per-spec verdict

| Margin | Denom | Verdict | Max share_within | Max med σ_within | Med share_within | Med med σ_within | n bins |
|--------|-------|---------|------------------|------------------|------------------|------------------|--------|
| cnae_section | V1 | SUPPORTED [YES] | 0.885 | 0.309 | 0.813 | 0.000 | 21 |
| cnae_section | V2 | SUPPORTED [YES] | 0.928 | 0.309 | 0.831 | 0.000 | 21 |
| policy_block | V1 | SUPPORTED [YES] | 0.700 | 0.329 | 0.607 | 0.268 | 5 |
| policy_block | V2 | SUPPORTED [YES] | 0.834 | 0.329 | 0.620 | 0.256 | 5 |
| policy_block_active | V1 | SUPPORTED [YES] | 0.700 | 0.329 | 0.607 | 0.268 | 4 |
| policy_block_active | V2 | SUPPORTED [YES] | 0.701 | 0.329 | 0.610 | 0.267 | 4 |

---

## 2. M1. cnae_section (21-bin: A–U)

### V1 — V1 (active-only denominator)

**Verdict:** SUPPORTED [YES]

| Bin | n_munis | Mean s | Total Var | Btw Var | Within Var | share_within | p10 σ | Med σ | p90 σ |
|-----|---------|--------|-----------|---------|------------|--------------|-------|-------|-------|
| A | 5,042 | 0.0588 | 0.03935 | 0.01852 | 0.02349 | 0.597 | 0.000 | 0.000 | 0.348 |
| B | 5,042 | 0.0231 | 0.01435 | 0.00770 | 0.00900 | 0.628 | 0.000 | 0.000 | 0.130 |
| C | 5,042 | 0.2637 | 0.12123 | 0.05496 | 0.07058 | 0.582 | 0.000 | 0.239 | 0.436 |
| D | 5,042 | 0.0059 | 0.00466 | 0.00126 | 0.00377 | 0.808 | 0.000 | 0.000 | 0.000 |
| E | 5,042 | 0.0077 | 0.00424 | 0.00098 | 0.00345 | 0.813 | 0.000 | 0.000 | 0.023 |
| F | 5,042 | 0.0400 | 0.02042 | 0.00852 | 0.01483 | 0.726 | 0.000 | 0.002 | 0.255 |
| G | 5,042 | 0.3142 | 0.14098 | 0.09147 | 0.08098 | 0.574 | 0.009 | 0.309 | 0.493 |
| H | 5,042 | 0.2117 | 0.09596 | 0.03627 | 0.06648 | 0.693 | 0.000 | 0.224 | 0.429 |
| I | 5,042 | 0.0059 | 0.00322 | 0.00085 | 0.00266 | 0.828 | 0.000 | 0.000 | 0.026 |
| J | 5,042 | 0.0320 | 0.02048 | 0.00341 | 0.01751 | 0.855 | 0.000 | 0.000 | 0.258 |
| K | — | — | — | — | — | — | — | — | — |
| L | 5,042 | 0.0017 | 0.00102 | 0.00041 | 0.00085 | 0.832 | 0.000 | 0.000 | 0.000 |
| M | 5,042 | 0.0062 | 0.00345 | 0.00073 | 0.00286 | 0.830 | 0.000 | 0.000 | 0.020 |
| N | 5,042 | 0.0192 | 0.01001 | 0.00502 | 0.00728 | 0.728 | 0.000 | 0.000 | 0.133 |
| O | — | — | — | — | — | — | — | — | — |
| P | 5,042 | 0.0027 | 0.00123 | 0.00032 | 0.00107 | 0.874 | 0.000 | 0.000 | 0.008 |
| Q | 5,042 | 0.0024 | 0.00093 | 0.00011 | 0.00082 | 0.885 | 0.000 | 0.000 | 0.005 |
| R | 5,042 | 0.0029 | 0.00197 | 0.00023 | 0.00173 | 0.875 | 0.000 | 0.000 | 0.002 |
| S | 5,042 | 0.0019 | 0.00110 | 0.00018 | 0.00095 | 0.859 | 0.000 | 0.000 | 0.002 |
| T | — | — | — | — | — | — | — | — | — |
| U | — | — | — | — | — | — | — | — | — |

### V2 — V2 (full-economy denominator)

**Verdict:** SUPPORTED [YES]

| Bin | n_munis | Mean s | Total Var | Btw Var | Within Var | share_within | p10 σ | Med σ | p90 σ |
|-----|---------|--------|-----------|---------|------------|--------------|-------|-------|-------|
| A | 5,045 | 0.0582 | 0.03881 | 0.01812 | 0.02330 | 0.600 | 0.000 | 0.000 | 0.345 |
| B | 5,045 | 0.0230 | 0.01426 | 0.00768 | 0.00895 | 0.627 | 0.000 | 0.000 | 0.129 |
| C | 5,045 | 0.2619 | 0.12055 | 0.05442 | 0.07029 | 0.583 | 0.000 | 0.238 | 0.436 |
| D | 5,045 | 0.0059 | 0.00465 | 0.00125 | 0.00375 | 0.808 | 0.000 | 0.000 | 0.000 |
| E | 5,045 | 0.0076 | 0.00423 | 0.00097 | 0.00344 | 0.814 | 0.000 | 0.000 | 0.023 |
| F | 5,045 | 0.0398 | 0.02032 | 0.00848 | 0.01477 | 0.727 | 0.000 | 0.002 | 0.254 |
| G | 5,045 | 0.3123 | 0.14042 | 0.09089 | 0.08095 | 0.576 | 0.010 | 0.309 | 0.494 |
| H | 5,045 | 0.2101 | 0.09516 | 0.03589 | 0.06595 | 0.693 | 0.000 | 0.223 | 0.427 |
| I | 5,045 | 0.0059 | 0.00320 | 0.00084 | 0.00266 | 0.829 | 0.000 | 0.000 | 0.026 |
| J | 5,045 | 0.0317 | 0.02025 | 0.00338 | 0.01733 | 0.856 | 0.000 | 0.000 | 0.257 |
| K | 5,045 | 0.0068 | 0.00457 | 0.00113 | 0.00381 | 0.834 | 0.000 | 0.000 | 0.026 |
| L | 5,045 | 0.0017 | 0.00102 | 0.00041 | 0.00084 | 0.832 | 0.000 | 0.000 | 0.000 |
| M | 5,045 | 0.0061 | 0.00342 | 0.00071 | 0.00284 | 0.831 | 0.000 | 0.000 | 0.019 |
| N | 5,045 | 0.0191 | 0.00997 | 0.00501 | 0.00726 | 0.728 | 0.000 | 0.000 | 0.133 |
| O | 5,045 | 0.0000 | 0.00000 | 0.00000 | 0.00000 | 0.913 | 0.000 | 0.000 | 0.000 |
| P | 5,045 | 0.0027 | 0.00123 | 0.00032 | 0.00107 | 0.874 | 0.000 | 0.000 | 0.008 |
| Q | 5,045 | 0.0024 | 0.00092 | 0.00011 | 0.00081 | 0.884 | 0.000 | 0.000 | 0.005 |
| R | 5,045 | 0.0029 | 0.00196 | 0.00022 | 0.00172 | 0.876 | 0.000 | 0.000 | 0.002 |
| S | 5,045 | 0.0019 | 0.00108 | 0.00018 | 0.00092 | 0.858 | 0.000 | 0.000 | 0.002 |
| T | 5,045 | 0.0000 | 0.00000 | 0.00000 | 0.00000 | 0.928 | 0.000 | 0.000 | 0.000 |
| U | 5,045 | 0.0001 | 0.00004 | 0.00001 | 0.00003 | 0.867 | 0.000 | 0.000 | 0.000 |

**V1 vs V2:** Denominator choice does **not** change the verdict (V1=SUPPORTED, V2=SUPPORTED).

---

## 2. M2. policy_block (5-bin: Agro/Ind/Infra/Serv/XX)

### V1 — V1 (active-only denominator)

**Verdict:** SUPPORTED [YES]

| Bin | n_munis | Mean s | Total Var | Btw Var | Within Var | share_within | p10 σ | Med σ | p90 σ |
|-----|---------|--------|-----------|---------|------------|--------------|-------|-------|-------|
| Agro | 5,042 | 0.0588 | 0.03935 | 0.01852 | 0.02349 | 0.597 | 0.000 | 0.000 | 0.348 |
| Ind | 5,042 | 0.2868 | 0.12777 | 0.06052 | 0.07385 | 0.578 | 0.000 | 0.257 | 0.447 |
| Infra | 5,042 | 0.2653 | 0.11316 | 0.04395 | 0.07927 | 0.700 | 0.000 | 0.278 | 0.450 |
| Serv | 5,042 | 0.3891 | 0.15073 | 0.08616 | 0.09317 | 0.618 | 0.000 | 0.329 | 0.492 |
| XX | — | — | — | — | — | — | — | — | — |

### V2 — V2 (full-economy denominator)

**Verdict:** SUPPORTED [YES]

| Bin | n_munis | Mean s | Total Var | Btw Var | Within Var | share_within | p10 σ | Med σ | p90 σ |
|-----|---------|--------|-----------|---------|------------|--------------|-------|-------|-------|
| Agro | 5,045 | 0.0582 | 0.03881 | 0.01812 | 0.02330 | 0.600 | 0.000 | 0.000 | 0.345 |
| Ind | 5,045 | 0.2849 | 0.12711 | 0.06000 | 0.07357 | 0.579 | 0.000 | 0.256 | 0.447 |
| Infra | 5,045 | 0.2633 | 0.11241 | 0.04356 | 0.07877 | 0.701 | 0.000 | 0.277 | 0.447 |
| Serv | 5,045 | 0.3867 | 0.15031 | 0.08566 | 0.09326 | 0.620 | 0.000 | 0.329 | 0.492 |
| XX | 5,045 | 0.0068 | 0.00460 | 0.00113 | 0.00384 | 0.834 | 0.000 | 0.000 | 0.027 |

**V1 vs V2:** Denominator choice does **not** change the verdict (V1=SUPPORTED, V2=SUPPORTED).

---

## 2. M3. policy_block_active (4-bin: Agro/Ind/Infra/Serv)

### V1 — V1 (active-only denominator)

**Verdict:** SUPPORTED [YES]

| Bin | n_munis | Mean s | Total Var | Btw Var | Within Var | share_within | p10 σ | Med σ | p90 σ |
|-----|---------|--------|-----------|---------|------------|--------------|-------|-------|-------|
| Agro | 5,042 | 0.0588 | 0.03935 | 0.01852 | 0.02349 | 0.597 | 0.000 | 0.000 | 0.348 |
| Ind | 5,042 | 0.2868 | 0.12777 | 0.06052 | 0.07385 | 0.578 | 0.000 | 0.257 | 0.447 |
| Infra | 5,042 | 0.2653 | 0.11316 | 0.04395 | 0.07927 | 0.700 | 0.000 | 0.278 | 0.450 |
| Serv | 5,042 | 0.3891 | 0.15073 | 0.08616 | 0.09317 | 0.618 | 0.000 | 0.329 | 0.492 |

### V2 — V2 (full-economy denominator)

**Verdict:** SUPPORTED [YES]

| Bin | n_munis | Mean s | Total Var | Btw Var | Within Var | share_within | p10 σ | Med σ | p90 σ |
|-----|---------|--------|-----------|---------|------------|--------------|-------|-------|-------|
| Agro | 5,045 | 0.0582 | 0.03881 | 0.01812 | 0.02330 | 0.600 | 0.000 | 0.000 | 0.345 |
| Ind | 5,045 | 0.2849 | 0.12711 | 0.06000 | 0.07357 | 0.579 | 0.000 | 0.256 | 0.447 |
| Infra | 5,045 | 0.2633 | 0.11241 | 0.04356 | 0.07877 | 0.701 | 0.000 | 0.277 | 0.447 |
| Serv | 5,045 | 0.3867 | 0.15031 | 0.08566 | 0.09326 | 0.620 | 0.000 | 0.329 | 0.492 |

**V1 vs V2:** Denominator choice does **not** change the verdict (V1=SUPPORTED, V2=SUPPORTED).

---

## 3. Top / Bottom Muni Sanity Check

Per (margin x denom), the 5 most variable + 5 least variable munis (by mean sigma_within across bins) and their annual share series are written to `variation_top_munis.csv`. Inspect these to verify the numbers correspond to plausible patterns.

---

## 4. Files Produced

| File | Rows | Description |
|------|------|-------------|
| variation_decomposition.csv | 60 | One row per margin x denom x bin: variance decomp + sigma quantiles |
| variation_by_muni.csv | 290980 | One row per margin x denom x muni x bin: n_years, mean, sigma_within |
| variation_summary.csv | 6 | One row per margin x denom: F1 verdict |
| variation_top_munis.csv | 3818 | Annual share series for top/bottom 5 munis |
| variation_within_muni_density.pdf | — | Density of sigma_within faceted by margin, colored by denom |

---

## 5. Implications for Identification

F1 is **CONFIRMED** on at least one (margin x denom) specification. Within-muni x time variation in BNDES credit shares exists for at least one candidate margin under at least one denominator choice. The shift-share IV identification strategy is not degenerate at the F1 link. **Next:** A6 (firm vs. project CNAE reconciliation, F2).

