/// Pulls reports from the FastAPI ingest server into the engine.
///
/// The FastAPI server (`server/`) owns the append-only observation log
/// (ADR-008); the router service only reads it. Adding an observation is
/// idempotent, so re-reading overlapping rows is safe. After the first pass
/// the poller asks only for rows the server *received* at or after the newest
/// `received_at` it has seen (KNOWN_FLAWS F-10): an offline report made hours
/// ago but uploaded now has a fresh `received_at`, which an `observed_at`
/// cursor would skip.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pulse_router/pulse_router.dart';

/// Result of one sync pass.
class SyncResult {
  /// Creates a result.
  const SyncResult({required this.fetched, required this.added, required this.skipped});

  /// Rows the server returned.
  final int fetched;

  /// Rows that were new to the engine and attached to at least one edge.
  final int added;

  /// Rows rejected as malformed or unknown (never fatal).
  final int skipped;
}

/// Polls `GET {baseUrl}/observations` and feeds the [engine].
class ObservationSync {
  /// Creates a poller. [client] is injectable for tests.
  ObservationSync({
    required this.engine,
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// The engine receiving observations.
  final RoutingEngine engine;

  /// The FastAPI server root, e.g. `http://localhost:8000`.
  final Uri baseUrl;
  final http.Client _client;
  Timer? _timer;

  /// Newest server `received_at` seen so far; `null` before the first pass.
  DateTime? _cursor;

  /// Fetches once. Network or parse failures throw; callers decide whether to
  /// retry ([start] swallows and logs them).
  Future<SyncResult> syncOnce() async {
    final cursor = _cursor;
    final uri = cursor == null
        ? baseUrl.resolve('observations')
        : baseUrl.resolve('observations').replace(
            queryParameters: {'received_since': cursor.toUtc().toIso8601String()},
          );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'GET /observations returned ${response.statusCode}',
        baseUrl,
      );
    }
    final rows = jsonDecode(response.body) as List<Object?>;
    var added = 0;
    var skipped = 0;
    var newest = cursor;
    for (final raw in rows) {
      if (raw is Map) {
        final received = DateTime.tryParse('${raw['received_at']}');
        if (received != null && (newest == null || received.isAfter(newest))) {
          newest = received;
        }
      }
      final obs = EngineObservation.tryParseWire(raw);
      if (obs == null) {
        skipped++;
        continue;
      }
      try {
        if (engine.addObservation(obs) > 0) added++;
      // ignore: avoid_catching_errors (addObservation validates with ArgumentError)
      } on ArgumentError {
        skipped++;
      }
    }
    // Only advance after the whole page parsed, so a failure retries the same window.
    _cursor = newest;
    return SyncResult(fetched: rows.length, added: added, skipped: skipped);
  }

  /// Starts polling every [every]; the first pass runs immediately.
  void start({Duration every = const Duration(seconds: 20)}) {
    Future<void> tick() async {
      try {
        final r = await syncOnce();
        if (r.added > 0 || r.skipped > 0) {
          // ignore: avoid_print
          print('observation sync: +${r.added} new, ${r.skipped} skipped, '
              '${r.fetched} fetched');
        }
      } on Object catch (e) {
        // ignore: avoid_print
        print('observation sync failed: ${e.runtimeType}');
      }
    }

    unawaited(tick());
    _timer = Timer.periodic(every, (_) => unawaited(tick()));
  }

  /// Stops polling and closes the HTTP client.
  void stop() {
    _timer?.cancel();
    _client.close();
  }
}
