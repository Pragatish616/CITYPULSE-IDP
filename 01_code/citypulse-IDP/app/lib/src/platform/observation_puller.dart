/// Pulls reports from the ingest server for the on-device engine, fetching
/// only what arrived since the last pull.
///
/// The cursor is the newest server `received_at` seen (KNOWN_FLAWS F-10): it
/// pages on arrival time, so a report made offline hours ago and uploaded now
/// is not skipped. It lives in memory on purpose. The engine's reports are
/// held in memory too, so after an app restart the engine is empty and the
/// first pull must fetch everything again; a cursor saved to disk would skip
/// reports the new engine has never seen.
library;

import 'dart:async';
import 'dart:convert';

import 'package:citypulse_app/src/core/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:pulse_router/pulse_router.dart';

/// Incremental report pulls.
class ObservationPuller {
  /// Creates a puller for the server at [ingestUrl].
  ObservationPuller({
    required this.ingestUrl,
    required http.Client client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client;

  /// FastAPI server root.
  final String ingestUrl;

  /// Per-request timeout.
  final Duration timeout;

  final http.Client _client;
  DateTime? _cursor;

  /// The newest `received_at` seen so far, or `null` before the first pull.
  DateTime? get cursor => _cursor;

  /// Fetches new reports. Returns an empty list on any server error; throws
  /// on network failure or timeout so the caller can treat it as offline.
  Future<List<EngineObservation>> pull() async {
    final base = AppConfig.join(ingestUrl, 'observations');
    final cursor = _cursor;
    final uri = cursor == null
        ? base
        : base.replace(
            queryParameters: {
              'received_since': cursor.toUtc().toIso8601String(),
            },
          );
    final r = await _client.get(uri).timeout(timeout);
    if (r.statusCode != 200) return const [];
    final rows = jsonDecode(r.body) as List<Object?>;
    var newest = cursor;
    final out = <EngineObservation>[];
    for (final raw in rows) {
      if (raw is Map) {
        final received = DateTime.tryParse('${raw['received_at']}');
        if (received != null && (newest == null || received.isAfter(newest))) {
          newest = received;
        }
      }
      if (EngineObservation.tryParseWire(raw) case final o?) out.add(o);
    }
    // Advance only after the whole page parsed, so a failure retries it.
    _cursor = newest;
    return out;
  }
}
