import 'package:collection/collection.dart';

import 'package:pulse_router/src/bidirectional_dijkstra.dart';
import 'package:pulse_router/src/csr_graph.dart';

/// Single-source shortest-path distances from [source] over [graph]'s
/// **free-flow metric** (`τ₀` only — never a hazard-adjusted cost). When
/// [forward] is `true`, walks [CsrGraph.outEdge] as usual; when `false`,
/// walks [CsrGraph.inEdge] to compute distances as if on the reversed graph
/// (i.e. `result[v]` is the shortest `v -> source` distance in the
/// *original* graph).
///
/// Landmarks are precomputed once on this fixed, always-available metric —
/// never on a specific hazard state — which is exactly what lets the same
/// landmark set stay valid under every possible hazard configuration (see
/// [AltLandmarks]'s doc comment).
List<double> _singleSourceFreeFlowDistances({
  required CsrGraph graph,
  required int source,
  required bool forward,
}) {
  final dist = List<double>.filled(graph.nodeCount, double.infinity);
  final settled = List<bool>.filled(graph.nodeCount, false);
  dist[source] = 0;

  final queue = HeapPriorityQueue<(int node, double dist)>(
    (a, b) => a.$2.compareTo(b.$2),
  )..add((source, 0));

  while (queue.isNotEmpty) {
    final (u, d) = queue.removeFirst();
    if (settled[u]) continue;
    if (d > dist[u]) continue; // stale lazy-deletion entry
    settled[u] = true;

    final degree = forward ? graph.outDegree(u) : graph.inDegree(u);
    for (var i = 0; i < degree; i++) {
      final edge = forward ? graph.outEdge(u, i) : graph.inEdge(u, i);
      final neighbor = forward ? edge.to : edge.from;
      final nd = dist[u] + edge.freeFlowSeconds;
      if (nd < dist[neighbor]) {
        dist[neighbor] = nd;
        queue.add((neighbor, nd));
      }
    }
  }
  return dist;
}

/// Selects [count] landmark node ids via farthest-point sampling on the
/// free-flow metric, starting from [seedNode]: repeatedly pick the
/// not-yet-chosen node with the greatest forward free-flow distance from the
/// nearest existing landmark. A simple, standard heuristic for landmark
/// *placement quality* — it does not affect correctness (any landmark set
/// gives a valid, consistent [AltLandmarks] potential; see that class's doc
/// comment), only how tight the resulting heuristic is.
///
/// Uses forward distance only, as a directed-graph approximation of "spread
/// out" — a deliberate simplification, not a claim of optimal placement.
List<int> selectFarthestPointLandmarks({
  required CsrGraph graph,
  required int count,
  int seedNode = 0,
}) {
  assert(count >= 1, 'count must be at least 1: got $count');
  assert(
    seedNode >= 0 && seedNode < graph.nodeCount,
    'seedNode out of range [0, ${graph.nodeCount}): got $seedNode',
  );
  assert(
    count <= graph.nodeCount,
    'count ($count) exceeds nodeCount (${graph.nodeCount})',
  );

  final landmarks = <int>[seedNode];
  final minDistToAnyLandmark = _singleSourceFreeFlowDistances(
    graph: graph,
    source: seedNode,
    forward: true,
  );

  while (landmarks.length < count) {
    var best = -1;
    var bestDist = -1.0;
    for (var v = 0; v < graph.nodeCount; v++) {
      final d = minDistToAnyLandmark[v];
      if (d.isFinite && d > bestDist) {
        bestDist = d;
        best = v;
      }
    }
    if (best == -1) {
      break; // every remaining node is unreachable from all landmarks so far
    }
    landmarks.add(best);

    final distFromNewLandmark = _singleSourceFreeFlowDistances(
      graph: graph,
      source: best,
      forward: true,
    );
    for (var v = 0; v < graph.nodeCount; v++) {
      if (distFromNewLandmark[v] < minDistToAnyLandmark[v]) {
        minDistToAnyLandmark[v] = distFromNewLandmark[v];
      }
    }
  }
  return landmarks;
}

/// ALT (A*, Landmarks, Triangle inequality) potentials, precomputed once on
/// the free-flow metric (`docs/IMPLEMENTATION_PLAN.md` T2.3).
///
/// **The admissibility result this exists to demonstrate (`CLAUDE.md` §6):**
/// since every hazard-aware edge cost satisfies `w_λ(e,t) ≥ τ₀(e,t)` (the
/// ADR-003 invariant `edgeCost` and `slowdownDelta`'s `max(1, ...)` clamp
/// guarantee), a potential built from free-flow shortest paths is not merely
/// *admissible* but **consistent** under any hazard-inflated cost function:
/// for free-flow distances, `h(u) ≤ τ₀(u,v) + h(v)` holds by the standard
/// ALT triangle-inequality argument; since `cost(u,v) ≥ τ₀(u,v)` always,
/// `h(u) ≤ cost(u,v) + h(v)` holds too. A consistent heuristic means
/// [aStarWithLandmarks] never needs to re-expand a settled node and always
/// finds the true shortest path — this is the empirical property
/// `test/alt_landmarks_test.dart` checks over thousands of randomised
/// hazard configurations, never rebuilding the landmarks themselves.
class AltLandmarks {
  AltLandmarks._({
    required this.landmarks,
    required this._distFrom,
    required this._distTo,
  });

  /// Builds landmark distance tables for [landmarkNodes] over [graph]'s
  /// free-flow metric. Two single-source Dijkstra runs per landmark (one
  /// forward, one on the reversed graph) — `O(k · (V + E) log V)` for `k`
  /// landmarks, run once regardless of how many hazard configurations are
  /// later queried against it.
  factory AltLandmarks.build({
    required CsrGraph graph,
    required List<int> landmarkNodes,
  }) {
    assert(landmarkNodes.isNotEmpty, 'at least one landmark is required');
    final distFrom = <List<double>>[];
    final distTo = <List<double>>[];
    for (final l in landmarkNodes) {
      distFrom.add(
        _singleSourceFreeFlowDistances(graph: graph, source: l, forward: true),
      );
      distTo.add(
        _singleSourceFreeFlowDistances(graph: graph, source: l, forward: false),
      );
    }
    return AltLandmarks._(
      landmarks: List.unmodifiable(landmarkNodes),
      distFrom: distFrom,
      distTo: distTo,
    );
  }

  /// The chosen landmark node ids, in the order their distance tables are
  /// stored.
  final List<int> landmarks;

  /// `_distFrom[i][v]` — free-flow shortest distance from landmark `i` to
  /// node `v`.
  final List<List<double>> _distFrom;

  /// `_distTo[i][v]` — free-flow shortest distance from node `v` to
  /// landmark `i`.
  final List<List<double>> _distTo;

  /// A lower bound on the remaining shortest-path cost from [node] to
  /// [target], valid under **any** hazard-aware cost function satisfying
  /// `w_λ(e,t) ≥ τ₀(e,t)` (see this class's doc comment). Always `≥ 0`.
  double potential(int node, int target) {
    var best = 0.0;
    for (var i = 0; i < landmarks.length; i++) {
      final viaTo = _distTo[i][node] - _distTo[i][target];
      final viaFrom = _distFrom[i][target] - _distFrom[i][node];
      if (viaTo > best) best = viaTo;
      if (viaFrom > best) best = viaFrom;
    }
    return best;
  }
}

/// Finds the shortest [source]-to-[target] path over [graph] under
/// time-varying [edgeCost], using A* guided by [landmarks]'s potential.
///
/// Because the potential is consistent under any admissible hazard cost
/// (see [AltLandmarks]), a node is never re-expanded once settled, and the
/// result is always the true shortest path — identical in cost to
/// [bidirectionalDijkstra] run with the same [edgeCost]. Returns `null` if
/// [target] is unreachable.
RouteResult? aStarWithLandmarks({
  required CsrGraph graph,
  required int source,
  required int target,
  required EdgeCostFn edgeCost,
  required AltLandmarks landmarks,
}) {
  if (source == target) {
    return RouteResult(totalCostSeconds: 0, nodePath: [source], edgePath: []);
  }

  final dist = <int, double>{source: 0};
  final prevNode = <int, int>{};
  final prevEdge = <int, int>{};
  final settled = <int>{};

  final queue = HeapPriorityQueue<(int node, double priority)>(
    (a, b) => a.$2.compareTo(b.$2),
  )..add((source, landmarks.potential(source, target)));

  while (queue.isNotEmpty) {
    final (u, priority) = queue.removeFirst();
    if (settled.contains(u)) continue;
    if (priority > dist[u]! + landmarks.potential(u, target)) continue; // stale
    settled.add(u);
    if (u == target) break; // consistent heuristic: this distance is final

    for (var i = 0; i < graph.outDegree(u); i++) {
      final edge = graph.outEdge(u, i);
      final cost = edgeCost(edge);
      if (cost == null) continue;
      if (!(cost >= 0)) {
        throw ArgumentError.value(
          cost,
          'edgeCost(edge)',
          'must be non-negative for A* (edge ${edge.edgeId})',
        );
      }

      final nd = dist[u]! + cost;
      final existing = dist[edge.to];
      if (existing != null && existing <= nd) continue;

      dist[edge.to] = nd;
      prevNode[edge.to] = u;
      prevEdge[edge.to] = edge.edgeId;
      queue.add((edge.to, nd + landmarks.potential(edge.to, target)));
    }
  }

  if (!settled.contains(target)) return null;

  final reversedNodePath = <int>[target];
  final reversedEdgePath = <int>[];
  var cursor = target;
  while (cursor != source) {
    reversedEdgePath.add(prevEdge[cursor]!);
    cursor = prevNode[cursor]!;
    reversedNodePath.add(cursor);
  }

  return RouteResult(
    totalCostSeconds: dist[target]!,
    nodePath: reversedNodePath.reversed.toList(),
    edgePath: reversedEdgePath.reversed.toList(),
  );
}
