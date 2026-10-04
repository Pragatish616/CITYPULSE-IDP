# Strand D — Confidence Decay, Information Freshness, Trust in Crowdsourced Geodata, Uncertainty Quantification and Explainability

**Research Agent D · CityPulse AI · 2026-09-11**

Scope: the literature underpinning the project's two headline novelty claims — "dynamic
confidence-decay scoring based on signal age" and "agentic natural-language explanation of
routing decisions". This strand is written sceptically: the brief asserts novelty that the
literature largely does not support, and the report says so explicitly in §9.

All citations below were located and checked via live web search/fetch during this session.
Where a bibliographic field could not be confirmed it is marked `[unverified]` rather than
guessed. No citation in this document is invented.

---

## 0. Executive summary

1. **"Confidence decays with age" is not a research contribution.** It is the standard
   practice of at least four mature literatures (Bayesian reputation, evidence theory,
   robotic map persistence, incident-duration survival analysis). CityPulse's version of it
   is, at present, weaker than a 2002 paper (§2.1).
2. **The brief's worked example is empirically backwards.** "2-min-old flood = max weight;
   3-hour-old unverified obstacle = low confidence" implies floods decay fast. Urban flood
   inundation in a city like Chennai persists for hours to days; loose debris clears in
   minutes. A single global λ is not merely crude, it is *wrong in the direction that
   matters for safety*. Per-hazard-class, covariate-conditional decay is a correctness
   requirement, not a refinement (§7, §8.1).
3. **Recommended formulation:** a Bayesian persistence filter — a two-state
   presence/absence process with a *Weibull* (not exponential) survival prior whose scale
   and shape are fitted per hazard class by interval-censored survival regression, updated
   recursively against positive reports, explicit refutations, and **silence** (traversals
   that produced no report). Surface it to the UI as a Subjective Logic triple
   (belief / disbelief / uncertainty) so "stale" is visually distinguishable from "refuted".
   The pitched pure-exponential decay is retained as the *provably correct observation-free
   marginal* of this model, which is exactly the offline case (§6, §7).
4. **Learning λ from data is sound engineering but is not, by itself, publishable.**
   Hazard-based duration modelling of road incidents has existed since at least Nam &
   Mannering (2000). What is potentially publishable is the *closed loop*: learned survival
   model → per-edge belief → routing cost → measured calibration and measured human
   reliance (§7.3).
5. **Novelty verdict:** every component is prior art; the specific union appears unpublished
   but the gap is a systems-integration gap, not a methods gap. Workshop-tier at best, and
   only with real evaluation attached (§9).

---

## 1. Information freshness: Age of Information (AoI)

### 1.1 Foundational definitions

AoI was introduced to answer a scheduling question — how often a source should push status
updates so that a remote monitor's information stays fresh.

- **Kaul, S., Yates, R., Gruteser, M. (2012).** *Real-Time Status: How Often Should One
  Update?* IEEE INFOCOM 2012, pp. 2731–2735.
  <https://www.winlab.rutgers.edu/~gruteser/papers/sanjitnew.pdf> ·
  DOI `10.1109/INFCOM.2012.6195689`

  Defines the age process. If `U(t)` is the generation timestamp of the most recent update
  received by the monitor at time `t`, then

  ```
  Δ(t) = t − U(t)
  ```

  a sawtooth that grows linearly between deliveries and drops on each delivery. The key
  early result is non-obvious and relevant here: **age is not minimised by maximising update
  rate**. Flooding the channel builds queueing delay, so stale packets arrive; there is an
  interior optimum. Any CityPulse ingest design that assumes "more reports = fresher map"
  is contradicted by the founding paper of the field it wants to borrow from.

- **Yates, R. D., Sun, Y., Brown, D. R., Kaul, S. K., Modiano, E., Ulukus, S. (2021).**
  *Age of Information: An Introduction and Survey.* IEEE Journal on Selected Areas in
  Communications 39(5):1183–1210. arXiv:2007.08564 ·
  <https://arxiv.org/pdf/2007.08564> · DOI `10.1109/JSAC.2021.3065072`

  The canonical survey. Covers peak age, average age, age-optimal sampling, and
  multi-source age. Also the correct single citation if CityPulse wants to reference AoI
  without overclaiming.

### 1.2 Non-linear age penalty — the part CityPulse actually needs

Linear age is the wrong penalty for hazards: the harm of acting on a stale flood report is
not proportional to its age; it is a function of the probability the flood has receded.

- **Sun, Y., Cyr, B. (2019).** *Sampling for Data Freshness Optimization: Non-linear Age
  Functions.* Journal of Communications and Networks 21(3):204–219. arXiv:1812.07241 ·
  <https://arxiv.org/abs/1812.07241> · DOI `10.1109/JCN.2019.000035`

  Generalises age to `p(Δ)` for an arbitrary non-decreasing penalty function, and shows the
  optimal sampling policy is a threshold policy in the *penalty*, not the age. This is the
  formal licence for CityPulse to use an exponential/Weibull confidence curve rather than
  raw elapsed time: `p(Δ) = 1 − S_T(Δ)` where `S_T` is the hazard's survival function.

### 1.3 Has AoI been applied to hazard/incident data? — No, not meaningfully

Searches for AoI applied to emergency/disaster/incident freshness returned only the adjacent
data-quality literature, not AoI proper:

- **Bharosa, N., Lee, J., Janssen, M. et al.** — data quality and information quality during
  disaster response is discussed qualitatively, e.g. *Data Quality for Situational Awareness
  during Mass-Casualty Events*, AMIA Annu Symp Proc.
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC2655881/>
- *The role of data and information quality during disaster response decision-making*,
  Progress in Disaster Science (2021).
  <https://www.sciencedirect.com/science/article/pii/S2590061721000624>

**Assessment (blunt).** AoI is a *queueing/scheduling* theory. Its object of study is the
control of update timing over a constrained channel. CityPulse does not control when citizens
report; it has no transmission scheduling problem. Importing the AoI vocabulary is therefore
decoration, and a reviewer who knows the field will say so. The one legitimate use is §1.2:
cite Sun & Cyr for the *non-linear penalty* formalism, and be explicit that the penalty
function is derived from a survival model, not from AoI optimisation. If the team wants a
defensible AoI angle, the only real one is in the **sync/offline** path — the edge device
*does* have a transmission scheduling problem when reconnecting, and minimising peak age of
the hazard map across a fleet of intermittently-connected devices is a genuine AoI problem.
That is a different paper from the one the brief describes.

---

## 2. Temporal decay in trust and reputation systems

### 2.1 Beta reputation with a forgetting factor (the baseline CityPulse must beat)

- **Jøsang, A., Ismail, R. (2002).** *The Beta Reputation System.* Proc. 15th Bled
  Electronic Commerce Conference, Bled, Slovenia, 17–19 June 2002.
  <https://people.cs.vt.edu/~irchen/5984/pdf/Josang-BECC02.pdf> ·
  <https://aisel.aisnet.org/bled2002/41/>

  Evidence is a count pair `(r, s)` of positive and negative feedback; belief is the
  posterior `Beta(r+1, s+1)`. The reputation rating is

  ```
  Rep(r, s) = E[Beta(r+1, s+1)] − 0.5 = (r − s) / (r + s + 2)      (their Eq. 6)
  ```

  and **temporal forgetting is their Eq. 13** — a first-order recursive discount:

  ```
  r⁽ⁿ⁾ = λ · r⁽ⁿ⁻¹⁾ + (1 − λ) · rₙ
  s⁽ⁿ⁾ = λ · s⁽ⁿ⁻¹⁾ + (1 − λ) · sₙ ,      0 ≤ λ ≤ 1
  ```

  (Equations transcribed from the PDF during this session.) This is a 24-year-old published
  mechanism that already does everything the brief claims as novel, *and does it better*,
  because it also carries negative evidence and an explicit posterior variance.

- **Jøsang, A., Quattrociocchi, W. (2009).** *Advanced Features in Bayesian Reputation
  Systems.* TrustBus 2009, Springer LNCS.
  <https://www.mn.uio.no/ifi/english/people/aca/josang/publications/jq2009-trustbus.pdf>

  Adds continuous-time (rather than per-event) decay, base rates, and multinomial ratings.

### 2.2 Subjective Logic — principled, decaying *confidence* (not just a score)

- **Jøsang, A. (2001).** *A Logic for Uncertain Probabilities.* International Journal of
  Uncertainty, Fuzziness and Knowledge-Based Systems 9(3):279–311.
- **Jøsang, A. (2016).** *Subjective Logic: A Formalism for Reasoning Under Uncertainty.*
  Springer. DOI `10.1007/978-3-319-42337-1`. Tutorial version:
  <https://www.auai.org/uai2016/tutorials_pres/subj_logic.pdf>
- **Jøsang, A., Kaplan, L. (2016).** *Principles of Subjective Networks.* FUSION 2016.
  <https://www.mn.uio.no/ifi/english/people/aca/josang/publications/jk2016-fusion.pdf>
- **Empirical caution:** *Subjective Logic Operators in Trust Assessment: an Empirical
  Study*, Information Systems Frontiers (2015).
  <https://link.springer.com/article/10.1007/s10796-014-9522-5> — different SL fusion
  operators give materially different answers on the same data; the choice is not neutral.

  A binomial opinion is `ω = (b, d, u, a)` with `b + d + u = 1` and base rate `a`; the
  projected probability is `P = b + a·u`. The bijection to Beta evidence is

  ```
  b = r / (r + s + 2),   d = s / (r + s + 2),   u = 2 / (r + s + 2)
  ```

  **Why this matters for CityPulse specifically:** a scalar "confidence" cannot distinguish
  *"we have no idea any more"* from *"three people just told us the road is clear"*. SL
  keeps them apart as `u` and `d`. A confidence-flagged UI that collapses them is
  communicating something false.

### 2.3 Dempster–Shafer with discounting / credibility decay

- **Shafer, G. (1976).** *A Mathematical Theory of Evidence.* Princeton University Press.
  Shafer's discounting operator: a source with reliability `α` has its mass function
  discounted `m^α(A) = α·m(A)` for `A ≠ Θ`, `m^α(Θ) = 1 − α + α·m(Θ)` — the classical way to
  down-weight an unreliable (or here, stale) source.
- **Song, Y., Wang, X., Lei, L., Xing, Y. (2015).** *Credibility decay model in temporal
  evidence combination.* Information Processing Letters 115(2). DOI
  `10.1016/j.ipl.2014.09.022` ·
  <https://www.sciencedirect.com/science/article/abs/pii/S0020019014001999>
  (Authors/venue/DOI confirmed via Semantic Scholar API this session.) Time-decaying
  credibility applied as a discount before Dempster combination — i.e. *literally the
  paper the brief's "decay score" step describes*, published in 2015.
- **Multi-criteria discounting under unreliable sources**, Information Sciences (2018).
  <https://www.sciencedirect.com/science/article/abs/pii/S0020025518301658>

  **Caution:** Dempster's rule behaves counter-intuitively under high conflict (Zadeh's
  counterexample), and DS belief/plausibility intervals are not probabilities, so they cannot
  be scored with proper scoring rules. For a system whose headline evaluation should be
  *calibration*, DS is the wrong choice. Cite it, do not build on it.

### 2.4 Decay in adjacent applied trust literatures (all prior art)

- Trust management in VANETs, incl. time-decayed event credibility — systematic review:
  <https://link.springer.com/article/10.1186/s13638-015-0353-y> ; comprehensive review:
  <https://www.frontiersin.org/journals/the-internet-of-things/articles/10.3389/friot.2022.995233/full>
- Mobile crowdsensing, time-aware/trust-weighted sensing data: *Trust-Based Time Series Data
  Model for Mobile Crowdsensing*, IEEE ICC 2017.
  <https://zhengzhenzhe220.github.io/papers/icc17.pdf>
- *Data Trustworthiness Evaluation in Mobile Crowdsensing Systems with Users' Trust
  Dispositions' Consideration*, Sensors (2019).
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC6471370/>

---

## 3. Volunteered Geographic Information (VGI): quality and trust

- **Goodchild, M. F. (2007).** *Citizens as sensors: the world of volunteered geography.*
  GeoJournal 69(4):211–221. DOI `10.1007/s10708-007-9111-y`. The origin of the term VGI.
- **Goodchild, M. F., Li, L. (2012).** *Assuring the quality of volunteered geographic
  information.* Spatial Statistics 1:110–120. DOI `10.1016/j.spasta.2012.03.002` ·
  <https://people.geog.ucsb.edu/~good/275/vgiquality.pdf>

  The three-approach framework CityPulse should structure its trust model around:
  **crowdsourcing** (Linus's Law — convergence through many eyes), **social** (a hierarchy of
  trusted gatekeepers/moderators), and **geographic** (consistency with known geographic
  facts — e.g. a flood report on a ridge line is implausible; a flood report in a known
  low-lying drainage-deficient ward is prior-plausible). The *geographic* approach is the one
  CityPulse can exploit cheaply via elevation/drainage data and is under-used in the
  crowdsourced-hazard space.

- **Haklay, M. (2010).** *How good is volunteered geographical information? A comparative
  study of OpenStreetMap and Ordnance Survey datasets.* Environment and Planning B: Planning
  and Design 37(4):682–703. DOI `10.1068/b35097` ·
  <https://journals.sagepub.com/doi/10.1068/b35097>
  Empirical positional accuracy ~6 m and strongly uneven completeness by area deprivation —
  relevant because CityPulse's OSM base graph quality in Chennai is an *unvalidated
  assumption* in the brief.

- **Keßler, C., de Groot, R. T. A. (2013).** *Trust as a Proxy Measure for the Quality of
  Volunteered Geographic Information in the Case of OpenStreetMap.* AGILE 2013, Springer
  LNG&C, pp. 21–37. DOI `10.1007/978-3-319-00615-4_2` ·
  <https://link.springer.com/chapter/10.1007/978-3-319-00615-4_2>
  Derives a trust value for a feature from its *provenance* — edit history, number of
  distinct editors, revision count, rollbacks. Directly transferable: a hazard report's
  prior credibility `c₀` should be a function of reporter history, not a constant.

- **Barron, C., Neis, P., Zipf, A. (2014).** *A Comprehensive Framework for Intrinsic
  OpenStreetMap Quality Analysis.* Transactions in GIS 18(6):877–895. DOI
  `10.1111/tgis.12073` — ~25 intrinsic (no-reference-data) quality indicators. Useful because
  CityPulse will have no ground-truth hazard map.

- **Senaratne, H., Mobasheri, A., Ali, A. L., Capineri, C., Haklay, M. (2017).** *A review of
  volunteered geographic information quality assessment methods.* International Journal of
  Geographical Information Science 31(1):139–167. DOI `10.1080/13658816.2016.1189556`
  [venue/DOI from memory — verify before citing in a submission]

- Trust/reputation modelling for VGI, further: *Data trustworthiness and user reputation as
  indicators of VGI quality*, Geo-spatial Information Science (2018).
  <https://www.tandfonline.com/doi/pdf/10.1080/10095020.2018.1496556>

---

## 4. Truth discovery and fusion from unreliable sources

- **Yin, X., Han, J., Yu, P. S. (2008).** *Truth Discovery with Multiple Conflicting
  Information Providers on the Web* (TruthFinder). IEEE TKDE 20(6):796–808. Conference
  version: KDD 2007, DOI `10.1145/1281192.1281309` ·
  <http://hanj.cs.illinois.edu/pdf/kdd07_xyin.pdf>
  The founding iterative fixpoint: source trustworthiness = average confidence of its facts;
  fact confidence = accumulated trust of its sources. Alternate to convergence.

- **Li, Q., Li, Y., Gao, J., Zhao, B., Fan, W., Han, J. (2014).** *Resolving Conflicts in
  Heterogeneous Data by Truth Discovery and Source Reliability Estimation* (CRH). ACM SIGMOD
  2014. DOI `10.1145/2588555.2610509` ·
  <https://dl.acm.org/doi/10.1145/2588555.2610509>
  Optimisation framing: minimise `Σ_s w_s Σ_o d(v_s^o, v*^o)` jointly over source weights `w`
  and truths `v*`, with per-datatype loss `d`. Handles categorical *and* continuous claims in
  one objective — relevant because CityPulse hazard reports mix type (categorical) with depth
  or severity (continuous).

- **Wang, D., Kaplan, L., Le, H., Abdelzaher, T. (2012).** *On truth discovery in social
  sensing: a maximum likelihood estimation approach.* ACM/IEEE IPSN 2012. DOI
  `10.1145/2185677.2185737` · journal version: *Maximum likelihood analysis of conflicting
  observations in social sensing*, ACM TOSN (2014), DOI `10.1145/2530289`
  EM over (source reliability, claim truth) with **confidence bounds** on the estimated
  truth — the social-sensing/Apollo line. <http://apollo2.cs.illinois.edu/publications.html>

- **Ouyang, R. W., Srivastava, M., Toniolo, A., Norman, T. J. (2016).** *Truth Discovery in
  Crowdsourced Detection of Spatial Events.* IEEE TKDE 28(4):1047–1060.
  <https://ieeexplore.ieee.org/document/7345583/> ·
  <https://eprints.soton.ac.uk/403233> (CIKM 2014 precursor, DOI `10.1145/2661829.2662003`)
  **The closest methodological match to CityPulse's ingest problem.** Unsupervised
  Truth-and-Spatial-Event (TSE) and Personalised TSE models that jointly infer whether a
  spatial event is real and how reliable each participant is, *without* requiring location
  tracking, explicitly modelling uncertainty in participant mobility. Anyone claiming novelty
  in "fusing noisy crowdsourced spatial hazard reports" has to deal with this paper.

- **Li, Y., Gao, J., Meng, C., Li, Q., Su, L., Zhao, B., Fan, W., Han, J. (2016).** *A Survey
  on Truth Discovery.* ACM SIGKDD Explorations 17(2):1–16. DOI `10.1145/2897350.2897352`

**Gap worth noting honestly:** classical truth discovery assumes a *static* truth. A hazard
is not static — it appears and clears. The temporal extension is exactly the persistence
problem in §5, and coupling source-reliability estimation with a temporal persistence model
is the one genuinely thin area in this literature.

---

## 5. Bayesian / recursive estimation of hazard persistence

### 5.1 Terminology collision — flag this explicitly in the write-up

"Hazard" in survival analysis means the *instantaneous failure rate* `λ(t)` of a lifetime
distribution. "Hazard" in CityPulse means a flood or an obstacle. The models below use the
first sense to model the lifetime of the second. Any paper must define both on first use or
reviewers will be confused.

### 5.2 The persistence filter (recommended backbone)

- **Rosen, D. M., Mason, J., Leonard, J. J. (2016).** *Towards Lifelong Feature-Based Mapping
  in Semi-Static Environments.* IEEE ICRA 2016.
  <https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/44821.pdf>

  Extracted from the PDF during this session. Each map feature has an unobserved survival
  time `T ~ p_T(·)`; existence indicator `X_t = 1 ⟺ t ≤ T`; a noisy detector with missed
  detection probability `P_M` and false alarm probability `P_F` produces observations `Y_t`.

  ```
  S_T(t) = P(T > t) = exp(−Λ_T(t)),    Λ_T(t) = ∫₀ᵗ λ_T(x) dx
  ```

  Posterior persistence belief for `t ≥ t_N`:

  ```
  p(X_t = 1 | Y_{1:N}) = [ p(Y_{1:N} | t_N) / p(Y_{1:N}) ] · (1 − F_T(t))
  p(Y_{1:N}) = Σ_i p(Y_{1:N} | t_i) [ F_T(t_{i+1}) − F_T(t_i) ]
  ```

  maintained recursively in **constant time and memory per observation** — critical for the
  on-device/offline requirement. They use the exponential prior `p_T(t;λ) = λe^{−λt}` as the
  maximum-entropy default *when only the mean lifetime is known*. That is the honest
  justification for exponential decay, and it also states the condition under which you
  should abandon it: as soon as you have lifetime data, you know more than the mean, and
  max-entropy no longer recommends the exponential.

### 5.3 HMM / Markov occupancy formulations

- **Rapp, M. et al. (2016).** *Hidden Markov model-based occupancy grid maps of dynamic
  environments.* FUSION 2016. <https://ieeexplore.ieee.org/document/7528099>
  [full author list not confirmed — dblp key `conf/fusion/RappDHDD16`]
- **Meyer-Delius, D., Beinhofer, M., Burgard, W. (2012).** *Occupancy grid models for robot
  mapping in changing environments.* AAAI 2012.
  <https://dl.acm.org/doi/10.5555/2900929.2901014> — per-cell two-state Markov chain with
  learned transition rates; the discrete-time analogue of §5.2.
- *Transitional Grid Maps: Joint Modeling of Static and Dynamic Occupancy* (2024).
  <https://arxiv.org/html/2401.06518v2>

### 5.4 Incident lifetimes — where the decay rate actually comes from

- **Nam, D., Mannering, F. (2000).** *An exploratory hazard-based analysis of highway
  incident duration.* Transportation Research Part A 34(2):85–102.
  <https://ideas.repec.org/a/eee/transa/v34y2000i2p85-102.html>
  Separately models detection/reporting, response and clearance durations with Weibull and
  log-logistic hazards; finds **duration dependence** — i.e. the exponential (memoryless)
  assumption is rejected by the data.
- **Hojati, A. T., Ferreira, L., Washington, S., Charles, P. (2013).** *Hazard based models
  for freeway traffic incident duration.* Accident Analysis & Prevention.
  <https://www.sciencedirect.com/science/article/abs/pii/S0001457512004599>
- *Traffic incident duration analysis and prediction models based on the survival analysis
  approach*, IET Intelligent Transport Systems (2014). DOI `10.1049/iet-its.2014.0036`
- *Incorporating real-time weather conditions into analyzing clearance time of freeway
  accidents: a grouped random parameters hazard-based duration model with time-varying
  covariates*, Analytic Methods in Accident Research (2023).
  <https://www.sciencedirect.com/science/article/abs/pii/S2213665723000027>
  — the state of the art: **time-varying covariates** (rainfall intensity) inside the hazard
  function. This is exactly what CityPulse needs for monsoon flooding and it already exists.
- *Statistical and machine-learning methods for clearance time prediction of road incidents:
  a methodology review* (2020).
  <https://www.sciencedirect.com/science/article/abs/pii/S2213665720300130>

**Consequence for the novelty claim:** a 25-year-old literature already fits
covariate-conditional survival models to exactly the quantity CityPulse calls λ. "We learn λ
from data" is a method transfer, not a discovery.

---

## 6. Candidate confidence-decay formulations

Notation throughout: a hazard report `i` of class `h` on road segment `e`, created at `t₀`,
age `Δ = t − t₀`. `c(t) ∈ [0,1]` is the system's belief that the hazard is *currently
present*. `S_h(·)` is the survival function of hazard class `h`'s lifetime.

### Model A — Exponential decay with hazard-class-specific rate (the pitched model)

```
c(t) = c₀ · exp(−λ_h · Δ)              λ_h = ln 2 / t½,h
```

- **Parameters:** `c₀` (prior credibility of the report — from reporter reputation and
  corroboration count); `λ_h`, ideally expressed as a half-life `t½,h` because that is what a
  civic partner can actually reason about ("a waterlogging report is half-believed after
  90 minutes").
- **Assumptions:** the lifetime `T ~ Exp(λ_h)`, i.e. **memoryless** — the probability the
  hazard clears in the next minute is independent of how long it has already persisted.
- **Literature:** max-entropy justification in Rosen et al. (2016) §5.2; forgetting-factor
  analogue in Jøsang & Ismail (2002) Eq. 13; time-discounted credibility in Song et al.
  (2015); non-linear age penalty framing in Sun & Cyr (2019).
- **Pros:** one parameter; `O(1)` and stateless — computable from the timestamp alone, so it
  survives a Redis restart and a total loss of connectivity; trivially explainable to a user;
  composes with everything downstream.
- **Cons:** (i) memorylessness is *empirically rejected* for road incidents (Nam & Mannering
  2000); (ii) it cannot go **up**, so a confirming report cannot restore confidence; (iii) it
  cannot represent refutation — decaying toward 0 asserts "the hazard is gone", when the
  truthful statement is "we no longer know"; (iv) `c₀` must smuggle in all source-reliability
  information with no mechanism for doing so.
- **Verdict:** keep as the offline/degraded-mode fallback only (see §7).

### Model B — Beta reputation with temporal discounting

Maintain per (segment, hazard-class) discounted evidence counts. In continuous time:

```
r(t) = Σ_{i ∈ pos} w_i · exp(−λ_h (t − t_i))
s(t) = Σ_{j ∈ neg} w_j · exp(−λ_h (t − t_j))

c(t) = E[Beta(r + α, s + β)] = (r(t) + α) / (r(t) + s(t) + α + β)
Var  = (r+α)(s+β) / [ (r+s+α+β)² (r+s+α+β+1) ]
```

with `α, β` encoding the **base rate** — e.g. the climatological probability that this
segment is flooded at this hour in this season (not `α = β = 1`).

- **Parameters:** `λ_h` (forgetting rate), `w_i` (per-reporter weights from provenance,
  Keßler & de Groot 2013), `α, β` (prior/base rate).
- **Literature:** Jøsang & Ismail (2002) Eq. 13; Jøsang & Quattrociocchi (2009).
- **Pros:** handles confirmation *and* refutation ("I just drove through, it's clear");
  decays to a meaningful base rate rather than to zero; conjugate, so `O(1)` update; explicit
  posterior variance gives a free, principled epistemic-uncertainty signal (few reports → wide
  posterior → low display confidence even when the point estimate is high); directly grounded
  in the VGI trust literature.
- **Cons:** one λ conflates two distinct physical processes — *the hazard clearing* and *our
  evidence going stale*. These have different timescales (a flood may persist 12 h while a
  report's informativeness about "right now" decays in 30 min). Requires reporter weighting
  to resist spam/sybils, which is a separate subsystem.
- **Verdict:** strong, cheap baseline. **It must appear as a baseline in the evaluation**;
  if CityPulse's model cannot beat 2002 on Brier score, there is no contribution.

### Model C — Subjective Logic opinion with uncertainty-directed decay

Represent each segment-hazard as `ω = (b, d, u, a)`, `b + d + u = 1`, projected probability
`P = b + a·u`. Decay moves mass **into uncertainty**, not into disbelief:

```
b(t) = b₀ · e^{−λ_h Δ}
d(t) = d₀ · e^{−λ_h Δ}
u(t) = 1 − (b₀ + d₀) · e^{−λ_h Δ}
P(t) = b(t) + a · u(t)   →   a   as Δ → ∞
```

Multi-reporter fusion uses SL's cumulative/averaging fusion; each reporter's opinion is first
passed through Jøsang's **trust discounting** operator with that reporter's trust opinion.

- **Parameters:** `λ_h`; base rate `a` per segment/hazard/season; reporter trust opinions;
  choice of fusion operator.
- **Literature:** Jøsang (2001, 2016); Jøsang & Kaplan (2016); empirical operator-sensitivity
  study (Information Systems Frontiers 2015).
- **Pros:** the only formulation in this list whose *semantics match what a confidence-flagged
  UI is supposed to say*. "Stale" (`u` high) and "contradicted" (`d` high) are different
  states and must render differently. Bijective with Beta, so it inherits §Model B's
  statistics for free. Trust discounting is a principled place to put reporter reliability.
- **Cons:** heavier; `a` must be estimated per segment (a real data problem in a city with no
  flood-frequency layer); the exponential decay of `b` and `d` is a modelling choice, **not**
  derived from SL's axioms — which means citing SL does not automatically justify the decay;
  fusion-operator choice materially changes results and there is no consensus.
- **Verdict:** adopt as the **presentation/fusion layer**, not the estimator.

### Model D — Bayesian persistence filter / HMM with a learned survival prior (**recommended**)

Latent state `X_t ∈ {1 = present, 0 = absent}`. Survival prior `S_h(Δ | x)` conditioned on
covariates `x` (rainfall in the last 3 h, road class, elevation/drainage index, hour of day,
season, hazard sub-type). Observations `Y` with class-specific miss rate `P_M` and false
alarm rate `P_F`.

Discrete-time forward recursion over a step `δ` (this is the implementable form):

```
predict:   b⁻ = b · S_h(Δ+δ | x) / S_h(Δ | x)        [+ μ_h (1 − b) if re-occurrence allowed]
update:    b⁺ = b⁻ · P(y | X=1) / [ b⁻ P(y | X=1) + (1 − b⁻) P(y | X=0) ]

  positive report:   P(y|1) = 1 − P_M ,           P(y|0) = P_F
  explicit "clear":  P(y|1) = P_F' ,              P(y|0) = 1 − P_M'
  silence over δ with n traversals:
                     P(y|1) = P_M^n ,             P(y|0) = (1 − P_F)^n
```

The third case is the important one and is absent from the brief: **a traversal that produces
no report is evidence of clearance**, at a strength governed by `P_M` and the traffic volume
on that edge. With no traversals, it contributes nothing — correctly, because silence on an
empty road at 03:00 means nothing.

With **zero observations** the recursion collapses to

```
b(t) = b₀ · S_h(Δ | x) / [ b₀ · S_h(Δ | x) + (1 − b₀) ]
```

and with a Weibull prior `S_h(Δ) = exp(−(Δ/η_h)^{k_h})` this is a strict generalisation of
Model A (recover Model A exactly at `k_h = 1`, `b₀ ≈ 0`).

- **Parameters:** `(η_h, k_h)` or a regression `log T = x'β + σε` (AFT form); `P_M`, `P_F`
  per hazard class; optional re-occurrence rate `μ_h`; an exposure model for traversals.
- **Literature:** Rosen, Mason, Leonard (2016); Meyer-Delius et al. (2012); Rapp et al.
  (2016); survival priors and covariates from Nam & Mannering (2000), Hojati et al. (2013)
  and the time-varying-covariate hazard models (2023).
- **Pros:** generalises A, B and C; produces a **calibrated probability**, which is the only
  quantity you can legitimately show a user, feed to a routing cost as an expectation, and
  score with a proper scoring rule; uses negative and null evidence properly; the
  hazard-class covariate structure fixes the flood/debris asymmetry that Model A gets wrong;
  constant-time recursive update suits the edge device.
- **Cons:** needs `P_M`/`P_F` estimates and an exposure (traversal-count) model — both
  obtainable but both extra work; cold-start problem for new cities; substantially more to
  explain to a user, which is why it needs Model C as the display layer.
- **Verdict:** **recommended core.**

### Model E — Dempster–Shafer with credibility decay (documented, not recommended)

Discount each report's mass function by a time-decaying reliability `α(Δ) = e^{−λΔ}` before
Dempster combination (Shafer 1976; Song et al. 2015). Pros: represents ignorance explicitly;
handles conflicting evidence. Cons: pathological behaviour under high conflict; belief
intervals are not probabilities, so Brier/ECE do not apply; no advantage over SL, which is
better-behaved and Beta-compatible. Cite for completeness; do not build on it.

---

## 7. Recommended formulation for CityPulse

### 7.1 The recommendation

> **Estimator:** Model D — a per-(segment, hazard) Bayesian persistence filter with a
> Weibull (or log-logistic) survival prior whose parameters are conditioned on covariates and
> **fitted from historical hazard-resolution data by interval-censored survival regression**;
> updated recursively against positive reports, explicit refutations, and traversal-silence.
>
> **Presentation:** Model C — expose the filter output as a Subjective Logic triple
> `(b, d, u)` with a per-segment base rate, so the UI can say "unconfirmed for 40 minutes"
> (high `u`) differently from "two drivers report it clear" (high `d`).
>
> **Offline/edge fallback:** Model A — the closed-form, observation-free marginal of Model D.
> Ship the fitted `(η_h, k_h)` table (a few hundred bytes) to the device; with no network
> there are no new observations, so the exact posterior *is* the survival curve. This is the
> single strongest framing available to the project: **the offline decay curve is not a
> degraded heuristic, it is the mathematically exact marginal of the online model under zero
> observations.** Say it that way in the paper.
>
> **Baselines that must be reported:** fixed TTL (what Waze effectively does), hand-tuned
> constant-λ exponential, Beta-with-forgetting (Jøsang & Ismail 2002), and the base rate.

### 7.2 Two corrections to the brief's design

**(a) The worked example is backwards.** "2-min-old flood = max weight; 3-hour-old unverified
obstacle = low confidence" reads as though flood confidence is the fast-decaying one. Urban
inundation in Chennai persists for hours to days after rainfall stops; a fallen branch is
cleared in tens of minutes. With a single global λ tuned to clear obstacles quickly, the
system will *prematurely route emergency vehicles into standing water*. Per-class λ is a
safety requirement.

**(b) Do not threshold confidence into the routing cost.** The brief implies a
confidence-flagged binary. Thresholding produces route flapping as `c(t)` crosses the
boundary, and users experience an unstable map. Use the belief as a probability inside an
expected-cost or risk-measure edge weight:

```
w(e) = t_free(e) + Σ_h b_h(e) · penalty_h(e)          (risk-neutral)
w(e) = t_free(e) + CVaR_β [ delay(e) ]                 (risk-averse, for EMS)
```

The risk-averse variant is the defensible one for emergency vehicles and gives the
explanation layer something concrete to verbalise ("we avoided Anna Salai because there is a
35 % chance of a 14-minute flood delay").

### 7.3 Learning λ from data — method, and whether it is a contribution

**Method.** Fit an accelerated-failure-time model to hazard lifetimes:

```
log T_i = x_i' β + σ ε_i
```

`x` = hazard class, rainfall intensity/accumulation, road class, elevation and drainage
index, hour of day, season, reporter count. Ground truth `T` is almost always
**interval-censored**: you observe "present at `t₁`" and "absent at `t₂`", not the exact
clearance instant, plus right-censoring for hazards never observed to clear. Use the
interval-censored likelihood; naïvely treating the midpoint as exact will bias `k̂` and is a
mistake reviewers catch.

**Label sources (all obtainable in Chennai):**
- Municipal complaint/closure logs (GCC grievance closure timestamps).
- Rain-gauge and water-level recession curves for flood hazards.
- Later contradicting reports from the crowd.
- **Traffic-speed recovery on the edge** — free-flow speed returning is a strong proxy for
  clearance, and this is the label source with the best coverage.

**Is it publishable?** Bluntly: **not on its own.** Hazard-based duration modelling of road
incidents dates to Nam & Mannering (2000) and has a large, active follow-on literature
including time-varying weather covariates. Fitting a Weibull to incident lifetimes is a
methods course exercise. What *could* carry a workshop paper is the combination:

1. **The closed loop.** Learned survival model → per-edge belief → routing cost → measured
   effect on route choice, on safety violations, and on user compliance. I found survival
   models of incident duration, and I found hazard-aware routing, but not the two wired
   together and evaluated end to end.
2. **Calibration as a first-class evaluation target for civic crowdsourced geodata.** The VGI
   and truth-discovery literatures report precision/recall/accuracy; they very rarely report
   reliability diagrams or ECE. Reporting calibration of a decayed confidence, stratified by
   report age, would be a small but real methodological contribution.
3. **The silence channel.** Using traversals-without-reports as Bayesian evidence of
   clearance is standard in robotics (persistence filters) but I found no application to
   crowdsourced *urban hazard* maps. This is the most defensible novel element in the whole
   project.
4. **Explanation faithfulness bound to the belief state** (§8.2).

Realistic target venues: SIGSPATIAL ARIC workshop, ISCRAM, IEEE GHTC, or an automotive-UI /
CHI LBW venue for the human-study half. Not a top-tier ML or DB contribution, and the team
should stop describing it as one.

---

## 8. How to evaluate this

### 8.1 Evaluating the confidence model

**Prediction task.** For report `i` at query time `t`, predict `P(hazard still present)`.
Ground truth from held-out resolution records (municipal closure logs, gauge recession,
verified follow-up reports, speed recovery).

**Metrics.**
- **Brier score** with **Murphy's (1973) three-component decomposition** into
  *reliability − resolution + uncertainty*. Report all three. Reliability is the calibration
  term; resolution is the "is the model saying anything useful" term. A model can win on
  Brier purely by predicting the base rate — the decomposition exposes that.
  - Brier, G. W. (1950). *Verification of Forecasts Expressed in Terms of Probability.*
    Monthly Weather Review 78(1):1–3.
  - Murphy, A. H. (1973). *A New Vector Partition of the Probability Score.* Journal of
    Applied Meteorology 12(4):595–600.
    <https://journals.ametsoc.org/view/journals/apme/12/4/1520-0450_1973_012_0595_anvpot_2_0_co_2.xml>
- **Reliability diagrams**, stratified by **report-age bucket** (0–5 min, 5–30 min, 30 min–2 h,
  2–12 h, >12 h) and by hazard class. This is the single most informative plot the project can
  produce and it directly tests the decay curve rather than the aggregate.
- **ECE / adaptive-ECE** with equal-mass bins, reported alongside the bin count — ECE is
  bin-sensitive and biased; do not report a bare ECE number.
  - Guo, C., Pleiss, G., Sun, Y., Weinberger, K. Q. (2017). *On Calibration of Modern Neural
    Networks.* ICML 2017, PMLR 70:1321–1330. <https://arxiv.org/abs/1706.04599>
- **Log loss** (penalises confident errors, which is the failure mode that hurts in routing).
- **AUROC** separately, to check discrimination independently of calibration.

**Baselines (mandatory).** Fixed TTL; constant-λ exponential with hand-tuned half-life;
Beta-with-forgetting (Jøsang & Ismail 2002); base rate. **If the learned model does not beat
the hand-tuned exponential on Brier, report that, and drop the novelty claim.**

**Ablations.** (i) no negative/silence evidence; (ii) no covariates (global λ); (iii)
exponential vs Weibull prior (tests the memorylessness assumption directly); (iv) no reporter
weighting.

**Splitting.** Never random-split. Reports from one flood event are strongly correlated;
random splits leak and will inflate results by a lot. Split by **event** and by **monsoon
episode**, and additionally hold out a **geographic** region to test transfer (the brief's
"designed for every city" claim).

**Routing-level metrics** — these are what actually matter and the calibration numbers alone
will not convince a reviewer:
- Excess travel time vs an oracle that knows true hazard states.
- **Safety violations:** routes sent through a hazard that was in fact present.
- **Unnecessary detour cost:** detours taken around hazards that had already cleared.
- Sweep the decision threshold / risk parameter and plot the **safety–efficiency Pareto
  frontier**, per hazard class. A single operating point is not an evaluation.

**Offline/online consistency** (specific to this project's central claim):
- Belief divergence (KL or absolute) between the edge model and the server model as a
  function of disconnection duration.
- **Decision divergence:** the fraction of routing decisions that differ between edge and
  server after `n` minutes offline. This is the number that substantiates or refutes "fully
  functional routing with zero external connectivity", and the project should be prepared for
  it to look bad past ~30 minutes.

### 8.2 Evaluating the explanations

**Why this needs teeth.** Turpin et al. show that plausible, fluent LLM explanations are
routinely *unfaithful* to the actual decision process. In a safety-critical routing context, a
fluent explanation of a wrong route is worse than no explanation.

- **Turpin, M., Michael, J., Perez, E., Bowman, S. R. (2023).** *Language Models Don't Always
  Say What They Think: Unfaithful Explanations in Chain-of-Thought Prompting.* NeurIPS 2023.
  <https://arxiv.org/abs/2305.04388>
- **Jacovi, A., Goldberg, Y. (2020).** *Towards Faithfully Interpretable NLP Systems: How
  Should We Define and Evaluate Faithfulness?* ACL 2020.
  <https://aclanthology.org/2020.acl-main.386/>
- **Miller, T. (2019).** *Explanation in Artificial Intelligence: Insights from the Social
  Sciences.* Artificial Intelligence 267:1–38. DOI `10.1016/j.artint.2018.07.007` ·
  <https://arxiv.org/abs/1706.07269> — explanations are **contrastive** ("why this route
  rather than that one"), **selected** (not exhaustive), and **social**. A route explanation
  that lists all avoided hazards is, by this account, a bad explanation.
- **Doshi-Velez, F., Kim, B. (2017).** *Towards A Rigorous Science of Interpretable Machine
  Learning.* arXiv:1702.08608 — the functionally-grounded / human-grounded / application-
  grounded evaluation taxonomy.

**Automatic faithfulness checks** (cheap, run in CI, no humans needed):
1. **Grounding / unsupported-claim rate.** Every street name, hazard class, confidence value
   and timestamp in the generated text must resolve to an object in the belief state. Parse
   the output and check. Report the unsupported-claim rate; the target for a safety system is
   zero.
2. **Contrastive validity.** If the explanation says "we avoided Route B because of flooding
   on X", then X must actually be on Route B *and* the flood penalty on X must be a material
   term in the cost difference `w(B) − w(A)`. This is directly computable from the router and
   is the strongest faithfulness test available in this setting. Make it a hard gate.
3. **Counterfactual consistency.** Perturb the belief state — remove the hazard, halve its
   confidence, change its class — and verify the explanation changes in the corresponding
   direction. An explanation invariant to the thing it claims to be explaining is unfaithful
   by construction.
4. **Simulatability.** Can a held-out judge (human or a separate model) predict the chosen
   route from the explanation alone?
5. **Adversarial hallucination audit.** Prompt with empty hazard sets, contradictory hazard
   sets, and hazards with `u ≈ 1`. Measure the fabricated-hazard rate and the rate at which
   the model asserts confidence the belief state does not support. Report it. This is
   non-negotiable for a safety-framed system.

**Human study design.**
- **Design:** within-subjects, 3 conditions — (1) route only, (2) route + confidence
  indicator, (3) route + confidence + NL explanation. Counterbalanced scenario order.
- **N:** ≥ 40 for a within-subjects design powered for medium effects; preregister the power
  analysis.
- **Critical design point — manipulate ground truth.** Include scenarios where the system is
  **right** and scenarios where it is **wrong**. Then measure **appropriate reliance**:
  `agreement | system correct` − `agreement | system wrong`. A condition that raises trust
  uniformly across both is an **automation-bias failure**, not a success. Reporting only
  aggregate trust would be the single most likely way for this project to draw a wrong
  conclusion.
- **Measures:** compliance/route-acceptance rate; self-reported trust; **Explanation
  Satisfaction Scale** and the trust scale from Hoffman et al.; decision time; NASA-TLX if
  workload is a concern; free-text critique for qualitative failure modes.
  - **Hoffman, R. R., Mueller, S. T., Klein, G., Litman, J. (2018).** *Metrics for
    Explainable AI: Challenges and Prospects.* arXiv:1812.04608.
    <https://arxiv.org/abs/1812.04608> ; journal version (2023), *Measures for explainable
    AI: explanation goodness, user satisfaction, mental models, curiosity, trust, and
    human-AI performance*, Frontiers in Computer Science 5:1096257.
  - **Lee, J. D., See, K. A. (2004).** *Trust in Automation: Designing for Appropriate
    Reliance.* Human Factors 46(1):50–80. — "appropriate reliance", not "more trust", is the
    design goal.
  - **Parasuraman, R., Riley, V. (1997).** *Humans and Automation: Use, Misuse, Disuse,
    Abuse.* Human Factors 39(2):230–253.
  - **Koo, J., Kwac, J., Ju, W., Steinert, M., Leifer, L., Nass, C. (2015).** *Why did my car
    just do that? Explaining semi-autonomous driving actions to improve driver understanding,
    trust, and performance.* International Journal on Interactive Design and Manufacturing
    9(4):269–275. DOI `10.1007/s12008-014-0227-2` ·
    <https://link.springer.com/article/10.1007/s12008-014-0227-2>
    Finding directly relevant to CityPulse: "why" explanations improved understanding and
    trust, but "how + why" together **increased anxiety and degraded driving performance**.
    More explanation is not monotonically better. Test explanation *length* as a factor.
- **Ethics:** institutional approval; the failure scenarios must be clearly simulated.

**Uncertainty display sub-study.** Compare (a) numeric percentage, (b) discrete 3-level badge,
(c) age-based natural phrasing ("reported 4 minutes ago, unconfirmed"), (d) a confidence
interval / graded visual.
- **MacEachren, A. M., Roth, R. E., O'Brien, J., Li, B., Swingley, D., Gahegan, M. (2012).**
  *Visual Semiotics & Uncertainty Visualization: An Empirical Study.* IEEE TVCG
  18(12):2496–2505.
  <https://geography.wisc.edu/cartography/projects/publications/MacEachrenEtAl_2012_TVCG.pdf>
  Empirically ranks visual variables for intuitiveness in depicting uncertainty — fuzziness,
  location, value/lightness and transparency perform best. Use their ranking rather than
  inventing a visual language.
- **Padilla, L., Kay, M., Hullman, J. (2021).** *Uncertainty Visualization.* Wiley StatsRef:
  Statistics Reference Online. DOI `10.1002/9781118445112.stat08296` ·
  <http://space.ucmerced.edu/Downloads/publications/Uncertainty_Visualization_Padilla_Kay_Hullman_2022.pdf>
- **Padilla, L. M. K., Powell, M., Kay, M., Hullman, J. (2021).** *Uncertain About
  Uncertainty: How Qualitative Expressions of Forecaster Confidence Impact Decision-Making
  With Uncertainty Visualizations.* Frontiers in Psychology 11:579267. DOI
  `10.3389/fpsyg.2020.579267` ·
  <https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2020.579267/full>
  **The closest empirical support for CityPulse's core UI claim:** participants integrated a
  qualitative confidence statement *together with* a quantitative uncertainty display, and
  became appropriately more cautious as stated confidence dropped. This is the paper to cite
  for "confidence-flagged UI" and it suggests pairing the numeric belief with a verbal
  confidence phrase rather than choosing one.
- **Joslyn, S., Savelli, S. (2010).** *Communicating forecast uncertainty: public perception
  of weather forecast uncertainty.* Meteorological Applications 17(2):180–195. DOI
  `10.1002/met.190` — lay users systematically misinterpret probabilistic forecasts unless
  the reference class is stated explicitly. "70 % confidence" without "that this road is
  flooded right now" will be misread.
- **Johnson, C., Shea, C., Holloway, C.** *The Role of Trust and Interaction in GPS Related
  Accidents: A Human Factors Safety Assessment of the Global Positioning System.*
  <https://www.dcs.gla.ac.uk/~johnson/papers/GPS/Johnson_Shea_Holloway_GPS.pdf> —
  documents drivers following navigation instructions into hazardous situations against
  direct visual evidence. The existence proof for over-trust in exactly this product category.

---

## 9. Novelty check — has this been done?

Searched hard for the specific combination: confidence-decayed crowdsourced hazard beliefs →
hazard-aware routing → natural-language explanation. Component by component:

| Component | Status | Representative prior art |
|---|---|---|
| Temporal decay of trust in crowdsourced reports | **Prior art, 2002** | Jøsang & Ismail (2002) Eq. 13; Song et al. (2015) credibility decay in DS; VANET trust reviews; MCS time-aware trust |
| Formal information-freshness metric | **Prior art** | Kaul et al. (2012); Yates et al. (2021); non-linear penalties Sun & Cyr (2019) |
| Trust/quality models for VGI | **Prior art, large field** | Goodchild & Li (2012); Keßler & de Groot (2013); Barron et al. (2014) |
| Fusing noisy crowdsourced *spatial event* reports with source reliability | **Prior art, direct match** | Ouyang et al. (2016) TKDE — TSE/PTSE for crowdsourced spatial event detection |
| Bayesian persistence of a latent map feature under noisy detection | **Prior art, direct match** | Rosen, Mason & Leonard (2016); Meyer-Delius et al. (2012); Rapp et al. (2016) |
| Learning hazard-lifetime decay rates from data with covariates | **Prior art, 25 years** | Nam & Mannering (2000); Hojati et al. (2013); time-varying-covariate hazard models (2023) |
| Crowdsourced flood data → risk-informed route optimisation | **Prior art, direct match** | Alizadeh, B., Li, D., Hillin, J., Meyer, M. A., Thompson, C. M., Zhang, Z., Behzadan, A. H. (2022), *Human-centered flood mapping and intelligent routing through augmenting flood gauge data with crowdsourced street photos*, Advanced Engineering Informatics. <https://www.sciencedirect.com/science/article/abs/pii/S1474034622001884> · preprint <https://repository.library.noaa.gov/view/noaa/57328/noaa_57328_DS1.pdf> — **verified this session: no temporal decay, no NL explanations**, but crowd-report → depth estimate → route optimisation is done |
| Routing around flooding from authoritative data, deployed | **Prior art, operational** | openrouteservice / HeiGIT disaster routing with Copernicus EMS flood extents. <https://heigit.org/routenplanung-im-uberflutungsgebiet-openrouteservice-nutzt-copernicus-ems-flut-daten-in-spezieller-losung-2/> |
| Flood-aware / risk-aware path planning | **Prior art, crowded** | e.g. Water Resources Management (2023) DOI `10.1007/s11269-023-03500-5`; Scientific Reports (2025) <https://www.nature.com/articles/s41598-025-06374-2>; Risk Analysis (2025) DOI `10.1111/risa.17599` |
| NL / LLM explanation of route or driving decisions | **Prior art** | Koo et al. (2015); *Constraint-Aware Route Recommendation from Natural Language via Hierarchical LLM Agents*, arXiv:2510.06078 <https://arxiv.org/html/2510.06078>; *HighwayLLM*, Robotics and Autonomous Systems (2025) |
| On-device quantised LLM, offline maps | **Commodity** | — |
| **The exact union** | **Not found as a published system** | — |

### Verdict

**Every ingredient is off-the-shelf and well published. The union appears unpublished, but it
is a systems-integration gap, not a methods gap.** That is a real but narrow kind of novelty,
and it is the kind that gets accepted at applied/workshop venues and rejected at methods
venues.

Specific warnings for the team:

1. **"Core novelty: offline-resilient, confidence-aware routing module" will not survive
   review as stated.** Routing under uncertain/stochastic edge costs is a large existing
   field, and offline routing is what every offline map application does. The sentence claims
   two things that are both standard.
2. **Do not lead with AoI.** The project has no update-scheduling problem, which is what AoI
   is about (§1.3). Using the term decoratively is a tell.
3. **The strongest genuinely-novel elements**, in order:
   (a) traversal-**silence** as Bayesian evidence of clearance in a crowdsourced urban hazard
   map (standard in robotics, not found in this domain);
   (b) **calibration** of an age-decayed confidence as a reported, stratified evaluation
   target for civic crowdsourced geodata;
   (c) **explanation faithfulness gated on the belief state** — the contrastive-validity check
   in §8.2(2) is a concrete, testable contribution;
   (d) framing the offline decay curve as the exact observation-free marginal of the online
   filter, which turns the fallback from a hack into a derivation.
4. **Without a real evaluation this is an engineering project, not research.** A demo plus a
   hand-tuned exponential will be correctly identified as such. The minimum viable research
   contribution is: reliability diagrams over real Chennai hazard-resolution data, beating the
   2002 Beta baseline on Brier, plus a reliance-appropriateness human study.
5. **Out-of-strand but must be said:** "Haven Mode" passively inferring home/work/school/family
   locations from routing history is a significant privacy and research-ethics exposure. It
   will attract ethics-review scrutiny and reviewer hostility, and it is orthogonal to the
   confidence contribution. Consider cutting it from any paper even if it stays in the demo.

---

## 10. Consolidated source list (39 verified sources)

**Age of Information / freshness**
1. Kaul, Yates, Gruteser (2012), IEEE INFOCOM — <https://www.winlab.rutgers.edu/~gruteser/papers/sanjitnew.pdf>
2. Yates, Sun, Brown, Kaul, Modiano, Ulukus (2021), IEEE JSAC 39(5) — <https://arxiv.org/pdf/2007.08564>
3. Sun, Cyr (2019), J. Communications and Networks 21(3) — <https://arxiv.org/abs/1812.07241>

**Trust / reputation / evidence decay**
4. Jøsang, Ismail (2002), Bled EC — <https://people.cs.vt.edu/~irchen/5984/pdf/Josang-BECC02.pdf>
5. Jøsang, Quattrociocchi (2009), TrustBus — <https://www.mn.uio.no/ifi/english/people/aca/josang/publications/jq2009-trustbus.pdf>
6. Jøsang (2001), IJUFKS 9(3):279–311
7. Jøsang (2016), *Subjective Logic*, Springer — DOI `10.1007/978-3-319-42337-1`; tutorial <https://www.auai.org/uai2016/tutorials_pres/subj_logic.pdf>
8. Jøsang, Kaplan (2016), FUSION — <https://www.mn.uio.no/ifi/english/people/aca/josang/publications/jk2016-fusion.pdf>
9. *Subjective Logic Operators in Trust Assessment: an Empirical Study* (2015), Inf. Syst. Frontiers — <https://link.springer.com/article/10.1007/s10796-014-9522-5>
10. Shafer (1976), *A Mathematical Theory of Evidence*, Princeton UP
11. Song, Wang, Lei, Xing (2015), Information Processing Letters 115(2) — DOI `10.1016/j.ipl.2014.09.022`
12. *Multi-criteria discounting in DS theory* (2018), Information Sciences — <https://www.sciencedirect.com/science/article/abs/pii/S0020025518301658>
13. *Trust management in VANET: a systematic review* (2015), EURASIP JWCN — <https://link.springer.com/article/10.1186/s13638-015-0353-y>
14. *Trust-Based Time Series Data Model for Mobile Crowdsensing* (2017), IEEE ICC — <https://zhengzhenzhe220.github.io/papers/icc17.pdf>

**VGI quality and trust**
15. Goodchild (2007), GeoJournal 69(4):211–221
16. Goodchild, Li (2012), Spatial Statistics 1:110–120 — <https://people.geog.ucsb.edu/~good/275/vgiquality.pdf>
17. Haklay (2010), Env. & Planning B 37(4):682–703 — <https://journals.sagepub.com/doi/10.1068/b35097>
18. Keßler, de Groot (2013), AGILE — <https://link.springer.com/chapter/10.1007/978-3-319-00615-4_2>
19. Barron, Neis, Zipf (2014), Transactions in GIS — <https://onlinelibrary.wiley.com/doi/abs/10.1111/tgis.12073>
20. *Data trustworthiness and user reputation as indicators of VGI quality* (2018), Geo-spatial Information Science — <https://www.tandfonline.com/doi/pdf/10.1080/10095020.2018.1496556>

**Truth discovery / fusion**
21. Yin, Han, Yu (2008), IEEE TKDE 20(6); KDD'07 — <http://hanj.cs.illinois.edu/pdf/kdd07_xyin.pdf>
22. Li Q. et al. (2014), ACM SIGMOD (CRH) — <https://dl.acm.org/doi/10.1145/2588555.2610509>
23. Wang, Kaplan, Le, Abdelzaher (2012), ACM/IEEE IPSN — <https://dl.acm.org/doi/abs/10.1145/2185677.2185737>
24. Ouyang, Srivastava, Toniolo, Norman (2016), IEEE TKDE 28(4):1047–1060 — <https://ieeexplore.ieee.org/document/7345583/>
25. Li Y. et al. (2016), ACM SIGKDD Explorations — <https://dl.acm.org/doi/10.1145/2897350.2897352>

**Persistence / survival / state estimation**
26. Rosen, Mason, Leonard (2016), IEEE ICRA — <https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/44821.pdf>
27. Rapp et al. (2016), FUSION — <https://ieeexplore.ieee.org/document/7528099>
28. Meyer-Delius, Beinhofer, Burgard (2012), AAAI — <https://dl.acm.org/doi/10.5555/2900929.2901014>
29. Nam, Mannering (2000), Transportation Research Part A 34(2):85–102 — <https://ideas.repec.org/a/eee/transa/v34y2000i2p85-102.html>
30. Hojati, Ferreira, Washington, Charles (2013), Accident Analysis & Prevention — <https://www.sciencedirect.com/science/article/abs/pii/S0001457512004599>
31. *Grouped random parameters hazard-based duration model with time-varying covariates* (2023), Analytic Methods in Accident Research — <https://www.sciencedirect.com/science/article/abs/pii/S2213665723000027>

**Uncertainty communication / human factors**
32. MacEachren et al. (2012), IEEE TVCG 18(12) — <https://geography.wisc.edu/cartography/projects/publications/MacEachrenEtAl_2012_TVCG.pdf>
33. Padilla, Kay, Hullman (2021), Wiley StatsRef — <http://space.ucmerced.edu/Downloads/publications/Uncertainty_Visualization_Padilla_Kay_Hullman_2022.pdf>
34. Padilla, Powell, Kay, Hullman (2021), Frontiers in Psychology 11:579267 — <https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2020.579267/full>
35. Joslyn, Savelli (2010), Meteorological Applications 17(2) — DOI `10.1002/met.190`
36. Lee, See (2004), Human Factors 46(1):50–80
37. Parasuraman, Riley (1997), Human Factors 39(2):230–253
38. Johnson, Shea, Holloway, *The Role of Trust and Interaction in GPS Related Accidents* — <https://www.dcs.gla.ac.uk/~johnson/papers/GPS/Johnson_Shea_Holloway_GPS.pdf>

**XAI / explanation evaluation / calibration**
39. Miller (2019), Artificial Intelligence 267:1–38 — <https://arxiv.org/abs/1706.07269>
40. Koo, Kwac, Ju, Steinert, Leifer, Nass (2015), IJIDeM 9(4):269–275 — <https://link.springer.com/article/10.1007/s12008-014-0227-2>
41. Hoffman, Mueller, Klein, Litman (2018), arXiv:1812.04608; (2023) Frontiers in Computer Science 5:1096257 — <https://arxiv.org/abs/1812.04608>
42. Jacovi, Goldberg (2020), ACL — <https://aclanthology.org/2020.acl-main.386/>
43. Turpin, Michael, Perez, Bowman (2023), NeurIPS — <https://arxiv.org/abs/2305.04388>
44. Doshi-Velez, Kim (2017), arXiv:1702.08608
45. Guo, Pleiss, Sun, Weinberger (2017), ICML, PMLR 70:1321–1330 — <https://arxiv.org/abs/1706.04599>
46. Brier (1950), Monthly Weather Review 78(1):1–3
47. Murphy (1973), J. Applied Meteorology 12(4):595–600 — <https://journals.ametsoc.org/view/journals/apme/12/4/1520-0450_1973_012_0595_anvpot_2_0_co_2.xml>

**Closest competing systems (novelty check)**
48. Alizadeh, Li, Hillin, Meyer, Thompson, Zhang, Behzadan (2022), Advanced Engineering Informatics — <https://repository.library.noaa.gov/view/noaa/57328/noaa_57328_DS1.pdf>
49. openrouteservice / HeiGIT disaster routing — <https://heigit.org/routenplanung-im-uberflutungsgebiet-openrouteservice-nutzt-copernicus-ems-flut-daten-in-spezieller-losung-2/>
50. *Constraint-Aware Route Recommendation from Natural Language via Hierarchical LLM Agents* (2025), arXiv:2510.06078 — <https://arxiv.org/html/2510.06078>

*Items 6, 10, 15, 36, 37, 44, 46 are canonical references cited without a live URL check this
session; verify page numbers against the publisher before submission. Item 27's full author
list is unconfirmed (dblp key `conf/fusion/RappDHDD16`).*
