import 'package:drift/drift.dart';

/// Append-only hazard observation log -- a G-Set CRDT (ADR-008) whose
/// precision is decoupled from its permanence (ADR-010). Mirrors
/// `docs/CONTRACTS.md` §1's `HazardObservation` field for field.
///
/// **This table has deliberately no `UPDATE`/`DELETE` DAO path for `id`,
/// `polarity`, `hazardClass` or `observedAt`** -- those are the immutable
/// facts ADR-008's merge-conflict-free argument depends on. The only
/// legitimate mutation is the ADR-010 coarsening sweep
/// (`HazardDatabase.coarsenObservation`), which rewrites `lat`/`lon`,
/// `sourceId` (crowd/app_traversal only) and `precisionState`/`coarsenedAt`
/// in place. Enforcement here is structural: no other method in
/// `HazardDatabase` writes to an existing row.
@DataClassName('ObservationRow')
class Observations extends Table {
  /// UUIDv7, client-generated (`docs/CONTRACTS.md` §1 header note). A plain
  /// `TEXT PRIMARY KEY` -- note this means SQLite does *not* alias this
  /// column to the table's `rowid` (only an `INTEGER PRIMARY KEY` column
  /// does that), so `Observations` keeps its own separate implicit integer
  /// `rowid`. That separate `rowid` is exactly what pairs each row with its
  /// `observations_rtree` shadow row (`HazardDatabase`'s doc comment).
  TextColumn get id => text()();

  /// `flood | waterlogging | debris | accident | closure | heat | aqi`.
  TextColumn get hazardClass => text().named('hazard_class')();

  /// `+1` present, `-1` absent/cleared (`docs/CONTRACTS.md` §1).
  IntColumn get polarity => integer()();

  /// From `geometry: { type: "Point", coordinates: [lon, lat] }`.
  RealColumn get lat => real()();

  /// From `geometry: { type: "Point", coordinates: [lon, lat] }`.
  RealColumn get lon => real()();

  /// Report accuracy, in metres.
  RealColumn get accuracyM => real().named('accuracy_m')();

  /// When the hazard was observed -- decay runs on this, never [receivedAt].
  DateTimeColumn get observedAt => dateTime().named('observed_at')();

  /// When this device received/ingested the report -- latency analysis only.
  DateTimeColumn get receivedAt => dateTime().named('received_at')();

  /// `municipal_sensor | official_feed | verified_responder | crowd |
  /// app_traversal` -- maps to the reliability weight `α_c`.
  TextColumn get sourceClass => text().named('source_class')();

  /// The reporting device/feed/sensor id.
  TextColumn get sourceId => text().named('source_id')();

  /// `intensity` is class-specific and optional (`docs/CONTRACTS.md` §1) --
  /// stored as a JSON string rather than one column per possible shape.
  TextColumn get intensityJson => text().named('intensity_json').nullable()();

  /// The raw source payload, if retained -- same reasoning as
  /// [intensityJson].
  TextColumn get rawJson => text().named('raw_json').nullable()();

  /// `exact` | `coarsened` (ADR-010).
  TextColumn get precisionState =>
      text().named('precision_state').withDefault(const Constant('exact'))();

  /// When the ADR-010 coarsening sweep ran, if it has.
  DateTimeColumn get coarsenedAt =>
      dateTime().named('coarsened_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Locally-created reports pending sync to the server's `/observations`
/// endpoint (T5.4 -- sync itself is not built here, only this table and the
/// DAO methods a future sync task calls). One entry per `Observations.id`.
///
/// Unlike `Observations`, ordinary mutation is fine on this table: it only
/// tracks sync bookkeeping (has this been sent yet, how many attempts), never
/// the hazard fact itself, so ADR-008's append-only argument does not apply
/// here.
@DataClassName('OutboxEntryRow')
class OutboxEntries extends Table {
  /// References `Observations.id`. One outbox entry per observation, so this
  /// doubles as the outbox row's own primary key.
  TextColumn get observationId => text().named('observation_id')();

  /// When this outbox entry was created.
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();

  /// `null` while pending; set once the server has acknowledged receipt.
  DateTimeColumn get syncedAt => dateTime().named('synced_at').nullable()();

  /// How many sync attempts have been made so far.
  IntColumn get syncAttempts =>
      integer().named('sync_attempts').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {observationId};
}
