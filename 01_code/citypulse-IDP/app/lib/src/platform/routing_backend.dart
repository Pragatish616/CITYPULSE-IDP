/// What the UI needs from a routing engine, whether it runs on the phone or on
/// `router_api`. Two implementations of one interface; the algorithm itself
/// exists once, in `pulse_router` (ADR-001).
library;

import 'package:citypulse_app/src/domain/models.dart';
import 'package:pulse_router/pulse_router.dart';

/// A routing engine the UI can call.
abstract class RoutingBackend {
  /// Where this backend calculates.
  ComputeSite get site;

  /// Loads whatever the backend needs. Safe to call repeatedly; completes when
  /// the backend can answer. Throws [RoutingException] (`notReady`) on failure.
  Future<void> warmUp();

  /// Plans a route. Throws [RoutingException].
  Future<RouteView> route({
    required GeoPoint from,
    required GeoPoint to,
    required TravelType travel,
    DateTime? at,
  });

  /// The risk overlay as a GeoJSON `FeatureCollection` string, for [bounds] only when given (the
  /// part of the map being looked at; ADR-020).
  Future<String> riskGeoJson({required TravelType travel, GeoBounds? bounds});

  /// Street search, nearest first when [near] is given.
  Future<List<Place>> searchPlaces(String query, {GeoPoint? near});

  /// The current flood-event state.
  Future<EventState> eventState();

  /// Makes a report this device just sent count immediately. A no-op for a
  /// server backend (the server learns of it from the ingest log).
  void addLocalObservation(EngineObservation observation);

  /// Releases resources.
  void dispose();
}
