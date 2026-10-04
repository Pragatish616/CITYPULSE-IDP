import 'package:pulse_belief/pulse_belief.dart';

import 'package:pulse_router/src/bidirectional_dijkstra.dart';
import 'package:pulse_router/src/csr_graph.dart';
import 'package:pulse_router/src/decision_trace.dart';
import 'package:pulse_router/src/edge_cost.dart' as cost;

/// Per-edge hazard configuration needed to cost and explain one edge —
/// everything `edgeCost` and `fuse` need that isn't the observations
/// themselves. Normally resolved from `config/hazard_classes.yaml` plus the
/// static prior `ℓ₀(e)` (T1.3).
///
/// **This type is new with T2.4, not specified by `docs/CONTRACTS.md`.**
/// The contract defines the wire schemas (`HazardObservation`,
/// `EdgeBelief`, `DecisionTrace`) but not this in-memory composition
/// structure — it exists purely to let [planRoute] call `pulse_belief` and
/// `pulse_router` together. `depthMm` is carried here, separately from
/// [WeightedObservation], because `pulse_belief` deliberately does not
/// model depth (`docs/CONTRACTS.md` §1: only flooding carries `depth_mm`,
/// and it is a point reading, not something Bayesian fusion applies to) —
/// this is the caller's job, and this is the caller.
class EdgeHazardConfig {
  /// Creates one edge's hazard configuration.
  const EdgeHazardConfig({
    required this.hazardClass,
    required this.priorLogOdds,
    required this.decayTauSeconds,
    required this.severity,
    required this.hMaxMm,
    required this.epsilon,
    this.depthMm,
    this.staleAfterSeconds,
  });

  /// The hazard class this edge is fused under (e.g. `"flood"`).
  final String hazardClass;

  /// `ℓ₀(e)` — the static terrain prior for this edge and class (T1.3).
  final double priorLogOdds;

  /// `T_c` for this hazard class (`config/hazard_classes.yaml`).
  final double decayTauSeconds;

  /// `s` — severity for this hazard class (`config/hazard_classes.yaml`).
  final double severity;

  /// `h_max` — the chance-constraint depth threshold (`config/hazard_classes.yaml`).
  final double hMaxMm;

  /// `ε` — the chance-constraint probability threshold.
  final double epsilon;

  /// The current standing-water depth reading for this edge, if any. Not
  /// fused across observations — the newest reading, resolved by the
  /// caller before calling [planRoute].
  final double? depthMm;

  /// Overrides `classifyConfidence`'s default staleness cutoff
  /// (`2 * decayTauSeconds`) for this edge, if set.
  final double? staleAfterSeconds;
}

/// A per-edge value computed on first use and cached. Indexing an edge with no
/// hazard configuration yields `null`, matching the `Map` it replaces.
class _LazyByEdge<V> {
  _LazyByEdge(this._has, this._compute);

  final bool Function(int edgeId) _has;
  final V Function(int edgeId) _compute;
  final Map<int, V> _cache = {};

  V? operator [](int edgeId) {
    if (!_has(edgeId)) return null;
    return _cache.putIfAbsent(edgeId, () => _compute(edgeId));
  }
}

RouteEdge _findEdge(CsrGraph graph, int from, int edgeId) {
  for (var i = 0; i < graph.outDegree(from); i++) {
    final edge = graph.outEdge(from, i);
    if (edge.edgeId == edgeId) return edge;
  }
  throw ArgumentError('edge $edgeId not found leaving node $from');
}

double _lengthMetres(RouteEdge edge) =>
    edge.freeFlowSeconds * edge.freeFlowKmh * 1000 / 3600;

List<RouteEdge> _pathEdges(CsrGraph graph, RouteResult route) => [
  for (var i = 0; i < route.edgePath.length; i++)
    _findEdge(graph, route.nodePath[i], route.edgePath[i]),
];

/// Plans one query end to end: fuses observations into per-edge belief
/// (`pulse_belief`), costs the graph under ADR-002/ADR-003, searches for the
/// safest route and a free-flow-only alternative, and assembles a
/// `DecisionTrace` (`docs/CONTRACTS.md` §3) — the composition
/// `decision_trace.dart` deliberately leaves to the caller. This is that
/// caller: the Dart AOT CLI (T2.4) and, eventually, the Flutter client both
/// call this same function, per ADR-001.
///
/// [hazardConfigByEdge] and [observationsByEdge] are keyed by `edge_id`.
/// An edge with no entry in [hazardConfigByEdge] is treated as having no
/// hazard evidence at all (contributes free-flow cost only, and becomes a
/// `data_gaps` entry if it lies on the chosen route) — never as "safe."
///
/// [sourceClassByObservationId] maps each observation's id
/// (`WeightedObservation.id`) to its original `source_class`
/// (`docs/CONTRACTS.md` §1) — `pulse_belief`'s `WeightedObservation`
/// deliberately drops that field (it only needs the resolved reliability
/// number, `α_c`), so a `blocking_edges[].source_class` has to be recovered
/// from here rather than guessed.
///
/// Returns `null` if [target] is unreachable from [source] even ignoring
/// all hazard cost (i.e. the graph itself is disconnected between them).
PlannedRoute? planRouteDetailed({
  required CsrGraph graph,
  required int source,
  required int target,
  required DateTime computedAt,
  required String userClass,
  required double z,
  required double lambda,
  required Map<int, EdgeHazardConfig> hazardConfigByEdge,
  required Map<int, List<WeightedObservation>> observationsByEdge,
  required Map<String, String> sourceClassByObservationId,
  required String queryId,
  String Function(int edgeId)? edgeLabel,
  String mode = 'offline',
  BeliefParams? beliefParams,
}) {
  if (source < 0 ||
      source >= graph.nodeCount ||
      target < 0 ||
      target >= graph.nodeCount) {
    throw ArgumentError(
      'source ($source) and target ($target) must be node ids in '
      '[0, ${graph.nodeCount})',
    );
  }
  final label = edgeLabel ?? (id) => 'edge $id';

  // Belief and the pessimistic index are computed only for the edges the
  // search (or the explanation) actually touches, then cached. The router
  // used to fuse all ~14.5k hazard edges up front; on a phone most of those
  // are nowhere near the route. Behaviour is identical because both values
  // are pure functions of the edge's inputs.
  final beliefByEdge = _LazyByEdge<BetaBelief>(hazardConfigByEdge.containsKey, (
    edgeId,
  ) {
    final config = hazardConfigByEdge[edgeId]!;
    return fuseBeta(
      observations: observationsByEdge[edgeId] ?? const [],
      priorLogOdds: config.priorLogOdds,
      t: computedAt,
      decayTauSeconds: config.decayTauSeconds,
      params: beliefParams,
    );
  });
  final pessimisticByEdge = _LazyByEdge<double>(
    hazardConfigByEdge.containsKey,
    (edgeId) => pessimisticBeta(belief: beliefByEdge[edgeId]!, z: z),
  );

  double? hazardAwareCost(RouteEdge edge) {
    final config = hazardConfigByEdge[edge.edgeId];
    if (config == null) return edge.freeFlowSeconds;
    return cost
        .edgeCost(
          freeFlowSeconds: edge.freeFlowSeconds,
          freeFlowKmh: edge.freeFlowKmh,
          pPessimistic: pessimisticByEdge[edge.edgeId]!,
          depthMm: config.depthMm,
          severity: config.severity,
          lambda: lambda,
          hMaxMm: config.hMaxMm,
          epsilon: config.epsilon,
        )
        .costSeconds;
  }

  double? freeFlowOnlyCost(RouteEdge edge) => edge.freeFlowSeconds;

  final chosenResult = bidirectionalDijkstra(
    graph: graph,
    source: source,
    target: target,
    edgeCost: hazardAwareCost,
  );
  if (chosenResult == null) return null;

  final altResult = bidirectionalDijkstra(
    graph: graph,
    source: source,
    target: target,
    edgeCost: freeFlowOnlyCost,
  )!; // never null: hazardAwareCost never removes more than freeFlowOnlyCost

  final chosenEdges = _pathEdges(graph, chosenResult);
  final freeFlowDurationSeconds = chosenEdges.fold(
    // fold's accumulator type is inferred from this seed, and the closure
    // below returns double; an int seed is a genuine type error, not lint
    // noise.
    // ignore: prefer_int_literals
    0.0,
    (sum, e) => sum + e.freeFlowSeconds,
  );
  final distanceMeters = chosenEdges.fold(
    // Same reason as freeFlowDurationSeconds above.
    // ignore: prefer_int_literals
    0.0,
    (sum, e) => sum + _lengthMetres(e),
  );
  final worstEdgeP = chosenEdges.fold(
    // Same reason again: an int seed would make fold's accumulator type
    // int, which the double-returning closure below cannot satisfy.
    // ignore: prefer_int_literals
    0.0,
    (best, e) => (pessimisticByEdge[e.edgeId] ?? 0) > best
        ? pessimisticByEdge[e.edgeId]!
        : best,
  );

  final chosen = ChosenRoute(
    routeId: 'A',
    durationSeconds: chosenResult.totalCostSeconds,
    distanceMeters: distanceMeters,
    freeFlowDurationSeconds: freeFlowDurationSeconds,
    worstEdgeP: worstEdgeP,
    geometryRef: 'nodes:${chosenResult.nodePath.join(",")}',
  );

  // An alternative's hazard edge may only be reported as "avoided" if the
  // chosen route does not use *that edge* (KNOWN_FLAWS F-04 item 2: the
  // template used to say "It avoids X" while the chosen route crossed X).
  // Membership is decided here, from the two paths, so no explanation layer
  // has to guess. It is deliberately edge-level, not street-name-level: a
  // detour usually goes round one segment of a long road, and the template
  // words the claim as "a stretch of X" so it stays true when the route
  // crosses X somewhere else.
  final chosenEdgeIds = {for (final e in chosenEdges) e.edgeId};
  bool avoidedByChosen(RouteEdge e) => !chosenEdgeIds.contains(e.edgeId);

  final alternatives = <AlternativeRoute>[];
  if (!_samePath(chosenResult, altResult)) {
    final altEdges = _pathEdges(graph, altResult);
    final removedEdges = <RouteEdge>[];
    for (final e in altEdges) {
      final config = hazardConfigByEdge[e.edgeId];
      if (config == null) continue;
      final result = cost.edgeCost(
        freeFlowSeconds: e.freeFlowSeconds,
        freeFlowKmh: e.freeFlowKmh,
        pPessimistic: pessimisticByEdge[e.edgeId]!,
        depthMm: config.depthMm,
        severity: config.severity,
        lambda: lambda,
        hMaxMm: config.hMaxMm,
        epsilon: config.epsilon,
      );
      if (result.removedByChanceConstraint) removedEdges.add(e);
    }

    final blockingEdges = <BlockingEdge>[];
    RejectedBecause rejectedBecause;
    if (removedEdges.isNotEmpty) {
      rejectedBecause = RejectedBecause.chanceConstraint;
      for (final e in removedEdges.where(avoidedByChosen)) {
        blockingEdges.add(
          _toBlockingEdge(
            edge: e,
            config: hazardConfigByEdge[e.edgeId]!,
            belief: beliefByEdge[e.edgeId]!,
            pPessimistic: pessimisticByEdge[e.edgeId]!,
            observations: observationsByEdge[e.edgeId] ?? const [],
            sourceClassByObservationId: sourceClassByObservationId,
            computedAt: computedAt,
            timePenaltySeconds: 0,
            removedByChanceConstraint: true,
            label: label,
          ),
        );
      }
    } else {
      rejectedBecause = RejectedBecause.higherCost;
      RouteEdge? worst;
      for (final e in altEdges) {
        if (hazardConfigByEdge[e.edgeId] == null) continue;
        if (!avoidedByChosen(e)) continue;
        if (worst == null ||
            pessimisticByEdge[e.edgeId]! > pessimisticByEdge[worst.edgeId]!) {
          worst = e;
        }
      }
      if (worst != null) {
        final config = hazardConfigByEdge[worst.edgeId]!;
        final penalty = hazardAwareCost(worst)! - worst.freeFlowSeconds;
        blockingEdges.add(
          _toBlockingEdge(
            edge: worst,
            config: config,
            belief: beliefByEdge[worst.edgeId]!,
            pPessimistic: pessimisticByEdge[worst.edgeId]!,
            observations: observationsByEdge[worst.edgeId] ?? const [],
            sourceClassByObservationId: sourceClassByObservationId,
            computedAt: computedAt,
            timePenaltySeconds: penalty,
            removedByChanceConstraint: false,
            label: label,
          ),
        );
      }
    }

    alternatives.add(
      AlternativeRoute(
        routeId: 'B',
        durationSeconds: altResult.totalCostSeconds,
        rejectedBecause: rejectedBecause,
        blockingEdges: blockingEdges,
      ),
    );
  }

  // A data gap is a stretch of the chosen route that the hazard map flags
  // (the edge carries a hazard prior) but where there is no recent report to
  // check it against. KNOWN_FLAWS F-08 / ADR-016: the previous rule was the
  // reverse -- it flagged every edge with *no* hazard entry (low prior,
  // nothing known) and never flagged a high-prior edge nobody had reported.
  // Edges with no hazard entry at all are not listed individually; the
  // route-level confidence band already says the data is thin.
  final dataGaps = <DataGap>[];
  final seenGapLabels = <String>{};
  for (final e in chosenEdges) {
    final config = hazardConfigByEdge[e.edgeId];
    if (config == null) continue;
    final belief = beliefByEdge[e.edgeId]!;
    final newest = belief.newestObservationAt;
    final staleAfter = config.staleAfterSeconds ?? 2 * config.decayTauSeconds;
    final hasRecentObservation =
        newest != null &&
        computedAt.difference(newest).inSeconds.toDouble() <= staleAfter;
    if (hasRecentObservation) continue;
    final corridor = label(e.edgeId);
    if (seenGapLabels.add(corridor)) {
      dataGaps.add(
        DataGap(corridor: corridor, reason: 'no_observations_in_window'),
      );
    }
  }

  final confidenceBand = _confidenceBandForRoute(
    chosenEdges,
    hazardConfigByEdge,
    beliefByEdge,
    computedAt,
  );

  final trace = DecisionTrace(
    queryId: queryId,
    computedAt: computedAt,
    mode: RoutingMode.values.firstWhere((m) => m.wireValue == mode),
    userClass: UserClass.values.firstWhere((c) => c.wireValue == userClass),
    z: z,
    lambda: lambda,
    chosen: chosen,
    alternatives: alternatives,
    contextFacts: const [],
    dataGaps: dataGaps,
    confidenceBand: confidenceBand,
  );
  return PlannedRoute(
    trace: trace,
    chosenNodes: List.unmodifiable(chosenResult.nodePath),
    fastestNodes: List.unmodifiable(altResult.nodePath),
  );
}

/// [planRouteDetailed]'s result: the `DecisionTrace` plus the two paths it
/// reasons about, as node ids, so a client can draw them.
class PlannedRoute {
  /// Creates a result.
  const PlannedRoute({
    required this.trace,
    required this.chosenNodes,
    required this.fastestNodes,
  });

  /// The decision trace (`docs/CONTRACTS.md` §3).
  final DecisionTrace trace;

  /// Nodes of the chosen (hazard-aware) route, source to target.
  final List<int> chosenNodes;

  /// Nodes of the fastest route ignoring hazard cost. Equal to
  /// [chosenNodes] when the hazard-aware search chose the fastest route.
  final List<int> fastestNodes;

  /// Whether the chosen route differs from the fastest one.
  bool get detours =>
      chosenNodes.length != fastestNodes.length ||
      Iterable<int>.generate(chosenNodes.length)
          .any((i) => chosenNodes[i] != fastestNodes[i]);
}

/// Plans one query end to end and returns the `DecisionTrace` -- see
/// [planRouteDetailed] for the version that also returns the paths.
DecisionTrace? planRoute({
  required CsrGraph graph,
  required int source,
  required int target,
  required DateTime computedAt,
  required String userClass,
  required double z,
  required double lambda,
  required Map<int, EdgeHazardConfig> hazardConfigByEdge,
  required Map<int, List<WeightedObservation>> observationsByEdge,
  required Map<String, String> sourceClassByObservationId,
  required String queryId,
  String Function(int edgeId)? edgeLabel,
  String mode = 'offline',
  BeliefParams? beliefParams,
}) => planRouteDetailed(
  graph: graph,
  source: source,
  target: target,
  computedAt: computedAt,
  userClass: userClass,
  z: z,
  lambda: lambda,
  hazardConfigByEdge: hazardConfigByEdge,
  observationsByEdge: observationsByEdge,
  sourceClassByObservationId: sourceClassByObservationId,
  queryId: queryId,
  edgeLabel: edgeLabel,
  mode: mode,
  beliefParams: beliefParams,
)?.trace;

bool _samePath(RouteResult a, RouteResult b) {
  if (a.edgePath.length != b.edgePath.length) return false;
  for (var i = 0; i < a.edgePath.length; i++) {
    if (a.edgePath[i] != b.edgePath[i]) return false;
  }
  return true;
}

BlockingEdge _toBlockingEdge({
  required RouteEdge edge,
  required EdgeHazardConfig config,
  required BetaBelief belief,
  required double pPessimistic,
  required List<WeightedObservation> observations,
  required Map<String, String> sourceClassByObservationId,
  required DateTime computedAt,
  required double timePenaltySeconds,
  required bool removedByChanceConstraint,
  required String Function(int) label,
}) {
  final ageSeconds = belief.newestObservationAt == null
      ? 0.0
      : computedAt.difference(belief.newestObservationAt!).inSeconds.toDouble();

  // The newest contributing observation's source_class, recovered by
  // matching observed_at back to the original list -- see planRoute's doc
  // comment on sourceClassByObservationId for why this indirection exists.
  var sourceClass = 'unknown';
  if (belief.newestObservationAt != null) {
    for (final obs in observations) {
      if (obs.observedAt == belief.newestObservationAt &&
          belief.contributingObservationIds.contains(obs.id)) {
        sourceClass = sourceClassByObservationId[obs.id] ?? 'unknown';
        break;
      }
    }
  }

  return BlockingEdge(
    edgeId: edge.edgeId,
    streetName: label(edge.edgeId),
    hazardClass: config.hazardClass,
    pMean: belief.pMean,
    pPessimistic: pPessimistic,
    nEff: belief.nEff,
    newestObservationAgeSeconds: ageSeconds,
    sourceClass: sourceClass,
    depthMm: config.depthMm,
    timePenaltySeconds: timePenaltySeconds,
    removedByChanceConstraint: removedByChanceConstraint,
    hasObservation: belief.newestObservationAt != null,
  );
}

ConfidenceBand _confidenceBandForRoute(
  List<RouteEdge> chosenEdges,
  Map<int, EdgeHazardConfig> hazardConfigByEdge,
  _LazyByEdge<BetaBelief> beliefByEdge,
  DateTime computedAt,
) {
  ConfidenceBand? worst;
  for (final e in chosenEdges) {
    final config = hazardConfigByEdge[e.edgeId];
    if (config == null) continue;
    final belief = beliefByEdge[e.edgeId]!;
    final ageSeconds = belief.newestObservationAt == null
        ? null
        : computedAt
              .difference(belief.newestObservationAt!)
              .inSeconds
              .toDouble();
    final band = classifyConfidence(
      nEff: belief.nEff,
      newestObservationAgeSeconds: ageSeconds,
      decayTauSeconds: config.decayTauSeconds,
      staleAfterSeconds: config.staleAfterSeconds,
    );
    worst = _worseBand(worst, band);
  }
  return worst ?? ConfidenceBand.low;
}

/// Aggregation policy for confidence across a route's edges (this task, not
/// yet in any ADR): report the single least-confident edge's band for the
/// whole route, never averaging it away — consistent with ADR-011's "no
/// single-color all-clear." Order, most to least concerning: `stale`,
/// `low`, `moderate`, `high`.
ConfidenceBand _worseBand(ConfidenceBand? a, ConfidenceBand b) {
  if (a == null) return b;
  const order = {
    ConfidenceBand.stale: 0,
    ConfidenceBand.low: 1,
    ConfidenceBand.moderate: 2,
    ConfidenceBand.high: 3,
  };
  return order[a]! <= order[b]! ? a : b;
}
