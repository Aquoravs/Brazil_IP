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