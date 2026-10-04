/// Turns a traveller's report into an `HazardObservation`, sends it to the
/// ingest server, and keeps it in an on-device queue when offline.
///
/// Privacy (ADR-007, PLAN.md §12): the location is rounded to 4 decimal places
/// (about 10 m) before it leaves the screen, there is no free text and no
/// photo, and the only identifier is a random install code the user can reset.
///
/// Abuse (PLAN.md §12): a report's weight comes from its source class
/// (`crowd`, 0.6 reliability), and a crowd depth never removes a road on its
/// own (`RoutingEngine.depthMinReliability`).
///
/// This queue is a `shared_preferences` list so one implementation works on web
/// and mobile (PLAN.md M4.5). Delivery is idempotent: each report keeps its
/// UUID, and the server ignores a repeated id (G-Set, ADR-008), so a retry after
/// a lost response cannot double-count. The queue holds at most [maxQueued]
/// reports (the oldest are dropped first). The Drift/SQLite cache and HLC sync
/// client in `storage/` and `sync/` are tested but not used by the app: Drift
/// cannot compile to the web target.
library;

import 'dart:async';
import 'dart:convert';

import 'package:citypulse_app/src/core/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:pulse_router/pulse_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// What the traveller sees.
enum ReportKind {
  /// A flooded road.
  flooded,

  /// Standing water.
  standing,

  /// The water has gone.
  cleared,
}

/// The traveller's depth estimate.
enum DepthBand {
  /// Not sure; no depth is sent.
  unknown(null),

  /// About ankle deep.
  ankle(100),

  /// About knee deep.
  knee(450),

  /// Above the knee.
  above(600);

  const DepthBand(this.millimetres);

  /// An approximate depth in millimetres for the band. These are rough,
  /// user-chosen bands, not measurements.
  final double? millimetres;
}

/// A report before it is sent.
class ReportDraft {
  /// Creates a draft.
  const ReportDraft({
    required this.kind,
    required this.depth,
    required this.point,
  });

  /// What was seen.
  final ReportKind kind;

  /// Depth estimate (ignored for a "cleared" report).
  final DepthBand depth;

  /// Where, before rounding.
  final GeoPoint point;
}

/// The outcome of [ReportRepository.submit].
enum SubmitStatus {
  /// The server accepted it.
  sent,

  /// Saved on the device; will be retried.
  queued,

  /// The server refused it as invalid; it will not be retried.
  rejected,
}

double _round4(double v) => (v * 1e4).roundToDouble() / 1e4;

/// Builds, sends and queues reports.
class ReportRepository {
  /// Creates a repository.
  ReportRepository({
    required this.ingestUrl,
    required this.prefs,
    required this.installId,
    http.Client? client,
    DateTime Function()? clock,
    this.onAccepted,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  /// The FastAPI server root.
  final String ingestUrl;

  /// Where the queue is stored.
  final SharedPreferences prefs;

  /// Reads the current anonymous install code (so a reset takes effect).
  final String Function() installId;

  /// Called with each report as soon as it is accepted or queued, so the local
  /// engine can count it immediately (including offline).
  final void Function(EngineObservation observation)? onAccepted;

  /// Per-request timeout.
  final Duration timeout;

  final http.Client _client;
  final DateTime Function() _clock;

  static const _queueKey = 'reports.queue';

  /// Most reports kept while offline; beyond this the oldest are dropped, so
  /// a phone that stays offline for weeks does not grow its preferences file
  /// without bound.
  static const maxQueued = 100;

  /// Reports waiting to be sent.
  int get pendingCount => _queue().length;

  List<String> _queue() => prefs.getStringList(_queueKey) ?? const [];

  /// Builds the wire JSON (`docs/CONTRACTS.md` §1) for [draft].
  Map<String, Object?> toWire(ReportDraft draft) {
    final cleared = draft.kind == ReportKind.cleared;
    final hazardClass = draft.kind == ReportKind.standing
        ? 'waterlogging'
        : 'flood';
    final depth = cleared ? null : draft.depth.millimetres;
    return {
      'id': const Uuid().v7(),
      'hazard_class': hazardClass,
      'polarity': cleared ? -1 : 1,
      'geometry': {
        'type': 'Point',
        'coordinates': [_round4(draft.point.lon), _round4(draft.point.lat)],
      },
      'accuracy_m': 25,
      'observed_at': _clock().toIso8601String(),
      'source_class': 'crowd',
      'source_id': 'install:${installId()}',
      if (depth != null)
        'intensity': {'depth_mm': depth, 'estimated_by': 'user'},
    };
  }

  /// Sends [draft], or queues it if the server cannot be reached.
  Future<SubmitStatus> submit(ReportDraft draft) async {
    final wire = toWire(draft);
    final observation = EngineObservation.tryParseWire(wire);
    final status = await _post(wire);
    if (status == SubmitStatus.rejected) return status;
    if (observation != null) onAccepted?.call(observation);
    if (status == SubmitStatus.queued) {
      final queue = [..._queue(), jsonEncode(wire)];
      await prefs.setStringList(
        _queueKey,
        queue.length > maxQueued
            ? queue.sublist(queue.length - maxQueued)
            : queue,
      );
    }
    return status;
  }

  Future<SubmitStatus> _post(Map<String, Object?> wire) async {
    try {
      final r = await _client
          .post(
            AppConfig.join(ingestUrl, 'observations'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(wire),
          )
          .timeout(timeout);
      if (r.statusCode >= 200 && r.statusCode < 300) return SubmitStatus.sent;
      // 4xx: the server judged the report invalid; retrying cannot help.
      if (r.statusCode >= 400 && r.statusCode < 500) {
        return SubmitStatus.rejected;
      }
      return SubmitStatus.queued;
    } on TimeoutException {
      return SubmitStatus.queued;
    } on http.ClientException {
      return SubmitStatus.queued;
    }
  }

  /// Tries to send every queued report; returns how many were delivered.
  /// Reports the server rejects are dropped; unreachable ones stay queued.
  Future<int> flushQueue() async {
    final remaining = <String>[];
    var delivered = 0;
    for (final item in _queue()) {
      final Map<String, Object?> wire;
      try {
        wire = jsonDecode(item) as Map<String, Object?>;
      } on FormatException {
        continue;
      }
      switch (await _post(wire)) {
        case SubmitStatus.sent:
          delivered++;
        case SubmitStatus.rejected:
          break;
        case SubmitStatus.queued:
          remaining.add(item);
      }
    }
    await prefs.setStringList(_queueKey, remaining);
    return delivered;
  }

  /// Releases the HTTP client.
  void dispose() => _client.close();
}
