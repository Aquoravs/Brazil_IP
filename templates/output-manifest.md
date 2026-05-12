---
title: Output Manifest Template
status: template
date: 2026-05-12
purpose: Standard manifest for exploration output folders. The project front door remains docs/PROJECT_BLUEPRINT.md.
---

# Output Manifest

Purpose: describe what an output folder contains, what decisions the outputs inform, and the current research use status. Link back to [../docs/PROJECT_BLUEPRINT.md](../docs/PROJECT_BLUEPRINT.md) or adjust the relative path when copied into a nested folder.

## Folder

- Branch:
- Output folder:
- Parent README:
- Status: ACTIVE / BLOCKED / DEFERRED / SETTLED / PROVISIONAL / SUPERSEDED
- Last updated:

## Decision Context

- Parent A/D/F IDs:
- Claim or decision informed:
- Current research use status: diagnostic only / supports next design decision / research building block / ready for production pipeline / superseded / do not use
- Production boundary:

## Load-Bearing Outputs

| Artifact | Created by | Contents | Use status | Caveat |
|---|---|---|---|---|
| `artifact.ext` | `script_or_manual_step` | Short description. | diagnostic only | State limits. |

## Non-Load-Bearing / Scratch Outputs

| Artifact pattern | Contents | Retention rule |
|---|---|---|
| `*.tmp` | Scratch diagnostics. | Delete or ignore unless promoted above. |

## Reproduction

- Inputs:
- Scripts / commands:
- Environment notes:
- Verification performed:

## Graduation / Archive Decision

- Graduation condition:
- Archive condition:
- Next owner / next action:
