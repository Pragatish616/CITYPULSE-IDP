# Data Contracts

**These schemas are the interfaces between components. Agree them before writing code; change
them only by ADR.** Four separate components consume the decision trace — the template
renderer, the SLM rewriter, the verifier, and the evaluation harness — so an unstable trace
schema breaks everything downstream at once.

All timestamps are RFC 3339 UTC. All ids are UUIDv7 (time-ordered, client-generatable).

---

## 1. HazardObservation — the append-only unit

An observation is an **immutable claim that something was true at a place at a time**. It is
never edited or deleted; a later observation with opposite polarity supersedes it in the
belief calculation, not in storage. This is what makes the sync a G-Set CRDT (ADR-008).

```json
{
  "id": "0192f3c1-...-7a2b",
  "hazard_class": "flood | waterlogging | debris | accident | closure | heat | aqi",
  "polarity": 1,
  "geometry": { "type": "Point", "coordinates": [80.2707, 13.0827] },
  "accuracy_m": 12.0,
  "observed_at": "2026-09-12T05:14:22Z",
  "received_at": "2026-09-12T05:14:29Z",
  "source_class": "municipal_sensor | official_feed | verified_responder | crowd | app_traversal",
  "source_id": "cmwssb.reservoir.chembarambakkam",
  "intensity": { "depth_mm": 320 },
  "raw": { },
  "precision_state": "exact",
  "coarsened_at": null
}
```

**`precision_state` / `coarsened_at` (added 2026-09-12, review pass — ADR-010).** Every
observation starts `"exact"`. 30 days after `observed_at`, or immediately on a user erasure
request, a sweep rewrites the record in place: `geometry` is snapped to a ~150 m grid cell,
`source_id` is replaced with a non-reversible bucket id (for `source_class: crowd` /
`app_traversal` only), `precision_state` becomes `"coarsened"`, and `coarsened_at` is set. The
id, polarity, class, and `observed_at` never change — this is a mutation of an existing fact,
not a retraction, so it does not reopen the CRDT merge question ADR-008 closed.

- `polarity`: `+1` hazard present, `−1` hazard absent/cleared. **Negative observations are
  first-class** — a traversal with no report is evidence of absence (see improvement I-02).
- `source_class` maps to the reliability weight `α_c` in the belief model. Keep the mapping in
  one config file, not scattered in code.
- `observed_at` vs `received_at` are different and both matter: decay runs on `observed_at`,
  latency analysis on the difference.
- `intensity` is class-specific and optional. Only flooding currently carries `depth_mm`, which
  feeds the Pregnolato slowdown `δ`.

## 2. EdgeBelief — what the router reads

```json
{
  "edge_id": 184223,
  "hazard_class": "flood",
  "prior_logodds": -2.1,
  "posterior_logodds": 1.34,
  "p_mean": 0.792,
  "n_eff": 1.8,
  "p_pessimistic": 1.0,
  "z": 1.28,
  "newest_observation_at": "2026-09-12T05:14:22Z",
  "contributing_observations": ["0192f3c1-...", "0192f3c2-..."]
}
```

**Corrected 2026-09-12 (review pass):** with `p_mean = 0.792`, `n_eff = 1.8`, `z = 1.28`, the
formula (`docs/DECISIONS.md` ADR-002) gives `0.792 + 1.28·√(0.792·0.208/2.8) ≈ 1.102`, which
the `min{1, …}` clamp caps at exactly `1.0` — **not** the `0.931` this example previously
stated, which satisfied no variant of the formula. This is a genuinely useful example of the
clamp activating: a single fresh observation at this `z` saturates the pessimistic bound. If a
non-clamped illustrative value is wanted instead, use `n_eff ≈ 9.8` with the same `p̄`, `z`:
`0.792 + 1.28·√(0.164736/10.8) = 0.792 + 1.28·0.1235 = 0.950`. (**Corrected 2026-09-12,
second pass** — an earlier version of this note gave `n_eff ≈ 6.5` for the same target, which
actually computes to `≈0.982`, not `0.95`; caught by the skeptic review below. Anyone editing
this paragraph again: paste the arithmetic into a calculator, don't estimate it.)

`contributing_observations` is what makes an explanation auditable. Keep it, even though it
costs memory — the verifier and the human study both need it.

## 3. DecisionTrace — the single most important schema in the project

Emitted by `pulse_router` for every query. **The explanation layers may use nothing else.**
If a fact is not in this object, no explanation may state it.

```json
{
  "query_id": "0192f3d0-...",
  "computed_at": "2026-09-12T05:15:01Z",
  "mode": "offline | online_enriched",
  "user_class": "commuter | emergency | pedestrian | cyclist",
  "z": 1.28,
  "lambda": 0.6,
  "chosen": {
    "route_id": "A",
    "duration_s": 1147,
    "distance_m": 8420,
    "free_flow_duration_s": 1023,
    "hazard_time_penalty_s": 124,
    "worst_edge_p": 0.31,
    "geometry_ref": "polyline:..."
  },
  "alternatives": [
    {
      "route_id": "B",
      "duration_s": 907,
      "rejected_because": "chance_constraint | higher_cost",
      "blocking_edges": [
        {
          "edge_id": 184223,
          "street_name": "Kotturpuram Bridge approach",
          "hazard_class": "flood",
          "p_mean": 0.792,
          "p_pessimistic": 1.0,
          "n_eff": 1.8,
          "newest_observation_age_s": 179,
          "source_class": "crowd",
          "depth_mm": 320,
          "time_penalty_s": 0,
          "removed_by_chance_constraint": true
        }
      ]
    }
  ],
  "context_facts": [
    { "key": "reservoir_level_pct", "value": 94, "label": "Chembarambakkam", "as_of": "2026-09-12T04:00:00Z" }
  ],
  "data_gaps": [
    { "corridor": "Velachery Main Rd", "reason": "no_observations_in_window" }
  ],
  "confidence_band": "high | moderate | low | stale"
}
```

Notes that matter:

- **`data_gaps` is not optional.** Absence of hazard data is not the same as absence of hazard,
  and the UI must be able to say so. A system that silently presents ignorance as safety is the
  failure mode this project exists to criticise.
- **`has_observation` (added 2026-10-02, ADR-016)** is an optional boolean on a blocking edge, serialised only when
  `false`: the hazard map flags the edge but nobody has reported it, so `newest_observation_age_s` is `0` and
  meaningless and no text may say it was reported.
- `rejected_because` is what makes contrastive explanation possible ("why not B").
- `context_facts` is the only channel for extra colour (reservoir levels, rainfall). Anything
  the explanation mentions must be here or in `alternatives`.
- `free_flow_duration_s` lets the explanation say "2 minutes slower" truthfully — it is
  `chosen.free_flow_duration_s − alternatives[best].duration_s` (1023 − 907 s in the example), computed, never
  estimated by a model. **Corrected 2026-10-02 (ADR-016):** this line used to say
  `chosen.duration_s − alternatives[best].duration_s`, which subtracts a hazard-penalised cost from a driving
  time; `duration_s` is a cost, not a number of minutes.
- **Note on the `blocking_edges[0]` example (added 2026-09-12):** `depth_mm: 320` correctly
  exceeds flood's `h_max_mm: 300` (`config/hazard_classes.yaml`), which is why
  `removed_by_chance_constraint: true` — the edge was removed by the depth threshold directly,
  not by the cost function. `δ` (ADR-003) is never evaluated for a chance-constraint-removed
  edge, so this depth being past Pregnolato's ~300 mm validated domain does not matter here;
  it would matter if `δ` were ever computed for a removed edge for diagnostic display —
  don't do that without clamping first.

## 4. Explanation + VerificationResult

```json
{
  "query_id": "0192f3d0-...",
  "tier": 0,
  "text": "Route A is 2 minutes slower than Route B. It avoids a stretch of Kotturpuram Bridge approach where flooding was reported 3 minutes ago.",
  "locale": "en | ta",
  "facts_used": ["alternatives[0].blocking_edges[0]", "chosen.duration_s"],
  "verification": {
    "passed": true,
    "numerals_grounded": true,
    "entities_grounded": true,
    "contrastive_valid": true,
    "unsupported_claims": [],
    "fallback_used": false,
    "latency_ms": 0.6
  }
}
```

**Verifier rules (implement exactly these; they are the paper's headline metric):**
1. Every numeral in `text` must appear in the trace, within rounding tolerance declared per field.
2. Every proper noun must appear as a `street_name`, `label`, or `corridor` in the trace.
3. Any comparative claim ("slower", "avoids") must be supported by the corresponding field —
   if the text says route B was rejected for a hazard, B's `blocking_edges` must be non-empty.
4. No hedge-free assertion about an edge whose `confidence_band` is `low` or `stale`.
5. Failure ⇒ discard silently, emit Tier 0, set `fallback_used: true`. **Never show an
   unverified explanation, and never tell the user it failed** — log it, count it, report the
   rate in the paper.
6. **(Added 2026-09-12, review pass — ADR-011.) No unhedged affirmative-safety assertion.**
   Text may never state or imply a road, route, or edge is "safe," "clear," or "passable" in
   absolute terms — only comparative/confidence-qualified statements. Failure ⇒ same as rule 5.

**`unsupported_claims` tagging convention (added with T4.2, `packages/pulse_explain`).** The
worked example above predates rule 6 and only shows dedicated booleans for rules 1–3
(`numerals_grounded`, `entities_grounded`, `contrastive_valid`). Rules 4 and 6 have no
dedicated boolean — they surface only as entries in `unsupported_claims`, each prefixed
`rule<N>:` (e.g. `"rule4:unhedged_low_confidence"`, `"rule6:unhedged_safety_claim:is safe"`).
`passed` is `true` iff `unsupported_claims` is empty, regardless of which rule a tag names.
**Any component that parses `unsupported_claims` — including the evaluation harness that
computes rule 6's precision/recall for ADR-011's ≥95%-recall bar — must parse against this
prefix, not against the three named booleans alone**, or it will silently undercount rule 4/6
failures. T4.2's implementation additionally tags two coherence checks this way that are not
literally one of the numbered six but are folded into rule 3's "supported by the corresponding
field" spirit: `rule3:data_gap_contradiction:<corridor>` (a claim naming a `data_gaps` corridor
that also carries a numeral, an avoidance word, or a hazard noun — a `data_gaps` entry means no
observation exists there, so nothing else may be asserted about it) and the case where an
avoidance claim names a specific `route_id` whose own `blocking_edges` is empty, even if some
*other* alternative's is not.

## 5. Config that must live in one place

`config/hazard_classes.yaml` — per class: decay constant `T_c`, severity `s`, source
reliabilities `α_c`, chance-constraint threshold `h_max`, and the human-readable noun the
template renderer uses. Every study varies these; scattering them across code makes the
ablations impossible.
