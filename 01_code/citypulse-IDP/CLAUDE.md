> **SUPERSEDED IN PART (2 October 2026). Read `../../CLAUDE.md` first.**
> This file is the team's original brief (17 September 2026). Its engineering, legal and convention rules (sections 3, 5 and 7) still apply.
> Several claims below were shown to be wrong in the October 2026 review:
> - "less evidence means more caution" (the index is non-monotone; KNOWN_FLAWS F-01);
> - ALT is not used by `planRoute` (F-11);
> - the "ALT admissibility" result is Delling and Wagner (2007), not new;
> - "on-device" has never been run on a device (F-06);
> - explanations are not verified (F-04, F-05).
> Use the top-level `CLAUDE.md` §6 wording table.

# CLAUDE.md — CityPulse AI

**Read this file completely before doing anything. It is the contract for how work happens in this repo.**

**Reframed 2026-09-17: this is a startup product build, not an academic research exercise.**
The deliverable is **a finished, working product**. An evaluation/paper may happen later (see
`paper/`), and when it does, ground it in what's actually built and measured — but do not let
novelty-defensibility or academic framing gate implementation decisions day to day. §9 below
(the novelty analysis) is retained as background for whenever this *is* formally evaluated, not
as a running constraint on what to build. Everything else in this file — the engineering and
legal constraints in §3, the architecture in §5, the model in §6, conventions in §7 — is exactly
as binding as before; only the research-project framing changed.

Team: Pragatish N, Ravi, Jyotish.

---

## 1. What CityPulse AI is (in one paragraph)

A hazard-aware urban routing system for Chennai. It fuses live and historical hazard
signals (flooding, waterlogging, road incidents, air quality, heat) onto an OpenStreetMap
road graph, computes routes that trade travel time against *probability-weighted* hazard
exposure, explains each routing decision in natural language, and continues to do all of
this **on the device with zero network connectivity**. Confidence in every hazard signal
decays with age on a per-hazard-class schedule, and that confidence is surfaced to the user
rather than hidden.

**The one-line claim we can actually defend:** *route, confidence state, and a verified
natural-language rationale, all produced on-device when the network is gone.*

---

## 2. Read these before writing code

| File | What it gives you |
|---|---|
| `docs/PROJECT_BRIEF.md` | The original pitch as presented. Historical record — **contains claims we have since disproved.** |
| `research/SYNTHESIS.md` | **Start here.** The merged findings, resolved design decisions, and the honest novelty position. |
| `docs/DECISIONS.md` | Architecture decision records. If you disagree with a choice, read the ADR first. |
| `docs/ARCHITECTURE.md` | The system as it is actually to be built. |
| `docs/APIS_AND_COSTS.md` | Every external service, its free-tier quota, and the traps. Budget is ₹0. |
| `docs/ROADMAP.md` | Week-by-week plan with the critical path marked. |
| `docs/EVALUATION.md` | The five studies that go in the paper. Build for these, not for the demo alone. |
| `docs/CHENNAI_PROTOTYPE_SPEC.md` | **What we build first.** v0 scope, the Chennai watchlist, the demo, and the success criteria. Overrides the deck. |
| `docs/COUNCIL_VERDICT.md` | The Roast Council's verdict and the standing risks. |
| `docs/IMPLEMENTATION_PLAN.md` | **Task-by-task build plan**, with the reasoning behind the sequencing. Pick work from here. |
| `docs/CONTRACTS.md` | The shared schemas — hazard observation, edge belief, **decision trace**, verification result. Four components depend on these; change only by ADR. |
| `docs/IMPROVEMENTS.md` | Ranked improvement ideas beyond the pitch, with what each buys the paper. |
| `docs/REVIEW_CHECKLIST.md` | What a reviewer checks, research integrity first. |
| `docs/GLOSSARY.md` | Notation and shared vocabulary. |
| `paper/OUTLINE.md` | Section-by-section paper skeleton with what evidence each section needs. |
| `research/raw/*.md` | The seven deep-research reports (~440 KB, ~250 sources). Cite from these — after opening the source. |
| `.claude/agents/*.md` | Role briefs: implementer, reviewer, experimentalist, paper-writer, data-wrangler. |

---

## 3. Hard constraints — do not violate these

1. **Budget is ₹0.** Every service must sit inside a free tier with no credit card. See
   `docs/APIS_AND_COSTS.md`. If a task seems to need paid infrastructure, stop and flag it
   rather than signing anything up.
2. **Never use Google Maps Platform data.** Its terms forbid using Google-derived data in a
   competing navigation product and forbid caching/offline storage — which is our core
   feature. Mixing it with OSM also creates an ODbL contamination problem. This is a
   project-ending legal risk, not a preference. (`research/raw/C-data-sources.md` §5.1)
3. **Never use `tile.openstreetmap.org` in the app.** The OSM tile usage policy explicitly
   prohibits bulk download for offline use. Use self-hosted PMTiles.
4. **No passive location inference without explicit consent.** India's DPDP Act 2023 (Rules
   notified 2025) applies. See ADR-006 — Haven Mode has been rescoped to explicit
   user-entered places for exactly this reason.
5. **The LLM never invents facts.** Every number and place name in an explanation must come
   from the router's structured decision trace and be verified before display. See ADR-004.
6. **The LLM never produces route geometry.** Graph search does. The pitch deck says
   otherwise; the pitch deck is wrong.
7. **Do not overclaim in writing.** We do not have live street-level flood depth for Chennai
   and no obtainable source provides it. Every document must say so. Overclaiming here is
   the single most likely thing to sink the project at review.

---

## 4. Current state

**Phase: core implementation well underway.** `docs/IMPLEMENTATION_PLAN.md` is the live,
authoritative record of what's built vs. pending — check it, not this section, for the current
task-by-task status; this section is a snapshot and will drift.

**v0 is scoped to a bounded Chennai watchlist (ADR-009).** We do not attempt to know the flood
state of every road — we maintain ~150–200 chronic waterlogging points and say plainly when we
have no data. Read `docs/CHENNAI_PROTOTYPE_SPEC.md` before picking up any task.

Built and passing, as of 2026-09-17: the routing core (`pulse_router`), the belief/fusion model
(`pulse_belief`), the template explanation renderer and symbolic verifier (`pulse_explain`), a
real Chennai road graph with static hazard prior, a 6,000+-event historical flood corpus, a
deterministic replay/evaluation harness, a Flutter client shell with offline routing and a local
hazard cache, and a FastAPI ingest server. ~250+ tests passing across the stack. Pick up
remaining work from `docs/IMPLEMENTATION_PLAN.md`'s task list.

**Still blocked on the human running this, not on code:**
1. **Benchmark a quantized SLM on the cheapest target Android phone** (₹10–15k class, not a
   flagship) — needs a physical device in hand.
2. **The ethics/IEC application** for the human study — an institutional submission with its
   own lead time.
3. **Free-tier account creation** (Supabase, Upstash, TomTom, OpenAQ, Groq) — see
   `docs/data-access-log.md`; the server/client are built to run without these but need real
   credentials to go live.

---

## 5. Architecture in brief

```
OSM (Geofabrik TN extract, pinned snapshot)
        │
        ▼
  Graph builder  ──► CSR adjacency + ALT landmarks + static hazard prior ℓ₀(e)
        │                        │
        │                        ├──► shipped to device (~20 MB)
        ▼                        ▼
  FastAPI server            Flutter client
   - hazard ingest           - pulse_router (Dart, same code as server)
   - PostGIS + Redis         - local hazard cache (SQLite + R*Tree)
   - SSE push                - PMTiles basemap (offline)
   - cloud LLM (online)      - template NLG (always) + optional SLM rewriter
   - append-only log         - outbox → syncs on reconnect
```

**We own the router.** We do not use OSRM (cannot do per-request cost models; ~20 min
re-customization), and not GraphHopper on-device (its Android offline support is
unmaintained). Valhalla is a documented stretch goal for turn-by-turn narration only.
Rationale in ADR-001.

**One router implementation, two consumers.** `packages/pulse_router` is a pure Dart
package. The Flutter app imports it directly; the Python evaluation harness shells out to
its AOT-compiled CLI. Never fork the algorithm into a second language — a divergence
between the demo router and the evaluated router invalidates the paper.

---

## 6. The core model (know this cold — it is the contribution)

Hazard belief on edge `e` at time `t`, fused in log-odds with per-class temporal decay:

```
ℓ(e,t) = ℓ₀(e) + Σᵢ yᵢ · κ(d(e,xᵢ)) · exp(−(t−tᵢ)/T_c) · logit(α_{cᵢ})
p̄(e,t) = σ(ℓ(e,t))
n_eff(e,t) = Σᵢ κ(d(e,xᵢ)) · exp(−(t−tᵢ)/T_c)
```

`ℓ₀` is the static terrain prior (elevation, HAND, drainage, historical inundation) — this
is what makes offline mode *reason* rather than just replay a cache. `T_c` is per hazard
class: flash flooding decays in tens of minutes, a fallen tree in days.

**Pessimistic plug-in — the single most important design decision:**

```
p̃(e,t) = min{1, p̄ + z·√(p̄(1−p̄)/(n_eff+1))}
```

The original pitch used `w = τ·(1 + λ·R·C)`, where low confidence drives the penalty toward
**zero** — an unverified flood report would make the router treat the road as clear. That is
risk-seeking under ambiguity and is indefensible for an ambulance. Here, *less evidence
means more caution*. `z` is set per user class (`z≈0` commuter, `z≈2` ambulance) and is a
clean product dial that is also directly explainable to the user.

**Edge cost — slowdown and harm are physically distinct and stay separate:**

```
w_λ(e,t) = τ₀·[1 + p̃·(δ−1)]  +  λ·p̃·s·τ₀        subject to   Pr[depth > h_max] ≤ ε
```

`δ` is the depth–disruption slowdown from Pregnolato et al. (2017) — real measured physics,
not an invented multiplier. The chance constraint removes edges outright rather than
assigning a large finite weight. Everything is in seconds, so `λ` stays interpretable and
the explanation layer can talk about it in plain language.

**A result worth writing up:** since `δ ≥ 1`, `p̃ ≥ 0`, `λ ≥ 0`, the hazard cost is always
`≥ τ_free`. Therefore **ALT landmark potentials computed once on the free-flow metric remain
admissible under every possible hazard configuration** — preprocessing never needs to be
re-run when hazards change. This does not appear stated in the hazard-routing literature.
Verify it carefully before claiming it.

---

## 7. Conventions

- **Python** 3.11+, FastAPI, `ruff` + `black`, type hints everywhere, `pytest`.
- **Dart/Flutter** stable channel, `dart format`, `very_good_analysis` lints.
- **Commits**: conventional commits (`feat:`, `fix:`, `exp:`, `paper:`). Prefix
  experiment-affecting changes with `exp:` so results stay traceable.
- **Every experiment is a script in `scripts/` with a pinned seed**, writing results to
  `data/results/<date>-<experiment>/`. No result goes in the paper unless a script
  reproduces it.
- **Data snapshots are pinned by date and never silently updated.** An OSM extract change
  mid-evaluation invalidates every prior number.
- **Secrets in `.env`, never committed.** `.env.example` lists required keys.
- **Citations**: when you add a claim to any document, cite from `research/raw/*.md` and
  carry the URL. **Open every citation before it enters the paper** — the research reports
  were produced by agents and only five load-bearing citations have been human-verified
  (see `research/SYNTHESIS.md` §9). One citation there is already flagged as unverifiable.
  Do not invent references; mark anything you cannot confirm `[UNVERIFIED]` rather than
  quietly dropping it.

---

## 8. How to work on this repo

1. **Before implementing anything, check `docs/DECISIONS.md`.** Most of the obvious
   questions are already answered there with reasoning.
2. **Prefer the boring, smallest thing that produces evidence.** This project is measured by
   whether five studies produce clean numbers, not by architectural elegance. Chennai is
   ~10⁵ nodes — do not build contraction hierarchies, do not build a microservice mesh.
3. **When the pitch deck and the research reports disagree, the research reports win.**
   The deck contains several claims that were disproved (see §7 of `research/SYNTHESIS.md`).
4. **Flag, do not silently fix, a claim that turns out to be false.** If a benchmark kills an
   assumption, say so loudly and write it into `docs/DECISIONS.md`. The paper's credibility
   comes from reporting what actually happened.
5. **Do not write files into the user's local project directories.** Deliver work in-repo
   here and report results in chat.

---

## 9. Honest novelty position — background for eventual evaluation, not a build gate

**This section is reference material for whenever this project is formally evaluated or
pitched — it does not gate day-to-day implementation decisions** (reframed 2026-09-17, see the
top of this file). Don't let novelty-defensibility block or slow down building a feature; do
keep this honest framing in mind whenever the project is actually written up or presented.

Three of the four originally claimed novelties do not survive prior-art search:

- **Dynamic hazard-aware routing** — IBM filed a flood-aware routing patent in 2011; Uber
  holds US10563994B2 on time-sliced per-segment risk; TomTom ships hazard categories at ~30 s
  latency in 80+ countries. **Not novel.**
- **Confidence decay** — Waze already expires reports on an engagement-driven TTL; temporal
  decay in trust models dates to 2002. **Not novel as a mechanism.**
- **"Haven Mode" predictive personal precaution** — TN-ALERT (Tamil Nadu government / RIMES,
  500k+ installs) already pushes flood risk alerts for five saved locations, in Tamil.
  **Not novel, and the passive-inference part adds DPDP exposure for little gain.** Rescoped.
- **Offline on-device explanation** — the closest patent (US6577950B2, expired) retrieves
  *pre-authored* landmark text, not generated rationale. **This is the white space.**

What we can honestly claim: the *integration* is unpublished, and four narrow contributions
are defensible — (1) generated-and-verified explanation on-device with faithfulness measured
rather than asserted, (2) hazard-class-specific decay *calibrated against real Chennai
closure data* with reliability diagrams, (3) pessimism-under-uncertainty routing with a
per-user-class `z`, (4) the ALT-admissibility result above. That is a workshop paper
(SIGSPATIAL ARIC, ISCRAM) or an applications track — not a methods venue. Aim there and land
it, rather than aiming high and getting desk-rejected.

**The headline metric of the paper is the explanation verification pass rate and the
confidence calibration curve — not "we ran a quantized model on a phone."**
