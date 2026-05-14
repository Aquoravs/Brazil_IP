---
status: READY (paste into a fresh orchestrator session)
date: 2026-05-13
purpose: Sequential + parallel orchestration of the AR-test updated results plan.
companion: 2026-05-13_ar_test_updated_meeting.md (APPROVED)
---

# Orchestrator prompt — Updated AR Test Results for the 2026-05-14 meeting

> Copy everything below the line into a fresh orchestrator session
> (`/orchestrator` or equivalent). The orchestrator should not enter
> plan mode; the plan is already APPROVED.

---

## Mission

Execute end-to-end the approved plan at
`journal/plans/2026-05-13_ar_test_updated_meeting.md`. Deliverable:
compiled Beamer PDF at `journal/meetings/2026-05-14/build/slides.pdf`
showing AR-test results for 4 cross-office channels (M, M·P, M·G, M·G·P)
× 4 control specs across two taxonomies (`policy_block`, `size_bin`).
Deadline: the 2026-05-14 meeting.

## Load-bearing context (read in this order, then stop reading)

1. `journal/plans/2026-05-13_ar_test_updated_meeting.md` — the plan,
   12 locked decisions L1–L12, file map, commands.
2. `docs/methodology/ar_test_specification.tex` §2.3 (Variant A,
   eq:w-own-rel) and §Volume control (eq:vol-explicit).
3. `docs/strategy/office_specific_exposure_weights.md` §3.2 (Variant F
   pre-earliest window timing, with worked example).
4. `explorations/anderson_rubin/active_denominator/R/02_ar_test_emp_share.R`
   — template for the AR runner (do not modify it; copy patterns).
5. `explorations/anderson_rubin/a10_composition_volume/output/slides.tex`
   — Beamer format target (palatino, 11pt, 16:9, booktabs, resizebox).

Skip `CLAUDE.md` re-read; you already have the rules in `.claude/rules/`.

## Branch and workspace

```
explorations/anderson_rubin/ar_meeting_2026_05_13/
  README.md          (create from templates/exploration-readme.md)
  SESSION_LOG.md     (append incremental entries; see logging rules)
  R/
    00_helpers.R
    01_build_variant_a_weights.R
    02_build_instruments_ec.R
    03_build_muni_ar_panel.R
    04_run_ar_regressions.R
    05_build_slides.R
  output/            (qs2 + csv + tex artefacts)
```

Final slides deck assembled at:
`journal/meetings/2026-05-14/slides.tex` + `build/slides.pdf`.

## Execution graph (DAG)

```
[Stage 0] helpers + windows  (one-shot, opus, HIGH)
      │
      ├──────────────────────────────────────┐
      │                                      │
[A1.pb] weights policy_block            [A1.sb] weights size_bin    (parallel)
      │                                      │
[A2.pb] Z + EC policy_block             [A2.sb] Z + EC size_bin     (parallel)
      │                                      │
[B.pb]  muni AR panel policy_block      [B.sb]  muni AR panel size_bin (parallel)
      │                                      │
[C.pb]  16 regressions policy_block     [C.sb]  16 regressions size_bin (parallel)
      │                                      │
[D.pb]  slide sections policy_block     [D.sb]  slide sections size_bin (parallel)
      │                                      │
      └──────────────────┬───────────────────┘
                         │
                  [E] verify + merge deck + compile
                         │
              [F] commit + journal entry
```

The two taxonomy lanes are fully independent after Stage 0. Run them
in parallel using two worker tracks. Within a lane, stages are
strictly sequential.

## Per-stage dispatch

For every stage: dispatch the worker, await its artefact, dispatch the
paired critic, and gate progression on critic score ≥ 80
(per `.claude/rules/quality.md` exploration-phase renormalization, active
components = Code / Data / Identification / Replication). Max 3
worker-critic rounds per stage; on the 3rd failure, escalate per
`.claude/rules/agents.md` §3.

| Stage | Worker | Critic | Model | Effort | Why this model |
|---|---|---|---|---|---|
| 0 | coder | coder-critic | **opus** | HIGH | Channel-window helper is math-heavy; mistakes propagate everywhere. The Variant F definition (`min_{ℓ∈O(c)} e_ℓ(t)`) must be verified against the worked-example table in §3.2 of the office-specific memo. |
| A1.pb / A1.sb | data-engineer | coder-critic | **opus** | HIGH | Variant A muni-relative normalization (`bar L^{c,affil}_{m,t}` denominator over all sectors AND all parties) is the single highest-risk computation in the plan. See plan §8 risk register. |
| A2.pb / A2.sb | coder | coder-critic | **sonnet** | MEDIUM | Stacking and EC summation is mechanical once Stage A1 is correct. |
| B.pb / B.sb | data-engineer | coder-critic | **sonnet** | MEDIUM | Standard panel merge; mostly key-joins. |
| C.pb / C.sb | coder | coder-critic | **sonnet** | MEDIUM | Mirrors `02_ar_test_emp_share.R` AR runner. 16 cells per taxonomy. |
| D.pb / D.sb | storyteller | storyteller-critic | **sonnet** | MEDIUM | Beamer LaTeX must mirror `a10_composition_volume/output/slides.tex`. |
| E | verifier (standard mode) | — | **haiku** | LOW | Mechanical compile + numeric cross-check between CSV and tex. |
| F | coder (commit only) | — | **haiku** | LOW | Stage commit; no logic. |

Effort interpretation: HIGH = extended reasoning / thorough self-review;
MEDIUM = standard reasoning; LOW = single-pass execution.

## Stage acceptance criteria (binding)

### Stage 0 — helpers
- **Output:** `R/00_helpers.R` exporting `T_Fc_window(t, channel)`,
  `election_calendar` (table of mayoral and gov/pres election years
  in [2000, 2017]), `load_taxonomy(tax)` (returns crosswalk), and
  `z_col_name(channel, sector)` / `ec_col_name(channel, sector)`.
- **Test:** reproducing exactly the 6-row worked-example table in
  `office_specific_exposure_weights.md` §3.2 (t ∈ {2008, 2010, 2011,
  2012, 2014, 2017}, channels in {M·P, M·G, M·G·P}). Helper must emit
  the expected `[2002,2005]`, `[2004,2007]`, … windows.
- **Corner case to document:** for t with `e_{F,c}(t) < 2002`, the
  intersection with [2002, 2017] is empty. Default policy: drop those
  (muni, year) pairs from the affected channel's panel; flag in logs.

### Stage A1 — Variant A weights (per taxonomy)
- **Math:** for every (channel c, muni m, year t, sector j, party p),
  ```
  w_tilde^{c,own}_{jmp,t} =
      (Σ_{s∈T^{F,c}_t} Σ_{f∈F(j,m)} L_{f,p,s})
      ÷
      (Σ_{s∈T^{F,c}_t} Σ_{j'} Σ_{p'} Σ_{f∈F(j',m)} L_{f,p',s})
  ```
  Denominator is muni-level total affiliated owner-years across ALL
  sectors and ALL parties — verify this in code review.
- **Invariant:** `Σ_{j,p} w_tilde^{c,own}_{jmp,t} ∈ {0, 1}` exactly
  (zero only if muni has no affiliated owners in the window).
- **Firm support:** RAIS universe (`in_rais == TRUE`); frozen at the
  pre-window per cycle.
- **Output:** `output/weights_variant_a_<tax>.qs2` with columns
  `muni_id, year, channel, sector, party, w_tilde, T_Fc_lo, T_Fc_hi`.

### Stage A2 — Z and EC
- **Z:** `Z^c_{jmt} = Σ_p w_tilde^{c,own}_{jmp,t} · Align^c_{mpt}`.
- **EC:** `EC^c_{jm,t} = Σ_p w_tilde^{c,own}_{jmp,t}` (per cell, before
  hold-out drop).
- **Output:** `output/Z_variant_a_<tax>.qs2` (long: muni, year, channel,
  sector, Z_val) and `output/EC_variant_a_<tax>.qs2` (same schema).
- **Invariant:** `Σ_j EC^c_{jm,t} ∈ {0, 1}` for every (m, t, c).

### Stage B — Muni AR panel
- **Schema:** muni_id, year, log_gdp, vol_ratio, plus J-1 sector columns
  per channel for Z's and per channel for EC's (hold-out = largest mean
  share per `02_ar_test_emp_share.R` convention).
- **Volume control:** `vol_ratio_mt = total_bndes_real_mt /
  pib_real_{m, 2002}`. Drop munis missing 2002 GDP.
- **Output:** `output/muni_panel_ar_<tax>.qs2`.

### Stage C — Regressions
- **Loop:** 4 channels × 4 specs = 16 regressions per taxonomy. For
  each: `fixest::feols(log_gdp ~ Z's [+ ec_cols] [+ vol_ratio] |
  muni_id + year, vcov = ~ muni_id, lean = TRUE)`. AR statistic =
  `fixest::wald(mod, keep = paste0("^Z_", channel, "_"))`.
- **Outputs:**
  - `output/ar_summary_<tax>.csv` (16 rows × `{channel, spec, n_obs,
    n_munis, K_Z, ar_F, ar_p, vol_coef, vol_se, ar_reject_5pc}`).
  - `output/ar_table_fstats_<tax>.tex` (bare booktabs `tabular`; rows
    = channels, columns = specs; cells = `F[stars] [p]`; stars per L11
    working-paper default).
  - `output/ar_table_coefs_<tax>_pair1.tex` (channels M, M·P).
  - `output/ar_table_coefs_<tax>_pair2.tex` (channels M·G, M·G·P).

### Stage D — Slide sections
- Mirror `explorations/anderson_rubin/a10_composition_volume/output/slides.tex`:
  - `\documentclass[aspectratio=169,11pt]{beamer}`, palatino, T1
    fontenc, booktabs, makecell, microtype.
  - Footer page number only.
- Per taxonomy: 3 slides (1 F-stat + 2 coef pairs).
- **Title slide:** "Updated AR Test Results" — date `May 14, 2026` on
  first body slide. No subtitle. Per L12.
- **Per-taxonomy intro slide:** name of taxonomy, K, hold-out sector.
- Coefficient slides use 2 sub-tables per slide (channels paired).

### Stage E — Verify + merge + compile
- **Cross-check:** every F and p in the F-stat tex matches the CSV
  row to 3 decimals.
- **Compile:** `cd journal/meetings/2026-05-14 && xelatex -interaction=
  nonstopmode slides.tex` twice (for refs).
- **First-stage diagnostic (advisory only):** rerun
  `run_first_stage_joint_F()` on the M·G·P channel for each taxonomy;
  log the value.
- **Output:** `journal/meetings/2026-05-14/build/slides.pdf`.

### Stage F — Commit + journal
- Single commit on `main` (no PR for exploration artefacts):
  ```
  feat(ar-test): updated AR results for 2026-05-14 meeting

  Variant A primary weights with pre-earliest windows, RAIS universe,
  per-cell EC, frozen support. 4 cross-office channels × 4 control
  specs × {policy_block, size_bin}.
  ```
- Append entries to `journal/research_journal.md` and to
  `journal/sessions/2026-05-13_ar_meeting_update.md` per
  `.claude/rules/logging.md`.

## Parallelism rules

- Stages 0 → A1 → A2 → B → C → D within a lane are strictly sequential.
- The two lanes `.pb` and `.sb` are fully independent after Stage 0;
  dispatch them as two parallel agent tracks.
- Inside each Stage A1, A2, B, C, D — no further parallelism (data
  hazards on shared qs2 files).
- Stage E waits on both lanes to complete D.

## Logging and progress

After each completed stage append an entry to
`journal/sessions/2026-05-13_ar_meeting_update.md` using the format
in `.claude/rules/logging.md`. After Stage F append a research-journal
entry per the same rules.

## Escalation

- Worker-critic rounds: max 3 per stage. Escalate per
  `.claude/rules/agents.md` §3:
  - A1, A2, B, C failures → strategist-critic (re-evaluate plan).
  - D failure → user.
- Verifier (Stage E): 2 retry attempts; then user.
- Numeric mismatch between tex and CSV: re-run Stage C; do not patch
  the tex by hand.

## Definition of done

- `journal/meetings/2026-05-14/build/slides.pdf` exists and renders
  the 6+ substantive slides.
- `output/ar_summary_policy_block.csv` and `output/ar_summary_size_bin.csv`
  each have 16 rows with finite `ar_F` and `ar_p`.
- All worker stages have critic scores ≥ 80.
- Commit hash recorded in the plan footer; plan status flipped to
  COMPLETED.
- Journal entry appended.
