# Talk Review — Beamer (Diagnostic Slide Deck)
**Date:** 2026-04-05
**Reviewer:** storyteller-critic
**Score:** 72/100 (advisory)
**File audited:** `paper/sections/first_stage.tex`

---

## Issues Found

### ISSUE 1 — `\scriptsize` body text on F-stat grid frames (Frames 2–5)
**Severity: High | Deduction: -12 (-3 per frame)**
In the Madrid theme at `aspectratio=169,10pt`, `\scriptsize` renders at ~7–8pt — below the 10pt projection minimum. The `\tiny` footnotes (~6pt) on those same frames are categorically unreadable at projection distance.

### ISSUE 2 — `\sbox0` box register fragility across 26 `\input{}` frames
**Severity: Medium-High | Deduction: -8**
All 26 table files use `\sbox0{...}` (LaTeX's scratch register). Beamer internals may also use `\setbox0`, causing silent corruption. Fix in Script 51: replace `\sbox0` with a named savebox (`\newsavebox{\mytablebox}`).

### ISSUE 3 — `\scriptsize` / `\tiny` on appendix index frame (Frame 8)
**Severity: Medium | Deduction: -3**
Bullet lists in `\scriptsize`, abbreviation key in `\tiny`.

### ISSUE 4 — `\multirow` + `\addlinespace` spacing inconsistency
**Severity: Low-Medium | Deduction: -5**
`\addlinespace[5pt]` inserts extra space not accounted for by `\multirow` row-counting, causing Coalition/Party cell vertical centering to appear slightly off. A `\midrule` would interact correctly.

### ISSUE 5 — Malformed `\begin{itemize}\small` (advisory)
**Severity: Low | Deduction: 0**
Line 281: `\begin{itemize}\small` — `\small` should precede or wrap the environment. Non-blocking but malformed.

---

## Score Breakdown

| Item | Deduction |
|------|-----------|
| Starting score | 100 |
| `\scriptsize` body: 4 F-stat grid frames | -12 |
| `\scriptsize`/`\tiny` appendix index | -3 |
| `\sbox0` box register fragility (26 frames) | -8 |
| `\multirow` + `\addlinespace` centering | -5 |
| **Final** | **72/100** |

---

## Recommended Actions

1. F-stat grids (Frames 2–5): `\scriptsize` → `\footnotesize`; `\tiny` footnotes → `\scriptsize`
2. Appendix index (Frame 8): `\scriptsize` lists → `\footnotesize`; `\tiny` key → `\scriptsize`
3. Script 51: replace `\sbox0` with `\newsavebox{\mytablebox}` in table generation code
4. F-stat grids: replace `\addlinespace[5pt]` with `\midrule` for correct `\multirow` centering
5. Line 281: change `\begin{itemize}\small` to `{\small\begin{itemize}` with closing `}`
