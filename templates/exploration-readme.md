---
title: [Exploration Name]
status: template
date: YYYY-MM-DD
purpose: Standard README for exploration branches. The project front door remains docs/PROJECT_BLUEPRINT.md.
---

# [Exploration Name]

Purpose: [1-2 sentences describing the exploration and the decision it informs].

Parent docs: [relative link to docs/PROJECT_BLUEPRINT.md], [relative link to docs/research_state.md], and [relative link to explorations/ACTIVE_PROJECTS.md].

Use-status labels: diagnostic only; supports next design decision; research building block; ready for production pipeline; superseded / do not use.

## Status

- Branch status: ACTIVE / BLOCKED / DEFERRED / COMPLETED / SUPERSEDED
- Started:
- Last updated:
- Owner artifact:
- Current research use status: diagnostic only / supports next design decision / research building block / ready for production pipeline / superseded / do not use

## Decision Context

| Field | Value |
|---|---|
| Parent A/D/F IDs | [A#, D#, F#] |
| Decision needed | [What this exploration helps decide.] |
| Current blocker | [None, or named upstream decision/artifact.] |
| Production boundary | [State exactly what this branch does not change in `scripts/R/` or production outputs.] |

## Inputs

| Input | Source | Role | Caveat |
|---|---|---|---|
| `input.ext` | `path/or/script` | [What it provides.] | [Known limitation.] |

## Scripts

| Script | Purpose | Writes |
|---|---|---|
| `R/00_example.R` | [Short purpose.] | `output/example.ext` |

## Outputs

Create or update `output/MANIFEST.md` from [output-manifest.md](output-manifest.md), adjusting the relative link when copied into a nested folder.

| Artifact | Use status | Notes |
|---|---|---|
| `output/artifact.ext` | diagnostic only | [Short description.] |

## Findings

Summarize only current branch findings. Do not frame exploration outputs as final publication artifacts.

- [Finding 1.]
- [Finding 2.]

## Caveats

- [Design, data, inference, or production-boundary caveat.]

## Graduation / Archive Decision

- Graduation condition: [What must happen before this can inform production pipeline work.]
- Archive condition: [When this branch should be marked SUPERSEDED, DEFERRED, or COMPLETED.]
- Next action: [Concrete next step or "none; retained for audit trail."]
