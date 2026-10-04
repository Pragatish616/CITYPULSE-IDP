import 'dart:convert';
import 'dart:io';

import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('DecisionTrace JSON round trip', () {
    DecisionTrace sample({bool prior = false}) => DecisionTrace(
      queryId: '0192f3d0-0000-7000-8000-000000000000',
      computedAt: DateTime.utc(2026, 9, 12, 5, 15, 1),
      mode: RoutingMode.offline,
      userClass: UserClass.pedestrian,
      z: 1.28,
      lambda: 1.2,
      chosen: ChosenRoute(
        routeId: 'A',
        durationSeconds: 1147,
        distanceMeters: 8420,
        freeFlowDurationSeconds: 1023,
        worstEdgeP: 0.31,
        geometryRef: 'nodes:1,2,3',
      ),
      alternatives: [
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
              newestObservationAgeSeconds: prior ? 0 : 179,
              sourceClass: prior ? 'unknown' : 'crowd',
              depthMm: 320,
              timePenaltySeconds: 0,
              removedByChanceConstraint: true,
              hasObservation: !prior,
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
        DataGap(
          corridor: 'Velachery Main Rd',
          reason: 'no_observations_in_window',
        ),
      ],
      confidenceBand: ConfidenceBand.low,
    );

    for (final prior in [false, true]) {
      test('toJson -> fromJson -> toJson is the identity '
          '(prior-only edge: $prior)', () {
        final wire = jsonDecode(
          jsonEncode(sample(prior: prior).toJson()),
        ) as Map<String, Object?>;
        final rebuilt = DecisionTrace.fromJson(wire);
        expect(jsonEncode(rebuilt.toJson()), equals(jsonEncode(wire)));
        expect(
          rebuilt.alternatives.single.blockingEdges.single.hasObservation,
          equals(!prior),
        );
      });
    }

    test('has_observation is only written when it is false (the golden wire '
        'format is unchanged)', () {
      final withReport = sample().toJson();
      final blocking =
          ((withReport['alternatives']! as List).single
                  as Map)['blocking_edges']
              as List;
      expect((blocking.single as Map).containsKey('has_observation'), isFalse);
      final priorOnly = sample(prior: true).toJson();
      final b2 =
          ((priorOnly['alternatives']! as List).single as Map)['blocking_edges']
              as List;
      expect((b2.single as Map)['has_observation'], isFalse);
    });

    test('a missing or mistyped field is a FormatException naming it', () {
      final wire =
          jsonDecode(jsonEncode(sample().toJson())) as Map<String, Object?>;
      (wire['chosen']! as Map<String, Object?>).remove('free_flow_duration_s');
      expect(
        () => DecisionTrace.fromJson(wire),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('free_flow_duration_s'),
          ),
        ),
      );
      final bad =
          jsonDecode(jsonEncode(sample().toJson())) as Map<String, Object?>;
      bad['confidence_band'] = 'perfect';
      expect(() => DecisionTrace.fromJson(bad), throwsFormatException);
    });

    test('an impossible trace from a server is rejected, not displayed', () {
      final wire =
          jsonDecode(jsonEncode(sample().toJson())) as Map<String, Object?>;
      (wire['chosen']! as Map<String, Object?>)['duration_s'] = 500;
      expect(() => DecisionTrace.fromJson(wire), throwsArgumentError);
    });
  });

  group('EngineConfig.fromMap against the real config/hazard_classes.yaml', () {
    final doc = loadYaml(
      File('../../config/hazard_classes.yaml').readAsStringSync(),
    ) as YamlMap;
    final config = EngineConfig.fromMap(doc);

    test('reads every section with the shipped values', () {
      expect(config.sourceReliability['crowd'], 0.6);
      expect(config.sourceReliability['municipal_sensor'], 0.97);
      expect(config.userClasses['commuter']!.z, 0);
      expect(config.userClasses['emergency']!.z, 2);
      expect(config.userClasses['pedestrian']!.lambda, 1.2);
      expect(config.hazardClasses['flood']!.decayTauSeconds, 7200);
      expect(config.hazardClasses['flood']!.hMaxMm, 300);
      expect(config.hazardClasses['waterlogging']!.hMaxMm, 200);
      expect(config.displayNouns['flood'], 'flooding');
    });

    test('a class that omits h_max_mm / epsilon gets the documented '
        'defaults', () {
      expect(config.hazardClasses['debris']!.hMaxMm, 300);
      expect(config.hazardClasses['debris']!.epsilon, 0.1);
    });

    test('a missing section or a non-number is a FormatException', () {
      expect(() => EngineConfig.fromMap({}), throwsFormatException);
      expect(
        () => EngineConfig.fromMap({
          'classes': {
            'flood': {'T_c_seconds': 'soon', 'severity': 1},
          },
          'user_classes': <String, Object?>{},
          'source_reliability': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });
  });
}
