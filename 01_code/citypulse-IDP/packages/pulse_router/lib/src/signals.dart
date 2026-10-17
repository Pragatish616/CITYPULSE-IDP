/// Traffic signals for the route facts (C8): OpenStreetMap `highway=traffic_signals` points from the CityPulse places layer, snapped to
/// graph nodes. The router counts the signal nodes a route goes through (`routeSignalFact` in query_orchestrator.dart).
///
/// This is a count, not a delay: OpenStreetMap does not carry signal timing, and Chennai's signal coverage in OpenStreetMap is
/// incomplete, so a route with no counted signal may still have some. Learning waits from traces is `ml/signal_timing/`.
library;

import 'dart:convert';

import 'package:pulse_router/src/edge_snapper.dart';

/// The signal points (lat, lon) in a places-layer file (`scripts/extract_osm_places.py`, version 1): rows of
/// `[lat, lon, category, name, kind, name_ta]` whose category id is `signal`.
List<(double, double)> parseSignalPoints(String poiJson) {
  final doc = jsonDecode(poiJson);
  if (doc is! Map) throw const FormatException('places layer: not an object');
  final cats = doc['categories'];
  final rows = doc['places'];
  if (cats is! List || rows is! List) {
    throw const FormatException('places layer: categories or places missing');
  }
  final signal = cats.indexWhere((c) => c is Map && c['id'] == 'signal');
  if (signal < 0) return const [];
  return [
    for (final r in rows)
      if (r is List && r.length >= 3 && r[2] == signal && r[0] is num && r[1] is num)
        ((r[0] as num).toDouble(), (r[1] as num).toDouble()),
  ];
}

/// The graph nodes nearest to [points], each within [maxM] metres (a signal tagged on a way's node is on the road, so 30 m is ample).
/// Points farther than that from any node (outside the pack, or on a road the pack leaves out) are dropped.
Set<int> snapSignals(List<(double, double)> points, EdgeSnapper snapper, {double maxM = 30}) => {
      for (final (lat, lon) in points) ?snapper.nearestNode(lat, lon, maxM: maxM),
    };
