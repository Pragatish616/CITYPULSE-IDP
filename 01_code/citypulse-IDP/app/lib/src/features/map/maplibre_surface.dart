/// MapLibre implementation of [MapSurfaceBuilder] (Android and web).
///
/// Basemap: the style URL from `AppConfig.mapStyleUrl` (OpenFreeMap by
/// default). Overlay layers, bottom to top: hazard map (dashed where only the
/// 2015 hazard zones speak, solid where a report exists), fastest route,
/// chosen route (white casing under blue), watchlist pins, markers.
library;

import 'dart:convert';

import 'package:citypulse_app/src/core/theme.dart';
import 'package:citypulse_app/src/features/map/map_surface.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pulse_router/pulse_router.dart';

// Line widths grow with zoom so the overlay reads as thin ribbons along the streets when the city is
// in view and as clear strokes up close, instead of one fixed width that clots into blocks where many
// short segments meet. Reported segments are always heavier than map-only ones, so the difference
// never rests on dashes or colour alone.
const List<Object> _priorWidth = [
  'interpolate',
  ['linear'],
  ['zoom'],
  10,
  0.7,
  13,
  1.6,
  15,
  3,
  17,
  5,
];
// A pale outline drawn under the overlay, slightly wider than the line, so the light orange stays
// visible on the basemap's yellow main roads.
const List<Object> _priorCasingWidth = [
  'interpolate',
  ['linear'],
  ['zoom'],
  10,
  1.6,
  13,
  2.8,
  15,
  4.4,
  17,
  6.6,
];
const List<Object> _reportedCasingWidth = [
  'interpolate',
  ['linear'],
  ['zoom'],
  10,
  2.4,
  13,
  4.4,
  15,
  6.6,
  17,
  10,
];
const List<Object> _reportedWidth = [
  'interpolate',
  ['linear'],
  ['zoom'],
  10,
  1.4,
  13,
  3,
  15,
  5,
  17,
  8,
];

/// Builds a [MapSurfaceBuilder] that draws with MapLibre using [styleUrl].
MapSurfaceBuilder maplibreSurfaceBuilder(
  String styleUrl, {
  required GeoPoint centre,
  double zoom = 11.5,
}) =>
    (context, callbacks) => MapLibreSurface(
      styleUrl: styleUrl,
      centre: centre,
      zoom: zoom,
      callbacks: callbacks,
    );

/// The MapLibre map plus its overlay layers.
class MapLibreSurface extends StatefulWidget {
  /// Creates the surface.
  const MapLibreSurface({
    required this.styleUrl,
    required this.centre,
    required this.callbacks,
    this.zoom = 11.5,
    super.key,
  });

  /// MapLibre style URL.
  final String styleUrl;

  /// Where the camera starts (the city centre).
  final GeoPoint centre;

  /// The zoom the camera starts at.
  final double zoom;

  /// Events to report.
  final MapSurfaceCallbacks callbacks;

  @override
  State<MapLibreSurface> createState() => _MapLibreSurfaceState();
}

class _MapLibreSurfaceState extends State<MapLibreSurface>
    implements MapHandle {
  MapLibreMapController? _controller;
  var _styleReady = false;

  // Latest requested state, re-applied when the style (re)loads.
  String? _risk;
  String? _watchlist;
  List<GeoPoint>? _path;
  List<GeoPoint>? _fastest;
  List<MapMarker> _markers = const [];

  static const _emptyCollection = {
    'type': 'FeatureCollection',
    'features': <Object?>[],
  };

  Map<String, dynamic> _parse(String? json) => json == null
      ? _emptyCollection
      : jsonDecode(json) as Map<String, dynamic>;

  Map<String, dynamic> _lineFeature(List<GeoPoint>? points) =>
      points == null || points.length < 2
      ? _emptyCollection
      : {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'properties': <String, dynamic>{},
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  for (final p in points) [p.lon, p.lat],
                ],
              },
            },
          ],
        };

  Map<String, dynamic> get _markerCollection => {
    'type': 'FeatureCollection',
    'features': [
      for (final m in _markers)
        {
          'type': 'Feature',
          'properties': {'kind': m.kind.name},
          'geometry': {
            'type': 'Point',
            'coordinates': [m.point.lon, m.point.lat],
          },
        },
    ],
  };

  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null) return;
    // Sources first, then layers, bottom to top.
    await c.addGeoJsonSource('risk', _parse(_risk));
    await c.addGeoJsonSource('fastest', _lineFeature(_fastest));
    await c.addGeoJsonSource('route', _lineFeature(_path));
    await c.addGeoJsonSource('watchlist', _parse(_watchlist));
    await c.addGeoJsonSource('markers', _markerCollection);

    // Hazard map. Colour by the pessimistic index; style by evidence so the
    // overlay never relies on colour alone.
    const riskColour = [
      'interpolate',
      ['linear'],
      ['get', 'p_pessimistic'],
      0.2,
      RiskPalette.riskLow,
      0.45,
      RiskPalette.riskMid,
      0.7,
      RiskPalette.riskHigh,
      0.95,
      RiskPalette.riskSevere,
    ];
    // Pale outlines first (they sit under the coloured lines), with the same dashes and filters.
    await c.addLineLayer(
      'risk',
      'risk-prior-casing',
      const LineLayerProperties(
        lineColor: '#FFFFFF',
        lineWidth: _priorCasingWidth,
        lineOpacity: 0.55,
        lineCap: 'round',
        lineJoin: 'round',
        lineDasharray: [2, 2],
      ),
      filter: const [
        '==',
        ['get', 'has_observation'],
        false,
      ],
      minzoom: kRiskMinZoom,
      enableInteraction: false,
    );
    await c.addLineLayer(
      'risk',
      'risk-reported-casing',
      const LineLayerProperties(
        lineColor: '#FFFFFF',
        lineWidth: _reportedCasingWidth,
        lineOpacity: 0.7,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: const [
        '==',
        ['get', 'has_observation'],
        true,
      ],
      minzoom: kRiskMinZoom,
      enableInteraction: false,
    );
    await c.addLineLayer(
      'risk',
      'risk-prior',
      const LineLayerProperties(
        lineColor: riskColour,
        lineWidth: _priorWidth,
        lineOpacity: 0.95,
        lineCap: 'round',
        lineJoin: 'round',
        lineDasharray: [2, 2],
      ),
      filter: const [
        '==',
        ['get', 'has_observation'],
        false,
      ],
      minzoom: kRiskMinZoom,
      enableInteraction: false,
    );
    await c.addLineLayer(
      'risk',
      'risk-reported',
      const LineLayerProperties(
        lineColor: riskColour,
        lineWidth: _reportedWidth,
        lineOpacity: 0.95,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: const [
        '==',
        ['get', 'has_observation'],
        true,
      ],
      minzoom: kRiskMinZoom,
      enableInteraction: false,
    );
    await c.addLineLayer(
      'fastest',
      'fastest-line',
      const LineLayerProperties(
        lineColor: RiskPalette.fastest,
        lineWidth: 4,
        lineDasharray: [1.5, 1.5],
        lineOpacity: 0.9,
      ),
      enableInteraction: false,
    );
    await c.addLineLayer(
      'route',
      'route-casing',
      const LineLayerProperties(
        lineColor: RiskPalette.routeCasing,
        lineWidth: 9,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await c.addLineLayer(
      'route',
      'route-line',
      const LineLayerProperties(
        lineColor: RiskPalette.route,
        lineWidth: 5.5,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    await c.addCircleLayer(
      'watchlist',
      'watchlist-pins',
      const CircleLayerProperties(
        circleColor: RiskPalette.watchlist,
        circleRadius: 5,
        circleOpacity: 0.85,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 1.5,
      ),
      enableInteraction: false,
    );
    await c.addCircleLayer(
      'markers',
      'markers-circle',
      const CircleLayerProperties(
        circleRadius: 9,
        circleColor: [
          'match',
          ['get', 'kind'],
          'origin',
          RiskPalette.origin,
          'destination',
          RiskPalette.destination,
          RiskPalette.avoided,
        ],
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
      enableInteraction: false,
    );
    _styleReady = true;
    widget.callbacks.onReady(this);
  }

  GeoPoint? _toGeo(LatLng? p) =>
      p == null ? null : (lat: p.latitude, lon: p.longitude);

  @override
  Future<void> setRisk(String? geoJson) async {
    _risk = geoJson;
    if (_styleReady)
      await _controller?.setGeoJsonSource('risk', _parse(geoJson));
  }

  @override
  Future<void> setWatchlist(String? geoJson) async {
    _watchlist = geoJson;
    if (_styleReady)
      await _controller?.setGeoJsonSource('watchlist', _parse(geoJson));
  }

  @override
  Future<void> setRoute({
    List<GeoPoint>? path,
    List<GeoPoint>? fastest,
    List<MapMarker> markers = const [],
  }) async {
    _path = path;
    _fastest = fastest;
    _markers = markers;
    final c = _controller;
    if (!_styleReady || c == null) return;
    await c.setGeoJsonSource('fastest', _lineFeature(fastest));
    await c.setGeoJsonSource('route', _lineFeature(path));
    await c.setGeoJsonSource('markers', _markerCollection);
  }

  @override
  Future<void> fit(List<GeoPoint> points) async {
    final c = _controller;
    if (c == null || points.isEmpty) return;
    var minLat = points.first.lat;
    var maxLat = minLat;
    var minLon = points.first.lon;
    var maxLon = minLon;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLon),
          northeast: LatLng(maxLat, maxLon),
        ),
        left: 48,
        right: 48,
        top: 120,
        bottom: 260,
      ),
    );
  }

  @override
  Future<MapView?> view() async {
    final c = _controller;
    final zoom = c?.cameraPosition?.zoom;
    if (c == null || zoom == null) return null;
    final b = await c.getVisibleRegion();
    return (
      bounds: (
        minLat: b.southwest.latitude,
        minLon: b.southwest.longitude,
        maxLat: b.northeast.latitude,
        maxLon: b.northeast.longitude,
      ),
      zoom: zoom,
    );
  }

  @override
  GeoPoint? cameraCenter() => _toGeo(_controller?.cameraPosition?.target);

  @override
  Future<void> flyTo(GeoPoint point, {double zoom = 15}) async {
    await _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(point.lat, point.lon), zoom),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: widget.styleUrl,
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.centre.lat, widget.centre.lon),
        zoom: widget.zoom,
      ),
      trackCameraPosition: true,
      compassEnabled: false,
      onMapCreated: (c) => _controller = c,
      onCameraIdle: widget.callbacks.onCameraIdle,
      onStyleLoadedCallback: _onStyleLoaded,
      onMapClick: (_, latLng) =>
          widget.callbacks.onTap((lat: latLng.latitude, lon: latLng.longitude)),
      onMapLongClick: (_, latLng) => widget.callbacks.onLongPress((
        lat: latLng.latitude,
        lon: latLng.longitude,
      )),
    );
  }
}
