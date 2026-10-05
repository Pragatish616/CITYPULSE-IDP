/// The HTTP surface of the routing service (PLAN.md M2.2).
///
/// Everything here is translation: JSON in, [RoutingEngine] call, JSON out.
/// No routing logic lives in this file (ADR-001).
///
/// Privacy (ADR-007): request bodies carry coordinates, so they are never
/// logged; the access log records method, path and status only.
library;

import 'dart:convert';
import 'dart:io' show HttpConnectionInfo;

import 'package:pulse_router/pulse_router.dart';
import 'package:router_api/src/rewrite_proxy.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'event_state.dart';

/// Settings for [buildHandler].
class ApiConfig {
  /// Creates the settings.
  const ApiConfig({
    this.allowedOrigin = '*',
    this.adminToken,
    this.maxBodyBytes = 4096,
    this.riskCacheSeconds = 20,
    this.packBuilt = 'unknown',
    this.trustForwardedFor = false,
    this.cityId = 'unknown',
    this.cityName = 'city',
    this.maxSnapMetres = 1500,
    this.hazardLayer = true,
  });

  /// Value of `Access-Control-Allow-Origin`. `*` is for local development;
  /// set the web app's origin in production.
  final String allowedOrigin;

  /// Required in the `x-admin-token` header to change the event state. When
  /// `null` the endpoint is disabled (403), not open.
  final String? adminToken;

  /// Largest accepted request body.
  final int maxBodyBytes;

  /// How long a computed risk overlay is reused.
  final int riskCacheSeconds;

  /// The pack's build date, reported by `/health`.
  final String packBuilt;

  /// The city this service serves (`config/cities.yaml` id and English name), for `/health` and
  /// error messages (ADR-018).
  final String cityId;

  /// English display name of the city.
  final String cityName;

  /// How far a start or end point may be from the road network and still be routed, metres.
  final double maxSnapMetres;

  /// Whether the main pack carries a real flood-hazard layer. Routes from a pack without one carry
  /// `hazard_layer: false`, and the app shows no advice for them (ADR-022).
  final bool hazardLayer;

  /// Use the first `X-Forwarded-For` address to tell callers apart for rate
  /// limiting. Only safe behind a reverse proxy that sets the header; a
  /// direct client could otherwise forge it.
  final bool trustForwardedFor;
}

/// A detailed pack served inside a larger region (ADR-022): Chennai inside Tamil Nadu. A route whose
/// start and end are both inside [city]'s box is answered from this engine; the answer carries
/// `hazard_layer: true` and the app shows its advice.
class DetailRegion {
  /// Creates a detail region.
  const DetailRegion({
    required this.city,
    required this.engine,
    required this.places,
  });

  /// Its configuration (box, snap radius, flood layer flag).
  final CityConfig city;

  /// Its routing engine.
  final RoutingEngine engine;

  /// Its search index, if any.
  final PlaceIndex? places;
}

Response _json(int status, Object? body) => Response(
  status,
  body: jsonEncode(body),
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Response _error(int status, String code, String message) =>
    _json(status, {'error': code, 'message': message});

List<double> _pt(GeoPoint p) => [_round6(p.lat), _round6(p.lon)];

double _round6(double v) => (v * 1e6).roundToDouble() / 1e6;

/// Builds the request handler: routes, CORS, body-size limit and access log.
Handler buildHandler(
  RoutingEngine engine, {
  ApiConfig config = const ApiConfig(),
  PlaceIndex? places,
  List<DetailRegion> details = const [],
  DateTime Function() now = _utcNow,
  int Function()? observationCount,
  RewriteProxy? rewrite,
  EventStateController? events,
}) {
  final router = Router();
  final riskCache = <String, ({DateTime at, String body})>{};
  var queryCounter = 0;

  // Engines that carry flood data and reports: the main one if it has a flood layer, else the detail
  // regions (ADR-022).
  final hazardEngines = config.hazardLayer || details.isEmpty
      ? [engine]
      : [for (final d in details) d.engine];

  router.get('/health', (Request request) {
    return _json(200, {
      'status': 'ok',
      'city': config.cityId,
      'nodes': engine.pack.nodeCount,
      'edges': engine.pack.edgeCount,
      'observations': observationCount?.call() ?? engine.observationCount,
      'event_state': hazardEngines.first.eventState.name,
      'detail_regions': [for (final d in details) d.city.id],
      'pack_built': config.packBuilt,
      'user_classes': engine.userClasses.keys.toList()..sort(),
    });
  });

  router.post('/route', (Request request) async {
    final Map<String, Object?> body;
    try {
      final text = await request.readAsString();
      if (text.length > config.maxBodyBytes) {
        return _error(413, 'too_large', 'Request body is too large.');
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) throw const FormatException();
      body = decoded;
    } on FormatException {
      return _error(400, 'bad_json', 'Body must be a JSON object.');
    }

    GeoPoint? point(String key) {
      final v = body[key];
      if (v is! Map) return null;
      final lat = v['lat'];
      final lon = v['lon'];
      if (lat is! num || lon is! num) return null;
      final la = lat.toDouble();
      final lo = lon.toDouble();
      if (!la.isFinite || !lo.isFinite) return null;
      if (la < -90 || la > 90 || lo < -180 || lo > 180) return null;
      return (lat: la, lon: lo);
    }

    final from = point('from');
    final to = point('to');
    if (from == null || to == null) {
      return _error(
        400,
        'bad_point',
        '"from" and "to" must each be {"lat": number, "lon": number}.',
      );
    }
    final userClass = body['user_class'] ?? 'commuter';
    if (userClass is! String || !engine.userClasses.containsKey(userClass)) {
      return _error(
        400,
        'bad_user_class',
        'user_class must be one of ${engine.userClasses.keys.join(", ")}.',
      );
    }
    DateTime at = now();
    final rawAt = body['at'];
    if (rawAt != null) {
      final parsed = rawAt is String ? DateTime.tryParse(rawAt) : null;
      if (parsed == null) {
        return _error(400, 'bad_time', '"at" must be an ISO-8601 time.');
      }
      at = parsed.toUtc();
    }

    final queryId = 'q-${at.microsecondsSinceEpoch}-${++queryCounter}';
    // Both ends inside a detailed region: use its pack (and its flood layer). If that finds no
    // route, or the ends are anywhere else, the main-road pack gives the best route, without advice.
    RouteOutcome? outcome;
    var usedRegion = config.cityId;
    var hazardLayer = config.hazardLayer;
    for (final d in details) {
      if (d.city.contains(from.lat, from.lon) &&
          d.city.contains(to.lat, to.lon)) {
        final detailed = d.engine.route(
          fromLat: from.lat,
          fromLon: from.lon,
          toLat: to.lat,
          toLon: to.lon,
          userClass: userClass,
          at: at,
          queryId: queryId,
          maxSnapMetres: d.city.maxSnapMetres,
        );
        if (detailed is RouteFound) {
          outcome = detailed;
          usedRegion = d.city.id;
          hazardLayer = d.city.hazardLayer;
          break;
        }
      }
    }
    outcome ??= engine.route(
      fromLat: from.lat,
      fromLon: from.lon,
      toLat: to.lat,
      toLon: to.lon,
      userClass: userClass,
      at: at,
      queryId: queryId,
      maxSnapMetres: config.maxSnapMetres,
    );
    switch (outcome) {
      case RouteNotFound(:final reason):
        return _json(422, {
          'error': 'no_route',
          'reason': switch (reason) {
            RouteFailure.originOutsideCoverage => 'origin_outside_coverage',
            RouteFailure.destinationOutsideCoverage =>
              'destination_outside_coverage',
            RouteFailure.sameLocation => 'same_location',
            RouteFailure.noRoute => 'no_route',
          },
          'message': switch (reason) {
            RouteFailure.originOutsideCoverage =>
              'The start point is outside the mapped ${config.cityName} road network.',
            RouteFailure.destinationOutsideCoverage =>
              'The destination is outside the mapped ${config.cityName} road network.',
            RouteFailure.sameLocation =>
              'The start and destination are the same place.',
            RouteFailure.noRoute => 'No road connects these two places.',
          },
        });
      case RouteFound(:final plan):
        return _json(200, {
          'trace': plan.trace.toJson(),
          'path': [for (final p in plan.path) _pt(p)],
          'fastest_path': [for (final p in plan.fastestPath) _pt(p)],
          'detours': plan.detours,
          'origin': _pt(plan.origin),
          'destination': _pt(plan.destination),
          'origin_snap_m': plan.originSnapMetres.round(),
          'destination_snap_m': plan.destinationSnapMetres.round(),
          'avoided_hazards': [for (final p in plan.avoidedHazards) _pt(p)],
          'event_state': plan.eventState.name,
          'hazard_layer': hazardLayer,
          'region': usedRegion,
          'compute_ms': double.parse(
            plan.computeMilliseconds.toStringAsFixed(1),
          ),
        });
    }
  });

  router.get('/risk', (Request request) {
    final q = request.url.queryParameters;
    final userClass = q['user_class'] ?? 'commuter';
    if (!engine.userClasses.containsKey(userClass)) {
      return _error(400, 'bad_user_class', 'Unknown user_class.');
    }
    List<double>? bbox;
    if (q['bbox'] != null) {
      final parts = q['bbox']!.split(',').map(double.tryParse).toList();
      if (parts.length != 4 || parts.any((v) => v == null || !v.isFinite)) {
        return _error(
          400,
          'bad_bbox',
          'bbox must be minLon,minLat,maxLon,maxLat.',
        );
      }
      bbox = parts.cast<double>();
    }
    final minP = double.tryParse(q['min_p'] ?? '0') ?? 0;
    final limit = (int.tryParse(q['limit'] ?? '') ?? 20000).clamp(1, 50000);
    // `detail=1` returns every property; the maps need only three and ask for the compact form.
    final detail = q['detail'] == '1';

    final t = now();
    // The same viewport is asked for again and again while a map is panned back and forth, so keep
    // the answers for a few seconds. The key changes with the reports, so a new report shows up at
    // once.
    final key =
        '$userClass|${hazardEngines.first.eventState.name}|'
        '${hazardEngines.fold<int>(0, (a, e) => a + e.observationCount)}|$detail|$minP|$limit|'
        '${q['bbox']}|${t.millisecondsSinceEpoch ~/ (config.riskCacheSeconds * 1000)}';
    var cached = riskCache[key];
    if (cached == null) {
      riskCache.removeWhere(
        (_, v) => t.difference(v.at).inSeconds > config.riskCacheSeconds * 3,
      );
      if (riskCache.length > 64) riskCache.remove(riskCache.keys.first);
      // Only edges in the box are computed (ADR-020): a map looking at one neighbourhood does
      // not pay for a whole state.
      final box = bbox == null
          ? null
          : (
              minLon: bbox[0],
              minLat: bbox[1],
              maxLon: bbox[2],
              maxLat: bbox[3],
            );
      var edges = [
        for (final e in hazardEngines)
          ...e.riskEdges(at: t, userClass: userClass, bbox: box, limit: limit),
      ];
      if (edges.length > limit) edges = edges.sublist(0, limit);
      if (minP > 0)
        edges = [
          for (final e in edges)
            if (e.pPessimistic >= minP) e,
        ];
      cached = (
        at: t,
        body: jsonEncode(riskEdgesToGeoJson(edges, compact: !detail)),
      );
      riskCache[key] = cached;
    }
    return Response.ok(
      cached.body,
      headers: const {'content-type': 'application/geo+json; charset=utf-8'},
    );
  });

  router.get('/places', (Request request) {
    final index = places;
    final indexes = [
      // Detailed streets first: at equal relevance a Chennai side street beats a state road.
      for (final d in details)
        if (d.places != null) d.places!,
      ?index,
    ];
    if (indexes.isEmpty) {
      return _error(404, 'no_places', 'Street search is not enabled.');
    }
    final q = request.url.queryParameters;
    final query = q['q'] ?? '';
    if (query.length > 80) return _error(400, 'bad_query', 'q is too long.');
    GeoPoint? near;
    if (q['near'] != null) {
      final parts = q['near']!.split(',').map(double.tryParse).toList();
      if (parts.length != 2 || parts.any((v) => v == null || !v.isFinite)) {
        return _error(400, 'bad_near', 'near must be lat,lon.');
      }
      near = (lat: parts[0]!, lon: parts[1]!);
    }
    final limit = (int.tryParse(q['limit'] ?? '') ?? 8).clamp(1, 25);
    // Each index returns its own best `limit`; merge them by relevance, then kind, then nearness
    // (ADR-022). Duplicates (the same name within 300 m) are dropped.
    final merged = <(PlaceMatch, int)>[];
    for (var i = 0; i < indexes.length; i++) {
      for (final m in indexes[i].search(query, near: near, limit: limit)) {
        merged.add((m, i));
      }
    }
    merged.sort((a, b) {
      if (a.$1.rank != b.$1.rank) return a.$1.rank.compareTo(b.$1.rank);
      final ta = PlaceIndex.tierOf(a.$1.kind);
      final tb = PlaceIndex.tierOf(b.$1.kind);
      if (ta != tb) return ta.compareTo(tb);
      final da = a.$1.distanceMetres;
      final db = b.$1.distanceMetres;
      if (da != null && db != null && da != db) return da.compareTo(db);
      return a.$2.compareTo(b.$2);
    });
    final seen = <PlaceMatch>[];
    for (final (m, _) in merged) {
      final dup = seen.any(
        (s) =>
            s.name == m.name &&
            (s.point.lat - m.point.lat).abs() < 0.003 &&
            (s.point.lon - m.point.lon).abs() < 0.003,
      );
      if (!dup) seen.add(m);
    }
    return _json(200, {
      'results': [
        for (final m in seen.take(limit))
          {
            'name': m.name,
            'lat': _round6(m.point.lat),
            'lon': _round6(m.point.lon),
            'segments': m.edgeCount,
            'kind': m.kind,
            if (m.distanceMetres != null)
              'distance_m': m.distanceMetres!.round(),
          },
      ],
    });
  });

  router.post('/rewrite', (Request request) async {
    final proxy = rewrite;
    if (proxy == null) {
      return _error(
        503,
        'rewrite_unavailable',
        'The cloud rewriter is not configured.',
      );
    }
    final Map<String, Object?> facts;
    try {
      final text = await request.readAsString();
      if (text.length > proxy.maxFactsChars + 256) {
        return _error(413, 'too_large', 'Request body is too large.');
      }
      final decoded = jsonDecode(text);
      final inner = decoded is Map ? decoded['facts'] : null;
      if (inner is! Map<String, Object?>) throw const FormatException();
      facts = inner;
    } on FormatException {
      return _error(400, 'bad_json', 'Body must be {"facts": {...}}.');
    }
    final forwarded = config.trustForwardedFor
        ? request.headers['x-forwarded-for']?.split(',').first.trim()
        : null;
    final connection = request.context['shelf.io.connection_info'];
    final caller = (forwarded != null && forwarded.isNotEmpty)
        ? forwarded
        : (connection is HttpConnectionInfo
              ? connection.remoteAddress.address
              : 'unknown');
    final result = await proxy.rewrite(facts, clientKey: caller);
    return switch (result) {
      RewriteText(:final text) => _json(200, {'text': text}),
      RewriteError(:final status, :final code, :final message) => _error(
        status,
        code,
        message,
      ),
    };
  });

  router.get('/event-state', (Request request) {
    final c = events;
    if (c != null) return _json(200, c.status().toJson());
    return _json(200, {'event_state': hazardEngines.first.eventState.name});
  });

  router.put('/event-state', (Request request) async {
    final token = config.adminToken;
    if (token == null || token.isEmpty) {
      return _error(403, 'disabled', 'Changing the event state is disabled.');
    }
    if (request.headers['x-admin-token'] != token) {
      return _error(401, 'unauthorised', 'Missing or wrong x-admin-token.');
    }
    final c = events;
    try {
      final body = jsonDecode(await request.readAsString()) as Map;
      if (body['mode'] == 'auto') {
        // Give the decision back to the satellite rain rule (ADR-027).
        if (c == null || !c.resumeAuto()) {
          return _error(
            400,
            'no_rain_source',
            'No rain source is configured, so there is no automatic mode to return to.',
          );
        }
        return _json(200, c.status().toJson());
      }
      final state = EventState.parse(body['event_state']! as String);
      final hours = body['hours'];
      if (hours != null && (hours is! num || hours <= 0 || hours > 24 * 14)) {
        return _error(
          400,
          'bad_hours',
          '"hours" must be a number from 0 to 336 (14 days).',
        );
      }
      if (c != null) {
        c.setManual(
          state,
          hold: hours == null
              ? null
              : Duration(minutes: ((hours as num) * 60).round()),
        );
      } else {
        engine.eventState = state;
        for (final d in details) {
          d.engine.eventState = state;
        }
      }
    } on Object {
      return _error(
        400,
        'bad_state',
        'Body must be {"event_state": "dry" | "watch" | "active", "hours": optional number} or {"mode": "auto"}.',
      );
    }
    final after = events;
    return _json(
      200,
      after != null
          ? after.status().toJson()
          : {'event_state': hazardEngines.first.eventState.name},
    );
  });

  final cors = <String, String>{
    'access-control-allow-origin': config.allowedOrigin,
    'access-control-allow-methods': 'GET, POST, PUT, OPTIONS',
    'access-control-allow-headers': 'content-type, x-admin-token',
    'access-control-max-age': '600',
  };

  return const Pipeline()
      .addMiddleware(
        (inner) => (request) async {
          if (request.method == 'OPTIONS') {
            return Response(204, headers: cors);
          }
          final sw = Stopwatch()..start();
          events?.refresh(); // overrides and holds can run out between polls
          Response response;
          try {
            response = await inner(request);
          } on Object {
            // Never leak a stack trace or the failing input to a client.
            response = _error(500, 'internal', 'Internal error.');
          }
          // ignore: avoid_print
          print(
            '${request.method} /${request.url.path} -> ${response.statusCode} '
            '(${sw.elapsedMilliseconds} ms)',
          );
          return response.change(headers: cors);
        },
      )
      .addHandler(router.call);
}

DateTime _utcNow() => DateTime.now().toUtc();
