/// CityPulse AI's routing core (`docs/IMPLEMENTATION_PLAN.md` T2.1): a CSR
/// road graph, bidirectional Dijkstra, and the ADR-003 hazard-aware edge cost
/// function with chance-constraint edge removal. `alt_landmarks.dart` (T2.3) is
/// exported but **not used by `planRoute`**, which runs plain bidirectional Dijkstra
/// (KNOWN_FLAWS F-11),
/// `DecisionTrace` emission (T2.2), and the query orchestrator that composes
/// this package with `pulse_belief` (consumed by the Dart AOT CLI, T2.4 —
/// `bin/pulse_router.dart`).
library;

export 'src/alt_landmarks.dart';
export 'src/bidirectional_dijkstra.dart';
export 'src/csr_graph.dart';
export 'src/decision_trace.dart';
export 'src/depth_disruption.dart';
export 'src/edge_cost.dart';
export 'src/city_config.dart';
export 'src/engine_config.dart';
export 'src/edge_snapper.dart';
export 'src/map_pack.dart';
export 'src/place_index.dart';
export 'src/query_orchestrator.dart';
export 'src/route_advisor.dart';
export 'src/routing_engine.dart';
export 'src/travel_profile.dart';
export 'src/path_simplify.dart';
