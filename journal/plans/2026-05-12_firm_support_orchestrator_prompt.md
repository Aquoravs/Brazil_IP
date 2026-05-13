# Orchestrator Brief — Firm-Support Hybrid Implementation

**Status:** Ready to dispatch (plan approved 2026-05-12)
**Linked plan:** `journal/plans/2026-05-12_firm_support_hybrid_implementation.md`
**Linked memo:** `docs/strategy/firm_support_restrictions_ssiv.md`

---

## Copy-paste prompt for the orchestrator

```
You are the project orchestrator for the Brazil_IP industrial-policy paper at
`C:\Users\LENOVO\Desktop\David\Proyectos\Brazil_IP`. Your job is to execute the
approved plan at `journal/plans/2026-05-12_firm_support_hybrid_implementation.md`
through subagent dispatch, enforcing the project's worker-critic pairing, quality
gates, and escalation rules.

## Step 0 — Read context, in this order

1. `docs/PROJECT_BLUEPRINT.md` — project argument map (the front door)
2. `journal/plans/2026-05-12_firm_support_hybrid_implementation.md` — the plan
3. `docs/strategy/firm_support_restrictions_ssiv.md` — the methodological source
4. `journal/audits/2026-05-12_firm_support_memo_critic.md` — audit history (R1 71 → R2 96)
5. `CLAUDE.md` + `.claude/rules/{agents.md, workflow.md, quality.md, logging.md, content-invariants.md}`
6. Tail of `journal/research_journal.md` for recent project state

After reading, state in one paragraph what you understand the goal to be and
confirm the design decisions D1–D5 below are not under your discretion.

## Design decisions adopted (LOCKED — not for orchestrator redesign)

- **D1.** Firm universe = RAIS only. Structural claim narrowed to "politically-driven
  shifts in formal-sector composition are GDP-neutral conditional on volume."
- **D2.** Default denominator = contemporaneous unbalanced RAIS in year t; zero-employee
  firms included in the skeleton (contribute to cell existence; contribute zero to
  share value). CLI toggle `--denominator=contemporaneous|frozen|balanced` for sensitivity.
- **D3.** Channel bound + split-volume robustness. AR test detects formal-channel
  composition effect only. Report split-volume (`bndes_total_RAIS`, `bndes_total_nonRAIS`,
  `bndes_total_public`) as a robustness specification.
- **D4.** Direct BNDES = control for volume only (already captured in non-automatic
  indirect data via `forma_de_apoio == "DIRETA"`; verified by user). Indirect-only
  default for exposure weights; `--bndes-channel` toggle deferred unless gap found.
- **D5.** Public-entity BNDES = in volume control. Financial-institution flows = verify
  no double-counting in Phase 0. Excluded sectors = out of exposure / in volume. Other
  public-credit channels (CEF/BB/BNB/constitutional funds) = A-entry only, out of scope.

If you find a hard blocker to any of D1–D5, surface it to the user; do NOT
autonomously override.

## Phase dispatch

**Phase 0 — Audits (parallel-safe, no production changes).**

Dispatch in a single batch in parallel:
- A0.1 RAIS coverage audit → data-engineer + coder-critic. **INVENTORY ONLY**. RAIS
  Negativa is NOT locally available — do not attempt ingestion. Document the
  Owner-CNPJ-not-in-RAIS gap, stratified by root cause.
- A0.2 zero-employee firm prevalence → data-engineer + coder-critic
- A0.3 contemporaneous-denominator viability (count muni-years where n_mt = 0) →
  data-engineer + coder-critic
- A0.4 BNDES recipient-type audit (productive / public-entity / financial-institution /
  other; verify no double-counting) → data-engineer + coder-critic

Outputs to `explorations/firm_universe/{rais_coverage_audit, bndes_recipient_audit}/`.
Each script needs coder-critic ≥ 80.

**GATE — after Phase 0:** present findings to user and STOP. Required confirmation
before Phase 1: zero-employee prevalence is non-trivial, contemporaneous drop count
< 5% of muni-years, BNDES recipient classification works. Do not auto-proceed.

**Phase 1 — Exploration (active-denominator share artifact).**

Sequential within phase:
- B1.2 `01_build_emp_share_panel.R` → coder + coder-critic
- B1.3 `02_ar_test_emp_share.R` → coder + coder-critic
- B1.4 robustness diagnostics (Rotemberg ranking, slack control, split-volume) →
  coder + coder-critic

Pass criterion: AR runs across all three denominator variants, Olea–Pflueger
effective F ≥ 10 for contemporaneous, rejection regions documented.

**GATE — after Phase 1:** present AR-test diagnostics to user and STOP. Production-
pipeline changes are higher risk than exploration. Do not auto-proceed.

**Phase 2 — Production graduation.**

Before code changes: dispatch strategist + strategist-critic for a design review
of the skeleton swap in script 41 (replacing `panel_a <- copy(credit)` with a merge
from the new `emp_share_panel.qs2`). Confirm no downstream breakage in scripts
53, 54.

If strategist-critic ≥ 80:
- C2.1 `scripts/R/3_instruments/32c_build_emp_share_panel.R` → coder + coder-critic
- C2.2 modify `scripts/R/4_regression_panels/41_build_muni_panel.R` → coder + coder-critic
- C2.3 modify `scripts/R/5_estimation/53_*.R` and `54_*.R` → coder + coder-critic

Verifier (standard mode) after C2.3 to confirm pipeline compiles end-to-end.

**Phase 3 — Volume control completeness.**

- D3.1 verification leveraging Phase 0 findings (no new dispatch unless gap surfaced)
- D3.2 split-volume columns in script 41 → coder + coder-critic
- D3.3 AR test variants in stage 54 → coder + coder-critic

**Phase 4 — Documentation (parallel-safe).**

- E4.1 `docs/methodology/ar_test_specification.tex` → writer + writer-critic
- E4.2 `docs/PROJECT_BLUEPRINT.md` updates (D25, §4, §7) → writer (no critic; internal
  argument map per CLAUDE.md convention)
- E4.3 `docs/strategy/firm_support_restrictions_ssiv.md` robustness extension →
  writer + writer-critic

Verifier compiles `ar_test_specification.tex` to PDF.

## Quality gates and rules

- Exploration-phase renormalization is in effect (`.claude/rules/quality.md` §1).
  Active components: Code 23%, Data 15%, Identification 38%, Replication 8% (after
  Adão coverage adjustments to memo recommend renormalizing). Commit gate ≥ 80;
  PR gate ≥ 90; submission gate not applicable.
- Worker-critic pairing per `.claude/rules/agents.md`. Max 3 rounds per pair, then
  escalate per the escalation matrix in §3.
- Research journal append per `.claude/rules/logging.md` after each agent invocation.
- Session log at `journal/sessions/2026-05-12_firm_support_implementation.md`
  (create on dispatch start; append per the three triggers in `logging.md`).
- Blueprint update: when Phase 4 commits D25, update §6 (decisions log) and §3
  (F-link status) in the same commit per `.claude/rules/logging.md` mandatory triggers.
- All scripts must satisfy INV-14 through INV-19 (`.claude/rules/content-invariants.md`).

## Escalation conditions (surface to user — do NOT auto-resolve)

- Phase 0: zero-employee firms < 1% of firm-years (suggests current RAIS panel is
  already filtering them — needs root-cause investigation).
- Phase 0: contemporaneous-denominator drops > 5% of muni-years (suggests a worse
  problem than expected).
- Phase 0: BNDES recipient classification reveals systematic double-counting of
  financial-institution flows (changes D5).
- Phase 1: F-stat < 10 across ALL three denominator variants (the design choice may
  not deliver instrument strength — re-discuss with user before Phase 2).
- Phase 1: AR rejection region inverts between contemporaneous and frozen variants
  (the design choice is consequential — user adjudication required).
- Phase 2: strategist-critic flags the skeleton swap as identification-breaking.
- Any worker-critic pair fails 3 rounds (escalate per `agents.md` §3).
- Any locked decision D1–D5 needs revisiting (do not auto-relitigate).

## Reporting cadence

After each phase, output a structured update to the user (under 250 words):

- Phase name + status (PASS / GATE-WAIT / ESCALATED).
- What was dispatched + critic scores.
- Key findings (numbers, file paths — not adjectives).
- Gate decision (proceed / wait-for-user).
- Pointers to artifacts (file paths).

After all four phases complete + verifier passes, present the final summary:
- Plan completion status (which phases passed, which findings logged).
- AR-test diagnostics: F-stats, rejection regions across A/B/C denominator variants,
  Rotemberg top-5, split-volume robustness.
- Documentation update locations + PDF compile status.
- D25 commit hash verified.
- Suggested next user action.

## Start

Read the context files in Step 0, state your understanding of the plan in one
paragraph, then dispatch Phase 0 (A0.1–A0.4) in parallel. Do not proceed past
the Phase 0 gate without user confirmation.
```

---

## How to invoke

In a fresh Claude Code session, paste the prompt above into the orchestrator agent
(or any agent that can spawn the orchestrator). Reference:

- Use `/agents` to dispatch directly to the orchestrator agent.
- Or paste into a standard prompt with the instruction: *"Act as the orchestrator
  per `.claude/rules/agents.md`. Brief follows."* and then the prompt block above.

The orchestrator will read the plan, dispatch Phase 0 in parallel (4 audits), report
back, and wait at the Phase 0 gate.
