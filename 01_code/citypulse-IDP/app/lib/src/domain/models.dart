/// Plain data types shared by the UI and the two routing back ends.
library;

import 'package:pulse_router/pulse_router.dart';

/// A named place a traveller can pick.
class Place {
  /// Creates a place.
  const Place({required this.name, required this.point, this.detail});

  /// Display name, e.g. a street name or "Dropped pin".
  final String name;

  /// Where it is.
  final GeoPoint point;

  /// Optional second line, e.g. "2.1 km from the map centre".
  final String? detail;

  /// A pin the user dropped on the map.
  factory Place.dropped(GeoPoint point) =>
      Place(name: 'Dropped pin', point: point);

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.name == name &&
      other.point.lat == point.lat &&
      other.point.lon == point.lon;

  @override
  int get hashCode => Object.hash(name, point.lat, point.lon);
}

/// A computed route, from either back end.
class RouteView {
  /// Creates a view.
  const RouteView({
    required this.trace,
    required this.path,
    required this.fastestPath,
    required this.detours,
    required this.avoidedHazards,
    required this.eventState,
    required this.computeMilliseconds,
    required this.computedOn,
    required this.origin,
    required this.destination,
    this.originSnapMetres = 0,
    this.destinationSnapMetres = 0,
    this.hazardLayer,
  });

  /// The decision trace; the only input to the explanation.
  final DecisionTrace trace;

  /// The chosen route, junction to junction.
  final List<GeoPoint> path;

  /// The fastest route ignoring hazards.
  final List<GeoPoint> fastestPath;

  /// Whether the chosen route differs from the fastest one.
  final bool detours;

  /// Midpoints of hazard edges the chosen route avoids.
  final List<GeoPoint> avoidedHazards;

  /// The event state the query ran under.
  final EventState eventState;

  /// Whether this route was computed with a flood-hazard layer (ADR-022). A server serving a
  /// region with a detailed city inside it says so per route; `null` means the city's own setting.
  final bool? hazardLayer;

  /// Engine time, milliseconds.
  final double computeMilliseconds;

  /// `device` or `server`.
  final ComputeSite computedOn;

  /// How far the start point you gave was from the junction the route starts at, metres.
  final double originSnapMetres;

  /// How far the destination you gave was from the junction the route ends at, metres.
  final double destinationSnapMetres;

  /// The junction the start snapped to.
  final GeoPoint origin;

  /// The junction the destination snapped to.
  final GeoPoint destination;

  /// Minutes the chosen route takes for this traveller's mode in free flow (not the penalised
  /// cost; see ADR-016). A walker's minutes are walking minutes (ADR-019).
  double get travelMinutes => trace.chosen.freeFlowDurationSeconds / 60;

  /// How many minutes longer than the fastest route this one is, or `0`.
  double get extraMinutes {
    if (trace.alternatives.isEmpty) return 0;
    final extra =
        trace.chosen.freeFlowDurationSeconds -
        trace.alternatives.first.durationSeconds;
    return extra <= 0 ? 0 : extra / 60;
  }
}

/// Where a route was calculated.
enum ComputeSite {
  /// In-process on this device.
  device,

  /// By `router_api`.
  server,
}

/// What a routing call can fail with.
enum RoutingFailure {
  /// Start is outside the mapped network.
  originOutside,

  /// Destination is outside the mapped network.
  destinationOutside,

  /// Start and destination are the same junction.
  sameLocation,

  /// No path exists.
  noRoute,

  /// The service could not be reached.
  network,

  /// The service answered with an error.
  server,

  /// Local map data is still loading or failed to load.
  notReady,
}

/// A routing failure with a machine-readable [kind].
class RoutingException implements Exception {
  /// Creates the exception.
  const RoutingException(this.kind, [this.detail]);

  /// What went wrong.
  final RoutingFailure kind;

  /// Optional developer-facing detail; never shown to users verbatim.
  final String? detail;

  @override
  String toString() =>
      'RoutingException($kind${detail == null ? '' : ': $detail'})';
}

/// A rectangle on the map, in degrees. A record so it can cross an isolate boundary.
typedef GeoBounds = ({
  double minLat,
  double minLon,
  double maxLat,
  double maxLon,
});

/// The traveller's mode. It selects the movement profile (speeds, road access, one-way rules) and
/// the hazard caution (`z`, `λ`) on the engine (ADR-019).
enum TravelType {
  /// Car.
  commuter('commuter'),

  /// Bicycle.
  cyclist('cyclist'),

  /// On foot.
  pedestrian('pedestrian'),

  /// Emergency vehicle.
  emergency('emergency');

  const TravelType(this.wire);

  /// The engine's user-class key.
  final String wire;

  /// Parses a stored value; unknown gives [commuter].
  static TravelType fromWire(String? v) =>
      TravelType.values.firstWhere((t) => t.wire == v, orElse: () => commuter);
}
