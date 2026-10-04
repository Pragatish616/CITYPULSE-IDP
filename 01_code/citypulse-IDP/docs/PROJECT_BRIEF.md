# CityPulse AI — Project Brief (source of truth for research agents)

Academic context: credited university research project, VIT Chennai.
Team: Pragatish N, Ravi, Jyotish. 7-week build-to-demo timeline.

## One-line pitch
"One agent. Every threat. A route that explains itself."
A civic-resilience routing system that ingests live urban hazard signals, computes
hazard-aware routes, and explains each routing decision in natural language — and
that keeps working with zero network connectivity.

## Problem framing (from pitch deck)
1. Emergency vehicles lose time to avoidable delays (signals, congestion).
2. Hazard information (e.g. a flood report) exists but never reaches the driver
   heading toward it in time.
3. Every map gives a route; none explain *why* that route is the right one.

## Claimed differentiation vs. prior art
Competitors each solve one slice: PulsePoint (EMS/cardiac signals), Google Flood
Hub (historical + predictive flood data), Waycare et al. (fleet/enterprise risk
mapping). CityPulse claims the union: dynamic routing + offline-first LLM +
predictive personalized precaution.

## Architecture (as pitched)
Pipeline: INGEST -> ROUTE -> EXPLAIN -> PRESENT -> OFFLINE FALLBACK & SYNC.

Engine steps:
1. Ingest — live timestamped hazard signals from municipal sensors + crowdsourced
   reports, structured as geospatial data.
2. Decay score — signal trust degrades with age (2-min-old flood = max weight;
   3-hour-old unverified obstacle = low confidence).
3. Connectivity check — cloud LLM when online; edge fallback the moment the
   connection drops.
4. On-device inference — quantized local model + pre-cached spatial graphs
   generate route geometry AND natural-language explanations locally.
5. Confidence-flagged UI — explicit reliability indicators tied to cache recency.
6. Reconnect & sync — reconcile local edge decisions with the central server,
   updating the global hazard map for other users.

Offline resilience claims: on-device quantized fallback model; dynamic
confidence-decay scoring based on signal age; fully functional routing with zero
external connectivity.

## "Haven Mode" (predictive personalized precaution)
Learn (passively infer home/work/school/family locations from encrypted everyday
routing usage) -> Forecast (ingest predictive municipal hazard models: urban
flooding, storm tracks, extreme heat index, air quality) -> Score (live comparative
risk across the user's meaningful locations) -> Detect (flag when risk at current
location significantly exceeds a known accessible safe location) -> Recommend
(plain-language precaution alert with the same confidence-decay transparency) ->
Adapt (learn which recommendations the user acted on).

## Proposed stack (as pitched, not yet validated)
Flutter (cross-platform client) · FastAPI (async backend) · PostgreSQL/PostGIS
(spatial indexing) · OSRM or GraphHopper (routing engine) · Redis (live signal
buffering + decay calculations) · OpenStreetMap data (no proprietary map infra).

## Positioning
Built for one city, designed for every city; OSM-driven so it ports anywhere;
framed as civic infrastructure for climate volatility, urban flooding and
localized emergencies. Primary pilot geography is Chennai, Tamil Nadu, India.

## Core novelty claimed (Week 5 of timeline)
"Offline-resilient, confidence-aware routing module" + agentic natural-language
explanation of routing decisions.
