/// Shared test fixtures for `pulse_explain`'s test suite. Not part of the
/// published package surface.
library;

import 'package:pulse_router/pulse_router.dart';

/// `config/hazard_classes.yaml`'s `display_noun` column, transcribed for
/// tests. If the real file's wording changes, this only needs to track it
/// closely enough that the renderer's grammar tests still make sense —
/// production code never hardcodes this (`pulse_explain`'s top-level doc
/// comment; `docs/CONTRACTS.md` §5).
const Map<String, String> testHazardDisplayNouns = {
  'flood': 'flooding',
  'waterlogging': 'waterlogging',
  'debris': 'debris on the road',
  'accident': 'an accident',
  'closure': 'a road closure',
  'heat': 'extreme heat',
  'aqi': 'poor air quality',
};

/// Builds a `DecisionTrace` matching `docs/CONTRACTS.md` §3's worked
/// example by default (`chosen.duration_s: 1147`, one alternative at `907`,
/// one chance-constraint-removed blocking edge at `179` s old) — every
/// parameter overridable for the cases that need to differ from it.
DecisionTrace buildTrace({
  String chosenRouteId = 'A',
  double chosenDurationSeconds = 1147,
  double chosenDistanceMeters = 8420,
  double chosenFreeFlowDurationSeconds = 1023,
  double worstEdgeP = 0.31,
  List<AlternativeRoute> alternatives = const [
    AlternativeRoute(
      routeId: 'B',
      durationSeconds: 907,
      rejectedBecause: RejectedBecause.chanceConstraint,
      blockingEdges: [
        BlockingEdge(
          edgeId: 184223,
          streetName: 'Kotturpuram Bridge approach',
          hazardClass: 'flood',
          pMean: 0.792,
          pPessimistic: 1,
          nEff: 1.8,
          newestObservationAgeSeconds: 179,
          sourceClass: 'crowd',
          depthMm: 320,
          timePenaltySeconds: 0,
          removedByChanceConstraint: true,
        ),
      ],
    ),
  ],
  List<ContextFact> contextFacts = const [],
  List<DataGap> dataGaps = const [],
  ConfidenceBand confidenceBand = ConfidenceBand.moderate,
  String queryId = '0192f3d0-0000-7000-8000-000000000000',
  DateTime? computedAt,
  UserClass userClass = UserClass.commuter,
  double z = 0,
  double lambda = 0.3,
  RoutingMode mode = RoutingMode.offline,
}) => DecisionTrace(
  queryId: queryId,
  computedAt: computedAt ?? DateTime.utc(2026, 9, 12, 5, 15, 1),
  mode: mode,
  userClass: userClass,
  z: z,
  lambda: lambda,
  chosen: ChosenRoute(
    routeId: chosenRouteId,
    durationSeconds: chosenDurationSeconds,
    distanceMeters: chosenDistanceMeters,
    freeFlowDurationSeconds: chosenFreeFlowDurationSeconds,
    worstEdgeP: worstEdgeP,
    geometryRef: 'nodes:1,2,3',
  ),
  alternatives: alternatives,
  contextFacts: contextFacts,
  dataGaps: dataGaps,
  confidenceBand: confidenceBand,
);
