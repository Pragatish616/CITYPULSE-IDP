# S6: Formulation and mathematics review (paper.tex Section III and its implementation)

Reviewer: S6 (formulation and maths). Scope: Eqs. (1)–(4), the "risk-seeking under ambiguity" argument, Proposition 1 (ALT consistency), Proposition 2 (bounded deterrence), the chance-constraint approximation, the Pregnolato curve and the δ≥1 clamp, and the code that implements them.

Files read: `IDEA_AND_FACTS.md`; `drafts/paper.tex` (all of it, focus on §III–IV); `pulse_belief/lib/src/{fusion,pessimistic,kernel,math_utils,observation}.dart`; `pulse_router/lib/src/{edge_cost,depth_disruption,alt_landmarks,bidirectional_dijkstra,query_orchestrator}.dart`; `config/hazard_classes.yaml`; `scripts/t1_3_build_graph_and_prior.py` (speeds); `scripts/t3_2_replay_engine.py` (snapping); `data/corpus/2026-09-17/edge_snap_index.json`; `data/graph/2026-09-14/chennai_graph_cli.json`.

Method: symbolic checks with sympy; numerical checks with numpy/scipy (script kept in the session scratchpad as `s6.py`); counts over the shipped graph and snap index; primary-source check of Pregnolato et al. (2017) through the open-access ScienceDirect full text.

Constants used below (from `hazard_classes.yaml`): α_crowd = 0.60 (logit = 0.405), α_official = 0.92 (logit = 2.442); z ∈ {0 commuter, 1.28 pedestrian, 2 emergency}; λ ∈ {0.3, 1.2, 1.0}; flood s = 1.0, h_max = 300 mm, ε = 0.10; waterlogging s = 0.6, h_max = 200 mm, ε = 0.15. The prior-only hazard edges have p0 ≥ 0.25 by construction; GCC category priors run from 0.02 to 0.45.

---

## Critical

### C1. Adding a positive crowd report *lowers* p̃ for every z>0 class, so Eq. (3) does not have the property the paper claims for it
- **Location:** Eq. (3) and the sentence that follows it ("thin evidence produces more caution, not less"); §III-B "Why not scale the penalty by confidence?" ("Equation (3) reverses the direction of that dependence"); `pessimistic.dart:40–42` together with `fusion.dart:95–97`.
- **Problem:** The statement "for fixed p̄, p̃ decreases in n_eff" is true (∂p̃/∂n = −z·√(p(1−p))/(2(n+1)^{3/2}) < 0, checked with sympy). But p̄ is never held fixed: one report raises n_eff by ω and moves ℓ by ω·logit(α) at the same time. For a weak source, the band shrinks by more than the mean rises. With p0 = 0.05, the values are:

  | evidence at d=0, age 0 | z=1.28 p̃ | z=2 p̃ |
  |---|---|---|
  | none (prior only) | 0.329 | 0.486 |
  | 1 positive crowd report | **0.309** | **0.441** |
  | 2 positive crowd reports | 0.333 | **0.461** |
  | 3 positive crowd reports | 0.380 | 0.509 |

  At z = 2 it takes three concurring flood reports before the router is more cautious than it was with none. With p0 = 0.20 and z = 2, one crowd report lowers p̃ from 1.00 to 0.90. Solving p̃(one report) = p̃(none) gives a crossover at α* ≈ 0.63 for z = 1.28 and α* ≈ 0.645 for z = 2. This holds for p0 from 0.02 to 0.10 (root-finding with brentq). The configured α_crowd = 0.60 sits just below that knife-edge.
- **Ageing makes it worse, in the opposite direction from the paper's claim.** As a single crowd report ages (ω: 1→0), p̃ rises: for z = 2 and p0 = 0.05 it goes from 0.441 to 0.486. For z = 1.28 the path is non-monotone (0.309 → 0.308 → 0.329). For an official report (α = 0.92), p̃ falls with age for every z. For z = 0 (the commuter default), p̃ = p̄ falls with age for every source.
- **Why it matters:** This is the paper's headline modelling idea and the basis of contribution 1. Its central claim, that the router "becomes more cautious when evidence is thin", is false for the source class that makes up 82% of the corpus (5,052 of 6,132 observations), for the two user classes that use z > 0. A referee who runs three lines of numpy will find it.
- **Suggested fix:** (a) Replace the Wald-type band with a quantity that is monotone in positive evidence by construction. One option: a Beta posterior per edge, with pseudo-counts a = a0 + Σω·[y=+1]·g(α) and b = b0 + Σω·[y=−1]·g(α), where (a0, b0) are set from p0 and a stated prior strength m0, and p̃ = Beta quantile at Φ(z). With that model, a positive report always raises every upper quantile. Alternatively, keep log-odds fusion but put the band in log-odds space with a variance that decreases in information Σω·logit(α)², not in report count, and check monotonicity. (b) In either case, state and prove (or test over a grid) a monotonicity lemma: ∂p̃/∂(positive evidence) ≥ 0. (c) Rewrite the §III-B paragraph accordingly (see S1).
- **Confidence:** High.
- **Evidence:** `s6.py` sections 5 and 5b; root-finding run. Reproduce with `pt = min(1, p + z*sqrt(p*(1-p)/(n+1)))`, `p = expit(logit(p0) + k*logit(0.6))`, `n = k`.

### C2. The production router does not use ALT, so Proposition 1 and the "minimum ratio 1.0" check concern code that is never on the query path
- **Location:** §IV, first paragraph ("bidirectional Dijkstra with ALT landmarks"); Proposition 1; §VI-E ("as Proposition 1 requires"); `query_orchestrator.dart:155–168`; `alt_landmarks.dart:195`.
- **Problem:** `planRoute` calls plain `bidirectionalDijkstra` twice, once with the hazard cost and once with the free-flow cost. No landmark potential is involved. `aStarWithLandmarks` is a *unidirectional* A* and is referenced only from `test/alt_landmarks_test.dart` (grep over the whole repo; the `bin/` directory has no landmark reference). No bidirectional ALT exists anywhere, so the question of how forward and backward potentials are combined does not arise.
- **Exactness of what exists:**
  - `bidirectionalDijkstra` is exact. It uses the standard stop rule topF + topB ≥ μ. It updates μ on every relaxation that touches a node labelled by the other side, and it handles one side's queue draining correctly by continuing with the one-sided bound topF ≥ μ. I traced the argument: when one side has drained, the first unsettled vertex v on an optimal path has an exact forward label and a final backward label, so μ ≤ OPT. Costs are ≥ τ0 > 0, and NaN or negative costs throw.
  - `aStarWithLandmarks` is exact under the stated invariant. Its potential is the maximum of 0 and the standard landmark differences. A maximum of consistent potentials is consistent. Infinite and NaN differences from disconnected components resolve to valid bounds (inf − finite = inf only when the node cannot reach the target; NaN is skipped by the `>` comparison). Its early exit at the target is valid under consistency.
- **Why it matters:** The paper attributes an architecture property to the system that the evaluated system does not have, and it presents an engineering check as confirming a proposition that has no effect on the reported results. If the team later adds bidirectional ALT, naive use of the forward potential on both sides is incorrect. The standard construction uses average potentials p_f = (π_t − π_s)/2 and p_r = −p_f (Ikeda et al. 1994; Goldberg & Harrelson 2005, already cited as `goldberg2005alt`), with the stop rule top_f + top_r ≥ μ + p_r(t). Proposition 1's w ≥ τ0 premise gives consistency for that pair as well.
- **Suggested fix:** Either (i) say "bidirectional Dijkstra; an ALT A* variant using landmarks precomputed on τ0 is implemented and tested but not used in the evaluated configuration", and move Proposition 1 to a remark, or (ii) wire ALT into `planRoute`, benchmark it (the reported 3.07 s per call is graph loading, so ALT is irrelevant to that number), and then keep the proposition. Delete "as Proposition 1 requires" from §VI-E, or rephrase it as "the w ≥ τ0 invariant held on all edges".
- **Confidence:** High.
- **Evidence:** Grep for `aStarWithLandmarks|AltLandmarks.build|bidirectionalDijkstra(` over the repo; read `query_orchestrator.dart`.

### C3. Eq. (1) defines a spatial kernel over all edges, but the implementation snaps each observation to exactly one directed edge, so flooded two-way streets are penalised in one direction only
- **Location:** Eq. (1) (κ(d(e, x_i)) for every e); `scripts/t3_2_replay_engine.py:108–139`; `data/corpus/2026-09-17/edge_snap_index.json`; `query_orchestrator.dart:120–127` (observations are looked up by `edge_id`).
- **Problem:** The snap index has 6,132 entries, one per observation, and every observation maps to exactly one `edge_id`. κ is applied only to the snap distance; observations never spread to neighbouring edges. Of the 5,775 directed edges carrying observations, 5,177 have a reverse twin (to→from) in the graph, and only 2 of those twins carry the evidence too. The twin receives a hazard entry only if its prior p0 ≥ 0.25.
- **Why it matters:** The router can avoid a reported flood in one direction and drive straight through it in the other. The formulation the paper presents is not the one evaluated. The reference-belief metrics in §V–VI inherit the same asymmetry, unless the re-analysis assigned beliefs differently; that should be checked by the evaluation reviewer.
- **Suggested fix:** Either implement Eq. (1) as written (attribute each observation to all edges within the kernel cutoff, at least to both directions of the snapped way), or change Eq. (1) to the snapped form and state the limitation. Re-run Study 1 after the fix.
- **Confidence:** High for the count. The effect on Table II is not quantified here.
- **Evidence:** Python over `chennai_graph_cli.json` and `edge_snap_index.json`: "edges with obs: 5775, with a reverse twin: 5177, twin also has obs: 2"; maximum edges per observation = 1.

---

## Significant

### S1. The "risk-seeking under ambiguity" argument is mislabelled and overstated
- **Location:** §III-B, paragraph "Why not scale the penalty by confidence?"; contribution bullet 1.
- **Problem:**
  1. *Terminology.* Preferring an option because its probability is less well known is **ambiguity-seeking** (ambiguity-loving, in the Ellsberg / Gilboa–Schmeidler sense), not risk-seeking. Risk-seeking means preferring mean-preserving spreads of *known* distributions.
  2. *Truth conditions.* Multiplying by confidence is not wrong in itself. If R = Pr[flood | report valid] and C = Pr[report still valid], then R·C is the correct marginal probability of flooding when an invalid report implies "no flood", and it is ambiguity-neutral. The argument is correct only when the no-information default should be the prior rather than 0. Then R·C is optimistic, because it decays to 0 instead of to p0, and it ignores second-order uncertainty. The paper's own fusion already handles the first point: an ageing report sends ℓ → ℓ0.
  3. *The "reverses the direction" claim is false in general.* For the commuter default (z = 0), p̃ = p̄ falls with report age exactly as R·C does; it only stops at p0 instead of 0. For official reports, p̃ falls with age at every z. The direction reverses only for weak sources at z > 0, which is the perverse case in C1.
- **Why it matters:** This is listed as a contribution. As written it would not survive a decision-theory referee.
- **Suggested fix:** Restate it as: "a confidence-multiplied penalty decays to zero as evidence ages, treating absence of information as evidence of absence. Our fusion decays to a susceptibility prior, and the z term adds an ambiguity margin." Use "ambiguity-averse / ambiguity-seeking". State the condition (no prior floor) under which R·C is optimistic. Drop "reverses the direction" unless the band is reformulated per C1 and a monotonicity result is shown.
- **Confidence:** High.
- **Evidence:** Analytical argument; numbers in `s6.py` section 5b (z = 0 monotone decreasing with age for all α; z = 2 and α = 0.92 also decreasing).

### S2. The pessimistic bound is neither a confidence bound nor consistent with the posterior that already contains the prior; the "+1" is unexplained
- **Location:** Eq. (3); `pessimistic.dart:40`.
- **Problem:**
  1. *What is the "+1"?* p̄(1−p̄)/(n_eff+1) equals the variance of a Beta(a, b) with mean p̄ and **a + b = n_eff**, because Var = m(1−m)/(a+b+1). Under that reading the +1 is not a prior pseudo-count; the prior contributes zero pseudo-counts to the variance even though ℓ0 is fully present in the mean. Under the other reading, a Wald interval with n_eff + 1 trials, the prior is worth exactly one observation whatever p0 or its provenance. Neither reading is stated, and the two disagree.
  2. *Units mismatch.* Each report adds ω·logit(α) to the mean but only ω to n_eff, so one official report (logit 2.44) and one crowd report (logit 0.41) count the same towards certainty.
  3. *Conflict reads as certainty.* n_eff is unsigned (as documented in `fusion.dart:32`), so one positive and one negative crowd report leave p̄ = p0 but shrink the band. With p0 = 0.25 and z = 2, p̃ goes from 1.00 (no evidence) to 0.75 (conflicting pair). With p0 = 0.05 and z = 1.28, it goes from 0.329 to 0.211. Conflicting evidence is the textbook case where an ambiguity-averse rule should be *more* cautious.
  4. *Wald collapse.* lim p̄→0 p̃ = 0 and lim p̄→1 p̃ = 1 (sympy), whatever n_eff is. Near 0 the bound is anti-conservative relative to standard intervals. At p̄ = 0.02, n_eff = 1, z = 2: ours 0.218; Wilson (n = 2) 0.680; Jeffreys 0.697; variance-matched Beta(a+b = n_eff) quantile 0.325. Near 0.5 with thin evidence it saturates. At p̄ = 0.5, n_eff = 0, z = 1: ours 1.000; Wilson 0.854; Jeffreys 0.841. Full grid for p̄ ∈ {0.02, 0.1, 0.3, 0.5}, n_eff ∈ {0, 0.5, 1, 5, 20}, z ∈ {0, 1, 2} is in the appendix table below.
  5. *Saturation on the actual hazard set.* With n_eff = 0, p̃ = 1 whenever p0 ≥ 0.20 at z = 2 (exact root 0.2000) and whenever p0 ≥ 0.379 at z = 1.28. All 8,759 prior-only hazard edges have p0 ≥ 0.25, so under the emergency class every one of them has p̃ = 1, and cost = 2τ0 at λ = 1. The bound carries no information there, and any report can only lower it (C1).
  6. "Mirrors UCB of bandit algorithms [auer2002ucb]": UCB1 is a Hoeffding/log-t bonus, not a variance-scaled Wald term. The analogy is loose.
- **Why it matters:** The method's distinguishing component has no probabilistic interpretation, so z has no coverage meaning ("z = 1.28" suggests a 90% one-sided bound that does not exist). Its behaviour on the real hazard set is degenerate for the emergency class.
- **Suggested fix:** Define an explicit second-order model. The simplest coherent option is a per-edge Beta with prior strength m0 (a0 = m0·p0, b0 = m0·(1−p0)), with evidence pseudo-counts that are reliability-weighted and decayed; then p̃ = Beta⁻¹(Φ(z)). Report it against the current Eq. (3) on the calibration study. If Eq. (3) is kept, call it a heuristic margin, say what the +1 means, and present the conflicting-evidence and saturation behaviour as limitations. The paper already lists Wilson as future work, but Wilson inherits issue 1 (what is n?) and does not by itself fix C1.
- **Confidence:** High for the numbers; medium-high for the interpretive claims.
- **Evidence:** `s6.py` sections 1, 2, 4 and 6; sympy limits and derivative.

### S3. The log-odds sum is a heuristic, not a Bayesian update, and the independence assumption saturates quickly
- **Location:** Eq. (1); `fusion.dart:95–97`; §VII "Independence".
- **Problem:**
  1. Using logit(α) as each report's log-likelihood ratio assumes a *symmetric channel*: Pr(+report | flooded) = α and Pr(+report | not flooded) = 1−α. That is coherent for a source with sensitivity = specificity = α, but it should be stated. It is implausible for app traversal, where "passed without reporting" has a very different likelihood ratio.
  2. Multiplying a log-LR by ω = κ·e^{−Δt/T_c} is a *tempered (power) likelihood*, not Bayesian conditioning. If κ is "probability the report refers to this edge", the coherent mixture likelihood is log(κ·LR + 1 − κ), which exceeds κ·log LR by Jensen. For α = 0.92 and κ = 0.5: 1.833 versus 1.221 (power). For time decay, a persistence model (two-state Markov, or the Rosen et al. persistence filter the paper already cites) relaxes the posterior toward the prior in probability space, not as e^{−t/T}·log LR in log-odds space.
  3. With independence, k identical fresh crowd reports on a prior of 0.05 give:

     | k | p̄ | p̃ at z=2 |
     |---|---|---|
     | 1 | 0.073 | 0.441 |
     | 3 | 0.151 | 0.509 |
     | 10 | 0.752 | 1.000 |
     | 30 | 0.9999 | 1.000 |

     Thirty correlated reshares of one sighting make the edge certainly flooded. The 2015 corpus already needed 2,806 duplicates removed.
- **Why it matters:** The paper cites the occupancy-grid tradition, but occupancy grids use an inverse sensor model with clamping. Here the update has neither a probabilistic derivation nor a cap, and the calibration study shows strong over-prediction, which is consistent with over-counting.
- **Suggested fix:** Present Eq. (1) as a "tempered log-odds pooling" heuristic with the symmetric-channel assumption explicit. Add correlation discounting (for example, per-cluster or per-source aggregation with a concave g(Σω) in place of the linear sum, or clamping ℓ to [ℓ_min, ℓ_max] as in occupancy grids). Optionally derive the decay from a persistence model and compare it on the calibration data.
- **Confidence:** High.
- **Evidence:** `s6.py` sections 3 and the mixture-versus-power computation.

### S4. The chance-constraint "point approximation" is not a valid chance constraint and fails open when depth is unknown
- **Location:** §III-C, last sentence; `edge_cost.dart:101–105`; `query_orchestrator.dart:53–56` (depth is the "newest reading", not fused or decayed).
- **Problem:** The rule is: remove e if ĥ > h_max and p̃ ≥ ε. In effect it sets Pr[h > h_max] := p̃·1[ĥ > h_max], which implies:
  1. *Pr = 0 whenever depth is unknown.* An unknown depth does not imply zero probability of exceeding h_max, so the constraint fails open by default. On the evaluated corpus, which has no depth anywhere, it never fires. The paper says this in threats to validity, but §III presents the rule as an approximation of the constraint.
  2. It treats Pr[h > h_max | hazard present, reading] as 1 if the point reading exceeds the threshold and 0 otherwise. There is no measurement-error model for crowd depth estimates.
  3. *ε is vacuous on high-prior edges.* Since p̃ ≥ p̄ → p0 ≥ 0.25 > ε (0.10 or 0.15) on every prior-only hazard edge, the probability clause is always satisfied there, and the rule reduces to "ĥ > h_max".
  4. *Stale depth never expires.* `depthMm` is not decayed, and p̃ does not fall below p0. A single old reading above 300 mm on a susceptible edge removes that edge permanently.
  5. *Low-prior edges keep reported deep water.* A single fresh crowd report of 320 mm on a p0 = 0.02 edge gives p̃ = 0.030 at z = 0, below ε, so the edge stays open. Its cost is only about 1.4τ0, because δ is capped at about 14.5 for a 30 km/h street (see S6). At z = 1.28 or z = 2 it is removed.
  6. Removal depends on z, which is a robustness margin. That is acceptable but should be named; it resembles an ambiguity-robust chance constraint only if p̃ were a valid upper confidence bound (S2).
- **Why it matters:** "Chance constraint" plus a Charnes–Cooper citation implies a probabilistic guarantee that the rule does not provide.
- **Suggested fix:** Call it a "threshold rule" rather than a chance-constraint approximation, or model it properly: Pr[h > h_max] = p̃ · Pr[h > h_max | flooded], with the second factor from a depth distribution. That distribution could be the reading with a reliability-dependent error model, or a class-level depth prior when no reading exists, so unknown depth is not mapped to zero. Decay depth readings on the same clock as the belief, and fuse depth from the same observations instead of carrying a separate "newest reading".
- **Confidence:** High.
- **Evidence:** Code reading; `s6.py` section 7.

### S5. Proposition 2 is correct as a necessary condition but has unstated assumptions and a notation slip; the 60 s → 18 s example is right
- **Location:** Proposition 2 and the paragraph after it.
- **Problem:**
  1. The ratio bound w/τ0 = 1 + λp̃s_c ≤ 1 + λs_c is correct. It needs s_c ≥ 0 and p̃ ≤ 1; the code guarantees both via `min{1,·}` and validation. The arithmetic checks: 0.3 × 1 × 60 × 1 = 18 s. For waterlogging (s = 0.6) the cap is 10.8 s; for a prior-only edge at z = 0 (p̃ = 0.25) it is 4.5 s.
  2. The route statement is exact as an iff only if the avoiding route P2 carries no hazard penalty. In general, P2 beats P1 if and only if T2 − T1 < λ(H1 − H2), with H = Σ_e p̃_e s_{c(e)} τ0(e) over each route's own edges; shared edges cancel. "Only if ΔT < λH1" holds as a necessary condition because H2 ≥ 0, which the proof should say.
  3. s_c sits outside the sum, but the class varies by edge (flood 1.0, waterlogging 0.6). The sum should be Σ_e p̃_e s_{c(e)} τ0(e) ≤ λ·s_max·T_h.
  4. It also assumes δ = 1 on *both* routes, no edge removed, and T_h measured over edges of P1 not in P2.
  5. "Proposition" is generous for a one-line substitution; "Remark" or "Observation" would fit an IEEE paper better. The actual insight, that a harm term proportional to τ0 makes short severe segments cheap, deserves its own sentence. A fix (harm per traversal, λ·p̃·s·H_c in seconds independent of τ0) should be stated in §III, not only in future work.
- **Why it matters:** These are minor correctness issues in the statement, but this proposition carries the paper's main empirical explanation.
- **Suggested fix:** Restate it as: "If δ ≡ 1 and no edge is removed, a route P2 is preferred over P1 iff T2 − T1 < λ(H1 − H2); in particular only if T2 − T1 < λ·max_c s_c·T_h(P1∖P2)." Make s_{c(e)} edge-indexed.
- **Confidence:** High.
- **Evidence:** Algebra; `s6.py` section 9.

### S6. Pregnolato curve: coefficients verified, but the 300 mm handling and the curve's scope differ from the source
- **Location:** §III-C (δ definition); `depth_disruption.dart:17, 26–33, 49–59`; `hazard_classes.yaml` (`h_max_mm_pedestrian`).
- **Verified against the primary source** (Pregnolato, Ford, Wilkinson, Dawson, *Transp. Res. D* 55:67–81, 2017, open-access full text on ScienceDirect, pii S1361920916308367). Their Eq. (4) is v(w) = 0.0009w² − 0.5529w + 86.9448, with R² = 0.95. w is water depth in mm and v is in km/h (their Table 2 lists depths in mm and speeds in km/h). v(w) is described as "the maximum acceptable velocity that ensures safe control of the vehicle given the depth of water". Table 2, point 10, sets 300 mm → 0 km/h as "the ultimate threshold for a safe drive for most of the common cars". Their disruption Eq. (3) uses (v − v(w)), which is consistent with speed = min(v_free, v(w)). **The paper's coefficients and units are correct**, and the code comment "[UNVERIFIED DETAIL]" can now be resolved.
- **Problems:**
  1. The fitted quadratic gives v(300) = 2.07 km/h, not 0, and has its vertex at 307.2 mm. The code clamps h to 300, so every depth ≥ 300 mm (500 mm, 1 m) yields v_safe = 2.07 km/h and a *finite* δ ≈ 14.5 on a 30 km/h street. The source treats 300 mm as impassable. The `vSafe <= 0 → ∞` branch at `depth_disruption.dart:56` is unreachable dead code. If it were made reachable, 0·∞ = NaN in `edge_cost.dart:109` whenever p̃ = 0.
  2. *δ ≥ 1 clamp.* The paper's justification, "for shallow water on a slow street", understates how wide the δ = 1 region is. Solving v(h) = v0 gives δ = 1 for every h below 166 mm (20 km/h residential), 131 mm (30 km/h), 102 mm (40 km/h), 76 mm (50 km/h) and 53 mm (60 km/h). Graph speeds max out at 70 km/h, so no edge has δ > 1 at zero depth. On most Chennai streets the slowdown term is therefore zero over roughly the first 130–170 mm and then rises steeply, so it acts almost like a step. The clamp is the natural reading of Pregnolato's min(v, v(w)) usage, so the paper can say that instead of presenting it as an implementation patch.
  3. *Scope.* The curve was fitted for passenger cars. It is applied unchanged to the emergency class (Kramer et al. 2016, cited inside Pregnolato, give 0.6 m wading for emergency vehicles) and to pedestrians. `h_max_mm_pedestrian` exists in the YAML but is never read; `EdgeHazardConfig` has one h_max per edge regardless of user class.
- **Suggested fix:** Return v_safe = 0 (δ = ∞, edge treated as removed) for h ≥ 300 mm, and guard 0·∞. Cite Pregnolato's Eq. (4) and Table 2 point 10 explicitly. Either restrict the depth model to cars or add class-specific curves and thresholds.
- **Confidence:** High (primary source read).
- **Evidence:** ScienceDirect full text, §3.1, Eq. (4) and Table 2; `s6.py` section 8.

### S7. The static prior is used as P(flooded now) at all times
- **Location:** §III-A ("a static prior log-odds ℓ0(e) encodes susceptibility"); §V-A (GCC category → 0.02–0.45).
- **Problem:** Hazard-zone categories describe susceptibility *given a flood event*. Using them as the unconditional probability that an edge is flooded at query time means that on a dry day every "Very High" edge carries p̄ = 0.45. With z = 2 that becomes p̃ = 1, and with z = 1.28 also p̃ = 1. Ageing evidence decays back to this level, not to near zero.
- **Why it matters:** This alone would explain the over-prediction in the reliability diagrams, and it makes deployed behaviour outside events absurd for the emergency class.
- **Suggested fix:** Make the prior event-conditional, for example ℓ0(e, t) = logit(Pr[flooded | event active]) when a rainfall or official alert is active, and a low base rate otherwise. State the event trigger.
- **Confidence:** Medium-high (this is a modelling judgement, but the consequence is computed).
- **Evidence:** `s6.py` section 4; YAML and prior-construction facts in IDEA_AND_FACTS.

---

## Minor

### M1. Proposition 1's hypotheses omit s_c ≥ 0 and finite δ
- **Location:** Proposition 1.
- **Problem:** w ≥ τ0 also needs s_c ≥ 0. The code validates it at `edge_cost.dart:91`. A finite δ, or a convention for 0·∞, is also required; see S6, item 1.
- **Fix:** Add both conditions to the statement. "Feasible potential" is the right term; keep it.
- **Confidence:** High.

### M2. The trace mixes objective cost with free-flow cost when comparing routes
- **Location:** `query_orchestrator.dart:197` and `:277`.
- **Problem:** The chosen route's `durationSeconds` is the hazard objective, which includes penalty seconds. The rejected alternative's `durationSeconds` is its pure free-flow cost. Explanations that compare the two compare different quantities. This is the same conflation §VI-C criticises in the old harness. For removed edges, `timePenaltySeconds` is 0.
- **Fix:** Report free-flow and objective cost for both routes.
- **Confidence:** High.

### M3. One hazard class per edge
- **Location:** §V-A; Eq. (4).
- **Problem:** The router accepts one hazard class per edge, so the minority class is dropped on edges with two classes. Eq. (4) has no rule for combining classes (for example Σ_c p̃_c s_c, or 1 − Π(1 − p̃_c) for the probability).
- **Fix:** State the combination rule even if the corpus only exercises one class.
- **Confidence:** High.

### M4. Kernel discontinuity at the cutoff
- **Location:** `kernel.dart`.
- **Problem:** κ(d) = e^{−d/75} with a hard cutoff at 300 m has a small discontinuity there (κ = 0.018 just inside, 0 just outside). It is harmless, but given C3 the kernel's shape is moot in the evaluation anyway.
- **Confidence:** High.

### M5. `logit` validates by assert only
- **Location:** `math_utils.dart:11`.
- **Problem:** `logit` relies on `assert`, which is stripped in release builds. In practice `WeightedObservation` validates α ∈ (0, 1) before `logit` is called, so this is defensive only.
- **Confidence:** High.

### M6. Notation
- **Location:** Eqs. (1)–(4).
- **Problem:** p̄ and n_eff are written without (e, t) in Eq. (3). α_i in Eq. (1) is per source class in the code (α_c). "UCB … used pessimistically": "lower/upper confidence bound used for robustness" is clearer.
- **Confidence:** High.

---

## Questions for the authors

1. Which interpretation of n_eff + 1 is intended: Beta with a + b = n_eff, or Wald with the prior as one trial? What prior strength (in pseudo-observations) does ℓ0 represent?
2. Was the reference belief in the re-analysis computed with the same one-directed-edge snapping (C3)? If so, how do Table II's exposure numbers change when both directions carry the evidence?
3. Is a monotonicity property (more positive evidence ⇒ p̃ non-decreasing) a design requirement? If so, the current Eq. (3) violates it (C1).
4. What does app-traversal (polarity −1, α = 0.7) mean as a symmetric channel, given that Pr(no report | flooded) is not 1 − Pr(no report | dry)?
5. Is z meant to have a coverage interpretation (1.28 ≈ 90% one-sided)? If yes, which distribution is it a quantile of?
6. Why use the newest depth reading undecayed, rather than fusing depth from the same observations?

---

## Appendix: bound comparison (n = n_eff + 1 for Wilson and Jeffreys; "BetaVM" = Beta quantile at Φ(z) with mean p̄ and a + b = n_eff)

| p̄ | n_eff | z | Eq.(3) | Wilson | Jeffreys | BetaVM |
|---|---|---|---|---|---|---|
| 0.02 | 0 | 2 | 0.300 | 0.808 | 0.870 | – |
| 0.02 | 1 | 2 | 0.218 | 0.680 | 0.697 | 0.325 |
| 0.02 | 5 | 2 | 0.134 | 0.423 | 0.375 | 0.207 |
| 0.02 | 20 | 2 | 0.081 | 0.192 | 0.158 | 0.112 |
| 0.10 | 0 | 1 | 0.400 | 0.592 | 0.614 | – |
| 0.10 | 1 | 2 | 0.524 | 0.729 | 0.760 | 0.839 |
| 0.10 | 20 | 2 | 0.231 | 0.300 | 0.283 | 0.265 |
| 0.30 | 0 | 2 | 1.000 | 0.900 | 0.948 | – |
| 0.30 | 5 | 1 | 0.487 | 0.504 | 0.505 | 0.502 |
| 0.30 | 20 | 2 | 0.500 | 0.518 | 0.516 | 0.517 |
| 0.50 | 0 | 1 | 1.000 | 0.854 | 0.841 | – |
| 0.50 | 1 | 2 | 1.000 | 0.908 | 0.943 | 0.999 |
| 0.50 | 20 | 2 | 0.718 | 0.700 | 0.706 | 0.715 |

At z = 0, Eq. (3) and Wilson both return p̄. Jeffreys returns its median, which differs from p̄. The full 60-row grid is printed by `s6.py`, section 2.

Pattern: Eq. (3) is strongly anti-conservative at small p̄ and thin evidence, which is where low-prior edges with one report sit. It over-saturates at p̄ ≥ 0.2–0.3 with thin evidence. It agrees with the standard intervals only once n_eff ≳ 5–20.

Sources: Pregnolato et al. 2017, full text at https://www.sciencedirect.com/science/article/pii/S1361920916308367 (open access; Eq. (4), Table 2). Secondary confirmation of the coefficients: https://www.frontiersin.org/journals/environmental-science/articles/10.3389/fenvs.2022.1056854/xml.
