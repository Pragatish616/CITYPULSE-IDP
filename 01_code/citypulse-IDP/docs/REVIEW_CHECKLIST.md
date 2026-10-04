# Review Checklist

Work through in order. Stop and report at the first item in §1 that fails.

## 1. Research integrity (most important — check first)
- [ ] Does any new text claim live street-level flood depth sensing? **We do not have it.**
- [ ] Does any text imply the on-device model produces route geometry?
- [ ] Is any already-published capability described as novel? Cross-check `research/SYNTHESIS.md` §7.
- [ ] Does every number in a doc or paper draft trace to a script in `scripts/` and a directory
      in `data/results/`?
- [ ] Is every new citation one that someone actually opened? (Only five are human-verified.)
- [ ] Did an experiment result get committed without its generating script or seed?

## 2. Safety direction
- [ ] Does low confidence *increase* caution everywhere it appears? (ADR-002. Check the sign —
      this is the defect most likely to survive a passing test suite.)
- [ ] Is `p̃` clamped to `≤ 1` everywhere the formula is implemented or restated, and is there a
      test that actually exercises the clamp (not just asserts it exists)? (ADR-002, added
      2026-09-12 — this exact omission shipped in three of four documents that state the
      formula until this review caught it.)
- [ ] Is `δ ≥ 1` (equivalently `w_λ(e,t) ≥ τ₀(e,t)`) enforced in code, with a test on a
      sub-87 km/h edge — not just assumed from the physics? (ADR-003, added 2026-09-12 — the
      ALT-admissibility proof is unsound without this.)
- [ ] Is the chance constraint implemented as edge removal, not a large finite weight? (ADR-003)
- [ ] Can an unverified explanation reach the user? It must not. (ADR-004)
- [ ] Does any generated or templated text, or any UI element, assert or imply a road/route is
      *safe* or *passable* in absolute terms? It must not — only relative/confidence-qualified
      statements are allowed. (ADR-011, verifier rule 6, added 2026-09-12)
- [ ] Do raw coordinates or a user id leave the device on any path? (ADR-007)
- [ ] Does any `HazardObservation` retain full-precision geometry or an identifying `source_id`
      past its 30-day coarsening window, or does an erasure request fail to coarsen it
      immediately? (ADR-010, added 2026-09-12)

## 3. Contracts
- [ ] Does the change alter `HazardObservation`, `EdgeBelief`, `DecisionTrace` or the
      verification result? If so, is there an ADR, and were all four consumers updated?
- [ ] Do the golden-file tests still pass, and if they were regenerated, was the diff inspected?
- [ ] Are `observed_at` and `received_at` still distinct?
- [ ] Is `data_gaps` still populated and still surfaced in the UI?

## 4. Reproducibility
- [ ] Seeds pinned. Data snapshots pinned by date. Manifest updated.
- [ ] Does the evaluation harness still call the same router binary the app uses?
- [ ] If belief or cost behaviour changed: were Studies 1–3 re-run and the commit tagged `exp:`?
- [ ] Is any Study 5 (human study) code being run against real participants before IEC approval
      has actually landed — not just been submitted? (T0.3/T6.2, added 2026-09-12 — a
      manipulated-ground-truth design is deception and should not run on a mere submission
      acknowledgement.)

## 5. Ordinary code review
- [ ] Tests written first and failing first; edge cases covered.
- [ ] No invented APIs, endpoints or library versions.
- [ ] Errors handled at boundaries; no silent excepts swallowing feed failures.
- [ ] Formatters clean; no secrets committed; `.env.example` updated if config changed.
- [ ] Nothing written into the user's local directories.

## 6. Scope discipline
- [ ] Is this complexity the project needs? (~10⁵ nodes. No CH, no microservices, no federated
      learning.)
- [ ] Does this task serve one of the five studies? If not, why is it being done in week N?
