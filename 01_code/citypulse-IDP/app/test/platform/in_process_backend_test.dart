// Runs the real engine, in-process, on the real bundled pack -- the offline
// path. Needs `app/assets/packs/` (run scripts/sync_data_assets.sh).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:citypulse_app/src/domain/models.dart';
import 'package:citypulse_app/src/platform/engine_host.dart';
import 'package:citypulse_app/src/platform/in_process_backend.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_router/pulse_router.dart';

import '../helpers/harness.dart';

class _MissingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => throw FlutterError('no asset $key');
}

// T. Nagar (Panagal Park) -> Velachery, the pair the old demo used.
const _from = (lat: 13.0419, lon: 80.2339);
const _to = (lat: 12.9806, lon: 80.2184);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InProcessBackend newBackend({
    Future<List<EngineObservation>> Function()? pull,
    Future<EventState> Function()? state,
  }) => InProcessBackend(
    bundle: rootBundle,
    clock: () => kTestNow,
    pullObservations: pull,
    pullEventState: state,
  );

  test('routes any origin and destination offline from the bundled pack, '
      'with a valid trace, a drawable path and a device label', () async {
    final backend = newBackend();
    await backend.warmUp();
    final view = await backend.route(
      from: _from,
      to: _to,
      travel: TravelType.commuter,
    );
    expect(view.computedOn, ComputeSite.device);
    expect(view.path.length, greaterThan(10));
    expect(view.trace.chosen.distanceMeters, greaterThan(3000));
    expect(view.computeMilliseconds, greaterThan(0));
    expect(view.travelMinutes, greaterThan(5));
  });

  test('the background isolate and the local engine give the same route '
      '(same code, same answer)', () async {
    final isolate = newBackend();
    final local = InProcessBackend(
      bundle: rootBundle,
      clock: () => kTestNow,
      hostFactory: (inputs) async => LocalEngineHost(inputs),
    );
    addTearDown(isolate.dispose);
    final a = await isolate.route(from: _from, to: _to, travel: TravelType.commuter);
    final b = await local.route(from: _from, to: _to, travel: TravelType.commuter);
    expect(a.path, b.path);
    // The query id and the compute time differ by design; everything else is equal.
    final ja = a.trace.toJson()..remove('query_id');
    final jb = b.trace.toJson()..remove('query_id');
    expect(jsonEncode(ja), jsonEncode(jb));
  });

  test('loading the pack and routing in the background leaves the main '
      "isolate's event loop free (no stall over 250 ms)", () async {
    // A 10 ms ticker on the main isolate: any long synchronous work here would
    // show up as one big gap between ticks. Desktop JIT numbers; the point is
    // that the parse (about 150 ms) and the search (150-650 ms) are not here.
    var last = DateTime.now();
    var worstGapMs = 0;
    final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final now = DateTime.now();
      final gap = now.difference(last).inMilliseconds;
      if (gap > worstGapMs) worstGapMs = gap;
      last = now;
    });
    final backend = newBackend();
    addTearDown(backend.dispose);
    await backend.warmUp();
    // Yield so the ticker gets a turn after each step; otherwise work done in
    // this isolate would finish inside microtasks and the stall would go
    // unseen (measured: the local engine stalls about 425 ms here, the
    // background one under 50 ms).
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await backend.route(from: _from, to: _to, travel: TravelType.commuter);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    ticker.cancel();
    expect(worstGapMs, lessThan(250), reason: 'worst gap $worstGapMs ms');
  });

  test(
    'typed failures for a point outside Chennai and for same place',
    () async {
      final backend = newBackend();
      await expectLater(
        backend.route(
          from: (lat: 0, lon: 0),
          to: _to,
          travel: TravelType.commuter,
        ),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingFailure.originOutside,
          ),
        ),
      );
      await expectLater(
        backend.route(
          from: _from,
          to: (lat: 0, lon: 0),
          travel: TravelType.commuter,
        ),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingFailure.destinationOutside,
          ),
        ),
      );
      await expectLater(
        backend.route(from: _from, to: _from, travel: TravelType.commuter),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingFailure.sameLocation,
          ),
        ),
      );
    },
  );

  test(
    'a missing pack is `notReady`, not a crash, and a later call retries',
    () async {
      final backend = InProcessBackend(bundle: _MissingBundle());
      await expectLater(
        backend.warmUp(),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingFailure.notReady,
          ),
        ),
      );
      await expectLater(
        backend.route(from: _from, to: _to, travel: TravelType.commuter),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingFailure.notReady,
          ),
        ),
      );
    },
  );

  test('street search works offline and orders by distance', () async {
    final backend = newBackend();
    final places = await backend.searchPlaces('usman road', near: _from);
    expect(places, isNotEmpty);
    expect(places.first.name.toLowerCase(), contains('usman road'));
    expect(places.first.detail, endsWith('km'));
    expect(await backend.searchPlaces('x'), isEmpty);
  });

  test('the risk overlay is GeoJSON for the hazard-map edges', () async {
    final json = await newBackend().riskGeoJson(travel: TravelType.pedestrian);
    expect(json, startsWith('{"type":"FeatureCollection"'));
    expect(json, contains('"p_pessimistic"'));
    expect(json.length, greaterThan(1000000));
  });

  test('on the device the overlay for a box is a fraction of the whole, computed '
      'in the background isolate, and is capped', () async {
    final backend = newBackend();
    addTearDown(backend.dispose);
    final whole = await backend.riskGeoJson(travel: TravelType.commuter);
    final box = await backend.riskGeoJson(
      travel: TravelType.commuter,
      bounds: (minLat: 13.00, minLon: 80.20, maxLat: 13.06, maxLon: 80.26),
    );
    expect(box.length, lessThan(whole.length / 3));
    expect(box, contains('"has_observation"'));
    expect(box, isNot(contains('"hazard_class"')), reason: 'compact form');
    final features = (jsonDecode(whole) as Map)['features'] as List;
    expect(features.length, lessThanOrEqualTo(8000), reason: 'the per-request cap');
  });

  test('reports pulled from the ingest server and the event state are '
      'applied; an offline server is ignored', () async {
    final backend = newBackend(
      pull: () async => throw Exception('offline'),
      state: () async => throw Exception('offline'),
    );
    await backend.warmUp();
    expect(
      await backend.eventState(),
      EventState.active,
      reason: 'cautious default',
    );

    final dry = newBackend(state: () async => EventState.dry);
    await dry.warmUp();
    expect(await dry.eventState(), EventState.dry);
    final view = await dry.route(
      from: _from,
      to: _to,
      travel: TravelType.emergency,
    );
    expect(view.eventState, EventState.dry);
    expect(view.trace.chosen.hazardTimePenaltySeconds, closeTo(0, 1e-6));
  });

  test('a report this device just made changes the next route, even with no '
      'network (the offline promise)', () async {
    final backend = newBackend(state: () async => EventState.dry);
    final before = await backend.route(
      from: _from,
      to: _to,
      travel: TravelType.commuter,
    );
    final mid = before.path.length ~/ 2;
    backend.addLocalObservation(
      EngineObservation(
        id: 'local-1',
        hazardClass: 'flood',
        polarity: 1,
        lat: (before.path[mid].lat + before.path[mid + 1].lat) / 2,
        lon: (before.path[mid].lon + before.path[mid + 1].lon) / 2,
        observedAt: kTestNow.subtract(const Duration(minutes: 5)),
        // A reliable source: a crowd depth alone does not close a road.
        sourceClass: 'municipal_sensor',
        depthMm: 450,
      ),
    );
    final after = await backend.route(
      from: _from,
      to: _to,
      travel: TravelType.commuter,
    );
    expect(after.detours, isTrue);
    expect(
      after.trace.alternatives.single.rejectedBecause,
      RejectedBecause.chanceConstraint,
    );
    expect(after.avoidedHazards, isNotEmpty);
  });
}
