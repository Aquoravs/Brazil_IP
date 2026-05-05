# Logging

## Session Logs

Individual session logs saved to `logs/session_logs/YYYY-MM-DD_description.md`.

### Three Triggers (all proactive)

**1. Post-Plan Log**
After plan approval, immediately capture: goal, approach, rationale, key context.

**2. Incremental Logging**
Append 1–3 lines whenever: a design decision is made, a problem is solved, the user corrects something, or the approach changes. Do not batch.

**3. End-of-Session Log**
When wrapping up (user says goodbye, plan was implemented, or before context compression): high-level summary, quality scores, open questions, blockers.

### Entry Format

```markdown
## YYYY-MM-DD HH:MM — [Brief Title]

**Operations:**
- [Scripts run, files created/modified/deleted]

**Decisions:**
- [Choice made] — [rationale]

**Results:**
- [Key findings, outputs produced]

**Commits:**
- `[hash]` [commit message]

**Status:**
- Done: [what's complete]
- Pending: [what remains]
```

### Rules

- One file per session, named by date and topic
- Append-only within a session — never overwrite earlier entries
- Include file paths and commit hashes when available
- If context compression hits mid-session, the incremental entries already capture the important decisions

---

## Quality Reports

Generated only at merge time — not at every commit or PR. Save to `logs/merges/YYYY-MM-DD_[branch-name].md`.

---

## Research Journal

Append to `logs/research_journal.md` whenever an agent completes work — writing code, drafting a section, producing a review, making an editorial decision, or transitioning between phases.
**Rules:** Append only. One entry per agent invocation. Include phase transitions and editorial decisions.

**Entry format:**
```markdown
### YYYY-MM-DD HH:MM — [Agent Name]
**Phase:** [Discovery/Strategy/Execution/Peer Review/Presentation]
**Target:** [file or topic]
**Score:** [XX/100 or PASS/FAIL or N/A]
**Verdict:** [one line — key finding or decision]
**Report:** [path to full report]
```
**Why it exists:** Agents read this to understand pipeline state — the editor checks what strategist-critic scored, the orchestrator checks which phases passed, the coder-critic checks what the coder built. It's the shared context across agents.

Agent outputs (reports, scripts, memos, decisions) are saved to `logs/` by the skills that produce them.

---

## Blueprint updates

The project's argument map at [`docs/PROJECT_BLUEPRINT.md`](../../docs/PROJECT_BLUEPRINT.md) is updated **in the same commit** as the work that triggered the update. The blueprint is the front door (`workflow.md` §5 Session Recovery step 0); failure to update breaks the document for the next session and is a process violation, not just a hygiene lapse.

**Mandatory triggers:**

- **New idea or angle** mentioned in any session → row in §4 (open angles register), with an A-number assigned. No exceptions; even half-formed ideas get an A-entry.
- **F-link status changes** (any element of F0–F4 moves between OPEN / UNDER TEST / PARTIAL / CONFIRMED / BLOCKED / PAUSED) → update §3 + add a one-line D-entry in §6.
- **Decision made** → entry in §6 (decisions log), append-only, D-numbered.
- **A-entry closed** (done, abandoned, superseded) → strike through with date and reason in §4. Do not delete (auditability).
- **Branch starts/closes** in `explorations/` → update §5.
- **Next action started or completed** → update §7 with the new actionable item. §7 is always concrete, never aspirational.

**Promotion rule:** an A-entry whose result reshapes the identification chain → promote to a new F-link in §3, with a D-entry in §6 recording the promotion.

**Coordination with `research_state.md`:** the blueprint is the *argument map* (load-bearing claims with status); `docs/research_state.md` is the *state catalog* (taxonomies, design decisions, findings). A taxonomy change goes in `research_state.md`. A decision that changes the argument goes in the blueprint. Operational decisions D1–D11 in `research_state.md` §3 are not duplicated in the blueprint; new framing decisions D12+ live in the blueprint §6.