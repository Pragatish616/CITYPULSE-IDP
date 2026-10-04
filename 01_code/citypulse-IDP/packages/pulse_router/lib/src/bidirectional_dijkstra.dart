import 'package:collection/collection.dart';

import 'package:pulse_router/src/csr_graph.dart';

/// The per-edge, time-of-query cost — `w_λ(e,t)` from `edgeCost`
/// (`docs/DECISIONS.md` ADR-003), or `null` if the chance constraint removes
/// the edge outright. Never a large finite weight for a removed edge.
typedef EdgeCostFn = double? Function(RouteEdge edge);

/// A found shortest path: node ids `source .. target` inclusive, and the
/// edge ids used to traverse them (`edgePath.length == nodePath.length - 1`).
class RouteResult {
  /// Creates a [RouteResult] directly. Normally produced by
  /// [bidirectionalDijkstra].
  const RouteResult({
    required this.totalCostSeconds,
    required this.nodePath,
    required this.edgePath,
  });

  /// Total cost in seconds, summing each edge's [EdgeCostFn] value.
  final double totalCostSeconds;

  /// Node ids visited, `nodePath.first == source`, `nodePath.last == target`.
  final List<int> nodePath;

  /// Edge ids used, in traversal order.
  final List<int> edgePath;
}

class _QueueEntry {
  const _QueueEntry(this.node, this.dist);
  final int node;
  final double dist;
}

/// One direction's Dijkstra state — forward and backward are identical in
/// shape, just walking [CsrGraph.outEdge] vs [CsrGraph.inEdge].
class _Side {
  _Side(int source) {
    dist[source] = 0;
    queue.add(_QueueEntry(source, 0));
  }

  final Map<int, double> dist = {};
  final Map<int, int> prevNode = {};
  final Map<int, int> prevEdge = {};
  final Set<int> settled = {};
  final HeapPriorityQueue<_QueueEntry> queue = HeapPriorityQueue(
    (a, b) => a.dist.compareTo(b.dist),
  );

  /// Discards stale (already-settled or superseded) entries from the front
  /// of the queue and returns the next valid minimum distance, or `null` if
  /// nothing valid remains.
  double? peekValidTop() {
    while (queue.isNotEmpty) {
      final top = queue.first;
      if (settled.contains(top.node) || top.dist > dist[top.node]!) {
        queue.removeFirst();
        continue;
      }
      return top.dist;
    }
    return null;
  }
}

/// Finds the shortest [source]-to-[target] path over [graph] under
/// time-varying edge costs from [edgeCost], via bidirectional Dijkstra
/// (`docs/IMPLEMENTATION_PLAN.md` T2.1). Returns `null` if [target] is
/// unreachable from [source] (including through edges removed by the chance
/// constraint).
///
/// **On the early-termination bound.** The standard `topF + topB >= best`
/// stopping rule is applied whenever *both* frontiers are still active. If
/// one side's queue drains first — everything reachable from it is already
/// settled with final distances — the other side keeps expanding alone,
/// checking its own top against `best`, since a settled side's fixed
/// distances can still combine with the active side's *future* relaxations
/// to beat the current best. Substituting `+infinity` for a drained side's
/// top and applying the two-sided bound anyway is the classic bug here: it
/// stops the active side before it has had a chance to relax into the other
/// side's already-final nodes.
///
/// **`edgeCost` must return a non-negative, non-`NaN` value or `null`** —
/// enforced with a real, non-strippable check at each call, not an
/// assertion. A 2026-09 security review found that a `NaN` cost (reachable
/// from a corrupted/adversarial hazard observation flowing through
/// `edgeCost()` in `edge_cost.dart`) previously defeated `relax`'s
/// monotonic-improvement guard silently: `existing <= candidateDist` is
/// `false` for a `NaN` `candidateDist`, so the guard never blocks it, and
/// once a node's distance is poisoned to `NaN` a later, worse-but-finite
/// distance can silently overwrite what had been correct — no crash, just a
/// wrong route. Throwing here instead converts that into an immediate,
/// diagnosable failure at the point of corruption.
RouteResult? bidirectionalDijkstra({
  required CsrGraph graph,
  required int source,
  required int target,
  required EdgeCostFn edgeCost,
}) {
  if (source == target) {
    return RouteResult(totalCostSeconds: 0, nodePath: [source], edgePath: []);
  }

  final fwd = _Side(source);
  final bwd = _Side(target);

  var best = double.infinity;
  int? meetNode;

  void relax(
    _Side side,
    _Side other,
    int node,
    RouteEdge edge,
    double edgeSeconds,
    int neighbor,
  ) {
    final candidateDist = side.dist[node]! + edgeSeconds;
    final existing = side.dist[neighbor];
    if (existing != null && existing <= candidateDist) return;

    side.dist[neighbor] = candidateDist;
    side.prevNode[neighbor] = node;
    side.prevEdge[neighbor] = edge.edgeId;
    side.queue.add(_QueueEntry(neighbor, candidateDist));

    final otherDist = other.dist[neighbor];
    if (otherDist != null) {
      final candidateMeet = candidateDist + otherDist;
      if (candidateMeet < best) {
        best = candidateMeet;
        meetNode = neighbor;
      }
    }
  }

  void expandForward() {
    final node = fwd.queue.removeFirst().node;
    if (fwd.settled.contains(node)) return;
    fwd.settled.add(node);
    for (var i = 0; i < graph.outDegree(node); i++) {
      final edge = graph.outEdge(node, i);
      final cost = edgeCost(edge);
      if (cost == null) continue;
      if (!(cost >= 0)) {
        throw ArgumentError.value(
          cost,
          'edgeCost(edge)',
          'must be non-negative for Dijkstra (edge ${edge.edgeId})',
        );
      }
      relax(fwd, bwd, node, edge, cost, edge.to);
    }
  }

  void expandBackward() {
    final node = bwd.queue.removeFirst().node;
    if (bwd.settled.contains(node)) return;
    bwd.settled.add(node);
    for (var i = 0; i < graph.inDegree(node); i++) {
      final edge = graph.inEdge(node, i);
      final cost = edgeCost(edge);
      if (cost == null) continue;
      if (!(cost >= 0)) {
        throw ArgumentError.value(
          cost,
          'edgeCost(edge)',
          'must be non-negative for Dijkstra (edge ${edge.edgeId})',
        );
      }
      relax(bwd, fwd, node, edge, cost, edge.from);
    }
  }

  while (true) {
    final topF = fwd.peekValidTop();
    final topB = bwd.peekValidTop();
    if (topF == null && topB == null) break;

    if (topF != null && topB != null) {
      if (topF + topB >= best) break;
      if (topF <= topB) {
        expandForward();
      } else {
        expandBackward();
      }
    } else if (topF != null) {
      if (topF >= best) break;
      expandForward();
    } else {
      if (topB! >= best) break;
      expandBackward();
    }
  }

  final finalMeetNode = meetNode;
  if (finalMeetNode == null) return null;

  final reversedNodePath = <int>[finalMeetNode];
  final reversedEdgePathForward = <int>[];
  var cursor = finalMeetNode;
  while (cursor != source) {
    reversedEdgePathForward.add(fwd.prevEdge[cursor]!);
    cursor = fwd.prevNode[cursor]!;
    reversedNodePath.add(cursor);
  }
  // `.reversed` is a lazy view over the same list -- materialise with
  // `.toList()` before reusing the name, rather than `setAll(0, x.reversed)`,
  // which reads and writes the same backing list at once.
  final nodePath = reversedNodePath.reversed.toList();
  final edgePathForward = reversedEdgePathForward.reversed.toList();

  final edgePathBackward = <int>[];
  cursor = finalMeetNode;
  while (cursor != target) {
    final edgeId = bwd.prevEdge[cursor]!;
    cursor = bwd.prevNode[cursor]!;
    edgePathBackward.add(edgeId);
    nodePath.add(cursor);
  }

  return RouteResult(
    totalCostSeconds: best,
    nodePath: nodePath,
    edgePath: [...edgePathForward, ...edgePathBackward],
  );
}
