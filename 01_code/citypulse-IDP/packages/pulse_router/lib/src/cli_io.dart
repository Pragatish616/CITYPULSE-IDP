import 'package:pulse_belief/pulse_belief.dart';

import 'package:pulse_router/src/csr_graph.dart';
import 'package:pulse_router/src/query_orchestrator.dart';

/// Parses a graph JSON document into a [CsrGraph]. Expected shape:
/// ```json
/// {
///   "node_count": 3,
///   "edges": [
///     {"edge_id": 0, "from": 0, "to": 1,
///      "free_flow_seconds": 5, "free_flow_kmh": 40}
///   ]
/// }
/// ```
/// This is a CLI-only (T2.4) input format, not part of `docs/CONTRACTS.md` —
/// the real graph build (T1.3) ships a packed binary array to the Flutter
/// client, not this JSON. This format exists purely so the evaluation
/// harness (Python) can hand a graph to this CLI without a shared binary
/// format between the two languages.
CsrGraph graphFromJson(Map<String, Object?> json) {
  final nodeCount = json['node_count']! as int;
  final edgesJson = json['edges']! as List<Object?>;
  final edges = [
    for (final e in edgesJson.cast<Map<String, Object?>>())
      GraphEdgeInput(
        edgeId: e['edge_id']! as int,
        from: e['from']! as int,
        to: e['to']! as int,
        freeFlowSeconds: (e['free_flow_seconds']! as num).toDouble(),
        freeFlowKmh: (e['free_flow_kmh']! as num).toDouble(),
      ),
  ];
  return CsrGraph.build(nodeCount: nodeCount, edges: edges);
}

/// Parses a hazards JSON document into the three maps [planRoute] needs.
/// Expected shape:
/// ```json
/// {
///   "hazards": [
///     {
///       "edge_id": 0,
///       "hazard_class": "flood",
///       "prior_logodds": -2.0,
///       "decay_tau_seconds": 3600,
///       "severity": 1.0,
///       "h_max_mm": 300,
///       "epsilon": 0.1,
///       "depth_mm": 350,
///       "stale_after_seconds": null,
///       "observations": [
///         {
///           "id": "obs1",
///           "polarity": 1,
///           "distance_m": 0,
///           "observed_at": "2026-09-14T12:00:00Z",
///           "source_reliability": 0.9,
///           "source_class": "crowd"
///         }
///       ]
///     }
///   ]
/// }
/// ```
/// An edge with no hazard data at all is simply absent from `hazards` —
/// there is no need to list it with empty observations.
({
  Map<int, EdgeHazardConfig> hazardConfigByEdge,
  Map<int, List<WeightedObservation>> observationsByEdge,
  Map<String, String> sourceClassByObservationId,
})
hazardInputFromJson(Map<String, Object?> json) {
  final hazardConfigByEdge = <int, EdgeHazardConfig>{};
  final observationsByEdge = <int, List<WeightedObservation>>{};
  final sourceClassByObservationId = <String, String>{};

  final hazardsJson = (json['hazards'] as List<Object?>? ?? const [])
      .cast<Map<String, Object?>>();
  for (final hazard in hazardsJson) {
    final edgeId = hazard['edge_id']! as int;
    hazardConfigByEdge[edgeId] = EdgeHazardConfig(
      hazardClass: hazard['hazard_class']! as String,
      priorLogOdds: (hazard['prior_logodds']! as num).toDouble(),
      decayTauSeconds: (hazard['decay_tau_seconds']! as num).toDouble(),
      severity: (hazard['severity']! as num).toDouble(),
      hMaxMm: (hazard['h_max_mm']! as num).toDouble(),
      epsilon: (hazard['epsilon']! as num).toDouble(),
      depthMm: (hazard['depth_mm'] as num?)?.toDouble(),
      staleAfterSeconds: (hazard['stale_after_seconds'] as num?)?.toDouble(),
    );

    final observationsJson =
        (hazard['observations'] as List<Object?>? ?? const [])
            .cast<Map<String, Object?>>();
    final observations = <WeightedObservation>[];
    for (final obs in observationsJson) {
      final id = obs['id']! as String;
      observations.add(
        WeightedObservation(
          id: id,
          polarity: obs['polarity']! as int,
          distanceM: (obs['distance_m']! as num).toDouble(),
          observedAt: DateTime.parse(obs['observed_at']! as String),
          sourceReliability: (obs['source_reliability']! as num).toDouble(),
        ),
      );
      final sourceClass = obs['source_class'] as String?;
      if (sourceClass != null) sourceClassByObservationId[id] = sourceClass;
    }
    observationsByEdge[edgeId] = observations;
  }

  return (
    hazardConfigByEdge: hazardConfigByEdge,
    observationsByEdge: observationsByEdge,
    sourceClassByObservationId: sourceClassByObservationId,
  );
}
