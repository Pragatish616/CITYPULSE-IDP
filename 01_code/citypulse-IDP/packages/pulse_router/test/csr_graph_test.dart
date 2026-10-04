import 'package:pulse_router/pulse_router.dart';
import 'package:test/test.dart';

void main() {
  group('CsrGraph', () {
    // 0 -> 1 (edge 10), 0 -> 2 (edge 11), 1 -> 2 (edge 12), 2 -> 0 (edge 13)
    final edges = [
      const GraphEdgeInput(
        edgeId: 10,
        from: 0,
        to: 1,
        freeFlowSeconds: 60,
        freeFlowKmh: 40,
      ),
      const GraphEdgeInput(
        edgeId: 11,
        from: 0,
        to: 2,
        freeFlowSeconds: 90,
        freeFlowKmh: 40,
      ),
      const GraphEdgeInput(
        edgeId: 12,
        from: 1,
        to: 2,
        freeFlowSeconds: 30,
        freeFlowKmh: 40,
      ),
      const GraphEdgeInput(
        edgeId: 13,
        from: 2,
        to: 0,
        freeFlowSeconds: 45,
        freeFlowKmh: 40,
      ),
    ];
    final graph = CsrGraph.build(nodeCount: 3, edges: edges);

    test('reports correct out-degree per node', () {
      expect(graph.outDegree(0), equals(2));
      expect(graph.outDegree(1), equals(1));
      expect(graph.outDegree(2), equals(1));
    });

    test('reports correct in-degree per node', () {
      expect(graph.inDegree(0), equals(1));
      expect(graph.inDegree(1), equals(1));
      expect(graph.inDegree(2), equals(2));
    });

    test('outEdge exposes the right static data, oriented from -> to', () {
      final outFrom0 = [
        for (var i = 0; i < graph.outDegree(0); i++) graph.outEdge(0, i),
      ];
      final edgeIds = outFrom0.map((e) => e.edgeId).toSet();
      expect(edgeIds, equals({10, 11}));
      for (final e in outFrom0) {
        expect(e.from, equals(0));
      }
    });

    test('inEdge exposes the same static data, still oriented from -> to', () {
      final inTo2 = [
        for (var i = 0; i < graph.inDegree(2); i++) graph.inEdge(2, i),
      ];
      final edgeIds = inTo2.map((e) => e.edgeId).toSet();
      expect(edgeIds, equals({11, 12}));
      for (final e in inTo2) {
        expect(e.to, equals(2));
      }
      final viaEdge12 = inTo2.firstWhere((e) => e.edgeId == 12);
      expect(viaEdge12.from, equals(1));
      expect(viaEdge12.freeFlowSeconds, equals(30));
    });

    test('a node with no outgoing edges has out-degree 0, not an error', () {
      final isolated = CsrGraph.build(nodeCount: 2, edges: []);
      expect(isolated.outDegree(0), equals(0));
      expect(isolated.outDegree(1), equals(0));
      expect(isolated.inDegree(0), equals(0));
    });

    test('rejects an edge referencing a node outside nodeCount', () {
      expect(
        () => CsrGraph.build(
          nodeCount: 2,
          edges: [
            const GraphEdgeInput(
              edgeId: 0,
              from: 0,
              to: 5,
              freeFlowSeconds: 1,
              freeFlowKmh: 1,
            ),
          ],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test(
      'GraphEdgeInput rejects non-positive freeFlowSeconds or freeFlowKmh',
      () {
        expect(
          () => GraphEdgeInput(
            edgeId: 0,
            from: 0,
            to: 1,
            freeFlowSeconds: 0,
            freeFlowKmh: 1,
          ),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => GraphEdgeInput(
            edgeId: 0,
            from: 0,
            to: 1,
            freeFlowSeconds: 1,
            freeFlowKmh: 0,
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );
  });
}
