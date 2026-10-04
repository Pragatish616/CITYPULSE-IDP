# pulse_router

Routing core (`docs/IMPLEMENTATION_PLAN.md` T2.1): CSR road graph, bidirectional Dijkstra, and
the ADR-003 hazard-aware edge cost function with chance-constraint edge removal.

- `CsrGraph` — CSR adjacency built once from a flat edge list, forward and backward (for
  bidirectional search) in one structure.
- `pregnolatoVSafeKmh` / `slowdownDelta` — the Pregnolato et al. (2017) depth-disruption
  function and `δ = max(1, v_free/v_safe(h))`. **The coefficient form is `[UNVERIFIED DETAIL]`**
  (`lib/src/depth_disruption.dart`) — from a secondary source, not yet checked against the
  paper PDF (`CLAUDE.md` §7's citation discipline). The `max(1, ...)` clamp is required: without
  it, an ordinary Chennai arterial (`v_free ≈ 30 km/h`) computes `δ < 1` at shallow depth,
  breaking the ALT-admissibility invariant `w_λ(e,t) ≥ τ₀(e,t)` (`docs/DECISIONS.md` ADR-003).
- `edgeCost` — `w_λ(e,t) = τ₀·[1 + p̃·(δ−1)] + λ·p̃·s·τ₀`, with the chance constraint
  `Pr[depth > h_max] ≤ ε` as edge removal, never a large finite weight. The chance-constraint
  check here (`pPessimistic` vs. `depthMm > hMaxMm`) is a modelling simplification pending a real
  depth distribution — see the doc comment in `lib/src/edge_cost.dart`.
- `bidirectionalDijkstra` — validated against hand-built toy graphs with known answers, plus a
  300-trial differential fuzz test against an independent reference Dijkstra
  (`test/bidirectional_dijkstra_test.dart`), which caught a real path-reconstruction aliasing
  bug (`list.setAll(0, list.reversed)` reads and writes the same backing list at once).
- `DecisionTrace` (T2.2, `lib/src/decision_trace.dart`) — the `docs/CONTRACTS.md` §3 schema and
  serialisation only; it assembles a trace from already-computed pieces (a chosen route, zero or
  more already-costed alternatives, already-fused blocking-edge facts) rather than deciding which
  alternatives to search for — that composition belongs to the caller (T2.4 or a future query
  orchestrator). Includes a real golden-file test (`test/decision_trace_test.dart` +
  `test/golden/sample_decision_trace.json`) that builds the trace object and asserts its
  `toJsonString()` output is byte-identical to the pinned fixture — not just a hand-copied
  example. Also fixes a genuine discrepancy in `docs/CONTRACTS.md` §3's prose about how
  `free_flow_duration_s` is derived (see the file's top-level doc comment).
- `classifyConfidence` — a simple, explicitly-provisional `confidence_band` policy (evidence mass,
  then staleness); `docs/CONTRACTS.md`/`docs/GLOSSARY.md` name the band values but specify no
  formula, so treat every threshold here as a placeholder pending T3.4 calibration.
- `AltLandmarks` / `selectFarthestPointLandmarks` / `aStarWithLandmarks` (T2.3,
  `lib/src/alt_landmarks.dart`) — ALT (A*, Landmarks, Triangle inequality) landmarks precomputed
  once on the free-flow metric. Verified empirically over a 10,000-trial randomised-hazard-config
  fuzz test (`test/alt_landmarks_test.dart`) that an ALT-guided search never returns a path
  costlier than plain `bidirectionalDijkstra` under the same cost function — the empirical half
  of the paper's ALT-admissibility claim (`CLAUDE.md` §6).

- `planRoute` (`lib/src/query_orchestrator.dart`) — the composition `decision_trace.dart`
  deliberately left to the caller: fuses observations into per-edge belief (`pulse_belief`),
  costs the graph (ADR-002/ADR-003), searches for the safest route and a free-flow-only
  alternative, and assembles the `DecisionTrace`. Not part of `docs/CONTRACTS.md` — a new,
  documented composition type (`EdgeHazardConfig`) exists purely to let this function call
  `pulse_belief` and `pulse_router` together. This is the one function the CLI and, eventually,
  the Flutter client both call, per ADR-001.
- **`bin/pulse_router.dart`** — the Dart AOT CLI (T2.4): `pulse_router route --graph <path>
  --observations <path> --source <id> --target <id> --at <iso8601> --user-class
  <commuter|emergency|pedestrian> --z <double> --lambda <double> [--query-id <id>] [--mode
  <offline|online_enriched>]`, emitting a `DecisionTrace` as JSON on stdout — how the Python
  evaluation harness calls the same router code the Flutter client will run. `--graph` and
  `--observations` take CLI-only JSON formats (`lib/src/cli_io.dart`'s doc comments give the
  exact shape) — not `docs/CONTRACTS.md` wire formats, since the real graph build (T1.3) ships a
  packed binary array, not JSON. Verified to both run under `dart run` and AOT-compile cleanly
  (`dart compile exe bin/pulse_router.dart`), with identical output either way.

Never fork the routing algorithm into a second language — the Flutter client and this CLI both
import this package directly (ADR-001).

## Input validation (2026-09 security review)

`edgeCost`, `pregnolatoVSafeKmh`, `slowdownDelta`, `classifyConfidence`, `ChosenRoute`, and both
search functions' `edgeCost` return value all validate with real, non-strippable checks (`throw
ArgumentError`), not `assert`. A review found several places where a `NaN` — reachable
transitively from a corrupted or adversarial hazard observation — silently satisfied the old
assert-based checks and then propagated in the *less* cautious direction: most seriously, the
chance-constraint safety gate in `edgeCost` failed **open** (kept a hazardous edge instead of
removing it) on a `NaN` `pPessimistic`/`depthMm`, and `classifyConfidence` fell through to
`ConfidenceBand.high` — the most reassuring value — on a `NaN` `nEff`. `bidirectionalDijkstra`
and `aStarWithLandmarks` also now reject a `NaN`/negative `edgeCost` outright, since the old
assert-only check let a `NaN` cost silently defeat the search's monotonic-improvement guard. See
the `regression for a 2026-09 security review finding` tests in `test/` for each case.
`GraphEdgeInput`/`CsrGraph.build` remain `assert`-only deliberately (documented in
`lib/src/csr_graph.dart`): unlike hazard observations, road-graph edges currently come only from
the controlled OSM pipeline (T1.3), not live untrusted input.

## Running the tests

```
dart pub get
dart test
```
