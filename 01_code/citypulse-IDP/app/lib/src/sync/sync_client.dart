/// The outbox <-> server sync client (T5.4, `docs/IMPLEMENTATION_PLAN.md`;
/// ADR-008's "written to a local outbox and replayed on reconnect with
/// `ON CONFLICT DO NOTHING`").
///
/// Two directions, both built on the existing T5.2 [HazardCache] surface and
/// the T5.3 server's `POST`/`GET /observations` (`server/app/routers/
/// observations.py`):
///
/// - [SyncClient.pushOutbox]: replays [HazardCache.pendingOutbox] against
///   `POST /observations`, one request per entry, marking each
///   [HazardCache.markOutboxSynced] only after a successful response. A
///   request that throws (timeout, connection refused, DNS failure -- any
///   simulated or real "connectivity died mid-report") leaves that entry
///   pending; the next call to [SyncClient.pushOutbox] retries it. Combined
///   with the server's G-Set dedup-on-`id` (ADR-008), a retried entry that
///   *did* actually arrive the first time (the response was lost, not the
///   request) is a no-op server-side, not a duplicate -- this is what makes
///   the whole path exactly-once rather than at-least-once with visible
///   duplicates.
/// - [SyncClient.pullSince]: fetches observations from
///   `GET /observations?since=...` and inserts each via
///   [HazardCache.insertObservation], which is already idempotent (T5.2) --
///   a re-pulled observation this device already has is a no-op, not a
///   duplicate row.
library;

import 'dart:convert';

import 'package:citypulse_app/src/storage/hazard_cache.dart';
import 'package:citypulse_app/src/sync/hlc.dart';
import 'package:http/http.dart' as http;

/// Raised by [SyncClient.pullSince] when the server returns a non-2xx
/// response. [SyncClient.pushOutbox] never throws this -- a failed push is
/// reported through [SyncStats.failedCount], not an exception, because one
/// bad entry must not abort the whole replay pass.
class SyncException implements Exception {
  /// Creates the exception with a human-readable [message].
  SyncException(this.message);

  /// Describes the failed request (status code and response body).
  final String message;

  @override
  String toString() => 'SyncException: $message';
}

/// The outcome of one [SyncClient.pushOutbox] pass.
class SyncStats {
  /// Creates the stats for one [SyncClient.pushOutbox] pass.
  const SyncStats({required this.pushedCount, required this.failedCount});

  /// How many pending outbox entries were POSTed successfully (2xx) and
  /// marked synced this pass.
  final int pushedCount;

  /// How many pending outbox entries failed this pass (network error or a
  /// non-2xx response) and remain pending for the next call.
  final int failedCount;
}

/// Syncs the local outbox with the server's `/observations` endpoint in
/// both directions. See this library's doc comment for the full
/// push/pull contract.
class SyncClient {
  /// Creates a sync client. [httpClient] defaults to a real
  /// `package:http` client; tests inject a fake/wrapping one to simulate
  /// network failures deterministically.
  SyncClient({
    required this.cache,
    required this.baseUri,
    required this.clock,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// The local hazard cache (T5.2) -- both the outbox source and the
  /// insert target for pulled observations.
  final HazardCache cache;

  /// The server's base URL, e.g. `https://citypulse.example/`. Resolved
  /// against `observations` (a relative reference, so `baseUri` must have a
  /// trailing `/` for [Uri.resolve] to append rather than replace the last
  /// path segment).
  final Uri baseUri;

  /// This device's HLC (ADR-008) -- [pushOutbox] stamps every outgoing
  /// report with [HybridLogicalClock.now].
  final HybridLogicalClock clock;

  final http.Client _http;

  Uri get _observationsUri => baseUri.resolve('observations');

  /// Replays every entry in [HazardCache.pendingOutbox] against
  /// `POST /observations`. See this library's doc comment for the
  /// exactly-once argument.
  Future<SyncStats> pushOutbox() async {
    final pending = await cache.pendingOutbox();
    var pushed = 0;
    var failed = 0;

    for (final entry in pending) {
      final obs = await cache.observationById(entry.observationId);
      if (obs == null) {
        // Should not happen -- Observations is append-only (ADR-008) and
        // enqueueOutbox is only ever called with an id already present
        // (HazardCache's own doc comment). Don't let one missing row crash
        // an entire sync pass; count it as a failure so it surfaces rather
        // than being silently swallowed.
        failed += 1;
        continue;
      }

      final stamp = clock.now();
      final body = jsonEncode(_toWireJson(obs, stamp));

      try {
        final response = await _http.post(
          _observationsUri,
          headers: const {'content-type': 'application/json'},
          body: body,
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          await cache.markOutboxSynced(obs.id);
          pushed += 1;
        } else {
          failed += 1;
        }
      } on Exception {
        // Network failure -- connection refused, timeout, DNS, TLS, a
        // dropped connection mid-request. Leave the entry pending; do not
        // call markOutboxSynced. This is the resume-after-failure guarantee
        // T5.4's acceptance test exercises directly.
        failed += 1;
      }
    }

    return SyncStats(pushedCount: pushed, failedCount: failed);
  }

  /// Fetches observations with `observed_at >= since` from the server and
  /// inserts each into the local cache via the existing idempotent
  /// [HazardCache.insertObservation]. Returns how many were genuinely new
  /// (already-known ids are silently skipped, per the G-Set property).
  ///
  /// Throws [SyncException] on a non-2xx response. Unlike [pushOutbox],
  /// there is no per-item pending state to preserve on failure -- a failed
  /// pull is simply retried wholesale (with the same `since`) by the
  /// caller, since pulling is naturally idempotent (re-inserting an
  /// already-known observation is a no-op).
  Future<int> pullSince(DateTime since) =>
      _pull({'since': since.toUtc().toIso8601String()});

  /// Like [pullSince] but pages by the server's arrival time (`received_at`),
  /// the cursor to use for incremental sync (KNOWN_FLAWS F-10): a report made
  /// offline at 09:00 and uploaded at 11:00 has `observed_at` 09:00 but
  /// `received_at` 11:00, so an `observed_at` cursor that already passed 09:00
  /// would never fetch it. Keep the largest `receivedAt` you have stored and
  /// pass it here; re-fetching the boundary row is harmless (G-Set).
  Future<int> pullReceivedSince(DateTime receivedSince) =>
      _pull({'received_since': receivedSince.toUtc().toIso8601String()});

  Future<int> _pull(Map<String, String> query) async {
    final uri = _observationsUri.replace(queryParameters: query);
    final response = await _http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncException(
        'GET /observations failed with ${response.statusCode}: '
        '${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    var inserted = 0;
    for (final item in decoded) {
      final record = _fromWireJson(item as Map<String, dynamic>);
      final wasNew = await cache.insertObservation(record);
      if (wasNew) {
        inserted += 1;
      }
    }
    return inserted;
  }

  /// Releases the underlying HTTP client's resources.
  void close() => _http.close();
}

/// The `raw` key an outgoing [HlcTimestamp] is embedded under.
///
/// **Design note (judgement call, flagged per CLAUDE.md):** ADR-008 asks for
/// HLC stamps on synced reports, but `docs/CONTRACTS.md` §1's
/// `HazardObservation` has no dedicated field for one, and the server's
/// Pydantic model (`server/app/models.py`) sets `extra="forbid"` -- posting
/// an unrecognised top-level field is rejected with 422, not silently
/// accepted. Adding a real `hlc` field to the shared contract is a schema
/// change CONTRACTS.md's own preamble says to make "only by ADR", which is
/// out of this task's "wiring, not rearchitecting" scope. `raw` is exactly
/// the field CONTRACTS.md §1 documents as a free-form payload area, so the
/// stamp is nested there instead: `raw['_hlc']` is the stamp's [HlcTimestamp.
/// encode] string. This is additive and non-destructive of any existing
/// `raw` content, and reversible without a migration if a dedicated field is
/// added later.
const String _hlcRawKey = '_hlc';

Map<String, dynamic> _toWireJson(
  HazardObservationRecord obs,
  HlcTimestamp stamp,
) {
  final raw = <String, dynamic>{...?obs.raw, _hlcRawKey: stamp.encode()};

  final json = <String, dynamic>{
    'id': obs.id,
    'hazard_class': obs.hazardClass,
    'polarity': obs.polarity,
    'geometry': {
      'type': 'Point',
      'coordinates': [obs.lon, obs.lat],
    },
    'accuracy_m': obs.accuracyM,
    'observed_at': obs.observedAt.toUtc().toIso8601String(),
    'received_at': obs.receivedAt.toUtc().toIso8601String(),
    'source_class': obs.sourceClass,
    'source_id': obs.sourceId,
    'intensity': obs.intensity,
    'raw': raw,
    'precision_state': obs.precisionState.value,
  };
  if (obs.coarsenedAt != null) {
    json['coarsened_at'] = obs.coarsenedAt!.toUtc().toIso8601String();
  }
  return json;
}

HazardObservationRecord _fromWireJson(Map<String, dynamic> json) {
  final geometry = json['geometry'] as Map<String, dynamic>;
  final coordinates = geometry['coordinates'] as List<dynamic>;
  final lon = (coordinates[0] as num).toDouble();
  final lat = (coordinates[1] as num).toDouble();

  final precisionStateStr = json['precision_state'] as String? ?? 'exact';
  final coarsenedAtStr = json['coarsened_at'] as String?;

  return HazardObservationRecord(
    id: json['id'] as String,
    hazardClass: json['hazard_class'] as String,
    polarity: json['polarity'] as int,
    lat: lat,
    lon: lon,
    accuracyM: (json['accuracy_m'] as num).toDouble(),
    observedAt: DateTime.parse(json['observed_at'] as String).toUtc(),
    receivedAt: DateTime.parse(json['received_at'] as String).toUtc(),
    sourceClass: json['source_class'] as String,
    sourceId: json['source_id'] as String,
    intensity: json['intensity'] as Map<String, dynamic>?,
    raw: json['raw'] as Map<String, dynamic>?,
    precisionState: PrecisionState.fromValue(precisionStateStr),
    coarsenedAt: coarsenedAtStr == null
        ? null
        : DateTime.parse(coarsenedAtStr).toUtc(),
  );
}
