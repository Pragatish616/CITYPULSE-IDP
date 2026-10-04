# Strand E — Prior Art, Competitive Landscape, Patents, and Evaluation Methodology

**Agent:** Research Agent E (adversarial / prior-art strand)
**Date:** 2026-09-12
**Project:** CityPulse AI (VIT Chennai, 7-week build-to-demo)
**Mandate:** Be the project's toughest critic. Establish what already exists so the team
does not claim novelty that is not there.

> **Headline verdict.** Of the four claimed novelties, **none is novel as an isolated
> capability.** Hazard-aware routing is a 15-year-old patented idea with shipped
> commercial implementations. Confidence/recency decay of crowdsourced incident reports
> is standard practice at Waze and TomTom and is the subject of an active literature.
> Natural-language explanation of route choice has a granted 2003 patent in the
> navigation domain and a 2025 arXiv literature in the LLM domain. "Haven Mode" is
> substantially Google's Personal Safety / Crisis Alerts plus Flood Hub subscriptions —
> and, in Tamil Nadu specifically, is close to what the state's own **TN-ALERT** app
> already pushes to 500,000+ devices in Tamil.
> **What is defensible is the *integration point*: hazard-aware routing whose
> explanation and confidence state are generated on-device and remain correct when the
> network is gone.** That is a systems contribution, not an algorithmic one, and it must
> be pitched and evaluated as such. See §3 for the per-claim verdict and §6 for a
> 7-week protocol that can actually substantiate it.

---

## 1. Verified competitor capability matrix

Legend: **Y** = verified shipped capability; **N** = verified absent; **P** = partial /
qualified; **?** = not verifiable from primary sources.

| System | Live hazard ingest | Hazard-aware **routing** (reroutes) | NL explanation of *why* this route | Works fully offline | Confidence/decay on reports | India coverage |
|---|---|---|---|---|---|---|
| **PulsePoint Respond** | Y (CAD feed from 4,400+ agencies) | **N** — no routing/turn-by-turn at all | N | N | N | N (US/Canada) |
| **Google Flood Hub** | Y (AI forecast, 150+ countries) | **N** — forecast/inundation maps only | N (plain-language summaries, not route reasons) | N | P (model uncertainty, not report decay) | **Y — nationwide India** |
| **Waycare → Rekor** | Y (probe + agency + weather fusion) | **P** — advisory to DOT/TMC operators, not driver rerouting | N | N | P (incident confidence internal) | N (US) |
| **Waze** | Y (crowdsourced: Flood, Fog, Icy, Slippery, Bad weather, Unplowed) | **P — yes for closures/hazards on the map; flood reports are warnings, routing avoidance is not documented** | N (shows *an* alert, not a rationale) | **N** — routing is server-side | **Y** — reports expire on a community-engagement-driven TTL | Y |
| **Google Maps** | Y (SOS Alerts, crisis layer, rapid flood maps, user-reported road closures) | **P** — alerts when your route enters a crisis area; automatic rerouting not documented | N | **P** — offline areas give turn-by-turn but **no live traffic/incidents** | P | Y |
| **Apple Maps** | P (user incident reporting: crash, hazard, speed check) | P | N | P (offline maps since iOS 17) | ? | Y |
| **TomTom (Hazard Warnings API)** | **Y** — 9 hazard categories, ~30s updates, 600M+ device probe network, OpenLR referencing, 80+ countries | P — push warnings to driver/AV; routing integration not stated on product page | N | N (cloud API) | ? (not stated publicly) | Y |
| **OsmAnd / Organic Maps** | N | N | N | **Y** — full offline routing on device | N | Y (OSM) |
| **NDMA Sachet (India)** | Y (CAP-style geo-tagged alerts, 12 languages) | **N** | N | N | N | **Y — national** |
| **IMD Damini / Mausam** | Y (lightning location network / weather) | N | N | N | N | Y |
| **TN-ALERT / TN-SMART (TN govt + RIMES)** | **Y — location-based flood risk alerts, dam storage, multi-hazard impact assessment, Tamil + English, 500k+ installs** | **N** | N | N | P (user feedback on alerts) | **Y — Tamil Nadu, the exact pilot geography** |
| **CityPulse AI (claimed)** | Y | Y | Y | Y | Y | Y |

### Corrections the pitch deck needs

The deck's framing — *"Competitors each solve one slice: PulsePoint (EMS/cardiac
signals), Google Flood Hub (historical + predictive flood data), Waycare et al.
(fleet/enterprise risk mapping)"* — is **directionally right but factually sloppy in
three places**, and one omission is serious.

1. **"Google Flood Hub = historical + predictive flood data" understates it badly.**
   Flood Hub is a live operational AI forecasting service covering **over 150 countries
   and ~2 billion people**, with **up to 7 days lead time for riverine floods and up to
   24 hours for urban flash floods**, a public **Flood Forecasting API**, an open-sourced
   hydrology model, inundation-history datasets, and (since 2025) email subscriptions to
   forecasts for a saved location. Critically, **its flood forecasting covers the whole
   of India**. If CityPulse says "Flood Hub is historical data" in front of a reviewer
   who knows the domain, the talk is over. Say instead: *Flood Hub forecasts basins and
   publishes inundation extents; it does not touch the road graph and produces no route.*
   That is the true and defensible gap.
   ([Google Flood Forecasting](https://sites.research.google/gr/floodforecasting/),
   [Flood Forecasting API](https://developers.google.com/flood-forecasting),
   [India/Bangladesh nationwide expansion](https://indiaai.gov.in/news/google-s-flood-forecasting-initiative-extends-to-the-whole-of-india-and-bangladesh))

2. **PulsePoint is *further* from CityPulse than the deck implies, in a way that helps
   you.** PulsePoint Respond does **not route anybody anywhere**. It shows the incident
   location and nearby AEDs on a map and hands off; it has no navigation engine. It also
   already does something the deck ignores: it pushes **public-interest alerts for
   wildfires, flooding and utility emergencies** to the community feed across 4,400+
   communities and 3M+ subscribers. So it *is* a civic hazard-alert channel — just not a
   router. ([PulsePoint Respond](https://www.pulsepoint.org/pulsepoint-respond),
   [Responder types](https://www.pulsepoint.org/responder-types-and-features))

3. **"Waycare et al." is stale.** Waycare Technologies was **acquired by Rekor Systems
   in 2021 for ~$61M** and the product line is now Rekor's. Calling it "Waycare" in 2026
   signals the competitive research was done from a 2020 blog post. Also, Waycare/Rekor
   is a **B2G traffic-management-centre product** — it advises DOT operators on where to
   stage units and when to push variable-message-sign warnings. It is not a consumer
   router, so it is a *weaker* competitor than the deck implies but a *stronger*
   precedent for "fuse heterogeneous signals into predicted road risk."
   ([Rekor acquisition release](https://www.rekor.ai/post/rekor-systems-to-acquire-waycare-technologies-ltd),
   [ITS International](https://www.itsinternational.com/its5/its8/news/rekor-acquire-waycare-61m))

4. **Omission — TomTom is the most dangerous competitor and the deck does not mention
   it.** TomTom **Hazard Warnings** is a shipping commercial product delivering **nine
   hazard categories** with **~30-second update cycles**, sourced from **600M+ connected
   devices**, referenced with OpenLR onto the road graph across **80+ countries and 3.7
   billion km**. That is "live timestamped hazard signals structured as geospatial data
   on a road graph" — bullet 1 of the CityPulse engine — at planetary scale, in
   production, for years. The deck must address TomTom explicitly.
   ([TomTom Hazard Warnings](https://www.tomtom.com/products/hazard-warnings/),
   [Hazards Connected Services API](https://developer.tomtom.com/connected-services-api/contents/hazards))

5. **Second omission, and the most embarrassing one — Tamil Nadu already ships a flood
   alerting app.** **TN-ALERT**, the client for **TN-SMART** (*TamilNadu System for
   Multi-hazard potential impact Assessment and emergency Response Tracking*), is
   published by **RIMES** (Regional Integrated Multi-Hazard Early Warning System) for the
   Tamil Nadu government. It delivers **location-based flood risk alerts**, weather
   forecasts for five saved locations, **dam storage information**, and tiered alert tones
   that override silent mode, in **Tamil and English**. It has **500,000+ installs** and
   was **last updated October 2025** — i.e. it is live and maintained, not abandoned. At
   the national level NDMA's **Sachet** delivers geo-tagged multi-hazard alerts in **12
   Indian languages**, and IMD's **Damini** (lightning) and **Mausam** cover their
   verticals. A Chennai-focused civic-resilience pitch that does not name TN-ALERT and
   Sachet reads as if the team did not look at what their own state and national
   governments already ship — and a VIT Chennai reviewing committee is *very* likely to
   know TN-ALERT exists. The honest and genuinely defensible gap: **TN-ALERT and Sachet
   tell you a hazard exists near a point; neither touches the road graph, and neither
   routes you anywhere.**
   ([TN-ALERT on Google Play](https://play.google.com/store/apps/details?id=int_.rimes.tnsmart&hl=en_IN),
   [TN-SMART, Tiruchirappalli district](https://tiruchirappalli.nic.in/revenue-department/tn-smart-mobile-app/),
   [Sachet — NDMA](https://sachet.ndma.gov.in/DownloadMobileApp),
   [Sachet overview](https://en.wikipedia.org/wiki/Sachet_(app)),
   [Damini](https://web.umang.gov.in/landing/department/damini-lightning-alert.html))

### Disaster / civic-alert app layer (verified)

- **FEMA app (US)** — real-time NWS alerts for up to 5 locations, preparedness content,
  shelter/disaster-recovery-centre locator, disaster-assistance application. No routing.
  ([FEMA Mobile Products](https://www.fema.gov/about/news-multimedia/mobile-products))
- **Disaster Alert (Pacific Disaster Center)** — global multi-hazard active-hazard map.
  Awareness product, no routing.
- **Zello** — push-to-talk over cellular; surged in downloads during Hurricane Irma and
  is genuinely used by volunteer rescue networks (Cajun Navy). **Relevant as a warning:
  the thing disaster users actually reach for is comms, not navigation.**
  ([Gulf News — Irma download surge](https://gulfnews.com/world/americas/walkie-talkie-app-downloads-soar-as-irma-looms-1.2087393))
- **Red Cross Emergency apps** — hazard alerts + preparedness checklists. No routing.
- **India-specific:** TN-ALERT/TN-SMART, Sachet, Damini, Mausam (above). Chennai's
  **Namma Chennai** app (Greater Chennai Corporation, 100k+ installs, 2.9★) is the
  **Public Grievance Redressal System** client — complaint registration and tracking. It
  is **not** a flood alerter or router, so do not list it as a flood competitor; but it
  *is* the existing municipal citizen-reporting channel, and therefore the most plausible
  real-world ingest partner and integration story for CityPulse. Its poor rating and
  reported crashes are also a useful, concrete statement of the local need.
  ([Namma Chennai on Google Play](https://play.google.com/store/apps/details?id=com.ceedeev.grivenancev2&hl=en))
  **IIT Madras has run a crowdsourced waterlogging-tracking effort for Chennai**, which is
  the closest local analogue to CityPulse's ingest layer and should be cited and, ideally,
  contacted — they may hold exactly the historical corpus Study 1 (§6.1) needs.
  ([IIT-M crowdsourcing waterlogging](https://news.careers360.com/iit-madras-enables-crowdsourcing-track-waterlogging-in-chennai/amp))

---

## 2. Academic and civic-tech prior art

### 2.1 PetaBencana.id / CogniCity (Jakarta) — the single most important precedent

**PetaBencana.id** (formerly PetaJakarta.org) is a deployed, government-integrated,
open-source (CogniCity OSS) crowdsourced flood-mapping platform. Residents report flood
depth via a social-media chatbot; reports are verified and rendered onto a live public
map used by Jakarta's emergency management agency (BPBD DKI Jakarta). It has been running
since ~2013, is documented in an OECD/OPSI case study, a University of Wollongong white
paper, and peer-reviewed literature.

**Why this matters to CityPulse, bluntly:** PetaBencana already did *ingest + trust
weighting + civic integration + free/open + emerging-megacity monsoon context*. It
deliberately stopped short of routing. **The team should cite it as the direct
intellectual ancestor and position CityPulse as "PetaBencana's ingest model, extended to
the road graph and made offline-resilient."** Claiming crowdsourced urban flood mapping
as novel in front of anyone in the ISCRAM community will fail immediately.

Sources: [OECD/OPSI case study PDF](https://oecd-opsi.org/wp-content/uploads/2019/07/PetaBencana.id_Indonesia_2013.pdf),
[PetaJakarta white paper (UOW)](https://documents.uow.edu.au/content/groups/public/@web/@smart/documents/doc/uow200106.pdf),
[Rest of World — "Hi, I'm Disaster Bot"](https://restofworld.org/2021/hi-im-disaster-bot/)

### 2.2 Flood-aware routing in the literature

This is an established subfield, not a gap.

- **Human-centred flood mapping + intelligent routing by augmenting flood gauge data
  with crowdsourced street photos** (*Advanced Engineering Informatics*, 2022) — this is
  almost exactly CityPulse's ingest→route pipeline: sparse official gauge data fused with
  crowdsourced observations to produce a flood surface, then routing over the impacted
  network. **If the team claims "nobody fuses municipal sensors with crowdsourced reports
  for flood routing," this paper falsifies it.**
  ([ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S1474034622001884))
- **A web-based decision support framework for optimizing road network accessibility and
  emergency facility allocation during flooding** (*Urban Informatics*, Springer, 2024).
  ([Springer](https://link.springer.com/article/10.1007/s44212-024-00040-0))
- **Integrated optimization of emergency evacuation routing for dam-failure-induced
  flooding: coupled flood–road network modeling** (*Applied Sciences*, 2025).
  ([MDPI](https://www.mdpi.com/2076-3417/15/8/4518))
- **A dynamic simulation framework for evaluating the impacts of urban flooding on
  transportation systems** (*IJDRS*, 2026) — directly relevant as an **evaluation
  methodology template**, see §6.
  ([Springer](https://link.springer.com/article/10.1007/s13753-026-00697-y))
- **A reinforcement-learning-based routing algorithm for large street networks**
  (*IJGIS*, 2023) — RL routing at city scale, NOAA-affiliated.
  ([T&F](https://www.tandfonline.com/doi/full/10.1080/13658816.2023.2279975),
  [NOAA repository PDF](https://repository.library.noaa.gov/view/noaa/61350/noaa_61350_DS1.pdf))

### 2.3 Risk-aware / safest-route routing (non-flood)

A mature line of work on multi-objective "safest vs fastest" routing exists, most of it
crime- or crash-risk-based. Representative:

- *Real-time safest route identification: examining the trade-off between safest and
  fastest routes* — **this paper already defines the core metric CityPulse needs
  (risk-exposure reduction vs. added travel time) and is the natural baseline to compare
  against.** ([ResearchGate](https://www.researchgate.net/publication/370206539_Real-time_safest_route_identification_Examining_the_trade-off_between_safest_and_fastest_routes))
- *Route-The Safe: a robust model for safest route prediction using crime and accidental
  data.* ([ResearchGate](https://www.researchgate.net/publication/338096313_Route-The_Safe_A_Robust_Model_for_Safest_Route_Prediction_Using_Crime_and_Accidental_Data))
- *Danger by design? Mapping safe route choices in Tshwane, South Africa* (*J. Transp.
  Security*, 2026). ([Springer](https://link.springer.com/article/10.1007/s12198-026-00363-w))
- *Algorithm to determine the safest route* (IJCSIT). ([PDF](https://www.ijcsit.com/docs/Volume%207/vol7issue3/ijcsit20160703106.pdf))

**Implication:** the *weighted-multi-criteria-shortest-path-with-risk-penalty* formulation
is textbook. Do not write it up as a contribution. Write up the **edge-weight function
that incorporates time-decayed confidence** as the contribution, and ablate it (§6.3).

### 2.4 Natural-language explanation of routes

- **Constraint-Aware Route Recommendation from Natural Language via Hierarchical LLM
  Agents** (arXiv 2510.06078, 2025) — LLM agents parse NL constraints into routing
  objectives. This is the *inverse* direction (NL → route) rather than (route → NL), so
  it does not fully pre-empt CityPulse, but it establishes that "LLM agents on top of a
  routing engine" is an active 2025 topic with published work.
  ([arXiv](https://arxiv.org/html/2510.06078))
- **On explaining recommendations with Large Language Models: a review** (*Frontiers in
  Big Data*, 2024) — the general LLM-explanation-of-recommendations survey. The
  evaluation constructs used there (persuasiveness, transparency, trust, satisfaction)
  are the ones CityPulse's user study should borrow.
  ([Frontiers](https://www.frontiersin.org/journals/big-data/articles/10.3389/fdata.2024.1505284/full),
  [PMC mirror](https://pmc.ncbi.nlm.nih.gov/articles/PMC11808143/))
- **Trust in crowdsourced data** — *Establishing Trust in Crowdsourced Data* (arXiv
  2511.03016, 2025) and *Evaluating Trust in User-Data Networks: What Can We Learn from
  Waze?* (ODU WS-DL). These directly cover CityPulse's "decay score" territory.
  ([arXiv](https://arxiv.org/html/2511.03016v1),
  [ODU WS-DL](https://ws-dl.blogspot.com/2022/01/2022-01-18-evaluating-trust-in-user.html))
- **Context-Aware Travel Time Prediction and Route Optimization Using Heterogeneous
  Traffic and Event Data: A Comprehensive Survey** (*Future Transportation*, 2025) — use
  this survey to position the related-work section; it will also show reviewers you know
  the field. ([MDPI](https://doi.org/10.3390/futuretransp6030119))

### 2.5 Offline-first navigation prior art

| Capability | OsmAnd | Organic Maps | Maps.me | Google Maps offline | HERE offline |
|---|---|---|---|---|---|
| Offline vector maps | Y | Y | Y | Y (downloaded area) | Y |
| **Offline route calculation** | **Y** | **Y** | **Y** | **Y (driving only)** | **Y** |
| Offline turn-by-turn voice | Y | Y | Y | Y | Y |
| Offline live traffic/incidents | **N** | **N** | **N** | **N** | **N** |
| Offline transit / walking / cycling directions | Y | Y | Y | **N** | P |
| Offline search | Y | Y | Y | P (limited) | Y |

**Verified facts that constrain the claim:** Google Maps offline supports **driving
directions only** — walking, cycling and transit directions are unavailable offline, and
**there is no live traffic, no lane guidance, and no incident data** while offline. OsmAnd
and Organic Maps compute full routes on-device from OSM data with no network at all.
([How-To Geek](https://www.howtogeek.com/how-to-use-google-maps-without-an-internet-connection/),
[Organic Maps review](https://privacygear.nl/en/reviews/organic-maps-review/),
[OsmAnd review](https://privacygear.nl/en/reviews/osmand-review/))

**Blunt consequence for the deck:** *"fully functional routing with zero external
connectivity"* is **not a novel claim — OsmAnd has done it since 2010.** The novel part,
if any, is **"routing that is still hazard-aware and still explains itself with a
calibrated confidence statement when offline."** Every slide that says "works offline"
without the words "hazard-aware" and "confidence-aware" next to it is claiming something
a free app already does better.

---

## 3. Prior-art verdict per claimed novelty

### 3.1 Dynamic hazard-aware routing — **NOT NOVEL**

**Verdict: prior art is overwhelming, spanning patents (2011), commercial products
(TomTom, Uber-patented safe routing), and a live academic subfield.**

- IBM filed **US20130116920A1, "System, method and program product for flood aware travel
  routing"** in **November 2011** — flood simulation from meteorological data, neural /
  Bayesian risk modelling per route, multiple routes ranked by flood risk, delivered to a
  phone/GPS, continuously reassessed as weather changes. That is CityPulse's routing
  claim, filed 15 years ago. (It went **abandoned**, which is good news for freedom to
  operate and bad news for novelty.)
- Uber holds **US10563994B2, "Safe routing for navigation systems"** (granted Feb 2020,
  active to 2036): per-road-segment safety scores computed at **multiple time slices**,
  the segment's score looked up **for the time the vehicle will actually traverse it**,
  then shortest-path over the safety-weighted graph. The temporal dimension CityPulse
  treats as its own is claimed here.
- TomTom ships hazard detection and delivery at 30-second latency across 80+ countries.

**What to do:** stop claiming it. Reframe as: *"we apply hazard-aware routing to
monsoon-season Chennai using open data and an open routing stack, which no deployed
system currently does for this city."* Geographic/deployment novelty is a legitimate,
honest, publishable claim. Algorithmic novelty here is not.

### 3.2 Offline LLM explanation of routing decisions — **PARTIALLY NOVEL (the strongest claim)**

**Verdict: the individual pieces all exist; the specific combination is thin in the
literature and is the best candidate for a genuine contribution.**

- Route *explanation* as a concept is patented: **US6577950B2, "Route guiding explanation
  device and route guiding explanation system"** (granted 2003). But close reading shows
  it retrieves **pre-authored human-written landmark-to-landmark descriptions** — it does
  **not** generate a rationale for *why* a route was selected. **This patent does not
  block CityPulse and, importantly, it is expired.**
- **US5181250A, "Natural language generation system for producing natural language
  instructions"** — classical NLG for instructions, long expired.
- LLM-based explanation of recommendations is a 2024–2025 survey-level topic; LLM agents
  over routing engines exist (arXiv 2510.06078).
- On-device LLM inference on phones is now routine: sub-3B quantized models run at usable
  token rates on modern handsets via llama.cpp/ExecuTorch/Qualcomm QNN stacks.

**So what is actually left?** The novel conjunction is: *(a)* the explanation is grounded
in the **specific hazard features and confidence values that drove the edge weights**
(i.e. faithful to the router, not a post-hoc plausible-sounding narrative), and *(b)* it
is generated **on-device under degraded connectivity**, where a cloud LLM is unavailable.
**Both halves must be evaluated or the claim is vapour** — see §6.4 (faithfulness) and
§6.5 (offline degradation).

**Warning about faithfulness.** The single most likely reviewer attack: *"your LLM writes
a nice sentence about avoiding a flooded road; how do you know the router actually
avoided it for that reason, and not because of a traffic weight?"* If the explanation is
generated from free text describing the situation, it is a **rationalization, not an
explanation**, and a competent reviewer will say so. Mitigation: generate explanations
from a **structured decision trace** emitted by the router (the set of edges excluded /
penalised, their hazard type, age, confidence, and the resulting delta in cost vs. the
unconstrained route), and measure faithfulness by checking every factual assertion in the
generated text against that trace.

### 3.3 Confidence decay on hazard signals — **NOT NOVEL (it is industry-standard)**

**Verdict: shipped by Waze; standard in the trust-in-crowdsourced-data literature.**

Waze's own documentation states that reports "appear on the map for a certain amount of
time" and that this **duration adjusts based on community engagement** — i.e. a
confirmation-weighted, time-decaying report lifetime, in production, at global scale.
TomTom's incident model likewise attaches lifecycle state to incidents. Academic work on
trust-weighting crowdsourced reports (arXiv 2511.03016; the Waze trust analysis) covers
the same ground.

**Salvageable sub-claim:** most systems use a *fixed or engagement-based TTL*, not a
**hazard-type-specific decay function** (a flood report decays differently from a fallen
tree, and differently again during active rainfall). If the team implements
**per-hazard-class parametric decay with the half-life calibrated from historical
Chennai incident-resolution data**, and **exposes the resulting confidence in the UI and
in the explanation**, that is a modest but real, and — importantly — *evaluable*
contribution. Without calibration against real resolution times, it is an arbitrary
constant and a reviewer will call it one.

Sources: [Waze — report bad weather](https://support.google.com/waze/answer/13809605?hl=en),
[Establishing Trust in Crowdsourced Data](https://arxiv.org/html/2511.03016v1)

### 3.4 "Haven Mode" (predictive personal precaution) — **NOT NOVEL, AND THE RISKIEST ITEM**

**Verdict: substantially shipped by Google; additionally carries privacy and ethics
exposure disproportionate to a 7-week student project.**

- **Google Personal Safety / Safety Hub** already does: crisis alerts for natural
  disasters, earthquake detection and alerting, emergency SOS, safety check, car-crash
  detection. It is preinstalled on Pixel and available on Android broadly.
  ([Personal Safety on Play](https://play.google.com/store/apps/details?id=com.google.android.apps.safetyhub&hl=en_US),
  [Android emergency help](https://support.google.com/android/answer/9319337?hl=en))
- **Google Maps already infers Home/Work** and Timeline already infers "meaningful
  places" from location history — the "Learn" step of Haven Mode is a shipped Google
  feature, not an invention.
- **Flood Hub now offers email subscriptions for a saved location** — i.e. "forecast
  hazard at a place you care about, tell you about it." That is Haven Mode's Forecast +
  Detect + Recommend loop, from Google, free.
  ([Flood Hub subscriptions](https://support.google.com/flood-hub/answer/16499229?hl=en))
- **Sachet** does geo-targeted multi-hazard alerting in 12 Indian languages nationally.
- **TN-ALERT already does "hazard forecasts for your meaningful locations"** — it accepts
  **five saved locations** and pushes location-based flood risk alerts for them, in Tamil,
  in Tamil Nadu, to 500k+ installed devices. Haven Mode's Learn→Forecast→Detect→Recommend
  loop is, minus the passive inference step, **the shipped TN-ALERT feature set**. The
  only thing CityPulse adds is inferring the locations instead of asking for them — which
  is the part that creates the privacy problem and adds the least user value.

**The genuinely distinctive fragment** is *comparative* risk ("risk **here** materially
exceeds risk at a **reachable safe location you already use**") plus the recommendation
to *move now*. I have not found this shipped. But it is also:

- **The hardest thing to evaluate in 7 weeks** (you need real hazard events and real
  users making real movement decisions), and
- **A safety-critical recommendation.** "Leave your house now" is advice that can kill
  someone if the hazard model is wrong, and an Indian institutional ethics committee will
  reasonably ask about it.
- **Passive inference of home/school/family locations from routing usage** is exactly the
  kind of processing that triggers scrutiny under India's **DPDP Act 2023** (purpose
  limitation, notice and consent, data minimisation), and "encrypted" is not a legal
  answer to a purpose-limitation question.

**Recommendation — cut Haven Mode from the build and keep it as a Future Work section.**
This is the strongest single recommendation in this report. It is the least novel, the
least evaluable, the most privacy-exposed, and the most safety-exposed of the four
claims, and it is the only one whose removal makes the remaining three *more* credible
rather than less. If the team insists on demoing it, demo it as a **simulated scenario
with synthetic profiles and no real user location history** and label it as such on the
slide.

---

## 4. Patents

Assignees and dates verified via Google Patents. **This is not a freedom-to-operate
opinion** — it is a novelty-assessment aid. For an academic project, the practical risk
is zero; the reputational risk of claiming a patented idea as your invention is not.

| Patent | Title | Assignee | Key dates | Status | Relevance to CityPulse |
|---|---|---|---|---|---|
| **US20130116920A1** | System, method and program product for **flood aware travel routing** | **IBM** | Filed 2011-11-07; pub. 2013-05-09 | **Abandoned** | **Direct hit on claim 3.1.** Flood simulation from met data + per-route risk model + ranked routes on a mobile device + in-trip reassessment. |
| **US10563994B2** | **Safe routing for navigation systems** | **Uber Technologies** | Priority 2016-12-14; granted 2020-02-18 | **Active** (to 2036) | **Direct hit on time-varying risk-weighted routing.** Per-segment safety scores at multiple time slices, looked up at predicted traversal time; shortest-path over safety-weighted graph. |
| **US10074139B2** | Route risk mitigation | (State Farm–family) | granted 2018 | Active | Risk-scored route selection; insurance-telematics framing. |
| **US10309792B2** | Route planning for an autonomous vehicle | — | granted 2019 | Active | Hazard/condition-aware route planning for AVs. |
| **US20170158191A1** | System and method for vehicle-assisted response to road conditions | — | pub. 2017 | — | Vehicle-sensed road condition → response. |
| **US6577950B2** | **Route guiding explanation device and route guiding explanation system** | — | granted 2003-06-10 | **Expired** | **Closest thing to "explained routing."** But it *retrieves pre-authored landmark descriptions*; it does **not** generate reasons for route choice. **Does not block, and supports the claim that generated route rationale is under-patented.** |
| **US5181250A** | Natural language generation system for producing natural language instructions | — | granted 1993 | Expired | Classical NLG for instructions. |
| **US7693653B2 / US20050216182A1** | Vehicle routing and path planning | — | 2005/2010 | — | Background art on constrained routing. |
| US20140358427 | Enhancing driving navigation via passive driver feedback | — | pub. 2014 | — | Passive feedback loop → navigation adjustment; touches Haven Mode's "Adapt" step. |

**Patent-landscape conclusion.**
1. **Hazard/flood-aware routing is thoroughly patented prior art.** Claiming it as novel
   is indefensible.
2. **Time-varying risk-weighted edge costs are claimed and live** (Uber, to 2036).
3. **Generated natural-language rationale for a routing decision is the whitest space
   found** — the only close patent is a 2003 expired one that does template retrieval,
   not rationale generation. **This is further evidence that §3.2 is the claim worth
   defending.**
4. I found **no patent specifically on age-based confidence decay of crowdsourced hazard
   reports feeding routing weights**, but absence of a patent hit is weak evidence given
   it is demonstrably practised (Waze) and published — so it is **prior art even though
   it may be unpatented**.

---

## 5. What CityPulse can honestly claim

Ranked by defensibility. Use this wording.

1. **(Strong, systems claim)** *An offline-capable civic routing system in which the
   hazard-aware route, the confidence state of the hazard evidence, and the
   natural-language rationale are all produced on-device, so the system degrades
   gracefully rather than failing when connectivity is lost — the exact condition that
   holds during the urban flooding it targets.* Nobody found doing all three offline.
2. **(Moderate)** *Explanations generated from a structured router decision trace, with
   an empirical faithfulness measurement* — i.e. explanation you can audit, not
   post-hoc narration. Under-patented and under-studied in navigation.
3. **(Moderate)** *Hazard-class-specific confidence decay calibrated against observed
   incident-resolution times in Chennai, propagated into both routing weights and the
   user-facing explanation.*
4. **(Honest, non-technical, still worth saying)** *First open-stack (OSM + OSRM/
   GraphHopper + PostGIS) hazard-aware routing deployment targeted at Chennai monsoon
   flooding, reproducible and portable to other Indian cities.*

And the one sentence the team should internalise: **the contribution is not that hazards
affect routes; it is that the user can tell how much to believe the route, even with no
signal.**

---

## 6. Evaluation protocol executable in 7 weeks

Designed against the actual standards of SIGSPATIAL/ITSC/ISCRAM reviewing. Five studies,
none of which requires a real flood to occur during the project.

### 6.0 Ground rules

- **Freeze a study city graph.** One Chennai OSM extract, pinned by date and hash, used
  by every experiment. Record the extract URL, date, node/edge counts. Reproducibility is
  cheap here and reviewers check.
- **Pre-register the metrics before running anything.** Write §6.3's metric definitions
  into the repo in week 3 and do not change them after seeing results.
- **Every number gets a confidence interval.** Single-run numbers with no variance are
  the most common reason a systems paper gets desk-rejected from a good venue.

### 6.1 Study 1 — Historical incident replay (the backbone; do this first)

**Why:** you cannot wait for a flood, and simulated hazards alone are unconvincing. Replay
is the credibility anchor.

**Build:** a dated corpus of Chennai waterlogging/road-closure events. Sources to mine:
Greater Chennai Corporation waterlogging complaint records, TN SDMA/IMD rainfall records
for the 2015/2021/2023 events, IIT-Madras crowdsourced waterlogging data, and
press-reported closure lists. Target ≥ 200 geolocated, timestamped hazard instances
across ≥ 3 distinct events. Snap each to OSM edges with a documented snapping radius.

**Protocol:** sample N = 1,000 origin–destination pairs stratified by distance band (<3
km, 3–10 km, >10 km) and by zone flood-proneness. For each OD pair and each event
timestamp, compute routes under each system configuration (§6.3) and score.

**Report:** per-configuration distribution of every metric in §6.3, with bootstrap 95%
CIs, plus a leave-one-event-out breakdown so a reviewer can see you did not tune on the
test event.

### 6.2 Study 2 — Simulation (SUMO) for the dynamic/congestion claim

Replay alone cannot show the *emergency-vehicle-time-saved* claim, because rerouting
changes congestion. Use **SUMO** (Eclipse, open source, the standard tool; it has a
dedicated conference proceedings series, and there is published work specifically on
optimising emergency-vehicle arrival time in SUMO).

**Scope it hard — 7 weeks.** One sub-network (5–15 km², e.g. a flood-prone Chennai
corridor), demand calibrated coarsely from any available count data (state the
limitation), 3 flood severity levels × 3 penetration rates of CityPulse-guided vehicles
(0 %, 10 %, 50 %) × ≥ 10 random seeds. Measure emergency-vehicle travel time, background
network delay (to check you are not harming everyone else — reviewers *will* ask), and
number of vehicles that enter a flooded edge.

**Do not attempt MATSim or CityFlow as well.** MATSim's agent-based co-evolutionary
demand calibration is a multi-month exercise; CityFlow is optimised for RL signal control,
not hazard routing. Cite both as alternatives considered and justify SUMO. Attempting
three simulators in 7 weeks produces three unconvincing half-results.

Sources: [SUMO overview](https://www.researchgate.net/publication/225022282_SUMO_-_Simulation_of_Urban_MObility_An_Overview),
[SUMO for emergency-vehicle arrival time](https://www.tib-op.org/ojs/index.php/scp/article/view/225),
[SUMO-based evaluation of incident impact](https://e-space.mmu.ac.uk/600548/2/goSMART%20paper.pdf),
[Urban flooding → transportation dynamic simulation framework](https://link.springer.com/article/10.1007/s13753-026-00697-y)

### 6.3 Route-quality metrics (define these in week 3, freeze them)

Configurations to compare (this is the ablation table that makes or breaks the paper):

| ID | Configuration |
|---|---|
| **C0** | Fastest route, hazard-blind (OSRM baseline) |
| **C1** | Hard-avoid: any edge with any hazard report is removed |
| **C2** | CityPulse, confidence-weighted penalty, **no** decay (fixed confidence) |
| **C3** | **CityPulse full**: confidence-weighted penalty **with** hazard-class decay |
| **C4** | Oracle: routes computed with perfect hindsight knowledge of which edges were actually impassable |

Metrics:

1. **Hazard exposure** — sum over route edges of (hazard severity × edge length), and the
   binary **impassable-edge-hit rate** (fraction of routes that traverse an edge that was
   in fact impassable at that timestamp, per the replay ground truth). *This is the
   headline safety metric.*
2. **Detour ratio** — route length (and duration) ÷ C0 length (duration). Report the
   **full distribution**, not the mean; the tail is what users experience.
3. **Exposure-reduction efficiency** — Δ exposure per unit of added travel time. This
   single number is the fairest summary of the safety/speed trade-off and mirrors the
   framing in the existing "safest vs fastest" literature.
4. **Time-to-safety** — for evacuation-style OD pairs, time to reach the nearest
   above-threshold-elevation shelter/safe node.
5. **Optimality gap vs. oracle** — (C_x exposure − C4 exposure) / (C0 exposure − C4
   exposure). Shows how much of the achievable benefit you actually captured.
6. **False-avoidance cost** — travel time wasted avoiding edges that were passable. The
   metric that keeps you honest about over-reacting to stale reports; **C2 vs C3 on this
   metric is the entire justification for the decay function.**

### 6.4 Study 3 — Explanation quality (two parts: automatic, then human)

**Part A — faithfulness (automatic, cheap, and the part reviewers respect most).**
Emit a structured decision trace per route: `{edges_penalised, hazard_type, report_age,
confidence, cost_delta, alternative_rejected}`. Then decompose each generated explanation
into atomic factual claims and check each against the trace. Report:
- **Faithfulness rate** = supported claims / total claims.
- **Hallucination rate** = claims contradicted by or absent from the trace.
- **Coverage** = fraction of the top-k decisive trace facts mentioned in the explanation.
Run on ≥ 300 routes, for both the cloud model and the on-device quantized model. **The
cloud-vs-edge faithfulness gap is a publishable result in itself and is exactly the
number that supports claim §3.2.** Have two annotators independently decompose a 50-route
subsample and report **Cohen's κ**.

**Part B — human study (see §6.6).**

### 6.5 Study 4 — Offline degradation and latency/throughput benchmarking

This is the study that substantiates the project's actual novelty, so do not shortchange
it.

**Degradation matrix.** Define connectivity states and measure everything in each:
`FULL_CLOUD` → `DEGRADED` (high latency / lossy, e.g. 500 ms RTT, 5 % loss, 200 kbps) →
`OFFLINE_FRESH` (no network, cache < 5 min old) → `OFFLINE_STALE` (cache 1 h) →
`OFFLINE_VERY_STALE` (cache 6 h / 24 h). Use `tc netem` to shape the network rather than
toggling airplane mode manually — it is reproducible.

For each state report: route computed at all? (yes/no), route quality vs. the
online-optimal route (all §6.3 metrics), explanation produced? faithfulness rate,
**confidence value displayed vs. the confidence that was actually warranted** (this is a
*calibration* experiment — plot displayed confidence against observed correctness in
decile bins and report **expected calibration error**; a well-calibrated stale-data
warning is a genuinely novel artifact).

**Latency/throughput.** Report on **real target hardware** (name the phones; include at
least one ₹10–15k Android device — a Chennai civic-resilience system evaluated only on a
flagship is not credible):
- Route computation: p50/p95/p99 latency, cold vs warm cache.
- On-device LLM: **time-to-first-token**, **tokens/sec**, total explanation latency, peak
  RAM, model size on disk, **battery drain per 100 explanations**, and thermal throttling
  behaviour over a sustained 20-minute run.
- Backend: FastAPI ingest throughput (reports/sec) and end-to-end signal-to-route-weight
  propagation latency at p95.
- Storage footprint of the pre-cached spatial graph for the Chennai extract.

**Feasibility note the team must confront now, in week 1, not week 5:** current sub-3B
quantized models are the realistic on-device option, and on mid-range Android hardware you
should expect roughly single-digit-to-low-tens tokens/sec, with significant time-to-first-
token on a cold start. If a "why this route" explanation is 60 tokens, that is survivable;
if the design calls for a paragraph, it is not. **Constrain the explanation to ≤ 2
sentences and benchmark on the cheap phone in week 2.** Also budget 1–3 GB of device
storage for model + graph and check it against the demo devices.
([Artificial Analysis — benchmarking small models on phones](https://artificialanalysis.ai/articles/mobile-phone-intelligence-inference),
[Optimizing LLMs using quantization for mobile execution](https://arxiv.org/html/2512.06490v1),
[Qualcomm Llama-3.2-1B mobile deployment](https://huggingface.co/qualcomm/Llama-v3.2-1B-Instruct))

### 6.6 Study 5 — Human-subject study (trust and understandability)

**Design.** Within-subjects, scenario-based, counterbalanced. Each participant sees the
same 6–8 routing scenarios (2 clear-cut hazard, 2 ambiguous/stale-evidence, 2
conflicting-evidence, 2 no-hazard control) under **three explanation conditions**:
- **E0** — route only (map + ETA), no explanation.
- **E1** — template explanation ("Avoiding Mount Road: flooding reported").
- **E2** — CityPulse generated explanation with explicit confidence and evidence age.

Counterbalance condition order (Latin square) and randomise scenario order.

**Sample size.** For a within-subjects design targeting a medium effect (d ≈ 0.5) at
α = .05, power .80, you need roughly **n ≈ 34 completing participants**; recruit **40–45**
to absorb dropouts and attention-check failures. **n = 40 within-subjects is defensible
at ITSC/ISCRAM/COMPASS. n = 12 is not, and n = 200 is not achievable in 7 weeks.** Do not
recruit only CS students from your own lab; stratify to include at least a third
non-technical participants and report the demographic table.

**Instruments (use validated scales; do not invent your own Likert items).**
- **Trust:** Jian, Bisantz & Drury (2000) *Checklist for Trust between People and
  Automation* — 12 items, 7-point. Note in the limitations that the scale has a
  documented **positive-response bias** (Gutzwiller et al., 2019); report item-level
  results, not just the mean.
  ([Jian et al. — DTIC PDF](https://apps.dtic.mil/sti/tr/pdf/ADA395339.pdf),
  [journal version](https://www.tandfonline.com/doi/abs/10.1207/S15327566IJCE0401_04),
  [positive-bias critique](https://journals.sagepub.com/doi/10.1177/1071181319631201))
- **Usability:** System Usability Scale (10 items) — standard, fast, comparable.
- **Workload:** NASA-TLX (raw TLX is acceptable and faster).
- **Understandability / explanation satisfaction:** adapt the explanation-quality
  constructs used in the LLM-explanation literature (transparency, satisfaction,
  sufficiency) — cite the Frontiers 2024 review rather than inventing items.
- **Behavioural measures (stronger than self-report — include them):** (a) **route
  acceptance rate** per condition; (b) **appropriate reliance** — does the participant
  *reject* the recommendation when the explanation discloses low confidence / stale
  evidence? This is the key measure: a good confidence display should *lower* trust when
  the evidence is bad. A system that increases trust uniformly is miscalibrating users,
  and saying so in the paper will read as rigour, not failure.
- **Decision time** per scenario.

**Analysis.** Repeated-measures ANOVA or Friedman (report normality checks), Holm
correction for multiple comparisons, effect sizes (η²ₚ / Kendall's W) alongside p-values.

**Ethics / IRB at an Indian university.** Do this in **week 1–2**; approval latency is the
most common cause of a cancelled user study.
- Route the protocol through VIT's **Institutional Ethics Committee / Institutional
  Review Board**. Even though this is not biomedical research, Indian IECs generally
  assess social and behavioural research against the **ICMR *National Ethical Guidelines
  for Biomedical and Health Research Involving Human Participants* (2017)**, which has a
  dedicated section on social and behavioural sciences research.
  ([ICMR guidelines PDF](https://ethics.ncdirindia.org/asset/pdf/ICMR_National_Ethical_Guidelines.pdf),
  [ICMR ethics portal](https://ethics.ncdirindia.org/icmr_ethical_guidelines.aspx),
  [IJMR commentary](https://ijmr.org.in/national-ethical-guidelines-for-biomedical-health-research-involving-human-participants-2017-a-commentary/))
- Prepare: a plain-language **participant information sheet in Tamil and English**,
  written informed consent, statement of voluntary withdrawal, data-minimisation plan, and
  an anonymisation/retention plan.
- **DPDP Act 2023 considerations:** if any location data is collected, collect the
  minimum, obtain specific purpose-bound consent, and state the retention period. For the
  lab study, **use scripted scenarios on pre-recorded map states — do not collect
  participants' real location traces.** This removes almost all the ethics risk at almost
  no scientific cost.
- **Safety framing:** the study is hypothetical scenario judgement, not live navigation.
  Put in writing (and in the consent form) that the system is a research prototype and
  must not be used for real emergency decisions. **Do not run any on-road study.**

### 6.7 Seven-week schedule (evaluation activities only)

| Week | Evaluation work |
|---|---|
| 1 | Freeze OSM extract; start incident-corpus collection; **submit IEC application**; benchmark a candidate quantized model on the cheapest target phone (feasibility gate). |
| 2 | Incident corpus to ≥ 100 events; define + commit metric definitions (§6.3); build the OD sampler; `tc netem` harness. |
| 3 | Corpus complete (≥ 200); implement decision-trace emission; pilot the human-study protocol with 4–5 people, fix the instrument. |
| 4 | Run Study 1 (replay) across C0–C4; build the SUMO sub-network. |
| 5 | Run Study 2 (SUMO); run Study 4 (offline degradation + latency, all devices). |
| 6 | Run Study 3A (faithfulness, 300 routes, 2 annotators on subsample); **run Study 5 (n≈40)**. |
| 7 | Analysis, calibration plots, write-up, reproducibility package (pinned extract, seeds, scripts, corpus). |

**If time collapses, cut in this order:** Haven Mode evaluation (cut first, and cut the
feature), then SUMO (Study 2), then reduce the human study to n = 25 and report it as a
pilot with effect-size estimates for a future study. **Never cut Study 1 or Study 4** —
those two carry the entire novelty claim.

---

## 7. Venue shortlist

| Venue | Type | Scope fit | Demandingness | Verdict |
|---|---|---|---|---|
| **ACM SIGSPATIAL — ARIC workshop** (Int'l Workshop on Advances in Resilient and Intelligent Cities) | Workshop, co-located with SIGSPATIAL | **Excellent** — resilient cities, spatial data, hazard + urban infrastructure | Moderate; workshop acceptance is far more forgiving than the main track | **Best scope fit — but VERIFY IT IS STILL RUNNING.** I could confirm editions 1–5 (2018–2022, 5th at Seattle, Nov 2022) but found **no 2024/2025 edition**. Check the current SIGSPATIAL workshop list before planning around it. ([ARIC 2021](https://urbands.github.io/ARIC2021/), [ARIC 2020](https://urbands.github.io/aric2020/), [ARIC 2022 report](https://doi.org/10.1145/3632268.3632272)) |
| **ACM SIGSPATIAL — GeoAI workshop** | Workshop | **Very good** and **confirmed active** (7th edition, ORNL-organised) | Moderate | **Live fallback for ARIC.** The on-device-LLM-for-geospatial-explanation angle fits GeoAI well. ([GeoAI 2025](https://events.ornl.gov/acmsigspatial-geoai2025/), [workshop series](https://geoai.ornl.gov/acmsigspatial-geoai/), [SIGSPATIAL 2025 workshops](https://sigspatial2025.sigspatial.org/workshop/)) |
| **ACM SIGSPATIAL — Applications Papers track** | A-tier conference, **separate track** | **Very good** — this track exists precisely for deployed/applied systems rather than new algorithms | High but **judged on deployment value, not algorithmic novelty** | **Better main-conference route than the research track** given §3.1. Read this CFP carefully — it is the most under-used option on this list. ([Applications Papers CFP](https://sigspatial2025.sigspatial.org/application-submission/)) |
| **ACM SIGSPATIAL research track** | A-tier conference | Excellent scope | **High** — expects strong spatial-algorithmic novelty and large-scale evaluation | Stretch goal only. The §3.1 prior art will be held against you hard here; prefer the Applications track. ([Research CFP](https://sigspatial2025.sigspatial.org/research-submission/)) |
| **IEEE ITSC** (Intelligent Transportation Systems Conference) | Large annual IEEE conference | **Very good** — routing, ITS, emergency vehicles; SUMO results land well | Moderate; broad and relatively accessible, high volume | **Strong second target**, especially if Study 2 (SUMO) succeeds. |
| **ISCRAM** (Information Systems for Crisis Response and Management) | Specialist conference | **Excellent** — the natural home for crowdsourced crisis data, PetaBencana-lineage work, and the human/trust study | Moderate; values deployment realism and field grounding over algorithmic novelty | **Strong target** — and the community most likely to give useful, expert feedback. ([ISCRAM proceedings](https://www.resurchify.com/impact/details/21100802691)) |
| **ACM COMPASS** (Computing and Sustainable Societies) | Conference (SIGCAS) | **Good** — ICTD/civic-tech framing, Global South deployments | Moderate–high; reviewers demand genuine community engagement and are hostile to "parachute" tech | Good fit **only if** you do real Chennai stakeholder engagement. Do not submit a lab-only prototype here. ([COMPASS](https://www.resurchify.com/impact/details/21100869825)) |
| **IEEE Access** | Open-access journal | Broad | Low–moderate bar, fast turnaround, **APC applies** | Reasonable fallback for a complete systems paper. Lower prestige; some committees discount it. |
| **Elsevier IJDRR** (Int'l Journal of Disaster Risk Reduction) | Journal | **Very good** — disaster risk reduction, flooding, resilience | Moderate–high; expects DRR framing, not just engineering | Good journal target after conference feedback. |
| **Elsevier Sustainable Cities and Society** | Journal | Good — urban resilience, smart cities | **High** — very high impact factor, highly selective, long review cycles | Not realistic as a first submission from a 7-week project. Consider for an extended version much later. ([SCS journal profile](https://www.letpub.com/journal-selector/journal/10255), [Scimago](https://www.scimagojr.com/journalsearch.php?q=19700194105&tip=sid)) |

**Recommended sequence:** ARIC/GeoAI workshop (or ISCRAM) first for feedback → extend with
the human study and SUMO results → ITSC or the **SIGSPATIAL Applications Papers track** →
IJDRR for the journal version.

**One warning on venue choice.** Several of the "easy" options in this space are
predatory or near-predatory, and a student paper in one of them is worse than no paper.
Stick to the venues above; if someone proposes a venue not on this list, check it against
the ACM/IEEE official conference listings and Scopus/DBLP indexing before paying anything.

---

## 8. Blunt summary of risks

1. **The deck's novelty claim, as written, will not survive a knowledgeable reviewer.**
   IBM filed flood-aware routing in 2011; Uber holds a live patent on time-varying
   risk-weighted routing; Waze already decays crowdsourced reports; OsmAnd has routed
   offline for 15 years.
2. **TomTom, Google Flood Hub and TN-ALERT are missing from the competitive slide** and
   all three are materially stronger than the competitors that are on it. **TN-ALERT is
   the worst omission** — it is a Tamil Nadu government flood-alert app with 500k+
   installs, updated October 2025, in the project's exact pilot geography. Fix this
   before any external presentation.
3. **"Waycare" has not existed as an independent company since 2021.**
4. **Haven Mode should be cut.** Least novel, least evaluable, most privacy- and
   safety-exposed.
5. **The explanation could be a rationalization rather than an explanation.** Without a
   decision-trace-grounded faithfulness measurement, the core demo is a language model
   writing plausible sentences about a route it did not compute. Measure it (§6.4).
6. **On-device LLM feasibility is an unvalidated week-5 assumption sitting under the
   project's only real novelty claim.** Benchmark a quantized model on the cheapest target
   phone in **week 1**. If it fails, the project pivots to templated explanations with
   confidence disclosure — which is still publishable, but only if you find out in week 1.
7. **The ethics application is on the critical path for the user study.** File in week 1.

---

## 9. Verified sources

All URLs retrieved 2026-09-12. No citation in this report is invented; where a source was
a search-result listing rather than a fetched page, the claim is hedged accordingly in the
text.

**Competitors**
1. PulsePoint Respond — https://www.pulsepoint.org/pulsepoint-respond
2. PulsePoint responder types & features — https://www.pulsepoint.org/responder-types-and-features
3. PulsePoint NEAR AED registry — https://www.pulsepoint.org/pulsepoint-aed
4. Google Flood Forecasting (Flood Hub) — https://sites.research.google/gr/floodforecasting/
5. Google Flood Forecasting API — https://developers.google.com/flood-forecasting
6. Flood Hub email subscriptions — https://support.google.com/flood-hub/answer/16499229?hl=en
7. Flood forecasting extended to all of India and Bangladesh — https://indiaai.gov.in/news/google-s-flood-forecasting-initiative-extends-to-the-whole-of-india-and-bangladesh
8. Rekor Systems to acquire Waycare Technologies — https://www.rekor.ai/post/rekor-systems-to-acquire-waycare-technologies-ltd
9. Rekor to acquire Waycare for $61m (ITS International) — https://www.itsinternational.com/its5/its8/news/rekor-acquire-waycare-61m
10. Waze — report bad weather (flood/fog/ice report types, report expiry) — https://support.google.com/waze/answer/13809605?hl=en
11. Google Maps crisis-related alerts — https://support.google.com/maps/answer/9985621?hl=en
12. Google Maps SOS Alerts: rapid flood maps — https://support.google.com/maps/answer/12492235?hl=en
13. TomTom Hazard Warnings — https://www.tomtom.com/products/hazard-warnings/
14. TomTom Hazards, Connected Services API — https://developer.tomtom.com/connected-services-api/contents/hazards
15. TomTom Traffic Incidents service — https://docs.tomtom.com/traffic-api/documentation/tomtom-maps/traffic-incidents/traffic-incidents-service

**Civic alert / India**
16. NDMA Sachet — download & national disaster alert portal — https://sachet.ndma.gov.in/DownloadMobileApp
17. Sachet (app) overview — https://en.wikipedia.org/wiki/Sachet_(app)
18. IMD Damini lightning alert — https://web.umang.gov.in/landing/department/damini-lightning-alert.html
19. Damini launch, IITM — https://www.tropmet.res.in/118-prjct_news
20. FEMA mobile products — https://www.fema.gov/about/news-multimedia/mobile-products
21. Zello download surge during Hurricane Irma — https://gulfnews.com/world/americas/walkie-talkie-app-downloads-soar-as-irma-looms-1.2087393
22. IIT Madras crowdsourcing to track Chennai waterlogging — https://news.careers360.com/iit-madras-enables-crowdsourcing-track-waterlogging-in-chennai/amp
23. Google Personal Safety app — https://play.google.com/store/apps/details?id=com.google.android.apps.safetyhub&hl=en_US
24. Android emergency help / crisis alerts — https://support.google.com/android/answer/9319337?hl=en
24a. **TN-ALERT (TN-SMART client, RIMES / Govt. of Tamil Nadu)** — https://play.google.com/store/apps/details?id=int_.rimes.tnsmart&hl=en_IN
24b. TN-SMART mobile app, Tiruchirappalli district (Govt. of Tamil Nadu) — https://tiruchirappalli.nic.in/revenue-department/tn-smart-mobile-app/
24c. TN-Alert on the App Store — https://apps.apple.com/in/app/tn-alert/id1559849577
24d. Namma Chennai (GCC Public Grievance Redressal System) — https://play.google.com/store/apps/details?id=com.ceedeev.grivenancev2&hl=en
24e. Tamil Nadu State Disaster Management Authority — https://en.wikipedia.org/wiki/Tamil_Nadu_State_Disaster_Management_Authority

**Academic / civic-tech prior art**
25. PetaBencana.id — OECD/OPSI case study — https://oecd-opsi.org/wp-content/uploads/2019/07/PetaBencana.id_Indonesia_2013.pdf
26. PetaJakarta.org white paper (University of Wollongong) — https://documents.uow.edu.au/content/groups/public/@web/@smart/documents/doc/uow200106.pdf
27. Rest of World — "Hi, I'm Disaster Bot" (PetaBencana) — https://restofworld.org/2021/hi-im-disaster-bot/
28. Human-centered flood mapping and intelligent routing (gauge + crowdsourced street photos) — https://www.sciencedirect.com/science/article/abs/pii/S1474034622001884
29. Web-based DSS for road network accessibility during flooding — https://link.springer.com/article/10.1007/s44212-024-00040-0
30. Evacuation routing for dam-failure flooding (coupled flood–road model) — https://www.mdpi.com/2076-3417/15/8/4518
31. Dynamic simulation framework: urban flooding impacts on transportation — https://link.springer.com/article/10.1007/s13753-026-00697-y
32. RL-based routing for large street networks (IJGIS) — https://www.tandfonline.com/doi/full/10.1080/13658816.2023.2279975
33. Real-time safest route identification: safest vs fastest trade-off — https://www.researchgate.net/publication/370206539_Real-time_safest_route_identification_Examining_the_trade-off_between_safest_and_fastest_routes
34. Route-The Safe: safest route prediction from crime & accident data — https://www.researchgate.net/publication/338096313_Route-The_Safe_A_Robust_Model_for_Safest_Route_Prediction_Using_Crime_and_Accidental_Data
35. Danger by design? Safe route choices in Tshwane — https://link.springer.com/article/10.1007/s12198-026-00363-w
36. Constraint-aware route recommendation from natural language via hierarchical LLM agents — https://arxiv.org/html/2510.06078
37. On explaining recommendations with LLMs: a review — https://www.frontiersin.org/journals/big-data/articles/10.3389/fdata.2024.1505284/full
38. Establishing Trust in Crowdsourced Data — https://arxiv.org/html/2511.03016v1
39. Evaluating trust in user-data networks: what can we learn from Waze? — https://ws-dl.blogspot.com/2022/01/2022-01-18-evaluating-trust-in-user.html
40. Context-aware travel time prediction & route optimization survey — https://doi.org/10.3390/futuretransp6030119

**Offline navigation**
41. Using Google Maps without an internet connection (offline limits) — https://www.howtogeek.com/how-to-use-google-maps-without-an-internet-connection/
42. Organic Maps review (offline routing) — https://privacygear.nl/en/reviews/organic-maps-review/
43. OsmAnd review (advanced offline navigation on OSM) — https://privacygear.nl/en/reviews/osmand-review/

**Patents (Google Patents)**
44. US20130116920A1 — Flood aware travel routing (IBM, abandoned) — https://patents.google.com/patent/US20130116920
45. US10563994B2 — Safe routing for navigation systems (Uber, active) — https://patents.google.com/patent/US10563994B2/
46. US10074139B2 — Route risk mitigation — https://patents.google.com/patent/US10074139B2/en
47. US10309792B2 — Route planning for an autonomous vehicle — https://patents.google.com/patent/US10309792B2/en
48. US20170158191A1 — Vehicle assisted response to road conditions — https://patents.google.com/patent/US20170158191
49. US6577950B2 — Route guiding explanation device and system — https://patents.google.com/patent/US6577950
50. US5181250A — NLG system for producing natural language instructions — https://patents.google.com/patent/US5181250
51. US7693653B2 — Vehicle routing and path planning — https://patents.google.com/patent/US7693653B2/en

**Evaluation methodology**
52. SUMO — Simulation of Urban MObility: an overview — https://www.researchgate.net/publication/225022282_SUMO_-_Simulation_of_Urban_MObility_An_Overview
53. SUMO modelling to optimize emergency vehicle arrival time — https://www.tib-op.org/ojs/index.php/scp/article/view/225
54. SUMO-based evaluation of road incidents' impact — https://e-space.mmu.ac.uk/600548/2/goSMART%20paper.pdf
55. Jian, Bisantz & Drury — Foundations for an empirically determined scale of trust in automated systems (DTIC PDF) — https://apps.dtic.mil/sti/tr/pdf/ADA395339.pdf
56. Jian et al. — journal version (Int. J. Cognitive Ergonomics 4(1)) — https://www.tandfonline.com/doi/abs/10.1207/S15327566IJCE0401_04
57. Gutzwiller et al. — Positive bias in the Trust in Automated Systems Survey — https://journals.sagepub.com/doi/10.1177/1071181319631201
58. HRI Scale Database — Trust in Automation scales — http://hriscaledatabase.psychology.gmu.edu/trust/2025/02/20/TIA.html
59. ICMR National Ethical Guidelines for Biomedical and Health Research Involving Human Participants (PDF) — https://ethics.ncdirindia.org/asset/pdf/ICMR_National_Ethical_Guidelines.pdf
60. ICMR ethical guidelines portal — https://ethics.ncdirindia.org/icmr_ethical_guidelines.aspx
61. IJMR commentary on the 2017 ICMR guidelines — https://ijmr.org.in/national-ethical-guidelines-for-biomedical-health-research-involving-human-participants-2017-a-commentary/
62. Artificial Analysis — benchmarking small models and mobile phones — https://artificialanalysis.ai/articles/mobile-phone-intelligence-inference
63. Optimizing LLMs using quantization for mobile execution — https://arxiv.org/html/2512.06490v1
64. Qualcomm Llama-3.2-1B-Instruct optimized for mobile deployment — https://huggingface.co/qualcomm/Llama-v3.2-1B-Instruct

**Venues**
65. ARIC 2021 (ACM SIGSPATIAL workshop on Advances in Resilient and Intelligent Cities) — https://urbands.github.io/ARIC2021/
66. ARIC 2020 — https://urbands.github.io/aric2020/
66a. ARIC 2022 workshop report (5th edition, SIGSPATIAL Special) — https://doi.org/10.1145/3632268.3632272
66b. ACM SIGSPATIAL GeoAI 2025 workshop — https://events.ornl.gov/acmsigspatial-geoai2025/
66c. ACM SIGSPATIAL GeoAI workshop series — https://geoai.ornl.gov/acmsigspatial-geoai/
66d. ACM SIGSPATIAL 2025 workshops list — https://sigspatial2025.sigspatial.org/workshop/
66e. SIGSPATIAL 2025 Applications Papers track CFP — https://sigspatial2025.sigspatial.org/application-submission/
66f. SIGSPATIAL 2025 Research Papers CFP — https://sigspatial2025.sigspatial.org/research-submission/
67. ISCRAM proceedings profile — https://www.resurchify.com/impact/details/21100802691
68. ACM COMPASS proceedings profile — https://www.resurchify.com/impact/details/21100869825
69. Sustainable Cities and Society — journal profile — https://www.letpub.com/journal-selector/journal/10255
70. Sustainable Cities and Society — Scimago — https://www.scimagojr.com/journalsearch.php?q=19700194105&tip=sid
