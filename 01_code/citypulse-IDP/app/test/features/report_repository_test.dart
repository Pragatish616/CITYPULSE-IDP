import 'dart:convert';

import 'package:citypulse_app/src/features/report/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_router/pulse_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/harness.dart';

const _point = (lat: 13.041872, lon: 80.234119);

Future<
  ({
    ReportRepository repo,
    SharedPreferences prefs,
    List<EngineObservation> accepted,
  })
>
_make(MockClient client) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final accepted = <EngineObservation>[];
  final repo = ReportRepository(
    ingestUrl: 'http://ingest.test/',
    prefs: prefs,
    installId: () => 'install-abc',
    client: client,
    clock: () => kTestNow,
    onAccepted: accepted.add,
  );
  return (repo: repo, prefs: prefs, accepted: accepted);
}

void main() {
  group('the report as sent', () {
    late ReportRepository repo;
    setUp(() async {
      repo = (await _make(MockClient((_) async => http.Response('{}', 201))))
          .repo;
    });

    test('follows docs/CONTRACTS.md §1 and carries nothing identifying: '
        'rounded position, random install code, no free text', () {
      final wire = repo.toWire(
        const ReportDraft(
          kind: ReportKind.flooded,
          depth: DepthBand.knee,
          point: _point,
        ),
      );
      expect(wire.keys.toSet(), {
        'id',
        'hazard_class',
        'polarity',
        'geometry',
        'accuracy_m',
        'observed_at',
        'source_class',
        'source_id',
        'intensity',
      });
      expect(wire['hazard_class'], 'flood');
      expect(wire['polarity'], 1);
      expect(wire['source_class'], 'crowd');
      expect(wire['source_id'], 'install:install-abc');
      expect(wire['observed_at'], '2026-10-02T06:00:00.000Z');
      // ~10 m: four decimal places, longitude first (GeoJSON).
      expect((wire['geometry']! as Map)['coordinates'], [80.2341, 13.0419]);
      expect(wire['intensity'], {'depth_mm': 450, 'estimated_by': 'user'});
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(wire['id']! as String),
        isTrue,
        reason: 'UUID v7',
      );
    });

    test('kinds map to hazard class and polarity; depth is dropped when the '
        'water has cleared or the depth is unknown', () {
      Map<String, Object?> w(ReportKind k, DepthBand d) =>
          repo.toWire(ReportDraft(kind: k, depth: d, point: _point));
      expect(
        w(ReportKind.standing, DepthBand.ankle)['hazard_class'],
        'waterlogging',
      );
      expect(w(ReportKind.standing, DepthBand.ankle)['intensity'], {
        'depth_mm': 100,
        'estimated_by': 'user',
      });
      final cleared = w(ReportKind.cleared, DepthBand.above);
      expect(cleared['polarity'], -1);
      expect(cleared.containsKey('intensity'), isFalse);
      expect(
        w(ReportKind.flooded, DepthBand.unknown).containsKey('intensity'),
        isFalse,
      );
    });

    test('every id is unique', () {
      const d = ReportDraft(
        kind: ReportKind.flooded,
        depth: DepthBand.unknown,
        point: _point,
      );
      expect({for (var i = 0; i < 50; i++) repo.toWire(d)['id']}.length, 50);
    });

    test('the wire form parses back into an engine observation', () {
      final wire = repo.toWire(
        const ReportDraft(
          kind: ReportKind.flooded,
          depth: DepthBand.knee,
          point: _point,
        ),
      );
      final obs = EngineObservation.tryParseWire(jsonDecode(jsonEncode(wire)));
      expect(obs, isNotNull);
      expect(obs!.depthMm, 450);
      expect(obs.sourceClass, 'crowd');
      expect(obs.lat, closeTo(13.0419, 1e-9));
    });
  });

  group('sending', () {
    const draft = ReportDraft(
      kind: ReportKind.flooded,
      depth: DepthBand.ankle,
      point: _point,
    );

    test(
      'a 201 is `sent`, posted to /observations, and counted locally',
      () async {
        late http.Request seen;
        final m = await _make(
          MockClient((req) async {
            seen = req;
            return http.Response('{"inserted":true}', 201);
          }),
        );
        expect(await m.repo.submit(draft), SubmitStatus.sent);
        expect(seen.url.toString(), 'http://ingest.test/observations');
        expect(seen.headers['content-type'], contains('application/json'));
        expect(m.accepted, hasLength(1));
        expect(m.repo.pendingCount, 0);
      },
    );

    test('offline: the report is queued on the device and still counts '
        'locally straight away', () async {
      final m = await _make(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await m.repo.submit(draft), SubmitStatus.queued);
      expect(m.repo.pendingCount, 1);
      expect(m.accepted, hasLength(1));
    });

    test('the offline queue is capped, dropping the oldest report first',
        () async {
      final m = await _make(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      for (var i = 0; i < ReportRepository.maxQueued + 5; i++) {
        await m.repo.submit(draft);
      }
      expect(m.repo.pendingCount, ReportRepository.maxQueued);
    });

    test('a retry sends the same id again, so the server can ignore a repeat',
        () async {
      var online = false;
      final ids = <String>[];
      final m = await _make(
        MockClient((req) async {
          if (!online) throw http.ClientException('offline');
          ids.add((jsonDecode(req.body) as Map)['id'] as String);
          return http.Response('{}', 201);
        }),
      );
      await m.repo.submit(draft);
      online = true;
      await m.repo.flushQueue();
      await m.repo.submit(draft);
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2), reason: 'distinct reports, distinct ids');
    });

    test('a 5xx is queued; a 4xx is `rejected` and neither queued nor '
        'counted', () async {
      final server = await _make(
        MockClient((_) async => http.Response('', 503)),
      );
      expect(await server.repo.submit(draft), SubmitStatus.queued);

      final bad = await _make(
        MockClient((_) async => http.Response('{"detail":"invalid"}', 422)),
      );
      expect(await bad.repo.submit(draft), SubmitStatus.rejected);
      expect(bad.repo.pendingCount, 0);
      expect(bad.accepted, isEmpty);
    });

    test('flushQueue delivers queued reports once the server is back, keeps '
        'the ones it still cannot send, and drops rejected ones', () async {
      var online = false;
      var rejectNext = false;
      final bodies = <String>[];
      final m = await _make(
        MockClient((req) async {
          if (!online) throw http.ClientException('offline');
          bodies.add(req.body);
          return rejectNext ? http.Response('', 422) : http.Response('{}', 201);
        }),
      );
      await m.repo.submit(draft);
      await m.repo.submit(draft);
      expect(m.repo.pendingCount, 2);

      expect(await m.repo.flushQueue(), 0, reason: 'still offline');
      expect(m.repo.pendingCount, 2);

      online = true;
      expect(await m.repo.flushQueue(), 2);
      expect(m.repo.pendingCount, 0);
      expect(bodies, hasLength(2));
      expect(
        bodies.toSet(),
        hasLength(2),
        reason: 'two distinct reports, ids intact',
      );

      online = false;
      await m.repo.submit(draft);
      online = true;
      rejectNext = true;
      expect(await m.repo.flushQueue(), 0);
      expect(
        m.repo.pendingCount,
        0,
        reason: 'a rejected report is not retried forever',
      );
    });

    test('a timeout is treated as offline', () async {
      final m = await _make(
        MockClient(
          (_) => Future<http.Response>.delayed(
            const Duration(seconds: 1),
            () => http.Response('{}', 201),
          ),
        ),
      );
      final repo = ReportRepository(
        ingestUrl: 'http://ingest.test',
        prefs: m.prefs,
        installId: () => 'x',
        client: MockClient(
          (_) => Future<http.Response>.delayed(
            const Duration(seconds: 1),
            () => http.Response('{}', 201),
          ),
        ),
        clock: () => kTestNow,
        timeout: const Duration(milliseconds: 20),
      );
      expect(await repo.submit(draft), SubmitStatus.queued);
    });
  });
}
