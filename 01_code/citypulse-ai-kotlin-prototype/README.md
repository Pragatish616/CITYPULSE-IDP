> **Archive / reference only (TRL 2).** This is an AI-generated Android UI mock-up with:
> - a 27-node toy graph;
> - a hard-coded confidence badge (94% online / 88% offline);
> - a slowdown curve wrongly attributed to Pregnolato;
> - a "Tier-1 SLM" that is only a second template.
> It is not evidence for the method. The real code is in `../citypulse-IDP/`. See `../../CLAUDE.md`.

# CityPulse AI — Chennai Flood-Safe Urban Navigation

[![Platform](https://img.shields.io/badge/Platform-Android-green.svg)](https://developer.android.com)
[![Kotlin](https://img.shields.io/badge/Kotlin-2.0+-blue.svg)](https://kotlinlang.org)
[![Compose](https://img.shields.io/badge/Jetpack%20Compose-M3-brightgreen.svg)](https://developer.android.com/jetpack/compose)
[![Architecture](https://img.shields.io/badge/Architecture-Offline--First%20MVVM-orange.svg)]()
[![License](https://img.shields.io/badge/License-MIT-purple.svg)]()

> **Hazard-aware urban routing for Chennai that keeps working and explaining decisions offline with confidence decay and pessimistic hazard fusion.**

---

## 🌧️ The Problem

During Chennai's monsoon season and extreme weather events (such as the 2015 floods and 2023 Cyclone Michaung), traditional consumer navigation systems catastrophically fail commuters:

- **Speed Over Safety:** Standard GPS navigates for shortest travel time. When key railway subways (Vyasarpadi, Ganesapuram, Usman Road) flood, navigation apps see zero traffic and route drivers into water traps.
- **Connectivity Blackouts:** Cellular infrastructure often collapses during severe storms, leaving server-dependent maps completely non-functional.
- **AI Hallucinations:** Unaudited AI routing recommendations invent flood statistics or hallucinate impassable detours.

---

## 🛡️ The CityPulse Solution

CityPulse AI is an **offline-first, hazard-aware routing engine** designed specifically for Chennai's terrain:

1. **Deterministic Hazard Routing:** Uses Dijkstra's algorithm augmented with dynamic flood penalties and strict chance constraints. Subways with $\ge 35\text{cm}$ standing water are automatically severed from routing calculations.
2. **Bayesian Belief Fusion with Temporal Half-Life Decay:** Incorporates historical terrain elevation priors ($l_0$) and fuses live multi-source observations (police alerts, GCC stormwater feeds, crowdsourced reports) with category-specific half-life decay.
3. **Pessimism-Under-Uncertainty:** Features an adjustable risk dial ($z$) allowing users (bikes, passenger cars, emergency ambulances) to penalize unverified or sparse hazard reports.
4. **Two-Tier Symbolic Explainability with Fail-Closed Fact Auditing:** Generates natural language dispatch rationales grounded in verified metrics (time added, km added, % hazard reduction). If candidate text contains any ungrounded numbers, the engine fails closed to a deterministic Tier-0 decision trace.
5. **Architectural 2D Vector Map:** A custom Jetpack Compose Canvas rendering real Chennai coordinates, isometric 3D building landmarks (white facades, green roofs), elevated safe corridors, and animated water hazard halos.

---

## 🎨 Design System

CityPulse AI features a **High-Contrast Minimalist Light Theme**:
- **Canvas & Surfaces:** Crisp Pure White (`#FFFFFF`) with subtle borders (`#E5E7EB`)
- **Typography:** High-contrast Charcoal Black (`#000000` / `#374151`)
- **Safe Pathways & Action Accents:** Botanical Emerald Green (`#16A34A`) & Container Green (`#DCFCE7`)
- **Hazard Identifiers:** Crimson Red (`#DC2626`) for severed roads, Amber (`#D97706`) for cautionary waterlogging

---

## 📱 Navigation Tabs

1. **Safe Map:** Interactive vector map comparing the Naive Route (red/dashed) with the CityPulse Safe Corridor (green/solid), complete with building landmarks and touch inspection.
2. **Why This Route?:** Comparative trade-off metrics, avoided flood chokepoints, high-ground detour distance, and symbolically audited dispatch briefings.
3. **Flood Watch:** Monitored Greater Chennai Corporation (GCC) hotspots with real-time water depth gauges and on-device hazard report submission.
4. **Rain Modes:** Scenario simulation lab (Monsoon Surge, Subway Closures Spate, Cyclone Michaung Replay, Dry Baseline) and vehicle risk dial configuration.

---

## 🛠️ Tech Stack & Architecture

- **Language:** 100% Kotlin
- **UI Framework:** Jetpack Compose (BOM 2025.02.00) with Material Design 3
- **Architecture:** Clean Architecture / MVVM with Kotlin Coroutines & `StateFlow`
- **Local Persistence:** AndroidX Room Database (offline-first caching)
- **Annotation Processing:** Google KSP
- **Testing:** Robolectric JVM tests, Roborazzi Screenshot Testing, JUnit 4
- **Secret Management:** Secrets Gradle Plugin via `.env` / `.env.example`

---

## 🚀 Building & Running

### Prerequisites
- Android Studio Ladybug / Meerkat or later
- JDK 11 or 17
- Android SDK 36 (targetSdk 36, minSdk 24)

### Clone & Build
```bash
git clone https://github.com/your-username/citypulse-ai.git
cd citypulse-ai
./gradlew assembleDebug
```

### Running Unit Tests
```bash
./gradlew testDebugUnitTest
```

---

## 📄 Documentation

For deep technical specifications, mathematical derivations, algorithm pseudo-code, and agent instructions, refer to [`AGENT_HANDOFF_CITYPULSE_AI.md`](./AGENT_HANDOFF_CITYPULSE_AI.md).
