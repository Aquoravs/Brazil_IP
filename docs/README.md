# docs/

Project-level design notes and reference material.

## Active

| File | Contents |
|------|----------|
| [`research_state.md`](research_state.md) | Current research state — design decisions, taxonomies, spec engine dimensions, findings, open questions, AR-test focus |
| [`doubts.md`](doubts.md) | 9 substantive design issues with their decisions (instrument timing, exclusion restriction, simplex, baseline year, FE choice, balanced panel, sector mismatch, bad-control concern) |
| [`meetings/`](meetings/) | Meeting records (cross-referenced from `logs/referee_response_tracker.md`) |
| [`methodology_notes/`](methodology_notes/) | Formal/technical reference documents — see below |

## `methodology_notes/`

| File | Contents |
|------|----------|
| `proposition2_aggregation_review.tex/.pdf` | Formal review of the firm ↔ sector aggregation claim; identifies the 5 conditions for numerical equivalence; distinguishes $Z$ (owner-count) from $\overline{\mathrm{FA}}$ (equal-firm). Was at `paper/review_aggregation.tex`; **not currently `\input{}`-ed by `paper/main.tex`** |
| `proposition2_failure_note.tex/.pdf` | Numeric verification of Proposition 2 on the reference firm spec (44M obs, B vs A samples, exact identity check, mean-regression gap) + plain-language C1–C6 walkthrough |
| `conditions_C3_C5_C6_explained.tex/.pdf` | Math + intuition for C3 (firm immobility), C5 (fixed cell composition), C6 (within-cell heterogeneity, irreducible on real data) |

## `archive/`

Historical material superseded by current files. Kept for traceability — substance preserved in `research_state.md` and `logs/knowledge.md`.

| File | Why archived |
|------|--------------|
| `master_roadmap.md` | 2026-03-12; references `paper/draft.tex` (now `main.tex`) and presentation paths that have moved; open decisions overlap with `logs/referee_response_tracker.md` |
| `old_CLAUDE_reference.md` | Pre-migration project doc using `BNDES/politicsregs/` paths; superseded by `INSTRUCTIONS.md` + `README.md` after the 2026-04-02 migration |
| `shift_share.md` | Updated shift-share spec; mostly superseded by `paper/regs.tex` (formal LaTeX) and `README.md` (pipeline mapping); validation rules preserved in `research_state.md` §7 |
| `first_stage_review.md` | Critical review of first-stage results (4 questions, recommendations). Findings preserved in `research_state.md` §6 and `logs/knowledge.md` §4. Recommendations are **secondary** — current focus has moved to AR test |
| `brainstorms/` | 5 brainstorms on firm-sector disconnect (implemented), affiliation diagnostics (implemented), fast Beamer table export (implemented), sector instrument weighting (implemented), AR test ideas (active — feeds C4/C8) |

## Cross-references

- Project overview, file layout, variable dictionary → [`../README.md`](../README.md)
- AI-agent-facing config and commands → [`../INSTRUCTIONS.md`](../INSTRUCTIONS.md)
- Authoritative draft of Section 5 (Specifications) → [`../paper/regs.tex`](../paper/regs.tex) (not yet integrated into `main.tex`)
- Implementation knowledge from session logs → [`../logs/knowledge.md`](../logs/knowledge.md)
- Advisor comment tracker (C1–C8) → [`../logs/referee_response_tracker.md`](../logs/referee_response_tracker.md)
