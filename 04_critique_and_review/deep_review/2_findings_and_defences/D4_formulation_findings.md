# Findings to defend (D4_formulation)

## F1 [Critical] C1. Adding a positive crowd report *lowers* p̃ for every z>0 class, so Eq. (3) does not have the property the paper claims for it
**Location:** Eq. (3) and the sentence that follows it ("thin evidence produces more caution, not less"); §III-B "Why not scale the penalty by confidence?" ("Equation (3) reverses the direction of that dependence"); `pessimistic.dart:40–42` together with `fusion.dart:95–97`.

**Claimed problem:** The statement "for fixed p̄, p̃ decreases in n_eff" is true (∂p̃/∂n = −z·√(p(1−p))/(2(n+1)^{3/2}) < 0, checked with sympy). But p̄ is never held fixed: one report raises n_eff by ω and moves ℓ by ω·logit(α) at the same time. For a weak source, the band shrinks by more than the mean rises. With p0 = 0.05, the values are:

  | evidence at d=0, age 0 | z=1.28 p̃ | z=2 p̃ |
  |---|---|---|
  | none (prior only) | 0.329 | 0.486 |
  | 1 positive crowd report | **0.309** | **0.441** |
  | 2 positive crowd reports | 0.333 | **0.461** |
  | 3 positive crowd reports | 0.380 | 0.509 |

  At z = 2 it takes three concurring flood reports before the router is more cautious than it was with none. With p0 = 0.20 and z = 2, one crowd report lowers p̃ from 1.00 to 0.90. Solving p̃(one report) = p̃(none) gives a crossover at α* ≈ 0.63 for z = 1.28 and α* ≈ 0.645 for z = 2. This holds for p0 from 0.02 to 0.10 (root-finding with brentq). The configured α_crowd = 0.60 sits just below that knife-edge.

## F2 [Critical] C2. The production router does not use ALT, so Proposition 1 and the "minimum ratio 1.0" check concern code that is never on the query path
**Location:** §IV, first paragraph ("bidirectional Dijkstra with ALT landmarks"); Proposition 1; §VI-E ("as Proposition 1 requires"); `query_orchestrator.dart:155–168`; `alt_landmarks.dart:195`.

**Claimed problem:** `planRoute` calls plain `bidirectionalDijkstra` twice, once with the hazard cost and once with the free-flow cost. No landmark potential is involved. `aStarWithLandmarks` is a *unidirectional* A* and is referenced only from `test/alt_landmarks_test.dart` (grep over the whole repo; the `bin/` directory has no landmark reference). No bidirectional ALT exists anywhere, so the question of how forward and backward potentials are combined does not arise.

## F3 [Critical] C3. Eq. (1) defines a spatial kernel over all edges, but the implementation snaps each observation to exactly one directed edge, so flooded two-way streets are penalised in one direction only
**Location:** Eq. (1) (κ(d(e, x_i)) for every e); `scripts/t3_2_replay_engine.py:108–139`; `data/corpus/2026-09-17/edge_snap_index.json`; `query_orchestrator.dart:120–127` (observations are looked up by `edge_id`).

**Claimed problem:** The snap index has 6,132 entries, one per observation, and every observation maps to exactly one `edge_id`. κ is applied only to the snap distance; observations never spread to neighbouring edges. Of the 5,775 directed edges carrying observations, 5,177 have a reverse twin (to→from) in the graph, and only 2 of those twins carry the evidence too. The twin receives a hazard entry only if its prior p0 ≥ 0.25.

## F4 [Significant] S1. The "risk-seeking under ambiguity" argument is mislabelled and overstated
**Location:** §III-B, paragraph "Why not scale the penalty by confidence?"; contribution bullet 1.

**Claimed problem:** 1. *Terminology.* Preferring an option because its probability is less well known is **ambiguity-seeking** (ambiguity-loving, in the Ellsberg / Gilboa–Schmeidler sense), not risk-seeking. Risk-seeking means preferring mean-preserving spreads of *known* distributions.
  2. *Truth conditions.* Multiplying by confidence is not wrong in itself. If R = Pr[flood | report valid] and C = Pr[report still valid], then R·C is the correct marginal probability of flooding when an invalid report implies "no flood", and it is ambiguity-neutral. The argument is correct only when the no-information default should be the prior rather than 0. Then R·C is optimistic, because it decays to 0 instead of to p0, and it ignores second-order uncertainty. The paper's own fusion already handles the first point: an ageing report sends ℓ → ℓ0.
  3. *The "reverses the direction" claim is false in general.* For the commuter default (z = 0), p̃ = p̄ falls with report age exactly as R·C does; it only stops at p0 instead of 0. For official reports, p̃ falls with age at every z. The direction reverses only for weak sources at z > 0, which is the perverse case in C1.

## F5 [Significant] S2. The pessimistic bound is neither a confidence bound nor consistent with the posterior that already contains the prior; the "+1" is unexplained
**Location:** Eq. (3); `pessimistic.dart:40`.

**Claimed problem:** 1. *What is the "+1"?* p̄(1−p̄)/(n_eff+1) equals the variance of a Beta(a, b) with mean p̄ and **a + b = n_eff**, because Var = m(1−m)/(a+b+1). Under that reading the +1 is not a prior pseudo-count; the prior contributes zero pseudo-counts to the variance even though ℓ0 is fully present in the mean. Under the other reading, a Wald interval with n_eff + 1 trials, the prior is worth exactly one observation whatever p0 or its provenance. Neither reading is stated, and the two disagree.
  2. *Units mismatch.* Each report adds ω·logit(α) to the mean but only ω to n_eff, so one official report (logit 2.44) and one crowd report (logit 0.41) count the same towards certainty.
  3. *Conflict reads as certainty.* n_eff is unsigned (as documented in `fusion.dart:32`), so one positive and one negative crowd report leave p̄ = p0 but shrink the band. With p0 = 0.25 and z = 2, p̃ goes from 1.00 (no evidence) to 0.75 (conflicting pair). With p0 = 0.05 and z = 1.28, it goes from 0.329 to 0.211. Conflicting evidence is the textbook case where an ambiguity-averse rule should be *more* cautious.
  4. *Wald collapse.* lim p̄→0 p̃ = 0 and lim p̄→1 p̃ = 1 (sympy), whatever n_eff is. Near 0 the bound is anti-conservative relative to standard intervals. At p̄ = 0.02, n_eff = 1, z = 2: ours 0.218; Wilson (n = 2) 0.680; Jeffreys 0.697; variance-matched Beta(a+b = n_eff) quantile 0.325. Near 0.5 with thin evidence it saturates. At p̄ = 0.5, n_eff = 0, z = 1: ours 1.000; Wilson 0.854; Jeffreys 0.841. Full grid for p̄ ∈ {0.02, 0.1, 0.3, 0.5}, n_eff ∈ {0, 0.5, 1, 5, 20}, z ∈ {0, 1, 2} is in the appendix table below.
  5. *Saturation on the actual hazard set.* With n_eff = 0, p̃ = 1 whenever p0 ≥ 0.20 at z = 2 (exact root 0.2000) and whenever p0 ≥ 0.379 at z = 1.28. All 8,759 prior-only hazard edges have p0 ≥ 0.25, so under the emergency class every one of them has p̃ = 1, and cost = 2τ0 at λ = 1. The bound carries no information there, and any report can only lower it (C1).
  6. "Mirrors UCB of bandit algorithms [auer2002ucb]": UCB1 is a Hoeffding/log-t bonus, not a variance-scaled Wald term. The analogy is loose.

## F6 [Significant] S3. The log-odds sum is a heuristic, not a Bayesian update, and the independence assumption saturates quickly
**Location:** Eq. (1); `fusion.dart:95–97`; §VII "Independence".

**Claimed problem:** 1. Using logit(α) as each report's log-likelihood ratio assumes a *symmetric channel*: Pr(+report | flooded) = α and Pr(+report | not flooded) = 1−α. That is coherent for a source with sensitivity = specificity = α, but it should be stated. It is implausible for app traversal, where "passed without reporting" has a very different likelihood ratio.
  2. Multiplying a log-LR by ω = κ·e^{−Δt/T_c} is a *tempered (power) likelihood*, not Bayesian conditioning. If κ is "probability the report refers to this edge", the coherent mixture likelihood is log(κ·LR + 1 − κ), which exceeds κ·log LR by Jensen. For α = 0.92 and κ = 0.5: 1.833 versus 1.221 (power). For time decay, a persistence model (two-state Markov, or the Rosen et al. persistence filter the paper already cites) relaxes the posterior toward the prior in probability space, not as e^{−t/T}·log LR in log-odds space.
  3. With independence, k identical fresh crowd reports on a prior of 0.05 give:

     | k | p̄ | p̃ at z=2 |
     |---|---|---|
     | 1 | 0.073 | 0.441 |
     | 3 | 0.151 | 0.509 |
     | 10 | 0.752 | 1.000 |
     | 30 | 0.9999 | 1.000 |

     Thirty correlated reshares of one sighting make the edge certainly flooded. The 2015 corpus already needed 2,806 duplicates removed.

## F7 [Significant] S4. The chance-constraint "point approximation" is not a valid chance constraint and fails open when depth is unknown
**Location:** §III-C, last sentence; `edge_cost.dart:101–105`; `query_orchestrator.dart:53–56` (depth is the "newest reading", not fused or decayed).

**Claimed problem:** The rule is: remove e if ĥ > h_max and p̃ ≥ ε. In effect it sets Pr[h > h_max] := p̃·1[ĥ > h_max], which implies:
  1. *Pr = 0 whenever depth is unknown.* An unknown depth does not imply zero probability of exceeding h_max, so the constraint fails open by default. On the evaluated corpus, which has no depth anywhere, it never fires. The paper says this in threats to validity, but §III presents the rule as an approximation of the constraint.
  2. It treats Pr[h > h_max | hazard present, reading] as 1 if the point reading exceeds the threshold and 0 otherwise. There is no measurement-error model for crowd depth estimates.
  3. *ε is vacuous on high-prior edges.* Since p̃ ≥ p̄ → p0 ≥ 0.25 > ε (0.10 or 0.15) on every prior-only hazard edge, the probability clause is always satisfied there, and the rule reduces to "ĥ > h_max".
  4. *Stale depth never expires.* `depthMm` is not decayed, and p̃ does not fall below p0. A single old reading above 300 mm on a susceptible edge removes that edge permanently.
  5. *Low-prior edges keep reported deep water.* A single fresh crowd report of 320 mm on a p0 = 0.02 edge gives p̃ = 0.030 at z = 0, below ε, so the edge stays open. Its cost is only about 1.4τ0, because δ is capped at about 14.5 for a 30 km/h street (see S6). At z = 1.28 or z = 2 it is removed.
  6. Removal depends on z, which is a robustness margin. That is acceptable but should be named; it resembles an ambiguity-robust chance constraint only if p̃ were a valid upper confidence bound (S2).

## F8 [Significant] S5. Proposition 2 is correct as a necessary condition but has unstated assumptions and a notation slip; the 60 s → 18 s example is right
**Location:** Proposition 2 and the paragraph after it.

**Claimed problem:** 1. The ratio bound w/τ0 = 1 + λp̃s_c ≤ 1 + λs_c is correct. It needs s_c ≥ 0 and p̃ ≤ 1; the code guarantees both via `min{1,·}` and validation. The arithmetic checks: 0.3 × 1 × 60 × 1 = 18 s. For waterlogging (s = 0.6) the cap is 10.8 s; for a prior-only edge at z = 0 (p̃ = 0.25) it is 4.5 s.
  2. The route statement is exact as an iff only if the avoiding route P2 carries no hazard penalty. In general, P2 beats P1 if and only if T2 − T1 < λ(H1 − H2), with H = Σ_e p̃_e s_{c(e)} τ0(e) over each route's own edges; shared edges cancel. "Only if ΔT < λH1" holds as a necessary condition because H2 ≥ 0, which the proof should say.
  3. s_c sits outside the sum, but the class varies by edge (flood 1.0, waterlogging 0.6). The sum should be Σ_e p̃_e s_{c(e)} τ0(e) ≤ λ·s_max·T_h.
  4. It also assumes δ = 1 on *both* routes, no edge removed, and T_h measured over edges of P1 not in P2.
  5. "Proposition" is generous for a one-line substitution; "Remark" or "Observation" would fit an IEEE paper better. The actual insight, that a harm term proportional to τ0 makes short severe segments cheap, deserves its own sentence. A fix (harm per traversal, λ·p̃·s·H_c in seconds independent of τ0) should be stated in §III, not only in future work.

## F9 [Significant] S6. Pregnolato curve: coefficients verified, but the 300 mm handling and the curve's scope differ from the source
**Location:** §III-C (δ definition); `depth_disruption.dart:17, 26–33, 49–59`; `hazard_classes.yaml` (`h_max_mm_pedestrian`).

**Claimed problem:** s:**
  1. The fitted quadratic gives v(300) = 2.07 km/h, not 0, and has its vertex at 307.2 mm. The code clamps h to 300, so every depth ≥ 300 mm (500 mm, 1 m) yields v_safe = 2.07 km/h and a *finite* δ ≈ 14.5 on a 30 km/h street. The source treats 300 mm as impassable. The `vSafe <= 0 → ∞` branch at `depth_disruption.dart:56` is unreachable dead code. If it were made reachable, 0·∞ = NaN in `edge_cost.dart:109` whenever p̃ = 0.
  2. *δ ≥ 1 clamp.* The paper's justification, "for shallow water on a slow street", understates how wide the δ = 1 region is. Solving v(h) = v0 gives δ = 1 for every h below 166 mm (20 km/h residential), 131 mm (30 km/h), 102 mm (40 km/h), 76 mm (50 km/h) and 53 mm (60 km/h). Graph speeds max out at 70 km/h, so no edge has δ > 1 at zero depth. On most Chennai streets the slowdown term is therefore zero over roughly the first 130–170 mm and then rises steeply, so it acts almost like a step. The clamp is the natural reading of Pregnolato's min(v, v(w)) usage, so the paper can say that instead of presenting it as an implementation patch.
  3. *Scope.* The curve was fitted for passenger cars. It is applied unchanged to the emergency class (Kramer et al. 2016, cited inside Pregnolato, give 0.6 m wading for emergency vehicles) and to pedestrians. `h_max_mm_pedestrian` exists in the YAML but is never read; `EdgeHazardConfig` has one h_max per edge regardless of user class.

## F10 [Significant] S7. The static prior is used as P(flooded now) at all times
**Location:** §III-A ("a static prior log-odds ℓ0(e) encodes susceptibility"); §V-A (GCC category → 0.02–0.45).

**Claimed problem:** Hazard-zone categories describe susceptibility *given a flood event*. Using them as the unconditional probability that an edge is flooded at query time means that on a dry day every "Very High" edge carries p̄ = 0.45. With z = 2 that becomes p̃ = 1, and with z = 1.28 also p̃ = 1. Ageing evidence decays back to this level, not to near zero.
