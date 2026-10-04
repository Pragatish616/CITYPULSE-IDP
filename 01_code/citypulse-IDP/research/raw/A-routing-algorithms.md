# Strand A — Hazard-Aware Routing Algorithms and Optimization Theory

**Research Agent A · CityPulse AI · 2026-09-11**
Scope: risk-/hazard-aware shortest paths, routing under uncertainty, dynamic edge-weight
maintenance at scale, routing-engine reality check, benchmarks. Written to be usable as
the algorithmic spine of the project, and deliberately critical of the pitch where the
pitch is wrong.

---

## 0. Executive orientation

The pitch deck frames CityPulse's hard problem as "compute hazard-aware routes." The
literature says the shortest-path part is essentially solved; the genuinely hard and
genuinely *unsolved* parts are three:

1. **Turning noisy, decaying, heterogeneous hazard signals into a calibrated per-edge
   cost.** Nobody has done this well. This is where the novelty is.
2. **Maintaining a speedup structure under frequent, adversarially-placed weight
   increases.** Partially solved (CCH/CRP), with a decisive simplification available to
   CityPulse that the literature does not emphasise (§6.3).
3. **Evaluating any of it.** There is no benchmark. Every flood-routing paper invents its
   own city, its own hydrodynamic model, and its own ground truth.

A fourth observation that should shape the 7-week plan: **Chennai's drivable OSM graph is
roughly 10^5 nodes.** At that size a plain bidirectional Dijkstra answers a query in tens
of milliseconds. Contraction hierarchies, CRP and the rest of the speedup-technique
literature exist to serve continental graphs of 10^7–10^8 nodes. Much of §3 is therefore
*background you should understand and explicitly decline to use*, not a shopping list.

---

## 1. Taxonomy of the problem space

```
HAZARD-AWARE ROUTING
│
├── A. OBJECTIVE STRUCTURE  (what is being optimised)
│   ├── A1 Single scalarised objective            w = f(travel time, risk)
│   │      ├── additive weighted sum   w = τ + λ·ρ
│   │      └── multiplicative penalty  w = τ·(1 + λ·ρ)
│   ├── A2 True multi-objective / Pareto           (Martins-style label setting)
│   ├── A3 Constrained (resource-constrained SP)   min τ  s.t. Σρ ≤ B
│   └── A4 Risk measures over a distribution
│          ├── expected value            (risk-neutral)
│          ├── mean–variance             (Markowitz-style)
│          ├── VaR / CVaR                (tail-focused, Toumazis & Kwon)
│          └── chance constraint         Pr[fail] ≤ ε
│
├── B. UNCERTAINTY MODEL  (what is unknown)
│   ├── B1 Deterministic, known                    classic SP
│   ├── B2 Time-dependent, deterministic (TDSP)    τ(e,t) known function of departure time
│   ├── B3 Stochastic, known distribution (SSP)    reliable SP, on-time arrival probability
│   ├── B4 Stochastic + time-dependent (STD)       hardest well-studied class
│   ├── B5 Set/interval (robust SP)                min-max, min-max regret
│   ├── B6 Adaptive / online (MDP, CTP)            decisions revealed en route
│   └── B7 EPISTEMIC: distribution parameters themselves uncertain   ← CityPulse lives here
│
├── C. APPLICATION LINEAGE
│   ├── C1 Hazmat routing          (risk = P(accident) × population exposed)
│   ├── C2 Evacuation routing      (network flow, contraflow, capacity-constrained)
│   ├── C3 Flood/inundation routing (depth → speed → impassability)
│   ├── C4 Emergency response / EMS dispatch
│   └── C5 Military / robotic risk-aware path planning (threat fields)
│
├── D. COMPUTATIONAL TECHNIQUE
│   ├── D1 Goal-directed:        A*, ALT (landmarks + triangle inequality)
│   ├── D2 Hierarchical:         CH, CCH, CRP/MLD, hub labelling
│   ├── D3 Time-dependent:       TCH, CATCHUp, TD-ALT
│   ├── D4 Learning-based:       Q-routing, GNN + RL, LLM-in-the-loop
│   └── D5 Metaheuristic:        GA/ACO/ABC (dominant in the flood/evac literature)
│
└── E. DYNAMICS REGIME  (how weights change)
    ├── E1 Static
    ├── E2 Periodic batch recustomisation        (OSRM live traffic: minutes)
    ├── E3 Incremental / partial recustomisation (CCH cell-local)
    └── E4 Per-request cost model                (Valhalla dynamic costing, GH custom models)
```

**Where CityPulse sits:** A1 + A4(chance constraint) · B7 · C3/C4 · D1+D2 · E3/E4.
The B7 cell — epistemic uncertainty over hazard presence, driven by sparse decaying
crowd reports — is the cell the literature has barely touched. See §8.

---

## 2. Annotated bibliography

All entries below were retrieved and checked during this session. Where I could not open
the publisher page directly (robots.txt / paywall), I say so and give the source that did
verify. I have marked **[UNVERIFIED DETAIL]** on any specific number I could not confirm
from primary text.

### 2.1 Foundations and surveys

**[1] Bast, Delling, Goldberg, Müller-Hannemann, Pajor, Sanders, Wagner, Werneck (2016).
"Route Planning in Transportation Networks."** In *Algorithm Engineering*, LNCS 9220,
Springer. arXiv:1504.05140.
<https://arxiv.org/abs/1504.05140> · <https://link.springer.com/chapter/10.1007/978-3-319-49487-6_2>
The canonical survey of shortest-path speedup techniques. Establishes the
preprocessing/space/query trade-off taxonomy (goal-directed vs. hierarchical vs. hub
labelling), and shows continental-scale driving directions in milliseconds. **Read this
first**; it is the map of §3. Its treatment of dynamic scenarios is the honest baseline:
speedup techniques and frequent weight changes are in tension, and CRP/CCH are the answer.

**[2] Goldberg & Harrelson (2005). "Computing the Shortest Path: A* Search Meets Graph
Theory."** SODA 2005, 156–165. <https://dl.acm.org/doi/10.5555/1070432.1070455> ·
<https://www.microsoft.com/en-us/research/publication/computing-the-shortest-path-a-search-meets-graph-theory/>
Introduces **ALT** (A*, Landmarks, Triangle inequality): precompute distances to ~16
landmark vertices, derive admissible lower-bound potentials via the triangle inequality.
Critically for CityPulse, ALT potentials computed on a *lower-bound* metric remain
admissible under **any** increase of edge weights — see §6.3. This paper is the single
most operationally relevant classical reference for this project.

**[3] Dean (2004). "Shortest Paths in FIFO Time-Dependent Networks: Theory and
Algorithms."** MIT technical report.
<https://people.csail.mit.edu/bdean/tdsp.pdf>
The standard reference for the FIFO (non-overtaking) condition: if travel-time functions
τ(e,t) satisfy FIFO, time-dependent shortest paths are solvable by a Dijkstra variant in
essentially static-SP time; without FIFO, waiting policies matter and the problem becomes
much harder. **CityPulse must enforce FIFO on its hazard-modulated cost** or it loses
Dijkstra correctness — this is a real constraint on how hazard onset is modelled.

**[4] Foschini, Hershberger, Suri. "On the Complexity of Time-Dependent Shortest Paths."**
SODA 2011; journal version *Algorithmica* 68(4), 2014.
<https://sites.cs.ucsb.edu/~suri/psdir/soda11.pdf>
Shows the *point-to-point time-dependent shortest path function* can have superpolynomial
(n^Θ(log n)) complexity even with piecewise-linear edge functions. The practical takeaway:
do not try to precompute profiles over all departure times; query for a fixed departure
time instead. This bounds what CityPulse can reasonably precompute.

### 2.2 Risk, uncertainty and multi-criteria formulations

**[5] Erkut & Verter (1998). "Modeling of Transport Risk for Hazardous Materials."**
*Operations Research* 46(5), 625–642. DOI 10.1287/opre.46.5.625.
<https://pubsonline.informs.org/doi/10.1287/opre.46.5.625> *(publisher page blocks
automated fetch; existence and metadata verified via INFORMS listing and citing works.)*
The origin of the standard hazmat risk model: edge risk = P(incident on edge) × consequence
(population within an impact band), summed along the path — i.e. **risk is an additive,
length-scaled exposure integral**. Shows different risk models yield materially different
"minimum-risk" paths, so the choice of risk functional is not innocent. This justifies
CityPulse's risk term being proportional to *dwell time on the edge*, not a flat per-edge
constant.

**[6] Erkut, Tjandra, Verter (2007). "Hazardous Materials Transportation."** Chapter 9 in
*Handbooks in Operations Research and Management Science*, Vol. 14 (Transportation),
Elsevier, 539–621. <https://www.sciencedirect.com/science/article/abs/pii/S0927050706140098>
The definitive survey of hazmat routing: risk models, bi-objective path finding, network
design, equity constraints. Its bi-objective (cost, risk) framing is directly transferable:
CityPulse's "travel time vs. hazard exposure" is structurally the same problem with a
different consequence model.

**[7] Toumazis & Kwon (2013). "Routing Hazardous Materials on Time-Dependent Networks Using
Conditional Value-at-Risk."** *Transportation Research Part C: Emerging Technologies*.
<https://www.sciencedirect.com/science/article/abs/pii/S0968090X13001861> ·
PDF: <https://comet.kaist.ac.kr/papers/toumazis2013trc.pdf>
Minimises **CVaR** of accident consequence on a time-dependent network, solving
`min_r { r + (1/(1-α)) Σ p_ij [c_ij − r]^+ }` by nesting a time-dependent shortest-path
subproblem (back-labelling, Bellman's principle) inside a search over the VaR threshold r.
The α parameter tunes risk-neutral → risk-averse. This is the most rigorous risk-measure
treatment applicable to CityPulse, and the honest alternative to the plug-in penalty I
recommend in §5. **[UNVERIFIED DETAIL]** exact volume/pages — I could not confirm
"Vol. 37, 73–92" from primary text; cite by DOI/PII.

**[8] Nie & Wu (2009). "Shortest Path Problem Considering On-Time Arrival Probability."**
*Transportation Research Part B: Methodological* 43(6), 597–613.
<https://ideas.repec.org/a/eee/transb/v43y2009i6p597-613.html> ·
<https://www.scholars.northwestern.edu/en/publications/shortest-path-problem-considering-on-time-arrival-probability>
Defines the *reliable a-priori shortest path*: maximise P(arrival ≤ deadline) rather than
minimise expected time. Builds on first-order stochastic dominance and a label-correcting
algorithm, and extends to time-dependent distributions. The key conceptual import for
CityPulse: **for emergency vehicles the objective is reliability, not expectation** — a
route with 12-min mean and 40-min tail is worse than a 15-min route with a 17-min tail.

**[9] Papadimitriou & Yannakakis (1991). "Shortest Paths Without a Map."** *Theoretical
Computer Science* 84(1), 127–150. (The **Canadian Traveller Problem**.)
<https://en.wikipedia.org/wiki/Canadian_traveller_problem> *(canonical secondary source;
the TCS paper is paywalled but universally cited with these details.)*
Proves that devising an optimal online strategy when edges may be blocked and blockages
are only discovered on arrival is **PSPACE-complete**. This is the formal statement of
CityPulse's actual situation: a driver discovers the flooded underpass when they reach it.
It means **no algorithm will be optimal**, and it licenses heuristic/adaptive policies —
but it should be cited honestly rather than glossed over.

**[10] Dumitrescu & Boland (2003). "Algorithms for the Weight Constrained Shortest Path
Problem."** *International Transactions in Operational Research* 8(1).
<https://eva.fing.edu.uy/pluginfile.php/277486/mod_resource/content/1/Dumitrescu-WCSP-ITOR-2001.pdf>
Reference treatment of the constrained SP formulation `min travel time s.t. risk ≤ B`,
with Lagrangian relaxation and preprocessing-based node/edge elimination. Relevant because
a **budget** formulation ("never exceed this much flood exposure") is often more
interpretable to a user — and to an LLM explainer — than a λ trade-off weight.

**[11] Ahmadi, Tack, Harabor, Kilby (2021). "A Fast Exact Algorithm for the Resource
Constrained Shortest Path Problem."** AAAI 2021.
<https://cdn.aaai.org/ojs/17450/17450-13-20944-1-2-20210518.pdf>
Modern, fast exact RCSP via bidirectional A* with path-dominance pruning; orders of
magnitude faster than earlier exact methods on road-network instances. If CityPulse wants
the budget formulation of [10] at interactive speed, this is the algorithm to implement.

### 2.3 Speedup techniques under changing weights

**[12] Dibbelt, Strasser, Wagner (2016). "Customizable Contraction Hierarchies."**
*ACM Journal of Experimental Algorithmics* 21(1), Article 1.5. DOI 10.1145/2886843.
arXiv:1402.0402. <https://arxiv.org/abs/1402.0402> ·
<https://dl.acm.org/doi/abs/10.1145/2886843>
Splits CH preprocessing into a **metric-independent** phase (contraction order from nested
dissection; the graph's separator structure, which never changes) and a cheap
**metric-dependent customisation** phase run whenever weights change. This is the correct
theoretical answer to "the hazard map just changed." Directly designed "for scenarios with
frequently changing edge weights" (authors' framing).

**[13] Bläsius, Buchhold, Wagner, Zeitz, Zündorf (2025). "Customizable Contraction
Hierarchies — A Survey."** arXiv:2502.10519.
<https://arxiv.org/abs/2502.10519>
Current state of the art in CCH engineering: a clean reference implementation, consolidated
recent advances, and performance improvements. The right source for implementation detail
if CityPulse builds its own CCH. Note this is a 2025 preprint — check for a peer-reviewed
version before citing in the final paper.

**[14] Delling, Goldberg, Pajor, Werneck (2017). "Customizable Route Planning in Road
Networks."** *Transportation Science* 51(2), 566–591. DOI 10.1287/trsc.2014.0579.
<https://pubsonline.informs.org/doi/10.1287/trsc.2014.0579> · preprint:
<https://www.microsoft.com/en-us/research/wp-content/uploads/2013/01/crp_web_130724.pdf>
**CRP** = multilevel overlay on a metric-independent partition; recustomisation for a new
metric is seconds on continental graphs, and only *cells containing changed edges* need
recomputation. This is the algorithm behind OSRM's MLD pipeline and (in spirit) Bing Maps.
*(INFORMS blocks automated fetch; verified via search index + the Microsoft Research
preprint, which is the same work.)*

**[15] Strasser, Wagner, Zeitz (2021). "Space-Efficient, Fast and Exact Routing in
Time-Dependent Road Networks" (CATCHUp).** *Algorithms* 14(3), 90. DOI 10.3390/a14030090.
Also ESA 2020, LIPIcs 173:81. <https://www.mdpi.com/1999-4893/14/3/90> ·
<https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ESA.2020.81>
Solves the memory blow-up of Time-Dependent CH by storing **shortcut paths instead of
shortcut travel-time functions**, computing travel times lazily. Reduces preprocessing to
minutes on continental instances with tens of millions of nodes. The reference point if
CityPulse ever wants genuinely time-dependent (not just currently-hazard-adjusted) routing.

**[16] "Optimized Customizable Route Planning in Large Road Networks with Batch
Processing" (2026).** arXiv:2604.10608; journal version *Future Transportation* 6(4), 134,
DOI 10.3390/futuretransp6040134.
<https://arxiv.org/abs/2604.10608>
Recent engineering work on customizable hierarchies; notably reports that **CCH now
dominates CRP on query performance**, and that batching queries exploits 95–99% subpath
overlap for order-of-magnitude speedups. Useful if CityPulse ever needs many-to-many
(e.g. "which of my meaningful locations is safest" in Haven Mode) — batch there, don't loop.

### 2.4 Flood / hazard-specific

**[17] Pregnolato, Ford, Wilkinson, Dawson (2017). "The Impact of Flooding on Road
Transport: A Depth-Disruption Function."** *Transportation Research Part D* 55, 67–81.
DOI 10.1016/j.trd.2017.06.020. <https://www.sciencedirect.com/science/article/pii/S1361920916308367>
· <https://eprints.ncl.ac.uk/239618>
**The single most important paper for CityPulse's cost function.** Derives an empirical
quadratic relating standing-water depth to safe vehicle speed (R² = 0.95) from video
footage plus literature synthesis, explicitly replacing the binary "open/closed" assumption
that dominates flood-transport modelling, and validates on the 28 June 2012 Newcastle
flood. This gives CityPulse a *physically grounded* hazard→cost transfer function instead
of an invented multiplier. **[UNVERIFIED DETAIL]** The widely-quoted coefficient form
`v = 0.0009h² − 0.5529h + 86.9448` (h in mm, v in km/h, valid to ~300 mm) appears in
secondary sources; confirm against the PDF before publishing it.

**[18] Li, Jiang, Chen, Lam, Xia, Ahmadian (2025). "An Overview of Flood Evacuation
Planning: Models, Methods, and Future Directions."** *Journal of Hydrology* 656, 133026.
DOI 10.1016/j.jhydrol.2025.133026.
<https://www.sciencedirect.com/science/article/pii/S0022169425003646> ·
<https://orca.cardiff.ac.uk/id/eprint/177049/>
Current survey spanning flood simulation, hazard assessment, shelter siting, route
generation and evacuee movement models. Confirms that **metaheuristics (GA/ACO) dominate
the flood evacuation routing literature** — which is a weakness, not a strength: these
papers rarely benchmark against exact methods and rarely run at interactive latency.
CityPulse can differentiate simply by being exact and real-time.

**[19] Liang, Liu, Zhang, Yang (2025). "Shortest Path Planning and Dynamic Rescue Forces
Dispatching for Urban Flood Disasters."** *Scientific Reports* 15, 23643.
DOI 10.1038/s41598-025-06374-2. <https://www.nature.com/articles/s41598-025-06374-2>
Customised A* with a domain-specific admissible heuristic (an "estimated time cost
function" tighter than Euclidean/v_max), over a time-dependent speed decay model
`v_ij(t) = v₀(1 − α − γ)·exp(−βt)` where α, β capture spatial/temporal flood impact and γ
baseline congestion. Closest published analogue to CityPulse's core routing step — and a
useful demonstration that a hand-built exponential decay is *accepted practice*, though
Pregnolato [17] is better grounded.

**[20] Zhou, Zheng, Liu, Xie, Wan (2022). "Flood Impacts on Urban Road Connectivity in
Southern China."** *Scientific Reports* 12, 16866. DOI 10.1038/s41598-022-20882-5.
<https://www.nature.com/articles/s41598-022-20882-5>
Coupled MIKE Urban (1-D drainage) + MIKE 21 (2-D surface) hydrodynamics over Shatian Town,
Guangdong. Finds >40% loss of road connectivity at a 1-in-100-year rainfall, with a sharp
non-linear threshold around the 20-year return period, and classifies segments impassable
above **0.15 m** depth. Also validates using citizen-science smartphone depth photos —
a directly reusable data-collection pattern for Chennai.

**[21] Karagiorgos et al. (2026). "Non-Linear Failure Patterns in Urban Road Networks
Exposed to Flooding."** *PLOS ONE*, DOI 10.1371/journal.pone.0354204.
<https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0354204>
Karlstad, Sweden, under 100-year and 10,000-year floods: travel time +120% / +170%; network
fragments into 3 major components plus 263 / 553 isolated clusters; mean degree falls
2.38 → 2.09 → 1.81; closeness-centrality distribution goes bimodal ("islands of
accessibility"). **The quantitative justification for CityPulse existing**: flood disruption
is non-linear and fragmenting, so naive routing fails abruptly rather than degrading
gracefully.

**[22] "Routing Optimization Framework for Exploring Time-Varying Urban Road Network
Vulnerability under Floods."** *ASCE Journal of Infrastructure Systems* 32(2).
DOI 10.1061/JITSE4.ISENG-2788. <https://ascelibrary.org/doi/10.1061/JITSE4.ISENG-2788>
Frames flood vulnerability as *time-varying* and couples it to routing rather than to
static connectivity metrics. **[UNVERIFIED DETAIL]** ASCE returned HTTP 403 to automated
fetch; I have the title/venue/DOI from indexing but have **not** read the abstract. Verify
authors and content before citing.

### 2.5 Signal quality, confidence and learning

**[23] Senarath, Nannapaneni, et al. (2020). "Emergency Incident Detection from
Crowdsourced Waze Data Using Bayesian Information Fusion."** arXiv:2011.05440;
IEEE/WIC/ACM Web Intelligence (WI-IAT) 2021, DOI 10.1109/WIIAT50758.2020.00013.
<https://arxiv.org/abs/2011.05440> · <https://ieeexplore.ieee.org/document/9457694/>
Bayesian framework modelling **(a) the reliability of individual crowd reporters and
(b) spatio-temporal uncertainty in report location/time**, fused to detect real incidents;
evaluated on Nashville, TN, beating baselines on F1 and AUC. This is the closest existing
formalisation of CityPulse's "confidence decay" idea — and note that it stops at
*detection*. **Nobody has carried the posterior forward into the routing cost function and
measured route quality.** That gap is CityPulse's opening (§8.1).

**[24] Pham, Narasimhamurthy, Mehran, Manley, Ashraf (2025). "Reinforcement Learning Based
Estimation of Shortest Paths in Dynamically Changing Transportation Networks."**
*Frontiers in Future Transportation*, DOI 10.3389/ffutr.2025.1524232.
<https://www.frontiersin.org/journals/future-transportation/articles/10.3389/ffutr.2025.1524232/full>
Q-routing achieves near-Dijkstra route costs on dynamic networks without prior knowledge of
link costs. Crucially, it reports that **A*'s heuristic ceases to be admissible once link
costs become dynamic**, producing worse routes than both Dijkstra and Q-routing. This is an
important caution — and §6.3 explains precisely why it does *not* apply to CityPulse
(their costs can decrease; CityPulse's hazard term only ever increases cost above free-flow).

**[25] Xue, Zhao, Qi, Zeng, Yu (2026). "Resilient Routing: Risk-Aware Dynamic Routing in
Smart Logistics via Spatiotemporal Graph Learning."** arXiv:2601.13632.
<https://arxiv.org/abs/2601.13632>
Predicts congestion risk with a spatiotemporal GNN, then routes on
`W_dyn(u,v) = dist(u,v) · (1 + λ · Risk_avg)` — *exactly* the multiplicative form in the
CityPulse brief. Reported case study: +2.1% distance buys −17.6% risk exposure. Useful as
(i) evidence that the multiplicative penalty is live in the current literature, and
(ii) a cautionary example: it uses a *point estimate* of risk with no uncertainty term,
which is the defect CityPulse should fix (§5.4).

### 2.6 Engine documentation (primary sources)

**[26] Project-OSRM. "Traffic" (wiki).**
<https://github.com/Project-OSRM/osrm-backend/wiki/Traffic>
OSRM accepts live speeds as **CSV segment-speed files**. CH pipeline requires re-running
`osrm-contract --segment-speed-file`; MLD pipeline requires `osrm-customize`, and the docs
state MLD "calculates routes more slowly than CH, but traffic imports are significantly
faster." Data reload requires restarting `osrm-routed` or using the shared-memory datastore.

**[27] Project-OSRM issue #5503, "Any Advice to Shorten Traffic Update Interval."**
<https://github.com/Project-OSRM/osrm-backend/issues/5503>
Concrete operational numbers: `osrm-customize` ≈ **10 minutes** for North America on an AWS
r5.2xlarge; the reporter's achievable traffic update cadence is **20 minutes**, against a
desired 2–3 minutes; "Cells customization took 379.771 seconds." No maintainer solution in
thread; the requested features (recustomise only affected cells; accept delta updates)
remain unimplemented. **This is the decisive evidence that OSRM is a batch-update engine.**

**[28] Valhalla docs — "Dynamic costing."**
<https://valhalla.github.io/valhalla/concepts/costing/dynamic-costing/>
"Rather than baking costs into the routing graph data, Valhalla uses dynamic, run-time
costing to generate costs based on a rich set of attributes stored in the routing tiles."
Per-request costing options, edge costing and transition (turn) costing, all applied to the
same tiles with no re-preprocessing.

**[29] Valhalla docs — "Speed information."**
<https://valhalla.github.io/valhalla/concepts/speeds/>
Valhalla resolves edge speed in priority order: **live traffic → predicted (historical,
weekly profiles in 5-minute buckets) → constrained flow (07:00–19:00) → free flow (night)
→ base tile speed.** Live traffic arrives as a separate overlay `traffic.tar` of
`TrafficSpeed` records (configured via `mjolnir.traffic_extract`), produced externally.
Update *frequency* is not specified in the docs — a real gap (§7.3).

**[30] Valhalla discussion #4746, "How would Valhalla be used on a mobile device?" plus
`Rallista/valhalla-mobile`.**
<https://github.com/valhalla/valhalla/discussions/4746> ·
<https://github.com/Rallista/valhalla-mobile>
Maintainer guidance: build tiles **server-side**, ship them to the client, and instantiate
Valhalla in-process via a thin C++ wrapper — no HTTP server on device. On-device tile
*generation* is "extremely resource-intensive" (needs admin DB, timezone data, elevation)
and is not recommended. `valhalla-mobile` provides iOS/Android builds exposing the route
function over a downloaded pre-parsed tileset. **This is a working offline-routing path.**

**[31] GraphHopper docs — "Custom models."**
<https://github.com/graphhopper/graphhopper/blob/master/docs/core/custom-models.md>
JSON rule language modifying `speed` (`multiply_by`, `limit_to`), `priority`,
`distance_influence` and turn costs at request time. Two constraints matter: arbitrary
request-time custom models need `ch.disable=true` (i.e. flexible/landmark mode, not CH),
and the rules can only read **encoded values already baked into the graph** — there is no
documented per-edge live-value injection path.

### 2.7 Benchmarks and simulation

**[32] 9th DIMACS Implementation Challenge — Shortest Paths (2006).**
<http://www.diag.uniroma1.it/challenge9/download.shtml> ·
<http://users.diag.uniroma1.it/challenge9/data/tiger/>
The standard road-network benchmark family (USA-road-d/USA-road-t, full USA ≈ 24M nodes,
plus TIGER/Line extracts). Every paper in §2.3 reports on these. Use them to validate your
CCH/ALT implementation's correctness and speed before pointing it at Chennai.

**[33] Eclipse SUMO** (<https://eclipse.dev/sumo/>) and **MATSim** (<https://matsim.org/>).
The two open microscopic/agent-based traffic simulators used throughout the evacuation and
flood-disruption literature; MATSim has an established large-scale emergency-egress
extension (used for the Padang tsunami evacuation study). For CityPulse these are the only
credible route to a **counterfactual** evaluation: you cannot flood Chennai to test, so you
simulate agents on a hazard-perturbed network and compare routing policies.

---

## 3. Where the literature actually stands (critical reading)

**Multi-objective is theoretically right and practically avoided.** True Pareto
label-setting (Martins-style) returns the full non-dominated set, but the set can be
exponential and the constants are brutal on road networks. Almost every deployed system
scalarises. You should scalarise too — but you should *know* that weighted-sum
scalarisation recovers only **supported** Pareto points (those on the convex hull of the
objective space). Routes in non-convex pockets of the trade-off curve are unreachable by
any λ. If a "moderately slower, dramatically safer" route exists in such a pocket, a λ
sweep will never surface it. The ε-constraint / budget formulation [10][11] does not have
this blind spot. **This is a real, citable limitation you should state rather than hide.**

**The flood-routing literature is methodologically weak.** [18] confirms metaheuristics
dominate. These papers typically: (a) use a GA/ACO where an exact polynomial algorithm
exists, (b) do not report query latency, (c) evaluate on a single synthetic scenario,
(d) have no baseline beyond "unmodified Dijkstra." Two exceptions worth respecting are [19]
(exact A* with a justified heuristic) and [17] (empirically grounded physics). CityPulse
can clear this bar easily; it should say so plainly in the paper and not overclaim novelty
on "we used A*."

**Risk measures: expectation is not enough, but CVaR may be overkill here.** [7][8] are
right that tail behaviour is what matters for emergency response. But CVaR needs a
*distribution over consequence*, and CityPulse's dominant uncertainty is binary
(is the underpass flooded or not?) with an uncertain probability. The honest intermediate
is a **chance constraint plus a pessimistic plug-in estimate** (§5) — cheaper, defensible,
and explainable to a user, which matters because the whole product thesis is explanation.

**Dynamic-weight handling is solved on paper and unsolved in shipped OSS.** CCH [12][13]
and CRP [14] are exactly the right structures, and [14] explicitly supports recustomising
only the cells that changed. Yet [27] shows that the most widely deployed OSS implementation
of that idea (OSRM MLD) exposes only a **full, file-driven, batch** recustomisation and a
process restart. The gap between the algorithms literature and the available engines is the
main engineering risk in this project.

---

## 4. Routing under uncertainty — what each model buys you

| Model | Assumes | Gives you | Cost | Fit for CityPulse |
|---|---|---|---|---|
| TDSP (FIFO) [3] | τ(e,t) known, non-overtaking | departure-time-aware optimal path | ≈ Dijkstra | **Yes** — use for the time axis |
| Stochastic SP / reliability [8] | known travel-time distributions | P(on-time) maximising path | label-correcting, heavier | Aspirational; you lack the data |
| Robust / min-max regret | interval bounds only | worst-case guarantee | NP-hard in general | Overkill; too conservative |
| CVaR [7] | known consequence distribution | tail control, tunable α | nested TDSP × VaR search | Good future work |
| MDP / adaptive [B6] | transition model known | optimal *policy*, reroutes en route | state-space explosion | Conceptually right, not in 7 weeks |
| CTP [9] | edges revealed on arrival | — (PSPACE-complete) | — | Cite as the honest hardness result |

**The pragmatic synthesis:** CityPulse should do TDSP on a *pessimistic point estimate*, and
re-plan on each new hazard signal. That is a receding-horizon (MPC-style) approximation to
the MDP. Say that explicitly in the paper — it is a principled framing, not a compromise.

---

## 5. Recommended formulation for CityPulse

### 5.1 Notation

Directed road graph `G = (V, E)`. For edge `e ∈ E` at wall-clock time `t`:

- `ℓ(e)` — length (m); `v_free(e)` — free-flow speed (m/s); `τ₀(e,t)` — baseline travel
  time (s), either `ℓ(e)/v_free(e)` or a time-of-day profile.
- `h(e,t)` — hazard *intensity* (for flooding, water depth in mm; per-class otherwise).
- `s(e,t) ∈ [0,1]` — hazard *severity* (normalised harm potential, per hazard class).
- `p(e,t) ∈ [0,1]` — posterior probability that the hazard is actually present.
- `n_eff(e,t) ≥ 0` — effective evidence count backing that posterior.

### 5.2 Step 1 — Confidence as a Bayesian posterior, not a multiplier

The brief treats "confidence" `C` as a scalar that decays with signal age. Model it instead
as a **posterior with a variance**, which is both more principled and strictly more useful.

Reports `r_1 … r_k` arrive with timestamps `t_i`, locations `x_i`, source classes `c_i`
(municipal sensor, verified responder, anonymous crowd report), and polarity
`y_i ∈ {+1 (hazard), −1 (clear)}`. Fuse in log-odds with exponential temporal decay:

```
                        k
  ℓ(e,t) = ℓ₀(e)  +    Σ   y_i · κ( d(e, x_i) ) · exp( −(t − t_i) / T_c ) · logit( α_{c_i} )
                       i=1

  p̄(e,t) = σ( ℓ(e,t) ) = 1 / (1 + e^{−ℓ(e,t)})
```

- `ℓ₀(e)` — **static prior log-odds** from terrain: elevation, HAND (Height Above Nearest
  Drainage), distance to stormwater drain, historical inundation. Precomputable offline.
  *This is what makes the offline mode non-trivial rather than a cached-route fallback.*
- `α_c ∈ (0.5, 1)` — reliability of source class `c`; `logit(α_c)` is its evidence weight.
  A municipal depth sensor might carry `α = 0.97`; a single anonymous report `α = 0.60`.
- `κ(d)` — spatial kernel (e.g. `exp(−d²/2σ²)`), attributing a point report to nearby edges.
- `T_c` — **per-hazard-class decay time constant**. Flash flood minutes–an hour; a fallen
  tree, days. This is the brief's "decay score", now with a defensible functional form.

Evidence mass (used for uncertainty, not for the mean):

```
  n_eff(e,t) = Σ_i κ( d(e, x_i) ) · exp( −(t − t_i) / T_c )
```

### 5.3 Step 2 — Pessimistic plug-in (the key design decision)

Take an **upper confidence bound** on hazard probability rather than the posterior mean:

```
  p̃(e,t) = min{ 1 ,  p̄(e,t) + z · sqrt( p̄(1 − p̄) / (n_eff + 1) ) }
```

with `z` the pessimism level (e.g. `z = 1.28` ≈ 90th percentile; `z = 1.96` ≈ 95th).

**Why this, and why it is the most important change to the brief's formula.** In the
proposed `w = τ·(1 + λ·R·C)`, low confidence `C → 0` drives the penalty to zero: the router
treats an unconfirmed flood report *as if the road were clear*. That is risk-seeking under
ambiguity, and for an ambulance it is the wrong sign. Here, low `n_eff` **widens** the
bound and **raises** the penalty. Uncertainty makes the router more cautious, not less.
This is standard pessimism-under-uncertainty from robust MDPs, and it is directly
explainable to a user: *"one unverified report, so we routed around it to be safe."*

Set `z` per user class: `z ≈ 0` for a commuter who resents detours; `z ≈ 2` for an
ambulance that cannot afford to be wrong. **This single parameter is a clean, defensible
product differentiator.**

### 5.4 Step 3 — Two physically distinct effects, two terms

A flooded road does two different things: it **slows you down**, and it **might harm you**.
Collapsing both into one multiplier (as [25] and the brief both do) loses the distinction
and makes λ uninterpretable. Separate them.

**(a) Expected hazard-adjusted travel time.** Let `δ(e,t) ≥ 1` be the slowdown multiplier
from the depth–disruption function [17]:

```
  δ(e,t) = v_free(e) / v_safe( h(e,t) )          with  v_safe(·)  from Pregnolato et al.
```

Then

```
  τ̂(e,t) = τ₀(e,t) · [ 1 + p̃(e,t) · ( δ(e,t) − 1 ) ]
```

i.e. the free-flow time, inflated in proportion to how likely the hazard is *and* how much
it slows traffic. When `p̃ = 0` or `δ = 1`, `τ̂ = τ₀` exactly.

**(b) Harm exposure.** Following the hazmat convention [5][6] that risk is an exposure
integral along the path:

```
  X(e,t) = p̃(e,t) · s(e,t) · τ₀(e,t)
```

— probability of hazard × severity × **time spent inside it**. Length-scaling matters: a
2 km flooded stretch is worse than a 50 m one at equal depth, and a per-edge flat penalty
would not capture that.

**(c) Combined edge cost.**

```
  ┌─────────────────────────────────────────────────────────────────────────┐
  │   w_λ(e, t)  =  τ₀(e,t) · [ 1 + p̃(e,t)·( δ(e,t) − 1 ) ]                │
  │                 +  λ · p̃(e,t) · s(e,t) · τ₀(e,t)                       │
  │                                                                          │
  │   subject to the hard feasibility constraint                            │
  │                                                                          │
  │       Pr[ h(e,t) > h_max(mode) ]  ≤  ε          (else  w_λ = +∞)        │
  └─────────────────────────────────────────────────────────────────────────┘
```

Everything is in **seconds**, including the risk term: `λ` has units of
seconds-of-detour-accepted per second-of-severity-1-exposure. That makes λ *explainable* —
"we will accept up to 3 extra minutes to avoid 1 minute of full-severity exposure" — which
matters enormously for the natural-language explanation layer.

The chance constraint is what handles genuine impassability. Do **not** encode "road is
closed" as a very large finite weight: a large weight still lets the solver choose the road
when every alternative is worse, which is precisely the failure you must avoid. Use `+∞`
(edge removal) and, if the graph disconnects, report *"no safe route exists"* — a legitimate
and honest output that consumer navigation apps never give. `h_max` is vehicle-mode
specific: ~150 mm for a car per [20]; ~300 mm is the upper validity limit of [17];
a fire appliance tolerates more.

### 5.5 Step 4 — λ as a deliberate product surface

Solve for three values of λ per request — `λ_fast = 0`, `λ_balanced`, `λ_safe` — and return
three routes with their `(Σ τ̂, Σ X)` pairs. This costs three queries (tens of milliseconds
at city scale), and it gives the LLM explainer something *concrete and quantitative* to
talk about:

> "The fast route crosses two underpasses with an 80% chance of standing water.
>  The recommended route adds 4 minutes and avoids both."

That is a far better product than a single opaque route, and it also honestly surfaces the
trade-off the weighted-sum scalarisation is making.

### 5.6 Why this over the alternatives

| Alternative | Why not (for CityPulse, now) |
|---|---|
| Brief's `τ·(1 + λ·R·C)` | Uncertainty is risk-*seeking* (§5.3). R and C are not separately identifiable from data — you estimate one posterior, so multiplying them double-counts. Cannot express hard impassability. Conflates slowdown with harm. |
| Pure multi-objective Pareto | Correct but expensive; Pareto set can be exponential; you would ship a set nobody reads. The 3-λ sweep is 90% of the value at 1% of the cost. |
| CVaR [7] | Right risk measure *if* you have a consequence distribution. You have a Bernoulli hazard with an uncertain parameter. The UCB plug-in is the cheap, honest approximation. **Flag CVaR as future work — it is a genuine improvement, not a strawman.** |
| RCSP budget [10][11] | Genuinely better than weighted sum for reaching non-supported Pareto points, and more interpretable ("stay under 60 s of exposure"). **Worth implementing if time allows** — it is the strongest single upgrade to this design. |
| RL / Q-routing [24] | Needs vastly more interaction data than a 7-week project generates; no admissibility guarantee; and the explanation story becomes much harder. Do not do this. |
| Full MDP / POMDP | Correct model of the true problem, computationally infeasible at city scale on a phone. Approximate it by receding-horizon replanning (§4). |

### 5.7 FIFO check (do not skip this)

Dijkstra correctness on the time-dependent cost requires FIFO: departing later must never
arrive earlier. Because `p̃`, `δ` and `s` all evolve with `t` independently of the traveller,
`τ̂(e,t)` can in principle violate FIFO when a hazard clears sharply. Two options:
(i) enforce a Lipschitz bound `|∂τ̂/∂t| < 1` by smoothing hazard onset/decay — the
exponential decay in §5.2 helps; (ii) freeze the hazard state at query time (evaluate all
edges at `t = t_departure`) and rely on replanning. **For the demo, option (ii) is correct,
simpler, and defensible** — say so explicitly rather than leaving it implicit.

---

## 6. Dynamic edge weights at scale — what actually tolerates hazard updates

### 6.1 The invalidation rules

| Technique | Preprocessing | Survives weight **increase**? | Survives weight **decrease**? | Update granularity |
|---|---|---|---|---|
| Dijkstra / bidirectional | none | yes (trivially) | yes | per-query |
| **A\* / ALT** [2] | landmark distances on a lower-bound metric | **YES — potentials stay admissible** | **No** — potentials may overestimate | per-query |
| CH [1] | full contraction (~minutes–hours) | **No** — shortcuts become too cheap → wrong answers | No — shortcuts too expensive → suboptimal | full re-contraction |
| **CCH** [12][13] | metric-independent order (expensive, once) + metric customisation (cheap) | yes, after customisation | yes, after customisation | **recustomise; cell-local possible** |
| **CRP / MLD** [14] | metric-independent partition + overlay customisation | yes, after customisation | yes, after customisation | **only cells containing changed edges** |
| CATCHUp / TCH [15] | time-dependent, path-based shortcuts | requires recustomisation | requires recustomisation | minutes on continental graphs |

### 6.2 Why CH is disqualified and CCH/CRP is the textbook answer

A CH shortcut `(u,w)` stores the weight of the contracted path `u→v→w`. Raise `w(u,v)` and
the stored shortcut is now *cheaper than reality*, so the query returns a path whose true
cost is higher than reported — silently **incorrect**, not merely suboptimal. Lower an edge
weight and the shortcut is too expensive, so a genuinely better path is missed. Either way,
CH must be rebuilt. CCH and CRP fix this by making the hierarchy (the separator / nested
dissection structure) **metric-independent**: geometry of the road network does not change
when a road floods, so only the numbers attached to it need recomputing [12][14].

### 6.3 The simplification the literature under-emphasises — and CityPulse's best trick

**CityPulse's hazard term only ever *increases* cost above free-flow.** Inspect §5.4:
`δ ≥ 1`, `p̃ ≥ 0`, `s ≥ 0`, `λ ≥ 0`, therefore

```
        w_λ(e, t)  ≥  τ_free(e)        for all  e, t, λ ≥ 0.
```

Consequently, **ALT potentials precomputed once on the hazard-free free-flow metric remain
admissible forever, under every possible hazard configuration.** Landmark preprocessing
never needs to be rerun. Hazards can appear, intensify, decay, and vanish; the A* heuristic
stays valid and the search stays correct.

This directly answers — and inverts — the caution in [24], which found A* losing
admissibility on dynamic networks: *their* costs could fall below the value the heuristic
was built on; CityPulse's cannot. This is a small theoretical observation with a large
engineering payoff, it is exactly the kind of result that fits a student paper, and **I have
not found it stated in the hazard-routing literature.** Worth writing up.

The same monotonicity means a **hazard-free CH** built once on `τ_free` yields a valid
lower-bound potential too, if you prefer CH-based `A*` potentials to landmarks.

### 6.4 Scale reality check

Chennai's drivable OSM network is on the order of **10⁵ nodes** (Geofabrik Southern Zone
extract, clipped to Greater Chennai Corporation). Continental instances in [1][12][14][15]
are 10⁷–10⁸. Rough expectations at 10⁵ nodes on a mid-range phone:

- Bidirectional Dijkstra, free-flow: **~10–40 ms**
- ALT-accelerated A*: **~2–10 ms**
- CCH customisation of the *entire* metric: **order of 10²–10³ ms** *(extrapolated from
  published continental figures; **must be measured, not assumed** — I have not found
  mobile-SoC CCH benchmarks in the literature, see §8.4)*

**Therefore: do not build CCH for the demo.** ALT + bidirectional A* on a mutable weight
array is sufficient, far simpler, and has the correctness property in §6.3 for free. Reach
for CCH only if profiling shows you need it, or if you extend to a metropolitan-region
graph. Presenting this as a measured, justified decision is stronger science than
implementing CCH because the survey papers do.

---

## 7. Engine reality check: OSRM vs. GraphHopper vs. Valhalla

| Capability | **OSRM** | **GraphHopper** | **Valhalla** |
|---|---|---|---|
| Live per-edge weight updates | CSV segment-speed file + full `osrm-customize` (MLD) or `osrm-contract` (CH), then process restart / datastore reload [26] | No documented live per-edge injection path; custom models read only pre-baked encoded values [31] | **`traffic.tar` live-speed overlay of `TrafficSpeed` records, highest priority in speed resolution** [29] |
| Update latency, real numbers | **~10 min customise (N. America); ~20 min achieved cadence; no partial/delta recustomisation** [27] | n/a | Overlay is an external artefact swapped in; cadence **not documented** [29] |
| Per-request cost model | **No** — cost model baked into Lua profile at extract time | **Yes** — JSON custom models, but arbitrary models need `ch.disable=true` (flexible/LM mode) [31] | **Yes, by design** — "rather than baking costs into the routing graph data, Valhalla uses dynamic, run-time costing" [28] |
| Time-dependent / historical speeds | limited | limited | **Yes** — weekly predicted profiles in 5-min buckets, plus constrained/free-flow [29] |
| Embedded / offline on mobile | No official mobile build | JVM; Android historically possible — **current support status uncertain, verify** | **Yes** — server-built tiles shipped to device, in-process C++ wrapper; `Rallista/valhalla-mobile` provides iOS/Android builds [30] |
| Query speed | fastest (CH) | fast (CH) / moderate (flexible) | slowest of the three |
| Language / FFI from Flutter | C++ (no mobile build) | Java (platform channel) | **C++ (`dart:ffi`)** |

### 7.1 Verdict — and it contradicts the brief

**The brief's "OSRM or GraphHopper" is the wrong pair.** Both fail CityPulse's two defining
requirements simultaneously. OSRM is a **batch-update** engine: [27] is direct evidence
from users trying and failing to get below a 20-minute traffic cycle, with no partial
recustomisation available. A system whose pitch is "a 2-minute-old flood report" cannot sit
on a 20-minute update cycle. GraphHopper has the best request-time cost-model ergonomics of
the three, but no documented way to push live per-edge hazard values into the graph, and it
gives up CH when you use arbitrary custom models anyway.

**Valhalla is the only one of the three that offers all of:** request-time cost model [28],
an in-place per-edge live-speed overlay [29], and a real embedded offline mobile story [30].

### 7.2 But the stronger recommendation: don't route through a black box at all

For a 7-week research project whose *contribution is the cost function*, wrapping a routing
engine is the wrong architecture. Every engine will fight you at exactly the point you care
about (injecting a per-edge, per-request, uncertainty-aware cost), and none of them will let
you publish the mechanism cleanly.

**Recommended split:**

- **Own the graph and the search.** Extract OSM → compact CSR adjacency (~10⁵ nodes) →
  your own ALT + bidirectional A* over a mutable `float[] hazard_multiplier` array. This is
  perhaps 600–1200 lines of code, is fully under your control, is the thing you publish, and
  ports to Dart/Rust/C++ for on-device use with no engine dependency.
- **Use Valhalla (or OSRM) as a utility service** for map matching, route geometry
  simplification, and turn-by-turn instruction generation — the boring, well-solved parts you
  should not reimplement.

Be honest in the paper about the trade-off: you lose turn restrictions, lane guidance and
years of OSM-tag edge cases, and you should say so.

### 7.3 Known unknowns on the engine side

- Valhalla's live-traffic update cadence is **not documented** [29]; tooling around
  `traffic.tar` has visibly churned (see valhalla issues #5006, #5062, and the community
  `alinmindroc/valhalla_traffic_poc` repo, which exists precisely because the official path
  is under-documented). **Prototype this in week 1 before committing.**
- GraphHopper's current Android/embedded support status — I did **not** verify this and
  should not be trusted on it. Check before relying on it.
- Whether Valhalla's live overlay can be updated in place in a memory-mapped file without
  a restart: strongly implied by the architecture, **not confirmed in docs**. Verify.

---

## 8. What is genuinely open

Ranked by (novelty × tractability in 7 weeks).

### 8.1 Calibrated confidence-decay feeding a routing cost — and being evaluated
The Bayesian-fusion work on crowd reports [23] stops at **detection**. The routing
literature takes hazard state as given. **Nobody closes the loop**: estimate a posterior
with a decay model, push it through a cost function, and then ask whether the resulting
*routes* were better. The open questions are sharp and answerable:
- Is `p̄(e,t)` **calibrated**? (Reliability diagram: of edges assigned p̄ ≈ 0.7, were ~70%
  actually impassable?) I found no paper that does this for hazard routing.
- What are the correct decay constants `T_c` per hazard class? Everyone hand-waves an
  exponential; **nobody fits `T_c` to data.** Fitting it for Chennai flooding, even crudely,
  is a publishable contribution.
- Does pessimism (`z > 0`) actually improve realised outcomes, or just add detours?
**This is the strongest novelty candidate and it is squarely inside the brief's own pitch.**

### 8.2 Route stability under streaming hazard updates
Every dynamic-SP paper optimises *recomputation latency*. None optimise **route churn**. A
driver rerouted every 30 seconds as reports trickle in has a useless product. There is no
formal treatment of a switching cost in hazard-driven rerouting. A concrete contribution:
add a hysteresis term — only re-issue a route if the new route improves cost by more than a
margin `μ`, or penalise deviation from the committed path — and characterise the
stability/optimality trade-off empirically. Small, well-defined, novel, demoable.

### 8.3 Routing objectives that are constrained to be *explainable*
The project's differentiator is explanation, but the literature has **nothing** on
optimising for explainability. Speculative but genuinely open: define a route's explanation
complexity (number of distinct hazard reasons, number of deviations from the fastest path)
and solve `min cost s.t. explanation complexity ≤ k`. A route that avoids five hazards for
marginal gain is worse-as-a-product than one that avoids the two that matter. I am not aware
of *any* prior work on this; I am also not certain it is tractable, so treat it as a stretch.

### 8.4 On-device budgets for customizable hierarchies
No published CCH/CRP customisation benchmarks on mobile SoCs under thermal and battery
constraints. The entire speedup-technique literature assumes a server. Measuring CCH
customisation on a mid-range Android device across city-sized graphs would be a small,
clean, useful empirical contribution — and you need the numbers anyway.

### 8.5 Distributionally-robust SP under epistemic uncertainty
CVaR [7] and robust SP assume the distribution (or its support) is known. CityPulse's
distribution *parameters* are themselves uncertain from sparse crowd evidence — cell B7 of
§1. Distributionally-robust optimisation exists and has not, as far as I found, been applied
to crowdsourced-hazard routing. Theoretically the most interesting gap; **almost certainly
too much for 7 weeks.** Name it as future work.

### 8.6 There is no benchmark, and building one may be the biggest contribution
Each flood-routing paper invents a city, a hydrodynamic model, and a ground truth [18][19]
[20][21]. Results are mutually incomparable. A released **Chennai hazard-routing benchmark**
— OSM snapshot + timestamped hazard event log + observed closures + a SUMO scenario + a
scoring script — would be cited by every subsequent paper in this niche and is genuinely
achievable in 7 weeks. It may well outlive the algorithm.

### 8.7 Honest non-novelties
State these plainly rather than letting a reviewer find them:
- "Hazard-aware A*" is not novel — [19] is 2025 and does essentially that.
- `w = d·(1 + λ·Risk)` is not novel — [25] is contemporaneous and identical in form.
- Depth→speed cost modulation is not novel — [17] is from 2017.
- "Offline routing on a phone" is not novel — OsmAnd and Organic Maps ship it.
The novelty is the **confidence-aware, pessimism-calibrated cost** and the **evaluation**,
not the search algorithm. Claim precisely that.

---

## 9. Engineering implications — concrete recommendations

### 9.1 Algorithm
1. **Bidirectional A\* with ALT potentials** on the free-flow metric. 16 landmarks, avoid
   selection. ~2–10 ms at city scale.
2. **Hazard costs live in a mutable `float32[|E|]` array**, recomputed lazily per edge on
   relaxation from the hazard index. No preprocessing invalidation ever (§6.3).
3. **Three λ values per request** (`0`, balanced, safe) → three routes + their
   `(Σ τ̂, Σ X)` pairs, handed to the explainer.
4. **Chance constraint as hard edge removal**, not a large finite weight. Report *"no safe
   route"* when the graph disconnects — an honest output that differentiates the product.
5. **Hysteresis on rerouting** (§8.2): re-issue only on improvement > μ. Set μ ≈ 60 s
   initially and tune.
6. **Freeze hazard state at query time** for FIFO safety (§5.7); rely on replanning for the
   time axis.
7. Defer CCH, CVaR, RCSP and RL. Name each as future work with a one-line justification.

### 9.2 Precompute (ship in the app bundle)
- Compact CSR graph for the target region (Chennai + ~20 km buffer).
- Free-flow metric `τ_free` + **16 ALT landmark distance tables** (`2 × 16 × |V|` int32 —
  at |V| = 1.5×10⁵ that is ~19 MB; halve with int16 deltas or fewer landmarks if tight).
- **Static hazard prior `ℓ₀(e)`** per edge from DEM-derived HAND, elevation, drain
  proximity, historical inundation. *This is what makes offline mode substantive rather
  than a stale route cache — and it is the most under-appreciated item on this list.*
- Edge → **H3 cell** index (res 9–10) for O(1) spatial attribution of incoming reports.
- Per-hazard-class constants: `T_c`, `α_c`, `h_max(mode)`, severity `s`.
- Optional: metric-independent CCH order (InertialFlowCutter / KaHIP) — compute it, ship
  it, use it only if profiling demands.

### 9.3 Do NOT precompute
- Time-dependent profile shortcuts (TCH/CATCHUp) — complexity results in [4] plus a 7-week
  budget make this a trap.
- Full CH — invalidated by the very thing the product is about (§6.2).
- Pareto route sets — the 3-λ sweep is the right approximation.

### 9.4 Engine decision
- **Primary:** Valhalla, for tiles + map matching + turn instructions + the offline mobile
  path [28][29][30]. **Spike the `traffic.tar` live-update path in week 1** — §7.3 flags it
  as the highest-uncertainty item in the stack.
- **Own:** the graph, the cost function, and the search. That is the contribution.
- **Reject:** OSRM as the live-hazard engine. [27] is decisive: ~10-minute customise,
  ~20-minute achieved cadence, no partial recustomisation, no per-request cost model.
  It remains fine for a batch baseline or for isochrones.
- **Revisit GraphHopper** only if the team's JVM/Android experience outweighs the
  live-update gap — and verify its current Android support status first.

### 9.5 Evaluation plan (this is where the marks are)
1. **Correctness:** validate the ALT/A* implementation against Dijkstra on DIMACS USA
   instances [32]; assert identical distances on 10⁴ random pairs.
2. **Latency:** query time distribution on-device, Chennai graph, cold and warm, across λ.
3. **Route quality:** replay historical Chennai flood events. Compare
   `{fastest, CityPulse λ_balanced, CityPulse λ_safe, oracle-with-hindsight}` on
   (a) realised travel time, (b) number of impassable-edge traversals, (c) failure rate
   (route required an actually-closed road).
4. **Calibration:** reliability diagram for `p̄(e,t)` against observed closures (§8.1).
   **This plot is your paper's money figure.**
5. **Counterfactual at scale:** SUMO or MATSim scenario with hazard-perturbed edges;
   measure aggregate delay under each policy [33].
6. **Ablations:** `z = 0` vs `z = 2` (does pessimism help?); with vs. without static prior
   `ℓ₀` under simulated total connectivity loss (does offline mode actually work?);
   hysteresis μ sweep (route churn vs. optimality).

### 9.6 Explicit risks in this recommendation
- Valhalla's live-traffic path may prove harder than the docs suggest (§7.3). Mitigation:
  bypass it entirely — your own search does not need Valhalla's cost model at all, only its
  tiles and instructions.
- The ALT landmark table may be too large for a low-end phone. Mitigation: fewer landmarks,
  int16 deltas, or drop to plain bidirectional Dijkstra (still ~10–40 ms).
- Ground-truth closure data for Chennai may not exist at usable resolution. **This is the
  biggest project risk and it is a data risk, not an algorithms risk.** Mitigation: the
  citizen-science depth-photo protocol in [20] is a proven, cheap fallback.

---

## 10. Sources

[1] <https://arxiv.org/abs/1504.05140> ·
[2] <https://dl.acm.org/doi/10.5555/1070432.1070455> ·
[3] <https://people.csail.mit.edu/bdean/tdsp.pdf> ·
[4] <https://sites.cs.ucsb.edu/~suri/psdir/soda11.pdf> ·
[5] <https://pubsonline.informs.org/doi/10.1287/opre.46.5.625> ·
[6] <https://www.sciencedirect.com/science/article/abs/pii/S0927050706140098> ·
[7] <https://www.sciencedirect.com/science/article/abs/pii/S0968090X13001861> ·
[8] <https://ideas.repec.org/a/eee/transb/v43y2009i6p597-613.html> ·
[9] <https://en.wikipedia.org/wiki/Canadian_traveller_problem> ·
[10] <https://eva.fing.edu.uy/pluginfile.php/277486/mod_resource/content/1/Dumitrescu-WCSP-ITOR-2001.pdf> ·
[11] <https://cdn.aaai.org/ojs/17450/17450-13-20944-1-2-20210518.pdf> ·
[12] <https://arxiv.org/abs/1402.0402> ·
[13] <https://arxiv.org/abs/2502.10519> ·
[14] <https://pubsonline.informs.org/doi/10.1287/trsc.2014.0579> ·
[15] <https://www.mdpi.com/1999-4893/14/3/90> ·
[16] <https://arxiv.org/abs/2604.10608> ·
[17] <https://www.sciencedirect.com/science/article/pii/S1361920916308367> ·
[18] <https://www.sciencedirect.com/science/article/pii/S0022169425003646> ·
[19] <https://www.nature.com/articles/s41598-025-06374-2> ·
[20] <https://www.nature.com/articles/s41598-022-20882-5> ·
[21] <https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0354204> ·
[22] <https://ascelibrary.org/doi/10.1061/JITSE4.ISENG-2788> ·
[23] <https://arxiv.org/abs/2011.05440> ·
[24] <https://www.frontiersin.org/journals/future-transportation/articles/10.3389/ffutr.2025.1524232/full> ·
[25] <https://arxiv.org/abs/2601.13632> ·
[26] <https://github.com/Project-OSRM/osrm-backend/wiki/Traffic> ·
[27] <https://github.com/Project-OSRM/osrm-backend/issues/5503> ·
[28] <https://valhalla.github.io/valhalla/concepts/costing/dynamic-costing/> ·
[29] <https://valhalla.github.io/valhalla/concepts/speeds/> ·
[30] <https://github.com/valhalla/valhalla/discussions/4746> ·
[31] <https://github.com/graphhopper/graphhopper/blob/master/docs/core/custom-models.md> ·
[32] <http://www.diag.uniroma1.it/challenge9/download.shtml> ·
[33] <https://eclipse.dev/sumo/> , <https://matsim.org/>

**Verification status.** [1][3][4][8][12][13][15][16][17][18][19][20][21][23][24][25]
[26][27][28][29][30][31][32] were opened and read this session. [2][5][6][7][10][11][14]
were confirmed to exist via publisher/index pages or author-hosted PDFs but the publisher
page blocked automated fetch in at least one case — metadata is from those secondary
confirmations. **[9] I have not read the primary TCS paper** (paywalled); complexity claim
is from the canonical secondary literature. **[22] I have the DOI/title only — ASCE returned
403; do not cite its content without reading it.** The Pregnolato coefficient values in
§5.4 are from secondary sources and must be checked against the paper PDF.
