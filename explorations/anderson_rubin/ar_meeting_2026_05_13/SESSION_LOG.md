# Session Log — AR Meeting 2026-05-13 branch

## 2026-05-13 — branch created

**Operations:**
- Created `explorations/anderson_rubin/ar_meeting_2026_05_13/{R,output}` and `journal/meetings/2026-05-14/build`.
- Wrote README.md and SESSION_LOG.md.

**Decisions:**
- Variant F (pre-earliest-election window) + Variant A (muni-relative owner share) is the primary spec for this run. Channels = {M, M·P, M·G, M·G·P}.
- Taxonomies = {policy_block (K=4), size_bin (K=3)}; size_bin labels MPME / Média / Grande for level 1 / 2 / 3.
- Channels use coalition-aligned shifts: align_mayor_coalition (M), align_mayor_pres_coalition (M·P), align_mayor_gov_coalition (M·G), align_triple_coalition (M·G·P).
- Hold-out = highest-mean-share sector per taxonomy (matches `02_ar_test_emp_share.R`).

**Status:**
- Pending: implement scripts 00 → 05, run regressions, compile slides.
