# Roast Council — Shared Note

Append, never overwrite. Each session adds a dated entry so the council continues rather than
restarting.

---

## 2026-09-12 — CityPulse AI

**Idea as pitched.** Hazard-aware urban routing for Chennai: ingest live hazard signals, decay
confidence by signal age, route around hazards, explain each decision in natural language, and
keep working entirely offline via an on-device quantized model. Plus "Haven Mode" — predictive
personal precaution from passively learned locations.

Council run with the seven research strands in `research/raw/` as evidence.

---

### THE BELIEVER

**Who desperately needs this.** A two-wheeler commuter in Velachery at 7am on a monsoon
morning, deciding whether the underpass is passable. Today they check a neighbourhood WhatsApp
group, search X for the area name, call someone who lives there, or drive until they see water
and turn around. None of those carry a timestamp, and all of them fail for the road nobody
happened to post about. The second user is an ambulance driver on Google Maps, which has no
flood layer at all — routing on local knowledge and radio, where one wrong detour is measured
in a life.

**Why now.** Three things changed inside eighteen months. Instruction-tuned models small enough
to matter on a ₹12,000 phone now exist — Gemma 3 270M is 253 MB at roughly 0.75% battery per
25 generations, which was simply not available before. Chennai's OSM road graph is now complete
enough to route on. And GCC/OpenCity published actual flood hazard zones, return-period flows
and 2015 inundation depth points as open data — which is the only reason a meaningful static
prior can be built at all. Demand changed too: Chennai flooding is now an annual event
(2015, 2021, Michaung 2023), not a once-a-decade one.

**The best version.** Not a consumer app — a **civic passability layer**. The thing that makes
"is this road passable right now" a queryable fact for Chennai, maintained by the people
driving on it, consumed by other apps and by the city itself. The app is the sensor; the API is
the product. PetaBencana in Jakarta is the precedent: a crowd-sourced flood map that became
official government infrastructure.

**The unfair advantage.** The offline path is not a feature, it is an economic moat. A
1,000-user pilot costs ≈₹10,700/month, >90% of it LLM output tokens. On-device inference is
what makes civic scale affordable, and a funded competitor optimising revenue-per-user will
never build the version that works free, offline, on a cheap phone — for exactly the user who
needs it most. Second advantage: nobody can *buy* street-level Chennai inundation data. It has
to be collected. Being three people in Chennai during the monsoon is a real edge over Google.

> **[Correction appended 2026-09-12, review pass — the session's own words above are kept
> unedited per this file's "append, never overwrite" rule.]** The Believer's ">90% LLM output
> tokens" figure does not match the arithmetic in its own source (`research/raw/G` §12): the
> real breakdown is ≈78% total LLM API cost, of which output tokens are roughly half. The
> underlying argument (one line item dominates the pilot cost, on-device inference is what
> makes it affordable) still holds at 78% — only the specific number was wrong, and it has
> since propagated, now corrected, into `research/SYNTHESIS.md` §6, `docs/APIS_AND_COSTS.md`
> §4, and `paper/OUTLINE.md` §8.

**The one bet.** That hyperlocal passability can be inferred from a sparse crowd plus a good
static prior well enough to beat "use Google Maps and your own judgement" — and that people
will contribute the observations that make it work.

---

### THE SKEPTIC

**Who will not pay.** Citizens, absolutely not. Zero willingness to pay for a safety app used
five days a year. The deck concedes this itself — *"most safety apps are opened once… this one
is already open, you used it for your commute"* is an admission that retention is the problem,
and the proposed fix means competing with Google Maps on daily turn-by-turn quality, which
three students lose catastrophically. Government will not pay quickly either: Tamil Nadu
municipal procurement runs 12–24 months, needs a registered entity, and TNSDMA has **already
funded TN-ALERT with RIMES**. You would be selling to a buyer who has already bought this.

**The free workaround that already wins.** TN-ALERT: free, government-endorsed, Tamil-language,
large install base, already alerting on saved locations. Google Maps: 100% of the routing,
shows closures, routes offline from downloaded areas. And the workaround people actually use —
a neighbourhood WhatsApp group — is free, already has the network effect, and beats any
cold-start app on the only thing that matters: how many people are reporting.

**The cold start is fatal in the exact scenario the product exists for.** On flood day one
there are no users in the affected area, so there are no observations, so `n_eff ≈ 0`
everywhere and the router falls back to the static prior — which is a 2015 map. You will have
built elaborate machinery for turning a 2015 flood raster into a route, presented as real-time.

**The blind spot.** The team is in love with the explanation layer. Nobody in a flooding
emergency reads a paragraph. The deck's own example is one sentence a template produces for
free; the LLM adds 253 MB, seconds of latency and a hallucination risk in a safety-critical
path, in exchange for nothing a user values. After prior art, the novelty you have left is the
part users care least about.

**Second blind spot: liability.** You are telling a person a road is passable. If they drown,
the first question is who told them to drive there. Three students, no legal entity, no
insurance, no disclaimer regime. TN-ALERT can absorb that because it is the government. You
cannot.

**Fastest way this dies.** Demo day. The monsoon hasn't broken, there are zero live reports, so
the demo replays 2015 data, and a reviewer asks: *"so what part of this is live?"* There is no
good answer to that question today.

**Fatal flaw.** No purchasable source provides street-level inundation for Chennai (strand C
confirms this), and the crowd that would provide it is empty at the moment it is needed. If the
hyperlocal signal cannot be manufactured, the core input does not exist — and belief, decay,
pessimism and explanation are all sophisticated machinery with no fuel.

---

### THE INVESTOR

**Proof anyone will pay: none.** Not one LOI, pilot commitment, or paid user. The 500k+
installs belong to your competitor. The closest comparable, PulsePoint, is a nonprofit funded
by fire departments — not a business, and deliberately so. Consumer safety apps have
approximately zero ARPU.

**First real rupee.** On the consumer path: ₹0 for at least 18 months. On the civic path:
12–24 months through a grant, CSR budget or municipal MoU. **But there is a nearer path the
deck never names — fleets.** Delivery and logistics operators (Swiggy, Zomato, Porter, Dunzo,
intra-city trucking) lose real money to monsoon disruption, already pay for routing, and have a
P&L line for it. A "monsoon passability API" priced per route has a buyer with a budget and a
procurement cycle measured in weeks, not years.

**Cheapest test this week — no code.** Take last monsoon's 20 worst-hit Chennai corridors.
Manually produce a passable/not-passable call for a 6-hour window using only open data. Give it
free to one delivery-fleet ops manager for a week. At the end ask one question: *"what would you
pay per month for this?"* That is a weekend, and it answers the only question that matters.

**Would I put my own money in?** As a company — **no**. As a research project with a ₹0 cost
base, a publication outcome and course credit — the yardstick is completely different, and
there it is a **yes**.

**The one number that changes my mind.** One fleet ops manager naming a figure above
₹15,000/month, or one municipal body signing an MoU for a pilot.

---

### THE JUDGE

**VERDICT: FIX FIRST.**

**Biggest risk, one line.** The system's core input — live street-level passability — does not
exist, cannot be bought, and is empty exactly when it is needed, so everything above it is
machinery without fuel.

**The 10-minute test.** Take the three worst-hit Chennai corridors from Cyclone Michaung
(4 December 2023). For each, write the exact sentence CityPulse would have displayed at 7am
that morning, using **only data that actually existed at 7am that day**. Three sentences, ten
minutes, no code. If all three read *"we have no data for this corridor,"* you have found the
real research question — and it is not the one currently on the slides.

**The exact change that flips this to BUILD.** Make the **negative-observation channel**
(traversal-silence, improvement I-02) the centre of the project rather than a footnote. The
unique asset is not the router and not the LLM — it is that a routing app, uniquely among all
these competitors, learns passability from the fact that people *are driving somewhere*. That
is the fuel nobody can buy, and it is the one input that is dense precisely where users are.

Consequences of that single change:
- **Product framing** becomes "the road passability layer for Chennai, built from the vehicles
  already moving" — not "AI that explains your route."
- **Research contribution** becomes inference of passability from sparse positive reports plus
  *structured absence*, with calibration measured. More novel than confidence decay, more
  defensible than explanation, and it directly answers the Skeptic's fatal flaw.
- **Revenue path** becomes a fleet passability API, which has a buyer with a budget.
- The explanation layer survives, demoted from headline to **the interface to uncertainty** —
  which is what it is actually good at.

Haven Mode stays cut (ADR-006).

**Standing risk to re-check next session:** whether traversal density in the flooded area is
non-zero at the moment of the flood. If people stop driving there entirely, absence of
traversal is absence of evidence, not evidence of absence — and the fix inherits the flaw it
was meant to solve. Model traversal as missing-not-at-random from day one.

**To verify before citing:** TN-ALERT's 500k+ install figure comes from strand E and has not
been independently confirmed. The app's existence and its saved-location alerting have been.

---

### Addendum — Review-fix verdict (2026-09-12, second pass)

A six-dimension read-only review found defects in the planning docs; fixes were applied as a
diff across 11 files. A Believer and Skeptic independently reviewed that diff (full reports
held by the Judge, not reproduced here). Three follow-up edits were then made in response to
the Skeptic's two concrete findings. The Judge re-ran `git diff`/`git log`, independently
recomputed every disputed number, and confirmed the follow-ups landed as described before
ruling.

**Independently verified by hand:** the `min{1,…}` clamp on `p̃` (ADR-002) and the `δ≥1`
invariant (ADR-003) are both real, previously-silent defects, now correctly stated and given
named test obligations. `n_eff≈9.8 → p̃≈0.950` recomputes to 0.9503 — correct. The prior wrong
attempt (`n_eff≈6.5`, claimed 0.95) recomputes to 0.9817 — confirmed wrong, and the file now
says so in its own text rather than hiding the correction. The clamp-saturation example
(n_eff=1.8 → 1.1025, clamped to 1.0) and the emergency-class example (z=2.0, p̄=0.7, n_eff=0.5
→ 1.448) both check out. The 78% LLM-cost figure ($88.65/$113.65) is threaded identically
across `COUNCIL_VERDICT.md`, `SYNTHESIS.md`, `APIS_AND_COSTS.md`, `OUTLINE.md` — no drift. The
`Phase 1`/`Phase 1b` split in `IMPLEMENTATION_PLAN.md` has no dangling cross-reference in
`ROADMAP.md` (grepped, zero hits) — clumsy, not broken.

**Confirmed landed, not just claimed:** (1) `CONTRACTS.md`'s corrected `n_eff≈9.8` example,
with the earlier wrong value left visible in a dated correction note; (2) `DECISIONS.md`
ADR-011's "Implementation note on rule 6," prescribing a two-layer approach (hand-audited
Tier-0 template fixture as a fixed test; denylist as an admittedly imperfect Tier-1/cloud
filter; rule 6's own precision/recall reported against the Study 3 human-κ subsample) and
explicitly forbidding shipping it as "a single unvalidated regex"; (3) `IMPLEMENTATION_PLAN.md`
T5.1's new "Required" bullet naming the disclaimer and badge-colour ban, with an explicit
acceptance criterion — a UI review against ADR-011 before the task is called done.

**VERDICT: BUILD.** The Believer and Skeptic agreed on the substance (clamp, δ≥1, ADR-010 all
real fixes); the Skeptic's two concrete gaps — the arithmetic error, and ADR-011 not wired to
the task that builds UI — are both fully closed by the follow-ups. The third thing the Skeptic
named, rule 6's semantic judgement not reducing to a mechanical lookup, is not a documentation
defect and cannot be closed by documentation — the follow-up correctly converts it from an
unacknowledged false promise into an honestly-bounded, measured risk instead.

**The single remaining gap, to close before T5.1's UI review (not before starting to build):**
ADR-011's rule-6 note commits to measuring precision/recall against the Study 3 human-κ
subsample but names no threshold and no fallback. Add one sentence: "If rule-6 recall on the
Study 3 subsample falls below [X]%, disable the Tier-1/cloud path for `low`/`stale`-confidence
cards and serve Tier-0 only" — a number and a fallback, not just a metric to report
after the fact.

**Biggest residual risk, one line.** Rule 6 (no unhedged safety assertion) is the one verifier
rule that cannot be made as reliable as rules 1–5 by construction, and the project has not yet
decided what happens when it fails silently in the field rather than in the Study 3 sample.
