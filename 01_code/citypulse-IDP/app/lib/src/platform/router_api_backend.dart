/// [RoutingBackend] that calls `services/router_api` over HTTP. The web app
/// uses this (a browser should not hold the city graph), and the phone can be
/// switched to it in Settings.
library;

import 'dart:async';
import 'dart:convert';

import 'package:citypulse_app/src/core/app_config.dart';
import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/platform/routing_backend.dart';
import 'package:http/http.dart' as http;
import 'package:pulse_router/pulse_router.dart';

/// Calls `router_api`.
class RouterApiBackend implements RoutingBackend {
  /// Creates a backend. [client] is injectable for tests.
  RouterApiBackend({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  /// The `router_api` root URL.
  final String baseUrl;

  /// Per-request timeout.
  final Duration timeout;
  final http.Client _client;

  @override
  ComputeSite get site => ComputeSite.server;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = AppConfig.join(baseUrl, path);
    return query == null ? base : base.replace(queryParameters: query);
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      throw const RoutingException(RoutingFailure.network, 'timeout');
    } on http.ClientException catch (e) {
      throw RoutingException(RoutingFailure.network, e.message);
    }
  }

  @override
  Future<void> warmUp() async {
    final r = await _send(() => _client.get(_uri('health')));
    if (r.statusCode != 200) {
      throw RoutingException(RoutingFailure.server, 'health ${r.statusCode}');
    }
  }

  @override
  Future<RouteView> route({
    required GeoPoint from,
    required GeoPoint to,
    required TravelType travel,
    DateTime? at,
  }) async {
    final response = await _send(
      () => _client.post(
        _uri('route'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'from': {'lat': from.lat, 'lon': from.lon},
          'to': {'lat': to.lat, 'lon': to.lon},
          'user_class': travel.wire,
          if (at != null) 'at': at.toUtc().toIso8601String(),
        }),
      ),
    );
    final Map<String, Object?> body;
    try {
      body = jsonDecode(response.body) as Map<String, Object?>;
    } on FormatException {
      throw RoutingException(
        RoutingFailure.server,
        'bad body ${response.statusCode}',
      );
    }

    if (response.statusCode == 422) {
      throw RoutingException(switch (body['reason']) {
        'origin_outside_coverage' => RoutingFailure.originOutside,
        'destination_outside_coverage' => RoutingFailure.destinationOutside,
        'same_location' => RoutingFailure.sameLocation,
        _ => RoutingFailure.noRoute,
      });
    }
    if (response.statusCode != 200) {
      throw RoutingException(
        RoutingFailure.server,
        'route ${response.statusCode}',
      );
    }

    try {
      List<GeoPoint> points(Object? raw) => [
        for (final p in raw! as List<Object?>)
          (
            lat: ((p! as List<Object?>)[0]! as num).toDouble(),
            lon: ((p as List<Object?>)[1]! as num).toDouble(),
          ),
      ];
      return RouteView(
        // Rebuilt with the same Dart code the server used, so the invariants
        // (e.g. duration >= free-flow) are re-checked on this side.
        trace: DecisionTrace.fromJson(body['trace']! as Map<String, Object?>),
        path: points(body['path']),
        fastestPath: points(body['fastest_path']),
        detours: body['detours']! as bool,
        avoidedHazards: points(body['avoided_hazards']),
        eventState: EventState.parse(body['event_state']! as String),
        computeMilliseconds: (body['compute_ms']! as num).toDouble(),
        computedOn: ComputeSite.server,
        origin: points([body['origin']]).single,
        destination: points([body['destination']]).single,
        originSnapMetres: (body['origin_snap_m'] as num?)?.toDouble() ?? 0,
        destinationSnapMetres:
            (body['destination_snap_m'] as num?)?.toDouble() ?? 0,
        hazardLayer: body['hazard_layer'] as bool?,
      );
      // A malformed or impossible response is a server problem, never a crash.
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      throw RoutingException(RoutingFailure.server, 'unreadable response: $e');
    }
  }

  @override
  Future<String> riskGeoJson({
    required TravelType travel,
    GeoBounds? bounds,
  }) async {
    final r = await _send(
      () => _client.get(
        _uri('risk', {
          'user_class': travel.wire,
          if (bounds != null)
            'bbox':
                '${bounds.minLon},${bounds.minLat},${bounds.maxLon},${bounds.maxLat}',
          'limit': '8000',
        }),
      ),
    );
    if (r.statusCode != 200) {
      throw RoutingException(RoutingFailure.server, 'risk ${r.statusCode}');
    }
    return r.body;
  }

  @override
  Future<List<Place>> searchPlaces(String query, {GeoPoint? near}) async {
    if (query.trim().length < 2) return const [];
    final r = await _send(
      () => _client.get(
        _uri('places', {
          'q': query.trim(),
          if (near != null) 'near': '${near.lat},${near.lon}',
          'limit': '8',
        }),
      ),
    );
    if (r.statusCode != 200) return const [];
    final rows =
        (jsonDecode(r.body) as Map<String, Object?>)['results']!
            as List<Object?>;
    return [
      for (final raw in rows.cast<Map<String, Object?>>())
        Place(
          name: raw['name']! as String,
          point: (
            lat: (raw['lat']! as num).toDouble(),
            lon: (raw['lon']! as num).toDouble(),
          ),
          detail: raw['distance_m'] == null
              ? null
              : '${((raw['distance_m']! as num) / 1000).toStringAsFixed(1)} km',
        ),
    ];
  }

  @override
  Future<EventState> eventState() async {
    final r = await _send(() => _client.get(_uri('event-state')));
    if (r.statusCode != 200) return EventState.active;
    return EventState.parse(
      (jsonDecode(r.body) as Map<String, Object?>)['event_state']! as String,
    );
  }

  @override
  void addLocalObservation(EngineObservation observation) {}

  @override
  void dispose() => _client.close();
}
