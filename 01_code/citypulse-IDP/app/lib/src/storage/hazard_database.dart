import 'dart:convert';
import 'dart:io';

import 'package:citypulse_app/src/storage/hazard_observation.dart';
import 'package:citypulse_app/src/storage/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

part 'hazard_database.g.dart';

/// ~150 m in degrees of latitude (1 deg lat ~= 111,320 m). Used for both
/// axes -- see [HazardDatabase.coarsenObservation]'s doc comment for why
/// that is a deliberate simplification, not a bug.
const double _kCoarseGridDeg = 150 / 111320;

/// The local, on-device hazard cache (T5.2, `docs/IMPLEMENTATION_PLAN.md`;
/// `docs/ARCHITECTURE.md` app/ section: "SQLite via Drift with the built-in
/// R*Tree module ... not SpatiaLite, not Isar").
///
/// Pairs two Drift-managed tables (`Observations`, `OutboxEntries`,
/// `tables.dart`) with a hand-written SQLite R*Tree virtual table
/// (`observations_rtree`), because Drift has no typed Dart-table API for the
/// `rtree` module (unlike its `Fts5Table` mixin for FTS5 -- inventing one
/// here would not be verifiable against Drift's actual public API). This is
/// exactly the "hand-write the R*Tree table and sync a shadow row per
/// insert" option the T5.2 task card names as acceptable.
///
/// The pairing follows SQLite's own documented rtree-plus-content-table
/// pattern (sqlite.org/rtree.html, "Using R-Trees"): the rtree's aliased
/// `id` column is kept equal to `Observations`'s own implicit SQLite
/// `rowid` -- *not* the text `id` primary key. A `TEXT PRIMARY KEY` column
/// does not become the rowid alias (only `INTEGER PRIMARY KEY` does), so
/// `Observations` keeps a separate, ordinary implicit rowid that is exactly
/// the join key `observationsInBbox` uses.
@DriftDatabase(tables: [Observations, OutboxEntries])
class HazardDatabase extends _$HazardDatabase {
  /// Wraps an already-created [QueryExecutor] -- tests pass
  /// `NativeDatabase.memory()` directly; production code should use
  /// [HazardDatabase.open] instead.
  HazardDatabase(super.executor);

  /// Production entry point: a file-backed database under the platform's
  /// application-support directory, following Drift's own documented
  /// Flutter setup (drift.simonbinder.eu, "Platforms" > "Flutter/Dart").
  /// Not exercised by this task's tests, which use
  /// `HazardDatabase(NativeDatabase.memory())` directly -- wiring this into
  /// the running app is the T5.2 -> route_service/UI integration follow-up
  /// the task card explicitly defers.
  factory HazardDatabase.open() => HazardDatabase(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await customStatement(
        'CREATE VIRTUAL TABLE observations_rtree '
        'USING rtree(id, minLat, maxLat, minLon, maxLon)',
      );
    },
  );

  /// Inserts [obs]. **A no-op if `obs.id` already exists** -- the G-Set CRDT
  /// property (ADR-008) that makes replayed/re-synced inserts idempotent,
  /// implemented as `INSERT OR IGNORE` (via
  /// [InsertStatement.insertReturningOrNull], which returns `null` exactly
  /// when the conflict clause suppressed the insert -- the documented way
  /// to distinguish "no-op" from "inserted" under `InsertMode.insertOrIgnore`
  /// without relying on `last_insert_rowid()`, which SQLite does not update
  /// on a suppressed insert).
  ///
  /// Returns `true` if a new row was written, `false` for the no-op case.
  Future<bool> insertObservation(HazardObservationRecord obs) {
    return transaction(() async {
      final inserted = await into(observations).insertReturningOrNull(
        _companionFrom(obs),
        mode: InsertMode.insertOrIgnore,
      );
      if (inserted == null) {
        return false;
      }
      final rowId = await _rowIdFor(obs.id);
      await customStatement(
        'INSERT INTO observations_rtree(id, minLat, maxLat, minLon, maxLon) '
        'VALUES (?, ?, ?, ?, ?)',
        [rowId, obs.lat, obs.lat, obs.lon, obs.lon],
      );
      return true;
    });
  }

  /// Observations whose point falls within
  /// `[minLat, maxLat] x [minLon, maxLon]`, optionally restricted to
  /// `observedAt >= since`.
  ///
  /// The bbox predicate runs first, against `observations_rtree`, joined
  /// back to `observations` on `rowid` -- this is the query that actually
  /// uses the R*Tree index (verify with `EXPLAIN QUERY PLAN` -- see
  /// `test/storage/hazard_cache_test.dart`). `since`, and the full typed row
  /// data, come from a second, ordinary typed Drift query restricted to the
  /// ids the first query found.
  Future<List<HazardObservationRecord>> observationsInBbox({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    DateTime? since,
  }) async {
    final matches = await customSelect(
      'SELECT o.id AS obs_id '
      'FROM observations_rtree AS r '
      'JOIN observations AS o ON o.rowid = r.id '
      'WHERE r.minLat <= ? AND r.maxLat >= ? '
      'AND r.minLon <= ? AND r.maxLon >= ?',
      variables: [
        Variable.withReal(maxLat),
        Variable.withReal(minLat),
        Variable.withReal(maxLon),
        Variable.withReal(minLon),
      ],
      readsFrom: {observations},
    ).get();

    final ids = matches.map((row) => row.read<String>('obs_id')).toList();
    if (ids.isEmpty) {
      return const [];
    }

    final query = select(observations)..where((o) => o.id.isIn(ids));
    if (since != null) {
      query.where((o) => o.observedAt.isBiggerOrEqualValue(since));
    }
    final rows = await query.get();
    return rows.map(_recordFrom).toList();
  }

  /// Fetches a single observation by its id, or `null` if it does not exist.
  ///
  /// **Addition beyond T5.2's original surface**, made by T5.4 (sync): the
  /// outbox (`OutboxEntries`) stores only `observationId`, so replaying it
  /// (`SyncClient.pushOutbox`) needs a way to load the full
  /// [HazardObservationRecord] to serialise onto the wire.
  /// `observationsInBbox` cannot serve this -- it requires a bounding box,
  /// and a locally-created report's own coordinates are exactly the point,
  /// not a box to search. Kept intentionally symmetrical with
  /// [insertObservation]/[coarsenObservation]'s existing id-keyed style
  /// rather than inventing a new query shape.
  Future<HazardObservationRecord?> observationById(String id) async {
    final row = await (select(
      observations,
    )..where((o) => o.id.equals(id))).getSingleOrNull();
    return row == null ? null : _recordFrom(row);
  }

  /// The ADR-010 coarsening sweep's one legitimate mutation of an existing
  /// observation: rewrites `lat`/`lon` to a ~150 m grid cell, replaces
  /// `sourceId` with a non-reversible bucket id for `source_class: crowd`
  /// and `app_traversal` reports only, and sets `precisionState` to
  /// `coarsened` with `coarsenedAt`. Leaves `id`, `polarity`, `hazardClass`
  /// and `observedAt` untouched, per ADR-010's own text: "a further
  /// mutation-in-place of an existing fact, not a retraction of it."
  ///
  /// A no-op if [id] does not exist.
  Future<void> coarsenObservation(String id, {DateTime? coarsenedAt}) async {
    final existing = await (select(
      observations,
    )..where((o) => o.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      return;
    }

    final coarsenedLat = _snapToGrid(existing.lat);
    final coarsenedLon = _snapToGrid(existing.lon);
    final rehashSource =
        existing.sourceClass == 'crowd' ||
        existing.sourceClass == 'app_traversal';
    final newSourceId = rehashSource
        ? _bucketId(existing.sourceId)
        : existing.sourceId;
    final at = coarsenedAt ?? DateTime.now().toUtc();

    await transaction(() async {
      await (update(observations)..where((o) => o.id.equals(id))).write(
        ObservationsCompanion(
          lat: Value(coarsenedLat),
          lon: Value(coarsenedLon),
          sourceId: Value(newSourceId),
          precisionState: Value(PrecisionState.coarsened.value),
          coarsenedAt: Value(at),
        ),
      );
      final rowId = await _rowIdFor(id);
      await customStatement(
        'UPDATE observations_rtree '
        'SET minLat = ?, maxLat = ?, minLon = ?, maxLon = ? '
        'WHERE id = ?',
        [coarsenedLat, coarsenedLat, coarsenedLon, coarsenedLon, rowId],
      );
    });
  }

  /// Records that [observationId] (an id already present in `Observations`)
  /// has a locally-created report pending sync. A no-op if already enqueued.
  Future<void> enqueueOutbox(String observationId) {
    return into(outboxEntries).insert(
      OutboxEntriesCompanion.insert(observationId: observationId),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Outbox entries not yet acknowledged by the server -- what a future
  /// T5.4 sync task replays.
  Future<List<OutboxEntryRow>> pendingOutbox() {
    return (select(outboxEntries)..where((o) => o.syncedAt.isNull())).get();
  }

  /// Marks [observationId]'s outbox entry as synced. A no-op if it does not
  /// exist (already synced-and-swept, or never enqueued).
  Future<void> markOutboxSynced(String observationId) {
    return (update(outboxEntries)
          ..where((o) => o.observationId.equals(observationId)))
        .write(OutboxEntriesCompanion(syncedAt: Value(DateTime.now().toUtc())));
  }

  Future<int> _rowIdFor(String id) async {
    final row = await customSelect(
      'SELECT rowid AS row_id FROM observations WHERE id = ?',
      variables: [Variable.withString(id)],
      readsFrom: {observations},
    ).getSingle();
    return row.read<int>('row_id');
  }
}

ObservationsCompanion _companionFrom(HazardObservationRecord obs) {
  return ObservationsCompanion.insert(
    id: obs.id,
    hazardClass: obs.hazardClass,
    polarity: obs.polarity,
    lat: obs.lat,
    lon: obs.lon,
    accuracyM: obs.accuracyM,
    observedAt: obs.observedAt,
    receivedAt: obs.receivedAt,
    sourceClass: obs.sourceClass,
    sourceId: obs.sourceId,
    intensityJson: Value(
      obs.intensity == null ? null : jsonEncode(obs.intensity),
    ),
    rawJson: Value(obs.raw == null ? null : jsonEncode(obs.raw)),
    precisionState: Value(obs.precisionState.value),
    coarsenedAt: Value(obs.coarsenedAt),
  );
}

HazardObservationRecord _recordFrom(ObservationRow row) {
  // `docs/CONTRACTS.md` header: "All timestamps are RFC 3339 UTC." Drift's
  // default unix-epoch DateTime storage round-trips the correct instant but
  // reads it back tagged `isUtc: false` (local) -- and Dart's `DateTime==`
  // requires matching zone tags, not just the same instant (see
  // `DateTime.operator==`'s own doc comment). `.toUtc()` here is what keeps
  // every `HazardObservationRecord` this layer hands out actually equal to
  // what was inserted, per the contract's own UTC requirement.
  return HazardObservationRecord(
    id: row.id,
    hazardClass: row.hazardClass,
    polarity: row.polarity,
    lat: row.lat,
    lon: row.lon,
    accuracyM: row.accuracyM,
    observedAt: row.observedAt.toUtc(),
    receivedAt: row.receivedAt.toUtc(),
    sourceClass: row.sourceClass,
    sourceId: row.sourceId,
    intensity: row.intensityJson == null
        ? null
        : jsonDecode(row.intensityJson!) as Map<String, dynamic>,
    raw: row.rawJson == null
        ? null
        : jsonDecode(row.rawJson!) as Map<String, dynamic>,
    precisionState: PrecisionState.fromValue(row.precisionState),
    coarsenedAt: row.coarsenedAt?.toUtc(),
  );
}

/// Snaps a coordinate to a fixed-size grid of ~150 m cells
/// (`_kCoarseGridDeg`), per ADR-010. **Deliberate simplification, flagged
/// per `CLAUDE.md` §8.4 rather than silently assumed correct:** this applies
/// the same degree-sized cell to both latitude and longitude. A true 150 m
/// *longitude* cell narrows towards the poles (it should be
/// `150 / (111320 * cos(latitude))` degrees), so at Chennai's latitude
/// (~13 deg N, cos ~= 0.974) the actual east-west cell width this produces is
/// ~146 m, not 150 m -- within a few percent, and ADR-010's own privacy
/// rationale ("what DPDP cares about" is the radius, not exact metres) does
/// not require closer precision than that, but a global deployment at higher
/// latitudes would need the cosine correction.
double _snapToGrid(double value) =>
    (value / _kCoarseGridDeg).round() * _kCoarseGridDeg;

/// A non-reversible bucket id for a coarsened `crowd`/`app_traversal`
/// `sourceId` (ADR-010). Deliberately a plain, unsalted FNV-1a 64-bit hash,
/// not a cryptographic one -- flagged as a judgement call: this is
/// sufficient to make the *stored* value non-reversible without brute
/// force, per ADR-010's wording, but a real deployment handling reports
/// tied to real user accounts should use a salted HMAC instead so that two
/// coarsened reports from the same device cannot be correlated by hashing
/// candidate source ids and comparing. Not adding the `crypto` package
/// dependency for that here keeps this task's surface area to what T5.2
/// asked for.
String _bucketId(String sourceId) {
  // This 64-bit constant isn't exactly representable as a JS double, but
  // this app is Android-only (`pubspec.yaml`'s own description) and never
  // compiles to JS -- see `avoid_js_rounded_ints`'s own rationale.
  // ignore: avoid_js_rounded_ints
  const fnvOffset = 0xcbf29ce484222325;
  // Same reasoning as fnvOffset above -- Android-only, never compiled to JS.
  // ignore: avoid_js_rounded_ints
  const fnvPrime = 0x100000001b3;
  var hash = fnvOffset;
  for (final byte in utf8.encode(sourceId)) {
    hash ^= byte;
    hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
  }
  return 'bucket_${hash.toRadixString(16).padLeft(16, '0')}';
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'hazard_cache.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
