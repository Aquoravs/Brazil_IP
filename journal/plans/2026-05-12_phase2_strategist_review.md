# Phase 2 Strategist Review — Production Graduation of the AR Test

**Date:** 2026-05-12
**Reviewer:** strategist (paired critic: strategist-critic)
**Phase:** Strategy gate before Phase 2 dispatch (production-pipeline edits)
**Source plan:** `journal/plans/2026-05-12_firm_support_hybrid_implementation.md`
**Source memo:** `docs/strategy/firm_support_restrictions_ssiv.md` (R2 96/100)
**Phase 1 artifact:** `explorations/anderson_rubin/active_denominator/` (B1.2 + B1.3 complete)
**Blueprint:** `docs/PROJECT_BLUEPRINT.md` (D28 production-margin status)

---

## A. Skeleton swap design (load-bearing change at script 41 line 508)

**Proposed change:** replace `panel_a <- copy(credit)` with merge against `emp_share_panel.qs2` (output of new script `32c_build_emp_share_panel.R`, promoted from Phase 1 artifact `R/01_build_emp_share_panel.R`).

**Identification-preserving?** Yes, subject to one binding condition. The hybrid memo (§Recommendation, pillar (i)) explicitly authorises this construction: the AR pivot inverts on the *realised* share vector $s^{\text{emp}}_{jmt}$, which by design must include post-election entry/exit because that churn is the channel through which the political shock can hit GDP. The instrument $z_{m,e(t)}$ continues to be built on the frozen $[e(t)-4, e(t)-1]$ exposure window (script 33, unchanged), so the GPSS predetermined-share logic is preserved on the instrument side. The skeleton swap touches only the endogenous variable.

**Binding condition (memo operational note ii, BHJ §4.4):** the slack control — share of $n_{mt}$ accounted for by frozen-baseline firms — must travel with the swap. Phase 1 B1.4 confirmed the slack is non-binding empirically (≤0.03 F shift), but it must remain in the production specification as a checkbox, not be silently dropped during the migration. Confirm the merge in script 41 carries the per-cell slack series (already produced by Phase 1's `output/slack_per_cell_contemporaneous.csv`).

**AR-pivot interpretation at the policy_block margin:** the AR pivot is margin-invariant in the sense that it tests $H_0:\beta = 0$ on whatever sector partition is fed to it. Moving from cnae_section (K = 20) to policy_block (K = 4) reduces the dimensionality of $\beta$ from 20 to 4, sharpens the economic interpretation (Agro/Ind/Infra/Serv are the BNDES policy levers, per script 30e's institutional logic), and reduces the many-instruments risk per Mikusheva–Sun (2022). The null is still GDP-neutrality of politically-driven composition shifts; the partition is coarser.

**Margin-invariance of the Phase 1 diagnostics:** **NOT margin-invariant.** Rotemberg-weight ranking, drop-top-5 reruns, and per-sector pre-trends are partition-dependent by construction. At cnae_section, top-5 drop survived at 1%; at policy_block with K = 4, "drop top 5" is undefined (there are only 4 blocks). Phase 2 must therefore re-run the Phase 1 diagnostics at the new margin: drop-top-1 and drop-top-2 Rotemberg substitutes, per-block pre-trends, slack control on/off. Authorize this as a mandatory Phase 2 sub-task, not a "Phase 3 polish".

## B. Margin choice — policy_block primary, cnae_section robustness

**Confirm policy_block as primary?** Yes, conditionally. The user directive (2026-05-12) defers `policy_block × S3` (blueprint §F1 top candidate) to a later task. Pure `policy_block` is the only available graduate target that (i) has a built crosswalk (script 30e exists, verified above), (ii) sits inside the F0-admissible firm-side margin set per `feedback_ssiv_margin_admissibility.md`, and (iii) is the institutional partition BNDES itself uses for its lending divisions. The K = 4 dimensionality is small but defensible: with n_offices = 3 (M/G/P) and n_alignment = 1 (signed exposure), the AR test has K ≈ 12 instruments, well above just-identified and well below the Mikusheva–Sun many-weak regime. Phase 1's MGP F = 19.98 was at K = 57; the policy_block F-stat at K = 12 may rise (less attenuation from weak instruments) or fall (less variation). This is an empirical question — Phase 2 must report it.

**Power concern:** the strategist-critic should flag the risk that with K = 4 the test loses cross-sectoral resolution. However, the memo's pillar (iii) explicitly endorses smaller K as a hedge against the many-weak regime; the policy_block partition was vetted by D16 and the user. Defensible at this stage.

**cnae_section as side-by-side robustness:** **REQUIRED.** Without it, the Phase 2 graduate has no way to demonstrate that the policy_block result is not an artifact of K = 4 dimensionality. Phase 1 already produced the cnae_section AR-test grid (`output/ar_test_summary.csv`); Phase 2 should preserve that comparison by running both partitions through the production pipeline via the existing `--sector-var` CLI flag in scripts 53/54. This is the same flag pattern already documented in `CLAUDE.md` (sector pipeline). Cost is small (one extra pipeline pass); benefit is the robustness exhibit the memo's R3 list requires.

## C. Carry-over routing

**(1) Section G missing.** Authorize the production-script fix if and only if root cause is in script 41/42 (panel build) and the fix does not alter the frozen exposure window or the firm-support hybrid construction. If root cause is upstream (script 30/30e crosswalk drops G as a residual block, or script 22 reconstruction filters it out), data-engineer must report before any edit — this is the boundary between "panel hygiene fix" (authorize) and "margin redefinition" (escalate). Default routing: authorize the diagnostic, gate the fix on the root-cause memo.

**(2) Pre-trend reformulation.** The Phase 1 B1.4 "contemporaneous-on-contemporaneous" pre-trend is not a proper τ-baseline test; it conditions on the outcome window. The proper test (regress pre-period $\Delta y_{m,\tau}$ or $s_{jm,\tau}$ on the realised election-cycle shock $Z_{m,e(t)}$ for $\tau < e(t)$) is GPSS §4.2 / BHJ §4 standard practice and the memo's robustness list (item 4: 2002-fixed vs cycle-specific baseline contrast) implicitly assumes it. Route this as a **Phase 1 extension run before Phase 2 dispatch**, not deferred to Phase 4. Reason: if the proper pre-trend test rejects on the high-Rotemberg-weight sectors at cnae_section, the policy_block migration would inherit the violation, and we would graduate a contaminated identifying assumption. Cost is one additional Phase 1 script (~2 hours); risk-reduction is large.

**(3) FI volume coefficient.** The −0.105 coefficient on a 0.10%-of-disbursement subaggregate is almost certainly a small-N leverage artifact (n FI-borrowers = 31–42 per Phase 0 A0.4). Defer the full split-volume cell-count diagnostic and winsorized rerun to Phase 3 (where script 41 builds split-volume columns), but require a one-page leverage check in Phase 2 — count of non-zero `bndes_total_nonRAIS` cells by year, and a Cook's-distance / DFBETA summary on the FI subset. This is a 30-minute diagnostic, not a phase-blocking task. Do not let the −3 t-statistic on a 0.1% channel acquire a life of its own in the writeup.

## D. Identification-breaking risks (three-strikes gate per `.claude/rules/agents.md`)

I see **no identification-breaking risk** in the Phase 2 graduation as currently scoped, provided:

- (i) Frozen exposure weights $w_{jm,\tau}$ on $[e(t)-4, e(t)-1]$ remain untouched (script 33 — out of Phase 2 edit scope).
- (ii) The contemporaneous-skeleton endogenous variable $s^{\text{emp}}_{jmt}$ travels with the BHJ §4.4 slack control (script 41 must carry the slack column).
- (iii) The CNPJ entry/exit caveat (memo operational note ii) is documented in script 41's header and the methodology PDF (Phase 4) — not silently inherited.
- (iv) Rotemberg / drop-top diagnostics are rerun at the policy_block margin (not assumed margin-invariant — see §A).
- (v) Pre-trend reformulation lands before Phase 2 dispatch (see §C item 2).

If (v) is dropped — i.e., Phase 2 dispatches without the proper pre-trend test — that is the closest thing to an identification risk in this packet. It does not break identification ex post, but it leaves a load-bearing assumption (no anticipation in pre-election outcome trends conditional on the cycle-specific shock) untested at the new margin. Strict reading of the memo's robustness list requires it; strategist-critic should flag if I weaken this to "deferred".

## E. Authorization decision

**REQUEST CHANGES** before Phase 2 dispatch. Two pre-conditions:

1. **Run the proper τ-baseline pre-trend test as a Phase 1 extension.** Regress pre-period $\Delta y_{m,\tau}$ and $s_{jm,\tau}$ ($\tau < e(t)$) on $Z_{m,e(t)}$ at both cnae_section and policy_block margins. Pass criterion: no systematic rejection on high-Rotemberg-weight sectors/blocks at 5%. Cost: ~2 hours.

2. **Pre-register the policy_block-margin diagnostic rerun as a mandatory Phase 2 sub-task.** Drop-top-1 and drop-top-2 Rotemberg substitutes at K = 4; slack control on/off; per-block pre-trend pass. Not a "Phase 3 polish".

Conditional on both, **AUTHORIZE Phase 2 dispatch at policy_block primary + cnae_section side-by-side robustness**, with the Section G diagnostic running in parallel (data-engineer reports root cause before any production edit beyond script 41 line 508).

The FI leverage check is a 30-minute Phase 2 sub-item, not a blocker. Defer the full split-volume implementation to Phase 3 as originally planned.

No escalation to user required at this gate — the user directive (graduate at policy_block, defer S3) is consistent with the memo and the blueprint, and the requested pre-conditions are within the memo's existing robustness list (items 7, 4 respectively), not new assumptions.
