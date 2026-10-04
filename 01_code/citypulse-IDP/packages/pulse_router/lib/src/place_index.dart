/// Offline street search over the map pack.
///
/// The pack carries 7,808 distinct OSM street names but no coordinate per
/// name, and the same name ("Main Road", "Gandhi Road") is used in many parts
/// of Chennai, so a name is not a place. This groups the edges of each name
/// into connected *stretches* (edges that share a junction), gives each
/// stretch a representative point, and lets a caller rank results by distance
/// from the map centre. It is the offline gazetteer PLAN.md §4.2 asks for, in
/// its simplest honest form: streets only, no landmarks, no house numbers.
///
/// A region pack (ADR-020) also carries a list of named places (cities, towns,
/// villages, suburbs) from the same OpenStreetMap extract, because for a whole
/// state people search for "Madurai", not for a road. Those are searched too and
/// listed first when the name matches.
library;

import 'dart:convert';

import 'dart:math' as math;

import 'package:pulse_router/src/map_pack.dart';
import 'package:pulse_router/src/routing_engine.dart';

/// A named place that is not a street: a city, town, village or suburb.
class GazetteerEntry {
  /// Creates an entry.
  const GazetteerEntry({
    required this.name,
    required this.lat,
    required this.lon,
    required this.kind,
    this.altNames = const [],
  });

  /// The name shown.
  final String name;

  /// Latitude.
  final double lat;

  /// Longitude.
  final double lon;

  /// `city`, `town`, `village`, `suburb`, `neighbourhood` or `quarter`.
  final String kind;

  /// Other names that also match (for example the Tamil name).
  final List<String> altNames;
}

/// Parses a pack's `places.json`: `{"version": 1, "places": [[name, lat, lon, kind, alt...], ...]}`.
/// Rows that are malformed are skipped, never fatal.
List<GazetteerEntry> parseGazetteer(String json) {
  final doc = jsonDecode(json);
  final rows = doc is Map ? doc['places'] : null;
  if (rows is! List) return const [];
  final out = <GazetteerEntry>[];
  for (final row in rows) {
    if (row is! List || row.length < 4) continue;
    final name = row[0];
    final lat = row[1];
    final lon = row[2];
    final kind = row[3];
    if (name is! String || name.isEmpty || lat is! num || lon is! num || kind is! String) {
      continue;
    }
    out.add(
      GazetteerEntry(
        name: name,
        lat: lat.toDouble(),
        lon: lon.toDouble(),
        kind: kind,
        altNames: [
          for (final a in row.skip(4))
            if (a is String && a.isNotEmpty) a,
        ],
      ),
    );
  }
  return out;
}

/// One searchable stretch of a named street, or a named place.
class PlaceMatch {
  /// Creates a match.
  const PlaceMatch({
    required this.name,
    required this.point,
    required this.edgeCount,
    this.distanceMetres,
    this.kind = 'street',
    this.rank = 0,
  });

  /// -1 when the name is exactly the query, 0 when it starts with the query, 1 when it only contains its
  /// words. For merging the results of several indexes (ADR-022).
  final int rank;

  /// `street`, or the kind of place (`city`, `town`, `village`, `suburb`, `neighbourhood`, `quarter`).
  final String kind;

  /// The street's OSM name.
  final String name;

  /// A point on the stretch (the edge midpoint nearest its centre).
  final GeoPoint point;

  /// How many road segments the stretch spans; a rough size.
  final int edgeCount;

  /// Distance from the `near` point passed to [PlaceIndex.search], if any.
  final double? distanceMetres;
}

class _Stretch {
  _Stretch(this.nameIndex, this.lat, this.lon, this.edges);
  final int nameIndex;
  final double lat;
  final double lon;
  final int edges;
}

/// Search index of named street stretches.
class PlaceIndex {
  /// Builds the index (about 0.2 s for Chennai on a desktop).
  PlaceIndex(this.pack, {this.gazetteer = const []}) {
    // Union-find over edges: two edges of the same name that share a node are
    // the same stretch.
    final parent = List<int>.generate(pack.edgeCount, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    // Key = name * nodeCount + node; fits a double exactly (< 2^53).
    final firstEdgeAtNode = <int, int>{};
    for (var e = 0; e < pack.edgeCount; e++) {
      final name = pack.nameIndex[e];
      if (name == 0) continue;
      for (final node in [pack.edgeFrom[e], pack.edgeTo[e]]) {
        final key = name * pack.nodeCount + node;
        final other = firstEdgeAtNode[key];
        if (other == null) {
          firstEdgeAtNode[key] = e;
        } else {
          union(other, e);
        }
      }
    }

    final members = <int, List<int>>{};
    for (var e = 0; e < pack.edgeCount; e++) {
      if (pack.nameIndex[e] == 0) continue;
      (members[find(e)] ??= []).add(e);
    }

    double midLat(int e) =>
        (pack.nodeLat[pack.edgeFrom[e]] + pack.nodeLat[pack.edgeTo[e]]) / 2;
    double midLon(int e) =>
        (pack.nodeLon[pack.edgeFrom[e]] + pack.nodeLon[pack.edgeTo[e]]) / 2;

    for (final edges in members.values) {
      var sumLat = 0.0;
      var sumLon = 0.0;
      for (final e in edges) {
        sumLat += midLat(e);
        sumLon += midLon(e);
      }
      final cLat = sumLat / edges.length;
      final cLon = sumLon / edges.length;
      var best = edges.first;
      var bestD = double.infinity;
      for (final e in edges) {
        final d = math.pow(midLat(e) - cLat, 2) + math.pow(midLon(e) - cLon, 2);
        if (d < bestD) {
          bestD = d.toDouble();
          best = e;
        }
      }
      _stretches.add(
        _Stretch(
          pack.nameIndex[best],
          midLat(best),
          midLon(best),
          edges.length,
        ),
      );
    }
    _normalised = [for (final n in pack.names) _normalise(n)];
  }

  /// The pack searched.
  final MapPack pack;

  /// Named places searched along with the streets.
  final List<GazetteerEntry> gazetteer;

  late final List<List<String>> _gazNames = [
    for (final g in gazetteer) [_normalise(g.name), for (final a in g.altNames) _normalise(a)],
  ];

  final List<_Stretch> _stretches = [];
  late final List<String> _normalised;

  /// Number of distinct stretches indexed.
  int get stretchCount => _stretches.length;

  static String _normalise(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Order in a result list: a city before a town before a street before a suburb or neighbourhood before a
  // village, among equally good name matches. A name that is exactly the query comes before all of those.
  /// Order of kinds in a result list, lower first.
  static int tierOf(String kind) => _tier[kind] ?? 5;

  static const _tier = {
    'city': 0,
    'town': 1,
    'street': 2,
    'suburb': 3,
    'neighbourhood': 3,
    'quarter': 3,
    'village': 4,
  };

  /// Streets and places matching [query], best first: names starting with the query, then names
  /// containing every query word; within each, a city or town before a street; then nearer to [near]
  /// first when [near] is given, otherwise bigger first. At most [limit] results; fewer than two
  /// letters returns nothing.
  List<PlaceMatch> search(String query, {GeoPoint? near, int limit = 8}) {
    final q = _normalise(query);
    if (q.length < 2 || limit <= 0) return const [];
    final words = q.split(' ');

    double? distanceTo(double lat, double lon) {
      if (near == null) return null;
      final dx = (lon - near.lon) * 111320 * math.cos(near.lat * math.pi / 180);
      final dy = (lat - near.lat) * 110574;
      return math.sqrt(dx * dx + dy * dy);
    }

    // A highway number is written "NH 44", "NH-44" or "NH44"; with a digit in the query, match the
    // spaceless forms too, and not "NH 444" for "NH 44".
    final compactQ = q.replaceAll(' ', '');
    final numbered = RegExp(r'\d').hasMatch(q)
        ? RegExp(RegExp.escape(compactQ) + r'(?!\d)')
        : null;

    int? rankOf(String name) {
      if (name == q) return -1;
      if (name.startsWith(q)) return 0;
      if (words.every(name.contains)) {
        if (numbered == null) return 1;
        // Each word is somewhere in the name, but "nh" and "44" may belong to different numbers.
        return numbered.hasMatch(name.replaceAll(' ', '')) ? 1 : (words.length > 1 ? null : 1);
      }
      if (numbered != null && numbered.hasMatch(name.replaceAll(' ', ''))) return 1;
      return null;
    }

    final scored = <({PlaceMatch match, int rank, int tier, int size})>[];
    for (final s in _stretches) {
      final rank = rankOf(_normalised[s.nameIndex]);
      if (rank == null) continue;
      scored.add((
        match: PlaceMatch(
          name: pack.names[s.nameIndex],
          point: (lat: s.lat, lon: s.lon),
          edgeCount: s.edges,
          distanceMetres: distanceTo(s.lat, s.lon),
          rank: rank,
        ),
        rank: rank,
        tier: _tier['street']!,
        size: s.edges,
      ));
    }
    for (var i = 0; i < gazetteer.length; i++) {
      int? best;
      for (final n in _gazNames[i]) {
        final r = rankOf(n);
        if (r != null && (best == null || r < best)) best = r;
      }
      if (best == null) continue;
      final g = gazetteer[i];
      scored.add((
        match: PlaceMatch(
          name: g.name,
          point: (lat: g.lat, lon: g.lon),
          edgeCount: 0,
          distanceMetres: distanceTo(g.lat, g.lon),
          kind: g.kind,
          rank: best,
        ),
        rank: best,
        tier: _tier[g.kind] ?? 5,
        size: 0,
      ));
    }
    scored.sort((a, b) {
      if (a.rank != b.rank) return a.rank.compareTo(b.rank);
      if (a.tier != b.tier) return a.tier.compareTo(b.tier);
      // Within the same relevance, a local user wants the nearest match; with
      // no reference point, the longest street first.
      final da = a.match.distanceMetres;
      final db = b.match.distanceMetres;
      if (da != null && db != null) {
        final byDistance = da.compareTo(db);
        if (byDistance != 0) return byDistance;
      }
      final bySize = b.size.compareTo(a.size);
      if (bySize != 0) return bySize;
      return a.match.name.compareTo(b.match.name);
    });
    return [for (final r in scored.take(limit)) r.match];
  }
}
