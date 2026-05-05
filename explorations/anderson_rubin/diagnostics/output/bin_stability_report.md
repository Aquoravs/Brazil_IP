# Bin Stability Pre-Exercise (E0) — Report

Generated: 2026-05-04 (from CSVs after sprintf-fix; full re-run pending).

## Goal

Measure bin migration across Options A4 (4-bin BNDES native), A3 (3-bin collapse),
and B (within-(cnae_section, cycle) tertiles) over the 7 election cycles 2005–2017.
Determines whether the cycle-baseline construction is necessary or can be replaced
with a simpler lifetime-mean rule.

**F0 link:** Bin stability is a precondition for justifying the cycle-baseline rule
in `docs/PROJECT_BLUEPRINT.md` §3 F0.

---

## 1. Top-Line Numbers

- **Fall-back rate:** **47.30%** of (firm × cycle) cells filled by the fall-back rule.
  This is large and load-bearing — see §4.

| Option | Multi-cycle firms | Ever changed | Share changed | Skip-bin moves (A4) | Boundary noise (A4) |
|--------|------------------|-------------|--------------|--------------------|--------------------|
| **A4** | 5,528,577 | 538,795 | **9.7%** | 7,225 | 63.3% of movers |
| **A3** | 5,532,991 | 96,147 | **1.7%** | — | — |
| **B**  | 5,533,071 | 1,885,764 | **34.1%** | — | — |

A4 movers split: **343,448 up-moves**, **220,397 down-moves**. Skip-bin moves
(|Δbin| ≥ 2) are 7,225 — only **1.28%** of all A4 moves. Migration under A4 is
overwhelmingly between adjacent bins.

**Boundary noise under A4 is high: 63.3%** of A4 movers cross a threshold by
≤ 2 employees at one of the two cycle endpoints. A large share of A4 migration
is small absolute movements at category edges, not real firm-size change.

---

## 2. A4 Transition Matrix (aggregate across all consecutive cycle pairs)

Rows = bin in cycle c, columns = bin in cycle c+1. Diagonal = stayers.

| From \ To  | Micro      | Pequena   | Média   | Grande |
|------------|-----------:|----------:|--------:|-------:|
| **Micro**   | 28,964,740 |   272,244 |   2,999 |    145 |
| **Pequena** |    178,211 | 2,754,502 |  60,946 |    122 |
| **Média**   |      3,746 |    35,118 | 465,079 |  6,992 |
| **Grande**  |        101 |       112 |   3,109 | 56,568 |

Diagonal share (stayers as a fraction of all consecutive-cycle observations) is
overwhelming for every starting bin. The dominant off-diagonal cells are
adjacent moves: Micro↔Pequena and Pequena↔Média. Skip-bin transitions are
rare and small in count.

---

## 3. Cross-Rule Consistency

Multi-cycle firms (any option): **5,533,072**

- Stable under **all 3** options: **3,319,626** (≈60.0%)
- Stable A4 but not B: **1,670,130** (absolute level stable; relative rank
  shifted — reflects peer-composition change, not firm-size change)
- Stable B but not A4: **323,204** (rank stable; firm crossed an absolute
  threshold while its sector grew with it)
- Stable A3 but not A4: **442,674** (move was within the Micro/Pequena
  boundary; the A3 collapse absorbs it)

A3 is much more stable than A4 because almost all A4 migration is at the
Micro↔Pequena boundary, which A3 collapses. B is more migratory than A4
because B reflects sector-relative rank rather than absolute level.

---

## 4. Critical caveat — the fall-back is doing a lot of work

47.3% of (firm × cycle) cells are filled by carrying the firm's mean_emp
forward (LOCF) or backward (NOCB) from a neighbouring cycle. By construction,
filled cells inherit the source cycle's bin value, so they **mechanically
contribute zero migration** for the firm. The headline 9.7% under A4 is an
underestimate of what migration would look like if every firm appeared in
every baseline window.

A fairer reading restricts to firms with *observed* (non-fall-back) bins in
≥ 2 cycles. That number is not in the current CSVs. **Recommend: a follow-up
run that reports `share_firms_ever_changed` on the observed-only subset
before committing to the lifetime-mean rule.**

The 63.3% boundary-noise share reinforces this: even of the migration we do
see under A4, most of it is small absolute movements at category edges —
i.e., the kind of churn that is more measurement noise than real growth.

---

## 5. Recommendation

Under the literal 20% threshold, A4's 9.7% migration rate is below the cut,
which would point to a **lifetime-mean rule** for the production margin.

Two reasons not to act on this verdict mechanically:

1. The fall-back rate (47.3%) means the headline number is depressed by
   construction. The true migration rate among firms observed in multiple
   baseline windows is likely materially higher.
2. Under A3 (the more interpretable collapse), migration is only 1.7% even
   without correcting for fall-back — A3 is functionally constant per firm.
   If A3 ends up being the production margin (E2 escalation path), the
   cycle-baseline overhead is unjustified for that option specifically.

**Action item for the user:** decide between two paths before E1.

- **Path A (proceed with cycle-baseline rule, keep current plan).**
  Defensible: under A4, 9.7% is non-trivial; under B, 34.1% migration confirms
  that within-sector rank shifts are real and the cycle structure matters.
  The fall-back inflation does not change the qualitative picture for B.
- **Path B (switch to lifetime-mean variant).** Defensible if you accept the
  A4 headline at face value and view A3 as the likely production winner.
  Requires re-running E1–E3 with lifetime-mean inputs.

Pending your decision, I recommend **Path A**: proceed to E1 with the
cycle-baseline rule as written, and surface this caveat in §4 of the final
synthesis. The Option-B evidence (34.1% migration, 29.1% in 2 distinct bins,
5.0% in all 3) is sufficient to justify keeping the cycle structure even if
A4 alone would not.

---

## 6. Files Written

| File | Description |
|------|-------------|
| `bin_stability_A4_distribution.csv` | n_distinct_bins distribution (A4) |
| `bin_stability_A4_transitions.csv` | Consecutive-cycle transition matrix (A4) — long format |
| `bin_stability_A3_distribution.csv` | n_distinct_bins distribution (A3) |
| `bin_stability_A3_transitions.csv` | Consecutive-cycle transition matrix (A3) — long format |
| `bin_stability_B_distribution.csv` | n_distinct_bins distribution (B) |
| `bin_stability_B_transitions.csv` | Consecutive-cycle transition matrix (B) — long format |
| `bin_stability_summary.csv` | Summary: one row per option, key metrics + flag |
| `bin_stability_report.md` | This file |
