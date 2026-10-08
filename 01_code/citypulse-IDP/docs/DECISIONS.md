# Architecture Decision Records

Each ADR states the decision, why, what was rejected, and what would make us reconsider.
Evidence lives in `research/raw/`.

---

## ADR-001 — We write our own routing engine

**Decision.** Implement the router ourselves: OSM → CSR adjacency array → bidirectional
A* with ALT landmark potentials over a mutable per-edge hazard array. One implementation, in
Dart, in `packages/pulse_router`, used by both the Flutter client and (via its AOT CLI) the
Python evaluation harness.

**Why.** Chennai's drivable graph is ~10⁵ nodes. Bidirectional Dijkstra at that size is
10–40 ms. CH/CRP exist for 10⁷–10⁸ node graphs; building them here is complexity theatre.
More importantly, our cost function needs a *per-request, per-user-class* pessimism
parameter `z` and a live hazard posterior — no off-the-shelf engine exposes that cleanly.

**Rejected.**
- **OSRM** — no per-request cost model; `osrm-customize` takes ~10 min with a ~20 min
  achievable traffic cadence and no partial recustomization (issue #5503). A product pitched
  on 2-minute-old flood reports cannot sit on it.
- **GraphHopper on-device** — Android offline support is explicitly unmaintained by its own
  maintainer (issue #1940). Server-side GraphHopper `custom_model` is viable but forces a
  second, divergent routing path.
- **Valhalla on-device** — genuinely the best off-the-shelf fit (tiled graph, query-time
  costing), but **there is no Flutter binding** (valhalla-mobile #40); a custom FFI wrapper
  is an unbounded week-1 risk for a 7-week project.

**Reconsider if.** The Chennai graph turns out to be far larger than estimated, or turn-by-turn
voice narration becomes a requirement (Valhalla returns as a stretch goal for narration only).

---

## ADR-002 — Confidence is a Bayesian posterior with a pessimistic plug-in, not a decay multiplier

**Decision.** Fuse reports in log-odds over a static terrain prior with per-hazard-class
exponential decay, then route on the **upper confidence bound**
`p̃ = min{1, p̄ + z·√(p̄(1−p̄)/(n_eff+1))}`. **The `min{1, …}` clamp is load-bearing, not
decoration — see the note below.**

**Why.** The pitch's `w = τ·(1 + λ·R·C)` has the confidence term the wrong way round: as
confidence falls, the penalty falls to zero, so an unverified flood report makes the router
treat the road as clear. That is risk-seeking under ambiguity — the opposite of what an
ambulance needs. With a UCB plug-in, thinner evidence *raises* caution, which is both
correct and directly explainable ("one unverified report, so we routed around it").

**Also fixed.** The brief's worked example is backwards: urban flooding persists for hours,
debris clears in minutes. A single global decay constant will route EMS into standing water.
`T_c` must be per hazard class.

**Stretch.** Replace the exponential with a **Bayesian persistence filter** (Rosen et al.,
ICRA 2016) under a **Weibull** survival prior fitted per hazard class, including
"traversal-silence" as calibrated evidence of absence. The pitched exponential is the exact
observation-free marginal of that model — so the offline fallback becomes a derivation
rather than a hack. That framing is the project's best rhetorical asset; take it if week 5
has room.

**Verified 2026-09-12 (review pass) — the clamp must be stated identically everywhere.**
`docs/GLOSSARY.md`, `research/SYNTHESIS.md` and this ADR previously stated the formula
*without* `min{1,…}`. Concretely, for the `emergency` class (`z = 2.0`,
`config/hazard_classes.yaml`) with a single fresh weak report (`p̄ ≈ 0.7`, `n_eff ≈ 0.5`):
`p̄ + z·√(p̄(1−p̄)/(n_eff+1)) ≈ 1.45` — over 1, a nonsensical "probability," and this is the
*normal* operating point for the class the pessimism argument is built around, not a corner
case. An implementer working from this ADR or the glossary alone (as
`docs/IMPLEMENTATION_PLAN.md`'s "read first" list directs) would ship an unclamped value,
which then corrupts `EdgeBelief.p_pessimistic`'s probability semantics and Study 2's Brier
score (only defined on `[0,1]`) — the paper's own headline calibration metric. **All
restatements of this formula must include the clamp; treat `CLAUDE.md` §6 as canonical and
the others as pointers to it, not independent restatements, to stop this drifting again.**

---

## ADR-003 — Slowdown and harm stay as separate cost terms

**Decision.** `w_λ(e,t) = τ₀·[1 + p̃·(δ−1)] + λ·p̃·s·τ₀`, with a hard chance constraint
`Pr[depth > h_max] ≤ ε` implemented as **edge removal**, not a large finite weight.

**Why.** A flooded road slows you down *and* might harm you; these are physically different
and collapsing them makes `λ` uninterpretable. `δ` comes from Pregnolato et al. (2017)'s
measured depth–disruption function (R² = 0.95) — real physics rather than an invented
multiplier. Keeping everything in seconds keeps `λ` explainable to the NLG layer. Large
finite weights let the search "buy" an impassable road when the alternative is long enough.

**Required invariant — verify before T2.1 is written (added 2026-09-12, review pass).**
CLAUDE.md §6's ALT-admissibility result needs `w_λ(e,t) ≥ τ₀(e,t)` on every edge, which needs
`δ(e,t) ≥ 1` always. Pregnolato's fitted `v_safe(h)` has intercept `v_safe(0) ≈ 87 km/h`, so
`δ = v_free(e)/v_safe(h) ≥ 1` **only if `v_free(e) ≤ v_safe(0)`** — and that does not hold
automatically. A perfectly ordinary Chennai arterial at `v_free(e) ≈ 30 km/h` gives
`δ ≈ 0.35` at zero depth: the hazard-adjusted cost drops *below* free-flow, the exact opposite
of the intended direction, and a silent breach of the admissibility guarantee on the majority
of Chennai's actual road classes (arterial and residential, not highway). **Implementation
must enforce `δ(e,t) = max(1, v_free(e)/v_safe(h(e,t)))` as a defensive clamp**, and T2.1's
test suite must include a case at a sub-87 km/h edge asserting `w_λ ≥ τ₀`. This is a
correctness requirement, not an optimization — do not defer it past T2.1.

---

## ADR-004 — Two-tier explanation: deterministic template always, SLM as a verified rewriter

**Decision.**
- **Tier 0** — a deterministic template renderer over the router's structured decision trace.
  Runs always, costs <1 ms, is 100% faithful, and is the permanent fallback.
- **Tier 1** — an on-device small language model acting **only as a rewriter**, never as a
  fact source, whose output must pass a symbolic verifier (every numeral and named entity
  must appear in the fact set) or be silently discarded in favour of Tier 0.

**Why.** Every content word in *"Route A is 4 minutes slower; it avoids a flooded underpass
reported 3 minutes ago"* is already a field in the router's output. This is surface
realisation over a closed domain. On the target hardware the SLM needs ~5.5 s and 0.5–1.7 GB
to say what a Dart function says in under a millisecond, for free, with perfect fidelity.
Small models hallucinate 5.7–7.4% even on grounded summarisation (Vectara HHEM), and
quantization adds up to 4.4% explanation-quality loss that LLM-as-judge fails to detect.

**The payoff.** The **verification pass rate becomes the paper's headline metric** — a more
publishable contribution than "we ran a quantized model on a phone."

**Model + runtime.** Gemma 3 270M IT, INT4-QAT, LoRA-tuned, via LiteRT-LM through
`flutter_gemma` (~250 MB resident, survives Android backgrounding; ~0.75% battery per 25
generations). Secondary arm for the capability comparison: Gemma 4 E2B (Apache 2.0).
Licence-clean baseline: Qwen3 0.6B on llama.cpp with GBNF constrained decoding.
Avoid MediaPipe (maintenance-only), MLC-LLM (1.1–1.8 tok/s decode, 4.2 GB), ExecuTorch and
NPU delegation (no time; flagship-only).

---

## ADR-005 — Offline-first, not offline-fallback

**Decision.** The client **always** computes the route locally from cached tiles, graph and
hazard state. The cloud is a deadline-bounded enrichment channel (~1.2 s budget), never a
dependency.

**Why.** The pitch's "fallback the millisecond a connection drop is detected" is not
implementable: no such signal exists for captive portals, stalled cellular or slow servers;
`connectivity_plus` reports interface state, not reachability. Offline-first is both
buildable and a *stronger* claim than a fast fallback.

**Consequences.** Storage budget ≈ 350–420 MB with the model, 100–170 MB without (**routing
graph, CSR + ALT** ~15–22 MB — this is our own data structure, not a Valhalla tile format;
see `docs/ARCHITECTURE.md`'s storage table — PMTiles z0–14 ~35–50 MB, Gemma 3 270M Q4_K_M
~250 MB per a third-party GGUF conversion [unverified against Google's own release — see
`research/SYNTHESIS.md` §9], hazard cache ~3 MB live / ~14 MB weekly, app binary ~40–70 MB).
All Tamil Nadu ≈ 750 MB–1 GB. **The model is the biggest line item, so ship template NLG as
the baseline and make the SLM an optional download.** Redis cannot expire individual geo-set
members — the decay sweeper needs a parallel ZSET.

---

## ADR-006 — Haven Mode is rescoped to explicit saved places

**Decision.** Drop passive inference of home/work/family locations. Users type in the places
they care about. Keep the risk scoring, comparison and plain-language precaution alert.

**Why.** Two independent reasons, either sufficient. (1) **It is not novel** — TN-ALERT (Tamil
Nadu government / RIMES, 500 k+ installs, Tamil-language, updated Oct 2025) already pushes
flood risk alerts for five saved locations, and Google Personal Safety plus Maps home/work
inference covers the rest. (2) **Passive inference is the highest-risk, lowest-value part of
the system** under the DPDP Act 2023 and its 2025 Rules, and it is the hardest thing to get
past an ethics committee. Continuous background GPS also costs ~25–40% battery per 12 h and
cannot restart from `BOOT_COMPLETED` on Android 15+.

**Also:** the deck's phrase "encrypted routing usage" describes the wrong property.
The claim is "on-device, never transmitted." Say that instead.

---

## ADR-007 — No precise coordinates leave the device

**Decision.** Cloud LLM calls receive the router's structured decision trace with place
names and relative geometry, never raw coordinates or a user identifier. Hazard reports sync
with coarsened location where the hazard's own location does not require precision.

**Why.** Free LLM tiers either explicitly train on submitted content (Gemini) or have terms
that cannot be verified either way. Under the DPDP Act, live location is personal data. This
also makes the ethics application dramatically simpler.

---

## ADR-008 — Hazard reports are an append-only log (a G-Set CRDT)

**Decision.** Reports are immutable observations with client-generated UUIDv7 ids and
hybrid-logical-clock stamps, written to a local outbox and replayed on reconnect with
`ON CONFLICT DO NOTHING`. LWW-Register only for mutable user preferences.

**Why.** Conflicts become impossible by construction — an observation is a fact about a time
and place, not mutable state. This removes the entire class of merge problems the deck's
"reconcile local edge decisions" language implies, and it is trivially idempotent under
replay.

---

## ADR-009 — v0 is a bounded watchlist, not city-wide sensing

**Decision.** The prototype maintains risk state for ~150–200 chronic waterlogging points
resolved to specific OSM edges, rather than attempting to know the flood state of the whole
road network. Full spec: `docs/CHENNAI_PROTOTYPE_SPEC.md`.

**Why.** No source provides live street-level inundation for Chennai (`research/raw/C`), and
the crowd that would provide it is empty precisely on flood day — the council identified this
as the project's fatal risk (`docs/COUNCIL_VERDICT.md`). Chennai floods in the same places each
year, so a bounded watchlist converts an unbounded sensing problem into a monitoring problem
that tens of reporters can cover instead of tens of thousands. It also makes the static prior
load-bearing rather than decorative.

**Consequences.**
- `HazardObservation` gains `watchlist_point_id`; watchlist points carry a basin/corridor link
  and an upstream reservoir, so one reservoir signal escalates a whole corridor at once.
- The replay corpus (T3.1) becomes a curated point list plus per-point event history, not a
  general event scrape.
- The system must render "no data for this corridor" as a distinct state — with a bounded
  watchlist, the boundary is visible to users and pretending otherwise is dishonest.
- The "designed for every city" claim is retired. The method ports; the system is Chennai's.

**Reconsider if.** The watchlist cannot be assembled to ≥100 validated points from open data,
which would mean the chronic-point premise is wrong and city-wide sensing is the only option —
in which case the honest move is to narrow to a research contribution and drop the product claim.

**Verified 2026-09-14 (T-W1's automatable pipeline, `scripts/tw1_build_watchlist.py`) — the
overall premise holds (402 candidate points from the primary GCC/OpenCity source alone, well
past the 100-point reconsideration threshold), but the primary source has a real, structural
coverage gap the pitch's candidate seed list did not anticipate.** The Mudichur /
Varadharajapuram / Old Perungalathur / Bharathy Nagar corridor —
`docs/CHENNAI_PROTOTYPE_SPEC.md` §4's own named example of "exactly the basin escalation
mechanism example needed" (three lakes overflowing into one corridor, Michaung 2023) — has only
2 zones (0 High/Very High) in the whole 7,453-zone GCC hazard-zone KML within 10 km of it,
against 1,189–3,869 for each of the other four Michaung press leads. Confirmed independently
(not just taken from the script's own report): the KML's own longitude range bottoms out at
80.1285°, east of the corridor's coordinates. This is almost certainly a Greater Chennai
Corporation administrative-boundary artifact — Mudichur and Perungalathur sit in Tambaram
Corporation, a separate civic body, not a data quality problem with the GCC source itself.
**Consequence:** no watchlist candidate near this specific corridor can be produced from this
source, at any clustering radius — this is a missing input, not a tuning problem. Before this
corridor is used in the pitch, the demo, or the paper as a worked example, either a Tambaram
Corporation (or equivalent) data source must be found, or — per this same ADR's own precedent
for the CMWSSB scraper ("remove the reservoir-escalation demo beat rather than build toward
it") — drop this specific corridor as a demo beat and pick one the primary source actually
covers (the Pallikaranai / Velachery-Taramani-Perungudi-Madipakkam / Besant Nagar-Thiruvanmiyur
corridors all have strong coverage and equally real Michaung press corroboration).

---

## ADR-010 — Hazard observations decouple "permanent belief contribution" from "permanent raw location" (added 2026-09-12, review pass)

**Decision.** A `HazardObservation` id, polarity, class, and its already-computed contribution
to belief fusion are permanent, per ADR-008 — that property is what removes the merge-conflict
class and must not change. But the record's precision is not permanent: 30 days after
`observed_at` (comfortably past every hazard class's `T_c` in `config/hazard_classes.yaml`,
so the record has already decayed to near-zero evidence weight by then), the record is
rewritten **in place** — `geometry` is coarsened to a fixed ~150 m grid cell, and `source_id`
is replaced with a non-reversible per-report bucket id for `source_class: crowd` and
`app_traversal` reports. A user-initiated erasure request performs the same coarsening
immediately, on their own reports, ahead of the 30-day schedule. Nothing is ever *deleted*;
the id, polarity, class, and `observed_at` stay untouched, so CRDT convergence (`ON CONFLICT
DO NOTHING`) is unaffected — this is a further mutation-in-place of an existing fact, not a
retraction of it.

**Why.** ADR-008's "immutable, appended forever" design and `research/raw/C-data-sources.md`'s
explicit recommendation ("set an explicit retention limit, and implement erasure-on-request")
directly contradicted each other, unreconciled, through the entire planning phase — flagged in
the 2026-09-12 review. The contradiction exists because ADR-008 conflated two different
things: the *belief-fusion effect* of a report (which must never change, or the whole CRDT
argument collapses) and the *raw personal-location precision* of a report (which DPDP's
retention-limitation and erasure principles govern, and which a citizen's own real-time
position — required to be near a hazard to report it — makes personal data regardless of
whose hazard it describes). Separating them resolves both requirements at once.

**Consequences.** `HazardObservation` (`docs/CONTRACTS.md` §1) gains `precision_state: exact |
coarsened` and `coarsened_at`. `fuse()` (T1.2) must compute `κ(d(e,x))` against a coarsened
geometry correctly — since coarsening only happens after a report has already decayed past
every class's `T_c`, this should not materially change any `n_eff` used in live routing;
Study 2 should confirm this empirically rather than assume it. T5.4 (sync) gains a scheduled
coarsening sweep, run alongside the existing decay ZSET sweeper. `docs/REVIEW_CHECKLIST.md`
gains a retention/erasure gate.

**Reconsider if.** Study 2 shows coarsening measurably degrades calibration within the
30-day window (i.e., 150 m resolution loses real discriminating signal before `T_c` would have
decayed it anyway) — shrink the window, not the coarsening radius; radius is what DPDP cares
about.

---

## ADR-011 — The system never asserts passability, only relative risk (added 2026-09-12, review pass)

**Decision.** No generated or templated output, and no UI element, may ever state or imply
that a road, route, or edge is *safe* or *passable* in absolute terms. The system emits only
comparative and confidence-qualified statements ("Route A avoids two unverified reports";
"no recent data for this corridor"). This is enforced twice: as a **fifth verifier rule**,
alongside `docs/CONTRACTS.md` §4's four — reject any text containing an unhedged
affirmative-safety assertion, discard to Tier 0 on failure like any other verifier failure —
and as a **UI rule**: no single-color "all clear" badge; only the four confidence bands
(`high | moderate | low | stale`) with their hedge text attached. Before first use, and once
per app version thereafter, the app shows an unavoidable disclaimer: *"CityPulse is a research
prototype. It estimates risk from limited data — it does not guarantee any road is safe.
Always use your own judgement."* A shorter form of the same sentence repeats on any card whose
`confidence_band` is `low` or `stale`.

**Why.** `docs/COUNCIL_VERDICT.md`'s Skeptic named this risk in the first council session
("if they drown, the first question is who told them to drive there... no legal entity, no
insurance, no disclaimer regime") and it went unaddressed through every document written since
— confirmed by the 2026-09-12 review, which found zero occurrences of
`liability|disclaimer|insurance` outside the verdict itself. The project's confidence machinery
(bands, `data_gaps`, the verifier) was designed and discussed purely as an *explainability*
feature; "we told the user we had low confidence" is not the same claim as "we are not
liable," and nothing forced that distinction to be made until now. Encoding the rule as a
verifier check, not just a UI convention, means a future UI change that adds a green "clear"
badge fails the same way a hallucinated street name fails — silently, logged, counted in the
verification pass rate — rather than depending on every future contributor remembering a
written guideline.

**Consequences.** `docs/CONTRACTS.md` §4 gains verifier rule 6. `docs/REVIEW_CHECKLIST.md` §2
gains a check. Study 5's IEC protocol (T0.3) must show the same disclaimer during consent, and
the consent script should be checked against this ADR before submission, not after.
`docs/IMPLEMENTATION_PLAN.md` T5.1 (Flutter shell) gains an explicit acceptance line for the
disclaimer and the badge-colour ban — an ADR that isn't wired into the task that builds UI is
just words, and this one wasn't until the 2026-09-12 skeptic pass caught the gap.

**Implementation note on rule 6 (added 2026-09-12, second pass — flagged by skeptic review,
not resolved by wishful thinking).** Rules 1–5 (`docs/CONTRACTS.md` §4) are mechanical field
lookups against the trace; rule 6 asks for a semantic judgement ("does this text imply
absolute safety") that a denylist alone cannot make reliably — "should be fine" or "nothing to
worry about" carry the same implication as "safe" without containing a banned word, and a
naive keyword filter will both over- and under-trigger. Given that, rule 6 is enforced in two
layers, not one: **(a)** Tier 0's template vocabulary is a closed, human-authored set — audit
it once, by hand, to confirm no template string can ever produce an absolute-safety claim, and
add that audit as a fixed test fixture (this makes Tier 0 compliance a design property, not a
runtime check). **(b)** For Tier 1 (SLM) and the cloud path, apply a keyword/phrase denylist
as a first-pass filter (this will both over- and under-trigger — that is expected, not a bug),
and — since this is exactly the kind of automatic-checker accuracy question Study 3 already
budgets for — report rule 6's own precision/recall against the human-κ subsample alongside the
other verifier rules, rather than assuming it is as clean as rules 1–5. Do not ship rule 6 as
a single unvalidated regex and call it done.

**Numeric bar and fallback (added 2026-09-12, third pass — flagged by judge review as the one
remaining gap before T5.1's UI review specifically, not before starting other work).** Rule
6's denylist must clear **≥95% recall** against the Study 3 human-κ subsample's
affirmative-safety-implying examples before Tier 1/cloud output is allowed to reach the
low/stale-confidence UI path at all. **If it doesn't clear that bar, the fallback is not "keep
tuning the denylist" — it's to serve Tier 0 only for any card whose `confidence_band` is `low`
or `stale`**, regardless of tier, until the denylist is replaced or improved. High-confidence
cards are lower-risk for this specific failure (the underlying belief is itself more likely
correct), so the fallback is scoped to exactly the cards where an unhedged claim would be most
dangerous, rather than disabling Tier 1 everywhere over one rule's shortfall.

**Reconsider if.** VIT or a future institutional partner is willing to put formal backing
behind passability claims (e.g., co-signing with the Corporation) — at that point the
disclaimer's *wording* should change, but the "no absolute passability claim" rule should not,
since the underlying data (a ~150–200-point watchlist against a ~10⁵-edge graph, ADR-009)
still cannot support it.

---

## ADR-012 — Study 1/2 (T3.3/T3.4) ran against a corpus that cannot support several of the
claims the studies were designed to make (added 2026-09-18)

**Decision.** Ship the Study 1/2 infrastructure (`scripts/study1_route_quality.py`,
`scripts/study2_calibration.py`, `scripts/study_common.py`) as built, and record the following
results honestly rather than retuning any parameter until a number looks better
(CLAUDE.md section 8.4). This ADR exists because several results below **contradict the
design's intent**, which per this repo's convention is itself the finding, not a bug to hide.

**What the data actually shows (2015 Chennai flood corpus, `data/corpus/2026-09-17/`, N as
stated in each result.json):**

1. **The corpus cannot support two of Study 1's four named metrics at all.** `depth_mm` is null
   for every one of its 5,775 observed edges (no source KML carries measured depth), so the
   literal chance-constraint hard-removal (`edge_cost.dart`) never fires for C0/C2/C3/C4/
   C-infinity — "impassable-edge-hit rate" is reported `not_applicable` for those configs.
   Separately, **every one of the corpus's 6,132 observations carries `polarity: 1`** (verified:
   zero `-1` records) — there is no confirmed-absent ground truth anywhere in this snapshot, so
   "false-avoidance cost" is reported `not_computable`, not approximated with a fabricated
   proxy. Both are corpus properties, not harness defects — see T3.1's own MANIFEST.md, which
   already flagged the depth gap; the all-positive-polarity gap had not previously been stated
   as plainly and is stated here.
2. **The oracle (C-infinity) degenerates to "ours" (C3) in this snapshot.** T3.1's corpus
   carries exactly one proxy timestamp for every observation (`2015-12-02T00:00:00Z`), and the
   replay clock is pinned to that same instant (T3.2 precedent) — so query-time windowing is
   already a no-op and skipping it (oracle's realisation) changes nothing. The "perfect
   hindsight upper bound" this config exists to establish cannot currently be demonstrated as
   distinct from C3 — a second, temporally-spread corpus is required, not a code fix.
3. **C1 (naive hard hazard avoidance) is not expressible via any existing CLI flag combination**
   — the only hard-removal mechanism (the depth-based chance constraint) requires non-null
   `depth_mm`, which point 1 above rules out entirely for real edges. It was realised by
   injecting a synthetic `depth_mm`/`epsilon` on edges crossing a `z=0` `p_mean` threshold, using
   the CLI's real removal mechanism on harness-injected, not measured, depth values — see
   `study_common.build_c1_injected_overrides`'s docstring for the full mechanism.
4. **Study 2's source-holdout calibration proxy is weakly discriminating and confounded with
   hazard class.** Ground truth (edge confirmed by `official_feed`, predictor = crowd reports +
   prior only) yields AUROC ≈ 0.56–0.57 for the per-hazard-class decay (C3/"ours"), the
   single-shared-decay baseline (C2), and the fixed-TTL baseline (C4) alike — **all three are
   statistically indistinguishable from each other and only marginally better than chance
   (0.5)** on this corpus and this proxy label. This directly contradicts the design's premise
   that per-hazard-class calibrated decay should out-discriminate a naive single decay constant
   or a fixed TTL; on this evidence it does not, at least not as measured here. **Reported
   prominently, not retuned to look better**, per this task's explicit instruction. Candidate
   explanations, none yet tested: (a) the source-holdout label is itself weak evidence (an
   unconfirmed crowd report is not proof of absence — see point 1's polarity gap — so `y=0` is
   contaminated with true positives, capping achievable AUROC regardless of the decay model);
   (b) the corpus's single timestamp means "report age" is entirely simulated
   (`at = observed_at + Δ`), so real-world decay-shape differences that only matter for
   genuinely time-separated reports may not be exercised at all; (c) the three decay mechanisms
   may simply not differ enough at this corpus's actual evidence density to matter. Distinguishing
   these requires either a second, real, time-separated event or ground truth beyond source-class
   holdout — both out of this task's scope.
5. **Study 2's hazard-class stratification degenerates to a single class ("flood") for the
   crowd-only predictor pool** — not from a shortage of waterlogging data (753 records exist),
   but because every `crowd_sourced_flooding_2015.kml` record is `hazard_class=flood` and every
   `gcc_stagnation_2015.kml` (waterlogging) record is `source_class=official_feed`, and Study 2's
   source-holdout design puts all `official_feed` records on the label side of the split, never
   the predictor side. The "stratified by hazard class" requirement (docs/EVALUATION.md Study 2)
   is genuinely satisfiable only for `flood` with this specific corpus and this specific
   ground-truth design.
6. **The Beta-reputation-with-forgetting baseline scores far worse (Brier ≈ 0.30 vs. ≈ 0.04 for
   the exponential-decay baselines) mainly because it has no analogue of the static terrain
   prior `ℓ₀`** — with no observations (the common case: most edges) it falls back to an
   uninformative `p=0.5`, which is a poor prediction against this label's ≈2.4% base rate,
   whereas every exponential-decay baseline falls back to the static prior instead. This makes
   the Beta-reputation comparison structurally unfavourable to that baseline on this corpus,
   independent of whether forgetting-factor decay itself is worse than exponential decay — an
   asymmetry in what each model can fall back on, not (necessarily) in the decay mechanism being
   compared. Flagged, not corrected by retrofitting a prior onto Beta-reputation after seeing
   this result.
7. **Scale was cut well below `docs/EVALUATION.md`'s stated N=1,000**, driven by a measured
   per-CLI-call cost of ≈3.07s (dominated by per-process graph load of 471,240 edges; the "ALT landmark rebuild" in
   the original wording was wrong, `planRoute` does not use ALT, F-11 — the CLI had no batch mode then; `route-batch`
   was added 2026-10-02, F-20). See each script's
   `result.json["scale_decision"]`/timing fields for the exact N used and the arithmetic behind
   it — stated explicitly rather than silently under-run.

**Why recorded as an ADR rather than just left in `result.json`.** Points 2, 4, 5, and 6 are
exactly the class of "a benchmark kills an assumption" finding CLAUDE.md section 8.4 requires be
written here, not just logged and moved past. None of these were retuned away — the decay
constants, thresholds, and Beta-reputation formulation are exactly as originally chosen.

**Consequences.** (a) A genuinely independent oracle upper bound and a genuine multi-event
Study 2 split both require a second, temporally-distinct hazard corpus — this is now a concrete,
named blocker for a stronger Study 1/2 result, not merely "T3.1's known limitation" in the
abstract. (b) Point 4's null-ish discrimination result means the paper cannot yet claim
per-hazard-class calibrated decay outperforms simpler baselines on real Chennai data — the
paper's honest claim, until better ground truth exists, is limited to the ALT-admissibility
result and the pessimism-under-uncertainty design argument (`research/SYNTHESIS.md`'s
already-scoped four narrow contributions), not a demonstrated calibration win. (c) Before citing
Study 2's AUROC/Brier numbers anywhere, the source-holdout proxy's limitations (points 4–5) must
be restated alongside them — reporting the number without the caveat would overclaim, which
CLAUDE.md section 3.7 names as the single most likely thing to sink the project at review.

**Reconsider if.** A second Chennai hazard corpus with genuine per-observation timestamps
(distinct from this proxy's single 2015-12-02 stamp) becomes available — at that point Study 2's
event split, the oracle's distinctness from C3, and the report-age-bucket stratification all
become independently testable rather than simulated, and the calibration comparison in point 4
can be re-run without the source-holdout label's contamination.


---

## ADR-015 — The pessimistic index is a Beta posterior quantile (supersedes the Wald band of ADR-002) (added 2026-10-02)

**Decision.** Each hazard edge's belief is `Beta(a, b)` with
`a = n0·p0 + s·S⁺`, `b = n0·(1−p0) + s·S⁻`, where `p0 = σ(ℓ0)` is the static prior and
`S = Σ polarity·κ(d)·e^(−Δt/T_c)·w(α)` is the **signed, reliability-weighted, decayed** evidence,
`w(α) = min(1, logit(α)/logit(α_ref))` (`w = 0` for `α ≤ 0.5`). The routing index is
`p̃ = min(1, max(p̄, Q_Φ(z)(Beta(a,b))))`: the `Φ(z)` upper quantile, floored at the mean `p̄ = a/(a+b)`.
`z = 0` gives the mean, so the commuter default is unchanged on prior-only edges. Implementation:
`packages/pulse_belief/lib/src/beta.dart` and `beta_belief.dart`; the router calls `fuseBeta` and
`pessimisticBeta`. The old `fuse`/`pessimistic` stay in the package, as legacy, so the pre-fix
numbers in `data/results/2026-09-18-*` remain reproducible.

**Why.** KNOWN_FLAWS F-01 (critical) and F-12. Evidence reaches the index only through `S`, and
`p̃` is increasing in `S`, so:
- a positive report can never lower `p̃`, for any reliability (the Wald index went 0.329 → 0.309 → 0.333 → 0.380
  at p0 = 0.05, α = 0.6, z = 1.28). `packages/pulse_belief/test/beta_test.dart` checks this on a grid of
  more than 5,000 prior/reliability/z/age/starting-state combinations;
- opposing reports cancel in `S`, instead of both raising `n_eff` and reading as certainty;
- ageing shrinks `|S|`, so evidence decays monotonically back to the prior's own quantile;
- it is a genuine posterior quantile: bounded by 1 without a clamp, no collapse near 0, and no longer
  saturating to 1.0 on every high-prior edge at z = 2.

`n_eff` is redefined as `|S|`, net reliability-weighted evidence in "full-reliability report" units:
three crowd reports (α = 0.6) are about 0.35, not 3. Confidence-band thresholds (`low < 1`, `moderate < 3`) are unchanged
and now mean report-equivalents, so "high" takes about five α = 0.9 reports.

**What this does not claim.** `n0 = 2` (prior strength), `s = 2` (pseudo-counts per full report) and
`α_ref = 0.97` are **placeholders**, like the `T_c` values (F-15). They cannot be fitted without time-stamped,
independent labels. Mapping a source's reliability to an evidence weight via `logit(α)` keeps the original model's
relative weighting but is a modelling choice, not a derivation. The quantile is a posterior quantile *under that
model*; it carries no frequentist coverage guarantee, so the wording rule in `CLAUDE.md` §6 ("a pessimistic index",
not a bound) still applies.

**Consequences.** Every route-quality and calibration number computed with the Wald index is superseded for
the *method* (old result folders are kept untouched). Studies 1 and 2 must be re-run (PLAN M1.11), and the Python
replica in `scripts/study_common.py` must be ported before Study 2 is re-scored. The 2015 replay cannot show that the
new index helps (it has no time spread and no independent labels); it only shows the old failure is gone.

**Reconsider if.** Labelled monsoon data shows the evidence mapping `w(α)` or `n0`/`s` is badly off; fit them then.

---

## ADR-016 — Explanation semantics: free-flow deltas, truthful "avoids", report-aware wording, honest data gaps (added 2026-10-02)

**Decision.**
1. "Route A is N minutes slower/faster than Route B" compares **`chosen.free_flow_duration_s` with `alternatives[0].duration_s`**
   (driving time against driving time). `chosen.duration_s` is the hazard-penalised cost the search minimised and is never
   described as minutes. The `docs/CONTRACTS.md` §4 worked example now reads "2 minutes slower" (1023 − 907 = 116 s),
   not "4 minutes" (1147 − 907).
2. `planRoute` lists an alternative's blocking edge only if the chosen route does not use **that edge**. The judgement is edge-level, not
   street-name-level, because a detour usually goes round one segment of a long road; the template words it "It avoids a stretch of X where
   flooding was reported N minutes ago", which stays true when the route crosses X elsewhere. (A first version also suppressed the claim whenever
   the route touched any stretch of the same named street; running the engine on real OSM names showed that hid the explanation in most
   detours, so it was changed before release.)
3. `BlockingEdge` gains an additive `has_observation` flag (serialised only when `false`). A prior-only edge is described as
   "which the hazard map marks for flooding but where no report has been received", never "reported moments ago".
4. **A data gap is a hazard-map edge on the chosen route with no recent observation** (none, or older than the staleness cutoff
   `2·T_c`). Edges with no hazard entry at all are not listed individually; the route-level confidence band covers them.
5. `renderTemplateSafe` never throws. If Tier 0 fails its own `verify()` it returns the fixed sentence `kMinimalExplanationText`
   (`fallbackUsed: true`), reports the failure through a callback for logging, and never shows the failing text.
6. The verifier gains: unit-typed number checks and subject binding ("N minutes slower" must equal the free-flow delta, "N minutes ago"
   a report age), comparative **direction** against the trace, avoidance **subject** (must be the chosen route) and **object**
   (must be something the trace names), an expanded English safety lexicon applied fail-closed with trace names stripped, and a
   Tamil stem list (unreviewed by a native speaker).

**Why.** KNOWN_FLAWS F-04, F-05, F-07, F-08. Measured with `packages/pulse_explain/test/fixtures/verifier_cases.json`
(234 cases written before the change; two honest cases were added afterwards, so the final run has 236): false accepts of sentences
that must be rejected fell from **150 of 209 (71.8%)** to **0 of 209**, with **0 of 27** honest sentences rejected (0 of 25 at baseline). Results: `data/results/2026-10-02-verifier-baseline/` and `data/results/2026-10-02-verifier/`.

**Limits.** The set is authored by the people who wrote the fix, two patterns were added after seeing residual failures on it,
and it is not model output. The real false-accept rate on Tier 1/2 text is unmeasured (Study 3). The Tamil list needs a native reader.
`FactSet` (the rewriter prompt) still exposes `duration_s`; a rewriter that calls it "minutes" is now rejected, which is the intended
safe failure.

**Schema note.** The one wire change is the optional `has_observation` key, so existing documents and the golden trace are unaffected.


## ADR-017 · Study 1 and Study 2 re-run on the fixed router (2026-10-02)

**Status.** Accepted. Results: `data/results/2026-10-02-study1-route-quality/`, `...-study1-rescored/`, `...-study2-calibration/`. The 2026-09-18 folders are untouched.

**What changed in the harness.** The router CLI (build `data/bin/2026-10-02/pulse_router.exe`) uses the Beta-posterior index (ADR-015). Evidence attaches to both directions of two-way streets (F-02). The harness calls `route-batch` (F-20), so Study 1 uses 1000 origin-destination pairs (seed 20260918; the first 100 are the same pairs as the 2026-09-18 run, checked). It adds the hybrid baseline (hard block at p-mean > 0.5 plus soft lambda = 5) and C3 at lambda = 5 and 20. Every route is re-scored under one reference belief, the Beta posterior mean of the C3 model, in free-flow time, with paired bootstrap intervals over pairs (B = 5000, seed 20261002). Parameters were fixed before the run.

**Results (1000 pairs, none disconnected under any configuration).**
1. Default commuter setting (z = 0, lambda = 0.3) changed 118 of 1000 routes (the old run: 7 of 100). Mean free-flow detour 0.01%. Change in sum of reference p-mean per route: -0.040 [-0.068, -0.017]; it comes from edges that carry reports (-0.037), not prior-only edges (-0.003 [-0.028, 0.017]).
2. Hard block alone (C1) leaves sum p-mean unchanged (-0.030 [-0.075, 0.017]) and shifts exposure onto prior-only edges (+0.077 [+0.037, +0.119]). Hard block plus soft cost (hybrid): -0.579 [-0.671, -0.488].
3. C3 at lambda = 5 is **not** better than the hybrid: C3(5) minus hybrid is +0.045 [+0.019, +0.072] in sum p-mean, i.e. slightly more exposure, with mean detour 0.85% vs 1.35%. On prior-only edges there is no difference (-0.011 [-0.032, 0.010]). The advantage over C1 reported in September comes from the soft cost, not from the C3 mechanism.
4. **Held-out official check.** With official reports held out of both beliefs, prior + crowd routes cross *more* official-report edges than prior-only routes: +0.081 [0.039, 0.126] per route at lambda = 5, +0.107 [0.058, 0.159] at lambda = 20. Crowd reports did not help, and on this metric they hurt slightly.
5. Study 2 (crowd pool now 9,336 edges, 56,016 rows; 61,016 rows with the 5,000 report-free edges): on the crowd pool the Brier skill against the prior alone is -0.15 for C3 and -0.285 for the fixed-TTL baseline; at report age 0 the prior scores 0.0361 and C3 0.0567. AUROC is 0.546 (C3) against 0.569 (prior alone).

**Reading.** The Beta fix removed the non-monotone behaviour, and the September finding stands in a stronger form: the crowd-report layer adds nothing measurable over the static GCC prior on this corpus, and slightly worsens the held-out check. Use the hybrid baseline as the comparison in any paper table.

**Limits.** One proxy timestamp, all reports positive, no depth, so decay, the chance constraint and false-avoidance cost remain untestable. The Study 2 label (an official report on the same edge) measures co-location, not flooding. "Official" points include GCC vulnerability designations. Node paths are mapped to edges by smallest free-flow time per hop, so parallel twins may differ. Study 2 pools are not yet split or controlled for edge length (F-14). The prior-strength and evidence-scale constants (2 and 2) are placeholders and were not tuned.


## ADR-018 · Cities are data: `config/cities.yaml` and a city-aware pack pipeline (2026-10-03)

**Status.** Accepted. Implements the "make the pipeline city-agnostic" option; a second live city is **not** started.

**Context.** Chennai was hard-coded in the map centre, the user-facing texts (including Chennai's control-room number), the
Overpass bounding box, the pack builder's file names and the router's error messages. The project's own plan
(`NEXT_STEPS.md`, "Stop doing") says not to add cities before one monsoon of Chennai labels exists, so the aim was to remove the
assumptions, not to expand.

**Decision.**
1. `config/cities.yaml` holds one entry per city: names (English, draft Tamil), centre, bounding box, pack folder, an optional
   watchlist file, `hazard_layer: true|false`, an optional checked `local_contact`, and the three data texts. `CityConfig` in
   `pulse_router` parses and validates it (a hazard-layer city must supply its own texts; one without gets honest defaults saying
   no flood-hazard layer is loaded).
2. `scripts/city_pipeline.py` fetches a city's roads and builds a pack in the existing binary format, reusing the Chennai
   graph and pack code. It builds only `hazard_layer: false` cities (flat default prior, the same value Chennai uses away from its
   zones) and refuses anything else; it also refuses a box that does not contain the configured centre. Output is deterministic.
3. The apps and the router service take the city at build or start time (`--dart-define=CITY`, env `CITY`); strings use
   `{city}` and three text placeholders; the Chennai local contact shows only for Chennai; the cloud-rewriter prompt no longer names a city.
4. Chennai's pinned pack and every Chennai string are unchanged: for Chennai the resolved texts are identical to before (tested).

**Consequences.** One build serves one city. A new city is routing-only until someone supplies a verified hazard source; the app
says so on screen. Nothing in belief, routing or explanation changed.

**Evidence.** A synthetic grid city ("Testville") goes Python builder -> Dart router -> HTTP service -> app texts in tests, with
a rebuild-is-byte-identical check and a guard that the committed fixture matches the builder. This shows no Chennai assumption
remains in code; it does not show that a real city's OpenStreetMap extract builds well. No real second city was fetched.

**Limits.** Tamil city texts and defaults are drafts. The watchlist layer is empty for cities without a candidates file (the toggle
still shows). Switching cities within one app or serving two cities from one router is not built.


## ADR-019 · Travel modes are movement profiles; bicycle added (2026-10-03)

**Status.** Accepted. Fixes KNOWN_FLAWS F-24; F-25 stays open.

**Context.** `commuter`, `pedestrian` and `emergency` differed only in the hazard-caution numbers `z` and `λ`. All three searched the
car graph at car speeds, so the same Chennai trip returned the same route and the same 14.9 minutes for 10.6 km for a walker as for
a car. There was no bicycle mode.

**Decision.**
1. A **travel profile** turns the pack's per-edge car speed and road class into one traveller's speed on that edge, or closes the
   edge to them, and says whether one-way streets bind them. `config/hazard_classes.yaml` `travel_profiles` holds `foot`,
   `bicycle` and `emergency`; `car` is the pack as it is. Each user class names its profile. The engine builds one routing graph per
   profile, on first use, keeping original edge ids, so hazard data and search stay unchanged and every mode finds its own route and
   its own duration with the same code.
2. **Foot:** 5 km/h (4-4.5 on trunk and primary), motorways closed, may walk against a one-way street (the reverse edge shares its
   forward edge's id). **Bicycle:** 15 km/h on quiet streets, lower "effective" speeds on busier roads (14 tertiary, 12 secondary, 10
   primary, 8 trunk), motorways closed, one-way streets obeyed. **Emergency:** car speed times a per-class factor from 1.0 (residential,
   unclassified) up to 1.4 (primary, trunk, motorway), capped at 90 km/h, chosen from the reasoning that a large vehicle gains little in a
   narrow lane and most on arterials. **Cyclist `z` = 1.0, `λ` = 0.8** (between pedestrian and car).
3. **`cyclist` is added to the `user_class` enum** in the decision trace contract (`docs/CONTRACTS.md`, `UserClass`).
4. The app offers four modes (car, bicycle, on foot, emergency vehicle); durations of 90 minutes and over read as hours.

**What this is not.** It is not machine learning and not a language model. Route geometry comes from graph search (CLAUDE.md §3 rule
6). **Every number in a profile is a placeholder assumption** chosen for plausibility; none is measured or fitted, and the bicycle
speeds fold road discomfort into a lower speed, so they change the reported time too. Learned per-edge speeds would need probe or
cycling data we do not have.

**Evidence.** Seeded comparison on the real Chennai pack, 296 random node pairs with a car route, `tool/mode_compare.dart`
(`data/results/2026-10-03-travel-modes-arterial-emergency/`; the earlier flat-multiplier run is kept in `...-travel-modes/`):
- **On foot and bicycle:** the route differs from the car route on 296 of 296 trips. Median speeds 4.9 and 14.0 km/h (car 46.8), median
  23.2 km on foot against 25.2 km by car.
- **Emergency (arterial factors):** differs from the car route on 38% of trips when dry and 41% in an active flood event; median 24.7 min
  against 31.9 min by car. With a flat 1.3 factor it differed on only 0.3% when dry and 8% in a flood event, which is why the factors are per class.
- The same trip as before (T. Nagar to Velachery): car 14.9 min / 10.6 km, bicycle 51.2 min / 10.4 km, on foot 98.3 min / 7.9 km,
  emergency 11.3 min / 11.2 km.
- Tests: `packages/pulse_router/test/travel_profile_test.dart` (speeds, closed classes, one-way handling, per-class factors, bad
  config refused) on the Testville grid and the real config.

**Limits.**
- The pack contains only roads cars can drive (F-25): no footways, paths, pedestrian streets, steps or cycle tracks. Walking and
  cycling routes therefore follow roads, and a real walker may have shortcuts we cannot see.
- The first walking or cycling route after start-up builds that mode's graph (a few hundred milliseconds on a desktop, more on a phone;
  about 20 MB of memory per mode).
- Depth-based slowdown (`δ`) is 1 when depth is unknown, which is always today, so water does not slow walkers in the model.
- Emergency routes assume no siren-specific rules beyond speed; contraflow driving is not modelled.
- The command-line router used by the study harness still searches the car graph; it only labels the class.

---

## ADR-020: Mapping India in phases, starting with Tamil Nadu's main roads (3 October 2026)

**Status:** accepted. Phase 1 built and exercised on a laptop; not run on a phone.

**Context.** The user's goal is the whole of India, mapped phase by phase. Everything until now was Chennai: the pack, the search, the
hazard overlay and the "outside the mapped network" check. A whole state has to stay interactive, so size and smoothness are design
constraints, not afterthoughts.

**Decision.**
1. **Phases.** Phase 1: Tamil Nadu, main roads only (motorway to secondary), as a *region pack* served by `services/router_api`. Later:
   detailed packs per district or city (tertiary and below), stitched to the backbone; then other states by the same builder.
2. **A leaner builder** (`scripts/region_pack.py`) streams a Geofabrik PBF with pyosmium instead of loading JSON, writes the same binary
   format as `city_pipeline`, and a `places.json` gazetteer (cities, towns, villages, suburbs, with Tamil names where OSM has them).
   Parity with `city_pipeline` is a test (byte-identical nodes and meta on Testville).
3. **Long roads are cut at 800 m** (`MAX_EDGE_M`) because a main-roads-only graph otherwise merges whole highways into single edges.
4. **Road numbers are searchable.** A street's search name is its name plus its OSM `ref` ("Salem - Kochi - Kanyakumari Highway (NH544)").
   Search matches "NH 44", "NH-44" and "NH44" alike, and not "NH444".
5. **Smoothness measures.** The hazard overlay is limited to the viewport (bbox, limit, compact GeoJSON, 250 ms debounce, padded regions
   with a small cache) and is hidden below zoom 10.5; long routes are thinned (Douglas-Peucker, 1,500 points maximum); each region sets
   its own snap radius and opening zoom (`max_snap_metres`, `initial_zoom` in `config/cities.yaml`); the route card says when the start or
   end is far from a mapped road.
6. **A region without a flood layer says so.** No flood-event banner, no "hazard confidence" badge or hazard explanation; the route card
   shows the city's no-hazard note instead.

**Evidence** (`data/results/2026-10-03-india-survey-tamil_nadu/result.json`, `data/packs/tamil_nadu-backbone-2026-10-03/manifest.json`):
- Survey of the 557 MB southern-zone extract inside the Tamil Nadu box: motorway to secondary = 76,802 ways, 73,375 km. The estimate from
  Chennai's edges-per-segment ratio was 1,298,218 edges and 42.7 MB. **The built pack has 257,249 edges and 9.0 MB.** The Chennai-calibrated
  estimate overstates a rural network about five-fold; do not use it to size other regions without a trial build.
- Pack: 143,227 nodes, 257,249 directed edges, 8,438 distinct street names; 25,144 places (39 cities, 571 towns, 23,013 villages, 1,521
  suburbs); read time 59 s, build 3 s on the authoring machine.
- One statewide route in the browser build (Chennai to the far south, 693.1 km): 1,278 route points, 65.3 KB, 291-305 ms on the server
  through a local proxy; the overlay query for the whole state returns an empty result (no hazard data), and place search answers in
  about 25 ms. Tamil-script search finds Madurai from "மதுரை".
- Tests after this change: pulse_router 165, router_api 25, app 144, Python (scripts and server) 104, all passing.

**Limits.**
- **There is no flood data outside Chennai.** The region pack carries a flat prior (p = 0.02) on every edge. It routes by road speed only.
- **Main roads only.** Tertiary and smaller roads are absent, so the start or end can be several kilometres from a mapped road (the card
  says how far). Villages are searchable but not necessarily reachable by a mapped road.
- The Tamil Nadu box is rectangular and includes parts of neighbouring states.
- **Pack format v1 has a 16-bit street-name index (65,535 names).** Adding tertiary and below for the whole state will exceed it; a v2
  with a 32-bit index is needed (F-26). One in-memory graph for the full state also did not fit this 7.4 GB machine.
- Server-side only: the app on a phone has not loaded this pack, and the gazetteer is not wired to the on-device path.
- Speeds are the placeholder per-class values of ADR-019, so intercity times (11 h 46 min for the 693 km trip above) are plausible
  numbers, not validated against real travel times.

---

## ADR-021: A small offline route advisor, in the style of a "System One" model (3 October 2026)

**Status:** accepted. Built and tested; not yet run on a phone.

**Context.** The user asked for fast AI on every calculated route, naming Jev (TypeSafe AI, "System One" models) as the kind of decision
model wanted. Jev is a hosted API in early access: every call goes over the network (about 70-500 ms by the vendor's own figure), costs per
token, and would send the route off the phone. The app must work offline, the budget is Rs 0, and DPDP rules limit sending location data to
third parties. The user then asked for a free model of the same kind that runs on the phone, with transparent scoring as its basis.

**Decision.** `packages/pulse_router/lib/src/route_advisor.dart`: a pure-Dart function `advise(RouteFacts)` that reads a route's own
`DecisionTrace` and returns, in one pass, typed decisions with scores:
- **Risk** over lower / moderate / high; **action** over proceed with care / wait / avoid; **evidence** strong / some / little; a **route-choice**
  check (how clearly the chosen route beats the alternatives); and at most two typed **reasons**. No text is generated. The words come from fixed,
  checked strings (English and Tamil) and the existing template explanation is unchanged.
- **How it scores** (all constants are visible in the file): the route's risk score is `0.7 * worst-edge index + 0.3 * hazard time added`; it is softly
  assigned to the three levels; the result is blended toward a "mostly moderate" prior as evidence thins; the traveller's class (`commuter` 1.0,
  `cyclist` 1.25, `pedestrian` 1.5, `emergency` 1.6) weights moderate and high risk; the action is a softmax over a small utility table.
- **UI:** one card (`AdviceCard`): verdict, a three-segment risk bar, evidence dots, at most two reasons, and a hedge line. It replaces the separate
  confidence badge on the route card. No green, no "safe", no percentages (ADR-011).
- A pluggable hosted model (Jev or another) could be added later behind the same `RouteFacts` input; it is not built, and would need consent to
  share the route.

**What it is not.** Not learned, not a language model. **Every weight is a hand-set placeholder** and the outputs are model scores, not measured
frequencies: there are no outcome labels to learn or calibrate from (ADR-012). Nothing here claims accuracy.

**Evidence.**
- `packages/pulse_router/test/route_advisor_test.dart` (20 tests) pins these properties: probabilities sum to 1 over a grid of inputs; more hazard never
  lowers the chance of "avoid"; thinner evidence never raises the chance of "proceed with care"; no evidence gives a non-"lower" and less decisive answer;
  a walker is warned more than a rider, a rider more than a driver; a much less risky chosen route wins the choice check clearly and an equal one only weakly; bad numbers (NaN, infinity) fall back to "avoid".
- Speed, measured on the authoring laptop: 1.5-1.7 microseconds per call over 100,000 calls. A phone has not been measured.
- `app/test/ui/advice_card_test.dart` (5 tests): the card, no percentages or safety words, two reasons at most, Tamil, one-sentence screen-reader label.

**Limits.**
- The Tamil text is a first draft, unreviewed, like the rest of the Tamil strings.
- The route-choice check only compares the router's chosen route with the alternatives the trace carries (their hazard exposure is known only
  for the edges the trace lists), so it is an agreement check, not an independent second opinion.
- Regions with no flood layer (ADR-020) show no advice card, only the no-flood-data note.
- Thresholds were chosen before looking at routes; if they are changed after seeing results the change must be recorded as a new ADR (CLAUDE.md rule 3 spirit).

---

## ADR-022: One app for Chennai and Tamil Nadu; advice only inside Chennai (3 October 2026)

**Status:** accepted. Built and exercised in the web build and the API tests; not run on a phone.

**Context.** The Chennai app (detailed streets, flood layer, AI advice, ADR-021) and the Tamil Nadu app (main roads only, ADR-020) were two
builds. The user asked to combine them: give the AI inference for Chennai alone, and for anything that crosses the border drop the inference and
show just the best route.

**Decision.**
1. **One deployment, two packs.** `config/cities.yaml` gives `tamil_nadu` a `detail_regions: [chennai]` list. The router API loads the Tamil Nadu
   main-road pack and, for each detail region, its own pack and search index.
2. **The rule is by start and end.** If **both** ends are inside Chennai's box, the Chennai pack answers; it cannot leave its own box, so the route
   cannot cross the border. If that finds no route, or either end is outside, the Tamil Nadu pack answers. A route from Chennai to Madurai is
   therefore a Tamil Nadu route, even though it starts in Chennai.
3. **The answer says which.** `POST /route` returns `hazard_layer` and `region`. The app shows the advice card and the explanation only when
   `hazard_layer` is true; otherwise it shows the time, distance, and the note "Flood-hazard data covers Chennai only…". The advice is computed on the phone
   (ADR-021), so no inference runs for a Tamil Nadu route.
4. **Flood overlay, reports and event state belong to Chennai.** `/risk` is answered from the Chennai engine only (so it is empty elsewhere); the event
   state is set on both engines; the observation sync feeds the Chennai engine. The banner reads "Chennai · Flood event: …" so it is clear what it covers.
5. **Search is merged.** Both indexes are searched and the results sorted by relevance, then kind (city, town, street, suburb, village), then nearness;
   the same name within about 300 m appears once.
6. The texts for the combined region (`hazard_note`, `about_data`, `data_credit`) credit the Chennai hazard data and say plainly that there is none elsewhere.

**Evidence.**
- `services/router_api/test/combined_test.dart` (7 tests, real packs): a route with both ends in Chennai returns `region: chennai`, `hazard_layer: true`;
  T. Nagar to Madurai returns `region: tamil_nadu`, `hazard_layer: false`, about 380-520 km; Madurai to Coimbatore has no flood layer; the overlay has
  features in Chennai and none near Madurai; search finds "Madurai" first and a Chennai street; the event state reaches both engines.
- In the browser build: T. Nagar to Velachery (9.3 km, 139 ms) shows the advice card; Chennai to Madurai (447.1 km, 7 h 35 min, about 263-298 ms) shows no card
  and the Chennai-only note.
- App tests: the advice card appears for a route with `hazard_layer: true`, not for `false`; the banner names the city; the flag is parsed (and left unset
  when a server omits it).
- Test counts after this change: pulse_router 188, router_api 32, app 153 (Python scripts and server suite unchanged at 104, not re-run).

**Limits.**
- A route from a point just outside Chennai's box to one inside it gets no advice, even though most of it is in Chennai.
- The Tamil Nadu box is a rectangle, so some points in neighbouring states route here too.
- Only the web build was exercised; the on-device path still serves one pack and would need the same rule to combine (not built).
- The memory cost of two engines in one process was not measured.

---

## ADR-023: A merged India flood event dataset from the free sources (4 October 2026)

**Status:** accepted. Built; not yet used by the router or the app.

**Context.** The scarce resource is independent, time-stamped flood evidence (CLAUDE.md section 0). The user asked to merge the free
Indian sources into the best dataset available. A search found no free source with street-level passability. What exists is district-level
event history (IMD, via the India Flood Inventory), region polygons with dates (Dartmouth Flood Observatory), district severity tables,
and river-level and satellite portals with no documented bulk access. The user approved downloading two: the India Flood Inventory v4 (four
CSVs, 1.9 MB) and the DFO India events (296 polygons, 0.4 MB).

**Decision.** `scripts/build_india_flood_dataset.py` writes `data/india_flood/2026-10-04/`:
1. `events.ndjson`: 6,876 IMD events and 296 DFO events in one schema, each tagged with source, licence and `commercial_use: false`.
2. `district_summary.csv`: 744 district rows joining the severity index, corrected flooded-area share, fatalities, population, mean duration and
   IFI event counts.
3. `tn_event_calendar.csv` and `links_tn.csv`: Tamil Nadu events from both sources joined by a rule fixed before any count was seen:
   **an IMD event and a DFO event are linked if their dates overlap within +-3 days AND the DFO polygon contains the headquarters point of a
   district named in the IMD event.** Tamil Nadu only, because only Tamil Nadu has district points (OSM place names from the Tamil Nadu pack).
4. Deaths from the two sources are kept in separate columns and never summed. Everything is research-only; a product build filters on `commercial_use`.

**Evidence** (`data/india_flood/2026-10-04/result.json`; tests in `scripts/tests/test_india_flood_dataset.py`, 11):
- 7,172 events; IFI spans 1967-07-02 to 2023-09-12 and has no coordinates; 188 events name Tamil Nadu.
- 38 of 38 Tamil Nadu districts got a headquarters point. 31 IMD-DFO links; 172 calendar rows, of which 15 are seen by both sources; 47 name Chennai.
- Chennai ranks 2nd of 37 Tamil Nadu districts and 117th of 743 in India on the District Flood Severity Index (16.62; Thanjavur is first in Tamil Nadu at 16.98).
- **The replay corpus's single proxy timestamp, 2015-12-02, falls inside an IMD Chennai event (1-3 December 2015).** IMD lists seven Chennai events from 9 November
  to 11 December 2015. This supports the proxy date as a plausible peak day. It does not give any observation its own time.
- The DFO polygon for that November to December 2015 event (centre 78.86 E, 11.83 N, "Tropical Storm Rovan", 180 deaths) does **not** contain the Chennai headquarters point. These
  polygons are too coarse to place a city.

**Limits.**
- None of this is street-level or live. It does not help with the 15 October gate by itself.
- Only Tamil Nadu is linked spatially. Other states are in the tables but need district boundaries, which were not downloaded.
- The link rule can chain: one DFO polygon joined seven IMD events into one 2015 cluster.
- District points are place names, not boundaries, so containment is approximate.
- Licences: IFI is CC BY-NC 4.0; DFO is CC BY 3.0 for older and CC BY-NC-SA 4.0 for recent events. The merged data must stay research-only and share-alike.
- Not yet tested: whether a district-level prior from this data beats the flat prior (p = 0.02) used outside Chennai. That needs its own pre-registered study.

---

## ADR-024: What to train on, and what not to (4 October 2026)

**Status:** accepted as a plan; nothing has been trained.

**Context.** The user asked for the best dataset to make an ML model worth using for route selection (`00_START_HERE/DATA_SOURCES_ASSESSMENT.md`).
A search found no public dataset with street-level, time-stamped flood labels for Chennai. The user approved downloading the Chennai Flood Monitor archive
(three Hugging Face datasets) and NYC FloodNet; the DEM, the OpenCity depth points and a live poller were not approved and are not built.

**Decision.**
1. Two models are worth attempting, both small, both judged against a baseline fixed beforehand:
   (a) an **event-gating model**: daily rain from 53 Chennai gauges, 1988 to 2019, against the 33 IMD-reported Chennai events of those years (354 event-days of 11,688),
   tested on later years and compared with a seasonal-rate table; (b) a **spatial susceptibility model** on the 2005, 2015 and 2020 flood points and extents plus drainage layers,
   tested on held-out areas and held-out events, treated as positive-unlabelled.
2. **No street-by-street live predictor is claimed.** The one source with street-level timestamps (173 citizen reports) has 12 reports above level 1.
3. **NYC FloodNet is a pipeline sandbox only.** Models trained on it are not transferred to Chennai.
4. **Street-level, time-stamped labels must be collected this monsoon** (field logs at the GCC subways and named points; app reports with a passability state). This needs the owner's go-ahead
   for any polling of the government server and volunteers for field work.
5. The CFM raw files stay out of git (no stated licence).

**Evidence.** `data/chennai_cfm/2026-10-04/profile.json`, `data/nyc_floodnet/2026-10-04/profile.json`.

**Limits.** Daily rain is coarse for flash flooding; there is no rain data for 2020 to 2022; no rain or level data from automatic stations in any flood window; the ward depth table is a frozen 2021 model run;
the Hugging Face cards overstated the data (15-minute readings, 169 reports from 2025), as the download showed.

---

## ADR-025: A nationwide district flood-event model, trained and found not to add value (4 October 2026)

**Status:** accepted. Trained once under a pre-registered rule; the rule's verdict is **no evidence of added value**.

**Context.** The user asked for a model trained on a dataset covering all of India. The only nationwide labels are district-level (IMD events in the India Flood Inventory), so the
model predicts whether a district is under a reported flood event on a given day, from rainfall. It does not place a flood on a street. The plan, features, splits, grid, baselines, metrics and
decision rule were committed in `data/nationwide_flood/2026-10-04/PREREGISTRATION.md` (commit `151dcfa`) before any rainfall was joined to labels or any model run. Two documented changes were made before any join
(addendum A: two more geocoding levels; addendum B: NASA POWER instead of Open-Meteo because the free tier allowed about 60 districts an hour).

**Result** (`data/results/2026-10-04-nationwide-flood-gating/result.json`; 592 districts, 29 states; train 1990-2009, validation 2010-2015, test 2016-2023 touched once):

| Test 2016-2023 | Average precision (95% CI) | Event recall at a 2% alert budget (95% CI) |
|---|---|---|
| Gradient-boosted model | 0.090 (0.057, 0.126) | 0.326 (0.252, 0.387) |
| B1: district and month event rate | 0.097 (0.055, 0.145) | 0.206 (0.120, 0.274) |
| B2: 3-day rain against its 95th percentile | 0.066 (0.044, 0.092) | 0.356 (0.309, 0.397) |

- Differences (model minus baseline, 95% CI): against B1, AP -0.007 (-0.020, +0.005), recall +0.120 (+0.092, +0.157); against B2, AP +0.024 (+0.008, +0.041), recall -0.030 (-0.106, +0.023).
- **The pre-registered rule needs the model to beat both baselines on both metrics. It does not:** it ties B1 on AP and B2 on recall. State-holdout AP (5 folds of held-out states, validation years) is 0.0506 against the best baseline's 0.0497; the model trained on all states did better than the unseen-states model in 4 of 5 folds.
- Test positives are 4.45% of district-days (77,002 of 1,729,824) against 1.35% in training: the reporting rate rose a lot.
- Validation AP is nearly flat across the 8 grid settings (0.059 to 0.062), so the extra capacity found nothing more to use.
- A plain rule, "alert when 3-day rain is in the district's top 5%", catches 36% of reported events while alerting on 2% of district-days. That is what the data supports; it is a baseline, not a validated product.

**What this means.** District-day reports of flood events are only weakly predictable from daily reanalysis rainfall. A learned nationwide model did not beat two trivial rules. We do not replace the flat prior outside Chennai with this model, and we do not claim nationwide
flood knowledge from it. Per the rule, no further tuning, features or baselines were tried after the verdict.

**Limits.**
- Labels are reported events, not floods; district names are noisy (the IFI lists districts under old states, misspells some, and its LGD codes collide across states).
- Coverage: 592 of 948 district names got a point, 77.2% of district-event pairs; 29 states; Arunachal Pradesh, Meghalaya, Delhi, Goa and several large Assam districts are absent.
- Rainfall is NASA POWER daily at 0.5 degrees (MERRA-2), which under-reads extreme local rain; points are district seats.
- Brier score is reported only for B1 (0.0428) and no reliability table was produced, because the model is trained with balanced class weights and its scores are rankings, not probabilities.
- Not tried, because the rule forbids tuning after the verdict: better rainfall (IMD gridded, ERA5-Land, IMERG), sub-daily rain, other labels. They are the next experiments, each needing its own pre-registration.

---

## ADR-026: Terrain and past floods as the training data for where water collects (4 October 2026)

**Status:** accepted. Eight pre-registered studies, run in order; every rule and every change to a plan was committed before the result it governs. The model-quality rules passed in the nationwide studies (B, B2) and in the transfer of the nationwide model to Chennai (C3, narrowly). The Chennai-local studies (A, A2) and all three routing tests were not met.

**Context.** The nationwide rainfall model (ADR-025) found no gain, and the user suggested elevation and previous flood records as better data. This ADR records what that data can and cannot do. It asks *where* water collects, not *when*, and it does not tell anyone a road is passable.

**Data used.** The Global Flood Database's 91 satellite maps of India floods 2000 to 2018 (250 m; CC BY-NC-ND 4.0, research only, never redistributed from this repository); Copernicus 90 m elevation tiles; for Chennai, the NRSC (December 2015) and IRS (2005) flood extents and three hotspot lists from the Chennai Flood Monitor archive, and its drainage and water layers.

### Results

| Study | What it asked | Result against its pre-registered rule |
|---|---|---|
| **B2, all 91 India maps** (spatial 2-degree blocks held out, 2.6 million sampled cells) | Does a terrain model rank flooded cells above dry ones better than the best single terrain feature? | **Met.** Average precision 0.311 (0.256, 0.364) against 0.188 (0.152, 0.231) for relief within 5 km; AUC 0.930 (0.915, 0.944) against 0.866 (0.835, 0.893). It beat the single feature on 81 of 91 maps in average precision and 89 of 91 in AUC. |
| B (the 11 maps that fit in memory, registered first) | The same | Met: AP 0.341 against 0.218. |
| B2, rainfall climatology added | Does the earlier rainfall work add anything? | **No evidence**: AP difference +0.0084 (-0.0054, +0.0222), AUC difference +0.0008 (-0.0043, +0.0053). |
| **A, Chennai region** (2005 and 2015 floods, hotspots) | Does a local terrain model beat the best single feature, across floods, across blocks, and on hotspot points no model saw? | **Not met.** Across floods and blocks it won (held-out blocks: AP 0.238, AUC 0.921 against 0.109, 0.853). Inside the city the AUC is only 0.614 (2005 to 2015) and 0.643 (2015 to 2005), and on the hotspot points the best single-feature rule ranked them higher than the model in three of the four cases, so the third rule failed. |
| **A2, Chennai plus water-ponding, water-flow and street-density features** | Do hydrology features fix the city core? | **Not met.** Held-out-block AP 0.243 against 0.238 for the Part A features (difference +0.0056 (-0.0207, +0.0322)); the new features had permutation importance near zero. |
| **C3, nationwide model applied to Chennai** (every training cell from the Chennai area removed) | Does it transfer to a place it never saw? | **Met, narrowly.** AP 0.073 (0.051, 0.103), AUC 0.759 (0.717, 0.797) against 0.064 and 0.701 for the best single feature; the AP difference is +0.0093 (+0.0001, +0.0183), so the AP gain is only just above zero and the AUC gain is +0.058. The base rate is 0.029. |
| **Routing round 1** (600 pairs, current classes) | Does a prior learned from 2005 keep routes out of the 2015 flood? | **Not met.** No prior, including the current one built from the 2015 hazard zones, reduced exposure for the commuter or pedestrian classes (reductions of at most 0.0015 of the route's length; the intervals include zero, except for two commuter variants, one of them the random allocation, whose reduction of 0.0003 is statistically above zero but negligible, so it is not evidence of skill). |
| **Routing round 2** (250 pairs, cautious travellers) | Can *any* prior help? Does the learned one when the router cares? | **Both rules not met.** An oracle prior built from the 2015 flood itself removes 84% of a walker's exposure (risk weight 20) at +39 min on a 315-minute walk, and 61% of a driver's (risk weight 5) at +3.1 min on 34. The learned and current priors removed essentially none. |
| **Routing C3** (nationwide prior, same 250 pairs) | Does the nationwide prior route around the flood? | **Not met.** See the table below. |

Routing results, December 2015 flood extent as truth (share of the route's length inside it; reductions are against a flat prior):

| Traveller | Prior | Share of route in the 2015 flood | Reduction vs flat (95% CI) | Added free-flow min |
|---|---|---|---|---|
| ped_l5 | flat | 0.109 | +0.0000 (+0.0000, +0.0000) | 0.0 |
| ped_l5 | gcc | 0.107 | +0.0023 (-0.0019, +0.0062) | 1.9 |
| ped_l5 | model05 | 0.109 | +0.0004 (-0.0017, +0.0025) | 2.6 |
| ped_l5 | national | 0.109 | -0.0000 (-0.0032, +0.0031) | 2.4 |
| ped_l5 | oracle | 0.023 | +0.0858 (+0.0751, +0.0968) | 24.9 |
| ped_l20 | flat | 0.109 | +0.0000 (+0.0000, +0.0000) | 0.0 |
| ped_l20 | gcc | 0.108 | +0.0014 (-0.0028, +0.0054) | 3.0 |
| ped_l20 | model05 | 0.109 | +0.0005 (-0.0021, +0.0031) | 6.0 |
| ped_l20 | national | 0.108 | +0.0009 (-0.0024, +0.0044) | 4.3 |
| ped_l20 | oracle | 0.018 | +0.0911 (+0.0799, +0.1025) | 38.8 |
| car_l5 | flat | 0.087 | +0.0000 (+0.0000, +0.0000) | 0.0 |
| car_l5 | gcc | 0.087 | -0.0001 (-0.0019, +0.0016) | 0.1 |
| car_l5 | model05 | 0.088 | -0.0012 (-0.0032, +0.0007) | 0.3 |
| car_l5 | national | 0.088 | -0.0012 (-0.0041, +0.0012) | 0.1 |
| car_l5 | oracle | 0.034 | +0.0534 (+0.0443, +0.0631) | 3.1 |

### What this means

1. **Terrain predicts where floods happen at the scale of a state or a river basin.** Across all 91 maps and held-out regions the terrain model is clearly better than the best single feature. Rainfall climatology adds nothing detectable. This is the clearest positive result here, and it is reproducible from the scripts.
2. **It does not predict which streets flood inside a city.** In Chennai the local model fails inside the city core; hydrology features did not rescue it; the nationwide model transfers to Chennai only weakly (AP about 2.6 times the base rate).
3. **A prior from this model does not make the router avoid a real flood.** Even the prior built from the 2015 hazard zones does not. The oracle shows the router *can* avoid it (61 to 84% of exposure at about 8 to 12% extra time) when the prior is correct, so the limit is the information in the prior, not the router. What changes routes is real, time-stamped evidence about particular streets, which is the data this project still lacks (ADR-024).
4. **No claim that this beats every other flood model.** It was compared with single-feature rules and with the existing prior, on these maps. It was not compared with published flood models, and we make no such claim.

### Limits

- Satellite flood maps (250 m MODIS) catch broad river and coastal flooding and miss street-scale urban flooding; negatives mean "not detected as flooded".
- Events overlap in space; blocks reduce but do not remove optimism. The secondary test on later events had one test event after excluding seen blocks and is not informative.
- The Global Flood Database licence (CC BY-NC-ND 4.0) forbids sharing derived material: the maps, the sampled cells and the trained models stay out of git; only aggregate results are committed. Everything regenerates from the scripts.
- Part A and A2 reuse the same Chennai extents, so they are not independent. Eight studies were run; the plans, additions and the changes made to them (memory limits, the class-name constraint, the geocoding fallback) are in the pre-registration files with their dates.
- Round 2's and C3's route tests use uniformly random node pairs, mostly long trips.
- The windowed feature builder agrees with the unwindowed one with correlation 1.000 on elevation, slope and relief and 0.97 on height above water (checked on one window).
- Nothing here has run on a phone, and no flood prior built from this work is in the app.

---

## ADR-027: The event state follows satellite rain by default, and a person can override it (5 October 2026)

**Status:** accepted by the owner on 5 October 2026 (decision), rule fixed the same day **before any replay or live trial**. The check described under *Validation* has not been run when this was written; its result will be added below, whatever it is.

**Context.** The event state (`dry`, `watch`, `active`) decides whether the static GCC hazard prior is applied (ADR-015, F-09). Until now a person set it by hand (`PUT /event-state` with the admin token) or the server's `EVENT_STATE` setting applied; the demo has run at `active`. ADR-026 and the NASA IMERG adapter (`server/app/ingest/imerg.py`, `GET /context/rain`) give a keyless satellite rain measure for Chennai. Options put to the owner: A manual, B automatic from rain, C suggest only. The owner chose **B with a human override**.

**Decision.**
1. **Default (mode `auto`).** The router service polls the report server's `/context/rain` every 15 minutes and sets the state from the rule below.
2. **Override (mode `manual`).** `PUT /event-state` with the admin token sets a state that wins over the rain rule. It stays until cleared, or for `hours` if given. `PUT /event-state {"mode": "auto"}` returns to the rain rule. The response and `GET /event-state` always say which mode and why.
3. **Mode `fixed`.** If no rain source is configured (no `OBSERVATIONS_URL`), the configured `EVENT_STATE` applies as before. Behaviour is unchanged for existing deployments that do not set the source.
4. **If the feed fails.** When the rain data is older than 12 hours, or no poll has succeeded for 12 hours, or none has ever succeeded, the state falls back to the configured `EVENT_STATE` (default `active`, the cautious setting) and is reported as `source: fallback`. Nothing is invented.

**The rule (placeholders; parameters fixed now, not tuned later).** Inputs are from the last three hours of the rain context: `A` = area-mean accumulation (mm), `P` = highest single-cell rate (mm/h).

| Level | Condition |
|---|---|
| `active` | `A >= 15 mm` or `P >= 25 mm/h` |
| `watch` | `A >= 8 mm` or `P >= 7.6 mm/h` |
| `dry` | otherwise |

*Holds*, because waterlogging outlasts rain and the data runs about six hours behind: after a reading at `active`, stay at `active` for 6 hours from when it was seen; after a reading at `watch` or higher, stay at `watch` or higher for 12 hours from when it was seen. Holds are counted from when the service saw the reading, not from the satellite time, so the data lag does not use them up. They are kept in memory; a restart forgets them (limitation).

*Where the numbers come from.* Not fitted to Chennai floods. `8 mm` and `15 mm` in three hours are the sustained rates of IMD's *heavy* (64.5 to 115.5 mm in 24 h) and *very heavy* (115.6 to 204.4 mm in 24 h) daily classes (64.5 / 24 x 3 = 8.1; 115.6 / 24 x 3 = 14.5). [UNVERIFIED: IMD class limits recalled, not opened in this session; check before citing.] `7.6 mm/h` is the lower bound of the generic *heavy* hourly band in `imerg.py`; `25 mm/h` is a round placeholder between that and the *violent* band at 50 mm/h.

**Disclosure about independence.** Before these numbers were fixed, the live adapter run had already shown the IMERG values for Michaung on 4 December 2023 (area mean about 6.6 mm/h, cell peak 9.7 to 12.2 mm/h). A three-hour accumulation near 20 mm from those values reaches `active` under this rule, so **Michaung is not an independent test of it**. The numbers were chosen from the IMD classes above, not by adjusting until Michaung passed, but the owner should read that sentence as a disclosure, not a reassurance.

**Limits, stated plainly.**
- **Late.** The newest image was about six hours old at the first live check, so the rule reacts hours after rain starts and cannot warn ahead. A forecast input would be needed for that; not built.
- **Coarse.** A cell is about 10 km; the Chennai box holds a handful. It can miss a local downpour and cannot see which street floods.
- **Not a flood measure.** Rain is not flooding; drainage, tides and tank releases matter. The rule only decides whether the static map is applied.
- **Every user is affected at once** by a switch, including a wrong one. That is why the override exists and why the mode and reason are always reported.
- **A dry reading turns the map off.** On a `dry` state the router ignores the prior and routes on road speeds and citizen reports only, and the advisor says "no flood event is under way". The demo, which has been fixed at `active`, will show `dry` on dry days from now on.

**Validation (to be run after the implementation, with these windows fixed now).** Replay the rule with the IMERG archive at 00, 06, 12 and 18 UTC (each with its six preceding half-hour images) over: **flood windows** 1 to 3 December 2015 (the project's replay day is 2 December 2015), 3 to 5 December 2023, and 29 November to 1 December 2025; **dry controls** 5 to 7 March 2024 and 10 to 12 April 2025. Report what state the rule gives at each time, in a result file. Expected, not guaranteed: `watch` or `active` on the flood windows, `dry` on the controls. A miss or a false alarm is reported as a negative result and the rule is not adjusted to remove it; any change is a new ADR with the reason.

**Not decided here.** Whether the app should show *why* the state is what it is (the server reports it; the app banner does not yet use it). Whether to add a forecast input.

### Validation result (run 5 October 2026 16:39 UTC; `data/results/2026-10-05-imerg-event-rule-replay/result.json`)

Run with the windows and numbers above, unchanged. Instantaneous level (no holds) at 00, 06, 12 and 18 UTC, from the six half-hour images ending at each time:

| Window | Highest level | Times at `watch` or higher | Criterion met? |
|---|---|---|---|
| 1 to 3 Dec 2015 (flood) | `active` | 4 of 12 (1 Dec 06:00 to 2 Dec 00:00) | yes |
| 3 to 5 Dec 2023 Michaung (flood; not independent) | `active` | 6 of 12 (3 Dec 18:00 to 4 Dec 18:00) | yes |
| 29 Nov to 1 Dec 2025 (north-east monsoon) | `watch` | 2 of 12 | yes, weakly (see below) |
| 5 to 7 Mar 2024 (dry control) | `dry` | 0 of 12 | yes |
| 10 to 12 Apr 2025 (dry control) | `watch` | 1 of 12 (11 Apr 00:00) | **no: a false alarm** |

Three of three flood windows and one of two controls met the criterion written in advance. Read it this way:
- **The April 2025 false alarm is a result, not noise to tune away.** That reading had a three-hour area mean of only 4.8 mm but one cell at 23.05 mm/h, so the single-cell condition (`P >= 7.6 mm/h`) fired. A brief convective shower can therefore switch the hazard map on; with the 12-hour hold, one such reading would keep it on for half a day. The rule was **not** changed. Whether to raise the cell threshold, require two cells, or drop the cell condition is a decision for the owner and, if taken, a new ADR with this table as its reason.
- **The November 2025 window is weak evidence.** It was chosen as a north-east monsoon window; it was never checked that Chennai flooded then. It reached `watch` twice (7.2 mm and 13.5 mm in three hours) and never `active`. It neither supports nor undermines the rule.
- **December 2015 and Michaung fit the rule,** and 2 December 2015 (the project's replay proxy day) falls in the tail of the 2015 window, where the rule has returned to `dry` by 06:00 UTC; with the holds the live rule would still read `watch` for 12 hours from the last `watch` reading. Michaung was seen before the numbers were fixed.
- **Not tested: timeliness.** The replay uses images ending at each time. Live, the newest image is about six hours old, so a real switch comes about six hours after the replay's time. The replay measures whether the rule can tell wet from dry, not whether it is early enough to help anyone.
- **Not tested: whether the hazard map helps** when it is switched on. That needs street-level, time-stamped passability data, which does not exist yet.

**Owner's decision on the false alarm (5 October 2026): leave the rule as found, for now.** The single-cell condition stays at 7.6 mm/h for `watch` and 25 mm/h for `active`. The cost accepted: a brief shower can keep the 2015 hazard map on for up to 12 hours. The rule is deployed in this form (live from 16:49 UTC). Revisit when there is more evidence, for example after the coming north-east monsoon: how often the rule switches, whether any switch matched a real event, and whether an operator had to override it. Any change then is a new ADR that cites the replay table above.


## ADR-028: A volunteer field log, kept apart from the router, to produce the missing ground truth (6 October 2026)

**Status:** built and tested locally; **not deployed, no volunteer has used it, no field data exists.** Written while the owner was away; the owner has not reviewed it.

**Context.** Every result so far ends at the same wall: there is no independent, time-stamped, street-level record of which roads were passable when. The replay corpus has one proxy timestamp and no depth (CLAUDE.md §4.4); Study 2's label is a co-location artefact (§5.3); ADR-027's rain rule was checked only for "wet versus dry" and never against a street (F-36); the 15 October 2026 gate asks for a live, timestamped passability feed and `NEXT_STEPS.md` lists a field-label pilot as the cheapest way to start one. A person standing at a point and saying "passable", "not passable" or "can't tell" is the oldest form of that evidence. The tool to collect it did not exist.

**Decision.** Build a small volunteer field log as part of the report server, under `/fieldlog` (reached as `/ingest/fieldlog/` in the one-container image), and keep it **separate from the router, the belief and the report store.**

*What it is.*
- A web page for a phone (English and Tamil; the Tamil is an unreviewed draft). A volunteer picks a site, taps one of three states, optionally a depth band if not passable, confirms, and the entry is stored on the phone and sent when there is a connection.
- 402 **candidate sites**: the centres of the GCC flood-hazard zones in `data/watchlist/2026-09-14/watchlist_candidates.json` (316 `High`, 86 `Very High`), each with the nearest OSM place name within 2 km (400 of 402) so a volunteer can search by area. **None is verified on the ground**; the page says so. 216 have no street name. A volunteer who finds the site is not at that point logs the nearest real spot, or uses "another place" (`adhoc`), which sends the spot's position rounded to about 10 m.
- Entries: `entry_id` (a UUID made on the phone), `site_id`, `state` (`passable` / `not_passable` / `unknown`), `observed_at` (the phone's clock, with zone), optional `depth_band` (`ankle` / `knee` / `above_knee` / `unknown`, only with `not_passable`), `client`; the server adds `volunteer` (a pseudonymous code), `received_at` and `lag_seconds`. No names, no free text, no photos in this version.
- `unknown` is a real answer. A volunteer who cannot tell must be able to say so without being counted as "passable".

*What it is not.*
- **It does not change any route and is not shown to any traveller.** Nothing in the router, the belief engine, `HazardObservation` or `docs/CONTRACTS.md` was touched. There is no switch that feeds it into the belief. Doing that would be a new ADR that says at what trust and how decay applies.
- It never says a road is safe (ADR-011). The page text and its Tamil twin are tested against a list of banned words ("safe", "dry", "clear", "open", "fine" and others); "passable" is the volunteer's own word for what they saw, and the stored label is `passable`, not "safe".

*Engineering choices, and why.*
- **Append-only, fsynced daily JSONL files; nothing is edited or deleted by the service.** A wrong entry is kept and a later one is added; analysis decides what to do. Reason: ground truth that can be quietly rewritten is not ground truth.
- **Idempotent by `entry_id`.** The same entry sent again with identical content returns 200 `duplicate`; the same id with different content returns 409 and nothing is changed. A phone that lost a response can therefore resend safely.
- **Offline first.** The queue lives in the phone's `localStorage`; sync rules are by HTTP status (retry on network error, 5xx and 429; stop on 401 and 403 and keep the queue; mark 4xx validation errors as rejected so they do not block the rest). Entries older than 14 days or more than 5 minutes in the future are refused by the server, because a wrong phone clock would put the observation in the wrong rain event; the page warns when the phone's clock differs from the server's.
- **Per-volunteer tokens from the environment** (`FIELDLOG_TOKENS`), compared in constant time. No tokens configured means logging is **off** (403), never open. A token shorter than 16 characters is refused and counted. Reading and exporting need a separate `FIELDLOG_ADMIN_TOKEN`.
- **Wrong guesses are slowed, but a valid token is never refused because of them.** In the single-container image many users arrive from one proxy address; a lockout that also blocked valid tokens would let anyone lock every volunteer out. This was first built the other way and changed after reasoning about the proxy case.
- **Rate limits** per volunteer: 300 per hour and 2,000 per day, to stop a runaway script, not a busy volunteer.
- **Strict page headers** (a Content Security Policy with no inline script or style, no third-party requests, geolocation allowed for the page only to sort the site list; the position never leaves the phone for listed sites).
- **CSV export is formula-safe** (cells starting with `=`, `+`, `-`, `@` are prefixed) because the file will be opened in a spreadsheet.
- **A service worker caches the page shell so it opens offline. It is untested in a real browser** (the embedded browser used in development blocks service-worker registration). The page works without it; only "open the page with no signal" depends on it.

**Limits, stated plainly.**
- **Storage is not durable on a free host.** The log is files on the container's disk. Render's free tier wipes that on a restart, a redeploy and (as far as is known) when the service sleeps. `/fieldlog/health` says `durable: false` unless the operator sets `FIELDLOG_DURABLE=1` after attaching a persistent disk; until then the log must be exported after every logging day (`scripts/fieldlog_ops.py export`, which checks the row count and prints a SHA-256). Not durable storage is the largest practical risk to the data.
- **Candidate sites are not verified passage points.** A hazard-zone centroid snapped to a road may be a field, a flyover or the wrong street. Counting `not_passable` at such a point measures the zone, not a street.
- **Volunteers choose when and where to look.** People log when it is wet and where they can reach, so the data will over-represent rain days and accessible places. The protocol asks for a paired dry-day control, but that reduces the problem, it does not remove it.
- **One observer, one moment, a phone clock.** There is no photo to check against. The protocol asks for occasional paired observations to measure how often two people disagree.
- **Privacy.** A volunteer code plus a time and a place is personal data about the volunteer. See `docs/FIELD_PROTOCOL.md` for the notice, retention and deletion; whether this meets the DPDP Act 2023 is **not established** and nobody on the team is a lawyer. Whether recruiting people beyond the team needs institutional ethics approval is for the owner to check with the institution (`docs/ethics/`).
- **Tamil text is a first draft**, never read by a native speaker.
- **No photo evidence**, although the field-label pilot in `NEXT_STEPS.md` mentions one. Photos carry faces, number plates and exact locations; adding them needs a storage and consent decision first.

**Analysis is pre-registered in `docs/FIELD_PROTOCOL.md` §8, before any data exists, and no analysis code has been written.** The ground truth must not be fitted to the models it will judge. Any use of field data to change ADR-027's thresholds, the prior, or the router is a new ADR citing the results file.

**Not decided here (owner).**
1. Who issues tokens and to whom (the team only, or outside volunteers).
2. Persistent storage: a free database account (Supabase, which `server/README.md` already describes) or a persistent disk on a paid plan. Either needs an account the owner creates.
3. Whether field data may ever feed the belief, and if so at what reliability α.
4. Whether to ask for institutional ethics review before outside volunteers.
5. Whether to deploy now. The local commits are not pushed.


## ADR-029: A rain forecast may raise the event state from `dry` to `watch`, if a pre-registered replay supports it (8 October 2026)

**Status:** built, replayed, and **not adopted**: the pre-registered criteria were not met (result at the end of this record), so the forecast stays off by default. The rule and validation below were committed before any forecast value for the test periods was read. Task M3.7.

**Context.** ADR-027 switches the event state from NASA IMERG satellite rain. The newest image is about six hours old (F-36), so the state changes hours after rain starts and cannot warn ahead. The router already defines `watch` as "a forecast or alert is in force" (`EventState` in `routing_engine.dart`); nothing sets it from a forecast. A numerical weather forecast is the only free input that looks ahead.

**Decision (the rule, fixed now).**
- **Source.** Open-Meteo's forecast API, model `ecmwf_ifs025` (ECMWF IFS 0.25°, ECMWF open data), hourly `precipitation` (mm in the preceding hour), at nine points: latitudes 12.80, 13.00, 13.20 by longitudes 80.00, 80.15, 80.30 (inside the Chennai box of `config/cities.yaml`). No other model, variable or point set.
- **Numbers.** Per hourly stamp, the area mean is the mean over the nine points. A three-hour accumulation ending at stamp H is the sum of the area means at H-2, H-1 and H.
- **Level.** At time t, take the stamps H with t < H <= t + 12 h and every three-hour window whose three stamps all lie there (ten windows). The forecast level is `watch` if the largest of those accumulations is **at least 8.0 mm**, otherwise `dry`. **A forecast never gives `active`.** The 8.0 mm is ADR-027's own `watch` accumulation, reused, not chosen for this rule. There is no single-point rate condition: model fields are smooth, and ADR-027's single-cell condition is what produced its April 2025 false alarm.
- **How it combines.** Only in automatic mode. The state in force is the higher of the ADR-027 state and the forecast level, so the forecast can raise `dry` to `watch` and can never lower anything. An operator override still wins. The status says `source: forecast` and gives the number when the forecast is what raised it.
- **When it is not trusted.** If the last successful forecast fetch is more than 6 hours old, or fewer than 9 of the 12 future stamps are present, the forecast is ignored and the ADR-027 rule runs alone. A failed forecast never triggers the configured fallback; only the rain rule does that.
- **Switch.** The router uses the forecast only when `EVENT_FORECAST=1`. **Default off.** It stays off by default unless the adoption criteria below are met and the owner agrees.
- **Load.** One request (nine points) every 30 minutes, about 48 a day.

**Validation (fixed now; run after the implementation).**
- *Periods.* P1 = 1 October to 31 December 2024 and P2 = 1 October to 31 December 2025 (north-east monsoons); P3 = 1 March to 30 April 2025 (dry season). The 2015 flood and Michaung (December 2023) are not testable: the forecast archive starts in January 2024 for these models.
- *Times.* T = 00, 06, 12 and 18 UTC of every day: 368 + 368 + 244 = 980 times.
- *Truth.* The ADR-027 instantaneous level from IMERG at T, computed exactly as `scripts/imerg_rule_replay.py` does (six half-hour images ending at T, no holds). **Wet** means that level is `watch` or `active`. Secondary truth, reported beside it: the IMERG three-hour area mean alone is at least 8 mm (no cell condition).
- *Forecasts.* Open-Meteo's Previous Runs archive for the same model and points. **Primary: `precipitation_previous_day1`**, the value forecast 24 hours before its valid time (this is longer notice than the live service uses, so it is the cautious case). Secondary: `precipitation` (the current run, `day0`; the optimistic case). Secondary model for context only, not for the decision: `gfs_seamless`.
- *Measures.*
  - **M1, same-time agreement (P1 + P2).** F(T) = `watch` if the forecast three-hour accumulation over the stamps T-2h, T-1h, T is at least 8 mm. Table of F(T) against wet(T); probability of detection (POD = hits / wet times) and false alarm ratio (FAR = false alarms / forecast-wet times). 95% intervals by bootstrap over calendar days, 10,000 resamples, seed 20260918.
  - **M2, warning ahead (P1 + P2).** A wet episode is a maximal run of consecutive wet times. It is *warned ahead* if the live rule above, evaluated at T0 - 6 h (T0 = the episode's first wet time), gives `watch`. The live satellite rule would see T0 only about six hours after T0, so a warned episode means at least about 12 hours' more notice. Report the share of episodes warned ahead.
  - **M3, false switching.** In P3, the share of times at which the live rule gives `watch`. In P1 + P2, the share of the live rule's `watch` times followed by no wet time at T + 6 h or T + 12 h.
- *Adoption criteria (all on ECMWF, `day1`, primary truth; choices made here, not derived from data):*
  1. POD at least 0.5 and FAR at most 0.5 (point estimates);
  2. at least half of the wet episodes warned ahead; if P1 + P2 hold fewer than 10 wet episodes, this criterion is "not testable" and adoption is not recommended;
  3. false switching in P3 at most 5% of times.
  If all three hold, the recommendation is to turn the forecast on by default (the owner decides). If any fails, it stays off by default and the result is reported as negative. A change of threshold, horizon, model or points after seeing these results is a new ADR, and it could not be validated on the same periods.

**Disclosure about independence.** IMERG values for 29 November to 1 December 2025 and 10 to 12 April 2025 were seen in the ADR-027 replay; both windows lie inside P2 and P3. No forecast value for any period was seen before this record was committed: the availability check printed only how many hourly values exist (all complete for all four models probed). The 12-hour horizon and the nine points were chosen here without data.

**Limits, stated plainly.**
- **The truth is satellite rain, not flooding.** The replay asks whether the forecast tells earlier what the satellite will say later. It says nothing about streets.
- **Six-hourly truth.** Short showers between the four daily times are invisible to both sides. IMERG images ending at T cover roughly T - 2.5 h to T + 0.5 h; the forecast stamps cover T - 3 h to T. The half-hour offset is kept, not corrected.
- **The archive is not the live feed.** The live service sees the newest run, published some hours after it starts; `day1` (24 h notice) understates and `day0` overstates what it would have had.
- **Licence.** Open-Meteo's free API is for non-commercial use (`docs/LICENCE_AUDIT.md`, row 2); its data is CC BY 4.0, and ECMWF open data is CC BY 4.0. Fine for this research project; a commercial deployment would need Open-Meteo's paid plan, a self-hosted Open-Meteo, or ECMWF open data read directly.
- **Small sample.** Two monsoon seasons will hold tens of wet times, not hundreds. The intervals will be wide and are reported as they are.


### Validation result (run 8 October 2026, 22:09 to 22:41 IST; `data/results/2026-10-08-forecast-rule-replay/result.json`)

Run exactly as registered above (pre-registration commit `0c9c6d0`, code commit `25c8d51`). All 980 times had IMERG truth (no image missing). Wet times: 23 in P1, 23 in P2, 4 in P3 (all four in the dry season from the single-cell condition); 24 wet episodes in P1 + P2.

**Primary (ECMWF, forecast made 24 h ahead, truth = ADR-027 level): the adoption criteria were NOT met.**

| Measure | Result | Criterion | Met? |
|---|---|---|---|
| M1 same-time detection (P1 + P2) | 7 hits, 39 misses, 5 false alarms, 685 correct negatives. POD **0.15** (95% day-bootstrap 0.05 to 0.28); FAR **0.42** (0.17 to 0.73) | POD at least 0.5 and FAR at most 0.5 | **no** (POD) |
| M2 warned ahead | **5 of 24** wet episodes (21%) | at least half | **no** |
| M3 false switching, dry season | 0 of 244 times | at most 5% | yes |
| M3 monsoon `watch` times not followed by a wet reading within 12 h | 13 of 29 (45%) | (reported, no criterion) | |

**Decision: the forecast stays off by default** (`EVENT_FORECAST` unset). The code stays, tested, so the owner can switch it on knowingly; it is not recommended.

Secondary results, reported as registered, **not** used for the decision:

| Forecast | Truth | POD (95%) | FAR (95%) | Episodes warned | Dry-season switching |
|---|---|---|---|---|---|
| ECMWF, current run (`day0`, optimistic) | ADR-027 level | 0.26 (0.13 to 0.40) | 0.33 (0.13 to 0.55) | 13 of 24 | 0 of 244 |
| ECMWF, 24 h ahead | 3 h area mean at least 8 mm | 0.25 (0.09 to 0.42) | 0.42 (0.17 to 0.73) | 6 of 17 | 0 of 244 |
| ECMWF, current run | 3 h area mean at least 8 mm | 0.32 (0.14 to 0.50) | 0.50 (0.29 to 0.75) | 9 of 17 | 0 of 244 |
| GFS, 24 h ahead | ADR-027 level | 0.11 (0.02 to 0.22) | 0.55 (0.27 to 0.88) | 4 of 24 | 0 of 244 |
| GFS, current run | ADR-027 level | 0.15 (0.03 to 0.29) | 0.50 (0.21 to 0.83) | 5 of 24 | 0 of 244 |

How to read it:
- **The forecast is quiet, not noisy.** It never switched on in the dry season, and when it did switch on in the monsoon it was right a little over half the time. Its failure is the other way: **it misses most of the rain the satellite later sees** (85% of wet times at 24 h notice). A three-hour, 8 mm area-mean threshold on a 25 km model mostly does not fire for Chennai's rain.
- **Even the optimistic case does not pass.** With the current run, half the episodes (13 of 24) would have been warned ahead, which would meet criterion 2, but detection is still 0.26. The registered decision rests on the 24-hour-ahead case and is not revisited.
- **The obvious next idea is a lower threshold. It is not tried here.** Lowering it after seeing these numbers would be tuning on the test data; it would need a new ADR and periods not used here (for example the 2026 north-east monsoon, scored after it ends).
- **Small sample.** 46 wet times and 24 episodes in two seasons; the intervals are wide. The result is "no evidence that this rule helps", not "forecasts cannot help".
- **The truth is satellite rain, not flooding,** as stated above. Nothing here says anything about streets.


## ADR-030: A local event miner that turns official posts and news into reviewed, quoted, place-matched street events (8 October 2026)

**Status:** accepted for building; evaluation pre-registered here **before** any real item is labelled or mined. Task M3.4 (first part). The owner chose this feature and the model (8 October 2026).

**Context.** The project lacks time-stamped, street-level evidence (CLAUDE.md §0 item 9). Official accounts and news already publish it in words: "traffic diverted at the Ganesapuram subway", "water receded, traffic restored on 100 Feet Road". Nobody turns those words into records with a place, a time, a condition and a source. A language model can read them; it can also invent places, misread conditions and drop negations. In the first trial on this laptop (8 October), Gemma 4 E4B read a made-up sentence "Traffic diverted at Ganesapuram subway due to waterlogging" as `passable`. That one wrong answer is why everything below is checked and reviewed.

**Decision.**
- **Where it runs.** An operator tool in `ml/event_miner/`, on a laptop with Ollama. It does not run on the free host (512 MB) and is not shown to travellers.
- **Model.** `qwen3.5:0.8b` through Ollama (Qwen, Apache 2.0, February 2026; text and images; 201 languages, Tamil not named in its documentation). Chosen by the owner because it is small enough to consider for a phone later. Gemma 4 E4B (installed) was measured on this laptop at 0.73 tokens/s reading and 3.6 tokens/s writing, too slow to use. Places are retrieved with `nomic-embed-text` (Apache 2.0, already installed). The model's Ollama digest is recorded with every output.
- **Input.** Text pasted or loaded from a file by an operator, with the source link, the source name and the publication time. **No automatic fetching**: each feed (a newspaper's RSS, an official account) needs the owner's go-ahead and a check of its terms first. Posts on platforms whose terms forbid automated collection are pasted by a person, never scraped.
- **Extraction (step 2 of PLAN §8.3).** Strict JSON constrained by a schema: per event `place_text`, `condition` (`flooded`, `closed`, `cleared`, `unknown`), `time_text`, `depth_words`, `quote`. Temperature 0, fixed seed 20260918, thinking off.
  - **Quote rule.** Every event must carry a quote that appears word for word in the source (after normalising spaces and quote marks). An event whose quote is not found is dropped and counted. The model cannot add a claim the text does not contain.
  - `cleared` matters: "water receded", "traffic restored" are the negative evidence the 2015 corpus never had (§4.4).
- **Places (step 3).** Candidates come from the project's gazetteer only: 661 OSM places (ODbL, 396 with Tamil names) and the 402 field-log candidate sites. Retrieval combines a lexical match and an embedding match; the model then chooses one of at most five listed candidates or `none`, through a schema that allows only those ids. **It never supplies a coordinate.** The 22 GCC subways are not in the gazetteer yet (M3.1); an event at a subway that is not listed is expected to come out `none`, and that is counted, not hidden.
- **Duplicates (step 4).** Same place id, same condition, same source and publication times within 6 hours: flagged as a duplicate, kept.
- **Review (step 5).** Every event waits for a person: accept, reject, or correct the place or the condition. Decisions are appended, never edited, with a reviewer code and time. **Accepted events are exported as a reviewed dataset; they do not enter the router's observations, the belief, or any route.** Feeding them anywhere is a new ADR (it needs a source class, a reliability and a decay that do not exist today, and `docs/CONTRACTS.md` is the owner's).
- **Storage.** Source text, extractions and decisions live in `data/miner/`, git-ignored: news text is copyrighted and posts can name people. Only aggregate results are committed.

**Evaluation (pre-registered; step 6).**
- *Test set.* At least 100 real items about Chennai rain (posts or news paragraphs, any year), collected by a team member from sources they may read, **labelled before the miner is run on them**, and never used in prompts or examples. Aim for at least 30 in Tamil and at least 20 with no street event at all.
- *Labels per item.* Every street event the text states: the gazetteer id of the most specific matching entry, or `none` with the place text; the condition; whether a time is stated. A second person labels a fifth of the items independently; agreement is reported.
- *Measures* (reported overall and separately for English and Tamil, as counts and shares):
  - event precision and recall: a mined event matches a gold event when the place id is the same (or both are `none` with the same place text, judged by the labeller) and the condition is the same;
  - place accuracy: among gold events that have a gazetteer id, the share the miner gave the same id; and within 200 m;
  - condition accuracy among place-matched events;
  - the share of events dropped by the quote rule; the share of gold events whose place is not in the gazetteer;
  - time per item on this laptop.
- *Bar, fixed now.* The miner is called **useful for suggestions** in a language if event precision is at least 0.7 and recall at least 0.6 there. Whatever the result, nothing skips review under this ADR. If the bar is not met, the result is reported as negative; trying a larger model (for example `qwen3.5:2b`) is a new ADR with a new test set or the same set re-run and reported as a second, not independent, attempt.
- *Prompts and examples* are fixed in code before labelling; the examples in the prompt are made-up sentences, written for the prompt, not taken from any source. Changing the prompt after seeing test results makes the next run a second attempt, reported as such.

**Limits.**
- A 0.8-billion-parameter model is small. It may miss events, confuse `closed` with `flooded`, and handle Tamil poorly. Measurement, not hope, decides.
- The gazetteer is areas and candidate sites, not streets or subways. Many events will map only to an area, which is coarse.
- Unit tests use a fake model; they prove the checks work, not that the model is accurate.
- Legal: copying a post into a local file for research is believed to be fair dealing; this is **not established**. Whether names in posts make this personal data processing under the DPDP Act is **not established**.
