/// Hand-built [DecisionTrace] fixtures for widget tests -- deliberately not
/// loaded from the bundled demo assets, so these tests run fast and never
/// touch the ~46 MB graph asset. Every fixture is a structurally valid
/// trace (satisfies `ChosenRoute`'s ALT-admissibility check and
/// `VerificationResult`'s consistency checks via `renderTemplate`, which is
/// how [Explanation]s are produced here -- never hand-built, so a test can
/// never accidentally assert against an explanation that couldn't really
/// have been verified).
library;

import 'package:pulse_explain/pulse_explain.dart';
import 'package:pulse_router/pulse_router.dart';

const _hazardDisplayNouns = {'flood': 'flooding'};

DecisionTrace _traceWithBand(ConfidenceBand band) => DecisionTrace(
  queryId: 'test-query',
  computedAt: DateTime.utc(2026, 9, 17, 6),
  mode: RoutingMode.offline,
  userClass: UserClass.commuter,
  z: 0,
  lambda: 0.3,
  chosen: ChosenRoute(
    routeId: 'A',
    durationSeconds: 1200,
    distanceMeters: 5000,
    freeFlowDurationSeconds: 1000,
    worstEdgeP: 0.3,
    geometryRef: 'nodes:1,2,3',
  ),
  alternatives: [
    const AlternativeRoute(
      routeId: 'B',
      durationSeconds: 1000,
      rejectedBecause: RejectedBecause.chanceConstraint,
      blockingEdges: [
        BlockingEdge(
          edgeId: 99,
          streetName: 'Test Canal Bridge',
          hazardClass: 'flood',
          pMean: 0.8,
          pPessimistic: 1,
          nEff: 0.5,
          newestObservationAgeSeconds: 300,
          sourceClass: 'crowd',
          depthMm: 350,
          timePenaltySeconds: 0,
          removedByChanceConstraint: true,
        ),
      ],
    ),
  ],
  contextFacts: const [],
  dataGaps: const [
    DataGap(corridor: 'Test Main Road', reason: 'no_observations_in_window'),
  ],
  confidenceBand: band,
);

/// One (trace, explanation) pair per confidence band, for widget tests that
/// need to exercise all four.
final Map<ConfidenceBand, ({DecisionTrace trace, Explanation explanation})>
fixturesByBand = {
  for (final band in ConfidenceBand.values)
    band: (
      trace: _traceWithBand(band),
      explanation: renderTemplate(
        trace: _traceWithBand(band),
        hazardDisplayNouns: _hazardDisplayNouns,
      ),
    ),
};
