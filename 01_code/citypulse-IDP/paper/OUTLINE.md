# Paper Outline

**Working title:** *Explaining the Detour: On-Device Confidence-Aware Hazard Routing with
Verified Natural-Language Rationales*

**Target:** SIGSPATIAL ARIC / GeoAI workshop or ISCRAM (first), then IEEE ITSC or SIGSPATIAL
Applications track. Not a methods venue — see `research/SYNTHESIS.md` §7.

**The spine:** the contribution is the *measurement*, not the system. Two numbers carry the
paper — the explanation verification pass rate (Study 3) and the confidence calibration curve
(Study 2). Every section should be serving one of them.

---

### 1. Introduction
The gap: hazard information exists but does not reach the driver heading toward it; maps give
a route but never a reason; and every AI-assisted system fails at the moment the network does.
State the contribution list from §7 of the synthesis — narrowly, without inflation.
*Evidence needed: none. Do not overstate here; the rest of the paper has to cash it.*

### 2. Related work
Four threads, each with an explicit "and here is what remains": hazard-aware and flood-aware
routing (incl. the IBM and Uber patents and TomTom's shipped product) · trust and temporal
decay in crowdsourced geodata · on-device inference and small language models · explanation
in navigation. **Concede prior art plainly.** A reviewer who finds TN-ALERT or US10563994B2
before we cite it will reject the paper.
*Source: `research/raw/E-prior-art-evaluation.md`, `raw/A`, `raw/D`.*

### 3. Problem formulation
Graph, hazard belief, decay, the pessimistic plug-in, the cost function, the chance
constraint. Include the argument that the common multiplicative form is risk-seeking under
ambiguity — this is a genuine and easily-communicated point.
*Source: `raw/A` §5, `raw/D`.*

### 4. System
Offline-first architecture, the decision trace, the two explanation tiers and the symbolic
verifier. Keep it short — it is context for the evaluation, not the contribution.
*Figure: the architecture diagram from `docs/ARCHITECTURE.md`.*

### 5. The ALT-admissibility property
Short formal section: the hazard cost is bounded below by free-flow time, so free-flow
landmark potentials stay admissible under any hazard configuration; preprocessing never
re-runs. **Verify this rigorously before writing it.**
*Evidence: proof + an empirical check that no ALT-guided query returns a suboptimal path.*

### 6. Evaluation
Studies 1–5 per `docs/EVALUATION.md`. Lead with calibration and faithfulness, not with route
quality.
*Key figures: Pareto frontier (safety violations vs unnecessary detours) · reliability diagram
stratified by report age and hazard class · verification pass rate by tier and by device ·
connectivity-ladder degradation curve · appropriate-reliance bars.*

### 7. Limitations
Written honestly and early, not as a defensive afterthought.
- **No live street-level inundation depth exists for Chennai.** We fuse a high-resolution
  static prior with coarse live forcing and user reports. Say it plainly.
- Single city, single monsoon season, one device class.
- Human study n ≈ 40, convenience sample of students — not emergency responders.
- The SLM is a rewriter, not a reasoner; we do not claim on-device reasoning.
- **(Added 2026-09-12 review.) The ALT-admissibility result depends on an implementation
  invariant (`δ ≥ 1`, `v_free(e) ≤ v_safe(0)`), not on Pregnolato's function alone** — state
  this as an enforced design constraint, not a physical inevitability. Report §5 the way
  ADR-003 now does: as consistency, not merely admissibility, but bounded by that invariant.
- **The basin-escalation mechanism reports a computed point-per-corridor count, not an
  assumed one.** If T-W1 could not actually compute a reservoir-to-corridor mapping in time,
  say so and describe the basin labelling as descriptive only, not predictive.
- **The Michaung (4 Dec 2023) replay corpus is corroborated by press reporting, not by an
  official GCC advisory record with closure timestamps.** State the actual source and its
  precision limits rather than presenting it as ground truth.
- **HazardObservation records are coarsened after 30 days (ADR-010), not permanently
  full-precision** — state this as the project's DPDP posture, and report the retention
  design as a contribution of the systems work, not hide it as an implementation detail.

### 8. Deployment economics
A 1 000-user pilot costs ≈ ₹10 700/month, of which ≈78% is the cloud LLM API cost (corrected
2026-09-12 — output tokens alone are roughly half the total; the ">90% output tokens" this
section previously stated didn't match its own source derivation). On-device inference is
what makes civic-scale deployment affordable, not merely robust. **This reframes the offline
component as an equity and affordability argument** — the strongest version of this paper for
an ICT4D audience.
*Source: `raw/G` §12 — recompute this from the primary derivation before it enters the paper,
do not restate the corrected percentage as new fact without re-checking it.*

### 9. Conclusion

---

## Figures to produce (build the scripts to emit these directly)
1. Architecture diagram
2. Belief/decay curves per hazard class, with real Chennai fitted constants
3. Pareto frontier, λ and z swept
4. Reliability diagram, stratified
5. Verification pass rate: cloud vs on-device vs template
6. Connectivity-ladder degradation
7. Appropriate reliance from the human study

## Writing rules
- Every number traces to a script in `scripts/` and a directory in `data/results/`.
- Every related-work claim carries a verified URL from `research/raw/`.
- No sentence claims live flood-depth sensing.
- No sentence says the on-device model produces route geometry.
