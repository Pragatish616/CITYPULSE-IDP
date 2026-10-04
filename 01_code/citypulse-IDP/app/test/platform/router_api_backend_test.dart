import 'dart:convert';

import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/platform/router_api_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_router/pulse_router.dart';

import '../helpers/harness.dart';

String _routeJson({int status = 200, Map<String, Object?>? override}) {
  final view = sampleRoute();
  return jsonEncode({
    'trace': view.trace.toJson(),
    'path': [
      for (final p in view.path) [p.lat, p.lon],
    ],
    'fastest_path': [
      for (final p in view.fastestPath) [p.lat, p.lon],
    ],
    'detours': view.detours,
    'origin': [view.origin.lat, view.origin.lon],
    'destination': [view.destination.lat, view.destination.lon],
    'avoided_hazards': [
      for (final p in view.avoidedHazards) [p.lat, p.lon],
    ],
    'event_state': 'active',
    'compute_ms': 12.5,
    ...?override,
  });
}

RouterApiBackend _backend(MockClient client) =>
    RouterApiBackend(baseUrl: 'http://api.test/', client: client);

const _from = (lat: 13.04, lon: 80.23);
const _to = (lat: 12.98, lon: 80.22);

void main() {
  test('route: sends the request and rebuilds the trace and paths', () async {
    late http.Request seen;
    final backend = _backend(
      MockClient((req) async {
        seen = req;
        return http.Response(_routeJson(), 200);
      }),
    );
    final view = await backend.route(
      from: _from,
      to: _to,
      travel: TravelType.pedestrian,
      at: kTestNow,
    );
    expect(seen.method, 'POST');
    expect(seen.url.toString(), 'http://api.test/route');
    final sent = jsonDecode(seen.body) as Map<String, Object?>;
    expect(sent['user_class'], 'pedestrian');
    expect(sent['from'], {'lat': 13.04, 'lon': 80.23});
    expect(sent['at'], kTestNow.toIso8601String());

    expect(view.computedOn, ComputeSite.server);
    expect(view.trace.chosen.freeFlowDurationSeconds, 1023);
    expect(
      view.trace.alternatives.single.blockingEdges.single.streetName,
      'Kotturpuram Bridge approach',
    );
    expect(view.path, hasLength(2));
    expect(view.detours, isTrue);
    expect(view.eventState, EventState.active);
    expect(view.computeMilliseconds, 12.5);
    expect(view.avoidedHazards, hasLength(1));
  });

  test('route: reads the per-route flood-layer flag, and leaves it unset when the server omits it (ADR-022)',
      () async {
    Future<RouteView> routeWith(Map<String, Object?>? override) => _backend(
          MockClient((_) async => http.Response(_routeJson(override: override), 200)),
        ).route(from: _from, to: _to, travel: TravelType.commuter, at: kTestNow);
    expect((await routeWith({'hazard_layer': false})).hazardLayer, isFalse);
    expect((await routeWith({'hazard_layer': true})).hazardLayer, isTrue);
    expect((await routeWith(null)).hazardLayer, isNull);
  });

  test('422 maps each reason to a typed failure', () async {
    for (final (reason, expected) in [
      ('origin_outside_coverage', RoutingFailure.originOutside),
      ('destination_outside_coverage', RoutingFailure.destinationOutside),
      ('same_location', RoutingFailure.sameLocation),
      ('no_route', RoutingFailure.noRoute),
    ]) {
      final backend = _backend(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'no_route', 'reason': reason}),
            422,
          ),
        ),
      );
      await expectLater(
        backend.route(from: _from, to: _to, travel: TravelType.commuter),
        throwsA(
          isA<RoutingException>().having((e) => e.kind, 'kind', expected),
        ),
        reason: reason,
      );
    }
  });

  test('network failures and timeouts are `network`, server errors and '
      'garbage are `server`', () async {
    Future<RoutingFailure> kindOf(MockClient c) async {
      try {
        await _backend(c)
            .route(from: _from, to: _to, travel: TravelType.commuter);
      } on RoutingException catch (e) {
        return e.kind;
      }
      fail('expected a RoutingException');
    }

    expect(
      await kindOf(
        MockClient((_) async => throw http.ClientException('offline')),
      ),
      RoutingFailure.network,
    );
    expect(
      await kindOf(
        MockClient((_) async => http.Response('{"error":"internal"}', 500)),
      ),
      RoutingFailure.server,
    );
    expect(
      await kindOf(MockClient((_) async => http.Response('<html>', 200))),
      RoutingFailure.server,
    );
    // A syntactically fine response that is not a valid trace is rejected.
    expect(
      await kindOf(
        MockClient(
          (_) async => http.Response(
            _routeJson(
              override: {
                'trace': {'query_id': 'x'},
              },
            ),
            200,
          ),
        ),
      ),
      RoutingFailure.server,
    );
  });

  test('an impossible trace from a server (duration below free-flow) is '
      'rejected, not displayed', () async {
    final view = sampleRoute();
    final trace =
        jsonDecode(jsonEncode(view.trace.toJson())) as Map<String, Object?>;
    (trace['chosen']! as Map<String, Object?>)['duration_s'] = 10;
    final backend = _backend(
      MockClient(
        (_) async => http.Response(_routeJson(override: {'trace': trace}), 200),
      ),
    );
    await expectLater(
      backend.route(from: _from, to: _to, travel: TravelType.commuter),
      throwsA(
        isA<RoutingException>().having(
          (e) => e.kind,
          'kind',
          RoutingFailure.server,
        ),
      ),
    );
  });

  test('searchPlaces parses results, passes the reference point and skips '
      'tiny queries without a request', () async {
    var requests = 0;
    late Uri url;
    final backend = _backend(
      MockClient((req) async {
        requests++;
        url = req.url;
        return http.Response(
          jsonEncode({
            'results': [
              {
                'name': 'Usman Road',
                'lat': 13.04,
                'lon': 80.23,
                'segments': 9,
                'distance_m': 1200,
              },
            ],
          }),
          200,
        );
      }),
    );
    expect(await backend.searchPlaces('a'), isEmpty);
    expect(requests, 0);
    final places = await backend.searchPlaces('usman', near: _from);
    expect(places.single.name, 'Usman Road');
    expect(places.single.detail, '1.2 km');
    expect(url.queryParameters['q'], 'usman');
    expect(url.queryParameters['near'], '13.04,80.23');
  });

  test(
    'eventState defaults to the cautious `active` if the service errs',
    () async {
      expect(
        await _backend(
          MockClient((_) async => http.Response('{"event_state":"dry"}', 200)),
        ).eventState(),
        EventState.dry,
      );
      expect(
        await _backend(MockClient((_) async => http.Response('oops', 503)))
            .eventState(),
        EventState.active,
      );
    },
  );

  test('riskGeoJson returns the body and passes the travel type', () async {
    late Uri url;
    final backend = _backend(
      MockClient((req) async {
        url = req.url;
        return http.Response('{"type":"FeatureCollection","features":[]}', 200);
      }),
    );
    expect(
      await backend.riskGeoJson(travel: TravelType.emergency),
      contains('FeatureCollection'),
    );
    expect(url.queryParameters['user_class'], 'emergency');
    await expectLater(
      _backend(MockClient((_) async => http.Response('', 500)))
          .riskGeoJson(travel: TravelType.commuter),
      throwsA(isA<RoutingException>()),
    );
  });

  test('warmUp checks /health', () async {
    var path = '';
    await _backend(
      MockClient((req) async {
        path = req.url.path;
        return http.Response('{"status":"ok"}', 200);
      }),
    ).warmUp();
    expect(path, '/health');
    await expectLater(
      _backend(MockClient((_) async => http.Response('', 502))).warmUp(),
      throwsA(isA<RoutingException>()),
    );
  });
}
