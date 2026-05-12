# docs/

Project-level design notes and reference material. Start with [`PROJECT_BLUEPRINT.md`](PROJECT_BLUEPRINT.md); it is the front door for current state, active gate, and next workflow step.

## Active

| File | Contents |
|------|----------|
| [`PROJECT_BLUEPRINT.md`](PROJECT_BLUEPRINT.md) | Short front door: current research question, active gate, next implementation step, and links to detailed state files. |
| [`research_state.md`](research_state.md) | Current AR research state, identification-chain status, active / blocked tracks, and production-margin boundary. |
| [`decision_log.md`](decision_log.md) | Append-only decision register with settled, provisional, superseded, deferred, and blocked statuses. |
| [`evidence_index.md`](evidence_index.md) | Traceability map from claims and decisions to evidence artifacts and research use status. |
| [`taxonomies.md`](taxonomies.md) | Sector and size taxonomy catalog, including production status and use status. |
| [`data_memos/`](data_memos/) | C6/C7-style data-source feasibility memos. |
| [`strategy/`](strategy/) | Load-bearing strategy memos and design rationale. Some older memos predate D28; check `research_state.md` before treating them as current guidance. |
| [`methodology/`](methodology/) | Formal and technical LaTeX notes, including [`ar_test_specification.tex`](methodology/ar_test_specification.tex). |

## Archive

Historical material superseded by current files. Kept for traceability; current status should be checked in [`research_state.md`](research_state.md), [`decision_log.md`](decision_log.md), and [`../journal/knowledge.md`](../journal/knowledge.md).

## Cross-references

- Project overview, file layout, variable dictionary -> [`../README.md`](../README.md)
- AI-agent-facing config and commands -> [`../CLAUDE.md`](../CLAUDE.md)
- Active exploration status -> [`../explorations/ACTIVE_PROJECTS.md`](../explorations/ACTIVE_PROJECTS.md)
- Implementation knowledge from session logs -> [`../journal/knowledge.md`](../journal/knowledge.md)
- Advisor meeting trackers -> [`../journal/meetings/`](../journal/meetings/)
