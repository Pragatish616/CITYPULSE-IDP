/// `flutter_map` implementation of [MapSurfaceBuilder], for the desktop test app (MapLibre has no Windows build).
///
/// Basemap: the same style the phone and web app use (`AppConfig.mapStyleUrl`, OpenFreeMap by default), drawn from its vector tiles by
/// `vector_map_tiles`. Overlays, bottom to top, as in `maplibre_surface.dart`: hazard map (dashed where only the 2015 hazard zones speak,
/// solid where a report exists), fastest route, chosen route (white casing under blue), watchlist pins, markers. If the style cannot be
/// loaded (no network) the overlays are still drawn, on a plain background.
library;

import 'dart:async';
import 'dart:convert';

import 'package:citypulse_app/src/core/theme.dart';
import 'package:citypulse_app/src/features/map/map_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

/// Builds a [MapSurfaceBuilder] that draws with `flutter_map` using the style at [styleUrl].
MapSurfaceBuilder flutterMapSurfaceBuilder(
  String styleUrl, {
  required GeoPoint centre,
  double zoom = 11.5,
}) =>
    (context, callbacks) => FlutterMapSurface(
      styleUrl: styleUrl,
      centre: centre,
      zoom: zoom,
      callbacks: callbacks,
    );

Color _hex(String s) => Color(int.parse('FF${s.substring(1)}', radix: 16));

/// Colour by the pessimistic index, linear between the palette's four stops (0.2, 0.45, 0.7, 0.95).
Color _riskColour(double p) {
  const stops = [0.2, 0.45, 0.7, 0.95];
  final colours = [
    _hex(RiskPalette.riskLow),
    _hex(RiskPalette.riskMid),
    _hex(RiskPalette.riskHigh),
    _hex(RiskPalette.riskSevere),
  ];
  if (p <= stops.first) return colours.first;
  if (p >= stops.last) return colours.last;
  for (var i = 0; i < stops.length - 1; i++) {
    if (p <= stops[i + 1]) {
      final t = (p - stops[i]) / (stops[i + 1] - stops[i]);
      return Color.lerp(colours[i], colours[i + 1], t)!;
    }
  }
  return colours.last;
}

/// Linear interpolation of a width over zoom stops, as the MapLibre expressions do.
double _byZoom(double zoom, List<(double, double)> stops) {
  if (zoom <= stops.first.$1) return stops.first.$2;
  if (zoom >= stops.last.$1) return stops.last.$2;
  for (var i = 0; i < stops.length - 1; i++) {
    if (zoom <= stops[i + 1].$1) {
      final t = (zoom - stops[i].$1) / (stops[i + 1].$1 - stops[i].$1);
      return stops[i].$2 + t * (stops[i + 1].$2 - stops[i].$2);
    }
  }
  return stops.last.$2;
}

const _priorW = [(10.0, 0.7), (13.0, 1.6), (15.0, 3.0), (17.0, 5.0)];
const _priorCasingW = [(10.0, 1.6), (13.0, 2.8), (15.0, 4.4), (17.0, 6.6)];
const _reportedW = [(10.0, 1.4), (13.0, 3.0), (15.0, 5.0), (17.0, 8.0)];
const _reportedCasingW = [(10.0, 2.4), (13.0, 4.4), (15.0, 6.6), (17.0, 10.0)];

class _RiskLine {
  _RiskLine(this.points, this.p, this.reported);
  final List<LatLng> points;
  final double p;
  final bool reported;
}

List<_RiskLine> _parseRisk(String? json) {
  if (json == null) return const [];
  final out = <_RiskLine>[];
  final collection = jsonDecode(json) as Map<String, dynamic>;
  for (final f in (collection['features'] as List? ?? const [])) {
    final feature = f as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) continue;
    final props = (feature['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final p = (props['p_pessimistic'] as num?)?.toDouble() ?? 0.2;
    final reported = props['has_observation'] == true;
    final lines = switch (geometry['type']) {
      'LineString' => [geometry['coordinates'] as List<dynamic>],
      'MultiLineString' => (geometry['coordinates'] as List<dynamic>).cast<List<dynamic>>(),
      _ => const <List<dynamic>>[],
    };
    for (final line in lines) {
      final pts = [
        for (final c in line)
          LatLng((c as List<dynamic>)[1] as double, c[0] as double),
      ];
      if (pts.length >= 2) out.add(_RiskLine(pts, p, reported));
    }
  }
  return out;
}

List<LatLng> _parsePoints(String? json) {
  if (json == null) return const [];
  final out = <LatLng>[];
  final collection = jsonDecode(json) as Map<String, dynamic>;
  for (final f in (collection['features'] as List? ?? const [])) {
    final geometry = (f as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
    if (geometry?['type'] == 'Point') {
      final c = geometry!['coordinates'] as List;
      out.add(LatLng(c[1] as double, c[0] as double));
    }
  }
  return out;
}

/// The `flutter_map` map plus its overlay layers.
class FlutterMapSurface extends StatefulWidget {
  /// Creates the surface.
  const FlutterMapSurface({
    required this.styleUrl,
    required this.centre,
    required this.callbacks,
    this.zoom = 11.5,
    super.key,
  });

  /// Style URL (MapLibre style JSON with vector tiles).
  final String styleUrl;

  /// Where the camera starts.
  final GeoPoint centre;

  /// The zoom the camera starts at.
  final double zoom;

  /// Events to report.
  final MapSurfaceCallbacks callbacks;

  @override
  State<FlutterMapSurface> createState() => _FlutterMapSurfaceState();
}

class _FlutterMapSurfaceState extends State<FlutterMapSurface>
    implements MapHandle {
  final _controller = MapController();
  Style? _style;
  String? _styleError;
  Timer? _idle;

  List<_RiskLine> _risk = const [];
  List<LatLng> _watchlist = const [];
  List<LatLng> _path = const [];
  List<LatLng> _fastest = const [];
  List<MapMarker> _markers = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadStyle());
  }

  Future<void> _loadStyle() async {
    try {
      final style = await StyleReader(
        uri: widget.styleUrl,
        logger: const vtr.Logger.noop(),
      ).read();
      if (mounted) setState(() => _style = style);
    } on Object catch (e) {
      if (mounted) setState(() => _styleError = e.toString());
    }
  }

  @override
  void dispose() {
    _idle?.cancel();
    _controller.dispose();
    super.dispose();
  }

  LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lon);

  @override
  Future<void> setRisk(String? geoJson) async {
    final parsed = _parseRisk(geoJson);
    if (mounted) setState(() => _risk = parsed);
  }

  @override
  Future<void> setWatchlist(String? geoJson) async {
    final parsed = _parsePoints(geoJson);
    if (mounted) setState(() => _watchlist = parsed);
  }

  @override
  Future<void> setRoute({
    List<GeoPoint>? path,
    List<GeoPoint>? fastest,
    List<MapMarker> markers = const [],
  }) async {
    if (!mounted) return;
    setState(() {
      _path = [for (final p in path ?? const <GeoPoint>[]) _ll(p)];
      _fastest = [for (final p in fastest ?? const <GeoPoint>[]) _ll(p)];
      _markers = markers;
    });
  }

  @override
  Future<void> fit(List<GeoPoint> points) async {
    if (points.isEmpty) return;
    final bounds = LatLngBounds.fromPoints([for (final p in points) _ll(p)]);
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(48, 120, 48, 260),
        maxZoom: 17,
      ),
    );
  }

  @override
  Future<MapView?> view() async {
    final cam = _controller.camera;
    final b = cam.visibleBounds;
    return (
      bounds: (
        minLat: b.south,
        minLon: b.west,
        maxLat: b.north,
        maxLon: b.east,
      ),
      zoom: cam.zoom,
    );
  }

  @override
  GeoPoint? cameraCenter() {
    final c = _controller.camera.center;
    return (lat: c.latitude, lon: c.longitude);
  }

  @override
  Future<void> flyTo(GeoPoint point, {double zoom = 15}) async {
    _controller.move(_ll(point), zoom);
  }

  void _onEvent(MapEvent event) {
    // The camera is idle 350 ms after the last movement (a pan, a wheel zoom, a fly-to).
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 350), () {
      if (mounted) widget.callbacks.onCameraIdle?.call();
    });
  }

  Widget _overlays(BuildContext context) {
    final zoom = MapCamera.of(context).zoom;
    final riskVisible = zoom >= kRiskMinZoom && _risk.isNotEmpty;
    return Stack(
      children: [
        if (riskVisible) ...[
          PolylineLayer(
            polylines: [
              for (final l in _risk)
                Polyline(
                  points: l.points,
                  strokeWidth: _byZoom(zoom, l.reported ? _reportedCasingW : _priorCasingW),
                  color: Colors.white.withValues(alpha: l.reported ? 0.7 : 0.55),
                  pattern: l.reported
                      ? const StrokePattern.solid()
                      : StrokePattern.dashed(segments: const [4, 4]),
                  strokeCap: StrokeCap.round,
                  strokeJoin: StrokeJoin.round,
                ),
            ],
          ),
          PolylineLayer(
            polylines: [
              for (final l in _risk)
                Polyline(
                  points: l.points,
                  strokeWidth: _byZoom(zoom, l.reported ? _reportedW : _priorW),
                  color: _riskColour(l.p).withValues(alpha: 0.95),
                  pattern: l.reported
                      ? const StrokePattern.solid()
                      : StrokePattern.dashed(segments: const [4, 4]),
                  strokeCap: StrokeCap.round,
                  strokeJoin: StrokeJoin.round,
                ),
            ],
          ),
        ],
        if (_fastest.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _fastest,
                strokeWidth: 4,
                color: _hex(RiskPalette.fastest).withValues(alpha: 0.9),
                pattern: StrokePattern.dashed(segments: const [6, 6]),
              ),
            ],
          ),
        if (_path.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _path,
                strokeWidth: 9,
                color: _hex(RiskPalette.routeCasing),
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
              Polyline(
                points: _path,
                strokeWidth: 5.5,
                color: _hex(RiskPalette.route),
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),
        if (_watchlist.isNotEmpty)
          CircleLayer(
            circles: [
              for (final p in _watchlist)
                CircleMarker(
                  point: p,
                  radius: 5,
                  color: _hex(RiskPalette.watchlist).withValues(alpha: 0.85),
                  borderStrokeWidth: 1.5,
                  borderColor: Colors.white,
                ),
            ],
          ),
        CircleLayer(
          circles: [
            for (final m in _markers)
              CircleMarker(
                point: _ll(m.point),
                radius: 9,
                color: _hex(switch (m.kind) {
                  MarkerKind.origin => RiskPalette.origin,
                  MarkerKind.destination => RiskPalette.destination,
                  MarkerKind.avoided => RiskPalette.avoided,
                }),
                borderStrokeWidth: 3,
                borderColor: Colors.white,
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: LatLng(widget.centre.lat, widget.centre.lon),
            initialZoom: widget.zoom,
            maxZoom: 19,
            backgroundColor: const Color(0xFFEFEFEF),
            onMapReady: () => widget.callbacks.onReady(this),
            onTap: (_, p) =>
                widget.callbacks.onTap((lat: p.latitude, lon: p.longitude)),
            onLongPress: (_, p) => widget.callbacks.onLongPress((
              lat: p.latitude,
              lon: p.longitude,
            )),
            onMapEvent: _onEvent,
          ),
          children: [
            if (style != null)
              VectorTileLayer(
                tileProviders: style.providers,
                theme: style.theme,
                sprites: style.sprites,
                maximumZoom: 19,
                tileOffset: TileOffset.DEFAULT,
                layerMode: VectorTileLayerMode.vector,
              ),
            Builder(builder: _overlays),
          ],
        ),
        if (style == null)
          Positioned(
            left: 8,
            top: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  _styleError == null
                      ? 'Loading the base map…'
                      : 'Base map unavailable (no network?). Routes are still drawn.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
