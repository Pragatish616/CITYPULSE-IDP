# S1: Novelty of CityPulse AI against flood-aware routing research, products and patents

Reviewer: S1 (novelty only; statistics, maths and code quality are out of scope)
Date: 1 October 2026
Documents reviewed: `citypulse_context/drafts/paper.tex` (title L20, abstract L44, intro L52–62, related work L64–75, Sections III–IV), `drafts/plan.tex` (bottom line L36, landscape table L117–128, claim verdicts L131–146, "make it unique" L149–158, startup positioning L171–176), `IDEA_AND_FACTS.md`, and the six research notes in `research_notes/Flood aware navigation literature/`.

Evidence conventions:
- **[opened]**: I read the source this session.
- **[notes]**: the metadata was verified in the research notes, and I relied on the notes' abstract-level summary.
- **[preprint]** and **[non-peer-reviewed]**: labelled where they apply.

I ran 11 targeted searches (Exa and fetches), listed at the end.

---

## 0. Classification of the core idea

**Verdict: systems integration plus an application case study. It is not a new method, and it is not yet a dataset or benchmark paper.**

Justification:
- Every algorithmic ingredient has direct precedent. Log-odds evidence fusion comes from occupancy grids. Age-decayed, type-specific report confidence appears in TomTom, HERE and Microsoft patents and in Waze's 30-minute expiry. Pessimism under thin evidence appears as LCB pessimism, worst-case CVaR under sparse data, and a 2026 credal posterior for crowd flood reports. Per-user risk tolerance appears in the MITRE patent and in VaR routing. FLOAT (Jao et al. 2025) uses the same time-versus-risk and flood-slowdown cost shape. The ALT validity result is Delling & Wagner 2007 and Nannicini et al. 2012. The template-then-LM-rewrite architecture is T2G2. Deterministic runtime checks on LLM output are an established pattern (RvLLM, the "deterministic LLM sandwich", Disha). Offline evacuation routing with shared blocked segments is Itoi et al. 2017.
- What is new is the **assembly**. The system combines an evidence-count-dependent pessimistic hazard probability, a per-class confidence dial, and a typed, fail-closed verifier that gates LM rewrites against a routing decision record. It runs entirely on a phone over a real city-scale graph of 193k nodes, and it is evaluated in replay on a real Indian flood corpus.
- The paper has two pieces of intellectual content beyond engineering. One is a design argument: confidence-multiplied penalties are optimistic under staleness, and that is exactly what incumbents' expiry rules do. The other is an empirical negative result: a time-proportional penalty caps deterrence at 1+λs, so the commuter default is nearly hazard-blind. Both are modest. The negative result is honest and useful, but it is elementary.
- It could become a **dataset/benchmark** paper only if the Chennai replay corpus is released with independent, time-stamped ground truth. Today the corpus has a single timestamp, no negatives and possible overlap with the osm-in "Flooded Streets" data (chennai_india.md, Q2, item 5).

**Implication for venue:** pitch the paper as a systems or applications paper (IEEE ITSC applications track, ISCRAM, SIGSPATIAL ARIC, IEEE GHTC or TENCON), not as a methods paper. The contribution list should say "integration + design argument + case study" in so many words.

---

## Claim-by-claim table

| # | Claim (location) | Closest prior work (opened or [notes]) | What is genuinely different | Verdict | Strongest defensible wording |
|---|---|---|---|---|---|
| 1 | Flood-aware routing (paper L56; plan L137) | IBM US20130116920A1 [opened]; HERE US11691646B2 [opened]; Li 2023, Liang 2025, Jao 2025 FLOAT, Karanjit 2026, Alabbad 2024 [notes] | Nothing | Not novel (paper already concedes) | Keep as stated at L56 |
| 2 | "We instead treat [flood state] as an uncertain belief built from sparse reports" (paper L66) | Safaei-Moghadam 2023 (already cited as `safaei2023waze`) [opened via search]: likelihood of roadway flood from a DEM prior plus Waze reports "to provide near-real-time navigational warnings". Toathom 2024 (per-section flood likelihood in routing); Alabbad 2024 (probabilistic forecasts); Lupa 2026 (bracketed uncertainty); Cao et al. 2026 (Bayesian MRF from sparse observations) [opened via search]; Li, Song & Li 2026 [preprint, opened]: distributionally robust credal posterior over crowd road-passability reports with stale forwarding, then min-max dispatch | Per-edge pessimistic bound with decay-weighted n_eff in a navigation (not dispatch) router | **Overclaimed** | "Several works estimate road-flood probability from crowd data [..] or route on expected flood likelihood [..]; few make the routing cost depend on how much evidence supports each edge." |
| 3 | Pessimistic upper bound, caution grows as evidence thins, per-class z (paper L58, L88–94; plan L141) | Jin, Yang & Wang 2025 (pessimism = sign-flipped bonus) [notes]; Flajolet 2018 (routing on confidence intervals) [notes]; Toumazis & Kwon 2016 (worst-case CVaR because data are insufficient) [notes]; Li, Song & Li 2026 credal flood-report fusion [preprint, opened]; Kang 2014 VaR at a chosen confidence level [notes]; MITRE US12135218B2, routing by user risk-tolerance profile [opened] | A Wald-type binomial bound on a per-edge hazard probability with decay-weighted n_eff, with z set by user class, in a crowd-fed flood navigator | **Incremental** (specific instantiation) | "We instantiate pessimism in the face of uncertainty [Jin; Gilboa–Schmeidler] as a per-edge upper bound on the fused hazard probability whose width shrinks with effective evidence, with the confidence level set per user class." |
| 4 | "Confidence-multiplied penalties are risk-seeking under ambiguity" (paper L58, L94) | Ellsberg 1961; Gilboa & Schmeidler 1989 [notes]. Industry practice that the argument targets: TomTom US9836486B2 (confidence "ages" by a decay function, below threshold "drivers are no longer informed") [opened]; HERE US10650670B2 (confidence falls with staleness, cancel below threshold) [opened]; Waze alerts removed after about 30 min unless confirmed [opened, secondary] | No routing paper found that states the argument explicitly (uncertain_routing.md, Q1) | **Novel as an explicit argument, but small**, and stated more strongly than the model supports (see S1) | "Expiry and confidence-decay rules used for crowd hazard alerts [TomTom; HERE; Waze] make a road look clear as evidence ages. For safety-critical classes this is optimism under ambiguity [Ellsberg; Gilboa–Schmeidler]; we use a bound that widens as evidence thins." |
| 5 | Formulation separating slowdown from harm (paper L58, L96–101) | Jao et al. 2025 FLOAT: λ trades time against flood risk, α is a flood-speed penalty [notes]; Krumm & Horvitz 2017; Galbrun 2016 [notes]; Pregnolato 2017 (cited) | The additive probabilistic harm term next to a probability-weighted depth slowdown | **Incremental** | "Following [FLOAT; Krumm], we keep slowdown and harm separate …" |
| 6 | Per-class depth chance constraint (paper L101) | Bonbibi [non-peer-reviewed, opened]: per-mobility-profile depth limits (wheelchair 0.1 m, foot 0.5 m, vehicle 0.3 m); He 2026 and Tahvildari 2022 (class-specific thresholds) [notes]; Charnes & Cooper (cited) | It never fires on the corpus (no depth data) | **Not novel**; also untested | Present as a design element, not a contribution |
| 7 | Bounded deterrence 1+λs (paper L59, Prop. 2; plan L143 "New finding") | Time-proportional exposure limits are known qualitatively: Donaldson 2026 (dose gains shrink because detours add time); Wang 2022 [notes]. Per-traversal versus per-time risk: Krumm 2017 [notes]. No head-to-head comparison found (uncertain_routing.md) | One-line algebra, plus an empirical demonstration on a real graph | **Incremental / elementary**; "New finding" in the plan is **overclaimed** | "We observe (Prop. 2) that a time-proportional hazard penalty bounds deterrence by 1+λs, and show its consequence on the Chennai graph." Call it an observation and lead with the empirical consequence. |
| 8 | ALT stays exact under hazard penalties (paper Prop. 1, L103–109; plan L140) | Delling & Wagner 2007 (cited); Nannicini et al. 2012 [notes] | Nothing; the δ≥1 clamp is an implementation condition | **Not novel** (credited correctly at L69, but labelled a "Proposition") | Rename to "Property" and cite both papers |
| 9 | Offline-first system with sync (paper L60, L120; plan L142) | Itoi et al. 2017 [opened]: offline evacuation app that infers blocked segments, reroutes and shares them over DTN. Google Maps offline driving navigation, which has no traffic or alternate routes offline [opened]. 2026 hackathon apps: Nongor, LIKAS, Disha [opened] | City-scale graph (193k nodes) with a probabilistic hazard belief carried offline | **Incremental** | "Unlike offline navigation in consumer apps, which loses hazard updates and rerouting offline [Google help], and offline evacuation apps [Itoi 2017], CityPulse keeps a probabilistic hazard belief and re-plans on it without connectivity." |
| 10 | Decision trace plus fail-closed verifier for LM rewrites (paper L60, L145–168; title L20; plan L142, L156) | T2G2 (template → LM rewrite) [notes]; VCP (rule check plus regeneration) [notes]; RouteExplainer (route explanation with GPT-4, no faithfulness check) [notes]; SVE (Schild 2025) [notes]; RvLLM runtime verification [opened via search]; Disha ("precise values never pass through the model", verification layer, rule-based fallback) [non-peer-reviewed, opened]; Bonbibi ("model composes; it never decides") [non-peer-reviewed, opened]; LIKAS (grammar-constrained, deterministic fallback) [non-peer-reviewed, opened] | A *typed* symbolic gate (numerals, entities, comparatives, data gaps, hedging, no-safety-claims) over an uncertain route decision, with fail-closed display of the template | **Incremental, and currently unevaluated.** "Verified Explanations" in the title is **overclaimed** | "a verifier-gated explanation design, whose pass and false-reject rates we leave to future work" — or measure them before submission |
| 11 | The combination (paper L56; plan L36, L142) | No single peer-reviewed system found. Non-peer-reviewed 2026 systems combine on-device LLM, offline flood-avoiding routing and grounded narration (Disha, Nongor, LIKAS, Bonbibi, CrisisConnect Edge) or decaying crowd reports with explainable routing (RainRoute AI) [all opened] | The probabilistic belief with an evidence-dependent bound; a typed verifier; replay on a real city corpus | **Defensible only with careful wording** | See the suggested wording under C3 |
| 12 | Class-specific decay (plan L138: "claim only calibrated, class-specific decay") | TomTom US9836486B2 [opened] describes the Trapster scheme where hazards expire by type (police trap 1 h, closure 6 h, construction 5 days) and confidences age by a decay function; Jøsang 2002, Rosen 2016 (cited) | Only *calibration* would be new, and Study 2 found C3 = C2 (no benefit) | **Not novel**; the calibrated variant is unsupported by the evidence | Drop as a contribution |
| 13 | Common-reference evaluation protocol (paper L61; plan L144 "Useful") | OD-pair frontiers are standard (Krumm, Ghoul, Rohmann, Donaldson) [notes]; scoring under a common reference is basic experimental hygiene | Fixes a flaw in the team's own earlier harness | **Not a contribution in itself** | Present as methodology. Claim a *benchmark* only once released with independent labels |
| 14 | Traversal silence as "the moat … nobody can buy it" (plan L151, L176) | Pietrobon et al. 2019 HERE (probe-absence closure detection) [notes]; Kong 2022; Hiramoto 2025; She 2019 [notes]; Itoi 2017 (deviation reveals blockage) [opened]; Yuan 2023 (INRIX null speed as a flood label) [notes] | Integration with a decaying log-odds belief, handling of missing-not-at-random reporting, and calibration | **Overclaimed** as stated | "We integrate probe-traversal likelihoods (per [Pietrobon; Kong; Hiramoto]) into …" |
| 15 | Reservoir-to-corridor causality that "global products do not model at street level" (plan L154) | Chennai RTFF & SDSS: ₹107.2 crore, operational since Oct 2025, covers lakes, rivers, drains and sea, with street-level inundation forecasts for Velachery, Saidapet, Mudichur and others [opened]; C-FLOWS, 796 scenarios including discharges [notes] | Feeding release signals into a routing prior | **Overclaimed** | "consume RTFF/CFM-DSS reservoir and inundation outputs as a dynamic prior" |
| 16 | "Forecasting … River and basin scale, not streets" (plan L124) | Flood Hub urban flash-flood forecasts, Mar 2026 (area-level) [notes]; Chennai RTFF street-level forecasts [opened] | n/a | **Factually outdated** | Correct the row |
| 17 | Positioning: "Chennai's monsoon passability layer …" (plan L171) | RiskMap Chennai, MIT Urban Risk Lab, 2017–2019, crowd flood reports to help residents "navigate to safety" [opened]; GCTP roadEase/Lepton to Google Maps [notes]; GCC ICCC EWS [notes] | Uncertainty-aware, segment-level output | **Partly pre-empted** | Name RiskMap and say why this attempt differs |
| 18 | Haven Mode not novel (plan L139) | TN-Alert location-based alerts [notes] | n/a | Plan verdict correct | Keep (now verified, so remove the asterisk) |

---

## Critical

### C1. The related-work claim that prior flood routers treat flood state as known is contradicted by already-cited and recent work

- **Location:** paper.tex L66 ("These studies generally treat the flood state as known from a model. We instead treat it as an uncertain belief built from sparse reports."). The same framing appears in abstract L44 and in contribution 1 (L58).
- **Problem:** This sentence is the paper's only stated point of departure from flood-routing work, and the record contradicts it:
  - **Safaei-Moghadam et al. 2023**, already in refs.bib as `safaei2023waze` and cited at L72 only as "crowd sensing", estimates *the likelihood* of roadway pluvial flooding by combining a depression-based DEM susceptibility analysis with Waze crowd reports, explicitly "to provide near-real-time navigational warnings". That is a static prior plus crowd reports producing a probability for navigation, which is CityPulse's belief layer in outline.
  - Toathom & Champrasert 2024 route relief vehicles on "the likelihood that each section of the road will flood".
  - Bucar & Hayeri 2022 learn link-level flood risk and benchmark against most-reliable paths.
  - Alabbad et al. 2024 drive routing from probabilistic 10-day forecasts.
  - Lupa et al. 2026 bracket passability uncertainty with two satellite products.
  - Cao et al. 2026 infer probabilistic road inundation from sparse observations with a Bayesian MRF and sequential updating.
  - Most pointedly, **Li, Song & Li 2026** (Research Square preprint, July 2026) fuse crowdsourced road-passability reports under uncertain source credibility and "stale forwarding" into a *distributionally robust credal posterior* and dispatch min-max, with a replay of the 2021 Zhengzhou flood. That is a pessimistic fusion of unreliable, ageing crowd evidence for flood routing. Their companion paper (Discover Artificial Intelligence, Aug 2026) routes trucks on Bayesian road-access beliefs with a CVaR criterion.
- **Why it matters:** A referee who knows any one of these will read L66 as a novelty claim that is false. That damages trust in the remaining claims. It is the single most likely cause of a "lack of awareness of related work" rejection.
- **Suggested fix:**
  1. Rewrite L66 along these lines: "Most flood routers take road state from a hydrodynamic or remote-sensing model [..]. Others estimate road-flood probability from crowd and traffic data [Safaei-Moghadam 2023; Yuan 2023; Cao 2026], route on expected flood likelihood [Toathom 2024; Bucar 2022] or forecast scenarios [Alabbad 2024], or fuse unreliable crowd reports robustly for dispatch [Li et al. 2026]. We are not aware of a navigation router whose edge cost depends on how much evidence supports each edge's estimate."
  2. Add a short paragraph on risk-averse and robust routing: Krumm & Horvitz 2017; Galbrun 2016; Rohmann & Bachem 2026; Flajolet 2018; Toumazis & Kwon 2016; Eyerich 2010 (CTP).
  3. Cite FLOAT (Jao 2025) for the λ/α cost shape.
- **Confidence:** High. Li et al. 2026 is a preprint, so cite it as one; the others are peer-reviewed.
- **Evidence:**
  - Safaei-Moghadam 2023: search result abstract (https://exa.ai/library/publication/8pkgb79h173); refs.bib L769.
  - Li, Song & Li 2026 preprint: https://exa.ai/library/publication/4smgs8ncbts [opened].
  - Li, Song & Li 2026, Discover AI: https://exa.ai/library/publication/9t6kyw5jv3v [opened].
  - Cao et al. 2026: https://exa.ai/library/publication/f31gx36ly8f [search abstract].
  - Toathom 2024: https://doi.org/10.3390/app14114482 [notes and search].
  - Alabbad 2024: https://doi.org/10.1007/s44212-024-00040-0 [notes].
  - Lupa 2026: https://doi.org/10.3390/rs18173004 [notes].
  - Jao 2025: https://doi.org/10.1109/ICNSC66229.2025.00052 [notes and search abstract].

### C2. The motivation ignores shipped products and Chennai's own systems, and two motivating sentences are inaccurate as written

- **Location:**
  - paper.tex L44: "Navigation apps route drivers into flooded streets because they optimise travel time on a network assumed to be intact, and they often stop working when floods take down cellular service".
  - L54: "cloud-dependent services fail when connectivity does".
  - The related work (L64–75) mentions no product, no patent beyond IBM and Uber, and no Chennai system.
- **Problem:**
  - **Google Maps India** has let users report and receive flooding/waterlogging alerts since October 2024. India had "the highest number of flood-related alerts on Maps globally" in 2025, and Maps takes closures from traffic police in 18 cities and from NHAI.
  - **Mappls** advertises "real-time Waterlogging Alerts ahead on your route while you navigate" (Aug 2026). Its CEO stated in 2023 that users are "alerted about incidents … on their route, and can be suggested alternative routes".
  - Google Maps **does** navigate offline for driving. It loses traffic and alternate routes offline ("If you're offline when you drive, you can't get traffic info or alternate routes"); it does not "stop working".
  - Chennai has the **RTFF & SDSS** (₹107.2 crore, fully operational Oct 2025), which issues street-level inundation forecasts for Velachery, Saidapet, Mudichur and other localities and disseminates through TN-Alert.
  - **RiskMap** (MIT Urban Risk Lab) ran crowd flood reporting in Chennai in 2017–2019 so residents could "navigate to safety".
  - HERE's patent US11691646B2 (filed 2020) warns of and reroutes around active floods at flood-prone locations, and its background states the very motivation the paper uses: maps "may actually define a route that directs a driver to and through a flooded roadway".
- **Why it matters:** An Indian or ITS referee will know Google Maps' flood alerts and Chennai's RTFF. A motivation that implies nobody addresses this reads as uninformed. The real gap is narrower, and it is defensible. No incumbent publishes per-segment uncertainty, ageing behaviour, or user-class risk tolerance. Offline, incumbents lose hazard updates and rerouting. Their alert-expiry rules are optimistic under staleness (C3/S1).
- **Suggested fix:**
  1. Replace the first abstract sentence with something like: "Consumer navigation apps now display crowd-reported flooding, but they do not expose how certain a report is, let stale reports expire silently, and lose hazard updates and rerouting when connectivity fails."
  2. Add a "Deployed systems" paragraph (about 6 lines) citing Google Maps India, Mappls, Waze's alert expiry, the HERE and TomTom patents, Chennai RTFF/C-FLOWS/TN-Alert, and RiskMap Chennai.
  3. Cite Itoi 2017 for offline evacuation routing.
- **Confidence:** High.
- **Evidence:**
  - https://www.timesnownews.com/technology-science/google-maps-adds-real-time-alerts-for-fog-and-flooding-in-india-how-it-works-article-113911307 [opened]
  - https://blog.google/intl/en-in/products/explore-communicate/google-maps-in-india-keeping-you-informed-with-new-safety-disruption-alerts/ [opened]
  - https://support.google.com/maps/answer/6291838 [opened]
  - https://www.linkedin.com/posts/mappls_waterlogging-alerts-activity-7490751087289954305-J_RR [opened]
  - https://www.linkedin.com/feed/update/urn:li:activity:7083740428323233792 [opened via search]
  - https://www.thehindu.com/news/cities/chennai/chennai-gets-indias-first-real-time-flood-forecast-system/article70186744.ece [opened]
  - https://riskmap.mit.edu/india [opened]
  - https://patents.google.com/patent/US11691646B2/en [opened]
  - https://doi.org/10.1186/s41070-017-0013-1 (authors' PDF: https://www2.itc.kansai-u.ac.jp/~sasabe/publications/itoi17OfflineMobileApplication.pdf) [opened]

### C3. The "combination" novelty is threatened by 2026 on-device-LLM flood apps, and the explanation half is unevaluated

- **Location:** paper.tex L20 (title "… with Verified Explanations"), L56 ("What we examine is a specific combination"), L60 (contribution 3), L149 ("We have not yet measured the pass rate …"); plan.tex L36 and L142 ("On-device route + confidence + verified explanation: Defensible").
- **Problem:** Between April and August 2026, several publicly documented, non-peer-reviewed systems shipped the same architectural pattern: an on-device small LM narrates a deterministically computed, flood-avoiding route; numbers stay in code; and there is a deterministic fallback.
  - **Disha** (Build with Gemma @Bangladesh, July 2026). Gemma 4 runs on-device over LiteRT-LM, with "Dijkstra flood-avoid routing on real OSM road graphs". "Every exact value … is produced by tested code, never by the model. An automation and verification layer sits on both sides of every generation". It runs a rule-based fallback when the model is unavailable, and it adopted "precise values never pass through the model" after observing number corruption.
  - **Bonbibi** (Arm challenge, Aug 2026). Offline flood simulation on a Raspberry Pi with "deterministic BFS" shelter routing per mobility profile and depth limits; "Granite composes personal guidance … The model composes; it never decides."
  - **LIKAS** (Kaggle, Apr–May 2026). "Zero network calls at runtime"; offline Dijkstra on a bundled OSM graph; a grammar-constrained Gemma tool dispatcher; a "deterministic keyword router" fallback.
  - **Nongor** (July 2026). Offline flood-avoiding shelter routing with Gemma on the handset.
  - **CrisisConnect Edge** (May 2026). Offline Gemma grounded in a cached package with "freshness metadata"; it must warn when the package is stale.
  - **RainRoute AI** (Aug 2026). Crowd hazard reports that "decay with distance and expire automatically after two hours" drive an "explainable" flood-aware route.

  All of these predate CityPulse's mid-September 2026 start. In the peer-reviewed literature, T2G2 already does template → LM rewrite, VCP does rule check plus regeneration, and RouteExplainer pairs route explanation with an LLM. Runtime verification of LLM output against domain constraints (RvLLM) and the "deterministic LLM sandwich" are documented patterns.

  What remains distinct in CityPulse:
  - (a) The hazard state is a **probabilistic, evidence-weighted belief** rather than a binary flood polygon.
  - (b) Routing uses an **evidence-dependent pessimistic bound** with a per-class dial.
  - (c) The gate is a **typed post-hoc verifier** (numerals with tolerance and unit conversion, entities, comparatives, data-gap coherence, required hedging, a ban on safety claims) that **fails closed to a template**, rather than keeping numbers out of the model.
  - (d) The router runs on a **193k-node city graph** with a real-event replay evaluation.

  However, (c) is described, not evaluated (L149, L251). So the title's "Verified Explanations" and contribution 3 rest on an untested design.
- **Why it matters:** Hackathon projects are not citable prior art in the same sense as peer-reviewed papers. But reviewers in on-device AI and disaster informatics will have seen the 2026 Gemma hackathons. "We are not aware of work combining on-device routing and LLM explanation" will then read as false. Patent examiners also treat public disclosures as prior art, which matters for any patent plans. An unmeasured verifier gives a referee nothing to weigh.
- **Suggested fix:**
  1. Retitle, for example: "Evidence-Aware Offline Flood Routing with Verifier-Gated Explanations: Design and a Replay Study on the Chennai Road Network".
  2. Replace L56 with: "To our knowledge, no peer-reviewed system combines (i) a per-edge flood belief fused from a susceptibility prior and age-decayed, source-weighted reports, (ii) routing on a bound whose width depends on the effective evidence, with a per-user-class confidence level, and (iii) natural-language explanations accepted only if a deterministic verifier finds them consistent with the routing decision record, all running on a phone without connectivity. Recent non-peer-reviewed systems pair on-device language models with offline flood-avoiding routing on binary flood extents [Disha; Bonbibi; LIKAS]; CityPulse differs in (i)–(iii)."
  3. Before submission, measure the verifier on N≥300 traces × 3 tiers: the pre-gate error rate, the post-gate error rate (which should be 0) and the false-reject rate. Without these numbers, demote contribution 3 to "system design" and say that it is unevaluated.
- **Confidence:** High on the existence and dates of the systems. Medium on how reviewers will weigh non-peer-reviewed prior art.
- **Evidence:**
  - https://github.com/mustafiz-07/UIU_Hacathon [opened via search]
  - https://www.kaggle.com/competitions/build-with-gemma-bangladesh/writeups/new-writeup-1785053923335 [opened via search]
  - https://devpost.com/software/bonbibi [opened]
  - https://github.com/JpCurada/likas [opened]
  - https://github.com/AuvroIslam/Nongor [opened; created 2026-07-28]
  - https://www.kaggle.com/competitions/gemma-4-good-hackathon/writeups/crisisconnect-edge-gemma-4-for-local-first-disast [search highlights]
  - https://devpost.com/software/rainroute-ai [search highlights]
  - https://arxiv.org/html/2505.18585v3 (RvLLM) [search abstract]
  - T2G2, VCP, RouteExplainer: explanation_llm.md [notes]

---

## Significant

### S1. The pessimism and risk-seeking argument lacks its intellectual ancestors, and the "reverses the direction" claim is stronger than the formula supports

- **Location:** paper.tex L58, L88–94 ("This mirrors the upper confidence bounds of bandit algorithms … but is used pessimistically"; "A common alternative prices an edge as w=τ0(1+λRC) …"; "Equation (3) reverses the direction of that dependence").
- **Problem:**
  1. Pessimism-as-sign-flipped-bonus is the core of offline-RL pessimism (Jin, Yang & Wang, MOR 2025). Routing on confidence-interval information is in Flajolet et al. 2018. Worst-case CVaR because "historical data are usually insufficient" is in Toumazis & Kwon 2016. Ambiguity aversion is formalised in Ellsberg 1961 and Gilboa & Schmeidler 1989. Pessimistic fusion of stale crowd flood reports is in Li et al. 2026 [preprint]. None of these is cited.
  2. The "common alternative" is asserted without citation. It *is* common, and saying so strengthens the paper:
     - TomTom US9836486B2: confidence values "age according to a predefined function"; below a threshold, "drivers are no longer informed"; hazards expire by type.
     - HERE US10650670B2: confidence is decreased for "staleness"; road events are cancelled below a lower threshold.
     - Waze alerts are typically removed after about 30 minutes unless confirmed.
     Citing these turns an abstract argument into a critique of deployed practice, which is the most original thing in the paper.
  3. L92 says p̃ decreases with n_eff "for fixed p̄". Under the paper's own fusion, though, decay changes both p̄ and n_eff: as reports age, p̄ reverts toward the prior while the band widens. Whether p̃ rises or falls as a flood report ages therefore depends on the prior and z. The claim that Eq. (3) "reverses the direction of that dependence" holds only at fixed p̄.

     (Out of my scope, flagged for the maths specialist: for prior-only edges, n_eff=0 gives p̃ = p0 + z·sqrt(p0(1−p0)). With z=2 this saturates at 1 for every p0 ≥ 0.2, so the emergency class would treat every medium-or-higher hazard zone as certainly flooded.)
- **Why it matters:** This argument is the paper's best claim to intellectual novelty. Without ancestors it looks naive; with them it looks well placed. Overstating the direction invites a counterexample from a referee.
- **Suggested fix:**
  - Cite Jin 2025, Gilboa–Schmeidler 1989, Ellsberg 1961 and Flajolet 2018, plus Li et al. 2026 as the closest flood-domain analogue.
  - Cite the TomTom, HERE and Waze sources as the "common alternative".
  - Restate the claim as: "holding the fused mean fixed, less evidence yields a higher routed probability; under decay, the routed probability of a reported edge falls toward a prior-dependent floor rather than toward zero."
- **Confidence:** High on missing citations and on industry practice. Medium on the exact direction under decay (needs the maths specialist).
- **Evidence:**
  - https://patents.google.com/patent/US9836486B2/en [opened; assignee TomTom]
  - https://patents.google.com/patent/US10650670B2/en [opened; assignee HERE]
  - Waze 30-min removal (Chen et al. 2020 report text): https://exa.ai/library/publication/bw1dv9b4fbg [search highlight; secondary]
  - Jin 2025 https://doi.org/10.1287/moor.2022.0216; Flajolet 2018 https://doi.org/10.1287/opre.2017.1662; Gilboa–Schmeidler https://doi.org/10.1016/0304-4068(89)90018-9 [notes]

### S2. Class-specific report decay is pre-empted by patents, so the plan's fallback claim ("calibrated, class-specific decay") is left with only its calibration part, which Study 2 did not support

- **Location:** plan.tex L138; paper.tex contribution framing (decay at L79–83, L186, L214); IDEA_AND_FACTS core idea ("decays … at a hazard-class-specific rate").
- **Problem:** TomTom's US9836486B2 describes the Trapster scheme, in which hazards expire after type-specific periods (police trap 1 h, road closure 6 h, construction zone 5 days). It then claims confidences that age by a decay function and are adjusted by positive and negative reports. Microsoft's US8983976B2 claims dynamically learned expiry with confidence and user trust ratings. Intel's US10737698 weights crowd road data by age. "Class-specific decay" is therefore not new. "Calibrated" decay would be new, but Study 2 found C3 indistinguishable from C2.
- **Why it matters:** The plan advises keeping this as a narrowed claim. It should be dropped entirely.
- **Suggested fix:** In the paper, describe class-specific T_c as a design parameter with cited precedent. Do not list it as a contribution.
- **Confidence:** High.
- **Evidence:**
  - https://patents.google.com/patent/US9836486B2/en [opened]
  - https://patents.google.com/patent/US8983976B2/en [opened; assignee Microsoft]
  - US10737698 highlight: https://exa.ai/library/legal/patent/wxkrp77y6s1jb1c03ygynx [search highlight; assignee not verified]

### S3. The cost formulation (slowdown separated from harm, per-class risk) has near-identical precedent

- **Location:** paper.tex L58 ("A formulation that separates slowdown from harm … with a per-user-class caution parameter"), L96–101.
- **Problem:**
  - FLOAT (Jao et al., ICNSC 2025) uses λ to trade travel time against flood risk and α as a flood-speed penalty. It sweeps them and reports that high λ and α give odd detours, mirroring CityPulse's sweep.
  - Krumm & Horvitz 2017 and Galbrun et al. 2016 keep time and risk separate.
  - MITRE's US12135218B2 (granted Nov 2024) claims navigation "dynamically assessed based on risk tolerance", with risk scores "weighed based on tolerance level".
  - Kang et al. 2014 make route choice "a function of the level of risk tolerance".
  - Bonbibi uses per-mobility-profile depth limits.
- **Why it matters:** Contribution 1 currently presents these as the paper's formulation.
- **Suggested fix:** Reword contribution 1 to: "An edge cost that, following [FLOAT; Krumm], separates slowdown from harm, but prices harm on a pessimistic probability whose margin depends on effective evidence, with the confidence level set per user class [cf. Kang 2014]."
- **Confidence:** High.
- **Evidence:**
  - https://exa.ai/library/publication/lxmwqdddw89 (FLOAT abstract) [opened via search]
  - https://patents.google.com/patent/US12135218B2/en [opened; assignee MITRE]
  - Krumm 2017 https://doi.org/10.1609/aaai.v31i2.19099 [notes]

### S4. The "bounded deterrence" proposition is elementary and should not be sold as a "new finding"

- **Location:** paper.tex L59 (contribution 2), Prop. 2 (L111–117); plan.tex L143 ("New finding").
- **Problem:** The bound follows from substituting δ=1 and p̃≤1, which is one line of algebra. Several works already note qualitatively that time-proportional exposure undercounts the harm of short severe segments and inflates the cost of detours:
  - Donaldson et al. 2026: dose reductions are smaller because detours add time.
  - Wang et al. 2022: slower travellers accrue more exposure.
  - Krumm 2017: per-traversal Bernoulli risk, not per-time.
  - Classic hazmat risk models.

  No head-to-head comparison was found (uncertain_routing.md, Q1 table). So the *empirical* demonstration on a city graph, and a fix compared head-to-head (per-edge harm μ·p̃·s), would be the actual contribution.
- **Why it matters:** Referees discount trivial propositions presented as contributions. The useful part is the negative result: 7 of 100 routes changed, and 29% versus 30% of routes crossed a high-probability edge.
- **Suggested fix:**
  - Call it an "Observation".
  - Make the contribution "we show empirically that the commuter default is nearly hazard-blind and trace this to time-proportional pricing".
  - Ideally add the per-edge harm term and compare it, which would be the first head-to-head comparison the notes could find.
- **Confidence:** High that it is elementary; medium that no published head-to-head exists (search-limited).
- **Evidence:** uncertain_routing.md Q1 table and Q2 (Donaldson 2026 https://doi.org/10.3389/frsc.2026.1869860; Wang 2022 https://doi.org/10.1016/j.trd.2022.103176) [notes].

### S5. The plan's "make it unique" items are presented as open white space, but prior art already exists for each

- **Location:** plan.tex L124 (forecasting row), L151 (traversal silence), L154 (reservoir-to-corridor causality), L171 (positioning).
- **Problem:**
  - L124 is outdated. Flood Hub has added urban flash-flood forecasts (Mar 2026, area-level), and Chennai's RTFF has given street-level inundation forecasts since Oct 2025.
  - L151 overclaims. Inferring closures from probe absence is published: HERE's Pietrobon et al. 2019 (92% precision on low-volume roads), Kong 2022 (taxi passing-rate drop for floods), Hiramoto 2025 (no traffic or speed below 20 km/h means inundated), She 2019, and Yuan 2023 (INRIX null speed as a flood label). Itoi 2017 infers blocked segments from route deviation.
  - L154 overclaims. RTFF already models lakes, rivers, drains and sea together across the Adyar, Cooum, Kosasthalaiyar and Kovalam sub-basins, with street-level outputs, and CFM-DSS publishes reservoir levels.
  - L171 ignores RiskMap Chennai (2017–19), which had the same city, the same crowd-reporting premise and a stated navigation purpose.
- **Why it matters:** These items will be repeated in pitches and in Paper 2's framing. A domain expert or investor will know RTFF and RiskMap.
- **Suggested fix:**
  - Reframe traversal silence as "integration of probe-traversal likelihoods into a calibrated belief, with missing-not-at-random handling" (crowd_flood_sensing.md, Q2).
  - Reframe the reservoir idea as "consume RTFF/CFM-DSS outputs as a dynamic prior".
  - Add a "why RiskMap ended and why this differs" line to the positioning.
  - Correct L124.
- **Confidence:** High.
- **Evidence:**
  - RTFF: The Hindu link in C2 [opened]
  - https://riskmap.mit.edu/india [opened]
  - Itoi 2017 [opened]
  - Pietrobon 2019 https://doi.org/10.1145/3325912, Kong 2022 https://doi.org/10.1111/jfr3.12799, Hiramoto 2025 https://doi.org/10.1016/j.ijdrr.2025.105373 [notes]

### S6. The evaluation protocol is listed as a contribution but is a correction of the team's own harness

- **Location:** paper.tex L61; plan.tex L144.
- **Problem:** The safest-path literature already scores routes on many OD pairs and reports exposure-versus-detour frontiers (Krumm 2017; Ghoul 2023; Rohmann 2026; Donaldson 2026). Scoring every configuration under one reference belief is ordinary experimental hygiene, and the paper itself shows that the reference is circular (L246). Reproducing the router's paths with an independent implementation is good engineering, not novelty.
- **Why it matters:** A referee may read this as padding. The paper also concedes that the evaluation cannot credit the method's distinctive part, z.
- **Suggested fix:**
  - Merge it into "a replay case study on the full Chennai graph".
  - If the team releases corpus, harness and baselines with a DOI, *and* adds independent, time-stamped labels (for example the CFM-DSS crowd layer with negatives, 2022–2025, or the IIT-M December 2023 depth reports), then claim "the first public replay benchmark for hazard-aware routing on an Indian city". The notes found no such benchmark (uncertain_routing.md Q3; flood_routing.md gap 8).
  - Before any benchmark claim, check that the 5,052 crowd observations do not derive from the osm-in "Flooded Streets" tool.
- **Confidence:** High.
- **Evidence:** uncertain_routing.md Q3; chennai_india.md Q2 [notes].

---

## Minor

### M1. Prop. 1 is a known result presented as a proposition
- **Location:** paper.tex L103–109.
- **Problem:** The credit to Delling & Wagner is correct, but the "Proposition"/proof format signals originality. Nannicini et al. 2012 state the result explicitly for increased arc costs with free-flow lower bounds.
- **Suggested fix:** Use "Property 1 (from [Delling & Wagner 2007; Nannicini et al. 2012])" and keep the δ-clamp remark.
- **Confidence:** High.
- **Evidence:** uncertain_routing.md (Nannicini preprint body quoted) [notes].

### M2. The explanation related work omits the direct ancestors
- **Location:** paper.tex L74–75.
- **Problem:** The paper cites Reiter, van Deemter, FActScore and TRUE, but omits:
  - T2G2 (Kale & Rastogi, EMNLP 2020), the same template → LM rewrite architecture;
  - VCP, a rule check with regeneration;
  - RouteExplainer and SVE (Schild 2025), route-specific explanation;
  - Ilyankou et al. 2026, which calls for neuro-symbolic, verifiable navigation;
  - Lei et al. 2025, which names hallucinated evacuation routes as a disaster-LLM risk.
- **Suggested fix:** Add these. Frame the verifier as the fail-closed alternative to rerank (DataTuner) and regenerate (VCP).
- **Confidence:** High.
- **Evidence:** explanation_llm.md [notes].

### M3. Offline-first related work omits the one peer-reviewed offline evacuation app
- **Location:** paper.tex L75 (offline-first is cited only to HLC, CRDT and local-first).
- **Problem:** Itoi et al. 2017 is an offline mobile app that estimates blocked segments, reroutes and shares the blocked segments over DTN. That is CityPulse's outbox and sync idea in disaster form.
- **Suggested fix:** Cite it in both Related Work and System Design.
- **Confidence:** High.
- **Evidence:** Itoi PDF [opened].

### M4. The patent coverage is thin
- **Location:** paper.tex L56 (IBM and Uber only).
- **Suggested fix:** Add:
  - HERE US11691646B2 (flood event warning at flood-prone locations, with rerouting; filed 2020);
  - MITRE US12135218B2 (risk-tolerance-profile navigation, 2024);
  - TomTom US9836486B2 and HERE US10650670B2 (decaying hazard confidence; for S1 and S2);
  - optionally an AV flood-routing patent, US12399034 (2025; assignee not verified here, so check before citing).
- **Confidence:** High for the four whose assignees I verified.
- **Evidence:** Google Patents pages [opened].

### M5. Tamil-first is listed as differentiation, but Tamil-language services already exist
- **Location:** plan.tex L157.
- **Problem:** TN-Alert is bilingual, and chennaiwaterlogging.org takes reports in Tamil over WhatsApp (chennai_india.md O3, O7). Tamil output is an equity feature, not a novelty. Also, the verifier's entity check cannot handle Tamil script (paper L149), so "verified Tamil explanations" is currently impossible.
- **Suggested fix:** Keep it as product scope only.
- **Confidence:** High.

### M6. "(Working title)" and the "Verified" wording
- **Location:** paper.tex L20.
- **Suggested fix:** See C3.

---

## Questions for the authors

1. Will the corpus, harness and baselines be released with a DOI before submission? That is the only route to a dataset or benchmark contribution, and it changes the paper's classification.
2. Can you obtain independent, time-stamped labels (CFM-DSS crowd layer 2022–2025 with "no water" negatives; IIT-M chennaiwaterlogging.org December 2023 depths) in time? Without them the distinctive part, z, cannot be credited (paper L210–211). Novelty claims about evidence-aware routing then rest on a design argument alone.
3. When was the CityPulse repository first made public, and did the team see the Gemma hackathon entries (Disha, LIKAS, Nongor, Bonbibi)? This affects how to word "to our knowledge" and any patent filing. Public disclosures dated April–August 2026 predate the September 2026 start.
4. Do Google Maps or Mappls actually reroute around flood reports, or only display them? I confirmed display and on-route alerts. A MapmyIndia CEO post (2023) mentions suggested alternative routes, but I found no documentation of automatic avoidance. A one-day field test in Chennai would let the paper state the incumbent gap precisely.
5. Is p̃ saturating to 1 at z=2 for prior-only edges with p0 ≥ 0.2 intended? (Forwarded to the maths specialist; it affects what "caution grows as evidence thins" means in practice.)

---

## Recommended contribution list (drop-in for paper.tex L57–62)

1. **Design:** an on-device flood router that prices each road segment on an upper bound of its fused hazard probability. The bound widens as the effective, age-decayed evidence thins, and its confidence level is set per user class. We argue that the confidence-decay and expiry rules used for crowd hazard alerts are optimistic under ambiguity for safety-critical users, and we position the design relative to pessimistic and robust decision rules.
2. **System:** an offline-first implementation on a 193k-node city graph. The same router code serves the app and the evaluation, and a structured decision trace backs explanations that are shown only if a deterministic verifier finds them consistent with the trace; otherwise the template is shown. (Add the measured pass and false-reject rates, or say the verifier is unevaluated.)
3. **Case study:** a replay on the 2015 Chennai floods. It shows that a time-proportional penalty leaves the commuter default nearly hazard-blind (an elementary bound, demonstrated empirically), and it maps the time-exposure trade-off for larger risk weights.
4. *(Only if released with independent labels)* **Benchmark:** a public Chennai replay corpus and harness for hazard-aware routing.

---

## Searches run this session (11)

1. Exa fetch: Nongor and LIKAS GitHub READMEs.
2. Exa search: on-device LLM plus offline flood routing in hackathon and GitHub projects. Found Disha, Bonbibi, RainRoute AI, CrisisConnect Edge, EnvRoute, SARA, CrisisNet and Panacea's Passage.
3. Exa fetch: Bonbibi Devpost.
4. Exa search: how Disha's verification layer works.
5. Exa fetch: Google Maps India flood alerts (Times Now), the Google India blog (Nov 2025), and Google Maps offline-navigation help.
6. Exa fetch: The Hindu on Chennai RTFF; riskmap.mit.edu/india; Itoi 2017 authors' PDF.
7. Exa search: patents on flood or hazard probability routing. Found IBM, HERE US11691646B2, MITRE US12135218B2, US12399034, US11385381 and US10955252.
8. Exa fetch: the MITRE and HERE patent pages; Exa search for patents on hazard-report confidence decay (TomTom US9836486B2, HERE US10650670B2, Microsoft US8983976B2, Intel US10737698).
9. Exa fetch: assignees for the TomTom, HERE and Microsoft patents.
10. Exa search and fetch: 2023–2026 uncertain flood-routing papers. Found Li, Song & Li 2026 (two papers), Cao et al. 2026 MRF, Pratap & Aziz 2025, and FLOAT.
11. Exa search: Mappls waterlogging alerts and rerouting. One more Exa search covered deterministic LLM-output verifiers (RvLLM, VeriPlan, the "deterministic LLM sandwich" pattern).
