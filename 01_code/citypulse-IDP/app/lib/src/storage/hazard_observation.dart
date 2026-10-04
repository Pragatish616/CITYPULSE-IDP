import 'package:flutter/foundation.dart' show immutable;

/// `precision_state` (`docs/CONTRACTS.md` §1, ADR-010). Every observation
/// starts [exact]; the coarsening sweep (`HazardDatabase.coarsenObservation`)
/// is the only thing that ever moves a record to [coarsened].
enum PrecisionState {
  /// Geometry and `source_id` are as originally reported.
  exact,

  /// Geometry has been snapped to a ~150 m grid cell and (for `crowd`/
  /// `app_traversal` sources) `source_id` replaced with a non-reversible
  /// bucket id, per the ADR-010 sweep.
  coarsened;

  /// The exact string this enum is stored/serialised as -- matches the
  /// contract's own `"exact" | "coarsened"` literal values.
  String get value => name;

  /// Parses the contract's `"exact" | "coarsened"` literal back into a
  /// [PrecisionState]. Throws [ArgumentError] for anything else.
  static PrecisionState fromValue(String value) => switch (value) {
    'exact' => PrecisionState.exact,
    'coarsened' => PrecisionState.coarsened,
    _ => throw ArgumentError.value(
      value,
      'value',
      'must be "exact" or "coarsened"',
    ),
  };
}

/// A plain, storage-agnostic mirror of `docs/CONTRACTS.md` §1's
/// `HazardObservation` -- the append-only unit ADR-008 describes as a G-Set
/// CRDT. Nothing in `packages/pulse_belief` or `packages/pulse_router` models
/// the *full* observation shape (`pulse_belief`'s `WeightedObservation` is
/// deliberately narrower -- see that file's doc comment: geometry and I/O
/// stay outside that pure-function package), so this is the first place in
/// the codebase that does.
///
/// This class is intentionally decoupled from Drift's generated row class
/// (`ObservationRow`, `hazard_database.g.dart`) so callers of
/// `HazardCache`/`HazardDatabase` never need to import generated code or
/// know it exists.
@immutable
class HazardObservationRecord {
  /// Creates a [HazardObservationRecord]. Throws (via `assert`, so only in
  /// debug/test builds -- this class is constructed exclusively from
  /// already-validated in-app data, never directly from untrusted network
  /// input, unlike `pulse_belief`'s `WeightedObservation`) if [polarity] is
  /// not `+1` or `-1`.
  const HazardObservationRecord({
    required this.id,
    required this.hazardClass,
    required this.polarity,
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.observedAt,
    required this.receivedAt,
    required this.sourceClass,
    required this.sourceId,
    this.intensity,
    this.raw,
    this.precisionState = PrecisionState.exact,
    this.coarsenedAt,
  }) : assert(
         polarity == 1 || polarity == -1,
         'polarity must be +1 (present) or -1 (absent/cleared)',
       );

  /// UUIDv7, client-generated (`docs/CONTRACTS.md` §1 header note).
  final String id;

  /// `flood | waterlogging | debris | accident | closure | heat | aqi`.
  final String hazardClass;

  /// `+1` hazard present, `-1` hazard absent/cleared. Negative observations
  /// are first-class evidence (`docs/CONTRACTS.md` §1, improvement I-02).
  final int polarity;

  /// From `geometry: { type: "Point", coordinates: [lon, lat] }`.
  final double lat;

  /// From `geometry: { type: "Point", coordinates: [lon, lat] }`.
  final double lon;

  /// Report accuracy, in metres.
  final double accuracyM;

  /// When the hazard was observed -- decay runs on this, never [receivedAt].
  final DateTime observedAt;

  /// When this device received/ingested the report -- latency analysis only.
  final DateTime receivedAt;

  /// `municipal_sensor | official_feed | verified_responder | crowd |
  /// app_traversal` -- maps to the reliability weight `α_c`.
  final String sourceClass;

  /// The reporting device/feed/sensor id.
  final String sourceId;

  /// Class-specific and optional (`docs/CONTRACTS.md` §1) -- e.g.
  /// `{"depth_mm": 320}` for flooding. Stored as JSON rather than one column
  /// per possible shape.
  final Map<String, dynamic>? intensity;

  /// The raw source payload, if retained. Same reasoning as [intensity].
  final Map<String, dynamic>? raw;

  /// `exact` | `coarsened` (ADR-010).
  final PrecisionState precisionState;

  /// When the ADR-010 coarsening sweep ran, if it has. `null` while
  /// [precisionState] is [PrecisionState.exact].
  final DateTime? coarsenedAt;

  /// Returns a copy with the given fields replaced -- the only fields ever
  /// legitimately rewritten (by the ADR-010 coarsening sweep). Everything
  /// else on a [HazardObservationRecord] is permanent, per ADR-008.
  HazardObservationRecord copyWith({
    double? lat,
    double? lon,
    String? sourceId,
    PrecisionState? precisionState,
    DateTime? coarsenedAt,
  }) {
    return HazardObservationRecord(
      id: id,
      hazardClass: hazardClass,
      polarity: polarity,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      accuracyM: accuracyM,
      observedAt: observedAt,
      receivedAt: receivedAt,
      sourceClass: sourceClass,
      sourceId: sourceId ?? this.sourceId,
      intensity: intensity,
      raw: raw,
      precisionState: precisionState ?? this.precisionState,
      coarsenedAt: coarsenedAt ?? this.coarsenedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HazardObservationRecord &&
          other.id == id &&
          other.hazardClass == hazardClass &&
          other.polarity == polarity &&
          other.lat == lat &&
          other.lon == lon &&
          other.accuracyM == accuracyM &&
          other.observedAt == observedAt &&
          other.receivedAt == receivedAt &&
          other.sourceClass == sourceClass &&
          other.sourceId == sourceId &&
          _mapEquals(other.intensity, intensity) &&
          _mapEquals(other.raw, raw) &&
          other.precisionState == precisionState &&
          other.coarsenedAt == coarsenedAt);

  @override
  int get hashCode => Object.hash(
    id,
    hazardClass,
    polarity,
    lat,
    lon,
    accuracyM,
    observedAt,
    receivedAt,
    sourceClass,
    sourceId,
    precisionState,
    coarsenedAt,
  );

  @override
  String toString() =>
      'HazardObservationRecord(id: $id, hazardClass: $hazardClass, '
      'polarity: $polarity, lat: $lat, lon: $lon, '
      'precisionState: ${precisionState.value})';
}

bool _mapEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
  if (a == null || b == null) {
    return a == b;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
