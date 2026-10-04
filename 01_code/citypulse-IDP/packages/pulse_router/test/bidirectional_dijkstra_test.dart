import 'dart:math';

import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

/// A plain, obviously-correct unidirectional Dijkstra, used only to
/// differentially test [bidirectionalDijkstra] against many random graphs.
/// Deliberately not shared code with `lib/src/bidirectional_dijkstra.dart` --
/// the whole point is an independent reference implementation.
double? _referenceDijkstra({
  required CsrGraph graph,
  required int source,
  required int target,
  required EdgeCostFn edgeCost,
}) {
  if (source == target) return 0;
  final dist = <int, double>{source: 0};
  final settled = <int>{};

  while (true) {
    int? u;
    var best = double.infinity;
    for (final entry in dist.entries) {
      if (!settled.contains(entry.key) && entry.value < best) {
        best = entry.value;
        u = entry.key;
      }
    }
    if (u == null) return null; // nothing left to settle, target unreached
    if (u == target) return dist[u];
    settled.add(u);

    for (var i = 0; i < graph.outDegree(u); i++) {
      final edge = graph.outEdge(u, i);
      final cost = edgeCost(edge);
      if (cost == null) continue;
      final nd = dist[u]! + cost;
      final existing = dist[edge.to];
      if (existing == null || nd < existing) {
        dist[edge.to] = nd;
      }
    }
  }
}

void _assertConsistentPath({
  required RouteResult result,
  required CsrGraph graph,
  required int source,
  required int target,
  required EdgeCostFn edgeCost,
}) {
  expect(result.nodePath.first, equals(source));
  expect(result.nodePath.last, equals(target));
  expect(result.edgePath.length, equals(result.nodePath.length - 1));

  var recomputed = 0.0;
  for (var i = 0; i < result.edgePath.length; i++) {
    final from = result.nodePath[i];
    final to = result.nodePath[i + 1];
    RouteEdge? found;
    for (var j = 0; j < graph.outDegree(from); j++) {
      final e = graph.outEdge(from, j);
      if (e.edgeId == result.edgePath[i]) {
        found = e;
        break;
      }
    }
    expect(
      found,
      isNotNull,
      reason: 'edge ${result.edgePath[i]} must actually leave node $from',
    );
    expect(found!.to, equals(to));
    final cost = edgeCost(found);
    expect(
      cost,
      isNotNull,
      reason: 'a path must never use a chance-constraint-removed edge',
    );
    recomputed += cost!;
  }
  expect(recomputed, closeTo(result.totalCostSeconds, 1e-6));
}

void main() {
  group('bidirectionalDijkstra -- hand-built toy graphs', () {
    test('a NaN or negative edgeCost throws immediately -- regression for a '
        "2026-09 security review finding: relax()'s monotonic-improvement "
        'guard (`existing <= candidateDist`) is false for a NaN '
        "candidateDist, so a NaN cost used to poison a node's distance "
        'silently rather than fail loudly', () {
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
      expect(
        () => bidirectionalDijkstra(
          graph: graph,
          source: 0,
          target: 1,
          edgeCost: (_) => double.nan,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => bidirectionalDijkstra(
          graph: graph,
          source: 0,
          target: 1,
          edgeCost: (_) => -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('source == target is a zero-cost, single-node path', () {
      final graph = CsrGraph.build(nodeCount: 1, edges: []);
      final result = bidirectionalDijkstra(
        graph: graph,
        source: 0,
        target: 0,
        edgeCost: (_) => 1,
      );
      expect(result!.totalCostSeconds, equals(0));
      expect(result.nodePath, equals([0]));
      expect(result.edgePath, isEmpty);
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
      final result = bidirectionalDijkstra(
        graph: graph,
        source: 0,
        target: 1,
        edgeCost: (_) => 1,
      );
      expect(result, isNull);
    });

    test('a simple chain picks the only path with the right total cost', () {
      final graph = CsrGraph.build(
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
      double? cost(RouteEdge e) => e.freeFlowSeconds;
      final result = bidirectionalDijkstra(
        graph: graph,
        source: 0,
        target: 3,
        edgeCost: cost,
      );
      expect(result!.totalCostSeconds, equals(60));
      expect(result.nodePath, equals([0, 1, 2, 3]));
      expect(result.edgePath, equals([0, 1, 2]));
    });

    test('picks the cheaper of two known-cost alternative routes', () {
      // 0 -> 1 -> 3 costs 10 + 10 = 20. 0 -> 2 -> 3 costs 5 + 5 = 10.
      final graph = CsrGraph.build(
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
      double? cost(RouteEdge e) => e.freeFlowSeconds;
      final result = bidirectionalDijkstra(
        graph: graph,
        source: 0,
        target: 3,
        edgeCost: cost,
      );
      expect(result!.totalCostSeconds, equals(10));
      expect(result.nodePath, equals([0, 2, 3]));
    });

    test('a hazard cost function that removes an edge forces a detour', () {
      // Direct 0 -> 1 (edge 0, cheap) is removed by the hazard cost
      // function; the only surviving path is 0 -> 2 -> 1 (edges 1, 2).
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
      double? cost(RouteEdge e) => e.edgeId == 0 ? null : e.freeFlowSeconds;
      final result = bidirectionalDijkstra(
        graph: graph,
        source: 0,
        target: 1,
        edgeCost: cost,
      );
      expect(result!.nodePath, equals([0, 2, 1]));
      expect(result.totalCostSeconds, equals(40));
    });

    test('uses the ADR-003 edgeCost function end-to-end, not just synthetic '
        'weights', () {
      final graph = CsrGraph.build(
        nodeCount: 2,
        edges: [
          const GraphEdgeInput(
            edgeId: 0,
            from: 0,
            to: 1,
            freeFlowSeconds: 100,
            freeFlowKmh: 30,
          ),
        ],
      );
      double? cost(RouteEdge e) => edgeCost(
        freeFlowSeconds: e.freeFlowSeconds,
        freeFlowKmh: e.freeFlowKmh,
        pPessimistic: 0.5,
        depthMm: 10,
        severity: 0.6,
        lambda: 0.3,
        hMaxMm: 300,
        epsilon: 0.1,
      ).costSeconds;
      final result = bidirectionalDijkstra(
        graph: graph,
        source: 0,
        target: 1,
        edgeCost: cost,
      );
      expect(result!.totalCostSeconds, greaterThanOrEqualTo(100));
    });
  });

  group('bidirectionalDijkstra -- differential test against a reference '
      'Dijkstra', () {
    test(
      'matches a plain reference Dijkstra across many random small graphs',
      () {
        final rng = Random(20260913);

        for (var trial = 0; trial < 300; trial++) {
          const nodeCount = 8;
          final edges = <GraphEdgeInput>[];
          var edgeId = 0;
          for (var u = 0; u < nodeCount; u++) {
            for (var v = 0; v < nodeCount; v++) {
              if (u == v) continue;
              if (rng.nextDouble() < 0.25) {
                edges.add(
                  GraphEdgeInput(
                    edgeId: edgeId++,
                    from: u,
                    to: v,
                    freeFlowSeconds: 1 + rng.nextDouble() * 100,
                    freeFlowKmh: 30,
                  ),
                );
              }
            }
          }
          final graph = CsrGraph.build(nodeCount: nodeCount, edges: edges);

          // Randomly remove ~10% of edges via the cost function, so chance-
          // constraint-style removal is exercised too.
          final removed = <int>{
            for (final e in edges)
              if (rng.nextDouble() < 0.1) e.edgeId,
          };
          double? cost(RouteEdge e) =>
              removed.contains(e.edgeId) ? null : e.freeFlowSeconds;

          final source = rng.nextInt(nodeCount);
          final target = rng.nextInt(nodeCount);

          final expected = _referenceDijkstra(
            graph: graph,
            source: source,
            target: target,
            edgeCost: cost,
          );
          final actual = bidirectionalDijkstra(
            graph: graph,
            source: source,
            target: target,
            edgeCost: cost,
          );

          if (expected == null) {
            expect(
              actual,
              isNull,
              reason:
                  'trial $trial: reference found no path but bidirectional did',
            );
          } else {
            expect(
              actual,
              isNotNull,
              reason:
                  'trial $trial: reference found a path (cost $expected) but '
                  'bidirectional did not',
            );
            expect(
              actual!.totalCostSeconds,
              closeTo(expected, 1e-6),
              reason: 'trial $trial: source=$source target=$target',
            );
            _assertConsistentPath(
              result: actual,
              graph: graph,
              source: source,
              target: target,
              edgeCost: cost,
            );
          }
        }
      },
    );
  });
}
