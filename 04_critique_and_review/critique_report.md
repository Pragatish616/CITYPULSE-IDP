---
title: "CityPulse AI: Classification, Deep Review, Council Verdict and Revised Plan"
subtitle: "Critique of the citypulse-IDP repository, the citypulse-ai prototype and the core idea"
date: "2 October 2026"
geometry: margin=2.2cm
fontsize: 10pt
mainfont: DejaVu Serif
sansfont: DejaVu Sans
monofont: DejaVu Sans Mono
colorlinks: true
toc: true
---

\newpage

# 1. Verdicts at a glance

| Question | Answer |
|------|--------------|
| What is the code? | A well-engineered **research artifact**: TRL 4 for the router and belief engine, TRL 3 for the system as a whole. The Kotlin app is a TRL 2 UI mock-up. |
| What is the core idea? | **Systems integration plus an application case study**, with a small modelling part. It is not a new algorithm, model or dataset. |
| What kind of product? | **Civic-tech flood resilience tool delivered as a navigation feature.** The B2B "passability API" has no code behind it. |
| Deep review (8 specialists, defence round, independent adjudicator) | **Reject as currently written; needs major revision.** 5 Critical, 15 Significant (paper) plus 7 Significant (plan). |
| Four-agent council | **FIX FIRST**, for the second time. The startup becomes **KILL** without a live, timestamped passability feed by **15 Oct 2026**. The research paper is **BUILD**, written as an honest evaluation. |
| Biggest single risk | There is no live street-level passability signal. Without one, the product is a static 2015 hazard map that Google beats for free. |

# 2. How to classify the code and the core idea

The classification uses four lenses, so that each part is judged by the standard that fits it:

- **Readiness:** technology readiness level (TRL). Definitions follow EU H2020 Annex G, cross-checked with NASA NPR 7123.1.
  - "Lab" means historical replay on a workstation.
  - "Relevant environment" means live Chennai monsoon data on an Android phone costing Rs 10–15k.
- **Software maturity:** prototype, research artifact, MVP or production.
- **Contribution type:** algorithm, model, dataset, system or case study.
- **Market category.**

## 2.1 citypulse-IDP (the research repository)

| Component | TRL | Why |
|-----|--|--------------|
| `pulse_router` + `pulse_belief` | **4** | Validated as components on the full graph (193,191 nodes; 471,240 directed edges). Two runs give byte-identical replays, and an independent SciPy port reproduced the paths on 100 of 100 origin–destination (OD) pairs. The data are historical: one timestamp, no depth, no negative reports. The ALT module is TRL 3 (tests only, not on the query path). |
| `pulse_explain` (Tier 0 + verifier) | **3–4** | Unit and adversarial tests exist. The review found sentences that should fail but pass. |
| Tier 1 / Tier 2 rewriters | **2–3** | Code is written against the APIs but has never been executed. |
| Flutter client | **3** | Runs one fixed query in a desktop host. There has been no device run and there is no report screen. |
| Server and sync | **3** | Tested in memory. Workers are unscheduled, the server has never been deployed, and hybrid logical clock (HLC) ordering is not used for paging. |
| **Whole system** | **3** | Each critical function has been shown separately, but the integrated system has never been demonstrated. |

- **Maturity: research artifact.** It sits above "prototype": it has ADRs, contracts, about 290 tests, determinism checks and recorded negative results. It sits below "MVP": no user can choose a route, submit a report or receive live data.
- **Architecture:**
  - modular monorepo with a shared pure-Dart core;
  - functional core with an imperative shell;
  - query pipeline: belief → pessimistic index → cost → search → trace → template → gate;
  - offline-first thick client (SQLite with R\*-tree, plus an outbox);
  - thin, event-sourced ingest server.

## 2.2 citypulse-ai (the Kotlin app from the handoff file)

- **TRL 2.** The concept is formulated and illustrated, but none of it is validated:
  - 27-node hand-made graph with invented priors;
  - confidence badge hard-coded at 94% online / 88% offline;
  - slowdown curve $1+3.2\tilde p^{1.5}$ wrongly attributed to Pregnolato;
  - the "Tier-1 SLM" is a second template;
  - the numeral checker uses `abs()`, so sign errors pass.
- **Maturity:** a UI/design mock-up generated with an AI app builder; a single-module Android MVVM app.
- **Use it as** a pitch and UX reference only. None of it is evidence for the method.

## 2.3 The core idea

- **Not a new algorithm.**
  - Bidirectional Dijkstra and ALT are textbook methods.
  - ALT's correctness when weights rise is Delling and Wagner (2007).
- **Not a new model.**
  - Log-odds fusion is the occupancy-grid method.
  - The pessimistic index is a one-sided Wald band. Its Bayes-UCB and pessimistic-RL relatives are already published.
  - Separating slowdown from harm, and the "ambiguity-seeking" argument against confidence-scaled penalties, are useful but small modelling points.
  - The $1+\lambda s$ penalty-cap proposition is elementary but explains the main empirical result.
  - The new non-monotonicity result (one weak report *lowers* the index) is a genuine, if negative, analytical finding.
- **Not a dataset.** The 2015 corpus is derived from OpenCity, has one timestamp, and has no independent labels.
- **What is publishable:**
  - the combination;
  - an honest replay evaluation on a real city graph;
  - the lesson that crowd evidence added nothing over the static prior on this corpus.

  That makes it an applied systems / ICT4D paper. Likely venue types are ACM COMPASS, IEEE GHTC or ITSC, ISCRAM, or a SIGSPATIAL short or demo paper.
- **ACM CCS:**
  - *Primary:* Applied computing → Operations research → Transportation.
  - *Secondary:* Information systems → Spatial-temporal systems; Computing methodologies → Probabilistic reasoning, Uncertainty quantification, Natural language generation; Human-centered computing → Ubiquitous and mobile computing.
- **Market category:**
  - *Primary:* civic-tech / public-good resilience tool, delivered as a consumer navigation feature.
  - *Credible second:* emergency-services decision support (the $z=2$ class), but no dispatch or fleet code exists.
  - *B2B passability data API:* not supported by any code today.

## 2.4 What the critique evaluates

The idea makes three claims, and the critique tests each one.

1. **The belief helps routing.** The test is whether routes change usefully when they are scored against something other than the model's own belief.
2. **Pessimism protects users when evidence is thin.** The test is whether the index actually rises as evidence thins.
3. **Explanations are verified.** The test is whether the gate rejects false or unsafe sentences.

The review (Section 3) and the replay re-analysis answer **no** to all three on the current code and data. Section 5 sets out what would change that.

# 3. Deep review report

**Process.**

1. Eight specialist reviewers covered novelty (three strands), route evaluation, calibration, the formulation, business, and code-versus-claims with classification. They produced 83 findings.
2. Five defence agents argued for the authors on every finding and re-ran numbers where they could.
3. A fresh adjudicator, who had seen neither side being written, ruled keep, downgrade, merge or drop on each finding.

All numbers below were reproduced by at least two agents.

## 3.1 Overall assessment

**Reject in current form; it needs a major revision to be competitive.** The draft is unusually candid. It reports weak calibration and a circular reference, shows deterministic reproduction, and includes an independent router check. It fails on three fronts:

- **Central claim.** "Caution grows as evidence thins" is arithmetically false along real evidence paths.
- **Evaluation.** No gain can be credited to fusing crowd reports. Every gain comes from avoiding uncalibrated static prior zones.
- **Implementation.** The code differs from the description: evidence is one-directional, ALT is not used, nothing has run on a device, and sync does not work as described.

The "verified explanation" half is unevaluated, and the shipped gate passes unsafe sentences.

## 3.2 Critical (5)

1. **The pessimistic index is non-monotone.** An ageing positive report lowers $\tilde p$ at every $z$. One fresh crowd report ($\alpha=0.6$; crowd reports are 82% of the corpus) also lowers $\tilde p$ for every $z>0$, until about three reports agree. At $p_0=0.05$ and $z=1.28$: 0.329 with no reports, 0.309 with one, 0.333 with two, 0.380 with three. The crossover is at $\alpha^*\approx0.63$.
2. **Evidence is one-directional.** Each observation snaps to a single directed edge. 5,177 of the 5,775 observed edges have a reverse twin, and only 2 of those twins carry evidence. A flooded two-way street is therefore penalised in one direction only. This is a live bug, and it biases every exposure number.
3. **Nothing credits crowd fusion.**
   - The advantage of the soft penalty over hard blocking is −0.28 on prior-only edges and +0.04 (worse) on edges with observations.
   - Against held-out official reports, prior plus crowd routes the same as, or slightly worse than, the prior alone.
   - Crowd evidence worsens the Brier score relative to the prior alone (0.0478 vs 0.0361 at age 0).
4. **"Verified" explanations can be false and unsafe.**
   - The template says "avoids X" while the chosen route crosses X.
   - The gate accepts comparisons whose direction is flipped.
   - The gate accepts "the bridge is dry now, go ahead on Route B" for a bridge the router had removed.
5. **"Runs entirely on the phone" is not implemented.** There is no device run, no on-device prior (the prior file is 152 MB), no snapping of reports to edges, no reporting screen, and only one fixed OD pair.

## 3.3 Significant (15 paper, 7 plan)

**Novelty and claims**

- Every component has precedent that the paper does not cite, so the novelty reduces to the combination.
- The motivation omits:
  - Google Maps India and Mappls flood alerts;
  - Chennai's real-time flood forecasting (RTFF) pilot;
  - the RiskMap Chennai pilot (2017–19).

**The pessimistic index and the prior**

- The index saturates: with $z=2$, $\tilde p=1$ on all 8,759 prior-only edges.
- Eq. (3) is not a bound:
  - $n_{\mathrm{eff}}$ ignores reliability;
  - conflicting reports read as certainty;
  - the band collapses near 0;
  - about 97% of edges get no penalty at all.
- The susceptibility prior is used as P(flooded now), with no gate for whether a flood event is happening.

**Routing**

- The depth rule never fires, because no depth data exist. It would also leave commuters routed through reported deep water on low-prior edges.
- ALT is not on the query path. The paper, Fig. 1 and ADR-012 all describe it as if it were.

**Explanations**

- The Tier 1/2 rewriters have never been executed.
- "N minutes slower" compares penalised cost with plain travel time.
- The template invents "reported moments ago" for edges that have no report.
- When Tier 0 fails its own check, the error is uncaught: no route is shown, and the banner prints the unverified text.
- Data-gap flags are inverted: low-prior edges are flagged, while high-prior edges without observations are not.

**Sync**

- HLC stamps are not used for ordering, so a report made offline and uploaded late is skipped.

**Evaluation**

- The calibration study's AUROC of 0.61 comes from confounds:
  - 5,000 undisclosed easy negatives;
  - GCC coverage (inside it, the prior's AUROC is 0.456 and C3's is 0.455);
  - edge length, which alone scores 0.651.
- The Brier skill score is negative (−0.70 against climatology).
- "No advantage of class-specific decay" implies a test that simulated ages cannot run.
- The hybrid baseline (block $\bar p>0.5$ plus $\lambda=5$) was missing. It reaches 0.79 at a 2.14% detour with zero high-risk crossings, which removes the trade-off the paper presented as forced.

**Plan**

- Fleet-first revenue is unsupported.
- The moat is overclaimed.
- Selling "passability" contradicts ADR-011.
- Outreach to government vendors is scheduled too late.
- The consumer segment and the RiskMap precedent are not addressed.
- Sequencing collides with the monsoon and exams.
- There is no funding path or commercial-validation metric.

## 3.4 Minor and dropped

- **Minor:** 25 items on wording, units, figure labels, test counts, the Kotlin graph size, and missing plan risk rows.
- **Dropped (4):**
  - "evaluation contribution is weak", because it is standard for this paper type;
  - "traversal silence not built", kept as a recommendation instead;
  - "Tamil", which is only a stated limitation;
  - one empty finding.

## 3.5 Questions for the authors

1. If Eq. (3) is replaced by a Beta posterior quantile with a reliability-weighted, conflict-aware evidence count, does any routing conclusion change?
2. If evidence is assigned to both directions of two-way streets, do the comparison with C1 and the crossing shares still hold?
3. Is there any setting where crowd evidence beats prior-only routing or calibration against ground truth that is independent of GCC products (for example, time-stamped 2023 Michaung data)?
4. Has the app run on a physical Android phone? What are its latency, memory use and on-device prior footprint?
5. After the direction, polarity and trace fixes, what are the gate's pass, false-reject and detection rates on real Tier 1/2 output?
6. How is the prior conditioned on an active event? What does the emergency class do on a dry day?

## 3.6 How the redrafted paper responds

| Review issue | Response in the v2 paper |
|------|-----------|
| Non-monotone index | Retitled as an *index*, not a bound. Now Proposition 2, with the numeric table. The "caution grows" claim is removed. |
| One-directional evidence | Disclosed under "What did not work". Absolute exposure figures are flagged as undercounts. |
| Nothing credits crowd fusion | Now the **main result** (RQ2). Adds the observed vs prior-only split (Fig. 3), the hybrid baseline and the official-holdout table. |
| False or unsafe explanations | "Verified" dropped from the title. A gate table with known gaps and the false-accept examples is included. Explanations are explicitly not claimed to be verified. |
| Not on the phone | "Implementation status" table added. The figure caption now says "intended to run on the phone". |
| ALT, HLC, saturation, prior semantics, calibration confounds, BSS, 5,000 negatives | All disclosed with numbers. ALT and HLC are described as implemented. |
| Prior art and motivation | Related work rebuilt with 90 references (was 61), covering Google Maps India, Mappls and RiskMap. |
| Contribution type | Reframed as a systems integration and case study, with three research questions. |


# 4. The four-agent council

The four roles were run one after another, each as a separate agent:

1. **Believer:** read the idea.
2. **Skeptic:** read the idea, the Believer's case and the review's surviving issues.
3. **Investor:** read all of the above.
4. **Judge:** ruled last.

Each agent received the user's prompt verbatim. Market facts came from the session's market research notes. In this section those figures are the agents' own and were not re-verified. One correction: the test count is about 290, not 250.

## 4.1 The Believer

#### WHO
The Chennai driver at a flooded subway at 9 pm in December, and the motor insurer who pays when that driver guesses wrong. Cranking a submerged engine is typically not covered, and an engine repair runs about Rs 1.5 lakh. Insurers lost about Rs 4,800–5,000 crore in 2015, mostly on motor claims, and saw 10,000+ motor claims after Michaung. Today people stitch together Google Maps, GCTP and GCC posts on X ("85 roads waterlogged") and WhatsApp. Hyderabad traffic police have said Maps cannot detect waterlogging. No one publishes per-segment passability with an age and a confidence attached.

#### WHY NOW
The city has finally put sensors on the problem. 17 of GCC's 22 subways have water-triggered boom barriers. There are 40 flood-meter CCTVs, 46 flood sensors, and an ICCC that lists "data integration and APIs" in its scope. CFM-DSS exposes a public WFS (181 layers were mirrored on 29 Sep 2026). GCC has named 290 past waterlogging points for this monsoon. Michaung took down exchanges in Tambaram, Adyar and Velachery, so offline matters. On-device small models now make offline explanations feasible. The monsoon starts this month.

#### BEST VERSION
Not another consumer map, but the Chennai passability layer. It would keep a timestamped, decaying probability per road segment, with an honest "we don't know". It would fuse GCC/GCTP text, barrier and sensor states, and vehicles that pass through without reporting. Insurers would use it to warn policyholders before they drive into water. Fleets would route on it. Phones would keep a copy for when the network dies. Police already pay a vendor (roadEase/Lepton) to push closures into maps, which proves the demand for structured feeds.

#### UNFAIR ADVANTAGE
The team is local, and its engineering is real. They have the full Chennai OSM graph (193,191 nodes) and a prior built from 7,453 GCC hazard polygons. They have a 6,132-observation 2015 replay corpus, deterministic runs and about 250 tests. Their explanations fail closed and never claim a road is "safe". No incumbent documents per-segment probability, report-age decay or offline uncertainty-aware routing, and Google calls Flood Hub's urban forecasts area-level. The algorithm is not the moat; prior art covers it. The moat is being on Chennai's streets this monsoon, collecting timestamped passability labels nobody else is collecting.

#### THE BET
That timestamped street-level passability signals for Chennai can be captured live this monsoon. Those signals are subway barrier states, flood meters, police closure posts and vehicles passing through without reporting. If they can, a calibrated per-segment probability will beat "Google Maps plus X posts" on the roads where engines actually drown.

## 4.2 The Skeptic


#### WHO WON'T PAY
Commuters won't. Google Maps is free, has 60M+ Indian contributors, and has offered flood/waterlogging reports with one-tap confirmation since October 2024. The WTP studies are blunt: drivers refuse to pay because free information exists. Insurers, the Believer's hero buyer, fund flood information as CSR (HDFC ERGO → mumbaiflood.in) or build it in-house (ICICI Lombard). There is no evidence of any insurer buying a third-party road feed. Delivery platforms solve it themselves (Zomato's 650+ weather stations, Blinkit's route blacklists). Tamil Nadu builds its own stack (TN-ALERT, TNSMART, a ₹107.2 crore forecast system) and buys system integrators, not student crowd apps. The one local price anchor, GCTP's ₹96 lakh/year, went to an IIT-incubated firm repackaging Google's traffic data.

#### ALREADY SOLVED BY
Google Maps: crowd flood reports, police-fed closures in 18 Indian cities, and Flood Hub urban flash-flood forecasts (March 2026). Google says it is working toward hyper-local resolution. roadEase/Lepton already pushes GCTP closures into Google Maps within 15 minutes. Mappls takes waterlogging reports. The free workaround that Chennai actually uses (Maps plus GCTP/GCC posts on X plus WhatsApp) costs nothing. The remaining gap, per-segment probability and offline use, is one no paying buyer has asked for.

#### BLIND SPOT
The math is not the product, and the math doesn't hold. The review found that "caution grows as evidence thins" is arithmetically false on real evidence paths. Crowd evidence worsens Brier against the prior alone, and the soft-routing gain comes entirely from prior-only GCC-zone edges. The default commuter setting changed 7/100 routes for +0.026 s, which is nearly hazard-blind. Of 5,775 observed edges, 5,177 have an unpenalised reverse twin. The "verified" explanation layer accepts "the bridge is dry now, go ahead". There has been no device run. The corpus has one 2015 timestamp, no depth and only positive reports. What exists is a static prior lookup dressed as Bayesian fusion, with zero passability ground truth.

#### FASTEST DEATH
The monsoon starts this month, inside the 7-week window. The bet needs live barrier states, flood meters and vehicle traversals, and the team has access to none of them. Vendor outreach is already flagged as too late. The team's own earlier council said the crowd is empty exactly when it is needed. The season passes with no labels, a Rs 0 budget buys no sensors, exams intervene, and Google keeps shrinking its forecast cells.

#### FATAL FLAW
The team has no live street-level passability signal it can actually obtain. If GCC/GCTP will not hand over barrier and sensor states this monsoon, CityPulse is a 2015 static hazard map with uncertainty decoration, and Google already serves the free version to everyone. Do not build it.

## 4.3 The Investor


#### PROOF OF PAYMENT
None. CityPulse has zero paying customers, zero LOIs and zero priced pilots. Money does move in this space, but none of it moves toward this team:
- GCTP pays ₹96 lakh/year to Mandark, an IIT-incubated firm, for a monitoring tool built on Google traffic data.
- GCC's ₹98.25 crore ICCC 2.0 contract goes to one system integrator through an open tender.
- Insurers spend through CSR (HDFC ERGO funds mumbaiflood.in) or build in-house (ICICI Lombard with Bhugol).
- Zomato gives its weather data away for free.
- Consumers: in Lyon, most drivers refused to pay because free information exists. There is no India WTP study.

The Believer's figures (₹4,800–5,000 crore of 2015 claims, ₹1.5 lakh per engine) measure pain. They are not proof that anyone will pay. RiskMap Chennai got 111,808 page views in 24 hours and still died after 2019. Heavy usage did not turn into revenue.

#### FIRST DOLLAR
Not inside the 7-week window. Consumers will never pay, because Google is free. Government money arrives on tender cycles, and the ICCC tender was only proposed in Sept 2026. Fleets build their own tools. Estimate: the earliest realistic money is a CSR or research grant, 6–12 months out, after this monsoon has passed. That would be a grant, not a sale.

#### CHEAPEST TEST THIS WEEK
Cost ₹0, done by 8 Oct. Write a one-page offer: "Live Chennai road-passability feed for the Oct–Dec monsoon, paid season pilot, ₹25,000" (price is an estimate). Send it to 20 named buyers:
- Chennai dark-store and fleet operators
- 5 motor-insurer regional claims heads
- Mandark and Lepton (roadEase), asking whether they would pay for GCC subway-barrier states as a structured feed

Pass: at least 2 signed LOIs with a rupee figure. Fail: compliments and "keep us posted".

#### MY MONEY
No. Not one rupee today. There is no payment signal. The team controls no live data source, and the only comparable contract went to an incumbent with police relationships.

#### THE NUMBER
**₹1,00,000 committed in writing by one non-grant buyer before 15 Dec 2026.** The buyer can be a fleet, an insurer or a GCTP/GCC vendor. ₹1 lakh is about 1% of GCTP's ₹96 lakh/year contract, and it is less than one drowned engine (₹1.5 lakh). If they can't sell that much during an active monsoon, they can't sell at all. If they hit it, I write a cheque.

## 4.4 The Judge


#### VERDICT: FIX FIRST, and this is the last FIX FIRST
The Skeptic and Investor win on the facts. Nobody pays, Google already does free flood reports, and the commuter default is nearly blind to hazards (7/100 routes changed, +0.026 s). The crowd evidence also makes Brier worse than the prior. The Believer is right about one thing: the moat is labels, not maths. But the team still has no labels. The 12 Sep council gave the same verdict for the same reason, and the fix it asked for (traversal-silence) never happened. If this second FIX FIRST also stalls, the startup is KILL.

**Split:** The **research paper is BUILD** now. Its bar is honest evaluation, not revenue. Report the negative and weak calibration results, the re-scored routes, and the "λ caps penalty at (1+λs)" proposition. Drop the ALT novelty claim, which is already in Delling & Wagner 2007, and correct the "caution grows as evidence thins" claim. The **startup is FIX FIRST**, and it turns into KILL on the date below.

#### BIGGEST RISK
The team has no live, timestamped, street-level passability signal it can get, so the product is a static 2015 hazard map with uncertainty decoration.

#### 10-MINUTE TEST (no code)
Open the CFM-DSS public WFS GetCapabilities in a browser and pull one GetFeature from any subway-barrier, flood-meter or sensor layer.
- **Pass:** the layer has a per-location reading with a timestamp from today.
- **Fail:** only static polygons or old snapshots. In that case, the same day, email GCC ICCC and GCTP one question: "Can we poll barrier and sensor state this monsoon?"

#### EXACT CHANGE THAT FLIPS IT TO BUILD
By 15 Oct, cut the scope from 471k edges to GCC's 22 subways plus its 290 named waterlogging points. Wire one live, timestamped feed into the belief engine, from CFM-DSS or a written yes from GCC/GCTP. Log every reading as a passability label. That fixes the single-timestamp, no-depth, positives-only corpus. Commercial flip: the Investor's bar of ₹1,00,000 committed in writing by one non-grant buyer before 15 Dec. No feed by 15 Oct means the startup is KILL and the team ships the paper only.


**Shared note (saved to memory):**

- **Idea:** CityPulse AI, offline hazard-aware Chennai routing on decaying per-segment flood probabilities, plus a passability feed for insurers and fleets.
- **Verdict:** FIX FIRST (2nd time; startup is KILL if no live feed by 15 Oct). Research paper: BUILD now as an honest evaluation with the negative results.
- **Risk:** The team has no live, timestamped street-level passability signal, so it is a static 2015 hazard map that Google already beats for free.
- **Next:** Check the CFM-DSS WFS for live barrier and sensor timestamps today; email GCC ICCC and GCTP; rescope to 22 subways + 290 points; chase ₹1 lakh LOI by 15 Dec.

# 5. Revised plan

The plan keeps two tracks apart, because they have different bars. The **research track** needs honest evidence. The **startup track** needs a live signal and a paying buyer. Dates assume today is 2 October 2026 and that the northeast monsoon arrives in October.

## 5.1 This week (2–8 October): tests before code

| Test | Cost | Pass | Fail |
|-----------|--|-----|------|
| **Judge's 10-minute test.** Open the CFM-DSS public map service (WFS) GetCapabilities. Pull one GetFeature from any subway-barrier, flood-meter or sensor layer. | 10 min | Per-location readings carry today's timestamp. | Only static polygons or old snapshots. Email GCC ICCC and GCTP the same day: "Can we poll barrier and sensor state this monsoon?" |
| **Investor's demand test.** Send a one-page offer for a season pilot (price is the Investor's estimate) to 20 named buyers: fleets and dark stores, 5 insurer claims heads, and the two traffic-data vendors. | Rs 0 | At least 2 signed LOIs that name a rupee figure. | Compliments and "keep us posted". |
| **Field-label pilot.** Pick 10 of GCC's 22 subways near campus or home. Agree a protocol: a timestamped photo plus a passable / not passable / unknown flag on every rain day. | Rs 0 | 3 people can log 10 sites within 24 h of rain. | Logging lags by more than a day. |

## 5.2 Gate on 15 October

- **Live feed obtained** (a CFM-DSS layer or a written yes from GCC or GCTP): the startup track continues, rescoped to the 22 subways plus the 290 named waterlogging points.
- **No feed:** the startup track stops (KILL, as the Judge ruled). The team ships the paper and keeps logging field labels as research data.

## 5.3 Research track (whatever happens at the gate)

**Weeks 1–2: fix what the review found** (in the repository, by the team)

1. Snap each observation to both directions of two-way streets.
2. Replace Eq. (3) with a Beta posterior upper quantile. Use a reliability-weighted evidence count, and handle negative reports.
3. Add an event gate on the prior, and decide what the emergency class does on dry days.
4. Fix the explanation layer:
   - make the "avoids" wording depend on the actual route;
   - compare free-flow time with free-flow time;
   - stop inventing report ages;
   - catch Tier 0 failures and still show the route.
5. Strengthen the gate: check comparison direction, tie each number to its subject, and add a negation and paraphrase test set.
6. Either put ALT on the query path or remove it from the description.
7. Page sync by HLC, not by arrival order.

**Weeks 2–4: re-run the studies**

- Re-run Study 1 with the hybrid baseline and the observed/prior-only split, and report disconnections.
- Rebuild Study 2:
  - report the crowd pool and the no-report pool separately;
  - control for coverage and edge length;
  - report the Brier skill score against climatology and the prior.

**Weeks 3–8: collect independent labels and run on a device**

- Collect independent labels during the monsoon from three sources:
  - the field protocol above;
  - any live CFM-DSS layer;
  - official closure posts, with timestamps.
- Use these labels for the first test of the belief that does not reuse the belief itself.
- Run the app on a Rs 10–15k Android phone. Measure latency, memory, the size of the on-device prior, and the gate's pass and false-reject rates on real Tier 1 output.

**Submission**

- Submit the v2 paper once the fixes are in and the numbers have been re-run.
- Pick from: ACM COMPASS, IEEE GHTC or ITSC, ISCRAM, or a SIGSPATIAL short paper. Check current deadlines before choosing.
- The literature review can go to a survey venue or be used as the thesis chapter.

## 5.4 Startup track (only if the gate passes)

- **Product:** a Chennai passability layer for the 22 subways and 290 points. Each point gets a timestamp, an age, a confidence and an honest "unknown". It is delivered as a feed and a simple public map.
- **First buyers to test,** in order:
  1. a traffic-data vendor that already serves the traffic police;
  2. one fleet or dark-store operator;
  3. one insurer's claims team.

  Consumer revenue is not expected, because Google is free.
- **Money:** go after a CSR grant or a government innovation grant in parallel; it is the realistic first money (Investor estimate: 6–12 months away). Commercial bar: a written commitment of Rs 1 lakh from a non-grant buyer by 15 December.
- **Positioning:** do not sell "safe routes", which ADR-011 itself avoids. Sell timestamped evidence with its age and confidence.
- **Constraints:** respect the DPDP Act. Keep saved places explicit, and do not track location passively.

## 5.5 What to stop doing

- Do not claim novelty for flood-aware routing, report decay or ALT correctness.
- Do not call the explanations "verified" until the gate's error rates have been measured.
- Do not use the Kotlin mock-up as evidence for the method.
- Do not expand to new hazards or cities before one Chennai monsoon of labels exists.

# 6. Sources and verification

- **Paper and review:** every reference was checked against Crossref, arXiv or a publisher or project page in this session. The paper cites 90 works and the literature review 323.
- **Market facts in Section 4:** these come from the session's market notes and the council agents, and were not independently re-verified.
- **Code facts:** these come from read-only copies of the two repositories. Nothing in the user's folders was changed.
