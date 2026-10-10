// ADR-032: hard limits on segments. The traveller's "Avoid accidents" choice, limits per travel mode, the fallback
// when the limits cut a trip off, the trace's `restricted` reason and what the advisor makes of it. The engine tests
// run on the real Chennai pack (data/packs/2026-10-02, in git), like engine_test.dart.
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _packDir = '../../data/packs/2026-10-02';

ByteData _read(String name) =>
    ByteData.sublistView(File('$_packDir/$name').readAsBytesSync());

const _classes = {
  'flood': HazardClassParams(
    decayTauSeconds: 7200,
    severity: 1,
    hMaxMm: 300,
    epsilon: 0.1,
  ),
  'waterlogging': HazardClassParams(
    decayTauSeconds: 5400,
    severity: 0.6,
    hMaxMm: 200,
    epsilon: 0.15,
  ),
  'accident': HazardClassParams(
    decayTauSeconds: 1800,
    severity: 0.4,
    hMaxMm: 300,
    epsilon: 0.1,
  ),
  'closure': HazardClassParams(
    decayTauSeconds: 14400,
    severity: 0.9,
    hMaxMm: 300,
    epsilon: 0.1,
  ),
};
const _users = {
  'commuter': UserClassParams(z: 0, lambda: 0.3),
  'emergency': UserClassParams(z: 2, lambda: 1),
};
const _reliability = {
  'municipal_sensor': 0.97,
  'official_feed': 0.92,
  'verified_responder': 0.9,
  'crowd': 0.6,
  'app_traversal': 0.7,
};

void main() {
  final t = DateTime.utc(2026, 10, 11, 6);

  // ---- the planner on a tiny graph ---------------------------------------------------------------------------------
  group('planRouteDetailed with restricted segments', () {
    // 0 -> 1 directly (edge 0, 5 s) or round by 2 (edges 1 and 2, 40 s).
    final graph = CsrGraph.build(
      nodeCount: 3,
      edges: const [
        GraphEdgeInput(
          edgeId: 0,
          from: 0,
          to: 1,
          freeFlowSeconds: 5,
          freeFlowKmh: 40,
        ),
        GraphEdgeInput(
          edgeId: 1,
          from: 0,
          to: 2,
          freeFlowSeconds: 20,
          freeFlowKmh: 40,
        ),
        GraphEdgeInput(
          edgeId: 2,
          from: 2,
          to: 1,
          freeFlowSeconds: 20,
          freeFlowKmh: 40,
        ),
      ],
    );
    const accident = RestrictedEdge(
      rule: 'avoid_reported',
      hazardClass: 'accident',
      pMean: 0.4,
      pPessimistic: 0.4,
      nEff: 1,
      newestReportAgeSeconds: 300,
      sourceClass: 'crowd',
      reportCount: 1,
    );

    PlannedRoute? plan(Map<int, RestrictedEdge> closed) => planRouteDetailed(
      graph: graph,
      source: 0,
      target: 1,
      computedAt: t,
      userClass: 'commuter',
      z: 0,
      lambda: 0.3,
      hazardConfigByEdge: const {},
      observationsByEdge: const {},
      sourceClassByObservationId: const {},
      queryId: 'q',
      edgeLabel: (id) => 'Road $id',
      restrictedEdges: closed,
    );

    test('a closed segment is not used, whatever the extra time, and the faster route is reported as restricted', () {
      final open = plan(const {})!;
      expect(open.chosenNodes, [0, 1]);
      final closed = plan({0: accident})!;
      expect(closed.chosenNodes, [
        0,
        2,
        1,
      ], reason: '40 s round instead of 5 s direct');
      expect(closed.trace.chosen.freeFlowDurationSeconds, 40);
      final alt = closed.trace.alternatives.single;
      expect(alt.rejectedBecause, RejectedBecause.restricted);
      final b = alt.blockingEdges.single;
      expect(
        (
          b.edgeId,
          b.hazardClass,
          b.streetName,
          b.newestObservationAgeSeconds,
          b.hasObservation,
        ),
        (0, 'accident', 'Road 0', 300.0, true),
      );
      expect(b.removedByChanceConstraint, isFalse);
    });

    test('when the closed segments cut the trip off, the planner returns null and leaves the choice to the caller', () {
      expect(plan({0: accident, 1: accident}), isNull);
    });
  });

  // ---- the wire format -----------------------------------------------------------------------------------------------
  test('the trace says "restricted" on the wire and reads it back', () {
    expect(RejectedBecause.restricted.wireValue, 'restricted');
    final graph = CsrGraph.build(
      nodeCount: 3,
      edges: const [
        GraphEdgeInput(
          edgeId: 0,
          from: 0,
          to: 1,
          freeFlowSeconds: 5,
          freeFlowKmh: 40,
        ),
        GraphEdgeInput(
          edgeId: 1,
          from: 0,
          to: 2,
          freeFlowSeconds: 20,
          freeFlowKmh: 40,
        ),
        GraphEdgeInput(
          edgeId: 2,
          from: 2,
          to: 1,
          freeFlowSeconds: 20,
          freeFlowKmh: 40,
        ),
      ],
    );
    final trace = planRoute(
      graph: graph,
      source: 0,
      target: 1,
      computedAt: t,
      userClass: 'commuter',
      z: 0,
      lambda: 0.3,
      hazardConfigByEdge: const {},
      observationsByEdge: const {},
      sourceClassByObservationId: const {},
      queryId: 'q',
      restrictedEdges: const {
        0: RestrictedEdge(
          rule: 'avoid_reported',
          hazardClass: 'accident',
          pMean: 0.4,
          pPessimistic: 0.4,
          nEff: 1,
          newestReportAgeSeconds: 60,
          sourceClass: 'crowd',
          reportCount: 1,
        ),
      },
    )!;
    final json = trace.toJson();
    expect(
      (json['alternatives']! as List)
          .cast<Map<String, Object?>>()
          .single['rejected_because'],
      'restricted',
    );
    expect(
      DecisionTrace.fromJson(json).alternatives.single.rejectedBecause,
      RejectedBecause.restricted,
    );
  });

  // ---- the config --------------------------------------------------------------------------------------------------
  group('the restrictions section of the config', () {
    Map<Object?, Object?> doc(Object? restrictions) => {
      'source_reliability': _reliability,
      'user_classes': {
        'commuter': {'z': 0, 'lambda': 0.3},
      },
      'travel_profiles': {
        'foot': {
          'speed_kmh': {'default': 4.5},
        },
      },
      'classes': {
        'flood': {'T_c_seconds': 7200, 'severity': 1.0},
        'accident': {'T_c_seconds': 1800, 'severity': 0.4},
      },
      'restrictions': restrictions,
    };

    test('is read per travel mode, and a missing section means no limits', () {
      final none = EngineConfig.fromMap(doc(null));
      expect(none.restrictions.byProfile, isEmpty);
      final c = EngineConfig.fromMap(
        doc({
          'report_window_factor': 2,
          'reliable_source_at': 0.85,
          'profiles': {
            'foot': {
              'avoid_reported': ['accident'],
              'max_flood_index': 0.6,
              'min_reports': 2,
            },
          },
        }),
      );
      final foot = c.restrictions.byProfile['foot']!;
      expect(foot.avoidReported, {'accident'});
      expect((foot.maxFloodIndex, foot.minReports), (0.6, 2));
      expect(
        foot.describe(),
        'avoid_reported=accident,max_flood_index=0.6,min_reports=2',
      );
    });

    test('refuses an unknown class, an unknown mode, and a flood index outside (0, 1]', () {
      expect(
        () => EngineConfig.fromMap(
          doc({
            'profiles': {
              'foot': {
                'avoid_reported': ['meteor'],
              },
            },
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => EngineConfig.fromMap(
          doc({
            'profiles': {
              'boat': {
                'avoid_reported': ['accident'],
              },
            },
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => EngineConfig.fromMap(
          doc({
            'profiles': {
              'foot': {'max_flood_index': 1.5},
            },
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => EngineConfig.fromMap(
          doc({
            'profiles': {
              'foot': {'min_reports': 0},
            },
          }),
        ),
        throwsFormatException,
      );
    });

    test(
      'the shipped config parses, and its limits name real classes and modes',
      () {
        final c = EngineConfig.fromMap(
          loadYaml(File('../../config/hazard_classes.yaml').readAsStringSync())
              as Map<Object?, Object?>,
        );
        expect(
          c.restrictions.byProfile.keys,
          containsAll(['foot', 'emergency']),
        );
        for (final rules in c.restrictions.byProfile.values) {
          expect(
            rules.minReports,
            greaterThanOrEqualTo(2),
            reason: 'a mode limit applies to everyone using the mode',
          );
        }
      },
    );
  });

  // ---- the engine on the real pack -----------------------------------------------------------------------------------
  group('RoutingEngine limits on the Chennai pack', () {
    late MapPack pack;
    late EdgeSnapper snapper;
    // T. Nagar to Velachery, as in engine_test.dart.
    const from = 31140;
    const to = 47036;

    setUpAll(() {
      pack = MapPack.parse(
        graph: _read('graph.bin'),
        nodes: _read('nodes.bin'),
        meta: _read('meta.bin'),
      );
      snapper = EdgeSnapper(pack);
    });

    RoutingEngine engine({
      RestrictionConfig restrictions = const RestrictionConfig(),
    }) => RoutingEngine(
      pack: pack,
      snapper: snapper,
      hazardClasses: _classes,
      userClasses: _users,
      sourceReliability: _reliability,
      eventState: EventState.dry,
      restrictionConfig: restrictions,
    );

    RoutePlan route(
      RoutingEngine e, {
      Set<String> avoid = const {},
      String user = 'commuter',
    }) {
      final out = e.route(
        fromLat: pack.nodeLat[from],
        fromLon: pack.nodeLon[from],
        toLat: pack.nodeLat[to],
        toLon: pack.nodeLon[to],
        userClass: user,
        at: t,
        avoidReported: avoid,
      );
      expect(out, isA<RouteFound>(), reason: '$out');
      return (out as RouteFound).plan;
    }

    List<int> nodesOf(RoutePlan p) => p.trace.chosen.geometryRef
        .substring('nodes:'.length)
        .split(',')
        .map(int.parse)
        .toList();

    Set<int> edgesOf(RoutePlan p) {
      final n = nodesOf(p);
      final out = <int>{};
      for (var i = 0; i + 1 < n.length; i++) {
        for (var k = 0; k < pack.graph.outDegree(n[i]); k++) {
          final e = pack.graph.outEdge(n[i], k);
          if (e.to == n[i + 1]) out.add(e.edgeId);
        }
      }
      return out;
    }

    ({double lat, double lon}) midOfRoute(RoutePlan p) {
      final n = nodesOf(p);
      final mid = n[n.length ~/ 2];
      return (lat: pack.nodeLat[mid], lon: pack.nodeLon[mid]);
    }

    EngineObservation report(
      String id,
      ({double lat, double lon}) at, {
      String cls = 'accident',
      int polarity = 1,
      Duration ago = const Duration(minutes: 5),
      String source = 'crowd',
    }) => EngineObservation(
      id: id,
      hazardClass: cls,
      polarity: polarity,
      lat: at.lat,
      lon: at.lon,
      observedAt: t.subtract(ago),
      sourceClass: source,
    );

    Object? fact(RoutePlan p, String key) {
      for (final f in p.trace.contextFacts) {
        if (f.key == key) return f.value;
      }
      return null;
    }

    test('with "Avoid accidents" on, the route keeps off every segment the report touches, whatever the time', () {
      final e = engine();
      final base = route(e);
      final spot = midOfRoute(base);
      e.addObservation(report('a1', spot));
      final touched = {
        for (final m in snapper.edgesNear(
          spot.lat,
          spot.lon,
          radiusM: 75,
          limit: 24,
        ))
          m.edgeId,
      };
      expect(touched, isNotEmpty);

      final usual = route(e);
      expect(fact(usual, 'traveller_avoids'), isNull);
      final avoided = route(e, avoid: {'accident'});
      expect(edgesOf(avoided).intersection(touched), isEmpty);
      expect(fact(avoided, 'traveller_avoids'), 'accident');
      expect(fact(avoided, 'restricted_segments'), greaterThanOrEqualTo(1));
      expect(fact(avoided, 'limits_not_met'), isNull);
      expect(fact(avoided, 'accident_reports_on_route'), 0);
      final alt = avoided.trace.alternatives.first;
      expect(alt.rejectedBecause, RejectedBecause.restricted);
      expect(
        alt.blockingEdges.every(
          (b) => b.hazardClass == 'accident' && b.hasObservation,
        ),
        isTrue,
      );
      expect(
        avoided.trace.chosen.freeFlowDurationSeconds,
        greaterThanOrEqualTo(base.trace.chosen.freeFlowDurationSeconds),
      );
      expect(
        avoided.avoidedHazards,
        isNotEmpty,
        reason: 'the map marks the avoided accident',
      );

      final advice = advise(
        RouteFacts.fromTrace(avoided.trace, eventState: EventState.dry),
      );
      expect(advice.reasons.first, AdviceReason.restrictedAvoided);
    });

    test(
      'without the switch the route may cross it, and the advisor is told so',
      () {
        final e = engine();
        final base = route(e);
        e.addObservation(report('a1', midOfRoute(base)));
        final usual = route(e);
        final on = fact(usual, 'accident_reports_on_route')! as int;
        if (on > 0) {
          final advice = advise(
            RouteFacts.fromTrace(usual.trace, eventState: EventState.dry),
          );
          expect(advice.reasons.first, AdviceReason.accidentOnRoute);
          expect(advice.riskLevel, isNot(RiskLevel.lower));
        }
      },
    );

    test('a newer "cleared" report of the same class lifts the limit; an old report does not count', () {
      final e = engine();
      final base = route(e);
      final spot = midOfRoute(base);
      e
        ..addObservation(report('a1', spot, ago: const Duration(minutes: 20)))
        ..addObservation(
          report('c1', spot, polarity: -1, ago: const Duration(minutes: 5)),
        );
      expect(
        fact(route(e, avoid: {'accident'}), 'restricted_segments'),
        isNull,
      );

      final old = engine()
        ..addObservation(report('a2', spot, ago: const Duration(minutes: 61)));
      expect(
        fact(route(old, avoid: {'accident'}), 'restricted_segments'),
        isNull,
        reason: 'older than 2 x T_c (30 min) for accidents',
      );
    });

    test('a mode limit needs two reports or one reliable source; the traveller\'s own choice needs one', () {
      const limits = RestrictionConfig(
        byProfile: {
          'car': RestrictionRules(avoidReported: {'accident'}, minReports: 2),
        },
      );
      final base = route(engine());
      final spot = midOfRoute(base);

      final one = engine(restrictions: limits)
        ..addObservation(report('a1', spot));
      expect(
        fact(route(one), 'restricted_segments'),
        isNull,
        reason: 'one anonymous report must not close a road for everyone',
      );
      expect(
        fact(route(one), 'mode_limits'),
        'avoid_reported=accident,min_reports=2',
      );
      expect(
        fact(route(one, avoid: {'accident'}), 'restricted_segments'),
        greaterThanOrEqualTo(1),
      );

      final two = engine(restrictions: limits)
        ..addObservation(report('a1', spot))
        ..addObservation(report('a2', spot, ago: const Duration(minutes: 3)));
      expect(fact(route(two), 'restricted_segments'), greaterThanOrEqualTo(1));

      final official = engine(restrictions: limits)
        ..addObservation(report('o1', spot, source: 'official_feed'));
      expect(
        fact(route(official), 'restricted_segments'),
        greaterThanOrEqualTo(1),
      );
    });

    test('when the limits cut the destination off, the usual route is shown and says so', () {
      final e = engine()
        ..addObservation(
          report('at-destination', (
            lat: pack.nodeLat[to],
            lon: pack.nodeLon[to],
          )),
        );
      final p = route(e, avoid: {'accident'});
      expect(fact(p, 'limits_not_met'), isTrue);
      expect(
        p.trace.alternatives.where(
          (a) => a.rejectedBecause == RejectedBecause.restricted,
        ),
        isEmpty,
      );
      final advice = advise(
        RouteFacts.fromTrace(p.trace, eventState: EventState.dry),
      );
      expect(advice.reasons.first, AdviceReason.limitsNotMet);
      expect(advice.riskLevel, isNot(RiskLevel.lower));
    });

    test('an unknown class to avoid is refused', () {
      expect(
        () => engine().route(
          fromLat: pack.nodeLat[from],
          fromLon: pack.nodeLon[from],
          toLat: pack.nodeLat[to],
          toLon: pack.nodeLon[to],
          userClass: 'commuter',
          at: t,
          avoidReported: {'meteor'},
        ),
        throwsArgumentError,
      );
    });
  });

  // ---- the advisor -------------------------------------------------------------------------------------------------
  group('the advisor with ADR-032 inputs', () {
    RouteFacts facts({
      int accidents = 0,
      int restricted = 0,
      bool notMet = false,
      double p = 0.01,
    }) => RouteFacts(
      worstEdgeP: p,
      hazardPenaltyRatio: 0,
      confidence: ConfidenceBand.moderate,
      dataGapCount: 0,
      userClass: UserClass.commuter,
      eventState: EventState.active,
      accidentReportsOnRoute: accidents,
      restrictedAlternatives: restricted,
      limitsNotMet: notMet,
    );

    test('an accident on the route is never "lower" risk and makes going ahead less likely', () {
      final quiet = advise(facts());
      final accident = advise(facts(accidents: 1));
      expect(accident.riskLevel, isNot(RiskLevel.lower));
      expect(
        accident.action[AdviceAction.proceedWithCare]!,
        lessThan(quiet.action[AdviceAction.proceedWithCare]!),
      );
      expect(accident.reasons.first, AdviceReason.accidentOnRoute);
      expect(
        accident.reasons,
        isNot(contains(AdviceReason.noHazardFound)),
        reason:
            '"no hazard found" would be false with an accident on the route',
      );
    });

    test('limits not met come first and also count as risk', () {
      final a = advise(facts(notMet: true, restricted: 1));
      expect(a.reasons.first, AdviceReason.limitsNotMet);
      expect(a.reasons, isNot(contains(AdviceReason.restrictedAvoided)));
      expect(a.riskLevel, isNot(RiskLevel.lower));
    });

    test('a restricted faster route is given as a reason and does not change the risk of the chosen one', () {
      final a = advise(facts(restricted: 1));
      expect(a.reasons.first, AdviceReason.restrictedAvoided);
      expect(a.risk, advise(facts()).risk);
    });

    test('scores still sum to 1 with the new inputs', () {
      for (final f in [
        facts(accidents: 3),
        facts(notMet: true),
        facts(restricted: 2, p: 0.7),
      ]) {
        final a = advise(f);
        expect(
          a.risk.values.fold<double>(0, (s, v) => s + v),
          closeTo(1, 1e-9),
        );
        expect(
          a.action.values.fold<double>(0, (s, v) => s + v),
          closeTo(1, 1e-9),
        );
      }
    });
  });
}
