/// Spatial lookup over the map pack: the nearest drivable node to a point (for
/// route endpoints) and the edges within a radius of a point (for attaching a
/// report to the road network).
///
/// This is the missing piece KNOWN_FLAWS F-06 names ("no code that snaps a new
/// report to an edge") and the on-device half of F-02: a report is attached to
/// **every** edge within a radius, so both directions of a two-way street get
/// it, each with its own distance. Pure Dart, no I/O.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pulse_router/src/map_pack.dart';

/// One edge found near a query point.
class EdgeMatch {
  /// Creates a match.
  const EdgeMatch({required this.edgeId, required this.distanceM});

  /// The edge's id (its index in the pack).
  final int edgeId;

  /// Distance from the query point to the edge's segment, metres.
  final double distanceM;
}

/// Uniform-grid index over a [MapPack]'s edge segments and nodes.
class EdgeSnapper {
  /// Builds the index. About 0.4 s on a desktop for the 471k-edge Chennai
  /// pack; [cellDegrees] of 0.002 is roughly 220 m.
  EdgeSnapper(this.pack, {this.cellDegrees = 0.002}) {
    var minLat = double.infinity;
    var minLon = double.infinity;
    var maxLat = -double.infinity;
    var maxLon = -double.infinity;
    for (var i = 0; i < pack.nodeCount; i++) {
      minLat = math.min(minLat, pack.nodeLat[i]);
      maxLat = math.max(maxLat, pack.nodeLat[i]);
      minLon = math.min(minLon, pack.nodeLon[i]);
      maxLon = math.max(maxLon, pack.nodeLon[i]);
    }
    _minLat = minLat;
    _minLon = minLon;
    _rows = ((maxLat - minLat) / cellDegrees).floor() + 1;
    _cols = ((maxLon - minLon) / cellDegrees).floor() + 1;
    _refLat = (minLat + maxLat) / 2;
    _metresPerDegLon = 111320 * math.cos(_refLat * math.pi / 180);

    _buildEdgeGrid();
    _buildNodeGrid();
    _seenStamp = Int32List(pack.edgeCount);
  }

  /// The pack this index covers.
  final MapPack pack;

  /// Grid cell size in degrees.
  final double cellDegrees;

  static const double _metresPerDegLat = 110574;

  late final double _minLat;
  late final double _minLon;
  late final int _rows;
  late final int _cols;
  late final double _refLat;
  late final double _metresPerDegLon;

  late final Int32List _edgeCellStart;
  late final Int32List _edgeCellItems;
  late final Int32List _nodeCellStart;
  late final Int32List _nodeCellItems;
  late final Int32List _seenStamp;
  var _stamp = 0;

  /// The approximate coverage box `(minLat, minLon, maxLat, maxLon)`.
  ({double minLat, double minLon, double maxLat, double maxLon}) get bounds => (
    minLat: _minLat,
    minLon: _minLon,
    maxLat: _minLat + _rows * cellDegrees,
    maxLon: _minLon + _cols * cellDegrees,
  );

  int _row(double lat) => ((lat - _minLat) / cellDegrees).floor();
  int _col(double lon) => ((lon - _minLon) / cellDegrees).floor();

  void _buildEdgeGrid() {
    final cells = _rows * _cols;
    final counts = Int32List(cells + 1);
    // Pass 1: count how many cells each edge's bounding box touches.
    void forEachCell(int e, void Function(int cell) visit) {
      final a = pack.edgeFrom[e];
      final b = pack.edgeTo[e];
      final r0 = _row(math.min(pack.nodeLat[a], pack.nodeLat[b]));
      final r1 = _row(math.max(pack.nodeLat[a], pack.nodeLat[b]));
      final c0 = _col(math.min(pack.nodeLon[a], pack.nodeLon[b]));
      final c1 = _col(math.max(pack.nodeLon[a], pack.nodeLon[b]));
      for (var r = r0; r <= r1; r++) {
        for (var c = c0; c <= c1; c++) {
          visit(r * _cols + c);
        }
      }
    }

    for (var e = 0; e < pack.edgeCount; e++) {
      forEachCell(e, (cell) => counts[cell + 1]++);
    }
    for (var i = 0; i < cells; i++) {
      counts[i + 1] += counts[i];
    }
    _edgeCellStart = counts;
    final cursor = Int32List.fromList(counts);
    _edgeCellItems = Int32List(counts[cells]);
    for (var e = 0; e < pack.edgeCount; e++) {
      forEachCell(e, (cell) => _edgeCellItems[cursor[cell]++] = e);
    }
  }

  void _buildNodeGrid() {
    final cells = _rows * _cols;
    final counts = Int32List(cells + 1);
    for (var n = 0; n < pack.nodeCount; n++) {
      counts[_row(pack.nodeLat[n]) * _cols + _col(pack.nodeLon[n]) + 1]++;
    }
    for (var i = 0; i < cells; i++) {
      counts[i + 1] += counts[i];
    }
    _nodeCellStart = counts;
    final cursor = Int32List.fromList(counts);
    _nodeCellItems = Int32List(pack.nodeCount);
    for (var n = 0; n < pack.nodeCount; n++) {
      final cell = _row(pack.nodeLat[n]) * _cols + _col(pack.nodeLon[n]);
      _nodeCellItems[cursor[cell]++] = n;
    }
  }

  double _xMetres(double lon) => (lon - _minLon) * _metresPerDegLon;
  double _yMetres(double lat) => (lat - _minLat) * _metresPerDegLat;

  /// Great-circle-free local distance in metres between two lat/lon points;
  /// accurate to well under 1% over a city.
  double distanceMetres(double lat1, double lon1, double lat2, double lon2) {
    final dx = (lon2 - lon1) * _metresPerDegLon;
    final dy = (lat2 - lat1) * _metresPerDegLat;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _pointToEdge(double lat, double lon, int e) {
    final a = pack.edgeFrom[e];
    final b = pack.edgeTo[e];
    final px = _xMetres(lon);
    final py = _yMetres(lat);
    final ax = _xMetres(pack.nodeLon[a]);
    final ay = _yMetres(pack.nodeLat[a]);
    final bx = _xMetres(pack.nodeLon[b]);
    final by = _yMetres(pack.nodeLat[b]);
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    final ex = px - cx;
    final ey = py - cy;
    return math.sqrt(ex * ex + ey * ey);
  }

  /// Edges whose segment lies within [radiusM] metres of the point, nearest
  /// first, at most [limit] of them. Both directions of a two-way street are
  /// returned (they share the same segment), each with the same distance.
  List<EdgeMatch> edgesNear(
    double lat,
    double lon, {
    double radiusM = 75,
    int limit = 24,
  }) {
    if (!(radiusM > 0) || limit <= 0) return const [];
    final dLat = radiusM / _metresPerDegLat;
    final dLon = radiusM / _metresPerDegLon;
    final r0 = math.max(0, _row(lat - dLat));
    final r1 = math.min(_rows - 1, _row(lat + dLat));
    final c0 = math.max(0, _col(lon - dLon));
    final c1 = math.min(_cols - 1, _col(lon + dLon));
    if (r0 > r1 || c0 > c1) return const [];

    _stamp++;
    final found = <EdgeMatch>[];
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        final cell = r * _cols + c;
        for (var i = _edgeCellStart[cell]; i < _edgeCellStart[cell + 1]; i++) {
          final e = _edgeCellItems[i];
          if (_seenStamp[e] == _stamp) continue;
          _seenStamp[e] = _stamp;
          final d = _pointToEdge(lat, lon, e);
          if (d <= radiusM) found.add(EdgeMatch(edgeId: e, distanceM: d));
        }
      }
    }
    found.sort((a, b) {
      final byDistance = a.distanceM.compareTo(b.distanceM);
      return byDistance != 0 ? byDistance : a.edgeId.compareTo(b.edgeId);
    });
    return found.length > limit ? found.sublist(0, limit) : found;
  }

  /// The nearest node to the point for which [accept] is true (default: any),
  /// searching outwards up to [maxM] metres. `null` if none.
  int? nearestNode(
    double lat,
    double lon, {
    double maxM = 1500,
    bool Function(int node)? accept,
  }) {
    final r = _row(lat);
    final c = _col(lon);
    final maxRing = (maxM / (cellDegrees * _metresPerDegLat)).ceil() + 1;
    final cellMetres =
        cellDegrees * math.min(_metresPerDegLat, _metresPerDegLon);
    int? best;
    var bestD = double.infinity;
    for (var ring = 0; ring <= maxRing; ring++) {
      // Every node in a ring beyond the best so far is at least
      // (ring - 1) cells away, so once that exceeds bestD we are done.
      if (best != null && (ring - 1) * cellMetres > bestD) break;
      for (var rr = r - ring; rr <= r + ring; rr++) {
        if (rr < 0 || rr >= _rows) continue;
        final onEdgeRow = rr == r - ring || rr == r + ring;
        for (var cc = c - ring; cc <= c + ring; cc++) {
          if (cc < 0 || cc >= _cols) continue;
          if (!onEdgeRow && cc != c - ring && cc != c + ring) continue;
          final cell = rr * _cols + cc;
          for (
            var i = _nodeCellStart[cell];
            i < _nodeCellStart[cell + 1];
            i++
          ) {
            final n = _nodeCellItems[i];
            if (accept != null && !accept(n)) continue;
            final d = distanceMetres(
              lat,
              lon,
              pack.nodeLat[n],
              pack.nodeLon[n],
            );
            if (d < bestD) {
              bestD = d;
              best = n;
            }
          }
        }
      }
    }
    return best != null && bestD <= maxM ? best : null;
  }
}
