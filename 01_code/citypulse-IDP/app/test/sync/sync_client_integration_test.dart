// T5.4 -- outbox sync exactly-once / resume-after-failure integration test
// (`docs/IMPLEMENTATION_PLAN.md` T5.4's acceptance criterion, verbatim:
// "an integration test that kills connectivity mid-report, restores it, and
// asserts exactly-once arrival and unchanged local state").
//
// This is the **real-server** variant of that test: it launches T5.3's
// actual FastAPI app (`server/app/main.py`) as a subprocess via uvicorn from
// the repo's `.venv`, forced onto the in-memory backend (`SUPABASE_URL`
// cleared), and drives `SyncClient` against it over real HTTP on
// 127.0.0.1. "Connectivity loss mid-report" is injected deterministically
// with a thin `http.BaseClient` wrapper that throws on the Nth call and
// forwards to a real `http.Client` afterwards -- actually severing a live
// TCP connection at an exact, reproducible instant from a test isn't
// practical, so the fault is injected at the client's transport boundary
// instead, while every request that *does* go out still hits the real
// server process end to end. This is deliberately the stronger of the two
// options the task card allows ("if you can run this against a real local
// server instance ... that's the strongest version") given a working
// `.venv` with fastapi/uvicorn is already present in this repo
// (`server/requirements.txt`).
//
// If the local dev environment lacks a usable Python venv/uvicorn (e.g. a
// different machine than the one this was authored on), the test marks
// itself skipped rather than failing for an unrelated reason.
import 'dart:convert';
import 'dart:io';

import 'package:citypulse_app/src/storage/hazard_cache.dart';
import 'package:citypulse_app/src/sync/hlc.dart';
import 'package:citypulse_app/src/sync/sync_client.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Wraps a real [http.Client], throwing a simulated connectivity failure on
/// the first [failFirstN] calls to [send] and forwarding to [_inner] for
/// every call after that. This is what makes "kill connectivity mid-report,
/// then restore it" deterministic in a test: the *n*th request never
/// reaches the network layer, so nothing is sent and nothing the server
/// could have received -- the fault is unambiguously "before send", not a
/// race with a real dropped socket.
class _FlakyOnceClient extends http.BaseClient {
  _FlakyOnceClient(this._inner, {required this.failFirstN});

  final http.Client _inner;
  final int failFirstN;
  int _calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _calls += 1;
    if (_calls <= failFirstN) {
      throw const SocketException(
        'simulated connectivity loss (test double, _FlakyOnceClient)',
      );
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Locates the repo-root-relative `.venv` Python executable and `server/`
/// directory, assuming `flutter test` runs with its cwd at the `app/`
/// package root (the standard invocation, and what
/// `docs/IMPLEMENTATION_PLAN.md`'s own task brief assumes elsewhere in this
/// suite).
({String python, String serverDir})? _locatePythonServer() {
  final appDir = Directory.current.path;
  final repoRoot = p.dirname(appDir);
  final python = p.join(repoRoot, '.venv', 'Scripts', 'python.exe');
  final serverDir = p.join(repoRoot, 'server');
  if (!File(python).existsSync() || !Directory(serverDir).existsSync()) {
    return null;
  }
  return (python: python, serverDir: serverDir);
}

class _RunningServer {
  _RunningServer._(this._process, this.baseUri);

  final Process _process;
  final Uri baseUri;

  static Future<_RunningServer> start(String python, String serverDir) async {
    final port = await _findFreePort();
    final process = await Process.start(
      python,
      [
        '-m',
        'uvicorn',
        'app.main:app',
        '--host',
        '127.0.0.1',
        '--port',
        '$port',
        '--log-level',
        'warning',
      ],
      workingDirectory: serverDir,
      environment: {
        // Force the in-memory repository regardless of a developer's real
        // .env (mirrors server/conftest.py's own app_instance fixture) --
        // this test must never touch a real database.
        'SUPABASE_URL': '',
      },
    );
    // Drain stdout/stderr so uvicorn's own logging never blocks on a full
    // pipe buffer.
    process.stdout.transform(utf8.decoder).listen((_) {});
    process.stderr.transform(utf8.decoder).listen((_) {});

    final baseUri = Uri.parse('http://127.0.0.1:$port/');
    await _waitForHealth(baseUri);
    return _RunningServer._(process, baseUri);
  }

  static Future<void> _waitForHealth(Uri baseUri) async {
    final client = http.Client();
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final response = await client
              .get(baseUri.resolve('health'))
              .timeout(const Duration(seconds: 1));
          if (response.statusCode == 200) {
            return;
          }
        } on Exception {
          // Not up yet -- keep polling.
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      throw StateError(
        'server at $baseUri did not become healthy within the deadline',
      );
    } finally {
      client.close();
    }
  }

  Future<void> stop() async {
    _process.kill();
    await _process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return _process.exitCode;
      },
    );
  }
}

HazardObservationRecord _localReport({required String id}) {
  final at = DateTime.utc(2026, 9, 18, 6);
  return HazardObservationRecord(
    id: id,
    hazardClass: 'waterlogging',
    polarity: 1,
    lat: 13.0827,
    lon: 80.2707,
    accuracyM: 15,
    observedAt: at,
    receivedAt: at,
    sourceClass: 'crowd',
    sourceId: 'device-under-test',
    intensity: const {'depth_mm': 180},
    raw: const {'note': 'kotturpuram bridge approach, reported in-app'},
  );
}

void main() {
  group('SyncClient exactly-once push, against a real server subprocess', () {
    _RunningServer? server;
    HazardDatabase? db;
    HazardCache? cache;

    setUp(() async {
      final located = _locatePythonServer();
      if (located == null) {
        markTestSkipped(
          'no .venv/Scripts/python.exe + server/ found next to app/ -- '
          'skipping the real-server sync integration test',
        );
        return;
      }
      server = await _RunningServer.start(located.python, located.serverDir);
      db = HazardDatabase(NativeDatabase.memory());
      cache = HazardCache(db!);
    });

    tearDown(() async {
      await db?.close();
      await server?.stop();
    });

    test('kills connectivity mid-report, restores it, and arrives exactly '
        'once with unchanged local state in between', () async {
      if (server == null) {
        return;
      }
      // A real UUID -- the server's Pydantic model types `id: UUID`
      // (`server/app/models.py`), per CONTRACTS.md §1's own
      // "UUIDv7, client-generated" header note; the local Drift schema
      // stores it as plain text and does not itself enforce the format.
      const reportId = 'e8400000-0000-4000-8000-000000000001';
      final report = _localReport(id: reportId);

      await cache!.insertObservation(report);
      await cache!.enqueueOutbox(reportId);

      final clock = HybridLogicalClock(nodeId: 'test-device-1');
      final realHttp = http.Client();
      final flaky = _FlakyOnceClient(realHttp, failFirstN: 1);
      final syncClient = SyncClient(
        cache: cache!,
        baseUri: server!.baseUri,
        clock: clock,
        httpClient: flaky,
      );

      // --- Attempt 1: connectivity dies mid-report. ---
      final firstAttempt = await syncClient.pushOutbox();
      expect(firstAttempt.pushedCount, 0);
      expect(firstAttempt.failedCount, 1);

      // Local state must be unchanged: still pending, and the stored
      // observation itself untouched.
      final stillPending = await cache!.pendingOutbox();
      expect(stillPending.map((e) => e.observationId), [reportId]);
      expect(stillPending.single.syncedAt, isNull);

      final unchangedRecord = await cache!.observationById(reportId);
      expect(unchangedRecord, equals(report));

      // The server must not have received anything -- the fault was
      // injected before the request was ever sent.
      final serverStateAfterFailure = await realHttp.get(
        server!.baseUri.resolve('observations'),
      );
      final afterFailureIds = (jsonDecode(serverStateAfterFailure.body) as List)
          .cast<Map<String, dynamic>>()
          .map((o) => o['id'])
          .toList();
      expect(afterFailureIds, isNot(contains(reportId)));

      // --- Connectivity restored: retry. ---
      final secondAttempt = await syncClient.pushOutbox();
      expect(secondAttempt.pushedCount, 1);
      expect(secondAttempt.failedCount, 0);

      final afterSuccess = await cache!.pendingOutbox();
      expect(afterSuccess, isEmpty);

      // --- Exactly-once arrival at the server: not zero, not duplicated. ---
      final serverStateAfterSuccess = await realHttp.get(
        server!.baseUri.resolve('observations'),
      );
      final matching = (jsonDecode(serverStateAfterSuccess.body) as List)
          .cast<Map<String, dynamic>>()
          .where((o) => o['id'] == reportId)
          .toList();
      expect(
        matching,
        hasLength(1),
        reason: 'the server must have received this report exactly once',
      );

      // A third push pass (nothing pending) must be a safe no-op.
      final thirdAttempt = await syncClient.pushOutbox();
      expect(thirdAttempt.pushedCount, 0);
      expect(thirdAttempt.failedCount, 0);

      syncClient.close();
      realHttp.close();
    });

    test('pullSince inserts server-side observations idempotently', () async {
      if (server == null) {
        return;
      }
      // Seed the server directly (a "another device's report" stand-in)
      // via a plain client, independent of SyncClient.
      final seedHttp = http.Client();
      const remoteId = 'e8400000-0000-4000-8000-000000000002';
      final remotePayload = <String, dynamic>{
        'id': remoteId,
        'hazard_class': 'debris',
        'polarity': 1,
        'geometry': {
          'type': 'Point',
          'coordinates': [80.2, 13.05],
        },
        'accuracy_m': 20.0,
        'observed_at': DateTime.utc(2026, 9, 18, 5).toIso8601String(),
        'source_class': 'crowd',
        'source_id': 'another-device',
        'precision_state': 'exact',
      };
      final postResp = await seedHttp.post(
        server!.baseUri.resolve('observations'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(remotePayload),
      );
      expect(postResp.statusCode, 201);

      final clock = HybridLogicalClock(nodeId: 'test-device-2');
      final syncClient = SyncClient(
        cache: cache!,
        baseUri: server!.baseUri,
        clock: clock,
        httpClient: http.Client(),
      );

      final insertedFirst = await syncClient.pullSince(
        DateTime.utc(2026, 9, 18),
      );
      expect(insertedFirst, 1);

      final stored = await cache!.observationById(remoteId);
      expect(stored, isNotNull);
      expect(stored!.hazardClass, 'debris');

      // Pulling again must not duplicate -- insertObservation's G-Set
      // no-op (T5.2) means a second pull of the same observation inserts
      // nothing new.
      final insertedSecond = await syncClient.pullSince(
        DateTime.utc(2026, 9, 18),
      );
      expect(insertedSecond, 0);

      syncClient.close();
      seedHttp.close();
    });
  });
}
