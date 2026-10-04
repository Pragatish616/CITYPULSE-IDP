# CityPulse AI — Research Synthesis

Merged findings from seven parallel deep-research strands (~440 KB of reports, ~250 verified
sources) run 2026-09-11/12. Each section cites the strand report that holds the detail and
the citations.

| Strand | Report | Scope |
|---|---|---|
| A | `raw/A-routing-algorithms.md` | Hazard-aware routing algorithms, cost functions, engines (33 sources) |
| B | `raw/B-edge-llm.md` | On-device LLM feasibility, quantization, runtimes, NLG alternatives (37 sources) |
| C | `raw/C-data-sources.md` | Hazard/mobility data for Chennai, licensing, DPDP (60+ sources) |
| D | `raw/D-confidence-xai.md` | Confidence decay, trust, calibration, explainability (50 sources) |
| E | `raw/E-prior-art-evaluation.md` | Prior art, patents, competitors, evaluation methodology (84 sources) |
| F | `raw/F-offline-architecture.md` | Offline-first systems engineering, sync, storage (39 sources) |
| G | `raw/G-free-apis-infra.md` | Free-tier APIs and infrastructure (86 sources) |

---

## 1. The headline finding

**The routing is not the contribution, and neither is running a model on a phone.**

Hazard-aware A* is published (Liang et al., *Scientific Reports* 2025). The exact
multiplicative cost form in the original pitch appears verbatim in Xue et al.
(arXiv:2601.13632). IBM filed a flood-aware routing patent in 2011; Uber holds
US10563994B2 (granted 2020, live to 2036) on time-sliced per-segment risk scores looked up at
predicted traversal time; TomTom ships nine hazard categories at ~30 s latency across 80+
countries from 600 M devices. Temporal decay of trust dates to Jøsang & Ismail (2002), and
Waze already expires reports on an engagement-driven TTL.

What is *not* in the literature or the patent record is **a route, a confidence state, and a
generated-and-verified natural-language rationale, all produced on-device with no network**,
with explanation faithfulness *measured* rather than asserted. The closest patent
(US6577950B2, expired) retrieves pre-authored landmark text, not generated rationale.

This is a **systems-integration gap, not a methods gap**. That sets the venue (workshop or
applications track) and it sets the paper's spine: the contribution is the *measurement*.

---

## 2. Where the pitch was wrong — corrections adopted

| Pitch claim | Verdict | Correction |
|---|---|---|
| `w = τ·(1 + λ·R·C)` | **Wrong sign** | Low confidence drove the penalty to zero — an unverified flood report would make the router treat the road as clear. Replaced with a pessimistic UCB plug-in (ADR-002). |
| A single confidence-decay rate | **Backwards example** | Urban flooding persists for *hours*; debris clears in minutes. The deck's worked example inverts this. Decay must be per hazard class or EMS gets routed into standing water. |
| "OSRM or GraphHopper" | **Neither is viable** | OSRM has no per-request cost model (~20 min re-customization cadence); GraphHopper's Android offline support is unmaintained. We own the router (ADR-001). |
| On-device model generates "route geometry AND explanations" | **Indefensible** | An LLM must not produce geometry. Graph search does. Reviewers will attack this sentence. |
| "Fallback the millisecond a connection drop is detected" | **Not implementable** | No such signal exists for captive portals, stalled cellular or slow servers. Reframed as offline-first — a stronger claim (ADR-005). |
| "Redis for decay calculations" | **Incomplete** | Redis cannot expire individual geo-set members; needs a parallel ZSET sweeper. |
| Haven Mode passive inference | **Not novel + high risk** | TN-ALERT already does saved-location flood alerts for Tamil Nadu. Rescoped to explicit saved places (ADR-006). |
| "Encrypted" routing-usage learning | **Wrong property** | Encryption is not the privacy claim. Say "on-device, never transmitted." |
| Google Flood Hub = "historical data" | **Factually wrong** | It covers 150+ countries with 7-day lead time, has an API, and covers all of India. |
| Waycare | **Out of date** | Acquired by Rekor in 2021. |
| Competitor table | **Incomplete** | Omits TomTom and TN-ALERT, the two most relevant incumbents. |

---

## 3. The model we will build (strands A + D, in agreement)

Strands A and D converged independently on the same structure, which is a good sign.

**Belief.** Log-odds fusion of timestamped, source-weighted, spatially-kernelled reports over
a **static terrain prior** `ℓ₀(e)` (elevation, HAND, drainage, historical inundation), with
per-hazard-class exponential decay `exp(−(t−tᵢ)/T_c)`. The prior is what makes offline mode
*reason* about an unreported road rather than merely replay a cache.

**Pessimism.** Route on `p̃ = min{1, p̄ + z·√(p̄(1−p̄)/(n_eff+1))}`. Thinner evidence ⇒ more
caution. `z` is per user class (commuter ≈ 0, ambulance ≈ 2) and is directly explainable.
**The clamp is load-bearing** — see `docs/DECISIONS.md` ADR-002 (verified 2026-09-12).

**Cost.** `w_λ = τ₀·[1 + p̃·(δ−1)] + λ·p̃·s·τ₀`, `δ` from Pregnolato et al. (2017)'s measured
depth–disruption function, plus a hard chance constraint implemented as edge removal.

**Stretch (D).** Replace the exponential with a Bayesian persistence filter (Rosen et al.,
ICRA 2016) under a **Weibull** survival prior fitted per hazard class by interval-censored
survival regression on covariates (rainfall, road class, elevation, hour, season), with
**traversal-silence** as calibrated evidence of absence. Surface it as a Subjective Logic
triple (b, d, u) so "stale" renders differently from "refuted". The pitched exponential is the
exact observation-free marginal of this model, so the offline fallback becomes a derivation
rather than a hack — the project's best rhetorical asset if week 5 has room.

**A theoretical result worth verifying and writing up (A).** Since `δ ≥ 1`, `p̃ ≥ 0`, `λ ≥ 0`,
the hazard cost is always `≥ τ_free`. Therefore ALT landmark potentials computed once on the
free-flow metric **remain admissible under every hazard configuration** — preprocessing never
needs re-running as hazards change. This inverts the usual "A* loses admissibility under
dynamic weights" caution and does not appear stated in the *hazard-routing* literature.

**Verified 2026-09-12 (review pass) — two corrections before this goes near the paper.**
(1) The graph-theoretic core is not just valid but understated: the same argument gives
**consistency**, not merely admissibility (`π(u) − π(v) ≤ w_freeflow(u,v) ≤ w_hazard(u,v)` for
every edge), which is the stronger, more useful guarantee — state it as consistency in §5 of
the paper. (2) **`δ ≥ 1` is an assumption, not a derived fact**, and is false on an ordinary
Chennai arterial unless enforced in code — see `docs/DECISIONS.md` ADR-003's new invariant.
Do not write "the hazard cost is always ≥ free-flow" as if it falls out of the physics; it
falls out of a clamp the implementation must apply. (3) **Keep the novelty claim narrow.**
To anyone familiar with Customizable Route Planning / Contraction Hierarchies (Delling et al.
— already cited in `research/raw/A` §2.3), this is a straightforward instance of the general
"preprocessing on a provable lower-bound metric survives any weight increase that stays above
it" principle. The claim "does not appear stated **for hazard routing specifically**" is
defensible; a claim of general shortest-path novelty is not, and a reviewer who knows that
literature will say so.

**What is *not* a contribution (D is blunt about this):** "learning λ from data" is a 25-year-old
transfer, not a novelty. Drop the Age-of-Information framing entirely — there is no scheduling
problem here and reviewers will notice.

---

## 4. The explanation layer (strand B)

Every content word in *"Route A is 4 minutes slower; it avoids a flooded underpass reported 3
minutes ago"* is already a field in the router's output. This is surface realisation over a
closed domain — exactly where the template-vs-"real"-NLG opposition is known to be false.

On a mid-range Android the SLM needs **~5.5 s** (≈90–120 tok/s prefill, ≈12–15 tok/s decode)
and 0.5–1.7 GB to produce what a Dart function produces in **under 1 ms**, free, with perfect
fidelity. Small models hallucinate **5.7–7.4%** even on grounded summarisation (Vectara HHEM),
and quantization adds up to **4.4%** explanation-quality loss that LLM-as-judge fails to
detect.

**So: template is the product, the SLM is the experiment.** Tier 0 deterministic template
always runs and is always the fallback; Tier 1 is a constrained *rewriter* that must pass a
symbolic verifier (every numeral and entity present in the fact set) or be discarded
silently. **The verification pass rate is the paper's headline number.**

Recommended: Gemma 3 270M IT, INT4-QAT, LoRA-tuned, via LiteRT-LM through `flutter_gemma`
(~250 MB resident, survives Android backgrounding; ~0.75% battery per 25 generations, versus
~7% per 20 generations for 2B-class models). Avoid MediaPipe (maintenance-only), MLC-LLM
(1.1–1.8 tok/s decode, 4.2 GB), ExecuTorch and NPU delegation.

---

## 5. What data actually exists (strand C)

**Obtainable today, zero auth:** Geofabrik OSM extract · OpenCity GCC flood hazard zones,
return-period flows and inundation depth points · OpenCity Chennai 2015 stagnation corpus ·
Open-Meteo forecast + flood APIs · GDACS RSS at 6-minute cadence · OpenAQ v3.

**Week 1–2:** TomTom traffic (2 500 incident calls/month free) · CMWSSB reservoir levels via a
30-line scraper — small effort, enormous explanatory payoff for the LLM layer ("Chembarambakkam
at 94%, Adyar corridor above the 25-year return period") · TN-SMART XHR endpoints · IMERG.

**Apply and assume failure:** IMD whitelisting (~40%) · NDMA SACHET (~60%) · Google Flood
Forecasting waitlist (~10%) · IIT Madras Chennai Water Logging dataset (~35%).

**The limitation that must be stated everywhere:** no obtainable source gives live
street-level inundation depth for Chennai. Every live flood signal is ≥5 km grid or a static
prior. Overclaiming here is the most likely thing to sink the project at review.

**Legal:** Google Maps Platform is excluded outright — its terms forbid use in a competing
navigation product and forbid the caching our offline mode requires, and mixing it with OSM
risks ODbL contamination. DPDP Act 2023 + 2025 Rules govern anything location-derived.

---

## 6. Infrastructure (strand G)

A complete ₹0 stack exists: Oracle Cloud Always Free (2 OCPU / 12 GB) for the backend,
Protomaps PMTiles on Cloudflare R2 for tiles, Supabase Free + PostGIS, Upstash Redis, Groq
for the cloud LLM path, FCM for push, GitHub Actions free on a public repo. Details and the
trap list are in `docs/APIS_AND_COSTS.md`.

**One finding belongs in the paper, not just the budget:** a 1 000-user pilot costs
≈ ₹10 700/month, of which **≈78% is the cloud LLM API cost, and output tokens alone are
roughly half the total** (corrected 2026-09-12 — the derivation in `research/raw/G` §12 gives
$88.65 of $113.65 total as the LLM line, not the ">90% output tokens" this section previously
claimed; the arithmetic didn't support that figure). One line item still dominating at 78% is
still the whole argument. The on-device model is what makes civic-scale deployment affordable
— that turns the offline component from a robustness feature into an *affordability*
argument — a considerably stronger claim for an ICT4D or COMPASS audience.

---

## 7. Honest novelty position

**Dead on arrival:** dynamic hazard-aware routing (IBM 2011, Uber US10563994B2, TomTom
shipping) · confidence decay as a mechanism (Jøsang & Ismail 2002; Waze TTL) · Haven Mode
(TN-ALERT, 500 k+ installs, already alerts on five saved locations in Tamil).

**Defensible, narrowly:**
1. Generated-and-verified explanation produced **on-device with no network**, grounded in a
   structured decision trace, with **faithfulness measured** rather than asserted.
2. Hazard-class-specific decay **calibrated against real Chennai closure data**, reported as
   reliability diagrams stratified by report age and hazard class — calibration as a reported
   target, not a hand-tuned constant.
3. Pessimism-under-uncertainty routing with a per-user-class `z`, and the argument that the
   common multiplicative form is risk-seeking under ambiguity.
4. The ALT-admissibility result (§3), if it holds up.
5. The traversal-silence channel (D) — absence of reports as calibrated evidence of absence.

**Venue ladder:** SIGSPATIAL ARIC or GeoAI workshop / ISCRAM first → IEEE ITSC or SIGSPATIAL
**Applications** track (not the research track) → IJDRR. Aim there and land it.

---

## 8. The five things that could still kill this project

1. **The SLM is unusable on a cheap phone.** 5–9 s time-to-first-token mid-drive is not a
   product. *Mitigation: benchmark on a ₹10–15k Android in week 1, not week 5.* The team will
   be tempted to benchmark on a flagship — that invalidates the core claim.
2. **Benchmarking on the wrong hardware, and not noticing.**
3. **No live hazard feed materialises.** Mitigation is already designed: a replay corpus from
   the 2015 Chennai stagnation data and OpenCity inundation records, with a deterministic
   replay harness. The evaluation is designed to survive having no live feed at all.
4. **Ethics approval arrives too late for the human study.** Start the IEC application in
   week 1.
5. **The team writes up the demo instead of the measurements.** The router working is not a
   result. The calibration curve and the verification pass rate are the results.

---

## 9. Citation verification status

Five load-bearing citations were independently spot-checked on 2026-09-12 against primary
sources:

| Claim | Status |
|---|---|
| Uber **US10563994B2** "Safe routing for navigation systems" — segment-level safety scores per 30-min interval, shortest-path over them | **Verified.** Filed 2019-02-11, granted 2020-02-18, assignee Uber Technologies. (Strand E said "live to 2036"; term runs ~20 yrs from the 2019 filing — the exact expiry should be re-checked before it goes in the paper.) |
| IBM **US20130116920A1** "System, method and program product for flood aware travel routing" | **Verified.** Filed 2011-11-07, published 2013-05-09, **abandoned 2018** (no response to office action). Abandoned ≠ not prior art. |
| **Pregnolato et al. (2017)** depth–disruption function | **Verified.** *Transportation Research Part D*, 55, 67–81. |
| **TN-ALERT** (Tamil Nadu govt / RIMES) | **Verified.** Live on Google Play (`int_.rimes.tnsmart`) and the App Store; TN-SMART portal at beta-tnsmart.rimes.int. |
| **Xue et al., arXiv:2601.13632** — cited by strand A as containing our multiplicative cost form verbatim | **NOT VERIFIED.** The fetch returned content about a "Risk-Aware Dynamic Routing (RADR)" framework but no confirmable title or author list. **Do not cite this until a human confirms it exists.** The "routing is not novel" verdict does not depend on it — the IBM and Uber patents, TomTom's shipped product and Liang et al. (2025) carry that conclusion independently. |

The remaining ~250 citations across `raw/` were gathered by research agents and are **not
individually verified**. Before any citation enters the paper, open it and confirm it says
what the report claims. Treat the reports as a well-sourced starting point, not as a
bibliography.

### Addendum, 2026-09-12 review pass — leads found for three previously-unsourced claims

The 2026-09-12 review found that the Michaung replay corpus, the CMWSSB scraper's feasibility,
and the basin/corridor escalation mechanism all had **zero backing citations anywhere in
`research/raw/`** despite being load-bearing for the demo, the spec's data model, and Study 1's
real-event corpus. A live web search (by the reviewing agent, not a research strand — **treat
every item below as an unopened lead, not a verified citation**, per this file's own rule) found:

- **Michaung corridor closures, 4 Dec 2023.** Independent, mutually corroborating news
  coverage (Citizen Matters, Adyar Times, Deccan Herald, a Medium explainer) names specific
  mechanisms matching the spec's own candidate seed list: the Pallikaranai 200 ft radial road
  flooded from Narayanapuram Lake's overflow; Mudichur/Varadharajapuram/Old
  Perungalathur/Bharathy Nagar had ~7 ft of water from Perungalathur, Mudichur and Mannivakkam
  Lakes overflowing; Velachery/Taramani/Perungudi/Madipakkam were heavily waterlogged;
  Besant Nagar/Sastri Nagar/Thiruvanmiyur were badly hit while Adyar/Kotturpuram proper were
  not. The Chembarambakkam-release-floods-Adyar causal chain the spec's demo script is built
  around is independently confirmed to have actually happened that day (reservoirs released
  water pre-emptively; the release flooded the Adyar). **This is a real, findable dataset, not
  an invented scenario — but every one of these sources is a news article, not a GCC advisory
  record with a timestamp precise enough for a 07:00 test. Someone must still find or request
  the official closure record (or accept press timestamps with a stated margin of error) before
  Study 1 treats this as ground truth.**
- **CMWSSB reservoir levels.** The official page is real and specific:
  `cmwssb.tn.gov.in/lake-level`. The reviewing agent's own fetch of it was also blocked
  (`ECONNRESET`) — the same failure `research/raw/C` reported from its environment. This is now
  failed from two independent environments, which raises rather than lowers the prior that it
  is geo-blocked or bot-blocked rather than simply unlucky. **Someone on the team must try this
  from a normal Indian residential/mobile connection in week 1** before "30-line scraper" is
  treated as a planning fact rather than a hope.
- **Chennai's basins are real, named, and roughly bounded** — Kosasthalaiyar (127.8 km²,
  covering GCC zones 1/2/3/7 fully and 6/8 partially), Adyar (860 km² catchment), Cooum, and
  Kovalam are the four major basins per Anna University's Centre for Climate Change and
  Disaster Management and corroborating academic sources (Wikipedia's Adyar/Cooum/Kosasthalaiyar
  River pages summarize the same boundaries). This is enough to assign each watchlist point a
  basin *label* by which of the three rivers or the coastal strip it drains toward — it is
  **not** enough, on its own, to justify the spec's specific "one reservoir signal escalates
  fourteen points" mechanism, which still needs an actual reservoir-to-corridor-to-point
  computation nobody has done. Treat the basin *labels* as sourced; treat the *escalation
  count* as still to be computed, not assumed.

None of the above is a substitute for someone on the team opening these sources directly
before they enter the paper, per this file's own rule above.
