import 'package:citypulse_app/src/storage/hazard_database.dart';
import 'package:citypulse_app/src/storage/hazard_observation.dart';

export 'package:citypulse_app/src/storage/hazard_database.dart'
    show HazardDatabase, OutboxEntryRow;
export 'package:citypulse_app/src/storage/hazard_observation.dart'
    show HazardObservationRecord, PrecisionState;

/// Clean public surface over [HazardDatabase] for callers outside
/// `lib/src/storage/` (T5.2, `docs/IMPLEMENTATION_PLAN.md`).
///
/// [HazardDatabase] already carries the real logic -- the R*Tree pairing and
/// the ADR-008 (append-only)/ADR-010 (coarsening) rules -- so this wrapper
/// is deliberately thin. It exists so call sites (the T5.2 -> route_service
/// integration this task defers, and the T5.4 sync task) depend on a small,
/// named surface instead of the generated Drift database class directly.
class HazardCache {
  /// Wraps an already-opened [HazardDatabase]. For production use, open one
  /// with `HazardDatabase.open()`; tests construct
  /// `HazardDatabase(NativeDatabase.memory())` directly.
  HazardCache(this._db);

  final HazardDatabase _db;

  /// Inserts [obs]. A no-op (per the G-Set CRDT property, ADR-008) if
  /// `obs.id` already exists. Returns `true` if a new row was written.
  Future<bool> insertObservation(HazardObservationRecord obs) =>
      _db.insertObservation(obs);

  /// Observations within the given bounding box, optionally restricted to
  /// `observedAt >= since`. Backed by the R*Tree index -- see
  /// [HazardDatabase.observationsInBbox].
  Future<List<HazardObservationRecord>> observationsInBbox({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    DateTime? since,
  }) => _db.observationsInBbox(
    minLat: minLat,
    minLon: minLon,
    maxLat: maxLat,
    maxLon: maxLon,
    since: since,
  );

  /// Fetches a single observation by id, or `null` if it does not exist.
  /// Added for T5.4 (sync) -- see [HazardDatabase.observationById].
  Future<HazardObservationRecord?> observationById(String id) =>
      _db.observationById(id);

  /// The ADR-010 coarsening sweep's one legitimate mutation of an existing
  /// observation. See [HazardDatabase.coarsenObservation].
  Future<void> coarsenObservation(String id, {DateTime? coarsenedAt}) =>
      _db.coarsenObservation(id, coarsenedAt: coarsenedAt);

  /// Marks [observationId] as a locally-created report pending sync (T5.4).
  Future<void> enqueueOutbox(String observationId) =>
      _db.enqueueOutbox(observationId);

  /// Outbox entries not yet acknowledged by the server.
  Future<List<OutboxEntryRow>> pendingOutbox() => _db.pendingOutbox();

  /// Marks [observationId]'s outbox entry as synced.
  Future<void> markOutboxSynced(String observationId) =>
      _db.markOutboxSynced(observationId);

  /// Closes the underlying database connection.
  Future<void> close() => _db.close();
}
