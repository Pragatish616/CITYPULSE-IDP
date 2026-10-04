# Evaluation Protocol

Five studies. These are the paper. Build the system so these are cheap to run.
Detail and citations: `research/raw/E-prior-art-evaluation.md`, `research/raw/D-confidence-xai.md`.

---

## Study 1 — Historical incident replay (the core result)

**Corpus.** ≥200 geolocated Chennai hazard events (OpenCity 2015 stagnation data, GCC
inundation depth points, crowd-sourced flooding records), replayed with real timestamps
through a deterministic harness. 1 000 origin–destination pairs sampled across the metro.

**Configurations.**
- C0 — shortest time, hazard-blind (baseline)
- C1 — hard hazard avoidance (naive, no confidence)
- C2 — hand-tuned single exponential decay
- C3 — per-hazard-class calibrated decay + pessimistic plug-in (ours)
- C4 — fixed TTL (the Waze-style baseline)
- C∞ — oracle with perfect hindsight hazard knowledge (upper bound)

**Metrics.** Impassable-edge-hit rate · detour ratio distribution (not just the mean) ·
exposure-reduction efficiency (risk avoided per extra second travelled) · false-avoidance
cost (detours taken for hazards that were not there).

**Present as a swept Pareto frontier** of safety violations against unnecessary detours, with
`λ` and `z` swept. A single operating point invites "you tuned it".

---

## Study 2 — Confidence calibration (the second core result)

The claim is that our confidence *means* something. Prove it.

**Metrics.** Brier score with Murphy's reliability/resolution decomposition · **reliability
diagrams stratified by report-age bucket and hazard class** · adaptive ECE · log loss · AUROC
reported separately from calibration.

**Mandatory baselines.** Fixed TTL · hand-tuned exponential · Jøsang & Ismail (2002) Beta
reputation with forgetting.

**Splitting.** Split by **event and monsoon episode, never randomly.** Reports from one flood
are correlated; a random split leaks and will inflate every number.

---

## Study 3 — Explanation faithfulness (the headline number)

**Automatic.** Claim-level checking of every generated explanation against the router's
decision trace: grounding rate, unsupported-claim rate, counterfactual consistency, and a
**contrastive-validity gate** — any route the explanation claims to reject must actually carry
the cost difference the explanation asserts.

**Scale.** 300 routes × {cloud LLM, on-device SLM, Tier 0 template}. Human agreement (Cohen's κ)
on a subsample to validate the automatic checker.

**Report the verification pass rate.** This is the number the paper is built around.

---

## Study 4 — Offline degradation and latency

**Connectivity ladder** shaped with `netem`: full connectivity → high latency → lossy →
captive portal → fully offline. At each rung: route quality delta, explanation tier reached,
and end-to-end latency.

**Hardware.** A **₹10–15k Android**, not a flagship. State the exact device and chipset in the
paper. Report time-to-first-token, decode rate, peak RSS, battery delta per 25 generations,
and thermal behaviour over a sustained run.

**Also report:** app storage footprint with and without the model (the affordability argument).

---

## Study 5 — Human study (n ≈ 40, within-subjects)

**Instruments.** Jian et al. trust-in-automation scale · SUS · comprehension items.

**The design that matters — manipulated ground truth.** Include trials where the system's
hazard belief is *wrong*, and measure **appropriate reliance**: agreement-when-right minus
agreement-when-wrong. Uniformly raised trust is an automation-bias failure, not a win, and a
paper that reports only "users trusted it more" will be read as naive.

**Ethics.** IEC/ICMR application must start in **week 1**. It is on the critical path.

---

## Simulation (optional, only if time allows)

One SUMO corridor: 3 hazard severities × 3 penetration rates × 10 seeds. Skip MATSim and
CityFlow — the setup cost is not repaid at this scale.

---

## Reproducibility rules

- Every study is a seeded script in `scripts/`, writing to `data/results/<date>-<study>/`.
- Data snapshots pinned by date; an OSM extract change mid-evaluation invalidates prior runs.
- The evaluation harness calls the **same** AOT-compiled router the app uses. A second
  implementation would invalidate the whole comparison.
