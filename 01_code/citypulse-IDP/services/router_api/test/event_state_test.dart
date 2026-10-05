// ADR-027: the event state follows satellite rain by default, with a human override.
// The rule's numbers are placeholders fixed in the ADR before any trial; these tests pin the BEHAVIOUR (thresholds as written, holds,
// fallback, override), not any claim that the numbers suit Chennai.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:router_api/router_api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

RainSignal rain({
  double acc = 0,
  double peak = 0,
  DateTime? asOf,
  bool stale = false,
  double ageMin = 360,
  int missing = 0,
}) => RainSignal(
  asOf: asOf ?? DateTime.utc(2026, 10, 5, 9, 30),
  dataAgeMinutes: ageMin,
  stale: stale,
  accumulationMm: acc,
  peakRateMmH: peak,
  nowPeakMmH: peak,
  intensityClass: 'none',
  slicesMissing: missing,
);

void main() {
  group('RainSignal.fromJson', () {
    Map<String, Object?> good() => {
      'as_of': '2026-10-05T10:30:00Z',
      'data_age_minutes': 357,
      'stale': false,
      'now': {'intensity_class': 'none', 'peak_rate_mm_h': 0.0},
      'recent': {
        'slices_used': 6,
        'slices_missing': 0,
        'area_mean_accumulation_mm': 0.03,
        'peak_rate_mm_h': 0.31,
      },
    };

    test('reads the report server answer', () {
      final s = RainSignal.fromJson(good());
      expect(s.asOf, DateTime.utc(2026, 10, 5, 10, 30));
      expect(s.accumulationMm, 0.03);
      expect(s.peakRateMmH, 0.31);
      expect(s.stale, isFalse);
    });

    test('a missing or broken field is a failure, never a silent zero', () {
      for (final bad in [
        {...good()}..remove('as_of'),
        {...good()}..['recent'] = {'slices_used': 0},
        {...good()}
          ..['recent'] = {
            'slices_used': 6,
            'area_mean_accumulation_mm': -1,
            'peak_rate_mm_h': 0,
          },
        {...good()}..['now'] = 'x',
      ]) {
        expect(
          () => RainSignal.fromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });
  });

  group('the rule (ADR-027)', () {
    test('thresholds are as written, at and either side of each edge', () {
      EventState lv(double acc, double peak) =>
          EventRule.levelOf(rain(acc: acc, peak: peak));
      expect(lv(0, 0), EventState.dry);
      expect(lv(7.99, 7.59), EventState.dry);
      expect(lv(8, 0), EventState.watch);
      expect(lv(0, 7.6), EventState.watch);
      expect(lv(14.99, 24.99), EventState.watch);
      expect(lv(15, 0), EventState.active);
      expect(lv(0, 25), EventState.active);
      expect(lv(100, 100), EventState.active);
    });
  });

  group('the controller', () {
    late DateTime clock;
    late List<EventState> applied;
    DateTime now() => clock;

    EventStateController make({
      bool source = true,
      EventState configured = EventState.active,
    }) => EventStateController(
      configured: configured,
      hasRainSource: source,
      apply: applied.add,
      now: now,
    );

    setUp(() {
      clock = DateTime.utc(2026, 10, 5, 16);
      applied = [];
    });

    test(
      'with no rain source it keeps the configured state, as before ADR-027',
      () {
        final c = make(source: false, configured: EventState.watch);
        final s = c.status();
        expect(
          (s.state, s.mode, s.source),
          (EventState.watch, 'fixed', 'configured'),
        );
        expect(c.resumeAuto(), isFalse, reason: 'nothing to return to');
      },
    );

    test(
      'before the first reading it uses the configured state and says so',
      () {
        final c = make();
        final s = c.status();
        expect(
          (s.state, s.mode, s.source),
          (EventState.active, 'auto', 'fallback'),
        );
        expect(s.reason, contains('No rain reading has been received yet'));
        expect(applied, [EventState.active]);
      },
    );

    test('a dry reading gives dry, from the rain', () {
      final c = make()..onRain(rain(acc: 0.03, peak: 0.31));
      final s = c.status();
      expect((s.state, s.source), (EventState.dry, 'rain'));
      expect(s.reason, contains('0.0 mm in the last 3 h'));
      expect(s.rain?.peakRateMmH, 0.31);
      expect(applied, [EventState.active, EventState.dry]);
    });

    test(
      'a watch reading holds for 12 hours from when it was seen, then drops',
      () {
        final c = make()
          ..onRain(rain(acc: 9, asOf: DateTime.utc(2026, 10, 5, 10)));
        expect(c.status().state, EventState.watch);
        // later readings are dry and have new satellite times
        for (var h = 1; h <= 11; h++) {
          clock = DateTime.utc(2026, 10, 5, 16).add(Duration(hours: h));
          c.onRain(
            rain(asOf: DateTime.utc(2026, 10, 5, 10).add(Duration(hours: h))),
          );
          expect(c.status().state, EventState.watch, reason: 'hour $h');
        }
        clock = DateTime.utc(
          2026,
          10,
          5,
          16,
          0,
        ).add(const Duration(hours: 12, minutes: 1));
        c.onRain(rain(asOf: DateTime.utc(2026, 10, 6, 5)));
        expect(c.status().state, EventState.dry);
      },
    );

    test(
      'an active reading holds 6 hours, then watch until 12 hours, then dry',
      () {
        final c = make()
          ..onRain(rain(acc: 20, asOf: DateTime.utc(2026, 10, 5, 10)));
        expect(c.status().state, EventState.active);
        clock = DateTime.utc(2026, 10, 5, 21, 59);
        c.onRain(rain(asOf: DateTime.utc(2026, 10, 5, 15)));
        expect(c.status().state, EventState.active);
        clock = DateTime.utc(2026, 10, 5, 22, 1);
        c.onRain(rain(asOf: DateTime.utc(2026, 10, 5, 16)));
        expect(c.status().state, EventState.watch);
        clock = DateTime.utc(2026, 10, 6, 4, 1);
        c.onRain(rain(asOf: DateTime.utc(2026, 10, 5, 22)));
        expect(c.status().state, EventState.dry);
      },
    );

    test(
      'polling the same old image again does not keep an old reading alive',
      () {
        final c = make()
          ..onRain(rain(acc: 9, asOf: DateTime.utc(2026, 10, 5, 10)));
        for (var m = 15; m <= 12 * 60 + 15; m += 15) {
          clock = DateTime.utc(2026, 10, 5, 16).add(Duration(minutes: m));
          c.onRain(
            rain(acc: 9, asOf: DateTime.utc(2026, 10, 5, 10), stale: false),
          );
        }
        // 12 h 15 min after first seen: the same image was re-polled all along, but the hold ran from the first time.
        expect(c.status().state, EventState.dry);
      },
    );

    test('a stale reading is not trusted: the configured state applies', () {
      final c = make(configured: EventState.watch)
        ..onRain(rain(acc: 0, stale: true, ageMin: 900));
      final s = c.status();
      expect((s.state, s.source), (EventState.watch, 'fallback'));
      expect(s.reason, contains('older than 12 hours'));
    });

    test('failed polls keep the last reading until it is 12 hours without a success', () {
      final c = make()..onRain(rain());
      clock = clock.add(const Duration(hours: 11));
      c.onRainFailure(const SocketException('down'));
      expect(c.status().source, 'rain');
      clock = clock.add(const Duration(hours: 2));
      c.onRainFailure(const SocketException('down'));
      final s = c.status();
      expect((s.state, s.source), (EventState.active, 'fallback'));
      expect(s.reason, contains('last poll failed: SocketException'));
    });

    test(
      'an operator override wins, shows who and until when, and can be cleared',
      () {
        final c = make()..onRain(rain(acc: 20));
        expect(c.status().state, EventState.active);
        c.setManual(EventState.dry);
        var s = c.status();
        expect(
          (s.state, s.mode, s.source),
          (EventState.dry, 'manual', 'manual'),
        );
        expect(s.reason, contains('Set by an operator'));
        c.onRain(rain(acc: 50, asOf: DateTime.utc(2026, 10, 5, 12)));
        expect(
          c.status().state,
          EventState.dry,
          reason: 'rain does not beat an override',
        );
        expect(c.resumeAuto(), isTrue);
        s = c.status();
        expect(
          (s.state, s.mode, s.source),
          (EventState.active, 'auto', 'rain'),
        );
      },
    );

    test(
      'a time-limited override ends by itself and the rain rule takes over',
      () {
        final c = make()..onRain(rain());
        c.setManual(EventState.active, hold: const Duration(hours: 2));
        expect(c.status().state, EventState.active);
        expect(c.status().manualUntil, DateTime.utc(2026, 10, 5, 18));
        clock = DateTime.utc(2026, 10, 5, 18, 1);
        final s = c.status();
        expect((s.state, s.mode), (EventState.dry, 'auto'));
      },
    );

    test('apply is called only when the state changes', () {
      final c = make()
        ..onRain(rain())
        ..onRain(rain(asOf: DateTime.utc(2026, 10, 5, 10)))
        ..refresh();
      expect(applied, [EventState.active, EventState.dry]);
    });
  });

  group('the rain poller', () {
    Map<String, Object?> body(double acc) => {
      'as_of': '2026-10-05T10:30:00Z',
      'data_age_minutes': 300,
      'stale': false,
      'now': {'intensity_class': 'moderate', 'peak_rate_mm_h': 3.0},
      'recent': {
        'slices_used': 6,
        'area_mean_accumulation_mm': acc,
        'peak_rate_mm_h': 3.0,
      },
    };

    test('a good answer is passed to the controller', () async {
      final c = EventStateController(
        configured: EventState.active,
        hasRainSource: true,
        apply: (_) {},
      );
      final calls = <Uri>[];
      final sync = RainSync(
        baseUrl: Uri.parse('http://report:8000/'),
        controller: c,
        client: MockClient((req) async {
          calls.add(req.url);
          return http.Response(jsonEncode(body(9)), 200);
        }),
      );
      await sync.syncOnce();
      expect(calls.single.toString(), 'http://report:8000/context/rain');
      expect(c.status().state, EventState.watch);
    });

    test('an error status, bad JSON and a network error each count as a failed poll', () async {
      for (final client in [
        MockClient((_) async => http.Response('{"detail":"x"}', 503)),
        MockClient((_) async => http.Response('not json', 200)),
        MockClient((_) async => throw http.ClientException('offline')),
        MockClient((_) async => http.Response('{"as_of":"nope"}', 200)),
      ]) {
        final c = EventStateController(
          configured: EventState.watch,
          hasRainSource: true,
          apply: (_) {},
        );
        await RainSync(
          baseUrl: Uri.parse('http://r/'),
          controller: c,
          client: client,
        ).syncOnce();
        final s = c.status();
        expect((s.state, s.source), (EventState.watch, 'fallback'));
      }
    });
  });

  group('the HTTP surface', () {
    late MapPack pack;
    late RoutingEngine engine;
    late EventStateController events;
    late Handler handler;

    ByteData read(String name) => ByteData.sublistView(
      File('../../data/packs/2026-10-02/$name').readAsBytesSync(),
    );

    setUpAll(() {
      pack = MapPack.parse(
        graph: read('graph.bin'),
        nodes: read('nodes.bin'),
        meta: read('meta.bin'),
      );
    });

    setUp(() {
      final cfg = EngineConfig.fromMap(
        loadYaml(File('../../config/hazard_classes.yaml').readAsStringSync())
            as YamlMap,
      );
      engine = RoutingEngine(
        pack: pack,
        snapper: EdgeSnapper(pack),
        hazardClasses: cfg.hazardClasses,
        userClasses: cfg.userClasses,
        travelProfiles: cfg.travelProfiles,
        sourceReliability: cfg.sourceReliability,
        eventState: EventState.active,
      );
      events = EventStateController(
        configured: EventState.active,
        hasRainSource: true,
        apply: (s) => engine.eventState = s,
      );
      handler = buildHandler(
        engine,
        config: const ApiConfig(adminToken: 's3cret'),
        events: events,
      );
    });

    Future<Response> call(
      String method,
      String path, {
      Object? body,
      bool admin = false,
    }) => Future.sync(
      () => handler(
        Request(
          method,
          Uri.parse('http://localhost$path'),
          body: body == null ? null : jsonEncode(body),
          headers: {if (admin) 'x-admin-token': 's3cret'},
        ),
      ),
    );

    Future<Map<String, Object?>> json(Response r) async =>
        jsonDecode(await r.readAsString()) as Map<String, Object?>;

    test(
      'GET says the state, the mode, the source, why, and the rain behind it',
      () async {
        events.onRain(rain(acc: 0.03, peak: 0.31));
        final r = await call('GET', '/event-state');
        expect(r.statusCode, 200);
        final j = await json(r);
        expect(j['event_state'], 'dry');
        expect(j['mode'], 'auto');
        expect(j['source'], 'rain');
        expect(j['reason'], contains('Satellite rain'));
        expect((j['rain']! as Map)['accumulation_3h_mm'], 0.03);
        expect(
          engine.eventState,
          EventState.dry,
          reason: 'the engine follows the controller',
        );
      },
    );

    test(
      'PUT overrides, with optional hours, and the engine follows',
      () async {
        events.onRain(rain());
        final r = await call(
          'PUT',
          '/event-state',
          body: {'event_state': 'watch', 'hours': 3},
          admin: true,
        );
        expect(r.statusCode, 200);
        final j = await json(r);
        expect((j['event_state'], j['mode']), ('watch', 'manual'));
        expect(j['override_until'], isNotNull);
        expect(engine.eventState, EventState.watch);
      },
    );

    test('PUT {"mode": "auto"} returns to the rain rule', () async {
      events.onRain(rain());
      await call(
        'PUT',
        '/event-state',
        body: {'event_state': 'active'},
        admin: true,
      );
      final r = await call(
        'PUT',
        '/event-state',
        body: {'mode': 'auto'},
        admin: true,
      );
      expect(r.statusCode, 200);
      expect((await json(r))['mode'], 'auto');
      expect(engine.eventState, EventState.dry);
    });

    test(
      'the override still needs the admin token, and bad input is refused',
      () async {
        expect(
          (await call(
            'PUT',
            '/event-state',
            body: {'event_state': 'dry'},
          )).statusCode,
          401,
        );
        expect(
          (await call(
            'PUT',
            '/event-state',
            body: {'mode': 'auto'},
          )).statusCode,
          401,
        );
        expect(
          (await call(
            'PUT',
            '/event-state',
            body: {'event_state': 'dry', 'hours': -1},
            admin: true,
          )).statusCode,
          400,
        );
        expect(
          (await call(
            'PUT',
            '/event-state',
            body: {'event_state': 'dry', 'hours': 99999},
            admin: true,
          )).statusCode,
          400,
        );
        expect(
          (await call(
            'PUT',
            '/event-state',
            body: {'event_state': 'storm'},
            admin: true,
          )).statusCode,
          400,
        );
        expect(
          events.status().mode,
          'auto',
          reason: 'nothing above changed it',
        );
      },
    );

    test(
      'with no rain source, "auto" is refused and an override still works',
      () async {
        final fixed = EventStateController(
          configured: EventState.active,
          hasRainSource: false,
          apply: (s) => engine.eventState = s,
        );
        final h = buildHandler(
          engine,
          config: const ApiConfig(adminToken: 's3cret'),
          events: fixed,
        );
        Future<Response> put(Object body) => Future.sync(
          () => h(
            Request(
              'PUT',
              Uri.parse('http://localhost/event-state'),
              body: jsonEncode(body),
              headers: {'x-admin-token': 's3cret'},
            ),
          ),
        );
        expect((await put({'mode': 'auto'})).statusCode, 400);
        expect((await put({'event_state': 'dry'})).statusCode, 200);
        expect(engine.eventState, EventState.dry);
      },
    );
  });
}
