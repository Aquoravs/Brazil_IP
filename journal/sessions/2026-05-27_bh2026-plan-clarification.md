## 2026-05-27 19:56 — BH-2026 Plan Clarification

**Operations:**
- Read `CLAUDE.md`, `docs/PROJECT_BLUEPRINT.md`, and shared logging, writing, and quality rules.
- Edited `journal/plans/2026-05-26_bh2026_optimal_first_stage.md`.

**Decisions:**
- Reframed Phase 1 D1 as a legacy sector-collapse diagnostic, not a BH-2026 production selector.
- Made the firm-level `FA^c_{f,m,t}` definition the central Phase 2 design space.
- Preserved selection by held-out sector-level first-stage F after additive firm-to-sector aggregation.

**Results:**
- Plan now separates legacy sector-weight diagnostics from firm-level exposure design, additive aggregation, and held-out sector evaluation.
- No production code changed and no pipeline runs launched.

**Commits:**
- None.

**Status:**
- Done: focused plan clarification patch.
- Pending: none for this request.

## 2026-05-27 20:10 — Baseline Window Clarification

**Operations:**
- Edited `journal/plans/2026-05-26_bh2026_optimal_first_stage.md`.

**Decisions:**
- Replaced the "higher-tier pre-window" robustness label with the three timing options: pre-earliest, pre-latest, and pre-mayor.
- Framed pre-latest as a recency stress test with explicit post-treatment risk for the earlier office.

**Results:**
- Phase 2 baseline-window grid now matches the user's clarified design.

**Commits:**
- None.

**Status:**
- Done: plan wording updated.
- Pending: none.
