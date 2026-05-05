Date: 2026-04-30

## AR Test: Conceptual Framework

BNDES private loans can influence municipal GDP through two distinct channels:

1. **Composition channel** — the allocation of credit across sectors within a municipality (the channel of interest).
2. **Volume channel** — the overall amount of credit flowing to firms in a municipality.

The objective is to isolate the composition (allocation) effect by sweeping out the total volume effect. Both sets of variables are endogenous, which raises the question of how to cleanly identify the composition channel.

## Core Question

What is the best approach to identify the composition channel when both the sector-share variables and aggregate municipality-level disbursements are endogenous?

## Proposed Alternatives

1. **Pure AR test (OLS)** — regress GDP on the endogenous BNDES sector share variables and the endogenous municipality-level total disbursements, with no instrumentation.
2. **Partial IV** — instrument for the endogenous BNDES sector shares but leave aggregate municipality-level disbursements as an endogenous control.
3. **Full IV** — instrument for both the BNDES sector shares and the municipality-level total disbursements.
4. **Mixed** — use the OLS AR test for sector share variables while instrumenting for municipality-level total disbursements.

## Sector Classification

Size-based bins (by initial employment within municipality or country) are the baseline approach:
- Equal-size bins (by number of observations) are preferred for statistical power.
- Align with how BNDES itself classifies firm sizes — use that as the primary grouping.
- A reasonable starting cut: 1–3, 4–10, 11+ employees; at minimum 3+ groups.

Additional margins to explore:
- Export-orientation as a sector classifier — research feasibility.
- Other firm-level margins available in BNDES data.
- Crosses of feasible classifications (e.g., industry × size × export category).

## Technical Notes

When running the AR test:
- Report the coefficient and significance of the exposure control.
- Include BNDES total amount as a control (loans / initial GDP) or instrument for it using the sum of the sector-specific instruments.
- When instrumenting, include first-stage results to assess instrument strength across specifications.

## Action Items

- Prepare a document explaining step by step how the instruments are constructed.
