# Documentation and Workflow Cleanup Plan

**Date:** 2026-05-12
**Scope:** Documentation, workflow conventions, exploration state, and research traceability.
**Non-goals:** Do not relitigate econometrics. Do not refactor production code. Do not force paper-ready output standards during the exploration phase.

## Objective

Make the repository easier for a new agent or human researcher to enter by separating:

- the project front door from detailed state catalogs;
- active, deferred, blocked, settled, provisional, and superseded items;
- production pipeline files from exploration artifacts;
- exploratory findings from research building blocks that can support later paper writing;
- claims from the evidence that supports them;
- the immediate next implementation step from longer-run backlog items.

The repository should be treated as an exploration and research-building system. Its near-term goal is not to produce final paper-ready outputs, but to produce reliable, well-labeled building blocks that can later be assembled into a paper.

## Guiding Conventions

Use these labels consistently:

| Label | Meaning |
|---|---|
| `ACTIVE` | Current workstream; can be worked on now. |
| `BLOCKED` | Cannot proceed until a named upstream decision or artifact exists. |
| `DEFERRED` | Intentionally postponed; not a current blocker. |
| `SETTLED` | Decision is currently adopted; do not reopen without new evidence. |
| `PROVISIONAL` | Working choice; valid for current exploration but may change. |
| `SUPERSEDED` | Replaced by a later decision; retained for audit trail. |
| `EXPLORATORY_RESULT` | Valid as a diagnostic result within its branch; not a production input by default. |
| `RESEARCH_BUILDING_BLOCK` | Stable enough to inform later synthesis, memos, or paper writing, but not itself a final paper artifact. |
| `PRODUCTION_PIPELINE_READY` | Implemented in `scripts/R/`, documented, and verified by project gates. |

Avoid "safe to cite" as the organizing frame. Prefer "safe to use for what?" with explicit use status:

- `diagnostic only`
- `supports next design decision`
- `research building block`
- `ready for production pipeline`
- `superseded / do not use`

## Deliverables

### 1. Shrink `docs/PROJECT_BLUEPRINT.md`

Convert it into a short front door, ideally 80-120 lines:

- current research question;
- current phase and active focus;
- immediate blocker;
- next implementation step;
- active vs deferred tracks;
- current production-pipeline caveat;
- links to detailed state documents.

It should not carry the full decision log, taxonomy catalog, or long evidence tables.

### 2. Restore `docs/research_state.md`

Create the missing state catalog referenced by existing docs. It should include:

- F0-F4 identification chain with status;
- active, blocked, deferred, completed, and superseded tracks;
- current production-margin status;
- current instrument-form status;
- next step and blocking dependency;
- short links to the evidence index and decision log.

### 3. Create `docs/decision_log.md`

Move the D1-D28 table out of the blueprint. Add status columns:

- `status`: settled / provisional / superseded / deferred;
- `superseded_by`;
- `source`;
- `evidence pointer`.

Keep it append-only in spirit. Do not delete old decisions; mark them.

### 4. Create `docs/evidence_index.md`

This is not a citation index. It is a traceability map:

| Claim / Decision | Status | Evidence artifact | Use status | Caveat |
|---|---|---|---|---|

Use it to answer: "Where does the evidence for this claim live, and what is it currently safe to use it for?"

### 5. Create `docs/taxonomies.md`

Move sector and size taxonomy details out of the blueprint:

- `cnae_section`;
- `custom_sector`;
- `policy_block_active`;
- S2/S3/S4;
- `policy_block_active x S3`;
- `cnae_section x S3`;
- legacy taxonomies.

Each row should specify production status, build script, evidence, and whether it is active, robustness, legacy, or exploratory.

### 6. Create `explorations/ACTIVE_PROJECTS.md`

Add one row per exploration branch:

| Branch | Status | Decision it informs | Main result | Next action | Owner artifact |
|---|---|---|---|---|---|

This should make stale exploration READMEs less dangerous.

### 7. Revise exploration templates

Update `templates/exploration-readme.md` so every future exploration includes:

- status;
- parent A/D/F IDs;
- decision needed;
- production boundary;
- inputs;
- scripts;
- outputs;
- findings;
- caveats;
- use status;
- graduation / archive decision.

Add `templates/output-manifest.md` for branch outputs.

### 8. Add output manifests to active exploration folders

Start with:

- `explorations/anderson_rubin/mass_weighted_first_stage/output/MANIFEST.md`;
- `explorations/anderson_rubin/a7_weight_comparison/output/MANIFEST.md`;
- `explorations/anderson_rubin/diagnostics/output/MANIFEST.md`.

These should be concise. They do not need to describe every CSV exhaustively on the first pass; prioritize the load-bearing artifacts.

## Phase Plan

### Phase 0 - Freeze cleanup vocabulary

Deliverable: this plan plus the status vocabulary above.

Acceptance criteria:

- no paper-ready or citation-focused language governs exploration outputs;
- all later edits use the same status labels.

### Phase 1 - Create new skeleton documents

Create:

- `docs/research_state.md`;
- `docs/decision_log.md`;
- `docs/evidence_index.md`;
- `docs/taxonomies.md`;
- `explorations/ACTIVE_PROJECTS.md`;
- `templates/output-manifest.md`.

Acceptance criteria:

- every new file has a clear purpose statement;
- no detailed migration is required yet;
- all files point back to the blueprint front door.

### Phase 2 - Split the blueprint

Edit `docs/PROJECT_BLUEPRINT.md` into the front door. Move detailed content into the new documents instead of duplicating it.

Acceptance criteria:

- blueprint states that Track 1, theoretical/econometric review, is the immediate gating item;
- blueprint clearly says the production margin is not committed under D28;
- no section in the blueprint calls `policy_block_active x S3` the committed production margin;
- blueprint links to research state, decision log, evidence index, taxonomies, methodology spec, and active explorations.

### Phase 3 - Normalize active exploration state

Update:

- `explorations/ACTIVE_PROJECTS.md`;
- parent `explorations/anderson_rubin/README.md`;
- `mass_weighted_first_stage/README.md`;
- `mass_weighted_first_stage/findings.md` only if needed for use-status wording;
- selected output manifests.

Acceptance criteria:

- every active branch has one status row;
- stale branches are clearly marked `SUPERSEDED`, `DEFERRED`, or `COMPLETED`;
- mass-weighted first-stage outputs are labeled as diagnostics and research-building evidence, not production-pipeline inputs.

### Phase 4 - Fix stale links and front-door references

Update:

- `CLAUDE.md` only where it points to stale workflow state;
- `docs/README.md`;
- `journal/knowledge.md`;
- any obvious `logs/` references that should now point to `journal/` or `docs/`.

Acceptance criteria:

- no front-door doc points to a missing `docs/research_state.md`;
- old `logs/` references are either fixed or clearly marked historical;
- a new agent can follow the first five links from `CLAUDE.md` without dead ends.

### Phase 5 - Review pass

Run a doc review, not an econometric review:

- check for contradictions around the production margin;
- check active/deferred/blocked labels;
- check that every major claim has an evidence pointer;
- check that the next implementation step is unambiguous.

Acceptance criteria:

- top-level workflow can be understood in under 10 minutes;
- detailed evidence can be found in under 2 clicks from the blueprint;
- no cleanup edit changes the research logic.

## Suggested Execution Strategy

Use one main orchestrator agent for the whole cleanup. The main risk is inconsistent terminology, not raw workload, so one agent should own the final integration.

Parallelize only after Phase 1 skeletons exist. Good disjoint work units:

1. **State and blueprint worker:** `docs/PROJECT_BLUEPRINT.md`, `docs/research_state.md`.
2. **Decisions and taxonomies worker:** `docs/decision_log.md`, `docs/taxonomies.md`.
3. **Explorations worker:** `explorations/ACTIVE_PROJECTS.md`, exploration READMEs, output manifests.
4. **Link-audit reviewer:** read-only pass over `CLAUDE.md`, `docs/README.md`, `journal/knowledge.md`, and key links.

If using subagents, give each one a disjoint write set and tell them not to edit files outside it. The orchestrator should merge, resolve terminology, and run the final contradiction check.

For a single agent in another chat, run sequentially by phases. That is slower but safer and probably sufficient for this cleanup because most edits are documentation moves and consistency checks.

## Minimum Viable Cleanup

If only two hours are available:

1. Create `docs/research_state.md` as a compact current-state catalog.
2. Shrink `docs/PROJECT_BLUEPRINT.md` and remove production-margin contradictions.
3. Create `explorations/ACTIVE_PROJECTS.md`.
4. Add `templates/output-manifest.md`.
5. Add one manifest for `mass_weighted_first_stage/output/`.
6. Fix missing/stale references in `docs/README.md` and `journal/knowledge.md`.

## Ideal Cleanup

If one to two days are available:

1. Complete all five phases.
2. Backfill manifests for the major AR exploration output folders.
3. Mark stale AR baseline and horserace docs as superseded or historical where appropriate.
4. Add a short status note to `docs/methodology/ar_test_specification.tex` identifying which design choices are active, provisional, and pending empirical graduation.
5. Run a final doc-link and contradiction audit.
