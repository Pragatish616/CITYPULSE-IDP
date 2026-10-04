import 'package:pulse_belief/pulse_belief.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 14, 12);

  WeightedObservation freshCrowdReport(String id) => WeightedObservation(
    id: id,
    polarity: 1,
    distanceM: 0,
    observedAt: t0,
    sourceReliability: 0.9,
  );

  group('planRoute -- no hazard data anywhere', () {
    test('picks the free-flow-optimal route, reports no alternative, lists '
        'no data gap (no edge carries a hazard prior) and says low '
        'confidence', () {
      final graph = CsrGraph.build(
        nodeCount: 3,
        edges: [
          const GraphEdgeInput(
            edgeId: 0,
            from: 0,
            to: 1,
            freeFlowSeconds: 5,
            freeFlowKmh: 40,
          ),
          const GraphEdgeInput(
            edgeId: 1,
            from: 0,
            to: 2,
            freeFlowSeconds: 20,
            freeFlowKmh: 40,
          ),
          const GraphEdgeInput(
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
        computedAt: t0,
        userClass: 'commuter',
        z: 0,
        lambda: 0.3,
        hazardConfigByEdge: const {},
        observationsByEdge: const {},
        sourceClassByObservationId: const {},
        queryId: 'q1',
      );

      expect(trace, isNotNull);
      expect(trace!.chosen.durationSeconds, equals(5));
      expect(trace.alternatives, isEmpty);
      // F-08 (ADR-016): an edge with no hazard entry is not a "data gap" --
      // that label was being put on the *least* risky edges.
      expect(trace.dataGaps, isEmpty);
      expect(trace.confidenceBand, equals(ConfidenceBand.low));
    });
  });

  group('planRoute -- data gaps mean "hazard-map edge, nobody reported" '
      '(F-08)', () {
    // 0 -> 1 -> 2, one edge each.
    final graph = CsrGraph.build(
      nodeCount: 3,
      edges: const [
        GraphEdgeInput(
          edgeId: 0,
          from: 0,
          to: 1,
          freeFlowSeconds: 10,
          freeFlowKmh: 30,
        ),
        GraphEdgeInput(
          edgeId: 1,
          from: 1,
          to: 2,
          freeFlowSeconds: 10,
          freeFlowKmh: 30,
        ),
      ],
    );
    const flood = EdgeHazardConfig(
      hazardClass: 'flood',
      priorLogOdds: -1,
      decayTauSeconds: 3600,
      severity: 1,
      hMaxMm: 300,
      epsilon: 0.1,
    );

    DecisionTrace plan(
      Map<int, EdgeHazardConfig> config,
      Map<int, List<WeightedObservation>> obs,
    ) => planRoute(
      graph: graph,
      source: 0,
      target: 2,
      computedAt: t0,
      userClass: 'commuter',
      z: 0,
      lambda: 0.3,
      hazardConfigByEdge: config,
      observationsByEdge: obs,
      sourceClassByObservationId: const {},
      queryId: 'gap',
      edgeLabel: (id) => id == 0 ? 'Alpha Road' : 'Beta Road',
    )!;

    test('a high-prior edge on the route with no report is listed', () {
      final trace = plan({0: flood}, const {});
      expect(trace.dataGaps.map((g) => g.corridor), equals(['Alpha Road']));
    });

    test('an edge with a fresh report is not listed, and an unhazarded edge '
        'is never listed', () {
      final trace = plan(
        {0: flood},
        {
          0: [freshCrowdReport('r1')],
        },
      );
      expect(trace.dataGaps, isEmpty);
    });

    test('an edge whose only report is older than the staleness cutoff is '
        'listed again', () {
      final trace = plan(
        {0: flood},
        {
          0: [
            WeightedObservation(
              id: 'old',
              polarity: 1,
              distanceM: 0,
              observedAt: t0.subtract(const Duration(hours: 5)),
              sourceReliability: 0.9,
            ),
          ],
        },
      );
      // 5 h > 2 * 3600 s staleness cutoff.
      expect(trace.dataGaps.map((g) => g.corridor), equals(['Alpha Road']));
    });
  });

  group('planRoute -- "avoided" edges and report age (F-04)', () {
    // Two parallel routes 0 -> 3. Fast: 0 -> 1 -> 3 (edges 0, 1). Slow
    // detour: 0 -> 2 -> 3 (edges 2, 3). Edge 0 is a heavily penalised
    // prior-only hazard, so the hazard-aware search takes the detour.
    CsrGraph build() => CsrGraph.build(
      nodeCount: 4,
      edges: const [
        GraphEdgeInput(
          edgeId: 0,
          from: 0,
          to: 1,
          freeFlowSeconds: 30,
          freeFlowKmh: 30,
        ),
        GraphEdgeInput(
          edgeId: 1,
          from: 1,
          to: 3,
          freeFlowSeconds: 30,
          freeFlowKmh: 30,
        ),
        GraphEdgeInput(
          edgeId: 2,
          from: 0,
          to: 2,
          freeFlowSeconds: 40,
          freeFlowKmh: 30,
        ),
        GraphEdgeInput(
          edgeId: 3,
          from: 2,
          to: 3,
          freeFlowSeconds: 40,
          freeFlowKmh: 30,
        ),
      ],
    );
    const hazard = EdgeHazardConfig(
      hazardClass: 'flood',
      priorLogOdds: 3, // p0 ~ 0.95
      decayTauSeconds: 3600,
      severity: 1,
      hMaxMm: 300,
      epsilon: 0.1,
    );

    test('a prior-only avoided edge is marked as having no observation '
        '(so the template cannot say "reported moments ago")', () {
      final trace = planRoute(
        graph: build(),
        source: 0,
        target: 3,
        computedAt: t0,
        userClass: 'pedestrian',
        z: 1.28,
        lambda: 5,
        hazardConfigByEdge: {0: hazard},
        observationsByEdge: const {},
        sourceClassByObservationId: const {},
        queryId: 'prior-only',
        edgeLabel: (id) => 'Road $id',
      )!;
      expect(trace.chosen.geometryRef, equals('nodes:0,2,3'));
      final blocking = trace.alternatives.single.blockingEdges.single;
      expect(blocking.edgeId, equals(0));
      expect(blocking.hasObservation, isFalse);
      expect(blocking.toJson()['has_observation'], isFalse);
    });

    test('avoidance is judged edge by edge: a detour round one stretch of a '
        'street is still reported even though the chosen route uses another '
        'stretch of the same named street', () {
      final trace = planRoute(
        graph: build(),
        source: 0,
        target: 3,
        computedAt: t0,
        userClass: 'pedestrian',
        z: 1.28,
        lambda: 5,
        hazardConfigByEdge: {0: hazard},
        observationsByEdge: const {},
        sourceClassByObservationId: const {},
        queryId: 'same-street',
        // Edge 0 (hazard, on the fast route) and edge 3 (on the chosen
        // detour) are two stretches of the same road.
        edgeLabel: (id) => (id == 0 || id == 3) ? 'Mount Road' : 'Road $id',
      )!;
      expect(trace.chosen.geometryRef, equals('nodes:0,2,3'));
      final blocking = trace.alternatives.single.blockingEdges.single;
      expect(blocking.edgeId, equals(0));
      expect(blocking.streetName, equals('Mount Road'));
    });

    test('an edge the chosen route DOES use is never reported as avoided', () {
      // Hazard on edge 1 only (shared by neither route here): make the chosen
      // route use the hazard edge by making it cheap.
      final trace = planRoute(
        graph: build(),
        source: 0,
        target: 3,
        computedAt: t0,
        userClass: 'commuter',
        z: 0,
        lambda: 0.3,
        hazardConfigByEdge: {
          1: const EdgeHazardConfig(
            hazardClass: 'flood',
            priorLogOdds: -3,
            decayTauSeconds: 3600,
            severity: 1,
            hMaxMm: 300,
            epsilon: 0.1,
          ),
        },
        observationsByEdge: const {},
        sourceClassByObservationId: const {},
        queryId: 'uses-hazard',
        edgeLabel: (id) => 'Road $id',
      )!;
      // Low prior, commuter: the soft penalty is tiny, so the fast route
      // through the hazard edge is still chosen and nothing is "avoided".
      expect(trace.chosen.geometryRef, equals('nodes:0,1,3'));
      expect(trace.alternatives, isEmpty);
    });

    test('a route with no hazard on it reports no alternative at all', () {
      final trace = planRoute(
        graph: build(),
        source: 0,
        target: 3,
        computedAt: t0,
        userClass: 'commuter',
        z: 0,
        lambda: 0.3,
        hazardConfigByEdge: const {},
        observationsByEdge: const {},
        sourceClassByObservationId: const {},
        queryId: 'none',
      )!;
      expect(trace.alternatives, isEmpty);
    });
  });

  group('planRoute -- chance-constraint-forced detour', () {
    test('removes the flooded direct edge and reports it as the blocking '
        'edge with rejected_because = chance_constraint', () {
      final graph = CsrGraph.build(
        nodeCount: 3,
        edges: [
          const GraphEdgeInput(
            edgeId: 0,
            from: 0,
            to: 1,
            freeFlowSeconds: 5,
            freeFlowKmh: 40,
          ),
          const GraphEdgeInput(
            edgeId: 1,
            from: 0,
            to: 2,
            freeFlowSeconds: 20,
            freeFlowKmh: 40,
          ),
          const GraphEdgeInput(
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
        computedAt: t0,
        userClass: 'emergency',
        z: 2,
        lambda: 1,
        hazardConfigByEdge: {
          0: const EdgeHazardConfig(
            hazardClass: 'flood',
            priorLogOdds: -2,
            decayTauSeconds: 3600,
            severity: 1,
            hMaxMm: 300,
            epsilon: 0.1,
            depthMm: 350,
          ),
        },
        observationsByEdge: {
          0: [freshCrowdReport('obs1')],
        },
        sourceClassByObservationId: const {'obs1': 'crowd'},
        queryId: 'q2',
      );

      expect(trace, isNotNull);
      expect(
        trace!.chosen.durationSeconds,
        equals(40),
      ); // forced via 0 -> 2 -> 1
      expect(trace.alternatives, hasLength(1));
      final alt = trace.alternatives.single;
      expect(alt.rejectedBecause, equals(RejectedBecause.chanceConstraint));
      expect(
        alt.durationSeconds,
        equals(5),
      ); // the free-flow time of the direct edge
      expect(alt.blockingEdges, hasLength(1));
      final blocking = alt.blockingEdges.single;
      expect(blocking.edgeId, equals(0));
      expect(blocking.hazardClass, equals('flood'));
      expect(blocking.removedByChanceConstraint, isTrue);
      expect(blocking.timePenaltySeconds, equals(0));
      expect(blocking.sourceClass, equals('crowd'));
      // ADR-015 (F-12): with the Beta quantile a single fresh α=0.9 report
      // at z=2 gives p~ = 0.915, not the Wald index's saturated 1.0. It is
      // still well above the chance-constraint epsilon (0.1), so the 350 mm
      // reading removes the edge exactly as before.
      expect(blocking.pPessimistic, closeTo(0.915, 5e-3));
      expect(blocking.pPessimistic, lessThan(1.0));
      expect(blocking.pPessimistic, greaterThan(blocking.pMean));
    });
  });

  group('planRoute -- higher-cost-forced detour (no chance constraint)', () {
    test('a costly-but-not-removed edge loses to a cheaper detour, reported '
        'with rejected_because = higher_cost', () {
      final graph = CsrGraph.build(
        nodeCount: 3,
        edges: [
          const GraphEdgeInput(
            edgeId: 0,
            from: 0,
            to: 1,
            freeFlowSeconds: 10,
            freeFlowKmh: 30,
          ),
          const GraphEdgeInput(
            edgeId: 1,
            from: 0,
            to: 2,
            freeFlowSeconds: 15,
            freeFlowKmh: 30,
          ),
          const GraphEdgeInput(
            edgeId: 2,
            from: 2,
            to: 1,
            freeFlowSeconds: 15,
            freeFlowKmh: 30,
          ),
        ],
      );

      final trace = planRoute(
        graph: graph,
        source: 0,
        target: 1,
        computedAt: t0,
        userClass: 'pedestrian',
        z: 1.28,
        lambda: 5,
        hazardConfigByEdge: {
          0: const EdgeHazardConfig(
            hazardClass: 'waterlogging',
            priorLogOdds:
                2, // strong prior -> p_mean already high before fusing
            decayTauSeconds: 3600,
            severity: 2,
            hMaxMm: 300,
            epsilon:
                0.9, // high epsilon -> chance constraint won't fire even at p~1
            // depthMm intentionally null: the chance constraint can never
            // fire without a depth reading, however high p_pessimistic gets.
          ),
        },
        observationsByEdge: {
          0: [freshCrowdReport('obs1')],
        },
        sourceClassByObservationId: const {'obs1': 'crowd'},
        queryId: 'q3',
      );

      expect(trace, isNotNull);
      expect(
        trace!.chosen.durationSeconds,
        equals(30),
      ); // via the detour, 15 + 15
      expect(trace.alternatives, hasLength(1));
      final alt = trace.alternatives.single;
      expect(alt.rejectedBecause, equals(RejectedBecause.higherCost));
      expect(
        alt.durationSeconds,
        equals(10),
      ); // the direct edge's free-flow time
      expect(alt.blockingEdges, hasLength(1));
      expect(alt.blockingEdges.single.edgeId, equals(0));
      expect(alt.blockingEdges.single.removedByChanceConstraint, isFalse);
      expect(alt.blockingEdges.single.timePenaltySeconds, greaterThan(0));
    });
  });

  group('planRoute -- unreachable target', () {
    test('returns null when the graph itself is disconnected', () {
      final graph = CsrGraph.build(
        nodeCount: 2,
        edges: [
          const GraphEdgeInput(
            edgeId: 0,
            from: 1,
            to: 0,
            freeFlowSeconds: 10,
            freeFlowKmh: 40,
          ),
        ],
      );
      final trace = planRoute(
        graph: graph,
        source: 0,
        target: 1,
        computedAt: t0,
        userClass: 'commuter',
        z: 0,
        lambda: 0.3,
        hazardConfigByEdge: const {},
        observationsByEdge: const {},
        sourceClassByObservationId: const {},
        queryId: 'q4',
      );
      expect(trace, isNull);
    });
  });

  group(
    'planRoute -- confidence band reflects the least-confident chosen edge',
    () {
      test('a single-edge route with plenty of fresh evidence (five α=0.9 reports, about 3.2 full-report equivalents) is high confidence', () {
        final graph = CsrGraph.build(
          nodeCount: 2,
          edges: [
            const GraphEdgeInput(
              edgeId: 0,
              from: 0,
              to: 1,
              freeFlowSeconds: 10,
              freeFlowKmh: 40,
            ),
          ],
        );
        final trace = planRoute(
          graph: graph,
          source: 0,
          target: 1,
          computedAt: t0,
          userClass: 'commuter',
          z: 0,
          lambda: 0.3,
          hazardConfigByEdge: {
            0: const EdgeHazardConfig(
              hazardClass: 'debris',
              priorLogOdds: -3,
              decayTauSeconds: 900,
              severity: 0.5,
              hMaxMm: 300,
              epsilon: 0.1,
            ),
          },
          observationsByEdge: {
            0: [
              freshCrowdReport('a'),
              freshCrowdReport('b'),
              freshCrowdReport('c'),
              freshCrowdReport('d'),
              freshCrowdReport('e'),
            ],
          },
          sourceClassByObservationId: const {
            'a': 'crowd',
            'b': 'crowd',
            'c': 'crowd',
            'd': 'crowd',
            'e': 'crowd',
          },
          queryId: 'q5',
        );
        expect(trace!.confidenceBand, equals(ConfidenceBand.high));
        expect(trace.dataGaps, isEmpty);
      });

      test('a stale observation (older than the staleness cutoff) is '
          'reported as stale', () {
        final graph = CsrGraph.build(
          nodeCount: 2,
          edges: [
            const GraphEdgeInput(
              edgeId: 0,
              from: 0,
              to: 1,
              freeFlowSeconds: 10,
              freeFlowKmh: 40,
            ),
          ],
        );
        final staleObs = WeightedObservation(
          id: 'old',
          polarity: 1,
          distanceM: 0,
          observedAt: t0.subtract(const Duration(hours: 5)),
          sourceReliability: 0.9,
        );
        final trace = planRoute(
          graph: graph,
          source: 0,
          target: 1,
          computedAt: t0,
          userClass: 'commuter',
          z: 0,
          lambda: 0.3,
          hazardConfigByEdge: {
            0: const EdgeHazardConfig(
              hazardClass: 'flood',
              priorLogOdds: -2,
              decayTauSeconds:
                  3600, // 1 hour -- 5 hours old is well past 2x this
              severity: 1,
              hMaxMm: 300,
              epsilon: 0.1,
            ),
          },
          observationsByEdge: {
            0: [staleObs],
          },
          sourceClassByObservationId: const {'old': 'crowd'},
          queryId: 'q6',
        );
        expect(trace!.confidenceBand, equals(ConfidenceBand.stale));
      });
    },
  );
}
