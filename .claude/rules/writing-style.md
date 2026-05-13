# Writing Style: Parsimony and Clarity

**Scope: every file this project touches** — paper sections, slides, plan files, session logs, `CLAUDE.md`, `PROJECT_BLUEPRINT.md`, strategy memos, and code comments. There is no carve-out for infrastructure documents. Critics score formal artifacts; for infrastructure files the rule is self-enforced.

---

## The Core Rule

**Use the fewest words that fully convey the idea.** If a sentence works without a word, remove it. If a label works without a qualifier, drop it.

---

## Specific Rules

### Labels and Names

- Prefer plain English over coded shorthand. Write "private loans only" not "D5-op private-vs-all-loans."
- Decision codes (D-numbers, F-links, A-entries) are index keys, not labels. They may appear as index keys in tables and logs, but every row or entry that uses one must carry a plain-English description alongside it. The description is the primary label; the code is the reference key.
- When a code appears in running text, append a one-phrase gloss: "D16 (production margin)" not bare "D16."
- Row headers in tables — including blueprint tables — must use plain English: "Private loans only" not "D5-op private-vs-all-loans."

### Sentences

- One idea per sentence.
- Cut throat-clearing openers: "It is worth noting that…", "As we can see…", "In this section we…"
- Cut hedging that adds no information: "relatively", "somewhat", "in some sense", "to a certain extent."
- Prefer active voice. "The instrument shifts employment shares" beats "Employment shares are shifted by the instrument."

### Documents and Memos

- State the conclusion first, then the evidence. Never bury the finding.
- Each paragraph has one job. If you can't name its job in four words, split it.
- Section headers should be noun phrases that tell you the answer, not the topic: "Composition effects dominate volume" beats "Results."

### Technical Labels in Code Comments and Specs

- Name variables and columns for what they measure, not for the decision that created them: `bndes_share_private` not `D5_private_loan_spec`.
- Spec-engine dimension names should be self-explanatory: `instrument_weight` not `iw_dim`.

---

## What Critics Check

| Agent | Check | Deduction |
|-------|-------|-----------|
| writer-critic | Bare decision codes in prose without gloss | −2 per instance |
| writer-critic | Throat-clearing or filler sentences | −1 per sentence (max −5) |
| writer-critic | Paragraphs with more than one job | −2 per paragraph |
| storyteller-critic | Slide titles that name topics instead of answers | −2 per slide |
| coder-critic | Variable names that encode decision codes instead of measurement concepts | −1 per variable (max −5) |

---

## The Test

Read the output aloud. If any phrase sounds like it was written for an index rather than a reader, rewrite it.
