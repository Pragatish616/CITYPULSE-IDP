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
      make()
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

  // ADR-029: a rain forecast may raise dry to watch. The rule was fixed before any forecast value was read; these tests pin
  // the behaviour, not any claim that the forecast is skilful.
  group('the forecast (ADR-029)', () {
    final t0 = DateTime.utc(2026, 10, 8, 12);
    late DateTime clock;
    late List<EventState> applied;

    /// A forecast fetched at [fetchedAt] (default: now) with [rain] mm (area mean) at the given hour offsets from 12:00.
    ForecastSignal fc({
      Map<int, double> rain = const {},
      DateTime? fetchedAt,
      bool stale = false,
      int first = -3,
      int last = 24,
    }) => ForecastSignal(
      fetchedAt: fetchedAt ?? clock,
      model: 'ecmwf_ifs025',
      stale: stale,
      hourly: [
        for (var h = first; h <= last; h++)
          (time: t0.add(Duration(hours: h)), mm: rain[h] ?? 0),
      ],
    );

    EventStateController make({bool forecast = true}) => EventStateController(
      configured: EventState.active,
      hasRainSource: true,
      hasForecastSource: forecast,
      apply: applied.add,
      now: () => clock,
    );

    setUp(() {
      clock = t0;
      applied = [];
    });

    test('the shared rule vectors (the Python copy reads the same file)', () {
      final doc = jsonDecode(
        File('test/fixtures/forecast_rule_vectors.json').readAsStringSync(),
      ) as Map<String, Object?>;
      expect(
        doc['watch_accumulation_mm'],
        EventRule.forecastWatchAccumulationMm,
      );
      expect(doc['horizon_hours'], EventRule.forecastHorizon.inHours);
      for (final v in (doc['vectors']! as List).cast<Map<String, Object?>>()) {
        final f = ForecastSignal.fromJson({
          'fetched_at': v['t'],
          'model': 'test',
          'hourly': v['hourly'],
        });
        final look = EventRule.forecastAhead(
          f,
          DateTime.parse(v['t']! as String),
        );
        expect(look.level?.name, v['level'], reason: '${v['name']}');
        if (v['max'] != null) {
          expect(
            look.maxMm,
            closeTo(v['max']! as num, 1e-9),
            reason: '${v['name']}',
          );
        }
      }
    });

    test('fromJson refuses a broken answer instead of reading zeros', () {
      final good = {
        'fetched_at': '2026-10-08T12:00:00Z',
        'model': 'ecmwf_ifs025',
        'hourly': [
          {'time': '2026-10-08T13:00:00Z', 'area_mean_mm': 1.5},
        ],
      };
      expect(ForecastSignal.fromJson(good).hourly.single.mm, 1.5);
      for (final bad in [
        {...good, 'fetched_at': 'nope'},
        {...good, 'hourly': <Object>[]},
        {
          ...good,
          'hourly': [
            {'time': '2026-10-08T13:00:00Z', 'area_mean_mm': -1},
          ],
        },
        {
          ...good,
          'hourly': [
            {'time': 'x', 'area_mean_mm': 1},
          ],
        },
        {
          ...good,
          'hourly': [
            {'time': '2026-10-08T13:00:00Z'},
          ],
        },
      ]) {
        expect(() => ForecastSignal.fromJson(bad), throwsFormatException);
      }
    });

    test(
      'switched off, a wet forecast changes nothing and is not reported',
      () {
        final c = make(forecast: false)
          ..onRain(rain(asOf: t0))
          ..onForecast(fc(rain: {3: 4, 4: 4, 5: 4}));
        final s = c.status();
        expect((s.state, s.source), (EventState.dry, 'rain'));
        expect(s.toJson().containsKey('forecast'), isFalse);
      },
    );

    test(
      'a wet forecast raises dry to watch and says why, with the numbers',
      () {
        final c = make()
          ..onRain(rain(asOf: t0))
          ..onForecast(fc(rain: {3: 4, 4: 4, 5: 1}));
        final s = c.status();
        expect(
          (s.state, s.mode, s.source),
          (EventState.watch, 'auto', 'forecast'),
        );
        expect(s.reason, contains('Raised to watch by the rain forecast'));
        expect(
          s.reason,
          contains('9.0 mm expected in the 3 hours to 2026-10-08 17:00 UTC'),
        );
        expect(s.reason, contains('Without the forecast: Satellite rain'));
        final j = s.toJson()['forecast']! as Map<String, Object?>;
        expect(j['trusted'], isTrue);
        expect(j['level'], 'watch');
        expect(j['max_3h_area_mean_mm_next_12h'], 9.0);
        expect(applied, [EventState.active, EventState.dry, EventState.watch]);
      },
    );

    test('a dry forecast leaves dry alone', () {
      final c = make()
        ..onRain(rain(asOf: t0))
        ..onForecast(fc(rain: {3: 2, 4: 2, 5: 2}));
      expect((c.status().state, c.status().source), (EventState.dry, 'rain'));
    });

    test(
      'a forecast never raises above watch and never lowers the rain rule',
      () {
        final c = make()
          ..onRain(rain(acc: 20, asOf: t0))
          ..onForecast(fc());
        expect(
          (c.status().state, c.status().source),
          (EventState.active, 'rain'),
        );
        c.onForecast(fc(rain: {1: 50, 2: 50, 3: 50}));
        expect(c.status().state, EventState.active);
      },
    );

    test(
      'a forecast fetched more than 6 hours ago, or flagged stale, is ignored',
      () {
        final c = make()
          ..onRain(rain(asOf: t0))
          ..onForecast(
            fc(
              rain: {8: 4, 9: 4, 10: 4},
              fetchedAt: t0.subtract(const Duration(hours: 6, minutes: 1)),
            ),
          );
        expect(c.status().state, EventState.dry);
        expect((c.status().toJson()['forecast']! as Map)['trusted'], isFalse);
        c.onForecast(fc(rain: {8: 4, 9: 4, 10: 4}, stale: true));
        expect(c.status().state, EventState.dry);
        c.onForecast(fc(rain: {8: 4, 9: 4, 10: 4}));
        expect(c.status().state, EventState.watch);
      },
    );

    test('too few hours ahead gives no answer, so the forecast is ignored', () {
      final c = make()
        ..onRain(rain(asOf: t0))
        ..onForecast(fc(rain: {2: 5, 3: 5, 4: 5}, last: 8));
      expect(c.status().state, EventState.dry);
      final j = c.status().toJson()['forecast']! as Map<String, Object?>;
      expect(
        (j['trusted'], j['level'], j['hours_present_next_12h']),
        (false, null, 8),
      );
    });

    test('the look-ahead moves with the clock between polls', () {
      final c = make()
        ..onRain(rain(asOf: t0))
        ..onForecast(fc(rain: {14: 4, 15: 4, 16: 4}));
      expect(c.status().state, EventState.dry, reason: 'rain is 14-16 h away');
      clock = t0.add(const Duration(hours: 4));
      c.refresh();
      expect(
        c.status().state,
        EventState.watch,
        reason: 'now it is 10-12 h away',
      );
      clock = t0.add(const Duration(hours: 17));
      c.onRain(rain(asOf: clock));
      expect(
        c.status().state,
        EventState.dry,
        reason: 'the forecast rain has passed',
      );
    });

    test('an operator override beats the forecast', () {
      final c = make()
        ..onRain(rain(asOf: t0))
        ..onForecast(fc(rain: {3: 4, 4: 4, 5: 4}))
        ..setManual(EventState.dry);
      expect((c.status().state, c.status().source), (EventState.dry, 'manual'));
    });

    test('a failed forecast poll never triggers the configured fallback', () {
      final c = make()
        ..onRain(rain(asOf: t0))
        ..onForecastFailure(const SocketException('down'));
      final s = c.status();
      expect((s.state, s.source), (EventState.dry, 'rain'));
      final j = s.toJson()['forecast']! as Map<String, Object?>;
      expect((j['trusted'], j['last_poll_failed']), (false, 'SocketException'));
    });

    test('the forecast can raise the configured fallback when that is dry', () {
      final c = EventStateController(
        configured: EventState.dry,
        hasRainSource: true,
        hasForecastSource: true,
        apply: applied.add,
        now: () => clock,
      )..onForecast(fc(rain: {3: 4, 4: 4, 5: 4}));
      final s = c.status();
      expect((s.state, s.source), (EventState.watch, 'forecast'));
      expect(s.reason, contains('Without the forecast: No rain reading'));
    });

    test(
      'the poller reads /context/forecast; a bad answer is a failed poll',
      () async {
        final c = make()..onRain(rain(asOf: t0));
        final calls = <Uri>[];
        Map<String, Object?> body() => {
          'fetched_at': '2026-10-08T12:00:00Z',
          'model': 'ecmwf_ifs025',
          'stale': false,
          'hourly': [
            for (var h = 1; h <= 12; h++)
              {
                'time': t0.add(Duration(hours: h)).toIso8601String(),
                'area_mean_mm': h == 2 || h == 3 || h == 4 ? 3.0 : 0.0,
              },
          ],
        };
        final ok = await ForecastSync(
          baseUrl: Uri.parse('http://report:8000/'),
          controller: c,
          client: MockClient((req) async {
            calls.add(req.url);
            return http.Response(jsonEncode(body()), 200);
          }),
        ).syncOnce();
        expect(ok, isTrue);
        expect(calls.single.toString(), 'http://report:8000/context/forecast');
        expect(c.status().state, EventState.watch);
        for (final client in [
          MockClient((_) async => http.Response('{"detail":"x"}', 503)),
          MockClient((_) async => http.Response('not json', 200)),
          MockClient((_) async => throw http.ClientException('offline')),
        ]) {
          expect(
            await ForecastSync(
              baseUrl: Uri.parse('http://r/'),
              controller: c,
              client: client,
            ).syncOnce(),
            isFalse,
          );
        }
        // The last good forecast is kept after failed polls.
        expect(c.status().state, EventState.watch);
      },
    );
  });
}
