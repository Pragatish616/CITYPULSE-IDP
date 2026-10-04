/// The map, behind an interface.
///
/// The screens talk to a [MapHandle], never to MapLibre directly, for two
/// reasons: widget tests run on a host VM that cannot host a native map view,
/// and the map engine is still provisional (PLAN.md M0.9 spikes `maplibre_gl`
/// against `flutter_map` on a real phone; ADR-014 picks one). Swapping the
/// engine means writing another [MapSurfaceBuilder], nothing else.
library;

import 'package:citypulse_app/src/domain/models.dart' show GeoBounds;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse_router/pulse_router.dart';

/// The overlay is drawn only from this zoom up. Below it a whole district is on screen and the street-
/// level hazard picture is neither readable nor worth fetching (ADR-020).
const double kRiskMinZoom = 10.5;

/// What part of the world the map is showing.
typedef MapView = ({GeoBounds bounds, double zoom});

/// A marker the screens ask the map to draw.
enum MarkerKind {
  /// Where the route starts.
  origin,

  /// Where the route ends.
  destination,

  /// A hazard the chosen route avoids.
  avoided,
}

/// A point to draw and what it is.
class MapMarker {
  /// Creates a marker.
  const MapMarker(this.kind, this.point);

  /// What it marks.
  final MarkerKind kind;

  /// Where.
  final GeoPoint point;
}

/// The operations the screens need from a map, once it exists.
abstract class MapHandle {
  /// Shows the hazard overlay from a GeoJSON string, or hides it when `null`.
  Future<void> setRisk(String? geoJson);

  /// Shows the watchlist pins from a GeoJSON string, or hides them.
  Future<void> setWatchlist(String? geoJson);

  /// Draws the chosen route, the fastest route (when different) and markers;
  /// everything `null`/empty clears them.
  Future<void> setRoute({
    List<GeoPoint>? path,
    List<GeoPoint>? fastest,
    List<MapMarker> markers = const [],
  });

  /// Moves the camera to show every point in [points].
  Future<void> fit(List<GeoPoint> points);

  /// The point at the middle of the visible map, or `null` before it is ready.
  GeoPoint? cameraCenter();

  /// The visible rectangle and zoom, or `null` before the map is ready.
  Future<MapView?> view();

  /// Moves the camera to [point] at [zoom].
  Future<void> flyTo(GeoPoint point, {double zoom = 15});
}

/// Events the map reports back.
class MapSurfaceCallbacks {
  /// Creates the callbacks.
  const MapSurfaceCallbacks({
    required this.onReady,
    required this.onTap,
    required this.onLongPress,
    this.onCameraIdle,
  });

  /// The map and its style are ready; the handle may be used.
  final void Function(MapHandle handle) onReady;

  /// A tap on the map.
  final void Function(GeoPoint point) onTap;

  /// A long press on the map.
  final void Function(GeoPoint point) onLongPress;

  /// The camera stopped moving (after a pan, zoom or fly-to).
  final VoidCallback? onCameraIdle;
}

/// Builds the map widget.
typedef MapSurfaceBuilder = Widget Function(
  BuildContext context,
  MapSurfaceCallbacks callbacks,
);

/// The map widget builder. The default is wired in `main.dart` to MapLibre;
/// tests override it with a fake.
final mapSurfaceBuilderProvider = Provider<MapSurfaceBuilder>(
  (ref) =>
      (context, callbacks) => const SizedBox.expand(),
);
