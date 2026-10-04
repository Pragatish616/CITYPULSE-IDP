# CityPulse Chennai v0 — Prototype Spec

**What we build first, and what we pitch.** This supersedes the pitch deck's scope. Anything
not named here is out of v0, including things the deck promised.

Codename for the scope: **The Watchlist.**

---

## 1. The reframe this whole spec rests on

The deck implies we know the flood state of every road in Chennai. We do not, cannot, and
cannot buy it — no source provides live street-level inundation (`research/raw/C`). Building
toward that is how this project dies.

But Chennai does not flood uniformly. It floods in the **same places, in roughly the same
order, every year** — the Velachery–Pallikaranai belt, the Adyar corridor, the Mudichur and
West Tambaram stretch, and a known set of rail subways that close whenever rainfall passes a
threshold. The Corporation and the city traffic police already work from lists of these.

So v0 does not attempt city-wide sensing. It maintains a **bounded watchlist of chronic
waterlogging points** and knows, for each one, the current risk and how confident it is.

This changes the problem from unbounded and impossible to bounded and tractable:

| | City-wide sensing | Watchlist (v0) |
|---|---|---|
| Points to know | ~10⁵ edges | ~150–200 points |
| Reporters needed for coverage | tens of thousands | tens |
| Cold start on flood day | fatal | survivable |
| Can a static prior carry it? | no | yes, partially |
| Demonstrable in 7 weeks | no | yes |

**Two hundred points is small enough that a handful of committed reporters covers it.** That
is the answer to the cold-start objection in `docs/COUNCIL_VERDICT.md`.

---

## 2. The signal that makes the demo, and the pitch

Chennai's most consequential flooding is **predictable hours ahead from free public data**,
through one causal chain that every resident already understands:

```
sustained rainfall  →  reservoir fills  →  surplus release  →  river rises  →  known corridor floods
   (Open-Meteo)        (CMWSSB levels)      (announced)        (Adyar/Cooum)     (watchlist points)
```

Chembarambakkam's release into the Adyar is the 2015 story, and the causal path is public
knowledge in the city — and it demonstrably happened again during Michaung (4 Dec 2023):
reservoirs released water pre-emptively and the release flooded the Adyar corridor, per press
coverage gathered in `research/SYNTHESIS.md` §9's addendum. Both inputs are free and
unauthenticated: Open-Meteo needs no key. CMWSSB lake levels are published at
`cmwssb.tn.gov.in/lake-level` — a real, specific, official page — **but treat "a ~30-line
scraper" as a hope, not a fact, until someone on the team reaches this page from an Indian
connection: it has failed to load from two independent non-India environments so far (see T0.5,
`docs/IMPLEMENTATION_PLAN.md`, added 2026-09-12).**

**This is the thing no competitor tells you.** Google Maps will never say "Chembarambakkam is
at 94% and rising, release is likely within 12 hours, and these 14 points on the Adyar corridor
go high-risk tonight." It is predictive, explainable, locally legible, and built from data
anyone could have used and nobody did.

**Lead the pitch with this, not with the AI.**

---

## 3. Scope

### In v0
1. **The watchlist** — 150–200 chronic waterlogging points, each resolved to specific OSM edges,
   each with a static prior, a hazard class and a severity.
2. **Risk state per point**, fused from five inputs:
   - static prior from GCC/OpenCity hazard zones + 2015 inundation depth points
   - live and forecast rainfall (Open-Meteo, no key)
   - reservoir levels and the release-risk chain (CMWSSB scraper)
   - citizen reports (in-app, positive and negative)
   - traversal silence — a user driving through a watchlist point without reporting is
     evidence of absence (improvement I-02)
3. **Hazard-aware routing** over the Chennai graph, avoiding high-risk watchlist edges under
   the pessimistic cost function (ADR-002, ADR-003).
4. **Explanations** from the decision trace, Tier 0 template shipped, verifier enforced.
5. **Full offline operation** — graph, tiles, watchlist, priors and last-known state all cached.
6. **Android only.**

### Out of v0 (say so on the slide, do not let it be discovered)
Haven Mode (ADR-006) · Tamil UI — v1, see I-06 · the on-device SLM in the interactive path
(benchmarked and reported, not shipped as the primary generator — ADR-004) · turn-by-turn voice
navigation · iOS · any city but Chennai · live street-level depth for arbitrary roads.

---

## 4. Building the watchlist (T-W1, the new first data task)

**Do not seed this from memory or from a chatbot.** Build it from sources, in this order:

1. **OpenCity / GCC flood hazard zones + inundation depth points** — the primary source, public
   domain, Chennai-specific (`research/raw/C`, C12/C13).
2. **The 2015 stagnation corpus** — points that actually stood in water.
3. **Rail and road subways** — these close on a rainfall threshold and are individually named
   in traffic advisories, which makes them the easiest points to validate and the most
   legible in an explanation.
4. **Cross-check against recent monsoons** (Michaung, Dec 2023) using news archives and any
   GCC advisory lists you can obtain — a point that appears in 2015 *and* 2023 is a high-confidence
   watchlist entry.

**Candidate seed areas for validation only — verify every one against the data above before it
enters the watchlist:** Velachery, Pallikaranai, Madipakkam, Perungudi, Taramani, Mudichur,
West Tambaram, Chromepet, Kotturpuram, Saidapet, Nandanam, Ashok Nagar/K.K. Nagar pockets,
T. Nagar, Pulianthope/Vyasarpadi, Ambattur, OMR and ECR low points. Treat this list as a
starting hypothesis with no evidentiary weight of its own.

**Refined against real Michaung (4 Dec 2023) reporting (added 2026-09-12, review pass —
still press-sourced, not GCC-advisory-sourced; see `research/SYNTHESIS.md` §9 addendum).** News
coverage from that day names specific mechanisms, not just neighbourhood names, which makes
better watchlist points than the area names alone:
- **Pallikaranai — the 200 ft radial road from Echankadu signal**, flooded by Narayanapuram
  Lake's overflow. A named road segment, not just a neighbourhood — resolve this to a specific
  OSM edge first.
- **Mudichur corridor — Varadharajapuram, Old Perungalathur, Bharathy Nagar**, ~7 ft of water
  from Perungalathur, Mudichur and Mannivakkam Lakes overflowing together. Three lakes
  overflowing into one corridor is exactly the "basin escalation" mechanism §4 below needs a
  real example of.
- **Velachery / Taramani / Perungudi / Madipakkam** — heavily waterlogged, consistent with the
  original hypothesis list.
- **Besant Nagar / Sastri Nagar / Thiruvanmiyur** — badly hit; note Adyar/Kotturpuram proper
  were *not* reported as badly hit the same day, which is useful negative signal for point
  selection (don't add a point just because it's in the Adyar corridor by name).

These are still secondary press sources, not the GCC/OpenCity primary data §4 requires as the
actual watchlist source — use them to prioritise which OpenCity/GCC points to check first, not
as a substitute for checking them.

### Basin definitions (added 2026-09-12, review pass)

The `basin` field ADR-009 calls "the data model's most important edge" had no source anywhere
in the research as of the last review. Chennai has four named, roughly-bounded basins:
**Kosasthalaiyar** (127.8 km², covering GCC administrative zones 1/2/3/7 fully and 6/8
partially, originates near Pallipattu in Thiruvallur district, empties via Ennore Creek),
**Adyar** (860 km² catchment, originates at Adhanur Lake in Kanchipuram district, collects
surplus from ~200 tanks and lakes plus city stormwater drains), **Cooum** (runs between the
Kosasthalaiyar and Adyar, trifurcating the city), and **Kovalam** (the fourth, southern basin).
Assigning each watchlist point one of these four labels is now sourceable. **What is still
missing:** an actual reservoir-to-corridor computation — i.e., which specific watchlist points
sit downstream of Chembarambakkam specifically, versus Poondi or Redhills — has not been done
by anyone, human or agent. Do not repeat "fourteen points" or any other specific escalation
count in the pitch or paper until this computation exists; say "an upstream basin's reservoir
level escalates its downstream points" without a specific number until T-W1 produces one.

**Schema** — extend `HazardObservation` with a `watchlist_point_id`. Each point carries:
stable id, name as a resident would say it, OSM edge ids, hazard class, static prior log-odds,
the corridor/basin it belongs to (Adyar / Cooum / Kosasthalaiyar / coastal / local drainage —
see the Basin definitions below), and its upstream reservoir if any. **The basin link is what
lets one reservoir signal escalate a whole corridor of points at once** — it is the data
model's most important edge. **The specific count of points per corridor has not been computed
yet** (2026-09-12 review) — do not state a number until T-W1 actually produces one.

**Acceptance:** a map of the watchlist that a Chennai resident looks at and says "yes, those are
the places." That review is a real acceptance test — book it with someone who drives the city.

---

## 5. Data stack for exactly this scope

Everything free, no card, per `docs/APIS_AND_COSTS.md`:

| Input | Source | Cadence | Auth |
|---|---|---|---|
| Road graph | Geofabrik TN extract, pinned | one-off | none |
| Static prior | OpenCity GCC hazard zones + 2015 inundation | one-off | none |
| Rainfall now + forecast | Open-Meteo | hourly | **none** |
| Reservoir levels | CMWSSB scraper | ~4×/day | none |
| Regional flood | Open-Meteo Flood (GloFAS) | daily | none |
| Alert heartbeat | GDACS RSS | 6 min | none |
| Traffic incidents | TomTom free tier | on demand | self-serve key |
| Air quality | OpenAQ v3 | hourly | free key |
| Citizen + traversal | our own app | live | — |

Nothing here requires an application, a letter, or a wait. Tier 2 sources (IMD, SACHET,
IIT-M dataset) remain applied-for and are a bonus, never a dependency.

---

## 6. The prototype demo — three minutes, in this order

**0:00 — Aeroplane mode.** Hold up the phone. "This has no network." Route across the Adyar
corridor. Route appears, explanation appears, confidence badge appears. Say nothing else for
five seconds and let it land.

**0:45 — The watchlist.** Show the map: points in confidence bands, and at least one corridor
rendered explicitly as *no data* rather than as safe. "We don't claim to know the whole city.
We claim to know these, and to tell you when we don't."

**1:15 — Reconnect, and predict.** Network back on. Reservoir level and rainfall update, and
the Adyar-basin points escalate together. "Chembarambakkam is at 94%. If they release tonight,
these points go first — that's not a model, it's the drainage." **State the actual N once
T-W1 computes it (2026-09-12 review) — do not say "fourteen" or any other number that hasn't
been derived from the real basin-to-point mapping.**

**2:00 — Replay Michaung.** 4 December 2023, 07:00. Show what CityPulse would have displayed
using only data available at 7am that morning, beside what a mapping app showed. This is the
10-minute test from the council verdict, promoted to the centre of the pitch — and if the
answer turns out to be weak, you learn it in week 1 rather than on stage.

**2:40 — The economics.** ₹10,700/month for 1,000 users on cloud inference, most of it tokens.
On-device is what makes a civic layer for ten million people affordable. Close there.

**Do not demo:** the LLM writing prose, Haven Mode, or anything requiring connectivity to look
impressive.

---

## 7. Prototype success criteria

Measurable, and these are what go on the results slide:

1. **Offline route** on a ₹10–15k Android across the Chennai graph, p95 under 500 ms end to end,
   with no network. Device and chipset named.
2. **Watchlist coverage** — N points with validated geometry and a resident sign-off; state the
   real N, do not round it up.
3. **Michaung replay** — of the corridors that actually closed on 4 Dec 2023, how many did the
   system flag at 07:00 using only 07:00-available data? Report the misses too. **A mediocre
   honest number here beats a good unexplained one.**
4. **Verification pass rate** — proportion of generated explanations passing the symbolic
   verifier, reported per tier.
5. **Calibration** — a reliability diagram for watchlist-point risk against observed closures,
   stratified by report age.

Criteria 3 and 5 are the paper. Criterion 1 is the demo. Do not let 1 eat the time for 3 and 5.

---

## 8. Build order for v0

Replaces the general plan for the prototype window; full detail in `docs/IMPLEMENTATION_PLAN.md`.

| Week | Deliverable |
|---|---|
| 1 | **Four** de-risking spikes (T0.1–T0.3 **plus T0.5, watchlist feasibility — added 2026-09-12 review**) plus the Michaung 7am test, done by hand |
| 2 | Watchlist built and validated (T-W1, now scoped as its own task card — see `docs/IMPLEMENTATION_PLAN.md`) · graph · static prior · belief model |
| 3 | Router + decision trace · Michaung replay as an automated study |
| 4 | Template explanations + verifier · reservoir/rainfall ingest and the basin escalation rule |
| 5 | Android client: offline map, watchlist layer, confidence and no-data states |
| 6 | Live ingest, sync, SLM benchmark, human study, demo rehearsal in aeroplane mode |
| 7 | Write-up |

---

## 9. What this costs us, stated honestly

Specialising to Chennai weakens the "designed for every city" claim, and that claim should be
dropped rather than defended. The honest version — **the method ports where equivalent open
data exists; the system is built for Chennai** — is both true and more credible from a
three-person team. A judge who lives in the city will trust specificity over scope every time.

The watchlist framing also concedes something the deck never did: there are roads we know
nothing about. Saying that out loud, on a slide, is the single most credible thing in the
entire pitch.
