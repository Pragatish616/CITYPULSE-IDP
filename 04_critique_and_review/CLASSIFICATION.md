# Classification of the code and the core idea

Source: specialist review S8 (deep review, October 2026). The summary is in `CLAUDE.md` §7.

### TRL definitions used
- **EU Horizon 2020 Work Programme, General Annex G:**
  - TRL 2: technology concept formulated
  - TRL 3: experimental proof of concept
  - TRL 4: technology validated in lab
  - TRL 5: technology validated in relevant environment
  - TRL 6: technology demonstrated in relevant environment
  - TRL 7: system prototype demonstration in operational environment
  - TRL 8–9: qualified and proven in operation
- **Cross-checked against NASA NPR 7123.1 (Appendix E):**
  - TRL 3: analytical and experimental critical-function proof-of-concept
  - TRL 4: component and/or breadboard validation in a laboratory environment
  - TRL 5: component and/or breadboard validation in a relevant environment
  - TRL 6: system/subsystem prototype demonstration in a relevant environment
- **What counts as what here:**
  - **Relevant environment:** live Chennai monsoon data on a ₹10–15k Android phone.
  - **Lab:** historical replay on a workstation.

### (a) `citypulse-IDP` (research repo)

| Component | TRL | Justification |
|---|---|---|
| `pulse_router` + `pulse_belief` | **4** | Validated as components on the full-scale real graph with a deterministic replay harness (byte-identical reruns) and an independent SciPy reproduction (100/100 paths). The data are historical with one timestamp, no depth and no negatives, so this is lab, not relevant environment. ALT is TRL 3 (toy-graph tests only, not integrated). |
| `pulse_explain` (Tier 0 + verifier) | **3–4** | The template and verifier are unit-validated with an adversarial suite. Robustness against real model output is unmeasured and has easy fail-open cases (C3). |
| Tier 1 / Tier 2 rewriters | **2–3** | Code written against the API; never executed. |
| Flutter client | **3** | Proof of concept: one fixed query in the host VM; cache, sync and rewriters not integrated; no device run (C2). |
| Server | **3** | API and in-memory store tested; workers unscheduled; feeds unverified live; never deployed. |
| **Whole system** | **3** | Critical functions are proven separately, but no integrated system has been demonstrated, even in the lab. |

- **Software maturity: research artifact** (a well-engineered research prototype). It is above "prototype": there are ADRs, contracts, about 290 tests, determinism checks and recorded negative results. It is below "MVP": no end-user can choose a route, submit a report or receive live data. It is not production: no deployment, no CI evidence, no device validation, no licence.
- **Architecture style:**
  - A modular monorepo with a **shared-core library architecture**, where one pure-Dart core has two consumers: in-process in Flutter, and as an AOT CLI for the Python harness.
  - The core follows **functional core / imperative shell**: pure fusion, cost and trace functions, with I/O kept at the edges.
  - The query runs as a **pipeline**: belief → pessimistic plug-in → cost → search → trace → NLG → verifier.
  - The client is **offline-first, thick-client and local-first**: SQLite/R*-tree cache plus outbox.
  - The server is **thin event-sourced ingest**: an append-only observation log with G-Set dedup and SSE pub/sub, plus a repository (ports-and-adapters) pattern for memory or PostGIS.
  - The evaluation layer is **batch scripts** around a subprocess CLI.

### (a) `citypulse-ai` (Kotlin)
- **TRL 2** (concept formulated and illustrated). It does not reach TRL 3: the "experiment" runs on a 27-node hand-made graph with invented priors, hard-coded confidence (94/88), a misattributed slowdown curve and a templated "SLM".
- **Maturity: UI/design mock-up (demo prototype)**, generated with an AI app builder (`metadata.json` declares `MAJOR_CAPABILITY_SERVER_SIDE_GEMINI_API`; the handoff doc is an agent transcript).
- **Architecture: single-module Android MVVM.** Compose UI, a ViewModel, a Repository, Room, and singleton `object` engines. The data layer is fixtures compiled into code.

### (b) The core idea

**Contribution type: primarily systems integration with an application case study.** It also has a modest modelling and analysis component.
- **Not a new algorithm.** Bidirectional Dijkstra and ALT are textbook. ALT's correctness under increasing weights is Delling & Wagner 2007.
- **Not a new model.**
  - Log-odds fusion follows the occupancy-grid tradition.
  - The pessimistic plug-in is a one-sided Wald/UCB band.
  - Separating slowdown from harm, and the "confidence-multiplied penalties are risk-seeking under ambiguity" argument, are useful modelling points but small.
  - Proposition 2 (the 1+λs cap) is an elementary but practically important bound.
- **Not a dataset or benchmark.** The 6,132-observation corpus is derived from OpenCity layers, has one timestamp, and has no labels independent of the belief. The deterministic replay harness could be released as a minor artifact.
- **HCI** is a stated future component (confidence UI, ADR-011 disclaimers, the Study 5 human study) with no results yet.
- **The publishable core** is the *combination*: offline belief-aware routing, a fail-closed explanation contract and an honest replay evaluation on a real city graph. This is an applied systems / ICT4D paper, not an algorithms paper.
- **Venue fit:** ACM COMPASS, ACM SIGSPATIAL (short or demo), IEEE ITSC or GHTC, ISCRAM.

**ACM CCS 2012 concepts** (best-effort paths):
- Applied computing → Operations research → Transportation *(primary)*
- Information systems → Information systems applications → Spatial-temporal systems → Geographic information systems / Location based services
- Theory of computation → Design and analysis of algorithms → Graph algorithms analysis → Shortest paths
- Computing methodologies → Artificial intelligence → Knowledge representation and reasoning → Probabilistic reasoning
- Computing methodologies → Modeling and simulation → Model development and analysis → Uncertainty quantification
- Computing methodologies → Artificial intelligence → Natural language processing → Natural language generation
- Human-centered computing → Ubiquitous and mobile computing
- Social and professional topics → Computing / technology policy (secondary, for the DPDP and disaster-response context)

**Product category:**
- **Primary: civic tech / public-good resilience tool, delivered as a consumer navigation feature** (an offline flood-aware route explainer for residents). This is what the code does: a single user, the commuter class as default, open government data, no accounts or billing.
- **Credible second market: an emergency-services decision-support tool.** The z=2 emergency class and chance constraint fit, but nothing for dispatch, fleets or multi-vehicle routing exists.
- **B2B data API** (the council's fleet "passability API"): **not supported by any code.** The server exposes raw observations only. There is no edge-level passability product, SLA or traversal-silence ingestion.
- **As a stand-alone consumer navigation app:** it competes directly with Google Maps and Waze closures. It is defensible only through offline operation plus local Chennai data, which is the claim C2 shows is not yet built.
