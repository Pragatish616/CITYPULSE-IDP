import 'dart:math';

import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

CsrGraph _chainGraph() => CsrGraph.build(
  nodeCount: 4,
  edges: [
    const GraphEdgeInput(
      edgeId: 0,
      from: 0,
      to: 1,
      freeFlowSeconds: 10,
      freeFlowKmh: 40,
    ),
    const GraphEdgeInput(
      edgeId: 1,
      from: 1,
      to: 2,
      freeFlowSeconds: 20,
      freeFlowKmh: 40,
    ),
    const GraphEdgeInput(
      edgeId: 2,
      from: 2,
      to: 3,
      freeFlowSeconds: 30,
      freeFlowKmh: 40,
    ),
  ],
);

CsrGraph _twoRouteGraph() => CsrGraph.build(
  nodeCount: 4,
  edges: [
    // 0 -> 1 -> 3 costs 10 + 10 = 20. 0 -> 2 -> 3 costs 5 + 5 = 10.
    const GraphEdgeInput(
      edgeId: 0,
      from: 0,
      to: 1,
      freeFlowSeconds: 10,
      freeFlowKmh: 40,
    ),
    const GraphEdgeInput(
      edgeId: 1,
      from: 1,
      to: 3,
      freeFlowSeconds: 10,
      freeFlowKmh: 40,
    ),
    const GraphEdgeInput(
      edgeId: 2,
      from: 0,
      to: 2,
      freeFlowSeconds: 5,
      freeFlowKmh: 40,
    ),
    const GraphEdgeInput(
      edgeId: 3,
      from: 2,
      to: 3,
      freeFlowSeconds: 5,
      freeFlowKmh: 40,
    ),
  ],
);

double? _freeFlowOnly(RouteEdge e) => e.freeFlowSeconds;

void main() {
  group('selectFarthestPointLandmarks', () {
    test('returns the requested count of distinct, valid node ids', () {
      final graph = _twoRouteGraph();
      final landmarks = selectFarthestPointLandmarks(graph: graph, count: 3);
      expect(landmarks.length, equals(3));
      expect(landmarks.toSet().length, equals(3));
      for (final l in landmarks) {
        expect(l, greaterThanOrEqualTo(0));
        expect(l, lessThan(graph.nodeCount));
      }
    });

    test('always includes the seed node', () {
      final graph = _twoRouteGraph();
      final landmarks = selectFarthestPointLandmarks(
        graph: graph,
        count: 2,
        seedNode: 1,
      );
      expect(landmarks, contains(1));
    });

    test('rejects a count exceeding nodeCount', () {
      final graph = _chainGraph();
      expect(
        () => selectFarthestPointLandmarks(graph: graph, count: 10),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('AltLandmarks.potential', () {
    test('is exactly zero when node == target', () {
      final graph = _chainGraph();
      final landmarks = AltLandmarks.build(graph: graph, landmarkNodes: [3]);
      expect(landmarks.potential(2, 2), equals(0));
    });

    test('never overestimates the true free-flow distance (admissible on '
        'the metric it was built from)', () {
      final graph = _twoRouteGraph();
      final landmarks = AltLandmarks.build(graph: graph, landmarkNodes: [1, 2]);
      // True free-flow distance 0 -> 3 is 10 (via node 2).
      const trueDistance = 10.0;
      expect(landmarks.potential(0, 3), lessThanOrEqualTo(trueDistance));
    });

    test('is never negative', () {
      final graph = _twoRouteGraph();
      final landmarks = AltLandmarks.build(
        graph: graph,
        landmarkNodes: [0, 1, 2, 3],
      );
      for (var u = 0; u < graph.nodeCount; u++) {
        for (var v = 0; v < graph.nodeCount; v++) {
          expect(landmarks.potential(u, v), greaterThanOrEqualTo(0));
        }
      }
    });
  });

  group('aStarWithLandmarks -- hand-built toy graphs', () {
    test('a NaN or negative edgeCost throws immediately -- same regression '
        'as bidirectional_dijkstra_test.dart, for the A* search path', () {
      final graph = _chainGraph();
      final landmarks = AltLandmarks.build(graph: graph, landmarkNodes: [3]);
      expect(
        () => aStarWithLandmarks(
          graph: graph,
          source: 0,
          target: 3,
          edgeCost: (_) => double.nan,
          landmarks: landmarks,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('source == target is a zero-cost, single-node path', () {
      final graph = _chainGraph();
      final landmarks = AltLandmarks.build(graph: graph, landmarkNodes: [3]);
      final result = aStarWithLandmarks(
        graph: graph,
        source: 1,
        target: 1,
        edgeCost: _freeFlowOnly,
        landmarks: landmarks,
      );
      expect(result!.totalCostSeconds, equals(0));
      expect(result.nodePath, equals([1]));
    });

    test('a simple chain picks the only path with the right total cost', () {
      final graph = _chainGraph();
      final landmarks = AltLandmarks.build(graph: graph, landmarkNodes: [3]);
      final result = aStarWithLandmarks(
        graph: graph,
        source: 0,
        target: 3,
        edgeCost: _freeFlowOnly,
        landmarks: landmarks,
      );
      expect(result!.totalCostSeconds, equals(60));
      expect(result.nodePath, equals([0, 1, 2, 3]));
      expect(result.edgePath, equals([0, 1, 2]));
    });

    test('picks the cheaper of two known-cost alternative routes', () {
      final graph = _twoRouteGraph();
      final landmarks = AltLandmarks.build(graph: graph, landmarkNodes: [3]);
      final result = aStarWithLandmarks(
        graph: graph,
        source: 0,
        target: 3,
        edgeCost: _freeFlowOnly,
        landmarks: landmarks,
      );
      expect(result!.totalCostSeconds, equals(10));
      expect(result.nodePath, equals([0, 2, 3]));
    });

    test('unreachable target returns null', () {
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
      final landmarks = AltLandmarks.build(graph: graph, landmarkNodes: [0]);
      final result = aStarWithLandmarks(
        graph: graph,
        source: 0,
        target: 1,
        edgeCost: _freeFlowOnly,
        landmarks: landmarks,
      );
      expect(result, isNull);
    });

    test('a hazard cost function that removes an edge forces the same '
        'detour bidirectionalDijkstra would take', () {
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
      final landmarks = AltLandmarks.build(graph: graph, landmarkNodes: [1]);
      double? cost(RouteEdge e) => e.edgeId == 0 ? null : e.freeFlowSeconds;
      final result = aStarWithLandmarks(
        graph: graph,
        source: 0,
        target: 1,
        edgeCost: cost,
        landmarks: landmarks,
      );
      expect(result!.nodePath, equals([0, 2, 1]));
      expect(result.totalCostSeconds, equals(40));
    });
  });

  group('T2.3 acceptance: ALT admissibility under randomised hazard '
      'configs', () {
    test('over >= 10,000 randomised hazard-derived cost functions on a fixed '
        'graph and a fixed landmark set (built once, on the free-flow metric), '
        'an ALT-guided search never returns a path costlier than plain '
        "bidirectional Dijkstra -- this is the empirical half of the paper's "
        'ALT-admissibility claim (CLAUDE.md §6)', () {
      final rng = Random(20260914);
      const nodeCount = 40;

      final edges = <GraphEdgeInput>[];
      var edgeId = 0;
      for (var u = 0; u < nodeCount; u++) {
        for (var v = 0; v < nodeCount; v++) {
          if (u == v) continue;
          if (rng.nextDouble() < 0.15) {
            edges.add(
              GraphEdgeInput(
                edgeId: edgeId++,
                from: u,
                to: v,
                freeFlowSeconds: 5 + rng.nextDouble() * 95,
                freeFlowKmh: 20 + rng.nextDouble() * 60,
              ),
            );
          }
        }
      }
      final graph = CsrGraph.build(nodeCount: nodeCount, edges: edges);

      // Landmarks built exactly once, on the free-flow metric only --
      // never rebuilt as hazard configurations change below, per the
      // admissibility claim under test.
      final landmarks = AltLandmarks.build(
        graph: graph,
        landmarkNodes: selectFarthestPointLandmarks(graph: graph, count: 4),
      );

      const trials = 10000;
      var comparableTrials = 0;
      for (var trial = 0; trial < trials; trial++) {
        // A random hazard configuration: each edge independently gets a
        // pessimistic hazard probability and depth; some are removed
        // outright by the chance constraint, exactly like a real query.
        final hazardByEdge = <int, ({double pPessimistic, double? depthMm})>{};
        for (final e in edges) {
          if (rng.nextDouble() < 0.3) {
            hazardByEdge[e.edgeId] = (
              pPessimistic: rng.nextDouble(),
              depthMm: rng.nextBool() ? 50 + rng.nextDouble() * 400 : null,
            );
          }
        }

        double? cost(RouteEdge e) {
          final hazard = hazardByEdge[e.edgeId];
          if (hazard == null) return e.freeFlowSeconds;
          return edgeCost(
            freeFlowSeconds: e.freeFlowSeconds,
            freeFlowKmh: e.freeFlowKmh,
            pPessimistic: hazard.pPessimistic,
            depthMm: hazard.depthMm,
            severity: 0.6,
            lambda: 0.5,
            hMaxMm: 300,
            epsilon: 0.15,
          ).costSeconds;
        }

        final source = rng.nextInt(nodeCount);
        final target = rng.nextInt(nodeCount);

        final reference = bidirectionalDijkstra(
          graph: graph,
          source: source,
          target: target,
          edgeCost: cost,
        );
        final altResult = aStarWithLandmarks(
          graph: graph,
          source: source,
          target: target,
          edgeCost: cost,
          landmarks: landmarks,
        );

        if (reference == null) {
          expect(
            altResult,
            isNull,
            reason: 'trial $trial: reference found no path but ALT did',
          );
          continue;
        }
        expect(
          altResult,
          isNotNull,
          reason: 'trial $trial: reference found a path but ALT did not',
        );
        expect(
          altResult!.totalCostSeconds,
          lessThanOrEqualTo(reference.totalCostSeconds + 1e-6),
          reason:
              'trial $trial: ALT returned a costlier path than plain '
              'Dijkstra -- admissibility violated '
              '(source=$source, target=$target)',
        );
        expect(
          altResult.totalCostSeconds,
          closeTo(reference.totalCostSeconds, 1e-6),
          reason:
              'trial $trial: ALT and reference disagree on optimal cost '
              '(source=$source, target=$target)',
        );
        comparableTrials++;
      }

      // Guard against a degenerate test that never actually finds a path
      // (e.g. a bug making the whole graph disconnected) -- that would
      // pass vacuously without checking anything.
      expect(comparableTrials, greaterThan(trials ~/ 2));
    });
  });
}
