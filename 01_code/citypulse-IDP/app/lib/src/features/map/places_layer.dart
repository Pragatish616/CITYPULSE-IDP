/// The CityPulse places layer: shops, schools, hospitals, police and fire stations, bus stands, stations, temples, landmarks,
/// parks, banks, fuel, public services and traffic signals, drawn over the base map when zoomed in to street level.
///
/// The points come from OpenStreetMap (ODbL), extracted by `scripts/extract_osm_places.py` and bundled as
/// `assets/data/places_poi.json`. They describe what is there, never the state of a road: a place on the map says nothing about
/// whether a street is flooded or passable (ADR-011).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:citypulse_app/src/domain/models.dart' show GeoBounds;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse_router/pulse_router.dart';

/// Places are drawn from this zoom up (street level); below it they would clutter the city view.
const double kPlacesMinZoom = 14;

/// Between [kPlacesMinZoom] and this zoom only the main kinds are drawn; shops, food, banks and signals join from here up.
const double kPlacesAllZoom = 15.5;

/// The most points sent to the map at once, so the map stays smooth.
const int kPlacesMaxShown = 1500;

/// Colour for each category id, as a `#RRGGBB` string (the map engines take strings).
const Map<String, String> kPlaceColours = {
  'education': '#3949AB',
  'health': '#E53935',
  'police': '#0D47A1',
  'fire': '#BF360C',
  'bus': '#00897B',
  'rail': '#37474F',
  'worship': '#F9A825',
  'landmark': '#8D6E63',
  'park': '#7CB342',
  'shop': '#D81B60',
  'food': '#8E24AA',
  'money': '#1E88E5',
  'fuel': '#6D4C41',
  'utility': '#78909C',
  'signal': '#212121',
};

/// The kinds shown only from [kPlacesAllZoom] up.
const Set<String> kDetailCategories = {'shop', 'food', 'money', 'signal'};

/// One category of the layer.
class PlaceCategory {
  /// Creates a category.
  const PlaceCategory(this.id, this.en, this.ta);

  /// Stable id, for example `police`.
  final String id;

  /// English label for the legend.
  final String en;

  /// Tamil label for the legend.
  final String ta;

  /// The category's colour as `#RRGGBB`.
  String get colour => kPlaceColours[id] ?? '#78909C';
}

/// One place.
class PlacePoint {
  /// Creates a place.
  const PlacePoint(this.lat, this.lon, this.category, this.name, this.kind, this.nameTa);

  /// Latitude.
  final double lat;

  /// Longitude.
  final double lon;

  /// Index into [PlacesLayer.categories].
  final int category;

  /// Name (English or as tagged), or empty for an unnamed kind such as a bus stop.
  final String name;

  /// What it is, for example `temple`, `bus stop`, `supermarket`.
  final String kind;

  /// Tamil name, or empty.
  final String nameTa;
}

/// The whole layer for one city.
class PlacesLayer {
  /// Creates a layer.
  const PlacesLayer(this.categories, this.places);

  /// A layer with nothing in it (a city without one, or a file that failed to load).
  static const PlacesLayer empty = PlacesLayer([], []);

  /// Reads `places_poi.json`.
  factory PlacesLayer.parse(String json) {
    final doc = jsonDecode(json) as Map<String, dynamic>;
    final cats = [
      for (final c in (doc['categories'] as List? ?? const []).cast<Map<String, dynamic>>())
        PlaceCategory(c['id'] as String, c['en'] as String, c['ta'] as String? ?? c['en'] as String),
    ];
    final places = <PlacePoint>[];
    for (final row in (doc['places'] as List? ?? const [])) {
      final r = row as List;
      final cat = (r[2] as num).toInt();
      if (cat < 0 || cat >= cats.length) continue;
      places.add(
        PlacePoint(
          (r[0] as num).toDouble(),
          (r[1] as num).toDouble(),
          cat,
          r[3] as String? ?? '',
          r.length > 4 ? r[4] as String? ?? '' : '',
          r.length > 5 ? r[5] as String? ?? '' : '',
        ),
      );
    }
    return PlacesLayer(cats, places);
  }

  /// Every category.
  final List<PlaceCategory> categories;

  /// Every place.
  final List<PlacePoint> places;

  /// The category of [p].
  PlaceCategory categoryOf(PlacePoint p) => categories[p.category];

  /// The places to draw for a map showing [bounds] at [zoom]: nothing below [kPlacesMinZoom]; the main kinds only below
  /// [kPlacesAllZoom]; at most [cap], main kinds first.
  List<PlacePoint> visible(GeoBounds bounds, double zoom, {int cap = kPlacesMaxShown}) {
    if (zoom < kPlacesMinZoom || places.isEmpty) return const [];
    final detail = zoom >= kPlacesAllZoom;
    final main = <PlacePoint>[];
    final extra = <PlacePoint>[];
    for (final p in places) {
      if (p.lat < bounds.minLat || p.lat > bounds.maxLat || p.lon < bounds.minLon || p.lon > bounds.maxLon) continue;
      if (kDetailCategories.contains(categories[p.category].id)) {
        if (detail) extra.add(p);
      } else {
        main.add(p);
      }
    }
    return [...main, ...extra].take(cap).toList();
  }

  /// A GeoJSON FeatureCollection of [points] for the map, with the label in [tamil] or English.
  String geoJson(List<PlacePoint> points, {bool tamil = false}) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final p in points)
        {
          'type': 'Feature',
          'properties': {
            'name': label(p, tamil: tamil),
            'kind': p.kind,
            'cat': categories[p.category].id,
            'colour': categories[p.category].colour,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [p.lon, p.lat],
          },
        },
    ],
  });

  /// The name to show for [p]: its name in the chosen language if it has one, else what it is.
  String label(PlacePoint p, {bool tamil = false}) {
    if (tamil && p.nameTa.isNotEmpty) return p.nameTa;
    if (p.name.isNotEmpty) return p.name;
    return p.kind;
  }

  /// The place nearest to [point] within [maxMetres], or null.
  PlacePoint? nearest(GeoPoint point, {double maxMetres = 60}) {
    PlacePoint? best;
    var bestD = maxMetres;
    final cosLat = math.cos(point.lat * math.pi / 180);
    for (final p in places) {
      final dy = (p.lat - point.lat) * 111320;
      if (dy.abs() > bestD) continue;
      final dx = (p.lon - point.lon) * 111320 * cosLat;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d <= bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }
}

/// The bundled places layer, loaded once and only when first asked for.
final placesLayerProvider = FutureProvider<PlacesLayer>((ref) async {
  try {
    return PlacesLayer.parse(await rootBundle.loadString('assets/data/places_poi.json'));
    // A missing or broken file means an empty layer, never a broken map.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return PlacesLayer.empty;
  }
});
