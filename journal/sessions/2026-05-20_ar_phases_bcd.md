# Session — AR test Phases B, C, D (instrument combinations + 2026-05-21 deck)

## 2026-05-20 — Phases B/C/D of the 2026-05-20 plan

**Goal:** Execute Phases B, C, D of `journal/plans/2026-05-20_ec-adequacy-and-instrument-combinations.md`. Phase A was already complete. Deliverable: the 2026-05-21 advisor meeting deck.

**Operations:**
- Phase B/C (coder): edited `03_build_muni_ar_panel.R` (Z retains all J sectors, EC retains J−1); wrote `B2_composition_first_stage.R`, `B3_volume_first_stage.R`, `B4_channel_routing.R`, `B5_advisor_comparison.R`, `B6_three_volume_ar.R`, `C3_coverage_audit.R`, `run_phase_bc.R`. Ran end-to-end for both margins. 28 output files in `explorations/anderson_rubin/ar_meeting_2026_05_13/output/`.
- coder-critic review: 82/100 (PASS). Four must-fix items addressed (preconditions + tryCatch, dead-stub removal, fallback invariant assertion, helper de-duplication); outputs verified byte-identical.
- Bug fix: degenerate joint Wald F (4.86e7, rank-deficient) at the `policy_block` composition first stage — guarded via `joint_F_rank_deficient()` in `00_helpers.R`; degenerate cell now prints "Rank-deficient (collinear channels)".
- Notation fix: `channel_label()` interaction channels switched to `$\cdot$` (INV-20); tables regenerated and re-copied.
- Phase D (storyteller): built `journal/meetings/2026-05-21/slides.tex` — 18 frames, inherits 2026-05-14 preamble/theme.
- `latex-aesthetic-review`: Phase 1 clean (18 pages, 0 overfull/underfull, no undefined refs).
- storyteller-critic review: 90/100. Applied the one substantive recommendation (slide 15 subtitle now lists the fallback composition set). Recompiled clean.

**Decisions (logged D33–D37 in `docs/decision_log.md`):**
- D33 — AR instruments retain all J sector columns per channel; EC retains J−1.
- D34 — channel routing rule from the two saturated first stages; fallback to mayor-crossed channels.
- D35 — Full-IV ("volume instrumented") column shown only if a channel clears the volume gate.
- D36 — three-volume AR table reported for two instrument sets (data-selected composition set + four mayor-crossed channels).
- D37 — AR test reported at two margins only: `policy_block` and `policy_block × S3`.

**Results:**
- Routing — `policy_block`: composition = {President} (F=7.75); volume = {Governor, Mayor·Governor}; rest dropped. 12-group: no channel clears the composition gate → fallback {M, M·P, M·G, M·G·P}; volume = {Governor}.
- B5 — `{M,G,M·G}` stacked is sharper than `{M·G}` alone at both margins (policy_block: F 4.82 vs 3.20; both reject).
- B6 — `policy_block`: among the four mayor-crossed channels, only Mayor·Governor rejects (F≈3.19, p≈0.012), stable across all three volume treatments; the President composition set never rejects. 12-group: the composition set rejects without/with a volume control (F=1.47, p=0.020) but NOT under Full IV (p=0.162).
- C3 — 12-group thin cells are 64.8% of cells but carry only 9.3% of GDP; effective shocks median 12.5.

**Status:**
- Done: Phases B, C, D. Deck compiled (`journal/meetings/2026-05-21/build/slides.pdf`, 18 pages). Decision log, research journal, blueprint, `findings.md`, `SESSION_LOG.md` updated.
- Pending: deferred per-channel F3 placebo/falsification on routing-relevant channels (run after the 2026-05-21 meeting). Resume Phase 4 documentation (E4.1, E4.3).
