# AGENT_HANDOFF_CITYPULSE_AI.md
# CityPulse AI — Chennai Flood-Safe Urban Navigation System
## Dense Agent Handoff Specification, Architecture Blueprint & Algorithm Manual

> **Classification:** Production Architecture Handoff & Technical Specification  
> **Target Audience:** Incoming Autonomous Coding Agents & Senior Android Engineers  
> **Repository Name:** `CityPulse AI`  
> **Application ID:** `com.aistudio.citypulse.hxqvlk`  
> **Platform & Runtime:** Android (Jetpack Compose, Kotlin 2.0+, Offline-First Edge Compute)  
> **Primary Design Theme:** High-Contrast Minimalist Light Mode (Botanical Emerald Green `#16A34A`, Crisp Pure White `#FFFFFF`, Charcoal Black `#000000`)

---

## 1. Executive Summary & Problem Space

### 1.1 The Urban Crisis in Chennai
During every northeast monsoon (October–December) and cyclonic weather system (e.g., Cyclone Michaung 2023, 2015 Chennai Floods), standard consumer navigation apps (Google Maps, Apple Maps, Waze) catastrophically fail commuters, delivery personnel, and first responders:
1. **Blind Routing:** Consumer GPS navigates strictly for **distance and travel time** ($\tau_0$). When a low-lying railway subway or basin is flooded, traditional maps see zero traffic congestion (because vehicles cannot enter) and continuously route approaching motorists into deep water traps.
2. **Subway Submersion Traps:** Critical railway grade separators across Chennai—including Ganesapuram (Vyasarpadi), Perambur Loco Works, Villivakkam, Thillai Ganga Nagar, Gengu Reddy (Egmore), and South Usman Road (T. Nagar)—sit 3 to 6 meters below grade. A 40-minute cloudburst submerges them under 50cm to 150cm of water, turning vehicles into floating hazards.
3. **Severe Connectivity Depletion:** In severe meteorological emergencies, cell towers flood or lose auxiliary diesel power. Navigation apps that rely on cloud servers display blank tiles, spinner locks, or fail to compute routes.
4. **Hallucinatory "AI Guidance":** Generative AI assistants deployed for disaster response frequently invent road conditions, misquote flood heights, or calculate nonsensical detours without grounded physical fact traces.

### 1.2 CityPulse AI Value Proposition
CityPulse AI replaces traditional fastest-path routing with **deterministic hazard-aware safe routing** engineered specifically for Chennai:
- **Safety Over Speed:** Explicitly penalties hazard exposure and sever impassable corridors under strict chance constraints.
- **Offline-First Autonomous Operation:** Operates 100% locally with zero internet connectivity using pre-compiled topological road graphs and terrain elevation priors ($l_0$).
- **Pessimism-Under-Uncertainty:** Uses a calibrated Bayesian risk dial ($z$) so that sparse or unverified data in a storm increases routing caution rather than false optimism.
- **Two-Tier Explainability with Fail-Closed Fact Auditing:** Generates clear dispatch briefs where every single metric (time added, km added, % hazard reduction, high-ground usage) is audited against a formal `DecisionFactSet`. Any numerical discrepancy or ungrounded claim triggers immediate fail-closed reversion to the Tier-0 deterministic template.

---

## 2. Conversation & Development History (Chronological Iterations)

| Iteration | Focus & Milestone | Key Decisions & Changes |
| :--- | :--- | :--- |
| **v0.1 — Inception** | Concept & Architectural Design | Established core Chennai road graph (Saidapet, Guindy, Velachery, T. Nagar, Central, Vyasarpadi, OMR). Defined mathematical models for Bayesian belief log-odds fusion and Dijkstra with hazard penalties. |
| **v0.2 — Local Data & DB** | Offline Persistence & Room Database | Configured AndroidX Room (`AppDatabase`, `HazardDao`, `HazardEntity`) with offline seeding of 6 GCC chronic waterlogging watchlist hotspots. Created `HazardRepository` with Kotlin Flow streams. |
| **v0.3 — Dual Routing Engine** | `PulseRouter` & Chance Constraints | Implemented simultaneous dual-route generation: (1) Naive Shortest Route vs. (2) CityPulse Hazard-Aware Route. Established 35cm subway and 60cm surface water chance-constraint severing ($100,000$s penalty). |
| **v0.4 — Symbolic Verification** | `SymbolicExplanationEngine` | Built Tier-0 deterministic template NLG and Tier-1 natural language briefing. Created regex-based symbolic fact verifier that audits all candidate numerals and enforces fail-closed guarantee against LLM hallucination. |
| **v0.5 — Visual Cartography** | Custom Canvas 2D Vector Map | Developed custom `InteractiveMapView` using `androidx.compose.foundation.Canvas`. Implemented isometric 3D architectural building footprints, animated water halos, coordinate projectors, and touch inspection. |
| **v0.6 — Design Overhaul** | High-Contrast Light Mode Refactor | Completely transitioned app theme from dark navy to crisp white (`#FFFFFF`), high-contrast black typography (`#000000`), and botanical emerald green (`#16A34A`). Redrew 3D buildings with white facades and green roofs. |
| **v0.7 — Presentation & PRD** | PRD, Pitch Script & Image Storyboard | Authored comprehensive PRD, 9-slide investor pitch script, and master 7-panel visual storyboard generation prompt. |
| **v0.8 — Agent Handoff & Packaging** | Clean Repository Archive & Specs | Generated comprehensive agent handoff specification and prepared GitHub-ready clean archive zip file. |

---

## 3. Technology Stack & Toolchain Specification

### 3.1 Core Environment & Build Platform
- **Operating System:** Linux (Cloud Container Environment)
- **Language:** Kotlin 2.0+ (100% Kotlin codebase, zero Java)
- **Gradle Version:** Gradle 8.13 (Kotlin DSL: `build.gradle.kts`, `settings.gradle.kts`)
- **Android Gradle Plugin (AGP):** 8.9.0
- **Compile SDK:** Android 36 (Android 15 / Vanilla Ice Cream)
- **Target SDK:** Android 36
- **Min SDK:** Android 24 (Android 7.0 Nougat — covering >95% of active devices)
- **JVM Target:** Java 11 bytecode compatibility (`JavaVersion.VERSION_11`)

### 3.2 Key Dependencies & Version Catalog (`gradle/libs.versions.toml`)
- **Compose BOM:** `2025.02.00`
- **UI Framework:** AndroidX Jetpack Compose with Material Design 3 (M3)
- **Activity Compose:** `androidx.activity:activity-compose:1.10.1`
- **Lifecycle & ViewModel:** `androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7`, `lifecycle-runtime-compose:2.8.7`
- **Local Database:** AndroidX Room `2.6.1` (`androidx.room:room-runtime`, `androidx.room:room-ktx`, `ksp(androidx.room:room-compiler)`)
- **Annotation Processor:** Google KSP (`com.google.devtools.ksp:2.0.21-1.0.27`)
- **Coroutines & Reactive Streams:** `org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.1`, `kotlinx-coroutines-android:1.10.1`
- **Networking & Serialization (Prepared):** Retrofit `2.11.0`, Moshi `1.15.2`, OkHttp `4.12.0`
- **Testing & JVM Simulation:** JUnit 4 (`4.13.2`), Robolectric (`4.14.1`), Roborazzi Compose (`1.40.1`), AndroidX Test Core/JUnit
- **Secret Management:** Secrets Gradle Plugin (`com.google.android.libraries.mapsplatform.secrets-gradle-plugin:2.0.1`) with `.env` / `.env.example` integration.

---

## 4. Complete Directory Hierarchy & Architectural File Map

```
/
├── metadata.json                                # Platform metadata (Name: "CityPulse AI", Server-Side Gemini capability)
├── settings.gradle.kts                          # Root project definition & repository configuration
├── build.gradle.kts                             # Top-level build configuration (plugins, repositories)
├── gradle.properties                            # JVM allocation (Xmx4g), non-transitive R, parallel build toggles
├── .env.example                                 # Sample environment variables for secrets plugin
├── .gitignore                                   # Standard Android git exclusion rules
├── gradle/
│   ├── libs.versions.toml                       # Centralized Version Catalog
│   └── wrapper/
│       └── gradle-wrapper.properties            # Gradle wrapper distribution configuration
├── app/
│   ├── build.gradle.kts                         # App module configuration, plugins, dependencies, signing configs
│   ├── proguard-rules.pro                       # ProGuard code shrinking & obfuscation rules
│   └── src/
│       ├── main/
│       │   ├── AndroidManifest.xml              # Manifest declaring application, activity, theme, and edge-to-edge
│       │   ├── java/com/example/
│       │   │   ├── MainActivity.kt              # Entry point activity, edge-to-edge, bottom bar navigation, top bar
│       │   │   ├── engine/
│       │   │   │   ├── PulseRouter.kt           # Dijkstra routing engine (naive vs hazard-aware), fact set builder
│       │   │   │   ├── BeliefFusionEngine.kt    # Bayesian log-odds fusion, temporal decay, pessimism variance model
│       │   │   │   └── SymbolicExplanationEngine.kt # Tier-0 deterministic NLG, Tier-1 SLM briefing, regex numeral verifier
│       │   │   ├── model/
│       │   │   │   └── Models.kt                # Immutable data classes: GeoPoint, RoadNode, RoadEdge, HazardObservation,
│       │   │   │                                # EdgeBelief, RiskProfile, RouteResult, DecisionFactSet, DecisionTrace, MapBuilding
│       │   │   ├── data/
│       │   │   │   ├── ChennaiGraphData.kt      # Complete topological graph: 18 nodes, 26 bi-directional edges, 6 hotspots
│       │   │   │   ├── ChennaiBuildingData.kt   # Architectural map buildings: heritage landmarks, tech parks, hospitals
│       │   │   │   ├── HazardRepository.kt      # Data layer bridging Room DAO, simulation scenarios, observation streams
│       │   │   │   └── local/
│       │   │   │       ├── AppDatabase.kt       # RoomDatabase definition (version = 1, exportSchema = false)
│       │   │   │       ├── HazardEntity.kt      # Room @Entity representing cached observations and watchlist spots
│       │   │   │       └── HazardDao.kt         # Room @Dao: Flow-based reactive queries, batch inserts, clearLiveHazards
│       │   │   └── ui/
│       │   │       ├── CityPulseViewModel.kt    # Single state container: CityPulseUiState, coroutine-backed actions
│       │   │       ├── screens/
│       │   │       │   ├── InteractiveMapView.kt # Custom Compose Canvas 2D map, building footprints, animated halos
│       │   │       │   ├── ExplanationView.kt   # Comparative route cards, decision trace facts, verified briefing badge
│       │   │       │   ├── WatchlistInspectorView.kt # Hotspot cards, live telemetry inspector, on-device hazard report modal
│       │   │       │   └── SimulationLabView.kt # Weather scenario selectors, risk profile dials, custom z-value slider
│       │   │       └── theme/
│       │   │           ├── Color.kt             # High-contrast palette: PrimaryGreen, SurfaceLight, TextPrimary, HazardCrimson
│       │   │           ├── Theme.kt             # Material 3 lightColorScheme binding
│       │   │           └── Type.kt              # Typography styles (Inter / Roboto font weights)
│       │   └── res/
│       │       ├── values/
│       │       │   ├── strings.xml              # app_name ("CityPulse AI"), UI text resources
│       │       │   ├── colors.xml               # XML color references for legacy system wrappers
│       │       │   └── themes.xml               # Base Android application window styles
│       │       ├── drawable/                    # Adaptive icon backgrounds and foreground vector assets
│       │       ├── mipmap-*/                    # Multi-density app launcher icons
│       │       └── xml/                         # Backup and data extraction security rules
│       └── test/
│           └── java/com/example/
│               ├── ExampleUnitTest.kt           # Basic host JVM test
│               ├── ExampleRobolectricTest.kt    # Full headless integration tests for beliefs, routing, and verification
│               └── GreetingScreenshotTest.kt    # Roborazzi screenshot verification test
```

---

## 5. Mathematical Models & Routing Algorithms (Exhaustive Formulation)

CityPulse AI is built on a rigorous, mathematically sound foundation combining Bayesian belief theory, traffic flow disruption physics, chance-constrained optimization, and deterministic verification.

```
       [ Static Terrain Prior l0(e) ]         [ Live Hazard Ingest / Room DB ]
                     │                                      │
                     │                           Observation age Δt, Category Tc
                     │                           Temporal Decay w_k = exp(-λ Δt)
                     ▼                                      ▼
             ┌────────────────────────────────────────────────────────┐
             │       Bayesian Log-Odds Fusion Engine                  │
             │       l(e,t) = l0(e) + Σ w_k · logit(α_k) · s_k        │
             │       Mean probability: p_bar = σ(l(e,t))              │
             └───────────────────────┬────────────────────────────────┘
                                     │
                     Effective observation mass N_eff
                     User Risk Dial z ∈ [0.2, 2.0]
                                     ▼
             ┌────────────────────────────────────────────────────────┐
             │       Pessimism-Under-Uncertainty Engine               │
             │       p_tilde = p_bar + z · sqrt(p_bar(1-p_bar)/(N+n0))│
             └───────────────────────┬────────────────────────────────┘
                                     │
            Disruption slowdown δ(p) = 1.0 + 3.2 · (p_tilde)^1.5
            Chance Constraint: Subway depth ≥ 35cm or p_tilde ≥ 0.85
                                     ▼
             ┌────────────────────────────────────────────────────────┐
             │       Chance-Constrained Dijkstra Routing (PulseRouter)│
             │       Edge Cost w(e,t) = Travel Delay + Risk Penalty   │
             │       Severed Edges (Cost ≥ 90,000s) Pruned From Graph │
             └───────────────────────┬────────────────────────────────┘
                                     │
             ┌───────────────────────┴────────────────────────────────┐
             ▼                                                        ▼
   [ Naive Shortest Route ]                              [ CityPulse Safe Route ]
             │                                                        │
             └───────────────────────┬────────────────────────────────┘
                                     │
                                     ▼
             ┌────────────────────────────────────────────────────────┐
             │       Symbolic Explanation & Fact Audit Engine         │
             │       Extracts DecisionFactSet (Δt, Δkm, % reduction)  │
             │       Generates Tier-0 Template + Tier-1 SLM Briefing  │
             │       Audits Numerals: Valid? ──YES──► Approved Brief  │
             │                                └──NO───► Revert Tier-0 │
             └────────────────────────────────────────────────────────┘
```

### 5.1 Static Terrain Elevation Prior ($l_0(e)$)
Every road edge $e \in E$ has a baseline log-odds of inundation based on physical geography, digital elevation models (DEM), and historical flood extents from 2015 and 2023:

$$p_0(e) = \sigma(l_0(e)) = \frac{1}{1 + e^{-l_0(e)}}, \quad l_0(e) = \ln\left(\frac{p_0(e)}{1 - p_0(e)}\right)$$

| Prior Classification (`TerrainPriorType`) | Prior Log-Odds $l_0$ | Prior Probability $p_0$ | Real-World Urban Feature |
| :--- | :---: | :---: | :--- |
| `EXTREME_DEPRESSION` | $+1.60$ | $\approx 83.2\%$ | Velachery Lake basin, Madipakkam low road, Perungudi marsh |
| `HIGH_FLOOD_PRONE` | $+0.85$ | $\approx 70.1\%$ | Vyasarpadi Ganesapuram Subway, Gengu Reddy Subway, T. Nagar Usman Rd |
| `MODERATE_PRONE` | $-0.40$ | $\approx 40.1\%$ | Saidapet low-level bridge, Adyar riverbank perimeter |
| `DEFAULT_URBAN` | $-1.80$ | $\approx 14.2\%$ | Standard storm-drained arterial roads (Anna Salai, Poonamallee High Rd) |
| `ELEVATED_RIDGE` | $-2.20$ | $\approx 9.9\%$ | Kathipara Flyover, Guindy Elevated Grade Separator, OMR Expressway |

### 5.2 Multi-Source Bayesian Log-Odds Fusion with Temporal Half-Life Decay
When live observation reports $k = 1, \dots, K$ arrive (from GCC sensors, traffic police, or crowd reports), their evidential weight decays exponentially over time according to their hazard category:

$$\Delta t_k = \max(0, t - t_k) \quad \text{[seconds]}$$

Each category $c$ possesses a characteristic half-life $T_c$. The decay rate constant is:

$$\lambda_c = \frac{\ln(2)}{T_c}$$

$$w_k(t) = \exp(-\lambda_c \Delta t_k) = \exp\left(-\frac{\ln(2)}{T_c} \Delta t_k\right)$$

| Hazard Category (`HazardCategory`) | Half-Life $T_c$ | Default Confidence $\alpha$ | Severe Blocking? | Physical Rationale |
| :--- | :---: | :---: | :---: | :--- |
| `FLASH_FLOOD_SURGE` | $45\text{ min}$ | $0.92$ | Yes | Fast run-off; recedes or breaches rapidly |
| `CHRONIC_WATERLOGGING` | $240\text{ min}$ ($4\text{ h}$) | $0.85$ | No | Low ground saturation; clears very slowly |
| `SUBWAY_INUNDATION` | $720\text{ min}$ ($12\text{ h}$) | $0.98$ | Yes | Underground depression; water remains trapped until pumps clear it |
| `FALLEN_TREE_DEBRIS` | $1440\text{ min}$ ($24\text{ h}$) | $0.90$ | No | Requires heavy municipal clearance equipment |
| `ROAD_COLLAPSE` | $2880\text{ min}$ ($48\text{ h}$) | $0.95$ | Yes | Structural culvert breach; requires civil engineering reconstruction |

The source confidence is mapped via logit transformation:

$$\text{logit}(\alpha_k) = \ln\left(\frac{\alpha_k}{1 - \alpha_k}\right)$$

The cumulative live evidence $\Delta l(e, t)$ and effective observation count $N_{eff}(e, t)$ are:

$$\Delta l(e, t) = \sum_{k \in \mathcal{O}(e)} w_k(t) \cdot \text{logit}(\alpha_k) \cdot s_k$$

$$N_{eff}(e, t) = \sum_{k \in \mathcal{O}(e)} w_k(t)$$

The fused log-odds and mean probability $\bar{p}(e, t)$ are:

$$l(e, t) = l_0(e) + \Delta l(e, t)$$

$$\bar{p}(e, t) = \sigma(l(e, t)) = \frac{1}{1 + e^{-l(e, t)}}$$

### 5.3 Pessimism-Under-Uncertainty (The Risk Dial $z$)
In an emergency disaster routing scenario, **ambiguity must be penalized**. If an edge has a high hazard prior but zero recent observations (i.e., $N_{eff} \approx 0$), the mean probability $\bar{p}$ has high variance. CityPulse AI models posterior parameter uncertainty using the sample variance of the Bernoulli estimator with $n_0 = 3.0$ virtual pseudo-counts from the terrain prior:

$$\text{Var}(p) = \frac{\bar{p}(e, t) \cdot (1 - \bar{p}(e, t))}{N_{eff}(e, t) + n_0}$$

The pessimistic probability of inundation $\tilde{p}(e, t)$ is computed by projecting along the upper confidence bound governed by the user's risk dial $z$:

$$\tilde{p}(e, t) = \text{clamp}_{[0.01, 0.99]}\left(\bar{p}(e, t) + z \cdot \sqrt{\text{Var}(p)}\right)$$

- **Commuter / Two-Wheeler:** $z = 0.2, \lambda_{risk} = 60\text{s}$ (Risk-tolerant; accepts moderate ambiguity).
- **Standard Car:** $z = 1.0, \lambda_{risk} = 180\text{s}$ (Balanced caution; avoids flooded subways and deep standing water).
- **Emergency Ambulance:** $z = 2.0, \lambda_{risk} = 420\text{s}$ (Pessimistic fail-safe; treats unverified low ground as impassable).

### 5.4 Empirical Depth-Disruption Speed Slowdown
Road waterlogging severely reduces transit speeds before complete impassability. Based on the empirical flood-depth vehicle velocity curve developed by **Pregnolato et al. (2017)**:

$$\delta(\tilde{p}) = 1.0 + 3.2 \cdot (\tilde{p}(e, t))^{1.5}$$

As $\tilde{p} \to 1.0$, the travel time on passable segments increases by a factor of $4.2\times$.

### 5.5 Chance-Constrained Edge Weighting & Dijkstra Formulation
Let $\tau_0(e) = \frac{L(e)}{v_0(e)}$ be the free-flow travel time. The routing cost $w_\lambda(e, t)$ combines delayed transit time and risk penalties:

$$w_\lambda(e, t) = \underbrace{\tau_0(e) \cdot \left[1 + \tilde{p}(e, t) \cdot (\delta(\tilde{p}) - 1)\right]}_{\text{Expected Travel Time with Slowdown}} + \underbrace{\lambda \cdot \tilde{p}(e, t) \cdot s_{mult} \cdot \left(\frac{\tau_0(e)}{60}\right)}_{\text{Subjective Hazard Disutility Penalty}}$$

where $s_{mult} = 2.2$ for subways/underpasses and $1.0$ for surface roads.

#### The Chance Constraint (Edge Severing Rule)
An edge is classified as **severed (impassable)** and assigned $w_\lambda(e, t) = 100,000\text{s}$ if:
1. `isSubwayOrUnderpass == true` and reported depth $d_{max} \ge 35\text{cm}$
2. `isSubwayOrUnderpass == true` and $\tilde{p}(e, t) \ge 0.85$
3. Surface road with active live evidence ($\Delta l > 0$) and $\tilde{p}(e, t) \ge 0.92$
4. Reported live depth $d_{max} \ge 60\text{cm}$

In `PulseRouter.runDijkstra()`, any edge with $w_\lambda(e, t) \ge 90,000\text{s}$ is skipped during neighbor relaxation, guaranteeing zero hazardous subway traversal in the computed safe route.

### 5.6 Two-Tier Symbolic Explanation Engine & Fail-Closed Fact Auditing
To prevent LLM hallucination and ensure 100% transparent dispatch rationales, the explanation pipeline operates in two distinct tiers:

1. **Tier-0 Deterministic Template NLG (`generateTier0Rationale`):**  
   Evaluates directly on-device in $<1\text{ms}$. Injects exact values from `DecisionFactSet` (time difference, distance difference, % hazard reduction, avoided chokepoints, high-ground km, $z$-value, confidence %).
2. **Tier-1 Natural Language Briefing (`generateTier1Briefing`):**  
   Constructs a natural language narrative suitable for voice dispatch or commuter notification.
3. **Symbolic Fact Verifier (`verifyExplanation`):**  
   Uses regex tokenization (`[-+]?\b\d+(?:\.\d+)?%?\b`) to extract **every single numerical token** from the candidate text. It compares each extracted number against the allowed set of ground-truth values in `DecisionFactSet` (within a $\pm 0.15$ floating point tolerance).
   - If **all** numbers match: Output is approved as `Tier-1 SLM (Symbolically Verified)`.
   - If **any** ungrounded number is found (e.g. invented "saving 45 minutes" or "99.9% safe"): **The engine fails closed**, rejects the candidate text, logs the flagged discrepancies, and reverts instantly to the Tier-0 deterministic template.

---

## 6. Detailed Module Breakdown & Source Code Reference

### 6.1 `com.example.model.Models.kt`
- `GeoPoint(lat: Double, lon: Double)`: Geographic coordinate container.
- `RoadNode(id, name, point, elevationMeters, isHighGround, areaZone)`: Topological graph vertex.
- `TerrainPriorType(label, priorL0, baseRiskDesc)`: Static risk enum.
- `HazardCategory(displayName, halfLifeMinutes, defaultAlpha, isSevereBlocking)`: Temporal decay enum.
- `RoadEdge(id, fromNodeId, toNodeId, roadName, lengthMeters, freeFlowSpeedKmh, terrainPrior, isSubwayOrUnderpass, isElevatedCorridor)`: Graph edge with computed `freeFlowTimeSeconds`.
- `HazardObservation`: Live observation entity with depth, confidence alpha, category, and timestamp.
- `EdgeBelief`: Full mathematical state of an edge ($l_0, \Delta l, \bar{p}, N_{eff}, \tilde{p}, \delta, w_\lambda$, isSevered).
- `RiskProfile`: Configuration holding $z$-dial and risk aversion constant $\lambda$.
- `RouteResult`: Path nodes, path edges, total distance, total time, average hazard %, severe count, high ground distance.
- `DecisionFactSet`: Grounded numeric fact set for symbolic verification.
- `DecisionTrace`: Audit log containing naive route, safe route, fact set, and verified explanations.
- `MapBuilding`: Footprint polygon container for 3D architectural rendering.

### 6.2 `com.example.engine.PulseRouter.kt`
- Implements Dijkstra's algorithm with a custom `PriorityQueue<PathStep>`.
- `computeNaiveRoute()`: Runs Dijkstra with weights $w(e) = \tau_0(e)$ (free-flow time only), simulating traditional naive GPS.
- `computeHazardAwareRoute()`: Runs Dijkstra with weights $w(e) = w_\lambda(e, t)$, pruning edges with cost $\ge 90,000$s.
- `createFactSet()`: Computes relative time delta, distance delta, hazard reduction %, identifies avoided chokepoints present in naive route but omitted in safe route.

### 6.3 `com.example.engine.BeliefFusionEngine.kt`
- `computeEdgeBeliefs()`: Batch iterates over all graph edges and groups observations.
- `computeSingleEdgeBelief()`: Executes log-odds summation, temporal exponential half-life decay, variance calculation, Pregnolato slowdown, and chance-constraint evaluation.

### 6.4 `com.example.engine.SymbolicExplanationEngine.kt`
- `generateTier0Rationale()`: Formats deterministic decision trace.
- `generateTier1Briefing()`: Produces readable natural language dispatch text.
- `verifyExplanation()`: Audits numerical tokens and enforces the fail-closed fallback to Tier-0.

### 6.5 `com.example.data.ChennaiGraphData.kt`
- Pre-compiled topological representation of Chennai's core urban grid:
  - 18 strategically positioned nodes covering North, Central, and South Chennai (Saidapet, Guindy, Velachery, T. Nagar, Central, Egmore, Vyasarpadi, Perambur, Adyar, OMR Tidel, Perungudi, Madipakkam, Tambaram, Mudichur, etc.).
  - 26 bi-directional edges (52 directed edges) with explicit tags for subways (`isSubwayOrUnderpass`) and elevated ridges (`isElevatedCorridor`).
  - Pre-seeded GCC flood hotspots (`CHENNAI_WATCHLIST`): Vyasarpadi Ganesapuram Subway, Velachery 100ft Bypass, Madipakkam Lake Road, Usman Road Subway, Perungudi Canal Corridor, Mudichur Low Basin.

### 6.6 `com.example.data.ChennaiBuildingData.kt`
- 26 landmark architectural polygons representing Chennai's iconic skyline:
  - Heritage landmarks: Ripon Building, Central Railway Station, Egmore Station, LIC Building, Kapaleeshwarar Temple.
  - Tech hubs: Tidel Park, Ascendas IT Park, Ramanujan IT City, Guindy Industrial Estate.
  - Institutional & transit: IIT Madras Campus, Anna University, Madras Medical College, Apollo Hospitals Greams Rd, Chennai Airport Domestic & International Terminals.

### 6.7 `com.example.data.local.AppDatabase.kt` & Room Layer
- SQLite database backing `HazardEntity`.
- `HazardDao`: Reactive queries returning `Flow<List<HazardEntity>>`, ensuring offline persistence across device reboots.

### 6.8 `com.example.ui.CityPulseViewModel.kt`
- Central MVVM coordinator holding `MutableStateFlow<CityPulseUiState>`.
- Reactive triggers:
  - Changes in origin/destination recalculate dual routes.
  - Selecting a weather scenario (`MONSOON_TORRENTIAL_SURGE`, `SUBWAY_CLOSURES_SPATE`, `CYCLONE_MICHAUNG_REPLAY`, `DRY_WEATHER_BASELINE`) updates Room DB, which re-emits through Flow and triggers real-time graph re-weighting.
  - Toggling offline mode updates graph priors to operate without network feeds.
  - Adjusting risk dials updates $z$ and immediately recalculates the safe route.

### 6.9 `com.example.ui.screens.*`
- `InteractiveMapView.kt`: High-performance custom 2D Canvas. Transforms GPS coordinates to canvas space, renders road line weights, draws 3D isometric building extrusions (white facades, black borders, green roofs), draws animated water hazard halos, and renders color-coded routes (Naive in dashed red/amber, Safe in solid green `#16A34A`).
- `ExplanationView.kt`: Dual-route comparison cards, fact-set breakdown chips, and SLM verification audit cards with fail-closed safety badge.
- `WatchlistInspectorView.kt`: Filterable GCC hotspot cards with real-time water depth gauges and modal citizen hazard report ingestion.
- `SimulationLabView.kt`: Weather scenario picker, vehicle profile selector, and manual risk dial slider.

---

## 7. UI/UX Design System Specification

### 7.1 Color Palette (`com.example.ui.theme.Color.kt`)
The UI strictly enforces a high-contrast minimalist light theme with botanical green accents:

```kotlin
val PrimaryGreen = Color(0xFF16A34A)       // Emerald Green (Primary actions, safe routes, active tabs)
val PrimaryGreenDark = Color(0xFF15803D)   // Dark Green (Borders, high-contrast badges)
val PrimaryGreenLight = Color(0xFFDCFCE7)  // Soft Light Green (Container fills, chip backgrounds)

val AppBackground = Color(0xFFFFFFFF)      // Pure White (Application canvas)
val SurfaceLight = Color(0xFFFFFFFF)       // Crisp White (Card surfaces, sheets, bottom nav)
val SurfaceCard = Color(0xFFF9FAFB)        // Subtle off-white (Nested sub-cards)
val SurfaceBorder = Color(0xFFE5E7EB)      // Neutral 200 (Clean divider lines)

val TextPrimary = Color(0xFF000000)        // Solid Black (Maximum legibility headings & values)
val TextSecondary = Color(0xFF374151)      // Charcoal 700 (Readable descriptions & subtitles)
val TextMuted = Color(0xFF6B7280)          // Neutral 500 (Footers, helper labels)

val HazardCrimson = Color(0xFFDC2626)      // Crimson Red (Severed subways, extreme flood warnings)
val WarningAmber = Color(0xFFD97706)       // Amber (Slowdown delays, moderate waterlogging)
```

### 7.2 Accessibility & Ergonomics
- All interactive controls have a minimum touch target size of **$48\text{dp} \times 48\text{dp}$**.
- Explicit `Modifier.testTag()` applied across tabs, inputs, and buttons (`nav_tab_map`, `nav_tab_explanation`, `nav_tab_watchlist`, `nav_tab_sim_lab`, `connectivity_status_badge`, `risk_profile_chip_*`, etc.).
- Complete Material 3 Edge-to-Edge compatibility using `enableEdgeToEdge()`, `statusBarsPadding()`, and `navigationBarsPadding()`.

---

## 8. Step-by-Step Instructions for the Incoming Coding Agent

When you inherit this codebase, follow these rules and operational procedures:

### 8.1 Build & Verification Workflow
1. **Compilation Check:** Always run `compile_applet` to verify compilation after any code edits.
2. **Local JVM Testing:** Run unit and Robolectric tests via `run_command` with:
   ```bash
   gradle :app:testDebugUnitTest
   ```
3. **DO NOT** attempt to use `adb`, Android emulators, or instrumented tests in `androidTest/`. They are strictly unsupported in this environment.
4. **Preserve Root Metadata:** Never remove `"MAJOR_CAPABILITY_SERVER_SIDE_GEMINI_API"` from `metadata.json`. Never change the `name` field in `metadata.json` without matching `app_name` in `strings.xml`.
5. **No Hardcoded API Keys:** If external APIs are added, use the Secrets Gradle Plugin via `.env` and `.env.example`.

### 8.2 Safe Code Extension Patterns
- **Adding Graph Nodes or Edges:**  
  Edit `ChennaiGraphData.kt`. Ensure coordinates fall within Chennai bounding box ($12.96^\circ - 13.12^\circ\text{N}$, $80.19^\circ - 80.29^\circ\text{E}$). Always assign realistic `TerrainPriorType` and set `isSubwayOrUnderpass = true` for rail grade separators.
- **Modifying Hazard Probabilities or Decay Rates:**  
  Edit `HazardCategory` enum in `Models.kt`. Ensure `halfLifeMinutes` aligns with civic drainage clearance timescales.
- **Extending Explanation Capabilities:**  
  If integrating cloud LLM calls (e.g. Gemini 1.5/2.0), always route candidate responses through `SymbolicExplanationEngine.verifyExplanation()`. Maintain the strict fail-closed contract that falls back to `generateTier0Rationale()` upon any discrepancy.

---

## 9. Verification & Test Suite Summary

The repository includes a dedicated Robolectric test suite in `app/src/test/java/com/example/ExampleRobolectricTest.kt`:
1. `read string from context`: Validates Android resources and app name string binding.
2. `test belief fusion log-odds and pessimism calculation`: Verifies that a 60cm waterlogging observation in Vyasarpadi subway elevates $\tilde{p} > 0.80$ and trips the chance-constraint severing flag.
3. `test pulse router avoids flooded subways`: Verifies that Dijkstra avoids the severed Vyasarpadi subway when routing from Chennai Central to Perambur, selecting an elevated safe bypass.
4. `test symbolic explanation engine verifies numbers and fails closed on hallucination`: Verifies that grounded numerical summaries pass Tier-1 verification, while ungrounded/hallucinated numerals (e.g., claiming 99.9% confidence or saving 45 minutes) fail closed to the Tier-0 template.

---

## 10. Conclusion & Production Readiness

CityPulse AI is fully operational, standalone, and compiles cleanly with zero external runtime server dependencies. It provides a blueprint for life-saving urban disaster navigation in coastal megacities vulnerable to monsoon deluge.
