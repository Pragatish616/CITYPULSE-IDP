# Improvement Register

Ideas that go beyond the pitch, ranked by payoff against effort. Each states what it buys the
*paper*, not just the product — this is credited research, and an improvement that makes the
demo prettier but produces no measurement is a distraction.

Status: all `proposed`. Promote to an ADR before implementing.

---

## Tier 1 — High payoff, low effort. Do these.

### I-01 — Demo starts with the network switched off
**Effort:** none. **Payoff:** large.
Every competitor demo assumes connectivity. Open in aeroplane mode, route, explain, *then*
reconnect and show the sync. The single most persuasive thirty seconds available, and it costs
nothing because it is the actual feature. Rehearse it; do not improvise it.

### I-02 — Every traversal is a negative observation
**Effort:** small (the schema already supports `polarity: −1`). **Payoff:** large, and it is a
genuine contribution.
When a user drives through an edge and reports nothing, that is calibrated evidence of
*absence* — `P(no report | hazard present) = P_M^n` over `n` traversals. It turns the app's own
users into the sensor network, which directly attacks the project's biggest data gap (no live
street-level inundation exists for Chennai; see `research/raw/C`). Strand D identifies this
"silence channel" as one of the few defensibly novel elements. It also makes the confidence
model *recover* after a flood clears, which a report-only model cannot do without someone
explicitly reporting "it's fine now" — which nobody ever does.
**Watch for:** survivorship bias. People do not drive into flooded roads, so absence of
traversal is not absence of hazard. Model traversal as missing-not-at-random and say so.

### I-03 — Rejection sampling on the verifier as a training signal
**Effort:** small. **Payoff:** large, and publishable.
The verifier (T4.2) already labels every SLM output pass/fail. Collect the passing generations
and LoRA-fine-tune the 270M model on them. This is free supervision, it directly raises the
headline metric, and "the verifier is both the evaluation and the training signal" is a clean
story for a workshop paper. Report pass rate before and after as an ablation.

### I-04 — Ship the replay harness as a public benchmark
**Effort:** small (it exists by T3.2 anyway). **Payoff:** disproportionate.
Package the Chennai corpus + replay engine + the C0–C4 baselines as a reproducible benchmark
with a fixed seed. Benchmarks get cited more than systems, they make the work reusable by the
next team, and reviewers at applications venues reward them. Name it and give it a DOI via
Zenodo.

### I-05 — "We don't know" as a first-class UI state
**Effort:** small (`data_gaps` is already in the trace). **Payoff:** it is the project's thesis.
The pitch criticises maps that give a route without a reason. The sharper criticism is maps
that present *ignorance* as safety. Render a corridor with no recent observations visibly
differently from one observed and found clear. No competitor does this, and it is exactly what
the confidence model makes possible.

---

## Tier 2 — High payoff, real effort. Pick one or two.

### I-06 — Tamil explanations
**Effort:** medium. **Payoff:** large at an ICT4D or COMPASS venue.
TN-ALERT ships in Tamil; an English-only civic safety tool for Chennai is a weak equity story.
Tamil is also a genuinely harder NLG test: small quantized models are poor at it, which makes
the Tier-0-template-first architecture pay off visibly, and gives a clean cross-lingual
verification-rate comparison. **This converts a weakness of small models into a result.**

### I-07 — Pedestrian hazard mode
**Effort:** medium. **Payoff:** high, and under-served in the literature.
Pregnolato's depth–disruption function is for *vehicles*. A pedestrian is impeded at far
shallower depths, and in Chennai during the monsoon most at-risk people are on foot or on
two-wheelers. A separate pedestrian depth threshold and severity curve is a small modelling
change with a strong equity argument and very little prior art. It also gives a second
`user_class` for the `z` sweep at almost no cost.

### I-08 — Fleet traces as a flood sensor
**Effort:** medium, contingent on data access. **Payoff:** high if it lands.
If MTC bus GPS or any fleet feed is obtainable, a cluster of vehicles slowing or stopping
where they normally do not is a strong inundation signal at street resolution — the exact
signal no purchasable source provides. Treat as a Tier 2 data application (low probability,
high value). Even a negative result ("we sought street-resolution signal and this is why none
exists") is worth a paragraph in Limitations.

### I-09 — Randomise the confidence display and measure reliance
**Effort:** medium (it rides on Study 5). **Payoff:** turns a UI choice into a finding.
Show numeric confidence to one arm, a three-band badge to another, and nothing to a control.
Measure *appropriate reliance*, not satisfaction. Uncertainty visualisation has a real
literature (`research/raw/D`) and almost no navigation-specific evidence — this is a
publishable sub-result that costs one extra condition.

---

## Tier 3 — Opportunistic. Watch for them.

### I-10 — The northeast monsoon lands inside the project window
Chennai's northeast monsoon runs roughly October–December. A seven-week build starting
mid-September puts weeks 5–7 near its onset. **If a real flooding event occurs, capture
everything** — raw feeds, app traces, timestamps — and write it up as a case study. A single
real event validated against a real system is worth more to reviewers than any amount of
replay. Have the capture scripts running from week 5 so you are not scrambling on the day.

### I-11 — Confidence-aware λ slider, explained
Exposing `z` as "how cautious should I be?" with the consequence stated in plain language
("2 minutes slower, avoids 3 uncertain reports") makes the pessimism legible rather than
paternalistic, and gives the human study a natural interaction to observe.

### I-12 — Precompute a flood-proneness rank per edge and ship it
Falls out of the static prior `ℓ₀` (T1.3) for free. It means the offline mode gives useful
answers on a corridor with *zero* observations, which is the difference between a system that
reasons offline and one that replays a cache. Worth calling out explicitly in the paper —
it is what distinguishes this from "we cached some routes".

---

## Explicitly rejected

- **Federated learning / differential privacy.** Not realistic in 7 weeks
  (`research/raw/F`), and ADR-006 removed the passive inference that would have needed it.
- **Contraction hierarchies.** Chennai is ~10⁵ nodes. Complexity theatre.
- **A larger on-device model.** 1.5 GB+ models get OOM-killed when backgrounded mid-drive,
  which is precisely when the app must survive (`research/raw/B`).
- **Age-of-Information framing.** No scheduling problem exists here; reviewers will notice
  (`research/raw/D`).
