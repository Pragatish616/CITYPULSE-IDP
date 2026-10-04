import 'dart:io';

import 'package:pulse_router/src/decision_trace.dart';
import 'package:test/test.dart';

DecisionTrace _sampleTrace() => DecisionTrace(
  queryId: '0192f3d0-0000-7000-8000-000000000000',
  computedAt: DateTime.utc(2026, 9, 12, 5, 15, 1),
  mode: RoutingMode.offline,
  userClass: UserClass.pedestrian,
  z: 1.28,
  lambda: 0.6,
  chosen: ChosenRoute(
    routeId: 'A',
    durationSeconds: 1147,
    distanceMeters: 8420,
    freeFlowDurationSeconds: 1023,
    worstEdgeP: 0.31,
    geometryRef: 'polyline:fixed_test_geometry',
  ),
  alternatives: [
    const AlternativeRoute(
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
  contextFacts: [
    ContextFact(
      key: 'reservoir_level_pct',
      value: 94,
      label: 'Chembarambakkam',
      asOf: DateTime.utc(2026, 9, 12, 4),
    ),
  ],
  dataGaps: const [
    DataGap(corridor: 'Velachery Main Rd', reason: 'no_observations_in_window'),
  ],
  confidenceBand: ConfidenceBand.low,
);

void main() {
  group('DecisionTrace golden file', () {
    test('a fixed graph-derived trace (fixed clock, fixed inputs) serialises '
        'byte-identical to the pinned golden file -- T2.2 acceptance '
        'criterion (docs/IMPLEMENTATION_PLAN.md)', () {
      final golden = File('test/golden/sample_decision_trace.json')
          .readAsStringSync();
      // Normalise line endings only -- this repo has mixed
      // core.autocrlf behaviour on Windows checkouts, and the point of
      // this test is byte-identical *content*, not literally identical
      // CR/LF bytes on disk.
      final actual = _sampleTrace().toJsonString().replaceAll('\r\n', '\n');
      final expected = golden.replaceAll('\r\n', '\n').trimRight();
      expect(actual, equals(expected));
    });

    test(
      'is deterministic: two builds of the same inputs produce identical bytes',
      () {
        expect(
          _sampleTrace().toJsonString(),
          equals(_sampleTrace().toJsonString()),
        );
      },
    );
  });

  group('BlockingEdge.toJson', () {
    test('emits every CONTRACTS.md field with the right key names', () {
      final json = const BlockingEdge(
        edgeId: 1,
        streetName: 'Test St',
        hazardClass: 'flood',
        pMean: 0.5,
        pPessimistic: 0.7,
        nEff: 2,
        newestObservationAgeSeconds: 100,
        sourceClass: 'crowd',
        depthMm: 50,
        timePenaltySeconds: 12,
        removedByChanceConstraint: false,
      ).toJson();
      expect(json, {
        'edge_id': 1,
        'street_name': 'Test St',
        'hazard_class': 'flood',
        'p_mean': 0.5,
        'p_pessimistic': 0.7,
        'n_eff': 2.0,
        'newest_observation_age_s': 100,
        'source_class': 'crowd',
        'depth_mm': 50.0,
        'time_penalty_s': 12,
        'removed_by_chance_constraint': false,
      });
    });

    test('a null depth_mm (no depth observation for this hazard class) '
        'survives as JSON null', () {
      final json = const BlockingEdge(
        edgeId: 1,
        streetName: 'Test St',
        hazardClass: 'debris',
        pMean: 0.3,
        pPessimistic: 0.4,
        nEff: 1,
        newestObservationAgeSeconds: 60,
        sourceClass: 'crowd',
        depthMm: null,
        timePenaltySeconds: 5,
        removedByChanceConstraint: false,
      ).toJson();
      expect(json['depth_mm'], isNull);
    });

    test('removed_by_chance_constraint edges round-trip time_penalty_s as 0, '
        'never a computed delta (docs/CONTRACTS.md §3 note)', () {
      final json = const BlockingEdge(
        edgeId: 2,
        streetName: 'Flooded Rd',
        hazardClass: 'flood',
        pMean: 0.9,
        pPessimistic: 1,
        nEff: 3,
        newestObservationAgeSeconds: 30,
        sourceClass: 'municipal_sensor',
        depthMm: 500,
        timePenaltySeconds: 0,
        removedByChanceConstraint: true,
      ).toJson();
      expect(json['time_penalty_s'], equals(0));
      expect(json['removed_by_chance_constraint'], isTrue);
    });
  });

  group('ChosenRoute', () {
    test('hazardTimePenaltySeconds is duration minus free-flow duration', () {
      final route = ChosenRoute(
        routeId: 'A',
        durationSeconds: 1147,
        distanceMeters: 8420,
        freeFlowDurationSeconds: 1023,
        worstEdgeP: 0.31,
        geometryRef: 'polyline:x',
      );
      expect(route.hazardTimePenaltySeconds, equals(124));
      expect(route.toJson()['hazard_time_penalty_s'], equals(124));
    });

    test('a zero hazard penalty (duration == free-flow) is allowed', () {
      final route = ChosenRoute(
        routeId: 'A',
        durationSeconds: 500,
        distanceMeters: 1000,
        freeFlowDurationSeconds: 500,
        worstEdgeP: 0,
        geometryRef: 'polyline:x',
      );
      expect(route.hazardTimePenaltySeconds, equals(0));
    });

    test(
      'accepts a duration a few ULPs below free-flow duration -- floating '
      'point summation-order noise, not a real admissibility violation '
      '(regression: running the real ~471k-edge Chennai graph, T1.3, '
      'produced durationSeconds=2170.457 < '
      'freeFlowDurationSeconds=2170.4570000000003 with zero hazard cost, '
      'where both are sums of the same edge weights in different orders)',
      () {
        final route = ChosenRoute(
          routeId: 'A',
          durationSeconds: 2170.457,
          distanceMeters: 8420,
          freeFlowDurationSeconds: 2170.4570000000003,
          worstEdgeP: 0,
          geometryRef: 'polyline:x',
        );
        expect(route.hazardTimePenaltySeconds, closeTo(0, 1e-6));
      },
    );

    test(
      'rejects a duration below free-flow duration -- this would silently '
      'violate the ALT-admissibility invariant (docs/DECISIONS.md ADR-003)',
      () {
        expect(
          () => ChosenRoute(
            routeId: 'A',
            durationSeconds: 400,
            distanceMeters: 1000,
            freeFlowDurationSeconds: 500,
            worstEdgeP: 0,
            geometryRef: 'polyline:x',
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });

  group('AlternativeRoute.toJson', () {
    test('emits rejected_because using the wire value, not the enum name', () {
      final json = const AlternativeRoute(
        routeId: 'B',
        durationSeconds: 900,
        rejectedBecause: RejectedBecause.higherCost,
        blockingEdges: [],
      ).toJson();
      expect(json['rejected_because'], equals('higher_cost'));
      expect(json['blocking_edges'], isEmpty);
    });
  });

  group('enum wire values', () {
    test('RoutingMode', () {
      expect(RoutingMode.offline.wireValue, equals('offline'));
      expect(RoutingMode.onlineEnriched.wireValue, equals('online_enriched'));
    });

    test('UserClass', () {
      expect(UserClass.commuter.wireValue, equals('commuter'));
      expect(UserClass.emergency.wireValue, equals('emergency'));
      expect(UserClass.pedestrian.wireValue, equals('pedestrian'));
    });

    test('ConfidenceBand', () {
      expect(ConfidenceBand.high.wireValue, equals('high'));
      expect(ConfidenceBand.moderate.wireValue, equals('moderate'));
      expect(ConfidenceBand.low.wireValue, equals('low'));
      expect(ConfidenceBand.stale.wireValue, equals('stale'));
    });

    test('RejectedBecause', () {
      expect(
        RejectedBecause.chanceConstraint.wireValue,
        equals('chance_constraint'),
      );
      expect(RejectedBecause.higherCost.wireValue, equals('higher_cost'));
    });
  });

  group('classifyConfidence', () {
    const decayTau = 3600.0;

    test('no evidence at all is not representable as "no age" alone -- '
        'nEff below the low threshold classifies as low', () {
      expect(
        classifyConfidence(
          nEff: 0,
          newestObservationAgeSeconds: null,
          decayTauSeconds: decayTau,
        ),
        equals(ConfidenceBand.low),
      );
    });

    test('age past the default staleness cutoff (2x decayTau) is stale, '
        'even with plenty of n_eff', () {
      expect(
        classifyConfidence(
          nEff: 10,
          newestObservationAgeSeconds: 2 * decayTau + 1,
          decayTauSeconds: decayTau,
        ),
        equals(ConfidenceBand.stale),
      );
    });

    test('age exactly at the staleness cutoff is not yet stale (strict >)', () {
      expect(
        classifyConfidence(
          nEff: 10,
          newestObservationAgeSeconds: 2 * decayTau,
          decayTauSeconds: decayTau,
        ),
        equals(ConfidenceBand.high),
      );
    });

    test('fresh but thin evidence (n_eff < 1) is low', () {
      expect(
        classifyConfidence(
          nEff: 0.5,
          newestObservationAgeSeconds: 10,
          decayTauSeconds: decayTau,
        ),
        equals(ConfidenceBand.low),
      );
    });

    test('moderate evidence band (1 <= n_eff < 3)', () {
      expect(
        classifyConfidence(
          nEff: 1,
          newestObservationAgeSeconds: 10,
          decayTauSeconds: decayTau,
        ),
        equals(ConfidenceBand.moderate),
      );
      expect(
        classifyConfidence(
          nEff: 2.9,
          newestObservationAgeSeconds: 10,
          decayTauSeconds: decayTau,
        ),
        equals(ConfidenceBand.moderate),
      );
    });

    test('n_eff >= 3 and fresh is high', () {
      expect(
        classifyConfidence(
          nEff: 3,
          newestObservationAgeSeconds: 10,
          decayTauSeconds: decayTau,
        ),
        equals(ConfidenceBand.high),
      );
    });

    test('a caller-supplied staleAfterSeconds overrides the 2x default', () {
      expect(
        classifyConfidence(
          nEff: 10,
          newestObservationAgeSeconds: 100,
          decayTauSeconds: decayTau,
          staleAfterSeconds: 50,
        ),
        equals(ConfidenceBand.stale),
      );
    });

    test('rejects a negative n_eff or non-positive decayTauSeconds', () {
      expect(
        () => classifyConfidence(
          nEff: -1,
          newestObservationAgeSeconds: null,
          decayTauSeconds: decayTau,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => classifyConfidence(
          nEff: 1,
          newestObservationAgeSeconds: null,
          decayTauSeconds: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'rejects a NaN n_eff outright -- regression for a 2026-09 security '
      'review finding: NaN made every threshold comparison below false and '
      'fell through to ConfidenceBand.high, the most reassuring value, '
      'computed from garbage input and shown directly to the user (ADR-011)',
      () {
        expect(
          () => classifyConfidence(
            nEff: double.nan,
            newestObservationAgeSeconds: null,
            decayTauSeconds: decayTau,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });

  group('ContextFact / DataGap', () {
    test(
      'ContextFact.toJson uses the given value type as-is (int stays int)',
      () {
        final json = ContextFact(
          key: 'reservoir_level_pct',
          value: 94,
          label: 'Chembarambakkam',
          asOf: DateTime.utc(2026, 9, 12, 4),
        ).toJson();
        expect(json['value'], equals(94));
        expect(json['as_of'], equals('2026-09-12T04:00:00Z'));
      },
    );

    test('DataGap.toJson', () {
      const gap = DataGap(
        corridor: 'Velachery Main Rd',
        reason: 'no_observations_in_window',
      );
      expect(gap.toJson(), {
        'corridor': 'Velachery Main Rd',
        'reason': 'no_observations_in_window',
      });
    });
  });
}
