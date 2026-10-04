import 'dart:typed_data';

/// One directed road segment as given to [CsrGraph.build].
///
/// `edgeId` is carried through unchanged so the router can look up
/// time-varying hazard cost for this specific edge (via a caller-supplied
/// cost function) and so a later `DecisionTrace` (T2.2) can cite it. A
/// two-way street is two `GraphEdgeInput`s, one per direction — this package
/// never infers directionality, the graph builder (T1.3/T3.1) does.
///
/// **Validation here is deliberately still `assert`-only (2026-09 security
/// review).** Unlike `pulse_belief`'s `WeightedObservation` — populated
/// directly from untrusted, network-derived crowd reports
/// (`docs/CONTRACTS.md` §1) — this class is currently only ever constructed
/// from the OSM graph-build pipeline (T1.3), a controlled, trusted source,
/// so `assert` being stripped in release is a smaller exposure than at that
/// boundary. Revisit with the same real-check treatment if road-graph edges
/// are ever accepted from untrusted input directly (e.g. a crowd-sourced
/// map-edit feature).
class GraphEdgeInput {
  /// Creates one directed edge from [from] to [to].
  const GraphEdgeInput({
    required this.edgeId,
    required this.from,
    required this.to,
    required this.freeFlowSeconds,
    required this.freeFlowKmh,
  }) : assert(edgeId >= 0, 'edgeId must be non-negative: got $edgeId'),
       assert(from >= 0, 'from must be non-negative: got $from'),
       assert(to >= 0, 'to must be non-negative: got $to'),
       assert(
         freeFlowSeconds > 0,
         'freeFlowSeconds (tau_0) must be positive: got $freeFlowSeconds',
       ),
       assert(
         freeFlowKmh > 0,
         'freeFlowKmh (v_free) must be positive: got $freeFlowKmh',
       );

  /// Stable id for this edge, e.g. into `EdgeBelief.edge_id`
  /// (`docs/CONTRACTS.md` §2). Not required to equal its index in any array.
  final int edgeId;

  /// Source node id, `0 <= from < nodeCount`.
  final int from;

  /// Target node id, `0 <= to < nodeCount`.
  final int to;

  /// `τ₀` — free-flow (or time-of-day) travel time in seconds.
  final double freeFlowSeconds;

  /// `v_free(e)` — free-flow speed in km/h. Needed by the Pregnolato
  /// depth-disruption slowdown `δ` (`docs/DECISIONS.md` ADR-003).
  final double freeFlowKmh;
}

/// A road network as a CSR (compressed sparse row) adjacency, built once from
/// a plain edge list.
///
/// Holds **both** the forward adjacency (outgoing edges per node) and the
/// backward adjacency (incoming edges per node, i.e. the forward adjacency of
/// the reversed graph) — bidirectional Dijkstra needs to walk both directions
/// without materialising a second copy of the graph.
///
/// This is a pure in-memory structure with no I/O: parsing OSM data into a
/// `List<GraphEdgeInput>` is the caller's job (T1.3).
class CsrGraph {
  /// Builds a [CsrGraph] over node ids `0 .. nodeCount - 1` from a flat list
  /// of directed [edges]. Two counting-sort passes (forward by `from`,
  /// backward by `to`) — `O(nodeCount + edges.length)`, no comparison sort.
  factory CsrGraph.build({
    required int nodeCount,
    required List<GraphEdgeInput> edges,
  }) {
    assert(nodeCount >= 0, 'nodeCount must be non-negative: got $nodeCount');
    for (final e in edges) {
      assert(
        e.from < nodeCount && e.to < nodeCount,
        'edge ${e.edgeId} references a node >= nodeCount ($nodeCount): '
        'from=${e.from}, to=${e.to}',
      );
    }

    final fwd = _buildDirection(
      nodeCount: nodeCount,
      edges: edges,
      keyOf: (e) => e.from,
      otherOf: (e) => e.to,
    );
    final bwd = _buildDirection(
      nodeCount: nodeCount,
      edges: edges,
      keyOf: (e) => e.to,
      otherOf: (e) => e.from,
    );

    return CsrGraph._(
      nodeCount: nodeCount,
      fwdRowPtr: fwd.rowPtr,
      fwdTarget: fwd.other,
      fwdEdgeId: fwd.edgeId,
      fwdFreeFlowSeconds: fwd.freeFlowSeconds,
      fwdFreeFlowKmh: fwd.freeFlowKmh,
      bwdRowPtr: bwd.rowPtr,
      bwdSource: bwd.other,
      bwdEdgeId: bwd.edgeId,
      bwdFreeFlowSeconds: bwd.freeFlowSeconds,
      bwdFreeFlowKmh: bwd.freeFlowKmh,
    );
  }

  /// Builds a [CsrGraph] straight from parallel arrays, without allocating one
  /// [GraphEdgeInput] per edge. Used for the binary map pack (PLAN.md M2.1),
  /// where this is the difference between ~0.2 s and ~1 s on a mid-range
  /// phone for the 471,240-edge Chennai graph. The arrays come from a file,
  /// so every value is checked with a real (non-`assert`) test.
  ///
  /// [edgeId] defaults to the array index.
  factory CsrGraph.fromArrays({
    required int nodeCount,
    required List<int> from,
    required List<int> to,
    required List<double> freeFlowSeconds,
    required List<double> freeFlowKmh,
    List<int>? edgeId,
  }) {
    final n = from.length;
    if (to.length != n ||
        freeFlowSeconds.length != n ||
        freeFlowKmh.length != n ||
        (edgeId != null && edgeId.length != n)) {
      throw ArgumentError('edge arrays must all have the same length');
    }
    if (nodeCount < 0) {
      throw ArgumentError.value(nodeCount, 'nodeCount', 'must be >= 0');
    }
    for (var i = 0; i < n; i++) {
      if (!(from[i] >= 0 && from[i] < nodeCount) ||
          !(to[i] >= 0 && to[i] < nodeCount)) {
        throw ArgumentError(
          'edge $i references a node outside [0, $nodeCount)',
        );
      }
      if (!(freeFlowSeconds[i] > 0) || !(freeFlowKmh[i] > 0)) {
        throw ArgumentError(
          'edge $i has a non-positive free-flow time or speed',
        );
      }
    }

    _CsrDirection build(List<int> keys, List<int> others) {
      final rowPtr = Int32List(nodeCount + 1);
      for (var i = 0; i < n; i++) {
        rowPtr[keys[i] + 1]++;
      }
      for (var i = 0; i < nodeCount; i++) {
        rowPtr[i + 1] += rowPtr[i];
      }
      final cursor = Int32List.fromList(rowPtr);
      final other = Int32List(n);
      final ids = Int32List(n);
      final seconds = Float64List(n);
      final kmh = Float64List(n);
      for (var i = 0; i < n; i++) {
        final slot = cursor[keys[i]]++;
        other[slot] = others[i];
        ids[slot] = edgeId == null ? i : edgeId[i];
        seconds[slot] = freeFlowSeconds[i];
        kmh[slot] = freeFlowKmh[i];
      }
      return _CsrDirection(
        rowPtr: rowPtr,
        other: other,
        edgeId: ids,
        freeFlowSeconds: seconds,
        freeFlowKmh: kmh,
      );
    }

    final fwd = build(from, to);
    final bwd = build(to, from);
    return CsrGraph._(
      nodeCount: nodeCount,
      fwdRowPtr: fwd.rowPtr,
      fwdTarget: fwd.other,
      fwdEdgeId: fwd.edgeId,
      fwdFreeFlowSeconds: fwd.freeFlowSeconds,
      fwdFreeFlowKmh: fwd.freeFlowKmh,
      bwdRowPtr: bwd.rowPtr,
      bwdSource: bwd.other,
      bwdEdgeId: bwd.edgeId,
      bwdFreeFlowSeconds: bwd.freeFlowSeconds,
      bwdFreeFlowKmh: bwd.freeFlowKmh,
    );
  }

  CsrGraph._({
    required this.nodeCount,
    required this._fwdRowPtr,
    required this._fwdTarget,
    required this._fwdEdgeId,
    required this._fwdFreeFlowSeconds,
    required this._fwdFreeFlowKmh,
    required this._bwdRowPtr,
    required this._bwdSource,
    required this._bwdEdgeId,
    required this._bwdFreeFlowSeconds,
    required this._bwdFreeFlowKmh,
  });

  /// Number of nodes, ids `0 .. nodeCount - 1`.
  final int nodeCount;

  final List<int> _fwdRowPtr; // length nodeCount + 1
  final List<int> _fwdTarget; // length edgeCount
  final List<int> _fwdEdgeId;
  final List<double> _fwdFreeFlowSeconds;
  final List<double> _fwdFreeFlowKmh;

  final List<int> _bwdRowPtr; // length nodeCount + 1
  final List<int> _bwdSource; // length edgeCount -- the 'from' of that edge
  final List<int> _bwdEdgeId;
  final List<double> _bwdFreeFlowSeconds;
  final List<double> _bwdFreeFlowKmh;

  static _CsrDirection _buildDirection({
    required int nodeCount,
    required List<GraphEdgeInput> edges,
    required int Function(GraphEdgeInput) keyOf,
    required int Function(GraphEdgeInput) otherOf,
  }) {
    final rowPtr = List<int>.filled(nodeCount + 1, 0);
    for (final e in edges) {
      rowPtr[keyOf(e) + 1]++;
    }
    for (var i = 0; i < nodeCount; i++) {
      rowPtr[i + 1] += rowPtr[i];
    }

    final cursor = List<int>.from(rowPtr);
    final other = List<int>.filled(edges.length, 0);
    final edgeId = List<int>.filled(edges.length, 0);
    final freeFlowSeconds = List<double>.filled(edges.length, 0);
    final freeFlowKmh = List<double>.filled(edges.length, 0);

    for (final e in edges) {
      final slot = cursor[keyOf(e)]++;
      other[slot] = otherOf(e);
      edgeId[slot] = e.edgeId;
      freeFlowSeconds[slot] = e.freeFlowSeconds;
      freeFlowKmh[slot] = e.freeFlowKmh;
    }

    return _CsrDirection(
      rowPtr: rowPtr,
      other: other,
      edgeId: edgeId,
      freeFlowSeconds: freeFlowSeconds,
      freeFlowKmh: freeFlowKmh,
    );
  }

  void _checkNode(int node) {
    assert(
      node >= 0 && node < nodeCount,
      'node out of range [0, $nodeCount): got $node',
    );
  }

  /// Number of outgoing edges from [node].
  int outDegree(int node) {
    _checkNode(node);
    return _fwdRowPtr[node + 1] - _fwdRowPtr[node];
  }

  /// The [i]th outgoing edge from [node], `0 <= i < outDegree(node)`.
  RouteEdge outEdge(int node, int i) {
    _checkNode(node);
    final slot = _fwdRowPtr[node] + i;
    assert(slot < _fwdRowPtr[node + 1], 'index $i out of range for node $node');
    return RouteEdge(
      edgeId: _fwdEdgeId[slot],
      from: node,
      to: _fwdTarget[slot],
      freeFlowSeconds: _fwdFreeFlowSeconds[slot],
      freeFlowKmh: _fwdFreeFlowKmh[slot],
    );
  }

  /// Number of incoming edges to [node] — i.e. outgoing edges of [node] in
  /// the reversed graph, used by the backward half of a bidirectional search.
  int inDegree(int node) {
    _checkNode(node);
    return _bwdRowPtr[node + 1] - _bwdRowPtr[node];
  }

  /// The [i]th incoming edge to [node], `0 <= i < inDegree(node)`. Still
  /// oriented `from -> to` in the *original* graph — the backward search
  /// walks `to`'s in-edges but must relax costs in the forward sense.
  RouteEdge inEdge(int node, int i) {
    _checkNode(node);
    final slot = _bwdRowPtr[node] + i;
    assert(slot < _bwdRowPtr[node + 1], 'index $i out of range for node $node');
    return RouteEdge(
      edgeId: _bwdEdgeId[slot],
      from: _bwdSource[slot],
      to: node,
      freeFlowSeconds: _bwdFreeFlowSeconds[slot],
      freeFlowKmh: _bwdFreeFlowKmh[slot],
    );
  }
}

class _CsrDirection {
  const _CsrDirection({
    required this.rowPtr,
    required this.other,
    required this.edgeId,
    required this.freeFlowSeconds,
    required this.freeFlowKmh,
  });

  final List<int> rowPtr;
  final List<int> other;
  final List<int> edgeId;
  final List<double> freeFlowSeconds;
  final List<double> freeFlowKmh;
}

/// One directed edge as returned by [CsrGraph.outEdge] / [CsrGraph.inEdge],
/// always oriented `from -> to` regardless of which side of the search
/// found it.
class RouteEdge {
  /// Creates a [RouteEdge] view over one directed edge's static data.
  const RouteEdge({
    required this.edgeId,
    required this.from,
    required this.to,
    required this.freeFlowSeconds,
    required this.freeFlowKmh,
  });

  /// Matches the `edgeId` this edge was built from.
  final int edgeId;

  /// Source node id.
  final int from;

  /// Target node id.
  final int to;

  /// `τ₀` in seconds.
  final double freeFlowSeconds;

  /// `v_free(e)` in km/h.
  final double freeFlowKmh;
}
